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
	"muzzle":    {"side": "weapon", "name": "Muzzle", "w": 8},
	"heart":     {"side": "core", "name": "Heart", "chassis": true, "w": 10},
	"plating":   {"side": "core", "name": "Plating", "w": 14},
	"generator": {"side": "core", "name": "Generator", "w": 12},
	"capacitor": {"side": "core", "name": "Capacitor", "w": 10},
	"reactor":   {"side": "core", "name": "Reactor", "w": 9},
	"antenna":   {"side": "core", "name": "Antenna", "w": 8},
	"emitter":   {"side": "core", "name": "Shield Emitter", "w": 7},
	"uplink":    {"side": "core", "name": "Uplink", "w": 8},
}
const WEAPON_SLOTS: Array = ["receiver", "barrel", "ammo", "scope", "power", "muzzle", "mag"]
const CORE_SLOTS: Array = ["heart", "plating", "generator", "capacitor", "reactor", "uplink", "antenna", "emitter"]

## Chassis layouts by rarity: slot -> how many of it the assembly holds.
const RECEIVER_LAYOUT: Dictionary = {
	"common":    {"barrel": 1, "ammo": 1},
	"uncommon":  {"barrel": 1, "ammo": 1, "scope": 1},
	"rare":      {"barrel": 1, "ammo": 1, "scope": 1, "power": 1, "muzzle": 1},
	"epic":      {"barrel": 1, "ammo": 1, "scope": 1, "power": 1, "muzzle": 1, "mag": 1},
	"legendary": {"barrel": 2, "ammo": 1, "scope": 1, "power": 1, "muzzle": 1, "mag": 1},
	"mythic":    {"barrel": 3, "ammo": 1, "scope": 1, "power": 1, "muzzle": 1, "mag": 1},
	"exotic":    {"barrel": 4, "ammo": 2, "scope": 1, "power": 1, "muzzle": 1, "mag": 1},
}
const HEART_LAYOUT: Dictionary = {
	"common":    {"plating": 1, "generator": 1},
	"uncommon":  {"plating": 1, "generator": 1, "capacitor": 1},
	"rare":      {"plating": 1, "generator": 1, "capacitor": 1, "reactor": 1, "uplink": 1},
	"epic":      {"plating": 1, "generator": 1, "capacitor": 1, "reactor": 1, "uplink": 1, "antenna": 1},
	"legendary": {"plating": 2, "generator": 1, "capacitor": 1, "reactor": 1, "uplink": 1, "antenna": 1, "emitter": 1},
	"mythic":    {"plating": 2, "generator": 2, "capacitor": 1, "reactor": 1, "uplink": 1, "antenna": 1, "emitter": 1},
	"exotic":    {"plating": 2, "generator": 2, "capacitor": 1, "reactor": 1, "uplink": 2, "antenna": 1, "emitter": 1},
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
	"brl_minigun":    {"slot": "barrel", "name": "Minigun Barrel", "frame": "minigun", "desc": "Six light rounds a second, each at a random body among the nearest three", "fx": {}, "look": 1, "w": 10},
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
	"emi_thorns": {"slot": "emitter", "name": "Thorn Field", "fx": {"reflect": 0.10}, "look": 2, "w": 7},
	"emi_stasis": {"slot": "emitter", "name": "Stasis Field", "fx": {"slow_hit": 0.08, "shield": 15.0}, "look": 3, "w": 6},
	# ---- V3 expansion (owner: "use your determination for additional weapon
	# types, part types, parts, effects"). Barrel variants re-tune a frame's
	# sheet: dmg_k / rate_k / range_k multiply, other keys override params.
	"rcv_burst":    {"slot": "receiver", "name": "Burst Receiver", "dmg_k": 0.9, "rate_k": 1.0, "fx": {"echo": 0.08}, "look": 4, "w": 6, "desc": "Every volley may fire twice"},
	"rcv_siege":    {"slot": "receiver", "name": "Siege Receiver", "dmg_k": 1.35, "rate_k": 0.75, "fx": {"range": 0.4}, "look": 5, "w": 5, "desc": "Slow, heavy and long-reaching"},
	"rcv_overdrive": {"slot": "receiver", "name": "Overdrive Receiver", "dmg_k": 1.1, "rate_k": 1.1, "fx": {"core_hp": -0.08}, "look": 6, "w": 4, "desc": "Faster and harder, at the Core's expense"},
	"brl_mortar":   {"slot": "barrel", "name": "Siege Mortar", "frame": "slag", "sheet": {"dmg_k": 3.2, "rate_k": 0.35, "range_k": 1.6, "splash": 1.8, "slow": 0.0}, "desc": "Huge, slow shells that crater a wide area at long range", "fx": {}, "look": 11, "w": 6},
	"brl_burst":    {"slot": "barrel", "name": "Burst Carbine", "frame": "autocannon", "sheet": {"dmg_k": 0.45, "rate_k": 1.0, "barrels": 3, "splash": 0.0}, "desc": "Three-round bursts at the nearest bodies", "fx": {}, "look": 12, "w": 8},
	"brl_flechette": {"slot": "barrel", "name": "Flechette Gun", "frame": "scatter", "sheet": {"dmg_k": 0.6, "pellets": 10, "cone": 30.0, "range_k": 1.15}, "desc": "Ten piercing darts in a tight cone", "fx": {"pierce": 1.0}, "look": 13, "w": 7},
	"brl_coil":     {"slot": "barrel", "name": "Coilgun", "frame": "rail", "sheet": {"dmg_k": 0.45, "rate_k": 2.6, "range_k": 0.75, "pierce": 4.0}, "desc": "Rapid magnetic slugs that pierce four bodies", "fx": {}, "look": 14, "w": 7},
	"brl_storm":    {"slot": "barrel", "name": "Storm Coil", "frame": "arc", "sheet": {"dmg_k": 0.6, "chain": 9, "chain_frac": 0.85}, "desc": "Weak lightning that jumps through nine bodies", "fx": {}, "look": 15, "w": 6},
	"brl_plasma":   {"slot": "barrel", "name": "Plasma Caster", "frame": "autocannon", "sheet": {"dmg_k": 2.4, "rate_k": 0.45, "splash": 1.2, "splash_frac": 0.6}, "desc": "Slow, heavy plasma bolts with a big burning blast", "fx": {"burn": 0.05}, "look": 16, "w": 6},
	"brl_frost":    {"slot": "barrel", "name": "Frost Projector", "frame": "flame", "sheet": {"dmg_k": 0.7, "flame_burn": 0.0}, "desc": "A cone of frost that slows what it touches (no burn)", "fx": {"slow_hit": 0.12}, "look": 17, "w": 6},
	"brl_quake":    {"slot": "barrel", "name": "Quake Hammer", "frame": "pulse", "sheet": {"dmg_k": 3.0, "rate_k": 0.35, "range_k": 0.9, "knock": 0.8}, "desc": "A slow, crushing shockwave around the Core", "fx": {}, "look": 18, "w": 5},
	"brl_hornet":   {"slot": "barrel", "name": "Hornet Pod", "frame": "missiles", "sheet": {"dmg_k": 0.55, "missiles": 7, "rate_k": 1.1}, "desc": "Seven small seekers at the nearest bodies", "fx": {}, "look": 19, "w": 6},
	"brl_disc":     {"slot": "barrel", "name": "Disc Thrower", "frame": "saw", "sheet": {"dmg_k": 0.7, "bounces": 8, "bounce_frac": 0.9}, "desc": "A disc that ricochets through nine bodies", "fx": {}, "look": 20, "w": 6},
	"brl_laser":    {"slot": "barrel", "name": "Pulse Laser", "frame": "lance", "sheet": {"dmg_k": 0.5, "rate_k": 2.0, "ramp": 0.35, "ramp_max": 1.0}, "desc": "Quick beam pulses that ramp fast", "fx": {}, "look": 21, "w": 6},
	"brl_vulcan":   {"slot": "barrel", "name": "Vulcan Cannon", "frame": "minigun", "sheet": {"dmg_k": 1.6, "rate_k": 0.7, "spread": 5}, "desc": "Heavier rotary rounds spread over the nearest five", "fx": {"crit": 0.03}, "look": 22, "w": 5},
	"amm_ricochet": {"slot": "ammo", "name": "Ricochet Rounds", "fx": {"bounce": 1.0}, "look": 8, "w": 7},
	"amm_reaper":   {"slot": "ammo", "name": "Reaper Rounds", "fx": {"execute": 0.03}, "look": 9, "w": 6},
	"amm_heavy":    {"slot": "ammo", "name": "Heavy Slugs", "fx": {"core_dmg": 0.18, "rate": -0.08}, "look": 10, "w": 7},
	"amm_siphon":   {"slot": "ammo", "name": "Siphon Rounds", "fx": {"lifesteal": 0.002}, "look": 11, "w": 6},
	"amm_bounty":   {"slot": "ammo", "name": "Bounty Rounds", "fx": {"kill_cash": 0.10}, "look": 12, "w": 6},
	"amm_seeker":   {"slot": "ammo", "name": "Seeker Rounds", "fx": {"core_single": 0.15, "crit": 0.02}, "look": 13, "w": 6},
	"scp_spotter":  {"slot": "scope", "name": "Spotter Scope", "fx": {"normal_dmg": 0.12}, "look": 4, "w": 7},
	"scp_ranger":   {"slot": "scope", "name": "Rangefinder", "fx": {"range": 0.35, "boss": 0.08}, "look": 5, "w": 7},
	"scp_tactical": {"slot": "scope", "name": "Tactical Optic", "fx": {"crit_dmg": 0.25, "crit": 0.02}, "look": 6, "w": 6},
	"pow_fusion":   {"slot": "power", "name": "Fusion Core", "fx": {"core_dmg": 0.10, "range": 0.25}, "look": 4, "w": 7},
	"pow_volatile": {"slot": "power", "name": "Volatile Cell", "fx": {"core_dmg": 0.30, "core_hp": -0.15}, "look": 5, "w": 5},
	"pow_cryo":     {"slot": "power", "name": "Cryo Cell", "fx": {"rate": 0.10, "slow_hit": 0.04}, "look": 6, "w": 6},
	"mag_belt":     {"slot": "mag", "name": "Belt Feed", "fx": {"rate": 0.18, "core_dmg": -0.06}, "look": 3, "w": 7},
	"mag_extended": {"slot": "mag", "name": "Extended Mag", "fx": {"rate": 0.06, "echo": 0.05}, "look": 4, "w": 7},
	"mag_shredder": {"slot": "mag", "name": "Shredder Mag", "fx": {"shred": 0.03}, "look": 5, "w": 6},
	"mzl_comp":     {"slot": "muzzle", "name": "Compensator", "fx": {"rate": 0.08}, "look": 0, "w": 10},
	"mzl_brake":    {"slot": "muzzle", "name": "Muzzle Brake", "fx": {"core_dmg": 0.06, "knock": 0.20}, "look": 1, "w": 8},
	"mzl_choke":    {"slot": "muzzle", "name": "Choke", "fx": {"pierce": 1.0}, "look": 2, "w": 7},
	"mzl_suppressor": {"slot": "muzzle", "name": "Suppressor", "fx": {"crit": 0.04, "crit_dmg": 0.15}, "look": 3, "w": 7},
	"mzl_flare":    {"slot": "muzzle", "name": "Flare Booster", "fx": {"splash": 0.15, "burn": 0.04}, "look": 4, "w": 6},
	"mzl_split":    {"slot": "muzzle", "name": "Splitter Muzzle", "fx": {"chain": 1.0, "core_dmg": -0.05}, "look": 5, "w": 5},
	"hrt_bastion":  {"slot": "heart", "name": "Bastion Heart", "hp_k": 1.45, "regen_k": 0.7, "fx": {"armor": 1.0}, "look": 4, "w": 5, "desc": "A wall of HP, slow to heal"},
	"hrt_scholar":  {"slot": "heart", "name": "Scholar Heart", "hp_k": 0.95, "regen_k": 1.0, "fx": {"xp": 0.08}, "look": 5, "w": 5, "desc": "Learns faster: +XP"},
	"plt_ablative": {"slot": "plating", "name": "Ablative Plating", "fx": {"core_hp": 0.18, "regen": -0.10}, "look": 4, "w": 6},
	"plt_crystal":  {"slot": "plating", "name": "Crystal Plating", "fx": {"shield": 15.0, "dr": 0.015}, "look": 5, "w": 6},
	"gen_fusion":   {"slot": "generator", "name": "Fusion Generator", "fx": {"regen": 0.08, "shield": 12.0}, "look": 3, "w": 7},
	"gen_surge":    {"slot": "generator", "name": "Surge Generator", "fx": {"regen": 0.25, "core_hp": -0.06}, "look": 4, "w": 6},
	"cap_flow":     {"slot": "capacitor", "name": "Flow Capacitor", "fx": {"cash_flat": 0.6}, "look": 3, "w": 7},
	"rct_scrap":    {"slot": "reactor", "name": "Salvage Reactor", "fx": {"scrap_find": 0.12, "coin_run": 0.03}, "look": 3, "w": 7},
	"upl_turret":   {"slot": "uplink", "name": "Turret Uplink", "fx": {"bld_dmg": 0.10}, "look": 0, "w": 10},
	"upl_servo":    {"slot": "uplink", "name": "Servo Uplink", "fx": {"bld_rate": 0.08}, "look": 1, "w": 9},
	"upl_barracks": {"slot": "uplink", "name": "Barracks Uplink", "fx": {"troop_dmg": 0.15, "troop_hp": 0.15}, "look": 2, "w": 7},
	"upl_ordnance": {"slot": "uplink", "name": "Ordnance Uplink", "fx": {"special_dmg": 0.15}, "look": 3, "w": 7},
	"ant_relay":    {"slot": "antenna", "name": "Relay Antenna", "fx": {"luck": 1.0, "scrap_find": 0.05}, "look": 3, "w": 6},
}

## Count-valued fx keys (stay whole; +1 per 2 masterworks instead of power).
const INT_KEYS: Array = ["pierce", "chain", "bounce", "loot_luck", "draft_luck", "luck"]
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
