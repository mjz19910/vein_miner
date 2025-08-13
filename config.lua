---@type VectorModule
local vector = vector
local table = table
local pairs = pairs
local math = math
---@type VeinMinerGlobal
local vein_miner = vein_miner
local voxel_util = vein_miner.voxel_util
local p = vector.new
local i = table.insert
local ia = table.insert_all

local dirt = {
	"default:dirt",
	dry = "default:dry_dirt",
	grass = {
		"default:dirt_with_grass",
		dry = "default:dry_dirt_with_dry_grass",
		snow = "default:dirt_with_snow",
		rainforest = "default:dirt_with_rainforest_litter",
		coniferous = "default:dirt_with_coniferous_litter",
	},
	permafrost = {
		"default:permafrost",
		moss = "default:permafrost_with_moss",
		stones = "default:permafrost_with_stones",
	},
}

local clay = "default:clay"

local stone = {
	"default:stone",
	ore = {
		coal = "default:stone_with_coal",
		copper = "default:stone_with_copper",
		diamond = "default:stone_with_diamond",
		gold = "default:stone_with_gold",
		iron = "default:stone_with_iron",
		mese = "default:stone_with_mese",
		tin = "default:stone_with_tin",
	},
	desert = "default:desert_stone",
	sandstone = "default:sandstone",
	desert_sandstone = "default:desert_sandstone",
	silver_sandstone = "default:silver_sandstone",
	cave_ice = "default:cave_ice",
}

local sand = {
	"default:sand",
	silver = "default:silver_sand",
	with_kelp = "default:sand_with_kelp",
}

local sandstone = {
	{
		"default:sandstone",
		block = "default:sandstone_block",
		brick = "default:sandstonebrick",
	},
	desert = {
		"default:desert_sandstone",
		block = "default:desert_sandstone_block",
		brick = "default:desert_sandstone_brick",
	},
	silver = {
		"default:silver_sandstone",
		block = "default:silver_sandstone_block",
		brick = "default:silver_sandstone_brick",
	},
}

local gravel = {"default:gravel"}

local grass = {
	{"default:grass_1", "default:grass_2", "default:grass_3", "default:grass_4", "default:grass_5"},
	jungle = {"default:junglegrass"},
	dry = {"default:dry_grass_1", "default:dry_grass_2", "default:dry_grass_3", "default:dry_grass_4", "default:dry_grass_5"},
	marram = {"default:marram_grass_1", "default:marram_grass_2", "default:marram_grass_3", "default:marram_grass_4", "default:marram_grass_5"},
	fern = {"default:fern_1", "default:fern_2", "default:fern_3"},
}

local flower = {
	{"flowers:chrysanthemum_green", "flowers:dandelion_yellow", "flowers:dandelion_white", "flowers:tulip_black", "flowers:tulip",
		"flowers:viola", "flowers:rose"},
	mushroom = {"flowers:mushroom_brown", "flowers:mushroom_red"},
}

local trees = {
	stem = {"default:acacia_bush_stem", "default:pine_bush_stem", "default:bush_stem"},
	trunk = {"default:tree", "default:pine_tree", "default:jungletree", "default:aspen_tree", "default:acacia_tree"},
}

local cobble = {
	"default:cobble",
	mossy = "default:mossycobble",
	stair = "stairs:stair_cobble",
}

local mesecon = {
	wire = {}, -- Will be dynamically generated as in your code
	vertical_wire = {"mesecons_extrawires:vertical_top_on", "mesecons_extrawires:vertical_top_off", "mesecons_extrawires:vertical_on",
		"mesecons_extrawires:vertical_off", "mesecons_extrawires:vertical_bottom_on", "mesecons_extrawires:vertical_bottom_off"},
	sticky_blocks = {"mesecons_stickyblocks:sticky_block_all"},
}

local mese_post_light = {
	"default:mese_post_light",
	pine = "default:mese_post_light_pine_wood",
	acacia = "default:mese_post_light_acacia_wood",
}

local leaves = {
	"default:leaves",
	acacia = "default:acacia_leaves",
	aspen = "default:aspen_leaves",
	jungle = "default:jungleleaves",
	pine = "default:pine_needles",
}
-- ignore_list_default = {leaves[1], leaves.acacia, leaves.aspen, leaves.jungle, leaves.pine, ...}

local blueberry = {
	bush = {
		leaves = "default:blueberry_bush_leaves",
		with_berries = "default:blueberry_bush_leaves_with_berries",
	},
}

local cotton = {
	wild = "farming:cotton_wild",
}

local snow = {"default:snow"}

---@class VeinMinerConfig
local CFG = {}

-- Maximum light scan distance
CFG.light_scan_dist = 1

