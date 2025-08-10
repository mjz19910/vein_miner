local dofile = dofile

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
	core.log("warning", "[vein_miner:print] " .. msg)
end

return require
