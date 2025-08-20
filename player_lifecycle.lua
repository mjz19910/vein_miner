---@type CoreModApi
local core = core
---@type VeinMinerGlobal
local vein_miner = vein_miner
local player_config_mgr = vein_miner.player_config_mgr
local player_hud = vein_miner.player_hud

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()

	player_config_mgr:load_defaults(name)
	vein_miner.scanner.light_scan_data[name] = {}
	player_hud.init_player(player)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	player_config_mgr.save(name)
	player_hud.remove_player(player)
end)
