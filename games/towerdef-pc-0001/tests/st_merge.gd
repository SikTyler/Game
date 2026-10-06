extends RefCounted
## P7a selftest stage: XP drafts and merge tiers. Every level-up opens a
## draft and every 5th a gold perk; duplicates merge (two same-id same-tier
## buildings -> tier + 1, x1.8 each, T3 cap) with a mod pick at T2 (3 mods)
## and T3 (2 capstones); mods stack and change the building the way their
## text says; MergeDB covers every run building with known fx keys.
## `t` is the selftest runner (t._check).

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const PickDB := preload("res://data/PickDB.gd")
const MergeDB := preload("res://data/MergeDB.gd")
const Draft := preload("res://Draft.gd")


static func run(t) -> void:
	_xp(t)
	_rules(t)
	_mods(t)
	_content(t)


## A quiet run: every cell open, no waves, no opening draft.
static func _run():
	var S = TowerState.new()
	S.setup(77, BaseMeta.normalize({}))
	for i in TowerState.N:
		S.unlocked[i] = not TowerState.is_core_cell(i)
	S.spawn_hold = true
	S.draft_queue.clear()
	return S


static func _put(S, i: int, id: String, tier: int = 1, mods: Array = []) -> void:
	S.slots[i] = {"id": id, "tier": tier, "rot": 6, "mods": mods}


static func _w(S, kind: String) -> Dictionary:
	for w in S.stats["weapons"]:
		if String(w["kind"]) == kind:
			return w
	return {}


static func _ev(ev: Array, kind: String) -> Array:
	return ev.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == kind)


# ------------------------------------------------------------------ XP
static func _xp(t) -> void:
	var S0 = TowerState.new()
	S0.setup(77, BaseMeta.normalize({}))
	t._check("P7a XP: a run starts with the opening draft queued", S0.draft_queue == [""])
	var S = _run()
	t._check("P7a XP: need = 6 x 1.18^(L-1)", is_equal_approx(S.xp_need(), 6.0) and is_equal_approx(S.xp_base * pow(1.18, 4.0), 6.0 * pow(1.18, 4.0)))
	# a scripted XP feed worth exactly 3 levels queues 3 drafts
	var need3: float = 0.0
	for k in 3:
		need3 += S.xp_base * pow(S.xp_growth, float(k))
	S.xp = need3 + 0.001
	var ev: Array = []
	S._check_level(ev)
	t._check("P7a XP: three levels at once = three drafts queued, three levelup events", S.level == 4 and S.draft_queue.size() == 3 and _ev(ev, "levelup").size() == 3)
	S.draft_queue.clear()
	S.xp = S.xp_need()
	ev = []
	S._check_level(ev)
	t._check("P7a XP: level 5 adds a gold perk offer (every 5th level)", S.level == 5 and S.perk_pending == 1 and bool(_ev(ev, "levelup")[0]["gold"]))
	S.draft_queue.clear()
	S.perk_pending = 0
	for L in range(5, 10):
		S.xp = S.xp_need()
		S._check_level([])
	t._check("P7a XP: levels 6-9 no gold perk, level 10 one", S.level == 10 and S.perk_pending == 1 and S.draft_queue.size() == 5)
	# XP is a build choice: the Refinery's +15% (x tier) speeds the drafts
	var R = _run()
	var base_m: float = float(R.stats["xp_mult"])
	_put(R, TowerState.cell(-4, 0), "refinery", 2)
	R.recompute()
	t._check("P7a XP: a T2 Refinery = +15% x 1.8 XP", is_equal_approx(float(R.stats["xp_mult"]), base_m + 0.15 * 1.8))


