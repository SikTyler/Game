extends SceneTree
## Corehold rules self-test. Drives TowerState / BaseMeta / Draft directly with
## fixed seeds and asserts what a human would check. Prints "SELFTEST OK" (exit
## 0) or "SELFTEST FAIL: <reason>" (exit 1).
## Run: godot --headless --path games/towerdef-pc-0001/ --script res://selftest.gd

const StKit := preload("res://tests/st_kit.gd")
const TowerState := preload("res://TowerState.gd")
const MissionDB := preload("res://data/MissionDB.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Draft := preload("res://Draft.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const Tiers := preload("res://Tiers.gd")
const Labs := preload("res://Labs.gd")
const LabDB := preload("res://data/LabDB.gd")
const Missions := preload("res://Missions.gd")
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
const Outpost := preload("res://Outpost.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const Reforge := preload("res://Reforge.gd")
const ReforgeDB := preload("res://data/ReforgeDB.gd")

var fails: Array = []


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails.append(name)
		print("SELFTEST FAIL: " + name + ("" if detail == "" else "  [" + detail + "]"))


## Legacy 5x5 index (Core at (2,2)) -> V2 P3b board (21x21, 26 px cells,
## 3x3 Core): an offset d becomes d + sign(d), so a legacy cell keeps its ring
## (ring 1 touches the Core). Cells that were neighbours across a ring may
## now have a gap between them (tests that need adjacency use _at()).
func _r(i5: int) -> int:
	return _lg(i5 / 5 - 2, i5 % 5 - 2)


func _lg(dr: int, dc: int) -> int:
	return TowerState.cell(dr + signi(dr) * TowerState.CORE_HALF, dc + signi(dc) * TowerState.CORE_HALF)


## Raw cell (dr, dc) from the Core's centre cell (+-2 touches the Core).
func _at(dr: int, dc: int) -> int:
	return TowerState.cell(dr, dc)


func _fresh(save: Dictionary = {}) -> RefCounted:
	var S = TowerState.new()
	S.setup(1234, BaseMeta.normalize(save))
	return S


func _initialize() -> void:
	# --- Stage 1: setup ------------------------------------------------------
	var S = _fresh()
	# REDESIGN: the Core's HP comes from its CoreDB sheet (Bastion L1 = 120).
	_check("setup: full hp (Bastion sheet)", is_equal_approx(S.hp, 120.0) and S.core_id == "core" and S.core_lvl == 1)
	# V2 P3b (deliberate): the start grid is 7x7 small cells (rings 1-2 around
	# the 3x3 Core); the 9 Core cells are never free.
	_check("setup: rings 1-2 unlocked, outside the 7x7 grid locked, the Core locked", bool(S.unlocked[_r(6)]) and bool(S.unlocked[_r(0)]) and not bool(S.unlocked[_at(-4, -4)]) and not bool(S.unlocked[_r(12)]) and not bool(S.unlocked[_at(1, 1)]))
	_check("setup: 40 free cells (7x7 minus the 3x3 Core)", S.free_slots().size() == 40)
	_check("setup: core is the only weapon", (S.stats["weapons"] as Array).size() == 1)

	# --- Stage 2: stats math + adjacency -------------------------------------
	# REDESIGN (deliberate): building numbers follow REDESIGN_SYSTEMS §2.3
	# (L1 sheet, +35% main stat per level); Armory is +15% to neighbours.
	S.slots[_r(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	var gun_dmg: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	_check("gatling L1 6 dmg x building scale (Steadfast-free)", is_equal_approx(gun_dmg, 6.0 * TowerState.bld_dmg()))
	S.slots[_at(-2, -1)] = {"id": "armory", "perm": 0, "run": 1}   # touches the gun and the Core
	S.recompute()
	var buffed: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	_check("armory buffs adjacent gun +15%", is_equal_approx(buffed, gun_dmg * 1.15) and _has_link(S, _at(-2, -1), _r(7), "ARM") and _has_link(S, _at(-2, -1), TowerState.CORE_SLOT, "ARM"))
	S.slots[_r(0)] = {"id": "armory", "perm": 0, "run": 1}   # NOT adjacent to 7
	S.recompute()
	_check("armory does not buff non-adjacent", is_equal_approx(float((S.stats["weapons"] as Array)[0]["dmg"]), buffed))
	S = _fresh()
	S.slots[_r(16)] = {"id": "mine", "perm": 0, "run": 2}
	S.slots[_r(18)] = {"id": "bulwark", "perm": 0, "run": 1}
	S.recompute()
	_check("mine L2 cash/s = Core 2.0 + 0.8x1.35 (V2: no Steadfast trait)", is_equal_approx(float(S.stats["cash_ps"]), 2.0 + 0.8 * 1.35))
	_check("bulwark raises max hp +40", is_equal_approx(float(S.stats["max_hp"]), 160.0))
	_check("bulwark heals by its bonus", is_equal_approx(S.hp, 160.0))

	# --- Stage 3: combat — core kills an enemy, rewards land ------------------
	S = _fresh()
	S.add_enemy({"kind": "drone", "pos": TowerState.CENTER + Vector2(200, 0), "hp": 4.0, "max_hp": 4.0, "spd": 0.0, "dmg": 4.0, "cash": 1.0, "xp": 1.0, "coin": 0.2, "size": 16.0, "atk_cd": 0.0, "slow_t": 0.0})
	S.spawn_hold = true
	var ev: Array = S.tick(0.05)
	var kinds: Array = ev.map(func(e): return e["t"])
	_check("core fires a shot", kinds.has("shot"))
	# V2 P3d: per-body kill events aggregate into one "kills" summary per substep
	_check("kills summary + cash + xp", kinds.has("kills") and S.cash >= 1.0 and S.xp >= 1.0 and S.kills == 1)

	# --- Stage 4: enemy reaches the core and damages it ----------------------
	S = _fresh()
	S.spawn_hold = true
	S.stats["weapons"] = []   # disarm to isolate
	# FEEDBACK-1: melee contact is at STOP_R from the Core centre (enemies now
	# walk through the grid; buildings in the way are attacked first).
	S.add_enemy({"kind": "hauler", "pos": TowerState.CENTER + Vector2(TowerState.STOP_R + 1.0, 0), "hp": 999.0, "max_hp": 999.0, "spd": 28.0, "dmg": 10.0, "cash": 3.0, "xp": 3.0, "coin": 0.6, "size": 26.0, "atk_cd": 0.0, "slow_t": 0.0})
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
	ev = S.tick(0.05)
	_check("XP level-up banks a reroll, opens no draft", S.level == 2 and S.draft.is_empty() and S.rerolls_left == 1 and _evts(ev, "levelup").size() == 1)
	S.wave_t = S.wave_time - 0.001
	ev = S.tick(0.05)
	_check("wave 1 cleared opens a 3-card draft", S.wave == 2 and S.draft.size() == 3 and _evts(ev, "draft_offer").size() == 1)
	var eco_n: int = 0
	for c in S.draft:
		if (c["tags"] as Array).has("eco"):
			eco_n += 1
	_check("G1 draft offers eco AND non-eco", eco_n >= 1 and eco_n <= 2)
	_check("FB1 the sim stays live during a draft (no slow-mo)", is_equal_approx(S.time_scale(), 1.0))
	S.draft = [Draft.card_for("mortar", S._draft_ctx("")), Draft.card_for("mine", S._draft_ctx("")), Draft.card_for("pk_arsenal", S._draft_ctx(""))]
	var card: Dictionary = S.draft[0]
	S.choose_card(0)
	_check("new card enters place mode", S.pending_place == String(card["id"]) and S.draft.is_empty())
	S.place(_at(-5, -5))  # locked — rejected
	_check("cannot place on locked slot", S.pending_place != "")
	S.place(_at(-2, -2))  # V2 P3b: the 2x2 Mortar would cover a Core cell — rejected
	_check("cannot place a 2x2 over the Core", S.pending_place != "")
	ev = S.place(_at(-3, -3))
	_check("placed building in free slot (2x2 footprint)", S.id_at(_at(-3, -3)) == "mortar" and S.pending_place == "" and S.owner_at(_at(-2, -2)) == _at(-3, -3) and is_equal_approx(S.time_scale(), 1.0))
	S.grant_draft()
	# FEEDBACK-1 (deliberate): a duplicate WEAPON is a new individual building;
	# a duplicate non-weapon is an upgrade applied onto the existing building.
	var dup: Dictionary = Draft.card_for("mortar", S._draft_ctx(""))
	_check("FB1 duplicate weapon = new individual building", String(dup["kind"]) == "new" and bool(dup["dup"]) and String(dup["reward"]) == "building")
	S.slots[_r(8)] = {"id": "mine", "perm": 0, "run": 1}
	S.recompute()
	var plus: Dictionary = Draft.card_for("mine", S._draft_ctx(""))
	_check("owned non-weapon offers only a plus card (Lv1 -> 2)", String(plus["kind"]) == "plus" and int(plus["lvl"]) == 1 and int(plus["to"]) == 2 and String(plus["reward"]) == "upgrade")
	S.draft = [plus]
	ev = S.choose_card(0)
	_check("FB1 an upgrade waits to be applied onto its building", S.lvl_at(_r(8)) == 1 and S.pending_upgrade == "mine" and _evts(ev, "upgrade_mode").size() == 1 and (_evts(ev, "upgrade_mode")[0]["slots"] as Array) == [_r(8)])
	_check("FB1 apply_upgrade refuses another building", S.apply_upgrade(_r(6)).is_empty() and S.pending_upgrade == "mine")
	ev = S.apply_upgrade(_r(8))
	_check("plus card raises owned level (applied by click)", S.lvl_at(_r(8)) == 2 and S.pending_upgrade == "" and _evts(ev, "building_level").size() == 1)
	# Every card names its reward type; perks land in the Perks list.
	var typed: bool = true
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	for k in 40:
		for c in Draft.roll_hand(rr, S._draft_ctx("")):
			typed = typed and ["building", "upgrade", "perk", "ability"].has(String((c as Dictionary).get("reward", "")))
	_check("FB1 every draft card carries its reward type", typed)
	S.draft = [Draft.card_for("pk_arsenal", S._draft_ctx(""))]
	ev = S.choose_card(0)
	S.perks_taken.append("p_dmg")
	var pl: Array = S.perk_list()
	_check("FB1 perk picks apply instantly and list under Perks (packs + gold perks)", int(S.packs.get("pk_arsenal", 0)) == 1 and String(_evts(ev, "pick_applied")[0]["reward"]) == "perk" and pl.any(func(p: Variant) -> bool: return String((p as Dictionary)["id"]) == "pk_arsenal" and String((p as Dictionary)["kind"]) == "pack") and pl.any(func(p: Variant) -> bool: return String((p as Dictionary)["kind"]) == "gold"))
	# V2 P3a (deliberate): structures have no HP, so nothing destroys an
	# upgrade's target mid-run (the FB1 cancel-on-destroy check is retired).
	_check("V2 P3a: structures have no HP and no destroy path", not ("bld_hp" in S) and not S.has_method("_destroy_building") and not S.has_method("_repair_buildings"))
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
	S.slots[_r(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	S.cash = 5.0
	_check("track refused when broke", S.buy_track("dmg").is_empty() and S.core_run_lvl == 0)
	S.cash = 1000.0
	_check("cash cannot level a building", S.upgrade(_r(7)).is_empty() and S.lvl_at(_r(7)) == 1)
	S.upgrade(_r(12))
	_check("Core cell upgrade = Damage track", S.core_run_lvl == 1 and int(S.tracks["dmg"]) == 1 and S.cash < 1000.0)
	_check("no per-cell run unlocks", S.unlock_plot(_at(-4, -4)).is_empty() and not bool(S.unlocked[_at(-4, -4)]))

	# --- Stage 8: death banks coins into permanent save ----------------------
	var save: Dictionary = BaseMeta.default_save()
	S = TowerState.new()
	S.setup(5, save)
	S.coins_run = 42.7
	S.hp = -1.0
	S.spawn_hold = true
	S.stats["regen"] = 0.0
	ev = S.tick(0.05)
	_check("death event + over", S.over and String(ev.back()["t"]) == "dead")
	_check("coins banked to save", int(save["coins"]) == 42 and int(save["runs"]) == 1 and int(save["best_wave"]) == 1)

	# --- Stage 9: the permanent Core level carries into the next run ---------
	# V2 (deliberate): the v3 permanent base (cells, perm buildings, Core stat
	# levels) is gone; the Core's permanent level is the meta Core power.
	save["coins"] = 100000
	var lv0: int = Cores.level(save)
	_check("Core level up spends coins", not Cores.try_level(save).is_empty() and Cores.level(save) == lv0 + 1 and int(save["coins"]) == 100000 - int(Cores.level_cost(lv0)["coins"]))
	S = TowerState.new()
	S.setup(6, save)
	_check("run grid starts empty", S.building_count() == 0 and not bool(S.unlocked[_at(-4, -4)]))
	_check("Core level applies to the run (HP x1.05/level)", is_equal_approx(S.hp, 120.0 * 1.05) and S.core_lvl == lv0 + 1)

	# --- Stage 10: persistence round-trip ------------------------------------
	MetaSave.clear()
	MetaSave.write(save)
	var back: Dictionary = BaseMeta.normalize(MetaSave.read())
	_check("save round-trips", int(back["coins"]) == int(save["coins"]) and Cores.level(back) == Cores.level(save) and int(back["version"]) == 5)
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
	_horde_stages()
	StKit.run(self)

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
	# --- Stage 12: save v5 (V2 hard reset) -----------------------------------
	# V2 (owner decision, deliberate): pre-v5 saves are NOT migrated — they
	# normalize to fresh v5 defaults with reset_v2 (one-time banner); audio
	# settings survive.
	var v1: Dictionary = {"coins": 123, "core": {"dmg": 1, "hp": 2, "regen": 0}, "slots": {"7": {"id": "gun", "lvl": 3}}, "unlocked": [0, 4], "best_wave": 37, "runs": 5, "labs": {"lvls": {"armor": 4, "coin": 2}}, "settings": {"music": 0.3, "sfx": 0.6, "mute": true}}
	var v4: Dictionary = {"version": 4, "coins": 9999, "scrap": 50, "keys": 3, "core_cores": 4, "cores": {"active": "lance", "owned": ["bastion", "lance"]}, "parts": {"items": {"1": {}}}, "best_wave": 61}
	var m: Dictionary = BaseMeta.normalize(v1)
	var m4: Dictionary = BaseMeta.normalize(v4)
	_check("V2 pre-v5 saves reset to fresh v5 defaults (+ reset_v2)", int(m["version"]) == 5 and int(m["coins"]) == 0 and int(m["runs"]) == 0 and int(m["best_wave"]) == 0 and bool(m.get("reset_v2", false)) and int(m4["coins"]) == 0 and int(m4["scrap"]) == 0 and bool(m4.get("reset_v2", false)))
	_check("V2 reset keeps audio settings", absf(float(m["settings"]["music"]) - 0.3) < 0.001 and bool(m["settings"]["mute"]))
	_check("V2 removed blocks are gone (cards, crates, parts, cores, keys, core_cores, factory, legacy base)", not m4.has("keys") and not m4.has("core_cores") and not m4.has("cards") and not m4.has("crates") and not m4.has("parts") and not m4.has("cores") and not m4.has("factory") and not m4.has("slots") and not m4.has("unlocked") and not m4.has("gems"))
	_check("V2 an empty dict is a new game (no reset banner)", not BaseMeta.normalize({}).has("reset_v2") and int(BaseMeta.normalize({})["version"]) == 5)
	var v2: Dictionary = BaseMeta.normalize({})
	v2["last_seen"] = NOW
	v2["best_coin_rate"] = 12.5
	v2["coins"] = 777
	v2["scrap"] = 31
	v2["shards"] = 4
	v2["core"]["lvl"] = 7
	v2["research"]["lvls"]["coin"] = 2
	v2 = BaseMeta.normalize(v2)
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(v2)))
	_check("AC-2 v5 round-trips through JSON", JSON.stringify(rt) == JSON.stringify(v2) and int(rt["core"]["lvl"]) == 7 and int(rt["scrap"]) == 31 and int(rt["shards"]) == 4)
	var bad: Dictionary = BaseMeta.normalize(v2)
	bad["research"]["lvls"]["dmg"] = 99
	bad["research"]["lvls"]["bogus"] = 3
	bad["core"]["lvl"] = 999
	bad["coins"] = -5
	bad = BaseMeta.normalize(bad)
	_check("AC-3 lab lvl clamped + unknown lab dropped", int(bad["research"]["lvls"]["dmg"]) == 30 and not (bad["research"]["lvls"] as Dictionary).has("bogus"))
	_check("AC-3 Core level clamped, negative coins floored", Cores.level(bad) == Cores.max_level(bad) and int(bad["coins"]) == 0)
	_check("AC-4 first boot pays no offline (Outpost away report)", int(Outpost.away_report(BaseMeta.normalize({}), NOW)["coins"]) == 0)
	# bank
	var b: Dictionary = BaseMeta.default_save()
	var bev: Array = BaseMeta.bank(b, 100, 25, 1, 10.0, NOW)   # meta-economy: w25 (T2 opens at w30)
	_check("bank records tier best, rate, last_seen, coins (no gems)", int(b["best_wave_by_tier"]["1"]) == 25 and is_equal_approx(float(b["best_coin_rate"]), 10.0) and int(b["last_seen"]) == NOW and int(b["coins"]) == 100 and not b.has("gems") and bev.is_empty())
	b["coins"] = 1_000_000

	# --- Stage 13: tiers (AC-5..7) ------------------------------------------
	_check("unlock waves 30/40/50 (meta-economy: was 40/50/60)", Tiers.unlock_wave(2) == 30 and Tiers.unlock_wave(3) == 40 and Tiers.unlock_wave(4) == 50)
	_check("T1 only at start", Tiers.highest(b) == 1 and Tiers.is_unlocked(b, 1) and not Tiers.is_unlocked(b, 2))
	bev = BaseMeta.bank(b, 10, 29, 1, 1.0, NOW)
	_check("w29 in T1 does not unlock T2", Tiers.highest(b) == 1 and bev.is_empty())
	var g0: int = int(b["coins"])
	bev = BaseMeta.bank(b, 10, 30, 1, 1.0, NOW)
	_check("AC-5 w30 in T1 unlocks T2 with +500 coins (FB1: was 10 gems)", Tiers.highest(b) == 2 and _evts(bev, "tier_unlocked").size() == 1 and int(b["coins"]) == g0 + 10 + 500)
	bev = BaseMeta.bank(b, 10, 35, 1, 1.0, NOW)
	_check("AC-5 tier unlock rewarded once", bev.is_empty() and int(b["coins"]) == g0 + 10 + 500 + 10)
	bev = BaseMeta.bank(b, 10, 39, 2, 1.0, NOW)
	_check("w39 in T2 does not unlock T3", Tiers.highest(b) == 2)
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
	# REDESIGN (ENGINE-META, deliberate): queues follow the Research Hall level
	# (was 2 base slots + gem-bought slots 3/4). Hall L4 = the old 2 queues.
	_hall(L, 4)
	L["coins"] = 50
	_check("lab cost table", Labs.cost("dmg", 0) == 80 and Labs.cost("dmg", 1) == 144 and Labs.cost("coin", 0) == 60)
	# FEEDBACK-1 (deliberate): research is INSTANT — no timers, no rush, no gems.
	_check("FB1 lab duration is 0 (instant)", Labs.duration(L, "dmg", 0) == 0 and Labs.duration(L, "speed", 1) == 0)
	var snap: String = JSON.stringify(L)
	_check("AC-11 start fails when broke, no mutation", Labs.start(L, "dmg", NOW).is_empty() and JSON.stringify(L) == snap)
	L["coins"] = 10000
	var lev: Array = Labs.start(L, "dmg", NOW)
	_check("FB1 start deducts cost and completes at once", _evts(lev, "lab_started").size() == 1 and _evts(lev, "lab_done").size() == 1 and int(L["coins"]) == 10000 - 80 and Labs.level(L, "dmg") == 1 and Labs.running(L).is_empty())
	_check("FB1 the same track can be bought again right away", not Labs.start(L, "dmg", NOW).is_empty() and Labs.level(L, "dmg") == 2)
	Labs.start(L, "coin", NOW)
	_check("FB1 no queue limit with a Hall (instant)", not Labs.start(L, "xp", NOW).is_empty() and Labs.level(L, "coin") == 1 and Labs.level(L, "xp") == 1)
	# Old saves: a project left in `running` completes on the next claim.
	(Labs.running(L) as Array).append({"track": "speed", "to_lvl": 1, "start": NOW, "end": NOW + 99999})
	lev = Labs.claim(L, NOW)
	_check("FB1 legacy queued research completes on claim", _evts(lev, "lab_done").size() == 1 and Labs.level(L, "speed") == 1 and Labs.running(L).is_empty())
	_check("FB1 no rush / gem API left", not Labs.new().has_method("rush") and not Labs.new().has_method("rush_cost") and not BaseMeta.default_save().has("gems"))
	_check("A4 speed steps follow speed lab", Labs.speed_steps(L) == [1.0, 1.5] and Labs.speed_steps(BaseMeta.default_save()) == [1.0])
	var hq: Dictionary = BaseMeta.default_save()
	var qok: Array = []
	for hl in [1, 3, 4, 7, 8, 10]:
		_hall(hq, int(hl))
		qok.append(Labs.slots(hq))
	var nohall: Dictionary = BaseMeta.default_save()
	nohall["outpost"]["buildings"] = {}
	_check("AC-20 queues 1/2/3 at Hall L1/L4/L8, 0 without a Hall", qok == [1, 1, 2, 2, 3, 3] and Labs.slots(nohall) == 0 and Labs.start(nohall, "dmg", NOW).is_empty())
	# V2 (deliberate): Part Analysis / Crate Theory are gone with parts and crates -> 10.
	_check("AC-20 every LabDB project + Grid (no part / crate research)", LabDB.IDS.size() == 10 and LabDB.DEFS.has("grid") and not LabDB.DEFS.has("labspeed") and not LabDB.DEFS.has("part_analysis") and not LabDB.DEFS.has("crate_theory") and String(LabDB.DEFS["offcap"]["name"]) == "Storage Tech" and String(LabDB.DEFS["offrate"]["name"]) == "Logistics Tech")
	# V2 P3b/P8 (deliberate): 26 px cells, grid 7x7 -> 21x21 in 7 steep steps.
	_check("V2 grid research 7..21 in 7 steps, costs 2k/10k/50k/200k/750k/2.5M/8M", LabDB.max_of("grid") == 7 and Labs.cost("grid", 0) == 2000 and Labs.cost("grid", 3) == 200000 and Labs.cost("grid", 6) == 8000000 and TowerState.grid_for_level(0) == 7 and TowerState.grid_for_level(1) == 9 and TowerState.grid_for_level(4) == 15 and TowerState.grid_for_level(7) == 21)
	L["research"]["lvls"]["dmg"] = 30
	_check("maxed track cannot start", Labs.start(L, "dmg", NOW).is_empty())
	var lm: Dictionary = Labs.modifiers(L)
	_check("lab modifiers: +5%/lvl dmg", is_equal_approx(float(lm["dmg"]), 1.5) and is_equal_approx(float(lm["coin"]), 0.05))

	# --- Stage 15: offline = Outpost accrual (REDESIGN, deliberate) ---------
	# Offline.gd is gone: the away pay is what the Outpost stored, capped by
	# each building's storage; Storage/Logistics Tech replace offcap/offrate.
	var O: Dictionary = BaseMeta.default_save()
	O["coins"] = 1000
	var om: String = _op_build(O, "mill", 4, 4, 0, NOW)
	_check("AC-17 last_seen 0 pays 0", int(Outpost.away_report(O, NOW + 3600)["coins"]) == 0)
	O["last_seen"] = NOW
	_check("AC-17 under 5 min pays 0", int(Outpost.away_report(O, NOW + 299)["coins"]) == 0)
	_check("away 1 h = Mill output (60/h)", absf(float(Outpost.away_report(O, NOW + 3600)["coins"]) - OutpostDB.MILL_RATE) < 0.01 and int(Outpost.away_report(O, NOW + 3600)["minutes"]) == 60)
	_check("AC-17 capped at 8 h of storage", absf(float(Outpost.away_report(O, NOW + 86400)["coins"]) - 8.0 * OutpostDB.MILL_RATE) < 0.01)
	O["research"]["lvls"]["offcap"] = 4
	O["research"]["lvls"]["offrate"] = 2
	_check("Storage Tech +4%/L, Logistics Tech +5%/L", absf(Outpost.cap(O, om) - OutpostDB.MILL_RATE * 1.10 * 8.0 * 1.16) < 0.01 and absf(Outpost.rate(O, om) - 1.1 * OutpostDB.MILL_RATE) < 0.01)
	O["research"]["lvls"]["offcap"] = 0
	O["research"]["lvls"]["offrate"] = 0
	var c18: int = int(O["coins"])
	var oev: Array = Outpost.claim_away(O, NOW + 600)
	_check("away claim pays + stamps last_seen", int(O["coins"]) == c18 + int(OutpostDB.MILL_RATE / 6.0) and int(O["last_seen"]) == NOW + 600 and _evts(oev, "offline").size() == 1)

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
	# FEEDBACK-1 (deliberate): mission rewards are coins (gems x40).
	M["missions"]["list"] = [{"tpl": "kill", "target": 3, "prog": 0, "claimed": false, "coins": 120}, {"tpl": "wave", "target": 10, "prog": 0, "claimed": false, "coins": 160}, {"tpl": "perk", "target": 2, "prog": 0, "claimed": false, "coins": 80}]
	var gm: int = int(M["coins"])
	_check("AC-29 cannot claim unfinished", Missions.claim(M, 0).is_empty())
	mev = Missions.on_run_events(M, [{"t": "kill"}, {"t": "kill"}, {"t": "kill"}, {"t": "kill"}, {"t": "wave", "wave": 12}, {"t": "perk_taken", "id": "p_dmg"}, {"t": "perk_taken", "id": "p_glass"}, {"t": "perk_taken", "id": "p_greed"}])
	_check("AC-29 run events advance progress", _evts(mev, "mission_done").size() == 3 and int(Missions.list(M)[0]["prog"]) == 3 and int(Missions.list(M)[1]["prog"]) == 10 and int(Missions.list(M)[2]["prog"]) == 2 and int(M["stats"]["kills"]) == 4)
	_check("AC-29 claim pays once", not Missions.claim(M, 0).is_empty() and int(M["coins"]) == gm + 120 and Missions.claim(M, 0).is_empty())
	_check("bonus needs all claimed", Missions.claim_bonus(M).is_empty())
	Missions.claim(M, 1)
	Missions.claim(M, 2)
	_check("AC-29 all-clear bonus +200 coins once", not Missions.claim_bonus(M).is_empty() and int(M["coins"]) == gm + 120 + 160 + 80 + 200 and Missions.claim_bonus(M).is_empty() and MissionDB.reward("kill") == 120)
	Missions.roll(M, NOW + 86400)
	var fresh: bool = true
	for e in Missions.list(M):
		fresh = fresh and int(e["prog"]) == 0 and not bool(e["claimed"])
	_check("AC-28 new day re-rolls + resets", fresh and not bool(M["missions"]["bonus_claimed"]))
	# lab starts + eco placements feed missions (V2: the v3 perm-base upgrades are gone)
	M["missions"]["list"] = [{"tpl": "upgrade", "target": 3, "prog": 0, "claimed": false, "coins": 80}, {"tpl": "lab", "target": 2, "prog": 0, "claimed": false, "coins": 80}, {"tpl": "eco", "target": 4, "prog": 0, "claimed": false, "coins": 80}]
	M["coins"] = 100000
	Labs.start(M, "xp", NOW)
	Missions.on_run_events(M, [{"t": "placed", "slot": 7, "id": "mine"}, {"t": "placed", "slot": 8, "id": "gun"}])
	_check("lab starts / eco placements count", int(Missions.list(M)[1]["prog"]) == 1 and int(Missions.list(M)[2]["prog"]) == 1)
	# streak
	var K: Dictionary = BaseMeta.default_save()
	var day0: int = Missions.day_of(NOW)
	var sev: Array = Missions.streak_claim(K, NOW)
	_check("AC-30 streak day 1 = 50 coins", int((_evts(sev, "streak_claimed")[0] as Dictionary)["day"]) == 1 and int(K["coins"]) == 50)
	_check("AC-30 once per day", Missions.streak_claim(K, NOW + 100).is_empty())
	for k in range(1, 6):
		Missions.streak_claim(K, NOW + 86400 * k)
	# FEEDBACK-1: the streak pays coins only (gem days -> coins).
	_check("streak day 6", int(K["streak"]["day_idx"]) == 6 and int(K["coins"]) == 50 + 80 + 100 + 120 + 200 + 160)
	sev = Missions.streak_claim(K, NOW + 86400 * 6)
	# V2 (deliberate): the day-7 card chest became +60 Scrap (cards are gone).
	_check("AC-30 day 7 = 400 coins + 60 Scrap", int(K["streak"]["day_idx"]) == 7 and int(K["coins"]) == 710 + 400 and int(K["scrap"]) == 60 and int((sev[0] as Dictionary).get("scrap", 0)) == 60 and not K.has("gems"))
	var c0: int = int(K["coins"])
	Missions.streak_claim(K, NOW + 86400 * 7)
	_check("streak loops with x1.1 coins", int(K["streak"]["day_idx"]) == 1 and int(K["streak"]["loops"]) == 1 and int(K["coins"]) == c0 + 55)
	Missions.streak_claim(K, NOW + 86400 * 9)
	_check("AC-30 missed day resets to day 1", int(K["streak"]["day_idx"]) == 1 and int(K["streak"]["last_day"]) == day0 + 9)

	# --- Stage 18: run_mods bundle (A8) -------------------------------------
	var R: Dictionary = BaseMeta.default_save()
	R["best_wave_by_tier"] = {"1": 40, "2": 50}
	R["tier"] = 3
	R["research"]["lvls"]["dmg"] = 4
	R["research"]["lvls"]["startcash"] = 2
	R["research"]["lvls"]["reroll"] = 1
	R["runs"] = 2
	R = BaseMeta.normalize(R)
	var rm: Dictionary = BaseMeta.run_mods(R)
	_check("A8 run_mods tier + mults", int(rm["tier"]) == 3 and is_equal_approx(float(rm["hp_mult"]), 2.25) and is_equal_approx(float(rm["coin_mult"]), 2.2) and int(rm["boss_every"]) == 10)
	_check("A8 run_mods labs", is_equal_approx(float(rm["lab_dmg"]), 0.2) and int(rm["start_cash"]) == 30 and int(rm["rerolls"]) == 1 and is_equal_approx(float(rm["speed"]), 1.0))
	_check("A8 run_mods new bldgs (no cards in V2)", not rm.has("cards") and bool(rm["allow_new_bldg"]) and not bool(BaseMeta.run_mods(BaseMeta.default_save())["allow_new_bldg"]))


func _enemy(kind: String, pos: Vector2, hp: float = 999.0) -> Dictionary:
	var d: Dictionary = EnemyDB.get_def(kind)
	return {"kind": kind, "pos": pos, "hp": hp, "max_hp": hp, "spd": float(d["spd"]), "dmg": float(d["dmg"]), "cash": float(d["cash"]), "xp": float(d["xp"]), "coin": float(d["coin"]), "size": float(d["size"]), "atk_cd": 0.0, "slow_t": 0.0, "shield": 0, "fire_cd": 0.0, "shock_t": 0.0, "shock_src": -1}


## HORDE Phase 1: enemies live in S.en (struct-of-arrays). Tests still build
## legacy Dicts with _enemy(), inject them through the store (S.add_enemy /
## S.set_enemies write the eid + slot back into the Dict), and _sync() copies
## the live store values back into those Dicts before asserting on them.
func _adds(S, list: Array) -> void:
	for d in list:
		S.add_enemy(d)


func _sync(S, list: Array) -> void:
	for d in list:
		var cur: Dictionary = S.enemy_dict(int((d as Dictionary)["eid"]))
		if not cur.is_empty():
			(d as Dictionary).merge(cur, true)


## Write a test Dict's edited fields back into the store.
func _push(S, d: Dictionary) -> void:
	S.set_enemy(int(d["eid"]), d)


## A standalone EnemyStore + EnemyHash (Troops.step's query object) from Dicts.
func _troop_q(list: Array) -> Array:
	var st = load("res://EnemyStore.gd").new()
	for d in list:
		var sl: int = st.alloc(int(d["eid"]), String(d["kind"]), d["pos"])
		st.fill(sl, d)
	return [st, load("res://EnemyHash.gd").new(st, TowerState.CENTER)]


func _last(S) -> Dictionary:
	var l: Array = S.enemy_list()
	return l.back() if not l.is_empty() else {}


## HORDE Phases 3+4: fixed substeps, separation, contact rule, knockback.
func _horde_p34() -> void:
	var S = _fresh()
	S.spawn_hold = true
	var n0: float = S.time_alive
	S.tick(0.02)
	_check("P3 fixed substep: a 0.02 s frame runs no step (accumulates)", S.time_alive == n0)
	S.tick(0.03)
	_check("P3 fixed substep: the carried remainder runs exactly one SUBSTEP", is_equal_approx(S.time_alive - n0, TowerState.SUBSTEP))
	# separation: two overlapping drones far from the Core are pushed apart
	S = _fresh()
	S.spawn_hold = true
	var a: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(-2, -300), 50.0)
	var b: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(2, -300), 50.0)
	a["spd"] = 0.0
	b["spd"] = 0.0
	S.set_enemies([a, b])
	var d0: float = S.en.pos[0].distance_to(S.en.pos[1])
	S._move_enemies(0.05, [])
	_check("P3 separation pushes overlapping bodies apart (deterministic)", S.en.pos[0].distance_to(S.en.pos[1]) > d0)
	# contact rule (MASS §D2 pressure): the front rank and the pile within the
	# press band behind it hit the Core; bodies beyond the band do not.
	S = _fresh()
	S.spawn_hold = true
	var f: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, TowerState.STOP_R), 50.0)
	var r: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, TowerState.STOP_R + 40.0), 50.0)
	var far: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, TowerState.STOP_R + 120.0), 50.0)
	f["spd"] = 0.0
	r["spd"] = 0.0
	far["spd"] = 0.0
	S.set_enemies([f, r, far])
	var cev: Array = []
	S._move_enemies(0.05, cev)
	var hits: Array = _evts(cev, "core_hit")
	_check("P3 contact rule: the front rank + the pile within the press band attack the Core, not beyond", hits.size() == 2)
	# knockback: impulse, friction, mass resists, bosses immune
	S = _fresh()
	S.spawn_hold = true
	var lt: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, -300), 50.0)
	var hv: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(300, 0), 50.0)
	var bs: Dictionary = _enemy("boss", TowerState.CENTER + Vector2(-300, 0), 50.0)
	lt["size"] = 16.0
	hv["size"] = 32.0
	S.set_enemies([lt, hv, bs])
	S.en.knock(0, Vector2(0, -100))
	S.en.knock(1, Vector2(100, 0))
	S.en.knock(2, Vector2(-100, 0))
	_check("P4 knock: v/mass (2x size = 1/4 speed), boss immune", is_equal_approx(S.en.vel[0].length(), 100.0) and is_equal_approx(S.en.vel[1].length(), 25.0) and S.en.vel[2] == Vector2.ZERO)
	S.en.spd[0] = 0.0
	var y0: float = S.en.pos[0].y
	S._move_enemies(0.05, [])
	_check("P4 knock moves the body and friction decays it", S.en.pos[0].y < y0 and S.en.vel[0].length() < 100.0)


