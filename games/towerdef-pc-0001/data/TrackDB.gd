extends RefCounted
## Core Enhancements (V2 P7b): in-run cash tracks in three trees. Standard
## tracks are cheap, small steps (base 40-150, growth 1.40-1.9, cap 5-25);
## each level adds `step` to the run's fx (TowerState.tf / pf: the same keys
## gear and Outpost buildings use). The five V1 tracks stay as OVERDRIVE
## tracks (od): big steps with a drawback each (their effects live in
## TowerState.compute_stats), base 300, growth 2.5, cap 4.
##   {tree, name, base, growth, cap, step{}, desc, [od, minus], [unlock]}
## `unlock` (P8): [research id, level] the save needs before the track can be
## bought (Enhancement Theory I / II / III open three tracks each).
## Tune pc_track_cap_<id> / pc_track_growth_<id> override a track.

const TREES: Array = [["attack", "Attack"], ["defense", "Defense"], ["economy", "Economy"]]

const DEFS: Dictionary = {
	# ---- Attack ----------------------------------------------------------
	"a_dmg":    {"tree": "attack", "name": "Damage", "base": 40.0, "growth": 1.40, "cap": 25, "step": {"dmg": 0.04}, "desc": "+4% all damage"},
	"a_rate":   {"tree": "attack", "name": "Attack Speed", "base": 45.0, "growth": 1.40, "cap": 20, "step": {"rate": 0.03, "bld_rate": 0.03}, "desc": "+3% Weapon and building attack rate"},
	"a_crit":   {"tree": "attack", "name": "Crit Chance", "base": 50.0, "growth": 1.42, "cap": 20, "step": {"crit": 0.015}, "desc": "+1.5% crit chance"},
	"a_critd":  {"tree": "attack", "name": "Crit Damage", "base": 50.0, "growth": 1.42, "cap": 20, "step": {"crit_dmg": 0.10}, "desc": "+10% crit damage"},
	"a_range":  {"tree": "attack", "name": "Range", "base": 60.0, "growth": 1.45, "cap": 15, "step": {"range": 0.10}, "desc": "+0.1 cell Weapon range"},
	"a_multi":  {"tree": "attack", "name": "Multishot", "base": 300.0, "growth": 2.20, "cap": 3, "step": {"multishot": 1.0}, "desc": "+1 Weapon target per volley"},
	"a_pierce": {"tree": "attack", "name": "Pierce", "base": 120.0, "growth": 1.80, "cap": 5, "step": {"pierce": 1.0}, "desc": "Weapon shots pierce +1 body", "unlock": ["enh_theory", 3]},
	"a_splash": {"tree": "attack", "name": "Splash", "base": 60.0, "growth": 1.45, "cap": 10, "step": {"splash": 0.05}, "desc": "+0.05 cell blast radius on splash Weapons"},
	"a_chain":  {"tree": "attack", "name": "Chain & Bounce", "base": 150.0, "growth": 1.90, "cap": 4, "step": {"chain": 1.0, "bounce": 1.0}, "desc": "+1 chain jump and +1 ricochet", "unlock": ["enh_theory", 2]},
	"a_boss":   {"tree": "attack", "name": "Boss Damage", "base": 55.0, "growth": 1.42, "cap": 15, "step": {"boss": 0.06}, "desc": "+6% damage to bosses"},
	"a_exec":   {"tree": "attack", "name": "Execute", "base": 80.0, "growth": 1.50, "cap": 10, "step": {"execute": 0.01}, "desc": "Weapon hits finish bodies under +1% HP", "unlock": ["enh_theory", 1]},
	"dmg":      {"tree": "attack", "name": "Overcharge", "od": true, "base": 300.0, "growth": 2.5, "cap": 4, "step": {}, "desc": "x1.40 Core + building damage", "minus": "-12% Core attack rate"},
	"rate":     {"tree": "attack", "name": "Overclock", "od": true, "base": 300.0, "growth": 2.5, "cap": 4, "step": {}, "desc": "+30% Core attack rate", "minus": "-9% Core damage"},
	"range":    {"tree": "attack", "name": "Long Barrel", "od": true, "base": 300.0, "growth": 2.5, "cap": 4, "step": {}, "desc": "+0.75 Core range", "minus": "-8% Core attack rate"},
	# ---- Defense ---------------------------------------------------------
	"d_hp":     {"tree": "defense", "name": "Max HP", "base": 40.0, "growth": 1.40, "cap": 25, "step": {"core_hp": 0.05}, "desc": "+5% Core max HP"},
	"d_regen":  {"tree": "defense", "name": "Regen", "base": 40.0, "growth": 1.40, "cap": 20, "step": {"regen": 0.10}, "desc": "+10% Core regen"},
	"d_armor":  {"tree": "defense", "name": "Armor", "base": 50.0, "growth": 1.45, "cap": 15, "step": {"armor": 1.0}, "desc": "+1 armor (flat off every hit)"},
	"d_dr":     {"tree": "defense", "name": "Damage Reduction", "base": 60.0, "growth": 1.45, "cap": 20, "step": {"dr": 0.01}, "desc": "-1% damage taken (60% cap)"},
	"d_shield": {"tree": "defense", "name": "Shield", "base": 60.0, "growth": 1.45, "cap": 15, "step": {"shield": 20.0}, "desc": "+20 shield, +2 shield regen"},
	"d_thorns": {"tree": "defense", "name": "Thorns", "base": 50.0, "growth": 1.42, "cap": 15, "step": {"reflect": 0.05}, "desc": "Reflect +5% of Core hits to the attacker", "unlock": ["enh_theory", 3]},
	"d_steal":  {"tree": "defense", "name": "Lifesteal", "base": 70.0, "growth": 1.50, "cap": 10, "step": {"lifesteal": 0.002}, "desc": "+0.2% of damage dealt heals the Core", "unlock": ["enh_theory", 1]},
	"d_knock":  {"tree": "defense", "name": "Knockback", "base": 40.0, "growth": 1.40, "cap": 10, "step": {"knock": 0.10}, "desc": "+10% Weapon knockback"},
	"d_slow":   {"tree": "defense", "name": "Frost Rounds", "base": 50.0, "growth": 1.45, "cap": 10, "step": {"slow_hit": 0.03}, "desc": "Weapon hits slow bodies +3%"},
	"d_last":   {"tree": "defense", "name": "Last Stand", "base": 400.0, "growth": 3.0, "cap": 1, "step": {"last_stand": 1.0}, "desc": "Below 30% HP: 2 s immunity, once per wave", "unlock": ["enh_theory", 2]},
	"armor":    {"tree": "defense", "name": "Fortress", "od": true, "base": 300.0, "growth": 2.5, "cap": 4, "step": {}, "desc": "+30% HP, +1 regen, +2 armor", "minus": "-9% Core damage"},
	# ---- Economy ---------------------------------------------------------
	"e_kill":   {"tree": "economy", "name": "Kill Cash", "base": 40.0, "growth": 1.40, "cap": 20, "step": {"kill_cash": 0.05}, "desc": "+5% kill cash"},
	"e_flow":   {"tree": "economy", "name": "Cash Flow", "base": 40.0, "growth": 1.40, "cap": 20, "step": {"cash": 0.05}, "desc": "+5% cash per second"},
	"e_int":    {"tree": "economy", "name": "Interest", "base": 60.0, "growth": 1.45, "cap": 10, "step": {"interest": 0.005}, "desc": "+0.5% wave interest"},
	"e_icap":   {"tree": "economy", "name": "Interest Cap", "base": 50.0, "growth": 1.42, "cap": 15, "step": {"icap": 0.15}, "desc": "+15% interest cap", "unlock": ["enh_theory", 3]},
	"e_xp":     {"tree": "economy", "name": "XP Gain", "base": 40.0, "growth": 1.40, "cap": 20, "step": {"xp": 0.05}, "desc": "+5% XP (faster drafts)"},
	"e_loot":   {"tree": "economy", "name": "Loot Luck", "base": 120.0, "growth": 1.80, "cap": 5, "step": {"loot_luck": 1.0}, "desc": "+1 luck on the loot this run banks"},
	"e_draft":  {"tree": "economy", "name": "Draft Luck", "base": 120.0, "growth": 1.80, "cap": 5, "step": {"draft_luck": 1.0}, "desc": "+1 draft luck (rarer cards)"},
	"e_free":   {"tree": "economy", "name": "Lucky Purchase", "base": 80.0, "growth": 1.50, "cap": 10, "step": {"free_buy": 0.03}, "desc": "+3% chance an enhancement is free", "unlock": ["enh_theory", 1]},
	"e_scrap":  {"tree": "economy", "name": "Scrap Find", "base": 50.0, "growth": 1.42, "cap": 15, "step": {"scrap_find": 0.10}, "desc": "+10% Scrap from drops", "unlock": ["enh_theory", 2]},
	"e_coin":   {"tree": "economy", "name": "Coin Bonus", "base": 70.0, "growth": 1.50, "cap": 15, "step": {"coin_run": 0.03}, "desc": "+3% coins this run"},
	"eco":      {"tree": "economy", "name": "Eco Engine", "od": true, "base": 300.0, "growth": 2.5, "cap": 4, "step": {}, "desc": "+3 cash/s, interest cap +40", "minus": "-8% Core max HP"},
}

