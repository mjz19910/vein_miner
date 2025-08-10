local table = table
local insert = table.insert

local liquid_set = {
	["default:water_source"] = true,
	["default:water_flowing"] = true,
	["default:lava_source"] = true,
	["default:lava_flowing"] = true,
}

local BlockDigger = {}
local vein_miner = vein_miner
local vector = vector
local core = core
local ipairs = ipairs
local p = vector.new
local utils = vein_miner.utils
local l_utils = vein_miner.l_utils
local dir_down = p(0, -1, 0)
local possible_flow_directions = {p(-1, 0, 0), p(1, 0, 0), p(0, 0, -1), p(0, 0, 1), p(0, 1, 0)}
local check_for_falling_neighbors = {p(-1, -1, 0), p(1, -1, 0), p(0, -1, -1), p(0, -1, 1), p(0, -1, 0), p(-1, 0, 0), p(1, 0, 0),
	p(0, 0, -1), p(0, 0, 1), p(0, 1, 0)}

local contains = table.contains
local get_node = core.get_node

local CFG = vein_miner.CFG
local sticky_nodes = CFG.sticky_nodes

local function is_sticky_node(name) return sticky_nodes[name] == true end

local cardinal_dirs = {p(1, 0, 0), p(-1, 0, 0), p(0, 1, 0), p(0, -1, 0), p(0, 0, 1), p(0, 0, -1)}
local function get_adjacent_positions(pos)
	local ret = {}
	for _, v in ipairs(cardinal_dirs) do
		insert(ret, pos + v)
	end
	return ret
end

local function is_stuck_to_sticky(pos)
	for _, adj_pos in ipairs(get_adjacent_positions(pos)) do
		local node = get_node(adj_pos)
		if is_sticky_node(node.name) then
			return true
		end
	end
	return false
end

local light_nodes = CFG.LIGHT_NODES

function BlockDigger.should_dig(node, pos)
	if node.name == "air" then
		return false
	end
	if table.contains(light_nodes, node.name) then
		return true
	end
	if not is_sticky_node(node.name) and is_stuck_to_sticky(pos) then
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
