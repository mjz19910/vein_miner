local LINE_LENGTH = 48 * 8

local assert = assert

local setmetatable = setmetatable

-- localize table iterators
local ipairs = ipairs

local math = math
---@type VectorModule
local vector = vector

local vec_new = vector.new
local normalize = vector.normalize
local round = vector.round

local ceil = math.ceil
local floor = math.floor

---@type CoreModApi
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

local up = vec_new(0, 1, 0)
local down = vec_new(0, -1, 0)

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
				if cur_node.name == "ignore" then return false end
				local def2 = registered_nodes[cur_node.name]
				if def2.liquidtype == "source" then return false end
				if def2.walkable then return false end
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
			if table.contains(neighbor_offsets, offset) then core.log("error", "duplicate offset " .. core.pos_to_string(offset)) end
			table.insert(neighbor_offsets, offset)
		end
	end
end

local offset = vector.offset

---@param pos Vector
---@param invalid_support_name string
local function is_supported(pos, invalid_support_name)
	-- Ensure all immediate neighbors exist
	for _, offset in ipairs(neighbor_offsets) do
		local node = get_node_or_nil(pos + offset)
		if not node then return false end
	end

	-- --- Roof check (scan y+1..y+3 for closest solid layer) ---
	local roof_all_solid = false
	local has_roof = false
	for dy = 1, 3 do
		local all_solid = true
		for dx = -2, 2 do
			for dz = -2, 2 do
				local check_pos = offset(pos, dx, dy, dz)
				local node = get_node_or_nil(check_pos)
				if not node or is_passable(node) then
					all_solid = false
					break
				end
			end
			if not all_solid then break end
		end
		if all_solid then
			roof_all_solid = true
			has_roof = true
			break -- closest roof layer found
		else
			-- found a layer but not all solid → roof is not fully blocking
			has_roof = true
			roof_all_solid = false
			break
		end
	end

	-- If we found neither floor nor roof → skip to neighbors
	-- if not has_floor and not has_roof then goto check_neighbors end

	-- If both floor and roof exist, require at least one to be NOT full solid
	if roof_all_solid then return false end

	::check_neighbors::
	-- Neighbor support check
	for _, offset in ipairs(neighbor_offsets) do
		local node = get_node(pos + offset)
		if is_node_supporting(node, invalid_support_name) then return true end
	end

	return false
end

local DISTANCE_INCREASE = 24

local TARGET_RADIANS = math.rad(360)

---@class FloorScanState
---@field player Player
---@field playing_sounds table<string, boolean>
--- player yaw vars
---@field player_start_yaw number|nil
--- min and max display
---@field log_min number|nil
---@field log_max number|nil
---@field min_dist number|nil
---@field max_dist number|nil
---@field nodes_this_tick integer Number of nodes placed this tick
---@field place_limit integer
---@field last_length integer|nil
local FloorScanState = {
	-- player yaw constants
	target_rad = math.rad(360),
}

---@param player Player
---@return FloorScanState
function floor_filler.new(player)
	---@type FloorScanState
	local self = {
		player = player,
	}

	setmetatable(self, {
		__index = FloorScanState,
	})

	-- initialize state
	self:reset()
	return self
end

function FloorScanState:_get_config_key() return self.player:get_player_name() end

function FloorScanState:_maybe_increase_saved_place_limit()
	if self.max_dist and self.max_dist > self.place_limit then
		self.place_limit = self.max_dist - self.max_dist % 8 + 8
		core.log("increased place limit to " .. math.floor(self.place_limit / 8) .. " 8x8 chunks")
		player_config_mgr:set_floor_place_limit(self:_get_config_key(), self.place_limit)
	end
end

function FloorScanState:_load_user_config()
	local limit = player_config_mgr:get_floor_place_limit(self:_get_config_key())
	if limit ~= nil then self.place_limit = limit end
end

