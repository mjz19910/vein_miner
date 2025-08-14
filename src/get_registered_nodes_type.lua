local registered_nodes = core.registered_nodes

local function format_table(tbl)
	if type(tbl[1]) == "table" then
		local ntbl = {}
		for i, v in ipairs(tbl) do
			ntbl[i] = format_table(v)
		end
		return format_table(ntbl)
	end
	return ("{%s}"):format(table.concat(tbl, ","))
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

local FixedNodeBox = {
	known = {
		type = true,
		fixed = true,
	},
}
FixedNodeBox.format_fixed = function(box_info)
	if type(box_info[1]) == "table" then
		return format_table(box_info)
	end
	return ("{%s}"):format(table.concat(box_info, ","))
end
---@param value FixedNodeBox
FixedNodeBox.format = function(value)
	local tclone = {}
	local show_clone = false
	for k, v in pairs(value) do
		if FixedNodeBox.known[k] then
			goto n
		end
		tclone[k] = v
		show_clone = true
		::n::
	end
	if show_clone then
		core.log("error", "FixedNodeBox " .. core.serialize(tclone):sub(8))
	end
	return ("{fixed=%s}"):format(FixedNodeBox.format_fixed(value.fixed))
end

local NodeBox = {
	known = {},
}

local ConnectedNodeBox = {
	known = {
		type = true,
		fixed = true,
		connect_left = true,
		connect_right = true,
		connect_front = true,
		connect_back = true,
	},
}

NodeBox.format = function(value)
	if value.type == "fixed" then
		return FixedNodeBox.format(value)
	elseif value.type == "regular" then
		local tclone = {}
		local show_clone = false
		for k, v in pairs(value) do
			if k == "type" then
				goto n
			end
			tclone[k] = v
			show_clone = true
			::n::
		end
		if show_clone then
			core.log("error", "RegularNodeBox " .. core.serialize(tclone):sub(8))
		end
		return format_table(value)
	elseif value.type == "connected" then
		local tclone = {}
		local show_clone = false
		for k, v in pairs(value) do
			if ConnectedNodeBox.known[k] then
				goto n
			end
			tclone[k] = v
			show_clone = true
			::n::
		end
		if show_clone then
			core.log("error", "ConnectedNodeBox " .. core.serialize(tclone):sub(8))
		end
		local tbl_out = {}
		if value.type ~= nil then
			table.insert(tbl_out, ('type="%s"'):format(value.type))
		end
		if value.fixed ~= nil then
			table.insert(tbl_out, ("fixed=%s"):format(FixedNodeBox.format_fixed(value.fixed)))
		end
		if value.connect_left ~= nil then
			table.insert(tbl_out, "connect_left=" .. FixedNodeBox.format_fixed(value.connect_left))
		end
		if value.connect_right ~= nil then
			table.insert(tbl_out, "connect_right=" .. FixedNodeBox.format_fixed(value.connect_right))
		end
		if value.connect_front ~= nil then
			table.insert(tbl_out, "connect_front=" .. FixedNodeBox.format_fixed(value.connect_front))
		end
		if value.connect_back ~= nil then
			table.insert(tbl_out, "connect_back=" .. FixedNodeBox.format_fixed(value.connect_back))
		end
		return ("{%s}"):format(table.concat(tbl_out, ","))
	else
		core.log("error", "NodeBox.type = " .. core.serialize(value.type):sub(8))
	end
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
	node_box = [[NodeBox]],
	selection_box = [[NodeBox]],
	collision_box = [[NodeBox]],
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
				-- core.log("action", name_info .. " tiles " .. table_array.format(node.tiles, TileDef.format))
				goto n
			end
			if key2 == "special_tiles" then
				-- core.log("action", name_info .. " special tiles " .. table_array.format(node.special_tiles, TileDef.format))
				goto n
			end
			if key2 == "node_box" then
				-- core.log("action", name_info .. " node box " .. NodeBox.format(val2))
				goto n
			end
			if key2 == "selection_box" then
				-- core.log("action", name_info .. " selection box " .. NodeBox.format(val2))
				goto n
			end
			if key2 == "collision_box" then
				NodeBox.format(val2)
				-- core.log("action", name_info .. " collision box " .. NodeBox.format(val2))
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
