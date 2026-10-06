extends RefCounted
## Dev save isolation: headless harness runs keep every slot, the legacy
## file and settings under user://dev/ (MetaSave.root()), clear() only acts
## there, and no script hard-codes a real save path (so running the gate on
## the machine the game is played on never touches the player's saves).
## `t` is the selftest runner (t._check).

const MetaSave := preload("res://MetaSave.gd")
const Settings := preload("res://Settings.gd")

const SKIP_DIRS: Array = [".godot", ".git", "third_party", "addons", "build"]
const SELF: String = "res://tests/st_saves.gd"


static func run(t) -> void:
	_paths(t)
	_clear_stays_in_dev(t)
	_no_hardcoded_paths(t)


static func _paths(t) -> void:
	var dev: String = MetaSave.DEV_DIR
	t._check("SAVES harness run uses user://dev/", MetaSave.root() == dev, MetaSave.root())
	var all_dev: bool = MetaSave.legacy_path().begins_with(dev) and Settings.path().begins_with(dev)
	for n in range(1, MetaSave.SLOT_COUNT + 1):
		all_dev = all_dev and MetaSave.slot_path(n).begins_with(dev)
	t._check("SAVES slot, legacy and settings paths all live under user://dev/", all_dev)


static func _clear_stays_in_dev(t) -> void:
	var prev: int = MetaSave.active
	MetaSave.set_active(1)
	var file: String = MetaSave.DEV_DIR + "slot_1.json"
	var wrote: bool = MetaSave.write_slot(1, {"probe": 1}) and FileAccess.file_exists(file)
	MetaSave.clear()
	t._check("SAVES write and clear act on the user://dev/ slot", wrote and not FileAccess.file_exists(file))
	MetaSave.set_active(prev)


## A quoted real-folder save path anywhere in game code would bypass root().
static func _no_hardcoded_paths(t) -> void:
	var needles: Array = ["\"user://" + "slot", "\"user://" + "save.json", "\"user://" + "settings.cfg"]
	var hits: PackedStringArray = []
	for path in _scripts("res://"):
		if path == SELF:
			continue
		var text: String = FileAccess.get_file_as_string(path)
		for n in needles:
			if text.contains(n):
				hits.append("%s: %s" % [path, n])
	t._check("SAVES no script hard-codes a real save/settings path", hits.is_empty(), ", ".join(hits))


static func _scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not SKIP_DIRS.has(sub):
			out.append_array(_scripts(dir.path_join(sub)))
	return out
