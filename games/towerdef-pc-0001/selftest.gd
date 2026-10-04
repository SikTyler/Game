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
const Settings := preload("res://Settings.gd")
const Keybinds := preload("res://Keybinds.gd")
const SteamService := preload("res://SteamService.gd")
const Achievements := preload("res://Achievements.gd")
const AchievementDB := preload("res://data/AchievementDB.gd")
const TuneRef := preload("res://Tune.gd")
const PowerModel := preload("res://PowerModel.gd")
const PickDB := preload("res://data/PickDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const Cores := preload("res://Cores.gd")
const Specials := preload("res://Specials.gd")
const Troops := preload("res://Troops.gd")
const Drops := preload("res://Drops.gd")
const Parts := preload("res://Parts.gd")
const PartDB := preload("res://data/PartDB.gd")
const SetDB := preload("res://data/SetDB.gd")
const Crates := preload("res://Crates.gd")
const CrateDB := preload("res://data/CrateDB.gd")
const Outpost := preload("res://Outpost.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")

var fails: Array = []


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails.append(name)
		print("SELFTEST FAIL: " + name + ("" if detail == "" else "  [" + detail + "]"))


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
	# REDESIGN: the Core's HP comes from its CoreDB sheet (Bastion L1 = 120).
	_check("setup: full hp (Bastion sheet)", is_equal_approx(S.hp, 120.0) and S.core_id == "bastion" and S.core_lvl == 1)
	_check("setup: inner ring unlocked, outer locked", bool(S.unlocked[_c(6)]) and not bool(S.unlocked[_c(0)]) and not bool(S.unlocked[_c(12)]))
	_check("setup: 8 free slots", S.free_slots().size() == 8)
	_check("setup: core is the only weapon", (S.stats["weapons"] as Array).size() == 1)

	# --- Stage 2: stats math + adjacency -------------------------------------
	# REDESIGN (deliberate): building numbers follow REDESIGN_SYSTEMS §2.3
	# (L1 sheet, +35% main stat per level); Armory is +15% to neighbours.
	S.slots[_c(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	var gun_dmg: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	_check("gatling L1 6 dmg x building scale (Steadfast-free)", is_equal_approx(gun_dmg, 6.0 * TowerState.bld_dmg()))
	S.slots[_c(6)] = {"id": "armory", "perm": 0, "run": 1}   # adjacent to gun (7) and core (12)
	S.recompute()
	var buffed: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	_check("armory buffs adjacent gun +15%", is_equal_approx(buffed, gun_dmg * 1.15) and _has_link(S, _c(6), _c(7), "ARM"))
	S.slots[_c(0)] = {"id": "armory", "perm": 0, "run": 1}   # NOT adjacent to 7
	S.recompute()
	_check("armory does not buff non-adjacent", is_equal_approx(float((S.stats["weapons"] as Array)[0]["dmg"]), buffed))
	S = _fresh()
	S.slots[_c(16)] = {"id": "mine", "perm": 0, "run": 2}
	S.slots[_c(18)] = {"id": "bulwark", "perm": 0, "run": 1}
	S.recompute()
	_check("mine L2 cash/s = Core 2.0 + 0.8x1.35, Steadfast +1%/building", is_equal_approx(float(S.stats["cash_ps"]), (2.0 + 0.8 * 1.35) * 1.02))
	_check("bulwark raises max hp +40", is_equal_approx(float(S.stats["max_hp"]), 160.0))
	_check("bulwark heals by its bonus", is_equal_approx(S.hp, 160.0))

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
	_check("enemy at wall hits core (10 dmg - 2 armor)", S.hp < 120.0 and S.hp > 111.0)

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

	# --- Stage 6: draft → place, plus-card, determinism -----------------------
	# REDESIGN (deliberate): drafts follow the wave cadence (after w1/2/3, then
	# every 2nd + boss), not XP; an XP level-up banks a free reroll instead.
	S = _fresh()
	S.spawn_hold = true
	S.xp = S.xp_need()
	ev = S.tick(0.01)
	_check("XP level-up banks a reroll, opens no draft", S.level == 2 and S.draft.is_empty() and S.rerolls_left == 1 and _evts(ev, "levelup").size() == 1)
	S.wave_t = S.wave_time - 0.001
	ev = S.tick(0.01)
	_check("wave 1 cleared opens a 3-card draft", S.wave == 2 and S.draft.size() == 3 and _evts(ev, "draft_offer").size() == 1)
	var eco_n: int = 0
	for c in S.draft:
		if (c["tags"] as Array).has("eco"):
			eco_n += 1
	_check("G1 draft offers eco AND non-eco", eco_n >= 1 and eco_n <= 2)
	_check("draft slows time", is_equal_approx(S.time_scale(), 0.2))
	S.draft = [Draft.card_for("mortar", S._draft_ctx("")), Draft.card_for("mine", S._draft_ctx("")), Draft.card_for("pk_arsenal", S._draft_ctx(""))]
	var card: Dictionary = S.draft[0]
	S.choose_card(0)
	_check("new card enters place mode", S.pending_place == String(card["id"]) and S.draft.is_empty())
	S.place(_c(0))  # locked — rejected
	_check("cannot place on locked slot", S.pending_place != "")
	ev = S.place(_c(6))
	_check("placed building in free slot", S.id_at(_c(6)) == "mortar" and S.pending_place == "" and is_equal_approx(S.time_scale(), 1.0))
	S.grant_draft()
	var plus: Dictionary = Draft.card_for("mortar", S._draft_ctx(""))
	_check("owned building offers only a plus card (Lv1 -> 2)", String(plus["kind"]) == "plus" and int(plus["lvl"]) == 1 and int(plus["to"]) == 2)
	S.draft = [plus]
	S.choose_card(0)
	_check("plus card raises owned level", S.lvl_at(_c(6)) == 2)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 99
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	var base_s = _fresh()
	_check("draft is seed-deterministic", JSON.stringify(Draft.roll_hand(r1, base_s._draft_ctx(""))) == JSON.stringify(Draft.roll_hand(r2, base_s._draft_ctx(""))))

	# --- Stage 7: in-run cash spend ------------------------------------------
	# REDESIGN (deliberate): cash buys the 5 Core tracks; buildings level only
	# through duplicate picks; rings open by track total (no per-cell unlock).
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	S.cash = 5.0
	_check("track refused when broke", S.buy_track("dmg").is_empty() and S.core_run_lvl == 0)
	S.cash = 1000.0
	_check("cash cannot level a building", S.upgrade(_c(7)).is_empty() and S.lvl_at(_c(7)) == 1)
	S.upgrade(_c(12))
	_check("Core cell upgrade = Damage track", S.core_run_lvl == 1 and int(S.tracks["dmg"]) == 1 and S.cash < 1000.0)
	_check("no per-cell run unlocks", S.unlock_plot(_c(0)).is_empty() and not bool(S.unlocked[_c(0)]))

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
	# REDESIGN (deliberate): the run grid starts EMPTY — permanent buildings
	# no longer enter runs (the Outpost replaces them in ENGINE-META).
	_check("run grid starts empty (no perm buildings / unlocks)", S.building_count() == 0 and not bool(S.unlocked[_c(0)]))
	_check("legacy perm core hp applied to the Core (+3%/lvl)", is_equal_approx(S.hp, 120.0 * 1.03))

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
	_redesign_run_stages()

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
	_check("B1 max hp x (1+lab_hp), unequipped card ignored", is_equal_approx(float(S.stats["max_hp"]), 132.0) and is_equal_approx(S.hp, 132.0))
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
	# REDESIGN: the first reroll of every draft is free; banked rerolls next.
	_check("first reroll per draft is free", rr.size() == 1 and S.rerolls_left == 2 and S.draft.size() == 3)
	rr = S.reroll_draft()
	_check("second reroll spends a banked reroll", rr.size() == 1 and S.rerolls_left == 1 and S.draft.size() == 3)

	# --- Stage 20: B2 speed + sub-steps (AC-15) ------------------------------
	var res: Array = []
	for sp in [1.0, 2.5]:
		var R = _fresh()
		R.max_hp_mult = 1.0e6   # REDESIGN: an untouched Core now dies ~w6; keep the run alive for the full 180 s
		R.recompute()
		R.hp = float(R.stats["max_hp"])
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
	S.slots[_c(7)] = {"id": "mine", "perm": 0, "run": 1}
	S.wave = 11
	S.recompute()
	# REDESIGN: every cash amount scales with the run cash index 1.10^(w-1).
	_check("cash/s (Core + Mine) x cash index 1.10^(w-1)", is_equal_approx(float(S.stats["cash_ps"]), (2.0 + 0.8) * 1.01 * pow(1.1, 10.0)))
	S.cash_earned = 1000.0 * pow(1.1, 10.0)
	var c_before: int = int(S.coins_run)
	S.hp = -1.0
	S.stats["regen"] = 0.0
	var dev: Array = S.tick(0.01)
	var go: Array = _evts(dev, "game_over")
	_check("AC-22 game_over itemises cash-out (12% of index-deflated cash)", go.size() == 1 and int(go[0]["breakdown"]["cashout"]) == 120 and int(go[0]["coins"]) == c_before + 120 and int(go[0]["breakdown"]["gems"]) == 3)
	_check("death banks coins + boss gems", int(sv3["coins"]) == c_before + 120 and int(sv3["gems"]) == 3 and int(sv3["gem_log"]["boss"]) == 3)
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
	_check("AC-25 ranged fires every 2s", shots == 2 and S.hp < float(S.stats["max_hp"]))
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
	S.slots[_c(7)] = {"id": "tesla", "perm": 0, "run": 3}
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

	# --- Stage 23: roguelite buildings (REDESIGN_SYSTEMS §2.3) ----------------
	# REDESIGN (deliberate): the S1-S11 adjacency web and the DR stack are
	# replaced by the redesign building sheet; these checks cover it.
	S = _open_run()
	S.slots[_c(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	var gr: float = float(_weapon(S, "gun")["rate"])
	_check("gatling L1: 6 dmg, 2.0/s", is_equal_approx(float(_weapon(S, "gun")["dmg"]), 6.0 * TowerState.bld_dmg()) and is_equal_approx(gr, 2.0))
	S.slots[_c(7)] = {"id": "gun", "perm": 0, "run": 5}
	S.recompute()
	_check("level-ups +35% main stat (L5 = 1.35^4)", is_equal_approx(float(_weapon(S, "gun")["dmg"]), 6.0 * TowerState.bld_dmg() * pow(1.35, 4.0)) and S.lvl_at(_c(7)) == 5)
	S.slots[_c(7)] = {"id": "gun", "perm": 0, "run": 9}
	_check("building level capped at 5", S.lvl_at(_c(7)) == 5 and TowerState.lvl_cap() == 5)
	S.slots[_c(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.slots[_c(8)] = {"id": "oilmill", "perm": 0, "run": 1}
	S.recompute()
	_check("oil mill: +2.0 cash/s, adjacent buildings -10% rate", is_equal_approx(float(_weapon(S, "gun")["rate"]), gr * 0.9) and _has_link(S, _c(8), _c(7), "OIL"))
	S.slots[_c(8)] = {}
	S.slots[_rc(4, 1)] = {"id": "beacon", "perm": 0, "run": 1}
	S.recompute()
	var gb: Dictionary = _weapon(S, "gun")
	_check("beacon radius 2: +10% rate, +0.3 range", is_equal_approx(float(gb["rate"]), gr * 1.1) and is_equal_approx(float(gb["range"]), 3.3 * TowerState.cpx()) and _has_link(S, _rc(4, 1), _c(7), "BEA"))
	S.slots[_rc(4, 1)] = {}
	S.slots[_rc(0, 0)] = {"id": "beacon", "perm": 0, "run": 1}
	S.recompute()
	_check("beacon does not reach 3 cells away", is_equal_approx(float(_weapon(S, "gun")["rate"]), gr))
	# Aegis: Core shield absorbs hits, regenerates after 4 s without damage.
	S = _fresh()
	S.spawn_hold = true
	S.slots[_c(13)] = {"id": "aegis", "perm": 0, "run": 1}
	S.recompute()
	S.shield = float(S.stats["shield_max"])
	_check("aegis shield 60 pts", is_equal_approx(S.shield, 60.0))
	var hp0: float = S.hp
	S._core_damage(42.0, [], "core_hit", TowerState.CENTER)
	_check("shield absorbs (42 - 2 armor) before HP", is_equal_approx(S.shield, 20.0) and is_equal_approx(S.hp, hp0))
	S._core_damage(42.0, [], "core_hit", TowerState.CENTER)
	_check("overflow reaches HP", is_equal_approx(S.shield, 0.0) and is_equal_approx(S.hp, hp0 - 20.0))
	S.stats["weapons"] = []
	for k in 60:
		S.tick(0.1)
	_check("shield regens 6/s after 4 s idle", S.shield > 5.0 and S.shield < 20.0)
	S = _fresh()
	S.hp = 100.0
	S._core_damage(1.0, [], "core_hit", TowerState.CENTER)
	_check("armor 2 vs a 1-dmg hit: 25% floor", is_equal_approx(S.hp, 99.75))
	# Vault interest: Core 2% + Vault 2%, cap (50 + 100) x cash index.
	S = _fresh()
	S.spawn_hold = true
	S.slots[_c(7)] = {"id": "vault", "perm": 0, "run": 1}
	S.recompute()
	S.cash = 100.0
	S.wave_t = S.wave_time - 0.001
	var vev: Array = S.tick(0.01)
	_check("interest: Core 2% + Vault 2% of banked cash", _evts(vev, "interest").size() == 1 and absf(float(_evts(vev, "interest")[0]["amt"]) - 4.0) < 0.05)
	S.cash = 1.0e6
	vev = []
	S._wave_end(vev)
	_check("interest cap (50 + 100) x cash index", is_equal_approx(float(vev[0]["amt"]), 150.0 * S.cash_index()))
	# Bounty Post: +20% kill cash for kills within 3 cells.
	S = _fresh()
	S.spawn_hold = true
	S.slots[_rc(2, 3)] = {"id": "bounty", "perm": 0, "run": 1}
	S.recompute()
	S.enemies.append(_enemy("drone", TowerState.slot_pos(_rc(2, 3)) + Vector2(0, -100), 0.0))
	S.cash = 0.0
	S._reap([])
	var near_c: float = S.cash
	S.enemies.append(_enemy("drone", TowerState.CENTER + Vector2(0, 300), 0.0))
	S.cash = 0.0
	S._reap([])
	_check("bounty: +20% kill cash only in radius", is_equal_approx(near_c, 1.2) and is_equal_approx(S.cash, 1.0))
	# Mortar min range, Cryo Spire slow aura, Obelisk lifesteal.
	S = _open_run()
	S.slots[_rc(2, 3)] = {"id": "mortar", "perm": 0, "run": 1}
	S.recompute()
	S.stats["weapons"] = [_weapon(S, "mortar")]
	var close_e: Dictionary = _enemy("hauler", TowerState.slot_pos(_rc(2, 3)) + Vector2(0, -50))
	S.enemies = [close_e]
	S._fire(0.01, [])
	_check("mortar cannot fire inside 1.5 cells", is_equal_approx(float(close_e["hp"]), 999.0))
	var far_e: Dictionary = _enemy("hauler", TowerState.slot_pos(_rc(2, 3)) + Vector2(0, -250))
	S.enemies = [far_e]
	S._fire(0.01, [])
	_check("mortar hits 18 dmg beyond min range", is_equal_approx(999.0 - float(far_e["hp"]), 18.0 * TowerState.bld_dmg()))
	S = _open_run()
	S.slots[_rc(2, 3)] = {"id": "frost", "perm": 0, "run": 1}
	S.recompute()
	S.stats["weapons"] = [_weapon(S, "frost")]
	var fe: Dictionary = _enemy("drone", TowerState.slot_pos(_rc(2, 3)) + Vector2(0, -150))
	S.enemies = [fe]
	S._fire(0.01, [])
	_check("cryo spire: slows 30% + chills (1.5 per pulse, 2/s)", is_equal_approx(float(fe["slow_m"]), 0.7) and float(fe["slow_t"]) > 0.0 and is_equal_approx(999.0 - float(fe["hp"]), 1.5 * TowerState.bld_dmg()))
	S = _fresh()
	S.slots[_c(7)] = {"id": "obelisk", "perm": 0, "run": 1}
	S.recompute()
	S.hp = 50.0
	S._hit(_enemy("hauler", TowerState.CENTER + Vector2(0, 300)), 100.0, [])
	_check("obelisk: 1% of dmg dealt heals the Core", is_equal_approx(S.hp, 51.0))
	# Every pick is offered by rarity weight; buildings are single-instance.
	var dctx: Dictionary = _fresh()._draft_ctx("")
	var ids_seen: Dictionary = {}
	var rng5 := RandomNumberGenerator.new()
	rng5.seed = 5
	for k in 400:
		for c in Draft.roll_hand(rng5, dctx):
			ids_seen[String(c["id"])] = String(c["rarity"])
	_check("all 36 run picks reachable (17 bld + 3 huts + 10 packs + 6 specials, minus pk_barracks w/o huts, railgun w/o ring 2)", ids_seen.size() >= 34 and not ids_seen.has("pk_barracks") and not ids_seen.has("railgun"))

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
	var had_draft: bool = S.draft.size() == 3
	S.draft = [Draft.card_for("pk_arsenal", S._draft_ctx(""))]
	pev.append_array(S.choose_card(0))
	_check("AC-23 perk_offer at wave 5 (right after the wave-4 draft)", had_draft and _evts(pev, "perk_offer").size() == 1 and S.perk_offer.size() == 3 and is_equal_approx(S.time_scale(), 0.2))
	S = _fresh()
	S.spawn_hold = true
	S.wave = 4
	S.wave_t = S.wave_time - 0.001
	pev = S.tick(0.01)
	_check("AC-23 perk queues behind the draft", S.draft.size() == 3 and S.perk_offer.is_empty() and S.perk_pending == 1)
	S.draft = [Draft.card_for("gun", S._draft_ctx(""))]
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
	_check("AC-24 Glass Cannon +40% dmg -25% hp", is_equal_approx(float(_weapon(S, "core")["dmg"]), base_core * 1.4) and is_equal_approx(float(S.stats["max_hp"]), 90.0))
	S.perks_taken = ["p_fort"]
	S.recompute()
	_check("AC-24 Fortress", is_equal_approx(float(S.stats["max_hp"]), 192.0) and is_equal_approx(float(S.stats["regen"]), 2.0) and is_equal_approx(float(_weapon(S, "core")["dmg"]), base_core * 0.8))
	S.perks_taken = ["p_frenzy", "p_rate"]
	S.recompute()
	_check("AC-24 Frenzy + Hair Trigger rate, regen 0", is_equal_approx(float(_weapon(S, "core")["rate"]), base_rate * 1.45) and is_equal_approx(float(S.stats["regen"]), 0.0))
	S.perks_taken = ["p_greed", "p_miser", "p_bloodmoon"]
	S.recompute()
	_check("AC-24 economy tradeoffs", is_equal_approx(S.run_coin_mult(), 1.5 * TuneRef.num("perk_bloodmoon", 1.25)) and is_equal_approx(S.run_cash_mult(), 1.5) and is_equal_approx(float(S.stats["xp_mult"]), 0.7) and S.upgrade_cost(TowerState.CORE_SLOT) == 14)
	var worst: bool = true
	var tr: Array = ["p_glass", "p_greed", "p_fort", "p_frenzy", "p_miser", "p_bloodmoon"]
	for mask in 64:
		var tk: Array = []
		for b in 6:
			if mask & (1 << b):
				tk.append(tr[b])
		S.perks_taken = tk
		S.recompute()
		if float(S.stats["max_hp"]) < 60.0 - 0.001 or float(S.stats["regen"]) < 0.0:
			worst = false
	_check("AC-24 no tradeoff combo below 50% hp or negative regen", worst)
	S = _fresh()
	S.hp = 10.0
	S.perk_offer = ["p_hp"]
	S.choose_perk(0)
	_check("Reinforced Core heals to full", is_equal_approx(S.hp, 150.0))

	# --- Stage 25: B8 cards in-run (AC-33) ------------------------------------
	var sv8: Dictionary = BaseMeta.default_save()
	sv8["cards"]["owned"] = {"c_wind": {"lvl": 2, "copies": 0}, "c_skip": {"lvl": 1, "copies": 0}}
	sv8["cards"]["equipped"] = ["c_wind", "c_skip"]
	S = TowerState.new()
	S.setup(3, sv8)
	S.spawn_hold = true
	S.hp = -1.0
	var wev: Array = S.tick(0.01)
	_check("AC-33 Second Wind revives at card %", _evts(wev, "revive").size() == 1 and not S.over and S.hp > 0.2 * float(S.stats["max_hp"]) and S.hp <= 0.255 * float(S.stats["max_hp"]))
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
	_check("Overdrive: hp lvl 20 -> 120 x (1+0.03*20) x 1.1^5", is_equal_approx(float(S.stats["max_hp"]), 120.0 * 1.6 * pow(1.1, 5.0)))
	od["core"] = {"dmg": 17, "hp": 0, "regen": 0}
	S = TowerState.new()
	S.setup(5, od)
	_check("Overdrive: dmg lvl 17 -> core dmg x 1.1^2", is_equal_approx(float(_weapon(S, "core")["dmg"]), 10.0 * (1.0 + 0.03 * 17.0) * pow(1.1, 2.0)))
	# REDESIGN (deliberate): Core Overcharge is replaced by the Damage cash
	# track: x1.08 per level on the Core AND every building, cost 20 x 1.18^n.
	S = _fresh()
	S.slots[_c(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	var g0: float = float(_weapon(S, "gun")["dmg"])
	var c0: float = float(_weapon(S, "core")["dmg"])
	S.cash = 1000.0
	S.upgrade(TowerState.CORE_SLOT)
	S.upgrade(TowerState.CORE_SLOT)
	_check("Damage track: 2 levels -> Core + buildings x1.08^2", S.core_run_lvl == 2 and is_equal_approx(float(_weapon(S, "gun")["dmg"]), g0 * 1.1664) and is_equal_approx(float(_weapon(S, "core")["dmg"]), c0 * 1.1664))
	_check("Damage track cost 20 x growth^n", S.upgrade_cost(TowerState.CORE_SLOT) == int(round(20.0 * pow(float(TowerState.TRACKS["dmg"]["growth"]), 2.0))) and is_equal_approx(float(S.stats["overcharge_step"]), 0.08))
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
	S.slots[_c(7)] = {"id": "gun", "perm": 0, "run": 1}
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
	# REDESIGN (deliberate): every building is run-only, so modes are run-scoped.
	var S2 = TowerState.new()
	S2.setup(77, S.save)
	_check("target modes are run-scoped (fresh run starts nearest)", String(S2.target_modes[_c(7)]) == "nearest" and not (S.save as Dictionary).has("target_modes"))
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
	_pc_save_stages()
	_pc_shell_stages()


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
	# REDESIGN (deliberate): run rings open by Core track total (ring 2 at 10,
	# ring 3 at 30), not by per-cell cash unlocks.
	var S1 = TowerState.new()
	S1.setup(3, BaseMeta.default_save())
	S1.cash = 1.0e9
	_check("PC-E1 run: per-cell unlock is gone", S1.unlock_plot(edge2).is_empty() and not bool(S1.unlocked[edge2]))
	var rev: Array = []
	for k in 9:
		rev.append_array(S1.buy_track("armor"))
	_check("PC-E1 run: ring 2 still shut at track total 9", not bool(S1.unlocked[edge2]) and _evts(rev, "ring_open").is_empty())
	rev = S1.buy_track("eco")
	_check("PC-E1 run: ring 2 opens at track total 10", bool(S1.unlocked[edge2]) and bool(S1.unlocked[corner2]) and not bool(S1.unlocked[edge3]) and _evts(rev, "ring_open").size() == 1 and int(_evts(rev, "ring_open")[0]["ring"]) == 2)
	for k in 20:
		rev = S1.buy_track("dmg")
	_check("PC-E1 run: ring 3 opens at track total 30", bool(S1.unlocked[edge3]) and S1.rings_open == 3)
	# Land development: +1 perm level cap per 4 outer cells (max +10).
	var ld: Dictionary = BaseMeta.default_save()
	var cap0: int = BaseMeta.perm_lvl_cap(ld)
	ld["unlocked"] = [8, 9, 10]
	var cap3: int = BaseMeta.perm_lvl_cap(ld)
	ld["unlocked"] = [8, 9, 10, 11]
	var cap4: int = BaseMeta.perm_lvl_cap(ld)
	var many: Array = []
	for i in TowerState.N:
		if BaseMeta.cell_ring(i) >= 2:
			many.append(i)
	ld["unlocked"] = many
	_check("PC land bonus: +1 perm cap per 4 outer cells, max +10", cap0 == 10 and cap3 == 10 and cap4 == 11 and BaseMeta.perm_lvl_cap(ld) == 20)
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
	S.build_cap = 12   # REDESIGN: the run grid has no tier cap now; the cap mechanism still holds
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
		for c in Draft.roll_hand(rng, S._draft_ctx("")):
			only_plus = only_plus and String((c as Dictionary)["kind"]) != "new"
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
	# REDESIGN (deliberate): S8-S11 synergies are gone; numbers follow the
	# redesign sheet (Railgun 60 dmg, Flak air-only x2.5).
	S = _open_run()
	S.slots[r2] = {"id": "railgun", "perm": 0, "run": 1}
	S.recompute()
	var rd0: float = float(_weapon(S, "railgun")["dmg"])
	_check("PC-E3 railgun base dmg 60, 0.25/s, range 7", is_equal_approx(rd0, 60.0 * TowerState.bld_dmg()) and is_equal_approx(float(_weapon(S, "railgun")["rate"]), 0.25))
	# Railgun pierces along its line.
	S = _open_run()
	S.slots[r2] = {"id": "railgun", "perm": 0, "run": 1}
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
	# Flak: flyers only, x2.5.
	S = _open_run()
	S.slots[r1] = {"id": "flak", "perm": 0, "run": 2}
	S.recompute()
	var fl: Dictionary = _weapon(S, "flak")
	_check("PC-E3 flak L2 dmg 8 x 1.35", is_equal_approx(float(fl["dmg"]), 8.0 * 1.35 * TowerState.bld_dmg()))
	S.stats["weapons"] = [fl]
	var fpos: Vector2 = TowerState.slot_pos(r1) + Vector2(0, -120)
	var heavy: Dictionary = _enemy("hauler", fpos + Vector2(0, 20))
	S.enemies.append_array([heavy])
	fev = []
	S._fire(0.01, fev)
	_check("PC-E3 flak cannot hit ground", is_equal_approx(float(heavy["hp"]), 999.0))
	var prey: Dictionary = _enemy("drone", fpos)
	S.enemies.append(prey)
	S.cooldowns[r1] = 0.0
	S._fire(0.01, fev)
	_check("PC-E3 flak x2.5 vs flyers", is_equal_approx(999.0 - float(prey["hp"]), 8.0 * 1.35 * 2.5 * TowerState.bld_dmg()) and is_equal_approx(float(heavy["hp"]), 999.0))
	var cw: Dictionary = _weapon(S, "flak").duplicate()
	cw["crit"] = 1.0
	S.stats["weapons"] = [cw]
	var ce: Dictionary = _enemy("drone", TowerState.slot_pos(r1) + Vector2(0, -100))
	S.enemies = [ce]
	S.cooldowns[r1] = 0.0
	fev = []
	S._fire(0.01, fev)
	var dm: Array = _evts(fev, "dmg")
	_check("PC-E3 crit hit doubles dmg + flags the event", dm.size() == 1 and bool((dm[0] as Dictionary).get("crit", false)) and is_equal_approx(999.0 - float(ce["hp"]), 2.0 * 2.5 * float(cw["dmg"])))
	S = _open_run()
	S.packs = {"pk_crit": 2}
	S.recompute()
	_check("PC-E3 Precision packs: +8% crit each (global)", is_equal_approx(float(S.stats["crit"]), 0.16))
	# Barricade: lane wall, -30% speed, 200 HP x1.35^(L-1) (x enemy dmg growth), rebuilt each wave.
	S = _open_run()
	S.stats["weapons"] = []
	S.slots[r2] = {"id": "barricade", "perm": 0, "run": 2}
	S.recompute()
	S.stats["weapons"] = []
	var whp: float = 200.0 * 1.35
	_check("PC-E3 barricade wall on its lane, 200 HP x1.35/lv", TowerState.cell_quad(r2) == 0 and S.walls.has(0) and is_equal_approx(float(S.walls[0]["hp"]), whp))
	var wn: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, -260))
	wn["quad"] = 0
	var ws: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, 260))
	ws["quad"] = 2
	S.enemies = [wn, ws]
	S._move_enemies(0.1, [])
	var dn: float = 260.0 - (wn["pos"] as Vector2).distance_to(TowerState.CENTER)
	var ds: float = 260.0 - (ws["pos"] as Vector2).distance_to(TowerState.CENTER)
	_check("PC-E3 wall slows its lane 30%, other lanes free", is_equal_approx(dn, ds * 0.7) and float(S.walls[0]["hp"]) < whp)
	wn["dmg"] = 5000.0
	var wev: Array = []
	S._move_enemies(0.1, wev)
	_check("PC-E3 wall breaks under damage", _evts(wev, "wall_broken").size() == 1 and float(S.walls[0]["hp"]) == 0.0)
	S.enemies.clear()
	S.wave_t = S.wave_time - 0.001
	wev = S.tick(0.01)
	_check("PC-E3 wall rebuilt next wave (x1.06 enemy dmg growth)", _evts(wev, "wall_up").size() == 1 and is_equal_approx(float(S.walls[0]["hp"]), whp * 1.06))
	# Outer rings reach further (+8% per ring past 1).
	S = _open_run()
	S.slots[r1] = {"id": "gun", "perm": 0, "run": 1}
	S.slots[_rc(0, 3)] = {"id": "gun", "perm": 0, "run": 1}
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
	for id in PickDB.BUILDINGS + PickDB.HUTS:
		ids_ok = ids_ok and String(BuildingDB.get_def(String(id)).get("name", "")) != "" and String(PickDB.get_def(String(id)).get("desc", "")) != ""
	_check("REDESIGN 17 buildings + 3 huts named in BuildingDB + PickDB", ids_ok and PickDB.BUILDINGS.size() == 17 and PickDB.HUTS.size() == 3 and PickDB.PACKS.size() == 10 and PickDB.SPECIALS.size() == 6 and PickDB.INSIGHT.size() == 7)


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
	S.slots[_rc(1, 3)] = {"id": "railgun", "perm": 0, "run": 1}
	S.recompute()
	_check("PC-E4 railgun cannot move inside ring 2", S.move_building(_rc(1, 3), _rc(3, 2)).is_empty() and S.move_building(_rc(1, 3), b).is_empty())
	S.pending_place = "railgun"
	var cev: Array = S.cancel_place()
	_check("cancel_place drops a pending card", S.pending_place == "" and cev.size() == 1 and String(cev[0]["t"]) == "place_cancelled" and S.cancel_place().is_empty())
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


static func _mc(id: String) -> float:
	return float((ModifierDB.DEFS[id] as Dictionary)["coin"])


## PC-E6 challenge modifiers, PC-E7 endless mode.
func _pc_mode_stages() -> void:
	_check("PC-E6 coin mult = min(3, 1 + sum)", is_equal_approx(ModifierDB.coin_mult(["glass"]), 1.0 + _mc("glass")) and is_equal_approx(ModifierDB.coin_mult(["glass", "haste"]), 1.0 + _mc("glass") + _mc("haste")) and is_equal_approx(ModifierDB.coin_mult(ModifierDB.IDS), 3.0) and is_equal_approx(ModifierDB.coin_mult(["bogus"]), 1.0))
	var S0 = _mod_run([])
	var S = _mod_run(["glass", "haste", "bogus", "glass"])
	var gh: float = 1.0 + _mc("glass") + _mc("haste")
	_check("PC-E6 modifiers cleaned + run coin mult applied", S.modifiers == ["glass", "haste"] and is_equal_approx(S.coin_mult, S0.coin_mult * gh) and is_equal_approx(S.run_coin_mult(), S0.run_coin_mult() * gh))
	_check("PC-E6 Glass Core: max HP -50%", is_equal_approx(float(S.stats["max_hp"]), 60.0) and is_equal_approx(S.hp, 60.0))
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
	_check("PC-E7 endless unlocked at wave 50, coins x0.9", E.mode == "endless" and is_equal_approx(E.coin_mult, N0.coin_mult * 0.9))
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
	_check("PC-E7 mutation pays +15% coins and buffs enemies", _evts(tk, "mutation_taken").size() == 1 and is_equal_approx(E.run_coin_mult(), cm0 * 1.15) and is_equal_approx(vh, 6.0 * 1.2) and E.mutation_offer.is_empty())
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


## PC-E9 save v3 migration + 3 slots + .bak fallback.
func _pc_save_stages() -> void:
	# A mobile v2 save (5x5 keys) migrates losslessly onto the 7x7 board.
	var v2: Dictionary = {
		"version": 2, "coins": 4321, "gems": 12, "core": {"dmg": 3, "hp": 2, "regen": 1},
		"slots": {"6": {"id": "armory", "lvl": 4}, "7": {"id": "gun", "lvl": 3}, "0": {"id": "mine", "lvl": 2}, "24": {"id": "vault", "lvl": 1}},
		"unlocked": [0, 4, 24], "runs": 9, "best_wave": 44, "tier": 2, "best_wave_by_tier": {"1": 44, "2": 3},
		"target_modes": {"7": "first"}, "stats": {"kills": 999, "bosses": 4},
		"labs": {"lvls": {"dmg": 3, "coin": 1}, "slots": 2, "running": []},
	}
	var m: Dictionary = BaseMeta.normalize(BaseMeta.migrate(v2))
	var slot_ok: bool = String(BaseMeta.slot_of(m, _c(6))["id"]) == "armory" and int(BaseMeta.slot_of(m, _c(6))["lvl"]) == 4 and String(BaseMeta.slot_of(m, _c(7))["id"]) == "gun" and String(BaseMeta.slot_of(m, _c(0))["id"]) == "mine" and String(BaseMeta.slot_of(m, _c(24))["id"]) == "vault" and (m["slots"] as Dictionary).size() == 4
	_check("PC-E9 v2 -> v3: version, cells offset (r+1,c+1)", int(m["version"]) == 3 and slot_ok and _c(6) == 16 and _c(24) == 40)
	_check("PC-E9 v2 -> v3: unlocks land on ring 2", (m["unlocked"] as Array) == [_c(0), _c(4), _c(24)] and BaseMeta.cell_ring(_c(0)) == 2)
	_check("PC-E9 v2 -> v3 keeps meta fields", int(m["coins"]) == 4321 and int(m["gems"]) == 12 and int(m["core"]["dmg"]) == 3 and int(m["runs"]) == 9 and int(m["best_wave_by_tier"]["1"]) == 44 and int(m["tier"]) == 2 and int(m["labs"]["lvls"]["dmg"]) == 3 and int(m["stats"]["kills"]) == 999 and int(m["stats"]["bosses"]) == 4)
	_check("PC-E9 v3 blocks filled", (m["history"] as Array).is_empty() and int(m["endless"]["best"]) == 0 and (m["stats"] as Dictionary).has("kills_by_kind"))
	var mm: Dictionary = BaseMeta.migrate(v2)
	_check("PC-E9 target modes remapped", String((mm["target_modes"] as Dictionary)[str(_c(7))]) == "first")
	_check("PC-E9 migrate is idempotent on v3", JSON.stringify(BaseMeta.migrate(m)) == JSON.stringify(m))
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(m)))
	_check("PC-E9 v3 JSON round-trip equality", JSON.stringify(rt) == JSON.stringify(m))
	# Slots.
	for n in [1, 2, 3]:
		MetaSave.delete_slot(n, MetaSave.DELETE_CONFIRM)
	var s1: Dictionary = BaseMeta.default_save()
	s1["coins"] = 111
	var s2: Dictionary = BaseMeta.default_save()
	s2["coins"] = 222
	s2["best_wave_by_tier"] = {"1": 41, "2": 7}
	s2["best_wave"] = 41
	_check("PC-E9 write slots", MetaSave.write_slot(1, s1) and MetaSave.write_slot(2, s2) and not MetaSave.write_slot(4, s1))
	_check("PC-E9 slots are independent", int(MetaSave.read_slot(1)["coins"]) == 111 and int(MetaSave.read_slot(2)["coins"]) == 222 and MetaSave.read_slot(3).is_empty() and not MetaSave.slot_exists(3))
	var sm: Dictionary = MetaSave.slot_summary(2)
	_check("PC-E9 slot summary", bool(sm["exists"]) and int(sm["best_tier"]) == 2 and int(sm["best_wave"]) == 41 and not bool(MetaSave.slot_summary(3)["exists"]))
	_check("PC-E9 copy only into an empty slot", not MetaSave.copy_slot(1, 2) and MetaSave.copy_slot(2, 3) and int(MetaSave.read_slot(3)["coins"]) == 222)
	_check("PC-E9 delete needs the typed confirmation", not MetaSave.delete_slot(3, "yes") and MetaSave.slot_exists(3) and MetaSave.delete_slot(3, MetaSave.DELETE_CONFIRM) and not MetaSave.slot_exists(3))
	s1["coins"] = 333
	MetaSave.write_slot(1, s1)
	var bak: Variant = JSON.parse_string(FileAccess.get_file_as_string(MetaSave.slot_path(1) + ".bak"))
	_check("PC-E9 .bak holds the previous save, no .tmp left", bak is Dictionary and int((bak as Dictionary)["coins"]) == 111 and not FileAccess.file_exists(MetaSave.slot_path(1) + ".tmp"))
	var f := FileAccess.open(MetaSave.slot_path(1), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	_check("PC-E9 corrupted primary falls back to .bak", int(MetaSave.read_slot(1)["coins"]) == 111)
	# Active slot API + legacy mobile save import into slot 1.
	MetaSave.set_active(2)
	_check("PC-E9 read()/write() use the active slot", int(MetaSave.read()["coins"]) == 222)
	MetaSave.set_active(1)
	MetaSave.delete_slot(1, MetaSave.DELETE_CONFIRM)
	var lf := FileAccess.open(MetaSave.LEGACY_PATH, FileAccess.WRITE)
	lf.store_string(JSON.stringify(v2))
	lf.close()
	var imp: Dictionary = BaseMeta.normalize(MetaSave.read_slot(1))
	_check("PC-E9 legacy save.json imports into slot 1 as v3", int(imp["version"]) == 3 and int(imp["coins"]) == 4321 and String(BaseMeta.slot_of(imp, _c(7))["id"]) == "gun" and MetaSave.read_slot(2).get("coins", 0) == 222)
	for n in [1, 2, 3]:
		MetaSave.delete_slot(n, MetaSave.DELETE_CONFIRM)
	MetaSave.set_active(1)


## PC-E11/E12 + PC-E10: settings round-trip, keybind remap, Steam no-op
## wrapper and the achievement table (via SteamService's mock log).
func _pc_shell_stages() -> void:
	# --- Settings (PC-E12) ---------------------------------------------------
	var d: Dictionary = Settings.defaults()
	_check("PC-E12 defaults are already normal", JSON.stringify(Settings.normalize(d)) == JSON.stringify(Settings.normalize(Settings.normalize(d))) and String(d["video"]["mode"]) == "windowed")
	var bad: Dictionary = {"video": {"mode": "sideways", "fps_cap": 77, "ui_scale": 9.0, "resolution": "huge"}, "audio": {"Master": 4.0, "SFX": -1.0}, "keybinds": {"nope": [], "pause": [{"type": "bogus"}]}}
	var nb: Dictionary = Settings.normalize(bad)
	_check("PC-E12 normalize clamps garbage", String(nb["video"]["mode"]) == "windowed" and int(nb["video"]["fps_cap"]) == 0 and is_equal_approx(float(nb["video"]["ui_scale"]), Settings.UI_SCALE_MAX) and nb["video"]["resolution"] == Vector2i(1920, 1080) and is_equal_approx(float(nb["audio"]["Master"]), 1.0) and is_equal_approx(float(nb["audio"]["SFX"]), 0.0) and not (nb["keybinds"] as Dictionary).has("nope") and ((nb["keybinds"] as Dictionary)["pause"] as Array).is_empty())
	var path: String = "user://_selftest_settings.cfg"
	var s1: Dictionary = Settings.defaults()
	s1["video"]["mode"] = "borderless"
	s1["video"]["resolution"] = Vector2i(1600, 900)
	s1["video"]["vsync"] = "adaptive"
	s1["video"]["fps_cap"] = 144
	s1["video"]["ui_scale"] = 1.25
	s1["audio"]["Music"] = 0.25
	s1["controls"]["deadzone"] = 0.3
	s1["controls"]["glyphs"] = "ps5"
	s1["gameplay"]["colorblind"] = "tritanopia"
	_check("PC-E12 settings write ok", Settings.write(s1, path) == OK)
	var r1: Dictionary = Settings.read(path)
	_check("PC-E12 settings round-trip through ConfigFile", JSON.stringify(r1) == JSON.stringify(Settings.normalize(s1)) and r1["video"]["resolution"] == Vector2i(1600, 900) and String(r1["video"]["mode"]) == "borderless")
	_check("PC-E12 missing file -> defaults", JSON.stringify(Settings.read("user://_nope_settings.cfg")) == JSON.stringify(Settings.defaults()))
	Settings.apply(r1)
	_check("PC-S1 fps cap applies to Engine.max_fps", Engine.max_fps == 144)
	var mi: int = AudioServer.get_bus_index("Music")
	_check("PC-S1 audio slider applies to the bus", mi >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(mi), linear_to_db(0.25)))
	_check("PC-E12 UI bus exists", AudioServer.get_bus_index("UI") >= 0)
	Settings.apply(Settings.defaults())
	_check("PC-E12 fps cap unlimited restores 0", Engine.max_fps == 0)
	_check("PC-S1 fullscreen toggle flips the mode", String(Settings.toggle_fullscreen(Settings.defaults())["video"]["mode"]) == "borderless" and String(Settings.toggle_fullscreen(Settings.toggle_fullscreen(Settings.defaults()))["video"]["mode"]) == "windowed")
	_check("PC-S1 resolution list filtered to screen", Settings.resolutions_for(Vector2i(1366, 768)) == [Vector2i(1280, 720), Vector2i(1366, 768)] and Settings.clamp_resolution(Vector2i(3840, 2160), Vector2i(1920, 1080)) == Vector2i(1920, 1080))
	_check("PC-S1 video revert after 10 s unless confirmed", Settings.revert_due(10.0, false) and not Settings.revert_due(9.9, false) and not Settings.revert_due(30.0, true))

	# --- Keybinds ------------------------------------------------------------
	Keybinds.ensure_actions(0.5, true)
	var all_ok: bool = true
	for a in Keybinds.DEFAULTS.keys():
		if not InputMap.has_action(String(a)) or InputMap.action_get_events(String(a)).is_empty() or not Keybinds.LABELS.has(a):
			all_ok = false
	_check("PC-E12 every hotkey action registered with defaults + label", all_ok)
	var space: InputEventKey = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	var pad_a: InputEventJoypadButton = InputEventJoypadButton.new()
	pad_a.button_index = JOY_BUTTON_A
	pad_a.pressed = true
	_check("PC-U3 Space triggers pause, pad A triggers confirm", InputMap.event_is_action(space, "pause") and InputMap.event_is_action(pad_a, "confirm"))
	var ctrl_r: InputEventKey = InputEventKey.new()
	ctrl_r.keycode = KEY_R
	ctrl_r.ctrl_pressed = true
	ctrl_r.pressed = true
	_check("PC-U3 Ctrl+R is retry", InputMap.event_is_action(ctrl_r, "retry", true) and not InputMap.event_is_action(ctrl_r, "ability_4", true))
	var dup: Dictionary = {}
	var clash: String = ""
	for a in Keybinds.DEFAULTS.keys():
		for e in Keybinds.default_events(String(a)):
			var k: String = JSON.stringify(Keybinds.event_to_dict(e))
			if dup.has(k):
				clash = "%s/%s" % [dup[k], a]
			dup[k] = a
	_check("PC-E12 no two default actions share a binding (%s)" % clash, clash == "")
	var map0: Dictionary = Keybinds.to_map()
	var kinds: Dictionary = {}
	for a in map0.keys():
		for e in map0[a]:
			kinds[String((e as Dictionary)["type"])] = true
	_check("PC-E12 defaults cover key, mouse, joy button and joy axis", kinds.has("key") and kinds.has("mouse") and kinds.has("joy_button") and kinds.has("joy_axis"))
	var js: String = JSON.stringify(map0)
	Keybinds.apply_map(JSON.parse_string(js))
	_check("PC-E12 keybind serialise/deserialise round-trip (via JSON)", JSON.stringify(Keybinds.to_map()) == js)
	# Remap conflict -> swap (input_helper pattern).
	var xkey: InputEventKey = InputEventKey.new()
	xkey.keycode = KEY_X
	var swapped: String = Keybinds.rebind("upgrade", 0, xkey)
	_check("PC-E12 remap conflict swaps the bindings", swapped == "sell" and Keybinds.hint("upgrade") == "X" and Keybinds.action_using(xkey, "upgrade") == "" and Keybinds.events_for("sell", false).any(func(e: InputEvent) -> bool: return e is InputEventKey and (e as InputEventKey).keycode == KEY_U))
	var lb: InputEventJoypadButton = InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	Keybinds.rebind("pause", 0, lb)
	_check("PC-E12 pad slot replaced, key slot kept", Keybinds.events_for("pause", true).size() == 1 and Keybinds.hint("pause", true) == "LB" and Keybinds.hint("pause") == "Space" and Keybinds.events_for("hotbar_prev", true).size() == 1 and Keybinds.hint("hotbar_prev", true) == "Start")
	# Persist the remap through settings.cfg, reset, reload.
	var s2: Dictionary = Settings.defaults()
	Settings.capture_keybinds(s2)
	Settings.write(s2, path)
	Keybinds.reset_all()
	_check("PC-S2 reset restores defaults", Keybinds.hint("upgrade") == "U" and Keybinds.hint("sell") == "X")
	Settings.apply_controls(Settings.read(path))
	_check("PC-S2 remap persists in settings.cfg", Keybinds.hint("upgrade") == "X" and Keybinds.hint("pause", true) == "LB")
	Keybinds.reset_all()
	_check("PC-U5 glyph paths resolve to vendored PNGs", ResourceLoader.exists(Keybinds.glyph_path(space)) and ResourceLoader.exists(Keybinds.glyph_path(pad_a, "ps5")) and Keybinds.glyph_path(pad_a, "ps5").ends_with("ps5/cross.png") and ResourceLoader.exists(Keybinds.glyph_path(Keybinds.default_events("speed_up")[1], "steamdeck")) and ResourceLoader.exists(Keybinds.glyph_path(Keybinds.default_events("zoom_in")[0])))
	_check("PC-U5 pad style from joypad name", Keybinds.pad_style("PS5 Controller") == "ps5" and Keybinds.pad_style("Steam Deck") == "steamdeck" and Keybinds.pad_style("Xbox Series Controller") == "xbox")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# --- SteamService no-op wrapper (PC-E11) ---------------------------------
	SteamService.reset_mock()
	_check("PC-E11 no GodotSteam -> init false, inactive", not SteamService.init() and not SteamService.is_active())
	_check("PC-E11 calls no-op and return false", not SteamService.unlock_achievement("ACH_TEST") and not SteamService.set_stat_int("stat_kills", 3) and not SteamService.set_rich_presence("status", "Menu") and not SteamService.overlay_active())
	_check("PC-E11 mock log records ops", SteamService.mock_ops("unlock_achievement") == [["ACH_TEST"]] and SteamService.mock_ops("init").size() == 1)
	SteamService.cloud_write("slot_1.json", "abc".to_utf8_buffer())
	_check("PC-E11 mock cloud round-trip", SteamService.cloud_read("slot_1.json").get_string_from_utf8() == "abc")
	_check("PC-E11 rich presence text", SteamService.presence_text("run", 12, 3) == "Run: Wave 12 · T3" and SteamService.presence_text("run", 80, 1, "endless") == "Endless: Wave 80" and SteamService.presence_text("base") == "Base" and SteamService.presence_text("menu") == "Menu")
	_check("PC-E11 cloud conflict keeps more playtime", SteamService.pick_conflict({"stats": {"play_s": 10.0}}, {"stats": {"play_s": 20.0}}) == "cloud" and SteamService.pick_conflict({"playtime_s": 30.0}, {"playtime_s": 20.0}) == "local")
	var ps: Dictionary = BaseMeta.default_save()
	SteamService.reset_mock()
	SteamService.push_stats(ps)
	_check("PC-E11 stats mirrored (5 stats + store)", SteamService.mock_ops("set_stat_int").size() == 5 and SteamService.mock_ops("store_stats").size() == 1)

	# --- Achievements (PC-E10) -----------------------------------------------
	_check("PC-E10 24 achievements, unique ids", AchievementDB.LIST.size() == 24 and AchievementDB.ids().size() == 24)
	var ring3: int = 0
	var full: Array = []
	for i in BaseMeta.N:
		if i != BaseMeta.CORE_SLOT and not BaseMeta.is_inner(i):
			full.append(i)
	var labs_max: Dictionary = BaseMeta.default_save()["labs"]
	var cases: Dictionary = {
		"ACH_FIRST_RUN": [{}, [{"t": "run_start"}, {"t": "game_over", "wave": 3, "build": []}], -1.0],
		"ACH_WAVE_25": [{}, [{"t": "run_start"}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 25}], -1.0],
		"ACH_WAVE_100": [{}, [{"t": "run_start"}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 100}], -1.0],
		"ACH_WAVE_250": [{}, [{"t": "run_start", "mode": "endless"}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 250}], -1.0],
		"ACH_TIER_3": [{"best_wave_by_tier": {"1": 9999, "2": 9999}}, [{"t": "meta"}], -1.0],
		"ACH_TIER_8": [{"best_wave_by_tier": {"1": 9999, "2": 9999, "3": 9999, "4": 9999, "5": 9999, "6": 9999, "7": 9999}}, [{"t": "meta"}], -1.0],
		"ACH_FIRST_BOSS": [{}, [{"t": "boss_bounty"}], -1.0],
		"ACH_BOSS_50": [{"stats": {"bosses": 50}}, [{"t": "meta"}], -1.0],
		"ACH_KILLS_100K": [{"stats": {"kills": 100000}}, [{"t": "meta"}], -1.0],
		"ACH_RING_3": [{"unlocked": [ring3]}, [{"t": "meta"}], -1.0],
		"ACH_FULL_BASE": [{"unlocked": full}, [{"t": "meta"}], -1.0],
		"ACH_ALL_SYNERGY": [{}, [{"t": "synergies", "n": AchievementDB.SYNERGY_TARGET}], -1.0],
		"ACH_ECO_ONLY": [{}, [{"t": "game_over", "wave": 30, "build": ["", "mine", "bounty"]}], -1.0],
		"ACH_NO_ECO": [{}, [{"t": "game_over", "wave": 60, "build": ["gun", "", "armory"]}], -1.0],
		"ACH_LABS_MAX": [{"labs": {"lvls": {"speed": 3}}}, [{"t": "meta"}], -1.0],
		"ACH_CARD_MAX": [{"cards": {"owned": {"c_test": {"lvl": CardDB.MAX_LVL, "copies": 0}}}}, [{"t": "meta"}], -1.0],
		"ACH_MOD_3": [{}, [{"t": "run_start", "modifiers": ["swarm", "haste", "noperks"]}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 51}], -1.0],
		"ACH_GLASS_50": [{}, [{"t": "run_start", "modifiers": ["glass"]}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 50}], -1.0],
		"ACH_ENCIRCLED_100": [{}, [{"t": "run_start", "modifiers": ["allsides"]}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 100}], -1.0],
		"ACH_NO_DAMAGE_10": [{}, [{"t": "run_start"}, {"t": "wave", "wave": 5}, {"t": "wave", "wave": 11}], -1.0],
		"ACH_SPEEDRUN": [{}, [{"t": "run_start"}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 40}], 590.0],
		"ACH_STREAK_7": [{"streak": {"day_idx": 7, "last_day": 3, "loops": 0}}, [{"t": "meta"}], -1.0],
		"ACH_MISSIONS_50": [{}, [], -1.0],
		"ACH_ENDLESS": [{"best_wave": 50, "best_wave_by_tier": {"1": 50}}, [{"t": "meta"}], -1.0],
	}
	for i in BaseMeta.N:
		if BaseMeta.cell_ring(i) == 3:
			ring3 = i
			break
	(cases["ACH_RING_3"][0] as Dictionary)["unlocked"] = [ring3]
	var m50: Array = []
	for k in 50:
		m50.append({"t": "mission_claimed", "idx": 0, "gems": 1})
	cases["ACH_MISSIONS_50"][1] = m50
	_check("PC-E10 every achievement has a synthetic case", cases.size() == 24 and cases.keys().all(func(k: Variant) -> bool: return AchievementDB.ids().has(String(k))))
	for id in cases.keys():
		var c: Array = cases[id]
		var sv: Dictionary = BaseMeta.default_save()
		for k in (c[0] as Dictionary).keys():
			sv[k] = (c[0] as Dictionary)[k]
		var run: Dictionary = Achievements.new_run()
		SteamService.reset_mock()
		var got: Array = Achievements.on_events(sv, run, c[1], 100, float(c[2]))
		var got2: Array = Achievements.on_events(sv, run, c[1], 200, float(c[2]))
		var fired: int = 0
		for x in got:
			if String((x as Dictionary)["id"]) == String(id):
				fired += 1
		var steam_n: int = SteamService.mock_ops("unlock_achievement").filter(func(a: Variant) -> bool: return String((a as Array)[0]) == String(id)).size()
		_check("PC-E10 %s fires exactly once + mirrors to Steam" % id, fired == 1 and Achievements.is_unlocked(sv, String(id)) and got2.filter(func(x: Variant) -> bool: return String((x as Dictionary)["id"]) == String(id)).is_empty() and steam_n == 1 and int(sv["achievements"]["unlocked"][id]) == 100)
	# Negative cases.
	var nsv: Dictionary = BaseMeta.default_save()
	var nrun: Dictionary = Achievements.new_run()
	Achievements.on_events(nsv, nrun, [{"t": "run_start"}, {"t": "wave", "wave": 5}, {"t": "core_hit", "dmg": 3.0}, {"t": "wave", "wave": 11}], 1, 700.0)
	Achievements.on_events(nsv, nrun, [{"t": "wave", "wave": 40}], 1, 700.0)
	Achievements.on_events(nsv, nrun, [{"t": "game_over", "wave": 40, "build": ["gun", "mine"], "duration_s": 300.0}], 1)
	_check("PC-E10 negatives: damage before w11, slow w40, mixed build", not Achievements.is_unlocked(nsv, "ACH_NO_DAMAGE_10") and not Achievements.is_unlocked(nsv, "ACH_SPEEDRUN") and not Achievements.is_unlocked(nsv, "ACH_ECO_ONLY") and not Achievements.is_unlocked(nsv, "ACH_NO_ECO") and Achievements.is_unlocked(nsv, "ACH_FIRST_RUN"))
	_check("PC-E10 W250 needs endless", not Achievements.is_unlocked(nsv, "ACH_WAVE_250"))
	# A real 9-wave normal run fires nothing.
	var tsv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	var T = TowerState.new()
	var ev0: Array = T.setup(4321, tsv)
	_godmode(T)
	var trun: Dictionary = Achievements.new_run()
	SteamService.reset_mock()
	var tev: Array = _sim_waves(T, 9, ev0)
	var tgot: Array = Achievements.on_events(tsv, trun, tev, 5, float(T.time_alive))
	_check("PC-E10 no false positives in a 9-wave normal run (%s)" % JSON.stringify(tgot), tgot.is_empty() and Achievements.unlocked_count(tsv) == 0 and SteamService.mock_ops("unlock_achievement").is_empty())
	_check("PC-E10 achievements survive normalize", BaseMeta.normalize({"achievements": {"unlocked": {"ACH_FIRST_RUN": 5}, "missions_claimed": 3}})["achievements"] == {"unlocked": {"ACH_FIRST_RUN": 5}, "missions_claimed": 3})
	SteamService.reset_mock()


