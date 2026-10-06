extends RefCounted
## Run building merges (V2 P7a). Two buildings of the same id and tier merge
## into one of tier + 1 (T1 -> T2 -> T3, x TIER_MULT base each); a duplicate
## draft card dropped on a T1 is a merge too. Reaching T2 offers the
## building's 3 mods (pick 1), reaching T3 its 2 capstones (pick 1). Mods
## stack on the building (merging two T2s keeps both their mods).
##   mod: {name, desc, fx{key: v}}
## fx vocabulary (TowerState.compute_stats reads it per building):
##   dmg / rate      +x of the building's damage / attack rate
##   range           +cells of reach
##   crit            +crit chance on this building's shots
##   pierce          +bodies a Gatling round / Railgun lane passes
##   splash          +x of the Mortar's blast radius
##   knock           +x of the Mortar's knockback
##   chains / arcs   +Tesla jumps / +forks per discharge
##   rounds          +Gatling rounds per shot
##   cone / burn     +x Flamer reach / burn damage
##   slow            +Cryo slow (fraction)
##   boss            +x of the Railgun's first-elite multiplier
##   arc             +degrees of traverse / cone width
##   power           +x of a support / eco / hut building's main effect
##   reach           +cells of a Beacon / Bounty Post / Armory's reach
##   quiet           an Oil Mill no longer slows its neighbours
## Tune pc_tier_mult overrides TIER_MULT.

const TuneRef := preload("res://Tune.gd")
const SupportDB := preload("res://data/SupportDB.gd")

const TIER_MULT: float = 1.8
const MAX_TIER: int = 3

