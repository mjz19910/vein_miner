core.register_chatcommand("pos", {
	description = "Show your position with 3 decimal places",
	privs = {},
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		local pos = player:get_pos()
		local msg = string.format("Your position is: (%.3f, %.3f, %.3f)", pos.x, pos.y, pos.z)
		return true, msg
	end,
})

core.register_chatcommand("yaw", {
	description = "Change player yaw",
	params = "[get | set <yaw>]",
	privs = {},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		local args = param:split(" ")
		local cmd = args[1]
		if cmd == "get" or cmd == nil or cmd == "" then
			local yaw = player:get_look_horizontal()
			return true, ("Your current yaw is %.1f degrees"):format(math.deg(yaw))
		elseif cmd == "set" then
			local yaw = 0
			if args[2] ~= nil then
				yaw = math.rad(tonumber(args[2]))
			end
			player:set_look_horizontal(yaw)
			return true, ("Yaw set to %.1f degrees"):format(math.deg(yaw))
		end
	end,
})
