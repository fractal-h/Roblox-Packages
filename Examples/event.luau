-- Services
local Event = require(script.event);

-- Events
local DoSomething = Event.new();

-- Event Fire Bound Functions
local BoundFunction = DoSomething:BindFire();

-- Event Bound Functions
local function SomethingSignalFunction(textToPrint: string, randomValue: number)
  print(textToPrint, randomValue);
end

-- Constructor for connections
local function AddConnection()
  local randomNumber = math.random(1,1000);
  DoSomething:Connect(SomethingSignalFunction, randomNumber);
end

-- Add in connections
for i = 1, 100 do 
  AddConnection();
end

-- Signal the event
DoSomething:Fire("Hello, world!");

-- Signal the event using the bound function
BoundFunction("Goodbye, world!");

-- Destroy the event
DoSomething:Destroy();
