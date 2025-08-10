local dofile = dofile

local modpath = core.get_modpath("vein_miner")

local function load(path) return dofile(modpath .. "/" .. path) end

local function require(modpath)
	local relative_path = modpath:gsub("^mods%.vein_miner%.", ""):gsub("%.", "/") .. ".lua"
	return load(relative_path)
end

return require