# ======================================================================
# REDESIGN ENGINE-RUN (REDESIGN_SPEC §2): PowerModel, Cores + cash tracks,
# empty roguelite grid + extended drafts, Specials, Troops, Insight, Drops.
# ======================================================================
func _redesign_run_stages() -> void:
	_power_model_stages()
	_core_stages()
	_track_stages()
	_core_attack_stages()
	_draft_stages()
	_special_stages()
	_troop_stages()
	_insight_drop_stages()
	_snapshot_stages()
	_engine_meta_stages()


## §2.7 PowerModel: pure, static, matches the engine's own curves.
func _power_model_stages() -> void:
	_check("PM hp_scale w1 = 1, w11 = 1.17^10 (T1)", is_equal_approx(PowerModel.hp_scale(1, 1), 1.0) and is_equal_approx(PowerModel.hp_scale(11, 1), pow(1.17, 10.0)))
	_check("PM hp growth per tier 1.17 / 1.18 / 1.155", is_equal_approx(PowerModel.hp_growth(1), 1.17) and is_equal_approx(PowerModel.hp_growth(2), 1.18) and is_equal_approx(PowerModel.hp_growth(5), 1.155))
	_check("PM endless softens past w100", PowerModel.hp_scale(120, 1, true) < PowerModel.hp_scale(120, 1, false) and is_equal_approx(PowerModel.hp_scale(100, 1, true), PowerModel.hp_scale(100, 1, false)))
	_check("PM spawn interval 1.8 -> cap 0.45 at w21", is_equal_approx(PowerModel.spawn_interval(1), 1.8) and is_equal_approx(PowerModel.spawn_interval(21), 0.45) and PowerModel.spawn_interval(20) > 0.45 and is_equal_approx(PowerModel.spawn_interval(60), 0.45))
	_check("PM required DPS table (w1 3.33, w10 26.3, w20 ~261, T3 x2.25)", absf(PowerModel.required_dps(1, 1) - 3.333) < 0.01 and absf(PowerModel.required_dps(10, 1) - 26.3) < 0.3 and absf(PowerModel.required_dps(20, 1) - 261.0) < 3.0 and is_equal_approx(PowerModel.required_dps(10, 3) / PowerModel.required_dps(10, 3) , 1.0) and absf(PowerModel.enemy_hp("drone", 10, 3) / PowerModel.enemy_hp("drone", 10, 1) - 2.25 * pow(1.155 / 1.17, 9.0)) < 0.001)
	# PM-1: PowerModel's curves equal the engine's for a plain run.
	var S = _fresh()
	var pm1: bool = true
	for w in [1, 10, 20, 40]:
		S.wave = int(w)
		pm1 = pm1 and absf(S.scale() - PowerModel.hp_scale(int(w), 1)) < 0.0001 * S.scale() and absf(S.interval_for(int(w)) - PowerModel.spawn_interval(int(w))) < 0.0001
	_check("PM-1 engine HP scale + spawn interval == PowerModel (w1/10/20/40)", pm1)
	var snap: Dictionary = {"core_dmg": 10.0, "core_rate": 1.0, "buildings": [{"dps": 5.0}], "troops": [{"dps": 10.0}], "specials": [{"dps": 1.0}], "mult": 2.0, "core_hp": 100.0, "core_regen": 2.0}
	_check("PM effective_dps sums layers (troops x0.6) x mult", is_equal_approx(PowerModel.effective_dps(snap), (10.0 + 5.0 + 6.0 + 1.0) * 2.0))
	_check("PM power ratio = eff / required", is_equal_approx(PowerModel.power_ratio(snap, 5, 1), 44.0 / PowerModel.required_dps(5, 1)))
	_check("PM ehp grows with regen", PowerModel.ehp(snap) > 100.0 and is_equal_approx(PowerModel.ehp(snap), 100.0 * (1.0 + 2.0 * 25.0 / 100.0)))
	var fw: int = PowerModel.frontier_wave(snap, 1)
	var snap2: Dictionary = snap.duplicate(true)
	snap2["mult"] = 4.0
	_check("PM frontier wave: R crosses 1 there, more power -> later", PowerModel.power_ratio(snap, fw, 1) < 1.0 and PowerModel.power_ratio(snap, fw - 1, 1) >= 1.0 and PowerModel.frontier_wave(snap2, 1) > fw)
	_check("PM bands (frontier 0.8-1.25, early >= 2, wall < 0.6)", PowerModel.band("frontier").is_equal_approx(Vector2(0.8, 1.25)) and is_equal_approx(PowerModel.band("early").x, 2.0) and is_equal_approx(PowerModel.band("wall").y, 0.6))
	_check("PM cash index 1.10^(w-1) x (1 + 0.5(t-1))", is_equal_approx(PowerModel.cash_index(11, 1), pow(1.1, 10.0)) and is_equal_approx(PowerModel.cash_index(1, 3), 2.0))
	_check("PM cash/wave grows ~1.10 after the spawn cap (PM-5)", absf(PowerModel.cash_per_wave(31, 1) / PowerModel.cash_per_wave(30, 1) - 1.10) < 0.001)
	_check("PM-9 shards = floor(sqrt(L/1e4)), monotonic", PowerModel.shards_for(6e5) == 7 and PowerModel.shards_for(2.5e7) == 50 and PowerModel.shards_for(0.0) == 0 and PowerModel.shards_for(1e6) >= PowerModel.shards_for(9.99e5))
	_check("PM shard_mult + reforge_worth", is_equal_approx(PowerModel.shard_mult({"power": 2, "economy": 1}), 1.1 * 1.05) and PowerModel.reforge_worth(2.5e6, 20) and not PowerModel.reforge_worth(6e5, 20))
	_check("PM meta_mult = product", is_equal_approx(PowerModel.meta_mult({"parts": 1.2, "core": 1.5, "shards": 2.0}), 3.6))
	var op: Dictionary = {"buildings": [{"rate": 60.0, "lvl": 1}, {"rate": 60.0, "lvl": 5, "adj": 2.0}, {"rate": 100.0, "linked": false}], "storage_h": 8.0}
	_check("PM outpost rate (lvl +25%, layout cap 60%, unlinked 0)", is_equal_approx(PowerModel.outpost_rate(op), 60.0 + 60.0 * 2.0 * 1.6))
	_check("PM outpost collect caps at storage hours", is_equal_approx(PowerModel.outpost_collect(op, 3600.0), PowerModel.outpost_rate(op)) and is_equal_approx(PowerModel.outpost_collect(op, 86400.0), 8.0 * PowerModel.outpost_rate(op)))
	_check("PM part budget B_r x (1 + 0.06(lvl-1))", is_equal_approx(PowerModel.part_budget("epic", 1), 0.17) and is_equal_approx(PowerModel.part_budget("rare", 11), 0.12 * 1.6))
	var pa: Dictionary = {"slot": "F", "rarity": "common", "lvl": 1, "stats": {"core_hp": 0.15, "rate": -0.05}}
	var pb: Dictionary = {"slot": "F", "rarity": "common", "lvl": 1, "stats": {"core_hp": 0.10, "rate": -0.05}}
	_check("PM part value: benefit scales with lvl, drawback does not", PowerModel.part_value(pa) > PowerModel.part_value(pb) and is_equal_approx(PowerModel.part_value({"lvl": 6, "stats": {"rate": -0.05}}), PowerModel.part_value({"lvl": 1, "stats": {"rate": -0.05}})))
	_check("PM dominates: strictly better same-slot only", PowerModel.dominates(pa, pb) and not PowerModel.dominates(pb, pa) and not PowerModel.dominates(pa, pa))


