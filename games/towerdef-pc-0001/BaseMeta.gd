extends RefCounted
## Permanent base (the meta layer, The Tower's "workshop" as buildings).
## Pure static functions over the save Dictionary — the view writes it to disk
## via MetaSave (3 slots). Save v3 (PC_SPEC §4) = the v2 shape below on the
## 7x7 board (cell keys 0..48, core 24) plus stats{} / history[] (Stats.gd),
## endless{best}. v2 -> v3 maps 5x5 (r,c) to 7x7 (r+1,c+1). v2 shape
## (SPEC A1 / SYSTEMS §12):
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
const Stats := preload("res://Stats.gd")
const Cores := preload("res://Cores.gd")
const PickDB := preload("res://data/PickDB.gd")
const Parts := preload("res://Parts.gd")
const Crates := preload("res://Crates.gd")
const Outpost := preload("res://Outpost.gd")
const Reforge := preload("res://Reforge.gd")

const VERSION: int = 3
## PC 7x7 base (PC_SPEC §2.1): rings by Chebyshev distance from the core cell
## (3,3). Ring 1 (8 cells) starts unlocked; ring 2 / ring 3 are bought per cell.
const SIDE: int = 7
const N: int = 49
const CORE_SLOT: int = 24
const CORE_STATS: Array = ["dmg", "hp", "regen"]
const MAX_LVL: int = 15
## Hard ceiling for migrated core levels; the live cap is core_cap(s).
const CORE_HARD_MAX: int = 60
const GEM_SOURCES: Array = ["boss", "mission", "streak", "tier", "mine"]


static func default_save() -> Dictionary:
	return {
		"version": VERSION, "coins": 0, "gems": 0,
		"core": {"dmg": 0, "hp": 0, "regen": 0}, "slots": {}, "unlocked": [],
		"runs": 0, "best_wave": 0, "tier": 1, "best_wave_by_tier": {"1": 0},
		"tiers_rewarded": [], "best_coin_rate": 0.0, "speed": 1.0,
		"research": Labs.default_block(),
		"cards": {"owned": {}, "equipped": [], "slots": Cards.MIN_SLOTS},
		"missions": {"day": -1, "list": [], "bonus_claimed": false},
		"streak": {"day_idx": 0, "last_day": -1, "loops": 0},
		"last_seen": 0, "stats": Stats.default_stats(), "history": [],
		"gem_log": {"boss": 0, "mission": 0, "streak": 0, "tier": 0},
		"boss_gems_today": {"day": -1, "n": 0},
		"settings": {"music": 0.8, "sfx": 1.0, "mute": false},
		"endless": {"best": 0},
		"achievements": {"unlocked": {}, "missions_claimed": 0},
		# Redesign ENGINE-RUN blocks (additive; save v4 folds them in).
		"cores": Cores.default_block(), "core_cores": 0, "insight": {},
		"scrap": 0, "keys": 0, "part_drops": [],
		"parts": Parts.default_block(), "crates": Crates.default_block(),
		"outpost": Outpost.default_block(),
		"reforge": Reforge.default_block(), "shards": 0,
	}


## Mobile 5x5 index -> PC 7x7 index: (r, c) -> (r+1, c+1). The 5x5 inner ring
## lands on 7x7 ring 1 and the 5x5 outer ring on ring 2.
static func idx5_to_7(i: int) -> int:
	return (i / 5 + 1) * SIDE + (i % 5 + 1)


## v1 (no `version`) -> v2 -> v3. Lossless; returns a new Dictionary.
static func migrate(s: Dictionary) -> Dictionary:
	var d: Dictionary = s.duplicate(true)
	var v: int = int(d.get("version", 1))
	if v >= VERSION:
		return d
	if v < 2:
		d = _migrate_v1(d)
	return _migrate_v2(d)


