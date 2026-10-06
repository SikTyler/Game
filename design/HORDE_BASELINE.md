# HORDE BASELINE (Phase 0)

- **Game code SHA measured:** `fa26547346c85f5b769f49e9c2bfdd1829aba975`. This is the branch `towerdef-0001` head at the start of Phase 0. Later Phase-0 commits only add `design/` docs and `tools/horde/`.
- **Engine:** Godot 4.6.3.stable.official.7d41c59c4.
- **Machine:** headless Linux container, 4 vCPU, no GPU (Mesa llvmpipe for render runs).
- **Raw logs:** `design/baseline/selftest.log`, `uitest.log`, `playtest.log`. The full sorted metrics JSON is in `design/baseline/playtest_metrics.json`.

## 1. Gate status

| Suite | Result | Notes |
|---|---|---|
| selftest.gd | **SELFTEST OK** (exit 0) | |
| uitest.gd | **UITEST OK** (exit 0) | |
| playtest.gd | **PLAYTEST OK** (exit 0) | Every gate in `GATES + RD_GATES` is true. Runtime 503 s (4 workers). |

### PLAYTEST METRICS summary
These are the numbers to diff after every horde phase. At horde_mult = 1 they must be identical except `runtime_s`.

**Gates (all true):**
- Core gates: solvent, first_goal_reachable, progressable, no_death_spiral, no_trivial_dominant.
- Campaign gates: t2_by_day5, tier3_by_day30, no_plateau_before_t3, no_plateau_after_t3, early_3day_rise.
- Gem gates: gems_per_day_ok, gem_sources_ok.
- Strategy gates: offline_below_active, mix_beats_weapon, mix_beats_eco, no_dominant_perk, ac38_eco_mix, ac39_no_mono, day1_band, seeds_ok.
- PC gates: pc_refinery_not_dominant, pc_modifiers_reach_w25, pc_modifiers_fair, pc_endless_runs.
- Redesign gates: rd_ac27_storage_fill, rd_archetypes_viable, rd_early_power, rd_frontier_band, rd_gems_sane, rd_loops_complete, rd_loops_faster, rd_no_dominant_part, rd_no_dominant_set, rd_no_plateau, rd_no_runaway, rd_outpost_share, rd_wall_exists.
- Also true: ac25_fresh_wall, ac29_spec_identity, ac29_wave_gap, ac38_strict, day1_in_target_band, fresh_median_first_goal, set4_no_trap.

**Informational metrics that are false today and are not gates:** `ac29_campaign_ok`, `mono_same_save_below_70`, `set4_fair`. Keep them as-is. A flip in either direction counts as a delta.

**Key numbers:**

| Metric | Value |
|---|---|
| first run | wave 20, 15 levels, 387 coins, 490 s |
| balanced_waves | [20,20,20,20,30,20,20,20] (best 30) |
| weapon_waves | [20,20,30,20,30,20,30,30] (best 30) |
| eco_waves | [6,10,10,6,10,10,16,10] (best 16) |
| day1_best_wave | 30 |
| t2_day / t3_day | 3 / 6 |
| best_wave_at_t3 | 50 |
| day30_best_wave_hi_tier | 86 |
| final_tier | 7 |
| fresh_runs | median wave 20, min 10, n 16, r_early median 3.93, r_wall median 0.5 |
| gems_total | 720 (24/day) |
| gem_log | boss 289, mission 293, streak 78, tier 60 |
| active_coin_rate / offline | 2760.8 / 507.6 |
| inrun_policy d20 | balanced w78 / 57976 coins; eco w43; weapon (see JSON) |
| mono_same_save d20 | balanced 78.5, gun 76, mortar 76.5, tesla 75 |
| mono_same_save d7 | balanced 54.5, gun 51.5, mortar 50, tesla 53 |
| pc_modifiers_d20 | base w78 / 58500. allsides ratio 1.05. elitist ratio 1.17, dwave −4. Others in JSON. |
| pc_endless_d20 | coin_ratio 0.89, 3 mutations |
| perk_top_coin_ratio | 1.19 |
| set4_probe | hi 83.5, lo 72, lancer 84.5, mint 79.5, storm 76.5, bulwark 72, swarm 72, trap 60 |
| ac29_specs | eco_coins_per_run_x 0.68, single_boss_dps_x 0.89 |

## 2. Peak live-enemy counts under the real bot policy

The harness is `tools/horde/peak.gd`. It builds an instrumented runtime copy of TowerState and a re-pointed playtest copy in `user://`. Counters are added in `_spawn`; game files are not touched. It runs playtest's own jobs in-process.

