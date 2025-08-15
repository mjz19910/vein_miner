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
---@type VeinMinerGlobal
local vein_miner = vein_miner
---@type VectorModule
local vector = vector
---@type LuantiCore
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

---@type VeinMinerConfig
local CFG = vein_miner.CFG
local sticky_nodes = CFG.sticky_nodes

local function is_sticky_node(name) return sticky_nodes[name] == true end

local cardinal_dirs = vein_miner.CFG.cardinal_dirs
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

local light_nodes_set = CFG.light_nodes_set

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
	if light_nodes_set[node.name] then
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
	if node.name == "default:snow" and above_node.name == "air" then
		return true
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
local h = vein_miner.h
local log_action = h.log_action
local mod_pos = h.mod_pos
local is_liquid = h.is_liquid
local fill_liquid_at_pos = vein_miner.fill_liquid_at_pos
local yneg = vector.new(0, -1, 0)
local jt = "default:jungletree"
local def_tree = "default:tree"
local pine = "default:pine_tree"
local aspen = "default:aspen_tree"
local acacia = "default:acacia_tree"
local cobble = "default:cobble"
local sand = "default:sand"
local mg_tree_trunk = {
	[jt] = true,
	[aspen] = true,
	[def_tree] = true,
	[acacia] = true,
	[pine] = true,
	[cobble] = true,
	[sand] = true,
}

---@param pos Vector
---@param oldnode MapNode
---@param player Player
---@param skip_pos table<integer, boolean>
local function place_log_over_dirt(pos, oldnode, player, skip_pos)
	-- The dirt is below the dug node
	local under_pos = pos + yneg
	local under_node = core.get_node_or_nil(under_pos)

	if not under_node then
		return
	end

	local under_name = under_node.name

	-- Check if the uncovered node is dirt or dry_dirt
	if under_name == "default:dirt" or under_name == "default:dry_dirt" then
		local inv = player:get_inventory()
		-- Try to find a block in main inventory
		for i = 1, inv:get_size("main") do
			local stack = inv:get_stack("main", i)
			local name = stack:get_name()
			if mg_tree_trunk[name] then
				local node = core.get_node_or_nil(pos)
				if node and node.name == "air" then
					if oldnode.name == name then
						return
					end
					skip_pos[core.hash_node_position(pos)] = true
					core.set_node(pos, {
						name = name,
					})
					core.check_for_falling(pos)
					stack:take_item(1)
					inv:set_stack("main", i, stack)
				end
				break
			end
		end
	end
end

--- place_log_over_dirt(pos, oldnode, state.player, state.skip_pos)
---@param state VeinMinerState
---@param pos Vector
---@param oldnode MapNode
function BlockDigger.notify_dig(state, pos, oldnode) end

---@param state VeinMinerState
---@param node_name string
---@param node_list MapNode[]
function BlockDigger.dig_node_list(state, node_name, node_list, repeat_count)
	local player = state.player
	local skip_pos = state.skip_pos
	local mined_nodes_count = 0
	if is_liquid(node_name, "water") or is_liquid(node_name, "lava") then
		if true then
			return 0, true
		end
		for index, pos in pairs(node_list) do
			fill_liquid_at_pos(pos, l_utils.handle_pos_notify)
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
		core.node_dig(pos, node, player)
		state.wielded:add_wear(dp.wear)
		state.cur_mined_nodes = state.cur_mined_nodes + 1
		mined_nodes_count = mined_nodes_count + 1

		BlockDigger.notify_dig(state, pos, node)
	end
	local wear_limit = 65535 - dp.wear
	for index, pos in pairs(node_list) do
		if state.skip_pos[core.hash_node_position(pos)] then
			goto next_node
		end
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
			local options = l_utils.get_scan_options(node_name, {})
			if options.light then
				state.pending_light_notify:push_left({
					pos = pos,
					queue_left = state.queue:length(),
				})
				state.found_light_count = state.found_light_count - 1
			end
			if not options.light or l_utils.is_floating(pos, node.name) then
				dig(pos, node)
				goto done
			end
			if options.light then
				do
					dig(pos, node)
					goto done
				end
				local nat_light = core.get_natural_light(vector.offset(pos, 0, -1, 0), 0.5)
				if nat_light ~= nil and nat_light > 5 then
					dig(pos, node)
					goto done
				end
				nat_light = core.get_natural_light(vector.offset(pos, 0, 1, 0), 0.5)
				if nat_light ~= nil and nat_light > 5 then
					dig(pos, node)
					goto done
				end
				nat_light = core.get_natural_light(pos, 0.5)
				if nat_light ~= nil and nat_light > 5 then
					dig(pos, node)
					goto done
				end
			end
			::done::
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
