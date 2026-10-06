extends RefCounted
## P6 selftest stage: the Outpost V2 rules. The V1 checks (placement,
## connectivity, power, accrual, instant builds, adjacency, decor, plots,
## charm, move / rotate / demolish, blueprints, run hooks, normalize) ported
## to the 48x32 map of small cells (Relay 3x3 at (4,8), Research Hall 3x3 on
## top of it, start area 12x12), plus the V2 rules: Relay unlocks, Core
## buildings -> permanent Core stats in runs, signed adjacency (heat, Pylons,
## rivals, floor / cap), scavengers banking gear, limits; P6c: adjacency
## sources for the connector lines, receivers only, per-building Core share,
## procedural art coverage.
## `t` is the selftest runner.

const Outpost := preload("res://Outpost.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const AdjDB := preload("res://data/AdjDB.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const TowerState := preload("res://TowerState.gd")
const Gear := preload("res://Gear.gd")
const Loot := preload("res://Loot.gd")

const OT0: int = 1767225600


static func run(t) -> void:
	_map(t)
	_place(t)
	_production(t)
	_adjacency(t)
	_land(t)
	_edit(t)
	_core(t)
	_scavengers(t)
	_links(t)


static func _save(coins: int = 10_000_000) -> Dictionary:
	var sv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	sv["coins"] = coins
	return sv


## Place + finish a building now. Returns its uid ("" if refused).
static func _b(sv: Dictionary, id: String, x: int, y: int, rot: int = 0, now: int = OT0) -> String:
	var pe: Array = _ev(Outpost.place(sv, id, x, y, rot, now), "op_placed")
	if pe.is_empty():
		return ""
	Outpost.tick(sv, now)
	return String(pe[0]["uid"])


static func _ev(ev: Array, kind: String) -> Array:
	return ev.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == kind)


static func _lb(sv: Dictionary, uid: String) -> Dictionary:
	return Outpost.layout_bonus(sv["outpost"], uid)


# ------------------------------------------------------------------ map

static func _map(t) -> void:
	var cover: Dictionary = {}
	var dup: int = 0
	for y in OutpostDB.H:
		for x in OutpostDB.W:
			var c := Vector2i(x, y)
			var n: int = 1 if OutpostDB.START.has_point(c) else 0
			for r in OutpostDB.PLOTS:
				n += 1 if (r as Rect2i).has_point(c) else 0
			if n == 1:
				cover[c] = true
			elif n > 1:
				dup += 1
	t._check("P6 map: 48x32 small cells; the start area + 17 plots tile it exactly", OutpostDB.W == 48 and OutpostDB.H == 32 and OutpostDB.PLOTS.size() == 17 and cover.size() == 48 * 32 and dup == 0)
	t._check("P6 map: Relay and Research Hall are 3x3, a start area of 12x12", OutpostDB.size_of("relay", 0) == Vector2i(3, 3) and OutpostDB.size_of("research", 0) == Vector2i(3, 3) and OutpostDB.START.size == Vector2i(12, 12) and OutpostDB.size_of("mill", 0) == Vector2i(2, 2) and OutpostDB.size_of("pylon", 0) == Vector2i(1, 1))
	var sv: Dictionary = _save()
	var o: Dictionary = sv["outpost"]
	t._check("P6 map: a new save has the Relay + a linked Research Hall on top of it", Outpost.level_of(sv, "research") == 1 and Outpost.research_queues(sv) == 1 and bool(Outpost.connected(o).values()[0]))
	var rocks_ok: bool = true
	for v in OutpostDB.VEINS:
		rocks_ok = rocks_ok and not OutpostDB.BLOCKED.has(v)
	t._check("P6 map: 7 rocks of 2x2, veins never under a rock, one vein in the start area", OutpostDB.BLOCKED.size() == 28 and rocks_ok and OutpostDB.START.has_point(OutpostDB.VEINS[0]))
	var cats_ok: bool = true
	for id in OutpostDB.IDS:
		var d: Dictionary = OutpostDB.DEFS[id]
		cats_ok = cats_ok and OutpostDB.CATS.has(String(d.get("cat", ""))) and d.has("desc") and d.has("coins")
	t._check("P6 data: every building has a category, price and description", cats_ok and OutpostDB.CORE_IDS.size() == 10 and OutpostDB.SCAVENGERS.size() == 3)


