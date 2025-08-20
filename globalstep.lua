local assert = assert
local pairs = pairs
local ipairs = ipairs
---@type CoreModApi
local core = core
---@type VeinMinerGlobal
local vein_miner = vein_miner
local aabb = vein_miner.aabb
local draw_region = aabb.draw

local hash_pos = core.hash_node_position
local get_player_by_name = core.get_player_by_name
local dtime_time = 0
local dtime_acc = 0
local dtime_next_falling_check = 0
local falling_check_delay = 1.25

local falling_delay_state = vein_miner.falling_delay_state
assert(falling_delay_state, "missing falling_delay_state")
local falling_delay_list = falling_delay_state.delayed_list
local falling_delayed_set = falling_delay_state.delayed_set
assert(falling_delay_list and falling_delayed_set, "need falling_delay_list info")
local check_for_falling = falling_delay_state.check_for_falling
assert(check_for_falling, "need original core.check_for_falling")
local light_scan_data = vein_miner.scanner.light_scan_data
assert(light_scan_data, "need light_scan_data")
local player_config_mgr = vein_miner.player_config_mgr
assert(player_config_mgr, "need player_config_mgr")

core.register_globalstep(function(dtime)
	dtime_acc = dtime_acc + dtime
	if dtime_acc > falling_delay_state.last_falling_node + falling_check_delay and #falling_delay_list > 0 then
		for i = 1, #falling_delay_list do
			local pos = falling_delay_list[i]
			local h = hash_pos(pos)
			falling_delay_list[i] = nil
			falling_delayed_set[h] = nil
			check_for_falling(pos)
		end
	end
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if player_config_mgr:is_light_debug_enabled(name) then
			local regions = light_scan_data[name]
			if dtime_time > 4 then
				for _, r in ipairs(regions) do r:draw() end
				dtime_time = 0
			end
		end
	end
	dtime_time = dtime_time + dtime
	falling_delay_state.current_tick_time = dtime_acc
end)
