--!strict
-- Matter components. Boats and fish are ECS ENTITIES; server systems query these.
-- Component instances are immutable: update with `world:insert(id, Comp({...}))`
-- or `world:insert(id, instance:patch({field = value}))`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Matter = require(ReplicatedStorage.Packages.Matter)

return {
	-- A physically-simulated part-boat the player sits on and drives.
	-- data = {
	--   model: Model,            -- the boat model (Parent = workspace.Boats)
	--   hull: BasePart,          -- PrimaryPart, unanchored, server-owned physics
	--   seat: Seat,              -- the seat you sit on
	--   floaters: {VectorForce}, -- single centred buoyancy force (drives the Y bob only)
	--   align: AlignOrientation, -- owns the hull's rotation (steer yaw + wave lean; anti-capsize)
	--   owner: Player,           -- who spawned it (drives via state.boatInput[owner])
	-- }
	Boat = Matter.component("Boat"),

	-- A kinematic fish. AI writes Velocity/Position each frame and moves the model.
	-- data = { model: Model }   (model.PrimaryPart is Anchored; AI sets its CFrame)
	Fish = Matter.component("Fish"),

	-- data = { value: Vector3 } — world position (fish)
	Position = Matter.component("Position"),

	-- data = { value: Vector3 } — current velocity (fish)
	Velocity = Matter.component("Velocity"),

	-- data = { dir: Vector3, timer: number } — wander steering state (fish)
	Wander = Matter.component("Wander"),
}
