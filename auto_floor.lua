local print = print
local setmetatable = setmetatable
local tostring = tostring
local type = type
---@type LuantiCore
local core = core

local assert = assert
---@type VectorModule
local vector = vector
local ipairs = ipairs
local pairs = pairs
local table = table
local math = math
---@type VeinMinerGlobal
local vein_miner = vein_miner

-- localize math
local round = vector.round
local offset = vector.offset
local normalize = vector.normalize
local multiply = vector.multiply
local new_vec = vector.new

local set_node = core.set_node
local get_node = core.get_node
local get_node_or_nil = core.get_node_or_nil
local sound_play = core.sound_play
local get_connected_players = core.get_connected_players

local registered_nodes = core.registered_nodes

local player_config_mgr = vein_miner.player_config_mgr
assert(player_config_mgr, "need vein_miner.player_config_mgr")
core.register_tool("vein_miner:auto_floor", {
	description = "Auto-Floor Builder",
	inventory_image = "default_wood.png",
})

local up = new_vec(0, 1, 0)
local down = new_vec(0, -1, 0)
local p = new_vec
local cardinal_dirs = vein_miner.CFG.cardinal_dirs
local diagonal_dirs = {p(1, 0, 1), p(-1, 0, 1), p(1, 0, -1), p(-1, 0, -1)}
local support_dirs = {new_vec(0, 0, 0)}
for _, dir in ipairs(cardinal_dirs) do
	if dir.y == 0 then
		table.insert(support_dirs, dir)
	end
end
table.insert_all(support_dirs, diagonal_dirs)
local vertical_offsets = {down, new_vec(0, 0, 0), up, up * 2}

local function is_node_supporting(node, skip_name)
	if node == nil then
		return false
	end
	if node.name == skip_name then
		return false
	end
	local def = registered_nodes[node.name]
	if def.air_equivalent then
		return false
	end
	if def.liquidtype == "source" then
		return true
	end
	if def.liquidtype == "flowing" then
		return true
	end
	do
		return true
	end
	if def and not def.floodable and def.walkable then
		return true
	end
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

local function make_set(table, init)
	local ret = {}
	for _, value in ipairs(table) do
		ret[value] = init
	end
	return ret
end

local placeable_nodes_to_skip = make_set({"default:jungletree"}, true)

local LINE_LENGTH = 256
---@class SoundInfo
---@field playing_sounds table<string, boolean>

---@param player Player
---@param sound_info SoundInfo
---@param target_pos Vector
---@param max_hear_distance number
local function try_place_block_from_inventory(player, sound_info, target_pos, max_hear_distance)
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
			if not sound_info.playing_sounds[def.sounds.place] then
				sound_play(def.sounds.place, {
					pos = target_pos,
					max_hear_distance = max_hear_distance,
				})
				sound_info.playing_sounds[def.sounds.place] = true
			end
			return true
		end
	end
	return false
end

local time_until_block_place = 0
---@type table<string, SoundInfo>
local sound_info_per_player = {}
---@type table<string, number>
local last_yaw_per_player = {}
---@type table<string, boolean>
local is_yaw_update_per_player_disabled = {}

local function is_passable(node)
	local def = registered_nodes[node.name]
	return def and def.walkable == false
end

local debug_log = false

local FloorScanState_mt = {}

local fmt_place_distance_vec2 = "place distance %s (%s,%s) 8x8 chunks away"
local fmt_place_distance_unit_min = "place distance (%s,--) 8x8 chunks away"
local fmt_place_distance_unit_max = "place distance (--,%s) 8x8 chunks away"

local floor_filler = {}

