local LINE_LENGTH = 256

local assert = assert

local setmetatable = setmetatable

-- localize table iterators
local ipairs = ipairs

local math = math
local vector = vector

local new_vec = vector.new
local p = new_vec
local normalize = vector.normalize
local round = vector.round

---@type LuantiCore
local core = core

local registered_nodes = core.registered_nodes

local set_node = core.set_node
local get_node = core.get_node
local get_node_or_nil = core.get_node_or_nil
local sound_play = core.sound_play
local get_connected_players = core.get_connected_players

---@type VeinMinerGlobal
local vein_miner = vein_miner
local h = vein_miner.h

local is_passable = h.is_passable
local is_node_supporting = h.is_node_supporting

local up = new_vec(0, 1, 0)
local down = new_vec(0, -1, 0)

local player_config_mgr = vein_miner.player_config_mgr
assert(player_config_mgr, "need vein_miner.player_config_mgr")

---@class FloorFiller
local floor_filler = {}

local placeable_nodes_to_skip = h.make_set({"default:jungletree", "digtron:light"}, true)

local support_dirs = vein_miner.CFG.SUPPORT_DIRS
local vertical_offsets = vein_miner.CFG.VERTICAL_OFFSETS

local sound_info_per_player = {}

---@param player Player
---@param playing_sounds table<string, boolean>
---@param target_pos Vector
---@param max_hear_distance number
local function try_place_block_from_inventory(player, playing_sounds, target_pos, max_hear_distance)
	local inv = player:get_inventory()
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		local name = stack:get_name()
		local def = registered_nodes[name]
		if not placeable_nodes_to_skip[name] and def and name ~= "air" and not def.groups.falling_node then
			local cur_node = core.get_node(target_pos)
			if cur_node and cur_node.name ~= "air" then
				if cur_node.name == "ignore" then
					return false
				end
				local def2 = registered_nodes[cur_node.name]
				if def2.liquidtype == "source" then
					return false
				end
				if def2.walkable then
					return false
				end
				core.node_dig(target_pos, cur_node, player)
			end
			set_node(target_pos, {
				name = name,
			})
			stack:take_item(1)
			inv:set_stack("main", i, stack)
			if not playing_sounds[def.sounds.place] then
				sound_play(def.sounds.place, {
					pos = target_pos,
					max_hear_distance = max_hear_distance,
				})
				playing_sounds[def.sounds.place] = true
			end
			return true
		end
	end
	return false
end

-- Precompute neighbor offsets for support checks
---@type Vector[]
local neighbor_offsets = {}
for _, dir in ipairs(support_dirs) do
	for _, vert in ipairs(vertical_offsets) do
		local offset = dir + vert
		if offset ~= vector.zero() then
			if table.contains(neighbor_offsets, offset) then
				core.log("error", "duplicate offset " .. core.pos_to_string(offset))
			end
			table.insert(neighbor_offsets, offset)
		end
	end
end

---@param pos Vector
local function is_supported(pos, invalid_support_name)
	for _, offset in ipairs(neighbor_offsets) do
		local node = get_node_or_nil(pos + offset)
		if not node then
			return false
		end
		if is_node_supporting(node, invalid_support_name) then
			return true
		end
	end
	local function check_axis(dx, dz)
		local node1 = get_node_or_nil(pos + new_vec(dx, 0, dz))
		local node2 = get_node_or_nil(pos + new_vec(-dx, 0, -dz))
		return is_node_supporting(node1, invalid_support_name) and is_node_supporting(node2, invalid_support_name)
	end
	if check_axis(1, 0) or check_axis(0, 1) then
		return true
	end
	return false
end

---@class FloorScanState
---@field playing_sounds table<string, boolean>
--- player yaw vars
---@field player_start_yaw number|nil
---@field last_yaw number|nil
--- min and max display
---@field log_min number|nil
---@field log_max number|nil
---@field min_dist number|nil
---@field max_dist number|nil
---@field blocks_this_tick integer Number of blocks placed this tick
local FloorScanState = {
	-- player yaw constants
	target_rad = math.rad(360),
}

---@param self FloorScanState
function FloorScanState:reset()
	self.active = false
	self.count = 0
	self.player_start_yaw = nil
	self.scan_radians = 0
	self.req_next_reset_scan_radians = 0
	self.yaw_update_disabled = false
	self.last_yaw = nil
	self.show_log = false
	self.log_min = nil
	self.log_max = nil
	self.min_dist = nil
	self.max_dist = nil
	self.last_pos = vector.new(0, -1, 0)
	self.blocks_placed = 0
	self.all_blocks_placed = 0
	self.blocks_this_tick = 0
end

---@param self FloorScanState
---@param pos Vector
function FloorScanState:leave_floor_scan(pos) end

