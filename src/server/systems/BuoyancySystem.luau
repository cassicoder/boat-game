--!strict
-- BuoyancySystem
-- Mass-calibrated, stable buoyancy. For each floater we sample the SAME Gerstner
-- surface the renderer draws and push up by how far the floater is submerged --
-- but the force is normalized so that at TargetSubmersion the floaters exactly
-- support the hull's weight, capped at MaxSubmersion so a deep dunk can never
-- produce an explosive impulse, and damped against the floater's vertical
-- velocity so the boat settles instead of launching. Spreading floaters to the
-- hull corners still lets it roll/pitch with the swell.
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
		local floaters = boat.floaters
		local count = #floaters
		if count == 0 then
			continue
		end

		-- Each floater carries an equal share of the hull's weight at rest.
		local perFloater = (hull.AssemblyMass * gravity) / count

		for _, vf in floaters do
			local att = vf.Attachment0
			if att then
				local p = att.WorldPosition
				local surfaceY = baseY + Wave.GetHeight(p.X, p.Z, t)
				local depth = surfaceY - p.Y -- how far this floater sits under the surface

				if depth > 0 then
					-- Normalized submersion: full weight support at TargetSubmersion,
					-- capped at MaxSubmersion so the force is always bounded.
					local submersion = math.min(depth, buoy.MaxSubmersion) / buoy.TargetSubmersion
					local up = perFloater * submersion

					-- Damp the floater's vertical velocity (mass-relative) so the hull
					-- settles onto the surface instead of bouncing/launching.
					local velY = hull:GetVelocityAtPosition(p).Y
					up -= buoy.Damping * perFloater * velY

					vf.Force = Vector3.new(0, math.max(up, 0), 0)
				else
					vf.Force = Vector3.zero
				end
			end
		end
	end
end
