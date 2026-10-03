extends Node2D
## Corehold view. Pure replay of TowerState / meta events + _draw() with ArtDB
## textures (primitive fallback when a texture is missing).
## Never owns a rule: every tap calls an engine / BaseMeta / Labs / Cards /
## Missions / Offline action and replays the returned events.
## Screens: "base" (tabs base|labs|cards|missions), "run", "results".
## Meta tab drawing + buttons live in ui/MetaTabs.gd.

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const PerkDB := preload("res://data/PerkDB.gd")
const LabDB := preload("res://data/LabDB.gd")
const CardDB := preload("res://data/CardDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const TuneRef := preload("res://Tune.gd")
const Labs := preload("res://Labs.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const Offline := preload("res://Offline.gd")
const Tiers := preload("res://Tiers.gd")
const Art := preload("res://ArtDB.gd")
const Tabs := preload("res://ui/MetaTabs.gd")
const RunView := preload("res://ui/RunView.gd")
const SfxScript := preload("res://Sfx.gd")
const Menus := preload("res://ui/Menus.gd")

const W: float = 720.0
const H: float = 1280.0
const BG: Color = Color("1b2027")
const PANEL: Color = Color("232a33")
const PANEL2: Color = Color("2b333d")
const RUST: Color = Color("d9773a")
const ENEMY: Color = Color("e8434f")
const ENEMY2: Color = Color("e04bc0")
const TEXT: Color = Color("e9edf2")
const DIM: Color = Color("9aa6b2")
const GOLD: Color = Color("f2c94c")
const GEM: Color = Color("5ad1f0")
const SHIELD: Color = Color("7fd8ff")
const ARENA_BOTTOM: float = 860.0
const TAB_IDS: Array = ["base", "labs", "cards", "missions"]
const TAB_NAMES: Array = ["Base", "Labs", "Cards", "Missions"]

var save: Dictionary = {}
var S: RefCounted = null
var screen: String = "base"
var tab: String = "base"
var sel: int = -1
var last_result: Dictionary = {}
var last_breakdown: Dictionary = {}
var ui: Control
var font: Font
var t_anim: float = 0.0
var ui_t: float = 0.0
var poll_t: float = 0.0
var last_tap_ms: int = -1000
var now_override: int = 0          # tests inject unix time here
var offline_offer: Dictionary = {} # {coins, minutes} while the modal is up
var toast_text: String = ""
var toast_t: float = 0.0
var toast_queue: Array = []
var view_tier: int = 1
var chest_msg: String = ""
var run_missions: int = 0
var meta_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var sfx: Node = null   # Sfx.gd (owned child, not an autoload)
var overlay: String = ""  # "", "options", "pause", "credits" (ui/Menus.gd)
var fader: ColorRect      # screen-transition fade (above ui, ignores input)
var fade: float = 0.0
const FADE_TIME: float = 0.25

# fx
var tracers: Array = []    # {a, b, t, color, w}
var rings: Array = []      # {pos, r, t, color}
var pops: Array = []       # {pos, text, t, color, size}
const BOUNTY_BANNER_DY: float = 3.4 * TowerState.CELL   # below the grid's bottom edge (2.5 cells)
var bolts: Array = []      # {a, t}
var slot_pop: Dictionary = {}
var shake: float = 0.0
var flash: float = 0.0
var heal_flash: float = 0.0
var level_burst: float = 0.0
var dust: Array = []


func _ready() -> void:
	font = ThemeDB.fallback_font
	meta_rng.seed = int(Time.get_ticks_usec() % 1000000007)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.position = Vector2.ZERO
	ui.size = Vector2(W, H)
	add_child(ui)
	fader = ColorRect.new()
	fader.color = Color(0.05, 0.06, 0.08, 1.0)
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fader.size = Vector2(W, H)
	fader.modulate = Color(1, 1, 1, 0)
	add_child(fader)
	sfx = SfxScript.new()
	sfx.name = "Sfx"
	add_child(sfx)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for k in 40:
		dust.append(Vector3(r.randf() * W, r.randf() * ARENA_BOTTOM, r.randf_range(4.0, 14.0)))
	boot(MetaSave.read(), now())


## SPEC boot: migrate -> normalize -> Labs.claim -> Missions.roll -> Offline modal.
func boot(raw: Dictionary, t: int) -> void:
	save = BaseMeta.normalize(raw)
	var ev: Array = Labs.claim(save, t)
	ev.append_array(Missions.roll(save, t))
	var off: Dictionary = Offline.compute(save, t)
	if int(off["coins"]) > 0:
		offline_offer = off
	else:
		offline_offer = {}
		Offline.claim(save, t)
	view_tier = int(save["tier"])
	screen = "base"
	tab = "base"
	sel = -1
	overlay = ""
	_queue_toasts(ev)
	MetaSave.write(save)
	if sfx != null:
		sfx.apply_settings(save["settings"])
		sfx.music_play()
	_rebuild_ui()


func now() -> int:
	if now_override > 0:
		return now_override
	return int(Time.get_unix_time_from_system())


static func fmt_dur(sec: int) -> String:
	var s: int = maxi(0, sec)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%ds" % s


static func fmt_num(v: int) -> String:
	if v >= 1000000:
		return "%.2fM" % (float(v) / 1000000.0)
	if v >= 10000:
		return "%.1fk" % (float(v) / 1000.0)
	return str(v)


# ------------------------------------------------------------------ flow
func start_run() -> void:
	if not Tiers.is_unlocked(save, view_tier):
		return
	BaseMeta.select_tier(save, view_tier)
	S = TowerState.new()
	_clear_fx()
	run_missions = 0
	last_breakdown = {}
	_handle(S.setup(TuneRef.seed_of(int(Time.get_ticks_usec() % 1000000)), save, now()))
	screen = "run"
	sel = -1
	overlay = ""
	_fade_in()
	_rebuild_ui()


func go_base() -> void:
	screen = "base"
	tab = "base"
	sel = -1
	overlay = ""
	_fade_in()
	_clear_fx()
	view_tier = int(save["tier"])
	var lev: Array = Labs.claim(save, now())
	_queue_toasts(lev)
	_meta_sfx(lev)
	_rebuild_ui()


## Short fade-from-dark on screen changes (Maaack scene-loader fade, inlined).
func _fade_in() -> void:
	fade = FADE_TIME


## Options / pause / credits modal. While a modal is up on the run screen the
## engine is not ticked (game time frozen).
func set_overlay(id: String) -> void:
	overlay = id
	sel = -1
	_rebuild_ui()


func is_paused() -> bool:
	return screen == "run" and overlay != ""


## Pause menu "Abandon run": the engine banks coins via its normal death path
## and emits game_over / dead, which the view replays like a real death.
func abandon_run() -> void:
	if S == null or screen != "run":
		return
	overlay = ""
	_handle(S.abandon())
	_fade_in()
	_rebuild_ui()


func toggle_mute_ui() -> void:
	toggle_mute()
	_rebuild_ui()


func set_tab(id: String) -> void:
	tab = id
	sel = -1
	_rebuild_ui()


func _save() -> void:
	if offline_offer.is_empty():
		save["last_seen"] = now()
	MetaSave.write(save)


## Every meta action funnels through here: toast, persist, rebuild.
func meta_act(ev: Array) -> void:
	if not ev.is_empty():
		_queue_toasts(ev)
		_meta_sfx(ev)
		_save()
	_rebuild_ui()


func claim_offline(double: bool) -> void:
	var ev: Array = Offline.claim(save, now(), double)
	if ev.is_empty() and double:
		_queue_toasts([{"t": "msg", "text": "Not enough gems"}])
		_rebuild_ui()
		return
	offline_offer = {}
	meta_act(ev)


func shift_tier(d: int) -> void:
	view_tier = clampi(view_tier + d, 1, mini(Tiers.tier_max(), Tiers.highest(save) + 1))
	if BaseMeta.select_tier(save, view_tier):
		_save()
	_rebuild_ui()


func cycle_speed() -> void:
	if S == null:
		return
	var steps: Array = Labs.speed_steps(save)
	if steps.size() <= 1:
		return
	var idx: int = 0
	for k in steps.size():
		if absf(float(steps[k]) - S.speed) < 0.01:
			idx = k
	var v: float = float(steps[(idx + 1) % steps.size()])
	BaseMeta.set_speed(save, v)
	_handle(S.set_speed(v))
	_rebuild_ui()


func _clear_fx() -> void:
	tracers.clear()
	rings.clear()
	pops.clear()
	bolts.clear()
	slot_pop.clear()
	shake = 0.0
	flash = 0.0
	heal_flash = 0.0
	level_burst = 0.0


func ev_text(e: Dictionary) -> String:
	match String(e.get("t", "")):
		"msg":
			return String(e["text"])
		"lab_done":
			return "Research done: %s Lv%d" % [String((LabDB.DEFS[String(e["track"])] as Dictionary)["name"]), int(e["lvl"])]
		"lab_started":
			return "Researching %s" % String((LabDB.DEFS[String(e["track"])] as Dictionary)["name"])
		"lab_rushed":
			return "Research rushed (-%d gems)" % int(e["gems"])
		"lab_slot":
			return "Lab slot %d unlocked" % int(e["n"])
		"card_slot":
			return "Card slot %d unlocked" % int(e["n"])
		"chest_opened":
			var cn: String = String((CardDB.DEFS[String(e["card"])] as Dictionary)["name"])
			if bool(e["new"]):
				return "New card: %s!" % cn
			if bool(e["lvl_up"]):
				return "%s card -> Lv%d" % [cn, int(e["lvl"])]
			return "%s card copy +1" % cn
		"card_equipped":
			return "Equipped %s" % String((CardDB.DEFS[String(e["card"])] as Dictionary)["name"])
		"card_unequipped":
			return "Unequipped %s" % String((CardDB.DEFS[String(e["card"])] as Dictionary)["name"])
		"mission_claimed":
			return "Mission reward +%d gems" % int(e["gems"])
		"mission_bonus":
			return "All-clear bonus +%d gems" % int(e["gems"])
		"mission_done":
			return "Mission complete!"
		"streak_claimed":
			return "Day %d reward: +%d coins +%d gems" % [int(e["day"]), int(e["coins"]), int(e["gems"])]
		"offline":
			return "Collected %d offline coins" % int(e["coins"])
		"tier_unlocked":
			return "Tier %d unlocked! +%d gems" % [int(e["tier"]), int(e["gems"])]
		"missions_rolled":
			return "New daily missions"
	return ""


## Audio for meta (base-screen) events. Rules stay in the engines; this only maps event -> clip.
func _meta_sfx(ev: Array) -> void:
	for x in ev:
		match String((x as Dictionary)["t"]):
			"lab_done":
				sfx_play("lab_done")
			"chest_opened":
				sfx_play("card_open")
			"lab_started", "lab_rushed", "lab_slot", "card_slot":
				sfx_play("upgrade")
			"tier_unlocked":
				sfx_play("levelup")
			"offline", "mission_claimed", "streak_claimed", "mission_bonus":
				sfx_play("coin")


func sfx_play(clip: String) -> void:
	if sfx != null:
		sfx.play(clip)


## Volume / mute API: persists in save["settings"] and re-applies to the buses.
func set_audio(key: String, v: Variant) -> void:
	var st: Dictionary = save["settings"]
	st[key] = v
	if sfx != null:
		sfx.apply_settings(st)
	_save()


func toggle_mute() -> void:
	set_audio("mute", not bool((save["settings"] as Dictionary)["mute"]))


func _queue_toasts(ev: Array) -> void:
	for x in ev:
		var s: String = ev_text(x as Dictionary)
		if s != "":
			toast_queue.append(s)


## Run-event -> clip map ("shot" picks shot_<weapon kind>).
const EVENT_CLIP: Dictionary = {
	"kill": "kill", "shield_hit": "hit", "shield_break": "shield_break", "boss": "boss_spawn",
	"boss_bounty": "boss_kill", "wave": "wave_start", "run_start": "wave_start", "wave_skip": "wave_start", "levelup": "levelup",
	"perk_taken": "perk", "placed": "place", "upgraded": "upgrade", "unlocked": "place",
	"core_hit": "core_hit", "interest": "coin", "revive": "levelup", "dead": "game_over",
	"tier_unlocked": "levelup",
}


func _handle(events: Array) -> void:
	var rebuild: bool = false
	if S != null and screen == "run":
		for x in Missions.on_run_events(save, events):
			if String((x as Dictionary)["t"]) == "mission_done":
				run_missions += 1
				pops.append({"pos": Vector2(360, 300), "text": "MISSION COMPLETE", "t": 1.4, "color": GEM, "size": 26})
	for e in events:
		var ev: Dictionary = e
		var clip: String = String(EVENT_CLIP.get(String(ev["t"]), ""))
		if String(ev["t"]) == "shot":
			clip = "shot_" + String(ev["kind"])
		if clip != "":
			sfx_play(clip)
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
			"enemy_shot":
				bolts.append({"a": ev["pos"], "t": 0.25})
				flash = minf(0.3, flash + 0.06)
			"shield_hit":
				rings.append({"pos": ev["pos"], "r": 26.0, "t": 0.2, "color": SHIELD})
			"shield_break":
				rings.append({"pos": ev["pos"], "r": 44.0, "t": 0.4, "color": SHIELD})
				pops.append({"pos": ev["pos"], "text": "BREAK", "t": 0.7, "color": SHIELD, "size": 20})
			"split":
				rings.append({"pos": ev["pos"], "r": 30.0, "t": 0.3, "color": ENEMY2})
			"interest":
				var ip: Vector2 = TowerState.slot_pos(int(ev["slot"]))
				pops.append({"pos": ip, "text": "+$%d" % int(round(float(ev["amt"]))), "t": 1.0, "color": GOLD, "size": 20})
				slot_pop[int(ev["slot"])] = 0.3
			"boss_bounty":
				var bp: Vector2 = ev["pos"]
				rings.append({"pos": bp, "r": 120.0, "t": 0.6, "color": GOLD})
				var bt: String = "BOUNTY +%d coins" % int(ev["coins"])
				if int(ev["gems"]) > 0:
					bt += "  +%d gems" % int(ev["gems"])
				# Banner sits in the open band below the 5x5 grid (AC-37: never over slots).
				pops.append({"pos": TowerState.CENTER + Vector2(0, BOUNTY_BANNER_DY), "text": bt, "t": 1.6, "color": GOLD, "size": 24})
			"revive":
				heal_flash = 0.6
				pops.append({"pos": TowerState.CENTER + Vector2(0, -200), "text": "SECOND WIND!", "t": 1.6, "color": Color("6bd46b"), "size": 34})
			"wave_skip":
				pops.append({"pos": TowerState.CENTER + Vector2(0, -160), "text": "WAVE SKIP +%d" % int(ev["skipped"]), "t": 1.4, "color": GEM, "size": 28})
			"wave":
				pops.append({"pos": TowerState.CENTER + Vector2(0, -260), "text": "WAVE %d" % int(ev["wave"]), "t": 1.4, "color": TEXT, "size": 40})
			"boss":
				pops.append({"pos": TowerState.CENTER + Vector2(0, -210), "text": "BOSS INBOUND", "t": 1.8, "color": ENEMY2, "size": 30})
				shake = 10.0
			"levelup":
				level_burst = 0.6
				rebuild = true
			"perk_taken":
				pops.append({"pos": TowerState.CENTER + Vector2(0, -200), "text": String(ev["name"]), "t": 1.4, "color": GOLD, "size": 30})
				rebuild = true
			"perk_offer", "draft_reroll", "speed":
				rebuild = true
			"placed", "upgraded", "unlocked":
				slot_pop[int(ev["slot"])] = 0.3
				rebuild = true
			"place_mode":
				rebuild = true
			"tier_unlocked":
				_queue_toasts([ev])
			"game_over":
				last_breakdown = ev
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
	var t: int = Time.get_ticks_msec()
	if t - last_tap_ms < 60:
		return
	last_tap_ms = t
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
	if screen == "results" or not offline_offer.is_empty() or overlay != "":
		return
	if screen == "base" and (tab != "base" or pos.y < 150.0 or pos.y > 640.0):
		return
	if screen == "run" and pos.y > ARENA_BOTTOM:
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
	if fade > 0.0:
		fade = maxf(0.0, fade - delta)
		fader.modulate = Color(1, 1, 1, 0.9 * fade / FADE_TIME)
	if screen == "run" and S != null and overlay != "":
		pass   # paused: engine time frozen
	elif screen == "run" and S != null:
		_handle(S.tick(delta))
		ui_t += delta
		if ui_t >= 0.25 and screen == "run":
			ui_t = 0.0
			_rebuild_ui()   # refresh affordability (buttons fire on PRESS, so safe)
	elif screen == "base":
		poll_t += delta
		if poll_t >= 1.0:
			poll_t = 0.0
			var t: int = now()
			var ev: Array = Labs.claim(save, t)
			ev.append_array(Missions.roll(save, t))
			if not ev.is_empty():
				meta_act(ev)
			elif tab == "labs" or tab == "missions":
				_rebuild_ui()   # live rush costs / countdowns
	if toast_t > 0.0:
		toast_t -= delta
	elif not toast_queue.is_empty():
		toast_text = String(toast_queue.pop_front())
		toast_t = 2.4
	for arr in [tracers, rings, pops, bolts]:
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
	heal_flash = maxf(0.0, heal_flash - delta)
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
func _style(col: Color, fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	return sb


func _btn(text: String, rect: Rect2, cb: Callable, enabled: bool = true, col: Color = RUST) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.disabled = not enabled
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 22)
	var sb: StyleBoxFlat = _style(col, col.darkened(0.55))
	var sbd: StyleBoxFlat = _style(Color("4a525c"), Color("2a3038"))
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sbd)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.pressed.connect(func() -> void: sfx_play("click"))
	b.pressed.connect(cb)
	ui.add_child(b)
	return b


## A rich button: optional icon + stacked label lines ([text, size, color]).
## layout "tall" = icon on top, centred lines; "row" = icon left, left lines.
## `key` is stored as meta so tests can find text-less buttons.
func _card(rect: Rect2, lines: Array, icon_id: String, cb: Callable, enabled: bool, col: Color, key: String, layout: String = "tall", icon_sz: float = 64.0) -> Button:
	var b: Button = _btn("", rect, cb, enabled, col)
	b.set_meta("key", key)
	var x0: float = 10.0
	var y: float = 10.0
	var tex: Texture2D = Art.tex(icon_id) if icon_id != "" else null
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.size = Vector2(icon_sz, icon_sz)
		if layout == "tall":
			tr.position = Vector2((rect.size.x - icon_sz) * 0.5, 8.0)
			y = 12.0 + icon_sz
		else:
			tr.position = Vector2(8.0, (rect.size.y - icon_sz) * 0.5)
			x0 = 16.0 + icon_sz
		if not enabled:
			tr.modulate = Color(1, 1, 1, 0.45)
		b.add_child(tr)
	if layout == "row":
		var total: float = 0.0
		for ln in lines:
			total += float((ln as Array)[1]) + 6.0
		y = maxf(4.0, (rect.size.y - total) * 0.5)
	for ln in lines:
		var la: Array = ln
		var sz: int = int(la[1])
		var lb := Label.new()
		lb.text = String(la[0])
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.add_theme_font_size_override("font_size", sz)
		var lc: Color = la[2]
		lb.add_theme_color_override("font_color", lc if enabled else Color(lc, 0.55))
		lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if layout == "tall" else HORIZONTAL_ALIGNMENT_LEFT
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.position = Vector2(x0, y)
		lb.size = Vector2(rect.size.x - x0 - 8.0, float(sz) + 4.0)
		b.add_child(lb)
		y += lb.get_combined_minimum_size().y + 2.0 if layout == "tall" else float(sz) + 6.0
	return b


func _badge(b: Button) -> void:
	var tr := TextureRect.new()
	tr.texture = Art.tex("badge_dot")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = Vector2(26, 26)
	tr.position = Vector2(b.size.x - 34, 6)
	if tr.texture == null:
		var cr := ColorRect.new()
		cr.color = ENEMY
		cr.size = Vector2(16, 16)
		cr.position = Vector2(b.size.x - 26, 8)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cr)
		return
	b.add_child(tr)