---@return FloorScanState
function floor_filler.new()
	---@class FloorScanState
	---@field player_start_yaw number | nil
	---@field max_place_distance number | nil
	---@field min_block_distance number | nil
	local self = {
		fresh = true,
		yaw_max = math.rad(6),
		target_rad = math.rad(360),
		count = 0,
		scan_radians = 0,
		log_min_block_distance = 0,
		log_max_block_distance = 0,
		player_start_yaw = nil,
		max_place_distance = nil,
		min_block_distance = nil,
	}
	self.req_next_reset_scan_radians = 0
	---@param self FloorScanState
	---@param player Player
	---@param player_name string
	---@param yaw number
	function self:run(player, player_name, yaw)
		self.fresh = false

		local plr_name = player_name

		local pos = player:get_pos()
		local dir = normalize(player:get_look_dir())
		local front_dir = normalize(new_vec(dir.x, 0, dir.z)) * 3
		local floor_pos = pos + front_dir + down
		local node_below = get_node_or_nil(floor_pos)
		if not node_below then
			return
		end

		local ctrl = player:get_player_control()
		local config = player_config_mgr.data[plr_name]
		local sound_info = sound_info_per_player[plr_name] or {}
		sound_info.playing_sounds = {}

		-- Place multiple floor blocks in a line in front of player
		local base_pos = pos
		local look_dir = player:get_look_dir()
		local forward_dir = normalize(p(look_dir.x, 0, look_dir.z))

		local line_start = round(base_pos + down + up / 2)
		local max_blocks = config.blocks_per_tick
		local j = 0
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
		local min_block_distance = self.min_block_distance
		local max_place_distance = self.max_place_distance
		local prev_max_place_distance = max_place_distance
		for i = 1, LINE_LENGTH do
			local target_offset = forward_dir * i
			local target_len = target_offset:length()
			if min_block_distance ~= nil and target_len > min_block_distance + 2 * 8 then
				break
			end
			local target_pos = round(line_start + forward_dir * i)

			local node_below = get_node(target_pos)
			if is_passable(node_below) and is_supported(target_pos, placeable_node_name) then
				if j >= max_blocks then
					break
				end
				if try_place_block_from_inventory(player, sound_info, target_pos, LINE_LENGTH) then
					if min_block_distance == nil or target_len < min_block_distance then
						min_block_distance = target_len - target_len % 8
						local log_min_block_distance = min_block_distance / 8
						if log_min_block_distance ~= self.log_min_block_distance then
							local prev_dist = self.log_min_block_distance
							local cur_dist = log_min_block_distance
							if cur_dist >= prev_dist and cur_dist <= prev_dist + 1 then
								goto skip1
							end
							if cur_dist <= prev_dist and cur_dist >= prev_dist - 1 then
								goto skip1
							end
							local max = self.log_max_block_distance
							local min = self.log_min_block_distance
							min = log_min_block_distance
							if max == nil or min > max then
								max = min
								self.show_log_max = true
							end
							self.show_log_min = true
							self.log_max_block_distance = max
							self.log_min_block_distance = min
							core.log("action", fmt_place_distance_vec2:format("min ", self.log_min_block_distance, self.log_max_block_distance))
							::skip1::
						end
					end
					if max_place_distance == nil or target_len > max_place_distance then
						local next_place_nearest = target_len - target_len % 8 + 8
						if max_place_distance ~= next_place_nearest then
							local prev_dist
							local cur_dist
							prev_dist = max_place_distance
							cur_dist = next_place_nearest
							if not prev_dist then
								goto skip2
							end
							if cur_dist >= prev_dist and cur_dist <= prev_dist + 8 then
								goto skip2
							end
							if cur_dist <= prev_dist and cur_dist >= prev_dist - 8 then
								goto skip2
							end
							do
								local log_max_block_dist = cur_dist / 8
								if self.log_min_block_distance == nil or self.log_min_block_distance > log_max_block_dist then
									self.log_min_block_distance = log_max_block_dist
									self.show_log_min = true
								end
								self.log_max_block_distance = log_max_block_dist
								self.show_log_max = true
								core.log("action", fmt_place_distance_vec2:format("max ", self.log_min_block_distance, self.log_max_block_distance))
							end
							::skip2::
							max_place_distance = next_place_nearest
						end
					end
					if self.show_log_min and self.show_log_max then
						local cur_pos = vector.new(self.log_min_block_distance, self.log_max_block_distance, 0)
						if self.last_pos == nil or cur_pos ~= self.last_pos then
							core.log("action", fmt_place_distance_vec2:format("both", self.log_min_block_distance, self.log_max_block_distance))
							self.show_log_min = false
							self.show_log_max = false
							self.last_pos = cur_pos
						end
					end
					j = j + 1
				end
			end
		end
		self.min_block_distance = min_block_distance
		self.max_place_distance = max_place_distance
		if j <= 1 and not is_yaw_update_per_player_disabled[plr_name] then
			local yaw_div
			local log_base = 1 + 0.7 * math.pow(0.95, 1)
			if max_place_distance ~= nil then
				yaw_div = (max_place_distance + 1) * 8 / math.log(self.count + log_base, log_base)
			else
				yaw_div = LINE_LENGTH * 8 / math.log(self.count + log_base, log_base)
			end
			local yaw_speed = self.yaw_max / yaw_div
			local s_yaw = self.scan_radians
			local new_yaw
			if ctrl.sneak then
				new_yaw = s_yaw - yaw_speed
			else
				new_yaw = s_yaw + yaw_speed
			end
			self.scan_radians = new_yaw
			self.count = self.count + 1
			if math.abs(self.scan_radians) > self.target_rad then
				player:set_look_horizontal(self.target_rad + self.player_start_yaw)
				is_yaw_update_per_player_disabled[plr_name] = true
				self.scan_radians = 0
				self.count = 0
				goto update_yaw
			end
			player:set_look_horizontal(self.scan_radians + self.player_start_yaw)
			if vector.length(player:get_velocity()) > 0.05 then
				is_yaw_update_per_player_disabled[plr_name] = true
				self.count = 0
				goto update_yaw
			end
		end
		::update_yaw::
		last_yaw_per_player[plr_name] = yaw
		if j <= 1 then
			time_until_block_place = time_until_block_place + 1
		else
			if debug_log then
				core.log("action", ("more than 1 block placed after %d steps"):format(time_until_block_place))
			end
			time_until_block_place = 0
			-- if self.count > 30 and self.scan_radians > self.req_next_reset_scan_radians then
			-- 	self.req_next_reset_scan_radians = self.scan_radians + 0.01 * 3
			-- 	self.scan_radians = self.scan_radians - self.yaw_max / 4
			-- end
			self.count = math.floor(self.count / 3)
		end
	end
	function self:reset()
		self.fresh = true
		self.player_start_yaw = nil
		self.scan_radians = 0
		self.log_min_block_distance = 0
		self.count = 0
		self.max_place_distance = nil
		self.min_block_distance = nil
		self.req_next_reset_scan_radians = 0
	end
	return self
