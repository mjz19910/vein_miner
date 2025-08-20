local assert = assert
---@type VectorModule
local vector = vector
local setmetatable = setmetatable
local ipairs = ipairs
local table = table
local math = math
---@type CoreModApi
local core = core
local utils = vein_miner.utils
---@class AABB
local aabb = {}

local vec_add = vector.add
local vec_sub = vector.subtract
local insert = table.insert
local remove = table.remove
local min = math.min
local max = math.max
local p = vector.new
local add_particle = core.add_particle

---@class Region
---@field __index Region
---@field min Vector
---@field max Vector

---@type Region
local Region = {}
Region.__index = Region

---@param min Vector
---@param max Vector
---@return Region
local function new_region(min, max)
	return setmetatable({
		min = min,
		max = max,
	}, Region)
end
aabb.new_region = new_region

function Region:clone() return new_region(p(self.min), p(self.max)) end

---@param self Region
---@param min Vector
---@param max Vector
function Region:assign_parts(min, max)
	self.min = min
	self.max = max
end

---@param self Region
---@param margin number
function Region:shrink_clone(margin) return self:clone():shrink(margin) end

---@param self Region
---@param margin number
function Region:grow_clone(margin) return self:clone():grow(margin) end

---@param self Region
---@param margin number
function Region:shrink(margin)
	self.min = vec_add(self.min, margin)
	self.max = vec_sub(self.max, margin)
end

---@param self Region
---@param margin number
function Region:grow(margin)
	self.min = vec_sub(self.min, margin)
	self.max = vec_add(self.max, margin)
end

---@param a Region
---@param b Region
---@return boolean
function Region:overlaps(other)
	local x_overlap = self.max.x >= other.min.x and self.min.x <= other.max.x
	local y_overlap = self.max.y >= other.min.y and self.min.y <= other.max.y
	local z_overlap = self.max.z >= other.min.z and self.min.z <= other.max.z
	return x_overlap and y_overlap and z_overlap
end

---@param a Region
---@param b Region
---@return boolean
function Region:is_inside(b)
	local min, max = self.min, self.max
	local inside_x = min.x >= b.min.x and max.x <= b.max.x
	local inside_y = min.y >= b.min.y and max.y <= b.max.y
	local inside_z = min.z >= b.min.z and max.z <= b.max.z
	return inside_x and inside_y and inside_z
end

---@param a Region
---@param b Region
---@return Region[]
local function subtract_box(a, b)
	if not a:overlaps(b) then
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

---@param container Region
---@param filled_list Region[]
---@return Region[]
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

---@param self Region
---@return number
function Region:volume() return (self.max.x - self.min.x + 1) * (self.max.y - self.min.y + 1) * (self.max.z - self.min.z + 1) end

-- If they overlap or touch (1-node gap), merge them
---@param min1 number
---@param max1 number
---@param min2 number
---@param max2 number
---@return boolean
local function axis_touch_or_overlap(min1, max1, min2, max2) return not (max1 < min2 - 1 or min1 > max2 + 1) end

---@param a Region
---@param b Region
---@return boolean
local function mergeable(a, b)
	local x_overlap = axis_touch_or_overlap(a.min.x, a.max.x, b.min.x, b.max.x)
	local y_overlap = axis_touch_or_overlap(a.min.y, a.max.y, b.min.y, b.max.y)
	local z_overlap = axis_touch_or_overlap(a.min.z, a.max.z, b.min.z, b.max.z)
	return x_overlap and y_overlap and z_overlap
end

---@param a Vector
---@param b Vector
---@return Vector
function vector.min(a, b) return vector.combine(a, b, min) end

---@param a Vector
---@param b Vector
---@return Vector
function vector.max(a, b) return vector.combine(a, b, max) end

---@param a Region
---@param b Region
---@return Region, Region[]
local function merge_regions(a, b)
	local merged = new_region(vector.min(a.min, b.min), vector.max(a.max, b.max))

	-- Compute filled volume from both regions
	local filled = {a, b}

	-- Optionally subtract a and b from merged box to find unknown volume
	local unknown_regions = subtract_region(merged, filled)

	return merged, unknown_regions
end

---@param region_list Region[]
---@return Region[] unknown_regions
function aabb.compact_regions(region_list)
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

---@param r Region
---@param scanned Region[]
---@param on_region fun(region: Region)
local function subtract_scan(r, scanned, on_region)
	local uncovered = subtract_region(r, scanned)
	for _, r in ipairs(uncovered) do
		on_region(r)
	end
end

---@class SubtractAndAccumulateOptions
---@field volume_threshold number|nil
---@field max_distance number|nil
---@field on_flush fun(region: Region)

