--!strict
-- OceanRenderer.luau
-- Builds and animates a realistic, SHADED Gerstner ocean on the CLIENT. A single
-- grid plane (Config.Ocean.Resolution² quads over Config.Ocean.Size studs) follows
-- the camera and, each RenderStepped:
--   * displaces every vertex with Wave.GetDisplacement(worldX, worldZ, t)
--   * recomputes per-vertex NORMALS from neighbour heights, so the sun shades the
--     waves (bright crests, dark troughs = the "shadows" that make swell readable)
--   * paints per-vertex COLORS: deep-blue troughs -> lighter crests -> white foam,
--     with a sun-side highlight.
-- t = workspace:GetServerTimeNow() — the SAME clock the server buoyancy samples,
-- so the water you see is the water the boats float on.
--
-- USE_EDITABLE_MESH = true  -> one shaded EditableMesh MeshPart (primary)
-- USE_EDITABLE_MESH = false -> buildPartGrid() fallback (flip the flag if needed)

local USE_EDITABLE_MESH = true

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Wave = require(ReplicatedStorage.Shared.Wave)

local OceanRenderer = {}

-- Shading palette + sun direction (roughly matches the afternoon sun).
local DEEP = Color3.fromRGB(6, 40, 72)
local SHALLOW = Color3.fromRGB(36, 116, 156)
local FOAM = Color3.fromRGB(226, 240, 246)
local SUN = Vector3.new(0.5, 0.82, -0.32).Unit

local function snap(v: number, cell: number): number
	return math.floor(v / cell + 0.5) * cell
end

