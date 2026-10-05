extends SceneTree
## HORDE Phase-0: cost of the current immediate-mode Battle._draw_world at N
## enemies. A bare Node2D stands in for Main (Battle only reads m.S,
## m.enemy_pos and the CanvasItem draw_* API). Measures the CPU time of the
## _draw_world call (draw-command recording) and the wall frame time.
## Needs a display: xvfb-run -a godot --path games/towerdef-pc-0001 --script ../../tools/horde/draw.gd -- counts=220,1000,5000
## (xvfb = Mesa llvmpipe software GL: frame times are an upper bound, the
## _draw_world CPU time is the representative number.)
const HL := preload("res://../../tools/horde/hlib.gd")
const KINDS: Array = ["drone", "drone", "drone", "skitter", "skitter", "hauler", "ranged", "splitter", "elite"]

const VIEW_SRC := """extends Node2D
var Battle = null
var S = null
var draw_us: Array = []
func enemy_pos(eid: int) -> Variant:
	return null
func _process(_d: float) -> void:
	queue_redraw()
func _draw() -> void:
	var t0: int = Time.get_ticks_usec()
	Battle._draw_world(self)
	draw_us.append(Time.get_ticks_usec() - t0)
"""

var counts: Array = []
var ci: int = 0
var frame: int = 0
var view: Node2D = null
var t_frames: int = 0
var rows: Array = []
var G: GDScript = null
const FRAMES: int = 90
const WARM: int = 15

func _initialize() -> void:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var p: PackedStringArray = String(a).split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else "1"
	counts = Array(String(args.get("counts", "220,1000,5000")).split(",")).map(func(x): return int(x))
	G = HL.build(100000)
	# no take_over here: Battle.gd only needs TowerState constants; S is duck-typed
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_next()


func _next() -> void:
	if view != null:
		view.queue_free()
	var S = G.new()
	S.setup(777, load("res://BaseMeta.gd").default_save(), 1)
	S.spawn_hold = true
	S.tick(0.05)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var ev: Array = []
	for k in int(counts[ci]):
		var a: float = r.randf() * TAU
		S._spawn(String(KINDS[k % KINDS.size()]), ev, S.CENTER + Vector2.from_angle(a) * r.randf_range(S.STOP_R, S.SPAWN_R), -1)
	# realistic mix of decorations: ~half damaged (HP bar), some slowed / flashing
	for k in S.enemies.size():
		var e: Dictionary = S.enemies[k]
		if k % 2 == 0:
			e["hp"] = float(e["max_hp"]) * 0.5
		if k % 5 == 0:
			e["slow_t"] = 1.0
		if k % 3 == 0:
			e["hit_t"] = 0.06
	var sc := GDScript.new()
	sc.source_code = VIEW_SRC
	sc.reload()
	view = Node2D.new()
	view.set_script(sc)
	view.set("S", S)
	view.set("Battle", load("res://ui/Battle.gd"))
	root.add_child(view)
	frame = 0


func _process(_delta: float) -> bool:
	if view == null:
		return false
	frame += 1
	if frame == WARM:
		t_frames = Time.get_ticks_usec()
		(view.get("draw_us") as Array).clear()
	if frame == WARM + FRAMES:
		var du: Array = view.get("draw_us")
		var s: float = 0.0
		for x in du:
			s += float(x)
		rows.append({"n": int(counts[ci]), "draw_world_ms": snappedf(s / maxf(1.0, du.size()) / 1000.0, 0.01),
			"frame_ms": snappedf(float(Time.get_ticks_usec() - t_frames) / FRAMES / 1000.0, 0.01), "draws": du.size()})
		ci += 1
		if ci >= counts.size():
			print("HORDE DRAW " + JSON.stringify({"renderer": RenderingServer.get_video_adapter_name(), "rows": rows}))
			return true
		_next()
	return false
