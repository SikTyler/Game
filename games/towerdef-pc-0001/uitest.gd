extends SceneTree
## Corehold PC interaction self-test — the view<->input twin of selftest.gd.
## Boots Main.tscn headless at 1920x1080 and drives the native desktop view
## with REAL mouse clicks, drags, wheel, keys and pad events, asserting ENGINE
## / SAVE state after every action: main menu + slots, the "while you were
## away" modal, the hub (Outpost home / tier select / modes), the Core tab
## (level), the Outpost (palette click + drag place, ghost preview, rotate,
## move, upgrade, demolish, collect, plots, pan / zoom, blueprints),
## Research, Missions, Reforge (two-step + tree),
## settings + remapping, records, and the run (draft cards, reroll, banish,
## drag-to-place, Core tracks, specials + aim, targeting, pause, retry,
## abandon -> results). Layout, tooltip, press-mode and focus checks on every
## screen. Prints "UITEST OK" (exit 0) or "UITEST FAIL: <n> checks failed".
## REDESIGN (deliberate rewrite): the permanent base grid, perm-building hotbar,
## info popover and mobile column are gone. V2 (deliberate): Core Bay, Crates,
## Cards and the Factory are gone (Core tab + the restored Outpost).
## Run: godot --headless --path games/towerdef-pc-0001/ --script res://uitest.gd

const Hub := preload("res://ui/Hub.gd")
const Kit := preload("res://ui/Kit.gd")
const Fonts := preload("res://ui/Fonts.gd")
const Intel := preload("res://ui/Intel.gd")
const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const Labs := preload("res://Labs.gd")
const Missions := preload("res://Missions.gd")
const Outpost := preload("res://Outpost.gd")
const Cores := preload("res://Cores.gd")
const Reforge := preload("res://Reforge.gd")
const Specials := preload("res://Specials.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const Settings := preload("res://Settings.gd")
const Keybinds := preload("res://Keybinds.gd")
const OutpostView := preload("res://ui/OutpostView.gd")
const CoreView := preload("res://ui/CoreView.gd")
const Hotbar := preload("res://ui/Hotbar.gd")
const BattleUI := preload("res://ui/Battle.gd")
const T0: int = 1800000000

var main: Node2D
var fail_count: int = 0


func _initialize() -> void:
	_run()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fail_count += 1
	print("UITEST %s: %s %s" % ["PASS" if ok else "FAIL", name, detail])


func _label(b: Control) -> String:
	if b.has_meta("key"):
		return String(b.get_meta("key"))
	return (b as Button).text if b is Button else ""


func _all_buttons() -> Array:
	var out: Array = []
	for c in main.ui.get_children():
		if c is Button and not (c as Button).is_queued_for_deletion():
			out.append(c)
	return out


func _find(key: String) -> Button:
	for c in _all_buttons():
		if _label(c as Button) == key:
			return c
	return null


func _findp(prefix: String) -> Button:
	for c in _all_buttons():
		if _label(c as Button).begins_with(prefix):
			return c
	return null


func _find_ctl(key: String) -> Control:
	for c in main.ui.get_children():
		if (c as Control).has_meta("key") and String((c as Control).get_meta("key")) == key and not c.is_queued_for_deletion():
			return c
	return null


func _press(key: String) -> bool:
	var b: Button = _find(key)
	if b == null:
		b = _findp(key)
	if b == null:
		print("UITEST note: no button '%s'" % key)
		return false
	_click(b.get_global_rect().get_center())
	return true


func _click(pos: Vector2) -> void:
	main.last_tap_ms = -1000
	_motion(pos)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev, true)


func _mouse(pos: Vector2, button: MouseButton, pressed: bool) -> void:
	main.last_tap_ms = -1000
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


## One wheel notch at pos (up = true / down = false).
func _wheel(pos: Vector2, up: bool) -> void:
	_mouse(pos, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, true)
	_mouse(pos, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, false)


func _motion(pos: Vector2, rel: Vector2 = Vector2.ZERO) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	root.push_input(ev, true)