## MASS_HORDE §Architecture gates: the C#-resident HordeWorld (flow field,
## liquid pressure, knockback, aggregated contact, query API, determinism).
func _mh_field(S, kind: String, n: int, c: Vector2, r0: float, r1: float, spd: float = -1.0) -> void:
	for i in n:
		var a: float = TAU * float(i) / 97.0 + float(i) * 0.013
		var r: float = r0 + (r1 - r0) * float((i * 37) % 101) / 100.0
		var d: Dictionary = _enemy(kind, c + Vector2.from_angle(a) * r, 999.0)
		if spd >= 0.0:
			d["spd"] = spd
		S.add_enemy(d)


func _mh_steps(S, n: int, ev: Array = []) -> void:
	for k in n:
		S._move_enemies(0.05, ev)


func _mass_horde_world() -> void:
	var C: Vector2 = TowerState.CENTER
	# ---- determinism: two fresh worlds, same inputs -> same C# checksum
	var sums: Array = []
	for run in 2:
		var D = _fresh()
		D.spawn_hold = true
		_mh_field(D, "mite", 1500, C, 220.0, 520.0)
		_mh_field(D, "hauler", 40, C, 300.0, 500.0)
		_mh_steps(D, 120)
		sums.append(int(D.en.world.call("Checksum")))
	_check("MASS_HORDE HordeWorld checksum is deterministic (1540 bodies x 120 steps, two worlds)", sums[0] == sums[1] and sums[0] != 0)
	# ---- flow field routes around a wall; nobody passes through a building
	var W = _fresh()
	W.spawn_hold = true
	W.stats["weapons"] = []
	var wall: Array = []
	for c in range(-7, 8):   # V2 P3b: 15 small cells (390 px) five rows north of the Core
		var wi: int = _at(-5, c)
		W.slots[wi] = {"id": "barricade", "perm": 0, "run": 2}
		wall.append(wi)
	W.recompute()
	W.stats["weapons"] = []
	var above: Vector2 = TowerState.slot_pos(_rc(-1, 3)) + Vector2(0, -40)
	_mh_steps(W, 1)   # first step builds the flow field from the building set
	var fd: Vector2 = W.en.world.call("FlowDir", above.x + 30.0, above.y)
	_check("MASS_HORDE flow field steers sideways around a wall (not into it)", absf(fd.x) > 0.6)
	_check("MASS_HORDE flow field rebuilds only when buildings change", int((W.en.world.call("Stats") as Dictionary)["flow_rebuilds"]) >= 1)
	var fr0: int = int((W.en.world.call("Stats") as Dictionary)["flow_rebuilds"])
	_mh_field(W, "mite", 300, above + Vector2(0, -160), 0.0, 90.0)
	var inside: int = 0
	for k in 800:   # 40 s: the crowd piles on the wall and drains round its ends
		W._move_enemies(0.05, [])
		if k % 4 == 0:
			for es in W.en.order:
				var p: Vector2 = W.en.pos[es]
				for wi in wall:
					var q: Vector2 = p - TowerState.slot_pos(int(wi))
					if absf(q.x) < TowerState.CELL * 0.5 - 2.0 and absf(q.y) < TowerState.CELL * 0.5 - 2.0:
						inside += 1
	var near: int = 0
	for es in W.en.order:
		if W.en.pos[es].distance_to(C) <= 140.0:
			near += 1
	_check("MASS_HORDE H9 >=70%% of bodies path around the wall to the Core (%d/300), none through it (%d)" % [near, inside], near >= 210 and inside == 0)
	_check("MASS_HORDE flow field not rebuilt while the building set is unchanged", int((W.en.world.call("Stats") as Dictionary)["flow_rebuilds"]) == fr0)
	# ---- pressure: a dense crowd piles on the Core without collapsing into itself
	var P = _fresh()
	P.spawn_hold = true
	_mh_field(P, "mite", 2000, C, 260.0, 520.0)
	_mh_steps(P, 360)
	var ov: PackedFloat64Array = P.en.world.call("OverlapStats")
	var far: float = 0.0
	var touching: int = 0
	for es in P.en.order:
		var dd: float = P.en.pos[es].distance_to(C)
		far = maxf(far, dd)
		if dd <= TowerState.STOP_R + 6.0:
			touching += 1
	_check("MASS_HORDE pressure: 2000 piled bodies keep their volume (mean overlap %.2f, max %.2f)" % [ov[1], ov[2]], ov[1] < 0.25 and ov[2] < 0.7)
	_check("MASS_HORDE pressure: the pile backs up away from the Core (%d px) while the front rank presses it (%d)" % [int(far), touching], far > 150.0 and touching >= 8)
	# ---- knockback parts the crowd (H9: mean radial distance grows within 0.3 s)
	var spread: Array = []
	for with_kick in [false, true]:
		var K = _fresh()
		K.spawn_hold = true
		var kc: Vector2 = C + Vector2(0, -320)
		for i in 400:
			var d: Dictionary = _enemy("mite", kc + Vector2(float(i % 20) - 9.5, float(i / 20) - 9.5) * 10.0, 999.0)
			d["spd"] = 0.0
			K.add_enemy(d)
		_mh_steps(K, 1)
		if with_kick:
			K.en.radial_knock(kc, 120.0, 400.0)
		_mh_steps(K, 6)
		var md: float = 0.0
		for es in K.en.order:
			md += K.en.pos[es].distance_to(kc)
		spread.append(md / float(K.en.count()))
	_check("MASS_HORDE knockback parts the crowd within 0.3 s (mean radius %.1f -> %.1f)" % [spread[0], spread[1]], float(spread[1]) > float(spread[0]) + 10.0)
	# ---- queries match brute force (C# hash vs the GDScript mirror)
	var qok: bool = true
	var qmsg: String = ""
	for t in 12:
		var qc: Vector2 = C + Vector2.from_angle(float(t) * 0.7) * (40.0 + 25.0 * float(t))
		var qr: float = 20.0 + 9.0 * float(t)
		var got: PackedInt32Array = P.eh.in_radius(qc, qr)
		var lo: Array = []
		var hi: Array = []
		var best: float = INF
		for es in P.en.order:
			var dd2: float = P.en.pos[es].distance_to(qc)
			if dd2 <= qr - 0.01:
				lo.append(es)
			if dd2 <= qr + 0.01:
				hi.append(es)
				best = minf(best, dd2)
		for x in lo:
			if not got.has(int(x)):
				qok = false
		for x in got:
			if not hi.has(int(x)):
				qok = false
		var nn: int = P.eh.nearest(qc, qr, {})
		if hi.is_empty() != (nn < 0) or (nn >= 0 and absf(P.en.pos[nn].distance_to(qc) - best) > 0.01):
			qok = false
		var dn: int = P.eh.density(qc, qr)
		if dn < lo.size() or dn > hi.size():
			qok = false
		if not qok and qmsg == "":
			qmsg = "pt %d: got %d lo %d hi %d" % [t, got.size(), lo.size(), hi.size()]
	var la: Vector2 = C + Vector2(-300, -200)
	var lb: Vector2 = C + Vector2(300, 150)
	var lg: PackedInt32Array = P.eh.line(la, lb, 6.0)
	var lbf: int = 0
	var seg: Vector2 = lb - la
	for es in P.en.order:
		var q: Vector2 = P.en.pos[es]
		var t2: float = clampf((q - la).dot(seg) / seg.length_squared(), 0.0, 1.0)
		var tr: float = (q - la).dot(seg) / seg.length_squared()
		if tr >= 0.0 and tr <= 1.0 and q.distance_to(la + seg * t2) <= 6.0 + P.en.size[es] * 0.5 - 0.01:
			lbf += 1
	_check("MASS_HORDE queries match brute force (radius / nearest / density) %s" % qmsg, qok)
	_check("MASS_HORDE line query matches brute force (%d vs %d)" % [lg.size(), lbf], lg.size() >= lbf and lg.size() <= lbf + 2 and lbf > 0)
	var nn3: PackedInt32Array = P.eh.nearest_n(C, 8, 200.0)
	var mono: bool = nn3.size() == 8
	for i in range(1, nn3.size()):
		mono = mono and P.en.pos[nn3[i]].distance_to(C) >= P.en.pos[nn3[i - 1]].distance_to(C) - 0.001
	_check("MASS_HORDE nearest_n: 8 bodies nearest-first", mono)
	var dz: Vector2 = P._densest(40.0)
	_check("MASS_HORDE densest point lies in the pile", dz != Vector2.INF and dz.distance_to(C) < far)
	# ---- dead bodies leave the world at once (no query / move until reaped)
	var dead_s: int = P.en.order[0]
	P._hit(dead_s, 1e9, [])
	_check("MASS_HORDE a killed body drops out of queries before the reap", not P.eh.in_radius(P.en.pos[dead_s], 0.5).has(dead_s))
	# ---- V2 P3a sealed Core: no structure is ever attacked; the crowd squeezes
	# through the Wall ring (slower than open ground) and every hit lands on the Core.
	var at_core_n: Array = []
	var bld_ev: int = 0
	var sq_n: int = 0
	for sealed in [true, false]:
		var G = _fresh()
		G.spawn_hold = true
		G.stats["weapons"] = []
		if sealed:
			for rc in TowerState.CORE_RING:
				G.slots[int(rc)] = {"id": "barricade", "perm": 0, "run": 3}
		G.recompute()
		G.stats["weapons"] = []
		_mh_field(G, "mite", 600, TowerState.slot_pos(_rc(2, 3)) + Vector2(0, -150), 0.0, 120.0)
		for k in 160:
			var gev: Array = []
			G._move_enemies(0.05, gev)
			for e in gev:
				if String((e as Dictionary)["t"]) in ["bld_hit", "building_destroyed", "bld_repair"]:
					bld_ev += 1
		var at_core: int = 0
		for es in G.en.order:
			if G.en.pos[es].distance_to(C) <= TowerState.STOP_R + 10.0:
				at_core += 1
		at_core_n.append(at_core)
		if sealed:
			sq_n = int(G.en.world.call("SqueezeStartCount"))
	_check("V2 P3a sealed Core: the crowd squeezes through the Wall ring (%d at the Core vs %d on open ground, %d squeezes), no structure is ever hit" % [at_core_n[0], at_core_n[1], sq_n], int(at_core_n[0]) > 0 and int(at_core_n[0]) < int(at_core_n[1]) and sq_n > 0 and bld_ev == 0)


