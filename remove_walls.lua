local core = core
---@type VectorModule
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

---@param cid integer
---@return string
local function get_node_name(cid) return minetest.get_name_from_content_id(cid) or tostring(cid) end

---@param vm VoxelManip
---@param start_pos Vector
---@param walls_to_remove table<integer, boolean>
---@param liquids table<integer, boolean>
---@param area VoxelArea
---@param data integer[]
---@return integer removed_count
local function remove_nonblocking_walls_dfs(vm, start_pos, walls_to_remove, liquids, area, data)
	local removed_count = 0
	local stack = {start_pos}
	local visited = {}

	-- Helper to get hash of a position (for visited set)
	local function pos_hash(pos) return core.hash_node_position(pos) end

	while #stack > 0 do
		local pos = table.remove(stack) -- pop

		local h = pos_hash(pos)
		if visited[h] then
			goto continue
		end

		-- Skip positions outside the area
		if not area:containsp(pos) then
			local outside_node = core.get_node(pos)
			local out_name = outside_node.name
			local out_cid = core.get_content_id(out_name)
			core.log("warning", ("Skip node out of bounds (dfs visit) of %s to %s cid %d (%s)"):format(pos_str(area.MinEdge), pos_str(area.MaxEdge),
				out_cid, out_name))
			goto continue
		end

		visited[h] = true

		local vi = area:indexp(pos)
		local cid = data[vi]
		local cid_name = get_node_name(cid)
		core.log("warning", string.format("checking node at %s cid %d (%s)", pos_str(pos), cid, cid_name))
		if walls_to_remove[cid] and not is_blocking_flow(data, area, liquids, pos) then
			local name = get_node_name(cid)
			core.log("warning", string.format("Removing node at %s cid %d (%s)", pos_str(pos), cid, name))
			data[vi] = minetest.CONTENT_AIR
			removed_count = removed_count + 1
		end

		-- Explore neighbors
		for _, dir in ipairs(cardinal_dirs) do
			local npos = vector.add(pos, dir)
			if area:containsp(npos) then
				local nvi = area:indexp(npos)
				if nvi and nvi >= 1 and nvi <= #data then
					local ncid = data[nvi]
					local ncid_name = get_node_name(ncid)
					if walls_to_remove[ncid] and not visited[pos_hash(npos)] then
						core.log("warning", string.format("Pushing neighbor %s cid %d (%s)", pos_str(npos), ncid, ncid_name))
						table.insert(stack, npos)
					else
						core.log("warning", string.format("Skipping neighbor not wall to remove %s cid %d (%s)", pos_str(npos), ncid, ncid_name))
					end
				end
			else
				local outside_node = core.get_node(npos)
				local out_name = outside_node.name
				local out_cid = core.get_content_id(out_name)
				core.log("warning", ("Skip node out of bounds (dfs neighbors) of %s to %s cid %d (%s)"):format(pos_str(area.MinEdge),
					pos_str(area.MaxEdge), out_cid, out_name))
			end
		end

		::continue::
	end

	return removed_count
end

local log_scope = "[remove_nonblocking_walls] "

---@class Chunk
---@field area VoxelArea
---@field start_pos Vector

---@param chunk Chunk
---@param removed_count integer
local function log_chunk_warning(chunk, removed_count)
	local area = chunk.area
	local msg = string.format("Processed chunk from %s to %s, removed %d nodes", pos_str(area.MinEdge), pos_str(area.MaxEdge), removed_count)
	minetest.log("warning", log_scope .. msg)
end

local vector_new = vector.new
local vector_add = vector.add
local vector_subtract = vector.subtract
local MAP_BLOCKSIZE = 16
local MAX_CHUNK_SIZE = 48
local DELAY_SECONDS = 0.5

local VoxelArea = VoxelArea
---@class VoxelAreaInit
---@field MinEdge Vector
---@field MaxEdge Vector
---@param tbl VoxelAreaInit
---@return VoxelArea
local VoxelArea_new = function(tbl) return VoxelArea:new(tbl) end

---@param p1 Vector
---@param p2 Vector
---@param expand_blocks integer Number of nodes to expand
---@return VoxelArea
local function expand_area(p1, p2, expand_nodes)
	local offset = math.floor(expand_nodes / 2)
	local min_expanded = vector_subtract(p1, offset)
	local max_expanded = vector_add(p2, offset)
	return VoxelArea_new {
		MinEdge = min_expanded,
		MaxEdge = max_expanded,
	}
end