## v2 -> v3: remap every 5x5 cell key onto the 7x7 board; new v3 blocks are
## filled with defaults by normalize().
static func _migrate_v2(d: Dictionary) -> Dictionary:
	var slots_in: Dictionary = d.get("slots", {})
	var slots: Dictionary = {}
	for key in slots_in.keys():
		var i5: int = int(key)
		if i5 >= 0 and i5 < 25:
			slots[str(idx5_to_7(i5))] = slots_in[key]
	d["slots"] = slots
	var un: Array = []
	for v in d.get("unlocked", []):
		var i5b: int = int(v)
		if i5b >= 0 and i5b < 25:
			un.append(idx5_to_7(i5b))
	d["unlocked"] = un
	if d.get("target_modes", null) is Dictionary:
		var tm_in: Dictionary = d["target_modes"]
		var tm: Dictionary = {}
		for key in tm_in.keys():
			var i5c: int = int(key)
			if i5c >= 0 and i5c < 25:
				tm[str(idx5_to_7(i5c))] = tm_in[key]
		d["target_modes"] = tm
	d["version"] = VERSION
	return d


static func _migrate_v1(d: Dictionary) -> Dictionary:
	var bw: int = int(d.get("best_wave", 0))
	d["best_wave_by_tier"] = {"1": bw}
	d["gems"] = 0
	d["tier"] = 1
	d["last_seen"] = 0
	var labs: Dictionary = d.get("labs", {})
	var lv: Dictionary = labs.get("lvls", {})
	lv.erase("armor")
	d["version"] = 2
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
		if BuildingDB.DEFS.has(id) and idx >= 0 and idx < N and idx != CORE_SLOT and place_ok(idx, id):
			slots[str(idx)] = {"id": id, "lvl": clampi(int(e.get("lvl", 1)), 1, cap)}
	d["slots"] = slots
	var un: Array = []
	for v in s.get("unlocked", []):
		var n2: int = int(v)
		if n2 >= 0 and n2 < N and cell_ring(n2) >= 2 and not un.has(n2):
			un.append(n2)
	d["unlocked"] = un
	# research (Research Hall projects; v3 "labs" is read when present)
	d["outpost"] = Outpost.normalize_block(s.get("outpost", null))
	var labs_in: Dictionary = {}
	if s.get("research", null) is Dictionary:
		labs_in = s["research"]
	elif s.get("labs", null) is Dictionary:
		labs_in = s["labs"]
	var lv_in: Dictionary = labs_in.get("lvls", {}) if labs_in.get("lvls", {}) is Dictionary else {}
	var labs: Dictionary = d["research"]
	var lv: Dictionary = labs["lvls"]
	for id in LabDB.IDS:
		lv[id] = clampi(int(lv_in.get(id, 0)), 0, LabDB.max_of(String(id)))
	var qn: int = Outpost.research_queues(d)
	var run: Array = []
	for r in labs_in.get("running", []):
		var e2: Dictionary = r
		var tid: String = String(e2.get("track", ""))
		if not LabDB.DEFS.has(tid) or run.size() >= qn:
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
	d["stats"] = Stats.normalize_stats(s.get("stats", {}))
	d["history"] = Stats.normalize_history(s.get("history", []))
	d["gem_log"] = _int_dict(s.get("gem_log", {}), GEM_SOURCES)
	var bg_in: Dictionary = s.get("boss_gems_today", {})
	d["boss_gems_today"] = {"day": int(bg_in.get("day", -1)), "n": maxi(0, int(bg_in.get("n", 0)))}
	var se_in: Dictionary = s.get("settings", {})
	var en_in: Dictionary = s.get("endless", {}) if s.get("endless", {}) is Dictionary else {}
	d["endless"] = {"best": maxi(0, int(en_in.get("best", 0)))}
	d["achievements"] = _achievements(s.get("achievements", {}))
	d["cores"] = Cores.normalize_block(s.get("cores", null), Cores.max_level(s))
	d["parts"] = Parts.normalize_block(s.get("parts", null))
	Parts.sanitize_presets(d)
	d["crates"] = Crates.normalize_block(s.get("crates", null))
	d["core_cores"] = maxi(0, int(s.get("core_cores", 0)))
	d["insight"] = PickDB.normalize_insight(s.get("insight", {}))
	d["scrap"] = maxi(0, int(s.get("scrap", 0)))
	d["keys"] = maxi(0, int(s.get("keys", 0)))
	var pd: Array = []
	for x in s.get("part_drops", []):
		if x is Dictionary and pd.size() < 200:
			pd.append({"rarity": String((x as Dictionary).get("rarity", "common")), "source": String((x as Dictionary).get("source", "kill"))})
	d["part_drops"] = pd
	d["reforge"] = Reforge.normalize_block(s.get("reforge", null))
	d["shards"] = maxi(0, int(s.get("shards", 0)))
	d["settings"] = {"music": clampf(float(se_in.get("music", 0.8)), 0.0, 1.0), "sfx": clampf(float(se_in.get("sfx", 1.0)), 0.0, 1.0), "mute": bool(se_in.get("mute", false))}
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
	return TuneRef.int_of("perm_lvl_cap", 10) + 5 * (Tiers.highest(s) - 1) + land_bonus(s)


