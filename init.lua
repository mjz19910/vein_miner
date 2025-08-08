vein_miner = {
	deque = {}
}
dofile(minetest.get_modpath("vein_miner") .. "/deque.lua")

local S = minetest.get_translator("vein_miner")

-- Maximum number of nodes that can be vein mined at once
local MAX_MINED_NODES = 188
-- Maximum light scan distance
local light_scan_dist = 1

-- PERMISSIONS
-- If true, prevent registered nodes in rNodes from being vein mined.
-- If false, prevent unregistered nodes in rNodes from being vein mined.
local nodeBlacklist = false
-- Blacklisted or whitelisted nodes for vein mining
local rNodes = {}

-- Whether or not to use a blacklist instead of a whitelist for tools
local toolBlacklist = false
-- Registered tools
local rTools = {}

minetest.register_on_mods_loaded(function()
	-- Get settings

	-- Check legacy settings
	local allow_ores = minetest.settings:get_bool("allow_ores")
	local allow_trees = minetest.settings:get_bool("allow_trees")
	local allow_all = minetest.settings:get_bool("allow_all")

	-- Fetch settings
	MAX_MINED_NODES = tonumber(minetest.settings:get("vein_miner_max_nodes"))

	-- Set MAX_MINED_NODES to default value in case getting the setting doesn't work
	if MAX_MINED_NODES == nil then
		MAX_MINED_NODES = 188
	end

	-- Use namespaces settings if legacy settings are unset
	if allow_ores == nil then
		allow_ores = minetest.settings:get_bool("vein_miner_allow_ores", true)
	end

	if allow_trees == nil then
		allow_trees = minetest.settings:get_bool("vein_miner_allow_trees", false)
	end

	if allow_all == nil then
		allow_all = minetest.settings:get_bool("vein_miner_allow_all", false)
	end

	-- Initialize tool whitelist with registered tools
	for name, def in pairs(minetest.registered_tools) do
		rTools[def.name] = true
	end

	-- Initialize whitelist for registered nodes
	if allow_all then
		-- wipe rNodes just in case
		for k, v in pairs(rNodes) do
			rNodes[k] = nil
		end
		nodeBlacklist = true
		for name, def in pairs(core.registered_nodes) do
			if def.groups.xray_node then
				rNodes[name] = true
			end
		end
	else
		if allow_ores then
			local ore_patterns = {":stone_with_", ":mineral_", "_ore$"}
			for name, def in pairs(core.registered_ores) do
				local node_name = def.ore
				for _, ore_pattern in pairs(ore_patterns) do
					if string_match(node_name, ore_pattern) ~= nil then
						rNodes[node_name] = true
						break
					end
				end
			end
		end

		-- Register tree nodes
		if allow_trees then
			for name, def in pairs(core.registered_nodes) do
				if def.groups.tree ~= nil then
					local node_name = def.name
					rNodes[node_name] = true
				end
			end
		end
	end

	light_scan_dist = tonumber(core.settings:get("vein_miner_light_scan_distance"))
end)

local modpath = core.get_modpath("vein_miner")

local log_work_start = false

dofile(modpath .. "/src/config.lua")
dofile(modpath .. "/src/aabb.lua")
dofile(modpath .. "/src/helpers.lua")
dofile(modpath .. "/src/player_config.lua")

local floor = math.floor
local ceil = math.ceil
local string_match = string.match

local log_error = vein_miner.h.log_error
local log_warning = vein_miner.h.log_warning
local log_action = vein_miner.h.log_action

local CFG = vein_miner.CFG

local ignored_nodes = CFG.IGNORED_NODES
local light_nodes = CFG.LIGHT_NODES
local mine_only_groups = CFG.MINE_ONLY_GROUPS
local mine_only_cur_set = {}
for k, v in pairs(CFG.MINE_ONLY_CUR_SET) do
	mine_only_cur_set[v] = true
end
local mine_only_group_sets = vein_miner.h.generate_mine_only_sets(mine_only_groups, mine_only_cur_set)
local surface_nodes = CFG.SURFACE_NODES

local storage = core.get_mod_storage()

local vec_dirs = CFG.VEC_DIRS
local seen_dir_set = {}
local joined_dirs = {}
local joined_dirs_set = {}
local known_dir_set = {}

local light_scan_data = {}
local function light_scan_reset(name) light_scan_data[name] = {} end

local vein_miner_current_state = {}

local BlockDigger = {}
local check_for_falling_neighbors = {vector.new(-1, -1, 0), vector.new(1, -1, 0), vector.new(0, -1, -1), vector.new(0, -1, 1),
                                     vector.new(0, -1, 0), vector.new(-1, 0, 0), vector.new(1, 0, 0), vector.new(0, 0, -1),
                                     vector.new(0, 0, 1), vector.new(0, 1, 0)}
local possible_flow_directions = {vector.new(-1, 0, 0), vector.new(1, 0, 0), vector.new(0, 0, -1), vector.new(0, 0, 1), vector.new(0, 1, 0)}
local liquid_set = {
	["default:water_source"] = true,
	["default:water_flowing"] = true,
	["default:lava_source"] = true,
	["default:lava_flowing"] = true
}
-- A tiny helper so we don’t repeat the same table‐look‑ups
local function is_falling(name)
	local def = core.registered_nodes[name]
	return def and ((def.groups and def.groups.falling_node) or def.liquidtype == "source" or def.liquidtype == "flowing")
end
local function is_liquid_source(name)
	local def = core.registered_nodes[name]
	return def and def.liquidtype == "source"
end
local sticky_nodes = CFG.sticky_nodes

-- Function to check if a node is sticky
local function is_sticky_node(name) return sticky_nodes[name] == true end

-- Get all 6 adjacent positions
local function get_adjacent_positions(pos)
	return {vector.offset(pos, 1, 0, 0), vector.offset(pos, -1, 0, 0), vector.offset(pos, 0, 1, 0), vector.offset(pos, 0, -1, 0),
         vector.offset(pos, 0, 0, 1), vector.offset(pos, 0, 0, -1)}
end

-- Function to check if a position is stuck to a sticky neighbor
local function is_stuck_to_sticky(pos)
	for _, adj_pos in ipairs(get_adjacent_positions(pos)) do
		local node = minetest.get_node(adj_pos)
		if is_sticky_node(node.name) then
			return true
		end
	end
	return false
end
function BlockDigger.should_dig(node, pos)
	if node.name == "air" then
		return false
	end
	if table.contains(light_nodes, node.name) then
		return true
	end
	if not is_sticky_node(node.name) and is_stuck_to_sticky(pos) then
		return false
	end
	local above = vector.offset(pos, 0, 1, 0)
	local above_node = core.get_node(above)
	if above_node.name == "default:snow" then
		return true -- falling block that we want to fall
	end
	if is_falling(above_node.name) then
		return false
	end
	for _, off in ipairs(possible_flow_directions) do
		local npos = vector.add(pos, off)
		if is_liquid_source(core.get_node(npos).name) then
			return false -- digging here may cause liquid to flow
		end
	end
	for _, off in ipairs(check_for_falling_neighbors) do
		local npos = vector.add(pos, off)
		local above_node = core.get_node(npos)
		if is_falling(above_node.name) then
			local below = vector.offset(npos, 0, -1, 0)
			local below_node = core.get_node(below)
			if below_node.name == "air" or liquid_set[below_node.name] then
				return false -- this falling node is unsupported
			end
		end
	end
	return true -- safe to mine
end
-- function BlockDigger.should_dig(node)
-- 	if node.name == "air" then
-- 		return false
-- 	end
-- 	return true
-- end

