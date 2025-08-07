aabb = {}

function aabb.region(min, max)
	return {
		min = min,
		max = max
	}
end

function aabb.regions_overlap(a, b)
	local x_overlap = a.max.x >= b.min.x and a.min.x <= b.max.x
	local y_overlap = a.max.y >= b.min.y and a.min.y <= b.max.y
	local z_overlap = a.max.z >= b.min.z and a.min.z <= b.max.z
	return x_overlap and y_overlap and z_overlap
end

function aabb.region_fully_covered(a, b)
	local x_covered = a.min.x >= b.min.x and a.max.x <= b.max.x
	local y_covered = a.min.y >= b.min.y and a.max.y <= b.max.y
	local z_covered = a.min.z >= b.min.z and a.max.z <= b.max.z
	return x_covered and y_covered and z_covered
end

function aabb.subtract_box(a, b)
	if not aabb.regions_overlap(a, b) then
		return {a}
	end

	local results = {}

	local xmin, xmax = a.min.x, a.max.x
	local ymin, ymax = a.min.y, a.max.y
	local zmin, zmax = a.min.z, a.max.z

	local bx1, bx2 = b.min.x, b.max.x
	local by1, by2 = b.min.y, b.max.y
	local bz1, bz2 = b.min.z, b.max.z

	-- 6 possible slabs around b
	if xmin < bx1 then
		table.insert(results, aabb.region(vector.new(xmin, ymin, zmin), vector.new(bx1 - 1, ymax, zmax)))
		xmin = bx1
	end
	if xmax > bx2 then
		table.insert(results, aabb.region(vector.new(bx2 + 1, ymin, zmin), vector.new(xmax, ymax, zmax)))
		xmax = bx2
	end
	if ymin < by1 then
		table.insert(results, aabb.region(vector.new(xmin, ymin, zmin), vector.new(xmax, by1 - 1, zmax)))
		ymin = by1
	end
	if ymax > by2 then
		table.insert(results, aabb.region(vector.new(xmin, by2 + 1, zmin), vector.new(xmax, ymax, zmax)))
		ymax = by2
	end
	if zmin < bz1 then
		table.insert(results, aabb.region(vector.new(xmin, ymin, zmin), vector.new(xmax, ymax, bz1 - 1)))
	end
	if zmax > bz2 then
		table.insert(results, aabb.region(vector.new(xmin, ymin, bz2 + 1), vector.new(xmax, ymax, zmax)))
	end

	return results
end

function aabb.subtract_region(container, filled_list)
	local remaining = {container}

	for _, filler in ipairs(filled_list) do
		local new_remaining = {}
		for _, r in ipairs(remaining) do
			local parts = aabb.subtract_box(r, filler)
			for _, part in ipairs(parts) do
				table.insert(new_remaining, part)
			end
		end
		remaining = new_remaining
	end

	return remaining
end

function aabb.volume(r) return (r.max.x - r.min.x + 1) * (r.max.y - r.min.y + 1) * (r.max.z - r.min.z + 1) end

-- If they overlap or touch (1-node gap), merge them
function aabb.axis_touch_or_overlap(min1, max1, min2, max2) return not (max1 < min2 - 1 or min1 > max2 + 1) end

function aabb.mergeable(a, b)
	local x_overlap = aabb.axis_touch_or_overlap(a.min.x, a.max.x, b.min.x, b.max.x)
	local y_overlap = aabb.axis_touch_or_overlap(a.min.y, a.max.y, b.min.y, b.max.y)
	local z_overlap = aabb.axis_touch_or_overlap(a.min.z, a.max.z, b.min.z, b.max.z)
	return x_overlap and y_overlap and z_overlap
end

function aabb.merge_regions(a, b)
	local merged = {
		min = vector.new(math.min(a.min.x, b.min.x), math.min(a.min.y, b.min.y), math.min(a.min.z, b.min.z)),
		max = vector.new(math.max(a.max.x, b.max.x), math.max(a.max.y, b.max.y), math.max(a.max.z, b.max.z))
	}

	-- Compute filled volume from both regions
	local filled = {a, b}

	-- Optionally subtract a and b from merged box to find unknown volume
	local unknown_regions = aabb.subtract_region(merged, filled)

	return merged, unknown_regions
end

