extends RefCounted
## Run screen (REDESIGN_SPEC §5 battlefield): centred field (Core + 7x7
## roguelite grid + troops + enemies + fx), left panel (draft / place / info,
## ui/DraftPanel.gd), right panel (Core portrait, HP, cash, stats and the 5
## cash tracks), bottom hotbar (specials 1-4, ui/Hotbar.gd) and the results
## modal. Every value is shown once. View only: reads TowerState, replays its
## events (core_attack, special_cast, troop_*), never decides outcomes.

const TowerState := preload("res://TowerState.gd")
const PickDB := preload("res://data/PickDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const Tiers := preload("res://Tiers.gd")
const Roll := preload("res://vfx/Roll.gd")
const Kit := preload("res://ui/Kit.gd")
const DraftPanel := preload("res://ui/DraftPanel.gd")
const Hotbar := preload("res://ui/Hotbar.gd")
const Intel := preload("res://ui/Intel.gd")

const ENEMY2: Color = Kit.MAGENTA
const SHIELD: Color = Color("7fd8ff")
const TRACK_ICON: Dictionary = {"dmg": "pk_arsenal", "rate": "pk_overclock", "range": "pk_optics", "eco": "pk_ledger", "armor": "pk_fort"}
const TRACK_TIP: Dictionary = {
	"dmg": "Damage enhancement: x1.08 Core and building damage per level",
	"rate": "Rate enhancement: +3% Core attack rate per level",
	"range": "Range enhancement: +0.1 cell Core range per level",
	"eco": "Eco enhancement: +0.4 cash/s and +5 interest cap per level",
	"armor": "Armor enhancement: +5% Core HP, +0.2 regen and +0.5 armor per level",
}


static func speed_str(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.01 else "%.1f" % v


static func pick_name(id: String) -> String:
	return String(PickDB.get_def(id).get("name", id))


# ===================================================================== build
static func build(m) -> void:
	var S = m.S
	if S == null:
		return
	DraftPanel.build(m)
	Hotbar.build(m)
	var rr: Rect2 = m.right_rect()
	var x: float = rr.position.x + 16.0
	var w: float = rr.size.x - 32.0
	var ty: float = track_y(m)
	var th: float = track_h(m)
	for k in TowerState.TRACK_IDS.size():
		var tid: String = TowerState.TRACK_IDS[k]
		var c: int = S.track_cost(tid)
		var td: Dictionary = TowerState.TRACKS[tid]
		var tip: String = "%s\nLevel %d / %d  ·  next $%d\n%s  ·  %s" % [String(TRACK_TIP[tid]), int(S.tracks[tid]), int(S.track_cap(tid)), maxi(0, c), String(td["desc"]), String(td.get("minus", ""))]
		Kit.hit(m, Rect2(x, ty + k * (th + 6.0), w, th), func() -> void: m.buy_track(tid), tip, "TRACK " + String(td["name"]), c >= 0 and S.cash >= float(c), Kit.GREEN)
	if m.sel >= 0 and S.is_weapon_slot(m.sel) and m.sel != TowerState.CORE_SLOT:
		var i: int = m.sel
		# floats on the field just under the selected weapon (left bar = Perks)
		var cs: float = TowerState.CELL * m.world_scale()
		var cp: Vector2 = m.w2s(TowerState.slot_pos(i)) + Vector2(0, cs * 0.5 + 6.0)
		var fr0: Rect2 = m.field_rect()
		var tr0 := Rect2(clampf(cp.x - 110.0, fr0.position.x + 4.0, fr0.end.x - 224.0), clampf(cp.y, fr0.position.y + 4.0, fr0.end.y - 150.0), 220, 40)
		Kit.btn(m, "Target: %s" % String(S.target_modes[i]).capitalize(), tr0, func() -> void: m._handle(S.cycle_target_mode(i)); m._rebuild_ui(), "Cycle this weapon's targeting mode (nearest / first / strongest / weakest)", true, Kit.ENEMY, "Target:")


static func track_h(m) -> float:
	return clampf((m.vh - 1080.0) * 0.05 + 62.0, 50.0, 66.0)


static func track_y(m) -> float:
	var rr: Rect2 = m.right_rect()
	return rr.end.y - 5.0 * (track_h(m) + 6.0) - 46.0


static func build_results(m) -> void:
	var r: Rect2 = results_rect(m)
	var bw: float = (r.size.x - 72.0) * 0.5
	Kit.btn(m, "Back to base", Rect2(r.position.x + 24, r.end.y - 76, bw, 56), m.go_base, "Return to the hub to spend your loot", true, Kit.RUST, "DBACK", "", 22)
	Kit.btn(m, "Play again", Rect2(r.position.x + 48 + bw, r.end.y - 76, bw, 56), func() -> void: m.start_run(), "Start a new run (every run is randomly seeded)", true, Kit.GREEN, "PLAY AGAIN", "", 20)


static func results_rect(m) -> Rect2:
	var fr: Rect2 = m.field_rect()
	var w: float = minf(fr.size.x - 40.0, 780.0)
	var h: float = minf(fr.size.y - 40.0, 760.0)
	return Rect2(fr.get_center().x - w * 0.5, fr.get_center().y - h * 0.5, w, h)


## Why `id` cannot go on cell `i` right now ("" when it can).
static func place_reason(m, i: int, id: String) -> String:
	var S = m.S
	if i < 0:
		return "Not a cell"
	if i == TowerState.CORE_SLOT:
		return "The Core"
	if not bool(S.unlocked[i]):
		return "Ring %d is closed (buy Core Enhancements)" % TowerState.ring_of(i)
	if S.id_at(i) != "":
		return "Occupied"
	if not S.can_place(i, id):
		return "Ring 2+ only" if id == "railgun" else ("Build cap reached" if S.at_cap() else "Can't place here")
	return ""


# ====================================================================== fx
static func core_attack_fx(m, ev: Dictionary) -> void:
	var S = m.S
	if S == null:
		return
	var c: Vector2 = TowerState.CENTER
	var kind: String = String(ev.get("kind", "cannon"))
	var tg: Array = ev.get("targets", [])
	match kind:
		"pulse":
			var cw: Dictionary = (S.stats["weapons"] as Array).back()
			m._ring(c, float(cw.get("range", 200.0)), 0.35, Kit.LAB)
		"beam":
			pass   # drawn continuously from S.beam_eid
		_:
			for eid in tg:
				var p: Variant = m.enemy_pos(int(eid))
				if p == null:
					continue
				var col: Color = Color("ffd36b") if kind == "cannon" else Color("ff8a3a")
				m._tracer(c, p as Vector2, col, 3.0 if kind == "cannon" else 5.0, 0.14)
				m._ring(p as Vector2, 22.0 if kind == "cannon" else 40.0, 0.25, col)


static func special_fx(m, ev: Dictionary) -> void:
	var c: Vector2 = TowerState.CENTER
	var id: String = String(ev.get("id", ""))
	match id:
		"sp_emp":
			m._ring(c, 420.0, 0.6, Kit.CYAN)
			m._ring(c, 260.0, 0.45, Kit.CYAN)
		"sp_repair":
			m.heal_flash = 0.6
		"sp_overdrive":
			m._ring(c, 80.0, 0.5, Kit.GOLD)
		"sp_magnet":
			m._pop(c + Vector2(0, -90), "CASH x2", 1.2, Kit.GREEN, 24)
		"sp_timewarp":
			m._ring(c, 460.0, 0.8, Color.WHITE)
	m._pop(c + Vector2(0, -120), pick_name(id).to_upper(), 1.0, Kit.GEM, 22)


# ================================================================ tooltips
static func world_tip(m, p: Vector2) -> String:
	var S = m.S
	if S == null or S.pending_place != "" or m.drag_card >= 0:
		return ""   # the placement preview carries the cell state
	var wp: Vector2 = m.s2w(p)
	var best: float = 22.0
	var found: Dictionary = {}
	var en = S.en
	for s in S.eh.candidates(wp, maxf(best, en.max_size)):
		var dd: float = en.pos[s].distance_to(wp)
		if dd < maxf(best, en.size[s]):
			best = dd
			found = en.get_dict(s)
	if not found.is_empty():
		return "%s\nHP %d / %d" % [String(Intel.NAMES.get(String(found["kind"]), String(found["kind"]).capitalize())), int(ceil(float(found["hp"]))), int(float(found["max_hp"]))]
	for t in S.troops:
		var td: Dictionary = t
		if String(td.get("state", "")) != "dead" and (td["pos"] as Vector2).distance_to(wp) < 14.0:
			return "%s (troop)\nHP %d / %d" % [String(td["kind"]).capitalize(), int(ceil(float(td["hp"]))), int(float(td["max_hp"]))]
	var i: int = m.slot_at(wp)
	if i >= 0:
		return cell_text(m, i)
	return ""


static func cell_text(m, i: int) -> String:
	var S = m.S
	var ring: int = TowerState.ring_of(i)
	if i == TowerState.CORE_SLOT:
		var cd: Dictionary = CoreDB.get_def(S.core_id)
		return "The Core  Lv%d\n%s: %s" % [int(S.core_lvl), String(cd["attack_name"]), String(cd["attack_desc"])]
	if not bool(S.unlocked[i]):
		return "Outside your grid\nResearch Grid Expansion to build here"
	var id: String = S.id_at(i)
	if id == "":
		return "Empty cell (ring %d)\nDraft a building and drop it here" % ring
	var d: Dictionary = PickDB.get_def(id)
	var up: String = "\nClick to apply the %s upgrade here" % pick_name(S.pending_upgrade) if S.pending_upgrade == id and S.upgrade_targets(id).has(i) else ""
	return "%s  Lv%d / %d  (%s)\nHP %d / %d\n%s%s" % [String(d["name"]), S.lvl_at(i), PickDB.max_of(id), String(d["rarity"]).capitalize(), int(S.bld_hp[i]), int(S.bld_max(i)), String(d["desc"]), up]


# ================================================================== ranges
## Base weapon reach in cells (TowerState weapon table) for a building that is
## not on the grid yet (placement preview).
const BASE_RANGE: Dictionary = {"gun": 3.0, "mortar": 4.5, "tesla": 3.0, "flak": 3.5, "railgun": 7.0, "frost": 2.5}


## World-space reach of the building on cell i: weapons use their live range,
## every other building its aura (the 8 neighbouring cells). {} = none.
static func range_of(m, i: int) -> Dictionary:
	var S = m.S
	if S == null or i < 0:
		return {}
	for wv in (S.stats.get("weapons", []) as Array):
		var wd: Dictionary = wv
		if int(wd.get("slot", -2)) == i:
			return {"r": float(wd.get("range", 0.0)), "kind": "weapon"}
	if i != TowerState.CORE_SLOT and S.id_at(i) != "":
		return {"r": TowerState.CELL * 1.5, "kind": "aura"}
	return {}


## Reach of `id` if it were placed now (live range of a placed twin, else base).
static func preview_range(m, id: String) -> Dictionary:
	var S = m.S
	if BASE_RANGE.has(id):
		for wv in (S.stats.get("weapons", []) as Array):
			var wd: Dictionary = wv
			if String(wd.get("kind", "")) == id:
				return {"r": float(wd.get("range", 0.0)), "kind": "weapon"}
		return {"r": float(BASE_RANGE[id]) * TowerState.cpx(), "kind": "weapon"}
	return {"r": TowerState.CELL * 1.5, "kind": "aura"}


static func draw_reach(m, c: Vector2, rg: Dictionary, col: Color) -> void:
	if rg.is_empty():
		return
	var r: float = float(rg["r"])
	if String(rg["kind"]) == "aura":
		var rect := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		m.draw_rect(rect, Color(col, 0.08))
		m.draw_rect(rect, Color(col, 0.6), false, 2.0)
		return
	m.draw_circle(c, r, Color(col, 0.07))
	m.draw_arc(c, r, 0, TAU, 96, Color(col, 0.6), 2.0)


## Owner feedback #1: clicking (selecting) any building shows its range.
static func _draw_ranges(m) -> void:
	var S = m.S
	if m.sel >= 0 and m.sel != TowerState.CORE_SLOT and S.id_at(m.sel) != "":
		draw_reach(m, TowerState.slot_pos(m.sel), range_of(m, m.sel), Kit.GEM)
		m.set_meta("range_shown", m.sel)
	else:
		m.set_meta("range_shown", -1)


# ===================================================================== draw
static func draw(m, off: Vector2) -> void:
	var S = m.S
	var fr: Rect2 = m.field_rect()
	_draw_field_bg(m, fr)
	if S != null:
		m.draw_set_transform_matrix(Transform2D(0.0, off) * m.world_xform())
		if m.gore != null and String(m.gore.get("level")) != "off":
			var gt: Texture2D = m.gore.call("ground_texture")
			if gt != null:
				m.draw_texture_rect(gt, m.gore.call("ground_rect"), false)   # HORDE P5 corpse/blood layer
		_draw_grid(m)
		_draw_ranges(m)
		_draw_world(m)
		_draw_fx(m)
		m.draw_set_transform(Vector2.ZERO)
		_draw_field_hud(m, fr)
	if m.flash > 0.0:
		m.draw_rect(fr, Color(0.9, 0.15, 0.2, m.flash * 0.35))
	if m.heal_flash > 0.0:
		m.draw_rect(fr, Color(0.4, 0.9, 0.4, m.heal_flash * 0.3))
	if S != null:
		Hotbar.draw(m)
		DraftPanel.draw(m)
		_draw_right(m)
		_draw_ghost(m)
	if m.screen == "results":
		_draw_results(m)


static func _draw_field_bg(m, fr: Rect2) -> void:
	m.draw_rect(fr, Kit.BG2)
	var gc := Color(1, 1, 1, 0.025)
	var x: float = fr.position.x
	while x <= fr.end.x:
		m.draw_line(Vector2(x, fr.position.y), Vector2(x, fr.end.y), gc, 1.0)
		x += 48.0
	var y: float = fr.position.y
	while y <= fr.end.y:
		m.draw_line(Vector2(fr.position.x, y), Vector2(fr.end.x, y), gc, 1.0)
		y += 48.0


static func _draw_grid(m) -> void:
	var S = m.S
	var C: Vector2 = TowerState.CENTER
	var c: float = TowerState.CELL
	# spawn ring (enemies come from every direction)
	m.draw_arc(C, float(S.spawn_r()), 0, TAU, 128, Color(1, 1, 1, 0.07), 2.0)
	var hs: float = float(S.grid_n) * 0.5
	var goff: Vector2 = Vector2(0.5, 0.5) * c if S.grid_n % 2 == 0 else Vector2.ZERO
	var plate := Rect2(C + goff - Vector2(hs * c + 8, hs * c + 8), Vector2(2.0 * hs * c + 16, 2.0 * hs * c + 16))
	m.draw_rect(plate, Kit.BG)
	m.draw_rect(plate, Color(Kit.RUST, 0.55), false, 3.0)
	var placing: bool = S.pending_place != "" or m.drag_card >= 0
	for i in TowerState.N:
		var p: Vector2 = TowerState.slot_pos(i)
		var sc: float = 1.0
		if m.slot_pop.has(i):
			sc = 1.0 + 0.3 * float(m.slot_pop[i]) / 0.3
		var half: float = (c * 0.5 - 3.0) * sc
		var r := Rect2(p - Vector2(half, half), Vector2(half * 2, half * 2))
		if i == TowerState.CORE_SLOT or not S.in_grid(i):
			continue
		if not bool(S.unlocked[i]):
			m.draw_rect(r, Color("0e1528"))
			m.draw_rect(r.grow(-6), Color(1, 1, 1, 0.025), false, 1.0)
			continue
		var id: String = S.id_at(i)
		if id == "":
			var oc := Kit.EDGE2
			var fill := Color("121b31")
			if placing and (S.pending_place == "" or S.can_place(i, S.pending_place)):
				# Floor the pulse so valid cells always read as "glowing".
				oc = Color(Kit.GREEN, 0.7 + 0.25 * sin(m.t_anim * 8.0))
				fill = Color("121b31").lerp(Kit.GREEN, 0.12)
			m.draw_rect(r, fill)
			m.draw_rect(r, oc, false, 2.0)
		else:
			var rc: Color = Kit.rarity_col(PickDB.rarity_of(id))
			m.draw_rect(r, Color(rc, 0.12))
			if not Kit.icon(m, id, r.grow(2)):
				m.draw_rect(r.grow(-6), rc)
			var lv: int = S.lvl_at(i)
			for k in lv:
				m.draw_rect(Rect2(r.position + Vector2(4 + k * 7, r.size.y - 7), Vector2(5, 4)), Kit.GOLD)
			# building HP (enemies attack buildings in their way)
			var bmx: float = float(S.bld_max(i))
			if bmx > 0.0 and float(S.bld_hp[i]) < bmx:
				var f: float = clampf(float(S.bld_hp[i]) / bmx, 0.0, 1.0)
				m.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 4)), Color(0, 0, 0, 0.6))
				m.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * f, 4)), Kit.GREEN.lerp(Kit.ENEMY, 1.0 - f))
			# pending upgrade: glow the buildings it can be applied to
			if S.pending_upgrade == id and S.upgrade_targets(id).has(i):
				m.draw_rect(r.grow(3), Color(Kit.GOLD, 0.6 + 0.35 * sin(m.t_anim * 8.0)), false, 3.0)
		if i == m.sel:
			m.draw_rect(r.grow(4), Color(1, 1, 1, 0.9), false, 3.0)
	# Core
	var cw: Dictionary = (S.stats["weapons"] as Array).back() if (S.stats.get("weapons", []) as Array).size() > 0 else {}
	if m.sel == TowerState.CORE_SLOT or m.mouse_pos.distance_to(m.w2s(C)) < c * m.world_scale():
		m.draw_circle(C, float(cw.get("range", 200.0)), Color(Kit.GEM, 0.05))
		m.draw_arc(C, float(cw.get("range", 200.0)), 0, TAU, 96, Color(Kit.GEM, 0.5), 2.0)
	var pulse: float = 0.5 + 0.5 * sin(m.t_anim * 3.0)
	var cr: float = c * 0.78
	m.draw_circle(C, cr + 8.0 + 4.0 * pulse, Color(1, 1, 1, 0.06))
	if not Kit.icon(m, "core_bastion", Rect2(C - Vector2(cr, cr), Vector2(cr, cr) * 2.0)):
		m.draw_circle(C, cr, Kit.RUST)
	if float(S.shield) > 0.0:
		var smax: float = maxf(1.0, float(S.stats.get("shield_max", 1.0)))
		m.draw_arc(C, cr + 6.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(S.shield) / smax, 0.0, 1.0), 48, SHIELD, 3.0)


