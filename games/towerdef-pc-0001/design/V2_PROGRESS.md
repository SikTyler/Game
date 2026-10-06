# Corehold V2 — progress log, gates and test ledger

Design: `V2_VISION.md` (why, competitor analysis), `V2_DESIGN.md` (schemas, numbers, phases).
Branch: `claude/hopeful-johnson-5n1y7a`, fast-forwarded from `towerdef-0001` @ 93ab95f.

## Toolchain
`bash tools/setup_godot.sh` installs Godot 4.6.3 **mono** (GitHub release) and the .NET 8 SDK. The Microsoft CDN is blocked by the egress policy here, so the SDK comes from the Ubuntu archive (`dotnet-sdk-8.0`). Then run `G=$(bash tools/setup_godot.sh --print) bash tools/test_all.sh`.

## Gates (every phase boundary)
`tools/test_all.sh` runs, in order:
1. import
2. C# build (fails on `error CS`)
3. `tools/parse_all.gd` (every script loads)
4. `selftest.gd` → `SELFTEST OK`
5. `uitest.gd` → `UITEST OK`
6. `horde_fp.gd` twice (same hash)
7. `smoke.gd` → `SMOKE OK`

The full `playtest.gd` (~35 min, 52 gates) is the P9 gate only. 7 mass balance gates were already failing at the V2 start (MASS_HORDE.md §Content).

## Baseline (P0, towerdef-0001 @ 93ab95f)
- selftest: OK (758 checks, ~29 s). uitest: OK (210 PASS lines, ~8 s). smoke: OK (~18 s; fresh run reaches w18, mini-campaign waves [18, 11, 24, 13]).
- HORDE_FP_GOLDEN `c21bb566…` (4 Cores: bastion 597311ff…, foundry bfc1ccf9…, lance 42787757…, tempest 40ee68ff…).
- Playtest `only=main` balanced campaign: day 1 best w30 (T2), gross 10.1k coins; day 2 gross 250k; day 3 gross 637k, Core L17. Mills give ~13–19k coins/h. These anchor the P8 research costs.