---@param r Region
---@param scanned Region[]
---@param opts SubtractAndAccumulateOptions
function aabb.subtract_and_accumulate(r, scanned, opts)
	local max_volume = opts.volume_threshold or 50000
	local max_dist = opts.max_distance or 16
	local on_flush = assert(opts.on_flush, "`on_flush` callback required")

	local uncovered = subtract_region(r, scanned)

	local ac = nil
	local ac_volume = 0

	for _, r in ipairs(uncovered) do
		local vol = r:volume()
		if vol >= max_volume then
			on_flush(r)
		else
			if not ac then
				ac = r:clone()
				ac_volume = vol
			else
				-- Check closeness
				local dx = math.max(0, math.max(ac.min.x - r.max.x, r.min.x - ac.max.x))
				local dy = math.max(0, math.max(ac.min.y - r.max.y, r.min.y - ac.max.y))
				local dz = math.max(0, math.max(ac.min.z - r.max.z, r.min.z - ac.max.z))
				local dist = dx + dy + dz

				if dist > max_dist then
					if ac:volume() >= max_volume then
						on_flush(ac)
					end
					ac = r:clone()
					ac_volume = vol
				else
					ac.min = vector.new(math.min(ac.min.x, r.min.x), math.min(ac.min.y, r.min.y), math.min(ac.min.z, r.min.z))
					ac.max = vector.new(math.max(ac.max.x, r.max.x), math.max(ac.max.y, r.max.y), math.max(ac.max.z, r.max.z))
					ac_volume = ac:volume()
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

---@param a Region
---@param b Region
---@return number
local function get_gap_distance(a, b)
	local dx = math.max(0, math.max(b.min.x - a.max.x, a.min.x - b.max.x))
	local dy = math.max(0, math.max(b.min.y - a.max.y, a.min.y - b.max.y))
	local dz = math.max(0, math.max(b.min.z - a.max.z, a.min.z - b.max.z))
	return math.max(dx, dy, dz)
end

-- Returns AABB between two regions within the max distance
---@param a Region
---@param b Region
---@param max_distance number
---@return Region | nil
function aabb.between(a, b, max_distance)
	if a:overlaps(b) then
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

---@param target Region
---@param region_list Region[]
---@return boolean
function aabb.is_covered_by_any(target, region_list)
	for _, r in ipairs(region_list) do
		if target:is_inside(r) then
			return true
		end
	end
	return false
end

---@param self Region
---@param pos Vector
---@return boolean
function Region:is_point_in_region(pos) return vector.in_area(pos, self.min, self.max) end

---@param r Region
---@return Vector
function Region:size() return self.max - self.min end

---@param self Region
---@return string
function Region:__tostring()
	local size = self.max - self.min
	return ("%s to %s (%s) Volume=%d"):format(self.min, self.max, self:size(), self:volume())
end

function Region:is_inside_any(region_list)
	for _, other in ipairs(region_list) do
		if self:is_inside(other) then
			return true
		end
	end
	return false
end

local function place_particle(pos, size, texture)
	add_particle({
		pos = pos,
		expirationtime = 4,
		size = size or 4,
		texture = texture or "default_mese_block.png",
		glow = 15,
	})
end

local function stone_part(pos) place_particle(pos, 6 / 3, "default_stone.png") end

local function mese_blk_part(pos) place_particle(pos, 6 / 3, "default_mese_block.png") end

local function diamond_blk_part(pos) place_particle(pos, 6 / 3, "default_diamond_block.png") end

local function stone_blk_part(pos) place_particle(pos, 6 / 3, "default_stone_block.png") end

function Region:draw()
	local min = self.min
	local max = self.max
	local step = 8

	-- Center point
	local center = vector.divide(vector.add(min, max), 2)
	mese_blk_part(center)

	local x_vals = utils.linspace_centered(min.x, max.x, center.x, step)
	local y_vals = utils.linspace_centered(min.y, max.y, center.y, step)
	local z_vals = utils.linspace_centered(min.z, max.z, center.z, step)

	-- Find center indices (should be exact match)
	local cx = utils.find_closest_index(x_vals, center.x)
	local cy = utils.find_closest_index(y_vals, center.y)
	local cz = utils.find_closest_index(z_vals, center.z)

	-- Draw shell
	for _, x in ipairs(x_vals) do
		for _, y in ipairs(y_vals) do
			for _, z in ipairs(z_vals) do
				local on_x_edge = (x == min.x or x == max.x)
				local on_y_edge = (y == min.y or y == max.y)
				local on_z_edge = (z == min.z or z == max.z)

				if on_x_edge or on_y_edge or on_z_edge then
					local pos = vector.new(x, y, z)

					if not on_y_edge then
						mese_blk_part(pos)
					elseif y == max.y then
						stone_part(pos)
					elseif y ~= min.y and (on_x_edge or on_z_edge) then
						stone_blk_part(pos)
					elseif y == min.y then
						diamond_blk_part(pos)
					end
				end
			end
		end
	end

	-- Draw axis lines through center
	for i = 2, #x_vals - 1 do
		if i ~= cx then
			mese_blk_part(vector.new(x_vals[i], y_vals[cy], z_vals[cz]))
		end
	end
	for i = 2, #y_vals - 1 do
		if i ~= cy then
			mese_blk_part(vector.new(x_vals[cx], y_vals[i], z_vals[cz]))
		end
	end
	for i = 2, #z_vals - 1 do
		if i ~= cz then
			mese_blk_part(vector.new(x_vals[cx], y_vals[cy], z_vals[i]))
		end
	end
end

return aabb
