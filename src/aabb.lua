local vector = vector
local setmetatable = setmetatable
local ipairs = ipairs
local table = table
local math = math

local add = vector.add
local sub = vector.subtract
local insert = table.insert
local remove = table.remove
local min = math.min
local max = math.max

local region_mt = {}
region_mt.__index = region_mt

local function new_region(min, max)
	return setmetatable({
		min = min,
		max = max,
	}, region_mt)
end
function region_mt:assign_parts(min, max)
	self.min = min
	self.max = max
end

function region_mt:shrink_parts(margin) return add(self.min, margin), add(self.max, -margin) end
function region_mt:grow_parts(margin) return add(self.min, -margin), add(self.max, margin) end

function region_mt:shrink_clone(margin)
	local min, max = self:shrink_parts(margin)
	return new_region(min, max)
end
function region_mt:grow_clone(margin)
	local min, max = self:grow_parts(margin)
	return new_region(min, max)
end
function region_mt:shrink(margin)
	local min, max = self:shrink_parts(margin)
	region_mt:assign_parts(min, max)
end
function region_mt:grow(margin)
	local min, max = self:grow_parts(margin)
	region_mt:assign_parts(min, max)
end

local function regions_overlap(a, b)
	local x_overlap = a.max.x >= b.min.x and a.min.x <= b.max.x
	local y_overlap = a.max.y >= b.min.y and a.min.y <= b.max.y
	local z_overlap = a.max.z >= b.min.z and a.min.z <= b.max.z
	return x_overlap and y_overlap and z_overlap
end

local function region_fully_covered(a, b)
	local x_covered = a.min.x >= b.min.x and a.max.x <= b.max.x
	local y_covered = a.min.y >= b.min.y and a.max.y <= b.max.y
	local z_covered = a.min.z >= b.min.z and a.max.z <= b.max.z
	return x_covered and y_covered and z_covered
end

local function subtract_box(a, b)
	if not regions_overlap(a, b) then
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
		insert(results, new_region(vector.new(xmin, ymin, zmin), vector.new(bx1 - 1, ymax, zmax)))
		xmin = bx1
	end
	if xmax > bx2 then
		insert(results, new_region(vector.new(bx2 + 1, ymin, zmin), vector.new(xmax, ymax, zmax)))
		xmax = bx2
	end
	if ymin < by1 then
		insert(results, new_region(vector.new(xmin, ymin, zmin), vector.new(xmax, by1 - 1, zmax)))
		ymin = by1
	end
	if ymax > by2 then
		insert(results, new_region(vector.new(xmin, by2 + 1, zmin), vector.new(xmax, ymax, zmax)))
		ymax = by2
	end
	if zmin < bz1 then
		insert(results, new_region(vector.new(xmin, ymin, zmin), vector.new(xmax, ymax, bz1 - 1)))
	end
	if zmax > bz2 then
		insert(results, new_region(vector.new(xmin, ymin, bz2 + 1), vector.new(xmax, ymax, zmax)))
	end

	return results
end

local function subtract_region(container, filled_list)
	local remaining = {container}

	for _, filler in ipairs(filled_list) do
		local new_remaining = {}
		for _, r in ipairs(remaining) do
			local parts = subtract_box(r, filler)
			for _, part in ipairs(parts) do
				insert(new_remaining, part)
			end
		end
		remaining = new_remaining
	end

	return remaining
end

local function volume(r) return (r.max.x - r.min.x + 1) * (r.max.y - r.min.y + 1) * (r.max.z - r.min.z + 1) end

-- If they overlap or touch (1-node gap), merge them
local function axis_touch_or_overlap(min1, max1, min2, max2) return not (max1 < min2 - 1 or min1 > max2 + 1) end

local function mergeable(a, b)
	local x_overlap = axis_touch_or_overlap(a.min.x, a.max.x, b.min.x, b.max.x)
	local y_overlap = axis_touch_or_overlap(a.min.y, a.max.y, b.min.y, b.max.y)
	local z_overlap = axis_touch_or_overlap(a.min.z, a.max.z, b.min.z, b.max.z)
	return x_overlap and y_overlap and z_overlap
end

function vector.min(a, b) return vector.combine(a, b, min) end

function vector.max(a, b) return vector.combine(a, b, max) end

local function merge_regions(a, b)
	local merged = new_region(vector.min(a.min, b.min), vector.max(a.max, b.max))

	-- Compute filled volume from both regions
	local filled = {a, b}

	-- Optionally subtract a and b from merged box to find unknown volume
	local unknown_regions = subtract_region(merged, filled)

	return merged, unknown_regions
end

