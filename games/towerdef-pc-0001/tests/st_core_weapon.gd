extends RefCounted
## P4b selftest stage: the forged Weapon in the run. The equipped frame
## decides the Core's attack and sheet (damage x item power), every frame
## fires its own pattern and kills, every gear fx key changes the run the way
## its text says, and manual aim retargets the Core (+crit, focus meter).
## `t` is the selftest runner (t._check).

const TowerState := preload("res://TowerState.gd")
const Gear := preload("res://Gear.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const ModuleDB := preload("res://data/ModuleDB.gd")


static func run(t) -> void:
	_sheet(t)
	_frames(t)
	_patterns(t)
	_fx_weapon(t)
	_fx_body(t)
	_aim(t)


## A run with `weapon` equipped (+ socketed modules), every cell open, no waves.
static func _run(weapon: Dictionary, mods: Array = [], lvl: int = 1):
	var sv: Dictionary = BaseMeta.default_save()
	sv["core"]["lvl"] = lvl
	var u: int = Gear.add_item(sv, weapon)
	Gear.equip(sv, u)
	for m in mods:
		Gear.equip(sv, Gear.add_item(sv, m))
	var S = TowerState.new()
	S.setup(1234, BaseMeta.normalize(sv))
	for i in TowerState.N:
		S.unlocked[i] = not TowerState.is_core_cell(i)
	S.spawn_hold = true
	return S


static func _w(base: String, perks: Array = [], rar: String = "common", lvl: int = 1, brand: String = "standard") -> Dictionary:
	return Gear.make("weapon", base, rar, lvl, perks, brand)


static func _m(base: String, perks: Array = [], rar: String = "common") -> Dictionary:
	return Gear.make("module", base, rar, 1, perks)


static func _p(id: String, tier: int = 5, q: float = 0.5) -> Dictionary:
	return {"id": id, "t": tier, "q": q, "lock": false}


static func _core(S) -> Dictionary:
	return (S.stats["weapons"] as Array).back()


## Only the Core fires; cooldown ready.
static func _ready(S) -> void:
	S.stats["weapons"] = [_core(S)]
	for k in TowerState.N:
		S.cooldowns[k] = 0.0


static func _body(S, p: Vector2, hp: float = 999.0, kind: String = "mite", spd: float = 0.0) -> int:
	S.add_enemy({"kind": kind, "pos": p, "hp": hp, "max_hp": hp, "size": 10.0, "spd": spd})
	return S.en.order[S.en.order.size() - 1]


static func _fire(S) -> Array:
	S.eh.rebuild()
	for k in TowerState.N:
		S.cooldowns[k] = 0.0
	var ev: Array = []
	S._fire(0.01, ev)
	return ev


static func _evts(ev: Array, kind: String) -> Array:
	return ev.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == kind)


static func _lost(S, e: int, hp0: float = 999.0) -> float:
	return hp0 - float(S.en.hp[e])


# ------------------------------------------------------------------ sheet

static func _sheet(t) -> void:
	var S = TowerState.new()
	S.setup(1234, BaseMeta.normalize({}))
	var cw: Dictionary = _core(S)
	t._check("P4 run: a fresh save fires the Standard Issue Autocannon = the base Core sheet", String(cw["attack"]) == "cannon" and is_equal_approx(float(cw["dmg"]), 10.0) and is_equal_approx(float(cw["rate"]), 1.25) and is_equal_approx(float(cw["range"]), 4.0 * TowerState.cpx()) and S.pfx.is_empty() and String(S.core_def["attack_name"]) == "Standard Issue Autocannon")
	t._check("P4 run: the Core's body stays the CoreDB sheet", is_equal_approx(float(S.stats["max_hp"]), float(CoreDB.get_def()["hp"])) and is_equal_approx(float(S.stats["cash_ps"]), float(CoreDB.get_def()["cash"])))
	var L = _run(_w("lance", [], "rare", 5))
	var lw: Dictionary = _core(L)
	t._check("P4 run: the equipped frame decides the attack; damage x item power", String(lw["attack"]) == "beam" and is_equal_approx(float(lw["dmg"]), 28.0 * 1.28 * 1.2 * 1.06) and is_equal_approx(float(lw["rate"]), 0.5) and is_equal_approx(float(lw["range"]), 5.5 * TowerState.cpx()))
	var K = _run(_w("autocannon", [], "common", 1, "kessler"))
	t._check("P4 run: a brand quirk lands in the run (Kessler +10% dmg, -5% rate)", is_equal_approx(float(_core(K)["dmg"]), 11.0) and is_equal_approx(float(_core(K)["rate"]), 1.25 * 0.95))
	var O = _run(_w("autocannon"), [_m("overclock")])
	t._check("P4 run: a socketed module lands in the run (Overclock +25% rate, -15% Core HP)", is_equal_approx(float(_core(O)["rate"]), 1.25 * 1.25) and is_equal_approx(float(O.stats["max_hp"]), 120.0 * 0.85))
	var sv: Dictionary = BaseMeta.default_save()
	var snap: String = JSON.stringify(sv)
	var R = TowerState.new()
	R.setup(1, sv)
	t._check("P4 run: setting up a run never writes the save's gear", JSON.stringify(sv) == snap)
	var bare: Dictionary = BaseMeta.default_save()
	bare.erase("gear")
	var B = TowerState.new()
	B.setup(1, bare)
	t._check("P4 run: a save without gear still fires the starter", String(_core(B)["attack"]) == "cannon" and not bare.has("gear"))