const MODS: Dictionary = {
	"gun": {
		"t2": [
			{"name": "Hollow Points", "desc": "+30% damage", "fx": {"dmg": 0.30}},
			{"name": "Belt Feed", "desc": "+30% fire rate", "fx": {"rate": 0.30}},
			{"name": "Tungsten Core", "desc": "Rounds pierce +4 bodies", "fx": {"pierce": 4.0}},
		],
		"t3": [
			{"name": "Triple Barrel", "desc": "Fires 3 rounds per shot (was 2)", "fx": {"rounds": 1.0}},
			{"name": "Wide Mount", "desc": "Traverse 120 -> 200 deg, +1 range", "fx": {"arc": 80.0, "range": 1.0}},
		],
	},
	"mortar": {
		"t2": [
			{"name": "Big Shells", "desc": "+40% blast radius", "fx": {"splash": 0.40}},
			{"name": "Fast Loader", "desc": "+35% fire rate", "fx": {"rate": 0.35}},
			{"name": "Long Tube", "desc": "+1.5 range", "fx": {"range": 1.5}},
		],
		"t3": [
			{"name": "Seismic Charge", "desc": "+60% damage, knockback x2", "fx": {"dmg": 0.60, "knock": 1.0}},
			{"name": "Carpet Shells", "desc": "+80% blast radius", "fx": {"splash": 0.80}},
		],
	},
	"tesla": {
		"t2": [
			{"name": "Long Arcs", "desc": "+4 chain jumps", "fx": {"chains": 4.0}},
			{"name": "Capacitor Bank", "desc": "+35% damage", "fx": {"dmg": 0.35}},
			{"name": "Rapid Discharge", "desc": "+30% fire rate", "fx": {"rate": 0.30}},
		],
		"t3": [
			{"name": "Storm Crown", "desc": "+2 forks per discharge", "fx": {"arcs": 2.0}},
			{"name": "Overvolt", "desc": "+60% damage, +1 range", "fx": {"dmg": 0.60, "range": 1.0}},
		],
	},
	"flak": {
		"t2": [
			{"name": "Pressure Nozzle", "desc": "+40% flame reach", "fx": {"cone": 0.40}},
			{"name": "Napalm Mix", "desc": "+60% burn damage", "fx": {"burn": 0.60}},
			{"name": "Wide Spray", "desc": "Cone 50 -> 80 deg", "fx": {"arc": 30.0}},
		],
		"t3": [
			{"name": "Inferno", "desc": "+100% burn damage, +20% reach", "fx": {"burn": 1.0, "cone": 0.20}},
			{"name": "Twin Jets", "desc": "+60% fire rate", "fx": {"rate": 0.60}},
		],
	},
	"railgun": {
		"t2": [
			{"name": "Heavy Slug", "desc": "+35% damage", "fx": {"dmg": 0.35}},
			{"name": "Coil Cooling", "desc": "+30% fire rate", "fx": {"rate": 0.30}},
			{"name": "Wide Bore", "desc": "+50% lane width", "fx": {"pierce": 7.0}},
		],
		"t3": [
			{"name": "Kingslayer", "desc": "First elite / boss hit x7 (was x4)", "fx": {"boss": 3.0}},
			{"name": "Hyper Rail", "desc": "+70% damage, +2 range", "fx": {"dmg": 0.70, "range": 2.0}},
		],
	},
	"frost": {
		"t2": [
			{"name": "Deep Freeze", "desc": "+15% slow", "fx": {"slow": 0.15}},
			{"name": "Wide Chill", "desc": "+1 range", "fx": {"range": 1.0}},
			{"name": "Frostbite", "desc": "+100% chill damage", "fx": {"dmg": 1.0}},
		],
		"t3": [
			{"name": "Absolute Zero", "desc": "+20% slow, +1 range", "fx": {"slow": 0.20, "range": 1.0}},
			{"name": "Shatter Field", "desc": "+250% chill damage", "fx": {"dmg": 2.5}},
		],
	},
	# ---- V2 P7d weapons ---------------------------------------------------
	"pulse": {
		"t2": [
			{"name": "Wide Pulse", "desc": "+0.8 range", "fx": {"range": 0.8}},
			{"name": "Heavy Pulse", "desc": "+40% damage", "fx": {"dmg": 0.40}},
			{"name": "Rapid Pulse", "desc": "+35% pulse rate", "fx": {"rate": 0.35}},
		],
		"t3": [
			{"name": "Shock Ring", "desc": "+80% damage, knockback x2", "fx": {"dmg": 0.80, "knock": 1.0}},
			{"name": "Resonance", "desc": "+60% rate, +0.5 range", "fx": {"rate": 0.60, "range": 0.5}},
		],
	},
	"missile": {
		"t2": [
			{"name": "Extra Pods", "desc": "+2 missiles per salvo", "fx": {"missiles": 2.0}},
			{"name": "HE Warheads", "desc": "+50% blast radius", "fx": {"splash": 0.50}},
			{"name": "Fast Reload", "desc": "+35% salvo rate", "fx": {"rate": 0.35}},
		],
		"t3": [
			{"name": "Swarm Rack", "desc": "+4 missiles per salvo", "fx": {"missiles": 4.0}},
			{"name": "Bunker Busters", "desc": "+80% damage, +10% crit", "fx": {"dmg": 0.80, "crit": 0.10}},
		],
	},
	"spike": {
		"t2": [
			{"name": "Barbs", "desc": "+60% damage", "fx": {"dmg": 0.60}},
			{"name": "Long Spikes", "desc": "+0.6 range", "fx": {"range": 0.6}},
			{"name": "Pistons", "desc": "+35% stab rate", "fx": {"rate": 0.35}},
		],
		"t3": [
			{"name": "Impaler", "desc": "+150% damage", "fx": {"dmg": 1.5}},
			{"name": "Thicket", "desc": "+1 range, +40% damage", "fx": {"range": 1.0, "dmg": 0.40}},
		],
	},
	"mines": {
		"t2": [
			{"name": "Shaped Charge", "desc": "+40% damage", "fx": {"dmg": 0.40}},
			{"name": "Wide Blast", "desc": "+40% blast radius", "fx": {"splash": 0.40}},
			{"name": "Quick Seed", "desc": "+35% laying rate", "fx": {"rate": 0.35}},
		],
		"t3": [
			{"name": "Carpet Mines", "desc": "+70% laying rate", "fx": {"rate": 0.70}},
			{"name": "Thermobaric", "desc": "+90% damage, +30% blast", "fx": {"dmg": 0.90, "splash": 0.30}},
		],
	},
	"scatter": {
		"t2": [
			{"name": "Full Choke", "desc": "+3 pellets", "fx": {"pellets": 3.0}},
			{"name": "Slugs", "desc": "+35% damage", "fx": {"dmg": 0.35}},
			{"name": "Pump Action", "desc": "+30% fire rate", "fx": {"rate": 0.30}},
		],
		"t3": [
			{"name": "Dragon Breath", "desc": "+6 pellets", "fx": {"pellets": 6.0}},
			{"name": "Wide Spread", "desc": "Cone 60 -> 100 deg, +40% damage", "fx": {"arc": 40.0, "dmg": 0.40}},
		],
	},
	"laser": {
		"t2": [
			{"name": "Focusing Array", "desc": "Ramps to x4 (was x3)", "fx": {"ramp": 1.0}},
			{"name": "Wide Beam", "desc": "+60% beam width", "fx": {"pierce": 5.0}},
			{"name": "Hot Emitter", "desc": "+35% damage", "fx": {"dmg": 0.35}},
		],
		"t3": [
			{"name": "Death Ray", "desc": "Ramps to x5, +30% damage", "fx": {"ramp": 2.0, "dmg": 0.30}},
			{"name": "Prism Split", "desc": "+70% damage, +1 range", "fx": {"dmg": 0.70, "range": 1.0}},
		],
	},
	"saw": {
		"t2": [
			{"name": "Ricochet Edge", "desc": "+2 bounces", "fx": {"bounces": 2.0}},
			{"name": "Serrated", "desc": "+40% damage", "fx": {"dmg": 0.40}},
			{"name": "Spinner", "desc": "+30% fire rate", "fx": {"rate": 0.30}},
		],
		"t3": [
			{"name": "Buzzsaw Storm", "desc": "+4 bounces, +20% damage", "fx": {"bounces": 4.0, "dmg": 0.20}},
			{"name": "Diamond Blade", "desc": "+90% damage, +10% crit", "fx": {"dmg": 0.90, "crit": 0.10}},
		],
	},
	"arcproj": {
		"t2": [
			{"name": "Long Arcs", "desc": "+3 jumps", "fx": {"chains": 3.0}},
			{"name": "Forked", "desc": "+1 fork", "fx": {"arcs": 1.0}},
			{"name": "High Voltage", "desc": "+35% damage", "fx": {"dmg": 0.35}},
		],
		"t3": [
			{"name": "Ball Lightning", "desc": "+2 forks, +3 jumps", "fx": {"arcs": 2.0, "chains": 3.0}},
			{"name": "Arc Flash", "desc": "+80% damage, +30% rate", "fx": {"dmg": 0.80, "rate": 0.30}},
		],
	},
	"sonic": {
		"t2": [
			{"name": "Bass Drop", "desc": "Knockback x1.6", "fx": {"knock": 0.60}},
			{"name": "Wide Horn", "desc": "Cone 70 -> 100 deg", "fx": {"arc": 30.0}},
			{"name": "Overdrive", "desc": "+50% damage", "fx": {"dmg": 0.50}},
		],
		"t3": [
			{"name": "Sonic Boom", "desc": "+120% damage, +0.5 range", "fx": {"dmg": 1.2, "range": 0.5}},
			{"name": "Shock Front", "desc": "Knockback x2.2, +40% rate", "fx": {"knock": 1.2, "rate": 0.40}},
		],
	},
	"harpoon": {
		"t2": [
			{"name": "Barbed Tip", "desc": "x4 on elites / bosses (was x2.5)", "fx": {"elite": 1.5}},
			{"name": "Winch", "desc": "+35% fire rate", "fx": {"rate": 0.35}},
			{"name": "Long Line", "desc": "+1.5 range", "fx": {"range": 1.5}},
		],
		"t3": [
			{"name": "Whaler", "desc": "+100% damage, x5 on elites", "fx": {"dmg": 1.0, "elite": 1.0}},
			{"name": "Twin Launcher", "desc": "+70% fire rate, +15% crit", "fx": {"rate": 0.70, "crit": 0.15}},
		],
	},
	"plasma": {
		"t2": [
			{"name": "Hotter Plasma", "desc": "+60% burn", "fx": {"burn": 0.60}},
			{"name": "Wide Field", "desc": "+50% lane width", "fx": {"pierce": 5.0}},
			{"name": "Long Fence", "desc": "+1.5 range", "fx": {"range": 1.5}},
		],
		"t3": [
			{"name": "Star Core", "desc": "+120% burn, +30% damage", "fx": {"burn": 1.2, "dmg": 0.30}},
			{"name": "Overcharge", "desc": "+60% rate, +1 range", "fx": {"rate": 0.60, "range": 1.0}},
		],
	},
	"flakburst": {
		"t2": [
			{"name": "Big Shells", "desc": "+40% burst radius", "fx": {"splash": 0.40}},
			{"name": "Proximity Fuse", "desc": "+35% damage", "fx": {"dmg": 0.35}},
			{"name": "Autoloader", "desc": "+35% fire rate", "fx": {"rate": 0.35}},
		],
		"t3": [
			{"name": "Cluster Flak", "desc": "+80% radius, +30% damage", "fx": {"splash": 0.80, "dmg": 0.30}},
			{"name": "Flak Curtain", "desc": "+70% rate, traverse 120 -> 200 deg", "fx": {"rate": 0.70, "arc": 80.0}},
		],
	},
	"armory": {
		"t2": [
			{"name": "Ammo Racks", "desc": "+50% to its damage buff", "fx": {"power": 0.50}},
			{"name": "Supply Lines", "desc": "Buffs buildings within 2 cells", "fx": {"reach": 1.0}},
			{"name": "Armour-Piercing", "desc": "Buffed buildings +5% crit", "fx": {"crit": 0.05}},
		],
		"t3": [
			{"name": "War Depot", "desc": "+100% to its damage buff", "fx": {"power": 1.0}},
			{"name": "Logistics Hub", "desc": "Buffs buildings within 3 cells", "fx": {"reach": 2.0}},
		],
	},
	"beacon": {
		"t2": [
			{"name": "Amplified", "desc": "+50% to its rate / range buff", "fx": {"power": 0.50}},
			{"name": "Tall Mast", "desc": "+2 cells reach", "fx": {"reach": 2.0}},
			{"name": "Overclock", "desc": "+60% to its rate buff (range buff unchanged)", "fx": {"power": 0.30, "rate": 0.30}},
		],
		"t3": [
			{"name": "Lighthouse", "desc": "+4 cells reach", "fx": {"reach": 4.0}},
			{"name": "Focus Lens", "desc": "+100% to its buffs", "fx": {"power": 1.0}},
		],
	},
	"bulwark": {
		"t2": [
			{"name": "Thick Plates", "desc": "+60% Core HP from it", "fx": {"power": 0.60}},
			{"name": "Reinforced", "desc": "+40% HP, +1 armor", "fx": {"power": 0.40, "armor": 1.0}},
			{"name": "Repair Drones", "desc": "+30% HP, +2 regen", "fx": {"power": 0.30, "regen": 2.0}},
		],
		"t3": [
			{"name": "Citadel", "desc": "+120% Core HP from it", "fx": {"power": 1.2}},
			{"name": "Ironclad", "desc": "+60% HP, +3 armor", "fx": {"power": 0.60, "armor": 3.0}},
		],
	},
	"aegis": {
		"t2": [
			{"name": "Dense Field", "desc": "+60% shield", "fx": {"power": 0.60}},
			{"name": "Quick Recharge", "desc": "+40% shield, +6 regen", "fx": {"power": 0.40, "regen": 6.0}},
			{"name": "Hard Light", "desc": "+30% shield, +1 armor", "fx": {"power": 0.30, "armor": 1.0}},
		],
		"t3": [
			{"name": "Bastion Field", "desc": "+120% shield", "fx": {"power": 1.2}},
			{"name": "Phase Shell", "desc": "+60% shield, +3 armor", "fx": {"power": 0.60, "armor": 3.0}},
		],
	},
	"barricade": {
		"t2": [
			{"name": "Razor Wire", "desc": "Slow aura +15%", "fx": {"slow": 0.15}},
			{"name": "Spikes", "desc": "Bodies by it take 4 dmg/s", "fx": {"dmg": 4.0}},
			{"name": "Wide Base", "desc": "+1 aura range", "fx": {"range": 1.0}},
		],
		"t3": [
			{"name": "Tar Pit", "desc": "Slow aura +25%", "fx": {"slow": 0.25}},
			{"name": "Killing Floor", "desc": "Bodies by it take 12 dmg/s", "fx": {"dmg": 12.0}},
		],
	},
	"mine": {
		"t2": [
			{"name": "Deep Shaft", "desc": "+60% cash", "fx": {"power": 0.60}},
			{"name": "Assayer", "desc": "+40% cash, +5% kill cash", "fx": {"power": 0.40, "kill_cash": 0.05}},
			{"name": "Night Shift", "desc": "+40% cash, +5% XP", "fx": {"power": 0.40, "xp": 0.05}},
		],
		"t3": [
			{"name": "Mother Lode", "desc": "+120% cash", "fx": {"power": 1.2}},
			{"name": "Bullion", "desc": "+60% cash, +1% interest", "fx": {"power": 0.60, "interest": 0.01}},
		],
	},
	"oilmill": {
		"t2": [
			{"name": "Muffled", "desc": "No longer slows neighbours", "fx": {"quiet": 1.0}},
			{"name": "Cracker", "desc": "+60% cash", "fx": {"power": 0.60}},
			{"name": "Fuel Line", "desc": "+30% cash, neighbours +5% damage", "fx": {"power": 0.30, "adj_dmg": 0.05}},
		],
		"t3": [
			{"name": "Refinery Row", "desc": "+120% cash", "fx": {"power": 1.2}},
			{"name": "Clean Burn", "desc": "+50% cash, no slowing", "fx": {"power": 0.50, "quiet": 1.0}},
		],
	},
	"bounty": {
		"t2": [
			{"name": "Big Bounties", "desc": "+60% to its kill cash", "fx": {"power": 0.60}},
			{"name": "Wanted Posters", "desc": "+1 cell reach", "fx": {"reach": 1.0}},
			{"name": "Headhunter", "desc": "+30% kill cash, +5% XP", "fx": {"power": 0.30, "xp": 0.05}},
		],
		"t3": [
			{"name": "Guild Hall", "desc": "+2 cells reach", "fx": {"reach": 2.0}},
			{"name": "Blood Money", "desc": "+120% to its kill cash", "fx": {"power": 1.2}},
		],
	},
	"vault": {
		"t2": [
			{"name": "Compound", "desc": "+60% interest", "fx": {"power": 0.60}},
			{"name": "Strongroom", "desc": "+100% interest cap", "fx": {"cap": 1.0}},
			{"name": "Dividends", "desc": "+30% interest, +0.5 cash/s", "fx": {"power": 0.30, "cash": 0.5}},
		],
		"t3": [
			{"name": "Central Bank", "desc": "+120% interest", "fx": {"power": 1.2}},
			{"name": "Treasure Hoard", "desc": "+200% interest cap", "fx": {"cap": 2.0}},
		],
	},
	"refinery": {
		"t2": [
			{"name": "Distillery", "desc": "+60% XP bonus", "fx": {"power": 0.60}},
			{"name": "Byproducts", "desc": "+100% cash", "fx": {"cash": 1.0}},
			{"name": "Lessons", "desc": "+30% XP bonus, +0.5 cash/s", "fx": {"power": 0.30, "cash": 0.5}},
		],
		"t3": [
			{"name": "Academy", "desc": "+120% XP bonus", "fx": {"power": 1.2}},
			{"name": "Cracking Tower", "desc": "+60% XP bonus, +200% cash", "fx": {"power": 0.60, "cash": 2.0}},
		],
	},
	"obelisk": {
		"t2": [
			{"name": "Blood Siphon", "desc": "+60% lifesteal", "fx": {"power": 0.60}},
			{"name": "Bone Ward", "desc": "+30% lifesteal, +1 armor", "fx": {"power": 0.30, "armor": 1.0}},
			{"name": "Vigil", "desc": "+30% lifesteal, +2 regen", "fx": {"power": 0.30, "regen": 2.0}},
		],
		"t3": [
			{"name": "Sanguine Spire", "desc": "+120% lifesteal", "fx": {"power": 1.2}},
			{"name": "Eternal Vigil", "desc": "+60% lifesteal, +6 regen", "fx": {"power": 0.60, "regen": 6.0}},
		],
	},
	"hut_infantry": {
		"t2": [
			{"name": "Veterans", "desc": "Troops +40% damage and HP", "fx": {"power": 0.40}},
			{"name": "Marksmen", "desc": "Troops +60% damage", "fx": {"troop_dmg": 0.60}},
			{"name": "Flak Vests", "desc": "Troops +80% HP", "fx": {"troop_hp": 0.80}},
		],
		"t3": [
			{"name": "Elite Squad", "desc": "Troops +80% damage and HP", "fx": {"power": 0.80}},
			{"name": "Iron Wall", "desc": "Troops +150% HP", "fx": {"troop_hp": 1.5}},
		],
	},
	"hut_sapper": {
		"t2": [
			{"name": "Bigger Bombs", "desc": "Sappers +60% damage", "fx": {"troop_dmg": 0.60}},
			{"name": "Quick Fuses", "desc": "Sappers +40% damage and HP", "fx": {"power": 0.40}},
			{"name": "Sprinters", "desc": "Sappers +80% HP", "fx": {"troop_hp": 0.80}},
		],
		"t3": [
			{"name": "Demolition Crew", "desc": "Sappers +120% damage", "fx": {"troop_dmg": 1.2}},
			{"name": "Shock Troops", "desc": "Sappers +80% damage and HP", "fx": {"power": 0.80}},
		],
	},
}