## Phase log
| Phase | Status | Notes |
|---|---|---|
| P0 setup / baseline / docs / smoke | done | tools/setup_godot.sh, tools/test_all.sh, tools/parse_all.gd, smoke.gd, V2 docs |
| P1 strip + hard reset | done | Removed Factory, Crates, Cards, Parts/Sets, Core Bay, 4 Cores→1, Keys, Core Cores, air (Drone Nest, flyer-only Flak), plaza; restored the pre-Factory Outpost (OutpostView from 5b10ce8, no Key Forge); save v5 hard reset (+ one-time banner); interim Core tab; Scrap-only drops. selftest 580 checks, uitest 166 PASS, smoke OK. |
| P2 neon casino UI foundation | done | Fonts (Inter body + Chakra Petch headings/numbers, OFL, `fonts/`), `ui/Fonts.gd`, `ui/NeonTheme.gd` (Godot Theme on the widget layer + tooltips), Kit V2 palette by token (navy #070a12→#0d1220, cyan #39e6ff, magenta #ff3ea5, gold #ffd34d, 7 gear rarities incl. prismatic Exotic), glowing buttons/panels, widgets `panel_glow` / `card_frame` / `tabs` / `big_number` / `req_chip` / `bar_glow` / `rarity_beam` / `glow` / `bg`, `vfx/Roll.gd` (counter roll-up + pop: top-bar currencies, results total), `vfx/Beam.gd` (loot beam + card shimmer), `Juice.shake(mag)`, `Sfx.play(clip, pitch)` + `seq_pitch`. Nav OUTPOST / CORE / FORGE (locked, SOON) / RESEARCH / REFORGE + magenta PLAY; Missions moved to the top bar. All screens restyled by token; no text below 14 px. |
| P3a squeeze instead of attack | done | HordeWorld: bodies never attack structures. Pressing a face whose cheapest route runs through it starts a squeeze (per-body `sqz`, no push-out, own motion x`horde_squeeze` 0.35 while overlapping a structure; ends once clear and the route no longer runs through one). Sappers ignore structures and detonate on the Core (`horde_sapper_core` x6, reaped, no kill); Spitters always spit at the Core. Deleted: `ACT_BLD`, `bldHits/bldDmg`, `LastBuildingDamage`, `bld_hp`, `bld_lost`, `_sync_bld_hp`, `_repair_buildings`, `_destroy_building`, `_spit_target`, `bld_max`, the `bld_hit(s)` / `building_destroyed` / `bld_repair` events, EnemyDB `bld`. Barricade is now the **Wall** (same id; slow aura kept); Wall of Flesh counts distinct bodies one Wall slows in a wave. Golden unchanged (the fingerprint board is never sealed and is classic: no Spitter siege). |
| P3b finer board | done | `CELL` 52 → 26, `SIDE` 11 → 21 (N 441), Core 3x3 on `CORE_SLOT` 220, `STOP_R` 44, `GRID_SIZES` 7..21 (Grid research 7 steps at the V2 steep costs 2k … 8M, explicit `costs` in LabDB). Footprints: `slots[anchor]` + `occ` (cell → anchor), `footprint` / `anchor_at` / `owner_at` / `fp_pos` / `ring_at` / `adjacent` / `fp_dist`; Mortar and Railgun 2x2 (`PickDB.size_of`). Adjacency = touching footprints (Armory, Oil Mill), Beacon reach 4 small cells (the old 2), ring range bonus per 52 px, Railgun needs its whole footprint on ring 3+. `build_cap` 40 (`pc_build_cap`). HordeWorld: flow cells and margin derived from the cell size (13 px / 676 px kept), building scans reach ⌈(r+0.5)/cell⌉, sticky face-slide side (small squares made bodies dither on a face's middle). View: footprint sprites and ghost, valid-cell glow from real footprints, 3x3 Core plate, cursor steps off footprints, click/drag pick the covering building. |
| P3d drop the classic ruleset | done | The designed mass horde is the only ruleset: `mass` and the legacy split knob (`horde_mult`, `Tune.horde_mult`, `_spawn_clones`, the per-body horde loot pool) are deleted with the classic plan (`_roll_kind`), spawn, reap, contact-armor share and building verbs; aggregation always on. `horde_fp` runs mass sims on two boards (open; Wall-sealed Core for beam / pulse). Perf: C# pair pass parallel (bit-identical: each body sums its own accumulator in a fixed order), mirror pull split hot (pos / vel / slows) vs on-demand cold, Wall auras one C# call per Wall. `horde_prof`: 10k bodies + 40 buildings **6.81 ms** per tick (gate ≤ 8 ms; P3a classic board was 6.78 ms with 9 buildings). selftest now ~70 s (mass waves everywhere). Done before P3c (deviation below). |

## Test ledger
Every deleted, rewritten or added check, with its reason. A surviving check is never silently loosened.

| Phase | Change | Checks | Reason |
|---|---|---|---|
| P1 | deleted `_factory_stages`, `_crate_stages`, `_parts_data/rule/engine_stages`, `_save_v4_stages`, Stage 17 (cards), PC-E1 meta-ring / land / perm-cap checks, PC-E2 perm-base cap, PC-E4 base move, perm railgun, Core Overdrive / core-cap checks, Core traits (Steadfast / Compound / Focus), flyer-only Flak, drone troops | −178 | systems removed by the owner brief (V2_VISION) |
| P1 | rewrote Stage 12 (save migration → v5 hard reset), Stage 9 (perm base → Core level carry), PC-E9 (v2 migration → reset + legacy import as fresh v5), `_core_stages` (4 Cores → 1 + attack-sheet fixtures), Reforge AC-21 (no parts / Lance / Core Cores), drops (Scrap only), achievements (39 → 33), cards in-run → wind_hp / skip_chance mechanics | rewritten | V2 design: one Core, no crates/cards/keys, hard reset |
| P1 | literals: Steadfast ×1.02 removed, rerolls (no card reroll), LabDB 12 → 10, huts 3 → 2, Insight 7 → 6, snapshot troops 4 → 3, day-7 streak chest → +60 Scrap | adjusted | follow-on of the removals |
| P1 | uitest: Core Bay / Crates / Factory / Cards sections → Core tab, restored pre-Factory `_outpost` (5b10ce8), V2 home + research/missions; loot feed newest row = bounty; Core tooltip = level + attack | 210 → 166 PASS | removed screens |
| P2 | added `tests/st_kit.gd` (selftest): palette contrast (every text token on every surface ≥ WCAG 4.5; rarities readable on cards), roll-up curve (monotonic, exact landing, ease-out, pop once, deterministic, snap/retarget), `Juice.shake_amount` scaling, `Sfx.seq_pitch` ladder | +17 | P2 foundation (pure parts) |
| P2 | uitest: per-screen text-size audit in `_audit` (drawn text and button labels ≥ 14 px, every audited screen), draw pass live headless, fonts bundled (Inter / Chakra Petch), Theme on `ui` + tooltips, button font + hover glow, nav (Forge locked, Missions in the top bar) | +22 PASS | P2 layout audit (V2_DESIGN P2) |
| P2 | 17 draw calls below 14 px raised to 14 (Intel enemy table rows 30 → 34 px, flow header 10 → 14 px; Draft card tags; Outpost palette; Reforge costs; enhancement descriptions; tier readout) | adjusted | P2 audit findings |
| P3a | deleted FB1 "barricade HP 200 / others 40", "stops at a sealing building and attacks it", "a building at 0 HP is destroyed", "the attacker moves on after the fall", "wave start repairs 50%", "destroying the upgrade's last target cancels it", MASS "sealed Core: aggregated bld_hit rows" + "the wall falls -> surge" | −8 | owner brief: no building HP |
| P3a | added: no HP / destroy path exists; open-ground building flowed around with zero squeezes; sealed ring crossed at ≤ 0.4x speed (free speed > 0.8x), reaches the Core, no structure event; its hits then land on the Core; sealed mass crowd (600 mites) reaches the Core but fewer than on open ground, squeezes > 0, no structure event | +5 | V2_DESIGN P3a gates |
| P3a | rewrote MASS Sapper: was "one blast on the wall (x12.5)", now "passes the Wall, detonates on the Core for x6 its hit, gone, not a kill" | rewritten | Sappers hit only the Core |
| P3b | selftest coordinate helpers: `_r` / `_rc` keep the legacy ring (offset d → d + sign(d)); new raw `_at(dr, dc)` = `TowerState.cell` | helper | 3x3 Core on a 21x21 board |
| P3b | rewrote: setup rings 1-2 open / 40 free cells (was ring 1 / 8); armory buffs a touching gun and links the Core; oil mill on a touching cell, never the Core; beacon reach 4 cells / not 5 away (was 2 / 3); grid research 7..21 at 2k..8M (was 3..10 at 60·3^L); PC-E1 rings 1-2 + GxG−9 cells for all 8 sizes, centred odd grids (was even-grid rows), override 9 / 21; railgun ring 3+ 2x2; ring range bonus per 52 px; locked/outside probes moved to ring 3+; flow wall laid as 15 raw cells (legacy mapping left gaps); sealed rings use the 16 `CORE_RING` cells | rewritten | finer board (V2_DESIGN P3b) |
| P3b | added: a 2x2 Mortar cannot cover a Core cell; a Railgun with any footprint cell on ring 2 is refused | +2 | footprints |
| P3b | uitest: dragged 2x2 Mortar snaps its footprint to the nearest grid corner (dropped on a cell corner, clear of the first gun); pad stick steps off the 3x3 Core in one push (CORE_SLOT + 2) | rewritten | footprints, 3x3 Core |
| P3d | deleted: MASS H3 "legacy split knob ships off", FB1/FB2 horde loot (3: drops cap, low-value drops, pool sweep), FB2 horde bodies scaled back, HORDE m=4 conservation + budget, T1 / T3 classic kind rolls | −9 | classic ruleset + legacy knob removed (V2_DESIGN P3d) |
| P3d | rewrote for the mass rules: kills summary (not per-kill events); B1 tier HP rides on the body count; Spitter shots counted from `core_hits`; Broodsac bursts into 6; Cryo slows 50% + chills 10%; damage ramp as a 41/1 ratio; strongest mode = first Gatling round + hits summary; flood capped at the mass cap; no-lanes over waves 1-12 on / just behind the ring; Flamer crit (cone lick x0.15); Haste / Swarm / mutation / Gambit as ratios to an unmodified spawn; Riflemen post (anchor = the Core); Courier and marked HP from the mass sheet; snapshot DPS x `MASS_CROWD`; contact rule = front rank + press band; spawn ring beyond the view ring; Elite Guard x3 plan elites | rewritten (21) | mass horde only |
| P3d | added: the body budget is the mass alive cap | +1 | |

## Golden fingerprint history (HORDE_FP_GOLDEN)
| Phase | Hash | Why it changed |
|---|---|---|
| baseline | c21bb5667802945c564e73d073a63130ec2008225f1aed81091afc00bfb969a4 | — |
| P1 | c9854a03c5355c55d7b0dc24437d3236f30838aa68a47f07bdb7df036172c22e | one Core (+ slag/beam/pulse sheet fixtures), no Drone Nest on the board, no Steadfast / legacy Core stats |
| P3a | c9854a03… (unchanged) | the fingerprint board is never sealed and runs the classic ruleset (no Spitter siege) |
| P3b | e5a407bd2e4e65145a86d0f657e533e6e75612e396a0eaf5aee02e04839a0402 | 21x21 board of 26 px cells, 3x3 Core (STOP_R 44), 2x2 Mortar / Railgun, flow resolution derived from the cell, sticky face slides; board re-laid in `BOARD_RC` |
| P3d | ebffce97b4c320ac7be5b7a64cc76b2a0d8aedd084e5c54cf270db8a9b81e214 | mass waves only (wave 14 mass plan + a fragile 150-body flood), beam / pulse on a Wall-sealed board (squeeze path) |

## Deviations from V2_DESIGN
- P1: the playtest bot was slimmed (spec / set / forge-loop jobs and RD gates removed with parts, crates, cards and the Factory); its Outpost plan is the pre-Factory OP_PLAN minus the Key Forge. The full rewrite stays in P9.
- P1: the Reforge Outpost nodes (`builder2`, `bp_*`, `retain`) are live again with the restored Outpost; `crate_luck` is removed.
- P2: the theme builder is `ui/NeonTheme.gd`, not `ui/Theme.gd` (`Theme` is a Godot class name); fonts live in `ui/Fonts.gd` so Kit and the theme share them without a preload cycle.
- P2: contrast is asserted in selftest (`st_kit`, pure) rather than uitest; uitest owns the drawn-text size audit.
- P2: hub toasts moved to bottom-centre (they covered the Outpost BUILD header); run toasts sit at the top of the field, clear of the hotbar.
- P3a: the squeeze state is a per-body C# byte array (`sqz`, reset on `Put`), not a GDScript-visible `F_SQUEEZE` flag bit: GDScript re-commits flags and would clobber it.
- P3a: the Wall keeps the id `barricade` (name and description changed) to keep data, art and test churn down; the P3b board rewrite can rename it if needed.
- P3a: Wall of Flesh counts distinct bodies slowed by one Wall in a wave (the achievement text), not bodies squeezed past it.
- P3b: `TowerState.cell(dr, dc)` is a raw offset from the Core's centre cell (±2 touches the Core); the ring-preserving legacy mapping lives only in the selftest helpers.
- P3b: the Grid research costs (2k … 8M) landed now with the 8 grid sizes rather than in P8; `Labs.cost` gained explicit per-step `costs`.
- P3b: huts and every support building stay 1x1; only the Mortar and Railgun are 2x2 for now (P7 content assigns footprints to the new buildings).
- P3d ran before P3c (the plan lists c then d): the directional targeting and `FirePatterns` are built once, on the only (mass) firing path, instead of being added to the classic branch and then deleted.
- P3d: `horde_prof` gained the 10k-body / 40-building gate run; the gate is met with a parallel C# pair pass and a hot / cold mirror pull rather than by cutting features.