# ------------------------------------------------------------------ place

static func _place(t) -> void:
	var sv: Dictionary = _save()
	t._check("AC-17 refuse: occupied (Relay), locked plot, rock, outside", Outpost.place_error(sv, "mill", 4, 8, 0) == "occupied" and Outpost.place_error(sv, "mill", 13, 5, 0) == "locked" and Outpost.place_error(sv, "mill", 26, 18, 0) != "" and Outpost.place_error(sv, "conduit", -1, 5, 0) == "outside")
	t._check("AC-17 Deep Mine only on a Crystal Vein", Outpost.place_error(sv, "gemmine", 8, 12, 0) == "needs_vein" and Outpost.place_error(sv, "gemmine", 1, 13, 0) == "")
	var c0: int = int(sv["coins"])
	var m1: String = _b(sv, "mill", 7, 8)
	t._check("OP place Mill: pays 500, built at once", m1 != "" and int(sv["coins"]) == c0 - 500 and bool(sv["outpost"]["buildings"][m1]["built"]))
	t._check("AC-17 quantity limit (Relay 1: 2 Mills)", _b(sv, "mill", 7, 10) != "" and Outpost.place_error(sv, "mill", 9, 8, 0) == "limit")
	t._check("P6 unlocks: an Optics Lab needs Relay 2", Outpost.place_error(sv, "optics", 9, 12, 0) == "relay")
	sv["outpost"]["relay_lvl"] = 2
	t._check("P6 unlocks: ... and places at Relay 2", Outpost.place_error(sv, "optics", 9, 12, 0) == "")
	# connectivity: an island Mill produces 0 until a Conduit links it
	var cs: Dictionary = _save()
	var isl: String = _b(cs, "mill", 1, 9)
	t._check("AC-17 unconnected generator produces 0", not bool(Outpost.connected(cs["outpost"])[isl]) and is_equal_approx(Outpost.rate(cs, isl), 0.0) and Outpost.nominal_rate(cs, isl) > 0.0)
	_b(cs, "conduit", 3, 9)
	t._check("AC-17 a Conduit next to the Relay links it", bool(Outpost.connected(cs["outpost"])[isl]) and is_equal_approx(Outpost.rate(cs, isl), OutpostDB.MILL_RATE))
	# power over budget scales efficiency
	var ps: Dictionary = _save()
	ps["outpost"]["relay_lvl"] = 1
	for p in [["mill", 7, 8], ["mill", 7, 10], ["refinery", 9, 8], ["barracks", 9, 10], ["archive", 7, 12], ["warehouse", 9, 12]]:
		_b(ps, String(p[0]), int(p[1]), int(p[2]))
	var dm: float = Outpost.demand(ps["outpost"])
	t._check("AC-17 over-budget power scales generator efficiency", dm > Outpost.supply(ps["outpost"]) and is_equal_approx(Outpost.efficiency(ps["outpost"]), Outpost.supply(ps["outpost"]) / dm))


# ------------------------------------------------------------------ production

