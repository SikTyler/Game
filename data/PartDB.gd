extends RefCounted
## V3 parts (design/V3_PARTS.md): the Weapon (attack) and the Core (defense /
## economy) are assemblies of typed parts. A part's slot says what it does:
## the chassis (Receiver / Heart) sets the layout by its rarity, a Barrel is
## the firing archetype, the rest add fx. Perks roll from AffixDB on every
## part, each with its own rarity tier.
##   slot     one of SLOTS
##   name     base name ("Minigun Barrel")
##   fx       pfx keys at L1 Common (scaled by Parts.power; negatives never scale)
##   frame    Barrels only: the FrameDB / attack sheet it fires (+ "minigun")
##   dmg_k / rate_k   Receivers: weapon damage / rate scale
##   hp_k / regen_k   Hearts: Core max HP / regen scale
##   look     PartVis variant index (silhouette)
##   w        drop weight within its slot

const SLOTS: Dictionary = {
	"receiver":  {"side": "weapon", "name": "Receiver", "chassis": true, "w": 10},
	"barrel":    {"side": "weapon", "name": "Barrel", "w": 16},
	"ammo":      {"side": "weapon", "name": "Ammo", "w": 14},
	"scope":     {"side": "weapon", "name": "Scope", "w": 11},
	"power":     {"side": "weapon", "name": "Power Cell", "w": 9},
	"mag":       {"side": "weapon", "name": "Magazine", "w": 7},
	"heart":     {"side": "core", "name": "Heart", "chassis": true, "w": 10},
	"plating":   {"side": "core", "name": "Plating", "w": 14},
	"generator": {"side": "core", "name": "Generator", "w": 12},
	"capacitor": {"side": "core", "name": "Capacitor", "w": 10},
	"reactor":   {"side": "core", "name": "Reactor", "w": 9},
	"antenna":   {"side": "core", "name": "Antenna", "w": 8},
	"emitter":   {"side": "core", "name": "Shield Emitter", "w": 7},
}
const WEAPON_SLOTS: Array = ["receiver", "barrel", "ammo", "scope", "power", "mag"]
const CORE_SLOTS: Array = ["heart", "plating", "generator", "capacitor", "reactor", "antenna", "emitter"]

## Chassis layouts by rarity: slot -> how many of it the assembly holds.
const RECEIVER_LAYOUT: Dictionary = {
	"common":    {"barrel": 1, "ammo": 1},
	"uncommon":  {"barrel": 1, "ammo": 1, "scope": 1},
	"rare":      {"barrel": 1, "ammo": 1, "scope": 1, "power": 1},
	"epic":      {"barrel": 1, "ammo": 1, "scope": 1, "power": 1, "mag": 1},
	"legendary": {"barrel": 2, "ammo": 1, "scope": 1, "power": 1, "mag": 1},
	"mythic":    {"barrel": 3, "ammo": 1, "scope": 1, "power": 1, "mag": 1},
	"exotic":    {"barrel": 4, "ammo": 1, "scope": 1, "power": 1, "mag": 1},
}
const HEART_LAYOUT: Dictionary = {
	"common":    {"plating": 1, "generator": 1},
	"uncommon":  {"plating": 1, "generator": 1, "capacitor": 1},
	"rare":      {"plating": 1, "generator": 1, "capacitor": 1, "reactor": 1},
	"epic":      {"plating": 1, "generator": 1, "capacitor": 1, "reactor": 1, "antenna": 1},
	"legendary": {"plating": 2, "generator": 1, "capacitor": 1, "reactor": 1, "antenna": 1, "emitter": 1},
	"mythic":    {"plating": 2, "generator": 1, "capacitor": 1, "reactor": 1, "antenna": 1, "emitter": 1},
	"exotic":    {"plating": 2, "generator": 2, "capacitor": 1, "reactor": 1, "antenna": 1, "emitter": 1},
}
## Perk slots a part has, by its rarity.
const PERK_SLOTS: Dictionary = {"common": 1, "uncommon": 1, "rare": 2, "epic": 2, "legendary": 3, "mythic": 3, "exotic": 4}

