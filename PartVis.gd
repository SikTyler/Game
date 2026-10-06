extends RefCounted
## Procedural parts art (V3, design/V3_PARTS.md §4). The Weapon and the Core
## are drawn from their installed parts - no sprites - so every build looks
## like what it does:
##   Weapon (top-down turret): the Receiver hub (shape by base, size by
##     rarity), 1-4 barrels fanned around it (each barrel's archetype
##     silhouette; the first points at the aim), a Muzzle on every barrel tip,
##     Scope, Power cell, Magazine and Ammo canisters on the hub.
##   Core: the Heart (glow), Plating shell(s) (shape by base: octagon, hex,
##     star, segments, layers, crystal), Generator rings, Capacitor coils,
##     a Reactor ring, Uplink dishes, Antenna masts and a Shield dome.
## Colours come from the Core Look (p / s / g / pat); rarity tints rims.
## `weapon_desc` / `core_desc` are the pure descriptions (also the test's
## uniqueness signature); the draw functions only render them. Draw calls take
## the canvas `ci` and its current transform `base` and restore it after.

const PartDB := preload("res://data/PartDB.gd")
const RarityDB := preload("res://data/RarityDB.gd")

const RARITY_COL: Dictionary = {"common": Color("9aa4b2"), "uncommon": Color("4ade80"), "rare": Color("38bdf8"),
	"epic": Color("b26bff"), "legendary": Color("f59e0b"), "mythic": Color("ff3e6c"), "exotic": Color("ffffff")}
## Ammo canister colour by ammo look.
const AMMO_COL: Array = ["d9c27a", "ff8a3d", "8ef06a", "c9d3e3", "ff4d6d", "9be8ff", "ffe14d", "ff8fd1",
	"4de8d0", "a855f7", "8a96ab", "e0365a", "ffd34d", "ff5fb8"]
## Power cell glow by power look.
const POWER_COL: Array = ["39e6ff", "b26bff", "ffe14d", "4de8d0", "e8f0ff", "ff4d6d", "9be8ff"]
## Heart glow by heart look.
const HEART_COL: Array = ["39e6ff", "6e9bff", "4ade80", "ffd34d", "c9d3e3", "c084fc"]
## Reactor ring by reactor look.
const REACTOR_COL: Array = ["39e6ff", "ffd34d", "4ade80", "e8a46f"]
## Barrel silhouette tweaks of the variant barrels (look -> tweak).
const VARIANT: Dictionary = {
	11: {"len": 0.9, "w": 1.6},             # Siege Mortar: a squat, fat tube
	12: {"n": 3, "len": 0.8},                # Burst Carbine: three short tubes
	13: {"len": 1.3, "w": 0.7},              # Flechette: a long, tight bell
	14: {"len": 0.75, "coils": 3},           # Coilgun: short rails with coils
	15: {"coils": 6},                        # Storm Coil: more coils
	16: {"w": 1.5, "glow": "ff5fb8"},        # Plasma Caster: a thick glowing tube
	17: {"tint": "9be8ff", "vanes": true},   # Frost Projector: icy nozzle + vanes
	18: {"w": 1.5, "len": 1.2},              # Quake Hammer: a heavy dish
	19: {"n": 3},                            # Hornet Pod: 3x3 tubes
	20: {"len": 1.25, "teeth": 6},           # Disc Thrower: a bigger, coarser blade
	21: {"seg": true},                       # Pulse Laser: segmented beam lens
	22: {"n": 6, "w": 1.3},                  # Vulcan: six heavier tubes
}


# ------------------------------------------------------------------ descriptions

static func _look(it: Dictionary) -> int:
	return int(PartDB.get_def(String(it.get("base", ""))).get("look", 0))


static func _brief(it: Dictionary) -> Dictionary:
	return {"look": _look(it), "rar": String(it.get("rar", "common")), "mw": mini(6, int(it.get("mw", 0)))}


## Equipped parts of a slot from a save (Parts.equipped without the preload
## cycle: PartVis is drawn by views that already hold the save).
static func _eq(s: Dictionary, slot: String) -> Array:
	var p: Variant = s.get("parts", null)
	if not (p is Dictionary):
		return []
	var out: Array = []
	var arr: Array = ((p as Dictionary).get("equipped", {}) as Dictionary).get(slot, [])
	var chassis_slot: String = "receiver" if PartDB.side_of(slot) == "weapon" else "heart"
	var ch: Array = ((p as Dictionary).get("equipped", {}) as Dictionary).get(chassis_slot, [])
	var ch_it: Dictionary = ((p as Dictionary)["items"] as Dictionary).get(str(ch[0]), {}) if not ch.is_empty() else {}
	var n: int = 1 if PartDB.is_chassis(slot) else int(PartDB.layout(chassis_slot, String(ch_it.get("rar", "common"))).get(slot, 0))
	for i in mini(n, arr.size()):
		var it: Dictionary = ((p as Dictionary)["items"] as Dictionary).get(str(arr[i]), {})
		if not it.is_empty():
			out.append(it)
	return out


static func _one(s: Dictionary, slot: String) -> Dictionary:
	var a: Array = _eq(s, slot)
	return _brief(a[0]) if not a.is_empty() else {}


## The Weapon's visual description (pure).
static func weapon_desc(s: Dictionary) -> Dictionary:
	var rc: Array = _eq(s, "receiver")
	var out: Dictionary = {"rcv": _brief(rc[0]) if not rc.is_empty() else {"look": 0, "rar": "common", "mw": 0}, "brl": [], "ammo": []}
	for b in _eq(s, "barrel"):
		var bd: Dictionary = PartDB.get_def(String((b as Dictionary)["base"]))
		var e: Dictionary = _brief(b)
		e["frame"] = String(bd.get("frame", "autocannon"))
		(out["brl"] as Array).append(e)
	if (out["brl"] as Array).is_empty():
		(out["brl"] as Array).append({"look": 0, "rar": "common", "mw": 0, "frame": "autocannon"})
	for a in _eq(s, "ammo"):
		(out["ammo"] as Array).append(_look(a))
	for sl in ["scope", "power", "muzzle", "mag"]:
		out[sl] = _one(s, sl)
	return out


