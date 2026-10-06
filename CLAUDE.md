# Corehold — project notes for Claude

The repo root is the Godot project (Godot **4.6.3 .NET**, C# + GDScript). `README.md` has the layout; `design/V2_DESIGN.md` the systems and numbers; `design/V2_PROGRESS.md` the change log, test ledger and golden-hash history.

## Toolchain
- `bash tools/setup_godot.sh` installs headless Godot 4.6.3 mono + .NET 8 under `~` (idempotent); `--print` echoes the binary path.
- `export DOTNET_ROOT=~/.dotnet PATH=~/.dotnet:$PATH` before running Godot headless.
- Gate: `TEST_OUT=<dir> bash tools/test_all.sh` → import, C# build, `tools/parse_all.gd`, `selftest.gd`, `uitest.gd`, `horde_fp.gd` ×2 (same hash), `smoke.gd`; ends with `ALL GATES OK`. Don't edit scripts it loads while it runs.
- Screenshots: `xvfb-run -a -s "-screen 0 1920x1080x24" $G --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script res://_shots.gd -- <outdir>`.
- Balance: `playtest.gd -- workers=4` (~2.5 h, not in the gate); `-- only=<job> [dir=<snapshots>]` runs one job. Tune overrides via `GF_TUNE='{"key":value}'` (`Tune.gd`).

## Conventions
- `TowerState.gd` owns run rules; `Main.gd` / `ui/*` are views and never mutate rules state directly.
- Determinism: the run is seeded; `selftest.gd` pins `HORDE_FP_GOLDEN`. A deliberate sim change re-records it with a dated rationale comment and a row in V2_PROGRESS's golden history.
- New checks go in `tests/st_<module>.gd` (`static func run(t)`), called from `selftest._initialize`. Changed or deleted checks get a test-ledger row in V2_PROGRESS.
- UI text ≥ 14 px and WCAG ≥ 4.5:1 (uitest audits it); every button has a tooltip.
- Scratch scripts start with `_dbg` and stay untracked.
