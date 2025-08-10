local pairs = pairs
local ipairs = ipairs
local vein_miner = vein_miner
local draw_region = aabb.draw

local hash_pos = core.hash_node_position
local get_player_by_name = core.get_player_by_name
local dtime_time = 0
local dtime_acc = 0
local dtime_next_falling_check = 0
local falling_check_delay = 0.5

local light_region_debug = vein_miner.light_region_debug
local falling_nodes = vein_miner.falling_nodes
local falling_nodes_set = vein_miner.falling_nodes_set
local check_for_falling = vein_miner.check_for_falling
local light_scan_data = vein_miner.light_scan_data
assert(light_region_debug, "need light region debug")
assert(falling_nodes and falling_nodes_set, "need falling_nodes info")
assert(check_for_falling, "need original core.check_for_falling")
assert(light_scan_data, "need light_scan_data")

core.register_globalstep(function(dtime)
	dtime_acc = dtime_acc + dtime
	if dtime_acc > dtime_next_falling_check and #falling_nodes > 0 then
		for i = 1, #falling_nodes do
			local pos = falling_nodes[i]
			falling_nodes[i] = nil
			local h = hash_pos(pos)
			falling_nodes_set[h] = nil
			check_for_falling(pos)
		end
		dtime_next_falling_check = dtime_acc + falling_check_delay
	end
	for name, enabled in pairs(light_region_debug) do
		local player = get_player_by_name(name)
		if enabled and player then
			local regions = light_scan_data[name]
			if dtime_time > 4 then
				for _, r in ipairs(regions) do
					draw_region(r)
				end
				dtime_time = 0
			end
		end
	end
	dtime_time = dtime_time + dtime
	vein_miner.current_tick_time = dtime_acc
end)
