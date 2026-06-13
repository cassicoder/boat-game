--!strict
-- SpawnMenu: one polished "Spawn Boat" button, top-LEFT (clear of the speedometer
-- and the mobile control pads). Flat dark translucent panel, rounded, accent
-- outline, subtle hover/press tweens. No gradients.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ACCENT = Color3.fromRGB(64, 196, 255)
local PANEL = Color3.fromRGB(12, 15, 20)
local TEXT = Color3.fromRGB(236, 241, 246)

local player = Players.LocalPlayer
local SpawnMenu = {}

function SpawnMenu.mount(remotes)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpawnMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(0, 0)
	btn.Position = UDim2.new(0, 18, 0, 18)
	btn.Size = UDim2.fromOffset(182, 48)
	btn.BackgroundColor3 = PANEL
	btn.BackgroundTransparency = 0.12
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = btn
	local s = Instance.new("UIStroke")
	s.Color = ACCENT
	s.Thickness = 1.4
	s.Transparency = 0.25
	s.Parent = btn

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(14, 0)
	icon.Size = UDim2.new(0, 30, 1, 0)
	icon.Font = Enum.Font.GothamBold
	icon.Text = "🚤"
	icon.TextSize = 22
	icon.Parent = btn

	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Position = UDim2.fromOffset(48, 0)
	txt.Size = UDim2.new(1, -58, 1, 0)
	txt.Font = Enum.Font.GothamBold
	txt.Text = "Spawn Boat"
	txt.TextColor3 = TEXT
	txt.TextSize = 16
	txt.TextXAlignment = Enum.TextXAlignment.Left
	txt.Parent = btn

	local function tween(props)
		TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), props):Play()
	end
	btn.MouseEnter:Connect(function()
		tween({ BackgroundTransparency = 0.0 })
		s.Transparency = 0
	end)
	btn.MouseLeave:Connect(function()
		tween({ BackgroundTransparency = 0.12 })
		s.Transparency = 0.25
	end)
	btn.MouseButton1Down:Connect(function()
		tween({ Size = UDim2.fromOffset(174, 46) })
	end)
	btn.MouseButton1Up:Connect(function()
		tween({ Size = UDim2.fromOffset(182, 48) })
	end)
	btn.Activated:Connect(function()
		remotes.SpawnBoat:FireServer()
	end)
end

return SpawnMenu
