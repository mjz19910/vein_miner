local l_utils = {}
local vein_miner = vein_miner
local table = table
local vector = vector
local contains = table.contains
local ItemStack = ItemStack
local core = core
local ipairs = ipairs
local offset = vector.offset
local p = vector.new
local insert = table.insert
local CFG = vein_miner.CFG

local light_nodes = CFG.LIGHT_NODES

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

---@param pos Vector
---@param state VienMinerState
function l_utils.handle_pos_notify(state, pos)
	local node = core.get_node(pos)
	l_utils.add_pos_to_queue(state, node.name, pos)
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
