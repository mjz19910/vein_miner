local VoxelArea = VoxelArea
local minetest = minetest

local CFG = vein_miner.CFG

local DELAY_SECONDS = 0.5
local MAX_CHUNK_SIZE = 24
local MAP_BLOCKSIZE = 8

local cardinal_dirs = CFG.cardinal_dirs

---@param vm VoxelManip
---@param start_list Vector[] -- multiple starting nodes
---@param walls_to_remove table<integer, boolean>
---@param liquids table<integer, boolean>
---@param area VoxelArea
---@param data integer[]
---@return integer removed_count, Chunk[] new_chunks
local function remove_nonblocking_walls_dfs(vm, start_list, walls_to_remove, liquids, area, data)
	local removed_count = 0
	local stack = {}
	for _, pos in ipairs(start_list) do
		table.insert(stack, pos)
	end

	local visited = {}
	local function pos_hash(pos) return core.hash_node_position(pos) end

	---@type Chunk[]
	local new_chunks = {}

	while #stack > 0 do
		local pos = table.remove(stack)
		local h = pos_hash(pos)
		if visited[h] then
			goto continue
		end

		visited[h] = true

		-- Check if pos inside current area
		if area:containsp(pos) then
			local vi = area:indexp(pos)
			local cid = data[vi]
			if walls_to_remove[cid] and not is_blocking_flow(data, area, liquids, pos) then
				data[vi] = minetest.CONTENT_AIR
				removed_count = removed_count + 1
			end

			-- Explore neighbors
			for _, dir in ipairs(cardinal_dirs) do
				local npos = vector.add(pos, dir)
				if not visited[pos_hash(npos)] then
					if area:containsp(npos) then
						local nvi = area:indexp(npos)
						if nvi and nvi >= 1 and nvi <= #data then
							local ncid = data[nvi]
							if walls_to_remove[ncid] then
								table.insert(stack, npos)
							end
						end
					else
						-- Out of bounds neighbor: if it's a wall node, add a new chunk around it
						local vm_tmp = minetest.get_voxel_manip()
						local chunk_min = vector.subtract(npos, 6)
						local chunk_max = vector.add(npos, 6)
						vm_tmp:read_from_map(chunk_min, chunk_max)
						local area_tmp = VoxelArea:new({
							MinEdge = chunk_min,
							MaxEdge = chunk_max,
						})
						local data_tmp = vm_tmp:get_data()

						if area_tmp:containsp(npos) then
							local vi_tmp = area_tmp:indexp(npos)
							if walls_to_remove[data_tmp[vi_tmp]] then
								table.insert(new_chunks, {
									area = area_tmp,
									start_list = {npos},
								})
							end
						end
					end
				end
			end
		end

		::continue::
	end

	return removed_count, new_chunks
end

---@param chunk Chunk
---@param removed_count integer
local function log_chunk_warning(chunk, removed_count)
	local area = chunk.area
	local msg = string.format("Processed chunk from %s to %s, removed %d nodes", minetest.pos_to_string(area.MinEdge),
		minetest.pos_to_string(area.MaxEdge), removed_count)
	minetest.log("warning", "[remove_nonblocking_walls] " .. msg)
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
			minetest.chat_send_player(user:get_player_name(), string.format("Removed %d non-blocking walls total.", removed_total))
			return
		end

		local chunk = chunks[chunk_index]
		local area = chunk.area
		vm:read_from_map(area.MinEdge, area.MaxEdge)
		local data = vm:get_data()

		local removed_count = remove_nonblocking_walls_dfs(vm, chunk.start_pos, walls_to_remove, liquids, area, data)
		removed_total = removed_total + removed_count

		vm:set_data(data)
		vm:write_to_map()
		vm:update_map()

		log_chunk_warning(chunk, removed_count)

		chunk_index = chunk_index + 1
		minetest.after(DELAY_SECONDS, process_next_chunk)
	end

	process_next_chunk()
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

	for x = min.x, max.x, MAX_CHUNK_SIZE do
		for y = min.y, max.y, MAX_CHUNK_SIZE do
			for z = min.z, max.z, MAX_CHUNK_SIZE do
				local chunk_min = vector.new(x, y, z)
				local chunk_max = vector.new(math.min(x + MAX_CHUNK_SIZE - 1, max.x), math.min(y + MAX_CHUNK_SIZE - 1, max.y),
					math.min(z + MAX_CHUNK_SIZE - 1, max.z))

				vm:read_from_map(chunk_min, chunk_max)
				local area = VoxelArea:new({
					MinEdge = chunk_min,
					MaxEdge = chunk_max,
				})
				local data = vm:get_data()

				local start_list = {}
				for cz = chunk_min.z, chunk_max.z do
					for cy = chunk_min.y, chunk_max.y do
						for cx = chunk_min.x, chunk_max.x do
							local pos = vector.new(cx, cy, cz)
							if area:containsp(pos) then
								local vi = area:indexp(pos)
								if walls_to_remove[data[vi]] then
									table.insert(start_list, pos)
								end
							end
						end
					end
				end

				if #start_list > 0 then
					table.insert(chunks, {
						area = VoxelArea:new({
							MinEdge = chunk_min,
							MaxEdge = chunk_max,
						}),
						start_list = start_list,
					})
				end
			end
		end
	end

	return chunks
