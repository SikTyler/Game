extends RefCounted
## P3c selftest stage: directional weapons. Arc turrets never fire outside
## their traverse; fixed cones / lanes fire only when a body is in their shape
## and always along their facing; facing defaults away from the Core, rotates
## in 45 deg steps (free), persists across recomputes and waves; 2x2
## footprints collide; the WeaponDB sheet drives the weapon numbers.
## `t` is the selftest runner (t._check, t._mfresh, t._at, t._weapon).

const TowerState := preload("res://TowerState.gd")
const WeaponDB := preload("res://data/WeaponDB.gd")
const FirePatterns := preload("res://FirePatterns.gd")


static func run(t) -> void:
	_data(t)
	_facing(t)
	_arc(t)
	_fixed(t)
	_footprints(t)


static func _data(t) -> void:
	var ok: bool = true
	for id in WeaponDB.DEFS.keys():
		var d: Dictionary = WeaponDB.DEFS[id]
		ok = ok and WeaponDB.AIMS.has(String(d["aim"])) and FirePatterns.PATTERNS.has(String(d["pattern"])) and int(d["size"]) >= 1 and float(d["dir_mult"]) >= 1.0
		ok = ok and TowerState.size_of(String(id)) == int(d["size"])
		ok = ok and (String(d["aim"]) != "radial" or float(d["dir_mult"]) == 1.0)
	t._check("P3c WeaponDB: every weapon has a known aim and pattern, its footprint, radial = x1.0", ok)
	t._check("P3c the 6 weapons: Gatling arc 120, Flamer fixed cone 50, Railgun fixed lane 2x2, Mortar / Tesla / Cryo radial (Mortar 2x2)",
		WeaponDB.aim_of("gun") == "arc" and is_equal_approx(float(WeaponDB.DEFS["gun"]["arc"]), 120.0)
		and WeaponDB.aim_of("flak") == "fixed" and is_equal_approx(float(WeaponDB.DEFS["flak"]["arc"]), 50.0)
		and WeaponDB.aim_of("railgun") == "fixed" and float(WeaponDB.DEFS["railgun"]["arc"]) == 0.0 and TowerState.size_of("railgun") == 2
		and WeaponDB.aim_of("mortar") == "radial" and TowerState.size_of("mortar") == 2
		and WeaponDB.aim_of("tesla") == "radial" and WeaponDB.aim_of("frost") == "radial")
	t._check("P3c rotation steps: 0 = east, 2 = south, 6 = north (45 deg, clockwise on screen)",
		WeaponDB.facing(0).is_equal_approx(Vector2.RIGHT) and WeaponDB.facing(2).is_equal_approx(Vector2.DOWN) and WeaponDB.facing(6).is_equal_approx(Vector2.UP) and WeaponDB.facing(8).is_equal_approx(Vector2.RIGHT)
		and WeaponDB.rot_toward(Vector2(0, -5)) == 6 and WeaponDB.rot_toward(Vector2(3, 3)) == 1)


static func _open(t):
	var S = t._mfresh()
	for i in TowerState.N:
		S.unlocked[i] = not TowerState.is_core_cell(i)
	S.spawn_hold = true
	return S


static func _facing(t) -> void:
	var S = _open(t)
	var n: int = t._at(-3, 0)
	S.pending_place = "gun"
	S.place(n)
	t._check("P3c a new weapon faces away from the Core (north of it -> north)", S.rot_at(n) == 6 and (t._weapon(S, "gun")["facing"] as Vector2).is_equal_approx(Vector2.UP))
	var c0: float = S.cash
	var ev: Array = S.rotate(n, 1)
	t._check("P3c rotate: +45 deg, free, recomputes the sheet", S.rot_at(n) == 7 and ev.size() == 1 and String(ev[0]["t"]) == "rotated" and (t._weapon(S, "gun")["facing"] as Vector2).is_equal_approx(WeaponDB.facing(7)) and S.cash == c0)
	S.recompute()
	S.wave_t = S.wave_time - 0.001
	S.tick(0.05)
	t._check("P3c facing persists across recomputes and waves", S.rot_at(n) == 7)
	S.slots[t._at(-3, 3)] = {"id": "mine", "tier": 1}
	S.recompute()
	t._check("P3c radial / non-weapon buildings do not rotate", S.rotate(t._at(-3, 3), 1).is_empty())
	S.pending_place = "flak"
	var hint: int = t._at(3, 0)
	S.rotate_pending(1, hint)
	t._check("P3c rotating the pick being placed starts from its default there (south -> +45)", S.pending_rot == 3 and S.pending_rot_at(hint) == 3)
	S.place(hint)
	t._check("P3c the placed pick keeps the chosen facing; the pending facing resets", S.rot_at(hint) == 3 and S.pending_rot == -1)


static func _clear_weapons(S, keep: String) -> void:
	var w: Array = []
	for x in S.stats["weapons"]:
		if String((x as Dictionary)["kind"]) == keep:
			w.append(x)
	S.stats["weapons"] = w
	for k in TowerState.N:
		S.cooldowns[k] = 0.0


