--!strict
-- BuoyancySystem
-- Per floater on each boat, sample the SAME Gerstner surface the renderer draws
-- (Config.Ocean.BaseY + Wave.GetHeight at the floater's world XZ) and push the
-- hull up by how far the floater is submerged, damped against vertical velocity.
-- Spreading the floaters to the hull corners makes the boat roll and pitch with
-- the swell. Despawn boats whose model has been removed from the world.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Wave = require(ReplicatedStorage.Shared.Wave)
local Components = require(ReplicatedStorage.Shared.Components)

return function(world, state)
	-- Shared clock: identical t on client + server so visuals and physics agree.
	local t = workspace:GetServerTimeNow()
	local buoyancy = state.config.Buoyancy
	local baseY = state.config.Ocean.BaseY

	for id, boat in world:query(Components.Boat) do
		-- Boat was removed from the workspace (e.g. cleaned up) -> drop the entity.
		if boat.model.Parent == nil then
			world:despawn(id)
			continue
		end

		local hull = boat.hull
		local verticalVel = hull.AssemblyLinearVelocity.Y

		for _, vf in boat.floaters do
			local p = vf.Attachment0.WorldPosition
			local surfaceY = baseY + Wave.GetHeight(p.X, p.Z, t)
			local depth = surfaceY - p.Y -- how far this floater sits under the surface

			local upward = 0
			if depth > 0 then
				-- Spring up by submersion, bleed off vertical bounce.
				upward = depth * buoyancy.Strength - buoyancy.VerticalDamping * verticalVel
				if upward < 0 then
					upward = 0
				end
			end

			-- VectorForces are RelativeTo World (set by BoatFactory): push straight up.
			vf.Force = Vector3.new(0, upward, 0)
		end
	end
end
