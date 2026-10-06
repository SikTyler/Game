# Corehold

A mass-horde tower defense × roguelite × idle base-builder for PC, built in Godot. Defend the Core against waves of hundreds to tens of thousands of bodies, draft weapons and perks as you level, build your Weapon and Core from procedurally drawn parts (barrels, ammo, scopes, platings, generators …), and grow your Outpost between runs.

## Play it

1. Install **Godot 4.6.3 — .NET edition** ([download](https://godotengine.org/download/archive/4.6.3-stable/), pick the ".NET" build). The crowd simulation is C#, so the standard build will not run it.
2. Install the **.NET 8 SDK** ([download](https://dotnet.microsoft.com/download/dotnet/8.0)).
3. Download this repo (Code → Download ZIP, or `git clone`).
4. Open Godot → **Import** → select `project.godot` in the repo folder → **Import & Edit**.
5. Press **F5** (or the ▶ button). The first open takes a minute while Godot imports assets and builds the C# project.

Controls are in [`design/CONTROLS.md`](design/CONTROLS.md) and rebindable in Settings → Controls.

Saves live in `%APPDATA%\Corehold-PC` on Windows (`~/.local/share/Corehold-PC` on Linux).

## Build an executable

In the editor: Project → Export → "Windows Desktop" or "Linux" (install the 4.6.3 .NET export templates when prompted). Output goes to `build/`. The `.github/workflows/export.yml` workflow does the same in CI (run it by hand from the Actions tab).

## Layout

| Path | What's there |
|---|---|
| `project.godot`, `Main.tscn`, `Main.gd` | Project entry: the one scene and its controller (input, screens, juice). |
| `TowerState.gd` | The run simulation (waves, weapons, drafts, economy) — the game's rules live here, the view never mutates them. |
| `HordeWorld.cs`, `EnemyStore.gd`, `EnemyHash.gd` | The C# crowd sim (flow field, squeeze, contact) and its GDScript mirror / spatial hash. |
| `BaseMeta.gd`, `Outpost.gd`, `Labs.gd`, `Parts.gd`, `PartVis.gd`, `Loot.gd`, `Cores.gd`, `Reforge.gd`, … | Meta systems: save, Outpost, research, Weapon / Core parts (design/V3_PARTS.md) and their art, loot, Core levels, prestige. |
| `data/` | Content tables (weapons, buildings, perks, research, parts and perk affixes, loot, enemies …). |
| `ui/`, `vfx/` | Code-drawn screens and widgets (`ui/Kit.gd` is the neon UI kit) and effects. |
| `art/`, `audio/`, `fonts/` | SVG art, WAV effects / music (`audio/recipes.json` = how they were made), bundled fonts. |
| `tests/`, `selftest.gd`, `uitest.gd`, `smoke.gd`, `horde_fp.gd`, `playtest.gd` | Test suites, determinism fingerprint, and the balance playtest bot. |
| `tools/` | `test_all.sh` (the full gate), `setup_godot.sh` (headless Godot + .NET install), `parse_all.gd`. |
| `design/` | Design docs: `V2_VISION.md` (pillars), `V2_DESIGN.md` (systems + numbers), `V2_PROGRESS.md` (change log, gates, test ledger), `MASS_HORDE.md`, `CONTROLS.md`. Older docs are history. |
| `steam/` | SteamPipe depot configs (manual upload). |
| `third_party/` | Credits and license texts for everything borrowed. |

## Tests

```
bash tools/test_all.sh          # import → C# build → parse → selftest → uitest → fingerprint ×2 → smoke
```

`tools/setup_godot.sh` installs a headless Godot 4.6.3 .NET + .NET 8 if `G` (path to the Godot binary) isn't set. The full balance playtest (`godot --headless --path . --script res://playtest.gd -- workers=4`) takes ~2.5 h and is not part of the gate.

## License

MIT — see `LICENSE`. Third-party credits in `third_party/`.
