extends RefCounted
## Core Parts (REDESIGN_SYSTEMS §3.2, REDESIGN_SPEC §3.1). Every part has a
## slot (F Frame, B Barrel, C Capacitor, E Engine), a rarity, a `plus` (the
## benefit, scaled +8% of L1 per level and +5% per star) and a `minus` (the
## drawback, which never scales). Values are in engine units (see FX_TEXT);
## TowerState folds the summed fx from `Parts.run_fx` (additive within
## (1 + sum) per key, POWER_MODEL §8 rule 5).
## Magnitudes are re-tuned from the SYSTEMS table so every part's L1 value
## (PowerModel.part_value over VAL) sits within 10 percent of its rarity
## budget and the drawback is at least a quarter of the benefit (AC-12). Set
## specials (rarity "special") unlock from full sets (SetDB) and are never in
## crate or drop pools.
## Slot fixes (deliberate, so every full set fits the F/B/C/E/F/B slot cycle):
## Mirror Hull sits in a Capacitor slot (Bulwark had 3 Frames) and Battery
## Bank in an Engine slot (Storm had 2 Capacitors). Ids are unchanged.

const DEFS: Dictionary = {
	"f_plating": {"name": "Plating", "slot": "F", "rarity": "common", "set": "", "plus": {"core_hp": 0.28}, "minus": {"rate": -0.042}},
	"f_lightweave": {"name": "Lightweave", "slot": "F", "rarity": "common", "set": "", "plus": {"rate": 0.131}, "minus": {"core_hp": -0.083}},
	"f_bulkhead": {"name": "Bulkhead", "slot": "F", "rarity": "rare", "set": "bulwark", "plus": {"armor": 2.93}, "minus": {"range": -0.3}},
	"f_regenmesh": {"name": "Regen Mesh", "slot": "F", "rarity": "rare", "set": "bulwark", "plus": {"regen": 0.59}, "minus": {"dmg": -0.063}},
	"f_mirror": {"name": "Mirror Hull", "slot": "C", "rarity": "epic", "set": "bulwark", "plus": {"reflect": 0.182}, "minus": {"cash": -0.124}},
	"f_ledgerframe": {"name": "Ledger Frame", "slot": "F", "rarity": "rare", "set": "mint", "plus": {"cash_flat": 0.61}, "minus": {"core_hp": -0.121}},
	"f_hivecomb": {"name": "Hivecomb", "slot": "F", "rarity": "epic", "set": "swarm", "plus": {"troop_count": 1}, "minus": {"troop_hp": -0.31}},
	"f_glass": {"name": "Glass Cannon", "slot": "F", "rarity": "legendary", "set": "", "plus": {"dmg": 0.40}, "minus": {"core_hp": -0.18}},
	"b_longbore": {"name": "Long Bore", "slot": "B", "rarity": "common", "set": "", "plus": {"range": 0.72}, "minus": {"rate": -0.042}},
	"b_shortbore": {"name": "Short Bore", "slot": "B", "rarity": "common", "set": "", "plus": {"rate": 0.131}, "minus": {"range": -0.2}},
	"b_hollow": {"name": "Hollow Point", "slot": "B", "rarity": "rare", "set": "lancer", "plus": {"core_dmg": 0.2}, "minus": {"crit": -0.03}},
	"b_focuslens": {"name": "Focus Lens", "slot": "B", "rarity": "epic", "set": "lancer", "plus": {"beam_ramp": 0.69}, "minus": {"retarget": 0.88}},
	"b_scatter": {"name": "Scatter Choke", "slot": "B", "rarity": "rare", "set": "storm", "plus": {"splash": 0.45}, "minus": {"core_single": -0.088}},
	"b_ringcaster": {"name": "Ringcaster", "slot": "B", "rarity": "epic", "set": "storm", "plus": {"chain": 1}, "minus": {"rate": -0.071}},
	"b_crit": {"name": "Keen Rifling", "slot": "B", "rarity": "rare", "set": "", "plus": {"crit": 0.10}, "minus": {"dmg": -0.045}},
	"b_bounty": {"name": "Bounty Sight", "slot": "B", "rarity": "rare", "set": "mint", "plus": {"kill_cash": 0.27}, "minus": {"dmg": -0.044}},
	"b_droneport": {"name": "Drone Port", "slot": "B", "rarity": "rare", "set": "swarm", "plus": {"hut_drone": 1}, "minus": {"core_dmg": -0.08}},
	"c_overcharge": {"name": "Overcharge Cell", "slot": "C", "rarity": "common", "set": "", "plus": {"special_dmg": 0.28}, "minus": {"special_cd": 0.033}},
	"c_quickcap": {"name": "Quick Cap", "slot": "C", "rarity": "rare", "set": "", "plus": {"special_cd": -0.179}, "minus": {"special_dmg": -0.121}},
	"c_battery": {"name": "Battery Bank", "slot": "E", "rarity": "rare", "set": "storm", "plus": {"special_charges": 1}, "minus": {"rate": -0.084}},
	"c_capacitor_arc": {"name": "Arc Capacitor", "slot": "C", "rarity": "epic", "set": "storm", "plus": {"chain_dmg": 0.39}, "minus": {"range": -0.41}},
	"c_interest": {"name": "Interest Chip", "slot": "C", "rarity": "rare", "set": "mint", "plus": {"interest": 0.026}, "minus": {"dmg": -0.0435}},
	"c_scope": {"name": "Hunter Scope", "slot": "C", "rarity": "epic", "set": "lancer", "plus": {"boss": 0.58}, "minus": {"normal_dmg": -0.25}},
	"c_pheromone": {"name": "Pheromone Cell", "slot": "C", "rarity": "rare", "set": "swarm", "plus": {"troop_dmg": 0.45}, "minus": {"core_dmg": -0.065}},
	"c_luckchip": {"name": "Luck Chip", "slot": "C", "rarity": "epic", "set": "", "plus": {"luck": 3}, "minus": {"perk_choices": -1}},
	"e_turbine": {"name": "Turbine", "slot": "E", "rarity": "common", "set": "", "plus": {"cash_flat": 0.39}, "minus": {"dmg": -0.042}},
	"e_reactor": {"name": "Reactor", "slot": "E", "rarity": "rare", "set": "", "plus": {"dmg": 0.2}, "minus": {"cash_flat": -0.179}},
	"e_dynamo": {"name": "Dynamo", "slot": "E", "rarity": "rare", "set": "", "plus": {"bld_rate": 0.45}, "minus": {"rate": -0.063}},
	"e_mintpress": {"name": "Mint Press", "slot": "E", "rarity": "epic", "set": "mint", "plus": {"cash": 0.40}, "minus": {"dmg": -0.061}},
	"e_bastionheart": {"name": "Bastion Heart", "slot": "E", "rarity": "epic", "set": "bulwark", "plus": {"dmg_per_bld": 0.037}, "minus": {"ring_delay": 1}},
	"e_railcore": {"name": "Rail Core", "slot": "E", "rarity": "legendary", "set": "lancer", "plus": {"core_dmg": 0.42}, "minus": {"nosplash": 1, "rate": -0.022}},
	"e_queen": {"name": "Queen Engine", "slot": "E", "rarity": "legendary", "set": "swarm", "plus": {"troop_respawn": -0.36}, "minus": {"queen_hold": 1}},
}

