---@class VeinMinerHelpers
local h = {}

---@type LuantiCore
local core = core
local pairs = pairs
local ipairs = ipairs

---@type VectorModule
local vector = vector

local vec_floor = vector.floor

local registered_nodes = core.registered_nodes

---@param msg string
function h.log_warning(msg) core.log("warning", msg) end

---@param msg string
function h.log_error(msg) core.log("error", msg) end

---@param msg string
function h.log_action(msg) core.log("action", msg) end

local vec_unit = vector.new(1, 1, 1)

---@param pos Vector
---@param mod_size Vector
function h.mod_pos(pos, mod_size) return vector.multiply(vec_floor(vector.divide(pos, mod_size)), mod_size) end

function h.is_liquid(node_name, liquid_type)
	return node_name == "default:" .. liquid_type .. "_source" or node_name == "default:" .. liquid_type .. "_flowing"
end

function h.make_set(table, init)
	local ret = {}
	for _, value in ipairs(table) do
		ret[value] = init
	end
	return ret
end

---@param node MapNode
function h.is_passable(node)
	local def = registered_nodes[node.name]
	return def and def.walkable == false
end

---@param node MapNode
---@param skip_name string
function h.is_node_supporting(node, skip_name)
	if node == nil then
		return false
	end
	if node.name == skip_name then
		return false
	end
	local def = registered_nodes[node.name]
	if def.air_equivalent then
		return false
	end
	if def.liquidtype == "source" then
		return true
	end
	if def.liquidtype == "flowing" then
		return true
	end
	if not def then
		return false
	end
	-- return not def.floodable and def.walkable
	return true
end

return h
