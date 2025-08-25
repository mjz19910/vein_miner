local math = math

local TAU = 2 * math.pi

local TARGET_RADIANS = math.rad(360) * 4
local LINE_LENGTH = 48 * 8
local DISTANCE_INCREASE = 3 * 8

local assert = assert

local setmetatable = setmetatable

-- localize table iterators
local ipairs = ipairs

---@type VectorModule
local vector = vector
local table = table

local vec_new = vector.new
local normalize = vector.normalize
local round = vector.round

local ceil = math.ceil
local floor = math.floor
local insert_all = table.insert_all
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

local dig_anyway_set = {}
local dig_anyway_list = {"default:snow"}
insert_all(dig_anyway_list, vein_miner.CFG.mining_groups.tree_trunk)
for _, v in ipairs(dig_anyway_list) do dig_anyway_set[v] = true end

---@param player Player
---@param playing_sounds table<string, boolean>
---@param target_pos Vector
---@param max_hear_distance number
local function try_place_block_from_inventory(player, playing_sounds, target_pos, max_hear_distance)
	local inv = player:get_inventory()
	for i = 1, inv:get_size("main") do
		local name = inv:get_stack("main", i):get_name()
		local def = registered_nodes[name]
		if not placeable_nodes_to_skip[name] and def and name ~= "air" and not def.groups.falling_node then
			local node = core.get_node(target_pos)
			if node and node.name ~= "air" then
				if node.name == "ignore" then return false end
				if node.name == name then return false end
				if dig_anyway_set[node.name] then
					core.node_dig(target_pos, node, player)
					goto after_dig
				end
				local def2 = registered_nodes[node.name]
				if def2.liquidtype == "source" then return false end
				if def2.walkable then return false end
				core.node_dig(target_pos, node, player)
				::after_dig::
			end
			set_node(target_pos, {
				name = name,
			})
			local stack = inv:get_stack("main", i)
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

local falling_blocks_to_support = {
	["default:gravel"] = true,
	["default:silver_sand"] = true,
}
local falling_blocks_to_support_new = {}
local normal_nodes = {
	air = true,
	["default:stone"] = true,
	["default:cobble"] = true,
	["wielded_light:12"] = true,
	["default:pine_bush_needles"] = true,
	["default:dirt"] = true,
	["default:stone_with_coal"] = true,
	["default:blueberry_bush_leaves_with_berries"] = true,
	["default:pine_tree"] = true,
	["default:leaves"] = true,
	["default:jungleleaves"] = true,
	["default:pine_needles"] = true,
	["fireflies:hidden_firefly"] = true,
	["wool:green"] = true,
	["default:dirt_with_grass"] = true,
	["default:dirt_with_snow"] = true,
	["default:stone_with_iron"] = true,
	["default:snowblock"] = true,
	["default:mese_post_light_pine_wood"] = true,
	["default:dirt_with_coniferous_litter"] = true,
	["default:mossycobble"] = true,
	["default:stone_with_tin"] = true,
	["default:water_flowing"] = true,
	["wielded_light:water_12"] = true,
	["default:water_source"] = true,
	["butterflies:butterfly_red"] = true,
	["default:bush_leaves"] = true,
	["butterflies:butterfly_violet"] = true,
	["default:cave_ice"] = true,
	["default:stone_with_copper"] = true,
	["default:tree"] = true,
	["default:jungletree"] = true,
	["default:acacia_leaves"] = true,
	["default:dry_dirt"] = true,
	["default:aspen_leaves"] = true,
	["default:aspen_tree"] = true,
	["default:apple"] = true,
}
local normal_nodes_new = {}