func _rebuild_ui() -> void:
	for c in ui.get_children():
		ui.remove_child(c)
		c.queue_free()
	if overlay != "":
		Menus.build(self)
		return
	match screen:
		"base":
			if not offline_offer.is_empty():
				_btn("Collect", Rect2(90, 680, 260, 96), func() -> void: claim_offline(false), true, GOLD)
				_btn("x2  (2 gems)", Rect2(370, 680, 260, 96), func() -> void: claim_offline(true), int(save["gems"]) >= 2, GEM)
				return
			match tab:
				"base":
					_build_base_ui()
				"labs":
					Tabs.build_labs(self)
				"cards":
					Tabs.build_cards(self)
				"missions":
					Tabs.build_missions(self)
			_build_meta_chrome()
		"run":
			_build_run_ui()
		"results":
			_btn("BACK TO BASE", Rect2(160, 1110, 400, 96), go_base)


func _build_meta_chrome() -> void:
	# tier selector (1010-1090), START (1090-1180), tab bar (1180-1280)
	_btn("<", Rect2(16, 1012, 120, 76), func() -> void: shift_tier(-1), view_tier > 1, DIM).add_theme_font_size_override("font_size", 34)
	_btn(">", Rect2(584, 1012, 120, 76), func() -> void: shift_tier(1), view_tier < mini(Tiers.tier_max(), Tiers.highest(save) + 1), DIM).add_theme_font_size_override("font_size", 34)
	_card(Rect2(624, 1, 94, 88), [], "icon_gear", func() -> void: set_overlay("options"), true, Color("4a525c"), "GEAR", "tall", 64.0).get_child(0).position.y = 12.0
	var sb := _btn("START RUN", Rect2(110, 1094, 500, 82), start_run, Tiers.is_unlocked(save, view_tier), RUST)
	sb.add_theme_font_size_override("font_size", 34)
	var t: int = now()
	for k in TAB_IDS.size():
		var id: String = TAB_IDS[k]
		var on: bool = tab == id
		var b: Button = _card(Rect2(k * 180 + 2, 1182, 176, 96), [[String(TAB_NAMES[k]), 20, TEXT if on else DIM]], "tab_" + id, func() -> void: set_tab(id), true, RUST if on else Color("4a525c"), "TAB " + String(TAB_NAMES[k]), "tall", 44.0)
		var badge: bool = false
		match id:
			"labs":
				badge = Labs.any_done(save, t)
			"cards":
				badge = int(save["gems"]) >= Cards.chest_cost()
			"missions":
				badge = Missions.has_claimable(save) or Missions.streak_available(save, t)
		if badge:
			_badge(b)


