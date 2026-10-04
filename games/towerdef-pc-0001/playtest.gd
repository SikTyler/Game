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
# Prints per-run lines + "PLAYTEST METRICS {json}" + exactly "PLAYTEST OK" (exit 0)
# or "PLAYTEST FAIL: ..." (exit 1). Clears user:// saves at start and end.

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const TuneRef := preload("res://Tune.gd")
const PerkDB := preload("res://data/PerkDB.gd")

const DT: float = 0.1
const MAX_SIM_S: float = 3600.0
const RUNS: int = 8
const FIRST_GOAL_WAVE: int = 5
const PROGRESS_GAIN: int = 5
const SEED_DEFAULT: int = 4242
const OC_VALUE: float = 6.0
const MIX_ECO_UNTIL: int = 15

var fail_count: int = 0
const GATES: Array = ["solvent", "first_goal_reachable", "progressable", "no_death_spiral", "no_trivial_dominant",
	"t2_by_day5", "tier3_by_day30", "no_plateau_before_t3", "early_3day_rise",
	"gems_per_day_ok", "gem_sources_ok", "offline_below_active", "mix_beats_weapon", "mix_beats_eco", "no_dominant_perk",
	"ac38_eco_mix", "ac39_no_mono", "day1_band", "no_plateau_after_t3", "seeds_ok",
	"pc_refinery_not_dominant", "pc_modifiers_reach_w25", "pc_modifiers_fair", "pc_endless_runs"]
const EXTRA_SEEDS: Array = [5151, 6262]   # AC-38/AC-40 re-checked on more seeds (thin margins)


func _initialize() -> void:
	MetaSave.clear()
	var seed0: int = TuneRef.seed_of(SEED_DEFAULT)
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
	# AC-39: from a fresh save, a mono-building board reaches < 70% of balanced.
	var mono8: Dictionary = {}
	var mono8_ok: bool = true
	for mid in ["gun", "mortar", "tesla"]:
		var mb8: int = int((camp["mono:" + mid]["waves"] as Array).max())
		mono8[mid] = mb8
		if float(mb8) >= 0.70 * float(bal_best):
			mono8_ok = false
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
		"mono_best": mono8, "ac39_no_mono": mono8_ok,
	}
	m.merge(campaign_checks(seed0))
	print("PLAYTEST METRICS " + JSON.stringify(m))
	for key in GATES:
		if not bool(m[key]):
			fail_count += 1
			print("PLAYTEST FAIL: " + key)
	MetaSave.clear()
	if fail_count == 0:
		print("PLAYTEST OK")
		quit(0)
	else:
		quit(1)


static func campaign(policy: String, seed0: int) -> Dictionary:
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
	if policy.begins_with("mono:"):
		# AC-39 probe: one building id everywhere (plus the core).
		return 3 if id == policy.substr(5) else 0
	match policy:
		"eco":
			return 3 if cat == "eco" else (1 if cat == "support" else 0)
		"refinery":
			# PC-E14 probe: Refinery + Mine economy (Smelter), weapons only as glue.
			return 3 if id == "refinery" or id == "mine" else (2 if cat == "weapon" else 0)
		"weapon":
			return 3 if cat == "weapon" else (1 if cat == "support" else 0)
	# balanced: keep weapons slightly ahead of eco, support as glue
	if cat == "weapon":
		return 3 if weapons <= ecos + 1 else 1
	if cat == "eco":
		return 3 if ecos < weapons else 1
	return 2


## The competent eco-mix draft: weapon feeders (Bounty / Oil Mill, S6/S7) are
## the best +1s; Mines only while their cash still has time to compound
## (early waves); otherwise weapons.
static func _mix_draft_score(S, id: String, kind: String) -> int:
	var cat: String = BuildingDB.cat_of(id)
	var cnt: Vector2i = _counts(S)
	var sc: int = 2
	if cnt.x < 3:
		sc = 7 if cat == "weapon" else 1   # nothing to feed yet: guns first
	elif id == "bounty" or id == "oilmill":
		sc = 6
	elif id == "mine" or id == "vault":
		sc = 5 if S.wave < MIX_ECO_UNTIL and cnt.x > cnt.y else 1
	elif cat == "weapon":
		sc = 4
	elif cat == "support":
		sc = 3
	return sc * 2 + (1 if kind == "new" else 0)


