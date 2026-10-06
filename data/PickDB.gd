extends RefCounted
## Roguelite draft content (REDESIGN_SPEC §2.3, SYSTEMS §2.3-2.7). Every
## in-run building, pack, special, troop hut and Insight pick. The run grid
## starts empty except for the Core, so everything on it comes from here.
##   fam: building | pack | special | hut | insight
##   rarity: common | rare | epic | legendary | insight
##   tags: eco dps aoe control troop special sustain (synergy chips + filter)
##   max: building/hut level cap (L5) or pack/special stack cap
##   size: run-grid footprint side (V2 P3b; 1 when absent, 2 = a 2x2 building)
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
	"gun":       {"fam": "building", "name": "Gatling", "rarity": "common", "tags": ["dps"], "max": 5, "desc": "Arc turret (120 deg): 6 dmg x1.2, 2.0/s, range 3; rounds pierce"},
	"mortar":    {"fam": "building", "name": "Mortar", "rarity": "common", "tags": ["aoe", "dps"], "max": 5, "size": 2, "desc": "2x2. 18 dmg, 0.4/s, range 4.5, 1-cell splash (min range 1.5)"},
	"tesla":     {"fam": "building", "name": "Tesla Coil", "rarity": "rare", "tags": ["aoe", "control"], "max": 5, "desc": "9 dmg, 0.8/s, chains 3 at 70%"},
	"flak":      {"fam": "building", "name": "Flamer", "rarity": "common", "tags": ["dps", "aoe"], "max": 5, "desc": "Fixed 50 deg cone along its facing (x1.4): fire licks, burn spreads through the pile"},
	"railgun":   {"fam": "building", "name": "Railgun", "rarity": "epic", "tags": ["dps"], "max": 5, "size": 2, "desc": "2x2 fixed lane along its facing (x1.6): 60 dmg, 0.25/s, pierces the whole line (range 7); ring 3+"},
	"armory":    {"fam": "building", "name": "Armory", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Adjacent buildings +15% dmg"},
	"beacon":    {"fam": "building", "name": "Beacon", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Within 4 cells: +10% rate, +0.3 range"},
	"bulwark":   {"fam": "building", "name": "Bulwark", "rarity": "common", "tags": ["sustain"], "max": 5, "desc": "Core +40 HP"},
	"aegis":     {"fam": "building", "name": "Aegis", "rarity": "epic", "tags": ["sustain"], "max": 5, "desc": "60-pt Core shield; regen 6/s after 4 s without damage"},
	"barricade": {"fam": "building", "name": "Wall", "rarity": "common", "tags": ["control"], "max": 5, "desc": "Blocker: the horde flows around it or squeezes through at a crawl; every enemy within 1.5 cells is slowed 30%"},
	"mine":      {"fam": "building", "name": "Gold Mine", "rarity": "common", "tags": ["eco"], "max": 5, "desc": "+0.8 cash/s"},
	"oilmill":   {"fam": "building", "name": "Oil Mill", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "+2.0 cash/s; adjacent buildings -10% rate"},
	"bounty":    {"fam": "building", "name": "Bounty Post", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "+20% kill cash within 3 cells"},
	"vault":     {"fam": "building", "name": "Vault", "rarity": "epic", "tags": ["eco"], "max": 5, "desc": "+2% interest, +100 interest cap"},
	"refinery":  {"fam": "building", "name": "Refinery", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "+15% XP (each level-up = a free reroll), +0.5 cash/s"},
	"frost":     {"fam": "building", "name": "Cryo Spire", "rarity": "rare", "tags": ["control"], "max": 5, "desc": "Slows 30% within 2.5 cells, 3 dmg/s"},
	"obelisk":   {"fam": "building", "name": "Siphon Obelisk", "rarity": "legendary", "tags": ["sustain"], "max": 5, "desc": "1% of all damage dealt heals the Core"},
	# ---- V2 P7d weapons (12) -------------------------------------------------
	"pulse":     {"fam": "building", "name": "Pulse Emitter", "rarity": "rare", "tags": ["aoe"], "max": 5, "desc": "Radial pulse: 6 dmg to every body within 2.2 cells, 0.7/s, a small shove"},
	"missile":   {"fam": "building", "name": "Missile Battery", "rarity": "epic", "tags": ["dps", "aoe"], "max": 5, "size": 2, "desc": "2x2. 4 homing missiles (12 dmg + small blasts) at the nearest bodies, range 5"},
	"spike":     {"fam": "building", "name": "Spike Pylon", "rarity": "common", "tags": ["aoe", "control"], "max": 5, "desc": "Stabs every body within 1.6 cells: 3 dmg, 2/s"},
	"mines":     {"fam": "building", "name": "Minelayer", "rarity": "rare", "tags": ["aoe"], "max": 5, "desc": "Seeds a mine under the nearest body: a 28-dmg blast (0.8 cell) after 1 s"},
	"scatter":   {"fam": "building", "name": "Scatter Gun", "rarity": "common", "tags": ["dps"], "max": 5, "desc": "Fixed 60 deg cone (x1.4): 6 pellets of 6 dmg at the nearest bodies in it"},
	"laser":     {"fam": "building", "name": "Laser Lance", "rarity": "epic", "tags": ["dps"], "max": 5, "size": 2, "desc": "2x2 fixed lane (x1.6): a beam through the whole lane, ramping to x3 while it keeps firing"},
	"saw":       {"fam": "building", "name": "Saw Launcher", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Arc 140 deg (x1.2): a 12-dmg saw that ricochets through 4 more bodies"},
	"arcproj":   {"fam": "building", "name": "Arc Projector", "rarity": "rare", "tags": ["aoe"], "max": 5, "desc": "Arc 100 deg (x1.3): forked lightning, 4 jumps per fork"},
	"sonic":     {"fam": "building", "name": "Sonic Cannon", "rarity": "rare", "tags": ["control"], "max": 5, "desc": "Fixed 70 deg cone (x1.4): a shock wave that hits the pile and hurls it back"},
	"harpoon":   {"fam": "building", "name": "Harpoon", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Arc 90 deg (x1.3): one 40-dmg bolt, x2.5 on elites and bosses, slows it 40%"},
	"plasma":    {"fam": "building", "name": "Plasma Fence", "rarity": "epic", "tags": ["control", "aoe"], "max": 5, "desc": "Fixed lane (x1.5): sets every body on its line burning for 2 s"},
	"flakburst": {"fam": "building", "name": "Flak Burst", "rarity": "common", "tags": ["aoe"], "max": 5, "desc": "Arc 120 deg (x1.2): airbursts over the crowd (9 dmg, 0.5-cell blasts)"},
	# ---- V2 P7d support / eco (22, SupportDB) -------------------------------
	"amp":         {"fam": "building", "name": "Amplifier", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Touching buildings (and the Core) +20% damage"},
	"ocrelay":     {"fam": "building", "name": "Overclock Relay", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Within 2 cells: +12% attack rate"},
	"uplink":      {"fam": "building", "name": "Targeting Uplink", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Within 3 cells: +0.4 range"},
	"critlens":    {"fam": "building", "name": "Crit Lens", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "Within 2 cells: +6% crit chance"},
	"coolant":     {"fam": "building", "name": "Coolant Tower", "rarity": "common", "tags": ["dps"], "max": 5, "desc": "Touching buildings +25% attack rate, -5% damage"},
	"ammodepot":   {"fam": "building", "name": "Ammo Depot", "rarity": "common", "tags": ["dps"], "max": 5, "desc": "Within 2 cells: +8% damage, +5% attack rate"},
	"watchtower":  {"fam": "building", "name": "Watchtower", "rarity": "common", "tags": ["dps"], "max": 5, "desc": "Within 3 cells: +0.25 range, +3% crit"},
	"forge":       {"fam": "building", "name": "War Forge", "rarity": "epic", "tags": ["dps"], "max": 5, "desc": "Touching buildings +12% damage, +3% crit"},
	"lure":        {"fam": "building", "name": "Snare Beacon", "rarity": "common", "tags": ["control"], "max": 5, "desc": "Weapon hits slow +5%, knockback +15%"},
	"shieldpylon": {"fam": "building", "name": "Shield Pylon", "rarity": "rare", "tags": ["sustain"], "max": 5, "desc": "+40 Core shield"},
	"bank":        {"fam": "building", "name": "Bank", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "+1% interest, +25% interest cap"},
	"capacitor":   {"fam": "building", "name": "Capacitor", "rarity": "rare", "tags": ["dps"], "max": 5, "desc": "+6% Weapon attack rate, +10% crit damage"},
	"market":      {"fam": "building", "name": "Market", "rarity": "common", "tags": ["eco"], "max": 5, "desc": "+1.2 cash/s, +5% kill cash"},
	"xpsiphon":    {"fam": "building", "name": "XP Siphon", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "+25% XP (more drafts)"},
	"magnet":      {"fam": "building", "name": "Loot Magnet", "rarity": "epic", "tags": ["eco"], "max": 5, "desc": "+1 loot luck, +10% Scrap"},
	"salvager":    {"fam": "building", "name": "Salvager", "rarity": "common", "tags": ["eco"], "max": 5, "desc": "+25% Scrap, +3% coins"},
	"totem":       {"fam": "building", "name": "Luck Totem", "rarity": "epic", "tags": ["eco"], "max": 5, "desc": "+1 draft luck (rarer cards)"},
	"medbay":      {"fam": "building", "name": "Med Bay", "rarity": "common", "tags": ["sustain"], "max": 5, "desc": "+30% Core regen, +5% Core max HP"},
	"taxoffice":   {"fam": "building", "name": "Tax Office", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "+0.5% interest, +8% cash per second"},
	"insurance":   {"fam": "building", "name": "Insurance Office", "rarity": "rare", "tags": ["sustain"], "max": 5, "desc": "-4% damage taken, +1 armor"},
	"slots":       {"fam": "building", "name": "Slot Machine", "rarity": "rare", "tags": ["eco"], "max": 5, "desc": "Spins at every wave start: x1 / x3 / x6 / x20 a 60-cash stake"},
	"gate":        {"fam": "building", "name": "Spike Gate", "rarity": "common", "tags": ["control"], "max": 5, "desc": "A Wall that also stabs: bodies within 1.5 cells -20% speed and take 6 dmg/s"},
	# ---- troop huts (6) ------------------------------------------------------
	"hut_infantry": {"fam": "hut", "name": "Rifle Barracks", "rarity": "common", "tags": ["troop"], "max": 5, "desc": "3 Riflemen guard the whole perimeter from their post; they taunt nearby enemies"},
	"hut_sapper":   {"fam": "hut", "name": "Sapper Den", "rarity": "rare", "tags": ["troop", "aoe"], "max": 5, "desc": "2 Sappers charge elites and bosses first and explode (x2 vs armored)"},
	"hut_sniper":   {"fam": "hut", "name": "Sniper Nest", "rarity": "rare", "tags": ["troop", "dps"], "max": 5, "desc": "1 Sniper: 40-dmg shots at range 6, picks off what the turrets miss"},
	"hut_guard":    {"fam": "hut", "name": "Guard Post", "rarity": "common", "tags": ["troop", "control"], "max": 5, "desc": "2 Guards: tough, taunting blockers that hold the line"},
	"hut_medic":    {"fam": "hut", "name": "Medic Tent", "rarity": "rare", "tags": ["troop", "sustain"], "max": 5, "desc": "1 Medic + Core regen +1.5 (x tier)"},
	"hut_engineer": {"fam": "hut", "name": "Engineer Hut", "rarity": "rare", "tags": ["troop", "dps"], "max": 5, "desc": "2 Engineers; touching buildings +10% attack rate"},
	# ---- upgrade packs (10; one-shot, last the run) --------------------------
	"pk_arsenal":   {"fam": "pack", "name": "Arsenal Pack", "rarity": "common", "tags": ["dps"], "max": 5, "desc": "+12% dmg (all)"},
	"pk_overclock": {"fam": "pack", "name": "Overclock Pack", "rarity": "common", "tags": ["dps"], "max": 3, "desc": "+8% rate (all), -5% Core HP"},
	"pk_fort":      {"fam": "pack", "name": "Fortify Pack", "rarity": "common", "tags": ["sustain"], "max": 3, "desc": "+20% Core HP, +1 armor"},
	"pk_ledger":    {"fam": "pack", "name": "Ledger Pack", "rarity": "common", "tags": ["eco"], "max": 5, "desc": "+0.6 cash/s, +5% kill cash"},
	"pk_optics":    {"fam": "pack", "name": "Optics Pack", "rarity": "rare", "tags": ["dps"], "max": 2, "desc": "+0.5 range (all)"},
	"pk_crit":      {"fam": "pack", "name": "Precision Pack", "rarity": "rare", "tags": ["dps"], "max": 3, "desc": "+8% crit chance (crit x2)"},
	"pk_logistics": {"fam": "pack", "name": "Logistics Pack", "rarity": "rare", "tags": ["eco"], "max": 3, "desc": "Core Enhancements -12% cost"},
	"pk_core":      {"fam": "pack", "name": "Core Surge", "rarity": "epic", "tags": ["dps"], "max": 2, "desc": "Core attack +15% dmg, +5% rate"},
	"pk_barracks":  {"fam": "pack", "name": "Drill Sergeant", "rarity": "rare", "tags": ["troop"], "max": 3, "desc": "Troops +25% HP and dmg, -2 s respawn"},
	"pk_gambit":    {"fam": "pack", "name": "Gambit", "rarity": "legendary", "tags": ["dps"], "max": 1, "desc": "+40% dmg (all), enemies +15% HP"},
	# ---- V2 P7d stat packs (20; fx per stack, TowerState.rfx) ---------------
	"pk_sharp":    {"fam": "pack", "name": "Sharp Rounds", "rarity": "common", "tags": ["dps"], "max": 3, "fx": {"crit": 0.04}, "desc": "+4% crit chance"},
	"pk_heavy":    {"fam": "pack", "name": "Heavy Shells", "rarity": "common", "tags": ["dps"], "max": 5, "fx": {"dmg": 0.06, "knock": 0.10}, "desc": "+6% damage, +10% knockback"},
	"pk_range":    {"fam": "pack", "name": "Rangefinder Pack", "rarity": "rare", "tags": ["dps"], "max": 3, "fx": {"range": 0.25}, "desc": "+0.25 Weapon range"},
	"pk_rate":     {"fam": "pack", "name": "Feeder Pack", "rarity": "common", "tags": ["dps"], "max": 5, "fx": {"rate": 0.05, "bld_rate": 0.05}, "desc": "+5% Weapon and building attack rate"},
	"pk_critd":    {"fam": "pack", "name": "Hollow Points", "rarity": "rare", "tags": ["dps"], "max": 3, "fx": {"crit_dmg": 0.15}, "desc": "+15% crit damage"},
	"pk_boss":     {"fam": "pack", "name": "Titan Rounds", "rarity": "rare", "tags": ["dps"], "max": 3, "fx": {"boss": 0.15}, "desc": "+15% damage to bosses"},
	"pk_armor":    {"fam": "pack", "name": "Plating Pack", "rarity": "common", "tags": ["sustain"], "max": 5, "fx": {"armor": 1.0}, "desc": "+1 Core armor"},
	"pk_regen":    {"fam": "pack", "name": "Repair Kit", "rarity": "common", "tags": ["sustain"], "max": 3, "fx": {"regen": 0.25}, "desc": "+25% Core regen"},
	"pk_shield":   {"fam": "pack", "name": "Shield Cell", "rarity": "rare", "tags": ["sustain"], "max": 3, "fx": {"shield": 25.0}, "desc": "+25 Core shield"},
	"pk_dr":       {"fam": "pack", "name": "Ablative Pack", "rarity": "rare", "tags": ["sustain"], "max": 3, "fx": {"dr": 0.03}, "desc": "-3% damage taken"},
	"pk_thorns":   {"fam": "pack", "name": "Barbed Pack", "rarity": "common", "tags": ["sustain"], "max": 3, "fx": {"reflect": 0.08}, "desc": "Reflect +8% of Core hits"},
	"pk_steal":    {"fam": "pack", "name": "Leech Pack", "rarity": "epic", "tags": ["sustain"], "max": 3, "fx": {"lifesteal": 0.004}, "desc": "+0.4% lifesteal"},
	"pk_xp":       {"fam": "pack", "name": "Study Pack", "rarity": "common", "tags": ["eco"], "max": 3, "fx": {"xp": 0.20}, "desc": "+20% XP"},
	"pk_kill":     {"fam": "pack", "name": "Bounty Pack", "rarity": "common", "tags": ["eco"], "max": 3, "fx": {"kill_cash": 0.08}, "desc": "+8% kill cash"},
	"pk_interest": {"fam": "pack", "name": "Savings Pack", "rarity": "rare", "tags": ["eco"], "max": 3, "fx": {"interest": 0.005, "icap": 0.10}, "desc": "+0.5% interest, +10% interest cap"},
	"pk_scrap":    {"fam": "pack", "name": "Salvage Pack", "rarity": "common", "tags": ["eco"], "max": 3, "fx": {"scrap_find": 0.15}, "desc": "+15% Scrap"},
	"pk_coin":     {"fam": "pack", "name": "Coin Pack", "rarity": "rare", "tags": ["eco"], "max": 3, "fx": {"coin_run": 0.05}, "desc": "+5% coins this run"},
	"pk_luck":     {"fam": "pack", "name": "Clover Pack", "rarity": "epic", "tags": ["eco"], "max": 2, "fx": {"draft_luck": 1.0}, "desc": "+1 draft luck"},
	"pk_slow":     {"fam": "pack", "name": "Cryo Rounds", "rarity": "common", "tags": ["control"], "max": 3, "fx": {"slow_hit": 0.04}, "desc": "Weapon hits slow +4%"},
	"pk_exec":     {"fam": "pack", "name": "Finisher Pack", "rarity": "rare", "tags": ["dps"], "max": 3, "fx": {"execute": 0.015}, "desc": "Weapon hits finish bodies under +1.5% HP"},
	# ---- specials (6; hotkeys 1-4; Napalm Line cut, §9) ---------------------
	"sp_orbital":   {"fam": "special", "name": "Orbital Strike", "rarity": "rare", "tags": ["special", "aoe"], "max": 3, "desc": "Target a 1.5-cell circle: 25x Core dmg after 0.8 s", "cd": 30.0},
	"sp_emp":       {"fam": "special", "name": "EMP Burst", "rarity": "rare", "tags": ["special", "control"], "max": 3, "desc": "All enemies -50% speed for 4 s; shields stripped", "cd": 25.0},
	"sp_repair":    {"fam": "special", "name": "Repair Pulse", "rarity": "common", "tags": ["special", "sustain"], "max": 3, "desc": "Heal the Core 35% max HP over 3 s", "cd": 40.0},
	"sp_overdrive": {"fam": "special", "name": "Overdrive", "rarity": "rare", "tags": ["special", "dps"], "max": 3, "desc": "Core rate x2 for 6 s", "cd": 45.0},
	"sp_magnet":    {"fam": "special", "name": "Cash Magnet", "rarity": "common", "tags": ["special", "eco"], "max": 3, "desc": "Kills give x2 cash for 10 s", "cd": 60.0},
	"sp_timewarp":  {"fam": "special", "name": "Time Warp", "rarity": "legendary", "tags": ["special", "control"], "max": 3, "desc": "Enemies frozen for 3 s", "cd": 90.0},
	"sp_nuke":      {"fam": "special", "name": "Tactical Nuke", "rarity": "legendary", "tags": ["special", "aoe"], "max": 3, "desc": "Target a 3-cell circle: 60x Weapon damage after 1.5 s", "cd": 120.0},
	"sp_shield":    {"fam": "special", "name": "Barrier", "rarity": "rare", "tags": ["special", "sustain"], "max": 3, "desc": "The Core is invulnerable for 3 s", "cd": 50.0},
	"sp_frenzy":    {"fam": "special", "name": "Frenzy", "rarity": "rare", "tags": ["special", "dps"], "max": 3, "desc": "Every building fires 50% faster for 8 s", "cd": 45.0},
	"sp_blackhole": {"fam": "special", "name": "Black Hole", "rarity": "epic", "tags": ["special", "control"], "max": 3, "desc": "Target a 2.5-cell circle: bodies -80% speed for 4 s and 10x Weapon damage", "cd": 60.0},
	"sp_meteor":    {"fam": "special", "name": "Meteor Shower", "rarity": "epic", "tags": ["special", "aoe"], "max": 3, "desc": "5 meteors around the densest pile: 8x Weapon damage each", "cd": 70.0},
	"sp_jackpot":   {"fam": "special", "name": "Jackpot", "rarity": "rare", "tags": ["special", "eco"], "max": 3, "desc": "Spin a Supply Drop right now", "cd": 90.0},
	# ---- Insight (7; super-rare, banked permanently at run end) -------------
	"in_dmg":   {"fam": "insight", "name": "Insight: Force", "rarity": "insight", "tags": [], "step": 0.005, "cap": 0.25, "desc": "+0.5% all dmg, permanently (cap 25%)"},
	"in_hp":    {"fam": "insight", "name": "Insight: Bulwark", "rarity": "insight", "tags": [], "step": 0.005, "cap": 0.25, "desc": "+0.5% Core HP, permanently (cap 25%)"},
	"in_cash":  {"fam": "insight", "name": "Insight: Ledger", "rarity": "insight", "tags": [], "step": 0.005, "cap": 0.20, "desc": "+0.5% cash/s and kill cash, permanently (cap 20%)"},
	"in_rate":  {"fam": "insight", "name": "Insight: Tempo", "rarity": "insight", "tags": [], "step": 0.003, "cap": 0.10, "desc": "+0.3% attack rate, permanently (cap 10%)"},
	"in_luck":  {"fam": "insight", "name": "Insight: Fortune", "rarity": "insight", "tags": [], "step": 1.0, "cap": 10.0, "desc": "+1 draft Luck, permanently (cap 10)"},
	"in_drop":  {"fam": "insight", "name": "Insight: Scavenger", "rarity": "insight", "tags": [], "step": 0.01, "cap": 0.15, "desc": "+1% part drop chance, permanently (cap 15%)"},
}

const BUILDINGS: Array = ["gun", "mortar", "tesla", "flak", "railgun", "armory", "beacon", "bulwark", "aegis", "barricade", "mine", "oilmill", "bounty", "vault", "refinery", "frost", "obelisk",
	"pulse", "missile", "spike", "mines", "scatter", "laser", "saw", "arcproj", "sonic", "harpoon", "plasma", "flakburst",
	"amp", "ocrelay", "uplink", "critlens", "coolant", "ammodepot", "watchtower", "forge", "lure", "shieldpylon", "bank",
	"capacitor", "market", "xpsiphon", "magnet", "salvager", "totem", "medbay", "taxoffice", "insurance", "slots", "gate"]
const HUTS: Array = ["hut_infantry", "hut_sapper", "hut_sniper", "hut_guard", "hut_medic", "hut_engineer"]
const PACKS: Array = ["pk_arsenal", "pk_overclock", "pk_fort", "pk_ledger", "pk_optics", "pk_crit", "pk_logistics", "pk_core", "pk_barracks", "pk_gambit",
	"pk_sharp", "pk_heavy", "pk_range", "pk_rate", "pk_critd", "pk_boss", "pk_armor", "pk_regen", "pk_shield", "pk_dr",
	"pk_thorns", "pk_steal", "pk_xp", "pk_kill", "pk_interest", "pk_scrap", "pk_coin", "pk_luck", "pk_slow", "pk_exec"]
const SPECIALS: Array = ["sp_orbital", "sp_emp", "sp_repair", "sp_overdrive", "sp_magnet", "sp_timewarp",
	"sp_nuke", "sp_shield", "sp_frenzy", "sp_blackhole", "sp_meteor", "sp_jackpot"]
const INSIGHT: Array = ["in_dmg", "in_hp", "in_cash", "in_rate", "in_luck", "in_drop"]


## Summed fx of the stat packs taken ({id: copies}; packs with an "fx").
static func pack_fx(packs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in packs.keys():
		var fx: Dictionary = (DEFS.get(String(id), {}) as Dictionary).get("fx", {})
		for k in fx.keys():
			out[k] = float(out.get(k, 0.0)) + float(fx[k]) * float(int(packs[id]))
	return out


## Run-grid footprint side of a pick (1x1 unless the def says otherwise).
static func size_of(id: String) -> int:
	return int((DEFS.get(id, {}) as Dictionary).get("size", 1))


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
