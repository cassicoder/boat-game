--!strict
-- Server bootstrap: builds the Matter world, wires remotes, schedules systems.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Matter = require(ReplicatedStorage.Packages.Matter)
local Components = require(ReplicatedStorage.Shared.Components)
local Config = require(ReplicatedStorage.Shared.Config)

local serverRoot = script.Parent
local BoatFactory = require(serverRoot.BoatFactory)

local function makeFolder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local boatFolder = makeFolder("Boats", workspace)
local fishFolder = makeFolder("Fish", workspace)

local remotesFolder = makeFolder("Remotes", ReplicatedStorage)
local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotesFolder
	return r
end
local SpawnBoat = makeRemote("SpawnBoat")
local BoatInput = makeRemote("BoatInput")

local world = Matter.World.new()

-- Global state passed to every system as the 2nd argument.
local state = {
	config = Config,
	players = Players,
	boatFolder = boatFolder,
	fishFolder = fishFolder,
	boatInput = {} :: { [Player]: { throttle: number, steer: number } },
	remotes = { SpawnBoat = SpawnBoat, BoatInput = BoatInput },
}

-- Client asks to spawn a boat -> build it from parts and register the ECS entity.
SpawnBoat.OnServerEvent:Connect(function(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = (rootPart and rootPart.CFrame) or CFrame.new(0, Config.Ocean.BaseY, 0)
	local pos = (origin * CFrame.new(0, 0, -22)).Position
	local spawnCF = CFrame.new(Vector3.new(pos.X, Config.Ocean.BaseY + 4, pos.Z))

	local model, seat, floaters, hull = BoatFactory.build(spawnCF)
	model.Parent = boatFolder
	pcall(function()
		if hull:CanSetNetworkOwnership() then
			hull:SetNetworkOwner(nil) -- keep buoyancy/physics server-authoritative
		end
	end)

	world:spawn(Components.Boat({
		model = model,
		hull = hull,
		seat = seat,
		floaters = floaters,
		owner = player,
	}))
end)

-- Client streams its drive input for the boat it occupies.
BoatInput.OnServerEvent:Connect(function(player, throttle, steer)
	if typeof(throttle) ~= "number" or typeof(steer) ~= "number" then
		return
	end
	state.boatInput[player] = {
		throttle = math.clamp(throttle, -1, 1),
		steer = math.clamp(steer, -1, 1),
	}
end)

Players.PlayerRemoving:Connect(function(player)
	state.boatInput[player] = nil
end)

local loop = Matter.Loop.new(world, state)
loop:scheduleSystems({
	require(serverRoot.systems.BuoyancySystem),
	require(serverRoot.systems.BoatMovementSystem),
	require(serverRoot.systems.FishSpawnSystem),
	require(serverRoot.systems.FishAISystem),
})
loop:begin({ default = RunService.Heartbeat })

print("[BoatGame] server ECS online")
