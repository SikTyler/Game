extends RefCounted
## Lifetime stats + run history (PC_SPEC §4). Pure static functions over the
## save Dictionary, fed ONLY through on_event / on_events with engine events
## (TowerState run events, BaseMeta "coins_spent"). Missions.on_run_events
## forwards every run event here, so the view feeds both with one call.
##   save["stats"]   = {kills, bosses, kills_by_kind{}, waves, runs, play_s,
##                      coins_earned, coins_spent, placed{}, best_by_mode{},
##                      dps_best}
##   save["history"] = last HISTORY_MAX runs, newest last:
##                     {seed, tier, mode, modifiers, wave, coins, duration_s,
##                      build:[ids by cell], perks, ts}

const HISTORY_MAX: int = 50
const MODES: Array = ["normal", "endless", "challenge"]
const INT_KEYS: Array = ["kills", "bosses", "waves", "runs", "coins_earned", "coins_spent",
	"parts_found", "crates_opened", "specials_cast", "couriers", "outpost_collects", "reforges"]


static func default_stats() -> Dictionary:
	return {
		"kills": 0, "bosses": 0, "kills_by_kind": {}, "waves": 0, "runs": 0, "play_s": 0.0,
		"coins_earned": 0, "coins_spent": 0, "placed": {},
		"best_by_mode": {"normal": 0, "endless": 0, "challenge": 0}, "dps_best": 0.0,
		# Redesign meta counters (achievements): parts found, crates opened,
		# specials cast, Couriers caught, Outpost collects, Reforges.
		"parts_found": 0, "crates_opened": 0, "specials_cast": 0, "couriers": 0, "outpost_collects": 0, "reforges": 0,
		# MASS_HORDE §D6: kills per weapon source (gun, mortar, ..., core, troop, special).
		"kills_by_weapon": {},
	}


static func _st(s: Dictionary) -> Dictionary:
	if not (s.get("stats", null) is Dictionary):
		s["stats"] = default_stats()
	var st: Dictionary = s["stats"]
	var d: Dictionary = default_stats()
	for k in d.keys():
		if not st.has(k):
			st[k] = d[k]
	return st


static func _bump(dict: Dictionary, key: String, n: int = 1) -> void:
	dict[key] = int(dict.get(key, 0)) + n


## Mode bucket of a finished run: endless, challenge (any modifier) or normal.
static func mode_of(ev: Dictionary) -> String:
	if String(ev.get("mode", "normal")) == "endless":
		return "endless"
	if (ev.get("modifiers", []) as Array).size() > 0:
		return "challenge"
	return "normal"


static func on_events(s: Dictionary, events: Array) -> void:
	for e in events:
		on_event(s, e)


static func on_event(s: Dictionary, e: Dictionary) -> void:
	var st: Dictionary = _st(s)
	match String(e.get("t", "")):
		"kill":
			st["kills"] = int(st["kills"]) + 1
			_bump(st["kills_by_kind"], String(e.get("kind", "drone")))
		"kills":   # horde aggregate (per body)
			st["kills"] = int(st["kills"]) + int(e.get("n", 0))
			var bk: Dictionary = e.get("by_kind", {})
			for kk in bk:
				_bump(st["kills_by_kind"], String(kk), int(bk[kk]))
		"boss_bounty":
			st["bosses"] = int(st["bosses"]) + 1
		"wave":
			st["waves"] = int(st["waves"]) + 1
		"placed":
			_bump(st["placed"], String(e.get("id", "")))
		"coins_spent":
			st["coins_spent"] = int(st["coins_spent"]) + maxi(0, int(e.get("n", 0)))
		"game_over":
			st["runs"] = int(st["runs"]) + 1
			st["play_s"] = float(st["play_s"]) + maxf(0.0, float(e.get("duration_s", 0.0)))
			st["coins_earned"] = int(st["coins_earned"]) + maxi(0, int(e.get("coins", 0)))
			st["dps_best"] = maxf(float(st["dps_best"]), float(e.get("dps", 0.0)))
			st["specials_cast"] = int(st["specials_cast"]) + maxi(0, int(e.get("specials_cast", 0)))
			st["couriers"] = int(st["couriers"]) + maxi(0, int(e.get("couriers", 0)))
			var kw: Dictionary = e.get("kills_by_weapon", {}) if e.get("kills_by_weapon", {}) is Dictionary else {}
			for wk in kw:
				_bump(st["kills_by_weapon"], String(wk), int(kw[wk]))
			var bm: Dictionary = st["best_by_mode"]
			var m: String = mode_of(e)
			bm[m] = maxi(int(bm.get(m, 0)), int(e.get("wave", 0)))
			record_run(s, e)


