--!strict
-- Builds a part-only boat (no meshes, no toolbox): a flat hull base, low side walls,
-- a pointed wedge bow, and a welded Seat. Only the hull simulates physics; everything
-- else is welded to it and Massless. The hull carries ONE centred buoyancy VectorForce
-- (the BuoyancySystem drives the Y bob) and an AlignOrientation that owns its rotation
-- (the BoatMovementSystem steers it) -- so it physically cannot capsize.
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

-- cframe: where to place the boat. Returns (model, seat, floaters, align, hull).
function BoatFactory.build(cframe: CFrame): (Model, Seat, { VectorForce }, AlignOrientation, BasePart)
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

	-- Single centred buoyancy force (vertical only, applied at the centre of mass) drives
	-- the Y bob. Because it acts through the CoM it can never impart a capsizing torque --
	-- roll & pitch are owned entirely by the AlignOrientation below.
	local buoyAtt = Instance.new("Attachment")
	buoyAtt.Name = "BuoyancyPoint"
	buoyAtt.Position = Vector3.new(0, -HULL_H / 2, 0) -- sampled at the hull bottom centre
	buoyAtt.Parent = hull

	local buoyVF = Instance.new("VectorForce")
	buoyVF.Name = "BuoyancyForce"
	buoyVF.Attachment0 = buoyAtt
	buoyVF.RelativeTo = Enum.ActuatorRelativeTo.World
	buoyVF.ApplyAtCenterOfMass = true
	buoyVF.Force = Vector3.zero
	buoyVF.Parent = hull
	local floaters: { VectorForce } = { buoyVF }

	-- Upright stabiliser: AlignOrientation eases the hull toward a goal CFrame the
	-- movement system sets each frame (steering yaw + a gentle lean into the wave
	-- surface). Non-rigid + finite Responsiveness => smooth swell-riding that can
	-- NEVER tip past the wave normal, so the boat is physically unable to flip.
	local orientAtt = Instance.new("Attachment")
	orientAtt.Name = "OrientPoint"
	orientAtt.Parent = hull

	local align = Instance.new("AlignOrientation")
	align.Name = "Upright"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = orientAtt
	align.RigidityEnabled = false
	align.MaxTorque = math.huge
	align.MaxAngularVelocity = math.huge
	align.Responsiveness = Config.Boat.OrientResponse
	align.CFrame = cframe.Rotation
	align.Parent = hull

	return model, seat, floaters, align, hull
end

return BoatFactory