--------------------------------------------------------------------------------
-- Shaded EditableMesh ocean (primary path)
--------------------------------------------------------------------------------
type EditableState = {
	em: EditableMesh,
	part: MeshPart,
	verts: { number },
	normals: { number },
	colors: { number },
	heights: { number },
	gridX: { number },
	gridZ: { number },
	res: number,
	nodes: number,
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
	local normals: { number } = {}
	local colors: { number } = {}
	local gridX: { number } = {}
	local gridZ: { number } = {}

	for iz = 0, res do
		for ix = 0, res do
			local lx = -half + ix * cell
			local lz = -half + iz * cell
			local index = iz * nodes + ix + 1
			verts[index] = em:AddVertex(Vector3.new(lx, 0, lz))
			normals[index] = em:AddNormal(Vector3.yAxis)
			colors[index] = em:AddColor(DEEP, 1)
			gridX[index] = lx
			gridZ[index] = lz
		end
	end

	-- Two triangles per quad; map each face's corner normals + colors to its verts.
	for iz = 0, res - 1 do
		for ix = 0, res - 1 do
			local a = iz * nodes + ix + 1
			local b = iz * nodes + (ix + 1) + 1
			local c = (iz + 1) * nodes + ix + 1
			local d = (iz + 1) * nodes + (ix + 1) + 1
			local f1 = em:AddTriangle(verts[a], verts[c], verts[b])
			em:SetFaceNormals(f1, { normals[a], normals[c], normals[b] })
			em:SetFaceColors(f1, { colors[a], colors[c], colors[b] })
			local f2 = em:AddTriangle(verts[b], verts[c], verts[d])
			em:SetFaceNormals(f2, { normals[b], normals[c], normals[d] })
			em:SetFaceColors(f2, { colors[b], colors[c], colors[d] })
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
	part.Material = Enum.Material.SmoothPlastic -- lets the per-vertex normals/colors shade
	part.Color = Color3.new(1, 1, 1) -- white so vertex colors render true
	part.Transparency = transparency
	part.Reflectance = 0.16 -- sky reflection for a wet sheen
	part.Position = Vector3.new(0, baseY, 0)
	part.Parent = Workspace

	return {
		em = em,
		part = part,
		verts = verts,
		normals = normals,
		colors = colors,
		heights = table.create(#verts, 0),
		gridX = gridX,
		gridZ = gridZ,
		res = res,
		nodes = nodes,
		cell = cell,
		half = half,
	}
end

local function animateEditableMesh(s: EditableState, originX: number, originZ: number, t: number)
	local em = s.em
	local verts, normals, colors = s.verts, s.normals, s.colors
	local heights = s.heights
	local gridX, gridZ = s.gridX, s.gridZ
	local res, nodes, cell = s.res, s.nodes, s.cell
	local maxH = Wave.MaxHeight()

	-- Pass 1: displace vertices, cache world height per node.
	for i = 1, #verts do
		local lx, lz = gridX[i], gridZ[i]
		local d = Wave.GetDisplacement(originX + lx, originZ + lz, t)
		em:SetPosition(verts[i], Vector3.new(lx + d.X, d.Y, lz + d.Z))
		heights[i] = d.Y
	end

	-- Pass 2: normals from neighbour heights (cheap) + shaded colors.
	for iz = 0, res do
		local rowL = iz * nodes
		for ix = 0, res do
			local i = rowL + ix + 1
			local hL = heights[rowL + math.max(ix - 1, 0) + 1]
			local hR = heights[rowL + math.min(ix + 1, res) + 1]
			local hD = heights[math.max(iz - 1, 0) * nodes + ix + 1]
			local hU = heights[math.min(iz + 1, res) * nodes + ix + 1]
			local n = Vector3.new(hL - hR, 2 * cell, hD - hU).Unit
			em:SetNormal(normals[i], n)

			local h = heights[i]
			local tone = math.clamp((h + maxH * 0.5) / maxH, 0, 1) -- trough->crest
			local c = DEEP:Lerp(SHALLOW, tone)
			c = c:Lerp(Color3.new(1, 1, 1), math.clamp(n:Dot(SUN), 0, 1) * 0.18) -- sun glint
			-- foam on the highest, steepest crests
			local foam = math.clamp((h - maxH * 0.45) / (maxH * 0.55), 0, 1) * (1 - n.Y) * 2.4
			c = c:Lerp(FOAM, math.clamp(foam, 0, 0.85))
			em:SetColor(colors[i], c, 1)
		end
	end
end

--------------------------------------------------------------------------------
-- Part-grid ocean (fallback path, USE_EDITABLE_MESH = false)
--------------------------------------------------------------------------------
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
	template.Material = Enum.Material.Glass
	template.Color = color
	template.Transparency = transparency
	template.Reflectance = 0.12
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

	return { folder = folder, tiles = tiles, tileX = tileX, tileZ = tileZ, baseY = baseY, cell = cell, half = half }
end

local function animatePartGrid(s: PartGridState, originX: number, originZ: number, t: number)
	local tiles, tileX, tileZ = s.tiles, s.tileX, s.tileZ
	for i = 1, #tiles do
		local wx = originX + tileX[i]
		local wz = originZ + tileZ[i]
		tiles[i].Position = Vector3.new(wx, s.baseY + Wave.GetHeight(wx, wz, t), wz)
	end
end

--------------------------------------------------------------------------------
-- Deep-water volume: a large dark body UNDER the animated surface so the ocean
-- reads as a thick, deep sea to the horizon. Top sits just below the deepest
-- trough; follows the camera on XZ.
--------------------------------------------------------------------------------
local DEEP_DEPTH = 400
local DEEP_TOP = Wave.MaxHeight() + 1.5

local function buildDeepWater(baseY: number, color: Color3): BasePart
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
	p.Size = Vector3.new(6000, DEEP_DEPTH, 6000)
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
		local ok, result = pcall(buildEditableMesh, size, res, baseY, color, transparency)
		if ok then
			editable = result
		else
			warn("[OceanRenderer] EditableMesh build failed, using part grid: " .. tostring(result))
		end
	end

	if editable then
		cell = editable.cell
	else
		if USE_EDITABLE_MESH then
			warn("[OceanRenderer] EditableMesh unavailable; falling back to part grid")
		end
		partGrid = buildPartGrid(size, res, baseY, color, transparency)
		cell = partGrid.cell
	end

	local deep = buildDeepWater(baseY, color:Lerp(Color3.fromRGB(0, 8, 18), 0.6))

	RunService.RenderStepped:Connect(function()
		camera = Workspace.CurrentCamera
		local t = Workspace:GetServerTimeNow()

		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		local originX = snap(camPos.X, cell)
		local originZ = snap(camPos.Z, cell)

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