func _build_base_ui() -> void:
	var coins: int = int(save["coins"])
	var core: Dictionary = save["core"]
	var labels: Dictionary = {"dmg": "Core DMG", "hp": "Core HP", "regen": "Regen"}
	var k2: int = 0
	for stat in BaseMeta.CORE_STATS:
		var lv: int = int(core[stat])
		var cc: int = BaseMeta.core_cost(lv)
		var st: String = stat
		var b2 := _btn("%s Lv%d/%d\n%s coins" % [String(labels[stat]), lv, BaseMeta.core_cap(save), fmt_num(cc)], Rect2(14 + k2 * 235, 664, 222, 88), func() -> void: _base_act(BaseMeta.try_core(save, st)), coins >= cc and lv < BaseMeta.core_cap(save), Color.WHITE)
		b2.add_theme_font_size_override("font_size", 20)
		k2 += 1
	if sel < 0 or sel == BaseMeta.CORE_SLOT:
		return
	var e: Dictionary = BaseMeta.slot_of(save, sel)
	if not BaseMeta.is_unlocked(save, sel):
		var c: int = BaseMeta.unlock_cost(save)
		_btn("Unlock slot  %s coins" % fmt_num(c), Rect2(160, 790, 400, 96), func() -> void: _base_act(BaseMeta.try_unlock(save, sel), "place"), coins >= c)
	elif e.is_empty():
		var ids: Array = BuildingDB.all_ids()
		for k in ids.size():
			var id: String = ids[k]
			var pc: int = BaseMeta.place_cost(id)
			var d: Dictionary = BuildingDB.get_def(id)
			var rect := Rect2(8 + (k % 5) * 141, 768 + (k / 5) * 118, 136, 112)
			_card(rect, [[String(d["name"]), 18, TEXT], ["%d coins" % pc, 18, GOLD]], id, func() -> void: _base_act(BaseMeta.try_place(save, sel, id), "place"), coins >= pc, BuildingDB.cat_color(String(d["cat"])), String(d["name"]), "tall", 40.0)
	else:
		var lvl: int = int(e["lvl"])
		var uc: int = BaseMeta.upgrade_cost(lvl)
		var cap: int = BaseMeta.perm_lvl_cap(save)
		var txt: String = "Upgrade Lv%d -> %d   %s coins" % [lvl, lvl + 1, fmt_num(uc)] if lvl < cap else "Lv%d  (cap %d — raise tier)" % [lvl, cap]
		_btn(txt, Rect2(14, 790, 456, 96), func() -> void: _base_act(BaseMeta.try_upgrade(save, sel)), coins >= uc and lvl < cap, BuildingDB.cat_color(BuildingDB.cat_of(String(e["id"]))))
		_btn("Demolish", Rect2(484, 790, 222, 96), func() -> void: _base_act(BaseMeta.demolish(save, sel)), true, ENEMY)


