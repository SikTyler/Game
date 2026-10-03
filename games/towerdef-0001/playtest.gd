extends SceneTree
# BALANCE / PLAYABILITY audit for Corehold. Drives the REAL loop (TowerState is
# the whole game; Main.gd is a replay view) at a fixed dt with a deterministic
# COMPETENT bot across a multi-run campaign, spending coins on the permanent
# base between runs exactly as a player would on the Base screen. Asserts:
#   - SOLVENT:        a fresh first run banks enough coins to buy something,
#   - FIRST GOAL:     a fresh first run (no meta) reaches wave FIRST_GOAL_WAVE,
#   - PROGRESSABLE:   the campaign's best wave climbs >= PROGRESS_GAIN over run 1,
#   - NO DEATH SPIRAL: no run regresses badly vs the previous one,
#   - NO TRIVIAL DOMINANT: neither a pure-eco nor a pure-weapon policy beats
#     the balanced policy by > 15% — the eco-vs-defense split is a real decision.
# Prints per-run lines + "PLAYTEST METRICS {json}" + exactly "PLAYTEST OK" (exit 0)
# or "PLAYTEST FAIL: ..." (exit 1). Clears user:// saves at start and end.

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const TuneRef := preload("res://Tune.gd")

const DT: float = 0.1
const MAX_SIM_S: float = 3600.0
const RUNS: int = 8
const FIRST_GOAL_WAVE: int = 5
const PROGRESS_GAIN: int = 5
const SEED_DEFAULT: int = 4242

var fail_count: int = 0


func _initialize() -> void:
	MetaSave.clear()
	var seed0: int = TuneRef.seed_of(SEED_DEFAULT)
	var camp: Dictionary = {}
	for pol in ["balanced", "eco", "weapon"]:
		camp[pol] = campaign(pol, seed0)
	var bal: Array = camp["balanced"]["waves"]
	var eco: Array = camp["eco"]["waves"]
	var wpn: Array = camp["weapon"]["waves"]
	var first: Dictionary = camp["balanced"]["first"]
	var first_wave: int = int(first["wave"])
	var bal_best: int = int(bal.max())
	var eco_best: int = int(eco.max())
	var wpn_best: int = int(wpn.max())
	var spiral: bool = false
	for k in range(1, bal.size()):
		if int(bal[k]) < int(bal[k - 1]) - 2:
			spiral = true
	var m: Dictionary = {
		"first_wave": first_wave, "first_coins": int(first["coins"]), "first_levels": int(first["level"]),
		"first_time_s": snappedf(float(first["time"]), 0.1),
		"balanced_waves": bal, "eco_waves": eco, "weapon_waves": wpn,
		"balanced_best": bal_best, "eco_best": eco_best, "weapon_best": wpn_best,
		"solvent": int(first["coins"]) >= 15,
		"first_goal_reachable": first_wave >= FIRST_GOAL_WAVE,
		"progressable": bal_best >= first_wave + PROGRESS_GAIN,
		"no_death_spiral": not spiral,
		"no_trivial_dominant": float(maxi(eco_best, wpn_best)) <= float(bal_best) * 1.15,
	}
	print("PLAYTEST METRICS " + JSON.stringify(m))
	for key in ["solvent", "first_goal_reachable", "progressable", "no_death_spiral", "no_trivial_dominant"]:
		if not bool(m[key]):
			fail_count += 1
			print("PLAYTEST FAIL: " + key)
	MetaSave.clear()
	if fail_count == 0:
		print("PLAYTEST OK")
		quit(0)
	else:
		quit(1)


func campaign(policy: String, seed0: int) -> Dictionary:
	var save: Dictionary = BaseMeta.default_save()
	var waves: Array = []
	var first: Dictionary = {}
	for r in RUNS:
		var res: Dictionary = run_once(save, policy, seed0 + r * 97)
		if r == 0:
			first = res
		waves.append(int(res["wave"]))
		print("PLAYTEST run %s #%d: wave %d lv %d kills %d coins %d (%.0fs) bank=%d" % [policy, r + 1, res["wave"], res["level"], res["kills"], res["coins"], res["time"], save["coins"]])
		spend_meta(save, policy)
	return {"waves": waves, "first": first}


