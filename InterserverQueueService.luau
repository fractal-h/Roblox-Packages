-- Typedef
export type OpenedQueueData = {
	queue: MemoryStoreQueue, 
	size: number,
	queueExpirationTime: number,

	DequeueEvent: BindableEvent
};
export type QueueData = {messageKey: string, data: {}};
export type QueueMessage = {queueId: string, key: number, data: {}};

-- Services
local MessagingService = game:GetService("MessagingService");
local MemoryStoreService = game:GetService("MemoryStoreService");

-- Data
local OpenedQueues = {} :: OpenedQueueData;
local ServerResponsePromise = {};
local DefaultQueueSize = math.pow(2, 4);
local DefaultQueueExpirationTime = 60 * 60 * 24; -- One day in seconds
local DefaultPingResponseTimeAllowance = 5; -- Must be whole integer 
local GameShutDown = false;

-- Messaging Keys
local ServerID = "Server-" .. game.JobId;
local ServerActive = "Activity-Check" .. ServerID;
local ServerActiveReceipt = "Acitivity-Check-Author" .. ServerID;

-- Module
local InterserverQueueService = {
	Enum = {
		FilterAction = {
			Remove = 0,
			Keep = 1,
		},	
	},	
};
InterserverQueueService.__index = InterserverQueueService;

-- Listeners
local DequeueListen = function(message: QueueMessage)
	if (GameShutDown) then return false end;

	local queueId = message.queueId;
	local key = message.key; 
	local data = message.data;

	local queueData = InterserverQueueService.Open(queueId);
	if (not queueData) then 
		warn("Critical Error: Dequeue Message Listener could not open queue " .. queueId);
		return 
	end

	-- Removes item from queue 
	queueData.DequeueEvent:Fire(data); -- key not provided because it has no relevance to packet outside RemoveAsync
	queueData.queue:RemoveAsync(key);
end

local ActivityCheck = function(responseTarget: string)
	if (GameShutDown) then return false end;
	MessagingService:PublishAsync(responseTarget, ServerActiveReceipt);
end

local ActivityCheckReceipt = function(responseId: string)
	ServerResponsePromise[responseId] = true;
end

local PingServer = function(serverId: string)
	if (GameShutDown) then return false end;
	if (ServerResponsePromise[serverId]) then return end;

	ServerResponsePromise[serverId] = DefaultPingResponseTimeAllowance;
	while (ServerResponsePromise[serverId] ~= true) do
		ActivityCheck("Activity-Check" .. serverId);
		task.wait(1);
		ServerResponsePromise[serverId] = math.max(ServerResponsePromise[serverId] - 1, 0);

		if (ServerResponsePromise[serverId] == 0) then 
			return false;
		end
	end

	ServerResponsePromise[serverId] = nil;

	return true;
end

-- Filter function
function Filter(packet: QueueData, filterValues: {}): boolean
	-- Establish "seen" table to avoid cyclic tables infinite recursion
	local alreadySeen = {};

	local function FilterQueue(currentSet: QueueData)
		if (alreadySeen[currentSet]) then return false end;
		alreadySeen[currentSet] = true;

		-- Check for values in table
		local filtersMet = true;
		for key, value in filterValues do 
			if (currentSet[key] == nil) then 
				filtersMet = false;
				break;
			end
			
			if (currentSet[key] ~= value) then 
				filtersMet = false;
				break; 
			end
		end
		
		-- If all filters met return true
		if (filtersMet) then return true end;
		
		-- If values are not found, recursively check through all other tables contained in the packet
		for key, value in currentSet do 
			if (typeof(value) ~= "table") then continue end;

			local filterMet = FilterQueue(currentSet[key]);
			if (filterMet) then return true end;
		end
	end

	-- Return
	return FilterQueue(packet, filterValues);
end

-- Functions

-- Recieves all items in queue
function InterserverQueueService.List(queueId: string): {QueueData}
	if (GameShutDown) then return false end;
	local queueData = InterserverQueueService.Open(queueId);
	if (not queueData) then return false end;

	-- If there is no data existing return true
	local queueSize = queueData.queue:GetSizeAsync();
	if (queueSize == 0) then return {} end;

	-- Read data based on queue size
	local success, list, readId = pcall(queueData.queue.ReadAsync, queueData.queue, queueSize, false, -1);
	assert(success, "Failure to read queue data, Error Message:\t" .. (tostring(list) or "N/A"));

	return list, readId;
end

-- Adds item to specified queue
function InterserverQueueService.Enqueue(queueId: string, ...)
	if (GameShutDown) then return false end;
	local queueData = InterserverQueueService.Open(queueId);
	if (not queueData) then return false end;

	local packetContent = {...};

	-- Set data 
	local data = {
		messageKey = ServerID,
		data = packetContent
	} :: QueueData;

	-- Attempt to set async
	local success, errorMsg = pcall(queueData.queue.AddAsync, queueData.queue, data, queueData.queueExpirationTime);

	-- If request fails, return false
	assert(success, "Attempt to enque data failed, error message:\t" .. (tostring(errorMsg or "N/A")));

	return true;
end

