local NodeScanner = {}
NodeScanner.__index = NodeScanner

local vector = vector -- localize for performance
local copy = table.copy

local mine_only_groups = {
	falling = {
		"default:sand",
		"default:gravel",
		"default:silver_sand",
	},
	marram_grass = {
		"default:marram_grass_1",
		"default:marram_grass_2",
		"default:marram_grass_3",
		"default:marram_grass_4",
		"default:marram_grass_5",
	},
	dry_grass = {
		"default:dry_grass_1",
		"default:dry_grass_2",
		"default:dry_grass_3",
		"default:dry_grass_4",
		"default:dry_grass_5",
	},
	grass = {
		"default:grass_1",
		"default:grass_2",
		"default:grass_3",
		"default:grass_4",
		"default:grass_5",
	},
	flowers = {
		"flowers:dandelion_yellow",
		"flowers:dandelion_white",
		"flowers:tulip_black",
		"flowers:tulip",
		"flowers:viola",
		"flowers:rose",
	},
	mushroom = {
		"flowers:mushroom_brown",
		"flowers:mushroom_red",
	},
	bush_stem = {
		"default:acacia_bush_stem",
		"default:pine_bush_stem",
		"default:bush_stem",
	},
	tree = {
		"default:tree",
		"default:pine_tree",
		"default:jungletree",
		"default:aspen_tree",
		"default:acacia_tree",
	},
	dirt = {
		"default:dirt",
		"default:permafrost",
	},
	stone_with_ore = {
		"default:stone_with_coal",
		"default:stone_with_copper",
		"default:stone_with_gold",
		"default:stone_with_iron",
		"default:stone_with_mese",
		"default:stone_with_tin",
	},
	stone_like = {
		"default:cobble",
		"default:mossycobble",
	},
	stone = {
		"default:stone",
	},
}

local ignored_nodes = {
	"default:chest",
	"default:leaves", -- default
	"drawers:trim",
	"drawers:pine_wood1",
	"drawers:controller", -- drawers
	"digtron:axle",
	"digtron:light",
	"digtron:pusher",
	"digtron:digger",
	"digtron:builder",
	"digtron:structure",
	"digtron:inventory",
	"digtron:fuelstore",
	"digtron:empty_crate",
	"digtron:auto_controller",
	"digtron:combined_storage",
	"digtron:inventory_ejector", -- digtron
}

local mine_only_cur_set = {
	"default:clay",
	"default:snow",
	"default:dry_dirt",
	"default:stone_block",
	"default:junglegrass",
	"default:blueberry_bush_leaves",
	"default:blueberry_bush_leaves_with_berries",
	"farming:cotton_wild",
}

local function handle_unexpected_target_nodes(target_nodes, node_name)
	if not table.contains(target_nodes, node_name) then
		if table.contains(ignored_nodes, node_name) then return "inc_mine_skip" end
		for k, value in pairs(mine_only_cur_set) do if node_name == value then return "mine_only_cur" end end
		return "error"
	end
	return "continue"
end

local mine_only_group_sets = {}
for key, group in pairs(mine_only_groups) do
	for idx, value in pairs(group) do
		mine_only_group_sets[value] = key
		table.insert(mine_only_cur_set, value)
	end
end

function NodeScanner.new(player_config)
	return setmetatable({
		player_config = player_config,
	}, NodeScanner)
end

function NodeScanner:get_scan_dimensions(playername, pos, scan_options)
	local xz_len, y_len = 8, 8
	if self.player_config[playername] == "large" and pos.y > -32.5 and not scan_options.light and not scan_options.small then

		xz_len = 32
		y_len = 32
		scan_options.large = true
	else
		scan_options.small = true
	end
	return vector.new(xz_len, y_len, xz_len), scan_options
end

function NodeScanner:get_target_nodes(node_name, scan_options)
	local target_nodes = {}

	if scan_options.light then
		table.insert_all(target_nodes, mine_only_groups.stone)
		table.insert_all(target_nodes, mine_only_groups.stone_like)
		table.insert_all(target_nodes, mine_only_groups.stone_with_ore)
		table.insert(target_nodes, node_name)
	elseif node_name == "default:brick" then
		table.insert_all(target_nodes, mine_only_groups.stone_with_ore)
		table.insert_all(target_nodes, mine_only_groups.stone)
		table.insert(target_nodes, "default:sand")
		table.insert(target_nodes, node_name)
	elseif mine_only_group_sets[node_name] ~= nil then
		local key = mine_only_group_sets[node_name]
		target_nodes = copy(mine_only_groups[key])
		scan_options._group_target = key
	else
		local result = handle_unexpected_target_nodes(target_nodes, node_name)
		if result == "error" then return nil, "error" end
		if result == "inc_mine_skip" then return {}, "skip" end
		if result == "mine_only_cur" then
			target_nodes = {
				node_name,
			}
		end
	end

	if scan_options.small then
		local key = scan_options._group_target
		if key == "stone" then
			table.insert_all(target_nodes, mine_only_groups.stone_like)
			table.insert_all(target_nodes, mine_only_groups.stone_with_ore)
		elseif key == "stone_like" or key == "stone_with_ore" then
			table.insert_all(target_nodes, mine_only_groups.stone)
		end
	end

	return target_nodes
end

function NodeScanner:mod_pos(pos, mod_size)
	pos = vector.divide(pos, mod_size)
	pos = vector.add(pos, 0.0001)
	pos = vector.floor(pos)
	pos = vector.multiply(pos, mod_size)
	return pos
end

function NodeScanner:scan_area(pos, size, nodes, use_hash)
	return core.find_nodes_in_area(self.minvec, self.maxvec, nodes, use_hash)
end

function NodeScanner:get_targets(player, pos, node_name, scan_options)
	local playername = player:get_player_name()
	local scan_size, updated_opts = self:get_scan_dimensions(playername, pos, scan_options)
	local targets = self:get_target_nodes(node_name, updated_opts)
	if not targets then return {} end

	self.minvec = self:mod_pos(pos, scan_size)
	self.maxvec = vector.add(self.minvec, vector.add(scan_size, -1))

	-- Add liquids last
	table.insert_all(targets, {
		"default:water_flowing",
		"default:water_source",
		"default:lava_flowing",
		"default:lava_source",
	})

	local nodes = self:scan_area(targets, true)

	-- Optional re-scan with reduced set
	local stone_only_nodes = {}
	if updated_opts.small then
		local reduced_targets = mine_only_groups.stone
		stone_only_nodes = self:scan_area(reduced_targets, true)
	end

	return nodes, stone_only_nodes
end

function NodeScanner:fix_light() core.fix_light(self.minvec, self.maxvec) end

return NodeScanner
