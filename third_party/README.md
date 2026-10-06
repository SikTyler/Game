# Third-party sources

Everything Corehold borrows, and how. Full license texts are in `licenses/`; the in-game credits screen (`data/CreditsDB.gd`) mirrors this list.

| Name | Source | License | How it is used |
|---|---|---|---|
| Godot Engine | https://godotengine.org | MIT | The engine (4.6.3 .NET). |
| jsfxr | https://github.com/chr15m/jsfxr | Unlicense | Sound effects were rendered with it (the WAVs in `audio/` are the output; `audio/recipes.json` holds the parameters). |
| ZzFX / ZzFXM | https://github.com/KilledByAPixel/ZzFX, https://github.com/keithclark/ZzFXM | MIT | Music and some effects were rendered with them. |
| Maaack Godot-Game-Template / Godot-Input-Remapping | https://github.com/Maaack/Godot-Game-Template | MIT | Patterns only (options, pause, credits, fades, key remapping). |
| quiver tower-defense-godot4 | https://github.com/quiver-dev/tower-defense-godot4 | MIT (code) | Patterns only; no art used. |
| Godot-4-Tower-Defense-Template | https://github.com/ape1121/Godot-4-Tower-Defense-Template | MIT | Nearest-target pattern (`TowerState.pick_target`). |
| controller_icons (Xelu prompts) | https://github.com/rsubtil/controller_icons | CC0 glyphs, MIT addon | Input prompt glyphs. |
| godot_input_helper | https://github.com/nathanhoad/godot_input_helper | MIT | Keybind save / load and swap-on-conflict (ported, no files copied). |
| Godot demo projects | https://github.com/godotengine/godot-demo-projects | MIT | Window, resolution, joypad and input-mapping patterns. |
| godot-ci | https://github.com/abarichello/godot-ci | MIT | Structure of `.github/workflows/export.yml`. |
| anthropics/skills theme-factory | https://github.com/anthropics/skills | Apache-2.0 | UI palette tooling used during design. |
| Chakra Petch, Inter (fonts) | https://github.com/google/fonts | OFL-1.1 | Bundled in `fonts/` unmodified. |
