extends SceneTree
## Corehold rules self-test. Drives TowerState / BaseMeta / Draft directly with
## fixed seeds and asserts what a human would check. Prints "SELFTEST OK" (exit
## 0) or "SELFTEST FAIL: <reason>" (exit 1).
## Run: godot --headless --path games/towerdef-pc-0001/ --script res://selftest.gd

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
const Perks := preload("res://Perks.gd")
const PerkDB := preload("res://data/PerkDB.gd")
const EnemyDB := preload("res://data/EnemyDB.gd")
const ModifierDB := preload("res://data/ModifierDB.gd")
const Stats := preload("res://Stats.gd")

var fails: Array = []


func _check(name: String, ok: bool) -> void:
	if not ok:
		fails.append(name)
		print("SELFTEST FAIL: " + name)


## Mobile 5x5 cell index -> the same cell on the PC 7x7 board (r+1, c+1), so
## the inherited 5x5 checks keep their exact geometry and adjacency.
func _c(i5: int) -> int:
	return BaseMeta.idx5_to_7(i5)


func _fresh(save: Dictionary = {}) -> RefCounted:
	var S = TowerState.new()
	S.setup(1234, BaseMeta.normalize(save))
	return S


func _initialize() -> void:
	# --- Stage 1: setup ------------------------------------------------------
	var S = _fresh()
	_check("setup: full hp", is_equal_approx(S.hp, 100.0))
	_check("setup: inner ring unlocked, outer locked", bool(S.unlocked[_c(6)]) and not bool(S.unlocked[_c(0)]) and not bool(S.unlocked[_c(12)]))
	_check("setup: 8 free slots", S.free_slots().size() == 8)
	_check("setup: core is the only weapon", (S.stats["weapons"] as Array).size() == 1)

	# --- Stage 2: stats math + adjacency -------------------------------------
	S.slots[_c(7)] = {"id": "gun", "perm": 1, "run": 0}
	S.recompute()
	var gun_dmg: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	S.slots[_c(6)] = {"id": "armory", "perm": 1, "run": 0}   # adjacent to gun (7) and core (12)
	S.recompute()
	var buffed: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	_check("armory buffs adjacent gun +25%", is_equal_approx(buffed, gun_dmg * 1.25))
	S.slots[_c(0)] = {"id": "armory", "perm": 1, "run": 0}   # NOT adjacent to 7
	S.recompute()
	_check("armory does not buff non-adjacent", is_equal_approx(float((S.stats["weapons"] as Array)[0]["dmg"]), buffed))
	S.slots[_c(16)] = {"id": "mine", "perm": 2, "run": 0}
	S.slots[_c(17)] = {"id": "oilmill", "perm": 1, "run": 0}   # adjacent to mine 16
	S.slots[_c(18)] = {"id": "bulwark", "perm": 1, "run": 0}
	S.recompute()
	_check("mine cash/sec", is_equal_approx(float(S.stats["cash_ps"]), 2.4))
	_check("oil mill + adjacent mine xp", is_equal_approx(float(S.stats["xp_mult"]), 1.0 + 0.25 + 0.15))
	_check("bulwark raises max hp", is_equal_approx(float(S.stats["max_hp"]), 140.0))
	_check("bulwark heals by its bonus", is_equal_approx(S.hp, 140.0))

	# --- Stage 3: combat — core kills an enemy, rewards land ------------------
	S = _fresh()
	S.enemies.append({"kind": "drone", "pos": TowerState.CENTER + Vector2(200, 0), "hp": 4.0, "max_hp": 4.0, "spd": 0.0, "dmg": 4.0, "cash": 1.0, "xp": 1.0, "coin": 0.2, "size": 16.0, "atk_cd": 0.0, "slow_t": 0.0})
	S.spawn_hold = true
	var ev: Array = S.tick(0.05)
	var kinds: Array = ev.map(func(e): return e["t"])
	_check("core fires a shot", kinds.has("shot"))
	_check("kill event + cash + xp", kinds.has("kill") and S.cash >= 1.0 and S.xp >= 1.0 and S.kills == 1)

	# --- Stage 4: enemy reaches the core and damages it ----------------------
	S = _fresh()
	S.spawn_hold = true
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
	S.spawn_hold = true
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
	S.place(_c(0))  # locked — rejected
	_check("cannot place on locked slot", S.pending_place != "")
	ev = S.place(_c(6))
	_check("placed building in free slot", S.id_at(_c(6)) == String(card["id"]) and S.pending_place == "" and is_equal_approx(S.time_scale(), 1.0))
	S.xp = S.xp_need()
	S.tick(0.01)
	var plus_idx: int = -1
	for k in S.draft.size():
		if String(S.draft[k]["kind"]) == "plus":
			plus_idx = k
	if plus_idx >= 0:
		var pid: String = S.draft[plus_idx]["id"]
		var before: int = S.lvl_at(_c(6))
		S.choose_card(plus_idx)
		_check("plus card raises owned level", pid != S.id_at(_c(6)) or S.lvl_at(_c(6)) == before + 1)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 99
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	var base_s = _fresh()
	_check("draft is seed-deterministic", JSON.stringify(Draft.offer(r1, base_s.slots, base_s.unlocked)) == JSON.stringify(Draft.offer(r2, base_s.slots, base_s.unlocked)))

	# --- Stage 7: in-run cash spend ------------------------------------------
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	S.cash = 5.0
	S.upgrade(_c(7))
	_check("upgrade refused when broke", S.lvl_at(_c(7)) == 1)
	S.cash = 1000.0
	S.upgrade(_c(7))
	_check("cash upgrade levels building", S.lvl_at(_c(7)) == 2 and S.cash < 1000.0)
	S.upgrade(_c(12))
	_check("cash upgrade levels core", S.core_run_lvl == 1)
	S.unlock_plot(_c(0))
	_check("run unlock opens outer plot", bool(S.unlocked[_c(0)]))

	# --- Stage 8: death banks coins into permanent save ----------------------
	var save: Dictionary = BaseMeta.default_save()
	S = TowerState.new()
	S.setup(5, save)
	S.coins_run = 42.7
	S.hp = -1.0
	S.spawn_hold = true
	S.stats["regen"] = 0.0
	ev = S.tick(0.01)
	_check("death event + over", S.over and String(ev.back()["t"]) == "dead")
	_check("coins banked to save", int(save["coins"]) == 42 and int(save["runs"]) == 1 and int(save["best_wave"]) == 1)

	# --- Stage 9: permanent base carries into the next run -------------------
	save["coins"] = 1000
	_check("perm place", BaseMeta.try_place(save, _c(7), "gun"))
	_check("perm place refuses occupied", not BaseMeta.try_place(save, _c(7), "mine"))
	_check("perm upgrade", BaseMeta.try_upgrade(save, _c(7)) and int(BaseMeta.slot_of(save, _c(7))["lvl"]) == 2)
	_check("perm unlock outer", BaseMeta.try_unlock(save, _c(0)))
	_check("perm core", BaseMeta.try_core(save, "hp"))
	S = TowerState.new()
	S.setup(6, save)
	_check("perm building present in new run", S.id_at(_c(7)) == "gun" and S.lvl_at(_c(7)) == 2)
	_check("perm unlock present in new run", bool(S.unlocked[_c(0)]))
	_check("perm core hp applied", is_equal_approx(S.hp, 125.0))
	S.cash = 1000.0
	S.upgrade(_c(7))
	_check("run levels don't leak into save", S.lvl_at(_c(7)) == 3 and int(BaseMeta.slot_of(save, _c(7))["lvl"]) == 2)

	# --- Stage 10: persistence round-trip ------------------------------------
	MetaSave.clear()
	MetaSave.write(save)
	var back: Dictionary = BaseMeta.normalize(MetaSave.read())
	_check("save round-trips", int(back["coins"]) == int(save["coins"]) and String(BaseMeta.slot_of(back, _c(7))["id"]) == "gun" and (back["unlocked"] as Array).has(_c(0)))
	var aset: Dictionary = save.duplicate(true)
	aset["settings"] = {"music": 0.25, "sfx": 0.5, "mute": true}
	MetaSave.write(aset)
	var aback: Dictionary = BaseMeta.normalize(MetaSave.read())
	var ast: Dictionary = aback["settings"]
	_check("audio settings survive save + normalize", absf(float(ast["music"]) - 0.25) < 0.001 and absf(float(ast["sfx"]) - 0.5) < 0.001 and bool(ast["mute"]))
	var aclamp: Dictionary = BaseMeta.normalize({"settings": {"music": 7.0, "sfx": -1.0}})
	_check("audio settings clamp + default mute", float(aclamp["settings"]["music"]) == 1.0 and float(aclamp["settings"]["sfx"]) == 0.0 and not bool(aclamp["settings"]["mute"]))
	MetaSave.clear()

	# --- Stage 10b: abandon banks coins via the death path -------------------
	var SA = _fresh()
	SA.coins_run = 40.0
	SA.wind_hp = 0.5
	var runs0: int = int(SA.save["runs"])
	var coins0: int = int(SA.save["coins"])
	var aev: Array = SA.abandon()
	var akinds: Array = []
	for x in aev:
		akinds.append(String((x as Dictionary)["t"]))
	_check("abandon ends run + banks coins (no revive)", SA.over and akinds.has("abandon") and akinds.has("dead") and not akinds.has("revive") and int(SA.save["runs"]) == runs0 + 1 and int(SA.save["coins"]) >= coins0 + 40)
	_check("abandon twice is a no-op", SA.abandon().is_empty())

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
	_engine_b_stages()
	_fix_round_stages()
	_juice_targeting_stages()
	_pc_engine_stages()

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
	_check("AC-1 migrate keeps v1 fields", int(m["coins"]) == 123 and int(m["runs"]) == 5 and int(m["core"]["hp"]) == 2 and String(BaseMeta.slot_of(m, _c(7))["id"]) == "gun" and int(BaseMeta.slot_of(m, _c(7))["lvl"]) == 3 and (m["unlocked"] as Array) == [_c(0), _c(4)])
	_check("AC-1 migrate v2 fields", int(m["best_wave_by_tier"]["1"]) == 37 and int(m["best_wave"]) == 37 and int(m["gems"]) == 0 and int(m["tier"]) == 1 and int(m["last_seen"]) == 0 and int(m["version"]) == BaseMeta.VERSION)
	_check("AC-1 armor lab dropped, others kept", not (m["labs"]["lvls"] as Dictionary).has("armor") and int(m["labs"]["lvls"]["coin"]) == 2)
	_check("normalize on raw v1 also migrates", int(BaseMeta.normalize(v1)["version"]) == BaseMeta.VERSION and int(BaseMeta.normalize(v1)["best_wave_by_tier"]["1"]) == 37)
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
	bad["slots"][str(_c(8))] = {"id": "laser_of_doom", "lvl": 1}
	bad["slots"][str(_c(7))]["lvl"] = 99
	bad["labs"]["lvls"]["dmg"] = 99
	bad["labs"]["lvls"]["bogus"] = 3
	bad["labs"]["running"] = [{"track": "coin", "to_lvl": 3, "start": 0, "end": 1}, {"track": "xp", "to_lvl": 1, "start": 0, "end": 1}, {"track": "hp", "to_lvl": 1, "start": 0, "end": 1}]
	bad["cards"]["owned"]["c_hp"] = {"lvl": 9, "copies": 3}
	bad["cards"]["owned"]["c_fake"] = {"lvl": 1, "copies": 0}
	bad = BaseMeta.normalize(bad)
	_check("AC-3 unknown building dropped", BaseMeta.slot_of(bad, _c(8)).is_empty())
	_check("AC-3 slot lvl clamped to perm cap", int(BaseMeta.slot_of(bad, _c(7))["lvl"]) == BaseMeta.perm_lvl_cap(bad))
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
	BaseMeta.try_place(b, _c(7), "gun")
	b["slots"][str(_c(7))]["lvl"] = 10
	_check("try_upgrade refuses past perm cap", not BaseMeta.try_upgrade(b, _c(7)))

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
	BaseMeta.try_place(M, _c(6), "mine")
	BaseMeta.try_upgrade(M, _c(6))
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