end

local active_players = {}

local function expand_area(p1, p2, expand_blocks)
	-- expand_blocks: how many blocks to add in all directions
	local expand_size = expand_blocks * MAP_BLOCKSIZE

	local new_p1 = vector.subtract(p1, expand_size)
	local new_p2 = vector.add(p2, expand_size)

	-- Clamp to max size 48
	local size_x = new_p2.x - new_p1.x + 1
	local size_y = new_p2.y - new_p1.y + 1
	local size_z = new_p2.z - new_p1.z + 1

	-- If size > MAX_CHUNK_SIZE, clamp
	if size_x > MAX_CHUNK_SIZE then
		new_p2.x = new_p1.x + MAX_CHUNK_SIZE - 1
	end
	if size_y > MAX_CHUNK_SIZE then
		new_p2.y = new_p1.y + MAX_CHUNK_SIZE - 1
	end
	if size_z > MAX_CHUNK_SIZE then
		new_p2.z = new_p1.z + MAX_CHUNK_SIZE - 1
	end

	return new_p1, new_p2
end

local function do_remove_nonblocking_walls(itemstack, user, pointed_thing)
	-- Your existing tool code logic goes here, adapted as a function
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
	local base_p1 = vector.new(start_pos.x, start_pos.y, start_pos.z)
	local base_p2 = vector.new(start_pos.x, start_pos.y, start_pos.z)

	local min, max = expand_area(base_p1, base_p2, 1)
	local chunk_area = VoxelArea:new{
		MinEdge = min,
		MaxEdge = max,
	}
	local vm = minetest.get_voxel_manip()
	local chunks = split_area_into_chunks_with_start(chunk_area, walls_to_remove, vm)

	if #chunks == 0 then
		minetest.chat_send_player(user:get_player_name(), "No removable walls found nearby.")
		return itemstack
	end

	process_chunks_delayed(chunks, vm, walls_to_remove, liquids, user)

	return itemstack
end

local function repeat_action(user, itemstack, pointed_thing)
	if not user or not user:is_player() then
		return
	end
	local player_name = user:get_player_name()

	-- Check if still holding left click
	if not user:get_player_control().LMB then
		-- stop repeating
		active_players[player_name] = nil
		return
	end

	-- Call the remove walls function
	do_remove_nonblocking_walls(itemstack, user, pointed_thing)

	-- Repeat after delay (e.g., 0.4s)
	minetest.after(0.4, function()
		if active_players[player_name] then
			repeat_action(user, itemstack, pointed_thing)
		end
	end)
end

minetest.register_tool("vein_miner:remove_walls", {
	description = "Remove Walls Tool",
	inventory_image = "default_tool_steelpick.png",

	---@param itemstack ItemStack
	---@param user Player
	---@param pointed_thing table
	---@return ItemStack
	on_use = function(itemstack, user, pointed_thing)
		if not pointed_thing or pointed_thing.type ~= "node" then
			return itemstack
		end

		local player_name = user:get_player_name()
		if not active_players[player_name] then
			active_players[player_name] = true
			repeat_action(user, itemstack, pointed_thing)
		end

		return itemstack
	end,

	---@param itemstack ItemStack
	---@param user Player
	---@param pointed_thing table
	---@return ItemStack
	on_place = function(itemstack, user, pointed_thing)
		-- Stop repeating on right click (optional)
		local player_name = user:get_player_name()
		active_players[player_name] = nil
		return itemstack
	end,
})