function aabb.compact_regions(region_list)
	local changed = true
	local unknown_regions = {}

	while changed do
		changed = false
		for i = 1, #region_list do
			for j = i + 1, #region_list do
				local a = region_list[i]
				local b = region_list[j]
				if a and b and aabb.mergeable(a, b) then
					local merged, gaps = aabb.merge_regions(a, b)
					region_list[i] = merged
					table.remove(region_list, j)
					-- Store the unknown "gap" regions created by the merge
					for _, gap in ipairs(gaps or {}) do
						table.insert(unknown_regions, gap)
					end
					changed = true
					break
				end
			end
			if changed then
				break
			end
		end
	end

	return unknown_regions
end

function aabb.subtract_scan(r, scanned, on_region)
	local uncovered = aabb.subtract_region(r, scanned)
	for _, r in ipairs(uncovered) do
		on_region(r)
	end
end

function aabb.subtract_and_accumulate(r, scanned, opts)
	local max_volume = opts.volume_threshold or 50000
	local max_dist = opts.max_distance or 16
	local on_flush = assert(opts.on_flush, "`on_flush` callback required")

	local uncovered = aabb.subtract_region(r, scanned)

	local ac = nil
	local ac_volume = 0

	for _, r in ipairs(uncovered) do
		local vol = aabb.volume(r)
		if vol >= max_volume then
			on_flush(r)
		else
			if not ac then
				ac = aabb.region(r.min, r.max)
				ac_volume = vol
			else
				-- Check closeness
				local dx = math.max(0, math.max(ac.min.x - r.max.x, r.min.x - ac.max.x))
				local dy = math.max(0, math.max(ac.min.y - r.max.y, r.min.y - ac.max.y))
				local dz = math.max(0, math.max(ac.min.z - r.max.z, r.min.z - ac.max.z))
				local dist = dx + dy + dz

				if dist > max_dist then
					if aabb.volume(ac) >= max_volume then
						on_flush(ac)
					end
					ac = aabb.region(r.min, r.max)
					ac_volume = vol
				else
					ac.min = vector.new(math.min(ac.min.x, r.min.x), math.min(ac.min.y, r.min.y), math.min(ac.min.z, r.min.z))
					ac.max = vector.new(math.max(ac.max.x, r.max.x), math.max(ac.max.y, r.max.y), math.max(ac.max.z, r.max.z))
					ac_volume = aabb.volume(ac)
				end

				if ac_volume >= max_volume then
					on_flush(ac)
					ac = nil
					ac_volume = 0
				end
			end
		end
	end

	if ac then
		on_flush(ac)
	end
end

function aabb.get_gap_distance(a, b)
	local dx = math.max(0, math.max(b.min.x - a.max.x, a.min.x - b.max.x))
	local dy = math.max(0, math.max(b.min.y - a.max.y, a.min.y - b.max.y))
	local dz = math.max(0, math.max(b.min.z - a.max.z, a.min.z - b.max.z))
	return math.max(dx, dy, dz)
end

-- Returns AABB between two regions within the max distance
function aabb.between(a, b, max_distance)
	if aabb.regions_overlap(a, b) then
		return nil
	end
	if aabb.get_gap_distance(a, b) > max_distance then
		return nil
	end
	local min = vector.new(math.min(a.max.x, b.max.x) + 1, math.min(a.max.y, b.max.y) + 1, math.min(a.max.z, b.max.z) + 1)
	local max = vector.new(math.max(a.min.x, b.min.x) - 1, math.max(a.min.y, b.min.y) - 1, math.max(a.min.z, b.min.z) - 1)
	local r = aabb.region(min, max)
	if r.min.x > r.max.x or r.min.y > r.max.y or r.min.z > r.max.z then
		return nil -- invalid or negative gap
	end
	return r
end

function aabb.is_covered_by_any(target, region_list)
	for _, r in ipairs(region_list) do
		if aabb.region_fully_covered(target, r) then
			return true
		end
	end
	return false
end

function aabb.is_point_in_region(r, pos)
	return pos.x >= r.min.x and pos.x <= r.max.x and pos.y >= r.min.y and pos.y <= r.max.y and pos.z >= r.min.z and pos.z <= r.max.z
end

function aabb.size(r) return r.max - r.min end

local size = aabb.size
local pos_str = core.pos_to_string

function aabb.size_str(r) return pos_str(size(r)) end

local volume = aabb.volume
local size_str = aabb.size_str

function aabb.region_str(r)
	local size = r.max - r.min
	return ("%s to %s (%s) Volume=%d"):format(pos_str(r.min), pos_str(r.max), size_str(r), volume(r))
end
