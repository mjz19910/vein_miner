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

local function format_table(tbl)
	if type(tbl[1]) == "table" then
		local ntbl = {}
		for i, v in ipairs(tbl) do
			ntbl[i] = format_table(v)
		end
		return format_table(ntbl)
	end
	return ("[%s]"):format(table.concat(tbl, ","))
end

local table_array = {}
table_array.format = function(value, next_format, ...)
	local ntbl = {}
	for i, v in ipairs(value) do
		ntbl[i] = next_format(v, ...)
	end
	return ("[%s]"):format(table.concat(ntbl, ","))
end
local TileAnimationParams = {
	known = {
		type = true,
		aspect_w = true,
		aspect_h = true,
		length = true,
	},
}
---@param value TileAnimationParams
TileAnimationParams.format = function(value)
	local tclone = {}
	local show_clone = false
	for k, v in pairs(value) do
		if TileAnimationParams.known[k] then
			goto n
		end
		tclone[k] = v
		show_clone = true
		::n::
	end
	if show_clone then
		core.log("error", "TileAnimationParams " .. core.serialize(tclone):sub(8))
	end
	local tbl_out = {}
	if value.type then
		table.insert(tbl_out, ('type="%s"'):format(value.type))
	end
	if value.aspect_w then
		table.insert(tbl_out, ('aspect_w=%d'):format(value.aspect_w))
	end
	if value.aspect_h then
		table.insert(tbl_out, ('aspect_h=%d'):format(value.aspect_h))
	end
	if value.length ~= nil then
		table.insert(tbl_out, ('backface_culling=%d'):format(value.length))
	end
	return ("{%s}"):format(table.concat(tbl_out, ","))
end
local TileDef = {
	known = {
		name = true,
		align_style = true,
		backface_culling = true,
		animation = true,
		tileable_vertical = true,
	},
}
TileDef.format = function(value)
	if type(value) == "string" then
		return ('"%s"'):format(value)
	end
	local tclone = {}
	local show_clone = false
	for k, v in pairs(value) do
		if TileDef.known[k] then
			goto n
		end
		tclone[k] = v
		show_clone = true
		::n::
	end
	if show_clone then
		core.log("error", "TileDef " .. core.serialize(tclone):sub(8))
	end
	local tbl_out = {}
	if value.name ~= nil then
		table.insert(tbl_out, ('name="%s"'):format(value.name))
	end
	if value.align_style ~= nil then
		table.insert(tbl_out, ('align_style="%s"'):format(value.align_style))
	end
	if value.backface_culling ~= nil then
		table.insert(tbl_out, ('backface_culling=%s'):format(tostring(value.backface_culling)))
	end
	if value.tileable_vertical ~= nil then
		table.insert(tbl_out, ('tileable_vertical=%s'):format(tostring(value.tileable_vertical)))
	end
	if value.animation ~= nil then
		table.insert(tbl_out, ('animation=%s'):format(TileAnimationParams.format(value.animation)))
	end
	return ("{%s}"):format(table.concat(tbl_out, ","))
end

local FixedNodeBox = {}
---@param value FixedNodeBox
FixedNodeBox.format = function(value)
	if value.type == "fixed" then
		local box_info = value.fixed
		if type(box_info[1]) == "table" then
			return ("FixedNodeBox(%s)"):format(format_table(value.fixed))
		end
		return ("FixedNodeBox([%s])"):format(table.concat(value.fixed, ","))
	else
		return ("[[%s]]"):format(core.serialize(value))
	end
	return ""
end

local function lua_serialize(value)
	if type(value) == "string" then
		return ('"%s"'):format(core.serialize(value))
	end
	return ("(function() %s end)()"):format(core.serialize(value))
end

local fmt_kv = 'registered_nodes["%s"]. %s = %s'

local ts = {
	---@type boolean
	boolean = "boolean",
	---@type integer
	integer = "integer",
	---@type string
	string = "string",
	---@type number
	number = "number",
	Vector = vector.zero(),
}