---@type string[]
local LIGHT_NODES = {mese_post_light.pine, mese_post_light.acacia}
CFG.LIGHT_NODES = LIGHT_NODES
---@type string[]
local target_list = {"default:stone_block", "fire:basic_flame", "default:obsidian", "wool:green", "wool:orange"}
CFG.target_list = target_list
---@type string[]
local ignore_list_default = {leaves[1], leaves.acacia, leaves.aspen, leaves.jungle, leaves.pine, "default:chest"}
---@type string[]
local digtron_parts = {"digtron:axle", "digtron:light", "digtron:pusher", "digtron:digger", "digtron:builder", "digtron:structure",
	"digtron:inventory", "digtron:fuelstore", "digtron:empty_crate", "digtron:auto_controller", "digtron:combined_storage",
	"digtron:inventory_ejector", "digtron:intermittent_digger", "digtron:master_builder", "digtron:controller"}
---@type string[]
local ignored_nodes = {}
table.insert_all(ignored_nodes, ignore_list_default)
table.insert_all(ignored_nodes, digtron_parts)
table.insert_all(ignored_nodes, {"drawers:trim", "drawers:pine_wood1", "drawers:controller"})
CFG.ignored_nodes = ignored_nodes
---@type string[]
local exclusive_nodes = {}
CFG.exclusive_nodes = exclusive_nodes
---@class MiningGroups
local mg = {
	grass = grass[1],
	jungle_grass = grass.jungle,
	dry_grass = grass.dry,
	marram_grass = grass.marram,
	fern = grass.fern,
	blueberry = {blueberry.bush.leaves, blueberry.bush.with_berries},
	gravel = {gravel[1]},
	silver_sand = {sand.silver},
	sand = {sand[1]},
	flower = flower[1],
	mushroom = flower.mushroom,
	stem = trees.stem,
	tree_trunk = trees.trunk,
	dirt = {dirt[1], dirt.permafrost[1]},
	ore = {stone.ore.coal, stone.ore.copper, stone.ore.diamond, stone.ore.gold, stone.ore.iron, stone.ore.mese, stone.ore.tin},
	stone = {stone[1], stone.desert, stone.sandstone, stone.desert_sandstone, stone.silver_sandstone, stone.cave_ice},
	mesecon_wire = mesecon.wire,
	mesecon_vertical_wire = mesecon.vertical_wire,
	misc = {sandstone.silver.brick},
	cobble = {cobble[1]},
	mossy_cobble = {cobble.mossy},
	cobble_stair = {cobble.stair},
	cotton = {cotton.wild},
	clay = {clay},
	surface = {},
	snow = {snow[1]},
}
---@type MiningGroups
CFG.mining_groups = mg
---@type Vector[]
local VEC_DIRS = {}
CFG.VEC_DIRS = VEC_DIRS
---@type Vector[]
local FLOATING_DIRS = {p(1, 0, 0), p(-1, 0, 0), p(0, 1, 0), p(0, -1, 0), p(0, 0, 1), p(0, 0, -1)}
CFG.FLOATING_DIRS = FLOATING_DIRS
---@type string[]
local COLOR_PALETTE = {"#ff0000", "#ff3300", "#ff6600", "#ff3333", "#cc0000", "#cc3333", "#990000", "#990033", "#660000", "#660033",
	"#ff0033", "#ff3366", "#ff6666", "#ff9999", "#ffcccc", "#ff6600", "#ff9900", "#ffcc00", "#ffff00", "#ffcc33", "#ffff33", "#cccc00",
	"#cccc33", "#999900", "#999933", "#ff00ff", "#ff33ff", "#ff66ff", "#ff99ff", "#ff3399", "#ff6699", "#ff99cc", "#ff66cc", "#ff33cc",
	"#cc00cc", "#cc33cc", "#cc66cc", "#cc99cc", "#cc00ff", "#cc33ff", "#cc66ff", "#cc99ff", "#9900cc", "#990099", "#660066", "#00ff00",
	"#33ff00", "#66ff00", "#99ff00", "#ccff00", "#00cc00", "#33cc00", "#66cc00", "#99cc00", "#ccff33", "#00ff33", "#33ff33", "#66ff33",
	"#99ff33", "#00cc33", "#33cc33", "#66cc33", "#99cc33", "#00ffff", "#33ffff", "#66ffff", "#99ffff", "#00cccc", "#33cccc", "#66cccc",
	"#99cccc", "#00ccff", "#33ccff", "#66ccff", "#99ccff", "#0099cc", "#3399cc", "#6699cc", "#00cc99", "#33cc99", "#66cc99", "#99cc99",
	"#00cc66", "#0000ff", "#3333ff", "#6666ff", "#9999ff", "#0000cc", "#3333cc", "#6666cc", "#9999cc", "#000099", "#333399", "#666699",
	"#000066", "#333366", "#666666", "#000033", "#333333", "#3300ff", "#6600ff", "#9900ff", "#cc00ff", "#ff00cc", "#ff33cc", "#ff66cc",
	"#ff99cc", "#cc3399", "#990066", "#660033", "#ffffff", "#cccccc", "#999999", "#666666", "#333333", "#000000"}