const SPECIALS: Dictionary = {
	"citadel_heart": {"name": "Citadel Heart", "slot": "E", "rarity": "special", "set": "bulwark", "plus": {"core_hp": 0.62, "armor": 3.7}, "minus": {"rate": -0.149}},
	"golden_ratio": {"name": "Golden Ratio", "slot": "C", "rarity": "special", "set": "mint", "plus": {"cash": 0.95}, "minus": {"special_tax": 0.05}},
	"singularity_lens": {"name": "Singularity Lens", "slot": "B", "rarity": "special", "set": "lancer", "plus": {"shred": 0.059}, "minus": {"range": -0.66}},
	"eye_of_storm": {"name": "Eye of the Storm", "slot": "F", "rarity": "special", "set": "storm", "plus": {"pulse_dmg": 0.93}, "minus": {"core_hp": -0.28}},
	"brood_mother": {"name": "Brood Mother", "slot": "E", "rarity": "special", "set": "swarm", "plus": {"hut_max": 1}, "minus": {"bld_dmg": -0.29}},
}

const SLOTS: Array = ["F", "B", "C", "E"]
const SLOT_NAMES: Dictionary = {"F": "Frame", "B": "Barrel", "C": "Capacitor", "E": "Engine", "S": "Set"}
const RARITIES: Array = ["common", "rare", "epic", "legendary"]
const MAX_LVL: Dictionary = {"common": 5, "rare": 10, "epic": 15, "legendary": 20, "special": 20}
const RARITY_R: Dictionary = {"common": 1, "rare": 2, "epic": 4, "legendary": 8, "special": 8}
const SALVAGE_BASE: Dictionary = {"common": 5, "rare": 15, "epic": 50, "legendary": 150, "special": 150}
## Keys whose value is a count (never fractional, never level-scaled).
const INT_KEYS: Array = ["troop_count", "hut_drone", "chain", "special_charges", "luck", "perk_choices", "hut_max", "ring_delay", "nosplash", "queen_hold", "last_stand", "interest_fast", "pierce", "storm_pulse", "troop_ls"]
## Valuation: fx key -> [PowerModel log-power weight, unit-to-fraction scale].
## A negative scale marks a key whose positive value is a cost (cooldown,
## delay). POWER_MODEL §8 weights for dmg/rate/hp/regen/cash/crit; the rest
## convert their unit into an equivalent fractional power.
const VAL: Dictionary = {
	"dmg": [1.0, 1.0], "core_dmg": [1.0, 1.0], "bld_dmg": [0.5, 1.0], "rate": [1.0, 1.0], "bld_rate": [0.5, 1.0],
	"core_hp": [0.5, 1.0], "regen": [0.4, 1.0], "armor": [0.4, 0.2], "range": [0.4, 0.5], "cash": [0.69, 1.0],
	"cash_flat": [0.69, 0.5], "kill_cash": [0.69, 1.0], "crit": [1.7, 1.0], "interest": [0.5, 15.0],
	"special_dmg": [0.5, 1.0], "special_cd": [0.5, -2.5], "special_charges": [0.3, 1.0], "chain": [0.6, 0.5],
	"chain_dmg": [0.8, 1.0], "splash": [0.5, 1.0], "core_single": [0.7, 1.0], "nosplash": [0.3, -0.3],
	"beam_ramp": [0.5, 1.0], "retarget": [0.3, -0.3], "boss": [1.0, 1.0], "normal_dmg": [1.0, 1.0],
	"troop_count": [0.6, 0.5], "hut_drone": [0.5, 0.5], "troop_hp": [0.2, 1.0], "troop_dmg": [0.5, 1.0],
	"troop_respawn": [0.8, -1.5], "queen_hold": [0.3, -0.3], "hut_max": [1.0, 0.6], "luck": [0.6, 0.2],
	"perk_choices": [0.3, 0.33], "dmg_per_bld": [1.0, 8.0], "ring_delay": [0.3, -0.25], "reflect": [0.6, 3.0],
	"special_tax": [0.3, -8.0], "shred": [1.0, 10.0], "pulse_dmg": [0.7, 1.0],
	"last_stand": [0.5, 0.3], "interest_fast": [0.5, 0.3], "pierce": [0.7, 0.4], "storm_pulse": [0.5, 0.3], "troop_ls": [0.3, 0.3],
}
## Tooltip text per fx key ("{v}" gets the formatted value).
const FX_TEXT: Dictionary = {
	"dmg": "{v} all damage", "core_dmg": "{v} Core damage", "bld_dmg": "{v} building damage", "rate": "{v} Core attack rate",
	"bld_rate": "{v} building attack rate", "core_hp": "{v} Core HP", "regen": "{v} Core regen", "armor": "{v} armor",
	"range": "{v} Core range (cells)", "cash": "{v} cash/s", "cash_flat": "{v} cash/s (flat)", "kill_cash": "{v} kill cash",
	"crit": "{v} crit chance", "interest": "{v} interest per wave, +50 cap", "special_dmg": "{v} special damage",
	"special_cd": "{v} special cooldowns", "special_charges": "{v} special charge", "chain": "{v} chain (Tempest: +1 ring)",
	"chain_dmg": "{v} chain / Tesla damage", "splash": "{v} Core splash (cells)", "core_single": "{v} Core single-target damage",
	"nosplash": "Core shots lose their splash", "beam_ramp": "{v} Lance ramp speed", "retarget": "{v} s beam retarget delay",
	"boss": "{v} damage vs bosses and elites", "normal_dmg": "{v} damage vs normal enemies", "troop_count": "{v} troop per hut",
	"hut_drone": "{v} drone per Drone Bay", "troop_hp": "{v} troop HP", "troop_dmg": "{v} troop damage",
	"troop_respawn": "{v} troop respawn time", "queen_hold": "Core holds fire while 3+ troops live", "hut_max": "{v} troop hut max",
	"luck": "{v} draft Luck", "perk_choices": "{v} perk choice", "dmg_per_bld": "{v} damage per building (max 12)",
	"ring_delay": "grid rings open one step later", "reflect": "reflects {v} of contact damage", "special_tax": "specials cost {v} of banked cash",
	"shred": "Core hits shred {v} armor (stacks x5)", "pulse_dmg": "{v} pulse ring damage",
	"last_stand": "Core immune 2 s after dropping below 30% HP (once per wave)", "interest_fast": "interest is paid every 15 s",
	"pierce": "Core attack pierces 1 extra enemy", "storm_pulse": "every 10th Core attack fires a free Pulse Ring",
	"troop_ls": "troops lifesteal 1% and heal the Core 0.5 HP per kill",
}
const PCT_KEYS: Array = ["dmg", "core_dmg", "bld_dmg", "rate", "bld_rate", "core_hp", "regen", "cash", "kill_cash", "crit", "interest", "special_dmg", "special_cd", "chain_dmg", "core_single", "beam_ramp", "boss", "normal_dmg", "troop_hp", "troop_dmg", "troop_respawn", "dmg_per_bld", "reflect", "special_tax", "shred", "pulse_dmg"]
const UNSIGNED_PCT: Array = ["reflect", "special_tax", "shred"]