## V2 P7d templates for the data-driven buildings (SupportDB auras / core
## fx and the new huts); the Spike Gate uses the Wall's mods.
const TEMPLATES: Dictionary = {
	"aura": {
		"t2": [
			{"name": "Amplified Field", "desc": "+50% to its aura", "fx": {"power": 0.50}},
			{"name": "Wide Field", "desc": "+1 cell reach", "fx": {"reach": 1.0}},
			{"name": "Resonant Field", "desc": "+30% to its aura, +1 reach at T3 merges", "fx": {"power": 0.30}},
		],
		"t3": [
			{"name": "Overcharged Field", "desc": "+100% to its aura", "fx": {"power": 1.0}},
			{"name": "Broadcast", "desc": "+2 cells reach, +25% to its aura", "fx": {"reach": 2.0, "power": 0.25}},
		],
	},
	"core": {
		"t2": [
			{"name": "Amplified", "desc": "+50% to its effect", "fx": {"power": 0.50}},
			{"name": "Efficient", "desc": "+30% to its effect, +0.5 cash/s", "fx": {"power": 0.30, "cash": 0.5}},
			{"name": "Hardened", "desc": "+30% to its effect, +1 Core armor", "fx": {"power": 0.30, "armor": 1.0}},
		],
		"t3": [
			{"name": "Overdrive", "desc": "+100% to its effect", "fx": {"power": 1.0}},
			{"name": "Masterwork", "desc": "+60% to its effect, +2 Core regen", "fx": {"power": 0.60, "regen": 2.0}},
		],
	},
	"hut": {
		"t2": [
			{"name": "Veterans", "desc": "Troops +40% damage and HP", "fx": {"power": 0.40}},
			{"name": "Heavy Arms", "desc": "Troops +60% damage", "fx": {"troop_dmg": 0.60}},
			{"name": "Body Armor", "desc": "Troops +80% HP", "fx": {"troop_hp": 0.80}},
		],
		"t3": [
			{"name": "Elite Squad", "desc": "Troops +80% damage and HP", "fx": {"power": 0.80}},
			{"name": "Juggernauts", "desc": "Troops +150% HP", "fx": {"troop_hp": 1.5}},
		],
	},
}


