--!strict
-- BoatMovementSystem
-- Arcade-stable boat driving. Thrust is applied HORIZONTALLY (wave tilt ignored)
-- as a mass-cancelled impulse, so the constants read as accelerations and a
-- heavier (occupied) boat handles the same. Steering and roll/pitch are handled
-- by writing the assembly's angular velocity directly -- it physically cannot
-- tumble -- and the planar speed is hard-capped. Requires the hull to be
-- server-owned (the bootstrap re-asserts this after a player sits).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Packages.Matter)
local Components = require(ReplicatedStorage.Shared.Components)

local ZERO = { throttle = 0, steer = 0 }

return function(world, state)
	local dt = Matter.useDeltaTime()
	if dt <= 0 then
		return
	end
	local cfg = state.config.Boat

	for _, boat in world:query(Components.Boat) do
		if boat.model.Parent == nil then
			continue
		end

		local hull = boat.hull
		local mass = hull.AssemblyMass
		local linVel = hull.AssemblyLinearVelocity
		local horiz = Vector3.new(linVel.X, 0, linVel.Z)

		-- Horizontal water drag (always on; mass-cancelled -> fixed decel rate).
		hull:ApplyImpulse(-horiz * (cfg.LinearDrag * mass * dt))

		local steer = 0
		if boat.seat.Occupant ~= nil then
			local input = state.boatInput[boat.owner] or ZERO
			local throttle = math.clamp(input.throttle, -1, 1)
			steer = math.clamp(input.steer, -1, 1)

			if throttle ~= 0 then
				local look = hull.CFrame.LookVector
				local fwd = Vector3.new(look.X, 0, look.Z)
				if fwd.Magnitude > 0.05 then
					fwd = fwd.Unit
					local forwardSpeed = horiz:Dot(fwd)
					-- Taper toward MaxSpeed in whichever direction we're pushing.
					local rel = if throttle > 0 then forwardSpeed else -forwardSpeed
					local taper = math.clamp(1 - rel / cfg.MaxSpeed, 0, 1)
					hull:ApplyImpulse(fwd * (throttle * cfg.DriveForce * mass * taper * dt))
				end
			end
		end

		-- Steering + stability: drive yaw directly and bleed off roll/pitch so the
		-- boat can never tumble. Yaw authority scales with speed (no spin-in-place).
		local speedFactor = math.clamp(horiz.Magnitude / 6, 0, 1)
		local av = hull.AssemblyAngularVelocity
		hull.AssemblyAngularVelocity = Vector3.new(
			av.X * cfg.RollDamp,
			-steer * cfg.TurnRate * speedFactor,
			av.Z * cfg.RollDamp
		)

		-- Hard planar speed cap so nothing can fling the boat across the map.
		if horiz.Magnitude > cfg.MaxSpeed then
			local capped = horiz.Unit * cfg.MaxSpeed
			hull.AssemblyLinearVelocity = Vector3.new(capped.X, linVel.Y, capped.Z)
		end
	end
end
