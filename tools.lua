local vector = vector
local ipairs = ipairs
local core = core
local vein_miner = vein_miner
local voxel_util = vein_miner.voxel_util
local p = vector.new

core.register_tool("vein_miner:log_particle_tool", {
	description = "Log Particle Highlighter",
	inventory_image = "default_wood.png",

	on_use = function(itemstack, user, pointed_thing)
		if not user or not user:is_player() then
			return itemstack
		end

		local logs = voxel_util.find_logs_keeping_leaves(user)
		for _, log_pos in ipairs(logs) do
			local above_pos = log_pos + p(0, 1, 0)
			local above_node = core.get_node_or_nil(above_pos)
			if above_node and (above_node.name == "air" or core.registered_nodes[above_node.name].buildable_to) then
				core.add_particle({
					pos = above_pos + p(0.5, 0.5, 0.5),
					velocity = p(0, 0.1, 0),
					acceleration = p(0, 0, 0),
					expirationtime = 2,
					size = 4,
					texture = "default_wood.png",
					glow = 4,
				})
			end
		end

		return itemstack
	end,
})