| Run | Peak `enemies.size()` | at wave | Refused at cap | Bodies spawned |
|---|---|---|---|---|
| fresh save, balanced (3 seeds) | 24 / 14 / 15 | 30 / 20 / 20 | 0 | 1140 / 581 / 583 |
| playtest `main` campaign (30 days, T1→T7) | **53** | 79 | 0 | 460,639 |
| playtest `forge:balanced` (reforge loops) | **69** | 80 | 0 | 194,487 |
| playtest `mods` (challenge modifiers incl. allsides/swarm/elitist, endless) | 35 | 67 | 0 | 139,381 |

**Correction to the brief:** the competent bot never has more than **~70** enemies alive. `MAX_ENEMIES = 220` is never reached in any playtest job. Only selftest's synthetic "T5 w60 10 s flood" reaches it. Enemies die quickly; the bot dies to HP scaling, not to count.

## 3. tick() cost per substep (Dict implementation)

The harness is `tools/horde/profile.gd`, with MAX_ENEMIES lifted in the runtime copy. Enemies are injected with the engine's own `_spawn(kind, ev, at, quad)` at random positions in the STOP_R..SPAWN_R annulus, using a 9-kind mix. HP is pinned at 1e15 so the count stays constant, and wave is set to 30. Each figure is the mean over 40 substeps of 0.05 s. Phase splits come from separate calls on the same state.

**Full board** (Core + 2 Gun, 2 Mortar, 2 Tesla, Frost, Flak, 2 Railgun):

| bodies | `_step` ms | move ms | fire ms | reap ms | troops ms | events/substep | Achievements+Missions on events ms | `_densest` (one Orbital auto-aim) |
|---|---|---|---|---|---|---|---|---|
| 220 | **0.56** | 0.36 | 0.05 | 0.05 | 0.00 | 16 | 0.17 | 17 ms |
| 1,000 | **2.75** | 1.89 | 0.20 | 0.25 | 0.00 | 65 | 0.61 | 370 ms |
| 5,000 | **16.3** | 11.0 | 1.31 | 1.48 | 0.01 | 305 | 2.69 | **11.3 s** (O(n²)) |

**Core only:** 0.42 / 2.27 / 10.8 ms per substep at 220 / 1k / 5k.

Spawn cost is about 8 µs per body (a Dict allocation each).

Reading the numbers:
- `_move_enemies` dominates at about **2.2 µs per enemy per substep**. That is Dict get/set on roughly 8 keys, with no neighbour work yet.
- `_fire` is cheap here because the weapons are few and pick_target is O(n) per shot. With the bot's real cadence (Core 1.25/s, Gun 2/s) it is 0.2 ms at 1k. It would grow with more weapons or the carry hops.
- Main runs one substep per 60 fps frame at speed 1. At speed 3 it runs ~1 substep of 0.05 s. Above ~1.5k Dict enemies the sim alone would blow the 16.6 ms frame (including `_handle`).
- `_densest` is unusable above ~300 bodies: an Orbital cast at 1k would hitch for 370 ms.

## 4. Draw cost of the current immediate-mode `Battle._draw_world`

The harness is `tools/horde/draw.gd`, run under xvfb with Mesa llvmpipe (software GL). A bare Node2D calls `Battle._draw_world` each frame. Half the bodies are damaged (HP bar), 1/5 are slowed and 1/3 are hit-flashing.

| bodies | `_draw_world` CPU (command recording) | frame time (llvmpipe, upper bound) |
|---|---|---|
| 220 | 1.69 ms | 24.6 ms |
| 1,000 | 8.16 ms | 39.9 ms |
| 5,000 | **38.3 ms** | 155 ms |

That is about **7.6 µs of CPU per enemy per frame** just to record ~5–6 canvas commands. The recording alone exceeds a 16.6 ms frame at about 2,000 enemies, before the GPU or the sim. A MultiMesh buffer fill (12 floats per instance, written in one PackedFloat32Array) is estimated at ≤0.5 µs per body in GDScript. llvmpipe frame times are not representative of a real GPU; re-measure on the owner's RTX 5080 in Phase 2.

## 5. Harness

`tools/horde/` holds throwaway scripts, not shipped. To reproduce, start in `games/towerdef-pc-0001`:

```
godot --headless --path . --script ../../tools/horde/peak.gd -- n=3            # fresh runs
godot --headless --path . --script ../../tools/horde/peak.gd -- job=main       # any playtest job
godot --headless --path . --script ../../tools/horde/profile.gd -- counts=220,1000,5000 steps=40 densest [board=core]
xvfb-run -a godot --path . --script ../../tools/horde/draw.gd -- counts=220,1000,5000
```
