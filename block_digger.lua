local modpath = core.get_modpath("vein_miner")
local ToolWear = dofile(modpath .. "/tool_wear_controller.lua")

local BlockDigger = {}
BlockDigger.__index = BlockDigger

function BlockDigger.new(opts)
	return setmetatable({
		player = opts.player,
		wielded = opts.tool,
		teleporter = opts.teleporter,
		scan_options = opts.scan_options,
		max_nodes = opts.max_nodes,
	}, BlockDigger)
end

function BlockDigger:init_tool(node_name)
	self.tool_wear = ToolWear.new(self.player, node_name)
	self.mined_nodes = 0
	self.cur_mined_nodes = 0
	self.prev_pos = nil
	self.prev_sector = nil
end

function BlockDigger:should_dig(pos, expected_name)
	local node = core.get_node(pos)
	if node.name ~= expected_name or node.name == "air" then
		return false
	end

	-- Check for falling block support (block above)
	local above = vector.offset(pos, 0, 1, 0)
	local above_node = core.get_node(above)
	local above_def = minetest.registered_nodes[above_node.name]
	if above_def and above_def.groups and above_def.groups.falling_node then
		return false -- skip nodes that support falling nodes
	end

	return true
end

function BlockDigger:dig_node(pos, expected_name)
	if not self.tool_wear:is_usable() then return end
	if not self:should_dig(pos, expected_name) then return end

	local area_sector = mod_pos(pos, vector.new(16, 16, 16))
	local p = self.prev_pos

	if p then
		if self.prev_sector ~= area_sector or self.cur_mined_nodes >= self.max_nodes then
			coroutine.yield(self.cur_mined_nodes)
			self.mined_nodes = self.mined_nodes + self.cur_mined_nodes
			self.cur_mined_nodes = 0
			self.prev_sector = area_sector
			self.teleporter:drain()
		end
	end

	core.node_dig(pos, core.get_node(pos), self.player)
	self.tool_wear:apply_wear()
	self.cur_mined_nodes = self.cur_mined_nodes + 1
	self.prev_pos = pos
end

function BlockDigger:dig_group(node_name, node_positions)
	self:init_tool(node_name)

	for _, pos in pairs(node_positions) do
		self:dig_node(pos, node_name)
	end
end

return BlockDigger
