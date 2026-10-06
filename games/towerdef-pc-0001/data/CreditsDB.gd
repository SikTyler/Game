extends RefCounted
## In-game credits (PC edition). Mirrors /third_party/README.md (all rows, incl. the PC section); tools/credits.test.mjs (npm test)
## fails if a used README source is missing here. If game-icons SVGs are adopted,
## add one "Icon by <author> from game-icons.net, CC BY 3.0" line per icon. Only sources actually used by the shipped game are listed;
## CC-BY items must carry their attribution line here.

const LINES: Array = [
	["COREHOLD", "h"],
	["Design, code, art and audio generated with GameForge (Claude skills)", "p"],
	["", "p"],
	["ENGINE", "h"],
	["Godot Engine — MIT License. (c) 2014-present Godot Engine contributors; (c) 2007-2014 Juan Linietsky, Ariel Manzur.", "p"],
	["", "p"],
	["AUDIO", "h"],
	["Sound effects rendered with jsfxr by Chris McCormick et al. — Unlicense (public domain).", "p"],
	["ZzFX (c) 2019 Frank Force — MIT License.", "p"],
	["Music sequenced with ZzFXM (c) 2020 Keith Clark — MIT License.", "p"],
	["", "p"],
	["CODE PATTERNS", "h"],
	["Options, pause, credits and fade patterns adapted from Maaack's Godot-Game-Template (c) 2022-present Marek Belski — MIT License.", "p"],
	["Tower defense patterns from quiver-dev/tower-defense-godot4 (c) 2022 Quiver — MIT License (code only; no art used).", "p"],
	["Targeting reference from ape1121/Godot-4-Tower-Defense-Template (c) 2024 Alp — MIT License.", "p"],
	["", "p"],
	["PC EDITION", "h"],
	["Input prompt glyphs: Xelu's FREE Controllers & Keyboard PROMPTS by Nicolae (Xelu) Berbece, thoseawesomeguys.com/prompts — CC0 (via rsubtil/controller_icons, addon (c) 2023 Ricardo Subtil — MIT License).", "p"],
	["Settings, video/audio options and input-remap patterns adapted from Maaack's Godot-Game-Template and Godot-Input-Remapping (c) Marek Belski — MIT License.", "p"],
	["Keybind save/load and swap-on-conflict ported from nathanhoad/godot_input_helper (c) 2022-present Nathan Hoad — MIT License.", "p"],
	["Window, resolution, joypad and input-mapping patterns from godotengine/godot-demo-projects (c) Godot Engine contributors — MIT License.", "p"],
	["Export CI adapted from abarichello/godot-ci (c) Barichello — MIT License.", "p"],
	["", "p"],
	["FONTS", "h"],
	["Chakra Petch (c) 2018 The Chakra Petch Project Authors — SIL Open Font License (OFL-1.1).", "p"],
	["Inter (c) 2020 The Inter Project Authors — SIL Open Font License (OFL-1.1).", "p"],
	["", "p"],
	["TOOLS", "h"],
	["UI palette tooling: anthropics/skills theme-factory (c) Anthropic — Apache-2.0.", "p"],
	["", "p"],
	["Full license texts ship in third_party/licenses/.", "p"],
	["Thanks for playing!", "p"],
]


static func text() -> String:
	var out: PackedStringArray = PackedStringArray()
	for ln in LINES:
		out.append(String((ln as Array)[0]))
	return "\n".join(out)
