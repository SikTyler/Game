extends RefCounted
## Roguelite draft content (REDESIGN_SPEC §2.3, SYSTEMS §2.3-2.7). Every
## in-run building, pack, special, troop hut and Insight pick. The run grid
## starts empty except for the Core, so everything on it comes from here.
##   fam: building | pack | special | hut | insight
##   rarity: common | rare | epic | legendary | insight
##   tags: eco dps aoe control troop special sustain (synergy chips + filter)
##   max: building/hut level cap (L5) or pack/special stack cap
## Building and hut stats live in TowerState.compute_stats (one owner of the
## math); this table is identity + display text + draft weights.

const RARITIES: Array = ["common", "rare", "epic", "legendary"]
const RARITY_W: Dictionary = {"common": 60.0, "rare": 28.0, "epic": 10.0, "legendary": 2.0}
const BUILDING_MAX: int = 5
const HUT_MAX: int = 3          # huts on the grid per run
const SPECIAL_SLOTS: int = 4
const SPECIAL_COPIES: int = 3

const DEFS: Dictionary = {
	# ---- buildings (17; the 15 "adapted" ids keep their art) ----------------
	"gun":       {"fam": "building", "name": "Gatling", "rarity": "common", "tags": ["dps"], "max": 5, "desc": "6 dmg, 2.0/s, range 3"},
	"mortar":    {"fam": "building", "name": "Mortar", "rarity": "common", "tags": ["aoe", "dps"], "max": 5, "desc": "18 dmg, 0.4/s, range 4.5, 1-cell splash (min range 1.5)"},
	"tesla":     {"fam": "building", "name": "Tesla Coil", "rarity": "rare", "tags": ["aoe", "control"], "max": 5, "desc": "9 dmg, 0.8/s, chains 3 at 70%"},
	"flak":      {"fam": "building", "name": "Flak", "rarity": "common", "tags": ["dps"], "max": 5, "desc": "8 dmg, 1.5/s, x2.5 vs flyers; cannot hit ground"},
	"railgun":   {"fam": "building", "name": "Railgun", "rarity": "epic", "tags": ["dps"], "max": 5, "desc": "60 dmg, 0.25/s, pierces a line (range 7); ring 2+"},
	"armory":    {"fam": "building", "name": "Armory", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Adjacent buildings +15% dmg"},
	"beacon":    {"fam": "building", "name": "Beacon", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Radius 2: +10% rate, +0.3 range"},
	"bulwark":   {"fam": "building", "name": "Bulwark", "rarity": "common", "tags": ["sustain"], "max": 5, "desc": "Core +40 HP"},
	"aegis":     {"fam": "building", "name": "Aegis", "rarity": "epic", "tags": ["sustain"], "max": 5, "desc": "60-pt Core shield; regen 6/s after 4 s without damage"},
	"barricade": {"fam": "building", "name": "Barricade", "rarity": "common", "tags": ["control"], "max": 5, "desc": "High-HP wall; every enemy within 1.5 cells (any side) is slowed 30%"},
	"mine":      {"fam": "building", "name": "Gold Mine", "rarity": "common", "tags": ["eco"], "max": 5, "desc": "+0.8 cash/s"},
	"oilmill":   {"fam": "building", "name": "Oil Mill", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "+2.0 cash/s; adjacent buildings -10% rate"},
	"bounty":    {"fam": "building", "name": "Bounty Post", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "+20% kill cash within 3 cells"},
	"vault":     {"fam": "building", "name": "Vault", "rarity": "epic", "tags": ["eco"], "max": 5, "desc": "+2% interest, +100 interest cap"},
	"refinery":  {"fam": "building", "name": "Refinery", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "+15% XP (each level-up = a free reroll), +0.5 cash/s"},
	"frost":     {"fam": "building", "name": "Cryo Spire", "rarity": "rare", "tags": ["control"], "max": 5, "desc": "Slows 30% within 2.5 cells, 3 dmg/s"},
	"obelisk":   {"fam": "building", "name": "Siphon Obelisk", "rarity": "legendary", "tags": ["sustain"], "max": 5, "desc": "1% of all damage dealt heals the Core"},
	# ---- troop huts (3) ------------------------------------------------------
	"hut_infantry": {"fam": "hut", "name": "Rifle Barracks", "rarity": "common", "tags": ["troop"], "max": 5, "desc": "3 Riflemen guard the whole perimeter from their post; they taunt nearby enemies"},
	"hut_sapper":   {"fam": "hut", "name": "Sapper Den", "rarity": "rare", "tags": ["troop", "aoe"], "max": 5, "desc": "2 Sappers charge elites and bosses first and explode (x2 vs armored)"},
	"hut_drone":    {"fam": "hut", "name": "Drone Nest", "rarity": "epic", "tags": ["troop"], "max": 5, "desc": "4 Drones fly out and hunt flyers first"},
	# ---- upgrade packs (10; one-shot, last the run) --------------------------
	"pk_arsenal":   {"fam": "pack", "name": "Arsenal Pack", "rarity": "common", "tags": ["dps"], "max": 5, "desc": "+12% dmg (all)"},
	"pk_overclock": {"fam": "pack", "name": "Overclock Pack", "rarity": "common", "tags": ["dps"], "max": 3, "desc": "+8% rate (all), -5% Core HP"},
	"pk_fort":      {"fam": "pack", "name": "Fortify Pack", "rarity": "common", "tags": ["sustain"], "max": 3, "desc": "+20% Core HP, +1 armor"},
	"pk_ledger":    {"fam": "pack", "name": "Ledger Pack", "rarity": "common", "tags": ["eco"], "max": 5, "desc": "+0.6 cash/s, +5% kill cash"},
	"pk_optics":    {"fam": "pack", "name": "Optics Pack", "rarity": "rare", "tags": ["dps"], "max": 2, "desc": "+0.5 range (all)"},
	"pk_crit":      {"fam": "pack", "name": "Precision Pack", "rarity": "rare", "tags": ["dps"], "max": 3, "desc": "+8% crit chance (crit x2)"},
	"pk_logistics": {"fam": "pack", "name": "Logistics Pack", "rarity": "rare", "tags": ["eco"], "max": 3, "desc": "Core cash tracks -12% cost"},
	"pk_core":      {"fam": "pack", "name": "Core Surge", "rarity": "epic", "tags": ["dps"], "max": 2, "desc": "Core attack +15% dmg, +5% rate"},
	"pk_barracks":  {"fam": "pack", "name": "Drill Sergeant", "rarity": "rare", "tags": ["troop"], "max": 3, "desc": "Troops +25% HP and dmg, -2 s respawn"},
	"pk_gambit":    {"fam": "pack", "name": "Gambit", "rarity": "legendary", "tags": ["dps"], "max": 1, "desc": "+40% dmg (all), enemies +15% HP"},
	# ---- specials (6; hotkeys 1-4; Napalm Line cut, §9) ---------------------
	"sp_orbital":   {"fam": "special", "name": "Orbital Strike", "rarity": "rare", "tags": ["special", "aoe"], "max": 3, "desc": "Target a 1.5-cell circle: 25x Core dmg after 0.8 s", "cd": 30.0},
	"sp_emp":       {"fam": "special", "name": "EMP Burst", "rarity": "rare", "tags": ["special", "control"], "max": 3, "desc": "All enemies -50% speed for 4 s; shields stripped", "cd": 25.0},
	"sp_repair":    {"fam": "special", "name": "Repair Pulse", "rarity": "common", "tags": ["special", "sustain"], "max": 3, "desc": "Heal the Core 35% max HP over 3 s", "cd": 40.0},
	"sp_overdrive": {"fam": "special", "name": "Overdrive", "rarity": "rare", "tags": ["special", "dps"], "max": 3, "desc": "Core rate x2 for 6 s", "cd": 45.0},
	"sp_magnet":    {"fam": "special", "name": "Cash Magnet", "rarity": "common", "tags": ["special", "eco"], "max": 3, "desc": "Kills give x2 cash for 10 s", "cd": 60.0},
	"sp_timewarp":  {"fam": "special", "name": "Time Warp", "rarity": "legendary", "tags": ["special", "control"], "max": 3, "desc": "Enemies frozen for 3 s", "cd": 90.0},
	# ---- Insight (7; super-rare, banked permanently at run end) -------------
	"in_dmg":   {"fam": "insight", "name": "Insight: Force", "rarity": "insight", "tags": [], "step": 0.005, "cap": 0.25, "desc": "+0.5% all dmg, permanently (cap 25%)"},
	"in_hp":    {"fam": "insight", "name": "Insight: Bulwark", "rarity": "insight", "tags": [], "step": 0.005, "cap": 0.25, "desc": "+0.5% Core HP, permanently (cap 25%)"},
	"in_cash":  {"fam": "insight", "name": "Insight: Ledger", "rarity": "insight", "tags": [], "step": 0.005, "cap": 0.20, "desc": "+0.5% cash/s and kill cash, permanently (cap 20%)"},
	"in_rate":  {"fam": "insight", "name": "Insight: Tempo", "rarity": "insight", "tags": [], "step": 0.003, "cap": 0.10, "desc": "+0.3% attack rate, permanently (cap 10%)"},
	"in_luck":  {"fam": "insight", "name": "Insight: Fortune", "rarity": "insight", "tags": [], "step": 1.0, "cap": 10.0, "desc": "+1 draft Luck, permanently (cap 10)"},
	"in_drop":  {"fam": "insight", "name": "Insight: Scavenger", "rarity": "insight", "tags": [], "step": 0.01, "cap": 0.15, "desc": "+1% part drop chance, permanently (cap 15%)"},
	"in_crate": {"fam": "insight", "name": "Insight: Appraiser", "rarity": "insight", "tags": [], "step": 0.005, "cap": 0.10, "desc": "+0.5% crate Epic+ odds, permanently (cap 10%)"},
}

const BUILDINGS: Array = ["gun", "mortar", "tesla", "flak", "railgun", "armory", "beacon", "bulwark", "aegis", "barricade", "mine", "oilmill", "bounty", "vault", "refinery", "frost", "obelisk"]
const HUTS: Array = ["hut_infantry", "hut_sapper", "hut_drone"]
const PACKS: Array = ["pk_arsenal", "pk_overclock", "pk_fort", "pk_ledger", "pk_optics", "pk_crit", "pk_logistics", "pk_core", "pk_barracks", "pk_gambit"]
const SPECIALS: Array = ["sp_orbital", "sp_emp", "sp_repair", "sp_overdrive", "sp_magnet", "sp_timewarp"]
const INSIGHT: Array = ["in_dmg", "in_hp", "in_cash", "in_rate", "in_luck", "in_drop", "in_crate"]


static func ids() -> Array:
	return BUILDINGS + HUTS + PACKS + SPECIALS


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func fam_of(id: String) -> String:
	return String((DEFS.get(id, {}) as Dictionary).get("fam", ""))


static func rarity_of(id: String) -> String:
	return String((DEFS.get(id, {}) as Dictionary).get("rarity", "common"))


static func tags_of(id: String) -> Array:
	return (DEFS.get(id, {}) as Dictionary).get("tags", [])


static func is_eco(id: String) -> bool:
	return tags_of(id).has("eco")


## Things that occupy a grid cell (buildings + huts).
static func is_placeable(id: String) -> bool:
	var f: String = fam_of(id)
	return f == "building" or f == "hut"


static func max_of(id: String) -> int:
	return int((DEFS.get(id, {}) as Dictionary).get("max", 1))


# ----------------------------------------------------------- Insight (meta)
## save.insight = {id: picks banked}. Value = picks * step, capped per stat.
static func insight_value(save: Dictionary, id: String) -> float:
	var d: Dictionary = DEFS.get(id, {})
	var ins: Variant = save.get("insight", {})
	var n: int = int((ins as Dictionary).get(id, 0)) if ins is Dictionary else 0
	return minf(float(d.get("cap", 0.0)), float(n) * float(d.get("step", 0.0)))


static func insight_capped(save: Dictionary, id: String) -> bool:
	var d: Dictionary = DEFS.get(id, {})
	return insight_value(save, id) >= float(d.get("cap", 0.0)) - 0.000001


static func normalize_insight(raw: Variant) -> Dictionary:
	var o: Dictionary = {}
	if raw is Dictionary:
		for id in INSIGHT:
			var d: Dictionary = DEFS[id]
			var mx: int = int(ceil(float(d["cap"]) / float(d["step"]) - 0.0001))
			var n: int = clampi(int((raw as Dictionary).get(id, 0)), 0, mx)
			if n > 0:
				o[id] = n
	return o


## Bank this run's Insight finds (win or loss); lifetime caps hold.
static func bank_insight(save: Dictionary, found: Array) -> Array:
	var ev: Array = []
	if not (save.get("insight", null) is Dictionary):
		save["insight"] = {}
	var ins: Dictionary = save["insight"]
	for v in found:
		var id: String = String(v)
		if not INSIGHT.has(id) or insight_capped(save, id):
			continue
		ins[id] = int(ins.get(id, 0)) + 1
		ev.append({"t": "insight_banked", "id": id, "value": insight_value(save, id)})
	return ev