static func _counts(S) -> Vector2i:
	var w: int = 0
	var e: int = 0
	for i in TowerState.N:
		var c: String = BuildingDB.cat_of(S.id_at(i))
		if c == "weapon":
			w += 1
		elif c == "eco":
			e += 1
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


## Competent in-run policy; also used as a library by selftest.
static func bot_step(S, policy: String, perk_pref: String = "") -> Array:
	var ev: Array = []
	if S.mutation_offer.size() > 0:
		ev.append_array(S.choose_mutation(_pick_mutation(S)))
	# PC lanes: keep the Beacon focus on the busiest active lane.
	if S.active_quads.size() > 0 and not S.active_quads.has(S.focus_quad):
		ev.append_array(S.set_focus(int(S.active_quads[0])))
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
		var cnt: Vector2i = _counts(S)
		var best: int = 0
		var best_score: int = -99
		for k in S.draft.size():
			var c: Dictionary = S.draft[k]
			var sc: int = _prefers(policy, String(c["id"]), cnt.x, cnt.y) * 2 + (1 if String(c["kind"]) == "new" else 0)
			if policy == "balanced":
				sc = _mix_draft_score(S, String(c["id"]), String(c["kind"]))
			if sc > best_score:
				best_score = sc
				best = k
		ev.append_array(S.choose_card(best))
	if S.pending_place != "":
		var cell: int = _place_cell(S, S.pending_place)
		if cell >= 0:
			ev.append_array(S.place(cell))
		elif S.free_slots().is_empty() or S.at_cap():
			ev.append_array(S.cancel_place())   # nowhere legal: skip the card
	# Spend cash: cheapest preferred upgrade (core counts as a weapon).
	var target: int = -1
	var cost: int = 1 << 30
	for i in TowerState.N:
		var id: String = S.id_at(i)
		if i != TowerState.CORE_SLOT and (id == "" or S.lvl_at(i) >= TowerState.lvl_cap()):
			continue
		var pref: int = 3 if i == TowerState.CORE_SLOT and policy != "eco" else (_prefers(policy, id, 0, 0) if id != "" else 1)
		if pref < 2:
			continue
		var c2: int = S.upgrade_cost(i)
		# Core Overcharge compounds every weapon, so a competent player values a
		# core level like OC_VALUE building levels.
		if i == TowerState.CORE_SLOT:
			c2 = int(float(c2) / OC_VALUE)
		if c2 < cost:
			cost = c2
			target = i
	if target >= 0 and S.cash >= float(S.upgrade_cost(target)):
		ev.append_array(S.upgrade(target))
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


## Placement on the 7x7: weapons (Railgun needs ring 2+) as close to the core
## as allowed so they cover every lane; eco / support fill the rest inner-first.
static func _place_cell(S, id: String) -> int:
	var best: int = -1
	var best_r: int = 99
	for i in S.free_slots():
		if not S.can_place(int(i), id):
			continue
		var r: int = TowerState.ring_of(int(i))
		if r < best_r:
			best_r = r
			best = int(i)
	return best


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
	while guard < 200:
		guard += 1
		var w: int = 0
		var e: int = 0
		var free: int = -1
		var cheapest: int = -1
		var cheapest_cost: int = 1 << 30
		for i in TowerState.N:
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
			if uc < cheapest_cost and int(s["lvl"]) < BaseMeta.perm_lvl_cap(save):
				cheapest_cost = uc
				cheapest = i
		var did: bool = false
		if free >= 0 and BaseMeta.building_count(save) < BaseMeta.build_cap(save):
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
			if int(core[stat]) < BaseMeta.core_cap(save) and BaseMeta.core_cost(int(core[stat])) <= cheapest_cost:
				did = BaseMeta.try_core(save, stat)
			if not did and cheapest >= 0:
				did = BaseMeta.try_upgrade(save, cheapest)
		# 7x7 ring unlocks: a free cell when the board needs room, otherwise land
		# development (BaseMeta.land_bonus) once everything else is saturated.
		if not did and (free < 0 or BaseMeta.building_count(save) >= BaseMeta.build_cap(save)):
			var ucell: int = -1
			var ucost: int = 1 << 30
			for i in TowerState.N:
				if not BaseMeta.is_unlocked(save, i) and i != TowerState.CORE_SLOT and BaseMeta.ring_open(save, i):
					var cc: int = BaseMeta.unlock_cost(save, i)
					if cc < ucost:
						ucost = cc
						ucell = i
			if ucell >= 0:
				did = BaseMeta.try_unlock(save, ucell)
		if not did:
			break