## HORDE Phase 1 gates: the 120 s seeded golden (recorded from the Dict
## implementation before the SoA port) and the store/hash invariants.
## FEEDBACK-1 (deliberate): no lanes, building blocking, live drafts, new
## tracks and difficulty change the sim, so the golden was re-recorded from
## this build (bit-identity to the Dict impl only held while rules matched).
## HORDE P3+P4 (deliberate): fixed substeps + separation + contact rule +
## knockback change the motion, so the golden was re-recorded again.
## MASS_HORDE (deliberate, FEEDBACK_3): the move step is now the C# HordeWorld
## (flow field around buildings, liquid pressure, aggregated building contact,
## C# queries in slot order), so the golden was re-recorded from this build.
## V2 P1 (deliberate): one Core (the 3 other attacks as sheet fixtures), no
## Drone Nest on the board (no air), no Steadfast trait / legacy Core stats,
## so the golden was re-recorded from this build (was c21bb566).
## V2 P3b (deliberate): 21x21 board of 26 px cells, 3x3 Core (STOP_R 44),
## 2x2 Mortar / Railgun, flow cells derived from the cell size, sticky face
## slides; the fingerprint board was re-laid on the new grid, so the golden
## was re-recorded from this build (was c9854a03).
## V2 P3d (deliberate): the classic ruleset is gone - the fingerprint runs
## designed mass waves (wave 14 plan, a fragile 150-body flood), beam / pulse on
## a Wall-sealed board (the squeeze path); re-recorded (was e5a407bd).
const HORDE_FP_GOLDEN: String = "ebffce97b4c320ac7be5b7a64cc76b2a0d8aedd084e5c54cf270db8a9b81e214"
## MASS_HORDE §Design content (designed mass waves, the shipping ruleset).
func _mfresh(seed_value: int = 1234):
	var S = TowerState.new()
	S.setup(seed_value, BaseMeta.normalize({}))
	return S


func _mass_content_stages() -> void:
	# ---- §D3 / H1: wave body counts 100s -> 1,000s -> 10,000s (T1)
	var S = _mfresh()
	_check("MASS H1 T1 bodies: w1 >= 100, w25 >= 1,000, w45 >= 10,000", S.mass_bodies(1) >= 100 and S.mass_bodies(25) >= 1000 and S.mass_bodies(45) >= 10000, "%d %d %d" % [S.mass_bodies(1), S.mass_bodies(25), S.mass_bodies(45)])
	var p1: Dictionary = S._build_mass_plan(1, 0.0)
	var mix_ok: bool = true
	for e in p1["entries"]:
		mix_ok = mix_ok and ["mite", "drone"].has(String((e as Dictionary)["kind"]))
	_check("MASS plan w1: B(1) designed bodies, swarmlings + grunts only, telegraph total", (p1["entries"] as Array).size() == S.mass_bodies(1) and mix_ok and int(S._telegraph_event(p1)["total"]) == S.mass_bodies(1))
	var p20: Dictionary = S._build_mass_plan(20, 0.0)
	var kinds20: Dictionary = {}
	for e in p20["entries"]:
		kinds20[String((e as Dictionary)["kind"])] = true
	_check("MASS plan w20: full roster (sapper, shield, splitter, hauler, elites) + boss flag", kinds20.has("sapper") and kinds20.has("shield") and kinds20.has("splitter") and kinds20.has("hauler") and kinds20.has("elite") and bool(p20["boss"]))
	_check("MASS T3: more bodies than T1 and sappers from wave 1", EnemyDB.tier_b(3) > EnemyDB.tier_b(1) and EnemyDB.mass_mix(1, 3).has("sapper") and not EnemyDB.mass_mix(1, 1).has("sapper"))
	# ---- H4 + H3: spawned bodies carry designed HP, never a share
	var ev: Array = []
	for i in 160:
		ev.append_array(S.tick(0.05))
	var h4: bool = S.en.count() > 0
	for sl in S.en.order:
		var k: String = S.en.kind[sl]
		var want: float = float(EnemyDB.mass_def(k)["hp"]) * S.mass_hp_scale(k, 1)
		if S.en.share[sl] != 1.0 or (not S.en.is_marked(sl) and absf(S.en.max_hp[sl] - want) > 1e-6 * want):
			h4 = false
	_check("MASS H3/H4: every body share 1, HP = designed x growth (no split factor)", h4)
	# ---- §D5 / H5: a full-clear wave pays its pool + 30% clear bonus
	var SE = _mfresh(77)
	SE.stats["weapons"] = []
	var kcash: float = 0.0
	var ccash: float = -1.0
	var guard: int = 0
	while ccash < 0.0 and guard < 600:
		guard += 1
		for e in SE.tick(0.05):
			var ed: Dictionary = e
			if String(ed["t"]) == "kills":
				kcash += float(ed["cash"])
			elif String(ed["t"]) == "wave_clear" and int(ed["wave"]) == 1:
				ccash = float(ed["cash"])
		for sl in SE.en.order:
			if SE.en.hp[sl] > 0.0:
				SE.en.hp[sl] = 0.0
				SE.en.kill(sl)
	var pool_c: float = SE.mass_cash_pool(1) * SE.run_cash_mult() * float(SE.stats["kill_cash"])
	_check("MASS H5: full clear of wave 1 pays pool x 1.3 (+-5%)", ccash >= 0.0 and absf((kcash + ccash) - pool_c * 1.3) <= 0.05 * pool_c * 1.3, "kill %.2f clear %.2f pool %.2f" % [kcash, ccash, pool_c])
	_check("MASS §D5: income per wave does not scale with the body count", absf(SE.mass_cash_pool(1) - SE.wave_time / SE.interval_for(1)) < 1e-9 and SE.mass_cash_pool(45) < 10.0 * SE.mass_cash_pool(1))
	# ---- §D3: the alive cap HOLDS the queue (never drops a planned body)
	var SH = _mfresh(5)
	SH.mass_cap = 40
	SH.stats["weapons"] = []
	SH.max_hp_mult = 1.0e9
	var peak: int = 0
	for i in 400:
		SH.tick(0.05)
		peak = maxi(peak, SH.en.count())
		SH.stats["weapons"] = []
	var held: bool = SH.plan_idx < SH.plan.size() and peak <= 40
	var killed: int = 0
	guard = 0
	while SH.plan_idx < SH.plan.size() and guard < 2000 and SH.wave == 1:
		guard += 1
		for sl in SH.en.order:
			if SH.en.hp[sl] > 0.0 and killed < 1000:
				SH.en.hp[sl] = 0.0
				SH.en.kill(sl)
				killed += 1
		SH.tick(0.05)
		SH.stats["weapons"] = []
	var a1: Dictionary = SH.wave_acct.get(1, {})
	_check("MASS alive cap: queue holds at the cap, then every planned body spawns", held and (a1.is_empty() or int(a1["spawned"]) == SH.mass_bodies(1)), "held %s peak %d" % [str(held), peak])
	# ---- §D1 / V2 Sapper: ignores structures, detonates on the Core (x6 its hit), no kill credit
	var SS = _mfresh()
	for i in TowerState.N:
		SS.unlocked[i] = i != TowerState.CORE_SLOT
	SS.spawn_hold = true
	var bi: int = _rc(1, 3)
	SS.slots[bi] = {"id": "barricade", "perm": 0, "run": 1}
	SS.recompute()
	SS.stats["weapons"] = []
	SS.stats["armor"] = 0.0
	SS.stats["dr"] = 0.0
	SS.shield = 0.0
	var shp0: float = SS.hp
	SS._spawn("sapper", [], TowerState.slot_pos(bi) + Vector2(0, -34))
	var sdmg: float = SS.en.dmg[SS.en.order[0]]
	SS.en.hp[SS.en.order[0]] = 1e9   # the Core's own gun must not kill it on the way
	var boom: Array = []
	for i in 240:
		boom.append_array(_evts(SS.tick(0.05), "sapper_blast"))
		SS.stats["weapons"] = []
		if not boom.is_empty():
			break
	var blast_ok: bool = boom.size() == 1 and int((boom[0] as Dictionary)["slot"]) == TowerState.CORE_SLOT and is_equal_approx(float((boom[0] as Dictionary)["dmg"]), 6.0 * sdmg)
	_check("MASS Sapper (V2): passes the Wall, detonates on the Core for x6 its hit, gone, not a kill", blast_ok and SS.hp < shp0 and SS.en.count() == 0 and SS.kills == 0, "%d blasts hp %.1f->%.1f n %d kills %d" % [boom.size(), shp0, SS.hp, SS.en.count(), SS.kills])
	# ---- §D1 Shieldbearer: the frontal shield soaks projectiles from the front only
	var SB = _mfresh()
	SB.spawn_hold = true
	SB._spawn("shield", [], TowerState.CENTER + Vector2(0, -300))
	var sb: int = SB.en.order[0]
	var g0: float = SB.en.guard[sb]
	var hp0: float = SB.en.hp[sb]
	SB._blockable = true
	SB._kb_from = TowerState.CENTER
	SB._hit(sb, 5.0, [])
	var front_ok: bool = SB.en.hp[sb] == hp0 and absf(SB.en.guard[sb] - (g0 - 5.0)) < 1e-9
	SB._kb_from = TowerState.CENTER + Vector2(0, -700)
	SB._hit(sb, 5.0, [])
	SB._blockable = false
	_check("MASS Shieldbearer: front hit soaked by its shield, a flank/rear hit is not", g0 > 0.0 and front_ok and absf(SB.en.hp[sb] - (hp0 - 5.0)) < 1e-9)
	# ---- §D4 weapon verbs
	var SG = _mfresh()
	SG.spawn_hold = true
	var gfrom: Vector2 = TowerState.CENTER
	for i in 6:
		SG.add_enemy({"kind": "mite", "pos": gfrom + Vector2(0, -60 - 14 * i), "hp": 999.0, "max_hp": 999.0, "size": 10.0})
	SG.eh.rebuild()
	SG._fire_mass("gun", {"slot": 0, "lvl": 1, "range": 300.0}, gfrom, SG.en.order[0], 10.0, false, [])
	var gh: int = 0
	for sl in SG.en.order:
		if SG.en.hp[sl] < 999.0:
			gh += 1
	# two rounds per shot (target + next nearest, here on the same line): each pierces 3
	_check("MASS Gun: 2 rounds, each pierces 3 bodies at Lv1 (x0.85 falloff)", gh == 3 and absf(SG.en.hp[SG.en.order[2]] - (999.0 - 2.0 * 10.0 * 0.85 * 0.85)) < 1e-6, "hit %d" % gh)
	var ST = _mfresh()
	ST.spawn_hold = true
	for i in 25:
		ST.add_enemy({"kind": "mite", "pos": TowerState.CENTER + Vector2(-600 + 50 * i, -200), "hp": 999.0, "max_hp": 999.0, "size": 10.0})
	ST.eh.rebuild()
	ST._fire_mass("tesla", {"slot": 0, "lvl": 1, "range": 300.0}, TowerState.CENTER, ST.en.order[0], 10.0, false, [])
	var th: int = 0
	for sl in ST.en.order:
		if ST.en.hp[sl] < 999.0:
			th += 1
	_check("MASS Tesla: 3 arcs x chain 6 = 18 distinct bodies at Lv1 (70 px jumps)", th == 18, "hit %d" % th)
	var SF = _mfresh()
	SF.spawn_hold = true
	SF.add_enemy({"kind": "mite", "pos": TowerState.CENTER + Vector2(0, -100), "hp": 999.0, "max_hp": 999.0, "size": 10.0})
	SF.add_enemy({"kind": "mite", "pos": TowerState.CENTER + Vector2(0, -108), "hp": 999.0, "max_hp": 999.0, "size": 10.0})
	SF.add_enemy({"kind": "mite", "pos": TowerState.CENTER + Vector2(0, 100), "hp": 999.0, "max_hp": 999.0, "size": 10.0})
	SF.eh.rebuild()
	SF._fire_mass("flak", {"slot": 0, "lvl": 1, "range": 300.0}, TowerState.CENTER, SF.en.order[0], 10.0, false, [])
	var cone_ok: bool = SF.en.hp[SF.en.order[0]] < 999.0 and SF.en.hp[SF.en.order[1]] < 999.0 and SF.en.hp[SF.en.order[2]] == 999.0 and SF.burning.size() == 2
	SF.add_enemy({"kind": "mite", "pos": TowerState.CENTER + Vector2(9, -100), "hp": 999.0, "max_hp": 999.0, "size": 10.0})
	SF.eh.rebuild()
	SF._burn_step(0.25, [])
	_check("MASS Flamer: cone licks bodies ahead (not behind), burn spreads to a touching body", cone_ok and SF.en.burn_t[SF.en.order[3]] > 0.0)
	# ---- §D1 Warlord surge: fodder near a Warlord runs +20%; a slow still wins
	var SW2 = _mfresh()
	SW2.spawn_hold = true
	SW2._spawn("elite", [], TowerState.CENTER + Vector2(0, -400))
	SW2.add_enemy({"kind": "mite", "pos": TowerState.CENTER + Vector2(30, -400), "hp": 999.0, "max_hp": 999.0, "size": 10.0, "spd": 0.0})
	SW2.add_enemy({"kind": "mite", "pos": TowerState.CENTER + Vector2(-30, -400), "hp": 999.0, "max_hp": 999.0, "size": 10.0, "spd": 0.0})
	SW2.add_enemy({"kind": "mite", "pos": TowerState.CENTER + Vector2(0, 400), "hp": 999.0, "max_hp": 999.0, "size": 10.0, "spd": 0.0})
	var slowed: int = SW2.en.order[2]
	SW2.en.apply_slow(slowed, 5.0, 0.5)
	SW2.eh.rebuild()
	SW2._warlord_surge(0.3)
	_check("MASS Warlord surge: near fodder x1.2, far fodder untouched, a slowed body stays slowed", SW2.en.slow_m[SW2.en.order[1]] == 1.2 and SW2.en.slow_m[SW2.en.order[3]] == 1.0 and SW2.en.slow_m[slowed] == 0.5)
	# ---- §D6 rescaled kill missions
	_check("MASS §D6 missions: kill 5k / 15k / 40k; kill-in-one-wave 1k / 5k", MissionDB.target("kill", 0) == 5000 and MissionDB.target("kill", 25) == 15000 and MissionDB.target("kill", 40) == 40000 and MissionDB.target("wave_kills", 0) == 1000 and MissionDB.target("wave_kills", 40) == 5000)
	# ---- H10: same seed, same mass run (kills / cash / bodies / C# checksum)
	var D1 = _mfresh(99)
	var D2 = _mfresh(99)
	for i in 900:
		D1.tick(0.05)
		D2.tick(0.05)
	_check("MASS H10: same seed -> identical kills / cash / bodies / C# checksum", D1.kills == D2.kills and D1.cash == D2.cash and D1.en.count() == D2.en.count() and int(D1.en.world.call("Checksum")) == int(D2.en.world.call("Checksum")) and D1.kills > 0)