static func _production(t) -> void:
	var a: Dictionary = _save()
	var mu: String = _b(a, "mill", 7, 8)
	Outpost.tick(a, OT0 + 3600)
	t._check("AC-18 accrual = rate x elapsed", absf(float(a["outpost"]["buildings"][mu]["stored"]) - OutpostDB.MILL_RATE) < 0.01)
	Outpost.tick(a, OT0 + 3600 * 30)
	t._check("AC-18 accrual clamps at the 8 h storage cap", is_equal_approx(float(a["outpost"]["buildings"][mu]["stored"]), 8.0 * OutpostDB.MILL_RATE) and is_equal_approx(Outpost.cap(a, mu), 8.0 * OutpostDB.MILL_RATE))
	var c0: int = int(a["coins"])
	var cev: Array = Outpost.collect(a, mu, OT0 + 3600 * 30)
	t._check("AC-18 collect pays whole coins and empties storage", _ev(cev, "collect").size() == 1 and int(a["coins"]) == c0 + int(8.0 * OutpostDB.MILL_RATE) and float(a["outpost"]["buildings"][mu]["stored"]) < 1.0)
	var pv: Dictionary = Outpost.pending(a, OT0 + 3600 * 32)
	t._check("OP pending previews without mutating", absf(float(pv["coins"]) - 2.0 * OutpostDB.MILL_RATE) < 0.01 and float(a["outpost"]["buildings"][mu]["stored"]) < 1.0)
	var nb: Dictionary = _save()
	var nu: String = _b(nb, "mill", 7, 8)
	nb["outpost"]["buildings"][nu]["last_tick"] = 0
	Outpost.tick(nb, OT0 + 86400)
	t._check("OP last_tick 0 = start the clock (no back pay)", is_equal_approx(float(nb["outpost"]["buildings"][nu]["stored"]), 0.0))
	var tu: String = _b(nb, "mill", 7, 10)
	var nr1: float = Outpost.nominal_rate(nb, tu)
	var uc: int = Outpost.cost("mill", 1)
	var c1: int = int(nb["coins"])
	var uev: Array = Outpost.upgrade(nb, tu, OT0 + 3720)
	t._check("OP upgrade cost x1.6^(L-1), instant, L2 = +25%", _ev(uev, "upgrade_done").size() == 1 and int(nb["coins"]) == c1 - uc and Outpost.cost("mill", 3) == int(round(500.0 * 2.56)) and is_equal_approx(Outpost.nominal_rate(nb, tu), 1.25 * nr1))
	t._check("OP max level = min(10, Relay L + 2)", Outpost.max_lvl(nb, "mill") == 3)
	# Deep Mine on the start vein, linked by Conduits; lit Lamps (decor cap)
	var gm: Dictionary = _save()
	var gu: String = _b(gm, "gemmine", 1, 13)
	for c in [Vector2i(3, 10), Vector2i(3, 11), Vector2i(3, 12), Vector2i(3, 13)]:
		_b(gm, "conduit", c.x, c.y)
	t._check("OP Deep Mine: 3x Mill rate in coins once linked", bool(Outpost.connected(gm["outpost"])[gu]) and is_equal_approx(Outpost.nominal_rate(gm, gu), 3.0 * OutpostDB.MILL_RATE * Outpost.global_mult(gm)))
	for lp in [Vector2i(0, 13), Vector2i(0, 14), Vector2i(1, 12), Vector2i(2, 12)]:
		Outpost.place_decor(gm, "dc_lamp", lp.x, lp.y, 0)
	t._check("AC-19 decor stack capped at +20% (4 lit Lamps on a Deep Mine)", is_equal_approx(float(_lb(gm, gu)["total"]), 0.20))


# ------------------------------------------------------------------ adjacency

