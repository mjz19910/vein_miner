local vec_dirs

-- Chatgpt wrote this
local light_scan = {}

-- Assumes these globals are available or passed in:
-- core, vector, light_node, known_lights, add_pos_to_queue, etc.

local function region_key(minp, maxp) return
	("%d,%d,%d:%d,%d,%d"):format(minp.x, minp.y, minp.z, maxp.x, maxp.y, maxp.z) end

local function regions_overlap(a, b)
	return not (a.maxp.x < b.minp.x or a.minp.x > b.maxp.x or a.maxp.y < b.minp.y or a.minp.y > b.maxp.y or a.maxp.z <
		       b.minp.z or a.minp.z > b.maxp.z)
end

local function region_fully_covered(new_region, existing)
	return (new_region.minp.x >= existing.minp.x and new_region.maxp.x <= existing.maxp.x and new_region.minp.y >=
		       existing.minp.y and new_region.maxp.y <= existing.maxp.y and new_region.minp.z >= existing.minp.z and
		       new_region.maxp.z <= existing.maxp.z)
end
-- Split region a by subtracting b (returns array of regions)
local function subtract_region(a, b)
	if not regions_overlap(a, b) then
		return {
			a,
		}
	end

	local results = {}

	local xmin, xmax = a.minp.x, a.maxp.x
	local ymin, ymax = a.minp.y, a.maxp.y
	local zmin, zmax = a.minp.z, a.maxp.z

	local bx1, bx2 = b.minp.x, b.maxp.x
	local by1, by2 = b.minp.y, b.maxp.y
	local bz1, bz2 = b.minp.z, b.maxp.z

	-- 6 possible slabs around b
	if xmin < bx1 then
		table.insert(results, {
			minp = vector.new(xmin, ymin, zmin),
			maxp = vector.new(bx1 - 1, ymax, zmax),
		})
		xmin = bx1
	end
	if xmax > bx2 then
		table.insert(results, {
			minp = vector.new(bx1 + 1, ymin, zmin),
			maxp = vector.new(xmax, ymax, zmax),
		})
		xmax = bx2
	end
	if ymin < by1 then
		table.insert(results, {
			minp = vector.new(xmin, ymin, zmin),
			maxp = vector.new(xmax, by1 - 1, zmax),
		})
		ymin = by1
	end
	if ymax > by2 then
		table.insert(results, {
			minp = vector.new(xmin, by2 + 1, zmin),
			maxp = vector.new(xmax, ymax, zmax),
		})
		ymax = by2
	end
	if zmin < bz1 then
		table.insert(results, {
			minp = vector.new(xmin, ymin, zmin),
			maxp = vector.new(xmax, ymax, bz1 - 1),
		})
	end
	if zmax > bz2 then
		table.insert(results, {
			minp = vector.new(xmin, ymin, bz2 + 1),
			maxp = vector.new(xmax, ymax, zmax),
		})
	end

	return results
end

light_scan.scanned_regions = {}

function light_scan.scan_nearby_lights(state, start_pos, node_name)
	local visited = {}
	local q = {
		start_pos,
	}
	local qhead = 1
	local minp = vector.copy(start_pos)
	local maxp = vector.copy(start_pos)

	local function maybe_enqueue(pos)
		local h = core.hash_node_position(pos)
		if not visited[h] then
			visited[h] = true
			q[#q + 1] = pos
		end
	end

	while qhead <= #q do
		local pos = q[qhead]
		qhead = qhead + 1

		local node = core.get_node(pos)
		if node.name ~= node_name then goto continue end

		minp.x = math.min(minp.x, pos.x)
		minp.y = math.min(minp.y, pos.y)
		minp.z = math.min(minp.z, pos.z)
		maxp.x = math.max(maxp.x, pos.x)
		maxp.y = math.max(maxp.y, pos.y)
		maxp.z = math.max(maxp.z, pos.z)

		for _, dir in ipairs(vec_dirs) do
			local neighbor = vector.add(pos, dir)
			maybe_enqueue(neighbor)
		end

		::continue::
	end

	local region = {
		minp = minp,
		maxp = maxp,
	}
	local uncovered = {
		region,
	}

	-- Subtract existing regions
	for _, scanned in ipairs(light_scan.scanned_regions) do
		local next_uncovered = {}
		for _, r in ipairs(uncovered) do
			local remaining = subtract_region(r, scanned)
			for _, rem in ipairs(remaining) do table.insert(next_uncovered, rem) end
		end
		uncovered = next_uncovered
		if #uncovered == 0 then return end
	end

	for _, r in ipairs(uncovered) do
		table.insert(light_scan.scanned_regions, r)

		local center = vector.divide(vector.add(r.minp, r.maxp), 2)
		vein_miner.add_pos_to_queue(state, node_name, center)
	end
end

function light_scan.init(CFG) vec_dirs = CFG.vec_dirs end

return light_scan
