--!strict
-- BoatMovementSystem
-- Drives each boat two ways, both stable:
--   * THRUST: a mass-cancelled horizontal impulse along the hull's facing (wave tilt
--     ignored), tapered toward MaxSpeed, with constant water drag and a hard speed cap.
--   * ROTATION: we never touch AssemblyAngularVelocity. Instead we set the boat's
--     AlignOrientation goal each frame -- the heading you steer (yaw) blended with a
--     gentle lean into the wave surface. The constraint eases the hull there, so it
--     turns smoothly and physically cannot capsize. Requires a server-owned hull.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matter = require(ReplicatedStorage.Packages.Matter)
local Components = require(ReplicatedStorage.Shared.Components)
local Wave = require(ReplicatedStorage.Shared.Wave)

local ZERO = { throttle = 0, steer = 0 }

-- Persistent steering heading per boat entity (radians); survives between frames.
local yawState: { [number]: number } = {}

-- Inverse of CFrame.Angles(0, yaw, 0).LookVector = Vector3.new(-sin yaw, 0, -cos yaw).
local function yawFromLook(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

return function(world, state)
	local dt = Matter.useDeltaTime()
	if dt <= 0 then
		return
	end
	local cfg = state.config.Boat
	local t = workspace:GetServerTimeNow()
	local seen: { [number]: boolean } = {}

	for id, boat in world:query(Components.Boat) do
		if boat.model.Parent == nil then
			continue
		end
		local hull = boat.hull
		local align = boat.align
		if not align then
			continue
		end
		seen[id] = true

		local mass = hull.AssemblyMass
		local linVel = hull.AssemblyLinearVelocity
		local horiz = Vector3.new(linVel.X, 0, linVel.Z)
		local speed = horiz.Magnitude

		-- Seed the heading from the hull's current facing the first time we see it.
		local yaw = yawState[id]
		if yaw == nil then
			yaw = yawFromLook(hull.CFrame.LookVector)
			yawState[id] = yaw
		end

		-- Constant horizontal water drag (mass-cancelled -> fixed decel rate).
		hull:ApplyImpulse(-horiz * (cfg.LinearDrag * mass * dt))

		local steer = 0
		if boat.seat.Occupant ~= nil then
			local input = state.boatInput[boat.owner] or ZERO
			local throttle = math.clamp(input.throttle, -1, 1)
			steer = math.clamp(input.steer, -1, 1)

			if throttle ~= 0 then
				local look = hull.CFrame.LookVector
				local fwd = Vector3.new(look.X, 0, look.Z) -- thrust stays horizontal
				if fwd.Magnitude > 0.05 then
					fwd = fwd.Unit
					local forwardSpeed = horiz:Dot(fwd)
					local rel = if throttle > 0 then forwardSpeed else -forwardSpeed
					local taper = math.clamp(1 - rel / cfg.MaxSpeed, 0, 1)
					hull:ApplyImpulse(fwd * (throttle * cfg.DriveForce * mass * taper * dt))
				end
			end
		end

		-- Steer the heading: turn faster with speed, but keep a little turn at rest so
		-- the boat is still maneuverable when stopped (no full spin-in-place though).
		local steerAuth = math.clamp(speed / 6, 0.25, 1)
		yaw += -steer * cfg.TurnRate * steerAuth * dt
		yawState[id] = yaw

		-- Build the goal orientation: face `yaw`, leaning partway into the wave surface.
		local pos = hull.Position
		local n = Wave.GetNormal(pos.X, pos.Z, t) -- ~vertical, so the lean is always small
		local up = Vector3.yAxis:Lerp(n, cfg.WaveFollow)
		if up.Magnitude < 1e-3 then
			up = Vector3.yAxis
		end
		up = up.Unit
		local fwd = CFrame.Angles(0, yaw, 0).LookVector
		fwd = fwd - up * fwd:Dot(up) -- project flat heading onto the tilted deck plane
		if fwd.Magnitude < 1e-3 then
			fwd = Vector3.new(0, 0, -1)
		end
		fwd = fwd.Unit
		local right = fwd:Cross(up) -- RightVector = Look x Up
		align.CFrame = CFrame.fromMatrix(Vector3.zero, right, up, -fwd)

		-- Hard planar speed cap so nothing can fling the boat across the map.
		if speed > cfg.MaxSpeed then
			local capped = horiz.Unit * cfg.MaxSpeed
			hull.AssemblyLinearVelocity = Vector3.new(capped.X, linVel.Y, capped.Z)
		end
	end

	-- Forget headings for boats that despawned.
	for trackedId in yawState do
		if not seen[trackedId] then
			yawState[trackedId] = nil
		end
	end
end