CFG.COLOR_PALETTE = COLOR_PALETTE
-- Define which nodes are considered "sticky"
---@class StickyNodes
local sticky_nodes = {
	["mesecons_stickyblocks:sticky_block_all"] = true,
}
CFG.sticky_nodes = sticky_nodes
---@type Vector[]
local cardinal_dirs = {p(1, 0, 0), p(-1, 0, 0), p(0, 1, 0), p(0, -1, 0), p(0, 0, 1), p(0, 0, -1)}
CFG.cardinal_dirs = cardinal_dirs
CFG.MAX_MINED_NODES = 188

---@param radius number
---@return Vector[]
local function gen_euclidean_offsets(radius)
	local dirs = {}
	local r2 = radius * radius
	for x = -math.ceil(radius), math.ceil(radius) do
		for y = -math.ceil(radius), math.ceil(radius) do
			for z = -math.ceil(radius), math.ceil(radius) do
				if not (x == 0 and y == 0 and z == 0) then
					local dist2 = x * x + y * y + z * z
					if dist2 <= r2 then
						dirs[#dirs + 1] = p(x, y, z)
					end
				end
			end
		end
	end
	return dirs
end

table.insert(CFG.VEC_DIRS, p(0, 0, 0))
-- distance limited to 3.1622776601684, ie 3.2
table.insert_all(CFG.VEC_DIRS, gen_euclidean_offsets(64 / 20))

ia(CFG.target_list, {cobble[1], cobble.mossy, cobble.stair})

i(CFG.ignored_nodes, mese_post_light[1])

-- go to the next nodeid (ex.: 01000011 --> 01000100)
local nid_inc = function() end
nid_inc = function(nid)
	local i = 0
	while nid[i - 1] ~= 1 do
		nid[i] = (nid[i] ~= 1) and 1 or 0
		i = i + 1
	end

	-- BUT: Skip impossible nodeids:
	if ((nid[0] == 0 and nid[4] == 1) or (nid[1] == 0 and nid[5] == 1) or (nid[2] == 0 and nid[6] == 1) or (nid[3] == 0 and nid[7] == 1)) then
		return nid_inc(nid)
	end

	return i <= 8
end

local function register_wires_group()
	local nid = {}
	while true do
		-- Create group specification and nodeid string (see note above for details)
		local nodeid = (nid[0] or "0") .. (nid[1] or "0") .. (nid[2] or "0") .. (nid[3] or "0") .. (nid[4] or "0") .. (nid[5] or "0") ..
			               (nid[6] or "0") .. (nid[7] or "0")

		table.insert(mesecon.wire, "mesecons:wire_" .. nodeid .. "_off")
		table.insert(mesecon.wire, "mesecons:wire_" .. nodeid .. "_on")

		if (nid_inc(nid) == false) then
			return
		end
	end
end

register_wires_group()

local mine_only_set = CFG.target_list
i(mine_only_set, "mesecons_powerplant:power_plant")
ia(mine_only_set, {"mesecons_movestones:sticky_movestone_vertical", "mesecons_stickyblocks:sticky_block_all"})
ia(mine_only_set, {"mesecons_movestones:sticky_movestone"})

local coral = {
	brown = "default:coral_brown",
	cyan = "default:coral_cyan",
	green = "default:coral_green",
	orange = "default:coral_orange",
	pink = "default:coral_pink",
}
local coral_skeleton = "default:coral_skeleton"

mg.coral = {coral_skeleton, coral.brown, coral.cyan, coral.green, coral.orange, coral.pink}
---@type table<string, boolean>
local ignored_nodes_set = {}
for k, v in pairs(ignored_nodes) do
	ignored_nodes_set[v] = true
end
CFG.ignored_nodes_set = ignored_nodes_set
---@type table<string, boolean>
local light_nodes_set = {}
for k, v in pairs(CFG.LIGHT_NODES) do
	light_nodes_set[v] = true
end
CFG.light_nodes_set = light_nodes_set
---@type table<string, boolean>
local exclusive_node_set = {}
for k, v in pairs(CFG.exclusive_nodes) do
	exclusive_node_set[v] = true
end
CFG.exclusive_node_set = exclusive_node_set

table.insert_all(mg.surface, {dirt.dry, dirt.grass.dry})
table.insert_all(mg.surface, {dirt.grass[1]})
table.insert_all(mg.surface, {dirt.grass.snow, dirt.grass.rainforest, dirt.grass.coniferous})
table.insert_all(mg.surface, {dirt.permafrost.moss, dirt.permafrost.stones})
table.insert_all(mg.surface, {sand.with_kelp})

local mining_groups = CFG.mining_groups
---@type table<string, boolean>
local target_set = {}
CFG.target_set = target_set
for k, v in pairs(CFG.target_list) do
	target_set[v] = true
end
---@type table<string, string>
local node_to_group = {}
for key, node_name_list in pairs(mining_groups) do
	for idx, node_name in pairs(node_name_list) do
		node_to_group[node_name] = key
		target_set[node_name] = true
	end
end
---@type table<string, string>
CFG.node_to_group = node_to_group

return CFG