func _enemy(kind: String, pos: Vector2, hp: float = 999.0) -> Dictionary:
	var d: Dictionary = EnemyDB.get_def(kind)
	return {"kind": kind, "pos": pos, "hp": hp, "max_hp": hp, "spd": float(d["spd"]), "dmg": float(d["dmg"]), "cash": float(d["cash"]), "xp": float(d["xp"]), "coin": float(d["coin"]), "size": float(d["size"]), "atk_cd": 0.0, "slow_t": 0.0, "shield": 0, "fire_cd": 0.0, "shock_t": 0.0, "shock_src": -1}


func _weapon(S, kind: String) -> Dictionary:
	for w in S.stats["weapons"]:
		if String(w["kind"]) == kind:
			return w
	return {}


func _has_link(S, a: int, b: int, tag: String) -> bool:
	for l in S.stats["links"]:
		var la: Array = l
		if int(la[0]) == a and int(la[1]) == b and String(la[2]) == tag:
			return true
	return false


## ENGINE-B run systems (SPEC B1-B8).
func _engine_b_stages() -> void:
	# --- Stage 19: B1 meta modifiers applied at setup (AC-14, AC-32) ----------
	var sv: Dictionary = BaseMeta.default_save()
	var S0 = TowerState.new()
	S0.setup(7, sv)
	var core0: float = float(_weapon(S0, "core")["dmg"])
	sv["labs"]["lvls"]["dmg"] = 4
	sv["labs"]["lvls"]["hp"] = 2
	sv["labs"]["lvls"]["startcash"] = 2
	sv["labs"]["lvls"]["reroll"] = 1
	sv["cards"]["owned"] = {"c_dmg": {"lvl": 1, "copies": 0}, "c_reroll": {"lvl": 1, "copies": 0}, "c_hp": {"lvl": 1, "copies": 0}}
	sv["cards"]["equipped"] = ["c_dmg", "c_reroll"]
	var S = TowerState.new()
	S.setup(7, sv)
	_check("B1 dmg x (1+lab)(1+card)", is_equal_approx(float(_weapon(S, "core")["dmg"]), core0 * 1.2 * 1.1))
	_check("B1 max hp x (1+lab_hp), unequipped card ignored", is_equal_approx(float(S.stats["max_hp"]), 110.0) and is_equal_approx(S.hp, 110.0))
	_check("B1 start cash + rerolls", is_equal_approx(S.cash, 30.0) and S.rerolls_left == 2)
	sv["best_wave_by_tier"] = {"1": 60, "2": 0}
	sv["tier"] = 2
	S = TowerState.new()
	S.setup(7, sv)
	_check("B1 tier 2 multipliers", S.tier == 2 and is_equal_approx(S.hp_mult, 1.5) and is_equal_approx(S.coin_mult, 1.6))
	S.spawn_hold = true
	S._spawn("drone", [])
	_check("B1 enemy hp x tier hp_mult", is_equal_approx(float(S.enemies[0]["hp"]), 6.0 * 1.5))
	S.enemies.clear()
	S.wave_t = S.wave_time - 0.001
	S.tick(0.01)
	_check("B1 wave coins x coin_mult", is_equal_approx(S.coins_run, 2.0 * 1.6))
	S.draft = [{"kind": "new", "id": "gun"}]
	var rr: Array = S.reroll_draft()
	_check("reroll spends a reroll", rr.size() == 1 and S.rerolls_left == 1 and S.draft.size() == 3)

	# --- Stage 20: B2 speed + sub-steps (AC-15) ------------------------------
	var res: Array = []
	for sp in [1.0, 2.5]:
		var R = _fresh()
		R.set_speed(sp)
		var real: float = 0.0
		while real * sp < 180.0 and not R.over:
			R.tick(0.05)
			real += 0.05
			if R.draft.size() > 0:
				R.choose_card(0)
			if R.pending_place != "" and R.free_slots().size() > 0:
				R.place(int(R.free_slots()[0]))
			if R.perk_offer.size() > 0:
				R.choose_perk(0)
		res.append([R.wave, R.kills, R.coins_run])
	_check("AC-15 speed-invariant wave/kills/coins %s" % str(res), int(res[0][0]) == int(res[1][0]) and absi(int(res[0][1]) - int(res[1][1])) <= 1 and absf(float(res[0][2]) - float(res[1][2])) <= 1.0)
	S = _fresh()
	S.set_speed(2.5)
	S.spawn_hold = true
	S.tick(0.1)
	_check("B2 speed scales game time", is_equal_approx(S.time_alive, 0.25))

	# --- Stage 21: B3 boss bounty, mine scaling, cash-out (AC-10, AC-22) -----
	var sv3: Dictionary = BaseMeta.default_save()
	S = TowerState.new()
	S.setup(9, sv3)
	S.spawn_hold = true
	S.wave = 20
	var bev: Array = []
	for k in 4:
		var b: Dictionary = _enemy("boss", TowerState.CENTER + Vector2(100, 0), 0.0)
		S.enemies.append(b)
		S._reap(bev)
	var bb: Array = _evts(bev, "boss_bounty")
	_check("boss bounty coins 25*w/10", bb.size() == 4 and int(bb[0]["coins"]) == 50)
	_check("AC-10 boss gems capped at 3 awards", S.gems_run == 3 and int(bb[3]["gems"]) == 0)
	# AC-10: 2 gems per award from T3; AC-10a: daily boss-gem allowance.
	var sv3b: Dictionary = BaseMeta.default_save()
	sv3b["best_wave_by_tier"] = {"1": 40, "2": 50}
	BaseMeta.select_tier(sv3b, 3)
	var T3S = TowerState.new()
	T3S.setup(9, sv3b, 1767225600)
	T3S.spawn_hold = true
	T3S.wave = 20
	var b3ev: Array = []
	for k in 4:
		T3S.enemies.append(_enemy("boss", TowerState.CENTER + Vector2(100, 0), 0.0))
		T3S._reap(b3ev)
	_check("AC-10 T3 boss gems = 2 per award, 3 awards", T3S.tier == 3 and T3S.gems_run == 6 and int(_evts(b3ev, "boss_bounty")[0]["gems"]) == 2)
	BaseMeta.bank(sv3b, 0, 20, 3, 1.0, 1767225600 + 60, 6)
	_check("AC-10a daily allowance 10 -> 4 left same day", BaseMeta.boss_gem_allowance(sv3b, 1767225600 + 120) == 4 and BaseMeta.boss_gem_allowance(sv3b, 1767225600 + 86400) == 10)
	T3S = TowerState.new()
	T3S.setup(10, sv3b, 1767225600 + 120)
	T3S.spawn_hold = true
	T3S.wave = 20
	for k in 3:
		T3S.enemies.append(_enemy("boss", TowerState.CENTER + Vector2(100, 0), 0.0))
		T3S._reap(b3ev)
	_check("AC-10a run gems clipped by the daily allowance", T3S.gems_run == 4)
	_check("AC-10a allowance survives normalize", int(BaseMeta.normalize(JSON.parse_string(JSON.stringify(sv3b)))["boss_gems_today"]["n"]) == 6)
	S.slots[_c(7)] = {"id": "mine", "perm": 1, "run": 0}
	S.wave = 11
	S.recompute()
	_check("mine scales 1.2*L*(1+0.03*(w-1))", is_equal_approx(float(S.stats["cash_ps"]), 1.2 * 1.3))
	S.cash_earned = 1000.0
	var c_before: int = int(S.coins_run)
	S.hp = -1.0
	S.stats["regen"] = 0.0
	var dev: Array = S.tick(0.01)
	var go: Array = _evts(dev, "game_over")
	_check("AC-22 game_over itemises cash-out", go.size() == 1 and int(go[0]["breakdown"]["cashout"]) == 20 and int(go[0]["coins"]) == c_before + 20 and int(go[0]["breakdown"]["gems"]) == 3)
	_check("death banks coins + boss gems", int(sv3["coins"]) == c_before + 20 and int(sv3["gems"]) == 3 and int(sv3["gem_log"]["boss"]) == 3)
	_check("dead stays the last event", String(dev.back()["t"]) == "dead")

	# --- Stage 22: B4 enemy roster (AC-25..27) --------------------------------
	_check("ranged gated to wave 8", not Tiers.allows("ranged", 1, 7) and Tiers.allows("ranged", 1, 8))
	S = _fresh()
	var seen: Dictionary = {}
	S.wave = 30
	for k in 3000:
		seen[S._roll_kind()] = true
	_check("T1 rolls ranged but never elite/splitter/mite", seen.has("ranged") and not seen.has("elite") and not seen.has("splitter") and not seen.has("mite"))
	S.tier = 3
	seen.clear()
	for k in 3000:
		seen[S._roll_kind()] = true
	_check("T3 rolls elite + splitter, never mite", seen.has("elite") and seen.has("splitter") and not seen.has("mite"))
	S = _fresh()
	S.spawn_hold = true
	S.stats["weapons"] = []
	S.stats["regen"] = 0.0
	S.enemies.append(_enemy("ranged", TowerState.CENTER + Vector2(240, 0)))
	S.enemies[0]["fire_cd"] = 2.0
	var shots: int = 0
	for k in 100:
		shots += _evts(S.tick(0.05), "enemy_shot").size()
	var rpos: Vector2 = S.enemies[0]["pos"]
	_check("AC-25 ranged stops at 230", absf(rpos.distance_to(TowerState.CENTER) - 230.0) < 0.5)
	_check("AC-25 ranged fires every 2s", shots == 2 and S.hp < 100.0)
	S = _fresh()
	S.spawn_hold = true
	S.wave = 20
	S._spawn("elite", [])
	var el: Dictionary = S.enemies[0]
	_check("AC-26 elite shield 3+floor(w/10)", int(el["shield"]) == 5)
	var sev: Array = []
	for k in 5:
		S._hit(el, 1.0e6, sev)
	_check("AC-26 shield absorbs exactly N hits", float(el["hp"]) > 0.0 and _evts(sev, "shield_hit").size() == 5 and _evts(sev, "shield_break").size() == 1)
	S._hit(el, 1.0e6, sev)
	_check("elite takes damage after shield breaks", float(el["hp"]) <= 0.0)
	S = _fresh()
	S.spawn_hold = true
	S.slots[_c(7)] = {"id": "tesla", "perm": 3, "run": 0}
	S.recompute()
	S.stats["weapons"] = [_weapon(S, "tesla")]
	S._spawn("elite", [])
	S.enemies[0]["pos"] = TowerState.slot_pos(_c(7)) + Vector2(60, 0)
	S.enemies[0]["spd"] = 0.0
	var tev: Array = S.tick(0.05)
	_check("AC-26 tesla chain hit counts as a shield hit", _evts(tev, "shield_hit").size() == 1 and int(S.enemies[0]["shield"]) == 2)
	S = _fresh()
	S.spawn_hold = true
	S.enemies.append(_enemy("splitter", TowerState.CENTER + Vector2(300, 0), 0.0))
	var spv: Array = []
	S._reap(spv)
	var mites: int = 0
	for e in S.enemies:
		if String(e["kind"]) == "mite":
			mites += 1
	_check("AC-27 splitter spawns 2 mites once", mites == 2 and _evts(spv, "split").size() == 1)
	for e in S.enemies:
		e["hp"] = 0.0
	spv.clear()
	S._reap(spv)
	_check("AC-27 mites do not split", S.enemies.is_empty() and _evts(spv, "split").is_empty())

	# --- Stage 23: B5/B6 buildings + synergies (AC-19..21) --------------------
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 1, "run": 0}
	S.recompute()
	var gr: float = float(_weapon(S, "gun")["rate"])
	S.slots[_c(8)] = {"id": "mine", "perm": 3, "run": 0}
	S.recompute()
	_check("S1 mine+gun +5%/mine lvl", is_equal_approx(float(_weapon(S, "gun")["rate"]), gr * 1.15) and _has_link(S, _c(8), _c(7), "S1"))
	S.slots[_c(8)] = {"id": "mine", "perm": 20, "run": 0}
	S.recompute()
	_check("S1 capped at +50%", is_equal_approx(float(_weapon(S, "gun")["rate"]), gr * 1.5))
	S.slots[_c(8)] = {}
	S.slots[_c(0)] = {"id": "mine", "perm": 3, "run": 0}
	S.recompute()
	_check("S1 needs adjacency", is_equal_approx(float(_weapon(S, "gun")["rate"]), gr) and not _has_link(S, _c(0), _c(7), "S1"))
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 25, "run": 0}
	S.slots[_c(6)] = {"id": "armory", "perm": 10, "run": 0}
	S.recompute()
	_check("AC-21 gun rate cap 2.5", is_equal_approx(float(_weapon(S, "gun")["rate"]), 2.5))
	_check("AC-21 armory per-target cap +100%", is_equal_approx(float(_weapon(S, "gun")["dmg"]), (3.0 + 2.0 * 25.0) * 2.0))
	S = _fresh()
	S.slots[_c(6)] = {"id": "bulwark", "perm": 2, "run": 0}
	S.slots[_c(0)] = {"id": "bulwark", "perm": 2, "run": 0}
	S.recompute()
	_check("S3 bulwark on core ring +3%/lvl dr", is_equal_approx(float(S.stats["dr"]), 0.06) and _has_link(S, _c(6), _c(12), "S3") and not _has_link(S, _c(0), _c(12), "S3"))
	S.slots[_c(11)] = {"id": "bulwark", "perm": 20, "run": 0}
	S.slots[_c(13)] = {"id": "aegis", "perm": 20, "run": 0}
	S.recompute()
	_check("dr caps: bulwark 30% + aegis 32% -> total 60%", is_equal_approx(float(S.stats["dr_bulwark"]), 0.3) and is_equal_approx(float(S.stats["dr_aegis"]), 0.32) and is_equal_approx(float(S.stats["dr"]), 0.6))
	S = _fresh()
	S.spawn_hold = true
	S.stats["weapons"] = []
	S.slots[_c(13)] = {"id": "aegis", "perm": 2, "run": 0}
	S.recompute()
	S.stats["weapons"] = []
	S.stats["regen"] = 0.0
	S.enemies.append(_enemy("hauler", TowerState.CENTER + Vector2(140, 0)))
	S.enemies[0]["dmg"] = 10.0
	S.tick(0.01)
	_check("AC-20 aegis core damage reduction", is_equal_approx(S.hp, 100.0 - 10.0 * 0.92))
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 1, "run": 0}
	S.slots[_c(17)] = {"id": "mine", "perm": 1, "run": 0}
	S.recompute()
	var g0: float = float(_weapon(S, "gun")["rate"])
	var m0: float = float(S.stats["cash_ps"])
	S.slots[_c(8)] = {"id": "aegis", "perm": 1, "run": 0}
	S.slots[_c(16)] = {"id": "aegis", "perm": 1, "run": 0}
	S.recompute()
	_check("AC-20 aegis +10% rate to adjacent weapon", is_equal_approx(float(_weapon(S, "gun")["rate"]), g0 * 1.1) and _has_link(S, _c(8), _c(7), "S5"))
	_check("AC-20 aegis -15% adjacent eco", is_equal_approx(float(S.stats["cash_ps"]), m0 * 0.85) and _has_link(S, _c(16), _c(17), "S5"))
	S = _fresh()
	S.spawn_hold = true
	S.slots[_c(7)] = {"id": "vault", "perm": 2, "run": 0}
	S.recompute()
	S.cash = 100.0
	S.wave_t = S.wave_time - 0.001
	var vev: Array = S.tick(0.01)
	_check("AC-20 vault interest 4%*L", _evts(vev, "interest").size() == 1 and is_equal_approx(float(_evts(vev, "interest")[0]["amt"]), 8.0))
	S.cash = 5000.0
	vev = []
	S._wave_end(vev)
	_check("vault cap 40*L", is_equal_approx(float(vev[0]["amt"]), 80.0))
	S.slots[_c(8)] = {"id": "bounty", "perm": 1, "run": 0}
	S.recompute()
	vev = []
	S._wave_end(vev)
	_check("S4 vault+bounty cap x1.5", is_equal_approx(float(vev[0]["amt"]), 120.0) and _has_link(S, _c(8), _c(7), "S4"))
	S = _fresh()
	S.slots[_c(7)] = {"id": "mortar", "perm": 1, "run": 0}
	S.slots[_c(8)] = {"id": "tesla", "perm": 1, "run": 0}
	S.recompute()
	_check("S2 link tesla->mortar", _has_link(S, _c(8), _c(7), "S2"))
	S.spawn_hold = true
	S.stats["weapons"] = [_weapon(S, "mortar")]
	var mdmg: float = float(_weapon(S, "mortar")["dmg"])
	var shocked: Dictionary = _enemy("drone", TowerState.slot_pos(_c(7)) + Vector2(100, 0))
	shocked["spd"] = 0.0
	shocked["shock_t"] = 1.0
	shocked["shock_src"] = _c(8)
	var plain: Dictionary = _enemy("drone", TowerState.slot_pos(_c(7)) + Vector2(100, 5))
	plain["spd"] = 0.0
	S.enemies.append(shocked)
	S.enemies.append(plain)
	S.tick(0.01)
	_check("S2 shocked enemy takes mortar splash x1.3", is_equal_approx(999.0 - float(shocked["hp"]), mdmg * 1.3) and is_equal_approx(999.0 - float(plain["hp"]), mdmg))
	var rng5 := RandomNumberGenerator.new()
	var sl: Array = []
	var un: Array = []
	for i in TowerState.N:
		sl.append({})
		un.append(i != TowerState.CORE_SLOT)
	var any_new: bool = false
	for k in 200:
		for c in Draft.offer(rng5, sl, un, false):
			if BuildingDB.NEW_IDS.has(String(c["id"])):
				any_new = true
	var got_new: bool = false
	for k in 200:
		for c in Draft.offer(rng5, sl, un, true):
			if BuildingDB.NEW_IDS.has(String(c["id"])):
				got_new = true
	_check("vault/aegis drafted only when allow_new_bldg", not any_new and got_new)
	var sv5: Dictionary = BaseMeta.default_save()
	sv5["runs"] = 2
	S = TowerState.new()
	S.setup(1, sv5)
	_check("allow_new_bldg from run 3", S.allow_new_bldg)

	# --- Stage 24: B7 perks (AC-23, AC-24) -------------------------------------
	var ra := RandomNumberGenerator.new()
	ra.seed = 5
	var rb := RandomNumberGenerator.new()
	rb.seed = 5
	var o1: Array = Perks.offer(ra, [])
	_check("AC-23 perk offer deterministic", o1 == Perks.offer(rb, []))
	var fams: Dictionary = {}
	for id in o1:
		fams[String(PerkDB.DEFS[id]["fam"])] = true
	_check("AC-23 3 distinct ids, one per family", o1.size() == 3 and fams.size() == 3)
	var taken: Array = ["p_hp", "p_fort"]
	var ok_untaken: bool = true
	for k in 50:
		var o: Array = Perks.offer(ra, taken)
		if o.has("p_hp") or o.has("p_fort") or o.size() != 3:
			ok_untaken = false
	_check("AC-23 never offers a maxed perk", ok_untaken)
	var full: Array = []
	for id in PerkDB.IDS:
		for k in int(PerkDB.DEFS[id]["stack"]):
			full.append(id)
	_check("no offer when every perk is maxed", Perks.offer(ra, full).is_empty())
	S = _fresh()
	S.spawn_hold = true
	S.wave = 4
	S.wave_t = S.wave_time - 0.001
	var pev: Array = S.tick(0.01)
	_check("AC-23 perk_offer at wave 5", _evts(pev, "perk_offer").size() == 1 and S.perk_offer.size() == 3 and is_equal_approx(S.time_scale(), 0.2))
	S = _fresh()
	S.spawn_hold = true
	S.xp = S.xp_need()
	S.wave = 4
	S.wave_t = S.wave_time - 0.001
	pev = S.tick(0.01)
	_check("AC-23 perk queues behind the building draft", S.draft.size() == 3 and S.perk_offer.is_empty() and S.perk_pending == 1)
	S.choose_card(0)
	pev = S.place(int(S.free_slots()[0]))
	_check("queued perk opens after the draft closes", _evts(pev, "perk_offer").size() == 1 and S.perk_offer.size() == 3)
	var pick: String = S.perk_offer[0]
	pev = S.choose_perk(0)
	_check("choose_perk emits perk_taken", _evts(pev, "perk_taken").size() == 1 and S.perks_taken == [pick] and S.perk_offer.is_empty())
	S = _fresh()
	var base_core: float = float(_weapon(S, "core")["dmg"])
	var base_rate: float = float(_weapon(S, "core")["rate"])
	S.perks_taken = ["p_dmg", "p_dmg"]
	S.recompute()
	_check("AC-24 Overcharge +20%/stack", is_equal_approx(float(_weapon(S, "core")["dmg"]), base_core * 1.4))
	S.perks_taken = ["p_glass"]
	S.recompute()
	_check("AC-24 Glass Cannon +40% dmg -25% hp", is_equal_approx(float(_weapon(S, "core")["dmg"]), base_core * 1.4) and is_equal_approx(float(S.stats["max_hp"]), 75.0))
	S.perks_taken = ["p_fort"]
	S.recompute()
	_check("AC-24 Fortress", is_equal_approx(float(S.stats["max_hp"]), 160.0) and is_equal_approx(float(S.stats["regen"]), 1.0) and is_equal_approx(float(_weapon(S, "core")["dmg"]), base_core * 0.8))
	S.perks_taken = ["p_frenzy", "p_rate"]
	S.recompute()
	_check("AC-24 Frenzy + Hair Trigger rate, regen 0", is_equal_approx(float(_weapon(S, "core")["rate"]), base_rate * 1.45) and is_equal_approx(float(S.stats["regen"]), 0.0))
	S.perks_taken = ["p_greed", "p_miser", "p_bloodmoon"]
	S.recompute()
	_check("AC-24 economy tradeoffs", is_equal_approx(S.run_coin_mult(), 1.5 * 1.75) and is_equal_approx(S.run_cash_mult(), 1.5) and is_equal_approx(float(S.stats["xp_mult"]), 0.7) and S.upgrade_cost(TowerState.CORE_SLOT) == 5)
	var worst: bool = true
	var tr: Array = ["p_glass", "p_greed", "p_fort", "p_frenzy", "p_miser", "p_bloodmoon"]
	for mask in 64:
		var tk: Array = []
		for b in 6:
			if mask & (1 << b):
				tk.append(tr[b])
		S.perks_taken = tk
		S.recompute()
		if float(S.stats["max_hp"]) < 50.0 - 0.001 or float(S.stats["regen"]) < 0.0:
			worst = false
	_check("AC-24 no tradeoff combo below 50% hp or negative regen", worst)
	S = _fresh()
	S.hp = 10.0
	S.perk_offer = ["p_hp"]
	S.choose_perk(0)
	_check("Reinforced Core heals to full", is_equal_approx(S.hp, 125.0))

	# --- Stage 25: B8 cards in-run (AC-33) ------------------------------------
	var sv8: Dictionary = BaseMeta.default_save()
	sv8["cards"]["owned"] = {"c_wind": {"lvl": 2, "copies": 0}, "c_skip": {"lvl": 1, "copies": 0}}
	sv8["cards"]["equipped"] = ["c_wind", "c_skip"]
	S = TowerState.new()
	S.setup(3, sv8)
	S.spawn_hold = true
	S.hp = -1.0
	var wev: Array = S.tick(0.01)
	_check("AC-33 Second Wind revives at card %", _evts(wev, "revive").size() == 1 and not S.over and S.hp > 20.0 and S.hp <= 25.5)
	S.hp = -1.0
	wev = S.tick(0.01)
	_check("AC-33 Second Wind only once", S.over and _evts(wev, "revive").is_empty())
	S = TowerState.new()
	S.setup(3, sv8)
	S.skip_chance = 1.0
	S.spawn_hold = true
	S.wave = 3
	S.wave_t = S.wave_time - 0.001
	var kv: int = S.kills
	wev = S.tick(0.01)
	var sk: Array = _evts(wev, "wave_skip")
	_check("AC-33 Wave Skip jumps 2 waves with 50% coins", S.wave == 5 and sk.size() == 1 and int(sk[0]["skipped"]) == 4 and is_equal_approx(S.coins_run, 4.0 * 0.5 + 5.0) and S.kills == kv)
	_check("skip landing on a perk wave still queues a perk", S.perk_offer.size() == 3 or S.perk_pending > 0)


