local vector = vector
local table = table
local p = vector.new
local i = table.insert
local ia = table.insert_all

vein_miner.CFG = {
	LIGHT_NODES = {"default:mese_post_light_pine_wood", "default:mese_post_light_acacia_wood"},
	MINE_ONLY_CUR_SET = {"default:clay", "default:snow", "default:dry_dirt", "default:stone_block", "farming:cotton_wild", "fire:basic_flame",
		"default:obsidian", "wool:green", "wool:orange"},
	IGNORED_NODES = {"default:chest", "default:leaves", "drawers:trim", "drawers:pine_wood1", "drawers:controller", "digtron:axle",
		"digtron:light", "digtron:pusher", "digtron:digger", "digtron:builder", "digtron:structure", "digtron:inventory", "digtron:fuelstore",
		"digtron:empty_crate", "digtron:auto_controller", "digtron:combined_storage", "digtron:inventory_ejector", "digtron:intermittent_digger",
		"digtron:master_builder", "digtron:controller"},
	SURFACE_NODES = {"default:dirt_with_grass", "default:dirt_with_snow", "default:dirt_with_rainforest_litter",
		"default:dirt_with_coniferous_litter", "default:dry_dirt_with_dry_grass", "default:permafrost_with_moss",
		"default:permafrost_with_stones", "default:sand_with_kelp"},
	MINE_ONLY_GROUPS = {
		grass = {"default:grass_1", "default:grass_2", "default:grass_3", "default:grass_4", "default:grass_5"},
		jungle_grass = {"default:junglegrass"},
		dry_grass = {"default:dry_grass_1", "default:dry_grass_2", "default:dry_grass_3", "default:dry_grass_4", "default:dry_grass_5"},
		marram_grass = {"default:marram_grass_1", "default:marram_grass_2", "default:marram_grass_3", "default:marram_grass_4",
			"default:marram_grass_5"},
		fern = {"default:fern_1", "default:fern_2", "default:fern_3"},
		blueberry = {"default:blueberry_bush_leaves", "default:blueberry_bush_leaves_with_berries"},
		gravel = {"default:gravel"},
		silver_sand = {"default:silver_sand"},
		sand = {"default:sand"},
		flowers = {"flowers:chrysanthemum_green", "flowers:dandelion_yellow", "flowers:dandelion_white", "flowers:tulip_black", "flowers:tulip",
			"flowers:viola", "flowers:rose"},
		mushroom = {"flowers:mushroom_brown", "flowers:mushroom_red"},
		bush_stem = {"default:acacia_bush_stem", "default:pine_bush_stem", "default:bush_stem"},
		tree = {"default:tree", "default:pine_tree", "default:jungletree", "default:aspen_tree", "default:acacia_tree"},
		dirt = {"default:dirt", "default:permafrost"},
		stone_with_ore = {"default:stone_with_coal", "default:stone_with_copper", "default:stone_with_diamond", "default:stone_with_gold",
			"default:stone_with_iron", "default:stone_with_mese", "default:stone_with_tin"},
		stone_like = {},
		stone = {"default:stone", "default:desert_stone", "default:sandstone", "default:desert_sandstone", "default:silver_sandstone",
			"default:cave_ice"},
		mesecons_wire = {},
		mesecon_vertical_wire = {"mesecons_extrawires:vertical_top_on", "mesecons_extrawires:vertical_top_off", "mesecons_extrawires:vertical_on",
			"mesecons_extrawires:vertical_off", "mesecons_extrawires:vertical_bottom_on", "mesecons_extrawires:vertical_bottom_off"},
		misc = {"default:silver_sandstone_brick"},
		cobble = {"default:cobble"},
		mossy_cobble = {"default:mossycobble"},
		cobble_stairs = {"stairs:stair_cobble"},
	},
	VEC_DIRS = {},
	FLOATING_DIRS = {p(1, 0, 0), p(-1, 0, 0), p(0, 1, 0), p(0, -1, 0), p(0, 0, 1), p(0, 0, -1)},
	COLOR_PALETTE = { --
	--
	--[[red]] --
	"#ff0000", "#ff3300", "#ff6600", "#ff3333", --
	"#cc0000", "#cc3333", "#990000", "#990033", --
	"#660000", "#660033", "#ff0033", "#ff3366", --
	"#ff6666", "#ff9999", "#ffcccc", --
	--[[red+green=yellow / orange]] --
	"#ff6600", "#ff9900", "#ffcc00", "#ffff00", --
	"#ffcc33", "#ffff33", "#cccc00", "#cccc33", --
	"#999900", "#999933", --
	--[[red+blue=magenta / pink]] --
	"#ff00ff", "#ff33ff", "#ff66ff", "#ff99ff", --
	"#ff3399", "#ff6699", "#ff99cc", "#ff66cc", --
	"#ff33cc", "#cc00cc", "#cc33cc", "#cc66cc", --
	"#cc99cc", "#cc00ff", "#cc33ff", "#cc66ff", --
	"#cc99ff", "#9900cc", "#990099", "#660066", --
	--[[green]] --
	"#00ff00", "#33ff00", "#66ff00", "#99ff00", --
	"#ccff00", "#00cc00", "#33cc00", "#66cc00", --
	"#99cc00", "#ccff33", "#00ff33", "#33ff33", --
	"#66ff33", "#99ff33", "#00cc33", "#33cc33", --
	"#66cc33", "#99cc33", --
	--[[green+blue=cyan / teal]] --
	"#00ffff", "#33ffff", "#66ffff", "#99ffff", --
	"#00cccc", "#33cccc", "#66cccc", "#99cccc", --
	"#00ccff", "#33ccff", "#66ccff", "#99ccff", --
	"#0099cc", "#3399cc", "#6699cc", "#00cc99", --
	"#33cc99", "#66cc99", "#99cc99", "#00cc66", --
	--[[blue]] --
	"#0000ff", "#3333ff", "#6666ff", "#9999ff", --
	"#0000cc", "#3333cc", "#6666cc", "#9999cc", --
	"#000099", "#333399", "#666699", "#000066", --
	"#333366", "#666666", "#000033", "#333333", --
	--[[blue+red=violet / purple]] --
	"#3300ff", "#6600ff", "#9900ff", "#cc00ff", --
	"#ff00cc", "#ff33cc", "#ff66cc", "#ff99cc", --
	"#cc3399", "#990066", "#660033", --
	--[[grayscale]] --
	"#ffffff", "#cccccc", "#999999", --
	"#666666", "#333333", "#000000" --
	},
	-- Define which nodes are considered "sticky"
	sticky_nodes = {
		["mesecons_stickyblocks:sticky_block_all"] = true,
	},
	cardinal_dirs = {p(0, 1, 0), p(0, -1, 0), p(1, 0, 0), p(-1, 0, 0), p(0, 0, 1), p(0, 0, -1)},
}
local function i_vec_dirs(arg) table.insert_all(vein_miner.CFG.VEC_DIRS, arg) end
-- self
i_vec_dirs({p(0, 0, 0)})
-- cardinal directions
i_vec_dirs({p(0, 1, 0), p(0, -1, 0), p(1, 0, 0), p(-1, 0, 0), p(0, 0, 1), p(0, 0, -1)})
-- xz
i_vec_dirs({p(1, 0, 1), p(-1, 0, 1), p(1, 0, -1), p(-1, 0, -1)})
-- xy
i_vec_dirs({p(1, 1, 0), p(-1, 1, 0), p(1, -1, 0), p(-1, -1, 0)})
-- yz
i_vec_dirs({p(0, 1, 1), p(0, -1, 1), p(0, 1, -1), p(0, -1, -1)})
-- x+ yz
i_vec_dirs({p(1, 1, 1), p(1, -1, 1), p(1, -1, -1), p(1, 1, -1)})
-- x- yz
i_vec_dirs({p(-1, 1, 1), p(-1, -1, 1), p(-1, -1, -1), p(-1, 1, -1)})
-- cords+ 2
i_vec_dirs({p(2, 0, 0), p(-2, 0, 0), p(0, 2, 0), p(0, -2, 0), p(0, 0, 2), p(0, 0, -2)})
-- cords+ 2,1
-- i_vec_dirs({p(-1, -2, 0)})
-- cords+ 2,1,1
-- i_vec_dirs({p(1, 2, 1)})
-- cords+ 3
-- i_vec_dirs({p(3, 0, 0), p(-3, 0, 0), p(0, 3, 0), p(0, -3, 0), p(0, 0, 3), p(0, 0, -3)})
-- distance of 3.1622776601684
-- i_vec_dirs({p(-3, 0, 1)})

ia(vein_miner.CFG.MINE_ONLY_CUR_SET, {"default:cobble", "default:mossycobble", "stairs:stair_cobble"})

i(vein_miner.CFG.IGNORED_NODES, "default:mese_post_light")

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

		ia(vein_miner.CFG.MINE_ONLY_GROUPS.mesecons_wire, {"mesecons:wire_" .. nodeid .. "_off", "mesecons:wire_" .. nodeid .. "_on"})

		if (nid_inc(nid) == false) then
			return
		end
	end
end
register_wires_group()

i(vein_miner.CFG.MINE_ONLY_CUR_SET, "mesecons_powerplant:power_plant")
ia(vein_miner.CFG.MINE_ONLY_CUR_SET, {"mesecons_movestones:sticky_movestone_vertical", "mesecons_stickyblocks:sticky_block_all"})
ia(vein_miner.CFG.MINE_ONLY_CUR_SET, {"mesecons_movestones:sticky_movestone"})