local function compact_regions(region_list)
	local changed = true
	local unknown_regions = {}

	while changed do
		changed = false
		for i = 1, #region_list do
			for j = i + 1, #region_list do
				local a = region_list[i]
				local b = region_list[j]
				if a and b and mergeable(a, b) then
					local merged, gaps = merge_regions(a, b)
					region_list[i] = merged
					remove(region_list, j)
					-- Store the unknown "gap" regions created by the merge
					for _, gap in ipairs(gaps or {}) do
						insert(unknown_regions, gap)
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

local function subtract_scan(r, scanned, on_region)
	local uncovered = subtract_region(r, scanned)
	for _, r in ipairs(uncovered) do
		on_region(r)
	end
end

local function subtract_and_accumulate(r, scanned, opts)
	local max_volume = opts.volume_threshold or 50000
	local max_dist = opts.max_distance or 16
	local on_flush = assert(opts.on_flush, "`on_flush` callback required")

	local uncovered = subtract_region(r, scanned)

	local ac = nil
	local ac_volume = 0

	for _, r in ipairs(uncovered) do
		local vol = volume(r)
		if vol >= max_volume then
			on_flush(r)
		else
			if not ac then
				ac = new_region(r.min, r.max)
				ac_volume = vol
			else
				-- Check closeness
				local dx = math.max(0, math.max(ac.min.x - r.max.x, r.min.x - ac.max.x))
				local dy = math.max(0, math.max(ac.min.y - r.max.y, r.min.y - ac.max.y))
				local dz = math.max(0, math.max(ac.min.z - r.max.z, r.min.z - ac.max.z))
				local dist = dx + dy + dz

				if dist > max_dist then
					if volume(ac) >= max_volume then
						on_flush(ac)
					end
					ac = new_region(r.min, r.max)
					ac_volume = vol
				else
					ac.min = vector.new(math.min(ac.min.x, r.min.x), math.min(ac.min.y, r.min.y), math.min(ac.min.z, r.min.z))
					ac.max = vector.new(math.max(ac.max.x, r.max.x), math.max(ac.max.y, r.max.y), math.max(ac.max.z, r.max.z))
					ac_volume = volume(ac)
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

local function get_gap_distance(a, b)
	local dx = math.max(0, math.max(b.min.x - a.max.x, a.min.x - b.max.x))
	local dy = math.max(0, math.max(b.min.y - a.max.y, a.min.y - b.max.y))
	local dz = math.max(0, math.max(b.min.z - a.max.z, a.min.z - b.max.z))
	return math.max(dx, dy, dz)
end

-- Returns AABB between two regions within the max distance
local function between(a, b, max_distance)
	if regions_overlap(a, b) then
		return nil
	end
	if get_gap_distance(a, b) > max_distance then
		return nil
	end
	local min = vector.new(math.min(a.max.x, b.max.x) + 1, math.min(a.max.y, b.max.y) + 1, math.min(a.max.z, b.max.z) + 1)
	local max = vector.new(math.max(a.min.x, b.min.x) - 1, math.max(a.min.y, b.min.y) - 1, math.max(a.min.z, b.min.z) - 1)
	local r = new_region(min, max)
	if r.min.x > r.max.x or r.min.y > r.max.y or r.min.z > r.max.z then
		return nil -- invalid or negative gap
	end
	return r
end

local function is_covered_by_any(target, region_list)
	for _, r in ipairs(region_list) do
		if region_fully_covered(target, r) then
			return true
		end
	end
	return false
end

local function is_point_in_region(r, pos)
	return pos.x >= r.min.x and pos.x <= r.max.x and pos.y >= r.min.y and pos.y <= r.max.y and pos.z >= r.min.z and pos.z <= r.max.z
end

local function size(r) return r.max - r.min end

local pos_str = core.pos_to_string

local function size_str(r) return pos_str(size(r)) end

local function region_str(r)
	local size = r.max - r.min
	return ("%s to %s (%s) Volume=%d"):format(pos_str(r.min), pos_str(r.max), size_str(r), volume(r))
end

aabb = {
	axis_touch_or_overlap = axis_touch_or_overlap,
	between = between,
	compact_regions = compact_regions,
	get_gap_distance = get_gap_distance,
	is_covered_by_any = is_covered_by_any,
	is_point_in_region = is_point_in_region,
	merge_regions = merge_regions,
	mergeable = mergeable,
	region = new_region,
	region_fully_covered = region_fully_covered,
	region_str = region_str,
	regions_overlap = regions_overlap,
	size = size,
	size_str = size_str,
	subtract_and_accumulate = subtract_and_accumulate,
	subtract_box = subtract_box,
	subtract_region = subtract_region,
	subtract_scan = subtract_scan,
	volume = volume,
}
