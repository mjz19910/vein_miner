local ipairs = ipairs

local table = table
local vector = vector

local insert_all = table.insert_all
local vnew = vector.new

local core = core
local minetest = minetest
local VoxelArea = VoxelArea
local VoxelManip = VoxelManip

local vein_miner = vein_miner
local aabb = aabb

local new_region = aabb.region

local log_action = vein_miner.h.log_action
local pos_str = core.pos_to_string

local cardinal_dirs = {vnew(1, 0, 0), vnew(-1, 0, 0), vnew(0, 1, 0), vnew(0, -1, 0), vnew(0, 0, 1), vnew(0, 0, -1)}
local liquid_set = {["default:water_source"] = true, ["default:water_flowing"] = true, ["default:lava_source"] = true,
	["default:lava_flowing"] = true}

local cid = core.get_content_id
local cid_air, cid_wool_green

local cids_source, cids_flowing
local cids_replace = {}

core.register_on_mods_loaded(function()
	local cid_water_source = cid("default:water_source")
	local cid_water_flowing = cid("default:water_flowing")
	local cid_lava_source = cid("default:lava_source")
	local cid_lava_flowing = cid("default:lava_flowing")

	cids_source = {[cid_water_source] = true, [cid_lava_source] = true}
	cids_flowing = {[cid_water_flowing] = true, [cid_lava_flowing] = true}

	for k, v in pairs(cids_source) do
		cids_replace[k] = v
	end
	for k, v in pairs(cids_flowing) do
		cids_replace[k] = v
	end

	cid_air = cid("air")
	cid_wool_green = cid("wool:green")
end)

local function push(qx, qy, qz, q_tail, x, y, z)
	qx[q_tail], qy[q_tail], qz[q_tail] = x, y, z
	return q_tail + 1
end

local function maybe_enqueue(qx, qy, qz, q_tail, visited, x, y, z)
	local hash = core.hash_node_position({x = x, y = y, z = z})
	if not visited[hash] then
		visited[hash] = true
		return push(qx, qy, qz, q_tail, x, y, z)
	end
	return q_tail
end

local function read_voxels_from_map(vm, region)
	assert(vm and region and region.min and region.max, "Invalid arguments to read_voxels_from_map")
	local emin, emax = vm:read_from_map(region.min, region.max)
	local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	local data = vm:get_data()
	return area, data
end

local function expand_axis_from_center(state, axis, limit, skip_flag)
	local region = state.region -- { min = vector, max = vector }
	local area = state.area
	local data = state.data
	local replace = state.replace -- cids_replace table

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
				local pos = {x = 0, y = 0, z = 0}
				pos[axis] = new_max
				pos.y = y
				pos.z = (axis == "x") and z or region.min.z + (z - region.min.z)
				local idx = area:index(pos.x, pos.y, pos.z)
				if replace[data[idx]] then
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
				local pos = {x = 0, y = 0, z = 0}
				pos[axis] = new_min
				pos.y = y
				pos.z = (axis == "x") and z or region.min.z + (z - region.min.z)
				local idx = area:index(pos.x, pos.y, pos.z)
				if replace[data[idx]] then
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

local function expand_vertical_axis(state, skip_y, notify_pos, vein_miner_state)
	local region = state.region -- { min = vector, max = vector }
	local area = state.area
	local data = state.data
	local replace = state.replace -- cids_replace table

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
				if replace[data[idx]] then
					region.min.y = y
					notify_limit(vector.new(x, y, z)) -- notify the liquid node position on min face
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
				if replace[data[idx]] then
					region.max.y = y
					notify_limit(vector.new(x, y, z)) -- notify liquid node pos on max face
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

local EXPAND_AMOUNT = 5

