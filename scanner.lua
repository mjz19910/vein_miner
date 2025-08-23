local ipairs = ipairs
local pairs = pairs
---@type VeinMinerGlobal
local vein_miner = vein_miner
local aabb = vein_miner.aabb
local CFG = vein_miner.CFG
local l_utils = vein_miner.l_utils

local log_error = vein_miner.h.log_error
local log_warning = vein_miner.h.log_warning
local log_action = vein_miner.h.log_action

---@class Scanner
local scanner = {}

local region_scan_fmt2 = " [LightScan] scanned region (%d) %s [%s]"
local region_scan_fmt1 = "[LightScan] scanned region (%d) %s"

local is_valid_pos_to_iter = vein_miner.is_valid_pos_to_iter

--- Clamp a vector's y to player bounds
---@param vec Vector
---@param config PlayerConfig
---@return Vector
function scanner.clamp_vec_to_player_bounds(vec, config)
	if vec.y < config.miny then
		vec.y = config.miny
	elseif vec.y >= config.maxy then
		vec.y = config.maxy - 1
	end
	return vec
end

--- Checks if a position is within player bounds
---@param pos Vector
---@param config PlayerConfig
---@return boolean
function scanner.is_pos_in_player_bounds(pos, config) return pos.y >= config.miny and pos.y < config.maxy end

local function count_found_nodes(state, iter, orig_pos, config)
	local count = 0
	for idx, next_pos in pairs(iter) do
		if not scanner.is_pos_in_player_bounds(next_pos, config) then goto skip end
		if orig_pos ~= next_pos then count = count + 1 end
		::skip::
	end
	return count
end

local function scan_nearby_region(state, r1, offset_vec, offset_str, pos, node_name, config)
	local r2 = aabb.new_region(r1.min + offset_vec, r1.max + offset_vec)
	local list = core.find_nodes_in_area(r2.min, r2.max, node_name, false)
	local count = count_found_nodes(state, list, pos, config)
	if count > 0 then log_action(region_scan_fmt2:format(count, r2, offset_str)) end
end

local VeinMinerState = vein_miner.mt

local function mark_near_light(self, node_name, pos)
	if not is_valid_pos_to_iter(pos, self.player_name) then return false end
	local h = core.hash_node_position(pos)
	if not self.known_lights[h] then
		self.known_lights[h] = true
		self:add_pos_to_queue(node_name, pos)
		return true
	end
	return false
end

local p = vector.new

