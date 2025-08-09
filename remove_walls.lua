---@param chunk_area VoxelArea
---@param walls_to_remove table<integer, boolean>
---@param vm VoxelManip
---@return Chunk[] -- chunks with .area and .start_list (Vector[])
local function split_area_into_chunks_with_start(chunk_area, walls_to_remove, vm)
	local chunks = {}
	local min = chunk_area.MinEdge
	local max = chunk_area.MaxEdge

	vm:read_from_map(min, max)
	local area = VoxelArea:new({
		MinEdge = min,
		MaxEdge = max,
	})
	local data = vm:get_data()

	local start_list = {}

	-- Collect all walls to remove within the chunk
	for z = min.z, max.z do
		for y = min.y, max.y do
			for x = min.x, max.x do
				local pos = vector.new(x, y, z)
				local vi = area:indexp(pos)
				if walls_to_remove[data[vi]] then
					table.insert(start_list, pos)
				end
			end
		end
	end

	if #start_list > 0 then
		table.insert(chunks, {
			area = area,
			start_list = start_list,
		})
	end

	return chunks
end

local active_players = {}

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

	-- Repeat after delay (e.g., 0.3s)
	minetest.after(0.3, function()
		if active_players[player_name] then
			repeat_action(user, itemstack, pointed_thing)
		end
	end)
end

minetest.register_tool("vein_miner:remove_walls", {
	description = "Remove Walls Tool",
	inventory_image = "default_tool_steelpick.png",

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
})