local block_dist_fmt = "place range at %.1f° min %s max %s, size %s"

local function log_block_distance(v) core.log("action", block_dist_fmt:format(v.deg, v.min, v.max, v.size)) end

---@param rad number
local function rad_to_deg_wrap360(rad)
	local deg = math.deg(rad) % 360
	if deg < 0 then
		deg = deg + 360
	end
	return deg
end
--- Update the minimum placement distance and maybe schedule a log
---@param self FloorScanState
---@param dist number
function FloorScanState:_update_min_dist(dist)
	if not self.min_dist or dist < self.min_dist then
		if self.log_min ~= dist then
			self.log_min = dist
			self.show_log = true
		end
		self.min_dist = dist
	end
end

--- Update the maximum placement distance and maybe schedule a log
---@param self FloorScanState
---@param dist number
function FloorScanState:_update_max_dist(dist)
	if not self.max_dist or dist > self.max_dist then
		if self.log_max ~= dist then
			self.log_max = dist
			self.show_log = true
		end
		self.max_dist = dist
	end
end

--- Log the current min/max block distance if needed
---@param self FloorScanState
function FloorScanState:_maybe_log_block_distance()
	local cur_pos = vector.new(self.log_min / 8, self.log_max / 8, 0):floor()

	-- Only log if the position changed
	if cur_pos ~= self.last_pos then
		log_block_distance({
			min = cur_pos.x,
			max = cur_pos.y,
			size = 8,
			deg = rad_to_deg_wrap360((self.scan_radians or 0) + (self.player_start_yaw or 0)),
		})
		self.show_log = false
		self.last_pos = cur_pos
	end
end

---@param self FloorScanState
function FloorScanState:_mark_active()
	-- Mark scan state as active
	self.active = true
end
local deactivate_fmt = "finished placing floor %d blocks placed from center %s"
---@param self FloorScanState
function FloorScanState:deactivate_tool()
	self.scan_radians = 0
	self.count = 0
	if self.blocks_placed > 0 then
		self.all_blocks_placed = self.all_blocks_placed + self.blocks_placed
	end
	if self.all_blocks_placed > 0 then
		local player_pos = round(self.player:get_pos())
		core.log("action", deactivate_fmt:format(self.all_blocks_placed, core.pos_to_string(player_pos)))
	end
	if self.all_blocks_placed > 0 then
		self.all_blocks_placed = 0
	end
end

---@param self FloorScanState
---@param target_pos Vector
---@param dist number
function FloorScanState:on_node_placed(target_pos, dist)
	if self.blocks_this_tick == 0 and self.blocks_placed == 0 then
		local t = self.log_range
		if self.count >= t.min and self.count < t.max then
			core.log("action", "count " .. self.count)
		end
		if self.count >= 400 then
			core.log("action", ("started placing floor after %d steps at %s"):format(self.count, core.pos_to_string(target_pos)))
		end
	end
	self:_update_min_dist(dist)
	self:_update_max_dist(dist)
	if self.show_log then
		self:_maybe_log_block_distance()
	end
	self.blocks_this_tick = self.blocks_this_tick + 1
	self.blocks_placed = self.blocks_placed + 1
end
function FloorScanState:iterate_line_block(target_pos, dist, placeable_node_name, sound_info)
	local node_below = get_node(target_pos)
	if not is_passable(node_below) then
		return
	end
	if target_pos.y == -1 or is_supported(target_pos, placeable_node_name) then
		if try_place_block_from_inventory(self.player, sound_info, target_pos, LINE_LENGTH) then
			self:on_node_placed(target_pos, dist)
		end
	end
end

local DISTANCE_INCREASE = 2 * 8

