extends RefCounted
## Steam platform wrapper (PC_SPEC §7). Static, no autoload, and NO typed
## reference to the GodotSteam GDExtension: every call goes through
## Engine.get_singleton("Steam").callv(...), so the project parses, runs and
## tests without the extension. When the singleton or an App ID is missing,
## every call is a no-op that returns false and is recorded in a local mock log
## ({op, args, t}) that selftest.gd inspects.
##
## The game only ever calls this module. Steam Auto-Cloud (configured in
## Steamworks on user://slot_*.json + user://settings.cfg) needs no code;
## cloud_write/cloud_read are the Remote Storage fallback.
## Never commit steam_appid.txt or the Steam SDK redistributables.

const SINGLETON: String = "Steam"
const MOCK_MAX: int = 512

static var _active: bool = false
static var _app_id: int = 0
static var _mock: Array[Dictionary] = []
static var _mock_cloud: Dictionary = {}
static var _presence: Dictionary = {}
static var _unlocked: Dictionary = {}


static func available() -> bool:
	return Engine.has_singleton(SINGLETON) or ClassDB.class_exists(SINGLETON)


static func _steam() -> Object:
	if Engine.has_singleton(SINGLETON):
		return Engine.get_singleton(SINGLETON)
	return null


static func _log(op: String, args: Array) -> void:
	_mock.append({"op": op, "args": args.duplicate(), "t": Time.get_ticks_msec()})
	while _mock.size() > MOCK_MAX:
		_mock.remove_at(0)


static func _call(method: String, args: Array) -> Variant:
	var s: Object = _steam()
	if s == null or not s.has_method(method):
		return null
	return s.callv(method, args)


## App ID: explicit arg, else steam_appid.txt next to the executable (dev only).
static func _resolve_app_id(app_id: int) -> int:
	if app_id > 0:
		return app_id
	var p: String = OS.get_executable_path().get_base_dir().path_join("steam_appid.txt")
	if FileAccess.file_exists(p):
		var f: FileAccess = FileAccess.open(p, FileAccess.READ)
		if f != null:
			return int(f.get_as_text().strip_edges())
	return 0


static func init(app_id: int = 0) -> bool:
	_app_id = _resolve_app_id(app_id)
	_active = false
	if available() and _app_id > 0:
		var r: Variant = _call("steamInitEx", [true, _app_id])
		if r is Dictionary:
			_active = int((r as Dictionary).get("status", 1)) == 0
		elif r is bool:
			_active = bool(r)
	_log("init", [_app_id, _active])
	return _active


static func is_active() -> bool:
	return _active


static func app_id() -> int:
	return _app_id


## Pump callbacks; Main calls this every frame.
static func tick() -> void:
	if _active:
		_call("run_callbacks", [])


static func unlock_achievement(id: String) -> bool:
	_log("unlock_achievement", [id])
	_unlocked[id] = true
	if not _active:
		return false
	var ok: bool = bool(_call("setAchievement", [id]))
	_call("storeStats", [])
	return ok


static func is_unlocked(id: String) -> bool:
	if _active:
		var r: Variant = _call("getAchievement", [id])
		if r is Dictionary:
			return bool((r as Dictionary).get("achieved", false))
	return bool(_unlocked.get(id, false))


static func set_stat_int(id: String, v: int) -> bool:
	_log("set_stat_int", [id, v])
	if not _active:
		return false
	return bool(_call("setStatInt", [id, v]))


static func store_stats() -> bool:
	_log("store_stats", [])
	if not _active:
		return false
	return bool(_call("storeStats", []))


## Mirror the lifetime stats PC_SPEC §5 lists to Steam.
static func push_stats(save: Dictionary) -> void:
	var st: Dictionary = save.get("stats", {}) if save.get("stats", {}) is Dictionary else {}
	set_stat_int("stat_kills", int(st.get("kills", 0)))
	set_stat_int("stat_bosses", int(st.get("bosses", 0)))
	set_stat_int("stat_best_wave", int(save.get("best_wave", 0)))
	set_stat_int("stat_runs", int(st.get("runs", 0)))
	set_stat_int("stat_playtime_min", int(float(st.get("play_s", 0.0)) / 60.0))
	# Redesign stats (the new achievements' progress bars in Steam).
	set_stat_int("stat_parts", int(st.get("parts_found", 0)))
	set_stat_int("stat_reforges", int(st.get("reforges", 0)))
	set_stat_int("stat_specials", int(st.get("specials_cast", 0)))
	store_stats()