# ------------------------------------------------------------------ rules
static func _rules(t) -> void:
	var S = _run()
	var a: int = TowerState.cell(-4, -4)
	var b: int = TowerState.cell(-4, 4)
	var c: int = TowerState.cell(4, -4)
	var d: int = TowerState.cell(4, 4)
	_put(S, a, "gun")
	_put(S, b, "gun")
	_put(S, c, "mortar")
	_put(S, d, "gun", 2)
	S.recompute()
	t._check("P7a merge: targets are same id + same tier only", S.merge_targets(a) == [b] and S.merge_targets(c).is_empty() and S.merge_targets(d).is_empty())
	t._check("P7a merge: a different id / tier / itself is refused", S.merge(a, c).is_empty() and S.merge(a, d).is_empty() and S.merge(a, a).is_empty() and S.tier_at(a) == 1)
	var dmg1: float = float(_w(S, "gun")["dmg"])
	var ev: Array = S.merge(a, b)
	t._check("P7a merge: a -> b: b is T2 on its own cell, a's cell is free", S.tier_at(b) == 2 and S.id_at(a) == "" and S.is_free(a) and _ev(ev, "merged").size() == 1 and int(_ev(ev, "merged")[0]["from"]) == a)
	var dmg2: float = 0.0
	for w in S.stats["weapons"]:
		if int(w["slot"]) == b:
			dmg2 = float(w["dmg"])
	t._check("P7a merge: T2 = x1.8 damage (pattern level 3)", is_equal_approx(dmg2, dmg1 * 1.8) and S.pattern_lvl(b) == 3)
	t._check("P7a merge: the T2 mod pick (3 mods) opens and blocks another merge", int(S.merge_offer["n"]) == 3 and int(S.merge_offer["tier"]) == 2 and _ev(ev, "merge_offer").size() == 1 and S._busy() and S.merge(d, b).is_empty())
	S.choose_mod(0)   # Hollow Points
	t._check("P7a merge: a mod is recorded on the building", S.merge_offer.is_empty() and S.mods_at(b).size() == 1 and String((S.mods_at(b)[0] as Dictionary)["name"]) == "Hollow Points")
	t._check("P7a merge: choose_mod with no offer does nothing", S.choose_mod(0).is_empty())
	# T2 + T2 (with its own mod) -> T3: mods stack, capstones offered
	(S.slots[d] as Dictionary)["mods"] = [[2, 1]]   # Belt Feed
	S.recompute()
	ev = S.merge(d, b)
	t._check("P7a merge: two T2s -> T3 keeps both mods and offers 2 capstones", S.tier_at(b) == 3 and S.mods_at(b).size() == 2 and int(S.merge_offer["n"]) == 2 and int(S.merge_offer["tier"]) == 3)
	S.choose_mod(0)   # Triple Barrel
	var gw: Dictionary = {}
	for w in S.stats["weapons"]:
		if int(w["slot"]) == b:
			gw = w
	t._check("P7a merge: stacked fx land (+30% dmg x +30% rate, +1 round) at x1.8^2", is_equal_approx(float(gw["dmg"]), dmg1 * 3.24 * 1.30) and is_equal_approx(float(gw["rounds_add"]), 1.0) and S.merge_targets(b).is_empty())
	# a duplicate card onto a T1
	var M = _run()
	var m1: int = TowerState.cell(-4, 0)
	_put(M, m1, "mine")
	M.recompute()
	M.pending_place = "mine"
	t._check("P7a merge: a duplicate card targets the T1 twin only", M.card_merge_targets("mine") == [m1] and M.card_merge_targets("gun").is_empty())
	var cash1: float = float(M.stats["cash_ps"])
	ev = M.merge_card(m1)
	t._check("P7a merge: the card makes the Mine a T2 (+0.8 x 0.8 cash/s base)", M.tier_at(m1) == 2 and M.pending_place == "" and is_equal_approx(float(M.stats["cash_ps"]) - cash1, 0.8 * 0.8 * M.cash_index() * M.cash_mult * (1.0 + M.pf("cash"))))
	# huts at the cap merge but never place
	var H = _run()
	_put(H, TowerState.cell(-4, 0), "hut_infantry")
	_put(H, TowerState.cell(4, 0), "hut_sapper")
	_put(H, TowerState.cell(0, 4), "hut_sapper", 2)
	H.recompute()
	var ctx: Dictionary = H._draft_ctx("")
	t._check("P7a merge: at the hut cap a hut card only merges (no new hut)", H.hut_count() == PickDB.HUT_MAX and bool(Draft.card_for("hut_infantry", ctx)["merge"]) and not H.can_place(TowerState.cell(0, -5), "hut_infantry"))
	# determinism: the offer is data, not a roll
	t._check("P7a merge: mod offers are fixed data (same 3 / 2 every time)", MergeDB.offer("gun", 2) == MergeDB.offer("gun", 2) and MergeDB.offer("gun", 2).size() == 3 and MergeDB.offer("gun", 3).size() == 2 and MergeDB.offer("gun", 1).is_empty())


