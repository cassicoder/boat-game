--!strict
-- Builds a part-only boat (no meshes, no toolbox): a flat hull base, low side walls,
-- a pointed wedge bow, and a welded Seat. Only the hull simulates physics; everything
-- else is welded to it and Massless. The hull carries the buoyancy floaters (bottom
-- Attachments + World-relative VectorForces the BuoyancySystem drives each frame).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

-- Hull footprint (studs). Boat faces -Z (forward look = -Z).
local HULL_W = 8 -- X (width)
local HULL_H = 2 -- Y (height)
local HULL_L = 16 -- Z (length)

local HULL_BROWN = Color3.fromRGB(102, 70, 44)
local WALL_TAN = Color3.fromRGB(150, 111, 71)
local ACCENT = Color3.fromRGB(64, 44, 28)
local SEAT_COLOR = Color3.fromRGB(58, 41, 27)

local BoatFactory = {}

-- Make a decorative (welded, non-simulating) part.
local function makeDeco(name: string, size: Vector3, color: Color3, canCollide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.WoodPlanks
	p.Anchored = false
	p.CanCollide = canCollide
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- Weld a part to the hull and parent it under the model.
local function weldTo(part: BasePart, hull: BasePart, model: Model, cf: CFrame)
	part.CFrame = cf
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hull
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
end

-- cframe: where to place the boat. Returns (model, seat, floaters, hull).
function BoatFactory.build(cframe: CFrame): (Model, Seat, { VectorForce }, BasePart)
	local model = Instance.new("Model")
	model.Name = "Boat"

	-- Hull base: the one and only simulated part.
	local hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Size = Vector3.new(HULL_W, HULL_H, HULL_L)
	hull.Color = HULL_BROWN
	hull.Material = Enum.Material.WoodPlanks
	hull.Anchored = false
	hull.CanCollide = true
	hull.TopSurface = Enum.SurfaceType.Smooth
	hull.BottomSurface = Enum.SurfaceType.Smooth
	-- Low density so it floats nicely; the rest of the props are stock-ish.
	hull.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.3, 0.5, 1, 1)
	hull.CFrame = cframe
	hull.Parent = model

	model.PrimaryPart = hull

	-- Side walls (left/right), low and thin, running the hull length.
	local wallH = 1.5
	local wallT = 0.5
	local wallY = HULL_H / 2 + wallH / 2 -- sit on top of the hull
	local wallX = HULL_W / 2 - wallT / 2 -- flush to the hull edges
	for _, sx in { -1, 1 } do
		local wall = makeDeco("Wall", Vector3.new(wallT, wallH, HULL_L), WALL_TAN, false)
		weldTo(wall, hull, model, cframe * CFrame.new(sx * wallX, wallY, 0))
	end

	-- Stern (back) wall closing off the +Z end.
	local stern = makeDeco("Stern", Vector3.new(HULL_W, wallH, wallT), WALL_TAN, false)
	weldTo(stern, hull, model, cframe * CFrame.new(0, wallY, HULL_L / 2 - wallT / 2))

	-- Pointed bow from two mirrored WedgeParts at the -Z (forward) end.
	-- A wedge's slope faces +Z and rises toward +Y; rotate so the points meet at the bow tip.
	local bowLen = 4
	local bowZ = -(HULL_L / 2 + bowLen / 2)
	for _, sx in { -1, 1 } do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Bow"
		wedge.Size = Vector3.new(HULL_W / 2, HULL_H + wallH, bowLen)
		wedge.Color = HULL_BROWN
		wedge.Material = Enum.Material.WoodPlanks
		wedge.Anchored = false
		wedge.CanCollide = false
		wedge.Massless = true
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.BottomSurface = Enum.SurfaceType.Smooth
		-- Point the slope outward toward the bow tip; mirror across X for the two halves.
		local yaw = (sx == 1) and math.pi or 0
		local cf = cframe
			* CFrame.new(sx * (HULL_W / 4), (HULL_H + wallH) / 2 - HULL_H / 2, bowZ)
			* CFrame.Angles(0, yaw + math.pi, 0)
		wedge.CFrame = cf
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hull
		weld.Part1 = wedge
		weld.Parent = wedge
		wedge.Parent = model
	end

	-- A trim strip along the top of the hull for a bit of accent.
	local trim = makeDeco("Trim", Vector3.new(HULL_W, 0.3, HULL_L), ACCENT, false)
	weldTo(trim, hull, model, cframe * CFrame.new(0, HULL_H / 2 + 0.15, 0))

	-- Seat on top, facing forward (-Z look). A Seat's occupant faces its -Z by default,
	-- and the hull's -Z is forward, so no extra yaw is needed.
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(3, 1, 3)
	seat.Color = SEAT_COLOR
	seat.Material = Enum.Material.WoodPlanks
	seat.Anchored = false
	seat.CanCollide = false
	seat.Massless = true
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.CFrame = cframe * CFrame.new(0, HULL_H / 2 + 0.5, 2)
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = hull
	seatWeld.Part1 = seat
	seatWeld.Parent = seat
	seat.Parent = model

	-- Floaters: spread across the four hull-bottom corners so wave tilt makes roll & pitch.
	-- Each gets a bottom Attachment + a World-relative VectorForce (driven by BuoyancySystem).
	local floaters: { VectorForce } = {}
	local count = Config.Buoyancy.FloaterCount
	local cornerX = HULL_W / 2 - 1
	local cornerZ = HULL_L / 2 - 1
	-- Four corner offsets (front-left, front-right, back-left, back-right).
	local corners = {
		Vector3.new(-cornerX, -HULL_H / 2, -cornerZ),
		Vector3.new(cornerX, -HULL_H / 2, -cornerZ),
		Vector3.new(-cornerX, -HULL_H / 2, cornerZ),
		Vector3.new(cornerX, -HULL_H / 2, cornerZ),
	}
	for i = 1, count do
		-- Cycle through the corners so any FloaterCount stays spread to the four corners.
		local offset = corners[((i - 1) % #corners) + 1]

		local att = Instance.new("Attachment")
		att.Name = "Floater" .. i
		att.Position = offset
		att.Parent = hull

		local vf = Instance.new("VectorForce")
		vf.Name = "FloaterForce" .. i
		vf.Attachment0 = att
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = false
		vf.Force = Vector3.zero
		vf.Parent = hull

		table.insert(floaters, vf)
	end

	return model, seat, floaters, hull
end

return BoatFactory