end

---@type table<string, FloorScanState>
local scan_state_map = {}

core.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	scan_state_map[player_name] = floor_filler.new()
end)

-- globalstep for vein_miner:auto_floor tool
core.register_globalstep(function(dtime)
	core.is_async = true
	for _, player in ipairs(get_connected_players()) do
		local yaw = player:get_look_horizontal()
		if yaw ~= yaw then
			player:set_look_horizontal(0)
			yaw = 0
		end
		local plr_name = player:get_player_name()
		local scan_state = scan_state_map[plr_name]
		local wielded = player:get_wielded_item():get_name()
		if wielded ~= "vein_miner:auto_floor" then
			if not scan_state.fresh then
				last_yaw_per_player[plr_name] = nil
				is_yaw_update_per_player_disabled[plr_name] = false
				scan_state:reset()
			end
			goto continue
		end

		if scan_state.player_start_yaw == nil then
			scan_state.player_start_yaw = yaw
		end

		scan_state:run(player, plr_name, yaw)

		::continue::
	end
	core.is_async = nil
end)

local auto_floor_recipe = {{"default:stick", "", "default:stick"}, {"", "default:cobble", ""}, {"", "default:mese_crystal_fragment", ""}};
core.register_craft({
	output = "vein_miner:auto_floor",
	recipe = auto_floor_recipe,
})
