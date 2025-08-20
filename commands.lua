local assert = assert
local string = string
local math = math
local tonumber = tonumber
---@type CoreModApi
local core = core
---@type VeinMinerGlobal
local vein_miner = vein_miner

local player_config_mgr = vein_miner.player_config_mgr

core.register_chatcommand("toggle_light_debug", {
	description = "Toggle debug view for light scan regions",
	func = function(name)
		local new_value = not player_config_mgr:is_light_debug_enabled(name)
		player_config_mgr:set_light_debug(name, new_value)

		if new_value then
			return true, "Light region debug ON"
		else
			return true, "Light region debug OFF"
		end
	end,
})

core.register_chatcommand("pos", {
	description = "Show your position with 3 decimal places",
	privs = {},
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then return false, "Player not found." end

		local pos = player:get_pos()
		local msg = string.format("Your position is: (%.3f, %.3f, %.3f)", pos.x, pos.y, pos.z)
		return true, msg
	end,
})

core.register_chatcommand("yaw", {
	description = "Change player yaw",
	params = "[get | set <yaw> | add <yaw>]",
	privs = {},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return false, "Player not found." end

		local args = param:split(" ")
		local cmd = args[1]
		if cmd == "get" or cmd == nil or cmd == "" then
			local yaw = player:get_look_horizontal()
			return true, ("Your current yaw is %.1f degrees"):format(math.deg(yaw))
		elseif cmd == "set" then
			local yaw = 0
			if args[2] ~= nil then yaw = math.rad(tonumber(args[2])) end
			player:set_look_horizontal(yaw)
			return true, ("Yaw set to %.1f degrees"):format(math.deg(yaw))
		elseif cmd == "add" then
			local yaw_change = 0
			if args[2] ~= nil then yaw_change = tonumber(args[2]) end
			local yaw = player:get_look_horizontal()
			if yaw_change ~= 0 then
				yaw = math.rad(math.deg(yaw) + yaw_change)
				player:set_look_horizontal(yaw)
				return true, ("Yaw changed by %.1f degrees to %.1f degrees"):format(yaw_change, math.deg(yaw))
			end
			return true, ("Your current yaw, %.1f degrees, did not change"):format(math.deg(yaw))
		end
	end,
})

local show_layer_bounds = vein_miner.show_layer_bounds
assert(show_layer_bounds, "need show_layer_bounds")

core.register_chatcommand("mine", {
	description = "Change configured mining layer",
	params = "[get [min|max] | set [min|max <y>] | up [min|max|both] | down [min|max|both] | reset]",
	privs = {},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return false, "Player not found." end

		---@type PlayerConfig
		local config = player_config_mgr.data[name]

		-- Initialize defaults if missing
		if config.miny == nil then config.miny = -128 end
		if config.maxy == nil then config.maxy = 128 end

		local args = param:split(" ")
		local cmd = args[1]
		local sub = args[2]
		local val = tonumber(args[3])

		local miny, maxy = config.miny, config.maxy

		if cmd == "get" or cmd == nil or cmd == "" then
			if sub == "min" then
				return true, "Minimum mining Y: y=" .. miny .. " (layer ≥ " .. math.floor(miny / 8) .. ")"
			elseif sub == "max" then
				return true, "Maximum mining Y: y=" .. maxy .. " (layer ≤ " .. math.floor(maxy / 8) .. ")"
			else
				return true, "Current mining bounds: " .. show_layer_bounds(miny, maxy)
			end
		elseif cmd == "set" then
			if sub == "min" and val then
				val = math.floor(val)
				if val > maxy then return false, "miny cannot be greater than maxy (" .. maxy .. ")" end
				config.miny = val
				return true, "Minimum mining Y set to y=" .. val
			elseif sub == "max" and val then
				val = math.floor(val)
				if val < miny then return false, "maxy cannot be less than miny (" .. miny .. ")" end
				config.maxy = val
				return true, "Maximum mining Y set to y=" .. val
			elseif sub == nil then
				local view_y = player:get_pos().y + 1.6
				local new_miny = math.floor((view_y - 16) / 8) * 8
				local new_maxy = math.floor((view_y + 48) / 8) * 8
				config.miny = new_miny
				config.maxy = new_maxy
				return true, "Mining range set from view: " .. show_layer_bounds(new_miny, new_maxy)
			else
				return false, "Usage: /mine set [min|max <y>]"
			end
		elseif cmd == "up" then
			if sub == "min" then
				config.miny = config.miny + 8
				return true, "Minimum mining Y increased to y=" .. config.miny
			elseif sub == "max" then
				config.maxy = config.maxy + 8
				return true, "Maximum mining Y increased to y=" .. config.maxy
			elseif sub == "both" or sub == nil then
				config.miny = config.miny + 8
				config.maxy = config.maxy + 8
				return true, "Mining range increased: " .. show_layer_bounds(config.miny, config.maxy)
			else
				return false, "Usage: /mine up [min|max|both]"
			end
		elseif cmd == "down" then
			if sub == "min" then
				if config.miny - 8 > config.maxy then return false, "miny cannot exceed maxy" end
				config.miny = config.miny - 8
				return true, "Minimum mining Y decreased to y=" .. config.miny
			elseif sub == "max" then
				if config.maxy - 8 < config.miny then return false, "maxy cannot be less than miny" end
				config.maxy = config.maxy - 8
				return true, "Maximum mining Y decreased to y=" .. config.maxy
			elseif sub == "both" or sub == nil then
				if config.miny - 8 > config.maxy - 8 then return false, "Range collapse: miny would exceed maxy" end
				config.miny = config.miny - 8
				config.maxy = config.maxy - 8
				return true, "Mining range decreased: " .. show_layer_bounds(config.miny, config.maxy)
			else
				return false, "Usage: /mine down [min|max|both]"
			end
		elseif cmd == "reset" then
			vein_miner.scanner.light_scan_reset(name)
			return false, "Light scan data reset"
		else
			return false, "Usage: /mine [get [min|max] | set [min|max <y>] | up [min|max|both] | down [min|max|both] | reset]"
		end
	end,
})

core.register_privilege("vein_miner_config", {
	description = "Can configure vein miner",
	give_to_singleplayer = false,
})

core.register_chatcommand("mining_mode", {
	description = "Change configured mining range (8 or 32 at y > -32)",
	params = "[small|large]",
	privs = {
		vein_miner_config = true,
	},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then return false, "Player not found." end

		param = param:lower()
		if player_config_mgr.data[name] == nil then player_config_mgr.data[name] = {} end

		local config = player_config_mgr.data[name]

		if param == "" or param == nil then
			return true, "Mining mode is " .. config.mode .. " range."
		elseif param == "small" then
			config.mode = "small"
			return true, "Mining mode set to small range."
		elseif param == "large" then
			config.mode = "large"
			return true, "Mining mode set to large range."
		else
			return false, "Invalid parameter. Use: /mining_mode small OR /mining_mode large"
		end
	end,
})

minetest.register_chatcommand("vm_set_blocks_per_tick", {
	params = "<count>",
	description = "Set how many blocks vein miner places per tick",
	func = function(name, param)
		local count = tonumber(param)
		if not count or count < 1 then return false, "Invalid number" end
		local cfg = player_config_mgr.data[name]
		cfg.blocks_per_tick = count

		player_config_mgr:save(name)
		return true, "Blocks per tick set to " .. count
	end,
})
