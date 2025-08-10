local core = core
local dofile = dofile

local require = dofile(core.get_modpath("vein_miner") .. "/require_local.lua")
local utils = require("mods.vein_miner.utils")
local require = utils.require

local minetest = minetest
local vector = vector
local ipairs = ipairs
local next = next
local table = table
local tonumber = tonumber
local pairs = pairs
local string = string
local math = math
local ItemStack = ItemStack
local coroutine = coroutine
local offset = vector.offset
local string_match = string.match
local floor = math.floor
local ceil = math.ceil
local yield = coroutine.yield
local add_particle = core.add_particle

---@type VeinMinerGlobal
vein_miner = {
	deque = {},
	utils = utils,
}
local vein_miner = vein_miner
require("mods.vein_miner.deque")
require("mods.vein_miner.auto_floor")
require("mods.vein_miner.voxel_utils")
require("mods.vein_miner.config")
require("mods.vein_miner.helpers")
aabb = require("mods.vein_miner.aabb")
local aabb = aabb
require("mods.vein_miner.liquid_filler")
require("mods.vein_miner.remove_walls")
local player_hud = require("mods.vein_miner.player_hud")
local p_config = require("mods.vein_miner.player_config")
vein_miner.player_config = p_config
utils:merge(require("mods.vein_miner.late_utils"))
local BlockDigger = require("mods.vein_miner.block_digger")
require("mods.vein_miner.commands")

local falling_nodes = {}
local falling_nodes_set = {}

vein_miner.falling_nodes = falling_nodes
vein_miner.falling_nodes_set = falling_nodes_set
vein_miner.last_falling_node = 0
vein_miner.check_for_falling = core.check_for_falling

core.check_for_falling = function(pos)
	local h = core.hash_node_position(pos)
	if not falling_nodes_set[h] then
		falling_nodes_set[h] = true
		table.insert(falling_nodes, pos)
	end
	vein_miner.last_falling_node = vein_miner.current_tick_time
end

---@type table<string, Region[]>
local light_scan_data = {}
vein_miner.light_scan_data = light_scan_data

function vein_miner.light_scan_reset(name) light_scan_data[name] = {} end

require("mods.vein_miner.globalstep")

local fill_liquid_at_pos = vein_miner.fill_liquid_at_pos

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

local log_work_start = false

local log_error = vein_miner.h.log_error
local log_warning = vein_miner.h.log_warning
local log_action = vein_miner.h.log_action

local CFG = vein_miner.CFG

local ignored_nodes = CFG.IGNORED_NODES
local light_nodes = CFG.LIGHT_NODES
utils.light_nodes = light_nodes
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

local vein_miner_current_state = {}

local check_for_falling_neighbors = {vector.new(-1, -1, 0), vector.new(1, -1, 0), vector.new(0, -1, -1), vector.new(0, -1, 1),
	vector.new(0, -1, 0), vector.new(-1, 0, 0), vector.new(1, 0, 0), vector.new(0, 0, -1), vector.new(0, 0, 1), vector.new(0, 1, 0)}
local possible_flow_directions = {vector.new(-1, 0, 0), vector.new(1, 0, 0), vector.new(0, 0, -1), vector.new(0, 0, 1), vector.new(0, 1, 0)}
local liquid_set = {
	["default:water_source"] = true,
	["default:water_flowing"] = true,
	["default:lava_source"] = true,
	["default:lava_flowing"] = true,
}

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
		local next_pos = utils.check_pos(pos + v)
		if next_pos then
			return next_pos
		end
	end
	for i, dir in pairs(joined_dirs) do
		local distance = vector.distance(vector.new(0, 0, 0), dir)
		if not known_dir_set[core.hash_node_position(dir)] then
			local next_pos = utils.check_pos(pos + dir)
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
				local next_pos = utils.check_pos(pos + dir1 + dir2)
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

local function mark_near_light(state, node_name, pos)
	if not is_valid_pos_to_iter(pos, state.player_name) then
		return false
	end
	local h = core.hash_node_position(pos)
	if not state.known_lights[h] then
		state.known_lights[h] = true
		utils.add_pos_to_queue(state, node_name, pos)
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

local function place_particle(pos, size, texture)
	add_particle({
		pos = pos,
		expirationtime = 4,
		size = size or 4,
		texture = texture or "default_mese_block.png",
		glow = 15,
	})
