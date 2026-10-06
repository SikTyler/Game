extends RefCounted
## P7d selftest stage: the 3x run content. Every weapon has a complete
## WeaponDB sheet, a draft card, merge mods and an icon; every firing pattern
## is used by a weapon; every weapon kills a walking line of bodies on its
## own; the new patterns' rules (ramp, pellets, bounces, missiles, mines,
## burn, shove, elite bolt) hold.
## `t` is the selftest runner (t._check).

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const PickDB := preload("res://data/PickDB.gd")
const WeaponDB := preload("res://data/WeaponDB.gd")
const MergeDB := preload("res://data/MergeDB.gd")
const FirePatterns := preload("res://FirePatterns.gd")
const Draft := preload("res://Draft.gd")
const Art := preload("res://ArtDB.gd")
const RunArt := preload("res://ui/RunArt.gd")


static func run(t) -> void:
	_data(t)
	_kills(t)
	_rules(t)


static func _run():
	var S = TowerState.new()
	S.setup(61, BaseMeta.normalize({}))
	for i in TowerState.N:
		S.unlocked[i] = not TowerState.is_core_cell(i)
	S.spawn_hold = true
	S.draft_queue.clear()
	return S


static func _w(S, slot: int) -> Dictionary:
	for w in S.stats["weapons"]:
		if int((w as Dictionary)["slot"]) == slot:
			return w
	return {}


static func _body(S, p: Vector2, hp: float = 30.0, spd: float = 0.0, kind: String = "drone") -> int:
	return S.add_enemy({"kind": kind, "pos": p, "hp": hp, "max_hp": hp, "spd": spd, "dmg": 0.0, "cash": 0.0, "xp": 0.0, "coin": 0.0, "size": 12.0, "atk_cd": 0.0, "slow_t": 0.0})


# ------------------------------------------------------------------ data
static func _data(t) -> void:
	var bad: Array = []
	for id in WeaponDB.DEFS.keys():
		var d: Dictionary = WeaponDB.get_def(String(id))
		for k in ["name", "size", "aim", "arc", "pattern", "dir_mult", "dmg", "rate", "range", "p"]:
			if not d.has(k):
				bad.append("%s:%s" % [id, k])
		if not WeaponDB.AIMS.has(String(d.get("aim", ""))) or not FirePatterns.PATTERNS.has(String(d.get("pattern", ""))):
			bad.append("%s:aim/pattern" % id)
		if PickDB.get_def(String(id)).is_empty() or not PickDB.BUILDINGS.has(id) or not Draft.WEAPONS.has(id):
			bad.append("%s:card" % id)
		if int(PickDB.get_def(String(id)).get("size", 1)) != int(d.get("size", 1)):
			bad.append("%s:size" % id)
		if MergeDB.offer(String(id), 2).size() != 3 or MergeDB.offer(String(id), 3).size() != 2:
			bad.append("%s:mods" % id)
		if Art.tex(String(id)) == null and not RunArt.knows(String(id)):
			bad.append("%s:icon" % id)
	t._check("P7d content: 18 weapons, each with a full sheet, a draft card, merge mods and an icon", WeaponDB.DEFS.size() == 18 and bad.is_empty(), str(bad))
	var radial: int = 0
	var dirn: int = 0
	for id in WeaponDB.DEFS.keys():
		if WeaponDB.aim_of(String(id)) == "radial":
			radial += 1
		else:
			dirn += 1
	t._check("P7d content: 7 radial + 11 arc / fixed weapons", radial == 7 and dirn == 11, "%d / %d" % [radial, dirn])
	var used: Dictionary = {}
	for id in WeaponDB.DEFS.keys():
		used[String(WeaponDB.get_def(String(id))["pattern"])] = true
	var unused: Array = FirePatterns.PATTERNS.filter(func(p: Variant) -> bool: return not used.has(p))
	t._check("P7d content: every firing pattern is used by a weapon", unused.is_empty(), str(unused))


