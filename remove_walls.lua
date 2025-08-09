local VoxelArea = VoxelArea
local minetest = minetest
local core = core
local table = table
local vector = vector
local ipairs = ipairs
local math = math

local CFG = vein_miner.CFG

local DELAY_SECONDS = 0.5
local MAX_CHUNK_SIZE = 8 * 2
local MAP_BLOCKSIZE = 8
local MAX_EXPAND = 12 -- nodes to expand by when out of bounds neighbor found

local cardinal_dirs = CFG.cardinal_dirs

---@type fun(pos: Vector): string
local pos_str = core.pos_to_string

local function send_message_to_user(name, msg)
	core.chat_send_player(name, msg)
	core.log("action", msg)
end

---@type table<integer, boolean>
local liquids = {}

local function is_blocking_flow(data, area, pos)
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

---@type table<integer, boolean>
local walls_to_remove = {}

---@param vm VoxelManip
---@param current_area VoxelArea
---@param pos Vector
---@return VoxelArea
local function expand_area_conditionally(vm, current_area, pos)
	local vector = vector
	local min_edge = current_area.MinEdge
	local max_edge = current_area.MaxEdge

	local expand_min = vector.new(math.min(min_edge.x, pos.x - MAX_EXPAND), math.min(min_edge.y, pos.y - MAX_EXPAND),
		math.min(min_edge.z, pos.z - MAX_EXPAND))
	local expand_max = vector.new(math.max(max_edge.x, pos.x + MAX_EXPAND), math.max(max_edge.y, pos.y + MAX_EXPAND),
		math.max(max_edge.z, pos.z + MAX_EXPAND))

	if expand_min.x == min_edge.x and expand_min.y == min_edge.y and expand_min.z == min_edge.z and expand_max.x == max_edge.x and expand_max.y ==
		max_edge.y and expand_max.z == max_edge.z then
		return current_area -- no expansion needed
	end

	vm:read_from_map(expand_min, expand_max)
	local area_check = VoxelArea:new{
		MinEdge = expand_min,
		MaxEdge = expand_max,
	}
	local data_check = vm:get_data()

	for z = expand_min.z, expand_max.z do
		for y = expand_min.y, expand_max.y do
			for x = expand_min.x, expand_max.x do
				local pos_check = vector.new(x, y, z)
				local vi = area_check:indexp(pos_check)
				if walls_to_remove[data_check[vi]] then
					return area_check
				end
			end
		end
	end

	return current_area -- no walls found, skip expansion
end

---@param vm VoxelManip
---@param start_pos Vector
---@param area VoxelArea
---@param data integer[]
---@return integer removed_count
local function remove_nonblocking_walls_dfs(vm, start_pos, area, data)
	local removed_count = 0
	local stack = {start_pos}
	local visited = {}

	local function pos_hash(pos) return core.hash_node_position(pos) end

	while #stack > 0 do
		local pos = table.remove(stack)
		local h = pos_hash(pos)
		if visited[h] then
			goto continue
		end
		if not area:containsp(pos) then
			-- Out of current area, check if we can expand
			vm:write_to_map() -- save changes before expanding
			area = expand_area_conditionally(vm, area, pos)
			data = vm:get_data()
			if not area:containsp(pos) then
				-- Even after expansion pos not in area, skip
				goto continue
			end
		end

		visited[h] = true

		local vi = area:indexp(pos)
		local cid = data[vi]

		if walls_to_remove[cid] and not is_blocking_flow(data, area, pos) then
			data[vi] = minetest.CONTENT_AIR
			removed_count = removed_count + 1
		end

		for _, dir in ipairs(cardinal_dirs) do
			local npos = vector.add(pos, dir)
			local nh = pos_hash(npos)
			if not visited[nh] then
				if area:containsp(npos) then
					local nvi = area:indexp(npos)
					local ncid = data[nvi]
					if walls_to_remove[ncid] then
						table.insert(stack, npos)
					end
				else
					-- Out of area neighbors will trigger expansion next iteration
					-- but only add if possibly a wall (no CID check since no data)
					table.insert(stack, npos)
				end
			end
		end

		::continue::
	end

	return removed_count
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
---@param user Player
local function process_chunks_delayed(chunks, vm, user)
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

		local removed_count = remove_nonblocking_walls_dfs(vm, chunk.start_list[1], area, data)
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
---@param vm VoxelManip
---@return Chunk[]
local function split_area_into_chunks_with_start(chunk_area, vm)
	---@type Chunk[]
	local chunks = {}
	local min = chunk_area.MinEdge
	local max = chunk_area.MaxEdge

	local xsz = max.x - min.x + 1
	local ysz = max.y - min.y + 1
	local zsz = max.z - min.z + 1

	local x_chunk_sz = math.min(MAX_CHUNK_SIZE, math.floor(xsz / 2) + 1)
	local y_chunk_sz = math.min(MAX_CHUNK_SIZE, math.floor(ysz / 2) + 1)
	local z_chunk_sz = math.min(MAX_CHUNK_SIZE, math.floor(zsz / 2) + 1)

	for x = min.x, max.x, x_chunk_sz do
		for y = min.y, max.y, y_chunk_sz do
			for z = min.z, max.z, z_chunk_sz do
				local chunk_min = vector.new(x, y, z)
				local chunk_max = vector.new(math.min(x + x_chunk_sz - 1, max.x), math.min(y + y_chunk_sz - 1, max.y),
					math.min(z + z_chunk_sz - 1, max.z))

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

	return new_p1, new_p2
