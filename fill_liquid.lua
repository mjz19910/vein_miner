local ipairs = ipairs

local table = table

local insert_all = table.insert_all

local VoxelArea = VoxelArea
local VoxelManip = VoxelManip

local new_region = aabb.region

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

local function expand_axis_from_center(args, axis, limit, skip_flag)
	local r = args.r -- { min = vector, max = vector }
	local area = args.area
	local data = args.data
	local replace = args.replace -- cids_replace table

	local size = r.max[axis] - r.min[axis] + 1
	if size >= limit then
		skip_flag[1] = true
		return false
	end

	local expanded = false
	while size < limit do
		local did_expand = false

		-- Positive direction
		local new_max = r.max[axis] + 1
		local found_positive = false
		for y = r.min.y, r.max.y do
			for z = r.min.z, r.max.z do
				local pos = {x = 0, y = 0, z = 0}
				pos[axis] = new_max
				pos.y = y
				pos.z = (axis == "x") and z or r.min.z + (z - r.min.z)
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
			r.max[axis] = new_max
			did_expand = true
		end

		-- Negative direction
		local new_min = r.min[axis] - 1
		local found_negative = false
		for y = r.min.y, r.max.y do
			for z = r.min.z, r.max.z do
				local pos = {x = 0, y = 0, z = 0}
				pos[axis] = new_min
				pos.y = y
				pos.z = (axis == "x") and z or r.min.z + (z - r.min.z)
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
			r.min[axis] = new_min
			did_expand = true
		end

		if not did_expand then
			break
		end

		size = r.max[axis] - r.min[axis] + 1
		expanded = true
	end

	if not expanded then
		skip_flag[1] = true
	end
	return expanded
end

local function expand_axis(minp, maxp, axis, limit, skip_flag, area, data)
	local function axis_iter(is_max)
		local start = is_max and maxp[axis] or minp[axis]
		for a = minp[axis], maxp[axis] do
			for b = minp.y, maxp.y do
				local pos = {x = 0, y = 0, z = 0}
				pos[axis] = a
				pos.y = b
				pos.x = pos.x or minp.x
				pos.z = pos.z or minp.z
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

	if axis_iter(false) or axis_iter(true) then
		return true
	end
	return false
end

local function expand_vertical_axis(args, skip_y, notify_pos)
	local r = args.r -- { min = vector, max = vector }
	local area = args.area
	local data = args.data
	local replace = args.replace -- cids_replace table
	local state = args.state -- for notify_pos()

	local size_x, size_z, size_y = r.max.x - r.min.x, r.max.z - r.min.z, r.max.y - r.min.y

	local function notify_limit(pos) notify_pos(state, pos) end

	if skip_y[1] then
		return false
	end

	local expanded = false

	-- Try expand downward by one
	do
		local y = r.min.y - 1
		for z = r.min.z, r.max.z do
			for x = r.min.x, r.max.x do
				local idx = area:index(x, y, z)
				if replace[data[idx]] then
					r.min.y = y
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
		local y = r.max.y + 1
		for z = r.min.z, r.max.z do
			for x = r.min.x, r.max.x do
				local idx = area:index(x, y, z)
				if replace[data[idx]] then
					r.max.y = y
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
		local new_size_y = r.max.y - r.min.y
		if not ((size_x < 64 and size_z < 64 and new_size_y < 64 * 3) or new_size_y < 64) then
			skip_y[1] = true
			return false
		end
		return true
	end

	return false
end