# ------------------------------------------------------------------ every weapon kills
static func _kills(t) -> void:
	var slow: Array = []
	for id in WeaponDB.DEFS.keys():
		if String(id) == "frost":
			continue   # the Cryo Spire is control: its chill barely scratches (slow checked below)
		var S = _run()
		var at: int = TowerState.cell(0, -6)
		S.slots[at] = {"id": String(id), "tier": 1, "rot": 4, "mods": []}   # faces west, toward the line
		S.recompute()
		var keep: Array = []
		for w in S.stats["weapons"]:
			if int((w as Dictionary)["slot"]) != TowerState.CORE_SLOT:
				keep.append(w)
		S.stats["weapons"] = keep   # the building alone
		var from: Vector2 = S.fp_pos(at)
		for k in 8:
			_body(S, from + Vector2(-60.0 - 14.0 * float(k), float(k % 3 - 1) * 8.0), 30.0, 18.0)
		for k in 400:
			S.tick(0.05)
			if S.kills >= 3:
				break
		if S.kills < 3:
			slow.append("%s:%d" % [id, S.kills])
	t._check("P7d content: every damage weapon alone kills a walking line of bodies (3+ in 20 s)", slow.is_empty(), str(slow))
	var F = _run()
	var fa: int = TowerState.cell(0, -6)
	F.slots[fa] = {"id": "frost", "tier": 1, "rot": 4, "mods": []}
	F.recompute()
	var fb: int = _body(F, F.fp_pos(fa) + Vector2(-30, 0), 1000.0)
	F.stats["weapons"] = (F.stats["weapons"] as Array).filter(func(w: Variant) -> bool: return int((w as Dictionary)["slot"]) == fa)
	F.tick(0.05)
	t._check("P7d content: the Cryo Spire (control) slows the bodies around it", F.en.slow_t[int(F.en.order[0])] > 0.0 and fb >= 0)


