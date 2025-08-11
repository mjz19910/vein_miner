core.register_abm({
	label = "Dry grass spread",
	nodenames = {"default:dry_dirt"},
	neighbors = {"air", "default:dry_dirt_with_dry_grass"},
	interval = 1,
	chance = 2,
	catch_up = true,
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

		-- Look for spreading dirt-type neighbours
		local p2 = core.find_node_near(pos, 1, "default:dry_dirt")
		if p2 then
			local n3 = core.get_node(p2)
			core.set_node(pos, {
				name = n3.name,
			})
			return
		end
	end,
})