## The Core's visual description (pure).
static func core_desc(s: Dictionary) -> Dictionary:
	var hr: Array = _eq(s, "heart")
	var out: Dictionary = {"heart": _brief(hr[0]) if not hr.is_empty() else {"look": 0, "rar": "common", "mw": 0}}
	for sl in ["plating", "generator", "uplink"]:
		var arr: Array = []
		for it in _eq(s, sl):
			arr.append(_brief(it))
		out[sl] = arr
	for sl in ["capacitor", "reactor", "antenna", "emitter"]:
		out[sl] = _one(s, sl)
	return out


## A stable signature of a save's whole build (Core + Weapon looks).
static func signature(s: Dictionary) -> String:
	return JSON.stringify({"w": weapon_desc(s), "c": core_desc(s)})


static func _c(hex: String, fallback: Color = Color.WHITE) -> Color:
	return Color.html(hex) if Color.html_is_valid(hex) else fallback


static func rar_col(r: String, t: float = 0.0) -> Color:
	if r == "exotic":
		return Color.from_hsv(fposmod(t * 0.18, 1.0), 0.55, 1.0)
	return RARITY_COL.get(r, Color("9aa4b2"))


static func _push(ci: CanvasItem, base: Transform2D, origin: Vector2, angle: float, sc: float) -> void:
	ci.draw_set_transform_matrix(base * Transform2D(angle, Vector2(sc, sc), 0.0, origin))


static func _pop(ci: CanvasItem, base: Transform2D) -> void:
	ci.draw_set_transform_matrix(base)


static func _ngon(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
	var o: PackedVector2Array = PackedVector2Array()
	for i in n:
		o.append(c + Vector2.from_angle(rot + TAU * float(i) / float(n)) * r)
	return o


static func _outline(ci: CanvasItem, poly: PackedVector2Array, col: Color, w: float) -> void:
	var pts: PackedVector2Array = poly.duplicate()
	pts.append(poly[0])
	ci.draw_polyline(pts, col, w, true)


static func _paint(look: Dictionary) -> Dictionary:
	return {"p": _c(String(look.get("p", "5a6788")), Color("5a6788")), "s": _c(String(look.get("s", "39e6ff")), Color("39e6ff")),
		"g": _c(String(look.get("g", "ff3ea5")), Color("ff3ea5")), "pat": int(look.get("pat", 0))}


# ------------------------------------------------------------------ weapon

## Draw the Weapon turret at `center`, `size` px across, barrel 0 along
## `aim`. Local units: the hub sits at 0, barrels reach ~50.
static func draw_weapon(ci: CanvasItem, W: Dictionary, look: Dictionary, center: Vector2, size: float, aim: float = 0.0, t: float = 0.0, base: Transform2D = Transform2D.IDENTITY) -> void:
	var P: Dictionary = _paint(look)
	var rv: Dictionary = W.get("rcv", {})
	var hub_r: float = 13.0 + 1.3 * float(RarityDB.rank(String(rv.get("rar", "common"))))
	_push(ci, base, center, aim, size / 100.0)
	var brl: Array = W.get("brl", [])
	var n: int = maxi(1, brl.size())
	# power cell behind the hub (opposite barrel 0), magazine and ammo below
	var pw: Dictionary = W.get("power", {})
	if not pw.is_empty():
		_power(ci, int(pw["look"]), Vector2(-hub_r - 6.0, 0), P, t)
	var mg: Dictionary = W.get("mag", {})
	if not mg.is_empty():
		_mag(ci, int(mg["look"]), Vector2(-4.0, hub_r + 4.0), P, t)
	var am: Array = W.get("ammo", [])
	for i in am.size():
		_ammo(ci, int(am[i]), Vector2(-hub_r * 0.2 - 9.0 * float(i), -hub_r - 4.0), P, t)
	# barrels fanned around the hub
	var mz: Dictionary = W.get("muzzle", {})
	for k in n:
		var b: Dictionary = brl[k] if k < brl.size() else {"look": 0, "rar": "common", "frame": "autocannon"}
		var a: float = TAU * float(k) / float(n)
		ci.draw_set_transform_matrix(base * Transform2D(aim, Vector2(size / 100.0, size / 100.0), 0.0, center) * Transform2D(a, Vector2.ZERO))
		var tip: Vector2 = _barrel(ci, String(b.get("frame", "autocannon")), int(b.get("look", 0)), hub_r - 3.0, P, t)
		if not mz.is_empty():
			_muzzle(ci, int(mz["look"]), tip, P, t)
		var rc: Color = rar_col(String(b.get("rar", "common")), t)
		if RarityDB.rank(String(b.get("rar", "common"))) >= 2:
			ci.draw_line(Vector2(hub_r, -1.0), Vector2(tip.x - 2.0, -1.0), Color(rc, 0.55), 1.0)
	_push(ci, base, center, aim, size / 100.0)
	# the hub on top of the barrel roots
	_hub(ci, int(rv.get("look", 0)), hub_r, P, t)
	var rcol: Color = rar_col(String(rv.get("rar", "common")), t)
	_outline(ci, _hub_poly(int(rv.get("look", 0)), hub_r), rcol, 1.6 + (0.8 * (0.5 + 0.5 * sin(t * 4.0)) if RarityDB.rank(String(rv.get("rar", "common"))) >= 4 else 0.0))
	# masterwork pips
	for k in int(rv.get("mw", 0)):
		ci.draw_circle(Vector2.from_angle(PI * 0.75 + float(k) * 0.32) * (hub_r + 2.5), 1.4, Color("ffd34d"))
	# scope on top of the hub, along barrel 0
	var sp: Dictionary = W.get("scope", {})
	if not sp.is_empty():
		_scope(ci, int(sp["look"]), Vector2(2.0, 0), P, t)
	_pop(ci, base)


## Receiver hub silhouettes by look.
static func _hub_poly(look: int, r: float) -> PackedVector2Array:
	match look % 7:
		1:   # heavy: a broad octagon
			return _ngon(Vector2.ZERO, r * 1.12, 8, PI / 8.0)
		2:   # rapid: a slim diamond
			return PackedVector2Array([Vector2(r * 1.2, 0), Vector2(0, -r * 0.8), Vector2(-r * 1.1, 0), Vector2(0, r * 0.8)])
		3:   # precision: a hexagon
			return _ngon(Vector2.ZERO, r, 6, 0.0)
		4:   # burst: three lobes
			var o: PackedVector2Array = PackedVector2Array()
			for i in 18:
				var a: float = TAU * float(i) / 18.0
				o.append(Vector2.from_angle(a) * r * (0.82 + 0.22 * cos(a * 3.0)))
			return o
		5:   # siege: a square block
			return PackedVector2Array([Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)])
		6:   # overdrive: a spiky gear
			var g: PackedVector2Array = PackedVector2Array()
			for i in 16:
				g.append(Vector2.from_angle(TAU * float(i) / 16.0) * r * (1.12 if i % 2 == 0 else 0.86))
			return g
	# standard: a rounded square
	var q: PackedVector2Array = PackedVector2Array()
	for i in 12:
		var a2: float = TAU * float(i) / 12.0 + PI / 12.0
		q.append(Vector2(cos(a2), sin(a2)) * r * (1.0 if i % 3 != 1 else 1.05))
	return q


