extends Node
## Corehold audio player (view-side; NOT an autoload). Owned by Main.
## Pool of POOL AudioStreamPlayers on bus "SFX" (round-robin), per-clip rate
## limit, per-frame cap, one looping music player on bus "Music".
## Main maps engine events -> clip names; the engine never references audio.
## `clip_log` records every clip actually started (tests assert on it).

const POOL: int = 8
const DEFAULT_GAP_MS: int = 50
const FRAME_CAP: int = 4
const CLIPS: Array = [
	"shot_core", "shot_gun", "shot_mortar", "shot_tesla", "hit", "kill",
	"shield_break", "boss_spawn", "boss_kill", "wave_start", "levelup", "perk",
	"card_open", "lab_done", "place", "upgrade", "click", "coin", "core_hit", "game_over",
	# V2 P9: every weapon has its own shot (procedural, audio/recipes.json)
	"shot_flak", "shot_railgun", "shot_frost", "shot_pulse", "shot_missile", "shot_spike", "shot_mines", "shot_scatter",
	"shot_laser", "shot_saw", "shot_arcproj", "shot_sonic", "shot_harpoon", "shot_plasma", "shot_flakburst",
]
## Rapid clips get a longer minimum interval so a burst never stacks.
const GAP_MS: Dictionary = {"shot_core": 70, "shot_gun": 60, "shot_mortar": 90, "shot_tesla": 70, "hit": 50, "kill": 50, "core_hit": 80,
	"shot_flak": 90, "shot_railgun": 90, "shot_frost": 110, "shot_pulse": 120, "shot_missile": 90, "shot_spike": 70, "shot_mines": 90, "shot_scatter": 80,
	"shot_laser": 120, "shot_saw": 80, "shot_arcproj": 80, "shot_sonic": 140, "shot_harpoon": 90, "shot_plasma": 120, "shot_flakburst": 90}
const LOG_MAX: int = 256

var streams: Dictionary = {}
var players: Array = []
var music: AudioStreamPlayer
var next_idx: int = 0
var last_ms: Dictionary = {}
var frame_count: int = 0
var frame_id: int = -1
var clip_log: Array = []       # [{"clip": String, "ms": int}]
var muted: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Headless runs use the Dummy driver, which never mixes, so started playbacks
## would leak at exit. Clips are still logged; nothing is actually started.
var silent: bool = false


static func ensure_buses() -> void:
	for nm in ["Music", "SFX"]:
		if AudioServer.get_bus_index(nm) < 0:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, &"Master")


func _ready() -> void:
	ensure_buses()
	silent = AudioServer.get_driver_name() == "Dummy"
	rng.seed = 1337
	for c in CLIPS:
		var path: String = "res://audio/%s.wav" % String(c)
		if ResourceLoader.exists(path):
			streams[String(c)] = load(path)
	for k in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		players.append(p)
	music = AudioStreamPlayer.new()
	music.bus = &"Music"
	if ResourceLoader.exists("res://audio/theme.wav"):
		var st: AudioStreamWAV = load("res://audio/theme.wav")
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * float(st.mix_rate))
		music.stream = st
	add_child(music)


## Pitch for step `k` of a rising sequence (P2 casino juice): a whole tone
## per step from 1.0, capped at two octaves (a reel tick or reveal ladder).
static func seq_pitch(k: int) -> float:
	return minf(4.0, pow(2.0, float(maxi(0, k)) * 2.0 / 12.0))


## Starts `clip` unless rate-limited / frame-capped / unknown. Returns true if
## logged. `pitch` > 0 plays at that pitch (rising sequences); otherwise a
## small random detune.
func play(clip: String, pitch: float = -1.0) -> bool:
	if not streams.has(clip):
		return false
	var now_ms: int = Time.get_ticks_msec()
	var gap: int = int(GAP_MS.get(clip, DEFAULT_GAP_MS))
	if last_ms.has(clip) and now_ms - int(last_ms[clip]) < gap:
		return false
	var f: int = Engine.get_process_frames()
	if f != frame_id:
		frame_id = f
		frame_count = 0
	if frame_count >= FRAME_CAP:
		return false
	frame_count += 1
	last_ms[clip] = now_ms
	clip_log.append({"clip": clip, "ms": now_ms, "pitch": pitch if pitch > 0.0 else 1.0})
	if clip_log.size() > LOG_MAX:
		clip_log.remove_at(0)
	var p: AudioStreamPlayer = players[next_idx]
	next_idx = (next_idx + 1) % POOL
	if silent:
		return true
	p.stream = streams[clip]
	p.pitch_scale = pitch if pitch > 0.0 else rng.randf_range(0.97, 1.03)
	p.play()
	return true


func played(clip: String) -> bool:
	for e in clip_log:
		if String((e as Dictionary)["clip"]) == clip:
			return true
	return false


func clear_log() -> void:
	clip_log.clear()
	last_ms.clear()


func music_play() -> void:
	if not silent and music.stream != null and not music.playing:
		music.play()


func music_stop() -> void:
	music.stop()


static func lin_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


## Applies save["settings"] {music, sfx, mute} to the buses.
func apply_settings(settings: Dictionary) -> void:
	muted = bool(settings.get("mute", false))
	var mi: int = AudioServer.get_bus_index("Music")
	var si: int = AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(mi, lin_db(float(settings.get("music", 0.8))) - 4.0)
	AudioServer.set_bus_volume_db(si, lin_db(float(settings.get("sfx", 1.0))))
	AudioServer.set_bus_mute(mi, muted)
	AudioServer.set_bus_mute(si, muted)


## Release live playbacks before shutdown (otherwise the playing music leaks at exit).
func _exit_tree() -> void:
	music.stop()
	music.stream = null
	for p in players:
		(p as AudioStreamPlayer).stop()
		(p as AudioStreamPlayer).stream = null
