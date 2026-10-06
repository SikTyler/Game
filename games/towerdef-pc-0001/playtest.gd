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
# Campaign gates (ECONOMY.md / BRIEF AC-38..41): eco-mix >= 1.10x pure weapon
# waves (AC-38), mono-building permanent boards < 70% of balanced (AC-39; the
# probe may still place drafted run-only buildings, which makes it stricter),
# T2 on day 3-5 + day-1 best wave 18-32 (AC-40), no post-T3 plateau, and the
# week-1 checks repeated on EXTRA_SEEDS.
# PC (7x7 board, build cap, multi-lane waves): the bot places weapons as close
# to the core as the ring rules allow, keeps the Beacon lane focus on an active
# lane, cancels cards with no legal cell, buys outer cells for land development
# once saturated, and picks the mildest endless mutation. PC gates: swapping
# Mines for Refineries never out-earns the same board by > 15% (PC-E14), every challenge modifier reaches
# wave 25 on the day-20 save and endless plays past its first mutation (PC-E16);
# modifier coin rewards are fair vs a same-seed baseline and endless pays
# 0.8-1.15x a normal run (PC_BALANCE.md).
# REDESIGN (ENGINE-RUN): the bot drafts every pick family (buildings, huts,
# packs, specials, Insight), casts specials, buys the 5 Core cash tracks and,
# between runs, Core levels (+ legacy Core stats). Adapted invariants (design
# change, documented): AC-38 -> REDESIGN_BRIEF AC-30 (mixed beats zero-eco and
# all-eco frontier, no coin premium); AC-39 -> a one-building run stays below
# the mixed run (no permanent mono boards exist); PC-E14 refinery probe now
# compares the same save (Refinery is a run pick; permanent slots no longer
# enter runs, ratio reported). Nothing else loosened.
# Prints per-run lines + "PLAYTEST METRICS {json}" + exactly "PLAYTEST OK" (exit 0)
# or "PLAYTEST FAIL: ..." (exit 1). Clears user:// saves at start and end.

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const TuneRef := preload("res://Tune.gd")
const PerkDB := preload("res://data/PerkDB.gd")
const PickDB := preload("res://data/PickDB.gd")
const Specials := preload("res://Specials.gd")
const Cores := preload("res://Cores.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const Reforge := preload("res://Reforge.gd")
const PowerModel := preload("res://PowerModel.gd")
const ReforgeDB := preload("res://data/ReforgeDB.gd")

const DT: float = 0.1
const MAX_SIM_S: float = 3600.0
const RUNS: int = 8
const FIRST_GOAL_WAVE: int = 5
## MASS_HORDE harness fidelity (documented in MASS_HORDE §Content): the 30-day
## campaign plays hundreds of runs, so a wave planned above this many bodies
## spawns one body per k = ceil(B / cap) carrying k x HP / damage / pool share
## / kill count. Waves up to the cap (every T1 wave <= 21, i.e. every first
## run, H7) are simulated 1:1; the H1/H2/H8 mass gates always run at 1:1.
const BOT_LOD_CAP: int = 1200
const PROGRESS_GAIN: int = 5
const SEED_DEFAULT: int = 4242
const MIX_ECO_UNTIL: int = 15

var fail_count: int = 0
const GATES: Array = ["solvent", "first_goal_reachable", "progressable", "no_death_spiral", "no_trivial_dominant",
	"t2_by_day5", "tier3_by_day30", "no_plateau_before_t3", "early_3day_rise",
	"gems_per_day_ok", "gem_sources_ok", "offline_below_active", "mix_beats_weapon", "mix_beats_eco", "no_dominant_perk",
	"ac38_eco_mix", "ac39_no_mono", "day1_band", "first_run_short", "no_plateau_after_t3", "seeds_ok",
	"pc_refinery_not_dominant", "pc_modifiers_reach_w25", "pc_modifiers_fair", "pc_endless_runs"]
const EXTRA_SEEDS: Array = [5151, 6262]   # AC-38/AC-40 re-checked on more seeds (thin margins)


static var QUIET: bool = false      # child jobs buffer their log instead of printing
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
	if args.has("only"):
		# Debug: one job in-process, verbose (no gates).
		FORGE_DUMP = String(args.get("dump", ""))
		FORGE_RESUME = String(args.get("resume", ""))
		var o: Dictionary = run_job(String(args["only"]), seed0, OS.get_user_data_dir())
		if not String(args["only"]).begins_with("main"):
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
# The audit is split into independent deterministic jobs (each one owns its
# saves and RNG seeds) so it can fan out over CPU cores: the parent re-launches
# this script headless once per job (`-- job=<name> dir=<tmp>`), at most
# `workers` at a time, and merges the results. Phase-B jobs replay the day-7 /
# day-20 snapshots the "main" job writes (var_to_bytes: exact). `-- serial`
# runs every job in-process (same results; for debugging).
const JOBS_A: Array = ["main", "forge:balanced", "forge:eco", "forge:single", "forge:damage", "strat", "seed:0", "seed:1", "pol", "fresh", "mass"]
const JOBS_B: Array = ["perks", "mods", "mono", "specs", "sets"]


static func _job_file(job: String) -> String:
	return job.replace(":", "_") + ".bin"


static func run_job(job: String, seed0: int, dir: String) -> Dictionary:
	var p: PackedStringArray = job.split(":")
	match p[0]:
		"pol":
			return job_policies(seed0)
		"main":
			return job_main(seed0, dir)
		"strat":
			return job_strat(seed0)
		"seed":
			return job_seed(seed0, int(EXTRA_SEEDS[int(p[1])]))
		"perks", "mods", "mono":
			var snaps: Dictionary = {}
			for d in [7, 20]:
				var f := FileAccess.open(dir.path_join("snap%d.bin" % d), FileAccess.READ)
				snaps[d] = bytes_to_var(f.get_buffer(f.get_length()))
				f.close()
			match p[0]:
				"perks":
					return job_perks(seed0, snaps)
				"mods":
					return job_mods(seed0, snaps)
				_:
					return job_mono(seed0, snaps)
		"fresh":
			return job_fresh(seed0)
		"mass":
			return job_mass(seed0)
	return {}


# ======================================================================
# MASS_HORDE §D8 invariants H1-H12 (replace the split-model gates; owner
# FEEDBACK_3). Every probe here runs the shipped ruleset at 1:1 (no harness
# LOD): designed bodies, mass waves, legacy split knob off.
#   H1 body counts 100s -> 1,000s -> 10,000s   H2 peak alive >= 10k, queue held
#   H3 no split body (share 1, knob 1)          H4 designed HP x growth
#   H5 full-clear wave pays pool x 1.3 (+-5%)   H6 drops <= cap, >= 1 per 2 waves
#   H7 first-run goal held on day 1 (campaign)  H8 every weapon kills masses
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
	S.slots[si] = {"id": kinds[0], "perm": 0, "run": lv}
	S.unlocked[si] = true
	if kinds.size() > 1:
		var s2: int = si - TowerState.size_of(kinds[1])   # V2 P3b: just west of the first footprint
		S.slots[s2] = {"id": kinds[1], "perm": 0, "run": lv}
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
		S.slots[si] = {"id": wk, "perm": 0, "run": 5}
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
	for d in [7, 20]:
		DirAccess.remove_absolute(dir.path_join("snap%d.bin" % d))
	R["_failed"] = failed
	return R


static func job_policies(seed0: int) -> Dictionary:
	var camp: Dictionary = {}
	for pol in ["balanced", "eco", "weapon", "mono:gun", "mono:mortar", "mono:tesla"]:
		camp[pol] = campaign(pol, seed0)
	var bal: Array = camp["balanced"]["waves"]
	var eco: Array = camp["eco"]["waves"]
	var wpn: Array = camp["weapon"]["waves"]
	var first: Dictionary = camp["balanced"]["first"]
	var first_wave: int = int(first["wave"])
	var bal_best: int = int(bal.max())
	var eco_best: int = int(eco.max())
	var wpn_best: int = int(wpn.max())
	# AC-39 (adapted, REDESIGN): the Core is the main weapon and buildings are
	# single-instance picks, so a "mono board" no longer exists; a run that
	# builds only one building id must still fall short of the mixed run.
	# (Was: mono permanent board < 70% of balanced.)
	var mono8: Dictionary = {}
	var mono8_ok: bool = true
	for mid in ["gun", "mortar", "tesla"]:
		var mb8: int = int((camp["mono:" + mid]["waves"] as Array).max())
		mono8[mid] = mb8
		if mb8 >= bal_best:
			mono8_ok = false
	# Death spiral (REDESIGN-adapted, deliberate): the in-run grid is now a
	# roguelite draft (starts empty, random picks), so single-seed outcomes
	# quantise to the boss walls (w20 / w30) and run-to-run drops of one boss
	# step are draft variance, not a collapse. A spiral is progress trending
	# DOWN: the later half's median below the first half's by > 2 waves, or any
	# run below the very first run by > 2. (Was: any run > 2 below the previous.)
	var half: int = bal.size() / 2
	var spiral: bool = _median(bal.slice(half)) < _median(bal.slice(0, half)) - 2.0
	for k in range(1, bal.size()):
		if int(bal[k]) < int(bal[0]) - 2:
			spiral = true
	return {
		"first_wave": first_wave, "first_coins": int(first["coins"]), "first_levels": int(first["level"]),
		"first_time_s": snappedf(float(first["time"]), 0.1),
		"balanced_waves": bal, "eco_waves": eco, "weapon_waves": wpn,
		"balanced_best": bal_best, "eco_best": eco_best, "weapon_best": wpn_best,
		"solvent": int(first["coins"]) >= 15,
		"first_goal_reachable": first_wave >= FIRST_GOAL_WAVE,
		"progressable": bal_best >= first_wave + PROGRESS_GAIN,
		"no_death_spiral": not spiral,
		"no_trivial_dominant": float(maxi(eco_best, wpn_best)) <= float(bal_best) * 1.15,
		"mono_best": mono8, "ac39_no_mono": mono8_ok,
	}


static func campaign(policy: String, seed0: int) -> Dictionary:
	var save: Dictionary = BaseMeta.default_save()
	var waves: Array = []
	var first: Dictionary = {}
	for r in RUNS:
		var res: Dictionary = run_once(save, policy, seed0 + r * 97)
		if r == 0:
			first = res
		waves.append(int(res["wave"]))
		say("PLAYTEST run %s #%d: wave %d lv %d kills %d coins %d (%.0fs) bank=%d" % [policy, r + 1, res["wave"], res["level"], res["kills"], res["coins"], res["time"], save["coins"]])
		spend_meta(save, policy)
	return {"waves": waves, "first": first}


## Draft score for one card under a policy (REDESIGN: every pick family).
##   balanced: weapons first, then a mix of eco / packs / specials / troops
##   eco:      eco picks first; weapon: dps/aoe/control only
##   mono:X:   AC-39 probe — only building X (and its level-ups); otherwise the
##             least committal card (packs that are not damage)
##   refinery: PC-E14 probe — Refinery + Mine first, weapons as glue
static func _card_score(S, policy: String, c: Dictionary) -> float:
	var id: String = String(c["id"])
	var fam: String = String(c["fam"])
	var kind: String = String(c["kind"])
	var tags: Array = c["tags"]
	var rar: int = ["common", "rare", "epic", "legendary"].find(String(c["rarity"]))
	if kind == "insight":
		return 1000.0
	var weapon: bool = fam == "building" and (tags.has("dps") or tags.has("aoe") or tags.has("control")) and not ["armory", "beacon", "barricade"].has(id)
	var eco: bool = tags.has("eco")
	var nw: int = _weapon_count(S)
	var sc: float = 1.0 + 1.5 * float(maxi(0, rar))
	if policy.begins_with("mono:"):
		if id == policy.substr(5):
			return 100.0
		if fam == "pack" and not tags.has("dps"):
			return 5.0
		return 1.0 if fam == "building" or fam == "hut" else 2.0
	match policy:
		"eco":
			if eco:
				sc += 10.0
			elif fam == "building" and nw < 1 and weapon:
				sc += 6.0
		"weapon":
			if weapon or (fam == "pack" and tags.has("dps")):
				sc += 10.0
			elif eco:
				sc -= 5.0
		"refinery":
			if id == "refinery" or id == "mine":
				sc += 12.0
			elif weapon:
				sc += 6.0
		"spec_eco", "single", "damage":
			# Redesign specs = the balanced line re-weighted: spec_eco takes up to
			# 3 eco picks from wave 10; single keeps few buildings and stacks the
			# Core (Core Surge, damage packs, Overdrive); damage takes one eco pick
			# and every damage card.
			var ne2: int = _counts(S).y
			if eco:
				var cap: int = {"spec_eco": 3, "single": 2, "damage": 1}[policy]
				var from: int = 10 if policy == "spec_eco" else TuneRef.int_of("bot_eco_from", 12)
				sc += 11.0 if (nw >= 1 and S.wave >= from and S.wave < 20 and ne2 < cap) else -2.0
			elif weapon:
				if policy == "single":
					sc += 11.0 if nw < 1 + S.wave / 10 else 4.0
				else:
					sc += 11.0 if nw < 3 + S.wave / 5 else 9.0
			elif fam == "pack" and tags.has("dps"):
				sc += 12.0 if (policy == "single" and id == "pk_core") else (10.0 if policy != "spec_eco" else 9.0)
			elif fam == "special":
				sc += (6.0 if policy == "single" and id == "sp_overdrive" else 0.0) + (3.0 if ["sp_orbital", "sp_overdrive", "sp_timewarp", "sp_emp"].has(id) else 1.0)
			elif fam == "hut":
				sc += 2.5
		_:
			# balanced = the weapon line plus an early eco engine: the first two
			# eco picks before wave 12 come first (they compound all run), then
			# weapons / damage packs, then utility (specials, troops).
			var ne: int = _counts(S).y
			if eco:
				sc += TuneRef.num("bot_eco_pick", 11.0) if (nw >= 2 and S.wave >= TuneRef.int_of("bot_eco_from", 12) and S.wave < 16 and ne < 2) else -2.0
			elif weapon:
				sc += 11.0 if nw < 3 + S.wave / 5 else 9.0
			elif fam == "pack" and tags.has("dps"):
				sc += 9.0
			elif fam == "special":
				sc += 3.0 if ["sp_orbital", "sp_overdrive", "sp_timewarp", "sp_emp"].has(id) else 1.0
			elif fam == "hut":
				sc += 2.5
	if kind == "plus":
		sc += 1.5
	return sc


static func _weapon_count(S) -> int:
	var n: int = 0
	for w in S.stats.get("weapons", []):
		if int((w as Dictionary)["slot"]) != TowerState.CORE_SLOT:
			n += 1
	return n


static func _counts(S) -> Vector2i:
	var w: int = 0
	var e: int = 0
	for i in TowerState.N:
		var id: String = S.id_at(i)
		if id == "":
			continue
		if PickDB.is_eco(id):
			e += 1
		elif BuildingDB.cat_of(id) == "weapon":
			w += 1
	return Vector2i(w, e)


## Perk pick: policy family first, pure perks over tradeoffs.
static func _perk_score(policy: String, id: String) -> int:
	var d: Dictionary = PerkDB.get_def(id)
	var fam: String = String(d.get("fam", ""))
	var sc: int = 0 if bool(d.get("tradeoff", false)) else 2
	match policy:
		"eco":
			sc += 3 if fam == "economy" else 0
		"weapon":
			sc += 3 if fam == "offense" else 0
		_:
			sc += 3 if fam != "economy" else 1
	return sc


## Track priority weights per policy: cheapest weighted cost wins.
static func _track_weight(S, policy: String, t: String) -> float:
	var hp_frac: float = S.hp / maxf(1.0, float(S.stats["max_hp"]))
	match policy:
		"eco":
			return {"eco": 0.4, "dmg": 1.0, "rate": 1.4, "range": 3.0, "armor": 1.6}[t]
		"weapon":
			return {"eco": 99.0, "dmg": 0.8, "rate": 1.0, "range": 2.0, "armor": 1.4}[t]
	var w: Dictionary = {"dmg": 0.8, "rate": 1.0, "range": 2.0, "eco": TuneRef.num("bot_eco_w", 0.35) if S.wave < TuneRef.int_of("bot_eco_until", 30) else TuneRef.num("bot_eco_w_late", 1.6), "armor": 0.9 if hp_frac < 0.5 else 1.4}
	match policy:
		"spec_eco":
			w = {"eco": 0.3 if S.wave < 35 else 1.2, "dmg": 0.8, "rate": 1.0, "range": 2.0, "armor": 0.9 if hp_frac < 0.5 else 1.4}
		"single":
			w = {"eco": 0.5 if S.wave < 25 else 1.8, "dmg": 0.7, "rate": 0.85, "range": 2.0, "armor": 0.9 if hp_frac < 0.5 else 1.4}
	if int(S.tracks["range"]) >= 6:
		w["range"] = 6.0
	# Boss prep: the last waves before a boss wave go to damage, not eco.
	var be: int = int(S.boss_every)
	if S.wave >= maxi(be, TuneRef.int_of("bot_boss_prep_from", 0)) and be - S.wave % be <= TuneRef.int_of("bot_boss_prep", 3):
		w["eco"] = float(w["eco"]) * 4.0
	return float(w[t])


## Specials: cast when it pays (bots use auto-aim for Orbital).
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
			"sp_orbital":
				go = live >= 4 or boss
			"sp_emp":
				go = live >= 10 or (boss and near > 0)
			"sp_repair":
				go = hp_frac < 0.55
			"sp_overdrive":
				go = near >= 3 or boss
			"sp_magnet":
				go = live >= 12
			"sp_timewarp":
				go = hp_frac < 0.4 and near >= 3
		if go:
			var r: Dictionary = S.cast_special(k, -1)
			ev.append_array(r["ev"])
	return ev


## Competent in-run policy; also used as a library by selftest / _shots.
static func bot_step(S, policy: String, perk_pref: String = "") -> Array:
	var ev: Array = []
	if S.mutation_offer.size() > 0:
		ev.append_array(S.choose_mutation(_pick_mutation(S)))
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
		if best_score < 5.0 and S.reroll_cost() == 0 and not policy.begins_with("mono:"):
			ev.append_array(S.reroll_draft())
		else:
			ev.append_array(S.choose_card(best))
	if S.pending_place != "":
		var cell: int = _place_cell(S, S.pending_place)
		if cell >= 0:
			ev.append_array(S.place(cell))
		else:
			ev.append_array(S.cancel_place())   # nowhere legal: skip the card
	# FEEDBACK-1: an upgrade pick is applied onto the lowest-level copy.
	if S.pending_upgrade != "":
		var tg: Array = S.upgrade_targets(S.pending_upgrade)
		var lo: int = -1
		for c in tg:
			if lo < 0 or S.lvl_at(int(c)) < S.lvl_at(lo):
				lo = int(c)
		ev.append_array(S.apply_upgrade(lo) if lo >= 0 else S.cancel_upgrade())
	if not policy.begins_with("mono:"):
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
	# Spend cash on the Core track with the cheapest weighted price.
	var guard: int = 0
	while guard < 12:
		guard += 1
		var bt: String = ""
		var bc: float = INF
		for t in TowerState.TRACK_IDS:
			var c: int = S.track_cost(String(t))
			if c < 0 or (policy == "weapon" and String(t) == "eco"):
				continue   # zero-eco line: never the Eco track either
			var wc: float = float(c) * _track_weight(S, policy, String(t))
			if wc < bc:
				bc = wc
				bt = String(t)
		if bt == "" or S.cash < float(S.track_cost(bt)):
			break
		ev.append_array(S.buy_track(bt))
	return ev


## Endless mutations: the competent pick is the least dangerous buff
## (Plating only matters with elites, Rush before Fangs/Vigor/Horde).
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


## Placement: weapons as close to the Core as allowed (cover every lane),
## huts on the busiest lane's side, eco / support on the outer cells.
static func _place_cell(S, id: String) -> int:
	var best: int = -1
	var best_k: float = INF
	var inner: bool = BuildingDB.cat_of(id) == "weapon" or id == "armory" or id == "beacon" or id == "frost"
	for i in S.free_slots():
		if not S.can_place(int(i), id):
			continue
		var r: int = TowerState.ring_of(int(i))
		var k: float = float(r) if inner else float(10 - r)
		if PickDB.fam_of(id) == "hut":
			k = float(10 - r)   # FEEDBACK-1: no lanes — huts sit on the outer cells
		k += float(int(i)) * 0.001
		if k < best_k:
			best_k = k
			best = int(i)
	return best


static func run_once(save: Dictionary, policy: String, seed_value: int) -> Dictionary:
	var S = TowerState.new()
	S.mass_lod_cap = BOT_LOD_CAP   # harness-only runtime cap (waves above it compress; see BOT_LOD_CAP)
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


## Meta spending between runs (REDESIGN + ENGINE-META): coins go to the
## active Core's level first (Core Cores gate every 5th level), then Field
## Crates (Keys open Supply Crates), then the best parts are installed and
## levelled with Scrap. The legacy v3 Core stat levels are no longer bought
## (save v4 migrates them into the Bastion level). The Outpost is built in
## session_open (it needs the clock).
static func spend_meta(save: Dictionary, policy: String, rng: RandomNumberGenerator = null) -> void:
	var guard: int = 0
	var core_order: Array = ["dmg", "hp", "regen"]
	while guard < 400:
		guard += 1
		var cid: String = Cores.active(save)
		var did: bool = not Cores.try_level(save).is_empty()
		if not did:
			break












## The Outpost plan a competent player follows (start area first, then plot
## 0): [kind, id, x, y, rot]. Each session the bot takes the first affordable
## action (one job per builder) within pc_bot_op_frac of its coins.
const OP_PLAN: Array = [
	["place", "mill", 4, 4, 0], ["place", "mill", 4, 6, 0], ["place", "warehouse", 3, 2, 0],
	["up", "mill"], ["up", "relay"], ["up", "research"], ["place", "conduit", 2, 6, 0],
	["place", "refinery", 0, 4, 0], ["place", "gemmine", 0, 6, 0],
	["plot", 0], ["place", "mill", 6, 4, 0], ["place", "archive", 6, 2, 0], ["place", "barracks", 8, 4, 0],
	["place", "mill", 8, 2, 0], ["up", "warehouse"], ["up", "refinery"], ["up", "gemmine"],
	["up", "archive"], ["up", "barracks"],
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


## Outpost hourly coin output (live).
static func outpost_coins_h(save: Dictionary) -> float:
	return float(Outpost.production(save)["coins"])


# ======================================================================
# CAMPAIGN SIM — ~30 simulated days of the full retention loop with an
# injected clock: login streak, missions, offline earnings, labs (real-time
# research that completes between sessions), cards (chests/equip/slots),
# perks, permanent base spending and tier selection. The balanced bot plays
# every run; policy / perk comparisons replay a frozen snapshot save.
# ======================================================================
const Labs := preload("res://Labs.gd")
const Missions := preload("res://Missions.gd")
const Outpost := preload("res://Outpost.gd")
const Tiers := preload("res://Tiers.gd")
const LabDB := preload("res://data/LabDB.gd")
const ModifierDB := preload("res://data/ModifierDB.gd")

const DAYS: int = 30
const SESSION_H: Array = [8, 8, 16, 16]        # 2 sessions x 2 runs; 8 h / 16 h offline gaps (AC-40)
const NOW0: int = 1767225600                   # 2026-01-01 00:00 UTC (a day boundary)
## FEEDBACK-1: Grid Expansion is the first research a player buys (bigger
## board = more buildings); Lab Speed is gone (research is instant).
const LAB_PRIO: Array = ["grid", "dmg", "hp", "coin", "speed", "startcash", "xp", "offrate", "offcap", "reroll"]
const LAB_W: Dictionary = {"grid": 0.25, "dmg": 1.0, "hp": 1.0, "coin": 1.0, "speed": 0.6, "startcash": 1.6, "xp": 1.8, "offrate": 2.0, "offcap": 2.0, "reroll": 2.5}

## One run on `save` (mutated: banks, missions). Returns run facts.
static func camp_run(save: Dictionary, policy: String, seed_value: int, now: int, perk_pref: String = "", feed_missions: bool = true, opts: Dictionary = {}) -> Dictionary:
	var S = TowerState.new()
	S.mass_lod_cap = BOT_LOD_CAP   # harness-only runtime cap (waves above it compress; see BOT_LOD_CAP)
	S.setup(seed_value, save, now, opts)
	var t: float = 0.0
	var acc: float = 0.0
	var res: Dictionary = {}
	var rw: Dictionary = {}          # wave -> effective DPS at the wave's start
	var whp: Dictionary = {}         # wave -> HP spawned in it (bosses, elites, tier multipliers)
	var wboss: Dictionary = {}       # wave -> boss HP spawned in it
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
				if String(S.en.kind[es]) == "boss":
					wboss[S.wave] = float(wboss.get(S.wave, 0.0)) + float(S.en.max_hp[es])
			k -= 1
		if ne > 0:
			last_eid = maxi(last_eid, int(S.en.eid[eo[ne - 1]]))
		if acc >= 0.5:
			acc = 0.0
			ev.append_array(bot_step(S, policy, perk_pref))
			if OS.get_environment("DBG2") != "" and int(t * 10.0) % 250 == 0:
				print("   camp t=%.0f wave %d alive %d ms %d" % [t, S.wave, S.en.count(), Time.get_ticks_msec()])
		if feed_missions:
			Missions.on_run_events(save, ev)
		for x in ev:
			var e: Dictionary = x
			if String(e.get("t", "")) == "game_over":
				res = e
	var coins: int = int(res.get("coins", int(S.coins_run)))
	# POWER_MODEL §2.3 / §9 probes. R(w) = effective DPS (PowerModel over the
	# engine's power_snapshot) / the HP the engine actually spawned per second
	# of wave w (PM-1's "measured spawn HP/s": composition, elites + shields,
	# bosses and tier multipliers included). Frontier = the death wave with the
	# build the run died with; early = w*/2 with the build of that moment; wall
	# = the frontier requirement grown to w*+5 by PowerModel's D(w) curve.
	# On a boss wave the boss's share of the HP is matched with single-target
	# DPS (AoE / multi-target factors do not apply to one target).
	var snap: Dictionary = S.power_snapshot()
	var wave_s: float = TuneRef.num("wave_time", 25.0)
	var hp_w: float = maxf(0.001, float(whp.get(S.wave, 0.0)))
	var b_sh: float = clampf(float(wboss.get(S.wave, 0.0)) / hp_w, 0.0, 1.0)
	var dps: float = PowerModel.effective_dps(snap) * (1.0 - b_sh) + PowerModel.single_target_dps(snap) * b_sh
	var front: float = dps / (hp_w / clampf(float(wt.get(S.wave, wave_s)), wave_s / 3.0, wave_s))
	var we: int = maxi(1, S.wave / 2)
	var early: float = float(rw.get(we, 0.0)) / maxf(0.001, float(whp.get(we, 0.0)) / wave_s)
	var wall: float = front * PowerModel.required_dps(S.wave, S.tier) / maxf(0.001, PowerModel.required_dps(S.wave + 5, S.tier))
	return {"wave": S.wave, "tier": S.tier, "coins": coins, "real_s": t, "gems": 0, "perks": S.perks_taken.duplicate(), "mode": S.mode, "mutations": S.mutations_taken.size(),
		"r_front": front, "r_early": early, "r_wall": wall,
		"r_hp": PowerModel.hp_ratio(snap, S.wave, S.tier), "timeout": not S.over, "boss_dps": PowerModel.single_target_dps(snap) * float(S.stats.get("boss_mult", 1.0))}


static func _labs_spend(save: Dictionary, now: int, frac: float = 0.5) -> void:
	var lguard: int = 0
	while Labs.running(save).size() < Labs.slots(save) and lguard < 200:
		lguard += 1
		var best: String = ""
		var best_sc: float = INF
		for idv in LAB_PRIO:
			var id: String = idv
			if Labs.is_running(save, id) or Labs.level(save, id) >= LabDB.max_of(id):
				continue
			var sc: float = float(Labs.cost(id, Labs.level(save, id))) * float(LAB_W[id])
			if sc < best_sc:
				best_sc = sc
				best = id
		if best == "" or float(Labs.cost(best, Labs.level(save, best))) > frac * float(save["coins"]):
			break
		Labs.start(save, best, now)


## Start-of-session chores, in the order a player meets them on the Base screen.
static func session_open(save: Dictionary, now: int, rng: RandomNumberGenerator, led: Dictionary, policy: String = "balanced") -> void:
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
	_labs_spend(save, now)
	outpost_spend(save, now)     # cheapest ROI first: Mills pay back in hours
	spend_meta(save, policy, rng)
	_labs_spend(save, now, 1.0)   # base saturated: the rest goes to research
	var steps: Array = Labs.speed_steps(save)
	BaseMeta.set_speed(save, float(steps[steps.size() - 1]))


## A competent player chases the "take tradeoff perks" daily while it is open.
static func _mission_perk(save: Dictionary) -> String:
	for x in Missions.list(save):
		var e: Dictionary = x
		if String(e["tpl"]) == "perk" and not bool(e["claimed"]) and not Missions.is_done(e):
			return "tradeoff"
	return ""


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


static func campaign_days(seed0: int, policy: String = "balanced", n_days: int = DAYS) -> Dictionary:
	var save: Dictionary = BaseMeta.default_save()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0 + 7
	var led: Dictionary = {"offline_coins": 0, "offline_min": 0, "gross_coins": 0, "run_coins": 0, "run_min": 0.0}
	var rate: Dictionary = {}          # tier -> latest coins / real minute
	var days: Array = []
	var snaps: Dictionary = {}
	var run_idx: int = 0
	var t2_day: int = -1
	var t3_day: int = -1
	var first_s: float = -1.0
	var goal_run: int = -1
	var goal_s: float = -1.0
	for d in n_days:
		for h in SESSION_H:
			var now: int = maxi(NOW0 + d * 86400 + int(h) * 3600, int(save["last_seen"]) + 60)
			session_open(save, now, rng, led, policy)
			var t: int = pick_tier(save, rate, run_idx)
			BaseMeta.select_tier(save, t)
			var r: Dictionary = camp_run(save, policy, seed0 + 1000 + run_idx * 131, now, _mission_perk(save))
			if OS.get_environment("PT_RUNS") != "":
				print("  run %d T%d wave %d game_s %.0f coins %d wall_ms %d" % [run_idx, t, int(r["wave"]), float(r["real_s"]), int(r["coins"]), Time.get_ticks_msec()])
			if run_idx == 0:
				first_s = float(r["real_s"])   # fresh save: game speed 1x
			if goal_run < 0 and t == 1 and int(r["wave"]) > TowerState.RUN_GOAL_WAVE:
				goal_run = run_idx + 1   # MASS_HORDE H7: first run that held the wave-20 goal
				goal_s = float(r["real_s"])
			run_idx += 1
			var mins: float = maxf(0.1, float(r["real_s"]) / 60.0)
			rate[t] = float(r["coins"]) / mins
			led["run_coins"] = int(led["run_coins"]) + int(r["coins"])
			led["run_min"] = float(led["run_min"]) + mins
			led["gross_coins"] = int(led["gross_coins"]) + int(r["coins"])
			save["last_seen"] = now + int(r["real_s"])
			_claim_missions(save)
		var hi: int = Tiers.highest(save)
		if hi >= 2 and t2_day < 0:
			t2_day = d + 1
		if hi >= 3 and t3_day < 0:
			t3_day = d + 1
		var lab_sum: int = 0
		for id in LabDB.IDS:
			lab_sum += Labs.level(save, String(id))
		var bit: int = Tiers.best_in(save, hi)
		var op_h: float = outpost_coins_h(save)
		var act_h: float = float(rate.get(Tiers.highest(save), rate.get(1, 0.0))) * 60.0
		var row: Dictionary = {
			"outpost_h": snappedf(op_h, 1.0), "outpost_ratio": snappedf(op_h / maxf(1.0, act_h), 0.001), "core_lvl": Cores.level(save),
			"day": d + 1, "tier": hi, "best_wave_hi_tier": bit, "best_wave": int(save["best_wave"]),
			"coins_gross": int(led["gross_coins"]), "bank": int(save["coins"]), "gems": int(save.get("gems", 0)),
			"gems_earned": _gems_total(save), "labs": lab_sum,
			"progress_key": hi * 1000 + bit,
		}
		days.append(row)
		say("CAMPAIGN " + policy + " day %2d: T%d best@T%d w%d best w%d | coins gross %d bank %d | gems %d (earned %d) | labs %d cards %d | core L%d parts %d outpost %d/h (x%.3f)" % [d + 1, hi, hi, bit, row["best_wave"], row["coins_gross"], row["bank"], row["gems"], row["gems_earned"], lab_sum, row["cards"], row["core_lvl"], row["parts"], int(op_h), float(row["outpost_ratio"])])
		if d + 1 == 7 or d + 1 == 20:
			snaps[d + 1] = save.duplicate(true)
	return {"days": days, "save": save, "led": led, "rate": rate, "t2_day": t2_day, "t3_day": t3_day, "snaps": snaps, "first_run_s": first_s, "goal_run": goal_run, "goal_s": goal_s}


## Shard tree priority for the bot (power first, then economy, then speed).
const SHARD_PRIO: Array = ["root_forge", "might", "bulwark_p", "prosperity", "head_start", "outpost_p", "starting_cash", "builder2", "shard_yield", "scrap_p", "crate_luck", "tempo", "banish_plus", "wide_draft", "core_ceiling", "retain"]


## Weighted cost per node (lower = bought first): a walled player puts its
## shards into raw power first, then the economy / speed nodes.
const SHARD_W: Dictionary = {"root_forge": 0.1, "might": 1.0, "bulwark_p": 1.3, "head_start": 1.5, "prosperity": 2.0, "outpost_p": 2.5, "starting_cash": 2.5}


static func spend_shards(save: Dictionary) -> void:
	var guard: int = 0
	while guard < 100:
		guard += 1
		var best: String = ""
		var bc: float = INF
		for id in SHARD_PRIO:
			if Reforge.can_buy(save, String(id)):
				var c: float = float(ReforgeDB.cost(String(id), Reforge.node(save, String(id)))) * float(SHARD_W.get(String(id), 3.0))
				if c < bc:
					bc = c
					best = String(id)
		if best == "" or Reforge.buy(save, best).is_empty():
			break


## A competent player reforges when the shards on offer at least match what
## the tree already holds (REDESIGN_SPEC §3.4 loop table: 12, 15, 28, 50).
static func wants_reforge(save: Dictionary) -> bool:
	return Reforge.can_reforge(save) and Reforge.shards_now(save) >= maxi(TuneRef.int_of("pc_bot_reforge_min", 16), int(save["reforge"]["cum_shards"]))


static func _gems_total(save: Dictionary) -> int:
	var gl: Dictionary = save.get("gem_log", {})
	var n: int = 0
	for k in gl.keys():
		n += int(gl[k])
	return n


## Replays a frozen snapshot with an in-run policy (and optional forced perk).
static func snap_eval(snap: Dictionary, policy: String, seeds: Array, perk_pref: String = "", opts: Dictionary = {}) -> Dictionary:
	var w: float = 0.0
	var c: float = 0.0
	for sv in seeds:
		var s: Dictionary = snap.duplicate(true)
		BaseMeta.select_tier(s, Tiers.highest(s))
		var r: Dictionary = camp_run(s, policy, int(sv), NOW0, perk_pref, false, opts)
		w += float(r["wave"])
		c += float(r["coins"])
	var n: float = float(seeds.size())
	return {"wave": w / n, "coins": c / n}


## ---- legacy campaign jobs (ECONOMY.md §6 / BRIEF AC-38..41, PC_BALANCE) ----
## The 30-day balanced campaign; writes the day-7 / day-20 snapshots for the
## phase-B jobs.
static func job_main(seed0: int, dir: String) -> Dictionary:
	var C: Dictionary = campaign_days(seed0)
	for d in [7, 20]:
		var f := FileAccess.open(dir.path_join("snap%d.bin" % d), FileAccess.WRITE)
		f.store_buffer(var_to_bytes((C["snaps"] as Dictionary)[d]))
		f.close()
	return {"days": C["days"], "led": C["led"], "gem_log": (C["save"] as Dictionary).get("gem_log", {}), "t2_day": C["t2_day"], "t3_day": C["t3_day"], "first_run_s": C["first_run_s"], "goal_run": C["goal_run"], "goal_s": C["goal_s"]}


## AC-38 (strategy level): a week of pure-weapon / pure-eco play from the same fresh save.
static func job_strat(seed0: int) -> Dictionary:
	var wk: int = 7
	var out: Dictionary = {}
	for p in ["weapon", "eco"]:
		var Cp: Dictionary = campaign_days(seed0, String(p), wk)
		var dp: Dictionary = (Cp["days"] as Array)[wk - 1]
		out[p] = {"key": int(dp["progress_key"]), "coins": int(dp["coins_gross"]), "best_wave": int(dp["best_wave"])}
	return out


## AC-38 / AC-40 on an extra seed (the eco-mix margin and early pace are seed-sensitive).
static func job_seed(seed0: int, xs: int) -> Dictionary:
	var wk: int = 7
	var sd: int = seed0 + xs
	var Cb: Dictionary = campaign_days(sd, "balanced", wk)
	var Cw: Dictionary = campaign_days(sd, "weapon", wk)
	var db: Dictionary = (Cb["days"] as Array)[wk - 1]
	var dw: Dictionary = (Cw["days"] as Array)[wk - 1]
	var d1: int = int(((Cb["days"] as Array)[0] as Dictionary)["best_wave"])
	var row: Dictionary = {"bal_wave": int(db["best_wave"]), "wpn_wave": int(dw["best_wave"]), "bal_coins": int(db["coins_gross"]), "wpn_coins": int(dw["coins_gross"]), "t2_day": int(Cb["t2_day"]), "day1": d1}
	row["ok"] = int(row["bal_wave"]) > int(row["wpn_wave"]) and int(row["t2_day"]) >= 3 and int(row["t2_day"]) <= 5 and d1 >= 18 and d1 <= 32
	return {"sd": sd, "row": row}




## AC-39 same-save mono boards (report) + in-run policy on the same frozen save (report).
static func job_mono(seed0: int, snaps: Dictionary) -> Dictionary:
	var mono: Dictionary = {}
	var mono_ok: bool = true
	var mseeds: Array = [seed0 + 11, seed0 + 23]
	for mday in [7, 20]:
		var msnap: Dictionary = snaps[mday]
		var mb: float = float(snap_eval(msnap, "balanced", mseeds)["wave"])
		var row: Dictionary = {"balanced": snappedf(mb, 0.1)}
		for mid in ["gun", "mortar", "tesla"]:
			var ms: Dictionary = msnap.duplicate(true)
			var sl: Dictionary = ms["slots"]
			for k in sl.keys():
				(sl[k] as Dictionary)["id"] = String(mid)
			var mw: float = float(snap_eval(ms, "mono:" + String(mid), mseeds)["wave"])
			row[mid] = snappedf(mw, 0.1)
			if mw >= 0.70 * mb:
				mono_ok = false   # report only (same-save probe); gate is the fresh-save AC-39
		mono["d%d" % mday] = row
	say("AC-39 mono boards (same save): " + JSON.stringify(mono))
	var seeds: Array = [seed0 + 11, seed0 + 23, seed0 + 37]
	var pol: Dictionary = {}
	for day in [7, 20]:
		var snap: Dictionary = snaps[day]
		for p in ["balanced", "weapon", "eco"]:
			pol["d%d_%s" % [day, p]] = snap_eval(snap, String(p), seeds)
		say("IN-RUN POLICY day %d (same save): balanced %s | weapon %s | eco %s" % [day, JSON.stringify(pol["d%d_balanced" % day]), JSON.stringify(pol["d%d_weapon" % day]), JSON.stringify(pol["d%d_eco" % day])])
	return {"mono": mono, "mono_ok": mono_ok, "pol": pol}


## I-4: no dominant perk — always-take-X policies on the day-20 save. A perk
## dominates when it out-earns the median by > 20% WITHOUT costing waves.
static func job_perks(seed0: int, snaps: Dictionary) -> Dictionary:
	var snap20: Dictionary = snaps[20]
	var perk_rows: Dictionary = {}
	var cv: Array = []
	var wv: Array = []
	for pid in PerkDB.IDS:
		var r: Dictionary = snap_eval(snap20, "balanced", [seed0 + 11, seed0 + 23], String(pid))
		perk_rows[pid] = {"wave": snappedf(float(r["wave"]), 0.1), "coins": int(r["coins"])}
		cv.append(float(r["coins"]))
		wv.append(float(r["wave"]))
	cv.sort()
	wv.sort()
	var c_med: float = (float(cv[5]) + float(cv[6])) / 2.0
	var w_med: float = (float(wv[5]) + float(wv[6])) / 2.0
	var dominant: Array = []
	var top_ratio: float = 0.0
	for pid in perk_rows.keys():
		var pr: Dictionary = perk_rows[pid]
		var ratio: float = float(pr["coins"]) / maxf(1.0, c_med)
		top_ratio = maxf(top_ratio, ratio)
		if ratio > 1.2 and float(pr["wave"]) >= w_med:
			dominant.append(pid)
	say("PERKS day 20 (always-take-X): " + JSON.stringify(perk_rows))
	return {"rows": perk_rows, "dominant": dominant, "top_ratio": top_ratio}


## PC-E14 refinery probe, PC-E16 modifiers / fairness, endless.
static func job_mods(seed0: int, snaps: Dictionary) -> Dictionary:
	var seeds: Array = [seed0 + 11, seed0 + 23, seed0 + 37]
	var snap20: Dictionary = snaps[20]
	# PC-E14: a Refinery + Mine economy must not out-earn the same board without
	# Refineries by > 15%. Same frozen day-7 / day-20 save; the probe turns every
	# other permanent Mine into a Refinery (so each sits next to a Mine: S11
	# Smelter), and both boards are played by the same eco-leaning in-run policy.
	var refin: Dictionary = {}
	var refin_ok: bool = true
	for rday in [7, 20]:
		var rsnap: Dictionary = snaps[rday]
		var rp: Dictionary = rsnap.duplicate(true)
		var nmine: int = 0
		var rsl: Dictionary = rp["slots"]
		for k in rsl.keys():
			var re: Dictionary = rsl[k]
			if String(re["id"]) == "mine":
				if nmine % 2 == 0:
					re["id"] = "refinery"
				nmine += 1
		var rb: Dictionary = snap_eval(rsnap, "refinery", seeds)
		var rr: Dictionary = snap_eval(rp, "refinery", seeds)
		var ratio: float = float(rr["coins"]) / maxf(1.0, float(rb["coins"]))
		refin["d%d" % rday] = {"with_refinery": rr, "without": rb, "coin_ratio": snappedf(ratio, 0.001)}
		if ratio > 1.15:
			refin_ok = false
	say("PC REFINERY vs balanced: " + JSON.stringify(refin))
	# PC-E16 (subset): every challenge modifier stays winnable to wave 25 on the
	# day-20 save, and an endless run plays past its first mutation.
	# PC_BALANCE fairness: each modifier's coin reward tracks its measured cost
	# (same save, same seeds vs no modifier): net coins 0.9-1.4x, and a modifier
	# that costs <= 1.5 waves may not pay > 1.25x (no free coins).
	var mod_rows: Dictionary = {}
	var mods_ok: bool = true
	var fair_ok: bool = true
	var modseeds: Array = [seed0 + 11, seed0 + 58]
	var mbase: Dictionary = snap_eval(snap20, "balanced", modseeds)
	mod_rows["_base"] = {"wave": snappedf(float(mbase["wave"]), 0.1), "coins": roundi(float(mbase["coins"]))}
	for mid in ModifierDB.IDS:
		var mr: Dictionary = snap_eval(snap20, "balanced", modseeds, "", {"modifiers": [mid]})
		var cr: float = float(mr["coins"]) / maxf(1.0, float(mbase["coins"]))
		var dw: float = float(mr["wave"]) - float(mbase["wave"])
		mod_rows[mid] = {"wave": snappedf(float(mr["wave"]), 0.1), "dwave": snappedf(dw, 0.1), "coin_ratio": snappedf(cr, 0.01)}
		mods_ok = mods_ok and float(mr["wave"]) >= 25.0
		fair_ok = fair_ok and cr >= 0.9 and cr <= 1.4 and not (dw >= -1.5 and cr > 1.25)
	say("PC MODIFIERS day 20: " + JSON.stringify(mod_rows))
	var esnap: Dictionary = snap20.duplicate(true)
	var endless_ok: bool = BaseMeta.endless_unlocked(esnap)
	var er: Dictionary = {}
	if endless_ok:
		BaseMeta.select_tier(esnap, Tiers.highest(esnap))
		er = camp_run(esnap, "balanced", seed0 + 11, NOW0, "", false, {"mode": "endless"})
		endless_ok = String(er["mode"]) == "endless" and int(er["wave"]) > ModifierDB.MUTATION_EVERY and int(er["mutations"]) >= 1
		# endless pays roughly a normal run (0.8-1.15x the same-seed baseline):
		# a real alternative, not a replacement for tier progression.
		var eb: Dictionary = snap_eval(snap20, "balanced", [seed0 + 11])
		er["coin_ratio"] = snappedf(float(er["coins"]) / maxf(1.0, float(eb["coins"])), 0.01)
		endless_ok = endless_ok and float(er["coin_ratio"]) >= 0.8 and float(er["coin_ratio"]) <= 1.15
	say("PC ENDLESS day 20: " + JSON.stringify(er))
	return {"refin": refin, "refin_ok": refin_ok, "mod_rows": mod_rows, "mods_ok": mods_ok, "fair_ok": fair_ok, "er": er, "endless_ok": endless_ok}


## Merge every job into the METRICS dict (legacy keys unchanged) + the
## redesign campaign gates (RD_GATES).
static func combine(R: Dictionary) -> Dictionary:
	var m: Dictionary = (R.get("pol", {}) as Dictionary).duplicate(true)
	var M: Dictionary = R.get("main", {})
	if M.is_empty():
		return m
	var days: Array = M["days"]
	var led: Dictionary = M["led"]
	var keys: Array = []
	for r in days:
		keys.append(int((r as Dictionary)["progress_key"]))
	var t3: int = int(M["t3_day"])
	# I-7: no 5-day window without a gain in (tier, best wave in highest tier) until T3
	var stall_days: Array = []
	var stop: int = t3 if t3 > 0 else DAYS
	for d in range(5, stop):
		if int(keys[d]) <= int(keys[d - 5]):
			stall_days.append(d + 1)
	# Post-T3 (fix round): the late game keeps climbing — no 5-day stall from
	# T3 to day 30, and the best wave climbs >= 8 past the T3 day.
	var late_stall: Array = []
	if t3 > 0:
		for d in range(maxi(5, t3 + 4), DAYS):
			if int(keys[d]) <= int(keys[d - 5]):
				late_stall.append(d + 1)
	var bw_t3: int = int((days[t3 - 1] as Dictionary)["best_wave"]) if t3 > 0 else 0
	var bw_30: int = int((days[DAYS - 1] as Dictionary)["best_wave"])
	var late_ok: bool = t3 > 0 and late_stall.is_empty() and bw_30 >= bw_t3 + 8
	# AC-40: in week 1 every 3-day window shows a gain
	var early: bool = true
	for d in range(3, mini(7, DAYS)):
		if int(keys[d]) <= int(keys[d - 3]):
			early = false
	# AC-41 / I-10: gems
	var gl: Dictionary = M["gem_log"]
	var gtot: int = 0
	var gmax: int = 0
	var gsrc: String = ""
	for k in gl.keys():
		gtot += int(gl[k])
		if int(gl[k]) > gmax:
			gmax = int(gl[k])
			gsrc = String(k)
	var gpd: float = float(gtot) / float(DAYS)
	# I-6: offline vs active coins/min
	var active_rate: float = float(led["run_coins"]) / maxf(0.1, float(led["run_min"]))
	var off_rate: float = float(led["offline_coins"]) / maxf(1.0, float(led["offline_min"]))
	var wk: int = 7
	var bal7: Dictionary = days[wk - 1]
	var strat: Dictionary = {"balanced": {"key": int(bal7["progress_key"]), "coins": int(bal7["coins_gross"]), "best_wave": int(bal7["best_wave"])}}
	var ST: Dictionary = R.get("strat", {})
	for p in ["weapon", "eco"]:
		strat[p] = ST.get(p, {"key": 0, "coins": 0, "best_wave": 0})
	var sb: Dictionary = strat["balanced"]
	var sw: Dictionary = strat["weapon"]
	var se: Dictionary = strat["eco"]
	say("STRATEGY week 1: balanced %s | weapon %s | eco %s" % [JSON.stringify(sb), JSON.stringify(sw), JSON.stringify(se)])
	var mix_w: bool = int(sb["key"]) >= int(sw["key"]) and int(sb["coins"]) > int(sw["coins"])
	var mix_e: bool = int(sb["key"]) > int(se["key"]) and int(sb["coins"]) > int(se["coins"])
	# AC-38 (adapted to REDESIGN_BRIEF AC-30 / G1): the mixed policy reaches a
	# strictly higher frontier than both zero-eco and all-eco. (Was: >= 1.10x
	# the weapon wave and >= 1.25x its coins; coins now follow waves only, and
	# the redesign wants viable specs, not an eco premium — PM-10.)
	var ac38: bool = int(sb["best_wave"]) > int(sw["best_wave"]) and int(sb["best_wave"]) > int(se["best_wave"])
	var seed_rows: Dictionary = {}
	var seeds_ok: bool = true
	for k in EXTRA_SEEDS.size():
		var sr: Dictionary = R.get("seed:%d" % k, {})
		if sr.is_empty():
			seeds_ok = false
			continue
		seed_rows[str(int(sr["sd"]))] = sr["row"]
		seeds_ok = seeds_ok and bool((sr["row"] as Dictionary)["ok"])
	say("SEEDS week 1: " + JSON.stringify(seed_rows))
	var MO: Dictionary = R.get("mono", {})
	var PK: Dictionary = R.get("perks", {})
	var MD: Dictionary = R.get("mods", {})
	var per_day: Array = []
	for r in days:
		var rd: Dictionary = r
		per_day.append({"day": rd["day"], "tier": rd["tier"], "best_wave_hi_tier": rd["best_wave_hi_tier"], "best_wave": rd["best_wave"], "coins": rd["coins_gross"], "gems": rd["gems_earned"], "labs": rd["labs"], "cards": rd["cards"], "core_lvl": rd["core_lvl"], "parts": rd["parts"], "outpost_h": rd["outpost_h"], "outpost_ratio": rd["outpost_ratio"]})
	var day1: int = int((days[0] as Dictionary)["best_wave"])
	var last: Dictionary = days[DAYS - 1]
	m.merge({
		"campaign_days": per_day, "t2_day": M["t2_day"], "t3_day": t3, "final_tier": int(last["tier"]),
		"day1_best_wave": day1, "day1_in_target_band": day1 >= 18 and day1 <= 32,
		"day30_best_wave_hi_tier": int(last["best_wave_hi_tier"]), "stall_days": stall_days,
		"gems_total": gtot, "gems_per_day": snappedf(gpd, 0.1), "gem_log": gl, "gem_top_source": gsrc,
		"active_coin_rate": snappedf(active_rate, 0.1), "offline_coin_rate": snappedf(off_rate, 0.1),
		"strategy_week1": strat, "ac38_strict": ac38, "inrun_policy": MO.get("pol", {}),
		"perks_d20": PK.get("rows", {}), "perk_top_coin_ratio": snappedf(float(PK.get("top_ratio", 0.0)), 0.01), "dominant_perks": PK.get("dominant", []),
		"t2_by_day5": int(M["t2_day"]) >= 3 and int(M["t2_day"]) <= 5,
		"day1_band": day1 >= 18 and day1 <= 32,
		# FEEDBACK-1 (new gate): a brand-new player's first run is short
		# (5-8 real minutes at 1x) so they reach the meta features sooner.
		"first_run_s": snappedf(float(M.get("first_run_s", -1.0)), 0.1),
		# MASS_HORDE (re-aimed, same band): the owner's 5-8 min first run is
		# checked on the MEDIAN of the FRESH_N fresh first runs (fresh_checks),
		# not one seed: with 100s of bodies a single run's wall varies +-5 waves.
		"first_run_short_single": float(M.get("first_run_s", -1.0)) >= 300.0 and float(M.get("first_run_s", -1.0)) <= 480.0,
		"tier3_by_day30": t3 > 0,
		"no_plateau_before_t3": stall_days.is_empty(),
		"early_3day_rise": early,
		# FEEDBACK-1 (deliberate gate change): gems / premium currency are
		# removed, so the AC-41 gem-income bands become "no gem is ever earned".
		"gems_per_day_ok": gtot == 0 and gpd == 0.0,
		"gem_sources_ok": gmax == 0,
		"offline_below_active": off_rate <= 0.2 * active_rate,
		"mix_beats_weapon": mix_w, "mix_beats_eco": mix_e,
		"no_dominant_perk": PK.has("dominant") and (PK["dominant"] as Array).is_empty(),
		"ac38_eco_mix": ac38, "mono_same_save": MO.get("mono", {}), "mono_same_save_below_70": bool(MO.get("mono_ok", false)),
		"late_stall_days": late_stall, "best_wave_at_t3": bw_t3, "no_plateau_after_t3": late_ok,
		"seed_runs": seed_rows, "seeds_ok": seeds_ok,
		"pc_refinery": MD.get("refin", {}), "pc_refinery_not_dominant": bool(MD.get("refin_ok", false)),
		"pc_modifiers_d20": MD.get("mod_rows", {}), "pc_modifiers_reach_w25": bool(MD.get("mods_ok", false)), "pc_modifiers_fair": bool(MD.get("fair_ok", false)),
		"pc_endless_d20": MD.get("er", {}), "pc_endless_runs": bool(MD.get("endless_ok", false)),
	})
	m.merge(fresh_checks(R.get("fresh", {})))
	m.merge(mass_checks(R.get("mass", {}), M))
	return m


## MASS_HORDE §D8 gates from the "mass" job (+ H7 from the main campaign).
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
		"fresh_median_first_goal": w.size() >= 16 and mw >= float(FIRST_GOAL_WAVE) and int(w.min()) >= FIRST_GOAL_WAVE,
		"fresh_median_s": snappedf(tm, 0.1),
		"first_run_short": tm >= 300.0 and tm <= 480.0,   # owner FB2: short first runs ~5-8 min (median of the fresh first runs)
	}


# ======================================================================
# REDESIGN CAMPAIGN (POWER_MODEL §9, REDESIGN_SPEC §3.4, REDESIGN_BALANCE.md)
# One fresh save per archetype spec, played session by session (4 runs a
# day on the SESSION_H clock) through FORGE_LOOPS Core Reforges. The bot is
# the competent player for its spec: Outpost first (OP_PLAN), Core levels,
# crates (token / Keys / Field), installs + levels the parts its spec values,
# drafts / casts specials / buys cash tracks with the spec's in-run policy,
# spends shards (SHARD_PRIO) and reforges when its spec says (SPEC_REFORGE)
# — never before it has regained the previous best. Measured per day: the
# boss-aware frontier power ratio at the death wave, the early (w*/2) and wall
# ratios, Outpost/active coin share, gems, loadouts; per loop: sessions to
# regain the previous best.
# ======================================================================




static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	var n: int = b.size()
	return float(b[n / 2]) if n % 2 == 1 else (float(b[n / 2 - 1]) + float(b[n / 2])) / 2.0


static var FORGE_DUMP: String = ""     # debug: write the state right after the first Reforge
static var FORGE_RESUME: String = ""   # debug: continue from such a state