---@param self FloorScanState
function FloorScanState:run()
	-- Skip if player is not holding the auto-floor tool
	local wielded = self.player:get_wielded_item():get_name()
	if wielded ~= "vein_miner:auto_floor" then
		self:deactivate_tool()
		if self.active then
			self:reset()
		end
		return
	end

	-- Get player info
	local player = self.player
	local yaw = player:get_look_horizontal()
	local pos = player:get_pos()

	local has_floor = false

	-- check a 3x3 area under player
	for dx = -1, 1 do
		for dz = -1, 1 do
			local check_pos = vector.add(pos, {
				x = dx,
				y = -1,
				z = dz,
			})
			local node = get_node_or_nil(check_pos)
			if node and not is_passable(node) then
				has_floor = true
				break
			end
		end
		if has_floor then
			break
		end
	end

	if not has_floor then
		-- skip this tick: no floor below player
		return
	end

	-- Initialize player yaw if not already set
	if self.player_start_yaw == nil then
		-- protect against NaN
		if yaw ~= yaw then
			player:set_look_horizontal(0)
			yaw = 0
		end
		self.player_start_yaw = yaw
	end

	self:_mark_active()

	-- Positioning and direction
	local look_dir = player:get_look_dir()
	local forward_dir = normalize(vector.new(look_dir.x, 0, look_dir.z))
	local line_start = round(pos + down + up / 2)

	-- Player config + controls
	local plr_name = player:get_player_name()
	local ctrl = player:get_player_control()
	local config = player_config_mgr.data[plr_name]

	-- Sound state
	local sound_info = sound_info_per_player[plr_name] or {}
	sound_info.playing_sounds = {}

	-- Inventory scan: find a valid node to place
	-- so we can ignore support provided by this node
	local placeable_node_name = nil
	local inv = player:get_inventory()
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		local name = stack:get_name()
		local def = registered_nodes[name]
		if not placeable_nodes_to_skip[name] and def and name ~= "air" and not def.groups.falling_node then
			placeable_node_name = def.name
			break
		end
	end

	-- Place blocks, update min/max distances, maybe log
	self.blocks_this_tick = 0
	self.max_blocks = config.blocks_per_tick
	for i = 1, LINE_LENGTH do
		if self.blocks_this_tick >= self.max_blocks then
			return false
		end
		local dist = (forward_dir * i):length()
		if dist > (self.max_dist or LINE_LENGTH) + DISTANCE_INCREASE then
			break
		end
		local target_pos = round(line_start + forward_dir * i)
		self:iterate_line_block(target_pos, dist, placeable_node_name, sound_info)
	end

	-- Handle yaw rotation if few blocks placed
	self:_maybe_update_yaw(player, yaw, ctrl)

	-- Handle timers + counters
	self:_update_counters(plr_name, yaw)
end

--- Update counters and timers after a tick
---@param player_name string
function FloorScanState:_update_counters(player_name)
	-- no blocks placed: increment timer
	if self.blocks_this_tick > 0 then
		-- Reset count
		self.count = 0

		-- Update total blocks placed
		self.all_blocks_placed = self.all_blocks_placed + self.blocks_placed
		self.blocks_placed = 0
	end

	-- Record last yaw for this player
	self.last_yaw = self.player_start_yaw
end

local function yaw_for_arc(distance)
	local theta_rad = 1 / distance
	return theta_rad
end

--- Adjust player yaw if few blocks were placed
---@param player Player
---@param yaw number Current yaw
---@param ctrl table Player control state
function FloorScanState:_maybe_update_yaw(player, yaw, ctrl)
	if self.blocks_this_tick ~= 0 or self.yaw_update_disabled then
		return
	end
	local yaw_speed
	if self.max_dist then
		yaw_speed = yaw_for_arc(self.max_dist * 2 + DISTANCE_INCREASE * 2) / 2
	else
		yaw_speed = yaw_for_arc(LINE_LENGTH * 2 + DISTANCE_INCREASE * 2) / 2
	end
	local new_yaw
	if ctrl.sneak then
		new_yaw = self.scan_radians - yaw_speed
	else
		new_yaw = self.scan_radians + yaw_speed
	end

	self.scan_radians = new_yaw
	self.count = self.count + 1

	-- Reset if scan exceeds full rotation
	if math.abs(self.scan_radians) > self.target_rad then
		player:set_look_horizontal(self.target_rad + (self.player_start_yaw or 0))
		self.yaw_update_disabled = true
		self:deactivate_tool()
		return
	end

	-- Update player's horizontal look
	player:set_look_horizontal(self.scan_radians + (self.player_start_yaw or 0))

	-- Disable yaw updates if player is moving
	if vector.length(player:get_velocity()) > 0.05 then
		self.yaw_update_disabled = true
		self:deactivate_tool()
	end
end

---@param player Player
---@return FloorScanState
function floor_filler.new(player)
	---@type FloorScanState
	local self = {
		player = player,
		playing_sounds = {},
		-- generic
		fresh = true,
		count = 0,
		-- player yaw vars
		player_start_yaw = nil,
		scan_radians = 0,
		req_next_reset_scan_radians = 0,
		yaw_update_disabled = false, -- replaces global table
		last_yaw = nil, -- replaces global last_yaw_per_player
		-- min and max display
		show_log = false,
		log_min = nil,
		log_max = nil,
		min_dist = nil,
		max_dist = nil,
		last_pos = vector.zero(),
		blocks_placed = 0,
		all_blocks_placed = 0,
	}

	---@class NumRange
	---@field min number
	---@field max number

	---@type NumRange
	self.log_range = {
		min = 200,
		max = 500,
	}

	setmetatable(self, {
		__index = FloorScanState,
	})

	-- initialize state
	self:reset()
	return self
end

return floor_filler