## PC land development: every pc_land_cells outer cells bought (ring 2/3) lift
## every building's permanent level cap by 1 (max pc_land_max). The build cap
## keeps the board scarce, so this is what makes the 48-cell base a real late
## coin sink instead of dead land.
static func land_bonus(s: Dictionary) -> int:
	var un: Array = s.get("unlocked", [])
	return mini(TuneRef.int_of("pc_land_max", 10), un.size() / maxi(1, TuneRef.int_of("pc_land_cells", 4)))


## The single hand-off to TowerState (SPEC A8).
static func run_mods(s: Dictionary) -> Dictionary:
	var hi: int = Tiers.highest(s)
	var t: int = clampi(int(s.get("tier", 1)), 1, hi)
	var lm: Dictionary = Labs.modifiers(s)
	var steps: Array = Labs.speed_steps(s)
	var sp: float = float(s.get("speed", 1.0))
	if not steps.has(sp):
		sp = 1.0
	var om: Dictionary = Outpost.run_mods(s) if s.get("outpost", null) is Dictionary else {}
	var rm: Dictionary = Reforge.run_mods(s)
	return {
		"rf_dmg": float(rm["rf_dmg"]), "rf_hp": float(rm["rf_hp"]), "rf_coin": float(rm["rf_coin"]),
		"barracks_tier": int(om.get("barracks_tier", 0)), "barracks_bonus": float(om.get("barracks_bonus", 0.0)),
		"insight_cap": int(om.get("insight_cap", 0)), "banish": int(om.get("banish", 0)),
		"tier": t, "hp_mult": Tiers.hp_mult(t), "coin_mult": Tiers.coin_mult(t),
		"boss_every": Tiers.boss_every(t),
		"lab_dmg": float(lm["dmg"]), "lab_hp": float(lm["hp"]),
		"lab_coin": float(lm["coin"]), "lab_xp": float(lm["xp"]),
		"start_cash": int(lm["start_cash"]) + int(rm["rf_start_cash"]), "rerolls": int(lm["rerolls"]),
		"cards": Cards.mods(s), "speed": sp,
		"allow_new_bldg": int(s.get("runs", 0)) >= 2,
	}


## Chebyshev ring of (r, c) around the core cell (3,3): 0 core, 1..3 rings.
static func cell_ring_rc(r: int, c: int) -> int:
	return maxi(absi(r - SIDE / 2), absi(c - SIDE / 2))


static func cell_ring(i: int) -> int:
	return cell_ring_rc(i / SIDE, i % SIDE)


static func is_corner(i: int) -> bool:
	var rg: int = cell_ring(i)
	return rg > 0 and absi(i / SIDE - SIDE / 2) == rg and absi(i % SIDE - SIDE / 2) == rg


static func is_inner(i: int) -> bool:
	return i >= 0 and i < N and cell_ring(i) == 1


