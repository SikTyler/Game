extends SceneTree
## Corehold PC interaction self-test — the view<->input twin of selftest.gd.
## Boots Main.tscn headless at 1920x1080 and drives the native desktop view
## with REAL mouse clicks, drags, wheel, keys and pad events, asserting ENGINE
## / SAVE state after every action: main menu + slots, the "while you were
## away" modal, the hub (Play / tier select / modes), Core Bay (select, level,
## drag-install, equip / unequip, presets, filters, level / lock / salvage),
## Crates (open + reveal), the Factory (WP3: palette click + drag place,
## ghost preview, rotate, drag-laid belts, pipette, deconstruct, recipes,
## facilities, land, bank Collect, pan / zoom / WASD, hub buildings), Research, Cards, Missions, Reforge (two-step + tree),
## settings + remapping, records, and the run (draft cards, reroll, banish,
## drag-to-place, Core tracks, specials + aim, targeting, pause, retry,
## abandon -> results). Layout, tooltip, press-mode and focus checks on every
## screen. Prints "UITEST OK" (exit 0) or "UITEST FAIL: <n> checks failed".
## REDESIGN (deliberate rewrite): the permanent base grid, perm-building hotbar,
## info popover and mobile column are gone (Outpost / Core Bay replace them).
## Run: godot --headless --path games/towerdef-pc-0001/ --script res://uitest.gd

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const Labs := preload("res://Labs.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const Outpost := preload("res://Outpost.gd")
const Parts := preload("res://Parts.gd")
const Cores := preload("res://Cores.gd")
const Crates := preload("res://Crates.gd")
const Reforge := preload("res://Reforge.gd")
const Specials := preload("res://Specials.gd")
const PartDB := preload("res://data/PartDB.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const Factory := preload("res://Factory.gd")
const FactoryDB := preload("res://data/FactoryDB.gd")
const Settings := preload("res://Settings.gd")
const Keybinds := preload("res://Keybinds.gd")
const CoreBay := preload("res://ui/CoreBay.gd")
const FactoryView := preload("res://ui/FactoryView.gd")
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
	return FactoryView.cell_rect(main, x, y).get_center()


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
	_press("SLOT 1 PLAY")
	await _frames()
	_check("PC: slot 1 loads to the hub (Play tab)", main.screen == "base" and main.tab == "play" and MetaSave.active == 1)
	# ---- PC-U1 native layout ------------------------------------------------------
	_check("PC-U1: no embedded mobile column (one unscaled Control layer)", main.ui.scale == Vector2.ONE and not ("col_s" in main) and main.get_node_or_null("Sfx") != null)
	_check("PC-U1: overlays ignore the mouse", main.tipbox.mouse_filter == Control.MOUSE_FILTER_IGNORE and main.ui.mouse_filter == Control.MOUSE_FILTER_IGNORE and main.fader.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	main.save = BaseMeta.default_save()
	main.save["coins"] = 50000
	main.save["scrap"] = 2000
	main.save["keys"] = 5
	main.save["core_cores"] = 10
	main.now_override = T0
	main._rebuild_ui()
	await _frames()
	_audit("play")

	# ---- BOOT: AWAY MODAL ------------------------------------------------------
	# WP3 (deliberate): the away pay is the factory's measured rate x time
	# (a legacy Outpost Mill is refunded at boot instead of paying storage).
	var boot_save: Dictionary = main.save.duplicate(true)
	Outpost.place(boot_save, "mill", 4, 4, 0, T0 - 7200 - 120)
	boot_save["factory"] = Factory.default_block()
	Factory.add_starter(boot_save["factory"])
	boot_save["factory"]["t"] = T0 - 7200
	boot_save["last_seen"] = T0 - 7200
	var es: Dictionary = BaseMeta.normalize(boot_save)
	Factory.migrate_outpost(es)
	Factory.away_report(es, T0)
	var ec0: int = int(es["coins"])
	Factory.claim_bank(es)
	var expect_off: int = int(es["coins"]) - ec0
	main.boot(boot_save, T0)
	await _frames()
	_check("away modal shown at boot (only Collect clickable)", not main.offline_offer.is_empty() and _find("Collect") != null and _find("DSTART") == null)
	var c_before: int = int(main.save["coins"])
	_press("Collect")
	await _frames()
	_check("Collect pays the factory's banked coins (measured rate x 2 h)", expect_off > 0 and int(main.save["coins"]) == c_before + expect_off and main.offline_offer.is_empty(), "%d" % expect_off)
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

	await _core_bay()
	await _crates()
	await _outpost()
	await _research_cards_missions()
	await _fb1_home()
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


# ============================================================== CORE BAY
func _core_bay() -> void:
	var s: Dictionary = main.save
	for id in ["f_plating", "f_lightweave", "b_longbore", "b_shortbore", "c_scope", "e_dynamo", "f_bulkhead"]:
		Parts.grant(s, id, "test")
	_key(KEY_K)
	await _frames()
	_check("BAY: K opens the Core Bay", main.tab == "bay")
	_audit("bay")
	_press("BAY CORE foundry")
	await _frames()
	_check("BAY: clicking a locked Core shows it (cannot be activated)", main.bay_core == "foundry" and _find("BAY ACTIVE").disabled)
	_press("BAY CORE bastion")
	await _frames()
	var c0: int = int(s["coins"])
	var lc: Dictionary = Cores.level_cost(1)
	_press("BAY LEVEL")
	await _frames()
	_check("BAY: Level up spends coins and raises the Core level", Cores.level(main.save, "bastion") == 2 and int(main.save["coins"]) == c0 - int(lc["coins"]))
	_key(KEY_U)
	await _frames()
	_check("BAY: U levels the viewed Core", Cores.level(main.save, "bastion") == 3)
	# drag a Frame part from the inventory onto Frame slot 0
	var uid: String = Parts.uid_of(s, "f_plating")
	var cell: Button = null
	for c in _all_buttons():
		if (c as Button).has_meta("uid") and String((c as Button).get_meta("uid")) == uid:
			cell = c
	_check("BAY: inventory shows owned parts", cell != null and _findp("PART ") != null)
	if cell != null:
		await _drag(cell.get_global_rect().get_center(), CoreBay.slot_pos(main, 0))
	_check("BAY: dragging a part onto its slot installs it", String(Parts.preset(main.save, "bastion")[0]) == uid, str(Parts.preset(main.save, "bastion")))
	# wrong slot type is refused
	var bar_uid: String = Parts.uid_of(s, "b_longbore")
	var bcell: Button = null
	for c in _all_buttons():
		if (c as Button).has_meta("uid") and String((c as Button).get_meta("uid")) == bar_uid:
			bcell = c
	if bcell != null:
		await _drag(bcell.get_global_rect().get_center(), CoreBay.slot_pos(main, 0))
	_check("BAY: a Barrel dropped on a Frame slot is refused", String(Parts.preset(main.save, "bastion")[0]) == uid)
	# select + Equip button
	main.bay_part = bar_uid
	main._rebuild_ui()
	await _frames()
	_press("BAY EQUIP")
	await _frames()
	_check("BAY: Equip installs into the open Barrel slot", Parts.preset(main.save, "bastion").has(bar_uid))
	_press("BAY UNEQUIP")
	await _frames()
	_check("BAY: Unequip removes it", not Parts.preset(main.save, "bastion").has(bar_uid))
	# presets
	_press("PRESET 2")
	await _frames()
	_check("BAY: preset tab 2 switches loadouts (empty)", Parts.preset_idx(main.save, "bastion") == 1 and String(Parts.preset(main.save, "bastion")[0]) == "")
	_key(KEY_1)
	await _frames()
	_check("BAY: key 1 returns to loadout 1", Parts.preset_idx(main.save, "bastion") == 0 and String(Parts.preset(main.save, "bastion")[0]) == uid)
	# filters
	_press("FILTER SLOT B")
	await _frames()
	var only_b: bool = true
	var n_parts: int = 0
	for c in _all_buttons():
		if (c as Button).has_meta("uid"):
			n_parts += 1
			if PartDB.slot_of(String(Parts.item(main.save, String((c as Button).get_meta("uid")))["id"])) != "B":
				only_b = false
	_check("BAY: slot filter shows only Barrels", only_b and n_parts == 2, str(n_parts))
	_press("FILTER SLOT ALL")
	await _frames()
	# level / lock / salvage
	main.bay_part = uid
	main._rebuild_ui()
	await _frames()
	var sc0: int = int(main.save["scrap"])
	_press("BAY PART LEVEL")
	await _frames()
	_check("BAY: part Lv up spends Scrap", int(Parts.item(main.save, uid)["lvl"]) == 2 and int(main.save["scrap"]) < sc0)
	var sal_uid: String = Parts.uid_of(s, "f_lightweave")
	main.bay_part = sal_uid
	main._rebuild_ui()
	await _frames()
	_press("BAY LOCK")
	await _frames()
	_check("BAY: Lock protects a part (Salvage disabled)", bool(Parts.item(main.save, sal_uid)["locked"]) and _find("BAY SALVAGE").disabled)
	_press("BAY LOCK")
	await _frames()
	var sc1: int = int(main.save["scrap"])
	_press("BAY SALVAGE")
	await _frames()
	_check("BAY: Salvage turns a part into Scrap", Parts.item(main.save, sal_uid).is_empty() and int(main.save["scrap"]) > sc1)
	# make another Core active once owned
	(main.save["cores"]["owned"] as Array).append("foundry")
	main.bay_core = "foundry"
	main._rebuild_ui()
	await _frames()
	_press("BAY ACTIVE")
	await _frames()
	_check("BAY: Make active switches the run Core", Cores.active(main.save) == "foundry")
	_press("BAY CORE bastion")
	await _frames()
	_press("BAY ACTIVE")
	await _frames()
	_check("BAY: back to Bastion", Cores.active(main.save) == "bastion")
	_motion(CoreBay.slot_pos(main, 0))
	await _frames(3)
	_check("BAY: hovering a slot shows the part tooltip with + and - lines", main.tipbox.visible and main.tip_label.text.contains("\n+") and main.tip_label.text.contains("\n-"), main.tip_label.text)


# ================================================================= CRATES
func _crates() -> void:
	var s: Dictionary = main.save
	_key(KEY_J)
	await _frames()
	_check("CRATE: J opens Crates", main.tab == "crates")
	_audit("crates")
	var n0: int = Parts.items(s).size() + 0
	var stars0: int = 0
	for it in Parts.items(s).values():
		stars0 += int((it as Dictionary)["stars"])
	var c0: int = int(s["coins"])
	var cost: int = Crates.coin_cost(s, "field")
	main.meta_rng.seed = 3
	_press("CRATE FIELD COINS")
	await _frames()
	var stars1: int = 0
	for it in Parts.items(main.save).values():
		stars1 += int((it as Dictionary)["stars"])
	_check("CRATE: Field Crate costs its coin price and yields a part", int(main.save["coins"]) == c0 - cost and (Parts.items(main.save).size() > n0 or stars1 > stars0 or int(main.save["scrap"]) > 0))
	_check("CRATE: the reveal plays from the open events", not main.crate_anim.is_empty() and (main.crate_anim["items"] as Array).size() == 1 and _find("CRATE SKIP") != null)
	_press("CRATE SKIP")
	await _frames()
	_check("CRATE: Skip reveals all (Close shown)", _find("CRATE CLOSE") != null)
	_press("CRATE CLOSE")
	await _frames()
	_check("CRATE: Close clears the stage", main.crate_anim.is_empty())
	var k0: int = int(main.save["keys"])
	_press("CRATE SUPPLY KEYS")
	await _frames()
	_check("CRATE: Supply Crate with a Key opens 2 parts", int(main.save["keys"]) == k0 - 1 and (main.crate_anim["items"] as Array).size() == 2)
	main.crate_anim = {}


# ============================================================ FB1 HOME
## PLAYTEST_FEEDBACK_1 home: the Outpost IS the hub; plaza buildings open the
## meta screens; Play / Missions / Reforge are small buttons; land chunks hide
## their resources; upgrades show before -> after; crate items open the bay;
## double-click equips / unequips / replaces; SVGs rasterise crisp.
func _fb1_home() -> void:
	var s: Dictionary = main.save
	main.set_tab("play")
	await _frames()
	# WP3 (deliberate): the home is the Factory: FCAT / FBUILD palette keys,
	# a 96x64 chunked map, Crate Depot naming, facility levels at the Relay.
	_check("FB1: home is the Factory (build palette + Play/Missions/Reforge buttons, no Core Bay tab)", _find("FCAT logistics") != null and _find("DSTART") != null and _find("DTAB Missions") != null and _find("DTAB Reforge") != null and _find("DTAB Core Bay") == null and _find("DTAB Crates") == null)
	_audit("home")
	_check("FB1/WP3: the factory map is large (>= 96x64 in 24 land chunks)", FactoryDB.W >= 96 and FactoryDB.H >= 64 and FactoryDB.CW * FactoryDB.CH == 24)
	var cat: Button = _find("FCAT logistics")
	_check("FB1: build categories carry icons", cat != null and cat.icon != null and _find("FCAT storage") != null and _find("FCAT storage").icon != null)
	for lm in [["bay", "Core Bay"], ["crates", "Crate"], ["research", "Research"], ["cards", "Card"]]:
		main.set_tab("play")
		await _frames()
		var lr: Rect2 = FactoryView.landmark_rect(main, String(lm[0]))
		_motion(lr.get_center())
		await _frames(3)
		var tip: String = main.tip_label.text
		_click(lr.get_center())
		await _frames()
		_check("FB1: clicking the %s building opens it" % String(lm[1]), main.tab == String(lm[0]) and tip.contains(String(lm[1])), "%s / %s" % [main.tab, tip])
	_press("DTAB Outpost")
	await _frames()
	_check("FB1: Back to Outpost returns home", main.tab == "play")
	# hidden resources in locked land
	var hid := Vector2i(-1, -1)
	var ck: Rect2i = FactoryDB.chunk_rect(10)   # east of the start (chunk 7 is bought in the factory section)
	for yy in range(ck.position.y, ck.end.y):
		for xx in range(ck.position.x, ck.end.x):
			if hid.x < 0 and Factory.deposit_at(Vector2i(xx, yy)) != "":
				hid = Vector2i(xx, yy)
	var htip: String = FactoryView.map_tip(main, FactoryView.cell_rect(main, hid.x, hid.y).get_center())
	_check("FB1: a deposit inside locked land is hidden", hid.x >= 0 and not Factory.is_open(s, hid) and htip.begins_with("Locked land") and not htip.contains("deposit"), htip)
	# facility upgrades show before -> after (Core Relay panel)
	_click(_op_scr(47, 23))
	await _frames()
	var ub: Button = _find("FFAC barracks")
	_check("FB1/WP3: facility upgrade shows before -> after (Barracks LvN -> N+1)", main.op_sel == Factory.uid_at(s, Vector2i(47, 23)) and ub != null and ub.text.contains("->"), str(ub.text if ub != null else ""))
	_check("WP3: the Relay tooltip reports its measured output", FactoryView.entity_tip(s, main.op_sel).contains("coins/min"))
	main.op_sel = ""
	# crate item -> Core Bay focused on it
	s["coins"] = maxi(int(s["coins"]), 100000)
	main.set_tab("crates")
	await _frames()
	main.meta_rng.seed = 11
	_press("CRATE FIELD COINS")
	await _frames()
	_press("CRATE SKIP")
	await _frames()
	var it0: Dictionary = (main.crate_anim.get("items", []) as Array)[0] if not (main.crate_anim.get("items", []) as Array).is_empty() else {}
	var cuid: String = String(it0.get("uid", ""))
	_press("CRATE ITEM 0")
	await _frames()
	_check("FB1: clicking a revealed crate part opens the Core Bay on it", cuid != "" and main.tab == "bay" and main.bay_part == cuid, "%s %s" % [cuid, main.bay_part])
	# double-click equip / unequip / replace
	var core: String = Cores.active(s)
	main.bay_core = core
	for row_k in Parts.N_SLOTS:
		Parts.unequip(s, core, row_k)
	Parts.grant(s, "b_longbore", "test")
	Parts.grant(s, "b_shortbore", "test")
	var u1: String = Parts.uid_of(s, "b_longbore")
	var u2: String = Parts.uid_of(s, "b_shortbore")
	main.bay_filter = {"slot": "B", "rarity": "", "set": ""}
	main.bay_page = 0
	main._rebuild_ui()
	await _frames()
	var dbl: Callable = func(uid: String) -> void:
		for n in 2:
			for c in _all_buttons():
				if (c as Button).has_meta("uid") and String((c as Button).get_meta("uid")) == uid:
					_click((c as Button).get_global_rect().get_center())
					break
			await _frames()
	await dbl.call(u1)
	var at1: int = Parts.preset(s, core).find(u1)
	_check("FB1: double-click equips a part", at1 >= 0, str(Parts.preset(s, core)))
	await dbl.call(u2)
	var row2: Array = Parts.preset(s, core)
	_check("FB1: double-click replaces the equipped part in that slot", at1 >= 0 and String(row2[at1]) == u2 and not row2.has(u1), str(row2))
	await dbl.call(u2)
	_check("FB1: double-click an equipped part unequips it", not Parts.preset(s, core).has(u2), str(Parts.preset(s, core)))
	main.bay_filter = {"slot": "", "rarity": "", "set": ""}
	# crisp SVG raster
	var tx: Texture2D = load("res://art/aegis.svg") as Texture2D
	_check("FB1: SVG art rasterises at >= 256 px (not upscaled blur)", tx != null and tx.get_width() >= 256, str(tx.get_width() if tx != null else 0))
	main.set_tab("play")
	await _frames()


# ================================================================= FACTORY (WP3)
## WP3 (deliberate rewrite): the plot/generator Outpost builder became the
## Factory. Same coverage, factory semantics: palette arm + click place,
## ghost validity, drag-from-palette, Esc, select, R rotate (armed + placed),
## drag-laid belts, Q pipette, X / right-click deconstruct, recipes,
## facilities, land purchase, bank Collect, pan (right drag / left drag on
## empty ground / WASD), wheel zoom, research tech row.
func _outpost() -> void:
	var s: Dictionary = main.save
	s["coins"] = 200000
	_key(KEY_O)
	await _frames()
	_check("OP: O opens the Factory", main.tab == "outpost")
	_audit("factory")
	main.fc_center = Vector2(48.0, 24.0)
	main.fc_zoom = 34.0
	var miners0: int = Factory.count_of(s, "miner")
	var c0: int = int(s["coins"])
	_press("FCAT production")
	await _frames()
	_press("FBUILD miner")
	await _frames()
	_check("OP: palette click arms the building", main.op_arm == "miner")
	_motion(_op_scr(52, 26))
	await _frames(2)
	var gh: Dictionary = main.get_meta("op_ghost", {})
	_check("OP: hover ghost validates the footprint (miner on copper)", gh.has("err") and String(gh["err"]) == "", str(gh))
	_motion(_op_scr(47, 23))
	await _frames(2)
	gh = main.get_meta("op_ghost", {})
	_check("OP: hover over the Core Relay shows the refusal", String(gh.get("err", "")) == "occupied", str(gh))
	_motion(_op_scr(56, 22))
	await _frames(2)
	gh = main.get_meta("op_ghost", {})
	_check("OP: a miner off any deposit is refused", String(gh.get("err", "")) == "no_deposit", str(gh))
	_click(_op_scr(52, 26))
	await _frames()
	var mu: String = Factory.uid_at(main.save, Vector2i(52, 26))
	_check("OP: click on the map places it (coins spent, built at once)", Factory.count_of(main.save, "miner") == miners0 + 1 and int(main.save["coins"]) == c0 - Factory.cost("miner") and mu != "")
	_check("OP: the build stays armed for the next one", main.op_arm == "miner")
	_key(KEY_ESCAPE)
	await _frames()
	_check("OP: Esc disarms", main.op_arm == "")
	# drag a Smelter from the palette onto the map
	var b: Button = _find("FBUILD smelter")
	if b != null:
		await _drag(b.get_global_rect().get_center(), _op_scr(56, 22))
	_check("OP: dragging a Smelter from the palette places it", String(Factory.ent(main.save, Factory.uid_at(main.save, Vector2i(56, 22))).get("id", "")) == "smelter")
	_key(KEY_ESCAPE)
	await _frames()
	# select
	_click(_op_scr(52, 26))
	await _frames()
	_check("OP: clicking a building selects it", main.op_sel == mu)
	_check("OP: the selection panel offers Rotate + Deconstruct", _find("FROTATE") != null and _find("FREMOVE") != null)
	# R rotates the armed piece and a placed one
	_press("FCAT logistics")
	await _frames()
	_press("FBUILD inserter")
	await _frames()
	var r0: int = main.op_rot
	_key(KEY_R)
	await _frames()
	_check("OP: R rotates the armed piece (4 directions)", main.op_rot == (r0 + 1) % 4)
	_key(KEY_ESCAPE)
	await _frames()
	_motion(_op_scr(52, 26))
	await _frames()
	_key(KEY_R)
	await _frames()
	_check("OP: R rotates the placed piece under the cursor", int(Factory.ent(main.save, mu)["rot"]) == 1)
	# drag-to-lay belts
	_press("FBUILD belt")
	await _frames()
	var nb0: int = Factory.count_of(main.save, "belt")
	await _drag(_op_scr(50, 29), _op_scr(55, 29))
	var line_ok: bool = true
	for x in range(50, 56):
		var e: Dictionary = Factory.ent(main.save, Factory.uid_at(main.save, Vector2i(x, 29)))
		line_ok = line_ok and String(e.get("id", "")) == "belt" and int(e.get("rot", -1)) == 0
	_check("OP: dragging lays a straight belt line facing the drag", line_ok and Factory.count_of(main.save, "belt") == nb0 + 6)
	await _drag(_op_scr(57, 25), _op_scr(58, 28))
	var corner: Dictionary = Factory.ent(main.save, Factory.uid_at(main.save, Vector2i(58, 25)))
	_check("OP: an L drag turns the corner (corner belt faces south)", String(corner.get("id", "")) == "belt" and int(corner["rot"]) == 1)
	_key(KEY_ESCAPE)
	await _frames()
	# Q pipette
	_motion(_op_scr(52, 26))
	await _frames()
	_key(KEY_Q)
	await _frames()
	_check("OP: Q copies the piece under the cursor (id + direction)", main.op_arm == "miner" and main.op_rot == 1)
	_key(KEY_ESCAPE)
	await _frames()
	# X / right click deconstruct (full refund)
	var cx: int = int(main.save["coins"])
	_motion(_op_scr(55, 29))
	await _frames()
	_key(KEY_X)
	await _frames()
	_check("OP: X deconstructs the piece under the cursor (refund)", Factory.uid_at(main.save, Vector2i(55, 29)) == "" and int(main.save["coins"]) == cx + Factory.cost("belt"))
	_mouse(_op_scr(54, 29), MOUSE_BUTTON_RIGHT, true)
	_mouse(_op_scr(54, 29), MOUSE_BUTTON_RIGHT, false)
	await _frames()
	_check("OP: a right click deconstructs too", Factory.uid_at(main.save, Vector2i(54, 29)) == "")
	# assembler recipe
	_press("FCAT production")
	await _frames()
	_press("FBUILD assembler")
	await _frames()
	_click(_op_scr(38, 22))
	await _frames()
	_key(KEY_ESCAPE)
	await _frames()
	var au: String = Factory.uid_at(main.save, Vector2i(38, 22))
	_click(_op_scr(39, 23))
	await _frames()
	_check("OP: an Assembler lists its recipes; circuits need research", main.op_sel == au and _find("FREC gear") != null and _find("FREC circuit") != null and _find("FREC circuit").disabled)
	_press("FREC gear")
	await _frames()
	_check("OP: choosing a recipe sets it", String(Factory.ent(main.save, au)["rec"]) == "gear")
	main.op_sel = ""
	# facilities at the Relay
	_click(_op_scr(47, 23))
	await _frames()
	var bl0: int = Factory.fac_level(main.save, "barracks")
	_press("FFAC barracks")
	await _frames()
	_check("OP: a facility upgrade at the Relay raises its level (feeds run mods)", Factory.fac_level(main.save, "barracks") == bl0 + 1 and Outpost.level_of(main.save, "barracks") == bl0 + 1)
	# bank Collect
	(Factory._f(main.save)["bank"] as Dictionary)["coins"] = 500.0
	main._rebuild_ui()
	await _frames()
	var cb: int = int(main.save["coins"])
	_press("FCOLLECT")
	await _frames()
	_check("OP: Collect pays the factory bank", int(main.save["coins"]) == cb + 500 and float(Factory._f(main.save)["bank"]["coins"]) < 1.0)
	# land
	main.op_sel = ""
	main.fc_center = Vector2(30.0, 24.0)
	main._rebuild_ui()
	await _frames()
	_click(_op_scr(26, 24))
	await _frames()
	_check("OP: clicking locked land selects the chunk", main.op_sel == "chunk:7")
	_press("FBUY LAND")
	await _frames()
	_check("OP: buying land opens it and reveals its deposits", (Factory._f(main.save)["chunks"] as Array).has(7) and Factory.deposit_visible(main.save, hid_cell(7)))
	main.fc_center = Vector2(48.0, 24.0)
	# pan + zoom
	var cam0: Vector2 = main.fc_center
	await _drag(_op_scr(60, 22), _op_scr(60, 22) + Vector2(120, 60), MOUSE_BUTTON_RIGHT)
	_check("OP: right-drag pans the map", main.fc_center.distance_to(cam0) > 1.5, str(main.fc_center))
	var cam1: Vector2 = main.fc_center
	await _drag(_op_scr(int(cam1.x) + 4, int(cam1.y) - 6), _op_scr(int(cam1.x) + 4, int(cam1.y) - 6) + Vector2(-150, 0))
	_check("OP: left-drag on empty ground pans too", main.fc_center.x > cam1.x + 2.0, "%s -> %s" % [cam1, main.fc_center])
	var cam2: Vector2 = main.fc_center
	var kd := InputEventKey.new()
	kd.physical_keycode = KEY_D
	kd.keycode = KEY_D
	kd.pressed = true
	Input.parse_input_event(kd)
	await _frames(12)
	kd = kd.duplicate()
	kd.pressed = false
	Input.parse_input_event(kd)
	await _frames()
	_check("OP: WASD pans (D moves the camera east)", main.fc_center.x > cam2.x, "%s -> %s" % [cam2, main.fc_center])
	var z0: float = main.fc_zoom
	_mouse(_op_scr(48, 24), MOUSE_BUTTON_WHEEL_UP, true)
	await _frames()
	_check("OP: wheel zooms the map", main.fc_zoom > z0)
	_mouse(_op_scr(48, 24), MOUSE_BUTTON_WHEEL_DOWN, true)
	_mouse(_op_scr(48, 24), MOUSE_BUTTON_WHEEL_DOWN, true)
	await _frames()
	_check("OP: wheel zooms back out", main.fc_zoom < z0)
	main.fc_center = Vector2(48.0, 24.0)
	main.fc_zoom = 34.0
	# the factory runs live while open (fixed steps)
	var made0: int = int(main.save["coins"])
	Factory._f(main.save)["acc"] = 0.0
	await _frames(30)
	_check("OP: the factory ticks live on its screen (items move, coins arrive)", int(main.save["coins"]) >= made0 and _any_items_on_belts(main.save))
	# factory technology in the Research Lab
	main.set_tab("research")
	await _frames()
	var tb: Button = _find("FTECH electronics")
	_check("OP: the Research Lab lists factory technology", tb != null and not tb.disabled)
	_press("FTECH electronics")
	await _frames()
	_check("OP: researching Electronics unlocks circuits", Factory.has_tech(main.save, "electronics"))
	_audit("research + factory tech")
	main.set_tab("play")
	main.op_sel = ""
	main._rebuild_ui()


func hid_cell(k: int) -> Vector2i:
	var r: Rect2i = FactoryDB.chunk_rect(k)
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			if Factory.deposit_at(Vector2i(xx, yy)) != "":
				return Vector2i(xx, yy)
	return Vector2i(-1, -1)


func _any_items_on_belts(sv: Dictionary) -> bool:
	for k in (Factory._f(sv)["ents"] as Dictionary).keys():
		var e: Dictionary = Factory._f(sv)["ents"][k]
		if e.has("it") and not (e["it"] as Array).is_empty():
			return true
	return false


# ================================================= RESEARCH / CARDS / MISSIONS
func _research_cards_missions() -> void:
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
	_key(KEY_C)
	await _frames()
	_check("CARDS: C opens Cards", main.tab == "cards" and _find("Open Chest") != null)
	_audit("cards")
	var g1: int = int(main.save["coins"])
	main.sfx.clear_log()
	_press("Open Chest")
	await _frames()
	_check("CARDS: Open Chest for coins (sfx card_open)", Cards.owned(main.save).size() == 1 and int(main.save["coins"]) == g1 - Cards.chest_cost() and main.sfx.played("card_open"))
	var cid: String = String(Cards.owned(main.save).keys()[0])
	_press("CARD " + cid)
	await _frames()
	_check("CARDS: click a card equips it", Cards.equipped(main.save).has(cid))
	_press("EQ " + cid)
	await _frames()
	_check("CARDS: click an equipped slot unequips", not Cards.equipped(main.save).has(cid))
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
	_check("RF: Reforge keeps owned parts", Parts.items(main.save).size() > 0)
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
	_check("HORDE P6: F3 toggles the debug overlay", main.dbg_overlay != ov0 and ds.has("bodies") and ds.has("fps") and ds.has("sim_ms") and ds.has("hash_ms") and ds.has("hash_cells"))
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
	_check("RUN: clicking a Core track buys a level", int(S.tracks["dmg"]) == 1 and S.cash < 400.0 - float(cost) + 5.0)
	_key(KEY_2, false, true)
	await _frames()
	_check("RUN: Shift+2 buys the Rate track", int(S.tracks["rate"]) == 1)
	_motion(_find("TRACK Eco").get_global_rect().get_center())
	await _frames(3)
	_check("RUN: hovering a track shows its tooltip", main.tipbox.visible and main.tip_label.text.begins_with("Eco track"), main.tip_label.text)
	_check("FB1: tooltips render a bold header + icon stat lines, no hotkey callouts", main.tip_rich.text.begins_with("[b]") and main.tip_rich.text.contains("[img") and not main.tip_label.text.contains("Shift"), main.tip_rich.text)
	_motion(_cell_scr(TowerState.CORE_SLOT))
	await _frames(3)
	_check("RUN: hovering the Core shows its attack + trait", main.tipbox.visible and main.tip_label.text.contains("Core") and main.tip_label.text.contains("Trait"), main.tip_label.text)
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
	_motion(_cell_scr(TowerState.CORE_SLOT))
	await _frames(2)
	_check("FB1: an invalid cell turns the preview red with a reason", String(main.get_meta("ghost_reason", "")) != "")
	_click(_cell_scr(cell))
	await _frames()
	_check("RUN: click a glowing cell places it", S.id_at(cell) == "gun" and S.pending_place == "")
	_check("sfx: place clip", main.sfx.played("place"))
	# drag a NEW building card onto a cell
	S.grant_draft()
	S.draft[1] = load("res://Draft.gd").card_for("mortar", S._draft_ctx(""))
	main._rebuild_ui()
	await _frames()
	var cb: Button = _findp("DCARD 1")
	var cell2: int = TowerState.CORE_RING[1]
	if cb != null:
		await _drag(cb.get_global_rect().get_center(), _cell_scr(cell2))
	_check("RUN: dragging a draft card onto a cell places it", S.id_at(cell2) == "mortar" and S.draft.is_empty())
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
	for tb in ["play", "bay", "crates", "outpost", "research", "reforge"]:
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
	_check("PC-U5: stick moves the grid cursor once per push", main.sel == TowerState.CORE_SLOT + 1, str(main.sel))
	_pad_axis(JOY_AXIS_LEFT_X, 0.0)
	main.S.pending_place = "gun"
	_pad_button(JOY_BUTTON_A)
	await _frames()
	_check("PC-U5: A places at the cursor", main.S.id_at(TowerState.CORE_SLOT + 1) == "gun")
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
