extends RefCounted
## View-only "juice" state (no rules): trauma screen shake + hit-pause.
## Shake: trauma in [0,1] adds on impacts and decays linearly; the offset is
## max_offset * trauma^2 * smooth noise (Squirrel Eiserloh's GDC 2016 trauma
## model; in-house implementation, the Quiver template had no shake script).
## Hit-pause: a short real-time window in which the view feeds the engine a
## dilated delta. The deterministic engine is untouched — tests tick directly.

const MAX_OFFSET: float = 16.0
const DECAY: float = 1.6         # trauma per second
const FREQ: float = 30.0         # noise samples per second
const PAUSE_SCALE: float = 0.05  # engine time scale while hit-paused
# HORDE P6 caps: a horde fires hundreds of impacts a second; trauma added per
# frame is budgeted and hit-stop is short with a cooldown, so feedback stays
# readable instead of a permanent shake / slow-motion.
const TRAUMA_PER_FRAME: float = 0.35
const TRAUMA_MAX: float = 0.8
const PAUSE_MAX: float = 0.08
const PAUSE_COOLDOWN: float = 0.6

var trauma: float = 0.0
var pause_t: float = 0.0
var _time: float = 0.0
var _frame_trauma: float = 0.0
var _pause_cd: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	_noise.seed = 4242


func add_trauma(amount: float) -> void:
	var add: float = clampf(amount, 0.0, maxf(0.0, TRAUMA_PER_FRAME - _frame_trauma))
	_frame_trauma += add
	trauma = clampf(trauma + add, 0.0, TRAUMA_MAX)


func hit_pause(secs: float) -> void:
	if _pause_cd > 0.0 and pause_t <= 0.0:
		return
	if pause_t <= 0.0:
		_pause_cd = PAUSE_COOLDOWN
	pause_t = maxf(pause_t, minf(secs, PAUSE_MAX))


## Engine delta to use this frame (dilated during hit-pause).
func engine_delta(delta: float) -> float:
	return delta * PAUSE_SCALE if pause_t > 0.0 else delta


func update(delta: float) -> void:
	_time += delta
	trauma = maxf(0.0, trauma - DECAY * delta)
	pause_t = maxf(0.0, pause_t - delta)
	_pause_cd = maxf(0.0, _pause_cd - delta)
	_frame_trauma = 0.0


func offset() -> Vector2:
	if trauma <= 0.0:
		return Vector2.ZERO
	var amp: float = MAX_OFFSET * trauma * trauma
	var s: float = _time * FREQ
	return Vector2(_noise.get_noise_2d(s, 0.0), _noise.get_noise_2d(0.0, s + 100.0)) * amp


func reset() -> void:
	trauma = 0.0
	pause_t = 0.0
	_pause_cd = 0.0
	_frame_trauma = 0.0