---@param state VeinMinerState
---@param regions Region[]
---@param pos Vector
---@param node_name string
---@param user_action boolean
---@param show_log boolean
---@param config PlayerConfig
local function scan_region_for_node(state, regions, r, pos, node_name, user_action, show_log, config)
	local center = (r.min + r.max) / 2
	local scan_distance = vector.distance(state.player:get_pos(), center)
	if false then
		if not show_log then return end
		local scan_nodes = core.find_nodes_in_area(r.min, r.max, node_name, false)
		local count = count_found_nodes(state, scan_nodes, pos, config)
		if count > 0 or user_action then
			local region_scan_fmt = "[LightScan] skipped region (%s) %s to %s (%s) Volume=%d Distance=%d"
			local min_str = core.pos_to_string(r.min)
			local max_str = core.pos_to_string(r.max)
			local size_str = core.pos_to_string(r.max - r.min)
			log_error(region_scan_fmt:format(count, min_str, max_str, size_str, aabb.volume(r), scan_distance))
		end
		return
	end
	-- state.wait_for_player_near_pos(state.player, center)
	local scan_nodes = core.find_nodes_in_area(r.min, r.max, node_name, false)
	local count = count_found_nodes(state, scan_nodes, pos, config)
	for _, p in pairs(scan_nodes) do
		local is_new_light = mark_near_light(state, node_name, p)
		if is_new_light then state.found_light_count = state.found_light_count + 1 end
	end
	if count > 0 or user_action then
		if not show_log then return end
		local min_str = core.pos_to_string(r.min)
		local max_str = core.pos_to_string(r.max)
		local size = r.max - r.min
		local size_str = core.pos_to_string(size)
		log_warning(region_scan_fmt1:format(count, r))
		local function scan_near(next_pos, next_pos_name) scan_nearby_region(state, r, next_pos, next_pos_name, pos, node_name, config) end
		scan_near(p(size.x, 0, 0), "X+")
		scan_near(p(-size.x, 0, 0), "X-")
		scan_near(p(0, size.y, 0), "Y+")
		scan_near(p(0, -size.y, 0), "Y-")
		scan_near(p(0, 0, size.z), "Z+")
		scan_near(p(0, 0, -size.z), "Z-")
		scan_near(p(size.x, 0, -size.z), "X+ Z-")
		scan_near(p(size.x, 0, size.z), "X+ Z+")
		scan_near(p(size.x, size.y, 0), "X+ Y+")
		scan_near(p(size.x, -size.y, 0), "X+ Y-")
		scan_near(p(size.x, size.y, -size.z), "X+ Y+ Z-")
		scan_near(p(size.x, size.y, size.z), "X+ Y+ Z+")
		scan_near(p(size.x, -size.y, -size.z), "X+ Y- Z-")
		scan_near(p(size.x, -size.y, size.z), "X+ Y- Z+")
		scan_near(p(-size.x * 2, 0, 0), "X- X-")
		scan_near(p(-size.x, 0, size.z), "X- Z+")
		scan_near(p(-size.x, 0, -size.z), "X- Z-")
		scan_near(p(-size.x, size.y, 0), "X- Y+")
		scan_near(p(-size.x, -size.y, 0), "X- Y-")
		scan_near(p(-size.x, size.y, -size.z), "X- Y+ Z-")
		scan_near(p(-size.x, -size.y, -size.z), "X- Y- Z-")
		scan_near(p(-size.x, size.y, size.z), "X- Y+ Z+")
		scan_near(p(-size.x, -size.y, size.z), "X- Y- Z+")
		scan_near(p(size.x * 2, 0, 0), "X+ X+")
		scan_near(p(0, size.y, size.z), "Y+ Z+")
		scan_near(p(0, size.y, -size.z), "Y+ Z-")
		scan_near(p(0, -size.y * 2, 0), "Y- Y-")
		scan_near(p(0, -size.y, size.z), "Y- Z+")
		scan_near(p(0, -size.y, -size.z), "Y- Z-")
		scan_near(p(0, size.y * 2, 0), "Y+ Y+")
		scan_near(p(0, 0, size.z * 2), "Z+ Z+")
		scan_near(p(0, 0, -size.z * 2), "Z- Z-")
	end
end

local player_config_mgr = vein_miner.player_config_mgr

---@type table<string, Region[]>
scanner.light_scan_data = {}

function scanner.light_scan_reset(name) scanner.light_scan_data[name] = {} end

---@param state VeinMinerState
---@param pos Vector
---@param node_name string
---@param options ScanOptions
---@param show_log boolean
function scanner.scan_nearby_lights(state, pos, node_name, options, show_log)
	local name = state.player_name
	local regions = scanner.light_scan_data[name]
	local config = player_config_mgr.data[name]
	local maxy = config.maxy
	---@param r Region
	---@param user_action boolean
	local function base_scan(r, user_action) scan_region_for_node(state, regions, r, pos, node_name, user_action, show_log, config) end
	---@param r Region
	local function full_scan(r) base_scan(r, true) end
	---@param r Region
	local function normal_scan(r) base_scan(r, false) end
	if config.last_maxy ~= config.maxy then
		for _, r in ipairs(regions) do normal_scan(r) end
		config.last_maxy = config.maxy
	end
	if options.user then for _, r in ipairs(regions) do if r:is_point_in_region(pos) then full_scan(r) end end end
	local scan_dist = CFG.light_scan_dist
	local scan_range = scan_dist / 2
	local minvec = vector.subtract(pos, math.floor(scan_range))
	minvec = scanner.clamp_vec_to_player_bounds(minvec, config)
	local maxvec = vector.add(minvec, scan_dist)
	maxvec = scanner.clamp_vec_to_player_bounds(maxvec, config)
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
	for _, r in ipairs(unknown) do normal_scan(r) end
	for _, r in ipairs(regions) do
		local size = r.min - r.max
		local size_change = scan_dist
		if size_change < 1 then size_change = 1 end
		r.min.x = r.min.x + size_change
		r.max.x = r.max.x - size_change
		r.min.y = r.min.y + size_change
		r.max.y = r.max.y - size_change
		r.min.z = r.min.z + size_change
		r.max.z = r.max.z - size_change
	end
	if newly_scanned and player_config_mgr:is_light_debug_enabled(name) then for _, region in ipairs(regions) do region:draw() end end
end

return scanner