# ------------------------------------------------------------------ frames

static func _frames(t) -> void:
	var bad: Array = []
	var nokill: Array = []
	for id in FrameDB.IDS:
		var S = _run(_w(String(id)))
		_ready(S)
		var a: int = _body(S, TowerState.CENTER + Vector2(0, -100))
		var b: int = _body(S, TowerState.CENTER + Vector2(30, -110))
		var c: int = _body(S, TowerState.CENTER + Vector2(-25, -125))
		var ev: Array = _fire(S)
		var ca: Array = _evts(ev, "core_attack")
		var dealt: float = _lost(S, a) + _lost(S, b) + _lost(S, c)
		if ca.size() != 1 or String(ca[0]["kind"]) != String(FrameDB.get_def(String(id))["attack"]) or dealt <= 0.0 or _evts(ev, "shot").is_empty():
			bad.append("%s %s %.1f" % [id, ca, dealt])
		# field test: 8 weak bodies walking in die within 20 s of real ticks
		var F = _run(_w(String(id)))
		var ids: Array = []
		for k in 8:
			var e: int = _body(F, TowerState.CENTER + Vector2.from_angle(float(k) * TAU / 8.0) * 160.0, 10.0, "mite", 25.0)
			ids.append(int(F.en.eid[e]))
		F.eh.rebuild()
		for k in 400:
			F.tick(0.05)
		var alive: int = 0
		for eid in ids:
			if not F.enemy_dict(int(eid)).is_empty() and float(F.enemy_dict(int(eid)).get("hp", 0.0)) > 0.0:
				alive += 1
		if alive > 0:
			nokill.append("%s %d alive" % [id, alive])
	t._check("P4 frames: all 10 frames fire their own attack and damage bodies", bad.is_empty(), str(bad))
	t._check("P4 frames: every frame clears 8 weak bodies walking in within 20 s", nokill.is_empty(), str(nokill))
	var w20 = _run(_w("scatter"), [], 20)
	t._check("P4 frames: Core level 20 upgrades the new frames too (Scatter +2 pellets)", int(_core(w20)["pellets"]) == 8 and int(_core(_run(_w("missiles"), [], 20))["missiles"]) == 5 and int(_core(_run(_w("rail"), [], 20))["rail_n"]) == 14)


# ------------------------------------------------------------------ patterns

