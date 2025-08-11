core.register_abm({
	label = "Dry grass spread",
	nodenames = {"default:dry_dirt"}, -- Trigger on dry dirt nodes, not dry grass
	neighbors = {"air", "default:dry_dirt_with_dry_grass"}, -- Check neighbors for dry grass
	interval = 6,
	chance = 50,
	catch_up = false,
	action = function(pos, node)
		-- Check for darkness: night, shadow or under a light-blocking node
		-- Returns if ignore above
		local above = {
			x = pos.x,
			y = pos.y + 1,
			z = pos.z,
		}
		if (core.get_node_light(above) or 0) < 13 then
			return
		end

		local p2 = core.find_node_near(pos, 1, "default:dry_dirt_with_dry_grass")
		if p2 then
			core.set_node(pos, {
				name = "default:dry_dirt_with_dry_grass",
			})
		end
	end,
})