## Fix-round systems: Core Overcharge (in-run cash sink), Core Overdrive (late
## coin sink via tier-raised core caps), S6/S7 eco->weapon feeders, run level cap.
func _fix_round_stages() -> void:
	# Core caps rise with tiers (late sink).
	var cs: Dictionary = BaseMeta.default_save()
	cs["coins"] = 1 << 40
	cs["core"]["hp"] = 15
	_check("core cap 15 at T1", BaseMeta.core_cap(cs) == 15 and not BaseMeta.try_core(cs, "hp"))
	cs["best_wave_by_tier"] = {"1": 40, "2": 50}
	_check("core cap +5 per tier (T3 = 25)", BaseMeta.core_cap(cs) == 25 and BaseMeta.try_core(cs, "hp") and int(cs["core"]["hp"]) == 16)
	# Overdrive: core levels above 15 compound max HP / regen / weapon dmg x1.1.
	var od: Dictionary = BaseMeta.default_save()
	od["best_wave_by_tier"] = {"1": 40, "2": 50}
	od["core"] = {"dmg": 0, "hp": 20, "regen": 0}
	var S = TowerState.new()
	S.setup(5, od)
	_check("Overdrive: hp lvl 20 -> (100+25*20) x 1.1^5", is_equal_approx(float(S.stats["max_hp"]), 600.0 * pow(1.1, 5.0)))
	od["core"] = {"dmg": 17, "hp": 0, "regen": 0}
	S = TowerState.new()
	S.setup(5, od)
	_check("Overdrive: dmg lvl 17 -> core dmg x 1.1^2", is_equal_approx(float(_weapon(S, "core")["dmg"]), 5.0 * (1.0 + 0.25 * 17.0) * pow(1.1, 2.0)))
	# Overcharge: each cash level on the core compounds ALL weapon damage.
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 1, "run": 0}
	S.recompute()
	var g0: float = float(_weapon(S, "gun")["dmg"])
	var c0: float = float(_weapon(S, "core")["dmg"])
	S.cash = 1000.0
	S.upgrade(TowerState.CORE_SLOT)
	S.upgrade(TowerState.CORE_SLOT)
	_check("Overcharge: 2 core cash levels -> all weapons x1.02^2 (core dmg 0)", S.core_run_lvl == 2 and is_equal_approx(float(_weapon(S, "gun")["dmg"]), g0 * 1.0404) and is_equal_approx(float(_weapon(S, "core")["dmg"]), c0 * 1.0404))
	_check("Overcharge cost 8 * 1.4^n", S.upgrade_cost(TowerState.CORE_SLOT) == int(8.0 * pow(1.4, 2.0)))
	var oc: Dictionary = BaseMeta.default_save()
	oc["core"] = {"dmg": 10, "hp": 0, "regen": 0}
	S = TowerState.new()
	S.setup(5, oc)
	_check("Overcharge step grows with perm Core DMG (0.02 + 0.006*L)", is_equal_approx(float(S.stats["overcharge_step"]), 0.08))
	# S6 Bounty Hunters / S7 Oil Shells.
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 1, "run": 0}
	S.recompute()
	g0 = float(_weapon(S, "gun")["dmg"])
	S.slots[_c(6)] = {"id": "bounty", "perm": 2, "run": 0}
	S.recompute()
	_check("S6 Bounty L2 feeds adjacent gun +10% dmg", is_equal_approx(float(_weapon(S, "gun")["dmg"]), g0 * 1.1) and _has_link(S, _c(6), _c(7), "S6"))
	S = _fresh()
	S.slots[_c(17)] = {"id": "mortar", "perm": 1, "run": 0}
	S.recompute()
	var m0: float = float(_weapon(S, "mortar")["dmg"])
	S.slots[_c(16)] = {"id": "oilmill", "perm": 3, "run": 0}
	S.slots[_c(18)] = {"id": "oilmill", "perm": 1, "run": 0}
	S.recompute()
	_check("S7 Oil Mills feed adjacent mortar +5%/lvl (3+1 -> +20%)", is_equal_approx(float(_weapon(S, "mortar")["dmg"]), m0 * 1.2) and _has_link(S, _c(16), _c(17), "S7"))
	S.slots[_c(12 - 5)] = {"id": "gun", "perm": 1, "run": 0}
	S.recompute()
	_check("S7 Oil Mill does not feed guns", not _has_link(S, _c(16), _c(7), "S7"))
	# Run level ceiling raised to 40 (late cash keeps converting).
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 39, "run": 0}
	S.recompute()
	S.cash = 1.0e9
	S.upgrade(_c(7))
	_check("run level cap 40", S.lvl_at(_c(7)) == 40 and S.upgrade(_c(7)).is_empty())
	# Enemy damage ramp 1.06/wave so HP (labs, perks, Overdrive) matters late.
	S = _fresh()
	S.wave = 41
	var sev: Array = []
	S._spawn("drone", sev)
	_check("enemy dmg ramp 1.06^(w-1)", is_equal_approx(float((S.enemies[S.enemies.size() - 1] as Dictionary)["dmg"]), 4.0 * pow(1.06, 40.0)))


