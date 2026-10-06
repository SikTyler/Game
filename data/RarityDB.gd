extends RefCounted
## Gear rarities (V2 P4, V2_DESIGN gear table). One table for Weapons and
## Core Modules. Odds are DISCLOSED in the Forge (ethical casino: visible pity,
## published odds, never paid).
##   perks     perk slots a fresh item rolls (Exotic: + its signature perk)
##   base      base-stat multiplier on the frame / module sheet
##   max_lvl   upgrade cap
##   rm        cost multiplier for upgrade / reroll / imprint
##   drop      % odds of a run drop (before luck)
##   forge     % odds of a Forge roll (Mythic / Exotic are drop-only)
##   salvage   Scrap returned by salvaging a fresh item

const IDS: Array = ["common", "uncommon", "rare", "epic", "legendary", "mythic", "exotic"]
const DEFS: Dictionary = {
	"common":    {"name": "Common",    "perks": 1, "base": 1.00, "max_lvl": 10, "rm": 1.0,  "drop": 58.0,  "forge": 50.0, "salvage": 4},
	"uncommon":  {"name": "Uncommon",  "perks": 2, "base": 1.12, "max_lvl": 15, "rm": 1.6,  "drop": 26.0,  "forge": 30.0, "salvage": 10},
	"rare":      {"name": "Rare",      "perks": 2, "base": 1.28, "max_lvl": 20, "rm": 2.5,  "drop": 11.0,  "forge": 15.0, "salvage": 25},
	"epic":      {"name": "Epic",      "perks": 3, "base": 1.48, "max_lvl": 25, "rm": 4.0,  "drop": 4.0,   "forge": 4.5,  "salvage": 60},
	"legendary": {"name": "Legendary", "perks": 3, "base": 1.72, "max_lvl": 30, "rm": 6.5,  "drop": 0.85,  "forge": 0.5,  "salvage": 150},
	"mythic":    {"name": "Mythic",    "perks": 4, "base": 2.00, "max_lvl": 40, "rm": 10.0, "drop": 0.14,  "forge": 0.0,  "salvage": 400},
	"exotic":    {"name": "Exotic",    "perks": 4, "base": 2.30, "max_lvl": 50, "rm": 15.0, "drop": 0.01,  "forge": 0.0,  "salvage": 1000},
}
## Visible pity (rolls without a hit): soft pity raises the odds linearly from
## `soft` until the hard cap guarantees the tier on roll `hard`.
const PITY: Dictionary = {
	"e": {"min": "epic", "soft": 22, "hard": 30},
	"l": {"min": "legendary", "soft": 110, "hard": 150},
	"m": {"min": "mythic", "soft": 800, "hard": 1000},
}


static func rank(r: String) -> int:
	return IDS.find(r)


static func get_def(r: String) -> Dictionary:
	return DEFS.get(r, DEFS["common"])


static func at_least(r: String, floor_r: String) -> bool:
	return rank(r) >= rank(floor_r)


## Next rarity up (merge result); "" at the top.
static func next(r: String) -> String:
	var k: int = rank(r)
	return String(IDS[k + 1]) if k >= 0 and k + 1 < IDS.size() else ""


## Odds table (percent) for a source ("drop" / "forge"), luck-shifted: each
## point of luck moves 2% of the Common share up the ladder (proportionally).
static func odds(source: String, luck: float = 0.0) -> Dictionary:
	var out: Dictionary = {}
	var tot: float = 0.0
	for r in IDS:
		out[r] = float((DEFS[r] as Dictionary)[source])
		tot += float(out[r])
	var shift: float = clampf(luck * 0.02, 0.0, 0.6) * float(out["common"])
	if shift > 0.0:
		out["common"] = float(out["common"]) - shift
		var up: float = 0.0
		for r in IDS:
			if r != "common":
				up += float(out[r])
		if up > 0.0:
			for r in IDS:
				if r != "common":
					out[r] = float(out[r]) + shift * float(out[r]) / up
	# normalise to 100 (tables are authored to sum to 100)
	if tot > 0.0:
		for r in IDS:
			out[r] = float(out[r]) * 100.0 / tot
	return out