local light_scan_boost = 0

local function is_node_vein_diggable(nodeName, wieldedName)
	local nodeCheck = nodeBlacklist and true or false
	local toolCheck = toolBlacklist and true or false

	-- check nodes
	if next(rNodes) then
		local isNodeInRNodes = (rNodes[nodeName] ~= nil) and true or false
		nodeCheck = (isNodeInRNodes ~= nodeBlacklist)
	end

	-- check tools
	if next(rTools) then
		local isToolInRTools = (rTools[wieldedName] ~= nil) and true or false
		toolCheck = (isToolInRTools ~= toolBlacklist)
	end

	return nodeCheck and toolCheck
end

function table.contains(table, element)
	for _, value in pairs(table) do
		if value == element then
			return true
		end
	end
	return false
end

-- Update wielded item
local function update_wielded_item(player, wielded)
	local tool = player:get_wielded_item()
	if tool:get_name() == wielded:get_name() then
		local wear_amount = 1 - (wielded:get_wear() / 65535)
		if wear_amount < 0.85 then
			log_action("high wear action " .. wear_amount)
		end
		wielded:set_wear(0)
		player:set_wielded_item(wielded)
	end
end

local function handle_unexpected_target_nodes(target_nodes, node_name)
	if table.contains(light_nodes, node_name) then
		return "add_current"
	end
	if not table.contains(target_nodes, node_name) then
		if table.contains(surface_nodes, node_name) then
			return "only_current"
		end
		if table.contains(ignored_nodes, node_name) then
			return "inc_mine_skip"
		end
		if mine_only_cur_set[node_name] then
			return "mine_only_cur"
		end
		return "error"
	end
	return "continue"
end

local node_scan_options_cache = {}
local function get_real_scan_options(node_name, options)
	options = options or {}
	if table.contains(light_nodes, node_name) then
		options.light = true
	end
	local def = ItemStack(node_name):get_definition()
	if def.liquidtype == "source" then
		options.liquid = true
	end
	if def.liquidtype == "flowing" then
		options.liquid = true
	end
	return options
end
local function get_scan_options(node_name, options)
	options = options or {}
	if options.user then
		return get_real_scan_options(node_name, options)
	end
	if node_scan_options_cache[node_name] ~= nil then
		return node_scan_options_cache[node_name]
	end
	options = get_real_scan_options(node_name)
	node_scan_options_cache[node_name] = options
	return options
end

for i, dir in pairs(vec_dirs) do
	for j, dir2 in pairs(vec_dirs) do
		local dir_res = dir + dir2
		local h = core.hash_node_position(dir_res)
		if not joined_dirs_set[h] then
			joined_dirs_set[h] = true
			table.insert(joined_dirs, dir_res)
		end
	end
end
local function fmt_layer(layer) return "y=" .. (layer * 8) .. ".." .. (layer * 8 + 7) end

local function is_valid_pos_to_iter(pos, player_name)
	local config = p_config.data[player_name]
	local maxy = config.maxy
	local miny = config.miny
	if pos.y > miny and pos.y <= maxy then
		return true
	end
	return false
end

local function add_pos_to_queue(state, node_name, pos, options)
	local h = core.hash_node_position(pos)
	if state.queued_set[h] then
		return
	end
	state.queued_set[h] = true
	state.queue:push_right({
		node_name = node_name,
		pos = pos,
		options = get_scan_options(node_name, options)
	})
end