func _base_act(ok: bool, clip: String = "upgrade") -> void:
	if ok:
		sfx_play(clip)
		slot_pop[sel] = 0.3
		_save()
	_rebuild_ui()


func _build_run_ui() -> void:
	var steps: Array = Labs.speed_steps(save)
	_card(Rect2(590, 194, 118, 88), [], "icon_pause", func() -> void: set_overlay("pause"), true, Color("4a525c"), "PAUSE", "tall", 64.0).get_child(0).position.y = 12.0
	_card(Rect2(590, 124, 118, 60), [["%sx" % _speed_str(S.speed), 22, TEXT]], "", cycle_speed, steps.size() > 1, GEM, "SPD", "tall")
	if S.perk_offer.size() > 0:
		for k in S.perk_offer.size():
			var pid: String = S.perk_offer[k]
			var d: Dictionary = PerkDB.get_def(pid)
			var lines: Array = [[String(d["name"]), 22, TEXT], [String(d["desc"]), 18, TEXT]]
			if bool(d["tradeoff"]):
				lines.append(["COST: " + String(d["cost"]), 18, Color("ff6b6b")])
			var idx: int = k
			var fam: String = String(d["fam"])
			var col: Color = BuildingDB.cat_color("weapon") if fam == "offense" else (BuildingDB.cat_color("support") if fam == "defense" else BuildingDB.cat_color("eco"))
			_card(Rect2(14 + k * 234, 940, 222, 250), lines, "perk_" + pid.substr(2), func() -> void: _handle(S.choose_perk(idx)), true, col, "PERK " + String(d["name"]), "tall", 64.0)
		return
	if S.draft.size() > 0:
		for k in S.draft.size():
			var card: Dictionary = S.draft[k]
			var id: String = card["id"]
			var d2: Dictionary = BuildingDB.get_def(id)
			var head: String = "NEW" if String(card["kind"]) == "new" else "+1 LEVEL"
			var idx2: int = k
			_card(Rect2(14 + k * 234, 940, 222, 240), [[head, 18, GOLD], [String(d2["name"]), 22, TEXT], [String(d2["desc"]), 18, DIM]], id, func() -> void: _handle(S.choose_card(idx2)), true, BuildingDB.cat_color(String(d2["cat"])), head + " " + String(d2["name"]), "tall", 56.0)
		if S.rerolls_left > 0:
			_btn("Reroll (%d left)" % S.rerolls_left, Rect2(220, 1190, 280, 80), func() -> void: _handle(S.reroll_draft()), true, GEM)
		return
	if S.pending_place != "":
		return
	if sel == TowerState.CORE_SLOT:
		var c: int = S.upgrade_cost(sel)
		var ocp: float = float(S.stats.get("overcharge_step", 0.02)) * 100.0
		_btn("Overcharge: all dmg +%.1f%%  $%d" % [ocp, c], Rect2(130, 960, 460, 90), func() -> void: _handle(S.upgrade(sel)), S.cash >= float(c), Color.WHITE)
	elif sel >= 0:
		if not bool(S.unlocked[sel]):
			var uc: int = S.unlock_cost()
			_btn("Unlock plot (this run)  $%d" % uc, Rect2(110, 960, 500, 90), func() -> void: _handle(S.unlock_plot(sel)), S.cash >= float(uc))
		elif S.id_at(sel) != "":
			var c2: int = S.upgrade_cost(sel)
			_btn("Upgrade Lv%d -> %d  $%d" % [S.lvl_at(sel), S.lvl_at(sel) + 1, c2], Rect2(160, 960, 400, 90), func() -> void: _handle(S.upgrade(sel)), S.cash >= float(c2) and S.lvl_at(sel) < TowerState.lvl_cap(), BuildingDB.cat_color(BuildingDB.cat_of(S.id_at(sel))))