# ======================================================================
# CAMPAIGN SIM — ~30 simulated days of the full retention loop with an
# injected clock: login streak, missions, offline earnings, labs (real-time
# research that completes between sessions), cards (chests/equip/slots),
# perks, permanent base spending and tier selection. The balanced bot plays
# every run; policy / perk comparisons replay a frozen snapshot save.
# ======================================================================
const Labs := preload("res://Labs.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const Offline := preload("res://Offline.gd")
const Tiers := preload("res://Tiers.gd")
const LabDB := preload("res://data/LabDB.gd")
const ModifierDB := preload("res://data/ModifierDB.gd")

const DAYS: int = 30
const SESSION_H: Array = [8, 8, 16, 16]        # 2 sessions x 2 runs; 8 h / 16 h offline gaps (AC-40)
const NOW0: int = 1767225600                   # 2026-01-01 00:00 UTC (a day boundary)
const LAB_PRIO: Array = ["dmg", "hp", "coin", "speed", "startcash", "labspeed", "xp", "offrate", "offcap", "reroll"]
const LAB_W: Dictionary = {"dmg": 1.0, "hp": 1.0, "coin": 1.0, "speed": 0.6, "startcash": 1.6, "labspeed": 1.4, "xp": 1.8, "offrate": 2.0, "offcap": 2.0, "reroll": 2.5}
const CARD_PRIO: Array = ["c_dmg", "c_hp", "c_wind", "c_coin", "c_cash", "c_xp", "c_skip", "c_reroll"]


## One run on `save` (mutated: banks, missions). Returns run facts.
static func camp_run(save: Dictionary, policy: String, seed_value: int, now: int, perk_pref: String = "", feed_missions: bool = true, opts: Dictionary = {}) -> Dictionary:
	var S = TowerState.new()
	S.setup(seed_value, save, now, opts)
	var t: float = 0.0
	var acc: float = 0.0
	var res: Dictionary = {}
	while not S.over and t < MAX_SIM_S:
		var ev: Array = S.tick(DT)
		t += DT
		acc += DT
		if acc >= 0.5:
			acc = 0.0
			ev.append_array(bot_step(S, policy, perk_pref))
		if feed_missions:
			Missions.on_run_events(save, ev)
		for x in ev:
			var e: Dictionary = x
			if String(e.get("t", "")) == "game_over":
				res = e
	var coins: int = int(res.get("coins", int(S.coins_run)))
	return {"wave": S.wave, "tier": S.tier, "coins": coins, "real_s": t, "gems": S.gems_run, "perks": S.perks_taken.duplicate(), "mode": S.mode, "mutations": S.mutations_taken.size()}


static func _gems_spend(save: Dictionary, rng: RandomNumberGenerator) -> void:
	var guard: int = 0
	while guard < 40:
		guard += 1
		var own: int = Cards.owned(save).size()
		var want: String = "chest"
		if Labs.slots(save) < 3:
			want = "lab"
		elif Cards.slots(save) < 3 and own >= 3:
			want = "card"
		elif own >= 4 and Labs.slots(save) < 4:
			want = "lab"
		elif Cards.slots(save) < 5 and own > Cards.slots(save) + 1:
			want = "card"
		var ev: Array = []
		match want:
			"lab":
				ev = Labs.buy_slot(save)
			"card":
				ev = Cards.buy_slot(save)
			_:
				ev = Cards.open_chest(save, rng)
		if ev.is_empty():
			break
	# equip the best loadout by priority
	for id in Cards.equipped(save).duplicate():
		Cards.unequip(save, String(id))
	for id in CARD_PRIO:
		if Cards.owned(save).has(id):
			Cards.equip(save, String(id))


static func _labs_spend(save: Dictionary, now: int, frac: float = 0.5) -> void:
	while Labs.running(save).size() < Labs.slots(save):
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
	for x in Offline.claim(save, now):
		var oe: Dictionary = x
		led["offline_coins"] = int(led["offline_coins"]) + int(oe["coins"])
		led["offline_min"] = int(led["offline_min"]) + int(oe["minutes"])
	Missions.streak_claim(save, now)
	led["gross_coins"] = int(led["gross_coins"]) + int(save["coins"]) - c0
	_claim_missions(save)
	_gems_spend(save, rng)
	_labs_spend(save, now)
	spend_meta(save, policy)
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
	for d in n_days:
		for h in SESSION_H:
			var now: int = maxi(NOW0 + d * 86400 + int(h) * 3600, int(save["last_seen"]) + 60)
			session_open(save, now, rng, led, policy)
			var t: int = pick_tier(save, rate, run_idx)
			BaseMeta.select_tier(save, t)
			var r: Dictionary = camp_run(save, policy, seed0 + 1000 + run_idx * 131, now, _mission_perk(save))
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
		var row: Dictionary = {
			"day": d + 1, "tier": hi, "best_wave_hi_tier": bit, "best_wave": int(save["best_wave"]),
			"coins_gross": int(led["gross_coins"]), "bank": int(save["coins"]), "gems": int(save["gems"]),
			"gems_earned": _gems_total(save), "labs": lab_sum, "cards": Cards.owned(save).size(),
			"progress_key": hi * 1000 + bit,
		}
		days.append(row)
		print("CAMPAIGN " + policy + " day %2d: T%d best@T%d w%d best w%d | coins gross %d bank %d | gems %d (earned %d) | labs %d cards %d" % [d + 1, hi, hi, bit, row["best_wave"], row["coins_gross"], row["bank"], row["gems"], row["gems_earned"], lab_sum, row["cards"]])
		if d + 1 == 7 or d + 1 == 20:
			snaps[d + 1] = save.duplicate(true)
	return {"days": days, "save": save, "led": led, "rate": rate, "t2_day": t2_day, "t3_day": t3_day, "snaps": snaps}


static func _gems_total(save: Dictionary) -> int:
	var gl: Dictionary = save["gem_log"]
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


## The campaign-level invariants (ECONOMY.md §6 / BRIEF AC-38..41).
func campaign_checks(seed0: int) -> Dictionary:
	var C: Dictionary = campaign_days(seed0)
	var days: Array = C["days"]
	var led: Dictionary = C["led"]
	var save: Dictionary = C["save"]
	var keys: Array = []
	for r in days:
		keys.append(int((r as Dictionary)["progress_key"]))
	var t3: int = int(C["t3_day"])
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
	var gl: Dictionary = save["gem_log"]
	var gtot: int = _gems_total(save)
	var gmax: int = 0
	var gsrc: String = ""
	for k in gl.keys():
		if int(gl[k]) > gmax:
			gmax = int(gl[k])
			gsrc = String(k)
	var gpd: float = float(gtot) / float(DAYS)
	# I-6: offline vs active coins/min
	var active_rate: float = float(led["run_coins"]) / maxf(0.1, float(led["run_min"]))
	var off_rate: float = float(led["offline_coins"]) / maxf(1.0, float(led["offline_min"]))
	# AC-38 (strategy level): a week of pure-weapon / pure-eco play from the same fresh save
	var wk: int = 7
	var bal7: Dictionary = days[wk - 1]
	var strat: Dictionary = {"balanced": {"key": int(bal7["progress_key"]), "coins": int(bal7["coins_gross"]), "best_wave": int(bal7["best_wave"])}}
	for p in ["weapon", "eco"]:
		var Cp: Dictionary = campaign_days(seed0, String(p), wk)
		var dp: Dictionary = (Cp["days"] as Array)[wk - 1]
		strat[p] = {"key": int(dp["progress_key"]), "coins": int(dp["coins_gross"]), "best_wave": int(dp["best_wave"])}
	var sb: Dictionary = strat["balanced"]
	var sw: Dictionary = strat["weapon"]
	var se: Dictionary = strat["eco"]
	print("STRATEGY week 1: balanced %s | weapon %s | eco %s" % [JSON.stringify(sb), JSON.stringify(sw), JSON.stringify(se)])
	var mix_w: bool = int(sb["key"]) >= int(sw["key"]) and int(sb["coins"]) > int(sw["coins"])
	var mix_e: bool = int(sb["key"]) > int(se["key"]) and int(sb["coins"]) > int(se["coins"])
	var ac38: bool = float(sb["best_wave"]) >= 1.10 * float(sw["best_wave"]) and float(sb["coins"]) >= 1.25 * float(sw["coins"])
	# AC-39: a mono-building board reaches < 70% of the balanced best wave. Same
	# frozen day-7 / day-20 save (same coins invested, same slot levels) with every
	# permanent slot rebuilt as one id, played by a bot that only upgrades that id.
	var mono: Dictionary = {}
	var mono_ok: bool = true
	var mseeds: Array = [seed0 + 11, seed0 + 23]
	for mday in [7, 20]:
		var msnap: Dictionary = (C["snaps"] as Dictionary)[mday]
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
	print("AC-39 mono boards (same save): " + JSON.stringify(mono))
	# AC-38 / AC-40 on extra seeds (the eco-mix margin and early pace are seed-sensitive).
	var seed_rows: Dictionary = {}
	var seeds_ok: bool = true
	for xs in EXTRA_SEEDS:
		var sd: int = seed0 + int(xs)
		var Cb: Dictionary = campaign_days(sd, "balanced", wk)
		var Cw: Dictionary = campaign_days(sd, "weapon", wk)
		var db: Dictionary = (Cb["days"] as Array)[wk - 1]
		var dw: Dictionary = (Cw["days"] as Array)[wk - 1]
		var d1: int = int(((Cb["days"] as Array)[0] as Dictionary)["best_wave"])
		var row: Dictionary = {"bal_wave": int(db["best_wave"]), "wpn_wave": int(dw["best_wave"]), "bal_coins": int(db["coins_gross"]), "wpn_coins": int(dw["coins_gross"]), "t2_day": int(Cb["t2_day"]), "day1": d1}
		row["ok"] = float(row["bal_wave"]) >= 1.10 * float(row["wpn_wave"]) and float(row["bal_coins"]) >= 1.25 * float(row["wpn_coins"]) and int(row["t2_day"]) >= 3 and int(row["t2_day"]) <= 5 and d1 >= 18 and d1 <= 32
		seeds_ok = seeds_ok and bool(row["ok"])
		seed_rows[str(sd)] = row
	print("SEEDS week 1: " + JSON.stringify(seed_rows))
	# In-run policy on the SAME frozen save (report): what drafting eco vs weapons does mid-run
	var seeds: Array = [seed0 + 11, seed0 + 23, seed0 + 37]
	var pol: Dictionary = {}
	for day in [7, 20]:
		var snap: Dictionary = (C["snaps"] as Dictionary)[day]
		for p in ["balanced", "weapon", "eco"]:
			pol["d%d_%s" % [day, p]] = snap_eval(snap, String(p), seeds)
		print("IN-RUN POLICY day %d (same save): balanced %s | weapon %s | eco %s" % [day, JSON.stringify(pol["d%d_balanced" % day]), JSON.stringify(pol["d%d_weapon" % day]), JSON.stringify(pol["d%d_eco" % day])])
	# I-4: no dominant perk — always-take-X policies on the day-20 save. A perk
	# dominates when it out-earns the median by > 20% WITHOUT costing waves.
	var snap20: Dictionary = (C["snaps"] as Dictionary)[20]
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
	print("PERKS day 20 (always-take-X): " + JSON.stringify(perk_rows))
	# PC-E14: a Refinery + Mine economy must not out-earn the same board without
	# Refineries by > 15%. Same frozen day-7 / day-20 save; the probe turns every
	# other permanent Mine into a Refinery (so each sits next to a Mine: S11
	# Smelter), and both boards are played by the same eco-leaning in-run policy.
	var refin: Dictionary = {}
	var refin_ok: bool = true
	for rday in [7, 20]:
		var rsnap: Dictionary = (C["snaps"] as Dictionary)[rday]
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
	print("PC REFINERY vs balanced: " + JSON.stringify(refin))
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
	print("PC MODIFIERS day 20: " + JSON.stringify(mod_rows))
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
	print("PC ENDLESS day 20: " + JSON.stringify(er))
	var per_day: Array = []
	for r in days:
		var rd: Dictionary = r
		per_day.append({"day": rd["day"], "tier": rd["tier"], "best_wave_hi_tier": rd["best_wave_hi_tier"], "best_wave": rd["best_wave"], "coins": rd["coins_gross"], "gems": rd["gems_earned"], "labs": rd["labs"], "cards": rd["cards"]})
	var day1: int = int((days[0] as Dictionary)["best_wave"])
	var last: Dictionary = days[DAYS - 1]
	return {
		"campaign_days": per_day, "t2_day": C["t2_day"], "t3_day": t3, "final_tier": int(last["tier"]),
		"day1_best_wave": day1, "day1_in_target_band": day1 >= 18 and day1 <= 32,
		"day30_best_wave_hi_tier": int(last["best_wave_hi_tier"]), "stall_days": stall_days,
		"gems_total": gtot, "gems_per_day": snappedf(gpd, 0.1), "gem_log": gl, "gem_top_source": gsrc,
		"active_coin_rate": snappedf(active_rate, 0.1), "offline_coin_rate": snappedf(off_rate, 0.1),
		"strategy_week1": strat, "ac38_strict": ac38, "inrun_policy": pol,
		"perks_d20": perk_rows, "perk_top_coin_ratio": snappedf(top_ratio, 0.01), "dominant_perks": dominant,
		"t2_by_day5": int(C["t2_day"]) >= 3 and int(C["t2_day"]) <= 5,
		"day1_band": day1 >= 18 and day1 <= 32,
		"tier3_by_day30": t3 > 0,
		"no_plateau_before_t3": stall_days.is_empty(),
		"early_3day_rise": early,
		"gems_per_day_ok": gpd >= 10.0 and gpd <= 30.0,
		"gem_sources_ok": float(gmax) <= 0.5 * float(gtot),
		"offline_below_active": off_rate <= 0.2 * active_rate,
		"mix_beats_weapon": mix_w, "mix_beats_eco": mix_e,
		"no_dominant_perk": dominant.is_empty(),
		"ac38_eco_mix": ac38, "mono_same_save": mono, "mono_same_save_below_70": mono_ok,
		"late_stall_days": late_stall, "best_wave_at_t3": bw_t3, "no_plateau_after_t3": late_ok,
		"seed_runs": seed_rows, "seeds_ok": seeds_ok,
		"pc_refinery": refin, "pc_refinery_not_dominant": refin_ok,
		"pc_modifiers_d20": mod_rows, "pc_modifiers_reach_w25": mods_ok, "pc_modifiers_fair": fair_ok,
		"pc_endless_d20": er, "pc_endless_runs": endless_ok,
	}
