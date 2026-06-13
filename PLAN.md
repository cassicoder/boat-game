# Boat Game — build plan

Roblox boating game, built **live on the base place via the Roblox Studio MCP**.
Stack: **Matter ECS** · **EditableMesh Gerstner ocean** · custom buoyancy · auto fish · spawnable part-boats with custom HUD. Scope: **prototype-rough** (functional first, polish later). No toolbox assets.

## Architecture
- `ReplicatedStorage/Shared/Wave` — Gerstner math (height/displacement/normal). Shared by render + physics. ✅ written
- `ReplicatedStorage/Packages/Matter` — ECS framework (vendored at build).
- `ReplicatedStorage/Shared/Components` — Matter components (Boat, Fish, Floater, Velocity, ...).
- `ServerScriptService/Server` — world bootstrap + systems: Buoyancy, BoatMovement, FishSpawn, FishAI, Spawn.
- `StarterPlayerScripts/Client` — OceanRenderer (EditableMesh), BoatController + HUD, SpawnMenu, Lighting.

## Build steps (each testable in Studio once MCP is connected)
1. **Foundation** — vendor Matter, world bootstrap, Components, Lighting/water color. *Test: place loads, console prints ECS tick.*
2. **Ocean** — EditableMesh grid displaced by Wave each frame, with LOD. *Test: animated waves visible.*
3. **Buoyancy + boat** — BoatFactory builds a part-boat (hull + Seat); BuoyancySystem floats/bobs it on the waves; custom HUD (throttle/steer) drives it via VectorForce + yaw torque. *Test: spawn, sit, drive, rides waves.*
4. **Fish** — FishSpawnSystem streams fish entities; FishAI = wander + separation + depth band; distance-culled. *Test: fish appear and swim.*
5. **Spawn UI + polish** — spawn menu, counters, foam at wake, atmosphere. *Test: full loop.*

## Subagent partition
Once the Wave + ECS contract is fixed, fan out isolated modules: Ocean renderer · Fish systems · UI · Boat factory/physics — each coded against the shared contract, then integrated and verified live.

## Status
- [x] Research (ECS, Gerstner, buoyancy, MCP) + outline + memory note
- [x] Scaffold + Wave math module
- [ ] **GATE: connect Roblox Studio MCP** (Isaac — Studio toggle + Claude Code restart)
- [ ] Steps 1–5 live build
