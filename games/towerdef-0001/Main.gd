extends Node2D
## Corehold view. Pure replay of TowerState events + _draw() primitives.
## Never owns a rule: every tap calls an engine/BaseMeta action.
## Screens: "base" (permanent base / workshop), "run", "results".

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const TuneRef := preload("res://Tune.gd")

const W: float = 720.0
const H: float = 1280.0
const BG: Color = Color("1b2027")
const PANEL: Color = Color("232a33")
const RUST: Color = Color("d9773a")
const ENEMY: Color = Color("e8434f")
const ENEMY2: Color = Color("e04bc0")
const TEXT: Color = Color("e9edf2")
const DIM: Color = Color("8a96a3")
const ARENA_BOTTOM: float = 860.0

var save: Dictionary = {}
var S: RefCounted = null
var screen: String = "base"
var sel: int = -1
var last_result: Dictionary = {}
var ui: Control
var font: Font
var t_anim: float = 0.0
var ui_t: float = 0.0
var last_tap_ms: int = -1000

# fx
var tracers: Array = []    # {a, b, t, color, w}
var rings: Array = []      # {pos, r, t, color}
var pops: Array = []       # {pos, text, t, color, size}
var slot_pop: Dictionary = {}
var shake: float = 0.0
var flash: float = 0.0
var level_burst: float = 0.0
var dust: Array = []


func _ready() -> void:
	font = ThemeDB.fallback_font
	save = BaseMeta.normalize(MetaSave.read())
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.position = Vector2.ZERO
	ui.size = Vector2(W, H)
	add_child(ui)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for k in 40:
		dust.append(Vector3(r.randf() * W, r.randf() * ARENA_BOTTOM, r.randf_range(4.0, 14.0)))
	_rebuild_ui()


# ------------------------------------------------------------------ flow
func start_run() -> void:
	S = TowerState.new()
	_clear_fx()
	_handle(S.setup(TuneRef.seed_of(int(Time.get_ticks_usec() % 1000000)), save))
	screen = "run"
	sel = -1
	_rebuild_ui()


func go_base() -> void:
	screen = "base"
	sel = -1
	_clear_fx()
	_rebuild_ui()


func _clear_fx() -> void:
	tracers.clear()
	rings.clear()
	pops.clear()
	slot_pop.clear()
	shake = 0.0
	flash = 0.0
	level_burst = 0.0


func _handle(events: Array) -> void:
	var rebuild: bool = false
	for e in events:
		var ev: Dictionary = e
		match String(ev["t"]):
			"shot":
				var kind: String = ev["kind"]
				var col: Color = Color.WHITE if kind == "core" else BuildingDB.cat_color("weapon")
				if kind == "tesla":
					col = Color("b48cff")
				tracers.append({"a": ev["from"], "b": ev["to"], "t": 0.12, "color": col, "w": 4.0 if kind == "mortar" else 2.0})
				if kind == "mortar":
					rings.append({"pos": ev["to"], "r": float(ev["radius"]), "t": 0.3, "color": RUST})
			"kill":
				pops.append({"pos": ev["pos"], "text": "+$%d" % int(round(float(ev["cash"]))), "t": 0.7, "color": BuildingDB.cat_color("eco"), "size": 18})
				rings.append({"pos": ev["pos"], "r": 18.0, "t": 0.2, "color": ENEMY})
			"core_hit":
				shake = minf(14.0, shake + 4.0)
				flash = minf(0.45, flash + 0.18)
			"wave":
				pops.append({"pos": TowerState.CENTER + Vector2(0, -260), "text": "WAVE %d" % int(ev["wave"]), "t": 1.4, "color": TEXT, "size": 40})
			"boss":
				pops.append({"pos": TowerState.CENTER + Vector2(0, -210), "text": "BOSS INBOUND", "t": 1.8, "color": ENEMY2, "size": 30})
				shake = 10.0
			"levelup":
				level_burst = 0.6
				rebuild = true
			"placed", "upgraded", "unlocked":
				slot_pop[int(ev["slot"])] = 0.3
				rebuild = true
			"place_mode":
				rebuild = true
			"dead":
				last_result = ev
				screen = "results"
				shake = 18.0
				flash = 0.6
				MetaSave.write(save)
				rebuild = true
	if rebuild:
		_rebuild_ui()


