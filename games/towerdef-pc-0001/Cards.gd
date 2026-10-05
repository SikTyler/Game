extends RefCounted
## Cards (SPEC A7). save["cards"] = {owned:{id:{lvl,copies}}, equipped:[id], slots:int}.
## Cards come from chests only (no gems, no paid currency).

const CardDB := preload("res://data/CardDB.gd")
const TuneRef := preload("res://Tune.gd")

const MIN_SLOTS: int = 2
const MAX_SLOTS: int = 5


static func _c(s: Dictionary) -> Dictionary:
	return s["cards"]


static func owned(s: Dictionary) -> Dictionary:
	return _c(s)["owned"]


static func equipped(s: Dictionary) -> Array:
	return _c(s)["equipped"]


static func slots(s: Dictionary) -> int:
	return int(_c(s)["slots"])


static func level(s: Dictionary, id: String) -> int:
	var o: Dictionary = owned(s).get(id, {})
	return int(o.get("lvl", 0))


## Card chest price in COINS (owner feedback #1: gems / premium currency removed).
static func chest_cost() -> int:
	return TuneRef.int_of("chest_coins", 400)


static func open_chest(s: Dictionary, rng: RandomNumberGenerator, free: bool = false) -> Array:
	var c: int = 0 if free else chest_cost()
	if int(s["coins"]) < c:
		return []
	s["coins"] = int(s["coins"]) - c
	var id: String = String(CardDB.IDS[rng.randi_range(0, CardDB.IDS.size() - 1)])
	var own: Dictionary = owned(s)
	var is_new: bool = not own.has(id)
	var lvl_up: bool = false
	if is_new:
		own[id] = {"lvl": 1, "copies": 0}
	else:
		var e: Dictionary = own[id]
		var lvl: int = int(e["lvl"])
		if lvl < CardDB.MAX_LVL:
			var copies: int = int(e["copies"]) + 1
			if copies >= lvl:
				copies -= lvl
				lvl += 1
				lvl_up = true
			e["lvl"] = lvl
			e["copies"] = copies if lvl < CardDB.MAX_LVL else 0
	var e2: Dictionary = own[id]
	return [{"t": "chest_opened", "card": id, "new": is_new, "lvl_up": lvl_up, "lvl": int(e2["lvl"]), "coins": c}]


static func equip(s: Dictionary, id: String) -> Array:
	var eq: Array = equipped(s)
	if not owned(s).has(id) or eq.has(id) or eq.size() >= slots(s):
		return []
	eq.append(id)
	return [{"t": "card_equipped", "card": id}]


static func unequip(s: Dictionary, id: String) -> Array:
	var eq: Array = equipped(s)
	if not eq.has(id):
		return []
	eq.erase(id)
	return [{"t": "card_unequipped", "card": id}]


static func slot_cost(s: Dictionary) -> int:
	match slots(s):
		2:
			return TuneRef.int_of("card_slot_coins_3", 1500)
		3:
			return TuneRef.int_of("card_slot_coins_4", 4000)
		4:
			return TuneRef.int_of("card_slot_coins_5", 10000)
	return 0


static func buy_slot(s: Dictionary) -> Array:
	var n: int = slots(s)
	if n >= MAX_SLOTS:
		return []
	var c: int = slot_cost(s)
	if int(s["coins"]) < c:
		return []
	s["coins"] = int(s["coins"]) - c
	_c(s)["slots"] = n + 1
	return [{"t": "card_slot", "n": n + 1, "coins": c}]


## Merged effects of the equipped cards only.
static func mods(s: Dictionary) -> Dictionary:
	var m: Dictionary = {"dmg": 0.0, "hp": 0.0, "cash": 0.0, "coin": 0.0, "xp": 0.0, "reroll": 0, "wind_hp": 0.0, "skip_chance": 0.0}
	for idv in equipped(s):
		var id: String = String(idv)
		var d: Dictionary = CardDB.DEFS.get(id, {})
		if d.is_empty():
			continue
		var key: String = String(d["key"])
		var v: float = CardDB.value(id, level(s, id))
		if key == "reroll":
			m["reroll"] = int(m["reroll"]) + int(v)
		else:
			m[key] = float(m[key]) + v
	return m


static func modifiers(s: Dictionary) -> Dictionary:
	return mods(s)