static func _speed_str(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.01 else "%.1f" % v


# ------------------------------------------------------------------ draw
func _text(s: String, pos: Vector2, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER, width: float = -1.0) -> void:
	var w: float = width
	var p: Vector2 = pos
	if align == HORIZONTAL_ALIGNMENT_CENTER and width < 0.0:
		w = 680.0
		p.x -= 340.0
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	draw_string(font, p + Vector2(2, 2), s, align, w, size, Color(0, 0, 0, 0.6))
	draw_string(font, p, s, align, w, size, col)


## Draws an ArtDB texture; returns false (draws nothing) when it is missing.
func _icon(id: String, r: Rect2, mod: Color = Color.WHITE) -> bool:
	var t: Texture2D = Art.tex(id)
	if t == null:
		return false
	draw_texture_rect(t, r, false, mod)
	return true


func _panel(r: Rect2, border: Color = Color("3a434e"), fill: Color = PANEL) -> void:
	draw_style_box(_style(border, fill), r)


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color("0e1115"))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Color(1, 1, 1, 0.2), false, 2.0)


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), BG)
	var off: Vector2 = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO
	draw_set_transform(off)
	_draw_background()
	if screen != "base" or tab == "base":
		_draw_base()
	if screen != "base" and S != null:
		RunView.draw_links(self)
		RunView.draw_world(self)
	draw_set_transform(Vector2.ZERO)
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(0.9, 0.15, 0.2, flash * 0.5))
	if heal_flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(0.4, 0.9, 0.4, heal_flash * 0.4))
	if screen == "base":
		_draw_meta()
	else:
		RunView.draw_hud(self)
	if overlay != "":
		Menus.draw(self)


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
	if screen != "base":
		draw_arc(TowerState.CENTER, 280.0, 0, TAU, 96, Color(1, 1, 1, 0.06), 2.0)


