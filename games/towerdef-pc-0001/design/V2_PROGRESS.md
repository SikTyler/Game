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

## Test ledger
Every deleted, rewritten or added check, with its reason. A surviving check is never silently loosened.

| Phase | Change | Checks | Reason |
|---|---|---|---|

## Golden fingerprint history (HORDE_FP_GOLDEN)
| Phase | Hash | Why it changed |
|---|---|---|
| baseline | c21bb5667802945c564e73d073a63130ec2008225f1aed81091afc00bfb969a4 | — |

## Deviations from V2_DESIGN
(none yet)
