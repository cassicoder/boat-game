--!strict
-- Matter components. Boats are ECS ENTITIES the server tracks; the
-- BoatOwnershipSystem queries these. Component instances are immutable:
-- update with `world:insert(id, Comp({...}))`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Matter = require(ReplicatedStorage.Packages.Matter)

return {
	-- A physically-simulated part-sailboat the player sits on and drives.
	-- Terrain water floats it (native buoyancy); the driver's client owns the hull
	-- and drives it (see client BoatController). data = {
	--   model: Model,    -- the boat model (Parent = workspace.Boats)
	--   hull: BasePart,  -- PrimaryPart, unanchored
	--   seat: Seat,      -- the cockpit seat
	--   owner: Player?,  -- who spawned it
	-- }
	Boat = Matter.component("Boat"),
}