func _draw_base() -> void:
	var c: float = TowerState.CELL
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
			draw_rect(r.grow(8 + 4 * pulse), Color(1, 1, 1, 0.10))
			if not _icon("core", r.grow(6)):
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
				if not _icon("icon_lock", r.grow(-12), Color(1, 1, 1, 0.35)):
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
	var col: Color = BuildingDB.cat_color(BuildingDB.cat_of(id))
	if not _icon(id, r.grow(3)):
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
			"tesla":
				draw_polyline(PackedVector2Array([p + Vector2(-8, -12), p + Vector2(4, -3), p + Vector2(-4, 3), p + Vector2(8, 12)]), g, 3.0)
			"armory":
				draw_rect(Rect2(p - Vector2(3, 11), Vector2(6, 22)), g)
				draw_rect(Rect2(p - Vector2(11, 3), Vector2(22, 6)), g)
			"mine":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -11), p + Vector2(11, 9), p + Vector2(-11, 9)]), g)
			_:
				draw_rect(Rect2(p - Vector2(11, 11), Vector2(22, 22)), g, false, 4.0)
	if lvl > 0:
		var bc: Vector2 = r.position + Vector2(r.size.x - 10, 10)
		draw_circle(bc, 11.0, Color("0e1115"))
		draw_arc(bc, 11.0, 0, TAU, 20, col, 2.0)
		_text(str(lvl), bc + Vector2(0, 6), 18, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 30.0)


