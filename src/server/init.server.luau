--!strict
-- Server bootstrap: clears the baseplate, fills a big body of Terrain water (which
-- floats the boats natively and lets players swim), spawns every player into their
-- own sailboat, and runs a tiny Matter ECS whose one system keeps each boat owned by
-- whoever is sitting in it (so the driver's client drives it smoothly).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Matter = require(ReplicatedStorage.Packages.Matter)
local Components = require(ReplicatedStorage.Shared.Components)
local Config = require(ReplicatedStorage.Shared.Config)

local serverRoot = script.Parent
local BoatFactory = require(serverRoot.BoatFactory)

-- The ocean is the world now: remove the baseplate + default spawn.
for _, name in { "Baseplate", "SpawnLocation" } do
	local existing = workspace:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Ocean: one big block of Terrain water, surface at BaseY. Native buoyancy floats
-- unanchored parts and Humanoids swim in it automatically.
--------------------------------------------------------------------------------
local Terrain = workspace.Terrain
do
	local o = Config.Ocean
	-- snap to the 4-stud voxel grid
	local size = math.floor(o.Size / 4) * 4
	local depth = math.floor(o.Depth / 4) * 4
	-- top surface at BaseY => centre at BaseY - depth/2
	Terrain:FillBlock(
		CFrame.new(0, o.BaseY - depth / 2, 0),
		Vector3.new(size, depth, size),
		Enum.Material.Water
	)
	Terrain.WaterColor = o.WaterColor
	Terrain.WaterReflectance = o.WaterReflectance
	Terrain.WaterTransparency = o.WaterTransparency
	Terrain.WaterWaveSize = o.WaterWaveSize
	Terrain.WaterWaveSpeed = o.WaterWaveSpeed
end

local function makeFolder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local boatFolder = makeFolder("Boats", workspace)

local remotesFolder = makeFolder("Remotes", ReplicatedStorage)
local SpawnBoat = Instance.new("RemoteEvent")
SpawnBoat.Name = "SpawnBoat"
SpawnBoat.Parent = remotesFolder

local world = Matter.World.new()
local state = {
	config = Config,
	players = Players,
	boatFolder = boatFolder,
}

-- Build a boat entity at a CFrame and register it in the ECS.
local function spawnBoat(owner: Player?, cframe: CFrame): (number, Seat, Model)
	local model, seat, hull = BoatFactory.build(cframe)
	model.Parent = boatFolder
	local id = world:spawn(Components.Boat({
		model = model,
		hull = hull,
		seat = seat,
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
	local spawnPos = Vector3.new(math.cos(angle) * 30, Config.Ocean.BaseY + 3, math.sin(angle) * 30)
	local id, seat, model = spawnBoat(player, CFrame.new(spawnPos))
	playerBoats[player] = { id = id, model = model }

	-- drop the character onto the seat and sit them down
	task.wait(0.1)
	if character.Parent and humanoid.Health > 0 then
		character:PivotTo(seat.CFrame * CFrame.new(0, 2.5, 0))
		seat:Sit(humanoid)
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

-- Spawn menu requests an EXTRA boat just in front of the player.
SpawnBoat.OnServerEvent:Connect(function(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = (rootPart and rootPart.CFrame) or CFrame.new(0, Config.Ocean.BaseY, 0)
	local pos = (origin * CFrame.new(0, 0, -26)).Position
	spawnBoat(player, CFrame.new(Vector3.new(pos.X, Config.Ocean.BaseY + 3, pos.Z)))
end)

Players.PlayerRemoving:Connect(function(player)
	playerBoats[player] = nil
end)

local loop = Matter.Loop.new(world, state)
loop:scheduleSystems({
	require(serverRoot.systems.BoatOwnershipSystem),
})
loop:begin({ default = RunService.Heartbeat })

print("[BoatGame] server online -- ocean filled, sailboats ready")