## Railgun is outer-ring only (ring >= 2); every other building fits anywhere.
static func place_ok(i: int, id: String) -> bool:
	if id == "railgun":
		return cell_ring(i) >= 2
	return true


## PC_SPEC §2.1 run build cap: 12 + 2*(highest_tier-1), capped at 40.
static func build_cap(s: Dictionary) -> int:
	var c: int = TuneRef.int_of("pc_build_cap_base", 12) + TuneRef.int_of("pc_build_cap_step", 2) * (Tiers.highest(s) - 1)
	return mini(TuneRef.int_of("pc_build_cap_max", 40), c)


static func building_count(s: Dictionary) -> int:
	return (s["slots"] as Dictionary).size()


## Ring 3 cells need best tier >= 3.
static func ring_open(s: Dictionary, i: int) -> bool:
	var rg: int = cell_ring(i)
	if rg <= 2:
		return true
	return Tiers.highest(s) >= TuneRef.int_of("pc_ring3_tier", 3)


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


## Per-cell permanent unlock price (PC_SPEC §2.1): ring 2 = 400*1.18^n, ring 3
## = 2500*1.22^n (n = cells of that ring already unlocked), corners +50%.
static func unlock_cost(s: Dictionary, i: int) -> int:
	var rg: int = cell_ring(i)
	if rg < 2:
		return 0
	var n: int = 0
	for v in s["unlocked"]:
		if cell_ring(int(v)) == rg:
			n += 1
	var c: float = 0.0
	if rg == 2:
		c = TuneRef.num("pc_cell_cost_r2", 400.0) * pow(TuneRef.num("pc_cell_growth_r2", 1.18), float(n))
	else:
		c = TuneRef.num("pc_cell_cost_r3", 2500.0) * pow(TuneRef.num("pc_cell_growth_r3", 1.22), float(n))
	if is_corner(i):
		c *= TuneRef.num("pc_corner_mult", 1.5)
	return int(c)


static func place_cost(id: String) -> int:
	var d: Dictionary = BuildingDB.get_def(id)
	return int(d.get("coin", 15))


static func upgrade_cost(lvl: int) -> int:
	return int(TuneRef.num("perm_upgrade_base", 45.0) * pow(1.55, lvl))


static func core_cost(lvl: int) -> int:
	return int(TuneRef.num("perm_core_base", 30.0) * pow(1.5, lvl))


static func try_unlock(s: Dictionary, i: int) -> bool:
	if i < 0 or i >= N or is_unlocked(s, i) or i == CORE_SLOT or not ring_open(s, i):
		return false
	var c: int = unlock_cost(s, i)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	Stats.on_event(s, {"t": "coins_spent", "n": c})
	(s["unlocked"] as Array).append(i)
	return true


static func try_place(s: Dictionary, i: int, id: String) -> bool:
	if not is_unlocked(s, i) or not slot_of(s, i).is_empty() or not BuildingDB.DEFS.has(id) or not place_ok(i, id):
		return false
	if building_count(s) >= build_cap(s):
		return false
	var c: int = place_cost(id)
	if int(s["coins"]) < c:
		return false
	s["coins"] = int(s["coins"]) - c
	Stats.on_event(s, {"t": "coins_spent", "n": c})
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
	Stats.on_event(s, {"t": "coins_spent", "n": c})
	e["lvl"] = lvl + 1
	Missions.progress(s, "upgrade", 1)
	return true