---@param pos Vector
---@param invalid_support_name string
local function is_supported(pos, invalid_support_name)
	-- Ensure all immediate neighbors exist
	for _, offset in ipairs(neighbor_offsets) do
		local node = get_node_or_nil(pos + offset)
		if not node or node.name == "ignore" then return false end
	end

	local check_pos = offset(pos, 0, 1, 0)
	local node = get_node_or_nil(check_pos)
	if falling_blocks_to_support[node.name] then return true end
	if not normal_nodes[node.name] then
		local def = registered_nodes[node.name]
		if def and def.groups and def.groups.falling_node then
			falling_blocks_to_support[node.name] = true
			falling_blocks_to_support_new[node.name] = true
			core.log("action", core.serialize(falling_blocks_to_support_new))
			return true
		else
			normal_nodes[node.name] = true
			normal_nodes_new[node.name] = true
			core.log("action", core.serialize(normal_nodes_new))
		end
	end

	local floor_air_count = 0
	for dx = -2, 2 do
		for dz = -2, 2 do
			local node = get_node_or_nil(offset(pos, dx, -1, dz))
			if node and is_passable(node) then floor_air_count = floor_air_count + 1 end
		end
	end

	-- --- Roof check (scan y+1..y+3 for closest solid layer) ---
	local roof_all_solid = false
	local has_roof = false
	for dy = 1, 3 do
		local air_count = 0
		for dx = -2, 2 do
			for dz = -2, 2 do
				local node = get_node_or_nil(offset(pos, dx, dy, dz))
				if node and is_passable(node) then air_count = air_count + 1 end
			end
		end
		if air_count == 0 then
			has_roof = true
			roof_all_solid = true
			break
		elseif air_count < 9 then
			has_roof = true
			roof_all_solid = false
			break
		end
	end

	-- If we found neither floor nor roof → skip to neighbors
	-- if not has_floor and not has_roof then goto check_neighbors end

	-- If both floor and roof exist, require at least one to be NOT full solid
	if roof_all_solid or floor_air_count == 0 then return false end

	::check_neighbors::
	-- Neighbor support check
	for _, offset in ipairs(neighbor_offsets) do
		local node = get_node(pos + offset)
		if is_node_supporting(node, invalid_support_name) then return true end
	end

	return false
end

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
local FloorScanState = {}

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
	self:reset(true)
	return self
end

function FloorScanState:_get_config_key() return self.player:get_player_name() end

function FloorScanState:_maybe_increase_saved_place_limit()
	if self.max_dist and self.max_dist > self.place_limit then
		self.place_limit = self.max_dist + 32
		core.log("increased place limit to " .. math.floor(self.place_limit / 8) .. " 8x8 chunks")
		player_config_mgr:set_floor_place_limit(self:_get_config_key(), self.place_limit)
	end
end

function FloorScanState:_load_user_config()
	local limit = player_config_mgr:get_floor_place_limit(self:_get_config_key())
	if limit ~= nil then self.place_limit = limit end
end

---@param self FloorScanState
---@param first_init boolean
function FloorScanState:reset(first_init)
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
	self.all_max_dist = nil
	self.last_pos = vec_new(0, -1, 0)
	self.blocks_placed = 0
	self.all_blocks_placed = 0
	self.nodes_this_tick = 0
	self.last_place_yaw_radians = nil
	self.use_set_fov = false

	local name = self.player:get_player_name()
	self.place_limit = player_config_mgr:get_floor_place_limit(name) or LINE_LENGTH
	self.nodes_per_tick = player_config_mgr:get_blocks_per_tick(name)
	if first_init then
		---@type NumRange
		self.log_range = {
			min = 100,
			max = 150,
		}
		self.did_disable_mapgen = false
	end

	if self.did_disable_mapgen then
		self.player:set_mapgen_disabled(false)
		self.did_disable_mapgen = false
	end
	self.nodes_per_tick_avg = 0
	self.current_line_y = 0
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
		if self.all_max_dist == nil then self.all_max_dist = dist end
		if dist > self.all_max_dist then self.all_max_dist = dist end
	end
end

--- Log the current min/max block distance if needed
---@param self FloorScanState
function FloorScanState:_maybe_log_block_distance()
	local cur_pos = vec_new(self.log_min, self.log_max, 0):divide(8):floor()

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
		self.player:set_fov(0, false, 0)
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
	if self.nodes_this_loop == 0 and self.blocks_placed == 0 then
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
	self.nodes_this_loop = self.nodes_this_loop + 1
	self.blocks_placed = self.blocks_placed + 1
end

---@param self FloorScanState
function FloorScanState:min_based_limit() return self.min_dist or self.place_limit end

---@param self FloorScanState
function FloorScanState:max_based_limit() return self.max_dist or self.all_max_dist or self.place_limit end

---@param self FloorScanState
function FloorScanState:get_place_limit() return self:max_based_limit() + DISTANCE_INCREASE end

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
		if self.active then
			self:reset()
			self.skip_after_yaw = false
		end
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
		self.current_yaw_rad = yaw + math.pi / 2
		self.player_pos = round(player:get_pos())
		local pos_offset = self.player_pos - player:get_pos()
		if pos_offset.y < -0.3 then self.player_pos.y = self.player_pos.y + 1 end
		pos_offset = self.player_pos - player:get_pos()
		core.log("pos diff " .. tostring(pos_offset))
		self.line_start = self.player_pos + down
		self.current_line_y = self.line_start.y
		core.log("action", "start line floor placing at " .. self.current_line_y)
		local ctrl = player:get_player_control()
		if not self.tool_active and ctrl.zoom then self.use_set_fov = true; end
		self.is_mapgen_disabled = self.player:get_mapgen_disabled()
		if not self.is_mapgen_disabled then
			player:set_mapgen_disabled(true)
			self.did_disable_mapgen = true
		end
	end

	if self.player_pos == nil then self.player_pos = round(player:get_pos()) end

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

	self.active = true
	for i = 1, 75 do
		if self.main_break_on_next then
			self.main_break_on_next = false
			break
		end
		self:main_loop(player, placeable_node_name)
		if self.nodes_this_tick > self.nodes_per_tick then break end
		do break end
	end
	if self.nodes_this_tick > 0 then
		self.nodes_per_tick_avg = self.nodes_per_tick_avg / 2 + self.nodes_this_tick / 2
		self.nodes_this_tick = 0
	elseif self.nodes_per_tick_avg < 1e-9 then
		self.nodes_per_tick_avg = 0
	else
		self.nodes_per_tick_avg = self.nodes_per_tick_avg / 1.01
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