func _horde_stages() -> void:
	var FP = load("res://horde_fp.gd")
	var got: String = FP.run_all()
	_check("HORDE 120 s seeded fingerprint matches the recorded golden (%s)" % got.left(8), got == HORDE_FP_GOLDEN)
	_check("HORDE fingerprint is deterministic (two runs)", FP.run_all() == got)
	# MASS_HORDE (deliberate): the C# vs GDScript float32 parity gate is retired
	# with the GDScript move path (MASS_HORDE §11: HordeMove.cs folded into the
	# C# HordeWorld, doubles throughout). Determinism moves to the HordeWorld
	# checksum and the fingerprint above; the world itself is gated below.
	_check("HORDE C# HordeWorld available (mono build)", load("res://EnemyStore.gd").cs_available())
	_mass_horde_world()
	_mass_content_stages()
	_horde_p34()
	var S = _fresh()
	S.spawn_hold = true
	var a: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, -300), 5.0)
	var b: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, 300), 5.0)
	var c: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(300, 0), 5.0)
	S.set_enemies([a, b, c])
	_check("HORDE store: slots 0..n-1, eid map, spawn order", int(a["slot"]) == 0 and int(c["slot"]) == 2 and S.en.slot_of(int(b["eid"])) == 1 and Array(S.en.order) == [0, 1, 2])
	S.set_enemy(int(b["eid"]), {"hp": 0.0})
	S._reap([])
	_check("HORDE reap frees the slot, keeps spawn order, drops the eid", Array(S.en.order) == [0, 2] and S.en.slot_of(int(b["eid"])) == -1 and S.enemy_dict(int(b["eid"])).is_empty())
	S._spawn("skitter", [], TowerState.CENTER + Vector2(-300, 0))
	_check("HORDE free list reuses the slot; new body goes last in order", Array(S.en.order) == [0, 2, 1] and String(S.en.kind[1]) == "skitter")
	_check("HORDE hash in_radius / nearest", Array(S.eh.in_radius(TowerState.CENTER + Vector2(0, -300), 10.0)) == [0] and S.eh.nearest(TowerState.CENTER + Vector2(290, 0), 50.0, {}) == 2 and S.eh.nearest(TowerState.CENTER, 50.0, {}) == -1)
	var hits: Array = []
	S.eh.damage(TowerState.CENTER, 310.0, 1.0, func(sl: int, amt: float) -> void: hits.append(sl))
	# MASS_HORDE (deliberate): queries come from the C# hash in ascending SLOT
	# order (was spawn order from the retired GDScript hash); still every body.
	_check("HORDE hash damage(): every live body in radius, slot order", hits == [0, 1, 2])
	_check("HORDE density counts exact neighbours", S.eh.density(TowerState.CENTER + Vector2(0, -300), 1.0) == 1)
	# V2 P3d (deliberate): the legacy split knob (horde_mult) and its per-body
	# loot pool / scaled bodies are gone with the classic ruleset; mass loot is
	# covered by the MASS §D5 stages.
	var SW = _fresh()
	SW.spawn_hold = true
	var wi: int = _rc(1, 2)
	SW.slots[wi] = {"id": "barricade", "perm": 0, "run": 1}
	SW.unlocked[wi] = true
	SW.recompute()
	SW._spawn("drone", [], SW.slot_pos(wi) + Vector2(0, -20))
	SW._spawn("drone", [], SW.slot_pos(wi) + Vector2(0, -900))
	SW.eh.rebuild()
	SW._wall_auras([])
	_check("FB2 Wall aura slows bodies on any side, not far ones", SW.en.slow_t[SW.en.order[0]] > 0.0 and SW.en.slow_t[SW.en.order[1]] == 0.0)
	var SC = _fresh()
	_check("FB2 map: the horde spawn ring lies beyond the framed view ring", SC.spawn_r() > SC.view_r())
	# ---- Phase 2: flat armor split + event aggregation
	var S4 = _fresh()
	S4.spawn_hold = true
	_check("V2 P3d: the body budget is the mass alive cap", S4.max_bodies() == S4.mass_cap)
	S4.stats["armor"] = 2.0
	S4.stats["dr"] = 0.0
	var hp0: float = S4.hp
	S4._core_damage(4.0, [], "core_hit", TowerState.CENTER, -1, 0.25)
	_check("HORDE flat armor split per body (4 - 2/4 = 3.5)", absf((hp0 - S4.hp) - 3.5) < 1e-9 or S4.shield > 0.0)
	var agg: Array = [{"t": "wave", "wave": 2}]
	for i in 5:
		agg.append({"t": "kill", "pos": Vector2(i, 0), "cash": 1.5, "kind": "drone"})
		agg.append({"t": "dmg", "eid": i, "pos": Vector2(i, 0), "amt": float(i + 1)})
	agg.append({"t": "kill", "pos": Vector2.ZERO, "cash": 9.0, "kind": "boss"})
	agg.append({"t": "core_hit", "dmg": 2.0, "pos": Vector2.ZERO})
	TowerState.aggregate_events(agg, 1)
	var ks: Array = _evts(agg, "kills")
	var hs: Array = _evts(agg, "hits")
	_check("HORDE aggregation: 1 kills (n 5, cash 7.5) + 1 hits (sum 15) + 1 core_hits; boss kill stays single", ks.size() == 1 and int(ks[0]["n"]) == 5 and absf(float(ks[0]["cash"]) - 7.5) < 1e-9 and hs.size() == 1 and absf(float(hs[0]["sum"]) - 15.0) < 1e-9 and _evts(agg, "core_hits").size() == 1 and _evts(agg, "kill").size() == 1 and _evts(agg, "dmg").is_empty() and String(agg[0]["t"]) == "wave")
	var sv: Dictionary = BaseMeta.normalize({})
	Missions.on_run_events(sv, [{"t": "kills", "n": 7, "by_kind": {"drone": 7}}])
	_check("HORDE aggregated kills count per body in Stats", int((sv["stats"] as Dictionary)["kills"]) == 7)


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
	sv["research"]["lvls"]["dmg"] = 4
	sv["research"]["lvls"]["hp"] = 2
	sv["research"]["lvls"]["startcash"] = 2
	sv["research"]["lvls"]["reroll"] = 1
	var S = TowerState.new()
	S.setup(7, sv)
	_check("B1 dmg x (1+lab) (V2: no cards)", is_equal_approx(float(_weapon(S, "core")["dmg"]), core0 * 1.2))
	_check("B1 max hp x (1+lab_hp)", is_equal_approx(float(S.stats["max_hp"]), 132.0) and is_equal_approx(S.hp, 132.0))
	_check("B1 start cash + rerolls", is_equal_approx(S.cash, 30.0) and S.rerolls_left == 1)
	sv["best_wave_by_tier"] = {"1": 60, "2": 0}
	sv["tier"] = 2
	S = TowerState.new()
	S.setup(7, sv)
	_check("B1 tier 2 multipliers", S.tier == 2 and is_equal_approx(S.hp_mult, 1.5) and is_equal_approx(S.coin_mult, 1.6))
	S.spawn_hold = true
	S._spawn("drone", [])
	# V2 P3d: mass bodies carry a tier's threat in their COUNT (tierB); per-body
	# HP only takes what tierB does not (mass_tier_hp = max(1, hp_mult / tierB)).
	_check("B1 tier 2: body HP = mass sheet x mass_hp_scale (tier HP rides on the count)", is_equal_approx(float(S.enemy_list()[0]["hp"]), float(EnemyDB.mass_def("drone")["hp"]) * S.mass_hp_scale("drone", S.wave)) and is_equal_approx(S.mass_tier_hp(), maxf(1.0, 1.5 / EnemyDB.tier_b(2))))
	S.set_enemies([])
	S.wave_t = S.wave_time - 0.001
	S.tick(0.05)
	_check("B1 wave coins x coin_mult", is_equal_approx(S.coins_run, 2.0 * 1.6))
	S.draft = [{"kind": "new", "id": "gun"}]
	var rr: Array = S.reroll_draft()
	# REDESIGN: the first reroll of every draft is free; banked rerolls next.
	_check("first reroll per draft is free", rr.size() == 1 and S.rerolls_left == 1 and S.draft.size() == 3)
	rr = S.reroll_draft()
	_check("second reroll spends a banked reroll", rr.size() == 1 and S.rerolls_left == 0 and S.draft.size() == 3)

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
		S.add_enemy(b)
		S._reap(bev)
	var bb: Array = _evts(bev, "boss_bounty")
	_check("boss bounty coins 25*w/10", bb.size() == 4 and int(bb[0]["coins"]) == 50)
	# FEEDBACK-1 (deliberate): gems are gone — bosses pay coins only, and an
	# old save's gem balance converts to coins (GEM_COINS each) on load.
	_check("FB1 boss bounty carries no gems", not (bb[0] as Dictionary).has("gems") and not ("gems_run" in S))
	var gsv: Dictionary = BaseMeta.default_save()
	gsv["gems"] = 4
	gsv["gem_log"] = {"boss": 4}
	var gn: Dictionary = BaseMeta.normalize(gsv)
	_check("FB1 gem blocks dropped on load", not gn.has("gems") and not gn.has("gem_log") and not gn.has("boss_gems_today"))
	S.slots[_r(7)] = {"id": "mine", "perm": 0, "run": 1}
	S.wave = 11
	S.recompute()
	# REDESIGN: every cash amount scales with the run cash index 1.10^(w-1).
	_check("cash/s (Core + Mine) x cash index 1.10^(w-1)", is_equal_approx(float(S.stats["cash_ps"]), (2.0 + 0.8) * pow(1.1, 10.0)))
	S.cash_earned = 1000.0 * pow(1.1, 10.0)
	var c_before: int = int(S.coins_run)
	S.hp = -1.0
	S.stats["regen"] = 0.0
	var dev: Array = S.tick(0.05)
	var go: Array = _evts(dev, "game_over")
	_check("AC-22 game_over itemises cash-out (12% of index-deflated cash)", go.size() == 1 and int(go[0]["breakdown"]["cashout"]) == 120 and int(go[0]["coins"]) == c_before + 120 and not (go[0]["breakdown"] as Dictionary).has("gems"))
	_check("death banks coins (no gems)", int(sv3["coins"]) == c_before + 120 and not sv3.has("gems"))
	_check("dead stays the last event", String(dev.back()["t"]) == "dead")

	# --- Stage 22: B4 enemy roster (AC-25..27) --------------------------------
	_check("ranged gated to wave 8", not Tiers.allows("ranged", 1, 7) and Tiers.allows("ranged", 1, 8))
	# V2 P3d (deliberate): the classic per-spawn roll (_roll_kind) is gone; the
	# mass wave mix (EnemyDB.mass_mix) and its elites are covered by the MASS
	# plan stages.
	S = _fresh()
	S.spawn_hold = true
	S.stats["weapons"] = []
	S.stats["regen"] = 0.0
	S.add_enemy(_enemy("ranged", TowerState.CENTER + Vector2(240, 0)))
	S.set_enemy(int(S.enemy_list()[0]["eid"]), {"fire_cd": 2.0})
	var shots: int = 0
	for k in 100:
		for ch in _evts(S.tick(0.05), "core_hits"):   # V2 P3d: shots aggregate into core_hits
			shots += int((ch as Dictionary).get("shots", 0))
	var rpos: Vector2 = S.enemy_list()[0]["pos"]
	_check("AC-25 ranged stops at 230", absf(rpos.distance_to(TowerState.CENTER) - 230.0) < 0.5)
	_check("AC-25 ranged fires every 2s", shots == 2 and S.hp < float(S.stats["max_hp"]))
	S = _fresh()
	S.spawn_hold = true
	S.wave = 20
	S._spawn("elite", [])
	var el: Dictionary = S.enemy_list()[0]
	_check("AC-26 elite shield 3+floor(w/10)", int(el["shield"]) == 5)
	var sev: Array = []
	for k in 5:
		S._hit(int(el["slot"]), 1.0e6, sev)
	_sync(S, [el])
	_check("AC-26 shield absorbs exactly N hits", float(el["hp"]) > 0.0 and _evts(sev, "shield_hit").size() == 5 and _evts(sev, "shield_break").size() == 1)
	S._hit(int(el["slot"]), 1.0e6, sev)
	_sync(S, [el])
	_check("elite takes damage after shield breaks", float(el["hp"]) <= 0.0)
	S = _fresh()
	S.spawn_hold = true
	S.slots[_r(7)] = {"id": "tesla", "perm": 0, "run": 3}
	S.recompute()
	S.stats["weapons"] = [_weapon(S, "tesla")]
	S._spawn("elite", [])
	S.set_enemy(int(S.enemy_list()[0]["eid"]), {"pos": TowerState.slot_pos(_r(7)) + Vector2(60, 0), "spd": 0.0})
	var tev: Array = S.tick(0.05)
	_check("AC-26 tesla chain hit counts as a shield hit", _evts(tev, "shield_hit").size() == 1 and int(S.enemy_list()[0]["shield"]) == 2)
	S = _fresh()
	S.spawn_hold = true
	S.add_enemy(_enemy("splitter", TowerState.CENTER + Vector2(300, 0), 0.0))
	var spv: Array = []
	S._reap(spv)
	var mites: int = 0
	for e in S.enemy_list():
		if String(e["kind"]) == "mite":
			mites += 1
	_check("AC-27 Broodsac bursts into mass_brood (6) swarmlings once", mites == TuneRef.int_of("mass_brood", 6) and _evts(spv, "split").size() == 1)
	for e in S.enemy_list():
		S.set_enemy(int(e["eid"]), {"hp": 0.0})
	spv.clear()
	S._reap(spv)
	_check("AC-27 mites do not split", S.enemy_count() == 0 and _evts(spv, "split").is_empty())

	# --- Stage 23: roguelite buildings (REDESIGN_SYSTEMS §2.3) ----------------
	# REDESIGN (deliberate): the S1-S11 adjacency web and the DR stack are
	# replaced by the redesign building sheet; these checks cover it.
	S = _open_run()
	S.slots[_r(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	var gr: float = float(_weapon(S, "gun")["rate"])
	_check("gatling L1: 6 dmg, 2.0/s", is_equal_approx(float(_weapon(S, "gun")["dmg"]), 6.0 * TowerState.bld_dmg()) and is_equal_approx(gr, 2.0))
	S.slots[_r(7)] = {"id": "gun", "perm": 0, "run": 5}
	S.recompute()
	_check("level-ups +35% main stat (L5 = 1.35^4)", is_equal_approx(float(_weapon(S, "gun")["dmg"]), 6.0 * TowerState.bld_dmg() * pow(1.35, 4.0)) and S.lvl_at(_r(7)) == 5)
	S.slots[_r(7)] = {"id": "gun", "perm": 0, "run": 9}
	_check("building level capped at 5", S.lvl_at(_r(7)) == 5 and TowerState.lvl_cap() == 5)
	S.slots[_r(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.slots[_at(-2, 1)] = {"id": "oilmill", "perm": 0, "run": 1}   # touches the gun (and the Core)
	S.recompute()
	_check("oil mill: +2.0 cash/s, adjacent buildings -10% rate (never the Core)", is_equal_approx(float(_weapon(S, "gun")["rate"]), gr * 0.9) and _has_link(S, _at(-2, 1), _r(7), "OIL") and not _has_link(S, _at(-2, 1), TowerState.CORE_SLOT, "OIL"))
	S.slots[_at(-2, 1)] = {}
	S.slots[_rc(4, 1)] = {"id": "beacon", "perm": 0, "run": 1}
	S.recompute()
	var gb: Dictionary = _weapon(S, "gun")
	_check("beacon radius 4 cells: +10% rate, +0.3 range", is_equal_approx(float(gb["rate"]), gr * 1.1) and is_equal_approx(float(gb["range"]), 3.3 * TowerState.cpx()) and _has_link(S, _rc(4, 1), _r(7), "BEA"))
	S.slots[_rc(4, 1)] = {}
	S.slots[_at(-7, 0)] = {"id": "beacon", "perm": 0, "run": 1}
	S.recompute()
	_check("beacon does not reach 5 cells away", is_equal_approx(float(_weapon(S, "gun")["rate"]), gr))
	# Aegis: Core shield absorbs hits, regenerates after 4 s without damage.
	S = _fresh()
	S.spawn_hold = true
	S.slots[_r(13)] = {"id": "aegis", "perm": 0, "run": 1}
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
	S.slots[_r(7)] = {"id": "vault", "perm": 0, "run": 1}
	S.recompute()
	S.cash = 100.0
	S.wave_t = S.wave_time - 0.001
	var vev: Array = S.tick(0.05)
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
	S.add_enemy(_enemy("drone", TowerState.slot_pos(_rc(2, 3)) + Vector2(0, -100), 0.0))
	S.cash = 0.0
	S._reap([])
	var near_c: float = S.cash
	S.add_enemy(_enemy("drone", TowerState.CENTER + Vector2(0, 300), 0.0))
	S.cash = 0.0
	S._reap([])
	_check("bounty: +20% kill cash only in radius", is_equal_approx(near_c, 1.2) and is_equal_approx(S.cash, 1.0))
	# Mortar min range, Cryo Spire slow aura, Obelisk lifesteal.
	S = _open_run()
	S.slots[_rc(2, 3)] = {"id": "mortar", "perm": 0, "run": 1}
	S.recompute()
	S.stats["weapons"] = [_weapon(S, "mortar")]
	var close_e: Dictionary = _enemy("hauler", TowerState.slot_pos(_rc(2, 3)) + Vector2(0, -50))
	S.set_enemies([close_e])
	S._fire(0.01, [])
	_sync(S, [close_e])
	_check("mortar cannot fire inside 1.5 cells", is_equal_approx(float(close_e["hp"]), 999.0))
	var far_e: Dictionary = _enemy("hauler", TowerState.slot_pos(_rc(2, 3)) + Vector2(0, -250))
	S.set_enemies([far_e])
	S._fire(0.01, [])
	_sync(S, [far_e])
	_check("mortar hits 18 dmg beyond min range", is_equal_approx(999.0 - float(far_e["hp"]), 18.0 * TowerState.bld_dmg()))
	S = _open_run()
	S.slots[_rc(2, 3)] = {"id": "frost", "perm": 0, "run": 1}
	S.recompute()
	S.stats["weapons"] = [_weapon(S, "frost")]
	var fe: Dictionary = _enemy("drone", TowerState.slot_pos(_rc(2, 3)) + Vector2(0, -150))
	S.set_enemies([fe])
	S._fire(0.01, [])
	_sync(S, [fe])
	# V2 P3d: the mass Cryo field slows 50% (mass_frost_slow) and chills for 10% of a pulse
	_check("cryo spire: slows 50% + chills (1.5 x 0.1 per pulse, 2/s) + frost flag", is_equal_approx(float(fe["slow_m"]), 0.5) and float(fe["slow_t"]) > 0.0 and is_equal_approx(999.0 - float(fe["hp"]), 1.5 * TowerState.bld_dmg() * TuneRef.num("mass_frost_dmg", 0.1)))
	S = _fresh()
	S.slots[_r(7)] = {"id": "obelisk", "perm": 0, "run": 1}
	S.recompute()
	S.hp = 50.0
	S._hit(S.add_enemy(_enemy("hauler", TowerState.CENTER + Vector2(0, 300))), 100.0, [])
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
	var pev: Array = S.tick(0.05)
	var had_draft: bool = S.draft.size() == 3
	S.draft = [Draft.card_for("pk_arsenal", S._draft_ctx(""))]
	pev.append_array(S.choose_card(0))
	_check("AC-23 perk_offer at wave 5 (right after the wave-4 draft)", had_draft and _evts(pev, "perk_offer").size() == 1 and S.perk_offer.size() == 3 and is_equal_approx(S.time_scale(), 1.0))   # FB1: sim stays live
	S = _fresh()
	S.spawn_hold = true
	S.wave = 4
	S.wave_t = S.wave_time - 0.001
	pev = S.tick(0.05)
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
	_check("AC-24 economy tradeoffs", is_equal_approx(S.run_coin_mult(), 1.5 * TuneRef.num("perk_bloodmoon", 1.25)) and is_equal_approx(S.run_cash_mult(), 1.5) and is_equal_approx(float(S.stats["xp_mult"]), 0.7) and S.upgrade_cost(TowerState.CORE_SLOT) == 84)   # FB1: Damage track base 120 (x0.7 Miser)
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

	# --- Stage 25: B8 revive / wave skip (AC-33) -----------------------------
	# V2 (deliberate): cards are gone; Second Wind / Wave Skip stay engine
	# mechanics fed by the meta bundle (wind_hp / skip_chance; P7 perks).
	var sv8: Dictionary = BaseMeta.default_save()
	S = TowerState.new()
	S.setup(3, sv8)
	S.wind_hp = 0.25
	S.spawn_hold = true
	S.hp = -1.0
	var wev: Array = S.tick(0.05)
	_check("AC-33 Second Wind revives at wind_hp", _evts(wev, "revive").size() == 1 and not S.over and S.hp > 0.2 * float(S.stats["max_hp"]) and S.hp <= 0.255 * float(S.stats["max_hp"]))
	S.hp = -1.0
	wev = S.tick(0.05)
	_check("AC-33 Second Wind only once", S.over and _evts(wev, "revive").is_empty())
	S = TowerState.new()
	S.setup(3, sv8)
	S.skip_chance = 1.0
	S.spawn_hold = true
	S.wave = 3
	S.wave_t = S.wave_time - 0.001
	var kv: int = S.kills
	wev = S.tick(0.05)
	var sk: Array = _evts(wev, "wave_skip")
	_check("AC-33 Wave Skip jumps 2 waves with 50% coins", S.wave == 5 and sk.size() == 1 and int(sk[0]["skipped"]) == 4 and is_equal_approx(S.coins_run, 4.0 * 0.5 + 5.0) and S.kills == kv)
	_check("skip landing on a perk wave still queues a perk", S.perk_offer.size() == 3 or S.perk_pending > 0)


## Fix-round systems: Core Overcharge (in-run cash sink), Core Overdrive (late
## coin sink via tier-raised core caps), S6/S7 eco->weapon feeders, run level cap.
func _fix_round_stages() -> void:
	# V2 (deliberate): the v3 Core stat caps / Overdrive are gone with the
	# permanent base (the Core level is the permanent Core power).
	# REDESIGN (deliberate): Core Overcharge is replaced by the Damage cash
	# track. FEEDBACK-1 (deliberate): fewer, bigger levels — x1.25 per level on
	# the Core AND every building (drawback -8% Core rate), cost 60 x 2.1^n.
	var S = _fresh()
	S.slots[_r(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	var g0: float = float(_weapon(S, "gun")["dmg"])
	var c0: float = float(_weapon(S, "core")["dmg"])
	S.cash = 1000.0
	S.upgrade(TowerState.CORE_SLOT)
	S.upgrade(TowerState.CORE_SLOT)
	_check("Damage track: 2 levels -> Core + buildings x1.40^2", S.core_run_lvl == 2 and is_equal_approx(float(_weapon(S, "gun")["dmg"]), g0 * 1.96) and is_equal_approx(float(_weapon(S, "core")["dmg"]), c0 * 1.96))
	_check("Damage track cost 120 x growth^n", S.upgrade_cost(TowerState.CORE_SLOT) == int(round(120.0 * pow(float(TowerState.TRACKS["dmg"]["growth"]), 2.0))) and is_equal_approx(float(S.stats["overcharge_step"]), 0.40))
	# Enemy damage ramp 1.06/wave so HP (labs, perks, Overdrive) matters late.
	S = _fresh()
	S.spawn_hold = true
	S._spawn("drone", [])
	var d1: float = float(_last(S)["dmg"])
	S.wave = 41
	S._spawn("drone", [])
	_check("enemy dmg ramp 1.06^(w-1)", is_equal_approx(float(_last(S)["dmg"]), d1 * pow(TuneRef.num("mass_dmg_g", S.dmg_growth), 40.0)) and is_equal_approx(S.dmg_growth, 1.06))


## VFX/gameplay pass: per-weapon targeting modes, hit flash + dmg events,
## tier-5 wave-60 enemy cap stress.
func _juice_targeting_stages() -> void:
	var S = _fresh()
	S.set_enemies([])
	var from: Vector2 = TowerState.slot_pos(_r(7))
	# a: nearest to weapon, low hp, far from core
	var a: Dictionary = _enemy("drone", from + Vector2(0, -60), 5.0)
	# b: closest to core, mid hp
	var b: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(-90, 0), 50.0)
	# c: strongest, farther from weapon
	var c: Dictionary = _enemy("drone", from + Vector2(150, -120), 500.0)
	# d: out of range, would win every mode
	var d: Dictionary = _enemy("drone", from + Vector2(0, -2000), 1.0)
	S.set_enemies([a, b, c, d])
	_check("target nearest", S.pick_target(from, 400.0, "nearest") == 0)
	_check("target first (closest to core)", S.pick_target(from, 400.0, "first") == 1)
	_check("target strongest", S.pick_target(from, 400.0, "strongest") == 2)
	_check("target weakest", S.pick_target(from, 400.0, "weakest") == 0)
	_check("target none in range", S.pick_target(from + Vector2(0, -5000), 50.0, "first") == -1)
	# Per-slot modes: only weapon slots, cycle wraps, fire() uses the mode.
	S = _fresh()
	S.slots[_r(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	_check("default target mode nearest", String(S.target_modes[_r(7)]) == "nearest")
	_check("non-weapon slot rejects mode", S.set_target_mode(_r(3), "first").is_empty())
	var cev: Array = S.cycle_target_mode(_r(7))
	_check("cycle -> first + event", String(S.target_modes[_r(7)]) == "first" and cev.size() == 1 and String((cev[0] as Dictionary)["t"]) == "target_mode")
	S.cycle_target_mode(_r(7))
	S.cycle_target_mode(_r(7))
	S.cycle_target_mode(_r(7))
	_check("cycle wraps to nearest", String(S.target_modes[_r(7)]) == "nearest")
	S.set_target_mode(_r(7), "strongest")
	S.set_enemies([])
	var from7: Vector2 = TowerState.slot_pos(_r(7))
	var weak: Dictionary = _enemy("drone", from7 + Vector2(0, -40), 10.0)
	var strong: Dictionary = _enemy("drone", from7 + Vector2(0, -150), 900.0)
	S.set_enemies([weak, strong])
	for k in TowerState.N:
		S.cooldowns[k] = 99.0
	S.cooldowns[_r(7)] = 0.0
	var fev: Array = []
	S._fire(0.01, fev)
	_sync(S, [weak, strong])
	# V2 P3d: the mass Gatling fires two rounds - the first at the mode's
	# target (the strongest), the second at the next nearest body.
	var sh: Array = _evts(fev, "shot")
	_check("fire() honours strongest mode (first round at the strongest)", float(strong["hp"]) < 900.0 and sh.size() >= 1 and ((sh[0] as Dictionary)["to"] as Vector2).distance_to(strong["pos"] as Vector2) < 20.0)
	_check("hit sets hit_t flash + counts into the hits summary", float(strong["hit_t"]) > 0.0 and S._hn >= 1)
	# REDESIGN (deliberate): every building is run-only, so modes are run-scoped.
	var S2 = TowerState.new()
	S2.setup(77, S.save)
	_check("target modes are run-scoped (fresh run starts nearest)", String(S2.target_modes[_r(7)]) == "nearest" and not (S.save as Dictionary).has("target_modes"))
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
		peak = maxi(peak, S.enemy_count())
		t += 0.05
		S.draft.clear()
		S.perk_offer.clear()
	_check("T5 w60 10 s flood: enemy count capped at the mass alive cap (peak %d)" % peak, peak <= S.mass_cap and peak > 50)


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
	var S = _fresh()
	var open_ok: bool = true
	for i in TowerState.N:
		open_ok = open_ok and bool(S.unlocked[i]) == (TowerState.ring_of(i) == 1 or TowerState.ring_of(i) == 2)
	_check("PC-E1 new save: exactly rings 1-2 unlocked (7x7 small-cell grid)", open_ok and S.free_slots().size() == 40 and S.grid_n == 7)
	# FEEDBACK-1 (deliberate): the run grid is a Research unlock (V2 P3b: 7x7
	# -> 9x9 ... -> 21x21 small cells, Core centred); Core tracks never open rings.
	var S1 = TowerState.new()
	S1.setup(3, BaseMeta.default_save())
	S1.cash = 1.0e9
	var e2c: int = _at(-4, 0)   # ring 3: just outside the 7x7 start grid
	_check("PC-E1 run: per-cell unlock is gone", S1.unlock_plot(e2c).is_empty() and not bool(S1.unlocked[e2c]))
	var rev: Array = []
	for t in TowerState.TRACK_IDS:
		for k in 3:
			rev.append_array(S1.buy_track(String(t)))
	_check("FB1 run: tracks never open grid cells", not bool(S1.unlocked[e2c]) and _evts(rev, "ring_open").is_empty() and S1.track_total() == 15)
	var gsz: Array = []
	var gopen: Array = []
	for lv in 8:
		var gs: Dictionary = BaseMeta.default_save()
		gs["research"]["lvls"]["grid"] = lv
		var G = TowerState.new()
		G.setup(7, gs)
		gsz.append(G.grid_n)
		var n_open: int = 0
		var centred: bool = true
		for i in TowerState.N:
			if bool(G.unlocked[i]):
				n_open += 1
				centred = centred and G.in_grid(i)
		gopen.append(n_open)
	_check("V2 grid research 7..21 opens GxG-9 cells (the 3x3 Core never opens)", gsz == [7, 9, 11, 13, 15, 17, 19, 21] and gopen == [40, 72, 112, 160, 216, 280, 352, 432])
	_check("V2 grids are centred on the Core (7x7 rows 7..13, 21x21 the whole board)", TowerState.grid_lo(7) == 7 and TowerState.grid_lo(21) == 0 and TowerState.in_grid_n(TowerState.CORE_SLOT, 7) and TowerState.in_grid_n(0, 21) and not TowerState.in_grid_n(0, 19))
	var G2 = TowerState.new()
	G2.setup(7, BaseMeta.default_save(), 0, {"grid": 9})
	_check("FB1 opts.grid override (tests/tools)", G2.grid_n == 9 and bool(G2.unlocked[_at(-4, 0)]) and not bool(G2.unlocked[_at(-5, 0)]))
	var G3 = TowerState.new()
	G3.setup(7, BaseMeta.default_save(), 0, {"grid": 21})
	_check("FB1 view fits: spawn radius grows with the grid", float(G3.spawn_r()) > float(G2.spawn_r()) and float(G2.spawn_r()) > float(S1.spawn_r()))
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
		S.pending_upgrade = ""
		S.perk_offer.clear()
	return out


## PC-E5 spawns + telegraph. FEEDBACK-1 (deliberate): lanes are gone —
## enemies come from every direction from wave 1; the telegraph announces the
## wave's total / elites / boss instead of quadrants.
func _pc_spawn_stages() -> void:
	var runs: Array = []
	for rep in 2:
		var R = TowerState.new()
		var ev0: Array = R.setup(4321, BaseMeta.default_save())
		_godmode(R)
		runs.append({"S": R, "ev": _sim_waves(R, 26, ev0)})
	var evs: Array = runs[0]["ev"]
	var tele: Dictionary = {}
	var start_t: Dictionary = {}
	var lead_ok: bool = true
	var order_ok: bool = true
	var boss_ok: bool = false
	var schema_ok: bool = true
	for e in evs:
		var d: Dictionary = e
		match String(d["t"]):
			"wave_telegraph":
				tele[int(d["wave"])] = d
				schema_ok = schema_ok and not d.has("quadrants") and d.has("total") and d.has("boss")
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
				boss_ok = tele.has(bw) and bool((tele[bw] as Dictionary)["boss"])
	# Spawned bodies of wave 1 already come from every side of the Core.
	var S2 = TowerState.new()
	var e2: Array = S2.setup(99, BaseMeta.default_save())
	_godmode(S2)
	var sectors: Dictionary = {}
	var r_ok: bool = true
	var tot_ok: bool = true
	var seen: Dictionary = {}
	var last_tele: Dictionary = {}
	for e in e2:
		if String((e as Dictionary)["t"]) == "wave_telegraph":
			last_tele[int((e as Dictionary)["wave"])] = e
	var guard: int = 0
	while S2.wave <= 12 and guard < 100000:
		guard += 1
		var n0: int = S2.enemy_count()
		for e in S2.tick(0.05):
			var d3: Dictionary = e
			if String(d3["t"]) == "wave_telegraph":
				last_tele[int(d3["wave"])] = d3
		S2.draft.clear()
		S2.pending_place = ""
		S2.pending_upgrade = ""
		S2.perk_offer.clear()
		var l2: Array = S2.enemy_list() if S2.enemy_count() > n0 else []
		for k in range(n0, l2.size()):
			var en: Dictionary = l2[k]
			if String(en["kind"]) in ["mite", "courier"]:
				continue
			var off: Vector2 = (en["pos"] as Vector2) - TowerState.CENTER
			# V2 P3d: mass surges land on or just behind the ring (mass_spawn_depth)
			r_ok = r_ok and off.length() >= float(S2.spawn_r()) - 40.0 and off.length() <= float(S2.spawn_r()) + TuneRef.num("mass_spawn_depth", 140.0) + 40.0
			sectors[posmod(int(floor(rad_to_deg(off.angle()) / 90.0)), 4)] = true
		var lw: Dictionary = S2.last_wave_spawned
		if not lw.is_empty() and not seen.has(int(lw["wave"])):
			seen[int(lw["wave"])] = true
			tot_ok = tot_ok and int((last_tele[int(lw["wave"])] as Dictionary)["total"]) == int(lw["n"])
	_check("PC-E5 wave_telegraph precedes wave_start by pc_telegraph_s", order_ok and lead_ok and start_t.size() >= 25)
	_check("FB1 telegraph carries total/boss, no quadrants", schema_ok and tele.has(1) and tele.has(25))
	_check("FB1 telegraph total == actual spawns per wave", tot_ok and seen.size() >= 10)
	_check("FB1 no lanes: waves 1-12 spawn on all 4 sides, on / just behind the spawn ring", sectors.size() == 4 and r_ok)
	_check("PC-E5 boss wave is telegraphed as a boss wave", boss_ok)
	var a_t: Array = []
	var b_t: Array = []
	for e in runs[0]["ev"]:
		if String((e as Dictionary)["t"]) == "wave_telegraph":
			a_t.append([(e as Dictionary)["total"], (e as Dictionary)["elites"], (e as Dictionary)["boss"]])
	for e in runs[1]["ev"]:
		if String((e as Dictionary)["t"]) == "wave_telegraph":
			b_t.append([(e as Dictionary)["total"], (e as Dictionary)["elites"], (e as Dictionary)["boss"]])
	_check("PC-E5 same seed -> same telegraphs", a_t.size() >= 25 and JSON.stringify(a_t) == JSON.stringify(b_t))
	var S = _fresh()
	_check("FB1 lane focus API is gone", not S.has_method("set_focus") and not S.has_method("quad_count") and not ("focus_quad" in S) and not ("walls" in S))


## A run with every cell unlocked and nothing firing on its own.
func _open_run():
	var S = _fresh()
	for i in TowerState.N:
		S.unlocked[i] = i != TowerState.CORE_SLOT
	S.spawn_hold = true
	return S


## (r, c) in the legacy 7x7 coordinates (Core at (3,3)) -> V2 P3b board, ring
## preserving (see _r).
func _rc(r: int, c: int) -> int:
	return _lg(r - 3, c - 3)


## PC-E3 new buildings + synergies S8-S11.
func _pc_building_stages() -> void:
	var r2: int = _rc(1, 3)     # ring 2, north lane
	var r1: int = _rc(2, 3)     # ring 1, north
	var S = _open_run()
	S.pending_place = "railgun"
	_check("PC-E3 railgun rejected on ring 1", S.place(r1).is_empty() and S.id_at(r1) == "")
	# V2 P3b: the 2x2 Railgun needs its whole footprint on ring 3+ (>= 2 old cells out)
	_check("PC-E3 railgun rejected with a footprint cell on ring 2", S.place(_at(-4, -1)).is_empty() and S.id_at(_at(-4, -1)) == "")
	_check("PC-E3 railgun placed on ring 3+ (2x2)", not S.place(_at(-5, -1)).is_empty() and S.id_at(_at(-5, -1)) == "railgun" and S.owner_at(_at(-4, 0)) == _at(-5, -1))
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
	_adds(S, [on1, on2, off])
	var fev: Array = []
	S._fire(0.01, fev)
	_sync(S, [on1, on2, off])
	_check("PC-E3 railgun pierces the line, misses off-line", float(on1["hp"]) < 999.0 and float(on2["hp"]) < 999.0 and is_equal_approx(float(off["hp"]), 999.0))
	# V2 (deliberate): no air — the Flak / Flamer hits ground (no flyer prey bonus).
	S = _open_run()
	S.slots[r1] = {"id": "flak", "perm": 0, "run": 2}
	S.recompute()
	var fl: Dictionary = _weapon(S, "flak")
	_check("PC-E3 flak L2 dmg 8 x 1.35", is_equal_approx(float(fl["dmg"]), 8.0 * 1.35 * TowerState.bld_dmg()) and not fl.has("prey"))
	S.stats["weapons"] = [fl]
	var fpos: Vector2 = TowerState.slot_pos(r1) + Vector2(0, -120)
	var heavy: Dictionary = _enemy("hauler", fpos + Vector2(0, 20))
	_adds(S, [heavy])
	fev = []
	S._fire(0.01, fev)
	_sync(S, [heavy])
	_check("V2 flak hits ground", float(heavy["hp"]) < 999.0)
	var cw: Dictionary = _weapon(S, "flak").duplicate()
	cw["crit"] = 1.0
	S.stats["weapons"] = [cw]
	var ce: Dictionary = _enemy("drone", TowerState.slot_pos(r1) + Vector2(0, -100))
	S.set_enemies([ce])
	S.cooldowns[r1] = 0.0
	S._hcrit = 0
	fev = []
	S._fire(0.01, fev)
	_sync(S, [ce])
	# V2 P3d: the Flamer's cone lick is mass_flame_hit of its damage; crits count in the hits summary
	_check("PC-E3 crit hit doubles dmg + counts as a crit", S._hcrit == 1 and is_equal_approx(999.0 - float(ce["hp"]), 2.0 * float(cw["dmg"]) * TuneRef.num("mass_flame_hit", 0.15)))
	S = _open_run()
	S.packs = {"pk_crit": 2}
	S.recompute()
	_check("PC-E3 Precision packs: +8% crit each (global)", is_equal_approx(float(S.stats["crit"]), 0.16))
	# FEEDBACK-1 (deliberate): lane walls are gone. Every building has HP and
	# enemies attack buildings standing in their way before the Core; the
	# V2 P3a (deliberate, owner brief: "remove individual building health,
	# enemies always attack the Core"): structures have no HP. The crowd is a
	# fluid on a flow field: a building with open ground around it is flowed
	# AROUND; a ring that seals the path is SQUEEZED THROUGH at horde_squeeze
	# (0.35x) - never attacked. The FB1 HP / attack / destroy / repair gates are
	# retired (test ledger, P3a).
	S = _open_run()
	S.slots[r2] = {"id": "barricade", "perm": 0, "run": 2}
	S.slots[_rc(3, 1)] = {"id": "mine", "perm": 0, "run": 1}
	S.recompute()
	S.stats["weapons"] = []
	var wa: Dictionary = _enemy("drone", TowerState.slot_pos(r2) + Vector2(0, -60))
	S.set_enemies([wa])
	var aev: Array = []
	for k in 40:
		S._move_enemies(0.1, aev)
	_sync(S, [wa])
	_check("MASS_HORDE an open-ground building is flowed around: the body reaches the Core, nothing squeezes", (wa["pos"] as Vector2).distance_to(TowerState.CENTER) <= TowerState.STOP_R + 8.5 and int(S.en.world.call("Squeezing")) == 0 and S.id_at(r2) == "barricade")
	S = _open_run()
	var rn: int = _at(-2, 0)   # the Core's north neighbour
	for rc in TowerState.CORE_RING:   # V2 P3b: the 16 cells touching the 3x3 Core
		S.slots[int(rc)] = {"id": "barricade", "perm": 0, "run": 2}
	S.recompute()
	S.stats["weapons"] = []
	var wn: Dictionary = _enemy("drone", TowerState.slot_pos(rn) + Vector2(0, -60))
	S.set_enemies([wn])
	var bev: Array = []
	var wr := Rect2(TowerState.slot_pos(rn) - Vector2(TowerState.CELL, TowerState.CELL) * 0.5, Vector2(TowerState.CELL, TowerState.CELL)).grow(-4.0)
	var prev: Vector2 = wn["pos"]
	var in_d: float = 0.0
	var in_t: float = 0.0
	var free_d: float = 0.0
	var reached: bool = false
	for k in 200:
		S._move_enemies(0.05, bev)
		_sync(S, [wn])
		var p: Vector2 = wn["pos"]
		if wr.has_point(p) and wr.has_point(prev):
			in_d += p.distance_to(prev)
			in_t += 0.05
		elif k >= 4 and k < 8:
			free_d += p.distance_to(prev)
		prev = p
		if p.distance_to(TowerState.CENTER) <= TowerState.STOP_R + 8.5:
			reached = true
			break
	var spd0: float = float(wn["spd"])
	var bad_ev: int = 0
	for e in bev:
		if String((e as Dictionary)["t"]) in ["bld_hit", "building_destroyed", "bld_repair"]:
			bad_ev += 1
	_check("V2 P3a sealed ring: the body squeezes through the Wall at <= 0.4x speed (%.1f vs %.1f px/s free) and reaches the Core; no structure event" % [in_d / maxf(0.01, in_t), free_d / 0.2], reached and in_t > 0.5 and in_d / in_t <= 0.4 * spd0 and free_d / 0.2 > 0.8 * spd0 and bad_ev == 0 and S.id_at(rn) == "barricade")
	var hit_ev: Array = []
	for k in 30:
		S._move_enemies(0.05, hit_ev)
	_check("V2 P3a: once through, its attacks land on the Core", _evts(hit_ev, "core_hit").size() >= 1)
	# Outer rings reach further (+8% per old 52 px ring past 1 = +4% per small ring).
	S = _open_run()
	S.slots[r1] = {"id": "gun", "perm": 0, "run": 1}
	S.slots[_at(-6, 0)] = {"id": "gun", "perm": 0, "run": 1}   # ring 5 = 156 px out, the old ring 3
	S.recompute()
	var rg1: float = 0.0
	var rg3: float = 0.0
	for w in S.stats["weapons"]:
		if String(w["kind"]) == "gun":
			if int(w["slot"]) == r1:
				rg1 = float(w["range"])
			else:
				rg3 = float(w["range"])
	_check("PC-E3 ring range bonus +8% per 52 px ring (+4% per small ring)", rg1 > 0.0 and is_equal_approx(rg3, rg1 * 1.16))
	var ids_ok: bool = true
	for id in PickDB.BUILDINGS + PickDB.HUTS:
		ids_ok = ids_ok and String(BuildingDB.get_def(String(id)).get("name", "")) != "" and String(PickDB.get_def(String(id)).get("desc", "")) != ""
	# V2 (deliberate): no air (Drone Nest gone), no crates (Appraiser Insight gone).
	_check("REDESIGN 17 buildings + 2 huts named in BuildingDB + PickDB", ids_ok and PickDB.BUILDINGS.size() == 17 and PickDB.HUTS.size() == 2 and PickDB.PACKS.size() == 10 and PickDB.SPECIALS.size() == 6 and PickDB.INSIGHT.size() == 6)


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
	S.add_enemy(_enemy("drone", TowerState.CENTER + Vector2(0, -300)))
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
	S.set_enemies([])
	S.slots[_rc(1, 3)] = {"id": "railgun", "perm": 0, "run": 1}
	S.recompute()
	_check("PC-E4 railgun cannot move inside ring 2", S.move_building(_rc(1, 3), _rc(3, 2)).is_empty() and S.move_building(_rc(1, 3), b).is_empty())
	S.pending_place = "railgun"
	var cev: Array = S.cancel_place()
	_check("cancel_place drops a pending card", S.pending_place == "" and cev.size() == 1 and String(cev[0]["t"]) == "place_cancelled" and S.cancel_place().is_empty())
	_check("PC-E4 core / locked cells refused", S.move_building(c, TowerState.CORE_SLOT).is_empty())


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
	_check("PC-E6 Haste: enemy speed +25%", is_equal_approx(float(S.enemy_list()[0]["spd"]), float(EnemyDB.mass_def("drone")["spd"]) * 1.25))
	S = _mod_run(["swarm"])
	S.spawn_hold = true
	S._spawn("drone", [])
	S0.spawn_hold = true
	S0._spawn("drone", [])
	var p0: int = int(S0._build_plan(3, 0.0)["entries"].size())
	var p1: int = int(S._build_plan(3, 0.0)["entries"].size())
	_check("PC-E6 Swarm: -30% HP each, +60% count", is_equal_approx(float(_last(S)["hp"]), float(_last(S0)["hp"]) * 0.7) and float(p1) >= 1.5 * float(p0) and float(p1) <= 1.7 * float(p0))
	S = _mod_run(["ironclad"])
	var e1: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 300))
	var e2: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 300))
	S._hit(S.add_enemy(e1), 10.0, [])
	S._hit(S.add_enemy(e2), 10.0, [], true)
	_sync(S, [e1, e2])
	_check("PC-E6 Ironclad: non-crit -20%, crit full", is_equal_approx(999.0 - float(e1["hp"]), 8.0) and is_equal_approx(999.0 - float(e2["hp"]), 10.0))
	var lab: Dictionary = BaseMeta.default_save()
	lab["research"]["lvls"]["startcash"] = 2
	lab["research"]["lvls"]["dmg"] = 4
	var SL = _mod_run([], lab)
	S = _mod_run(["poverty"], lab)
	_check("PC-E6 Austerity: start cash 0", is_equal_approx(SL.cash, 30.0) and is_equal_approx(S.cash, 0.0))
	S.spawn_hold = true
	S.add_enemy(_enemy("drone", TowerState.CENTER + Vector2(0, 300), 0.0))
	S._reap([])
	_check("PC-E6 Austerity: kill cash -30%", is_equal_approx(S.cash, 1.0 * 0.7))
	# FEEDBACK-1: every wave comes from all sides now; Encircled = +25% enemies.
	S = _mod_run(["allsides"])
	_check("PC-E6 Encircled: +25% enemy count", is_equal_approx(S.count_mult, 1.25))
	S = _mod_run(["noperks"])
	S.spawn_hold = true
	S.wave = 4
	S.wave_t = S.wave_time - 0.001
	var pev: Array = S.tick(0.05)
	_check("PC-E6 Purist suppresses perk_offer", S.wave == 5 and _evts(pev, "perk_offer").is_empty() and S.perk_offer.is_empty() and S.perk_pending == 0)
	S = _mod_run(["elitist"])
	# V2 P3d: mass waves carry elites from wave 5 on any tier; Elite Guard triples them.
	var el: int = int(S._build_mass_plan(10, 0.0)["elites"])
	var el0: int = int(S0._build_mass_plan(10, 0.0)["elites"])
	_check("PC-E6 Elite Guard: x3 elites in a wave (%d vs %d)" % [el, el0], el0 > 0 and el == 3 * el0)
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
	var mev: Array = E.tick(0.05)
	var mo: Array = _evts(mev, "mutation_offer")
	_check("PC-E7 mutation offer at wave 25 (3 distinct)", E.wave == 25 and mo.size() == 1 and E.mutation_offer.size() == 3 and E.mutation_offer[0] != E.mutation_offer[1] and E.mutation_offer[1] != E.mutation_offer[2] and is_equal_approx(E.time_scale(), 1.0))   # FB1: sim stays live
	E.mutation_offer = ["m_vigor", "m_rush", "m_horde"]
	var cm0: float = E.run_coin_mult()
	E._spawn("drone", [])
	var vh0: float = float(_last(E)["hp"])
	var tk: Array = E.choose_mutation(0)
	E._spawn("drone", [])
	var vh: float = float(_last(E)["hp"]) / vh0
	_check("PC-E7 mutation pays +15% coins and buffs enemies (+20% HP)", _evts(tk, "mutation_taken").size() == 1 and is_equal_approx(E.run_coin_mult(), cm0 * 1.15) and is_equal_approx(vh, 1.2) and E.mutation_offer.is_empty())
	N0.mode = "normal"
	N0.wave = 49
	N0.wave_t = N0.wave_time - 0.001
	N0.spawn_hold = true
	_check("PC-E7 normal mode never offers mutations", _evts(N0.tick(0.05), "mutation_offer").is_empty())
	E.wave = 120
	_check("PC-E7 soft HP exponent past wave 100", is_equal_approx(E.scale(), pow(E.hp_growth, 99.0) * pow(1.12, 20.0)))
	E.wave = 130
	E.wave_t = E.wave_time - 0.001
	E.mutation_offer.clear()
	E.tick(0.05)
	_check("PC-E7 no wave cap", E.wave == 131 and not E.over)
	var bw_before: Dictionary = (es["best_wave_by_tier"] as Dictionary).duplicate()
	E.hp = -1.0
	E.stats["regen"] = 0.0
	var dev: Array = E.tick(0.05)
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
	Labs.start(sp, "dmg", 0)
	_check("PC-E8 coins_spent fed by meta spends (research)", int(sp["stats"]["coins_spent"]) == Labs.cost("dmg", 0))
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
	# V2 (deliberate): a pre-v5 save (here a mobile v2) is not migrated — it
	# normalizes to fresh v5 defaults (hard reset).
	var v2: Dictionary = {
		"version": 2, "coins": 4321, "gems": 12, "core": {"dmg": 3, "hp": 2, "regen": 1},
		"slots": {"6": {"id": "armory", "lvl": 4}, "7": {"id": "gun", "lvl": 3}, "0": {"id": "mine", "lvl": 2}, "24": {"id": "vault", "lvl": 1}},
		"unlocked": [0, 4, 24], "runs": 9, "best_wave": 44, "tier": 2, "best_wave_by_tier": {"1": 44, "2": 3},
		"target_modes": {"7": "first"}, "stats": {"kills": 999, "bosses": 4},
		"labs": {"lvls": {"dmg": 3, "coin": 1}, "slots": 2, "running": []},
	}
	var m: Dictionary = BaseMeta.normalize(v2)
	_check("PC-E9 pre-v5 save -> fresh v5 (hard reset)", int(m["version"]) == 5 and int(m["coins"]) == 0 and int(m["runs"]) == 0 and bool(m.get("reset_v2", false)) and not m.has("slots") and not m.has("gems"))
	_check("PC-E9 v5 blocks filled", (m["history"] as Array).is_empty() and int(m["endless"]["best"]) == 0 and (m["stats"] as Dictionary).has("kills_by_kind"))
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(m)))
	_check("PC-E9 v5 JSON round-trip equality", JSON.stringify(rt) == JSON.stringify(m))
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
	_check("PC-E9 legacy save.json imports into slot 1 as a fresh v5 (reset)", int(imp["version"]) == 5 and int(imp["coins"]) == 0 and bool(imp.get("reset_v2", false)) and MetaSave.read_slot(2).get("coins", 0) == 222)
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
	# REDESIGN (deliberate): + parts / reforges / specials stats -> 8.
	_check("PC-E11 stats mirrored (8 stats + store)", SteamService.mock_ops("set_stat_int").size() == 8 and SteamService.mock_ops("store_stats").size() == 1)

	# --- Achievements (PC-E10) -----------------------------------------------
	# REDESIGN (ENGINE-META, deliberate): +10 achievements (AC-23) -> 34.
	var stx: Dictionary = BaseMeta.default_save()
	Stats.on_event(stx, {"t": "game_over", "wave": 20, "couriers": 1, "specials_cast": 7, "duration_s": 1.0})
	_check("ACH hooks: game_over feeds couriers + specials_cast stats", int(stx["stats"]["couriers"]) == 1 and int(stx["stats"]["specials_cast"]) == 7)
	# MASS_HORDE §D6 (deliberate content change): 34 -> 39 achievements (Exterminator
	# II/III ladder, The Tide, Wall of Flesh, Parting the Sea); ids still unique.
	var ach_u: Dictionary = {}
	for aid in AchievementDB.ids():
		ach_u[aid] = true
	# V2 (deliberate): 39 -> 33 (ring/base, card, part, set and 4-Core achievements removed).
	_check("PC-E10 33 achievements, unique ids", AchievementDB.LIST.size() == 33 and ach_u.size() == 33)
	var labs_max: Dictionary = BaseMeta.default_save()["research"]
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
		# MASS_HORDE §D6 additions (event / save driven).
		"ACH_KILLS_1M": [{"stats": {"kills": 1000000}}, [{"t": "meta"}], -1.0],
		"ACH_KILLS_10M": [{"stats": {"kills": 10000000}}, [{"t": "meta"}], -1.0],
		"ACH_TIDE": [{}, [{"t": "tide", "wave": 45, "peak": 10000}], -1.0],
		"ACH_WALL_FLESH": [{}, [{"t": "wall_of_flesh", "slot": 3, "n": 2000}], -1.0],
		"ACH_PART_SEA": [{}, [{"t": "part_sea", "n": 500}], -1.0],
		"ACH_ALL_SYNERGY": [{}, [{"t": "synergies", "n": AchievementDB.SYNERGY_TARGET}], -1.0],
		"ACH_ECO_ONLY": [{}, [{"t": "game_over", "wave": 30, "build": ["", "mine", "bounty"]}], -1.0],
		"ACH_NO_ECO": [{}, [{"t": "game_over", "wave": 60, "build": ["gun", "", "armory"]}], -1.0],
		"ACH_LABS_MAX": [{"research": {"lvls": {"speed": 3}, "running": []}}, [{"t": "meta"}], -1.0],
		"ACH_FIRST_REFORGE": [{"reforge": {"count": 1, "nodes": {}}}, [{"t": "meta"}], -1.0],
		"ACH_REFORGE_5": [{"reforge": {"count": 5, "nodes": {}}}, [{"t": "meta"}], -1.0],
		"ACH_GEM_MINE": [{"outpost": {"buildings": {"1": {"id": "gemmine", "built": true}}, "plots": []}}, [{"t": "meta"}], -1.0],
		"ACH_COURIER": [{"stats": {"couriers": 1}}, [{"t": "meta"}], -1.0],
		# V2 (deliberate): Frontier Settled = every Outpost plot (the Factory's land chunks are gone).
		"ACH_OUTPOST_FULL": [{"outpost": {"buildings": {}, "plots": range(OutpostDB.PLOTS.size())}}, [{"t": "meta"}], -1.0],
		"ACH_INSIGHT_10": [{"insight": {"in_dmg": 6, "in_hp": 4}}, [{"t": "meta"}], -1.0],
		"ACH_SPECIAL_100": [{"stats": {"specials_cast": 100}}, [{"t": "meta"}], -1.0],
		"ACH_MOD_3": [{}, [{"t": "run_start", "modifiers": ["swarm", "haste", "noperks"]}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 51}], -1.0],
		"ACH_GLASS_50": [{}, [{"t": "run_start", "modifiers": ["glass"]}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 50}], -1.0],
		"ACH_ENCIRCLED_100": [{}, [{"t": "run_start", "modifiers": ["allsides"]}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 100}], -1.0],
		"ACH_NO_DAMAGE_10": [{}, [{"t": "run_start"}, {"t": "wave", "wave": 5}, {"t": "wave", "wave": 11}], -1.0],
		"ACH_SPEEDRUN": [{}, [{"t": "run_start"}, {"t": "core_hit", "dmg": 1.0}, {"t": "wave", "wave": 40}], 590.0],
		"ACH_STREAK_7": [{"streak": {"day_idx": 7, "last_day": 3, "loops": 0}}, [{"t": "meta"}], -1.0],
		"ACH_MISSIONS_50": [{}, [], -1.0],
		"ACH_ENDLESS": [{"best_wave": 50, "best_wave_by_tier": {"1": 50}}, [{"t": "meta"}], -1.0],
	}
	var m50: Array = []
	for k in 50:
		m50.append({"t": "mission_claimed", "idx": 0, "gems": 1})
	cases["ACH_MISSIONS_50"][1] = m50
	_check("PC-E10 every achievement has a synthetic case", cases.size() == 33 and cases.keys().all(func(k: Variant) -> bool: return AchievementDB.ids().has(String(k))))
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
	_check("PC-E10 achievements survive normalize", BaseMeta.normalize({"version": 5, "achievements": {"unlocked": {"ACH_FIRST_RUN": 5}, "missions_claimed": 3}})["achievements"] == {"unlocked": {"ACH_FIRST_RUN": 5}, "missions_claimed": 3})
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


