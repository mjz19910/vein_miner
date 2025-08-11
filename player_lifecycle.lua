local core = core
---@type VeinMinerGlobal
local vein_miner = vein_miner
local player_config_mgr = vein_miner.player_config_mgr
local player_hud = vein_miner.player_hud

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	player_config_mgr.load_player_config(name)
	local config = player_config_mgr.data[name]

	if config.maxy == nil then
		config.maxy = 144
	end
	if config.target_layer ~= nil then
		config.maxy = config.target_layer * 8 + 7
		config.target_layer = nil
	end
	if config.miny == nil then
		config.miny = -144
	end
	if config.mode == nil then
		config.mode = "small" -- default: "small"
	end
	if config.blocks_per_tick == nil then
		config.blocks_per_tick = 1 -- default: 1
	end

	vein_miner.scanner.light_scan_data[name] = {}
	vein_miner.light_region_debug[name] = true

	-- Init the player hud
	player_hud.init_player(player)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	player_config_mgr.save_player_config(name)

	player_hud.remove_player(player)
end)