static func _hub(ci: CanvasItem, look: int, r: float, P: Dictionary, t: float) -> void:
	var poly: PackedVector2Array = _hub_poly(look, r)
	var pc: Color = P["p"]
	var dark: Color = pc.darkened(0.55)
	ci.draw_colored_polygon(poly, pc)
	ci.draw_circle(Vector2.ZERO, r * 0.55, dark)
	ci.draw_circle(Vector2.ZERO, r * 0.32, Color(P["s"], 0.65 + 0.25 * sin(t * 3.0)))
	match look % 7:
		3:
			ci.draw_arc(Vector2.ZERO, r * 0.75, 0.0, TAU, 18, P["g"], 1.2)
		5:
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				ci.draw_circle(c * r * 0.72, 1.4, P["g"])
		6:
			for k in 3:
				var a: float = PI * 0.6 + float(k) * 0.4
				ci.draw_line(Vector2.from_angle(a) * r * 0.6, Vector2.from_angle(a) * r * 0.95, Color("ff8a3d", 0.6 + 0.4 * sin(t * 8.0 + float(k))), 1.6)


## One barrel along +x from `x0`; returns its tip.
static func _barrel(ci: CanvasItem, frame: String, look: int, x0: float, P: Dictionary, t: float) -> Vector2:
	var v: Dictionary = VARIANT.get(look, {})
	var lk: float = float(v.get("len", 1.0))
	var wk: float = float(v.get("w", 1.0))
	var sc: Color = _c(String(v.get("tint", "")), P["s"]) if v.has("tint") else P["s"]
	var pc: Color = P["p"]
	var dark: Color = pc.darkened(0.55)
	var gc: Color = P["g"]
	match frame:
		"minigun":
			var L: float = 30.0 * lk
			var n: int = int(v.get("n", 4))
			var tw: float = 2.4 * wk
			var span: float = 10.0 * wk
			for i in n:
				var y: float = -span * 0.5 + span * float(i) / float(maxi(1, n - 1))
				ci.draw_rect(Rect2(Vector2(x0, y - tw * 0.5), Vector2(L, tw)), sc.darkened(0.15))
			ci.draw_rect(Rect2(Vector2(x0 + L * 0.55, -span * 0.5 - 2.0), Vector2(4.0, span + 4.0)), dark)
			var sp: float = fposmod(t * 12.0, 1.0)
			ci.draw_line(Vector2(x0 + L * 0.55, -span * 0.5 + span * sp), Vector2(x0 + L * 0.55 + 4.0, -span * 0.5 + span * sp), gc, 1.2)
			return Vector2(x0 + L, 0)
		"rail":
			var L2: float = 46.0 * lk
			ci.draw_rect(Rect2(Vector2(x0, -6.0), Vector2(L2, 2.6)), dark)
			ci.draw_rect(Rect2(Vector2(x0, 3.4), Vector2(L2, 2.6)), dark)
			ci.draw_line(Vector2(x0 + 2.0, 0), Vector2(x0 + L2, 0), Color(sc, 0.55 + 0.4 * sin(t * 6.0)), 1.6)
			for i in int(v.get("coils", 0)):
				var cx: float = x0 + 6.0 + float(i) * (L2 - 10.0) / float(maxi(1, int(v.get("coils", 0))))
				ci.draw_arc(Vector2(cx, 0), 7.5, 0.0, TAU, 12, gc, 1.2)
			return Vector2(x0 + L2, 0)
		"pulse":
			var L3: float = 10.0 * lk
			var R: float = 9.0 * wk
			ci.draw_rect(Rect2(Vector2(x0, -3.0), Vector2(L3, 6.0)), dark)
			ci.draw_arc(Vector2(x0 + L3 + 2.0, 0), R, -PI * 0.5, PI * 0.5, 14, sc, 3.0)
			var ph: float = fposmod(t * 1.5, 1.0)
			ci.draw_arc(Vector2(x0 + L3 + 2.0, 0), R + 6.0 * ph, -PI * 0.45, PI * 0.45, 12, Color(sc, 1.0 - ph), 1.5)
			return Vector2(x0 + L3 + 2.0 + R, 0)
		"scatter":
			var L4: float = 26.0 * lk
			var w0: float = 7.0 * wk
			var w1: float = 17.0 * wk
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, -w0 * 0.5), Vector2(x0 + L4, -w1 * 0.5), Vector2(x0 + L4, w1 * 0.5), Vector2(x0, w0 * 0.5)]), dark)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x0 + 2.0, -w0 * 0.3), Vector2(x0 + L4 - 1.0, -w1 * 0.38), Vector2(x0 + L4 - 1.0, w1 * 0.38), Vector2(x0 + 2.0, w0 * 0.3)]), sc.darkened(0.2))
			return Vector2(x0 + L4, 0)
		"slag":
			var L5: float = 22.0 * lk
			var w5: float = 11.0 * wk
			ci.draw_rect(Rect2(Vector2(x0, -w5 * 0.5), Vector2(L5, w5)), dark)
			ci.draw_rect(Rect2(Vector2(x0, -w5 * 0.5 + 1.5), Vector2(L5, w5 - 3.0)), pc.lightened(0.1))
			for i in 2:
				ci.draw_line(Vector2(x0 + L5 * (0.35 + 0.35 * float(i)), -w5 * 0.5), Vector2(x0 + L5 * (0.35 + 0.35 * float(i)), w5 * 0.5), sc, 2.0)
			return Vector2(x0 + L5, 0)
		"arc":
			var L6: float = 30.0 * lk
			ci.draw_rect(Rect2(Vector2(x0, -2.5), Vector2(L6, 5.0)), dark)
			var nc: int = int(v.get("coils", 4))
			for i in nc:
				var cx2: float = x0 + 5.0 + float(i) * (L6 - 8.0) / float(maxi(1, nc))
				ci.draw_arc(Vector2(cx2, 0), 5.5, 0.0, TAU, 10, gc, 1.4)
			ci.draw_circle(Vector2(x0 + L6, 0), 3.5, Color(sc, 0.6 + 0.4 * sin(t * 10.0)))
			return Vector2(x0 + L6 + 2.0, 0)
		"flame":
			var L7: float = 24.0 * lk
			ci.draw_rect(Rect2(Vector2(x0, -3.5), Vector2(L7, 7.0)), dark)
			ci.draw_rect(Rect2(Vector2(x0 + 2.0, 5.0), Vector2(L7 * 0.55, 6.0)), sc.darkened(0.25))
			ci.draw_circle(Vector2(x0 + L7 + 2.0, 0), 2.6, Color(sc, 0.5 + 0.5 * sin(t * 9.0)))
			if bool(v.get("vanes", false)):
				for i in 3:
					var vx: float = x0 + 6.0 + float(i) * 6.0
					ci.draw_colored_polygon(PackedVector2Array([Vector2(vx, -3.5), Vector2(vx + 4.0, -3.5), Vector2(vx + 2.0, -8.5)]), sc)
			return Vector2(x0 + L7, 0)
		"missiles":
			var L8: float = 20.0 * lk
			var rows: int = int(v.get("n", 2))
			var H: float = 7.0 * float(rows) + 2.0
			ci.draw_rect(Rect2(Vector2(x0, -H * 0.5), Vector2(L8, H)), dark)
			for i in rows:
				for j in rows:
					var cy: float = -H * 0.5 + 4.5 + 7.0 * float(j)
					ci.draw_circle(Vector2(x0 + L8 - 3.5 - 6.0 * float(i) / float(rows), cy), 2.4, sc)
			return Vector2(x0 + L8, 0)
		"saw":
			var L9: float = 16.0
			var R2: float = 8.5 * lk
			ci.draw_rect(Rect2(Vector2(x0, -2.5), Vector2(L9, 5.0)), dark)
			var c: Vector2 = Vector2(x0 + L9 + R2 * 0.6, 0)
			var teeth: int = int(v.get("teeth", 10))
			var blade: PackedVector2Array = PackedVector2Array()
			for i in teeth * 2:
				blade.append(c + Vector2.from_angle(t * 8.0 + TAU * float(i) / float(teeth * 2)) * R2 * (1.0 if i % 2 == 0 else 0.78))
			ci.draw_colored_polygon(blade, sc.darkened(0.1))
			ci.draw_circle(c, R2 * 0.3, dark)
			return c + Vector2(R2, 0)
		"lance":
			var L10: float = 42.0 * lk
			ci.draw_rect(Rect2(Vector2(x0, -2.0), Vector2(L10, 4.0)), dark)
			if bool(v.get("seg", false)):
				for i in 5:
					var sx: float = x0 + 4.0 + float(i) * (L10 - 6.0) / 5.0
					ci.draw_line(Vector2(sx, -3.5), Vector2(sx, 3.5), Color(sc, 0.5 + 0.5 * sin(t * 7.0 - float(i))), 1.4)
			else:
				ci.draw_line(Vector2(x0 + 2.0, 0), Vector2(x0 + L10, 0), Color(sc, 0.6 + 0.3 * sin(t * 4.0)), 1.4)
			ci.draw_circle(Vector2(x0 + L10, 0), 3.8, gc)
			return Vector2(x0 + L10 + 2.0, 0)
	# autocannon (+ Burst Carbine / Plasma Caster)
	var L0: float = 34.0 * lk
	var w: float = 7.0 * wk
	var tubes: int = int(v.get("n", 1))
	for i in tubes:
		var y0: float = (float(i) - float(tubes - 1) * 0.5) * (w * 0.9)
		var tw0: float = w if tubes == 1 else w * 0.7
		ci.draw_rect(Rect2(Vector2(x0, y0 - tw0 * 0.5), Vector2(L0, tw0)), dark)
		ci.draw_rect(Rect2(Vector2(x0, y0 - tw0 * 0.5 + 1.0), Vector2(L0, tw0 - 2.0)), sc.darkened(0.15))
		ci.draw_line(Vector2(x0 + 2.0, y0 - tw0 * 0.5 + 1.5), Vector2(x0 + L0 - 2.0, y0 - tw0 * 0.5 + 1.5), Color(1, 1, 1, 0.35), 1.0)
	if v.has("glow"):
		ci.draw_circle(Vector2(x0 + L0, 0), w * 0.6, Color(_c(String(v["glow"])), 0.55 + 0.35 * sin(t * 5.0)))
	return Vector2(x0 + L0, 0)


