--!strict
-- Lighting.luau
-- Sets a pleasant mid-afternoon open-sea look: ClockTime ~14, atmosphere haze,
-- a clear sky, and subtle Bloom + ColorCorrection + SunRays post-effects.
-- Idempotent — apply() reuses existing instances by name, so it's safe to call
-- once on client start (or again after a respawn) without stacking effects.

local Lighting = game:GetService("Lighting")

local M = {}

-- Get a uniquely-named child of `parent` of `className`, creating it once.
local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	elseif existing then
		existing:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

function M.apply()
	-- Core daytime sea grading.
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 12
	Lighting.Brightness = 2.4
	Lighting.ExposureCompensation = 0.1
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 150, 170)
	Lighting.Ambient = Color3.fromRGB(70, 90, 105)
	Lighting.ColorShift_Top = Color3.fromRGB(245, 240, 220)
	Lighting.ShadowSoftness = 0.5
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000 -- atmosphere handles distance haze instead

	-- Thin sea-air atmosphere: a touch of haze, cool tint, bright sun glare.
	local atmos = ensure(Lighting, "Atmosphere", "SeaAtmosphere") :: Atmosphere
	atmos.Density = 0.32
	atmos.Offset = 0.1
	atmos.Color = Color3.fromRGB(199, 215, 224)
	atmos.Decay = Color3.fromRGB(106, 144, 168)
	atmos.Glare = 0.35
	atmos.Haze = 1.6

	-- Clear daytime sky.
	local sky = ensure(Lighting, "Sky", "SeaSky") :: Sky
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 0
	sky.StarCount = 0
	sky.CelestialBodiesShown = true

	-- Soft highlight bloom off the water sparkle.
	local bloom = ensure(Lighting, "BloomEffect", "SeaBloom") :: BloomEffect
	bloom.Intensity = 0.7
	bloom.Size = 24
	bloom.Threshold = 1.1

	-- Gentle warm-cool grade to make the sea read as inviting, not washed out.
	local cc = ensure(Lighting, "ColorCorrectionEffect", "SeaColorCorrection") :: ColorCorrectionEffect
	cc.Brightness = 0.02
	cc.Contrast = 0.08
	cc.Saturation = 0.12
	cc.TintColor = Color3.fromRGB(255, 250, 244)

	-- Subtle god-rays from the sun.
	local rays = ensure(Lighting, "SunRaysEffect", "SeaSunRays") :: SunRaysEffect
	rays.Intensity = 0.18
	rays.Spread = 0.9
end

return M
