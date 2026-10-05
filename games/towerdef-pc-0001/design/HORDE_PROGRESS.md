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
