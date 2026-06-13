# BoatGame — module contract (build to this EXACTLY)

A Roblox boating game. Matter ECS (server-only). Animated Gerstner ocean (client).
Custom buoyancy. Auto fish. Spawnable part-boats with a custom HUD. No toolbox assets.
Scope: **prototype-rough** — functional and clean, not over-polished. `--!strict` Luau, tabs.

## Golden rules (every module)
- **Shared clock:** any wave time `t` = `workspace:GetServerTimeNow()` on BOTH client and
  server, so the visible ocean and the physics agree across clients.
- **Sea level** = `Config.Ocean.BaseY`. Surface world height at (x,z) =
  `Config.Ocean.BaseY + Wave.GetHeight(x, z, t)`.
- Don't yield inside Matter systems. Don't edit files outside your assigned paths.
- Requires:
  - `local ReplicatedStorage = game:GetService("ReplicatedStorage")`
  - `local Wave = require(ReplicatedStorage.Shared.Wave)`
  - `local Config = require(ReplicatedStorage.Shared.Config)`
  - `local Components = require(ReplicatedStorage.Shared.Components)`
  - `local Matter = require(ReplicatedStorage.Packages.Matter)`

## Wave API (already written — `src/shared/Wave.luau`)
- `Wave.GetHeight(x, z, t) -> number` — vertical displacement (what buoyancy samples).
- `Wave.GetDisplacement(x, z, t) -> Vector3` — full Gerstner xyz offset (renderer).
- `Wave.GetNormal(x, z, t) -> Vector3` — surface normal.

## Components (already written — `src/shared/Components.luau`)
- `Components.Boat` data: `{ model: Model, hull: BasePart, seat: Seat, floaters: {VectorForce}, owner: Player }`
- `Components.Fish` data: `{ model: Model }`
- `Components.Position` data: `{ value: Vector3 }`
- `Components.Velocity` data: `{ value: Vector3 }`
- `Components.Wander` data: `{ dir: Vector3, timer: number }`

## Matter cheat-sheet
- Spawn: `local id = world:spawn(Components.Fish({model=m}), Components.Position({value=p}))`
- Query: `for id, fish, pos in world:query(Components.Fish, Components.Position) do ... end`
- Read one: `local boat = world:get(id, Components.Boat)`
- Update a component (immutable): `world:insert(id, Components.Position({value = newP}))`
  or `world:insert(id, pos:patch({ value = newP }))`
- Despawn: `world:despawn(id)`
- A **system** is `return function(world, state) ... end`. `state` is the table below.

## `state` (2nd arg to every system)
```
state = {
  config = Config,
  players = Players,                 -- the Players service
  boatFolder = Folder,               -- workspace.Boats  (parent boat models here)
  fishFolder = Folder,               -- workspace.Fish   (parent fish models here)
  boatInput = { [Player] = {throttle=number, steer=number} },  -- latest drive input
  remotes = { SpawnBoat = RemoteEvent, BoatInput = RemoteEvent },
}
```

## Remotes (created by server bootstrap, under ReplicatedStorage.Remotes)
- `SpawnBoat` — client fires (no args) to request a boat.
- `BoatInput` — client fires `(throttle: number, steer: number)` each input change; both -1..1.

---

# Module assignments

### A. `src/client/OceanRenderer.luau`  (ModuleScript) + `src/client/Lighting.luau`
- `OceanRenderer.start(config)`:
  - Build a **single EditableMesh** plane, `config.Ocean.Resolution`² quads spanning
    `config.Ocean.Size` studs, as a MeshPart parented to workspace (Anchored, CanCollide off,
    Material = Water if available else Glass, Color/Transparency from config).
  - Each `RenderStepped`, recenter the plane under the camera (snap to grid cell so it tiles),
    and set every vertex Y (and xz Gerstner pull) via `Wave.GetDisplacement(worldX, worldZ, t)`
    with `t = workspace:GetServerTimeNow()`. Recompute normals if cheap.
  - **EditableMesh API is version-sensitive — VERIFY it via context7 or roblox docs before coding**
    (`AssetService:CreateEditableMesh`, `:AddVertex`, `:AddTriangle`, `:SetPosition`, and
    `AssetService:CreateMeshPartAsync(Content.fromObject(em))`). Include a clearly-separated
    fallback `buildPartGrid()` (a grid of thin Anchored parts displaced by `Wave.GetHeight`)
    behind a `USE_EDITABLE_MESH` flag, so we can switch live if the EditableMesh path misbehaves.
  - Performance: only update vertices within view distance; this is prototype-rough, keep it simple.
- `Lighting.apply()`: set a pleasant daytime sea look — ClockTime ~14, an Atmosphere, Sky,
  subtle Bloom + ColorCorrection, Sunrays. Idempotent (safe to call once).
- Both return a table with the named function(s).

### B. `src/server/systems/BuoyancySystem.luau` + `src/server/systems/BoatMovementSystem.luau`
- **BuoyancySystem** `return function(world, state)`:
  - `local t = workspace:GetServerTimeNow()`.
  - For each `id, boat in world:query(Components.Boat)`: for each `vf` in `boat.floaters`:
    - `local p = vf.Attachment0.WorldPosition`
    - `local surfaceY = state.config.Ocean.BaseY + Wave.GetHeight(p.X, p.Z, t)`
    - `local depth = surfaceY - p.Y` (how far the floater is under the surface)
    - If `depth > 0`: upward = `depth * Buoyancy.Strength` minus
      `Buoyancy.VerticalDamping * boat.hull.AssemblyLinearVelocity.Y` (clamp upward >= 0-ish).
      Else upward = 0.
    - `vf.Force = Vector3.new(0, upward, 0)` (the VectorForces are RelativeTo World; set by BoatFactory).
  - Net effect: hull rides + tilts with the waves. Skip boats whose `model.Parent == nil`
    (despawned); optionally `world:despawn(id)` if the model is gone.