static func has(id: String) -> bool:
	return DEFS.has(id) or SPECIALS.has(id)


static func get_def(id: String) -> Dictionary:
	if DEFS.has(id):
		return DEFS[id]
	return SPECIALS.get(id, {})


static func is_special(id: String) -> bool:
	return SPECIALS.has(id)


static func rarity_of(id: String) -> String:
	return String(get_def(id).get("rarity", "common"))


static func slot_of(id: String) -> String:
	return String(get_def(id).get("slot", ""))


static func set_of(id: String) -> String:
	return String(get_def(id).get("set", ""))


static func max_lvl(id: String) -> int:
	return int(MAX_LVL.get(rarity_of(id), 5))


## Ids of one rarity (crate / drop pools; set specials excluded), sorted.
static func pool(rarity: String) -> Array:
	var out: Array = []
	for id in DEFS.keys():
		if String((DEFS[id] as Dictionary)["rarity"]) == rarity:
			out.append(String(id))
	out.sort()
	return out


## Benefit multiplier at a level / star count (SYSTEMS §3.1, §3.4).
static func plus_mult(lvl: int, stars: int = 0) -> float:
	return (1.0 + 0.08 * float(maxi(1, lvl) - 1)) * (1.0 + 0.05 * float(clampi(stars, 0, 2)))