## VFX/gameplay pass: per-weapon targeting modes, hit flash + dmg events,
## tier-5 wave-60 enemy cap stress.
func _juice_targeting_stages() -> void:
	var S = _fresh()
	S.enemies.clear()
	var from: Vector2 = TowerState.slot_pos(_c(7))
	# a: nearest to weapon, low hp, far from core
	var a: Dictionary = _enemy("drone", from + Vector2(0, -60), 5.0)
	# b: closest to core, mid hp
	var b: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(-90, 0), 50.0)
	# c: strongest, farther from weapon
	var c: Dictionary = _enemy("drone", from + Vector2(150, -120), 500.0)
	# d: out of range, would win every mode
	var d: Dictionary = _enemy("drone", from + Vector2(0, -2000), 1.0)
	S.enemies.append_array([a, b, c, d])
	_check("target nearest", S.pick_target(from, 400.0, "nearest") == 0)
	_check("target first (closest to core)", S.pick_target(from, 400.0, "first") == 1)
	_check("target strongest", S.pick_target(from, 400.0, "strongest") == 2)
	_check("target weakest", S.pick_target(from, 400.0, "weakest") == 0)
	_check("target none in range", S.pick_target(from + Vector2(0, -5000), 50.0, "first") == -1)
	# Per-slot modes: only weapon slots, cycle wraps, fire() uses the mode.
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 1, "run": 0}
	S.recompute()
	_check("default target mode nearest", String(S.target_modes[_c(7)]) == "nearest")
	_check("non-weapon slot rejects mode", S.set_target_mode(_c(3), "first").is_empty())
	var cev: Array = S.cycle_target_mode(_c(7))
	_check("cycle -> first + event", String(S.target_modes[_c(7)]) == "first" and cev.size() == 1 and String((cev[0] as Dictionary)["t"]) == "target_mode")
	S.cycle_target_mode(_c(7))
	S.cycle_target_mode(_c(7))
	S.cycle_target_mode(_c(7))
	_check("cycle wraps to nearest", String(S.target_modes[_c(7)]) == "nearest")
	S.set_target_mode(_c(7), "strongest")
	S.enemies.clear()
	var from7: Vector2 = TowerState.slot_pos(_c(7))
	var weak: Dictionary = _enemy("drone", from7 + Vector2(0, -40), 10.0)
	var strong: Dictionary = _enemy("drone", from7 + Vector2(0, -150), 900.0)
	S.enemies.append_array([weak, strong])
	for k in TowerState.N:
		S.cooldowns[k] = 99.0
	S.cooldowns[_c(7)] = 0.0
	var fev: Array = []
	S._fire(0.01, fev)
	_check("fire() honours strongest mode", float(strong["hp"]) < 900.0 and float(weak["hp"]) == 10.0)
	_check("hit sets hit_t flash + dmg event", float(strong["hit_t"]) > 0.0 and _evts(fev, "dmg").size() >= 1)
	_check("perm weapon mode persists in save", String((S.save["target_modes"] as Dictionary)[str(_c(7))]) == "strongest")
	var S2 = TowerState.new()
	S2.setup(77, S.save)
	_check("persisted mode restored next run", String(S2.target_modes[_c(7)]) == "strongest")
	# Stress: tier 5, wave 60, forced spawn flood for 10 s -> cap holds.
	S = _fresh()
	S.tier = 5
	S.hp_mult = 50.0
	S._enter_wave(60)
	S.min_spawn = 0.001
	S.spawn_base = 0.001
	S.stats["max_hp"] = 1.0e15
	S.hp = 1.0e15
	var peak: int = 0
	var t: float = 0.0
	while t < 10.0 and not S.over:
		S.tick(0.05)
		peak = maxi(peak, S.enemies.size())
		t += 0.05
		S.draft.clear()
		S.perk_offer.clear()
	_check("T5 w60 10 s flood: enemy count capped (peak %d)" % peak, peak <= TowerState.MAX_ENEMIES and peak > 50)


