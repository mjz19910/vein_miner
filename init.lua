---@type LuantiCore
local core = core
local dofile = dofile

local require = dofile(core.get_modpath("vein_miner") .. "/require_local.lua")

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
local debug = debug
local offset = vector.offset
local string_match = string.match
local floor = math.floor
local ceil = math.ceil
local yield = coroutine.yield
local add_particle = core.add_particle

vein_miner = {}
---@class VeinMinerGlobal
local vein_miner = vein_miner
local utils = require("mods.vein_miner.utils")
local require = utils.require
vein_miner.utils = utils
vein_miner.deque = require("mods.vein_miner.deque")
vein_miner.voxel_util = require("mods.vein_miner.voxel_util")
require("mods.vein_miner.config")
require("mods.vein_miner.helpers")
---@type VeinMinerHelpers
local h = require("mods.vein_miner.helpers")
vein_miner.h = h
---@type AABB
local aabb = require("mods.vein_miner.aabb")
vein_miner.aabb = aabb
require("mods.vein_miner.liquid_filler")
require("mods.vein_miner.remove_walls")
---@type PlayerHud
local player_hud = require("mods.vein_miner.player_hud")
vein_miner.player_hud = player_hud
---@type PlayerConfigManager
local p_config = require("mods.vein_miner.player_config")
vein_miner.player_config = p_config
local l_utils = require("mods.vein_miner.late_utils")
vein_miner.l_utils = l_utils
local BlockDigger = require("mods.vein_miner.block_digger")

function vein_miner.show_layer_bounds(miny, maxy)
	local y_range = "y=" .. miny .. ".." .. maxy
	local layer_info = "(layers " .. math.floor(miny / 8) .. " to " .. math.floor(maxy / 8) .. ")"
	return y_range .. " " .. layer_info
end

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
local CFG = vein_miner.CFG
require("mods.vein_miner.lit_cobble")
require("mods.vein_miner.player_lifecycle")

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

	CFG.MAX_MINED_NODES = MAX_MINED_NODES

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

local storage = core.get_mod_storage()

local vec_dirs = CFG.VEC_DIRS
local seen_dir_set = {}
local joined_dirs = {}
local joined_dirs_set = {}
local known_dir_set = {}

---@type table<string, VeinMinerState>
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

local ignored_nodes_set = CFG.ignored_nodes_set
local surface_nodes_set = CFG.surface_nodes_set
local light_nodes_set = CFG.light_nodes_set

local function get_scan_mode(node_name)
	if ignored_nodes_set[node_name] then
		return "inc_mine_skip"
	end
	if light_nodes_set[node_name] then
		return "add_current"
	end
	if surface_nodes_set[node_name] then
		return "only_current"
	end
	if mine_only_cur_set[node_name] then
		return "mine_only_cur"
	end
	return "error"
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
	---@type PlayerConfig
	local config = p_config.data[player_name]
	local maxy = config.maxy
	local miny = config.miny
	if pos.y >= miny and pos.y < maxy then
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
		l_utils.add_pos_to_queue(state, node_name, pos)
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
	local r2 = aabb.new_region(r1.min + offset_vec, r1.max + offset_vec)
	local list = core.find_nodes_in_area(r2.min, r2.max, node_name, false)
	local count = count_found_nodes(list, pos, state.player_name)
	if count > 0 then
		log_action(region_scan_fmt2:format(count, r2, offset_str))
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
		log_warning(region_scan_fmt1:format(count, r))
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
			if r:is_point_in_region(pos) then
				full_scan(r)
			end
		end
	end
	local scan_dist = light_scan_dist
	local scan_range = scan_dist / 2
	local minvec = vector.subtract(pos, math.floor(scan_range))
	local maxvec = vector.add(minvec, scan_dist)
	if maxvec.y > maxy then
		maxvec.y = maxy
	end
	local total_count = 0
	local r = aabb.new_region(minvec, maxvec)
	local newly_scanned = not r:is_inside_any(regions)
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
			if gap and gap:volume() < GAP_THRESHOLD then
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
			r:draw()
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

local function iter_node_groups(state, iter_nodes)
	local player_name = state.player_name
	state.prev_pos = nil
	local i = 0
	::again::
	for node_name, node in pairs(iter_nodes) do
		local dug_nodes, next_group = BlockDigger.dig_node_list(state, node_name, node, i)
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
	if light_nodes_set[attach_node.name] then
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

local is_liquid = h.is_liquid

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

	local minvec = h.mod_pos(pos, vec_size)
	local chunk_hash = core.hash_node_position(minvec)
	local maxvec = vector.add(minvec, vector.subtract(vec_size, 1))

	if minvec.y < config.miny then
		minvec.y = config.miny
	end
	if maxvec.y > config.maxy then
		maxvec.y = config.maxy
	end

	if state.pos_mod_seen[chunk_hash] then
		return
	end

	if not is_valid_pos_to_iter(pos, player_name) then
		return
	end

	if is_liquid(node_name, "water") or is_liquid(node_name, "lava") then
		fill_liquid_at_pos(state, pos, l_utils.handle_pos_notify)
		return
	end
	if options.light then
		state.pending_light_notify:push_left({
			pos = pos,
			queue_left = state.queue:length(),
		})
	end

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
	table.insert_all(target_nodes, mine_only_groups.ore)
	local target_flags = {
		liquid = true,
		falling = true,
	}
	local scan_mode = get_scan_mode(node_name)
	core.log("warning", "scan_mode " .. scan_mode)
	if scan_mode == "error" then
		if not known_unhandled_nodes[node_name] then
			known_unhandled_nodes[node_name] = true
			log_error("unhandled node name " .. node_name)
		end
		return
	end
	if scan_mode == "inc_mine_skip" then
		return
	end
	if scan_mode == "only_current" then
		target_nodes = {}
		target_flags.falling = false
		target_flags.liquid = false
		table.insert(target_nodes, node_name)
	end
	if scan_mode == "add_current" then
		table.insert(target_nodes, node_name)
	end
	local group_target = nil
	if scan_mode == "mine_only_cur" then
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

local VeinMinerState = {}
VeinMinerState.__index = VeinMinerState

-- Update wielded item
function VeinMinerState.update_wielded_item(player, wielded)
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

vein_miner.state = {}
---@class VeinMinerState
---@field pos Vector
---@field queue Deque
---@param player Player
---@param player_name string
---@param pos Vector
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
		running = false,
	}

	return setmetatable(state, VeinMinerState)
end

---@class MapNode
---@field name string
---@param pos Vector
---@param oldnode MapNode
---@param player Player|nil
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
	end
	l_utils.add_pos_to_queue(state, node_name, pos, {
		user = true,
	})
	if not state.running then
		vein_miner_step(state)
	end
end)
require("mods.vein_miner.hand_override")
-- a tool not in the tools module
require("mods.vein_miner.auto_floor")
-- load the tools module
require("mods.vein_miner.tools")
require("mods.vein_miner.abm")
