extends RefCounted
## Real-time research in the Outpost's Research Hall (SPEC A3/A4, REDESIGN
## SPEC §3.3). Pure static rules over save["research"] (was "labs" in v3):
##   {lvls:{id:int}, running:[{track,to_lvl,start,end}]}
## Queue count = Research Hall level (1/2/3 at Hall L1/L4/L8; 0 without a
## Hall); gem-bought lab slots are gone. Scholar decor next to the Hall speeds
## research (Outpost.hall_speed). Every time function takes `now`.

const Stats := preload("res://Stats.gd")
const LabDB := preload("res://data/LabDB.gd")
const Missions := preload("res://Missions.gd")
const TuneRef := preload("res://Tune.gd")
const Outpost := preload("res://Outpost.gd")

const MIN_SLOTS: int = 1
const MAX_SLOTS: int = 3


static func default_block() -> Dictionary:
	var lv: Dictionary = {}
	for id in LabDB.IDS:
		lv[id] = 0
	return {"lvls": lv, "running": []}


static func _rb(s: Dictionary) -> Dictionary:
	if not (s.get("research", null) is Dictionary):
		s["research"] = default_block()
	var r: Dictionary = s["research"]
	if not (r.get("lvls", null) is Dictionary):
		r["lvls"] = default_block()["lvls"]
	if not (r.get("running", null) is Array):
		r["running"] = []
	return r


static func level(s: Dictionary, id: String) -> int:
	return int((_rb(s)["lvls"] as Dictionary).get(id, 0))


static func running(s: Dictionary) -> Array:
	return _rb(s)["running"]


## Queues = Research Hall level band (AC-20).
static func slots(s: Dictionary) -> int:
	return Outpost.research_queues(s)


static func cost(id: String, lvl: int) -> int:
	var d: Dictionary = LabDB.DEFS.get(id, {})
	if d.is_empty():
		return 0
	return int(float(d["base"]) * pow(float(d["growth"]), float(lvl)))


static func speed_mult(s: Dictionary) -> float:
	return maxf(0.4, 1.0 - 0.06 * float(level(s, "labspeed")))


## Seconds to research `id` from lvl -> lvl+1.
static func duration(s: Dictionary, id: String, lvl: int) -> int:
	var d: Dictionary = LabDB.DEFS.get(id, {})
	if d.is_empty():
		return 0
	return int(float(d["dur_base"]) * pow(float(d["dur_growth"]), float(lvl)) * speed_mult(s) / Outpost.hall_speed(s))


static func is_running(s: Dictionary, id: String) -> bool:
	for r in running(s):
		if String((r as Dictionary)["track"]) == id:
			return true
	return false


static func can_start(s: Dictionary, id: String) -> bool:
	if not LabDB.DEFS.has(id) or is_running(s, id):
		return false
	var lvl: int = level(s, id)
	if lvl >= LabDB.max_of(id) or running(s).size() >= slots(s):
		return false
	return int(s["coins"]) >= cost(id, lvl)


static func start(s: Dictionary, id: String, now: int) -> Array:
	if not can_start(s, id):
		return []
	var lvl: int = level(s, id)
	Stats.on_event(s, {"t": "coins_spent", "n": cost(id, lvl)})
	s["coins"] = int(s["coins"]) - cost(id, lvl)
	var end_t: int = now + duration(s, id, lvl)
	running(s).append({"track": id, "to_lvl": lvl + 1, "start": now, "end": end_t})
	var ev: Array = [{"t": "lab_started", "track": id, "to_lvl": lvl + 1, "end": end_t, "slot": running(s).size() - 1}]
	ev.append_array(Missions.progress(s, "lab", 1))
	return ev


## Completes every slot whose end has passed.
static func claim(s: Dictionary, now: int) -> Array:
	var ev: Array = []
	var keep: Array = []
	var labs: Dictionary = _rb(s)
	var lv: Dictionary = labs["lvls"]
	for r in running(s):
		var e: Dictionary = r
		if now >= int(e["end"]):
			var id: String = String(e["track"])
			var to_lvl: int = mini(int(e["to_lvl"]), LabDB.max_of(id))
			lv[id] = maxi(int(lv.get(id, 0)), to_lvl)
			ev.append({"t": "lab_done", "track": id, "lvl": to_lvl})
		else:
			keep.append(e)
	labs["running"] = keep
	return ev


static func rush_cost(s: Dictionary, slot: int, now: int) -> int:
	var run: Array = running(s)
	if slot < 0 or slot >= run.size():
		return 0
	var rem: int = maxi(0, int((run[slot] as Dictionary)["end"]) - now)
	if rem <= 0:
		return 0
	var per: float = TuneRef.num("lab_rush_min_per_gem", 30.0)
	return maxi(1, int(ceil(float(rem) / 60.0 / per)))


static func rush(s: Dictionary, slot: int, now: int) -> Array:
	var run: Array = running(s)
	if slot < 0 or slot >= run.size():
		return []
	var g: int = rush_cost(s, slot, now)
	if int(s["gems"]) < g:
		return []
	s["gems"] = int(s["gems"]) - g
	(run[slot] as Dictionary)["end"] = now
	var ev: Array = [{"t": "lab_rushed", "gems": g, "slot": slot}]
	ev.append_array(claim(s, now))
	return ev


static func progress(s: Dictionary, slot: int, now: int) -> float:
	var run: Array = running(s)
	if slot < 0 or slot >= run.size():
		return 0.0
	var e: Dictionary = run[slot]
	var a: int = int(e["start"])
	var b: int = int(e["end"])
	if b <= a:
		return 1.0
	return clampf(float(now - a) / float(b - a), 0.0, 1.0)


static func any_done(s: Dictionary, now: int) -> bool:
	for r in running(s):
		if now >= int((r as Dictionary)["end"]):
			return true
	return false


## Unlocked game-speed steps: [1.0] + one per Speed lab level.
static func speed_steps(s: Dictionary) -> Array:
	var n: int = clampi(level(s, "speed"), 0, 3)
	var steps: Array = LabDB.SPEED_STEPS.slice(0, n + 1)
	# Reforge `tempo`: +0.25x max game speed per level (stacks on the lab).
	var rf: Variant = s.get("reforge", null)
	var tempo: int = 0
	if rf is Dictionary and (rf as Dictionary).get("nodes", null) is Dictionary:
		tempo = clampi(int(((rf as Dictionary)["nodes"] as Dictionary).get("tempo", 0)), 0, 4)
	var top: float = float(steps[steps.size() - 1])
	for k in tempo:
		steps.append(top + 0.25 * float(k + 1))
	return steps


## Run-facing lab modifiers.
static func modifiers(s: Dictionary) -> Dictionary:
	return {
		"dmg": 0.05 * float(level(s, "dmg")),
		"hp": 0.05 * float(level(s, "hp")),
		"coin": 0.05 * float(level(s, "coin")),
		"xp": 0.04 * float(level(s, "xp")),
		"start_cash": 15 * level(s, "startcash"),
		"rerolls": level(s, "reroll"),
		"offcap_h": level(s, "offcap"),
		"offrate": 0.05 * float(level(s, "offrate")),
	}
