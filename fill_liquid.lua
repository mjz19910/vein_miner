-- local builtin lua functions
local ipairs = ipairs
local pairs = pairs
local setmetatable = setmetatable
local next = next

-- local builtin lua tables
local table = table
-- local vector = vector
local coroutine = coroutine

-- local builtin lua table functions
local insert_all = table.insert_all
local vec_new = vector.new
local zero = vector.zero
local co_wrap = coroutine.wrap
local co_yield = coroutine.yield

-- minetest tables
local core = core
local minetest = minetest
local VoxelArea = VoxelArea
local VoxelManip = VoxelManip

-- minetest table functions
local pos_str = core.pos_to_string
local cid = core.get_content_id

-- vein_miner tables
local vein_miner = vein_miner
local aabb = aabb
local helpers = vein_miner.h

-- vein_miner table functions
local new_region = aabb.region
local log_action = helpers.log_action

-- constants
local cardinal_dirs = {vec_new(1, 0, 0), vec_new(-1, 0, 0), vec_new(0, 1, 0), vec_new(0, -1, 0), vec_new(0, 0, 1), vec_new(0, 0, -1)}
local liquid_set = {
	["default:water_source"] = true,
	["default:water_flowing"] = true,
	["default:lava_source"] = true,
	["default:lava_flowing"] = true,
}

local cid_air, cid_wool_green

local cids_source, cids_flowing
local cids_replace = {}

core.register_on_mods_loaded(function()
	local cid_water_source = cid("default:water_source")
	local cid_water_flowing = cid("default:water_flowing")
	local cid_lava_source = cid("default:lava_source")
	local cid_lava_flowing = cid("default:lava_flowing")

	cids_source = {
		[cid_water_source] = true,
		[cid_lava_source] = true,
	}
	cids_flowing = {
		[cid_water_flowing] = true,
		[cid_lava_flowing] = true,
	}

	for k, v in pairs(cids_source) do
		cids_replace[k] = v
	end
	for k, v in pairs(cids_flowing) do
		cids_replace[k] = v
	end

	cid_air = cid("air")
	cid_wool_green = cid("wool:green")
end)

local vec_add = vector.add
local vec_sub = vector.subtract

local function expand_region(region, amount)
	region.min = vec_sub(region.min, amount)
	region.max = vec_add(region.max, amount)
end

local function shrink_region(region, amount)
	region.min = vec_add(region.min, amount)
	region.max = vec_sub(region.max, amount)
end

local function push(qx, qy, qz, q_tail, x, y, z)
	qx[q_tail], qy[q_tail], qz[q_tail] = x, y, z
	return q_tail + 1
end

local hash_pos = core.hash_node_position

local function maybe_enqueue(qx, qy, qz, q_tail, visited, x, y, z)
	local hash = hash_pos(vec_new(x, y, z))
	if not visited[hash] then
		visited[hash] = true
		return push(qx, qy, qz, q_tail, x, y, z)
	end
	return q_tail
end

local function read_voxels_from_map(vm, region)
	local emin, emax = vm:read_from_map(region.min, region.max)
	local area = VoxelArea:new{
		MinEdge = emin,
		MaxEdge = emax,
	}
	local data = vm:get_data()
	return area, data
end

local State = {}
State.__index = State

function State:new(vm, cid_wall)
	local self = setmetatable({
		vm = vm,
		cid_wall = cid_wall,
		cids_replace = cids_replace,
		cids_source = cids_source,
		cids_flowing = cids_flowing,
	}, State)
	return self
end

function State:reload_region(region)
	local area, data = read_voxels_from_map(self.vm, region)
	self.area = area
	self.data = data
end

local function expand_axis_from_center(state, region, axis, limit, skip_flag)
	local area = state.area
	local data = state.data
	local cids_replace = state.cids_replace

	local size = region.max[axis] - region.min[axis] + 1
	if size >= limit then
		skip_flag[1] = true
		return false
	end

	local expanded = false
	while size < limit do
		local did_expand = false

		-- Positive direction
		local new_max = region.max[axis] + 1
		local found_positive = false
		for y = region.min.y, region.max.y do
			for z = region.min.z, region.max.z do
				local pos = zero()
				pos[axis] = new_max
				pos.y = y
				pos.z = (axis == "x") and z or region.min.z + (z - region.min.z)
				local idx = area:index(pos.x, pos.y, pos.z)
				if cids_replace[data[idx]] then
					found_positive = true
					break
				end
			end
			if found_positive then
				break
			end
		end
		if found_positive then
			region.max[axis] = new_max
			did_expand = true
		end

		-- Negative direction
		local new_min = region.min[axis] - 1
		local found_negative = false
		for y = region.min.y, region.max.y do
			for z = region.min.z, region.max.z do
				local pos = zero()
				pos[axis] = new_min
				pos.y = y
				pos.z = (axis == "x") and z or region.min.z + (z - region.min.z)
				local idx = area:index(pos.x, pos.y, pos.z)
				if cids_replace[data[idx]] then
					found_negative = true
					break
				end
			end
			if found_negative then
				break
			end
		end
		if found_negative then
			region.min[axis] = new_min
			did_expand = true
		end

		if not did_expand then
			break
		end

		size = region.max[axis] - region.min[axis] + 1
		expanded = true
	end

	if not expanded then
		skip_flag[1] = true
	end
	return expanded
