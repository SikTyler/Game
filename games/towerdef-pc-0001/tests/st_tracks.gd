extends RefCounted
## P7b selftest stage: Core Enhancements. TrackDB's three trees (Attack /
## Defense / Economy, ~10 standard tracks each + the five Overdrives): cheap
## standard costs, caps, every standard step lands in the run's fx, spot
## checks on the real stats, buy x5 / MAX, Lucky Purchase determinism,
## draft / loot luck, coin bonus, interest cap.
## `t` is the selftest runner (t._check).

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const TrackDB := preload("res://data/TrackDB.gd")


static func run(t) -> void:
	_data(t)
	_costs(t)
	_fx(t)
	_buying(t)


static func _run():
	var S = TowerState.new()
	S.setup(55, BaseMeta.normalize({}))
	S.spawn_hold = true
	S.draft_queue.clear()
	return S


static func _core(S) -> Dictionary:
	return (S.stats["weapons"] as Array).back()


static func _data(t) -> void:
	var bad: Array = []
	for id in TrackDB.IDS:
		var d: Dictionary = TrackDB.get_def(String(id))
		if String(d.get("name", "")) == "" or String(d.get("desc", "")) == "" or not ["attack", "defense", "economy"].has(String(d.get("tree", ""))):
			bad.append(id)
		if not TrackDB.is_od(String(id)) and (d.get("step", {}) as Dictionary).is_empty():
			bad.append(String(id) + ":step")
	t._check("P7b tracks: every track has a tree, name, text; standard tracks a step", bad.is_empty(), str(bad))
	var na: int = TrackDB.tree_ids("attack").filter(func(i: Variant) -> bool: return not TrackDB.is_od(String(i))).size()
	var nd: int = TrackDB.tree_ids("defense").filter(func(i: Variant) -> bool: return not TrackDB.is_od(String(i))).size()
	var ne: int = TrackDB.tree_ids("economy").filter(func(i: Variant) -> bool: return not TrackDB.is_od(String(i))).size()
	t._check("P7b tracks: ~10 standard tracks per tree (11 / 10 / 10) + 5 Overdrives", na == 11 and nd == 10 and ne == 10 and TrackDB.OVERDRIVE.size() == 5 and TrackDB.IDS.size() == 36)
	var names: Dictionary = {}
	for id in TrackDB.IDS:
		names[String(TrackDB.get_def(String(id))["name"])] = true
	t._check("P7b tracks: names are unique (the panel's button keys)", names.size() == TrackDB.IDS.size())


static func _costs(t) -> void:
	var S = _run()
	t._check("P7b tracks: Damage costs 40, then x1.40 per level", S.track_cost("a_dmg") == 40)
	S.cash = 1.0e9
	S.buy_track("a_dmg")
	S.buy_track("a_dmg")
	t._check("P7b tracks: ... 40 x 1.4^2 at level 2", S.track_cost("a_dmg") == int(round(40.0 * 1.96)))
	var cheap: bool = true
	for id in TrackDB.IDS:
		var d: Dictionary = TrackDB.get_def(String(id))
		if TrackDB.is_od(String(id)):
			continue
		cheap = cheap and float(d["base"]) <= 400.0 and float(d["growth"]) <= 3.0 and int(d["cap"]) >= 1 and int(d["cap"]) <= 25
	t._check("P7b tracks: standard tracks are cheap small steps (base <= 400, cap <= 25)", cheap and S.track_cost("a_hp") == -1)
	S.tracks["a_multi"] = TowerState.track_cap("a_multi")
	t._check("P7b tracks: a capped track costs -1 and refuses", S.track_cost("a_multi") == -1 and S.buy_track("a_multi").is_empty())


