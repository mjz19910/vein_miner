local TeleportController = {}
TeleportController.__index = TeleportController
function TeleportController.new(player)
	return setmetatable({
		player = player,
		queue = vein_miner.deque.new(),
		seen = {},
		max_seen = 200,
		step_time = 0.06,
		total_time_limit = 0.4,
	}, TeleportController)
end

function TeleportController:enqueue(pos)
	local hash = core.hash_node_position(pos)
	if not self.seen[hash] then
		self.seen[hash] = true
		self.queue:push_right(vector.offset(pos, 0, -0.5, 0))
	end
	if next(self.seen, self.max_seen) ~= nil then
		self.seen = {}
	end
end

function TeleportController:drain()
	if self.queue:is_empty() then return nil end

	for pos in self.queue:iter_left() do
		self.player:set_pos(pos)
		coroutine.yield({
			wait = true,
			time = self.step_time,
		})
	end

	local total_steps = self.queue:length()
	local total_delay = self.total_time_limit - (self.step_time * total_steps)
	if total_delay > 0 then
		coroutine.yield({
			wait = true,
			time = total_delay,
		})
	end

	-- Reset queue
	self.queue.head = 0
	self.queue.tail = 0
end

function TeleportController:has_pending() return not self.queue:is_empty() end
return TeleportController
