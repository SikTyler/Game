extends RefCounted
## Remappable InputMap actions (PC_SPEC §1.3 keyboard/mouse, §1.4 controller).
## Static, no autoload. ensure_actions() registers every action with its
## defaults; apply_map()/to_map() round-trip bindings as
## {action: [event dicts]} for user://settings.cfg (never in a save slot).
## Patterns ported from nathanhoad/godot_input_helper (MIT: serialise,
## swap-if-taken rebinding) and godot-demo-projects gui/input_mapping (MIT).

const DEADZONE: float = 0.5
const KEY_SLOTS: int = 2   # key/mouse bindings per action
const PAD_SLOTS: int = 1   # joypad bindings per action

## Shorthand: "k:<KEY>[+shift|+ctrl|+alt]", "m:<button>", "jb:<button>", "ja:<axis>:<+1|-1>".
const DEFAULTS: Dictionary = {
	"pause":         ["k:%d" % KEY_SPACE, "jb:%d" % JOY_BUTTON_START],
	"speed_down":    ["k:%d" % KEY_F, "ja:%d:1" % JOY_AXIS_TRIGGER_LEFT],
	"speed_up":      ["k:%d" % KEY_G, "ja:%d:1" % JOY_AXIS_TRIGGER_RIGHT],
	"hotbar_1":      ["k:%d" % KEY_1], "hotbar_2": ["k:%d" % KEY_2], "hotbar_3": ["k:%d" % KEY_3],
	"hotbar_4":      ["k:%d" % KEY_4], "hotbar_5": ["k:%d" % KEY_5], "hotbar_6": ["k:%d" % KEY_6],
	"hotbar_7":      ["k:%d" % KEY_7], "hotbar_8": ["k:%d" % KEY_8], "hotbar_9": ["k:%d" % KEY_9],
	"hotbar_10":     ["k:%d" % KEY_0],
	"hotbar_prev":   ["jb:%d" % JOY_BUTTON_LEFT_SHOULDER],
	"hotbar_next":   ["jb:%d" % JOY_BUTTON_RIGHT_SHOULDER],
	"ability_1":     ["k:%d" % KEY_Q], "ability_2": ["k:%d" % KEY_W],
	"ability_3":     ["k:%d" % KEY_E], "ability_4": ["k:%d" % KEY_R],
	"track_1":       ["k:%d+shift" % KEY_1], "track_2": ["k:%d+shift" % KEY_2], "track_3": ["k:%d+shift" % KEY_3],
	"track_4":       ["k:%d+shift" % KEY_4], "track_5": ["k:%d+shift" % KEY_5],
	"reroll":        ["k:%d" % KEY_T],
	"banish":        ["k:%d" % KEY_N],
	"upgrade":       ["k:%d" % KEY_U],
	"sell":          ["k:%d" % KEY_X, "k:%d" % KEY_DELETE, "jb:%d" % JOY_BUTTON_Y],
	"confirm":       ["k:%d" % KEY_ENTER, "jb:%d" % JOY_BUTTON_A],
	"cancel":        ["k:%d" % KEY_ESCAPE, "jb:%d" % JOY_BUTTON_B],
	"info":          ["m:%d" % MOUSE_BUTTON_RIGHT, "jb:%d" % JOY_BUTTON_X],
	"toggle_left":   ["k:%d" % KEY_TAB],
	"toggle_right":  ["k:%d+shift" % KEY_TAB],
	"tab_base":      ["k:%d" % KEY_B], "tab_labs": ["k:%d" % KEY_L],
	"tab_cards":     ["k:%d" % KEY_C], "tab_missions": ["k:%d" % KEY_M],
	"tab_bay":       ["k:%d" % KEY_K], "tab_crates": ["k:%d" % KEY_J],
	"tab_outpost":   ["k:%d" % KEY_O], "tab_reforge": ["k:%d" % KEY_Y],
	"tab_stats":     ["k:%d" % KEY_H, "jb:%d" % JOY_BUTTON_BACK],
	"retry":         ["k:%d+ctrl" % KEY_R],
	"fullscreen":    ["k:%d" % KEY_F11, "k:%d+alt" % KEY_ENTER],
	"screenshot":    ["k:%d" % KEY_F12],
	"zoom_in":       ["m:%d" % MOUSE_BUTTON_WHEEL_UP],
	"zoom_out":      ["m:%d" % MOUSE_BUTTON_WHEEL_DOWN],
	"cursor_up":     ["k:%d" % KEY_UP, "ja:%d:-1" % JOY_AXIS_LEFT_Y],
	"cursor_down":   ["k:%d" % KEY_DOWN, "ja:%d:1" % JOY_AXIS_LEFT_Y],
	"cursor_left":   ["k:%d" % KEY_LEFT, "ja:%d:-1" % JOY_AXIS_LEFT_X],
	"cursor_right":  ["k:%d" % KEY_RIGHT, "ja:%d:1" % JOY_AXIS_LEFT_X],
	"modifier_bulk": ["k:%d" % KEY_SHIFT],
}

