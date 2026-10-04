extends RefCounted
## Real-time research (SPEC A3/A4). Pure static rules over save["labs"]:
##   {lvls:{id:int}, slots:int(2..4), running:[{track,to_lvl,start,end}]}
## Every time function takes `now` (unix seconds) so tests are deterministic.

const Stats := preload("res://Stats.gd")
const LabDB := preload("res://data/LabDB.gd")
const Missions := preload("res://Missions.gd")
const TuneRef := preload("res://Tune.gd")

const MIN_SLOTS: int = 2
const MAX_SLOTS: int = 4


static func level(s: Dictionary, id: String) -> int:
	var labs: Dictionary = s["labs"]
	var lv: Dictionary = labs["lvls"]
	return int(lv.get(id, 0))


static func running(s: Dictionary) -> Array:
	var labs: Dictionary = s["labs"]
	return labs["running"]


static func slots(s: Dictionary) -> int:
	var labs: Dictionary = s["labs"]
	return int(labs["slots"])


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
	return int(float(d["dur_base"]) * pow(float(d["dur_growth"]), float(lvl)) * speed_mult(s))


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
	var labs: Dictionary = s["labs"]
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


static func slot_cost(s: Dictionary) -> int:
	var n: int = slots(s)
	if n == 2:
		return TuneRef.int_of("lab_slot3_gems", 60)
	if n == 3:
		return TuneRef.int_of("lab_slot4_gems", 150)
	return 0


static func buy_slot(s: Dictionary) -> Array:
	var n: int = slots(s)
	if n >= MAX_SLOTS:
		return []
	var c: int = slot_cost(s)
	if int(s["gems"]) < c:
		return []
	s["gems"] = int(s["gems"]) - c
	(s["labs"] as Dictionary)["slots"] = n + 1
	return [{"t": "lab_slot", "n": n + 1, "gems": c}]


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
	return LabDB.SPEED_STEPS.slice(0, n + 1)


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
