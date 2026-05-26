local Players = game:GetService("Players");
local InterserverQueueService = require(script.Parent.InterserverQueueService);
local queueId = "ServerQueue"
local queue = InterserverQueueService.Open(queueId);

-- In Lobby Server
queue.DequeueEvent.Event:Connect(function(packet)
	local foundPlayer = Players:GetPlayerByUserId(packet.UserId);
	if (not foundPlayer) then return end;
	
	-- teleport player to game instance
end)

Players.PlayerAdded:Connect(function(plr)
	InterserverQueueService.Enqueue(queueId, {
		UserId = plr.UserId,
    -- include target server job id if you are teleporting the player to it once the player is dequeued
	});
end)

Players.PlayerRemoving:Connect(function(plr)
	InterserverQueueService.Filter(queueId, InterserverQueueService.Enum.FilterAction.Remove, {
		UserId = plr.UserId	
    -- filter checks for all specified items to be true, no need to specify irrelevant members 
	});
end)

-- In Game Server
Players.PlayerRemoving:Connect(function(plr)
	InterserverQueueService.Dequeue(queueId); 
end)




