--!strict
-- BuoyancySystem
-- One centred, mass-calibrated buoyancy force per boat. We sample the SAME Gerstner
-- surface the renderer draws and push UP with a clamped restoring spring: it exactly
-- supports the hull's weight at TargetSubmersion, rises with depth but is capped at
-- MaxLift*weight so a deep dunk can never launch the boat, drops to zero once the
-- point clears the surface, and is damped against vertical velocity so the hull
-- settles instead of bobbing forever. The force acts through the centre of mass, so
-- it only ever moves the boat in Y -- rotation is owned by the AlignOrientation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Wave = require(ReplicatedStorage.Shared.Wave)
local Components = require(ReplicatedStorage.Shared.Components)

return function(world, state)
	local t = workspace:GetServerTimeNow() -- shared clock: physics matches visuals
	local baseY = state.config.Ocean.BaseY
	local buoy = state.config.Buoyancy
	local gravity = workspace.Gravity

	for id, boat in world:query(Components.Boat) do
		if boat.model.Parent == nil then
			world:despawn(id)
			continue
		end

		local hull = boat.hull
		local vf = boat.floaters[1]
		if not vf then
			continue
		end
		local att = vf.Attachment0
		if not att then
			continue
		end

		local p = att.WorldPosition
		local surfaceY = baseY + Wave.GetHeight(p.X, p.Z, t)
		local depth = surfaceY - p.Y -- how far the hull centre sits under the surface

		local weight = hull.AssemblyMass * gravity -- force needed to hold it up
		local lift = 0
		if depth > 0 then
			-- Clamped restoring spring: = weight at TargetSubmersion, capped at MaxLift.
			local s = 1 + buoy.Stiffness * (depth - buoy.TargetSubmersion) / buoy.TargetSubmersion
			lift = math.clamp(s, 0, buoy.MaxLift) * weight
			-- Damp vertical velocity (mass-relative) so it settles onto the surface.
			local velY = hull:GetVelocityAtPosition(p).Y
			lift -= buoy.Damping * weight * velY
		end

		vf.Force = Vector3.new(0, math.max(lift, 0), 0)
	end
end
