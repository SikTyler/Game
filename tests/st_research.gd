extends RefCounted
## P8 selftest stage: the research tree. LabDB data (categories, Hall rows,
## prerequisites, fx vocabulary), the steep key costs, Lab Discount, Hall and
## prerequisite gating, and a table-driven pass that sets each project's
## level and checks the stat it promises moves (run fx, enemy cuts, drafts,
## Outpost licences, Forge discounts, loot, Enhancement Theory unlocks).
## `t` is the selftest runner (t._check).

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Labs := preload("res://Labs.gd")
const LabDB := preload("res://data/LabDB.gd")
const TrackDB := preload("res://data/TrackDB.gd")
const Outpost := preload("res://Outpost.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const Parts := preload("res://Parts.gd")
const Drops := preload("res://Drops.gd")
const Loot := preload("res://Loot.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const RunArt := preload("res://ui/RunArt.gd")

const OT0: int = 1767225600
## Run fx keys TowerState reads through pf() (research fx must be among them).
const PF_KEYS: Array = ["range", "crit", "rate", "dr", "shield", "boss", "interest", "run_cash"]


static func run(t) -> void:
	_data(t)
	_costs(t)
	_gating(t)
	_run_effects(t)
	_meta_effects(t)
	_qol(t)


static func _save(coins: int = 100_000_000) -> Dictionary:
	var sv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	sv["coins"] = coins
	return sv


static func _lv(sv: Dictionary, id: String, lv: int) -> void:
	(sv["research"]["lvls"] as Dictionary)[id] = lv


static func _hall(sv: Dictionary, lvl: int) -> void:
	var bl: Dictionary = sv["outpost"]["buildings"]
	for k in bl.keys():
		if String((bl[k] as Dictionary)["id"]) == "research":
			(bl[k] as Dictionary)["lvl"] = lvl


static func _run(sv: Dictionary, seed_value: int = 77):
	var S = TowerState.new()
	S.setup(seed_value, sv)
	return S


static func _ev(ev: Array, kind: String) -> Array:
	return ev.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == kind)


# ------------------------------------------------------------------ data
static func _data(t) -> void:
	var cats: Dictionary = {}
	var bad: Array = []
	for id in LabDB.IDS:
		var d: Dictionary = LabDB.get_def(String(id))
		cats[String(d.get("cat", ""))] = int(cats.get(String(d.get("cat", "")), 0)) + 1
		for k in ["name", "cat", "max", "effect", "icon", "hall"]:
			if not d.has(k):
				bad.append("%s no %s" % [id, k])
		if d.has("costs") and (d["costs"] as Array).size() != int(d["max"]):
			bad.append("%s costs != max" % id)
		if not d.has("costs") and not (d.has("base") and d.has("growth")):
			bad.append("%s no price" % id)
		if not LabDB.HALL_ROWS.has(int(d.get("hall", 0))):
			bad.append("%s hall %s" % [id, d.get("hall")])
		for r in d.get("req", []):
			var rid: String = String((r as Array)[0])
			if not LabDB.DEFS.has(rid) or int((r as Array)[1]) > LabDB.max_of(rid) or rid == String(id):
				bad.append("%s req %s" % [id, r])
		for k in (d.get("fx", {}) as Dictionary).keys():
			if not PF_KEYS.has(String(k)):
				bad.append("%s fx %s" % [id, k])
	var cat_ok: bool = true
	for c in LabDB.CATS:
		cat_ok = cat_ok and int(cats.get(String((c as Array)[0]), 0)) > 0
	t._check("P8 research: 48+ projects in 7 categories, unique ids, every one complete (name, price, Hall row, icon)", LabDB.IDS.size() >= 48 and LabDB.IDS.size() == LabDB.DEFS.size() and cat_ok and cats.size() == LabDB.CATS.size() and bad.is_empty(), "%d %s %s" % [LabDB.IDS.size(), cats, bad])
	# every prerequisite chain ends (no cycles): depth-first with a guard
	var cyc: Array = []
	for id in LabDB.IDS:
		var seen: Dictionary = {}
		var stack: Array = [String(id)]
		var n: int = 0
		while not stack.is_empty() and n < 500:
			n += 1
			var cur: String = String(stack.pop_back())
			for r in LabDB.get_def(cur).get("req", []):
				var rid: String = String((r as Array)[0])
				if rid == String(id):
					cyc.append(id)
				elif not seen.has(rid):
					seen[rid] = true
					stack.append(rid)
	t._check("P8 research: prerequisites form no cycles; the existing V1 projects keep their ids", cyc.is_empty() and LabDB.DEFS.has("offcap") and LabDB.DEFS.has("offrate") and LabDB.DEFS.has("dmg") and LabDB.DEFS.has("core_theory"), str(cyc))
	var gl: Array = []
	for id in LabDB.IDS:
		var sp: Array = LabDB.get_def(String(id))["icon"]
		if sp.size() != 2 or not Color.html_is_valid(String(sp[1])):
			gl.append(id)
	t._check("P8 research: every project has a neon glyph icon", gl.is_empty(), str(gl))


# ------------------------------------------------------------------ costs
static func _costs(t) -> void:
	t._check("P8 steep: Game Speed 8k / 60k / 400k / 2.5M for 1.5x / 2x / 2.5x / 3x", Labs.cost("speed", 0) == 8000 and Labs.cost("speed", 1) == 60000 and Labs.cost("speed", 2) == 400000 and Labs.cost("speed", 3) == 2500000 and LabDB.SPEED_STEPS == [1.0, 1.5, 2.0, 2.5, 3.0])
	var sv: Dictionary = _save()
	_lv(sv, "speed", 4)
	t._check("P8 steep: Speed 4 unlocks every step up to 3x", Labs.speed_steps(sv) == [1.0, 1.5, 2.0, 2.5, 3.0], str(Labs.speed_steps(sv)))
	t._check("P8 steep: Grid 2k .. 8M, Lab Discount 25k x 2.4^L, Draft Choices 150k / 2M", Labs.cost("grid", 0) == 2000 and Labs.cost("grid", 6) == 8000000 and Labs.cost("lab_discount", 0) == 25000 and Labs.cost("lab_discount", 2) == 144000 and Labs.cost("draft_choices", 0) == 150000 and Labs.cost("draft_choices", 1) == 2000000)
	var d0: Dictionary = _save(10000)
	t._check("P8 discount: none at Lab Discount 0 (price = list price)", Labs.price(d0, "dmg") == 80 and Labs.discount(d0) == 0.0)
	_lv(d0, "lab_discount", 5)
	var lc: int = int(d0["coins"])
	var ev: Array = Labs.start(d0, "dmg", OT0)
	t._check("P8 discount: Lab Discount 5 = -15% on every project, and start() pays the discounted price", Labs.price(d0, "grid") == 1700 and int(ev[0]["cost"]) == 68 and int(d0["coins"]) == lc - 68 and Labs.level(d0, "dmg") == 1, "%d %s" % [Labs.price(d0, "grid"), ev])


# ------------------------------------------------------------------ gating
static func _gating(t) -> void:
	var sv: Dictionary = _save()
	t._check("P8 gating: a new save (Hall Lv 1) opens the row-1 projects", Labs.can_start(sv, "dmg") and Labs.can_start(sv, "grid") and Labs.can_start(sv, "speed") and Labs.can_start(sv, "fast_reveal"))
	t._check("P8 gating: a Hall-3 project names the Hall level it needs", not Labs.can_start(sv, "loot_theory") and Labs.why_locked(sv, "loot_theory") == "Needs Research Hall Lv 3" and Labs.start(sv, "loot_theory", OT0).is_empty())
	_hall(sv, 3)
	t._check("P8 gating: with the Hall row open, a missing prerequisite names itself", Labs.can_start(sv, "loot_theory") and Labs.why_locked(sv, "optics") == "Needs Targeting AI Lv 2" and not Labs.can_start(sv, "optics"), Labs.why_locked(sv, "optics"))
	_lv(sv, "targeting", 2)
	t._check("P8 gating: meeting the prerequisite opens it", Labs.is_open(sv, "optics") and Labs.can_start(sv, "optics"))
	_hall(sv, 5)
	t._check("P8 gating: Hall 5 still holds back the Hall-8 row (Mythic Fusion)", Labs.why_locked(sv, "mythic_fusion") == "Needs Research Hall Lv 8" and Labs.hall_req("mythic_fusion") == 8)
	var nh: Dictionary = _save()
	_hall(nh, 0)
	t._check("P8 gating: no Research Hall, no research", not Labs.can_start(nh, "dmg"))


# ------------------------------------------------------------------ run
static func _run_effects(t) -> void:
	var base = _run(_save())
	# fx research: each level adds its fx to the run's pf()
	var fx_ids: Array = []
	var fx_bad: Array = []
	for id in LabDB.IDS:
		var fx: Dictionary = LabDB.get_def(String(id)).get("fx", {})
		if fx.is_empty():
			continue
		fx_ids.append(id)
		var sv: Dictionary = _save()
		_lv(sv, String(id), 3)
		var S = _run(sv)
		for k in fx.keys():
			if not is_equal_approx(S.pf(String(k)) - base.pf(String(k)), 3.0 * float(fx[k])):
				fx_bad.append("%s %s %f" % [id, k, S.pf(String(k)) - base.pf(String(k))])
	t._check("P8 table: every fx project (Targeting AI, Optics, Reactor, Aegis, Shielding, Boss Breaker, Compound Interest) moves its run fx by fx x level", fx_ids.size() >= 7 and fx_bad.is_empty(), "%s %s" % [fx_ids, fx_bad])
	var tg: Dictionary = _save()
	_lv(tg, "targeting", 4)
	_lv(tg, "shielding", 2)
	var T = _run(tg)
	t._check("P8 table: Targeting AI 4 = +0.2 cell Weapon range, Core Shielding 2 = +20 shield (live stats)", is_equal_approx(float((T.stats["weapons"] as Array).back()["range"]) - float((base.stats["weapons"] as Array).back()["range"]), 0.2 * TowerState.cpx()) and is_equal_approx(float(T.stats.get("shield_max", 0.0)) - float(base.stats.get("shield_max", 0.0)), 20.0), "%s %s / %s %s" % [(T.stats["weapons"] as Array).back()["range"], (base.stats["weapons"] as Array).back()["range"], T.stats.get("shield_max"), base.stats.get("shield_max")])
	var en: Dictionary = _save()
	_lv(en, "en_hp", 10)
	_lv(en, "en_atk", 5)
	_lv(en, "en_speed", 5)
	var E = _run(en)
	t._check("P8 table: Weak Points 10 / Blunting 5 / Mire Field 5 = enemy HP x0.90, damage x0.90, speed x0.95", is_equal_approx(E.enemy_hp_mod, base.enemy_hp_mod * 0.9) and is_equal_approx(E.enemy_dmg_mod, base.enemy_dmg_mod * 0.9) and is_equal_approx(E.enemy_spd_mod, base.enemy_spd_mod * 0.95))
	var el: Dictionary = _save()
	_lv(el, "elite_hp", 10)
	var A = _run(el, 5)
	var B = _run(_save(), 5)
	A._spawn("elite", [], TowerState.CENTER + Vector2(300, 0))
	B._spawn("elite", [], TowerState.CENTER + Vector2(300, 0))
	var ea: int = int(A.en.order[A.en.order.size() - 1])
	var eb: int = int(B.en.order[B.en.order.size() - 1])
	t._check("P8 table: Elite Profiling 10 = elites spawn with -30% HP", is_equal_approx(A.en.max_hp[ea], B.en.max_hp[eb] * 0.7) and A.en.kind[ea] == "elite", "%f %f" % [A.en.max_hp[ea], B.en.max_hp[eb]])
	var sp: Dictionary = _save()
	_lv(sp, "sapper_damp", 5)
	_lv(sp, "manual", 3)
	_lv(sp, "bounty", 4)
	_lv(sp, "loot_theory", 5)
	var P = _run(sp)
	t._check("P8 table: Sapper Dampening / Manual Mastery / Clear Bounty / Loot Theory reach the run", is_equal_approx(float(P.mods["lab_enemy"]["sapper"]), 0.40) and is_equal_approx(float(P.mods["lab_aim"]), 0.15) and is_equal_approx(float(P.mods["lab_bounty"]), 0.40) and is_equal_approx(float(P.mods["lab_items"]), 0.50))
	# Loot Theory raises the item roll odds but keeps the RNG call order
	var r1 := RandomNumberGenerator.new()
	var l1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	var l2 := RandomNumberGenerator.new()
	r1.seed = 9
	r2.seed = 9
	l1.seed = 11
	l2.seed = 11
	var n1: int = 0
	var n2: int = 0
	for k in 2000:
		n1 += Drops.roll(r1, "elite", {"tier": 1, "wave": 5, "items_left": 99, "item_mult": 1.0}, l1).filter(func(d: Variant) -> bool: return String((d as Dictionary)["kind"]) == "item").size()
		n2 += Drops.roll(r2, "elite", {"tier": 1, "wave": 5, "items_left": 99, "item_mult": 2.0}, l2).filter(func(d: Variant) -> bool: return String((d as Dictionary)["kind"]) == "item").size()
	t._check("P8 table: Loot Theory's item multiplier raises elite item drops on the same RNG stream", n2 > n1 and n1 > 0 and r1.state == r2.state and l1.state == l2.state, "%d vs %d" % [n1, n2])
	# drafts: choices, locks, banishes
	var dr: Dictionary = _save()
	_lv(dr, "draft_choices", 2)
	_lv(dr, "draft_lock", 1)
	_lv(dr, "banish_r", 2)
	_lv(dr, "reroll", 1)
	var D = _run(dr)
	var guard: int = 0
	while D.draft.is_empty() and guard < 50:
		guard += 1
		D.tick(0.1)
	var D0 = _run(_save())
	guard = 0
	while D0.draft.is_empty() and guard < 50:
		guard += 1
		D0.tick(0.1)
	t._check("P8 table: Draft Choices 2 = 5 cards (3 without), Draft Lock = 3 locks, Banish 2 = +2 banishes", D.draft.size() == 5 and D0.draft.size() == 3 and D.lock_cap() == 3 and D0.lock_cap() == 2 and D.banish_left == D0.banish_left + 2, "%d %d %d %d" % [D.draft.size(), D0.draft.size(), D.banish_left, D0.banish_left])
	# Enhancement Theory gates nine tracks, three per level
	var et: Dictionary = _save()
	var U = _run(et)
	U.cash = 1.0e9
	var locked: Array = []
	for tid in TrackDB.IDS:
		if not U.track_unlocked(String(tid)):
			locked.append(tid)
	t._check("P8 Enhancement Theory: 9 tracks start locked (3 per tree) and can't be bought", locked.size() == 9 and U.buy_track("a_exec").is_empty() and not U.track_unlocked("e_free") and U.track_unlocked("a_dmg"), str(locked))
	_lv(et, "enh_theory", 2)
	var U2 = _run(et)
	U2.cash = 1.0e9
	t._check("P8 Enhancement Theory II opens tiers I + II, not III", U2.track_unlocked("a_exec") and U2.track_unlocked("d_last") and not U2.track_unlocked("a_pierce") and not U2.buy_track("a_chain").is_empty() and TrackDB.unlock_label("a_pierce") == "Enhancement Theory III")
	var nl: Dictionary = _save()
	_lv(nl, "targeting", 5)
	_lv(nl, "en_hp", 10)
	var NL = TowerState.new()
	NL.setup(77, nl, 0, {"modifiers": ["nolabs"]})
	t._check("P8 table: the No Labs modifier drops research fx and enemy cuts too", is_equal_approx(NL.pf("range"), base.pf("range")) and is_equal_approx(NL.enemy_hp_mod, base.enemy_hp_mod))


# ------------------------------------------------------------------ meta
static func _meta_effects(t) -> void:
	# Outpost licences
	var sv: Dictionary = _save()
	var m0: int = Outpost.limit_of(sv, "mill")
	var s0: int = Outpost.limit_of(sv, "scav_post")
	var c0: int = Outpost.limit_of(sv, "arsenal")
	_lv(sv, "lic_mill", 2)
	_lv(sv, "lic_mine", 1)
	_lv(sv, "lic_scav", 1)
	_lv(sv, "lic_core", 1)
	t._check("P8 licences: Mill +2, Mine +1, each Scavenger +1, each Core building +1", Outpost.limit_of(sv, "mill") == m0 + 2 and Outpost.limit_of(sv, "gemmine") == OutpostDB.limit("gemmine", int(sv["outpost"]["relay_lvl"])) + 1 and Outpost.limit_of(sv, "scav_post") == s0 + 1 and Outpost.limit_of(sv, "scav_deep") == OutpostDB.limit("scav_deep", 1) + 1 and Outpost.limit_of(sv, "arsenal") == c0 + 1)
	var rq0: int = Outpost.relay_req_of(sv, "scav_deep")
	_lv(sv, "lic_adv", 2)
	t._check("P8 licences: Advanced Licensing 2 opens Relay-3+ buildings two Relay levels early (never below 2)", rq0 == 7 and Outpost.relay_req_of(sv, "scav_deep") == 5 and Outpost.relay_req_of(sv, "shrine") == 2 and Outpost.relay_req_of(sv, "pylon") == 2 and Outpost.relay_req_of(sv, "arsenal") == 1)
	var pm: Dictionary = _save()
	pm["outpost"]["relay_lvl"] = 2
	var mills: int = 0
	for x in [[7, 8], [7, 11], [10, 8]]:
		var pe: Array = _ev(Outpost.place(pm, "mill", int(x[0]), int(x[1]), 0, OT0), "op_placed")
		mills += pe.size()
	_lv(pm, "lic_mill", 1)
	var pe2: Array = _ev(Outpost.place(pm, "mill", 10, 11, 0, OT0), "op_placed")
	t._check("P8 licences: placing honours the licence (a 3rd Mill at Relay 2 only with a Mill Licence)", mills == 2 and pe2.size() == 1, "%d %d" % [mills, pe2.size()])
	# Scavenging speeds scavengers
	var sc: Dictionary = _save()
	sc["outpost"]["relay_lvl"] = 8
	var pe3: Array = _ev(Outpost.place(sc, "scav_post", 7, 8, 0, OT0), "op_placed")
	var su: String = String(pe3[0]["uid"]) if not pe3.is_empty() else ""
	var r0: float = Outpost.nominal_rate(sc, su) if su != "" else 0.0
	_lv(sc, "scav_rate", 5)
	t._check("P8 table: Scavenging 5 = Scavengers +30% speed", su != "" and r0 > 0.0 and is_equal_approx(Outpost.nominal_rate(sc, su), r0 * 1.3), "%f %f" % [r0, Outpost.nominal_rate(sc, su) if su != "" else 0.0])
	# Forge discounts
	var fg: Dictionary = _save()
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var it: Dictionary = Parts.roll(r, "drop", {"base": "brl_autocannon", "slot": "barrel", "rarity": "epic"}, {})
	var up0: int = Parts.upgrade_cost(it, fg)
	var rr0: int = Parts.reroll_cost(it, fg)
	var sl0: int = Parts.salvage_value(it, fg)
	_lv(fg, "greater_cal", 2)
	_lv(fg, "reroll_disc", 5)
	_lv(fg, "reclaim", 5)
	t._check("P8 forge (V3 parts): Greater Calibration 2 = upgrades -10%, Reroll Discount 5 = rerolls -40%, Reclamation 5 = smelt +50%", Parts.upgrade_cost(it, fg) == int(round(float(Parts.upgrade_cost(it)) * 0.9)) and up0 == Parts.upgrade_cost(it) and Parts.reroll_cost(it, fg) == int(round(float(rr0) * 0.6)) and Parts.salvage_value(it, fg) == int(round(float(sl0) * 1.5)), "%d %d %d / %d %d %d" % [up0, rr0, sl0, Parts.upgrade_cost(it, fg), Parts.reroll_cost(it, fg), Parts.salvage_value(it, fg)])
	# Cache Luck lifts cache contents (same save stream, same caches)
	var ranks: Array = []
	for cl in [0, 5]:
		var lsv: Dictionary = _save()
		_lv(lsv, "cache_luck", cl)
		var caches: Array = []
		for k in 25:
			caches.append({"id": "field", "ilvl": 20})
		var ev: Array = Loot.realize(lsv, {"caches": caches, "items": [], "scrap": 0, "tier": 1, "luck": 0})
		var sum: int = 0
		for e in ev:
			if ["loot_item", "loot_salvaged"].has(String((e as Dictionary)["t"])):
				sum += RarityDB.rank(String((e as Dictionary)["rar"]))
		ranks.append(sum)
	t._check("P8 loot: Cache Luck 5 raises the rarity of cache contents", int(ranks[1]) > int(ranks[0]), str(ranks))
	# the research view's glyph tiles draw for every project (no missing glyph)
	t._check("P8 research view: Labs.levels hands every project to the run (TrackDB unlocks)", (BaseMeta.run_mods(_save())["res"] as Dictionary).size() == LabDB.IDS.size())


# ------------------------------------------------------------------ P8b QOL
static func _qol(t) -> void:
	var sv: Dictionary = _save()
	t._check("P8b QOL: switches start off and do nothing without research", Labs.auto_buy_mode(sv) == "" and Labs.cycle_auto_buy(sv) == "" and Labs.auto_salvage_level(sv) == 0 and Labs.cycle_auto_salvage(sv) == 0 and not Labs.toggle_auto_restart(sv) and not Labs.auto_restart_on(sv) and Labs.preset_slots(sv) == 0 and sv.has("qol"))
	var bad: Dictionary = BaseMeta.normalize({"version": BaseMeta.VERSION, "qol": {"auto_buy": "bogus", "auto_salvage": 9, "auto_restart": 1}})
	t._check("P8b QOL: the save block normalizes (unknown rule off, salvage clamped)", String(bad["qol"]["auto_buy"]) == "" and int(bad["qol"]["auto_salvage"]) == 2 and bool(bad["qol"]["auto_restart"]))
	# Auto-Collect: coins / Scrap buildings, not Scavengers
	var oc: Dictionary = _save()
	oc["outpost"]["relay_lvl"] = 8
	var mu: String = ""
	var pe: Array = _ev(Outpost.place(oc, "mill", 7, 8, 0, OT0), "op_placed")
	if not pe.is_empty():
		mu = String(pe[0]["uid"])
	var pe2: Array = _ev(Outpost.place(oc, "scav_post", 7, 10, 0, OT0), "op_placed")
	var su: String = String(pe2[0]["uid"]) if not pe2.is_empty() else ""
	var later: int = OT0 + 6 * 3600 * 4
	t._check("P8b Auto-Collect: nothing without the research", Outpost.auto_collect(oc, later).filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == "auto_collect").is_empty())
	_lv(oc, "auto_collect", 1)
	var c0: int = int(oc["coins"])
	var ac: Array = _ev(Outpost.auto_collect(oc, later + 60), "auto_collect")
	var bl: Dictionary = oc["outpost"]["buildings"]
	t._check("P8b Auto-Collect: one summary event pays the Mill; the Scavenger keeps its items for a click", mu != "" and su != "" and ac.size() == 1 and int(ac[0]["coins"]) > 0 and int(oc["coins"]) == c0 + int(ac[0]["coins"]) and float(bl[mu]["stored"]) < 1.0 and float(bl[su]["stored"]) >= 1.0, "%s %s" % [ac, bl.get(su, {})])
	# P9 regression: the boot "while you were away" claim with a stocked
	# Scavenger (its resource is items, not coins / Scrap) used to crash
	var aw: Array = Outpost.claim_away(oc, later + 7200)
	t._check("P9 regression: claim_away with a stocked Scavenger pays coins and banks its items (no crash)", _ev(aw, "offline").size() == 1 and _ev(aw, "loot_item").size() + _ev(aw, "loot_salvaged").size() >= 1, str(aw.map(func(e: Variant) -> String: return String((e as Dictionary)["t"]))))
	# Auto-Salvage: Commons become Scrap on arrival when switched on
	var ls: Dictionary = _save()
	_lv(ls, "auto_salvage", 1)
	Labs.cycle_auto_salvage(ls)
	var n0: int = (Parts.block(ls)["items"] as Dictionary).size()
	var lev: Array = Loot.realize(ls, {"caches": [{"id": "field", "ilvl": 10}, {"id": "field", "ilvl": 10}, {"id": "field", "ilvl": 10}], "items": [], "scrap": 0, "tier": 1, "luck": 0})
	var kept_common: int = 0
	for e in _ev(lev, "loot_item"):
		if String(e["rar"]) == "common":
			kept_common += 1
	var auto_c: Array = _ev(lev, "loot_salvaged").filter(func(e: Variant) -> bool: return bool((e as Dictionary).get("auto", false)) and String((e as Dictionary)["rar"]) == "common")
	t._check("P8b Auto-Salvage: Commons are salvaged for Scrap on arrival, better parts are kept", kept_common == 0 and auto_c.size() > 0 and (Parts.block(ls)["items"] as Dictionary).size() == n0 + _ev(lev, "loot_item").size() and Labs.cycle_auto_salvage(ls) == 0, "%d %d" % [kept_common, auto_c.size()])
	# Presets
	var ps: Dictionary = _save()
	_lv(ps, "presets", 2)
	var g: Dictionary = Parts.block(ps)
	var w0: int = int(g["equipped"]["barrel"][0])
	var r := RandomNumberGenerator.new()
	r.seed = 21
	var w1: int = Parts.add_item(ps, Parts.roll(r, "drop", {"base": "brl_lance", "slot": "barrel", "rarity": "rare"}, {}))
	var m1: int = Parts.add_item(ps, Parts.roll(r, "drop", {"base": "amm_toxic", "slot": "ammo", "rarity": "rare"}, {}))
	var sv0: Array = Parts.save_preset(ps, 0)
	Parts.equip(ps, w1, 0)
	Parts.equip(ps, m1)
	Parts.save_preset(ps, 1)
	var ld0: Array = Parts.load_preset(ps, 0)
	var back0: bool = int(g["equipped"]["barrel"][0]) == w0 and (g["equipped"]["ammo"] as Array).is_empty()
	Parts.load_preset(ps, 1)
	var back1: bool = int(g["equipped"]["barrel"][0]) == w1 and int((g["equipped"]["ammo"] as Array)[0]) == m1
	t._check("P8b presets: save / load swaps the whole loadout; slot 3 needs more research", sv0.size() == 1 and ld0.size() == 1 and back0 and back1 and Parts.save_preset(ps, 2).is_empty())
	Parts.unequip(ps, "ammo", 0)
	Parts.salvage(ps, m1)
	Parts.load_preset(ps, 1)
	t._check("P8b presets: a smelted part leaves its slot empty", (g["equipped"]["ammo"] as Array).is_empty())
	# Bulk Upgrade
	var bu: Dictionary = _save(1_000_000)
	_lv(bu, "bulk_upgrade", 1)
	var it: Dictionary = Parts.roll(r, "drop", {"base": "brl_autocannon", "slot": "barrel", "rarity": "common"}, {})
	var u: int = Parts.add_item(bu, it)
	var up5: Array = Parts.upgrade_n(bu, u, 5)
	var upm: Array = Parts.upgrade_n(bu, u, 0)
	t._check("P8b Bulk Upgrade: x5 = five levels, MAX = up to the rarity cap", _ev(up5, "part_upgrade").size() == 5 and int(Parts.item(bu, u)["lvl"]) == Parts.max_lvl_of("common") and not upm.is_empty())
	var nb: Dictionary = _save(1_000_000)
	var u2: int = Parts.add_item(nb, Parts.roll(r, "drop", {"base": "brl_autocannon", "slot": "barrel", "rarity": "common"}, {}))
	t._check("P8b Bulk Upgrade: without the research one click is one level", _ev(Parts.upgrade_n(nb, u2, 5), "part_upgrade").size() == 1)
	# Auto-Buy in a run
	var ab: Dictionary = _save()
	_lv(ab, "auto_buy", 1)
	_lv(ab, "enh_theory", 1)
	Labs.cycle_auto_buy(ab)
	var S = _run(ab)
	S.draft_queue.clear()
	S.cash = 1000.0
	var ev: Array = []
	S._auto_buy(ev)
	var bought: Array = _ev(ev, "track")
	var only_attack: bool = true
	for e in bought:
		only_attack = only_attack and String(TrackDB.get_def(String(e["track"]))["tree"]) == "attack" and not TrackDB.is_od(String(e["track"])) and bool(e.get("auto", false))
	t._check("P8b Auto-Buy: Attack rule buys the cheapest Attack tracks and keeps 25% of the cash", Labs.auto_buy_mode(ab) == "attack" and bought.size() >= 3 and only_attack and S.cash >= 250.0 - 0.001, "%d %s %f" % [bought.size(), only_attack, S.cash])
	var S0 = _run(_save())
	S0.cash = 1000.0
	var ev0: Array = []
	S0._auto_buy(ev0)
	t._check("P8b Auto-Buy: off without the research (a default run buys nothing)", ev0.is_empty() and is_equal_approx(S0.cash, 1000.0))
	# Auto-Restart switch
	var ar: Dictionary = _save()
	_lv(ar, "auto_restart", 1)
	t._check("P8b Auto-Restart: the switch toggles once researched", Labs.toggle_auto_restart(ar) and Labs.auto_restart_on(ar) and not Labs.toggle_auto_restart(ar))

