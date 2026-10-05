extends SceneTree
## HORDE Phase-0/1 (Phase 1: SoA EnemyStore + EnemyHash): TowerState.tick() cost per substep at N live enemies.
## Instrumented runtime copy of TowerState with MAX_ENEMIES lifted (hlib.gd);
## enemies are injected through the engine's own _spawn(kind, ev, at, quad)
## (spawn_hold stops the wave plan). Enemy HP is pinned huge so the body count
## stays constant while every weapon fires; Core HP is refilled each substep.
## Usage: godot --headless --path games/towerdef-pc-0001 --script ../../tools/horde/profile.gd -- counts=220,1000,5000 steps=40 board=full|core
const HL := preload("res://../../tools/horde/hlib.gd")
const KINDS: Array = ["drone", "drone", "drone", "skitter", "skitter", "hauler", "ranged", "splitter", "elite"]
## ring-1 cells around the Core (16..32) + ring-2 railgun / hut cells.
const BOARD: Dictionary = {16: "gun", 17: "mortar", 18: "tesla", 23: "frost", 25: "flak", 30: "gun", 31: "mortar", 32: "tesla", 10: "railgun", 38: "railgun"}

var Ach = null
var Mis = null
var Stats = null

func _initialize() -> void:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var p: PackedStringArray = String(a).split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else "1"
	var g: GDScript = HL.build(100000)
	HL.take_over(g)
	Ach = load("res://Achievements.gd")
	Mis = load("res://Missions.gd")
	var counts: Array = Array(String(args.get("counts", "220,1000,5000")).split(",")).map(func(x): return int(x))
	var steps: int = int(args.get("steps", "40"))
	var board: String = String(args.get("board", "full"))
	var rows: Array = []
	for n in counts:
		rows.append(_profile(g, int(n), steps, board, bool(args.has("densest"))))
	print("HORDE PROFILE " + JSON.stringify({"board": board, "steps": steps, "rows": rows}))
	quit(0)


func _mk(g: GDScript, board: String):
	var BM = load("res://BaseMeta.gd")
	var S = g.new()
	S.setup(777, BM.default_save(), 1_700_000_000)
	S.spawn_hold = true
	S.wave = 30          # mid-game wave: hp/dmg scaling, quad_count 3
	if board == "full":
		for i in BOARD.keys():
			S.slots[int(i)] = {"id": String(BOARD[i]), "perm": 0, "run": 1}
			S.unlocked[int(i)] = true
		S.recompute()
	return S


func _profile(g: GDScript, n: int, steps: int, board: String, do_densest: bool) -> Dictionary:
	var S = _mk(g, board)
	var ev0: Array = []
	S.tick(0.05)     # adopt the plan (spawn_hold keeps it empty)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var t_sp: int = Time.get_ticks_usec()
	for k in n:
		var a: float = r.randf() * TAU
		var d: float = r.randf_range(S.STOP_R, S.SPAWN_R)
		S._spawn(String(KINDS[k % KINDS.size()]), ev0, S.CENTER + Vector2.from_angle(a) * d, -1)
	var spawn_us: float = float(Time.get_ticks_usec() - t_sp) / float(maxi(1, n))
	for e in S.en.order:
		S.en.hp[e] = 1e15
		S.en.max_hp[e] = 1e15
	var ph: Dictionary = {"move": 0, "fire": 0, "troops": 0, "reap": 0, "step": 0}
	var evn: int = 0
	var handle_us: int = 0
	for s in steps:
		S.hp = 1e12
		var ev: Array = []
		var t0: int = Time.get_ticks_usec()
		S._step(S.SUBSTEP, ev)
		ph["step"] += Time.get_ticks_usec() - t0
		evn += ev.size()
		var th: int = Time.get_ticks_usec()
		var save: Dictionary = S.save
		Ach.on_events(save, Ach.new_run(), ev, 0, 1.0)
		Mis.on_run_events(save, ev)
		handle_us += Time.get_ticks_usec() - th
		# phase split (same state, separate calls)
		var e2: Array = []
		var t1: int = Time.get_ticks_usec()
		S._move_enemies(S.SUBSTEP, e2)
		var t2: int = Time.get_ticks_usec()
		S._fire(S.SUBSTEP, e2)
		var t3: int = Time.get_ticks_usec()
		S._troops_step(S.SUBSTEP, e2)
		var t4: int = Time.get_ticks_usec()
		S._reap(e2)
		var t5: int = Time.get_ticks_usec()
		ph["move"] += t2 - t1
		ph["fire"] += t3 - t2
		ph["troops"] += t4 - t3
		ph["reap"] += t5 - t4
	var out: Dictionary = {"n": S.enemy_count(), "hash_rebuilds": S.eh.rebuilds, "spawn_us_each": snappedf(spawn_us, 0.01), "events_per_step": evn / steps,
		"handle_ms_per_step": snappedf(float(handle_us) / steps / 1000.0, 0.001)}
	for k in ph.keys():
		out[k + "_ms"] = snappedf(float(ph[k]) / steps / 1000.0, 0.001)
	if do_densest:
		var td: int = Time.get_ticks_usec()
		S._densest(2.0 * S.cpx())
		out["densest_ms"] = snappedf(float(Time.get_ticks_usec() - td) / 1000.0, 0.1)
	return out
