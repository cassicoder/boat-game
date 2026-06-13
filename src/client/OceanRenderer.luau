--!strict
-- OceanRenderer.luau
-- The ocean is now Roblox Terrain Water (native, realistic, and performant — no
-- per-frame mesh skinning). It's generated into the place and tuned via Terrain's
-- water properties (color / transparency / reflectance / wave size + speed), and
-- the boats float on it with Roblox's built-in water buoyancy.
--
-- This module is intentionally a no-op, kept so the client bootstrap's
-- require/start call stays valid. To switch back to a custom Gerstner mesh, restore
-- the previous implementation from git history.
local OceanRenderer = {}

function OceanRenderer.start(_config)
	-- intentionally empty: Terrain Water is the ocean
end

return OceanRenderer
