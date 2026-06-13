--!strict
-- FishAISystem
-- Steers every fish each frame: a timer-based random WANDER heading, gentle
-- SEPARATION from nearby fish, and a DEPTH-BAND pull that keeps each fish inside
-- [BaseY+DepthMin, BaseY+DepthMax] and never lets it breach the live wave
-- surface. Velocity is renormalized to a constant cruise speed, position is
-- integrated, and the model is faced along its heading. O(n^2) over ~45 fish.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Wave = require(ReplicatedStorage.Shared.Wave)
local Components = require(ReplicatedStorage.Shared.Components)
local Matter = require(ReplicatedStorage.Packages.Matter)

-- A fresh random heading. Mostly horizontal with a touch of vertical so fish
-- don't all swim in one flat plane.
local function randomHeading(): Vector3
	local angle = math.random() * 2 * math.pi
	local pitch = (math.random() - 0.5) * 0.6
	return Vector3.new(math.cos(angle), pitch, math.sin(angle)).Unit
end

return function(world, state)
	local dt = Matter.useDeltaTime()
	local t = workspace:GetServerTimeNow()

	local fishConfig = state.config.Fish
	local baseY = state.config.Ocean.BaseY
	local speed = fishConfig.Speed
	local turnRate = fishConfig.TurnRate
	local separation = fishConfig.Separation
	local depthMinY = baseY + fishConfig.DepthMin
	local depthMaxY = baseY + fishConfig.DepthMax

	-- Collect into a plain array first via the stable query iterator, so the
	-- O(n^2) separation pass reads stable values and we only write back after.
	local list = {}
	for id, fishC, posC, velC, wanderC in world:query(Components.Fish, Components.Position, Components.Velocity, Components.Wander) do
		table.insert(list, {
			id = id,
			model = fishC.model,
			pos = posC.value,
			vel = velC.value,
			dir = wanderC.dir,
			timer = wanderC.timer,
		})
	end

	for _, f in list do
		local pos = f.pos
		local vel = f.vel

		-- --- Wander: re-roll the target heading whenever the timer elapses. ---
		local timer = f.timer - dt
		local dir = f.dir
		if timer <= 0 then
			dir = randomHeading()
			timer = 1.5 + math.random() * 2.5
		end

		local steer = dir * speed

		-- --- Separation: push away from any fish inside the comfort radius. ---
		local sep = Vector3.zero
		for _, o in list do
			if o.id ~= f.id then
				local toMe = pos - o.pos
				local d = toMe.Magnitude
				if d > 0 and d < separation then
					sep += toMe.Unit * (separation - d) / separation
				end
			end
		end
		steer += sep * speed

		-- --- Depth band: steer back inside the swim layer, never breach. ---
		local surfaceY = baseY + Wave.GetHeight(pos.X, pos.Z, t)
		local ceilingY = math.min(depthMaxY, surfaceY - 1.5)
		if pos.Y > ceilingY then
			steer += Vector3.new(0, -speed, 0)
		elseif pos.Y < depthMinY then
			steer += Vector3.new(0, speed, 0)
		end

		-- --- Turn velocity toward the desired steer at a capped rate. ---
		if steer.Magnitude > 0 then
			local desired = steer.Unit * speed
			local newVel = vel + (desired - vel) * math.clamp(turnRate * dt, 0, 1)
			if newVel.Magnitude > 0 then
				vel = newVel.Unit * speed
			end
		end

		-- --- Integrate position, hard-clamped under the live surface. ---
		local newPos = pos + vel * dt
		local clampSurfaceY = baseY + Wave.GetHeight(newPos.X, newPos.Z, t)
		local maxY = math.min(depthMaxY, clampSurfaceY - 1.0)
		newPos = Vector3.new(newPos.X, math.clamp(newPos.Y, depthMinY, maxY), newPos.Z)

		-- --- Face the model along its velocity. ---
		if f.model.Parent ~= nil and f.model.PrimaryPart and vel.Magnitude > 0 then
			f.model.PrimaryPart.CFrame = CFrame.lookAt(newPos, newPos + vel)
		end

		-- --- Persist the updated state. ---
		world:insert(
			f.id,
			Components.Position({ value = newPos }),
			Components.Velocity({ value = vel }),
			Components.Wander({ dir = dir, timer = timer })
		)
	end
end
