# Third-party sources

Every external source used by GameForge / Corehold. Licenses were verified by reading the upstream LICENSE file (jsfxr: UNLICENSE file + package.json). Copies live in `licenses/`. Retrieved 2026-10-03 (git clone --depth 1; commit shown).

| Name | URL @ commit | License | Taken / planned | Attribution |
|---|---|---|---|---|
| jsfxr | https://github.com/chr15m/jsfxr @ b7b6aa2 | Unlicense (public domain) | Vendored unmodified: `tools/vendor/jsfxr/{sfxr.js,riffwave.js,UNLICENSE}`, driven by `tools/sfx.mjs` | jsfxr by Chris McCormick et al. (courtesy) |
| ZzFX | https://github.com/KilledByAPixel/ZzFX @ aab7e2b | MIT | Vendored unmodified (ZzFXM's bundled copy): `tools/vendor/zzfxm/zzfx.js` + `LICENSE.ZzFX`, used by `tools/sfx.mjs` | ZzFX (c) 2019 Frank Force |
| ZzFXM | https://github.com/keithclark/ZzFXM @ cb07fa9 | MIT | Vendored unmodified: `tools/vendor/zzfxm/{zzfxm.js,LICENSE}`, used by `tools/music.mjs`; example songs as format reference only | ZzFXM (c) 2020 Keith Clark |
| Quiver tower-defense-godot4 | https://github.com/quiver-dev/tower-defense-godot4 @ 1cbd622 | Code MIT; assets CC-BY 4.0 | Patterns only (health-bar tween, pause, popup, hit-state flash idea for towerdef-0001 `hit_t`); no assets/code copied. Shake (vfx/Juice.gd) is in-house since the repo has none. Repo contains no audio files (LFS holds PNG/OTF only) | Code (c) 2022 Quiver; any asset used: "Art by Quiver, CC-BY 4.0" |
| Godot-4-Tower-Defense-Template | https://github.com/ape1121/Godot-4-Tower-Defense-Template @ cfdbf5e | MIT | Used (2026-10-03): `try_get_closest_target()` pattern adapted into `TowerState.pick_target()` (towerdef-0001); first/strongest/weakest modes written in-house | (c) 2024 Alp |
| Maaack Godot-Game-Template | https://github.com/Maaack/Godot-Game-Template @ 6849d6c | MIT | Patterns adapted (no files copied, no autoloads): options/audio sliders+mute, pause menu, credits list, fade transition -> `games/towerdef-0001/ui/Menus.gd`, `data/CreditsDB.gd`, Main fade | (c) 2022-present Marek Belski |
| game-icons.net | https://github.com/game-icons/icons @ 82d9488 | CC-BY 3.0 (some authors CC0) | Planned: selected SVGs for labs/cards/perks/coins/gems, recoloured | "Icons by <author> from game-icons.net, CC BY 3.0" — per icon, shown in in-game credits |
| anthropics/skills theme-factory | https://github.com/anthropics/skills/tree/main/skills/theme-factory @ 8a1541c | Apache-2.0 | Vendored to `.claude/skills/theme-factory/` (LICENSE.txt + NOTICE); only the SKILL.md description changed | theme-factory (c) Anthropic, Apache-2.0 |
| Idle-math references | Kongregate "The Math of Idle Games" (blog); ellisonleao/magictools (MIT); godotengine/awesome-godot (CC-BY 4.0) | — | Formulas/ideas only, no files copied | — |

**Not obtainable:** kenney.nl (impact-sounds, interface-sounds, particle-pack) returned HTTP 000 (blocked by proxy); not used.
**Rejected:** youtd2 (CC-BY-NC assets); Hollow-Vigil, drift-station, awesome-claude-skills (no license).

## Corehold PC edition (games/towerdef-pc-0001 only)

Retrieved 2026-10-04 (git clone --depth 1; commit shown). These rows are credited in `games/towerdef-pc-0001/data/CreditsDB.gd` only (checked by `tools/credits.test.mjs`).

| Name | URL @ commit | License | Taken / planned | Attribution |
|---|---|---|---|---|
| controller_icons (Xelu prompts) | https://github.com/rsubtil/controller_icons @ 4246544 | CC0 (glyph PNGs, Xelu); addon code MIT | Vendored unmodified PNGs only: `games/towerdef-pc-0001/art/glyphs/{key,mouse,xbox(=xboxseries),ps5,steamdeck}/` (diagram sheets and the Godot-logo plugin icon excluded); no addon code. MIT text: `licenses/rsubtil-controller-icons.LICENSE` + copy next to the glyphs | Xelu's FREE Controllers & Keyboard PROMPTS, Nicolae (Xelu) Berbece, thoseawesomeguys.com/prompts (courtesy) |
| Maaack Godot-Input-Remapping | https://github.com/Maaack/Godot-Input-Remapping @ 8c031bf | MIT | Patterns only (remap list + capture flow) for `Keybinds.gd` / settings Controls tab; no files copied. Godot-Game-Template row above covers `app_settings.gd` patterns ported into `Settings.gd` | (c) Marek Belski |
| godot_input_helper | https://github.com/nathanhoad/godot_input_helper @ ccfad58 | MIT | Patterns ported (no files copied, no autoload): event (de)serialisation, swap-if-taken rebinding, device detection -> `Keybinds.gd` (`licenses/nathanhoad-godot-input-helper.LICENSE`) | (c) 2022-present Nathan Hoad |
| Godot demo projects | https://github.com/godotengine/godot-demo-projects @ 3e08537 | MIT | Patterns: gui/input_mapping, misc/window_management, gui/multiple_resolutions, misc/joypads -> `Settings.gd`, `Keybinds.gd` (`licenses/godot-demo-projects.LICENSE`) | (c) Godot Engine contributors |
| godot-ci | https://github.com/abarichello/godot-ci @ 6b5c4c4 | MIT | Workflow structure adapted into `.github/workflows/towerdef-pc-export.yml` (GODOT_VERSION 4.6.3; Steam upload is a manual step) (`licenses/abarichello-godot-ci.LICENSE`) | (c) Barichello |

**PC — not used:** GodotSteam (license UNVERIFIED: GitHub repo archived, Codeberg blocked) — nothing vendored; `SteamService.gd` is our own dynamic-call wrapper. Kenney Input Prompts (kenney.nl blocked). chickensoft GameDemo (C#, read only).