## Press at `a`, move in steps, release at `b` (a real drag).
func _drag(a: Vector2, b: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_motion(a)
	_mouse(a, button, true)
	await _frames()
	var prev: Vector2 = a
	for k in range(1, 5):
		var p: Vector2 = a.lerp(b, float(k) / 4.0)
		_motion(p, p - prev)
		prev = p
		await _frames(1)
	_mouse(b, button, false)
	await _frames()


func _key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		root.push_input(ev, true)


func _pad_button(b: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		ev.pressed = pressed
		ev.device = 0
		root.push_input(ev, true)


func _pad_axis(axis: JoyAxis, v: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = v
	ev.device = 0
	root.push_input(ev, true)


func _cell_scr(i: int) -> Vector2:
	return main.w2s(TowerState.slot_pos(i))


func _op_scr(x: int, y: int) -> Vector2:
	return OutpostView.cell_rect(main, x, y).get_center()


func _no_overlap(rects: Array) -> bool:
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			if (rects[a] as Rect2).grow(-1.0).intersects((rects[b] as Rect2).grow(-1.0)):
				return false
	return true


func _frames(n: int = 2) -> void:
	for k in n:
		await process_frame


## PC-U2 on the current screen: every visible button has a tooltip, fires on
## press, is >= 40 px tall and sits inside the viewport.
func _audit(where: String) -> void:
	var bad: Array = []
	var vis := Rect2(Vector2.ZERO, main.get_viewport().get_visible_rect().size)
	for c in _all_buttons():
		var b: Button = c
		if not b.visible:
			continue
		if b.tooltip_text == "" or b.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
			bad.append(_label(b) + " tip/mode")
		if b.size.y < 40.0:
			bad.append(_label(b) + " h")
		if not vis.grow(1.0).encloses(b.get_global_rect()):
			bad.append(_label(b) + " out %s" % b.get_global_rect())
	_check("PC-U2 %s: buttons have tooltips, press mode, >= 40 px, inside the window" % where, bad.is_empty(), str(bad))
	# P2 layout audit: the last drawn frame asked for no text below Kit.MIN_TEXT
	# and no button label is smaller either.
	var small: Array = Kit.small_text.duplicate()
	for c in _all_buttons():
		var b2: Button = c
		if b2.visible and b2.text != "" and b2.get_theme_font_size("font_size") < Kit.MIN_TEXT:
			small.append(_label(b2) + " btn %d" % b2.get_theme_font_size("font_size"))
	_check("P2 %s: no text below %d px" % [where, Kit.MIN_TEXT], small.is_empty(), str(small))


func _run() -> void:
	MetaSave.clear()
	root.size = Vector2i(1920, 1080)
	var scene: PackedScene = load("res://Main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await _frames()
	main.settings["controls"]["tooltip_delay"] = 0.0
	# ---- MENU ------------------------------------------------------------------
	_check("PC: boots to the main menu", main.screen == "menu")
	_check("PC: slot picker shows 3 slots", _find("SLOT 1 PLAY") != null and _find("SLOT 2 PLAY") != null and _find("SLOT 3 PLAY") != null)
	_audit("menu")
	# ---- P2 neon theme ------------------------------------------------------------
	var f0: int = Kit.frames
	await _frames()
	_check("P2: the draw pass runs headless (the text-size audit is live)", Kit.frames > f0)
	_check("P2: body text is Inter, headings Chakra Petch (bundled OFL fonts)", main.font is FontVariation and (main.font as FontVariation).base_font.resource_path.ends_with("Inter.ttf") and Fonts.head().resource_path.ends_with("ChakraPetch-SemiBold.ttf") and Fonts.bold().resource_path.ends_with("ChakraPetch-Bold.ttf"))
	_check("P2: the neon Theme is set on the widget layer and tooltips", main.ui.theme != null and main.tipbox.theme == main.ui.theme and main.ui.theme.default_font == main.font)
	var b1: Button = _find("SLOT 1 PLAY")
	_check("P2: buttons use Chakra Petch labels and a glowing hover", b1.get_theme_font("font") == Fonts.head() and (b1.get_theme_stylebox("hover") as StyleBoxFlat).shadow_size > 0)
	_press("SLOT 1 PLAY")
	await _frames()
	_check("PC: slot 1 loads to the hub (Play tab)", main.screen == "base" and main.tab == "play" and MetaSave.active == 1)
	# ---- PC-U1 native layout ------------------------------------------------------
	_check("PC-U1: no embedded mobile column (one unscaled Control layer)", main.ui.scale == Vector2.ONE and not ("col_s" in main) and main.get_node_or_null("Sfx") != null)
	_check("PC-U1: overlays ignore the mouse", main.tipbox.mouse_filter == Control.MOUSE_FILTER_IGNORE and main.ui.mouse_filter == Control.MOUSE_FILTER_IGNORE and main.fader.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	main.save = BaseMeta.default_save()
	main.save["coins"] = 50000
	main.save["scrap"] = 2000
	main.now_override = T0
	main._rebuild_ui()
	await _frames()
	_audit("play")

	# ---- BOOT: AWAY MODAL ------------------------------------------------------
	# V2 (deliberate): the Factory is gone; the away pay is the Outpost's
	# stored production again (pre-Factory behaviour).
	var boot_save: Dictionary = main.save.duplicate(true)
	Outpost.place(boot_save, "mill", 4, 4, 0, T0 - 7200 - 120)
	Outpost.tick(boot_save, T0 - 7200)
	boot_save["last_seen"] = T0 - 7200
	var expect_off: int = int(Outpost.away_report(BaseMeta.normalize(boot_save), T0)["coins"])
	main.boot(boot_save, T0)
	await _frames()
	_check("away modal shown at boot (only Collect clickable)", not main.offline_offer.is_empty() and _find("Collect") != null and _find("DSTART") == null)
	var c_before: int = int(main.save["coins"])
	_press("Collect")
	await _frames()
	_check("Collect pays the Outpost's stored coins", expect_off > 0 and int(main.save["coins"]) == c_before + expect_off and main.offline_offer.is_empty(), "%d" % expect_off)
	_check("missions rolled at boot", Missions.list(main.save).size() == 3)

	# ---- TIER SELECT --------------------------------------------------------------
	main.save["best_wave_by_tier"] = {"1": 40}
	main._rebuild_ui()
	await _frames()
	_press(">")
	await _frames()
	_check("tier > selects tier 2", int(main.save["tier"]) == 2 and main.view_tier == 2)
	_press(">")
	await _frames()
	_check("locked tier 3 shown, START disabled", main.view_tier == 3 and int(main.save["tier"]) == 2 and _find("DSTART").disabled)
	_press("<")
	await _frames()
	_press("<")
	await _frames()
	_check("tier < back to tier 1", int(main.save["tier"]) == 1)

	await _core_tab()
	await _outpost()
	await _research_missions()
	await _home()
	await _reforge()
	await _settings_records()
	await _run_screen()
	await _pad_and_slots()

	MetaSave.clear()
	if fail_count == 0:
		print("UITEST OK")
		quit(0)
	else:
		print("UITEST FAIL: %d checks failed" % fail_count)
		quit(1)


# ================================================================== CORE (V2)
## V2 (deliberate): the Core Bay (4 Cores, parts, presets) is gone; the Core
## tab shows the one Core's level + sheet (P4: Weapon / Modules / Look).
func _core_tab() -> void:
	_key(KEY_K)
	await _frames()
	_check("CORE: K opens the Core tab", main.tab == "core" and _find("CORE LEVEL") != null)
	_audit("core")
	var c0: int = int(main.save["coins"])
	var lv0: int = Cores.level(main.save)
	var lc: int = int(Cores.level_cost(lv0)["coins"])
	_press("CORE LEVEL")
	await _frames()
	_check("CORE: Level up spends coins and raises the Core level", Cores.level(main.save) == lv0 + 1 and int(main.save["coins"]) == c0 - lc)
	_check("CORE: the Level button tooltip shows the cost and per-level gains", _find("CORE LEVEL").tooltip_text.contains("coins") and _find("CORE LEVEL").tooltip_text.contains("dmg"))
	main.save["coins"] = 0
	main._rebuild_ui()
	await _frames()
	_check("CORE: Level up is disabled when broke", _find("CORE LEVEL").disabled)
	main.save["coins"] = 50000


# ================================================================= OUTPOST
## V2 (deliberate): the Factory is gone; this is the pre-Factory plot / building
## Outpost again (restored from 5b10ce8; no Command Plaza, no Key Forge).
func _outpost() -> void:
	var s: Dictionary = main.save
	s["coins"] = 200000
	_key(KEY_O)
	await _frames()
	_check("OP: O opens the Outpost", main.tab == "outpost")
	_audit("outpost")
	var o: Dictionary = s["outpost"]
	var mills0: int = Outpost.count_of(o, "mill")
	var c0: int = int(s["coins"])
	# palette click arms, map click places (a 2x2 Mill next to the Relay)
	_press("OPBUILD mill")
	await _frames()
	_check("OP: palette click arms the building", main.op_arm == "mill")
	_motion(_op_scr(4, 6))
	await _frames(2)
	var gh: Dictionary = main.get_meta("op_ghost", {})
	_check("OP: hover preview validates the footprint and the Relay link", gh.has("err") and String(gh["err"]) == "" and bool(gh.get("linked", false)), str(gh))
	_motion(_op_scr(0, 2))
	await _frames(2)
	gh = main.get_meta("op_ghost", {})
	_check("OP: hover over the Research Hall shows the refusal", String(gh.get("err", "")) == "occupied", str(gh))
	_click(_op_scr(4, 6))
	await _frames()
	var o2: Dictionary = main.save["outpost"]
	# FEEDBACK-1 (deliberate): builds are instant — no builder is held.
	_check("OP: click on the map places it (coins spent, built at once)", Outpost.count_of(o2, "mill") == mills0 + 1 and int(main.save["coins"]) == c0 - Outpost.cost("mill", 1) and Outpost.busy(main.save) == 0)
	var new_uid: String = main.op_sel
	_check("OP: the new building is selected", new_uid != "" and (o2["buildings"] as Dictionary).has(new_uid))
	# FEEDBACK-1: no build timers, so no gem Skip button either.
	_check("OP: the build is finished at once (no Skip)", bool((o2["buildings"][new_uid] as Dictionary)["built"]) and _find("OP SKIP 0") == null and not main.save.has("gems"))
	# drag a Conduit from the palette onto the map
	_press("OPCAT infra")
	await _frames()
	var b: Button = _find("OPBUILD conduit")
	if b != null:
		await _drag(b.get_global_rect().get_center(), _op_scr(1, 4))
	_check("OP: dragging a Conduit from the palette places it", Outpost.occupancy(main.save["outpost"]).has(Vector2i(1, 4)))
	_key(KEY_ESCAPE)
	await _frames()
	_check("OP: Esc disarms", main.op_arm == "")
	# select + upgrade (U) + move (M) + rotate (R) + demolish (Del)
	_click(_op_scr(4, 6))
	await _frames()
	_check("OP: clicking a building selects it", main.op_sel == new_uid)
	_key(KEY_U)
	await _frames()
	_check("OP: U upgrades instantly", not Outpost.has_job(main.save, new_uid) and int((o2["buildings"][new_uid] as Dictionary)["lvl"]) == 2)
	_check("OP: the upgrade is complete (no Skip needed)", int((o2["buildings"][new_uid] as Dictionary)["lvl"]) == 2 and _find("OP SKIP 0") == null)
	_key(KEY_M)
	await _frames()
	_check("OP: M picks the building up", main.op_moving)
	_click(_op_scr(0, 6))
	await _frames()
	_check("OP: click drops it at the new spot", int((o2["buildings"][new_uid] as Dictionary)["x"]) == 0 and int((o2["buildings"][new_uid] as Dictionary)["y"]) == 6 and not main.op_moving)
	_press("OPCAT support")
	await _frames()
	_press("OPBUILD scrapyard")
	await _frames()
	var r0: int = main.op_rot
	_key(KEY_R)
	await _frames()
	_check("OP: R rotates the armed footprint", main.op_rot == (r0 + 1) % 2)
	_key(KEY_ESCAPE)
	await _frames()
	main.op_sel = new_uid
	_key(KEY_DELETE)
	await _frames()
	_check("OP: Delete demolishes the selection", not (o2["buildings"] as Dictionary).has(new_uid))
	# collect: click a full generator; Collect all at Relay 3
	var mill_uid: String = ""
	Outpost.place(main.save, "mill", 4, 4, 0, T0 - 4000)
	Outpost.tick(main.save, T0)
	for u in o2["buildings"].keys():
		if String((o2["buildings"][u] as Dictionary)["id"]) == "mill" and bool((o2["buildings"][u] as Dictionary)["built"]):
			mill_uid = String(u)
	if mill_uid != "":
		(o2["buildings"][mill_uid] as Dictionary)["stored"] = 120.0
	main._rebuild_ui()
	await _frames()
	var cb: int = int(main.save["coins"])
	var mb: Dictionary = o2["buildings"].get(mill_uid, {})
	_click(_op_scr(int(mb.get("x", 4)), int(mb.get("y", 4))))
	await _frames()
	_check("OP: clicking a stocked generator collects it", int(main.save["coins"]) >= cb + 120)
	_check("OP: Collect all is locked below Relay Lv3", _find("OP COLLECT ALL").disabled)
	o2["relay_lvl"] = 3
	if mill_uid != "":
		(o2["buildings"][mill_uid] as Dictionary)["stored"] = 50.0
	main._rebuild_ui()
	await _frames()
	var cc: int = int(main.save["coins"])
	_press("OP COLLECT ALL")
	await _frames()
	_check("OP: Collect all collects every building", int(main.save["coins"]) >= cc + 50)
	# plots
	var pk: int = -1
	for k in OutpostDB.PLOTS.size():
		if pk < 0 and Outpost.plot_adjacent(o2, k) and not (o2["plots"] as Array).has(k):
			pk = k
	var pr: Rect2i = OutpostDB.PLOTS[pk]
	_click(_op_scr(pr.position.x, pr.position.y))
	await _frames()
	_check("OP: clicking locked land selects the plot", main.op_sel == "plot:%d" % pk)
	_press("OP PLOT COINS")
	await _frames()
	_check("OP: buying a plot opens the land", (o2["plots"] as Array).has(pk))
	# pan + zoom
	var cam0: Vector2 = main.op_cam
	await _drag(_op_scr(6, 1), _op_scr(6, 1) + Vector2(120, 60), MOUSE_BUTTON_RIGHT)
	_check("OP: right-drag pans the map", main.op_cam.distance_to(cam0) > 50.0, str(main.op_cam))
	var z0: float = main.op_zoom
	_mouse(_op_scr(5, 5), MOUSE_BUTTON_WHEEL_UP, true)
	await _frames()
	_check("OP: wheel zooms the map", main.op_zoom > z0)
	main.op_cam = Vector2.ZERO
	main.op_zoom = 1.0
	# blueprints
	var nb: int = (o2["blueprints"] as Array).size()
	_press("BP SAVE")
	await _frames()
	_check("OP: blueprint Save stores the layout", (o2["blueprints"] as Array).size() == nb + 1)
	_press("BP EXPORT")
	await _frames()
	_check("OP: Export produces a layout code", main.op_bp_text != "" and Outpost.import_layout(main.op_bp_text).size() > 0)
	_press("BP LOAD 0")
	await _frames()
	_check("OP: Load rebuilds the saved blueprint", main.toast_queue.any(func(t: Variant) -> bool: return String(t).begins_with("Blueprint rebuilt")) or main.toast_text.begins_with("Blueprint rebuilt"))
	main.op_sel = ""
	main._rebuild_ui()


# ======================================================= RESEARCH / MISSIONS
func _research_missions() -> void:
	var s: Dictionary = main.save
	_key(KEY_L)
	await _frames()
	_check("RES: L opens Research", main.tab == "research" and _find("LAB dmg") != null)
	_audit("research")
	var lc: int = int(s["coins"])
	_press("LAB dmg")
	await _frames()
	# FEEDBACK-1 (deliberate): research is instant — no queue, no Rush.
	_check("RES: click a project researches it instantly", Labs.level(main.save, "dmg") == 1 and not Labs.is_running(main.save, "dmg") and int(main.save["coins"]) == lc - Labs.cost("dmg", 0))
	_check("RES: no Rush button (no timers, no gems)", _find("Rush") == null)
	_check("V2: no Cards / Crates / Core Bay / Factory tech left", _findp("CARD ") == null and _find("Open Chest") == null and _findp("FTECH") == null)
	_key(KEY_M)
	await _frames()
	_check("MIS: M opens Missions", main.tab == "missions")
	_audit("missions")
	var c2: int = int(main.save["coins"])
	_press("Claim Day")
	await _frames()
	_check("MIS: streak claim", int(main.save["streak"]["day_idx"]) == 1 and int(main.save["coins"]) > c2)
	var lst: Array = Missions.list(main.save)
	for k in lst.size():
		lst[k]["prog"] = int(lst[k]["target"])
	main._rebuild_ui()
	await _frames()
	for k in lst.size():
		_press("MCLAIM %d" % k)
		await _frames()
	_check("MIS: mission claims", Missions.all_claimed(main.save))
	var g3: int = int(main.save["coins"])
	_press("BONUS")
	await _frames()
	_check("MIS: all-clear bonus (coins)", bool(main.save["missions"]["bonus_claimed"]) and int(main.save["coins"]) > g3)


# ================================================================ HOME (V2)
## V2 home: the Outpost is the hub; the top menu holds Core / Research /
## Missions / Reforge (no plaza buildings, no Crate Depot / Card Hall).
func _home() -> void:
	main.set_tab("play")
	await _frames()
	_check("V2 home: Outpost map + top menu Core / Research / Missions / Reforge", _findp("OPBUILD ") != null and _find("DSTART") != null and _find("DTAB Core") != null and _find("DTAB Research") != null and _find("DTAB Missions") != null and _find("DTAB Reforge") != null and _find("DTAB Core Bay") == null and _find("DTAB Crates") == null and _find("DTAB Cards") == null)
	var fg: Button = _find("DTAB Forge")
	_check("P2 nav: OUTPOST / CORE / FORGE / RESEARCH / REFORGE, Forge shown locked until the gear engine", fg != null and fg.disabled and fg.tooltip_text.contains("Forge") and _find("DTAB Outpost").text == "OUTPOST")
	var mb: Button = _find("DTAB Missions")
	_check("P2 nav: Missions is a top-bar button", mb != null and mb.position.y < float(main.TOP_H) and mb.position.x > Hub.start_rect(main).position.x - 700.0)
	for nv in [["DTAB Core", "core"], ["DTAB Research", "research"], ["DTAB Missions", "missions"], ["DTAB Reforge", "reforge"]]:
		_press(String(nv[0]))
		await _frames()
		_check("V2 top menu %s opens its screen" % String(nv[0]), main.tab == String(nv[1]), main.tab)
	var r4: Rect2 = Hub.nav_rect(main, Hub.NAV.size())
	_check("V2 top menu clears the deploy cluster", r4.end.x <= Hub.start_rect(main).position.x - 330.0, str(r4))
	_press("DTAB Outpost")
	await _frames()
	_check("V2 Back to Outpost returns home", main.tab == "play")
	_audit("home")
	var cat: Button = _find("OPCAT prod")
	_check("FB1: build categories carry icons", cat != null and cat.icon != null)
	_check("V2: no plaza landmarks on the Outpost map", OutpostView.LANDMARKS.is_empty() and OutpostView.landmark_at(Vector2i(-2, 1)) == "")
	var tx: Texture2D = load("res://art/aegis.svg") as Texture2D
	_check("FB1: SVG art rasterises at >= 256 px (not upscaled blur)", tx != null and tx.get_width() >= 256, str(tx.get_width() if tx != null else 0))


# ================================================================= REFORGE
func _reforge() -> void:
	var s: Dictionary = main.save
	_key(KEY_Y)
	await _frames()
	_check("RF: Y opens Reforge", main.tab == "reforge")
	_audit("reforge")
	_check("RF: Reforge is locked below the gate", _find("REFORGE").disabled == not Reforge.can_reforge(s))
	s["best_wave_by_tier"] = {"1": 45}
	s["reforge"]["coins_since"] = 250000
	main._rebuild_ui()
	await _frames()
	var want: int = Reforge.shards_now(s)
	_press("REFORGE")
	await _frames()
	_check("RF: first click asks to confirm (nothing reset)", main.rf_confirm == 1 and int(main.save["coins"]) > 0 and _find("REFORGE CONFIRM") != null)
	_press("REFORGE CANCEL")
	await _frames()
	_check("RF: Keep playing cancels", main.rf_confirm == 0)
	_press("REFORGE")
	await _frames()
	_press("REFORGE CONFIRM")
	await _frames()
	_check("RF: confirmed Reforge banks shards and resets coins", Reforge.count(main.save) == 1 and int(main.save["shards"]) == want and int(main.save["coins"]) == 0, "%d" % want)
	_check("RF: Reforge keeps Scrap", int(main.save["scrap"]) > 0)
	_press("RF might")
	await _frames()
	_check("RF: a branch node needs the root first", Reforge.node(main.save, "might") == 0)
	_press("RF root_forge")
	await _frames()
	_press("RF might")
	await _frames()
	_check("RF: tree nodes buy with shards", Reforge.node(main.save, "root_forge") == 1 and Reforge.node(main.save, "might") == 1)
	main.save["coins"] = 50000


# ======================================================= SETTINGS / RECORDS
func _settings_records() -> void:
	var settings_before: Dictionary = Settings.read()
	_press("HUD Settings")
	await _frames()
	_check("PC-S1: settings opens on 4 tabs", main.overlay == "settings" and _find("SET TAB Video") != null and _find("SET TAB Controls") != null)
	_audit("settings")
	var vs0: String = String(Settings.normalize(main.settings)["video"]["vsync"])
	_press("SET VSync")
	await _frames()
	var vs1: String = String(Settings.normalize(main.settings)["video"]["vsync"])
	_check("PC-S1: VSync cycles and persists to settings.cfg", vs1 != vs0 and String(Settings.read()["video"]["vsync"]) == vs1)
	_check("HORDE P5: gore defaults to low", String(Settings.normalize(main.settings)["video"]["gore"]) == "low")
	_press("SET Gore")
	await _frames()
	var gr1: String = String(Settings.normalize(main.settings)["video"]["gore"])
	_check("HORDE P5: gore setting cycles and persists to settings.cfg", gr1 != "low" and String(Settings.read()["video"]["gore"]) == gr1, gr1)
	_check("HORDE P5: gore view follows the setting", main.gore != null and String(main.gore.get("level")) == gr1, String(main.gore.get("level")))
	_press("SET Gore")
	await _frames()
	_check("HORDE P5: gore off persists", String(Settings.read()["video"]["gore"]) == "off" and String(main.gore.get("level")) == "off")
	_press("SET TAB Controls")
	await _frames()
	_press("REMAP pause")
	await _frames()
	_check("PC-S2: remap button enters capture", main.remap_action == "pause")
	_key(KEY_P)
	await _frames()
	_check("PC-S2: captured key rebinds the action", main.remap_action == "" and Keybinds.hint("pause") == "P", Keybinds.hint("pause"))
	_press("REMAP pause")
	await _frames()
	_key(KEY_U)
	await _frames()
	_check("PC-S2: conflicting key swaps bindings", Keybinds.hint("pause") == "U" and Keybinds.hint("upgrade") == "P")
	_press("KEYS RESET ALL")
	await _frames()
	_check("PC-S2: reset all restores defaults", Keybinds.hint("pause") == "Space" and Keybinds.hint("upgrade") == "U")
	_press("SET CLOSE")
	await _frames()
	Settings.write(settings_before)
	Settings.apply(settings_before)
	main.settings = Settings.normalize(settings_before)
	main.settings["controls"]["tooltip_delay"] = 0.0
	var ov0: bool = main.dbg_overlay
	_key(KEY_F3)
	await _frames()
	var ds: Dictionary = main.debug_stats()
	_check("HORDE P6: F3 toggles the debug overlay", main.dbg_overlay != ov0 and ds.has("bodies") and ds.has("fps") and ds.has("sim_ms") and ds.has("hash_ms") and ds.has("hash_cells") and ds.has("render_ms"))
	_key(KEY_F3)
	await _frames()
	_check("HORDE P6: F3 toggles the overlay back", main.dbg_overlay == ov0)
	_key(KEY_H)
	await _frames()
	_check("PC-U7: H opens stats", main.overlay == "stats")
	_audit("records")
	_press("REC Achievements")
	await _frames()
	_check("PC-U7: achievements tab", main.overlay == "achievements")
	_key(KEY_ESCAPE)
	await _frames()
	_check("PC-U3: Esc closes the overlay", main.overlay == "")
	_press("DTAB Outpost")   # FB1 (deliberate): the Play tab became the Outpost home button
	await _frames()
	_press("MODES")
	await _frames()
	_check("PC: mode select lists modifiers", main.overlay == "modes" and _find("MOD Swarm") != null)
	_press("MOD Swarm")
	await _frames()
	_check("PC: toggling a modifier updates run options", (main.run_opts["modifiers"] as Array).has("swarm"))
	_press("MOD Swarm")
	await _frames()
	_press("MODES CLOSE")
	await _frames()


# =================================================================== RUN
func _run_screen() -> void:
	main.save["research"]["lvls"]["speed"] = 1
	main._rebuild_ui()
	await _frames()
	main.sfx.clear_log()
	_press("DSTART")
	await _frames()
	_check("RUN: START RUN starts a run on an empty grid", main.screen == "run" and main.S != null and main.S.building_count() == 0)
	_check("sfx: wave_start on run start", main.sfx.played("wave_start"))
	var S = main.S
	S.spawn_hold = true
	_audit("run")
	# PC-U1 run layout
	var top := Rect2(0, 0, main.vw, main.TOP_H)
	# FEEDBACK-1 (deliberate): the bottom bar is gone — abilities float inside
	# the field — so the hotbar rect left the no-overlap set and must now sit
	# INSIDE the field, with the side panels reaching the window bottom.
	_check("PC-U1: top bar, left, field, right do not overlap at 1920x1080", main.vw >= 1919.0 and _no_overlap([top, main.left_rect(), main.field_rect(), main.right_rect()]))
	_check("FB1: no bottom bar (panels reach the bottom; abilities float inside the field)", main.field_rect().end.y >= main.vh - 0.5 and main.left_rect().end.y >= main.vh - 0.5 and main.field_rect().encloses(main.hot_rect()))
	_check("PC-U1: the whole 7x7 grid is inside the field", main.field_rect().has_point(_cell_scr(0)) and main.field_rect().has_point(_cell_scr(TowerState.N - 1)))
	await _frames(2)
	var cash_tips: int = 0
	var hp_tips: int = 0
	for st in main.stat_tips:
		if String((st as Array)[1]).begins_with("Run cash"):
			cash_tips += 1
		if String((st as Array)[1]).begins_with("Core HP"):
			hp_tips += 1
	_check("PC-G6: cash and Core HP are shown once (right panel only)", cash_tips == 1 and hp_tips == 1, "%d/%d" % [cash_tips, hp_tips])
	var kill_tip: bool = false
	for st in main.stat_tips:
		if String((st as Array)[1]).begins_with("Enemies killed") and ((st as Array)[0] as Rect2).position.x >= main.right_rect().position.x:
			kill_tip = true
	_check("FB1: enemies killed is shown in the right Core panel", kill_tip)
	_check("FB1: the left bar is the Perks menu (no Build/Info)", load("res://ui/DraftPanel.gd").perk_rows(main).is_empty())
	for res in [Vector2i(1280, 720), Vector2i(1280, 800)]:
		root.size = res
		await _frames(3)
		_audit("run %dx%d" % [res.x, res.y])
	root.size = Vector2i(1920, 1080)
	await _frames(3)
	# speed
	_press("SPD")
	await _frames()
	_check("RUN: speed button cycles game speed", absf(S.speed - 1.5) < 0.01 and absf(float(main.save["speed"]) - 1.5) < 0.01)
	_key(KEY_F)
	await _frames()
	_check("RUN: F steps the speed down", absf(S.speed - 1.0) < 0.01)
	# tracks
	S.cash = 400.0
	main._rebuild_ui()
	await _frames()
	var cost: int = S.track_cost("dmg")
	_press("TRACK Damage")
	await _frames()
	_check("RUN: clicking a Core Enhancement buys a level", int(S.tracks["dmg"]) == 1 and S.cash < 400.0 - float(cost) + 5.0)
	_key(KEY_2, false, true)
	await _frames()
	_check("RUN: Shift+2 buys the Rate track", int(S.tracks["rate"]) == 1)
	_motion(_find("TRACK Eco").get_global_rect().get_center())
	await _frames(3)
	# FB2 (deliberate): "Core tracks" renamed "Core Enhancements" everywhere.
	_check("RUN: hovering a track shows its tooltip", main.tipbox.visible and main.tip_label.text.begins_with("Eco enhancement"), main.tip_label.text)
	_check("FB1: tooltips render a bold header + icon stat lines, no hotkey callouts", main.tip_rich.text.begins_with("[b]") and main.tip_rich.text.contains("[img") and not main.tip_label.text.contains("Shift"), main.tip_rich.text)
	# FB2 right panel: Loot Drops feed aggregates kill loot; Core-hit flash is capped
	main._handle([{"t": "drop", "kind": "scrap", "n": 3, "source": "kill", "pos": Vector2.ZERO}, {"t": "drop", "kind": "scrap", "n": 2, "source": "kill", "pos": Vector2.ZERO}, {"t": "boss_bounty", "coins": 7, "pos": Vector2.ZERO}])
	var lf0: Dictionary = main.loot_feed[0] if not main.loot_feed.is_empty() else {}
	var scrap_n: float = 0.0
	for f in main.loot_feed:
		if String((f as Dictionary)["k"]) == "scrap":
			scrap_n = float((f as Dictionary)["n"])
	# V2 (deliberate): Keys are gone; the newest row is a boss bounty instead.
	_check("FB2: Loot Drops feed aggregates drops (scrap 3+2 = 5, newest first)", is_equal_approx(scrap_n, 5.0) and String(lf0.get("k", "")) == "bounty", str(main.loot_feed))
	var hz: Array = []
	for q in 60:
		hz.append({"t": "core_hits", "n": 40, "dmg": 1.0, "shots": 0, "pos_sample": [Vector2.ZERO]})
	main.flash = 0.0
	main.flash_cd = 0.0
	main._handle(hz)
	_check("FB2: horde Core hits pulse the flash once, capped", main.flash > 0.0 and main.flash <= main.FLASH_CAP + 0.001, str(main.flash))
	await _frames(4)
	var ro: Dictionary = Intel.roster(S)
	_check("FB2: Enemy intel lists this round's types (alive or queued) with 1-5 stars", not ro.is_empty() and Intel.stars(S, String(ro.keys()[0])) >= 1 and Intel.stars(S, "boss") <= 5 and main.intel_seen.size() >= ro.size(), str(ro.keys()))
	_motion(_cell_scr(TowerState.CORE_SLOT))
	await _frames(3)
	# V2 (deliberate): one Core, no traits — the tooltip names the Core and the
	# equipped Weapon (P4: the starter is the Standard Issue Autocannon).
	_check("RUN: hovering the Core shows its level + equipped Weapon", main.tipbox.visible and main.tip_label.text.contains("Core") and main.tip_label.text.contains("Standard Issue Autocannon"), main.tip_label.text)
	# draft: cards, reroll, banish, Q pick, place
	S.grant_draft()
	S.draft[0] = load("res://Draft.gd").card_for("gun", S._draft_ctx(""))
	main._rebuild_ui()
	await _frames(2)
	_check("RUN: the draft panel shows the cards", S.draft.size() >= 3 and _findp("DCARD 0") != null and _findp("DCARD 2") != null)
	var DP = load("res://ui/DraftPanel.gd")
	var Dr = load("res://Draft.gd")
	_check("FB1: draft cards name their type (BUILDING vs PERK vs ABILITY)", String(DP.card_type(main, Dr.card_for("gun", S._draft_ctx("")))["type"]) == "BUILDING" and String(DP.card_type(main, Dr.card_for("pk_arsenal", S._draft_ctx("")))["type"]) == "PERK" and String(DP.card_type(main, Dr.card_for("sp_emp", S._draft_ctx("")))["type"]) == "ABILITY")
	_check("FB1: a non-weapon duplicate says drag onto your <Building>", String(DP.card_type(main, {"id": "mine", "fam": "building", "kind": "plus", "reward": "upgrade", "lvl": 1, "to": 2})["sub"]).begins_with("Drag onto your Gold Mine"))
	_check("FB1: no hotkey callouts on the draft buttons", _find("Reroll") != null and not _find("Reroll").text.contains("[") and not _find("Banish").text.contains("["))
	_audit("draft")
	var hand0: String = JSON.stringify(S.draft)
	_press("Reroll")
	await _frames()
	_check("RUN: free reroll re-rolls the hand", not S.free_reroll and S.draft.size() >= 3)
	_check("RUN: reroll now shows its cash cost", _find("Reroll") != null and _find("Reroll").text.contains("$"))
	# Force a known banishable card into slot 2: the rerolled hand is random, and
	# could put an insight card there (unbanishable) or "gun"/"mortar" (banishing
	# those empties the later forced card_for("gun"/"mortar") cards below).
	S.draft[2] = load("res://Draft.gd").card_for("mine", S._draft_ctx(""))
	main._rebuild_ui()
	await _frames()
	var bid: String = String((S.draft[2] as Dictionary)["id"])
	_press("Banish")
	await _frames()
	_check("RUN: Banish arms banish mode", main.banish_mode)
	_press("DCARD 2")
	await _frames()
	_check("RUN: clicking a card in banish mode banishes it", S.banished.has(bid) and S.banish_left == 0 and not main.banish_mode)
	S.draft[0] = load("res://Draft.gd").card_for("gun", S._draft_ctx(""))
	main._rebuild_ui()
	await _frames()
	_key(KEY_Q)
	await _frames()
	_check("RUN: Q takes draft card 1 (place mode)", S.draft.is_empty() and S.pending_place == "gun", "draft %s pending '%s' perk %d mut %d over %s" % [str(S.draft.map(func(c: Dictionary) -> String: return String(c["id"]))), S.pending_place, S.perk_offer.size(), S.mutation_offer.size(), str(S.over)])
	var cell: int = TowerState.CORE_RING[0]
	_motion(_cell_scr(cell))
	await _frames(2)
	_check("FB1: placing shows the building as the cursor on a valid (green) cell", String(main.get_meta("ghost_id", "")) == "gun" and String(main.get_meta("ghost_reason", "x")) == "")
	_check("FB1: the placement preview has a range radius", float(BattleUI.preview_range(main, "gun")["r"]) > TowerState.CELL)
	# V2 P3c: the ghost shows the turret's facing (away from the Core); Z turns it
	var gr0: int = int(main.get_meta("ghost_rot", -1))
	_key(KEY_Z)
	await _frames(2)
	_check("P3c: Z turns the weapon being placed (+45 deg from the facing its ghost shows)", gr0 >= 0 and int(main.get_meta("ghost_rot", -1)) == posmod(gr0 + 1, 8) and S.pending_rot == posmod(gr0 + 1, 8), "%d -> %d" % [gr0, int(main.get_meta("ghost_rot", -1))])
	_wheel(_cell_scr(cell), false)
	await _frames(2)
	_check("P3c: the mouse wheel turns it while placing (not the zoom)", S.pending_rot == posmod(gr0 + 2, 8))
	_wheel(_cell_scr(cell), true)
	await _frames(2)
	_motion(_cell_scr(TowerState.CORE_SLOT))
	await _frames(2)
	_check("FB1: an invalid cell turns the preview red with a reason", String(main.get_meta("ghost_reason", "")) != "")
	_click(_cell_scr(cell))
	await _frames()
	_check("RUN: click a glowing cell places it", S.id_at(cell) == "gun" and S.pending_place == "")
	_check("P3c: the placed turret keeps the chosen facing", S.rot_at(cell) == posmod(gr0 + 1, 8))
	main.sel = cell
	_key(KEY_Z)
	await _frames()
	_check("P3c: Z turns the selected turret (free)", S.rot_at(cell) == posmod(gr0 + 2, 8))
	_check("sfx: place clip", main.sfx.played("place"))
	# drag a NEW building card onto a cell
	S.grant_draft()
	S.draft[1] = load("res://Draft.gd").card_for("mortar", S._draft_ctx(""))
	main._rebuild_ui()
	await _frames()
	var cb: Button = _findp("DCARD 1")
	var cell2: int = TowerState.CORE_RING[4]   # V2 P3b: clear of the gun on CORE_RING[0]
	# V2 P3b: a 2x2 footprint centres on the grid corner nearest the cursor;
	# drop on cell2's top-left corner so the Mortar covers cell2.
	var corner: Vector2 = TowerState.slot_pos(cell2) - Vector2(TowerState.CELL, TowerState.CELL) * 0.5
	if cb != null:
		await _drag(cb.get_global_rect().get_center(), main.w2s(corner))
	var a2: int = TowerState.anchor_at(corner, 2)
	_check("RUN: dragging a draft card onto a cell places it (2x2 footprint under the cursor)", S.id_at(a2) == "mortar" and S.owner_at(cell2) == a2 and S.draft.is_empty(), "a2 %d cell2 %d owner %d id '%s' draft %d pending '%s' reason '%s'" % [a2, cell2, S.owner_at(cell2), S.id_at(a2), S.draft.size(), S.pending_place, BattleUI.place_reason(main, a2, "mortar")])
	# target mode on a selected weapon
	_click(_cell_scr(cell))
	await _frames()
	var tm0: String = String(S.target_modes[cell])
	await _frames(2)
	_check("FB1: clicking a building shows its range circle", int(main.get_meta("range_shown", -1)) == cell and float(BattleUI.range_of(main, cell).get("r", 0.0)) > 0.0)
	_check("FB1: non-weapon buildings show an aura range", String(BattleUI.preview_range(main, "mine")["kind"]) == "aura")
	_press("Target:")
	await _frames()
	_check("RUN: Target button cycles the weapon's mode", String(S.target_modes[cell]) != tm0)
	# specials: key cast, cooldown, targeted aim
	Specials.take(S.specials, "sp_repair")
	Specials.take(S.specials, "sp_orbital")
	S._spawn("hauler", [])
	# a durable target: with the sim live the Core would otherwise kill it
	# before the aimed cast below (FEEDBACK-1: enemies walk into Core range).
	S.set_enemy(int((S.enemy_list().back() as Dictionary)["eid"]), {"hp": 1.0e9, "max_hp": 1.0e9})
	main._rebuild_ui()
	await _frames()
	_check("RUN: the hotbar shows the specials", _find("SPECIAL 1") != null and not _find("SPECIAL 1").disabled and _find("SPECIAL 3").disabled)
	_check("FB1: abilities float over the bottom of the field", main.field_rect().encloses(_find("SPECIAL 1").get_global_rect()))
	S.perks_taken.append("p_dmg")
	_check("FB1: taken gold perks are listed under Perks", (DP.perk_rows(main) as Array).any(func(r: Dictionary) -> bool: return String(r["sec"]) == "GOLD PERKS"))
	S.perks_taken.erase("p_dmg")
	var casts0: int = S.special_casts
	_key(KEY_1)
	await _frames()
	_check("RUN: key 1 casts special 1 (cooldown starts)", S.special_casts == casts0 + 1 and float((S.specials[0] as Dictionary)["cd"]) > 0.0)
	_press("SPECIAL 1")
	await _frames()
	_check("RUN: casting on cooldown is refused", S.special_casts == casts0 + 1)
	_key(KEY_2)
	await _frames()
	_check("RUN: a targeted special arms the aim cursor", main.aim_special == 1 and S.special_casts == casts0 + 1)
	_mouse(main.w2s(TowerState.CENTER + Vector2(120, 0)), MOUSE_BUTTON_RIGHT, true)
	_mouse(main.w2s(TowerState.CENTER + Vector2(120, 0)), MOUSE_BUTTON_RIGHT, false)
	await _frames()
	_check("RUN: right-click cancels the aim", main.aim_special == -1)
	_key(KEY_2)
	await _frames()
	_click(main.w2s(TowerState.CENTER + Vector2(160, -40)))
	await _frames()
	_check("RUN: clicking the field drops the Orbital Strike there", S.special_casts == casts0 + 2 and S.orbitals.size() == 1 and (S.orbitals[0]["pos"] as Vector2).distance_to(TowerState.CENTER + Vector2(160, -40)) < 2.0, "casts %d/%d orb %s aim %d" % [S.special_casts, casts0, str(S.orbitals), main.aim_special])
	# wheel zoom
	for k in 8:
		_mouse(main.w2s(TowerState.CENTER), MOUSE_BUTTON_WHEEL_UP, true)
	await _frames()
	_check("RUN: zoom clamps at 1.4", absf(main.zoom - 1.4) < 0.001)
	main.zoom = 1.0
	# pause / resume / lane / retry
	_key(KEY_SPACE)
	await _frames()
	var ta: float = S.time_alive
	await _frames(6)
	_check("RUN: Space pauses (engine time frozen)", main.overlay == "pause" and S.time_alive == ta)
	_audit("pause")
	_key(KEY_SPACE)
	await _frames(4)
	# HORDE P3 (deliberate): fixed 0.05 s substeps accumulate across frames,
	# so a few short frames may not reach one step yet; wait (bounded) for it.
	for _w in 120:
		if S.time_alive > ta:
			break
		await _frames(1)
	_check("RUN: Space resumes", main.overlay == "" and S.time_alive > ta)
	# FEEDBACK-1 (deliberate): no lanes, no seed replay.
	_key(KEY_V)
	await _frames()
	_check("RUN: no lane focus (V does nothing)", not ("focus_quad" in S) and main.S == S)
	_key(KEY_R, true)
	await _frames()
	_check("RUN: Ctrl+R never replays a seed mid-run", main.S == S)
	var S2 = main.S
	S2.coins_run = 33.0
	var runs_b: int = int(main.save["runs"])
	_press("HUD Pause")
	await _frames()
	_press("Abandon")
	await _frames(3)
	_check("RUN: Abandon ends the run -> results (banked)", S2.over and main.screen == "results" and int(main.save["runs"]) == runs_b + 1)
	_check("RUN: results offer Back to base + Play again (no seed retry)", _find("DBACK") != null and _find("PLAY AGAIN") != null and _find("RETRY SEED") == null)
	_audit("results")
	_check("sfx: game_over clip", main.sfx.played("game_over"))
	_press("DBACK")
	await _frames()
	_check("RUN: Back to base returns to the hub", main.screen == "base" and main.tab == "play")


# ======================================================= PAD + SLOT DELETE
func _pad_and_slots() -> void:
	_pad_button(JOY_BUTTON_A)
	await _frames()
	_check("PC-U5: pad input switches glyphs", main.last_device == "pad")
	main.screen = "base"
	for tb in ["play", "core", "outpost", "research", "reforge"]:
		main.set_tab(tb)
		await _frames()
		var dead: Array = []
		for c in _all_buttons():
			if not (c as Button).disabled and ((c as Button).focus_mode != Control.FOCUS_ALL or (c as Button).find_next_valid_focus() == null):
				dead.append(_label(c as Button))
		_check("PC-U5: %s focus chain has no dead ends (pad)" % tb, dead.is_empty(), str(dead))
	main.set_tab("play")
	main.start_run()
	await _frames()
	main.S.spawn_hold = true
	main.sel = TowerState.CORE_SLOT
	_pad_axis(JOY_AXIS_LEFT_X, 1.0)
	await _frames()
	_pad_axis(JOY_AXIS_LEFT_X, 1.0)
	await _frames()
	# V2 P3b: one push steps off the 3x3 Core onto the next free cell
	_check("PC-U5: stick moves the grid cursor once per push", main.sel == TowerState.CORE_SLOT + 2, str(main.sel))
	_pad_axis(JOY_AXIS_LEFT_X, 0.0)
	main.S.pending_place = "gun"
	_pad_button(JOY_BUTTON_A)
	await _frames()
	_check("PC-U5: A places at the cursor", main.S.id_at(TowerState.CORE_SLOT + 2) == "gun")
	main.abandon_run()
	await _frames(3)
	_key(KEY_ESCAPE)
	await _frames()
	_check("PC-U5: keyboard switches glyphs back; Esc leaves results", main.last_device == "kbm" and main.screen == "base")
	_press("HUD Menu")
	await _frames()
	_check("PC: Menu returns to the slot picker", main.screen == "menu" and MetaSave.slot_exists(1))
	_press("SLOT 1 DELETE")
	await _frames()
	_check("PC-U6: delete asks for confirmation first", main.confirm_del == 1 and MetaSave.slot_exists(1) and _find("SLOT 1 CONFIRM") != null)
	_press("SLOT 1 CONFIRM")
	await _frames()
	_check("PC-U6: confirmed delete removes the slot", not MetaSave.slot_exists(1))
	_press("SLOT 1 PLAY")
	await _frames()
	_check("PC: new game in the emptied slot", main.screen == "base" and int(main.save["runs"]) == 0)