func _core_run(core: String, lvl: int = 1, seed_value: int = 1234):
	var sv: Dictionary = BaseMeta.default_save()
	sv["cores"] = {"active": core, "owned": ["bastion", core], "levels": {core: lvl}}
	var S = TowerState.new()
	S.setup(seed_value, BaseMeta.normalize(sv))
	return S


## §2.1 Cores: sheets, per-level scaling, level cost, unlocks, save block.
func _core_stages() -> void:
	_check("CORE 4 Cores ship (Hive deferred, R8)", CoreDB.IDS == ["bastion", "foundry", "lance", "tempest"] and not CoreDB.has("hive"))
	var sv: Dictionary = BaseMeta.default_save()
	_check("CORE default save: Bastion active, owned, L1", Cores.active(sv) == "bastion" and Cores.owned(sv) == ["bastion"] and Cores.level(sv) == 1)
	_check("CORE level cost round(250*1.18^(L-1)) + floor(L/5) Core Cores", int(Cores.level_cost(1)["coins"]) == 250 and int(Cores.level_cost(2)["coins"]) == 295 and int(Cores.level_cost(4)["core_cores"]) == 0 and int(Cores.level_cost(5)["core_cores"]) == 1 and int(Cores.level_cost(10)["coins"]) == int(round(250.0 * pow(1.18, 9.0))))
	var snap: String = JSON.stringify(sv)
	_check("CORE try_level refuses when broke (no mutation)", Cores.try_level(sv, "bastion").is_empty() and JSON.stringify(sv) == snap)
	sv["coins"] = 1000
	var ev: Array = Cores.try_level(sv, "bastion")
	_check("CORE try_level spends coins, +1 level, event", ev.size() == 1 and Cores.level(sv, "bastion") == 2 and int(sv["coins"]) == 750)
	sv["coins"] = 1 << 30
	for k in 3:
		Cores.try_level(sv, "bastion")
	_check("CORE L5 needs a Core Core", Cores.level(sv, "bastion") == 5 and Cores.try_level(sv, "bastion").is_empty())
	sv["core_cores"] = 1
	_check("CORE Core Core spent at L5 -> L6", not Cores.try_level(sv, "bastion").is_empty() and int(sv["core_cores"]) == 0 and Cores.level(sv, "bastion") == 6)
	_check("CORE cannot level / select an unowned Core", Cores.try_level(sv, "lance").is_empty() and Cores.select(sv, "lance").is_empty())
	var u: Dictionary = BaseMeta.default_save()
	_check("CORE Foundry locked until T2 wave 30", not Cores.unlock_met(u, "foundry") and Cores.check_unlocks(u).is_empty())
	u["best_wave_by_tier"] = {"1": 40, "2": 30}
	var uev: Array = Cores.check_unlocks(u)
	_check("CORE Foundry unlocks on a T2 clear (once)", uev.size() == 1 and String(uev[0]["core"]) == "foundry" and Cores.is_owned(u, "foundry") and Cores.check_unlocks(u).is_empty())
	_check("CORE Lance needs a Reforge; Tempest needs a set-2 + best 60", not Cores.unlock_met(u, "lance") and Cores.unlock_met(u, "lance", {"reforges": 1}) and not Cores.unlock_met(u, "tempest", {"set2": true}))
	u["best_wave"] = 60
	_check("CORE Tempest with set-2 at best wave 60", Cores.unlock_met(u, "tempest", {"set2": true}) and not Cores.unlock_met(u, "tempest"))
	_check("CORE select switches the active Core", Cores.select(u, "foundry").size() == 1 and Cores.active(u) == "foundry")
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(u)))
	_check("CORE block survives JSON + normalize", Cores.active(rt) == "foundry" and Cores.is_owned(rt, "foundry") and Cores.level(rt, "foundry") == 1)
	var bad: Dictionary = BaseMeta.normalize({"cores": {"active": "hive", "owned": ["hive", "lance", "x"], "levels": {"lance": 999}}})
	_check("CORE normalize drops unknown ids, clamps levels, active falls back", Cores.active(bad) == "bastion" and Cores.owned(bad) == ["bastion", "lance"] and Cores.level(bad, "lance") == 40)
	# Core level scales its sheet (dmg x1.06, HP x1.05, regen x1.04, cash x1.04).
	var A = _core_run("bastion", 1)
	var B = _core_run("bastion", 11)
	var aw: Dictionary = _weapon(A, "core")
	var bw: Dictionary = _weapon(B, "core")
	_check("CORE L11: dmg x1.06^10, HP x1.05^10, regen x1.04^10, cash x1.04^10, rate/range flat", is_equal_approx(float(bw["dmg"]) / float(aw["dmg"]), pow(1.06, 10.0) * 1.25 / 1.25) and is_equal_approx(float(B.stats["max_hp"]), 120.0 * pow(1.05, 10.0)) and is_equal_approx(float(B.stats["regen"]), pow(1.04, 10.0)) and is_equal_approx(float(B.stats["cash_ps"]), 2.0 * pow(1.04, 10.0)) and is_equal_approx(float(bw["rate"]), float(aw["rate"])) and is_equal_approx(float(bw["range"]), float(aw["range"])))
	_check("CORE trait strength x1.25 at L10, x1.5 at L30", is_equal_approx(CoreDB.trait_mult(9), 1.0) and is_equal_approx(CoreDB.trait_mult(10), 1.25) and is_equal_approx(CoreDB.trait_mult(30), 1.5))
	for id in CoreDB.IDS:
		var C = _core_run(String(id))
		var d: Dictionary = CoreDB.get_def(String(id))
		var cw: Dictionary = _weapon(C, "core")
		_check("CORE %s sheet: dmg/rate/range/HP/cash/attack" % id, C.core_id == String(id) and is_equal_approx(float(cw["dmg"]), float(d["dmg"])) and is_equal_approx(float(cw["rate"]), float(d["rate"])) and is_equal_approx(float(cw["range"]), float(d["range"]) * TowerState.cpx()) and is_equal_approx(float(C.stats["max_hp"]), float(d["hp"])) and is_equal_approx(float(C.stats["cash_ps"]), float(d["cash"])) and String(cw["attack"]) == String(d["attack"]))
	var O = TowerState.new()
	var osv: Dictionary = BaseMeta.default_save()
	O.setup(1, osv, 0, {"core": "lance"})
	_check("CORE opts.core ignored when not owned", O.core_id == "bastion")
	# Traits.
	var T = _core_run("bastion", 10)
	for i in [16, 17, 18]:
		T.slots[i] = {"id": "mine", "perm": 0, "run": 1}
	T.recompute()
	_check("CORE Steadfast: +1%/building x1.25 at L10 on Core dmg + cash", is_equal_approx(float(_weapon(T, "core")["dmg"]), 10.0 * pow(1.06, 9.0) * (1.0 + 0.03 * 1.25)) and is_equal_approx(float(T.stats["cash_ps"]), (2.0 * pow(1.04, 9.0) + 2.4) * (1.0 + 0.03 * 1.25)))
	var F = _core_run("foundry")
	F.tracks["eco"] = 2
	F.recompute()
	_check("CORE Compound: interest cap +5 +10 per Eco level", is_equal_approx(float(F.stats["interest_cap"]), 150.0 + 2.0 * 15.0) and is_equal_approx(float(F._draft_ctx("")["eco_mult"]), 1.5))
	var L = _core_run("lance")
	L.slots[16] = {"id": "gun", "perm": 0, "run": 1}
	L.recompute()
	_check("CORE Focus: buildings in Core range -10% rate", is_equal_approx(float(_weapon(L, "gun")["rate"]), 2.0 * 0.9))