local function remove_useless_walls(vm, area, data, minp, maxp, cid_wool_green, cid_air, cids_source)
  local walls_to_remove = {}

  -- First pass: find useless walls
  for z = minp.z + 1, maxp.z - 1 do
    for y = minp.y + 1, maxp.y - 1 do
      for x = minp.x + 1, maxp.x - 1 do
        local i = area:index(x, y, z)
        if data[i] == cid_wool_green then
          local useless = true
          for _, off in ipairs({{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}) do
            local ni = area:index(x + off[1], y + off[2], z + off[3])
            local beyond_pos = {x = x + 2*off[1], y = y + 2*off[2], z = z + 2*off[3]}
            -- Only check beyond if inside current bounds
            if area:contains(beyond_pos) then
              local beyond_idx = area:index(beyond_pos.x, beyond_pos.y, beyond_pos.z)
              if cids_source[data[ni]] and data[beyond_idx] == cid_air then
                useless = true
                break
              else
                useless = false
              end
            else
              -- We don't know beyond block because it's outside VM bounds
              -- So be conservative and assume wall might be useful
              useless = false
            end
          end
          if useless then
            table.insert(walls_to_remove, {x = x, y = y, z = z})
          end
        end
      end
    end
  end

  -- If no useless walls, nothing to do
  if #walls_to_remove == 0 then return minp, maxp end

  -- Expand bounds to include walls to remove
  local new_minp = vector.new(minp)
  local new_maxp = vector.new(maxp)

  for _, pos in ipairs(walls_to_remove) do
    if pos.x < new_minp.x then new_minp.x = pos.x end
    if pos.y < new_minp.y then new_minp.y = pos.y end
    if pos.z < new_minp.z then new_minp.z = pos.z end

    if pos.x > new_maxp.x then new_maxp.x = pos.x end
    if pos.y > new_maxp.y then new_maxp.y = pos.y end
    if pos.z > new_maxp.z then new_maxp.z = pos.z end
  end

  -- Re-read voxel manip for expanded bounds to be sure all data is loaded
  local emin, emax = vm:read_from_map(new_minp, new_maxp)
  area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
  data = vm:get_data()

  -- Remove useless walls in updated data
  for _, pos in ipairs(walls_to_remove) do
    local i = area:index(pos.x, pos.y, pos.z)
    data[i] = cid_air
  end

  -- Update vm data
  vm:set_data(data)

  -- Return updated bounds and area, data, vm for further processing
  return new_minp, new_maxp, area, data, vm
end

-- === Main function ===
function vein_miner.fill_liquid_at_pos(state, pos, notify_pos)
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

		if not liquid_set[core.get_node({x = x, y = y, z = z}).name] then
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

	local r = new_region(vector.new(minx, miny, minz), vector.new(maxx, maxy, maxz))

	-- Expand bounds
	local skip_x, skip_y, skip_z = {false}, {false}, {false}
	local vm, emin, emax, area, data
	local axis_info = {state = state, r = r, replace = cids_replace};

	local function loop_expand()
		vm = VoxelManip()
		emin, emax = vm:read_from_map(r.min, r.max)
		axis_info.area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
		axis_info.data = vm:get_data()

		if not skip_x[1] and expand_axis_from_center(axis_info, "x", 96, skip_x) then
			return true
		end
		if not skip_z[1] and expand_axis_from_center(axis_info, "z", 96, skip_z) then
			return true
		end
		if not skip_y[1] and expand_vertical_axis(axis_info, skip_y, notify_pos) then
			return true
		end
		return false
	end

	while loop_expand() do
	end

	-- Replace and wall liquids
	r.min = vector.subtract(r.min, 2)
	r.max = vector.add(r.max, 2)

	emin, emax = vm:read_from_map(r.min, r.max)
	area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	data = vm:get_data()

	-- Clear liquids
	for z = r.min.z + 2, r.max.z - 2 do
		for y = r.min.y + 2, r.max.y - 2 do
			for x = r.min.x + 2, r.max.x - 2 do
				local i = area:index(x, y, z)
				if cids_replace[data[i]] then
					data[i] = cid_air
				end
			end
		end
	end

	-- Build walls
	for z = r.min.z + 1, r.max.z - 1 do
		for y = r.min.y + 1, r.max.y - 1 do
			for x = r.min.x + 1, r.max.x - 1 do
				local i = area:index(x, y, z)
				if data[i] ~= cid_air then
					goto continue_wall
				end
				for _, off in ipairs({{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}) do
					local ni = area:index(x + off[1], y + off[2], z + off[3])
					if cids_source[data[ni]] then
						data[ni] = cid_wool_green -- wall
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
end
