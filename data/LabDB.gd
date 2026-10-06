extends RefCounted
## Research Hall projects (V2 P8). Research is INSTANT (owner feedback #1: no
## timers) and paid in coins. Each project:
##   name, cat, max          category tab (CATS) and level cap
##   costs | base + growth   explicit price per step, else base * growth^L
##   hall                    Research Hall level that opens it (row 1 / 3 / 5 / 8)
##   req [[id, lvl], ...]    other research it needs first
##   fx {key: per level}     run fx (TowerState pf keys) added per level
##   effect, icon [glyph, colour]   card text and the RunArt glyph
## Effects without fx are read by level where they apply (Labs.modifiers,
## Labs.enemy, Gear, Loot, Outpost licences, TrackDB unlocks). Every price is
## cut by Lab Discount (Labs.price). Ids of the V1 projects are kept for saves:
## offcap = Storage Tech, offrate = Logistics Tech.

const CATS: Array = [["core", "Core"], ["enemy", "Enemy"], ["economy", "Economy"], ["loot", "Loot"], ["forge", "Forge"], ["run", "Run"], ["qol", "QOL"]]
## Research Hall levels that open each row of projects.
const HALL_ROWS: Array = [1, 3, 5, 8]

const DEFS: Dictionary = {
	# ---- Core ------------------------------------------------------------
	"dmg":         {"name": "Calibration", "cat": "core", "max": 30, "base": 80.0, "growth": 1.8, "hall": 1, "effect": "+5% damage (Core & weapons)", "icon": ["burst", "ff4d6d"]},
	"hp":          {"name": "Plating", "cat": "core", "max": 30, "base": 80.0, "growth": 1.8, "hall": 1, "effect": "+5% Core max HP", "icon": ["shield", "6e9bff"]},
	"core_theory": {"name": "Core Theory", "cat": "core", "max": 5, "costs": [5000, 40000, 250000, 1500000, 8000000], "hall": 1, "effect": "Unlocks Core levels 10 / 20 / 30 / 40 / 50", "icon": ["rings", "39e6ff"]},
	"targeting":   {"name": "Targeting AI", "cat": "core", "max": 10, "base": 1500.0, "growth": 1.7, "hall": 1, "req": [["dmg", 3]], "fx": {"range": 0.05}, "effect": "+0.05 cell Weapon range", "icon": ["eye", "39e6ff"]},
	"optics":      {"name": "Optics", "cat": "core", "max": 10, "base": 3000.0, "growth": 1.75, "hall": 3, "req": [["targeting", 2]], "fx": {"crit": 0.005}, "effect": "+0.5% crit chance", "icon": ["lens", "ff5fb8"]},
	"reactor":     {"name": "Reactor Tuning", "cat": "core", "max": 10, "base": 3000.0, "growth": 1.75, "hall": 3, "req": [["dmg", 5]], "fx": {"rate": 0.02}, "effect": "+2% Weapon attack rate", "icon": ["chevrons", "ff9b3d"]},
	"aegis":       {"name": "Aegis", "cat": "core", "max": 10, "base": 4000.0, "growth": 1.75, "hall": 3, "req": [["hp", 5]], "fx": {"dr": 0.005}, "effect": "-0.5% damage taken", "icon": ["shield", "8fb8ff"]},
	"shielding":   {"name": "Core Shielding", "cat": "core", "max": 10, "base": 2500.0, "growth": 1.7, "hall": 3, "req": [["hp", 3]], "fx": {"shield": 10.0}, "effect": "+10 Core shield", "icon": ["shield", "39e6ff"]},
	"manual":      {"name": "Manual Mastery", "cat": "core", "max": 5, "base": 6000.0, "growth": 2.0, "hall": 3, "req": [["targeting", 1]], "effect": "+5% max focus damage while you aim", "icon": ["target", "ffd34d"]},
	# ---- Enemy -----------------------------------------------------------
	"en_hp":       {"name": "Weak Points", "cat": "enemy", "max": 15, "base": 2000.0, "growth": 1.6, "hall": 3, "effect": "-1% enemy HP", "icon": ["target", "ff4d6d"]},
	"en_atk":      {"name": "Blunting", "cat": "enemy", "max": 10, "base": 2500.0, "growth": 1.65, "hall": 3, "req": [["en_hp", 2]], "effect": "-2% enemy damage", "icon": ["spikes", "8fb8ff"]},
	"en_speed":    {"name": "Mire Field", "cat": "enemy", "max": 10, "base": 3000.0, "growth": 1.7, "hall": 3, "req": [["en_hp", 3]], "effect": "-1% enemy speed", "icon": ["snow", "9fe0ff"]},
	"boss_breaker": {"name": "Boss Breaker", "cat": "enemy", "max": 10, "base": 8000.0, "growth": 1.7, "hall": 5, "req": [["dmg", 5]], "fx": {"boss": 0.05}, "effect": "+5% damage to bosses", "icon": ["missile", "ff9b3d"]},
	"elite_hp":    {"name": "Elite Profiling", "cat": "enemy", "max": 10, "base": 6000.0, "growth": 1.7, "hall": 5, "req": [["en_hp", 5]], "effect": "-3% elite HP", "icon": ["lens", "ffd34d"]},
	"sapper_damp": {"name": "Sapper Dampening", "cat": "enemy", "max": 5, "base": 10000.0, "growth": 2.0, "hall": 5, "req": [["en_atk", 2]], "effect": "-8% Sapper blast damage", "icon": ["mine", "ff4d6d"]},
	# ---- Economy ---------------------------------------------------------
	"coin":        {"name": "Coin Bonus", "cat": "economy", "max": 20, "base": 60.0, "growth": 1.35, "hall": 1, "effect": "+5% coins", "icon": ["coin", "ffd34d"]},
	"startcash":   {"name": "Starting Cash", "cat": "economy", "max": 15, "base": 40.0, "growth": 1.40, "hall": 1, "effect": "+$15 cash at run start", "icon": ["coin", "a3e635"]},
	"interest":    {"name": "Compound Interest", "cat": "economy", "max": 10, "base": 1500.0, "growth": 1.6, "hall": 1, "req": [["coin", 2]], "fx": {"interest": 0.002}, "effect": "+0.2% wave interest", "icon": ["bank", "ffd34d"]},
	# V2 P10 eco ramp: the long run-cash line (owner: "a lengthy ramp-up requiring heavy investment in research and outpost building")
	"field_econ":  {"name": "Field Economics", "cat": "economy", "max": 15, "base": 1800.0, "growth": 1.62, "hall": 3, "req": [["coin", 2]], "fx": {"run_cash": 0.10}, "effect": "+10% all run cash (more enhancements, longer runs)", "icon": ["coin", "4ade80"]},
	"bounty":      {"name": "Clear Bounty", "cat": "economy", "max": 10, "base": 1000.0, "growth": 1.55, "hall": 1, "req": [["coin", 1]], "effect": "+10% coins from cleared waves", "icon": ["star", "ffd34d"]},
	"offcap":      {"name": "Storage Tech", "cat": "economy", "max": 8, "base": 150.0, "growth": 1.60, "hall": 1, "effect": "+4% Outpost storage", "icon": ["box", "e8c48f"]},
	"offrate":     {"name": "Logistics Tech", "cat": "economy", "max": 5, "base": 120.0, "growth": 1.50, "hall": 1, "effect": "+5% Outpost production", "icon": ["gear", "a3e635"]},
	"lab_discount": {"name": "Lab Discount", "cat": "economy", "max": 10, "base": 25000.0, "growth": 2.4, "hall": 3, "req": [["coin", 3]], "effect": "-3% on all research", "icon": ["lens", "a3e635"]},
	"lic_mill":    {"name": "Mill Licence", "cat": "economy", "max": 2, "costs": [20000, 250000], "hall": 3, "req": [["offrate", 1]], "effect": "+1 Mill in the Outpost", "icon": ["gear", "ffd34d"]},
	"lic_mine":    {"name": "Mine Licence", "cat": "economy", "max": 2, "costs": [60000, 600000], "hall": 5, "req": [["lic_mill", 1]], "effect": "+1 Deep Mine in the Outpost", "icon": ["mine", "ffd34d"]},
	"lic_scav":    {"name": "Scavenger Licence", "cat": "economy", "max": 2, "costs": [80000, 900000], "hall": 5, "req": [["lic_mill", 1]], "effect": "+1 of each Scavenger in the Outpost", "icon": ["magnet", "f59e0b"]},
	"lic_core":    {"name": "Core Works Licence", "cat": "economy", "max": 1, "costs": [400000], "hall": 5, "req": [["lic_mill", 1]], "effect": "+1 of every Core building in the Outpost", "icon": ["rings", "ff9b3d"]},
	"lic_adv":     {"name": "Advanced Licensing", "cat": "economy", "max": 2, "costs": [150000, 1500000], "hall": 5, "req": [["lic_mill", 1]], "effect": "Outpost buildings that need Relay 3+ unlock one Relay level earlier", "icon": ["star", "39e6ff"]},
	# ---- Loot ------------------------------------------------------------
	"loot_theory": {"name": "Loot Theory", "cat": "loot", "max": 10, "base": 4000.0, "growth": 1.7, "hall": 3, "effect": "+10% elite item drop chance", "icon": ["box", "f59e0b"]},
	"appraisal":   {"name": "Appraisal", "cat": "loot", "max": 10, "base": 6000.0, "growth": 1.8, "hall": 3, "req": [["loot_theory", 1]], "effect": "+1 rarity luck on drops, crates and Fabricator stock", "icon": ["star", "f59e0b"]},
	"cache_luck":  {"name": "Cache Luck", "cat": "loot", "max": 5, "base": 20000.0, "growth": 2.0, "hall": 5, "req": [["appraisal", 2]], "effect": "+2 rarity luck inside caches", "icon": ["slot", "a855f7"]},
	"scav_rate":   {"name": "Scavenging", "cat": "loot", "max": 10, "base": 5000.0, "growth": 1.7, "hall": 3, "req": [["loot_theory", 1]], "effect": "+6% Scavenger speed", "icon": ["magnet", "4ade80"]},
	"reclaim":     {"name": "Reclamation", "cat": "loot", "max": 5, "base": 3000.0, "growth": 1.8, "hall": 1, "effect": "+10% Scrap from smelting parts", "icon": ["gear", "d9b98a"]},
	# ---- Forge -----------------------------------------------------------
	"stabilizer":  {"name": "Stabilizer", "cat": "forge", "max": 2, "costs": [5000, 80000], "hall": 3, "effect": "+1 perk lock slot per part (1 -> 3)", "icon": ["shield", "ffd34d"]},
	"blacklist":   {"name": "Blacklist", "cat": "forge", "max": 3, "costs": [10000, 120000, 1200000], "hall": 3, "req": [["stabilizer", 1]], "effect": "+1 banned perk per assembly (Weapon / Core)", "icon": ["target", "ff3ea5"]},
	"reroll_disc": {"name": "Reroll Discount", "cat": "forge", "max": 5, "base": 4000.0, "growth": 1.8, "hall": 3, "effect": "-8% perk reroll Scrap", "icon": ["slot", "d9b98a"]},
	"greater_cal": {"name": "Greater Calibration", "cat": "forge", "max": 5, "base": 5000.0, "growth": 1.9, "hall": 3, "effect": "-5% part upgrade coins", "icon": ["chevrons", "39e6ff"]},
	"enchanters_eye": {"name": "Enchanter's Eye", "cat": "forge", "max": 1, "costs": [250000], "hall": 5, "req": [["reroll_disc", 2]], "effect": "Perk rerolls offer 3 candidates", "icon": ["eye", "a855f7"]},
	"masterwork_odds": {"name": "Masterwork Odds", "cat": "forge", "max": 3, "costs": [30000, 300000, 2000000], "hall": 5, "req": [["greater_cal", 2]], "effect": "+5% masterwork jackpot chance (15% -> 30%)", "icon": ["star", "ffd34d"]},
	"brand_contracts": {"name": "Part Contracts", "cat": "forge", "max": 1, "costs": [150000], "hall": 5, "req": [["blacklist", 1]], "effect": "Pick the part type of a Scrap crate (x1.5 price)", "icon": ["coin", "ff3ea5"]},
	"mythic_fusion": {"name": "Mythic Fusion", "cat": "forge", "max": 1, "costs": [5000000], "hall": 8, "req": [["stabilizer", 2]], "effect": "Merge three Legendaries into a Mythic", "icon": ["rings", "ff3e6c"]},
	# ---- Run -------------------------------------------------------------
	"grid":        {"name": "Grid Expansion", "cat": "run", "max": 7, "costs": [2000, 10000, 50000, 200000, 750000, 2500000, 8000000], "hall": 1, "effect": "Bigger run grid: 7x7 -> 9x9 -> 11x11 ... -> 21x21", "icon": ["box", "39e6ff"]},
	"speed":       {"name": "Game Speed", "cat": "run", "max": 4, "costs": [8000, 60000, 400000, 2500000], "hall": 1, "effect": "Unlocks game speed 1.5x / 2x / 2.5x / 3x", "icon": ["chevrons", "39e6ff"]},
	"xp":          {"name": "XP Theory", "cat": "run", "max": 20, "base": 50.0, "growth": 1.35, "hall": 1, "effect": "+4% run XP (more drafts)", "icon": ["drop", "39e6ff"]},
	"reroll":      {"name": "Reroll Bank", "cat": "run", "max": 3, "base": 250.0, "growth": 3.0, "hall": 1, "effect": "+1 free draft reroll per run", "icon": ["slot", "39e6ff"]},
	"banish_r":    {"name": "Banish", "cat": "run", "max": 2, "costs": [20000, 300000], "hall": 3, "req": [["reroll", 1]], "effect": "+1 draft banish per run", "icon": ["target", "8a9bbd"]},
	"draft_lock":  {"name": "Draft Lock", "cat": "run", "max": 1, "costs": [60000], "hall": 3, "req": [["reroll", 1]], "effect": "Lock one more draft card (2 -> 3)", "icon": ["shield", "c084fc"]},
	"enh_theory":  {"name": "Enhancement Theory", "cat": "run", "max": 3, "costs": [10000, 120000, 1000000], "hall": 3, "req": [["xp", 3]], "effect": "Opens advanced Core Enhancements: I Execute / Lifesteal / Lucky Purchase, II Chain & Bounce / Last Stand / Scrap Find, III Pierce / Thorns / Interest Cap", "icon": ["rings", "a855f7"]},
	"draft_choices": {"name": "Draft Choices", "cat": "run", "max": 2, "costs": [150000, 2000000], "hall": 5, "req": [["reroll", 1]], "effect": "+1 card in every draft (3 -> 5)", "icon": ["pellets", "c084fc"]},
	# ---- QOL -------------------------------------------------------------
	"fast_reveal": {"name": "Fast Reveal", "cat": "qol", "max": 1, "costs": [2500], "hall": 1, "effect": "Loot reveals play twice as fast", "icon": ["chevrons", "ffd34d"]},
	"presets":     {"name": "Loadout Presets", "cat": "qol", "max": 3, "costs": [15000, 150000, 1500000], "hall": 3, "effect": "+1 saved loadout (Weapon + Core parts), on the Armory's Presets row", "icon": ["box", "39e6ff"]},
	"auto_salvage": {"name": "Auto-Salvage", "cat": "qol", "max": 2, "costs": [20000, 200000], "hall": 3, "effect": "Smelt banked Commons (Lv 2: and Uncommons) on arrival, when switched on in the Armory", "icon": ["gear", "d9b98a"]},
	"auto_collect": {"name": "Auto-Collect", "cat": "qol", "max": 1, "costs": [30000], "hall": 3, "effect": "The Outpost collects its coins and Scrap by itself (Scavengers stay manual)", "icon": ["magnet", "4ade80"]},
	"bulk_upgrade": {"name": "Bulk Upgrade", "cat": "qol", "max": 1, "costs": [40000], "hall": 3, "effect": "Upgrade gear x5 or to its max in one click", "icon": ["chevrons", "4ade80"]},
	"auto_buy":    {"name": "Auto-Buy", "cat": "qol", "max": 1, "costs": [80000], "hall": 3, "req": [["enh_theory", 1]], "effect": "Runs spend spare cash on Core Enhancements by the rule you pick (AUTO in the run panel)", "icon": ["coin", "a3e635"]},
	"auto_restart": {"name": "Auto-Restart", "cat": "qol", "max": 1, "costs": [100000], "hall": 5, "effect": "A finished run starts the next one after 8 s, when switched on", "icon": ["rings", "4ade80"]},
}