## Display order per tree (standard tracks first, Overdrives last).
const IDS: Array = ["a_dmg", "a_rate", "a_crit", "a_critd", "a_range", "a_multi", "a_pierce", "a_splash", "a_chain", "a_boss", "a_exec", "dmg", "rate", "range",
	"d_hp", "d_regen", "d_armor", "d_dr", "d_shield", "d_thorns", "d_steal", "d_knock", "d_slow", "d_last", "armor",
	"e_kill", "e_flow", "e_int", "e_icap", "e_xp", "e_loot", "e_draft", "e_free", "e_scrap", "e_coin", "eco"]
## The five Overdrive ids (V1 tracks, kept for the trade-offs + Reforge head_start).
const OVERDRIVE: Array = ["dmg", "rate", "range", "eco", "armor"]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func tree_ids(tree: String) -> Array:
	return IDS.filter(func(t: Variant) -> bool: return String((DEFS[t] as Dictionary)["tree"]) == tree)


static func is_od(id: String) -> bool:
	return bool((DEFS.get(id, {}) as Dictionary).get("od", false))


## fx of `lvls` ({id: level}): summed steps.
static func fx_of(lvls: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in lvls.keys():
		var n: int = int(lvls[id])
		if n <= 0 or not DEFS.has(id):
			continue
		var st: Dictionary = (DEFS[id] as Dictionary)["step"]
		for k in st.keys():
			out[k] = float(out.get(k, 0.0)) + float(st[k]) * float(n)
	return out


## "Enhancement Theory II" for a gated track ("" when always open).
static func unlock_label(id: String) -> String:
	var u: Variant = get_def(id).get("unlock", [])
	if not (u is Array) or (u as Array).size() < 2:
		return ""
	var roman: Array = ["", "I", "II", "III", "IV", "V"]
	var lv: int = int(u[1])
	return "%s %s" % ["Enhancement Theory" if String(u[0]) == "enh_theory" else String(u[0]), roman[lv] if lv < roman.size() else str(lv)]
