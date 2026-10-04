extends RefCounted
## PC desktop shell for Main.gd (PC_SPEC UI package). View only: every action
## calls Main / engine APIs (BaseMeta, TowerState, MetaSave, Settings,
## Keybinds, Stats) and never owns a rule. `m` is the Main node (untyped: a
## preload of Main here would be cyclic).
##
## Layout at 1920x1080 (scales with the live viewport):
##   top HUD (HUD_H) | left build/info panel | battlefield + 7x7 base (the
##   mobile view as a centre column) | right meta panel | bottom hotbar (HOT_H)
## Screens/overlays added here: main menu + save-slot picker, settings (Video,
## Audio, Controls with remap, Gameplay), stats, run history, achievements,
## mode select (endless + challenge modifiers), right-click info popover, the
## endless mutation pick, wave telegraph arrows, drag ghost and hover tooltips.

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const PerkDB := preload("res://data/PerkDB.gd")
const ModifierDB := preload("res://data/ModifierDB.gd")
const AchievementDB := preload("res://data/AchievementDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const Settings := preload("res://Settings.gd")
const Keybinds := preload("res://Keybinds.gd")
const Stats := preload("res://Stats.gd")
const Achievements := preload("res://Achievements.gd")
const Tiers := preload("res://Tiers.gd")
const Labs := preload("res://Labs.gd")
const Art := preload("res://ArtDB.gd")

const BG: Color = Color("1b2027")
const PANEL: Color = Color("232a33")
const PANEL2: Color = Color("2b333d")
const EDGE: Color = Color("3a434e")
const RUST: Color = Color("d9773a")
const ENEMY: Color = Color("e8434f")
const TEXT: Color = Color("e9edf2")
const DIM: Color = Color("9aa6b2")
const GOLD: Color = Color("f2c94c")
const GEM: Color = Color("5ad1f0")
const GREEN: Color = Color("6bd46b")
const MAG: Color = Color("e04bc0")

const OVERLAYS: Array = ["info", "settings", "stats", "history", "achievements", "modes"]
const SET_TABS: Array = ["video", "audio", "controls", "gameplay"]
const KEYS_PER_PAGE: int = 11
const HOT_KEYS: Array = ["hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4", "hotbar_5", "hotbar_6", "hotbar_7", "hotbar_8", "hotbar_9", "hotbar_10"]
const QUAD_NAMES: Array = ["North-east", "South-east", "South-west", "North-west"]
const LEGEND: Array = ["pause", "upgrade", "sell", "cancel", "info", "speed_up", "lane_next", "tab_stats", "retry", "fullscreen"]

## Joypad axes report "pressed" on every motion event past the deadzone: an
## action fires once per crossing (cleared again on its release event).
static var _axis_held: Dictionary = {}


# =================================================================== helpers
static func tip_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.96)
	sb.border_color = RUST
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func _sb(col: Color, fill: Color, bw: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = col
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	return sb


## Desktop button: press-action, tooltip, focusable (keyboard/pad navigation),
## >= 40 px tall. `key` (meta) lets tests find it; defaults to the text.
static func btn(m, text: String, rect: Rect2, cb: Callable, tip: String, enabled: bool = true, col: Color = RUST, key: String = "", icon: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = Vector2(rect.size.x, maxf(40.0, rect.size.y))
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	# Keyboard/mouse: no focus (Space/Enter stay hotkeys). Pad: full focus chain.
	b.focus_mode = Control.FOCUS_ALL if String(m.last_device) == "pad" else Control.FOCUS_NONE
	b.disabled = not enabled
	b.clip_text = true
	b.tooltip_text = tip if tip != "" else text
	b.set_meta("key", key if key != "" else text)
	b.add_theme_font_size_override("font_size", 18)
	var sb: StyleBoxFlat = _sb(col, col.darkened(0.6))
	var sbh: StyleBoxFlat = _sb(col.lightened(0.25), col.darkened(0.4))
	var sbf: StyleBoxFlat = _sb(Color.WHITE, col.darkened(0.45), 3)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_stylebox_override("focus", sbf)
	b.add_theme_stylebox_override("disabled", _sb(Color("4a525c"), Color("252b32")))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", DIM)
	if icon != "":
		var t: Texture2D = Art.tex(icon)
		if t != null:
			b.icon = t
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", int(minf(36.0, b.size.y - 8.0)))
	b.pressed.connect(func() -> void: m.sfx_play("click"))
	b.pressed.connect(cb)
	m.dui.add_child(b)
	return b


static func _t(m, s: String, pos: Vector2, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = 400.0) -> void:
	var p: Vector2 = pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	m.draw_string(m.font, p + Vector2(1, 2), s, align, width, size, Color(0, 0, 0, 0.55))
	m.draw_string(m.font, p, s, align, width, size, col)


static func _wrap(m, s: String, pos: Vector2, size: int, col: Color, width: float, max_lines: int = 6) -> float:
	m.draw_multiline_string(m.font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, max_lines, col)
	var ts: Vector2 = m.font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size, max_lines)
	return ts.y


static func _panel(m, r: Rect2, border: Color = EDGE, fill: Color = PANEL) -> void:
	m.draw_style_box(_sb(border, fill), r)


static func hint(m, action: String) -> String:
	var pad: bool = String(m.last_device) == "pad"
	var h: String = Keybinds.hint(action, pad)
	if h == "" and pad:
		h = Keybinds.hint(action, false)
	return h


static func _stat_tip(m, r: Rect2, text: String) -> void:
	m.stat_tips.append([r, text])


static func apply_settings(m, s: Dictionary) -> void:
	m.settings = Settings.normalize(s)
	Settings.apply(m.settings, m.get_tree())
	Settings.write(m.settings)
	m._rebuild_ui()


static func _hud_rect(m) -> Rect2:
	return Rect2(0, 0, m.vw, m.HUD_H)


static func _hot_rect(m) -> Rect2:
	return Rect2(0, m.vh - m.HOT_H, m.vw, m.HOT_H)


static func left_rect(m) -> Rect2:
	return Rect2(0, m.HUD_H, m.panel_w, m.vh - m.HUD_H - m.HOT_H)


static func right_rect(m) -> Rect2:
	return Rect2(m.vw - m.panel_w, m.HUD_H, m.panel_w, m.vh - m.HUD_H - m.HOT_H)


static func _modal_rect(m, w: float, h: float) -> Rect2:
	return Rect2(floorf((m.vw - w) * 0.5), floorf((m.vh - h) * 0.5), w, h)


# ===================================================================== build
static func build(m) -> void:
	if m.screen == "menu":
		if m.overlay == "settings":
			_build_settings(m)
		elif m.overlay == "":
			_build_menu(m)
		return
	if m.overlay in OVERLAYS:
		match String(m.overlay):
			"info": _build_info(m)
			"settings": _build_settings(m)
			"stats", "history", "achievements": _build_records(m)
			"modes": _build_modes(m)
		return
	if m.overlay != "":
		return   # mobile Menus modal (pause / options / credits) owns input
	_build_hud(m)
	if m.screen == "base" and not m.offline_offer.is_empty():
		return
	_build_hotbar(m)
	_build_side(m)


static func _build_hud(m) -> void:
	var x: float = m.vw - 8.0
	var items: Array = [
		["Menu", "Main menu / save slots (Esc on the base)", func() -> void: m.go_menu(), "icon_menu"],
		["Settings", "Video, audio, controls and gameplay settings", func() -> void: m.set_overlay("settings"), "icon_gear"],
		["Awards", "Achievements (%d / %d)" % [Achievements.unlocked_count(m.save), AchievementDB.ids().size()], func() -> void: m.set_overlay("achievements"), "icon_trophy"],
		["History", "Your last 50 runs, with Retry seed", func() -> void: m.set_overlay("history"), "icon_history"],
		["Stats", "Lifetime stats  [%s]" % hint(m, "tab_stats"), func() -> void: m.set_overlay("stats"), "icon_stats"],
	]
	for it in items:
		var a: Array = it
		x -= 132.0
		btn(m, String(a[0]), Rect2(x, 8, 126, 44), a[2], String(a[1]), true, Color("4a525c"), "HUD " + String(a[0]), String(a[3]))


static func _build_hotbar(m) -> void:
	var hr: Rect2 = _hot_rect(m)
	if m.screen == "base":
		var ids: Array = BuildingDB.all_ids()
		var n: int = ids.size()
		var sw: float = minf(118.0, (hr.size.x - 32.0) / float(n) - 6.0)
		var x0: float = floorf((m.vw - (sw + 6.0) * float(n)) * 0.5)
		for k in n:
			var id: String = ids[k]
			var d: Dictionary = BuildingDB.get_def(id)
			var pc: int = BaseMeta.place_cost(id)
			var hk: String = hint(m, String(HOT_KEYS[k])) if k < HOT_KEYS.size() else ""
			var tip: String = "%s — %d coins\n%s\nDrag onto a cell, or press %s then click a cell." % [String(d["name"]), pc, String(d["desc"]), hk if hk != "" else "it"]
			var col: Color = BuildingDB.cat_color(String(d["cat"]))
			var on: bool = m.armed == id
			var b: Button = btn(m, "", Rect2(x0 + k * (sw + 6.0), hr.position.y + 8, sw, hr.size.y - 16), func() -> void: m.begin_drag_building(id), tip, true, Color.WHITE if on else col, "HOT " + String(d["name"]))
			_slot_content(b, id, hk, "%d" % pc, int(m.save["coins"]) >= pc)
		return
	if m.screen == "run" and m.S != null:
		var S = m.S
		var cards: Array = []
		if S.mutation_offer.size() > 0:
			for k in S.mutation_offer.size():
				var mid: String = S.mutation_offer[k]
				var md: Dictionary = ModifierDB.MUTATIONS.get(mid, {})
				var idx: int = k
				cards.append([String(md.get("name", mid)), String(md.get("desc", "")) + "  (+10% coins)", func() -> void: m._handle(S.choose_mutation(idx)), MAG, "MUT " + String(md.get("name", mid)), "icon_endless"])
		elif S.perk_offer.size() > 0:
			for k in S.perk_offer.size():
				var pid: String = S.perk_offer[k]
				var pd: Dictionary = PerkDB.get_def(pid)
				var idx2: int = k
				var desc: String = String(pd["desc"]) + ("   COST: " + String(pd["cost"]) if bool(pd["tradeoff"]) else "")
				cards.append([String(pd["name"]), desc, func() -> void: m._handle(S.choose_perk(idx2)), GOLD, "DPERK " + String(pd["name"]), "perk_" + pid.substr(2)])
		elif S.draft.size() > 0:
			for k in S.draft.size():
				var card: Dictionary = S.draft[k]
				var bid: String = card["id"]
				var bd: Dictionary = BuildingDB.get_def(bid)
				var idx3: int = k
				var head: String = "NEW " if String(card["kind"]) == "new" else "+1 LV "
				cards.append([head + String(bd["name"]), String(bd["desc"]) + ("\nDrag onto a cell to place." if head == "NEW " else ""), func() -> void: m.begin_drag_card(idx3), BuildingDB.cat_color(String(bd["cat"])), "DCARD " + String(bd["name"]), bid])
		if not cards.is_empty():
			var cw: float = 420.0
			var x1: float = floorf((m.vw - (cw + 12.0) * float(cards.size())) * 0.5)
			for k in cards.size():
				var c: Array = cards[k]
				var hk2: String = hint(m, String(HOT_KEYS[k]))
				var b2: Button = btn(m, "", Rect2(x1 + k * (cw + 12.0), hr.position.y + 8, cw, hr.size.y - 16), c[2], String(c[0]) + "\n" + String(c[1]), true, c[3], String(c[4]))
				_card_content(b2, String(c[5]), hk2, String(c[0]), String(c[1]))
			if S.draft.size() > 0 and S.rerolls_left > 0:
				btn(m, "Reroll (%d)" % S.rerolls_left, Rect2(x1 + cards.size() * (cw + 12.0), hr.position.y + 24, 150, 64), func() -> void: m._handle(S.reroll_draft()), "Reroll the draft", true, GEM, "DREROLL")
			return
		# quick actions
		var qa: Array = [
			["Pause  [%s]" % hint(m, "pause"), "Pause / resume the run", func() -> void: m.set_overlay("pause"), "icon_pause"],
			["Speed %sx  [%s]" % [m._speed_str(S.speed), hint(m, "speed_up")], "Cycle game speed (Labs unlock more)", func() -> void: m.cycle_speed(), "icon_speed"],
			["Lane: %s  [%s]" % [String(QUAD_NAMES[S.focus_quad]), hint(m, "lane_next")], "Lane focus: Lane Beacons buff damage against this lane", func() -> void: m._handle(S.set_focus((S.focus_quad + 1) % 4)), "lane_arrow"],
		]
		if S.pending_place != "":
			qa.append(["Cancel place  [%s]" % hint(m, "cancel"), "Drop the pending building card", func() -> void: m._handle(S.cancel_place()), "icon_lock"])
		var qw: float = 300.0
		var x2: float = floorf((m.vw - (qw + 12.0) * float(qa.size())) * 0.5)
		for k in qa.size():
			var q: Array = qa[k]
			btn(m, String(q[0]), Rect2(x2 + k * (qw + 12.0), hr.position.y + 22, qw, 68), q[2], String(q[1]), true, Color("4a525c"), "Q" + str(k), String(q[3]))
	elif m.screen == "results":
		btn(m, "Retry seed  [%s]" % hint(m, "retry"), Rect2(m.vw * 0.5 - 360, hr.position.y + 22, 340, 68), func() -> void: m.start_run(m.last_seed), "Replay this run's seed (%d) with the same mode and modifiers" % m.last_seed, true, GEM, "RETRY SEED")
		btn(m, "Back to Base", Rect2(m.vw * 0.5 + 20, hr.position.y + 22, 340, 68), func() -> void: m.go_base(), "Return to the permanent base", true, RUST, "DBACK")


static func _slot_content(b: Button, id: String, hk: String, cost: String, ok: bool) -> void:
	var tr := TextureRect.new()
	tr.texture = Art.tex(id)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = Vector2(b.size.x * 0.5 - 26, 6)
	tr.size = Vector2(52, 52)
	if not ok:
		tr.modulate = Color(1, 1, 1, 0.45)
	b.add_child(tr)
	_lbl(b, hk, Vector2(6, 2), 15, GOLD)
	_lbl(b, cost, Vector2(0, b.size.y - 28), 16, GOLD if ok else DIM, b.size.x, HORIZONTAL_ALIGNMENT_CENTER)


static func _card_content(b: Button, icon: String, hk: String, title: String, desc: String) -> void:
	var tr := TextureRect.new()
	tr.texture = Art.tex(icon)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = Vector2(10, (b.size.y - 60) * 0.5)
	tr.size = Vector2(60, 60)
	b.add_child(tr)
	_lbl(b, "[%s]" % hk, Vector2(b.size.x - 60, 6), 16, GOLD, 52.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_lbl(b, title, Vector2(80, 6), 20, TEXT, b.size.x - 150)
	var d: Label = _lbl(b, desc, Vector2(80, 32), 15, DIM, b.size.x - 90)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size.y = b.size.y - 38
	d.clip_text = true


static func _lbl(parent: Control, s: String, pos: Vector2, size: int, col: Color, width: float = 0.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.position = pos
	l.horizontal_alignment = align
	if width > 0.0:
		l.size = Vector2(width, float(size) + 6.0)
	parent.add_child(l)
	return l


static func _build_side(m) -> void:
	if m.show_right:
		var rr: Rect2 = right_rect(m)
		var x: float = rr.position.x + 16.0
		var w: float = rr.size.x - 32.0
		if m.screen == "base":
			var tabs: Array = [["base", "Base", "tab_base"], ["labs", "Labs", "tab_labs"], ["cards", "Cards", "tab_cards"], ["missions", "Missions", "tab_missions"]]
			var tw: float = (w - 8.0) / 2.0
			for k in tabs.size():
				var tb: Array = tabs[k]
				var id: String = tb[0]
				btn(m, "%s  [%s]" % [String(tb[1]), hint(m, String(tb[2]))], Rect2(x + (k % 2) * (tw + 8.0), rr.position.y + 12 + (k / 2) * 52.0, tw, 46), func() -> void: m.set_tab(id), "Open the %s tab" % String(tb[1]), true, RUST if m.tab == id else Color("4a525c"), "DTAB " + String(tb[1]))
			btn(m, "Mode & challenges", Rect2(x, rr.end.y - 132, w, 52), func() -> void: m.set_overlay("modes"), "Pick Normal or Endless and stack challenge modifiers for bonus coins", true, MAG, "MODES", "icon_mod")
			btn(m, "START RUN  (Tier %d)" % m.view_tier, Rect2(x, rr.end.y - 72, w, 60), func() -> void: m.start_run(), "Start a run with the current mode and modifiers", Tiers.is_unlocked(m.save, m.view_tier), RUST, "DSTART")
	if m.show_left and m.sel >= 0:
		var lr: Rect2 = left_rect(m)
		var bx: float = lr.position.x + 16.0
		var bw: float = (lr.size.x - 44.0) / 2.0
		var by: float = lr.end.y - 64.0
		btn(m, "Upgrade [%s]" % hint(m, "upgrade"), Rect2(bx, by, bw, 52), func() -> void: do_upgrade(m), "Upgrade the selected cell", true, GREEN, "DUPG")
		btn(m, "Info [%s]" % hint(m, "info"), Rect2(bx + bw + 12.0, by, bw, 52), func() -> void: m.open_info(m.sel), "Open the cell info popover (or right-click a cell)", true, GEM, "DINFO", "icon_info")


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
		btn(m, ("Continue" if active else "Load") if ex else "New game", Rect2(x + 20, y0 + 250, cw - 40, 60), func() -> void: m.load_slot(slot), "Play save slot %d" % slot, true, RUST, "SLOT %d PLAY" % slot)
		if ex:
			if m.confirm_del == slot:
				btn(m, "Confirm delete", Rect2(x + 20, y0 + 322, (cw - 52) * 0.5, 48), func() -> void: m.delete_slot(slot), "Permanently delete slot %d" % slot, true, ENEMY, "SLOT %d CONFIRM" % slot)
				btn(m, "Keep", Rect2(x + 32 + (cw - 52) * 0.5, y0 + 322, (cw - 52) * 0.5, 48), func() -> void: m.ask_delete(0), "Cancel the delete", true, Color("4a525c"), "SLOT %d KEEP" % slot)
			else:
				btn(m, "Delete", Rect2(x + 20, y0 + 322, (cw - 52) * 0.5, 48), func() -> void: m.ask_delete(slot), "Delete slot %d (asks to confirm)" % slot, true, Color("7a3a3a"), "SLOT %d DELETE" % slot)
				btn(m, "Copy to empty", Rect2(x + 32 + (cw - 52) * 0.5, y0 + 322, (cw - 52) * 0.5, 48), func() -> void: m.copy_slot(slot), "Copy this save into the first empty slot", true, Color("4a525c"), "SLOT %d COPY" % slot)
	var by: float = y0 + 430.0
	var labels: Array = [["Settings", "Video, audio, controls (key remapping) and gameplay", func() -> void: m.set_overlay("settings")],
		["Credits", "Open-source credits", func() -> void: m.set_overlay("credits")],
		["Quit", "Quit to desktop", func() -> void: m.get_tree().quit()]]
	for k in labels.size():
		var l: Array = labels[k]
		btn(m, String(l[0]), Rect2(m.vw * 0.5 - 160, by + k * 64.0, 320, 54), l[2], String(l[1]), true, Color("4a525c"), "MENU " + String(l[0]))
	_focus_first(m)


static func _focus_first(m) -> void:
	if String(m.last_device) != "pad":
		return
	for c in m.dui.get_children():
		if c is Button and not (c as Button).disabled:
			(c as Button).call_deferred("grab_focus")
			return


static func _build_info(m) -> void:
	var i: int = m.info_cell
	var r: Rect2 = info_rect(m)
	var y: float = r.end.y - 60.0
	var w3: float = (r.size.x - 48.0) / 3.0
	btn(m, "Upgrade [%s]" % hint(m, "upgrade"), Rect2(r.position.x + 12, y, w3, 48), func() -> void: do_upgrade(m), "Upgrade this cell", true, GREEN, "INFO UPGRADE")
	var sell_ok: bool = m.screen == "base" and i != BaseMeta.CORE_SLOT and not BaseMeta.slot_of(m.save, i).is_empty()
	btn(m, "Sell [%s]" % hint(m, "sell"), Rect2(r.position.x + 24 + w3, y, w3, 48), func() -> void: do_sell(m), "Demolish this building (base only; runs cannot sell)", sell_ok, ENEMY, "INFO SELL")
	btn(m, "Close [%s]" % hint(m, "cancel"), Rect2(r.position.x + 36 + w3 * 2.0, y, w3, 48), func() -> void: m.set_overlay(""), "Close the popover", true, Color("4a525c"), "INFO CLOSE")
	if m.screen == "run" and m.S != null and m.S.is_weapon_slot(i):
		btn(m, "Target: %s" % String(m.S.target_modes[i]).capitalize(), Rect2(r.position.x + 12, y - 56, r.size.x - 24, 46), func() -> void: m._handle(m.S.cycle_target_mode(i)); m._rebuild_ui(), "Cycle this weapon's targeting mode", true, BuildingDB.cat_color("weapon"), "INFO TARGET")
	_focus_first(m)


static func info_rect(m) -> Rect2:
	var p: Vector2 = m.w2s(TowerState.slot_pos(maxi(0, m.info_cell)))
	var w: float = 540.0
	var h: float = 300.0
	var x: float = p.x + 48.0
	if x + w > m.vw - 8.0:
		x = p.x - 48.0 - w
	return Rect2(clampf(x, 8.0, m.vw - w - 8.0), clampf(p.y - h * 0.5, m.HUD_H + 8.0, m.vh - h - 8.0), w, h)


static func _build_settings(m) -> void:
	var r: Rect2 = _modal_rect(m, 1100, 820)
	var tw: float = (r.size.x - 40.0 - 18.0) / 4.0
	for k in SET_TABS.size():
		var id: String = SET_TABS[k]
		btn(m, id.capitalize(), Rect2(r.position.x + 20 + k * (tw + 6.0), r.position.y + 70, tw, 50), func() -> void: m.set_tab_id = id; m.remap_action = ""; m._rebuild_ui(), "%s settings" % id.capitalize(), true, RUST if m.set_tab_id == id else Color("4a525c"), "SET TAB " + id.capitalize())
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
				["Confirm sell", "On" if bool(g["confirm_sell"]) else "Off", "gameplay", "confirm_sell", [false, true], "Ask before demolishing"],
				["Default speed", "%sx" % str(g["default_speed"]), "gameplay", "default_speed", [1.0, 1.5, 2.0, 3.0, 4.0], "Speed a run starts at"],
				["Colorblind", String(g["colorblind"]).capitalize(), "gameplay", "colorblind", Settings.COLORBLIND, "Colorblind palette"],
				["Tooltip delay", "%.1fs" % float((s["controls"] as Dictionary)["tooltip_delay"]), "controls", "tooltip_delay", [0.0, 0.2, 0.4, 0.8], "How long to hover before a tooltip shows"],
			]
		"controls":
			_build_keymap(m, r, s)
	for k in rows.size():
		var row: Array = rows[k]
		var sec: String = row[2]
		var key: String = row[3]
		var opts: Array = row[4]
		btn(m, "%s:  %s" % [String(row[0]), String(row[1])], Rect2(x, y + k * 62.0, r.size.x - 80.0, 52), func() -> void: cycle_setting(m, sec, key, opts), String(row[5]) + " (click to change)", true, Color("4a525c"), "SET " + String(row[0]))
	btn(m, "Close [%s]" % hint(m, "cancel"), Rect2(r.end.x - 220, r.end.y - 70, 200, 52), func() -> void: m.set_overlay(""), "Close settings (changes are saved)", true, RUST, "SET CLOSE")
	_focus_first(m)


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
		var row: int = k - start
		var kb: String = Keybinds.hint(a, false)
		var pd: String = Keybinds.hint(a, true)
		var cap: bool = m.remap_action == a
		btn(m, ("Press a key... (Esc cancels)" if cap else (kb if kb != "" else "—")), Rect2(x + 420, y + row * 50.0, 300, 44), func() -> void: m.remap_action = a; m._rebuild_ui(), "Rebind %s (keyboard / mouse / pad)" % String(Keybinds.LABELS.get(a, a)), true, GOLD if cap else Color("4a525c"), "REMAP " + a)
		btn(m, pd if pd != "" else "—", Rect2(x + 740, y + row * 50.0, 160, 44), func() -> void: m.remap_action = a; m._rebuild_ui(), "Controller binding for %s (press a pad button)" % String(Keybinds.LABELS.get(a, a)), true, Color("3a434e"), "PAD " + a)
		btn(m, "Reset", Rect2(x + 920, y + row * 50.0, 100, 44), func() -> void: Keybinds.reset_action(a); save_keys(m), "Restore the default for this action", true, Color("3a434e"), "RESET " + a)
	var py: float = r.end.y - 70.0
	btn(m, "< Prev", Rect2(r.position.x + 20, py, 140, 52), func() -> void: m.keymap_page -= 1; m._rebuild_ui(), "Previous page of actions", m.keymap_page > 0, Color("4a525c"), "KEYS PREV")
	btn(m, "Next >", Rect2(r.position.x + 170, py, 140, 52), func() -> void: m.keymap_page += 1; m._rebuild_ui(), "Next page of actions", m.keymap_page < pages - 1, Color("4a525c"), "KEYS NEXT")
	btn(m, "Reset all", Rect2(r.position.x + 320, py, 160, 52), func() -> void: Keybinds.reset_all(); save_keys(m), "Restore every default binding", true, ENEMY, "KEYS RESET ALL")
	var c: Dictionary = s["controls"]
	btn(m, "Pad glyphs: %s" % String(c["glyphs"]).capitalize(), Rect2(r.position.x + 490, py, 260, 52), func() -> void: cycle_setting(m, "controls", "glyphs", Settings.GLYPHS), "Controller button art style", true, Color("4a525c"), "SET Glyphs")


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
	if other != "":
		m.menu_msg = "Swapped with %s" % String(Keybinds.LABELS.get(other, other))
	else:
		m.menu_msg = ""
	m.get_viewport().set_input_as_handled()
	save_keys(m)


static func _build_records(m) -> void:
	var r: Rect2 = _modal_rect(m, 1240, 860)
	var tabs: Array = [["stats", "Stats"], ["history", "History"], ["achievements", "Achievements"]]
	for k in tabs.size():
		var tb: Array = tabs[k]
		var id: String = tb[0]
		btn(m, String(tb[1]), Rect2(r.position.x + 20 + k * 206.0, r.position.y + 70, 200, 50), func() -> void: m.set_overlay(id), "Show %s" % String(tb[1]), true, RUST if m.overlay == id else Color("4a525c"), "REC " + String(tb[1]))
	if m.overlay == "history":
		var h: Array = m.save.get("history", [])
		var n: int = mini(12, h.size())
		for k in n:
			var e: Dictionary = h[h.size() - 1 - k]
			var entry: Dictionary = e
			btn(m, "Retry", Rect2(r.end.x - 160, r.position.y + 160 + k * 52.0, 130, 44), func() -> void: m.retry_entry(entry), "Replay seed %d (Tier %d, %s)" % [int(e["seed"]), int(e["tier"]), String(e["mode"])], true, GEM, "HIST RETRY %d" % k)
	btn(m, "Close [%s]" % hint(m, "cancel"), Rect2(r.end.x - 220, r.end.y - 70, 200, 52), func() -> void: m.set_overlay(""), "Close", true, RUST, "REC CLOSE")
	_focus_first(m)


static func _build_modes(m) -> void:
	var r: Rect2 = _modal_rect(m, 1100, 820)
	var x: float = r.position.x + 40.0
	var y: float = r.position.y + 120.0
	var mode: String = String(m.run_opts.get("mode", "normal"))
	var eu: bool = BaseMeta.endless_unlocked(m.save)
	btn(m, "Normal", Rect2(x, y, 300, 56), func() -> void: m.run_opts["mode"] = "normal"; m._rebuild_ui(), "Standard run: tier progression counts", true, RUST if mode == "normal" else Color("4a525c"), "MODE Normal")
	btn(m, "Endless" if eu else "Endless (best wave 50)", Rect2(x + 320, y, 360, 56), func() -> void: m.run_opts["mode"] = "endless"; m._rebuild_ui(), "No wave cap; mutation pick every 25 waves; coins x0.8" + ("" if eu else ". Unlocks at best wave 50."), eu, MAG if mode == "endless" else Color("4a525c"), "MODE Endless", "icon_endless")
	var mods: Array = m.run_opts.get("modifiers", [])
	for k in ModifierDB.IDS.size():
		var id: String = ModifierDB.IDS[k]
		var d: Dictionary = ModifierDB.get_def(id)
		var on: bool = mods.has(id)
		var col: int = k % 3
		var row: int = k / 3
		btn(m, "%s %s  +%d%%" % ["[x]" if on else "[ ]", String(d["name"]), int(round(float(d["coin"]) * 100.0))], Rect2(x + col * 345.0, y + 120 + row * 70.0, 330, 56), func() -> void: toggle_mod(m, id), String(d["desc"]) + " — coin reward +%d%%" % int(round(float(d["coin"]) * 100.0)), true, ENEMY if on else Color("4a525c"), "MOD " + String(d["name"]), "icon_mod")
	btn(m, "Start run", Rect2(r.end.x - 440, r.end.y - 70, 200, 52), func() -> void: m.start_run(), "Start with this mode and modifiers", Tiers.is_unlocked(m.save, m.view_tier), RUST, "MODES START")
	btn(m, "Close [%s]" % hint(m, "cancel"), Rect2(r.end.x - 220, r.end.y - 70, 200, 52), func() -> void: m.set_overlay(""), "Keep these choices and close", true, Color("4a525c"), "MODES CLOSE")
	_focus_first(m)


static func toggle_mod(m, id: String) -> void:
	var mods: Array = (m.run_opts.get("modifiers", []) as Array).duplicate()
	if mods.has(id):
		mods.erase(id)
	else:
		mods.append(id)
	m.run_opts["modifiers"] = ModifierDB.clean(mods)
	m._rebuild_ui()


# =================================================================== actions
static func do_upgrade(m) -> void:
	var i: int = m.sel
	if i < 0:
		return
	if m.screen == "base":
		if i == BaseMeta.CORE_SLOT:
			m._base_act(BaseMeta.try_core(m.save, "dmg"))
		else:
			m._base_act(BaseMeta.try_upgrade(m.save, i))
	elif m.screen == "run" and m.S != null:
		m._handle(m.S.upgrade(i))
		m._rebuild_ui()


static func do_sell(m) -> void:
	var i: int = m.sel
	if i < 0:
		return
	if m.screen == "base":
		if BaseMeta.demolish(m.save, i):
			m.sfx_play("click")
			m._save()
		if m.overlay == "info":
			m.overlay = ""
		m._rebuild_ui()
	else:
		m._queue_toasts([{"t": "msg", "text": "Buildings can only be sold on the base"}])


## Why `id` cannot go on cell `i` right now ("" when it can).
static func place_reason(m, i: int, id: String) -> String:
	if i < 0:
		return "Not a cell"
	if i == TowerState.CORE_SLOT:
		return "The Core"
	if m.screen == "run" and m.S != null:
		if not bool(m.S.unlocked[i]):
			return "Locked plot"
		if m.S.id_at(i) != "":
			return "Occupied"
		if not m.S.can_place(i, id):
			return "Ring 2+ only" if id == "railgun" else ("Build cap reached" if m.S.at_cap() else "Can't place here")
		return ""
	if not BaseMeta.is_unlocked(m.save, i):
		return "Locked cell"
	if not BaseMeta.slot_of(m.save, i).is_empty():
		return "Occupied"
	if not BaseMeta.place_ok(i, id):
		return "Ring 2+ only"
	if BaseMeta.building_count(m.save) >= BaseMeta.build_cap(m.save):
		return "Build cap reached"
	if int(m.save["coins"]) < BaseMeta.place_cost(id):
		return "Need %d coins" % BaseMeta.place_cost(id)
	return ""


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
	if _pressed(m, event, "retry") and (m.screen == "run" or m.screen == "results") and m.last_seed != 0:
		m.start_run(m.last_seed)
		return true
	if _pressed(m, event, "cancel"):
		_cancel(m)
		return true
	if m.screen == "menu" or m.overlay in ["settings", "stats", "history", "achievements", "modes", "options", "credits"]:
		if m.overlay in ["stats", "history", "achievements"] and _pressed(m, event, "tab_stats"):
			m.set_overlay("")
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
	for k in HOT_KEYS.size():
		if _pressed(m, event, String(HOT_KEYS[k])):
			hotbar(m, k)
			return true
	if _pressed(m, event, "upgrade"):
		do_upgrade(m)
		return true
	if _pressed(m, event, "sell"):
		do_sell(m)
		return true
	if _pressed(m, event, "info") and m.sel >= 0:
		m.open_info(m.sel)
		return true
	if m.overlay == "info":
		return false
	for d in [["cursor_up", -TowerState.SIDE], ["cursor_down", TowerState.SIDE], ["cursor_left", -1], ["cursor_right", 1]]:
		if _pressed(m, event, String(d[0])):
			move_cursor(m, int(d[1]))
			return true
	if _pressed(m, event, "confirm"):
		confirm(m)
		return true
	if _pressed(m, event, "speed_up") or _pressed(m, event, "speed_down"):
		m.cycle_speed()
		return true
	if m.screen == "run" and m.S != null:
		if _pressed(m, event, "lane_next"):
			m._handle(m.S.set_focus((m.S.focus_quad + 1) % 4))
			m._rebuild_ui()
			return true
		if _pressed(m, event, "lane_prev"):
			m._handle(m.S.set_focus((m.S.focus_quad + 3) % 4))
			m._rebuild_ui()
			return true
	if m.screen == "base":
		for t in [["tab_base", "base"], ["tab_labs", "labs"], ["tab_cards", "cards"], ["tab_missions", "missions"]]:
			if _pressed(m, event, String(t[0])):
				m.set_tab(String(t[1]))
				return true
	if _pressed(m, event, "toggle_left"):
		m.show_left = not m.show_left
		m._rebuild_ui()
		return true
	if _pressed(m, event, "toggle_right"):
		m.show_right = not m.show_right
		m._rebuild_ui()
		return true
	return false


static func _cancel(m) -> void:
	if m.overlay != "":
		m.set_overlay("")
	elif m.drag_id != "" or m.drag_card >= 0 or m.armed != "":
		m.drag_id = ""
		m.drag_card = -1
		m.armed = ""
		m._rebuild_ui()
	elif m.screen == "run" and m.S != null and m.S.pending_place != "":
		m._handle(m.S.cancel_place())
		m._rebuild_ui()
	elif m.sel >= 0:
		m.sel = -1
		m._rebuild_ui()
	elif m.screen == "run":
		m.set_overlay("pause")
	elif m.screen == "base":
		m.go_menu()


static func hotbar(m, k: int) -> void:
	if m.screen == "run" and m.S != null:
		var S = m.S
		if S.mutation_offer.size() > k:
			m._handle(S.choose_mutation(k))
		elif S.perk_offer.size() > k:
			m._handle(S.choose_perk(k))
		elif S.draft.size() > k:
			m._handle(S.choose_card(k))
		m._rebuild_ui()
	elif m.screen == "base" and m.tab == "base":
		var ids: Array = BuildingDB.all_ids()
		if k < ids.size():
			m.arm(String(ids[k]))


static func move_cursor(m, d: int) -> void:
	var i: int = m.sel
	if i < 0:
		m.sel = TowerState.CORE_SLOT
	else:
		var r: int = i / TowerState.SIDE
		var c: int = i % TowerState.SIDE
		if absi(d) == 1:
			c = clampi(c + d, 0, TowerState.SIDE - 1)
		else:
			r = clampi(r + d / TowerState.SIDE, 0, TowerState.SIDE - 1)
		m.sel = r * TowerState.SIDE + c
	m._rebuild_ui()


static func confirm(m) -> void:
	var i: int = m.sel
	if i < 0:
		return
	if m.screen == "run" and m.S != null:
		if m.S.pending_place != "":
			m._handle(m.S.place(i))
		elif m.S.draft.size() > 0:
			m._handle(m.S.choose_card(0))
		m._rebuild_ui()
	elif m.screen == "base":
		if not BaseMeta.is_unlocked(m.save, i):
			m._base_act(BaseMeta.try_unlock(m.save, i), "place")
		elif m.armed != "" and BaseMeta.slot_of(m.save, i).is_empty():
			m._base_act(BaseMeta.try_place(m.save, i, m.armed), "place")


# ================================================================ tooltips
static func update_tip(m, delta: float) -> void:
	var t: String = tip_at(m, m.mouse_pos)
	if t != m.tip_text:
		m.tip_text = t
		m.tip_t = 0.0
	else:
		m.tip_t += delta
	var delay: float = float((Settings.normalize(m.settings)["controls"] as Dictionary)["tooltip_delay"])
	var show: bool = t != "" and m.tip_t >= delay and m.drag_id == "" and m.drag_card < 0
	m.tipbox.visible = show
	if show:
		m.tip_label.text = t
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
	for host in [m.dui, m.ui]:
		var kids: Array = (host as Control).get_children()
		for k in range(kids.size() - 1, -1, -1):
			var c: Variant = kids[k]
			if c is Control and (c as Control).visible and not (c as Control).is_queued_for_deletion() and (c as Control).tooltip_text != "" and (c as Control).get_global_rect().has_point(p):
				return (c as Control).tooltip_text
	if m.overlay != "" or m.screen == "menu":
		return ""
	if m.field_rect().has_point(p):
		var wp: Vector2 = m.s2w(p)
		if m.S != null and m.screen == "run":
			var best: float = 22.0
			var found: Dictionary = {}
			for e in m.S.enemies:
				var ed: Dictionary = e
				var dd: float = (ed["pos"] as Vector2).distance_to(wp)
				if dd < maxf(best, float(ed["size"])):
					best = dd
					found = ed
			if not found.is_empty():
				return "%s\nHP %d / %d" % [String(found["kind"]).capitalize(), int(ceil(float(found["hp"]))), int(float(found["max_hp"]))]
		var i: int = m.slot_at(wp)
		if i >= 0 and (m.screen == "run" or m.tab == "base"):
			return cell_text(m, i)
	for st in m.stat_tips:
		var a: Array = st
		if (a[0] as Rect2).has_point(p):
			return String(a[1])
	return ""


static func cell_text(m, i: int) -> String:
	var ring: int = BaseMeta.cell_ring(i)
	if i == TowerState.CORE_SLOT:
		return "The Core\nProtect it. Upgrade it with coins on the base, or Overcharge it with cash in a run."
	var id: String = ""
	var lvl: int = 0
	var unlocked: bool = true
	if m.screen == "run" and m.S != null:
		id = m.S.id_at(i)
		lvl = m.S.lvl_at(i)
		unlocked = bool(m.S.unlocked[i])
	else:
		var e: Dictionary = BaseMeta.slot_of(m.save, i)
		unlocked = BaseMeta.is_unlocked(m.save, i)
		if not e.is_empty():
			id = String(e["id"])
			lvl = int(e["lvl"])
	if not unlocked:
		if m.screen == "base":
			return "Locked cell (ring %d)\nUnlock: %d coins%s" % [ring, BaseMeta.unlock_cost(m.save, i), "" if BaseMeta.ring_open(m.save, i) else "\nRing 3 needs Tier 3"]
		return "Locked plot (ring %d)\nUnlock for this run with cash" % ring
	if id == "":
		return "Empty cell (ring %d)\nDrag a building here from the hotbar" % ring
	var d: Dictionary = BuildingDB.get_def(id)
	return "%s  Lv%d  (ring %d)\n%s\nRight-click for Upgrade / Sell" % [String(d["name"]), lvl, ring, String(d["desc"])]


# ===================================================================== draw
## Battlefield backdrop across the whole centre region + lane telegraphs
## (drawn under the world).
static func draw_field(m) -> void:
	var fr: Rect2 = m.field_rect()
	m.draw_rect(fr, Color("161b21"))
	var gc := Color(1, 1, 1, 0.03)
	var x: float = fr.position.x
	while x <= fr.end.x:
		m.draw_line(Vector2(x, fr.position.y), Vector2(x, fr.end.y), gc, 1.0)
		x += 48.0
	var y: float = fr.position.y
	while y <= fr.end.y:
		m.draw_line(Vector2(fr.position.x, y), Vector2(fr.end.x, y), gc, 1.0)
		y += 48.0
	if m.screen == "run" and m.S != null:
		var c: Vector2 = m.w2s(TowerState.CENTER)
		m.draw_arc(c, TowerState.SPAWN_R * m.col_s * m.zoom, 0, TAU, 128, Color(1, 1, 1, 0.07), 2.0)


static func _quad_dir(q: int) -> Vector2:
	return Vector2.from_angle(deg_to_rad(-67.5 + 90.0 * float(q)))


static func _draw_lanes(m) -> void:
	var S = m.S
	var fr: Rect2 = m.field_rect()
	var c: Vector2 = m.w2s(TowerState.CENTER)
	var tele: bool = not S.next_plan.is_empty()
	var quads: Array = (S.next_plan.get("quads", []) as Array) if tele else S.active_quads
	var counts: Dictionary = S.next_plan.get("counts", {}) if tele else S.wave_spawned
	var bd: int = int(S.next_plan.get("boss_dir", -1)) if tele else S.boss_dir
	for q in range(4):
		var dir: Vector2 = _quad_dir(q)
		var inner: Rect2 = fr.grow(-46.0)
		var tx: float = (inner.end.x - c.x) / dir.x if dir.x > 0.0 else (inner.position.x - c.x) / dir.x
		var ty: float = (inner.end.y - c.y) / dir.y if dir.y > 0.0 else (inner.position.y - c.y) / dir.y
		var p: Vector2 = c + dir * minf(tx, ty)
		# keep clear of the centre column's top HUD (wave / HP bars)
		var cx0: float = m.col_pos.x - 40.0
		var cx1: float = m.col_pos.x + m.W * m.col_s + 40.0
		if p.y < m.col_pos.y + 200.0 * m.col_s and p.x > cx0 and p.x < cx1:
			p.x = cx1 if dir.x > 0.0 else cx0
			p.y = c.y + dir.y * absf((p.x - c.x) / dir.x)
			p.y = maxf(p.y, inner.position.y)
		var on: bool = quads.has(q)
		var col: Color = (MAG if bd == q else ENEMY) if on else Color(1, 1, 1, 0.12)
		if on and tele:
			col = Color(col, 0.55 + 0.45 * sin(m.t_anim * 8.0))
		var tip: Vector2 = p - dir * 34.0
		var side: Vector2 = dir.orthogonal() * 20.0
		m.draw_colored_polygon(PackedVector2Array([tip, p + side, p - side]), col)
		if q == S.focus_quad:
			m.draw_arc(p, 30.0, 0, TAU, 32, GEM, 2.0)
		if on:
			var lab: String = "%d%s" % [int(counts.get(q, 0)), " BOSS" if bd == q else ""]
			_t(m, lab, p - dir * 58.0 + Vector2(0, 8), 20, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	if tele:
		var gw: float = m.col_pos.x - fr.position.x - 16.0
		if gw > 120.0:
			var gx: float = fr.position.x + 8.0
			_panel(m, Rect2(gx, fr.position.y + 12, gw, 70), ENEMY, Color(0.16, 0.06, 0.07, 0.92))
			_t(m, "WAVE %d INCOMING" % int(S.next_plan.get("wave", 0)), Vector2(gx + gw * 0.5, fr.position.y + 42), 20, TEXT, HORIZONTAL_ALIGNMENT_CENTER, gw - 12)
			_t(m, "%d lane%s%s" % [quads.size(), "" if quads.size() == 1 else "s", "  ·  BOSS" if bd >= 0 else ""], Vector2(gx + gw * 0.5, fr.position.y + 68), 16, Color(ENEMY.lightened(0.3)), HORIZONTAL_ALIGNMENT_CENTER, gw - 12)


## Desktop chrome over the column view (screen space).
static func draw(m) -> void:
	m.stat_tips = []
	if m.screen == "menu":
		_draw_menu(m)
		if m.overlay in OVERLAYS:
			_draw_overlay(m)
		return
	if m.screen == "run" and m.S != null:
		_draw_lanes(m)
	_draw_ghost(m)
	if m.show_left:
		_draw_left(m)
	if m.show_right:
		_draw_right(m)
	_draw_hud(m)
	m.draw_rect(_hot_rect(m), PANEL)
	m.draw_line(Vector2(0, m.vh - m.HOT_H), Vector2(m.vw, m.vh - m.HOT_H), RUST, 2.0)
	if m.screen == "run" and m.S != null and m.S.draft.is_empty() and m.S.perk_offer.is_empty() and m.S.mutation_offer.is_empty():
		_t(m, "Drafts, perks and mutations appear here  ·  %s/%s/%s pick" % [hint(m, "hotbar_1"), hint(m, "hotbar_2"), hint(m, "hotbar_3")], Vector2(16, m.vh - 10), 14, DIM, HORIZONTAL_ALIGNMENT_LEFT, 700.0)
	if m.screen == "run" and m.S != null and m.S.mutation_offer.size() > 0:
		var fr: Rect2 = m.field_rect()
		var gw: float = m.col_pos.x - fr.position.x - 16.0
		if gw > 120.0:
			_panel(m, Rect2(fr.position.x + 8, fr.position.y + 92, gw, 96), MAG, Color(0.14, 0.05, 0.13, 0.92))
			_t(m, "ENDLESS MUTATION", Vector2(fr.position.x + 8 + gw * 0.5, fr.position.y + 122), 20, MAG.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, gw - 12)
			_wrap(m, "Pick one below. Enemies get stronger, coins +10%.", Vector2(fr.position.x + 20, fr.position.y + 148), 15, TEXT, gw - 24, 2)
	if m.overlay in OVERLAYS:
		_draw_overlay(m)


static func _draw_hud(m) -> void:
	m.draw_rect(_hud_rect(m), PANEL)
	m.draw_line(Vector2(0, m.HUD_H), Vector2(m.vw, m.HUD_H), RUST, 2.0)
	_t(m, "COREHOLD", Vector2(18, 41), 28, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 220.0)
	var x: float = 220.0
	var items: Array = [["icon_coin", Main_fmt(int(m.save["coins"])), GOLD, "Coins — permanent currency for the base, labs and cells"],
		["icon_gem", str(int(m.save["gems"])), GEM, "Gems — card chests and lab rushes"],
		["icon_tier", "Tier %d" % int(m.view_tier), TEXT, "Selected tier (higher tiers: tougher enemies, more coins)"],
		["icon_xp", "Best w%d" % int(m.save["best_wave"]), DIM, "Best wave reached in any tier"]]
	if m.screen == "run" and m.S != null:
		items.remove_at(3)
		items.append(["icon_cash", "$%d" % int(m.S.cash), GREEN, "Cash — this run only; buys upgrades and plots"])
		items.append(["icon_clock", "Wave %d" % int(m.S.wave), TEXT, "Current wave (%s)" % String(m.S.mode)])
		items.append(["icon_speed", "DPS %d" % int(m.S.dps()), ENEMY, "Estimated damage per second of your whole base"])
	for it in items:
		var a: Array = it
		var r := Rect2(x, 10, 170, 40)
		var tx: Texture2D = Art.tex(String(a[0]))
		if tx != null:
			m.draw_texture_rect(tx, Rect2(x, 12, 36, 36), false)
		_t(m, String(a[1]), Vector2(x + 42, 39), 22, a[2], HORIZONTAL_ALIGNMENT_LEFT, 128.0)
		_stat_tip(m, r, String(a[3]))
		x += 168.0
	if m.toast_t > 0.0 and m.toast_text != "" and m.screen != "base":
		var fr: Rect2 = m.field_rect()
		var gx0: float = m.col_pos.x + m.W * m.col_s
		var gw: float = fr.end.x - gx0 - 16.0
		if gw > 120.0:
			var a: float = clampf(m.toast_t * 3.0, 0.0, 1.0)
			_panel(m, Rect2(gx0 + 8, fr.position.y + 12, gw, 64), Color(GOLD, a), Color(0.18, 0.15, 0.08, 0.92 * a))
			_wrap(m, m.toast_text, Vector2(gx0 + 20, fr.position.y + 38), 17, Color(TEXT, a), gw - 24, 2)


static func Main_fmt(v: int) -> String:
	if v >= 1000000:
		return "%.2fM" % (float(v) / 1000000.0)
	if v >= 10000:
		return "%.1fk" % (float(v) / 1000.0)
	return str(v)


static func _draw_left(m) -> void:
	var r: Rect2 = left_rect(m)
	m.draw_rect(r, PANEL)
	m.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), EDGE, 2.0)
	var x: float = r.position.x + 20.0
	var w: float = r.size.x - 40.0
	var y: float = r.position.y + 40.0
	_t(m, "BUILD / INFO", Vector2(x, y), 22, RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
	y += 18.0
	var focus: int = m.sel
	var hov: int = -1
	if m.field_rect().has_point(m.mouse_pos):
		hov = m.slot_at(m.s2w(m.mouse_pos))
	if hov >= 0:
		focus = hov
	if m.screen == "base" and m.armed != "":
		var d0: Dictionary = BuildingDB.get_def(m.armed)
		_panel(m, Rect2(x, y + 6, w, 64), GOLD, PANEL2)
		_t(m, "Armed: %s — click a cell (%s cancels)" % [String(d0["name"]), hint(m, "cancel")], Vector2(x + 12, y + 44), 17, GOLD, HORIZONTAL_ALIGNMENT_LEFT, w - 24)
		y += 80.0
	if focus >= 0:
		var txt: String = cell_text(m, focus)
		var lines: PackedStringArray = txt.split("\n")
		var id: String = ""
		if m.screen == "run" and m.S != null:
			id = m.S.id_at(focus)
		elif not BaseMeta.slot_of(m.save, focus).is_empty():
			id = String(BaseMeta.slot_of(m.save, focus)["id"])
		if focus == TowerState.CORE_SLOT:
			id = "core"
		_panel(m, Rect2(x, y + 6, w, 300), EDGE, PANEL2)
		if id != "":
			var tx: Texture2D = Art.tex(id)
			if tx != null:
				m.draw_texture_rect(tx, Rect2(x + 14, y + 20, 72, 72), false)
		_t(m, lines[0], Vector2(x + 100, y + 50), 22, TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
		var body: String = "\n".join(lines.slice(1))
		_wrap(m, body, Vector2(x + 14, y + 120), 17, DIM, w - 28, 8)
		if m.screen == "base" and id != "" and id != "core":
			var lvl: int = int(BaseMeta.slot_of(m.save, focus).get("lvl", 0))
			_t(m, "Next level: %s coins  ·  cap %d" % [Main_fmt(BaseMeta.upgrade_cost(lvl)), BaseMeta.perm_lvl_cap(m.save)], Vector2(x + 14, y + 290), 16, GOLD, HORIZONTAL_ALIGNMENT_LEFT, w - 28)
		elif m.screen == "run" and m.S != null and id != "":
			_t(m, "Upgrade: $%d" % m.S.upgrade_cost(focus), Vector2(x + 14, y + 290), 16, GREEN, HORIZONTAL_ALIGNMENT_LEFT, w - 28)
		y += 320.0
	else:
		_wrap(m, "Hover a cell for details. Drag buildings from the hotbar onto the base, right-click a cell for Upgrade / Sell, and use the mouse wheel to zoom.", Vector2(x, y + 30), 17, DIM, w, 6)
		y += 150.0
	if m.screen == "base":
		_t(m, "Buildings %d / %d   ·   Land bonus +%d cap" % [BaseMeta.building_count(m.save), BaseMeta.build_cap(m.save), BaseMeta.land_bonus(m.save)], Vector2(x, y + 10), 17, TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
		_stat_tip(m, Rect2(x, y - 10, w, 26), "Build cap = 12 + 2 per tier above 1 (max 40). Every 4 outer cells bought raise the level cap by 1.")
		y += 30.0
	# hotkey legend
	var lh: float = 22.0
	y = maxf(y + 10.0, r.end.y - 84.0 - lh * float(LEGEND.size()) - 16.0)
	_t(m, "HOTKEYS", Vector2(x, y), 16, RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
	for k in LEGEND.size():
		var a: String = LEGEND[k]
		var py: float = y + 22.0 + float(k) * lh
		_t(m, hint(m, a), Vector2(x, py), 15, GOLD, HORIZONTAL_ALIGNMENT_LEFT, 110.0)
		_t(m, String(Keybinds.LABELS.get(a, a)), Vector2(x + 116, py), 15, DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 116.0)


static func _draw_right(m) -> void:
	var r: Rect2 = right_rect(m)
	m.draw_rect(r, PANEL)
	m.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), EDGE, 2.0)
	var x: float = r.position.x + 20.0
	var w: float = r.size.x - 40.0
	var y: float = r.position.y + (150.0 if m.screen == "base" else 40.0)
	if m.screen == "run" and m.S != null:
		var S = m.S
		_t(m, "RUN", Vector2(x, y), 22, RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
		var mode_s: String = String(S.mode).capitalize()
		if not S.modifiers.is_empty():
			mode_s += "  +%d modifiers (coins x%.2f)" % [S.modifiers.size(), float(S.mod_coin)]
		_t(m, mode_s, Vector2(x, y + 30), 17, MAG if S.mode == "endless" else DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
		_t(m, "Buildings %d / cap  ·  Level %d" % [S.building_count(), int(S.level)], Vector2(x, y + 56), 17, TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
		y += 90.0
		_t(m, "LANES", Vector2(x, y), 18, RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
		var tele: bool = not S.next_plan.is_empty()
		for q in range(4):
			var on: bool = (S.next_plan.get("quads", []) as Array).has(q) if tele else S.active_quads.has(q)
			var cnt: int = int((S.next_plan.get("counts", {}) as Dictionary).get(q, 0)) if tele else int(S.wave_spawned.get(q, 0))
			var ly: float = y + 28.0 + float(q) * 28.0
			var wall: String = ""
			if S.walls.has(q):
				var wd: Dictionary = S.walls[q]
				wall = "  wall %d/%d" % [int(wd.get("hp", 0)), int(wd.get("max", 0))]
			_t(m, "%s%s  %s%s" % ["> " if q == S.focus_quad else "  ", String(QUAD_NAMES[q]), ("%d %s" % [cnt, "incoming" if tele else "spawned"]) if on else "quiet", wall], Vector2(x, ly), 17, (ENEMY if on else DIM), HORIZONTAL_ALIGNMENT_LEFT, w)
			_stat_tip(m, Rect2(x, ly - 20, w, 26), "Lane %s. Telegraphs show 3 s before a wave. %s/%s change the lane focus (Lane Beacons)." % [String(QUAD_NAMES[q]), hint(m, "lane_prev"), hint(m, "lane_next")])
		y += 150.0
		_t(m, "ENEMIES ON FIELD", Vector2(x, y), 18, RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
		var kinds: Dictionary = {}
		for e in S.enemies:
			var kd: String = String((e as Dictionary)["kind"])
			kinds[kd] = int(kinds.get(kd, 0)) + 1
		var k2: int = 0
		for kd in kinds.keys():
			var ey: float = y + 30.0 + float(k2 / 2) * 44.0
			var ex: float = x + float(k2 % 2) * (w * 0.5)
			var tx: Texture2D = Art.tex(String(kd))
			if tx != null:
				m.draw_texture_rect(tx, Rect2(ex, ey - 6, 36, 36), false)
			_t(m, "%s x%d" % [String(kd).capitalize(), int(kinds[kd])], Vector2(ex + 42, ey + 18), 16, TEXT, HORIZONTAL_ALIGNMENT_LEFT, w * 0.5 - 46)
			k2 += 1
		y += 40.0 + 44.0 * ceilf(float(k2) / 2.0)
		if not S.mutations_taken.is_empty():
			_t(m, "Mutations: %d (coins x%.2f)" % [S.mutations_taken.size(), S.mutation_coin()], Vector2(x, y + 10), 17, MAG, HORIZONTAL_ALIGNMENT_LEFT, w)
		return
	if m.screen == "base":
		_t(m, "COMMAND", Vector2(x, y), 22, RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
		var st: Dictionary = m.save.get("stats", {})
		var rows: Array = [
			["Runs", str(int(m.save["runs"]))],
			["Highest tier", str(Tiers.highest(m.save))],
			["Perm level cap", str(BaseMeta.perm_lvl_cap(m.save))],
			["Lifetime kills", Main_fmt(int(st.get("kills", 0)))],
			["Achievements", "%d / %d" % [Achievements.unlocked_count(m.save), AchievementDB.ids().size()]],
		]
		for k in rows.size():
			var row: Array = rows[k]
			_t(m, String(row[0]), Vector2(x, y + 36 + k * 30), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, w * 0.6)
			_t(m, String(row[1]), Vector2(x + w, y + 36 + k * 30), 18, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.4)
		y += 200.0
		_t(m, "NEXT RUN", Vector2(x, y), 18, RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
		var mode: String = String(m.run_opts.get("mode", "normal"))
		var mods: Array = m.run_opts.get("modifiers", [])
		_t(m, "%s  ·  Tier %d" % [mode.capitalize(), int(m.view_tier)], Vector2(x, y + 30), 18, MAG if mode == "endless" else TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
		var names: Array = []
		for id in mods:
			names.append(String(ModifierDB.get_def(String(id))["name"]))
		_wrap(m, ("Modifiers: " + ", ".join(names) + "  (coins x%.2f)" % ModifierDB.coin_mult(mods)) if not names.is_empty() else "No challenge modifiers", Vector2(x, y + 50), 16, DIM, w, 3)


static func _draw_ghost(m) -> void:
	var id: String = m.drag_id
	if m.drag_card >= 0 and m.S != null and m.drag_card < m.S.draft.size():
		id = String((m.S.draft[m.drag_card] as Dictionary)["id"])
	if id == "" or m.mouse_pos.distance_to(m.drag_start) <= 12.0:
		return
	var reason: String = "Drop on a cell"
	if m.field_rect().has_point(m.mouse_pos):
		var i: int = m.slot_at(m.s2w(m.mouse_pos))
		if i >= 0:
			reason = place_reason(m, i, id)
			var cs: float = TowerState.CELL * m.col_s * m.zoom
			var cp: Vector2 = m.w2s(TowerState.slot_pos(i))
			var cr := Rect2(cp - Vector2(cs, cs) * 0.5, Vector2(cs, cs))
			m.draw_rect(cr, Color(GREEN, 0.25) if reason == "" else Color(ENEMY, 0.25))
			m.draw_rect(cr, GREEN if reason == "" else ENEMY, false, 3.0)
	var tx: Texture2D = Art.tex(id)
	if tx != null:
		m.draw_texture_rect(tx, Rect2(m.mouse_pos - Vector2(32, 32), Vector2(64, 64)), false, Color(1, 1, 1, 0.8))
	if reason != "":
		_panel(m, Rect2(m.mouse_pos + Vector2(36, -16), Vector2(230, 34)), ENEMY, Color(0.1, 0.05, 0.05, 0.92))
		_t(m, reason, m.mouse_pos + Vector2(48, 8), 17, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 210.0)
	m.set_meta("ghost_reason", reason)


static func _draw_menu(m) -> void:
	var c: Vector2 = Vector2(m.vw * 0.5, 0)
	var tx: Texture2D = Art.tex("core")
	for k in 6:
		var a: float = m.t_anim * 0.2 + float(k) * TAU / 6.0
		m.draw_arc(Vector2(c.x, 190), 120.0 + 24.0 * float(k), a, a + 1.2, 24, Color(RUST, 0.08 + 0.02 * float(k)), 3.0)
	if tx != null:
		m.draw_texture_rect(tx, Rect2(c.x - 64, 90, 128, 128), false)
	_t(m, "COREHOLD", Vector2(c.x, 280), 64, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 900.0)
	_t(m, "PC EDITION  ·  choose a save slot", Vector2(c.x, 316), 20, DIM, HORIZONTAL_ALIGNMENT_CENTER, 900.0)
	var cw: float = 440.0
	var x0: float = floorf((m.vw - (cw * 3.0 + 40.0)) * 0.5)
	var y0: float = 330.0
	for n in [1, 2, 3]:
		var sm: Dictionary = MetaSave.slot_summary(n)
		var x: float = x0 + float(n - 1) * (cw + 20.0)
		var active: bool = MetaSave.active == n
		_panel(m, Rect2(x, y0, cw, 390), RUST if active else EDGE, PANEL)
		var tsv: Texture2D = Art.tex("icon_save")
		if tsv != null:
			m.draw_texture_rect(tsv, Rect2(x + 20, y0 + 22, 44, 44), false)
		_t(m, "SLOT %d%s" % [n, "  (active)" if active else ""], Vector2(x + 76, y0 + 54), 26, TEXT, HORIZONTAL_ALIGNMENT_LEFT, cw - 90)
		if bool(sm.get("exists", false)):
			var pl: int = int(float(sm.get("play_s", 0.0)))
			_t(m, "Tier %d   ·   Best wave %d" % [int(sm["tier"]), int(sm["best_wave"])], Vector2(x + 24, y0 + 120), 20, TEXT, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
			_t(m, "Highest tier %d" % int(sm["best_tier"]), Vector2(x + 24, y0 + 152), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
			_t(m, "Played %dh %02dm" % [pl / 3600, (pl % 3600) / 60], Vector2(x + 24, y0 + 182), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
			if m.confirm_del == n:
				_t(m, "Delete slot %d? This cannot be undone." % n, Vector2(x + 24, y0 + 228), 18, ENEMY, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
		else:
			_t(m, "Empty slot", Vector2(x + 24, y0 + 120), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
			_t(m, "Start a new base here", Vector2(x + 24, y0 + 152), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 48)
	if m.menu_msg != "":
		_t(m, m.menu_msg, Vector2(c.x, m.vh - 40), 20, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 900.0)


static func _draw_overlay(m) -> void:
	if m.overlay == "info":
		var r: Rect2 = info_rect(m)
		var cs: float = TowerState.CELL * m.col_s * m.zoom
		var cp: Vector2 = m.w2s(TowerState.slot_pos(m.info_cell))
		m.draw_rect(Rect2(cp - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), GOLD, false, 3.0)
		_panel(m, r, GOLD, Color(0.1, 0.12, 0.15, 0.97))
		var lines: PackedStringArray = cell_text(m, m.info_cell).split("\n")
		_t(m, lines[0], Vector2(r.position.x + 20, r.position.y + 40), 24, TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40)
		_wrap(m, "\n".join(lines.slice(1)), Vector2(r.position.x + 20, r.position.y + 76), 17, DIM, r.size.x - 40, 6)
		return
	m.draw_rect(Rect2(0, 0, m.vw, m.vh), Color(0, 0, 0, 0.72))
	match String(m.overlay):
		"settings":
			var r2: Rect2 = _modal_rect(m, 1100, 820)
			_panel(m, r2, RUST, PANEL2)
			_t(m, "SETTINGS", Vector2(r2.position.x + 24, r2.position.y + 50), 34, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
			if m.set_tab_id == "controls":
				_t(m, "Action", Vector2(r2.position.x + 40, r2.position.y + 142), 16, DIM, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
				_t(m, "Keyboard / mouse", Vector2(r2.position.x + 460, r2.position.y + 142), 16, DIM, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
				_t(m, "Controller", Vector2(r2.position.x + 780, r2.position.y + 142), 16, DIM, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
				var acts: Array = Keybinds.actions()
				var start: int = m.keymap_page * KEYS_PER_PAGE
				for k in range(start, mini(acts.size(), start + KEYS_PER_PAGE)):
					_t(m, String(Keybinds.LABELS.get(acts[k], acts[k])), Vector2(r2.position.x + 40, r2.position.y + 180 + (k - start) * 50.0), 19, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
				_t(m, "Page %d / %d" % [m.keymap_page + 1, int(ceil(float(acts.size()) / float(KEYS_PER_PAGE)))], Vector2(r2.position.x + 780, r2.end.y - 36), 16, DIM, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
			if m.menu_msg != "":
				_t(m, m.menu_msg, Vector2(r2.position.x + 420, r2.position.y + 50), 18, GOLD, HORIZONTAL_ALIGNMENT_LEFT, 600.0)
		"stats", "history", "achievements":
			var r3: Rect2 = _modal_rect(m, 1240, 860)
			_panel(m, r3, RUST, PANEL2)
			_t(m, String(m.overlay).to_upper(), Vector2(r3.position.x + 24, r3.position.y + 50), 34, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 500.0)
			match String(m.overlay):
				"stats": _draw_stats(m, r3)
				"history": _draw_history(m, r3)
				"achievements": _draw_achievements(m, r3)
		"modes":
			var r4: Rect2 = _modal_rect(m, 1100, 820)
			_panel(m, r4, MAG, PANEL2)
			_t(m, "MODE & CHALLENGES", Vector2(r4.position.x + 24, r4.position.y + 50), 34, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 600.0)
			var mods: Array = m.run_opts.get("modifiers", [])
			_t(m, "Challenge modifiers (coin rewards stack, capped at x%.1f)" % ModifierDB.COIN_CAP, Vector2(r4.position.x + 40, r4.position.y + 225), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, 800.0)
			_t(m, "Coin multiplier: x%.2f" % ModifierDB.coin_mult(mods), Vector2(r4.position.x + 40, r4.position.y + 480), 26, GOLD, HORIZONTAL_ALIGNMENT_LEFT, 600.0)
			_wrap(m, "Endless: no wave cap, a mutation pick every 25 waves (+10% coins each), banks coins x0.8 and keeps its own best. Modifiers apply to both modes.", Vector2(r4.position.x + 40, r4.position.y + 530), 17, DIM, 1000.0, 3)


static func _draw_stats(m, r: Rect2) -> void:
	var st: Dictionary = Stats._st(m.save)
	var x: float = r.position.x + 40.0
	var y: float = r.position.y + 170.0
	var bm: Dictionary = st.get("best_by_mode", {})
	var ps: int = int(float(st.get("play_s", 0.0)))
	var rows: Array = [
		["Runs", str(int(st["runs"]))], ["Waves cleared", Main_fmt(int(st["waves"]))],
		["Kills", Main_fmt(int(st["kills"]))], ["Bosses killed", str(int(st["bosses"]))],
		["Coins earned", Main_fmt(int(st["coins_earned"]))], ["Coins spent", Main_fmt(int(st["coins_spent"]))],
		["Play time", "%dh %02dm" % [ps / 3600, (ps % 3600) / 60]], ["Best DPS", str(int(float(st.get("dps_best", 0.0))))],
		["Best wave (normal)", str(int(bm.get("normal", 0)))], ["Best wave (endless)", str(int(bm.get("endless", 0)))],
		["Best wave (challenge)", str(int(bm.get("challenge", 0)))], ["History entries", str((m.save.get("history", []) as Array).size())],
	]
	for k in rows.size():
		var row: Array = rows[k]
		var cx: float = x + float(k % 2) * 580.0
		var cy: float = y + float(k / 2) * 48.0
		_t(m, String(row[0]), Vector2(cx, cy), 22, DIM, HORIZONTAL_ALIGNMENT_LEFT, 340.0)
		_t(m, String(row[1]), Vector2(cx + 520, cy), 22, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 180.0)
	var fav: Array = Stats.favourite(m.save, 3)
	var fy: float = y + 330.0
	_t(m, "Most placed buildings", Vector2(x, fy), 20, RUST, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
	for k in fav.size():
		var fid: String = String(fav[k])
		var tx: Texture2D = Art.tex(fid)
		if tx != null:
			m.draw_texture_rect(tx, Rect2(x + k * 260.0, fy + 16, 56, 56), false)
		_t(m, String(BuildingDB.get_def(fid).get("name", fid)), Vector2(x + 64 + k * 260.0, fy + 52), 18, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 190.0)
	var kk: Dictionary = st.get("kills_by_kind", {})
	var ky: float = fy + 110.0
	_t(m, "Kills by enemy", Vector2(x, ky), 20, RUST, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
	var j: int = 0
	for kd in kk.keys():
		_t(m, "%s  %s" % [String(kd).capitalize(), Main_fmt(int(kk[kd]))], Vector2(x + float(j % 4) * 290.0, ky + 34 + float(j / 4) * 30.0), 18, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 280.0)
		j += 1


static func _draw_history(m, r: Rect2) -> void:
	var h: Array = m.save.get("history", [])
	var x: float = r.position.x + 40.0
	var y: float = r.position.y + 150.0
	var hx: Array = [0.0, 110.0, 190.0, 420.0, 520.0, 640.0, 760.0]
	var hn: Array = ["Run", "Tier", "Mode", "Wave", "Coins", "Time", "Seed"]
	for c in hn.size():
		_t(m, String(hn[c]), Vector2(x + float(hx[c]), y), 17, DIM, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
	if h.is_empty():
		_t(m, "No runs yet — finish a run to see it here.", Vector2(x, y + 50), 20, DIM, HORIZONTAL_ALIGNMENT_LEFT, 800.0)
	for k in mini(12, h.size()):
		var e: Dictionary = h[h.size() - 1 - k]
		var ry: float = y + 40.0 + float(k) * 52.0
		var mode: String = String(e["mode"]) + ("+%d" % (e["modifiers"] as Array).size() if not (e["modifiers"] as Array).is_empty() else "")
		var cols: Array = ["#%d" % (h.size() - k), "T%d" % int(e["tier"]), mode, "w%d" % int(e["wave"]), Main_fmt(int(e["coins"])), "%dm%02ds" % [int(float(e["duration_s"])) / 60, int(float(e["duration_s"])) % 60], str(int(e["seed"]))]
		var xs: Array = [0.0, 110.0, 190.0, 420.0, 520.0, 640.0, 760.0]
		for c in cols.size():
			_t(m, String(cols[c]), Vector2(x + float(xs[c]), ry), 19, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 220.0)


static func _draw_achievements(m, r: Rect2) -> void:
	var ids: Array = AchievementDB.ids()
	var x: float = r.position.x + 30.0
	var y: float = r.position.y + 140.0
	var cw: float = (r.size.x - 60.0) / 3.0
	_t(m, "%d / %d unlocked" % [Achievements.unlocked_count(m.save), ids.size()], Vector2(r.end.x - 330, r.position.y + 50), 20, GOLD, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
	var tx: Texture2D = Art.tex("icon_trophy")
	for k in ids.size():
		var id: String = ids[k]
		var d: Dictionary = AchievementDB.get_def(id)
		var on: bool = Achievements.is_unlocked(m.save, id)
		var cx: float = x + float(k % 3) * cw
		var cy: float = y + float(k / 3) * 74.0
		_panel(m, Rect2(cx, cy, cw - 10, 66), GOLD if on else EDGE, PANEL if on else Color("1e242b"))
		if tx != null:
			m.draw_texture_rect(tx, Rect2(cx + 10, cy + 13, 40, 40), false, Color.WHITE if on else Color(1, 1, 1, 0.25))
		_t(m, String(d["name"]), Vector2(cx + 60, cy + 28), 19, TEXT if on else DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 80)
		_t(m, String(d["desc"]), Vector2(cx + 60, cy + 52), 15, DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 80)