---@param self FloorScanState
function FloorScanState:reset()
	self:_maybe_increase_saved_place_limit()

	if not self.playing_sounds then self.playing_sounds = {} end
	-- generic
	self.active = false
	self.count = 0
	-- player yaw vars
	self.player_start_yaw = nil
	self.scan_radians = 0
	self.req_next_reset_scan_radians = 0
	self.yaw_update_disabled = false -- replaces global table
	-- min and max display
	self.show_log = false
	self.log_min = nil
	self.log_max = nil
	self.min_dist = nil
	self.max_dist = nil
	self.last_pos = vec_new(0, -1, 0)
	self.blocks_placed = 0
	self.all_blocks_placed = 0
	self.nodes_this_tick = 0
	self.last_place_yaw_radians = nil
	self.use_set_fov = false

	if not self.place_limit then self.place_limit = LINE_LENGTH end

	if not self.log_range then
		---@type NumRange
		self.log_range = {
			min = 100,
			max = 150,
		}
	end

	local name = self.player:get_player_name()
	local config = player_config_mgr.data[name]
	if config.floor_place_limit ~= nil then self.place_limit = config.floor_place_limit end

	self.nodes_per_tick = player_config_mgr:get_blocks_per_tick(name)

end

---@param self FloorScanState
---@param pos Vector
function FloorScanState:leave_floor_scan(pos) end

local block_dist_fmt = "place range at %.1f° min %s max %s, size %s"

---@param min integer
---@param max integer
---@param size integer
---@param deg number
local function log_block_distance(min, max, size, deg) core.log("action", block_dist_fmt:format(deg, min, max, size)) end

---@param rad number
local function rad_to_deg_wrap360(rad)
	local deg = math.deg(rad) % 360
	if deg < 0 then deg = deg + 360 end
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
	local cur_pos = vec_new(self.log_min, self.log_max, 0):divide(2):round():multiply(2)

	-- Only log if the position changed
	if cur_pos ~= self.last_pos then
		log_block_distance(cur_pos.x, cur_pos.y, 8, self:get_angle_deg())
		self.show_log = false
		self.last_pos = cur_pos
	end
end

local deactivate_fmt = "floor finished at %s, %d nodes placed"
---@param self FloorScanState
function FloorScanState:deactivate_tool()
	self.scan_radians = 0
	self.count = 0
	if self.blocks_placed > 0 then self.all_blocks_placed = self.all_blocks_placed + self.blocks_placed end
	if self.all_blocks_placed > 0 then
		local player_pos = round(self.player:get_pos())
		core.log("action", deactivate_fmt:format(core.pos_to_string(player_pos), self.all_blocks_placed))
	end
	if self.all_blocks_placed > 0 then self.all_blocks_placed = 0 end
	if self.tool_active then
		local c = self.player:get_player_control()
		if c.zoom then
			self.player:set_fov(10, false, 0.75)
			core.after(0.75, function() self.player:set_fov(0, false, 0) end)
		else
			self.player:set_fov(0, false, 1.25)
		end
		self.tool_active = false
	end
end

local floor_place_fmt = "started placing floor after %d steps at %s with yaw=%.1f"
local log_action_fmt = "count %d pos %s deg %.1f"

---@param self FloorScanState
---@param target_pos Vector
---@param dist number
function FloorScanState:on_node_placed(pos, dist)
	self.last_place_yaw_radians = self.scan_radians + self.player_start_yaw
	if self.nodes_this_tick == 0 and self.blocks_placed == 0 then
		local a, b = self.count, self.log_range
		if a >= b.min then
			local c, d = core.pos_to_string(pos), self:get_angle_deg()
			if a < b.max then
				core.log("action", log_action_fmt:format(a, c, d))
			else
				core.log("action", floor_place_fmt:format(a, c, d))
			end
		end
	end
	self:_update_min_dist(dist)
	self:_update_max_dist(dist)
	if self.show_log then self:_maybe_log_block_distance() end
	self.nodes_this_tick = self.nodes_this_tick + 1
	self.blocks_placed = self.blocks_placed + 1
end

---@param self FloorScanState
---@param target_pos Vector
---@param line_len number
---@param node_below MapNode
---@param placeable_node_name string
function FloorScanState:iterate_offset(target_pos, line_len, node_below, placeable_node_name)
	if target_pos.y == -1 or is_supported(target_pos, placeable_node_name) then
		if try_place_block_from_inventory(self.player, self.playing_sounds, target_pos, self.place_limit) then
			self:on_node_placed(target_pos, line_len)
		end
	end
