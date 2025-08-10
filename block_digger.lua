local coroutine = coroutine
local ItemStack = ItemStack
local table = table
local pairs = pairs
local insert = table.insert
local yield = coroutine.yield

local liquid_set = {
	["default:water_source"] = true,
	["default:water_flowing"] = true,
	["default:lava_source"] = true,
	["default:lava_flowing"] = true,
}

local BlockDigger = {}
local vein_miner = vein_miner
local vector = vector
local core = core
local ipairs = ipairs
local p = vector.new
local utils = vein_miner.utils
local l_utils = vein_miner.l_utils
local dir_down = p(0, -1, 0)
local possible_flow_directions = {p(-1, 0, 0), p(1, 0, 0), p(0, 0, -1), p(0, 0, 1), p(0, 1, 0)}
local check_for_falling_neighbors = {p(-1, -1, 0), p(1, -1, 0), p(0, -1, -1), p(0, -1, 1), p(0, -1, 0), p(-1, 0, 0), p(1, 0, 0),
	p(0, 0, -1), p(0, 0, 1), p(0, 1, 0)}

local contains = table.contains
local get_node = core.get_node

local CFG = vein_miner.CFG
local sticky_nodes = CFG.sticky_nodes

local function is_sticky_node(name) return sticky_nodes[name] == true end

local cardinal_dirs = {p(1, 0, 0), p(-1, 0, 0), p(0, 1, 0), p(0, -1, 0), p(0, 0, 1), p(0, 0, -1)}
local function get_adjacent_positions(pos)
	local ret = {}
	for _, v in ipairs(cardinal_dirs) do
		insert(ret, pos + v)
	end
	return ret
end

local function is_stuck_to_sticky(pos)
	for _, adj_pos in ipairs(get_adjacent_positions(pos)) do
		local node = get_node(adj_pos)
		if is_sticky_node(node.name) then
			return true
		end
	end
	return false
end

local light_nodes = CFG.LIGHT_NODES

local function is_falling(name)
	local def = core.registered_nodes[name]
	return def and def.groups and def.groups.falling_node
end

local function is_liquid_source(name)
	local def = core.registered_nodes[name]
	return def and def.liquidtype == "source"
end

function BlockDigger.should_dig(node, pos)
	if node.name == "air" then
		return false
	end
	if table.contains(light_nodes, node.name) then
		return true
	end
	if not is_sticky_node(node.name) and is_stuck_to_sticky(pos) then
		return false
	end
	local above = vector.offset(pos, 0, 1, 0)
	local above_node = core.get_node(above)
	if above_node.name == "default:snow" then
		return true -- falling block that we want to fall
	end
	if is_falling(above_node.name) then
		return false
	end
	if false then
		for _, off in ipairs(possible_flow_directions) do
			local npos = pos + off
			if is_liquid_source(core.get_node(npos).name) then
				return false -- digging here may cause liquid to flow
			end
		end
	end
	for _, off in ipairs(check_for_falling_neighbors) do
		local npos = pos + off
		local above_node = core.get_node(npos)
		if is_falling(above_node.name) then
			local below = npos + dir_down
			local below_node = get_node(below)
			if below_node.name == "air" or liquid_set[below_node.name] then
				return false -- this falling node is unsupported
			end
		end
	end
	return true -- safe to mine
end

local log_action = vein_miner.h.log_action
local mod_pos = vein_miner.h.mod_pos
local is_liquid = vein_miner.h.is_liquid
function BlockDigger.dig_node_list(state, node_name, node_list, repeat_count)
	local mined_nodes_count = 0
	if is_liquid(node_name, "water") or is_liquid(node_name, "lava") then
		if true then
			return 0, true
		end
		for index, pos in pairs(node_list) do
			state:fill_liquid_at_pos(pos, utils.handle_pos_notify)
			mined_nodes_count = mined_nodes_count + 1
		end
		if repeat_count <= 2 then
			log_action("done liquid processing for " .. node_name .. " " .. mined_nodes_count .. " nodes")
		end
		return 0
	end
	-- calculate durability per block
	local def = ItemStack(node_name):get_definition()
	local tp = state.wielded:get_tool_capabilities()
	local dp = core.get_dig_params(def.groups, tp)
	if not dp.diggable then
		return 0
	end
	local function dig(pos, node)
		core.node_dig(pos, node, state.player)
		state.wielded:add_wear(dp.wear)
		state.cur_mined_nodes = state.cur_mined_nodes + 1
		mined_nodes_count = mined_nodes_count + 1
	end
	local wear_limit = 65535 - dp.wear
	for index, pos in pairs(node_list) do
		if state.wielded:get_wear() < wear_limit then
			local p = state.prev_pos
			local area_sector = mod_pos(pos, vector.new(16, 16, 16))
			if p then
				if state.cur_mined_nodes >= state.co_cur_max_nodes then
					yield(state.cur_mined_nodes)
					state.co_cur_max_nodes = CFG.MAX_MINED_NODES
					state.mined_nodes = state.mined_nodes + state.cur_mined_nodes
					state.cur_mined_nodes = 0
					state:do_update_pos()
				end
			end
			local node = core.get_node(pos)
			if not BlockDigger.should_dig(node, pos) then
				goto next_node
			end
			local options = utils.get_scan_options(node_name, {})
			if options.light then
				state.pending_light_notify:push_left({
					pos = pos,
					queue_left = state.queue:length(),
				})
				state.found_light_count = state.found_light_count - 1
			end
			if not options.light or l_utils.is_floating(pos, node.name) then
				dig(pos, node)
			end
			if options.light then
				local nat_light = core.get_natural_light(pos, 0.5)
				if nat_light > 5 then
					dig(pos, node)
				end
			end
			do
				local tool = state.player:get_wielded_item()
				if tool:get_wear() ~= state.wielded:get_wear() then
					state.wielded:set_wear(tool:get_wear())
				end
				if state.wielded:get_wear() > 65535 - dp.wear * 3 then
					state.update_wielded_item(state.player, state.wielded)
				end
			end
			state.prev_pos = pos
			state.prev_sector = area_sector
		end
		::next_node::
	end
	return mined_nodes_count
end

return BlockDigger
