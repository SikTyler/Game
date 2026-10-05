# HORDE progress log

## Phase 1 — SoA + eid map + EnemyHash (horde-p1)

**Outcome: done, bit-identical.**

### What changed
- `EnemyStore.gd` (new, pure RefCounted, `TowerState.en`): every body is a slot in packed arrays (`PackedFloat64Array` for every float field, `PackedInt32Array` ints/flags, `PackedVector2Array` pos/vel/exit, `PackedStringArray` kind). Free list (`free_head`/`next_free`, O(1) alloc/release, slots recycled), stable `eid_slot` map (`slot_of(eid)`), and `order` = live slots in spawn order, compacted in `_reap` exactly like the old `enemies` Array. All rule loops iterate `en.order`.
- `EnemyHash.gd` (new, `TowerState.eh`): 32 px uniform grid over CENTER ± 512 (outside bodies clamp into edge cells, so nothing is missed). Counting-sort rebuild, lazy on `en.dirty` (set by move, Pulse knock, spawn, reap, escape, test writes), so every query sees current positions. Cells hold spawn-order ranks: candidates come back in spawn order and callers keep the Dict code's exact predicates and tie operators (`<=` in `_nearest`/carry, `<` + d² in `pick_target`, `>`/`<` in `_densest`). API: `candidates`, `rect` (railgun segment AABB), `in_radius`, `nearest`, `density` (exact count, cell walk), `damage`, `impulse`/`radial_impulse` (Phase-4 knockback; not called at horde_mult 1).
- Ported to the hash: `pick_target`, `_nearest`, `_hit_carry`, Gun/Flak/Mortar splash, Railgun line, Frost aura, Tesla chains, Core cannon splash / slag / beam (`beam_eid` via the map) / pulse (+ Static chain) / Storm free pulse, Lancer pierce, Orbital strike, `_densest` (exact count via hash), troops (`Troops.step(troops, en, eh, dt, ctx)`: contact/taunt, `_eid_index`, `_seek`, sapper AoE; troop hits resolve eid -> slot), `cast_special` (EMP/live count). `_hit`/`_shred`/`_roll_drops`/`_core_damage` take a slot.
- `_move_enemies`: the hot pass now runs inside `EnemyStore.move()` (own-member packed access is ~5x faster than `en.x[s]` from TowerState) and returns an ordered `[op, arg]` log (wall broke / ranged shot / melee hit / courier escape). TowerState replays the Core-side effects in the same order; nothing replayed feeds back into another body's movement, so results and the event stream are identical.
- Readers: `Main.enemy_pos` (eid map), `Battle` draw + hover tip (hash), `Hotbar` count, `_shots.gd`, `playtest.gd` use the store / `enemy_count()`.
- Accessors for tests/tools: `add_enemy(dict)` (defaults = the Dict code's `.get()` fallbacks, assigns eid), `set_enemies(list)`, `enemy_dict(eid)`, `enemy_list()`, `enemy_count()`, `set_enemy(eid, fields)`.
- selftest: injection goes through the store; `_sync()` copies live store values back into the test's Dicts before the same assertions; `_push()` writes test edits back; `_troop_q()` builds a standalone store+hash for the Troops unit tests. **No assertion was weakened or removed; no literal changed.** New `_horde_stages`: the 120 s golden + store/hash invariants (slot reuse, spawn order kept after reap, eid map, in_radius/nearest/damage/density).
- `horde_fp.gd` (new): 120 s seeded fingerprint, 4 sims (one per Core attack: cannon/slag/beam/pulse) on a full board (Gun, Mortar, Tesla, Frost, Flak, Railgun, 3 huts, Barricade) from wave 14 with a 150-body fragile flood at t=30 s (kills, carry, splits, troops all engage). SHA-256 over wave/kills/cash/hp, `_densest` result and every body's eid/pos/hp/slow_t/shield each sim second. Golden **99dfcba3…** recorded from the Dict implementation (commit before the port) and asserted in selftest.
- `tools/horde/hlib.gd` + `profile.gd` adapted to the store (cap patch anchors, HP pin, rebuild counter).

### Gates
- `--import`, `--quit-after 120`: clean (no SCRIPT ERROR / ERROR: / Failed to load).
- selftest: **SELFTEST OK** (incl. the golden: fingerprint == Dict golden).
- uitest: **UITEST OK** (158 PASS, same as baseline).
- playtest: **PLAYTEST OK**; full `PLAYTEST METRICS` JSON diffed against `design/baseline/playtest_metrics.json`: **0 differences** (excluding `runtime_s`). Runtime 550 s vs 503 s baseline (+9%, same container class; the bot sims run ≤220 bodies where the hash is mostly on its small-n path).

### Profile (tools/horde/profile.gd, full board, 40 substeps, HP pinned, ms per substep; baseline = HORDE_BASELINE Dict impl)

| bodies | `_step` ms (base → now) | move ms | fire ms | reap ms | `_densest` |
|---|---|---|---|---|---|
| 220 | 0.56 → **0.29** | 0.36 → 0.12 | 0.05 → 0.07 | 0.05 → 0.03 | 17 ms → 2.5 ms |
| 1,000 | 2.75 → **1.13** | 1.89 → 0.51 | 0.20 → 0.25 | 0.25 → 0.09 | 370 ms → 35 ms |
| 5,000 | 16.3 → **5.6** | 11.0 → 2.7 | 1.31 → 1.19 | 1.48 → 0.42 | 11.3 s → 0.82 s |

Move is ~0.5 µs/body (plan target ≤3 µs incl. separation: met with room). Spawn is still ~7.5 µs/body (TuneRef/EnemyDB lookups per spawn, not storage). Achievements+Missions on events: 0.67 ms @1k, 2.8 ms @5k (Phase 2 aggregation's job).

### Open / notes
- `_densest` stays an exact neighbour count (C13): 1.1 s at 5k bodies piled on the stop ring. Fine at today's 220 cap; at horde scale it needs the cell-histogram approximation (changes Orbital auto-aim ties, so it belongs with the Phase-3 behaviour change).
- EnemyHash keys are `(cell << 20) | spawn_rank` in a natively sorted PackedInt64Array; a cell row is one contiguous run found by `bsearch`. A first counting-sort version paid a fixed 1024-cell prefix pass per rebuild, which made low-count sims slower than the Dict code (a playtest run took 1718 s vs 503 s baseline — partly also orphaned processes from an aborted earlier run); replaced, plus a small-n fast path (≤64 bodies: candidates = `order`, no rebuild). Seeded 4×120 s fingerprint sim: Dict 2.04 s → SoA 1.48 s.
- Queries whose AABB covers ≥ half the grid (Railgun 590 px, big Core ranges) return the whole `order` (exact superset, no gather/sort).
- `tools/horde/draw.gd` (Phase-0 draw profiler) still reads `S.enemies`; not adapted (Phase 2 replaces the draw path with MultiMesh).

## Phase 2 — horde_mult, event aggregation, MultiMesh view (horde-p2)

### What landed
- **`horde_mult`** (`Tune.horde_mult()`, GF_TUNE `{"horde_mult":m}`, clamped 1..16, default 1). `_spawn_due` spawns each plan entry as `m` bodies: the first through the normal `_spawn` (same rng draws), then `_spawn_clones` copies it m-1 times, fanned ±2° around the Core by body index. **No extra rng draws**, so the wave sequence is unchanged. Each body's hp/max_hp/dmg/cash/xp/coin = entry × 1/m (new `EnemyStore.share`). **Single bodies:** boss, elite (whole shields, C5), marked elites and couriers. Splitter mites inherit the parent's share.
- **Armor split (C4):** `_core_damage(..., share)` subtracts `armor × share` per body hit. The 25% floor is unchanged.
- **Kills per body (C2):** `kills`, Stats and Missions count bodies. To keep pacing, kill-count thresholds scale by m: the daily "Kill N" mission target is `(150+10B)×m` and ACH_KILLS_100K is `100000×m`.
- **Loot (C3):** loot rolls once per body. Parts and scrap only come from boss, elite and courier kills, which are all single bodies. A horde body rolls the per-kill key at `p×share`, so keys per wave are conserved at any m. Loot stays per body and low value, and the expected value per wave is unchanged. I did not add a new "common horde trinket" currency, because that would inflate the economy. It is left for the economy pass if the owner wants visible frequent drops.
- **Event aggregation** (`TowerState.aggregate_events`, called per substep in `tick` only when m>1; at m=1 the stream is untouched): per-body `kill` (except boss), `dmg` and `core_hit`/`enemy_shot` events collapse into `kills{n,cash,by_kind,pos_sample≤16}`, `hits{n,sum,crit_n,top≤8}` and `core_hits{n,dmg,shots,pos_sample≤8}`. Consumers:
  - Stats and Missions add `n`.
  - Achievements treats these events as HOT, and `core_hits` sets damaged_early.
  - `Main._handle` draws one burst/ring per sampled position, one trauma for `core_hits`, and damage popups only for the top 8 hits. Popups merge per 64 px cell, so numbers no longer stack.
  - Sfx plays once per aggregate and keeps its existing GAP_MS rate limit.
- **View:** `Battle._draw_enemies` uses one `MultiMesh` per enemy kind: an ArrayMesh unit quad textured with the kind's SVG icon. The 12-float instance buffer is refilled from SoA each frame. Per-instance colour gives the hit flash (over-bright) and the slow tint. Marked/shield overlays and HP bars are drawn only for boss/elite/courier/marked bodies. Enemy SVG imports are raised to `svg/scale=2.0` (128 px raster), which makes them crisp at 1080p.
- **MAX_ENEMIES:** the 220 constant is kept. The cap is now `max_bodies() = MAX_ENEMIES × horde_mult`, so behaviour at m=1 is identical (C1).
- **Tests:** selftest gained Phase 2 checks:
  - conservation at m=4 (hp/cash/dmg)
  - body budget
  - armor split
  - the aggregation schema, with the boss kill kept single
  - aggregated kills counted in Stats
  
  No existing assertion changed. The `tools/horde/hlib.gd` anchors and `draw.gd` were ported to the store.

### Gates
- `--import` clean; `--quit-after 120`: no errors; **SELFTEST OK** (HORDE FP golden unchanged); **UITEST OK**; shots rendered (16_battle_late shows the MultiMesh enemies upright and crisp).
- **PLAYTEST OK at horde_mult 1**: the `PLAYTEST METRICS` JSON vs `design/baseline/playtest_metrics.json` gives **0 differences** (excluding runtime_s). Runtime was 1873 s, with 4 playtests running in parallel on 4 cores.
- **Warning for future runs:** the playtest jobs share `user://pt_jobs` snapshots. Running several playtests in parallel corrupts them (a first attempt crashed at playtest.gd:161 and gave a false m=1 diff). Give each concurrent run its own `XDG_DATA_HOME`.

### Playtest at horde_mult 2 / 4 / 8 (GF_TUNE overrides; deltas vs baseline)
| m | result | gates failing | metric keys differing |
|---|---|---|---|
| 1 | **OK** | — | 0 |
| 2 | FAIL | progressable, no_death_spiral, seeds_ok, rd_loops_faster, rd_no_dominant_part | 38 |
| 4 | FAIL | t2_by_day5, mix_beats_weapon, ac38_eco_mix, rd_no_dominant_part, ac25_fresh_wall | 38 |
| 8 | FAIL | progressable, no_death_spiral, mix_beats_weapon, seeds_ok, pc_modifiers_reach_w25, pc_modifiers_fair, rd_archetypes_viable, rd_no_dominant_part, ac29_wave_gap, ac25_fresh_wall | 46 |

Headline numbers (base → m2 / m4 / m8): balanced_best 30 → 30/30/30; eco_best 16 → 17/19/20; first_wave 20 → 30/20/30; day30 hi-tier wave 86 → 87/88/88; t2_day 3 → 3/2/5; t3_day 6 → 6/7/5.

**Per-weapon AoE vs single-target value.** These are `mono_same_save` mean waves on the same save: gun = single target; mortar/tesla = AoE/chain.

| m | d7 balanced / gun / mortar / tesla | d20 balanced / gun / mortar / tesla |
|---|---|---|
| 1 | 54.5 / 51.5 / 50.0 / 53.0 | 78.5 / 76.0 / 76.5 / 75.0 |
| 2 | 58.5 / 53.0 / 51.5 / 57.0 | 75.0 / 68.0 / 74.5 / 76.0 |
| 4 | 56.5 / 15.0 / 10.0 / 15.0 | 76.5 / 74.5 / 75.5 / 75.0 |
| 8 | 60.0 / 56.5 / 56.0 / 60.0 | 75.0 / 46.0 / 46.0 / 48.0 |

Reading the table:
- Single-target gun loses the most value as m grows (d20: 76 → 68 at m2). Tesla gains relative to it at m2, which matches R5.
- At m4 (d7) and m8 (d20), every mono board collapses (10–15 / 46–48 waves). Mixed boards hold at 75–78.
- Balanced runs barely move, and eco gains (cheaper kills feed cash/s).
- The failing gates are balance gates (death spiral / progress / dominance), not crashes.

Retuning for m>1 is owner-facing balance work: weapon cadence and AoE scaling, plus the Phase 3 contact rule, which cuts Core damage once only the front rank attacks. The default stays m=1 until then.

### Profile (container CPU, llvmpipe)
Sim, `tools/horde/profile.gd` full board, 20 substeps, HP pinned, ms per substep (GF_TUNE m=1; m=8 within noise):

| bodies | `_step` | move | fire | reap | Ach+Missions on events |
|---|---|---|---|---|---|
| 1,000 | 0.91 | 0.41 | 0.16 | 0.08 | 0.34 |
| 5,000 | 5.0 | 2.5 | 0.95 | 0.42 | 1.7 |
| 10,000 | 10.0 | 4.8 | 2.0 | 0.77 | 3.2 |

The profile harness drives `_step` directly with bodies at the stop ring, so its event handling is the raw per-event stream (381 events/substep at 10k, mostly core_hit). In the game, `tick()` collapses these into at most 3 aggregate records per substep when m>1. Each aggregate costs O(1) in Stats, Missions and Main, plus O(events) for the single collapse pass.

Draw, `tools/horde/draw.gd` (xvfb llvmpipe), `_draw_world` CPU per frame (baseline immediate mode → MultiMesh):

| bodies | `_draw_world` CPU | frame (llvmpipe, upper bound) |
|---|---|---|
| 1,000 | 8.16 → **2.14 ms** | 39.9 → 16.8 ms |
| 5,000 | 38.3 → **9.95 ms** | 155 → 58 ms |
| 10,000 | — → **19.4 ms** | — → 91 ms |

The remaining ~2 µs/body is the GDScript buffer fill. It still needs a real-GPU re-check on the owner's RTX 5080 (R9). Moving the fill into EnemyStore as a packed write is the Phase 7 lever.

## Owner feedback #1: run rules (commits 5de3ed1, e5bd5a0, + tools fix)
Implemented in the engine (TowerState / EnemyStore / Draft / Labs / Outpost / BaseMeta), tested in selftest:
1. **Lanes removed.** Spawns are uniform around the Core on `spawn_r()`. The quadrant plan, lane focus (API, Z/V hotkeys, hotbar/Battle UI) and lane walls are gone. The telegraph is now `{total, elites, boss}`. The Encircled modifier is repurposed to +25% enemies.
2. **Buildings block.** Every building has HP: 40, or 200 for the Barricade, ×1.35 per level, × enemy damage growth. Buildings repair 50% at each wave start. An enemy whose leading edge touches a building cell stops and attacks it (`ACT_BLD`, `bld_hit` events; `bld_hits` at horde>1). At 0 HP the building is destroyed and lost for the run (`building_destroyed`, `bld_lost`). Melee contact with the Core is now at STOP_R 34 px.
3. **Live drafts:** `time_scale()` is always 1.0.
4. **Grid research:** "grid" lab (cost 150×3^L) sets the grid to 3/5/7/8/10. The board is 11×11 with the Core at (5,5). Rings no longer open from track totals. The view zooms to `spawn_r()`. Bastion Heart is now one grid step smaller.
5. **Core tracks:** at most 8 levels (Range: 6), costs 60–90 × 2.0–2.3^L, and each level has a drawback (see `TRACKS.minus`).
6. **Difficulty:** enemy HP ×2.5 and damage ×1.5 (`pc_enemy_hp` / `pc_enemy_dmg`). The first fresh run dies at wave ~16–21.
7. **Typed rewards:** every card carries `reward` (building/upgrade/perk/ability). A duplicate weapon is a new building (`dup`). A non-weapon duplicate sets `pending_upgrade`, which the player applies with `apply_upgrade(cell)` (click or drag), or drops with `cancel_upgrade`. `perk_list()` returns packs, gold perks and Insight.
8. **No seed retry:** results show "Play again" with a new random run; history Retry and Ctrl+R replay are removed.
9. **Gems removed:** legacy gems convert to coins at 25 each on load. Missions, streak and tier rewards pay coins. Chests and card slots cost coins. Crates open with keys or coins. Rush/skip are removed. The Gem Mine is now the Deep Mine (coins).
10. **Instant builds and research:** queued jobs in old saves complete on the next tick or claim. Lab Speed is removed.
Also: the top bar shows run coins, scrap and keys live.

Test changes are deliberate and tagged `FEEDBACK-1`/`FB1` in selftest/uitest. Lane, ring, gem, timer and seed-retry assertions were replaced by assertions of the new rules. HP literals are × `difficulty_hp()`. The HORDE golden was re-recorded (82857cc8…) with an added two-run determinism check.
Playtest gate changes: the gem gates now assert zero gems. New gate `first_run_short` (first run 300–480 s). The bot applies upgrades, buys grid research first, and spends ≤15% of the bank on cards.

### Gates
import, --quit-after 120: clean · SELFTEST OK · UITEST OK · shots rendered (fb1shots).
**PLAYTEST FAIL, 19 gates:** progressable, no_death_spiral, t2_by_day5, tier3_by_day30, offline_below_active, ac38_eco_mix, first_run_short (245 s; band 300–480), no_plateau_after_t3, seeds_ok, pc_endless_runs, rd_frontier_band, rd_no_plateau, rd_loops_faster, rd_archetypes_viable, rd_outpost_share, rd_ac27_storage_fill, ac29_wave_gap, ac25_fresh_wall, set4_no_trap.
Key metrics: the main campaign never reaches T2 (t2_day -1; best wave at day 30 is 49), with boss walls at w20/w30. Day-1 best wave is 21. Active coin rate is 975/min against 285/min offline.
Cause: ×2.5 HP is too steep for the meta curve once building loss and the big-step tracks are combined. The early harness (fresh.gd, 24 runs) put T2 near day 6, but the full campaign stalls below w40.
Next pass (blocked by the effort cap, not attempted): taper `pc_enemy_hp` by tier/wave (e.g. 2.5 early → 1.6 by w20), soften the T1 w20/w30 boss ramp, then rerun the playtest.

### Profile (tools/horde/profile.gd, full board, 20 substeps)
| bodies | step ms (before → after) | move ms (before → after) |
|---|---|---|
| 1,000 | 0.91 → 0.76 | 0.41 → 0.59 |
| 5,000 | 5.0 → 4.24 | 2.5 → 3.07 |

The building block check adds about 25% to move. Total step time is lower because fewer events are emitted.

## HORDE Phases 3+4: fixed substeps, one-pass move with separation, contact rule, knockback
Commits: P3+P4 core, then the separation perf fix (both on towerdef-0001).
- **C8, fixed substeps:** `tick()` adds `delta*speed` to `step_acc` and runs a whole `_step(SUBSTEP=0.05)` for each full substep. A short frame may run no step, and the remainder carries over. At 60 fps and 1×, the sim steps every third frame. View interpolation between steps is NOT done yet (follow-up for Phase 6), so motion can look choppy at 1×.
- **One hot pass** (`EnemyStore.move`): timers, then courier/taunt, then seek toward CENTER with acceleration (`horde_accel` 6/s up to `spd`), then soft separation, then knockback velocity with friction (`horde_friction` 6/s), then the stop-ring wall.
  - Separation is a linked-cell grid (32 px cells, 96×96) built in-pass from the old positions (a Jacobi read), weighted by mass so heavy bodies shove light ones. It is capped at `size*0.35` per substep, and the scan is capped at 12 candidates per body (`prm[4]`, deterministic spawn order). Bodies off the grid skip separation.
- **Contact rule:** a body that is blocked by a building (leading edge in a standing building's cell) attacks that building first. Otherwise only bodies with `|p-C| <= stop + size/2 + 0.5` attack the Core. Rear ranks pile up and do not attack.
- **Knockback:** `EnemyStore.knock` applies `vel += J/mass`, with mass = (size/16)². Bosses and couriers are immune.
  - Single-target hits push away from the shooter with `KNOCK_W[weapon] * horde_knock(60) * (0.25 + min(1, dmg/max_hp))`. Gun 0.6, railgun 1.6, flak 0.5, tesla 0.3, Core 1.0.
  - Mortar uses `radial_knock` (linear falloff, 1.5× splash).
  - The Pulse 12 px teleport is replaced by an equivalent outward impulse: 12 px total under friction.
- **Deterministic:** the HORDE golden 120 s fingerprint did not change (9376f262…; the seeded run never exceeds the cap or reaches the crowd regime there), and the two-run determinism check passes.
- **Tests (deliberate, tagged):**
  - New selftest `_horde_p34`: fixed-substep accumulate/carry, separation, front-rank-only contact, knock v/mass with boss immunity, and friction.
  - The pulse-knockback assertion now checks outward velocity instead of displacement (Phase 4).
  - selftest `tick(0.01)` literals → `tick(0.05)`, because a tick shorter than a substep now runs no step.
  - The uitest "Space resumes" check now waits, bounded at 120 frames, for one substep.

### Gates
import clean · --quit-after 120 clean · SELFTEST OK · UITEST OK · PLAYTEST FAIL **15** (baseline after feedback-1: 19).
- **Now passing:** progressable, no_death_spiral, rd_no_plateau, rd_archetypes_viable, set4_no_trap.
- **Newly failing:** no_plateau_before_t3.
- **Still failing:** t2_by_day5 (t2_day **8**, was never), tier3_by_day30, offline_below_active (314 offline vs 1071 active /min), ac38_eco_mix, first_run_short (244.5 s; band 300–480), no_plateau_after_t3, seeds_ok, pc_endless_runs, rd_frontier_band, rd_loops_faster, rd_outpost_share, rd_ac27_storage_fill, ac29_wave_gap, ac25_fresh_wall.
- The contact rule cut Core damage (only the front rank hits), so the main campaign now reaches T2. The balance taper proposed in the feedback-1 section is still the next lever. It was not attempted, because of the effort cap.

### Profile (tools/horde/profile.gd, full board, 20 substeps; move = seek+separation+knock in one pass)
| bodies | move ms (feedback-1 → P3/4) | step ms |
|---|---|---|
| 1,000 | 0.59 → 4.9 | 5.1 |
| 5,000 | 3.07 → 20.5 | 21.3 |
| 10,000 | — → 38.9 | 41.5 |

The profile scatters bodies over the board, so they overlap heavily: the crowd is denser than a packed horde. Before the neighbour cap, the cost grew quadratically (444 ms at 10k).

**Verdict:** GDScript cannot hold 60 fps at the HORDE_PLAN PC target. At 20 Hz substeps, 5k bodies cost about 420 ms per second of sim at 1× (2× and 3× speed multiply that), and 10k cost about 830 ms/s.

**PROPOSAL (not implemented, owner decision):** move `EnemyStore.move` and the separation grid to a C# (or GDExtension C++) hot loop over the same packed arrays. The expected gain is 20–50× in the inner pair loop, which puts 10k under 2 ms per substep. Alternatively, a compute-shader separation pass with a CPU readback of positions. A cheaper step first: cap separation to every other substep, or use the 12-candidate scan only inside the crowd band near the Core.

## Phases 5 + 6 (view only) — outcome

- **Gore (P5):** `vfx/Gore.gd` — pooled one-shot GPUParticles2D blood emitters (low 6 / full 16, round-robin, no allocation in a kill storm) + a never-cleared 2048² SubViewport ground layer (covers 2600 world units around the Core). Corpses/blood are stamp commands in a capped ring buffer (512); at most 24 (low) / 96 (full) are drawn per frame with UPDATE_ONCE, so cost is per new stamp, not per corpse. Battle draws the ground texture under the grid/world. Horde `kills` aggregates stamp every body (count `n`), not just the 16-position sample. Run reset clears via CLEAR_MODE_ONCE.
- **Setting:** `video.gore` off/low/full in settings.cfg (default low), Settings > Video row "Gore"; live-applied each frame.
- **Feedback (P6):** Juice caps — trauma added per frame ≤ 0.35, total ≤ 0.8; hit-stop ≤ 0.08 s with a 0.6 s cooldown; mass-kill (n ≥ 40 per substep) hit-stop 0.03 s. Screen shake now honours the existing "Screen shake" / "Reduce motion" settings (it was ignored before). Damage numbers get a drop shadow (aggregation per 64 px cell unchanged).
- **Debug overlay (P6):** F3 toggles; shows bodies, FPS, sim ms (smoothed wall time of `S.tick`), hash ms (`EnemyHash.last_us`, last rebuild), hash cells (distinct occupied cells), gore level + queued stamps. Timing fields are view-only and do not affect the sim.
- **Tests:** uitest +6 checks (gore default low, cycles + persists, view follows, off persists, F3 on/off with all stat keys). No assertions changed.
- **Gates:** import OK; `--quit-after 120` clean; SELFTEST OK (golden/hash unchanged — sim untouched); UITEST OK; PLAYTEST FAIL on the same 15 gates as after P3+P4 (view-only change, expected).
- **Shot:** `_shots.gd` adds `21_horde_gore.png` (900 extra bodies at horde_mult 10, gore full, overlay on). Under xvfb software GL: ~420 live bodies, sim 3.8 ms, hash 0.26 ms, 101 cells; FPS figure under xvfb is not representative.
- **Note:** the ground stamps are subtle at the default zoom; the field-wide red tint in the shot is the existing core-hit flash, not gore.

## FB1 run-screen UI (PLAYTEST_FEEDBACK_1) — view only, sim unchanged
- Range on click: selecting any building draws its reach (weapons: live range circle; non-weapons: aura square over the 8 neighbours). `Battle.range_of / preview_range / draw_reach`.
- Projectiles: every shot tracer now carries a visible travelling projectile head (muzzle -> target over the tracer life).
- Live currencies: top-left bar already adds this run's coins / scrap / keys live (confirmed, unchanged).
- Placement preview: while placing (taken pick or dragged card) the cursor becomes the building icon on the hovered cell, with its range radius, tinted green (valid) / red (with the reason). World tooltips are suppressed while placing.
- Left bar: Build/Info + hotkey legend removed; it is now the PERKS menu (gold perks, stat perks/packs, insights, mutations) whenever no draft is open. Weapon Target button floats under the selected weapon on the field.
- Right Core panel gains "Enemies killed" (bodies). Track number badges removed.
- Bottom bar removed: field and side panels run to the window bottom; specials are floating round icons over the bottom of the field (cooldown sweep + copy pips, no key labels, no FIELD / NEXT DRAFT text). The field prompt sits above them.
- Draft cards: coloured type banner with icon — BUILDING (blue, "Place another <X>" for weapon duplicates), UPGRADE (green, "Drag onto your <Building>" for non-weapon duplicates), PERK (gold, "listed under Perks"), ABILITY (cyan). Hotkey badges and "[key]" text removed from cards, Reroll/Banish/Cancel, track tips, ability tips and the top bar.
- Tooltips: structured RichTextLabel — bold gold header, then one stat line per row (" · " split) led by a related icon (dmg/HP/rate/range/cash/coins/level/cooldown...). `tip_label` keeps the canonical plain text.
- uitest: +15 FB1 checks. One deliberate assertion change: PC-U1 "top bar, left, field, right, hotbar do not overlap" — the hotbar rect now lives inside the field by design, so it left the no-overlap set and a new check asserts the field encloses it and the panels reach the bottom.
- Shots: 15_place now hovers a free cell (preview + range); 16 selects a weapon if one survives.
- Gates: --import / --quit-after clean; SELFTEST OK; UITEST OK; playtest: see below.
- Playtest: same 15 balance-gate FAILs as after P3-P6 (e.g. ac25_fresh_wall, ac29_wave_gap, rd_ac27_storage_fill) — expected, this change is view-only; no new failures.

## FB1 home / outpost / art (PLAYTEST_FEEDBACK_1) — view + Outpost map data; run sim unchanged
- Home IS the Outpost: tabs "play" and "outpost" both render it (`Hub.is_home`). The nav row is now small buttons: Outpost (or "Back to Outpost"), Missions, Reforge; on the right, tier < TIER n >, Modes and PLAY Tn (`DSTART`). The old Play column (active Core, how-a-run-works, summaries) is gone.
- Command Plaza: a 4-column strip west of the grid with four clickable buildings (Core Bay with the active Core's art, Crates, Research Lab, Card Hall). Clicking one opens its screen; hover shows a tooltip; badges sit on the buildings. A Research Hall on the grid also gets an "Open" button.
- Map much larger: `OutpostDB` W/H 14x10 -> 24x16. Plots 0-7 are unchanged; nine new grid chunks (8-16), +3 Crystal Veins and +4 rocks inside them. Locked land hides its veins and rocks (fogged; the tooltip says the contents are unknown until bought). The builder queue strip is removed (builds are instant), so the map gains that height. Header strip: Relay, Power, coins/scrap/keys per hour and Charm, each with an icon and a tooltip, plus Collect all.
- Build palette: a "BUILD" header; categories are a 2x2 grid of icon tabs (Production / Support / Links / Decor); entries show a coin icon and cost; hotkey badges are removed.
- Upgrades show what they do: `OutpostView.upgrade_delta(s, uid)` (pure, computed on a copy) gives [label, before, after] rows. A "NEXT UPGRADE" block in the selected panel shows them; the Upgrade tooltip lists them. Mill: Coins/hour 1080 -> 1350, Storage. Relay: Power, max building level, generator limits, Collect all at Lv3. Also covered: research queues, barracks troop bonus, archive insights/banish, warehouse and scrapyard %.
- Crates: once the reveal is done, each revealed part card is clickable ("Open in Core Bay") -> `Main.open_part_in_bay` -> Core Bay with filters cleared, paged to that part and selected.
- Core Bay: double-click (<=450 ms, same part) equips into the best slot (empty fitting slot first, else replaces the part there); double-click an installed part (inventory or slot) unequips it. A hint line under the grid explains this.
- Crisp SVG: all 292 `art/*.svg.import` now use svg/scale = ceil(256/longest side) (48px art -> x6, 64 -> x4, 128 -> x2), with mipmaps generated. `project.godot` sets the canvas default_texture_filter to linear-mipmaps. Before, the 48/64 px rasters were upscaled to 100-170 px on screen, which was the blur. All textures are drawn via draw_texture_rect, so layout does not change.
- Input: map clicks on the home are ignored while the away-collect modal is open (fix found by uitest). Enter on the home starts a run only when nothing is armed or selected.
- uitest: +17 FB1 checks (`_fb1_home`), covering the home/plaza/nav, the map size, category icons, the 4 plaza buildings opening their screens, Back to Outpost, hidden veins, the Mill and Relay before->after, crate item -> bay, double-click equip / replace / unequip, and 256 px rasters. One literal changed on purpose: `_press("DTAB Play")` -> `_press("DTAB Outpost")`. The Play tab button no longer exists; the assertion after it is unchanged.
- Shots reviewed (fb1shots 02_play = home, 03_bay, 04c_crate_done, 05*_outpost*). Fixed from the renders: truncated category labels (moved to 2x2), the header hint truncation, and too-dark locked land.
- Gates: --import clean; --quit-after 120 clean; SELFTEST OK (sim/golden untouched; Outpost selftests pass on the larger map); UITEST OK.
- Playtest: FAIL on 15 balance gates, the same count as after P3-P6/FB1 run-ui: t2_by_day5, tier3_by_day30, no_plateau_before_t3, offline_below_active, ac38_eco_mix, first_run_short, no_plateau_after_t3, seeds_ok, pc_endless_runs, rd_frontier_band, rd_loops_faster, rd_outpost_share, rd_ac27_storage_fill, ac29_wave_gap, ac25_fresh_wall. These are run-balance gates; this change does not touch the run sim. The playtest Outpost plan only uses plots 0-7, which are unchanged. No new SCRIPT ERRORs.