static func _muzzle(ci: CanvasItem, look: int, tip: Vector2, P: Dictionary, t: float) -> void:
	var dark: Color = (P["p"] as Color).darkened(0.6)
	var gc: Color = P["g"]
	match look % 6:
		0:   # compensator: a slotted block
			ci.draw_rect(Rect2(tip + Vector2(-1, -4.5), Vector2(6, 9)), dark)
			ci.draw_line(tip + Vector2(1, -4.5), tip + Vector2(1, 4.5), gc, 1.0)
			ci.draw_line(tip + Vector2(3, -4.5), tip + Vector2(3, 4.5), gc, 1.0)
		1:   # brake: a wide block
			ci.draw_rect(Rect2(tip + Vector2(-1, -6.5), Vector2(5, 13)), dark)
		2:   # choke: a narrowing cone
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -4), tip + Vector2(7, -2), tip + Vector2(7, 2), tip + Vector2(0, 4)]), gc.darkened(0.3))
		3:   # suppressor: a long can
			ci.draw_rect(Rect2(tip + Vector2(-1, -3.5), Vector2(11, 7)), dark)
			ci.draw_line(tip + Vector2(1, -3.5), tip + Vector2(9, -3.5), Color(gc, 0.5), 1.0)
		4:   # flare booster: a glowing ring
			ci.draw_arc(tip + Vector2(3, 0), 4.5, 0.0, TAU, 12, Color("ff8a3d", 0.7 + 0.3 * sin(t * 9.0)), 2.0)
		5:   # splitter: forked prongs
			ci.draw_line(tip, tip + Vector2(7, -5), gc, 1.8)
			ci.draw_line(tip, tip + Vector2(7, 5), gc, 1.8)


