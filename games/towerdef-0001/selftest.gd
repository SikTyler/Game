extends SceneTree
## Corehold rules self-test. Drives TowerState / BaseMeta / Draft directly with
## fixed seeds and asserts what a human would check. Prints "SELFTEST OK" (exit
## 0) or "SELFTEST FAIL: <reason>" (exit 1).
## Run: godot --headless --path games/towerdef-0001/ --script res://selftest.gd

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Draft := preload("res://Draft.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const Tiers := preload("res://Tiers.gd")
const Labs := preload("res://Labs.gd")
const LabDB := preload("res://data/LabDB.gd")
const Offline := preload("res://Offline.gd")
const Missions := preload("res://Missions.gd")
const Cards := preload("res://Cards.gd")
const CardDB := preload("res://data/CardDB.gd")

var fails: Array = []


func _check(name: String, ok: bool) -> void:
	if not ok:
		fails.append(name)
		print("SELFTEST FAIL: " + name)


func _fresh(save: Dictionary = {}) -> RefCounted:
	var S = TowerState.new()
	S.setup(1234, BaseMeta.normalize(save))
	return S


func _initialize() -> void:
	# --- Stage 1: setup ------------------------------------------------------
	var S = _fresh()
	_check("setup: full hp", is_equal_approx(S.hp, 100.0))
	_check("setup: inner ring unlocked, outer locked", bool(S.unlocked[6]) and not bool(S.unlocked[0]) and not bool(S.unlocked[12]))
	_check("setup: 8 free slots", S.free_slots().size() == 8)
	_check("setup: core is the only weapon", (S.stats["weapons"] as Array).size() == 1)

	# --- Stage 2: stats math + adjacency -------------------------------------
	S.slots[7] = {"id": "gun", "perm": 1, "run": 0}
	S.recompute()
	var gun_dmg: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	S.slots[6] = {"id": "armory", "perm": 1, "run": 0}   # adjacent to gun (7) and core (12)
	S.recompute()
	var buffed: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	_check("armory buffs adjacent gun +25%", is_equal_approx(buffed, gun_dmg * 1.25))
	S.slots[0] = {"id": "armory", "perm": 1, "run": 0}   # NOT adjacent to 7
	S.recompute()
	_check("armory does not buff non-adjacent", is_equal_approx(float((S.stats["weapons"] as Array)[0]["dmg"]), buffed))
	S.slots[16] = {"id": "mine", "perm": 2, "run": 0}
	S.slots[17] = {"id": "oilmill", "perm": 1, "run": 0}   # adjacent to mine 16
	S.slots[18] = {"id": "bulwark", "perm": 1, "run": 0}
	S.recompute()
	_check("mine cash/sec", is_equal_approx(float(S.stats["cash_ps"]), 2.4))
	_check("oil mill + adjacent mine xp", is_equal_approx(float(S.stats["xp_mult"]), 1.0 + 0.25 + 0.15))
	_check("bulwark raises max hp", is_equal_approx(float(S.stats["max_hp"]), 140.0))
	_check("bulwark heals by its bonus", is_equal_approx(S.hp, 140.0))

	# --- Stage 3: combat — core kills an enemy, rewards land ------------------
	S = _fresh()
	S.enemies.append({"kind": "drone", "pos": TowerState.CENTER + Vector2(200, 0), "hp": 4.0, "max_hp": 4.0, "spd": 0.0, "dmg": 4.0, "cash": 1.0, "xp": 1.0, "coin": 0.2, "size": 16.0, "atk_cd": 0.0, "slow_t": 0.0})
	S.spawn_t = 999.0
	var ev: Array = S.tick(0.05)
	var kinds: Array = ev.map(func(e): return e["t"])
	_check("core fires a shot", kinds.has("shot"))
	_check("kill event + cash + xp", kinds.has("kill") and S.cash >= 1.0 and S.xp >= 1.0 and S.kills == 1)

	# --- Stage 4: enemy reaches the core and damages it ----------------------
	S = _fresh()
	S.spawn_t = 999.0
	S.stats["weapons"] = []   # disarm to isolate
	S.enemies.append({"kind": "hauler", "pos": TowerState.CENTER + Vector2(140, 0), "hp": 999.0, "max_hp": 999.0, "spd": 28.0, "dmg": 10.0, "cash": 3.0, "xp": 3.0, "coin": 0.6, "size": 26.0, "atk_cd": 0.0, "slow_t": 0.0})
	ev = S.tick(0.1)
	_check("enemy at wall hits core", is_equal_approx(S.hp, 90.0 + 0.05) or S.hp < 100.0)

	# --- Stage 5: waves scale + spawn cap ------------------------------------
	S = _fresh()
	var s1: float = S.scale()
	var i1: float = S.spawn_interval()
	S.wave = 40
	_check("hp scale grows with wave", S.scale() > s1 * 10.0)
	_check("spawn interval shrinks but is capped", S.spawn_interval() < i1 and is_equal_approx(S.spawn_interval(), S.min_spawn))
	S = _fresh()
	S.wave_t = S.wave_time - 0.01
	S.wave = 9
	ev = S.tick(0.05)
	var has_boss: bool = false
	for e in ev:
		if String(e["t"]) == "boss":
			has_boss = true
	_check("wave 10 spawns a boss", S.wave == 10 and has_boss)

	# --- Stage 6: level-up draft → place, plus-card, determinism -------------
	S = _fresh()
	S.xp = S.xp_need()
	S.spawn_t = 999.0
	ev = S.tick(0.01)
	_check("level-up opens 3-card draft", S.level == 2 and S.draft.size() == 3)
	var cats: Array = []
	for c in S.draft:
		cats.append(BuildingDB.cat_of(String(c["id"])))
	_check("draft offers weapon AND eco", cats.has("weapon") and cats.has("eco"))
	_check("draft slows time", is_equal_approx(S.time_scale(), 0.2))
	var card: Dictionary = S.draft[0]
	S.choose_card(0)
	_check("new card enters place mode", S.pending_place == String(card["id"]) and S.draft.is_empty())
	S.place(0)  # locked — rejected
	_check("cannot place on locked slot", S.pending_place != "")
	ev = S.place(6)
	_check("placed building in free slot", S.id_at(6) == String(card["id"]) and S.pending_place == "" and is_equal_approx(S.time_scale(), 1.0))
	S.xp = S.xp_need()
	S.tick(0.01)
	var plus_idx: int = -1
	for k in S.draft.size():
		if String(S.draft[k]["kind"]) == "plus":
			plus_idx = k
	if plus_idx >= 0:
		var pid: String = S.draft[plus_idx]["id"]
		var before: int = S.lvl_at(6)
		S.choose_card(plus_idx)
		_check("plus card raises owned level", pid != S.id_at(6) or S.lvl_at(6) == before + 1)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 99
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	var base_s = _fresh()
	_check("draft is seed-deterministic", JSON.stringify(Draft.offer(r1, base_s.slots, base_s.unlocked)) == JSON.stringify(Draft.offer(r2, base_s.slots, base_s.unlocked)))

	# --- Stage 7: in-run cash spend ------------------------------------------
	S = _fresh()
	S.slots[7] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	S.cash = 5.0
	S.upgrade(7)
	_check("upgrade refused when broke", S.lvl_at(7) == 1)
	S.cash = 1000.0
	S.upgrade(7)
	_check("cash upgrade levels building", S.lvl_at(7) == 2 and S.cash < 1000.0)
	S.upgrade(12)
	_check("cash upgrade levels core", S.core_run_lvl == 1)
	S.unlock_plot(0)
	_check("run unlock opens outer plot", bool(S.unlocked[0]))

	# --- Stage 8: death banks coins into permanent save ----------------------
	var save: Dictionary = BaseMeta.default_save()
	S = TowerState.new()
	S.setup(5, save)
	S.coins_run = 42.7
	S.hp = -1.0
	S.spawn_t = 999.0
	S.stats["regen"] = 0.0
	ev = S.tick(0.01)
	_check("death event + over", S.over and String(ev.back()["t"]) == "dead")
	_check("coins banked to save", int(save["coins"]) == 42 and int(save["runs"]) == 1 and int(save["best_wave"]) == 1)

	# --- Stage 9: permanent base carries into the next run -------------------
	save["coins"] = 1000
	_check("perm place", BaseMeta.try_place(save, 7, "gun"))
	_check("perm place refuses occupied", not BaseMeta.try_place(save, 7, "mine"))
	_check("perm upgrade", BaseMeta.try_upgrade(save, 7) and int(BaseMeta.slot_of(save, 7)["lvl"]) == 2)
	_check("perm unlock outer", BaseMeta.try_unlock(save, 0))
	_check("perm core", BaseMeta.try_core(save, "hp"))
	S = TowerState.new()
	S.setup(6, save)
	_check("perm building present in new run", S.id_at(7) == "gun" and S.lvl_at(7) == 2)
	_check("perm unlock present in new run", bool(S.unlocked[0]))
	_check("perm core hp applied", is_equal_approx(S.hp, 125.0))
	S.cash = 1000.0
	S.upgrade(7)
	_check("run levels don't leak into save", S.lvl_at(7) == 3 and int(BaseMeta.slot_of(save, 7)["lvl"]) == 2)

	# --- Stage 10: persistence round-trip ------------------------------------
	MetaSave.clear()
	MetaSave.write(save)
	var back: Dictionary = BaseMeta.normalize(MetaSave.read())
	_check("save round-trips", int(back["coins"]) == int(save["coins"]) and String(BaseMeta.slot_of(back, 7)["id"]) == "gun" and (back["unlocked"] as Array).has(0))
	MetaSave.clear()

	# --- Stage 11: a full idle run terminates (endless ramp is lethal) -------
	S = _fresh()
	var t: float = 0.0
	while not S.over and t < 2400.0:
		S.tick(0.1)
		t += 0.1
		if S.draft.size() > 0:
			S.choose_card(0)
		if S.pending_place != "" and S.free_slots().size() > 0:
			S.place(int(S.free_slots()[0]))
	_check("unattended run ends in death", S.over and S.wave >= 3)

	_meta_stages()

	if fails.is_empty():
		print("SELFTEST OK")
		quit(0)
	else:
		print("SELFTEST FAIL: %d checks" % fails.size())
		quit(1)


func _evts(ev: Array, kind: String) -> Array:
	return ev.filter(func(e): return String(e["t"]) == kind)


## ENGINE-A meta systems (SPEC A1-A8). Fixed `now` so everything is deterministic.
func _meta_stages() -> void:
	var NOW: int = 1_800_000_000
	# --- Stage 12: save v2 + migration (AC-1..4) ----------------------------
	var v1: Dictionary = {"coins": 123, "core": {"dmg": 1, "hp": 2, "regen": 0}, "slots": {"7": {"id": "gun", "lvl": 3}}, "unlocked": [0, 4], "best_wave": 37, "runs": 5, "labs": {"lvls": {"armor": 4, "coin": 2}}}
	var m: Dictionary = BaseMeta.normalize(BaseMeta.migrate(v1))
	_check("AC-1 migrate keeps v1 fields", int(m["coins"]) == 123 and int(m["runs"]) == 5 and int(m["core"]["hp"]) == 2 and String(BaseMeta.slot_of(m, 7)["id"]) == "gun" and int(BaseMeta.slot_of(m, 7)["lvl"]) == 3 and (m["unlocked"] as Array) == [0, 4])
	_check("AC-1 migrate v2 fields", int(m["best_wave_by_tier"]["1"]) == 37 and int(m["best_wave"]) == 37 and int(m["gems"]) == 0 and int(m["tier"]) == 1 and int(m["last_seen"]) == 0 and int(m["version"]) == 2)
	_check("AC-1 armor lab dropped, others kept", not (m["labs"]["lvls"] as Dictionary).has("armor") and int(m["labs"]["lvls"]["coin"]) == 2)
	_check("normalize on raw v1 also migrates", int(BaseMeta.normalize(v1)["version"]) == 2 and int(BaseMeta.normalize(v1)["best_wave_by_tier"]["1"]) == 37)
	var v2: Dictionary = BaseMeta.normalize(m)
	v2["gems"] = 77
	v2["last_seen"] = NOW
	v2["best_coin_rate"] = 12.5
	v2["labs"]["running"] = [{"track": "dmg", "to_lvl": 1, "start": NOW, "end": NOW + 300}]
	v2["cards"]["owned"] = {"c_dmg": {"lvl": 2, "copies": 1}}
	v2["cards"]["equipped"] = ["c_dmg"]
	v2 = BaseMeta.normalize(v2)
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(v2)))
	_check("AC-2 v2 round-trips through JSON", JSON.stringify(rt) == JSON.stringify(v2) and int(rt["gems"]) == 77)
	var bad: Dictionary = BaseMeta.normalize(v2)
	bad["slots"]["8"] = {"id": "laser_of_doom", "lvl": 1}
	bad["slots"]["7"]["lvl"] = 99
	bad["labs"]["lvls"]["dmg"] = 99
	bad["labs"]["lvls"]["bogus"] = 3
	bad["labs"]["running"] = [{"track": "coin", "to_lvl": 3, "start": 0, "end": 1}, {"track": "xp", "to_lvl": 1, "start": 0, "end": 1}, {"track": "hp", "to_lvl": 1, "start": 0, "end": 1}]
	bad["cards"]["owned"]["c_hp"] = {"lvl": 9, "copies": 3}
	bad["cards"]["owned"]["c_fake"] = {"lvl": 1, "copies": 0}
	bad = BaseMeta.normalize(bad)
	_check("AC-3 unknown building dropped", BaseMeta.slot_of(bad, 8).is_empty())
	_check("AC-3 slot lvl clamped to perm cap", int(BaseMeta.slot_of(bad, 7)["lvl"]) == BaseMeta.perm_lvl_cap(bad))
	_check("AC-3 lab lvl clamped + unknown lab dropped", int(bad["labs"]["lvls"]["dmg"]) == 30 and not (bad["labs"]["lvls"] as Dictionary).has("bogus"))
	_check("AC-3 running <= slots", (bad["labs"]["running"] as Array).size() <= int(bad["labs"]["slots"]))
	_check("AC-3 card lvl clamped + unknown card dropped", int(bad["cards"]["owned"]["c_hp"]["lvl"]) == 5 and not (bad["cards"]["owned"] as Dictionary).has("c_fake"))
	_check("AC-4 first v2 boot pays no offline", int(Offline.compute(m, NOW)["coins"]) == 0)
	# bank + perm cap
	var b: Dictionary = BaseMeta.default_save()
	var bev: Array = BaseMeta.bank(b, 100, 35, 1, 10.0, NOW, 2)
	_check("bank records tier best, rate, last_seen, gems", int(b["best_wave_by_tier"]["1"]) == 35 and is_equal_approx(float(b["best_coin_rate"]), 10.0) and int(b["last_seen"]) == NOW and int(b["gems"]) == 2 and int(b["gem_log"]["boss"]) == 2 and bev.is_empty())
	_check("perm lvl cap 10 at T1", BaseMeta.perm_lvl_cap(b) == 10)
	b["coins"] = 1_000_000
	BaseMeta.try_place(b, 7, "gun")
	b["slots"]["7"]["lvl"] = 10
	_check("try_upgrade refuses past perm cap", not BaseMeta.try_upgrade(b, 7))

	# --- Stage 13: tiers (AC-5..7) ------------------------------------------
	_check("unlock waves 40/50/60", Tiers.unlock_wave(2) == 40 and Tiers.unlock_wave(3) == 50 and Tiers.unlock_wave(4) == 60)
	_check("T1 only at start", Tiers.highest(b) == 1 and Tiers.is_unlocked(b, 1) and not Tiers.is_unlocked(b, 2))
	bev = BaseMeta.bank(b, 10, 39, 1, 1.0, NOW)
	_check("w39 in T1 does not unlock T2", Tiers.highest(b) == 1 and bev.is_empty())
	var g0: int = int(b["gems"])
	bev = BaseMeta.bank(b, 10, 40, 1, 1.0, NOW)
	_check("AC-5 w40 in T1 unlocks T2 with +10 gems", Tiers.highest(b) == 2 and _evts(bev, "tier_unlocked").size() == 1 and int(b["gems"]) == g0 + 10 and int(b["gem_log"]["tier"]) == 10)
	bev = BaseMeta.bank(b, 10, 45, 1, 1.0, NOW)
	_check("AC-5 tier unlock rewarded once", bev.is_empty() and int(b["gems"]) == g0 + 10)
	_check("perm cap +5 per tier", BaseMeta.perm_lvl_cap(b) == 15)
	bev = BaseMeta.bank(b, 10, 49, 2, 1.0, NOW)
	_check("w49 in T2 does not unlock T3", Tiers.highest(b) == 2)
	var big: Dictionary = BaseMeta.default_save()
	big["best_wave_by_tier"] = {"1": 999, "2": 999, "3": 999, "4": 999, "5": 999, "6": 999, "7": 999, "8": 999}
	_check("AC-5 max tier 8", Tiers.highest(big) == 8 and not Tiers.is_unlocked(big, 9))
	_check("AC-6 hp mult 1.5^(T-1)", is_equal_approx(Tiers.hp_mult(1), 1.0) and is_equal_approx(Tiers.hp_mult(3), 2.25) and is_equal_approx(Tiers.hp_mult(4), 3.375))
	_check("AC-6 coin mult 1+0.6(T-1)", is_equal_approx(Tiers.coin_mult(1), 1.0) and is_equal_approx(Tiers.coin_mult(2), 1.6) and is_equal_approx(Tiers.coin_mult(3), 2.2))
	_check("AC-7 boss every 10 (T1-4) / 8 (T5+)", Tiers.boss_every(1) == 10 and Tiers.boss_every(4) == 10 and Tiers.boss_every(5) == 8)
	_check("roster gates", Tiers.allows("ranged", 1, 8) and not Tiers.allows("ranged", 1, 7) and not Tiers.allows("elite", 1, 20) and Tiers.allows("elite", 2, 5) and not Tiers.allows("splitter", 2, 20) and Tiers.allows("splitter", 3, 5) and not Tiers.allows("mite", 5, 50) and Tiers.allows("drone", 1, 1))
	_check("elite weight 0/8%/16%", is_equal_approx(Tiers.elite_weight(1), 0.0) and is_equal_approx(Tiers.elite_weight(2), 0.08) and is_equal_approx(Tiers.elite_weight(4), 0.16))
	var nb: Dictionary = BaseMeta.normalize(b)
	nb["tier"] = 7
	_check("normalize clamps chosen tier to highest", int(BaseMeta.normalize(nb)["tier"]) == 2)

	# --- Stage 14: labs + game speed (AC-11..13, A4) ------------------------
	var L: Dictionary = BaseMeta.default_save()
	L["coins"] = 50
	_check("lab cost table", Labs.cost("dmg", 0) == 80 and Labs.cost("dmg", 1) == 144 and Labs.cost("coin", 0) == 60)
	_check("lab duration table", Labs.duration(L, "dmg", 0) == 300 and Labs.duration(L, "speed", 1) == 5400)
	var snap: String = JSON.stringify(L)
	_check("AC-11 start fails when broke, no mutation", Labs.start(L, "dmg", NOW).is_empty() and JSON.stringify(L) == snap)
	L["coins"] = 10000
	var lev: Array = Labs.start(L, "dmg", NOW)
	_check("AC-11 start deducts cost, sets end", _evts(lev, "lab_started").size() == 1 and int(L["coins"]) == 10000 - 80 and int((Labs.running(L)[0] as Dictionary)["end"]) == NOW + 300)
	_check("cannot double-start a track", Labs.start(L, "dmg", NOW).is_empty())
	Labs.start(L, "coin", NOW)
	snap = JSON.stringify(L)
	_check("AC-11 start fails without free slot, no mutation", Labs.start(L, "xp", NOW).is_empty() and JSON.stringify(L) == snap)
	_check("AC-12 claim before end is a no-op", Labs.claim(L, NOW + 299).is_empty() and Labs.level(L, "dmg") == 0)
	_check("progress halfway", is_equal_approx(Labs.progress(L, 0, NOW + 150), 0.5))
	lev = Labs.claim(L, NOW + 300)
	_check("AC-12 claim completes exactly the finished slot", _evts(lev, "lab_done").size() == 2 and Labs.level(L, "dmg") == 1 and Labs.level(L, "coin") == 1 and Labs.running(L).is_empty())
	Labs.start(L, "speed", NOW)   # 1800 s = 30 min -> 1 gem
	(Labs.running(L)[0] as Dictionary)["end"] = NOW + 5400   # 90 min left -> 3 gems
	_check("AC-13 rush cost ceil(rem_min/30)", Labs.rush_cost(L, 0, NOW) == 3 and Labs.rush_cost(L, 0, NOW + 1801) == 2 and Labs.rush_cost(L, 0, NOW + 5399) == 1)
	snap = JSON.stringify(L)
	_check("AC-13 rush fails w/o gems, no mutation", Labs.rush(L, 0, NOW).is_empty() and JSON.stringify(L) == snap)
	L["gems"] = 5
	lev = Labs.rush(L, 0, NOW)
	_check("AC-13 rush completes now", _evts(lev, "lab_rushed").size() == 1 and int(L["gems"]) == 2 and Labs.level(L, "speed") == 1)
	_check("A4 speed steps follow speed lab", Labs.speed_steps(L) == [1.0, 1.5] and Labs.speed_steps(BaseMeta.default_save()) == [1.0])
	L["gems"] = 59
	_check("AC-13 slot 3 needs 60 gems", Labs.buy_slot(L).is_empty() and Labs.slots(L) == 2)
	L["gems"] = 60 + 150
	_check("AC-13 slot 3 = 60, slot 4 = 150, max 4", not Labs.buy_slot(L).is_empty() and int(L["gems"]) == 150 and not Labs.buy_slot(L).is_empty() and int(L["gems"]) == 0 and Labs.slots(L) == 4 and Labs.buy_slot(L).is_empty())
	L["labs"]["lvls"]["labspeed"] = 10
	_check("lab speed floors at 0.4x", is_equal_approx(Labs.speed_mult(L), 0.4) and Labs.duration(L, "dmg", 0) == 120)
	L["labs"]["lvls"]["dmg"] = 30
	_check("maxed track cannot start", Labs.start(L, "dmg", NOW).is_empty())
	var lm: Dictionary = Labs.modifiers(L)
	_check("lab modifiers: +5%/lvl dmg", is_equal_approx(float(lm["dmg"]), 1.5) and is_equal_approx(float(lm["coin"]), 0.05))

	# --- Stage 15: offline (AC-17/18) ---------------------------------------
	var O: Dictionary = BaseMeta.default_save()
	O["best_coin_rate"] = 100.0
	_check("AC-17 last_seen 0 pays 0", int(Offline.compute(O, NOW)["coins"]) == 0)
	O["last_seen"] = NOW
	_check("AC-17 under 5 min pays 0", int(Offline.compute(O, NOW + 299)["coins"]) == 0)
	_check("offline 10 min = 15% rate", int(Offline.compute(O, NOW + 600)["coins"]) == 150)
	_check("AC-17 capped at 4 h", int(Offline.compute(O, NOW + 86400)["minutes"]) == 240)
	O["labs"]["lvls"]["offcap"] = 8
	_check("AC-17 cap max 12 h", int(Offline.compute(O, NOW + 86400)["minutes"]) == 720)
	var back_t: int = NOW - 5000
	_check("AC-17 clock backwards pays 0 + resets", int(Offline.compute(O, back_t)["coins"]) == 0 and int(O["last_seen"]) == back_t)
	var ok18: bool = true
	for lvl in LabDB.max_of("offrate") + 1:
		O["labs"]["lvls"]["offrate"] = lvl
		ok18 = ok18 and Offline.rate_per_min(O) <= 0.20 * float(O["best_coin_rate"]) + 0.0001
	_check("AC-18 offline rate <= 20% of best active at every offrate lvl", ok18)
	O["labs"]["lvls"]["offrate"] = 0
	O["last_seen"] = NOW
	O["coins"] = 0
	var oev: Array = Offline.claim(O, NOW + 600, false)
	_check("offline claim pays + stamps last_seen", int(O["coins"]) == 150 and int(O["last_seen"]) == NOW + 600 and _evts(oev, "offline").size() == 1)
	O["last_seen"] = NOW
	_check("offline x2 needs 2 gems", Offline.claim(O, NOW + 600, true).is_empty() and int(O["last_seen"]) == NOW)
	O["gems"] = 2
	Offline.claim(O, NOW + 600, true)
	_check("offline x2 doubles for 2 gems", int(O["coins"]) == 450 and int(O["gems"]) == 0)

	# --- Stage 16: missions + streak (AC-28..30) ----------------------------
	var M: Dictionary = BaseMeta.default_save()
	M["best_wave"] = 30
	var mev: Array = Missions.roll(M, NOW)
	var day1: String = JSON.stringify(Missions.list(M))
	var tpls: Array = Missions.list(M).map(func(e): return String(e["tpl"]))
	_check("AC-28 rolls 3 distinct templates", _evts(mev, "missions_rolled").size() == 1 and tpls.size() == 3 and tpls[0] != tpls[1] and tpls[1] != tpls[2] and tpls[0] != tpls[2])
	_check("AC-28 same day does not re-roll", Missions.roll(M, NOW + 60).is_empty())
	var M2: Dictionary = BaseMeta.default_save()
	M2["best_wave"] = 30
	Missions.roll(M2, NOW + 10)
	_check("AC-28 same day -> same missions", JSON.stringify(Missions.list(M2)) == day1)
	var differs: bool = false
	for k in range(1, 6):
		var M3: Dictionary = BaseMeta.default_save()
		M3["best_wave"] = 30
		Missions.roll(M3, NOW + 86400 * k)
		differs = differs or JSON.stringify(Missions.list(M3)) != day1
	_check("different days roll differently", differs)
	# force a known list to test progress deterministically
	M["missions"]["list"] = [{"tpl": "kill", "target": 3, "prog": 0, "claimed": false, "gems": 3}, {"tpl": "wave", "target": 10, "prog": 0, "claimed": false, "gems": 4}, {"tpl": "perk", "target": 2, "prog": 0, "claimed": false, "gems": 2}]
	var gm: int = int(M["gems"])
	_check("AC-29 cannot claim unfinished", Missions.claim(M, 0).is_empty())
	mev = Missions.on_run_events(M, [{"t": "kill"}, {"t": "kill"}, {"t": "kill"}, {"t": "kill"}, {"t": "wave", "wave": 12}, {"t": "perk_taken", "id": "p_dmg"}, {"t": "perk_taken", "id": "p_glass"}, {"t": "perk_taken", "id": "p_greed"}])
	_check("AC-29 run events advance progress", _evts(mev, "mission_done").size() == 3 and int(Missions.list(M)[0]["prog"]) == 3 and int(Missions.list(M)[1]["prog"]) == 10 and int(Missions.list(M)[2]["prog"]) == 2 and int(M["stats"]["kills"]) == 4)
	_check("AC-29 claim pays once", not Missions.claim(M, 0).is_empty() and int(M["gems"]) == gm + 3 and Missions.claim(M, 0).is_empty())
	_check("bonus needs all claimed", Missions.claim_bonus(M).is_empty())
	Missions.claim(M, 1)
	Missions.claim(M, 2)
	_check("AC-29 all-clear bonus +5 once", not Missions.claim_bonus(M).is_empty() and int(M["gems"]) == gm + 3 + 4 + 2 + 5 and Missions.claim_bonus(M).is_empty() and int(M["gem_log"]["mission"]) == 14)
	Missions.roll(M, NOW + 86400)
	var fresh: bool = true
	for e in Missions.list(M):
		fresh = fresh and int(e["prog"]) == 0 and not bool(e["claimed"])
	_check("AC-28 new day re-rolls + resets", fresh and not bool(M["missions"]["bonus_claimed"]))
	# permanent upgrades + lab starts feed missions
	M["missions"]["list"] = [{"tpl": "upgrade", "target": 3, "prog": 0, "claimed": false, "gems": 2}, {"tpl": "lab", "target": 2, "prog": 0, "claimed": false, "gems": 2}, {"tpl": "eco", "target": 4, "prog": 0, "claimed": false, "gems": 2}]
	M["coins"] = 100000
	BaseMeta.try_core(M, "dmg")
	BaseMeta.try_place(M, 6, "mine")
	BaseMeta.try_upgrade(M, 6)
	Labs.start(M, "xp", NOW)
	Missions.on_run_events(M, [{"t": "placed", "slot": 7, "id": "mine"}, {"t": "placed", "slot": 8, "id": "gun"}])
	_check("perm upgrades / lab starts / eco placements count", int(Missions.list(M)[0]["prog"]) == 2 and int(Missions.list(M)[1]["prog"]) == 1 and int(Missions.list(M)[2]["prog"]) == 1)
	# streak
	var K: Dictionary = BaseMeta.default_save()
	var day0: int = Missions.day_of(NOW)
	var sev: Array = Missions.streak_claim(K, NOW)
	_check("AC-30 streak day 1 = 50 coins", int((_evts(sev, "streak_claimed")[0] as Dictionary)["day"]) == 1 and int(K["coins"]) == 50)
	_check("AC-30 once per day", Missions.streak_claim(K, NOW + 100).is_empty())
	for k in range(1, 6):
		Missions.streak_claim(K, NOW + 86400 * k)
	_check("streak day 6", int(K["streak"]["day_idx"]) == 6 and int(K["gems"]) == 2 + 3 + 4)
	sev = Missions.streak_claim(K, NOW + 86400 * 6)
	_check("AC-30 day 7 = 10 gems + free chest", int(K["streak"]["day_idx"]) == 7 and int(K["gems"]) == 19 and _evts(sev, "chest_opened").size() == 1 and (K["cards"]["owned"] as Dictionary).size() == 1 and int(K["gem_log"]["streak"]) == 19)
	var c0: int = int(K["coins"])
	Missions.streak_claim(K, NOW + 86400 * 7)
	_check("streak loops with x1.1 coins", int(K["streak"]["day_idx"]) == 1 and int(K["streak"]["loops"]) == 1 and int(K["coins"]) == c0 + 55)
	Missions.streak_claim(K, NOW + 86400 * 9)
	_check("AC-30 missed day resets to day 1", int(K["streak"]["day_idx"]) == 1 and int(K["streak"]["last_day"]) == day0 + 9)

	# --- Stage 17: cards (AC-31/32) -----------------------------------------
	var C: Dictionary = BaseMeta.default_save()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	_check("AC-31 chest needs 20 gems", Cards.open_chest(C, rng).is_empty())
	C["gems"] = 20 * 40
	var r1 := RandomNumberGenerator.new()
	r1.seed = 7
	var r2 := RandomNumberGenerator.new()
	r2.seed = 7
	var C2: Dictionary = C.duplicate(true)
	var cev: Array = Cards.open_chest(C, r1)
	_check("AC-31 chest costs 20 + seeded", int(C["gems"]) == 780 and JSON.stringify(cev) == JSON.stringify(Cards.open_chest(C2, r2)) and bool(cev[0]["new"]))
	# force-level a card: set owned and open many chests
	C["cards"]["owned"] = {"c_dmg": {"lvl": 1, "copies": 0}}
	var lvl_ok: bool = true
	var dups: int = 0
	var guard: int = 0
	while Cards.level(C, "c_dmg") < 5 and guard < 39:
		guard += 1
		var before: int = Cards.level(C, "c_dmg")
		var cp: int = int(C["cards"]["owned"]["c_dmg"]["copies"])
		var e3: Array = Cards.open_chest(C, rng)
		if String(e3[0]["card"]) == "c_dmg":
			dups += 1
			if cp + 1 >= before:
				lvl_ok = lvl_ok and bool(e3[0]["lvl_up"]) and Cards.level(C, "c_dmg") == before + 1
			else:
				lvl_ok = lvl_ok and not bool(e3[0]["lvl_up"])
	_check("AC-31 dup levels at copies >= L", lvl_ok and dups > 0)
	C["cards"]["owned"] = {}
	C["cards"]["owned"]["c_dmg"] = {"lvl": 5, "copies": 0}
	C["cards"]["owned"]["c_hp"] = {"lvl": 1, "copies": 0}
	C["cards"]["owned"]["c_cash"] = {"lvl": 2, "copies": 0}
	C["cards"]["owned"]["c_reroll"] = {"lvl": 3, "copies": 0}
	C["cards"]["equipped"] = []
	_check("unowned card cannot equip", Cards.equip(C, "c_wind").is_empty())
	Cards.equip(C, "c_dmg")
	Cards.equip(C, "c_hp")
	_check("AC-32 only 2 free slots", Cards.equip(C, "c_cash").is_empty())
	var cm: Dictionary = Cards.mods(C)
	_check("AC-32 only equipped cards modify", is_equal_approx(float(cm["dmg"]), 0.40) and is_equal_approx(float(cm["hp"]), 0.15) and is_equal_approx(float(cm["cash"]), 0.0))
	C["gems"] = 30 + 60 + 100
	_check("card slots 30/60/100, max 5", not Cards.buy_slot(C).is_empty() and int(C["gems"]) == 160 and not Cards.buy_slot(C).is_empty() and not Cards.buy_slot(C).is_empty() and int(C["gems"]) == 0 and Cards.slots(C) == 5 and Cards.buy_slot(C).is_empty())
	Cards.equip(C, "c_reroll")
	_check("reroll card gives int rerolls", int(Cards.mods(C)["reroll"]) == 2)
	Cards.unequip(C, "c_dmg")
	_check("unequip removes effect", is_equal_approx(float(Cards.mods(C)["dmg"]), 0.0))

	# --- Stage 18: run_mods bundle (A8) -------------------------------------
	var R: Dictionary = BaseMeta.normalize(C)
	R["best_wave_by_tier"] = {"1": 40, "2": 50}
	R["tier"] = 3
	R["labs"]["lvls"]["dmg"] = 4
	R["labs"]["lvls"]["startcash"] = 2
	R["labs"]["lvls"]["reroll"] = 1
	R["runs"] = 2
	R = BaseMeta.normalize(R)
	var rm: Dictionary = BaseMeta.run_mods(R)
	_check("A8 run_mods tier + mults", int(rm["tier"]) == 3 and is_equal_approx(float(rm["hp_mult"]), 2.25) and is_equal_approx(float(rm["coin_mult"]), 2.2) and int(rm["boss_every"]) == 10)
	_check("A8 run_mods labs", is_equal_approx(float(rm["lab_dmg"]), 0.2) and int(rm["start_cash"]) == 30 and int(rm["rerolls"]) == 1 and is_equal_approx(float(rm["speed"]), 1.0))
	_check("A8 run_mods cards + new bldgs", is_equal_approx(float((rm["cards"] as Dictionary)["hp"]), 0.15) and bool(rm["allow_new_bldg"]) and not bool(BaseMeta.run_mods(BaseMeta.default_save())["allow_new_bldg"]))
