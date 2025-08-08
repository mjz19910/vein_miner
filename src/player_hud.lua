-- player_hud.lua
local player_hud = {}

-- Store HUD element IDs by player name
local hud_data = {}

function player_hud.init_player(player)
	local name = player:get_player_name()
	if hud_data[name] then
		return
	end -- Already initialized

	hud_data[name] = {
		nodes_mined = player:hud_add({
			type = "text",
			position = {
				x = 0.5,
				y = 0.07
			},
			offset = {
				x = 0,
				y = 0
			},
			text = "Nodes mined: 0",
			alignment = {
				x = 0,
				y = 0
			},
			scale = {
				x = 1,
				y = 1
			},
			number = 0xFFFFFF,
			z_index = 100
		})
	}
end

function player_hud.update_nodes_mined(player, count)
	local name = player:get_player_name()
	local hud = hud_data[name]
	if hud and hud.nodes_mined then
		player:hud_change(hud.nodes_mined, "text", "Nodes mined: " .. tostring(count))
	end
end

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
