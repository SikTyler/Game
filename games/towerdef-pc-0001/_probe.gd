extends SceneTree
## scratch probe (not committed)
const PT := preload("res://playtest.gd")
const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")

func _initialize() -> void:
	var n: int = int(OS.get_environment("PN")) if OS.get_environment("PN") != "" else 1
	for i in n:
		var save: Dictionary = BaseMeta.default_save()
		var S = TowerState.new()
		S.mass = true
		S.setup(4242 + i * 7919, save)
		var t: float = 0.0
		var acc: float = 0.0
		var lw: int = 0
		var t0: int = Time.get_ticks_msec()
		var wave_log: Array = []
		while not S.over and t < float(OS.get_environment("PT") if OS.get_environment("PT") != "" else "900"):
			var ev: Array = S.tick(0.1)
			t += 0.1
			acc += 0.1
			for e in ev:
				if OS.get_environment("PV") == "2" and ["core_hits", "boss", "building_destroyed", "sapper_blast"].has(String(e["t"])) and float(e.get("dmg", 99.0)) > 2.0:
					print("  t=%.1f %s" % [t, str(e).left(160)])
				if String(e["t"]) == "wave_clear":
					wave_log.append("c%d:%.0f" % [int(e["wave"]), float(e["cash"])])
			if S.wave != lw and OS.get_environment("PV") != "":
				lw = S.wave
				print(str(S.dbg_hits)); S.dbg_hits = {}
				print("w%d t=%.0f alive=%d hp=%.0f/%.0f cash=%.0f earned=%.0f kills=%d dps=%.0f lvl=%d blds=%d leak=%d" % [S.wave, t, S.en.count(), S.hp, float(S.stats["max_hp"]), S.cash, S.cash_earned, S.kills, S.dps(), S.level, S.building_count(), S.mass_leaked])
			if acc >= 0.5:
				acc = 0.0
				PT.bot_step(S, "balanced")
		print("RUN %d: wave %d t=%.0f kills=%d coins=%.1f peak=%d real_ms=%d kbw=%s" % [i, S.wave, t, S.kills, S.coins_run, S.mass_peak, Time.get_ticks_msec() - t0, str(S.kills_by_weapon)])
		print(" ".join(wave_log))
	quit(0)
