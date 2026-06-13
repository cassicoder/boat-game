--!strict
-- OceanRenderer.luau
-- Builds and animates the visible Gerstner ocean on the CLIENT. A single grid
-- plane (Config.Ocean.Resolution² quads over Config.Ocean.Size studs) follows the
-- camera and, each RenderStepped, displaces every vertex with
-- Wave.GetDisplacement(worldX, worldZ, t) at t = workspace:GetServerTimeNow() —
-- the SAME clock the server buoyancy samples, so the water you see is the water
-- the boats float on.
--
-- Two build paths share one animation loop:
--   USE_EDITABLE_MESH = true  -> one EditableMesh MeshPart (smooth, cheap to skin)
--   USE_EDITABLE_MESH = false -> buildPartGrid() fallback (a grid of thin parts,
--                                displaced by Wave.GetHeight) — flip the flag to
--                                switch live if the EditableMesh path misbehaves.

-- Flip this to switch the live ocean implementation.
local USE_EDITABLE_MESH = true

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Wave = require(ReplicatedStorage.Shared.Wave)

local OceanRenderer = {}

-- Resolve the prettiest available water material; older surfaces fall back to Glass.
local function oceanMaterial(): Enum.Material
	if (Enum.Material :: any).Water then
		return Enum.Material.Water
	end
	return Enum.Material.Glass
end

-- Snap a world coordinate to the grid cell size so the plane tiles seamlessly as
-- it follows the camera (vertices always land on the same Gerstner phase).
local function snap(v: number, cell: number): number
	return math.floor(v / cell + 0.5) * cell
end

--------------------------------------------------------------------------------
-- EditableMesh ocean (primary path)
--------------------------------------------------------------------------------
-- Verified against current create.roblox.com docs (2026-06):
--   AssetService:CreateEditableMesh()            -> empty, resizable EditableMesh
--   em:AddVertex(p: Vector3): int64              -> stable vertex id
--   em:AddTriangle(v0, v1, v2): int64            -> stable face id
--   em:SetPosition(vertexId, p: Vector3)         -> moves a vertex (reflects live)
--   AssetService:CreateMeshPartAsync(Content.fromObject(em), opts): MeshPart
-- SetPosition updates show immediately on the linked MeshPart, so we build the
-- MeshPart ONCE and only re-skin vertex positions each frame.

type EditableState = {
	em: EditableMesh,
	part: MeshPart,
	verts: { number },   -- vertexId per grid node, row-major (res+1)²
	gridX: { number },   -- node-local X in [-half, half], indexed like verts
	gridZ: { number },   -- node-local Z in [-half, half]
	res: number,
	cell: number,
	half: number,
}

local function buildEditableMesh(size: number, res: number, baseY: number, color: Color3, transparency: number): EditableState?
	local em = AssetService:CreateEditableMesh()
	if not em then
		return nil
	end

	local nodes = res + 1
	local cell = size / res
	local half = size / 2

	local verts: { number } = {}
	local gridX: { number } = {}
	local gridZ: { number } = {}

	-- Lay out a flat (res+1)² node grid centered on the part origin.
	for iz = 0, res do
		for ix = 0, res do
			local lx = -half + ix * cell
			local lz = -half + iz * cell
			local id = em:AddVertex(Vector3.new(lx, 0, lz))
			local index = iz * nodes + ix + 1
			verts[index] = id
			gridX[index] = lx
			gridZ[index] = lz
		end
	end

	-- Two triangles per quad. Winding faces +Y (up).
	for iz = 0, res - 1 do
		for ix = 0, res - 1 do
			local a = iz * nodes + ix + 1
			local b = iz * nodes + (ix + 1) + 1
			local c = (iz + 1) * nodes + ix + 1
			local d = (iz + 1) * nodes + (ix + 1) + 1
			em:AddTriangle(verts[a], verts[c], verts[b])
			em:AddTriangle(verts[b], verts[c], verts[d])
		end
	end

	local part: MeshPart = AssetService:CreateMeshPartAsync(
		Content.fromObject(em),
		{ CollisionFidelity = Enum.CollisionFidelity.Box }
	)
	part.Name = "OceanMesh"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = oceanMaterial()
	part.Color = color
	part.Transparency = transparency
	part.Reflectance = 0.12 -- water sheen so the surface reads as solid, not a film
	part.Position = Vector3.new(0, baseY, 0)
	part.Parent = Workspace

	return {
		em = em,
		part = part,
		verts = verts,
		gridX = gridX,
		gridZ = gridZ,
		res = res,
		cell = cell,
		half = half,
	}
end

-- Re-skin every vertex: world (x,z) under the camera-snapped origin -> Gerstner
-- displacement -> local vertex position (relative to the part origin at y=baseY).
local function animateEditableMesh(s: EditableState, originX: number, originZ: number, t: number)
	local verts = s.verts
	local gridX = s.gridX
	local gridZ = s.gridZ
	local em = s.em
	for i = 1, #verts do
		local lx = gridX[i]
		local lz = gridZ[i]
		local wx = originX + lx
		local wz = originZ + lz
		local d = Wave.GetDisplacement(wx, wz, t)
		-- Local position: keep the flat node lattice but add the full xyz pull.
		em:SetPosition(verts[i], Vector3.new(lx + d.X, d.Y, lz + d.Z))
	end
end