-- Helper: check if both feet+head are passable
local function is_standable(pos)
	local node_feet = core.get_node_or_nil(pos)
	local node_head = core.get_node_or_nil(pos + vector.new(0, 1, 0))
	if not node_feet or not node_head then return false end

	if node_feet.name == "ignore" or node_head.name == "ignore" then return false end

	local def_feet = core.registered_nodes[node_feet.name]
	local def_head = core.registered_nodes[node_head.name]
	if not def_feet or not def_head then return false end

	return not def_feet.walkable and not def_head.walkable
end

---@param player Player
---@param target_pos Vector
---@return boolean success
local function safe_set_player_pos(player, target_pos)
	-- directions to search: N, S, E, W
	local dirs = {vector.new(1, 0, 0), vector.new(-1, 0, 0), vector.new(0, 0, 1), vector.new(0, 0, -1)}

	-- Check target position first
	if is_standable(target_pos) then
		player:set_pos(target_pos)
		return target_pos, true
	end

	for r = 1, 32 do
		for _, d in ipairs(dirs) do
			local candidate = target_pos + d * r
			if is_standable(candidate) then
				player:set_pos(candidate)
				return candidate, true
			end
		end
	end

	return target_pos, false
end

function FloorScanState:main_loop(player, placeable_node_name)
	local ctrl = player:get_player_control()

	if self.yaw_update_disabled then
		if ctrl.zoom then self.skip_after_yaw = true end
		local player_pos = round(player:get_pos())
		local pos_offset = self.player_pos - player:get_pos()
		if pos_offset.y < -0.3 then self.player_pos.y = self.player_pos.y + 1 end
		if not self.skip_after_yaw then
			local yaw_speed = get_yaw_speed_for_distance(self:get_place_limit()) * 1.5
			self.scan_radians = self.scan_radians + yaw_speed
			self.current_yaw_rad = self.scan_radians + self.player_start_yaw + math.pi / 2
			player:set_look_horizontal(self.scan_radians + self.player_start_yaw + yaw_speed)
			local prev = self:get_angle_rad() % (TAU * 2)
			local curr = (self:get_angle_rad() + yaw_speed) % (TAU * 2)
			local step = TAU / 2 -- 180° in radians
			local prev_sector = math.floor(prev / step)
			local curr_sector = math.floor(curr / step)

			if prev_sector ~= curr_sector then
				local has_big_max = self.max_dist and self.max_dist >= 64
				if self.nodes_per_tick_avg < 0.4 or (has_big_max and self.nodes_per_tick_avg < 1.5) then
					local avg_rounded = math.floor(self.nodes_per_tick_avg * 1e5) / 1e5
					self.current_line_y = self.current_line_y - 1
					self.player_pos.y = self.current_line_y + 1
					self.player_pos = safe_set_player_pos(player, self.player_pos)
					self.line_start = vector.new(self.player_pos)
					self.line_start.y = self.current_line_y
				end
			end
		else
			self.current_yaw_rad = player:get_look_horizontal() + math.pi / 2
		end
		self.main_break_on_next = true
	end

	local line_start = self.line_start
	local player_pos = self.player_pos

	-- Positioning and direction
	local yaw = self.current_yaw_rad
	local forward_dir = vec_new(math.cos(yaw), 0, math.sin(yaw))

	-- Player config + controls
	local player_name = player:get_player_name()

	self.nodes_this_loop = 0
	local playing_sounds = self.playing_sounds
	local max_nodes = self.nodes_per_tick - self.nodes_this_tick
	local place_limit = self.place_limit
	local last_place_pos = nil
	for offset in raycast(forward_dir) do
		local target_pos = line_start + vec_new(offset.x, 0, offset.z)
		local cur_len = offset:length()
		if cur_len > self:get_place_limit() then break end
		local cur = get_node_or_nil(target_pos)
		if not cur then goto next end
		if cur.name == placeable_node_name then goto next end
		core.log("action", "enter raycast loop " .. core.pos_to_string(target_pos) .. " cast offset " .. core.pos_to_string(offset))
		if self.nodes_this_loop >= max_nodes then break end
		local cur = get_node_or_nil(target_pos)
		if not cur then break end
		if dig_anyway_set[cur.name] then goto try_dig end
		if not is_passable(cur) then goto next end
		if target_pos.y ~= -1 and not is_supported(target_pos, placeable_node_name) then goto next end
		if cur.name == "ignore" then goto next end
		do
			local def = registered_nodes[cur.name]
			if def.liquidtype == "source" then goto next end
			if def.walkable then goto next end
		end
		::try_dig::
		last_place_pos = target_pos
		if not try_place_block_from_inventory(player, playing_sounds, target_pos, place_limit) then goto next end
		self:on_node_placed(target_pos, cur_len)
		self.break_on_next = false
		do break end
		::next::
	end
	if self.nodes_this_loop > 0 then self.nodes_this_tick = self.nodes_this_tick + self.nodes_this_loop end
	if last_place_pos ~= nil and not self.yaw_update_disabled then player:set_pos(last_place_pos + up / 2) end
	if last_place_pos ~= nil and self.yaw_update_disabled and self.nodes_per_tick_avg < 0.5 then player:set_pos(last_place_pos + up / 2) end
	-- Handle yaw rotation if few blocks placed
	self:_maybe_update_yaw(player, ctrl)
	-- Handle timers + counters
	self:_update_counters(player_name)
	if self.use_set_fov and not self.yaw_update_disabled then player:set_look_horizontal(self.current_yaw_rad - math.pi / 2) end
