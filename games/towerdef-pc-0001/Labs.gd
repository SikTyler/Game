extends RefCounted
## Research in the Outpost's Research Hall (SPEC A3, REDESIGN_SPEC §3.3).
## Pure static rules over save["research"] (was "labs" in v3):
##   {lvls:{id:int}, running:[]}
## Owner feedback #1: research is INSTANT (no timers, no rush, no gems). A
## Research Hall is still required (Outpost.research_queues > 0). `running`
## stays in the schema for old saves: claim() completes anything left in it.

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
	if d.has("costs"):
		var cs: Array = d["costs"]
		return int(cs[clampi(lvl, 0, cs.size() - 1)])
	return int(float(d["base"]) * pow(float(d["growth"]), float(lvl)))


## Research is instant: 0 seconds (kept for callers / old views).
static func duration(_s: Dictionary, _id: String, _lvl: int) -> int:
	return 0


static func is_running(s: Dictionary, id: String) -> bool:
	for r in running(s):
		if String((r as Dictionary)["track"]) == id:
			return true
	return false


static func can_start(s: Dictionary, id: String) -> bool:
	if not LabDB.DEFS.has(id) or is_running(s, id):
		return false
	var lvl: int = level(s, id)
	if lvl >= LabDB.max_of(id) or slots(s) <= 0:
		return false
	return int(s["coins"]) >= cost(id, lvl)


static func start(s: Dictionary, id: String, now: int) -> Array:
	if not can_start(s, id):
		return []
	var lvl: int = level(s, id)
	Stats.on_event(s, {"t": "coins_spent", "n": cost(id, lvl)})
	s["coins"] = int(s["coins"]) - cost(id, lvl)
	var ev: Array = [{"t": "lab_started", "track": id, "to_lvl": lvl + 1, "end": now, "slot": 0}]
	(_rb(s)["lvls"] as Dictionary)[id] = lvl + 1
	ev.append({"t": "lab_done", "track": id, "lvl": lvl + 1})
	ev.append_array(Missions.progress(s, "lab", 1))
	return ev


## Completes every leftover queued project from an old save (instant now).
static func claim(s: Dictionary, _now: int) -> Array:
	var ev: Array = []
	var keep: Array = []
	var labs: Dictionary = _rb(s)
	var lv: Dictionary = labs["lvls"]
	for r in running(s):
		var e: Dictionary = r
		if LabDB.DEFS.has(String(e["track"])):
			var id: String = String(e["track"])
			var to_lvl: int = mini(int(e["to_lvl"]), LabDB.max_of(id))
			lv[id] = maxi(int(lv.get(id, 0)), to_lvl)
			ev.append({"t": "lab_done", "track": id, "lvl": to_lvl})
	labs["running"] = keep
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