static func _draw_world(m) -> void:
	var S = m.S
	# Lance beam
	if int(S.beam_eid) >= 0:
		var bp: Variant = m.enemy_pos(int(S.beam_eid))
		if bp != null:
			var ramp: float = clampf(float(S.beam_t) / 6.0, 0.0, 1.0)
			m.draw_line(TowerState.CENTER, bp as Vector2, Color(0.5, 0.95, 1.0, 0.25), 10.0 + 8.0 * ramp)
			m.draw_line(TowerState.CENTER, bp as Vector2, Color(0.85, 1.0, 1.0, 0.9), 2.0 + 3.0 * ramp)
	# pending Orbital Strikes
	for o in S.orbitals:
		var od: Dictionary = o
		var op: Vector2 = od["pos"]
		m.draw_arc(op, float(od["r"]), 0, TAU, 40, Color(Kit.GOLD, 0.8), 2.0)
		m.draw_circle(op, float(od["r"]) * (1.0 - clampf(float(od["t"]) / 0.8, 0.0, 1.0)), Color(Kit.GOLD, 0.18))
	# troops
	for t in S.troops:
		var td: Dictionary = t
		if String(td.get("state", "")) == "dead":
			continue
		var tp: Vector2 = td["pos"]
		var tk: String = String(td.get("kind", "rifleman"))
		var tr := Rect2(tp - Vector2(11, 11), Vector2(22, 22))
		if not Kit.icon(m, "troop_" + tk, tr):
			m.draw_circle(tp, 7.0, Kit.GREEN)
		var hf: float = float(td["hp"]) / maxf(1.0, float(td["max_hp"]))
		if hf < 1.0:
			m.draw_rect(Rect2(tp + Vector2(-9, 12), Vector2(18, 3)), Color(0, 0, 0, 0.6))
			m.draw_rect(Rect2(tp + Vector2(-9, 12), Vector2(18 * hf, 3)), Kit.GREEN)
	# enemies (HORDE Phase 2): one MultiMesh per kind from the SVG icon,
	# per-instance colour = hit flash / slow tint; overlays + HP bars only on
	# the few special bodies (elite / boss / marked / courier).
	_draw_enemies(m, S.en)


