local DELAY_SECONDS = 0.5
local MAX_CHUNK_SIZE = 48
local MAP_BLOCKSIZE = 8

---@param chunk Chunk
---@param removed_count integer
local function log_chunk_warning(chunk, removed_count)
	local area = chunk.area
	local msg = string.format("Processed chunk from %s to %s, removed %d nodes", core.pos_to_string(area.MinEdge),
		core.pos_to_string(area.MaxEdge), removed_count)
	core.log("warning", "[remove_nonblocking_walls] " .. msg)
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

	local chunk_area = expand_area(base_p1, base_p2, 1)
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