## PC ENGINE package (design/PC_SPEC.md §10 ENGINE, PC-E1..E9).
func _pc_engine_stages() -> void:
	_pc_board_stages()
	_pc_spawn_stages()
	_pc_building_stages()
	_pc_move_stages()
	_pc_mode_stages()
	_pc_stats_stages()


## PC-E1 7x7 ring unlocks, PC-E2 build cap.
func _pc_board_stages() -> void:
	_check("PC-E1 cell_ring 0..3", BaseMeta.cell_ring_rc(3, 3) == 0 and BaseMeta.cell_ring_rc(2, 4) == 1 and BaseMeta.cell_ring_rc(1, 3) == 2 and BaseMeta.cell_ring_rc(0, 6) == 3 and BaseMeta.cell_ring(TowerState.CORE_SLOT) == 0)
	var ring_n: Array = [0, 0, 0, 0]
	for i in TowerState.N:
		ring_n[BaseMeta.cell_ring(i)] = int(ring_n[BaseMeta.cell_ring(i)]) + 1
	_check("PC-E1 ring sizes 1/8/16/24", ring_n == [1, 8, 16, 24])
	var S = _fresh()
	var open_ok: bool = true
	for i in TowerState.N:
		open_ok = open_ok and bool(S.unlocked[i]) == (BaseMeta.cell_ring(i) == 1)
	_check("PC-E1 new save: exactly ring 1 unlocked", open_ok and S.free_slots().size() == 8)
	var sv: Dictionary = BaseMeta.default_save()
	var edge2: int = 1 * 7 + 3      # (1,3) ring 2 edge
	var corner2: int = 1 * 7 + 1    # (1,1) ring 2 corner
	var edge3: int = 0 * 7 + 3      # (0,3) ring 3 edge
	var corner3: int = 0            # (0,0) ring 3 corner
	_check("PC-E1 ring 2 cost 400, corner +50%", BaseMeta.unlock_cost(sv, edge2) == 400 and BaseMeta.unlock_cost(sv, corner2) == 600)
	_check("PC-E1 ring 3 cost 2500, corner +50%", BaseMeta.unlock_cost(sv, edge3) == 2500 and BaseMeta.unlock_cost(sv, corner3) == 3750)
	sv["coins"] = 1_000_000
	_check("PC-E1 ring 2 unlock", BaseMeta.try_unlock(sv, edge2) and int(sv["coins"]) == 1_000_000 - 400)
	_check("PC-E1 ring 2 price grows 1.18^n", BaseMeta.unlock_cost(sv, 1 * 7 + 2) == int(400.0 * 1.18) and BaseMeta.unlock_cost(sv, edge3) == 2500)
	var c3: int = int(sv["coins"])
	_check("PC-E1 ring 3 locked below T3 (no charge)", not BaseMeta.try_unlock(sv, edge3) and int(sv["coins"]) == c3 and not BaseMeta.is_unlocked(sv, edge3))
	sv["best_wave_by_tier"] = {"1": 40, "2": 50}
	_check("PC-E1 ring 3 unlocks at T3", Tiers.highest(sv) == 3 and BaseMeta.try_unlock(sv, edge3) and int(sv["coins"]) == c3 - 2500)
	_check("PC-E1 ring 3 price grows 1.22^n", BaseMeta.unlock_cost(sv, 0 * 7 + 2) == int(2500.0 * 1.22))
	_check("PC-E1 core / ring 1 cannot be bought", not BaseMeta.try_unlock(sv, TowerState.CORE_SLOT) and not BaseMeta.try_unlock(sv, 2 * 7 + 2))
	var S1 = TowerState.new()
	S1.setup(3, BaseMeta.default_save())
	S1.cash = 1.0e6
	_check("PC-E1 in-run unlock refuses ring 3 below T3", S1.unlock_plot(edge3).is_empty() and not bool(S1.unlocked[edge3]))
	_check("PC-E1 in-run unlock opens ring 2", not S1.unlock_plot(edge2).is_empty() and bool(S1.unlocked[edge2]))
	# PC-E2 build cap = 12 + 2(t-1), capped at 40.
	var cs: Dictionary = BaseMeta.default_save()
	_check("PC-E2 cap 12 at T1", BaseMeta.build_cap(cs) == 12)
	cs["best_wave_by_tier"] = {"1": 40, "2": 50}
	_check("PC-E2 cap 16 at T3", BaseMeta.build_cap(cs) == 16)
	cs["best_wave_by_tier"] = {"1": 999, "2": 999, "3": 999, "4": 999, "5": 999, "6": 999, "7": 999}
	_check("PC-E2 cap 26 at T8 (<= 40)", BaseMeta.build_cap(cs) == mini(40, 12 + 2 * 7))
	S = TowerState.new()
	S.setup(5, BaseMeta.default_save())
	S.spawn_hold = true
	for i in TowerState.N:
		S.unlocked[i] = i != TowerState.CORE_SLOT
	var placed: int = 0
	for i in TowerState.N:
		if i != TowerState.CORE_SLOT and placed < 12:
			S.slots[i] = {"id": "mine", "perm": 0, "run": 1}
			placed += 1
	S.recompute()
	S.pending_place = "gun"
	var free_i: int = int(S.free_slots()[0])
	var snap: String = JSON.stringify(S.slots)
	_check("PC-E2 place past cap returns [] and does not mutate", S.at_cap() and S.place(free_i).is_empty() and JSON.stringify(S.slots) == snap and S.pending_place == "gun")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var only_plus: bool = true
	for k in 50:
		for c in Draft.offer(rng, S.slots, S.unlocked, true, S.build_cap):
			only_plus = only_plus and String((c as Dictionary)["kind"]) == "plus"
	_check("PC-E2 draft offers no NEW cards at the cap", only_plus)
	var ps: Dictionary = BaseMeta.default_save()
	ps["coins"] = 1_000_000
	var pn: int = 0
	for i in TowerState.N:
		if BaseMeta.is_unlocked(ps, i) and BaseMeta.try_place(ps, i, "gun"):
			pn += 1
	ps["best_wave_by_tier"] = {"1": 0}
	for i in [1 * 7 + 3, 1 * 7 + 2, 1 * 7 + 4, 3 * 7 + 1, 3 * 7 + 5]:
		BaseMeta.try_unlock(ps, int(i))
		if BaseMeta.try_place(ps, int(i), "mine"):
			pn += 1
	_check("PC-E2 permanent base also capped at 12", pn == 12 and BaseMeta.building_count(ps) == 12)


## Strong run for long wave sims: huge core damage + HP so nothing dies.
func _godmode(S) -> void:
	S.dmg_mult = 1.0e6
	S.max_hp_mult = 1.0e9
	S.recompute()
	S.hp = float(S.stats["max_hp"])


## Ticks S through `waves` waves, returning every event in order with the
## game time it was emitted at (ev["_t"]).
func _sim_waves(S, waves: int, ev0: Array = []) -> Array:
	var out: Array = []
	for e in ev0:
		var d: Dictionary = (e as Dictionary).duplicate()
		d["_t"] = 0.0
		out.append(d)
	var guard: int = 0
	while S.wave <= waves and not S.over and guard < 200000:
		guard += 1
		for e in S.tick(0.05):
			var d2: Dictionary = (e as Dictionary).duplicate()
			d2["_t"] = S.time_alive
			out.append(d2)
		S.draft.clear()
		S.pending_place = ""
		S.perk_offer.clear()
	return out


