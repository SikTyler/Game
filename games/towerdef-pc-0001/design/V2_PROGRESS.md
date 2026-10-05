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

## Test ledger
Every deleted, rewritten or added check, with its reason. A surviving check is never silently loosened.

| Phase | Change | Checks | Reason |
|---|---|---|---|
| P1 | deleted `_factory_stages`, `_crate_stages`, `_parts_data/rule/engine_stages`, `_save_v4_stages`, Stage 17 (cards), PC-E1 meta-ring / land / perm-cap checks, PC-E2 perm-base cap, PC-E4 base move, perm railgun, Core Overdrive / core-cap checks, Core traits (Steadfast / Compound / Focus), flyer-only Flak, drone troops | −178 | systems removed by the owner brief (V2_VISION) |
| P1 | rewrote Stage 12 (save migration → v5 hard reset), Stage 9 (perm base → Core level carry), PC-E9 (v2 migration → reset + legacy import as fresh v5), `_core_stages` (4 Cores → 1 + attack-sheet fixtures), Reforge AC-21 (no parts / Lance / Core Cores), drops (Scrap only), achievements (39 → 33), cards in-run → wind_hp / skip_chance mechanics | rewritten | V2 design: one Core, no crates/cards/keys, hard reset |
| P1 | literals: Steadfast ×1.02 removed, rerolls (no card reroll), LabDB 12 → 10, huts 3 → 2, Insight 7 → 6, snapshot troops 4 → 3, day-7 streak chest → +60 Scrap | adjusted | follow-on of the removals |
| P1 | uitest: Core Bay / Crates / Factory / Cards sections → Core tab, restored pre-Factory `_outpost` (5b10ce8), V2 home + research/missions; loot feed newest row = bounty; Core tooltip = level + attack | 210 → 166 PASS | removed screens |

## Golden fingerprint history (HORDE_FP_GOLDEN)
| Phase | Hash | Why it changed |
|---|---|---|
| baseline | c21bb5667802945c564e73d073a63130ec2008225f1aed81091afc00bfb969a4 | — |
| P1 | c9854a03c5355c55d7b0dc24437d3236f30838aa68a47f07bdb7df036172c22e | one Core (+ slag/beam/pulse sheet fixtures), no Drone Nest on the board, no Steadfast / legacy Core stats |

## Deviations from V2_DESIGN
- P1: the playtest bot was slimmed (spec / set / forge-loop jobs and RD gates removed with parts, crates, cards and the Factory); its Outpost plan is the pre-Factory OP_PLAN minus the Key Forge. The full rewrite stays in P9.
- P1: the Reforge Outpost nodes (`builder2`, `bp_*`, `retain`) are live again with the restored Outpost; `crate_luck` is removed.
