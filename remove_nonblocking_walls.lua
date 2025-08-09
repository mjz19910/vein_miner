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
---@param start_pos vector
---@param area VoxelArea
---@param data integer[]
---@param walls_to_remove table<integer, boolean>
---@param liquids table<integer, boolean>
---@param action fun(pos: vector, vi: integer)
local function dfs_voxels(start_pos, area, data, walls_to_remove, liquids, action)
	local visited = {}
	local stack = {start_pos}

	while #stack > 0 do
		local pos = table.remove(stack)
		local key = core.hash_node_position(pos)
		if visited[key] then
			goto continue
		end
		visited[key] = true

		if not area:containsp(pos) then
			goto continue
		end

		local vi = area:indexp(pos)
		local cid = data[vi]
		if not walls_to_remove[cid] then
			goto continue
		end

		if is_blocking_flow(data, area, liquids, pos) then
			goto continue
		end

		action(pos, vi)

		for _, dir in ipairs(cardinal_dirs) do
			local npos = vector.add(pos, dir)
			local nkey = pos_key(npos)
			if not visited[nkey] then
				table.insert(stack, npos)
			end
		end

		::continue::
	end
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
		local radius = 5
		local p1 = vector.subtract(start_pos, radius)
		local p2 = vector.add(start_pos, radius)

		local vm = minetest.get_voxel_manip()
		local emin, emax = vm:read_from_map(p1, p2)
		local area = VoxelArea:new{
			MinEdge = emin,
			MaxEdge = emax,
		}
		local data = vm:get_data()

		local removed_count = 0

		local function remove_wall_action(pos, vi)
			data[vi] = minetest.CONTENT_AIR
			removed_count = removed_count + 1
		end

		dfs_voxels(start_pos, area, data, walls_to_remove, liquids, remove_wall_action)

		vm:set_data(data)
		vm:write_to_map()
		vm:update_map()

		minetest.chat_send_player(user:get_player_name(), string.format("Removed %d non-blocking walls.", removed_count))

		return itemstack
	end,
})
