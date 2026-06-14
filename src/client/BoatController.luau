--!strict
-- BoatController (client)
-- Smooth, client-authoritative sailboat driving. When the local player sits in a
-- boat seat the server hands THIS client network ownership of the hull, so we can set
-- the hull's velocity directly here every frame -- zero latency, crisp, and (because
-- we own it) nothing fights us. Terrain water provides float + drag + swimming for
-- free, so we only:
--   * read WASD locally (mobile pads feed setTouch),
--   * ease the HORIZONTAL velocity toward heading * throttle * TopSpeed, leaving the
--     vertical velocity to the water so it keeps floating,
--   * ease the yaw toward the steer, and self-level roll/pitch toward a gently
--     swaying "up" so it rocks like a real boat and can't capsize.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

local BoatController = {}

-- input state (keyboard + touch summed)
local keyT, keyS = 0, 0
local touchT, touchS = 0, 0
function BoatController.setTouch(throttle: number, steer: number)
	touchT, touchS = throttle, steer
end

local hull: BasePart? = nil

local function isBoatSeat(seat: Instance?): boolean
	local boats = Workspace:FindFirstChild("Boats")
	return seat ~= nil and boats ~= nil and seat:IsDescendantOf(boats)
end

local function bindCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Seated:Connect(function(active, seat)
		if active and isBoatSeat(seat) then
			local model = seat:FindFirstAncestorOfClass("Model")
			hull = (model and model.PrimaryPart) or nil
		else
			hull = nil
		end
	end)
end

function BoatController.start()
	local keyMap: { [Enum.KeyCode]: (number) -> () } = {
		[Enum.KeyCode.W] = function(v) keyT += v end,
		[Enum.KeyCode.S] = function(v) keyT -= v end,
		[Enum.KeyCode.A] = function(v) keyS -= v end,
		[Enum.KeyCode.D] = function(v) keyS += v end,
		[Enum.KeyCode.Up] = function(v) keyT += v end,
		[Enum.KeyCode.Down] = function(v) keyT -= v end,
		[Enum.KeyCode.Left] = function(v) keyS -= v end,
		[Enum.KeyCode.Right] = function(v) keyS += v end,
	}
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		local fn = keyMap[input.KeyCode]
		if fn then fn(1) end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local fn = keyMap[input.KeyCode]
		if fn then fn(-1) end
	end)

	if player.Character then bindCharacter(player.Character) end
	player.CharacterAdded:Connect(bindCharacter)

	local cfg = Config.Boat
	RunService.Heartbeat:Connect(function(dt)
		local h = hull
		if not h or not h.Parent then return end

		local throttle = math.clamp(keyT + touchT, -1, 1)
		local steer = math.clamp(keyS + touchS, -1, 1)
		local cf = h.CFrame

		-- HORIZONTAL thrust: ease velocity toward heading * throttle * TopSpeed; keep
		-- the vertical component so Terrain-water buoyancy keeps floating us.
		local look = cf.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local vel = h.AssemblyLinearVelocity
		local targetH = flat * (throttle * cfg.TopSpeed)
		local curH = Vector3.new(vel.X, 0, vel.Z)
		local newH = curH:Lerp(targetH, math.clamp(cfg.Accel * dt, 0, 1))
		h.AssemblyLinearVelocity = Vector3.new(newH.X, vel.Y, newH.Z)

		-- YAW: ease toward the steer target.
		local av = h.AssemblyAngularVelocity
		local targetYaw = steer * cfg.TurnRate
		local yaw = av.Y + (targetYaw - av.Y) * math.clamp(cfg.TurnAccel * dt, 0, 1)

		-- SELF-LEVEL with SWAY: build a gently rocking "up" (roll about forward, pitch
		-- about right) and drive the deck's up-vector toward it. up x desiredUp gives
		-- the world-space angular velocity that rotates us there -> never capsizes.
		local t = Workspace:GetServerTimeNow()
		local right = flat:Cross(Vector3.yAxis)
		right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
		local roll = math.sin(t * cfg.SwaySpeed) * cfg.SwayAmp
		local pitch = math.sin(t * cfg.SwaySpeed * 0.8 + 1.3) * cfg.SwayAmp
		local desiredUp = (Vector3.yAxis + right * roll + flat * pitch).Unit
		local correct = cf.UpVector:Cross(desiredUp) * cfg.Righting

		h.AssemblyAngularVelocity = Vector3.new(correct.X, yaw, correct.Z)
	end)
end

return BoatController
