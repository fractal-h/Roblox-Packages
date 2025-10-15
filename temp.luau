-- TYPEDEF
-- Define connection type
type Connection = {
	Pause: () -> nil,
	Resume: () -> nil,
	Disconnect: () -> nil	
};

-- Define event type
type Event = {
	Fire: (...any?) -> nil,	
	ClearConnections: () -> nil,
	Destroy: () -> nil,
	Once: (callback: (...any?) -> nil, ...any?) -> Connection,
	Connect: (callback: (...any?) -> nil, ...any?) -> Connection,
	BindFire: () -> (...any?)
};

-- DATA
local eventId = 0; -- event id counter
local events = {}; -- stores events
local namedEvents = {}; -- stores ids of named events (so they can be retrieved by name)

-- CONNECTION
local connection;
connection = {
	new = function(attachedEventId: number, callback: (...any?) -> nil, id: number, once: boolean, ...): Connection

		-- Connection constructor

		local newConnection = setmetatable({
			attachedEventId = attachedEventId,
			id = id,
			once = once,
			paused = false,
			passedParameters = {...},
			callback = callback,
		}, connection);

		return newConnection;

	end,	
};
connection.__index = connection;

function connection:Signal(...) -- Fire the connected function with stored values as well as the ones passed when signal was fired
	task.spawn(self.callback, ..., table.unpack(self.passedParameters));

	if (self.once) then
		self:Disconnect();
	end
end

function connection:Pause() -- Prevents the connection from being signaled when event is fired
	self.paused = true;
end

function connection:Resume() -- Enables the connection to be signaled when event is fired
	self.paused = false;
end

function connection:Disconnect() -- Disconnects connection from event and clears memory
	rawset(events[self.attachedEventId].connected, self.id, nil);
	setmetatable(self, nil);
end

-- High order function that creates a connection object and returns it
local function createConnection(self, callback, once, ...)
	self.connectionId += 1;
	local newConnection = connection.new(self.id, callback, self.connectionId, once, ...);
	newConnection.id = self.connectionId;
	self.connected[self.connectionId] = newConnection;
	return newConnection;
end

-- EVENT
local event;
event = {
	getEvent = function(identifier, waitTime: number) -- retrieve event based on name or id
		local found = events[namedEvents[identifier]] or events[identifier];

		-- if the event does not exist, then the specified (if specified) is waited trying to find it
		if (not found and waitTime) then 
			local elapsed = 0;
			repeat elapsed += task.wait() until (events[namedEvents[identifier]] or events[identifier]) or elapsed >= waitTime;
		end
		return found;
	end,

	-- This function creates a new event object
	new = function(name: string): Event -- Event Construction

		-- Increase event counter
		eventId += 1;

		local id = eventId;

		-- This creates a table and sets its metatable to the event's (this makes it so it has the same methods as it)
		local newEvent = setmetatable({
			id = id,
			name = name,
			connectionId = 0,
			connected = {},
		}, event);

		events[eventId] = newEvent;

		if (name) then 

			-- Preventing Overlapping Event names
			if (namedEvents[name]) then error("Attempted to override event ", name) end;

			namedEvents[name] = id;

		end

		return events[eventId];

	end,	
};
event.__index = event;

function event:__call(...) -- When you call the event directly, it fires the event
	self:Fire(...);
end

function event:ClearConnections() -- Clear all connections and free memory

	self.connectionId = 0;

	-- Disconnect and clear memory of connected tables
	for _, connection in pairs(self.connected) do
		connection:Disconnect();
	end

end

function event:Destroy() -- Clear memory of connections and event

	-- Remove event name from list
	if (self.name) then 
		rawset(namedEvents, self.name, nil);
	end

	-- Free memory
	self:ClearConnections();
	rawset(events, self.id, nil);
	setmetatable(self, nil);
end

function event:Connect(callback: (...any?) -> nil, ...): Connection -- Connect a function and store desired parameters 
	assert(callback, "Callback cannot be nil; (Event: " .. (self.name or self.id));
	return createConnection(self, callback, false, ...);
end