end

---@param self FloorScanState
function FloorScanState:min_based_limit() return self.min_dist or self.place_limit end

---@param self FloorScanState
function FloorScanState:max_based_limit() return self.max_dist or self.place_limit end

---@param self FloorScanState
function FloorScanState:get_place_limit() return self:min_based_limit() + DISTANCE_INCREASE end

-- Traces from line_start in forward_dir until limit
-- yields node positions along the ray
local function raycast(dir)
	local pos = vector.zero()
	-- avoid divide by zero
	local step = {
		x = (dir.x > 0) and 1 or -1,
		y = (dir.y > 0) and 1 or -1,
		z = (dir.z > 0) and 1 or -1,
	}
	local t_max = {
		x = ((step.x > 0 and (pos.x + 1 - pos.x) or (pos.x - pos.x)) / (dir.x ~= 0 and dir.x or 1e-9)),
		y = ((step.y > 0 and (pos.y + 1 - pos.y) or (pos.y - pos.y)) / (dir.y ~= 0 and dir.y or 1e-9)),
		z = ((step.z > 0 and (pos.z + 1 - pos.z) or (pos.z - pos.z)) / (dir.z ~= 0 and dir.z or 1e-9)),
	}
	local t_delta = {
		x = math.abs(1 / (dir.x ~= 0 and dir.x or 1e-9)),
		y = math.abs(1 / (dir.y ~= 0 and dir.y or 1e-9)),
		z = math.abs(1 / (dir.z ~= 0 and dir.z or 1e-9)),
	}
	return function()
		local cur = vec_new(pos)
		-- advance
		if t_max.x < t_max.y and t_max.x < t_max.z then
			pos.x = pos.x + step.x
			t_max.x = t_max.x + t_delta.x
		elseif t_max.y < t_max.z then
			pos.y = pos.y + step.y
			t_max.y = t_max.y + t_delta.y
		else
			pos.z = pos.z + step.z
			t_max.z = t_max.z + t_delta.z
		end
		return cur
	end
end

local p_str = core.pos_to_string

local max_distance_fmt = "node placed at %s with new max distance %.1f from %s"

---@param self FloorScanState
function FloorScanState:run()
	local player = self.player

	-- Skip if player is not holding the auto-floor tool
	local wielded = player:get_wielded_item():get_name()
	if wielded ~= "vein_miner:auto_floor" then
		self:deactivate_tool()
		if self.active then self:reset() end
		return
	end

	if self.player_start_yaw == nil then
		local yaw = player:get_look_horizontal()
		-- protect against NaN
		if yaw ~= yaw then
			player:set_look_horizontal(0)
			yaw = 0
		end
		self.player_start_yaw = yaw
		self.current_yaw_rad = yaw - math.pi / 2
	end

	self.active = true

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

	local player_pos = player:get_pos()
	local line_start = round(player_pos + down + up / 2)

	if self.yaw_update_disabled then self.current_yaw_rad = player:get_look_horizontal() + math.pi / 2 end

	-- Positioning and direction
	local forward_dir = vec_new(math.cos(self.current_yaw_rad), 0, math.sin(self.current_yaw_rad))

	-- Player config + controls
	local player_name = player:get_player_name()
	local ctrl = player:get_player_control()

	if not self.tool_active and ctrl.zoom then self.use_set_fov = true; end

	-- Sound state
	local playing_sounds = self.playing_sounds

	local max_nodes = self.nodes_per_tick
	for offset in raycast(forward_dir) do
		local target_pos = line_start + offset
		local cur_len = offset:length()
		if cur_len > self:get_place_limit() then break end
		if self.nodes_this_tick >= max_nodes then break end
		if math.floor(target_pos.y) <= math.floor(player_pos.y) - 1 then target_pos.y = target_pos.y + 1 end
		local node_below = get_node_or_nil(target_pos)
		if not node_below then break end
		if not is_passable(node_below) then goto continue end
		if target_pos.y ~= -1 and not is_supported(target_pos, placeable_node_name) then goto continue end
		if not try_place_block_from_inventory(self.player, self.playing_sounds, target_pos, self.place_limit) then goto continue end
		if not self.last_length or cur_len > self.last_length + 0.1 then
			core.chat_send_player(player_name, max_distance_fmt:format(p_str(target_pos), cur_len, p_str(line_start)))
			self.last_length = cur_len
		end
		self:on_node_placed(target_pos, cur_len)
		::continue::
	end

	-- Handle yaw rotation if few blocks placed
	self:_maybe_update_yaw(player, ctrl)

	-- Handle timers + counters
	self:_update_counters(player_name)
