--!strict
-- Central tunables. Pure data — required by both server systems and the client
-- ocean renderer. Tune these live once it's running in Studio.
local Config = {
	Ocean = {
		Size = 1000,        -- studs: full width of the ocean plane (it follows the camera)
		Resolution = 40,    -- grid cells per side (per-frame normal+color shading: keep modest)
		BaseY = 0,          -- sea level in world Y (studs)
		Color = Color3.fromRGB(16, 92, 126),
		Transparency = 0.08,
	},

	Boat = {
		DriveForce = 58,   -- forward acceleration per unit throttle (studs/s^2, mass-cancelled)
		TurnRate = 1.5,    -- max yaw rate while turning (rad/s)
		LinearDrag = 0.5,  -- horizontal velocity bleed-off per second
		RollDamp = 0.85,   -- per-frame retain factor for roll/pitch (lower = steadier)
		MaxSpeed = 105,    -- hard speed cap (studs/s)
	},

	Buoyancy = {
		FloaterCount = 4,        -- floaters BoatFactory spreads across the hull bottom
		TargetSubmersion = 0.55, -- studs the hull settles under the surface at rest
		MaxSubmersion = 4.0,     -- cap so a deep dunk can't produce an explosive force
		LiftBias = 1.7,          -- >1 floats the boat higher (more freeboard above water)
		Damping = 0.22,          -- vertical-velocity damping (mass-relative; kills launch)
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
