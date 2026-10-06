extends RefCounted
## Core Weapon frames (V2 P4): the Weapon the player forges and mounts in the
## Core's centre slot. A frame fixes the attack (TowerState._core_fire /
## FirePatterns), its L1 numbers and its silhouette (PartVis barrel); rarity, level,
## brand and perks scale and modify it. The first four are the old Core
## attacks; the other six are new patterns.
##   attack   core attack code (cannon slag beam pulse scatter rail arc flame missiles saw)
##   dmg, rate, range: L1 Common sheet (range in cpx() cells)
##   p        attack parameters (splash in cells, slows, ramps, counts ...)
##   look     V2 silhouette data (V3 barrels draw from their PartDB look)
##   affinity perk ids this frame rolls more often (x2 weight)

const IDS: Array = ["autocannon", "slag", "lance", "pulse", "scatter", "rail", "arc", "flame", "missiles", "saw"]
const DEFS: Dictionary = {
	"autocannon": {"name": "Autocannon", "attack": "cannon", "dmg": 10.0, "rate": 1.25, "range": 4.0,
		"p": {"splash": 0.5, "splash_frac": 0.4}, "desc": "Shells the nearest enemy; a 0.5-cell splash at 40%",
		"look": {"body": 0, "barrel": 0, "muzzle": 0}, "affinity": ["w_dmg", "w_splash", "w_rate"]},
	"slag": {"name": "Slag Lobber", "attack": "slag", "dmg": 5.0, "rate": 1.0, "range": 3.5,
		"p": {"splash": 1.0, "slow": 0.2, "slow_t": 2.0}, "desc": "Lobs molten slag: a 1-cell splash that slows 20% for 2 s",
		"look": {"body": 1, "barrel": 3, "muzzle": 2}, "affinity": ["w_splash", "w_slow", "w_burn"]},
	"lance": {"name": "Lance", "attack": "beam", "dmg": 28.0, "rate": 0.5, "range": 5.5,
		"p": {"ramp": 0.15, "ramp_max": 1.5}, "desc": "A beam that locks one target and ramps up to +150% the longer it holds",
		"look": {"body": 2, "barrel": 1, "muzzle": 1}, "affinity": ["w_boss", "w_crit_dmg", "w_range"]},
	"pulse": {"name": "Pulse Nova", "attack": "pulse", "dmg": 6.0, "rate": 0.8, "range": 3.0,
		"p": {"knock": 0.3, "chain_every": 5, "chain_frac": 0.4, "chain_n": 3}, "desc": "A ring that hits everything in range and knocks it back; every 5th chains outward",
		"look": {"body": 3, "barrel": 4, "muzzle": 3}, "affinity": ["w_knock", "w_rate", "w_chain"]},
	"scatter": {"name": "Scatter Cannon", "attack": "scatter", "dmg": 4.0, "rate": 1.0, "range": 3.0,
		"p": {"pellets": 6, "cone": 40.0}, "desc": "Six pellets across a 40 deg cone at the target; each stops in the first body",
		"look": {"body": 0, "barrel": 2, "muzzle": 4}, "affinity": ["w_multishot", "w_dmg", "w_knock"]},
	"rail": {"name": "Rail Driver", "attack": "rail", "dmg": 30.0, "rate": 0.4, "range": 6.5,
		"p": {"pierce": 10.0}, "desc": "A slug through every body on the line to the target",
		"look": {"body": 2, "barrel": 5, "muzzle": 1}, "affinity": ["w_pierce", "w_crit", "w_boss"]},
	"arc": {"name": "Arc Caster", "attack": "arc", "dmg": 8.0, "rate": 1.0, "range": 3.5,
		"p": {"chain": 5, "chain_frac": 0.8, "jump": 70.0}, "desc": "Lightning that jumps 5 times (70 px, x0.8 per jump) and shocks",
		"look": {"body": 3, "barrel": 6, "muzzle": 5}, "affinity": ["w_chain", "w_slow", "w_rate"]},
	"flame": {"name": "Flame Projector", "attack": "flame", "dmg": 6.0, "rate": 2.0, "range": 2.5,
		"p": {"cone": 50.0}, "desc": "A 50 deg cone of fire at the target: light hits, a spreading burn",
		"look": {"body": 1, "barrel": 7, "muzzle": 6}, "affinity": ["w_burn", "w_rate", "w_splash"]},
	"missiles": {"name": "Swarm Missiles", "attack": "missiles", "dmg": 7.0, "rate": 0.6, "range": 5.0,
		"p": {"missiles": 4, "splash": 0.3}, "desc": "Four seekers at the four nearest enemies; a small blast each",
		"look": {"body": 4, "barrel": 8, "muzzle": 7}, "affinity": ["w_multishot", "w_splash", "w_range"]},
	# V3 parts: the Minigun barrel (not in IDS: V2 gear never rolls it)
	"minigun": {"name": "Minigun", "attack": "minigun", "dmg": 2.6, "rate": 6.0, "range": 3.5,
		"p": {"spread": 3}, "desc": "Hoses the crowd: six light rounds a second, each at a random body among the nearest three",
		"look": {"body": 0, "barrel": 2, "muzzle": 4}, "affinity": ["w_rate", "w_dmg", "w_crit"]},
	"saw": {"name": "Saw Launcher", "attack": "saw", "dmg": 12.0, "rate": 0.9, "range": 4.0,
		"p": {"bounces": 4, "bounce_frac": 0.85, "jump": 90.0}, "desc": "A saw that ricochets between 5 enemies (x0.85 each) and shreds armor",
		"look": {"body": 4, "barrel": 9, "muzzle": 8}, "affinity": ["w_bounce", "w_shred", "w_dmg"]},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["autocannon"])