static func _prefers(policy: String, id: String, weapons: int, ecos: int) -> int:
	var cat: String = BuildingDB.cat_of(id)
	match policy:
		"eco":
			return 3 if cat == "eco" else (1 if cat == "support" else 0)
		"weapon":
			return 3 if cat == "weapon" else (1 if cat == "support" else 0)
	# balanced: keep weapons slightly ahead of eco, support as glue
	if cat == "weapon":
		return 3 if weapons <= ecos + 1 else 1
	if cat == "eco":
		return 3 if ecos < weapons else 1
	return 2


static func _counts(S) -> Vector2i:
	var w: int = 0
	var e: int = 0
	for i in 25:
		var c: String = BuildingDB.cat_of(S.id_at(i))
		if c == "weapon":
			w += 1
		elif c == "eco":
			e += 1
	return Vector2i(w, e)


## Competent in-run policy; also used as a library by selftest.
static func bot_step(S, policy: String) -> void:
	if S.draft.size() > 0:
		var cnt: Vector2i = _counts(S)
		var best: int = 0
		var best_score: int = -99
		for k in S.draft.size():
			var c: Dictionary = S.draft[k]
			var sc: int = _prefers(policy, String(c["id"]), cnt.x, cnt.y) * 2 + (1 if String(c["kind"]) == "new" else 0)
			if sc > best_score:
				best_score = sc
				best = k
		S.choose_card(best)
	if S.pending_place != "":
		var free: Array = S.free_slots()
		if free.size() > 0:
			S.place(int(free[0]))
	# Spend cash: cheapest preferred upgrade (core counts as a weapon).
	var target: int = -1
	var cost: int = 1 << 30
	for i in 25:
		var id: String = S.id_at(i)
		if i != TowerState.CORE_SLOT and id == "":
			continue
		var pref: int = 3 if i == TowerState.CORE_SLOT and policy != "eco" else (_prefers(policy, id, 0, 0) if id != "" else 1)
		if pref < 2:
			continue
		var c2: int = S.upgrade_cost(i)
		if c2 < cost:
			cost = c2
			target = i
	if target >= 0 and S.cash >= float(cost):
		S.upgrade(target)


static func run_once(save: Dictionary, policy: String, seed_value: int) -> Dictionary:
	var S = TowerState.new()
	S.setup(seed_value, save)
	var t: float = 0.0
	var acc: float = 0.0
	while not S.over and t < MAX_SIM_S:
		S.tick(DT)
		t += DT
		acc += DT
		if acc >= 0.5:
			acc = 0.0
			bot_step(S, policy)
	return {"wave": S.wave, "level": S.level, "kills": S.kills, "coins": int(S.coins_run), "time": t}


static func spend_meta(save: Dictionary, policy: String) -> void:
	var guard: int = 0
	var core_order: Array = ["dmg", "hp", "regen"]
	while guard < 60:
		guard += 1
		var w: int = 0
		var e: int = 0
		var free: int = -1
		var cheapest: int = -1
		var cheapest_cost: int = 1 << 30
		for i in 25:
			var s: Dictionary = BaseMeta.slot_of(save, i)
			if s.is_empty():
				if free < 0 and BaseMeta.is_unlocked(save, i):
					free = i
				continue
			var c: String = BuildingDB.cat_of(String(s["id"]))
			if c == "weapon":
				w += 1
			elif c == "eco":
				e += 1
			var uc: int = BaseMeta.upgrade_cost(int(s["lvl"]))
			if uc < cheapest_cost:
				cheapest_cost = uc
				cheapest = i
		var did: bool = false
		if free >= 0:
			var best_id: String = ""
			var best_sc: int = -1
			for id in BuildingDB.ids():
				var sc: int = _prefers(policy, id, w, e) * 10 - BaseMeta.place_cost(id) / 5
				if sc > best_sc:
					best_sc = sc
					best_id = id
			did = BaseMeta.try_place(save, free, best_id)
		if not did:
			var core: Dictionary = save["core"]
			var stat: String = core_order[0]
			for k in core_order:
				if int(core[k]) < int(core[stat]):
					stat = k
			if BaseMeta.core_cost(int(core[stat])) <= cheapest_cost:
				did = BaseMeta.try_core(save, stat)
			elif cheapest >= 0:
				did = BaseMeta.try_upgrade(save, cheapest)
		if not did and free < 0:
			for i in 25:
				if not BaseMeta.is_unlocked(save, i) and i != 12:
					did = BaseMeta.try_unlock(save, i)
					break
		if not did:
			break