local function filter_liquid(state, pos)
	local node = core.get_node(pos)
	if not liquid_set[node.name] then
		return
	end

	-- CONFIG
	local LIMIT = 64 * 6

	-- STATE
	local visited = {}
	local qx, qy, qz = {}, {}, {}
	local q_head, q_tail = 1, 1
	local queue_count = 0

	local minx, miny, minz = pos.x, pos.y, pos.z
	local maxx, maxy, maxz = pos.x, pos.y, pos.z

	-- QUEUE UTILS
	local function push(x, y, z)
		qx[q_tail], qy[q_tail], qz[q_tail] = x, y, z
		q_tail = q_tail + 1
	end

	local function maybe_enqueue(x, y, z)
		local hash = core.hash_node_position({
			x = x,
			y = y,
			z = z
		})
		if not visited[hash] then
			visited[hash] = true
			push(x, y, z)
		end
	end

	-- SEED
	visited[core.hash_node_position(pos)] = true
	push(pos.x, pos.y, pos.z)

	-- FLOOD-FILL
	while q_head < q_tail do
		local x, y, z = qx[q_head], qy[q_head], qz[q_head]
		q_head = q_head + 1

		local node = core.get_node(vector.new(x, y, z))
		if not liquid_set[node.name] then
			goto continue
		end

		queue_count = queue_count + 1
		if queue_count > LIMIT then
			goto continue
		end

		-- bounds
		if x < minx then
			minx = x
		elseif x > maxx then
			maxx = x
		end
		if y < miny then
			miny = y
		elseif y > maxy then
			maxy = y
		end
		if z < minz then
			minz = z
		elseif z > maxz then
			maxz = z
		end

		maybe_enqueue(x + 1, y, z)
		maybe_enqueue(x - 1, y, z)
		maybe_enqueue(x, y, z + 1)
		maybe_enqueue(x, y, z - 1)

		::continue::
	end

	if next(visited) == nil then
		return
	end

	local minp = vector.new(minx, miny, minz)
	local maxp = vector.new(maxx, maxy, maxz)

	-- SETUP VM + CONTENT IDS
	local vm = VoxelManip()
	local cid = core.get_content_id
	local cid_air = cid("air")
	local cid_wall = cid("wool:green")

	local cids_replace = {
		[cid("default:water_source")] = true,
		[cid("default:water_flowing")] = true,
		[cid("default:lava_source")] = true,
		[cid("default:lava_flowing")] = true
	}

	local cids_source = {
		[cid("default:water_source")] = true,
		[cid("default:lava_source")] = true
	}

	local emin, emax
	local area
	local data

	-- EXPAND LOGIC
	local function expand_axis(minp, maxp, axis, limit, skip_flag)
		local function axis_iter(start, is_max)
			local pos = vector.new()
			pos[axis] = start
			for a = minp[axis], maxp[axis] do
				for b = minp.y, maxp.y do
					pos[axis] = a
					pos.y = b
					local idx = area:index(pos.x, pos.y, pos.z)
					if cids_replace[data[idx]] then
						if is_max then
							maxp[axis] = maxp[axis] + 1
						else
							minp[axis] = minp[axis] - 1
						end
						if (maxp[axis] - minp[axis]) < limit then
							return true
						end
						skip_flag[1] = true
						return false
					end
				end
			end
			return false
		end

		if axis_iter(minp[axis], false) or axis_iter(maxp[axis], true) then
			return true
		end

		return false
	end

	-- Axis expansion with feedback loop
	local skip_x, skip_y, skip_z = {false}, {false}, {false}
	local function loop_expand()
		local size = maxp - minp
		log_action(("filter liquid bounds %s %s %s"):format(tostring(size), tostring(minp), tostring(maxp)))

		emin, emax = vm:read_from_map(minp, maxp)
		area = VoxelArea:new{
			MinEdge = emin,
			MaxEdge = emax
		}
		data = vm:get_data()

		if not skip_x[1] and expand_axis(minp, maxp, "x", 128, skip_x) then
			return true
		end
		if not skip_z[1] and expand_axis(minp, maxp, "z", 128, skip_z) then
			return true
		end
		if not skip_y[1] then
			local size_x = maxp.x - minp.x
			local size_z = maxp.z - minp.z
			local size_y = maxp.y - minp.y

			local function notify_limit(pos)
				local node = core.get_node(pos)
				add_pos_to_queue(state, node.name, pos)
			end

			for _, direction in ipairs({"up", "down"}) do
				local y = (direction == "up") and maxp.y or minp.y
				for z = minp.z, maxp.z do
					for x = minp.x, maxp.x do
						local idx = area:index(x, y, z)
						if cids_replace[data[idx]] then
							if direction == "up" then
								maxp.y = maxp.y + 1
							else
								minp.y = minp.y - 1
							end

							if ((size_x < 32 and size_z < 32 and size_y < 256) or size_y < 32) then
								return true
							else
								notify_limit(vector.new(x, y, z))
								skip_y[1] = true
								break
							end
						end
					end
				end
			end
		end

		return false
	end

	while loop_expand() do
	end

	log_error("final filter liquid bounds " .. tostring(maxp - minp) .. " " .. tostring(minp))

	-- FINAL VOXEL REPLACE + WALLING
	minp = vector.subtract(minp, 2)
	maxp = vector.add(maxp, 2)

	emin, emax = vm:read_from_map(minp, maxp)
	area = VoxelArea:new{
		MinEdge = emin,
		MaxEdge = emax
	}
	data = vm:get_data()

	for z = minp.z + 2, maxp.z - 2 do
		for y = minp.y + 2, maxp.y - 2 do
			for x = minp.x + 2, maxp.x - 2 do
				local i = area:index(x, y, z)
				if cids_replace[data[i]] then
					data[i] = cid_air
				end
			end
		end
	end

	for z = minp.z + 1, maxp.z - 1 do
		for y = minp.y + 1, maxp.y - 1 do
			for x = minp.x + 1, maxp.x - 1 do
				local i = area:index(x, y, z)
				if data[i] ~= cid_air then
					goto continue_wall
				end

				for _, off in ipairs({{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}) do
					local ni = area:index(x + off[1], y + off[2], z + off[3])
					if cids_source[data[ni]] then
						data[ni] = cid_wall
					end
				end

				::continue_wall::
			end
		end
	end

	vm:set_data(data)
	vm:write_to_map()
	vm:update_liquids()
	vm:update_map()

	log_action("filter liquid map updated")
end

local function can_player_fit(pos)
	local pos_node = core.get_node(pos)
	local above = vector.offset(pos, 0, 1, 0)
	local above_node = core.get_node(above)
	return pos_node.name == "air" and above_node.name == "air"
end

local function check_pos(pos)
	if can_player_fit(pos) then
		return pos
	end
	return nil
end

local function on_found_empty_space(dir)
	local distance = vector.distance(vector.new(0, 0, 0), dir)
	local hash = core.hash_node_position(dir)
	if not seen_dir_set[hash] then
		seen_dir_set[hash] = true
		if distance < 3 then
			log_action("teleport location " .. core.pos_to_string(dir) .. " distance " .. distance)
		end
	end
end

local function on_light_source(pos)
	local res = {}
	for i, v in pairs(vec_dirs) do
		local next_pos = check_pos(pos + v)
		if next_pos then
			return next_pos
		end
	end
	for i, dir in pairs(joined_dirs) do
		local distance = vector.distance(vector.new(0, 0, 0), dir)
		if not known_dir_set[core.hash_node_position(dir)] then
			local next_pos = check_pos(pos + dir)
			if next_pos then
				on_found_empty_space(dir)
				table.insert(res, next_pos)
				known_dir_set[core.hash_node_position(dir)] = true
			end
		end
	end
	for i, dir1 in pairs(joined_dirs) do
		for i2, dir2 in pairs(vec_dirs) do
			local distance = vector.distance(vector.new(0, 0, 0), dir1 + dir2)
			if not known_dir_set[core.hash_node_position(dir1 + dir2)] then
				local next_pos = check_pos(pos + dir1 + dir2)
				if next_pos then
					on_found_empty_space(dir1 + dir2)
					table.insert(res, next_pos)
					known_dir_set[core.hash_node_position(dir1 + dir2)] = true
				end
			end
		end
	end
	if #res > 0 then
		return res[1]
	end
	log_error("missing air at pos " .. core.pos_to_string(pos))
	return nil
end

local function async_wait(time)
	coroutine.yield({
		wait = true,
		time = time
	})
end

local function mark_near_light(state, node_name, pos)
	if not is_valid_pos_to_iter(pos, state.player_name) then
		return false
	end
	local h = core.hash_node_position(pos)
	if not state.known_lights[h] then
		state.known_lights[h] = true
		add_pos_to_queue(state, node_name, pos)
		return true
	end
	return false
end

local function count_found_nodes(iter, orig_pos, player_name)
	local count = 0
	for idx, next_pos in pairs(iter) do
		if not is_valid_pos_to_iter(next_pos, player_name) then
			goto skip
		end
		if orig_pos ~= next_pos then
			count = count + 1
		end
		::skip::
	end
	return count
end

function vector.midpoint(a, b)
	return vector.new(math.floor((a.x + b.x) / 2 + 0.5), math.floor((a.y + b.y) / 2 + 0.5), math.floor((a.z + b.z) / 2 + 0.5))
end

local function notify_pos(pos, color, size, expire_time)
	core.add_particle({
		pos = pos,
		expirationtime = expire_time or 30,
		size = size or 6,
		collisiondetection = false,
		vertical = false,
		texture = "bubble.png^[colorize:" .. color .. ":160",
		glow = 15
	})
end
local function wait_for_player_near_pos(player, target_pos)
	local out_of_range = vector.distance(player:get_pos(), target_pos) > 220
	while out_of_range and vector.distance(player:get_pos(), target_pos) > 128 do
		local player_pos = player:get_pos()
		notify_pos(target_pos, "#9900ffff", 25, 1)

		local difference = vector.normalize(target_pos - player_pos)

		player_pos = vector.add(player_pos, difference * 16)
		player:set_pos(player_pos)

		local world_particle_pos = vector.add(player_pos, difference * 8)
		local view_particle_pos = vector.offset(player_pos, 0, 1.5, 0)
		notify_pos(view_particle_pos, "#00ff00ff", 7, 0.5)

		local look_pos = vector.offset(player_pos, 0, 1.5, 0)
		local dir = vector.subtract(target_pos, look_pos)
		local flat_dir = vector.new(dir.x, 0, dir.z)

		local yaw = math.atan2(flat_dir.z, flat_dir.x) - math.pi / 2
		local hyp = math.sqrt(dir.x * dir.x + dir.z * dir.z)
		local pitch = -math.atan2(dir.y, hyp)

		player:set_look_horizontal(yaw)
		player:set_look_vertical(pitch)
		async_wait(0.2)
	end
	if out_of_range then
		async_wait(0.6)
	end
end
local region_scan_fmt1 = "[LightScan] scanned region (%d) %s"
local region_scan_fmt2 = " [LightScan] scanned region (%d) %s [%s]"
local function scan_nearby_region(state, r1, offset_vec, offset_str, pos, node_name)
	local r2 = aabb.region(r1.min + offset_vec, r1.max + offset_vec)
	local list = core.find_nodes_in_area(r2.min, r2.max, node_name, false)
	local count = count_found_nodes(list, pos, state.player_name)
	if count > 0 then
		log_action(region_scan_fmt2:format(count, aabb.region_str(r2), offset_str))
	end
end
local function scan_region_for_node(state, regions, r, pos, node_name, user_action, show_log)
	local center = (r.min + r.max) / 2
	local scan_distance = vector.distance(state.player:get_pos(), center)
	if scan_distance > 300 then
		if not show_log then
			return
		end
		local scan_nodes = core.find_nodes_in_area(r.min, r.max, node_name, false)
		local count = count_found_nodes(scan_nodes, pos, state.player_name)
		if count > 0 or user_action then
			local region_scan_fmt = "[LightScan] skipped region (%s) %s to %s (%s) Volume=%d Distance=%d"
			local min_str = core.pos_to_string(r.min)
			local max_str = core.pos_to_string(r.max)
			local size_str = core.pos_to_string(r.max - r.min)
			log_error(region_scan_fmt:format(count, min_str, max_str, size_str, aabb.volume(r), scan_distance))
		end
		return
	end
	wait_for_player_near_pos(state.player, center)
	local scan_nodes = core.find_nodes_in_area(r.min, r.max, node_name, false)
	local count = count_found_nodes(scan_nodes, pos, state.player_name)
	for _, p in pairs(scan_nodes) do
		local is_new_light = mark_near_light(state, node_name, p)
		if is_new_light then
			state.found_light_count = state.found_light_count + 1
		end
	end
	if count > 0 or user_action then
		if not show_log then
			return
		end
		local min_str = core.pos_to_string(r.min)
		local max_str = core.pos_to_string(r.max)
		local size = r.max - r.min
		local size_str = core.pos_to_string(size)
		log_warning(region_scan_fmt1:format(count, aabb.region_str(r)))
		scan_nearby_region(state, r, vector.new(size.x, 0, 0), "X+", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x, 0, 0), "X-", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, size.y, 0), "Y+", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, -size.y, 0), "Y-", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, 0, size.z), "Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, 0, -size.z), "Z-", pos, node_name)
		scan_nearby_region(state, r, vector.new(size.x, 0, -size.z), "X+ Z-", pos, node_name)
		scan_nearby_region(state, r, vector.new(size.x, 0, size.z), "X+ Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(size.x, size.y, 0), "X+ Y+", pos, node_name)
		scan_nearby_region(state, r, vector.new(size.x, -size.y, 0), "X+ Y-", pos, node_name)
		scan_nearby_region(state, r, vector.new(size.x, size.y, -size.z), "X+ Y+ Z-", pos, node_name)
		scan_nearby_region(state, r, vector.new(size.x, size.y, size.z), "X+ Y+ Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(size.x, -size.y, -size.z), "X+ Y- Z-", pos, node_name)
		scan_nearby_region(state, r, vector.new(size.x, -size.y, size.z), "X+ Y- Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x * 2, 0, 0), "X- X-", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x, 0, size.z), "X- Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x, 0, -size.z), "X- Z-", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x, size.y, 0), "X- Y+", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x, -size.y, 0), "X- Y-", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x, size.y, -size.z), "X- Y+ Z-", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x, -size.y, -size.z), "X- Y- Z-", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x, size.y, size.z), "X- Y+ Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(-size.x, -size.y, size.z), "X- Y- Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(size.x * 2, 0, 0), "X+ X+", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, size.y, size.z), "Y+ Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, size.y, -size.z), "Y+ Z-", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, -size.y * 2, 0), "Y- Y-", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, -size.y, size.z), "Y- Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, -size.y, -size.z), "Y- Z-", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, size.y * 2, 0), "Y+ Y+", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, 0, size.z * 2), "Z+ Z+", pos, node_name)
		scan_nearby_region(state, r, vector.new(0, 0, -size.z * 2), "Z- Z-", pos, node_name)
	end
