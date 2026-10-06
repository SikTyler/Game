extends RefCounted
## Gear perks (affixes, V2 P4). A perk is {id, t (tier 1-7), q (quality 0-1),
## lock}; its value = base x TSCALE[t-1] x (0.8 + 0.4 q) (int perks round, min
## 1, capped at `cap`). Every key lands in the run's pfx and is read by
## TowerState.pf() (st_gear checks each key is consumed).
##   key    pfx key            kind  weapon | module | any (rolls on both)
##   fmt    pct | flat | int   w     roll weight (rarer perks are lighter)
##   frames (optional) frames this perk can roll on (frame-specific perks)
## Tier from item level: 1 + ilvl / 25, capped at 7; the Forge and rerolls
## never roll above T5 (T6-T7 are drop-only); masterworks can raise a tier.

const TSCALE: Array = [1.0, 1.5, 2.1, 2.8, 3.6, 4.6, 6.0]
const FORGE_TIER_CAP: int = 5
const MAX_TIER: int = 7

const DEFS: Dictionary = {
	# ---- weapon perks (the Core's attack)
	"w_dmg":       {"name": "Overpressure",   "key": "core_dmg",   "base": 0.06,  "fmt": "pct",  "kind": "weapon", "w": 12, "text": "+%s weapon damage"},
	"w_rate":      {"name": "Rapid Cycler",   "key": "rate",       "base": 0.05,  "fmt": "pct",  "kind": "weapon", "w": 12, "text": "+%s attack rate"},
	"w_range":     {"name": "Long Barrel",    "key": "range",      "base": 0.25,  "fmt": "flat", "kind": "weapon", "w": 10, "text": "+%s range (cells)"},
	"w_crit":      {"name": "Weak Point",     "key": "crit",       "base": 0.03,  "fmt": "pct",  "kind": "weapon", "w": 10, "text": "+%s crit chance"},
	"w_crit_dmg":  {"name": "Hollow Point",   "key": "crit_dmg",   "base": 0.15,  "fmt": "pct",  "kind": "weapon", "w": 9,  "text": "+%s crit damage"},
	"w_pierce":    {"name": "Penetrator",     "key": "pierce",     "base": 1.0,   "fmt": "int",  "kind": "weapon", "w": 7,  "cap": 6, "text": "+%s pierce"},
	"w_splash":    {"name": "Fragmenting",    "key": "splash",     "base": 0.12,  "fmt": "flat", "kind": "weapon", "w": 9,  "text": "+%s splash radius (cells)"},
	"w_chain":     {"name": "Conductive",     "key": "chain",      "base": 1.0,   "fmt": "int",  "kind": "weapon", "w": 6,  "cap": 5, "text": "+%s chain jumps / pulse rings"},
	"w_chain_dmg": {"name": "Overcharge",     "key": "chain_dmg",  "base": 0.08,  "fmt": "pct",  "kind": "weapon", "w": 7,  "text": "+%s chain damage"},
	"w_multishot": {"name": "Twin Feed",      "key": "multishot",  "base": 1.0,   "fmt": "int",  "kind": "weapon", "w": 3,  "cap": 3, "text": "+%s extra shots"},
	"w_bounce":    {"name": "Ricochet",       "key": "bounce",     "base": 1.0,   "fmt": "int",  "kind": "weapon", "w": 4,  "cap": 4, "text": "+%s bounces"},
	"w_burn":      {"name": "Incendiary",     "key": "burn",       "base": 0.08,  "fmt": "pct",  "kind": "weapon", "w": 8,  "text": "ignites: %s of hit damage per second"},
	"w_slow":      {"name": "Cryo Rounds",    "key": "slow_hit",   "base": 0.06,  "fmt": "pct",  "kind": "weapon", "w": 8,  "text": "hits slow %s"},
	"w_knock":     {"name": "Kinetic",        "key": "knock",      "base": 0.15,  "fmt": "pct",  "kind": "weapon", "w": 7,  "text": "+%s knockback"},
	"w_boss":      {"name": "Giant Slayer",   "key": "boss",       "base": 0.08,  "fmt": "pct",  "kind": "weapon", "w": 9,  "text": "+%s damage to elites and bosses"},
	"w_normal":    {"name": "Crowd Breaker",  "key": "normal_dmg", "base": 0.05,  "fmt": "pct",  "kind": "weapon", "w": 9,  "text": "+%s damage to the horde"},
	"w_execute":   {"name": "Executioner",    "key": "execute",    "base": 0.02,  "fmt": "pct",  "kind": "weapon", "w": 4,  "text": "executes non-bosses below %s HP"},
	"w_shred":     {"name": "Serrated",       "key": "shred",      "base": 0.03,  "fmt": "pct",  "kind": "weapon", "w": 7,  "text": "each hit: +%s damage taken (stacks)"},
	"w_echo":      {"name": "Echo",           "key": "echo",       "base": 0.05,  "fmt": "pct",  "kind": "weapon", "w": 4,  "text": "%s chance to fire twice"},
	"w_single":    {"name": "Focus Lens",     "key": "core_single", "base": 0.06, "fmt": "pct",  "kind": "weapon", "w": 8,  "text": "+%s damage to the main target"},
	"w_ramp":      {"name": "Resonator",      "key": "beam_ramp",  "base": 0.10,  "fmt": "pct",  "kind": "weapon", "w": 10, "frames": ["lance"], "text": "+%s beam ramp"},
	"w_pulse":     {"name": "Shockwave",      "key": "pulse_dmg",  "base": 0.10,  "fmt": "pct",  "kind": "weapon", "w": 10, "frames": ["pulse"], "text": "+%s pulse damage"},
	# ---- module / any perks (the Core's body, buildings, economy)
	"m_hp":        {"name": "Plated",         "key": "core_hp",    "base": 0.05,  "fmt": "pct",  "kind": "module", "w": 12, "text": "+%s Core max HP"},
	"m_regen":     {"name": "Nanorepair",     "key": "regen",      "base": 0.08,  "fmt": "pct",  "kind": "module", "w": 10, "text": "+%s Core regen"},
	"m_armor":     {"name": "Reinforced",     "key": "armor",      "base": 0.6,   "fmt": "flat", "kind": "module", "w": 10, "text": "+%s Core armor"},
	"m_shield":    {"name": "Deflector",      "key": "shield",     "base": 12.0,  "fmt": "flat", "kind": "module", "w": 8,  "text": "+%s Core shield"},
	"m_lifesteal": {"name": "Siphon",         "key": "lifesteal",  "base": 0.004, "fmt": "pct",  "kind": "module", "w": 6,  "text": "heals %s of damage dealt"},
	"m_thorns":    {"name": "Thorn Plate",    "key": "reflect",    "base": 0.04,  "fmt": "pct",  "kind": "module", "w": 7,  "text": "reflects %s of contact damage"},
	"m_dr":        {"name": "Dampener",       "key": "dr",         "base": 0.012, "fmt": "pct",  "kind": "module", "w": 7,  "text": "-%s damage taken"},
	"m_kill_cash": {"name": "Bounty Chip",    "key": "kill_cash",  "base": 0.05,  "fmt": "pct",  "kind": "module", "w": 9,  "text": "+%s kill cash"},
	"m_cash":      {"name": "Dividend",       "key": "cash_flat",  "base": 0.3,   "fmt": "flat", "kind": "module", "w": 8,  "text": "+%s cash/s"},
	"m_cash_pct":  {"name": "Treasury Link",  "key": "cash",       "base": 0.04,  "fmt": "pct",  "kind": "module", "w": 8,  "text": "+%s cash/s"},
	"m_interest":  {"name": "Compound",       "key": "interest",   "base": 0.004, "fmt": "pct",  "kind": "module", "w": 6,  "text": "+%s interest"},
	"m_xp":        {"name": "Learning Chip",  "key": "xp",         "base": 0.05,  "fmt": "pct",  "kind": "module", "w": 8,  "text": "+%s run XP"},
	"m_luck":      {"name": "Fortune Chip",   "key": "luck",       "base": 1.0,   "fmt": "int",  "kind": "module", "w": 5,  "cap": 5, "text": "+%s luck"},
	"m_bld_dmg":   {"name": "Fire Control",   "key": "bld_dmg",    "base": 0.05,  "fmt": "pct",  "kind": "module", "w": 9,  "text": "+%s building damage"},
	"m_bld_rate":  {"name": "Servo Link",     "key": "bld_rate",   "base": 0.04,  "fmt": "pct",  "kind": "module", "w": 8,  "text": "+%s building attack rate"},
	"m_troop_dmg": {"name": "Drill Chip",     "key": "troop_dmg",  "base": 0.08,  "fmt": "pct",  "kind": "module", "w": 6,  "text": "+%s troop damage"},
	"m_troop_hp":  {"name": "Medic Chip",     "key": "troop_hp",   "base": 0.08,  "fmt": "pct",  "kind": "module", "w": 6,  "text": "+%s troop HP"},
	"m_special":   {"name": "Ordnance Link",  "key": "special_dmg", "base": 0.10, "fmt": "pct",  "kind": "module", "w": 6,  "text": "+%s special damage"},
	"m_scrap":     {"name": "Salvager",       "key": "scrap_find", "base": 0.06,  "fmt": "pct",  "kind": "module", "w": 7,  "text": "+%s Scrap from runs"},
	"m_coin":      {"name": "Golden Touch",   "key": "coin_run",   "base": 0.03,  "fmt": "pct",  "kind": "module", "w": 7,  "text": "+%s coins from runs"},
	"a_dmg":       {"name": "Empowered",      "key": "dmg",        "base": 0.03,  "fmt": "pct",  "kind": "any",    "w": 10, "text": "+%s all damage"},
	"a_crit":      {"name": "Lucky Strike",   "key": "crit",       "base": 0.02,  "fmt": "pct",  "kind": "any",    "w": 7,  "text": "+%s crit chance (all)"},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


## Value of a perk {id, t, q}.
static func value(id: String, t: int, q: float) -> float:
	var d: Dictionary = DEFS.get(id, {})
	if d.is_empty():
		return 0.0
	var v: float = float(d["base"]) * float(TSCALE[clampi(t, 1, MAX_TIER) - 1]) * (0.8 + 0.4 * clampf(q, 0.0, 1.0))
	if String(d["fmt"]) == "int":
		return float(clampi(int(round(v)), 1, int(d.get("cap", 99))))
	return v


## Display text: "+12% weapon damage".
static func text(id: String, t: int, q: float) -> String:
	var d: Dictionary = DEFS.get(id, {})
	if d.is_empty():
		return id
	var v: float = value(id, t, q)
	var s: String
	match String(d["fmt"]):
		"pct":
			s = ("%.1f%%" % (v * 100.0)) if v * 100.0 < 10.0 else ("%d%%" % int(round(v * 100.0)))
		"int":
			s = str(int(v))
		_:
			s = "%.2f" % v if v < 10.0 else str(int(round(v)))
	return String(d["text"]) % s


## Perk ids that may roll on an item of `kind` (and `frame`, for weapons).
static func pool(kind: String, frame: String = "") -> Array:
	var out: Array = []
	for id in DEFS.keys():
		var d: Dictionary = DEFS[id]
		var k: String = String(d["kind"])
		if k != "any" and k != kind:
			continue
		if d.has("frames") and not (d["frames"] as Array).has(frame):
			continue
		out.append(id)
	out.sort()
	return out


## Tier a roll gets from an item level (capped for Forge / reroll sources).
static func tier_for(ilvl: int, cap: int = MAX_TIER) -> int:
	return clampi(1 + ilvl / 25, 1, mini(cap, MAX_TIER))
