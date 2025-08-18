local require = require
local print = print
local setmetatable = setmetatable
local tostring = tostring
local type = type
---@type LuantiCore
local core = core

local assert = assert
---@type VectorModule
local vector = vector
local ipairs = ipairs
local pairs = pairs
local table = table
local math = math
---@type VeinMinerGlobal
local vein_miner = vein_miner

-- localize math
local round = vector.round
local offset = vector.offset
local normalize = vector.normalize
local multiply = vector.multiply
local new_vec = vector.new

local set_node = core.set_node
local get_node = core.get_node
local get_node_or_nil = core.get_node_or_nil
local sound_play = core.sound_play
local get_connected_players = core.get_connected_players

local registered_nodes = core.registered_nodes

local player_config_mgr = vein_miner.player_config_mgr
assert(player_config_mgr, "need vein_miner.player_config_mgr")

core.register_tool("vein_miner:auto_floor", {
	description = "Auto-Floor Builder",
	inventory_image = "default_wood.png",
})

---@type FloorFiller
local floor_filler = require("mods.vein_miner.floor_filler")

---@type table<string, FloorScanState>
local scan_state_map = {}

core.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	scan_state_map[player_name] = floor_filler.new(player)
end)

core.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	scan_state_map[player_name] = nil
end)

-- globalstep for vein_miner:auto_floor tool
core.register_globalstep(function(dtime)
	core.is_async = true

	for _, player in ipairs(get_connected_players()) do
		local plr_name = player:get_player_name()
		scan_state_map[plr_name]:run()
	end

	core.is_async = nil
end)

local auto_floor_recipe = {{"default:stick", "", "default:stick"}, {"", "default:cobble", ""}, {"", "default:mese_crystal_fragment", ""}};

core.register_craft({
	output = "vein_miner:auto_floor",
	recipe = auto_floor_recipe,
})
