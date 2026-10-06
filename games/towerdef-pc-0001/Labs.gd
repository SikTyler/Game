extends RefCounted
## Research in the Outpost's Research Hall (SPEC A3, V2 P8).
## Pure static rules over save["research"] (was "labs" in v3):
##   {lvls:{id:int}, running:[]}
## Owner feedback #1: research is INSTANT (no timers, no rush, no gems). A
## Research Hall is still required (Outpost.research_queues > 0). `running`
## stays in the schema for old saves: claim() completes anything left in it.
## V2 P8: a project opens at its Research Hall row (LabDB.hall: Hall level 1 /
## 3 / 5 / 8) once its prerequisites (LabDB.req) are met; every price is cut
## by Lab Discount (-3% per level); run_fx() / enemy() feed the run.

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


## List price of step `lvl` -> lvl + 1 (before Lab Discount).
static func cost(id: String, lvl: int) -> int:
	var d: Dictionary = LabDB.DEFS.get(id, {})
	if d.is_empty():
		return 0
	if d.has("costs"):
		var cs: Array = d["costs"]
		return int(cs[clampi(lvl, 0, cs.size() - 1)])
	return int(float(d["base"]) * pow(float(d["growth"]), float(lvl)))


## Lab Discount: -3% per level on every research price.
static func discount(s: Dictionary) -> float:
	return 0.03 * float(mini(level(s, "lab_discount"), LabDB.max_of("lab_discount")))


## What the next level of `id` costs this save (Lab Discount applied).
static func price(s: Dictionary, id: String) -> int:
	return int(round(float(cost(id, level(s, id))) * (1.0 - discount(s))))


## Research Hall level a project needs (its row).
static func hall_req(id: String) -> int:
	return int(LabDB.get_def(id).get("hall", 1))


## Unmet prerequisites of `id`: [[id, lvl], ...] (empty when all are met).
static func missing_reqs(s: Dictionary, id: String) -> Array:
	var out: Array = []
	for r in LabDB.get_def(id).get("req", []):
		if level(s, String((r as Array)[0])) < int((r as Array)[1]):
			out.append(r)
	return out


## Why `id` can't be researched yet ("" when it is open): the Hall row
## first, then the first missing prerequisite. Coins are not checked here.
static func why_locked(s: Dictionary, id: String) -> String:
	if not LabDB.DEFS.has(id):
		return "Unknown research"
	if Outpost.level_of(s, "research") < hall_req(id):
		return "Needs Research Hall Lv %d" % hall_req(id)
	var mr: Array = missing_reqs(s, id)
	if not mr.is_empty():
		var r: Array = mr[0]
		return "Needs %s Lv %d" % [String(LabDB.get_def(String(r[0]))["name"]), int(r[1])]
	return ""


static func is_open(s: Dictionary, id: String) -> bool:
	return why_locked(s, id) == ""


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
	if lvl >= LabDB.max_of(id) or slots(s) <= 0 or not is_open(s, id):
		return false
	return int(s["coins"]) >= price(s, id)


static func start(s: Dictionary, id: String, now: int) -> Array:
	if not can_start(s, id):
		return []
	var lvl: int = level(s, id)
	var c: int = price(s, id)
	Stats.on_event(s, {"t": "coins_spent", "n": c})
	s["coins"] = int(s["coins"]) - c
	var ev: Array = [{"t": "lab_started", "track": id, "to_lvl": lvl + 1, "end": now, "slot": 0, "cost": c}]
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
	var n: int = clampi(level(s, "speed"), 0, LabDB.max_of("speed"))
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
		# V2 P8
		"aim": 0.05 * float(level(s, "manual")),
		"bounty": 0.10 * float(level(s, "bounty")),
		"items": 0.10 * float(level(s, "loot_theory")),
		"banish": level(s, "banish_r"),
		"locks": level(s, "draft_lock"),
		"choices": level(s, "draft_choices"),
	}


## Run fx from research (LabDB fx x level), summed into the run's pf().
static func run_fx(s: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in LabDB.IDS:
		var fx: Dictionary = LabDB.get_def(String(id)).get("fx", {})
		var lv: int = level(s, String(id))
		if lv <= 0:
			continue
		for k in fx.keys():
			out[k] = float(out.get(k, 0.0)) + float(fx[k]) * float(lv)
	return out


## Enemy-side research cuts (fractions): hp / dmg / spd / elite HP / Sapper blast.
static func enemy(s: Dictionary) -> Dictionary:
	return {
		"hp": 0.01 * float(level(s, "en_hp")),
		"dmg": 0.02 * float(level(s, "en_atk")),
		"spd": 0.01 * float(level(s, "en_speed")),
		"elite": 0.03 * float(level(s, "elite_hp")),
		"sapper": 0.08 * float(level(s, "sapper_damp")),
	}


## Every research level (TowerState reads TrackDB unlocks from it).
static func levels(s: Dictionary) -> Dictionary:
	return (_rb(s)["lvls"] as Dictionary).duplicate()
