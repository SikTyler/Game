extends SceneTree
## Corehold interaction self-test — the view<->input twin of selftest.gd.
## Boots Main.tscn headless and pushes REAL mouse clicks through the full loop:
## base: select slot -> build -> upgrade core -> START RUN -> level-up card ->
## place on slot -> select -> cash upgrade -> unlock plot -> death -> results ->
## BACK TO BASE -> START RUN again (loop seam). Also: offline-earnings modal,
## tier selector, Labs / Cards / Missions tabs, speed pill, draft reroll and
## the perk overlay (SPEC UI). Asserts ENGINE / SAVE state after
## every click. Prints "UITEST OK" (exit 0) or "UITEST FAIL: <n> checks failed".
## Run: godot --headless --path games/towerdef-pc-0001/ --script res://uitest.gd

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const Labs := preload("res://Labs.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const Outpost := preload("res://Outpost.gd")
const Desktop := preload("res://ui/Desktop.gd")
const Settings := preload("res://Settings.gd")
const Keybinds := preload("res://Keybinds.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const T0: int = 1800000000

var main: Node2D
var fail_count: int = 0


## Mobile 5x5 cell index -> the same cell on the PC 7x7 board (r+1, c+1).
func _c(i5: int) -> int:
	return BaseMeta.idx5_to_7(i5)


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


## Button label: its "key" meta (rich / ambiguous buttons) or its text of a rich (icon + labels) button.
func _label(b: Button) -> String:
	if b.has_meta("key"):
		return String(b.get_meta("key"))
	return b.text


func _find_ctl(key: String) -> Control:
	for c in main.ui.get_children():
		if (c as Control).has_meta("key") and String((c as Control).get_meta("key")) == key and not c.is_queued_for_deletion():
			return c
	return null


func _find(prefix: String) -> Button:
	for c in main.ui.get_children():
		if c is Button and _label(c as Button).begins_with(prefix) and not (c as Button).is_queued_for_deletion():
			return c
	return null


func _press(prefix: String) -> bool:
	var b: Button = _find(prefix)
	if b == null:
		print("UITEST note: no button '%s'" % prefix)
		return false
	_click(b.get_global_rect().get_center())
	return true


## Desktop chrome (main.dui) lookups: exact "key" meta.
func _findd(key: String) -> Button:
	for c in main.dui.get_children():
		if c is Button and _label(c as Button) == key and not (c as Button).is_queued_for_deletion():
			return c
	return null


func _pressd(key: String) -> bool:
	var b: Button = _findd(key)
	if b == null:
		print("UITEST note: no desktop button '%s'" % key)
		return false
	_click(b.get_global_rect().get_center())
	return true


func _mouse(pos: Vector2, button: MouseButton, pressed: bool) -> void:
	main.last_tap_ms = -1000
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


func _motion(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


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


func _no_overlap(rects: Array) -> bool:
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			if (rects[a] as Rect2).grow(-1.0).intersects((rects[b] as Rect2).grow(-1.0)):
				return false
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
	# ---- PC MAIN MENU / SLOT PICKER (PC-U6) -----------------------------------
	_check("PC: boots to the main menu", main.screen == "menu")
	_check("PC: slot picker shows 3 slots", _findd("SLOT 1 PLAY") != null and _findd("SLOT 2 PLAY") != null and _findd("SLOT 3 PLAY") != null)
	_pressd("SLOT 1 PLAY")
	await _frames()
	_check("PC: slot 1 loads to the base", main.screen == "base" and MetaSave.active == 1)
	main.save = BaseMeta.default_save()
	main.save["coins"] = 1000   # PC ring-2 corner cell costs 600
	main._rebuild_ui()
	await _frames()

	# ---- BASE SCREEN ---------------------------------------------------------
	_check("boots to base screen", main.screen == "base")
	_click(main.w2s(TowerState.slot_pos(_c(7))))
	await _frames()
	_check("tap selects slot", main.sel == _c(7))
	_check("sfx node owned by Main (no autoload)", main.sfx != null and main.sfx.get_parent() == main and AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Music") >= 0)
	main.sfx.clear_log()
	_press("Gun Turret")
	await _frames()
	_check("build button places permanent gun", String(BaseMeta.slot_of(main.save, _c(7)).get("id", "")) == "gun")
	_check("sfx: button click + place clips fire", main.sfx.played("click") and main.sfx.played("place"))
	main.sfx.clear_log()
	_press("Upgrade")
	await _frames()
	_check("perm upgrade button", int(BaseMeta.slot_of(main.save, _c(7)).get("lvl", 0)) == 2)
	_check("sfx: upgrade clip fires", main.sfx.played("upgrade"))
	_press("Core DMG")
	await _frames()
	_check("core upgrade button", int(main.save["core"]["dmg"]) == 1)
	_click(main.w2s(TowerState.slot_pos(_c(0))))
	await _frames()
	_press("Unlock slot")
	await _frames()
	_check("perm unlock button", BaseMeta.is_unlocked(main.save, _c(0)))

	# ---- BOOT: OFFLINE EARNINGS MODAL -----------------------------------------
	# REDESIGN (ENGINE-META, deliberate): the away pay is the Outpost's stored
	# production (Offline.gd is gone) — a connected Coin Mill ran for 2 h.
	main.now_override = T0
	var boot_save: Dictionary = main.save.duplicate(true)
	boot_save["coins"] = int(boot_save["coins"]) + 500
	var mev: Array = Outpost.place(boot_save, "mill", 4, 4, 0, T0 - 7200 - 120)
	Outpost.tick(boot_save, T0 - 7200)
	boot_save["last_seen"] = T0 - 7200
	var expect_off: int = int(Outpost.away_report(BaseMeta.normalize(boot_save), T0)["coins"])
	main.boot(boot_save, T0)
	await _frames()
	_check("offline modal shown at boot", not main.offline_offer.is_empty() and _find("Collect") != null and _find("START RUN") == null)
	var c_before: int = int(main.save["coins"])
	_press("Collect")
	await _frames()
	_check("collect pays offline coins", expect_off > 0 and int(main.save["coins"]) == c_before + expect_off and main.offline_offer.is_empty(), "%d" % expect_off)
	_check("missions rolled at boot", Missions.list(main.save).size() == 3)
	_check("boot kept permanent base", String(BaseMeta.slot_of(main.save, _c(7)).get("id", "")) == "gun")

	# ---- TIER SELECTOR -------------------------------------------------------
	main.save["best_wave_by_tier"] = {"1": 40}
	main._rebuild_ui()
	await _frames()
	_press(">")
	await _frames()
	_check("tier > selects tier 2", int(main.save["tier"]) == 2 and main.view_tier == 2)
	_press(">")
	await _frames()
	_check("locked tier 3 shown, not selected, START disabled", main.view_tier == 3 and int(main.save["tier"]) == 2 and _find("START RUN").disabled)
	_press("<")
	await _frames()
	_press("<")
	await _frames()
	_check("tier < back to tier 1", int(main.save["tier"]) == 1 and main.view_tier == 1)

	# ---- LABS TAB ------------------------------------------------------------
	main.save["coins"] = 5000
	main.save["gems"] = 300
	_press("TAB Labs")
	await _frames()
	_check("labs tab opens", main.tab == "labs" and _find("LAB dmg") != null)
	var lc: int = int(main.save["coins"])
	_press("LAB dmg")
	await _frames()
	_check("start research", Labs.is_running(main.save, "dmg") and int(main.save["coins"]) == lc - Labs.cost("dmg", 0))
	main.now_override = T0 + 100000
	main.poll_t = 1.0
	await _frames(3)
	_check("real-time research completes on poll", Labs.level(main.save, "dmg") == 1 and not Labs.is_running(main.save, "dmg"))
	_press("LAB hp")
	await _frames()
	var g0: int = int(main.save["gems"])
	_press("Rush")
	await _frames()
	_check("rush finishes research for gems", Labs.level(main.save, "hp") == 1 and int(main.save["gems"]) < g0)
	# REDESIGN (deliberate): no gem lab slots; queues follow the Research Hall.
	_check("research queue count follows the Research Hall", Labs.slots(main.save) == 1 and _find("Buy slot") == null)

	# ---- CARDS TAB -----------------------------------------------------------
	_press("TAB Cards")
	await _frames()
	_check("cards tab opens", main.tab == "cards" and _find("Open Chest") != null)
	var g1: int = int(main.save["gems"])
	main.sfx.clear_log()
	_press("Open Chest")
	await _frames()
	_check("sfx: card_open clip fires", main.sfx.played("card_open"))
	_check("open chest", Cards.owned(main.save).size() == 1 and int(main.save["gems"]) == g1 - Cards.chest_cost())
	var cid: String = String(Cards.owned(main.save).keys()[0])
	_press("CARD " + cid)
	await _frames()
	_check("tap card equips", Cards.equipped(main.save).has(cid))
	_press("EQ " + cid)
	await _frames()
	_check("tap equipped slot unequips", not Cards.equipped(main.save).has(cid))
	_press("CARD " + cid)
	await _frames()
	_press("CSLOT")
	await _frames()
	_check("buy card slot", Cards.slots(main.save) == 3 and Cards.equipped(main.save).has(cid))

	# ---- MISSIONS TAB --------------------------------------------------------
	_press("TAB Missions")
	await _frames()
	var g2: int = int(main.save["gems"])
	var c2b: int = int(main.save["coins"])
	_press("Claim Day")
	await _frames()
	_check("streak claim day 1", int(main.save["streak"]["day_idx"]) == 1 and int(main.save["coins"]) > c2b)
	_check("streak not claimable twice", _find("Claim Day") == null)
	var lst: Array = Missions.list(main.save)
	for k in lst.size():
		lst[k]["prog"] = int(lst[k]["target"])
	main._rebuild_ui()
	await _frames()
	for k in lst.size():
		_press("MCLAIM %d" % k)
		await _frames()
	_check("mission claims", Missions.all_claimed(main.save) and int(main.save["gems"]) > g2)
	var g3: int = int(main.save["gems"])
	_press("BONUS")
	await _frames()
	_check("all-clear bonus", bool(main.save["missions"]["bonus_claimed"]) and int(main.save["gems"]) > g3)
	_press("TAB Base")
	await _frames()
	_check("back to base tab", main.tab == "base")
	main.save["research"]["lvls"]["speed"] = 1

	# ---- OPTIONS / CREDITS (gear) ---------------------------------------------
	_press("GEAR")
	await _frames()
	_check("gear opens options", main.overlay == "options" and _find_ctl("SLIDER music") != null and _find("MUTE") != null)
	var ms: Control = _find_ctl("SLIDER music")
	if ms != null:
		var mr: Rect2 = ms.get_global_rect()
		_click(Vector2(mr.position.x + mr.size.x * 0.25, mr.get_center().y))
		await _frames()
	var mus: float = float(main.save["settings"]["music"])
	_check("music slider click sets volume", mus > 0.1 and mus < 0.4, str(mus))
	var ss: Control = _find_ctl("SLIDER sfx")
	if ss != null:
		var sr: Rect2 = ss.get_global_rect()
		_click(Vector2(sr.position.x + sr.size.x * 0.6, sr.get_center().y))
		await _frames()
	var sv: float = float(main.save["settings"]["sfx"])
	_check("sfx slider click sets volume", sv > 0.45 and sv < 0.75, str(sv))
	_check("music volume applied to bus", absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - (main.sfx.lin_db(mus) - 4.0)) < 0.5)
	var m0: bool = bool(main.save["settings"]["mute"])
	_press("MUTE")
	await _frames()
	_check("mute button toggles + applies", bool(main.save["settings"]["mute"]) != m0 and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) != m0)
	var disk: Dictionary = BaseMeta.normalize(MetaSave.read())
	_check("audio settings persisted to save file", absf(float(disk["settings"]["music"]) - mus) < 0.001 and absf(float(disk["settings"]["sfx"]) - sv) < 0.001 and bool(disk["settings"]["mute"]) != m0)
	_press("MUTE")
	await _frames()
	_press("Credits")
	await _frames()
	_check("credits open from options", main.overlay == "credits" and _find_ctl("CREDITS_SCROLL") != null)
	_press("Back")
	await _frames()
	_check("credits back -> options", main.overlay == "options")
	_press("Back")
	await _frames()
	_check("options close to base", main.overlay == "" and _find("START RUN") != null)

	# ---- RUN -----------------------------------------------------------------
	main.sfx.clear_log()
	_press("START RUN")
	await _frames()
	_check("start run", main.screen == "run" and main.S != null)
	_check("sfx: wave_start clip fires on run start", main.sfx.played("wave_start"))
	var S = main.S
	# REDESIGN (deliberate): the run grid starts empty; permanent buildings stay out of runs.
	_check("run grid starts empty (perm base stays out of runs)", S.building_count() == 0 and not bool(S.unlocked[_c(0)]))
	_press("SPD")
	await _frames()
	_check("speed pill cycles game speed", absf(S.speed - 1.5) < 0.01 and absf(float(main.save["speed"]) - 1.5) < 0.01)
	_press("SPD")
	await _frames()
	_check("speed pill wraps to 1x", absf(S.speed - 1.0) < 0.01)
	S.spawn_hold = true
	# REDESIGN: drafts follow the wave cadence; grant_draft is the tool hook.
	S.grant_draft()
	S.draft[0] = load("res://Draft.gd").card_for("gun", S._draft_ctx(""))
	main._rebuild_ui()
	await _frames(3)
	_check("draft shows cards", S.draft.size() == 3 and (_find("NEW") != null or _find("+1") != null))
	var new_id: String = ""
	var card_btn: Button = null
	for c in main.ui.get_children():
		if c is Button and _label(c as Button).begins_with("NEW"):
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
		_click(main.w2s(TowerState.slot_pos(_c(8))))
		await _frames()
		_check("slot tap places building", S.id_at(_c(8)) == new_id and S.pending_place == "")
		_check("sfx: run place clip fires", main.sfx.played("place"))
	else:
		_check("draft has a NEW card", false)
	S.cash = 500.0
	# REDESIGN (deliberate): buildings level through duplicate picks only and
	# rings open by Core track total, so cash goes into the Core tracks.
	_check("cash cannot level a building / unlock a cell", S.upgrade(_c(8)).is_empty() and S.unlock_plot(_c(4)).is_empty())
	_click(main.w2s(TowerState.slot_pos(_c(12))))
	await _frames()
	main.sfx.clear_log()
	_press("Overcharge")
	await _frames()
	_check("core cash upgrade button", S.core_run_lvl == 1)
	_check("sfx: run upgrade clip fires", main.sfx.played("upgrade"))
	# Targeting: selected weapon shows a "Target: X" cycle button (real click).
	var tm0: String = String(S.target_modes[_c(12)])
	_check("target button shown for selected weapon", _find("Target: Nearest") != null or _find("Target:") != null)
	_press("Target:")
	await _frames()
	_check("target button cycles mode", String(S.target_modes[_c(12)]) != tm0 and String(S.target_modes[_c(12)]) == String(TowerState.TARGET_MODES[(TowerState.TARGET_MODES.find(tm0) + 1) % 4]))
	_check("target button label updates", _find("Target: " + String(S.target_modes[_c(12)]).capitalize()) != null)
	# AC-37 polish: the boss-bounty banner renders below the grid, never over a slot.
	main._handle([{"t": "boss_bounty", "coins": 50, "gems": 1, "pos": TowerState.CENTER}])
	var bpop: Dictionary = main.pops.last
	var bpos: Vector2 = bpop["pos"]
	_check("bounty banner clears the grid", String(bpop["text"]).begins_with("BOUNTY") and bpos.y - 30.0 > TowerState.CENTER.y + float(TowerState.SIDE) * 0.5 * TowerState.CELL)

	# ---- REROLL + PERK OVERLAY -----------------------------------------------
	S.grant_draft()
	await _frames(3)
	S.free_reroll = false
	S.rerolls_left = 1
	main._rebuild_ui()
	await _frames()
	_press("Reroll")
	await _frames()
	_check("draft reroll button", S.rerolls_left == 0 and S.draft.size() == 3)
	var dk: String = _label(_find("NEW")) if _find("NEW") != null else "+1"
	_press(dk)
	await _frames()
	if S.pending_place != "":
		_click(main.w2s(TowerState.slot_pos(int(S.free_slots()[0]))))
		await _frames()
	_check("rerolled draft resolves", S.draft.is_empty() and S.pending_place == "")
	S.perk_pending = 1
	await _frames(3)
	_check("perk overlay shows 3 cards", S.perk_offer.size() == 3 and _find("PERK") != null)
	var pid: String = String(S.perk_offer[0])
	_press("PERK")
	await _frames()
	_check("perk tap takes perk", S.perks_taken.size() == 1 and S.perk_offer.is_empty() and _find("PERK") == null, pid)

	# ---- PAUSE / RESUME --------------------------------------------------------
	S.spawn_hold = true
	_press("PAUSE")
	await _frames()
	var ta: float = S.time_alive
	var wt: float = S.wave_t
	await _frames(10)
	_check("pause opens menu + freezes engine time", main.overlay == "pause" and main.is_paused() and S.time_alive == ta and S.wave_t == wt)
	_press("Options")
	await _frames(4)
	_check("pause -> options keeps time frozen", main.overlay == "options" and S.time_alive == ta)
	_press("Back")
	await _frames()
	_check("options back -> pause", main.overlay == "pause")
	_press("Resume")
	await _frames(4)
	_check("resume unfreezes engine time", main.overlay == "" and S.time_alive > ta)

	# ---- DEATH -> RESULTS -> BASE -> RUN (loop seam) -------------------------
	S.wind_used = true   # a chest may have equipped Second Wind; this check is about the death seam
	S.hp = -1.0
	S.stats["regen"] = 0.0
	await _frames(3)
	_check("death shows results", main.screen == "results" and _find("BACK TO BASE") != null)
	_check("sfx: game_over clip fires", main.sfx.played("game_over"))
	_check("sfx: rate limit drops a same-clip burst", main.sfx.play("kill") != main.sfx.play("kill") or not main.sfx.streams.has("kill"))
	var vol_before: bool = bool(main.save["settings"]["mute"])
	main.toggle_mute()
	_check("sfx: mute toggles save setting + bus", bool(main.save["settings"]["mute"]) != vol_before and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) != vol_before)
	main.toggle_mute()
	_check("coins banked", int(main.save["runs"]) == 1)
	_check("results has coin breakdown", (main.last_result.get("breakdown", {}) as Dictionary).has("cashout") and not main.last_breakdown.is_empty())
	_press("BACK TO BASE")
	await _frames()
	_check("back to base screen", main.screen == "base" and _find("START RUN") != null)
	_press("START RUN")
	await _frames()
	_check("second run starts fresh", main.screen == "run" and main.S != S and main.S.wave == 1 and main.S.id_at(_c(8)) == "")

	# ---- ABANDON (pause menu) -> coins banked --------------------------------
	var S2 = main.S
	S2.coins_run = 33.0
	var runs_b: int = int(main.save["runs"])
	var coins_b: int = int(main.save["coins"])
	_press("PAUSE")
	await _frames()
	_press("Abandon")
	await _frames(3)
	_check("abandon ends run -> results", S2.over and main.screen == "results" and _find("BACK TO BASE") != null)
	_check("abandon banks coins", int(main.save["runs"]) == runs_b + 1 and int(main.save["coins"]) >= coins_b + 33, "%d -> %d" % [coins_b, int(main.save["coins"])])
	var disk2: Dictionary = BaseMeta.normalize(MetaSave.read())
	_check("abandon bank persisted", int(disk2["coins"]) == int(main.save["coins"]))

	await _pc_desktop()

	MetaSave.clear()
	if fail_count == 0:
		print("UITEST OK")
		quit(0)
	else:
		print("UITEST FAIL: %d checks failed" % fail_count)
		quit(1)


# ============================================================ PC DESKTOP UI
func _pc_desktop() -> void:
	var settings_before: Dictionary = Settings.read()
	_pressd("DBACK")
	await _frames()
	_check("PC: results Back to Base (hotbar)", main.screen == "base")
	main.save["coins"] = 5000
	main.settings["controls"]["tooltip_delay"] = 0.0
	main._rebuild_ui()
	await _frames()

	# ---- PC-U1 layout -----------------------------------------------------
	var hud := Rect2(0, 0, main.vw, main.HUD_H)
	var hot := Rect2(0, main.vh - main.HOT_H, main.vw, main.HOT_H)
	var lr: Rect2 = Desktop.left_rect(main)
	var rr: Rect2 = Desktop.right_rect(main)
	var col := Rect2(main.col_pos, Vector2(main.W, main.H) * main.col_s)
	_check("PC-U1: HUD, left, centre, right, hotbar do not overlap at 1920x1080", main.vw >= 1919.0 and _no_overlap([hud, hot, lr, rr, col]), "%s" % [[hud, hot, lr, rr, col]])
	for res in [Vector2i(1280, 720), Vector2i(1280, 800)]:
		root.size = res
		await _frames(3)
		var vis := Rect2(Vector2.ZERO, main.get_viewport().get_visible_rect().size)
		var inside: bool = true
		for c in main.dui.get_children():
			if c is Control and not (c as Control).is_queued_for_deletion() and not vis.encloses((c as Control).get_rect()):
				inside = false
				print("UITEST note: outside ", _label(c as Button) if c is Button else c.name, " ", (c as Control).get_rect(), " vis ", vis)
		_check("PC-U1: every control in the viewport at %dx%d (re-laid out)" % [res.x, res.y], inside and absf(main.vw - vis.size.x) < 1.0)
	root.size = Vector2i(1920, 1080)
	await _frames(3)

	# ---- PC-U2 tooltips / press mode / height ------------------------------
	var bad: Array = []
	for host in [main.dui, main.ui]:
		for c in host.get_children():
			if c is Button and (c as Button).visible and not (c as Button).is_queued_for_deletion():
				var b: Button = c
				if b.tooltip_text == "" or b.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
					bad.append(_label(b))
				if host == main.dui and b.size.y < 40.0:
					bad.append(_label(b) + " h")
	_check("PC-U2: every button has a tooltip, press action, >= 40 px", bad.is_empty(), str(bad))
	_check("PC-U2: tooltip box ignores the mouse", main.tipbox.mouse_filter == Control.MOUSE_FILTER_IGNORE and main.dui.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	# hover -> tooltip appears (button, then a cell)
	var sb: Button = _findd("HUD Stats")
	_motion(sb.get_global_rect().get_center())
	await _frames(3)
	_check("PC: hovering a button shows its tooltip", main.tipbox.visible and main.tip_label.text.contains("Lifetime"), main.tip_label.text)
	_motion(_cell_scr(TowerState.CORE_SLOT))
	await _frames(3)
	_check("PC: hovering a cell shows a building tooltip", main.tipbox.visible and main.tip_label.text.begins_with("The Core"), main.tip_label.text)
	_motion(Vector2(main.vw * 0.5, 30))
	await _frames(2)

	# ---- PC-U4 drag-to-place / right-click / wheel ---------------------------
	var free: int = -1
	for i in TowerState.N:
		if free < 0 and i != TowerState.CORE_SLOT and BaseMeta.is_unlocked(main.save, i) and BaseMeta.slot_of(main.save, i).is_empty() and BaseMeta.place_ok(i, "gun"):
			free = i
	if free < 0:
		free = _c(13)
		BaseMeta.demolish(main.save, free)
		main._rebuild_ui()
		await _frames()
	var hb: Button = _findd("HOT Gun Turret")
	var hp: Vector2 = hb.get_global_rect().get_center()
	_motion(hp)
	_mouse(hp, MOUSE_BUTTON_LEFT, true)
	await _frames()
	_motion(_cell_scr(free))
	await _frames(2)
	_mouse(_cell_scr(free), MOUSE_BUTTON_LEFT, false)
	await _frames()
	_check("PC-U4: drag from hotbar to a valid cell places", String(BaseMeta.slot_of(main.save, free).get("id", "")) == "gun")
	var locked: int = 0   # ring-3 corner, locked on a fresh save
	_check("PC-U4: test cell 0 is locked", not BaseMeta.is_unlocked(main.save, locked))
	hb = _findd("HOT Gun Turret")
	hp = hb.get_global_rect().get_center()
	_motion(hp)
	_mouse(hp, MOUSE_BUTTON_LEFT, true)
	await _frames()
	_motion(_cell_scr(locked))
	await _frames(3)
	_check("PC-U4: drag ghost over a locked cell shows the reason", String(main.get_meta("ghost_reason", "")) == "Locked cell", String(main.get_meta("ghost_reason", "")))
	_mouse(_cell_scr(locked), MOUSE_BUTTON_LEFT, false)
	await _frames()
	_check("PC-U4: drop on a locked cell does not place", BaseMeta.slot_of(main.save, locked).is_empty() and main.drag_id == "")
	_mouse(_cell_scr(free), MOUSE_BUTTON_RIGHT, true)
	_mouse(_cell_scr(free), MOUSE_BUTTON_RIGHT, false)
	await _frames()
	_check("PC-U4: right-click opens the info popover with Upgrade/Sell", main.overlay == "info" and main.info_cell == free and _findd("INFO UPGRADE") != null and _findd("INFO SELL") != null)
	_pressd("INFO UPGRADE")
	await _frames()
	_check("PC-U4: popover Upgrade upgrades", int(BaseMeta.slot_of(main.save, free).get("lvl", 0)) == 2)
	_pressd("INFO SELL")
	await _frames()
	_check("PC-U4: popover Sell demolishes", BaseMeta.slot_of(main.save, free).is_empty() and main.overlay == "")
	var c0: Vector2 = _cell_scr(TowerState.CORE_SLOT)
	_mouse(c0, MOUSE_BUTTON_WHEEL_UP, true)
	await _frames()
	_check("PC-U4: wheel up zooms in", absf(main.zoom - 1.1) < 0.001, str(main.zoom))
	for k in 10:
		_mouse(main.w2s(TowerState.CENTER), MOUSE_BUTTON_WHEEL_UP, true)
	await _frames()
	_check("PC-U4: zoom clamps at 1.4", absf(main.zoom - 1.4) < 0.001, str(main.zoom))
	for k in 12:
		_mouse(main.w2s(TowerState.CENTER), MOUSE_BUTTON_WHEEL_DOWN, true)
	await _frames()
	_check("PC-U4: zoom clamps at 0.8", absf(main.zoom - 0.8) < 0.001, str(main.zoom))
	main.zoom = 1.0
	_click(_cell_scr(TowerState.CORE_SLOT))
	await _frames()
	_check("PC: click still selects a cell after zooming", main.sel == TowerState.CORE_SLOT)

	# ---- PC-U3 hotkeys -------------------------------------------------------
	main.sel = -1
	_key(KEY_1)
	await _frames()
	var first: String = String(BuildingDB.all_ids()[0])
	_check("PC-U3: 1 arms hotbar slot 1", main.armed == first, main.armed)
	_key(KEY_ESCAPE)
	await _frames()
	_check("PC-U3: Esc cancels the armed building", main.armed == "")
	_key(KEY_1)
	await _frames()
	_click(_cell_scr(free))
	await _frames()
	_check("PC-U3: armed building places on click", String(BaseMeta.slot_of(main.save, free).get("id", "")) == first)
	_key(KEY_ESCAPE)
	main.sel = free
	await _frames()
	_key(KEY_U)
	await _frames()
	_check("PC-U3: U upgrades the selection", int(BaseMeta.slot_of(main.save, free).get("lvl", 0)) == 2)
	_key(KEY_X)
	await _frames()
	_check("PC-U3: X sells the selection", BaseMeta.slot_of(main.save, free).is_empty())
	_key(KEY_L)
	await _frames()
	_check("PC-U3: L opens the Labs tab", main.tab == "labs")
	_key(KEY_B)
	await _frames()
	_key(KEY_H)
	await _frames()
	_check("PC-U3: H opens stats", main.overlay == "stats")
	_key(KEY_ESCAPE)
	await _frames()
	_check("PC-U3: Esc closes the overlay", main.overlay == "")

	# ---- PC-U5 controller --------------------------------------------------
	main.sel = TowerState.CORE_SLOT
	_pad_axis(JOY_AXIS_LEFT_X, 1.0)
	await _frames()
	_pad_axis(JOY_AXIS_LEFT_X, 1.0)   # still held: no repeat
	await _frames()
	_check("PC-U5: stick moves the grid cursor once per push", main.sel == TowerState.CORE_SLOT + 1, str(main.sel))
	_check("PC-U5: glyphs switch to the pad", main.last_device == "pad" and Desktop.hint(main, "cancel") == "B")
	_pad_axis(JOY_AXIS_LEFT_X, 0.0)
	await _frames()
	main.armed = first
	_pad_button(JOY_BUTTON_A)
	await _frames()
	_check("PC-U5: A places the armed building at the cursor", String(BaseMeta.slot_of(main.save, TowerState.CORE_SLOT + 1).get("id", "")) == first)
	var dead: Array = []
	for c in main.dui.get_children():
		if c is Button and not (c as Button).disabled:
			if (c as Button).focus_mode != Control.FOCUS_ALL or (c as Button).find_next_valid_focus() == null:
				dead.append(_label(c as Button))
	_check("PC-U5: base focus chain has no dead ends (pad)", dead.is_empty(), str(dead))
	main.set_overlay("settings")
	await _frames()
	var dead2: int = 0
	for c in main.dui.get_children():
		if c is Button and (c as Button).focus_mode != Control.FOCUS_ALL:
			dead2 += 1
	_check("PC-U5: settings buttons are all focusable (pad)", dead2 == 0)
	main.set_overlay("")
	_key(KEY_ESCAPE)   # back to keyboard/mouse
	await _frames()
	_check("PC-U5: keyboard switches glyphs back", main.last_device == "kbm")
	main.sel = -1

	# ---- PC-S1/S2 settings + remap ------------------------------------------
	_pressd("HUD Settings")
	await _frames()
	_check("PC-S1: settings opens on 4 tabs", main.overlay == "settings" and _findd("SET TAB Video") != null and _findd("SET TAB Audio") != null and _findd("SET TAB Controls") != null and _findd("SET TAB Gameplay") != null)
	var vs0: String = String(Settings.normalize(main.settings)["video"]["vsync"])
	_pressd("SET VSync")
	await _frames()
	var vs1: String = String(Settings.normalize(main.settings)["video"]["vsync"])
	_check("PC-S1: VSync cycles and persists to settings.cfg", vs1 != vs0 and String(Settings.read()["video"]["vsync"]) == vs1)
	var fps0: int = int(Engine.max_fps)
	_pressd("SET FPS cap")
	await _frames()
	_check("PC-S1: FPS cap applies to the engine", int(Engine.max_fps) != fps0 and int(Engine.max_fps) == int(main.settings["video"]["fps_cap"]))
	_pressd("SET TAB Audio")
	await _frames()
	_check("PC-S1: audio tab lists every bus", _findd("SET Master volume") != null and _findd("SET UI volume") != null)
	_pressd("SET TAB Controls")
	await _frames()
	_pressd("REMAP pause")
	await _frames()
	_check("PC-S2: remap button enters capture", main.remap_action == "pause")
	_key(KEY_P)
	await _frames()
	_check("PC-S2: captured key rebinds the action", main.remap_action == "" and Keybinds.hint("pause") == "P", Keybinds.hint("pause"))
	_check("PC-S2: binding persisted in settings.cfg", (Settings.read()["keybinds"] as Dictionary).has("pause"))
	_pressd("REMAP pause")
	await _frames()
	_key(KEY_U)   # U belongs to "upgrade": swap
	await _frames()
	_check("PC-S2: conflicting key swaps bindings", Keybinds.hint("pause") == "U" and Keybinds.hint("upgrade") == "P", "%s / %s" % [Keybinds.hint("pause"), Keybinds.hint("upgrade")])
	_pressd("KEYS RESET ALL")
	await _frames()
	_check("PC-S2: reset all restores defaults", Keybinds.hint("pause") == "Space" and Keybinds.hint("upgrade") == "U")
	_pressd("SET CLOSE")
	await _frames()

	# ---- PC-U7 stats / history / achievements --------------------------------
	_pressd("HUD History")
	await _frames()
	var hist: Array = main.save.get("history", [])
	_check("PC-U7: history lists the save's runs with Retry", main.overlay == "history" and hist.size() >= 2 and _findd("HIST RETRY 0") != null and _findd("HIST RETRY %d" % (mini(12, hist.size()) - 1)) != null)
	_pressd("REC Stats")
	await _frames()
	_check("PC-U7: stats overlay from engine data", main.overlay == "stats" and int(main.save["stats"]["runs"]) == hist.size())
	_pressd("REC Achievements")
	await _frames()
	_check("PC-U7: achievements overlay", main.overlay == "achievements")
	_pressd("REC Stats")
	await _frames()
	_pressd("REC History")
	await _frames()
	var want_seed: int = int((hist[hist.size() - 1] as Dictionary)["seed"])
	_pressd("HIST RETRY 0")
	await _frames()
	_check("PC-U7: Retry replays the entry's seed", main.screen == "run" and main.S != null and int(main.S.run_seed) == want_seed and main.last_seed == want_seed)

	# ---- in-run: pause key, draft/perk hotkeys, lane focus, retry -----------
	var S = main.S
	_key(KEY_SPACE)
	await _frames()
	_check("PC-U3: Space pauses", main.overlay == "pause" and main.is_paused())
	_key(KEY_SPACE)
	await _frames()
	_check("PC-U3: Space resumes", main.overlay == "")
	var fq: int = S.focus_quad
	_key(KEY_V)
	await _frames()
	_check("PC-U3: V moves the lane focus", S.focus_quad == (fq + 1) % 4)
	S.perk_pending = 1
	for k in 40:
		if S.perk_offer.size() > 0:
			break
		await _frames(1)
	var perks0: int = S.perks_taken.size()
	_check("PC-U6: perk draft modal on the hotbar", S.perk_offer.size() == 3 and _findd("DPERK " + String(load("res://data/PerkDB.gd").get_def(String(S.perk_offer[1]))["name"])) != null)
	_key(KEY_2)
	await _frames()
	_check("PC-U6: perk draft accepts 2", S.perks_taken.size() == perks0 + 1 and S.perk_offer.is_empty())
	S.grant_draft()
	for k in 40:
		if S.draft.size() > 0:
			break
		await _frames(1)
	if S.draft.size() > 0:
		var cell: int = int(S.free_slots()[0]) if S.free_slots().size() > 0 else -1
		var card: Button = null
		for c in main.dui.get_children():
			if c is Button and _label(c as Button).begins_with("DCARD"):
				card = c
				break
		var newc: bool = String((S.draft[0] as Dictionary)["kind"]) == "new"
		if card != null and cell >= 0 and newc:
			var cp: Vector2 = card.get_global_rect().get_center()
			_motion(cp)
			_mouse(cp, MOUSE_BUTTON_LEFT, true)
			await _frames()
			_motion(_cell_scr(cell))
			await _frames()
			_mouse(_cell_scr(cell), MOUSE_BUTTON_LEFT, false)
			await _frames()
			_check("PC-U4: drag a draft card onto a run cell places it", S.id_at(cell) != "" and S.draft.is_empty())
		else:
			_key(KEY_1)
			await _frames()
			_check("PC-U3: 1 picks draft card 1", S.draft.is_empty())
	var seed_now: int = main.last_seed
	_key(KEY_R, true)
	await _frames()
	_check("PC-U3: Ctrl+R retries the same seed", main.S != S and int(main.S.run_seed) == seed_now)
	main.abandon_run()
	await _frames(3)
	_check("PC-U6: death screen shows Retry seed + Back to Base", main.screen == "results" and _findd("RETRY SEED") != null and _findd("DBACK") != null)
	_pressd("DBACK")
	await _frames()

	# ---- mode select (endless + modifiers) ----------------------------------
	_pressd("MODES")
	await _frames()
	_check("PC: mode select lists the 9 modifiers", main.overlay == "modes" and _findd("MOD Swarm") != null and _findd("MOD Fresh Start") != null)
	_check("PC: endless locked below best wave 50", _findd("MODE Endless").disabled == not BaseMeta.endless_unlocked(main.save))
	_pressd("MOD Swarm")
	await _frames()
	_check("PC: toggling a modifier updates run options", (main.run_opts["modifiers"] as Array).has("swarm"))
	_pressd("MODES START")
	await _frames()
	_check("PC: run starts with the chosen modifiers", main.screen == "run" and (main.S.modifiers as Array).has("swarm"))
	main.abandon_run()
	await _frames(3)
	_pressd("DBACK")
	await _frames()

	# ---- slot delete needs confirmation (PC-U6) ----------------------------
	_pressd("HUD Menu")
	await _frames()
	_check("PC: Menu returns to the slot picker", main.screen == "menu")
	_check("PC: slot 1 exists on disk", MetaSave.slot_exists(1))
	_pressd("SLOT 1 DELETE")
	await _frames()
	_check("PC-U6: delete asks for confirmation first", main.confirm_del == 1 and MetaSave.slot_exists(1) and _findd("SLOT 1 CONFIRM") != null)
	_pressd("SLOT 1 CONFIRM")
	await _frames()
	_check("PC-U6: confirmed delete removes the slot", not MetaSave.slot_exists(1))
	_pressd("SLOT 1 PLAY")
	await _frames()
	_check("PC: new game in the emptied slot", main.screen == "base" and int(main.save["runs"]) == 0)
	Settings.write(settings_before)   # leave the player's settings.cfg as found
	Settings.apply(settings_before)