static func _fx(t) -> void:
	# every standard step lands in pf (one level each, on a fresh run)
	var bad: Array = []
	for id in TrackDB.IDS:
		if TrackDB.is_od(String(id)):
			continue
		var S = _run()
		S.cash = 1.0e9
		S.buy_track(String(id))
		var st: Dictionary = TrackDB.get_def(String(id))["step"]
		for k in st.keys():
			if not is_equal_approx(S.tf(String(k)), float(st[k])) or not is_equal_approx(S.pf(String(k)) - float(S.pfx.get(k, 0.0)), float(st[k])):
				bad.append("%s:%s" % [id, k])
	t._check("P7b tracks: every standard step lands in the run fx (tf / pf)", bad.is_empty(), str(bad))
	var A = _run()
	var B = _run()
	B.cash = 1.0e9
	for id in ["a_dmg", "d_hp", "d_dr", "a_multi", "e_kill", "e_icap", "a_crit", "a_critd"]:
		B.buy_track(String(id))
	t._check("P7b tracks: Damage +4% on the Weapon", is_equal_approx(float(_core(B)["dmg"]), float(_core(A)["dmg"]) * 1.04))
	t._check("P7b tracks: Max HP +5%, Damage Reduction 1%", is_equal_approx(float(B.stats["max_hp"]), float(A.stats["max_hp"]) * 1.05) and is_equal_approx(float(B.stats["dr"]), float(A.stats["dr"]) + 0.01))
	t._check("P7b tracks: Multishot +1 target, crit +1.5% / +10% crit damage", int(_core(B)["multishot"]) == int(_core(A).get("multishot", 0)) + 1 and is_equal_approx(float(B.stats["crit"]), float(A.stats["crit"]) + 0.015) and is_equal_approx(B.crit_mult(), A.crit_mult() + 0.10))
	t._check("P7b tracks: Kill Cash +5%, Interest Cap +15%", is_equal_approx(float(B.stats["kill_cash"]), float(A.stats["kill_cash"]) * 1.05) and is_equal_approx(float(B.stats["interest_cap"]), float(A.stats["interest_cap"]) * 1.15))
	var C = _run()
	C.cash = 1.0e9
	var l0: int = C.luck_now()
	var cm: float = C.run_coin_mult()
	C.buy_track("e_draft")
	C.buy_track("e_coin")
	t._check("P7b tracks: Draft Luck +1 (in the draft ctx), Coin Bonus +3%", C.luck_now() == l0 + 1 and int(C._draft_ctx("")["luck"]) == l0 + 1 and is_equal_approx(C.run_coin_mult(), cm * 1.03))
	C.buy_track("e_loot")
	C.hp = -1.0
	C.tick(0.05)
	t._check("P7b tracks: Loot Luck +1 rides the banked loot", C.over and int(C.loot["luck"]) == C.luck + 1)
	# Overdrives still carry their trade-offs (and nothing in tf)
	var O = _run()
	O.cash = 1.0e9
	O.buy_track("dmg")
	t._check("P7b tracks: an Overdrive keeps its trade-off and adds no tf", O.tfx.is_empty() and is_equal_approx(float(_core(O)["dmg"]), float(_core(A)["dmg"]) * 1.40))


static func _buying(t) -> void:
	var S = _run()
	S.cash = 40.0 + 56.0 + 78.4 + 109.76 + 153.66 + 1.0
	var ev: Array = S.buy_tracks("a_dmg", 5)
	t._check("P7b tracks: buy x5 buys five levels when the cash covers them", int(S.tracks["a_dmg"]) == 5 and ev.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == "track").size() == 5)
	S.cash = 1.0e12
	S.buy_tracks("d_last", 999)
	t._check("P7b tracks: MAX stops at the cap", int(S.tracks["d_last"]) == TowerState.track_cap("d_last"))
	S.cash = 0.0
	t._check("P7b tracks: buy x5 with no cash buys nothing", S.buy_tracks("a_rate", 5).is_empty() and int(S.tracks["a_rate"]) == 0)
	# Lucky Purchase: seeded (draft stream), a free level costs 0
	var L1 = _run()
	var L2 = _run()
	var frees: Array = []
	for L in [L1, L2]:
		L.cash = 1.0e9
		L.tracks["e_free"] = 10
		L.tfx = TrackDB.fx_of(L.tracks)
		var n: int = 0
		for k in 60:
			var e1: Array = L.buy_track("a_dmg" if k < 25 else ("d_hp" if k < 50 else "e_kill"))
			if not e1.is_empty() and bool((e1[0] as Dictionary)["free"]):
				n += 1
		frees.append(n)
	t._check("P7b tracks: Lucky Purchase (30%) refunds some buys, the same ones for the same seed", int(frees[0]) > 3 and int(frees[0]) < 30 and frees[0] == frees[1], str(frees))
	var N = _run()
	N.cash = 1.0e9
	var c0: float = N.cash
	var e2: Array = N.buy_track("a_dmg")
	t._check("P7b tracks: without Lucky Purchase every buy is paid", not bool((e2[0] as Dictionary)["free"]) and is_equal_approx(c0 - N.cash, 40.0))