local function expand_region_to_include(state, pos)
	local vm = state.vm
	local region = state.region

	-- Log warning about expansion
	core.log("warning", ("Expanding voxel area bounds to include position %s"):format(tostring(pos)))

	-- Expand bounds by 5 blocks where pos is outside
	if pos.x < region.min.x then
		region.min.x = pos.x - EXPAND_AMOUNT
	elseif pos.x > region.max.x then
		region.max.x = pos.x + EXPAND_AMOUNT
	end

	if pos.y < region.min.y then
		region.min.y = pos.y - EXPAND_AMOUNT
	elseif pos.y > region.max.y then
		region.max.y = pos.y + EXPAND_AMOUNT
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

	return coroutine.wrap(function()
		for z = minz, maxz do
			for y = miny, maxy do
				for x = minx, maxx do
					coroutine.yield(vnew(x, y, z))
				end
			end
		end
	end)
end

local function is_useless_wall(state, pos)
	local did_expand = false
	local idx = state.area:indexp(pos)
	if state.data[idx] ~= state.cid_wall then
		return false, did_expand
	end

	for _, off in ipairs(cardinal_dirs) do
		local neighbor_pos = pos + off
		local expanded = ensure_pos_in_area(state, neighbor_pos)
		if expanded then
			did_expand = true
		end
		local nidx = state.area:indexp(neighbor_pos)
		if state.replace[state.data[nidx]] then
			return false, did_expand
		end
	end

	return true, did_expand
end

local function try_remove_wall_at_edge(state, region, pos)
	local is_useless, did_expand = is_useless_wall(state, pos)
	if is_useless then
		local min = region.min
		local max = region.max
		if pos.x == min.x or pos.x == max.x or pos.y == min.y or pos.y == max.y or pos.z == min.z or pos.z == max.z then
			local expanded = ensure_pos_in_area(state, pos)
			if expanded then
				did_expand = true
			end
		end
		state.data[state.area:indexp(pos)] = state.cid_air
	end
	return did_expand
end

local function region_equals(region, b_min, b_max) return vector.equals(region.min, b_min) and vector.equals(region.max, b_max) end

local function remove_useless_walls(state)
	local region = state.region
	local retry_count = 0
	::retry::
	for pos in iter_region_positions(region) do
		local expanded = try_remove_wall_at_edge(state, region, pos)
		if retry_count < 16 and expanded then
			retry_count = retry_count + 1
			goto retry
		end
	end
end

-- Returns true if position is a wall node
local function is_wall(state, pos)
	local idx = state.area:indexp(pos)
	return state.data[idx] == state.cid_wool_green
end

-- Returns true if position is a liquid node (source or flowing)
local function is_liquid(state, pos)
	local idx = state.area:indexp(pos)
	return state.replace[state.data[idx]] == true
end

