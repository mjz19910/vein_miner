function table.contains(table, element) end
function vector.midpoint(a, b) end

core.check_for_falling = function(pos) end

function vein_miner.state.new(pos, player, player_name, wielded) end

local sticky_nodes = CFG.sticky_nodes

local function is_falling(name) end
local function is_liquid_source(name) end
local function is_sticky_node(name) return sticky_nodes[name] == true end

local function is_stuck_to_sticky(pos) end

local BlockDigger = {}
function BlockDigger.should_dig(node, pos) end

local light_scan_data = {}
local function light_scan_reset(name) light_scan_data[name] = {} end
-- Define which nodes are considered "sticky"
local function get_adjacent_positions(pos) end
local function is_node_vein_diggable(nodeName, wieldedName) end
local function update_wielded_item(player, wielded) end
local function handle_unexpected_target_nodes(target_nodes, node_name) end
local function get_real_scan_options(node_name, options) end
local function get_scan_options(node_name, options) end
local function fmt_layer(layer) return "y=" .. (layer * 8) .. ".." .. (layer * 8 + 7) end
local function is_valid_pos_to_iter(pos, player_name) end
local function add_pos_to_queue(state, node_name, pos, options) end
local function filter_liquid(state, pos)
	local function push(x, y, z) end
	local function maybe_enqueue(x, y, z) end
	local function expand_axis(minp, maxp, axis, limit, skip_flag) local function axis_iter(start, is_max) end end
	local function loop_expand() local function notify_limit(pos) end end
end
local function can_player_fit(pos) end
local function check_pos(pos) end
local function on_found_empty_space(dir) end
local function on_light_source(pos) end
local function async_wait(time) end
local function mark_near_light(state, node_name, pos) end
local function count_found_nodes(iter, orig_pos, player_name) end
local function notify_pos(pos, color, size, expire_time) end
local function wait_for_player_near_pos(player, target_pos) end
local function scan_nearby_region(state, r1, offset_vec, offset_str, pos, node_name) end
local function scan_region_for_node(state, regions, r, pos, node_name, user_action, show_log) end
local function place_mese_particle(pos, size) end
local function place_particle(pos, size, texture) end
local function clamp_max(vmin, vmax, step) end
local function linspace_inclusive(vmin, vmax, step)
	-- Returns a list starting at vmin and ending at vmax, with intervals ≤ step
end
local function linspace_side(start_pos, end_pos, step)
	-- Generate points from start_pos to end_pos inclusive, stepping by step
end
local function linspace_centered(vmin, vmax, center, step) end
local function find_closest_index(arr, value) end
function aabb.draw(r)
	local function place_ston_particle(pos) place_particle(pos, 6 / 3, "default_stone.png") end
	local function place_mese_particle_local(pos) place_mese_particle(pos, 6 / 3) end
	local function place_diamond_block_particle(pos) place_particle(pos, 6 / 3, "default_diamond_block.png") end
	local function place_stone_block_particle(pos) place_particle(pos, 6 / 3, "default_stone_block.png") end
end
local function scan_nearby_lights(state, pos, node_name, options, show_log)
	local player_name = state.player_name
	local regions = light_scan_data[player_name]
	local function base_scan(r, user_action) scan_region_for_node(state, regions, r, pos, node_name, user_action, show_log) end
	local function full_scan(r) base_scan(r, true) end
	local function normal_scan(r) base_scan(r, false) end
end
local function add_light_to_teleport_queue(state, v) end
local function do_update_pos(state) end
local function has_empty_main_inv_slot(player) end
local function is_floating(pos, expected_name) end
local function process_node_group(state, node_name, node, repeat_count) end
local function iter_node_groups(state, iter_nodes) end
local function notify_missing_light(pos, attach_dir, expire_time) end
local function dig_pos_process_queue_item(state, item, player_name) end
local function dig_pos(state) end
local function dig_finish(state) end
local function after_delay(data, fn, state) end
local function after_co_start(state, co, async_step_fn, status, action_count) end
local function resume_coroutine(state, co, async_step_fn) end
local function vein_miner_step(state) end
local function show_layer_bounds(miny, maxy) end
local function node_sound_defaults(tbl) end
local function node_sound_stone_defaults(tbl) end
local function register_lit_cobble(light_level) end

core.register_on_mods_loaded(function() end)
core.register_on_dignode(function(pos, oldnode, player) end)
core.register_on_joinplayer(function(player) end)
core.register_on_leaveplayer(function(player) end)
core.register_globalstep(function(dtime) end)
