--!strict
-- OceanRenderer.luau
-- Animated Gerstner ocean on the CLIENT via EditableMesh. Each RenderStepped:
--   * displaces every vertex with Wave.GetDisplacement
--   * recomputes per-vertex NORMALS from neighbour heights so the sun shades the
--     swell (bright crests, dark troughs) — realism without per-frame vertex colors.
-- Kept LEAN on purpose (position + normal only, modest resolution) so it stays
-- smooth: per-frame vertex colors at high res were what made the old version
-- stutter/glitch. t = workspace:GetServerTimeNow() — the SAME clock the server
-- buoyancy samples, so the water you see is the water the boats float on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Wave = require(ReplicatedStorage.Shared.Wave)

local OceanRenderer = {}

local function snap(v: number, cell: number): number
	return math.floor(v / cell + 0.5) * cell
end

type State = {
	em: EditableMesh,
	part: MeshPart,
	verts: { number },
	normals: { number },
	heights: { number },
	gridX: { number },
	gridZ: { number },
	res: number,
	nodes: number,
	cell: number,
}

local function build(size: number, res: number, baseY: number, color: Color3, transparency: number): State?
	local em = AssetService:CreateEditableMesh()
	if not em then
		return nil
	end
	local nodes = res + 1
	local cell = size / res
	local half = size / 2
	local verts, normals, gridX, gridZ = {}, {}, {}, {}

	for iz = 0, res do
		for ix = 0, res do
			local lx = -half + ix * cell
			local lz = -half + iz * cell
			local i = iz * nodes + ix + 1
			verts[i] = em:AddVertex(Vector3.new(lx, 0, lz))
			normals[i] = em:AddNormal(Vector3.yAxis)
			gridX[i] = lx
			gridZ[i] = lz
		end
	end

	for iz = 0, res - 1 do
		for ix = 0, res - 1 do
			local a = iz * nodes + ix + 1
			local b = iz * nodes + ix + 2
			local c = (iz + 1) * nodes + ix + 1
			local d = (iz + 1) * nodes + ix + 2
			local f1 = em:AddTriangle(verts[a], verts[c], verts[b])
			em:SetFaceNormals(f1, { normals[a], normals[c], normals[b] })
			local f2 = em:AddTriangle(verts[b], verts[c], verts[d])
			em:SetFaceNormals(f2, { normals[b], normals[c], normals[d] })
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
	part.Material = Enum.Material.SmoothPlastic -- so the per-vertex normals shade the swell
	part.Color = color
	part.Transparency = transparency
	part.Reflectance = 0.25 -- sky reflection for a wet sheen
	part.Position = Vector3.new(0, baseY, 0)
	part.Parent = Workspace

	return {
		em = em,
		part = part,
		verts = verts,
		normals = normals,
		heights = table.create(#verts, 0),
		gridX = gridX,
		gridZ = gridZ,
		res = res,
		nodes = nodes,
		cell = cell,
	}
end

local function animate(s: State, ox: number, oz: number, t: number)
	local em, verts, normals, heights = s.em, s.verts, s.normals, s.heights
	local gridX, gridZ, res, nodes, cell = s.gridX, s.gridZ, s.res, s.nodes, s.cell

	for i = 1, #verts do
		local lx, lz = gridX[i], gridZ[i]
		local d = Wave.GetDisplacement(ox + lx, oz + lz, t)
		em:SetPosition(verts[i], Vector3.new(lx + d.X, d.Y, lz + d.Z))
		heights[i] = d.Y
	end

	for iz = 0, res do
		local row = iz * nodes
		for ix = 0, res do
			local i = row + ix + 1
			local hL = heights[row + math.max(ix - 1, 0) + 1]
			local hR = heights[row + math.min(ix + 1, res) + 1]
			local hD = heights[math.max(iz - 1, 0) * nodes + ix + 1]
			local hU = heights[math.min(iz + 1, res) * nodes + ix + 1]
			em:SetNormal(normals[i], Vector3.new(hL - hR, 2 * cell, hD - hU).Unit)
		end
	end
end

--------------------------------------------------------------------------------
-- Deep-water body under the surface so the sea reads as thick + deep.
--------------------------------------------------------------------------------
local DEEP_DEPTH = 400
local DEEP_TOP = Wave.MaxHeight() + 1.5

local function buildDeep(baseY: number, color: Color3): BasePart
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
	p.Reflectance = 0.06
	p.Size = Vector3.new(2048, DEEP_DEPTH, 2048)
	p.Position = Vector3.new(0, baseY - DEEP_DEPTH / 2 - DEEP_TOP, 0)
	p.Parent = Workspace
	return p
end

function OceanRenderer.start(config)
	local o = config.Ocean
	local editable: State? = nil
	local ok, result = pcall(build, o.Size, o.Resolution, o.BaseY, o.Color, o.Transparency)
	if ok then
		editable = result
	else
		warn("[OceanRenderer] EditableMesh build failed: " .. tostring(result))
	end

	local deep = buildDeep(o.BaseY, o.Color:Lerp(Color3.fromRGB(0, 8, 18), 0.6))
	local cell = editable and editable.cell or (o.Size / o.Resolution)

	RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		local t = Workspace:GetServerTimeNow()
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		local ox, oz = snap(camPos.X, cell), snap(camPos.Z, cell)

		deep.Position = Vector3.new(camPos.X, o.BaseY - DEEP_DEPTH / 2 - DEEP_TOP, camPos.Z)
		if editable then
			editable.part.Position = Vector3.new(ox, o.BaseY, oz)
			animate(editable, ox, oz, t)
		end
	end)
end

return OceanRenderer
