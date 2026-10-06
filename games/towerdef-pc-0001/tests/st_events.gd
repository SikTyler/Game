extends RefCounted
## P7c selftest stage: run events. Directives (a cleared boss wave offers 3
## rule-changers; gains and costs land), the Supply Drop slot spin (every 7th
## wave, seeded, x1 / x3 / x8 payouts, jackpot), the kill-streak combo
## (tiers, decay, cash / XP multiplier), draft card locks (rerolls keep them,
## carried to the next hand, max 2) and weapon evolutions (T3 + partner).
## `t` is the selftest runner (t._check).

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const DirectiveDB := preload("res://data/DirectiveDB.gd")
const EvoDB := preload("res://data/EvoDB.gd")
const Draft := preload("res://Draft.gd")


static func run(t) -> void:
	_directives(t)
	_supply(t)
	_combo(t)
	_locks(t)
	_evolution(t)


static func _run(sd: int = 91):
	var S = TowerState.new()
	S.setup(sd, BaseMeta.normalize({}))
	for i in TowerState.N:
		S.unlocked[i] = not TowerState.is_core_cell(i)
	S.spawn_hold = true
	S.draft_queue.clear()
	return S


static func _ev(ev: Array, kind: String) -> Array:
	return ev.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == kind)


static func _core(S) -> Dictionary:
	return (S.stats["weapons"] as Array).back()


# ---------------------------------------------------------------- directives
static func _directives(t) -> void:
	var S = _run()
	S.wave = S.boss_every
	S.wave_t = S.wave_time - 0.001
	var ev: Array = S.tick(0.05)
	var offer: Array = S.directive_offer.duplicate()
	var uniq: Dictionary = {}
	for id in offer:
		uniq[id] = true
	t._check("P7c directive: clearing a boss wave offers 3 distinct Directives (no Epic draft)", _ev(ev, "directive_offer").size() == 1 and offer.size() == 3 and uniq.size() == 3 and S.draft.is_empty() and S._busy())
	var S2 = _run()
	S2.wave = S2.boss_every
	S2.wave_t = S2.wave_time - 0.001
	S2.tick(0.05)
	t._check("P7c directive: the offer is seeded (same seed, same three)", S2.directive_offer == offer)
	var B = _run()
	var base_dmg: float = float(_core(B)["dmg"])
	B.directive_offer = ["dr_bullet"]
	ev = B.choose_directive(0)
	t._check("P7c directive: Bullet Hell = +2 targets, -25% damage", B.directives == ["dr_bullet"] and int(_core(B)["multishot"]) == 2 and is_equal_approx(float(_core(B)["dmg"]), base_dmg * 0.75) and _ev(ev, "directive_taken").size() == 1 and not B._busy())
	var G = _run()
	var hp0: float = G.enemy_hp_mod
	G.directive_offer = ["dr_gold"]
	G.choose_directive(0)
	t._check("P7c directive: Gold Rush = kill cash x2, enemies +20% HP", is_equal_approx(G.pf("kill_cash"), 1.0) and is_equal_approx(G.enemy_hp_mod, hp0 * 1.2))
	var H = _run()
	var ch0: int = int(H._draft_ctx("")["choices"])
	var c0: float = H.count_mult
	H.directive_offer = ["dr_high"]
	H.choose_directive(0)
	t._check("P7c directive: High Roller = +1 draft choice, +25% coins, +15% enemies", int(H._draft_ctx("")["choices"]) == ch0 + 1 and is_equal_approx(H.xf("coin_run"), 0.25) and is_equal_approx(H.count_mult, c0 * 1.15))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var never: bool = true
	for k in 50:
		never = never and not DirectiveDB.offer(rng, ["dr_bullet", "dr_gold"]).has("dr_bullet")
	t._check("P7c directive: a taken Directive is never offered again; every one has a cost", never and DirectiveDB.IDS.all(func(i: Variant) -> bool: return String(DirectiveDB.get_def(String(i)).get("cost", "")) != ""))


