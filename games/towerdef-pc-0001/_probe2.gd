extends SceneTree
const PT := preload("res://playtest.gd")
const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")

func _initialize() -> void:
	var save: Dictionary = BaseMeta.default_save()
	var S = TowerState.new()
	S.mass = true
	S.mass_lod_cap = int(OS.get_environment("LOD")) if OS.get_environment("LOD") != "" else 2500
	S.setup(4242, save)
	S.dmg_mult = float(OS.get_environment("DM")) if OS.get_environment("DM") != "" else 4.0
	S.recompute()
	var t: float = 0.0
	var acc: float = 0.0
	var lw: int = 0
	var t0: int = Time.get_ticks_msec()
	var tw: int = t0
	while not S.over and t < 1500.0:
		S.tick(0.1)
		t += 0.1
		acc += 0.1
		if S.wave != lw:
			var now: int = Time.get_ticks_msec()
			print("w%d t=%.0f alive=%d kills=%d real_ms_wave=%d hp=%.0f blds=%d" % [S.wave, t, S.en.count(), S.kills, now - tw, S.hp, S.building_count()])
			tw = now
			lw = S.wave
		if acc >= 0.5:
			acc = 0.0
			PT.bot_step(S, "balanced")
	print("END wave %d real_ms=%d" % [S.wave, Time.get_ticks_msec() - t0])
	quit(0)