## Scrap to go L -> L+1: 10 * r * 1.25^(L-1).
static func level_cost(id: String, lvl: int) -> int:
	return int(round(10.0 * float(RARITY_R.get(rarity_of(id), 1)) * pow(1.25, float(maxi(1, lvl) - 1))))


## Total Scrap invested to reach `lvl` from L1.
static func invested(id: String, lvl: int) -> int:
	var n: int = 0
	for l in range(1, maxi(1, lvl)):
		n += level_cost(id, l)
	return n


## Signed valuation stats {key: frac} for PowerModel.part_value.
static func val_stats(fx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in fx.keys():
		var v: Array = VAL.get(String(k), [0.5, 1.0])
		out[String(k)] = float(fx[k]) * float(v[1])
	return out


static func val_weights() -> Dictionary:
	var w: Dictionary = {}
	for k in VAL.keys():
		w[k] = float((VAL[k] as Array)[0])
	return w


## A part as PowerModel sees it: {rarity, lvl, slot, stats}.
static func pm_part(id: String, lvl: int = 1) -> Dictionary:
	var d: Dictionary = get_def(id)
	var fx: Dictionary = (d.get("plus", {}) as Dictionary).duplicate()
	fx.merge(d.get("minus", {}))
	return {"rarity": String(d.get("rarity", "common")), "lvl": lvl, "slot": String(d.get("slot", "")), "stats": val_stats(fx)}


static func fmt_fx(k: String, v: float) -> String:
	var t: String = String(FX_TEXT.get(k, k + " {v}"))
	var s: String = ""
	if UNSIGNED_PCT.has(k):
		s = "%.0f%%" % (v * 100.0)
	elif PCT_KEYS.has(k):
		s = "%+.0f%%" % (v * 100.0)
	elif INT_KEYS.has(k):
		s = "%+d" % int(v)
	else:
		s = "%+.1f" % v
	return t.replace("{v}", s)


## Tooltip lines {plus: ["+ ..."], minus: ["- ..."]} (AC-34: both present).
static func lines(id: String, lvl: int = 1, stars: int = 0) -> Dictionary:
	var d: Dictionary = get_def(id)
	var m: float = plus_mult(lvl, stars)
	var plus: Array = []
	var minus: Array = []
	var p: Dictionary = d.get("plus", {})
	for k in p.keys():
		var v: float = float(p[k]) if INT_KEYS.has(String(k)) else float(p[k]) * m
		plus.append("+ " + fmt_fx(String(k), v))
	var n: Dictionary = d.get("minus", {})
	for k in n.keys():
		minus.append("- " + fmt_fx(String(k), float(n[k])))
	return {"plus": plus, "minus": minus}
