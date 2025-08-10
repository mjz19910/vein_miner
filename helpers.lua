local minetest = minetest
local pairs = pairs
vein_miner.h = {}
---@param groups table<string, string[]>
---@param valid_set table<string, boolean>
function vein_miner.h.generate_mine_only_sets(groups, valid_set)
	---@type table<string, string>
	local ret = {}
	for key, group in pairs(groups) do
		for idx, value in pairs(group) do
			ret[value] = key
			valid_set[value] = true
		end
	end
	return ret
end

function vein_miner.h.log_warning(msg) minetest.log("warning", msg) end

function vein_miner.h.log_error(msg) minetest.log("error", msg) end

function vein_miner.h.log_action(msg) minetest.log("action", msg) end

function vein_miner.h.mod_pos(pos, mod_size)
	pos = vector.divide(pos, mod_size)
	pos = vector.add(pos, 0.0001)
	pos = vector.floor(pos)
	pos = vector.multiply(pos, mod_size)
	return pos
end

function vein_miner.h.is_liquid(node_name, liquid_type)
	return node_name == "default:" .. liquid_type .. "_source" or node_name == "default:" .. liquid_type .. "_flowing"
end