end
local function notify_pos(pos, color, size, expire_time)
	add_particle({
		pos = pos,
		expirationtime = expire_time or 30,
		size = size or 6,
		texture = "bubble.png^[colorize:" .. color .. ":160",
		glow = 15,
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
		utils.async_wait(0.2)
	end
	if out_of_range then
		utils.async_wait(0.6)
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

local function stone_part(pos) place_particle(pos, 6 / 3, "default_stone.png") end
local function mese_blk_part(pos) place_particle(pos, 6 / 3, "default_mese_block.png") end
local function diamond_blk_part(pos) place_particle(pos, 6 / 3, "default_diamond_block.png") end
local function stone_blk_part(pos) place_particle(pos, 6 / 3, "default_stone_block.png") end

function aabb.draw(r)
	local min = r.min
	local max = r.max
	local step = 8

	-- Center point
	local center = vector.divide(vector.add(min, max), 2)
	mese_blk_part(center)

	local x_vals = utils.linspace_centered(min.x, max.x, center.x, step)
	local y_vals = utils.linspace_centered(min.y, max.y, center.y, step)
	local z_vals = utils.linspace_centered(min.z, max.z, center.z, step)

	-- Find center indices (should be exact match)
	local cx = utils.find_closest_index(x_vals, center.x)
	local cy = utils.find_closest_index(y_vals, center.y)
	local cz = utils.find_closest_index(z_vals, center.z)

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
						mese_blk_part(pos)
					elseif y == max.y then
						stone_part(pos)
					elseif y ~= min.y and (on_x_edge or on_z_edge) then
						stone_blk_part(pos)
					elseif y == min.y then
						diamond_blk_part(pos)
					end
				end
			end
		end
	end

	-- Draw axis lines through center
	for i = 2, #x_vals - 1 do
		if i ~= cx then
			mese_blk_part(vector.new(x_vals[i], y_vals[cy], z_vals[cz]))
		end
	end
	for i = 2, #y_vals - 1 do
		if i ~= cy then
			mese_blk_part(vector.new(x_vals[cx], y_vals[i], z_vals[cz]))
		end
	end
	for i = 2, #z_vals - 1 do
		if i ~= cz then
			mese_blk_part(vector.new(x_vals[cx], y_vals[cy], z_vals[i]))
		end
	end
end

---@param pos Vector
local function scan_nearby_lights(state, pos, node_name, options, show_log)
	local player_name = state.player_name
	local regions = light_scan_data[player_name]
	local config = p_config.data[player_name]
	local maxy = config.maxy
	---@param r Region
	---@param user_action boolean
	local function base_scan(r, user_action) scan_region_for_node(state, regions, r, pos, node_name, user_action, show_log) end
	---@param r Region
	local function full_scan(r) base_scan(r, true) end
	---@param r Region
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
		---@type SubtractAndAccumulateOptions
		local opts = {
			volume_threshold = 80000,
			max_distance = 26,
			---@param r Region
			on_flush = function(r)
				normal_scan(r)
				table.insert(regions, r)
			end,
		};
		aabb.subtract_and_accumulate(r, regions, opts)
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

local mod_pos = vein_miner.h.mod_pos
local is_liquid = vein_miner.h.is_liquid
local function process_node_group(state, node_name, node, repeat_count)
	local mined_nodes_count = 0
	if is_liquid(node_name, "water") or is_liquid(node_name, "lava") then
		if true then
			return 0, true
		end
		for index, pos in pairs(node) do
			fill_liquid_at_pos(state, pos, utils.handle_pos_notify)
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
	local function dig(pos, node)
		core.node_dig(pos, node, state.player)
		state.wielded:add_wear(dp.wear)
		state.cur_mined_nodes = state.cur_mined_nodes + 1
		mined_nodes_count = mined_nodes_count + 1
	end
	local wear_limit = 65535 - dp.wear
	for index, pos in pairs(node) do
		if state.wielded:get_wear() < wear_limit then
			local p = state.prev_pos
			local area_sector = mod_pos(pos, vector.new(16, 16, 16))
			if p then
				if state.cur_mined_nodes >= state.co_cur_max_nodes then
					yield(state.cur_mined_nodes)
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
			local options = utils.get_scan_options(node_name, {})
			if options.light then
				state.pending_light_notify:push_left({
					pos = pos,
					queue_left = state.queue:length(),
				})
				state.found_light_count = state.found_light_count - 1
			end
			if not options.light or utils.is_floating(pos, node.name) then
				dig(pos, node)
			end
			if options.light then
				local nat_light = core.get_natural_light(pos, 0.5)
				if nat_light > 5 then
					dig(pos, node)
				end
			end
			do
				local tool = state.player:get_wielded_item()
				if tool:get_wear() ~= state.wielded:get_wear() then
					state.wielded:set_wear(tool:get_wear())
				end
				if state.wielded:get_wear() > 65535 - dp.wear * 3 then
					update_wielded_item(state.player, state.wielded)
				end
			end
			state.prev_pos = pos
			state.prev_sector = area_sector
		end
		::next_node::
	end
	return mined_nodes_count
end

local function iter_node_groups(state, iter_nodes)
	local player_name = state.player_name
	state.prev_pos = nil
	local i = 0
	::again::
	for node_name, node in pairs(iter_nodes) do
		local dug_nodes, next_group = process_node_group(state, node_name, node, i)
		if next_group then
			goto continue
		end
		local player = state.player
		if player then
			player_hud.update_nodes_mined(player, state.mined_nodes + state.cur_mined_nodes)
		end
		if dug_nodes > 0 and i < 32 then
			i = i + 1
			goto again
		end
		::continue::
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
		fill_liquid_at_pos(state, pos, utils.handle_pos_notify)
		return
	end
	if options.light then
		state.pending_light_notify:push_left({
			pos = pos,
			queue_left = state.queue:length(),
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
	table.insert_all(target_nodes, mine_only_groups.target_nodes)
	table.insert_all(target_nodes, mine_only_groups.stone)
	table.insert_all(target_nodes, mine_only_groups.stone_like)
	table.insert_all(target_nodes, mine_only_groups.stone_with_ore)
	local target_flags = {
		liquid = true,
		falling = true,
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

	if not utils.has_empty_main_inv_slot(state.player) then
		core.chat_send_player(state.player_name, "Waiting for empty inventory slot for digging")
	end
	while not utils.has_empty_main_inv_slot(state.player) do
		utils.async_wait(3)
	end
	if false and target_flags.liquid then
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

		notify_pos(minvec, "#ffff00ff", 6, 120)

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

local clear_mined_nodes_job = nil

local function dig_finish(state)
	for v in state.pending_light_scan:iter_right() do
		scan_nearby_lights(state, v[1], v[2], v[3], true)
	end
	if state.total_action_count > 0 then
		log_warning("vein miner complete in " .. state.total_action_count .. " steps\n" .. '***')
	elseif state.work_done then
		if state.mined_nodes > 0 then
			log_warning("vein miner complete\n" .. '***')
		else
			log_warning("vein miner complete")
		end
	end
	if clear_mined_nodes_job ~= nil then
		clear_mined_nodes_job:cancel()
		clear_mined_nodes_job = nil
	end
	local player = state.player

	if player then
		clear_mined_nodes_job = core.after(2.5, function() player_hud.update_nodes_mined(player, 0) end)
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
		found_light_count = 0,
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
	utils.add_pos_to_queue(state, node_name, pos, {
		user = true,
	})
end)

function vein_miner.show_layer_bounds(miny, maxy)
	local y_range = "y=" .. (miny + 1) .. ".." .. maxy
	local layer_info = "(layers " .. math.floor((miny + 1) / 8) .. " to " .. math.floor(maxy / 8) .. ")"
	return y_range .. " " .. layer_info
end

core.override_item("", {
	range = 7,
})

local function node_sound_defaults(tbl)
	tbl = tbl or {}
	tbl.footstep = tbl.footstep or {
		name = "",
		gain = 1.0,
	}
	tbl.dug = tbl.dug or {
		name = "default_dug_node",
		gain = 0.25,
	}
	tbl.place = tbl.place or {
		name = "default_place_node_hard",
		gain = 1.0,
	}
	return tbl
end

local function node_sound_stone_defaults(tbl)
	tbl = tbl or {}
	tbl.footstep = tbl.footstep or {
		name = "default_hard_footstep",
		gain = 0.2,
	}
	tbl.dug = tbl.dug or {
		name = "default_hard_footstep",
		gain = 1.0,
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
			stone = 2,
		},
		light_source = light_level,
		drop = node_name,
		sounds = node_sound_stone_defaults(),
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
	recipe = {"default:cobble", "default:mese_crystal_fragment"},
})

core.register_craft({
	type = "shapeless",
	output = "default:cobble 2",
	recipe = {"default:cobble", "vein_miner:lit_cobble_1"},
	replacements = {{"vein_miner:lit_cobble_1", "default:mese_crystal_fragment"}},
})

core.register_craft({
	type = "shapeless",
	output = "vein_miner:lit_cobble_1",
	recipe = {"default:cobble", "vein_miner:lit_cobble_2"},
	replacements = {{"default:cobble", "default:cobble"}},
})

core.register_craft({
	type = "shapeless",
	output = "vein_miner:lit_cobble_2 2",
	recipe = {"vein_miner:lit_cobble_1", "vein_miner:lit_cobble_1"},
})

core.register_craft({
	output = "vein_miner:lit_cobble_2",
	recipe = {{"vein_miner:lit_cobble_1"}},
})

-- Register to handle players

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
	vein_miner.light_region_debug[name] = true

	-- Init the player hud
	player_hud.init_player(player)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	p_config.save_player_config(name)

	player_hud.remove_player(player)
end)
