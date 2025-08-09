local core = core
local vector = vector
local ipairs = ipairs

local pos_str = core.pos_to_string
local vec_new = vector.new
local cardinal_dirs = {vec_new(1, 0, 0), vec_new(-1, 0, 0), vec_new(0, 1, 0), vec_new(0, -1, 0), vec_new(0, 0, 1), vec_new(0, 0, -1)}

---@param data integer[]
---@param area VoxelArea
---@param liquids table<integer, boolean>
---@param pos vector
---@return boolean
local function is_blocking_flow(data, area, liquids, pos)
	local current_cid = data[area:indexp(pos)]
	if liquids[current_cid] then
		return false
	end
	for _, dir in ipairs(cardinal_dirs) do
		local npos = vector.add(pos, dir)
		if area:containsp(npos) then
			local neighbor_cid = data[area:indexp(npos)]
			if liquids[neighbor_cid] then
				return true
			end
		end
	end
	return false
end

---@class Count
---@field val integer

---@param v integer
---@return Count
local function Count(v)
	return {
		val = v,
	}
end

---@param vm VoxelManip
---@param area VoxelArea
---@param data integer[]
---@param pos vector
---@param removed_count Count
local function remove_wall_action(vm, area, data, pos, removed_count)
	local vi = area:indexp(pos)
	data[vi] = minetest.CONTENT_AIR
	removed_count.val = removed_count.val + 1
end

-- DFS traversal over voxels in 'area' starting at 'start_pos'
-- Calls 'action(pos, vi)' on each visited voxel that matches walls_to_remove and not blocking flow.
---@param vm VoxelManip
---@param start_pos vector
---@param walls_to_remove table<number, boolean>
---@param liquids table<number, boolean>
local function remove_nonblocking_walls_dfs(vm, start_pos, walls_to_remove, liquids)
	local expand_margin = 2 -- how many nodes to expand by when needed

	local emin, emax = vm:read_from_map(start_pos, start_pos)
	local area = VoxelArea:new{
		MinEdge = emin,
		MaxEdge = emax,
	}
	local data = vm:get_data()

	local visited = {}
	local function mark_visited(pos) visited[core.hash_node_position(pos)] = true end
	local function is_visited(pos) return visited[core.hash_node_position(pos)] ~= nil end

	local stack = {start_pos}
	mark_visited(start_pos)

	local removed_count = Count(0)

	while #stack > 0 do
		local pos = table.remove(stack)
		local vi = area:indexp(pos)
		local cid = data[vi]

		if walls_to_remove[cid] and not is_blocking_flow(data, area, liquids, pos) then
			remove_wall_action(vm, area, data, pos, removed_count)
		end

		for _, dir in ipairs(cardinal_dirs) do
			local npos = vector.add(pos, dir)

			if not is_visited(npos) then
				if area:containsp(npos) then
					mark_visited(npos)
					table.insert(stack, npos)
				else
					-- Expand area to include npos
					local new_min = vector.min(area.MinEdge, vector.subtract(npos, expand_margin))
					local new_max = vector.max(area.MaxEdge, vector.add(npos, expand_margin))
					vm:read_from_map(new_min, new_max)
					emin, emax = vm:read_from_map(new_min, new_max)
					area = VoxelArea:new{
						MinEdge = emin,
						MaxEdge = emax,
					}
					data = vm:get_data()

					mark_visited(npos)
					table.insert(stack, npos)
				end
			end
		end
	end

	vm:set_data(data)
	vm:write_to_map()
	vm:update_map()

	return removed_count.val
end

local log_scope = "[remove_nonblocking_walls] "

local function log_chunk_warning(chunk, removed_count)
	local msg = string.format("Processed chunk from %s to %s, removed %d nodes", pos_str(chunk.min), pos_str(chunk.max), removed_count)
	minetest.log("warning", log_scope .. msg)
end

local vector_new = vector.new
local vector_add = vector.add
local vector_subtract = vector.subtract
local MAP_BLOCKSIZE = 16
local MAX_CHUNK_SIZE = 48
local DELAY_SECONDS = 0.5
local cardinal_dirs = {
	vector_new(1, 0, 0), vector_new(-1, 0, 0),
	vector_new(0, 1, 0), vector_new(0, -1, 0),
	vector_new(0, 0, 1), vector_new(0, 0, -1),
}

---@param p1 Vector
---@param p2 Vector
---@param expand_blocks integer Number of map blocks (size 16) to expand
---@return Vector, Vector
local function expand_area(p1, p2, expand_blocks)
	local offset = MAP_BLOCKSIZE * expand_blocks
	local min_expanded = vector_subtract(p1, offset)
	local max_expanded = vector_add(p2, offset)
	return min_expanded, max_expanded
end