# ----------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	var pos: Vector2 = Vector2.ZERO
	var pressed: bool = false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		pos = mb.position
	if not pressed:
		return
	# Android emulates a mouse click from each touch — drop the duplicate.
	var now: int = Time.get_ticks_msec()
	if now - last_tap_ms < 60:
		return
	last_tap_ms = now
	tap_at(pos)


func slot_at(pos: Vector2) -> int:
	var rel: Vector2 = pos - TowerState.CENTER + Vector2(2.5 * TowerState.CELL, 2.5 * TowerState.CELL)
	if rel.x < 0.0 or rel.y < 0.0:
		return -1
	var x: int = int(rel.x / TowerState.CELL)
	var y: int = int(rel.y / TowerState.CELL)
	if x > 4 or y > 4:
		return -1
	return y * 5 + x


func tap_at(pos: Vector2) -> void:
	if pos.y > ARENA_BOTTOM or screen == "results":
		return
	var i: int = slot_at(pos)
	if screen == "run" and S != null and S.pending_place != "" and i >= 0:
		_handle(S.place(i))
		return
	sel = i
	_rebuild_ui()


# ---------------------------------------------------------------- update
func _process(delta: float) -> void:
	t_anim += delta
	if screen == "run" and S != null:
		_handle(S.tick(delta))
		ui_t += delta
		if ui_t >= 0.25 and screen == "run":
			ui_t = 0.0
			_rebuild_ui()   # refresh affordability (buttons fire on PRESS, so safe)
	for arr in [tracers, rings, pops]:
		var keep: Array = []
		for f in arr:
			var fd: Dictionary = f
			fd["t"] = float(fd["t"]) - delta
			if float(fd["t"]) > 0.0:
				keep.append(fd)
		arr.clear()
		arr.append_array(keep)
	for k in slot_pop.keys():
		slot_pop[k] = float(slot_pop[k]) - delta
		if float(slot_pop[k]) <= 0.0:
			slot_pop.erase(k)
	shake = maxf(0.0, shake - 40.0 * delta)
	flash = maxf(0.0, flash - 1.5 * delta)
	level_burst = maxf(0.0, level_burst - delta)
	for k in dust.size():
		var d: Vector3 = dust[k]
		d.y += d.z * delta
		d.x += d.z * 0.4 * delta
		if d.y > ARENA_BOTTOM:
			d.y = 0.0
		if d.x > W:
			d.x = 0.0
		dust[k] = d
	queue_redraw()


# -------------------------------------------------------------------- UI
func _btn(text: String, rect: Rect2, cb: Callable, enabled: bool = true, col: Color = RUST) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.55)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	var sbd: StyleBoxFlat = sb.duplicate()
	sbd.bg_color = Color("2a3038")
	sbd.border_color = Color("4a525c")
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sbd)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.pressed.connect(cb)
	ui.add_child(b)
	return b


func _rebuild_ui() -> void:
	for c in ui.get_children():
		ui.remove_child(c)
		c.queue_free()
	match screen:
		"base":
			_build_base_ui()
		"run":
			_build_run_ui()
		"results":
			_btn("BACK TO BASE", Rect2(160, 960, 400, 90), go_base)


