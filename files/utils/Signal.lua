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
		self._argData = nil
		self._argCount = nil -- Prevent edge case of :Fire("A", nil) --> "A" instead of "A", nil

		return self
	end

	function Signal.isSignal(object)
		return typeof(object) == 'table' and getmetatable(object) == Signal;
	end;

	--- Fire the event with the given arguments. All handlers will be invoked. Handlers follow
	-- Roblox signal conventions.
	-- @param ... Variable arguments to pass to handler
	-- @treturn nil
function Signal:Fire(...)
	if not self._bindableEvent then return end
	
	local argData = {...}
	local argCount = select("#", ...)
	
	-- Store current fire's arguments
	self._argData = argData
	self._argCount = argCount
	
	-- Fire the event
	self._bindableEvent:Fire()
	
	-- Clear after handlers have run
	self._argData = nil
	self._argCount = nil
end

function Signal:Connect(handler)
	if not self._bindableEvent then 
		return error("Signal has been destroyed")
	end

	if type(handler) ~= "function" then
		error(("connect(%s)"):format(typeof(handler)), 2)
	end

	return self._bindableEvent.Event:Connect(function()
		-- Capture args immediately when the BindableEvent fires
		local argData = self._argData
		local argCount = self._argCount
		
		handler(unpack(argData, 1, argCount))
	end)
end

function Signal:Wait()
	-- Capture the args immediately when the event fires, before Fire() clears them
	local argData, argCount
	
	local connection
	connection = self._bindableEvent.Event:Connect(function()
		argData = self._argData
		argCount = self._argCount
		connection:Disconnect()
	end)
	
	self._bindableEvent.Event:Wait()
	
	assert(argData, "Missing arg data, likely due to :TweenSize/Position corrupting threadrefs.")
	return unpack(argData, 1, argCount)
end


return Signal
