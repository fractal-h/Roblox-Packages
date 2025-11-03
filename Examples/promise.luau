-- Service
local Promise = require(path.to.Promise)

-- Example A
local fast = Promise.new(function(self)
	self:Yield(1)
	self:Resolve("Fast one!")
end)

local slow = Promise.new(function(self)
	self:Yield(3)
	self:Resolve("Slow one.")
end)

Promise.race({fast, slow}):Then(function(self, result)
	print("🏁 Winner:", result)
end)

-- Example B
local p1 = Promise.new(function(self)
	self:Yield(1)
	self:Resolve("Task 1 Complete")
end)

local p2 = Promise.new(function(self)
	self:Yield(2)
	self:Resolve("Task 2 Complete")
end)

local combined = Promise.all({p1, p2})

combined:Then(function(self, results)
	print("🎉 All tasks done:", table.concat(results, ", "))
end)

-- Example C
-- Create a promise that simulates loading data
local loadDataPromise = Promise.new(function(self, playerId)
	print("Loading data for player:", playerId)

	-- Simulate some async wait
	self:Yield(2)  -- equivalent to task.wait(2)

	-- Fake condition for success/failure
	if math.random() > 0.5 then
		self:Resolve({level = 10, gold = 500})
	else
		self:Reject("Failed to load player data.")
	end
end, 12345)

-- Chain promise handlers
loadDataPromise:Then(function(self, data)
		print("✅ Data loaded:", data.level, "Level,", data.gold, "Gold")
	end)
	:Catch(function(self, err)
		warn("❌ Error loading data:", err)
	end)
	:Finally(function(self)
		print("🔚 Load attempt finished for player.")
	end)