static func _adjacency(t) -> void:
	var j: Dictionary = _save()
	j["outpost"]["relay_lvl"] = 8
	var ma: String = _b(j, "mill", 7, 9)
	_b(j, "mill", 7, 11)
	t._check("AC-19 +10% per touching Mill", is_equal_approx(float(_lb(j, ma)["parts"]["mills"]), 0.10))
	_b(j, "mill", 7, 7)
	_b(j, "mill", 9, 8)
	_b(j, "warehouse", 9, 10)
	_b(j, "beaconpost", 9, 12)
	var lb: Dictionary = _lb(j, ma)
	t._check("AC-19 Mills max +30%, +15% Warehouse, +5% Beacon (layout +50%)", is_equal_approx(float(lb["parts"]["mills"]), 0.30) and is_equal_approx(float(lb["parts"]["warehouse"]), 0.15) and is_equal_approx(float(lb["parts"]["beacon"]), 0.05) and is_equal_approx(float(lb["total"]), 0.50), str(lb))
	t._check("AC-19 Warehouse +10% storage within 2 cells", is_equal_approx(Outpost.warehouse_bonus(j["outpost"], ma), 0.10))
	var r: Dictionary = _save()
	r["outpost"]["relay_lvl"] = 8
	var rf: String = _b(r, "refinery", 7, 8)
	_b(r, "mill", 7, 10)
	t._check("AC-19 Refinery -10% next to a Mill (noise)", is_equal_approx(float(_lb(r, rf)["total"]), -0.10))
	Outpost.place_decor(r, "dc_smelter", 9, 8, 0)
	t._check("AC-19 Refinery +20% next to a Smelter", is_equal_approx(float(_lb(r, rf)["total"]), 0.10))
	# V2 signed rules
	var h: Dictionary = _save()
	h["outpost"]["relay_lvl"] = 8
	var hm: String = _b(h, "mill", 7, 8)
	var hr: String = _b(h, "reactor", 9, 8)
	var ha: String = _b(h, "arsenal", 9, 10)
	t._check("P6 adjacency: a Reactor heats a touching Mill (-15%) and powers a touching Arsenal (+20%)", is_equal_approx(float(_lb(h, hm)["parts"].get("heat", 0.0)), -0.15) and is_equal_approx(float(_lb(h, ha)["parts"].get("reactor", 0.0)), 0.20) and hr != "")
	var py: Dictionary = _save()
	py["outpost"]["relay_lvl"] = 8
	var pa: String = _b(py, "arsenal", 7, 8)
	var pb: String = _b(py, "treasury", 7, 10)
	_b(py, "pylon", 9, 9)
	_b(py, "conduit", 9, 10)
	_b(py, "conduit", 9, 11)
	var pc: String = _b(py, "bulwark_w", 10, 11)
	var near: Dictionary = _lb(py, pa)
	t._check("P6 adjacency: a Pylon is -5% to what touches it, +5% at 2 cells", is_equal_approx(float(near["parts"].get("pylon_hum", 0.0)), -0.05) and not near["parts"].has("pylon") and is_equal_approx(float(_lb(py, pc)["parts"].get("pylon", 0.0)), 0.05) and not _lb(py, pc)["parts"].has("pylon_hum") and pb != "", "%s %s" % [near, _lb(py, pc)])
	var sc: Dictionary = _save()
	sc["outpost"]["relay_lvl"] = 8
	var s1: String = _b(sc, "scav_post", 7, 8)
	var s2: String = _b(sc, "scav_den", 7, 10)
	t._check("P6 adjacency: scavengers within 2 cells compete (-15% each way)", is_equal_approx(float(_lb(sc, s1)["parts"].get("rivals", 0.0)), -0.15) and is_equal_approx(float(_lb(sc, s2)["parts"].get("rivals", 0.0)), -0.15))
	var fl: Dictionary = _save()
	fl["outpost"]["relay_lvl"] = 8
	var fm: String = _b(fl, "refinery", 7, 9)
	_b(fl, "mill", 7, 7)
	_b(fl, "reactor", 9, 9)
	_b(fl, "pylon", 7, 11)
	t._check("P6 adjacency: rules list both directions for a building (palette)", AdjDB.rules_for("reactor").size() >= 2 and AdjDB.rules_for("mill").size() >= 4)
	t._check("P6 adjacency: the total never drops below -40% or rises above +60%", float(_lb(fl, fm)["total"]) >= AdjDB.NERF_FLOOR and AdjDB.BUFF_CAP == 0.60 and AdjDB.NERF_FLOOR == -0.40)
	var unl: Dictionary = _save()
	unl["outpost"]["relay_lvl"] = 8
	var um: String = _b(unl, "mill", 7, 8)
	var ub: String = _b(unl, "beaconpost", 9, 11)
	var before: bool = _lb(unl, um)["parts"].has("beacon")
	_b(unl, "conduit", 9, 9)
	_b(unl, "conduit", 9, 10)
	t._check("P6 adjacency: an unlinked source gives nothing until a Conduit links it", ub != "" and not before and is_equal_approx(float(_lb(unl, um)["parts"].get("beacon", 0.0)), 0.05))


# ------------------------------------------------------------------ plots, decor

static func _land(t) -> void:
	var p: Dictionary = _save(100_000_000)
	t._check("OP plot 0 costs 5,000; a non-adjacent plot is refused", int(Outpost.plot_cost(p)["coins"]) == 5000 and Outpost.unlock_plot(p, 5).is_empty())
	Outpost.unlock_plot(p, 0)
	t._check("OP plot n = 5,000 x 2.2^n; plot 5 adjacent after plot 0", int(Outpost.plot_cost(p)["coins"]) == 11000 and not Outpost.unlock_plot(p, 5).is_empty())
	var d: Dictionary = _save()
	d["outpost"]["plots"] = [0, 1, 2, 3, 4, 5, 6, 7]
	var n: int = 0
	for y in range(0, 20):
		for x in range(12, 28):
			if n < 20 and not Outpost.place_decor(d, "dc_tree", x, y, 0).is_empty():
				n += 1
	t._check("OP Charm +1% per 10 decor (max +10%)", n == 20 and is_equal_approx(Outpost.charm(d["outpost"]), 0.02))
	var dk: String = String(d["outpost"]["decor"].keys()[0])
	var c2: int = int(d["coins"])
	Outpost.remove_decor(d, dk)
	t._check("OP remove decor refunds 50%", int(d["coins"]) == c2 + 25)


