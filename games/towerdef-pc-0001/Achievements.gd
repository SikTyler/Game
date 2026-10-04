extends RefCounted
## Achievement engine (PC_SPEC §5). Static, pure rules: consumes engine events
## (TowerState / Missions / meta actions) plus the persistent save, records
## unlocks in save["achievements"] = {unlocked:{id: unix_ts}, missions_claimed:int}
## and mirrors each NEW unlock to SteamService exactly once. Returns
## {"t": "achievement", "id", "name"} events for the view to toast.
##
## Run-scoped facts (core damage before wave 11, time at wave 40, active
## synergies) live in a caller-owned `run` Dictionary from new_run().

const AchievementDB := preload("res://data/AchievementDB.gd")
const SteamService := preload("res://SteamService.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Tiers := preload("res://Tiers.gd")
const LabDB := preload("res://data/LabDB.gd")
const Labs := preload("res://Labs.gd")
const CardDB := preload("res://data/CardDB.gd")
const Cards := preload("res://Cards.gd")


## Per-frame combat events that never change a save-based achievement.
const HOT: Array = ["shot", "dmg", "kill", "core_hit", "enemy_shot", "shield_hit", "split", "refined", "interest"]


static func new_run() -> Dictionary:
	return {"wave": 1, "damaged_early": false, "time": 0.0, "mode": "normal", "modifiers": [], "synergies": 0, "active": false}


static func normalize(src: Variant) -> Dictionary:
	var d: Dictionary = src if src is Dictionary else {}
	var un: Dictionary = {}
	var un_in: Variant = d.get("unlocked", {})
	if un_in is Dictionary:
		var valid: Array = AchievementDB.ids()
		for k in (un_in as Dictionary).keys():
			if valid.has(String(k)):
				un[String(k)] = maxi(0, int((un_in as Dictionary)[k]))
	return {"unlocked": un, "missions_claimed": maxi(0, int(d.get("missions_claimed", 0)))}


static func _a(save: Dictionary) -> Dictionary:
	if not (save.get("achievements", null) is Dictionary) or not ((save["achievements"] as Dictionary).get("unlocked", null) is Dictionary):
		save["achievements"] = normalize(save.get("achievements", {}))
	return save["achievements"]


static func is_unlocked(save: Dictionary, id: String) -> bool:
	return (_a(save)["unlocked"] as Dictionary).has(id)


static func unlocked_count(save: Dictionary) -> int:
	return (_a(save)["unlocked"] as Dictionary).size()


## Unlock once; mirrors to Steam. Returns [] if already unlocked/unknown.
static func unlock(save: Dictionary, id: String, now: int = 0) -> Array:
	var def: Dictionary = AchievementDB.get_def(id)
	if def.is_empty() or is_unlocked(save, id):
		return []
	(_a(save)["unlocked"] as Dictionary)[id] = now
	SteamService.unlock_achievement(id)
	return [{"t": "achievement", "id": id, "name": String(def["name"])}]


## Re-push every recorded unlock to Steam (e.g. after a cloud restore).
static func resync(save: Dictionary) -> int:
	var n: int = 0
	for id in (_a(save)["unlocked"] as Dictionary).keys():
		SteamService.unlock_achievement(String(id))
		n += 1
	return n


static func _build_has_cat(build: Array, cat: String) -> bool:
	for id in build:
		var s: String = String(id)
		if s == "" or s == "core":
			continue
		if BuildingDB.DEFS.has(s) and String((BuildingDB.DEFS[s] as Dictionary).get("cat", "")) == cat:
			return true
	return false


static func _build_count(build: Array) -> int:
	var n: int = 0
	for id in build:
		var s: String = String(id)
		if s != "" and s != "core" and BuildingDB.DEFS.has(s):
			n += 1
	return n


## Feed a batch of engine events. `time_alive` (seconds of game time) is the
## run clock when known (TowerState.time_alive); -1 keeps the last value.
static func on_events(save: Dictionary, run: Dictionary, events: Array, now: int = 0, time_alive: float = -1.0) -> Array:
	var out: Array = []
	if time_alive >= 0.0:
		run["time"] = time_alive
	var meta: bool = false
	for e in events:
		if not (e is Dictionary):
			continue
		var ev: Dictionary = e
		if not HOT.has(String(ev.get("t", ""))):
			meta = true
		match String(ev.get("t", "")):
			"run_start":
				var fresh: Dictionary = new_run()
				for k in fresh.keys():
					run[k] = fresh[k]
				run["active"] = true
				run["mode"] = String(ev.get("mode", "normal"))
				run["modifiers"] = (ev.get("modifiers", []) as Array).duplicate()
			"core_hit", "enemy_shot":
				if int(run.get("wave", 1)) <= 10 and float(ev.get("dmg", 1.0)) > 0.0:
					run["damaged_early"] = true
			"wave":
				var w: int = int(ev.get("wave", 0))
				run["wave"] = maxi(int(run.get("wave", 1)), w)
				out.append_array(_wave_checks(save, run, w, now))
			"boss_bounty":
				out.append_array(unlock(save, "ACH_FIRST_BOSS", now))
			"synergies":
				run["synergies"] = maxi(int(run.get("synergies", 0)), int(ev.get("n", 0)))
				if int(ev.get("n", 0)) >= AchievementDB.SYNERGY_TARGET:
					out.append_array(unlock(save, "ACH_ALL_SYNERGY", now))
			"mission_claimed":
				var a: Dictionary = _a(save)
				a["missions_claimed"] = int(a["missions_claimed"]) + 1
			"game_over":
				out.append_array(_game_over(save, run, ev, now))
	if meta:
		out.append_array(check_save(save, now))
	return out


static func _wave_checks(save: Dictionary, run: Dictionary, w: int, now: int) -> Array:
	var out: Array = []
	var mods: Array = run.get("modifiers", [])
	if w >= 25:
		out.append_array(unlock(save, "ACH_WAVE_25", now))
	if w >= 100:
		out.append_array(unlock(save, "ACH_WAVE_100", now))
	if w >= 250 and String(run.get("mode", "")) == "endless":
		out.append_array(unlock(save, "ACH_WAVE_250", now))
	if w >= 11 and bool(run.get("active", false)) and not bool(run.get("damaged_early", true)):
		out.append_array(unlock(save, "ACH_NO_DAMAGE_10", now))
	if w >= AchievementDB.SPEEDRUN_WAVE and float(run.get("time", INF)) <= AchievementDB.SPEEDRUN_S:
		out.append_array(unlock(save, "ACH_SPEEDRUN", now))
	if w >= 51 and mods.size() >= 3:
		out.append_array(unlock(save, "ACH_MOD_3", now))
	if w >= 50 and mods.has("glass"):
		out.append_array(unlock(save, "ACH_GLASS_50", now))
	if w >= 100 and mods.has("allsides"):
		out.append_array(unlock(save, "ACH_ENCIRCLED_100", now))
	return out


static func _game_over(save: Dictionary, run: Dictionary, ev: Dictionary, now: int) -> Array:
	var out: Array = unlock(save, "ACH_FIRST_RUN", now)
	var w: int = int(ev.get("wave", 0))
	var build: Array = ev.get("build", [])
	var mods: Array = ev.get("modifiers", run.get("modifiers", []))
	run["modifiers"] = mods.duplicate()
	run["mode"] = String(ev.get("mode", run.get("mode", "normal")))
	if float(ev.get("duration_s", -1.0)) >= 0.0:
		run["time"] = float(ev["duration_s"])
	# Wave-reached checks again from the authoritative final wave (no speedrun:
	# duration at death is not the time at wave 40).
	var t_keep: float = float(run.get("time", INF))
	run["time"] = INF
	out.append_array(_wave_checks(save, run, w, now))
	run["time"] = t_keep
	if w >= 30 and _build_count(build) > 0 and not _build_has_cat(build, "weapon"):
		out.append_array(unlock(save, "ACH_ECO_ONLY", now))
	if w >= 60 and not _build_has_cat(build, "eco"):
		out.append_array(unlock(save, "ACH_NO_ECO", now))
	run["active"] = false
	return out


## Achievements that depend only on the persistent save.
static func check_save(save: Dictionary, now: int = 0) -> Array:
	var out: Array = []
	var st: Dictionary = save.get("stats", {}) if save.get("stats", {}) is Dictionary else {}
	if int(st.get("bosses", 0)) >= 1:
		out.append_array(unlock(save, "ACH_FIRST_BOSS", now))
	if int(st.get("bosses", 0)) >= 50:
		out.append_array(unlock(save, "ACH_BOSS_50", now))
	if int(st.get("kills", 0)) >= 100000:
		out.append_array(unlock(save, "ACH_KILLS_100K", now))
	if int(st.get("runs", 0)) >= 1:
		out.append_array(unlock(save, "ACH_FIRST_RUN", now))
	if int(save.get("best_wave", 0)) >= 25:
		out.append_array(unlock(save, "ACH_WAVE_25", now))
	if int(save.get("best_wave", 0)) >= 100:
		out.append_array(unlock(save, "ACH_WAVE_100", now))
	var en: Dictionary = save.get("endless", {}) if save.get("endless", {}) is Dictionary else {}
	if int(en.get("best", 0)) >= 250:
		out.append_array(unlock(save, "ACH_WAVE_250", now))
	if save.has("best_wave_by_tier"):
		var hi: int = Tiers.highest(save)
		if hi >= 3:
			out.append_array(unlock(save, "ACH_TIER_3", now))
		if hi >= 8:
			out.append_array(unlock(save, "ACH_TIER_8", now))
	if BaseMeta.endless_unlocked(save):
		out.append_array(unlock(save, "ACH_ENDLESS", now))
	if save.get("unlocked", null) is Array:
		var ring3: bool = false
		var cells: int = 0
		for i in BaseMeta.N:
			if i == BaseMeta.CORE_SLOT:
				continue
			if BaseMeta.is_unlocked(save, i):
				cells += 1
				if BaseMeta.cell_ring(i) >= 3:
					ring3 = true
		if ring3:
			out.append_array(unlock(save, "ACH_RING_3", now))
		if cells >= AchievementDB.FULL_BASE_CELLS:
			out.append_array(unlock(save, "ACH_FULL_BASE", now))
	if save.get("research", null) is Dictionary:
		for id in LabDB.DEFS.keys():
			if Labs.level(save, String(id)) >= int((LabDB.DEFS[id] as Dictionary)["max"]):
				out.append_array(unlock(save, "ACH_LABS_MAX", now))
				break
	if save.get("cards", null) is Dictionary:
		for id in Cards.owned(save).keys():
			if Cards.level(save, String(id)) >= CardDB.MAX_LVL:
				out.append_array(unlock(save, "ACH_CARD_MAX", now))
				break
	var sk: Dictionary = save.get("streak", {}) if save.get("streak", {}) is Dictionary else {}
	if int(sk.get("day_idx", 0)) >= 7 or int(sk.get("loops", 0)) >= 1:
		out.append_array(unlock(save, "ACH_STREAK_7", now))
	if int(_a(save)["missions_claimed"]) >= 50:
		out.append_array(unlock(save, "ACH_MISSIONS_50", now))
	return out
