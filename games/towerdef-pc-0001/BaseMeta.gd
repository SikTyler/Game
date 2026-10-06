extends RefCounted
## Permanent meta layer (save v5, Corehold V2). Pure static functions over the
## save Dictionary — the view writes it to disk via MetaSave (3 slots).
## V2 is a HARD RESET (owner decision): any save older than v5 normalizes to
## fresh v5 defaults with reset_v2 = true (the view shows a one-time banner).
## Shape:
##   {version: 5, coins, scrap, shards, runs, best_wave, tier,
##    best_wave_by_tier: {"N": w}, tiers_rewarded: [N], best_coin_rate, speed,
##    core: {lvl, look}  (Cores.gd), gear: {items, equipped, pity, ...} (Gear.gd),
##    research: {lvls, running} (Labs.gd), outpost (Outpost.gd),
##    reforge (Reforge.gd), insight: {id: n} (PickDB),
##    missions, streak, last_seen, stats, history, settings, endless,
##    achievements}

const LabDB := preload("res://data/LabDB.gd")
const MissionDB := preload("res://data/MissionDB.gd")
const Tiers := preload("res://Tiers.gd")
const Labs := preload("res://Labs.gd")
const Missions := preload("res://Missions.gd")
const TuneRef := preload("res://Tune.gd")
const Stats := preload("res://Stats.gd")
const Cores := preload("res://Cores.gd")
const PickDB := preload("res://data/PickDB.gd")
const Outpost := preload("res://Outpost.gd")
const Reforge := preload("res://Reforge.gd")
const Gear := preload("res://Gear.gd")
const Loot := preload("res://Loot.gd")

const VERSION: int = 5


static func default_save() -> Dictionary:
	return {
		"version": VERSION, "coins": 0, "scrap": 0, "shards": 0,
		"runs": 0, "best_wave": 0, "tier": 1, "best_wave_by_tier": {"1": 0},
		"tiers_rewarded": [], "best_coin_rate": 0.0, "speed": 1.0,
		"core": Cores.default_block(),
		"gear": Gear.default_block(),
		"research": Labs.default_block(),
		"missions": {"day": -1, "list": [], "bonus_claimed": false},
		"streak": {"day_idx": 0, "last_day": -1, "loops": 0},
		"last_seen": 0, "stats": Stats.default_stats(), "history": [],
		"settings": {"music": 0.8, "sfx": 1.0, "mute": false},
		"endless": {"best": 0},
		"achievements": {"unlocked": {}, "missions_claimed": 0},
		"insight": {},
		"outpost": Outpost.default_block(),
		"reforge": Reforge.default_block(),
	}


## True for a save written before V2 (anything with data but version < 5).
static func is_pre_v2(raw: Dictionary) -> bool:
	return not raw.is_empty() and int(raw.get("version", 1)) < VERSION


## Coerce JSON floats to ints, fill missing keys, clamp levels, drop unknowns.
## Pre-V2 saves are not migrated: they become fresh defaults (+ reset_v2).
static func normalize(s_in: Dictionary) -> Dictionary:
	var d: Dictionary = default_save()
	if is_pre_v2(s_in):
		d["reset_v2"] = true
		var se_old: Variant = s_in.get("settings", {})
		if se_old is Dictionary:
			d["settings"] = _settings(se_old)   # audio settings survive the reset
		return d
	var s: Dictionary = s_in
	if bool(s.get("reset_v2", false)):
		d["reset_v2"] = true
	d["coins"] = maxi(0, int(s.get("coins", 0)))
	d["scrap"] = maxi(0, int(s.get("scrap", 0)))
	d["shards"] = maxi(0, int(s.get("shards", 0)))
	d["runs"] = maxi(0, int(s.get("runs", 0)))
	# tiers
	var bw_in: Dictionary = s.get("best_wave_by_tier", {}) if s.get("best_wave_by_tier", {}) is Dictionary else {}
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
	d["outpost"] = Outpost.normalize_block(s.get("outpost", null))
	d["reforge"] = Reforge.normalize_block(s.get("reforge", null))
	d["core"] = Cores.normalize_block(s.get("core", null), Cores.max_level(d))
	d["gear"] = Gear.normalize_block(s.get("gear", null), Cores.level(d))
	# research
	var labs_in: Dictionary = s.get("research", {}) if s.get("research", {}) is Dictionary else {}
	var lv_in: Dictionary = labs_in.get("lvls", {}) if labs_in.get("lvls", {}) is Dictionary else {}
	var lv: Dictionary = (d["research"] as Dictionary)["lvls"]
	for id in LabDB.IDS:
		lv[id] = clampi(int(lv_in.get(id, 0)), 0, LabDB.max_of(String(id)))
	# missions + streak
	var m_in: Dictionary = s.get("missions", {}) if s.get("missions", {}) is Dictionary else {}
	var m: Dictionary = d["missions"]
	m["day"] = int(m_in.get("day", -1))
	m["bonus_claimed"] = bool(m_in.get("bonus_claimed", false))
	var ml: Array = []
	for x in m_in.get("list", []):
		if not (x is Dictionary):
			continue
		var me: Dictionary = x
		var tpl: String = String(me.get("tpl", ""))
		if MissionDB.DEFS.has(tpl) and ml.size() < Missions.PER_DAY:
			var tg: int = maxi(1, int(me.get("target", 1)))
			ml.append({"tpl": tpl, "target": tg, "prog": clampi(int(me.get("prog", 0)), 0, tg), "claimed": bool(me.get("claimed", false)), "coins": MissionDB.reward(tpl)})
	m["list"] = ml
	var st_in: Dictionary = s.get("streak", {}) if s.get("streak", {}) is Dictionary else {}
	d["streak"] = {"day_idx": clampi(int(st_in.get("day_idx", 0)), 0, 7), "last_day": int(st_in.get("last_day", -1)), "loops": maxi(0, int(st_in.get("loops", 0)))}
	d["stats"] = Stats.normalize_stats(s.get("stats", {}))
	d["history"] = Stats.normalize_history(s.get("history", []))
	var en_in: Dictionary = s.get("endless", {}) if s.get("endless", {}) is Dictionary else {}
	d["endless"] = {"best": maxi(0, int(en_in.get("best", 0)))}
	d["achievements"] = _achievements(s.get("achievements", {}))
	d["insight"] = PickDB.normalize_insight(s.get("insight", {}))
	d["settings"] = _settings(s.get("settings", {}))
	# speed snaps to an unlocked step
	var steps: Array = Labs.speed_steps(d)
	var sp: float = float(s.get("speed", 1.0))
	var snap: float = 1.0
	for v in steps:
		if float(v) <= sp + 0.001:
			snap = float(v)
	d["speed"] = snap
	return d


