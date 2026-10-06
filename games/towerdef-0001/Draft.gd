extends RefCounted
## Level-up draft: 3 seeded building cards. A card is NEW (place a run-only
## building into a free slot) or PLUS (+1 run level on an owned type).
## The offer always tries to include one weapon AND one eco card, so every
## level-up poses the eco-vs-defense tradeoff.

const BuildingDB := preload("res://data/BuildingDB.gd")


static func offer(rng: RandomNumberGenerator, slots: Array, unlocked: Array, allow_new: bool = false) -> Array:
	var has_free: bool = false
	var owned: Dictionary = {}
	for i in 25:
		var s: Dictionary = slots[i]
		if s.is_empty():
			if i != 12 and bool(unlocked[i]):
				has_free = true
		else:
			owned[String(s["id"])] = true
	var cands: Array = []
	for id in (BuildingDB.all_ids() if allow_new else BuildingDB.ids()):
		if owned.has(id):
			cands.append({"kind": "plus", "id": id})
		if has_free:
			cands.append({"kind": "new", "id": id})
	# Fisher-Yates on the seeded rng (Array.shuffle ignores the seed).
	for i in range(cands.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	var picks: Array = []
	var used: Dictionary = {}
	for want in ["weapon", "eco"]:
		for c in cands:
			var cd: Dictionary = c
			var id: String = cd["id"]
			if BuildingDB.cat_of(id) == want and not used.has(id):
				picks.append(cd)
				used[id] = true
				break
	for c in cands:
		if picks.size() >= 3:
			break
		var cd2: Dictionary = c
		var id2: String = cd2["id"]
		if not used.has(id2):
			picks.append(cd2)
			used[id2] = true
	return picks