static func upload_score(board: String, v: int) -> bool:
	_log("upload_score", [board, v])
	if not _active:
		return false
	# Leaderboards are async (findLeaderboard -> uploadLeaderboardScore);
	# only the request is issued here.
	_call("findLeaderboard", [board])
	return true


static func set_rich_presence(key: String, value: String) -> bool:
	_log("set_rich_presence", [key, value])
	_presence[key] = value
	if not _active:
		return false
	return bool(_call("setRichPresence", [key, value]))


static func presence() -> Dictionary:
	return _presence.duplicate()


## Rich-presence states (§7): Menu, Base, Run: Wave w · Tt, Endless, Challenge.
static func presence_text(screen: String, wave: int = 0, tier: int = 1, mode: String = "normal", mult: float = 1.0) -> String:
	match screen:
		"run":
			if mode == "endless":
				return "Endless: Wave %d" % wave
			if mult > 1.001:
				return "Challenge x%.1f · Wave %d" % [mult, wave]
			return "Run: Wave %d · T%d" % [wave, tier]
		"base":
			return "Base"
	return "Menu"


static func update_presence(screen: String, wave: int = 0, tier: int = 1, mode: String = "normal", mult: float = 1.0) -> bool:
	var txt: String = presence_text(screen, wave, tier, mode, mult)
	if String(_presence.get("status", "")) == txt:
		return false
	set_rich_presence("wave", str(wave))
	set_rich_presence("tier", str(tier))
	return set_rich_presence("status", txt)


static func cloud_write(path: String, data: PackedByteArray) -> bool:
	_log("cloud_write", [path, data.size()])
	if not _active:
		_mock_cloud[path] = data.duplicate()
		return false
	return bool(_call("fileWrite", [path, data]))


static func cloud_read(path: String) -> PackedByteArray:
	_log("cloud_read", [path])
	if not _active:
		var m: Variant = _mock_cloud.get(path, PackedByteArray())
		return m if m is PackedByteArray else PackedByteArray()
	var size: int = int(_call("getFileSize", [path]))
	var r: Variant = _call("fileRead", [path, size])
	if r is Dictionary:
		var buf: Variant = (r as Dictionary).get("buf", PackedByteArray())
		if buf is PackedByteArray:
			return buf
	return PackedByteArray()


## Push every save slot file present in user:// to Remote Storage.
static func cloud_sync_slots(paths: Array) -> int:
	var n: int = 0
	for p in paths:
		var path: String = String(p)
		if not FileAccess.file_exists(path):
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		cloud_write(path.get_file(), bytes)
		n += 1
	return n


## Cloud conflict rule (PC_SPEC §4): keep the slot with more playtime.
static func pick_conflict(local_save: Dictionary, cloud_save: Dictionary) -> String:
	var a: float = float(local_save.get("playtime_s", (local_save.get("stats", {}) as Dictionary).get("play_s", 0.0) if local_save.get("stats", {}) is Dictionary else 0.0))
	var b: float = float(cloud_save.get("playtime_s", (cloud_save.get("stats", {}) as Dictionary).get("play_s", 0.0) if cloud_save.get("stats", {}) is Dictionary else 0.0))
	return "cloud" if b > a else "local"


static func overlay_active() -> bool:
	if not _active:
		return false
	return bool(_call("isOverlayEnabled", []))


static func mock_log() -> Array[Dictionary]:
	return _mock.duplicate()


static func mock_ops(op: String) -> Array:
	var out: Array = []
	for m in _mock:
		if String(m["op"]) == op:
			out.append(m["args"])
	return out


static func reset_mock() -> void:
	_mock.clear()
	_mock_cloud.clear()
	_presence.clear()
	_unlocked.clear()
