extends RefCounted
## Enemy archetypes at wave 1 (SYSTEMS §8). Spawn gates live in Tiers.allows;
## weights in WEIGHTS (roll order: hauler, splitter, elite, ranged, skitter, drone). TowerState scales hp/dmg by hp_growth^(wave-1).

const DEFS: Dictionary = {
	"drone":   {"hp": 6.0,   "spd": 45.0, "dmg": 4.0,  "cash": 1.0,  "xp": 1.0,  "coin": 0.2,  "size": 16.0},
	"skitter": {"hp": 3.0,   "spd": 85.0, "dmg": 2.0,  "cash": 1.0,  "xp": 1.0,  "coin": 0.15, "size": 13.0},
	"hauler":  {"hp": 24.0,  "spd": 28.0, "dmg": 10.0, "cash": 3.0,  "xp": 3.0,  "coin": 0.6,  "size": 26.0},
	"ranged":  {"hp": 8.0,   "spd": 40.0, "dmg": 3.0,  "cash": 2.0,  "xp": 2.0,  "coin": 0.3,  "size": 15.0},
	"elite":   {"hp": 30.0,  "spd": 32.0, "dmg": 12.0, "cash": 5.0,  "xp": 5.0,  "coin": 1.0,  "size": 24.0},
	"splitter": {"hp": 18.0, "spd": 38.0, "dmg": 6.0,  "cash": 2.0,  "xp": 2.0,  "coin": 0.4,  "size": 22.0},
	"mite":    {"hp": 3.0,   "spd": 95.0, "dmg": 1.5,  "cash": 0.5,  "xp": 0.5,  "coin": 0.05, "size": 10.0},
	# Courier (REDESIGN §2.6): rare loot runner, 2x drone HP, 3x speed, harmless.
	"courier": {"hp": 12.0,  "spd": 135.0, "dmg": 0.0, "cash": 5.0,  "xp": 2.0,  "coin": 2.0,  "size": 18.0},
	"boss":    {"hp": 200.0, "spd": 22.0, "dmg": 18.0, "cash": 25.0, "xp": 15.0, "coin": 10.0, "size": 44.0},
	# MASS_HORDE §D1 new units (mass waves only; never in the classic roll).
	"sapper":  {"hp": 12.0,  "spd": 55.0, "dmg": 2.0,  "cash": 2.0,  "xp": 2.0,  "coin": 0.3,  "size": 16.0},
	"shield":  {"hp": 40.0,  "spd": 38.0, "dmg": 1.0,  "cash": 3.0,  "xp": 3.0,  "coin": 0.6,  "size": 20.0},
}

## Spawn weights per roll slot; elite comes from Tiers.elite_weight(tier).
const WEIGHTS: Dictionary = {"hauler": 0.15, "splitter": 0.10, "ranged": 0.12, "skitter": 0.25}
const ROLL_ORDER: Array = ["hauler", "splitter", "elite", "ranged", "skitter"]


static func get_def(kind: String) -> Dictionary:
	return DEFS.get(kind, {})


