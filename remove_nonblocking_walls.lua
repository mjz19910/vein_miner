local vec_new = vector.new
local cardinal_dirs = {vec_new(1, 0, 0), vec_new(-1, 0, 0), vec_new(0, 1, 0), vec_new(0, -1, 0), vec_new(0, 0, 1), vec_new(0, 0, -1)}

local function is_blocking_flow(data, area, liquids, pos)
	local current_cid = data[area:indexp(pos)]

	if liquids[current_cid] then
		return false
	end

	for _, dir in ipairs(cardinal_dirs) do
		local npos = pos + dir
		if area:contains(npos) then
			local neighbor_cid = data[area:indexp(npos)]
			if liquids[neighbor_cid] then
				return true
			end
		end
	end

	return false
end

minetest.register_tool("vein_miner:remove_nonblocking_walls", {
	description = "Remove Non-blocking Walls Tool",
	inventory_image = "default_tool_steelpick.png", -- Minetest Game image

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

		local pos = pointed_thing.under
		local radius = 1
		local p1 = vector.subtract(pos, radius)
		local p2 = vector.add(pos, radius)

		local vm = minetest.get_voxel_manip()
		local emin, emax = vm:read_from_map(p1, p2)
		local area = VoxelArea:new{
			MinEdge = emin,
			MaxEdge = emax,
		}
		local data = vm:get_data()

		local removed_count = 0

		for z = p1.z, p2.z do
			for y = p1.y, p2.y do
				for x = p1.x, p2.x do
					local p = vector.new(x, y, z)
					local vi = area:indexp(p)
					local cid = data[vi]

					if walls_to_remove[cid] then
						if not is_blocking_flow(data, area, liquids, p) then
							data[vi] = minetest.CONTENT_AIR
							removed_count = removed_count + 1
						end
					end
				end
			end
		end

		vm:set_data(data)
		vm:write_to_map()
		vm:update_map()

		minetest.chat_send_player(user:get_player_name(), string.format("Removed %d non-blocking walls.", removed_count))

		return itemstack
	end,
})
