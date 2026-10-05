extends SceneTree
const PT := preload("res://playtest.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const TowerState := preload("res://TowerState.gd")

func _initialize() -> void:
	for i in [0, 8, 10]:
		var save: Dictionary = BaseMeta.default_save()
		var S = TowerState.new()
		S.mass = true
		S.mass_lod_cap = 1200
		S.setup(4242 + 50000 + i * 7919, save, PT.NOW0, {})
		var t: float = 0.0
		var acc: float = 0.0
		var lw: int = -1
		while not S.over and t < 900.0:
			S.tick(0.1)
			t += 0.1
			acc += 0.1
			if S.wave != lw:
				lw = S.wave
				if S.wave >= 5:
					var hs: Array = []
					for k in S.dbg_hits.keys():
						hs.append("%s:%.0f" % [k, float(S.dbg_hits[k])])
					print("  w%d hp=%.0f/%.0f blds=%d dps=%.0f lvl=%d cash=%.0f %s" % [S.wave, S.hp, float(S.stats["max_hp"]), S.building_count(), S.dps(), S.level, S.cash, " ".join(hs)])
				S.dbg_hits = {}
			if acc >= 0.5:
				acc = 0.0
				PT.bot_step(S, "balanced", "")
		var hs2: Array = []
		for k in S.dbg_hits.keys():
			hs2.append("%s:%.0f" % [k, float(S.dbg_hits[k])])
		print("RUN %d died w%d last-wave hits %s picks %s" % [i, S.wave, " ".join(hs2), str(S.picks_taken)])
	quit(0)
