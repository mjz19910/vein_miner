-- voxel_utils.lua
-- Utility functions for voxel manipulation in Luanti mods
local voxel_utils = {}

local core = core or minetest
local vector_new = vector.new
local hash_node_position = core.hash_node_position
local get_position_from_hash = core.get_position_from_hash
local get_name_from_content_id = minetest.get_name_from_content_id
local table = table
local ipairs = ipairs

---Convert position to VoxelArea index
---@param area VoxelArea
---@param pos Vector
---@return integer
function voxel_utils.pos_to_index(area, pos) return area:indexp(pos) end

---Convert index to position
---@param area VoxelArea
---@param index integer
---@return Vector
function voxel_utils.index_to_pos(area, index) return area:position(index) end

---Check if a position is inside the VoxelArea
---@param area VoxelArea
---@param pos Vector
---@return boolean
function voxel_utils.is_inside_area(area, pos)
	local minp = area.MinEdge
	local maxp = area.MaxEdge
	return pos.x >= minp.x and pos.x <= maxp.x and pos.y >= minp.y and pos.y <= maxp.y and pos.z >= minp.z and pos.z <= maxp.z
end

---Iterate over all positions inside the VoxelArea
---@param area VoxelArea
---@param func fun(pos: Vector)
function voxel_utils.iterate_area(area, func)
	local minp = area.MinEdge
	local maxp = area.MaxEdge
	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			for x = minp.x, maxp.x do
				func(vector.new(x, y, z))
			end
		end
	end
end

---Get node name at a position
---@param vm VoxelManip
---@param data integer[]
---@param area VoxelArea
---@param pos Vector
---@return string
function voxel_utils.get_node_at_pos(vm, data, area, pos)
	local index = area:index(pos.x, pos.y, pos.z)
	local c = data[index]
	return core.get_name_from_content_id(c)
end

---Set node content id at a position
---@param data integer[]
---@param area VoxelArea
---@param pos Vector
---@param content_id integer
function voxel_utils.set_node_at_pos(data, area, pos, content_id)
	local index = area:index(pos.x, pos.y, pos.z)
	data[index] = content_id
end

---Safely set a node if inside area
---@param data integer[]
---@param area VoxelArea
---@param pos Vector
---@param content_id integer
---@return boolean success
function voxel_utils.safe_set_node(data, area, pos, content_id)
	if voxel_utils.is_inside_area(area, pos) then
		voxel_utils.set_node_at_pos(data, area, pos, content_id)
		return true
	end
	return false
end
(function()
	local p = vector_new
	---Get neighboring positions (6-directional)
	---@param pos Vector
	---@return Vector[]
	function voxel_utils.get_neighbors(pos)
		return {p(pos.x + 1, pos.y, pos.z), p(pos.x - 1, pos.y, pos.z), p(pos.x, pos.y + 1, pos.z), p(pos.x, pos.y - 1, pos.z),
			p(pos.x, pos.y, pos.z + 1), p(pos.x, pos.y, pos.z - 1)}
	end
end)()

---Fast integer hash for a node position using the engine's built-in method
---@param pos Vector
---@return integer
function voxel_utils.pos_hash(pos) return hash_node_position(pos) end

---Inverse of pos_hash
---@param hash integer
---@return Vector
function voxel_utils.pos_unhash(hash) return get_position_from_hash(hash) end

---Flood fill a voxel region starting at pos
---@param vm VoxelManip
---@param data integer[]
---@param area VoxelArea
---@param start_pos Vector
---@param predicate fun(node_name: string): boolean
---@param fill_content_id integer
function voxel_utils.flood_fill(vm, data, area, start_pos, predicate, fill_content_id)
	local to_visit = {start_pos}
	local visited = {}
	local pos_key = voxel_utils.pos_hash

	while #to_visit > 0 do
		local pos = table.remove(to_visit)
		local key = pos_key(pos)
		if not visited[key] and voxel_utils.is_inside_area(area, pos) then
			visited[key] = true
			local node_name = voxel_utils.get_node_at_pos(vm, data, area, pos)
			if predicate(node_name) then
				voxel_utils.set_node_at_pos(data, area, pos, fill_content_id)
				for _, npos in ipairs(voxel_utils.get_neighbors(pos)) do
					if not visited[pos_key(npos)] then
						table.insert(to_visit, npos)
					end
				end
			end
		end
	end
end

return voxel_utils