static func _body(S, p: Vector2, hp: float = 999.0) -> int:
	S.add_enemy({"kind": "mite", "pos": p, "hp": hp, "max_hp": hp, "size": 10.0, "spd": 0.0})
	return S.en.order[S.en.order.size() - 1]


static func _arc(t) -> void:
	var S = _open(t)
	var a: int = t._at(-3, 0)
	S.slots[a] = {"id": "gun", "tier": 1, "rot": 6}   # faces north
	S.recompute()
	_clear_weapons(S, "gun")
	var from: Vector2 = S.fp_pos(a)
	var behind: int = _body(S, from + Vector2(0, 120))      # south: outside the 120 deg arc
	var side: int = _body(S, from + Vector2(130, -10))      # east, ~4 deg above the horizon: outside (60 deg half arc)
	S.eh.rebuild()
	var ev: Array = []
	S._fire(0.01, ev)
	t._check("P3c Gatling (arc 120): never fires at bodies outside its traverse", _evts(ev, "shot").is_empty() and S.en.hp[behind] == 999.0 and S.en.hp[side] == 999.0)
	var ahead: int = _body(S, from + Vector2(40, -120))      # ~18 deg off north: inside
	S.eh.rebuild()
	ev = []
	S._fire(0.01, ev)
	t._check("P3c Gatling fires at a body inside its arc, and only there", S.en.hp[ahead] < 999.0 and S.en.hp[behind] == 999.0 and S.en.hp[side] == 999.0)
	var cands: Array = []
	for m in ["first", "strongest", "weakest"]:
		cands.append(S.pick_target_for(t._weapon(S, "gun"), from, String(m)))
	t._check("P3c every targeting mode stays inside the arc", cands.all(func(c: Variant) -> bool: return int(c) == ahead))


static func _fixed(t) -> void:
	# Railgun: a fixed 2x2 lane north; a body east is ignored, a body in the lane fires it.
	var S = _open(t)
	var r: int = t._at(-7, -1)
	S.slots[r] = {"id": "railgun", "tier": 1, "rot": 6}
	S.recompute()
	_clear_weapons(S, "railgun")
	var from: Vector2 = S.fp_pos(r)
	var east: int = _body(S, from + Vector2(150, 0))
	S.eh.rebuild()
	var ev: Array = []
	S._fire(0.01, ev)
	t._check("P3c Railgun (fixed lane): an empty lane holds fire (a body off the lane is ignored)", _evts(ev, "shot").is_empty() and S.en.hp[east] == 999.0 and float(S.cooldowns[r]) == 0.0)
	var lane1: int = _body(S, from + Vector2(4, -120))
	var lane2: int = _body(S, from + Vector2(-3, -260))
	S.eh.rebuild()
	ev = []
	S._fire(0.01, ev)
	var sh: Array = _evts(ev, "shot")
	t._check("P3c Railgun fires straight along its facing through the whole lane", sh.size() == 1 and S.en.hp[lane1] < 999.0 and S.en.hp[lane2] < 999.0 and S.en.hp[east] == 999.0 and ((sh[0]["to"] as Vector2) - from).normalized().is_equal_approx(Vector2.UP))
	# Flamer: a fixed 50 deg cone; a body 40 deg off the facing is outside it.
	var F = _open(t)
	var f: int = t._at(-3, 0)
	F.slots[f] = {"id": "flak", "tier": 1, "rot": 6}
	F.recompute()
	_clear_weapons(F, "flak")
	var ff: Vector2 = F.fp_pos(f)
	var off: int = _body(F, ff + Vector2.from_angle(deg_to_rad(-90.0 + 40.0)) * 60.0)
	F.eh.rebuild()
	ev = []
	F._fire(0.01, ev)
	t._check("P3c Flamer (fixed cone): holds fire while its cone is empty", _evts(ev, "shot").is_empty() and F.en.hp[off] == 999.0)
	var inside: int = _body(F, ff + Vector2.from_angle(deg_to_rad(-90.0 + 15.0)) * 60.0)
	F.eh.rebuild()
	ev = []
	F._fire(0.01, ev)
	t._check("P3c Flamer licks the body inside its cone, not the one outside", F.en.hp[inside] < 999.0 and F.en.hp[off] == 999.0 and F.burning.size() == 1)


static func _footprints(t) -> void:
	var S = _open(t)
	S.pending_place = "mortar"
	var a: int = t._at(-5, -1)
	t._check("P3c a 2x2 Mortar places on four free cells", not S.place(a).is_empty() and S.owner_at(a + 1) == a and S.owner_at(a + TowerState.SIDE + 1) == a)
	S.pending_place = "railgun"
	t._check("P3c a 2x2 footprint overlapping another is refused", S.place(a + 1).is_empty() and S.place(a - TowerState.SIDE - 1).is_empty() and S.pending_place == "railgun")
	t._check("P3c a 2x2 footprint must stay on the board", not S.can_place(TowerState.SIDE - 1, "railgun") and TowerState.footprint(TowerState.N - 1, 2).is_empty())


static func _evts(ev: Array, kind: String) -> Array:
	return ev.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == kind)