## V2: one Core. The other three pre-V2 Core attacks (Slag / Beam / Pulse)
## become Weapon frames in P4; until then these fixtures swap the run's Core
## sheet so their attack code stays covered.
const ATTACK_SHEETS: Dictionary = {
	"foundry": {"name": "Foundry", "dmg": 5.0, "rate": 1.0, "range": 3.5, "hp": 100.0, "regen": 0.8, "armor": 1.0, "cash": 4.0, "irate": 0.05, "icap": 150.0,
		"attack": "slag", "splash": 1.0, "slow": 0.2, "slow_t": 2.0, "attack_name": "Slag Spitter", "attack_desc": ""},
	"lance": {"name": "Lance", "dmg": 28.0, "rate": 0.5, "range": 5.5, "hp": 90.0, "regen": 0.6, "armor": 1.0, "cash": 1.5, "irate": 0.01, "icap": 30.0,
		"attack": "beam", "ramp": 0.15, "ramp_max": 1.5, "attack_name": "Charging Beam", "attack_desc": ""},
	"tempest": {"name": "Tempest", "dmg": 6.0, "rate": 0.8, "range": 3.0, "hp": 140.0, "regen": 1.2, "armor": 3.0, "cash": 1.8, "irate": 0.02, "icap": 40.0,
		"attack": "pulse", "knock": 0.3, "chain_every": 5, "chain_frac": 0.4, "chain_n": 3, "attack_name": "Pulse Ring", "attack_desc": ""},
}


