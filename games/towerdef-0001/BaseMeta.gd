extends RefCounted
## Permanent base (the meta layer, The Tower's "workshop" as buildings).
## Pure static functions over the save Dictionary — the view writes it to disk
## via MetaSave. Save shape:
##   {coins:int, core:{dmg,hp,regen}, slots:{"<idx>":{id,lvl}}, unlocked:[idx],
##    best_wave:int, runs:int}

const BuildingDB := preload("res://data/BuildingDB.gd")
const TuneRef := preload("res://Tune.gd")

const CORE_SLOT: int = 12
const CORE_STATS: Array = ["dmg", "hp", "regen"]
const MAX_LVL: int = 15


static func default_save() -> Dictionary:
	return {"coins": 0, "core": {"dmg": 0, "hp": 0, "regen": 0}, "slots": {}, "unlocked": [], "best_wave": 0, "runs": 0}


## Fill missing keys and coerce JSON floats back to ints.
static func normalize(s: Dictionary) -> Dictionary:
	var d: Dictionary = default_save()
	d["coins"] = int(s.get("coins", 0))
	d["best_wave"] = int(s.get("best_wave", 0))
	d["runs"] = int(s.get("runs", 0))
	var core_in: Dictionary = s.get("core", {})
	var core: Dictionary = {}
	for k in CORE_STATS:
		core[k] = int(core_in.get(k, 0))
	d["core"] = core
	var slots_in: Dictionary = s.get("slots", {})
	var slots: Dictionary = {}
	for key in slots_in.keys():
		var e: Dictionary = slots_in[key]
		var id: String = String(e.get("id", ""))
		if BuildingDB.DEFS.has(id):
			slots[str(int(key))] = {"id": id, "lvl": maxi(1, int(e.get("lvl", 1)))}
	d["slots"] = slots
	var un: Array = []
	for v in s.get("unlocked", []):
		un.append(int(v))
	d["unlocked"] = un
	return d


static func is_inner(i: int) -> bool:
	var dx: int = absi(i % 5 - 2)
	var dy: int = absi(i / 5 - 2)
	return dx <= 1 and dy <= 1 and i != CORE_SLOT


static func is_unlocked(s: Dictionary, i: int) -> bool:
	if i == CORE_SLOT:
		return false
	if is_inner(i):
		return true
	var un: Array = s["unlocked"]
	return un.has(i)


static func slot_of(s: Dictionary, i: int) -> Dictionary:
	var slots: Dictionary = s["slots"]
	return slots.get(str(i), {})


static func unlock_cost(s: Dictionary) -> int:
	var un: Array = s["unlocked"]
	return int(TuneRef.num("perm_unlock_base", 30.0) * pow(1.45, un.size()))


static func place_cost(id: String) -> int:
	var d: Dictionary = BuildingDB.get_def(id)
	return int(d.get("coin", 15))


static func upgrade_cost(lvl: int) -> int:
	return int(TuneRef.num("perm_upgrade_base", 15.0) * pow(1.55, lvl))


static func core_cost(lvl: int) -> int:
	return int(TuneRef.num("perm_core_base", 10.0) * pow(1.5, lvl))


static func try_unlock(s: Dictionary, i: int) -> bool:
	if i < 0 or i > 24 or is_unlocked(s, i) or i == CORE_SLOT:
		return false
	var c: int = unlock_cost(s)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	(s["unlocked"] as Array).append(i)
	return true


static func try_place(s: Dictionary, i: int, id: String) -> bool:
	if not is_unlocked(s, i) or not slot_of(s, i).is_empty() or not BuildingDB.DEFS.has(id):
		return false
	var c: int = place_cost(id)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	(s["slots"] as Dictionary)[str(i)] = {"id": id, "lvl": 1}
	return true


static func try_upgrade(s: Dictionary, i: int) -> bool:
	var e: Dictionary = slot_of(s, i)
	if e.is_empty():
		return false
	var lvl: int = int(e["lvl"])
	if lvl >= MAX_LVL:
		return false
	var c: int = upgrade_cost(lvl)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	e["lvl"] = lvl + 1
	return true


static func demolish(s: Dictionary, i: int) -> bool:
	var slots: Dictionary = s["slots"]
	return slots.erase(str(i))


static func try_core(s: Dictionary, stat: String) -> bool:
	var core: Dictionary = s["core"]
	if not core.has(stat):
		return false
	var lvl: int = int(core[stat])
	if lvl >= MAX_LVL:
		return false
	var c: int = core_cost(lvl)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	core[stat] = lvl + 1
	return true


## Bank a finished run's coins + record.
static func bank(s: Dictionary, coins: int, wave: int) -> void:
	s["coins"] = int(s["coins"]) + coins
	s["runs"] = int(s["runs"]) + 1
	s["best_wave"] = maxi(int(s["best_wave"]), wave)
