extends RefCounted
## Global PC settings (PC_SPEC §6). Static, no autoload. Stored in a
## ConfigFile at user://settings.cfg (user://dev/ in harness and dev runs,
## see MetaSave.root()), never inside a save slot. Patterns
## ported from Maaack/Godot-Game-Template app_settings.gd (MIT) and the
## godot-demo-projects window_management / multiple_resolutions demos (MIT).
##
## A settings value is a plain Dictionary {section: {key: value}}; load()
## always returns a normalised copy, so callers never see missing keys.

const Keybinds := preload("res://Keybinds.gd")
const MetaSave := preload("res://MetaSave.gd")

const VERSION: int = 1

const MODES: Array = ["windowed", "borderless", "fullscreen"]
const VSYNC: Array = ["off", "on", "adaptive"]
const FPS_CAPS: Array = [30, 60, 120, 144, 165, 240, 0]   # 0 = unlimited
const RESOLUTIONS: Array = [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const BUSES: Array = ["Master", "Music", "SFX", "UI"]
const DMG_NUMBERS: Array = ["off", "compact", "full"]
const GORE: Array = ["off", "low", "full"]
const GLYPHS: Array = ["auto", "xbox", "ps5", "steamdeck"]
const COLORBLIND: Array = ["off", "deuteranopia", "protanopia", "tritanopia"]
const MIN_WINDOW: Vector2i = Vector2i(1280, 720)
const UI_SCALE_MIN: float = 0.75
const UI_SCALE_MAX: float = 1.5

const DEFAULTS: Dictionary = {
	"video": {"mode": "windowed", "resolution": Vector2i(1920, 1080), "monitor": -1, "vsync": "on", "fps_cap": 0,
		"ui_scale": 1.0, "shake": true, "dmg_numbers": "full", "reduce_motion": false, "gore": "low"},
	"audio": {"Master": 0.8, "Music": 0.7, "SFX": 0.9, "UI": 0.8, "mute": false, "mute_unfocused": true},
	"controls": {"deadzone": 0.5, "tooltip_delay": 0.4, "edge_pan": false, "invert_zoom": false, "glyphs": "auto"},
	"gameplay": {"pause_on_draft": false, "pause_on_focus_loss": true, "confirm_sell": false, "default_speed": 1.0,
		"colorblind": "off", "language": "en"},
	"keybinds": {},   # {action: [event dicts]}; empty = defaults
}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


static func _pick(v: Variant, allowed: Array, fallback: Variant) -> Variant:
	return v if allowed.has(v) else fallback


## Coerce any (possibly hand-edited / older) dictionary into a valid one.
static func normalize(src: Dictionary) -> Dictionary:
	var d: Dictionary = defaults()
	var v_in: Dictionary = src.get("video", {}) if src.get("video", {}) is Dictionary else {}
	var v: Dictionary = d["video"]
	v["mode"] = _pick(String(v_in.get("mode", v["mode"])), MODES, v["mode"])
	var res: Variant = v_in.get("resolution", v["resolution"])
	if res is Vector2i and (res as Vector2i).x >= 640 and (res as Vector2i).y >= 360:
		v["resolution"] = res
	elif res is Vector2 and (res as Vector2).x >= 640.0 and (res as Vector2).y >= 360.0:
		v["resolution"] = Vector2i(res as Vector2)
	v["monitor"] = int(v_in.get("monitor", -1))
	v["vsync"] = _pick(String(v_in.get("vsync", v["vsync"])), VSYNC, v["vsync"])
	v["fps_cap"] = _pick(int(v_in.get("fps_cap", v["fps_cap"])), FPS_CAPS, 0)
	v["ui_scale"] = clampf(snappedf(float(v_in.get("ui_scale", 1.0)), 0.05), UI_SCALE_MIN, UI_SCALE_MAX)
	v["shake"] = bool(v_in.get("shake", true))
	v["dmg_numbers"] = _pick(String(v_in.get("dmg_numbers", "full")), DMG_NUMBERS, "full")
	v["reduce_motion"] = bool(v_in.get("reduce_motion", false))
	v["gore"] = _pick(String(v_in.get("gore", "low")), GORE, "low")
	var a_in: Dictionary = src.get("audio", {}) if src.get("audio", {}) is Dictionary else {}
	var a: Dictionary = d["audio"]
	for b in BUSES:
		a[b] = clampf(float(a_in.get(b, a[b])), 0.0, 1.0)
	a["mute"] = bool(a_in.get("mute", false))
	a["mute_unfocused"] = bool(a_in.get("mute_unfocused", true))
	var c_in: Dictionary = src.get("controls", {}) if src.get("controls", {}) is Dictionary else {}
	var c: Dictionary = d["controls"]
	c["deadzone"] = clampf(float(c_in.get("deadzone", 0.5)), 0.05, 0.95)
	c["tooltip_delay"] = clampf(float(c_in.get("tooltip_delay", 0.4)), 0.0, 2.0)
	c["edge_pan"] = bool(c_in.get("edge_pan", false))
	c["invert_zoom"] = bool(c_in.get("invert_zoom", false))
	c["glyphs"] = _pick(String(c_in.get("glyphs", "auto")), GLYPHS, "auto")
	var g_in: Dictionary = src.get("gameplay", {}) if src.get("gameplay", {}) is Dictionary else {}
	var g: Dictionary = d["gameplay"]
	g["pause_on_draft"] = bool(g_in.get("pause_on_draft", false))
	g["pause_on_focus_loss"] = bool(g_in.get("pause_on_focus_loss", true))
	g["confirm_sell"] = bool(g_in.get("confirm_sell", false))
	g["default_speed"] = clampf(float(g_in.get("default_speed", 1.0)), 0.5, 4.0)
	g["colorblind"] = _pick(String(g_in.get("colorblind", "off")), COLORBLIND, "off")
	g["language"] = "en"
	var k_in: Variant = src.get("keybinds", {})
	var kb: Dictionary = {}
	if k_in is Dictionary:
		for act in (k_in as Dictionary).keys():
			if Keybinds.DEFAULTS.has(String(act)) and (k_in as Dictionary)[act] is Array:
				var evs: Array = []
				for e in (k_in as Dictionary)[act]:
					if e is Dictionary and Keybinds.dict_to_event(e) != null:
						evs.append(Keybinds.event_to_dict(Keybinds.dict_to_event(e)))
				kb[String(act)] = evs
	d["keybinds"] = kb
	return d


# ------------------------------------------------------------- persistence
static func path() -> String:
	return MetaSave.root() + "settings.cfg"


static func write(s: Dictionary, file: String = "") -> Error:
	var cf: ConfigFile = ConfigFile.new()
	var n: Dictionary = normalize(s)
	cf.set_value("meta", "version", VERSION)
	for sec in ["video", "audio", "controls", "gameplay"]:
		var d: Dictionary = n[sec]
		for k in d.keys():
			cf.set_value(sec, String(k), d[k])
	var kb: Dictionary = n["keybinds"]
	for act in kb.keys():
		cf.set_value("keybinds", String(act), kb[act])
	return cf.save(file if not file.is_empty() else path())


static func read(file: String = "") -> Dictionary:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load(file if not file.is_empty() else path()) != OK:
		return defaults()
	var raw: Dictionary = {}
	for sec in cf.get_sections():
		var d: Dictionary = {}
		for k in cf.get_section_keys(sec):
			d[k] = cf.get_value(sec, k)
		raw[sec] = d
	return normalize(raw)


## Snapshot the live InputMap bindings into s["keybinds"].
static func capture_keybinds(s: Dictionary) -> void:
	s["keybinds"] = Keybinds.to_map()


# ------------------------------------------------------------- apply
## Apply everything that does not need a window to exist; safe headless.
static func apply(s: Dictionary, tree: SceneTree = null) -> void:
	var n: Dictionary = normalize(s)
	apply_audio(n)
	apply_controls(n)
	apply_video(n, tree)


static func apply_controls(s: Dictionary) -> void:
	Keybinds.ensure_actions(float((s["controls"] as Dictionary)["deadzone"]))
	if not (s["keybinds"] as Dictionary).is_empty():
		Keybinds.apply_map(s["keybinds"])


static func bus_db(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.0001))


