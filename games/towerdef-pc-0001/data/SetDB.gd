extends RefCounted
## Part sets (REDESIGN_SYSTEMS §3.3). A set counts DISTINCT equipped members.
## 2-piece and 4-piece bonuses are fx dicts in PartDB units (Parts.run_fx adds
## them to the part sum). Equipping 4 distinct members at once (once ever)
## permanently unlocks the set's special part (PartDB.SPECIALS).
## Budget (POWER_MODEL §8 rule 4, B = budget of the set's best member rarity):
## 2-piece <= 0.5 B, 4-piece <= 1.2 B. Storm's 2-piece is re-tuned from "+1
## chain everywhere" (0.24 log-power, over its 0.085 cap) to +10% chain/Tesla
## damage; the +1 chain stays on Ringcaster.

const DEFS: Dictionary = {
	"bulwark": {"name": "Bulwark", "members": ["f_bulkhead", "f_regenmesh", "f_mirror", "e_bastionheart"], "special": "citadel_heart",
		"two": {"core_hp": 0.15}, "four": {"last_stand": 1}, "spec": "sustain"},
	"mint": {"name": "Mint", "members": ["f_ledgerframe", "b_bounty", "c_interest", "e_mintpress"], "special": "golden_ratio",
		"two": {"cash": 0.10}, "four": {"dividend": 0.20}, "spec": "eco"},
	"lancer": {"name": "Lancer", "members": ["b_hollow", "b_focuslens", "c_scope", "e_railcore"], "special": "singularity_lens",
		"two": {"core_dmg": 0.02}, "four": {"pierce": 1}, "spec": "single"},  # meta-economy: 2-piece 0.05 -> 0.02 (full set out-waved the single spec)
	"storm": {"name": "Storm", "members": ["b_scatter", "b_ringcaster", "c_battery", "c_capacitor_arc"], "special": "eye_of_storm",
		"two": {"chain_dmg": 0.10}, "four": {"storm_pulse": 1}, "spec": "area"},
	"swarm": {"name": "Swarm", "members": ["f_hivecomb", "b_droneport", "c_pheromone", "e_queen"], "special": "brood_mother",
		"two": {"troop_hp": 0.15, "troop_dmg": 0.15}, "four": {"troop_ls": 1, "queen_hold": -1, "dmg": 0.13}, "spec": "troops"},
}

const IDS: Array = ["bulwark", "mint", "lancer", "storm", "swarm"]
const RANK: Dictionary = {"common": 0, "rare": 1, "epic": 2, "legendary": 3}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func special_of(set_id: String) -> String:
	return String(get_def(set_id).get("special", ""))


## The best member rarity (the set's budget rarity).
static func budget_rarity(set_id: String, part_rarity: Callable) -> String:
	var best: String = "common"
	for m in get_def(set_id).get("members", []):
		var r: String = String(part_rarity.call(String(m)))
		if int(RANK.get(r, 0)) > int(RANK.get(best, 0)):
			best = r
	return best
