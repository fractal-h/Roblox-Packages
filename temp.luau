-- Temp file to get skill role in hidden devs
-- Services
local Event = require(game.ReplicatedStorage.Assets.Modules.Utility.Event);
local Debris = game:GetService("Debris");

-- Events
local WalkSpeedChanged = game.ReplicatedStorage["Remote Events"].WalkSpeedChanged;

-- Data
local Cooldowns = require(script.Cooldowns);
local DefaultData = require(script.DefaultData);
local DefaultStates = require(script.DefaultStates);
local entity;
local Active = {};

-- Typedef
export type EntityEvents = {
	StateChanged: Event,
};

export type Entity = {
	-- Members
	eid: number,
	
	states: EntityStates,	
	data: EntityData,
	events: EntityEvents,
	
	-- Methods
	Destroy: () -> nil, -- Destroys Entity and Clears Data
	GetRaw: () -> Entity, -- Creates clone of entity data with no proxy tables (for printing etc)
	AddAttribute: (string, any?) -> nil, -- Adds Attribute
	ClearAttribute: (string) -> nil, -- Clears attribute (cannot clear things such as health maxhealth etc)
	Tick: (number) -> (boolean, string?), -- Updates entity with main loop
	GetRoot: () -> Part, -- Gets root part of character 
	TakeDamage: (number, boolean) -> nil, -- Takes specified damage and kills entity if health drops below 0
	
		-- Private
	AITick: (number) -> (boolean, string?), -- Updates AI entities with main loop
};

-- State Changed Callbacks
local StateChangedCallbacks = {
	blocking = function(cooldowns, oldState, newState)
		if (newState == true and oldState == false and os.clock() - (cooldowns.blocking or 0) < 0) then 
			warn("ENTITY: Attempted to block prior to block cooldown expiring.")
			return false;
		end

		if (oldState == true and newState == false) then 
			cooldowns.blocking = os.clock() + Cooldowns.blocking;
		end
		
		return true
	end,	
	default = function()
		return true;
	end,
};

local DataChangedCallbacks = {
	walkSpeed = function(self, value)
		if (not self.client) then return end;
		
		WalkSpeedChanged:InvokeClient(self.client.player, value);
	end,	
};

-- Destructor
local function DestroyCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid");
	
	if (_G.KILL_ON_DEATH and humanoid) then
		humanoid.Health = -1;
		Debris:AddItem(character, _G.RESPAWN_TIME);
		return;
	end
	
	-- Implement ragdoll
	if (_G.RAGDOLL_ON_DEATH) then 
		Debris:AddItem(character, _G.RESPAWN_TIME);
		return;
	end
	
	-- Default to destroy
	Debris:AddItem(character, 0);
end