end

local function expand_vertical_axis(state, region, skip_y, notify_pos, vein_miner_state)
	local area = state.area
	local data = state.data
	local cids_replace = state.cids_replace

	local size_x, size_z, size_y = region.max.x - region.min.x, region.max.z - region.min.z, region.max.y - region.min.y

	local function notify_limit(pos) notify_pos(vein_miner_state, pos) end

	if skip_y[1] then
		return false
	end

	local expanded = false

	-- Try expand downward by one
	do
		local y = region.min.y - 1
		for z = region.min.z, region.max.z do
			for x = region.min.x, region.max.x do
				local idx = area:index(x, y, z)
				if cids_replace[data[idx]] then
					region.min.y = y
					notify_limit(vec_new(x, y, z)) -- notify the liquid node position on min face
					expanded = true
					break
				end
			end
			if expanded then
				break
			end
		end
	end

	-- Try expand upward by one
	if not skip_y[1] then
		local y = region.max.y + 1
		for z = region.min.z, region.max.z do
			for x = region.min.x, region.max.x do
				local idx = area:index(x, y, z)
				if cids_replace[data[idx]] then
					region.max.y = y
					notify_limit(vec_new(x, y, z)) -- notify liquid node pos on max face
					expanded = true
					break
				end
			end
			if expanded then
				break
			end
		end
	end

	-- Check size limits and notify if exceeded
	if expanded then
		local new_size_y = region.max.y - region.min.y
		if not ((size_x < 64 and size_z < 64 and new_size_y < 64 * 3) or new_size_y < 64) then
			skip_y[1] = true
			return false
		end
		return true
	end

	return false
end

local EXPAND_AMOUNT = 1

local function expand_region_to_include(state, region, pos)
	local vm = state.vm

	-- Log warning about expansion
	core.log("warning", ("Expanding voxel area bounds to include position %s"):format(pos_str(pos)))

	-- Expand bounds by EXPAND_AMOUNT blocks where pos is outside
	if pos.x < region.min.x then
		region.min.x = pos.x - EXPAND_AMOUNT
	elseif pos.x > region.max.x then
		region.max.x = pos.x + EXPAND_AMOUNT
	end

	if pos.z < region.min.z then
		region.min.z = pos.z - EXPAND_AMOUNT
	elseif pos.z > region.max.z then
		region.max.z = pos.z + EXPAND_AMOUNT
	end

	core.log("warning", ("Expanding voxel area to new region from %s to %s"):format(pos_str(region.min), pos_str(region.max)))

	-- Re-read voxel data and update area
	local area, data = read_voxels_from_map(vm, region)
	state.area = area
	state.data = data
end

local function ensure_pos_in_area(state, pos)
	if not state.area:containsp(pos) then
		expand_region_to_include(state, pos)
		return true
	end
	return false
end

-- Helper iterator over positions inside the region
local function iter_region_positions(region)
	local minx, maxx = region.min.x, region.max.x
	local miny, maxy = region.min.y, region.max.y
	local minz, maxz = region.min.z, region.max.z

	return co_wrap(function()
		for z = minz, maxz do
			for y = miny, maxy do
				for x = minx, maxx do
					co_yield(vec_new(x, y, z))
				end
			end
		end
	end)
end

local function is_useless_wall(state, pos)
	local did_expand = false
	local idx = state.area:indexp(pos)
	if state.data[idx] ~= state.cid_wall then
		return false
	end

	for _, off in ipairs(cardinal_dirs) do
		local neighbor_pos = pos + off
		local nidx = state.area:indexp(neighbor_pos)
		if state.cids_replace[state.data[nidx]] then
			return false
		end
	end

	return true
end

local function region_equals(region, b_min, b_max) return vector.equals(region.min, b_min) and vector.equals(region.max, b_max) end

