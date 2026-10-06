extends RefCounted
## Gear brands (V2 P4; fictional manufacturers, Borderlands-style): each rolls
## a quirk (a small built-in trade-off folded into the item's fx), a palette
## (GearVis default paint) and name syllables (NameDB). Brands are rolled at
## random; the Brand Contracts research lets the Forge pick one (P8).

const IDS: Array = ["kessler", "volt", "inferno", "halcyon", "brute", "nyx"]
const DEFS: Dictionary = {
	"kessler": {"name": "Kessler Arms", "quirk": {"dmg": 0.10, "rate": -0.05}, "quirk_text": "+10% damage, -5% rate",
		"palette": ["8a95a8", "ff8a3d", "ffd34d"], "syl": ["Kes", "Grav", "Iron", "Hollow", "Ram"]},
	"volt": {"name": "Volt Dynamics", "quirk": {"chain_dmg": 0.15, "range": 0.2}, "quirk_text": "+15% chain damage, +0.2 range",
		"palette": ["39e6ff", "e8f0ff", "5b8cff"], "syl": ["Volt", "Arc", "Spark", "Ion", "Flux"]},
	"inferno": {"name": "Inferno Works", "quirk": {"burn": 0.10, "crit": -0.02}, "quirk_text": "+10% burn, -2% crit chance",
		"palette": ["ff4d6d", "ffb03a", "ffd34d"], "syl": ["Pyre", "Ash", "Ember", "Scorch", "Magma"]},
	"halcyon": {"name": "Halcyon", "quirk": {"crit": 0.04, "dmg": -0.04}, "quirk_text": "+4% crit chance, -4% damage",
		"palette": ["f0f6ff", "ffd34d", "a78bfa"], "syl": ["Hal", "Seraph", "Dawn", "Lumen", "Aria"]},
	"brute": {"name": "Brute Forge", "quirk": {"splash": 0.25, "rate": -0.08}, "quirk_text": "+0.25 splash, -8% rate",
		"palette": ["7a8f4a", "2a2f22", "d9b98a"], "syl": ["Brut", "Slab", "Maul", "Tusk", "Grind"]},
	"nyx": {"name": "Nyx Labs", "quirk": {"range": 0.35, "dmg": -0.05}, "quirk_text": "+0.35 range, -5% damage",
		"palette": ["b26bff", "2dd4bf", "ff3ea5"], "syl": ["Nyx", "Void", "Shade", "Echo", "Wisp"]},
	# never rolled (not in IDS): the starter weapon's neutral, quirk-free maker
	"standard": {"name": "Corehold Standard", "quirk": {}, "quirk_text": "No quirk",
		"palette": ["5a6788", "39e6ff", "e8f0ff"], "syl": ["Standard Issue"]},
}
const STANDARD: String = "standard"


static func has(id: String) -> bool:
	return DEFS.has(id)


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["kessler"])
