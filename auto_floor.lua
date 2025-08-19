local require = require
---@type LuantiCore
local core = core
---@type VectorModule
local ipairs = ipairs
local get_connected_players = core.get_connected_players
---@type FloorFiller
local floor_filler = require("mods.vein_miner.floor_filler")
---@type table<string, FloorScanState>
local scan_state_map = {}
core.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	scan_state_map[player_name] = floor_filler.new(player)
end)
core.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	scan_state_map[player_name] = nil
end)
-- globalstep for vein_miner:auto_floor tool
core.register_globalstep(function(dtime)
	core.is_async = true

	for _, player in ipairs(get_connected_players()) do
		local plr_name = player:get_player_name()
		scan_state_map[plr_name]:run()
	end

	core.is_async = nil
end)

core.register_tool("vein_miner:auto_floor", {
	description = "Auto-Floor Builder",
	inventory_image = "default_wood.png",
})
core.register_craft({
	output = "vein_miner:auto_floor",
	recipe = {{"default:stick", "", "default:stick"}, {"", "default:cobble", ""}, {"", "default:mese_crystal_fragment", ""}},
})
