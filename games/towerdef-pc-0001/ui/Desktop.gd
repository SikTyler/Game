extends RefCounted
## Desktop chrome for Main.gd (REDESIGN_SPEC §5): the top bar, the main menu /
## save-slot picker, modal overlays (pause, settings with key remapping,
## credits, stats / history / achievements, mode select), the boot "while you
## were away" modal, toasts, hover tooltips and the hotkey / controller action
## router. Native 1920x1080 coordinates (re-laid out from m.vw / m.vh). View
## only: actions call the pure modules and replay events through Main.

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const ModifierDB := preload("res://data/ModifierDB.gd")
const AchievementDB := preload("res://data/AchievementDB.gd")
const CreditsDB := preload("res://data/CreditsDB.gd")
const PickDB := preload("res://data/PickDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const Settings := preload("res://Settings.gd")
const Keybinds := preload("res://Keybinds.gd")
const Stats := preload("res://Stats.gd")
const Achievements := preload("res://Achievements.gd")
const Tiers := preload("res://Tiers.gd")
const Labs := preload("res://Labs.gd")
const Cores := preload("res://Cores.gd")
const Outpost := preload("res://Outpost.gd")
const Kit := preload("res://ui/Kit.gd")
const Battle := preload("res://ui/Battle.gd")
const Hub := preload("res://ui/Hub.gd")
const OutpostView := preload("res://ui/OutpostView.gd")
const LootReveal := preload("res://ui/LootReveal.gd")

const OVERLAYS: Array = ["pause", "settings", "credits", "stats", "history", "achievements", "modes", "goal", "loot"]
const SET_TABS: Array = ["video", "audio", "controls", "gameplay"]
const KEYS_PER_PAGE: int = 11

## Joypad axes report "pressed" on every motion past the deadzone: an action
## fires once per crossing (cleared again on its release event).
static var _axis_held: Dictionary = {}


static func hint(m, action: String) -> String:
	return Kit.hint(m, action)


static func modal_rect(m, w: float, h: float) -> Rect2:
	return Rect2(floorf((m.vw - w) * 0.5), floorf((m.vh - h) * 0.5), minf(w, m.vw - 16.0), minf(h, m.vh - 16.0))


## The boot "while you were away" modal grows with the number of resources.
static func offline_rect(m) -> Rect2:
	var n: int = 0
	for k in ["coins", "scrap"]:
		if int(m.offline_offer.get(k, 0)) > 0:
			n += 1
	return modal_rect(m, 760, 300.0 + 66.0 * float(maxi(1, n)))


static func apply_settings(m, s: Dictionary) -> void:
	m.settings = Settings.normalize(s)
	Settings.apply(m.settings, m.get_tree())
	Settings.write(m.settings)
	m._rebuild_ui()


# ===================================================================== build
static func build(m) -> void:
	if m.screen == "menu":
		match String(m.overlay):
			"settings":
				_build_settings(m)
			"credits":
				_build_credits(m)
			_:
				_build_menu(m)
		_focus_first(m)
		return
	if m.overlay in OVERLAYS:
		match String(m.overlay):
			"pause":
				_build_pause(m)
			"settings":
				_build_settings(m)
			"credits":
				_build_credits(m)
			"stats", "history", "achievements":
				_build_records(m)
			"modes":
				_build_modes(m)
			"goal":
				_build_goal(m)
			"loot":
				LootReveal.build(m)
		_focus_first(m)
		return
	if m.screen == "base" and not m.offline_offer.is_empty():
		var r: Rect2 = offline_rect(m)
		Kit.btn(m, "Collect", Rect2(r.position.x + 230, r.end.y - 92, 300, 60), m.claim_offline, "Collect everything the Outpost stored while you were away", true, Kit.GOLD, "Collect", "ui_collect", 24)
		_focus_first(m)
		return
	_build_topbar(m)
	match String(m.screen):
		"base":
			Hub.build(m)
		"run":
			Battle.build(m)
		"results":
			Battle.build_results(m)
	_focus_first(m)


const TOP_BTN_W: float = 150.0


## Right-hand top-bar buttons: [label, tip, callable, key, icon].
static func _topbar_items(m) -> Array:
	var items: Array = []
	if m.screen == "run":
		items.append(["Pause", "Pause the run (engine time freezes)", func() -> void: m.set_overlay("pause"), "HUD Pause", "icon_pause"])
	else:
		items.append(["Menu", "Save slots and quit", m.go_menu, "HUD Menu", "icon_menu"])
	items.append(["Settings", "Video, audio, controls (key remapping) and gameplay", func() -> void: m.set_overlay("settings"), "HUD Settings", "icon_gear"])
	items.append(["Records", "Lifetime stats, run history and achievements", func() -> void: m.set_overlay("stats"), "HUD Stats", "icon_stats"])
	if m.screen == "base":
		items.append(["Missions", "Daily missions and the login streak", func() -> void: m.set_tab("missions"), "DTAB Missions", "tab_missions"])
	return items


## Left edge of the right-hand button cluster (and the run's Speed button).
static func topbar_right_x(m) -> float:
	return m.vw - 8.0 - TOP_BTN_W * float(_topbar_items(m).size()) - (132.0 if m.screen == "run" else 0.0)


static func _build_topbar(m) -> void:
	var x: float = m.vw - 8.0
	for it in _topbar_items(m):
		var a: Array = it
		x -= TOP_BTN_W
		var on: bool = String(a[3]) == "DTAB Missions" and m.tab == "missions"
		Kit.btn(m, String(a[0]), Rect2(x, 8, TOP_BTN_W - 8.0, 40), a[2], String(a[1]), true, Kit.CYAN if on else Kit.NEUTRAL, String(a[3]), String(a[4]), 15)
	if m.screen == "run" and m.S != null:
		var steps: Array = Labs.speed_steps(m.save)
		x -= 132.0
		Kit.btn(m, "Speed %sx" % Battle.speed_str(m.S.speed), Rect2(x, 8, 124, 40), func() -> void: m.cycle_speed(), "Game speed [%s/%s]. Research Game Speed unlocks faster steps." % [hint(m, "speed_down"), hint(m, "speed_up")], steps.size() > 1, Kit.CYAN, "SPD", "icon_speed", 15)


static func _build_menu(m) -> void:
	var cw: float = 440.0
	var x0: float = floorf((m.vw - (cw * 3.0 + 40.0)) * 0.5)
	var y0: float = 330.0
	for n in [1, 2, 3]:
		var slot: int = n
		var sm: Dictionary = MetaSave.slot_summary(slot)
		var x: float = x0 + float(n - 1) * (cw + 20.0)
		var ex: bool = bool(sm.get("exists", false))
		var active: bool = MetaSave.active == slot
		Kit.btn(m, ("Continue" if active else "Load") if ex else "New game", Rect2(x + 20, y0 + 250, cw - 40, 60), func() -> void: m.load_slot(slot), "Play save slot %d" % slot, true, Kit.RUST, "SLOT %d PLAY" % slot, "", 22)
		if ex:
			if m.confirm_del == slot:
				Kit.btn(m, "Confirm delete", Rect2(x + 20, y0 + 322, (cw - 52) * 0.5, 48), func() -> void: m.delete_slot(slot), "Permanently delete slot %d" % slot, true, Kit.ENEMY, "SLOT %d CONFIRM" % slot)
				Kit.btn(m, "Keep", Rect2(x + 32 + (cw - 52) * 0.5, y0 + 322, (cw - 52) * 0.5, 48), func() -> void: m.ask_delete(0), "Cancel the delete", true, Kit.NEUTRAL, "SLOT %d KEEP" % slot)
			else:
				Kit.btn(m, "Delete", Rect2(x + 20, y0 + 322, (cw - 52) * 0.5, 48), func() -> void: m.ask_delete(slot), "Delete slot %d (asks to confirm)" % slot, true, Color("7a3a3a"), "SLOT %d DELETE" % slot)
				Kit.btn(m, "Copy to empty", Rect2(x + 32 + (cw - 52) * 0.5, y0 + 322, (cw - 52) * 0.5, 48), func() -> void: m.copy_slot(slot), "Copy this save into the first empty slot", true, Kit.NEUTRAL, "SLOT %d COPY" % slot)
	var by: float = y0 + 430.0
	var labels: Array = [["Settings", "Video, audio, controls (key remapping) and gameplay", func() -> void: m.set_overlay("settings")],
		["Credits", "Open-source credits", func() -> void: m.set_overlay("credits")],
		["Quit", "Quit to desktop", func() -> void: m.get_tree().quit()]]
	for k in labels.size():
		var l: Array = labels[k]
		Kit.btn(m, String(l[0]), Rect2(m.vw * 0.5 - 160, by + k * 62.0, 320, 52), l[2], String(l[1]), true, Kit.NEUTRAL, "MENU " + String(l[0]), "", 20)


static func _focus_first(m) -> void:
	if String(m.last_device) != "pad":
		return
	for c in m.ui.get_children():
		if c is Button and not (c as Button).disabled and not (c as Button).is_queued_for_deletion():
			var b: Button = c
			(func() -> void:
				if is_instance_valid(b) and b.is_inside_tree() and not b.is_queued_for_deletion():
					b.grab_focus()).call_deferred()
			return


static func _build_pause(m) -> void:
	var r: Rect2 = modal_rect(m, 520, 470)
	var x: float = r.position.x + 60.0
	var w: float = r.size.x - 120.0
	Kit.btn(m, "Resume  [%s]" % hint(m, "pause"), Rect2(x, r.position.y + 110, w, 64), func() -> void: m.set_overlay(""), "Back to the run", true, Kit.GEM, "Resume", "", 24)
	Kit.btn(m, "Settings", Rect2(x, r.position.y + 190, w, 56), func() -> void: m.set_overlay("settings"), "Video, audio, controls and gameplay", true, Kit.NEUTRAL, "Options", "icon_gear", 20)
	Kit.btn(m, "Records", Rect2(x, r.position.y + 258, w, 56), func() -> void: m.set_overlay("stats"), "Stats, history and achievements", true, Kit.NEUTRAL, "PAUSE Records", "icon_stats", 20)
	Kit.btn(m, "Abandon run (bank coins)", Rect2(x, r.position.y + 350, w, 56), m.abandon_run, "End the run now; coins earned so far are banked", true, Kit.ENEMY, "Abandon", "", 20)


## MASS_HORDE §D7: the first run's soft goal (wave 20, the second boss).
static func _build_goal(m) -> void:
	var r: Rect2 = modal_rect(m, 640, 420)
	var x: float = r.position.x + 60.0
	var w: float = r.size.x - 120.0
	Kit.btn(m, "Keep going  (the tide builds to wave 50)", Rect2(x, r.position.y + 250, w, 60), func() -> void: m.set_overlay(""), "Continue this run: waves 21-50 grow toward 10,000 enemies at once", true, Kit.GEM, "GOAL Continue", "", 20)
	Kit.btn(m, "Bank coins and end the run", Rect2(x, r.position.y + 324, w, 56), m.abandon_run, "End the run now; coins earned so far are banked", true, Kit.GOLD, "GOAL Bank", "", 20)


static func _build_credits(m) -> void:
	var r: Rect2 = modal_rect(m, 900, 800)
	var sc := ScrollContainer.new()
	sc.position = r.position + Vector2(40, 100)
	sc.size = Vector2(r.size.x - 80, r.size.y - 200)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.set_meta("key", "CREDITS_SCROLL")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(r.size.x - 110, 0)
	box.add_theme_constant_override("separation", 6)
	for ln in CreditsDB.LINES:
		var la: Array = ln
		var lb := Label.new()
		lb.text = String(la[0])
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size = Vector2(r.size.x - 110, 0)
		var hd: bool = String(la[1]) == "h"
		lb.add_theme_font_size_override("font_size", 22 if hd else 17)
		lb.add_theme_color_override("font_color", Kit.GOLD if hd else Kit.TEXT)
		box.add_child(lb)
	sc.add_child(box)
	m.ui.add_child(sc)
	Kit.btn(m, "Back [%s]" % hint(m, "cancel"), Rect2(r.end.x - 240, r.end.y - 76, 200, 52), func() -> void: m.set_overlay(""), "Close the credits", true, Kit.RUST, "Back")


static func _build_settings(m) -> void:
	var r: Rect2 = modal_rect(m, 1100, 820)
	var tw: float = (r.size.x - 40.0 - 18.0) / 4.0
	for k in SET_TABS.size():
		var id: String = SET_TABS[k]
		Kit.btn(m, id.capitalize(), Rect2(r.position.x + 20 + k * (tw + 6.0), r.position.y + 70, tw, 50), func() -> void: m.set_tab_id = id; m.remap_action = ""; m._rebuild_ui(), "%s settings" % id.capitalize(), true, Kit.RUST if m.set_tab_id == id else Kit.NEUTRAL, "SET TAB " + id.capitalize())
	var s: Dictionary = Settings.normalize(m.settings)
	var x: float = r.position.x + 40.0
	var y: float = r.position.y + 150.0
	var rows: Array = []
	match String(m.set_tab_id):
		"video":
			var v: Dictionary = s["video"]
			rows = [
				["Display mode", String(v["mode"]).capitalize(), "video", "mode", Settings.MODES, "Windowed, borderless fullscreen or exclusive fullscreen"],
				["Resolution", "%dx%d" % [(v["resolution"] as Vector2i).x, (v["resolution"] as Vector2i).y], "video", "resolution", Settings.resolutions_for(DisplayServer.screen_get_size()), "Window size (windowed mode)"],
				["VSync", String(v["vsync"]).capitalize(), "video", "vsync", Settings.VSYNC, "Vertical sync"],
				["FPS cap", "Unlimited" if int(v["fps_cap"]) == 0 else str(int(v["fps_cap"])), "video", "fps_cap", Settings.FPS_CAPS, "Frame-rate limit"],
				["UI scale", "%d%%" % int(round(float(v["ui_scale"]) * 100.0)), "video", "ui_scale", [0.75, 1.0, 1.25, 1.5], "Scale every interface element"],
				["Screen shake", "On" if bool(v["shake"]) else "Off", "video", "shake", [true, false], "Camera shake on hits"],
				["Damage numbers", String(v["dmg_numbers"]).capitalize(), "video", "dmg_numbers", Settings.DMG_NUMBERS, "Floating damage numbers"],
				["Gore", String(v["gore"]).capitalize(), "video", "gore", Settings.GORE, "Blood bursts and corpses on the ground"],
			]
		"audio":
			var a: Dictionary = s["audio"]
			for bus in Settings.BUSES:
				rows.append([String(bus) + " volume", "%d%%" % int(round(float(a[bus]) * 100.0)), "audio", String(bus), [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], "Volume of the %s bus" % String(bus)])
			rows.append(["Mute all", "On" if bool(a["mute"]) else "Off", "audio", "mute", [false, true], "Mute every bus"])
			rows.append(["Mute when unfocused", "On" if bool(a["mute_unfocused"]) else "Off", "audio", "mute_unfocused", [true, false], "Silence the game in the background"])
		"gameplay":
			var g: Dictionary = s["gameplay"]
			rows = [
				["Pause on draft", "On" if bool(g["pause_on_draft"]) else "Off", "gameplay", "pause_on_draft", [true, false], "Freeze time while a draft is open"],
				["Pause on focus loss", "On" if bool(g["pause_on_focus_loss"]) else "Off", "gameplay", "pause_on_focus_loss", [true, false], "Pause when the window loses focus"],
				["Confirm demolish", "On" if bool(g["confirm_sell"]) else "Off", "gameplay", "confirm_sell", [false, true], "Ask before demolishing Outpost buildings"],
				["Default speed", "%sx" % str(g["default_speed"]), "gameplay", "default_speed", [1.0, 1.5, 2.0, 3.0, 4.0], "Speed a run starts at"],
				["Colorblind", String(g["colorblind"]).capitalize(), "gameplay", "colorblind", Settings.COLORBLIND, "Colorblind palette"],
				["Tooltip delay", "%.1fs" % float((s["controls"] as Dictionary)["tooltip_delay"]), "controls", "tooltip_delay", [0.0, 0.2, 0.4, 0.8], "How long to hover before a tooltip shows"],
			]
		"controls":
			_build_keymap(m, r, s)
	for k in rows.size():
		var rw: Array = rows[k]
		var sec: String = rw[2]
		var key: String = rw[3]
		var opts: Array = rw[4]
		Kit.btn(m, "%s:  %s" % [String(rw[0]), String(rw[1])], Rect2(x, y + k * 62.0, r.size.x - 80.0, 52), func() -> void: cycle_setting(m, sec, key, opts), String(rw[5]) + " (click to change)", true, Kit.NEUTRAL, "SET " + String(rw[0]))
	Kit.btn(m, "Credits", Rect2(r.end.x - 180, r.position.y + 14, 160, 44), func() -> void: m.set_overlay("credits"), "Open-source credits", true, Kit.NEUTRAL, "Credits")
	Kit.btn(m, "Close [%s]" % hint(m, "cancel"), Rect2(r.end.x - 220, r.end.y - 70, 200, 52), func() -> void: m.set_overlay("pause" if m.screen == "run" else ""), "Close settings (changes are saved)", true, Kit.RUST, "SET CLOSE")


static func cycle_setting(m, sec: String, key: String, opts: Array) -> void:
	var s: Dictionary = Settings.normalize(m.settings)
	var sd: Dictionary = s[sec]
	var cur: Variant = sd[key]
	var idx: int = -1
	for k in opts.size():
		if typeof(opts[k]) == typeof(cur) and opts[k] == cur:
			idx = k
		elif (typeof(cur) == TYPE_FLOAT or typeof(cur) == TYPE_INT) and (typeof(opts[k]) == TYPE_FLOAT or typeof(opts[k]) == TYPE_INT) and absf(float(opts[k]) - float(cur)) < 0.001:
			idx = k
	sd[key] = opts[(idx + 1) % opts.size()]
	apply_settings(m, s)


static func _build_keymap(m, r: Rect2, s: Dictionary) -> void:
	var acts: Array = Keybinds.actions()
	var pages: int = int(ceil(float(acts.size()) / float(KEYS_PER_PAGE)))
	m.keymap_page = clampi(m.keymap_page, 0, pages - 1)
	var x: float = r.position.x + 40.0
	var y: float = r.position.y + 150.0
	var start: int = m.keymap_page * KEYS_PER_PAGE
	for k in range(start, mini(acts.size(), start + KEYS_PER_PAGE)):
		var a: String = acts[k]
		var rw: int = k - start
		var kb: String = Keybinds.hint(a, false)
		var pd: String = Keybinds.hint(a, true)
		var cap: bool = m.remap_action == a
		Kit.btn(m, ("Press a key... (Esc cancels)" if cap else (kb if kb != "" else "—")), Rect2(x + 420, y + rw * 50.0, 300, 44), func() -> void: m.remap_action = a; m._rebuild_ui(), "Rebind %s (keyboard / mouse / pad)" % String(Keybinds.LABELS.get(a, a)), true, Kit.GOLD if cap else Kit.NEUTRAL, "REMAP " + a)
		Kit.btn(m, pd if pd != "" else "—", Rect2(x + 740, y + rw * 50.0, 160, 44), func() -> void: m.remap_action = a; m._rebuild_ui(), "Controller binding for %s (press a pad button)" % String(Keybinds.LABELS.get(a, a)), true, Kit.EDGE, "PAD " + a)
		Kit.btn(m, "Reset", Rect2(x + 920, y + rw * 50.0, 100, 44), func() -> void: Keybinds.reset_action(a); save_keys(m), "Restore the default for this action", true, Kit.EDGE, "RESET " + a)
	var py: float = r.end.y - 70.0
	Kit.btn(m, "< Prev", Rect2(r.position.x + 20, py, 120, 52), func() -> void: m.keymap_page -= 1; m._rebuild_ui(), "Previous page of actions", m.keymap_page > 0, Kit.NEUTRAL, "KEYS PREV")
	Kit.btn(m, "Next >", Rect2(r.position.x + 148, py, 120, 52), func() -> void: m.keymap_page += 1; m._rebuild_ui(), "Next page of actions", m.keymap_page < pages - 1, Kit.NEUTRAL, "KEYS NEXT")
	Kit.btn(m, "Reset all", Rect2(r.position.x + 276, py, 130, 52), func() -> void: Keybinds.reset_all(); save_keys(m), "Restore every default binding", true, Kit.ENEMY, "KEYS RESET ALL")
	var c: Dictionary = s["controls"]
	Kit.btn(m, "Pad: %s" % String(c["glyphs"]).capitalize(), Rect2(r.position.x + 414, py, 210, 52), func() -> void: cycle_setting(m, "controls", "glyphs", Settings.GLYPHS), "Controller button art style", true, Kit.NEUTRAL, "SET Glyphs")


static func save_keys(m) -> void:
	var s: Dictionary = Settings.normalize(m.settings)
	Settings.capture_keybinds(s)
	m.settings = s
	Settings.write(s)
	m._rebuild_ui()


## Settings > Controls remap capture (called from Main._input while armed).
static func capture_remap(m, event: InputEvent) -> void:
	var ev: InputEvent = null
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE or (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			m.remap_action = ""
			m.get_viewport().set_input_as_handled()
			m._rebuild_ui()
			return
		var k: InputEventKey = event
		var nk := InputEventKey.new()
		nk.physical_keycode = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		nk.keycode = k.keycode if k.keycode != KEY_NONE else k.physical_keycode
		ev = nk
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		var nm := InputEventMouseButton.new()
		nm.button_index = (event as InputEventMouseButton).button_index
		ev = nm
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var nj := InputEventJoypadButton.new()
		nj.button_index = (event as InputEventJoypadButton).button_index
		ev = nj
	if ev == null:
		return
	var a: String = m.remap_action
	m.remap_action = ""
	var other: String = Keybinds.rebind(a, 0, ev)
	m.menu_msg = "Swapped with %s" % String(Keybinds.LABELS.get(other, other)) if other != "" else ""
	m.get_viewport().set_input_as_handled()
	save_keys(m)


static func _build_records(m) -> void:
	var r: Rect2 = modal_rect(m, 1240, 860)
	var tabs: Array = [["stats", "Stats"], ["history", "History"], ["achievements", "Achievements"]]
	for k in tabs.size():
		var tb: Array = tabs[k]
		var id: String = tb[0]
		Kit.btn(m, String(tb[1]), Rect2(r.position.x + 20 + k * 206.0, r.position.y + 70, 200, 50), func() -> void: m.set_overlay(id), "Show %s" % String(tb[1]), true, Kit.RUST if m.overlay == id else Kit.NEUTRAL, "REC " + String(tb[1]))
	if m.overlay == "history":
		var h: Array = m.save.get("history", [])
		var n: int = mini(12, h.size())
		var _n: int = n   # run history is read-only (seeds are never replayable)
	Kit.btn(m, "Close [%s]" % hint(m, "cancel"), Rect2(r.end.x - 220, r.end.y - 70, 200, 52), func() -> void: m.set_overlay("pause" if m.screen == "run" else ""), "Close", true, Kit.RUST, "REC CLOSE")


static func _build_modes(m) -> void:
	var r: Rect2 = modal_rect(m, 1100, 820)
	var x: float = r.position.x + 40.0
	var y: float = r.position.y + 120.0
	var mode: String = String(m.run_opts.get("mode", "normal"))
	var eu: bool = BaseMeta.endless_unlocked(m.save)
	Kit.btn(m, "Normal", Rect2(x, y, 300, 56), func() -> void: m.run_opts["mode"] = "normal"; m._rebuild_ui(), "Standard run: tier progression counts", true, Kit.RUST if mode == "normal" else Kit.NEUTRAL, "MODE Normal")
	Kit.btn(m, "Endless" if eu else "Endless (best wave 50)", Rect2(x + 320, y, 360, 56), func() -> void: m.run_opts["mode"] = "endless"; m._rebuild_ui(), "No wave cap; mutation pick every 25 waves; coins x0.9" + ("" if eu else ". Unlocks at best wave 50."), eu, Kit.MAG if mode == "endless" else Kit.NEUTRAL, "MODE Endless", "icon_endless")
	var mods: Array = m.run_opts.get("modifiers", [])
	for k in ModifierDB.IDS.size():
		var id: String = ModifierDB.IDS[k]
		var d: Dictionary = ModifierDB.get_def(id)
		var on: bool = mods.has(id)
		Kit.btn(m, "%s %s  +%d%%" % ["[x]" if on else "[ ]", String(d["name"]), int(round(float(d["coin"]) * 100.0))], Rect2(x + (k % 3) * 345.0, y + 120 + (k / 3) * 70.0, 330, 56), func() -> void: toggle_mod(m, id), String(d["desc"]) + " — coin reward +%d%%" % int(round(float(d["coin"]) * 100.0)), true, Kit.ENEMY if on else Kit.NEUTRAL, "MOD " + String(d["name"]), "icon_mod")
	Kit.btn(m, "Start run", Rect2(r.end.x - 440, r.end.y - 70, 200, 52), func() -> void: m.start_run(), "Start with this mode and modifiers", Tiers.is_unlocked(m.save, m.view_tier), Kit.RUST, "MODES START")
	Kit.btn(m, "Close [%s]" % hint(m, "cancel"), Rect2(r.end.x - 220, r.end.y - 70, 200, 52), func() -> void: m.set_overlay(""), "Keep these choices and close", true, Kit.NEUTRAL, "MODES CLOSE")


static func toggle_mod(m, id: String) -> void:
	var mods: Array = (m.run_opts.get("modifiers", []) as Array).duplicate()
	if mods.has(id):
		mods.erase(id)
	else:
		mods.append(id)
	m.run_opts["modifiers"] = ModifierDB.clean(mods)
	m._rebuild_ui()


# =================================================================== actions
static func _pressed(m, event: InputEvent, action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	if event is InputEventJoypadMotion:
		if event.is_action_released(action):
			_axis_held.erase(action)
			return false
		if event.is_action_pressed(action):
			if _axis_held.has(action):
				return false
			_axis_held[action] = true
			return true
		return false
	return event.is_action_pressed(action, false, true)


## Hotkeys / controller (Main._unhandled_input). Returns true when consumed.
static func handle_action(m, event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch:
		return false
	if _pressed(m, event, "fullscreen"):
		apply_settings(m, Settings.toggle_fullscreen(m.settings))
		return true
	if _pressed(m, event, "retry") and m.screen == "results":
		m.start_run()   # a fresh, randomly seeded run (no seed replay)
		return true
	if _pressed(m, event, "cancel"):
		_cancel(m)
		return true
	if m.screen == "menu" or m.overlay in ["settings", "stats", "history", "achievements", "modes", "credits"]:
		if m.overlay in ["stats", "history", "achievements"] and _pressed(m, event, "tab_stats"):
			m.set_overlay("pause" if m.screen == "run" else "")
			return true
		return false
	if _pressed(m, event, "pause") and m.screen == "run":
		m.set_overlay("" if m.overlay == "pause" else "pause")
		return true
	if m.overlay == "pause":
		return false
	if _pressed(m, event, "tab_stats"):
		m.set_overlay("stats")
		return true
	if m.screen == "run" and m.S != null:
		return _run_action(m, event)
	if m.screen == "base" and m.offline_offer.is_empty():
		return _hub_action(m, event)
	return false


static func _run_action(m, event: InputEvent) -> bool:
	var S = m.S
	for k in 4:
		if _pressed(m, event, "hotbar_%d" % (k + 1)):
			m.cast(k)
			return true
		if _pressed(m, event, "ability_%d" % (k + 1)):
			_offer_pick(m, k)
			return true
	for k in TowerState.TRACK_IDS.size():
		if _pressed(m, event, "track_%d" % (k + 1)):
			m.buy_track(String(TowerState.TRACK_IDS[k]))
			return true
	if _pressed(m, event, "rotate"):
		m.rotate_weapon(1)
		return true
	if _pressed(m, event, "reroll"):
		m.reroll()
		return true
	if _pressed(m, event, "banish"):
		m.toggle_banish()
		return true
	if _pressed(m, event, "upgrade"):
		m.buy_track("dmg")
		return true
	if _pressed(m, event, "speed_up"):
		m.cycle_speed(1)
		return true
	if _pressed(m, event, "speed_down"):
		m.cycle_speed(-1)
		return true
	for d in [["cursor_up", -TowerState.SIDE], ["cursor_down", TowerState.SIDE], ["cursor_left", -1], ["cursor_right", 1]]:
		if _pressed(m, event, String(d[0])):
			move_cursor(m, int(d[1]))
			return true
	if _pressed(m, event, "confirm"):
		if (S.pending_place != "" or S.pending_upgrade != "") and m.sel >= 0:
			m.place_at(m.sel)
		elif not S.draft.is_empty():
			m.pick_card(0)
		return true
	return false


## Draft / perk / mutation offers share the pick keys (Q W E R).
static func _offer_pick(m, k: int) -> void:
	var S = m.S
	if S.mutation_offer.size() > k:
		m._handle(S.choose_mutation(k))
	elif S.perk_offer.size() > k:
		m._handle(S.choose_perk(k))
	elif S.draft.size() > k:
		m.pick_card(k)
		return
	m._rebuild_ui()


static func _hub_action(m, event: InputEvent) -> bool:
	if _pressed(m, event, "confirm") and m.tab == "play" and m.op_arm == "" and m.op_sel == "" and String(m.last_device) != "pad":
		m.start_run()
		return true
	if Hub.is_home(m.tab) and OutpostView.action(m, event):
		return true
	for t in Hub.TAB_KEYS:
		if _pressed(m, event, String(t[0])):
			m.set_tab(String(t[1]))
			return true
	return false


static func _cancel(m) -> void:
	if m.remap_action != "":
		m.remap_action = ""
		m._rebuild_ui()
	elif m.overlay != "":
		m.set_overlay("pause" if m.screen == "run" and m.overlay != "pause" else "")
	elif m.screen == "run" and m.S != null:
		if m.aim_special >= 0 or m.banish_mode or m.drag_card >= 0:
			m.aim_special = -1
			m.banish_mode = false
			m.drag_card = -1
			m._rebuild_ui()
		elif m.S.pending_place != "":
			m._handle(m.S.cancel_place())
			m._rebuild_ui()
		elif m.S.pending_upgrade != "":
			m._handle(m.S.cancel_upgrade())
			m._rebuild_ui()
		elif m.sel >= 0:
			m.sel = -1
			m._rebuild_ui()
		else:
			m.set_overlay("pause")
	elif m.screen == "base":
		if Hub.is_home(m.tab) and (m.op_arm != "" or m.op_moving or m.op_sel != ""):
			OutpostView.cancel(m)
		elif not Hub.is_home(m.tab):
			m.set_tab("play")
		else:
			m.go_menu()
	elif m.screen == "results":
		m.go_base()


static func move_cursor(m, d: int) -> void:
	var i: int = m.sel
	if i < 0:
		m.sel = TowerState.CORE_SLOT
	else:
		# V2 P3b: step off the current footprint (the 3x3 Core, a 2x2 building)
		# in one push; landing on a building selects its anchor.
		var S = m.S
		var own: int = S.owner_at(i) if S != null else -1
		var r: int = i / TowerState.SIDE
		var c: int = i % TowerState.SIDE
		var cur: int = i
		for _k in TowerState.SIDE:
			var r2: int = r
			var c2: int = c
			if absi(d) == 1:
				c2 = clampi(c + d, 0, TowerState.SIDE - 1)
			else:
				r2 = clampi(r + d / TowerState.SIDE, 0, TowerState.SIDE - 1)
			if r2 == r and c2 == c:
				break
			r = r2
			c = c2
			cur = r * TowerState.SIDE + c
			if own < 0 or S == null or S.owner_at(cur) != own:
				break
		var o2: int = S.owner_at(cur) if S != null else -1
		m.sel = o2 if o2 >= 0 else cur
	m._rebuild_ui()


# ================================================================ tooltips
static func update_tip(m, delta: float) -> void:
	var t: String = tip_at(m, m.mouse_pos)
	if t != m.tip_text:
		m.tip_text = t
		m.tip_t = 0.0
	else:
		m.tip_t += delta
	var delay: float = float((Settings.normalize(m.settings)["controls"] as Dictionary)["tooltip_delay"])
	var show: bool = t != "" and m.tip_t >= delay and m.drag_card < 0 and not m.op_drag and not m.op_pan
	m.tipbox.visible = show
	if show:
		if m.tip_label.text != t:
			m.tip_label.text = t
			m.tip_rich.text = Kit.tip_bbcode(t)
		m.tipbox.reset_size()
		var sz: Vector2 = m.tipbox.get_combined_minimum_size()
		var p: Vector2 = m.mouse_pos + Vector2(18, 22)
		if p.x + sz.x > m.vw - 6.0:
			p.x = m.mouse_pos.x - sz.x - 12.0
		if p.y + sz.y > m.vh - 6.0:
			p.y = m.mouse_pos.y - sz.y - 12.0
		m.tipbox.position = p


static func tip_at(m, p: Vector2) -> String:
	if p.x < 0.0:
		return ""
	var kids: Array = (m.ui as Control).get_children()
	for k in range(kids.size() - 1, -1, -1):
		var c: Variant = kids[k]
		if c is Control and (c as Control).visible and not (c as Control).is_queued_for_deletion() and (c as Control).tooltip_text != "" and (c as Control).get_global_rect().has_point(p):
			return (c as Control).tooltip_text
	if m.overlay != "" or m.screen == "menu":
		return ""
	if m.screen == "run" and m.field_rect().has_point(p):
		var w: String = Battle.world_tip(m, p)
		if w != "":
			return w
	if m.screen == "base" and Hub.is_home(m.tab) and OutpostView.map_rect(m).has_point(p):
		var o: String = OutpostView.map_tip(m, p)
		if o != "":
			return o
	for st in m.stat_tips:
		var a: Array = st
		if (a[0] as Rect2).has_point(p):
			return String(a[1])
	return ""


# ===================================================================== draw
static func draw_topbar(m) -> void:
	var r := Rect2(0, 0, m.vw, m.TOP_H)
	m.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]), PackedColorArray([Kit.BG, Kit.BG, Kit.BG2, Kit.BG2]))
	# glowing cyan edge that fades out toward both ends
	var y: float = m.TOP_H - 1.0
	var mid := Color(Kit.CYAN, 0.7)
	var clear := Color(Kit.CYAN, 0.0)
	m.draw_polygon(PackedVector2Array([Vector2(0, y - 1), Vector2(m.vw * 0.5, y - 1), Vector2(m.vw * 0.5, y + 1), Vector2(0, y + 1)]), PackedColorArray([clear, mid, mid, clear]))
	m.draw_polygon(PackedVector2Array([Vector2(m.vw * 0.5, y - 1), Vector2(m.vw, y - 1), Vector2(m.vw, y + 1), Vector2(m.vw * 0.5, y + 1)]), PackedColorArray([mid, clear, clear, mid]))
	Kit.icon(m, "core_bastion", Rect2(12, 8, 40, 40))
	Kit.th(m, "COREHOLD", Vector2(59, 37), 24, Kit.CYAN, HORIZONTAL_ALIGNMENT_LEFT, 150.0)
	var x: float = 210.0
	var rl: Dictionary = m.rolls
	var cur: Array = [
		["cur_coin", "coins", Kit.GOLD, "Coins — Core levels, the Outpost, research and forging (live during a run)", 134.0, true],
		["cur_scrap", "scrap", Kit.SCRAP, "Scrap — the Forge's material: reroll, lock and upgrade gear (drops, salvage, Scrap Refinery)", 116.0, true],
		["cur_shard", "shards", Kit.SHARD, "Reforge Shards — spend on the permanent Reforge tree", 96.0, false],
	]
	var compact: bool = m.vw < 1500.0
	for c in cur:
		var a: Array = c
		var w: float = float(a[4]) * (0.85 if compact else 1.0)
		var ro: Variant = rl.get(String(a[1]))
		var v: float = float(m.save.get(String(a[1]), 0)) if ro == null else (ro as RefCounted).call("value")
		var sc: float = 1.0 if ro == null else float((ro as RefCounted).call("scale"))
		var txt: String = Kit.fmt(v) if bool(a[5]) else str(int(round(v)))
		Kit.chip(m, String(a[0]), txt, Vector2(x, 38), a[2], String(a[3]), w, sc)
		x += w + 8.0
	# centre: run wave / tier, or hub tier / best
	var right_x: float = topbar_right_x(m) - 16.0
	var cx: float = (x + right_x) * 0.5
	var cw: float = maxf(120.0, right_x - x - 20.0)
	var s: Dictionary = m.save
	if (m.screen == "run" or m.screen == "results") and m.S != null:
		var S = m.S
		var mode: String = "" if S.mode == "normal" else "  ·  " + String(S.mode).capitalize()
		Kit.th(m, "WAVE %d" % int(S.wave), Vector2(cx - 90, 38), 26, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 160.0)
		var bw: float = minf(200.0, cw * 0.4)
		Kit.bar_glow(m, Rect2(cx - 70, 15, bw, 7), float(S.wave_t) / maxf(0.01, float(S.wave_time)), Kit.CYAN)
		Kit.t(m, "Tier %d%s  ·  %s" % [int(S.tier), mode, Kit.dur(int(S.time_alive))], Vector2(cx - 70, 44), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw * 0.5)
		m.stat_tips.append([Rect2(cx - cw * 0.5, 4, cw, 50), "Wave %d — the bar shows the time to the next wave. Tier %d." % [int(S.wave), int(S.tier)]])
	else:
		Kit.th(m, "TIER %d  ·  BEST WAVE %d" % [int(m.view_tier), int(s["best_wave"])], Vector2(cx, 36), 17, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, cw)
	if m.screen == "base" and m.overlay == "" and m.offline_offer.is_empty() and Hub.badge(m, "missions"):
		badge_dot_top(m)


## Missions badge on its top-bar button (the right-most item in the hub).
static func badge_dot_top(m) -> void:
	var p := Vector2(m.vw - 8.0 - TOP_BTN_W * float(_topbar_items(m).size()) + TOP_BTN_W - 18.0, 14.0)
	Hub.badge_dot(m, p)


static func draw_toast(m) -> void:
	if m.toast_t <= 0.0 or m.toast_text == "" or m.screen == "menu":
		return
	var a: float = clampf(m.toast_t * 3.0, 0.0, 1.0)
	# V2: hub toasts sit bottom-centre (clear of the nav and panel headers);
	# in a run they sit at the top of the field, clear of the hotbar.
	var w: float = 460.0
	var y: float = m.vh - 112.0 if m.screen == "base" else m.TOP_H + 12.0
	var r := Rect2(floorf((m.vw - w) * 0.5), y, w, 42)
	Kit.panel_glow(m, r, Color(Kit.GOLD, a), Color(Kit.BG2, 0.96 * a), 0.9 * a)
	Kit.t(m, m.toast_text, Vector2(r.get_center().x, y + 26), 16, Color(Kit.TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, w - 20.0)


static func draw_menu(m) -> void:
	var c: Vector2 = Vector2(m.vw * 0.5, 0)
	for k in 6:
		var a: float = m.t_anim * 0.2 + float(k) * TAU / 6.0
		m.draw_arc(Vector2(c.x, 180), 120.0 + 24.0 * float(k), a, a + 1.2, 24, Color(Kit.RUST, 0.08 + 0.02 * float(k)), 3.0)
	Kit.glow(m, Vector2(c.x, 156), 220.0, Kit.CYAN, 0.2 + 0.05 * sin(m.t_anim * 1.5))
	Kit.icon(m, "core_bastion", Rect2(c.x - 64, 92, 128, 128))
	Kit.big_number(m, "COREHOLD", Vector2(c.x, 280), 68, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 900.0)
	Kit.t(m, "PC EDITION  ·  choose a save slot", Vector2(c.x, 314), 20, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, 900.0)
	var cw: float = 440.0
	var x0: float = floorf((m.vw - (cw * 3.0 + 40.0)) * 0.5)
	var y0: float = 330.0
	for n in [1, 2, 3]:
		var sm: Dictionary = MetaSave.slot_summary(n)
		var x: float = x0 + float(n - 1) * (cw + 20.0)
		var active: bool = MetaSave.active == n
		Kit.panel(m, Rect2(x, y0, cw, 390), Kit.RUST if active else Kit.EDGE, Kit.PANEL)
		Kit.icon(m, "icon_save", Rect2(x + 20, y0 + 22, 44, 44))
		Kit.t(m, "SLOT %d%s" % [n, "  (active)" if active else ""], Vector2(x + 76, y0 + 54), 26, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, cw - 90)
		if bool(sm.get("exists", false)):
			var pl: int = int(float(sm.get("play_s", 0.0)))
			Kit.t(m, "Tier %d   ·   Best wave %d" % [int(sm["tier"]), int(sm["best_wave"])], Vector2(x + 24, y0 + 120), 20, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
			Kit.t(m, "Highest tier %d" % int(sm["best_tier"]), Vector2(x + 24, y0 + 152), 18, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
			Kit.t(m, "Played %dh %02dm" % [pl / 3600, (pl % 3600) / 60], Vector2(x + 24, y0 + 182), 18, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
			if m.confirm_del == n:
				Kit.t(m, "Delete slot %d? This cannot be undone." % n, Vector2(x + 24, y0 + 228), 18, Kit.ENEMY, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
		else:
			Kit.t(m, "Empty slot", Vector2(x + 24, y0 + 120), 22, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
			Kit.t(m, "Start a new Core here", Vector2(x + 24, y0 + 152), 18, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
	if m.menu_msg != "":
		Kit.t(m, m.menu_msg, Vector2(c.x, m.vh - 40), 20, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 900.0)
	if m.overlay != "":
		draw_overlay(m)


static func draw_overlay(m) -> void:
	if m.screen == "base" and not m.offline_offer.is_empty() and m.overlay == "":
		_draw_offline(m)
		return
	if not (m.overlay in OVERLAYS):
		return
	m.draw_rect(Rect2(0, 0, m.vw, m.vh), Color(0, 0, 0, 0.72))
	match String(m.overlay):
		"loot":
			LootReveal.draw(m)
		"pause":
			var rp: Rect2 = modal_rect(m, 520, 470)
			Kit.panel(m, rp, Kit.GEM, Kit.PANEL2)
			Kit.t(m, "PAUSED", Vector2(rp.get_center().x, rp.position.y + 64), 38, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, rp.size.x)
			Kit.t(m, "Engine time is frozen", Vector2(rp.get_center().x, rp.position.y + 92), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, rp.size.x)
		"goal":
			var rg: Rect2 = modal_rect(m, 640, 420)
			Kit.panel(m, rg, Kit.GOLD, Kit.PANEL2)
			Kit.t(m, "RUN COMPLETE", Vector2(rg.get_center().x, rg.position.y + 70), 40, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, rg.size.x)
			Kit.t(m, "Wave 20 held: the first run's goal.", Vector2(rg.get_center().x, rg.position.y + 112), 20, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, rg.size.x)
			if m.S != null:
				Kit.t(m, "%s kills  ·  %s" % [Kit.fmt(float(m.S.kills)), Kit.dur(int(m.S.time_alive))], Vector2(rg.get_center().x, rg.position.y + 150), 18, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, rg.size.x)
			Kit.t(m, "From here the horde grows into the thousands, then 10,000+.", Vector2(rg.get_center().x, rg.position.y + 200), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, rg.size.x)
		"credits":
			var rc: Rect2 = modal_rect(m, 900, 800)
			Kit.panel(m, rc, Kit.RUST, Kit.PANEL2)
			Kit.t(m, "CREDITS", Vector2(rc.position.x + 40, rc.position.y + 62), 34, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
		"settings":
			var r2: Rect2 = modal_rect(m, 1100, 820)
			Kit.panel(m, r2, Kit.RUST, Kit.PANEL2)
			Kit.t(m, "SETTINGS", Vector2(r2.position.x + 24, r2.position.y + 50), 34, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
			if m.set_tab_id == "controls":
				Kit.t(m, "Action", Vector2(r2.position.x + 40, r2.position.y + 142), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
				Kit.t(m, "Keyboard / mouse", Vector2(r2.position.x + 460, r2.position.y + 142), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
				Kit.t(m, "Controller", Vector2(r2.position.x + 780, r2.position.y + 142), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
				var acts: Array = Keybinds.actions()
				var start: int = m.keymap_page * KEYS_PER_PAGE
				for k in range(start, mini(acts.size(), start + KEYS_PER_PAGE)):
					Kit.t(m, String(Keybinds.LABELS.get(acts[k], acts[k])), Vector2(r2.position.x + 40, r2.position.y + 180 + (k - start) * 50.0), 19, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
				Kit.t(m, "Page %d / %d" % [m.keymap_page + 1, int(ceil(float(acts.size()) / float(KEYS_PER_PAGE)))], Vector2(r2.position.x + 650, r2.end.y - 36), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 140.0)
			if m.menu_msg != "":
				Kit.t(m, m.menu_msg, Vector2(r2.position.x + 420, r2.position.y + 50), 18, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 600.0)
		"stats", "history", "achievements":
			var r3: Rect2 = modal_rect(m, 1240, 860)
			Kit.panel(m, r3, Kit.RUST, Kit.PANEL2)
			Kit.t(m, String(m.overlay).to_upper(), Vector2(r3.position.x + 24, r3.position.y + 50), 34, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 500.0)
			match String(m.overlay):
				"stats":
					_draw_stats(m, r3)
				"history":
					_draw_history(m, r3)
				"achievements":
					_draw_achievements(m, r3)
		"modes":
			var r4: Rect2 = modal_rect(m, 1100, 820)
			Kit.panel(m, r4, Kit.MAG, Kit.PANEL2)
			Kit.t(m, "MODE & CHALLENGES", Vector2(r4.position.x + 24, r4.position.y + 50), 34, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 600.0)
			var mods: Array = m.run_opts.get("modifiers", [])
			Kit.t(m, "Challenge modifiers (coin rewards stack, capped at x%.1f)" % ModifierDB.COIN_CAP, Vector2(r4.position.x + 40, r4.position.y + 225), 18, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 800.0)
			Kit.t(m, "Coin multiplier: x%.2f" % ModifierDB.coin_mult(mods), Vector2(r4.position.x + 40, r4.position.y + 480), 26, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 600.0)
			Kit.wrap(m, "Endless: no wave cap, a mutation pick every 25 waves (+15% coins each), banks coins x0.9 and keeps its own best. Modifiers apply to both modes.", Vector2(r4.position.x + 40, r4.position.y + 530), 17, Kit.DIM, 1000.0, 3)


static func _draw_offline(m) -> void:
	var off: Dictionary = m.offline_offer
	m.draw_rect(Rect2(0, 0, m.vw, m.vh), Color(0, 0, 0, 0.72))
	var r: Rect2 = offline_rect(m)
	Kit.panel(m, r, Kit.GOLD, Kit.PANEL2, 3)
	Kit.t(m, "WHILE YOU WERE AWAY", Vector2(r.get_center().x, r.position.y + 70), 36, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Kit.t(m, "Away %s — your Outpost kept producing (each building stores up to its cap)" % Kit.dur(int(off.get("minutes", 0)) * 60), Vector2(r.get_center().x, r.position.y + 108), 19, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var rows: Array = [["cur_coin", "coins", "coins", Kit.GOLD], ["cur_scrap", "scrap", "Scrap", Kit.SCRAP]]
	var y: float = r.position.y + 150.0
	for rw in rows:
		var a: Array = rw
		var n: int = int(off.get(String(a[1]), 0))
		if n <= 0:
			continue
		Kit.icon(m, String(a[0]), Rect2(r.position.x + 220, y, 52, 52))
		Kit.t(m, "+%s %s" % [Kit.fmt(float(n)), String(a[2])], Vector2(r.position.x + 290, y + 40), 34, a[3], HORIZONTAL_ALIGNMENT_LEFT, 400.0)
		y += 66.0
	Kit.t(m, "Warehouses and Storage Tech research raise each building's storage.", Vector2(r.get_center().x, r.end.y - 112), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 40.0)


static func _draw_stats(m, r: Rect2) -> void:
	var st: Dictionary = Stats._st(m.save)
	var x: float = r.position.x + 40.0
	var y: float = r.position.y + 170.0
	var bm: Dictionary = st.get("best_by_mode", {})
	var ps: int = int(float(st.get("play_s", 0.0)))
	var rows: Array = [
		["Runs", str(int(st["runs"]))], ["Waves cleared", Kit.fmt(float(st["waves"]))],
		["Kills", Kit.fmt(float(st["kills"]))], ["Bosses killed", str(int(st["bosses"]))],
		["Coins earned", Kit.fmt(float(st["coins_earned"]))], ["Coins spent", Kit.fmt(float(st["coins_spent"]))],
		["Play time", "%dh %02dm" % [ps / 3600, (ps % 3600) / 60]], ["Best DPS", str(int(float(st.get("dps_best", 0.0))))],
		["Best wave (normal)", str(int(bm.get("normal", 0)))], ["Best wave (endless)", str(int(bm.get("endless", 0)))],
		["Reforges", str(int(st.get("reforges", 0)))], ["Outpost collects", str(int(st.get("outpost_collects", 0)))],
	]
	for k in rows.size():
		var rw: Array = rows[k]
		var cx: float = x + float(k % 2) * 580.0
		var cy: float = y + float(k / 2) * 46.0
		Kit.t(m, String(rw[0]), Vector2(cx, cy), 22, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 340.0)
		Kit.t(m, String(rw[1]), Vector2(cx + 520, cy), 22, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 180.0)
	var fav: Array = Stats.favourite(m.save, 3)
	var fy: float = y + 350.0
	Kit.t(m, "Most placed buildings", Vector2(x, fy), 20, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
	for k in fav.size():
		var fid: String = String(fav[k])
		Kit.icon(m, fid, Rect2(x + k * 260.0, fy + 16, 56, 56))
		Kit.t(m, String(PickDB.get_def(fid).get("name", fid)), Vector2(x + 64 + k * 260.0, fy + 52), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 190.0)
	var kk: Dictionary = st.get("kills_by_kind", {})
	var ky: float = fy + 110.0
	Kit.t(m, "Kills by enemy", Vector2(x, ky), 20, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
	var j: int = 0
	for kd in kk.keys():
		Kit.t(m, "%s  %s" % [String(kd).capitalize(), Kit.fmt(float(kk[kd]))], Vector2(x + float(j % 4) * 290.0, ky + 34 + float(j / 4) * 30.0), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 280.0)
		j += 1


static func _draw_history(m, r: Rect2) -> void:
	var h: Array = m.save.get("history", [])
	var x: float = r.position.x + 40.0
	var y: float = r.position.y + 150.0
	var xs: Array = [0.0, 110.0, 190.0, 420.0, 520.0, 640.0, 760.0]
	var hn: Array = ["Run", "Tier", "Mode", "Wave", "Coins", "Time", "Seed"]
	for c in hn.size():
		Kit.t(m, String(hn[c]), Vector2(x + float(xs[c]), y), 17, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
	if h.is_empty():
		Kit.t(m, "No runs yet — finish a run to see it here.", Vector2(x, y + 50), 20, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 800.0)
	for k in mini(12, h.size()):
		var e: Dictionary = h[h.size() - 1 - k]
		var ry: float = y + 40.0 + float(k) * 52.0
		var mode: String = String(e["mode"]) + ("+%d" % (e["modifiers"] as Array).size() if not (e["modifiers"] as Array).is_empty() else "")
		var cols: Array = ["#%d" % (h.size() - k), "T%d" % int(e["tier"]), mode, "w%d" % int(e["wave"]), Kit.fmt(float(e["coins"])), "%dm%02ds" % [int(float(e["duration_s"])) / 60, int(float(e["duration_s"])) % 60], str(int(e["seed"]))]
		for c in cols.size():
			Kit.t(m, String(cols[c]), Vector2(x + float(xs[c]), ry), 19, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 220.0)


static func _draw_achievements(m, r: Rect2) -> void:
	var ids: Array = AchievementDB.ids()
	var x: float = r.position.x + 30.0
	var y: float = r.position.y + 136.0
	var cw: float = (r.size.x - 60.0) / 3.0
	var rows: int = int(ceil(float(ids.size()) / 3.0))
	var rh: float = minf(60.0, (r.size.y - 230.0) / float(maxi(1, rows)))
	Kit.t(m, "%d / %d unlocked" % [Achievements.unlocked_count(m.save), ids.size()], Vector2(r.end.x - 330, r.position.y + 50), 20, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
	for k in ids.size():
		var id: String = ids[k]
		var d: Dictionary = AchievementDB.get_def(id)
		var on: bool = Achievements.is_unlocked(m.save, id)
		var cx: float = x + float(k % 3) * cw
		var cy: float = y + float(k / 3) * rh
		Kit.panel(m, Rect2(cx, cy, cw - 10, rh - 6), Kit.GOLD if on else Kit.EDGE, Kit.CARD if on else Kit.PANEL)
		Kit.icon(m, "icon_trophy", Rect2(cx + 8, cy + (rh - 6) * 0.5 - 16, 32, 32), Color.WHITE if on else Color(1, 1, 1, 0.25))
		Kit.t(m, String(d["name"]), Vector2(cx + 48, cy + rh * 0.42), 17, Kit.TEXT if on else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 66)
		Kit.t(m, String(d["desc"]), Vector2(cx + 48, cy + rh * 0.42 + 19), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 66)
		m.stat_tips.append([Rect2(cx, cy, cw - 10, rh - 6), "%s\n%s" % [String(d["name"]), String(d["desc"])]])
