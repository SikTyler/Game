extends SceneTree
## Corehold interaction self-test — the view<->input twin of selftest.gd.
## Boots Main.tscn headless and pushes REAL mouse clicks through the full loop:
## base: select slot -> build -> upgrade core -> START RUN -> level-up card ->
## place on slot -> select -> cash upgrade -> unlock plot -> death -> results ->
## BACK TO BASE -> START RUN again (loop seam). Also: offline-earnings modal,
## tier selector, Labs / Cards / Missions tabs, speed pill, draft reroll and
## the perk overlay (SPEC UI). Asserts ENGINE / SAVE state after
## every click. Prints "UITEST OK" (exit 0) or "UITEST FAIL: <n> checks failed".
## Run: godot --headless --path games/towerdef-0001/ --script res://uitest.gd

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const Labs := preload("res://Labs.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const Offline := preload("res://Offline.gd")
const T0: int = 1800000000

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


## Button label: its "key" meta (rich / ambiguous buttons) or its text of a rich (icon + labels) button.
func _label(b: Button) -> String:
	if b.has_meta("key"):
		return String(b.get_meta("key"))
	return b.text


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
	_check("sfx node owned by Main (no autoload)", main.sfx != null and main.sfx.get_parent() == main and AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Music") >= 0)
	main.sfx.clear_log()
	_press("Gun Turret")
	await _frames()
	_check("build button places permanent gun", String(BaseMeta.slot_of(main.save, 7).get("id", "")) == "gun")
	_check("sfx: button click + place clips fire", main.sfx.played("click") and main.sfx.played("place"))
	main.sfx.clear_log()
	_press("Upgrade")
	await _frames()
	_check("perm upgrade button", int(BaseMeta.slot_of(main.save, 7).get("lvl", 0)) == 2)
	_check("sfx: upgrade clip fires", main.sfx.played("upgrade"))
	_press("Core DMG")
	await _frames()
	_check("core upgrade button", int(main.save["core"]["dmg"]) == 1)
	_click(TowerState.slot_pos(0))
	await _frames()
	_press("Unlock slot")
	await _frames()
	_check("perm unlock button", BaseMeta.is_unlocked(main.save, 0))

	# ---- BOOT: OFFLINE EARNINGS MODAL -----------------------------------------
	main.now_override = T0
	var boot_save: Dictionary = main.save.duplicate(true)
	boot_save["last_seen"] = T0 - 7200
	boot_save["best_coin_rate"] = 20.0
	var expect_off: int = int(Offline.compute(BaseMeta.normalize(boot_save), T0)["coins"])
	main.boot(boot_save, T0)
	await _frames()
	_check("offline modal shown at boot", not main.offline_offer.is_empty() and _find("Collect") != null and _find("START RUN") == null)
	var c_before: int = int(main.save["coins"])
	_press("Collect")
	await _frames()
	_check("collect pays offline coins", expect_off > 0 and int(main.save["coins"]) == c_before + expect_off and main.offline_offer.is_empty(), "%d" % expect_off)
	_check("missions rolled at boot", Missions.list(main.save).size() == 3)
	_check("boot kept permanent base", String(BaseMeta.slot_of(main.save, 7).get("id", "")) == "gun")

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
	_press("Buy slot")
	await _frames()
	_check("buy lab slot", Labs.slots(main.save) == 3)

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
	main.save["labs"]["lvls"]["speed"] = 1

	# ---- RUN -----------------------------------------------------------------
	main.sfx.clear_log()
	_press("START RUN")
	await _frames()
	_check("start run", main.screen == "run" and main.S != null)
	_check("sfx: wave_start clip fires on run start", main.sfx.played("wave_start"))
	var S = main.S
	_check("perm base carried into run", S.id_at(7) == "gun" and S.lvl_at(7) == 2 and bool(S.unlocked[0]))
	_press("SPD")
	await _frames()
	_check("speed pill cycles game speed", absf(S.speed - 1.5) < 0.01 and absf(float(main.save["speed"]) - 1.5) < 0.01)
	_press("SPD")
	await _frames()
	_check("speed pill wraps to 1x", absf(S.speed - 1.0) < 0.01)
	S.spawn_t = 999.0
	S.xp = S.xp_need()
	await _frames(3)
	_check("level-up shows draft cards", S.draft.size() == 3 and (_find("NEW") != null or _find("+1") != null))
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
		_click(TowerState.slot_pos(8))
		await _frames()
		_check("slot tap places building", S.id_at(8) == new_id and S.pending_place == "")
		_check("sfx: run place clip fires", main.sfx.played("place"))
	else:
		_check("draft has a NEW card", false)
	_click(TowerState.slot_pos(7))
	await _frames()
	S.cash = 500.0
	main._rebuild_ui()
	await _frames()
	var lv: int = S.lvl_at(7)
	main.sfx.clear_log()
	_press("Upgrade")
	await _frames()
	_check("cash upgrade button", S.lvl_at(7) == lv + 1)
	_check("sfx: run upgrade clip fires", main.sfx.played("upgrade"))
	_click(TowerState.slot_pos(4))
	await _frames()
	_press("Unlock plot")
	await _frames()
	_check("run unlock button", bool(S.unlocked[4]))
	_click(TowerState.slot_pos(12))
	await _frames()
	_press("Overcharge")
	await _frames()
	_check("core cash upgrade button", S.core_run_lvl == 1)
	# AC-37 polish: the boss-bounty banner renders below the grid, never over a slot.
	main._handle([{"t": "boss_bounty", "coins": 50, "gems": 1, "pos": TowerState.CENTER}])
	var bpop: Dictionary = main.pops[main.pops.size() - 1]
	var bpos: Vector2 = bpop["pos"]
	_check("bounty banner clears the grid", String(bpop["text"]).begins_with("BOUNTY") and bpos.y - 30.0 > TowerState.CENTER.y + 2.5 * TowerState.CELL)

	# ---- REROLL + PERK OVERLAY -----------------------------------------------
	S.xp = S.xp_need()
	await _frames(3)
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
		_click(TowerState.slot_pos(int(S.free_slots()[0])))
		await _frames()
	_check("rerolled draft resolves", S.draft.is_empty() and S.pending_place == "")
	S.perk_pending = 1
	await _frames(3)
	_check("perk overlay shows 3 cards", S.perk_offer.size() == 3 and _find("PERK") != null)
	var pid: String = String(S.perk_offer[0])
	_press("PERK")
	await _frames()
	_check("perk tap takes perk", S.perks_taken.size() == 1 and S.perk_offer.is_empty() and _find("PERK") == null, pid)

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
	_check("second run starts fresh", main.screen == "run" and main.S != S and main.S.wave == 1 and main.S.id_at(8) == "")

	MetaSave.clear()
	if fail_count == 0:
		print("UITEST OK")
		quit(0)
	else:
		print("UITEST FAIL: %d checks failed" % fail_count)
		quit(1)