## The mod table of a building: its own, else a template.
static func mods_of(id: String) -> Dictionary:
	if MODS.has(id):
		return MODS[id]
	if id == "gate":
		return MODS["barricade"]
	if id.begins_with("hut_"):
		return TEMPLATES["hut"]
	if SupportDB.has(id):
		return TEMPLATES["aura"] if SupportDB.get_def(id).has("aura") else TEMPLATES["core"]
	return {}


## Every fx key a mod may carry (the content check in st_merge).
const FX_KEYS: Array = ["dmg", "rate", "range", "crit", "pierce", "splash", "knock", "chains", "arcs", "rounds", "cone", "burn",
	"missiles", "pellets", "bounces", "ramp", "elite",
	"slow", "boss", "arc", "power", "reach", "quiet", "armor", "regen", "kill_cash", "xp", "interest", "cap", "cash",
	"adj_dmg", "troop_dmg", "troop_hp"]


static func tier_mult(tier: int) -> float:
	return pow(TuneRef.num("pc_tier_mult", TIER_MULT), float(clampi(tier, 1, MAX_TIER) - 1))


## The mods offered when a building of `id` reaches `tier` ([] when none).
static func offer(id: String, tier: int) -> Array:
	var d: Dictionary = mods_of(id)
	return (d.get("t%d" % tier, []) as Array)


## Mod `k` of the `tier` offer of `id` ({} when out of range).
static func mod_of(id: String, tier: int, k: int) -> Dictionary:
	var o: Array = offer(id, tier)
	return o[k] if k >= 0 and k < o.size() else {}


## Summed fx of a building's taken mods ([[tier, k], ...]).
static func fx_of(id: String, mods: Array) -> Dictionary:
	var out: Dictionary = {}
	for m in mods:
		var md: Dictionary = mod_of(id, int((m as Array)[0]), int((m as Array)[1]))
		for k in (md.get("fx", {}) as Dictionary).keys():
			out[k] = float(out.get(k, 0.0)) + float(md["fx"][k])
	return out