## kind -> MultiMesh (reused every frame; instance buffer refilled from SoA)
static var _mm: Dictionary = {}
static var _quad: ArrayMesh = null
static var _buf: Dictionary = {}   # kind -> PackedFloat32Array
static var _cnt: Dictionary = {}   # kind -> int
static var _fb_tex: Texture2D = null
const EnemyStoreRef := preload("res://EnemyStore.gd")


## Kinds without art draw as a soft enemy-red disc (one shared texture).
static func _fallback_tex() -> Texture2D:
	if _fb_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(Kit.ENEMY, 1.0))
		g.set_color(1, Color(Kit.ENEMY, 0.0))
		g.add_point(0.55, Kit.ENEMY)
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 32
		gt.height = 32
		_fb_tex = gt
	return _fb_tex


static func _unit_quad() -> ArrayMesh:
	if _quad == null:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		_quad = ArrayMesh.new()
		_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _quad


## FB2 render interpolation: the sim moves bodies in fixed 0.05 s substeps, so
## between steps the view advances each walker by its current seek speed times
## the unconsumed step time (S.step_acc / speed-scaled), toward its goal and never
## past it. View-only: the sim state is never touched.
static func rpos(m, en, es: int) -> Vector2:
	var p: Vector2 = en.pos[es]
	var S = m.S
	if S == null:
		return p
	var cs: float = en.cur_s[es]
	if cs <= 0.0:
		return p
	var lead: float = clampf(float(S.step_acc), 0.0, TowerState.SUBSTEP)
	var goal: Vector2 = en.exit[es] if en.kind[es] == "courier" else TowerState.CENTER
	var d: Vector2 = goal - p
	var dist: float = d.length()
	if dist < 1.0:
		return p
	return p + d / dist * minf(dist * 0.5, cs * lead)