# ---------------------------------------------------------------- supply drop
static func _supply(t) -> void:
	var S = _run()
	S.wave = TowerState.SUPPLY_EVERY - 1
	S.wave_t = S.wave_time - 0.001
	var ev: Array = S.tick(0.05)
	var sd: Array = _ev(ev, "supply_drop")
	t._check("P7c supply: entering wave 7 spins a 3-reel Supply Drop", S.wave == TowerState.SUPPLY_EVERY and sd.size() == 1 and (sd[0]["reels"] as Array).size() == 3)
	var S2 = _run()
	S2.wave = TowerState.SUPPLY_EVERY - 1
	S2.wave_t = S2.wave_time - 0.001
	var ev2: Array = S2.tick(0.05)
	t._check("P7c supply: the reels are seeded (same seed, same spin)", (_ev(ev2, "supply_drop")[0]["reels"] as Array) == (sd[0]["reels"] as Array))
	var P = _run()
	var cash0: float = P.cash
	var xp0: float = P.xp
	var pe: Array = []
	P._supply_pay(["cash", "cash", "xp"], pe)
	var pays: Dictionary = pe[0]["pays"]
	t._check("P7c supply: a cash pair pays x3 (360 x cash index), a lone XP pays x1", is_equal_approx(P.cash - cash0, 360.0 * P.cash_index()) and is_equal_approx(float(pays["cash"]), 360.0 * P.cash_index()) and is_equal_approx(P.xp - xp0, 0.35 * P.xp_need()) and not bool(pe[0]["jackpot"]))
	var R = _run()
	R._supply_pay(["reroll", "card", "cache"], [])
	t._check("P7c supply: reroll / card / cache singles: +1 reroll, +1 draft queued, +1 Field Cache", R.rerolls_left == 1 and R.draft_queue.size() == 1 and (R.loot["caches"] as Array).size() == 1 and String((R.loot["caches"] as Array)[0]["id"]) == "field")
	var J = _run()
	var jc0: float = J.cash
	var je: Array = []
	J._supply_pay(["star", "star", "star"], je)
	t._check("P7c supply: three stars = JACKPOT (400 x cash index, an Epic+ draft, an Elite Cache)", bool(je[0]["jackpot"]) and is_equal_approx(J.cash - jc0, 400.0 * J.cash_index()) and J.draft_queue == ["epic"] and String((J.loot["caches"] as Array)[0]["id"]) == "elite")
	var D = _run()
	D._supply_pay(["star", "star", "xp"], [])
	t._check("P7c supply: two stars = a gold perk offer", D.perk_pending == 1)


# ---------------------------------------------------------------- combo
static func _combo(t) -> void:
	var S = _run()
	t._check("P7c combo: no streak = x1", S.combo_tier == 0 and is_equal_approx(S.combo_mult(), 1.0))
	S.combo = 150.0
	var ev: Array = []
	S._combo_check(ev)
	t._check("P7c combo: 150 kills on the meter = tier 2 (x1.25), with an event", S.combo_tier == 2 and is_equal_approx(S.combo_mult(), 1.25) and _ev(ev, "combo_tier").size() == 1)
	S.combo = 1500.0
	S._combo_check([])
	t._check("P7c combo: 1500 = FRENZY x2.00", S.combo_tier == 4 and is_equal_approx(S.combo_mult(), 2.0))
	S.combo = 100.0
	S._combo_check([])
	S.stats["weapons"] = []
	for k in 25:
		S.tick(0.1)
	t._check("P7c combo: the meter decays (100 -> ~37 after 2.5 s = tier 1)", S.combo > 30.0 and S.combo < 45.0 and S.combo_tier == 1, "%.1f" % S.combo)
	# the multiplier pays kill cash + XP; kills fill the meter
	var A = _run()
	var B = _run()
	B.combo = 150.0
	B._combo_check([])
	for X in [A, B]:
		X.add_enemy({"kind": "drone", "pos": TowerState.CENTER + Vector2(200, 0), "hp": 0.5, "max_hp": 0.5, "spd": 0.0, "dmg": 0.0, "cash": 4.0, "xp": 2.0, "coin": 0.0, "size": 12.0, "atk_cd": 0.0, "slow_t": 0.0})   # xp 2 x1.25 < the level-1 need (4)
	A.stats["cash_ps"] = 0.0
	B.stats["cash_ps"] = 0.0
	var ca: float = A.cash
	var cb: float = B.cash
	var xa: float = A.xp
	var xb: float = B.xp
	A.tick(0.05)
	B.tick(0.05)
	t._check("P7c combo: x1.25 on kill cash and XP; a kill adds to the meter", A.kills == 1 and B.kills == 1 and is_equal_approx((B.cash - cb), (A.cash - ca) * 1.25) and is_equal_approx(B.xp - xb, (A.xp - xa) * 1.25) and A.combo > 0.5, "kills %d %d cash %.3f %.3f xp %.3f %.3f combo %.2f %d" % [A.kills, B.kills, A.cash - ca, B.cash - cb, A.xp - xa, B.xp - xb, A.combo, B.combo_tier])


