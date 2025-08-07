local minetest = minetest
local pcall = pcall
local type = type

p_config = {
  data = {}
}
local storage = minetest.get_mod_storage()

function p_config.save_player_config(name)
  if p_config.data[name] then
    local serialized = minetest.serialize(p_config.data[name])
    storage:set_string("player_config:" .. name, serialized)
  end
end

function p_config.load_player_config(name)
  local data = storage:get_string("player_config:" .. name)
  if data and data ~= "" then
    local ok, result = pcall(minetest.deserialize, data)
    if ok and type(result) == "table" then
      p_config.data[name] = result
    else
      p_config.data[name] = {} -- fallback if corrupted
    end
  else
    p_config.data[name] = {} -- new player
  end
end