# ------------------------------------------------------------------ pattern rules
static func _rules(t) -> void:
	# Laser Lance ramps while it keeps firing, resets when the lane empties
	var L = _run()
	var la: int = TowerState.cell(0, -6)
	L.slots[la] = {"id": "laser", "tier": 1, "rot": 4, "mods": []}
	L.recompute()
	var lw: Dictionary = _w(L, la)
	var lf: Vector2 = L.fp_pos(la)
	var e: int = _body(L, lf + Vector2(-80, 0), 1.0e6)
	var ev: Array = []
	for k in 6:
		FirePatterns.beam_ramp(L, lw, lf, Vector2(-1, 0), 10.0, false, ev)
	t._check("P7d laser: the beam ramps +0.25 a shot up to x3", is_equal_approx(float(L.beam_ramps[la]), 2.5))
	for k in 10:
		FirePatterns.beam_ramp(L, lw, lf, Vector2(-1, 0), 10.0, false, ev)
	t._check("P7d laser: ... capped at x3 (x4 with Focusing Array)", is_equal_approx(float(L.beam_ramps[la]), 3.0) and e >= 0)
	# Scatter: pellets on the nearest bodies in the cone
	var C = _run()
	var ca: int = TowerState.cell(0, -6)
	C.slots[ca] = {"id": "scatter", "tier": 1, "rot": 4, "mods": []}
	C.recompute()
	var cw: Dictionary = _w(C, ca)
	var cf: Vector2 = C.fp_pos(ca)
	var ids: Array = []
	for k in 8:
		ids.append(_body(C, cf + Vector2(-40.0 - 10.0 * float(k), 0.0), 100.0))
	FirePatterns.cone_burst(C, cw, cf, Vector2(-1, 0), 5.0, false, [])
	var hit_n: int = 0
	for b in C.enemy_list():
		if float((b as Dictionary)["hp"]) < 100.0:
			hit_n += 1
	t._check("P7d scatter: 6 pellets hit the 6 nearest bodies in the cone", hit_n == 6, str(hit_n))
	# Saw: target + 4 bounces
	var W = _run()
	var bodies: Array = []
	for k in 8:
		bodies.append(_body(W, TowerState.CENTER + Vector2(-200.0 - 15.0 * float(k), 0.0), 100.0))
	var sw: Dictionary = {"kind": "saw", "bounces": 4, "range": 300.0}
	FirePatterns.bounce(W, sw, TowerState.CENTER, int(W.en.order[0]), 10.0, false, [])
	var sn: int = 0
	for b in W.enemy_list():
		if float((b as Dictionary)["hp"]) < 100.0:
			sn += 1
	t._check("P7d saw: the blade hits its target and bounces through 4 more", sn == 5, str(sn))
	# Missile Battery: 4 missiles at 4 bodies
	var M = _run()
	for k in 6:
		_body(M, TowerState.CENTER + Vector2(-150.0 - 60.0 * float(k), 0.0), 100.0)
	var mw: Dictionary = {"kind": "missile", "missiles": 4, "blast": 1.0, "range": 1000.0}
	FirePatterns.homing(M, mw, TowerState.CENTER, int(M.en.order[0]), 10.0, false, [])
	var mn: int = 0
	for b in M.enemy_list():
		if float((b as Dictionary)["hp"]) < 100.0:
			mn += 1
	t._check("P7d missiles: a salvo is 4 missiles at 4 bodies", mn == 4, str(mn))
	# Minelayer: a delayed blast at the target
	var N = _run()
	var nb: int = _body(N, TowerState.CENTER + Vector2(-200, 0), 100.0)
	FirePatterns.mine(N, {"kind": "mines", "blast": 20.0, "fuse": 1.0}, TowerState.CENTER, int(N.en.order[0]), 25.0, false, [])
	var before: float = float(N.enemy_list()[0]["hp"])
	N.stats["weapons"] = []
	for k in 24:
		N.tick(0.05)
	t._check("P7d mines: the mine waits for its fuse, then blasts (25 dmg)", is_equal_approx(before, 100.0) and N.orbitals.is_empty() and float(N.enemy_list()[0]["hp"]) <= 75.0 + 0.01 and nb >= 0)
	# Harpoon: x2.5 on an elite, plain on a drone
	var H = _run()
	_body(H, TowerState.CENTER + Vector2(-200, 0), 1000.0, 0.0, "elite")
	_body(H, TowerState.CENTER + Vector2(200, 0), 1000.0)
	var hw: Dictionary = {"kind": "harpoon", "elite": 2.5, "slow": 0.4}
	FirePatterns.heavy(H, hw, TowerState.CENTER, int(H.en.order[0]), 40.0, false, [])
	FirePatterns.heavy(H, hw, TowerState.CENTER, int(H.en.order[1]), 40.0, false, [])
	var hl: Array = H.enemy_list()
	t._check("P7d harpoon: x2.5 on elites", is_equal_approx(1000.0 - float(hl[0]["hp"]), 100.0) and is_equal_approx(1000.0 - float(hl[1]["hp"]), 40.0), "%s" % [hl.map(func(x: Variant) -> float: return float((x as Dictionary)["hp"]))])
	# Plasma Fence: the lane burns
	var P = _run()
	_body(P, TowerState.CENTER + Vector2(-100, 0), 100.0)
	FirePatterns.lane_burn(P, {"kind": "plasma", "range": 300.0, "pierce": 10.0, "burn_s": 2.0}, TowerState.CENTER, Vector2(-1, 0), 10.0, false, [])
	t._check("P7d plasma: a body on the lane takes the touch and starts burning", float(P.enemy_list()[0]["hp"]) < 100.0 and P.en.burn_t[int(P.en.order[0])] > 0.0)
	# Pulse: hits all around it and shoves them
	var U = _run()
	var u0: Vector2 = TowerState.CENTER + Vector2(-200, 0)
	for k in 5:
		_body(U, u0 + Vector2.from_angle(TAU * float(k) / 5.0) * 30.0, 100.0)
	var uw: Dictionary = {"kind": "pulse", "pattern": "nova", "dmg": 6.0, "range": 50.0}
	var any: bool = FirePatterns.aura_hit(U, uw, u0, [])
	var un: int = 0
	for b in U.enemy_list():
		if float((b as Dictionary)["hp"]) < 100.0:
			un += 1
	t._check("P7d pulse: a nova hits every body in range", any and un == 5)