## PC-E5 multi-direction spawns + telegraph.
func _pc_spawn_stages() -> void:
	var S = _fresh()
	var sched: bool = true
	for w in range(1, 120):
		var want: int = 1 if w < 10 else (2 if w < 25 else (3 if w < 50 else 4))
		sched = sched and S.quad_count(w) == want
	_check("PC-E5 quadrant schedule 1/2/3/4 at w1/10/25/50", sched)
	_check("PC-E5 quad_of sectors N/NE=0 E/SE=1 S/SW=2 W/NW=3", TowerState.quad_of(TowerState.CENTER + Vector2(0, -100)) == 0 and TowerState.quad_of(TowerState.CENTER + Vector2(70, -70)) == 0 and TowerState.quad_of(TowerState.CENTER + Vector2(100, 0)) == 1 and TowerState.quad_of(TowerState.CENTER + Vector2(70, 70)) == 1 and TowerState.quad_of(TowerState.CENTER + Vector2(0, 100)) == 2 and TowerState.quad_of(TowerState.CENTER + Vector2(-70, 70)) == 2 and TowerState.quad_of(TowerState.CENTER + Vector2(-100, 0)) == 3 and TowerState.quad_of(TowerState.CENTER + Vector2(-70, -70)) == 3)
	var runs: Array = []
	for rep in 2:
		var R = TowerState.new()
		var ev0: Array = R.setup(4321, BaseMeta.default_save())
		_godmode(R)
		runs.append({"S": R, "ev": _sim_waves(R, 26, ev0)})
	var evs: Array = runs[0]["ev"]
	var tele: Dictionary = {}
	var start_t: Dictionary = {}
	var quads_ok: bool = true
	var lead_ok: bool = true
	var order_ok: bool = true
	var counts_ok: bool = true
	var boss_ok: bool = false
	var dir_ok: bool = true
	for e in evs:
		var d: Dictionary = e
		match String(d["t"]):
			"wave_telegraph":
				var w: int = int(d["wave"])
				tele[w] = d
				quads_ok = quads_ok and (d["quadrants"] as Array).size() == runs[0]["S"].quad_count(w)
			"wave_start":
				var w2: int = int(d["wave"])
				start_t[w2] = float(d["_t"])
				if not tele.has(w2):
					order_ok = false
				else:
					var lead: float = float(d["_t"]) - float((tele[w2] as Dictionary)["_t"])
					lead_ok = lead_ok and absf(lead - TowerState.telegraph_s()) <= 0.06
			"boss":
				var bw: int = 0
				for k in start_t.keys():
					bw = maxi(bw, int(k))
				boss_ok = tele.has(bw) and int((tele[bw] as Dictionary)["boss_dir"]) == int(d["quad"]) and int(d["quad"]) >= 0
	# Spawned enemies of a wave all come from that wave's telegraphed quadrants.
	var S2 = TowerState.new()
	var e2: Array = S2.setup(99, BaseMeta.default_save())
	_godmode(S2)
	var last_tele: Dictionary = {}
	var seen_counts: Dictionary = {}
	for e in e2:
		if String((e as Dictionary)["t"]) == "wave_telegraph":
			last_tele[int((e as Dictionary)["wave"])] = e
	var guard: int = 0
	while S2.wave <= 12 and guard < 100000:
		guard += 1
		var n0: int = S2.enemies.size()
		for e in S2.tick(0.05):
			var d3: Dictionary = e
			if String(d3["t"]) == "wave_telegraph":
				last_tele[int(d3["wave"])] = d3
		S2.draft.clear()
		S2.pending_place = ""
		S2.perk_offer.clear()
		var aq: Array = S2.active_quads
		for k in range(n0, S2.enemies.size()):
			var en: Dictionary = S2.enemies[k]
			if String(en["kind"]) != "mite" and not aq.has(int(en["quad"])):
				dir_ok = false
		var lw: Dictionary = S2.last_wave_spawned
		if not lw.is_empty() and not seen_counts.has(int(lw["wave"])):
			seen_counts[int(lw["wave"])] = true
			var tc: Dictionary = (last_tele[int(lw["wave"])] as Dictionary)["counts"]
			var sc: Dictionary = lw["counts"]
			for q in tc.keys():
				counts_ok = counts_ok and int(tc[q]) == int(sc.get(int(q), 0))
			for q2 in sc.keys():
				counts_ok = counts_ok and tc.has(q2)
	_check("PC-E5 telegraph quadrant count follows the schedule", quads_ok and tele.has(1) and tele.has(10) and tele.has(25))
	_check("PC-E5 wave_telegraph precedes wave_start by pc_telegraph_s", order_ok and lead_ok and start_t.size() >= 25)
	_check("PC-E5 telegraph counts == actual spawns per quadrant", counts_ok and seen_counts.size() >= 10)
	_check("PC-E5 spawns come only from active quadrants", dir_ok)
	_check("PC-E5 boss comes from the telegraphed boss_dir", boss_ok)
	var a_dirs: Array = []
	var b_dirs: Array = []
	for e in runs[0]["ev"]:
		if String((e as Dictionary)["t"]) == "wave_telegraph":
			a_dirs.append([(e as Dictionary)["quadrants"], (e as Dictionary)["counts"], (e as Dictionary)["boss_dir"]])
	for e in runs[1]["ev"]:
		if String((e as Dictionary)["t"]) == "wave_telegraph":
			b_dirs.append([(e as Dictionary)["quadrants"], (e as Dictionary)["counts"], (e as Dictionary)["boss_dir"]])
	_check("PC-E5 same seed -> same directions", a_dirs.size() >= 25 and JSON.stringify(a_dirs) == JSON.stringify(b_dirs))
	S = _fresh()
	_check("PC-E5 lane focus", S.set_focus(2).size() == 1 and S.focus_quad == 2 and S.set_focus(7).is_empty() and S.focus_quad == 2)


## A run with every cell unlocked and nothing firing on its own.
func _open_run():
	var S = _fresh()
	for i in TowerState.N:
		S.unlocked[i] = i != TowerState.CORE_SLOT
	S.spawn_hold = true
	return S


func _rc(r: int, c: int) -> int:
	return r * TowerState.SIDE + c


## PC-E3 new buildings + synergies S8-S11.
func _pc_building_stages() -> void:
	var r2: int = _rc(1, 3)     # ring 2, north lane
	var r1: int = _rc(2, 3)     # ring 1, north
	var S = _open_run()
	S.pending_place = "railgun"
	_check("PC-E3 railgun rejected on ring 1", S.place(r1).is_empty() and S.id_at(r1) == "")
	_check("PC-E3 railgun placed on ring 2", not S.place(r2).is_empty() and S.id_at(r2) == "railgun")
	var bs: Dictionary = BaseMeta.default_save()
	bs["coins"] = 1000
	_check("PC-E3 perm railgun rejected on ring 1", not BaseMeta.try_place(bs, r1, "railgun") and int(bs["coins"]) == 1000)
	# S8 Capacitor Bank: +20% per 5 Tesla levels, capped at +60%.
	S = _open_run()
	S.slots[r2] = {"id": "railgun", "perm": 1, "run": 0}
	S.recompute()
	var rd0: float = float(_weapon(S, "railgun")["dmg"])
	_check("PC-E3 railgun base dmg 30+18L", is_equal_approx(rd0, 48.0))
	S.slots[_rc(5, 3)] = {"id": "tesla", "perm": 10, "run": 0}
	S.recompute()
	_check("PC-E3 S8 needs adjacency (+0)", is_equal_approx(float(_weapon(S, "railgun")["dmg"]), rd0) and not _has_link(S, _rc(5, 3), r2, "S8"))
	S.slots[_rc(1, 4)] = {"id": "tesla", "perm": 5, "run": 0}
	S.recompute()
	_check("PC-E3 S8 Tesla L5 adjacent: +20%", is_equal_approx(float(_weapon(S, "railgun")["dmg"]), rd0 * 1.2) and _has_link(S, _rc(1, 4), r2, "S8"))
	S.slots[_rc(1, 2)] = {"id": "tesla", "perm": 10, "run": 0}
	S.recompute()
	_check("PC-E3 S8 capped at +60%", is_equal_approx(float(_weapon(S, "railgun")["dmg"]), rd0 * 1.6))
	# Railgun pierces along its line.
	S = _open_run()
	S.slots[r2] = {"id": "railgun", "perm": 1, "run": 0}
	S.recompute()
	S.stats["weapons"] = [_weapon(S, "railgun")]
	var rpos: Vector2 = TowerState.slot_pos(r2)
	var on1: Dictionary = _enemy("hauler", rpos + Vector2(0, -100))
	var on2: Dictionary = _enemy("hauler", rpos + Vector2(0, -200))
	var off: Dictionary = _enemy("hauler", rpos + Vector2(80, -150))
	S.enemies.append_array([on1, on2, off])
	var fev: Array = []
	S._fire(0.01, fev)
	_check("PC-E3 railgun pierces the line, misses off-line", float(on1["hp"]) < 999.0 and float(on2["hp"]) < 999.0 and is_equal_approx(float(off["hp"]), 999.0))
	# Flak: splash, x1.5 vs light prey.
	S = _open_run()
	S.slots[r1] = {"id": "flak", "perm": 2, "run": 0}
	S.recompute()
	var fl: Dictionary = _weapon(S, "flak")
	_check("PC-E3 flak dmg 2+1L, no crit alone", is_equal_approx(float(fl["dmg"]), 4.0) and is_equal_approx(float(fl["crit"]), 0.0))
	S.stats["weapons"] = [fl]
	var fpos: Vector2 = TowerState.slot_pos(r1) + Vector2(0, -120)
	var prey: Dictionary = _enemy("drone", fpos)
	var heavy: Dictionary = _enemy("hauler", fpos + Vector2(10, 0))
	S.enemies.append_array([prey, heavy])
	S.focus_quad = 2
	fev = []
	S._fire(0.01, fev)
	_check("PC-E3 flak splash x1.5 vs drone, x1 vs hauler", is_equal_approx(999.0 - float(prey["hp"]), 6.0) and is_equal_approx(999.0 - float(heavy["hp"]), 4.0))
	# S9 Crossfire: Flak next to a Gun -> both +10% crit.
	S = _open_run()
	S.slots[r1] = {"id": "flak", "perm": 1, "run": 0}
	S.slots[_rc(2, 2)] = {"id": "gun", "perm": 1, "run": 0}
	S.slots[_rc(5, 5)] = {"id": "gun", "perm": 1, "run": 0}
	S.recompute()
	var gun_adj: float = -1.0
	var gun_far: float = -1.0
	for w in S.stats["weapons"]:
		if String(w["kind"]) == "gun":
			if int(w["slot"]) == _rc(2, 2):
				gun_adj = float(w["crit"])
			else:
				gun_far = float(w["crit"])
	_check("PC-E3 S9 Crossfire +10% crit both, 0 when apart", is_equal_approx(float(_weapon(S, "flak")["crit"]), 0.1) and is_equal_approx(gun_adj, 0.1) and is_equal_approx(gun_far, 0.0) and _has_link(S, r1, _rc(2, 2), "S9"))
	var cw: Dictionary = _weapon(S, "flak").duplicate()
	cw["crit"] = 1.0
	S.stats["weapons"] = [cw]
	var ce: Dictionary = _enemy("hauler", TowerState.slot_pos(r1) + Vector2(0, -100))
	S.enemies = [ce]
	fev = []
	S._fire(0.01, fev)
	var dm: Array = _evts(fev, "dmg")
	_check("PC-E3 crit hit doubles dmg + flags the event", dm.size() == 1 and bool((dm[0] as Dictionary).get("crit", false)) and is_equal_approx(999.0 - float(ce["hp"]), 2.0 * float(cw["dmg"])))
	# Beacon: +15%/lv vs the focused lane; S10 Spotter on an adjacent Mortar.
	S = _open_run()
	S.slots[_rc(4, 4)] = {"id": "beacon", "perm": 2, "run": 0}
	S.slots[_rc(2, 2)] = {"id": "mortar", "perm": 1, "run": 0}
	S.recompute()
	var mr0: float = float(_weapon(S, "mortar")["range"])
	_check("PC-E3 beacon +15%/lv", is_equal_approx(float(S.stats["beacon"]), 0.30) and not _has_link(S, _rc(4, 4), _rc(2, 2), "S10"))
	var fq: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, -250))
	var oq: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 250))
	S.set_focus(0)
	var hev: Array = []
	S._hit(fq, 10.0, hev)
	S._hit(oq, 10.0, hev)
	_check("PC-E3 beacon bonus only on the focused lane", is_equal_approx(999.0 - float(fq["hp"]), 13.0) and is_equal_approx(999.0 - float(oq["hp"]), 10.0))
	S.slots[_rc(2, 1)] = {"id": "beacon", "perm": 1, "run": 0}
	S.recompute()
	_check("PC-E3 S10 Spotter: adjacent mortar +25% range", is_equal_approx(float(_weapon(S, "mortar")["range"]), mr0 * 1.25) and _has_link(S, _rc(2, 1), _rc(2, 2), "S10"))
	# Refinery: 10% of the wave's cash income -> coins (cap 5/lv); S11 Smelter.
	S = _open_run()
	S.slots[r1] = {"id": "refinery", "perm": 2, "run": 0}
	S.slots[_rc(5, 5)] = {"id": "mine", "perm": 1, "run": 0}
	S.recompute()
	var m_far: float = float(S.stats["cash_ps"])
	S.wave_cash0 = 0.0
	S.cash_earned = 30.0
	var c0: float = S.coins_run
	var rev: Array = []
	S._wave_end(rev)
	_check("PC-E3 refinery converts 10% of wave income", is_equal_approx(S.coins_run - c0, 3.0) and _evts(rev, "refined").size() == 1)
	S.cash_earned = 1000.0
	c0 = S.coins_run
	S._wave_end([])
	_check("PC-E3 refinery cap 5 coins/lv/wave", is_equal_approx(S.coins_run - c0, 10.0))
	S.slots[_rc(5, 5)] = {}
	S.slots[_rc(2, 2)] = {"id": "mine", "perm": 1, "run": 0}
	S.recompute()
	_check("PC-E3 S11 Smelter: adjacent mine +20%", is_equal_approx(float(S.stats["cash_ps"]), m_far * 1.2) and _has_link(S, r1, _rc(2, 2), "S11"))
	S.slots[_rc(1, 3)] = {"id": "aegis", "perm": 1, "run": 0}
	S.recompute()
	_check("PC-E3 aegis -15% hits the refinery", is_equal_approx(float((S.stats["refineries"] as Array)[0]["rate"]), 0.085))
	# Barricade: lane wall, -30% speed, 60 HP/lv, rebuilt each wave.
	S = _open_run()
	S.stats["weapons"] = []
	S.slots[r2] = {"id": "barricade", "perm": 2, "run": 0}
	S.recompute()
	S.stats["weapons"] = []
	_check("PC-E3 barricade wall on its lane, 60 HP/lv", TowerState.cell_quad(r2) == 0 and S.walls.has(0) and is_equal_approx(float(S.walls[0]["hp"]), 120.0))
	var wn: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, -260))
	wn["quad"] = 0
	var ws: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, 260))
	ws["quad"] = 2
	S.enemies = [wn, ws]
	S._move_enemies(0.1, [])
	var dn: float = 260.0 - (wn["pos"] as Vector2).distance_to(TowerState.CENTER)
	var ds: float = 260.0 - (ws["pos"] as Vector2).distance_to(TowerState.CENTER)
	_check("PC-E3 wall slows its lane 30%, other lanes free", is_equal_approx(dn, ds * 0.7) and float(S.walls[0]["hp"]) < 120.0)
	wn["dmg"] = 5000.0
	var wev: Array = []
	S._move_enemies(0.1, wev)
	_check("PC-E3 wall breaks under damage", _evts(wev, "wall_broken").size() == 1 and float(S.walls[0]["hp"]) == 0.0)
	S.enemies.clear()
	S.wave_t = S.wave_time - 0.001
	wev = S.tick(0.01)
	_check("PC-E3 wall rebuilt next wave", _evts(wev, "wall_up").size() == 1 and is_equal_approx(float(S.walls[0]["hp"]), 120.0))
	# Outer rings reach further (+8% per ring past 1).
	S = _open_run()
	S.slots[r1] = {"id": "gun", "perm": 1, "run": 0}
	S.slots[_rc(0, 3)] = {"id": "gun", "perm": 1, "run": 0}
	S.recompute()
	var rg1: float = 0.0
	var rg3: float = 0.0
	for w in S.stats["weapons"]:
		if String(w["kind"]) == "gun":
			if int(w["slot"]) == r1:
				rg1 = float(w["range"])
			else:
				rg3 = float(w["range"])
	_check("PC-E3 ring range bonus +8%/ring", rg1 > 0.0 and is_equal_approx(rg3, rg1 * 1.16))
	var ids_ok: bool = true
	for id in ["railgun", "flak", "beacon", "refinery", "barricade"]:
		ids_ok = ids_ok and BuildingDB.all_ids().has(id) and String(BuildingDB.get_def(id).get("desc", "")) != ""
	_check("PC-E3 15 buildings in the DB", ids_ok and BuildingDB.all_ids().size() == 15)


