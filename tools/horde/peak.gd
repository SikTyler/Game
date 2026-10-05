extends SceneTree
## HORDE Phase-0: peak live-enemy counts under the REAL playtest bot policy.
## Usage (from repo root):
##   godot --headless --path games/towerdef-pc-0001 --script ../../tools/horde/peak.gd -- [cap=N] [job=fresh|main]
## fresh: N fresh-save balanced runs (playtest camp_run).  main: playtest's
## "main" campaign job in-process (8 runs/days of meta progression).
const HL := preload("res://../../tools/horde/hlib.gd")

func _initialize() -> void:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var p: PackedStringArray = String(a).split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else "1"
	var cap: int = int(args.get("cap", "-1"))
	var g: GDScript = HL.build(cap)
	HL.take_over(g)
	var PT: GDScript = load("res://playtest.gd")
	PT.set("QUIET", true)
	var job: String = String(args.get("job", "fresh"))
	var t0: int = Time.get_ticks_msec()
	var out: Dictionary = {"job": job, "cap": cap if cap > 0 else 220}
	if job == "fresh":
		var BM = load("res://BaseMeta.gd")
		var rows: Array = []
		for i in int(args.get("n", "3")):
			g.set("hpeak", 0)
			g.set("hrefused", 0)
			g.set("hspawns", 0)
			var save: Dictionary = BM.default_save()
			var r: Dictionary = PT.camp_run(save, "balanced", 4242 + 50000 + i * 7919, 1_700_000_000, "", false)
			rows.append({"seed_i": i, "wave": int(r["wave"]), "peak": g.get("hpeak"), "peak_wave": g.get("hpeak_wave"), "refused": g.get("hrefused"), "spawns": g.get("hspawns")})
		out["runs"] = rows
	else:
		var r2: Dictionary = PT.run_job(job, 4242, OS.get_user_data_dir())
		out["result_keys"] = r2.keys()
		out["peak"] = g.get("hpeak")
		out["peak_wave"] = g.get("hpeak_wave")
		out["refused"] = g.get("hrefused")
		out["spawns"] = g.get("hspawns")
	out["wall_s"] = float(Time.get_ticks_msec() - t0) / 1000.0
	print("HORDE PEAK " + JSON.stringify(out))
	quit(0)
