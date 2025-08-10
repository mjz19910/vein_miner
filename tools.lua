local vector = vector
local ipairs = ipairs
local core = core
local vein_miner = vein_miner
local voxel_util = vein_miner.voxel_util
local p = vector.new

core.register_tool("vein_miner:log_particle_tool", {
	description = "Log Particle Highlighter",
	inventory_image = "default_torch_on_floor.png",

	on_use = function(itemstack, user, pointed_thing)
		if not user or not user:is_player() or not pointed_thing.under then
			return itemstack
		end

		local logs = voxel_util.find_logs_keeping_leaves(pointed_thing.under)
		for _, log_pos in ipairs(logs) do
			local above_pos = log_pos + p(0, 1, 0)
			local above_node = core.get_node_or_nil(above_pos)
			if above_node and (above_node.name == "air" or core.registered_nodes[above_node.name].buildable_to) then
				local log_node = core.get_node(log_pos)
				local particle_texture
				-- try to get texture of the log node
				local def = core.registered_nodes[log_node.name]
				if def and def.tiles then
					local top = def.tiles[1]
					local side = def.tiles[3] or top
					if type(top) == "table" then
						top = top.name
					end
					if type(side) == "table" then
						side = side.name
					end
					particle_texture = "[inventorycube{" .. top .. "{" .. side .. "{" .. side
				end

				if not particle_texture then
					local log_tex = "default_wood.png" -- fallback
					particle_texture = "[inventorycube{" .. log_tex .. "{" .. log_tex .. "{" .. log_tex
				end
				core.add_particle({
					pos = above_pos,
					velocity = p(0, -0.1 / 3, 0),
					acceleration = p(0, 0, 0),
					expirationtime = 6,
					size = 6,
					texture = particle_texture, -- "[inventorycube{default_wood.png{default_wood.png{default_wood.png",
					glow = 5,
				})
			end
		end

		return itemstack
	end,
})