local valid_drawtype_set = {
	mesh = true,
	liquid = true,
	nodebox = true,
	airlike = true,
	raillike = true,
	firelike = true,
	signlike = true,
	glasslike = true,
	plantlike = true,
	flowingliquid = true,
	plantlike_rooted = true,
	allfaces_optional = true,
	glasslike_framed_optional = true,
}

local skip_keys = {
	is_ground_content = ts.boolean,
	description = ts.string,
	_tnt_loss = ts.integer,
	inventory_image = ts.string,
	stack_max = ts.integer,
	waving = ts.integer,
	pointable = ts.boolean,
	diggable = ts.boolean,
	wield_image = ts.string,
	gain_open = ts.number,
	sunlight_propagates = ts.boolean,
	legacy_facedir_simple = ts.boolean,
	liquid_renewable = ts.boolean,
	walkable = ts.boolean,
	drop = ts.string,
	place_param2 = ts.integer,
	buildable_to = ts.boolean,
	mesecon_wire = ts.boolean,
	__mesecon_basename = ts.string,
	legacy_mineral = ts.boolean,
	sound_open = ts.string,
	minlight = ts.integer,
	visual_scale = ts.integer,
	gain_close = ts.number,
	floodable = ts.boolean,
	drowning = ts.integer,
	sound_close = ts.string,
	delayer_onstate = ts.string,
	legacy_wallmounted = ts.boolean,
	node_placement_prediction = ts.string,
	node_dig_prediction = ts.string,
	mesh = ts.string,
	material = ts.string,
	drawer_stack_max_factor = ts.integer,
	air_equivalent = ts.boolean,
	liquid_alternative_flowing = ts.string,
	liquid_alternative_source = ts.string,
	liquid_viscosity = ts.integer,
	pressureplate_basename = ts.string,
	delayer_time = ts.number,
	liquid_range = ts.number,
	protected = ts.boolean,
	delayer_offstate = ts.string,
	next_plant = ts.string,
	liquids_pointable = ts.boolean,
	is_luacontroller = ts.boolean,
	wield_scale = ts.Vector,
	tile_front = ts.string,
	tile_side = ts.string,
	_gate = ts.string,
	maxlight = ts.integer,
	damage_per_second = ts.integer,
	is_burnt = ts.boolean,
	climbable = ts.boolean,
	is_vertical_conductor = ts.boolean,
	onstate = ts.string,
	offstate = ts.string,
	inputnumber = ts.integer,
	_gate_sound = ts.string,
	tiles = "TileDef[]",
	special_tiles = "TileDef[]",
	connects_to = "string[]",
	__mesecon_state = [['"off"']],
	paramtype = [['"none"' | '"light"']],
	liquidtype = [['"source"' | '"flowing"']],
	paramtype2 = [['"facedir"'|'"4dir"'|'"flowingliquid"']],
	use_texture_alpha = [['"clip"' | '"blend"']],
	drawtype = [['"nodebox"' | '"liquid"' | '"airlike"' | '"plantlike"' | '"allfaces_optional"']],
	visual = [['"mesh"']],
	on_use = [[fun()]],
	assess = [[fun()]],
	on_dig = [[fun()]],
	can_dig = [[fun()]],
	on_drop = [[fun()]],
	on_burn = [[fun()]],
	on_timer = [[fun()]],
	on_blast = [[fun()]],
	on_punch = [[fun()]],
	on_place = [[fun()]],
	on_flood = [[fun()]],
	on_ignite = [[fun()]],
	on_rotate = [[fun()]],
	test_build = [[fun()]],
	on_key_use = [[fun()]],
	technic_run = [[fun()]],
	mvps_sticky = [[fun()]],
	execute_dig = [[fun()]],
	on_destruct = [[fun()]],
	on_construct = [[fun()]],
	execute_build = [[fun()]],
	execute_eject = [[fun()]],
	on_rightclick = [[fun()]],
	after_dig_node = [[fun()]],
	after_destruct = [[fun()]],
	damage_creatures = [[fun()]],
	after_place_node = [[fun()]],
	on_receive_fields = [[fun()]],
	_digtron_formspec = [[fun()]],
	on_skeleton_key_use = [[fun()]],
	on_metadata_inventory_put = [[fun()]],
	on_metadata_inventory_take = [[fun()]],
	on_metadata_inventory_move = [[fun()]],
	allow_metadata_inventory_take = [[fun()]],
	allow_metadata_inventory_move = [[fun()]],
	node_box = [[FixedNodeBox]],
	selection_box = [[FixedNodeBox]],
	collision_box = [[FixedNodeBox]],
	groups = [[table<string, integer>]],
	mesecons = [[MeseconsData]],
	post_effect_color = [[RGBAColor]],
	digiline = [[DigilineData]],
	door = [[table]],
	connect_sides = [[table]],
	soil = [[SoilData]],
	fertility = [[table]],
	virtual_portstates = [[MeseconPortStates]],
}