func _core_run(core: String, lvl: int = 1, seed_value: int = 1234):
	var sv: Dictionary = BaseMeta.default_save()
	sv["core"] = {"lvl": lvl}
	var S = TowerState.new()
	S.setup(seed_value, BaseMeta.normalize(sv))
	if ATTACK_SHEETS.has(core):
		S.core_def = ATTACK_SHEETS[core]
		S.recompute()
		S.hp = float(S.stats["max_hp"])
	return S


## V2 Core: one sheet (the old Bastion numbers), coin-only levels, save block.
func _core_stages() -> void:
	_check("CORE one Core (V2): id core, Bastion sheet", CoreDB.ID == "core" and CoreDB.has("core") and not CoreDB.has("bastion") and float(CoreDB.get_def()["hp"]) == 120.0 and String(CoreDB.get_def()["attack"]) == "cannon")
	var sv: Dictionary = BaseMeta.default_save()
	_check("CORE default save: L1", Cores.level(sv) == 1 and Cores.active(sv) == "core")
	_check("CORE level cost round(250*1.18^(L-1)), coins only (Core Cores are gone)", int(Cores.level_cost(1)["coins"]) == 250 and int(Cores.level_cost(2)["coins"]) == 295 and not Cores.level_cost(15).has("core_cores") and int(Cores.level_cost(10)["coins"]) == int(round(250.0 * pow(1.18, 9.0))))
	var snap: String = JSON.stringify(sv)
	_check("CORE try_level refuses when broke (no mutation)", Cores.try_level(sv).is_empty() and JSON.stringify(sv) == snap)
	sv["coins"] = 1000
	var ev: Array = Cores.try_level(sv)
	_check("CORE try_level spends coins, +1 level, event", ev.size() == 1 and Cores.level(sv) == 2 and int(sv["coins"]) == 750 and String(ev[0]["t"]) == "core_level")
	sv["coins"] = 1 << 40
	for k in 20:
		Cores.try_level(sv)
	_check("CORE levels past 15 stay coin-only", Cores.level(sv) == 22)
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(sv)))
	_check("CORE block survives JSON + normalize", Cores.level(rt) == 22)
	var bad: Dictionary = BaseMeta.normalize({"version": 5, "core": {"lvl": 999}})
	_check("CORE normalize clamps the level", Cores.level(bad) == CoreDB.MAX_LVL)
	sv["reforge"] = {"nodes": {"core_ceiling": 1}}
	_check("CORE max 60, 75 with core_ceiling", Cores.max_level(BaseMeta.default_save()) == 60 and Cores.max_level(sv) == 75)
	# Core level scales its sheet (dmg x1.06, HP x1.05, regen x1.04, cash x1.04).
	var A = _core_run("core", 1)
	var B = _core_run("core", 11)
	var aw: Dictionary = _weapon(A, "core")
	var bw: Dictionary = _weapon(B, "core")
	_check("CORE L11: dmg x1.06^10, HP x1.05^10, regen x1.04^10, cash x1.04^10, rate/range flat", is_equal_approx(float(bw["dmg"]) / float(aw["dmg"]), pow(1.06, 10.0)) and is_equal_approx(float(B.stats["max_hp"]), 120.0 * pow(1.05, 10.0)) and is_equal_approx(float(B.stats["regen"]), pow(1.04, 10.0)) and is_equal_approx(float(B.stats["cash_ps"]), 2.0 * pow(1.04, 10.0)) and is_equal_approx(float(bw["rate"]), float(aw["rate"])) and is_equal_approx(float(bw["range"]), float(aw["range"])))
	for id in ["core"] + ATTACK_SHEETS.keys():
		var C = _core_run(String(id))
		var d: Dictionary = C.core_def
		var cw: Dictionary = _weapon(C, "core")
		_check("CORE %s sheet: dmg/rate/range/HP/cash/attack" % id, is_equal_approx(float(cw["dmg"]), float(d["dmg"])) and is_equal_approx(float(cw["rate"]), float(d["rate"])) and is_equal_approx(float(cw["range"]), float(d["range"]) * TowerState.cpx()) and is_equal_approx(float(C.stats["max_hp"]), float(d["hp"])) and is_equal_approx(float(C.stats["cash_ps"]), float(d["cash"])) and String(cw["attack"]) == String(d["attack"]))


