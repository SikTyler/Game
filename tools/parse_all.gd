extends SceneTree
## Loads every GDScript under res:// (except .godot/) so a parse or preload
## error anywhere fails the gate, even in scripts no test happens to touch.
## Prints PARSE OK / PARSE FAIL <path>.


func _initialize() -> void:
	var bad: Array = []
	var n: int = 0
	for p in _scripts("res://"):
		n += 1
		var s: Variant = load(p)
		if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate():
			bad.append(p)
	for p in bad:
		print("PARSE FAIL " + String(p))
	print("PARSE OK %d scripts" % n if bad.is_empty() else "PARSE FAILED %d of %d" % [bad.size(), n])
	quit(0 if bad.is_empty() else 1)


func _scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if not f.begins_with("."):
			var p: String = dir.path_join(f)
			if d.current_is_dir():
				out.append_array(_scripts(p))
			elif f.ends_with(".gd"):
				out.append(p)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