static func _draw_enemies(m, en) -> void:
	# MASS_HORDE §View: C# writes every live body into one buffer per visual
	# kind (transform + colour, stacked: density shading, slow tint, elite / marked tint
	# shading, surge flare) and uploads each with one MultimeshSetBuffer call.
	# GDScript never iterates bodies here.
	var t0: int = Time.get_ticks_usec()
	var S = m.S
	var w: Object = en.world
	var nvk: int = EnemyStoreRef.VIS_KINDS.size()
	var lead: float = clampf(float(S.step_acc), 0.0, TowerState.SUBSTEP) if S != null else 0.0
	var half: float = float(S.spawn_r()) + 200.0 if S != null else 1300.0
	var info: PackedInt32Array = w.call("RenderPrep", nvk, lead, TowerState.HIT_FLASH, TowerState.CENTER.x, TowerState.CENTER.y, half)
	for vk in nvk:
		var n2: int = info[vk * 2]
		if n2 <= 0:
			continue
		var kind: String = EnemyStoreRef.VIS_KINDS[vk]
		var tx: Texture2D = Kit.Art.tex(kind)
		var mm: MultiMesh = _mm.get(kind, null)
		if mm == null:
			mm = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_2D
			mm.use_colors = true
			mm.mesh = _unit_quad()
			_mm[kind] = mm
		var capi: int = info[vk * 2 + 1]
		if mm.instance_count != capi:
			mm.instance_count = capi
		w.call("Upload", mm.get_rid(), vk)
		if tx == null:
			tx = _fallback_tex()
		m.draw_multimesh(mm, tx)
	var special: PackedInt32Array = w.call("Specials")
	m.dbg_render_ms = lerpf(float(m.dbg_render_ms), float(Time.get_ticks_usec() - t0) / 1000.0, 0.2)
	for es in special:
		var p: Vector2 = rpos(m, en, es)
		var s: float = en.size[es]
		var kind: String = en.kind[es]
		var col: Color = ENEMY2 if kind in ["skitter", "boss", "mite", "splitter"] else Kit.ENEMY
		var hitr := Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0)
		if en.is_marked(es):
			m.draw_arc(p, s * 1.3, 0, TAU, 24, Kit.GOLD, 2.0)
		if en.shield[es] > 0:
			if not Kit.icon(m, "elite_shield", hitr.grow(s * 0.3)):
				m.draw_arc(p, s * 1.2, 0, TAU, 24, SHIELD, 3.0)
		var frac: float = en.hp[es] / en.max_hp[es]
		if frac < 1.0:
			m.draw_rect(Rect2(p + Vector2(-s * 0.6, s * 0.85), Vector2(s * 1.2, 4)), Color(0, 0, 0, 0.6))
			m.draw_rect(Rect2(p + Vector2(-s * 0.6, s * 0.85), Vector2(s * 1.2 * frac, 4)), col.lightened(0.3))


