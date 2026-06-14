--!strict
-- Builds a part-only SAILBOAT (no meshes, no toolbox): a sleek white hull with a
-- waterline stripe and pointed bow, a wood deck + low cabin, a cockpit Seat, and a
-- mast carrying a triangular mainsail + jib. Only the hull simulates physics and
-- carries the mass; everything else is welded to it and Massless, so Terrain water
-- floats the whole boat off the hull's density alone. The driver's client drives it
-- (see client BoatController); nothing here applies force.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

-- Hull footprint (studs). Boat faces -Z (forward look = -Z).
local HULL_W = 5     -- X (beam / width)
local HULL_H = 2.5   -- Y (depth of hull)
local HULL_L = 20    -- Z (length)

local HULL_WHITE = Color3.fromRGB(238, 238, 234)
local STRIPE = Color3.fromRGB(28, 52, 92)        -- navy waterline stripe
local DECK_WOOD = Color3.fromRGB(168, 120, 78)
local TRIM = Color3.fromRGB(116, 82, 52)         -- gunwale / darker wood
local CABIN = Color3.fromRGB(226, 226, 222)
local SAIL = Color3.fromRGB(244, 242, 234)       -- cream canvas
local MAST_WOOD = Color3.fromRGB(120, 88, 58)
local KEEL = Color3.fromRGB(44, 48, 56)

local BoatFactory = {}

