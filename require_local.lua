local dofile = dofile
---@type CoreModApi
local core = core

local modpath = core.get_modpath("vein_miner")

local function load(path) return dofile(modpath .. "/" .. path) end

local function require(modpath)
	local relative_path = modpath:gsub("^mods%.vein_miner%.", ""):gsub("%.", "/") .. ".lua"
	return load(relative_path)
end

print = function(...)
	local args = {...}
	local parts = {}
	for i, v in ipairs(args) do
		parts[#parts + 1] = tostring(v)
	end
	local msg = table.concat(parts, " ")
	core.log("warning", ("[%s:print] %s"):format(core.get_last_run_mod(), msg))
end

return require
