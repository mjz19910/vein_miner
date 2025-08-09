local possible_flow_directions = {vector.new(-1, 0, 0), vector.new(1, 0, 0), vector.new(0, 0, -1), vector.new(0, 0, 1), vector.new(0, 1, 0)}
local check_for_falling_neighbors = {vector.new(-1, -1, 0), vector.new(1, -1, 0), vector.new(0, -1, -1), vector.new(0, -1, 1),
	vector.new(0, -1, 0), vector.new(-1, 0, 0), vector.new(1, 0, 0), vector.new(0, 0, -1), vector.new(0, 0, 1), vector.new(0, 1, 0)}
local liquid_set = {
	["default:water_source"] = true,
	["default:water_flowing"] = true,
	["default:lava_source"] = true,
	["default:lava_flowing"] = true,
}

local BlockDigger = {}
local utils = vein_miner.utils
local dir_down = vector.new(0, -1, 0)

function BlockDigger.should_dig(node, pos)
	if node.name == "air" then
		return false
	end
	if table.contains(utils.light_nodes, node.name) then
		return true
	end
	if not utils.is_sticky_node(node.name) and utils.is_stuck_to_sticky(pos) then
		return false
	end
	local above = vector.offset(pos, 0, 1, 0)
	local above_node = core.get_node(above)
	if above_node.name == "default:snow" then
		return true -- falling block that we want to fall
	end
	if utils.is_falling(above_node.name) then
		return false
	end
	if false then
		for _, off in ipairs(possible_flow_directions) do
			local npos = pos + off
			if utils.is_liquid_source(core.get_node(npos).name) then
				return false -- digging here may cause liquid to flow
			end
		end
	end
	for _, off in ipairs(check_for_falling_neighbors) do
		local npos = pos + off
		local above_node = core.get_node(npos)
		if utils.is_falling(above_node.name) then
			local below = npos + dir_down
			local below_node = core.get_node(below)
			if below_node.name == "air" or liquid_set[below_node.name] then
				return false -- this falling node is unsupported
			end
		end
	end
	return true -- safe to mine
end

return BlockDigger
