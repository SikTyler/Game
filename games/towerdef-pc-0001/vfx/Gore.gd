extends Node2D
## HORDE Phase 5 gore (view only, never touches rules).
##  * Blood bursts: a fixed pool of one-shot GPUParticles2D emitters, restarted
##    round-robin, so a kill storm never allocates nodes.
##  * Ground layer: a SubViewport that is NEVER cleared. Corpses / blood are
##    queued as stamp commands in a capped ring buffer; each frame at most
##    STAMPS_PER_FRAME of them are drawn ONCE into the viewport (UPDATE_ONCE),
##    so the cost is per new stamp, not per corpse on the ground.
## Main draws `ground_texture()` under the world (Battle.draw) via ground_rect().
## Level: "off" (nothing), "low" (few emitters, small stamps), "full".

const GROUND_PX: int = 2048          # texture size (square)
const GROUND_WORLD: float = 2600.0   # world units covered, centred on CENTER
const RING_CAP: int = 512            # pending stamp commands (oldest dropped)

var level: String = "low"
var center: Vector2 = Vector2.ZERO
var bursts_fired: int = 0
var stamps_drawn: int = 0

var _emitters: Array[GPUParticles2D] = []
var _next: int = 0
var _vp: SubViewport = null
var _painter: Node2D = null
var _ring: Array[Dictionary] = []     # pending stamps {p: Vector2 world, r: float, c: Color, s: int seed}
var _batch: Array[Dictionary] = []    # stamps drawn this frame
var _wipe: bool = false


func setup(world_center: Vector2, lvl: String) -> void:
	center = world_center
	_vp = SubViewport.new()
	_vp.size = Vector2i(GROUND_PX, GROUND_PX)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_painter = Node2D.new()
	_painter.draw.connect(_paint)
	_vp.add_child(_painter)
	set_level(lvl)


func set_level(lvl: String) -> void:
	if lvl == level and not _emitters.is_empty():
		return
	level = lvl
	for e in _emitters:
		e.queue_free()
	_emitters.clear()
	_next = 0
	var n: int = 0 if level == "off" else (6 if level == "low" else 16)
	for k in n:
		_emitters.append(_make_emitter(level == "full"))
	if level == "off":
		clear()


func stamps_per_frame() -> int:
	return 0 if level == "off" else (24 if level == "low" else 96)


func _make_emitter(full: bool) -> GPUParticles2D:
	var p: GPUParticles2D = GPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 24 if full else 12
	p.lifetime = 0.55
	p.explosiveness = 0.95
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, 380, 0)
	mat.initial_velocity_min = 70.0
	mat.initial_velocity_max = 260.0
	mat.damping_min = 80.0
	mat.damping_max = 160.0
	mat.scale_min = 2.0
	mat.scale_max = 5.0
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var gt: GradientTexture1D = GradientTexture1D.new()
	gt.gradient = ramp
	mat.color_ramp = gt
	p.process_material = mat
	add_child(p)
	return p


## One kill: spray (if an emitter is free in the ring) + queue a ground stamp.
func kill(pos: Vector2, col: Color, big: bool = false, stamp_too: bool = true) -> void:
	if level == "off":
		return
	if not _emitters.is_empty():
		var p: GPUParticles2D = _emitters[_next]
		_next = (_next + 1) % _emitters.size()
		p.position = pos
		p.modulate = col
		p.restart()
		p.emitting = true
		bursts_fired += 1
	if stamp_too:
		stamp(pos, (22.0 if big else 9.0) * (1.3 if level == "full" else 1.0), col)   # FB2: larger, readable pools


func stamp(pos: Vector2, r: float, col: Color) -> void:
	if level == "off":
		return
	if _ring.size() >= RING_CAP:
		_ring.pop_front()
	_ring.append({"p": pos, "r": r, "c": col, "s": int(pos.x * 13.0 + pos.y * 7.0)})


## MASS_HORDE §View: corpses from the C# death ring, packed [x, y, radius]*n
## (already capped by the caller to this frame's stamp budget).
func stamp_packed(c: PackedFloat32Array) -> void:
	if level == "off":
		return
	var col: Color = Color(0.85, 0.12, 0.1)
	var k: float = 1.3 if level == "full" else 1.0
	for i in c.size() / 3:
		stamp(Vector2(c[i * 3], c[i * 3 + 1]), maxf(5.0, c[i * 3 + 2] * 1.6) * k, col)


func pending() -> int:
	return _ring.size()


## Flush up to stamps_per_frame() queued stamps into the ground (one render).
func flush() -> void:
	if _vp == null:
		return
	var n: int = mini(stamps_per_frame(), _ring.size())
	if n <= 0 and not _wipe:
		return
	_batch = _ring.slice(0, n)
	_ring = _ring.slice(n)
	stamps_drawn += n
	_painter.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func clear() -> void:
	_ring.clear()
	_batch.clear()
	for e in _emitters:
		e.emitting = false
	if _vp != null:
		_wipe = true
		_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE   # one clear, then never again
		_painter.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func w2g(p: Vector2) -> Vector2:
	return (p - center) * (float(GROUND_PX) / GROUND_WORLD) + Vector2(GROUND_PX, GROUND_PX) * 0.5


func _paint() -> void:
	_wipe = false
	var k: float = float(GROUND_PX) / GROUND_WORLD
	for d in _batch:
		var g: Vector2 = w2g(d["p"])
		var r: float = float(d["r"]) * k
		var c: Color = (d["c"] as Color).lerp(Color(0.62, 0.03, 0.05), 0.65).darkened(0.15)   # FB2: blood red, brighter
		var s: int = int(d["s"])
		_painter.draw_circle(g, r, Color(c, 0.7))   # corpse / pool
		for j in 4:   # splats, deterministic from the stamp seed
			var a: float = float((s * (j + 3) * 2654435761) % 6283) / 1000.0
			var dd: float = r * (1.2 + float((s >> j) & 7) * 0.25)
			_painter.draw_circle(g + Vector2.from_angle(a) * dd, r * 0.42, Color(c, 0.62))
	_batch.clear()


func ground_texture() -> Texture2D:
	return null if _vp == null else _vp.get_texture()


## World-space rect the ground texture covers.
func ground_rect() -> Rect2:
	return Rect2(center - Vector2(GROUND_WORLD, GROUND_WORLD) * 0.5, Vector2(GROUND_WORLD, GROUND_WORLD))