## Base-screen rearrange (free): move a permanent building to an empty
## unlocked cell, or swap two buildings. Respects the Railgun ring rule.
static func try_move(s: Dictionary, a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= N or b >= N or a == CORE_SLOT or b == CORE_SLOT:
		return false
	var ea: Dictionary = slot_of(s, a)
	var eb: Dictionary = slot_of(s, b)
	if ea.is_empty() or not is_unlocked(s, b) or not place_ok(b, String(ea["id"])):
		return false
	if not eb.is_empty() and not place_ok(a, String(eb["id"])):
		return false
	var slots: Dictionary = s["slots"]
	slots.erase(str(a))
	slots.erase(str(b))
	slots[str(b)] = ea
	if not eb.is_empty():
		slots[str(a)] = eb
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
	Stats.on_event(s, {"t": "coins_spent", "n": c})
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
static func bank(s: Dictionary, coins: int, wave: int, tier: int = 1, run_minutes: float = 0.0, now: int = 0, gems: int = 0, record: bool = true) -> Array:
	var ev: Array = []
	var hi_before: int = Tiers.highest(s)
	s["coins"] = int(s["coins"]) + maxi(0, coins)
	Reforge.on_coins(s, coins)
	s["runs"] = int(s["runs"]) + 1
	if not s.has("best_wave_by_tier"):
		s["best_wave_by_tier"] = {"1": 0}
	if record:
		s["best_wave"] = maxi(int(s["best_wave"]), wave)
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
			# Redesign: every tier clear also pays Core Cores (Core level gates).
			var ccs: int = TuneRef.int_of("pc_tier_corecores", 2)
			s["core_cores"] = int(s.get("core_cores", 0)) + ccs
			ev.append({"t": "tier_unlocked", "tier": n, "gems": g, "core_cores": ccs})
	return ev


## Bank a run's loot (REDESIGN §2.6): Scrap and Keys into the wallet; part
## drops wait in save.part_drops for the Parts module to resolve into parts.
static func bank_loot(s: Dictionary, loot: Dictionary, rng: RandomNumberGenerator = null) -> Array:
	var ev: Array = []
	var sc: int = int(round(float(maxi(0, int(loot.get("scrap", 0)))) * Parts.scrap_mult(s)))
	var ky: int = maxi(0, int(loot.get("keys", 0)))
	var cc: int = maxi(0, int(loot.get("core_cores", 0)))
	s["scrap"] = int(s.get("scrap", 0)) + sc
	s["keys"] = int(s.get("keys", 0)) + ky
	s["core_cores"] = int(s.get("core_cores", 0)) + cc
	if not (s.get("part_drops", null) is Array):
		s["part_drops"] = []
	var pd: Array = s["part_drops"]
	for p in loot.get("parts", []):
		pd.append((p as Dictionary).duplicate())
	if sc > 0 or ky > 0 or cc > 0 or not (loot.get("parts", []) as Array).is_empty():
		ev.append({"t": "loot_banked", "scrap": sc, "keys": ky, "core_cores": cc, "parts": (loot.get("parts", []) as Array).size()})
	# ENGINE-META: generic part drops resolve into concrete parts (seeded).
	if rng != null:
		ev.append_array(Parts.resolve_drops(s, rng))
	ev.append_array(Cores.check_unlocks(s, {"set2": Parts.any_set2(s)}))
	return ev


## PC_SPEC §3.1: endless unlocks once any run reached wave 50.
static func endless_unlocked(s: Dictionary) -> bool:
	return int(s.get("best_wave", 0)) >= TuneRef.int_of("pc_endless_unlock", 50)


static func record_endless(s: Dictionary, wave: int) -> void:
	if not (s.get("endless", null) is Dictionary):
		s["endless"] = {"best": 0}
	var e: Dictionary = s["endless"]
	e["best"] = maxi(int(e.get("best", 0)), wave)


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


## save["achievements"] (PC_SPEC §4 v3): {unlocked:{id: unix_ts}, missions_claimed}.
## Achievements.gd owns the rules; this only keeps the shape valid.
static func _achievements(src: Variant) -> Dictionary:
	var d: Dictionary = src if src is Dictionary else {}
	var un: Dictionary = {}
	var u_in: Variant = d.get("unlocked", {})
	if u_in is Dictionary:
		var u: Dictionary = u_in
		for k in u.keys():
			un[String(k)] = maxi(0, int(u[k]))
	return {"unlocked": un, "missions_claimed": maxi(0, int(d.get("missions_claimed", 0)))}