## Append a finished run (a game_over event) to the history ring buffer.
static func record_run(s: Dictionary, e: Dictionary) -> void:
	if not (s.get("history", null) is Array):
		s["history"] = []
	var h: Array = s["history"]
	h.append({
		"seed": int(e.get("seed", 0)), "tier": int(e.get("tier", 1)), "mode": String(e.get("mode", "normal")),
		"modifiers": (e.get("modifiers", []) as Array).duplicate(), "wave": int(e.get("wave", 0)),
		"coins": int(e.get("coins", 0)), "duration_s": float(e.get("duration_s", 0.0)),
		"build": (e.get("build", []) as Array).duplicate(), "perks": (e.get("perks", []) as Array).duplicate(),
		"ts": int(e.get("ts", 0)),
	})
	while h.size() > HISTORY_MAX:
		h.remove_at(0)


## Options to replay a history entry with TowerState.setup (same seed, tier,
## mode and modifiers -> identical waves given the same base).
static func retry_opts(entry: Dictionary) -> Dictionary:
	return {"seed": int(entry.get("seed", 0)), "tier": int(entry.get("tier", 1)), "mode": String(entry.get("mode", "normal")), "modifiers": (entry.get("modifiers", []) as Array).duplicate()}


## The most-placed building ids (favourite build), most first.
static func favourite(s: Dictionary, n: int = 3) -> Array:
	var placed: Dictionary = _st(s)["placed"]
	var ids: Array = placed.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return int(placed[a]) > int(placed[b]) or (int(placed[a]) == int(placed[b]) and String(a) < String(b)))
	return ids.slice(0, n)


static func _int_map(src: Variant) -> Dictionary:
	var o: Dictionary = {}
	if src is Dictionary:
		var d: Dictionary = src
		for k in d.keys():
			o[String(k)] = maxi(0, int(d[k]))
	return o


## JSON-safe coercion for BaseMeta.normalize (floats -> ints, unknowns dropped).
static func normalize_stats(src: Variant) -> Dictionary:
	var st_in: Dictionary = src if src is Dictionary else {}
	var d: Dictionary = default_stats()
	for k in INT_KEYS:
		d[k] = maxi(0, int(st_in.get(k, 0)))
	d["play_s"] = maxf(0.0, float(st_in.get("play_s", 0.0)))
	d["dps_best"] = maxf(0.0, float(st_in.get("dps_best", 0.0)))
	d["kills_by_kind"] = _int_map(st_in.get("kills_by_kind", {}))
	d["kills_by_weapon"] = _int_map(st_in.get("kills_by_weapon", {}))
	d["placed"] = _int_map(st_in.get("placed", {}))
	var bm_in: Dictionary = st_in.get("best_by_mode", {}) if st_in.get("best_by_mode", {}) is Dictionary else {}
	var bm: Dictionary = {}
	for m in MODES:
		bm[m] = maxi(0, int(bm_in.get(m, 0)))
	d["best_by_mode"] = bm
	return d


static func normalize_history(src: Variant) -> Array:
	var out: Array = []
	if not (src is Array):
		return out
	for x in src:
		if not (x is Dictionary):
			continue
		var e: Dictionary = x
		var mods: Array = []
		for m in e.get("modifiers", []):
			mods.append(String(m))
		var build: Array = []
		for b in e.get("build", []):
			build.append(String(b))
		var perks: Array = []
		for p in e.get("perks", []):
			perks.append(String(p))
		out.append({
			"seed": int(e.get("seed", 0)), "tier": maxi(1, int(e.get("tier", 1))), "mode": String(e.get("mode", "normal")),
			"modifiers": mods, "wave": maxi(0, int(e.get("wave", 0))), "coins": maxi(0, int(e.get("coins", 0))),
			"duration_s": maxf(0.0, float(e.get("duration_s", 0.0))), "build": build, "perks": perks, "ts": maxi(0, int(e.get("ts", 0))),
		})
	while out.size() > HISTORY_MAX:
		out.remove_at(0)
	return out
