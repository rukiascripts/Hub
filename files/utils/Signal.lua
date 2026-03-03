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

		self._handlers = {}
		self._waiting = {}
		self._destroyed = false

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
    local args = {n = select("#", ...), ...}

    for _, handler in self._handlers do
        task.defer(handler, unpack(args, 1, args.n))
    end

    for _, thread in self._waiting do
        task.defer(thread, unpack(args, 1, args.n))
    end

    table.clear(self._waiting)
end

	--- Connect a new handler to the event. Returns a connection object that can be disconnected.
	-- @tparam function handler Function handler called with arguments passed when `:Fire(...)` is called
	-- @treturn Connection Connection object that can be disconnected
function Signal:Connect(handler)
    if self._destroyed then
        return error("Signal has been destroyed");
    end

    if type(handler) ~= "function" then
        error(("connect(%s)"):format(typeof(handler)), 2)
    end

    local handlers = self._handlers
    table.insert(handlers, handler)

    local conn = {}
    conn.Connected = true

    function conn:Disconnect()
        self.Connected = false
        local index = table.find(handlers, handler)
        if (index) then
            table.remove(handlers, index)
        end
    end

    conn.Remove = conn.Disconnect
    conn.Destroy = conn.Disconnect

    return conn
end


	--- Wait for fire to be called, and return the arguments it was given.
	-- @treturn ... Variable arguments from connection
function Signal:Wait()
    table.insert(self._waiting, coroutine.running())
    return coroutine.yield()
end


	--- Disconnects all connected events to the signal. Voids the signal as unusable.
	-- @treturn nil
	function Signal:Destroy()
		self._destroyed = true
		table.clear(self._handlers)
		table.clear(self._waiting)
	end

return Signal
