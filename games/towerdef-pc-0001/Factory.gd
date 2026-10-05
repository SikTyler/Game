extends RefCounted
## The Factory (PLAYTEST_FEEDBACK_2, plan WP3): the Factorio-style Outpost.
## Pure static rules over save.factory; no engine nodes, no clocks except the
## `now` (unix seconds) callers inject.
##   factory = {v, chunks: [k], next_uid, ents: {"<uid>": ent}, tech: [id],
##     fac: {research, barracks, archive, scrapyard} (levels), bank: {cur},
##     rate: {cur: per s}, rate_rev, meter: {t, got, items}, items_rate,
##     frac: {cur}, data, acc, t (unix s of the last settle), rev, migrated}
##   ent = {id, x, y, rot, st} + per-kind state:
##     belt / belt2 / ug_in / ug_out: it [[item, pos]] (front first)
##     splitter: buf [item], tog;  inserter: hand, t;  miner: p, out
##     smelter / assembler: rec, in {item: n}, out {item: n}, p
##     chest / vault: inv {item: n};  coal_gen: fuel, burn
## Simulation: fixed DT steps, entities in ascending uid order, so a factory
## state + a step count always gives the same result. Live while the Outpost
## screen is open (live()); away / in-run production is the measured
## steady-state rate (meter, or estimate_rate() on a copy) x elapsed time,
## capped by storage (away_cap_s), banked at the Relay until collected.

const DB := preload("res://data/FactoryDB.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const TuneRef := preload("res://Tune.gd")

const DIRS: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const BELTS: Array = ["belt", "belt2", "ug_in", "ug_out"]
const MACHINES: Array = ["smelter", "assembler"]
const MINERS: Array = ["miner", "miner2"]
const STORES: Array = ["chest", "vault"]
const GENS: Array = ["windmill", "coal_gen", "relay"]
const SIM_MAX_STEPS: int = 25   # live(): at most this many steps per frame

static var _compiled: Dictionary = {}     # rev -> compiled structure
static var _deposits: Dictionary = {}     # cell key -> res (fixed map, built once)
static var _rocks: Dictionary = {}


# ================================================================ blocks
static func default_block() -> Dictionary:
	var f: Dictionary = {"v": 1, "chunks": DB.START_CHUNKS.duplicate(), "next_uid": 1, "ents": {}, "tech": [],
		"fac": {"research": 1, "barracks": 0, "archive": 0, "scrapyard": 0},
		"bank": _zero(), "rate": _zero(), "rate_rev": -1, "meter": {"t": 0.0, "got": _zero(), "items": {}}, "items_rate": {},
		"frac": _zero(), "data": 0, "acc": 0.0, "t": 0, "rev": 0, "migrated": false}
	for h in DB.HUBS:
		var p: Vector2i = DB.HUB_POS[h]
		_add(f, String(h), p.x, p.y, 0)
	f["rev"] = _layout_rev(f)
	return f


## A playable starter: an iron miner belted into the Relay (ore sells), with
## a Wind Turbine. New saves and migrated Outposts get it (free).
static func add_starter(f: Dictionary) -> void:
	_add(f, "miner", 41, 19, 0)            # iron patch 40..44 x 18..21; output (43, 19)
	for x in range(43, 46):
		_add(f, "belt", x, 19, 0)
	_add(f, "belt", 46, 19, 1)
	_add(f, "belt", 46, 20, 1)
	_add(f, "belt", 46, 21, 1)             # feeds the Relay at (46, 22)
	_add(f, "windmill", 43, 21, 0)
	f["rev"] = _layout_rev(f)


static func _zero() -> Dictionary:
	return {"coins": 0.0, "scrap": 0.0, "keys": 0.0, "data": 0.0}


## Layout fingerprint: the compile cache key. A pure function of the
## placed entities, so JSON + normalize round-trips are stable and a
## simulated copy shares its original's compiled structure.
static func _layout_rev(f: Dictionary) -> int:
	var ents: Dictionary = f["ents"]
	var keys: Array = ents.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(String(a)) < int(String(b)))
	var parts: PackedStringArray = PackedStringArray()
	for k in keys:
		var e: Dictionary = ents[k]
		parts.append("%s:%s:%d:%d:%d" % [String(k), String(e["id"]), int(e["x"]), int(e["y"]), int(e["rot"])])
	return absi(";".join(parts).hash()) + 1


static func _f(s: Dictionary) -> Dictionary:
	if not (s.get("factory", null) is Dictionary):
		s["factory"] = default_block()
	return s["factory"]


static func _new_state(id: String) -> Dictionary:
	if BELTS.has(id):
		return {"it": []}
	match id:
		"splitter":
			return {"buf": [], "tog": 0}
		"inserter":
			return {"hand": "", "t": 0.0}
		"miner", "miner2":
			return {"p": 0.0, "out": ""}
		"smelter", "assembler":
			return {"rec": "", "in": {}, "out": {}, "p": 0.0}
		"chest", "vault":
			return {"inv": {}}
		"coal_gen":
			return {"fuel": 0, "burn": 0.0}
	return {}


static func _add(f: Dictionary, id: String, x: int, y: int, rot: int) -> String:
	var uid: String = str(int(f["next_uid"]))
	f["next_uid"] = int(f["next_uid"]) + 1
	var e: Dictionary = {"id": id, "x": x, "y": y, "rot": rot, "st": ""}
	e.merge(_new_state(id))
	(f["ents"] as Dictionary)[uid] = e
	return uid


