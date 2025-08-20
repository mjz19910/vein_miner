local minetest = minetest
local pcall = pcall
local type = type

---@class PlayerConfigManager
---@field data table<string, PlayerConfig>
local player_config_mgr = {
	data = {},
}

local storage = minetest.get_mod_storage()

---@param self PlayerConfigManager
---@param name string
function player_config_mgr:save(name)
	if self.data[name] then
		local serialized = minetest.serialize(self.data[name])
		storage:set_string("player_config:" .. name, serialized)
	end
end

---@param self PlayerConfigManager
---@param name string
function player_config_mgr:load(name)
	local data = storage:get_string("player_config:" .. name)
	if data and data ~= "" then
		local ok
		---@type PlayerConfig
		local result
		ok, result = pcall(minetest.deserialize, data)
		if ok and type(result) == "table" then
			self.data[name] = result
		else
			self.data[name] = {} -- fallback if corrupted
		end
	else
		self.data[name] = {} -- new player
	end
end

---@param self PlayerConfigManager
---@param name string
function player_config_mgr:load_defaults(name)
	self:load(name)
	local config = self.data[name]
	if config.miny == nil then config.miny = -144 end
	if config.maxy == nil then config.maxy = 144 end
	if config.mode == nil then config.mode = "small" end
	if config.blocks_per_tick == nil then config.blocks_per_tick = 4 end
	if config.light_debug == nil then config.light_debug = true end
end

--- Get a player's config
---@param self PlayerConfigManager
---@param name string
---@return PlayerConfig
function player_config_mgr:get(name)
	local config = self.data[name]
	if not config then error("config not loaded for " .. name) end
	return config
end

--- Returns whether light debug is enabled for a player.
---@param self PlayerConfigManager
---@param name string
---@return boolean
function player_config_mgr:is_light_debug_enabled(name) return self:get(name).light_debug end

--- Sets the light debug flag and saves immediately.
---@param self PlayerConfigManager
---@param name string
---@param enabled boolean
function player_config_mgr:set_light_debug(name, enabled)
	self:get(name).light_debug = enabled
	self:save(name)
end

---@param self PlayerConfigManager
---@param name string
function player_config_mgr:get_floor_place_limit(name) return self:get(name).floor_place_limit end

--- Set the floor placement limit and save.
---@param self PlayerConfigManager
---@param name string
---@param limit integer
function player_config_mgr:set_floor_place_limit(name, limit)
	self:get(name).floor_place_limit = limit
	self:save(name)
end

return player_config_mgr