-- Returns true if position is a wall node
local function is_wall(state, pos)
	local idx = state.area:indexp(pos)
	return state.data[idx] == state.cid_wall
end

-- Returns true if position is a liquid node (source or flowing)
local function is_liquid(state, pos)
	local idx = state.area:indexp(pos)
	return state.cids_replace[state.data[idx]] == true
end

-- Checks if wall at pos is adjacent to liquid; if yes, it’s necessary
local function is_wall_adjacent_to_liquid(state, pos)
	for _, off in ipairs(cardinal_dirs) do
		local npos = pos + off
		ensure_pos_in_area(state, npos)
		if is_liquid(state, npos) then
			return true
		end
	end
	return false
end

-- DFS to mark reachable walls connected to liquid or boundary as necessary
local function dfs_mark_necessary(state, start_pos, visited)
	local stack = {start_pos}

	while #stack > 0 do
		local pos = table.remove(stack)
		local hash = hash_pos(pos)
		if visited[hash] then
			goto continue
		end
		visited[hash] = true

		if not is_wall(state, pos) then
			goto continue
		end

		-- Mark as necessary by setting visited true

		-- Explore neighbors
		for _, off in ipairs(cardinal_dirs) do
			local npos = pos + off
			local in_region = state.area:containsp(npos)
			if in_region and not visited[hash_pos(npos)] then
				stack[#stack + 1] = npos
			end
		end

		::continue::
	end
end

local function visualize_region_particles(region, params)
	local min, max = region.min, region.max

	for x = min.x, max.x do
		for y = min.y, max.y do
			for z = min.z, max.z do
				local on_edge = ((x == min.x or x == max.x) and 1 or 0) + ((y == min.y or y == max.y) and 1 or 0) +
					                ((z == min.z or z == max.z) and 1 or 0)

				if on_edge == 2 then -- edges of the bounding box
					local pos = vec_new(x + 0.5, y + 0.5, z + 0.5)
					minetest.add_particle({
						pos = pos,
						velocity = vec_new(0, 0, 0),
						expirationtime = params.expirationtime,
						size = params.size,
						texture = params.texture,
						glow = params.glow,
					})
				end
			end
		end
	end
end

local wall_region_cache = {} -- list of { region = {min=vec, max=vec}, state = {...} }

-- Globalstep timer for particle visualization
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer >= 1 then -- every second
		timer = 0
		local particle_params = {
			texture = "default_diamond.png",
			expirationtime = 2, -- particles last 2 seconds
			size = 5,
			glow = 15,
		}
		for _, entry in ipairs(wall_region_cache) do
			visualize_region_particles(entry.region, particle_params)
		end
	end
end)

local function pos_in_region(pos, region)
	local min = region.min
	local max = region.max
	return pos.x >= min.x and pos.x <= max.x and pos.y >= min.y and pos.y <= max.y and pos.z >= min.z and pos.z <= max.z
end

local function get_cached_wall_state(pos)
	for _, entry in ipairs(wall_region_cache) do
		if pos_in_region(pos, entry.region) then
			return entry.state
		end
	end
	return nil
end

local function cache_wall_region(region, state)
	table.insert(wall_region_cache, {
		region = region,
		state = state,
	})
end

-- Remove walls not marked as necessary by DFS
local function remove_unnecessary_walls(state, region)
	local visited = {}
	local wall_search_region = region:shrink(1)

	-- First, mark all walls adjacent to liquid as necessary
	for pos in iter_region_positions(wall_search_region) do
		if is_wall(state, pos) and is_wall_adjacent_to_liquid(state, pos) then
			dfs_mark_necessary(state, pos, visited)
		end
	end

	-- Then, remove walls that are not visited (not necessary)
	for pos in iter_region_positions(wall_search_region) do
		local hash = hash_pos(pos)
		if is_wall(state, pos) and not visited[hash] then
			local idx = state.area:indexp(pos)
			state.data[idx] = state.cid_air
		end
	end
end

local function aabb_overlap(r1, r2)
	return not (r1.max.x < r2.min.x or r1.min.x > r2.max.x or r1.max.y < r2.min.y or r1.min.y > r2.max.y or r1.max.z < r2.min.z or r1.min.z >
		       r2.max.z)
end

local function remove_overlapping_wall_regions(cache)
	local to_remove = {}

	-- Find all overlapping region pairs
	for i = 1, #cache do
		for j = i + 1, #cache do
			if aabb_overlap(cache[i].region, cache[j].region) then
				to_remove[i] = true
				to_remove[j] = true
			end
		end
	end

	-- Remove all overlapping regions
	local new_cache = {}
	for i, entry in ipairs(cache) do
		if not to_remove[i] then
			table.insert(new_cache, entry)
		end
	end

	-- Replace cache contents
	for i = 1, #cache do
		cache[i] = nil
	end
	for i, entry in ipairs(new_cache) do
		cache[i] = entry
	end