## Display order + labels for the Controls tab of the settings menu.
const LABELS: Dictionary = {
	"pause": "Pause / resume", "speed_down": "Speed down", "speed_up": "Speed up",
	"hotbar_1": "Special 1", "hotbar_2": "Special 2", "hotbar_3": "Special 3", "hotbar_4": "Special 4",
	"hotbar_5": "Hotbar 5", "hotbar_6": "Hotbar 6", "hotbar_7": "Hotbar 7", "hotbar_8": "Hotbar 8",
	"hotbar_9": "Hotbar 9", "hotbar_10": "Hotbar 10", "hotbar_prev": "Hotbar previous", "hotbar_next": "Hotbar next",
	"ability_1": "Draft pick 1", "ability_2": "Draft pick 2", "ability_3": "Draft pick 3", "ability_4": "Draft pick 4 / Outpost rotate",
	"track_1": "Core track: Damage", "track_2": "Core track: Rate", "track_3": "Core track: Range", "track_4": "Core track: Eco", "track_5": "Core track: Armor",
	"reroll": "Reroll draft", "banish": "Banish mode (draft)",
	"upgrade": "Upgrade (Outpost / Core)", "sell": "Demolish / salvage", "confirm": "Place / confirm", "cancel": "Cancel / back", "info": "Cell info",
	"toggle_left": "Toggle left panel", "toggle_right": "Toggle right panel",
	"tab_base": "Play", "tab_labs": "Research", "tab_cards": "Cards", "tab_missions": "Missions / Outpost move", "tab_stats": "Stats / history",
	"tab_bay": "Core Bay", "tab_crates": "Crates", "tab_outpost": "Outpost", "tab_reforge": "Reforge",
	"retry": "Play again (new run)",
	"fullscreen": "Toggle fullscreen", "screenshot": "Screenshot", "zoom_in": "Zoom in", "zoom_out": "Zoom out",
	"cursor_up": "Cursor up", "cursor_down": "Cursor down", "cursor_left": "Cursor left", "cursor_right": "Cursor right",
	"modifier_bulk": "Bulk modifier",
}


static func actions() -> Array:
	return DEFAULTS.keys()