## §2.2 cash tracks: costs, effects, caps, head_start, kill-cash index.
func _track_stages() -> void:
	var S = _fresh()
	_check("TRACK 5 tracks start at 0 (head_start 0)", S.tracks == {"dmg": 0, "rate": 0, "range": 0, "eco": 0, "armor": 0})
	_check("TRACK base costs 20/30/40/25/25", S.track_cost("dmg") == 20 and S.track_cost("rate") == 30 and S.track_cost("range") == 40 and S.track_cost("eco") == 25 and S.track_cost("armor") == 25)
	S.cash = 1.0e9
	for t in ["rate", "range", "eco", "armor"]:
		S.buy_track(String(t))
	_check("TRACK cost grows by its growth", S.track_cost("rate") == int(round(30.0 * float(TowerState.TRACKS["rate"]["growth"]))) and S.track_cost("eco") == int(round(25.0 * float(TowerState.TRACKS["eco"]["growth"]))) and S.track_cost("armor") == int(round(25.0 * float(TowerState.TRACKS["armor"]["growth"]))))
	var cw: Dictionary = _weapon(S, "core")
	_check("TRACK Rate +3%, Range +0.1 cell", is_equal_approx(float(cw["rate"]), 1.25 * 1.03) and is_equal_approx(float(cw["range"]), 4.1 * TowerState.cpx()))
	_check("TRACK Eco +0.4 cash/s, interest cap +5", is_equal_approx(float(S.stats["cash_ps"]), 2.4) and is_equal_approx(float(S.stats["interest_cap"]), 55.0))
	_check("TRACK Armor +5% HP, +0.2 regen, +0.5 armor", is_equal_approx(float(S.stats["max_hp"]), 126.0) and is_equal_approx(float(S.stats["regen"]), 1.2) and is_equal_approx(float(S.stats["armor"]), 2.5))
	S.tracks["range"] = 20
	S.recompute()
	_check("TRACK capped (range 20) -> cost -1, buy refused", S.track_cost("range") == -1 and S.buy_track("range").is_empty())
	S.packs = {"pk_logistics": 2}
	S.recompute()
	_check("TRACK Logistics packs -12% cost each", S.track_cost("dmg") == int(round(20.0 * 0.88 * 0.88)))
	var hs: Dictionary = BaseMeta.default_save()
	hs["reforge"] = {"count": 1, "nodes": {"head_start": 3}}
	var H = TowerState.new()
	H.setup(1, BaseMeta.normalize(hs))
	_check("TRACK starting level = Reforge head_start", int(H.tracks["dmg"]) == 3 and int(H.tracks["armor"]) == 3 and H.core_run_lvl == 3)
	# Kill cash x 1.10^(w-1) x (1 + 0.5(t-1)).
	S = _fresh()
	S.spawn_hold = true
	S.wave = 11
	S.recompute()
	S.cash = 0.0
	S.enemies.append(_enemy("hauler", TowerState.CENTER + Vector2(0, 300), 0.0))
	S._reap([])
	_check("TRACK kill cash 3 x 1.10^10 (T1)", is_equal_approx(S.cash, 3.0 * pow(1.1, 10.0)))
	var t3: Dictionary = BaseMeta.default_save()
	t3["best_wave_by_tier"] = {"1": 40, "2": 50}
	BaseMeta.select_tier(t3, 3)
	var S3 = TowerState.new()
	S3.setup(1, t3)
	S3.spawn_hold = true
	S3.cash = 0.0
	S3.enemies.append(_enemy("drone", TowerState.CENTER + Vector2(0, 300), 0.0))
	S3._reap([])
	_check("TRACK kill cash x (1 + 0.5(t-1)) at T3", is_equal_approx(S3.cash, 2.0))


## §2.1 Core attack behaviours (events only; the view replays them).
func _core_attack_stages() -> void:
	# Bastion: Auto Cannon at the nearest, 0.5-cell splash at 40%.
	var S = _core_run("bastion")
	S.spawn_hold = true
	var a: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, -230))
	var b: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(15, -235))
	var c: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 280))
	a["eid"] = 1
	b["eid"] = 2
	c["eid"] = 3
	S.enemies = [a, b, c]
	var ev: Array = []
	S._fire(0.01, ev)
	var ca: Array = _evts(ev, "core_attack")
	_check("ATK cannon: core_attack event, nearest + 40% splash", ca.size() == 1 and String(ca[0]["kind"]) == "cannon" and is_equal_approx(999.0 - float(a["hp"]), 10.0) and is_equal_approx(999.0 - float(b["hp"]), 4.0) and is_equal_approx(float(c["hp"]), 999.0) and (ca[0]["targets"] as Array) == [1, 2])
	var S20 = _core_run("bastion", 20)
	S20.spawn_hold = true
	var e1: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, -230))
	var e2: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 280))
	S20.enemies = [e1, e2]
	S20._fire(0.01, [])
	_check("ATK Bastion L20 double barrel hits 2 targets", float(e1["hp"]) < 999.0 and float(e2["hp"]) < 999.0)
	# Foundry: Slag splash 1 cell + 2 s slow -20%.
	S = _core_run("foundry")
	S.spawn_hold = true
	a = _enemy("hauler", TowerState.CENTER + Vector2(0, -230))
	b = _enemy("hauler", TowerState.CENTER + Vector2(40, -240))
	S.enemies = [a, b]
	ev = []
	S._fire(0.01, ev)
	_check("ATK slag: full dmg splash + slow 20% for 2 s", is_equal_approx(999.0 - float(a["hp"]), 5.0) and is_equal_approx(999.0 - float(b["hp"]), 5.0) and is_equal_approx(float(a["slow_m"]), 0.8) and is_equal_approx(float(a["slow_t"]), 2.0) and String(_evts(ev, "core_attack")[0]["kind"]) == "slag")
	# Lance: highest-HP target, ramps +15%/s while held, resets on switch.
	S = _core_run("lance")
	S.spawn_hold = true
	var weak: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, -220), 100.0)
	var strong: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 300), 5000.0)
	weak["eid"] = 10
	strong["eid"] = 11
	weak["spd"] = 0.0
	strong["spd"] = 0.0
	S.enemies = [weak, strong]
	ev = S.tick(0.05)
	_check("ATK beam locks the highest-HP enemy", float(weak["hp"]) == 100.0 and float(strong["hp"]) < 5000.0 and S.beam_eid == 11)
	var hp_a: float = float(strong["hp"])
	for k in 40:
		S.tick(0.05)   # 2 s held -> next shot +30%
	var first_dmg: float = 5000.0 - hp_a
	var hp_b: float = float(strong["hp"])
	_check("ATK beam ramp builds while held (dmg > base)", S.beam_t > 1.5 and hp_b < hp_a - first_dmg * 1.2)
	strong["hp"] = 0.0
	S._reap([])
	S.tick(0.05)
	var reset_ok: bool = S.beam_eid == -1 and S.beam_t == 0.0
	for k in 45:
		S.tick(0.05)
	_check("ATK beam resets on a switch (ramp 0, then locks the next)", reset_ok and S.beam_eid == 10 and S.beam_t < 2.0)
	S = _core_run("lance")
	S.spawn_hold = true
	var boss: Dictionary = _enemy("boss", TowerState.CENTER + Vector2(0, 300), 1.0e6)
	S.enemies = [boss]
	S._fire(0.01, [])
	_check("ATK Focus: +25% vs bosses", is_equal_approx(1.0e6 - float(boss["hp"]), 28.0 * 1.25))
	# Tempest: ring hits every enemy in range once, knockback, every 5th chains.
	S = _core_run("tempest")
	S.spawn_hold = true
	var inside: Array = []
	for k in 3:
		var en: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2.from_angle(float(k) * 2.0) * 205.0)
		en["eid"] = 20 + k
		inside.append(en)
	var outer: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 400))
	outer["eid"] = 30
	S.enemies = inside + [outer]
	ev = []
	S._fire(0.01, ev)
	var all_hit: bool = true
	for en in inside:
		all_hit = all_hit and is_equal_approx(999.0 - float(en["hp"]), 6.0) and (en["pos"] as Vector2).distance_to(TowerState.CENTER) > 205.0
	_check("ATK pulse: every enemy in range once + knockback; outer untouched", all_hit and is_equal_approx(float(outer["hp"]), 999.0) and (_evts(ev, "core_attack")[0]["targets"] as Array).size() == 3)
	S.pulse_n = 4
	S.cooldowns[TowerState.CORE_SLOT] = 0.0
	for en in inside:
		en["pos"] = TowerState.CENTER + ((en["pos"] as Vector2) - TowerState.CENTER).normalized() * 205.0
	S._fire(0.01, [])
	_check("ATK Static: 5th pulse chains 40% beyond range", is_equal_approx(999.0 - float(outer["hp"]), 6.0 * 0.4))
	# Overkill carry: surplus single-target damage rolls to the next enemy.
	S = _core_run("bastion")
	S.spawn_hold = true
	var k1: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, -230), 3.0)
	var k2: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(260, 0), 50.0)
	S.enemies = [k1, k2]
	S._fire(0.01, [])
	_check("ATK overkill carry: 10 dmg kills a 3-HP drone, 60% of the 7 left rolls on", float(k1["hp"]) <= 0.0 and is_equal_approx(50.0 - float(k2["hp"]), 7.0 * 0.6))
	# Pulse with nothing in range stays ready (no wasted cooldown).
	S = _core_run("tempest")
	S.spawn_hold = true
	S.enemies = [_enemy("hauler", TowerState.CENTER + Vector2(0, 400))]
	ev = []
	S._fire(0.01, ev)
	_check("ATK no target in range: no event, attack stays ready", _evts(ev, "core_attack").is_empty() and float(S.cooldowns[TowerState.CORE_SLOT]) == 0.0)


func _ctx_empty() -> Dictionary:
	return {"owned": {}, "free": true, "free_outer": true, "huts": 0, "packs": {}, "specials": {}, "banished": [], "luck": 0, "choices": 3}


