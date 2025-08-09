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

function utils.merge(other)
	for k, v in pairs(other) do
		self[k] = v
	end
end

return utils