static func _scope(ci: CanvasItem, look: int, at: Vector2, P: Dictionary, t: float) -> void:
	var dark: Color = (P["p"] as Color).darkened(0.6)
	var gc: Color = P["g"]
	match look % 7:
		0:   # long optic
			ci.draw_rect(Rect2(at + Vector2(-6, -3), Vector2(22, 6)), dark)
			ci.draw_circle(at + Vector2(16, 0), 3.2, gc)
		1:   # red dot
			ci.draw_rect(Rect2(at + Vector2(-2, -3.5), Vector2(9, 7)), dark)
			ci.draw_circle(at + Vector2(2.5, 0), 1.6, Color("ff4d6d", 0.7 + 0.3 * sin(t * 6.0)))
		2:   # hunter sight: a crosshair ring
			ci.draw_rect(Rect2(at + Vector2(-4, -3), Vector2(14, 6)), dark)
			ci.draw_arc(at + Vector2(12, 0), 4.5, 0.0, TAU, 12, gc, 1.4)
			ci.draw_line(at + Vector2(8, 0), at + Vector2(16, 0), gc, 1.0)
		3:   # thermal: an orange lens
			ci.draw_rect(Rect2(at + Vector2(-5, -3.5), Vector2(16, 7)), dark)
			ci.draw_circle(at + Vector2(11, 0), 3.4, Color("ff8a3d"))
		4:   # spotter: twin lenses
			ci.draw_rect(Rect2(at + Vector2(-4, -5), Vector2(14, 10)), dark)
			ci.draw_circle(at + Vector2(10, -2.5), 2.2, gc)
			ci.draw_circle(at + Vector2(10, 2.5), 2.2, gc)
		5:   # rangefinder: a laser line
			ci.draw_rect(Rect2(at + Vector2(-4, -3), Vector2(13, 6)), dark)
			ci.draw_line(at + Vector2(9, 0), at + Vector2(36, 0), Color("ff4d6d", 0.25 + 0.15 * sin(t * 5.0)), 1.0)
		_:   # tactical: a box and a dot
			ci.draw_rect(Rect2(at + Vector2(-5, -4), Vector2(12, 8)), dark)
			ci.draw_circle(at + Vector2(5, 0), 2.0, gc)


static func _power(ci: CanvasItem, look: int, at: Vector2, P: Dictionary, t: float) -> void:
	var col: Color = _c(String(POWER_COL[look % POWER_COL.size()]))
	var dark: Color = (P["p"] as Color).darkened(0.6)
	var fl: float = 0.6 + 0.4 * sin(t * (11.0 if look % 7 == 5 else 3.0))
	ci.draw_rect(Rect2(at + Vector2(-8, -5), Vector2(10, 10)), dark)
	ci.draw_rect(Rect2(at + Vector2(-6.5, -3.5), Vector2(7, 7)), Color(col, fl))
	if look % 7 == 3:   # capacitor bank: coils
		for i in 3:
			ci.draw_line(at + Vector2(-8 + float(i) * 3.5, -7), at + Vector2(-8 + float(i) * 3.5, 7), col, 1.0)


