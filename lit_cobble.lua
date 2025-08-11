local core = core
local table = table
---@type VeinMinerGlobal
local vein_miner = vein_miner
local register_node = core.register_node
local insert = table.insert

local CFG = vein_miner.CFG

local mine_only_cur_set = CFG.mine_only_cur_set
local mine_only_group_sets = CFG.mine_only_group_sets
local mine_only_groups = CFG.MINE_ONLY_GROUPS

local function node_sound_defaults(tbl)
	tbl = tbl or {}
	tbl.footstep = tbl.footstep or {
		name = "",
		gain = 1.0,
	}
	tbl.dug = tbl.dug or {
		name = "default_dug_node",
		gain = 0.25,
	}
	tbl.place = tbl.place or {
		name = "default_place_node_hard",
		gain = 1.0,
	}
	return tbl
end

local function node_sound_stone_defaults(tbl)
	tbl = tbl or {}
	tbl.footstep = tbl.footstep or {
		name = "default_hard_footstep",
		gain = 0.2,
	}
	tbl.dug = tbl.dug or {
		name = "default_hard_footstep",
		gain = 1.0,
	}
	node_sound_defaults(tbl)
	return tbl
end

local function register_lit_cobble(light_level)
	local node_name = "vein_miner:lit_cobble_" .. light_level
	register_node(node_name, {
		description = ("Lit Cobblestone (Level=%d)"):format(light_level),
		tiles = {"default_cobble.png"},
		groups = {
			cracky = 3,
			stone = 2,
		},
		light_source = light_level,
		drop = node_name,
		sounds = node_sound_stone_defaults(),
	})

	insert(mine_only_groups.lit_cobble, node_name)
	mine_only_group_sets[node_name] = "lit_cobble"
	mine_only_cur_set[node_name] = true
end

mine_only_groups.lit_cobble = {}

for i = 1, 14 do
	register_lit_cobble(i)
end

core.register_craft({
	type = "shapeless",
	output = "vein_miner:lit_cobble_1",
	recipe = {"default:cobble", "default:mese_crystal_fragment"},
})

core.register_craft({
	type = "shapeless",
	output = "default:cobble 2",
	recipe = {"default:cobble", "vein_miner:lit_cobble_1"},
	replacements = {{"vein_miner:lit_cobble_1", "default:mese_crystal_fragment"}},
})

core.register_craft({
	type = "shapeless",
	output = "vein_miner:lit_cobble_1",
	recipe = {"default:cobble", "vein_miner:lit_cobble_2"},
	replacements = {{"default:cobble", "default:cobble"}},
})

core.register_craft({
	type = "shapeless",
	output = "vein_miner:lit_cobble_2 2",
	recipe = {"vein_miner:lit_cobble_1", "vein_miner:lit_cobble_1"},
})

core.register_craft({
	output = "vein_miner:lit_cobble_2",
	recipe = {{"vein_miner:lit_cobble_1"}},
})
