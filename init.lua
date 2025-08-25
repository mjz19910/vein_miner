local dofile = dofile
---@type CoreModApi
local core = core

local require = dofile(core.get_modpath("vein_miner") .. "/require_local.lua")

vein_miner = {}
---@class VeinMinerGlobal
local vein_miner = vein_miner
local utils = require("mods.vein_miner.utils")
local require = utils.require
_G.require = require
vein_miner.utils = utils

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

---@type VectorModule
local vector = vector

local offset = vector.offset
local string_match = string.match
local floor = math.floor
local ceil = math.ceil
local yield = coroutine.yield
local insert = table.insert
local contains = table.contains
local vec_new = vector.new

local add_particle = core.add_particle

local async_wait = utils.async_wait

---@type table<string, boolean>
vein_miner.light_region_debug = {}

vein_miner.deque = require("mods.vein_miner.deque")
vein_miner.voxel_util = require("mods.vein_miner.voxel_util")
local h = require("mods.vein_miner.helpers")
---@type VeinMinerHelpers
vein_miner.h = h
local is_liquid = h.is_liquid
---@type VeinMinerConfig
local CFG = require("mods.vein_miner.config")
---@type VeinMinerConfig
vein_miner.CFG = CFG
local mining_groups = CFG.mining_groups
local node_to_group = CFG.node_to_group
---@class GroupEntry
---@field nodes string[]
---@field falling_nodes string[]
---@type table<string, GroupEntry>
local node_to_group_cache = {}
---@type AABB
local aabb = require("mods.vein_miner.aabb")
vein_miner.aabb = aabb
local liquid_filler = require("mods.vein_miner.liquid_filler")
---@type LiquidFiller
vein_miner.liquid_filler = liquid_filler
require("mods.vein_miner.remove_walls")
local player_hud = require("mods.vein_miner.player_hud")
vein_miner.player_hud = player_hud
local player_config_mgr = require("mods.vein_miner.player_config")
---@type PlayerConfigManager
vein_miner.player_config_mgr = player_config_mgr
local l_utils = require("mods.vein_miner.late_utils")
---@type VeinMinerLateUtils
vein_miner.l_utils = l_utils
local BlockDigger = require("mods.vein_miner.block_digger")

function vein_miner.show_layer_bounds(miny, maxy)
	local y_range = "y=" .. miny .. ".." .. maxy
	local layer_info = "(layers " .. math.floor(miny / 8) .. " to " .. math.floor(maxy / 8) .. ")"
	return y_range .. " " .. layer_info
end

require("mods.vein_miner.commands")

vein_miner.falling_delay_state = {}
local falling_delay_state = vein_miner.falling_delay_state

---@type Vector[]
falling_delay_state.delayed_list = {}
---@type table<integer, boolean>
falling_delay_state.delayed_set = {}
falling_delay_state.last_falling_node = 0
falling_delay_state.check_for_falling = core.check_for_falling
falling_delay_state.current_tick_time = 0

local falling_delayed_list = falling_delay_state.delayed_list
local falling_delayed_set = falling_delay_state.delayed_set
---@param pos Vector
core.check_for_falling = function(pos)
	local h = core.hash_node_position(pos)
	if not falling_delayed_set[h] then
		falling_delayed_set[h] = true
		insert(falling_delayed_list, pos)
	end
	falling_delay_state.last_falling_node = falling_delay_state.current_tick_time
end

local CFG = vein_miner.CFG
require("mods.vein_miner.lit_cobble")
require("mods.vein_miner.player_lifecycle")

local fill_liquid_at_pos = liquid_filler.fill_liquid_at_pos

local S = core.get_translator("vein_miner")

-- Maximum number of nodes that can be vein mined at once
local MAX_MINED_NODES = 188

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