## PC-E4 move / swap buildings.
func _pc_move_stages() -> void:
	var S = _open_run()
	var a: int = _rc(2, 3)
	var b: int = _rc(2, 2)
	var c: int = _rc(2, 4)
	S.slots[a] = {"id": "gun", "perm": 0, "run": 3}
	S.slots[c] = {"id": "mine", "perm": 0, "run": 1}
	S.recompute()
	S.cash = 100.0
	var mev: Array = S.move_building(a, b)
	_check("PC-E4 free move between waves + event", mev.size() == 1 and String(mev[0]["t"]) == "building_moved" and S.id_at(b) == "gun" and S.id_at(a) == "" and S.lvl_at(b) == 3 and is_equal_approx(S.cash, 100.0))
	mev = S.move_building(b, c)
	_check("PC-E4 move onto a building swaps", mev.size() == 1 and S.id_at(c) == "gun" and S.id_at(b) == "mine" and String(mev[0]["swapped"]) == "mine")
	S.enemies.append(_enemy("drone", TowerState.CENTER + Vector2(0, -300)))
	var val: int = S.building_value(c)
	var cost: int = S.move_cost(c, a)
	_check("PC-E4 in-wave move costs 10% of value", cost == int(ceil(0.1 * float(val))) and cost > 0)
	var cash0: float = S.cash
	S.move_building(c, a)
	_check("PC-E4 in-wave move charges cash", S.id_at(a) == "gun" and is_equal_approx(S.cash, cash0 - float(cost)))
	cash0 = S.cash
	S.move_building(a, c, true)
	_check("PC-E4 paused move is free", S.id_at(c) == "gun" and is_equal_approx(S.cash, cash0))
	S.cash = 0.0
	_check("PC-E4 broke in-wave move refused", S.move_building(c, a).is_empty() and S.id_at(c) == "gun")
	S.enemies.clear()
	S.slots[_rc(1, 3)] = {"id": "railgun", "perm": 1, "run": 0}
	S.recompute()
	_check("PC-E4 railgun cannot move inside ring 2", S.move_building(_rc(1, 3), _rc(3, 2)).is_empty() and S.move_building(_rc(1, 3), b).is_empty())
	_check("PC-E4 core / locked cells refused", S.move_building(c, TowerState.CORE_SLOT).is_empty())
	var bs: Dictionary = BaseMeta.default_save()
	bs["coins"] = 1000
	BaseMeta.try_place(bs, a, "gun")
	BaseMeta.try_place(bs, c, "mine")
	_check("PC-E4 base move + swap", BaseMeta.try_move(bs, a, b) and String(BaseMeta.slot_of(bs, b)["id"]) == "gun" and BaseMeta.try_move(bs, b, c) and String(BaseMeta.slot_of(bs, c)["id"]) == "gun" and String(BaseMeta.slot_of(bs, b)["id"]) == "mine" and not BaseMeta.try_move(bs, c, _rc(0, 0)))


func _mod_run(mods: Array, sv: Dictionary = {}, seed_value: int = 1234):
	var S = TowerState.new()
	S.setup(seed_value, BaseMeta.normalize(sv), 0, {"modifiers": mods})
	return S


