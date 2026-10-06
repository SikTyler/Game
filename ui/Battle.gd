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
const Labs := preload("res://Labs.gd")
const DraftPanel := preload("res://ui/DraftPanel.gd")
const Hotbar := preload("res://ui/Hotbar.gd")
const Intel := preload("res://ui/Intel.gd")
const WeaponDB := preload("res://data/WeaponDB.gd")
const SupportDB := preload("res://data/SupportDB.gd")
const COMPASS: Array = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const FirePatterns := preload("res://FirePatterns.gd")
const PartVis := preload("res://PartVis.gd")
const Cores := preload("res://Cores.gd")
const LootDB := preload("res://data/LootDB.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const EnhancePanel := preload("res://ui/EnhancePanel.gd")

const ENEMY2: Color = Kit.MAGENTA
const SHIELD: Color = Color("7fd8ff")


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
	EnhancePanel.build(m)   # V2 P7b: Core Enhancement trees
	# V2 P7a: Merge (keyboard / pad path to drag-merge) under any selected
	# building that has a same-id, same-tier twin
	if m.sel >= 0 and m.sel != TowerState.CORE_SLOT and S.id_at(m.sel) != "" and S.merge_partner(m.sel) >= 0:
		var mi: int = m.sel
		var mcs: float = TowerState.CELL * float(S.size_at(mi)) * m.world_scale()
		var mcp: Vector2 = m.w2s(S.fp_pos(mi)) + Vector2(0, mcs * 0.5 + 6.0 + (46.0 if S.is_weapon_slot(mi) else 0.0))
		var fr1: Rect2 = m.field_rect()
		var mr0 := Rect2(clampf(mcp.x - 110.0, fr1.position.x + 4.0, fr1.end.x - 224.0), clampf(mcp.y, fr1.position.y + 4.0, fr1.end.y - 104.0), 220, 40)
		Kit.btn(m, "Merge -> T%d" % (S.tier_at(mi) + 1), mr0, func() -> void: m.merge_into(S.merge_partner(mi), mi), "Fold the nearest same-tier %s into this one (or drag one onto the other): T%d -> T%d, then pick a mod" % [pick_name(S.id_at(mi)), S.tier_at(mi), S.tier_at(mi) + 1], true, Kit.GOLD, "MERGE", "icon_tier", 16)
	if m.sel >= 0 and S.is_weapon_slot(m.sel) and m.sel != TowerState.CORE_SLOT:
		var i: int = m.sel
		# floats on the field just under the selected weapon (left bar = Perks)
		var cs: float = TowerState.CELL * float(S.size_at(i)) * m.world_scale()
		var cp: Vector2 = m.w2s(S.fp_pos(i)) + Vector2(0, cs * 0.5 + 6.0)
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
	if Labs.level(m.save, "auto_restart") > 0:
		var on: bool = Labs.auto_restart_on(m.save)
		Kit.btn(m, "AUTO-RESTART: %s" % ("ON" if on else "OFF"), Rect2(r.position.x + 24.0, r.end.y - 152.0, r.size.x * 0.5 - 44.0, 60.0), func() -> void:
			Labs.toggle_auto_restart(m.save)
			m.results_t0 = m.t_anim
			m._save()
			m._rebuild_ui(), "Auto-Restart (research): start the next run %d s after this screen opens" % int(Labs.AUTO_RESTART_S), true, Kit.GREEN if on else Kit.NEUTRAL, "AUTORESTART", "", 18)
	var n: int = loot_count(m)
	if n > 0:
		var lb: Button = Kit.btn(m, "OPEN LOOT  ·  %d items" % n, Rect2(r.get_center().x + 20.0, r.end.y - 152.0, r.size.x * 0.5 - 44.0, 60.0), m.open_loot, "Reveal this run's items one by one (already in your inventory)", true, Kit.GOLD, "loot:open", "chest", 20)
		lb.add_theme_font_override("font", Kit.Fonts.bold())


static func loot_count(m) -> int:
	var n: int = 0
	for e in m.run_loot:
		if String((e as Dictionary).get("t", "")) == "loot_item":
			n += 1
	return n


static func results_rect(m) -> Rect2:
	var fr: Rect2 = m.field_rect()
	var w: float = minf(fr.size.x - 40.0, 780.0)
	var h: float = minf(fr.size.y - 40.0, 760.0)
	return Rect2(fr.get_center().x - w * 0.5, fr.get_center().y - h * 0.5, w, h)


## Why `id` cannot go with its footprint anchored at cell `i` right now
## ("" when it can).
static func place_reason(m, i: int, id: String) -> String:
	var S = m.S
	if i < 0:
		return "Not a cell"
	var fp: Array = TowerState.footprint(i, TowerState.size_of(id))
	if fp.is_empty():
		return "Off the grid"
	for c in fp:
		var ci: int = c
		if TowerState.is_core_cell(ci):
			return "The Core"
		if not bool(S.unlocked[ci]):
			return "Outside your grid (Research Grid Expansion)"
		if S.owner_at(ci) >= 0:
			return "Occupied"
	if not S.can_place(i, id):
		return "Ring 3+ only" if id == "railgun" else ("Build cap reached" if S.at_cap() else "Can't place here")
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
		var o: int = S.owner_at(i)
		return cell_text(m, o if o >= 0 else i)
	return ""


static func cell_text(m, i: int) -> String:
	var S = m.S
	var ring: int = TowerState.ring_of(i)
	if i == TowerState.CORE_SLOT:
		var cd: Dictionary = S.core_def if not (S.core_def as Dictionary).is_empty() else CoreDB.get_def(S.core_id)
		return "The Core  Lv%d\n%s: %s\nAuto-fire hits an Elite or Boss on the Core first, and every other shot hunts a Spitter" % [int(S.core_lvl), String(cd.get("attack_name", "")), String(cd.get("attack_desc", ""))]
	if not bool(S.unlocked[i]):
		return "Outside your grid\nResearch Grid Expansion to build here"
	var id: String = S.id_at(i)
	if id == "":
		return "Empty cell (ring %d)\nDraft a building and drop it here" % ring
	var d: Dictionary = PickDB.get_def(id)
	var up: String = ""
	if S.pending_place == id and S.card_merge_targets(id).has(i):
		up = "\nClick to merge your %s card into it (T1 -> T2)" % pick_name(id)
	elif S.merge_partner(i) >= 0:
		up = "\nDrag it onto another T%d %s to merge (T%d -> T%d)" % [S.tier_at(i), pick_name(id), S.tier_at(i), S.tier_at(i) + 1]
	for md in S.mods_at(i):
		up += "\n+ %s: %s" % [String((md as Dictionary).get("name", "")), String((md as Dictionary).get("desc", ""))]
	var aim: String = ""
	if WeaponDB.directional(id):
		aim = "\n%s, facing %s  ·  [%s] or wheel turns it" % ["Arc %d deg" % int(WeaponDB.DEFS[id]["arc"]) if WeaponDB.aim_of(id) == "arc" else ("Fixed lane" if float(WeaponDB.DEFS[id]["arc"]) == 0.0 else "Fixed cone %d deg" % int(WeaponDB.DEFS[id]["arc"])), COMPASS[S.rot_at(i)], Kit.hint(m, "rotate")]
	if bool((S.slots[i] as Dictionary).get("evo", false)):
		up += "\nEVOLVED: %s" % String(TowerState.EvoDB.get_def(id).get("desc", ""))
	return "%s  T%d / %d  (%s)\n%s%s%s" % [S.name_at(i), S.tier_at(i), TowerState.lvl_cap(), String(d["rarity"]).capitalize(), String(d["desc"]), aim, up]


# ================================================================== ranges
## World-space reach of the building on cell i: weapons use their live range
## and aim (V2 P3c: radial circle, arc wedge, fixed cone or lane along their
## facing), every other building its aura (the cells around it). {} = none.
static func range_of(m, i: int) -> Dictionary:
	var S = m.S
	if S == null or i < 0:
		return {}
	for wv in (S.stats.get("weapons", []) as Array):
		var wd: Dictionary = wv
		if int(wd.get("slot", -2)) == i:
			return _aim_shape(m, wd)
	if i != TowerState.CORE_SLOT and S.id_at(i) != "":
		var fx: Dictionary = (S.stats.get("bfx", {}) as Dictionary).get(i, {})
		return aura_shape(S.id_at(i), S.size_at(i), int(fx.get("reach", 0.0)))
	return {}


## V2 P10 (owner: "some buildings show a 3x3 radius that don't affect
## adjacent buildings"): only buildings that reach their neighbours get a
## shape - the square of cells their aura covers, or a circle for the
## radius effects (Wall slow, Bounty). Global-effect buildings get none.
static func aura_shape(id: String, size: int, reach: int = 0) -> Dictionary:
	var cells: int = 0
	match id:
		"armory":
			cells = 1 + reach
		"beacon":
			cells = 4 + reach
		"hut_engineer", "oilmill":
			cells = 1
		"barricade", "gate":
			return {"r": 1.5 * TowerState.cpx(), "kind": "weapon", "aim": "radial"}   # the Wall slow aura (pc_wall_aura)
		"bounty":
			return {"r": (3.0 + float(reach)) * TowerState.cpx(), "kind": "weapon", "aim": "radial"}
		_:
			if SupportDB.has(id) and SupportDB.get_def(id).has("aura"):
				cells = int(SupportDB.get_def(id)["aura"]["r"]) + reach
	if cells <= 0:
		return {}
	return {"r": TowerState.CELL * (0.5 * float(size) + float(cells)), "kind": "aura"}


## The drawn shape of a weapon sheet: {r, kind: weapon, aim, facing, arc_cos, width}.
static func _aim_shape(m, wd: Dictionary) -> Dictionary:
	var r: float = float(wd.get("range", 0.0))
	if String(wd.get("pattern", "")) == "cone_dot":
		r = FirePatterns.cone_len(m.S, wd)
	return {"r": r, "kind": "weapon", "aim": String(wd.get("aim", "radial")), "facing": wd.get("facing", Vector2.UP),
		"arc_cos": float(wd.get("arc_cos", -1.0)), "width": float(wd.get("pierce", 0.0)) + 6.0}


## Reach of `id` if it were placed now at anchor `at_i` (live sheet of a placed
## twin turned to the pending facing, else its WeaponDB base).
static func preview_range(m, id: String, at_i: int = -1) -> Dictionary:
	var S = m.S
	if WeaponDB.has(id):
		var face: Vector2 = WeaponDB.facing(S.pending_rot_at(at_i) if at_i >= 0 else 6)
		for wv in (S.stats.get("weapons", []) as Array):
			var wd: Dictionary = (wv as Dictionary).duplicate()
			if String(wd.get("kind", "")) == id:
				wd["facing"] = face
				return _aim_shape(m, wd)
		var d: Dictionary = WeaponDB.get_def(id)
		var base: Dictionary = {"range": float(d["range"]) * TowerState.cpx(), "pattern": String(d["pattern"]), "aim": String(d["aim"]),
			"facing": face, "arc_cos": cos(deg_to_rad(float(d["arc"]) * 0.5)), "pierce": float((d["p"] as Dictionary).get("pierce", 0.0)), "lvl": 1}
		return _aim_shape(m, base)
	return aura_shape(id, PickDB.size_of(id))


static func draw_reach(m, c: Vector2, rg: Dictionary, col: Color, scale: float = 1.0) -> void:
	if rg.is_empty():
		return
	var r: float = float(rg["r"]) * scale
	if String(rg["kind"]) == "aura":
		var rect := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		m.draw_rect(rect, Color(col, 0.08))
		m.draw_rect(rect, Color(col, 0.6), false, 2.0)
		return
	var aim: String = String(rg.get("aim", "radial"))
	var face: Vector2 = rg.get("facing", Vector2.UP)
	if aim == "radial":
		m.draw_circle(c, r, Color(col, 0.07))
		m.draw_arc(c, r, 0, TAU, 96, Color(col, 0.6), 2.0)
		return
	var ac: float = float(rg.get("arc_cos", -1.0))
	if aim == "fixed" and ac >= 0.9999:
		# a lane: a strip along the facing
		var w: float = float(rg.get("width", 8.0)) * scale
		var nrm := Vector2(-face.y, face.x) * w
		var tip: Vector2 = c + face * r
		var pts := PackedVector2Array([c + nrm, tip + nrm, tip - nrm, c - nrm])
		m.draw_colored_polygon(pts, Color(col, 0.10))
		m.draw_polyline(PackedVector2Array([c + nrm, tip + nrm, tip - nrm, c - nrm, c + nrm]), Color(col, 0.7), 2.0)
		m.draw_line(c, tip, Color(col, 0.35), 1.0)
		return
	# an arc traverse or a fixed cone: a wedge around the facing
	var half: float = acos(clampf(ac, -1.0, 1.0))
	var a0: float = face.angle()
	var fan := PackedVector2Array([c])
	var seg: int = maxi(6, int(half * 20.0))
	for k in seg + 1:
		fan.append(c + Vector2.from_angle(a0 - half + 2.0 * half * float(k) / float(seg)) * r)
	m.draw_colored_polygon(fan, Color(col, 0.09 if aim == "arc" else 0.13))
	var edge := PackedVector2Array(fan)
	edge.append(c)
	m.draw_polyline(edge, Color(col, 0.7), 2.0)


## Small facing pointer on a directional building (world space).
static func draw_facing(m, c: Vector2, face: Vector2, half: float, col: Color) -> void:
	var tip: Vector2 = c + face * (half + 5.0)
	var nrm := Vector2(-face.y, face.x) * 4.0
	var base: Vector2 = c + face * (half - 1.0)
	m.draw_colored_polygon(PackedVector2Array([tip, base + nrm, base - nrm]), col)


## Owner feedback #1: clicking (selecting) any building shows its range.
static func _draw_ranges(m) -> void:
	var S = m.S
	if m.sel >= 0 and m.sel != TowerState.CORE_SLOT and S.id_at(m.sel) != "":
		draw_reach(m, S.fp_pos(m.sel), range_of(m, m.sel), Kit.GEM)
		m.set_meta("range_shown", m.sel)
	else:
		m.set_meta("range_shown", -1)


# ===================================================================== draw
## The world canvas transform of this frame (PartVis draws through it).
static var _base: Transform2D = Transform2D.IDENTITY


static func draw(m, off: Vector2) -> void:
	var S = m.S
	var fr: Rect2 = m.field_rect()
	_draw_field_bg(m, fr)
	if S != null:
		_base = Transform2D(0.0, off) * m.world_xform()
		m.draw_set_transform_matrix(_base)
		if m.gore != null and String(m.gore.get("level")) != "off":
			var gt: Texture2D = m.gore.call("ground_texture")
			if gt != null:
				# HORDE P5 corpse/blood layer; V2 P9 audit: muted (cool tint, ~45% alpha) so the
				# floor never outshouts the enemies or the Core
				m.draw_texture_rect(gt, m.gore.call("ground_rect"), false, Color(0.62, 0.5, 0.72, 0.45))
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
		if m.screen != "results":
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
	# V2 P3b: cells a footprint of the pending pick could cover right now
	var ok_cells: Dictionary = {}
	if S.pending_place != "":
		var psz: int = TowerState.size_of(S.pending_place)
		for a in TowerState.N:
			if S.can_place(a, S.pending_place):
				for fc in TowerState.footprint(a, psz):
					ok_cells[fc] = true
	for i in TowerState.N:
		if TowerState.is_core_cell(i) or not S.in_grid(i):
			continue
		var p: Vector2 = TowerState.slot_pos(i)
		var half: float = c * 0.5 - 1.0
		var r := Rect2(p - Vector2(half, half), Vector2(half * 2, half * 2))
		if not bool(S.unlocked[i]):
			m.draw_rect(r, Color("0e1528"))
			continue
		var o: int = S.owner_at(i)
		if o < 0:
			var oc := Color(Kit.EDGE2, 0.8)
			var fill := Color("121b31")
			if placing and (ok_cells.has(i) if S.pending_place != "" else true):
				# Floor the pulse so valid cells always read as "glowing".
				oc = Color(Kit.GREEN, 0.55 + 0.25 * sin(m.t_anim * 8.0))
				fill = Color("121b31").lerp(Kit.GREEN, 0.12)
			m.draw_rect(r, fill)
			m.draw_rect(r, oc, false, 1.0)
			if i == m.sel:
				m.draw_rect(r.grow(3), Color(1, 1, 1, 0.9), false, 2.0)
			continue
		if o != i:
			continue   # covered by a bigger footprint (drawn from its anchor)
		var id: String = S.id_at(i)
		var sz: int = S.size_at(i)
		var sc: float = 1.0
		if m.slot_pop.has(i):
			sc = 1.0 + 0.3 * float(m.slot_pop[i]) / 0.3
		var bh: float = (c * 0.5 * float(sz) - 1.0) * sc
		var br := Rect2(S.fp_pos(i) - Vector2(bh, bh), Vector2(bh, bh) * 2.0)
		var rc: Color = Kit.rarity_col(PickDB.rarity_of(id))
		m.draw_rect(br, Color(rc, 0.14))
		m.draw_rect(br, Color(rc, 0.55), false, 1.0)
		if not Kit.icon(m, id, br.grow(1)):
			m.draw_rect(br.grow(-4), rc)
		if WeaponDB.directional(id):
			draw_facing(m, br.get_center(), WeaponDB.facing(S.rot_at(i)), bh, Color(Kit.CYAN, 0.9))
		# V2 P7a: tier chevrons (T2 cyan, T3 gold) along the bottom edge
		var tr: int = S.tier_at(i)
		if tr >= 2:
			var tc: Color = Kit.GOLD if tr >= 3 else Kit.CYAN
			var cw2: float = minf(8.0, br.size.x * 0.2)
			for k in tr - 1:
				var bx: float = br.position.x + 3.0 + float(k) * (cw2 + 2.0)
				m.draw_colored_polygon(PackedVector2Array([Vector2(bx, br.end.y - 2.0), Vector2(bx + cw2 * 0.5, br.end.y - 2.0 - cw2 * 0.6), Vector2(bx + cw2, br.end.y - 2.0)]), tc)
			m.draw_rect(br, Color(tc, 0.7), false, 1.5)
		# merge targets glow: the card being placed / the building being dragged
		var twin: bool = (S.pending_place == id and S.card_merge_targets(id).has(i))
		twin = twin or (m.drag_card >= 0 and m.drag_card < S.draft.size() and String((S.draft[m.drag_card] as Dictionary)["id"]) == id and S.card_merge_targets(id).has(i))
		twin = twin or (m.bld_drag >= 0 and m.bld_drag != i and S.merge_targets(m.bld_drag).has(i) and m.mouse_pos.distance_to(m.drag_start) > 12.0)
		if twin:
			m.draw_rect(br.grow(3), Color(Kit.GOLD, 0.6 + 0.35 * sin(m.t_anim * 8.0)), false, 2.5)
		if i == m.sel:
			m.draw_rect(br.grow(3), Color(1, 1, 1, 0.9), false, 2.0)
	# Core
	var cw: Dictionary = (S.stats["weapons"] as Array).back() if (S.stats.get("weapons", []) as Array).size() > 0 else {}
	if m.sel == TowerState.CORE_SLOT or m.mouse_pos.distance_to(m.w2s(C)) < c * 1.5 * m.world_scale():
		m.draw_circle(C, float(cw.get("range", 200.0)), Color(Kit.GEM, 0.05))
		m.draw_arc(C, float(cw.get("range", 200.0)), 0, TAU, 96, Color(Kit.GEM, 0.5), 2.0)
	var pulse: float = 0.5 + 0.5 * sin(m.t_anim * 3.0)
	var cr: float = c * 1.45   # the 3x3 Core footprint
	Kit.glow(m, C, cr * 2.2, Kit.CYAN, 0.12 + 0.06 * pulse)
	m.draw_circle(C, cr + 6.0 + 3.0 * pulse, Color(1, 1, 1, 0.05))
	# V3: the player's Core drawn from its parts, with the Weapon turret (its
	# barrels fanned) turning to where barrel 0 fires (or to the cursor)
	var want: float = ((S.aim_pos - C) if bool(S.aim_on) else (S.core_aim_dir as Vector2)).angle()
	m.turret_ang = lerp_angle(float(m.turret_ang), want, 0.35)
	PartVis.draw_assembly(m, m.save, Cores.look(m.save), C, cr, float(m.turret_ang), m.t_anim, _base)
	if float(S.shield) > 0.0:
		var smax: float = maxf(1.0, float(S.stats.get("shield_max", 1.0)))
		m.draw_arc(C, cr + 6.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(S.shield) / smax, 0.0, 1.0), 48, SHIELD, 3.0)
	_draw_reticle(m, S)


