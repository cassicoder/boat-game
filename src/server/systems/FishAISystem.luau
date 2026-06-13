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
	local pitch = (math.random() - 0.5) * 0.6 -- gentle up/down bias
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

	-- Snapshot so the O(n^2) separation pass reads stable positions while we
	-- write updated ones back via world:insert.
	local fish = world:query(Components.Fish, Components.Position, Components.Velocity, Components.Wander):snapshot()

	for _, entry in fish do
		local id = entry[1]
		local pos = entry[3].value :: Vector3
		local vel = entry[4].value :: Vector3
		local wander = entry[5]

		-- --- Wander: re-roll the target heading whenever the timer elapses. ---
		local timer = wander.timer - dt
		local dir = wander.dir
		if timer <= 0 then
			dir = randomHeading()
			timer = 1.5 + math.random() * 2.5 -- hold this heading 1.5-4s
		end

		-- Begin building this frame's desired steering from the wander heading.
		local steer = dir * speed

		-- --- Separation: push away from any fish inside the comfort radius. ---
		local sep = Vector3.zero
		for _, other in fish do
			if other[1] == id then
				continue
			end
			local toMe = pos - (other[3].value :: Vector3)
			local d = toMe.Magnitude
			if d > 0 and d < separation then
				-- Weight by closeness so the nearest neighbours shove hardest.
				sep += toMe.Unit * (separation - d) / separation
			end
		end
		steer += sep * speed

		-- --- Depth band: steer back inside the swim layer, and never breach. ---
		local surfaceY = baseY + Wave.GetHeight(pos.X, pos.Z, t)
		-- Stay at least a little under the actual wave surface.
		local ceilingY = math.min(depthMaxY, surfaceY - 1.5)
		if pos.Y > ceilingY then
			steer += Vector3.new(0, -speed, 0)
		elseif pos.Y < depthMinY then
			steer += Vector3.new(0, speed, 0)
		end

		-- --- Turn velocity toward the desired steer at a capped rate. ---
		if steer.Magnitude > 0 then
			local desired = steer.Unit * speed
			-- Move current heading toward desired, limited by turnRate*dt.
			local newVel = vel + (desired - vel) * math.clamp(turnRate * dt, 0, 1)
			if newVel.Magnitude > 0 then
				vel = newVel.Unit * speed
			end
		end

		-- --- Integrate position. ---
		local newPos = pos + vel * dt

		-- Hard clamp so a fish can never end up above the surface even mid-step.
		local clampSurfaceY = baseY + Wave.GetHeight(newPos.X, newPos.Z, t)
		local maxY = math.min(depthMaxY, clampSurfaceY - 1.0)
		newPos = Vector3.new(newPos.X, math.clamp(newPos.Y, depthMinY, maxY), newPos.Z)

		-- --- Face the model along its velocity. ---
		local fishData = entry[2]
		local model = fishData.model
		if model.Parent ~= nil and model.PrimaryPart and vel.Magnitude > 0 then
			model.PrimaryPart.CFrame = CFrame.lookAt(newPos, newPos + vel)
		end

		-- --- Persist the updated state. ---
		world:insert(
			id,
			Components.Position({ value = newPos }),
			Components.Velocity({ value = vel }),
			Components.Wander({ dir = dir, timer = timer })
		)
	end
end
