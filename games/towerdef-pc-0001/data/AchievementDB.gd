extends RefCounted
## PC achievements (PC_SPEC §5). Pure data; Achievements.gd evaluates them
## and SteamService mirrors unlocks. Steam API names == ids.
## kind: "run"    -> checked on game_over / in-run events (field: what)
##       "save"   -> checked against the persistent save after any meta change

const LIST: Array = [
	{"id": "ACH_FIRST_RUN",     "name": "First Light",     "desc": "Finish any run"},
	{"id": "ACH_WAVE_25",       "name": "Holding Pattern", "desc": "Reach wave 25"},
	{"id": "ACH_WAVE_100",      "name": "Centurion",       "desc": "Reach wave 100"},
	{"id": "ACH_WAVE_250",      "name": "Unbreakable",     "desc": "Reach wave 250 in endless"},
	{"id": "ACH_TIER_3",        "name": "Tiered Up",       "desc": "Unlock Tier 3"},
	{"id": "ACH_TIER_8",        "name": "Apex",            "desc": "Unlock Tier 8"},
	{"id": "ACH_FIRST_BOSS",    "name": "Big Game",        "desc": "Kill a boss"},
	{"id": "ACH_BOSS_50",       "name": "Boss Hunter",     "desc": "Kill 50 bosses (lifetime)"},
	{"id": "ACH_KILLS_100K",    "name": "Exterminator",    "desc": "100,000 lifetime kills"},
	{"id": "ACH_KILLS_1M",      "name": "Exterminator II", "desc": "1,000,000 lifetime kills"},
	{"id": "ACH_KILLS_10M",     "name": "Exterminator III", "desc": "10,000,000 lifetime kills"},
	{"id": "ACH_TIDE",          "name": "The Tide",        "desc": "Survive a wave with 10,000 enemies alive at once"},
	{"id": "ACH_WALL_FLESH",    "name": "Wall of Flesh",   "desc": "A single Wall slows 2,000 enemies in one wave"},
	{"id": "ACH_PART_SEA",      "name": "Parting the Sea", "desc": "Knock back 500 enemies with a single blast"},
	{"id": "ACH_ALL_SYNERGY",   "name": "Networked",       "desc": "Have 6 synergies active at once in a run"},
	{"id": "ACH_ECO_ONLY",      "name": "Merchant Prince", "desc": "Reach wave 30 with no weapon buildings"},
	{"id": "ACH_NO_ECO",        "name": "Iron Doctrine",   "desc": "Reach wave 60 with no eco buildings"},
	{"id": "ACH_LABS_MAX",      "name": "Mad Scientist",   "desc": "Max any lab track"},
	{"id": "ACH_MOD_3",         "name": "Masochist",       "desc": "Clear wave 50 with 3+ modifiers"},
	{"id": "ACH_GLASS_50",      "name": "Glass Cannon",    "desc": "Reach wave 50 with Glass Core"},
	{"id": "ACH_ENCIRCLED_100", "name": "Surrounded",      "desc": "Reach wave 100 with Encircled"},
	{"id": "ACH_NO_DAMAGE_10",  "name": "Untouched",       "desc": "Clear waves 1-10 without core damage"},
	{"id": "ACH_SPEEDRUN",      "name": "Overclocked",     "desc": "Reach wave 40 within 10 minutes of game time"},
	{"id": "ACH_STREAK_7",      "name": "Regular",         "desc": "Reach a 7-day login streak"},
	{"id": "ACH_MISSIONS_50",   "name": "Contractor",      "desc": "Claim 50 missions"},
	{"id": "ACH_ENDLESS",       "name": "No End",          "desc": "Unlock endless mode"},
	# Redesign / V2: all save-based.
	{"id": "ACH_FIRST_REFORGE", "name": "Reforged",        "desc": "Complete a Core Reforge"},
	{"id": "ACH_REFORGE_5",     "name": "Phoenix Core",    "desc": "Complete 5 Core Reforges"},
	{"id": "ACH_GEM_MINE",      "name": "Prospector",      "desc": "Build a Deep Mine in the Outpost"},
	{"id": "ACH_COURIER",       "name": "Intercepted",     "desc": "Catch a Courier"},
	{"id": "ACH_OUTPOST_FULL",  "name": "Frontier Settled", "desc": "Buy every land plot of the Outpost"},
	{"id": "ACH_INSIGHT_10",    "name": "Insightful",      "desc": "Bank 10 Insight picks"},
	{"id": "ACH_SPECIAL_100",   "name": "Ability Spammer", "desc": "Cast 100 special attacks"},
]

const SYNERGY_TARGET: int = 6
const SPEEDRUN_WAVE: int = 40
const SPEEDRUN_S: float = 600.0


static func ids() -> Array:
	var out: Array = []
	for a in LIST:
		out.append(String((a as Dictionary)["id"]))
	return out


static func get_def(id: String) -> Dictionary:
	for a in LIST:
		if String((a as Dictionary)["id"]) == id:
			return a
	return {}
