--!strict
-- BoatHUD: visible only while the local player sits in a boat. Load-bearing info
-- (the speedometer) sits on the LEFT. Touch devices get on-screen throttle/steer
-- pads that feed the BoatController; on PC there are NO arrows -- you drive with
-- W/A/S/D (handled in the controller).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ACCENT = Color3.fromRGB(64, 196, 255)
local PANEL = Color3.fromRGB(12, 15, 20)
local TEXT = Color3.fromRGB(236, 241, 246)
local SUBTEXT = Color3.fromRGB(150, 162, 174)

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local BoatHUD = {}

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end
local function stroke(inst: Instance, color: Color3, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = inst
end

-- controller: the BoatController module (we forward touch input to it)
function BoatHUD.mount(controller)
	local gui = Instance.new("ScreenGui")
	gui.Name = "BoatHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ---- Speedometer (left, vertically centered) ----
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 18, 0.5, 70)
	panel.Size = UDim2.fromOffset(190, 106)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.2
	panel.Parent = gui
	corner(panel, 16)
	stroke(panel, Color3.fromRGB(255, 255, 255), 1, 0.86)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(18, 14)
	label.Size = UDim2.fromOffset(154, 14)
	label.Font = Enum.Font.GothamMedium
	label.Text = "SPEED"
	label.TextColor3 = SUBTEXT
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = panel

	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Position = UDim2.fromOffset(16, 26)
	value.Size = UDim2.fromOffset(154, 46)
	value.Font = Enum.Font.GothamBold
	value.Text = "0"
	value.TextColor3 = TEXT
	value.TextSize = 42
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Parent = panel

	local unit = Instance.new("TextLabel")
	unit.BackgroundTransparency = 1
	unit.Position = UDim2.fromOffset(18, 72)
	unit.Size = UDim2.fromOffset(154, 12)
	unit.Font = Enum.Font.Gotham
	unit.Text = "knots"
	unit.TextColor3 = SUBTEXT
	unit.TextSize = 11
	unit.TextXAlignment = Enum.TextXAlignment.Left
	unit.Parent = panel

	local barBg = Instance.new("Frame")
	barBg.Position = UDim2.new(0, 18, 1, -16)
	barBg.Size = UDim2.new(1, -36, 0, 4)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 46, 54)
	barBg.BorderSizePixel = 0
	barBg.Parent = panel
	corner(barBg, 2)
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = ACCENT
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	corner(barFill, 2)

	-- ---- touch input -> controller ----
	local touchT, touchS = 0, 0
	local function pushTouch()
		controller.setTouch(math.clamp(touchT, -1, 1), math.clamp(touchS, -1, 1))
	end

	if isTouch then
		local function pad(text: string, pos: UDim2, anchorX: number): TextButton
			local b = Instance.new("TextButton")
			b.AnchorPoint = Vector2.new(anchorX, 1)
			b.Position = pos
			b.Size = UDim2.fromOffset(76, 76)
			b.BackgroundColor3 = PANEL
			b.BackgroundTransparency = 0.18
			b.Text = text
			b.Font = Enum.Font.GothamBold
			b.TextColor3 = TEXT
			b.TextSize = 30
			b.Parent = gui
			corner(b, 20)
			stroke(b, Color3.fromRGB(255, 255, 255), 1, 0.85)
			return b
		end
		local left = pad("‹", UDim2.new(0, 24, 1, -28), 0)
		local right = pad("›", UDim2.new(0, 112, 1, -28), 0)
		local up = pad("▲", UDim2.new(1, -112, 1, -28), 1)
		local down = pad("▼", UDim2.new(1, -24, 1, -28), 1)

		local function hold(btn: TextButton, on: () -> (), off: () -> ())
			btn.MouseButton1Down:Connect(function() on(); pushTouch() end)
			btn.MouseButton1Up:Connect(function() off(); pushTouch() end)
		end
		hold(left, function() touchS = -1 end, function() touchS = 0 end)
		hold(right, function() touchS = 1 end, function() touchS = 0 end)
		hold(up, function() touchT = 1 end, function() touchT = 0 end)
		hold(down, function() touchT = -1 end, function() touchT = 0 end)
	else
		-- PC: a quiet hint, no arrows.
		local hint = Instance.new("TextLabel")
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -16)
		hint.Size = UDim2.fromOffset(380, 20)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.GothamMedium
		hint.Text = "W / S  throttle      A / D  steer"
		hint.TextColor3 = SUBTEXT
		hint.TextSize = 13
		hint.Parent = gui
	end

	-- ---- seat detection (show HUD + read speed) ----
	local seatPart: BasePart? = nil
	local function isBoatSeat(part: Instance?): boolean
		local boats = workspace:FindFirstChild("Boats")
		return part ~= nil and boats ~= nil and part:IsDescendantOf(boats)
	end

	local function bindCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Seated:Connect(function(active, seat)
			if active and isBoatSeat(seat) then
				seatPart = seat
				gui.Enabled = true
			else
				seatPart = nil
				gui.Enabled = false
				touchT, touchS = 0, 0
				pushTouch()
			end
		end)
	end
	if player.Character then bindCharacter(player.Character) end
	player.CharacterAdded:Connect(bindCharacter)

	RunService.RenderStepped:Connect(function()
		if seatPart and seatPart.Parent then
			local spd = seatPart.AssemblyLinearVelocity.Magnitude
			value.Text = tostring(math.floor(spd + 0.5))
			barFill.Size = UDim2.new(math.clamp(spd / Config.Boat.TopSpeed, 0, 1), 0, 1, 0)
		end
	end)
end

return BoatHUD
