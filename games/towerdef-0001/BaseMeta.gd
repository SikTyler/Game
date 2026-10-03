extends RefCounted
## Permanent base (the meta layer, The Tower's "workshop" as buildings).
## Pure static functions over the save Dictionary — the view writes it to disk
## via MetaSave. Save v2 shape (SPEC A1 / SYSTEMS §12):
##   {version:2, coins, gems, core:{dmg,hp,regen}, slots:{"<idx>":{id,lvl}},
##    unlocked:[idx], runs, best_wave, tier, best_wave_by_tier:{"N":w},
##    tiers_rewarded:[N], best_coin_rate:float, speed:float,
##    labs:{lvls,slots,running}, cards:{owned,equipped,slots},
##    missions:{day,list,bonus_claimed}, streak:{day_idx,last_day,loops},
##    last_seen:int, stats:{kills,bosses}, gem_log:{boss,mission,streak,tier}}

const BuildingDB := preload("res://data/BuildingDB.gd")
const LabDB := preload("res://data/LabDB.gd")
const CardDB := preload("res://data/CardDB.gd")
const MissionDB := preload("res://data/MissionDB.gd")
const Tiers := preload("res://Tiers.gd")
const Labs := preload("res://Labs.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const TuneRef := preload("res://Tune.gd")

const VERSION: int = 2
const CORE_SLOT: int = 12
const CORE_STATS: Array = ["dmg", "hp", "regen"]
const MAX_LVL: int = 15
## Hard ceiling for migrated core levels; the live cap is core_cap(s).
const CORE_HARD_MAX: int = 60
const GEM_SOURCES: Array = ["boss", "mission", "streak", "tier"]


static func default_save() -> Dictionary:
	var lv: Dictionary = {}
	for id in LabDB.IDS:
		lv[id] = 0
	return {
		"version": VERSION, "coins": 0, "gems": 0,
		"core": {"dmg": 0, "hp": 0, "regen": 0}, "slots": {}, "unlocked": [],
		"runs": 0, "best_wave": 0, "tier": 1, "best_wave_by_tier": {"1": 0},
		"tiers_rewarded": [], "best_coin_rate": 0.0, "speed": 1.0,
		"labs": {"lvls": lv, "slots": Labs.MIN_SLOTS, "running": []},
		"cards": {"owned": {}, "equipped": [], "slots": Cards.MIN_SLOTS},
		"missions": {"day": -1, "list": [], "bonus_claimed": false},
		"streak": {"day_idx": 0, "last_day": -1, "loops": 0},
		"last_seen": 0, "stats": {"kills": 0, "bosses": 0},
		"gem_log": {"boss": 0, "mission": 0, "streak": 0, "tier": 0},
		"boss_gems_today": {"day": -1, "n": 0},
	}


## v1 (no `version`) -> v2. Lossless for v1 fields; returns a new Dictionary.
static func migrate(s: Dictionary) -> Dictionary:
	var d: Dictionary = s.duplicate(true)
	if int(d.get("version", 1)) >= VERSION:
		return d
	var bw: int = int(d.get("best_wave", 0))
	d["best_wave_by_tier"] = {"1": bw}
	d["gems"] = 0
	d["tier"] = 1
	d["last_seen"] = 0
	var labs: Dictionary = d.get("labs", {})
	var lv: Dictionary = labs.get("lvls", {})
	lv.erase("armor")
	d["version"] = VERSION
	return d


static func _int_dict(src: Dictionary, keys: Array) -> Dictionary:
	var o: Dictionary = {}
	for k in keys:
		o[k] = int(src.get(k, 0))
	return o


## Coerce JSON floats to ints, fill missing keys, clamp levels, drop unknowns.
static func normalize(s_in: Dictionary) -> Dictionary:
	var s: Dictionary = s_in
	if int(s_in.get("version", 1)) < VERSION:
		s = migrate(s_in)
	var d: Dictionary = default_save()
	d["coins"] = maxi(0, int(s.get("coins", 0)))
	d["gems"] = maxi(0, int(s.get("gems", 0)))
	d["runs"] = maxi(0, int(s.get("runs", 0)))
	# tiers
	var bw_in: Dictionary = s.get("best_wave_by_tier", {})
	var bw: Dictionary = {}
	for t in range(1, Tiers.tier_max() + 1):
		if bw_in.has(str(t)):
			bw[str(t)] = maxi(0, int(bw_in[str(t)]))
	if not bw.has("1"):
		bw["1"] = 0
	d["best_wave_by_tier"] = bw
	var best: int = int(s.get("best_wave", 0))
	for k in bw.keys():
		best = maxi(best, int(bw[k]))
	d["best_wave"] = best
	var hi: int = Tiers.highest(d)
	d["tier"] = clampi(int(s.get("tier", 1)), 1, hi)
	var tr: Array = []
	for v in s.get("tiers_rewarded", []):
		var n: int = int(v)
		if n >= 2 and n <= Tiers.tier_max() and not tr.has(n):
			tr.append(n)
	tr.sort()
	d["tiers_rewarded"] = tr
	d["best_coin_rate"] = maxf(0.0, float(s.get("best_coin_rate", 0.0)))
	d["last_seen"] = maxi(0, int(s.get("last_seen", 0)))
	# base
	var core_in: Dictionary = s.get("core", {})
	var core: Dictionary = {}
	for k in CORE_STATS:
		core[k] = clampi(int(core_in.get(k, 0)), 0, CORE_HARD_MAX)
	d["core"] = core
	var cap: int = perm_lvl_cap(d)
	var slots_in: Dictionary = s.get("slots", {})
	var slots: Dictionary = {}
	for key in slots_in.keys():
		var e: Dictionary = slots_in[key]
		var id: String = String(e.get("id", ""))
		var idx: int = int(key)
		if BuildingDB.DEFS.has(id) and idx >= 0 and idx < 25 and idx != CORE_SLOT:
			slots[str(idx)] = {"id": id, "lvl": clampi(int(e.get("lvl", 1)), 1, cap)}
	d["slots"] = slots
	var un: Array = []
	for v in s.get("unlocked", []):
		var n2: int = int(v)
		if n2 >= 0 and n2 < 25 and n2 != CORE_SLOT and not un.has(n2):
			un.append(n2)
	d["unlocked"] = un
	# labs
	var labs_in: Dictionary = s.get("labs", {})
	var lv_in: Dictionary = labs_in.get("lvls", {})
	var labs: Dictionary = d["labs"]
	var lv: Dictionary = labs["lvls"]
	for id in LabDB.IDS:
		lv[id] = clampi(int(lv_in.get(id, 0)), 0, LabDB.max_of(String(id)))
	labs["slots"] = clampi(int(labs_in.get("slots", Labs.MIN_SLOTS)), Labs.MIN_SLOTS, Labs.MAX_SLOTS)
	var run: Array = []
	for r in labs_in.get("running", []):
		var e2: Dictionary = r
		var tid: String = String(e2.get("track", ""))
		if not LabDB.DEFS.has(tid) or run.size() >= int(labs["slots"]):
			continue
		var dup: bool = false
		for q in run:
			if String((q as Dictionary)["track"]) == tid:
				dup = true
		if dup or int(lv[tid]) >= LabDB.max_of(tid):
			continue
		run.append({"track": tid, "to_lvl": int(lv[tid]) + 1, "start": int(e2.get("start", 0)), "end": int(e2.get("end", 0))})
	labs["running"] = run
	# cards
	var cards_in: Dictionary = s.get("cards", {})
	var cards: Dictionary = d["cards"]
	cards["slots"] = clampi(int(cards_in.get("slots", Cards.MIN_SLOTS)), Cards.MIN_SLOTS, Cards.MAX_SLOTS)
	var own_in: Dictionary = cards_in.get("owned", {})
	var own: Dictionary = {}
	for cid in CardDB.IDS:
		if own_in.has(cid):
			var oe: Dictionary = own_in[cid]
			var cl: int = clampi(int(oe.get("lvl", 1)), 1, CardDB.MAX_LVL)
			own[cid] = {"lvl": cl, "copies": 0 if cl >= CardDB.MAX_LVL else maxi(0, int(oe.get("copies", 0)))}
	cards["owned"] = own
	var eq: Array = []
	for v in cards_in.get("equipped", []):
		var ce: String = String(v)
		if own.has(ce) and not eq.has(ce) and eq.size() < int(cards["slots"]):
			eq.append(ce)
	cards["equipped"] = eq
	# missions + streak
	var m_in: Dictionary = s.get("missions", {})
	var m: Dictionary = d["missions"]
	m["day"] = int(m_in.get("day", -1))
	m["bonus_claimed"] = bool(m_in.get("bonus_claimed", false))
	var ml: Array = []
	for x in m_in.get("list", []):
		var me: Dictionary = x
		var tpl: String = String(me.get("tpl", ""))
		if MissionDB.DEFS.has(tpl) and ml.size() < Missions.PER_DAY:
			var tg: int = maxi(1, int(me.get("target", 1)))
			ml.append({"tpl": tpl, "target": tg, "prog": clampi(int(me.get("prog", 0)), 0, tg), "claimed": bool(me.get("claimed", false)), "gems": int(me.get("gems", MissionDB.reward(tpl)))})
	m["list"] = ml
	var st_in: Dictionary = s.get("streak", {})
	d["streak"] = {"day_idx": clampi(int(st_in.get("day_idx", 0)), 0, 7), "last_day": int(st_in.get("last_day", -1)), "loops": maxi(0, int(st_in.get("loops", 0)))}
	d["stats"] = _int_dict(s.get("stats", {}), ["kills", "bosses"])
	d["gem_log"] = _int_dict(s.get("gem_log", {}), GEM_SOURCES)
	var bg_in: Dictionary = s.get("boss_gems_today", {})
	d["boss_gems_today"] = {"day": int(bg_in.get("day", -1)), "n": maxi(0, int(bg_in.get("n", 0)))}
	# speed snaps to an unlocked step
	var steps: Array = Labs.speed_steps(d)
	var sp: float = float(s.get("speed", 1.0))
	var snap: float = 1.0
	for v in steps:
		if float(v) <= sp + 0.001:
			snap = float(v)
	d["speed"] = snap
	return d


## Late coin sink (fix round): every tier above 1 lifts the core stat cap by
## core_cap_step levels, so banked coins keep converting into HP / damage /
## regen after the base grid is saturated.
static func core_cap(s: Dictionary) -> int:
	return mini(CORE_HARD_MAX, MAX_LVL + TuneRef.int_of("core_cap_step", 5) * (Tiers.highest(s) - 1))


static func perm_lvl_cap(s: Dictionary) -> int:
	return TuneRef.int_of("perm_lvl_cap", 10) + 5 * (Tiers.highest(s) - 1)


## The single hand-off to TowerState (SPEC A8).
static func run_mods(s: Dictionary) -> Dictionary:
	var hi: int = Tiers.highest(s)
	var t: int = clampi(int(s.get("tier", 1)), 1, hi)
	var lm: Dictionary = Labs.modifiers(s)
	var steps: Array = Labs.speed_steps(s)
	var sp: float = float(s.get("speed", 1.0))
	if not steps.has(sp):
		sp = 1.0
	return {
		"tier": t, "hp_mult": Tiers.hp_mult(t), "coin_mult": Tiers.coin_mult(t),
		"boss_every": Tiers.boss_every(t),
		"lab_dmg": float(lm["dmg"]), "lab_hp": float(lm["hp"]),
		"lab_coin": float(lm["coin"]), "lab_xp": float(lm["xp"]),
		"start_cash": int(lm["start_cash"]), "rerolls": int(lm["rerolls"]),
		"cards": Cards.mods(s), "speed": sp,
		"allow_new_bldg": int(s.get("runs", 0)) >= 2,
	}


static func is_inner(i: int) -> bool:
	var dx: int = absi(i % 5 - 2)
	var dy: int = absi(i / 5 - 2)
	return dx <= 1 and dy <= 1 and i != CORE_SLOT


static func is_unlocked(s: Dictionary, i: int) -> bool:
	if i == CORE_SLOT:
		return false
	if is_inner(i):
		return true
	var un: Array = s["unlocked"]
	return un.has(i)


static func slot_of(s: Dictionary, i: int) -> Dictionary:
	var slots: Dictionary = s["slots"]
	return slots.get(str(i), {})


static func unlock_cost(s: Dictionary) -> int:
	var un: Array = s["unlocked"]
	return int(TuneRef.num("perm_unlock_base", 90.0) * pow(1.45, un.size()))


static func place_cost(id: String) -> int:
	var d: Dictionary = BuildingDB.get_def(id)
	return int(d.get("coin", 15))


static func upgrade_cost(lvl: int) -> int:
	return int(TuneRef.num("perm_upgrade_base", 45.0) * pow(1.55, lvl))


static func core_cost(lvl: int) -> int:
	return int(TuneRef.num("perm_core_base", 30.0) * pow(1.5, lvl))


static func try_unlock(s: Dictionary, i: int) -> bool:
	if i < 0 or i > 24 or is_unlocked(s, i) or i == CORE_SLOT:
		return false
	var c: int = unlock_cost(s)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	(s["unlocked"] as Array).append(i)
	return true


static func try_place(s: Dictionary, i: int, id: String) -> bool:
	if not is_unlocked(s, i) or not slot_of(s, i).is_empty() or not BuildingDB.DEFS.has(id):
		return false
	var c: int = place_cost(id)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	(s["slots"] as Dictionary)[str(i)] = {"id": id, "lvl": 1}
	return true


static func try_upgrade(s: Dictionary, i: int) -> bool:
	var e: Dictionary = slot_of(s, i)
	if e.is_empty():
		return false
	var lvl: int = int(e["lvl"])
	if lvl >= perm_lvl_cap(s):
		return false
	var c: int = upgrade_cost(lvl)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	e["lvl"] = lvl + 1
	Missions.progress(s, "upgrade", 1)
	return true


static func demolish(s: Dictionary, i: int) -> bool:
	var slots: Dictionary = s["slots"]
	return slots.erase(str(i))


static func try_core(s: Dictionary, stat: String) -> bool:
	var core: Dictionary = s["core"]
	if not core.has(stat):
		return false
	var lvl: int = int(core[stat])
	if lvl >= core_cap(s):
		return false
	var c: int = core_cost(lvl)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	core[stat] = lvl + 1
	Missions.progress(s, "upgrade", 1)
	return true


## AC-10a: boss gems are capped per calendar day (boss_gem_daily) on top of
## the 3-awards-per-run cap, so the T3 doubling cannot dominate gem income.
static func boss_gem_allowance(s: Dictionary, now: int) -> int:
	var cap: int = TuneRef.int_of("boss_gem_daily", 10)
	var bg: Dictionary = s.get("boss_gems_today", {})
	if int(bg.get("day", -1)) != Missions.day_of(now):
		return cap
	return maxi(0, cap - int(bg.get("n", 0)))


## Bank a finished run: coins + gems, per-tier record, best coin rate,
## last_seen, and first-time tier unlock rewards. Returns events.
static func bank(s: Dictionary, coins: int, wave: int, tier: int = 1, run_minutes: float = 0.0, now: int = 0, gems: int = 0) -> Array:
	var ev: Array = []
	var hi_before: int = Tiers.highest(s)
	s["coins"] = int(s["coins"]) + maxi(0, coins)
	s["runs"] = int(s["runs"]) + 1
	s["best_wave"] = maxi(int(s["best_wave"]), wave)
	if not s.has("best_wave_by_tier"):
		s["best_wave_by_tier"] = {"1": 0}
	var bw: Dictionary = s["best_wave_by_tier"]
	var tk: String = str(maxi(1, tier))
	bw[tk] = maxi(int(bw.get(tk, 0)), wave)
	if tier >= hi_before and run_minutes > 0.0:
		s["best_coin_rate"] = maxf(float(s.get("best_coin_rate", 0.0)), float(coins) / run_minutes)
	if now > 0:
		s["last_seen"] = now
	if gems > 0:
		Missions.add_gems(s, "boss", gems)
		var day: int = Missions.day_of(now)
		var bg: Dictionary = s.get("boss_gems_today", {})
		var used: int = int(bg.get("n", 0)) if int(bg.get("day", -1)) == day else 0
		s["boss_gems_today"] = {"day": day, "n": used + gems}
	if not s.has("tiers_rewarded"):
		s["tiers_rewarded"] = []
	var tr: Array = s["tiers_rewarded"]
	var hi: int = Tiers.highest(s)
	for n in range(2, hi + 1):
		if not tr.has(n):
			tr.append(n)
			var g: int = TuneRef.int_of("tier_gems", 10)
			Missions.add_gems(s, "tier", g)
			ev.append({"t": "tier_unlocked", "tier": n, "gems": g})
	return ev


## Tier selector (Base screen): only unlocked tiers may be chosen.
static func select_tier(s: Dictionary, n: int) -> bool:
	if not Tiers.is_unlocked(s, n):
		return false
	s["tier"] = n
	return true


## Speed pill: persists the chosen game speed if it is an unlocked step.
static func set_speed(s: Dictionary, v: float) -> bool:
	if not Labs.speed_steps(s).has(v):
		return false
	s["speed"] = v
	return true
