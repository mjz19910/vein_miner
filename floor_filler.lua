local LINE_LENGTH = 256

local assert = assert

-- localize table iterators
local ipairs = ipairs

local math = math
local vector = vector

local new_vec = vector.new
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

local floor_filler = {}

local placeable_nodes_to_skip = h.make_set({"default:jungletree", "digtron:light"}, true)

local support_dirs = vein_miner.CFG.SUPPORT_DIRS
local vertical_offsets = vein_miner.CFG.VERTICAL_OFFSETS

---@param player Player
---@param playing_sounds SoundInfo
---@param target_pos Vector
---@param max_hear_distance number
local function try_place_block_from_inventory(skip, player, playing_sounds, target_pos, max_hear_distance)
	local inv = player:get_inventory()
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		local name = stack:get_name()
		local def = registered_nodes[name]
		if not skip[name] and def and name ~= "air" and not def.groups.falling_node then
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

---@param pos Vector
local function is_supported(pos, invalid_support_name)
	local below_pos = pos + new_vec(0, -1, 0)
	local below_node = get_node_or_nil(below_pos)
	if not below_node then
		return false
	end
	for _, dir in ipairs(support_dirs) do
		for _, vert in ipairs(vertical_offsets) do
			local sup_pos = pos + dir + vert
			if sup_pos ~= pos then
				local node = get_node_or_nil(sup_pos)
				if is_node_supporting(node, invalid_support_name) then
					return true
				end
			end
		end
	end
	local npos = pos + new_vec(1, 0, 0)
	local node1 = get_node_or_nil(npos)
	local npos = pos + new_vec(-1, 0, 0)
	local node2 = get_node_or_nil(npos)
	local east_support = is_node_supporting(node1, invalid_support_name)
	local west_support = is_node_supporting(node2, invalid_support_name)
	if east_support and west_support then
		return true
	end
	local npos = pos + new_vec(0, 0, 1)
	local node1 = get_node_or_nil(npos)
	local npos = pos + new_vec(0, 0, -1)
	local node2 = get_node_or_nil(npos)
	local north_support = is_node_supporting(node1, invalid_support_name)
	local south_support = is_node_supporting(node2, invalid_support_name)
	if north_support and south_support then
		return true
	end
	return false
end

---@return FloorScanState
function floor_filler.new()
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
	local ret = {
		playing_sounds = {},
		-- generic
		fresh = true,
		count = 0,
		-- player yaw constants
		yaw_max = math.rad(6),
		target_rad = math.rad(360),
		-- player yaw vars
		player_start_yaw = nil,
		has_player_yaw = false,
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

	---@param self FloorScanState
	function ret:reset()
		self.fresh = true
		self.count = 0
		self.player_start_yaw = nil
		self.has_player_yaw = false
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
	end

	---@param pos Vector
	function ret:leave(pos)
		if self.blocks_placed > 0 then
			self.all_blocks_placed = self.all_blocks_placed + self.blocks_placed
		end
		if self.all_blocks_placed > 0 then
			core.log("action", "finished placing floor " .. self.all_blocks_placed .. " blocks placed from center " .. core.pos_to_string(pos))
		end
	end

	---@param self FloorScanState
	---@param player Player
	function ret:run(player)
		local plr_name = player:get_player_name()

		-- tool check
		local wielded = player:get_wielded_item():get_name()
		if wielded ~= "vein_miner:auto_floor" then
			if not self.fresh then
				self.yaw_update_disabled = false
				self.last_yaw = nil
				self:leave(player:get_pos())
				self:reset()
			end
			return
		end

		-- normalize yaw
		local yaw = player:get_look_horizontal()
		if yaw ~= yaw then -- NaN check
			player:set_look_horizontal(0)
			yaw = 0
		end

		-- first-time init
		if not self.has_player_yaw then
			self.player_start_yaw = yaw
			self.has_player_yaw = true
		end

		-- main scanning logic
		self:_do_scan(player, yaw)
	end

	-- private: scanning & placement logic
	function ret:_do_scan(player, yaw)
		local plr_name = player:get_player_name()
		self.fresh = false

		local pos = player:get_pos()
		local dir = normalize(player:get_look_dir())
		local front_dir = normalize(new_vec(dir.x, 0, dir.z)) * 3
		local floor_pos = pos + front_dir + down
		if not get_node_or_nil(floor_pos) then
			return
		end

		local ctrl = player:get_player_control()
		local config = player_config_mgr.data[plr_name]
		local playing_sounds = self.playing_sounds

		-- find a placeable node
		local inv = player:get_inventory()
		local placeable_node_name
		for i = 1, inv:get_size("main") do
			local stack = inv:get_stack("main", i)
			local name = stack:get_name()
			local def = registered_nodes[name]
			if not placeable_nodes_to_skip[name] and def and name ~= "air" and not def.groups.falling_node then
				placeable_node_name = def.name
				break
			end
		end

		local base_pos = pos
		local forward_dir = normalize(new_vec(dir.x, 0, dir.z))
		local line_start = round(base_pos + down + up / 2)
		local max_blocks = config.blocks_per_tick

		local blocks_this_tick = 0

		for i = 1, LINE_LENGTH do
			local target_pos = round(line_start + forward_dir * i)
			local len = (forward_dir * i):length()

			if self.min_dist and len > self.min_dist + 8 then
				break
			end

			local node_below = get_node(target_pos)
			if is_passable(node_below) and is_supported(target_pos, placeable_node_name) then
				if blocks_this_tick >= max_blocks then
					break
				end

				if try_place_block_from_inventory(placeable_nodes_to_skip, player, playing_sounds, target_pos, LINE_LENGTH) then
					blocks_this_tick = blocks_this_tick + 1
					self.blocks_placed = self.blocks_placed + 1

					local dist = len - len % 8 + 8
					self:_update_min_log(dist)
					self:_update_max_log(dist)
					self:_log_positions()

					if blocks_this_tick == 1 and self.blocks_placed == 1 then
						self:_log_first_block(target_pos)
					end
				end
			end
		end

		if blocks_this_tick <= 1 and not self.yaw_update_disabled then
			self:_update_yaw(player, ctrl, blocks_this_tick)
		end

		self.last_yaw = yaw
		self:_finalize_tick(blocks_this_tick)
	end

	-- initialize state
	ret:reset()
	return ret
end

return floor_filler
