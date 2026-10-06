extends RefCounted
## The Outpost (REDESIGN_SPEC §3.2, SYSTEMS §5): a persistent base built
## outside runs. Pure static rules over save.outpost with an injected `now`
## (unix seconds) for every time-dependent call:
## V2 P6: a 48x32 map of small cells, Core buildings (permanent Core stats
## via core_bonus -> BaseMeta.run_mods), scavengers (gear tokens banked with
## Loot.realize), signed AdjDB adjacency (layout_bonus), Relay-level unlocks.
##   outpost = {relay_lvl, plots: [k], next_uid, credit,
##     buildings: {"<uid>": {id, x, y, rot, lvl, stored, last_tick, built, spent}},
##     queue: [{uid, kind: "build"|"upgrade", ends_at}], (uid "relay" = Relay)
##     decor: {"<uid>": {id, x, y, rot}}, blueprints: [{name, layout}],
##     theme}
## Rules: placement inside open land, not blocked/occupied, Gem Mine on a
## Crystal Vein, quantity limits by Relay level; connectivity is a 4-neighbour
## flood fill from the Relay through Conduits and buildings (unconnected
## generators produce 0); power over budget scales generator efficiency;
## adjacency / Warehouse / Beacon layout bonus capped at +60%; production
## accrues min(rate x elapsed, cap) per building; one job per builder.
## last_tick == 0 means "not started": the first tick only stamps the clock,
## so a migrated save never double-pays the absence (SYSTEMS §8 step 4).

const OutpostDB := preload("res://data/OutpostDB.gd")
const Tiers := preload("res://Tiers.gd")
const Missions := preload("res://Missions.gd")
const Stats := preload("res://Stats.gd")
const TuneRef := preload("res://Tune.gd")
const AdjDB := preload("res://data/AdjDB.gd")
const LootDB := preload("res://data/LootDB.gd")

const HALL_POS: Vector2i = Vector2i(4, 5)      # the 3x3 Research Hall, touching the Relay's top
const DIRS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const BLUEPRINTS_MAX: int = 5


static func default_block(with_hall: bool = true) -> Dictionary:
	var o: Dictionary = {"relay_lvl": 1, "plots": [], "next_uid": 1, "credit": 0, "buildings": {}, "queue": [],
		"decor": {}, "blueprints": [], "theme": "ash"}
	if with_hall:
		_add_building(o, "research", HALL_POS.x, HALL_POS.y, 0, true)
	return o


static func _add_building(o: Dictionary, id: String, x: int, y: int, rot: int, built: bool) -> String:
	var uid: String = str(int(o["next_uid"]))
	o["next_uid"] = int(o["next_uid"]) + 1
	(o["buildings"] as Dictionary)[uid] = {"id": id, "x": x, "y": y, "rot": rot, "lvl": 1, "stored": 0.0, "last_tick": 0, "built": built, "spent": int(OutpostDB.get_def(id).get("coins", 0))}
	return uid


static func _o(s: Dictionary) -> Dictionary:
	if not (s.get("outpost", null) is Dictionary):
		s["outpost"] = default_block()
	return s["outpost"]


## Coerce a raw (JSON) block: known ids, clamped levels, unique uids;
## anything outside open land or overlapping is lifted to unplaced (x = -1).
static func normalize_block(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return default_block()
	var r: Dictionary = raw
	var o: Dictionary = default_block(false)
	o["relay_lvl"] = clampi(int(r.get("relay_lvl", 1)), 1, 10)
	var pl: Array = []
	for v in r.get("plots", []):
		var k: int = int(v)
		if k >= 0 and k < OutpostDB.PLOTS.size() and not pl.has(k):
			pl.append(k)
	o["plots"] = pl
	o["credit"] = maxi(0, int(r.get("credit", 0)))
	o["theme"] = String(r.get("theme", "ash"))
	var hi: int = 0
	var bl: Dictionary = {}
	var bin: Dictionary = r.get("buildings", {}) if r.get("buildings", {}) is Dictionary else {}
	var keys: Array = bin.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(String(a)) < int(String(b)))
	for k in keys:
		var e: Variant = bin[k]
		if not (e is Dictionary) or not OutpostDB.IDS.has(String((e as Dictionary).get("id", ""))) or int(String(k)) <= 0:
			continue
		var ed: Dictionary = e
		var id: String = String(ed["id"])
		hi = maxi(hi, int(String(k)))
		bl[str(int(String(k)))] = {"id": id, "x": int(ed.get("x", -1)), "y": int(ed.get("y", -1)), "rot": int(ed.get("rot", 0)) % 2,
			"lvl": clampi(int(ed.get("lvl", 1)), 1, 10), "stored": maxf(0.0, float(ed.get("stored", 0.0))),
			"last_tick": maxi(0, int(ed.get("last_tick", 0))), "built": bool(ed.get("built", true)), "spent": maxi(0, int(ed.get("spent", 0)))}
	var dc: Dictionary = {}
	var din: Dictionary = r.get("decor", {}) if r.get("decor", {}) is Dictionary else {}
	for k in din.keys():
		var e2: Variant = din[k]
		if e2 is Dictionary and OutpostDB.DECOR.has(String((e2 as Dictionary).get("id", ""))) and int(String(k)) > 0:
			hi = maxi(hi, int(String(k)))
			dc[str(int(String(k)))] = {"id": String((e2 as Dictionary)["id"]), "x": int((e2 as Dictionary).get("x", 0)), "y": int((e2 as Dictionary).get("y", 0)), "rot": int((e2 as Dictionary).get("rot", 0)) % 2}
	o["buildings"] = bl
	o["decor"] = dc
	o["next_uid"] = maxi(hi + 1, int(r.get("next_uid", 1)))
	var q: Array = []
	for x in r.get("queue", []):
		if x is Dictionary:
			var u: String = String((x as Dictionary).get("uid", ""))
			if u == "relay" or bl.has(u):
				# builds are instant now: a job left in an old save completes on the next tick
				q.append({"uid": u, "kind": String((x as Dictionary).get("kind", "build")), "ends_at": 0})
	o["queue"] = q
	var bps: Array = []
	for x in r.get("blueprints", []):
		if x is Dictionary and bps.size() < BLUEPRINTS_MAX:
			bps.append({"name": String((x as Dictionary).get("name", "Layout")), "layout": _clean_layout((x as Dictionary).get("layout", []))})
	o["blueprints"] = bps
	_lift_invalid(o)
	return o