func _build_base_ui() -> void:
	var coins: int = int(save["coins"])
	if sel >= 0 and sel != BaseMeta.CORE_SLOT:
		var e: Dictionary = BaseMeta.slot_of(save, sel)
		if not BaseMeta.is_unlocked(save, sel):
			var c: int = BaseMeta.unlock_cost(save)
			_btn("Unlock slot  ◆%d" % c, Rect2(160, 910, 400, 80), func() -> void: _base_act(BaseMeta.try_unlock(save, sel)), coins >= c)
		elif e.is_empty():
			var ids: Array = BuildingDB.ids()
			for k in ids.size():
				var id: String = ids[k]
				var pc: int = BaseMeta.place_cost(id)
				var d: Dictionary = BuildingDB.get_def(id)
				var rect := Rect2(14 + (k % 4) * 175, 900 + (k / 4) * 74, 166, 66)
				var b := _btn("%s\n◆%d" % [String(d["name"]), pc], rect, func() -> void: _base_act(BaseMeta.try_place(save, sel, id)), coins >= pc, BuildingDB.cat_color(String(d["cat"])))
				b.add_theme_font_size_override("font_size", 18)
		else:
			var lvl: int = int(e["lvl"])
			var uc: int = BaseMeta.upgrade_cost(lvl)
			_btn("Upgrade Lv%d→%d  ◆%d" % [lvl, lvl + 1, uc], Rect2(20, 910, 440, 80), func() -> void: _base_act(BaseMeta.try_upgrade(save, sel)), coins >= uc and lvl < BaseMeta.MAX_LVL, BuildingDB.cat_color(BuildingDB.cat_of(String(e["id"]))))
			_btn("Demolish", Rect2(480, 910, 220, 80), func() -> void: _base_act(BaseMeta.demolish(save, sel)), true, ENEMY)
	var core: Dictionary = save["core"]
	var labels: Dictionary = {"dmg": "Core DMG", "hp": "Core HP", "regen": "Regen"}
	var k2: int = 0
	for stat in BaseMeta.CORE_STATS:
		var lv: int = int(core[stat])
		var cc: int = BaseMeta.core_cost(lv)
		var st: String = stat
		var b2 := _btn("%s Lv%d\n◆%d" % [String(labels[stat]), lv, cc], Rect2(14 + k2 * 235, 1062, 222, 74), func() -> void: _base_act(BaseMeta.try_core(save, st)), coins >= cc and lv < BaseMeta.MAX_LVL, Color.WHITE)
		b2.add_theme_font_size_override("font_size", 19)
		k2 += 1
	var sb := _btn("START RUN", Rect2(110, 1160, 500, 96), start_run, true, RUST)
	sb.add_theme_font_size_override("font_size", 34)


func _base_act(ok: bool) -> void:
	if ok:
		slot_pop[sel] = 0.3
		MetaSave.write(save)
	_rebuild_ui()


func _build_run_ui() -> void:
	if S.draft.size() > 0:
		for k in S.draft.size():
			var card: Dictionary = S.draft[k]
			var id: String = card["id"]
			var d: Dictionary = BuildingDB.get_def(id)
			var head: String = "NEW" if String(card["kind"]) == "new" else "+1 LEVEL"
			var idx: int = k
			var b := _btn("%s\n%s\n\n%s" % [head, String(d["name"]), String(d["desc"])], Rect2(14 + k * 234, 900, 222, 230), func() -> void: _handle(S.choose_card(idx)), true, BuildingDB.cat_color(String(d["cat"])))
			b.add_theme_font_size_override("font_size", 19)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	if S.pending_place != "":
		return
	if sel == TowerState.CORE_SLOT:
		var c: int = S.upgrade_cost(sel)
		_btn("Core DMG +25%%  $%d" % c, Rect2(160, 960, 400, 84), func() -> void: _handle(S.upgrade(sel)), S.cash >= float(c), Color.WHITE)
	elif sel >= 0:
		if not bool(S.unlocked[sel]):
			var uc: int = S.unlock_cost()
			_btn("Unlock plot (this run)  $%d" % uc, Rect2(110, 960, 500, 84), func() -> void: _handle(S.unlock_plot(sel)), S.cash >= float(uc))
		elif S.id_at(sel) != "":
			var c2: int = S.upgrade_cost(sel)
			_btn("Upgrade Lv%d→%d  $%d" % [S.lvl_at(sel), S.lvl_at(sel) + 1, c2], Rect2(160, 960, 400, 84), func() -> void: _handle(S.upgrade(sel)), S.cash >= float(c2) and S.lvl_at(sel) < TowerState.MAX_LVL, BuildingDB.cat_color(BuildingDB.cat_of(S.id_at(sel))))


# ------------------------------------------------------------------ draw
func _text(s: String, pos: Vector2, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER, width: float = -1.0) -> void:
	var w: float = width
	var p: Vector2 = pos
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0.0:
		w = 600.0
		p.x -= 300.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	draw_string(font, p + Vector2(2, 2), s, align, w, size, Color(0, 0, 0, 0.6))
	draw_string(font, p, s, align, w, size, col)


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), BG)
	var off: Vector2 = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO
	draw_set_transform(off)
	_draw_background()
	_draw_base()
	if screen != "base" and S != null:
		_draw_world()
	draw_set_transform(Vector2.ZERO)
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(0.9, 0.15, 0.2, flash * 0.5))
	_draw_hud()