---@param p1 Vector
---@param p2 Vector
---@return Vector[]
local function split_area_into_chunks(p1, p2)
	local chunks = {}
	for x = p1.x, p2.x, MAX_CHUNK_SIZE do
		for y = p1.y, p2.y, MAX_CHUNK_SIZE do
			for z = p1.z, p2.z, MAX_CHUNK_SIZE do
				local chunk_min = vector_new(x, y, z)
				local chunk_max = vector_new(
					math.min(x + MAX_CHUNK_SIZE - 1, p2.x),
					math.min(y + MAX_CHUNK_SIZE - 1, p2.y),
					math.min(z + MAX_CHUNK_SIZE - 1, p2.z)
				)
				table.insert(chunks, {min = chunk_min, max = chunk_max})
			end
		end
	end
	return chunks
end

---@param chunks table[] List of chunks {min=Vector, max=Vector}
---@param vm VoxelManip
---@param walls_to_remove table<integer, boolean>
---@param liquids table<integer, boolean>
---@param user Player
local function process_chunks_delayed(chunks, vm, walls_to_remove, liquids, user)
	local chunk_index = 1
	local removed_total = 0

	local function process_next_chunk()
		if chunk_index > #chunks then
			minetest.chat_send_player(user:get_player_name(),
				string.format("Removed %d non-blocking walls total.", removed_total))
			return
		end

		local chunk = chunks[chunk_index]
		vm:read_from_map(chunk.min, chunk.max)
		local area = VoxelArea:new{MinEdge=chunk.min, MaxEdge=chunk.max}
		local data = vm:get_data()

		local removed_count = remove_nonblocking_walls_dfs(vm, chunk.min, walls_to_remove, liquids, area, data)
		removed_total = removed_total + removed_count

		vm:set_data(data)
		vm:write_to_map()
		vm:update_map()

		minetest.log("warning", string.format("[remove_nonblocking_walls] Processed chunk from %s to %s, removed %d nodes",
			pos_str(chunk.min), pos_str(chunk.max), removed_count))

		chunk_index = chunk_index + 1
		minetest.after(DELAY_SECONDS, process_next_chunk)
	end

	process_next_chunk()
end

minetest.register_tool("vein_miner:remove_nonblocking_walls", {
	description = "Remove Non-blocking Walls Tool",
	inventory_image = "default_tool_steelpick.png",

	---@param itemstack ItemStack
	---@param user Player
	---@param pointed_thing table
	---@return ItemStack
	on_use = function(itemstack, user, pointed_thing)
		if not pointed_thing or pointed_thing.type ~= "node" then
			return itemstack
		end

		-- Runtime content IDs
		local cid_vein_wall = minetest.get_content_id("vein_miner:lit_cobble_1")
		local cid_wool_green = minetest.get_content_id("wool:green")

		local cid_water_source = minetest.get_content_id("default:water_source")
		local cid_water_flowing = minetest.get_content_id("default:water_flowing")
		local cid_lava_source = minetest.get_content_id("default:lava_source")
		local cid_lava_flowing = minetest.get_content_id("default:lava_flowing")

		local liquids = {
			[cid_water_source] = true,
			[cid_water_flowing] = true,
			[cid_lava_source] = true,
			[cid_lava_flowing] = true,
		}

		local walls_to_remove = {
			[cid_vein_wall] = true,
			[cid_wool_green] = true,
		}

		local start_pos = pointed_thing.under
		local base_p1 = vector_new(start_pos.x, start_pos.y, start_pos.z)
		local base_p2 = vector_new(start_pos.x, start_pos.y, start_pos.z)

		local expanded_p1, expanded_p2 = expand_area(base_p1, base_p2, 6)

		local size_x = expanded_p2.x - expanded_p1.x + 1
		local size_y = expanded_p2.y - expanded_p1.y + 1
		local size_z = expanded_p2.z - expanded_p1.z + 1

		local vm = minetest.get_voxel_manip()

		if size_x > MAX_CHUNK_SIZE or size_y > MAX_CHUNK_SIZE or size_z > MAX_CHUNK_SIZE then
			local chunks = split_area_into_chunks(expanded_p1, expanded_p2)
			process_chunks_delayed(chunks, vm, walls_to_remove, liquids, user)
		else
			vm:read_from_map(expanded_p1, expanded_p2)
			local area = VoxelArea:new{
				MinEdge = expanded_p1,
				MaxEdge = expanded_p2,
			}
			local data = vm:get_data()

			local removed_count = remove_nonblocking_walls_dfs(vm, start_pos, walls_to_remove, liquids, area, data)

			vm:set_data(data)
			vm:write_to_map()
			vm:update_map()

			minetest.chat_send_player(user:get_player_name(),
				string.format("Removed %d non-blocking walls.", removed_count))
		end

		return itemstack
	end,
})