## §2.3 drafts: cadence, rarity weights + luck, G1, reroll cost, banish,
## duplicates, specials / huts / packs / Insight eligibility.
func _draft_stages() -> void:
	var w0: Dictionary = Draft.rarity_weights(0)
	var w10: Dictionary = Draft.rarity_weights(10)
	var w99: Dictionary = Draft.rarity_weights(99)
	_check("DRAFT rarity weights 60/28/10/2", is_equal_approx(float(w0["common"]), 60.0) and is_equal_approx(float(w0["rare"]), 28.0) and is_equal_approx(float(w0["epic"]), 10.0) and is_equal_approx(float(w0["legendary"]), 2.0))
	_check("DRAFT luck moves Common into Epic+ (max 10)", is_equal_approx(float(w10["common"]), 50.0) and is_equal_approx(float(w10["epic"]) + float(w10["legendary"]), 22.0) and is_equal_approx(float(w10["rare"]), 28.0) and JSON.stringify(w99) == JSON.stringify(w10))
	# Empirical rarity mix over many hands.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var cnt: Dictionary = {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	var tot: int = 0
	for k in 2000:
		var ctx: Dictionary = _ctx_empty()
		ctx["choices"] = 1
		for c in Draft.roll_hand(rng, ctx):
			cnt[String(c["rarity"])] = int(cnt[String(c["rarity"])]) + 1
			tot += 1
	_check("DRAFT empirical rarity mix ~60/28/10/2 (%s)" % JSON.stringify(cnt), absf(float(cnt["common"]) / float(tot) - 0.60) < 0.04 and absf(float(cnt["rare"]) / float(tot) - 0.28) < 0.04 and absf(float(cnt["epic"]) / float(tot) - 0.10) < 0.025 and int(cnt["legendary"]) > 10)
	# G1: every 3-card hand mixes eco and non-eco.
	var g1: bool = true
	var uniq: bool = true
	for k in 500:
		var h: Array = Draft.roll_hand(rng, _ctx_empty())
		var e: int = 0
		var seen: Dictionary = {}
		for c in h:
			if (c["tags"] as Array).has("eco"):
				e += 1
			uniq = uniq and not seen.has(String(c["id"]))
			seen[String(c["id"])] = true
		g1 = g1 and h.size() == 3 and e >= 1 and e <= 2
	_check("DRAFT G1 eco guarantee holds over 500 hands", g1)
	var g2: bool = true
	for k in 300:
		var c2: Dictionary = _ctx_empty()
		c2["weapons"] = 1
		var h2w: Array = Draft.roll_hand(rng, c2)
		var hw: bool = false
		for c in h2w:
			hw = hw or Draft.is_weapon(c)
		g2 = g2 and hw
	_check("DRAFT G2 starter guarantee: < 2 weapons -> a weapon building every hand", g2)
	var S2r = _fresh()
	var S2b = _fresh()
	S2r.spawn_hold = true
	S2b.spawn_hold = true
	S2b.grant_draft()
	S2b.reroll_draft()
	_check("RNG drafts never move the wave stream", S2r.rng.state == S2b.rng.state)
	_check("DRAFT a hand never repeats an id", uniq)
	# Guarantees.
	var ep: bool = true
	for k in 300:
		var ctx2: Dictionary = _ctx_empty()
		ctx2["guarantee"] = "epic"
		var h2: Array = Draft.roll_hand(rng, ctx2)
		ep = ep and ["epic", "legendary"].has(String(h2[0]["rarity"]))
	_check("DRAFT boss guarantee: slot 0 is Epic+", ep)
	# Eligibility.
	var ctx3: Dictionary = _ctx_empty()
	ctx3["owned"] = {"gun": 5, "mortar": 2}
	_check("DRAFT owned L5 building never offered; owned L2 -> plus 2->3", Draft.card_for("gun", ctx3).is_empty() and String(Draft.card_for("mortar", ctx3)["kind"]) == "plus" and int(Draft.card_for("mortar", ctx3)["to"]) == 3)
	ctx3["free"] = false
	_check("DRAFT no free cell -> no NEW building / hut; plus still ok", Draft.card_for("tesla", ctx3).is_empty() and Draft.card_for("hut_infantry", ctx3).is_empty() and not Draft.card_for("mortar", ctx3).is_empty())
	var ctx4: Dictionary = _ctx_empty()
	ctx4["free_outer"] = false
	_check("DRAFT railgun needs a free ring-2+ cell", Draft.card_for("railgun", ctx4).is_empty())
	ctx4["huts"] = 3
	_check("DRAFT max 3 huts; Drill Sergeant needs a hut", Draft.card_for("hut_drone", ctx4).is_empty() and not Draft.card_for("pk_barracks", ctx4).is_empty() and Draft.card_for("pk_barracks", _ctx_empty()).is_empty())
	ctx4["packs"] = {"pk_gambit": 1, "pk_arsenal": 4}
	_check("DRAFT pack stack caps (Gambit 1, Arsenal 5)", Draft.card_for("pk_gambit", ctx4).is_empty() and not Draft.card_for("pk_arsenal", ctx4).is_empty())
	ctx4["specials"] = {"sp_emp": 3, "sp_repair": 1}
	_check("DRAFT specials max 3 copies", Draft.card_for("sp_emp", ctx4).is_empty() and int(Draft.card_for("sp_repair", ctx4)["lvl"]) == 1)
	ctx4["banished"] = ["pk_ledger"]
	_check("DRAFT banished id leaves the pool", Draft.card_for("pk_ledger", ctx4).is_empty())
	_check("DRAFT Napalm Line is cut (§9)", not PickDB.DEFS.has("sp_napalm"))
	# Insight: p per slot, at most one per hand, never when blocked / capped.
	var ins_n: int = 0
	var ins_multi: bool = false
	for k in 3000:
		var ctx5: Dictionary = _ctx_empty()
		ctx5["insight_ok"] = true
		ctx5["insight_p"] = 0.01
		var h5: Array = Draft.roll_hand(rng, ctx5)
		var n5: int = 0
		for c in h5:
			if String(c["kind"]) == "insight":
				n5 += 1
		ins_n += n5
		ins_multi = ins_multi or n5 > 1
	_check("DRAFT Insight ~1%% per slot (%d in 9000 slots), max 1 per hand" % ins_n, ins_n >= 50 and ins_n <= 140 and not ins_multi)
	var ctx6: Dictionary = _ctx_empty()
	ctx6["insight_ok"] = true
	ctx6["insight_p"] = 1.0
	ctx6["insight_blocked"] = PickDB.INSIGHT.duplicate()
	var h6: Array = Draft.roll_hand(rng, ctx6)
	var none6: bool = true
	for c in h6:
		none6 = none6 and String(c["kind"]) != "insight"
	_check("DRAFT capped Insight never offered", none6 and h6.size() == 3)
	# Engine cadence: after waves 1, 2, 3, then every 2nd + boss (Epic+).
	var S = _fresh()
	_godmode(S)
	S.spawn_hold = true
	var opened: Array = []
	var guar: Dictionary = {}
	for w in range(1, 13):
		S.wave_t = S.wave_time - 0.001
		var ev: Array = S.tick(0.01)
		for d in _evts(ev, "draft_offer"):
			opened.append(w)
			if String(d["guarantee"]) == "epic":
				guar[w] = true
		while S.draft.size() > 0 or S.pending_place != "" or S.perk_offer.size() > 0:
			S.draft.clear()
			S.pending_place = ""
			S.perk_offer.clear()
			var ev2: Array = []
			S._check_queue(ev2)
			for d in _evts(ev2, "draft_offer"):
				opened.append(w)
				if String(d["guarantee"]) == "epic":
					guar[w] = true
	_check("DRAFT cadence: w1,2,3, then even waves + extra Epic+ on boss w10 (%s)" % str(opened), opened == [1, 2, 3, 4, 6, 8, 10, 10, 12] and guar.has(10))
	# Reroll pricing: 1 free per draft, then banked, then 10 doubling x1.10^(w-1).
	S = _fresh()
	S.spawn_hold = true
	S.grant_draft()
	_check("DRAFT grant_draft opens a hand", S.draft.size() == 3)
	_check("DRAFT first reroll free", S.reroll_cost() == 0 and S.reroll_draft().size() == 1 and not S.free_reroll)
	S.cash = 0.0
	_check("DRAFT paid reroll refused when broke", S.reroll_cost() == 10 and S.reroll_draft().is_empty())
	S.cash = 100.0
	S.reroll_draft()
	_check("DRAFT paid reroll 10 then 20 (doubling)", is_equal_approx(S.cash, 90.0) and S.reroll_cost() == 20)
	S.wave = 11
	_check("DRAFT reroll price x1.10^(w-1)", S.reroll_cost() == int(round(20.0 * pow(1.1, 10.0))))
	# Banish: 1 per run, id leaves the run pool, slot re-rolled.
	S = _fresh()
	S.spawn_hold = true
	S.grant_draft()
	var bid: String = String(S.draft[1]["id"])
	var bev: Array = S.banish(1)
	_check("DRAFT banish removes the id for the run + re-rolls the slot", bev.size() == 1 and S.banished == [bid] and String(S.draft[1]["id"]) != bid and S.draft.size() == 3 and S.banish_left == 0)
	_check("DRAFT only 1 banish per run", S.banish(0).is_empty())
	var never: bool = true
	for k in 100:
		for c in Draft.roll_hand(rng, S._draft_ctx("")):
			never = never and String(c["id"]) != bid
	_check("DRAFT banished id never returns this run", never)
	var bsv: Dictionary = BaseMeta.default_save()
	bsv["reforge"] = {"nodes": {"banish_plus": 2, "wide_draft": 1}}
	var BS = TowerState.new()
	BS.setup(1, BaseMeta.normalize(bsv))
	BS.spawn_hold = true
	BS.grant_draft()
	_check("DRAFT banish+ and wide_draft nodes: 3 banishes, 4 cards", BS.banish_left == 3 and BS.draft.size() == 4)
	# Picks apply: pack / special / insight / hut.
	S = _fresh()
	S.spawn_hold = true
	var dmg0: float = float(_weapon(S, "core")["dmg"])
	S.draft = [Draft.card_for("pk_arsenal", S._draft_ctx(""))]
	var pev: Array = S.choose_card(0)
	_check("DRAFT pack applies at once (+12% dmg) + pick_applied", is_equal_approx(float(_weapon(S, "core")["dmg"]), dmg0 * 1.12) and _evts(pev, "pick_applied").size() == 1 and S.picks_taken == ["pk_arsenal"])
	S.draft = [Draft.card_for("pk_gambit", S._draft_ctx(""))]
	S.choose_card(0)
	S._spawn("drone", [])
	_check("DRAFT Gambit +40% dmg, enemies +15% HP", is_equal_approx(float(_weapon(S, "core")["dmg"]), dmg0 * 1.12 * 1.4) and is_equal_approx(float(S.enemies.back()["hp"]), 6.0 * 1.15))
	S.packs = {"pk_core": 1, "pk_overclock": 1, "pk_fort": 1, "pk_optics": 1}
	S.recompute()
	var cw: Dictionary = _weapon(S, "core")
	_check("DRAFT Core Surge +30% dmg +10% rate; Overclock +8% rate -5% HP; Fortify +20% HP +1 armor; Optics +0.5 range", is_equal_approx(float(cw["dmg"]), dmg0 * 1.3) and is_equal_approx(float(cw["rate"]), 1.25 * 1.1 * 1.08) and is_equal_approx(float(S.stats["max_hp"]), 120.0 * 1.2 * 0.95) and is_equal_approx(float(S.stats["armor"]), 3.0) and is_equal_approx(float(cw["range"]), 4.5 * TowerState.cpx()))
	S.draft = [Draft.card_for("in_dmg", {"insight_ok": true})]
	pev = S.choose_card(0)
	_check("DRAFT Insight pick is recorded for banking", S.insight_found == ["in_dmg"] and _evts(pev, "insight_found").size() == 1)
	_check("DRAFT Insight run cap 1 (no more Insight offers)", not bool(S._draft_ctx("")["insight_ok"]))
	S.draft = [Draft.card_for("hut_infantry", S._draft_ctx(""))]
	S.choose_card(0)
	pev = S.place(_rc(2, 3))
	_check("DRAFT hut placed -> 3 Riflemen spawn", S.troops.size() == 3 and _evts(pev, "troop_spawn").size() == 3 and S.hut_count() == 1)


## §2.4 Specials: slots, hotkeys 1-4, cooldown in sim time, effects, events.
func _special_stages() -> void:
	var slots: Array = []
	_check("SPEC take fills slots in order", int(Specials.take(slots, "sp_emp")["slot"]) == 0 and int(Specials.take(slots, "sp_repair")["slot"]) == 1)
	var t2: Dictionary = Specials.take(slots, "sp_emp")
	_check("SPEC duplicate pick = +1 copy (max 3), -3% cd per extra", int(t2["copies"]) == 2 and is_equal_approx(Specials.cooldown("sp_emp", 2), 25.0 * 0.97) and is_equal_approx(Specials.cooldown("sp_emp", 9), 25.0 * 0.94))
	Specials.take(slots, "sp_overdrive")
	Specials.take(slots, "sp_magnet")
	var t5: Dictionary = Specials.take(slots, "sp_timewarp", 1)
	_check("SPEC 5th special replaces the chosen slot", slots.size() == 4 and String(t5["replaced"]) == "sp_repair" and String((slots[1] as Dictionary)["id"]) == "sp_timewarp")
	Specials.consume(slots, 0)
	var rev: Array = Specials.tick(slots, 10.0)
	_check("SPEC cooldown ticks down, ready event at 0", rev.is_empty() and not Specials.ready(slots, 0) and Specials.tick(slots, 20.0).size() == 1 and Specials.ready(slots, 0))
	# Engine casts.
	var S = _fresh()
	S.spawn_hold = true
	_check("SPEC empty slot -> empty", String(S.cast_special(0)["result"]) == "empty")
	S.draft = [Draft.card_for("sp_emp", S._draft_ctx(""))]
	S.choose_card(0)
	_check("SPEC EMP with no enemies -> no_target (cooldown kept)", String(S.cast_special(0)["result"]) == "no_target" and Specials.ready(S.specials, 0))
	var el: Dictionary = _enemy("elite", TowerState.CENTER + Vector2(0, 300))
	el["shield"] = 4
	S.enemies = [el]
	var r: Dictionary = S.cast_special(0)
	_check("SPEC EMP: ok + special_cast, -50% speed 4 s, shields stripped", String(r["result"]) == "ok" and _evts(r["ev"], "special_cast").size() == 1 and is_equal_approx(float(el["slow_m"]), 0.5) and is_equal_approx(float(el["slow_t"]), 4.0) and int(el["shield"]) == 0)
	_check("SPEC recast on cooldown -> cooldown", String(S.cast_special(0)["result"]) == "cooldown")
	S.set_speed(2.0)
	S.enemies.clear()
	var ready_ev: Array = []
	for k in 130:
		ready_ev.append_array(S.tick(0.1))
	_check("SPEC cooldown respects game speed (25 s at 2x in 13 s real)", _evts(ready_ev, "special_ready").size() == 1 and Specials.ready(S.specials, 0))
	# Orbital: targeted, 25x Core dmg after 0.8 s in a 1.5-cell circle.
	S = _fresh()
	S.spawn_hold = true
	S.draft = [Draft.card_for("sp_orbital", S._draft_ctx(""))]
	S.choose_card(0)
	var t1: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, -320), 1.0e6)
	var tfar: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 320), 1.0e6)
	t1["spd"] = 0.0
	tfar["spd"] = 0.0
	S.enemies = [t1, tfar]
	S.stats["weapons"].back()["range"] = 1.0
	r = S.cast_special(0, TowerState.CENTER + Vector2(0, -320))
	var dmg_core: float = float(_weapon(S, "core")["dmg"])
	_check("SPEC Orbital queues a strike (no instant dmg)", String(r["result"]) == "ok" and float(t1["hp"]) == 1.0e6 and S.orbitals.size() == 1)
	var oev: Array = []
	for k in 9:
		oev.append_array(S.tick(0.1))
	_check("SPEC Orbital lands after 0.8 s: 25x Core dmg in radius only", is_equal_approx(1.0e6 - float(t1["hp"]), 25.0 * dmg_core) and is_equal_approx(float(tfar["hp"]), 1.0e6) and _evts(oev, "orbital_hit").size() == 1)
	S = _fresh()
	S.spawn_hold = true
	S.specials = [{"id": "sp_orbital", "copies": 1, "cd": 0.0, "charges": 1}]
	var cl: Array = []
	for k in 4:
		cl.append(_enemy("drone", TowerState.CENTER + Vector2(10.0 * float(k), 300)))
	S.enemies = cl + [_enemy("drone", TowerState.CENTER + Vector2(0, -300))]
	r = S.cast_special(0)
	_check("SPEC Orbital auto-aims the densest cluster", String(r["result"]) == "ok" and (S.orbitals[0]["pos"] as Vector2).y > TowerState.CENTER.y)
	# Repair / Overdrive / Magnet / Time Warp.
	S = _fresh()
	S.spawn_hold = true
	S.specials = [{"id": "sp_repair", "copies": 1, "cd": 0.0, "charges": 1}, {"id": "sp_overdrive", "copies": 1, "cd": 0.0, "charges": 1}, {"id": "sp_magnet", "copies": 1, "cd": 0.0, "charges": 1}, {"id": "sp_timewarp", "copies": 1, "cd": 0.0, "charges": 1}]
	S.stats["regen"] = 0.0
	S.hp = 10.0
	S.cast_special(0)
	for k in 30:
		S.tick(0.1)
	_check("SPEC Repair heals 35% max HP over 3 s", absf(S.hp - (10.0 + 0.35 * 120.0)) < 0.5)
	S.cast_special(1)
	_check("SPEC Overdrive buff 6 s (Core rate x2 at fire time)", is_equal_approx(float(S.buffs["overdrive_t"]), 6.0))
	S.cast_special(2)
	S.cash = 0.0
	S.enemies = [_enemy("drone", TowerState.CENTER + Vector2(0, 300), 0.0)]
	S._reap([])
	_check("SPEC Cash Magnet: x2 kill cash", is_equal_approx(S.cash, 2.0))
	var fz: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, 400))
	S.enemies = [fz]
	S.cast_special(3)
	var p0: Vector2 = fz["pos"]
	S._move_enemies(0.5, [])
	_check("SPEC Time Warp freezes enemies 3 s", (fz["pos"] as Vector2) == p0 and is_equal_approx(float(S.buffs["warp_t"]), 3.0))