-- Finds lowest value item in queue
function InterserverQueueService.Dequeue(queueId: string)
	if (GameShutDown) then return false end;
	local queueData = InterserverQueueService.Open(queueId);
	if (not queueData) then return false end;

	-- Memory stored in FIFO format, getasync(1) should always (if not empty) return oldest item
	local success, packet, foundId = pcall(queueData.queue.ReadAsync, queueData.queue, 1, false, -1);
	local foundData = packet[1];

	-- Return false if queue empty
	if (not foundData) then
		return false;
	end

	-- If server is current server skip next steps
	if (foundData.messageKey == ServerID) then
		DequeueListen({queueId = queueId, key = foundId, data = packet});
		return true;
	end

	-- Ping server, if there is no response within 5 seconds remove all queue data points associated with that server
	local serverWaiting = PingServer(foundData.messageKey);
	if (not serverWaiting) then 
		InterserverQueueService.FreeServer(queueId, foundData.messageKey);

		-- Attempt to move to next data point (after all points associated with innactive server are cleared)
		InterserverQueueService.Dequeue(queueId);
		return false;
	end

	-- Tell server that owns queue data point to dequeue 
	MessagingService:PublishAsync(foundData.messageKey, {queueId = queueId, key = foundId, data = packet});

	return true;
end

-- Removes item from specified queue
function InterserverQueueService.Remove(queueId: string, key: string)
	if (GameShutDown) then return false end;

	warn("InterserverQueueService.Remove required a readId, which is created when ReadAsync is called.\nTo remove at index use InterserverQueueService.Filter")

	local queueData = InterserverQueueService.Open(queueId);
	if (not queueData) then return false end;

	-- Remove from queue
	queueData.queue:RemoveAsync(key);
end

function InterserverQueueService.Filter(queueId: string, action: number, filterValues: {})
	if (GameShutDown) then return false end;

	local queueData = InterserverQueueService.Open(queueId);
	if (not queueData) then return false end;

	local list, readId = InterserverQueueService.List(queueId);
	local packetBuffer = {};
	local deletionRequired = false;

	for i, packet in ipairs(list) do
		local filterMet = Filter(packet, filterValues);

		-- Switch based on action Enum
		if (action == InterserverQueueService.Enum.FilterAction.Remove) then 
			if (filterMet) then 
				deletionRequired = true;
			else
				table.insert(packetBuffer, packet);
			end

			continue;
		elseif (action == InterserverQueueService.Enum.FilterAction.Keep) then 
			if (filterMet) then 
				table.insert(packetBuffer, packet);
			else
				deletionRequired = true;
			end

			continue;
		else
			warn("Provided Action value does not match existing FilterAction Enum");
		end
	end

	if (not deletionRequired) then return true end;

	-- Free packets associated with server
	queueData.queue:RemoveAsync(readId);

	-- Write new data
	for key, packet in ipairs(packetBuffer) do 
		pcall(queueData.queue.AddAsync, queueData.queue, packet, queueData.queueExpirationTime);
	end
end

-- Open a queue instance
function InterserverQueueService.Open(queueId: string, queueSize: number?, expirationTime: number?): OpenedQueueData
	if (GameShutDown) then return false end;

	-- If there is existing hash map with the key return that 
	local existingData = OpenedQueues[queueId];

	if (existingData) then 
		return existingData;
	end

	-- Return if queue size is not specified and queue is not already opened
	if (not queueSize) then
		queueSize = DefaultQueueSize;
		warn("Auto-set queue '" .. queueId .. "' page size to " .. DefaultQueueSize);
	end

	-- Open hash map instance
	local success, queueData = pcall(MemoryStoreService.GetQueue, MemoryStoreService, queueId, DefaultPingResponseTimeAllowance);

	-- Handle error
	assert(success, queueId .. " was not found, error message:\t" .. (tostring(queueData or "N/A")));

	-- Set data
	OpenedQueues[queueId] = {
		queue = queueData,
		size = queueSize,
		queueExpirationTime = expirationTime or DefaultQueueExpirationTime,

		DequeueEvent = Instance.new("BindableEvent"),
	};

	return OpenedQueues[queueId];
end

-- Free data associated with queue
function InterserverQueueService.Free(queueId: string)
	local queueData = OpenedQueues[queueId];
	if (not OpenedQueues[queueId]) then
		warn("Attempted to free data for non-existant queue " .. queueId);
		return false;
	end

	-- If there is no data existing return true
	local queueSize = queueData.queue:GetSizeAsync();
	if (queueSize == 0) then return true end;

	-- Recieve all data
	local success, items, readId = pcall(queueData.queue.ReadAsync, queueData.queue, queueSize, false, -1);

	if (not success) then 
		warn("Failed to read server data. Error message:\t" .. (tostring(items) or "N/A"))
		return false;
	end

	-- Clear data
	queueData.queue:RemoveAsync(readId);

	OpenedQueues[queueId].DequeueEvent:Destroy();

	rawset(OpenedQueues, queueId, nil);
	return true;
end

-- Frees all data points associated with the server specified
function InterserverQueueService.FreeServer(queueId: string, serverId: string)
	InterserverQueueService.Filter(queueId, InterserverQueueService.Enum.FilterAction.Remove, {messageKey = serverId})
end

-- Connections
MessagingService:SubscribeAsync(ServerID, DequeueListen); 
MessagingService:SubscribeAsync(ServerActive, ActivityCheck);
MessagingService:SubscribeAsync(ServerActiveReceipt, ActivityCheckReceipt);

-- BindToClose
game:BindToClose(function()
	for queueId, _ in OpenedQueues do 
		InterserverQueueService.FreeServer(queueId, ServerID);
		OpenedQueues[queueId] = nil;
	end
	GameShutDown = true;
end)

-- Return
return InterserverQueueService;