static func _patterns(t) -> void:
	var C = TowerState.CENTER
	# Scatter: pellets in a 40 deg cone at the target; a body square to the side is untouched.
	var S = _run(_w("scatter"))
	_ready(S)
	var front: int = _body(S, C + Vector2(0, -80))
	var side: int = _body(S, C + Vector2(90, 0))
	var ev: Array = _fire(S)
	var pel: Array = _evts(ev, "shot").filter(func(e: Variant) -> bool: return bool((e as Dictionary).get("pellet", false)))
	t._check("P4 Scatter: 6 pellets across the cone at the target; outside the cone is safe", pel.size() == 6 and _lost(S, front) > 0.0 and _lost(S, side) == 0.0)
	# Rail: through the line to the target, not beside it.
	var R = _run(_w("rail"))
	_ready(R)
	var r1: int = _body(R, C + Vector2(0, -60))
	var r2: int = _body(R, C + Vector2(2, -140))
	var r3: int = _body(R, C + Vector2(-2, -220))
	var roff: int = _body(R, C + Vector2(100, -10))
	_fire(R)
	t._check("P4 Rail Driver: one slug through every body on the line, no falloff; off the line is safe", is_equal_approx(_lost(R, r1), 30.0) and is_equal_approx(_lost(R, r2), 30.0) and is_equal_approx(_lost(R, r3), 30.0) and _lost(R, roff) == 0.0)
	# Arc: chains through bodies within 70 px, x0.8 per jump; a far body is safe.
	var A = _run(_w("arc"))
	_ready(A)
	var a1: int = _body(A, C + Vector2(0, -60))
	var a2: int = _body(A, C + Vector2(0, -120))
	var a3: int = _body(A, C + Vector2(0, -180))
	var afar: int = _body(A, C + Vector2(200, 60))
	_fire(A)
	t._check("P4 Arc Caster: chains 60 px hops at x0.8; shocks; a far body is safe", is_equal_approx(_lost(A, a1), 8.0) and is_equal_approx(_lost(A, a2), 6.4) and is_equal_approx(_lost(A, a3), 5.12) and _lost(A, afar) == 0.0 and A.en.shock_t[a2] > 0.0)
	# Flame: every body in the cone takes a hit and burns; behind is safe.
	var F = _run(_w("flame"))
	_ready(F)
	var f1: int = _body(F, C + Vector2(0, -70))
	var f2: int = _body(F, C + Vector2(20, -110))
	var fb: int = _body(F, C + Vector2(0, 90))
	_fire(F)
	t._check("P4 Flame Projector: the cone burns every body in it; behind the Core is safe", _lost(F, f1) > 0.0 and _lost(F, f2) > 0.0 and _lost(F, fb) == 0.0 and F.burning.size() == 2)
	# Missiles: 4 seekers at 4 different bodies.
	var M = _run(_w("missiles"))
	_ready(M)
	var mids: Array = []
	for k in 6:
		mids.append(_body(M, C + Vector2.from_angle(float(k) * TAU / 6.0) * (90.0 + 20.0 * float(k))))
	var mev: Array = _fire(M)
	var hit_n: int = 0
	for e in mids:
		hit_n += 1 if _lost(M, int(e)) >= 7.0 else 0
	t._check("P4 Swarm Missiles: 4 seekers, each at a different body (the nearest 4)", hit_n == 4 and _evts(mev, "shot").size() == 4 and _lost(M, int(mids[5])) == 0.0 and _lost(M, int(mids[4])) == 0.0)
	# Saw: ricochets through 5 bodies (x0.85 each) and shreds each.
	var W = _run(_w("saw"))
	_ready(W)
	var ws: Array = []
	for k in 6:
		ws.append(_body(W, C + Vector2(0, -60.0 - 60.0 * float(k))))
	_fire(W)
	var cut: int = 0
	for e in ws:
		cut += 1 if _lost(W, int(e)) > 0.0 else 0
	t._check("P4 Saw Launcher: ricochets through 5 bodies at x0.85 and shreds each", cut == 5 and is_equal_approx(_lost(W, int(ws[1])), 12.0 * 0.85) and W.en.shred_n[int(ws[0])] == 1 and _lost(W, int(ws[5])) == 0.0)


# ------------------------------------------------------------------ weapon fx