const BASES: Dictionary = {
	# ---- Receivers (weapon chassis)
	"rcv_standard": {"slot": "receiver", "name": "Standard Receiver", "dmg_k": 1.0, "rate_k": 1.0, "fx": {}, "look": 0, "w": 10, "desc": "Balanced frame"},
	"rcv_heavy":    {"slot": "receiver", "name": "Heavy Receiver", "dmg_k": 1.2, "rate_k": 0.85, "fx": {}, "look": 1, "w": 8, "desc": "Hits harder, cycles slower"},
	"rcv_rapid":    {"slot": "receiver", "name": "Rapid Receiver", "dmg_k": 0.85, "rate_k": 1.2, "fx": {}, "look": 2, "w": 8, "desc": "Cycles faster, hits lighter"},
	"rcv_precise":  {"slot": "receiver", "name": "Precision Receiver", "dmg_k": 1.0, "rate_k": 0.95, "fx": {"crit": 0.05}, "look": 3, "w": 6, "desc": "Steady frame: +crit"},
	# ---- Barrels (the archetype: how the Weapon fires)
	"brl_autocannon": {"slot": "barrel", "name": "Autocannon Barrel", "frame": "autocannon", "fx": {}, "look": 0, "w": 12},
	"brl_minigun":    {"slot": "barrel", "name": "Minigun Barrel", "frame": "minigun", "fx": {}, "look": 1, "w": 10},
	"brl_sniper":     {"slot": "barrel", "name": "Sniper Rail", "frame": "rail", "fx": {}, "look": 2, "w": 8},
	"brl_blast":      {"slot": "barrel", "name": "Blast Emitter", "frame": "pulse", "fx": {}, "look": 3, "w": 8},
	"brl_scatter":    {"slot": "barrel", "name": "Scattergun Barrel", "frame": "scatter", "fx": {}, "look": 4, "w": 9},
	"brl_lobber":     {"slot": "barrel", "name": "Slag Lobber", "frame": "slag", "fx": {}, "look": 5, "w": 8},
	"brl_arc":        {"slot": "barrel", "name": "Arc Coil", "frame": "arc", "fx": {}, "look": 6, "w": 7},
	"brl_flame":      {"slot": "barrel", "name": "Flame Nozzle", "frame": "flame", "fx": {}, "look": 7, "w": 8},
	"brl_missile":    {"slot": "barrel", "name": "Missile Rack", "frame": "missiles", "fx": {}, "look": 8, "w": 7},
	"brl_saw":        {"slot": "barrel", "name": "Saw Launcher", "frame": "saw", "fx": {}, "look": 9, "w": 7},
	"brl_lance":      {"slot": "barrel", "name": "Lance Emitter", "frame": "lance", "fx": {}, "look": 10, "w": 6},
	# ---- Ammo (on-hit effects)
	"amm_standard":   {"slot": "ammo", "name": "Standard Rounds", "fx": {"core_dmg": 0.10}, "look": 0, "w": 10},
	"amm_incendiary": {"slot": "ammo", "name": "Incendiary Rounds", "fx": {"burn": 0.12}, "look": 1, "w": 9},
	"amm_toxic":      {"slot": "ammo", "name": "Toxic Rounds", "fx": {"burn": 0.08, "shred": 0.02}, "look": 2, "w": 8},
	"amm_ap":         {"slot": "ammo", "name": "Armor-Piercing Rounds", "fx": {"pierce": 1.0, "shred": 0.02}, "look": 3, "w": 8},
	"amm_explosive":  {"slot": "ammo", "name": "Explosive Rounds", "fx": {"splash": 0.25}, "look": 4, "w": 8},
	"amm_cryo":       {"slot": "ammo", "name": "Cryo Rounds", "fx": {"slow_hit": 0.10}, "look": 5, "w": 7},
	"amm_shock":      {"slot": "ammo", "name": "Shock Rounds", "fx": {"chain": 1.0}, "look": 6, "w": 7},
	"amm_hollow":     {"slot": "ammo", "name": "Hollow Points", "fx": {"crit_dmg": 0.30}, "look": 7, "w": 7},
	# ---- Scopes
	"scp_long":    {"slot": "scope", "name": "Long Optic", "fx": {"range": 0.5}, "look": 0, "w": 10},
	"scp_reddot":  {"slot": "scope", "name": "Red Dot", "fx": {"crit": 0.06}, "look": 1, "w": 10},
	"scp_hunter":  {"slot": "scope", "name": "Hunter Sight", "fx": {"boss": 0.20}, "look": 2, "w": 8},
	"scp_thermal": {"slot": "scope", "name": "Thermal Scope", "fx": {"range": 0.25, "crit": 0.03}, "look": 3, "w": 8},
	# ---- Power cells
	"pow_overclock": {"slot": "power", "name": "Overclock Cell", "fx": {"rate": 0.15}, "look": 0, "w": 10},
	"pow_dense":     {"slot": "power", "name": "Dense Cell", "fx": {"core_dmg": 0.15}, "look": 1, "w": 10},
	"pow_surge":     {"slot": "power", "name": "Surge Cell", "fx": {"rate": 0.15, "core_dmg": 0.10, "core_hp": -0.10}, "look": 2, "w": 7},
	"pow_capbank":   {"slot": "power", "name": "Capacitor Bank", "fx": {"core_single": 0.20, "echo": 0.06}, "look": 3, "w": 7},
	# ---- Magazines
	"mag_drum":  {"slot": "mag", "name": "Drum Magazine", "fx": {"rate": 0.10}, "look": 0, "w": 10},
	"mag_echo":  {"slot": "mag", "name": "Echo Chamber", "fx": {"echo": 0.10}, "look": 1, "w": 8},
	"mag_quick": {"slot": "mag", "name": "Quickload Mag", "fx": {"rate": 0.06, "core_dmg": 0.05}, "look": 2, "w": 9},
	# ---- Hearts (Core chassis)
	"hrt_standard": {"slot": "heart", "name": "Standard Heart", "hp_k": 1.0, "regen_k": 1.0, "fx": {}, "look": 0, "w": 10, "desc": "Balanced core"},
	"hrt_fortress": {"slot": "heart", "name": "Fortress Heart", "hp_k": 1.25, "regen_k": 0.8, "fx": {}, "look": 1, "w": 8, "desc": "More HP, slower repairs"},
	"hrt_dynamo":   {"slot": "heart", "name": "Dynamo Heart", "hp_k": 0.9, "regen_k": 1.35, "fx": {}, "look": 2, "w": 8, "desc": "Fast repairs, less HP"},
	"hrt_merchant": {"slot": "heart", "name": "Merchant Heart", "hp_k": 0.9, "regen_k": 1.0, "fx": {"kill_cash": 0.10}, "look": 3, "w": 6, "desc": "Trades HP for cash"},
	# ---- Plating (HP / armor / thorns)
	"plt_basic":     {"slot": "plating", "name": "Steel Plating", "fx": {"core_hp": 0.10}, "look": 0, "w": 10},
	"plt_composite": {"slot": "plating", "name": "Composite Plating", "fx": {"core_hp": 0.05, "armor": 1.0}, "look": 1, "w": 8},
	"plt_spiked":    {"slot": "plating", "name": "Spiked Plating", "fx": {"core_hp": 0.04, "reflect": 0.06}, "look": 2, "w": 7},
	"plt_reactive":  {"slot": "plating", "name": "Reactive Plating", "fx": {"dr": 0.03}, "look": 3, "w": 7},
	# ---- Generators (regen / shield)
	"gen_basic":  {"slot": "generator", "name": "Repair Generator", "fx": {"regen": 0.15}, "look": 0, "w": 10},
	"gen_shield": {"slot": "generator", "name": "Shield Generator", "fx": {"shield": 25.0}, "look": 1, "w": 8},
	"gen_leech":  {"slot": "generator", "name": "Leech Generator", "fx": {"lifesteal": 0.002}, "look": 2, "w": 6},
	# ---- Capacitors (economy: cash)
	"cap_basic":  {"slot": "capacitor", "name": "Cash Capacitor", "fx": {"cash": 0.10}, "look": 0, "w": 10},
	"cap_bank":   {"slot": "capacitor", "name": "Bank Capacitor", "fx": {"interest": 0.005, "icap": 0.15}, "look": 1, "w": 8},
	"cap_bounty": {"slot": "capacitor", "name": "Bounty Capacitor", "fx": {"kill_cash": 0.12}, "look": 2, "w": 8},
	# ---- Reactors (economy: XP / coins / run cash)
	"rct_xp":   {"slot": "reactor", "name": "Study Reactor", "fx": {"xp": 0.06}, "look": 0, "w": 9},
	"rct_coin": {"slot": "reactor", "name": "Mint Reactor", "fx": {"coin_run": 0.06}, "look": 1, "w": 9},
	"rct_run":  {"slot": "reactor", "name": "Field Reactor", "fx": {"run_cash": 0.08}, "look": 2, "w": 8},
	# ---- Antennas (loot)
	"ant_scrap": {"slot": "antenna", "name": "Salvage Antenna", "fx": {"scrap_find": 0.15}, "look": 0, "w": 10},
	"ant_luck":  {"slot": "antenna", "name": "Fortune Antenna", "fx": {"loot_luck": 1.0}, "look": 1, "w": 8},
	"ant_draft": {"slot": "antenna", "name": "Scout Antenna", "fx": {"draft_luck": 1.0}, "look": 2, "w": 7},
	# ---- Shield emitters
	"emi_dome":   {"slot": "emitter", "name": "Dome Emitter", "fx": {"shield": 40.0}, "look": 0, "w": 10},
	"emi_damper": {"slot": "emitter", "name": "Damper Emitter", "fx": {"dr": 0.04}, "look": 1, "w": 8},
}