core.register_on_mods_loaded(function()
	local quit = false
	for key1, node in pairs(registered_nodes) do
		for key2, val2 in pairs(node) do
			if key2 == "visual" then
				if val2 == "mesh" then
					goto n
				end
				core.log("action", fmt_kv:format(node.name, key2, lua_serialize(val2)))
				goto n
			end
			local name_info = "node name " .. node.name
			if key2 == "type" then
				if node.type ~= "node" then
					core.log("error", "invalid registered node type is not node " .. key1 .. " has type of " .. node.type)
				end
				goto n
			end
			if key2 == "mod_origin" then
				-- core.log("action", "mod origin for " .. name_info .. " is " .. node.mod_origin)
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
				table_array.format(node.tiles, TileDef.format)
				-- core.log("action", name_info .. " tiles " .. table_array.format(node.tiles, TileDef.format))
				goto n
			end
			if key2 == "special_tiles" then
				-- core.log("action", name_info .. " special tiles " .. table_array.format(node.special_tiles, TileDef.format))
				goto n
			end
			if key2 == "node_box" then
				-- core.log("action", name_info .. " node box " .. FixedNodeBox.format(val2))
				goto n
			end
			if key2 == "selection_box" then
				-- core.log("action", name_info .. " selection box " .. FixedNodeBox.format(val2))
				goto n
			end
			if key2 == "collision_box" then
				-- core.log("action", name_info .. " collision box " .. FixedNodeBox.format(val2))
				goto n
			end
			if key2 == "light_source" then
				-- core.log("action", name_info .. " light source " .. node.light_source)
				goto n
			end
			if key2 == "use_texture_alpha" then
				if val2 == "clip" or val2 == "blend" or val2 == "opaque" then
					goto n
				end
				core.log("action", fmt_kv:format(node.name, key2, lua_serialize(val2)))
				goto n
			end
			if key2 == "liquidtype" then
				if val2 == "source" then
					goto n
				end
				if val2 == "flowing" then
					goto n
				end
				core.log("action", fmt_kv:format(node.name, key2, lua_serialize(val2)))
				goto n
			end
			if key2 == "paramtype" then
				if val2 == "none" then
					goto n
				end
				if val2 == "light" then
					goto n
				end
				core.log("action", fmt_kv:format(node.name, key2, lua_serialize(val2)))
				goto n
			end
			if key2 == "drawtype" then
				if not valid_drawtype_set[val2] then
					core.log("action", fmt_kv:format(node.name, key2, lua_serialize(val2)))
				end
				goto n
			end
			if key2 == "paramtype2" then
				if val2 == "facedir" then
					goto n
				end
				if val2 == "4dir" then
					goto n
				end
				if val2 == "wallmounted" or val2 == "leveled" then
					goto n
				end
				if val2 == "flowingliquid" or val2 == "meshoptions" then
					goto n
				end
				core.log("action", fmt_kv:format(node.name, key2, lua_serialize(val2)))
				goto n
			end
			if key2 == "sounds" then
				if false then
					local str_fmt = "registered_nodes[\"%s\"].%s[\"%s\"]=%s"
					for sound_key, sound in pairs(val2) do
						core.log("action", str_fmt:format(node.name, key2, sound_key, lua_serialize(sound)))
					end
				end
				goto n
			end
			if skip_keys[key2] ~= nil then
				goto n
			end
			do
				core.log("warning", fmt_kv:format(key1, key2, lua_serialize(val2)))
				quit = true
				break
			end
			::n::
		end
		if quit then
			break
		end
	end
end)