- **BoatMovementSystem** `return function(world, state)`:
  - For each boat: read `input = state.boatInput[boat.owner]` (default throttle/steer 0).
    Only drive while someone sits (`boat.seat.Occupant ~= nil`).
  - Apply forward force along the hull's look vector ∝ `input.throttle * Config.Boat.DriveForce`,
    tapered as speed approaches `Config.Boat.MaxSpeed`. Apply yaw torque ∝
    `input.steer * Config.Boat.TurnTorque`. Apply horizontal water drag (`LinearDrag`) and
    angular drag (`AngularDrag`) opposing current velocity/spin.
  - Use `hull:ApplyImpulse` / `hull:ApplyAngularImpulse` scaled by `state` dt
    (use `Matter.useDeltaTime()`), OR persistent VectorForce/Torque you create once and store
    via attributes on the hull — your choice, but keep it stable (no runaway spin).

### C. `src/server/BoatFactory.luau`  (ModuleScript)
- `BoatFactory.build(cframe) -> (model: Model, seat: Seat, floaters: {VectorForce}, hull: BasePart)`
- Build a small boat **entirely from Parts/WedgeParts** (no meshes, no toolbox): a flat hull
  base (the `hull`, set as `model.PrimaryPart`), low side walls, a pointed bow (WedgeParts),
  and a `Seat` welded on top facing forward. Weld everything to the hull (WeldConstraints);
  only the hull drives physics. Reasonable size (~ 8 x 2 x 16 studs), light `CustomPhysicalProperties`
  density (~0.4) so it floats nicely. Place at `cframe`.
- Create `Config.Buoyancy.FloaterCount` **Attachments** on the hull bottom, spread to the four
  corners (so wave tilt produces roll/pitch). For each, create a `VectorForce`:
  `Attachment0 = thatAttachment`, `RelativeTo = Enum.ActuatorRelativeTo.World`,
  `ApplyAtCenterOfMass = false`, `Force = Vector3.zero`, parented to the hull. Return them in `floaters`.
- Return `model, seat, floaters, hull`.

### D. `src/server/systems/FishSpawnSystem.luau` + `src/server/systems/FishAISystem.luau`
- **FishSpawnSystem** `return function(world, state)`:
  - Throttle with `Matter.useThrottle(0.5)` so it only acts ~twice a second.
  - Count current fish (`world:query(Components.Fish)`). While count < `Config.Fish.MaxCount`
    and at least one player exists, spawn a fish near a random player within `SpawnRadius`,
    at a random depth in `[DepthMin, DepthMax]` below `Ocean.BaseY`. Build the fish model from
    Parts (a small ellipsoid-ish body + a wedge tail, ~2-3 studs, Anchored PrimaryPart,
    CanCollide off), parent to `state.fishFolder`, and
    `world:spawn(Components.Fish({model=m}), Components.Position({value=p}), Components.Velocity({value=v0}), Components.Wander({dir=randDir, timer=0}))`.
  - Despawn fish farther than `DespawnRadius` from every player (`world:despawn(id)` + `model:Destroy()`).
- **FishAISystem** `return function(world, state)`:
  - `dt = Matter.useDeltaTime()`, `t = workspace:GetServerTimeNow()`.
  - For each `id, fish, pos, vel, wander in world:query(Fish, Position, Velocity, Wander)`:
    - **Wander**: occasionally re-roll `wander.dir` (timer-based). Steer velocity toward it at `TurnRate`.
    - **Separation**: push gently away from nearby fish (within `Config.Fish.Separation`).
    - **Depth band**: keep `pos.value.Y` between `BaseY+DepthMin` and `BaseY+DepthMax`
      (steer up/down); never breach the surface (`Wave.GetHeight`).
    - Normalize to `Config.Fish.Speed`, integrate position, and set the model `CFrame` to look
      along velocity. Use `world:insert` to store updated Position/Velocity/Wander.
  - Keep it O(n²) simple for `MaxCount` ~45; that's fine.

### E. `src/client/ui/SpawnMenu.luau` + `src/client/ui/BoatHUD.luau`
- Hand-built UI (no toolbox). Respect Isaac's **left-bias**: load-bearing info (speed, status)
  goes on the LEFT; quiet actions on the right.
- **SpawnMenu** `SpawnMenu.mount(remotes)`: a clean ScreenGui with a single prominent
  "🚤 Spawn Boat" button (bottom-left). On click, `remotes.SpawnBoat:FireServer()`.
  Flat, rounded corners, dark translucent panel, no AI-slop gradients.
- **BoatHUD** `BoatHUD.mount(remotes)`:
  - Detect when the LocalPlayer is seated in a boat seat (watch `Humanoid.Seated` /
    `Humanoid.SeatPart`; a boat seat lives under `workspace.Boats`). Show the HUD only while seated.
  - On-screen controls: throttle (W/S or up/down buttons) and steering (A/D or a slider),
    plus a left-side speedometer reading `seatPart.AssemblyLinearVelocity.Magnitude`.
  - Each input change, `remotes.BoatInput:FireServer(throttle, steer)` with values in -1..1.
    Also read keyboard (W/A/S/D) via UserInputService and feed the same path.
  - Hide + send `(0,0)` when the player stands up.
- Both return a table with `.mount`.

## Acceptance (each module)
- File at the exact path above, `--!strict`, returns the specified table/function.
- No requires to anything not listed here. No external packages beyond `Matter`.
- Reads tunables from `Config`; never hard-codes sea level or wave math (use `Wave`).