# ------------------------------------------------------------------ edit

static func _edit(t) -> void:
	var mv: Dictionary = _save()
	var ku: String = _b(mv, "mill", 7, 8)
	t._check("OP move is free + validated", not Outpost.move(mv, ku, 7, 11, 0, OT0).is_empty() and int(mv["outpost"]["buildings"][ku]["y"]) == 11 and Outpost.move(mv, ku, 4, 8, 0, OT0).is_empty())
	var ws: String = _b(mv, "scrapyard", 0, 12)
	t._check("OP rotate swaps the footprint", not Outpost.move(mv, ws, 0, 12, 1, OT0).is_empty() and (Outpost.footprint("scrapyard", 0, 12, 1)[1] as Vector2i) == Vector2i(0, 13))
	var c3: int = int(mv["coins"])
	Outpost.demolish(mv, ku, OT0)
	t._check("OP demolish refunds 50%", int(mv["coins"]) == c3 + 250)
	var bp: Dictionary = _save()
	var bu: String = _b(bp, "mill", 7, 8)
	Outpost.save_blueprint(bp, "Mint Ring")
	var code: String = Outpost.export_layout(bp["outpost"])
	Outpost.move(bp, bu, 7, 11, 0, OT0)
	var lr: Dictionary = Outpost.load_blueprint(bp, Outpost.import_layout(code), OT0)
	t._check("OP blueprint export / import + rebuild moves owned buildings back", int(bp["outpost"]["buildings"][bu]["y"]) == 8 and (lr["missing"] as Array).is_empty())
	t._check("OP blueprint reports buildings you do not own", (Outpost.load_blueprint(bp, [{"id": "archive", "x": 9, "y": 8, "rot": 0}], OT0)["missing"] as Array) == ["archive"])
	var rh: Dictionary = _save()
	var bk: String = _b(rh, "barracks", 7, 8)
	var ar: String = _b(rh, "archive", 7, 10)
	rh["outpost"]["buildings"][bk]["lvl"] = 4
	rh["outpost"]["buildings"][ar]["lvl"] = 9
	var rm: Dictionary = BaseMeta.run_mods(rh)
	t._check("OP run hooks: Barracks tier = level, Archive L9 cap +2 / +1 banish", int(rm["barracks_tier"]) == 4 and int(rm["insight_cap"]) == 2 and int(rm["banish"]) == 1)
	var nz: Dictionary = _save()
	_b(nz, "mill", 7, 8)
	nz["outpost"]["buildings"]["99"] = {"id": "mill", "x": 7, "y": 8, "rot": 0, "lvl": 1}
	nz["outpost"]["buildings"]["98"] = {"id": "bogus", "x": 0, "y": 0}
	var nn: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(nz)))
	t._check("OP normalize: unknown dropped, overlap lifted to unplaced", not (nn["outpost"]["buildings"] as Dictionary).has("98") and int(nn["outpost"]["buildings"]["99"]["x"]) == -1 and int(nn["outpost"]["next_uid"]) >= 100)


# ------------------------------------------------------------------ Core buildings

