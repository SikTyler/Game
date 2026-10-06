extends RefCounted
## Daily missions + login streak (SPEC A6). save["missions"] =
## {day, list:[{tpl,target,prog,claimed,coins}], bonus_claimed}; save["streak"] =
## {day_idx(0..7), last_day, loops}. Same day => same missions (seeded by day).

const MissionDB := preload("res://data/MissionDB.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const TuneRef := preload("res://Tune.gd")
const Stats := preload("res://Stats.gd")

const PER_DAY: int = 3


static func day_of(now: int, tz_offset: int = 0) -> int:
	return int(floor(float(now + tz_offset) / 86400.0))


static func _m(s: Dictionary) -> Dictionary:
	return s["missions"]


static func list(s: Dictionary) -> Array:
	return _m(s)["list"]


static func roll(s: Dictionary, now: int, tz_offset: int = 0) -> Array:
	var day: int = day_of(now, tz_offset)
	var m: Dictionary = _m(s)
	if int(m["day"]) == day and not list(s).is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day)
	var pool: Array = MissionDB.IDS.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var b: int = int(s.get("best_wave", 0))
	var out: Array = []
	for k in PER_DAY:
		var tpl: String = String(pool[k])
		out.append({"tpl": tpl, "target": MissionDB.target(tpl, b), "prog": 0, "claimed": false, "coins": MissionDB.reward(tpl)})
	m["day"] = day
	m["list"] = out
	m["bonus_claimed"] = false
	return [{"t": "missions_rolled", "day": day}]


static func is_done(e: Dictionary) -> bool:
	return int(e["prog"]) >= int(e["target"])


## Advance every unclaimed mission of `tpl`. max_mode keeps the highest value
## seen (wave / cash-in-one-run) instead of adding.
static func progress(s: Dictionary, tpl: String, amount: int, max_mode: bool = false) -> Array:
	var ev: Array = []
	if not s.has("missions"):
		return ev
	var lst: Array = list(s)
	for idx in lst.size():
		var e: Dictionary = lst[idx]
		if String(e["tpl"]) != tpl or bool(e["claimed"]) or is_done(e):
			continue
		var p: int = maxi(int(e["prog"]), amount) if max_mode else int(e["prog"]) + amount
		e["prog"] = mini(p, int(e["target"]))
		if is_done(e):
			ev.append({"t": "mission_done", "idx": idx, "tpl": tpl})
	return ev


## Feed a run's event stream into mission progress + lifetime stats (every
## event is forwarded to Stats.on_event, which owns save["stats"] / history).
## (Lab starts and permanent upgrades are counted by Labs/BaseMeta directly.)
static func on_run_events(s: Dictionary, events: Array) -> Array:
	var ev: Array = []
	for x in events:
		var e: Dictionary = x
		Stats.on_event(s, e)
		match String(e.get("t", "")):
			"kill":
				ev.append_array(progress(s, "kill", 1))
			"kills":   # horde aggregate (per body)
				ev.append_array(progress(s, "kill", int(e.get("n", 0))))
			"wave":
				ev.append_array(progress(s, "wave", int(e.get("wave", 0)), true))
			"wave_kills":   # MASS_HORDE §D6: kills credited during one wave
				ev.append_array(progress(s, "wave_kills", int(e.get("n", 0)), true))
			"boss_bounty":
				ev.append_array(progress(s, "boss", 1))
			"placed":
				if BuildingDB.cat_of(String(e.get("id", ""))) == "eco":
					ev.append_array(progress(s, "eco", 1))
			"perk_taken":
				var pid: String = String(e.get("id", ""))
				if bool(e.get("tradeoff", false)) or MissionDB.TRADEOFF_PERKS.has(pid):
					ev.append_array(progress(s, "perk", 1))
			"game_over", "dead":
				if e.has("cash_earned"):
					ev.append_array(progress(s, "cash", int(e["cash_earned"]), true))
				if e.has("wave"):
					ev.append_array(progress(s, "wave", int(e["wave"]), true))
	return ev


static func claim(s: Dictionary, idx: int) -> Array:
	var lst: Array = list(s)
	if idx < 0 or idx >= lst.size():
		return []
	var e: Dictionary = lst[idx]
	if bool(e["claimed"]) or not is_done(e):
		return []
	e["claimed"] = true
	var g: int = int(e.get("coins", 0))
	add_coins(s, g)
	return [{"t": "mission_claimed", "idx": idx, "coins": g}]


static func all_claimed(s: Dictionary) -> bool:
	var lst: Array = list(s)
	if lst.is_empty():
		return false
	for x in lst:
		if not bool((x as Dictionary)["claimed"]):
			return false
	return true


static func claim_bonus(s: Dictionary) -> Array:
	var m: Dictionary = _m(s)
	if bool(m["bonus_claimed"]) or not all_claimed(s):
		return []
	m["bonus_claimed"] = true
	var g: int = TuneRef.int_of("mission_bonus_coins", 200)
	add_coins(s, g)
	return [{"t": "mission_bonus", "coins": g}]


static func has_claimable(s: Dictionary) -> bool:
	for x in list(s):
		var e: Dictionary = x
		if not bool(e["claimed"]) and is_done(e):
			return true
	return all_claimed(s) and not bool(_m(s)["bonus_claimed"])


# ---------------------------------------------------------------- streak
static func streak_available(s: Dictionary, now: int, tz_offset: int = 0) -> bool:
	var st: Dictionary = s["streak"]
	return int(st["last_day"]) != day_of(now, tz_offset)


## Ladder day (1..7) the next claim would pay.
static func streak_next_day(s: Dictionary, now: int, tz_offset: int = 0) -> int:
	var st: Dictionary = s["streak"]
	var day: int = day_of(now, tz_offset)
	var last: int = int(st["last_day"])
	if last >= 0 and day == last + 1:
		return int(st["day_idx"]) % 7 + 1
	if last == day:
		return int(st["day_idx"])
	return 1


static func streak_claim(s: Dictionary, now: int, tz_offset: int = 0) -> Array:
	if not streak_available(s, now, tz_offset):
		return []
	var st: Dictionary = s["streak"]
	var day: int = day_of(now, tz_offset)
	var last: int = int(st["last_day"])
	var idx: int = 1
	if last >= 0 and day == last + 1:
		idx = int(st["day_idx"]) % 7 + 1
		if idx == 1 and int(st["day_idx"]) == 7:
			st["loops"] = int(st["loops"]) + 1
	else:
		st["loops"] = 0
	st["day_idx"] = idx
	st["last_day"] = day
	var r: Dictionary = MissionDB.STREAK[idx - 1]
	var mult: float = minf(2.0, 1.0 + 0.1 * float(st["loops"]))
	var coins: int = int(floor(float(r["coins"]) * mult))
	s["coins"] = int(s["coins"]) + coins
	var ev: Array = [{"t": "streak_claimed", "day": idx, "coins": coins}]
	if int(r.get("scrap", 0)) > 0:
		s["scrap"] = int(s.get("scrap", 0)) + int(r["scrap"])
		ev[0]["scrap"] = int(r["scrap"])
	return ev


## Meta coin reward (missions / bonus).
static func add_coins(s: Dictionary, n: int) -> void:
	s["coins"] = int(s.get("coins", 0)) + n