end

local light_region_debug = {}

core.register_chatcommand("toggle_light_debug", {
	description = "Toggle debug view for light scan regions",
	func = function(name)
		light_region_debug[name] = not light_region_debug[name]
		if light_region_debug[name] then
			return true, "Light region debug ON"
		else
			return true, "Light region debug OFF"
		end
	end
})

local function place_mese_particle(pos, size)
	core.add_particle({
		pos = pos,
		velocity = vector.new(0, 0, 0),
		acceleration = vector.new(0, 0, 0),
		expirationtime = 4,
		size = size,
		texture = "default_mese_block.png",
		glow = 15
	})
end
local function place_particle(pos, size, texture)
	core.add_particle({
		pos = pos,
		velocity = vector.new(0, 0, 0),
		acceleration = vector.new(0, 0, 0),
		expirationtime = 4,
		size = size,
		texture = texture,
		glow = 15
	})
end

local function clamp_max(vmin, vmax, step)
	local range = vmax - vmin
	local count = math.ceil(range / step)
	return vmin + count * step, range, count
end

local function linspace_inclusive(vmin, vmax, step)
	-- Returns a list starting at vmin and ending at vmax, with intervals ≤ step
	local result = {}
	local range = vmax - vmin
	local steps = math.max(1, math.ceil(range / step))

	for i = 0, steps do
		local t = i / steps
		table.insert(result, vmin + t * range)
	end

	return result
end

local function linspace_side(start_pos, end_pos, step)
	-- Generate points from start_pos to end_pos inclusive, stepping by step
	local points = {}
	local dir = (end_pos >= start_pos) and 1 or -1
	local dist = math.abs(end_pos - start_pos)
	local count = math.max(1, math.ceil(dist / step))

	for i = 0, count do
		local t = i / count
		local val = start_pos + dir * t * dist
		table.insert(points, val)
	end

	return points
end

local function linspace_centered(vmin, vmax, center, step)
	-- Build linspace that includes center exactly, split into two sides
	local left = linspace_side(vmin, center, step)
	local right = linspace_side(center, vmax, step)

	-- Remove duplicate center at start of right side
	table.remove(right, 1)

	-- Concatenate left + right
	for _, v in ipairs(right) do
		table.insert(left, v)
	end

	return left
end

local function find_closest_index(arr, value)
	local closest_idx = 1
	local closest_dist = math.abs(arr[1] - value)
	for i = 2, #arr do
		local dist = math.abs(arr[i] - value)
		if dist < closest_dist then
			closest_idx = i
			closest_dist = dist
		end
	end
	return closest_idx
end

function aabb.draw(r)
	local min = r.min
	local max = r.max
	local step = 8

	-- Center point
	local center = vector.divide(vector.add(min, max), 2)
	place_mese_particle(center)

	local x_vals = linspace_centered(min.x, max.x, center.x, step)
	local y_vals = linspace_centered(min.y, max.y, center.y, step)
	local z_vals = linspace_centered(min.z, max.z, center.z, step)

	-- Find center indices (should be exact match)
	local cx = find_closest_index(x_vals, center.x)
	local cy = find_closest_index(y_vals, center.y)
	local cz = find_closest_index(z_vals, center.z)

	local layers = { --
	function(pos) place_particle(pos, 6 / 3, "default_stone.png") end, --
	function(pos) place_mese_particle(pos, 6 / 3) end, --
	function(pos) place_particle(pos, 6 / 3, "default_diamond_block.png") end, --
	function(pos) place_particle(pos, 6 / 3, "default_stone_block.png") end --
	}

	-- Draw shell
	for _, x in ipairs(x_vals) do
		for _, y in ipairs(y_vals) do
			for _, z in ipairs(z_vals) do
				local on_x_edge = (x == min.x or x == max.x)
				local on_y_edge = (y == min.y or y == max.y)
				local on_z_edge = (z == min.z or z == max.z)

				if on_x_edge or on_y_edge or on_z_edge then
					local pos = vector.new(x, y, z)

					if not on_y_edge then
						layers[2](pos)
					elseif y == max.y then
						layers[1](pos)
					elseif y ~= min.y and (on_x_edge or on_z_edge) then
						layers[4](pos)
					elseif y == min.y then
						layers[3](pos)
					end
				end
			end
		end
	end

	-- Draw axis lines through center
	for i = 2, #x_vals - 1 do
		if i ~= cx then
			layers[2](vector.new(x_vals[i], y_vals[cy], z_vals[cz]))
		end
	end
	for i = 2, #y_vals - 1 do
		if i ~= cy then
			layers[2](vector.new(x_vals[cx], y_vals[i], z_vals[cz]))
		end
	end
	for i = 2, #z_vals - 1 do
		if i ~= cz then
			layers[2](vector.new(x_vals[cx], y_vals[cy], z_vals[i]))
		end
	end
