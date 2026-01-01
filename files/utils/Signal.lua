--- Lua-side duplication of the API of events on Roblox objects.
-- Signals are needed for to ensure that for local events objects are passed by
-- reference rather than by value where possible, as the BindableEvent objects
-- always pass signal arguments by value, meaning tables will be deep copied.
-- Roblox's deep copy method parses to a non-lua table compatable format.
-- @classmod Signal

local Signal = {}
Signal.__index = Signal
Signal.ClassName = "Signal"

--- Constructs a new signal.
-- @constructor Signal.new()
-- @treturn Signal
function Signal.new()
	local self = setmetatable({}, Signal)

	self._bindableEvent = Instance.new("BindableEvent")
	self._argMap = {} -- Store args by unique ID
	self._nextId = 0

	return self
end

function Signal:Fire(...)
	if not self._bindableEvent then return end
	
	-- Generate unique ID for this fire
	local id = self._nextId
	self._nextId = id + 1
	
	-- Store args with their count
	self._argMap[id] = {
		args = {...},
		count = select("#", ...)
	}
	
	-- Fire with just the ID
	self._bindableEvent:Fire(id)
	
	-- Clean up after a short delay
	task.defer(function()
		self._argMap[id] = nil
	end)
end

function Signal:Connect(handler)
	if not self._bindableEvent then 
		return error("Signal has been destroyed")
	end

	if type(handler) ~= "function" then
		error(("connect(%s)"):format(typeof(handler)), 2)
	end

	return self._bindableEvent.Event:Connect(function(id)
		local data = self._argMap[id]
		if data then
			handler(unpack(data.args, 1, data.count))
		end
	end)
end

function Signal:Wait()
	if not self._bindableEvent then return end
	
	local id = self._bindableEvent.Event:Wait()
	local data = self._argMap[id]
	
	if data then
		return unpack(data.args, 1, data.count)
	end
end

function Signal:Destroy()
	if self._bindableEvent then
		self._bindableEvent:Destroy()
		self._bindableEvent = nil
	end

	self._argMap = nil
	self._nextId = nil
end

return Signal