static func apply_audio(s: Dictionary) -> void:
	var a: Dictionary = s["audio"]
	for b in BUSES:
		var idx: int = AudioServer.get_bus_index(String(b))
		if idx < 0:
			continue
		AudioServer.set_bus_volume_db(idx, bus_db(float(a[b])))
		AudioServer.set_bus_mute(idx, float(a[b]) <= 0.0001 or (String(b) == "Master" and bool(a["mute"])))


static func headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func apply_video(s: Dictionary, tree: SceneTree = null) -> void:
	var v: Dictionary = s["video"]
	Engine.max_fps = int(v["fps_cap"])
	if tree != null:
		tree.root.content_scale_factor = float(v["ui_scale"])
	if headless():
		return
	DisplayServer.window_set_min_size(MIN_WINDOW)
	match String(v["vsync"]):
		"off": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"adaptive": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var mon: int = int(v["monitor"])
	if mon >= 0 and mon < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(mon)
	match String(v["mode"]):
		"fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var res: Vector2i = clamp_resolution(v["resolution"], DisplayServer.screen_get_size())
			DisplayServer.window_set_size(res)
			var scr: Rect2i = DisplayServer.screen_get_usable_rect()
			DisplayServer.window_set_position(scr.position + (scr.size - res) / 2)


## Resolution list filtered to the screen (windowed only).
static func resolutions_for(screen: Vector2i) -> Array:
	var out: Array = []
	for r in RESOLUTIONS:
		var rv: Vector2i = r
		if screen.x <= 0 or (rv.x <= screen.x and rv.y <= screen.y):
			out.append(rv)
	if out.is_empty():
		out.append(RESOLUTIONS[0])
	return out


static func clamp_resolution(res: Vector2i, screen: Vector2i) -> Vector2i:
	if screen.x <= 0 or (res.x <= screen.x and res.y <= screen.y):
		return res
	var list: Array = resolutions_for(screen)
	return list[list.size() - 1]


## F11 / Alt+Enter: windowed <-> borderless fullscreen.
static func toggle_fullscreen(s: Dictionary) -> Dictionary:
	var n: Dictionary = normalize(s)
	var v: Dictionary = n["video"]
	v["mode"] = "windowed" if String(v["mode"]) != "windowed" else "borderless"
	return n


## Video changes revert after REVERT_S unless confirmed (§6). Pure helper:
## returns the settings that should be live at time `t` since apply.
const REVERT_S: float = 10.0


static func revert_due(elapsed: float, confirmed: bool) -> bool:
	return not confirmed and elapsed >= REVERT_S
