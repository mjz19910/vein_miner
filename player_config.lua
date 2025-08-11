local minetest = minetest
local pcall = pcall
local type = type

---@class PlayerConfigManager
local player_config_mgr = {}
---@type table<string, PlayerConfig>
local per_player_config = {}
player_config_mgr.data = per_player_config
local storage = minetest.get_mod_storage()

---@param player_name string
function player_config_mgr.save_player_config(player_name)
	if player_config_mgr.data[player_name] then
		local serialized = minetest.serialize(player_config_mgr.data[player_name])
		storage:set_string("player_config:" .. player_name, serialized)
	end
end

---@param player_name string
function player_config_mgr.load_player_config(player_name)
	local data = storage:get_string("player_config:" .. player_name)
	if data and data ~= "" then
		local ok
		---@type PlayerConfig
		local result
		ok, result = pcall(minetest.deserialize, data)
		if ok and type(result) == "table" then
			player_config_mgr.data[player_name] = result
		else
			player_config_mgr.data[player_name] = {} -- fallback if corrupted
		end
	else
		player_config_mgr.data[player_name] = {} -- new player
	end
end

return player_config_mgr
