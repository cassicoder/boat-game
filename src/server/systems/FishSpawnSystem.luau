--!strict
-- FishSpawnSystem
-- Keeps the sea populated. Throttled to ~twice a second: counts live fish, and
-- while below Config.Fish.MaxCount (and at least one player exists) spawns a new
-- part-built fish near a random player, at a random depth in the swim band.
-- Also culls fish that have drifted past DespawnRadius from every player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(ReplicatedStorage.Shared.Components)
local Matter = require(ReplicatedStorage.Packages.Matter)

-- A few fishy base hues; each spawn jitters from one of these for variety.
local FISH_COLORS: { Color3 } = {
	Color3.fromRGB(94, 132, 158),
	Color3.fromRGB(120, 146, 120),
	Color3.fromRGB(158, 138, 96),
	Color3.fromRGB(110, 120, 150),
	Color3.fromRGB(150, 110, 110),
}

-- Slight per-fish color wobble so a school doesn't look cloned.
local function jitterColor(base: Color3): Color3
	local function j(c: number): number
		return math.clamp(c + (math.random() - 0.5) * 0.18, 0, 1)
	end
	return Color3.new(j(base.R), j(base.G), j(base.B))
end

-- Build a small fish entirely from Parts: an ellipsoid-ish body + a wedge tail,
-- welded together. PrimaryPart (the body) is Anchored — the AI sets its CFrame.
local function buildFishModel(color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Fish"

	-- Body: a squashed block (~2.6 long), rounded into a soft ellipsoid via mesh.
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Block
	body.Size = Vector3.new(0.9, 0.9, 2.6)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = color
	body.CFrame = CFrame.new()

	local round = Instance.new("SpecialMesh")
	round.MeshType = Enum.MeshType.Sphere
	round.Scale = Vector3.new(1, 1, 1)
	round.Parent = body
	body.Parent = model

	-- Tail: a wedge flaring out behind the body.
	local tail = Instance.new("WedgePart")
	tail.Name = "Tail"
	tail.Size = Vector3.new(0.2, 1.1, 1.0)
	tail.Anchored = true
	tail.CanCollide = false
	tail.CanQuery = false
	tail.CanTouch = false
	tail.Material = Enum.Material.SmoothPlastic
	tail.Color = color:Lerp(Color3.new(0, 0, 0), 0.15)
	-- Sit the wedge at the back (+Z is forward, so the tail trails at -Z),
	-- rotated so its slope reads as a fin.
	tail.CFrame = body.CFrame * CFrame.new(0, 0, -1.6) * CFrame.Angles(0, math.rad(90), math.rad(90))
	tail.Parent = model

	model.PrimaryPart = body

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = tail
	weld.Parent = body

	return model
end

return function(world, state)
	-- Act ~twice a second; spawning every frame would thrash.
	if not Matter.useThrottle(0.5) then
		return
	end

	local fishConfig = state.config.Fish
	local baseY = state.config.Ocean.BaseY

	-- Gather the players that have a character root to anchor spawns/culls to.
	local roots: { Vector3 } = {}
	for _, player in state.players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(roots, (root :: BasePart).Position)
		end
	end

	-- Count live fish and cull any that have wandered too far from everyone.
	local count = 0
	for id, fish, pos in world:query(Components.Fish, Components.Position) do
		count += 1

		if #roots > 0 then
			local nearest = math.huge
			for _, rp in roots do
				local d = (pos.value - rp).Magnitude
				if d < nearest then
					nearest = d
				end
			end
			if nearest > fishConfig.DespawnRadius then
				world:despawn(id)
				fish.model:Destroy()
				count -= 1
			end
		end
	end

	-- No players -> nothing to spawn around.
	if #roots == 0 then
		return
	end

	-- Top the population back up toward MaxCount.
	while count < fishConfig.MaxCount do
		local anchor = roots[math.random(1, #roots)]

		-- Random horizontal offset within SpawnRadius around the chosen player.
		local angle = math.random() * 2 * math.pi
		local dist = math.sqrt(math.random()) * fishConfig.SpawnRadius
		local offsetX = math.cos(angle) * dist
		local offsetZ = math.sin(angle) * dist

		-- Random depth in the swim band (DepthMin..DepthMax are below BaseY).
		local depth = fishConfig.DepthMin + math.random() * (fishConfig.DepthMax - fishConfig.DepthMin)
		local spawnPos = Vector3.new(anchor.X + offsetX, baseY + depth, anchor.Z + offsetZ)

		-- Random heading on the horizontal plane to start drifting along.
		local heading = math.random() * 2 * math.pi
		local dir = Vector3.new(math.cos(heading), 0, math.sin(heading)).Unit
		local vel = dir * fishConfig.Speed

		local color = jitterColor(FISH_COLORS[math.random(1, #FISH_COLORS)])
		local model = buildFishModel(color)
		model:PivotTo(CFrame.lookAt(spawnPos, spawnPos + dir))
		model.Parent = state.fishFolder

		world:spawn(
			Components.Fish({ model = model }),
			Components.Position({ value = spawnPos }),
			Components.Velocity({ value = vel }),
			Components.Wander({ dir = dir, timer = 0 })
		)

		count += 1
	end
end
