extends RefCounted
## Persistence seam (PC_SPEC §4): 3 save slots at user://slot_{1,2,3}.json.
## Each write keeps the previous file as slot_n.bak and goes through an atomic
## .tmp + rename; a corrupted primary falls back to the .bak. The mobile-format
## user://save.json (save v1/v2) is imported into slot 1 when slot 1 is empty
## (BaseMeta.normalize migrates it to v3). Settings live in user://settings.cfg,
## never in a slot. Static-only so the headless tests preload it (no autoloads).
## Dev isolation: headless harnesses (`--script`) and any run with
## COREHOLD_DEV_SAVES=1 keep slots, the legacy file and settings under
## user://dev/ (root()), so tests and dev tools never touch the player's saves.

const SLOT_COUNT: int = 3
const DELETE_CONFIRM: String = "DELETE"
const DEV_ENV: String = "COREHOLD_DEV_SAVES"
const DEV_DIR: String = "user://dev/"

static var active: int = 1
static var _root: String = ""


## "user://dev/" for harness / dev runs, else "user://". Decided once the
## main loop exists (a harness's main loop is its SceneTree script).
static func root() -> String:
	if _root.is_empty():
		var loop: MainLoop = Engine.get_main_loop()
		var args: PackedStringArray = OS.get_cmdline_args()
		var dev: bool = OS.get_environment(DEV_ENV) == "1" or args.has("--script") or args.has("-s") \
			or (loop != null and loop.get_script() != null)
		if not dev and loop == null:
			return "user://"
		_root = DEV_DIR if dev else "user://"
		if dev:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEV_DIR))
	return _root


static func slot_path(n: int) -> String:
	return root() + "slot_%d.json" % n


static func legacy_path() -> String:
	return root() + "save.json"


static func valid_slot(n: int) -> bool:
	return n >= 1 and n <= SLOT_COUNT


static func set_active(n: int) -> bool:
	if not valid_slot(n):
		return false
	active = n
	return true


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(text) != OK:   # corrupt file: quiet failure (no engine error spam)
		return null
	var parsed: Variant = j.data
	if parsed is Dictionary:
		return parsed
	return null


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func slot_exists(n: int) -> bool:
	return valid_slot(n) and (FileAccess.file_exists(slot_path(n)) or FileAccess.file_exists(slot_path(n) + ".bak"))


## Primary, else the .bak, else (slot 1 only) the legacy mobile save; {} if none.
static func read_slot(n: int) -> Dictionary:
	if not valid_slot(n):
		return {}
	var p: Variant = _read_json(slot_path(n))
	if p is Dictionary:
		return p
	var b: Variant = _read_json(slot_path(n) + ".bak")
	if b is Dictionary:
		return b
	if n == 1:
		var l: Variant = _read_json(legacy_path())
		if l is Dictionary:
			return l
	return {}


## Atomic write: old primary -> .bak, new data -> .tmp -> rename to primary.
static func write_slot(n: int, data: Dictionary) -> bool:
	if not valid_slot(n):
		return false
	var path: String = slot_path(n)
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	if _read_json(path) is Dictionary:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


## Deleting needs the typed confirmation word (the slot picker asks for it).
static func delete_slot(n: int, confirm: String) -> bool:
	if not valid_slot(n) or confirm != DELETE_CONFIRM:
		return false
	_remove(slot_path(n))
	_remove(slot_path(n) + ".bak")
	_remove(slot_path(n) + ".tmp")
	if n == 1:
		_remove(legacy_path())
	return true


## Copy a slot into an EMPTY slot.
static func copy_slot(src: int, dst: int) -> bool:
	if not valid_slot(src) or not valid_slot(dst) or src == dst or slot_exists(dst):
		return false
	var d: Dictionary = read_slot(src)
	if d.is_empty():
		return false
	return write_slot(dst, d)


## Slot-picker card data. Reads the raw file; tier/best come from the save keys.
static func slot_summary(n: int) -> Dictionary:
	var d: Dictionary = read_slot(n)
	if d.is_empty():
		return {"slot": n, "exists": false}
	var bw: Dictionary = d.get("best_wave_by_tier", {}) if d.get("best_wave_by_tier", {}) is Dictionary else {}
	var best_tier: int = 1
	for k in bw.keys():
		if int(bw[k]) > 0:
			best_tier = maxi(best_tier, int(k))
	var st: Dictionary = d.get("stats", {}) if d.get("stats", {}) is Dictionary else {}
	return {
		"slot": n, "exists": true, "best_tier": best_tier, "tier": int(d.get("tier", 1)),
		"best_wave": int(d.get("best_wave", 0)), "play_s": float(st.get("play_s", 0.0)),
		"last_played": int(d.get("last_seen", 0)), "version": int(d.get("version", 1)),
	}


static func read() -> Dictionary:
	return read_slot(active)


static func write(data: Dictionary) -> void:
	write_slot(active, data)


## Wipe the active slot (and the legacy file it would re-import from).
static func clear() -> void:
	_remove(slot_path(active))
	_remove(slot_path(active) + ".bak")
	_remove(slot_path(active) + ".tmp")
	_remove(legacy_path())