## Display / iteration order (by category, cheapest first within a row).
const IDS: Array = [
	"dmg", "hp", "core_theory", "targeting", "optics", "reactor", "aegis", "shielding", "manual",
	"en_hp", "en_atk", "en_speed", "boss_breaker", "elite_hp", "sapper_damp",
	"coin", "startcash", "interest", "field_econ", "bounty", "offcap", "offrate", "lab_discount", "lic_mill", "lic_mine", "lic_scav", "lic_core", "lic_adv",
	"loot_theory", "appraisal", "cache_luck", "scav_rate", "reclaim",
	"stabilizer", "blacklist", "reroll_disc", "greater_cal", "enchanters_eye", "masterwork_odds", "brand_contracts", "mythic_fusion",
	"grid", "speed", "xp", "reroll", "banish_r", "draft_lock", "enh_theory", "draft_choices",
	"fast_reveal", "presets", "auto_salvage", "auto_collect", "bulk_upgrade", "auto_buy", "auto_restart",
]

const SPEED_STEPS: Array = [1.0, 1.5, 2.0, 2.5, 3.0]


static func max_of(id: String) -> int:
	var d: Dictionary = DEFS.get(id, {})
	return int(d.get("max", 0))


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func cat_ids(cat: String) -> Array:
	return IDS.filter(func(x: Variant) -> bool: return String((DEFS[x] as Dictionary)["cat"]) == cat)


static func cat_name(cat: String) -> String:
	for c in CATS:
		if String((c as Array)[0]) == cat:
			return String((c as Array)[1])
	return cat