static func _mag(ci: CanvasItem, look: int, at: Vector2, P: Dictionary, t: float) -> void:
	var dark: Color = (P["p"] as Color).darkened(0.55)
	var sc: Color = P["s"]
	match look % 6:
		0:   # drum
			ci.draw_circle(at, 6.5, dark)
			ci.draw_circle(at, 4.2, sc)
			ci.draw_circle(at, 1.6, dark)
		1:   # echo chamber: rings
			ci.draw_circle(at, 5.0, dark)
			ci.draw_arc(at, 6.5 + fposmod(t * 3.0, 1.0) * 2.0, 0.0, TAU, 12, Color(sc, 0.6), 1.2)
		2:   # quickload: a box
			ci.draw_rect(Rect2(at + Vector2(-5, -2), Vector2(10, 8)), dark)
			ci.draw_rect(Rect2(at + Vector2(-3, 0), Vector2(6, 4)), sc)
		3:   # belt feed: links
			for i in 4:
				ci.draw_rect(Rect2(at + Vector2(-6 + float(i) * 3.5, -1), Vector2(2.5, 5)), Color("d9c27a"))
		4:   # extended: a long box
			ci.draw_rect(Rect2(at + Vector2(-4, -2), Vector2(8, 13)), dark)
			ci.draw_line(at + Vector2(0, 0), at + Vector2(0, 9), sc, 1.4)
		_:   # shredder: a spiked box
			ci.draw_rect(Rect2(at + Vector2(-5, -2), Vector2(10, 8)), dark)
			for i in 3:
				ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-5 + float(i) * 3.5, 6), at + Vector2(-3 + float(i) * 3.5, 6), at + Vector2(-4 + float(i) * 3.5, 9)]), sc)


static func _ammo(ci: CanvasItem, look: int, at: Vector2, P: Dictionary, t: float) -> void:
	var col: Color = _c(String(AMMO_COL[look % AMMO_COL.size()]))
	var dark: Color = (P["p"] as Color).darkened(0.6)
	ci.draw_rect(Rect2(at + Vector2(-3.5, -7), Vector2(7, 9)), dark)
	ci.draw_rect(Rect2(at + Vector2(-2.5, -6), Vector2(5, 7)), Color(col, 0.75 + 0.25 * sin(t * 2.5 + float(look))))
	ci.draw_line(at + Vector2(-3.5, -3), at + Vector2(3.5, -3), dark, 1.0)


# ------------------------------------------------------------------ core

## Draw the Core from its parts at `center`, shell radius `r` px, then the
## Weapon turret on top aimed at `aim`.
static func draw_assembly(ci: CanvasItem, s: Dictionary, look: Dictionary, center: Vector2, r: float, aim: float = -PI * 0.5, t: float = 0.0, base: Transform2D = Transform2D.IDENTITY) -> void:
	draw_core(ci, core_desc(s), look, center, r, t, base)
	draw_weapon(ci, weapon_desc(s), look, center, r * 1.15, aim, t, base)


static func draw_core(ci: CanvasItem, D: Dictionary, look: Dictionary, center: Vector2, r: float, t: float = 0.0, base: Transform2D = Transform2D.IDENTITY) -> void:
	var P: Dictionary = _paint(look)
	var pc: Color = P["p"]
	var sc: Color = P["s"]
	var gc: Color = P["g"]
	_push(ci, base, center, 0.0, r / 50.0)
	# shield dome (behind everything)
	var em: Dictionary = D.get("emitter", {})
	if not em.is_empty():
		_emitter(ci, int(em["look"]), sc, t)
	# antenna masts
	var an: Dictionary = D.get("antenna", {})
	if not an.is_empty():
		_antenna(ci, int(an["look"]), sc, gc, t)
	# plating shell(s)
	var pl: Array = D.get("plating", [])
	if pl.size() >= 2:
		_plating(ci, int((pl[1] as Dictionary)["look"]), 50.0, pc.darkened(0.25), sc, t, true)
	if not pl.is_empty():
		_plating(ci, int((pl[0] as Dictionary)["look"]), 44.0, pc, sc, t, false)
		_outline(ci, _shell_poly(int((pl[0] as Dictionary)["look"]), 44.0), rar_col(String((pl[0] as Dictionary)["rar"]), t), 2.0)
	else:
		# bare frame: a skeleton ring
		ci.draw_circle(Vector2.ZERO, 40.0, pc.darkened(0.45))
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			ci.draw_line(Vector2.from_angle(a) * 18.0, Vector2.from_angle(a) * 40.0, Color(sc, 0.35), 2.0)
		ci.draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 32, Color(sc, 0.6), 2.0)
	# uplink dishes on the shell
	var ul: Array = D.get("uplink", [])
	for i in ul.size():
		for j in 2:
			var a2: float = PI * 0.25 + PI * float(j) + PI * 0.5 * float(i)
			_uplink(ci, int((ul[i] as Dictionary)["look"]), Vector2.from_angle(a2) * 40.0, a2, gc, t)
	# capacitor coils
	var cp: Dictionary = D.get("capacitor", {})
	if not cp.is_empty():
		_capacitor(ci, int(cp["look"]), t)
	# reactor ring
	var rc: Dictionary = D.get("reactor", {})
	if not rc.is_empty():
		var rcol: Color = _c(String(REACTOR_COL[int(rc["look"]) % REACTOR_COL.size()]))
		ci.draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 36, Color(rcol, 0.55 + 0.3 * sin(t * 2.0)), 3.5)
		for i in 6:
			var a3: float = TAU * float(i) / 6.0 - t * 0.6
			ci.draw_circle(Vector2.from_angle(a3) * 27.0, 1.8, rcol)
	# generator rings
	var gn: Array = D.get("generator", [])
	for i in gn.size():
		_generator(ci, int((gn[i] as Dictionary)["look"]), 21.0 + 4.0 * float(i), sc, gc, t * (1.0 if i == 0 else -1.3))
	# the heart
	var ht: Dictionary = D.get("heart", {})
	var hcol: Color = _c(String(HEART_COL[int(ht.get("look", 0)) % HEART_COL.size()]))
	var hr: float = 11.0 + 0.9 * float(RarityDB.rank(String(ht.get("rar", "common"))))
	ci.draw_circle(Vector2.ZERO, hr + 5.0, Color(hcol, 0.18 + 0.08 * sin(t * 2.4)))
	ci.draw_circle(Vector2.ZERO, hr, pc.darkened(0.5))
	ci.draw_circle(Vector2.ZERO, hr * 0.7, Color(hcol, 0.75 + 0.2 * sin(t * 3.0)))
	ci.draw_arc(Vector2.ZERO, hr, 0.0, TAU, 24, rar_col(String(ht.get("rar", "common")), t), 1.6)
	_pop(ci, base)


