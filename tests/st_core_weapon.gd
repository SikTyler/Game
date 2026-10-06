extends RefCounted
## P4b / V3 selftest stage: the Weapon (parts) in the run. The installed
## Barrel decides the Core's attack and sheet (damage x part power x the
## Receiver), every barrel fires its own pattern and kills, a Legendary+
## Receiver fires one barrel per sector, every part fx key changes the run
## the way its text says, and manual aim retargets the Core (+crit, focus).
## `t` is the selftest runner (t._check).

const TowerState := preload("res://TowerState.gd")
const Parts := preload("res://Parts.gd")
const PartDB := preload("res://data/PartDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const AffixDB := preload("res://data/AffixDB.gd")


static func run(t) -> void:
	_sheet(t)
	_frames(t)
	_patterns(t)
	_multi(t)
	_fx_weapon(t)
	_fx_body(t)
	_aim(t)
	_threat(t)


## A save with `barrel` as barrel 0 and `parts` installed; chassis
## (Receiver / Heart) parts in `parts` go in first so their slots open.
static func _save(barrel: Dictionary, parts: Array = [], lvl: int = 1) -> Dictionary:
	var sv: Dictionary = BaseMeta.default_save()
	sv["core"]["lvl"] = lvl
	for m in parts:
		if PartDB.is_chassis(String((m as Dictionary)["slot"])):
			Parts.equip(sv, Parts.add_item(sv, m))
	Parts.equip(sv, Parts.add_item(sv, barrel), 0)
	for m in parts:
		if not PartDB.is_chassis(String((m as Dictionary)["slot"])):
			Parts.equip(sv, Parts.add_item(sv, m))
	return sv


## A run with that loadout, every cell open, no waves.
static func _run(barrel: Dictionary, parts: Array = [], lvl: int = 1):
	var S = TowerState.new()
	S.setup(1234, BaseMeta.normalize(_save(barrel, parts, lvl)))
	for i in TowerState.N:
		S.unlocked[i] = not TowerState.is_core_cell(i)
	S.spawn_hold = true
	return S


## A barrel part (`base` is a PartDB barrel, or a FrameDB frame id).
static func _w(base: String, perks: Array = [], rar: String = "common", lvl: int = 1) -> Dictionary:
	return Parts.make(base if PartDB.has(base) else _barrel_of(base), rar, lvl, perks)


static func _barrel_of(frame: String) -> String:
	for b in PartDB.bases_of("barrel"):
		if String(PartDB.get_def(String(b))["frame"]) == frame and not (PartDB.get_def(String(b)) as Dictionary).has("sheet"):
			return String(b)
	return "brl_autocannon"


## Any other part.
static func _m(base: String, perks: Array = [], rar: String = "common") -> Dictionary:
	return Parts.make(base, rar, 1, perks)


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
	var hp0: float = float(CoreDB.get_def()["hp"])
	t._check("P4 run: a fresh save fires the starter Autocannon Barrel = the base Core sheet", String(cw["attack"]) == "cannon" and is_equal_approx(float(cw["dmg"]), 10.0) and is_equal_approx(float(cw["rate"]), 1.25) and is_equal_approx(float(cw["range"]), 4.0 * TowerState.cpx()) and S.pfx.is_empty() and String(S.core_def["attack_name"]) == "Autocannon Barrel")
	t._check("P4 run: the Core's body stays the CoreDB sheet (starter Heart)", is_equal_approx(float(S.stats["max_hp"]), hp0) and is_equal_approx(float(S.stats["cash_ps"]), float(CoreDB.get_def()["cash"])))
	var L = _run(_w("lance", [], "rare", 5))
	var lw: Dictionary = _core(L)
	t._check("P4 run: the installed barrel decides the attack; damage x part power", String(lw["attack"]) == "beam" and is_equal_approx(float(lw["dmg"]), 28.0 * 1.28 * 1.2 * 1.06) and is_equal_approx(float(lw["rate"]), 0.5) and is_equal_approx(float(lw["range"]), 5.5 * TowerState.cpx()))
	var K = _run(_w("autocannon"), [_m("rcv_heavy")])
	t._check("V3 run: the Receiver scales the barrel (Heavy: x1.2 dmg, x0.85 rate)", is_equal_approx(float(_core(K)["dmg"]), 12.0) and is_equal_approx(float(_core(K)["rate"]), 1.25 * 0.85))
	var O = _run(_w("autocannon"), [_m("rcv_overdrive")])
	t._check("V3 run: a Receiver's own fx lands in the run (Overdrive x1.1 dmg / rate, -8% Core HP)", is_equal_approx(float(_core(O)["dmg"]), 11.0) and is_equal_approx(float(_core(O)["rate"]), 1.25 * 1.1) and is_equal_approx(float(O.stats["max_hp"]), hp0 * 0.92))
	var U = _run(_w("autocannon"), [_m("rcv_standard", [], "rare")])
	t._check("V3 run: a rarer Receiver adds half its power to the barrel (Rare: x1.14)", is_equal_approx(float(_core(U)["dmg"]), 10.0 * (0.5 + 0.5 * 1.28)))
	var H = _run(_w("autocannon"), [_m("hrt_fortress")])
	t._check("V3 run: the Heart scales the Core body (Fortress: HP x1.25, regen x0.8)", is_equal_approx(float(H.stats["max_hp"]), hp0 * 1.25) and is_equal_approx(float(H.core_def["regen"]), float(CoreDB.get_def()["regen"]) * 0.8))
	var HE = _run(_w("autocannon"), [_m("hrt_standard", [], "epic")])
	t._check("V3 run: a rarer Heart raises HP by 15% of its power (Epic: x1.072)", is_equal_approx(float(HE.stats["max_hp"]), hp0 * (0.85 + 0.15 * 1.48)))
	var sv: Dictionary = BaseMeta.default_save()
	var snap: String = JSON.stringify(sv)
	var R = TowerState.new()
	R.setup(1, sv)
	t._check("P4 run: setting up a run never writes the save's parts", JSON.stringify(sv) == snap)
	var bare: Dictionary = BaseMeta.default_save()
	bare.erase("parts")
	var B = TowerState.new()
	B.setup(1, bare)
	t._check("P4 run: a save without parts still fires the starter", String(_core(B)["attack"]) == "cannon" and not bare.has("parts"))


# ------------------------------------------------------------------ frames

static func _frames(t) -> void:
	var bad: Array = []
	var nokill: Array = []
	for id in PartDB.bases_of("barrel"):
		var atk: String = String(FrameDB.get_def(String(PartDB.get_def(String(id))["frame"]))["attack"])
		var S = _run(_w(String(id)))
		_ready(S)
		var a: int = _body(S, TowerState.CENTER + Vector2(0, -100))
		var b: int = _body(S, TowerState.CENTER + Vector2(30, -110))
		var c: int = _body(S, TowerState.CENTER + Vector2(-25, -125))
		var ev: Array = _fire(S)
		var ca: Array = _evts(ev, "core_attack")
		var dealt: float = _lost(S, a) + _lost(S, b) + _lost(S, c)
		if ca.size() != 1 or String(ca[0]["kind"]) != atk or dealt <= 0.0 or _evts(ev, "shot").is_empty():
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
	t._check("V3 barrels: all %d barrels fire their frame's attack and damage bodies" % PartDB.bases_of("barrel").size(), bad.is_empty(), str(bad))
	t._check("V3 barrels: every barrel clears 8 weak bodies walking in within 20 s", nokill.is_empty(), str(nokill))
	var w20 = _run(_w("scatter"), [], 20)
	t._check("P4 frames: Core level 20 upgrades the barrels too (Scatter +2 pellets)", int(_core(w20)["pellets"]) == 8 and int(_core(_run(_w("missiles"), [], 20))["missiles"]) == 5 and int(_core(_run(_w("rail"), [], 20))["rail_n"]) == 14)


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


# ------------------------------------------------------------------ V3 multi-barrel + variants

## Keep only the Core's barrels firing; cooldowns ready.
static func _ready_all(S) -> void:
	S.stats["weapons"] = (S.stats["weapons"] as Array).filter(func(w: Variant) -> bool: return int((w as Dictionary)["slot"]) == TowerState.CORE_SLOT)
	for k in TowerState.N:
		S.cooldowns[k] = 0.0
	S.barrel_cd = [0.0, 0.0, 0.0, 0.0]


static func _fire_all(S) -> Array:
	S.eh.rebuild()
	for k in TowerState.N:
		S.cooldowns[k] = 0.0
	S.barrel_cd = [0.0, 0.0, 0.0, 0.0]
	var ev: Array = []
	S._fire(0.01, ev)
	return ev


static func _multi(t) -> void:
	var C = TowerState.CENTER
	# the Receiver's rarity decides how many barrels it holds
	var lay: Array = []
	for r in ["common", "epic", "legendary", "mythic", "exotic"]:
		lay.append(int(PartDB.layout("receiver", String(r))["barrel"]))
	t._check("V3 layout: barrels by Receiver rarity: Common-Epic 1, Legendary 2, Mythic 3, Exotic 4", lay == [1, 1, 2, 3, 4], str(lay))
	# a Legendary Receiver with a 2nd barrel: two Core weapons, barrel 0 last
	var sv: Dictionary = _save(_w("autocannon"), [_m("rcv_standard", [], "legendary")])
	var b2: int = Parts.add_item(sv, _w("rail"))
	Parts.equip(sv, b2)
	var S = TowerState.new()
	S.setup(1234, BaseMeta.normalize(sv))
	S.spawn_hold = true
	var cws: Array = (S.stats["weapons"] as Array).filter(func(w: Variant) -> bool: return int((w as Dictionary)["slot"]) == TowerState.CORE_SLOT)
	t._check("V3 multi-barrel: each barrel is its own Core weapon (barrel 0 last, each with its own attack)", cws.size() == 2 and int((cws.back() as Dictionary)["barrel"]) == 0 and String((cws.back() as Dictionary)["attack"]) == "cannon" and String((cws[0] as Dictionary)["attack"]) == "rail" and int((cws[0] as Dictionary)["nbarrels"]) == 2)
	t._check("V3 multi-barrel: the Core sheet lists every barrel; the name is the Receiver's", (S.core_def["barrels"] as Array).size() == 2 and String(S.core_def["attack_name"]) == String(Parts.equipped(sv, "receiver")[0]["name"]))
	_ready_all(S)
	var north: int = _body(S, C + Vector2(0, -80))
	var south: int = _body(S, C + Vector2(0, 150))
	var ev: Array = _fire_all(S)
	_fire_all(S)   # barrel 1 aims opposite barrel 0's last target
	t._check("V3 multi-barrel: two barrels cover opposite sectors (a body behind the Core is hit too)", _lost(S, north) > 0.0 and _lost(S, south) > 0.0 and _evts(ev, "core_attack").size() >= 1, "%.1f %.1f" % [_lost(S, north), _lost(S, south)])
	var one = _run(_w("autocannon"))
	_ready(one)
	var n1: int = _body(one, C + Vector2(0, -80))
	var s1: int = _body(one, C + Vector2(0, 150))
	_fire(one)
	_fire(one)
	t._check("V3 multi-barrel: ... while one barrel only takes the nearest", _lost(one, n1) > 0.0 and _lost(one, s1) == 0.0)
	# an extra barrel with nothing in its sector holds fire
	var sv2: Dictionary = _save(_w("autocannon"), [_m("rcv_standard", [], "legendary")])
	Parts.equip(sv2, Parts.add_item(sv2, _w("autocannon")))
	var Q = TowerState.new()
	Q.setup(1234, BaseMeta.normalize(sv2))
	Q.spawn_hold = true
	_ready_all(Q)
	_body(Q, C + Vector2(0, -80))
	_body(Q, C + Vector2(20, -100))
	_fire_all(Q)
	var qa: Array = _evts(_fire_all(Q), "core_attack")
	t._check("V3 multi-barrel: an extra barrel with nothing in its own sector holds fire", qa.size() == 1, str(qa.size()))
	# Minigun: light rounds spread over the nearest 3 around the target
	var M = _run(_w("brl_minigun"))
	_ready(M)
	var m0: int = _body(M, C + Vector2(0, -80))
	var m1: int = _body(M, C + Vector2(15, -90))
	var m2: int = _body(M, C + Vector2(-15, -92))
	var mfar: int = _body(M, C + Vector2(0, -200))
	for k in 40:
		_fire(M)
	t._check("V3 Minigun: rounds spread over the nearest 3 bodies; a body 110 px past them is untouched", _lost(M, m0) > 0.0 and _lost(M, m1) > 0.0 and _lost(M, m2) > 0.0 and _lost(M, mfar) == 0.0)
	t._check("V3 Minigun: 6 rounds a second, 2.6 each (x part power)", is_equal_approx(float(_core(M)["rate"]), 6.0) and is_equal_approx(float(_core(M)["dmg"]), 2.6))
	# variants re-tune their frame
	var BC = _run(_w("brl_burst"))
	t._check("V3 Burst Carbine: an Autocannon variant firing 3 rounds at x0.45, no splash", String(_core(BC)["attack"]) == "cannon" and int(_core(BC)["barrels"]) == 3 and is_equal_approx(float(_core(BC)["dmg"]), 4.5) and float(_core(BC)["splash"]) == 0.0)
	var CO = _run(_w("brl_coil"))
	t._check("V3 Coilgun: a Rail variant, x2.6 rate, pierces 4", String(_core(CO)["attack"]) == "rail" and int(_core(CO)["rail_n"]) == 4 and is_equal_approx(float(_core(CO)["rate"]), 0.4 * 2.6))
	var MO = _run(_w("brl_mortar"))
	t._check("V3 Siege Mortar: a Slag variant, x3.2 dmg, x1.6 range, wide blast", String(_core(MO)["attack"]) == "slag" and is_equal_approx(float(_core(MO)["dmg"]), 16.0) and is_equal_approx(float(_core(MO)["range"]), 3.5 * 1.6 * TowerState.cpx()) and float(_core(MO)["splash"]) > 1.5 * TowerState.cpx())
	var FR = _run(_w("brl_frost"))
	t._check("V3 Frost Projector: a Flame cone that slows and never burns", float(_core(FR)["flame_burn"]) == 0.0 and float(FR.core_slow) > 0.0)


# ------------------------------------------------------------------ weapon fx

static func _fx_weapon(t) -> void:
	var C = TowerState.CENTER
	# echo: a barrel perk fires the volley again at its chance
	var E = _run(_w("autocannon", [_p("w_echo", 7, 1.0)]))
	_ready(E)
	_body(E, C + Vector2(0, -80), 1.0e9)
	var echoes: int = 0
	for k in 200:
		echoes += _evts(_fire(E), "core_echo").size()
	t._check("P4 fx echo: the attack fires twice at its echo chance", is_equal_approx(float(_core(E)["echo"]), AffixDB.value("w_echo", 7, 1.0)) and echoes > int(200.0 * float(_core(E)["echo"]) * 0.5) and echoes < int(200.0 * float(_core(E)["echo"]) * 1.6) + 4, str(echoes))
	# bounce: Ricochet Rounds hit 1 more body at x0.7
	var B = _run(_w("autocannon"), [_m("amm_ricochet")])
	_ready(B)
	var b0: int = _body(B, C + Vector2(0, -80))
	var b1: int = _body(B, C + Vector2(0, -140))
	var b2: int = _body(B, C + Vector2(0, -200))
	_fire(B)
	t._check("V3 ammo: Ricochet Rounds bounce a hit to 1 more body at x0.7", is_equal_approx(_lost(B, b0), 10.0) and is_equal_approx(_lost(B, b1), 7.0) and _lost(B, b2) == 0.0)
	# burn (barrel perk) + slow (Cryo Rounds)
	var H = _run(_w("autocannon", [_p("w_burn")]), [_m("amm_cryo")])
	_ready(H)
	var h0: int = _body(H, C + Vector2(0, -80))
	_fire(H)
	t._check("P4 fx burn / slow: hits ignite (perk) and slow (Cryo Rounds)", H.burning.has(h0) and is_equal_approx(H.en.burn_d[h0], 10.0 * float(H.core_burn)) and H.en.slow_t[h0] > 0.0 and H.en.slow_m[h0] < 1.0)
	var H0 = _run(_w("autocannon"))
	t._check("P4 fx: a plain loadout has no on-hit hook (no per-hit cost)", not H0._core_hook)
	# execute: a non-boss pushed below the threshold dies
	var X = _run(_w("autocannon", [_p("w_execute", 5)]))
	_ready(X)
	var x0: int = _body(X, C + Vector2(0, -80))
	X.en.hp[x0] = 60.0
	var x1: int = _body(X, C + Vector2(0, -80) + Vector2(400, 400), 999.0)
	_fire(X)
	t._check("P4 fx execute: a hit leaving a body under the threshold kills it", float(X.core_exec) > 0.06 and X.en.hp[x0] <= 0.0 and _lost(X, x1) == 0.0)
	# crit damage (Hollow Points), knockback (Muzzle Brake on a Rare Receiver)
	var D = _run(_w("autocannon"), [_m("amm_hollow")])
	t._check("V3 ammo: Hollow Points raise the crit multiplier (x2 -> x2.3)", is_equal_approx(D.crit_mult(), 2.3) and is_equal_approx(_run(_w("autocannon")).crit_mult(), 2.0))
	var KN = _run(_w("autocannon"), [_m("rcv_standard", [], "rare"), _m("mzl_brake")])
	t._check("V3 muzzle: a Muzzle Brake +20% Weapon knockback (needs a Rare Receiver's muzzle slot)", is_equal_approx(float(_core(KN)["knock_m"]), 1.2))
	# scope range on an Uncommon Receiver
	var SC = _run(_w("autocannon"), [_m("rcv_standard", [], "uncommon"), _m("scp_long")])
	t._check("V3 scope: a Long Optic +0.5 cells range", is_equal_approx(float(_core(SC)["range"]), 4.5 * TowerState.cpx()))
	# power cell on a Rare Receiver vs the same Receiver bare
	var PR0 = _run(_w("autocannon"), [_m("rcv_standard", [], "rare")])
	var PR = _run(_w("autocannon"), [_m("rcv_standard", [], "rare"), _m("pow_overclock")])
	t._check("V3 power: an Overclock Cell +15% rate", is_equal_approx(float(_core(PR)["rate"]), float(_core(PR0)["rate"]) * 1.15))
	# armor-piercing rounds: +1 pierce
	var AP = _run(_w("autocannon"), [_m("amm_ap")])
	t._check("V3 ammo: Armor-Piercing Rounds +1 pierce and armor shred", int(_core(AP)["pierce"]) == 1 and float(AP.stats["shred"]) > 0.0)
	# part fx cover the whole Weapon: a perk on a barrel buffs every barrel
	var sv: Dictionary = _save(_w("autocannon", [_p("w_dmg", 3, 0.5)]), [_m("rcv_standard", [], "legendary")])
	Parts.equip(sv, Parts.add_item(sv, _w("autocannon")))
	var W2 = TowerState.new()
	W2.setup(1, BaseMeta.normalize(sv))
	var cws: Array = (W2.stats["weapons"] as Array).filter(func(w: Variant) -> bool: return int((w as Dictionary)["slot"]) == TowerState.CORE_SLOT)
	t._check("V3 fx: part fx apply to the whole Weapon (a barrel's perk buffs both barrels)", cws.size() == 2 and is_equal_approx(float((cws[0] as Dictionary)["dmg"]), float((cws[1] as Dictionary)["dmg"])) and float((cws[0] as Dictionary)["dmg"]) > 10.0 * (0.5 + 0.5 * 1.72))
	# multishot is gone from parts (owner: "remove multishot")
	t._check("V3 fx: Twin Feed (multishot) never rolls on a part", not Parts.perk_pool("weapon").has("w_multishot") and int(_core(H0)["multishot"]) == 0)


# ------------------------------------------------------------------ body fx

static func _fx_body(t) -> void:
	var base = _run(_w("autocannon"))
	var S = _run(_w("autocannon"), [_m("gen_shield"), _m("amm_siphon")])
	t._check("V3 fx shield / lifesteal: a Shield Generator +25 shield (and shield regen), Siphon Rounds +0.2% lifesteal", is_equal_approx(float(S.stats["shield_max"]) - float(base.stats["shield_max"]), 25.0) and float(S.stats["shield_regen"]) > float(base.stats["shield_regen"]) and is_equal_approx(float(S.stats["lifesteal"]) - float(base.stats["lifesteal"]), 0.002))
	var D = _run(_w("autocannon"), [_m("plt_basic", [_p("m_dr", 5, 0.5)])])
	t._check("P4 fx damage reduction: a Dampener perk cuts damage taken", is_equal_approx(float(D.stats["dr"]), AffixDB.value("m_dr", 5, 0.5)))
	D.hp = 100.0
	base.hp = 100.0
	D._core_damage(50.0, [], "core_hit", TowerState.CENTER)
	base._core_damage(50.0, [], "core_hit", TowerState.CENTER)
	t._check("P4 fx damage reduction: ... in the Core's damage intake", float(D.hp) > float(base.hp))
	var PL = _run(_w("autocannon"), [_m("plt_basic"), _m("gen_basic")])
	t._check("V3 plating / generator: Steel Plating +10% HP, Repair Generator +15% regen", is_equal_approx(float(PL.stats["max_hp"]), float(base.stats["max_hp"]) * 1.1) and is_equal_approx(float(PL.stats["regen"]), float(base.stats["regen"]) * 1.15))
	var XP = _run(_w("autocannon"), [_m("hrt_scholar")])
	t._check("V3 heart: a Scholar Heart +8% run XP", is_equal_approx(float(XP.stats["xp_mult"]), float(base.stats["xp_mult"]) * 1.08))
	var CO = _run(_w("autocannon"), [_m("plt_basic", [_p("m_coin", 5, 0.5)])])
	t._check("P4 fx run coins: Golden Touch raises the run's coin multiplier", is_equal_approx(float(CO.coin_mult), float(base.coin_mult) * (1.0 + AffixDB.value("m_coin", 5, 0.5))))
	var SC = _run(_w("autocannon"), [_m("plt_basic", [_p("m_scrap", 7, 1.0)])])
	var bs: int = _body(SC, TowerState.CENTER + Vector2(0, -80), 999.0, "boss")
	var b0: int = _body(base, TowerState.CENTER + Vector2(0, -80), 999.0, "boss")
	SC._roll_drops(bs, [])
	base._roll_drops(b0, [])
	t._check("P4 fx Scrap find: Salvager raises boss Scrap", int(SC.loot["scrap"]) == int(round(float(base.loot["scrap"]) * (1.0 + AffixDB.value("m_scrap", 7, 1.0)))) and int(SC.loot["scrap"]) > int(base.loot["scrap"]))
	var LK = _run(_w("autocannon"), [_m("hrt_standard", [], "epic"), _m("ant_draft")])
	t._check("V3 antenna: a Scout Antenna +1 draft luck (needs an Epic Heart's antenna slot)", int(LK.luck_now()) == int(base.luck_now()) + 1)
	var CA = _run(_w("autocannon"), [_m("hrt_standard", [], "uncommon"), _m("cap_basic")])
	var CA0 = _run(_w("autocannon"), [_m("hrt_standard", [], "uncommon")])
	t._check("V3 capacitor: a Cash Capacitor +10% Core cash", is_equal_approx(float(CA.stats["cash_ps"]), float(CA0.stats["cash_ps"]) * 1.1))
	# only the slots the chassis opens count
	var sv: Dictionary = BaseMeta.default_save()
	var cu: int = Parts.add_item(sv, _m("cap_basic"))
	var why: String = Parts.why_equip(sv, cu)
	((sv["parts"]["equipped"] as Dictionary)["capacitor"] as Array).append(cu)   # forced into a slot a Common Heart lacks
	var L1 = TowerState.new()
	L1.setup(1, sv)
	t._check("V3 slots: a Common Heart has no Capacitor slot (install refused, a forced one does nothing)", why.contains("rarer Heart") and is_equal_approx(float(L1.stats["cash_ps"]), float(base.stats["cash_ps"])) and Parts.equipped(sv, "capacitor").is_empty())
	Parts.equip(sv, Parts.add_item(sv, _m("hrt_standard", [], "uncommon")))
	var L5 = TowerState.new()
	L5.setup(1, sv)
	t._check("V3 slots: ... an Uncommon Heart opens it", Parts.equipped(sv, "capacitor").size() == 1 and float(L5.stats["cash_ps"]) > float(base.stats["cash_ps"]))


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


# ------------------------------------------------------------------ threat priority (V2 P9)

static func _threat(t) -> void:
	var C = TowerState.CENTER
	var S = _run(_w("autocannon"))
	_ready(S)
	var mite: int = _body(S, C + Vector2(0, -46))
	var el: int = _body(S, C + Vector2(0, 52), 999.0, "elite")
	S.en.flags[el] = S.en.flags[el] | 4   # EnemyStore.F_LEAK: it reached the Core
	_fire(S)
	t._check("P9 threat: auto-fire takes an Elite gnawing on the Core over a nearer body", _lost(S, el) > 0.0 and _lost(S, mite) == 0.0)
	var A = _run(_w("autocannon"))
	_ready(A)
	var am: int = _body(A, C + Vector2(0, -46))
	var ae: int = _body(A, C + Vector2(0, 120), 999.0, "elite")
	_fire(A)
	t._check("P9 threat: an Elite still walking in waits its turn (nearest first)", _lost(A, am) > 0.0 and _lost(A, ae) == 0.0)
	var B = _run(_w("autocannon"))
	_ready(B)
	var bm: int = _body(B, C + Vector2(0, -60))
	var sp: int = _body(B, C + Vector2(230, 0), 999.0, "ranged")
	_fire(B)
	var s1: float = _lost(B, sp)
	_fire(B)
	t._check("P9 threat: every other auto volley takes the Spitter at the stand-off ring", s1 > 0.0 and _lost(B, sp) == s1 and _lost(B, bm) > 0.0, "%.1f %.1f" % [s1, _lost(B, bm)])
	var M = _run(_w("autocannon"))
	_ready(M)
	var mm: int = _body(M, C + Vector2(150, 0))
	var me: int = _body(M, C + Vector2(0, 52), 999.0, "elite")
	M.en.flags[me] = M.en.flags[me] | 4
	M.set_aim(M.en.pos[mm], true)
	_fire(M)
	t._check("P9 threat: manual aim overrides the threat priority", _lost(M, mm) > 0.0 and _lost(M, me) == 0.0)
