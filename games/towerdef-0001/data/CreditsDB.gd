extends RefCounted
## In-game credits. Mirrors /third_party/README.md (keep in sync when a source
## is added there). Only sources actually used by the shipped game are listed;
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