## §2.5 Troops: spawn per hut level, roam out along the lane, fight, die,
## respawn, retreat, taunt; deterministic.
func _troop_stages() -> void:
	_check("TROOP count +1 at L3 and L5", Troops.count_for("hut_infantry", 1) == 3 and Troops.count_for("hut_infantry", 3) == 4 and Troops.count_for("hut_infantry", 5) == 5 and Troops.count_for("hut_sapper", 1) == 2 and Troops.count_for("hut_drone", 1) == 4)
	var st: Dictionary = Troops.troop_stats("hut_infantry", 2, {"dmg_mult": 2.0, "hp_mult": 1.0, "respawn_minus": 2.0, "cell_px": 78.0})
	_check("TROOP stats: +25% HP/dmg per hut level, respawn - Drill Sergeant", is_equal_approx(float(st["max_hp"]), 40.0 * 1.25) and is_equal_approx(float(st["dmg"]), 5.0 * 1.25 * 2.0) and is_equal_approx(float(st["respawn"]), 6.0) and is_equal_approx(float(st["range"]), 2.0 * 78.0))
	var S = _open_run()
	S.slots[_rc(2, 3)] = {"id": "hut_infantry", "perm": 0, "run": 1}
	S.recompute()
	var sev: Array = []
	S._drain_troop_events(sev)
	_check("TROOP 3 Riflemen spawn at the hut", S.troops.size() == 3 and _evts(sev, "troop_spawn").size() == 3 and (S.troops[0]["pos"] as Vector2) == TowerState.slot_pos(_rc(2, 3)))
	var anchor: Vector2 = S.troops[0]["anchor"]
	_check("TROOP lane anchor sits outside the wall on the hut's side", anchor.distance_to(TowerState.CENTER) > TowerState.STOP_R and anchor.y < TowerState.CENTER.y)
	S.stats["weapons"] = [S.stats["weapons"].back()]
	S.stats["weapons"].back()["range"] = 1.0   # silence the Core
	for k in 60:
		S.tick(0.1)
	_check("TROOP idle troops walk out to the anchor", (S.troops[0]["pos"] as Vector2).distance_to(anchor) < 2.0)
	var foe: Dictionary = _enemy("hauler", anchor + Vector2(0, -150), 200.0)
	foe["eid"] = 900
	foe["spd"] = 0.0
	S.enemies = [foe]
	var tev: Array = []
	for k in 40:
		tev.append_array(S.tick(0.1))
	_check("TROOP seek + engage: troops hit the enemy (troop_move + troop_hit)", float(foe["hp"]) < 200.0 and _evts(tev, "troop_hit").size() > 3 and _evts(tev, "troop_move").size() >= 1)
	# Enemies hit troops in contact (50% contact dmg); Riflemen taunt.
	var gentle: Dictionary = _enemy("hauler", S.troops[0]["pos"], 1.0e9)
	gentle["eid"] = 902
	gentle["dmg"] = 0.5
	gentle["spd"] = 30.0
	S.enemies = [gentle]
	var gpos: Vector2 = gentle["pos"]
	for k in 10:
		S.tick(0.1)
	_check("TROOP Riflemen taunt (pinned enemy does not advance)", (gentle["pos"] as Vector2).distance_to(gpos) < 3.0)
	var brute: Dictionary = _enemy("hauler", S.troops[0]["pos"], 1.0e9)
	brute["eid"] = 901
	brute["dmg"] = 400.0
	brute["spd"] = 30.0
	S.enemies = [brute]
	tev = []
	for k in 10:
		tev.append_array(S.tick(0.1))
	_check("TROOP contact dmg kills troops -> troop_die + respawn timer", _evts(tev, "troop_die").size() >= 1 and S.troops.filter(func(t: Variant) -> bool: return String((t as Dictionary)["state"]) == "dead").size() >= 1)
	S.enemies.clear()
	tev = []
	for k in 100:
		tev.append_array(S.tick(0.1))
	_check("TROOP dead troops respawn at the hut after the delay", Troops.alive_count(S.troops) == 3 and _evts(tev, "troop_spawn").size() >= 1)
	# Sapper: suicide charge, aoe x2 vs armored, priority on elites.
	var tr: Array = []
	var huts: Array = [{"slot": 5, "id": "hut_sapper", "lvl": 1, "home": Vector2(0, 0), "anchor": Vector2(0, -100)}]
	var counter: Dictionary = {"next": 1}
	Troops.sync(tr, huts, {"cell_px": 78.0}, counter)
	var drone_e: Dictionary = _enemy("drone", Vector2(0, -60), 500.0)
	drone_e["eid"] = 1
	var elite_e: Dictionary = _enemy("elite", Vector2(40, -150), 500.0)
	elite_e["eid"] = 2
	var res: Dictionary = {}
	var hits: Array = []
	var died: int = 0
	for k in 60:
		res = Troops.step(tr, [drone_e, elite_e], 0.1, {"cell_px": 78.0})
		hits.append_array(res["hits"])
		died += _evts(res["ev"], "troop_die").size()
	var elite_hit: float = 0.0
	for h in hits:
		if int(h["eid"]) == 2:
			elite_hit += float(h["dmg"])
	_check("TROOP sappers charge the elite first and blast x2 vs armored", elite_hit >= 60.0 and died >= 1 and int(tr[0]["tgt"]) != 1)
	# Drones prefer flyers and retreat below 25%.
	tr = []
	Troops.sync(tr, [{"slot": 6, "id": "hut_drone", "lvl": 1, "home": Vector2(0, 0), "anchor": Vector2(0, -100)}], {"cell_px": 78.0}, counter)
	var ground: Dictionary = _enemy("hauler", Vector2(0, -90), 500.0)
	ground["eid"] = 3
	var flyer: Dictionary = _enemy("drone", Vector2(60, -200), 500.0)
	flyer["eid"] = 4
	Troops.step(tr, [ground, flyer], 0.1, {"cell_px": 78.0})
	_check("TROOP drones hunt flyers first", int(tr[0]["tgt"]) == 4)
	tr[0]["hp"] = 1.0
	res = Troops.step(tr, [ground, flyer], 0.1, {"cell_px": 78.0})
	_check("TROOP drone retreats below 25% HP", String(tr[0]["state"]) == "retreat")
	# Determinism: two identical runs with huts produce identical troop events.
	var fp: Array = []
	for rep in 2:
		var R = _fresh()
		_godmode(R)
		R.slots[_rc(2, 3)] = {"id": "hut_infantry", "perm": 0, "run": 2}
		R.slots[_rc(3, 2)] = {"id": "hut_drone", "perm": 0, "run": 1}
		R.recompute()
		var evs: Array = []
		for k in 600:
			for e in R.tick(0.1):
				var t: String = String((e as Dictionary)["t"])
				if t.begins_with("troop_"):
					evs.append(e)
			R.draft.clear()
			R.perk_offer.clear()
		fp.append(JSON.stringify(evs))
	_check("TROOP deterministic (same seed -> same troop events)", fp[0] == fp[1] and String(fp[0]).length() > 200)


## §2.6/§2.7: Insight banking, drop rolls (replayable), Courier, marked elites.
func _insight_drop_stages() -> void:
	var sv: Dictionary = BaseMeta.default_save()
	var ev: Array = PickDB.bank_insight(sv, ["in_dmg", "in_luck", "bogus"])
	_check("INS bank: +1 per pick, unknown ignored", ev.size() == 2 and int(sv["insight"]["in_dmg"]) == 1 and is_equal_approx(PickDB.insight_value(sv, "in_dmg"), 0.005) and is_equal_approx(PickDB.insight_value(sv, "in_luck"), 1.0))
	sv["insight"]["in_rate"] = 33
	PickDB.bank_insight(sv, ["in_rate", "in_rate"])
	_check("INS lifetime cap per stat (rate 10%)", is_equal_approx(PickDB.insight_value(sv, "in_rate"), 0.10) and PickDB.insight_capped(sv, "in_rate") and int(sv["insight"]["in_rate"]) == 34)
	var nb: Dictionary = BaseMeta.normalize({"insight": {"in_dmg": 999, "in_bogus": 3, "in_hp": -2}})
	_check("INS normalize clamps to cap + drops unknown", int(nb["insight"]["in_dmg"]) == 50 and not (nb["insight"] as Dictionary).has("in_bogus") and not (nb["insight"] as Dictionary).has("in_hp"))
	# Insight applies to the run and banks at run end (win or loss).
	var isv: Dictionary = BaseMeta.default_save()
	isv["insight"] = {"in_dmg": 10, "in_hp": 20, "in_luck": 3}
	var S = TowerState.new()
	S.setup(1, BaseMeta.normalize(isv))
	_check("INS applies: +5% dmg, +10% HP, Luck 3", is_equal_approx(float(_weapon(S, "core")["dmg"]), 10.0 * 1.05) and is_equal_approx(float(S.stats["max_hp"]), 132.0) and S.luck == 3)
	S.insight_found = ["in_cash"]
	S.loot = {"parts": [{"rarity": "epic", "source": "boss"}], "scrap": 10, "keys": 1, "capped_parts": 0}
	var dev: Array = S.abandon()
	var go: Dictionary = _evts(dev, "game_over")[0]
	# REDESIGN (ENGINE-META, deliberate): a banked part drop now resolves into a
	# concrete part of its rarity (seeded) instead of waiting in part_drops.
	var pn: Array = _evts(dev, "part_new")
	_check("INS + loot banked at run end (abandon = loss path)", int(S.save["insight"]["in_cash"]) == 1 and _evts(dev, "insight_banked").size() == 1 and int(S.save["scrap"]) == 10 and int(S.save["keys"]) == 1 and (S.save["part_drops"] as Array).is_empty() and pn.size() == 1 and String(pn[0]["rarity"]) == "epic" and Parts.count(S.save) == 1 and _evts(dev, "loot_banked").size() == 1 and (go["insight"] as Array) == ["in_cash"])
	# Drops: rates and replay.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var boss_parts: int = 0
	var rar: Dictionary = {}
	for k in 4000:
		for d in Drops.roll(rng, "boss", {"tier": 2}):
			if String(d["kind"]) == "part":
				boss_parts += 1
				rar[String(d["rarity"])] = int(rar.get(String(d["rarity"]), 0)) + 1
	_check("DROP boss 12%% part, Rare+ only (%d / 4000, %s)" % [boss_parts, JSON.stringify(rar)], boss_parts > 400 and boss_parts < 560 and not rar.has("common") and int(rar.get("rare", 0)) > int(rar.get("epic", 0)))
	var bd: Array = Drops.roll(rng, "boss", {"tier": 3})
	var scrap_ok: bool = false
	for d in bd:
		scrap_ok = scrap_ok or (String(d["kind"]) == "scrap" and int(d["n"]) == 15)
	_check("DROP boss always gives 5*T Scrap", scrap_ok)
	var cd: Array = Drops.roll(rng, "courier", {"parts_so_far": 99})
	_check("DROP Courier: 100% part (ignores the cap) + 1 Key", cd.size() == 2 and String(cd[0]["kind"]) == "part" and String(cd[1]["kind"]) == "key" and ["rare", "epic", "legendary"].has(String(cd[0]["rarity"])))
	var capped: int = 0
	for k in 2000:
		for d in Drops.roll(rng, "elite", {"parts_so_far": 3}):
			if String(d["kind"]) == "part":
				capped += 1
	_check("DROP part cap 3 per run (non-Courier)", capped == 0)
	var el_dm: int = 0
	var el_base: int = 0
	for k in 20000:
		for d in Drops.roll(rng, "elite", {"drop_mult": 1.15}):
			if String(d["kind"]) == "part":
				el_dm += 1
	_check("DROP elite ~3%% x in_drop (%d / 20000 at x1.15)" % el_dm, el_dm > 560 and el_dm < 840)
	var loot: Dictionary = Drops.empty_loot()
	Drops.add(loot, [{"kind": "part", "rarity": "rare", "source": "elite"}, {"kind": "scrap", "n": 5}, {"kind": "key", "n": 1}, {"kind": "part_capped", "rarity": "rare"}, {"kind": "part", "rarity": "epic", "source": "courier"}])
	_check("DROP loot fold: parts / scrap / keys / capped count", (loot["parts"] as Array).size() == 2 and int(loot["scrap"]) == 5 and int(loot["keys"]) == 1 and int(loot["capped_parts"]) == 1 and Drops.capped_count(loot) == 1)
	# Engine: boss kill emits drop events; drops replay with the seed and
	# never perturb the wave RNG.
	var A = _fresh()
	var B = _fresh()
	A.spawn_hold = true
	B.spawn_hold = true
	var da: Array = []
	var db: Array = []
	for k in 40:
		A.enemies.append(_enemy("boss", TowerState.CENTER + Vector2(0, 300), 0.0))
		A._reap(da)
		B.enemies.append(_enemy("boss", TowerState.CENTER + Vector2(0, 300), 0.0))
		B._reap(db)
	_check("DROP engine: boss drops emitted + replay exactly", _evts(da, "drop").size() >= 40 and JSON.stringify(_evts(da, "drop")) == JSON.stringify(_evts(db, "drop")) and int(A.loot["scrap"]) == 200)
	var C = _fresh()
	_check("DROP loot RNG is separate from the wave RNG", A.rng.state == C.rng.state)
	# Courier spawns, runs on a chord outside the wall, escapes or drops.
	var K = _fresh()
	K.spawn_hold = true
	K.active_quads = [0]
	var kev: Array = []
	K._spawn_courier(kev)
	var cour: Dictionary = K.enemies.back()
	_check("COURIER spawn event, 2x drone HP, 3x speed", _evts(kev, "courier_spawn").size() == 1 and String(cour["kind"]) == "courier" and is_equal_approx(float(cour["max_hp"]), 12.0) and is_equal_approx(float(cour["spd"]), 135.0))
	var min_d: float = INF
	var esc: Array = []
	for k in 200:
		var e2: Array = []
		K._move_enemies(0.05, e2)
		esc.append_array(e2)
		if not K.enemies.is_empty():
			min_d = minf(min_d, (K.enemies[0]["pos"] as Vector2).distance_to(TowerState.CENTER))
	_check("COURIER stays outside the wall and escapes", min_d > TowerState.STOP_R + 30.0 and _evts(esc, "courier_escape").size() == 1 and K.enemies.is_empty())
	_check("COURIER never before wave 15", not Drops.courier_roll(rng, 14))
	var cw: Dictionary = {}
	var hits_c: int = 0
	for k in 10000:
		if Drops.courier_roll(rng, 20):
			hits_c += 1
	_check("COURIER ~0.6%% per wave from w15 (%d / 10000)" % hits_c, hits_c > 35 and hits_c < 90)
	# Marked elites carry loot (x3 HP) and roll on the elite table.
	var M = _fresh()
	var marked_seen: bool = false
	for w in range(8, 40):
		var p: Dictionary = M._build_plan(w, 0.0)
		for en in p["entries"]:
			marked_seen = marked_seen or bool((en as Dictionary).get("marked", false))
	_check("MARK marked elites appear from w8", marked_seen and not _plan_has_mark(M, 7))
	M.spawn_hold = true
	M._spawn("drone", [], Vector2.INF, 0, true)
	_check("MARK marked enemy x3 HP + flag", bool(M.enemies.back()["marked"]) and is_equal_approx(float(M.enemies.back()["max_hp"]), 18.0))


func _plan_has_mark(S, w: int) -> bool:
	for k in 30:
		var p: Dictionary = S._build_plan(w, 0.0)
		for en in p["entries"]:
			if bool((en as Dictionary).get("marked", false)):
				return true
	return false


## §2.7 power_snapshot feeds PowerModel; R tracks the board.
func _snapshot_stages() -> void:
	var S = _fresh()
	var snap: Dictionary = S.power_snapshot()
	_check("SNAP keys: core dmg/rate/hp/regen, buildings, troops, specials, mult", snap.has("core_dmg") and snap.has("core_rate") and snap.has("core_hp") and snap.has("core_regen") and snap.has("buildings") and snap.has("troops") and snap.has("specials") and is_equal_approx(float(snap["mult"]), 1.0))
	_check("SNAP Bastion L1 values", is_equal_approx(float(snap["core_dmg"]), 10.0) and is_equal_approx(float(snap["core_rate"]), 1.25) and is_equal_approx(float(snap["core_hp"]), 120.0))
	var r0: float = PowerModel.power_ratio(snap, 1, 1)
	S.slots[_rc(2, 3)] = {"id": "gun", "perm": 0, "run": 1}
	S.slots[_rc(3, 2)] = {"id": "hut_drone", "perm": 0, "run": 1}
	S.specials = [{"id": "sp_orbital", "copies": 1, "cd": 0.0, "charges": 1}]
	S.recompute()
	var snap2: Dictionary = S.power_snapshot()
	_check("SNAP lists building DPS, troops, orbital DPS", (snap2["buildings"] as Array).size() == 1 and is_equal_approx(float(snap2["buildings"][0]["dps"]), 12.0 * TowerState.bld_dmg()) and (snap2["troops"] as Array).size() == 4 and float(snap2["specials"][0]["dps"]) > 0.0)
	_check("SNAP power ratio rises with the board", PowerModel.power_ratio(snap2, 1, 1) > r0 and r0 > 2.0)


# ======================================================================
# ENGINE-META (REDESIGN_SPEC §3): Parts, Crates, Outpost, Research, Reforge,
# save v4. TDD'd here; each sub-stage is one system.
# ======================================================================
func _engine_meta_stages() -> void:
	_parts_data_stages()
	_parts_rule_stages()
	_parts_engine_stages()
	_crate_stages()
	_outpost_stages()


## A save owning `ids` (fresh items, L1), Core `core` at level `lvl`.
func _parts_save(ids: Array, core: String = "bastion", lvl: int = 40) -> Dictionary:
	var sv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	if core != "bastion":
		(sv["cores"]["owned"] as Array).append(core)
	sv["cores"]["active"] = core
	sv["cores"]["levels"][core] = lvl
	for id in ids:
		Parts.grant(sv, String(id))
	return sv


## Equip ids into the first fitting open slots of the active Core.
func _equip_all(sv: Dictionary, ids: Array) -> void:
	var core: String = String(sv["cores"]["active"])
	for id in ids:
		var uid: String = Parts.uid_of(sv, String(id))
		for k in Parts.N_SLOTS:
			if Parts.fits(sv, uid, k) and String(Parts.preset(sv, core)[k]) == "" and Parts.slot_open(Cores.level(sv, core), k):
				Parts.equip(sv, core, k, uid)
				break


## AC-11 / AC-12: data shape, budget, trade-off, Pareto; set budgets.
func _parts_data_stages() -> void:
	_check("PART 32 parts + 5 set specials", PartDB.DEFS.size() == 32 and PartDB.SPECIALS.size() == 5)
	var shape: bool = true
	var budget: Array = []
	var trade: Array = []
	var w: Dictionary = PartDB.val_weights()
	for id in PartDB.DEFS.keys() + PartDB.SPECIALS.keys():
		var d: Dictionary = PartDB.get_def(String(id))
		shape = shape and PartDB.SLOTS.has(String(d["slot"])) and PartDB.MAX_LVL.has(String(d["rarity"])) and not (d["plus"] as Dictionary).is_empty() and not (d["minus"] as Dictionary).is_empty()
		for k in (d["plus"] as Dictionary).keys() + (d["minus"] as Dictionary).keys():
			shape = shape and PartDB.VAL.has(String(k)) and PartDB.FX_TEXT.has(String(k))
		var v: float = PowerModel.part_value(PartDB.pm_part(String(id)), w)
		var b: float = PowerModel.part_budget(String(d["rarity"]), 1)
		if absf(v - b) > 0.10 * b:
			budget.append("%s %.3f/%.3f" % [id, v, b])
		var pos: float = PowerModel.part_value({"lvl": 1, "stats": PartDB.val_stats(d["plus"])}, w)
		var neg: float = PowerModel.part_value({"lvl": 1, "stats": PartDB.val_stats(d["minus"])}, w)
		if pos <= 0.0 or neg >= 0.0 or -neg < 0.25 * pos:
			trade.append(id)
	_check("AC-11 every part: slot, rarity, >=1 benefit, >=1 drawback, known fx keys", shape)
	_check("AC-12 every part value within 10% of its budget (L1)", budget.is_empty(), str(budget))
	_check("AC-12 every drawback >= 25% of its benefit", trade.is_empty(), str(trade))
	var dom: Array = []
	var ids: Array = PartDB.DEFS.keys() + PartDB.SPECIALS.keys()
	for a in ids:
		for b2 in ids:
			if a == b2 or PartDB.rarity_of(String(a)) != PartDB.rarity_of(String(b2)):
				continue
			if PowerModel.dominates(PartDB.pm_part(String(a)), PartDB.pm_part(String(b2))):
				dom.append("%s>%s" % [a, b2])
	_check("AC-12 Pareto: no part dominates another of its slot and rarity", dom.is_empty(), str(dom))
	var setb: Array = []
	for st in SetDB.IDS:
		var sd: Dictionary = SetDB.get_def(String(st))
		var B: float = PowerModel.part_budget(SetDB.budget_rarity(String(st), PartDB.rarity_of), 1)
		var v2: float = PowerModel.part_value({"lvl": 1, "stats": PartDB.val_stats(sd["two"])}, w)
		var v4: float = PowerModel.part_value({"lvl": 1, "stats": PartDB.val_stats(sd["four"])}, w)
		if v2 > 0.5 * B or v4 > 1.2 * B:
			setb.append(st)
		for m in sd["members"]:
			if PartDB.set_of(String(m)) != String(st):
				setb.append(m)
		if PartDB.set_of(SetDB.special_of(String(st))) != String(st) or not PartDB.is_special(SetDB.special_of(String(st))):
			setb.append(st)
	_check("SET budgets: 2-piece <= 0.5B, 4-piece <= 1.2B; members + special tagged", setb.is_empty(), str(setb))
	# Every full set fits one Core's 6 normal slots at once.
	var fit: Array = []
	for st in SetDB.IDS:
		var need: Dictionary = {}
		for m in SetDB.get_def(String(st))["members"]:
			need[PartDB.slot_of(String(m))] = int(need.get(PartDB.slot_of(String(m)), 0)) + 1
		for k in need.keys():
			if int(need[k]) > Parts.SLOT_TYPES.slice(0, 6).count(k):
				fit.append(st)
	_check("SET every full set fits the F/B/C/E/F/B slots", fit.is_empty(), str(fit))
	var pools: bool = true
	for r in PartDB.RARITIES:
		for id in PartDB.pool(String(r)):
			pools = pools and not PartDB.is_special(String(id)) and PartDB.rarity_of(String(id)) == String(r)
	_check("PART pools by rarity exclude set specials", pools and PartDB.pool("legendary").size() == 3)
	var ln: Dictionary = PartDB.lines("f_plating")
	_check("PART tooltip has a + and a - line", (ln["plus"] as Array).size() == 1 and (ln["minus"] as Array).size() == 1 and String(ln["plus"][0]).begins_with("+ ") and String(ln["minus"][0]).begins_with("- "))


