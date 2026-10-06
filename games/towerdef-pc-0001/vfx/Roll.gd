extends RefCounted
## Number roll-up ("slot reel") for counters: the shown value eases from the
## old number to the new one, then pops (a short scale bump) on landing.
## Bigger jumps roll longer. View only and deterministic: the curve depends
## on (from, to, elapsed) alone, so tests can sample it (st_kit).

const MIN_DUR: float = 0.35
const MAX_DUR: float = 1.2
const POP_DUR: float = 0.22
const POP_SCALE: float = 0.18

var from: float = 0.0
var to: float = 0.0
var t: float = 0.0
var dur: float = 0.0
var started: bool = false


## Roll time for a jump of `delta`: 0.35 s, +0.12 s per decade, capped at 1.2 s.
static func duration(delta: float) -> float:
	return clampf(MIN_DUR + 0.12 * log(absf(delta) + 1.0) / log(10.0), MIN_DUR, MAX_DUR)


## Ease-out cubic: fast start, soft landing.
static func ease_out(x: float) -> float:
	var k: float = 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - k * k * k


## Value shown `el` seconds into a roll from `a` to `b` lasting `d` seconds.
static func value_at(a: float, b: float, el: float, d: float) -> float:
	if d <= 0.0 or el >= d:
		return b
	return lerpf(a, b, ease_out(el / d))


## Landing pop: 1.0 while rolling, then up to 1 + POP_SCALE and back to 1.0.
static func pop_at(el: float, d: float) -> float:
	var p: float = el - d
	if d <= 0.0 or p < 0.0 or p > POP_DUR:
		return 1.0
	return 1.0 + POP_SCALE * sin(PI * p / POP_DUR)


## Points the counter at a new value. The first call (or `snap`) jumps there.
func set_target(v: float, snap: bool = false) -> void:
	if not started or snap:
		from = v
		to = v
		t = 0.0
		dur = 0.0
		started = true
		return
	if is_equal_approx(v, to):
		return
	from = value()
	to = v
	t = 0.0
	dur = duration(to - from)


func update(delta: float) -> void:
	t += maxf(0.0, delta)


func value() -> float:
	return value_at(from, to, t, dur)


func scale() -> float:
	return pop_at(t, dur)


## True while the number is still moving (or popping).
func busy() -> bool:
	return dur > 0.0 and t < dur + POP_DUR
