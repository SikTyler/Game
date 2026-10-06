extends SceneTree
# V2 BALANCE / PLAYABILITY audit for Corehold (V2 P9). Drives the real loop
# (TowerState is the whole game; Main.gd is a view) at a fixed dt with a
# deterministic competent bot, in runs (drafts, merges, placement facing away
# from the Core, specials, Core Enhancements) and between runs (MetaBot: the
# Outpost build plan, research by weighted priority, Core levels, gear: merge
# / equip / upgrade / forge / salvage). Jobs fan out over worker processes:
#   main       a DAYS-day campaign (4 runs a day on the SESSION_H clock) with
#              day rows; writes the day-3 / day-8 snapshots for phase B
#   fresh      FRESH_N brand-new first runs (first-run length, early wall)
#   mass       the MASS_HORDE H1-H10 engine gates
#   gear       day 8: the save's gear vs a Common Autocannon loadout
#   corebld    day 8: with vs without the Outpost's Core buildings
#   xp         day 3: XP-focus vs balanced levels by wave 12 (Core held up)
#   dir        day 8: radial-only vs directional-only weapon drafts
#   weapons_*  day 8: each weapon as the only weapon vs the balanced mix
#   perks      day 8: each gold-perk family preferred vs balanced
# Gates: GATES + MASS_GATES (V2_PROGRESS §P9 documents each threshold).
# Prints per-run / per-day lines, "PLAYTEST METRICS {json}" and exactly
# "PLAYTEST OK" (exit 0) or "PLAYTEST FAIL: <gate>" lines (exit 1).
# Debug: `-- only=<job>` runs one job in-process (verbose, no gates);
# `-- serial` runs every job in-process. Clears user:// saves at start / end.

