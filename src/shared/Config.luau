--!strict
-- Central tunables. Pure data — required by both server systems and the client
-- ocean renderer. Tune these live once it's running in Studio.
local Config = {
	Ocean = {
		Size = 1200,        -- studs: full width of the ocean plane (it follows the camera)
		Resolution = 48,    -- grid cells per side for the EditableMesh (48x48 quads)
		BaseY = 0,          -- sea level in world Y (studs)
		Color = Color3.fromRGB(26, 92, 122),
		Transparency = 0.28,
	},

	Boat = {
		DriveForce = 28000, -- forward push per unit of throttle (-1..1)
		TurnTorque = 11000, -- yaw torque per unit of steer (-1..1)
		LinearDrag = 1200,  -- water resistance: force opposing horizontal velocity
		AngularDrag = 2500, -- resistance opposing yaw spin
		MaxSpeed = 70,      -- soft cap (studs/s) used to taper drive force
	},

	Buoyancy = {
		FloaterCount = 4,        -- floaters BoatFactory spreads across the hull bottom
		Strength = 26000,        -- upward force per stud of submersion, per floater
		VerticalDamping = 1800,  -- opposes vertical velocity at each floater (kills bounce)
	},

	Fish = {
		MaxCount = 45,
		SpawnRadius = 220,  -- spawn fish within this distance of a player
		DespawnRadius = 320,-- cull fish beyond this distance from every player
		Speed = 13,         -- cruise speed (studs/s)
		TurnRate = 2.5,     -- how fast a fish can change heading (rad/s)
		DepthMin = -26,     -- deepest a fish swims (below BaseY)
		DepthMax = -5,      -- shallowest a fish swims (below the surface)
		Separation = 8,     -- comfortable spacing between fish (studs)
	},
}

return Config
