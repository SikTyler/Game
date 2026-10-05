extends SceneTree
## HORDE hot-loop profile: EnemyStore.move() on N bodies (1k/2k/5k) packed in
## a ring around the Core, C# (HordeMove.cs) vs the GDScript reference path.
## Also asserts both paths leave bit-identical positions.
## Usage: godot --headless --path games/towerdef-pc-0001 --script res://horde_prof.gd

const STEPS: int = 60


func _initialize() -> void:
	var ES = load("res://EnemyStore.gd")
	var TS = load("res://TowerState.gd")
	var C: Vector2 = TS.CENTER
	var prm := PackedFloat64Array([6.0, 0.5, 0.35, 6.0])
	for n in [1000, 2000, 5000]:
		var res: Dictionary = {}
		for mode in [0, 1]:
			ES.cs_mode = mode
			if mode == 1 and not ES.cs_available():
				print("HORDE PROF C# unavailable")
				continue
			var en = ES.new()
			for i in n:
				var a: float = TAU * float(i) / 97.0
				var s: int = en.alloc(i + 1, "ranged" if i % 9 == 0 else "drone", C + Vector2.from_angle(a) * (200.0 + float(i % 53) * 9.0))
				en.spd[s] = 40.0
				en.hp[s] = 10.0
				en.set_size(s, 12.0 + float(i % 4) * 4.0)
				if i % 5 == 0:
					en.knock(s, Vector2.from_angle(a) * 80.0)
			en.move(1.0 / 60.0, false, C, 70.0, 160.0, 2.0, PackedByteArray(), 9, 78.0, prm)   # warm-up
			var t0: int = Time.get_ticks_usec()
			for k in STEPS:
				en.move(1.0 / 60.0, false, C, 70.0, 160.0, 2.0, PackedByteArray(), 9, 78.0, prm)
			var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / float(STEPS)
			res[mode] = en.pos
			print("HORDE PROF n=%d path=%s %.3f ms/move" % [n, "cs" if mode == 1 else "gd", ms])
		if res.size() == 2:
			print("HORDE PROF n=%d identical=%s" % [n, str(res[0] == res[1])])
	ES.cs_mode = -1
	quit(0)