# ------------------------------------------------------------------ mods
static func _mods(t) -> void:
	var S = _run()
	var i: int = TowerState.cell(-4, -4)
	var cases: Array = [
		["mortar", [[2, 0]], "splash_m", 1.40],
		["tesla", [[2, 0]], "chains_add", 4.0],
		["tesla", [[3, 0]], "arcs_add", 2.0],
		["railgun", [[3, 0]], "boss_add", 3.0],
		["flak", [[2, 0]], "cone_m", 1.40],
		["flak", [[2, 1]], "burn_m", 1.60],
		["gun", [[2, 2]], "pierce_add", 4.0],
	]
	var ok: bool = true
	var bad: Array = []
	for cs in cases:
		var c: Array = cs
		S.slots[i] = {}
		_put(S, i, String(c[0]), 3, c[1])
		S.recompute()
		var w: Dictionary = _w(S, String(c[0]))
		if not is_equal_approx(float(w.get(String(c[2]), -1.0)), float(c[3])):
			ok = false
			bad.append("%s %s=%s" % [c[0], c[2], str(w.get(String(c[2]), null))])
	t._check("P7a mods: weapon fx reach the sheet (splash, chains, arcs, boss, cone, burn, pierce)", ok, str(bad))
	S.slots[i] = {}
	_put(S, i, "frost", 2, [[2, 0]])
	S.recompute()
	t._check("P7a mods: Deep Freeze +15% Cryo slow", is_equal_approx(float(_w(S, "frost")["slow"]), 0.45))
	S.slots[i] = {}
	_put(S, i, "gun", 3, [[3, 1]])
	S.recompute()
	t._check("P7a mods: Wide Mount widens the Gatling arc (120 -> 200 deg)", is_equal_approx(float(_w(S, "gun")["arc_cos"]), cos(deg_to_rad(100.0))))
	# support: Oil Mill Muffled stops its neighbours' rate penalty
	var O = _run()
	var g: int = TowerState.cell(-4, 0)
	_put(O, g, "gun")
	_put(O, TowerState.cell(-5, 0), "oilmill")
	O.recompute()
	var slow_rate: float = float(_w(O, "gun")["rate"])
	(O.slots[TowerState.cell(-5, 0)] as Dictionary)["mods"] = [[2, 0]]
	O.recompute()
	t._check("P7a mods: a Muffled Oil Mill no longer slows its neighbour", float(_w(O, "gun")["rate"]) > slow_rate * 1.05)
	# economy: Vault Strongroom doubles its interest cap share
	var V = _run()
	var cap0: float = float(V.stats["interest_cap"])
	_put(V, TowerState.cell(-4, 0), "vault")
	V.recompute()
	var cap1: float = float(V.stats["interest_cap"])
	(V.slots[TowerState.cell(-4, 0)] as Dictionary)["mods"] = [[2, 1]]
	V.recompute()
	t._check("P7a mods: Strongroom = +100% to the Vault's interest cap share", is_equal_approx(float(V.stats["interest_cap"]) - cap0, 2.0 * (cap1 - cap0)))
	# Bulwark Ironclad: +3 armor on top of its HP
	var B = _run()
	var arm0: float = float(B.stats["armor"])
	_put(B, TowerState.cell(-4, 0), "bulwark", 3, [[3, 1]])
	B.recompute()
	t._check("P7a mods: Ironclad = +3 Core armor", is_equal_approx(float(B.stats["armor"]) - arm0, 3.0))
	# Beacon Tall Mast reaches 2 cells further
	var C = _run()
	_put(C, TowerState.cell(-4, 0), "beacon", 2, [[2, 1]])
	_put(C, TowerState.cell(-4, 6), "gun")
	C.recompute()
	var reached: bool = false
	for l in C.stats["links"]:
		if String((l as Array)[2]) == "BEA" and int((l as Array)[1]) == TowerState.cell(-4, 6):
			reached = true
	t._check("P7a mods: Tall Mast reaches a building 5-6 cells away", reached)
	# huts: Marksmen +60% troop damage
	var T = _run()
	_put(T, TowerState.cell(-4, 0), "hut_infantry", 2)
	T.recompute()
	var d0: float = float((T.troops[0] as Dictionary)["dmg"]) if not T.troops.is_empty() else 0.0
	(T.slots[TowerState.cell(-4, 0)] as Dictionary)["mods"] = [[2, 1]]
	T.recompute()
	var d1: float = float((T.troops[0] as Dictionary)["dmg"]) if not T.troops.is_empty() else 0.0
	t._check("P7a mods: Marksmen = troops +60% damage", d0 > 0.0 and is_equal_approx(d1, d0 * 1.6))
	# Wall: tiers widen / deepen the aura, Killing Floor deals damage
	var W = _run()
	var wi: int = TowerState.cell(-4, 0)
	_put(W, wi, "barricade", 3, [[3, 1]])
	W.recompute()
	var e: int = W.add_enemy({"kind": "drone", "pos": W.fp_pos(wi) + Vector2(10, 0), "hp": 500.0, "max_hp": 500.0, "spd": 0.0, "dmg": 0.0, "cash": 0.0, "xp": 0.0, "coin": 0.0, "size": 12.0, "atk_cd": 0.0, "slow_t": 0.0})
	W.stats["weapons"] = []
	for k in 10:
		W.tick(0.1)
	var hp1: float = float(W.enemy_list()[0]["hp"]) if not W.enemy_list().is_empty() else 500.0
	t._check("P7a mods: a Killing Floor Wall damages bodies in its aura", hp1 < 500.0 and e >= 0, str(hp1))


# ------------------------------------------------------------------ content
static func _content(t) -> void:
	var missing: Array = []
	for id in PickDB.BUILDINGS + PickDB.HUTS:
		var off2: Array = MergeDB.offer(String(id), 2)
		var off3: Array = MergeDB.offer(String(id), 3)
		if off2.size() != 3 or off3.size() != 2:
			missing.append(id)
			continue
		for md in off2 + off3:
			var mdd: Dictionary = md
			if String(mdd.get("name", "")) == "" or String(mdd.get("desc", "")) == "" or (mdd.get("fx", {}) as Dictionary).is_empty():
				missing.append("%s:%s" % [id, mdd.get("name", "?")])
			for k in (mdd["fx"] as Dictionary).keys():
				if not MergeDB.FX_KEYS.has(String(k)):
					missing.append("%s:%s:%s" % [id, mdd["name"], k])
	t._check("P7a content: every run building has 3 T2 mods + 2 T3 capstones with known fx keys", missing.is_empty(), str(missing))
	t._check("P7a content: no plus / upgrade card kind remains", not Draft.REWARD.has("plus") and Draft.reward_of("new") == "building")
