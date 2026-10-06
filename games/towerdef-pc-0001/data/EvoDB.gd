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
	# ---- V2 P7d
	"pulse": {"name": "Shockwave Core", "partner": "capacitor", "fx": {"dmg": 1.0, "range": 1.0, "rate": 0.30}, "desc": "+100% damage, +1 range, +30% rate"},
	"missile": {"name": "Swarm Command", "partner": "uplink", "fx": {"missiles": 4.0, "dmg": 0.40}, "desc": "+4 missiles per salvo, +40% damage"},
	"spike": {"name": "Iron Maiden", "partner": "gate", "fx": {"dmg": 1.5, "range": 0.6}, "desc": "+150% damage, +0.6 range"},
	"mines": {"name": "Minefield", "partner": "lure", "fx": {"splash": 0.60, "dmg": 0.80, "rate": 0.30}, "desc": "+60% blast, +80% damage, +30% laying rate"},
	"scatter": {"name": "Buckshot Storm", "partner": "ammodepot", "fx": {"pellets": 6.0, "dmg": 0.40}, "desc": "+6 pellets, +40% damage"},
	"laser": {"name": "Solar Lance", "partner": "coolant", "fx": {"ramp": 2.0, "dmg": 0.60, "pierce": 6.0}, "desc": "Ramps to x5, +60% damage, a wider beam"},
	"saw": {"name": "Ripper", "partner": "salvager", "fx": {"bounces": 4.0, "dmg": 0.60}, "desc": "+4 bounces, +60% damage"},
	"arcproj": {"name": "Tempest Arc", "partner": "ocrelay", "fx": {"chains": 6.0, "arcs": 2.0, "dmg": 0.30}, "desc": "+6 jumps, +2 forks, +30% damage"},
	"sonic": {"name": "Thunderclap", "partner": "shieldpylon", "fx": {"knock": 1.5, "dmg": 1.0, "arc": 30.0}, "desc": "Knockback x2.5, +100% damage, a wider cone"},
	"harpoon": {"name": "Leviathan Spear", "partner": "watchtower", "fx": {"dmg": 1.0, "elite": 2.5, "range": 1.5}, "desc": "+100% damage, x5 on elites, +1.5 range"},
	"plasma": {"name": "Sun Fence", "partner": "amp", "fx": {"burn": 1.5, "dmg": 0.60}, "desc": "+150% burn, +60% damage"},
	"flakburst": {"name": "Cluster Barrage", "partner": "critlens", "fx": {"splash": 0.50, "dmg": 0.60, "crit": 0.15}, "desc": "+50% bursts, +60% damage, +15% crit"},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


## The draft card for evolving the weapon anchored at `slot`.
static func card(id: String, slot: int) -> Dictionary:
	return {"id": "evo_" + id, "weapon": id, "kind": "evo", "fam": "evolution", "rarity": "legendary", "tags": ["dps"], "reward": "evolution", "slot": slot}
