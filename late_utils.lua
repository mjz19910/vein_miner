local CFG = vein_miner.CFG
local sticky_nodes = CFG.sticky_nodes
local l_utils = {}
local contains = table.contains
local ItemStack = ItemStack
local core = core
local ipairs = ipairs
local offset = vector.offset
local p = vector.new
local insert = table.insert

local light_nodes = vein_miner.CFG.LIGHT_NODES

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

function l_utils.get_scan_options(node_name, options)
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

function l_utils.add_pos_to_queue(state, node_name, pos, options)
	local h = core.hash_node_position(pos)
	if state.queued_set[h] then
		return
	end
	state.queued_set[h] = true
	state.queue:push_right({
		node_name = node_name,
		pos = pos,
		options = l_utils.get_scan_options(node_name, options),
	})
end

function l_utils.is_falling(name)
	local def = core.registered_nodes[name]
	return def and def.groups and def.groups.falling_node
end
function l_utils.is_liquid_source(name)
	local def = core.registered_nodes[name]
	return def and def.liquidtype == "source"
end
function l_utils.is_sticky_node(name) return sticky_nodes[name] == true end
local cardinal_dirs = {p(1, 0, 0), p(-1, 0, 0), p(0, 1, 0), p(0, -1, 0), p(0, 0, 1), p(0, 0, -1)}
function l_utils.get_adjacent_positions(pos)
	local ret = {}
	for _, v in ipairs(cardinal_dirs) do
		insert(ret, pos + v)
	end
	return ret
end
function l_utils.is_stuck_to_sticky(pos)
	for _, adj_pos in ipairs(l_utils.get_adjacent_positions(pos)) do
		local node = core.get_node(adj_pos)
		if l_utils.is_sticky_node(node.name) then
			return true
		end
	end
	return false
end

local floating_dirs = CFG.FLOATING_DIRS
function l_utils.is_floating(pos, expected_name)
	for _, offset in ipairs(floating_dirs) do
		local neighbor_pos = pos + offset
		local neighbor = core.get_node_or_nil(neighbor_pos)
		if neighbor and neighbor.name ~= "air" and neighbor.name ~= "ignore" and neighbor.name ~= expected_name then
			return false
		end
	end
	return true
end

return l_utils