## V2 P4 manual aim: a reticle on the aim point (AIM_R ring, crosshair) whose
## gold arc is the focus meter (+30% damage when full).
static func _draw_reticle(m, S) -> void:
	if not bool(S.aim_on) and float(S.focus) <= 0.0:
		return
	var p: Vector2 = S.aim_pos
	var r: float = float(TowerState.AIM_R)
	var a: float = 1.0 if bool(S.aim_on) else 0.4
	m.draw_line(TowerState.CENTER, p, Color(Kit.MAGENTA, 0.18 * a), 2.0)
	m.draw_arc(p, r, 0.0, TAU, 32, Color(Kit.MAGENTA, 0.8 * a), 2.0)
	for k in 4:
		var d: Vector2 = Vector2.from_angle(float(k) * PI * 0.5)
		m.draw_line(p + d * (r * 0.45), p + d * (r * 1.25), Color(Kit.MAGENTA, 0.9 * a), 2.0)
	var f: float = clampf(float(S.focus), 0.0, 1.0)
	if f > 0.0:
		m.draw_arc(p, r + 6.0, -PI * 0.5, -PI * 0.5 + TAU * f, 40, Color(Kit.GOLD, a), 4.0)
	if f >= 1.0:
		m.draw_circle(p, 4.0 + 1.5 * sin(m.t_anim * 10.0), Kit.GOLD)