static func _core(t) -> void:
	var sv: Dictionary = _save()
	sv["outpost"]["relay_lvl"] = 8
	var ar: String = _b(sv, "arsenal", 7, 8)
	sv["outpost"]["buildings"][ar]["lvl"] = 3
	t._check("P6 core: a linked Arsenal L3 = +6% all damage", is_equal_approx(float(Outpost.core_bonus(sv).get("dmg", 0.0)), 0.06))
	_b(sv, "reactor", 9, 8)
	t._check("P6 core: a touching Reactor scales it +20% (and adds +1.5% rate)", is_equal_approx(float(Outpost.core_bonus(sv)["dmg"]), 0.072) and is_equal_approx(float(Outpost.core_bonus(sv)["rate"]), 0.015))
	var rm: Dictionary = BaseMeta.run_mods(sv)
	t._check("P6 core: the bonus rides BaseMeta.run_mods into the run", is_equal_approx(float((rm["outpost_fx"] as Dictionary)["dmg"]), 0.072))
	var S = TowerState.new()
	S.setup(1, sv)
	var base = TowerState.new()
	base.setup(1, _save())
	t._check("P6 core: ... and the run's Core damage / rate use it", is_equal_approx(float((S.stats["weapons"] as Array).back()["dmg"]), float((base.stats["weapons"] as Array).back()["dmg"]) * 1.072) and is_equal_approx(float((S.stats["weapons"] as Array).back()["rate"]), float((base.stats["weapons"] as Array).back()["rate"]) * 1.015))
	var un: Dictionary = _save()
	un["outpost"]["relay_lvl"] = 8
	_b(un, "arsenal", 1, 9)
	t._check("P6 core: an unlinked Core building gives nothing", Outpost.core_bonus(un).is_empty())
	var fw: Dictionary = _save()
	fw["outpost"]["relay_lvl"] = 8
	var fu: String = _b(fw, "forgeworks", 7, 8)
	fw["outpost"]["buildings"][fu]["lvl"] = 5
	t._check("P6 core: Forge Works L5 = -10% Forge costs", int(Gear.forge_cost(fw)["coins"]) == int(round(1500.0 * 0.9)))
	var sh: Dictionary = _save()
	sh["outpost"]["relay_lvl"] = 8
	var su: String = _b(sh, "shrine", 7, 8)
	sh["outpost"]["buildings"][su]["lvl"] = 4
	t._check("P6 core: Fortune Shrine L4 = +4 loot luck when a run banks", is_equal_approx(Loot.luck_of(sh, {"luck": 1}), 5.0))
	var lim: Dictionary = _save()
	lim["outpost"]["relay_lvl"] = 1
	_b(lim, "arsenal", 7, 8)
	var e1: String = Outpost.place_error(lim, "arsenal", 7, 10, 0)
	lim["outpost"]["relay_lvl"] = 6
	t._check("P6 core: one of each at first, two from Relay 6", e1 == "limit" and Outpost.place_error(lim, "arsenal", 7, 10, 0) == "")
	var pw: Dictionary = _save()
	pw["outpost"]["relay_lvl"] = 1
	var pa: String = _b(pw, "arsenal", 7, 8)
	var full: float = float(Outpost.core_bonus(pw)["dmg"])
	for p in [["mill", 7, 10], ["mill", 9, 10], ["refinery", 9, 8], ["barracks", 7, 12], ["treasury", 9, 12]]:
		_b(pw, String(p[0]), int(p[1]), int(p[2]))
	t._check("P6 core: over-budget power scales Core buildings too", pa != "" and Outpost.efficiency(pw["outpost"]) < 1.0 and float(Outpost.core_bonus(pw)["dmg"]) < full)


# ------------------------------------------------------------------ scavengers

static func _scavengers(t) -> void:
	var sv: Dictionary = _save()
	sv["outpost"]["relay_lvl"] = 4
	sv["best_wave"] = 50
	var su: String = _b(sv, "scav_post", 7, 8)
	Outpost.tick(sv, OT0 + 6 * 3600)
	t._check("P6 scavenge: a Scavenger Post finds an item every 6 h", absf(float(sv["outpost"]["buildings"][su]["stored"]) - 1.0) < 0.01)
	Outpost.tick(sv, OT0 + 72 * 3600)
	t._check("P6 scavenge: ... storing up to 4", is_equal_approx(float(sv["outpost"]["buildings"][su]["stored"]), 4.0) and is_equal_approx(Outpost.cap(sv, su), 4.0))
	var n0: int = Gear.count(sv)
	var ev: Array = Outpost.collect(sv, su, OT0 + 72 * 3600)
	t._check("P6 scavenge: collecting banks 4 items like run loot (NEW, at 60% of the best wave)", Gear.count(sv) == n0 + 4 and _ev(ev, "loot_item").size() == 4 and _ev(ev, "collect").size() == 1 and Outpost.scav_ilvl(sv) == 30)
	var dn: String = _b(sv, "scav_den", 12 - 3, 8)
	sv["outpost"]["buildings"][dn]["stored"] = 1.0
	sv["outpost"]["buildings"][dn]["last_tick"] = OT0 + 72 * 3600
	var ev2: Array = Outpost.collect(sv, dn, OT0 + 72 * 3600)
	t._check("P6 scavenge: a Scavenger Den's find is a Field Cache (2 items)", _ev(ev2, "cache_open").size() == 1 and _ev(ev2, "loot_item").size() == 2)
	t._check("P6 scavenge: scavengers don't count as coin / Scrap production", not Outpost.production(sv).has("item") and Outpost.pending(sv, OT0 + 80 * 3600).has("coins"))


