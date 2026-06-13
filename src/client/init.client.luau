--!strict
-- Client bootstrap: lighting, the animated ocean, and the UI.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local clientRoot = script.Parent
local Config = require(ReplicatedStorage.Shared.Config)

local OceanRenderer = require(clientRoot.OceanRenderer)
local Lighting = require(clientRoot.Lighting)
local SpawnMenu = require(clientRoot.ui.SpawnMenu)
local BoatHUD = require(clientRoot.ui.BoatHUD)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	SpawnBoat = remotesFolder:WaitForChild("SpawnBoat") :: RemoteEvent,
	BoatInput = remotesFolder:WaitForChild("BoatInput") :: RemoteEvent,
}

Lighting.apply()
OceanRenderer.start(Config)
SpawnMenu.mount(remotes)
BoatHUD.mount(remotes)

print("[BoatGame] client online")