end

local function flood_fill_liquid(start_pos, limit)
	local visited = {}
	local qx, qy, qz = {}, {}, {}
	local q_head, q_tail = 1, 1
	local count = 0

	local minx, miny, minz = start_pos.x, start_pos.y, start_pos.z
	local maxx, maxy, maxz = start_pos.x, start_pos.y, start_pos.z

	visited[hash_pos(start_pos)] = true
	q_tail = push(qx, qy, qz, q_tail, start_pos.x, start_pos.y, start_pos.z)

	while q_head < q_tail do
		local x, y, z = qx[q_head], qy[q_head], qz[q_head]
		q_head = q_head + 1

		if not liquid_set[core.get_node(vec_new(x, y, z)).name] then
			goto continue
		end

		count = count + 1
		if count > limit then
			goto continue
		end

		minx, maxx = math.min(minx, x), math.max(maxx, x)
		miny, maxy = math.min(miny, y), math.max(maxy, y)
		minz, maxz = math.min(minz, z), math.max(maxz, z)

		q_tail = maybe_enqueue(qx, qy, qz, q_tail, visited, x + 1, y, z)
		q_tail = maybe_enqueue(qx, qy, qz, q_tail, visited, x - 1, y, z)
		q_tail = maybe_enqueue(qx, qy, qz, q_tail, visited, x, y, z + 1)
		q_tail = maybe_enqueue(qx, qy, qz, q_tail, visited, x, y, z - 1)

		::continue::
	end

	if next(visited) == nil then
		return nil
	end

	return new_region(vec_new(minx, miny, minz), vec_new(maxx, maxy, maxz))
end

local function expand_liquid_bounds(state, region, notify_pos, vein_miner_state)
	local vm = state.vm

	local skip_x, skip_y, skip_z = {false}, {false}, {false}

	local function loop_expand()
		state:reload_region(region)

		if not skip_x[1] and expand_axis_from_center(state, region, "x", 96, skip_x) then
			return true
		end
		if not skip_z[1] and expand_axis_from_center(state, region, "z", 96, skip_z) then
			return true
		end
		if not skip_y[1] and expand_vertical_axis(state, region, skip_y, notify_pos, vein_miner_state) then
			return true
		end
		return false
	end

	while loop_expand() do
	end
end

local function clear_liquids(state, region)
	local clear_region = new_region(vector.add(region.min, 2), vector.subtract(region.max, 2))

	for pos in iter_region_positions(clear_region) do
		local idx = state.area:indexp(pos)
		if state.cids_replace[state.data[idx]] then
			state.data[idx] = state.cid_air
		end
	end
end

local function build_walls(state, region)
	local wall_region = new_region(vector.add(region.min, 1), vector.subtract(region.max, 1))

	for pos in iter_region_positions(wall_region) do
		local idx = state.area:indexp(pos)
		if state.data[idx] ~= state.cid_air then
			goto continue_wall
		end

		for _, offset in ipairs(cardinal_dirs) do
			local neighbor_pos = pos + offset
			local nidx = state.area:indexp(neighbor_pos)
			if state.cids_source[state.data[nidx]] then
				state.data[nidx] = state.cid_wall
			end
		end

		::continue_wall::
	end
end

-- === Main function ===
function vein_miner.fill_liquid_at_pos(vein_miner_state, pos, notify_pos)
	if not liquid_set[core.get_node(pos).name] then
		return
	end

	local cached_state = get_cached_wall_state(pos)
	if cached_state then
		return
	end

	local LIMIT = 64 * 6
	local region = flood_fill_liquid(pos, LIMIT)
	if not region then
		return
	end

	local state = State:new(VoxelManip(), cid_wool_green)
	state:reload_region(region)

	-- Expand bounds
	expand_liquid_bounds(state, region, notify_pos, vein_miner_state)

	region = region:grow(2)
	state:reload_region(region)

	clear_liquids(state, region)
	build_walls(state, region)

	region = region:grow(1)
	state:reload_region(region)

	remove_unnecessary_walls(state, region)

	cache_wall_region(region, state)
	remove_overlapping_wall_regions(wall_region_cache)

	state.vm:set_data(state.data)
	state.vm:write_to_map()
	state.vm:update_liquids()
	state.vm:update_map()
end