## Count-valued fx keys (stay whole; +1 per 2 masterworks instead of power).
const INT_KEYS: Array = ["pierce", "chain", "bounce", "loot_luck", "draft_luck"]
## Perk ids parts never roll (V2 P10 owner: "remove multishot").
const NO_PERKS: Array = ["w_multishot"]


static func has(base: String) -> bool:
	return BASES.has(base)


static func get_def(base: String) -> Dictionary:
	return BASES.get(base, {})


static func slot_of(base: String) -> String:
	return String((BASES.get(base, {}) as Dictionary).get("slot", ""))


static func side_of(slot: String) -> String:
	return String((SLOTS.get(slot, {}) as Dictionary).get("side", ""))


static func is_chassis(slot: String) -> bool:
	return bool((SLOTS.get(slot, {}) as Dictionary).get("chassis", false))


## Bases of a slot, in table order.
static func bases_of(slot: String) -> Array:
	var out: Array = []
	for k in BASES.keys():
		if String((BASES[k] as Dictionary)["slot"]) == slot:
			out.append(k)
	return out


## The slot layout a chassis of rarity `rar` opens (Receiver or Heart).
static func layout(chassis_slot: String, rar: String) -> Dictionary:
	var t: Dictionary = RECEIVER_LAYOUT if chassis_slot == "receiver" else HEART_LAYOUT
	return t.get(rar, t["common"])