const TowerState := preload("res://TowerState.gd")
const TrackDB := preload("res://data/TrackDB.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const TuneRef := preload("res://Tune.gd")
const PerkDB := preload("res://data/PerkDB.gd")
const PickDB := preload("res://data/PickDB.gd")
const Specials := preload("res://Specials.gd")
const Cores := preload("res://Cores.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const PowerModel := preload("res://PowerModel.gd")
const WeaponDB := preload("res://data/WeaponDB.gd")
const Gear := preload("res://Gear.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const Labs := preload("res://Labs.gd")
const Missions := preload("res://Missions.gd")
const Outpost := preload("res://Outpost.gd")
const Tiers := preload("res://Tiers.gd")
const LabDB := preload("res://data/LabDB.gd")

const DT: float = 0.1
const MAX_SIM_S: float = 3600.0
## MASS_HORDE harness fidelity (MASS_HORDE §Content): a wave planned above this
## many bodies spawns one body per k = ceil(B / cap) carrying k x HP / damage /
## pool share / kill count. Every first-session wave stays under it.
const BOT_LOD_CAP: int = 1200
const SEED_DEFAULT: int = 4242
## V2 P9 day-1 goal: the campaign's best wave on day 1 (4 runs).
const FIRST_GOAL_WAVE: int = 10
const DAYS: int = 10
const SESSION_H: Array = [8, 8, 16, 16]        # 2 sessions x 2 runs; 8 h / 16 h offline gaps
const NOW0: int = 1767225600                   # 2026-01-01 00:00 UTC (a day boundary)
const SNAP_DAYS: Array = [3, 8]
const AB_SEEDS: Array = [101, 202, 303]

var fail_count: int = 0
const GATES: Array = ["solvent", "first_goal_day1", "first_run_short", "fresh_median_first_goal", "progressable", "no_death_spiral",
	"t2_by_day3_6", "speed2_by_day4_8", "gear_matters", "corebld_matters", "xp_drafts", "dir_parity",
	"no_dominant_weapon", "no_dominant_perk", "pity_holds"]


static var QUIET: bool = false      # child jobs buffer their log instead of printing
static var DAYS_RUN: int = DAYS     # `-- only=main days=N` (debug) shortens the campaign
static var LOGBUF: Array = []


## Every report line goes through here: printed in the parent, buffered in a
## child job (the parent prints each job's buffer in a fixed order).
static func say(line: String) -> void:
	LOGBUF.append(line)
	if not QUIET:
		print(line)


func _initialize() -> void:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var p: PackedStringArray = String(a).split("=", true, 1)
		args[p[0]] = p[1] if p.size() > 1 else "1"
	var seed0: int = TuneRef.seed_of(SEED_DEFAULT)
	if args.has("job"):
		# Child worker: run one job, write {log, r} to dir/<job>.bin, exit.
		QUIET = true
		var dir: String = String(args.get("dir", ""))
		var r: Dictionary = run_job(String(args["job"]), seed0, dir)
		var f := FileAccess.open(dir.path_join(_job_file(String(args["job"]))), FileAccess.WRITE)
		f.store_buffer(var_to_bytes({"log": LOGBUF, "r": r}))
		f.close()
		quit(0)
		return
	if args.has("days"):
		DAYS_RUN = int(args["days"])
	if args.has("only"):
		var o: Dictionary = run_job(String(args["only"]), seed0, OS.get_user_data_dir())
		print("ONLY " + JSON.stringify(o))
		quit(0)
		return
	MetaSave.clear()
	var t0: int = Time.get_ticks_msec()
	var R: Dictionary = run_jobs(seed0, args.has("serial"), int(args.get("workers", "4")))
	var m: Dictionary = combine(R)
	m["runtime_s"] = snappedf(float(Time.get_ticks_msec() - t0) / 1000.0, 0.1)
	print("PLAYTEST METRICS " + JSON.stringify(m))
	for key in GATES + MASS_GATES:
		if not bool(m.get(key, false)):
			fail_count += 1
			print("PLAYTEST FAIL: " + key)
	for jf in R.get("_failed", []):
		fail_count += 1
		print("PLAYTEST FAIL: job " + String(jf) + " crashed")
	MetaSave.clear()
	if fail_count == 0:
		print("PLAYTEST OK")
		quit(0)
	else:
		quit(1)


# ------------------------------------------------------------- job runner
# Each job owns its saves and RNG seeds, so the audit fans out over CPU cores:
# the parent re-launches this script headless once per job (`-- job=<name>
# dir=<tmp>`), at most `workers` at a time, and merges the results. Phase-B
# jobs replay the day-3 / day-8 snapshots the "main" job writes (var_to_bytes:
# exact). `-- serial` runs every job in-process (same results; debugging).
const JOBS_A: Array = ["main", "fresh", "mass"]
const JOBS_B: Array = ["gear", "corebld", "xp", "dir", "weapons_a", "weapons_b", "perks"]


static func _job_file(job: String) -> String:
	return "job_%s.bin" % job.replace(":", "_")


static func _snap_path(dir: String, d: int) -> String:
	return dir.path_join("snap%d.bin" % d)


static func _snap(dir: String, d: int) -> Dictionary:
	var path: String = _snap_path(dir, d)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var v: Variant = bytes_to_var(f.get_buffer(f.get_length()))
	f.close()
	return v if v is Dictionary else {}


static func run_job(job: String, seed0: int, dir: String) -> Dictionary:
	match job:
		"main":
			var M: Dictionary = campaign(seed0, DAYS_RUN)
			for d in (M["snaps"] as Dictionary).keys():
				var f := FileAccess.open(_snap_path(dir, int(d)), FileAccess.WRITE)
				f.store_buffer(var_to_bytes(M["snaps"][d]))
				f.close()
			M.erase("snaps")
			M.erase("save")
			return M
		"fresh":
			return job_fresh(seed0)
		"mass":
			return job_mass(seed0)
		"gear":
			return job_gear(seed0, _snap(dir, 8))
		"corebld":
			return job_corebld(seed0, _snap(dir, 8))
		"xp":
			return job_xp(seed0, _snap(dir, 3))
		"dir":
			return job_dir(seed0, _snap(dir, 8))
		"weapons_a":
			return job_weapons(seed0, _snap(dir, 8), _weapon_ids().slice(0, _weapon_ids().size() / 2))
		"weapons_b":
			return job_weapons(seed0, _snap(dir, 8), _weapon_ids().slice(_weapon_ids().size() / 2))
		"perks":
			return job_perks(seed0, _snap(dir, 8))
	return {}


func run_jobs(seed0: int, serial: bool, workers: int) -> Dictionary:
	var dir: String = OS.get_user_data_dir().path_join("pt_jobs")
	DirAccess.make_dir_recursive_absolute(dir)
	var R: Dictionary = {}
	var failed: Array = []
	var order: Array = ["main"] + JOBS_B + JOBS_A.slice(1)
	if serial:
		for job in order:
			LOGBUF = []
			R[job] = run_job(String(job), seed0, dir)
	else:
		var exe: String = OS.get_executable_path()
		var proj: String = ProjectSettings.globalize_path("res://")
		var pending: Array = order.duplicate()
		var running: Dictionary = {}     # job -> pid
		var done: Dictionary = {}
		while pending.size() > 0 or running.size() > 0:
			for job in running.keys():
				if not OS.is_process_running(int(running[job])):
					running.erase(job)
					done[job] = true
					var path: String = dir.path_join(_job_file(String(job)))
					if FileAccess.file_exists(path):
						var f := FileAccess.open(path, FileAccess.READ)
						var res: Variant = bytes_to_var(f.get_buffer(f.get_length()))
						f.close()
						DirAccess.remove_absolute(path)
						var rd: Dictionary = res
						for line in rd["log"]:
							print(String(line))
						R[job] = rd["r"]
					else:
						failed.append(job)
						R[job] = {}
			var k: int = 0
			while k < pending.size() and running.size() < maxi(1, workers):
				var job: String = String(pending[k])
				if JOBS_B.has(job) and not done.has("main"):
					k += 1
					continue
				pending.remove_at(k)
				var pid: int = OS.create_process(exe, ["--headless", "--path", proj, "--script", "res://playtest.gd", "--", "job=" + job, "dir=" + dir])
				if pid <= 0:
					failed.append(job)
					R[job] = {}
					done[job] = true
				else:
					running[job] = pid
			OS.delay_msec(100)
	for d in SNAP_DAYS:
		DirAccess.remove_absolute(_snap_path(dir, int(d)))
	R["_failed"] = failed
	return R



#   H9 fluid sanity (selftest MASS-HORDE world) H10 same seed -> same waves
#   H11 perf logged (not gated)                 H12 = no_death_spiral (kept)
# ======================================================================
const MASS_GATES: Array = ["h1_wave_bodies", "h2_peak_10k_held", "h3_no_split", "h4_designed_hp", "h5_pool_cash", "h6_drops", "h7_first_goal_day1", "h8_weapons_matter", "h10_mass_determinism"]
const EnemyDB := preload("res://data/EnemyDB.gd")
const H8_WEAPONS: Array = ["gun", "mortar", "tesla", "flak", "railgun", "frost"]


static func _mass_S(seed_value: int, save: Dictionary = {}):
	var S = TowerState.new()
	S.setup(seed_value, save if not save.is_empty() else BaseMeta.default_save())
	return S


static func job_mass(seed0: int) -> Dictionary:
	var out: Dictionary = {}
	# ---- H1: the body-count curve, and what wave 1 actually spawns
	var S1 = _mass_S(seed0)
	var w1_spawned: int = 0
	var guard: int = 0
	while S1.wave == 1 and guard < 1000:
		guard += 1
		S1.tick(DT)
	w1_spawned = S1.mass_spawned
	out["h1"] = {"w1_planned": S1.mass_bodies(1), "w1_spawned": w1_spawned, "w25": S1.mass_bodies(25), "w45": S1.mass_bodies(45), "w50": S1.mass_bodies(50),
		"t3_w1": 0, "t3_w30": 0}
	var S3 = _mass_S(seed0)
	S3.tier = 3
	(out["h1"] as Dictionary)["t3_w1"] = S3.mass_bodies(1)
	(out["h1"] as Dictionary)["t3_w30"] = S3.mass_bodies(30)
	out["h1_ok"] = w1_spawned >= 100 and S1.mass_bodies(25) >= 1000 and S1.mass_bodies(45) >= 10000
	# ---- H2 / H3 / H4 / H11: a forced T1 wave 50 (19,800 bodies) with no
	# defence: the alive count climbs to the 16,384 cap, the queue holds, no
	# planned body is dropped, every body is a designed one.
	var S2 = _mass_S(seed0 + 1)
	S2.max_hp_mult = 1.0e9
	S2.recompute()
	S2.hp = float(S2.stats["max_hp"])
	S2.plan = []
	S2.plan_idx = 0
	S2.wave = 50
	S2.wave_t = 0.0
	var peak: int = 0
	var ms_peak: float = 0.0
	var t0: int = Time.get_ticks_usec()
	var ticks: int = 0
	for i in int(24.0 / DT):
		S2.stats["weapons"] = []
		var u0: int = Time.get_ticks_usec()
		S2.tick(DT)
		var u1: int = Time.get_ticks_usec()
		ticks += 1
		if S2.en.count() >= peak:
			peak = S2.en.count()
			ms_peak = float(u1 - u0) / 1000.0 / maxf(1.0, DT / TowerState.SUBSTEP)
	var planned: int = (S2.plan as Array).size()
	var a50: Dictionary = S2.wave_acct.get(50, {})
	var queued: int = planned - S2.plan_idx
	var spawned50: int = int(a50.get("spawned", 0))
	var share_ok: bool = true   # V2 P3d: no legacy split knob; every body is a whole designed unit
	var hp_ok: bool = S2.en.count() > 0
	var n_chk: int = 0
	for sl in S2.en.order:
		if S2.en.share[sl] != 1.0:
			share_ok = false
		var k: String = S2.en.kind[sl]
		if n_chk < 2000 and not S2.en.is_marked(sl) and not ["boss", "elite", "courier"].has(k):
			n_chk += 1
			var want: float = float(EnemyDB.mass_def(k)["hp"]) * S2.mass_hp_scale(k, 50)
			if absf(S2.en.max_hp[sl] - want) > 1e-6 * want:
				hp_ok = false
	out["h2"] = {"planned": planned, "spawned": spawned50, "queued": queued, "peak_alive": peak, "cap": TowerState.MASS_CAP,
		"ms_per_substep_at_peak": snappedf(ms_peak, 0.01), "wall_s": snappedf(float(Time.get_ticks_usec() - t0) / 1.0e6, 0.1)}
	out["h2_ok"] = peak >= 10000 and peak <= TowerState.MASS_CAP and spawned50 + queued == planned and queued > 0
	out["h3_ok"] = share_ok
	out["h4_ok"] = hp_ok and n_chk > 100
	say("MASS H2 forced wave 50: " + JSON.stringify(out["h2"]))
	# ---- H5: full-clear waves pay pool x 1.3 (kill shares + clear bonus)
	var h5: Dictionary = {}
	var h5_ok: bool = true
	for w in [1, 9, 25]:   # non-boss waves (a boss is spawned by the wave advance, not the forced plan)
		var SE = _mass_S(seed0 + 2)
		SE.max_hp_mult = 1.0e9
		SE.recompute()
		SE.hp = float(SE.stats["max_hp"])
		SE.stats["weapons"] = []
		if w > 1:
			SE.plan = []
			SE.plan_idx = 0
			SE.wave = w
			SE.wave_t = 0.0
			SE.recompute()
			SE.stats["weapons"] = []
		var kc: float = 0.0
		var cc: float = -1.0
		guard = 0
		while cc < 0.0 and guard < 2000:
			guard += 1
			SE.combo = 0.0   # V2 P7c: the kill-streak combo is a bonus on top of the pool
			SE.combo_tier = 0
			for e in SE.tick(TowerState.SUBSTEP):
				var ed: Dictionary = e
				if String(ed["t"]) == "kills":
					kc += float(ed["cash"])
				elif String(ed["t"]) == "wave_clear" and int(ed["wave"]) == w:
					cc = float(ed["cash"])
			SE.stats["weapons"] = []
			for sl in SE.en.order:
				if SE.en.hp[sl] > 0.0 and int(SE.en.wv[sl]) == w:
					SE.en.hp[sl] = 0.0
					SE.en.kill(sl)
		var want5: float = SE.mass_cash_pool(w) * 1.3 * PowerModel.cash_index(w, 1) * SE.run_cash_mult() * float(SE.stats["kill_cash"])
		var got5: float = kc + maxf(0.0, cc)
		h5[str(w)] = {"want": snappedf(want5, 0.1), "got": snappedf(got5, 0.1), "bodies": SE.mass_bodies(w)}
		h5_ok = h5_ok and cc >= 0.0 and absf(got5 - want5) <= 0.05 * want5
	out["h5"] = h5
	out["h5_ok"] = h5_ok and float((h5["25"] as Dictionary)["want"]) / float((h5["1"] as Dictionary)["want"]) < float(S1.mass_bodies(25)) / float(S1.mass_bodies(1)) * PowerModel.cash_index(25, 1)
	# ---- H6 + H10: a fresh balanced bot run (x3, same seed): drops per wave
	# within the cap and >= 1 per 2 waves; per-wave kills / leaks / cash
	# bit-identical across the three runs.
	var fps: Array = []
	var drops_w: Dictionary = {}
	var waves_run: int = 0
	for rep in 3:
		var SR = _mass_S(seed0 + 3)
		var fp: Array = []
		var acc: float = 0.0
		var lw: int = 1
		var dw: Dictionary = {}
		guard = 0
		while not SR.over and SR.wave <= 14 and guard < 100000:
			guard += 1
			var ev: Array = SR.tick(DT)
			acc += DT
			for e in ev:
				var ed2: Dictionary = e
				if String(ed2["t"]) == "loot_drop":
					var dwv: int = int(ed2.get("wave", SR.wave))
					dw[dwv] = int(dw.get(dwv, 0)) + 1
			if SR.wave != lw:
				fp.append([lw, SR.kills, SR.mass_leaked, snappedf(SR.cash_earned, 0.000001)])
				lw = SR.wave
			if acc >= 0.5:
				acc = 0.0
				bot_step(SR, "balanced")
		fps.append(fp)
		drops_w = dw
		waves_run = lw
	var cap6: int = TuneRef.int_of("mass_drop_cap", 6)
	var dmax: int = 0
	var dtot: int = 0
	for k in drops_w.keys():
		dmax = maxi(dmax, int(drops_w[k]))
		dtot += int(drops_w[k])
	out["h6"] = {"drops_by_wave": drops_w, "max_per_wave": dmax, "cap": cap6, "total": dtot, "waves": waves_run}
	out["h6_ok"] = dmax <= cap6 + 0 and dtot * 2 >= waves_run - 1
	out["h10"] = {"waves": (fps[0] as Array).size(), "fp_last": (fps[0] as Array).back() if not (fps[0] as Array).is_empty() else []}
	out["h10_ok"] = not (fps[0] as Array).is_empty() and fps[0] == fps[1] and fps[1] == fps[2]
	# ---- H8: each weapon alone vs a dense mite field at wave 10
	var h8: Dictionary = {}
	for lv in [1, 5]:
		var row: Dictionary = {}
		for wk in H8_WEAPONS:
			row[wk] = snappedf(_weapon_kps(String(wk), lv, seed0), 0.01)
		h8["lv%d" % lv] = row
	var b1: float = 0.0
	var b5: float = 0.0
	for wk in H8_WEAPONS:
		b1 = maxf(b1, float((h8["lv1"] as Dictionary)[wk]))
		b5 = maxf(b5, float((h8["lv5"] as Dictionary)[wk]))
	# H8 (§D4, re-aimed and documented in MASS_HORDE §Content): the Cryo Spire
	# is the force multiplier (D4: "5-20 kills/s directly"), so instead of a
	# kill share it must lift a Gun's kills by >= 10% (Brittle / shatter);
	# the Railgun's Lv5 exemption needs its elite/boss single-target DPS to lead.
	var ok8: bool = b1 > 0.0
	for wk in H8_WEAPONS:
		if String(wk) == "frost":
			continue
		ok8 = ok8 and float((h8["lv1"] as Dictionary)[wk]) >= 0.25 * b1
		if String(wk) != "railgun":
			ok8 = ok8 and float((h8["lv5"] as Dictionary)[wk]) >= 0.15 * b5
	var gf: float = _weapon_kps("gun+frost", 1, seed0)
	h8["gun_plus_frost_lv1"] = snappedf(gf, 0.01)
	ok8 = ok8 and gf >= 1.10 * float((h8["lv1"] as Dictionary)["gun"])
	var bd: Dictionary = _boss_dps_lv5(seed0)
	h8["boss_dps_lv5"] = bd
	var rail_lead: bool = true
	for wk in bd.keys():
		if String(wk) != "railgun" and float(bd[wk]) >= float(bd["railgun"]):
			rail_lead = false
	ok8 = ok8 and (rail_lead or float((h8["lv5"] as Dictionary)["railgun"]) >= 0.15 * b5)
	out["h8"] = h8
	out["h8_ok"] = ok8
	say("MASS H1 %s | H5 %s | H6 %s | H8 %s | H10 %s" % [JSON.stringify(out["h1"]), JSON.stringify(h5), JSON.stringify(out["h6"]), JSON.stringify(h8), JSON.stringify(out["h10"])])
	return out


## Kills per second of one weapon (alone, level `lv`, wave 10) against a
## dense, replenished swarmling field (hex-packed 10 px apart, 150 px out).
static func _weapon_kps(kinds_s: String, lv: int, seed0: int) -> float:
	var S = _mass_S(seed0 + 9)
	S.spawn_hold = true
	var kinds: PackedStringArray = kinds_s.split("+")
	var si: int = _north_anchor(kinds[0])
	S.slots[si] = {"id": kinds[0], "tier": mini(lv, 3)}
	S.unlocked[si] = true
	if kinds.size() > 1:
		var s2: int = si - TowerState.size_of(kinds[1])   # V2 P3b: just west of the first footprint
		S.slots[s2] = {"id": kinds[1], "tier": mini(lv, 3)}
		S.unlocked[s2] = true
	S.wave = 10
	S.recompute()
	var keep: Array = []
	for w in S.stats["weapons"]:
		if kinds.has(String((w as Dictionary)["kind"])):
			keep.append(w)
	S.stats["weapons"] = keep
	var from: Vector2 = S.fp_pos(si)
	# the field sits beyond the Mortar's minimum range and inside every range
	var c: Vector2 = from + Vector2(0, -180)
	var pts: Array = []
	var row: int = 0
	var y: float = -90.0
	while y <= 90.0:
		var x: float = -90.0 + (5.0 if row % 2 == 1 else 0.0)
		while x <= 90.0:
			if Vector2(x, y).length() <= 90.0:
				pts.append(c + Vector2(x, y))
			x += 10.0
		y += 8.66
		row += 1
	var hp: float = float(EnemyDB.mass_def("mite")["hp"]) * S.mass_hp_scale("mite", 10)
	var eids: Array = []
	for p in pts:
		var d: Dictionary = {"kind": "mite", "pos": p, "hp": hp, "max_hp": hp, "spd": 0.0, "size": 10.0}
		S.add_enemy(d)
		eids.append(int(d["eid"]))
	var k0: int = S.kills
	var T: float = 10.0
	for i in int(T / TowerState.SUBSTEP):
		S.tick(TowerState.SUBSTEP)
		S.stats["weapons"] = keep
		for j in eids.size():
			if S.en.slot_of(int(eids[j])) < 0:
				var d2: Dictionary = {"kind": "mite", "pos": pts[j], "hp": hp, "max_hp": hp, "spd": 0.0, "size": 10.0}
				S.add_enemy(d2)
				eids[j] = int(d2["eid"])
	return float(S.kills - k0) / T


## V2 P3b: anchor of a footprint just north of the 3x3 Core (ring 1; the
## Railgun's ring 3+), centred on the Core's column.
static func _north_anchor(id: String) -> int:
	var sz: int = TowerState.size_of(id)
	var dr: int = (-5 if id == "railgun" else -2) - (sz - 1)
	return TowerState.cell(dr, -(sz - 1) / 2 if sz > 1 else 0)


## Single-target DPS vs a boss of each weapon at Lv5 (the Railgun's x4 on the
## first elite / boss it hits; Gun rounds 2; Tesla's first arc only).
static func _boss_dps_lv5(seed0: int) -> Dictionary:
	var S = _mass_S(seed0 + 11)
	var out: Dictionary = {}
	for wk in ["gun", "mortar", "tesla", "flak", "railgun"]:
		var si: int = _north_anchor(wk)
		for i in TowerState.N:
			if i != TowerState.CORE_SLOT:
				S.slots[i] = {}
		S.slots[si] = {"id": wk, "tier": 3}
		S.unlocked[si] = true
		S.recompute()
		for w in S.stats["weapons"]:
			var wd: Dictionary = w
			if String(wd["kind"]) != wk:
				continue
			var d: float = float(wd["dmg"]) * float(wd["rate"])
			match wk:
				"railgun":
					d *= TuneRef.num("mass_rail_boss", 4.0)
				"gun":
					d *= float(TuneRef.int_of("mass_gun_rounds", 2))
				"flak":
					d *= TuneRef.num("mass_flame_hit", 0.15) + TuneRef.num("mass_flame_burn", 0.3) * TuneRef.num("mass_burn_s", 2.0)
			out[wk] = snappedf(d, 0.01)
	return out


## AC-25 + the strong death-spiral partner: FRESH_N first runs of the
## balanced bot, each on its own brand-new save and seed (no meta, no draft
## memory). Reports death waves and the boss-aware R probes of camp_run.
const FRESH_N: int = 16
## A fresh first run (no meta) must reach this wave (every one of FRESH_N).
const FRESH_GOAL_WAVE: int = 5
static func job_fresh(seed0: int) -> Dictionary:
	var waves: Array = []
	var times: Array = []
	var re: Array = []
	var rwl: Array = []
	var rf: Array = []
	for i in FRESH_N:
		var save: Dictionary = BaseMeta.default_save()
		var r: Dictionary = camp_run(save, "balanced", seed0 + 50000 + i * 7919, NOW0, "", false)
		waves.append(int(r["wave"]))
		times.append(float(r["real_s"]))
		re.append(float(r["r_early"]))
		rwl.append(float(r["r_wall"]))
		rf.append(float(r["r_front"]))
	say("FRESH balanced x%d: waves %s | R early %s | R wall %s" % [FRESH_N, str(waves), str(re.map(func(x: float) -> float: return snappedf(x, 0.01))), str(rwl.map(func(x: float) -> float: return snappedf(x, 0.01)))])
	return {"waves": waves, "times": times, "r_early": re, "r_wall": rwl, "r_front": rf}



# ======================================================================
# IN-RUN BOT
# ======================================================================
static func _weapon_ids() -> Array:
	return WeaponDB.DEFS.keys()


static func _is_weapon(id: String) -> bool:
	return WeaponDB.has(id)


## Draft score for one card under an in-run policy:
##   balanced     weapons first (up to 3 + wave / 5), supports once two
##                weapons stand, two eco picks in waves 6-17, damage packs,
##                then specials / huts; evolutions and Insight always
##   xp           balanced + XP cards first (XP Siphon, XP packs)
##   radial / directional   balanced, but only weapons of that aim class
##   only:<id>    balanced, but <id> is the only weapon it drafts
static func _card_score(S, policy: String, c: Dictionary) -> float:
	var id: String = String(c["id"])
	var fam: String = String(c["fam"])
	var kind: String = String(c["kind"])
	var tags: Array = c["tags"]
	var rar: int = maxi(0, ["common", "rare", "epic", "legendary"].find(String(c["rarity"])))
	if kind == "insight":
		return 1000.0
	if kind == "evo":
		return 900.0
	var weapon: bool = fam == "building" and _is_weapon(id)
	var eco: bool = tags.has("eco")
	if weapon and policy.begins_with("only:") and id != policy.substr(5):
		return -50.0
	if weapon and (policy == "radial" or policy == "directional") and WeaponDB.directional(id) != (policy == "directional"):
		return -50.0
	var nw: int = _weapon_count(S)
	var sc: float = 1.0 + 1.5 * float(rar)
	if weapon:
		sc += 11.0 if nw < 3 + S.wave / 5 else 8.0
		# a horde is a crowd: area damage first; a pure-control weapon (Cryo
		# Spire, Sonic Cannon) only once two damage weapons stand
		if tags.has("aoe"):
			sc += 2.0
		if not tags.has("dps") and not tags.has("aoe") and nw < 2:
			sc -= 8.0
	elif eco:
		sc += 10.0 if (nw >= 2 and S.wave >= 6 and S.wave < 18 and _counts(S).y < 2) else -2.0
	elif fam == "building":
		sc += 7.5 if nw >= 2 else 3.0   # supports buff the weapons around them
	elif fam == "pack":
		sc += 8.5 if tags.has("dps") else 4.0
	elif fam == "special":
		sc += 3.0
	elif fam == "hut":
		sc += 2.5
	if policy == "xp" and _xp_card(id):
		sc += 14.0
	if bool(c.get("merge", false)):
		sc += 2.0   # V2 P7a: a duplicate merges into a T2
	return sc


static func _xp_card(id: String) -> bool:
	if id == "xpsiphon":
		return true
	return float((PickDB.get_def(id).get("fx", {}) as Dictionary).get("xp", 0.0)) > 0.0


## V2 P7a bot merging: take mod 0 of an open offer, then fold any building
## into its same-tier twin (lowest anchor first, deterministic).
static func merge_step(S) -> Array:
	var ev: Array = []
	var guard: int = 0
	while guard < 12:
		guard += 1
		if not S.merge_offer.is_empty():
			ev.append_array(S.choose_mod(0))
			continue
		var done: bool = false
		for a in TowerState.N:
			var tg: Array = S.merge_targets(a)
			if not tg.is_empty():
				ev.append_array(S.merge(a, int(tg[0])))
				done = true
				break
		if not done:
			break
	return ev


static func _weapon_count(S) -> int:
	var n: int = 0
	for i in TowerState.N:
		if _is_weapon(S.id_at(i)) and S.owner_at(i) == i:
			n += 1
	return n


static func _counts(S) -> Vector2i:
	var w: int = 0
	var e: int = 0
	for i in TowerState.N:
		var id: String = S.id_at(i)
		if id == "" or S.owner_at(i) != i:
			continue
		if PickDB.is_eco(id):
			e += 1
		elif _is_weapon(id):
			w += 1
	return Vector2i(w, e)


## Gold perk pick: pure perks over trade-offs; offense / defense / tempo
## first; `fam:<f>` prefers family f; `xp` prefers XP perks.
static func _perk_score(policy: String, id: String) -> int:
	var d: Dictionary = PerkDB.get_def(id)
	var fam: String = String(d.get("fam", ""))
	var sc: int = 0 if bool(d.get("tradeoff", false)) else 2
	if policy.begins_with("fam:"):
		return sc + (8 if fam == policy.substr(4) else 0)
	if policy == "xp" and float((d.get("fx", {}) as Dictionary).get("xp", 0.0)) > 0.0:
		sc += 8
	return sc + (3 if ["offense", "defense", "tempo"].has(fam) else 1)


## Track priority weights: the cheapest weighted price wins. Standard tracks
## by tree (defense when hurt, economy early); Overdrives at a premium.
static func _track_weight(S, policy: String, t: String) -> float:
	var hp_frac: float = S.hp / maxf(1.0, float(S.stats["max_hp"]))
	if TrackDB.is_od(t):
		var od: Dictionary = {"dmg": 1.6, "rate": 1.8, "range": 3.0, "eco": 2.5 if S.wave < 25 else 6.0, "armor": 1.6 if hp_frac < 0.5 else 2.6}
		return float(od.get(t, 3.0))
	var tree: String = String(TrackDB.get_def(t).get("tree", "attack"))
	var w: float = {"attack": 1.0, "defense": 0.9 if hp_frac < 0.5 else 1.4, "economy": 0.8 if S.wave < 20 else 2.0}.get(tree, 1.0)
	if policy == "xp" and t == "e_xp":
		w *= 0.25
	# boss prep: the last waves before a boss wave go to attack
	var be: int = int(S.boss_every)
	if tree == "economy" and be - S.wave % be <= 2:
		w *= 3.0
	return w


## Specials: cast when it pays (targeted ones auto-aim at the densest pile).
static func _use_specials(S) -> Array:
	var ev: Array = []
	var live: int = 0
	var near: int = 0
	var boss: bool = false
	var core_r: float = float((S.stats["weapons"] as Array).back()["range"])
	var en = S.en
	for es in en.order:
		if en.hp[es] <= 0.0:
			continue
		live += 1
		if TowerState.CENTER.distance_to(en.pos[es]) <= core_r:
			near += 1
		if en.kind[es] == "boss":
			boss = true
	var hp_frac: float = S.hp / maxf(1.0, float(S.stats["max_hp"]))
	for k in S.specials.size():
		if not Specials.ready(S.specials, k):
			continue
		var id: String = String((S.specials[k] as Dictionary)["id"])
		var go: bool = false
		match id:
			"sp_orbital", "sp_nuke", "sp_meteor":
				go = live >= 8 or boss
			"sp_emp", "sp_blackhole":
				go = live >= 12 or (boss and near > 0)
			"sp_repair":
				go = hp_frac < 0.55
			"sp_shield":
				go = hp_frac < 0.35 and near >= 3
			"sp_overdrive", "sp_frenzy":
				go = near >= 3 or boss
			"sp_magnet":
				go = live >= 12
			"sp_timewarp":
				go = hp_frac < 0.4 and near >= 3
			"sp_jackpot":
				go = true
		if go:
			var r: Dictionary = S.cast_special(k, -1)
			ev.append_array(r["ev"])
	return ev


## Competent in-run policy; also used as a library by _shots.
static func bot_step(S, policy: String, perk_pref: String = "") -> Array:
	var ev: Array = []
	if S.mutation_offer.size() > 0:
		ev.append_array(S.choose_mutation(_pick_mutation(S)))
	if S.directive_offer.size() > 0:
		ev.append_array(S.choose_directive(0))
	if S.perk_offer.size() > 0:
		var bp: int = 0
		var bs: int = -99
		for k in S.perk_offer.size():
			var ps: int = _perk_score(policy, String(S.perk_offer[k]))
			if perk_pref != "" and String(S.perk_offer[k]) == perk_pref:
				ps = 100
			elif perk_pref == "tradeoff" and PerkDB.is_tradeoff(String(S.perk_offer[k])):
				ps += 10
			if ps > bs:
				bs = ps
				bp = k
		ev.append_array(S.choose_perk(bp))
	if S.draft.size() > 0:
		var best: int = 0
		var best_score: float = -99.0
		for k in S.draft.size():
			var sc: float = _card_score(S, policy, S.draft[k])
			if sc > best_score:
				best_score = sc
				best = k
		# A free reroll is taken when the hand has nothing the policy wants.
		if best_score < 5.0 and S.reroll_cost() == 0:
			ev.append_array(S.reroll_draft())
		else:
			ev.append_array(S.choose_card(best))
	if S.pending_place != "":
		# V2 P7a: a duplicate merges into its T1 twin when it has one
		var tw: Array = S.card_merge_targets(S.pending_place)
		if not tw.is_empty():
			ev.append_array(S.merge_card(int(tw[0])))
		else:
			var cell: int = _place_cell(S, S.pending_place)
			if cell >= 0:
				ev.append_array(S.place(cell))
			else:
				ev.append_array(S.cancel_place())   # nowhere legal: skip the card
	ev.append_array(merge_step(S))
	ev.append_array(_use_specials(S))
	# A competent player focuses fire on a boss once it is inside Core range.
	var core_r: float = float((S.stats["weapons"] as Array).back()["range"])
	var boss_in: bool = false
	var en = S.en
	for es in en.order:
		if en.kind[es] == "boss" and TowerState.CENTER.distance_to(en.pos[es]) <= core_r:
			boss_in = true
			break
	var want: String = "strongest" if boss_in else "nearest"
	for w in S.stats["weapons"]:
		var si: int = int((w as Dictionary)["slot"])
		if String(S.target_modes[si]) != want:
			ev.append_array(S.set_target_mode(si, want))
	# Spend cash on the Core Enhancement with the cheapest weighted price.
	var guard: int = 0
	while guard < 12:
		guard += 1
		var bt: String = ""
		var bc: float = INF
		for t in TowerState.TRACK_IDS:
			var c: int = S.track_cost(String(t))
			if c < 0 or not S.track_unlocked(String(t)):
				continue
			var wc: float = float(c) * _track_weight(S, policy, String(t))
			if wc < bc:
				bc = wc
				bt = String(t)
		if bt == "" or S.cash < float(S.track_cost(bt)):
			break
		ev.append_array(S.buy_track(bt))
	return ev


## Endless mutations: the least dangerous buff first.
static func _pick_mutation(S) -> int:
	var order: Array = ["m_plating", "m_rush", "m_fangs", "m_vigor", "m_horde"]
	var best: int = 0
	var best_r: int = 99
	for k in S.mutation_offer.size():
		var r: int = order.find(String(S.mutation_offer[k]))
		if r >= 0 and r < best_r:
			best_r = r
			best = k
	return best


## Placement: weapons and auras as close to the Core as allowed (they face
## away from it by default), eco / huts on the outer cells. A directional
## weapon takes the cell of its ring whose default facing is furthest from
## the facings already covered (the lowest free index used to stack every
## arc / lane on the north row and leave the other bearings open).
static func _place_cell(S, id: String) -> int:
	var best: int = -1
	var best_k: float = INF
	var inner: bool = _is_weapon(id) or (PickDB.fam_of(id) == "building" and not PickDB.is_eco(id))
	var faces: Array = []
	if _is_weapon(id) and WeaponDB.directional(id):
		for a in TowerState.N:
			if a != TowerState.CORE_SLOT and S.owner_at(a) == a and WeaponDB.directional(S.id_at(a)):
				faces.append(WeaponDB.facing(S.rot_at(a)))
	for i in S.free_slots():
		if not S.can_place(int(i), id):
			continue
		var r: int = TowerState.ring_of(int(i))
		var k: float = float(r) if inner else float(20 - r)
		if not faces.is_empty():
			var f: Vector2 = WeaponDB.facing(S.default_rot(int(i), id))
			var ov: float = -1.0
			for fc in faces:
				ov = maxf(ov, f.dot(fc as Vector2))
			k += 0.45 * (ov + 1.0)   # 0 (opposite) .. 0.9 (same bearing): stays within the ring
		k += float(int(i)) * 0.001
		if k < best_k:
			best_k = k
			best = int(i)
	return best


# ======================================================================
# META BOT (between runs)
# ======================================================================
## The Outpost plan a competent player follows (start area first, then plot
## 0): [kind, id, x, y, rot]. Each session the bot takes the first affordable
## action (one job per builder) within pc_bot_op_frac of its coins.
const OP_PLAN: Array = [
	# V2 P6 (48x32 small cells; Relay 3x3 at (4,8), Research Hall above it)
	["place", "mill", 7, 8, 0], ["place", "mill", 7, 10, 0], ["place", "warehouse", 9, 8, 0],
	["up", "mill"], ["up", "relay"], ["up", "research"],
	["place", "arsenal", 9, 10, 0], ["place", "treasury", 7, 12, 0], ["place", "reactor", 9, 12, 0],
	["place", "conduit", 3, 9, 0], ["place", "refinery", 1, 9, 0], ["place", "conduit", 1, 11, 0], ["place", "conduit", 1, 12, 0], ["place", "gemmine", 1, 13, 0],
	["place", "bulwark_w", 7, 5, 0], ["place", "scav_post", 9, 5, 0],
	["plot", 0], ["place", "conduit", 11, 8, 0], ["place", "mill", 12, 8, 0], ["place", "archive", 12, 6, 0], ["place", "barracks", 12, 10, 0],
	["place", "optics", 14, 8, 0], ["place", "rangefinder", 14, 10, 0], ["place", "aegis_a", 14, 6, 0],
	["place", "training", 16, 10, 0], ["place", "shrine", 16, 6, 0], ["place", "forgeworks", 16, 8, 0],
	["up", "arsenal"], ["up", "reactor"], ["up", "warehouse"], ["up", "refinery"], ["up", "gemmine"], ["up", "treasury"],
	["up", "bulwark_w"], ["up", "optics"], ["up", "rangefinder"], ["up", "aegis_a"], ["up", "scav_post"],
	["up", "archive"], ["up", "barracks"], ["up", "training"], ["up", "shrine"], ["up", "forgeworks"],
]


static func _op_has(save: Dictionary, id: String, x: int, y: int) -> bool:
	for k in save["outpost"]["buildings"].keys():
		var b: Dictionary = save["outpost"]["buildings"][k]
		if String(b["id"]) == id and int(b["x"]) == x and int(b["y"]) == y:
			return true
	return false


static func outpost_spend(save: Dictionary, now: int) -> void:
	Outpost.tick(save, now)
	var guard: int = 0
	while guard < 8 and Outpost.busy(save) < Outpost.builders(save):
		guard += 1
		var budget: int = int(float(save["coins"]) * TuneRef.num("pc_bot_op_frac", 0.4)) + int(save["outpost"].get("credit", 0))
		var did: bool = false
		for st in OP_PLAN:
			var a: Array = st
			match String(a[0]):
				"place":
					var id: String = String(a[1])
					if _op_has(save, id, int(a[2]), int(a[3])):
						continue
					var d: Dictionary = OutpostDB.get_def(id)
					if int(d["coins"]) > budget:
						continue
					did = not Outpost.place(save, id, int(a[2]), int(a[3]), int(a[4]), now).is_empty()
				"plot":
					var pc: Dictionary = Outpost.plot_cost(save)
					if int(pc["coins_alt"]) <= budget:
						did = not Outpost.unlock_plot(save, int(a[1])).is_empty()
				"up":
					var uid: String = ""
					if String(a[1]) == "relay":
						if Outpost.relay_cost(int(save["outpost"]["relay_lvl"])) <= budget:
							uid = "relay"
					else:
						var lo: int = 99
						for k in save["outpost"]["buildings"].keys():
							var b: Dictionary = save["outpost"]["buildings"][k]
							if String(b["id"]) == String(a[1]) and int(b["lvl"]) < lo and Outpost.can_upgrade(save, String(k)) and Outpost.cost(String(b["id"]), int(b["lvl"])) <= budget:
								lo = int(b["lvl"])
								uid = String(k)
					if uid != "":
						did = not Outpost.upgrade(save, uid, now).is_empty()
			if did:
				break
		if not did:
			break


## A competent player works toward the next Core milestone: what it needs
## (an Outpost building / level, the Relay, Core Theory) goes first, within
## half the coins.
const CoreLevelDB := preload("res://data/CoreLevelDB.gd")
static func core_reqs_spend(save: Dictionary, now: int) -> void:
	var ms: int = CoreLevelDB.next_milestone(Cores.level(save))
	if ms <= 0:
		return
	for r in CoreLevelDB.reqs_for(ms):
		var rq: Array = r
		var budget: int = int(float(save["coins"]) * 0.5)
		match String(rq[0]):
			"res":
				var id: String = String(rq[1])
				if Labs.level(save, id) < int(rq[2]) and Labs.is_open(save, id) and Labs.price(save, id) <= budget:
					Labs.start(save, id, now)
			"relay":
				if int(save["outpost"]["relay_lvl"]) < int(rq[2]) and Outpost.relay_cost(int(save["outpost"]["relay_lvl"])) <= budget:
					Outpost.upgrade(save, "relay", now)
			"bld":
				var id2: String = String(rq[1])
				var best_uid: String = ""
				var best_lv: int = -1
				for k in save["outpost"]["buildings"].keys():
					var b: Dictionary = save["outpost"]["buildings"][k]
					if String(b["id"]) == id2 and int(b["lvl"]) > best_lv:
						best_lv = int(b["lvl"])
						best_uid = String(k)
				if best_uid == "":
					for st in OP_PLAN:
						var a: Array = st
						if String(a[0]) == "place" and String(a[1]) == id2 and int(OutpostDB.get_def(id2)["coins"]) <= budget:
							Outpost.place(save, id2, int(a[2]), int(a[3]), int(a[4]), now)
							break
				elif best_lv < int(rq[2]) and Outpost.can_upgrade(save, best_uid) and Outpost.cost(id2, best_lv) <= budget:
					Outpost.upgrade(save, best_uid, now)


## Outpost hourly coin output (live).
static func outpost_coins_h(save: Dictionary) -> float:
	return float(Outpost.production(save)["coins"])


## Research weights (lower = bought earlier at the same price): the board,
## Core levels and raw power first, then economy, enemy cuts and the Forge.
const LAB_W: Dictionary = {
	"grid": 0.3, "core_theory": 0.35, "dmg": 1.0, "hp": 1.1, "coin": 0.9, "speed": 0.12, "startcash": 2.0, "xp": 1.4,
	"offrate": 1.3, "offcap": 2.5, "reroll": 2.5, "targeting": 1.3, "reactor": 1.2, "optics": 1.4, "aegis": 1.5, "shielding": 1.7,
	"en_hp": 1.0, "en_atk": 1.4, "en_speed": 1.6, "boss_breaker": 1.4, "elite_hp": 1.8, "interest": 1.8, "bounty": 1.2,
	"lab_discount": 0.7, "lic_mill": 0.9, "loot_theory": 1.6, "appraisal": 1.7, "enh_theory": 1.2, "stabilizer": 3.0,
	"greater_cal": 2.0, "draft_choices": 1.0, "banish_r": 3.0, "draft_lock": 3.0, "scav_rate": 2.5, "reclaim": 3.0,
}


## Buys research (cheapest weighted price first) until `budget` coins are spent.
static func research_spend(save: Dictionary, now: int, budget: int) -> void:
	var spent: int = 0
	for guard in 200:
		var best: String = ""
		var best_sc: float = INF
		for idv in LAB_W.keys():
			var id: String = String(idv)
			if Labs.level(save, id) >= LabDB.max_of(id) or not Labs.is_open(save, id):
				continue
			var sc: float = float(Labs.price(save, id)) * float(LAB_W[id])
			if sc < best_sc:
				best_sc = sc
				best = id
		if best == "":
			return
		var pr: int = Labs.price(save, best)
		if spent + pr > budget or pr > int(save["coins"]):
			return
		if Labs.start(save, best, now).is_empty():
			return
		spent += pr


## Gear: weapons by estimated DPS, modules by power x perks.
static func _gear_score(save: Dictionary, uid: int) -> float:
	var it: Dictionary = Gear.item(save, uid)
	if it.is_empty():
		return 0.0
	if String(it["kind"]) == "weapon":
		return Gear.est_dps(it)
	return Gear.power(it) * (1.0 + 0.35 * float((it["perks"] as Array).size()))


static func _by_score(save: Dictionary, uids: Array) -> Array:
	var a: Array = uids.duplicate()
	a.sort_custom(func(x: Variant, y: Variant) -> bool:
		var sx: float = _gear_score(save, int(x))
		var sy: float = _gear_score(save, int(y))
		return sx > sy if sx != sy else int(x) < int(y))
	return a


## Merge spare Commons / Uncommons (best three into the next rarity), equip the
## best Weapon and Modules, salvage the weakest past 150 items, level the
## equipped gear, forge a little when rich.
static func gear_manage(save: Dictionary) -> void:
	for kind in ["weapon", "module"]:
		for rar in ["common", "uncommon"]:
			for guard in 20:
				var pool: Array = []
				for u in Gear.uids(save, String(kind)):
					var it: Dictionary = Gear.item(save, int(u))
					if String(it["rar"]) == rar and not Gear.is_equipped(save, int(u)) and not bool(it.get("fav", false)):
						pool.append(int(u))
				if pool.size() < 3:
					break
				var set3: Array = _by_score(save, pool).slice(0, 3)
				if Gear.why_merge(save, set3, int(set3[0])) != "" or Gear.merge(save, set3, int(set3[0]), 0).is_empty():
					break
	var ws: Array = _by_score(save, Gear.uids(save, "weapon"))
	if not ws.is_empty() and not Gear.is_equipped(save, int(ws[0])):
		Gear.equip(save, int(ws[0]))
	var ms: Array = _by_score(save, Gear.uids(save, "module"))
	var n: int = Gear.sockets_for(Cores.level(save))
	for k in mini(n, ms.size()):
		Gear.equip(save, int(ms[k]), k)
	if Gear.count(save) > 150:
		var all: Array = _by_score(save, Gear.uids(save))
		all.reverse()
		for u in all:
			if Gear.count(save) <= 120:
				break
			if not Gear.is_equipped(save, int(u)):
				Gear.salvage(save, int(u))
	var w: Dictionary = Gear.weapon(save)
	if not w.is_empty():
		for guard in 60:
			if Gear.why_upgrade(save, int(w["uid"])) != "" or float(Gear.upgrade_cost(w, save)) > 0.15 * float(save["coins"]):
				break
			Gear.upgrade(save, int(w["uid"]))
	for m in Gear.modules(save):
		for guard in 40:
			if Gear.why_upgrade(save, int(m["uid"])) != "" or float(Gear.upgrade_cost(m, save)) > 0.04 * float(save["coins"]):
				break
			Gear.upgrade(save, int(m["uid"]))
	for k in 2:
		var fc: Dictionary = Gear.forge_cost(save)
		if w.is_empty() or int(save["coins"]) < 8 * int(fc["coins"]) or int(save["scrap"]) < int(fc["scrap"]) + 100 or Gear.count(save) >= 150:
			break
		Gear.forge_new(save, "weapon", String(w["base"]))


## Core levels with what the session has left (requirements permitting).
static func core_spend(save: Dictionary, frac: float) -> void:
	for guard in 400:
		var c: int = int(Cores.level_cost(Cores.level(save))["coins"])
		if float(c) > frac * float(save["coins"]) or Cores.try_level(save).is_empty():
			return


## Start-of-session chores, in the order a player meets them on the hub.
static func session_open(save: Dictionary, now: int, led: Dictionary) -> void:
	Labs.claim(save, now)
	Missions.roll(save, now)
	var c0: int = int(save["coins"])
	var away: int = maxi(0, now - int(save["last_seen"])) / 60 if int(save["last_seen"]) > 0 else 0
	for x in Outpost.claim_away(save, now):
		var oe: Dictionary = x
		if String(oe["t"]) == "offline":
			led["offline_coins"] = int(led["offline_coins"]) + int(oe["coins"])
	save["last_seen"] = now
	led["offline_min"] = int(led["offline_min"]) + away
	Missions.streak_claim(save, now)
	led["gross_coins"] = int(led["gross_coins"]) + int(save["coins"]) - c0
	_claim_missions(save)
	core_reqs_spend(save, now)   # the next Core milestone's requirements
	outpost_spend(save, now)     # cheapest ROI first: Mills pay back in hours
	var c1: int = int(save["coins"])
	research_spend(save, now, int(0.3 * float(c1)))
	gear_manage(save)
	core_spend(save, 0.5)
	research_spend(save, now, int(0.5 * float(save["coins"])))   # half of the rest; the bank saves for big buys
	var steps: Array = Labs.speed_steps(save)
	BaseMeta.set_speed(save, float(steps[steps.size() - 1]))


static func _claim_missions(save: Dictionary) -> void:
	for k in Missions.list(save).size():
		Missions.claim(save, k)
	Missions.claim_bonus(save)


## Tier choice: push the highest unlocked tier; when it pays < 80% of the tier
## below (coins per real minute), farm the lower tier on alternate runs.
static func pick_tier(save: Dictionary, rate: Dictionary, run_idx: int) -> int:
	var h: int = Tiers.highest(save)
	if h > 1 and rate.has(h) and rate.has(h - 1) and float(rate[h]) < 0.8 * float(rate[h - 1]) and run_idx % 2 == 1:
		return h - 1
	return h


# ======================================================================
# CAMPAIGN (main job)
# ======================================================================
## The DAYS-day balanced campaign on one fresh save. Per run: tier, wave,
## coins, game seconds, banked rarities; per day: tier, best waves, Core
## level, research, game speed, gear, coins, Outpost output.
static func campaign(seed0: int, n_days: int) -> Dictionary:
	var save: Dictionary = BaseMeta.default_save()
	var led: Dictionary = {"offline_coins": 0, "offline_min": 0, "gross_coins": 0, "run_coins": 0, "run_min": 0.0}
	var rate: Dictionary = {}          # tier -> latest coins / real minute
	var days: Array = []
	var runs: Array = []
	var snaps: Dictionary = {}
	var run_idx: int = 0
	var t2_day: int = -1
	var sp2_day: int = -1
	var goal_run: int = -1
	var goal_s: float = -1.0
	var first_coins: int = -1
	var rar: Dictionary = {}
	var pity_max: Dictionary = {"e": 0, "l": 0, "m": 0}
	var best_at: Dictionary = {}       # tier -> best wave so far (spiral check)
	var spiral: Array = []
	for d in n_days:
		for h in SESSION_H:
			var now: int = maxi(NOW0 + d * 86400 + int(h) * 3600, int(save["last_seen"]) + 60)
			session_open(save, now, led)
			var t: int = pick_tier(save, rate, run_idx)
			BaseMeta.select_tier(save, t)
			var c0: int = int(save["coins"])
			var r: Dictionary = camp_run(save, "balanced", seed0 + 1000 + run_idx * 131, now)
			if run_idx == 0:
				first_coins = int(save["coins"]) - c0
			if goal_run < 0 and t == 1 and int(r["wave"]) > TowerState.RUN_GOAL_WAVE:
				goal_run = run_idx + 1   # MASS_HORDE H7: first run that held the wave-20 goal
				goal_s = float(r["real_s"])
			var bt: int = int(best_at.get(t, 0))
			if bt >= 10 and int(r["wave"]) < bt / 2:
				spiral.append([run_idx, t, int(r["wave"]), bt])
			best_at[t] = maxi(bt, int(r["wave"]))
			for k in (r["rar"] as Dictionary).keys():
				rar[k] = int(rar.get(k, 0)) + int(r["rar"][k])
			var pity: Dictionary = Gear.block(save)["pity"]
			for g in pity_max.keys():
				pity_max[g] = maxi(int(pity_max[g]), int(pity.get(g, 0)))
			var mins: float = maxf(0.1, float(r["real_s"]) / 60.0)
			rate[t] = float(r["coins"]) / mins
			led["run_coins"] = int(led["run_coins"]) + int(r["coins"])
			led["run_min"] = float(led["run_min"]) + mins
			led["gross_coins"] = int(led["gross_coins"]) + int(r["coins"])
			save["last_seen"] = now + int(r["real_s"])
			runs.append({"day": d + 1, "tier": t, "wave": int(r["wave"]), "coins": int(r["coins"]), "game_s": snappedf(float(r["game_s"]), 1.0), "level": int(r["level"])})
			say("  run %2d d%d T%d wave %2d lvl %2d coins %6d game %4.0fs speed x%.1f" % [run_idx, d + 1, t, int(r["wave"]), int(r["level"]), int(r["coins"]), float(r["game_s"]), float(save["speed"])])
			run_idx += 1
			_claim_missions(save)
		var hi: int = Tiers.highest(save)
		if hi >= 2 and t2_day < 0:
			t2_day = d + 1
		var steps: Array = Labs.speed_steps(save)
		if steps.has(2.0) and sp2_day < 0:
			sp2_day = d + 1
		var lab_sum: int = 0
		for id in LabDB.IDS:
			lab_sum += Labs.level(save, String(id))
		var w: Dictionary = Gear.weapon(save)
		var row: Dictionary = {
			"day": d + 1, "tier": hi, "best_wave_hi_tier": Tiers.best_in(save, hi), "best_wave": int(save["best_wave"]),
			"progress_key": hi * 1000 + Tiers.best_in(save, hi), "core_lvl": Cores.level(save), "labs": lab_sum,
			"speed": float(steps[steps.size() - 1]), "weapon_rar": String(w.get("rar", "")), "weapon_dps": snappedf(Gear.est_dps(w), 0.1) if not w.is_empty() else 0.0,
			"items": Gear.count(save), "coins_gross": int(led["gross_coins"]), "bank": int(save["coins"]), "scrap": int(save["scrap"]),
			"outpost_h": snappedf(outpost_coins_h(save), 1.0), "relay": int(save["outpost"]["relay_lvl"]), "hall": Outpost.level_of(save, "research"),
		}
		days.append(row)
		say("CAMPAIGN day %2d: T%d best@T%d w%d best w%d | core L%d labs %d speed x%.1f | weapon %s %.0f dps, %d items | coins gross %d bank %d scrap %d | outpost %d/h relay %d hall %d | core needs %s" % [d + 1, hi, hi, int(row["best_wave_hi_tier"]), int(row["best_wave"]), int(row["core_lvl"]), lab_sum, float(row["speed"]), String(row["weapon_rar"]), float(row["weapon_dps"]), int(row["items"]), int(row["coins_gross"]), int(row["bank"]), int(row["scrap"]), int(row["outpost_h"]), int(row["relay"]), int(row["hall"]), str(Cores.missing(save))])
		if SNAP_DAYS.has(d + 1):
			snaps[d + 1] = save.duplicate(true)
	return {"days": days, "runs": runs, "save": save, "led": led, "t2_day": t2_day, "speed2_day": sp2_day, "snaps": snaps,
		"goal_run": goal_run, "goal_s": goal_s, "first_coins": first_coins, "rar": rar, "pity_max": pity_max, "spiral": spiral}


## One run on `save` (mutated: banks, missions). Returns run facts: wave,
## tier, coins, real / game seconds, level, banked rarities, R probes.
static func camp_run(save: Dictionary, policy: String, seed_value: int, now: int, perk_pref: String = "", feed_missions: bool = true, opts: Dictionary = {}) -> Dictionary:
	var S = TowerState.new()
	S.mass_lod_cap = BOT_LOD_CAP   # harness-only runtime cap (waves above it compress; see BOT_LOD_CAP)
	S.setup(seed_value, save, now, opts)
	var t: float = 0.0
	var acc: float = 0.0
	var res: Dictionary = {}
	var rar: Dictionary = {}
	var rw: Dictionary = {}          # wave -> effective DPS at the wave's start
	var whp: Dictionary = {}         # wave -> HP spawned in it
	var wt: Dictionary = {}          # wave -> seconds of it played
	var lw: int = -1
	var last_eid: int = -1
	while not S.over and t < MAX_SIM_S:
		var ev: Array = S.tick(DT)
		t += DT
		acc += DT
		if S.wave != lw:
			lw = S.wave
			rw[lw] = PowerModel.effective_dps(S.power_snapshot())
		wt[S.wave] = float(wt.get(S.wave, 0.0)) + DT * S.speed
		var eo: PackedInt32Array = S.en.order
		var ne: int = eo.size()
		var k: int = ne - 1
		while k >= 0 and int(S.en.eid[eo[k]]) > last_eid:
			var es: int = eo[k]
			if String(S.en.kind[es]) != "courier":
				whp[S.wave] = float(whp.get(S.wave, 0.0)) + float(S.en.max_hp[es])
			k -= 1
		if ne > 0:
			last_eid = maxi(last_eid, int(S.en.eid[eo[ne - 1]]))
		if acc >= 0.5:
			acc = 0.0
			ev.append_array(bot_step(S, policy, perk_pref))
		if feed_missions:
			Missions.on_run_events(save, ev)
		for x in ev:
			var e: Dictionary = x
			match String(e.get("t", "")):
				"game_over":
					res = e
				"loot_item", "loot_salvaged":
					rar[String(e["rar"])] = int(rar.get(String(e["rar"]), 0)) + 1
	var coins: int = int(res.get("coins", int(S.coins_run)))
	var wave_s: float = TuneRef.num("wave_time", 25.0)
	var we: int = maxi(1, S.wave / 2)
	var early: float = float(rw.get(we, 0.0)) / maxf(0.001, float(whp.get(we, 0.0)) / wave_s)
	var snap: Dictionary = S.power_snapshot()
	var hp_w: float = maxf(0.001, float(whp.get(S.wave, 0.0)))
	var front: float = PowerModel.effective_dps(snap) / (hp_w / clampf(float(wt.get(S.wave, wave_s)), wave_s / 3.0, wave_s))
	var wall: float = front * PowerModel.required_dps(S.wave, S.tier) / maxf(0.001, PowerModel.required_dps(S.wave + 5, S.tier))
	return {"wave": S.wave, "tier": S.tier, "coins": coins, "real_s": t, "game_s": t * S.speed, "level": S.level, "rar": rar,
		"perks": S.perks_taken.duplicate(), "r_early": early, "r_front": front, "r_wall": wall, "timeout": not S.over}


# ======================================================================
# PHASE-B JOBS (A/B on the frozen day-3 / day-8 snapshots)
# ======================================================================
## Mean death wave of `policy` over seeds, each run on a fresh copy of `save`.
static func ab_waves(save: Dictionary, policy: String, seeds: Array, perk_pref: String = "") -> Dictionary:
	var waves: Array = []
	var tot: float = 0.0
	for sd in seeds:
		var sv: Dictionary = save.duplicate(true)
		var r: Dictionary = camp_run(sv, policy, int(sd), int(sv.get("last_seen", NOW0)) + 3600, perk_pref, false)
		waves.append(int(r["wave"]))
		tot += float(r["wave"])
	return {"waves": waves, "mean": tot / maxf(1.0, float(seeds.size()))}


## The snapshot's gear vs a fresh Common Autocannon loadout.
static func job_gear(seed0: int, snap: Dictionary) -> Dictionary:
	if snap.is_empty():
		return {}
	var a: Dictionary = ab_waves(snap, "balanced", AB_SEEDS.map(func(x: Variant) -> int: return seed0 + int(x)))
	var bare: Dictionary = snap.duplicate(true)
	bare["gear"] = Gear.default_block()
	var b: Dictionary = ab_waves(bare, "balanced", AB_SEEDS.map(func(x: Variant) -> int: return seed0 + int(x)))
	var ratio: float = float(a["mean"]) / maxf(0.1, float(b["mean"]))
	say("GEAR day 8: own gear %s vs Common Autocannon %s -> x%.2f" % [str(a["waves"]), str(b["waves"]), ratio])
	return {"with": a, "without": b, "ratio": ratio}


## With vs without the Outpost's Core buildings (Arsenal, Reactor, ...).
static func job_corebld(seed0: int, snap: Dictionary) -> Dictionary:
	if snap.is_empty():
		return {}
	var a: Dictionary = ab_waves(snap, "balanced", AB_SEEDS.map(func(x: Variant) -> int: return seed0 + int(x)))
	var bare: Dictionary = snap.duplicate(true)
	var bl: Dictionary = bare["outpost"]["buildings"]
	var n: int = 0
	for k in bl.keys():
		if OutpostDB.CORE_IDS.has(String((bl[k] as Dictionary)["id"])):
			bl.erase(k)
			n += 1
	var b: Dictionary = ab_waves(bare, "balanced", AB_SEEDS.map(func(x: Variant) -> int: return seed0 + int(x)))
	var ratio: float = float(a["mean"]) / maxf(0.1, float(b["mean"]))
	say("COREBLD day 8: %d Core buildings %s vs none %s -> x%.2f" % [n, str(a["waves"]), str(b["waves"]), ratio])
	return {"with": a, "without": b, "ratio": ratio, "core_buildings": n}


## Levels reached by wave XP_WAVE with the Core held up (pure XP engine):
## XP-focus policy vs balanced on the day-3 save.
const XP_WAVE: int = 12
static func _levels_by(save: Dictionary, policy: String, seed_value: int) -> int:
	var S = TowerState.new()
	S.mass_lod_cap = BOT_LOD_CAP
	S.setup(seed_value, save.duplicate(true), int(save.get("last_seen", NOW0)) + 3600)
	S.max_hp_mult = 1.0e6
	S.recompute()
	S.hp = float(S.stats["max_hp"])
	var t: float = 0.0
	var acc: float = 0.0
	while S.wave <= XP_WAVE and not S.over and t < MAX_SIM_S:
		S.tick(DT)
		t += DT
		acc += DT
		if acc >= 0.5:
			acc = 0.0
			bot_step(S, policy)
	return S.level


static func job_xp(seed0: int, snap: Dictionary) -> Dictionary:
	if snap.is_empty():
		return {}
	var lb: Array = []
	var lx: Array = []
	for sd in AB_SEEDS:
		lb.append(_levels_by(snap, "balanced", seed0 + int(sd)))
		lx.append(_levels_by(snap, "xp", seed0 + int(sd)))
	var mb: float = float(lb.reduce(func(a: int, b: int) -> int: return a + b, 0)) / float(lb.size())
	var mx: float = float(lx.reduce(func(a: int, b: int) -> int: return a + b, 0)) / float(lx.size())
	say("XP day 3: levels by wave %d balanced %s vs XP focus %s -> x%.2f" % [XP_WAVE, str(lb), str(lx), mx / maxf(0.1, mb)])
	return {"balanced": lb, "xp": lx, "ratio": mx / maxf(0.1, mb)}


## Radial-only vs directional-only weapon drafts on the day-8 save.
static func job_dir(seed0: int, snap: Dictionary) -> Dictionary:
	if snap.is_empty():
		return {}
	var sds: Array = AB_SEEDS.map(func(x: Variant) -> int: return seed0 + int(x))
	var r: Dictionary = ab_waves(snap, "radial", sds)
	var d: Dictionary = ab_waves(snap, "directional", sds)
	var ratio: float = maxf(float(r["mean"]), float(d["mean"])) / maxf(0.1, minf(float(r["mean"]), float(d["mean"])))
	say("DIR day 8: radial %s vs directional %s -> spread x%.2f" % [str(r["waves"]), str(d["waves"]), ratio])
	return {"radial": r, "directional": d, "spread": ratio}


## Each weapon as the only weapon (one seed) vs the balanced mean.
static func job_weapons(seed0: int, snap: Dictionary, ids: Array) -> Dictionary:
	if snap.is_empty():
		return {}
	var bal: Dictionary = ab_waves(snap, "balanced", AB_SEEDS.map(func(x: Variant) -> int: return seed0 + int(x)))
	var out: Dictionary = {}
	for id in ids:
		out[String(id)] = int(ab_waves(snap, "only:" + String(id), [seed0 + int(AB_SEEDS[0])])["waves"][0])
	say("WEAPONS day 8: balanced %s | only-one-weapon %s" % [str(bal["waves"]), JSON.stringify(out)])
	return {"balanced": bal, "only": out}


## Each gold-perk family preferred (one seed) vs the balanced mean.
static func job_perks(seed0: int, snap: Dictionary) -> Dictionary:
	if snap.is_empty():
		return {}
	var bal: Dictionary = ab_waves(snap, "balanced", AB_SEEDS.map(func(x: Variant) -> int: return seed0 + int(x)))
	var out: Dictionary = {}
	for f in PerkDB.FAMILIES:
		out[String(f)] = int(ab_waves(snap, "fam:" + String(f), [seed0 + int(AB_SEEDS[0])])["waves"][0])
	say("PERKS day 8: balanced %s | family-first %s" % [str(bal["waves"]), JSON.stringify(out)])
	return {"balanced": bal, "fam": out}


# ======================================================================
# GATES
# ======================================================================
## Merge every job into the METRICS dict and evaluate the V2 gates.
static func combine(R: Dictionary) -> Dictionary:
	var m: Dictionary = {}
	var M: Dictionary = R.get("main", {})
	var Fr: Dictionary = R.get("fresh", {})
	var X: Dictionary = R.get("mass", {})
	m.merge(fresh_checks(Fr))
	m.merge(mass_checks(X, M))
	var days: Array = M.get("days", [])
	if days.is_empty():
		return m
	m["days"] = days
	m["t2_day"] = int(M["t2_day"])
	m["speed2_day"] = int(M["speed2_day"])
	m["first_coins"] = int(M["first_coins"])
	m["rarities"] = M["rar"]
	m["pity_max"] = M["pity_max"]
	m["spiral"] = M["spiral"]
	# solvent: the very first run banks a Core level (300 coins) or more
	m["solvent"] = int(M["first_coins"]) >= 300
	m["first_goal_day1"] = int((days[0] as Dictionary)["best_wave"]) >= FIRST_GOAL_WAVE
	m["progressable"] = int((days.back() as Dictionary)["progress_key"]) >= int((days[0] as Dictionary)["progress_key"]) + 10
	m["no_death_spiral"] = (M["spiral"] as Array).is_empty()
	m["t2_by_day3_6"] = int(M["t2_day"]) >= 3 and int(M["t2_day"]) <= 6
	m["speed2_by_day4_8"] = int(M["speed2_day"]) >= 4 and int(M["speed2_day"]) <= 8
	var G: Dictionary = R.get("gear", {})
	m["gear_ratio"] = snappedf(float(G.get("ratio", 0.0)), 0.01)
	m["gear_matters"] = float(G.get("ratio", 0.0)) >= 1.25
	var C: Dictionary = R.get("corebld", {})
	m["corebld_ratio"] = snappedf(float(C.get("ratio", 0.0)), 0.01)
	m["corebld_matters"] = float(C.get("ratio", 0.0)) >= 1.10
	var XP: Dictionary = R.get("xp", {})
	m["xp_ratio"] = snappedf(float(XP.get("ratio", 0.0)), 0.01)
	m["xp_drafts"] = float(XP.get("ratio", 0.0)) >= 1.20
	var D: Dictionary = R.get("dir", {})
	m["dir_spread"] = snappedf(float(D.get("spread", 99.0)), 0.01)
	m["dir_parity"] = not D.is_empty() and float(D["spread"]) <= 1.25
	# no dominant weapon: no single-weapon run beats the balanced mix by > 20%
	var only: Dictionary = {}
	var bal_w: float = 0.0
	for j in ["weapons_a", "weapons_b"]:
		var W: Dictionary = R.get(j, {})
		if W.is_empty():
			continue
		only.merge(W["only"])
		bal_w = maxf(bal_w, float(W["balanced"]["mean"]))
	var top_w: float = 0.0
	for k in only.keys():
		top_w = maxf(top_w, float(only[k]))
	m["weapons_only"] = only
	m["weapon_top_ratio"] = snappedf(top_w / maxf(0.1, bal_w), 0.01)
	m["no_dominant_weapon"] = only.size() == _weapon_ids().size() and top_w <= 1.2 * bal_w
	var P: Dictionary = R.get("perks", {})
	var top_p: float = 0.0
	for k in (P.get("fam", {}) as Dictionary).keys():
		top_p = maxf(top_p, float(P["fam"][k]))
	m["perk_fam"] = P.get("fam", {})
	m["perk_top_ratio"] = snappedf(top_p / maxf(0.1, float((P.get("balanced", {}) as Dictionary).get("mean", 0.0))), 0.01)
	m["no_dominant_perk"] = not P.is_empty() and top_p <= 1.2 * float(P["balanced"]["mean"])
	# pity: counters never pass their hard caps; Epic+ arrives at least once
	# per 30 banked rolls on average
	var rolls: int = 0
	var epic_up: int = 0
	for k in (M["rar"] as Dictionary).keys():
		rolls += int(M["rar"][k])
		if RarityDB.at_least(String(k), "epic"):
			epic_up += int(M["rar"][k])
	var pm: Dictionary = M["pity_max"]
	m["pity_holds"] = int(pm["e"]) <= int(RarityDB.PITY["e"]["hard"]) and int(pm["l"]) <= int(RarityDB.PITY["l"]["hard"]) and epic_up * 30 >= rolls
	return m


static func mass_checks(X: Dictionary, M: Dictionary) -> Dictionary:
	var o: Dictionary = {"mass_h": X.duplicate(true)}
	o["h1_wave_bodies"] = bool(X.get("h1_ok", false))
	o["h2_peak_10k_held"] = bool(X.get("h2_ok", false))
	o["h3_no_split"] = bool(X.get("h3_ok", false))
	o["h4_designed_hp"] = bool(X.get("h4_ok", false))
	o["h5_pool_cash"] = bool(X.get("h5_ok", false))
	o["h6_drops"] = bool(X.get("h6_ok", false))
	o["h8_weapons_matter"] = bool(X.get("h8_ok", false))
	o["h10_mass_determinism"] = bool(X.get("h10_ok", false))
	# H7 (re-aimed, documented in MASS_HORDE §Content): the campaign bot holds
	# the T1 wave-20 goal within its first day (4 runs), and that run is
	# shorter than 18 min (25 s waves: wave 20 is ~8.5 min).
	var gr: int = int(M.get("goal_run", -1))
	o["goal_run"] = gr
	o["goal_run_s"] = snappedf(float(M.get("goal_s", -1.0)), 0.1)
	o["h7_first_goal_day1"] = gr >= 1 and gr <= SESSION_H.size() and float(M.get("goal_s", 1e9)) <= 18.0 * 60.0
	return o



## AC-25 + the strong no-death-spiral partner over FRESH_N fresh first runs.
## AC-25: the median fresh balanced death wave is in [12, 25] and at most a
## quarter of fresh runs reach the wave-30 boss; median R(w*/2) >= 2 and
## median R(w*+5) < 0.6. Spiral partner: the median fresh run reaches the
## first goal and no fresh run falls short of it.
static func fresh_checks(Fr: Dictionary) -> Dictionary:
	if Fr.is_empty():
		return {"ac25_fresh_wall": false, "fresh_median_first_goal": false}
	var w: Array = Fr["waves"]
	var mw: float = _median(w)
	var at30: int = 0
	for x in w:
		if int(x) >= 30:
			at30 += 1
	var tm: float = _median(Fr.get("times", []))
	var me: float = _median(Fr["r_early"])
	var ml: float = _median(Fr["r_wall"])
	return {
		"fresh_runs": {"n": w.size(), "waves": w, "median_wave": mw, "min_wave": int(w.min()), "reach_w30": at30, "r_early_median": snappedf(me, 0.01), "r_wall_median": snappedf(ml, 0.01)},
		"ac25_fresh_wall": w.size() >= 16 and mw >= 8.0 and mw <= 15.0 and at30 * 4 <= w.size() and me >= 2.0 and ml < 0.6,   # owner FB1: fresh wall at waves 8-15 (was 12-25)
		"fresh_median_first_goal": w.size() >= 16 and mw >= float(FRESH_GOAL_WAVE) and int(w.min()) >= FRESH_GOAL_WAVE,
		"fresh_median_s": snappedf(tm, 0.1),
		"first_run_short": tm >= 300.0 and tm <= 480.0,   # owner FB2: short first runs ~5-8 min (median of the fresh first runs)
	}


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	var n: int = b.size()
	return float(b[n / 2]) if n % 2 == 1 else (float(b[n / 2 - 1]) + float(b[n / 2])) / 2.0