## §2.2 cash tracks: costs, effects, caps, head_start, kill-cash index.
func _track_stages() -> void:
	var S = _fresh()
	_check("TRACK 5 tracks start at 0 (head_start 0)", S.tracks == {"dmg": 0, "rate": 0, "range": 0, "eco": 0, "armor": 0})
	# FEEDBACK-1 (deliberate): few, big, expensive levels with a drawback each.
	_check("TRACK base costs 120/140/180/100/120", S.track_cost("dmg") == 120 and S.track_cost("rate") == 140 and S.track_cost("range") == 180 and S.track_cost("eco") == 100 and S.track_cost("armor") == 120)
	_check("FB1 every track names its drawback, caps <= 8", TowerState.TRACK_IDS.all(func(t: Variant) -> bool: return String((TowerState.TRACKS[t] as Dictionary).get("minus", "")) != "" and TowerState.track_cap(String(t)) <= 8))
	S.cash = 1.0e9
	for t in ["rate", "range", "eco", "armor"]:
		S.buy_track(String(t))
	_check("TRACK cost grows by its growth", S.track_cost("rate") == int(round(140.0 * float(TowerState.TRACKS["rate"]["growth"]))) and S.track_cost("eco") == int(round(100.0 * float(TowerState.TRACKS["eco"]["growth"]))) and S.track_cost("armor") == int(round(120.0 * float(TowerState.TRACKS["armor"]["growth"]))))
	var cw: Dictionary = _weapon(S, "core")
	_check("TRACK Rate +30% (Range -8% rate), Range +0.75 cell", is_equal_approx(float(cw["rate"]), 1.25 * 1.30 * 0.92) and is_equal_approx(float(cw["range"]), 4.75 * TowerState.cpx()))
	_check("TRACK Eco +3 cash/s, interest cap +40", is_equal_approx(float(S.stats["cash_ps"] ), 5.0) and is_equal_approx(float(S.stats["interest_cap"]), 90.0))
	_check("TRACK Armor +30% HP (Eco -8% HP), +1 regen, +2 armor", is_equal_approx(float(S.stats["max_hp"]), 120.0 * 1.3 * 0.92) and is_equal_approx(float(S.stats["regen"]), 2.0) and is_equal_approx(float(S.stats["armor"]), 4.0))
	var S0 = _fresh()
	_check("FB1 Rate and Armor cost Core dmg (-9% each)", is_equal_approx(float(cw["dmg"]), float(_weapon(S0, "core")["dmg"]) * 0.91 * 0.91))
	S.tracks["range"] = 6
	S.recompute()
	_check("TRACK capped (range 6) -> cost -1, buy refused", S.track_cost("range") == -1 and S.buy_track("range").is_empty())
	S.packs = {"pk_logistics": 2}
	S.recompute()
	_check("TRACK Logistics packs -12% cost each", S.track_cost("dmg") == int(round(120.0 * 0.88 * 0.88)))
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
	S.add_enemy(_enemy("hauler", TowerState.CENTER + Vector2(0, 300), 0.0))
	S._reap([])
	_check("TRACK kill cash 3 x 1.10^10 (T1)", is_equal_approx(S.cash, 3.0 * pow(1.1, 10.0)))
	var t3: Dictionary = BaseMeta.default_save()
	t3["best_wave_by_tier"] = {"1": 40, "2": 50}
	BaseMeta.select_tier(t3, 3)
	var S3 = TowerState.new()
	S3.setup(1, t3)
	S3.spawn_hold = true
	S3.cash = 0.0
	S3.add_enemy(_enemy("drone", TowerState.CENTER + Vector2(0, 300), 0.0))
	S3._reap([])
	_check("TRACK kill cash x (1 + 0.5(t-1)) at T3", is_equal_approx(S3.cash, 2.0))


## §2.1 Core attack behaviours (events only; the view replays them).
func _core_attack_stages() -> void:
	# Bastion: Auto Cannon at the nearest, 0.5-cell splash at 40%.
	var S = _core_run("core")
	S.spawn_hold = true
	var a: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, -230))
	var b: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(15, -235))
	var c: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 280))
	a["eid"] = 1
	b["eid"] = 2
	c["eid"] = 3
	S.set_enemies([a, b, c])
	var ev: Array = []
	S._fire(0.01, ev)
	var ca: Array = _evts(ev, "core_attack")
	_sync(S, [a, b, c])
	_check("ATK cannon: core_attack event, nearest + 40% splash", ca.size() == 1 and String(ca[0]["kind"]) == "cannon" and is_equal_approx(999.0 - float(a["hp"]), 10.0) and is_equal_approx(999.0 - float(b["hp"]), 4.0) and is_equal_approx(float(c["hp"]), 999.0) and (ca[0]["targets"] as Array) == [1, 2])
	var S20 = _core_run("core", 20)
	S20.spawn_hold = true
	var e1: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, -230))
	var e2: Dictionary = _enemy("hauler", TowerState.CENTER + Vector2(0, 280))
	S20.set_enemies([e1, e2])
	S20._fire(0.01, [])
	_sync(S20, [e1, e2])
	_check("ATK Bastion L20 double barrel hits 2 targets", float(e1["hp"]) < 999.0 and float(e2["hp"]) < 999.0)
	# Foundry: Slag splash 1 cell + 2 s slow -20%.
	S = _core_run("foundry")
	S.spawn_hold = true
	a = _enemy("hauler", TowerState.CENTER + Vector2(0, -230))
	b = _enemy("hauler", TowerState.CENTER + Vector2(40, -240))
	S.set_enemies([a, b])
	ev = []
	S._fire(0.01, ev)
	_sync(S, [a, b])
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
	S.set_enemies([weak, strong])
	ev = S.tick(0.05)
	_sync(S, [weak, strong])
	_check("ATK beam locks the highest-HP enemy", float(weak["hp"]) == 100.0 and float(strong["hp"]) < 5000.0 and S.beam_eid == 11)
	var hp_a: float = float(strong["hp"])
	for k in 40:
		S.tick(0.05)   # 2 s held -> next shot +30%
	var first_dmg: float = 5000.0 - hp_a
	_sync(S, [weak, strong])
	var hp_b: float = float(strong["hp"])
	_check("ATK beam ramp builds while held (dmg > base)", S.beam_t > 1.5 and hp_b < hp_a - first_dmg * 1.2)
	strong["hp"] = 0.0
	_push(S, strong)
	S._reap([])
	S.tick(0.05)
	var reset_ok: bool = S.beam_eid == -1 and S.beam_t == 0.0
	for k in 45:
		S.tick(0.05)
	_check("ATK beam resets on a switch (ramp 0, then locks the next)", reset_ok and S.beam_eid == 10 and S.beam_t < 2.0)
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
	S.set_enemies(inside + [outer])
	ev = []
	S._fire(0.01, ev)
	_sync(S, inside + [outer])
	var all_hit: bool = true
	for en in inside:
		# HORDE Phase 4 (deliberate): the pulse knock is an outward impulse
		# (velocity), not a 12 px teleport; displacement happens in the move pass.
		var ks: int = S.en.slot_of(int(en["eid"]))
		all_hit = all_hit and is_equal_approx(999.0 - float(en["hp"]), 6.0) and ks >= 0 and S.en.vel[ks].dot((S.en.pos[ks] - TowerState.CENTER)) > 0.0
	_check("ATK pulse: every enemy in range once + knockback; outer untouched", all_hit and is_equal_approx(float(outer["hp"]), 999.0) and (_evts(ev, "core_attack")[0]["targets"] as Array).size() == 3)
	S.pulse_n = 4
	S.cooldowns[TowerState.CORE_SLOT] = 0.0
	for en in inside:
		en["pos"] = TowerState.CENTER + ((en["pos"] as Vector2) - TowerState.CENTER).normalized() * 205.0
		_push(S, en)
	S._fire(0.01, [])
	_sync(S, [outer])
	_check("ATK Static: 5th pulse chains 40% beyond range", is_equal_approx(999.0 - float(outer["hp"]), 6.0 * 0.4))
	# Overkill carry: surplus single-target damage rolls to the next enemy.
	S = _core_run("core")
	S.spawn_hold = true
	var k1: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, -230), 3.0)
	var k2: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(260, 0), 50.0)
	S.set_enemies([k1, k2])
	S._fire(0.01, [])
	_sync(S, [k1, k2])
	_check("ATK overkill carry: 10 dmg kills a 3-HP drone, 60% of the 7 left rolls on", float(k1["hp"]) <= 0.0 and is_equal_approx(50.0 - float(k2["hp"]), 7.0 * 0.6))
	# Pulse with nothing in range stays ready (no wasted cooldown).
	S = _core_run("tempest")
	S.spawn_hold = true
	S.set_enemies([_enemy("hauler", TowerState.CENTER + Vector2(0, 400))])
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
	ctx3["owned"] = {"gun": 5, "mortar": 2, "mine": 5, "vault": 2}
	ctx3["copies"] = {"gun": 5, "mortar": 1, "mine": 1, "vault": 1}
	# FEEDBACK-1: weapon duplicates are new buildings (up to max copies);
	# non-weapon duplicates are upgrades applied onto the building.
	_check("DRAFT owned L5 building never offered; owned L2 -> plus 2->3", Draft.card_for("gun", ctx3).is_empty() and Draft.card_for("mine", ctx3).is_empty() and String(Draft.card_for("vault", ctx3)["kind"]) == "plus" and int(Draft.card_for("vault", ctx3)["to"]) == 3)
	_check("FB1 weapon duplicate with a free cell -> new building (dup)", String(Draft.card_for("mortar", ctx3)["kind"]) == "new" and bool(Draft.card_for("mortar", ctx3)["dup"]))
	ctx3["free"] = false
	_check("FB1 weapon duplicate without a free cell -> plus", String(Draft.card_for("mortar", ctx3)["kind"]) == "plus" and int(Draft.card_for("mortar", ctx3)["to"]) == 3)
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
		var ev: Array = S.tick(0.05)
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
	S._spawn("drone", [])
	var gh0: float = float(_last(S)["hp"])
	S.draft = [Draft.card_for("pk_gambit", S._draft_ctx(""))]
	S.choose_card(0)
	S._spawn("drone", [])
	_check("DRAFT Gambit +40% dmg, enemies +15% HP", is_equal_approx(float(_weapon(S, "core")["dmg"]), dmg0 * 1.12 * 1.4) and is_equal_approx(float(_last(S)["hp"]), gh0 * 1.15))
	S.packs = {"pk_core": 1, "pk_overclock": 1, "pk_fort": 1, "pk_optics": 1}
	S.recompute()
	var cw: Dictionary = _weapon(S, "core")
	_check("DRAFT Core Surge +15% dmg +5% rate; Overclock +8% rate -5% HP; Fortify +20% HP +1 armor; Optics +0.5 range", is_equal_approx(float(cw["dmg"]), dmg0 * 1.15) and is_equal_approx(float(cw["rate"]), 1.25 * 1.05 * 1.08) and is_equal_approx(float(S.stats["max_hp"]), 120.0 * 1.2 * 0.95) and is_equal_approx(float(S.stats["armor"]), 3.0) and is_equal_approx(float(cw["range"]), 4.5 * TowerState.cpx()))
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
	S.set_enemies([el])
	var r: Dictionary = S.cast_special(0)
	_sync(S, [el])
	_check("SPEC EMP: ok + special_cast, -50% speed 4 s, shields stripped", String(r["result"]) == "ok" and _evts(r["ev"], "special_cast").size() == 1 and is_equal_approx(float(el["slow_m"]), 0.5) and is_equal_approx(float(el["slow_t"]), 4.0) and int(el["shield"]) == 0)
	_check("SPEC recast on cooldown -> cooldown", String(S.cast_special(0)["result"]) == "cooldown")
	S.set_speed(2.0)
	S.set_enemies([])
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
	S.set_enemies([t1, tfar])
	S.stats["weapons"].back()["range"] = 1.0
	r = S.cast_special(0, TowerState.CENTER + Vector2(0, -320))
	var dmg_core: float = float(_weapon(S, "core")["dmg"])
	_sync(S, [t1, tfar])
	_check("SPEC Orbital queues a strike (no instant dmg)", String(r["result"]) == "ok" and float(t1["hp"]) == 1.0e6 and S.orbitals.size() == 1)
	var oev: Array = []
	for k in 9:
		oev.append_array(S.tick(0.1))
	_sync(S, [t1, tfar])
	_check("SPEC Orbital lands after 0.8 s: 25x Core dmg in radius only", is_equal_approx(1.0e6 - float(t1["hp"]), 25.0 * dmg_core) and is_equal_approx(float(tfar["hp"]), 1.0e6) and _evts(oev, "orbital_hit").size() == 1)
	S = _fresh()
	S.spawn_hold = true
	S.specials = [{"id": "sp_orbital", "copies": 1, "cd": 0.0, "charges": 1}]
	var cl: Array = []
	for k in 4:
		cl.append(_enemy("drone", TowerState.CENTER + Vector2(10.0 * float(k), 300)))
	S.set_enemies(cl + [_enemy("drone", TowerState.CENTER + Vector2(0, -300))])
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
	S.set_enemies([_enemy("drone", TowerState.CENTER + Vector2(0, 300), 0.0)])
	S._reap([])
	_check("SPEC Cash Magnet: x2 kill cash", is_equal_approx(S.cash, 2.0))
	var fz: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, 400))
	S.set_enemies([fz])
	S.cast_special(3)
	var p0: Vector2 = fz["pos"]
	S._move_enemies(0.5, [])
	_sync(S, [fz])
	_check("SPEC Time Warp freezes enemies 3 s", (fz["pos"] as Vector2) == p0 and is_equal_approx(float(S.buffs["warp_t"]), 3.0))


## §2.5 Troops: spawn per hut level, roam out to their post, fight, die,
## respawn, retreat, taunt; deterministic.
func _troop_stages() -> void:
	_check("TROOP count +1 at L3 and L5", Troops.count_for("hut_infantry", 1) == 3 and Troops.count_for("hut_infantry", 3) == 4 and Troops.count_for("hut_infantry", 5) == 5 and Troops.count_for("hut_sapper", 1) == 2 and not Troops.DEFS.has("hut_drone"))
	var st: Dictionary = Troops.troop_stats("hut_infantry", 2, {"dmg_mult": 2.0, "hp_mult": 1.0, "respawn_minus": 2.0, "cell_px": 78.0})
	_check("TROOP stats: +25% HP/dmg per hut level, respawn - Drill Sergeant", is_equal_approx(float(st["max_hp"]), 40.0 * 1.25) and is_equal_approx(float(st["dmg"]), 5.0 * 1.25 * 2.0) and is_equal_approx(float(st["respawn"]), 6.0) and is_equal_approx(float(st["range"]), 2.0 * 78.0))
	var S = _open_run()
	S.slots[_rc(2, 3)] = {"id": "hut_infantry", "perm": 0, "run": 1}
	S.recompute()
	var sev: Array = []
	S._drain_troop_events(sev)
	_check("TROOP 3 Riflemen spawn at the hut", S.troops.size() == 3 and _evts(sev, "troop_spawn").size() == 3 and (S.troops[0]["pos"] as Vector2) == TowerState.slot_pos(_rc(2, 3)))
	# V2 P3d (horde-only): Riflemen guard the whole perimeter - anchor = the
	# Core, idle at a post just outside the grid on the hut's side.
	var anchor: Vector2 = S.troops[0]["post"]
	_check("TROOP post sits outside the wall on the hut's side (anchor = the Core)", anchor.distance_to(TowerState.CENTER) > S.grid_half_px() and anchor.y < TowerState.CENTER.y and (S.troops[0]["anchor"] as Vector2) == TowerState.CENTER)
	S.stats["weapons"] = [S.stats["weapons"].back()]
	S.stats["weapons"].back()["range"] = 1.0   # silence the Core
	for k in 60:
		S.tick(0.1)
	_check("TROOP idle troops walk out to their post", (S.troops[0]["pos"] as Vector2).distance_to(anchor) < 2.0)
	var foe: Dictionary = _enemy("hauler", anchor + Vector2(0, -150), 200.0)
	foe["eid"] = 900
	foe["spd"] = 0.0
	S.set_enemies([foe])
	var tev: Array = []
	for k in 40:
		tev.append_array(S.tick(0.1))
	_sync(S, [foe])
	_check("TROOP seek + engage: troops hit the enemy (troop_move + troop_hit)", float(foe["hp"]) < 200.0 and _evts(tev, "troop_hit").size() > 3 and _evts(tev, "troop_move").size() >= 1)
	# Enemies hit troops in contact (50% contact dmg); Riflemen taunt.
	var gentle: Dictionary = _enemy("hauler", S.troops[0]["pos"], 1.0e9)
	gentle["eid"] = 902
	gentle["dmg"] = 0.5
	gentle["spd"] = 30.0
	S.set_enemies([gentle])
	var gpos: Vector2 = gentle["pos"]
	for k in 10:
		S.tick(0.1)
	_sync(S, [gentle])
	_check("TROOP Riflemen taunt (pinned enemy does not advance)", (gentle["pos"] as Vector2).distance_to(gpos) < 3.0)
	var brute: Dictionary = _enemy("hauler", S.troops[0]["pos"], 1.0e9)
	brute["eid"] = 901
	brute["dmg"] = 400.0
	brute["spd"] = 30.0
	S.set_enemies([brute])
	tev = []
	for k in 10:
		tev.append_array(S.tick(0.1))
	_check("TROOP contact dmg kills troops -> troop_die + respawn timer", _evts(tev, "troop_die").size() >= 1 and S.troops.filter(func(t: Variant) -> bool: return String((t as Dictionary)["state"]) == "dead").size() >= 1)
	S.set_enemies([])
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
	var tq: Array = _troop_q([drone_e, elite_e])
	for k in 60:
		res = Troops.step(tr, tq[0], tq[1], 0.1, {"cell_px": 78.0})
		hits.append_array(res["hits"])
		died += _evts(res["ev"], "troop_die").size()
	var elite_hit: float = 0.0
	for h in hits:
		if int(h["eid"]) == 2:
			elite_hit += float(h["dmg"])
	_check("TROOP sappers charge the elite first and blast x2 vs armored", elite_hit >= 60.0 and died >= 1 and int(tr[0]["tgt"]) != 1)
	# Drones prefer flyers and retreat below 25%.
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
	var nb: Dictionary = BaseMeta.normalize({"version": 5, "insight": {"in_dmg": 999, "in_bogus": 3, "in_hp": -2}})
	_check("INS normalize clamps to cap + drops unknown", int(nb["insight"]["in_dmg"]) == 50 and not (nb["insight"] as Dictionary).has("in_bogus") and not (nb["insight"] as Dictionary).has("in_hp"))
	# Insight applies to the run and banks at run end (win or loss).
	var isv: Dictionary = BaseMeta.default_save()
	isv["insight"] = {"in_dmg": 10, "in_hp": 20, "in_luck": 3}
	var S = TowerState.new()
	S.setup(1, BaseMeta.normalize(isv))
	_check("INS applies: +5% dmg, +10% HP, Luck 3", is_equal_approx(float(_weapon(S, "core")["dmg"]), 10.0 * 1.05) and is_equal_approx(float(S.stats["max_hp"]), 132.0) and S.luck == 3)
	S.insight_found = ["in_cash"]
	S.loot = {"scrap": 10}
	var dev: Array = S.abandon()
	var go: Dictionary = _evts(dev, "game_over")[0]
	# V2 P1 (deliberate): loot is Scrap only until P5 (items + caches).
	_check("INS + loot banked at run end (abandon = loss path)", int(S.save["insight"]["in_cash"]) == 1 and _evts(dev, "insight_banked").size() == 1 and int(S.save["scrap"]) == 10 and _evts(dev, "loot_banked").size() == 1 and (go["insight"] as Array) == ["in_cash"])
	# Drops (V2 P1 interim, deliberate): Scrap only — boss 5*T, Courier 10*T,
	# elite 25% x in_drop for T Scrap. P5 brings items and caches.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bd: Array = Drops.roll(rng, "boss", {"tier": 3})
	_check("DROP boss always gives 5*T Scrap", bd.size() == 1 and String(bd[0]["kind"]) == "scrap" and int(bd[0]["n"]) == 15)
	var cd: Array = Drops.roll(rng, "courier", {"tier": 2})
	_check("DROP Courier gives 10*T Scrap", cd.size() == 1 and int(cd[0]["n"]) == 20)
	var el_dm: int = 0
	for k in 20000:
		for d in Drops.roll(rng, "elite", {"drop_mult": 1.15}):
			if String(d["kind"]) == "scrap":
				el_dm += 1
	_check("DROP elite ~25%% x in_drop (%d / 20000 at x1.15)" % el_dm, el_dm > 5300 and el_dm < 6200)
	var loot: Dictionary = Drops.empty_loot()
	Drops.add(loot, [{"kind": "scrap", "n": 5}, {"kind": "scrap", "n": 2}, {"kind": "junk", "n": 9}])
	_check("DROP loot fold: scrap only", int(loot["scrap"]) == 7 and loot.size() == 1)
	# Engine: boss kill emits drop events; drops replay with the seed and
	# never perturb the wave RNG.
	var A = _fresh()
	var B = _fresh()
	A.spawn_hold = true
	B.spawn_hold = true
	var da: Array = []
	var db: Array = []
	for k in 40:
		A.add_enemy(_enemy("boss", TowerState.CENTER + Vector2(0, 300), 0.0))
		A._reap(da)
		B.add_enemy(_enemy("boss", TowerState.CENTER + Vector2(0, 300), 0.0))
		B._reap(db)
	_check("DROP engine: boss drops emitted + replay exactly", _evts(da, "drop").size() >= 40 and JSON.stringify(_evts(da, "drop")) == JSON.stringify(_evts(db, "drop")) and int(A.loot["scrap"]) == 200)
	var C = _fresh()
	_check("DROP loot RNG is separate from the wave RNG", A.rng.state == C.rng.state)
	# Courier spawns, runs on a chord outside the wall, escapes or drops.
	var K = _fresh()
	K.spawn_hold = true
	var kev: Array = []
	K._spawn_courier(kev)
	var cour: Dictionary = _last(K)
	_check("COURIER spawn event, mass sheet HP, 140 px/s", _evts(kev, "courier_spawn").size() == 1 and String(cour["kind"]) == "courier" and is_equal_approx(float(cour["max_hp"]), float(EnemyDB.mass_def("courier")["hp"]) * K.mass_hp_scale("courier", K.wave)) and is_equal_approx(float(cour["spd"]), float(EnemyDB.mass_def("courier")["spd"])))
	var min_d: float = INF
	var esc: Array = []
	for k in 200:
		var e2: Array = []
		K._move_enemies(0.05, e2)
		esc.append_array(e2)
		if K.enemy_count() > 0:
			min_d = minf(min_d, (K.enemy_list()[0]["pos"] as Vector2).distance_to(TowerState.CENTER))
	_check("COURIER stays outside the wall and escapes", min_d > TowerState.STOP_R + 30.0 and _evts(esc, "courier_escape").size() == 1 and K.enemy_count() == 0)
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
	M._spawn("drone", [])
	var mh0: float = float(_last(M)["max_hp"])
	M._spawn("drone", [], Vector2.INF, true)
	_check("MARK marked enemy x3 HP + flag", bool(_last(M)["marked"]) and is_equal_approx(float(_last(M)["max_hp"]), mh0 * 3.0))


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
	S.slots[_rc(3, 2)] = {"id": "hut_infantry", "perm": 0, "run": 1}
	S.specials = [{"id": "sp_orbital", "copies": 1, "cd": 0.0, "charges": 1}]
	S.recompute()
	var snap2: Dictionary = S.power_snapshot()
	_check("SNAP lists building DPS, troops, orbital DPS", (snap2["buildings"] as Array).size() == 1 and is_equal_approx(float(snap2["buildings"][0]["dps"]), 12.0 * TowerState.bld_dmg() * float(TowerState.MASS_CROWD["gun"])) and (snap2["troops"] as Array).size() == 3 and float(snap2["specials"][0]["dps"]) > 0.0)
	_check("SNAP power ratio rises with the board", PowerModel.power_ratio(snap2, 1, 1) > r0 and r0 > 2.0)


