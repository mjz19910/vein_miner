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

-- DFS traversal over voxels in 'area' starting at 'start_pos'
-- Calls 'action(pos, vi)' on each visited voxel that matches walls_to_remove and not blocking flow.
---@param vm VoxelManip
---@param start_pos vector
---@param walls_to_remove table<number, boolean>
---@param liquids table<number, boolean>
---@param action fun(pos: vector, vi: integer, data: integer[]): boolean
local function remove_nonblocking_walls_dfs(vm, start_pos, walls_to_remove, liquids, action)
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

	local removed_count = 0

	while #stack > 0 do
		local pos = table.remove(stack)
		local vi = area:indexp(pos)
		local cid = data[vi]

		if walls_to_remove[cid] and not is_blocking_flow(data, area, liquids, pos) then
			action(pos, vi, data)
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
end
---@class InvRef
---@field get_size fun(self: InvRef, listname: string): integer
---@field set_size fun(self: InvRef, listname: string, size: integer)
---@field get_width fun(self: InvRef, listname: string): integer
---@field set_width fun(self: InvRef, listname: string, width: integer)
---@field get_stack fun(self: InvRef, listname: string, index: integer): ItemStack
---@field set_stack fun(self: InvRef, listname: string, index: integer, stack: ItemStack)
---@field add_item fun(self: InvRef, listname: string, stack: ItemStack): ItemStack|nil
---@field remove_item fun(self: InvRef, listname: string, stack: ItemStack): ItemStack|nil
---@field room_for_item fun(self: InvRef, listname: string, stack: ItemStack): boolean
---@field contains_item fun(self: InvRef, listname: string, stack: ItemStack): boolean
---@field get_list_names fun(self: InvRef): string[]
---@field set_location fun(self: InvRef, location: string)

---@class MetaDataRef
---@field get_string fun(self: MetaDataRef, key: string): string
---@field set_string fun(self: MetaDataRef, key: string, value: string)
---@field get_int fun(self: MetaDataRef, key: string): integer
---@field set_int fun(self: MetaDataRef, key: string, value: integer)
---@field get_float fun(self: MetaDataRef, key: string): number
---@field set_float fun(self: MetaDataRef, key: string, value: number)
---@field to_table fun(self: MetaDataRef): table
---@field from_table fun(self: MetaDataRef, table: table)
---@field get_inventory fun(self: MetaDataRef): InvRef
---@field set_inventory fun(self: MetaDataRef, inv: InvRef)

---@class ItemStack
---@field get_count fun(self: ItemStack): integer
---@field get_name fun(self: ItemStack): string
---@field take_item fun(self: ItemStack, count: integer): ItemStack
---@field add_item fun(self: ItemStack, stack: ItemStack|string): ItemStack
---@field get_wear fun(self: ItemStack): integer
---@field set_wear fun(self: ItemStack, wear: integer)
---@field get_meta fun(self: ItemStack): MetaDataRef
---@field to_string fun(self: ItemStack): string

---@class Player
---@field get_player_name fun(self: Player): string
---@field get_pos fun(self: Player): vector
---@field hud_add fun(self: Player, params: table): integer
---@field hud_remove fun(self: Player, id: integer)
---@field hud_change fun(self: Player, id: integer, params: table)
---@field hud_get fun(self: Player, id: integer): table
---@field get_wielded_item fun(self: Player): ItemStack
---@field set_wielded_item fun(self: Player, item: ItemStack|string)
---@field is_player fun(self: any): boolean

---@class pointed_thing
---@field type string
---@field under vector
---@field above vector

local MAP_BLOCKSIZE = 8
local MAX_CHUNK_SIZE = 48
local CHUNK_DELAY = 0.5

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

