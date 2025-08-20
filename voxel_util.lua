---@class VoxelUtil
--- Utility functions for voxel manipulation in Luanti mods
local voxel_util = {}

-- voxel_util.lua
---@type CoreModApi
local core = core
local vector = vector
local table = table
local ipairs = ipairs
---@type VoxelArea
local VoxelArea = VoxelArea
local p = vector.new
local hash_node_position = core.hash_node_position
local get_position_from_hash = core.get_position_from_hash
local get_name_from_content_id = core.get_name_from_content_id

---Convert position to VoxelArea index
---@param area VoxelArea
---@param pos Vector
---@return integer
function voxel_util.pos_to_index(area, pos) return area:indexp(pos) end

---Convert index to position
---@param area VoxelArea
---@param index integer
---@return Vector
function voxel_util.index_to_pos(area, index) return area:position(index) end

---Check if a position is inside the VoxelArea
---@param area VoxelArea
---@param pos Vector
---@return boolean
function voxel_util.is_inside_area(area, pos)
	local minp = area.MinEdge
	local maxp = area.MaxEdge
	return pos.x >= minp.x and pos.x <= maxp.x and pos.y >= minp.y and pos.y <= maxp.y and pos.z >= minp.z and pos.z <= maxp.z
end

---Iterate over all positions inside the VoxelArea
---@param area VoxelArea
---@param func fun(pos: Vector)
function voxel_util.iterate_area(area, func)
	local minp = area.MinEdge
	local maxp = area.MaxEdge
	for z = minp.z, maxp.z do for y = minp.y, maxp.y do for x = minp.x, maxp.x do func(p(x, y, z)) end end end
end

---Get node name at a position
---@param vm VoxelManip
---@param data ContentId[]
---@param area VoxelArea
---@param pos Vector
---@return string
function voxel_util.get_node_at_pos(vm, data, area, pos)
	local index = area:index(pos.x, pos.y, pos.z)
	local c = data[index]
	return core.get_name_from_content_id(c)
end

---Set node content id at a position
---@param data ContentId[]
---@param area VoxelArea
---@param pos Vector
---@param content_id ContentId
function voxel_util.set_node_at_pos(data, area, pos, content_id)
	local index = area:index(pos.x, pos.y, pos.z)
	data[index] = content_id
end

---Safely set a node if inside area
---@param data ContentId[]
---@param area VoxelArea
---@param pos Vector
---@param content_id ContentId
---@return boolean success
function voxel_util.safe_set_node(data, area, pos, content_id)
	if voxel_util.is_inside_area(area, pos) then
		voxel_util.set_node_at_pos(data, area, pos, content_id)
		return true
	end
	return false
end

---Get neighboring positions (6-directional)
---@param pos Vector
---@return Vector[]
function voxel_util.get_neighbors(pos)
	return {p(pos.x + 1, pos.y, pos.z), p(pos.x - 1, pos.y, pos.z), p(pos.x, pos.y + 1, pos.z), p(pos.x, pos.y - 1, pos.z),
		p(pos.x, pos.y, pos.z + 1), p(pos.x, pos.y, pos.z - 1)}
end

---Fast integer hash for a node position using the engine's built-in method
---@param pos Vector
---@return NodeHash
function voxel_util.pos_hash(pos) return hash_node_position(pos) end

---Inverse of pos_hash
---@param hash NodeHash
---@return Vector
function voxel_util.pos_unhash(hash) return get_position_from_hash(hash) end

---Flood fill a voxel region starting at pos
---@param vm VoxelManip
---@param data ContentId[]
---@param area VoxelArea
---@param start_pos Vector
---@param predicate fun(node_name: string): boolean
---@param fill_content_id ContentId
function voxel_util.flood_fill(vm, data, area, start_pos, predicate, fill_content_id)
	local to_visit = {start_pos}
	local visited = {}

	while #to_visit > 0 do
		local pos = table.remove(to_visit)
		local key = hash_node_position(pos)
		if not visited[key] and voxel_util.is_inside_area(area, pos) then
			visited[key] = true
			local node_name = voxel_util.get_node_at_pos(vm, data, area, pos)
			if predicate(node_name) then
				voxel_util.set_node_at_pos(data, area, pos, fill_content_id)
				for _, npos in ipairs(voxel_util.get_neighbors(pos)) do
					if not visited[hash_node_position(npos)] then table.insert(to_visit, npos) end
				end
			end
		end
	end
end

