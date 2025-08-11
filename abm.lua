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

if false then
	core.register_abm({
		label = "Remove invalid dirt towers",
		nodenames = {"default:dirt_with_rainforest_litter"},
		neighbors = {"air", "default:dirt"},
		interval = 15,
		chance = 50,
		catch_up = false,
		action = function(pos, node)
			local above = vector.offset(pos, 0, 1, 0)
			local n_above = core.get_node_or_nil(above)
			if not n_above then
				return
			end
			if n_above.name ~= "air" then
				return
			end
			-- Only trigger if we're the top block of a tower
			local below1 = vector.offset(pos, 0, -1, 0)
			local n_below1 = core.get_node_or_nil(below1)
			local n = core.get_node_or_nil(pos)
			if not n then
				return
			end
			if n_below1 and n_below1.name == "air" then
				core.node_dig(pos, n, nil)
				return
			end

			-- Walk down and collect tower nodes
			local tower_nodes = {pos}
			local c = vector.new(pos)
			c.y = c.y - 1
			while true do
				local n = core.get_node_or_nil(c)
				if not n or n.name ~= "default:dirt" then
					break
				end
				tower_nodes[#tower_nodes + 1] = vector.new(c)
				c.y = c.y - 1
			end

			-- this tower is tall enough
			if #tower_nodes >= 3 then
				return
			end

			if #tower_nodes == 1 then
				core.node_dig(pos, n, nil)
				return
			end

			local str_tower_pos_list = {}
			for _, p in ipairs(tower_nodes) do
				local n = core.get_node(p)
				core.node_dig(p, n, nil)
				table.insert(str_tower_pos_list, core.pos_to_string(p))
			end

			-- core.log("action", "tower of nodes dug (" .. table.concat(str_tower_pos_list, ",") .. ")")
		end,
	})

end
