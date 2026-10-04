extends RefCounted
## Core roster meta rules (REDESIGN_SPEC §2.1): which Core is active, its
## permanent level (bought outside a run with coins + Core Cores) and the
## unlock conditions. Pure static functions over the save Dictionary:
##   save.cores = {active: id, owned: [ids], levels: {id: L}}
##   save.core_cores = int (Core Cores currency)
## Level cost L -> L+1: round(base * 1.18^(L-1)) coins + floor(L/5) Core Cores;
## base = pc_core_cost_base (spec 200, tuned to 250 for meta pacing).

const CoreDB := preload("res://data/CoreDB.gd")
const TuneRef := preload("res://Tune.gd")


static func default_block() -> Dictionary:
	return {"active": "bastion", "owned": ["bastion"], "levels": {"bastion": 1}}


## Coerce a raw (JSON) cores block: known ids only, levels clamped, the
## active Core always owned, Bastion always owned.
static func normalize_block(raw: Variant, max_lvl: int = CoreDB.MAX_LVL) -> Dictionary:
	var d: Dictionary = default_block()
	if not (raw is Dictionary):
		return d
	var r: Dictionary = raw
	var owned: Array = ["bastion"]
	for v in r.get("owned", []):
		var id: String = String(v)
		if CoreDB.has(id) and not owned.has(id):
			owned.append(id)
	var lv_in: Dictionary = r.get("levels", {}) if r.get("levels", {}) is Dictionary else {}
	var lv: Dictionary = {}
	for id in owned:
		lv[id] = clampi(int(lv_in.get(id, 1)), 1, max_lvl)
	var act: String = String(r.get("active", "bastion"))
	d["owned"] = owned
	d["levels"] = lv
	# Part presets (Parts.sanitize_presets validates them against the inventory).
	if r.get("presets", null) is Dictionary:
		d["presets"] = (r["presets"] as Dictionary).duplicate(true)
	if r.get("preset_idx", null) is Dictionary:
		d["preset_idx"] = (r["preset_idx"] as Dictionary).duplicate(true)
	d["active"] = act if owned.has(act) else "bastion"
	return d


static func _block(s: Dictionary) -> Dictionary:
	if not (s.get("cores", null) is Dictionary):
		s["cores"] = default_block()
	return s["cores"]


static func active(s: Dictionary) -> String:
	var b: Variant = s.get("cores", null)
	if b is Dictionary and CoreDB.has(String((b as Dictionary).get("active", ""))):
		return String((b as Dictionary)["active"])
	return "bastion"


static func owned(s: Dictionary) -> Array:
	var b: Variant = s.get("cores", null)
	if b is Dictionary:
		return ((b as Dictionary).get("owned", ["bastion"]) as Array).duplicate()
	return ["bastion"]


static func is_owned(s: Dictionary, id: String) -> bool:
	return owned(s).has(id)


static func level(s: Dictionary, id: String = "") -> int:
	var cid: String = active(s) if id == "" else id
	var b: Variant = s.get("cores", null)
	if b is Dictionary:
		var lv: Variant = (b as Dictionary).get("levels", {})
		if lv is Dictionary:
			return maxi(1, int((lv as Dictionary).get(cid, 1)))
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
	return {
		"coins": int(round(TuneRef.num("pc_core_cost_base", 250.0) * pow(TuneRef.num("pc_core_cost_growth", 1.18), float(maxi(1, lvl) - 1)))),
		"core_cores": maxi(1, lvl) / 5,
	}


static func can_level(s: Dictionary, id: String) -> bool:
	if not is_owned(s, id):
		return false
	var lv: int = level(s, id)
	if lv >= max_level(s):
		return false
	var c: Dictionary = level_cost(lv)
	return int(s.get("coins", 0)) >= int(c["coins"]) and int(s.get("core_cores", 0)) >= int(c["core_cores"])


## Spend coins (+ Core Cores every 5th level) on a permanent Core level.
static func try_level(s: Dictionary, id: String) -> Array:
	if not can_level(s, id):
		return []
	var lv: int = level(s, id)
	var c: Dictionary = level_cost(lv)
	s["coins"] = int(s["coins"]) - int(c["coins"])
	s["core_cores"] = int(s.get("core_cores", 0)) - int(c["core_cores"])
	var b: Dictionary = _block(s)
	(b["levels"] as Dictionary)[id] = lv + 1
	return [{"t": "core_level", "core": id, "level": lv + 1, "coins": int(c["coins"]), "core_cores": int(c["core_cores"])}]


static func select(s: Dictionary, id: String) -> Array:
	if not is_owned(s, id) or active(s) == id:
		return []
	_block(s)["active"] = id
	return [{"t": "core_selected", "core": id}]


## Unlock conditions (SYSTEMS §1.4, R8). ctx overrides for systems that live
## in later work packages: {reforges: int, set2: bool}. Defaults read the save.
static func unlock_met(s: Dictionary, id: String, ctx: Dictionary = {}) -> bool:
	match id:
		"bastion":
			return true
		"foundry":
			var bw: Variant = s.get("best_wave_by_tier", {})
			return bw is Dictionary and int((bw as Dictionary).get("2", 0)) >= TuneRef.int_of("pc_foundry_wave", 30)
		"lance":
			var rf: Variant = s.get("reforge", {})
			var n: int = int((rf as Dictionary).get("count", 0)) if rf is Dictionary else 0
			return int(ctx.get("reforges", n)) >= 1
		"tempest":
			return bool(ctx.get("set2", false)) and int(s.get("best_wave", 0)) >= 60
	return false


## Grant every Core whose condition is now met; returns core_unlocked events.
static func check_unlocks(s: Dictionary, ctx: Dictionary = {}) -> Array:
	var ev: Array = []
	for id in CoreDB.IDS:
		var cid: String = id
		if is_owned(s, cid) or not unlock_met(s, cid, ctx):
			continue
		var b: Dictionary = _block(s)
		(b["owned"] as Array).append(cid)
		(b["levels"] as Dictionary)[cid] = 1
		ev.append({"t": "core_unlocked", "core": cid})
	return ev
