-- utils.lua
utils = {}

local core = core
local utils = utils
local dofile = dofile
local modpath = core.get_modpath("vein_miner")

function utils.load(path) return dofile(modpath .. "/" .. path) end
function utils.require(modpath)
	local relative_path = modpath:gsub("^mods%.vein_miner%.", ""):gsub("%.", "/") .. ".lua"
	return utils.load(relative_path)
end