static func _settings(src: Variant) -> Dictionary:
	var se: Dictionary = src if src is Dictionary else {}
	return {"music": clampf(float(se.get("music", 0.8)), 0.0, 1.0), "sfx": clampf(float(se.get("sfx", 1.0)), 0.0, 1.0), "mute": bool(se.get("mute", false))}


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
		"insight_cap": int(om.get("insight_cap", 0)), "banish": int(om.get("banish", 0)) + int(lm["banish"]),
		"outpost_fx": (om.get("outpost_fx", {}) as Dictionary).duplicate(),
		"tier": t, "hp_mult": Tiers.hp_mult(t), "coin_mult": Tiers.coin_mult(t),
		"boss_every": Tiers.boss_every(t),
		"lab_dmg": float(lm["dmg"]), "lab_hp": float(lm["hp"]),
		"lab_coin": float(lm["coin"]), "lab_xp": float(lm["xp"]),
		"start_cash": int(lm["start_cash"]) + int(rm["rf_start_cash"]), "rerolls": int(lm["rerolls"]),
		"speed": sp, "grid_lvl": Labs.level(s, "grid"),
		"allow_new_bldg": int(s.get("runs", 0)) >= 2,
		# V2 P8 research: run fx (pf), enemy cuts, levels (TrackDB unlocks)
		"lab_fx": Labs.run_fx(s), "lab_enemy": Labs.enemy(s), "res": Labs.levels(s),
		"lab_aim": float(lm["aim"]), "lab_bounty": float(lm["bounty"]), "lab_items": float(lm["items"]),
		"lab_locks": int(lm["locks"]), "lab_choices": int(lm["choices"]),
	}


## Bank a finished run: coins, per-tier record, best coin rate,
## last_seen, and first-time tier unlock rewards. Returns events.
static func bank(s: Dictionary, coins: int, wave: int, tier: int = 1, run_minutes: float = 0.0, now: int = 0, record: bool = true) -> Array:
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
	if not s.has("tiers_rewarded"):
		s["tiers_rewarded"] = []
	var tr: Array = s["tiers_rewarded"]
	var hi: int = Tiers.highest(s)
	for n in range(2, hi + 1):
		if not tr.has(n):
			tr.append(n)
			var g: int = TuneRef.int_of("tier_coins", 500)
			s["coins"] = int(s["coins"]) + g
			ev.append({"t": "tier_unlocked", "tier": n, "coins": g})
	return ev


## Bank a run's loot: Scrap into the wallet (P5: items and caches too).
static func bank_loot(s: Dictionary, loot: Dictionary, _rng: RandomNumberGenerator = null) -> Array:
	# V2 P5: tokens -> items on the meta RNG (Loot.realize) + all Scrap
	return Loot.realize(s, loot, scrap_mult(s))


## Scrap multiplier on banked loot (Reforge Scrapper +10%/L).
static func scrap_mult(s: Dictionary) -> float:
	return 1.0 + 0.1 * float(Reforge.node(s, "scrap_p"))


## PC_SPEC §3.1: endless unlocks once any run reached wave 50.
static func endless_unlocked(s: Dictionary) -> bool:
	return int(s.get("best_wave", 0)) >= TuneRef.int_of("pc_endless_unlock", 50)


static func record_endless(s: Dictionary, wave: int) -> void:
	if not (s.get("endless", null) is Dictionary):
		s["endless"] = {"best": 0}
	var e: Dictionary = s["endless"]
	e["best"] = maxi(int(e.get("best", 0)), wave)


## Tier selector (hub): only unlocked tiers may be chosen.
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
