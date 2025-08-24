local ipairs = ipairs
local pairs = pairs
---@type CoreModApi
local core = core
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

local region_scan_fmt = "[LightScan] scanned region (%d) %s for %s"

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
local VeinMinerState = vein_miner.mt
local function mark_near_light(self, node_name, pos)
	if not is_valid_pos_to_iter(pos, self.player_name) then return end
	local h = core.hash_node_position(pos)
	if not self.known_lights[h] then
		self.known_lights[h] = true
		self:add_pos_to_queue(node_name, pos)
		return true
	end
end

local p = vector.new

---@param state VeinMinerState
---@param regions Region[]
---@param pos Vector
---@param node_name string
---@param config PlayerConfig
local function scan_region_for_node(state, regions, r, pos, node_name, config)
	local scan_nodes = core.find_nodes_in_area(r.min, r.max, node_name, false)
	local count = 0
	for _, p in pairs(scan_nodes) do if mark_near_light(state, node_name, p) then count = count + 1 end end
	if count > 0 then
		state.found_light_count = state.found_light_count + count
		log_warning(region_scan_fmt:format(count, r, node_name))
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
function scanner.scan_nearby_lights(state, pos, node_name, options)
	local name = state.player_name
	local regions = scanner.light_scan_data[name]
	local config = player_config_mgr.data[name]
	local maxy = config.maxy
	---@param r Region
	local function scan(r) scan_region_for_node(state, regions, r, pos, node_name, config) end
	if config.last_maxy ~= config.maxy then
		-- for _, r in ipairs(regions) do scan(r) end
		config.last_maxy = config.maxy
	end
	if options.user then for _, r in ipairs(regions) do if r:is_point_in_region(pos) then scan(r) end end end
	local light_scan_distance = CFG.light_scan_dist
	local minvec = vector.subtract(pos, math.floor(light_scan_distance / 2))
	minvec = scanner.clamp_vec_to_player_bounds(minvec, config)
	local maxvec = vector.add(minvec, light_scan_distance)
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
				scan(r)
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
					scan(r)
					table.insert(regions, r)
				end
			end
		end
	end
	local unknown = aabb.compact_regions(regions)
	for _, r in ipairs(unknown) do scan(r) end
	if newly_scanned and player_config_mgr:is_light_debug_enabled(name) then for _, region in ipairs(regions) do region:draw() end end
end

return scanner
