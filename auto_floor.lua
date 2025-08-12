---@type LuantiCore
local core = core
---@type LuantiCore
local minetest = minetest

local assert = assert
local vector = vector
local ipairs = ipairs

-- localize math
local round = vector.round
local offset = vector.offset
local normalize = vector.normalize
local new_vec = vector.new

local set_node = minetest.set_node
local get_node = minetest.get_node
local get_node_or_nil = minetest.get_node_or_nil
local sound_play = minetest.sound_play
local get_connected_players = minetest.get_connected_players

local registered_nodes = minetest.registered_nodes

---@type VeinMinerGlobal
local vein_miner = vein_miner

local player_config_mgr = vein_miner.player_config_mgr
assert(player_config_mgr, "need vein_miner.player_config_mgr")
minetest.register_tool("vein_miner:auto_floor", {
	description = "Auto-Floor Builder",
	inventory_image = "default_wood.png",
})

local last_floor_data = {}

local up = new_vec(0, 1, 0)
local down = new_vec(0, -1, 0)
local p = new_vec
local cardinal_dirs = vein_miner.CFG.cardinal_dirs
local diagonal_dirs = {p(1, 0, 1), p(-1, 0, 1), p(1, 0, -1), p(-1, 0, -1)}
local support_dirs = {}
for _, dir in ipairs(cardinal_dirs) do
	if dir.y == 0 then
		table.insert(support_dirs, dir)
	end
end
table.insert_all(support_dirs, diagonal_dirs)
local vertical_offsets = {down, up, up * 2}

local function is_node_supporting(node)
	if node == nil then
		return false
	end
	if node.name == "ignore" then
		return false
	end
	local def = registered_nodes[node.name]
	if def and not def.floodable and node.name ~= "air" then
		return true
	end
end

local function is_supported(pos)
	for _, dir in ipairs(support_dirs) do
		for _, vert in ipairs(vertical_offsets) do
			local sup_pos = pos + dir + vert
			local node = get_node_or_nil(sup_pos)
			if is_node_supporting(node) then
				return true
			end
		end
	end
	local npos = pos + new_vec(1, 0, 0)
	local node1 = get_node_or_nil(npos)
	local npos = pos + new_vec(-1, 0, 0)
	local node2 = get_node_or_nil(npos)
	local east_support = is_node_supporting(node1)
	local west_support = is_node_supporting(node2)
	if east_support and west_support then
		return true
	end
	local npos = pos + new_vec(0, 0, 1)
	local node1 = get_node_or_nil(npos)
	local npos = pos + new_vec(0, 0, -1)
	local node2 = get_node_or_nil(npos)
	local north_support = is_node_supporting(node1)
	local south_support = is_node_supporting(node2)
	if north_support and south_support then
		return true
	end
	return false
end

local LINE_LENGTH = 16
---@class SoundInfo
---@field is_playing boolean

---@param player Player
---@param sound_info SoundInfo
---@param target_pos Vector
---@param max_hear_distance number
local function try_place_block_from_inventory(player, sound_info, target_pos, max_hear_distance)
	local inv = player:get_inventory()
	for i = 1, inv:get_size("main") do
		local stack = inv:get_stack("main", i)
		local name = stack:get_name()
		if registered_nodes[name] and name ~= "air" then
			set_node(target_pos, {
				name = name,
			})
			stack:take_item(1)
			inv:set_stack("main", i, stack)
			if not sound_info.is_playing then
				sound_play("default_place_node_hard", {
					pos = target_pos,
					max_hear_distance = max_hear_distance,
				})
				sound_info.is_playing = true
			end
			return true
		end
	end
	return false
end

local max_recheck_count = 0
local sound_info = {}

-- globalstep for vein_miner:auto_floor tool
core.register_globalstep(function(dtime)
	for _, player in ipairs(get_connected_players()) do
		local ctrl = player:get_player_control()
		local name = player:get_player_name()
		local config = player_config_mgr.data[name]
		local cur_sound_info = sound_info[name] or {}
		cur_sound_info.is_playing = false
		local wielded = player:get_wielded_item():get_name()
		if wielded ~= "vein_miner:auto_floor" then
			last_floor_data[name] = nil
			goto continue
		end

		local pos = round(player:get_pos())
		local dir = normalize(player:get_look_dir())
		local front_dir = normalize(new_vec(dir.x, 0, dir.z)) * 3
		local floor_pos = round(pos + up / 2) + front_dir + down
		local node_below = get_node_or_nil(floor_pos)
		if not node_below then
			goto continue
		end

		-- Fall recovery
		local last = last_floor_data[name]
		if last and pos.y < last.y - 1 then
			player:set_pos(new_vec(pos.x, last.y, pos.z))
			local restore_pos = offset(last, 0, -1, 0)
			if try_place_block_from_inventory(player, restore_pos, LINE_LENGTH + 8) then
				last_floor_data[name] = nil
			end
			goto continue
		end

		-- Place multiple floor blocks in a line in front of player
		local base_pos = nil
		if pos.y < 0 then
			base_pos = vector.offset(pos, 0, 1, 0)
		else
			base_pos = vector.offset(pos, 0, 0.25, 0)
		end
		local look_dir = player:get_look_dir()
		local forward_dir = vector.normalize(vector.new(look_dir.x, 0, look_dir.z))

		local did_place_some = false
		local j = 0
		for i = 1, LINE_LENGTH do
			local offset_vec = vector.multiply(forward_dir, i)
			local target_pos = base_pos + offset_vec + down

			local node_below = minetest.get_node(target_pos)
			if node_below.name == "air" and is_supported(target_pos) then
				if j >= config.blocks_per_tick then
					break
				end
				if try_place_block_from_inventory(player, cur_sound_info, target_pos, LINE_LENGTH + 8) then
					j = j + 1
					did_place_some = true
				end
			end
		end

		if did_place_some then
			last_floor_data[name] = vector.new(pos)
		end
		::continue::
	end
end)

local auto_floor_recipe = {{"default:stick", "", "default:stick"}, {"", "default:cobble", ""}, {"", "default:mese_crystal_fragment", ""}};
minetest.register_craft({
	output = "vein_miner:auto_floor",
	recipe = auto_floor_recipe,
})
