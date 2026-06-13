--!strict
-- BoatMovementSystem
-- Drives each occupied boat: forward thrust along the hull's look vector (tapered
-- as it nears MaxSpeed), yaw torque from steering, and horizontal + angular water
-- drag opposing motion so the boat coasts to a stop and never spins out. All forces
-- are applied as impulses scaled by dt, so behaviour is frame-rate independent.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Packages.Matter)
local Components = require(ReplicatedStorage.Shared.Components)

local ZERO_INPUT = { throttle = 0, steer = 0 }

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
		local linVel = hull.AssemblyLinearVelocity
		local angVel = hull.AssemblyAngularVelocity

		-- --- Drag (always on, so an unmanned boat coasts to rest) ---
		-- Horizontal water resistance opposing planar velocity.
		local horizVel = Vector3.new(linVel.X, 0, linVel.Z)
		local dragImpulse = -horizVel * cfg.LinearDrag * dt
		hull:ApplyImpulse(dragImpulse)

		-- Angular resistance opposing yaw spin (about world up).
		local yawDragImpulse = Vector3.new(0, -angVel.Y * cfg.AngularDrag * dt, 0)
		hull:ApplyAngularImpulse(yawDragImpulse)

		-- --- Drive (only while someone is seated) ---
		if boat.seat.Occupant ~= nil then
			local input = state.boatInput[boat.owner] or ZERO_INPUT
			local throttle = math.clamp(input.throttle, -1, 1)
			local steer = math.clamp(input.steer, -1, 1)

			-- Forward thrust along the hull's facing, tapered toward MaxSpeed so the
			-- boat can't accelerate past the soft cap (taper hits 0 at MaxSpeed).
			if throttle ~= 0 then
				local look = hull.CFrame.LookVector
				local forwardSpeed = horizVel:Dot(look)
				local taper = math.clamp(1 - forwardSpeed / cfg.MaxSpeed, 0, 1)
				local thrust = throttle * cfg.DriveForce * taper
				hull:ApplyImpulse(look * thrust * dt)
			end

			-- Yaw torque from steering.
			if steer ~= 0 then
				local torque = steer * cfg.TurnTorque
				hull:ApplyAngularImpulse(Vector3.new(0, torque * dt, 0))
			end
		end
	end
end