func _draw_background() -> void:
	var gc := Color(1, 1, 1, 0.035)
	var x: float = 0.0
	while x <= W:
		draw_line(Vector2(x, 0), Vector2(x, ARENA_BOTTOM), gc, 1.0)
		x += 40.0
	var y: float = 0.0
	while y <= ARENA_BOTTOM:
		draw_line(Vector2(0, y), Vector2(W, y), gc, 1.0)
		y += 40.0
	for d in dust:
		var dv: Vector3 = d
		draw_rect(Rect2(dv.x, dv.y, 2, 2), Color(0.85, 0.47, 0.23, 0.25))
	# core range ring
	var rr: float = 280.0
	draw_arc(TowerState.CENTER, rr, 0, TAU, 96, Color(1, 1, 1, 0.06), 2.0)


func _slot_color(id: String) -> Color:
	return BuildingDB.cat_color(BuildingDB.cat_of(id))


func _draw_base() -> void:
	var c: float = TowerState.CELL
	# base plate
	var plate := Rect2(TowerState.CENTER - Vector2(2.5 * c + 6, 2.5 * c + 6), Vector2(5 * c + 12, 5 * c + 12))
	draw_rect(plate, Color("12161b"))
	draw_rect(plate, RUST.darkened(0.3), false, 3.0)
	var placing: bool = screen == "run" and S != null and S.pending_place != ""
	for i in 25:
		var p: Vector2 = TowerState.slot_pos(i)
		var sc: float = 1.0
		if slot_pop.has(i):
			sc = 1.0 + 0.35 * float(slot_pop[i]) / 0.3
		var half: float = (c * 0.5 - 3.0) * sc
		var r := Rect2(p - Vector2(half, half), Vector2(half * 2, half * 2))
		if i == TowerState.CORE_SLOT:
			var pulse: float = 0.5 + 0.5 * sin(t_anim * 3.0)
			draw_rect(r.grow(8 + 4 * pulse), Color(1, 1, 1, 0.12))
			draw_rect(r, Color("f4f6f8"))
			draw_rect(r.grow(-10), RUST)
			draw_arc(p, half + 14 + 6 * pulse, 0, TAU, 40, Color(1, 1, 1, 0.35), 2.0)
		else:
			var unlocked: bool
			var id: String
			var lvl: int
			if screen == "base" or S == null:
				unlocked = BaseMeta.is_unlocked(save, i)
				var e: Dictionary = BaseMeta.slot_of(save, i)
				id = "" if e.is_empty() else String(e["id"])
				lvl = 0 if e.is_empty() else int(e["lvl"])
			else:
				unlocked = bool(S.unlocked[i])
				id = S.id_at(i)
				lvl = S.lvl_at(i)
			if not unlocked:
				draw_rect(r, Color("161a1f"))
				draw_line(r.position + Vector2(10, 10), r.end - Vector2(10, 10), Color("39414b"), 2.0)
				draw_line(Vector2(r.end.x - 10, r.position.y + 10), Vector2(r.position.x + 10, r.end.y - 10), Color("39414b"), 2.0)
			elif id == "":
				var oc := Color("4a5560")
				if placing:
					oc = Color(1, 1, 1, 0.4 + 0.4 * sin(t_anim * 8.0))
				draw_rect(r, Color("1f252c"))
				draw_rect(r, oc, false, 2.0)
			else:
				_draw_building(id, lvl, r)
		if i == sel:
			draw_rect(r.grow(4), Color(1, 1, 1, 0.9), false, 3.0)


func _draw_building(id: String, lvl: int, r: Rect2) -> void:
	var col: Color = _slot_color(id)
	draw_rect(r.grow(5), Color(col, 0.18))
	draw_rect(r, col.darkened(0.45))
	draw_rect(r, col, false, 3.0)
	var p: Vector2 = r.get_center()
	var g: Color = col.lightened(0.3)
	match id:
		"gun":
			draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), g)
			draw_line(p, p + Vector2(0, -16), g, 5.0)
		"mortar":
			draw_circle(p, 10.0, g)
			draw_circle(p, 5.0, col.darkened(0.6))
		"tesla":
			draw_polyline(PackedVector2Array([p + Vector2(-8, -12), p + Vector2(4, -3), p + Vector2(-4, 3), p + Vector2(8, 12)]), g, 3.0)
		"armory":
			draw_rect(Rect2(p - Vector2(3, 11), Vector2(6, 22)), g)
			draw_rect(Rect2(p - Vector2(11, 3), Vector2(22, 6)), g)
		"bulwark":
			draw_rect(Rect2(p - Vector2(11, 11), Vector2(22, 22)), g, false, 4.0)
		"mine":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -11), p + Vector2(11, 9), p + Vector2(-11, 9)]), g)
		"oilmill":
			draw_circle(p + Vector2(0, 3), 8.0, g)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(6, 0), p + Vector2(-6, 0)]), g)
		"bounty":
			_text("$", p + Vector2(0, 9), 24, g)
	if lvl > 0:
		_text(str(lvl), r.position + Vector2(r.size.x - 3, 15), 13, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 18.0)


