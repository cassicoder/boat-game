--!strict
-- BoatHUD
-- Shows only while the LocalPlayer is seated in a boat seat (a Seat that lives
-- under workspace.Boats). Left side carries the load-bearing info: a live
-- speedometer (Isaac's left-bias). On-screen throttle/steer buttons mirror the
-- W/A/S/D keys; either source feeds the same combined input. Each time throttle
-- or steer changes we fire BoatInput(throttle, steer); standing up fires (0, 0).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

type Remotes = {
	SpawnBoat: RemoteEvent,
	BoatInput: RemoteEvent,
}

local BoatHUD = {}

-- Palette (shared with SpawnMenu): flat, neutral, dark-translucent.
local PANEL_BG = Color3.fromRGB(18, 20, 24)
local ACCENT = Color3.fromRGB(38, 132, 196)
local ACCENT_ON = Color3.fromRGB(52, 152, 219)
local CTRL_BG = Color3.fromRGB(34, 38, 44)
local TEXT = Color3.fromRGB(236, 240, 244)
local TEXT_DIM = Color3.fromRGB(150, 158, 168)

local FADE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Build a flat, rounded control button. `align` lays it inside a parent that
-- uses absolute positioning so we can shape a +/cross of arrows.
local function makeControl(parent: GuiObject, name: string, glyph: string, pos: UDim2): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = pos
	btn.Size = UDim2.fromOffset(56, 56)
	btn.BackgroundColor3 = CTRL_BG
	btn.BackgroundTransparency = 0.15
	btn.AutoButtonColor = false
	btn.Text = glyph
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 26
	btn.TextColor3 = TEXT
	btn.BorderSizePixel = 0
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = btn

	return btn
end

function BoatHUD.mount(remotes: Remotes)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BoatHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = playerGui

	-- ===== LEFT: speedometer (load-bearing info) =====
	local speedPanel = Instance.new("Frame")
	speedPanel.Name = "Speedometer"
	speedPanel.AnchorPoint = Vector2.new(0, 0.5)
	speedPanel.Position = UDim2.new(0, 24, 0.5, 0)
	speedPanel.Size = UDim2.fromOffset(150, 84)
	speedPanel.BackgroundColor3 = PANEL_BG
	speedPanel.BackgroundTransparency = 0.25
	speedPanel.BorderSizePixel = 0
	speedPanel.Parent = gui

	local speedCorner = Instance.new("UICorner")
	speedCorner.CornerRadius = UDim.new(0, 14)
	speedCorner.Parent = speedPanel

	local speedValue = Instance.new("TextLabel")
	speedValue.Name = "Value"
	speedValue.AnchorPoint = Vector2.new(0, 1)
	speedValue.Position = UDim2.new(0, 16, 1, -10)
	speedValue.Size = UDim2.new(1, -32, 0, 44)
	speedValue.BackgroundTransparency = 1
	speedValue.Text = "0"
	speedValue.Font = Enum.Font.GothamBold
	speedValue.TextSize = 40
	speedValue.TextColor3 = TEXT
	speedValue.TextXAlignment = Enum.TextXAlignment.Left
	speedValue.Parent = speedPanel

	local speedUnit = Instance.new("TextLabel")
	speedUnit.Name = "Unit"
	speedUnit.AnchorPoint = Vector2.new(0, 0)
	speedUnit.Position = UDim2.new(0, 16, 0, 12)
	speedUnit.Size = UDim2.new(1, -32, 0, 16)
	speedUnit.BackgroundTransparency = 1
	speedUnit.Text = "SPEED  ·  studs/s"
	speedUnit.Font = Enum.Font.GothamMedium
	speedUnit.TextSize = 12
	speedUnit.TextColor3 = TEXT_DIM
	speedUnit.TextXAlignment = Enum.TextXAlignment.Left
	speedUnit.Parent = speedPanel

	-- ===== RIGHT: quiet on-screen controls (D-pad of arrows) =====
	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.AnchorPoint = Vector2.new(1, 1)
	controls.Position = UDim2.new(1, -28, 1, -28)
	controls.Size = UDim2.fromOffset(184, 184)
	controls.BackgroundTransparency = 1
	controls.Parent = gui

	local upBtn = makeControl(controls, "Up", "▲", UDim2.new(0.5, 0, 0, 28))
	local downBtn = makeControl(controls, "Down", "▼", UDim2.new(0.5, 0, 1, -28))
	local leftBtn = makeControl(controls, "Left", "◀", UDim2.new(0, 28, 0.5, 0))
	local rightBtn = makeControl(controls, "Right", "▶", UDim2.new(1, -28, 0.5, 0))

	-- ===== Input state =====
	-- Throttle/steer are each the sum of (keyboard) and (on-screen) contributions,
	-- so holding W and tapping ▲ don't cancel; we clamp to -1..1 before sending.
	local keyThrottle, keySteer = 0, 0
	local btnThrottle, btnSteer = 0, 0
	local lastThrottle, lastSteer = 0, 0

	local function combine()
		return math.clamp(keyThrottle + btnThrottle, -1, 1), math.clamp(keySteer + btnSteer, -1, 1)
	end

	local function sendIfChanged()
		local throttle, steer = combine()
		if throttle ~= lastThrottle or steer ~= lastSteer then
			lastThrottle, lastSteer = throttle, steer
			remotes.BoatInput:FireServer(throttle, steer)
		end
	end

	-- ===== Boat-seat detection =====
	-- Treat a seat as a boat seat if its part is a descendant of workspace.Boats.
	local function isBoatSeat(part: BasePart?): boolean
		if not part then
			return false
		end
		local boats = Workspace:FindFirstChild("Boats")
		return boats ~= nil and part:IsDescendantOf(boats)
	end

	local seated = false
	local renderConn: RBXScriptConnection? = nil
	local seatPart: BasePart? = nil

	local function stopRender()
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
	end

	local function showHUD(part: BasePart)
		seated = true
		seatPart = part
		gui.Enabled = true
		stopRender()
		renderConn = RunService.RenderStepped:Connect(function()
			local p = seatPart
			if p then
				local speed = p.AssemblyLinearVelocity.Magnitude
				speedValue.Text = tostring(math.floor(speed + 0.5))
			end
		end)
	end

	local function hideHUD()
		if not seated then
			return
		end
		seated = false
		seatPart = nil
		gui.Enabled = false
		stopRender()
		-- Reset and force a (0, 0) on stand-up regardless of last value.
		keyThrottle, keySteer, btnThrottle, btnSteer = 0, 0, 0, 0
		lastThrottle, lastSteer = 0, 0
		remotes.BoatInput:FireServer(0, 0)
	end

	-- ===== On-screen control wiring (press = engage, release = let go) =====
	local function bindHold(btn: TextButton, onPress: () -> (), onRelease: () -> ())
		local function press()
			TweenService:Create(btn, FADE_TWEEN, { BackgroundColor3 = ACCENT_ON }):Play()
			onPress()
			sendIfChanged()
		end
		local function release()
			TweenService:Create(btn, FADE_TWEEN, { BackgroundColor3 = CTRL_BG }):Play()
			onRelease()
			sendIfChanged()
		end
		btn.MouseButton1Down:Connect(press)
		btn.MouseButton1Up:Connect(release)
		btn.MouseLeave:Connect(release)
	end

	bindHold(upBtn, function()
		btnThrottle = 1
	end, function()
		btnThrottle = 0
	end)
	bindHold(downBtn, function()
		btnThrottle = -1
	end, function()
		btnThrottle = 0
	end)
	bindHold(leftBtn, function()
		btnSteer = -1
	end, function()
		btnSteer = 0
	end)
	bindHold(rightBtn, function()
		btnSteer = 1
	end, function()
		btnSteer = 0
	end)

	-- ===== Keyboard (W/A/S/D) — only acts while seated in a boat =====
	local function onKey(input: InputObject, pressed: boolean)
		if not seated then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.W then
			keyThrottle = pressed and 1 or 0
		elseif key == Enum.KeyCode.S then
			keyThrottle = pressed and -1 or 0
		elseif key == Enum.KeyCode.A then
			keySteer = pressed and -1 or 0
		elseif key == Enum.KeyCode.D then
			keySteer = pressed and 1 or 0
		else
			return
		end
		sendIfChanged()
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		onKey(input, true)
	end)
	UserInputService.InputEnded:Connect(function(input)
		onKey(input, false)
	end)

	-- ===== Watch the character's Humanoid for seat changes =====
	local function bindCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid

		local function evaluate()
			local part = humanoid.SeatPart
			if humanoid.Sit and isBoatSeat(part) and part then
				if not seated or seatPart ~= part then
					showHUD(part)
				end
			else
				hideHUD()
			end
		end

		humanoid.Seated:Connect(evaluate)
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(evaluate)
		evaluate()
	end

	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		hideHUD()
		bindCharacter(character)
	end)
	player.CharacterRemoving:Connect(hideHUD)

	return gui
end

return BoatHUD
