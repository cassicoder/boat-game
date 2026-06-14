--!strict
-- Central tunables. Pure data -- required by the server bootstrap (ocean + boats)
-- and the client (boat controller + HUD). Tune live in Studio.
local Config = {
	Ocean = {
		Size = 8192,       -- studs: square of Terrain water (multiple of 4)
		Depth = 512,       -- studs: how deep the water body goes (top surface at BaseY)
		BaseY = 0,         -- sea level in world Y (the water surface)
		-- Desaturated teal -- a real open sea, not a pool. (Less blue per request.)
		WaterColor = Color3.fromRGB(34, 78, 74),
		WaterReflectance = 1,     -- full sky reflection (needs Lighting.Technology = Future)
		WaterTransparency = 0.2,  -- low = opaque deep ocean, a little depth tint
		WaterWaveSize = 0.3,      -- 0..1 studs (engine cap is 1); visible ocean chop
		WaterWaveSpeed = 14,      -- rolling swell speed
	},

	Boat = {
		TopSpeed = 70,      -- studs/s the boat eases up to at full throttle
		Accel = 1.4,        -- how fast velocity eases toward target (higher = snappier)
		TurnRate = 1.5,     -- yaw rate at full steer (rad/s)
		TurnAccel = 5,      -- how fast the turn eases in
		Righting = 4,       -- self-leveling gain (keeps it from capsizing)
		HullDensity = 0.5,  -- <1 floats on Terrain water; ~0.5 sits IN the water with a real waterline
		SwayAmp = 0.06,     -- radians of gentle roll/pitch rock so it sways like a real boat
		SwaySpeed = 0.85,   -- rock frequency
	},
}

return Config