--------------------------------------------------------------------------------
-- Part-grid ocean (fallback path, USE_EDITABLE_MESH = false)
--------------------------------------------------------------------------------
-- A coarse grid of thin anchored tiles. Each frame each tile is parked at its
-- camera-relative cell and lifted to Wave.GetHeight at that world (x,z). Cheap,
-- ugly-but-reliable; here so we can flip the top flag if EditableMesh acts up.

type PartGridState = {
	folder: Folder,
	tiles: { BasePart },
	tileX: { number },
	tileZ: { number },
	baseY: number,
	cell: number,
	half: number,
}

local function buildPartGrid(size: number, res: number, baseY: number, color: Color3, transparency: number): PartGridState
	-- Keep the fallback coarse so we never spawn thousands of parts.
	local tilesPerSide = math.clamp(res, 8, 32)
	local cell = size / tilesPerSide
	local half = size / 2

	local folder = Instance.new("Folder")
	folder.Name = "OceanPartGrid"

	local tiles: { BasePart } = {}
	local tileX: { number } = {}
	local tileZ: { number } = {}

	local template = Instance.new("Part")
	template.Anchored = true
	template.CanCollide = false
	template.CanQuery = false
	template.CanTouch = false
	template.CastShadow = false
	template.TopSurface = Enum.SurfaceType.Smooth
	template.BottomSurface = Enum.SurfaceType.Smooth
	template.Material = oceanMaterial()
	template.Color = color
	template.Transparency = transparency
	template.Size = Vector3.new(cell, 1, cell)

	for iz = 0, tilesPerSide - 1 do
		for ix = 0, tilesPerSide - 1 do
			local lx = -half + (ix + 0.5) * cell
			local lz = -half + (iz + 0.5) * cell
			local tile = template:Clone()
			tile.Parent = folder
			local index = #tiles + 1
			tiles[index] = tile
			tileX[index] = lx
			tileZ[index] = lz
		end
	end
	template:Destroy()

	folder.Parent = Workspace

	return {
		folder = folder,
		tiles = tiles,
		tileX = tileX,
		tileZ = tileZ,
		baseY = baseY,
		cell = cell,
		half = half,
	}
end

local function animatePartGrid(s: PartGridState, originX: number, originZ: number, t: number)
	local tiles = s.tiles
	local tileX = s.tileX
	local tileZ = s.tileZ
	for i = 1, #tiles do
		local wx = originX + tileX[i]
		local wz = originZ + tileZ[i]
		local y = s.baseY + Wave.GetHeight(wx, wz, t)
		tiles[i].Position = Vector3.new(wx, y, wz)
	end
end

--------------------------------------------------------------------------------
-- Deep-water volume: a large dark body UNDER the animated surface so the ocean
-- reads as a thick, deep sea (with real depth toward the horizon) instead of a
-- thin transparent sheet. Its top sits below the lowest wave trough and it
-- follows the camera on XZ each frame.
--------------------------------------------------------------------------------
local DEEP_DEPTH = 400
local DEEP_TOP = 7 -- studs below sea level the body's top sits (under the troughs)

local function buildDeepWater(size: number, baseY: number, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = "OceanDeep"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = 0
	p.Reflectance = 0.08
	p.Size = Vector3.new(size * 3, DEEP_DEPTH, size * 3)
	p.Position = Vector3.new(0, baseY - DEEP_DEPTH / 2 - DEEP_TOP, 0)
	p.Parent = Workspace
	return p
end

--------------------------------------------------------------------------------
-- Public: start the ocean.
--------------------------------------------------------------------------------
function OceanRenderer.start(config)
	local ocean = config.Ocean
	local size: number = ocean.Size
	local res: number = ocean.Resolution
	local baseY: number = ocean.BaseY
	local color: Color3 = ocean.Color
	local transparency: number = ocean.Transparency

	local camera = Workspace.CurrentCamera

	local editable: EditableState? = nil
	local partGrid: PartGridState? = nil
	local cell: number

	if USE_EDITABLE_MESH then
		editable = buildEditableMesh(size, res, baseY, color, transparency)
	end

	if editable then
		cell = editable.cell
	else
		-- Either the fallback was requested, or CreateEditableMesh failed (budget).
		if USE_EDITABLE_MESH then
			warn("[OceanRenderer] EditableMesh unavailable; falling back to part grid")
		end
		partGrid = buildPartGrid(size, res, baseY, color, transparency)
		cell = partGrid.cell
	end

	local deep = buildDeepWater(size, baseY, color:Lerp(Color3.fromRGB(0, 8, 18), 0.6))

	RunService.RenderStepped:Connect(function()
		camera = Workspace.CurrentCamera
		local t = Workspace:GetServerTimeNow()

		-- Recenter under the camera, snapped to a grid cell so the lattice tiles
		-- seamlessly (vertices keep landing on consistent Gerstner phases).
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		local originX = snap(camPos.X, cell)
		local originZ = snap(camPos.Z, cell)

		-- Keep the deep-water body centered under the camera so the sea fills the
		-- horizon in every direction.
		deep.Position = Vector3.new(camPos.X, baseY - DEEP_DEPTH / 2 - DEEP_TOP, camPos.Z)

		if editable then
			editable.part.Position = Vector3.new(originX, baseY, originZ)
			animateEditableMesh(editable, originX, originZ, t)
		elseif partGrid then
			animatePartGrid(partGrid, originX, originZ, t)
		end
	end)
end

return OceanRenderer