static func _fx_weapon(t) -> void:
	var C = TowerState.CENTER
	# multishot: Twin Feed fires a second volley at another body
	var S0 = _run(_w("autocannon"))
	var S1 = _run(_w("autocannon"), [_m("twin_feed")])
	t._check("P4 fx multishot: Twin Feed = 1 extra volley", int(_core(S1)["multishot"]) == 1 and int(_core(S0)["multishot"]) == 0)
	var mb: Array = []
	for S in [S0, S1]:
		_ready(S)
		mb.append([_body(S, C + Vector2(0, -80)), _body(S, C + Vector2(0, 160))])
	_fire(S0)
	_fire(S1)
	t._check("P4 fx multishot: one body hit without it, both with it", _lost(S0, mb[0][0]) > 0.0 and _lost(S0, mb[0][1]) == 0.0 and _lost(S1, mb[1][0]) > 0.0 and _lost(S1, mb[1][1]) > 0.0)
	var P1 = _run(_w("pulse"), [_m("twin_feed")])
	t._check("P4 fx multishot: on a Pulse Nova it adds a ring instead", int(_core(P1)["rings"]) == 2)
	# echo: the first volley again (50% here) - counts ~half of 200 shots
	var E = _run(_w("autocannon", [_p("w_echo", 7, 1.0)]))
	_ready(E)
	_body(E, C + Vector2(0, -80), 1.0e9)
	var echoes: int = 0
	for k in 200:
		echoes += _evts(_fire(E), "core_echo").size()
	t._check("P4 fx echo: the attack fires twice at its echo chance", is_equal_approx(float(_core(E)["echo"]), AffixDB.value("w_echo", 7, 1.0)) and echoes > int(200.0 * float(_core(E)["echo"]) * 0.5) and echoes < int(200.0 * float(_core(E)["echo"]) * 1.6) + 4, str(echoes))
	# bounce: Ricochet hits 2 more bodies at x0.7, x0.49
	var B = _run(_w("autocannon"), [_m("ricochet")])
	_ready(B)
	var b0: int = _body(B, C + Vector2(0, -80))
	var b1: int = _body(B, C + Vector2(0, -140))
	var b2: int = _body(B, C + Vector2(0, -200))
	_fire(B)
	t._check("P4 fx bounce: a hit bounces to 2 more bodies at x0.7 each", is_equal_approx(_lost(B, b0), 10.0) and is_equal_approx(_lost(B, b1), 7.0) and is_equal_approx(_lost(B, b2), 4.9))
	# burn + slow on hit
	var H = _run(_w("autocannon", [_p("w_burn")]), [_m("cryo_core")])
	_ready(H)
	var h0: int = _body(H, C + Vector2(0, -80))
	_fire(H)
	t._check("P4 fx burn / slow: Weapon hits ignite and slow", H.burning.has(h0) and is_equal_approx(H.en.burn_d[h0], 10.0 * float(H.core_burn)) and H.en.slow_t[h0] > 0.0 and H.en.slow_m[h0] < 1.0)
	var H0 = _run(_w("autocannon"))
	t._check("P4 fx: a quirk-free loadout has no on-hit hook (no per-hit cost)", not H0._core_hook)
	# execute: a non-boss pushed below the threshold dies
	var X = _run(_w("autocannon", [_p("w_execute", 5)]))
	_ready(X)
	var x0: int = _body(X, C + Vector2(0, -80))
	X.en.hp[x0] = 60.0
	var x1: int = _body(X, C + Vector2(0, -80) + Vector2(400, 400), 999.0)
	_fire(X)
	t._check("P4 fx execute: a hit leaving a body under the threshold kills it", float(X.core_exec) > 0.06 and X.en.hp[x0] <= 0.0 and _lost(X, x1) == 0.0)
	# crit damage, knockback
	var D = _run(_w("autocannon"), [_m("crit_lens")])
	t._check("P4 fx crit damage: Crit Lens raises the crit multiplier (x2 -> x2.3)", is_equal_approx(D.crit_mult(), 2.3) and is_equal_approx(_run(_w("autocannon")).crit_mult(), 2.0))
	var KN = _run(_w("autocannon"), [_m("kinetic_ram")])
	t._check("P4 fx knockback: Kinetic Ram +40% Weapon knockback", is_equal_approx(float(_core(KN)["knock_m"]), 1.4))


# ------------------------------------------------------------------ body fx

