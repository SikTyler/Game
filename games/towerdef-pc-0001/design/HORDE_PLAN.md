# HORDE PLAN — Phase 0 audit + plan (Corehold PC, towerdef-pc-0001)

Governing doc: `design/HORDE_BRIEF.md` (owner's verbatim brief). Phase 0 changed
no game code; measurements are in `design/HORDE_BASELINE.md`, raw logs in
`design/baseline/`, throwaway harness in `tools/horde/`.
All refs are `file:line` at audit SHA `fa26547` (start of Phase 0).

---------------------------------------------------------------------------

## 1. Owner's description: confirmed / corrected

| Claim | Verdict | Detail |
|---|---|---|
| "~10–220 enemies" | **Corrected (in part)** | 220 is a hard cap, not a typical count: `TowerState.gd:48 MAX_ENEMIES = 220`. `_spawn` returns false (the spawn is lost, not queued) when the field is full (`TowerState.gd:1239`). Splitter mites are dropped the same way. Measured with the real playtest bot (HORDE_BASELINE §2): peaks are **14–24** on fresh runs and **53–69** across the whole 30-day campaign, forge loops, modifiers and endless. The cap was **never** reached; only selftest's synthetic flood (selftest.gd:1058) hits it. So the realistic range is "~10–70", and 220 is the cap. |
| Dictionaries in `TowerState.enemies` | **Confirmed** | `TowerState.gd:100`. The real schema is wider than the comment: `kind,pos,hp,max_hp,spd,dmg,cash,xp,coin,size,atk_cd,slow_t,slow_m,shield,fire_cd,shock_t,shock_src,hit_t,eid,taunt_t,quad` + optional `max_shield,marked,exit,shred_n` (`TowerState.gd:1251-1283`, `_shred` 1803). |
| Deterministic, seeded, headless `tick()` | **Confirmed** | `tick` 869-880 splits real `delta*speed` into `n = ceil(d/SUBSTEP)` equal substeps (`SUBSTEP = 0.05`, line 49). Each substep is `_step` 883-917, with `dt = sub * time_scale()` and SLOWMO 0.2 while a draft is open. There are 4 independent RNG streams (88-91): `rng` (wave plan, kind rolls, spawn jitter), `drop_rng` (loot, courier, mark), `draft_rng`, `combat_rng` (crits, wave skip). They are seeded from the run seed in `setup` (236-239). Correction: the substep is **variable-length** (`d/n` ≤ 0.05), not fixed. Results are speed-invariant only because tests use fixed `DT=0.1` (`playtest.gd:52`). Iteration order (`enemies` array order) is part of determinism: targeting ties, `_nearest` uses `<=` (later index wins), and crits roll per shot in loop order. |
| Immediate-mode drawing in `ui/Battle.gd` | **Confirmed** | `Battle._draw_world` 295-356. Per enemy it draws 1 `draw_texture_rect` (SVG icon via `Kit.icon` → `ArtDB.tex`), up to 3 arcs (marked/slow/shield), 1 hit-flash circle and 2 HP-bar rects. Everything goes through Main's single `_draw` (`Main.gd` → `Battle.draw`). Fx come from FxPools (`Main.gd:92-96`), the kill bursts are CPUParticles2D (`vfx/Bursts.gd`, POOL 12), and shake/hit-stop come from `vfx/Juice.gd`. |
| No nodes / no physics | **Confirmed** | Enemies have no nodes. Movement is a straight radial seek with no collision or separation (`_move_enemies` 1329-1391). |

Other facts the plan must respect:
- Enemies **never overlap-resolve**. Every non-ranged enemy that reaches `STOP_R` (200) attacks the Core every 1.0 s (`TowerState.gd:1385-1388`). Today **all** arrived bodies attack, so total contact DPS scales with the count.
- `_reap` (1849-1887) rebuilds the array (`enemies = alive`) every substep. Compaction keeps order stable.
- Tests and tools read `S.enemies` as Dicts directly: `selftest.gd` (81 references, including literal enemy Dicts **without `eid`**, e.g. 100, 111), `playtest.gd` (6: bot boss check, `camp_run` HP probe via eid ordering), `Main.gd:647`, `Battle.gd:156,333`, `Hotbar.gd:75`.

## 2. Systems touching enemies (rating: untouched / adapt / rewrite)

| # | System | Ref | Rating | Reason |
|---|---|---|---|---|
| 1 | Wave plan `_build_plan` / `_spawn_due` / `_roll_kind` | TowerState.gd:1125-1235 | **adapt** | Must emit `horde_mult` bodies per entry without extra `rng` draws at mult 1. Telegraph `counts`/`total` semantics need a decision (entries vs bodies). |
| 2 | `_spawn` (incl. boss/elite/ranged/marked branches, cap) | 1238-1289 | **adapt** | Writes into SoA slots via the free list. Divides hp/cash/xp/coin/dmg by mult. Cap becomes a body budget. |
| 3 | `_spawn_courier` | 1294-1304 | **adapt** | Uses `enemies.back()`; switch to the returned eid. Courier stays a single body. |
| 4 | `_move_enemies` (seek, slow/shock/hit timers, taunt, wall slow+wear, ranged fire, contact attack, courier escape) | 1329-1391 | **rewrite** | Becomes the single hot pass: accel/max-speed seek, separation via EnemyHash, contact rule. Timers move to packed arrays. Wall wear stays per-body (sums are conserved). |
| 5 | `pick_target` (4 modes, flyers-only) | 1397-1429 | **rewrite** | O(n) scan → `EnemyHash.in_radius`/`nearest`. Tie-break must reproduce the current order. |
| 6 | `_nearest` | 1454-1468 | **rewrite** | Hash nearest; `<=` tie = highest slot index today (see determinism). |
| 7 | `_hit` (ironclad, elite shield, boss/normal mult, shred, lifesteal, dmg event) | 1473-1502 | **adapt** | Same math on SoA; event emission goes into the aggregator. |
| 8 | `_hit_carry` (overkill carry, Dict-keyed `done`) | 1509-1538 | **rewrite** | O(n) per hop + Dict-as-key → hash nearest with an eid exclusion set. |
| 9 | `_fire` buildings: frost aura | 1574-1589 | **adapt** | → `in_radius`. |
| 10 | `_fire`: railgun line pierce | 1604-1618 | **adapt** | → hash cells along the segment (capsule query). |
| 11 | `_fire`: flak (prey x2.5 on flyers) | 1619-1621 | **untouched** (beyond index→slot) | Single target. |
| 12 | `_fire`: mortar splash + min_range | 1591, 1622-1630 | **adapt** | → `damage(center,r)`. Later phase adds `radial_impulse`. |
| 13 | `_fire`: tesla chain (`_nearest` 90 px, shock_src) | 1631-1648 | **adapt** | → hash nearest. `shock_src` stays a slot index of the *weapon* (not an eid). |
| 14 | `_fire`: gun default → `_hit_carry` | 1649-1651 | **adapt** | Via #8. |
| 15 | `_beam_hold` (Lance) | 1655-1664 | **adapt** | O(n) eid scan → eid→slot map. |
| 16 | `_core_fire` cannon (barrels, splash_frac) | 1676-1705 | **adapt** | → hash; per-target `targets` eid list must be capped/aggregated. |
| 17 | `_core_fire` slag | 1706-1721 | **adapt** | → `damage`. |
| 18 | `_core_fire` beam (strongest) | 1722-1744 | **adapt** | Strongest-in-range via hash; `beam_eid` via the map. |
| 19 | `_core_fire` pulse (+knock 0.3*40 px, chain_every sort of ALL outer enemies) | 1745-1778 | **rewrite** | `inside.has()` is O(n²) and the outer `sort_custom` is O(n log n) of Dicts. The knock becomes the knockback system's `radial_impulse`. |
| 20 | `_pierce` (Lancer 4p) | 1784-1797 | **adapt** | Linear `enemies[k]==te` Dict compare → slot. |
| 21 | `_shred` | 1801-1803 | **untouched** (field move) | Per-enemy counter → packed int. |
| 22 | `_free_pulse` (Storm 4p) | 1807-1816 | **adapt** | → `in_radius`. |
| 23 | Troops (`Troops.step`, `_eid_index`, `_seek`, contact/taunt, sapper AoE) + `_troops_step` hit loop | Troops.gd:114-261, TowerState.gd:1820-1838 | **rewrite** | Per troop: O(n) contact scan, O(n) eid lookup, O(n) seek; per hit, an O(n) eid scan in TowerState. Port to the hash + eid map; Troops.gd receives a query object instead of the Array. |
| 24 | `_reap` (cash/xp/coin, bounty zones, kill event, splitter→mites, drops) | 1849-1887 | **rewrite** | Free-list release instead of rebuilding the array; kill aggregation; mite spawn after compaction. |
| 25 | `_roll_drops` / `Drops.roll` (key roll on **every** kill) | 1892-1907, Drops.gd:42-62 | **adapt** | One `drop_rng` draw per body breaks conservation and determinism under mult. See CONFLICTS C3. |
| 26 | `_boss_bounty` | 1911-1922 | **untouched** | Boss stays single. |
| 27 | `_core_damage` (reflect via `src`, armor, shield, last stand) | 1307-1326 | **adapt** | `src` Dict → slot; per-hit `core_hit` events → aggregated (armor-per-hit maths stays per body, see risk R3). |
| 28 | Orbital Strike resolution | 950-956 | **adapt** | → `damage(c,r)`. |
| 29 | `cast_special` (live count, EMP all, `_densest`) | 2265-2328 | **adapt** | Live count is O(n). EMP loops all bodies (fine as a packed loop). |
| 30 | `_densest` (O(n²)) | 2333-2353 | **rewrite** | Hash cell-count density (per brief). Tie rules: focused lane +1, then closest to the Core. |
| 31 | Walls (`_sync_walls`, `_rebuild_walls`, wear in move) | 780-799, 1366-1376 | **adapt** | Logic stays; wear moves into the hot pass. |
| 32 | `move_cost` (`enemies.is_empty()`) | 2434 | **adapt** | → `alive_count == 0`. |
| 33 | Missions (`kill` +1 per event) | Missions.gd:82-83 | **adapt** | Read `n` from aggregated kill events. |
| 34 | Stats (`kills`, `kills_by_kind`) | Stats.gd:62-64 | **adapt** | Aggregated `{kind→n}`. |
| 35 | Achievements (`HOT` list, `core_hit` early-damage flag, lifetime kills ≥100000 via Stats) | Achievements.gd:23,115-117,191 | **adapt** | The early-damage flag must survive aggregation (dmg sum > 0). Kill totals come through Stats. |
| 36 | `Main._handle` (sfx per event, tracers, `_dmg_num`, kill bursts/rings, core_hit trauma, shield rings, split) | Main.gd:791-880 | **rewrite** | One sfx/fx call per event today. It must consume aggregated per-substep records with caps. |
| 37 | `Main._dmg_num` (linear merge over 48 pool items) | Main.gd:597-614 | **adapt** | Feed from aggregated dmg; keep the per-eid merge only for elites/bosses/top-N. |
| 38 | `Main.enemy_pos` (O(n) eid scan) | Main.gd:645-651 | **adapt** | → eid map. |
| 39 | `Battle.core_attack_fx` (tracer+ring per target eid) | Battle.gd:107-127 | **adapt** | Cap the tracers; it uses `enemy_pos` per target. |
| 40 | `Battle.world_tip` (O(n) hover) | Battle.gd:149-172 | **adapt** | → hash nearest. |
| 41 | `Battle._draw_world` enemy loop | Battle.gd:332-356 | **rewrite** | MultiMesh per kind + per-instance colour; HP bars only for elite/boss. Walls/beam/orbitals/troops stay immediate. |
| 42 | `Hotbar` enemy count | ui/Hotbar.gd:75 | **adapt** | `alive_count`. |
| 43 | Damage numbers / Juice | Main.gd:95, vfx/Juice.gd | **adapt** | Juice already caps trauma (≤1) and hit-pause (max, not sum). Only the per-event call sites change. |
| 44 | Kill bursts | vfx/Bursts.gd (CPUParticles2D ×12) | **adapt** | Gore phase: pooled GPUParticles2D per brief. Bursts stay for elites/boss. |
| 45 | PowerModel snapshot / playtest R-probes | TowerState.gd:2367-2418, playtest.gd:839-900 | **adapt** (test-side) | `camp_run` reads `S.enemies[k]["eid"/"kind"/"max_hp"]`. HP per wave is conserved, so the probe works through an accessor. |
| 46 | Splitter → mites | 1878-1887 | **adapt** | Mites per body: each split body yields `splitter_children` mites at 1/mult each (conserved). |
| 47 | Ranged enemy fire (`enemy_shot`) | 1379-1383 | **adapt** | Per body, dmg/mult. Events aggregated. |
| 48 | `power_snapshot`, `dps()` | 2357-2418 | **untouched** | No enemy reads. |

## 3. Per-enemy balance values

**EnemyDB.DEFS** (`data/EnemyDB.gd:5-16`), wave-1 values:

| kind | hp | spd | dmg | cash | xp | coin | size |
|---|---|---|---|---|---|---|---|
| drone | 6 | 45 | 4 | 1 | 1 | 0.2 | 16 |
| skitter | 3 | 85 | 2 | 1 | 1 | 0.15 | 13 |
| hauler | 24 | 28 | 10 | 3 | 3 | 0.6 | 26 |
| ranged | 8 | 40 | 3 | 2 | 2 | 0.3 | 15 |
| elite | 30 | 32 | 12 | 5 | 5 | 1.0 | 24 |
| splitter | 18 | 38 | 6 | 2 | 2 | 0.4 | 22 |
| mite | 3 | 95 | 1.5 | 0.5 | 0.5 | 0.05 | 10 |
| courier | 12 | 135 | 0 | 5 | 2 | 2.0 | 18 |
| boss | 200 | 22 | 18 | 25 | 15 | 10 | 44 |

**Roll weights** (`EnemyDB.gd:19-20`, `TowerState._roll_kind` 1210-1235): hauler 0.15 (w≥5), splitter 0.10, ranged 0.12, skitter 0.25 (w≥3, plus the hauler weight before w5), elite `Tiers.elite_weight` 0/0.08/0.16 (T1/T2-3/T4+, `Tiers.gd:51-54`; `elitist` modifier ×3), and the remainder → drone. Gates: `Tiers.allows` (Tiers.gd:58-68): ranged w≥8, elite T≥2 & w≥5, splitter T≥3 & w≥5, mite never rolled.

**Scaling at spawn** (`TowerState._spawn` 1242-1283):
- HP = def.hp × `scale()` (806-811: `hp_growth^(w-1)`; growth 1.17/1.18/1.155 by tier, `PowerModel.gd:29-34`; endless past w100 ×1.12/w) × `hp_mult` (tier: `Tiers.hp_mult` = 1.5^(T-1), Tiers.gd:38) × `perk_enemy_hp` × `enemy_hp_mod` (modifiers/mutations) × (1 + 0.15·Gambit packs).
- spd = def.spd × `perk_enemy_spd` × `enemy_spd_mod`.
- dmg = def.dmg × `dmg_growth^(w-1)` (1.06, line 226) × `hp_mult` × `enemy_dmg_mod`. Note that contact dmg scales with the tier HP multiplier.
- cash/xp/coin are flat def values. They are scaled at kill (see below).

**Boss** (1263-1273): HP × `boss_hp_hi` 0.5 (T≥2), or for T1 × (1 + (boss_hp_t1 3.0 − 1)·ramp(w 10→30)), with the first T1 boss (w≤10) × `pc_first_boss` 0.6. dmg × `pc_boss_dmg` 1.0. Cadence `boss_every` = 10 (8 at T≥5, Tiers.gd:47), spawned in `_advance_wave` (1020-1021) on `boss_dir`. Bypasses the plan; refused if at cap.

**Elite shield** (1274-1276): `elite_shield_base` 3 + wave/10 + `elite_shield_add` (Plating mutation). Each hit is absorbed whole (`_hit` 1477-1484). EMP zeroes it (2305).

**Marked elite** (1279-1282, `Drops.elite_mark_roll` Drops.gd:106-110): w≥8, p 0.25/wave on `drop_rng`, HP × `pc_mark_hp` 3.0, counts as BOSSY for Hunter Scope/Lance.

**Ranged**: stop at `ranged_stop` 230, fire every `ranged_fire` 2.0 s for full dmg (1330-1383).

**Contact**: stop at `STOP_R` 200 (line 45). `atk_cd` reset to **1.0 s** (1387). The first hit is immediate (atk_cd starts at 0). Damage goes through `_core_damage` (armor floor `pc_armor_floor` 0.25 × amt, dr, Aegis shield, Mirror reflect).

**Walls**: `pc_wall_r` STOP_R+50, slow `pc_wall_slow` 0.30, wear = dmg·dt per body (1332-1376).

**Troops vs enemies**: contact 0.5 × dmg/s per enemy in contact (Troops.gd:185-190), taunt 0.15 s.

**Courier**: from w15, p `pc_courier_p` 0.006/wave on `drop_rng` (Drops.gd:99-102), 3× speed chord, guaranteed part (rare 40/epic 45/legendary 15) + key (Drops.gd:16,59-60).

**Splitter**: on death spawns `splitter_children` 2 mites at ±10 px (1882-1887). Mites are full EnemyDB mite stats (scaled by the current wave).

**Kill rewards** (`_reap` 1866-1873):
- cash = def.cash × `cash_index` (1.10^(w-1) × (1 + 0.5(T-1)), PowerModel.gd:157-158) × bounty-zone bonus × `kill_cash` × `run_cash_mult` × `kill_cash_mod` × Magnet 2×.
- xp = def.xp × `xp_mult`.
- coin = def.coin × `run_coin_mult`.
- `kills` +1.

**Drop rolls** (`Drops.roll`): boss part p 0.12 + scrap 5·T + core_core 0.25·(1+(T-1)); elite/marked part p 0.03; part cap 3/run; **every non-courier kill rolls a key at `pc_key_p` 0.0005** (Drops.gd:61).

**Plan sizing**: interval = max(`min_spawn` 0.45, 1.8·0.93^(w-1)) × `perk_spawn` / `count_mult` (swarm 1.6, m_horde +20%/stack) (1116-1118). Entries per wave ≤ `pc_plan_max` 400 (1143). `wave_time` is 25 s.

**Hit modifiers**: `ironclad`, `boss_mult`/`normal_mult` (Hunter Scope), `shred` ×5 stacks, crit `pc_crit_mult` 2.0, carry `pc_carry_hops` 2 / `pc_carry_frac` 0.6, `HIT_FLASH` 0.12.

---------------------------------------------------------------------------

## 4. Architecture plan (per brief phases)

### Phase 1 — SoA + eid map + EnemyHash, all targeting ported (horde_mult fixed at 1)

**Files**: new `EnemyStore.gd` (pure RefCounted, owned by TowerState as `en`) and new `EnemyHash.gd`. TowerState.gd gains all call sites. Troops.gd moves to a query-object signature. Main.gd/Battle.gd/Hotbar.gd change their readers. selftest.gd injects through the new API. playtest.gd uses accessors.

**SoA layout** (`EnemyStore`), capacity grows by doubling:
- `PackedVector2Array pos, vel`
- `PackedFloat32Array`? **No: `PackedFloat64Array`** for hp, max_hp, spd, dmg, cash, xp, coin, size, atk_cd, slow_t, slow_m, fire_cd, shock_t, hit_t, taunt_t. GDScript `float` is f64 today, and f32 storage would change results. This is required for bit-identity.
- `PackedInt32Array kind_id, eid, shield, max_shield, shock_src, quad, shred_n, flags (bit0 alive, bit1 marked, bit2 courier), next_free`
- `PackedVector2Array exit` (courier). Kind is an int id into a `KINDS` table, and strings are kept only at the API edge.
- **Free list**: `free_head` + `next_free[]`. `alloc()` pops the head or appends; `release(slot)` clears the alive bit and pushes.
- **eid→slot map**: `Dictionary eid_slot` (int→int), updated on alloc/release. `slot_of(eid)` returns −1 if dead/missing. beam_eid, troop `tgt`, `elite_marked`/courier events and Main.enemy_pos all use it.
- **Order/determinism**: today's semantics depend on array order = spawn order (with compaction). A free list reuses slots and breaks that order. Plan: keep a parallel `PackedInt32Array order` (live slots in spawn order) that is compacted in `_reap` exactly like `alive` today. Every "for e in enemies" becomes "for s in order". This gives bit-identical iteration at horde_mult 1. The free list still gives O(1) alloc and no Dict churn. Compacting `order` is O(n) ints per substep, which is cheap.
- Accessors for tests/tools: `get_dict(slot)` / `to_dicts()` (debug, tests) and `add_enemy(dict)` (selftest injection, fills defaults incl. eid).

**EnemyHash** (uniform grid hash, separate from the 7×7 build grid):
- Cell size **32 px** (≈ 2× the median body size of 16 and ≥ the max separation radius). Field bounding box: CENTER ± (SPAWN_R + margin) = ~1000×1000 → 32×32 = 1024 cells, dense-array buckets. Rebuilt each substep by counting sort (`cell_start`, `cell_items`) in O(n), with no Dicts.
- Queries visit cells in a fixed row-major order and slots in `order` rank order within a cell. They return candidates sorted by `order` rank before tie-breaking, so `nearest`/`pick_target` reproduce the linear scan's winner exactly (same `<=`/`<` semantics on squared distance).
- API: `in_radius(c, r, out)`, `nearest(c, r, exclude)`, `damage(c, r, amt, …)` (helper that calls `_hit`), `impulse(slot, v)`, `radial_impulse(c, r, k, falloff)`. Also `segment(from, dir, reach, half_w)` for the railgun and `density(r)` for `_densest`.
- Large radii (railgun 590 px, mortar 351 range): range queries cover many cells, but the per-cell scan is still cheaper than the Dict loop. `pick_target` "first"/"strongest"/"weakest" still has to visit everything in range, so it uses ring-ordered expansion only for "nearest".
- Bosses (size 44) are inserted by centre. Queries pad by `max_size/2` where the current code adds `size*0.5`.

**Gate**: selftest/uitest/playtest pass with **identical PLAYTEST METRICS JSON** (except `runtime_s`) to HORDE_BASELINE.

### Phase 2 — MultiMesh rendering + event aggregation + horde_mult (no separation)

**horde_mult conservation** (`horde_mult` int ∈ {1,2,4,8,16}, Tune `horde_mult`, settings later):
- Each plan entry spawns `m` bodies (same kind, same quadrant; jitter ±2° deterministic by body index, **no extra `rng` draws** so the wave sequence is unchanged). Body stats: hp, max_hp, dmg ÷ m. cash/xp/coin ÷ m are accumulated in f64, so totals are exact up to float rounding (no integer remainders, since all reward pools are floats today). `kills`, Missions, Stats and achievements count **plan-entry kills, not bodies**: a body kill adds 1/m to a per-entry counter, and the entry counts as 1 kill when its last body dies (store the `group` id per body). This keeps "Mission/stat/achievement kill counts match" literally, at the same value for any m. Elite shields: per body = ceil(shield/m)? Shields absorb **whole hits**, so splitting changes value non-linearly. See CONFLICTS C5.
- **Stays per entry (single body)**: boss, courier, marked elite (loot carrier, single eid event), mites (mites come from a split body → `children` mites at 1/m each; that would be m·2 mites per splitter entry with HP/m, conserving totals).
- Drops: roll once per **entry** death (the last body), not per body. That keeps `drop_rng` call counts and loot identical at m=1 and conserved at m>1 (C3).
- `MAX_ENEMIES` becomes a body budget (`220 × m` at the start, then the measured target). Refusal semantics stay (C1).
- Contact damage ÷ m per body. With no separation in Phase 2, all bodies arrive, so the total DPS is conserved.
- Telegraph `counts`/`total` stay in entries (UI multiplies for display).

**Event aggregation schema** (per substep, appended once at substep end):
- `{"t":"hits", "n":int, "sum":float, "crit_n":int, "by_kind":{weapon_kind:{n,sum}}, "top":[{eid,pos,amt,crit}] (≤8 largest)}`
- `{"t":"kills", "n":int, "entries":int, "cash":float, "by_kind":{kind:{n, entries}}, "pos_sample":[≤16 Vector2]}`
- `{"t":"core_hits", "n":int, "dmg":float, "pos_sample":[…]}`, `{"t":"shield_hits", "n", "breaks", "pos_sample"}`
- At **m=1 the per-event stream stays exactly as today** (aggregator off). That keeps selftest's event assertions and bit-identity. With m>1 it switches to aggregated mode. Missions/Stats/Achievements accept both forms (`n` defaults to 1). Boss/elite/marked/courier events are never aggregated.

**Rendering**: one `MultiMeshInstance2D` per kind (9) with a quad mesh + the SVG texture. Per-instance colour does the hit flash/slow tint. The instance buffer is filled from SoA each frame (`RenderingServer.multimesh_set_buffer` with one PackedFloat32Array, 12 floats per instance for 2D transform+colour). HP bars only for elite/boss/marked (immediate).

### Phase 3 — Separation + contact rule
In the single hot pass: seek CENTER with accel + max speed, and soft separation from hash neighbours (radius = (size_i+size_j)/2, push ∝ overlap, capped). A body attacks only if `|pos−C| ≤ STOP_R + size/2 + ε`, i.e. it is in the front rank. Ranged keep their stop ring. The wall is applied as a speed cap. Deterministic: neighbour order = order-rank, Jacobi update (read old pos, write new).

### Phase 4 — Knockback
`vel += J/mass` with `mass ∝ size²` (boss/courier immune as today's pulse rule), friction `vel *= exp(-k dt)`. Single-target impulse ∝ dmg/max_hp × weapon factor; `radial_impulse` with linear falloff for mortar/orbital/pulse. The existing Pulse knock (1757-1764, 12 px teleport) is replaced. At m=1 the knockback is **off by default** (bit-identity) or behind `horde_mult>1`. See C7.

### Phase 5 — Gore
View only: pooled GPUParticles2D (blood), a corpse/blood stamp into a never-cleared SubViewport ground layer (ring buffer of stamp commands per frame, capped). Setting `gore` off/low/full in settings.cfg (`Settings.gd`).

### Phase 6 — Feedback polish + debug overlay
Overlay shows bodies, FPS, sim ms, hash ms, hash cells. Juice calls go through aggregated records with caps.

### Phase 7 — Performance
The hot loop stays one pass. Decision point for C#/compute (ask first).

## 5. Determinism strategy (bit-identical at horde_mult = 1)
1. f64 packed storage for every float field (no f32 rounding).
2. `order` array = spawn order with `_reap`-identical compaction. All loops iterate it.
3. Hash queries return candidates ranked by `order`. Comparisons copy today's operators (`<=` in `_nearest`/`_hit_carry`, `<` + d² tie in `pick_target`, `>`/`<` in `_densest`). Distance maths uses identical expressions (`distance_to` vs `distance_squared_to` exactly as now, e.g. mortar uses `distance_to(tpos) <= rad`).
4. No new RNG draws on any stream at m=1. horde spread is a deterministic function of (entry, body index).
5. Per-hit events emitted in the same order at m=1 (aggregator off).
6. Gate: diff of the full `PLAYTEST METRICS` JSON plus a new selftest golden. The golden runs a 120-s seeded sim at m=1 and hashes (wave, kills, cash, hp, every enemy pos/hp); this hash is recorded **now from the Dict implementation** in Phase 1's first commit.

## 6. PC enemy-count target
See HORDE_BASELINE §3/§4 for the numbers.

**Target: 2,000 live bodies at 60 fps at game speed 1 with the full feature set (separation + knockback + gore "low"). Stretch: 3,000 with gore off. 5k–10k only with a C#/compute hot loop (Phase 7 decision, ask first).**

Reasoning:
- **Demand.** Today's peak is ~70 entries alive (HORDE_BASELINE §2). At horde_mult 16 that is ~1,100 bodies, and at 32 it is ~2,200. Bodies live longer under separation/front-rank-only contact, so expect ~1.5× on top. 2k covers m=16 with headroom, which is the "Orc Problem" feel at the late waves. m=8 (~550) covers early/mid.
- **Sim budget.** Of the 16.6 ms frame, budget ≤6 ms for the sim (1 substep at speed 1, up to 2 when frames drop). The measured Dict move costs 2.2 µs per body. Packed-array SoA in GDScript typically gives 3–5× over Dict get/set, so ~0.5–0.7 µs per body for seek. Separation adds ~6–10 hash-neighbour checks at ~0.1 µs each, so ~1.5–2 µs per body for the single hot pass. Hash rebuild is ~0.2 µs per body; targeting and AoE on the hash are O(k), not O(n). That gives ~2.5 µs per body: 2k ≈ 5 ms, 3k ≈ 7.5 ms, 5k ≈ 12.5 ms (too slow with view work), 10k ≈ 25 ms (impossible). Speed ×3 at 5k is clearly out of reach in GDScript.
- **Draw budget.** Immediate mode costs 7.6 µs per body (38 ms at 5k), which is why it gets rewritten. A MultiMesh fill at ≤0.5 µs per body gives 2k ≈ 1 ms CPU. GPU cost for 2–5k textured quads is trivial on an RTX 5080.
- **Events.** Per-hit events scale with bodies (305 per substep at 5k, 2.7 ms in Achievements/Missions alone). Aggregation makes this O(1).
- Phase 1 must verify the SoA speed-up claim with `tools/horde/profile.gd`. If the hot pass exceeds 3 µs per body, the target drops to ~1.5k and the C# question comes earlier.

## 7. Expected AoE vs single-target value shift (per weapon / Core) at horde_mult 2/4/8/16
Model: a wave keeps total HP H and count N·m. Single-target weapons lose overkill efficiency only through per-shot granularity. AoE weapons hit k bodies in radius r, and density per area rises ×m (no separation) or is capped by separation packing (Phase 3+).

| Weapon / Core | Mechanic | m=2 | m=4 | m=8 | m=16 | Note |
|---|---|---|---|---|---|---|
| Gun (single + carry) | 1 target, carry 0.6×2 hops | ≈1.0× | 0.95× | 0.9× | 0.85× | Overkill per shot grows as body HP drops below shot dmg; the carry recovers 60%. Shot cadence becomes the limit (kills/s ≤ rate·3). |
| Flak (prey ×2.5) | single, no carry | 0.9× | 0.7× | 0.5× | 0.3× | **Loses badly**: 1 body per shot, no carry. Kill rate is capped at the fire rate once body HP < dmg. |
| Railgun (line pierce) | all on line | ~1.6× | ~2.5× | ~4× | ~6× | Bodies on the line scale with density (sublinear after Phase 3). |
| Mortar (splash r) | all in radius | ~1.8× | ~3× | ~5× | ~8× | ∝ density, capped by packing. |
| Tesla (chains n, 0.7 falloff, 90 px) | n targets fixed | 0.95× | 0.85× | 0.7× | 0.5× | The fixed chain count means less HP per zap; the chains more often find a target. |
| Frost (aura dmg + slow) | all in range | ~2× | ~4× | ~8× | ~16× (dmg) | Damage scales linearly with bodies (dmg is per body, HP per body ÷ m). **Strongest gainer**: risk of becoming dominant. |
| Core Cannon (barrels + splash 0.4) | single+splash | ~1.3× | ~1.8× | ~2.5× | ~3.5× | Splash share dominates. |
| Core Slag (splash + slow) | AoE | ~1.8× | ~3× | ~5× | ~8× | Like Mortar. |
| Core Lance beam (strongest, ramp) | single, ramp resets on retarget | 0.7× | 0.5× | 0.35× | 0.25× | **Loses most**: bodies die fast, so the ramp keeps resetting (`beam_t = -retarget`). Boss value unchanged. |
| Core Pulse (all in Core range) | all in range | ~2× | ~4× | ~8× | ~16× | Linear, like Frost. Chain_every adds fixed 3 targets. |
| Orbital Strike | AoE | ~m× | | | | ∝ density. |
| Troops (Rifleman single, Sapper AoE ×2 vs armored) | mixed | rifle 0.9→0.5×, sapper ~m× | | | | Contact damage on troops = Σ dmg/m over bodies in contact. It rises with density, so troops die faster. |
| Elite shields | whole-hit absorb | see C5 | | | | |

The numbers are first-order estimates (uniform density, no separation). Phase 2 replaces them with measured playtest deltas per weapon policy at each m.

## 8. Risks
- **R1 GDScript throughput**: see HORDE_BASELINE. The hot loop has to beat ~0.3 µs/body/op. GDScript packed-array loops run ~30–60 M simple ops/s. At 5k bodies × (seek + ~8 neighbour checks) ≈ 50k–80k pair checks per substep; at 3 substeps/frame (speed ×3) that is ~240k/frame ≈ 6–10 ms. Feasible at 1k-3k, marginal at 5k, and not at 10k with game speed ×3. This is the C#/compute decision point.
- **R2 Determinism drift** from hash query order or float re-association. Mitigated by §5 and the golden hash.
- **R3 Armor floor non-linearity**: `_core_damage` subtracts flat armor per hit (`max(0.25·amt, amt − armor)`). Splitting a hit into m pieces of amt/m makes armor m× more effective until the 25% floor. **Contact damage conservation breaks** wherever armor > 0 (C4).
- **R4 Whole-hit shields** (C5), **ironclad**, shred stacks and crit per shot are all per-hit mechanics. They change value non-linearly with m.
- **R5 Overkill/cadence ceiling**: single-target weapons can't kill m× more bodies. Policies built on gun/flak/lance lose waves at high m, so playtest gates may fail at m ≥ 4.
- **R6 Event volume**: today ~events per substep scale with hits. Measured 220→5000 bodies under the full board in HORDE_BASELINE. Missions/Achievements run per event (Achievements' `meta` check is O(events)). Aggregation is mandatory before m>1 ships.
- **R7 Contact rule (Phase 3)** cuts Core damage drastically (only the front rank attacks). Total contact DPS will be far lower than today's "everyone at STOP_R attacks", which shifts balance even at m=1 (C6).
- **R8 Test coupling**: 81 selftest references construct/mutate Dict enemies. Migration risk of silently weakened assertions.
- **R9 Draw**: llvmpipe numbers in HORDE_BASELINE are CPU-side only. MultiMesh moves cost to the GPU; real-GPU verification is needed on the owner's PC.

## 9. CONFLICTS (flagged, not resolved)
- **C1 MAX_ENEMIES = 220 cap** (TowerState.gd:48) and selftest "T5 w60 10 s flood: enemy count capped" (selftest.gd:1058, asserts `peak <= MAX_ENEMIES`). The brief wants thousands of bodies. Raising the cap at m=1 changes behaviour, because refused spawns at the cap are currently *lost* (not bit-identical if raised). Proposal: cap = 220·m bodies; needs owner sign-off.
- **C2 "Each body gets 1/horde_mult of … xp, coin"** vs **kill counts must match**. Missions/Stats/achievements count kill *events* today. With m bodies per enemy, either kill counts rise ×m (Stats lifetime kills, ACH 100000 kills, kill missions get m× easier) or kills count per original entry (proposed). The brief's "Mission, stat and achievement kill counts must still match" is read as per-entry. Confirm.
- **C3 Drops roll per kill on `drop_rng`**: the key roll (p 0.0005, Drops.gd:61) runs on **every** non-courier kill. Per body that would give ×m keys and also shift the drop_rng sequence (marks/couriers/parts change). The brief lists cash/xp/coin/contact only. Proposal: roll drops once per entry.
- **C4 Contact damage conservation vs flat armor**: `_core_damage` applies flat `armor` + a 25% floor per hit. 1/m bodies are mitigated far more, so per-wave core damage is **not** conserved even with dmg/m. The same applies to `reflect` (Mirror) and Ironclad (per hit). Needs a rule (e.g. aggregate contact hits per substep before armor, or scale armor by 1/m per body).
- **C5 Elite shields absorb whole hits** (3 + w/10). Splitting an elite into m bodies with the same shield multiplies total shield hits ×m (much stronger), and 1/m of a shield is fractional. The brief says nothing about shields. Proposal options: shields stay per entry on one "lead" body, or ceil(shield/m) per body. Owner choice.
- **C6 "Only enemies actually touching STOP_R attack the core"** changes today's rule (every arrived body attacks, 1 hit/s). Even at m=1 with separation, fewer enemies attack, so the Core takes less damage and the playtest numbers change. That conflicts with "at horde_mult=1 … bit-identical" for Phases 3+. Proposal: the bit-identity gate applies to Phases 1–2. Phases 3–4 report deltas (or separation/contact rule only active when m>1). Decide.
- **C7 Knockback at m=1**: the brief wants knockback (Phase 4) and m=1 bit-identity. The current Pulse knock (12 px teleport, TowerState.gd:1757-1764) is the only knockback. The same decision as C6.
- **C8 Substeps are not fixed**: `tick` uses `n = ceil(d/0.05)` with `sub = d/n`, so a frame of 0.06 s gives 2 × 0.03 s. The brief says "fixed-substep". Making them truly fixed (accumulator) changes results for any delta that isn't a multiple of 0.05 (Main at 60 fps: 0.0167 → 1 substep of 0.0167 today). Playtest uses DT 0.1 → 2×0.05 either way (identical), but uitest/Main would differ. Flag; keep the current scheme unless the owner wants the change.
- **C9 Naming collision**: `count_mult` already exists with the `swarm` modifier (×1.6) and the `m_horde` endless mutation ("Horde: enemy count +20%", ModifierDB.gd:30). These raise *entry* counts (more total HP/rewards), unlike `horde_mult` (conserved). UI/docs need distinct naming. `m_horde` is not the horde mode.
- **C10 Splitter/mite conservation**: the brief says "bosses stay single bodies" but is silent on mites (spawned on death, not by the plan) and couriers/marked elites (single loot carriers with eid-specific events). Proposed: courier + marked stay single; mites inherit 1/m. Confirm.
- **C11 "Each body gets 1/horde_mult of HP"** vs tier/boss/mark HP multipliers: these apply before the division (fine), but `PowerModel`/playtest `R` probes measure HP per wave via eid ordering (playtest.gd:855-866). Unchanged totals, but the probe code itself reads Dicts (test change needed).
- **C12 "No nodes"** vs view: MultiMesh/GPUParticles/SubViewport are nodes, but the brief puts them in the view, so this is consistent. Noted only.
- **C13 "Port _densest (currently O(n²))"**: confirmed O(n²). Orbital auto-aim tie semantics (focused lane +1) must be reproduced by the hash density for m=1 bit-identity. Cell-count density is not the same function as the exact neighbour count, so an exact port (hash-accelerated exact count) is planned, not a cell histogram.
