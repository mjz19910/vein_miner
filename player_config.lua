local minetest = minetest
local pcall = pcall
local type = type

---@type PlayerConfigManager
local player_config = {
	data = {},
}
local storage = minetest.get_mod_storage()

function player_config.save_player_config(name)
	if player_config.data[name] then
		local serialized = minetest.serialize(player_config.data[name])
		storage:set_string("player_config:" .. name, serialized)
	end
end

function player_config.load_player_config(name)
	local data = storage:get_string("player_config:" .. name)
	if data and data ~= "" then
		local ok
		---@type PlayerConfig
		local result
		ok, result = pcall(minetest.deserialize, data)
		if ok and type(result) == "table" then
			player_config.data[name] = result
		else
			player_config.data[name] = {} -- fallback if corrupted
		end
	else
		player_config.data[name] = {} -- new player
	end
end

return player_config
