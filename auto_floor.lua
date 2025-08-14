---@type LuantiCore
local core = core

local assert = assert
---@type VectorModule
local vector = vector
local ipairs = ipairs

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

---@type VeinMinerGlobal
local vein_miner = vein_miner

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
	if def and not def.floodable and def.walkable then
		return true
	end
end

---@param pos Vector
local function is_supported(pos)
	local below_pos = pos + new_vec(0, -1, 0)
	local below_node = get_node_or_nil(below_pos)
	if not below_node or (below_node.name ~= "default:dirt" and core.get_item_group(below_node.name, "soil") > 0) then
		return false
	end
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
		if def and name ~= "air" and not def.groups.falling_node then
			local cur_node = core.get_node(target_pos)
			if cur_node and cur_node.name ~= "air" then
				return false
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

local dbg_count = 0
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

-- globalstep for vein_miner:auto_floor tool
core.register_globalstep(function(dtime)
	for _, player in ipairs(get_connected_players()) do
		local yaw = player:get_look_horizontal()
		if yaw ~= yaw then
			player:set_look_horizontal(0)
			yaw = 0
		end
		local name = player:get_player_name()
		local wielded = player:get_wielded_item():get_name()
		if wielded ~= "vein_miner:auto_floor" then
			dbg_count = 0
			last_yaw_per_player[name] = nil
			is_yaw_update_per_player_disabled[name] = false
			goto continue
		end

		local pos = player:get_pos()
		local dir = normalize(player:get_look_dir())
		local front_dir = normalize(new_vec(dir.x, 0, dir.z)) * 3
		local floor_pos = pos + front_dir + down
		local node_below = get_node_or_nil(floor_pos)
		if not node_below then
			goto continue
		end

		local ctrl = player:get_player_control()
		local config = player_config_mgr.data[name]
		local sound_info = sound_info_per_player[name] or {}
		sound_info.playing_sounds = {}

		-- Place multiple floor blocks in a line in front of player
		local base_pos = pos
		local look_dir = player:get_look_dir()
		local forward_dir = normalize(p(look_dir.x, 0, look_dir.z))

		local line_start = base_pos + down
		local max_blocks = config.blocks_per_tick
		local j = 0
		for i = 1, LINE_LENGTH do
			local target_pos = line_start + forward_dir * i

			local node_below = get_node(target_pos)
			if true or is_passable(node_below) and is_supported(target_pos) then
				if j >= max_blocks then
					break
				end
				if try_place_block_from_inventory(player, sound_info, target_pos, LINE_LENGTH) then
					j = j + 1
				end
			end
		end
		if j <= 1 then
			time_until_block_place = time_until_block_place + 1
		else
			core.log("action", ("more than 1 block placed after %d steps"):format(time_until_block_place))
			time_until_block_place = 0
		end
		if j <= 1 and not is_yaw_update_per_player_disabled[name] then
			local yaw_max = math.pow(9 / 10, 1) * 2
			local yaw_speed = yaw_max * math.log(dbg_count + 1, 2) / LINE_LENGTH
			local new_yaw = math.rad((math.deg(yaw) + yaw_speed) % 360)
			if last_yaw_per_player[name] and new_yaw + 0.1 < last_yaw_per_player[name] then
				is_yaw_update_per_player_disabled[name] = true
				player:set_look_horizontal(0)
				goto continue
			end
			player:set_look_horizontal(new_yaw)
			dbg_count = dbg_count + 1
			if vector.length(player:get_velocity()) > 0.3 then
				is_yaw_update_per_player_disabled[name] = true
				goto continue
			end
		elseif not is_yaw_update_per_player_disabled[name] then
			if time_until_block_place > 12 then
				local new_yaw = math.rad(math.deg(yaw) - 0.8)
				player:set_look_horizontal(new_yaw)
				yaw = new_yaw
			end
			dbg_count = math.floor(dbg_count / (math.log(dbg_count + 1, 2) * 2 + 3))
		else
			dbg_count = 0
		end
		last_yaw_per_player[name] = yaw
		::continue::
	end
end)

local auto_floor_recipe = {{"default:stick", "", "default:stick"}, {"", "default:cobble", ""}, {"", "default:mese_crystal_fragment", ""}};
core.register_craft({
	output = "vein_miner:auto_floor",
	recipe = auto_floor_recipe,
})

local function format_table(tbl) return ("[%s]"):format(table.concat(tbl, ",")) end

core.register_on_mods_loaded(function()
	local key1 = next(registered_nodes)
	local node = registered_nodes[key1]
	for key2, val2 in pairs(node) do
		local name_info = "node name " .. node.name
		if key2 == "type" then
			if node.type ~= "node" then
				core.log("error", "invalid registered node type is not node " .. key1 .. " has type of " .. node.type)
			end
			goto n
		end
		if key2 == "mod_origin" then
			core.log("action", "mod origin for " .. name_info .. " is " .. node.mod_origin)
			goto n
		end
		if key2 == "name" then
			if node.name ~= key1 then
				core.log("error", ("invalid registered node name mismatch %s and %s"):format(node.name, key1))
			end
			goto n
		end
		if key2 == "allow_metadata_inventory_put" then
			goto n
		end
		if key2 == "tiles" then
			core.log("action", name_info .. " tiles " .. format_table(node.tiles))
			goto n
		end
		if key2 == "selection_box" then
			local sel_box = node.selection_box
			if sel_box.type ~= "fixed" then
				core.log("warning", name_info .. " selection box (not fixed) " .. core.serialize(sel_box))
			end
			core.log("action", name_info .. " selection box " .. format_table(sel_box.fixed))
			goto n
		end
		if key2 == "light_source" then
			core.log("action", name_info .. " light source " .. node.light_source)
			goto n
		end
		local skip_keys = {
			is_ground_content = 1,
			paramtype2 = 1,
			description = 1,
			sounds = 1,
			can_dig = 1,
			on_rightclick = 1,
			groups = 1,
			drawtype = 1,
		}
		if skip_keys[key2] == 1 then
			goto n
		end
		do
			core.log("warning", ('registered_nodes["%s"].%s'):format(key1, key2))
			core.log("warning", "value of " .. core.serialize(val2))
			break
		end
		::n::
	end
end)