## Plating shell silhouettes by look (radius `R`).
static func _shell_poly(look: int, R: float) -> PackedVector2Array:
	match look % 6:
		1:   # composite: a hexagon
			return _ngon(Vector2.ZERO, R, 6, PI / 6.0)
		2:   # spiked: a 12-point star
			var o: PackedVector2Array = PackedVector2Array()
			for i in 24:
				o.append(Vector2.from_angle(TAU * float(i) / 24.0 - PI * 0.5) * R * (1.12 if i % 2 == 0 else 0.86))
			return o
		3:   # reactive: a round shell
			return _ngon(Vector2.ZERO, R, 28, 0.0)
		4:   # ablative: a decagon
			return _ngon(Vector2.ZERO, R, 10, 0.0)
		5:   # crystal: a faceted gem
			var g: PackedVector2Array = PackedVector2Array()
			for i in 14:
				g.append(Vector2.from_angle(TAU * float(i) / 14.0) * R * (1.0 if i % 2 == 0 else 0.9))
			return g
	return _ngon(Vector2.ZERO, R, 8, PI / 8.0)   # steel: an octagon


static func _plating(ci: CanvasItem, look: int, R: float, pc: Color, sc: Color, t: float, outer: bool) -> void:
	var poly: PackedVector2Array = _shell_poly(look, R)
	ci.draw_colored_polygon(poly, pc)
	match look % 6:
		1:
			_outline(ci, _ngon(Vector2.ZERO, R * 0.78, 6, PI / 6.0), Color(sc, 0.45), 1.5)
		3:   # reactive segments
			for i in 8:
				var a: float = TAU * float(i) / 8.0
				ci.draw_line(Vector2.from_angle(a) * R * 0.7, Vector2.from_angle(a) * R, Color(sc, 0.4), 1.5)
		4:   # ablative layers
			for k in 2:
				_outline(ci, _ngon(Vector2.ZERO, R * (0.82 - 0.1 * float(k)), 10, 0.0), Color(pc.lightened(0.25), 0.8), 1.5)
		5:   # crystal shards
			for i in 7:
				var a2: float = TAU * float(i) / 7.0 + 0.2
				var tip: Vector2 = Vector2.from_angle(a2) * R * 0.95
				ci.draw_colored_polygon(PackedVector2Array([Vector2.from_angle(a2 - 0.12) * R * 0.7, tip, Vector2.from_angle(a2 + 0.12) * R * 0.7]), Color(sc, 0.35 + 0.2 * sin(t * 2.0 + float(i))))
	if outer:
		_outline(ci, poly, Color(sc, 0.5), 1.5)


static func _emitter(ci: CanvasItem, look: int, sc: Color, t: float) -> void:
	var col: Color = [sc, Color("6e9bff"), Color("ff3ea5"), Color("9be8ff")][look % 4]
	var a: float = 0.10 + 0.05 * sin(t * 2.0)
	ci.draw_circle(Vector2.ZERO, 60.0, Color(col, a))
	ci.draw_arc(Vector2.ZERO, 60.0, 0.0, TAU, 40, Color(col, 0.45 + 0.2 * sin(t * 2.0)), 1.6)
	if look % 4 == 2:   # thorn field
		for i in 12:
			var b: float = TAU * float(i) / 12.0 + t * 0.2
			ci.draw_line(Vector2.from_angle(b) * 56.0, Vector2.from_angle(b) * 64.0, Color(col, 0.7), 1.5)


static func _antenna(ci: CanvasItem, look: int, sc: Color, gc: Color, t: float) -> void:
	var masts: int = 2 + look % 2
	for i in masts:
		var a: float = -PI * 0.5 + (float(i) - float(masts - 1) * 0.5) * 0.55
		var p0: Vector2 = Vector2.from_angle(a) * 40.0
		var p1: Vector2 = Vector2.from_angle(a) * (56.0 + 3.0 * float(look % 3))
		ci.draw_line(p0, p1, Color(sc, 0.8), 1.6)
		ci.draw_circle(p1, 2.2, Color(gc, 0.5 + 0.5 * sin(t * 4.0 + float(i) * 1.7)))


static func _uplink(ci: CanvasItem, look: int, at: Vector2, a: float, gc: Color, t: float) -> void:
	var col: Color = [gc, Color("ffd34d"), Color("4ade80"), Color("ff8a3d")][look % 4]
	var d: Vector2 = Vector2.from_angle(a)
	ci.draw_circle(at, 4.5, Color(0.05, 0.07, 0.12, 0.95))
	ci.draw_arc(at + d * 1.5, 5.5, a - 1.1, a + 1.1, 8, col, 1.8)
	ci.draw_circle(at + d * 3.0, 1.3, Color(col, 0.6 + 0.4 * sin(t * 5.0)))


static func _capacitor(ci: CanvasItem, look: int, t: float) -> void:
	var col: Color = [Color("ffd34d"), Color("4ade80"), Color("ff9b3d"), Color("39e6ff")][look % 4]
	for i in 4:
		var a: float = PI * 0.25 + PI * 0.5 * float(i)
		var c: Vector2 = Vector2.from_angle(a) * 33.0
		ci.draw_circle(c, 4.0, Color(0.05, 0.07, 0.12, 0.95))
		for k in 3:
			ci.draw_arc(c, 2.0 + float(k) * 1.2, 0.0, TAU, 8, Color(col, 0.5 + 0.5 * sin(t * 3.0 + float(i))), 0.9)


