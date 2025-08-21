---@type CoreModApi
local core = core

core.register_chatcommand("freeze_mapgen", {
	params = "",
	description = "Disable mapgen around you",
	func = function(name)
		local player = core.get_player_by_name(name)
		player:set_mapgen_disabled(true)
		return true, "Mapgen disabled for you."
	end,
})

core.register_chatcommand("resume_mapgen", {
	params = "",
	description = "Enable mapgen around you",
	func = function(name)
		local player = core.get_player_by_name(name)
		player:set_mapgen_disabled(false)
		return true, "Mapgen enabled for you."
	end,
})
