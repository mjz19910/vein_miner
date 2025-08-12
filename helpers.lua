local minetest = minetest
local pairs = pairs
---@class VeinMinerHelpers
local h = {}

---@param msg string
function h.log_warning(msg) minetest.log("warning", msg) end

---@param msg string
function h.log_error(msg) minetest.log("error", msg) end

---@param msg string
function h.log_action(msg) minetest.log("action", msg) end

---@param pos Vector
---@param mod_size Vector
function h.mod_pos(pos, mod_size)
	pos = vector.divide(pos, mod_size)
	pos = vector.add(pos, 0.0001)
	pos = vector.floor(pos)
	pos = vector.multiply(pos, mod_size)
	return pos
end

function h.is_liquid(node_name, liquid_type)
	return node_name == "default:" .. liquid_type .. "_source" or node_name == "default:" .. liquid_type .. "_flowing"
end

return h
