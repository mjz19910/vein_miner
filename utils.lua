-- utils.lua
local error = error
---@type LuantiCore
local core = core
local dofile = dofile
local vector = vector
local math = math
local floor = math.floor
local p = vector.new
local coroutine = coroutine
local ItemStack = ItemStack
local yield = coroutine.yield
local pairs = pairs
local ipairs = ipairs
local vein_miner = vein_miner

---@param table table
---@param element any
function table.contains(table, element)
	for _, value in pairs(table) do
		if value == element then
			return true
		end
	end
	return false
end

local table = table

---@param self Vector
---@param b Vector
function vector:midpoint(b) return p(floor((self.x + b.x) / 2 + 0.5), floor((self.y + b.y) / 2 + 0.5), floor((self.z + b.z) / 2 + 0.5)) end

local contains = table.contains

local modpath = core.get_modpath("vein_miner")

---@class VeinMinerUtils
local utils = {}

---@param path string
function utils.load(path) return dofile(modpath .. "/" .. path) end

---@param modpath string
function utils.require(modpath)
	local relative_path = modpath:gsub("^mods%.vein_miner%.", ""):gsub("%.", "/") .. ".lua"
	return utils.load(relative_path)
end

---@param time number
function utils.async_wait(time)
	yield({
		wait = true,
		time = time,
	})
end

---@param pos Vector
function utils.can_player_fit(pos)
	local pos_node = core.get_node(pos)
	local above = vector.offset(pos, 0, 1, 0)
	local above_node = core.get_node(above)
	return pos_node.name == "air" and above_node.name == "air"
end

---@param pos Vector
function utils.check_pos(pos)
	if utils.can_player_fit(pos) then
		return pos
	end
	return nil
end

---@param vmin number
---@param vmax number
---@param step number
function utils.clamp_max(vmin, vmax, step)
	local range = vmax - vmin
	local count = math.ceil(range / step)
	return vmin + count * step, range, count
end

---@param vmin number
---@param vmax number
---@param step number
function utils.linspace_inclusive(vmin, vmax, step)
	-- Returns a list starting at vmin and ending at vmax, with intervals ≤ step
	local result = {}
	local range = vmax - vmin
	local steps = math.max(1, math.ceil(range / step))

	for i = 0, steps do
		local t = i / steps
		table.insert(result, vmin + t * range)
	end

	return result
end

---@param start_pos number
---@param end_pos number
---@param step number
function utils.linspace_side(start_pos, end_pos, step)
	-- Generate points from start_pos to end_pos inclusive, stepping by step
	local points = {}
	local dir = (end_pos >= start_pos) and 1 or -1
	local dist = math.abs(end_pos - start_pos)
	local count = math.max(1, math.ceil(dist / step))

	for i = 0, count do
		local t = i / count
		local val = start_pos + dir * t * dist
		table.insert(points, val)
	end

	return points
end

---@param vmin number
---@param vmax number
---@param center number
---@param step number
function utils.linspace_centered(vmin, vmax, center, step)
	-- Build linspace that includes center exactly, split into two sides
	local left = utils.linspace_side(vmin, center, step)
	local right = utils.linspace_side(center, vmax, step)

	-- Remove duplicate center at start of right side
	table.remove(right, 1)

	-- Concatenate left + right
	for _, v in ipairs(right) do
		table.insert(left, v)
	end

	return left
end

---@param arr number[]
---@param value number
function utils.find_closest_index(arr, value)
	local closest_idx = 1
	local closest_dist = math.abs(arr[1] - value)
	for i = 2, #arr do
		local dist = math.abs(arr[i] - value)
		if dist < closest_dist then
			closest_idx = i
			closest_dist = dist
		end
	end
	return closest_idx
end

---@param player Player
function utils.has_empty_main_inv_slot(player)
	local inventory = player:get_inventory()
	local inv_list = inventory:get_list("main")
	if not inv_list then
		error("missing main list in player inventory")
	end
	for _, stack in ipairs(inv_list) do
		if stack:is_empty() then
			return true
		end
	end
	return false
end

return utils
