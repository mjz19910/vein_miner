--- Deque implementation by Pierre 'catwell' Chapuis
--- MIT licensed (see LICENSE.txt)
local assert = assert
local setmetatable = setmetatable

---@class DequeModule
local deque = {}

---@class Deque
---@field head number
---@field tail number
---@generic T
local Deque = {}

---@param self Deque
---@generic T
---@param value T
function Deque:push_right(value)
	assert(value ~= nil)
	self.tail = self.tail + 1
	self[self.tail] = value
end

---@param self Deque
---@generic T
---@param value T
function Deque:push_left(value)
	assert(value ~= nil)
	self[self.head] = value
	self.head = self.head - 1
end

---@param self Deque
---@generic T
---@return T | nil
function Deque:peek_right() return self[self.tail] end

---@param self Deque
---@generic T
---@return T | nil
function Deque:peek_left() return self[self.head + 1] end

---@param self Deque
---@generic T
---@return T | nil
function Deque:pop_right()
	if self:is_empty() then
		return nil
	end
	local r = self[self.tail]
	self[self.tail] = nil
	self.tail = self.tail - 1
	return r
end

---@param self Deque
---@generic T
---@return T | nil
function Deque:pop_left()
	if self:is_empty() then
		return nil
	end
	self.head = self.head + 1
	local r = self[self.head]
	self[self.head] = nil
	return r
end

---@param self Deque
---@generic T
---@param n integer | nil
---@return nil
function Deque:rotate_right(n)
	n = n or 1
	if self:is_empty() then
		return nil
	end
	for i = 1, n do
		self:push_left(self:pop_right())
	end
end

---@param self Deque
---@generic T
---@param n integer | nil
---@return nil
function Deque:rotate_left(n)
	n = n or 1
	if self:is_empty() then
		return nil
	end
	for i = 1, n do
		self:push_right(self:pop_left())
	end
end

---@param self Deque
---@param idx number
local _remove_at_internal = function(self, idx)
	for i = idx, self.tail do
		self[i] = self[i + 1]
	end
	self.tail = self.tail - 1
end

---@param self Deque
---@param value T
---@generic T
function Deque:remove_right(value)
	for i = self.tail, self.head + 1, -1 do
		if self[i] == value then
			_remove_at_internal(self, i)
			return true
		end
	end
	return false
end

---@param self Deque
---@param x T
---@generic T
function Deque:remove_left(x)
	for i = self.head + 1, self.tail do
		if self[i] == x then
			_remove_at_internal(self, i)
			return true
		end
	end
	return false
end

---@param self Deque
---@return integer
function Deque:length() return self.tail - self.head end

---@param self Deque
function Deque:is_empty() return self:length() == 0 end

---@param self Deque
---@return T[]
---@generic T
function Deque:contents()
	local r = {}
	for i = self.head + 1, self.tail do
		r[i - self.head] = self[i]
	end
	return r
end

---@param self Deque
---@return fun(): T | nil
---@generic T
function Deque:iter_right()
	local i = self.tail + 1
	return function()
		if i > self.head + 1 then
			i = i - 1
			return self[i]
		end
	end
end

---@param self Deque
---@return fun(): T | nil
---@generic T
function Deque:iter_left()
	local i = self.head
	return function()
		if i < self.tail then
			i = i + 1
			return self[i]
		end
	end
end

---@return Deque
---@generic T
function deque.new()
	---@type Deque
	local r = {
		head = 0,
		tail = 0,
	}
	return setmetatable(r, {
		__index = Deque,
	})
end

return deque
