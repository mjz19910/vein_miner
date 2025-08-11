-- player_hud.lua
local pairs = pairs

---@class PlayerHud
local player_hud = {}

-- Store HUD element IDs by player name
---@type table<string, VeinMinerHud>
local hud_data = {}

---@class VeinMinerHud
---@field nodes_mined integer

local function vec_2d(x, y)
	return {
		x = x,
		y = y,
	}
end

local function vec_2d_zero()
	return {
		x = 0,
		y = 0,
	}
end

---@param player Player
function player_hud.init_player(player)
	local name = player:get_player_name()
	if hud_data[name] then
		return
	end -- Already initialized
	hud_data[name] = {}

	local cur_hud = hud_data[name]

	cur_hud.nodes_mined = player:hud_add({
		type = "text",
		position = vec_2d(0, 0.06),
		offset = vec_2d_zero(),
		alignment = vec_2d_zero(),
		scale = vec_2d(1, 1),
		number = 0xFFFFFF,
		z_index = 100,
		text = "Nodes mined: 0",
	})
end

---@param player Player
---@param count number
function player_hud.update_nodes_mined(player, count)
	local name = player:get_player_name()
	local hud = hud_data[name]
	if hud and hud.nodes_mined then
		player:hud_change(hud.nodes_mined, "text", "Nodes mined: " .. count)
	end
end

---@param player Player
function player_hud.remove_player(player)
	local name = player:get_player_name()
	local hud = hud_data[name]
	if hud then
		local p = player
		for _, id in pairs(hud) do
			p:hud_remove(id)
		end
		hud_data[name] = nil
	end
end

return player_hud