end

--- Update counters and timers after a tick
---@param self FloorScanState
---@param player_name string
function FloorScanState:_update_counters(player_name)
	-- no blocks placed: increment timer
	if self.nodes_this_tick > 0 then
		-- Reset count
		self.nodes_this_tick = 0
		self.count = 0

		-- Update total blocks placed
		self.all_blocks_placed = self.all_blocks_placed + self.blocks_placed
		self.blocks_placed = 0
	end

	if self.last_place_yaw_radians and self.count > self.log_range.min then
		self:_reset_range_vars()
		core.log("action", "finished placing floor at deg " .. ("%.1f"):format(rad_to_deg_wrap360(self.last_place_yaw_radians)))
		self.last_place_yaw_radians = nil
	end
end

---@param dist number
local function yaw_for_arc(dist) return 1 / dist end

---@param dist number
local function get_yaw_speed_for_distance(dist)
	local xz_offset = dist + 1
	local max_dist = vec_new(xz_offset, 0, xz_offset):length()
	return yaw_for_arc(math.ceil(max_dist))
end

---@param self FloorScanState
function FloorScanState:get_angle_rad() return self.scan_radians + self.player_start_yaw end

---@param self FloorScanState
function FloorScanState:get_angle_deg() return rad_to_deg_wrap360(self.scan_radians + self.player_start_yaw) end

local TAU = 2 * math.pi

function FloorScanState:_reset_range_vars()
	if self.min_dist and self.max_dist then
		local cur_pos = vec_new(self.min_dist, self.max_dist, 0):divide(2):round():multiply(2)
		core.log("action", ("reset range vars from (%d,%d)"):format(cur_pos.x, cur_pos.y))
		self.last_length = nil
	end
	self.min_dist = nil
	self.max_dist = nil
	self.log_min = nil
	self.log_max = nil
	self.show_log = false
end

--- Adjust player yaw if few blocks were placed
---@param self FloorScanState
---@param player Player
---@param ctrl table Player control state
function FloorScanState:_maybe_update_yaw(player, ctrl)
	if self.yaw_update_disabled or self.nodes_this_tick ~= 0 then return end
	if not self.tool_active and self.use_set_fov then
		player:set_fov(10, false, 1)
		self.tool_active = true
	end
	local yaw_speed = get_yaw_speed_for_distance(self:get_place_limit()) / 1.3
	if ctrl.sneak then yaw_speed = -yaw_speed end
	local prev = self:get_angle_rad() % TAU
	local curr = (self:get_angle_rad() + yaw_speed) % TAU

	-- crossed π (180°)
	-- if prev < math.pi and curr >= math.pi then
	-- 	core.log("action", "180° passed (forward)")
	-- elseif prev >= math.pi and curr < math.pi then
	-- 	core.log("action", "180° passed (backward)")
	-- end

	-- detect crossing 0° in either direction
	if math.abs(curr - prev) > math.pi then self:_reset_range_vars() end

	-- Reset if scan exceeds full rotation
	if math.abs(self.scan_radians) > self.target_rad then
		self.yaw_update_disabled = true
		self:deactivate_tool()
		return
	end

	self.scan_radians = self.scan_radians + yaw_speed
	self.current_yaw_rad = self.scan_radians + self.player_start_yaw + math.pi / 2
	self.count = self.count + 1
end

return floor_filler