func _counter(id: String, n: String, pos: Vector2, size: int, col: Color, isz: float = 34.0) -> void:
	if not _icon(id, Rect2(pos - Vector2(0, isz * 0.5 + size * 0.35), Vector2(isz, isz))):
		draw_circle(pos + Vector2(isz * 0.5, -size * 0.35), isz * 0.35, col)
	_text(n, pos + Vector2(isz + 6, 0), size, col, HORIZONTAL_ALIGNMENT_LEFT, 200.0)


# ------------------------------------------------------------- meta screen
func _draw_meta() -> void:
	var t: int = now()
	# top bar
	draw_rect(Rect2(0, 0, W, 90), PANEL)
	draw_line(Vector2(0, 90), Vector2(W, 90), RUST, 3.0)
	_counter("icon_coin", fmt_num(int(save["coins"])), Vector2(14, 58), 28, GOLD, 46.0)
	_counter("icon_gem", str(int(save["gems"])), Vector2(216, 58), 28, GEM, 46.0)
	var st: Dictionary = save["streak"]
	_counter("icon_streak", "Streak %d" % int(st["day_idx"]), Vector2(330, 58), 24, Color("ff9f5a"), 46.0)
	_text("Best w%d" % int(save["best_wave"]), Vector2(610, 56), 22, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
	# banner
	if toast_t > 0.0 and toast_text != "":
		var a: float = clampf(toast_t * 3.0, 0.0, 1.0)
		_panel(Rect2(16, 98, 688, 48), Color(GOLD, a), Color(0.18, 0.15, 0.08, 0.95 * a))
		_text(toast_text, Vector2(360, 130), 22, Color(TEXT, a))
	else:
		_text("COREHOLD", Vector2(360, 136), 36, Color(TEXT, 0.9))
	match tab:
		"base":
			_draw_base_tab()
		"labs":
			Tabs.draw_labs(self, t)
		"cards":
			Tabs.draw_cards(self)
		"missions":
			Tabs.draw_missions(self, t)
	# tier selector
	draw_rect(Rect2(0, 1004, W, 276), PANEL)
	draw_line(Vector2(0, 1004), Vector2(W, 1004), Color("3a434e"), 2.0)
	if Tiers.is_unlocked(save, view_tier):
		_icon("icon_tier", Rect2(170, 1028, 40, 40))
		_text("TIER %d" % view_tier, Vector2(220, 1060), 30, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 150.0)
		_text("x%.1f coins" % Tiers.coin_mult(view_tier), Vector2(370, 1046), 20, GOLD, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
		_text("enemy HP x%.1f" % Tiers.hp_mult(view_tier), Vector2(370, 1074), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
	else:
		_icon("icon_lock", Rect2(160, 1030, 36, 36), Color(1, 1, 1, 0.7))
		_text(Tiers.requirement(view_tier), Vector2(380, 1060), 26, Color("ff8a8a"), HORIZONTAL_ALIGNMENT_CENTER, 360.0)
	if not offline_offer.is_empty():
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.7))
		_panel(Rect2(50, 360, 620, 440), GOLD, PANEL2)
		_text("WELCOME BACK", Vector2(360, 430), 38, TEXT)
		_text("Away %s — your base kept mining" % fmt_dur(int(offline_offer["minutes"]) * 60), Vector2(360, 480), 22, DIM)
		_icon("icon_coin", Rect2(200, 528, 64, 64))
		_text("+%s" % fmt_num(int(offline_offer["coins"])), Vector2(280, 580), 48, GOLD, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
		_text("coins earned offline", Vector2(360, 640), 22, TEXT)


func _draw_base_tab() -> void:
	_text("PERMANENT BASE", Vector2(360, 196), 26, TEXT)
	_text("Runs %d  ·  Perm level cap %d  ·  Tier %d unlocked" % [int(save["runs"]), BaseMeta.perm_lvl_cap(save), Tiers.highest(save)], Vector2(360, 232), 18, DIM)
	var hint: String = "Tap a slot to build your permanent base"
	if sel == BaseMeta.CORE_SLOT:
		hint = "The Core — upgrade it below"
	elif sel >= 0:
		var e: Dictionary = BaseMeta.slot_of(save, sel)
		if not e.is_empty():
			var d: Dictionary = BuildingDB.get_def(String(e["id"]))
			hint = "%s Lv%d" % [String(d["name"]), int(e["lvl"])]
			_text(String(d["desc"]), Vector2(360, 310), 18, DIM)
		elif BaseMeta.is_unlocked(save, sel):
			hint = "Empty slot — pick a building"
		else:
			hint = "Locked outer slot"
	_text(hint, Vector2(360, 284), 22, TEXT)
	_text("PERMANENT CORE", Vector2(360, 650), 18, DIM)
	if sel >= 0 and sel != BaseMeta.CORE_SLOT and BaseMeta.is_unlocked(save, sel) and BaseMeta.slot_of(save, sel).is_empty():
		_text("BUILD (permanent)", Vector2(360, 762), 18, DIM)


# --------------------------------------------------------------- run HUD