---Iterator over voxel indices and positions in a VoxelArea between minp and maxp (inclusive)
---Uses the VoxelArea:iterp() method to efficiently iterate over indices in the specified range.
---
---Each call returns the next index and its corresponding Vector position.
---
---@param vm VoxelManip The voxel manipulator to iterate over.
---@param minp Vector The minimum corner position of the iteration volume.
---@param maxp Vector The maximum corner position of the iteration volume.
---@param full_minp Vector The minimum corner of the full VoxelManip area.
---@param full_maxp Vector The maximum corner of the full VoxelManip area.
---@return fun(): Vector, ContentId, integer
function voxel_util.iterate_voxelarea(vm, full_minp, full_maxp, user_minp, user_maxp)
	local area = VoxelArea:new{
		MinEdge = full_minp, -- Assuming you can get these from vm
		MaxEdge = full_maxp,
	}

	-- Clamp minp/maxp inside vm area (optional safety)
	local minx = math.max(user_minp.x, area.MinEdge.x)
	local miny = math.max(user_minp.y, area.MinEdge.y)
	local minz = math.max(user_minp.z, area.MinEdge.z)
	local maxx = math.min(user_maxp.x, area.MaxEdge.x)
	local maxy = math.min(user_maxp.y, area.MaxEdge.y)
	local maxz = math.min(user_maxp.z, area.MaxEdge.z)

	local data = vm:get_data()

	-- Start index in the vm area for min corner
	local i = area:index(minx, miny, minz) - 1

	local xrange = maxx - minx + 1
	local yrange = maxy - miny + 1
	local zrange = maxz - minz + 1

	local y = 0
	local z = 0

	local yreqstride = area.ystride - xrange
	local multistride = area.zstride - ((yrange - 1) * area.ystride + xrange)

	local nextaction = i + 1 + xrange

	return function()
		i = i + 1
		if i == nextaction then
			y = y + 1
			if y == yrange then
				z = z + 1
				if z == zrange then return end
				i = i + multistride
				y = 0
				nextaction = i + xrange
			else
				i = i + yreqstride
				nextaction = i + xrange
			end
		end

		-- Calculate 3D position from linear index
		local pos = area:position(i)
		local val = data[i]

		return pos, val, i
	end
end

---Convert a list of nodenames into a lookup table of content ids for quick checks
---@param nodenames string[]
---@return table<ContentId, boolean> content_id_lookup
function voxel_util.content_ids_lookup(nodenames)
	local lookup = {}
	for _, name in ipairs(nodenames) do
		local cid = core.get_content_id(name)
		if cid then lookup[cid] = true end
	end
	return lookup
end

---Create a lookup table from content IDs to nodenames (reverse of content_ids_lookup)
---@param cids ContentId[]
---@return table<ContentId, string> cid_to_name_lookup
function voxel_util.content_names_lookup(cids)
	local lookup = {}
	for _, cid in ipairs(cids) do
		local name = core.get_name_from_content_id(cid)
		if name then lookup[cid] = name end
	end
	return lookup
end

---Find logs that keep leaves alive within a 9x9 horizontal area and leaf decay vertical radius around player
---@param pos Vector
---@return Vector[] logs_positions
function voxel_util.find_logs_keeping_leaves(pos)
	local LOG_KEEP_RADIUS = 2 -- leaf decay radius

	local minp = vector.new(pos.x - 5, pos.y - LOG_KEEP_RADIUS - 2, pos.z - 5)
	local maxp = vector.new(pos.x + 5, pos.y + LOG_KEEP_RADIUS + 2, pos.z + 5)

	local vm = core.get_voxel_manip(minp, maxp)
	local map_minp, map_maxp = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new{
		MinEdge = map_minp,
		MaxEdge = map_maxp,
	}
	local data = vm:get_data()

	local log_nodes = {"default:tree", "default:jungletree", "default:pine_tree", "default:acacia_tree", "default:aspen_tree"}
	local log_cids = voxel_util.content_ids_lookup(log_nodes)

	local leaf_nodes = {"default:leaves", "default:jungleleaves", "default:pine_needles", "default:acacia_leaves", "default:aspen_leaves"}
	local leaf_cids = voxel_util.content_ids_lookup(leaf_nodes)

	local found_logs = {}

	local next = voxel_util.iterate_voxelarea(vm, map_minp, map_maxp, minp, maxp)
	while true do
		local pos, cid, idx = next()
		if not pos then break end
	end
	for pos, cid, idx in voxel_util.iterate_voxelarea(vm, map_minp, map_maxp, minp, maxp) do
		if log_cids[cid] then
			local keeps_leaf = false
			for x = -LOG_KEEP_RADIUS, LOG_KEEP_RADIUS do
				for y = -LOG_KEEP_RADIUS, LOG_KEEP_RADIUS do
					for z = -LOG_KEEP_RADIUS, LOG_KEEP_RADIUS do
						local leaf_pos = vector.new(pos.x + x, pos.y + y, pos.z + z)
						local leaf_idx = area:index(leaf_pos.x, leaf_pos.y, leaf_pos.z)
						if leaf_cids[data[leaf_idx]] then
							keeps_leaf = true
							break
						end
					end
					if keeps_leaf then break end
				end
				if keeps_leaf then break end
			end
			if keeps_leaf then table.insert(found_logs, pos) end
		end
	end

	return found_logs
end

--- Generate integer offsets in a 3D sphere, sorted optionally later
---@param radius integer
---@return Vector[] Array of {x, y, z}
function voxel_util.gen_euclidean_offsets_3d(radius)
	local offsets = {}
	local radius_sq = radius * radius

	for x = -radius, radius do
		for y = -radius, radius do
			for z = -radius, radius do
				local dist2 = x * x + y * y + z * z
				if dist2 <= radius_sq then table.insert(offsets, vector.new(x, y, z)) end
			end
		end
	end

	return offsets
end

return voxel_util