end

local last_center_per_player = {}
local function scan_nearby_lights(state, pos, node_name, options, show_log)
	local player_name = state.player_name
	local regions = light_scan_data[player_name]
	local config = p_config.data[player_name]
	local maxy = config.maxy
	local function base_scan(r, user_action) scan_region_for_node(state, regions, r, pos, node_name, user_action, show_log) end
	local function full_scan(r) base_scan(r, true) end
	local function normal_scan(r) base_scan(r, false) end
	if config.last_maxy ~= config.maxy then
		for _, r in ipairs(regions) do
			normal_scan(r)
		end
		config.last_maxy = config.maxy
	end
	if options.user then
		for _, r in ipairs(regions) do
			if aabb.is_point_in_region(r, pos) then
				full_scan(r)
			end
		end
	end
	local scan_dist = light_scan_dist
	local scan_range = scan_dist / 2
	local minvec = vector.offset(pos, math.ceil(-scan_range), math.ceil(-scan_range), math.ceil(-scan_range))
	local maxvec = vector.offset(minvec, scan_dist, scan_dist, scan_dist)
	if maxvec.y > maxy then
		maxvec.y = maxy
	end
	local total_count = 0
	local newly_scanned = true
	local r = aabb.region(minvec, maxvec)
	for _, s in ipairs(regions) do
		if aabb.region_fully_covered(r, s) then
			newly_scanned = false
			break
		end
	end
	if newly_scanned then
		aabb.subtract_and_accumulate(r, regions, {
			volume_threshold = 80000,
			max_distance = 26,
			on_flush = function(r)
				normal_scan(r)
				table.insert(regions, r)
			end
		})
	end
	local GAP_THRESHOLD = 160000
	local MAX_GAP_DIST = 11
	for i = 1, #regions - 1 do
		for j = i + 1, #regions do
			local gap = aabb.between(regions[i], regions[j], MAX_GAP_DIST)
			if gap and aabb.volume(gap) < GAP_THRESHOLD then
				if not aabb.is_covered_by_any(gap, regions) then
					normal_scan(r)
					table.insert(regions, r)
				end
			end
		end
	end
	local unknown = aabb.compact_regions(regions)
	for _, r in ipairs(unknown) do
		normal_scan(r)
	end
	for _, r in ipairs(regions) do
		local size = r.min - r.max
		local size_change = math.floor(scan_dist / 2)
		if size_change < 1 then
			size_change = 1
		end
		if size.x > size_change * 2 then
			r.min.x = r.min.x + size_change
			r.max.x = r.max.x - size_change
		end
		if size.y > size_change * 2 then
			r.min.y = r.min.y + size_change
			r.max.y = r.max.y - size_change
		end
		if size.z > size_change * 2 then
			r.min.z = r.min.z + size_change
			r.max.z = r.max.z - size_change
		end
	end
	if newly_scanned then
		for _, r in ipairs(regions) do
			aabb.draw(r)
		end
	end
end

local do_teleport_skip_warn = false
local add_to_teleport_queue = false
local function add_light_to_teleport_queue(state, v)
	local pos = v.pos
	local h = core.hash_node_position(pos)
	if not state.teleport_skip_set[h] then
		state.teleport_skip_set[h] = true
		local update_pos = on_light_source(pos)
		local below_pos = vector.offset(pos, 0, -1, 0)
		if update_pos == nil then
			update_pos = below_pos
		end
		if add_to_teleport_queue then
			state.teleport_queue:push_right(update_pos)
		end
		local tp_diff = core.pos_to_string(vector.subtract(update_pos, pos))
		local target = core.pos_to_string(below_pos)
		log_action("teleport left " .. v.queue_left .. " diff " .. tp_diff .. " trg " .. target)
		if do_teleport_skip_warn then
			state.teleport_skip_count = state.teleport_skip_count + 1
			if state.teleport_skip_count > state.warn_next then
				log_action("teleport large skip_count " .. state.teleport_skip_count)
				state.warn_next = state.warn_next + 200
			end
		end
	end
end

local function do_update_pos(state)
	if not state.teleport_queue:is_empty() then
		for cur_pos in state.teleport_queue:iter_right() do
			local h = core.hash_node_position(cur_pos)
			if not state.seen_teleports_set[h] then
				state.seen_teleports_set[h] = true
				cur_pos.y = cur_pos.y - 0.5
				state.player:set_pos(cur_pos)
				-- async_wait(0)
				-- async_wait(0.08)
				-- async_wait(0.5)
			end
		end
		-- local time_left = 0.4 - (0.06 * teleport_queue:length())
		-- if time_left > 0 then
		-- 	async_wait(time_left)
		-- end
		state.teleport_queue.head = 0
		state.teleport_queue.tail = 0
	end
end

local function has_empty_main_inv_slot(player)
	local inventory = player:get_inventory()
	local inv_list = inventory:get_list("main")
	for _, stack in ipairs(inv_list) do
		if stack:is_empty() then
			return true
		end
	end
	return false
end

local floating_dirs = CFG.FLOATING_DIRS

local function is_floating(pos, expected_name)
	for _, offset in ipairs(floating_dirs) do
		local neighbor_pos = vector.add(pos, offset)
		local neighbor = core.get_node_or_nil(neighbor_pos)
		if neighbor and neighbor.name ~= "air" and neighbor.name ~= "ignore" and neighbor.name ~= expected_name then
			-- Found a supporting node
			return false
		end
	end
	-- All neighbors are air or ignore: it's floating
	return true
end

local mod_pos = vein_miner.h.mod_pos
local is_liquid = vein_miner.h.is_liquid
local function process_node_group(state, node_name, node, repeat_count)
	local mined_nodes_count = 0
	if is_liquid(node_name, "water") or is_liquid(node_name, "lava") then
		for index, pos in pairs(node) do
			filter_liquid(state, pos)
			mined_nodes_count = mined_nodes_count + 1
		end
		if repeat_count <= 2 then
			log_action("done liquid processing for " .. node_name .. " " .. mined_nodes_count .. " nodes")
		end
		return 0
	end
	-- calculate durability per block
	local def = ItemStack(node_name):get_definition()
	local tp = state.wielded:get_tool_capabilities()
	local dp = core.get_dig_params(def.groups, tp)
	if not dp.diggable then
		return 0
	end
	local wear_limit = 65535 - dp.wear
	for index, pos in pairs(node) do
		if state.wielded:get_wear() < wear_limit then
			local p = state.prev_pos
			local area_sector = mod_pos(pos, vector.new(16, 16, 16))
			if p then
				if state.cur_mined_nodes >= state.co_cur_max_nodes then
					coroutine.yield(state.cur_mined_nodes)
					state.co_cur_max_nodes = MAX_MINED_NODES
					state.mined_nodes = state.mined_nodes + state.cur_mined_nodes
					state.cur_mined_nodes = 0
					do_update_pos(state)
				end
			end
			local node = core.get_node(pos)
			if not BlockDigger.should_dig(node, pos) then
				goto next_node
			end
			local options = get_scan_options(node_name, {})
			if options.light then
				state.pending_light_notify:push_left({
					pos = pos,
					queue_left = state.queue:length()
				})
				state.found_light_count = state.found_light_count - 1
			end
			if not options.light or is_floating(pos, node.name) then
				core.node_dig(pos, node, state.player)
				mined_nodes_count = mined_nodes_count + 1
			end
			if options.light then
				local nat_light = core.get_natural_light(pos, 0.5)
				if nat_light > 0 then
					core.node_dig(pos, node, state.player)
					mined_nodes_count = mined_nodes_count + 1
				end
			end
			state.wielded:add_wear(dp.wear)
			do
				local tool = state.player:get_wielded_item()
				if tool:get_wear() ~= state.wielded:get_wear() then
					state.wielded:set_wear(tool:get_wear())
				end
				if state.wielded:get_wear() > 65535 - dp.wear * 3 then
					update_wielded_item(state.player, state.wielded)
				end
			end
			state.cur_mined_nodes = state.cur_mined_nodes + 1
			state.prev_pos = pos
			state.prev_sector = area_sector
		end
		::next_node::
	end
	return mined_nodes_count