local function split_area_into_chunks(p1, p2)
	local chunks = {}

	for z = p1.z, p2.z, MAX_CHUNK_SIZE do
		for y = p1.y, p2.y, MAX_CHUNK_SIZE do
			for x = p1.x, p2.x, MAX_CHUNK_SIZE do
				local chunk_p1 = vector.new(x, y, z)
				local chunk_p2 = vector.new(math.min(x + MAX_CHUNK_SIZE - 1, p2.x), math.min(y + MAX_CHUNK_SIZE - 1, p2.y),
					math.min(z + MAX_CHUNK_SIZE - 1, p2.z))
				table.insert(chunks, {
					min = chunk_p1,
					max = chunk_p2,
				})
			end
		end
	end

	return chunks
end

local function process_chunks_delayed(chunks, vm, walls_to_remove, liquids, action, user, idx, removed_total)
	idx = idx or 1
	removed_total = removed_total or 0

	if idx > #chunks then
		minetest.chat_send_player(user:get_player_name(), string.format("Removed %d non-blocking walls (in chunks).", removed_total))
		return
	end

	local chunk = chunks[idx]
	-- Re-read map in chunk area
	vm:read_from_map(chunk.min, chunk.max)
	local area = VoxelArea:new{
		MinEdge = chunk.min,
		MaxEdge = chunk.max,
	}
	local data = vm:get_data()

	local removed = remove_nonblocking_walls_dfs(vm, chunk.min, walls_to_remove, liquids, action, area, data)
	removed_total = removed_total + removed

	vm:set_data(data)
	vm:write_to_map()
	vm:update_map()

	-- Schedule next chunk
	minetest.after(CHUNK_DELAY,
		function() process_chunks_delayed(chunks, vm, walls_to_remove, liquids, action, user, idx + 1, removed_total) end)
end

local function remove_wall_action(vm, area, data, pos, removed_count)
	local vi = area:indexp(pos)
	data[vi] = minetest.CONTENT_AIR
	removed_count.count = removed_count.count + 1
end

minetest.register_tool("vein_miner:remove_nonblocking_walls", {
	description = "Remove Non-blocking Walls Tool",
	inventory_image = "default_tool_steelpick.png",

	---@param itemstack ItemStack
	---@param user Player
	---@param pointed_thing pointed_thing
	---@return ItemStack
	on_use = function(itemstack, user, pointed_thing)
		if not pointed_thing or pointed_thing.type ~= "node" then
			return
		end

		-- Get content IDs here, at runtime
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
		local base_p1 = vector.subtract(start_pos, 0)
		local base_p2 = vector.add(start_pos, 0)

		-- Expand by blocks, e.g., 6 blocks = 48 nodes total
		local expanded_p1, expanded_p2 = expand_area(base_p1, base_p2, 6)

		-- If the expanded size is bigger than MAX_CHUNK_SIZE, split & process delayed
		local size_x = expanded_p2.x - expanded_p1.x + 1
		local size_y = expanded_p2.y - expanded_p1.y + 1
		local size_z = expanded_p2.z - expanded_p1.z + 1

		local vm = minetest.get_voxel_manip()

		if size_x > MAX_CHUNK_SIZE or size_y > MAX_CHUNK_SIZE or size_z > MAX_CHUNK_SIZE then
			local chunks = split_area_into_chunks(expanded_p1, expanded_p2)
			process_chunks_delayed(chunks, vm, walls_to_remove, liquids, remove_wall_action, user)
		else
			-- Just one chunk
			vm:read_from_map(expanded_p1, expanded_p2)
			local area = VoxelArea:new{
				MinEdge = expanded_p1,
				MaxEdge = expanded_p2,
			}
			local data = vm:get_data()

			local removed_count = remove_nonblocking_walls_dfs(vm, start_pos, walls_to_remove, liquids, remove_wall_action, area, data)

			vm:set_data(data)
			vm:write_to_map()
			vm:update_map()

			minetest.chat_send_player(user:get_player_name(), string.format("Removed %d non-blocking walls.", removed_count))
		end

		return itemstack
	end,
})
