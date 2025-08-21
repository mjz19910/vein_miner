---@type CoreModApi
local core = core
---@type VeinMinerGlobal
local vein_miner = vein_miner

---@type PlayerConfigManager
local player_config_mgr = vein_miner.player_config_mgr

core.register_chatcommand("freeze_mapgen", {
	params = "",
	description = "Disable mapgen around you",
	func = function(name)
		local player = core.get_player_by_name(name)
		player:set_mapgen_disabled(true)
		player_config_mgr:persist_mapgen_disabled(name, true)
		return true, "Mapgen disabled for you."
	end,
})

core.register_chatcommand("resume_mapgen", {
	params = "",
	description = "Enable mapgen around you",
	func = function(name)
		local player = core.get_player_by_name(name)
		player:set_mapgen_disabled(false)
		player_config_mgr:persist_mapgen_disabled(name, false)
		return true, "Mapgen enabled for you."
	end,
})