# ---------------------------------------------------------------- locks
static func _locks(t) -> void:
	var S = _run()
	S.grant_draft()
	var c1: Dictionary = S.draft[1]
	var ev: Array = S.toggle_lock(1)
	t._check("P7c lock: a card locks (event)", bool((S.draft[1] as Dictionary).get("lock", false)) and _ev(ev, "draft_lock").size() == 1)
	S.reroll_draft()
	t._check("P7c lock: a reroll keeps the locked card in its slot", String((S.draft[1] as Dictionary)["id"]) == String(c1["id"]) and bool((S.draft[1] as Dictionary).get("lock", false)))
	var ids: Dictionary = {}
	for c in S.draft:
		ids[String((c as Dictionary)["id"])] = true
	t._check("P7c lock: ... and the rerolled hand never repeats it", ids.size() == S.draft.size())
	S.toggle_lock(0)
	t._check("P7c lock: max 2 locks", S.toggle_lock(2).is_empty() and not bool((S.draft[2] as Dictionary).get("lock", false)))
	S.draft[2] = Draft.card_for("pk_arsenal", S._draft_ctx(""))
	S.choose_card(2)
	var carried: Array = S.carry_cards.map(func(c: Variant) -> String: return String(((c as Dictionary)["card"] as Dictionary)["id"]))
	t._check("P7c lock: taking another card carries the locked ones over", carried.size() == 2)
	S.grant_draft()
	t._check("P7c lock: the next hand opens with them, still locked", S.draft.size() >= 2 and String((S.draft[0] as Dictionary)["id"]) == String(carried[0]) and String((S.draft[1] as Dictionary)["id"]) == String(carried[1]) and bool((S.draft[0] as Dictionary).get("lock", false)) and bool((S.draft[1] as Dictionary).get("lock", false)), str(carried))
	S.toggle_lock(0)
	t._check("P7c lock: a locked card unlocks", not bool((S.draft[0] as Dictionary).get("lock", false)))


# ---------------------------------------------------------------- evolution
static func _evolution(t) -> void:
	var S = _run()
	var g: int = TowerState.cell(-4, 0)
	S.slots[g] = {"id": "gun", "tier": 3, "rot": 6, "mods": []}
	S.recompute()
	var ev: Array = []
	S._check_evo(ev)
	t._check("P7c evo: a T3 Gatling alone is not ready", _ev(ev, "evo_ready").is_empty() and S.draft_queue.is_empty())
	S.slots[TowerState.cell(-5, 0)] = {"id": "armory", "tier": 1, "rot": 6, "mods": []}
	S.recompute()
	var r0: float = 0.0
	for w in S.stats["weapons"]:
		if int((w as Dictionary)["slot"]) == g:
			r0 = float((w as Dictionary)["dmg"])
	ev = S.tick(0.05)
	t._check("P7c evo: a touching Armory makes it ready: a draft led by the EVOLUTION card", _ev(ev, "evo_ready").size() == 1 and S.draft.size() >= 1 and String((S.draft[0] as Dictionary)["kind"]) == "evo" and int((S.draft[0] as Dictionary)["slot"]) == g)
	S.reroll_draft()
	t._check("P7c evo: a reroll keeps the evolution card", String((S.draft[0] as Dictionary)["kind"]) == "evo")
	ev = S.choose_card(0)
	var w2: Dictionary = {}
	for w in S.stats["weapons"]:
		if int((w as Dictionary)["slot"]) == g:
			w2 = w
	t._check("P7c evo: taking it evolves the Gatling into Bullet Storm (+2 rounds, +50% dmg)", _ev(ev, "evolved").size() == 1 and S.name_at(g) == "Bullet Storm" and is_equal_approx(float(w2["rounds_add"]), 2.0) and is_equal_approx(float(w2["dmg"]), r0 * 1.5))
	var ev3: Array = []
	S._check_evo(ev3)
	t._check("P7c evo: an evolution is offered once", ev3.is_empty())
	var bad: Array = []
	for id in EvoDB.DEFS.keys():
		var d: Dictionary = EvoDB.get_def(String(id))
		if String(d.get("name", "")) == "" or String(d.get("partner", "")) == "" or (d.get("fx", {}) as Dictionary).is_empty():
			bad.append(id)
	t._check("P7c evo: every evolution names a partner building and an fx package", bad.is_empty() and EvoDB.DEFS.size() >= 6, str(bad))
