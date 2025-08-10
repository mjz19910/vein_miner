local minetest = minetest
local pcall = pcall
local type = type
local player_config = {
	---@type table<string, PlayerConfig>
  data = {}
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
    local ok, result = pcall(minetest.deserialize, data)
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

---@class PlayerConfig
---@field miny number
---@field maxy number
---@field last_maxy number|nil
---@