end

local cid_vein_wall
local cid_wool_green

local cid_water_source
local cid_water_flowing
local cid_lava_source
local cid_lava_flowing

local function do_remove_nonblocking_walls(itemstack, user, pointed_thing)
	-- Your existing tool code logic goes here, adapted as a function
	if not pointed_thing or pointed_thing.type ~= "node" then
		return itemstack
	end

	-- Runtime content IDs
	cid_vein_wall = minetest.get_content_id("vein_miner:lit_cobble_1")
	cid_wool_green = minetest.get_content_id("wool:green")

	cid_water_source = minetest.get_content_id("default:water_source")
	cid_water_flowing = minetest.get_content_id("default:water_flowing")
	cid_lava_source = minetest.get_content_id("default:lava_source")
	cid_lava_flowing = minetest.get_content_id("default:lava_flowing")

	liquids = {
		[cid_water_source] = true,
		[cid_water_flowing] = true,
		[cid_lava_source] = true,
		[cid_lava_flowing] = true,
	}

	walls_to_remove = {
		[cid_vein_wall] = true,
		[cid_wool_green] = true,
	}

	local start_pos = pointed_thing.under
	local base_p1 = vector.new(start_pos.x, start_pos.y, start_pos.z)
	local base_p2 = vector.new(start_pos.x, start_pos.y, start_pos.z)

	local min, max = expand_area(base_p1, base_p2, 3)
	local chunk_area = VoxelArea:new{
		MinEdge = min,
		MaxEdge = max,
	}
	local vm = minetest.get_voxel_manip()
	local chunks = split_area_into_chunks_with_start(chunk_area, vm)

	local chunk_areas = {}
	for _, v in ipairs(chunks) do
		table.insert(chunk_areas, {v.area.MinEdge, v.area.MaxEdge})
	end
	local name = user:get_player_name()

	send_message_to_user(name, "chunk_areas=" .. core.serialize(chunk_areas))

	if #chunks == 0 then
		send_message_to_user(name, "No removable walls found nearby.")
		return itemstack
	end

	process_chunks_delayed(chunks, vm, user)

	return itemstack
end

local function raycast_next_pointed(user, max_distance)
	local pos = user:get_pos()
	local eye_offset = vector.new(0, user:get_properties().eye_height or 1.5, 0)
	local eye_pos = vector.add(pos, eye_offset)
	local look_dir = user:get_look_dir()

	local ray = core.raycast(eye_pos, vector.add(eye_pos, vector.multiply(look_dir, max_distance)), false, false)

	for pointed_thing in ray do
		if pointed_thing.type == "node" then
			return pointed_thing
		end
	end
	return nil
end

minetest.register_tool("vein_miner:remove_walls", {
	description = "Remove Walls Tool",
	inventory_image = "default_tool_steelpick.png",

	---@param itemstack ItemStack
	---@param user Player
	---@param pointed_thing table
	---@return ItemStack
	on_use = function(itemstack, user, pointed_thing)
		local player_name = user:get_player_name()
		-- Call the remove walls function
		do_remove_nonblocking_walls(itemstack, user, pointed_thing)
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