# ------------------------------------------------------------------ P6c links

static func _links(t) -> void:
	var OV = load("res://ui/OutpostView.gd")
	var OA = load("res://ui/OutpostArt.gd")
	var h: Dictionary = _save()
	h["outpost"]["relay_lvl"] = 8
	var hm: String = _b(h, "mill", 7, 8)
	var hr: String = _b(h, "reactor", 9, 8)
	var ha: String = _b(h, "arsenal", 9, 10)
	var la: Dictionary = _lb(h, ha)
	t._check("P6c links: layout_bonus names each part's sources (Reactor -> Arsenal, Reactor -> Mill)", la["srcs"].get("reactor", []) == [hr] and _lb(h, hm)["srcs"].get("heat", []) == [hr], str(la))
	t._check("P6c links: a once-only part credits its source in full", is_equal_approx(float(OV._ins(la).get(hr, 0.0)), 0.20) and is_equal_approx(float(OV._ins(_lb(h, hm)).get(hr, 0.0)), -0.15))
	t._check("P6c links: core_part is one building's share of core_bonus", is_equal_approx(float(Outpost.core_part(h["outpost"], ha).get("dmg", 0.0)), float(Outpost.core_bonus(h)["dmg"])) and is_equal_approx(float(Outpost.core_part(h["outpost"], ha)["dmg"]), 0.024))
	var j: Dictionary = _save()
	j["outpost"]["relay_lvl"] = 8
	var ma: String = _b(j, "mill", 7, 9)
	var mb: String = _b(j, "mill", 7, 11)
	var mc: String = _b(j, "mill", 9, 9)
	var ins: Dictionary = OV._ins(_lb(j, ma))
	t._check("P6c links: a stacking part splits over its sources (two Mills, +10% each)", ins.size() == 2 and is_equal_approx(float(ins.get(mb, 0.0)), 0.10) and is_equal_approx(float(ins.get(mc, 0.0)), 0.10), str(ins))
	var w: Dictionary = _save()
	w["outpost"]["relay_lvl"] = 8
	var wu: String = _b(w, "warehouse", 7, 8)
	var wm: String = _b(w, "mill", 7, 10)
	_b(w, "beaconpost", 9, 9)
	t._check("P6c links: Beacons / Pylons reach only buildings a layout bonus scales (a Mill, not a Warehouse)", not AdjDB.receives("warehouse") and AdjDB.receives("arsenal") and (_lb(w, wu)["parts"] as Dictionary).is_empty() and is_equal_approx(float(_lb(w, wm)["parts"].get("beacon", 0.0)), 0.05))
	var d: Dictionary = _save()
	d["outpost"]["relay_lvl"] = 8
	_b(d, "barracks", 7, 8)
	_b(d, "training", 9, 8)
	t._check("P6c links: Training Grounds drill a touching Barracks (+10% troops in runs)", is_equal_approx(float(BaseMeta.run_mods(d)["barracks_bonus"]), 0.10))
	var miss: Array = []
	for id in OutpostDB.IDS:
		if id == "conduit":
			continue
		if not OA.has_art(id) or not OA.CAT_COL.has(String(OutpostDB.get_def(id)["cat"])):
			miss.append(id)
	for id in AdjDB.RECEIVERS:
		if not OutpostDB.IDS.has(id):
			miss.append("recv:" + String(id))
	t._check("P6c art: every building has a neon glyph + category rim (and every receiver exists)", miss.is_empty() and OA.has_art("relay"), str(miss))