## AC-13 / AC-14 / AC-16: inventory, leveling, salvage, slots, presets, sets.
func _parts_rule_stages() -> void:
	var sv: Dictionary = _parts_save([], "bastion", 1)
	var ev: Array = Parts.grant(sv, "f_plating", "crate")
	var uid: String = Parts.uid_of(sv, "f_plating")
	_check("PART grant: new item L1", _evts(ev, "part_new").size() == 1 and uid != "" and int(Parts.item(sv, uid)["lvl"]) == 1 and Parts.count(sv) == 1)
	Parts.grant(sv, "f_plating")
	Parts.grant(sv, "f_plating")
	var ev3: Array = Parts.grant(sv, "f_plating")
	_check("PART duplicates: 2 stars then auto-salvage for Scrap", int(Parts.item(sv, uid)["stars"]) == 2 and _evts(ev3, "part_dup_salvaged").size() == 1 and int(sv["scrap"]) == 5 and Parts.count(sv) == 1)
	_check("PART level cost 10*r*1.25^(L-1)", PartDB.level_cost("f_plating", 1) == 10 and PartDB.level_cost("f_glass", 3) == int(round(80.0 * 1.5625)) and PartDB.level_cost("b_hollow", 2) == 25)
	_check("PART level up refused without Scrap", Parts.level_up(sv, uid).is_empty() and int(Parts.item(sv, uid)["lvl"]) == 1)
	sv["scrap"] = 1000
	var lv: Array = Parts.level_up(sv, uid)
	_check("AC-16 level up spends Scrap per formula", lv.size() == 1 and int(Parts.item(sv, uid)["lvl"]) == 2 and int(sv["scrap"]) == 990)
	for k in 10:
		Parts.level_up(sv, uid)
	_check("PART max level by rarity (common 5)", int(Parts.item(sv, uid)["lvl"]) == 5 and not Parts.can_level(sv, uid))
	var inv: int = PartDB.invested("f_plating", 5)
	_check("PART invested = sum of level costs", inv == 10 + 13 + 16 + 20)
	Parts.set_locked(sv, uid, true)
	_check("AC-16 locked parts cannot be salvaged", Parts.salvage(sv, uid).is_empty() and Parts.owns(sv, "f_plating"))
	Parts.set_locked(sv, uid, false)
	var s0: int = int(sv["scrap"])
	var sev: Array = Parts.salvage(sv, uid)
	_check("AC-16 salvage = base + 50% invested", sev.size() == 1 and int(sv["scrap"]) == s0 + 5 + int(round(0.5 * float(inv))) and not Parts.owns(sv, "f_plating"))
	# Slots by Core level (AC-14).
	_check("AC-14 slots 2/3/4/5/6 at L1/5/12/20/30, Set slot at L40", Parts.slot_count(1) == 2 and Parts.slot_count(4) == 2 and Parts.slot_count(5) == 3 and Parts.slot_count(12) == 4 and Parts.slot_count(20) == 5 and Parts.slot_count(30) == 6 and not Parts.slot_open(39, 6) and Parts.slot_open(40, 6))
	var s2: Dictionary = _parts_save(["f_plating", "b_longbore", "c_overcharge", "citadel_heart"], "bastion", 1)
	var up: String = Parts.uid_of(s2, "f_plating")
	var ub: String = Parts.uid_of(s2, "b_longbore")
	var uc: String = Parts.uid_of(s2, "c_overcharge")
	_check("AC-14 wrong slot type refused", Parts.equip(s2, "bastion", 1, up).is_empty() and Parts.equip(s2, "bastion", 0, ub).is_empty())
	_check("AC-14 locked slot refused (C slot at L1)", Parts.equip(s2, "bastion", 2, uc).is_empty())
	_check("AC-14 right slot accepted", Parts.equip(s2, "bastion", 0, up).size() >= 1 and Parts.equip(s2, "bastion", 1, ub).size() >= 1 and Parts.equipped(s2, "bastion").size() == 2)
	var uh: String = Parts.uid_of(s2, "citadel_heart")
	_check("AC-14 set special only in the Set slot or its own type", Parts.fits(s2, uh, 6) and Parts.fits(s2, uh, 3) and not Parts.fits(s2, up, 6))
	Parts.select_preset(s2, "bastion", 2)
	_check("PRESET 2 starts empty", Parts.equipped(s2, "bastion").is_empty())
	Parts.equip(s2, "bastion", 0, up)
	var js: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(s2)))
	var p0: Array = Parts.preset(js, "bastion", 0)
	_check("AC-14 4 presets per Core round-trip save/load", Parts.preset_idx(js, "bastion") == 2 and Parts.equipped(js, "bastion").size() == 1 and String(p0[0]) == up and String(p0[1]) == ub and (js["cores"]["presets"]["bastion"] as Array).size() == 4)
	Parts.select_preset(js, "bastion", 0)
	Parts.unequip(js, "bastion", 1)
	_check("PART unequip", Parts.equipped(js, "bastion").size() == 1)
	var sal: Dictionary = js.duplicate(true)
	Parts.salvage(sal, up)
	_check("PART salvage strips the part from presets", Parts.equipped(sal, "bastion").is_empty())
	# Sets (AC-13).
	var ms: Dictionary = _parts_save(["f_ledgerframe", "b_bounty", "c_interest", "e_mintpress"], "bastion", 40)
	_equip_all(ms, ["f_ledgerframe", "b_bounty"])
	var fx2: Dictionary = Parts.run_fx(ms, "bastion")
	_check("AC-13 2-piece active at 2 distinct members", int(Parts.set_counts(ms, "bastion").get("mint", 0)) == 2 and is_equal_approx(float(fx2.get("cash", 0.0)), 0.10) and not fx2.has("interest_fast") and Parts.any_set2(ms))
	var cev: Array = []
	for id in ["c_interest", "e_mintpress"]:
		var u2: String = Parts.uid_of(ms, String(id))
		for k in Parts.N_SLOTS:
			if Parts.fits(ms, u2, k) and String(Parts.preset(ms, "bastion")[k]) == "":
				cev.append_array(Parts.equip(ms, "bastion", k, u2))
				break
	var fx4: Dictionary = Parts.run_fx(ms, "bastion")
	_check("AC-13 4-piece active + full set unlocks Golden Ratio once", is_equal_approx(float(fx4.get("interest_fast", 0.0)), 1.0) and _evts(cev, "set_complete").size() == 1 and _evts(cev, "special_part_unlocked").size() == 1 and Parts.owns(ms, "golden_ratio") and (ms["parts"]["sets_completed"] as Array) == ["mint"])
	var ms2: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(ms)))
	_check("AC-13 set unlock + special persist through save/load", (ms2["parts"]["specials_unlocked"] as Array).has("golden_ratio") and Parts.owns(ms2, "golden_ratio"))
	_check("AC-13 completing again does not re-grant", Parts.check_sets(ms2, "bastion").is_empty())
	# Stacking rule: same stat additive; plus scales with lvl/stars, minus never.
	var st: Dictionary = _parts_save(["f_glass"], "bastion", 1)
	_equip_all(st, ["f_glass"])
	var g: String = Parts.uid_of(st, "f_glass")
	(Parts.item(st, g) as Dictionary)["lvl"] = 6
	(Parts.item(st, g) as Dictionary)["stars"] = 1
	var gx: Dictionary = Parts.run_fx(st, "bastion")
	_check("PART fx: plus x(1+0.08(L-1))x(1+0.05 stars), minus unscaled", is_equal_approx(float(gx["dmg"]), 0.45 * 1.4 * 1.05) and is_equal_approx(float(gx["core_hp"]), -0.23))
	# Seeded drop resolution.
	var r1 := RandomNumberGenerator.new()
	var r2 := RandomNumberGenerator.new()
	r1.seed = 77
	r2.seed = 77
	var da: Dictionary = _parts_save([], "bastion", 1)
	var db: Dictionary = _parts_save([], "bastion", 1)
	da["part_drops"] = [{"rarity": "rare", "source": "boss"}, {"rarity": "legendary", "source": "courier"}]
	db["part_drops"] = da["part_drops"].duplicate(true)
	Parts.resolve_drops(da, r1)
	Parts.resolve_drops(db, r2)
	var ia: Array = []
	for k in Parts.items(da).keys():
		ia.append(String(Parts.items(da)[k]["id"]))
	var ib: Array = []
	for k in Parts.items(db).keys():
		ib.append(String(Parts.items(db)[k]["id"]))
	_check("DROP resolve: seeded, rarity kept, part_drops emptied", ia == ib and ia.size() == 2 and PartDB.rarity_of(String(ia[0])) == "rare" and PartDB.rarity_of(String(ia[1])) == "legendary" and (da["part_drops"] as Array).is_empty())
	# Reforge part reset: levels to 1, 50% invested refunded.
	var rs: Dictionary = _parts_save(["f_glass"], "bastion", 1)
	var rg: String = Parts.uid_of(rs, "f_glass")
	(Parts.item(rs, rg) as Dictionary)["lvl"] = 4
	var ref: int = Parts.reforge_reset(rs)
	_check("PART reforge reset: L1, 50% Scrap refund", int(Parts.item(rs, rg)["lvl"]) == 1 and ref == PartDB.invested("f_glass", 4) / 2 and int(rs["scrap"]) == ref)
	# Tempest unlock reads the live 2-piece (Cores ctx from Parts).
	var ts: Dictionary = BaseMeta.normalize(ms.duplicate(true))
	ts["best_wave"] = 60
	BaseMeta.bank_loot(ts, Drops.empty_loot())
	_check("CORE Tempest unlocks with a 2-piece + best wave 60", Cores.is_owned(ts, "tempest"))


func _parts_run(ids: Array, core: String = "bastion", lvl: int = 40, seed_value: int = 1234):
	var sv: Dictionary = _parts_save(ids, core, lvl)
	_equip_all(sv, ids)
	var S = TowerState.new()
	S.setup(seed_value, sv)
	return S


## Every equipped part's benefit and drawback reach the run (TowerState.setup).
func _parts_engine_stages() -> void:
	var B = _parts_run([], "bastion", 1)
	var core0: Dictionary = _weapon(B, "core")
	var P = _parts_run(["f_plating"], "bastion", 1)
	var core1: Dictionary = _weapon(P, "core")
	_check("RUN Plating: +28% Core HP, -4.2% rate", is_equal_approx(float(P.stats["max_hp"]), float(B.stats["max_hp"]) * 1.28) and is_equal_approx(float(core1["rate"]), float(core0["rate"]) * (1.0 - 0.042)) and is_equal_approx(P.hp, float(P.stats["max_hp"])))
	var G = _parts_run(["f_glass"], "bastion", 1)
	_check("RUN Glass Cannon: +45% all dmg, -23% HP", is_equal_approx(float(_weapon(G, "core")["dmg"]), float(core0["dmg"]) * 1.45) and is_equal_approx(float(G.stats["max_hp"]), float(B.stats["max_hp"]) * 0.77))
	var T = _parts_run(["e_turbine", "f_ledgerframe"], "bastion", 40)
	var B40 = _parts_run([], "bastion", 40)
	_check("RUN Turbine + Ledger: flat cash/s, -dmg, -HP", float(T.stats["cash_ps"]) > float(B40.stats["cash_ps"]) and float(_weapon(T, "core")["dmg"]) < float(_weapon(B40, "core")["dmg"]) and float(T.stats["max_hp"]) < float(B40.stats["max_hp"]))
	var L = _parts_run(["b_longbore"], "bastion", 1)
	_check("RUN Long Bore: +0.72 range cells, -rate", is_equal_approx(float(_weapon(L, "core")["range_cells"]), float(core0["range_cells"]) + 0.72) and float(_weapon(L, "core")["rate"]) < float(core0["rate"]))
	var R = _parts_run(["e_railcore"], "bastion", 40)
	_check("RUN Rail Core: +69% Core dmg, no splash", is_equal_approx(float(_weapon(R, "core")["dmg"]), float(_weapon(B40, "core")["dmg"]) * 1.69) and is_equal_approx(float(_weapon(R, "core")["splash"]), 0.0))
	var C = _parts_run(["c_luckchip"], "bastion", 12)
	_check("RUN Luck Chip: +3 Luck", C.luck == 3)
	var Q = _parts_run(["c_quickcap"], "bastion", 12)
	_check("RUN Quick Cap: special cd x0.821, dmg x0.879", is_equal_approx(float(Q.mods["special_cd"]), 1.0 - 0.179) and is_equal_approx(float(Q.mods["special_dmg"]), 1.0 - 0.121))
	var H = _parts_run(["e_bastionheart"], "bastion", 20)
	_check("RUN Bastion Heart: rings open one step later", H.ring_threshold(2) == 30 and H.ring_threshold(3) == 60 and B.ring_threshold(2) == 10)
	# Hunter Scope: bosses take more, normal enemies less (in _hit).
	var S = _parts_run(["c_scope"], "bastion", 12)
	var eb: Dictionary = _enemy("boss", Vector2(400, 400), 1000.0)
	var en: Dictionary = _enemy("drone", Vector2(400, 400), 1000.0)
	S._hit(eb, 100.0, [])
	S._hit(en, 100.0, [])
	_check("RUN Hunter Scope: +45% vs boss, -8.7% vs normal", is_equal_approx(float(eb["hp"]), 1000.0 - 145.0) and is_equal_approx(float(en["hp"]), 1000.0 - 91.3))
	# Mirror Hull: contact damage reflects.
	var M = _parts_run(["f_mirror"], "bastion", 12)
	var em: Dictionary = _enemy("drone", Vector2(400, 400), 1000.0)
	M._core_damage(10.0, [], "core_hit", em["pos"], em)
	_check("RUN Mirror Hull reflects 18.2% of contact dmg", is_equal_approx(float(em["hp"]), 1000.0 - 1.82))
	# Bulwark 4-piece: last stand once per wave.
	var W = _parts_run(["f_bulkhead", "f_regenmesh", "f_mirror", "e_bastionheart"], "bastion", 40)
	W.hp = float(W.stats["max_hp"]) * 0.35
	var lev: Array = []
	W._core_damage(float(W.stats["max_hp"]) * 0.2, lev, "core_hit", Vector2.ZERO)
	var hp1: float = W.hp
	W._core_damage(50.0, lev, "core_hit", Vector2.ZERO)
	_check("RUN Bulwark 4-piece: 2 s immunity below 30% (once)", _evts(lev, "last_stand").size() == 1 and is_equal_approx(W.hp, hp1) and W.last_stand_used)
	# Battery Bank stores an extra special charge.
	var Bt = _parts_run(["c_battery"], "bastion", 12)
	Bt.specials = [{"id": "sp_repair", "copies": 1, "cd": 0.0, "charges": 1}]
	_check("RUN Battery: 1st cast", String(Bt.cast_special(0)["result"]) == "ok")
	Bt._tick_buffs(Specials.cooldown("sp_repair", 1) + 0.1, [])
	_check("RUN Battery: a finished cooldown banks a charge and restarts", int(Bt.specials[0]["bank"]) == 1 and float(Bt.specials[0]["cd"]) > 0.0 and String(Bt.cast_special(0)["result"]) == "ok" and String(Bt.cast_special(0)["result"]) == "cooldown")
	# Hivecomb / Drone Port: more troops.
	var Hv = _parts_run(["f_hivecomb", "b_droneport"], "bastion", 40)
	var tm: Dictionary = Hv._troop_mods()
	_check("RUN Hivecomb +1 troop/hut, Drone Port +1 drone, troop HP -31% (+15% Swarm 2-piece)", int(tm["extra"]) == 1 and int(tm["extra_drone"]) == 1 and is_equal_approx(float(tm["hp_mult"]), float(B40._troop_mods()["hp_mult"]) * (1.0 - 0.31 + 0.15)))
	# Mint 4-piece: interest every 15 s instead of per wave.
	var Mi = _parts_run(["f_ledgerframe", "b_bounty", "c_interest", "e_mintpress"], "bastion", 40)
	Mi.spawn_hold = true
	Mi.wave_started = true
	Mi.cash = 100.0
	var iev: Array = []
	for k in 160:
		Mi._step(0.1, iev)
	_check("RUN Mint 4-piece pays interest every 15 s", _evts(iev, "interest").size() == 1)
	# Lancer 4-piece: Core shots pierce one extra enemy.
	var Lp = _parts_run(["b_hollow", "b_focuslens", "c_scope", "e_railcore"], "bastion", 40)
	_check("RUN Lancer 4-piece: pierce 1", int(_weapon(Lp, "core")["pierce"]) == 1)
	# Same seed, same parts -> same run fingerprint (determinism kept).
	var f1 = _parts_run(["f_glass", "b_crit"], "bastion", 12, 99)
	var f2 = _parts_run(["f_glass", "b_crit"], "bastion", 12, 99)
	_godmode(f1)
	_godmode(f2)
	var a1: Array = _sim_waves(f1, 4)
	var a2: Array = _sim_waves(f2, 4)
	_check("RUN parts keep the run deterministic", JSON.stringify(a1).length() > 100 and JSON.stringify(a1) == JSON.stringify(a2))


## AC-15: crate odds (disclosed), pity (saved), costs, duplicates -> stars.
func _crate_stages() -> void:
	var sv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	_check("CRATE Field cost 2,500 x (1 + 0.25(T-1))", Crates.coin_cost(sv) == 2500)
	sv["best_wave_by_tier"] = {"1": 60, "2": 60, "3": 10}
	_check("CRATE Field cost scales with tier (T3 x1.5)", Crates.coin_cost(sv) == 3750)
	sv["research"] = {"lvls": {"crate_theory": 5}}
	_check("CRATE Crate Theory -2%/level", Crates.coin_cost(sv) == int(round(3750.0 * 0.9)))
	var o: Dictionary = Crates.odds(BaseMeta.default_save(), "field")
	_check("CRATE disclosed odds = table (sum 100)", is_equal_approx(float(o["common"]), 70.0) and is_equal_approx(float(o["legendary"]), 0.5) and is_equal_approx(float(o["common"]) + float(o["rare"]) + float(o["epic"]) + float(o["legendary"]), 100.0))
	var lk: Dictionary = BaseMeta.default_save()
	lk["reforge"] = {"nodes": {"crate_luck": 5}}
	_check("CRATE crate_luck raises Epic+ odds relatively", float(Crates.odds(lk, "supply")["epic"]) > 12.0 and float(Crates.odds(lk, "supply")["legendary"]) > 3.0)
	# 10,000 seeded rolls match the disclosed odds (pure roll, no pity).
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var cnt: Dictionary = {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	for k in 10000:
		var r: String = Crates.roll_rarity(rng, o)
		cnt[r] = int(cnt[r]) + 1
	_check("AC-15 10,000 Field rolls within tolerance of 70/25/4.5/0.5", absi(int(cnt["common"]) - 7000) < 200 and absi(int(cnt["rare"]) - 2500) < 170 and absi(int(cnt["epic"]) - 450) < 70 and absi(int(cnt["legendary"]) - 50) < 25, str(cnt))
	# 10,000 real opens (with pity) never fall below the disclosed Epic+ odds.
	var ps: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	ps["coins"] = 1 << 40
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	var ep: int = 0
	var gap: int = 0
	var max_gap: int = 0
	for k in 10000:
		var ev: Array = Crates.open(ps, "field", "coins", rng2)
		var got: bool = false
		for r in (ev[0] as Dictionary)["rarities"]:
			if String(r) == "epic" or String(r) == "legendary":
				got = true
		ep += 1 if got else 0
		gap = 0 if got else gap + 1
		max_gap = maxi(max_gap, gap)
	_check("AC-15 Field pity: an Epic+ at least every 20 opens; Epic+ rate >= disclosed", max_gap <= 19 and float(ep) / 10000.0 >= 0.05 and float(ep) / 10000.0 < 0.08, "%d gap %d" % [ep, max_gap])
	# Pity is saved: 19 misses persist across save/load and the 20th is Epic+.
	var pv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	pv["crates"]["pity"]["field"]["epic"] = 19
	var pv2: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(pv)))
	pv2["coins"] = 5000
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 1
	var pev: Array = Crates.open(pv2, "field", "coins", rng3)
	_check("AC-15 pity counter saved; 20th open guarantees Epic+, then resets", int(pv["crates"]["pity"]["field"]["epic"]) == 19 and ["epic", "legendary"].has(String(pev[0]["rarities"][0])) and int(pv2["crates"]["pity"]["field"]["epic"]) == 0 and int(pv2["coins"]) == 2500)
	var lg: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	lg["crates"]["pity"]["vault"]["legendary"] = 14
	lg["keys"] = 4
	var lev: Array = Crates.open(lg, "vault", "keys", rng3)
	_check("CRATE Vault: 4 parts, Legendary pity at 15, paid 4 Keys", (lev[0]["rarities"] as Array).size() == 4 and (lev[0]["rarities"] as Array).has("legendary") and int(lg["keys"]) == 0 and Parts.count(lg) >= 1)
	var sp: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	_check("CRATE refused when unaffordable", Crates.open(sp, "supply", "gems", rng3).is_empty() and Crates.open(sp, "field", "coins", rng3).is_empty() and Crates.open(sp, "field", "token", rng3).is_empty())
	sp["gems"] = 60
	var sev: Array = Crates.open(sp, "supply", "gems", rng3)
	_check("CRATE Supply: 2 parts for 60 gems", (sev[0]["rarities"] as Array).size() == 2 and int(sp["gems"]) == 0 and int(sp["stats"]["crates_opened"]) == 1)
	var vr: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	vr["gems"] = 300 * 50
	var vok: bool = true
	for k in 50:
		var vv: Array = Crates.open(vr, "vault", "gems", rng3)
		var best: int = 0
		for r in vv[0]["rarities"]:
			best = maxi(best, int(Crates.RANK[r]))
		vok = vok and best >= 1
	_check("CRATE Vault always holds a Rare+", vok)
	var tk: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	tk["crates"]["tokens"]["field"] = 1
	_check("CRATE free Field token opens once", Crates.open(tk, "field", "token", rng3).size() >= 2 and Crates.tokens(tk) == 0 and Crates.open(tk, "field", "token", rng3).is_empty())
	var same1: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	var same2: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	same1["gems"] = 600
	same2["gems"] = 600
	var ra := RandomNumberGenerator.new()
	var rb := RandomNumberGenerator.new()
	ra.seed = 5
	rb.seed = 5
	_check("CRATE opens are seeded (same seed -> same parts)", JSON.stringify(Crates.open(same1, "supply", "gems", ra)) == JSON.stringify(Crates.open(same2, "supply", "gems", rb)))


