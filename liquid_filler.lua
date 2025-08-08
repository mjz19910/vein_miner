local liquid_set = {["default:water_source"] = true, ["default:water_flowing"] = true, ["default:lava_source"] = true,
	["default:lava_flowing"] = true}

-- === Module-scope constants ===
local cid = core.get_content_id
local cid_air = cid("air")
local cid_wall = cid("wool:green")

local cids_replace = {[cid("default:water_source")] = true, [cid("default:water_flowing")] = true, [cid("default:lava_source")] = true,
	[cid("default:lava_flowing")] = true}

local cids_source = {[cid("default:water_source")] = true, [cid("default:lava_source")] = true}

-- === Module-scope helpers ===
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

	local minp = vector.new(minx, miny, minz)
	local maxp = vector.new(maxx, maxy, maxz)

	-- Expand bounds
	local skip_x, skip_y, skip_z = {false}, {false}, {false}
	local vm, emin, emax, area, data

	local function loop_expand()
		vm = VoxelManip()
		emin, emax = vm:read_from_map(minp, maxp)
		area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
		data = vm:get_data()

		if not skip_x[1] and expand_axis(minp, maxp, "x", 96, skip_x, area, data) then
			return true
		end
		if not skip_z[1] and expand_axis(minp, maxp, "z", 96, skip_z, area, data) then
			return true
		end

		if not skip_y[1] then
			local size_x, size_z, size_y = maxp.x - minp.x, maxp.z - minp.z, maxp.y - minp.y
			local function notify_limit(pos)
				notify_pos(state, pos)
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

	-- Replace and wall liquids
	minp = vector.subtract(minp, 2)
	maxp = vector.add(maxp, 2)

	emin, emax = vm:read_from_map(minp, maxp)
	area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
	data = vm:get_data()

	-- Clear liquids
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

	-- Build walls
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
end