core.register_on_mods_loaded(function()
	-- Get settings

	-- Check legacy settings
	local allow_ores = core.settings:get_bool("allow_ores")
	local allow_trees = core.settings:get_bool("allow_trees")
	local allow_all = core.settings:get_bool("allow_all")

	-- Fetch settings
	MAX_MINED_NODES = tonumber(core.settings:get("vein_miner_max_nodes"))

	-- Set MAX_MINED_NODES to default value in case getting the setting doesn't work
	if MAX_MINED_NODES == nil then MAX_MINED_NODES = 188 end

	CFG.MAX_MINED_NODES = MAX_MINED_NODES

	-- Use namespaces settings if legacy settings are unset
	if allow_ores == nil then allow_ores = core.settings:get_bool("vein_miner_allow_ores", true) end

	if allow_trees == nil then allow_trees = core.settings:get_bool("vein_miner_allow_trees", false) end

	if allow_all == nil then allow_all = core.settings:get_bool("vein_miner_allow_all", false) end

	-- Initialize tool whitelist with registered tools
	for name, def in pairs(core.registered_tools) do rTools[def.name] = true end

	-- Initialize whitelist for registered nodes
	if allow_all then
		-- wipe rNodes just in case
		for k, v in pairs(rNodes) do rNodes[k] = nil end
		nodeBlacklist = true
		for name, def in pairs(core.registered_nodes) do if def.groups.xray_node then rNodes[name] = true end end
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

	CFG.light_scan_dist = tonumber(core.settings:get("vein_miner_light_scan_distance"))
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
local exclusive_node_set = CFG.exclusive_node_set
local light_nodes_set = CFG.light_nodes_set
local target_set = CFG.target_set

local function get_scan_mode(node_name)
	if ignored_nodes_set[node_name] then return "ignore" end
	if not target_set[node_name] then return "error" end
end

for i, dir in pairs(vec_dirs) do
	for j, dir2 in pairs(vec_dirs) do
		local dir_res = dir + dir2
		local h = core.hash_node_position(dir_res)
		if not joined_dirs_set[h] then
			joined_dirs_set[h] = true
			insert(joined_dirs, dir_res)
		end
	end
end
local function fmt_layer(layer) return "y=" .. (layer * 8) .. ".." .. (layer * 8 + 7) end

local function on_found_empty_space(dir)
	local distance = vector.distance(vector.new(0, 0, 0), dir)
	local hash = core.hash_node_position(dir)
	if not seen_dir_set[hash] then
		seen_dir_set[hash] = true
		if distance < 3 then log_action("teleport location " .. core.pos_to_string(dir) .. " distance " .. distance) end
	end
end

local function on_light_source(pos)
	local res = {}
	for i, v in pairs(vec_dirs) do
		local next_pos = utils.check_pos(pos + v)
		if next_pos then return next_pos end
	end
	for i, dir in pairs(joined_dirs) do
		local distance = vector.distance(vector.new(0, 0, 0), dir)
		if not known_dir_set[core.hash_node_position(dir)] then
			local next_pos = utils.check_pos(pos + dir)
			if next_pos then
				on_found_empty_space(dir)
				insert(res, next_pos)
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
					insert(res, next_pos)
					known_dir_set[core.hash_node_position(dir1 + dir2)] = true
				end
			end
		end
	end
	if #res > 0 then return res[1] end
	log_error("missing air at pos " .. core.pos_to_string(pos))
	return nil
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

local add_to_teleport_queue = false
local function add_light_to_teleport_queue(state, v)
	local pos = v.pos
	local h = core.hash_node_position(pos)
	if not state.teleport_skip_set[h] then
		state.teleport_skip_set[h] = true
		local update_pos = on_light_source(pos)
		local below_pos = vector.offset(pos, 0, -1, 0)
		if update_pos == nil then update_pos = below_pos end
		if add_to_teleport_queue then state.teleport_queue:push_right(update_pos) end
		local tp_diff = core.pos_to_string(vector.subtract(update_pos, pos))
		local target = core.pos_to_string(below_pos)
		log_action("teleport left " .. v.queue_left .. " diff " .. tp_diff .. " trg " .. target)
	end
end

local function iter_node_groups(state, iter_nodes)
	local player_name = state.player_name
	state.prev_pos = nil
	local i = 0
	::again::
	for node_name, node in pairs(iter_nodes) do
		local dug_nodes, next_group = BlockDigger.dig_node_list(state, node_name, node, i)
		if next_group then goto continue end
		local player = state.player
		if player then player_hud.update_nodes_mined(player, state.mined_nodes + state.cur_mined_nodes) end
		if dug_nodes > 0 and i < 32 then
			i = i + 1
			goto again
		end
		::continue::
	end
end
---@param player Player
---@param target_pos Vector
local function try_place_node_from_inventory(player, pos, name)
	local inv = player:get_inventory()
	if inv:contains_item("main", name) then
		local node = core.get_node_or_nil(pos)
		if node then
			if node.name ~= "air" then core.node_dig(pos, node, player) end
			core.set_node(pos, {
				name = name,
			})
			local def = core.registered_nodes[name]
			if def and def.sounds and def.sounds.place then
				core.sound_play(def.sounds.place, {
					pos = pos,
					max_hear_distance = 64,
				})
			end
			inv:remove_item("main", name)
			return true
		end
	end
	return false
end
local function is_passable(node)
	local def = core.registered_nodes[node.name]
	return def and def.walkable == false
end
local function notify_missing_light(player, pos, attach_dir, expire_time)
	local attach_node = core.get_node_or_nil(pos + attach_dir)
	if attach_node == nil or attach_node.name == "air" then return end
	if attach_node.name == "default:water_flowing" then return end
	if attach_node.name == "default:water_source" then return end
	if light_nodes_set[attach_node.name] then return end
	local nat_light = core.get_natural_light(pos, 0.5)
	if nat_light ~= nil and nat_light >= 5 then return end
	local node = core.get_node_or_nil(pos)
	if node == nil or node.name == "air" then
		if not try_place_node_from_inventory(player, pos, "default:mese_post_light_pine_wood") then
			notify_pos(pos + (attach_dir / 16 * 4), "#00ff00ff", 4, expire_time)
		end
	end
end
local xpos = vector.new(1, 0, 0)
local xneg = vector.new(-1, 0, 0)
local ypos = vector.new(0, 1, 0)
local yneg = vector.new(0, -1, 0)
local zpos = vector.new(0, 0, 1)
local zneg = vector.new(0, 0, -1)

local water_targets = {"default:water_flowing", "default:water_source", "default:lava_flowing", "default:lava_source"}

local known_unhandled_nodes = {}

local function is_valid_pos_to_iter(pos, player_name)
	---@type PlayerConfig
	local config = player_config_mgr.data[player_name]
	local maxy = config.maxy
	local miny = config.miny
	if pos.y >= miny and pos.y < maxy then return true end
	return false
end
vein_miner.is_valid_pos_to_iter = is_valid_pos_to_iter

local scanner = require("mods.vein_miner.scanner")
vein_miner.scanner = scanner

require("mods.vein_miner.globalstep")

---@type table<string, boolean>
local falling_groups_all = {
	gravel = true,
	sand = true,
	silver_sand = true,
	desert_sand = true,
	snow = true,
}
---@type table<string, boolean>
local known_groups = {
	cobble = true,
	tree_trunk = true,
	surface = true,
	stem = true,
	snow = true,
	snow_block = true,
	desert_sand = true,
	apple = true,
	butterfly = true,
	firefly = true,
	coral = true,
	green_wool = true,
}
---@type table<string, boolean>
local green_groups = {
	fern = true,
	grass = true,
	cotton = true,
	flower = true,
	papyrus = true,
	mushroom = true,
	blueberry = true,
	dry_grass = true,
	jungle_grass = true,
	marram_grass = true,
}
---@type table<string, boolean>
local wanted_groups = {
	clay = true,
	ore = true,
	stone = true,
	dirt = true,
}
---@type string[]
local green_list = {}
---@type string[]
local wanted_list = {}
---@type string[]
local falling_list_all = {}
for k, _ in pairs(falling_groups_all) do table.insert_all(falling_list_all, mining_groups[k]) end
for k, _ in pairs(green_groups) do table.insert_all(green_list, mining_groups[k]) end
for k, _ in pairs(wanted_groups) do table.insert_all(wanted_list, mining_groups[k]) end

---@type string[]
local cobble_target_list = {}
---@type table<string, boolean>
local cobble_target_groups = {
	cobble = true,
	stem = true,
	tree_trunk = true,
	surface = true,
	cotton = true,
	dry_grass = true,
	fern = true,
	flower = true,
	grass = true,
	jungle_grass = true,
	clay = true,
	ore = true,
	stone = true,
	butterfly = true,
	firefly = true,
	papyrus = true,
	blueberry = true,
	mushroom = true,
	marram_grass = true,
	coral = true,
	snow_block = true,
	green_wool = true,
}

for k, _ in pairs(cobble_target_groups) do table.insert_all(cobble_target_list, mining_groups[k]) end

---@class VeinMinerState
---@field pos Vector
---@field queue Deque<ScanItem>
---@field player Player
---@field player_name string
---@field skip_pos table<integer, boolean>
---@field pending_light_scan Deque
---@param player Player
---@param player_name string
---@param pos Vector
---@param wielded ItemStack
local VeinMinerState = {}
VeinMinerState.__index = VeinMinerState
vein_miner.mt = VeinMinerState

---@param self VeinMinerState
function VeinMinerState:do_update_pos()
	if not self.teleport_queue:is_empty() then
		for cur_pos in self.teleport_queue:iter_right() do
			local h = core.hash_node_position(cur_pos)
			if not self.seen_teleports_set[h] then
				self.seen_teleports_set[h] = true
				cur_pos.y = cur_pos.y - 0.5
				self.player:set_pos(cur_pos)
				-- async_wait(0)
				-- async_wait(0.08)
				-- async_wait(0.5)
			end
		end
		-- local time_left = 0.4 - (0.06 * teleport_queue:length())
		-- if time_left > 0 then
		-- 	async_wait(time_left)
		-- end
		self.teleport_queue.head = 0
		self.teleport_queue.tail = 0
	end
end

---@type table<string, VeinMinerState>
local vein_miner_current_state = {}
---@param nodes string[]
---@param falling_nodes string[]
local function load_cobble_list(nodes, falling_nodes)
	for _, nn in ipairs(cobble_target_list) do
		if contains(falling_list_all, nn) then
			if not contains(falling_nodes, nn) then insert(falling_nodes, nn) end
		elseif not contains(nodes, nn) then
			insert(nodes, nn)
		end
	end
end

---@class ScanItem
---@field node_name string
---@field pos Vector
---@field options ScanOptions
---@field oldnode MapNode | nil

---@param self VeinMinerState
---@param node_name string
---@param pos Vector
---@param options ScanOptions
function VeinMinerState:add_pos_to_queue(node_name, pos, options)
	local h = core.hash_node_position(pos)
	if self.queued_set[h] then return nil end
	self.queued_set[h] = true
	---@type ScanItem
	local item = {
		node_name = node_name,
		pos = pos,
		options = l_utils.get_scan_options(node_name, options),
	}
	self.queue:push_right(item)
	return item
end

local vec_up = vec_new(0, 1, 0)
local vec_down = vec_new(0, -1, 0)

---@param self VeinMinerState
---@param item ScanItem
---@param player_name string
function VeinMinerState:process_queue_item(item, player_name)
	local config = player_config_mgr.data[player_name]
	local player = self.player

	local pos = item.pos
	local node_name = item.node_name
	local options = item.options

	if item.oldnode then BlockDigger.notify_dig(self, pos, item.oldnode) end

	local xz_len = 8
	local y_len = 8
	if config.mode == "large" then
		if pos.y > -32.5 and (not options.light) and (not options.small) then
			xz_len = 32
			y_len = 32
			options.large = true
		end
	end
	if not options.large then options.small = true end

	local vec_size = vector.new(xz_len, y_len, xz_len)
	vec_size = vec_new(8, 8, 8)

	local minvec = h.mod_pos(pos, vec_size)
	minvec = scanner.clamp_vec_to_player_bounds(minvec, config)
	local chunk_hash = core.hash_node_position(minvec)
	local maxvec = vector.add(minvec, vector.subtract(vec_size, 1))
	maxvec = scanner.clamp_vec_to_player_bounds(maxvec, config)

	if self.pos_mod_seen[chunk_hash] then return end
	if not scanner.is_pos_in_player_bounds(pos, config) then return end

	local def = core.registered_nodes[node_name]
	if def.liquidtype == "source" or def.liquidtype == "flowing" then
		fill_liquid_at_pos(self, pos, l_utils.handle_pos_notify)
		return
	end

	if player_config_mgr:is_light_debug_enabled(player_name) then
		local center = vector.floor(vector.divide(vector.add(minvec, maxvec), 2))
		if options.large then
			notify_pos(center, "#0000ffff", 7 * 4, 4 * 60)
		else
			notify_pos(center, "#0000ffff", 7, 4 * 60)
		end
	end

	local target_nodes = {node_name}
	if options.user then
		local extra_node = core.get_node(pos + vec_down)
		local extra_target = extra_node.name
		local def = core.registered_nodes[extra_target]
		if def.liquidtype == "source" then goto skip_below_light_scan end
		if def.liquidtype == "flowing" then goto skip_below_light_scan end
		if node_name ~= extra_target then
			target_nodes[2] = extra_target
			if l_utils.get_scan_options(extra_target).light then
				self.pending_light_scan:push_left({
					pos = pos,
					name = extra_target,
					options = options,
				})
				scanner.scan_nearby_lights(self, pos, extra_target, options)
			end
		end
		::skip_below_light_scan::
	end
	if options.user and options.light then self.found_light_count = self.found_light_count + 1 end
	if not utils.has_empty_main_inv_slot(player) then core.chat_send_player(player_name, "Waiting for empty inventory slot for digging") end
	while not utils.has_empty_main_inv_slot(player) do async_wait(1) end
	iter_node_groups(self, core.find_nodes_in_area(minvec, maxvec, target_nodes, true))
	core.fix_light(minvec, maxvec)
	if options.light then
		self.pending_light_scan:push_left({
			pos = pos,
			name = node_name,
			options = options,
		})
		scanner.scan_nearby_lights(self, pos, node_name, options)
	end

	if not options.large and player_config_mgr:is_light_debug_enabled(player_name) then
		-- allow water to flow
		core.after(5, function()
			local light_timeout = 120
			notify_pos(minvec, "#ffff00ff", 6, light_timeout + 60)
			local lp_north = vector.offset(minvec, 3, 3, 7)
			local lp_south = vector.offset(minvec, 3, 3, 0)
			local lp_west = vector.offset(minvec, 0, 3, 3)
			local lp_east = vector.offset(minvec, 7, 3, 3)
			local lp_down = vector.offset(minvec, 3, 0, 3)
			local lp_up = vector.offset(minvec, 3, 7, 3)
			notify_missing_light(player, lp_east, xpos, light_timeout)
			notify_missing_light(player, lp_west, xneg, light_timeout)
			notify_missing_light(player, lp_up, ypos, light_timeout)
			notify_missing_light(player, lp_down, yneg, light_timeout)
			notify_missing_light(player, lp_north, zpos, light_timeout)
			notify_missing_light(player, lp_south, zneg, light_timeout)
		end)
	end

	self.work_done = true

	self.pos_mod_seen[core.hash_node_position(minvec)] = true
end

-- Recursively mines a vein of blocks
---@param self VeinMinerState
function VeinMinerState:dig_pos()
	self.running = true
	local queue = self.queue
	local player_name = self.player_name
	while not queue:is_empty() do
		local item = self:pop_queue()
		if log_work_start then log_warning("start work on item at " .. core.pos_to_string(item.pos) .. " " .. item.node_name) end
		self:process_queue_item(item, player_name)
		self.mined_nodes = self.mined_nodes + self.cur_mined_nodes
		self.co_cur_max_nodes = self.co_cur_max_nodes - self.cur_mined_nodes
		if self.cur_mined_nodes > 0 then coroutine.yield(self.cur_mined_nodes) end
		self.cur_mined_nodes = 0
		self:do_update_pos()
	end
end

local clear_mined_nodes_job = nil

local function dig_finish(state)
	if state.total_action_count > 0 then
		log_warning("vein miner complete in " .. state.total_action_count .. " steps")
	elseif state.work_done then
		if state.mined_nodes > 0 then
			log_warning("vein miner complete (nodes were mined)")
		else
			log_warning("vein miner complete")
		end
	end
	if clear_mined_nodes_job ~= nil then
		clear_mined_nodes_job:cancel()
		clear_mined_nodes_job = nil
	end
	local player = state.player

	if player then clear_mined_nodes_job = core.after(2.5, function() player_hud.update_nodes_mined(player, 0) end) end
end

local next_loop_action_divisor = 7000;

local function after_delay(data, fn, state)
	if data == nil then
		core.after(0, fn, state)
		return
	end
	if type(data) == "table" then
		if data.wait then core.after(data.time, fn, state) end
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

local function run_to_completion(co, on_complete)
	local status = coroutine.status(co)
	if status == "suspended" then
		core.is_async = true
		local ok, value = coroutine.resume(co)
		core.is_async = nil
		if not ok then
			log_error("run_to_completion error " .. value)
			log_error(debug.traceback(co))
		else
			if value and value.time ~= nil then
				core.after(value.time, run_to_completion, co, on_complete)
			else
				core.after(0, run_to_completion, co, on_complete)
			end

		end
	elseif status == "dead" then
		if on_complete ~= nil then on_complete() end
	else
		log_error("unexpected coroutine status in run_to_completion " .. status)
	end
end

---@class LightScanParams
---@field pos Vector
---@field name string
---@field options ScanOptions

---@param state VeinMinerState
local function vein_miner_step(state)
	::start::
	if state.thread == nil then state.thread = coroutine.create(function() return state:dig_pos() end) end
	local co = state.thread
	local co_status = coroutine.status(co)
	if co_status == "suspended" then
		core.is_async = true
		local status, action_count = coroutine.resume(co)
		core.is_async = nil
		if not status then
			log_error("vein_miner coroutine error " .. action_count)
			log_error(debug.traceback(co))
		else
			after_delay(action_count, vein_miner_step, state)
		end
	elseif co_status == "dead" then
		if not state.queue:is_empty() then
			state.thread = nil
			goto start
		else
			local function on_complete()
				if not state.queue:is_empty() then return vein_miner_step(state) end
				dig_finish(state)
				vein_miner_current_state[state.player_name] = nil
			end
			run_to_completion(coroutine.create(function()
				---@type LightScanParams
				for v in state.pending_light_scan:iter_right() do scanner.scan_nearby_lights(state, v.pos, v.name, v.options, true) end
				state.pending_light_scan.head = 0
				state.pending_light_scan.tail = 0
			end), on_complete)
		end
	else
		log_error("unexpected coroutine status " .. co_status)
	end
end

function VeinMinerState.wait_for_player_near_pos(player, target_pos)
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
	if out_of_range then async_wait(0.6) end
end

-- Update wielded item
function VeinMinerState.update_wielded_item(player, wielded)
	local tool = player:get_wielded_item()
	if tool:get_name() == wielded:get_name() then
		local wear_amount = 1 - (wielded:get_wear() / 65535)
		if wear_amount < 0.85 then log_action("high wear action " .. wear_amount) end
		wielded:set_wear(0)
		player:set_wielded_item(wielded)
	end
end

---@param self VeinMinerState
---@return ScanItem
function VeinMinerState:pop_queue() return self.queue:pop_left() end
---@param self VeinMinerState
function VeinMinerState:is_queue_empty() return self.queue:is_empty() end

---@param player Player
---@param player_name string
---@param pos Vector
---@param wielded ItemStack
function VeinMinerState.new(pos, player, player_name, wielded)
	---@type VeinMinerState
	local self = {
		pos = pos,
		player = player,
		player_name = player_name,
		wielded = wielded,
		prev_pos = nil,
		prev_sector = nil,
		running = false,
		work_done = false,
		total_action_count = 0,
		found_light_count = 0,
		mined_nodes = 0,
		cur_mined_nodes = 0,
		warn_next = 200,
		co_cur_max_nodes = MAX_MINED_NODES,
		queued_set = {},
		skip_pos = {},
		seen_teleports_set = {},
		logged_teleports = {},
		teleport_skip_set = {},
		known_lights = {},
		pos_mod_seen = {},
		queue = vein_miner.deque.new(),
		teleport_queue = vein_miner.deque.new(),
		falling_check_nodes = vein_miner.deque.new(),
		-- pending_light_notify = vein_miner.deque.new(),
		pending_light_scan = vein_miner.deque.new(),
	}

	return setmetatable(self, VeinMinerState)
end

---@class MapNode
---@field name string
---@param pos Vector
---@param oldnode MapNode
---@param player Player|nil
core.register_on_dignode(function(pos, oldnode, player)
	if core.is_async then return end
	if player == nil then return end
	if oldnode == nil then return end
	local node_name = oldnode.name
	if pos == nil then return end
	if player:get_player_control().sneak then return end
	local wielded = player:get_wielded_item()
	if not is_node_vein_diggable(node_name, wielded:get_name()) then return end

	-- start vein mining
	local player_name = player:get_player_name()
	if player_config_mgr.data[player_name] == nil then player_config_mgr.data[player_name] = {} end
	local config = player_config_mgr.data[player_name]
	if config.mode == nil then config.mode = "small" end
	local state = vein_miner_current_state[player_name]
	if state == nil then
		state = VeinMinerState.new(pos, player, player_name, wielded)
		vein_miner_current_state[player_name] = state
	end
	local q_item = state:add_pos_to_queue(node_name, pos, {
		user = true,
	})
	if q_item then q_item.oldnode = oldnode end
	if not state.running then vein_miner_step(state) end
end)
require("mods.vein_miner.hand_override")
-- a tool not in the tools module
require("mods.vein_miner.auto_floor")
-- load the tools module
require("mods.vein_miner.tools")
require("mods.vein_miner.abm")
require("mods.vein_miner.src.mod")