end

--- Update counters and timers after a tick
---@param self FloorScanState
---@param player_name string
function FloorScanState:_update_counters(player_name)
	-- no blocks placed: increment timer
	if self.blocks_placed > 0 then
		-- Reset count
		self.count = 0

		-- Update total blocks placed
		self.all_blocks_placed = self.all_blocks_placed + self.blocks_placed
		self.blocks_placed = 0
	end

	if self.last_place_yaw_radians and self.count > self.log_range.min then
		core.log("action", "finished placing floor at deg " .. ("%.1f"):format(rad_to_deg_wrap360(self.last_place_yaw_radians)))
		self.last_place_yaw_radians = nil
	end
end

---@param self FloorScanState
function FloorScanState:get_angle_rad() return self.scan_radians + self.player_start_yaw end

---@param self FloorScanState
function FloorScanState:get_angle_deg() return rad_to_deg_wrap360(self.scan_radians + self.player_start_yaw) end

--- Adjust player yaw if few blocks were placed
---@param self FloorScanState
---@param player Player
---@param ctrl table Player control state
function FloorScanState:_maybe_update_yaw(player, ctrl)
	if self.yaw_update_disabled or self.nodes_this_loop ~= 0 then return end
	if not self.tool_active and self.use_set_fov then
		player:set_fov(10, false, 0)
		self.tool_active = true
	end
	local yaw_speed = get_yaw_speed_for_distance(self:get_place_limit()) * 1.25
	if ctrl.sneak then yaw_speed = -yaw_speed end

	local prev = self:get_angle_rad() % TAU
	local curr = (self:get_angle_rad() + yaw_speed) % TAU
	local step = TAU / 4 -- 90° in radians

	-- detect crossing any multiple of 90°
	local prev_sector = math.floor(prev / step)
	local curr_sector = math.floor(curr / step)

	if prev_sector ~= curr_sector then
		-- which boundary did we cross?
		local boundary = curr_sector * step
		core.log("action", ("crossed %.1f°"):format(math.deg(boundary)))
		if curr_sector == 0 then
			if self.break_on_next then
				self.yaw_update_disabled = true
				self.main_break_on_next = true
				self.break_on_next = false
				self:deactivate_tool()
				return
			end
			self.break_on_next = true
		end
	end

	-- Abort if player requested abort (sneak + zoom)
	if player:get_velocity():length() > 0.05 and ctrl.sneak and ctrl.zoom then
		self.yaw_update_disabled = true
		self.break_on_next = true
		self.main_break_on_next = true
		self:deactivate_tool()
		return
	end

	-- Reset if scan exceeds full rotation
	if math.abs(self.scan_radians) > TARGET_RADIANS then
		self.current_yaw_rad = TARGET_RADIANS + self.player_start_yaw + math.pi / 2
		self.yaw_update_disabled = true
		self.break_on_next = true
		self.main_break_on_next = true
		self:deactivate_tool()
		return
	end

	self.scan_radians = self.scan_radians + yaw_speed
	self.current_yaw_rad = self.scan_radians + self.player_start_yaw + math.pi / 2
	self.count = self.count + 1
end

return floor_filler