# ======================================================================
# ENGINE-META (REDESIGN_SPEC §3): Parts, Crates, Outpost, Research, Reforge,
# save v4. TDD'd here; each sub-stage is one system.
# ======================================================================
func _engine_meta_stages() -> void:
	_outpost_stages()
	_reforge_stages()


const OT0: int = 1767225600


func _op_save(coins: int = 1000000) -> Dictionary:
	var sv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	sv["coins"] = coins
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
	_check("AC-17 quantity limit (Relay 1: 2 Mills)", _op_build(sv, "mill", 4, 6) != "" and Outpost.place_error(sv, "mill", 4, 2, 0) == "limit")
	# Connectivity (AC-17): an island Mill produces 0 until a Conduit links it.
	var cs: Dictionary = _op_save()
	var isl: String = _op_build(cs, "mill", 0, 6)
	var con: Dictionary = Outpost.connected(cs["outpost"])
	_check("AC-17 unconnected generator produces 0", not bool(con[isl]) and is_equal_approx(Outpost.rate(cs, isl), 0.0) and Outpost.nominal_rate(cs, isl) > 0.0)
	_op_build(cs, "conduit", 2, 6)
	_check("AC-17 a Conduit next to the Relay links it (flood fill)", bool(Outpost.connected(cs["outpost"])[isl]) and is_equal_approx(Outpost.rate(cs, isl), OutpostDB.MILL_RATE))
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
	_check("AC-18 accrual = rate x elapsed (60/h)", absf(float(a["outpost"]["buildings"][mu]["stored"]) - OutpostDB.MILL_RATE) < 0.01)
	Outpost.tick(a, OT0 + 3600 * 30)
	_check("AC-18 accrual clamps at the 8 h storage cap", is_equal_approx(float(a["outpost"]["buildings"][mu]["stored"]), 8.0 * OutpostDB.MILL_RATE) and is_equal_approx(Outpost.cap(a, mu), 8.0 * OutpostDB.MILL_RATE))
	var c0: int = int(a["coins"])
	var cev: Array = Outpost.collect(a, mu, OT0 + 3600 * 30)
	_check("AC-18 collect pays whole coins and empties storage", _evts(cev, "collect").size() == 1 and int(a["coins"]) == c0 + int(8.0 * OutpostDB.MILL_RATE) and float(a["outpost"]["buildings"][mu]["stored"]) < 1.0 and int(a["stats"]["outpost_collects"]) == 1)
	var pv: Dictionary = Outpost.pending(a, OT0 + 3600 * 32)
	_check("OP pending previews without mutating", absf(float(pv["coins"]) - 2.0 * OutpostDB.MILL_RATE) < 0.01 and float(a["outpost"]["buildings"][mu]["stored"]) < 1.0)
	# First tick of a never-ticked building only stamps the clock (no back pay).
	var nb: Dictionary = _op_save()
	var nu: String = _op_build(nb, "mill", 4, 4)
	nb["outpost"]["buildings"][nu]["last_tick"] = 0
	Outpost.tick(nb, OT0 + 86400)
	_check("OP last_tick 0 = start the clock (no double pay after migration)", is_equal_approx(float(nb["outpost"]["buildings"][nu]["stored"]), 0.0) and int(nb["outpost"]["buildings"][nu]["last_tick"]) == OT0 + 86400)
	# FEEDBACK-1 (deliberate): builds and upgrades are INSTANT (no timers, no
	# builders limit, no gem skips).
	var t: Dictionary = _op_save()
	var pe: Array = Outpost.place(t, "mill", 4, 4, 0, OT0)
	var tu: String = String(_evts(pe, "op_placed")[0]["uid"])
	_check("FB1 a build completes on placement", _evts(pe, "build_done").size() == 1 and bool(t["outpost"]["buildings"][tu]["built"]) and Outpost.busy(t) == 0)
	_check("FB1 no builder limit (2nd build at once)", not Outpost.place(t, "mill", 4, 6, 0, OT0).is_empty() and not Outpost.place(t, "conduit", 2, 6, 0, OT0).is_empty())
	var dev: Array = Outpost.tick(t, OT0 + 3600)
	_check("FB1 an instant build produces from placement", float(t["outpost"]["buildings"][tu]["stored"]) > 0.0 and absf(float(t["outpost"]["buildings"][tu]["stored"]) - Outpost.rate(t, tu)) < 0.01)
	var nr1: float = Outpost.nominal_rate(t, tu)
	var uc: int = Outpost.cost("mill", 1)
	var c1: int = int(t["coins"])
	var uev: Array = Outpost.upgrade(t, tu, OT0 + 3720)
	_check("OP upgrade cost x1.6^(L-1), instant", _evts(uev, "upgrade_done").size() == 1 and int(t["coins"]) == c1 - uc and Outpost.cost("mill", 3) == int(round(500.0 * 2.56)) and Outpost.build_time(t, "mill", 2) == 0)
	_check("OP upgrade done: L2 = +25% production", int(t["outpost"]["buildings"][tu]["lvl"]) == 2 and is_equal_approx(Outpost.nominal_rate(t, tu), 1.25 * nr1))
	_check("OP max level = min(10, Relay L + 2)", Outpost.max_lvl(t, "mill") == 3)
	var sk: Dictionary = _op_save()
	sk["outpost"]["queue"] = [{"uid": "relay", "kind": "upgrade", "ends_at": OT0 + 99999}]
	var skn: Dictionary = BaseMeta.normalize(sk)
	Outpost.tick(skn, OT0)
	_check("FB1 a job queued in an old save completes on the next tick", int(skn["outpost"]["relay_lvl"]) == 2 and (skn["outpost"]["queue"] as Array).is_empty() and not Outpost.new().has_method("skip"))
	var _dv: int = dev.size()
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
	_check("AC-19 Warehouse +10% storage within radius 2", is_equal_approx(Outpost.warehouse_bonus(j["outpost"], ma), 0.10))
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
	# FEEDBACK-1 (deliberate): the Gem Mine is now the Deep Mine — a coin
	# generator (3x a Mill's base rate, 8 h storage); no gems, no daily cap.
	var gm: Dictionary = _op_save()
	var gu: String = _op_build(gm, "gemmine", 0, 6)
	_op_build(gm, "conduit", 2, 6)
	_check("OP Deep Mine: 3x Mill rate in coins", String(OutpostDB.get_def("gemmine")["res"]) == "coins" and is_equal_approx(Outpost.nominal_rate(gm, gu), 3.0 * OutpostDB.MILL_RATE * Outpost.global_mult(gm)))
	Outpost.tick(gm, OT0 + 86400 * 30)
	_check("OP Deep Mine storage cap = 8 h of output", is_equal_approx(float(gm["outpost"]["buildings"][gu]["stored"]), Outpost.cap(gm, gu)) and is_equal_approx(Outpost.cap(gm, gu), 8.0 * Outpost.nominal_rate(gm, gu) * (1.0 + Outpost.warehouse_bonus(gm["outpost"], gu))))
	var gg: int = int(gm["coins"])
	var gst: float = float(gm["outpost"]["buildings"][gu]["stored"])
	Outpost.collect(gm, gu, OT0 + 86400 * 30)
	_check("OP Deep Mine collect pays coins", int(gm["coins"]) == gg + int(floor(gst)) and not gm.has("gems"))
	# Plots: cost, adjacency (coins only — FEEDBACK-1).
	var p: Dictionary = _op_save(10000000)
	_check("OP plot 0 costs 5,000; a non-adjacent plot is refused", int(Outpost.plot_cost(p)["coins"]) == 5000 and Outpost.unlock_plot(p, 5).is_empty())
	Outpost.unlock_plot(p, 0)
	_check("OP plot k = 5,000 x 2.2^k; plot 5 adjacent after plot 0", int(Outpost.plot_cost(p)["coins"]) == 11000 and not Outpost.unlock_plot(p, 5).is_empty())
	Outpost.unlock_plot(p, 1)
	Outpost.unlock_plot(p, 2)
	var pc4: Dictionary = Outpost.plot_cost(p)
	var cp4: int = int(p["coins"])
	Outpost.unlock_plot(p, 3, "coins")
	_check("FB1 5th plot: plain coin price 5,000 x 2.2^4, no gem option", not pc4.has("gems") and int(pc4["coins"]) == int(round(5000.0 * pow(2.2, 4.0))) and int(p["coins"]) == cp4 - int(pc4["coins"]))
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
	# FEEDBACK-1: builds are instant, so nothing is ever "queued" — a fresh
	# building demolishes at the normal 50% refund and no builder is held.
	var qd: Dictionary = _op_save()
	var qe: Array = Outpost.place(qd, "barracks", 4, 2, 0, OT0)
	var c4: int = int(qd["coins"])
	Outpost.demolish(qd, String(_evts(qe, "op_placed")[0]["uid"]), OT0)
	_check("FB1 demolish right after placing refunds 50%, no builder held", int(qd["coins"]) == c4 + 1500 and Outpost.busy(qd) == 0)
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



## Set the pre-placed Research Hall's level (queue tests).
func _hall(sv: Dictionary, lvl: int) -> void:
	var bl: Dictionary = sv["outpost"]["buildings"]
	for k in bl.keys():
		if String((bl[k] as Dictionary)["id"]) == "research":
			(bl[k] as Dictionary)["lvl"] = lvl


## AC-21: gate, shard formula, reset / keep lists, tree cost + max, effects.
func _reforge_stages() -> void:
	var sv: Dictionary = BaseMeta.normalize({})
	sv["core"]["lvl"] = 20
	sv["coins"] = 50000
	sv["scrap"] = 3
	sv["best_wave_by_tier"] = {"1": 39}
	sv["best_wave"] = 39
	sv["reforge"]["coins_since"] = 600000
	_check("AC-21 refused below the gate (w39, 600k coins)", not Reforge.can_reforge(sv) and Reforge.reforge(sv, OT0).is_empty() and int(sv["coins"]) == 50000)
	_check("AC-21 coin gate: 1,000,000 coins since", Reforge.can_reforge({"best_wave_by_tier": {"1": 1}, "reforge": {"coins_since": 1000000, "nodes": {}}}))
	sv["best_wave_by_tier"] = {"1": 40}
	_check("AC-21 wave gate: best wave 40", Reforge.can_reforge(sv))
	var sh1: int = int(floor(ReforgeDB.SHARD_K * sqrt(60.0))) + 5
	_check("AC-21 shards = floor(k sqrt(6e5 / 1e4)) + 5 first (k = ReforgeDB.SHARD_K; loop table at k 1: 12)", Reforge.shards_now(sv) == sh1 and int(Reforge.preview(sv)["shards"]) == sh1 and bool(Reforge.preview(sv)["worth"]))
	# Build a little state to reset.
	var mu: String = _op_build(sv, "mill", 4, 4)
	sv["outpost"]["buildings"][mu]["lvl"] = 3
	sv["outpost"]["relay_lvl"] = 3
	sv["outpost"]["plots"] = [0]
	Outpost.place_decor(sv, "dc_tree", 7, 2, 0)
	Outpost.save_blueprint(sv, "Mine")
	sv["research"]["lvls"]["dmg"] = 5
	sv["insight"]["in_dmg"] = 4
	sv["tier"] = 1
	var c_before: int = int(sv["coins"])
	var ev: Array = Reforge.reforge(sv, OT0 + 100)
	var ok_reset: bool = int(sv["coins"]) == 0 and Cores.level(sv) == 1 and int(sv["outpost"]["buildings"][mu]["lvl"]) == 1 and int(sv["outpost"]["relay_lvl"]) == 1 and int(sv["research"]["lvls"]["dmg"]) == 0 and int(sv["tier"]) == 1 and Tiers.highest(sv) == 1
	_check("AC-21 resets: coins, Core level, Outpost levels + Relay, research, tier", c_before > 0 and _evts(ev, "reforge").size() == 1 and ok_reset)
	var ok_keep: bool = (sv["outpost"]["plots"] as Array) == [0] and (sv["outpost"]["decor"] as Dictionary).size() == 1 and (sv["outpost"]["blueprints"] as Array).size() == 1 and int(sv["outpost"]["buildings"][mu]["x"]) == 4 and not sv.has("gems") and int(sv["scrap"]) == 3 and int(sv["insight"]["in_dmg"]) == 4 and int(sv["best_wave"]) == 39
	_check("AC-21 keeps: layout/plots/decor/blueprints, Scrap, Insight, best wave", ok_keep)
	_check("AC-21 shards banked, count + cum", int(sv["shards"]) == sh1 and Reforge.count(sv) == 1 and int(sv["reforge"]["cum_shards"]) == sh1 and int(sv["reforge"]["coins_since"]) == 0 and int(sv["stats"]["reforges"]) == 1)
	_check("AC-21 gate re-arms after a Reforge (tier progress reset)", not Reforge.can_reforge(sv))
	sv["reforge"]["coins_since"] = 2500000
	_check("R5 2nd Reforge: no first bonus (2.5e6 -> floor(k x 15.8))", Reforge.shards_now(sv) == int(floor(ReforgeDB.SHARD_K * sqrt(250.0))))
	var rs: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(sv)))
	_check("AC-21 tree/shards/count survive save/load", int(rs["shards"]) == sh1 and Reforge.count(rs) == 1)
	# Tree: root first, cost base + step*L, max.
	_check("AC-21 nodes need root_forge", not Reforge.can_buy(sv, "might") and not Reforge.buy(sv, "root_forge").is_empty() and int(sv["shards"]) == sh1 - 1)
	Reforge.buy(sv, "might")
	Reforge.buy(sv, "might")
	_check("AC-21 cost 2 + L (might: 2 then 3)", Reforge.node(sv, "might") == 2 and int(sv["shards"]) == sh1 - 6)
	sv["shards"] = 999
	for k in 5:
		Reforge.buy(sv, "banish_plus")
	_check("AC-21 max respected (banish+ 2)", Reforge.node(sv, "banish_plus") == 2 and ReforgeDB.cost("head_start", 2) == 8)
	_check("AC-21 tree has no core_hive (deferred)", not ReforgeDB.NODES.has("core_hive") and ReforgeDB.IDS.size() == ReforgeDB.NODES.size())
	# Effects reach the run and the meta.
	for id in ["bulwark_p", "prosperity", "starting_cash", "head_start", "wide_draft", "tempo", "builder2", "shard_yield", "scrap_p", "outpost_p", "retain"]:
		Reforge.buy(sv, String(id))
	_check("V2 crate_luck node is gone", not ReforgeDB.NODES.has("crate_luck"))
	var S = TowerState.new()
	S.setup(3, sv)
	# Node strengths are ReforgeDB data (balance pass 2: might x1.6, bulwark x1.35 per level, multiplicative).
	_check("RF might x2 (multiplicative) / bulwark / prosperity levels apply ReforgeDB amt in the run", is_equal_approx(S.dmg_mult, 1.0 + ReforgeDB.bonus("might", 2)) and is_equal_approx(S.dmg_mult, pow(1.0 + ReforgeDB.amt("might"), 2.0)) and is_equal_approx(S.max_hp_mult, 1.0 + ReforgeDB.bonus("bulwark_p", 1)) and is_equal_approx(S.coin_mult, 1.0 + ReforgeDB.amt("prosperity")))
	_check("RF head_start + starting_cash + wide_draft + banish+", int(S.tracks["dmg"]) == 1 and int(S.cash) == 25 and int(S._draft_ctx("")["choices"]) == 4 and S.banish_left == 3)
	_check("RF tempo adds a speed step, builder2 a builder", (Labs.speed_steps(sv) as Array).back() == 1.25 and Outpost.builders(sv) == 2)
	_check("RF shard_yield +10% (k x 1.1)", Reforge.shards_now({"reforge": {"count": 1, "coins_since": 1000000, "nodes": {"shard_yield": 1}}}) == int(floor(ReforgeDB.SHARD_K * 1.1 * 10.0)))
	Reforge.buy(sv, "bp_mint")
	_check("RF bp_mint: Mint Ring blueprint + 20% build credit", String((sv["outpost"]["blueprints"] as Array).back()["name"]) == "Mint Ring" and int(sv["outpost"]["credit"]) == (500 * 2 + 2000) / 5)
	# retain keeps floor(lvl x 10%) of Outpost levels.
	var rt: Dictionary = _op_save()
	var ru: String = _op_build(rt, "mill", 4, 4)
	rt["outpost"]["buildings"][ru]["lvl"] = 10
	rt["reforge"]["nodes"] = {"root_forge": 1, "retain": 3}
	rt["best_wave_by_tier"] = {"1": 45}
	Reforge.reforge(rt, OT0)
	_check("RF retain 3: keeps 30% of Outpost levels (L10 -> L3)", int(rt["outpost"]["buildings"][ru]["lvl"]) == 3)
	# Outpost coins feed coins_since.
	var oc: Dictionary = _op_save()
	var ou: String = _op_build(oc, "mill", 4, 4)
	Outpost.collect(oc, ou, OT0 + 3600)
	_check("RF Outpost coins count toward coins_since", int(oc["reforge"]["coins_since"]) == int(OutpostDB.MILL_RATE))