static func _clean_layout(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for x in raw:
			if x is Dictionary and OutpostDB.IDS.has(String((x as Dictionary).get("id", ""))):
				out.append({"id": String((x as Dictionary)["id"]), "x": int((x as Dictionary).get("x", 0)), "y": int((x as Dictionary).get("y", 0)), "rot": int((x as Dictionary).get("rot", 0)) % 2})
	return out


## Sanitize step: overlapping or out-of-land buildings / decor are lifted.
static func _lift_invalid(o: Dictionary) -> void:
	var taken: Dictionary = {}
	for c in _relay_cells():
		taken[c] = "relay"
	for k in _sorted_keys(o["buildings"]):
		var b: Dictionary = o["buildings"][k]
		if int(b["x"]) < 0:
			continue
		var ok: bool = true
		var cells: Array = footprint(String(b["id"]), int(b["x"]), int(b["y"]), int(b["rot"]))
		for c in cells:
			if taken.has(c) or not _land_ok(o, c):
				ok = false
		if String(b["id"]) == "gemmine" and not _on_vein(cells):
			ok = false
		if not ok:
			b["x"] = -1
			b["y"] = -1
			continue
		for c in cells:
			taken[c] = k
	for k in _sorted_keys(o["decor"]):
		var d: Dictionary = o["decor"][k]
		var cells2: Array = footprint(String(d["id"]), int(d["x"]), int(d["y"]), int(d["rot"]))
		var ok2: bool = true
		for c in cells2:
			if taken.has(c) or not _land_ok(o, c):
				ok2 = false
		if not ok2:
			(o["decor"] as Dictionary).erase(k)
			continue
		for c in cells2:
			taken[c] = "d" + String(k)


static func _sorted_keys(d: Dictionary) -> Array:
	var ks: Array = d.keys()
	ks.sort_custom(func(a: Variant, b: Variant) -> bool: return int(String(a)) < int(String(b)))
	return ks


# ------------------------------------------------------------------ map
static func footprint(id: String, x: int, y: int, rot: int) -> Array:
	var sz: Vector2i = OutpostDB.size_of(id, rot)
	var out: Array = []
	for dy in sz.y:
		for dx in sz.x:
			out.append(Vector2i(x + dx, y + dy))
	return out


static func _relay_cells() -> Array:
	return footprint("relay", OutpostDB.RELAY.x, OutpostDB.RELAY.y, 0)


static func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < OutpostDB.W and c.y < OutpostDB.H


## Plot index of a cell (-1 = start area / none).
static func plot_of(c: Vector2i) -> int:
	if OutpostDB.START.has_point(c):
		return -1
	for k in OutpostDB.PLOTS.size():
		if (OutpostDB.PLOTS[k] as Rect2i).has_point(c):
			return k
	return -2


static func is_open(o: Dictionary, c: Vector2i) -> bool:
	if not in_map(c):
		return false
	var p: int = plot_of(c)
	return p == -1 or (p >= 0 and (o["plots"] as Array).has(p))


static func _land_ok(o: Dictionary, c: Vector2i) -> bool:
	return is_open(o, c) and not OutpostDB.BLOCKED.has(c)


static func _on_vein(cells: Array) -> bool:
	for c in cells:
		if OutpostDB.VEINS.has(c):
			return true
	return false


## cell -> occupant ("relay", building uid, or "d<uid>" decor).
static func occupancy(o: Dictionary, skip: String = "") -> Dictionary:
	var m: Dictionary = {}
	for c in _relay_cells():
		m[c] = "relay"
	for k in o["buildings"].keys():
		var b: Dictionary = o["buildings"][k]
		if String(k) == skip or int(b["x"]) < 0:
			continue
		for c in footprint(String(b["id"]), int(b["x"]), int(b["y"]), int(b["rot"])):
			m[c] = String(k)
	for k in o["decor"].keys():
		if "d" + String(k) == skip:
			continue
		var d: Dictionary = o["decor"][k]
		for c in footprint(String(d["id"]), int(d["x"]), int(d["y"]), int(d["rot"])):
			m[c] = "d" + String(k)
	return m


static func count_of(o: Dictionary, id: String) -> int:
	var n: int = 0
	for k in o["buildings"].keys():
		if String((o["buildings"][k] as Dictionary)["id"]) == id:
			n += 1
	return n


## "" when `id` may stand at (x, y, rot); otherwise the refusal reason.
## skip = uid being moved (its own cells do not block).
static func place_error(s: Dictionary, id: String, x: int, y: int, rot: int, skip: String = "") -> String:
	var o: Dictionary = _o(s)
	var is_decor: bool = OutpostDB.DECOR.has(id)
	if not is_decor and not OutpostDB.IDS.has(id):
		return "unknown"
	var cells: Array = footprint(id, x, y, rot)
	var occ: Dictionary = occupancy(o, skip)
	for c in cells:
		if not in_map(c):
			return "outside"
		if not is_open(o, c):
			return "locked"
		if OutpostDB.BLOCKED.has(c):
			return "blocked"
		if occ.has(c):
			return "occupied"
	if id == "gemmine" and not _on_vein(cells):
		return "needs_vein"
	if not is_decor and int(o["relay_lvl"]) < relay_req_of(s, id):
		return "relay"
	if not is_decor and skip == "" and count_of(o, id) >= limit_of(s, id):
		return "limit"
	return ""


## V2 P8 licences: how many of `id` this save may place (Relay limit +
## Mill / Mine / Scavenger / Core Works Licence research).
static func limit_of(s: Dictionary, id: String) -> int:
	var lim: int = OutpostDB.limit(id, int(_o(s)["relay_lvl"]))
	if id == "conduit":
		return lim
	match id:
		"mill":
			lim += _research_lvl(s, "lic_mill")
		"gemmine":
			lim += _research_lvl(s, "lic_mine")
	if OutpostDB.SCAVENGERS.has(id):
		lim += _research_lvl(s, "lic_scav")
	if OutpostDB.CORE_IDS.has(id):
		lim += _research_lvl(s, "lic_core")
	return lim


## Relay level `id` needs here: Advanced Licensing opens buildings that need
## Relay 3+ one level earlier per level (never below 2).
static func relay_req_of(s: Dictionary, id: String) -> int:
	var r: int = OutpostDB.relay_req(id)
	if r >= 3:
		r = maxi(2, r - clampi(_research_lvl(s, "lic_adv"), 0, 2))
	return r


# -------------------------------------------------------- connectivity
## uid -> bool: 4-neighbour flood fill from the Relay through every placed
## building (Conduits included). Decor never conducts.
static func connected(o: Dictionary) -> Dictionary:
	var occ: Dictionary = {}
	for k in o["buildings"].keys():
		var b: Dictionary = o["buildings"][k]
		if int(b["x"]) < 0:
			continue
		for c in footprint(String(b["id"]), int(b["x"]), int(b["y"]), int(b["rot"])):
			occ[c] = String(k)
	var seen: Dictionary = {}
	var out: Dictionary = {}
	var stack: Array = _relay_cells().duplicate()
	for c in stack:
		seen[c] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in DIRS:
			var n: Vector2i = cur + (d as Vector2i)
			if seen.has(n) or not occ.has(n):
				continue
			seen[n] = true
			out[occ[n]] = true
			stack.append(n)
	var res: Dictionary = {}
	for k in o["buildings"].keys():
		res[String(k)] = out.has(String(k))
	return res


## Is a decor piece (Lamp) lit: 4-adjacent to a connected building / Relay?
static func _decor_lit(o: Dictionary, d: Dictionary, con: Dictionary) -> bool:
	var occ: Dictionary = occupancy(o)
	for c in footprint(String(d["id"]), int(d["x"]), int(d["y"]), int(d["rot"])):
		for dv in DIRS:
			var n: Vector2i = (c as Vector2i) + (dv as Vector2i)
			var who: String = String(occ.get(n, ""))
			if who == "relay" or (who != "" and not who.begins_with("d") and bool(con.get(who, false))):
				return true
	return false


static func supply(o: Dictionary) -> float:
	return 10.0 + 4.0 * float(int(o["relay_lvl"]) - 1)


static func demand(o: Dictionary, con: Dictionary = {}) -> float:
	var cn: Dictionary = con if not con.is_empty() else connected(o)
	var p: float = 0.0
	for k in o["buildings"].keys():
		var b: Dictionary = o["buildings"][k]
		if bool(b["built"]) and bool(cn.get(String(k), false)):
			p += float(OutpostDB.get_def(String(b["id"])).get("power", 0))
	for k in o["decor"].keys():
		var d: Dictionary = o["decor"][k]
		var pw: float = float((OutpostDB.DECOR[String(d["id"])] as Dictionary).get("power", 0.0))
		if pw > 0.0 and _decor_lit(o, d, cn):
			p += pw
	return p


## Generator efficiency: 1, or budget / demand when over budget.
static func efficiency(o: Dictionary, con: Dictionary = {}) -> float:
	var dm: float = demand(o, con)
	if dm <= 0.0:
		return 1.0
	return minf(1.0, supply(o) / dm)


# ------------------------------------------------------------ adjacency
static func _cells_of(o: Dictionary, uid: String) -> Array:
	var b: Dictionary = o["buildings"][uid]
	return footprint(String(b["id"]), int(b["x"]), int(b["y"]), int(b["rot"]))


## Set of occupant ids 4-adjacent to a building (excluding itself).
static func neighbours(o: Dictionary, uid: String) -> Array:
	var occ: Dictionary = occupancy(o)
	var mine: Array = _cells_of(o, uid)
	var out: Array = []
	for c in mine:
		for dv in DIRS:
			var n: Vector2i = (c as Vector2i) + (dv as Vector2i)
			if mine.has(n):
				continue
			var who: String = String(occ.get(n, ""))
			if who != "" and not out.has(who):
				out.append(who)
	return out


static func _cheb(a: Array, b: Array) -> int:
	var best: int = 99
	for p in a:
		for q in b:
			best = mini(best, maxi(absi((p as Vector2i).x - (q as Vector2i).x), absi((p as Vector2i).y - (q as Vector2i).y)))
	return best


static func _decor_tag(o: Dictionary, who: String) -> String:
	if not who.begins_with("d"):
		return ""
	var d: Dictionary = (o["decor"] as Dictionary).get(who.substr(1), {})
	return String((OutpostDB.DECOR.get(String(d.get("id", "")), {}) as Dictionary).get("tag", ""))


## Layout bonus of one building {total, parts: {key: frac}}: the signed
## AdjDB rules from built, linked neighbours (touching or within reach) plus
## decor (Smelter, lit Lamps, scholar / training pieces; decor capped at
## +20%); the total is capped at +60% and floored at -40%.
static func layout_bonus(o: Dictionary, uid: String, con: Dictionary = {}) -> Dictionary:
	var b: Dictionary = o["buildings"][uid]
	var id: String = String(b["id"])
	var parts: Dictionary = {}
	var srcs: Dictionary = {}
	if int(b["x"]) < 0:
		return {"total": 0.0, "parts": parts, "srcs": srcs}
	var cn: Dictionary = con if not con.is_empty() else connected(o)
	var touching: Array = neighbours(o, uid)
	var mine: Array = _cells_of(o, uid)
	for rule in AdjDB.RULES:
		var rd: Dictionary = rule
		if not AdjDB.targets(rd, id) or (String(rd["dst"]) == "*" and String(rd["src"]) == id):
			continue
		var n: int = 0
		var who: Array = []
		for k in o["buildings"].keys():
			var bb: Dictionary = o["buildings"][k]
			if String(k) == uid or String(bb["id"]) != String(rd["src"]) or not bool(bb["built"]) or int(bb["x"]) < 0 or not bool(cn.get(String(k), false)):
				continue
			var near: bool = false
			if int(rd["r"]) <= 1:
				near = touching.has(String(k))
			else:
				var dd: int = _cheb(_cells_of(o, String(k)), mine)
				near = dd <= int(rd["r"]) and dd >= int(rd.get("rmin", 1))
			if near:
				n += 1
				who.append(String(k))
		if n <= 0:
			continue
		var v: float = float(rd["eff"]) * (1.0 if bool(rd.get("once", false)) else float(n))
		if rd.has("max"):
			v = clampf(v, -float(rd["max"]), float(rd["max"]))
		var key: String = String(rd["key"])
		if bool(rd.get("once", false)) and parts.has(key):
			continue   # the same effect from two rule rows counts once
		parts[key] = float(parts.get(key, 0.0)) + v
		srcs[key] = (srcs.get(key, []) as Array) + who
	var decor: float = 0.0
	var lamps: int = 0
	var scholar: int = 0
	var training: int = 0
	for who in touching:
		var w: String = String(who)
		if not w.begins_with("d"):
			continue
		var tag: String = _decor_tag(o, w)
		var dd2: Dictionary = (o["decor"] as Dictionary)[w.substr(1)]
		if tag == "industrial" and String(dd2["id"]) == "dc_smelter" and id == "refinery":
			decor += 0.20
		if String(dd2["id"]) == "dc_lamp" and id == "gemmine" and _decor_lit(o, dd2, cn):
			lamps += 1
		if tag == "scholar":
			scholar += 1
		if tag == "training":
			training += 1
	if id == "gemmine" and lamps > 0:
		decor += 0.10 * float(lamps)
	if id == "research" and scholar > 0:
		decor += minf(0.15, 0.05 * float(scholar))
	if id == "barracks" and training > 0:
		decor += 0.05 * float(training)
	if decor != 0.0:
		parts["decor"] = minf(0.20, decor)
	var tot: float = 0.0
	for k in parts.keys():
		tot += float(parts[k])
	return {"total": clampf(tot, AdjDB.NERF_FLOOR, TuneRef.num("pc_layout_cap", AdjDB.BUFF_CAP)), "parts": parts, "srcs": srcs}


## Warehouse storage bonus on a building: +25% (+5%/L) within radius 2.
static func warehouse_bonus(o: Dictionary, uid: String) -> float:
	var best: float = 0.0
	for k in o["buildings"].keys():
		var w: Dictionary = o["buildings"][k]
		if String(w["id"]) != "warehouse" or not bool(w["built"]) or int(w["x"]) < 0 or String(k) == uid:
			continue
		if _cheb(_cells_of(o, String(k)), _cells_of(o, uid)) <= 2:
			best = maxf(best, 0.10 + 0.02 * float(int(w["lvl"]) - 1))
	return best


# ----------------------------------------------------------- production
static func _research_lvl(s: Dictionary, id: String) -> int:
	var rs: Variant = s.get("research", null)
	if rs is Dictionary and (rs as Dictionary).get("lvls", null) is Dictionary:
		return int(((rs as Dictionary)["lvls"] as Dictionary).get(id, 0))
	return 0


static func _node(s: Dictionary, id: String) -> int:
	var rf: Variant = s.get("reforge", null)
	if rf is Dictionary and (rf as Dictionary).get("nodes", null) is Dictionary:
		return int(((rf as Dictionary)["nodes"] as Dictionary).get(id, 0))
	return 0


## Charm: +1% per 10 decor pieces placed (max +10%).
static func charm(o: Dictionary) -> float:
	return minf(0.10, 0.01 * float((o["decor"] as Dictionary).size() / 10))


## Global production mult: Charm x outpost_p (+8%/L) x Logistics Tech (+5%/L).
static func global_mult(s: Dictionary) -> float:
	var o: Dictionary = _o(s)
	return (1.0 + charm(o)) * (1.0 + 0.08 * float(_node(s, "outpost_p"))) * (1.0 + 0.05 * float(_research_lvl(s, "offrate")))


## Nominal hourly output of a building (level, layout, global; no power/
## connection), 0 for non-generators.
static func nominal_rate(s: Dictionary, uid: String, con: Dictionary = {}) -> float:
	var o: Dictionary = _o(s)
	var b: Dictionary = o["buildings"][uid]
	var id: String = String(b["id"])
	var d: Dictionary = OutpostDB.get_def(id)
	if not OutpostDB.GENERATORS.has(id) or int(b["x"]) < 0:
		return 0.0
	var L: int = int(b["lvl"])
	var lay: float = float(layout_bonus(o, uid, con)["total"])
	if OutpostDB.SCAVENGERS.has(id):
		# V2 P8 Scavenging research: +6% per level
		return float(d["rate"]) * (1.0 + 0.25 * float(L - 1)) * (1.0 + lay) * global_mult(s) * (1.0 + 0.06 * float(_research_lvl(s, "scav_rate")))
	match id:
		"gemmine":
			# Deep Mine (was the Gem Mine; gems are gone): a big coin generator
			# on a vein; only Lamps boost its layout.
			return float(d["rate"]) * (1.0 + 0.25 * float(L - 1)) * (1.0 + lay) * global_mult(s)
		"mill":
			var tm: float = 1.0 + TuneRef.num("pc_mill_tier", OutpostDB.MILL_TIER) * float(Tiers.highest(s) - 1)
			return TuneRef.num("pc_mill_rate", float(d["rate"])) * (1.0 + 0.25 * float(L - 1)) * (1.0 + lay) * global_mult(s) * tm
	# Scrap Refinery (+10% per Reforge scrap_p level).
	return float(d["rate"]) * (1.0 + 0.25 * float(L - 1)) * (1.0 + lay) * global_mult(s) * (1.0 + 0.10 * float(_node(s, "scrap_p")))


## Live hourly output: nominal x efficiency, 0 if unbuilt or unconnected.
static func rate(s: Dictionary, uid: String, con: Dictionary = {}) -> float:
	var o: Dictionary = _o(s)
	var b: Dictionary = o["buildings"][uid]
	var cn: Dictionary = con if not con.is_empty() else connected(o)
	if not bool(b["built"]) or not bool(cn.get(uid, false)):
		return 0.0
	return nominal_rate(s, uid, cn) * efficiency(o, cn)


## Storage cap: storage_h hours of nominal output x Warehouse x Storage Tech
## (+4%/L).
static func cap(s: Dictionary, uid: String, con: Dictionary = {}) -> float:
	var o: Dictionary = _o(s)
	var b: Dictionary = o["buildings"][uid]
	var d: Dictionary = OutpostDB.get_def(String(b["id"]))
	if d.has("hard_cap"):
		return float(d["hard_cap"])
	if d.has("store"):
		return float(int(d["store"]) + (int(b["lvl"]) - 1) / 3)   # token storage: +1 per 3 levels
	var h: float = TuneRef.num("pc_storage_h", 8.0) if String(b["id"]) == "mill" else float(d["storage_h"])
	return nominal_rate(s, uid, con) * h * (1.0 + warehouse_bonus(o, uid)) * (1.0 + 0.04 * float(_research_lvl(s, "offcap")))


static func _accrue(s: Dictionary, upto: int) -> void:
	var o: Dictionary = _o(s)
	var con: Dictionary = connected(o)
	for k in o["buildings"].keys():
		var b: Dictionary = o["buildings"][k]
		if not OutpostDB.GENERATORS.has(String(b["id"])) or not bool(b["built"]):
			continue
		var last: int = int(b["last_tick"])
		if last <= 0 or upto < last:
			b["last_tick"] = upto
			continue
		var r: float = rate(s, String(k), con)
		var cp: float = cap(s, String(k), con)
		var st: float = float(b["stored"])
		if st < cp:
			b["stored"] = minf(cp, st + r * float(upto - last) / 3600.0)
		b["last_tick"] = upto


## Advance the Outpost to `now`: accrue up to each finishing job in order,
## complete it, continue. Returns build_done / upgrade_done / relay_done.
static func tick(s: Dictionary, now: int) -> Array:
	var o: Dictionary = _o(s)
	var ev: Array = []
	var guard: int = 0
	while guard < 64:
		guard += 1
		var q: Array = o["queue"]
		var bi: int = -1
		for i in q.size():
			if int((q[i] as Dictionary)["ends_at"]) <= now and (bi < 0 or int((q[i] as Dictionary)["ends_at"]) < int((q[bi] as Dictionary)["ends_at"])):
				bi = i
		if bi < 0:
			break
		var job: Dictionary = q[bi]
		_accrue(s, int(job["ends_at"]))
		q.remove_at(bi)
		ev.append_array(_complete(s, job))
	_accrue(s, now)
	return ev


static func _complete(s: Dictionary, job: Dictionary) -> Array:
	var o: Dictionary = _o(s)
	var uid: String = String(job["uid"])
	var t: int = int(job["ends_at"])
	if uid == "relay":
		o["relay_lvl"] = mini(10, int(o["relay_lvl"]) + 1)
		return [{"t": "relay_done", "lvl": int(o["relay_lvl"])}]
	if not (o["buildings"] as Dictionary).has(uid):
		return []
	var b: Dictionary = o["buildings"][uid]
	if String(job["kind"]) == "build":
		b["built"] = true
		b["last_tick"] = t
		return [{"t": "build_done", "uid": uid, "id": String(b["id"])}]
	b["lvl"] = mini(10, int(b["lvl"]) + 1)
	return [{"t": "upgrade_done", "uid": uid, "id": String(b["id"]), "lvl": int(b["lvl"])}]


## Preview of what is stored at `now` (no mutation): {coins, scrap}.
static func pending(s: Dictionary, now: int) -> Dictionary:
	var c: Dictionary = s.duplicate(true)
	tick(c, now)
	var out: Dictionary = {"coins": 0.0, "scrap": 0.0}
	var o: Dictionary = _o(c)
	for k in o["buildings"].keys():
		var b: Dictionary = o["buildings"][k]
		var res: String = String(OutpostDB.get_def(String(b["id"])).get("res", ""))
		if out.has(res):
			out[res] = float(out[res]) + float(b["stored"])
	return out


## Total hourly production per resource (live).
static func production(s: Dictionary) -> Dictionary:
	var o: Dictionary = _o(s)
	var con: Dictionary = connected(o)
	var out: Dictionary = {"coins": 0.0, "scrap": 0.0}
	for k in o["buildings"].keys():
		var res: String = String(OutpostDB.get_def(String((o["buildings"][k] as Dictionary)["id"])).get("res", ""))
		if out.has(res):
			out[res] = float(out[res]) + rate(s, String(k), con)
	return out


static func _pay_res(s: Dictionary, res: String, n: int) -> void:
	if n <= 0:
		return
	match res:
		"coins":
			s["coins"] = int(s.get("coins", 0)) + n
			if s.get("reforge", null) is Dictionary:
				(s["reforge"] as Dictionary)["coins_since"] = int((s["reforge"] as Dictionary).get("coins_since", 0)) + n
		"scrap":
			s["scrap"] = int(s.get("scrap", 0)) + n


## Collect one building's whole units (fractions stay).
static func collect(s: Dictionary, uid: String, now: int) -> Array:
	var ev: Array = tick(s, now)
	var o: Dictionary = _o(s)
	if not (o["buildings"] as Dictionary).has(uid):
		return ev
	var b: Dictionary = o["buildings"][uid]
	var res: String = String(OutpostDB.get_def(String(b["id"])).get("res", ""))
	var n: int = int(floor(float(b["stored"])))
	if res == "" or n <= 0:
		return ev
	b["stored"] = float(b["stored"]) - float(n)
	if OutpostDB.SCAVENGERS.has(String(b["id"])):
		ev.append_array(_scavenge(s, res, n))
	else:
		_pay_res(s, res, n)
	if s.get("stats", null) is Dictionary:
		(s["stats"] as Dictionary)["outpost_collects"] = int((s["stats"] as Dictionary).get("outpost_collects", 0)) + 1
	ev.append({"t": "collect", "uid": uid, "id": String(b["id"]), "res": res, "n": n})
	return ev


## Scavenged tokens bank like run loot (Loot.realize: items on the meta RNG).
static func _scavenge(s: Dictionary, res: String, n: int) -> Array:
	var il: int = scav_ilvl(s)
	var loot: Dictionary = {"scrap": 0, "items": [], "caches": [], "luck": 0, "tier": Tiers.highest(s)}
	for k in n:
		if res == "item":
			(loot["items"] as Array).append({"src": "scavenger", "ilvl": il})
		else:
			(loot["caches"] as Array).append({"id": res, "ilvl": il})
	return load("res://Loot.gd").realize(s, loot)


## Item level of scavenged gear: 60% of the best wave, +15 per tier above 1.
static func scav_ilvl(s: Dictionary) -> int:
	return clampi(int(float(int(s.get("best_wave", 0))) * 0.6) + 15 * (Tiers.highest(s) - 1), 1, 200)


## "While you were away" (replaces Offline.gd): what the Outpost stored since
## last_seen. {coins, scrap, minutes}; zero under 5 minutes or on
## a first boot (last_seen 0) — the Outpost accrual itself is the offline pay.
static func away_report(s: Dictionary, now: int) -> Dictionary:
	var last: int = int(s.get("last_seen", 0))
	var out: Dictionary = pending(s, now)
	out["minutes"] = 0 if last <= 0 or now < last else (now - last) / 60
	if last <= 0 or now - last < TuneRef.int_of("offline_min", 300):
		for k in ["coins", "scrap"]:
			out[k] = 0.0
	return out


## Collect the away report (boot modal): every building, Relay level ignored.
static func claim_away(s: Dictionary, now: int) -> Array:
	var ev: Array = collect_all(s, now, true)
	s["last_seen"] = now
	var tot: Dictionary = {"coins": 0, "scrap": 0}
	for e in ev:
		# Scavengers collect items / caches (their own events), not coins or Scrap
		if String((e as Dictionary)["t"]) == "collect" and tot.has(String(e["res"])):
			tot[String(e["res"])] = int(tot[String(e["res"])]) + int(e["n"])
	if int(tot["coins"]) + int(tot["scrap"]) > 0:
		ev.append({"t": "offline", "coins": int(tot["coins"]), "scrap": int(tot["scrap"])})
	return ev


static func collect_all_unlocked(s: Dictionary) -> bool:
	return int(_o(s)["relay_lvl"]) >= 3


## V2 P8b Auto-Collect research: collect every coin / Scrap building (not
## Scavengers: their items wait for a click). One summary event, no per-
## building events (no toast spam); [] without the research or with nothing.
static func auto_collect(s: Dictionary, now: int) -> Array:
	if _research_lvl(s, "auto_collect") <= 0:
		return []
	var ev: Array = tick(s, now)
	var tot: Dictionary = {"coins": 0, "scrap": 0}
	for k in _sorted_keys(_o(s)["buildings"]):
		var b: Dictionary = _o(s)["buildings"][k]
		if OutpostDB.SCAVENGERS.has(String(b["id"])) or float(b.get("stored", 0.0)) < 1.0:
			continue
		for e in collect(s, String(k), now):
			if String((e as Dictionary)["t"]) == "collect" and tot.has(String(e["res"])):
				tot[String(e["res"])] = int(tot[String(e["res"])]) + int(e["n"])
	if int(tot["coins"]) + int(tot["scrap"]) > 0:
		ev.append({"t": "auto_collect", "coins": int(tot["coins"]), "scrap": int(tot["scrap"])})
	return ev


## Collect every building (Relay L3+, or force for the boot "while you were
## away" report).
static func collect_all(s: Dictionary, now: int, force: bool = false) -> Array:
	if not force and not collect_all_unlocked(s):
		return []
	var ev: Array = tick(s, now)
	for k in _sorted_keys(_o(s)["buildings"]):
		ev.append_array(collect(s, String(k), now))
	return ev


# --------------------------------------------------------------- builds
static func builders(s: Dictionary) -> int:
	return 1 + mini(1, _node(s, "builder2"))


static func busy(s: Dictionary) -> int:
	return (_o(s)["queue"] as Array).size()


static func has_job(s: Dictionary, uid: String) -> bool:
	for j in _o(s)["queue"]:
		if String((j as Dictionary)["uid"]) == uid:
			return true
	return false


static func max_lvl(s: Dictionary, id: String) -> int:
	if id == "relay":
		return 10
	return mini(int(OutpostDB.get_def(id).get("max_lvl", 10)), int(_o(s)["relay_lvl"]) + 2)


## Coins / seconds to go from lvl -> lvl + 1 (lvl 0 = the initial build).
static func cost(id: String, lvl: int) -> int:
	var d: Dictionary = OutpostDB.get_def(id)
	return int(round(float(d.get("coins", 0)) * pow(1.6, float(maxi(1, lvl) - 1))))


## Owner feedback #1: every Outpost build / upgrade is instant.
static func build_time(_s: Dictionary, _id: String, _lvl: int) -> int:
	return 0


## Spend coins on an Outpost build, Outpost credit (migration) first.
static func _spend(s: Dictionary, c: int) -> bool:
	var o: Dictionary = _o(s)
	var cr: int = int(o.get("credit", 0))
	if int(s.get("coins", 0)) + cr < c:
		return false
	var from_cr: int = mini(cr, c)
	o["credit"] = cr - from_cr
	s["coins"] = int(s["coins"]) - (c - from_cr)
	if c - from_cr > 0:
		Stats.on_event(s, {"t": "coins_spent", "n": c - from_cr})
	return true


static func can_afford(s: Dictionary, c: int) -> bool:
	return int(s.get("coins", 0)) + int(_o(s).get("credit", 0)) >= c


## Place a new building (pays L1 cost; built instantly). Refused: invalid
## spot, limit, unaffordable.
static func place(s: Dictionary, id: String, x: int, y: int, rot: int, now: int) -> Array:
	if not OutpostDB.IDS.has(id) or place_error(s, id, x, y, rot) != "":
		return []
	var d: Dictionary = OutpostDB.get_def(id)
	var c: int = int(d.get("coins", 0))
	if not can_afford(s, c):
		return []
	var ev: Array = tick(s, now)
	_spend(s, c)
	var o: Dictionary = _o(s)
	var uid: String = _add_building(o, id, x, y, rot % 2, true)
	(o["buildings"][uid] as Dictionary)["last_tick"] = now
	ev.append({"t": "op_placed", "uid": uid, "id": id, "x": x, "y": y, "rot": rot % 2, "ends_at": now, "coins": c})
	ev.append({"t": "build_done", "uid": uid, "id": id})
	return ev


## Move / rotate a building for free (validated like a placement).
static func move(s: Dictionary, uid: String, x: int, y: int, rot: int, now: int) -> Array:
	var o: Dictionary = _o(s)
	if not (o["buildings"] as Dictionary).has(uid):
		return []
	var b: Dictionary = o["buildings"][uid]
	if place_error(s, String(b["id"]), x, y, rot, uid) != "":
		return []
	var ev: Array = tick(s, now)
	b["x"] = x
	b["y"] = y
	b["rot"] = rot % 2
	ev.append({"t": "op_moved", "uid": uid, "x": x, "y": y, "rot": rot % 2})
	return ev


## Demolish: 100% refund while its build is queued, 50% of coins spent after.
static func demolish(s: Dictionary, uid: String, now: int) -> Array:
	var o: Dictionary = _o(s)
	if not (o["buildings"] as Dictionary).has(uid):
		return []
	var ev: Array = tick(s, now)
	var b: Dictionary = o["buildings"][uid]
	var queued: bool = not bool(b["built"])
	var refund: int = int(b["spent"]) if queued else int(b["spent"]) / 2
	var q: Array = o["queue"]
	for i in range(q.size() - 1, -1, -1):
		if String((q[i] as Dictionary)["uid"]) == uid:
			q.remove_at(i)
	(o["buildings"] as Dictionary).erase(uid)
	s["coins"] = int(s.get("coins", 0)) + refund
	ev.append({"t": "op_demolished", "uid": uid, "id": String(b["id"]), "refund": refund})
	return ev


static func can_upgrade(s: Dictionary, uid: String) -> bool:
	var o: Dictionary = _o(s)
	if uid == "relay":
		return int(o["relay_lvl"]) < 10 and can_afford(s, relay_cost(int(o["relay_lvl"])))
	if not (o["buildings"] as Dictionary).has(uid):
		return false
	var b: Dictionary = o["buildings"][uid]
	var id: String = String(b["id"])
	return bool(b["built"]) and int(b["lvl"]) < max_lvl(s, id) and can_afford(s, cost(id, int(b["lvl"])))


static func relay_cost(lvl: int) -> int:
	return int(round(float(OutpostDB.get_def("relay")["coins"]) * pow(1.8, float(maxi(1, lvl) - 1))))


static func upgrade(s: Dictionary, uid: String, now: int) -> Array:
	if not can_upgrade(s, uid):
		return []
	var ev: Array = tick(s, now)
	var o: Dictionary = _o(s)
	if uid == "relay":
		var rc: int = relay_cost(int(o["relay_lvl"]))
		_spend(s, rc)
		ev.append({"t": "op_upgrade", "uid": "relay", "to": int(o["relay_lvl"]) + 1, "ends_at": now, "coins": rc})
		ev.append_array(_complete(s, {"uid": "relay", "kind": "upgrade", "ends_at": now}))
		return ev
	var b: Dictionary = o["buildings"][uid]
	var c: int = cost(String(b["id"]), int(b["lvl"]))
	_spend(s, c)
	b["spent"] = int(b["spent"]) + c
	ev.append({"t": "op_upgrade", "uid": uid, "to": int(b["lvl"]) + 1, "ends_at": now, "coins": c})
	ev.append_array(_complete(s, {"uid": uid, "kind": "upgrade", "ends_at": now}))
	return ev


# ----------------------------------------------------------------- plots
## Plot unlock price for the n-th plot opened: 5,000 x 2.2^n coins (coins
## only; gems are gone).
static func plot_cost(s: Dictionary) -> Dictionary:
	var n: int = (_o(s)["plots"] as Array).size()
	var c: int = int(round(5000.0 * pow(2.2, float(n))))
	return {"coins": c, "coins_alt": c}


static func plot_adjacent(o: Dictionary, k: int) -> bool:
	var r: Rect2i = OutpostDB.PLOTS[k]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			for dv in DIRS:
				var n: Vector2i = Vector2i(x, y) + (dv as Vector2i)
				if not r.has_point(n) and is_open(o, n):
					return true
	return false


## `_pay` is kept for old callers (coins only now).
static func unlock_plot(s: Dictionary, k: int, _pay: String = "coins") -> Array:
	var o: Dictionary = _o(s)
	if k < 0 or k >= OutpostDB.PLOTS.size() or (o["plots"] as Array).has(k) or not plot_adjacent(o, k):
		return []
	var pc: Dictionary = plot_cost(s)
	var c: int = int(pc["coins"])
	if int(s.get("coins", 0)) < c:
		return []
	s["coins"] = int(s["coins"]) - c
	Stats.on_event(s, {"t": "coins_spent", "n": c})
	(o["plots"] as Array).append(k)
	return [{"t": "plot_open", "plot": k, "coins": c}]


# ----------------------------------------------------------------- decor
static func place_decor(s: Dictionary, id: String, x: int, y: int, rot: int) -> Array:
	if not OutpostDB.DECOR.has(id) or place_error(s, id, x, y, rot) != "":
		return []
	var d: Dictionary = OutpostDB.DECOR[id]
	if int(s.get("coins", 0)) < int(d["coins"]):
		return []
	s["coins"] = int(s["coins"]) - int(d["coins"])
	var o: Dictionary = _o(s)
	var uid: String = str(int(o["next_uid"]))
	o["next_uid"] = int(o["next_uid"]) + 1
	(o["decor"] as Dictionary)[uid] = {"id": id, "x": x, "y": y, "rot": rot % 2}
	return [{"t": "decor_placed", "uid": uid, "id": id, "x": x, "y": y}]


static func move_decor(s: Dictionary, uid: String, x: int, y: int, rot: int) -> Array:
	var o: Dictionary = _o(s)
	if not (o["decor"] as Dictionary).has(uid):
		return []
	var d: Dictionary = o["decor"][uid]
	if place_error(s, String(d["id"]), x, y, rot, "d" + uid) != "":
		return []
	d["x"] = x
	d["y"] = y
	d["rot"] = rot % 2
	return [{"t": "decor_moved", "uid": uid, "x": x, "y": y}]


## Remove decor (50% coin refund).
static func remove_decor(s: Dictionary, uid: String) -> Array:
	var o: Dictionary = _o(s)
	if not (o["decor"] as Dictionary).has(uid):
		return []
	var d: Dictionary = o["decor"][uid]
	var refund: int = int((OutpostDB.DECOR[String(d["id"])] as Dictionary)["coins"]) / 2
	(o["decor"] as Dictionary).erase(uid)
	s["coins"] = int(s.get("coins", 0)) + refund
	return [{"t": "decor_removed", "uid": uid, "refund": refund}]


# ------------------------------------------------------------ blueprints
static func layout_of(o: Dictionary) -> Array:
	var out: Array = []
	for k in _sorted_keys(o["buildings"]):
		var b: Dictionary = o["buildings"][k]
		if int(b["x"]) >= 0:
			out.append({"id": String(b["id"]), "x": int(b["x"]), "y": int(b["y"]), "rot": int(b["rot"])})
	return out


## Save the current layout (max 5; same name overwrites).
static func save_blueprint(s: Dictionary, name: String) -> Array:
	var o: Dictionary = _o(s)
	var bps: Array = o["blueprints"]
	var entry: Dictionary = {"name": name, "layout": layout_of(o)}
	for i in bps.size():
		if String((bps[i] as Dictionary)["name"]) == name:
			bps[i] = entry
			return [{"t": "blueprint_saved", "name": name, "idx": i}]
	if bps.size() >= BLUEPRINTS_MAX:
		return []
	bps.append(entry)
	return [{"t": "blueprint_saved", "name": name, "idx": bps.size() - 1}]


## One-click rebuild: owned buildings move to the layout's spots (first
## fitting building of each id); returns {ev, missing: [ids]}.
static func load_blueprint(s: Dictionary, layout: Array, now: int) -> Dictionary:
	var o: Dictionary = _o(s)
	tick(s, now)
	var pool: Dictionary = {}
	for k in _sorted_keys(o["buildings"]):
		var id: String = String((o["buildings"][k] as Dictionary)["id"])
		if not pool.has(id):
			pool[id] = []
		(pool[id] as Array).append(String(k))
	# Lift every building that the layout will place, then drop them in.
	var used: Dictionary = {}
	var plan: Array = []
	var missing: Array = []
	for x in _clean_layout(layout):
		var e: Dictionary = x
		var cand: Array = pool.get(String(e["id"]), [])
		var pick: String = ""
		for u in cand:
			if not used.has(u):
				pick = String(u)
				break
		if pick == "":
			missing.append(String(e["id"]))
			continue
		used[pick] = true
		plan.append([pick, e])
	var old: Dictionary = {}
	for p in plan:
		var b: Dictionary = o["buildings"][String(p[0])]
		old[String(p[0])] = [int(b["x"]), int(b["y"]), int(b["rot"])]
		b["x"] = -1
		b["y"] = -1
	var ev: Array = []
	for p in plan:
		var uid: String = String(p[0])
		var e2: Dictionary = p[1]
		var b2: Dictionary = o["buildings"][uid]
		if place_error(s, String(b2["id"]), int(e2["x"]), int(e2["y"]), int(e2["rot"]), uid) == "":
			b2["x"] = int(e2["x"])
			b2["y"] = int(e2["y"])
			b2["rot"] = int(e2["rot"])
		else:
			var ob: Array = old[uid]
			if place_error(s, String(b2["id"]), int(ob[0]), int(ob[1]), int(ob[2]), uid) == "":
				b2["x"] = int(ob[0])
				b2["y"] = int(ob[1])
				b2["rot"] = int(ob[2])
			missing.append(String(b2["id"]))
	ev.append({"t": "blueprint_loaded", "placed": plan.size() - missing.size(), "missing": missing.duplicate()})
	return {"ev": ev, "missing": missing}


static func export_layout(o: Dictionary) -> String:
	return Marshalls.utf8_to_base64(JSON.stringify(layout_of(o)))


static func import_layout(text: String) -> Array:
	var raw: Variant = JSON.parse_string(Marshalls.base64_to_utf8(text.strip_edges()))
	return _clean_layout(raw)


# ------------------------------------------------------- meta hand-offs
static func level_of(s: Dictionary, id: String) -> int:
	var o: Dictionary = _o(s)
	var best: int = 0
	for k in o["buildings"].keys():
		var b: Dictionary = o["buildings"][k]
		if String(b["id"]) == id and bool(b["built"]) and int(b["x"]) >= 0:
			best = maxi(best, int(b["lvl"]))
	return best


## Research Hall queues: 1 / 2 / 3 at Hall L1 / L4 / L8 (0 without a Hall).
static func research_queues(s: Dictionary) -> int:
	var L: int = level_of(s, "research")
	if L <= 0:
		return 0
	return 3 if L >= 8 else (2 if L >= 4 else 1)


## Lab speed from the Research Hall's layout (scholar decor, Beacons,
## Pylons; max +15%).
static func hall_speed(s: Dictionary) -> float:
	var o: Dictionary = _o(s)
	for k in o["buildings"].keys():
		if String((o["buildings"][k] as Dictionary)["id"]) == "research" and int((o["buildings"][k] as Dictionary)["x"]) >= 0:
			return 1.0 + minf(0.15, float(layout_bonus(o, String(k))["total"]))
	return 1.0


## Permanent Core stats from the Core buildings: {key: value} summed over
## built, linked ones = per-level value x level x (1 + layout) x power
## efficiency. Keys: dmg rate core_hp dr crit range cash xp (run pfx),
## loot_luck (bank), forge_disc (Forge).
static func core_bonus(s: Dictionary) -> Dictionary:
	var o: Dictionary = _o(s)
	var con: Dictionary = connected(o)
	var eff: float = efficiency(o, con)
	var out: Dictionary = {}
	for k in o["buildings"].keys():
		var b: Dictionary = o["buildings"][k]
		var d: Dictionary = OutpostDB.get_def(String(b["id"]))
		if not d.has("core") or not bool(b["built"]) or int(b["x"]) < 0 or not bool(con.get(String(k), false)):
			continue
		var part: Dictionary = core_part(o, String(k), con, eff)
		for key in part.keys():
			out[key] = float(out.get(key, 0.0)) + float(part[key])
	return out


## One Core building's share of core_bonus at its current level ({} when it
## is not a Core building; ignores built / linked - callers check).
static func core_part(o: Dictionary, uid: String, con: Dictionary = {}, eff: float = -1.0) -> Dictionary:
	var b: Dictionary = o["buildings"][uid]
	var d: Dictionary = OutpostDB.get_def(String(b["id"]))
	if not d.has("core") or int(b["x"]) < 0:
		return {}
	var cn: Dictionary = con if not con.is_empty() else connected(o)
	var e: float = eff if eff >= 0.0 else efficiency(o, cn)
	var m: float = float(int(b["lvl"])) * (1.0 + float(layout_bonus(o, uid, cn)["total"])) * e
	var out: Dictionary = {}
	for key in (d["core"] as Dictionary).keys():
		out[key] = float(d["core"][key]) * m
	return out


## The run's share of core_bonus (TowerState pfx keys).
const RUN_KEYS: Array = ["dmg", "rate", "core_hp", "dr", "crit", "range", "cash", "xp"]


## Run-facing bundle: Barracks troop tier, Archive Insight cap / banish.
static func run_mods(s: Dictionary) -> Dictionary:
	var bar: int = level_of(s, "barracks")
	var arc: int = level_of(s, "archive")
	var o: Dictionary = _o(s)
	var bar_bonus: float = 0.0
	for k in o["buildings"].keys():
		if String((o["buildings"][k] as Dictionary)["id"]) == "barracks" and bool((o["buildings"][k] as Dictionary)["built"]):
			bar_bonus = float(layout_bonus(o, String(k))["total"])
	var cb: Dictionary = core_bonus(s)
	var fx: Dictionary = {}
	for k in RUN_KEYS:
		if cb.has(k):
			fx[k] = float(cb[k])
	return {
		"outpost_fx": fx,
		"barracks_tier": bar, "barracks_bonus": bar_bonus,
		"insight_cap": (2 if arc >= 6 else (1 if arc >= 3 else 0)),
		"banish": 1 if arc >= 9 else 0,
	}


## Reforge (R6): building levels reset to 1 (retain keeps floor(lvl x frac)),
## Relay back to L1, running jobs finish instantly; layout, plots, decor,
## blueprints and stored output are kept.
static func reforge_reset(s: Dictionary, retain: float, now: int) -> void:
	var o: Dictionary = _o(s)
	tick(s, now)
	for j in o["queue"]:
		if String((j as Dictionary)["kind"]) == "build" and (o["buildings"] as Dictionary).has(String((j as Dictionary)["uid"])):
			(o["buildings"][String((j as Dictionary)["uid"])] as Dictionary)["built"] = true
	o["queue"] = []
	for k in o["buildings"].keys():
		var b: Dictionary = o["buildings"][k]
		b["lvl"] = maxi(1, int(floor(float(b["lvl"]) * retain)))
	o["relay_lvl"] = 1