-- Checks if wall at pos is adjacent to liquid; if yes, it’s necessary
local function is_wall_adjacent_to_liquid(state, pos)
	for _, off in ipairs({{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}) do
		local npos = vector.add(pos, vector.new(off[1], off[2], off[3]))
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
		local hash = core.hash_node_position(pos)
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
			local npos = vector.add(pos, vector.new(off[1], off[2], off[3]))
			-- Make sure npos is inside the region, expand if needed
			ensure_pos_in_area(state, npos)
			local in_region = state.area:contains(npos)
			if in_region and not visited[core.hash_node_position(npos)] then
				stack[#stack + 1] = npos
			end
		end

		::continue::
	end
end

local wall_region_cache = {} -- list of { region = {min=vec, max=vec}, state = {...} }

local wall_region_cache = {}

local function pos_in_region(pos, region)
	return pos.x >= region.min.x and pos.x <= region.max.x and pos.y >= region.min.y and pos.y <= region.max.y and pos.z >= region.min.z and
		       pos.z <= region.max.z
end

local function get_cached_wall_state(pos)
	for _, entry in ipairs(wall_region_cache) do
		if pos_in_region(pos, entry.region) then
			return entry.state
		end
	end
	return nil
end

local function cache_wall_region(region, state) table.insert(wall_region_cache, {region = region, state = state}) end

-- Remove walls not marked as necessary by DFS
local function remove_unnecessary_walls(state)
	local region = state.region
	local visited = {}

	-- First, mark all walls adjacent to liquid as necessary
	for pos in iter_region_positions(region) do
		if is_wall(state, pos) and is_wall_adjacent_to_liquid(state, pos) then
			dfs_mark_necessary(state, pos, visited)
		end
	end

	-- Then, remove walls that are not visited (not necessary)
	for pos in iter_region_positions(region) do
		local hash = core.hash_node_position(pos)
		if is_wall(state, pos) and not visited[hash] then
			local idx = state.area:indexp(pos)
			state.data[idx] = state.cid_air
		end
	end
end

-- === Main function ===
function vein_miner.fill_liquid_at_pos(vein_miner_state, pos, notify_pos)
	if not liquid_set[core.get_node(pos).name] then
		return
	end

	local LIMIT = 64 * 6
	local visited = {}
	local qx, qy, qz = {}, {}, {}
	local q_head, q_tail = 1, 1
	local queue_count = 0

	local minx, miny, minz = pos.x, pos.y, pos.z
	local maxx, maxy, maxz = pos.x, pos.y, pos.z

	-- Seed queue
	visited[core.hash_node_position(pos)] = true
	q_tail = push(qx, qy, qz, q_tail, pos.x, pos.y, pos.z)

	-- Flood-fill
	while q_head < q_tail do
		local x, y, z = qx[q_head], qy[q_head], qz[q_head]
		q_head = q_head + 1

		if not liquid_set[core.get_node(vnew(x, y, z)).name] then
			goto continue
		end

		queue_count = queue_count + 1
		if queue_count > LIMIT then
			goto continue
		end

		-- Track bounds
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
		return
	end

	local region = new_region(vnew(minx, miny, minz), vnew(maxx, maxy, maxz))

	-- Expand bounds
	local skip_x, skip_y, skip_z = {false}, {false}, {false}
	local vm = VoxelManip()
	local area, data = read_voxels_from_map(vm, region)
	local state = {vm = VoxelManip(), area = area, data = data, region = region, replace = cids_replace}

	local function loop_expand()
		local area, data = read_voxels_from_map(vm, region)
		state.area = area
		state.data = data

		if not skip_x[1] and expand_axis_from_center(state, "x", 96, skip_x) then
			return true
		end
		if not skip_z[1] and expand_axis_from_center(state, "z", 96, skip_z) then
			return true
		end
		if not skip_y[1] and expand_vertical_axis(state, skip_y, notify_pos, vein_miner_state) then
			return true
		end
		return false
	end

	while loop_expand() do
	end

	-- Replace and wall liquids
	region.min = vector.subtract(region.min, 2)
	region.max = vector.add(region.max, 2)

	local area, data = read_voxels_from_map(vm, region)
	state.area = area
	state.data = data

	-- Clear liquids
	local clear_region = new_region(vector.add(region.min, 2), vector.subtract(region.max, 2))

	for pos in iter_region_positions(clear_region) do
		local i = state.area:indexp(pos)
		if cids_replace[state.data[i]] then
			state.data[i] = cid_air
		end
	end

	-- Build walls
	local wall_region = new_region(vector.add(region.min, 1), vector.subtract(region.max, 1))

	for pos in iter_region_positions(wall_region) do
		local i = state.area:indexp(pos)
		if state.data[i] ~= cid_air then
			goto continue_wall
		end

		for _, off in ipairs({vector.new(1, 0, 0), vector.new(-1, 0, 0), vector.new(0, 1, 0), vector.new(0, -1, 0), vector.new(0, 0, 1),
			vector.new(0, 0, -1)}) do
			local neighbor_pos = pos + off
			local ni = state.area:indexp(neighbor_pos)
			if cids_source[state.data[ni]] then
				state.data[ni] = cid_wool_green -- place wall here
			end
		end

		::continue_wall::
	end

	region.min = vector.subtract(region.min, 1)
	region.max = vector.add(region.max, 1)

	remove_unnecessary_walls(state)

	state.vm:set_data(state.data)
	state.vm:write_to_map()
	state.vm:update_liquids()
	state.vm:update_map()
end
