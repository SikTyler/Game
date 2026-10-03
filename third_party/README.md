# Third-party sources

Every external source used by GameForge / Corehold. Licenses were verified by reading the upstream LICENSE file (jsfxr: UNLICENSE file + package.json). Copies live in `licenses/`. Retrieved 2026-10-03 (git clone --depth 1; commit shown).

| Name | URL @ commit | License | Taken / planned | Attribution |
|---|---|---|---|---|
| jsfxr | https://github.com/chr15m/jsfxr @ b7b6aa2 | Unlicense (public domain) | Vendored unmodified: `tools/vendor/jsfxr/{sfxr.js,riffwave.js,UNLICENSE}`, driven by `tools/sfx.mjs` | jsfxr by Chris McCormick et al. (courtesy) |
| ZzFX | https://github.com/KilledByAPixel/ZzFX @ aab7e2b | MIT | Vendored unmodified (ZzFXM's bundled copy): `tools/vendor/zzfxm/zzfx.js` + `LICENSE.ZzFX`, used by `tools/sfx.mjs` | ZzFX (c) 2019 Frank Force |
| ZzFXM | https://github.com/keithclark/ZzFXM @ cb07fa9 | MIT | Vendored unmodified: `tools/vendor/zzfxm/{zzfxm.js,LICENSE}`, used by `tools/music.mjs`; example songs as format reference only | ZzFXM (c) 2020 Keith Clark |
| Quiver tower-defense-godot4 | https://github.com/quiver-dev/tower-defense-godot4 @ 1cbd622 | Code MIT; assets CC-BY 4.0 | Patterns only (health-bar tween, pause, popup); no assets taken. Repo contains no audio files (LFS holds PNG/OTF only) | Code (c) 2022 Quiver; any asset used: "Art by Quiver, CC-BY 4.0" |
| Godot-4-Tower-Defense-Template | https://github.com/ape1121/Godot-4-Tower-Defense-Template @ cfdbf5e | MIT | Planned: targeting logic (closest-target) adapted into TowerState | (c) 2024 Alp |
| Maaack Godot-Game-Template | https://github.com/Maaack/Godot-Game-Template @ 6849d6c | MIT | Planned: options/audio menu, pause menu, credits, scene-loader fade patterns adapted (no autoloads) | (c) 2022-present Marek Belski |
| game-icons.net | https://github.com/game-icons/icons @ 82d9488 | CC-BY 3.0 (some authors CC0) | Planned: selected SVGs for labs/cards/perks/coins/gems, recoloured | "Icons by <author> from game-icons.net, CC BY 3.0" — per icon, shown in in-game credits |
| anthropics/skills theme-factory | https://github.com/anthropics/skills/tree/main/skills/theme-factory @ 8a1541c | Apache-2.0 | Planned: vendor folder to `.claude/skills/theme-factory/` with LICENSE | theme-factory (c) Anthropic, Apache-2.0 |
| Idle-math references | Kongregate "The Math of Idle Games" (blog); ellisonleao/magictools (MIT); godotengine/awesome-godot (CC-BY 4.0) | — | Formulas/ideas only, no files copied | — |

**Not obtainable:** kenney.nl (impact-sounds, interface-sounds, particle-pack) returned HTTP 000 (blocked by proxy); not used.
**Rejected:** youtd2 (CC-BY-NC assets); Hollow-Vigil, drift-station, awesome-claude-skills (no license).