func _draw_world() -> void:
	for e in S.enemies:
		var ed: Dictionary = e
		var p: Vector2 = ed["pos"]
		var s: float = float(ed["size"])
		var kind: String = ed["kind"]
		var col: Color = ENEMY
		if kind == "skitter" or kind == "boss":
			col = ENEMY2
		draw_rect(Rect2(p - Vector2(s, s) * 0.9, Vector2(s, s) * 1.8), Color(col, 0.15))
		if kind == "skitter":
			var dir: Vector2 = (TowerState.CENTER - p).normalized()
			var n: Vector2 = Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([p + dir * s, p - dir * s * 0.7 + n * s * 0.8, p - dir * s * 0.7 - n * s * 0.8]), col)
		else:
			draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), col)
			if kind == "boss" or kind == "hauler":
				draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), col.lightened(0.4), false, 3.0)
		if float(ed["slow_t"]) > 0.0:
			draw_rect(Rect2(p - Vector2(s, s) * 0.6, Vector2(s, s) * 1.2), Color("b48cff"), false, 2.0)
		var frac: float = float(ed["hp"]) / float(ed["max_hp"])
		if frac < 1.0:
			draw_rect(Rect2(p + Vector2(-s * 0.6, s * 0.7), Vector2(s * 1.2, 3)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(p + Vector2(-s * 0.6, s * 0.7), Vector2(s * 1.2 * frac, 3)), col.lightened(0.3))
	for f in tracers:
		var fd: Dictionary = f
		var a: float = float(fd["t"]) / 0.12
		var tc: Color = fd["color"]
		draw_line(fd["a"], fd["b"], Color(tc, 0.25 * a), float(fd["w"]) * 3.0)
		draw_line(fd["a"], fd["b"], Color(tc, a), float(fd["w"]))
	for f in rings:
		var fd2: Dictionary = f
		var rc: Color = fd2["color"]
		draw_arc(fd2["pos"], float(fd2["r"]) * (1.3 - float(fd2["t"])), 0, TAU, 32, Color(rc, minf(1.0, float(fd2["t"]) * 4.0)), 3.0)
	if level_burst > 0.0:
		var k: float = 1.0 - level_burst / 0.6
		draw_arc(TowerState.CENTER, 40.0 + 420.0 * k, 0, TAU, 96, Color(BuildingDB.cat_color("eco"), 1.0 - k), 8.0)
	for f in pops:
		var fd3: Dictionary = f
		var pp: Vector2 = fd3["pos"]
		var lift: float = (1.0 - float(fd3["t"])) * 30.0
		var pc: Color = fd3["color"]
		_text(String(fd3["text"]), pp - Vector2(0, lift), int(fd3["size"]), Color(pc, minf(1.0, float(fd3["t"]) * 2.5)))


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color("0e1115"))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Color(1, 1, 1, 0.2), false, 2.0)


