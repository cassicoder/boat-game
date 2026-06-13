--!strict
-- SpawnMenu
-- One prominent "Spawn Boat" button anchored bottom-LEFT (Isaac's left-bias: the
-- load-bearing action sits where the eye lands). Flat dark translucent panel,
-- rounded corners, subtle TweenService hover/press states. No gradients.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

type Remotes = {
	SpawnBoat: RemoteEvent,
	BoatInput: RemoteEvent,
}

local SpawnMenu = {}

-- Palette (shared with BoatHUD): flat, neutral, dark-translucent.
local PANEL_BG = Color3.fromRGB(18, 20, 24)
local ACCENT = Color3.fromRGB(38, 132, 196)
local ACCENT_HOVER = Color3.fromRGB(52, 152, 219)
local ACCENT_PRESS = Color3.fromRGB(28, 104, 158)
local TEXT = Color3.fromRGB(236, 240, 244)

local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function SpawnMenu.mount(remotes: Remotes)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpawnMenu"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- Bottom-left anchored button.
	local button = Instance.new("TextButton")
	button.Name = "SpawnButton"
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, 24, 1, -24)
	button.Size = UDim2.fromOffset(196, 52)
	button.BackgroundColor3 = ACCENT
	button.AutoButtonColor = false
	button.Text = "🚤  Spawn Boat"
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.TextColor3 = TEXT
	button.BorderSizePixel = 0
	button.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button

	-- A whisper of a dark border so the button reads against bright water.
	local stroke = Instance.new("UIStroke")
	stroke.Color = PANEL_BG
	stroke.Transparency = 0.4
	stroke.Thickness = 1
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = button

	-- Hover / press polish via TweenService.
	local function tweenTo(color: Color3, info: TweenInfo)
		TweenService:Create(button, info, { BackgroundColor3 = color }):Play()
	end

	button.MouseEnter:Connect(function()
		tweenTo(ACCENT_HOVER, HOVER_TWEEN)
	end)
	button.MouseLeave:Connect(function()
		tweenTo(ACCENT, HOVER_TWEEN)
	end)
	button.MouseButton1Down:Connect(function()
		tweenTo(ACCENT_PRESS, PRESS_TWEEN)
	end)
	button.MouseButton1Up:Connect(function()
		tweenTo(ACCENT_HOVER, PRESS_TWEEN)
	end)

	button.Activated:Connect(function()
		remotes.SpawnBoat:FireServer()
	end)

	return gui
end

return SpawnMenu