static func _fx_body(t) -> void:
	var base = _run(_w("autocannon"))
	var S = _run(_w("autocannon"), [_m("shield_gen"), _m("siphon")])
	t._check("P4 fx shield / lifesteal: Shield Generator +30 shield (and regen), Siphon +1% lifesteal", is_equal_approx(float(S.stats["shield_max"]) - float(base.stats["shield_max"]), 30.0) and float(S.stats["shield_regen"]) > float(base.stats["shield_regen"]) and is_equal_approx(float(S.stats["lifesteal"]) - float(base.stats["lifesteal"]), 0.01))
	var D = _run(_w("autocannon"), [_m("regen_cell", [_p("m_dr", 5, 0.5)])])
	t._check("P4 fx damage reduction: a Dampener perk cuts damage taken", is_equal_approx(float(D.stats["dr"]), AffixDB.value("m_dr", 5, 0.5)))
	D.hp = 100.0
	base.hp = 100.0
	D._core_damage(50.0, [], "core_hit", TowerState.CENTER)
	base._core_damage(50.0, [], "core_hit", TowerState.CENTER)
	t._check("P4 fx damage reduction: ... in the Core's damage intake", float(D.hp) > float(base.hp))
	var XP = _run(_w("autocannon"), [_m("learning_chip")])
	t._check("P4 fx XP: Learning Chip +10% run XP", is_equal_approx(float(XP.stats["xp_mult"]), float(base.stats["xp_mult"]) * 1.1))
	var CO = _run(_w("autocannon"), [_m("regen_cell", [_p("m_coin", 5, 0.5)])])
	t._check("P4 fx run coins: Golden Touch raises the run's coin multiplier", is_equal_approx(float(CO.coin_mult), float(base.coin_mult) * (1.0 + AffixDB.value("m_coin", 5, 0.5))))
	var SC = _run(_w("autocannon"), [_m("regen_cell", [_p("m_scrap", 7, 1.0)])])
	var bs: int = _body(SC, TowerState.CENTER + Vector2(0, -80), 999.0, "boss")
	var b0: int = _body(base, TowerState.CENTER + Vector2(0, -80), 999.0, "boss")
	SC._roll_drops(bs, [])
	base._roll_drops(b0, [])
	t._check("P4 fx Scrap find: Salvager raises boss Scrap", int(SC.loot["scrap"]) == int(round(float(base.loot["scrap"]) * (1.0 + AffixDB.value("m_scrap", 7, 1.0)))) and int(SC.loot["scrap"]) > int(base.loot["scrap"]))
	var LK = _run(_w("autocannon"), [_m("fortune_chip")])
	t._check("P4 fx luck: Fortune Chip +1 draft luck", int(LK.luck) == int(base.luck) + 1)
	var sv: Dictionary = BaseMeta.default_save()
	for id in ["shield_gen", "siphon"]:
		Gear.equip(sv, Gear.add_item(sv, _m(String(id))))
	((sv["gear"]["equipped"] as Dictionary)["sockets"] as Array).append(Gear.add_item(sv, _m("crit_lens")))   # a 3rd socket the Core hasn't opened
	var L1 = TowerState.new()
	L1.setup(1, sv)
	t._check("P4 fx: only the sockets the Core level has opened count (2 at L1)", is_equal_approx(L1.crit_mult(), 2.0) and float(L1.stats["shield_max"]) >= 30.0 and Gear.modules(sv).size() == 2)
	sv["core"]["lvl"] = 5
	var L5 = TowerState.new()
	L5.setup(1, sv)
	t._check("P4 fx: ... and Core L5 opens the 3rd", is_equal_approx(L5.crit_mult(), 2.3))


# ------------------------------------------------------------------ manual aim

static func _aim(t) -> void:
	var C = TowerState.CENTER
	var S = _run(_w("autocannon"))
	_ready(S)
	var near: int = _body(S, C + Vector2(0, -60))
	var far: int = _body(S, C + Vector2(200, 100))
	_fire(S)
	t._check("P4 aim: auto-fire takes the nearest body", _lost(S, near) > 0.0 and _lost(S, far) == 0.0)
	S.set_aim(C + Vector2(205, 95), true)
	var ev: Array = _fire(S)
	var sh: Array = _evts(ev, "shot")
	var ang: float = rad_to_deg(absf(((sh[0]["to"] as Vector2) - C).angle_to(Vector2(205, 95)))) if not sh.is_empty() else 99.0
	t._check("P4 aim: holding fire on a point shoots the body under the cursor (within 3 deg)", _lost(S, far) > 0.0 and ang < 3.0, "%.2f" % ang)
	S.set_aim(C + Vector2(-250, 0), true)
	var lost0: float = _lost(S, near)
	_fire(S)
	t._check("P4 aim: nothing under the cursor -> auto target", _lost(S, near) > lost0)
	var c0: int = 0
	var c1: int = 0
	var wd: Dictionary = _core(S)
	for k in 2000:
		S.aim_on = false
		c0 += 1 if S._roll_crit(wd) else 0
		S.aim_on = true
		c1 += 1 if S._roll_crit(wd) else 0
	t._check("P4 aim: +15% crit chance while aiming (Core only)", c0 == 0 and c1 > 230 and c1 < 370, "%d %d" % [c0, c1])
	var F = _run(_w("autocannon"))
	_ready(F)
	F.stats["crit"] = -1.0   # no crit noise in the damage literal
	F.set_aim(C, true)
	for k in 80:
		F._fire(0.05, [])
	t._check("P4 aim: the focus meter fills over 4 s", is_equal_approx(F.focus, 1.0))
	var fb: int = _body(F, C + Vector2(0, -80))
	F.set_aim(F.en.pos[fb], true)
	_fire(F)
	t._check("P4 aim: full focus = +30% damage", is_equal_approx(_lost(F, fb), 13.0))
	F.set_aim(C, false)
	for k in 31:
		F._fire(0.05, [])
	t._check("P4 aim: releasing drains focus within 1.5 s; auto-fire resumes", F.focus == 0.0 and not F.aim_on)
