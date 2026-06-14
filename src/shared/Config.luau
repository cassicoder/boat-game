--!strict
-- Central tunables. Pure data — required by both server systems and the client
-- ocean renderer. Tune these live once it's running in Studio.
local Config = {
	Ocean = {
		Size = 1000,        -- studs: full width of the ocean plane (it follows the camera)
		Resolution = 34,    -- grid cells per side (position+normal each frame -> modest = smooth)
		BaseY = 0,          -- sea level in world Y (studs)
		Color = Color3.fromRGB(16, 92, 126),
		Transparency = 0.1,
	},

	Boat = {
		DriveForce = 55,     -- forward acceleration per unit throttle (studs/s^2, mass-cancelled)
		TurnRate = 1.4,      -- yaw rate while steering (rad/s)
		OrientResponse = 14, -- AlignOrientation responsiveness (higher = snappier upright)
		WaveFollow = 0.5,    -- 0 = always flat, 1 = fully match the wave-surface tilt (lean into swells)
		LinearDrag = 0.5,    -- horizontal velocity bleed-off per second
		MaxSpeed = 90,       -- hard speed cap (studs/s)
	},

	Buoyancy = {
		TargetSubmersion = 0.6, -- studs the hull rides under the surface at rest
		Stiffness = 1.4,        -- restoring-force gain per (depth - target)/target
		MaxLift = 3.0,          -- upward force cap as a multiple of boat weight (no launch)
		Damping = 0.5,          -- vertical-velocity damping (kills bounce; mass-relative)
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
