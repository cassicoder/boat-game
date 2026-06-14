--!strict
-- Client bootstrap: lighting, the boat controller, and the UI. The ocean is Terrain
-- water (built on the server), so there's no client ocean renderer anymore.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local clientRoot = script.Parent

local Lighting = require(clientRoot.Lighting)
local BoatController = require(clientRoot.BoatController)
local SpawnMenu = require(clientRoot.ui.SpawnMenu)
local BoatHUD = require(clientRoot.ui.BoatHUD)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	SpawnBoat = remotesFolder:WaitForChild("SpawnBoat") :: RemoteEvent,
}

Lighting.apply()
BoatController.start()
SpawnMenu.mount(remotes)
BoatHUD.mount(BoatController)

print("[BoatGame] client online")