## Coerce a raw (JSON) block. Unknown ids and invalid placements are dropped;
## hubs are re-added at their fixed spots if missing.
static func normalize_block(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return default_block()
	var r: Dictionary = raw
	var f: Dictionary = default_block()
	f["ents"] = {}
	var ch: Array = []
	for v in r.get("chunks", []):
		var k: int = int(v)
		if k >= 0 and k < DB.CW * DB.CH and not ch.has(k):
			ch.append(k)
	for k in DB.START_CHUNKS:
		if not ch.has(k):
			ch.append(k)
	ch.sort()
	f["chunks"] = ch
	var tech: Array = []
	for v in r.get("tech", []):
		if DB.TECH.has(String(v)) and not tech.has(String(v)):
			tech.append(String(v))
	f["tech"] = tech
	var fac_in: Dictionary = r.get("fac", {}) if r.get("fac", {}) is Dictionary else {}
	for id in DB.FAC_IDS:
		var lo: int = 1 if id == "research" else 0
		(f["fac"] as Dictionary)[id] = clampi(int(fac_in.get(id, lo)), lo, int((DB.FACILITIES[id] as Dictionary)["max"]))
	for key in ["bank", "rate", "frac"]:
		var src: Dictionary = r.get(key, {}) if r.get(key, {}) is Dictionary else {}
		for c in DB.CURRENCIES:
			(f[key] as Dictionary)[c] = maxf(0.0, float(src.get(c, 0.0)))
	f["data"] = maxi(0, int(r.get("data", 0)))
	f["t"] = maxi(0, int(r.get("t", 0)))
	f["migrated"] = bool(r.get("migrated", false))
	var ir: Dictionary = r.get("items_rate", {}) if r.get("items_rate", {}) is Dictionary else {}
	for it in ir.keys():
		if DB.ITEMS.has(String(it)):
			(f["items_rate"] as Dictionary)[String(it)] = maxf(0.0, float(ir[it]))
	var ein: Dictionary = r.get("ents", {}) if r.get("ents", {}) is Dictionary else {}
	var keys: Array = ein.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(String(a)) < int(String(b)))
	var hi: int = 0
	var occ: Dictionary = {}
	var hubs_seen: Dictionary = {}
	for k in keys:
		var e: Variant = ein[k]
		if not (e is Dictionary) or int(String(k)) <= 0:
			continue
		var ed: Dictionary = e
		var id: String = String(ed.get("id", ""))
		if not DB.DEFS.has(id):
			continue
		var x: int = int(ed.get("x", -1))
		var y: int = int(ed.get("y", -1))
		var rot: int = posmod(int(ed.get("rot", 0)), 4)
		if DB.HUBS.has(id):
			if hubs_seen.has(id):
				continue
			var hp: Vector2i = DB.HUB_POS[id]
			x = hp.x
			y = hp.y
			rot = 0
			hubs_seen[id] = true
		var cells: Array = footprint(id, x, y, rot)
		var ok: bool = true
		for c in cells:
			if not in_map(c) or occ.has(_key(c)) or (not DB.HUBS.has(id) and (not _open(f, c) or is_rock(c))):
				ok = false
		if not ok:
			continue
		for c in cells:
			occ[_key(c)] = true
		var ne: Dictionary = {"id": id, "x": x, "y": y, "rot": rot, "st": String(ed.get("st", ""))}
		ne.merge(_clean_state(id, ed))
		var uid: String = str(int(String(k)))
		(f["ents"] as Dictionary)[uid] = ne
		hi = maxi(hi, int(uid))
	f["next_uid"] = maxi(hi + 1, int(r.get("next_uid", 1)))
	for h in DB.HUBS:
		if not hubs_seen.has(h):
			var hp2: Vector2i = DB.HUB_POS[h]
			var blocked: bool = false
			for c in footprint(String(h), hp2.x, hp2.y, 0):
				if occ.has(_key(c)):
					blocked = true
			if not blocked:
				_add(f, String(h), hp2.x, hp2.y, 0)
	f["rev"] = _layout_rev(f)
	f["rate_rev"] = int(f["rev"]) if int(r.get("rate_rev", -1)) == int(f["rev"]) else -1   # a measured rate stays valid for its layout
	return f


static func _clean_state(id: String, ed: Dictionary) -> Dictionary:
	var st: Dictionary = _new_state(id)
	if st.has("it"):
		var its: Array = []
		for v in ed.get("it", []):
			if v is Array and (v as Array).size() == 2 and DB.ITEMS.has(String((v as Array)[0])):
				its.append([String((v as Array)[0]), maxf(0.0, float((v as Array)[1]))])
		its.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
		st["it"] = its
	if st.has("buf"):
		var b: Array = []
		for v in ed.get("buf", []):
			if DB.ITEMS.has(String(v)) and b.size() < 4:
				b.append(String(v))
		st["buf"] = b
		st["tog"] = int(ed.get("tog", 0)) % 2
	if st.has("hand"):
		st["hand"] = String(ed.get("hand", "")) if DB.ITEMS.has(String(ed.get("hand", ""))) else ""
		st["t"] = maxf(0.0, float(ed.get("t", 0.0)))
	if st.has("p"):
		st["p"] = clampf(float(ed.get("p", 0.0)), 0.0, 1.0)
	if st.has("out") and st["out"] is String:
		st["out"] = String(ed.get("out", "")) if DB.ITEMS.has(String(ed.get("out", ""))) else ""
	if st.has("rec"):
		var rec: String = String(ed.get("rec", ""))
		st["rec"] = rec if DB.RECIPES.has(rec) and String((DB.RECIPES[rec] as Dictionary)["at"]) == id else ""
		st["in"] = _clean_inv(ed.get("in", {}))
		st["out"] = _clean_inv(ed.get("out", {}))
	if st.has("inv"):
		st["inv"] = _clean_inv(ed.get("inv", {}))
	if st.has("fuel"):
		st["fuel"] = clampi(int(ed.get("fuel", 0)), 0, 5)
		st["burn"] = maxf(0.0, float(ed.get("burn", 0.0)))
	return st


