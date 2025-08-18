---@type VeinMinerGlobal
local vein_miner = vein_miner
local voxel_util = vein_miner.voxel_util
local math = math
local table = table
local print = print
-- Localize frequently used functions
local sqrt = math.sqrt
local floor = math.floor
local sort = table.sort
local unpack = unpack
--- Returns an iterator that yields all distinct 3D distances in ascending order
---@param offsets Vector[] Array of {x,y,z}
---@return fun(): number|nil
local function gen_distances(offsets)
	-- copy and sort offsets by full Euclidean distance
	local sorted = {unpack(offsets)}
	sort(sorted, function(a, b)
		local da = a.x * a.x + a.y * a.y + a.z * a.z
		local db = b.x * b.x + b.y * b.y + b.z * b.z
		return da < db
	end)

	local seen = {}
	local i = 0
	local n = #sorted

	return function()
		while true do
			i = i + 1
			if i > n then
				return nil
			end
			local off = sorted[i]
			local d = sqrt(off.x * off.x + off.y * off.y + off.z * off.z)
			if not seen[d] then
				seen[d] = true
				return d, off
			end
		end
	end
end

local function example_gen_distances()
	-- Example usage with the generator
	local offsets3d = voxel_util.gen_euclidean_offsets_3d(5)
	local dist_gen = gen_distances(offsets3d)
	local count = 0
	local dist_limit = 3.32
	for dist, pos in dist_gen do
		if dist > dist_limit then
			print(("Next distance > %.2f:"):format(dist_limit), floor(dist * 1000) / 1000, dist, pos)
			count = count + 1
			if count > 1 and dist % 1 == 0 then
				break
			end
		end
	end
end
example_gen_distances()