static func is_pad(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


static func is_kbm(ev: InputEvent) -> bool:
	return ev is InputEventKey or ev is InputEventMouseButton


static func _parse(code: String) -> InputEvent:
	var parts: PackedStringArray = code.split(":")
	match parts[0]:
		"k":
			var mods: PackedStringArray = parts[1].split("+")
			var k: InputEventKey = InputEventKey.new()
			k.keycode = int(mods[0]) as Key
			k.shift_pressed = mods.has("shift")
			k.ctrl_pressed = mods.has("ctrl")
			k.alt_pressed = mods.has("alt")
			return k
		"m":
			var m: InputEventMouseButton = InputEventMouseButton.new()
			m.button_index = int(parts[1]) as MouseButton
			return m
		"jb":
			var b: InputEventJoypadButton = InputEventJoypadButton.new()
			b.button_index = int(parts[1]) as JoyButton
			b.device = -1
			return b
		"ja":
			var a: InputEventJoypadMotion = InputEventJoypadMotion.new()
			a.axis = int(parts[1]) as JoyAxis
			a.axis_value = float(parts[2])
			a.device = -1
			return a
	return null


static func default_events(action: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for c in DEFAULTS.get(action, []):
		var e: InputEvent = _parse(String(c))
		if e != null:
			out.append(e)
	return out


# ------------------------------------------------------------- serialise
static func event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k: InputEventKey = ev
		var code: int = int(k.keycode) if k.keycode != KEY_NONE else int(k.physical_keycode)
		return {"type": "key", "keycode": code, "shift": k.shift_pressed, "ctrl": k.ctrl_pressed, "alt": k.alt_pressed}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button": int((ev as InputEventMouseButton).button_index)}
	if ev is InputEventJoypadButton:
		return {"type": "joy_button", "button": int((ev as InputEventJoypadButton).button_index)}
	if ev is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = ev
		return {"type": "joy_axis", "axis": int(jm.axis), "value": 1.0 if jm.axis_value >= 0.0 else -1.0}
	return {}


static func dict_to_event(d: Dictionary) -> InputEvent:
	match String(d.get("type", "")):
		"key":
			var k: InputEventKey = InputEventKey.new()
			k.keycode = int(d.get("keycode", 0)) as Key
			k.shift_pressed = bool(d.get("shift", false))
			k.ctrl_pressed = bool(d.get("ctrl", false))
			k.alt_pressed = bool(d.get("alt", false))
			return k
		"mouse":
			var m: InputEventMouseButton = InputEventMouseButton.new()
			m.button_index = int(d.get("button", 1)) as MouseButton
			return m
		"joy_button":
			var b: InputEventJoypadButton = InputEventJoypadButton.new()
			b.button_index = int(d.get("button", 0)) as JoyButton
			b.device = -1
			return b
		"joy_axis":
			var a: InputEventJoypadMotion = InputEventJoypadMotion.new()
			a.axis = int(d.get("axis", 0)) as JoyAxis
			a.axis_value = 1.0 if float(d.get("value", 1.0)) >= 0.0 else -1.0
			a.device = -1
			return a
	return null


static func same(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	return event_to_dict(a) == event_to_dict(b)


# ------------------------------------------------------------- InputMap
## Register every action (idempotent). Existing bindings are kept unless
## reset is true.
static func ensure_actions(deadzone: float = DEADZONE, reset: bool = false) -> void:
	for a in DEFAULTS.keys():
		var action: String = String(a)
		if not InputMap.has_action(action):
			InputMap.add_action(action, deadzone)
			reset_action(action)
		else:
			InputMap.action_set_deadzone(action, deadzone)
			if reset:
				reset_action(action)


static func set_deadzone(dz: float) -> void:
	for a in DEFAULTS.keys():
		if InputMap.has_action(String(a)):
			InputMap.action_set_deadzone(String(a), clampf(dz, 0.05, 0.95))


static func reset_action(action: String) -> void:
	InputMap.action_erase_events(action)
	for e in default_events(action):
		InputMap.action_add_event(action, e)


static func reset_all() -> void:
	for a in DEFAULTS.keys():
		reset_action(String(a))


static func events_for(action: String, pad: bool) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		var ev: InputEvent = e
		if is_pad(ev) == pad:
			out.append(ev)
	return out


## {action: [event dicts]} for every remappable action.
static func to_map() -> Dictionary:
	var out: Dictionary = {}
	for a in DEFAULTS.keys():
		var arr: Array = []
		if InputMap.has_action(String(a)):
			for e in InputMap.action_get_events(String(a)):
				var d: Dictionary = event_to_dict(e)
				if not d.is_empty():
					arr.append(d)
		out[String(a)] = arr
	return out


## Apply a stored map; unknown actions and malformed events are ignored,
## actions absent from the map keep their defaults.
static func apply_map(map: Dictionary) -> void:
	ensure_actions()
	for a in map.keys():
		var action: String = String(a)
		if not DEFAULTS.has(action) or not (map[a] is Array):
			continue
		InputMap.action_erase_events(action)
		for d in map[a]:
			if d is Dictionary:
				var ev: InputEvent = dict_to_event(d)
				if ev != null:
					InputMap.action_add_event(action, ev)


## Which remappable action already uses `ev` (excluding `except`), or "".
static func action_using(ev: InputEvent, except: String = "") -> String:
	for a in DEFAULTS.keys():
		var action: String = String(a)
		if action == except or not InputMap.has_action(action):
			continue
		for e in InputMap.action_get_events(action):
			if same(e, ev):
				return action
	return ""


## Bind `ev` into slot `idx` of the action's key (or pad) bindings. If another
## action already uses it, that action receives the binding being replaced
## (swap-if-taken, input_helper pattern). Returns the action swapped with, or "".
static func rebind(action: String, idx: int, ev: InputEvent) -> String:
	if not InputMap.has_action(action) or ev == null:
		return ""
	var pad: bool = is_pad(ev)
	var cur: Array[InputEvent] = events_for(action, pad)
	var old: InputEvent = cur[idx] if idx >= 0 and idx < cur.size() else null
	var other: String = action_using(ev, action)
	if other != "":
		for e in InputMap.action_get_events(other):
			if same(e, ev):
				InputMap.action_erase_event(other, e)
		if old != null:
			InputMap.action_add_event(other, old)
	if old != null:
		InputMap.action_erase_event(action, old)
	# Drop an exact duplicate already on this action.
	for e in InputMap.action_get_events(action):
		if same(e, ev):
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, ev)
	var cap: int = PAD_SLOTS if pad else KEY_SLOTS
	var now_evs: Array[InputEvent] = events_for(action, pad)
	while now_evs.size() > cap:
		InputMap.action_erase_event(action, now_evs[0])
		now_evs.remove_at(0)
	return other


static func unbind(action: String, idx: int, pad: bool) -> void:
	var cur: Array[InputEvent] = events_for(action, pad)
	if idx >= 0 and idx < cur.size():
		InputMap.action_erase_event(action, cur[idx])


# ------------------------------------------------------------- labels/glyphs
static func label_for(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k: InputEventKey = ev
		var s: String = OS.get_keycode_string(k.keycode if k.keycode != KEY_NONE else k.physical_keycode)
		if k.alt_pressed:
			s = "Alt+" + s
		if k.shift_pressed:
			s = "Shift+" + s
		if k.ctrl_pressed:
			s = "Ctrl+" + s
		return s
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
		return "Mouse %d" % int((ev as InputEventMouseButton).button_index)
	if ev is InputEventJoypadButton:
		return String(PAD_NAMES.get(int((ev as InputEventJoypadButton).button_index), "Pad %d" % int((ev as InputEventJoypadButton).button_index)))
	if ev is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = ev
		return String(AXIS_NAMES.get(int(jm.axis), "Axis %d" % int(jm.axis))) + ("+" if jm.axis_value >= 0.0 else "-")
	return "?"


static func hint(action: String, pad: bool = false) -> String:
	var evs: Array[InputEvent] = events_for(action, pad)
	return label_for(evs[0]) if not evs.is_empty() else ""


const PAD_NAMES: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "View",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down", JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
}
const AXIS_NAMES: Dictionary = {
	JOY_AXIS_LEFT_X: "LS X", JOY_AXIS_LEFT_Y: "LS Y", JOY_AXIS_RIGHT_X: "RS X", JOY_AXIS_RIGHT_Y: "RS Y",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}

## Glyph file stems per pad style (art/glyphs/<style>/<stem>.png, Xelu CC0).
const PAD_GLYPH: Dictionary = {
	"xbox": {JOY_BUTTON_A: "a", JOY_BUTTON_B: "b", JOY_BUTTON_X: "x", JOY_BUTTON_Y: "y", JOY_BUTTON_LEFT_SHOULDER: "lb", JOY_BUTTON_RIGHT_SHOULDER: "rb", JOY_BUTTON_START: "menu", JOY_BUTTON_BACK: "view", JOY_BUTTON_DPAD_UP: "dpad_up", JOY_BUTTON_DPAD_DOWN: "dpad_down", JOY_BUTTON_DPAD_LEFT: "dpad_left", JOY_BUTTON_DPAD_RIGHT: "dpad_right", JOY_BUTTON_LEFT_STICK: "l_stick_click", JOY_BUTTON_RIGHT_STICK: "r_stick_click"},
	"ps5": {JOY_BUTTON_A: "cross", JOY_BUTTON_B: "circle", JOY_BUTTON_X: "square", JOY_BUTTON_Y: "triangle", JOY_BUTTON_LEFT_SHOULDER: "l1", JOY_BUTTON_RIGHT_SHOULDER: "r1", JOY_BUTTON_START: "options", JOY_BUTTON_BACK: "share", JOY_BUTTON_DPAD_UP: "dpad_up", JOY_BUTTON_DPAD_DOWN: "dpad_down", JOY_BUTTON_DPAD_LEFT: "dpad_left", JOY_BUTTON_DPAD_RIGHT: "dpad_right", JOY_BUTTON_LEFT_STICK: "l_stick_click", JOY_BUTTON_RIGHT_STICK: "r_stick_click"},
	"steamdeck": {JOY_BUTTON_A: "a", JOY_BUTTON_B: "b", JOY_BUTTON_X: "x", JOY_BUTTON_Y: "y", JOY_BUTTON_LEFT_SHOULDER: "l1", JOY_BUTTON_RIGHT_SHOULDER: "r1", JOY_BUTTON_START: "menu", JOY_BUTTON_BACK: "dots", JOY_BUTTON_DPAD_UP: "dpad_up", JOY_BUTTON_DPAD_DOWN: "dpad_down", JOY_BUTTON_DPAD_LEFT: "dpad_left", JOY_BUTTON_DPAD_RIGHT: "dpad_right", JOY_BUTTON_LEFT_STICK: "l_stick_click", JOY_BUTTON_RIGHT_STICK: "r_stick_click"},
}
const AXIS_GLYPH: Dictionary = {
	"xbox": {JOY_AXIS_LEFT_X: "l_stick", JOY_AXIS_LEFT_Y: "l_stick", JOY_AXIS_RIGHT_X: "r_stick", JOY_AXIS_RIGHT_Y: "r_stick", JOY_AXIS_TRIGGER_LEFT: "lt", JOY_AXIS_TRIGGER_RIGHT: "rt"},
	"ps5": {JOY_AXIS_LEFT_X: "l_stick", JOY_AXIS_LEFT_Y: "l_stick", JOY_AXIS_RIGHT_X: "r_stick", JOY_AXIS_RIGHT_Y: "r_stick", JOY_AXIS_TRIGGER_LEFT: "l2", JOY_AXIS_TRIGGER_RIGHT: "r2"},
	"steamdeck": {JOY_AXIS_LEFT_X: "l_stick", JOY_AXIS_LEFT_Y: "l_stick", JOY_AXIS_RIGHT_X: "r_stick", JOY_AXIS_RIGHT_Y: "r_stick", JOY_AXIS_TRIGGER_LEFT: "l2", JOY_AXIS_TRIGGER_RIGHT: "r2"},
}
const MOUSE_GLYPH: Dictionary = {
	MOUSE_BUTTON_LEFT: "left", MOUSE_BUTTON_RIGHT: "right", MOUSE_BUTTON_MIDDLE: "middle",
	MOUSE_BUTTON_WHEEL_UP: "wheel_up", MOUSE_BUTTON_WHEEL_DOWN: "wheel_down",
}
const KEY_GLYPH: Dictionary = {
	KEY_SPACE: "space", KEY_ESCAPE: "esc", KEY_ENTER: "enter", KEY_TAB: "tab", KEY_DELETE: "del",
	KEY_SHIFT: "shift", KEY_CTRL: "ctrl", KEY_ALT: "alt", KEY_BACKSPACE: "backspace",
	KEY_UP: "arrow_up", KEY_DOWN: "arrow_down", KEY_LEFT: "arrow_left", KEY_RIGHT: "arrow_right",
	KEY_HOME: "home", KEY_END: "end", KEY_PAGEUP: "page_up", KEY_PAGEDOWN: "page_down", KEY_INSERT: "insert",
}


## res:// path of the glyph PNG for an event ("" when there is none).
## style: "xbox" | "ps5" | "steamdeck" for pads (Auto resolves via pad_style()).
static func glyph_path(ev: InputEvent, style: String = "xbox") -> String:
	var stem: String = ""
	var dir: String = ""
	if ev is InputEventKey:
		var k: InputEventKey = ev
		var code: Key = k.keycode if k.keycode != KEY_NONE else k.physical_keycode
		dir = "key"
		if KEY_GLYPH.has(code):
			stem = String(KEY_GLYPH[code])
		elif code >= KEY_F1 and code <= KEY_F12:
			stem = "f%d" % (int(code) - int(KEY_F1) + 1)
		elif (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9):
			stem = OS.get_keycode_string(code).to_lower()
	elif ev is InputEventMouseButton:
		dir = "mouse"
		stem = String(MOUSE_GLYPH.get(int((ev as InputEventMouseButton).button_index), ""))
	elif ev is InputEventJoypadButton:
		dir = style if PAD_GLYPH.has(style) else "xbox"
		stem = String((PAD_GLYPH[dir] as Dictionary).get(int((ev as InputEventJoypadButton).button_index), ""))
	elif ev is InputEventJoypadMotion:
		dir = style if AXIS_GLYPH.has(style) else "xbox"
		stem = String((AXIS_GLYPH[dir] as Dictionary).get(int((ev as InputEventJoypadMotion).axis), ""))
	if stem == "":
		return ""
	return "res://art/glyphs/%s/%s.png" % [dir, stem]


## Pad glyph style from a joypad name (Auto mode).
static func pad_style(joy_name: String) -> String:
	var n: String = joy_name.to_lower()
	if n.contains("steam") or n.contains("deck"):
		return "steamdeck"
	if n.contains("ps5") or n.contains("dualsense") or n.contains("ps4") or n.contains("dualshock") or n.contains("playstation") or n.contains("sony"):
		return "ps5"
	return "xbox"