---@param chunk_area VoxelArea
---@param walls_to_remove table<integer, boolean>
---@param vm VoxelManip
---@return Chunk[]
local function split_area_into_chunks_with_start(chunk_area, walls_to_remove, vm)
	---@type Chunk[]
	local chunks = {}
	local min = chunk_area.MinEdge
	local max = chunk_area.MaxEdge

	local size_x = max.x - min.x + 1
	local size_y = max.y - min.y + 1
	local size_z = max.z - min.z + 1

	if size_x <= MAX_CHUNK_SIZE and size_y <= MAX_CHUNK_SIZE and size_z <= MAX_CHUNK_SIZE then
		vm:read_from_map(min, max)
		local area = VoxelArea:new({
			MinEdge = min,
			MaxEdge = max,
		})
		local data = vm:get_data()

		local start_pos = nil
		for z = min.z, max.z do
			for y = min.y, max.y do
				for x = min.x, max.x do
					local pos = vector.new(x, y, z)
					local vi = area:indexp(pos)
					if walls_to_remove[data[vi]] then
						start_pos = pos
						break
					end
				end
				if start_pos then
					break
				end
			end
			if start_pos then
				break
			end
		end

		if start_pos then
			table.insert(chunks, {
				area = area,
				start_pos = start_pos,
			})
		end

		return chunks
	end

	for x = min.x, max.x, MAX_CHUNK_SIZE do
		for y = min.y, max.y, MAX_CHUNK_SIZE do
			for z = min.z, max.z, MAX_CHUNK_SIZE do
				local chunk_min = vector.new(x, y, z)
				local chunk_max = vector.new(math.min(x + MAX_CHUNK_SIZE - 1, max.x), math.min(y + MAX_CHUNK_SIZE - 1, max.y),
					math.min(z + MAX_CHUNK_SIZE - 1, max.z))

				-- Read chunk voxel data to find a start wall node
				vm:read_from_map(chunk_min, chunk_max)
				local area = VoxelArea_new({
					MinEdge = chunk_min,
					MaxEdge = chunk_max,
				})
				local data = vm:get_data()

				local start_pos = nil
				for cz = chunk_min.z, chunk_max.z do
					for cy = chunk_min.y, chunk_max.y do
						for cx = chunk_min.x, chunk_max.x do
							local pos = vector.new(cx, cy, cz)
							if area:containsp(pos) then
								local vi = area:indexp(pos)
								if walls_to_remove[data[vi]] then
									start_pos = pos
									break
								end
							end
						end
						if start_pos then
							break
						end
					end
					if start_pos then
						break
					end
				end

				if start_pos then
					table.insert(chunks, {
						area = VoxelArea_new {
							MinEdge = chunk_min,
							MaxEdge = chunk_max,
						},
						start_pos = start_pos,
					})
				else
					-- Skip chunks with no walls to remove
				end
			end
		end
	end

	return chunks
end

---@param chunks Chunk[]
---@param vm VoxelManip
---@param walls_to_remove table<integer, boolean>
---@param liquids table<integer, boolean>
---@param user Player
local function process_chunks_delayed(chunks, vm, walls_to_remove, liquids, user)
	local chunk_index = 1
	local removed_total = 0

	local function process_next_chunk()
		if chunk_index > #chunks then
			return
		end

		local chunk = chunks[chunk_index]
		local area = chunk.area
		vm:read_from_map(area.MinEdge, area.MaxEdge)
		local data = vm:get_data()

		-- Use saved start_pos inside chunk
		local removed_count = remove_nonblocking_walls_dfs(vm, chunk.start_pos, walls_to_remove, liquids, area, data)
		removed_total = removed_total + removed_count

		vm:set_data(data)
		vm:write_to_map()
		vm:update_map()

		log_chunk_warning(chunk, removed_count)

		chunk_index = chunk_index + 1
		if chunk_index > #chunks then
			minetest.chat_send_player(user:get_player_name(), string.format("Removed %d non-blocking walls total.", removed_total))
			return
		end
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

		print("cid_vein_wall", cid_vein_wall)
		print("cid_wool_green", cid_wool_green)

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

		local chunk_area = expand_area(base_p1, base_p2, 12)
		local vm = minetest.get_voxel_manip()
		local chunks = split_area_into_chunks_with_start(chunk_area, walls_to_remove, vm)
		core.log("warning", "chunks from pos " .. pos_str(start_pos) .. " " .. core.serialize(chunks))
		process_chunks_delayed(chunks, vm, walls_to_remove, liquids, user)

		return itemstack
	end,
})
