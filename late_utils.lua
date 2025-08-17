---@class VeinMinerLateUtils
local l_utils = {}
---@type VeinMinerGlobal
local vein_miner = vein_miner
local table = table
local vector = vector
local contains = table.contains
local ItemStack = ItemStack
---@type LuantiCore
local core = core
local ipairs = ipairs
local offset = vector.offset
local p = vector.new
local insert = table.insert
local CFG = vein_miner.CFG

local light_nodes = CFG.LIGHT_NODES

---@type table<string, ScanOptions>
local node_scan_options_cache = {}
---@param node_name string
---@param options ScanOptions
local function get_real_scan_options(node_name, options)
	options = options or {}
	if contains(light_nodes, node_name) then
		options.light = true
	end
	if node_name == "default:cobble" then
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

---@class ScanOptions
---@field user boolean|nil
---@field light boolean|nil
---@field liquid boolean|nil

---@param node_name string
---@param options ScanOptions
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

---@class ScanItem
---@field node_name string
---@field pos Vector
---@field options ScanOptions
---@field oldnode MapNode | nil

---@param state VeinMinerState
---@param node_name string
---@param pos Vector
---@param options ScanOptions
function l_utils.add_pos_to_queue(state, node_name, pos, options)
	local h = core.hash_node_position(pos)
	if state.queued_set[h] then
		return nil
	end
	state.queued_set[h] = true
	---@type ScanItem
	local item = {
		node_name = node_name,
		pos = pos,
		options = l_utils.get_scan_options(node_name, options),
	}
	state.queue:push_right(item)
	return item
end

---@param pos Vector
---@param state VeinMinerState
function l_utils.handle_pos_notify(state, pos)
	local node = core.get_node(pos)
	l_utils.add_pos_to_queue(state, node.name, pos)
end

local floating_dirs = CFG.FLOATING_DIRS
function l_utils.is_floating(pos, expected_name)
	for _, offset in ipairs(floating_dirs) do
		local neighbor_pos = pos + offset
		local neighbor = core.get_node_or_nil(neighbor_pos)
		if neighbor and neighbor.name ~= "air" and neighbor.name ~= "default:water_source" and neighbor.name ~= "default:water_flowing" and
			neighbor.name ~= "ignore" and neighbor.name ~= expected_name then
			return false
		end
	end
	return true
end

function l_utils.is_holding_liquid_back(pos, node)
	if node.name ~= "default:cobble" and node.name ~= "default:mossycobble" then
		return false
	end
	local pos1 = vector.offset(pos, 0, 1, 0)
	local node1 = core.get_node_or_nil(pos1)
	if not node1 then
		return true
	end
	local def1 = core.registered_nodes[node1.name]
	local pos2 = vector.offset(pos, -1, 0, 0)
	local node2 = core.get_node_or_nil(pos2)
	if not node2 then
		return true
	end
	local def2 = core.registered_nodes[node2.name]
	if def1.liquidtype == "source" and def2.liquidtype == "source" then
		return false
	end
	local pos2 = vector.offset(pos, 0, 0, 1)
	local node2 = core.get_node_or_nil(pos2)
	if not node2 then
		return true
	end
	local def2 = core.registered_nodes[node2.name]
	if def1.liquidtype == "source" and def2.liquidtype == "source" then
		return false
	end
	for _, offset in ipairs(floating_dirs) do
		local neighbor_pos = pos + offset
		local neighbor = core.get_node_or_nil(neighbor_pos)
		if not neighbor then
			return true
		end
		local ndef = core.registered_nodes[neighbor.name]
		if ndef.liquidtype == "source" or ndef.liquidtype == "flowing" then
			return true
		end
		::continue::
	end
	return false
end

return l_utils