# ---------------------------------------------------------------- MASS_HORDE
## MASS_HORDE §D1/§D2: the designed mass roster (shipping waves). Every body is
## a designed unit at mass scale (no share of a bigger enemy). hp / dmg are
## Tier-1 wave-1 values; dmg is one contact hit on the Core (C# contact cadence
## 1 s; Spitters fire at range); `bld` = damage per contact hit on a structure
## (Sapper: its one detonation). cash / xp / coin are WEIGHTS that split each
## wave's designed pool (§D5), not payouts. `size` = 2 x the §D1 radius.
## `grow` picks the per-body HP growth class ("f" fodder/line, "h" heavy).
const MASS: Dictionary = {
	"mite":     {"hp": 2.0,   "spd": 90.0,  "dmg": 0.25, "bld": 0.25, "cash": 1.0,  "xp": 1.0,  "coin": 0.0,  "size": 10.0, "grow": "f"},
	"drone":    {"hp": 5.0,   "spd": 50.0,  "dmg": 0.5,  "bld": 0.5,  "cash": 2.0,  "xp": 2.0,  "coin": 0.0,  "size": 14.0, "grow": "f"},
	"skitter":  {"hp": 3.0,   "spd": 120.0, "dmg": 0.4,  "bld": 0.4,  "cash": 2.0,  "xp": 2.0,  "coin": 0.0,  "size": 12.0, "grow": "f"},
	"hauler":   {"hp": 60.0,  "spd": 30.0,  "dmg": 3.0,  "bld": 3.0,  "cash": 20.0, "xp": 20.0, "coin": 1.0,  "size": 26.0, "grow": "h"},
	"ranged":   {"hp": 8.0,   "spd": 42.0,  "dmg": 1.0,  "bld": 1.5,  "cash": 6.0,  "xp": 6.0,  "coin": 0.0,  "size": 14.0, "grow": "f"},
	"sapper":   {"hp": 12.0,  "spd": 55.0,  "dmg": 2.0,  "bld": 25.0, "cash": 8.0,  "xp": 8.0,  "coin": 0.0,  "size": 16.0, "grow": "f"},
	"shield":   {"hp": 40.0,  "spd": 38.0,  "dmg": 1.0,  "bld": 1.0,  "cash": 15.0, "xp": 15.0, "coin": 1.0,  "size": 20.0, "grow": "h", "guard": 30.0},
	"splitter": {"hp": 25.0,  "spd": 40.0,  "dmg": 1.0,  "bld": 1.0,  "cash": 10.0, "xp": 10.0, "coin": 0.0,  "size": 22.0, "grow": "h"},
	"courier":  {"hp": 30.0,  "spd": 140.0, "dmg": 0.0,  "bld": 0.0,  "cash": 0.0,  "xp": 0.0,  "coin": 0.0,  "size": 18.0, "grow": "h"},
	"elite":    {"hp": 300.0, "spd": 34.0,  "dmg": 8.0,  "bld": 8.0,  "cash": 150.0, "xp": 150.0, "coin": 10.0, "size": 24.0, "grow": "e"},
	"boss":     {"hp": 3000.0, "spd": 22.0, "dmg": 40.0, "bld": 40.0, "cash": 1500.0, "xp": 1500.0, "coin": 100.0, "size": 52.0, "grow": "e"},
}

## §D3 mix by wave band (share of the body count; elites / bosses / couriers
## are added on top). Rows: [first wave, {kind: share}]; the last row whose
## first wave <= w applies. Sappers come from wave 1 at Tier 3+ (§D7).
const MASS_MIX: Array = [
	[1,  {"mite": 0.80, "drone": 0.20}],
	[5,  {"mite": 0.65, "drone": 0.20, "skitter": 0.10, "ranged": 0.05}],
	[10, {"mite": 0.55, "drone": 0.18, "skitter": 0.10, "ranged": 0.06, "shield": 0.04, "sapper": 0.03, "splitter": 0.02, "hauler": 0.02}],
	[20, {"mite": 0.50, "drone": 0.16, "skitter": 0.10, "ranged": 0.07, "shield": 0.06, "sapper": 0.04, "splitter": 0.04, "hauler": 0.03}],
	[35, {"mite": 0.48, "drone": 0.14, "skitter": 0.10, "ranged": 0.08, "shield": 0.07, "sapper": 0.05, "splitter": 0.04, "hauler": 0.04}],
]
## Deterministic fill order of a surge (largest share first, ties by this list).
const MASS_ORDER: Array = ["mite", "drone", "skitter", "ranged", "shield", "sapper", "splitter", "hauler"]
## §D3 body-count tier factor (T1 = 1.0; T6+ keeps growing x1.5 per tier).
const TIER_B: Array = [1.0, 1.6, 2.5, 4.0, 6.0]


static func mass_def(kind: String) -> Dictionary:
	return MASS.get(kind, MASS["drone"])


static func mass_mix(w: int, tier: int) -> Dictionary:
	var m: Dictionary = {}
	for row in MASS_MIX:
		if int((row as Array)[0]) <= w:
			m = (row as Array)[1]
	m = m.duplicate()
	if tier >= 3 and not m.has("sapper"):
		# Tier 3+: sappers from wave 1 (taken out of the swarmling share)
		m["sapper"] = 0.03
		m["mite"] = float(m["mite"]) - 0.03
	return m


static func tier_b(tier: int) -> float:
	var t: int = maxi(1, tier)
	if t <= TIER_B.size():
		return float(TIER_B[t - 1])
	return float(TIER_B[TIER_B.size() - 1]) * pow(1.5, float(t - TIER_B.size()))