-- Make a welded, non-simulating decorative part.
local function makeDeco(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = false
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

-- cframe: where to place the boat. Returns (model, seat, hull).
function BoatFactory.build(cframe: CFrame): (Model, Seat, BasePart)
	local model = Instance.new("Model")
	model.Name = "Sailboat"

	-- Hull: the one and only simulated, mass-carrying part. Density < 1 so Terrain
	-- water floats it; ~0.5 sits it IN the water with a believable waterline.
	local hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Size = Vector3.new(HULL_W, HULL_H, HULL_L)
	hull.Color = HULL_WHITE
	hull.Material = Enum.Material.SmoothPlastic
	hull.Anchored = false
	hull.CanCollide = true
	hull.TopSurface = Enum.SurfaceType.Smooth
	hull.BottomSurface = Enum.SurfaceType.Smooth
	hull.CustomPhysicalProperties = PhysicalProperties.new(Config.Boat.HullDensity, 0.3, 0.5, 1, 1)
	hull.CFrame = cframe
	hull.Parent = model
	model.PrimaryPart = hull

	-- Navy waterline stripe (thin band around the hull sides at the waterline).
	for _, sx in { -1, 1 } do
		local stripe = makeDeco("Stripe", Vector3.new(0.12, 0.5, HULL_L * 0.96), STRIPE, Enum.Material.SmoothPlastic)
		weldTo(stripe, hull, model, cframe * CFrame.new(sx * (HULL_W / 2 + 0.02), 0.1, 0))
	end

	-- Pointed bow: two mirrored wedges taper the -Z (front) end to a stem.
	local bowLen = 5
	local bowZ = -(HULL_L / 2 + bowLen / 2)
	for _, sx in { -1, 1 } do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Bow"
		wedge.Size = Vector3.new(HULL_W / 2, HULL_H, bowLen)
		wedge.Color = HULL_WHITE
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.Anchored = false
		wedge.CanCollide = false
		wedge.Massless = true
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.BottomSurface = Enum.SurfaceType.Smooth
		local yaw = (sx == 1) and 0 or math.pi
		local cf = cframe * CFrame.new(sx * (HULL_W / 4), 0, bowZ) * CFrame.Angles(0, yaw, 0)
		wedge.CFrame = cf
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hull
		weld.Part1 = wedge
		weld.Parent = wedge
		wedge.Parent = model
	end

	-- Thin fin keel under the hull centre (looks like a sailboat; tiny volume).
	local keel = makeDeco("Keel", Vector3.new(0.4, 1.8, 7), KEEL, Enum.Material.SmoothPlastic)
	weldTo(keel, hull, model, cframe * CFrame.new(0, -(HULL_H / 2 + 0.9), 1))

	-- Wood deck across the top of the hull.
	local deckY = HULL_H / 2 + 0.1
	local deck = makeDeco("Deck", Vector3.new(HULL_W - 0.2, 0.2, HULL_L - 0.4), DECK_WOOD, Enum.Material.WoodPlanks)
	weldTo(deck, hull, model, cframe * CFrame.new(0, deckY, 0))

	-- Gunwale trim strips along the deck edges.
	for _, sx in { -1, 1 } do
		local rail = makeDeco("Rail", Vector3.new(0.22, 0.5, HULL_L - 1), TRIM, Enum.Material.WoodPlanks)
		weldTo(rail, hull, model, cframe * CFrame.new(sx * (HULL_W / 2 - 0.1), deckY + 0.25, 0))
	end

	-- Low cabin (coachroof) forward of the cockpit.
	local cabin = makeDeco("Cabin", Vector3.new(HULL_W - 1.4, 1.2, 6), CABIN, Enum.Material.SmoothPlastic)
	weldTo(cabin, hull, model, cframe * CFrame.new(0, deckY + 0.7, -3))
	local cabinTrim = makeDeco("CabinTrim", Vector3.new(HULL_W - 1.2, 0.18, 6.2), TRIM, Enum.Material.WoodPlanks)
	weldTo(cabinTrim, hull, model, cframe * CFrame.new(0, deckY + 1.32, -3))

	-- Cockpit Seat, toward the stern, facing forward (-Z look).
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2.4, 0.6, 2.4)
	seat.Color = TRIM
	seat.Material = Enum.Material.WoodPlanks
	seat.Anchored = false
	seat.CanCollide = false
	seat.Massless = true
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.CFrame = cframe * CFrame.new(0, deckY + 0.4, 5.5)
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = hull
	seatWeld.Part1 = seat
	seatWeld.Parent = seat
	seat.Parent = model

	-- Mast: tall cylinder a touch forward of centre.
	local mastH = 16
	local mastZ = -1
	local boomY = deckY + 1.4
	local mast = Instance.new("Part")
	mast.Name = "Mast"
	mast.Shape = Enum.PartType.Cylinder
	mast.Size = Vector3.new(mastH, 0.5, 0.5) -- cylinder long axis is X; rotate to vertical
	mast.Color = MAST_WOOD
	mast.Material = Enum.Material.Wood
	mast.Anchored = false
	mast.CanCollide = false
	mast.Massless = true
	weldTo(mast, hull, model, cframe * CFrame.new(0, deckY + mastH / 2, mastZ) * CFrame.Angles(0, 0, math.rad(90)))

	-- Boom: horizontal cylinder from the mast going aft.
	local boomLen = 8
	local boom = Instance.new("Part")
	boom.Name = "Boom"
	boom.Shape = Enum.PartType.Cylinder
	boom.Size = Vector3.new(boomLen, 0.35, 0.35) -- long axis X; rotate to lie along Z
	boom.Color = MAST_WOOD
	boom.Material = Enum.Material.Wood
	boom.Anchored = false
	boom.CanCollide = false
	boom.Massless = true
	weldTo(boom, hull, model, cframe * CFrame.new(0, boomY, mastZ + boomLen / 2) * CFrame.Angles(0, math.rad(90), 0))

	-- Mainsail: a right-triangle WedgePart. Vertical luff up the mast, foot along the
	-- boom, leech sloping from masthead down to the boom end. The wedge's tall face
	-- sits at the mast and it tapers aft (+Z) to the leech.
	local sailH = mastH - 2
	local sailFoot = boomLen - 0.5
	local mainsail = Instance.new("WedgePart")
	mainsail.Name = "Mainsail"
	mainsail.Size = Vector3.new(0.1, sailH, sailFoot)
	mainsail.Color = SAIL
	mainsail.Material = Enum.Material.Fabric
	mainsail.Anchored = false
	mainsail.CanCollide = false
	mainsail.Massless = true
	mainsail.TopSurface = Enum.SurfaceType.Smooth
	mainsail.BottomSurface = Enum.SurfaceType.Smooth
	-- bottom of the sail at boom height; tall face at the mast, tapering aft
	weldTo(mainsail, hull, model, cframe * CFrame.new(0, boomY + sailH / 2, mastZ + sailFoot / 2))

	-- Jib: a smaller foresail forward of the mast, tapering toward the bow.
	local jibH = 10
	local jibFoot = 5
	local jib = Instance.new("WedgePart")
	jib.Name = "Jib"
	jib.Size = Vector3.new(0.1, jibH, jibFoot)
	jib.Color = SAIL
	jib.Material = Enum.Material.Fabric
	jib.Anchored = false
	jib.CanCollide = false
	jib.Massless = true
	jib.TopSurface = Enum.SurfaceType.Smooth
	jib.BottomSurface = Enum.SurfaceType.Smooth
	-- rotate 180 about Y so the tall face is forward (at the forestay) and it tapers aft toward the mast
	weldTo(jib, hull, model, cframe * CFrame.new(0, boomY + jibH / 2, mastZ - jibFoot / 2 - 1) * CFrame.Angles(0, math.pi, 0))

	return model, seat, hull
end

return BoatFactory