static func _clean_inv(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for k in (raw as Dictionary).keys():
			var n: int = int((raw as Dictionary)[k])
			if DB.ITEMS.has(String(k)) and n > 0:
				out[String(k)] = n
	return out


## Save migration: the plot/generator Outpost is retired. Generators,
## conduits, beacons, warehouses and decor are refunded (what was spent +
## whatever they had stored); Research Hall / Barracks / Archive / Salvage
## Yard levels move to factory facilities. Idempotent (factory.migrated).
## Returns {coins, scrap, keys} refunded.
static func migrate_outpost(s: Dictionary) -> Dictionary:
	var f: Dictionary = _f(s)
	var out: Dictionary = {"coins": 0, "scrap": 0, "keys": 0}
	if bool(f.get("migrated", false)):
		return out
	f["migrated"] = true
	if (f["ents"] as Dictionary).size() <= DB.HUBS.size():
		add_starter(f)
	var o: Variant = s.get("outpost", null)
	if not (o is Dictionary):
		return out
	var od: Dictionary = o
	var bl: Dictionary = od.get("buildings", {}) if od.get("buildings", {}) is Dictionary else {}
	var keep: Dictionary = {}
	for k in bl.keys():
		var b: Dictionary = bl[k]
		var id: String = String(b.get("id", ""))
		if DB.FACILITIES.has(id):
			if bool(b.get("built", true)):
				var fac: Dictionary = f["fac"]
				fac[id] = clampi(maxi(int(fac.get(id, 0)), int(b.get("lvl", 1))), 0, int((DB.FACILITIES[id] as Dictionary)["max"]))
			keep[k] = b
			continue
		out["coins"] = int(out["coins"]) + maxi(0, int(b.get("spent", 0)))
		var res: String = String(OutpostDB.get_def(id).get("res", ""))
		if res != "" and out.has(res):
			out[res] = int(out[res]) + int(floor(maxf(0.0, float(b.get("stored", 0.0)))))
	var dc: Dictionary = od.get("decor", {}) if od.get("decor", {}) is Dictionary else {}
	for k in dc.keys():
		out["coins"] = int(out["coins"]) + int((OutpostDB.DECOR.get(String((dc[k] as Dictionary).get("id", "")), {"coins": 0}) as Dictionary).get("coins", 0))
	out["coins"] = int(out["coins"]) + maxi(0, int(od.get("credit", 0)))
	od["buildings"] = keep
	od["decor"] = {}
	od["credit"] = 0
	od["queue"] = []
	for c in ["coins", "scrap", "keys"]:
		s[c] = int(s.get(c, 0)) + int(out[c])
	return out


# ================================================================ geometry
static func _key(c: Vector2i) -> int:
	return c.y * DB.W + c.x


static func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < DB.W and c.y < DB.H


static func chunk_of(c: Vector2i) -> int:
	if not in_map(c):
		return -1
	return (c.y / DB.CHUNK) * DB.CW + c.x / DB.CHUNK


static func _open(f: Dictionary, c: Vector2i) -> bool:
	return (f["chunks"] as Array).has(chunk_of(c))


static func is_open(s: Dictionary, c: Vector2i) -> bool:
	return in_map(c) and _open(_f(s), c)


static func footprint(id: String, x: int, y: int, rot: int) -> Array:
	var sz: Vector2i = DB.size_of(id, rot)
	var out: Array = []
	for dy in sz.y:
		for dx in sz.x:
			out.append(Vector2i(x + dx, y + dy))
	return out


static func _build_map() -> void:
	if not _deposits.is_empty():
		return
	for d in DB.STARTER_DEPOSITS:
		for yy in range(int(d[2]), int(d[2]) + int(d[4])):
			for xx in range(int(d[1]), int(d[1]) + int(d[3])):
				_deposits[_key(Vector2i(xx, yy))] = String(d[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = DB.DEPOSIT_SEED
	for k in DB.CW * DB.CH:
		var cr: Rect2i = DB.chunk_rect(k)
		var start: bool = DB.START_CHUNKS.has(k)
		var patches: int = 0 if start else 2 + rng.randi_range(0, 1)
		for p in patches:
			var res: String = String(DB.DEPOSIT_RES[rng.randi_range(0, DB.DEPOSIT_RES.size() - 1)])
			var w: int = rng.randi_range(3, 6)
			var h: int = rng.randi_range(3, 5)
			var px: int = cr.position.x + rng.randi_range(1, DB.CHUNK - w - 1)
			var py: int = cr.position.y + rng.randi_range(1, DB.CHUNK - h - 1)
			for yy in range(py, py + h):
				for xx in range(px, px + w):
					# ragged patch edges
					if (xx == px or xx == px + w - 1) and (yy == py or yy == py + h - 1):
						continue
					if not _deposits.has(_key(Vector2i(xx, yy))):
						_deposits[_key(Vector2i(xx, yy))] = res
		for i in (0 if start else DB.ROCKS_PER_CHUNK):
			var rc: Vector2i = Vector2i(cr.position.x + rng.randi_range(0, DB.CHUNK - 1), cr.position.y + rng.randi_range(0, DB.CHUNK - 1))
			if not _deposits.has(_key(rc)):
				_rocks[_key(rc)] = true


## Deposit under a cell ("" = none). Hidden-ness is a view concern
## (deposit_visible): the map itself is fixed.
static func deposit_at(c: Vector2i) -> String:
	_build_map()
	return String(_deposits.get(_key(c), ""))


static func deposit_visible(s: Dictionary, c: Vector2i) -> bool:
	return is_open(s, c) and deposit_at(c) != ""


static func is_rock(c: Vector2i) -> bool:
	_build_map()
	return _rocks.has(_key(c))


## All deposit cells of a chunk (used by the reveal toast / tests).
static func chunk_deposits(k: int) -> Dictionary:
	_build_map()
	var out: Dictionary = {}
	var r: Rect2i = DB.chunk_rect(k)
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			var d: String = String(_deposits.get(_key(Vector2i(xx, yy)), ""))
			if d != "":
				out[d] = int(out.get(d, 0)) + 1
	return out


static func ent(s: Dictionary, uid: String) -> Dictionary:
	return (_f(s)["ents"] as Dictionary).get(uid, {})


static func uid_at(s: Dictionary, c: Vector2i) -> String:
	return String((_compile(_f(s))["occ"] as Dictionary).get(_key(c), ""))


static func count_of(s: Dictionary, id: String) -> int:
	var n: int = 0
	for k in (_f(s)["ents"] as Dictionary).keys():
		if String(((_f(s)["ents"] as Dictionary)[k] as Dictionary)["id"]) == id:
			n += 1
	return n


static func has_tech(s: Dictionary, id: String) -> bool:
	return id == "" or (_f(s)["tech"] as Array).has(id)


# ================================================================ compile
## Structure derived from the layout, cached by the factory's rev (every
## edit takes a fresh, process-unique rev, so a simulated copy shares it).
static func _compile(f: Dictionary) -> Dictionary:
	var rev: int = int(f.get("rev", 0))
	var ents: Dictionary = f["ents"]
	if _compiled.has(rev) and int((_compiled[rev] as Dictionary)["n"]) == ents.size():
		return _compiled[rev]
	var occ: Dictionary = {}
	var order: Array = ents.keys()
	order.sort_custom(func(a: Variant, b: Variant) -> bool: return int(String(a)) < int(String(b)))
	for uid in order:
		var e: Dictionary = ents[uid]
		for c in footprint(String(e["id"]), int(e["x"]), int(e["y"]), int(e["rot"])):
			occ[_key(c)] = String(uid)
	var tgt: Dictionary = {}     # uid -> [target uid, entry] (belts, miners, inserters: drop)
	var src: Dictionary = {}     # inserter uid -> source uid
	var lane: Dictionary = {}    # splitter uid -> [uid0, uid1]
	var blen: Dictionary = {}    # belt uid -> length (ug_in = tunnel length)
	for uid in order:
		var e: Dictionary = ents[uid]
		var id: String = String(e["id"])
		var rot: int = int(e["rot"])
		var p: Vector2i = Vector2i(int(e["x"]), int(e["y"]))
		var d: Vector2i = DIRS[rot]
		if id == "ug_in":
			var link: String = ""
			var dist: int = 1
			for i in range(1, DB.UG_RANGE + 2):
				var q: String = String(occ.get(_key(p + d * i), ""))
				if q != "" and String((ents[q] as Dictionary)["id"]) == "ug_out" and int((ents[q] as Dictionary)["rot"]) == rot:
					link = q
					dist = i
					break
			tgt[uid] = [link, 0.0]
			blen[uid] = float(dist)
		elif BELTS.has(id):
			tgt[uid] = _belt_target(ents, occ, p + d, rot)
			blen[uid] = 1.0
		elif id == "inserter":
			src[uid] = String(occ.get(_key(p - d), ""))
			tgt[uid] = [String(occ.get(_key(p + d), "")), 0.5]
		elif MINERS.has(id):
			tgt[uid] = _belt_target(ents, occ, miner_out(id, p.x, p.y, rot), rot)
		elif id == "splitter":
			var l: Array = []
			for c in footprint(id, p.x, p.y, rot):
				l.append(_belt_target(ents, occ, (c as Vector2i) + d, rot))
			lane[uid] = l
	# never let a building feed itself (a machine output cell inside its own footprint cannot happen; guard anyway)
	for uid in tgt.keys():
		if String((tgt[uid] as Array)[0]) == String(uid):
			tgt[uid] = ["", 0.0]
	var pw: Dictionary = _power_graph(ents, order)
	var c: Dictionary = {"n": ents.size(), "occ": occ, "order": order, "tgt": tgt, "src": src, "lane": lane, "blen": blen,
		"net_of": pw["net_of"], "nets": pw["nets"]}
	if _compiled.size() > 12:
		_compiled.clear()
	_compiled[rev] = c
	return c


## Where something moving `rot` into cell `c` lands: [uid, entry pos]. A belt
## fed from behind takes it at 0, from the side at 0.5; head-on is refused.
static func _belt_target(ents: Dictionary, occ: Dictionary, c: Vector2i, rot: int) -> Array:
	var q: String = String(occ.get(_key(c), ""))
	if q == "":
		return ["", 0.0]
	var te: Dictionary = ents[q]
	var tid: String = String(te["id"])
	if BELTS.has(tid):
		var tr: int = int(te["rot"])
		if tr == rot:
			return [q, 0.0]
		if (tr + 2) % 4 == rot:
			return ["", 0.0]
		if tid == "ug_out":
			return ["", 0.0]       # exits only take items from their entrance
		return [q, 0.5]
	return [q, 0.0]


## The cell a miner drops onto: the front cell on its left (relative to rot).
static func miner_out(id: String, x: int, y: int, rot: int) -> Vector2i:
	var sz: Vector2i = DB.size_of(id, rot)
	match rot:
		0:
			return Vector2i(x + sz.x, y)
		1:
			return Vector2i(x + sz.x - 1, y + sz.y)
		2:
			return Vector2i(x - 1, y + sz.y - 1)
	return Vector2i(x, y - 1)


static func _center(e: Dictionary) -> Vector2:
	var sz: Vector2i = DB.size_of(String(e["id"]), int(e["rot"]))
	return Vector2(float(e["x"]) + float(sz.x) * 0.5, float(e["y"]) + float(sz.y) * 0.5)


## Power networks: poles, generators and the Relay are nodes; nodes within
## LINK_RANGE (centre to centre) join; every node powers cells within
## POLE_REACH of its footprint. Consumers take the lowest-index net covering
## any of their cells.
static func _power_graph(ents: Dictionary, order: Array) -> Dictionary:
	var nodes: Array = []
	for uid in order:
		var id: String = String((ents[uid] as Dictionary)["id"])
		if id == "pole" or GENS.has(id):
			nodes.append(uid)
	var net_idx: Dictionary = {}
	var nets: Array = []
	for n in nodes:
		if net_idx.has(n):
			continue
		var ni: int = nets.size()
		var members: Array = []
		var stack: Array = [n]
		net_idx[n] = ni
		while not stack.is_empty():
			var a: String = String(stack.pop_back())
			members.append(a)
			for b in nodes:
				if not net_idx.has(b) and _center(ents[a]).distance_to(_center(ents[b])) <= DB.LINK_RANGE:
					net_idx[b] = ni
					stack.append(b)
		members.sort_custom(func(a: Variant, b: Variant) -> bool: return int(String(a)) < int(String(b)))
		nets.append({"nodes": members, "users": []})
	var cover: Dictionary = {}
	for n in nodes:
		var e: Dictionary = ents[n]
		var sz: Vector2i = DB.size_of(String(e["id"]), int(e["rot"]))
		var ni2: int = int(net_idx[n])
		for yy in range(int(e["y"]) - DB.POLE_REACH, int(e["y"]) + sz.y + DB.POLE_REACH):
			for xx in range(int(e["x"]) - DB.POLE_REACH, int(e["x"]) + sz.x + DB.POLE_REACH):
				var k: int = _key(Vector2i(xx, yy))
				if not cover.has(k) or int(cover[k]) > ni2:
					cover[k] = ni2
	var net_of: Dictionary = {}
	for uid in order:
		var e2: Dictionary = ents[uid]
		if float(DB.get_def(String(e2["id"])).get("power", 0.0)) <= 0.0:
			continue
		var best: int = -1
		for c in footprint(String(e2["id"]), int(e2["x"]), int(e2["y"]), int(e2["rot"])):
			var k2: int = _key(c)
			if cover.has(k2) and (best < 0 or int(cover[k2]) < best):
				best = int(cover[k2])
		if best >= 0:
			net_of[uid] = best
			((nets[best] as Dictionary)["users"] as Array).append(uid)
	return {"net_of": net_of, "nets": nets}


static func _supply_of(e: Dictionary) -> float:
	var id: String = String(e["id"])
	if id == "coal_gen":
		return float(DB.get_def(id)["supply"]) if float(e.get("burn", 0.0)) > 0.0 else 0.0
	return float(DB.get_def(id).get("supply", 0.0))


## Per-net {supply, demand, sat}. sat = min(1, supply / demand).
static func power_report(s: Dictionary) -> Array:
	var f: Dictionary = _f(s)
	return _power_now(f, _compile(f))


static func _power_now(f: Dictionary, c: Dictionary) -> Array:
	var ents: Dictionary = f["ents"]
	var out: Array = []
	for net in c["nets"]:
		var sup: float = 0.0
		var dem: float = 0.0
		for n in (net as Dictionary)["nodes"]:
			sup += _supply_of(ents[n])
		for u in (net as Dictionary)["users"]:
			dem += float(DB.get_def(String((ents[u] as Dictionary)["id"])).get("power", 0.0))
		out.append({"supply": sup, "demand": dem, "sat": 1.0 if dem <= 0.0 else minf(1.0, sup / dem)})
	return out


## Power satisfaction for one entity (1 for unpowered kinds, 0 when unlinked).
static func sat_of(s: Dictionary, uid: String) -> float:
	var f: Dictionary = _f(s)
	var c: Dictionary = _compile(f)
	var e: Dictionary = (f["ents"] as Dictionary).get(uid, {})
	if e.is_empty() or float(DB.get_def(String(e["id"])).get("power", 0.0)) <= 0.0:
		return 1.0
	if not (c["net_of"] as Dictionary).has(uid):
		return 0.0
	return float((_power_now(f, c)[int(c["net_of"][uid])] as Dictionary)["sat"])


# ================================================================ items
static func _inv_total(inv: Dictionary) -> int:
	var n: int = 0
	for k in inv.keys():
		n += int(inv[k])
	return n


static func _recipe_for(e: Dictionary, item: String) -> String:
	var rec: String = String(e.get("rec", ""))
	if String(e["id"]) == "smelter" and DB.SMELT_BY_INPUT.has(item):
		var idle: bool = (e["in"] as Dictionary).is_empty() and (e["out"] as Dictionary).is_empty() and float(e["p"]) <= 0.0
		if rec == "" or idle:
			return String(DB.SMELT_BY_INPUT[item])
	return rec


## Can `e` take `item` (entry for belts)? Pure check, no mutation.
static func _accepts(f: Dictionary, e: Dictionary, item: String, entry: float) -> bool:
	var id: String = String(e["id"])
	if BELTS.has(id):
		for it in e["it"]:
			if absf(float((it as Array)[1]) - entry) < DB.GAP:
				return false
		return true
	match id:
		"splitter":
			return (e["buf"] as Array).size() < 4
		"chest", "vault":
			return _inv_total(e["inv"]) < int(DB.get_def(id)["cap"])
		"relay":
			return DB.VALUE.has(item)
		"coal_gen":
			return item == "coal" and int(e["fuel"]) < 5
		"smelter", "assembler":
			var rec: String = _recipe_for(e, item)
			if rec == "" or not has_tech_f(f, String((DB.RECIPES[rec] as Dictionary)["tech"])):
				return false
			var need: Dictionary = (DB.RECIPES[rec] as Dictionary)["in"]
			if not need.has(item):
				return false
			return int((e["in"] as Dictionary).get(item, 0)) < int(need[item]) * DB.MACHINE_BUF
	return false


static func has_tech_f(f: Dictionary, id: String) -> bool:
	return id == "" or (f["tech"] as Array).has(id)


## Put `item` into `e` (after _accepts). Relay pays out immediately.
static func _insert(s: Dictionary, f: Dictionary, e: Dictionary, item: String, entry: float) -> void:
	var id: String = String(e["id"])
	if BELTS.has(id):
		var its: Array = e["it"]
		var at: int = its.size()
		for i in its.size():
			if float((its[i] as Array)[1]) < entry:
				at = i
				break
		its.insert(at, [item, entry])
		return
	match id:
		"splitter":
			(e["buf"] as Array).append(item)
		"chest", "vault":
			(e["inv"] as Dictionary)[item] = int((e["inv"] as Dictionary).get(item, 0)) + 1
		"relay":
			_sell(s, f, item)
		"coal_gen":
			e["fuel"] = int(e["fuel"]) + 1
		"smelter", "assembler":
			var rec: String = _recipe_for(e, item)
			e["rec"] = rec
			(e["in"] as Dictionary)[item] = int((e["in"] as Dictionary).get(item, 0)) + 1


static func _push(s: Dictionary, f: Dictionary, t: Array, item: String) -> bool:
	var uid: String = String(t[0])
	if uid == "":
		return false
	var e: Dictionary = (f["ents"] as Dictionary).get(uid, {})
	if e.is_empty() or not _accepts(f, e, item, float(t[1])):
		return false
	_insert(s, f, e, item, float(t[1]))
	return true


## An item a source can hand an inserter that the target accepts ("" none).
static func _peek(f: Dictionary, se: Dictionary, te: Dictionary, entry: float) -> String:
	var id: String = String(se["id"])
	var cands: Array = []
	if BELTS.has(id):
		for it in se["it"]:
			cands.append(String((it as Array)[0]))
	elif id == "splitter":
		cands = (se["buf"] as Array).duplicate()
	elif MINERS.has(id):
		if String(se["out"]) != "":
			cands = [String(se["out"])]
	elif STORES.has(id):
		for it in DB.ITEM_IDS:
			if int((se["inv"] as Dictionary).get(it, 0)) > 0:
				cands.append(it)
	elif MACHINES.has(id):
		for it in DB.ITEM_IDS:
			if int((se["out"] as Dictionary).get(it, 0)) > 0:
				cands.append(it)
	for it in cands:
		if _accepts(f, te, String(it), entry):
			return String(it)
	return ""


static func _take(se: Dictionary, item: String) -> void:
	var id: String = String(se["id"])
	if BELTS.has(id):
		var its: Array = se["it"]
		for i in its.size():
			if String((its[i] as Array)[0]) == item:
				its.remove_at(i)
				return
	elif id == "splitter":
		(se["buf"] as Array).erase(item)
	elif MINERS.has(id):
		se["out"] = ""
	else:
		var inv: Dictionary = se["inv"] if STORES.has(id) else se["out"]
		inv[item] = int(inv[item]) - 1
		if int(inv[item]) <= 0:
			inv.erase(item)


# ================================================================ economy
static func _sell(s: Dictionary, f: Dictionary, item: String) -> void:
	var v: Dictionary = DB.VALUE.get(item, {})
	var m: Dictionary = f["meter"]
	(m["items"] as Dictionary)[item] = int((m["items"] as Dictionary).get(item, 0)) + 1
	for cur in v.keys():
		var amt: float = float(v[cur]) * value_mult(s, String(cur))
		(m["got"] as Dictionary)[cur] = float((m["got"] as Dictionary).get(cur, 0.0)) + amt
		_pay(s, f, String(cur), amt)


## Relay payout multiplier per currency (tune knob; coins scale with the
## highest tier reached like the old Coin Mill: x(1 + 0.8 x (tier - 1))).
static func value_mult(s: Dictionary, cur: String) -> float:
	if cur == "coins":
		var hi: int = 1
		var bw: Variant = s.get("best_wave_by_tier", {})
		if bw is Dictionary:
			for k in (bw as Dictionary).keys():
				if int((bw as Dictionary)[k]) > 0 or int(String(k)) == 1:
					hi = maxi(hi, int(String(k)))
		return TuneRef.num("factory_coin", 1.0) * (1.0 + OutpostDB.MILL_TIER * float(hi - 1))
	return TuneRef.num("factory_" + cur, 1.0)


## Whole units go to the save; fractions carry in factory.frac.
static func _pay(s: Dictionary, f: Dictionary, cur: String, amt: float) -> void:
	var fr: Dictionary = f["frac"]
	var tot: float = float(fr.get(cur, 0.0)) + amt
	var n: int = int(floor(tot))
	fr[cur] = tot - float(n)
	if n <= 0:
		return
	match cur:
		"coins":
			s["coins"] = int(s.get("coins", 0)) + n
			if s.get("reforge", null) is Dictionary:
				(s["reforge"] as Dictionary)["coins_since"] = int((s["reforge"] as Dictionary).get("coins_since", 0)) + n
		"scrap", "keys":
			s[cur] = int(s.get(cur, 0)) + n
		"data":
			f["data"] = int(f.get("data", 0)) + n


# ================================================================ tick
## One fixed step of DB.DT seconds.
static func step(s: Dictionary) -> void:
	var f: Dictionary = _f(s)
	var c: Dictionary = _compile(f)
	var ents: Dictionary = f["ents"]
	var dt: float = DB.DT
	# 1) generators burn fuel, then power satisfaction per net
	for uid in c["order"]:
		var g: Dictionary = ents[uid]
		if String(g["id"]) == "coal_gen":
			if float(g["burn"]) <= 0.0 and int(g["fuel"]) > 0:
				g["fuel"] = int(g["fuel"]) - 1
				g["burn"] = float(g["burn"]) + float(DB.get_def("coal_gen")["burn"])
			g["st"] = "on" if float(g["burn"]) > 0.0 else "no fuel"
	var pw: Array = _power_now(f, c)
	for uid in c["order"]:
		var g2: Dictionary = ents[uid]
		if String(g2["id"]) == "coal_gen" and float(g2["burn"]) > 0.0:
			g2["burn"] = maxf(0.0, float(g2["burn"]) - dt)
	var net_of: Dictionary = c["net_of"]
	for uid in c["order"]:
		var e: Dictionary = ents[uid]
		var id: String = String(e["id"])
		var sat: float = 1.0
		if float(DB.get_def(id).get("power", 0.0)) > 0.0:
			sat = float((pw[int(net_of[uid])] as Dictionary)["sat"]) if net_of.has(uid) else 0.0
		if MINERS.has(id):
			_step_miner(s, f, c, String(uid), e, sat, dt)
		elif MACHINES.has(id):
			_step_machine(f, e, sat, dt)
		elif id == "inserter":
			_step_inserter(s, f, c, String(uid), e, sat, dt)
		elif BELTS.has(id):
			_step_belt(s, f, c, String(uid), e, dt)
		elif id == "splitter":
			_step_splitter(s, f, c, String(uid), e)
	# 2) throughput meter
	var m: Dictionary = f["meter"]
	m["t"] = float(m["t"]) + dt
	if float(m["t"]) >= DB.METER_WINDOW:
		_close_window(f)


static func _close_window(f: Dictionary) -> void:
	var m: Dictionary = f["meter"]
	var t: float = maxf(0.001, float(m["t"]))
	for cur in DB.CURRENCIES:
		(f["rate"] as Dictionary)[cur] = float((m["got"] as Dictionary).get(cur, 0.0)) / t
	var ir: Dictionary = {}
	for it in (m["items"] as Dictionary).keys():
		ir[it] = float((m["items"] as Dictionary)[it]) / t
	f["items_rate"] = ir
	f["rate_rev"] = int(f["rev"])
	f["meter"] = {"t": 0.0, "got": _zero(), "items": {}}


static func _step_miner(s: Dictionary, f: Dictionary, c: Dictionary, uid: String, e: Dictionary, sat: float, dt: float) -> void:
	var id: String = String(e["id"])
	var res: String = ""
	for cell in footprint(id, int(e["x"]), int(e["y"]), int(e["rot"])):
		res = deposit_at(cell)
		if res != "":
			break
	if res == "":
		e["st"] = "no deposit"
		return
	if String(e["out"]) == "":
		var rate: float = DB.MINER2_RATE if id == "miner2" else DB.MINER_RATE
		e["p"] = float(e["p"]) + dt * sat * rate
		if float(e["p"]) >= 1.0:
			e["p"] = float(e["p"]) - 1.0
			e["out"] = res
	if String(e["out"]) != "":
		if _push(s, f, (c["tgt"] as Dictionary).get(uid, ["", 0.0]), String(e["out"])):
			e["out"] = ""
			e["st"] = "working" if sat >= 0.999 else "low power"
		else:
			e["st"] = "output blocked"
	else:
		e["st"] = "no power" if sat <= 0.0 else ("working" if sat >= 0.999 else "low power")


static func _step_machine(f: Dictionary, e: Dictionary, sat: float, dt: float) -> void:
	var rec: String = String(e["rec"])
	if rec == "":
		e["st"] = "no recipe" if String(e["id"]) == "assembler" else "idle"
		return
	var r: Dictionary = DB.RECIPES[rec]
	if not has_tech_f(f, String(r["tech"])):
		e["st"] = "needs research"
		return
	var inv: Dictionary = e["in"]
	for it in (r["in"] as Dictionary).keys():
		if int(inv.get(it, 0)) < int((r["in"] as Dictionary)[it]):
			e["st"] = "starved"
			return
	if _inv_total(e["out"]) >= DB.OUT_CAP:
		e["st"] = "output full"
		return
	if sat <= 0.0:
		e["st"] = "no power"
		return
	e["p"] = float(e["p"]) + dt * sat / float(r["time"])
	e["st"] = "working" if sat >= 0.999 else "low power"
	if float(e["p"]) >= 1.0:
		e["p"] = float(e["p"]) - 1.0
		for it in (r["in"] as Dictionary).keys():
			inv[it] = int(inv[it]) - int((r["in"] as Dictionary)[it])
			if int(inv[it]) <= 0:
				inv.erase(it)
		for it in (r["out"] as Dictionary).keys():
			(e["out"] as Dictionary)[it] = int((e["out"] as Dictionary).get(it, 0)) + int((r["out"] as Dictionary)[it])


static func _step_inserter(s: Dictionary, f: Dictionary, c: Dictionary, uid: String, e: Dictionary, sat: float, dt: float) -> void:
	var cyc: float = DB.INSERTER_CYCLE
	var ents: Dictionary = f["ents"]
	var t: Array = (c["tgt"] as Dictionary).get(uid, ["", 0.0])
	var su: String = String((c["src"] as Dictionary).get(uid, ""))
	if sat <= 0.0:
		e["st"] = "no power"
		return
	e["t"] = float(e["t"]) + dt * sat
	if String(e["hand"]) == "":
		if float(e["t"]) < cyc * 0.5:
			return
		e["t"] = cyc * 0.5
		if su == "" or String(t[0]) == "":
			e["st"] = "no source" if su == "" else "no target"
			return
		var se: Dictionary = ents[su]
		var te: Dictionary = ents[String(t[0])]
		var it: String = _peek(f, se, te, float(t[1]))
		if it == "":
			e["st"] = "waiting"
			return
		_take(se, it)
		e["hand"] = it
		e["st"] = "working"
		return
	if float(e["t"]) < cyc:
		return
	e["t"] = cyc
	if _push(s, f, t, String(e["hand"])):
		e["hand"] = ""
		e["t"] = 0.0
		e["st"] = "working"
	else:
		e["st"] = "target full"


static func _step_belt(s: Dictionary, f: Dictionary, c: Dictionary, uid: String, e: Dictionary, dt: float) -> void:
	var its: Array = e["it"]
	if its.is_empty():
		e["st"] = ""
		return
	var v: float = float(DB.BELT_SPEED.get(String(e["id"]), 2.0)) * dt
	var L: float = float((c["blen"] as Dictionary).get(uid, 1.0))
	var front: Array = its[0]
	var start: int = 1
	var np: float = float(front[1]) + v
	if np >= L:
		if _push(s, f, (c["tgt"] as Dictionary).get(uid, ["", 0.0]), String(front[0])):
			its.remove_at(0)
			start = 0
			e["st"] = ""
		else:
			front[1] = L
			e["st"] = "blocked"
	else:
		front[1] = np
		e["st"] = ""
	for i in range(start, its.size()):
		var a: Array = its[i]
		var p: float = minf(float(a[1]) + v, L)
		if i > 0:
			p = minf(p, float((its[i - 1] as Array)[1]) - DB.GAP)
		a[1] = maxf(float(a[1]), p)


## Splitter: up to 2 items per step, alternating lanes; a blocked lane sends
## everything to the other one.
static func _step_splitter(s: Dictionary, f: Dictionary, c: Dictionary, uid: String, e: Dictionary) -> void:
	var buf: Array = e["buf"]
	var l: Array = (c["lane"] as Dictionary).get(uid, [])
	var sent: int = 0
	while not buf.is_empty() and sent < 2 and l.size() == 2:
		var it: String = String(buf[0])
		var k: int = int(e["tog"])
		if _push(s, f, l[k], it):
			e["tog"] = 1 - k
		elif not _push(s, f, l[1 - k], it):
			break
		buf.remove_at(0)
		sent += 1
	e["st"] = "blocked" if buf.size() >= 4 else ""


## Run whole steps of real time `delta` (live, Outpost screen open). Keeps
## the clock settled at `now` so the away estimate never double counts.
static func live(s: Dictionary, delta: float, now: int) -> int:
	var f: Dictionary = _f(s)
	f["acc"] = minf(float(f.get("acc", 0.0)) + delta, DB.DT * float(SIM_MAX_STEPS))
	var n: int = 0
	while float(f["acc"]) >= DB.DT and n < SIM_MAX_STEPS:
		step(s)
		f["acc"] = float(f["acc"]) - DB.DT
		n += 1
	f["t"] = now
	return n


static func simulate(s: Dictionary, seconds: float) -> void:
	var n: int = int(round(seconds / DB.DT))
	for i in n:
		step(s)


# ================================================================ away
## Steady-state rate {cur: per s}: simulate a copy (warm-up, then a measured
## window). Used after edits, before the live meter has a full window.
static func estimate_rate(s: Dictionary, warm: float = 60.0, window: float = 120.0) -> Dictionary:
	var f: Dictionary = _f(s)
	var copy: Dictionary = {"factory": f.duplicate(true), "best_wave_by_tier": s.get("best_wave_by_tier", {}).duplicate(true) if s.get("best_wave_by_tier", {}) is Dictionary else {}}
	var cf: Dictionary = copy["factory"]
	simulate(copy, warm)
	# a window that never closes on its own (t starts far below zero)
	cf["meter"] = {"t": -1e9, "got": _zero(), "items": {}}
	var n: int = int(round(window / DB.DT))
	for i in n:
		step(copy)
	var secs: float = float(n) * DB.DT
	var m: Dictionary = cf["meter"]
	var out: Dictionary = _zero()
	for cur in DB.CURRENCIES:
		out[cur] = float((m["got"] as Dictionary).get(cur, 0.0)) / secs
	var ir: Dictionary = {}
	for it in (m["items"] as Dictionary).keys():
		ir[it] = float((m["items"] as Dictionary)[it]) / secs
	return {"rate": out, "items": ir}


## Make factory.rate match the current layout (re-estimates after an edit).
static func ensure_rate(s: Dictionary) -> Dictionary:
	var f: Dictionary = _f(s)
	if int(f.get("rate_rev", -1)) != int(f["rev"]):
		var est: Dictionary = estimate_rate(s)
		f["rate"] = est["rate"]
		f["items_rate"] = est["items"]
		f["rate_rev"] = int(f["rev"])
	return f["rate"]


static func storage_slots(s: Dictionary) -> int:
	var n: int = 0
	for k in (_f(s)["ents"] as Dictionary).keys():
		var id: String = String(((_f(s)["ents"] as Dictionary)[k] as Dictionary)["id"])
		if STORES.has(id):
			n += int(DB.get_def(id)["cap"])
	return n


## How long the factory keeps producing unattended (seconds).
static func away_cap_s(s: Dictionary) -> float:
	return minf(DB.AWAY_MAX_H, DB.AWAY_BASE_H + DB.AWAY_PER_SLOT_H * float(storage_slots(s))) * 3600.0


## Bank the time since factory.t at the measured rate, capped by storage.
static func settle(s: Dictionary, now: int) -> void:
	var f: Dictionary = _f(s)
	var last: int = int(f.get("t", 0))
	f["t"] = now
	if last <= 0 or now <= last:
		return
	var rate: Dictionary = ensure_rate(s)
	var el: float = float(now - last)
	var cap: float = away_cap_s(s)
	var bank: Dictionary = f["bank"]
	for cur in DB.CURRENCIES:
		var r: float = float(rate.get(cur, 0.0))
		bank[cur] = minf(float(bank.get(cur, 0.0)) + r * el, r * cap)


## Pure preview of what settle() would bank (no mutation, for estimates/tests).
static func away_estimate(s: Dictionary, seconds: float) -> Dictionary:
	var rate: Dictionary = ensure_rate(s)
	var out: Dictionary = {}
	var cap: float = away_cap_s(s)
	for cur in DB.CURRENCIES:
		out[cur] = float(rate.get(cur, 0.0)) * minf(seconds, cap)
	return out


## "While you were away": settle, then report the bank (zeros under
## offline_min or on a first boot).
static func away_report(s: Dictionary, now: int) -> Dictionary:
	var f: Dictionary = _f(s)
	var last: int = int(f.get("t", 0))
	settle(s, now)
	var out: Dictionary = {}
	for cur in DB.CURRENCIES:
		out[cur] = float((f["bank"] as Dictionary).get(cur, 0.0))
	var away: int = int(s.get("last_seen", 0))
	away = maxi(away, 0)
	out["minutes"] = 0 if away <= 0 or now < away else (now - away) / 60
	out["hours_cap"] = away_cap_s(s) / 3600.0
	if last <= 0:
		for cur in DB.CURRENCIES:
			out[cur] = 0.0
	return out


## Pay the bank out (whole units; fractions carry). Event "factory_bank".
static func claim_bank(s: Dictionary) -> Array:
	var f: Dictionary = _f(s)
	var bank: Dictionary = f["bank"]
	var paid: Dictionary = {}
	var any: bool = false
	for cur in DB.CURRENCIES:
		var before: int = _cur_of(s, f, cur)
		_pay(s, f, cur, float(bank.get(cur, 0.0)))
		bank[cur] = 0.0
		paid[cur] = _cur_of(s, f, cur) - before
		any = any or int(paid[cur]) > 0
	if not any:
		return []
	if s.get("stats", null) is Dictionary:
		(s["stats"] as Dictionary)["outpost_collects"] = int((s["stats"] as Dictionary).get("outpost_collects", 0)) + 1
	var ev: Dictionary = {"t": "factory_bank"}
	ev.merge(paid)
	return [ev]


static func _cur_of(s: Dictionary, f: Dictionary, cur: String) -> int:
	return int(f.get("data", 0)) if cur == "data" else int(s.get(cur, 0))


# ================================================================ build
static func cost(id: String) -> int:
	return int(DB.get_def(id).get("coins", 0))


## "" when placeable, else outside | locked | rock | occupied | no_deposit |
## tech | hub | coins.
static func place_error(s: Dictionary, id: String, x: int, y: int, rot: int, check_coins: bool = true) -> String:
	if not DB.DEFS.has(id):
		return "unknown"
	if DB.HUBS.has(id):
		return "hub"
	if not has_tech(s, String(DB.get_def(id)["tech"])):
		return "tech"
	var f: Dictionary = _f(s)
	var occ: Dictionary = _compile(f)["occ"]
	var dep: bool = false
	for c in footprint(id, x, y, rot):
		if not in_map(c):
			return "outside"
		if not _open(f, c):
			return "locked"
		if is_rock(c):
			return "rock"
		if occ.has(_key(c)):
			return "occupied"
		if deposit_at(c) != "":
			dep = true
	if MINERS.has(id) and not dep:
		return "no_deposit"
	if check_coins and int(s.get("coins", 0)) < cost(id):
		return "coins"
	return ""


static func place(s: Dictionary, id: String, x: int, y: int, rot: int) -> Array:
	if place_error(s, id, x, y, rot) != "":
		return []
	var f: Dictionary = _f(s)
	s["coins"] = int(s["coins"]) - cost(id)
	var uid: String = _add(f, id, x, y, posmod(rot, 4))
	f["rev"] = _layout_rev(f)
	return [{"t": "factory_place", "uid": uid, "id": id, "x": x, "y": y}]


## Lay a straight / L-shaped run of belts (drag): every free cell from a to b
## (x first, then y). Each piece faces the next cell. Stops when coins run out.
static func place_line(s: Dictionary, id: String, a: Vector2i, b: Vector2i, rot_hint: int = 0) -> Array:
	var cells: Array = line_cells(a, b)
	var ev: Array = []
	for i in cells.size():
		var c: Vector2i = cells[i]
		var rot: int = rot_hint
		if i + 1 < cells.size():
			rot = dir_index((cells[i + 1] as Vector2i) - c)
		elif i > 0:
			rot = dir_index(c - (cells[i - 1] as Vector2i))
		var u: String = uid_at(s, c)
		if u != "" and BELTS.has(String(ent(s, u)["id"])) and String(ent(s, u)["id"]) == id:
			rotate(s, u, rot)
			continue
		ev.append_array(place(s, id, c.x, c.y, rot))
	return ev


static func line_cells(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = [a]
	var c: Vector2i = a
	while c.x != b.x:
		c.x += signi(b.x - c.x)
		out.append(c)
	while c.y != b.y:
		c.y += signi(b.y - c.y)
		out.append(c)
	return out


static func dir_index(d: Vector2i) -> int:
	for i in 4:
		if DIRS[i] == d:
			return i
	return 0


static func rotate(s: Dictionary, uid: String, rot: int) -> Array:
	var f: Dictionary = _f(s)
	var e: Dictionary = (f["ents"] as Dictionary).get(uid, {})
	if e.is_empty() or DB.HUBS.has(String(e["id"])):
		return []
	var nr: int = posmod(rot, 4)
	if nr == int(e["rot"]):
		return []
	(f["ents"] as Dictionary).erase(uid)
	f["rev"] = _layout_rev(f)
	var ok: bool = place_error(s, String(e["id"]), int(e["x"]), int(e["y"]), nr, false) == ""
	(f["ents"] as Dictionary)[uid] = e
	if ok:
		e["rot"] = nr
	f["rev"] = _layout_rev(f)
	return [{"t": "factory_rotate", "uid": uid, "rot": int(e["rot"])}] if ok else []


## Deconstruct: full coin refund; contents are lost. Hubs refuse.
static func remove(s: Dictionary, uid: String) -> Array:
	var f: Dictionary = _f(s)
	var e: Dictionary = (f["ents"] as Dictionary).get(uid, {})
	if e.is_empty() or DB.HUBS.has(String(e["id"])):
		return []
	(f["ents"] as Dictionary).erase(uid)
	s["coins"] = int(s.get("coins", 0)) + cost(String(e["id"]))
	f["rev"] = _layout_rev(f)
	return [{"t": "factory_remove", "uid": uid, "id": String(e["id"])}]


static func set_recipe(s: Dictionary, uid: String, rec: String) -> Array:
	var e: Dictionary = ent(s, uid)
	if e.is_empty() or not MACHINES.has(String(e["id"])) or not DB.RECIPES.has(rec):
		return []
	var r: Dictionary = DB.RECIPES[rec]
	if String(r["at"]) != String(e["id"]) or not has_tech(s, String(r["tech"])):
		return []
	if String(e["rec"]) == rec:
		return []
	e["rec"] = rec
	e["in"] = {}
	e["p"] = 0.0
	_f(s)["rate_rev"] = -1
	return [{"t": "factory_recipe", "uid": uid, "rec": rec}]


# ---------------------------------------------------------------- land
static func chunk_cost(s: Dictionary) -> int:
	var bought: int = (_f(s)["chunks"] as Array).size() - DB.START_CHUNKS.size()
	return int(round(float(DB.CHUNK_BASE) * pow(DB.CHUNK_GROWTH, float(bought))))


static func chunk_adjacent(s: Dictionary, k: int) -> bool:
	var ch: Array = _f(s)["chunks"]
	if ch.has(k) or k < 0 or k >= DB.CW * DB.CH:
		return false
	var cx: int = k % DB.CW
	var cy: int = k / DB.CW
	for d in DIRS:
		var nx: int = cx + (d as Vector2i).x
		var ny: int = cy + (d as Vector2i).y
		if nx >= 0 and ny >= 0 and nx < DB.CW and ny < DB.CH and ch.has(ny * DB.CW + nx):
			return true
	return false


## Buy a land chunk; its deposits are revealed (event lists them).
static func unlock_chunk(s: Dictionary, k: int) -> Array:
	if not chunk_adjacent(s, k):
		return []
	var c: int = chunk_cost(s)
	if int(s.get("coins", 0)) < c:
		return []
	s["coins"] = int(s["coins"]) - c
	var f: Dictionary = _f(s)
	(f["chunks"] as Array).append(k)
	(f["chunks"] as Array).sort()
	f["rev"] = _layout_rev(f)
	return [{"t": "factory_chunk", "k": k, "cost": c, "deposits": chunk_deposits(k)}]


# ---------------------------------------------------------------- research / facilities
static func tech_can(s: Dictionary, id: String) -> bool:
	if not DB.TECH.has(id) or has_tech(s, id):
		return false
	var d: Dictionary = DB.TECH[id]
	return has_tech(s, String(d["req"])) and int(s.get("coins", 0)) >= int(d["coins"]) and int(_f(s).get("data", 0)) >= int(d["data"])


static func research(s: Dictionary, id: String) -> Array:
	if not tech_can(s, id):
		return []
	var d: Dictionary = DB.TECH[id]
	var f: Dictionary = _f(s)
	s["coins"] = int(s["coins"]) - int(d["coins"])
	f["data"] = int(f["data"]) - int(d["data"])
	(f["tech"] as Array).append(id)
	f["rate_rev"] = -1
	return [{"t": "factory_tech", "id": id}]


static func fac_level(s: Dictionary, id: String) -> int:
	var f: Variant = s.get("factory", null)
	if not (f is Dictionary):
		return 0
	return int(((f as Dictionary).get("fac", {}) as Dictionary).get(id, 0))


static func fac_cost(id: String, lvl: int) -> int:
	return int(round(float((DB.FACILITIES[id] as Dictionary)["coins"]) * pow(1.6, float(maxi(1, lvl) - 1))))


static func fac_upgrade(s: Dictionary, id: String) -> Array:
	if not DB.FACILITIES.has(id):
		return []
	var lvl: int = fac_level(s, id)
	if lvl >= int((DB.FACILITIES[id] as Dictionary)["max"]):
		return []
	var c: int = fac_cost(id, lvl)
	if int(s.get("coins", 0)) < c:
		return []
	s["coins"] = int(s["coins"]) - c
	(_f(s)["fac"] as Dictionary)[id] = lvl + 1
	return [{"t": "factory_fac", "id": id, "lvl": lvl + 1}]


# ---------------------------------------------------------------- info
## Nominal output per minute of a machine / miner at its current power.
static func throughput(s: Dictionary, uid: String) -> Dictionary:
	var e: Dictionary = ent(s, uid)
	if e.is_empty():
		return {}
	var id: String = String(e["id"])
	var sat: float = sat_of(s, uid)
	if MINERS.has(id):
		var res: String = ""
		for c in footprint(id, int(e["x"]), int(e["y"]), int(e["rot"])):
			res = deposit_at(c)
			if res != "":
				break
		var r: float = (DB.MINER2_RATE if id == "miner2" else DB.MINER_RATE) * 60.0 * sat
		return {res: r} if res != "" else {}
	if MACHINES.has(id) and String(e["rec"]) != "":
		var rd: Dictionary = DB.RECIPES[String(e["rec"])]
		var out: Dictionary = {}
		for it in (rd["out"] as Dictionary).keys():
			out[it] = float((rd["out"] as Dictionary)[it]) * 60.0 / float(rd["time"]) * sat
		return out
	if BELTS.has(id):
		return {"items": float(DB.BELT_SPEED.get(id, 2.0)) / DB.GAP * 60.0}
	if id == "inserter":
		return {"items": 60.0 / DB.INSERTER_CYCLE * sat}
	return {}


static func items_on(e: Dictionary) -> int:
	if e.has("it"):
		return (e["it"] as Array).size()
	if e.has("inv"):
		return _inv_total(e["inv"])
	return 0
