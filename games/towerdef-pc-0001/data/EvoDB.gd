extends RefCounted
## Weapon evolutions (V2 P7c, Vampire Survivors-style): a T3 weapon with its
## partner building touching it earns a one-time legendary EVOLUTION card in
## the next draft. Taking it evolves that weapon: a new name and a big fx
## package (MergeDB fx vocabulary) on top of its tier and mods.
##   weapon id -> {name, partner, fx{}, desc}
## P7d adds the evolutions of the new weapons.

const DEFS: Dictionary = {
	"gun": {"name": "Bullet Storm", "partner": "armory", "fx": {"rounds": 2.0, "dmg": 0.50, "pierce": 3.0}, "desc": "5 rounds per shot, +50% damage, +3 pierce"},
	"mortar": {"name": "Meteor Battery", "partner": "beacon", "fx": {"splash": 0.60, "dmg": 0.50, "knock": 1.0}, "desc": "+60% blast radius, +50% damage, knockback x2"},
	"tesla": {"name": "Storm Spire", "partner": "refinery", "fx": {"arcs": 3.0, "chains": 6.0, "dmg": 0.30}, "desc": "+3 forks, +6 jumps, +30% damage"},
	"flak": {"name": "Inferno Engine", "partner": "oilmill", "fx": {"burn": 1.5, "cone": 0.50, "rate": 0.30}, "desc": "+150% burn, +50% reach, +30% fire rate"},
	"railgun": {"name": "Mass Driver", "partner": "bulwark", "fx": {"boss": 6.0, "dmg": 0.60, "pierce": 10.0}, "desc": "First elite / boss hit x10, +60% damage, a wider lane"},
	"frost": {"name": "Absolute Zero", "partner": "aegis", "fx": {"slow": 0.25, "dmg": 2.0, "range": 1.0}, "desc": "+25% slow, +200% chill damage, +1 range"},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


## The draft card for evolving the weapon anchored at `slot`.
static func card(id: String, slot: int) -> Dictionary:
	return {"id": "evo_" + id, "weapon": id, "kind": "evo", "fam": "evolution", "rarity": "legendary", "tags": ["dps"], "reward": "evolution", "slot": slot}