function event:Once(callback: (...any?) -> nil, ...): Connection -- Connect a function and store desired parameters that after being signaled clears its memory. 
	assert(callback, "Callback cannot be nil; (Event: " .. (self.name or self.id));
	return createConnection(self, callback, true, ...);
end

function event:Fire(...) -- Signal all connected functions with passed parameters
	for _, connection in pairs(self.connected) do

		if (connection.paused) then continue end;

		connection:Signal(...);
	end

end

-- This bindfire method returns a function that when called Fires the event with the parameters passed
function event:BindFire() -- To allow for the fire function to be passed as a callback
	return function(...) self:Fire(...) end;
end

return event;

-- All of my code is broken into modules so the few that do break 200 lines are like 500+ lines. I do not want to go back and add extra comments explaining what Im doing to a script with 500+ lines. Pretend the following code was a part of the previous module.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local RunService = game:GetService("RunService");
local TweenService = game:GetService("TweenService");

-- Module
local utility = {
	-- Reflects vector intersecting with normal 
	ReflectVector = function(incident: Vector3, normal: Vector3): Vector3
		return incident - 2 * incident:Dot(normal) * normal
	end,
	-- Tweens keypoints in numbersequence (for transparency etc). Does not tween envelope.
	TweenNumberSequence = function(numberSequence: NumberSequence, tweenInfo: TweenInfo, callback: (numberSequence: NumberSequence) -> nil, sequencesValues: {number})
		-- Get origin and goals for keypoints
		local keypointOrigins = numberSequence.Keypoints;
		
		-- Error handling
		assert(#sequencesValues == #keypointOrigins, "Attempted to tween NumberSequence with invalid number of points");
		assert(callback, "No callback set for NumberSequence tween");
		assert(tweenInfo.Time > 0, "TweenInfo time for NumberSequence tween must be above 0");
		
		-- Find deltas for keypoints
		local deltas = {};
		for index, value in sequencesValues do 
			deltas[index] = value - keypointOrigins[index].Value;	
		end
		
		-- Tween in keypoints
		local elapsed = 0;
		local currentSequence;
		while (elapsed < tweenInfo.Time) do 
			elapsed = math.min(elapsed + RunService.PreSimulation:Wait(), tweenInfo.Time);
			
			-- Find alpha
			local alpha = TweenService:GetValue(elapsed / tweenInfo.Time, tweenInfo.EasingStyle, tweenInfo.EasingDirection);
			
			-- Update each keypoint
			local keypoints = {};
			for index, value in deltas do
				local keypoint = NumberSequenceKeypoint.new(keypointOrigins[index].Time, keypointOrigins[index].Value + value * alpha, keypointOrigins[index].Envelope);
				keypoints[index] = keypoint;
			end
			
			-- Create new number sequence and call the callback
			currentSequence = NumberSequence.new(keypoints);
			callback(currentSequence);
		end
		
		return currentSequence;
	end,
	-- Locks vector 3 y axis to 0
	Vector3YAxis0 = function(vector: Vector3): Vector3
		return Vector3.new(vector.X, 0, vector.Z);
	end,	
	-- Determines if parts (assumed to be unrotated 3d rectangles) are overlaping based on position and size
	Collision3d = function(a: Part, b: Part): boolean
		local ap, as = a.Position, a.Size;
		local bp, bs = b.Position, b.Size;

		-- Find collision based on position data
		return math.abs(ap.X - bp.X) < (as.X + bs.X) * 0.5
			and math.abs(ap.Y - bp.Y) < (as.Y + bs.Y) * 0.5
			and math.abs(ap.Z - bp.Z) < (as.Z + bs.Z) * 0.5;
	end,
	-- This function calculates the mass of a model provided, and then returns that mass
	GetModelMass = function(model: Model): number
		local mass = 0;
		-- This loop goes through all descendant instances of the model and adds their mass to the mass variable
		for _, v: Part in model:GetDescendants() do 
			if (not v:IsA("BasePart")) then continue end;
			mass += not v.Massless and v.Mass or 0;
		end
		return mass;
	end,
};

return utility;
