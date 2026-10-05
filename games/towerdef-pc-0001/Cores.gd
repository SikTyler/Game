extends RefCounted
## Core meta rules (V2: one Core). Pure static functions over the save:
##   save.core = {lvl: int}   (P4 adds look / loadout; P6 adds level requirements)
## Level cost L -> L+1: round(base * growth^(L-1)) coins (pc_core_cost_base 250,
## pc_core_cost_growth 1.18). P6 gates milestone levels behind Outpost
## buildings and research (CoreLevelDB).

const CoreDB := preload("res://data/CoreDB.gd")
const TuneRef := preload("res://Tune.gd")


static func default_block() -> Dictionary:
	return {"lvl": 1}


## Coerce a raw (JSON) core block.
static func normalize_block(raw: Variant, max_lvl: int = CoreDB.MAX_LVL) -> Dictionary:
	var d: Dictionary = default_block()
	if raw is Dictionary:
		d["lvl"] = clampi(int((raw as Dictionary).get("lvl", 1)), 1, max_lvl)
		for k in (raw as Dictionary).keys():
			if String(k) != "lvl":
				d[String(k)] = (raw as Dictionary)[k]
	return d


static func _block(s: Dictionary) -> Dictionary:
	if not (s.get("core", null) is Dictionary):
		s["core"] = default_block()
	return s["core"]


## Kept for callers that still name the Core (always "core").
static func active(_s: Dictionary = {}) -> String:
	return CoreDB.ID


static func level(s: Dictionary, _id: String = "") -> int:
	var b: Variant = s.get("core", null)
	if b is Dictionary:
		return maxi(1, int((b as Dictionary).get("lvl", 1)))
	return 1


## 60, or 75 with the Reforge node core_ceiling (save.reforge.nodes).
static func max_level(s: Dictionary) -> int:
	var rf: Variant = s.get("reforge", null)
	if rf is Dictionary:
		var nodes: Variant = (rf as Dictionary).get("nodes", {})
		if nodes is Dictionary and int((nodes as Dictionary).get("core_ceiling", 0)) > 0:
			return CoreDB.max_lvl_ceiling()
	return CoreDB.max_lvl()


static func level_cost(lvl: int) -> Dictionary:
	return {"coins": int(round(TuneRef.num("pc_core_cost_base", 250.0) * pow(TuneRef.num("pc_core_cost_growth", 1.18), float(maxi(1, lvl) - 1))))}


static func can_level(s: Dictionary, _id: String = "") -> bool:
	var lv: int = level(s)
	if lv >= max_level(s):
		return false
	return int(s.get("coins", 0)) >= int(level_cost(lv)["coins"])


## Spend coins on a permanent Core level.
static func try_level(s: Dictionary, _id: String = "") -> Array:
	if not can_level(s):
		return []
	var lv: int = level(s)
	var c: int = int(level_cost(lv)["coins"])
	s["coins"] = int(s["coins"]) - c
	_block(s)["lvl"] = lv + 1
	return [{"t": "core_level", "core": CoreDB.ID, "level": lv + 1, "coins": c}]