static func _draw_fx(m) -> void:
	for bd in m.bolts.items:
		if float(bd["t"]) <= 0.0:
			continue
		var bp: Vector2 = (bd["a"] as Vector2).lerp(TowerState.CENTER, 1.0 - float(bd["t"]) / 0.25)
		if not Kit.icon(m, "bolt", Rect2(bp - Vector2(12, 12), Vector2(24, 24))):
			m.draw_circle(bp, 5.0, Kit.ENEMY)
	for fd in m.tracers.items:
		if float(fd["t"]) <= 0.0:
			continue
		var a: float = float(fd["t"]) / maxf(0.01, float(fd["life"]))
		var tc: Color = fd["color"]
		m.draw_line(fd["a"], fd["b"], Color(tc, 0.18 * a), float(fd["w"]) * 3.0)
		m.draw_line(fd["a"], fd["b"], Color(tc, 0.55 * a), float(fd["w"]))
		# Owner feedback #1: every shot draws a visible projectile travelling
		# from the muzzle to the target over the tracer's life.
		var hp: Vector2 = (fd["a"] as Vector2).lerp(fd["b"] as Vector2, minf(1.0, (1.0 - a) * 1.6))
		var pr: float = 3.0 + float(fd["w"]) * 1.2
		m.draw_circle(hp, pr * 1.9, Color(tc, 0.3))
		m.draw_circle(hp, pr, Color(tc.lightened(0.5), 1.0))
	for fd2 in m.rings.items:
		if float(fd2["t"]) <= 0.0:
			continue
		var rc: Color = fd2["color"]
		var k: float = 1.0 - float(fd2["t"]) / maxf(0.01, float(fd2["life"]))
		m.draw_arc(fd2["pos"], float(fd2["r"]) * (0.3 + 0.7 * k), 0, TAU, 40, Color(rc, minf(1.0, float(fd2["t"]) * 4.0)), 3.0)
	if m.level_burst > 0.0:
		var k2: float = 1.0 - m.level_burst / 0.6
		m.draw_arc(TowerState.CENTER, 40.0 + 300.0 * k2, 0, TAU, 96, Color(Kit.GREEN, 1.0 - k2), 6.0)
	for dn in m.dmgnums.items:
		var dt: float = float(dn["t"])
		if dt <= 0.0:
			continue
		var age: float = float(dn["life"]) - dt
		var dsz: int = int(dn["size"])
		var pun: float = 1.0 + maxf(0.0, 0.12 - age) * 3.0
		var dc: Color = Color("fff2c0") if dsz >= 24 else Color(1, 1, 1)
		var dp: Vector2 = (dn["pos"] as Vector2) + Vector2(float(int(dn["eid"]) * 37 % 31) - 15.0, -18.0 - age * 50.0)
		var da: float = minf(1.0, dt * 3.0)
		# HORDE P6 readability: a dark drop shadow under each aggregated number
		Kit.t(m, Kit.fmt(float(dn["amt"])), dp + Vector2(1.5, 1.5), int(float(dsz) * pun), Color(0, 0, 0, 0.8 * da), HORIZONTAL_ALIGNMENT_CENTER, 120.0)
		Kit.t(m, Kit.fmt(float(dn["amt"])), dp, int(float(dsz) * pun), Color(dc, da), HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	for fd3 in m.pops.items:
		if float(fd3["t"]) <= 0.0:
			continue
		var pp: Vector2 = fd3["pos"]
		var lift: float = (1.0 - float(fd3["t"])) * 30.0
		var pc: Color = fd3["color"]
		Kit.t(m, String(fd3["text"]), pp - Vector2(0, lift), int(fd3["size"]), Color(pc, minf(1.0, float(fd3["t"]) * 2.5)), HORIZONTAL_ALIGNMENT_CENTER, 600.0)


## Field banners: incoming wave, placement / aim prompts, Insight fanfare.
static func _draw_field_hud(m, fr: Rect2) -> void:
	var S = m.S
	var cx: float = fr.get_center().x
	if not S.next_plan.is_empty():
		var txt: String = "WAVE %d INCOMING  ·  %d enemies%s" % [int(S.next_plan.get("wave", 0)), (S.next_plan.get("entries", []) as Array).size(), "  ·  BOSS" if bool(S.next_plan.get("boss", false)) else ""]
		Kit.panel(m, Rect2(cx - 230, fr.position.y + 12, 460, 40), Kit.ENEMY, Color(0.16, 0.06, 0.07, 0.9))
		Kit.t(m, txt, Vector2(cx, fr.position.y + 39), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 440.0)
	var prompt: String = ""
	if m.aim_special >= 0 and m.aim_special < S.specials.size():
		prompt = "Click the field to drop %s  ·  %s again = auto-target  ·  right-click cancels" % [pick_name(String((S.specials[m.aim_special] as Dictionary)["id"])), Kit.hint(m, "hotbar_%d" % (m.aim_special + 1))]
		if fr.has_point(m.mouse_pos):
			var rr: float = 1.5 * TowerState.cpx() * m.world_scale()
			m.draw_arc(m.mouse_pos, rr, 0, TAU, 48, Kit.GOLD, 2.0)
			m.draw_circle(m.mouse_pos, rr, Color(Kit.GOLD, 0.1))
	elif S.pending_place != "":
		prompt = "Place %s: click a glowing cell  ·  %s cancels" % [pick_name(S.pending_place), Kit.hint(m, "cancel")]
	elif S.pending_upgrade != "":
		prompt = "Upgrade %s: click (or drag onto) a glowing %s  ·  %s cancels" % [pick_name(S.pending_upgrade), pick_name(S.pending_upgrade), Kit.hint(m, "cancel")]
	elif m.banish_mode:
		prompt = "Banish: click a draft card to remove it from this run"
	if prompt != "":
		var pw: float = minf(fr.size.x - 20.0, 24.0 + m.font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)
		var py: float = m.hot_rect().position.y - 48.0   # above the floating abilities
		Kit.panel(m, Rect2(cx - pw * 0.5, py, pw, 40), Kit.GOLD, Color(0.14, 0.12, 0.06, 0.92))
		Kit.t(m, prompt, Vector2(cx, py + 27), 17, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, pw - 16.0)
	if m.insight_t > 0.0:
		var a: float = clampf(m.insight_t, 0.0, 1.0)
		var s: float = 1.0 + maxf(0.0, m.insight_t - 2.0) * 0.6
		var r := Rect2(cx - 260 * s, fr.get_center().y - 230, 520 * s, 92)
		Kit.panel(m, r, Color(Kit.RARITY["insight"], a), Color(0.04, 0.12, 0.12, 0.92 * a), 3)
		Kit.icon(m, "insight", Rect2(r.position.x + 14, r.position.y + 10, 72, 72), Color(1, 1, 1, a))
		Kit.t(m, "INSIGHT FOUND", Vector2(r.position.x + 100, r.position.y + 38), 26, Color(Kit.RARITY["insight"], a), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 110)
		Kit.t(m, "%s — banked permanently at run end" % m.insight_name, Vector2(r.position.x + 100, r.position.y + 68), 17, Color(Kit.TEXT, a), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 110)


## Placement preview (owner feedback #1): while a building is being placed —
## a dragged NEW-building card or a taken pick waiting for a cell — the cursor
## becomes the building with its range radius, tinted green (valid) or red
## (invalid, with the reason) on the hovered cell.
static func _draw_ghost(m) -> void:
	var S = m.S
	var id: String = ""
	var is_new: bool = true
	if m.drag_card >= 0 and m.drag_card < S.draft.size() and m.mouse_pos.distance_to(m.drag_start) > 12.0:
		id = String((S.draft[m.drag_card] as Dictionary)["id"])
		is_new = String((S.draft[m.drag_card] as Dictionary).get("kind", "")) == "new"
	elif S.pending_place != "" and m.field_rect().has_point(m.mouse_pos):
		id = S.pending_place
	elif S.pending_upgrade != "" and m.field_rect().has_point(m.mouse_pos):
		id = S.pending_upgrade
		is_new = false
	if id == "":
		m.set_meta("ghost_reason", "")
		m.set_meta("ghost_id", "")
		return
	var reason: String = "Drop on a cell"
	var cs: float = TowerState.CELL * m.world_scale()
	var at: Vector2 = m.mouse_pos
	var ok: bool = false
	if m.field_rect().has_point(m.mouse_pos):
		var i: int = m.slot_at(m.s2w(m.mouse_pos))
		if i >= 0:
			if is_new:
				reason = place_reason(m, i, id)
			elif S.pending_upgrade != "" or (m.drag_card >= 0 and String((S.draft[m.drag_card] as Dictionary).get("kind", "")) == "plus"):
				reason = "" if S.id_at(i) == id else "Drop on your %s" % pick_name(id)
			else:
				reason = "Release to take this pick"
			ok = reason == "" or reason.begins_with("Release")
			at = m.w2s(TowerState.slot_pos(i))
			var cr := Rect2(at - Vector2(cs, cs) * 0.5, Vector2(cs, cs))
			m.draw_rect(cr, Color(Kit.GREEN, 0.25) if ok else Color(Kit.ENEMY, 0.25))
			m.draw_rect(cr, Kit.GREEN if ok else Kit.ENEMY, false, 3.0)
			if is_new and (S.pending_place != "" or m.drag_card >= 0):
				var rg: Dictionary = preview_range(m, id)
				var sr: float = float(rg["r"]) * m.world_scale()
				var rc: Color = Kit.GREEN if ok else Kit.ENEMY
				if String(rg["kind"]) == "aura":
					var ar := Rect2(at - Vector2(sr, sr), Vector2(sr, sr) * 2.0)
					m.draw_rect(ar, Color(rc, 0.08))
					m.draw_rect(ar, Color(rc, 0.7), false, 2.0)
				else:
					m.draw_circle(at, sr, Color(rc, 0.08))
					m.draw_arc(at, sr, 0, TAU, 96, Color(rc, 0.7), 2.0)
	var gs: float = maxf(48.0, cs * 0.9)
	Kit.icon(m, id, Rect2(at - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), Color(0.6, 1.0, 0.6, 0.85) if ok else Color(1.0, 0.55, 0.55, 0.8))
	if reason != "" and not ok:
		var tw: float = 24.0 + m.font.get_string_size(reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		Kit.panel(m, Rect2(m.mouse_pos + Vector2(36, -16), Vector2(tw, 34)), Kit.ENEMY, Color(0.1, 0.05, 0.05, 0.92))
		Kit.t(m, reason, m.mouse_pos + Vector2(48, 8), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, tw - 16.0)
	m.set_meta("ghost_reason", reason)
	m.set_meta("ghost_id", id)


static func _draw_right(m) -> void:
	var S = m.S
	var rr: Rect2 = m.right_rect()
	m.draw_rect(rr, Kit.PANEL)
	m.draw_line(rr.position, Vector2(rr.position.x, rr.end.y), Kit.EDGE, 2.0)
	var x: float = rr.position.x + 16.0
	var w: float = rr.size.x - 32.0
	var y: float = rr.position.y + 14.0
	var cd: Dictionary = CoreDB.get_def(S.core_id)
	# portrait
	Kit.panel(m, Rect2(x, y, 96, 96), Kit.RUST, Kit.BG2)
	Kit.icon(m, "core_bastion", Rect2(x + 6, y + 6, 84, 84))
	Kit.t(m, "The Core", Vector2(x + 110, y + 26), 22, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
	Kit.t(m, "Lv %d" % int(S.core_lvl), Vector2(x + 110, y + 50), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
	Kit.t(m, String(cd["attack_name"]), Vector2(x + 110, y + 74), 16, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
	m.stat_tips.append([Rect2(x, y, w, 96), "%s\n%s" % [String(cd["attack_name"]), String(cd["attack_desc"])]])
	y += 108.0
	# HP + shield
	var mhp: float = maxf(1.0, float(S.stats["max_hp"]))
	Kit.bar_glow(m, Rect2(x, y, w, 24), float(S.hp) / mhp, Kit.ENEMY, 10)
	Kit.t(m, "HP %d / %d" % [clampi(int(ceil(float(S.hp))), 0, int(mhp)), int(mhp)], Vector2(x + w * 0.5, y + 19), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	m.stat_tips.append([Rect2(x, y, w, 24), "Core HP. The run ends at 0."])
	y += 28.0
	var smax: float = float(S.stats.get("shield_max", 0.0))
	if smax > 0.0:
		Kit.bar(m, Rect2(x, y, w, 10), float(S.shield) / smax, SHIELD)
		m.stat_tips.append([Rect2(x, y - 2, w, 14), "Aegis shield %d / %d" % [int(S.shield), int(smax)]])
		y += 14.0
	# cash
	y += 34.0
	Kit.icon(m, "cur_cash", Rect2(x, y - 30, 36, 36))
	Kit.t(m, "$%s" % Kit.fmt(float(S.cash)), Vector2(x + 44, y), 30, Kit.GREEN, HORIZONTAL_ALIGNMENT_LEFT, w * 0.55)
	var st: Dictionary = S.stats
	Kit.t(m, "+%.1f/s" % float(st.get("cash_ps", 0.0)), Vector2(x + w, y - 12), 15, Kit.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.4)
	Kit.t(m, "interest %d%% (cap %d)" % [int(round(float(st.get("interest_rate", 0.0)) * 100.0)), int(float(st.get("interest_cap", 0.0)))], Vector2(x + w, y + 6), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5)
	m.stat_tips.append([Rect2(x, y - 34, w, 44), "Run cash: buys Core Enhancements and rerolls. Earned per second, per kill (x1.10 per wave) and as interest each wave on banked cash up to the cap."])
	y += 30.0
	# Owner feedback #1: enemies killed lives in the Core panel (bodies counted)
	Kit.icon(m, "mis_kill", Rect2(x, y - 4, 30, 30))
	Kit.t(m, "Enemies killed", Vector2(x + 38, y + 18), 17, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w * 0.5)
	Kit.t(m, Kit.fmt(float(S.kills)), Vector2(x + w, y + 20), 24, Kit.ENEMY, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5)
	m.stat_tips.append([Rect2(x, y - 4, w, 30), "Enemies killed this run\nEvery body in a horde counts  ·  %d enemies on the field now" % S.enemy_count()])
	y += 40.0
	# stats
	var cw: Dictionary = (st["weapons"] as Array).back()
	var rows: Array = [
		["Damage", Kit.fmt(float(cw.get("dmg", 0.0))), "Core damage per hit (all multipliers)"],
		["Attack rate", "%.2f/s" % float(cw.get("rate", 0.0)), "Core attacks per second"],
		["Range", "%.1f cells" % float(cw.get("range_cells", 0.0)), "Core attack range"],
		["Regen", "%.1f/s" % float(st.get("regen", 0.0)), "HP the Core regenerates per second"],
		["Armor", "%.1f" % float(st.get("armor", 0.0)), "Flat damage removed from each enemy hit"],
		["Base DPS", Kit.fmt(float(S.dps())), "Estimated damage per second of the Core and every building"],
		["Coins this run", Kit.fmt(float(S.coins_run)), "Coins banked when the run ends (x tier, x modifiers)"],
		["Crit chance", "%d%%" % int(round(minf(1.0, float(st.get("crit", 0.0)) + float(cw.get("crit", 0.0))) * 100.0)), "Chance a Core hit deals critical damage"],
		["Best wave", "%d" % int(m.save.get("best_wave", 0)), "Your best wave on any tier — beat it to push the frontier"],
	]
	# FB2: stats in two compact columns, freeing room for Enemies + Loot Drops
	var sh: float = 22.0
	var cw2: float = (w - 12.0) * 0.5
	for k in rows.size():
		var rw: Array = rows[k]
		Kit.row(m, String(rw[0]), String(rw[1]), Vector2(x + float(k % 2) * (cw2 + 12.0), y + sh * float(k / 2)), cw2, Kit.TEXT, String(rw[2]), 14)
	y += sh * float((rows.size() + 1) / 2) + 6.0
	Intel.draw(m, x, w, y, track_y(m) - 58.0)
	# tracks
	var ty: float = track_y(m)
	var th: float = track_h(m)
	Kit.head(m, "CORE ENHANCEMENTS  (cash, this run)", Vector2(x, ty - 30), w)
	for k in TowerState.TRACK_IDS.size():
		var tid: String = TowerState.TRACK_IDS[k]
		var td: Dictionary = TowerState.TRACKS[tid]
		var r := Rect2(x, ty + k * (th + 6.0), w, th)
		var c: int = S.track_cost(tid)
		var can: bool = c >= 0 and S.cash >= float(c)
		Kit.panel(m, r, Kit.GREEN if can else Kit.EDGE, Kit.tint(Kit.GREEN, 0.12) if can else Kit.PANEL)
		Kit.icon(m, String(TRACK_ICON[tid]), Rect2(r.position.x + 8, r.position.y + (th - 36) * 0.5, 36, 36), Color.WHITE if can else Color(1, 1, 1, 0.5))
		Kit.t(m, "%s  Lv %d" % [String(td["name"]), int(S.tracks[tid])], Vector2(r.position.x + 52, r.position.y + th * 0.45), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 150)
		Kit.t(m, "%s  ·  %s" % [String(td["desc"]), String(td.get("minus", ""))], Vector2(r.position.x + 52, r.position.y + th * 0.45 + 18), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 150)
		Kit.t(m, ("$%s" % Kit.fmt(float(c))) if c >= 0 else "MAX", Vector2(r.end.x - 10, r.position.y + th * 0.45), 18, Kit.GREEN if can else Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)


static func _draw_results(m) -> void:
	m.draw_rect(m.field_rect(), Color(0, 0, 0, 0.55))
	var r: Rect2 = results_rect(m)
	Kit.panel(m, r, Kit.ENEMY, Color(Kit.BG2, 0.97), 3)
	var cx: float = r.get_center().x
	var lr: Dictionary = m.last_result
	Kit.t(m, "CORE DESTROYED", Vector2(cx, r.position.y + 58), 40, Kit.ENEMY, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Kit.t(m, "Wave %d   ·   %d kills   ·   Tier %d" % [int(lr.get("wave", 0)), int(lr.get("kills", 0)), int(m.S.tier) if m.S != null else 1], Vector2(cx, r.position.y + 96), 20, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var bd: Dictionary = lr.get("breakdown", {})
	var x: float = r.position.x + 40.0
	var w: float = r.size.x * 0.5 - 60.0
	var y: float = r.position.y + 150.0
	Kit.head(m, "COINS", Vector2(x, y), w)
	var rows: Array = [
		["Wave coins", Kit.fmt(float(bd.get("wave", 0)))], ["Kill coins", Kit.fmt(float(bd.get("kills", 0)))],
		["Boss bounty", Kit.fmt(float(bd.get("boss", 0)))], ["Cash-out", Kit.fmt(float(bd.get("cashout", 0)))],
		["x Tier %d" % int(bd.get("tier", 1)), "x%.1f" % Tiers.coin_mult(int(bd.get("tier", 1)))],
		["x Bonuses", "x%.2f" % (float(bd.get("mult", 1.0)) / maxf(0.01, Tiers.coin_mult(int(bd.get("tier", 1)))))],
	]
	for k in rows.size():
		var rw: Array = rows[k]
		Kit.row(m, String(rw[0]), String(rw[1]), Vector2(x, y + 34 + k * 30.0), w, Kit.TEXT, "", 17)
	var yb: float = y + 34 + rows.size() * 30.0 + 20.0
	# casino moment: the banked total rolls up, then pops (vfx/Roll.gd)
	var tot: float = float(lr.get("coins", 0))
	var el: float = m.t_anim - m.results_t0 - 0.3
	var rd: float = Roll.duration(tot) * 1.6
	Kit.glow(m, Vector2(x + 20, yb + 16), 60.0, Kit.GOLD, 0.35)
	Kit.icon(m, "cur_coin", Rect2(x, yb - 4, 40, 40))
	Kit.big_number(m, "+%s coins" % Kit.fmt(Roll.value_at(0.0, tot, maxf(0.0, el), rd)), Vector2(x + 48, yb + 30), 32, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w, Roll.pop_at(maxf(0.0, el), rd))
	Kit.t(m, "%d missions completed" % m.run_missions, Vector2(x, yb + 104), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	# loot
	var lx: float = r.get_center().x + 20.0
	Kit.head(m, "LOOT", Vector2(lx, y), w)
	var ly: float = y + 24.0
	var any: bool = false
	for e in m.run_loot:
		var ev: Dictionary = e
		var et: String = String(ev["t"])
		if et == "loot_banked":
			var bits: Array = []
			if int(ev.get("scrap", 0)) > 0:
				bits.append("+%d Scrap" % int(ev["scrap"]))
			if not bits.is_empty():
				Kit.t(m, "  ·  ".join(bits), Vector2(lx, ly + 22), 17, Kit.SCRAP, HORIZONTAL_ALIGNMENT_LEFT, w)
				ly += 30.0
				any = true
			continue
		if ly > r.end.y - 130.0:
			break
		var icon_id: String = String(ev.get("id", ""))
		var label: String = ""
		var col: Color = Kit.TEXT
		match et:
			"insight_banked":
				label = "%s banked" % pick_name(icon_id)
				col = Kit.RARITY["insight"]
		if label == "":
			continue
		Kit.icon(m, icon_id, Rect2(lx, ly, 36, 36))
		Kit.t(m, label, Vector2(lx + 44, ly + 25), 17, col, HORIZONTAL_ALIGNMENT_LEFT, w - 44)
		ly += 42.0
		any = true
	if not any:
		Kit.t(m, "No loot this run — bosses, marked elites and Couriers drop it.", Vector2(lx, ly + 22), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	Kit.t(m, "Spend coins on the Core, the Outpost and Research", Vector2(cx, r.end.y - 96), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
