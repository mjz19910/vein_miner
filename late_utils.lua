local CFG = vein_miner.CFG
local light_nodes = CFG.LIGHT_NODES
local sticky_nodes = CFG.sticky_nodes
local utils = utils
local contains = table.contains
local ItemStack = ItemStack
local core = core
local ipairs = ipairs
local offset = vector.offset
local insert = vector.insert
local p = vector.new

local node_scan_options_cache = {}
local function get_real_scan_options(node_name, options)
	options = options or {}
	if contains(light_nodes, node_name) then
		options.light = true
	end
	local def = ItemStack(node_name):get_definition()
	if def.liquidtype == "source" then
		options.liquid = true
	end
	if def.liquidtype == "flowing" then
		options.liquid = true
	end
	return options
end
function utils.get_scan_options(node_name, options)
	options = options or {}
	if options.user then
		return get_real_scan_options(node_name, options)
	end
	if node_scan_options_cache[node_name] ~= nil then
		return node_scan_options_cache[node_name]
	end
	options = get_real_scan_options(node_name)
	node_scan_options_cache[node_name] = options
	return options
end

function utils.is_falling(name)
	local def = core.registered_nodes[name]
	return def and ((def.groups and def.groups.falling_node) or def.liquidtype == "source" or def.liquidtype == "flowing")
end
function utils.is_liquid_source(name)
	local def = core.registered_nodes[name]
	return def and def.liquidtype == "source"
end
function utils.is_sticky_node(name) return sticky_nodes[name] == true end
local cardinal_dirs = {p(1, 0, 0), p(-1, 0, 0), p(0, 1, 0), p(0, -1, 0), p(0, 0, 1), p(0, 0, -1)}
function utils.get_adjacent_positions(pos)
	local ret = {}
	for _, v in ipairs(cardinal_dirs) do
		insert(ret, pos + v)
	end
	return ret
end
function utils.is_stuck_to_sticky(pos)
	for _, adj_pos in ipairs(utils.get_adjacent_positions(pos)) do
		local node = core.get_node(adj_pos)
		if utils.is_sticky_node(node.name) then
			return true
		end
	end
	return false
end
