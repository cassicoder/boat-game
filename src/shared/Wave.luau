--!strict
-- Wave.luau
-- Analytic Gerstner-wave ocean surface. PURE MATH, no Instances — this single
-- module is shared by BOTH the ocean renderer (visual vertex displacement) and
-- the buoyancy physics (surface-height sampling), so the water you see is the
-- exact water the boats float on.
--
-- Gerstner / trochoidal waves (ref: GPU Gems Ch.1). Each flat point (x,z) is
-- pushed along a circular orbit: it rises and also pulls toward wave crests,
-- which sharpens peaks and flattens troughs — the look of real ocean swell.

local Wave = {}

-- One wave layer. Sum several for a natural, non-repeating sea.
export type WaveDef = {
	direction: Vector2, -- travel direction in the XZ plane (need not be unit)
	wavelength: number, -- crest-to-crest distance, studs
	amplitude: number,  -- wave height, studs
	steepness: number,  -- 0..1 crest sharpness (too high = loops/artifacts)
	speed: number,      -- phase speed, studs/sec
}

-- Four layered swells: big slow primary + smaller faster chop on top.
local WAVES: { WaveDef } = {
	{ direction = Vector2.new( 1.0,  0.3), wavelength = 85, amplitude = 3.0, steepness = 0.55, speed = 11 },
	{ direction = Vector2.new(-0.6,  1.0), wavelength = 53, amplitude = 1.7, steepness = 0.50, speed = 9  },
	{ direction = Vector2.new( 0.4, -0.9), wavelength = 31, amplitude = 0.9, steepness = 0.45, speed = 7  },
	{ direction = Vector2.new(-1.0, -0.2), wavelength = 18, amplitude = 0.5, steepness = 0.40, speed = 5  },
}

local TAU = 2 * math.pi

-- Full Gerstner displacement of flat point (x, z) at time t.
-- Returns the world offset (dx, dy, dz) to ADD to the flat grid point — used by
-- the renderer to move each mesh vertex.
function Wave.GetDisplacement(x: number, z: number, t: number): Vector3
	local dx, dy, dz = 0.0, 0.0, 0.0
	for _, w in WAVES do
		local dir = w.direction.Unit
		local k = TAU / w.wavelength                         -- wave number
		local q = w.steepness / (k * w.amplitude * #WAVES)   -- loop-safe steepness
		local omega = w.speed * k                            -- angular frequency
		local theta = k * (dir.X * x + dir.Y * z) + omega * t
		local c, s = math.cos(theta), math.sin(theta)
		dx += q * w.amplitude * dir.X * c
		dz += q * w.amplitude * dir.Y * c
		dy += w.amplitude * s
	end
	return Vector3.new(dx, dy, dz)
end

-- Vertical surface height at flat (x, z). This is what BUOYANCY samples per
-- floater point. (The horizontal Gerstner pull is small, so sampling at the
-- query x,z directly is accurate enough and far cheaper than inverting it.)
function Wave.GetHeight(x: number, z: number, t: number): number
	local dy = 0.0
	for _, w in WAVES do
		local dir = w.direction.Unit
		local k = TAU / w.wavelength
		local omega = w.speed * k
		dy += w.amplitude * math.sin(k * (dir.X * x + dir.Y * z) + omega * t)
	end
	return dy
end

-- Approximate surface normal via finite differences of the height field.
-- Cheap; good enough for shading, foam, and aligning boats to the slope.
function Wave.GetNormal(x: number, z: number, t: number): Vector3
	local e = 0.5
	local hL = Wave.GetHeight(x - e, z, t)
	local hR = Wave.GetHeight(x + e, z, t)
	local hD = Wave.GetHeight(x, z - e, t)
	local hU = Wave.GetHeight(x, z + e, t)
	return Vector3.new(hL - hR, 2 * e, hD - hU).Unit
end

return Wave
