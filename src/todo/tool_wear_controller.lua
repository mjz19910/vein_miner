local ToolWearController = {}
ToolWearController.__index = ToolWearController

function ToolWearController.new(player, node_name)
	local wielded = player:get_wielded_item()
	local def = minetest.registered_items[node_name] or {}
	local tp = wielded:get_tool_capabilities()
	local dp = core.get_dig_params(def.groups or {}, tp)

	return setmetatable({
		player = player,
		wielded = wielded,
		wear = dp.wear or 0,
		limit = 65535 - (dp.wear or 0),
	}, ToolWearController)
end

function ToolWearController:is_usable()
	return self.wielded:get_wear() < self.limit
end

function ToolWearController:apply_wear()
	self.wielded:add_wear(self.wear)

	-- Sync with player's actual wielded item
	local current = self.player:get_wielded_item()
	if current:get_wear() ~= self.wielded:get_wear() then
		self.wielded:set_wear(current:get_wear())
	end

	-- If near breaking, force update
	if self.wielded:get_wear() > (65535 - self.wear * 3) then
		self.player:set_wielded_item(self.wielded)
	end
end

return ToolWearController