func _draw_hud() -> void:
	draw_rect(Rect2(0, ARENA_BOTTOM + 30, W, H - ARENA_BOTTOM - 30), PANEL)
	draw_line(Vector2(0, ARENA_BOTTOM + 30), Vector2(W, ARENA_BOTTOM + 30), RUST, 3.0)
	if screen == "base":
		_text("COREHOLD", Vector2(360, 62), 46, TEXT)
		_text("◆ %d coins" % int(save["coins"]), Vector2(24, 110), 26, BuildingDB.cat_color("eco"), HORIZONTAL_ALIGNMENT_LEFT, 300.0)
		_text("Best wave %d" % int(save["best_wave"]), Vector2(696, 110), 24, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
		var hint: String = "Tap a slot to build your permanent base"
		if sel == BaseMeta.CORE_SLOT:
			hint = "The Core — upgrade it below"
		elif sel >= 0:
			var e: Dictionary = BaseMeta.slot_of(save, sel)
			if not e.is_empty():
				var d: Dictionary = BuildingDB.get_def(String(e["id"]))
				hint = "%s Lv%d — %s" % [String(d["name"]), int(e["lvl"]), String(d["desc"])]
			elif BaseMeta.is_unlocked(save, sel):
				hint = "Empty slot — pick a building"
			else:
				hint = "Locked outer slot"
		_text(hint, Vector2(360, 830), 22, TEXT)
		_text("PERMANENT CORE", Vector2(360, 1052), 18, DIM)
		return
	if S == null:
		return
	# top HUD
	_text("WAVE %d" % S.wave, Vector2(360, 50), 40, TEXT)
	_bar(Rect2(160, 66, 400, 16), S.wave_t / S.wave_time, Color(1, 1, 1, 0.35))
	_text("$%d" % int(S.cash), Vector2(24, 50), 34, BuildingDB.cat_color("eco"), HORIZONTAL_ALIGNMENT_LEFT, 200.0)
	_text("◆%d" % int(S.coins_run), Vector2(696, 50), 28, BuildingDB.cat_color("eco").lightened(0.3), HORIZONTAL_ALIGNMENT_RIGHT, 200.0)
	var mhp: float = float(S.stats["max_hp"])
	_bar(Rect2(160, 96, 400, 22), S.hp / mhp, Color("e8434f"))
	_text("%d / %d" % [int(S.hp), int(mhp)], Vector2(360, 114), 18, TEXT)
	# xp bar
	_bar(Rect2(20, ARENA_BOTTOM - 4, 680, 18), S.xp / S.xp_need(), Color("6bd46b"))
	_text("LV %d" % S.level, Vector2(360, ARENA_BOTTOM + 11), 16, TEXT)
	if screen == "results":
		draw_rect(Rect2(60, 300, 600, 380), Color(0, 0, 0, 0.75))
		_text("CORE DESTROYED", Vector2(360, 380), 44, ENEMY)
		_text("Reached wave %d" % int(last_result.get("wave", 0)), Vector2(360, 460), 32, TEXT)
		_text("%d kills" % int(last_result.get("kills", 0)), Vector2(360, 510), 26, DIM)
		_text("+◆%d coins banked" % int(last_result.get("coins", 0)), Vector2(360, 580), 32, BuildingDB.cat_color("eco"))
		_text("Spend them on your permanent base", Vector2(360, 630), 20, DIM)
		return
	if S.draft.size() > 0:
		_text("LEVEL UP — pick a building", Vector2(360, 1170), 26, TEXT)
		_text("Eco grows faster · weapons survive longer", Vector2(360, 1206), 20, DIM)
		return
	if S.pending_place != "":
		var d2: Dictionary = BuildingDB.get_def(S.pending_place)
		_text("Tap a free slot to place", Vector2(360, 950), 26, TEXT)
		_text(String(d2["name"]), Vector2(360, 995), 34, BuildingDB.cat_color(String(d2["cat"])))
		_text("(time slowed)", Vector2(360, 1035), 20, DIM)
		return
	var info: String = "Tap a building to upgrade it with cash"
	if sel == TowerState.CORE_SLOT:
		info = "Core — %.0f dmg" % float((S.stats["weapons"] as Array).back()["dmg"])
	elif sel >= 0 and S.id_at(sel) != "":
		var d3: Dictionary = BuildingDB.get_def(S.id_at(sel))
		info = "%s Lv%d — %s" % [String(d3["name"]), S.lvl_at(sel), String(d3["desc"])]
	elif sel >= 0 and not bool(S.unlocked[sel]):
		info = "Locked plot — unlock for this run"
	_text(info, Vector2(360, 925), 22, TEXT)
	var st: Dictionary = S.stats
	_text("$%.1f/s   XP ×%.2f   Bounty ×%.2f   Regen %.1f/s" % [float(st["cash_ps"]), float(st["xp_mult"]), float(st["bounty_mult"]), float(st["regen"])], Vector2(360, 1230), 19, DIM)