-- Generic
local function EmptyEntity(): Entity
	local states = table.clone(DefaultStates);
	local data = table.clone(DefaultData);
	local destroying = false;
	
	local cooldowns = {};
	local nonstandardAttributes = {};
	
	local obj = {
		states = {}, -- Proxy
		data = {},
		events = {
			Destroying = Event.new(),
			StateChanged = Event.new(),	
			DataChanged = Event.new(),
		},
	} :: Entity;
	
	-- Create Proxy Table for states to get __newindex signal for StateChanged event 
	setmetatable(obj.states, {
		__newindex = function(self, key, value)
			-- Reset values
			rawset(self, key, nil);
			assert(typeof(value) == "boolean", "ENTITY: Attempted to set entity state " .. key .. " to non-boolean type " .. typeof(value));
			
			-- Verify state update and make necessary changes
			local callback = StateChangedCallbacks[key];
			local query = not callback or callback(cooldowns, states[key], value);
			if (not query) then return end;
		
			-- Update value and cooldown
			states[key] = value;
			obj.events.StateChanged:Fire(key);
		end,
		__index = states,
	});
	
	-- Create Proxy Table for states to get __newindex signal for DataChanged event 
	setmetatable(obj.data, {
		__newindex = function(self, key, value)
			-- Reset values
			rawset(self, key, nil);

			-- Verify state update and make necessary changes
			local callback = DataChangedCallbacks[key];
			local query = not callback or callback(self, value);
			if (not query) then return end;

			-- Update value and cooldown
			data[key] = value;
			obj.events.DataChanged:Fire(key);
		end,
		__index = data,
	});
	
	setmetatable(obj, entity);
	
	-- Create proxy table to redirect indexs to data table
	local dataProxy = setmetatable({}, {
		-- Standard methods
		__newindex = function(self, key, value)
			rawset(self, key, nil);
			
			-- Find member of states to update
			if (states[key] ~= nil) then 
				obj.states[key] = value;
				return;
			end
			
			-- Find member of data to update
			if (data[key] ~= nil or key == "character") then
				assert(typeof(value) == typeof(data[key]) or (key == "character" and typeof(value) == "Instance"), "Attempted to set " .. key .. " of entity to non-" .. typeof(data[key]) .. " type " .. typeof(value));
				obj.data[key] = value;
				return;
			end
			
			-- Look for nonstandard attribute
			if (nonstandardAttributes[key]) then 
				assert(typeof(value) == typeof(nonstandardAttributes[key]), "ENTITY: Attempted to set Entity attribute " .. key .. " to incorrect type " .. typeof(value));
				nonstandardAttributes[key] = value;
				return;
			end
			
			error("ENTITY: Attempted to edit non-existant or read only member of Entity " .. key);
		end,
		__index = function(self, key) -- Redirects referances to data/states/event	
			local metaTable = getmetatable(self);
			local referance = metaTable[key] or obj[key] or states[key] or data[key] or obj.events[key] or nonstandardAttributes[key];
			return referance;
		end,
		__eq = function(self, comp)
			local otherID = (typeof(comp) == "table") and comp.eid or -1;
			return (self.eid == otherID);
		end,
		__tostring = function(self)
			return "Entity " .. self.eid;
		end,
		
		-- Methods
		Destroy = function(self)
			if (destroying) then return end; -- Cancel repeat destroy calls 
			destroying = true;
			
			-- Remove from entity pool
			Active[self.eid] = nil;
			
			-- Fire event
			obj.events.Destroying:Fire();
			
			-- Destroys character
			if (self.character) then 
				DestroyCharacter(self.character)
			end
			
			-- Clear events
			for eventName, event in self.events do 
				event:Destroy();
			end
			
			-- Free up data
			obj = nil;
			data = nil;
			states = nil;
			nonstandardAttributes = nil;
			cooldowns = nil;
		end,
		
		TakeDamage = function(self, amount: number, bypassIFrames: boolean?)
			if (self.iframes and not bypassIFrames) then return end;
			self.health -= amount;
			
			-- Kill self if health <= 0 
			if (self.health <= 0) then 
				self:Destroy();
			end
		end,
		
		AddAttribute = function(self, key, value)
			nonstandardAttributes[key] = value;
		end,
		
		ClearAttribute = function(self, key)
			if (not nonstandardAttributes[key]) then return end;
			nonstandardAttributes[key] = nil;
		end,
		
		GetRaw = function(self)
			local clone = table.clone(obj);
			clone.states = states;
			clone.nonstandardAttributes = nonstandardAttributes;
			return clone;
		end,
		
		AITick = function(self, deltaTime: number): (boolean, string?)
			
			-- path finding, combat, etc
			return true;
		end,
		
		Tick = function(self, deltaTime: number): (boolean, string?)
			-- Conditions 
			if (not self.character) then -- Temp for testing
				return false, self.eid .. " does not have a valid character set";
			end

			-- Update
			if (self.regenEnabled) then 
				self.health = math.min(self.maxHealth, self.health + self.regenSpeed * deltaTime);
			end
			
			-- Handle stun
			if (nonstandardAttributes.stunTimer) then 
				if (nonstandardAttributes.stunTimer < os.clock()) then 
					self:ClearAttribute("stunTimer");
					self.stunned = false;
				end
			end
			
			-- Dash CD 
			if (self.dashCD) then 
				if (self.dashCD < os.clock()) then 
					self:ClearAttribute("dashCD");
				end
			end
			
			-- IFrames
			self.iframeAmount = math.max(self.iframeAmount - 1, 0);
			self.iframes = self.iframeAmount > 0;
			
			if (self.iframes) then 
				print("IFrames remaining: ", self.iframeAmount)
			end
			
			-- Temp
			if (_G.USE_STANDARD_HEALTHBAR) then 
				self.character.Humanoid.MaxHealth = self.maxHealth;
				self.character.Humanoid.Health = self.health;
			end
			
			-- Handle attack cd
			if (nonstandardAttributes.attackCD) then 
				if (nonstandardAttributes.attackCD < os.clock()) then 
					self:ClearAttribute("attackCD");
					self.canAttack = true;
				end
			elseif (self.canAttack == false) then 
				-- Prevent canAttack being locked to false if attackCD doesnt exist
				self.canAttack = true;
			end

			-- Redirect to AI tick once all generic conditions and updates are completed
			if (self.AI) then return self:AITick(deltaTime) end;

			return true;
		end,
		
		GetRoot = function(self): Part
			return self.character.HumanoidRootPart;
		end,
	});
	
	return dataProxy;
end

-- Update Function
local function Parse(deltaTime: number)
	for id, entity: Entity in Active do 
		local success, errorMessage = entity:Tick(deltaTime);
		
		if (not success) then
			warn("ENTITY: Non-fatal error, " .. errorMessage);
			entity:Destroy();
			continue;
		end
	end
end

-- Entity Class
local entityId = 1;
entity = {
	new = function(character: Model, data: EntityData?): Entity
		assert(character, "ENTITY: Attempted to create entity without a character");
		assert(character.Humanoid, "ENTITY: Attempted to create entity with no humanoid");
		-- Create entity
		local new = EmptyEntity() :: Entity;
		
		-- Set Character
		new.character = character;
		
		-- Load in data 
		if (data) then 
			for i, v in data do 
				new[i] = v;
			end
		end
		
		-- Add to entity pool
		Active[entityId] = new;
		character.Parent = workspace.Active;
		new.eid = entityId;
		
		-- Handle destruction
		character.Destroying:Once(function()
			new:Destroy();
		end)
		
		character.Humanoid.Died:Once(function()
			new:Destroy();
		end)
		
		-- Update humanoid 
		character.Humanoid.MaxHealth = new.maxHealth;
		character.Humanoid.Health = new.health;
		character.Humanoid.WalkSpeed = new.walkSpeed;
		
		-- Increment ID
		entityId += 1;
		
		return new;
	end,	
	GetEntities = function()
		return Active;
	end,
	Update = function(deltaTime: number)
		local success, errorMessage = pcall(Parse, deltaTime);
		
		if (not success) then 
			warn("ENTITY: Fatal error, " .. errorMessage);
		end
	end, -- Meant to only be called by the game loop
};
entity.__index = entity;

return entity;
