--!strict
-- Server bootstrap: builds the Matter world, wires remotes, schedules systems,
-- clears the baseplate, and spawns every player seated in their own boat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Matter = require(ReplicatedStorage.Packages.Matter)
local Components = require(ReplicatedStorage.Shared.Components)
local Config = require(ReplicatedStorage.Shared.Config)

local serverRoot = script.Parent
local BoatFactory = require(serverRoot.BoatFactory)

-- The ocean is the world now: remove the baseplate and default spawn so nothing
-- blocks the view or hangs in the sky.
for _, name in { "Baseplate", "SpawnLocation" } do
	local existing = workspace:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

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

local state = {
	config = Config,
	players = Players,
	boatFolder = boatFolder,
	fishFolder = fishFolder,
	boatInput = {} :: { [Player]: { throttle: number, steer: number } },
	remotes = { SpawnBoat = SpawnBoat, BoatInput = BoatInput },
}

-- Build a boat entity at a CFrame and register it in the ECS.
local function spawnBoat(owner: Player?, cframe: CFrame): (number, Seat, Model)
	local model, seat, floaters, hull = BoatFactory.build(cframe)
	model.Parent = boatFolder
	pcall(function()
		if hull:CanSetNetworkOwnership() then
			hull:SetNetworkOwner(nil) -- keep buoyancy/physics server-authoritative
		end
	end)
	local id = world:spawn(Components.Boat({
		model = model,
		hull = hull,
		seat = seat,
		floaters = floaters,
		owner = owner,
	}))
	return id, seat, model
end

-- Each player gets their own boat to spawn into; a respawn replaces it.
local playerBoats: { [Player]: { id: number, model: Model } } = {}

local function giveBoat(player: Player, character: Model)
	local prev = playerBoats[player]
	if prev then
		if world:contains(prev.id) then
			world:despawn(prev.id)
		end
		if prev.model.Parent then
			prev.model:Destroy()
		end
		playerBoats[player] = nil
	end

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	-- spread spawns around the origin so players don't stack
	local angle = (player.UserId % 12) * (math.pi * 2 / 12)
	local spawnPos = Vector3.new(math.cos(angle) * 26, Config.Ocean.BaseY + 5, math.sin(angle) * 26)
	local id, seat, model = spawnBoat(player, CFrame.new(spawnPos))
	playerBoats[player] = { id = id, model = model }

	-- drop the character onto the seat and sit them down
	task.wait(0.1)
	if character.Parent and humanoid.Health > 0 then
		character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
		seat:Sit(humanoid)
		-- Re-assert server ownership: sitting hands the assembly to the client,
		-- which would fight the server's buoyancy/drive forces (the "going crazy").
		task.wait(0.2)
		if model.PrimaryPart then
			pcall(function()
				if model.PrimaryPart:CanSetNetworkOwnership() then
					model.PrimaryPart:SetNetworkOwner(nil)
				end
			end)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(giveBoat, player, character)
	end)
	if player.Character then
		task.defer(giveBoat, player, player.Character)
	end
end)

-- Spawn menu requests an EXTRA boat in front of the player.
SpawnBoat.OnServerEvent:Connect(function(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = (rootPart and rootPart.CFrame) or CFrame.new(0, Config.Ocean.BaseY, 0)
	local pos = (origin * CFrame.new(0, 0, -22)).Position
	spawnBoat(player, CFrame.new(Vector3.new(pos.X, Config.Ocean.BaseY + 4, pos.Z)))
end)

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
	playerBoats[player] = nil
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