## PC-E6 challenge modifiers, PC-E7 endless mode.
func _pc_mode_stages() -> void:
	_check("PC-E6 coin mult = min(3, 1 + sum)", is_equal_approx(ModifierDB.coin_mult(["glass"]), 1.4) and is_equal_approx(ModifierDB.coin_mult(["glass", "haste"]), 1.7) and is_equal_approx(ModifierDB.coin_mult(ModifierDB.IDS), 3.0) and is_equal_approx(ModifierDB.coin_mult(["bogus"]), 1.0))
	var S0 = _mod_run([])
	var S = _mod_run(["glass", "haste", "bogus", "glass"])
	_check("PC-E6 modifiers cleaned + run coin mult applied", S.modifiers == ["glass", "haste"] and is_equal_approx(S.coin_mult, S0.coin_mult * 1.7) and is_equal_approx(S.run_coin_mult(), S0.run_coin_mult() * 1.7))
	_check("PC-E6 Glass Core: max HP -50%", is_equal_approx(float(S.stats["max_hp"]), 50.0) and is_equal_approx(S.hp, 50.0))
	S.spawn_hold = true
	S._spawn("drone", [])
	_check("PC-E6 Haste: enemy speed +25%", is_equal_approx(float(S.enemies[0]["spd"]), 45.0 * 1.25))
	S = _mod_run(["swarm"])
	S.spawn_hold = true
	S._spawn("drone", [])
	var p0: int = int(S0._build_plan(3, 0.0)["entries"].size())
	var p1: int = int(S._build_plan(3, 0.0)["entries"].size())
	_check("PC-E6 Swarm: -30% HP each, +60% count", is_equal_approx(float(S.enemies[0]["hp"]), 6.0 * 0.7) and float(p1) >= 1.5 * float(p0) and float(p1) <= 1.7 * float(p0))
	S = _mod_run(["ironclad"])
	var e1: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 300))
	var e2: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 300))
	S._hit(e1, 10.0, [])
	S._hit(e2, 10.0, [], true)
	_check("PC-E6 Ironclad: non-crit -20%, crit full", is_equal_approx(999.0 - float(e1["hp"]), 8.0) and is_equal_approx(999.0 - float(e2["hp"]), 10.0))
	var lab: Dictionary = BaseMeta.default_save()
	lab["labs"]["lvls"]["startcash"] = 2
	lab["labs"]["lvls"]["dmg"] = 4
	var SL = _mod_run([], lab)
	S = _mod_run(["poverty"], lab)
	_check("PC-E6 Austerity: start cash 0", is_equal_approx(SL.cash, 30.0) and is_equal_approx(S.cash, 0.0))
	S.spawn_hold = true
	S.enemies.append(_enemy("drone", TowerState.CENTER + Vector2(0, 300), 0.0))
	S._reap([])
	_check("PC-E6 Austerity: kill cash -30%", is_equal_approx(S.cash, 1.0 * 0.7))
	S = _mod_run(["allsides"])
	_check("PC-E6 Encircled: 4 lanes from wave 1", S.active_quads.size() == 4 and S.quad_count(1) == 4)
	S = _mod_run(["noperks"])
	S.spawn_hold = true
	S.wave = 4
	S.wave_t = S.wave_time - 0.001
	var pev: Array = S.tick(0.01)
	_check("PC-E6 Purist suppresses perk_offer", S.wave == 5 and _evts(pev, "perk_offer").is_empty() and S.perk_offer.is_empty() and S.perk_pending == 0)
	S = _mod_run(["elitist"])
	var el: bool = false
	S.wave = 10
	for k in 2000:
		el = el or S._roll_kind() == "elite"
	var el0: bool = false
	S0.wave = 10
	for k in 2000:
		el0 = el0 or S0._roll_kind() == "elite"
	_check("PC-E6 Elite Guard: elites from T1", el and not el0)
	S = _mod_run(["nolabs"], lab)
	_check("PC-E6 Fresh Start: lab bonuses off", is_equal_approx(float(_weapon(S, "core")["dmg"]), float(_weapon(S0, "core")["dmg"])) and float(_weapon(SL, "core")["dmg"]) > float(_weapon(S0, "core")["dmg"]) and is_equal_approx(S.cash, 0.0))
	# PC-E7 endless.
	var es: Dictionary = BaseMeta.default_save()
	es["best_wave_by_tier"] = {"1": 49}
	es = BaseMeta.normalize(es)
	var E = TowerState.new()
	var eev: Array = E.setup(5, es, 0, {"mode": "endless"})
	_check("PC-E7 endless locked below wave 50", E.mode == "normal" and _evts(eev, "endless_locked").size() == 1 and not BaseMeta.endless_unlocked(es))
	es["best_wave_by_tier"] = {"1": 50}
	es = BaseMeta.normalize(es)
	var N0 = TowerState.new()
	N0.setup(5, es)
	E = TowerState.new()
	E.setup(5, es, 0, {"mode": "endless"})
	_check("PC-E7 endless unlocked at wave 50, coins x0.8", E.mode == "endless" and is_equal_approx(E.coin_mult, N0.coin_mult * 0.8))
	E.spawn_hold = true
	E.wave = 24
	E.wave_t = E.wave_time - 0.001
	var mev: Array = E.tick(0.01)
	var mo: Array = _evts(mev, "mutation_offer")
	_check("PC-E7 mutation offer at wave 25 (3 distinct)", E.wave == 25 and mo.size() == 1 and E.mutation_offer.size() == 3 and E.mutation_offer[0] != E.mutation_offer[1] and E.mutation_offer[1] != E.mutation_offer[2] and is_equal_approx(E.time_scale(), 0.2))
	E.mutation_offer = ["m_vigor", "m_rush", "m_horde"]
	var cm0: float = E.run_coin_mult()
	var tk: Array = E.choose_mutation(0)
	E._spawn("drone", [])
	var vh: float = float(E.enemies[E.enemies.size() - 1]["hp"]) / E.scale()
	_check("PC-E7 mutation pays +10% coins and buffs enemies", _evts(tk, "mutation_taken").size() == 1 and is_equal_approx(E.run_coin_mult(), cm0 * 1.1) and is_equal_approx(vh, 6.0 * 1.2) and E.mutation_offer.is_empty())
	N0.mode = "normal"
	N0.wave = 49
	N0.wave_t = N0.wave_time - 0.001
	N0.spawn_hold = true
	_check("PC-E7 normal mode never offers mutations", _evts(N0.tick(0.01), "mutation_offer").is_empty())
	E.wave = 120
	_check("PC-E7 soft HP exponent past wave 100", is_equal_approx(E.scale(), pow(E.hp_growth, 99.0) * pow(1.12, 20.0)))
	E.wave = 130
	E.wave_t = E.wave_time - 0.001
	E.mutation_offer.clear()
	E.tick(0.01)
	_check("PC-E7 no wave cap", E.wave == 131 and not E.over)
	var bw_before: Dictionary = (es["best_wave_by_tier"] as Dictionary).duplicate()
	E.hp = -1.0
	E.stats["regen"] = 0.0
	var dev: Array = E.tick(0.01)
	var go: Array = _evts(dev, "game_over")
	_check("PC-E7 endless banks its own best, not the tier ladder", E.over and go.size() == 1 and String(go[0]["mode"]) == "endless" and int(es["endless"]["best"]) == 131 and JSON.stringify(es["best_wave_by_tier"]) == JSON.stringify(bw_before))


## Deterministic hands-on run for `waves` waves; returns the JSON of every
## event (the retry-seed fingerprint).
func _run_fingerprint(sv: Dictionary, opts: Dictionary, waves: int) -> String:
	var R = TowerState.new()
	var evs: Array = R.setup(int(opts.get("seed", 0)), sv, 0, opts)
	R.max_hp_mult = 1.0e6
	R.recompute()
	R.hp = float(R.stats["max_hp"])
	var guard: int = 0
	while R.wave <= waves and not R.over and guard < 100000:
		guard += 1
		evs.append_array(R.tick(0.1))
		if R.draft.size() > 0:
			evs.append_array(R.choose_card(0))
		if R.pending_place != "" and R.free_slots().size() > 0:
			evs.append_array(R.place(int(R.free_slots()[0])))
		if R.perk_offer.size() > 0:
			evs.append_array(R.choose_perk(0))
	var keep: Array = []
	for e in evs:
		var d: Dictionary = e
		if String(d["t"]) == "wave" and int(d["wave"]) > waves:
			break
		keep.append(d)
	return JSON.stringify(keep)


## PC-E8 lifetime stats + run history + retry seed.
func _pc_stats_stages() -> void:
	var s: Dictionary = BaseMeta.default_save()
	var st0: String = JSON.stringify(s["stats"])
	var R = _fresh(s)
	_check("PC-E8 a run does not touch stats by itself", JSON.stringify(R.save["stats"]) == st0)
	var evs: Array = [{"t": "kill", "kind": "skitter"}, {"t": "kill", "kind": "skitter"}, {"t": "kill", "kind": "boss"}, {"t": "boss_bounty", "coins": 5}, {"t": "wave", "wave": 2}, {"t": "wave", "wave": 3}, {"t": "placed", "slot": 17, "id": "gun"}, {"t": "placed", "slot": 18, "id": "gun"}, {"t": "placed", "slot": 19, "id": "mine"}]
	Stats.on_events(s, evs)
	Stats.on_event(s, {"t": "game_over", "wave": 33, "coins": 120, "duration_s": 600.0, "seed": 9, "tier": 2, "mode": "normal", "modifiers": ["glass"], "build": ["gun"], "perks": ["p_dmg"], "ts": 77, "dps": 55.5})
	var st: Dictionary = s["stats"]
	_check("PC-E8 kills by kind + bosses + waves", int(st["kills"]) == 3 and int(st["kills_by_kind"]["skitter"]) == 2 and int(st["kills_by_kind"]["boss"]) == 1 and int(st["bosses"]) == 1 and int(st["waves"]) == 2)
	_check("PC-E8 placed by id + favourite", int(st["placed"]["gun"]) == 2 and Stats.favourite(s, 2) == ["gun", "mine"])
	_check("PC-E8 game_over: runs, play time, coins, best by mode, dps", int(st["runs"]) == 1 and is_equal_approx(float(st["play_s"]), 600.0) and int(st["coins_earned"]) == 120 and int(st["best_by_mode"]["challenge"]) == 33 and int(st["best_by_mode"]["normal"]) == 0 and is_equal_approx(float(st["dps_best"]), 55.5))
	var h: Array = s["history"]
	_check("PC-E8 history entry recorded", h.size() == 1 and int(h[0]["seed"]) == 9 and int(h[0]["wave"]) == 33 and (h[0]["modifiers"] as Array) == ["glass"] and int(h[0]["tier"]) == 2)
	var sp: Dictionary = BaseMeta.default_save()
	sp["coins"] = 5000
	BaseMeta.try_place(sp, _rc(2, 3), "gun")
	BaseMeta.try_core(sp, "dmg")
	_check("PC-E8 coins_spent fed by BaseMeta spends", int(sp["stats"]["coins_spent"]) == 15 + 30)
	var M: Dictionary = BaseMeta.default_save()
	Missions.on_run_events(M, [{"t": "kill", "kind": "drone"}, {"t": "boss_bounty"}])
	_check("PC-E8 Missions forwards run events to Stats once", int(M["stats"]["kills"]) == 1 and int(M["stats"]["kills_by_kind"]["drone"]) == 1 and int(M["stats"]["bosses"]) == 1)
	for k in 50:
		Stats.on_event(s, {"t": "game_over", "wave": 10 + k, "coins": 1, "seed": 100 + k})
	h = s["history"]
	_check("PC-E8 history ring buffer keeps 50, 51st evicts the oldest", h.size() == 50 and int(h[0]["seed"]) == 100 and int(h[49]["seed"]) == 149)
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(s)))
	_check("PC-E8 stats + history survive JSON + normalize", JSON.stringify(rt["stats"]) == JSON.stringify(BaseMeta.normalize(s)["stats"]) and (rt["history"] as Array).size() == 50 and int(rt["stats"]["kills_by_kind"]["skitter"]) == 2)
	# Retry the same seed from history: identical first 10 waves.
	var base: Dictionary = BaseMeta.default_save()
	var A = TowerState.new()
	A.setup(31337, base.duplicate(true), 0, {"modifiers": ["haste"]})
	var gev: Array = A.abandon()
	Stats.on_events(base, gev)
	var entry: Dictionary = (base["history"] as Array)[0]
	var ro: Dictionary = Stats.retry_opts(entry)
	var f1: String = _run_fingerprint(BaseMeta.default_save(), {"seed": 31337, "modifiers": ["haste"]}, 10)
	var f2: String = _run_fingerprint(BaseMeta.default_save(), ro, 10)
	var f3: String = _run_fingerprint(BaseMeta.default_save(), {"seed": 31338, "modifiers": ["haste"]}, 10)
	_check("PC-E8 retry seed reproduces the first 10 waves", int(ro["seed"]) == 31337 and f1.length() > 1000 and f1.hash() == f2.hash() and f1 == f2 and f1 != f3)