const OT0: int = 1767225600


func _op_save(coins: int = 1000000) -> Dictionary:
	var sv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	sv["coins"] = coins
	sv["gems"] = 1000
	return sv


## Place + finish a building now (skips its build timer). Returns its uid.
func _op_build(sv: Dictionary, id: String, x: int, y: int, rot: int = 0, now: int = OT0) -> String:
	var ev: Array = Outpost.place(sv, id, x, y, rot, now)
	var pe: Array = _evts(ev, "op_placed")
	if pe.is_empty():
		return ""
	var uid: String = String(pe[0]["uid"])
	var q: Array = sv["outpost"]["queue"]
	for j in q:
		(j as Dictionary)["ends_at"] = now
	Outpost.tick(sv, now)
	return uid


## AC-17..19 + storage, timers, plots, decor, blueprints, research hooks.
func _outpost_stages() -> void:
	var sv: Dictionary = _op_save()
	var o: Dictionary = sv["outpost"]
	_check("OP new save: Relay L1 + a connected Research Hall", int(o["relay_lvl"]) == 1 and Outpost.level_of(sv, "research") == 1 and Outpost.research_queues(sv) == 1 and bool(Outpost.connected(o).values()[0]))
	# Placement validation (AC-17).
	_check("AC-17 refuse: occupied (Relay), locked plot, outside, blocked", Outpost.place_error(sv, "mill", 2, 4, 0) == "occupied" and Outpost.place_error(sv, "mill", 7, 3, 0) == "locked" and Outpost.place_error(sv, "mill", 13, 9, 0) != "" and Outpost.place_error(sv, "conduit", -1, 3, 0) == "outside")
	_check("AC-17 Gem Mine only on a Crystal Vein", Outpost.place_error(sv, "gemmine", 4, 2, 0) == "needs_vein" and Outpost.place_error(sv, "gemmine", 0, 6, 0) == "")
	var m1: String = _op_build(sv, "mill", 4, 4)
	_check("OP place Mill: pays 500, builds on a timer", m1 != "" and int(sv["coins"]) == 1000000 - 500 and bool(o["buildings"][m1]["built"]))
	_check("AC-17 quantity limit (Relay 1: 2 Mills, 0 Key Forges)", _op_build(sv, "mill", 4, 6) != "" and Outpost.place_error(sv, "mill", 4, 2, 0) == "limit" and Outpost.place_error(sv, "keyforge", 4, 2, 0) == "limit")
	# Connectivity (AC-17): an island Mill produces 0 until a Conduit links it.
	var cs: Dictionary = _op_save()
	var isl: String = _op_build(cs, "mill", 0, 6)
	var con: Dictionary = Outpost.connected(cs["outpost"])
	_check("AC-17 unconnected generator produces 0", not bool(con[isl]) and is_equal_approx(Outpost.rate(cs, isl), 0.0) and Outpost.nominal_rate(cs, isl) > 0.0)
	_op_build(cs, "conduit", 2, 6)
	_check("AC-17 a Conduit next to the Relay links it (flood fill)", bool(Outpost.connected(cs["outpost"])[isl]) and is_equal_approx(Outpost.rate(cs, isl), 60.0))
	# Power budget scales efficiency (AC-17).
	var ps: Dictionary = _op_save()
	ps["outpost"]["plots"] = [0, 1]
	_op_build(ps, "mill", 4, 4)
	_op_build(ps, "mill", 4, 6)
	_op_build(ps, "refinery", 6, 4)
	_op_build(ps, "barracks", 4, 2)
	_op_build(ps, "archive", 6, 2)
	_op_build(ps, "warehouse", 6, 6)
	var dm: float = Outpost.demand(ps["outpost"])
	_check("AC-17 over-budget power scales generator efficiency", dm > Outpost.supply(ps["outpost"]) and is_equal_approx(Outpost.efficiency(ps["outpost"]), Outpost.supply(ps["outpost"]) / dm))
	# Accrual (AC-18): rate x elapsed, clamped at cap; collect empties.
	var a: Dictionary = _op_save()
	var mu: String = _op_build(a, "mill", 4, 4)
	Outpost.tick(a, OT0 + 3600)
	_check("AC-18 accrual = rate x elapsed (60/h)", absf(float(a["outpost"]["buildings"][mu]["stored"]) - 60.0) < 0.01)
	Outpost.tick(a, OT0 + 3600 * 30)
	_check("AC-18 accrual clamps at the 8 h storage cap", is_equal_approx(float(a["outpost"]["buildings"][mu]["stored"]), 480.0) and is_equal_approx(Outpost.cap(a, mu), 480.0))
	var c0: int = int(a["coins"])
	var cev: Array = Outpost.collect(a, mu, OT0 + 3600 * 30)
	_check("AC-18 collect pays whole coins and empties storage", _evts(cev, "collect").size() == 1 and int(a["coins"]) == c0 + 480 and float(a["outpost"]["buildings"][mu]["stored"]) < 1.0 and int(a["stats"]["outpost_collects"]) == 1)
	var pv: Dictionary = Outpost.pending(a, OT0 + 3600 * 32)
	_check("OP pending previews without mutating", absf(float(pv["coins"]) - 120.0) < 0.01 and float(a["outpost"]["buildings"][mu]["stored"]) < 1.0)
	# First tick of a never-ticked building only stamps the clock (no back pay).
	var nb: Dictionary = _op_save()
	var nu: String = _op_build(nb, "mill", 4, 4)
	nb["outpost"]["buildings"][nu]["last_tick"] = 0
	Outpost.tick(nb, OT0 + 86400)
	_check("OP last_tick 0 = start the clock (no double pay after migration)", is_equal_approx(float(nb["outpost"]["buildings"][nu]["stored"]), 0.0) and int(nb["outpost"]["buildings"][nu]["last_tick"]) == OT0 + 86400)
	# Timers + builders (AC-18).
	var t: Dictionary = _op_save()
	var pe: Array = Outpost.place(t, "mill", 4, 4, 0, OT0)
	var tu: String = String(_evts(pe, "op_placed")[0]["uid"])
	_check("AC-18 one job per builder (2nd build refused)", Outpost.place(t, "mill", 4, 6, 0, OT0).is_empty() and Outpost.busy(t) == 1 and Outpost.builders(t) == 1)
	_check("AC-18 Conduits are instant (no builder)", not Outpost.place(t, "conduit", 2, 6, 0, OT0).is_empty())
	Outpost.tick(t, OT0 + 119)
	_check("AC-18 build not done before ends_at", not bool(t["outpost"]["buildings"][tu]["built"]))
	var dev: Array = Outpost.tick(t, OT0 + 120 + 3600)
	_check("AC-18 build completes at ends_at, produces from then", _evts(dev, "build_done").size() == 1 and bool(t["outpost"]["buildings"][tu]["built"]) and absf(float(t["outpost"]["buildings"][tu]["stored"]) - 60.0) < 0.01)
	var uc: int = Outpost.cost("mill", 1)
	var c1: int = int(t["coins"])
	var uev: Array = Outpost.upgrade(t, tu, OT0 + 3720)
	_check("OP upgrade cost x1.6^(L-1), time x1.4^(L-1)", uev.size() >= 1 and int(t["coins"]) == c1 - uc and Outpost.cost("mill", 3) == int(round(500.0 * 2.56)) and Outpost.build_time(t, "mill", 2) == int(round(120.0 * 1.4)))
	Outpost.tick(t, OT0 + 3720 + 120)
	_check("OP upgrade done: L2 = +25% production", int(t["outpost"]["buildings"][tu]["lvl"]) == 2 and is_equal_approx(Outpost.nominal_rate(t, tu), 75.0))
	_check("OP max level = min(10, Relay L + 2)", Outpost.max_lvl(t, "mill") == 3)
	var sk: Dictionary = _op_save()
	Outpost.place(sk, "research", 0, 6, 0, OT0)
	Outpost.place(sk, "barracks", 4, 2, 0, OT0)
	_check("OP skip cost = 1 gem per 3 min (rounded up)", Outpost.skip_cost(sk, 0, OT0) == 10 and Outpost.skip_cost(sk, 0, OT0 + 1500) == 2)
	var g0: int = int(sk["gems"])
	Outpost.skip(sk, 0, OT0)
	_check("OP skip finishes the job for gems", int(sk["gems"]) == g0 - 10 and Outpost.level_of(sk, "barracks") == 1)
	# Adjacency + cap (AC-19).
	var j: Dictionary = _op_save()
	j["outpost"]["plots"] = [0, 1]
	j["outpost"]["relay_lvl"] = 8
	var ma: String = _op_build(j, "mill", 4, 4)
	var mb: String = _op_build(j, "mill", 4, 6)
	var lb: Dictionary = Outpost.layout_bonus(j["outpost"], ma)
	_check("AC-19 +10% per adjacent Mill", is_equal_approx(float(lb["total"]), 0.10) and is_equal_approx(float(lb["parts"]["mills"]), 0.10))
	_op_build(j, "mill", 6, 4)
	_op_build(j, "mill", 6, 2)
	_op_build(j, "warehouse", 4, 2)
	_op_build(j, "beaconpost", 3, 6)
	var lb2: Dictionary = Outpost.layout_bonus(j["outpost"], ma)
	_check("AC-19 Mill adj max +30%, +15% Warehouse, +5% Beacon", is_equal_approx(float(lb2["parts"]["mills"]), 0.20) and is_equal_approx(float(lb2["parts"]["warehouse"]), 0.15) and is_equal_approx(float(lb2["parts"]["beacon"]), 0.05))
	_check("AC-19 Warehouse +25% storage within radius 2", is_equal_approx(Outpost.warehouse_bonus(j["outpost"], ma), 0.25))
	var r: Dictionary = _op_save()
	r["outpost"]["plots"] = [0, 1]
	r["outpost"]["relay_lvl"] = 8
	var rf: String = _op_build(r, "refinery", 4, 4)
	_op_build(r, "mill", 4, 6)
	_check("AC-19 Refinery -10% next to a Mill (noise)", is_equal_approx(float(Outpost.layout_bonus(r["outpost"], rf)["total"]), -0.10))
	Outpost.place_decor(r, "dc_smelter", 4, 3, 0)
	_check("AC-19 Refinery +20% next to a Smelter", is_equal_approx(float(Outpost.layout_bonus(r["outpost"], rf)["total"]), 0.10))
	var cap: Dictionary = _op_save()
	cap["outpost"]["plots"] = [0, 1, 2, 4]
	cap["outpost"]["relay_lvl"] = 8
	var mc: String = _op_build(cap, "mill", 6, 2)
	_op_build(cap, "mill", 8, 2)
	_op_build(cap, "mill", 6, 4)
	_op_build(cap, "mill", 6, 0)
	_op_build(cap, "warehouse", 4, 2)
	_op_build(cap, "beaconpost", 8, 4)
	_op_build(cap, "conduit", 4, 4)
	_op_build(cap, "conduit", 5, 4)
	var tb: float = 0.0
	for k in (Outpost.layout_bonus(cap["outpost"], mc)["parts"] as Dictionary).values():
		tb += float(k)
	# The best Mill layout (3 Mills + Warehouse + Beacon) sums to +50%; the
	# +60% cap bounds every stack (decor stacks are capped at +20% before it).
	_check("AC-19 layout total = min(+60%, adjacency + Warehouse + Beacon)", is_equal_approx(tb, 0.50) and is_equal_approx(float(Outpost.layout_bonus(cap["outpost"], mc)["total"]), minf(0.60, tb)), "%.2f" % tb)
	var gl: Dictionary = _op_save()
	var gmu: String = _op_build(gl, "gemmine", 0, 6)
	for lp in [Vector2i(2, 6), Vector2i(2, 7), Vector2i(0, 5), Vector2i(1, 5)]:
		Outpost.place_decor(gl, "dc_lamp", lp.x, lp.y, 0)
	_check("AC-19 decor stack capped at +20% (4 lit Lamps on a Gem Mine)", is_equal_approx(float(Outpost.layout_bonus(gl["outpost"], gmu)["total"]), 0.20))
	# Gem Mine: rate band, hard cap 24, daily cap 25.
	var gm: Dictionary = _op_save()
	var gu: String = _op_build(gm, "gemmine", 0, 6)
	_op_build(gm, "conduit", 2, 6)
	_check("OP Gem Mine 1 gem / 3 h at L1", is_equal_approx(Outpost.rate(gm, gu), 1.0 / 3.0))
	Outpost.tick(gm, OT0 + 86400 * 30)
	_check("OP Gem Mine hard cap 24 stored", is_equal_approx(float(gm["outpost"]["buildings"][gu]["stored"]), 24.0))
	var gg: int = int(gm["gems"])
	Outpost.collect(gm, gu, OT0 + 86400 * 30)
	gm["outpost"]["buildings"][gu]["stored"] = 24.0
	Outpost.collect(gm, gu, OT0 + 86400 * 30)
	_check("OP Gem Mine daily cap 25 (gem_log mine)", int(gm["gems"]) == gg + 25 and int(gm["gem_log"]["mine"]) == 25 and is_equal_approx(float(gm["outpost"]["buildings"][gu]["stored"]), 23.0))
	# Plots: cost, adjacency, gems-or-coins x3.
	var p: Dictionary = _op_save(10000000)
	_check("OP plot 0 costs 5,000; a non-adjacent plot is refused", int(Outpost.plot_cost(p)["coins"]) == 5000 and Outpost.unlock_plot(p, 5).is_empty())
	Outpost.unlock_plot(p, 0)
	_check("OP plot k = 5,000 x 2.2^k; plot 5 adjacent after plot 0", int(Outpost.plot_cost(p)["coins"]) == 11000 and not Outpost.unlock_plot(p, 5).is_empty())
	Outpost.unlock_plot(p, 1)
	Outpost.unlock_plot(p, 2)
	var pc4: Dictionary = Outpost.plot_cost(p)
	var gp: int = int(p["gems"])
	var cp4: int = int(p["coins"])
	Outpost.unlock_plot(p, 3, "coins")
	_check("OP 5th plot: coins x3 instead of 80 gems (gems never gate)", int(pc4["gems"]) == 80 and int(p["coins"]) == cp4 - int(pc4["coins"]) * 3 and int(p["gems"]) == gp)
	# Decor + Charm.
	var d: Dictionary = _op_save()
	d["outpost"]["plots"] = [0, 1, 2, 3, 4, 5, 6, 7]
	var n: int = 0
	for y in range(0, 10):
		for x in range(6, 14):
			if n < 20 and not Outpost.place_decor(d, "dc_tree", x, y, 0).is_empty():
				n += 1
	_check("OP Charm +1% per 10 decor (max +10%)", n == 20 and is_equal_approx(Outpost.charm(d["outpost"]), 0.02))
	var dk: String = String(d["outpost"]["decor"].keys()[0])
	var c2: int = int(d["coins"])
	Outpost.remove_decor(d, dk)
	_check("OP remove decor refunds 50%", int(d["coins"]) == c2 + 25)
	# Move / rotate / demolish.
	var mv: Dictionary = _op_save()
	var ku: String = _op_build(mv, "mill", 4, 4)
	_check("OP move is free + validated", not Outpost.move(mv, ku, 4, 6, 0, OT0).is_empty() and int(mv["outpost"]["buildings"][ku]["y"]) == 6 and Outpost.move(mv, ku, 2, 4, 0, OT0).is_empty())
	var ws: String = _op_build(mv, "scrapyard", 0, 6)
	_check("OP rotate (R) swaps the footprint", not Outpost.move(mv, ws, 0, 6, 1, OT0).is_empty() and Outpost.footprint("scrapyard", 0, 6, 1).size() == 2 and (Outpost.footprint("scrapyard", 0, 6, 1)[1] as Vector2i) == Vector2i(0, 7))
	var c3: int = int(mv["coins"])
	Outpost.demolish(mv, ku, OT0)
	_check("OP demolish after build refunds 50%", int(mv["coins"]) == c3 + 250)
	var qd: Dictionary = _op_save()
	var qe: Array = Outpost.place(qd, "barracks", 4, 2, 0, OT0)
	var c4: int = int(qd["coins"])
	Outpost.demolish(qd, String(_evts(qe, "op_placed")[0]["uid"]), OT0)
	_check("OP demolish while queued refunds 100% and frees the builder", int(qd["coins"]) == c4 + 3000 and Outpost.busy(qd) == 0)
	# Blueprints: save / export / import / one-click rebuild.
	var bp: Dictionary = _op_save()
	var bu: String = _op_build(bp, "mill", 4, 4)
	Outpost.save_blueprint(bp, "Mint Ring")
	var code: String = Outpost.export_layout(bp["outpost"])
	Outpost.move(bp, bu, 4, 6, 0, OT0)
	var lr: Dictionary = Outpost.load_blueprint(bp, Outpost.import_layout(code), OT0)
	_check("OP blueprint export/import + rebuild moves owned buildings back", int(bp["outpost"]["buildings"][bu]["y"]) == 4 and (lr["missing"] as Array).is_empty() and (bp["outpost"]["blueprints"] as Array).size() == 1)
	var miss: Dictionary = Outpost.load_blueprint(bp, [{"id": "archive", "x": 4, "y": 2, "rot": 0}], OT0)
	_check("OP blueprint reports buildings you do not own", (miss["missing"] as Array) == ["archive"])
	for k in 6:
		Outpost.save_blueprint(bp, "L%d" % k)
	_check("OP 5 blueprint slots max", (bp["outpost"]["blueprints"] as Array).size() == 5)
	# Run hooks: Barracks tier, Archive Insight cap / banish.
	var rh: Dictionary = _op_save()
	var bk: String = _op_build(rh, "barracks", 4, 2)
	var ar: String = _op_build(rh, "archive", 4, 4)
	rh["outpost"]["buildings"][bk]["lvl"] = 4
	rh["outpost"]["buildings"][ar]["lvl"] = 9
	var rm: Dictionary = BaseMeta.run_mods(rh)
	_check("OP run hooks: Barracks tier = level, Archive L9 cap +2 / +1 banish", int(rm["barracks_tier"]) == 4 and int(rm["insight_cap"]) == 2 and int(rm["banish"]) == 1)
	var Sx = TowerState.new()
	Sx.setup(5, rh)
	_check("OP Archive feeds the run (banish 2)", Sx.banish_left == 2)
	# Normalize: overlapping / out-of-land buildings are lifted, JSON round-trip.
	var nz: Dictionary = _op_save()
	_op_build(nz, "mill", 4, 4)
	nz["outpost"]["buildings"]["99"] = {"id": "mill", "x": 4, "y": 4, "rot": 0, "lvl": 1}
	nz["outpost"]["buildings"]["98"] = {"id": "bogus", "x": 0, "y": 0}
	var nn: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(nz)))
	_check("OP normalize: unknown dropped, overlap lifted to unplaced", not (nn["outpost"]["buildings"] as Dictionary).has("98") and int(nn["outpost"]["buildings"]["99"]["x"]) == -1 and int(nn["outpost"]["next_uid"]) >= 100)
	_check("OP art bands L1-3 / L4-7 / L8-10", OutpostDB.art_id("mill", 3) == "op_mill_1" and OutpostDB.art_id("mill", 4) == "op_mill_2" and OutpostDB.art_id("beaconpost", 9) == "op_beacon_3")
	var arts: bool = true
	for id in OutpostDB.IDS + ["relay"]:
		for L in [1, 5, 9]:
			arts = arts and FileAccess.file_exists("res://art/" + OutpostDB.art_id(String(id), int(L)) + ".svg")
	for id in OutpostDB.DECOR.keys():
		arts = arts and FileAccess.file_exists("res://art/" + String(id) + ".svg")
	_check("OP every building band + decor has an SVG", arts)
