extends Node2D
## Pooled CPUParticles2D kill bursts (view only). A fixed ring of one-shot
## emitters is created once; burst() restarts the next one at a position in a
## category colour, so a kill storm never allocates nodes and is capped at
## POOL concurrent bursts.

const POOL: int = 12

var _emitters: Array[CPUParticles2D] = []
var _next: int = 0


func _ready() -> void:
	for k in POOL:
		var p: CPUParticles2D = CPUParticles2D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 14
		p.lifetime = 0.45
		p.explosiveness = 0.95
		p.direction = Vector2.UP
		p.spread = 180.0
		p.gravity = Vector2(0, 260)
		p.initial_velocity_min = 90.0
		p.initial_velocity_max = 220.0
		p.scale_amount_min = 3.0
		p.scale_amount_max = 6.0
		p.damping_min = 60.0
		p.damping_max = 120.0
		var ramp: Gradient = Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = ramp
		add_child(p)
		_emitters.append(p)


func burst(pos: Vector2, col: Color, big: bool = false) -> void:
	if _emitters.is_empty():
		return
	var p: CPUParticles2D = _emitters[_next]
	_next = (_next + 1) % _emitters.size()
	p.position = pos
	p.color = col
	p.scale_amount_max = 10.0 if big else 6.0
	p.initial_velocity_max = 380.0 if big else 220.0
	p.restart()
	p.emitting = true


func clear() -> void:
	for p in _emitters:
		p.emitting = false
