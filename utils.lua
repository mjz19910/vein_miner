-- utils.lua
local core = core
local dofile = dofile
local vector = vector
local table = table
local math = math
local floor = math.floor
local p = vector.new
local coroutine = coroutine
local yield = coroutine.yield
local pairs = pairs
local ipairs = ipairs

function table.contains(table, element)
	for _, value in pairs(table) do
		if value == element then
			return true
		end
	end
	return false
end

function vector.midpoint(a, b) return p(floor((a.x + b.x) / 2 + 0.5), floor((a.y + b.y) / 2 + 0.5), floor((a.z + b.z) / 2 + 0.5)) end

local modpath = core.get_modpath("vein_miner")

local utils = {}

function utils.load(path) return dofile(modpath .. "/" .. path) end

function utils.require(modpath)
	local relative_path = modpath:gsub("^mods%.vein_miner%.", ""):gsub("%.", "/") .. ".lua"
	return utils.load(relative_path)
end

function utils.async_wait(time)
	yield({
		wait = true,
		time = time,
	})
end

function utils.can_player_fit(pos)
	local pos_node = core.get_node(pos)
	local above = vector.offset(pos, 0, 1, 0)
	local above_node = core.get_node(above)
	return pos_node.name == "air" and above_node.name == "air"
end

function utils.check_pos(pos)
	if utils.can_player_fit(pos) then
		return pos
	end
	return nil
end

function utils.add_pos_to_queue(state, node_name, pos, options)
	local h = core.hash_node_position(pos)
	if state.queued_set[h] then
		return
	end
	state.queued_set[h] = true
	state.queue:push_right({
		node_name = node_name,
		pos = pos,
		options = utils.get_scan_options(node_name, options),
	})
end

function utils.handle_pos_notify(state, pos)
	local node = core.get_node(pos)
	utils.add_pos_to_queue(state, node.name, pos)
end

function utils:merge(other)
	for k, v in pairs(other) do
		self[k] = v
	end
end

function utils.clamp_max(vmin, vmax, step)
	local range = vmax - vmin
	local count = math.ceil(range / step)
	return vmin + count * step, range, count
end

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

function utils.has_empty_main_inv_slot(player)
	local inventory = player:get_inventory()
	local inv_list = inventory:get_list("main")
	for _, stack in ipairs(inv_list) do
		if stack:is_empty() then
			return true
		end
	end
	return false
end

return utils
