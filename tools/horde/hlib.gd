extends RefCounted
## HORDE Phase-0 throwaway harness helpers. Builds an INSTRUMENTED, runtime-only
## copy of res://TowerState.gd (the game file on disk is never touched):
##   - static hpeak / hpeak_wave / hrefused / hspawns counters in _spawn
##   - optional MAX_ENEMIES override (cap lifted for profiling / demand runs)
## take_over() makes every later preload("res://TowerState.gd") (playtest.gd,
## Main, ...) resolve to the instrumented copy.

static func build(max_enemies: int = -1) -> GDScript:
	var src: String = FileAccess.get_file_as_string("res://TowerState.gd")
	src = _rep(src, "var next_eid: int = 1\n", "var next_eid: int = 1\nstatic var hpeak: int = 0\nstatic var hpeak_wave: int = 0\nstatic var hrefused: int = 0\nstatic var hspawns: int = 0\nstatic var hcap_ticks: int = 0\n")
	src = _rep(src, "\tif en.count() >= max_bodies():\n\t\treturn false\n\tvar d: Dictionary = EnemyDB.get_def(kind)", "\tif en.count() >= max_bodies():\n\t\threfused += 1\n\t\treturn false\n\tvar d: Dictionary = EnemyDB.get_def(kind)")
	src = _rep(src, "\ten.quad[e] = quad_of(pos)\n\tif kind == \"boss\":\n", "\tif kind == \"boss\":\n\t\tpass\n\ten.quad[e] = quad_of(pos)\n\thspawns += 1\n\tif en.count() > hpeak:\n\t\thpeak = en.count()\n\t\thpeak_wave = wave\n")
	if max_enemies > 0:
		src = _rep(src, "const MAX_ENEMIES: int = 220", "const MAX_ENEMIES: int = %d" % max_enemies)
	var g := GDScript.new()
	g.source_code = src
	var err: int = g.reload()
	assert(err == OK, "instrumented TowerState failed to compile")
	return g


static func _rep(src: String, a: String, b: String) -> String:
	assert(src.find(a) >= 0, "harness patch anchor missing: " + a.substr(0, 40))
	return src.replace(a, b)


static func take_over(g: GDScript) -> void:
	g.take_over_path("res://TowerState.gd")


## Typed `const X := preload(...)` cannot resolve a taken-over path, so for
## playtest.gd write the instrumented TowerState + a re-pointed playtest copy to
## user:// (outside the repo) and load those instead.
static func user_playtest(max_enemies: int = -1) -> GDScript:
	var g: GDScript = build(max_enemies)
	var f := FileAccess.open("user://horde_TowerState.gd", FileAccess.WRITE)
	f.store_string(g.source_code)
	f.close()
	var pt: String = FileAccess.get_file_as_string("res://playtest.gd")
	pt = _rep(pt, 'preload("res://TowerState.gd")', 'preload("user://horde_TowerState.gd")')
	var f2 := FileAccess.open("user://horde_playtest.gd", FileAccess.WRITE)
	f2.store_string(pt)
	f2.close()
	return load("user://horde_playtest.gd")
