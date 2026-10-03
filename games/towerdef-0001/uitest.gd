extends SceneTree
## Corehold interaction self-test — the view<->input twin of selftest.gd.
## Boots Main.tscn headless and pushes REAL mouse clicks through the full loop:
## base: select slot -> build -> upgrade core -> START RUN -> level-up card ->
## place on slot -> select -> cash upgrade -> unlock plot -> death -> results ->
## BACK TO BASE -> START RUN again (loop seam). Asserts ENGINE state after
## every click. Prints "UITEST OK" (exit 0) or "UITEST FAIL: <n> checks failed".
## Run: godot --headless --path games/towerdef-0001/ --script res://uitest.gd

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")

var main: Node2D
var fail_count: int = 0


func _initialize() -> void:
	_run()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fail_count += 1
	print("UITEST %s: %s %s" % ["PASS" if ok else "FAIL", name, detail])


func _click(pos: Vector2) -> void:
	main.last_tap_ms = -1000
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev, true)


func _find(prefix: String) -> Button:
	for c in main.ui.get_children():
		if c is Button and (c as Button).text.begins_with(prefix) and not (c as Button).is_queued_for_deletion():
			return c
	return null


func _press(prefix: String) -> bool:
	var b: Button = _find(prefix)
	if b == null:
		print("UITEST note: no button '%s'" % prefix)
		return false
	_click(b.get_global_rect().get_center())
	return true


func _frames(n: int = 2) -> void:
	for k in n:
		await process_frame


func _run() -> void:
	MetaSave.clear()
	var scene: PackedScene = load("res://Main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await _frames()
	main.save = BaseMeta.default_save()
	main.save["coins"] = 500
	main._rebuild_ui()
	await _frames()

	# ---- BASE SCREEN ---------------------------------------------------------
	_check("boots to base screen", main.screen == "base")
	_click(TowerState.slot_pos(7))
	await _frames()
	_check("tap selects slot", main.sel == 7)
	_press("Gun Turret")
	await _frames()
	_check("build button places permanent gun", String(BaseMeta.slot_of(main.save, 7).get("id", "")) == "gun")
	_press("Upgrade")
	await _frames()
	_check("perm upgrade button", int(BaseMeta.slot_of(main.save, 7).get("lvl", 0)) == 2)
	_press("Core DMG")
	await _frames()
	_check("core upgrade button", int(main.save["core"]["dmg"]) == 1)
	_click(TowerState.slot_pos(0))
	await _frames()
	_press("Unlock slot")
	await _frames()
	_check("perm unlock button", BaseMeta.is_unlocked(main.save, 0))

	# ---- RUN -----------------------------------------------------------------
	_press("START RUN")
	await _frames()
	_check("start run", main.screen == "run" and main.S != null)
	var S = main.S
	_check("perm base carried into run", S.id_at(7) == "gun" and S.lvl_at(7) == 2 and bool(S.unlocked[0]))
	S.spawn_t = 999.0
	S.xp = S.xp_need()
	await _frames(3)
	_check("level-up shows draft cards", S.draft.size() == 3 and (_find("NEW") != null or _find("+1") != null))
	var new_id: String = ""
	var card_btn: Button = null
	for c in main.ui.get_children():
		if c is Button and (c as Button).text.begins_with("NEW"):
			card_btn = c
			break
	var idx: int = -1
	for k in S.draft.size():
		if String(S.draft[k]["kind"]) == "new" and idx < 0:
			idx = k
			new_id = S.draft[k]["id"]
	if card_btn != null and idx >= 0:
		_click(card_btn.get_global_rect().get_center())
		await _frames()
		_check("card tap enters place mode", S.pending_place == new_id)
		_click(TowerState.slot_pos(8))
		await _frames()
		_check("slot tap places building", S.id_at(8) == new_id and S.pending_place == "")
	else:
		_check("draft has a NEW card", false)
	_click(TowerState.slot_pos(7))
	await _frames()
	S.cash = 500.0
	main._rebuild_ui()
	await _frames()
	var lv: int = S.lvl_at(7)
	_press("Upgrade")
	await _frames()
	_check("cash upgrade button", S.lvl_at(7) == lv + 1)
	_click(TowerState.slot_pos(4))
	await _frames()
	_press("Unlock plot")
	await _frames()
	_check("run unlock button", bool(S.unlocked[4]))
	_click(TowerState.slot_pos(12))
	await _frames()
	_press("Core DMG")
	await _frames()
	_check("core cash upgrade button", S.core_run_lvl == 1)

	# ---- DEATH -> RESULTS -> BASE -> RUN (loop seam) -------------------------
	S.hp = -1.0
	S.stats["regen"] = 0.0
	await _frames(3)
	_check("death shows results", main.screen == "results" and _find("BACK TO BASE") != null)
	_check("coins banked", int(main.save["runs"]) == 1)
	_press("BACK TO BASE")
	await _frames()
	_check("back to base screen", main.screen == "base" and _find("START RUN") != null)
	_press("START RUN")
	await _frames()
	_check("second run starts fresh", main.screen == "run" and main.S != S and main.S.wave == 1 and main.S.id_at(8) == "")

	MetaSave.clear()
	if fail_count == 0:
		print("UITEST OK")
		quit(0)
	else:
		print("UITEST FAIL: %d checks failed" % fail_count)
		quit(1)