static func _generator(ci: CanvasItem, look: int, R: float, sc: Color, gc: Color, t: float) -> void:
	match look % 5:
		1:   # shield generator: two counter-rotating arcs
			for k in 3:
				var a: float = t * 1.2 + TAU * float(k) / 3.0
				ci.draw_arc(Vector2.ZERO, R, a, a + 1.4, 8, sc, 2.4)
				ci.draw_arc(Vector2.ZERO, R - 3.0, -a, -a + 1.0, 8, Color(sc, 0.6), 1.4)
		2:   # leech: red tendrils
			for k in 5:
				var b: float = TAU * float(k) / 5.0 + t * 0.5
				ci.draw_line(Vector2.from_angle(b) * (R - 6.0), Vector2.from_angle(b + 0.25) * R, Color("e0365a"), 1.6)
		3:   # fusion: a bright double ring
			ci.draw_arc(Vector2.ZERO, R, 0.0, TAU, 28, Color(gc, 0.8), 2.0)
			ci.draw_arc(Vector2.ZERO, R - 3.0, 0.0, TAU, 28, Color(sc, 0.6 + 0.3 * sin(t * 4.0)), 1.2)
		4:   # surge: a jagged ring
			var o: PackedVector2Array = PackedVector2Array()
			for i in 17:
				o.append(Vector2.from_angle(TAU * float(i) / 16.0 + t * 0.4) * R * (1.0 if i % 2 == 0 else 0.86))
			ci.draw_polyline(o, Color("ffe14d", 0.8), 1.6)
		_:   # repair generator: a gapped ring
			for k in 4:
				var c2: float = t + TAU * float(k) / 4.0
				ci.draw_arc(Vector2.ZERO, R, c2, c2 + 1.1, 8, Color("4ade80", 0.85), 2.2)


# ------------------------------------------------------------------ single part icon

## One part as a card / inventory icon, `size` px across.
static func draw_part(ci: CanvasItem, it: Dictionary, look: Dictionary, center: Vector2, size: float, t: float = 0.0, base: Transform2D = Transform2D.IDENTITY) -> void:
	var P: Dictionary = _paint(look)
	var slot: String = String(it.get("slot", PartDB.slot_of(String(it.get("base", "")))))
	var lk: int = _look(it)
	var rc: Color = rar_col(String(it.get("rar", "common")), t)
	_push(ci, base, center, 0.0, size / 100.0)
	ci.draw_circle(Vector2.ZERO, 46.0, Color(rc, 0.10))
	ci.draw_arc(Vector2.ZERO, 46.0, 0.0, TAU, 40, Color(rc, 0.65), 2.0)
	match slot:
		"receiver":
			_push(ci, base, center, 0.0, size / 100.0 * 2.2)
			_hub(ci, lk, 13.0 + 1.3 * float(RarityDB.rank(String(it.get("rar", "common")))), P, t)
		"barrel":
			_push(ci, base, center + Vector2(-size * 0.36, 0), 0.0, size / 100.0 * 1.45)
			_barrel(ci, String(PartDB.get_def(String(it["base"])).get("frame", "autocannon")), lk, 0.0, P, t)
		"ammo":
			_push(ci, base, center + Vector2(0, size * 0.08), 0.0, size / 100.0 * 4.0)
			_ammo(ci, lk, Vector2.ZERO, P, t)
		"scope":
			_push(ci, base, center + Vector2(-size * 0.12, 0), 0.0, size / 100.0 * 2.8)
			_scope(ci, lk, Vector2.ZERO, P, t)
		"power":
			_push(ci, base, center + Vector2(size * 0.06, 0), 0.0, size / 100.0 * 3.6)
			_power(ci, lk, Vector2.ZERO, P, t)
		"mag":
			_push(ci, base, center, 0.0, size / 100.0 * 3.6)
			_mag(ci, lk, Vector2.ZERO, P, t)
		"muzzle":
			_push(ci, base, center + Vector2(-size * 0.18, 0), 0.0, size / 100.0 * 3.6)
			ci.draw_rect(Rect2(Vector2(-10, -2.5), Vector2(10, 5)), (P["p"] as Color).darkened(0.4))
			_muzzle(ci, lk, Vector2.ZERO, P, t)
		"heart":
			_push(ci, base, center, 0.0, size / 100.0 * 1.6)
			var hcol: Color = _c(String(HEART_COL[lk % HEART_COL.size()]))
			ci.draw_circle(Vector2.ZERO, 22.0, Color(hcol, 0.2 + 0.08 * sin(t * 2.4)))
			ci.draw_circle(Vector2.ZERO, 16.0, (P["p"] as Color).darkened(0.5))
			ci.draw_circle(Vector2.ZERO, 11.0, Color(hcol, 0.8))
		"plating":
			_push(ci, base, center, 0.0, size / 100.0 * 0.85)
			_plating(ci, lk, 44.0, P["p"], P["s"], t, true)
		"generator":
			_push(ci, base, center, 0.0, size / 100.0 * 1.4)
			_generator(ci, lk, 24.0, P["s"], P["g"], t)
			ci.draw_circle(Vector2.ZERO, 8.0, Color(P["s"], 0.6))
		"capacitor":
			_push(ci, base, center, 0.0, size / 100.0 * 0.95)
			_capacitor(ci, lk, t)
		"reactor":
			_push(ci, base, center, 0.0, size / 100.0 * 1.3)
			var rcol: Color = _c(String(REACTOR_COL[lk % REACTOR_COL.size()]))
			ci.draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 36, Color(rcol, 0.7 + 0.25 * sin(t * 2.0)), 5.0)
			ci.draw_circle(Vector2.ZERO, 10.0, Color(rcol, 0.5))
		"uplink":
			_push(ci, base, center + Vector2(0, size * 0.08), 0.0, size / 100.0 * 3.2)
			_uplink(ci, lk, Vector2.ZERO, -PI * 0.5, P["g"], t)
		"antenna":
			_push(ci, base, center + Vector2(0, size * 0.42), 0.0, size / 100.0 * 0.9)
			_antenna(ci, lk, P["s"], P["g"], t)
		"emitter":
			_push(ci, base, center, 0.0, size / 100.0 * 0.7)
			_emitter(ci, lk, P["s"], t)
	_pop(ci, base)
