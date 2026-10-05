# MASS_HORDE — genuine mass-horde redesign

Governing: `PLAYTEST_FEEDBACK_3.md` (waves of 100s → 1,000s → 10,000s; a liquid, physics-based crowd like *Sir, We Have an Orc Problem*; `horde_mult` splitting is REJECTED), then FEEDBACK_2, FEEDBACK_1, HORDE_BRIEF.

## Architecture

### 1. HordeWorld — C#-resident body store
- `HordeWorld` is a plain C# class (no `Node`) owning every body array as SoA `double[]`/`int[]`/`byte[]`: `px, py, vx, vy, hp, maxHp, radius, mass, speed, dmg, atkCd, slowT, slowM, shockT, hitT, kind, flags, gen`, plus a free list. The arrays stay on the C# side for the whole run. **No arrays are copied across the boundary on a tick.**
- GDScript gets a thin `[GlobalClass] HordeWorldHandle : RefCounted` that wraps one `HordeWorld`. Its methods take and return scalars or small packed results only: `Spawn(kind, x, y, count, seed)`, `Step(dt)`, `Count()`, the query API (§5), `DrainEvents()`, `FillMultiMesh(rid)`, `Save()/Load()`.
- Body identity is `(slot, gen)` packed into an `int` (a 20-bit slot and a 12-bit generation), so stale handles can be detected. Kind stats come from a `KindTable` that GDScript pushes once at boot from `Tune.gd`/the enemy defs. Rules data stays authored in GDScript; C# executes it.
- Capacity: grow-only, with power-of-two doubling and a hard cap of 65,536. A spawn past the cap is queued (the queue is a ring buffer in C#) and emerges as bodies die. That turns the hard cap into "the gate is full" pressure instead of dropped units.

### 2. Flow field toward the core
- Coarse grid of 32 px cells (128×128 for the 4096 px arena). Every cell stores an integrated-cost distance and a unit flow vector.
- Recomputed **only when the building set changes** (place, sell, destroy, or Core upgrade). TowerState bumps `buildings_version` and the handle calls `RebuildFlow(blockedCells, targetCells)` with packed int arrays. The recompute is a Dijkstra from the core cells, with 8-neighbour moves, weights 1/√2, and no corner cutting. Building cells are **obstacles with a high cost (e.g. 40)** rather than walls. A walled-in core still has a finite path, so the horde flows *into* the wall and chews through it. This is the Orc-Problem siege behaviour.
- Cost: about 16k cells, under 1 ms in C#. It runs on build events, not per tick. Each body samples its cell's vector with a bilinear blend of 4 cells to avoid lane banding.

### 3. Fluid crowd model (fixed step 1/60 s)
Per body, in ascending slot order:
1. **Seek:** `a = (flow·speed·slowMul − v) · k_accel`.
2. **Pressure/separation:** a uniform hash with a cell equal to 2× the max swarm radius (16 px). It is rebuilt each step with a counting sort (`head/link`, no allocation). Over the 3×3 neighbourhood, overlapping pairs push apart with `k_p · overlap/(r_i+r_j)`, weighted by `mass_j/(mass_i+mass_j)`. Heavies plough through swarmers, and swarmers pile against heavies and walls.
3. **Damping and limit:** `v *= (1 − k_damp·dt)`, then clamp `|v| ≤ vmax`. `vmax` is above the seek speed, so impulses can briefly overshoot. That gives the splash.
4. **Integrate:** `p += v·dt`. Then resolve against building discs and the core disc by projecting out and zeroing the inward normal velocity. The crowd **piles up** at a wall, and back-pressure propagates through the separation term. Gaps fill naturally, and when a wall dies the dammed mass **surges** through.
5. **Impulses:** `ApplyImpulse(x, y, r, strength, falloff)` adds `Δv = strength·(1−d/r)/mass` radially. Explosions part the sea, and the sea refills it.

### 4. Contact rule
A body whose disc touches a building disc (or the core) with `atkCd ≤ 0` emits an `ATTACK(target, dmg)` event and resets its cooldown. Ranged kinds emit `SHOT` within `r_fire`. Couriers emit `ESCAPE` at their exit. Events go into a C# ring buffer. GDScript calls `DrainEvents()` once per tick and gets one `PackedInt32Array` plus one `PackedFloat64Array`, **aggregated per target**: (target, hits, dmgSum). There are no per-body events, so 10k bodies on a wall give one row per building.

### 5. Combat query API (for GDScript weapons)
Every query runs against the same spatial hash. It returns aggregates, never per-body arrays, unless a small N is requested:
- `DamageRadius(x, y, r, dmg, impulse, flagsMask) -> [kills, hits, dmgDealt, cashSum, xpSum, coinSum]`
- `DamageCone(x, y, dirX, dirY, halfAngle, range, dmg, impulse)` and `DamageLine(x0, y0, x1, y1, width, dmg, pierceMax)`, both returning the same aggregate.
- `NearestN(x, y, n, maxR) -> PackedInt32Array ids` (targeting; n is at most 64). `DensestCell(x, y, range)` for splash towers aiming at the thickest knot.
- `Chain(startId, jumps, jumpR, dmg, falloff) -> aggregate + PackedVector2Array hop positions` (for the VFX).
- `ApplyImpulse` (§3), `ApplyStatus(x, y, r, slow, shock, dur)`.
- Death pass: a killed body credits `cash/xp/coin` into the aggregate, pushes a corpse decal `(x, y, kind)` into a capped ring (for example 4,096) for the view, and frees the slot at the end of the step. Kill counts, missions and achievements read the aggregates. The economy is designed per kill at swarm scale (see the balance section later), not scaled-down single-enemy values.
- Sample positions: each damage query also returns up to 8 hit positions for VFX. The view never iterates bodies.

### 6. Elites and bosses
These are the same world and the same arrays, with `flags` bits `ELITE` and `BOSS` and high `mass/radius/hp`. They take part in pressure, so a boss shoves the swarm aside. Their special abilities (aura, summon, charge) are C# switch cases keyed by kind code and run after the move pass. Summons call the internal `Spawn`. GDScript can ask `Bosses() -> PackedInt32Array` (fewer than 16) for health bars and the Intel panel.

### 7. Determinism
- All sim state is `double`, and Godot `Vector2` (float32) is never used in HordeWorld. Iteration always runs in ascending slot order. The hash is built deterministically, so bucket order follows slot order. There is no `Parallel.For` in the step: any future threading must be partitioned so the results do not depend on order (two-phase compute and apply).
- RNG: a per-world `xorshift64*` seeded from the run seed and the wave index. It is consumed only on the sim thread. `Math.Sqrt` is IEEE-exact. Avoid `Math.Sin/Cos` in the step, or table them, because cross-platform libm can differ.
- Bench verified: two fresh worlds stepped 60 times are bit-identical (below).

### 8. Budgets (60 fps = 16.7 ms frame)
| Item | 10k | 20k |
|---|---|---|
| Sim step (move + hash + pressure) | ≤ 2 ms | ≤ 4 ms |
| Weapon queries (all towers) | ≤ 1 ms | ≤ 1.5 ms |
| MultiMesh fill + upload | ≤ 0.5 ms | ≤ 1 ms |
| Flow rebuild (event only) | < 1 ms | < 1 ms |
At 40k the dense core pile is roughly 4× the 20k cost, from neighbour counts. **Shipping caps live bodies at 20k**, with the excess queued at the gates (§1). "10,000s" waves are sustained streams of 10–30k total across the wave, with no more than 20k alive.

### 9. Rendering
- One `MultiMeshInstance2D` per visual class (swarm, heavy, elite/boss) with `use_custom_data` for tint and flash. `HordeWorldHandle.FillMultiMesh(rid, class)` writes a reused `float[]` (12 floats per instance for a 2D transform, plus colour and custom) and calls `RenderingServer.MultimeshSetBuffer` once per class per frame. `visible_instance_count` is set to the live count. The interpolation alpha is applied in C# from the previous and current positions.
- Corpses are drawn as a second MultiMesh from the corpse ring (blood decals). There is no per-body Node, and there are no `_draw` loops over bodies.
- Fallback: if the C# runtime is unavailable, there is no horde. Mass horde is C#-only; the mono build is the shipping target. GPU compute is not needed at 20k (bench). We will propose it only if the 50k+ ambition comes back.

### 10. Save and test hooks
- `Save()` returns a `PackedByteArray` (live bodies + RNG + queue + flow version). `Load(bytes)` restores it. Wave-boundary saves remain the default.
- `Checksum() -> int64` (FNV over px/py/hp bits) for determinism assertions in selftest: the same seed and inputs must give the same checksum after N steps.
- `Stats() -> Dictionary` (alive, queued, kills, max pile density, step µs) for the Intel panel and playtest metrics.
- selftest cases: spawn → flow reaches core; wall blocks → pile → surge on destroy; impulse parts the crowd; radius damage aggregates are correct; save/load round-trip checksum.

### 11. Migration
- **EnemyStore.gd** becomes a facade over `HordeWorldHandle`. Its public query/damage methods keep their signatures where weapons rely on them, but delegate. The GDScript SoA path is retired. The per-body fields (`share`, the `horde_mult` split) are removed. `horde_mult` stays a legacy test knob that defaults to 1 and is not exposed in shipping UI.
- **EnemyHash.gd** is replaced by the C# hash. Its tests are re-aimed at the C# queries (assertions updated deliberately and documented, not deleted).
- **HordeMove.cs** is folded into `HordeWorld.Step`. Its float32 bit-parity contract with GDScript is dropped deliberately: it existed only to mirror the GDScript path, which goes away. The determinism contract moves to the double-precision C# checksum.
- **TowerState** keeps rules, economy and waves. It owns `buildings_version`, drives `RebuildFlow`, consumes `DrainEvents` for building/core damage, and consumes query aggregates for the economy. Wave defs move from enemy counts × mult to **designed swarm compositions**: an early tier in the hundreds, mid tiers in the thousands, late tiers at 10k+.

### 12. Feasibility microbenchmark (measured 2026-10-05)
Standalone .NET 8 console (Release), 4-core Xeon @ 2.1 GHz (cloud container, much slower than the owner's desktop). Bodies were ring-spawned and converging on the core through the flow field + 16 px uniform-hash pressure + damping + vmax + core-disc projection. Timing covers 600 steps after a 120-step warmup, by which point a dense pile has formed at the core.

| Bodies | step ms | MultiMesh fill ms | deterministic |
|---|---|---|---|
| 10,000 | 1.09 | 0.03 | yes |
| 20,000 | 3.08 | 0.04 | yes |
| 40,000 | 11.77 | 0.12 | yes |

Verdict: 10k and 20k fit the 60 fps budget comfortably on single-threaded C# with doubles, even on this weak CPU. The super-linear 40k figure comes from pile density, which the per-pair cap and the 20k live cap address. Bench source: the scratchpad `hbench/Program.cs`. It is deliberately kept out of the Godot project so it is not compiled into the game assembly.

## Blockers
- None for architecture. Open risk: the cost of GDScript→C# call marshalling per weapon query. Mitigation: batch tower queries into one `FireAll(packed tower table)` call if profiling shows more than 1 ms.