end

local function iter_node_groups(state, iter_nodes)
	state.prev_pos = nil
	local i = 0
	::again::
	for node_name, node in pairs(iter_nodes) do
		local dug_nodes = process_node_group(state, node_name, node, i)
		if dug_nodes > 0 and i < 32 then
			i = i + 1
			goto again
		end
	end
end
local function notify_missing_light(pos, attach_dir, expire_time)
	local attach_node = core.get_node_or_nil(pos + attach_dir)
	if attach_node == nil or attach_node.name == "air" then
		return
	end
	if table.contains(light_nodes, attach_node.name) then
		return
	end
	local node = core.get_node_or_nil(pos)
	if node == nil or node.name == "air" then
		notify_pos(pos + (attach_dir / 16 * 4), "#00ff00ff", 4, expire_time)
	end
end
local xpos = vector.new(1, 0, 0)
local xneg = vector.new(-1, 0, 0)
local ypos = vector.new(0, 1, 0)
local yneg = vector.new(0, -1, 0)
local zpos = vector.new(0, 0, 1)
local zneg = vector.new(0, 0, -1)

local water_targets = {"default:water_flowing", "default:water_source", "default:lava_flowing", "default:lava_source"}
local falling_target_nodes = table.copy(mine_only_groups.sand)
table.insert_all(falling_target_nodes, mine_only_groups.silver_sand)
table.insert_all(falling_target_nodes, mine_only_groups.gravel)

local known_unhandled_nodes = {}
local function dig_pos_process_queue_item(state, item, player_name)
	local config = p_config.data[player_name]

	local pos = item.pos
	local node_name = item.node_name
	local options = item.options

	local xz_len = 8
	local y_len = 8
	if config.mode == "large" then
		if pos.y > -32.5 and (not options.light) and (not options.small) then
			xz_len = 32
			y_len = 32
			options.large = true
		end
	end
	if not options.large then
		options.small = true
	end

	local vec_size = vector.new(xz_len, y_len, xz_len);

	local minvec = mod_pos(pos, vec_size)

	if state.pos_mod_seen[core.hash_node_position(minvec)] then
		return
	end

	if not is_valid_pos_to_iter(pos, player_name) then
		return
	end

	if is_liquid(node_name, "water") or is_liquid(node_name, "lava") then
		filter_liquid(state, pos)
		return
	end
	if options.light then
		state.pending_light_notify:push_left({
			pos = pos,
			queue_left = state.queue:length()
		})
	end

	local vec_max = vector.add(vec_size, -1)
	local maxvec = vector.add(minvec, vec_max)
	local center = vector.floor(vector.divide(vector.add(minvec, maxvec), 2))

	if vector.distance(state.player:get_pos(), center) > 150 then
		return
	end

	wait_for_player_near_pos(state.player, center)

	if options.large then
		notify_pos(center, "#0000ffff", 6 * 4, 120 + 30)
	else
		notify_pos(center, "#0000ffff", 6, 120 + 30)
	end

	local target_nodes = {}
	table.insert_all(target_nodes, {"default:dirt"})
	table.insert_all(target_nodes, mine_only_groups.stone)
	table.insert_all(target_nodes, mine_only_groups.stone_like)
	table.insert_all(target_nodes, mine_only_groups.stone_with_ore)
	local target_flags = {
		liquid = true,
		falling = true
	}
	local node_result = handle_unexpected_target_nodes(target_nodes, node_name)
	if node_result == "error" then
		if not known_unhandled_nodes[node_name] then
			known_unhandled_nodes[node_name] = true
			log_error("unhandled node name " .. node_name)
		end
		return
	end
	if node_result == "inc_mine_skip" then
		return
	end
	if node_result == "only_current" then
		target_nodes = {}
		target_flags.falling = false
		target_flags.liquid = false
		table.insert(target_nodes, node_name)
	end
	if node_result == "add_current" then
		table.insert(target_nodes, node_name)
	end
	local group_target = nil
	if node_result == "mine_only_cur" then
		if node_name == "wool:green" then
			target_nodes = {}
			target_flags.falling = false
		elseif not table.contains(falling_target_nodes, node_name) then
			target_nodes = {}
			target_flags.falling = false
			target_flags.liquid = false
		end
		if mine_only_group_sets[node_name] ~= nil then
			local target_key = mine_only_group_sets[node_name]
			table.insert_all(target_nodes, mine_only_groups[target_key])
			group_target = target_key
		else
			table.insert(target_nodes, node_name)
		end
	end

	if options.user and options.light then
		state.found_light_count = state.found_light_count + 1
	end

	if not has_empty_main_inv_slot(state.player) then
		core.chat_send_player(state.player_name, "Waiting for empty inventory slot for digging")
	end
	while not has_empty_main_inv_slot(state.player) do
		async_wait(3)
	end
	if target_flags.liquid then
		iter_node_groups(state, core.find_nodes_in_area(minvec, maxvec, water_targets, true))
	end
	if target_flags.falling then
		iter_node_groups(state, core.find_nodes_in_area(minvec, maxvec, falling_target_nodes, true))
	end
	iter_node_groups(state, core.find_nodes_in_area(minvec, maxvec, target_nodes, true))

	core.fix_light(minvec, maxvec)

	for v in state.pending_light_notify:iter_right() do
		add_light_to_teleport_queue(state, v)
	end

	if options.light then
		state.pending_light_scan:push_left({pos, node_name, options})
		scan_nearby_lights(state, pos, node_name, options, false)
	end

	if not options.large then
		local light_timeout = 20

		-- notify_pos(minvec, "#ffff00ff", 6, light_timeout + 15)

		local lp_north = vector.offset(minvec, 3, 3, 7)
		local lp_south = vector.offset(minvec, 3, 3, 0)
		local lp_west = vector.offset(minvec, 0, 3, 3)
		local lp_east = vector.offset(minvec, 7, 3, 3)
		local lp_down = vector.offset(minvec, 3, 0, 3)
		local lp_up = vector.offset(minvec, 3, 7, 3)
		notify_missing_light(lp_east, xpos, light_timeout)
		notify_missing_light(lp_west, xneg, light_timeout)
		notify_missing_light(lp_up, ypos, light_timeout)
		notify_missing_light(lp_down, yneg, light_timeout)
		notify_missing_light(lp_north, zpos, light_timeout)
		notify_missing_light(lp_south, zneg, light_timeout)
	end

	state.work_done = true

	state.pos_mod_seen[core.hash_node_position(minvec)] = true