static func _draw_world(m) -> void:
	var S = m.S
	# V2 P5 loot beams: a drop token stands in its colour for 2.6 s
	for b in m.loot_beams:
		var bd: Dictionary = b
		var f: float = clampf(float(bd["t"]) / 0.35, 0.0, 1.0) * clampf((2.6 - float(bd["t"])) / 0.6, 0.0, 1.0)
		Kit.rarity_beam(m, bd["pos"], String(bd["rar"]), 220.0 * f, m.t_anim, 30.0)
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
	en.ensure_cold()   # V2 P3d: cur_s is pulled on demand (at most once per step)
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
		# V2 P9 audit: spread numbers of neighbouring bodies on both axes, outline
		# them (no translucent shadow) and drop them once they fade past half
		# alpha, so the pile reads as numbers instead of noise.
		var dp: Vector2 = (dn["pos"] as Vector2) + Vector2(float(int(dn["eid"]) * 37 % 31) - 15.0, -18.0 - age * 50.0 + float(int(dn["eid"]) * 53 % 23) - 11.0)
		var da: float = minf(1.0, dt * 3.0)
		if da < 0.5:
			continue
		Kit.t_outline(m, Kit.fmt(float(dn["amt"])), dp, int(float(dsz) * pun), Color(dc, da), HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	# V2 P10 loot pops: the drop's icon rises off the body that dropped it
	for lp in m.loot_pops.items:
		var lt: float = float(lp["t"])
		if lt <= 0.0:
			continue
		var la: float = clampf(lt / 0.35, 0.0, 1.0)
		var age: float = m.LOOT_POP_S - lt
		var lpos: Vector2 = (lp["pos"] as Vector2) + Vector2(0, -22.0 - 34.0 * minf(1.0, age / 0.6))
		var sz: float = 26.0 * (1.0 + maxf(0.0, 0.18 - age) * 2.5)
		m.draw_circle(lpos, sz * 0.62, Color(0.02, 0.03, 0.07, 0.55 * la))
		Kit.icon(m, String(lp["icon"]), Rect2(lpos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(lp["color"], la))
		if String(lp["text"]) != "":
			Kit.t_outline(m, String(lp["text"]), lpos + Vector2(sz * 0.5 + 2.0, 6.0), 15, Color(Kit.TEXT, la), HORIZONTAL_ALIGNMENT_LEFT, 80.0)
	for fd3 in m.pops.items:
		if float(fd3["t"]) <= 0.0:
			continue
		var pp: Vector2 = fd3["pos"]
		var lift: float = (1.0 - float(fd3["t"])) * 30.0
		var pc: Color = fd3["color"]
		Kit.t_outline(m, String(fd3["text"]), pp - Vector2(0, lift), int(fd3["size"]), Color(pc, minf(1.0, float(fd3["t"]) * 2.5)), HORIZONTAL_ALIGNMENT_CENTER, 600.0)


## Field banners: incoming wave, placement / aim prompts, Insight fanfare.
## V2 P7c: Supply Drop reel symbols [label, colour].
const SUPPLY_SYM: Dictionary = {"cash": ["$", Color("4ade80")], "xp": ["XP", Color("39e6ff")], "reroll": ["REROLL", Color("a78bfa")],
	"card": ["CARD", Color("ff3ea5")], "cache": ["CACHE", Color("f59e0b")], "star": ["★", Color("ffd34d")]}
const SUPPLY_STOP: Array = [0.9, 1.4, 1.9]
const SUPPLY_SHOW: float = 4.2


static func _draw_field_hud(m, fr: Rect2) -> void:
	var S = m.S
	var cx: float = fr.get_center().x
	_draw_combo(m, fr)
	_draw_supply(m, fr)
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
		if S.card_merge_targets(S.pending_place).is_empty():
			prompt = "Place %s: click a glowing cell  ·  %s cancels" % [pick_name(S.pending_place), Kit.hint(m, "cancel")]
		else:
			prompt = "Place %s on a free cell, or click your glowing T1 %s to merge it (T2)  ·  %s cancels" % [pick_name(S.pending_place), pick_name(S.pending_place), Kit.hint(m, "cancel")]
	elif m.bld_drag >= 0 and m.mouse_pos.distance_to(m.drag_start) > 12.0 and not S.merge_targets(m.bld_drag).is_empty():
		prompt = "Drop on a glowing %s to merge (T%d -> T%d)" % [pick_name(S.id_at(m.bld_drag)), S.tier_at(m.bld_drag), S.tier_at(m.bld_drag) + 1]
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
	if id == "":
		m.set_meta("ghost_reason", "")
		m.set_meta("ghost_id", "")
		return
	var reason: String = "Drop on a cell"
	var cs: float = TowerState.CELL * m.world_scale()
	var at: Vector2 = m.mouse_pos
	var ok: bool = false
	if m.field_rect().has_point(m.mouse_pos):
		var wp: Vector2 = m.s2w(m.mouse_pos)
		var sz: int = TowerState.size_of(id) if is_new else 1
		# new picks snap their footprint under the cursor; upgrades target the
		# building covering the cell
		var i: int = TowerState.anchor_at(wp, sz) if is_new else m.pick_at(wp)
		# V2 P7a: hovering a T1 twin with a duplicate card = merge
		var tw: int = m.pick_at(wp)
		if is_new and tw >= 0 and S.card_merge_targets(id).has(tw):
			var ts: float = cs * float(S.size_at(tw))
			var tat: Vector2 = m.w2s(TowerState.fp_center(tw, S.size_at(tw)))
			var trr := Rect2(tat - Vector2(ts, ts) * 0.5, Vector2(ts, ts))
			m.draw_rect(trr.grow(4), Color(Kit.GOLD, 0.25))
			m.draw_rect(trr.grow(4), Kit.GOLD, false, 3.0)
			Kit.panel(m, Rect2(tat + Vector2(-60, -ts * 0.5 - 40), Vector2(120, 30)), Kit.GOLD, Color(0.14, 0.12, 0.06, 0.94))
			Kit.th(m, "MERGE -> T2", tat + Vector2(0, -ts * 0.5 - 19), 16, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
			m.set_meta("ghost_reason", "merge")
			m.set_meta("ghost_id", id)
			return
		if i >= 0:
			if is_new:
				reason = place_reason(m, i, id)
			else:
				reason = "Release to take this pick"
			ok = reason == "" or reason.begins_with("Release")
			if not is_new:
				sz = S.size_at(i)
			at = m.w2s(TowerState.fp_center(i, sz))
			var fs: float = cs * float(sz)
			var cr := Rect2(at - Vector2(fs, fs) * 0.5, Vector2(fs, fs))
			m.draw_rect(cr, Color(Kit.GREEN, 0.25) if ok else Color(Kit.ENEMY, 0.25))
			m.draw_rect(cr, Kit.GREEN if ok else Kit.ENEMY, false, 3.0)
			if is_new and (S.pending_place != "" or m.drag_card >= 0):
				var rg: Dictionary = preview_range(m, id, i)
				var rc: Color = Kit.GREEN if ok else Kit.ENEMY
				draw_reach(m, at, rg, rc, m.world_scale())
				if WeaponDB.directional(id):
					m.set_meta("ghost_rot", S.pending_rot_at(i))
					draw_facing(m, at, WeaponDB.facing(S.pending_rot_at(i)), fs * 0.5, rc)
	var gs: float = maxf(40.0, cs * 0.9 * float(TowerState.size_of(id)))
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
	m.draw_rect(rr, Color(Kit.PANEL, 1.0))   # V2 P9 audit: opaque, the horde never shows through HUD text
	m.draw_line(rr.position, Vector2(rr.position.x, rr.end.y), Kit.EDGE, 2.0)
	var x: float = rr.position.x + 16.0
	var w: float = rr.size.x - 32.0
	var y: float = rr.position.y + 14.0
	var cd: Dictionary = S.core_def if not (S.core_def as Dictionary).is_empty() else CoreDB.get_def(S.core_id)
	# portrait
	Kit.panel(m, Rect2(x, y, 96, 96), Kit.RUST, Kit.BG2)
	# V2 P9 audit: the portrait is the player's own procedural Core (was the V1 sprite)
	PartVis.draw_assembly(m, m.save, Cores.look(m.save), Vector2(x + 48, y + 48), 30.0, -PI * 0.5, m.t_anim)
	Kit.t(m, "The Core", Vector2(x + 110, y + 26), 22, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
	Kit.t(m, "Lv %d" % int(S.core_lvl), Vector2(x + 110, y + 50), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
	Kit.t(m, Kit.fit(m, String(cd["attack_name"]), 16, w - 114), Vector2(x + 110, y + 74), 16, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
	m.stat_tips.append([Rect2(x, y, w, 96), "%s\n%s" % [String(cd["attack_name"]), String(cd["attack_desc"])]])
	y += 108.0
	# HP + shield
	var mhp: float = maxf(1.0, float(S.stats["max_hp"]))
	Kit.bar_glow(m, Rect2(x, y, w, 24), float(S.hp) / mhp, Kit.ENEMY, 10)
	Kit.t_outline(m, "HP %d / %d" % [clampi(int(ceil(float(S.hp))), 0, int(mhp)), int(mhp)], Vector2(x + w * 0.5, y + 19), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
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
	EnhancePanel.draw(m)   # V2 P7b


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
	var left: float = m.auto_restart_left()
	if left >= 0.0:   # V2 P8b Auto-Restart countdown above its switch
		Kit.th(m, "NEXT RUN IN %d s" % int(ceil(left)), Vector2(r.position.x + 24.0 + (r.size.x * 0.5 - 44.0) * 0.5, r.end.y - 160.0), 16, Kit.GREEN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x * 0.5)
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
	# caches grouped: "Boss Vault x2 · 8 items"
	var groups: Dictionary = {}
	var order: Array = []
	for e in m.run_loot:
		if String((e as Dictionary)["t"]) == "cache_open":
			var cid: String = String(e["cache"])
			if not groups.has(cid):
				groups[cid] = [0, 0]
				order.append(cid)
			groups[cid][0] = int(groups[cid][0]) + 1
			groups[cid][1] = int(groups[cid][1]) + (e["uids"] as Array).size()
	order.sort_custom(func(a: Variant, b: Variant) -> bool: return LootDB.IDS.find(String(a)) > LootDB.IDS.find(String(b)))
	for cid in order:
		if ly > r.end.y - 196.0:
			break
		var g: Array = groups[cid]
		var d: Dictionary = LootDB.get_def(String(cid))
		Kit.icon(m, "chest", Rect2(lx, ly, 36, 36))
		Kit.t(m, "%s  x%d%s" % [String(d["name"]), int(g[0]), ("  ·  %d items" % int(g[1])) if int(g[1]) > 0 else ""], Vector2(lx + 44, ly + 25), 17, Kit.rarity_text(String(d["min"])) if String(d["min"]) != "" else Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 44)
		ly += 42.0
		any = true
	for e in m.run_loot:
		var ev: Dictionary = e
		var et: String = String(ev["t"])
		if et == "cache_open":
			continue
		if et == "loot_banked":
			var bits: Array = []
			if int(ev.get("scrap", 0)) > 0:
				bits.append("+%d Scrap" % int(ev["scrap"]))
			if not bits.is_empty():
				Kit.t(m, "  ·  ".join(bits), Vector2(lx, ly + 22), 17, Kit.SCRAP, HORIZONTAL_ALIGNMENT_LEFT, w)
				ly += 30.0
				any = true
			continue
		if ly > r.end.y - 196.0:
			break
		var icon_id: String = String(ev.get("id", ""))
		var label: String = ""
		var col: Color = Kit.TEXT
		match et:
			"insight_banked":
				label = "%s banked" % pick_name(icon_id)
				col = Kit.RARITY["insight"]
			"loot_item":
				if String(ev.get("cache", "")) != "":
					continue
				icon_id = "icon_gear"
				label = "%s item (elite drop)" % String(RarityDB.get_def(String(ev["rar"]))["name"])
				col = Kit.rarity_col(String(ev["rar"]))
			"loot_salvaged":
				icon_id = "cur_scrap"
				label = "Inventory full: a %s salvaged" % String(RarityDB.get_def(String(ev["rar"]))["name"])
				col = Kit.DIM
		if label == "":
			continue
		Kit.icon(m, icon_id, Rect2(lx, ly, 36, 36))
		Kit.t(m, label, Vector2(lx + 44, ly + 25), 17, col, HORIZONTAL_ALIGNMENT_LEFT, w - 44)
		ly += 42.0
		any = true
	if not any:
		Kit.t(m, "No loot this run — elites, bosses, Couriers and every 5th wave drop it.", Vector2(lx, ly + 22), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	if loot_count(m) == 0:
		Kit.t(m, "Spend coins on the Core, the Outpost and Research", Vector2(cx, r.end.y - 96), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## V2 P7c combo meter: under the wave banner while a streak is on.
static func _draw_combo(m, fr: Rect2) -> void:
	var S = m.S
	if float(S.combo) < 1.0:
		return
	var tiers: Array = TowerState.COMBO_TIERS
	var t: int = int(S.combo_tier)
	var nxt: float = float((tiers[mini(t, tiers.size() - 1)] as Array)[0])
	var prev: float = 0.0 if t <= 0 else float((tiers[t - 1] as Array)[0])
	var fr2: float = 1.0 if t >= tiers.size() else clampf((float(S.combo) - prev) / maxf(1.0, nxt - prev), 0.0, 1.0)
	var col: Color = [Kit.DIM, Kit.CYAN, Kit.GREEN, Kit.GOLD, Kit.MAGENTA][mini(t, 4)]
	var r := Rect2(fr.end.x - 236, fr.position.y + 60, 220, 44)
	Kit.panel(m, r, col if t > 0 else Kit.EDGE, Color(0.04, 0.06, 0.11, 0.88), 2 if t > 0 else 1)
	var pulse: float = 1.0 + (0.08 * sin(m.t_anim * 10.0) if t >= 3 else 0.0)
	Kit.th(m, ("COMBO  x%.2f" % S.combo_mult()) if t > 0 else "COMBO", Vector2(r.position.x + 10, r.position.y + 20), int(16.0 * pulse), col if t > 0 else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 150.0)
	Kit.t(m, "%d" % int(S.combo), Vector2(r.end.x - 10, r.position.y + 20), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 70.0)
	Kit.bar_glow(m, Rect2(r.position.x + 10, r.position.y + 28, r.size.x - 20, 8), fr2, col if t > 0 else Kit.CYAN)
	m.stat_tips.append([r, "Kill-streak combo: kills fill it, it drains over ~2.5 s.\nx1.10 / x1.25 / x1.50 / x2.00 kill cash and XP at %s kills" % ", ".join(PackedStringArray(tiers.map(func(x: Variant) -> String: return "%d" % int((x as Array)[0]))))])


## V2 P7c Supply Drop: a 3-reel slot machine over the field; reels stop one
## by one (rising clicks, Main), then the payout.
static func _draw_supply(m, fr: Rect2) -> void:
	var sd: Dictionary = m.supply_show
	if sd.is_empty():
		return
	var age: float = float(m.t_anim) - float(m.supply_t0)
	if age > SUPPLY_SHOW:
		return
	var a: float = clampf(minf(age * 4.0, (SUPPLY_SHOW - age) * 2.0), 0.0, 1.0)
	var cx: float = fr.get_center().x
	var jp: bool = bool(sd.get("jackpot", false))
	var r := Rect2(cx - 220, fr.position.y + 110, 440, 190)
	var rim: Color = Kit.GOLD if jp else Kit.MAGENTA
	Kit.glow(m, r.get_center(), 260.0, rim, 0.18 * a)
	Kit.panel_glow(m, r, Color(rim, a), Color(0.06, 0.04, 0.10, a), 1.4, 3)
	Kit.th(m, "SUPPLY DROP", Vector2(cx, r.position.y + 30), 22, Color(Kit.GOLD, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var reels: Array = sd.get("reels", [])
	var keys: Array = SUPPLY_SYM.keys()
	for k in 3:
		var rr := Rect2(r.position.x + 28 + float(k) * 132.0, r.position.y + 46, 120, 84)
		m.draw_rect(rr, Color(0.02, 0.02, 0.05, a))
		m.draw_rect(rr, Color(rim, 0.7 * a), false, 2.0)
		var stopped: bool = age >= float(SUPPLY_STOP[k])
		var sym: String = String(reels[k]) if stopped and k < reels.size() else String(keys[int(age * 18.0 + float(k) * 3.0) % keys.size()])
		var sc: Array = SUPPLY_SYM.get(sym, ["?", Kit.TEXT])
		var yoff: float = 0.0 if stopped else fposmod(age * 600.0, 30.0) - 15.0
		if stopped:
			Kit.glow(m, rr.get_center(), 60.0, sc[1], 0.35 * a)
		Kit.th(m, String(sc[0]), Vector2(rr.get_center().x, rr.get_center().y + 10 + yoff), 26 if String(sc[0]).length() <= 2 else 18, Color(sc[1], a * (1.0 if stopped else 0.6)), HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
	if age >= float(SUPPLY_STOP[2]) + 0.25:
		var txt: String = supply_text(sd)
		Kit.th(m, txt, Vector2(cx, r.end.y - 22), 20 if jp else 17, Color(Kit.GOLD if jp else Kit.TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 20)


## Payout line of a Supply Drop ("JACKPOT!" / "$640 · +2 rerolls" ...).
static func supply_text(sd: Dictionary) -> String:
	var p: Dictionary = sd.get("pays", {})
	var parts: Array = []
	if bool(sd.get("jackpot", false)):
		parts.append("JACKPOT!  $%s + Epic draft + Elite Cache" % Kit.fmt(float(p.get("jackpot", 0.0))))
	if p.has("cash"):
		parts.append("+$%s" % Kit.fmt(float(p["cash"])))
	if p.has("xp"):
		parts.append("+%d XP" % int(float(p["xp"])))
	if p.has("reroll"):
		parts.append("+%d reroll%s" % [int(p["reroll"]), "" if int(p["reroll"]) == 1 else "s"])
	if p.has("card"):
		parts.append("+%d draft%s" % [int(p["card"]), "" if int(p["card"]) == 1 else "s"])
	if p.has("cache"):
		parts.append("+%d cache%s" % [int(p["cache"]), "" if int(p["cache"]) == 1 else "s"])
	if p.has("star"):
		parts.append("+1 gold perk")
	return "  ·  ".join(PackedStringArray(parts))