end

-- Recursively mines a vein of blocks
local function dig_pos(state)
	state.prev_pos = nil
	state.prev_sector = nil
	state.seen_teleports_set = {}
	state.logged_teleports = {}
	state.teleport_skip_set = {}
	state.known_lights = {}
	if do_teleport_skip_warn then
		state.teleport_skip_count = 0
	end
	state.mined_nodes = 0
	state.cur_mined_nodes = 0
	state.warn_next = 200
	state.co_cur_max_nodes = MAX_MINED_NODES
	state.teleport_queue = vein_miner.deque.new()

	state.work_done = false

	state.pos_mod_seen = {}

	state.pending_light_notify = vein_miner.deque.new()
	state.pending_light_scan = vein_miner.deque.new()

	local queue = state.queue
	local player_name = state.player_name

	while not queue:is_empty() do
		local item = queue:pop_left()
		if log_work_start then
			log_warning("start work on item at " .. core.pos_to_string(item.pos) .. " " .. item.node_name)
		end
		dig_pos_process_queue_item(state, item, player_name)
		state.mined_nodes = state.mined_nodes + state.cur_mined_nodes
		state.co_cur_max_nodes = state.co_cur_max_nodes - state.cur_mined_nodes
		if state.cur_mined_nodes > 0 then
			coroutine.yield(state.cur_mined_nodes)
		end
		state.cur_mined_nodes = 0
		do_update_pos(state)
	end
end

local function dig_finish(state)
	for v in state.pending_light_scan:iter_right() do
		scan_nearby_lights(state, v[1], v[2], v[3], true)
	end
	if state.total_action_count > 0 then
		log_warning("vein miner complete in " .. state.total_action_count .. " steps\n" .. '***')
	elseif state.work_done then
		log_warning("vein miner complete\n" .. '***')
	end
end

local next_loop_action_divisor = --[[2000]] 4000;

local function after_delay(data, fn, state)
	if data == nil then
		core.after(0, fn, state)
		return
	end
	if type(data) == "table" then
		if data.wait then
			core.after(data.time, fn, state)
		end
		return
	end
	local mined_nodes = data
	state.total_action_count = state.total_action_count + mined_nodes
	local action_cost = mined_nodes / next_loop_action_divisor
	if action_cost > 0.09 then
		local delay_total = math.floor(action_cost * 10000) / 10000
		log_action("mined nodes is " .. mined_nodes .. "; run next loop in " .. delay_total)
	end
	core.after(action_cost, fn, state)
end

local function after_co_start(state, co, async_step_fn, status, action_count)
	core.is_async = nil
	if not status then
		log_error("vein_miner coroutine error " .. action_count)
		log_error(debug.traceback(co))
		return
	else
		after_delay(action_count, async_step_fn, state)
		return
	end
end

local function resume_coroutine(state, co, async_step_fn)
	core.is_async = true
	local status, action_count = coroutine.resume(co)
	after_co_start(state, co, async_step_fn, status, action_count)
end

local function vein_miner_step(state)
	::start::
	if state.thread == nil then
		state.thread = coroutine.create(function() return dig_pos(state) end)
	end
	local co_status = coroutine.status(state.thread)
	if co_status == "suspended" then
		resume_coroutine(state, state.thread, vein_miner_step)
	elseif co_status == "dead" then
		if not state.queue:is_empty() then
			state.thread = nil
			goto start
		else
			dig_finish(state)
			vein_miner_current_state[state.player_name] = nil
		end
	else
		log_error("unexpected coroutine status " .. co_status)
	end
end

vein_miner.state = {}

function vein_miner.state.new(pos, player, player_name, wielded)
	local state = {
		pos = pos,
		player = player,
		player_name = player_name,
		wielded = wielded,
		falling_check_nodes = vein_miner.deque.new(),
		queue = vein_miner.deque.new(),
		queued_set = {},
		total_action_count = 0,
		found_light_count = 0
	}

	return state
end

core.register_on_dignode(function(pos, oldnode, player)
	if core.is_async then
		return
	end
	if player == nil then
		return
	end
	if oldnode == nil then
		return
	end
	local node_name = oldnode.name
	if pos == nil then
		return
	end
	if player:get_player_control().sneak then
		return
	end
	local wielded = player:get_wielded_item()
	if not is_node_vein_diggable(node_name, wielded:get_name()) then
		return
	end

	-- start vein mining
	local player_name = player:get_player_name()
	if p_config.data[player_name] == nil then
		p_config.data[player_name] = {}
	end
	local config = p_config.data[player_name]
	if config.mode == nil then
		config.mode = "small"
	end
	local state = vein_miner_current_state[player_name]
	if state == nil then
		state = vein_miner.state.new(pos, player, player_name, wielded)
		vein_miner_current_state[player_name] = state
		vein_miner_step(state)
	end
	local queue = state.queue
	local qs = state.queued_set
	add_pos_to_queue(state, node_name, pos, {
		user = true
	})
end)

core.register_privilege("vein_miner_config", {
	description = "Can configure vein miner",
	give_to_singleplayer = false
})

core.register_chatcommand("mining_mode", {
	description = "Change configured mining range (8 or 32 at y > -32)",
	params = "[small|large]",
	privs = {
		vein_miner_config = true
	},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		param = param:lower()
		if p_config.data[name] == nil then
			p_config.data[name] = {}
		end

		local config = p_config.data[name]

		if param == "" or param == nil then
			return true, "Mining mode is " .. config.mode .. " range."
		elseif param == "small" then
			config.mode = "small"
			return true, "Mining mode set to small range."
		elseif param == "large" then
			config.mode = "large"
			return true, "Mining mode set to large range."
		else
			return false, "Invalid parameter. Use: /mining_mode small OR /mining_mode large"
		end
	end
})

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	p_config.load_player_config(name)
	local config = p_config.data[name]

	if config.maxy == nil then
		config.maxy = 144
	end
	if config.target_layer ~= nil then
		config.maxy = config.target_layer * 8 + 7
		config.target_layer = nil
	end
	if config.miny == nil then
		config.miny = -144
	end
	if config.mode == nil then
		config.mode = "small" -- default: "small"
	end

	light_scan_data[name] = {}
	light_region_debug[name] = true
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	p_config.save_player_config(name)
end)

local function show_layer_bounds(miny, maxy)
	local y_range = "y=" .. (miny + 1) .. ".." .. maxy
	local layer_info = "(layers " .. math.floor((miny + 1) / 8) .. " to " .. math.floor(maxy / 8) .. ")"
	return y_range .. " " .. layer_info
end

core.register_chatcommand("mine", {
	description = "Change configured mining layer",
	params = "[get [min|max] | set [min|max <y>] | up [min|max|both] | down [min|max|both] | reset]",
	privs = {},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		local config = p_config.data[name]

		-- Initialize defaults if missing
		if config.miny == nil then
			config.miny = -128
		end
		if config.maxy == nil then
			config.maxy = 128
		end

		local args = param:split(" ")
		local cmd = args[1]
		local sub = args[2]
		local val = tonumber(args[3])

		local miny, maxy = config.miny, config.maxy

		if cmd == "get" or cmd == nil or cmd == "" then
			if sub == "min" then
				return true, "Minimum mining Y: y=" .. miny .. " (layer ≥ " .. math.floor(miny / 8) .. ")"
			elseif sub == "max" then
				return true, "Maximum mining Y: y=" .. maxy .. " (layer ≤ " .. math.floor(maxy / 8) .. ")"
			else
				return true, "Current mining bounds: " .. show_layer_bounds(miny, maxy)
			end
		elseif cmd == "set" then
			if sub == "min" and val then
				val = math.floor(val)
				if val > maxy then
					return false, "miny cannot be greater than maxy (" .. maxy .. ")"
				end
				config.miny = val
				return true, "Minimum mining Y set to y=" .. val
			elseif sub == "max" and val then
				val = math.floor(val)
				if val < miny then
					return false, "maxy cannot be less than miny (" .. miny .. ")"
				end
				config.maxy = val
				return true, "Maximum mining Y set to y=" .. val
			elseif sub == nil then
				local view_y = player:get_pos().y + 1.6
				local new_miny = math.floor((view_y - 16) / 8) * 8 - 1
				local new_maxy = math.floor((view_y + 48) / 8) * 8
				config.miny = new_miny
				config.maxy = new_maxy
				return true, "Mining range set from view: " .. show_layer_bounds(new_miny, new_maxy)
			else
				return false, "Usage: /mine set [min|max <y>]"
			end
		elseif cmd == "up" then
			if sub == "min" then
				config.miny = config.miny + 8
				return true, "Minimum mining Y increased to y=" .. config.miny
			elseif sub == "max" then
				config.maxy = config.maxy + 8
				return true, "Maximum mining Y increased to y=" .. config.maxy
			elseif sub == "both" or sub == nil then
				config.miny = config.miny + 8
				config.maxy = config.maxy + 8
				return true, "Mining range increased: " .. show_layer_bounds(config.miny, config.maxy)
			else
				return false, "Usage: /mine up [min|max|both]"
			end
		elseif cmd == "down" then
			if sub == "min" then
				if config.miny - 8 > config.maxy then
					return false, "miny cannot exceed maxy"
				end
				config.miny = config.miny - 8
				return true, "Minimum mining Y decreased to y=" .. config.miny
			elseif sub == "max" then
				if config.maxy - 8 < config.miny then
					return false, "maxy cannot be less than miny"
				end
				config.maxy = config.maxy - 8
				return true, "Maximum mining Y decreased to y=" .. config.maxy
			elseif sub == "both" or sub == nil then
				if config.miny - 8 > config.maxy - 8 then
					return false, "Range collapse: miny would exceed maxy"
				end
				config.miny = config.miny - 8
				config.maxy = config.maxy - 8
				return true, "Mining range decreased: " .. show_layer_bounds(config.miny, config.maxy)
			else
				return false, "Usage: /mine down [min|max|both]"
			end
		elseif cmd == "reset" then
			light_scan_reset(name)
			return false, "Light scan data reset"
		else
			return false, "Usage: /mine [get [min|max] | set [min|max <y>] | up [min|max|both] | down [min|max|both] | reset]"
		end
	end
})

local falling_check_delay = 0.5

local dtime_acc = 0
local dtime_next_falling_check = falling_check_delay

local falling_nodes = {}
local falling_nodes_set = {}

local prev_core_check_for_falling = core.check_for_falling
core.check_for_falling = function(pos)
	local h = core.hash_node_position(pos)
	if not falling_nodes_set[h] then
		falling_nodes_set[h] = true
		table.insert(falling_nodes, pos)
	end
	if dtime_next_falling_check < dtime_acc + falling_check_delay then
		dtime_next_falling_check = dtime_acc + falling_check_delay
	end
end

local dtime_time = 0

core.register_globalstep(function(dtime)
	dtime_acc = dtime_acc + dtime
	if dtime_acc > dtime_next_falling_check and #falling_nodes > 0 then
		for i = 1, #falling_nodes do
			local pos = falling_nodes[i]
			falling_nodes[i] = nil
			local h = core.hash_node_position(pos)
			falling_nodes_set[h] = nil
			prev_core_check_for_falling(pos)
		end
		dtime_next_falling_check = dtime_acc + falling_check_delay
	end
	for name, enabled in pairs(light_region_debug) do
		local player = core.get_player_by_name(name)
		if enabled and player then
			local regions = light_scan_data[name]
			if dtime_time > 4 then
				for _, r in ipairs(regions) do
					aabb.draw(r)
				end
				dtime_time = 0
			end
		end
	end
	dtime_time = dtime_time + dtime
end)

core.register_chatcommand("yaw", {
	description = "Change player yaw",
	params = "[get | set <yaw>]",
	privs = {},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		local args = param:split(" ")
		local cmd = args[1]
		if cmd == "get" or cmd == nil or cmd == "" then
			local yaw = player:get_look_horizontal()
			return true, ("Your current yaw is %.1f degrees"):format(math.deg(yaw))
		elseif cmd == "set" then
			local yaw = 0
			if args[2] ~= nil then
				yaw = math.rad(tonumber(args[2]))
			end
			player:set_look_horizontal(yaw)
			return true, ("Yaw set to %.1f degrees"):format(math.deg(yaw))
		end
	end
})

core.register_chatcommand("pos", {
	description = "Show your position with 3 decimal places",
	privs = {},
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		local pos = player:get_pos()
		local msg = string.format("Your position is: (%.3f, %.3f, %.3f)", pos.x, pos.y, pos.z)
		return true, msg
	end
})

core.override_item("", {
	range = 7
})

local function node_sound_defaults(tbl)
	tbl = tbl or {}
	tbl.footstep = tbl.footstep or {
		name = "",
		gain = 1.0
	}
	tbl.dug = tbl.dug or {
		name = "default_dug_node",
		gain = 0.25
	}
	tbl.place = tbl.place or {
		name = "default_place_node_hard",
		gain = 1.0
	}
	return tbl
end

local function node_sound_stone_defaults(tbl)
	tbl = tbl or {}
	tbl.footstep = tbl.footstep or {
		name = "default_hard_footstep",
		gain = 0.2
	}
	tbl.dug = tbl.dug or {
		name = "default_hard_footstep",
		gain = 1.0
	}
	node_sound_defaults(tbl)
	return tbl
end
local function register_lit_cobble(light_level)
	local node_name = "vein_miner:lit_cobble_" .. light_level
	core.register_node(node_name, {
		description = ("Lit Cobblestone (Level=%d)"):format(light_level),
		tiles = {"default_cobble.png"},
		groups = {
			cracky = 3,
			stone = 2
		},
		light_source = light_level,
		drop = node_name,
		sounds = node_sound_stone_defaults()
	})

	table.insert(mine_only_groups.lit_cobble, node_name)
	mine_only_group_sets[node_name] = "lit_cobble"
	mine_only_cur_set[node_name] = true
end

mine_only_groups.lit_cobble = {}

for i = 1, 14 do
	register_lit_cobble(i)
end

core.register_craft({
	type = "shapeless",
	output = "vein_miner:lit_cobble_1",
	recipe = {"default:cobble", "default:mese_crystal_fragment"}
})

core.register_craft({
	type = "shapeless",
	output = "default:cobble 2",
	recipe = {"default:cobble", "vein_miner:lit_cobble_1"},
	replacements = {{"vein_miner:lit_cobble_1", "default:mese_crystal_fragment"}}
})

core.register_craft({
	type = "shapeless",
	output = "vein_miner:lit_cobble_1",
	recipe = {"default:cobble", "vein_miner:lit_cobble_2"},
	replacements = {{"default:cobble", "default:cobble"}}
})

core.register_craft({
	type = "shapeless",
	output = "vein_miner:lit_cobble_2 2",
	recipe = {"vein_miner:lit_cobble_1", "vein_miner:lit_cobble_1"}
})

core.register_craft({
	output = "vein_miner:lit_cobble_2",
	recipe = {{"vein_miner:lit_cobble_1"}}
})
