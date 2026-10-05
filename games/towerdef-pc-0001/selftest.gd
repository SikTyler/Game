extends SceneTree
## Corehold rules self-test. Drives TowerState / BaseMeta / Draft directly with
## fixed seeds and asserts what a human would check. Prints "SELFTEST OK" (exit
## 0) or "SELFTEST FAIL: <reason>" (exit 1).
## Run: godot --headless --path games/towerdef-pc-0001/ --script res://selftest.gd

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
const Reforge := preload("res://Reforge.gd")
const ReforgeDB := preload("res://data/ReforgeDB.gd")

var fails: Array = []


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails.append(name)
		print("SELFTEST FAIL: " + name + ("" if detail == "" else "  [" + detail + "]"))


## Mobile 5x5 cell index -> the same cell on the PC 7x7 board (r+1, c+1), so
## the inherited 5x5 checks keep their exact geometry and adjacency.
func _c(i5: int) -> int:
	return BaseMeta.idx5_to_7(i5)


## Mobile 5x5 index -> run board index (FEEDBACK-1: 11x11, Core at (5,5)):
## (r, c) -> (r+3, c+3); rings are the same as on the old 7x7 board.
func _r(i5: int) -> int:
	return (i5 / 5 + 3) * 11 + (i5 % 5 + 3)


func _fresh(save: Dictionary = {}) -> RefCounted:
	var S = TowerState.new()
	S.setup(1234, BaseMeta.normalize(save))
	return S


func _initialize() -> void:
	# --- Stage 1: setup ------------------------------------------------------
	var S = _fresh()
	# REDESIGN: the Core's HP comes from its CoreDB sheet (Bastion L1 = 120).
	_check("setup: full hp (Bastion sheet)", is_equal_approx(S.hp, 120.0) and S.core_id == "bastion" and S.core_lvl == 1)
	_check("setup: inner ring unlocked, outer locked", bool(S.unlocked[_r(6)]) and not bool(S.unlocked[_r(0)]) and not bool(S.unlocked[_r(12)]))
	_check("setup: 8 free slots", S.free_slots().size() == 8)
	_check("setup: core is the only weapon", (S.stats["weapons"] as Array).size() == 1)

	# --- Stage 2: stats math + adjacency -------------------------------------
	# REDESIGN (deliberate): building numbers follow REDESIGN_SYSTEMS §2.3
	# (L1 sheet, +35% main stat per level); Armory is +15% to neighbours.
	S.slots[_r(7)] = {"id": "gun", "perm": 0, "run": 1}
	S.recompute()
	var gun_dmg: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	_check("gatling L1 6 dmg x building scale (Steadfast-free)", is_equal_approx(gun_dmg, 6.0 * TowerState.bld_dmg()))
	S.slots[_r(6)] = {"id": "armory", "perm": 0, "run": 1}   # adjacent to gun (7) and core (12)
	S.recompute()
	var buffed: float = float((S.stats["weapons"] as Array)[0]["dmg"])
	_check("armory buffs adjacent gun +15%", is_equal_approx(buffed, gun_dmg * 1.15) and _has_link(S, _r(6), _r(7), "ARM"))
	S.slots[_r(0)] = {"id": "armory", "perm": 0, "run": 1}   # NOT adjacent to 7
	S.recompute()
	_check("armory does not buff non-adjacent", is_equal_approx(float((S.stats["weapons"] as Array)[0]["dmg"]), buffed))
	S = _fresh()
	S.slots[_r(16)] = {"id": "mine", "perm": 0, "run": 2}
	S.slots[_r(18)] = {"id": "bulwark", "perm": 0, "run": 1}
	S.recompute()
	_check("mine L2 cash/s = Core 2.0 + 0.8x1.35, Steadfast +1%/building", is_equal_approx(float(S.stats["cash_ps"]), (2.0 + 0.8 * 1.35) * 1.02))
	_check("bulwark raises max hp +40", is_equal_approx(float(S.stats["max_hp"]), 160.0))
	_check("bulwark heals by its bonus", is_equal_approx(S.hp, 160.0))

	# --- Stage 3: combat — core kills an enemy, rewards land ------------------
	S = _fresh()
	S.add_enemy({"kind": "drone", "pos": TowerState.CENTER + Vector2(200, 0), "hp": 4.0, "max_hp": 4.0, "spd": 0.0, "dmg": 4.0, "cash": 1.0, "xp": 1.0, "coin": 0.2, "size": 16.0, "atk_cd": 0.0, "slow_t": 0.0})
	S.spawn_hold = true
	var ev: Array = S.tick(0.05)
	var kinds: Array = ev.map(func(e): return e["t"])
	_check("core fires a shot", kinds.has("shot"))
	_check("kill event + cash + xp", kinds.has("kill") and S.cash >= 1.0 and S.xp >= 1.0 and S.kills == 1)

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
	S.place(_r(0))  # locked — rejected
	_check("cannot place on locked slot", S.pending_place != "")
	ev = S.place(_r(6))
	_check("placed building in free slot", S.id_at(_r(6)) == "mortar" and S.pending_place == "" and is_equal_approx(S.time_scale(), 1.0))
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
	# A pending upgrade whose only target is destroyed is cancelled.
	S.draft = [Draft.card_for("mine", S._draft_ctx(""))]
	S.choose_card(0)
	var dev2: Array = []
	S._destroy_building(_r(8), dev2)
	_check("FB1 destroying the upgrade's last target cancels it", S.pending_upgrade == "" and _evts(dev2, "upgrade_cancelled").size() == 1 and _evts(dev2, "building_destroyed").size() == 1)
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
	_check("no per-cell run unlocks", S.unlock_plot(_r(0)).is_empty() and not bool(S.unlocked[_r(0)]))

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
	_check("run grid starts empty (no perm buildings / unlocks)", S.building_count() == 0 and not bool(S.unlocked[_r(0)]))
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
	_horde_stages()

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
	var m3: Dictionary = BaseMeta.migrate(v1, 3)
	_check("AC-1 migrate keeps v1 fields (to v3)", int(m3["coins"]) == 123 and int(m3["runs"]) == 5 and int(m3["core"]["hp"]) == 2 and String(m3["slots"][str(_c(7))]["id"]) == "gun" and int(m3["slots"][str(_c(7))]["lvl"]) == 3 and (m3["unlocked"] as Array) == [_c(0), _c(4)])
	# REDESIGN (ENGINE-META, deliberate, AC-22): v4 refunds the permanent base
	# and folds the Core stat levels into the Bastion level.
	var m: Dictionary = BaseMeta.normalize(BaseMeta.migrate(v1))
	var rf1: int = BaseMeta.place_cost("gun") + BaseMeta.upgrade_cost(1) + BaseMeta.upgrade_cost(2) + 2 * 500 + BaseMeta.core_cost(1)
	_check("AC-1 v1 -> v4: base refunded, Core stats -> Bastion L2", int(m["coins"]) == 123 + rf1 and int(m["runs"]) == 5 and int(m["core"]["hp"]) == 0 and (m["slots"] as Dictionary).is_empty() and Cores.level(m, "bastion") == 2)
	_check("AC-1 migrate v2 fields", int(m["best_wave_by_tier"]["1"]) == 37 and int(m["best_wave"]) == 37 and not m.has("gems") and int(m["tier"]) == 1 and int(m["last_seen"]) == 0 and int(m["version"]) == BaseMeta.VERSION)
	# REDESIGN (ENGINE-META, deliberate): labs live in save.research now.
	_check("AC-1 armor lab dropped, others kept", not (m["research"]["lvls"] as Dictionary).has("armor") and int(m["research"]["lvls"]["coin"]) == 2)
	_check("normalize on raw v1 also migrates", int(BaseMeta.normalize(v1)["version"]) == BaseMeta.VERSION and int(BaseMeta.normalize(v1)["best_wave_by_tier"]["1"]) == 37)
	var v2: Dictionary = BaseMeta.normalize(m)
	v2["last_seen"] = NOW
	v2["best_coin_rate"] = 12.5
	v2["research"]["running"] = [{"track": "dmg", "to_lvl": 1, "start": NOW, "end": NOW + 300}]
	v2["cards"]["owned"] = {"c_dmg": {"lvl": 2, "copies": 1}}
	v2["cards"]["equipped"] = ["c_dmg"]
	v2 = BaseMeta.normalize(v2)
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(v2)))
	_check("AC-2 v2 round-trips through JSON", JSON.stringify(rt) == JSON.stringify(v2) and not rt.has("gems"))
	var bad: Dictionary = BaseMeta.normalize(v2)
	bad["slots"][str(_c(8))] = {"id": "laser_of_doom", "lvl": 1}
	bad["slots"][str(_c(7))] = {"id": "gun", "lvl": 99}   # legacy view key (v4 keeps it empty)
	bad["research"]["lvls"]["dmg"] = 99
	bad["research"]["lvls"]["bogus"] = 3
	bad["research"]["running"] = [{"track": "coin", "to_lvl": 3, "start": 0, "end": 1}, {"track": "xp", "to_lvl": 1, "start": 0, "end": 1}, {"track": "hp", "to_lvl": 1, "start": 0, "end": 1}]
	bad["cards"]["owned"]["c_hp"] = {"lvl": 9, "copies": 3}
	bad["cards"]["owned"]["c_fake"] = {"lvl": 1, "copies": 0}
	bad = BaseMeta.normalize(bad)
	_check("AC-3 unknown building dropped", BaseMeta.slot_of(bad, _c(8)).is_empty())
	_check("AC-3 slot lvl clamped to perm cap", int(BaseMeta.slot_of(bad, _c(7))["lvl"]) == BaseMeta.perm_lvl_cap(bad))
	_check("AC-3 lab lvl clamped + unknown lab dropped", int(bad["research"]["lvls"]["dmg"]) == 30 and not (bad["research"]["lvls"] as Dictionary).has("bogus"))
	_check("AC-3 running <= Research Hall queues", (bad["research"]["running"] as Array).size() <= Labs.slots(bad) and Labs.slots(bad) == 1)
	_check("AC-3 card lvl clamped + unknown card dropped", int(bad["cards"]["owned"]["c_hp"]["lvl"]) == 5 and not (bad["cards"]["owned"] as Dictionary).has("c_fake"))
	_check("AC-4 first v2 boot pays no offline (Outpost away report)", int(Outpost.away_report(m, NOW)["coins"]) == 0)
	# bank + perm cap
	var b: Dictionary = BaseMeta.default_save()
	var bev: Array = BaseMeta.bank(b, 100, 35, 1, 10.0, NOW)
	_check("bank records tier best, rate, last_seen, coins (no gems)", int(b["best_wave_by_tier"]["1"]) == 35 and is_equal_approx(float(b["best_coin_rate"]), 10.0) and int(b["last_seen"]) == NOW and int(b["coins"]) == 100 and not b.has("gems") and bev.is_empty())
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
	var g0: int = int(b["coins"])
	bev = BaseMeta.bank(b, 10, 40, 1, 1.0, NOW)
	_check("AC-5 w40 in T1 unlocks T2 with +500 coins (FB1: was 10 gems)", Tiers.highest(b) == 2 and _evts(bev, "tier_unlocked").size() == 1 and int(b["coins"]) == g0 + 10 + 500)
	bev = BaseMeta.bank(b, 10, 45, 1, 1.0, NOW)
	_check("AC-5 tier unlock rewarded once", bev.is_empty() and int(b["coins"]) == g0 + 10 + 500 + 10)
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
	# FEEDBACK-1: +Grid Expansion, -Lab Speed (research time is gone) -> still 12.
	_check("AC-20 every LabDB project + Part Analysis + Crate Theory + Grid", LabDB.IDS.size() == 12 and LabDB.DEFS.has("grid") and not LabDB.DEFS.has("labspeed") and LabDB.DEFS.has("part_analysis") and LabDB.DEFS.has("crate_theory") and String(LabDB.DEFS["offcap"]["name"]) == "Storage Tech" and String(LabDB.DEFS["offrate"]["name"]) == "Logistics Tech")
	_check("FB1 grid research 3/5/7/8/10, cost 60 x3^L", LabDB.max_of("grid") == 4 and Labs.cost("grid", 0) == 60 and Labs.cost("grid", 3) == 1620 and TowerState.grid_for_level(0) == 3 and TowerState.grid_for_level(1) == 5 and TowerState.grid_for_level(2) == 7 and TowerState.grid_for_level(3) == 8 and TowerState.grid_for_level(4) == 10)
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
	# permanent upgrades + lab starts feed missions
	M["missions"]["list"] = [{"tpl": "upgrade", "target": 3, "prog": 0, "claimed": false, "coins": 80}, {"tpl": "lab", "target": 2, "prog": 0, "claimed": false, "coins": 80}, {"tpl": "eco", "target": 4, "prog": 0, "claimed": false, "coins": 80}]
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
	# FEEDBACK-1: the streak pays coins only (gem days -> coins).
	_check("streak day 6", int(K["streak"]["day_idx"]) == 6 and int(K["coins"]) == 50 + 80 + 100 + 120 + 200 + 160)
	sev = Missions.streak_claim(K, NOW + 86400 * 6)
	_check("AC-30 day 7 = 400 coins + free chest", int(K["streak"]["day_idx"]) == 7 and int(K["coins"]) == 710 + 400 and _evts(sev, "chest_opened").size() == 1 and (K["cards"]["owned"] as Dictionary).size() == 1 and not K.has("gems"))
	var c0: int = int(K["coins"])
	Missions.streak_claim(K, NOW + 86400 * 7)
	_check("streak loops with x1.1 coins", int(K["streak"]["day_idx"]) == 1 and int(K["streak"]["loops"]) == 1 and int(K["coins"]) == c0 + 55)
	Missions.streak_claim(K, NOW + 86400 * 9)
	_check("AC-30 missed day resets to day 1", int(K["streak"]["day_idx"]) == 1 and int(K["streak"]["last_day"]) == day0 + 9)

	# --- Stage 17: cards (AC-31/32) -----------------------------------------
	var C: Dictionary = BaseMeta.default_save()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# FEEDBACK-1: card chests and slots cost coins (gems removed).
	_check("AC-31 chest needs 400 coins", Cards.open_chest(C, rng).is_empty())
	C["coins"] = 400 * 40
	var r1 := RandomNumberGenerator.new()
	r1.seed = 7
	var r2 := RandomNumberGenerator.new()
	r2.seed = 7
	var C2: Dictionary = C.duplicate(true)
	var cev: Array = Cards.open_chest(C, r1)
	_check("AC-31 chest costs 400 coins + seeded", int(C["coins"]) == 400 * 39 and JSON.stringify(cev) == JSON.stringify(Cards.open_chest(C2, r2)) and bool(cev[0]["new"]))
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
	C["coins"] = 1500 + 4000 + 10000
	_check("card slots 1500/4000/10000 coins, max 5", not Cards.buy_slot(C).is_empty() and int(C["coins"]) == 14000 and not Cards.buy_slot(C).is_empty() and not Cards.buy_slot(C).is_empty() and int(C["coins"]) == 0 and Cards.slots(C) == 5 and Cards.buy_slot(C).is_empty())
	Cards.equip(C, "c_reroll")
	_check("reroll card gives int rerolls", int(Cards.mods(C)["reroll"]) == 2)
	Cards.unequip(C, "c_dmg")
	_check("unequip removes effect", is_equal_approx(float(Cards.mods(C)["dmg"]), 0.0))

	# --- Stage 18: run_mods bundle (A8) -------------------------------------
	var R: Dictionary = BaseMeta.normalize(C)
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
	_check("A8 run_mods cards + new bldgs", is_equal_approx(float((rm["cards"] as Dictionary)["hp"]), 0.15) and bool(rm["allow_new_bldg"]) and not bool(BaseMeta.run_mods(BaseMeta.default_save())["allow_new_bldg"]))


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
	# contact rule: a body behind the front rank never hits the Core
	S = _fresh()
	S.spawn_hold = true
	var f: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, TowerState.STOP_R), 50.0)
	var r: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, TowerState.STOP_R + 40.0), 50.0)
	f["spd"] = 0.0
	r["spd"] = 0.0
	S.set_enemies([f, r])
	var cev: Array = []
	S._move_enemies(0.05, cev)
	var hits: Array = _evts(cev, "core_hit")
	_check("P3 contact rule: only the touching front rank attacks the Core", hits.size() == 1)
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


## HORDE Phase 1 gates: the 120 s seeded golden (recorded from the Dict
## implementation before the SoA port) and the store/hash invariants.
## FEEDBACK-1 (deliberate): no lanes, building blocking, live drafts, new
## tracks and difficulty change the sim, so the golden was re-recorded from
## this build (bit-identity to the Dict impl only held while rules matched).
## HORDE P3+P4 (deliberate): fixed substeps + separation + contact rule +
## knockback change the motion, so the golden was re-recorded again.
const HORDE_FP_GOLDEN: String = "9376f2623b5decc493ff065eddff9f3daab94f977e75df9a8d93e0428a6a1fbd"
func _horde_stages() -> void:
	var FP = load("res://horde_fp.gd")
	var got: String = FP.run_all()
	_check("HORDE 120 s seeded fingerprint matches the recorded golden (%s)" % got.left(8), got == HORDE_FP_GOLDEN)
	_check("HORDE fingerprint is deterministic (two runs)", FP.run_all() == got)
	# C# hot loop (HordeMove.cs) vs the GDScript reference path: bit-identical.
	var ES = load("res://EnemyStore.gd")
	var prev_mode: int = ES.cs_mode
	ES.cs_mode = 0
	var got_gd: String = FP.run_all()
	ES.cs_mode = 1
	var got_cs: String = FP.run_all() if ES.cs_available() else got_gd
	ES.cs_mode = prev_mode
	_check("HORDE C# hot loop available (mono build)", ES.cs_available())
	_check("HORDE C# and GDScript hot loops give the same 120 s fingerprint", got_gd == HORDE_FP_GOLDEN and got_cs == HORDE_FP_GOLDEN)
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
	_check("HORDE hash damage(): every live body in radius, spawn order", hits == [0, 2, 1])
	_check("HORDE density counts exact neighbours", S.eh.density(TowerState.CENTER + Vector2(0, -300), 1.0) == 1)
	# ---- FB1: per-body horde loot is common, low value and capped per wave
	var SL = _fresh()
	SL.horde_mult = 4
	SL.wave = 2
	var c0: float = SL.coins_run
	for _i in range(2000):
		SL._horde_loot()
	_check("FB1 horde loot: drops happen and cap at 3 x wave per wave", SL.horde_loot_total > 0.0 and is_equal_approx(SL.coins_run - c0, 6.0))
	# ---- Phase 2: horde_mult conservation + event aggregation
	var S1 = _fresh()
	S1.spawn_hold = true
	S1._spawn("hauler", [], TowerState.CENTER + Vector2(0, -400))
	var S4 = _fresh()
	S4.spawn_hold = true
	S4.horde_mult = 4
	S4._spawn("hauler", [], TowerState.CENTER + Vector2(0, -400), false, 0.25)
	S4._spawn_clones(4)
	var sum_hp: float = 0.0
	var sum_cash: float = 0.0
	var sum_dmg: float = 0.0
	for sl in S4.en.order:
		sum_hp += S4.en.hp[sl]
		sum_cash += S4.en.cash[sl]
		sum_dmg += S4.en.dmg[sl]
	_check("HORDE m=4: 4 bodies, HP / cash / contact dmg conserved", S4.en.count() == 4 and absf(sum_hp - S1.en.hp[0]) < 1e-6 and absf(sum_cash - S1.en.cash[0]) < 1e-9 and absf(sum_dmg - S1.en.dmg[0]) < 1e-9)
	_check("HORDE m=4: body budget scales (MAX_ENEMIES x m)", S4.max_bodies() == TowerState.MAX_ENEMIES * 4 and S1.max_bodies() == TowerState.MAX_ENEMIES)
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
	_check("B1 enemy hp x tier hp_mult", is_equal_approx(float(S.enemy_list()[0]["hp"]), 6.0 * 1.5 * TowerState.difficulty_hp()))   # FB1: x difficulty
	S.set_enemies([])
	S.wave_t = S.wave_time - 0.001
	S.tick(0.05)
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
	gsv["coins"] = 10
	var gn: Dictionary = BaseMeta.normalize(gsv)
	_check("FB1 legacy gems -> coins on load, gem blocks dropped", int(gn["coins"]) == 10 + 4 * BaseMeta.GEM_COINS and not gn.has("gems") and not gn.has("gem_log") and not gn.has("boss_gems_today"))
	S.slots[_r(7)] = {"id": "mine", "perm": 0, "run": 1}
	S.wave = 11
	S.recompute()
	# REDESIGN: every cash amount scales with the run cash index 1.10^(w-1).
	_check("cash/s (Core + Mine) x cash index 1.10^(w-1)", is_equal_approx(float(S.stats["cash_ps"]), (2.0 + 0.8) * 1.01 * pow(1.1, 10.0)))
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
	S.add_enemy(_enemy("ranged", TowerState.CENTER + Vector2(240, 0)))
	S.set_enemy(int(S.enemy_list()[0]["eid"]), {"fire_cd": 2.0})
	var shots: int = 0
	for k in 100:
		shots += _evts(S.tick(0.05), "enemy_shot").size()
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
	_check("AC-27 splitter spawns 2 mites once", mites == 2 and _evts(spv, "split").size() == 1)
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
	S.slots[_r(8)] = {"id": "oilmill", "perm": 0, "run": 1}
	S.recompute()
	_check("oil mill: +2.0 cash/s, adjacent buildings -10% rate", is_equal_approx(float(_weapon(S, "gun")["rate"]), gr * 0.9) and _has_link(S, _r(8), _r(7), "OIL"))
	S.slots[_r(8)] = {}
	S.slots[_rc(4, 1)] = {"id": "beacon", "perm": 0, "run": 1}
	S.recompute()
	var gb: Dictionary = _weapon(S, "gun")
	_check("beacon radius 2: +10% rate, +0.3 range", is_equal_approx(float(gb["rate"]), gr * 1.1) and is_equal_approx(float(gb["range"]), 3.3 * TowerState.cpx()) and _has_link(S, _rc(4, 1), _r(7), "BEA"))
	S.slots[_rc(4, 1)] = {}
	S.slots[_rc(0, 0)] = {"id": "beacon", "perm": 0, "run": 1}
	S.recompute()
	_check("beacon does not reach 3 cells away", is_equal_approx(float(_weapon(S, "gun")["rate"]), gr))
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
	_check("cryo spire: slows 30% + chills (1.5 per pulse, 2/s)", is_equal_approx(float(fe["slow_m"]), 0.7) and float(fe["slow_t"]) > 0.0 and is_equal_approx(999.0 - float(fe["hp"]), 1.5 * TowerState.bld_dmg()))
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

	# --- Stage 25: B8 cards in-run (AC-33) ------------------------------------
	var sv8: Dictionary = BaseMeta.default_save()
	sv8["cards"]["owned"] = {"c_wind": {"lvl": 2, "copies": 0}, "c_skip": {"lvl": 1, "copies": 0}}
	sv8["cards"]["equipped"] = ["c_wind", "c_skip"]
	S = TowerState.new()
	S.setup(3, sv8)
	S.spawn_hold = true
	S.hp = -1.0
	var wev: Array = S.tick(0.05)
	_check("AC-33 Second Wind revives at card %", _evts(wev, "revive").size() == 1 and not S.over and S.hp > 0.2 * float(S.stats["max_hp"]) and S.hp <= 0.255 * float(S.stats["max_hp"]))
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
	# track. FEEDBACK-1 (deliberate): fewer, bigger levels — x1.25 per level on
	# the Core AND every building (drawback -8% Core rate), cost 60 x 2.1^n.
	S = _fresh()
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
	S.wave = 41
	var sev: Array = []
	S._spawn("drone", sev)
	_check("enemy dmg ramp 1.06^(w-1)", is_equal_approx(float(_last(S)["dmg"]), 4.0 * pow(1.06, 40.0) * TowerState.difficulty_dmg()))   # FB1: x difficulty


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
	_check("fire() honours strongest mode", float(strong["hp"]) < 900.0 and float(weak["hp"]) == 10.0)
	_check("hit sets hit_t flash + dmg event", float(strong["hit_t"]) > 0.0 and _evts(fev, "dmg").size() >= 1)
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
	_check("PC-E1 cell_ring 0..3", BaseMeta.cell_ring_rc(3, 3) == 0 and BaseMeta.cell_ring_rc(2, 4) == 1 and BaseMeta.cell_ring_rc(1, 3) == 2 and BaseMeta.cell_ring_rc(0, 6) == 3 and BaseMeta.cell_ring(BaseMeta.CORE_SLOT) == 0)
	var ring_n: Array = [0, 0, 0, 0]
	for i in BaseMeta.N:   # FEEDBACK-1: the meta 7x7 base and the run board are separate now
		ring_n[BaseMeta.cell_ring(i)] = int(ring_n[BaseMeta.cell_ring(i)]) + 1
	_check("PC-E1 ring sizes 1/8/16/24", ring_n == [1, 8, 16, 24])
	var S = _fresh()
	var open_ok: bool = true
	for i in TowerState.N:
		open_ok = open_ok and bool(S.unlocked[i]) == (TowerState.ring_of(i) == 1)
	_check("PC-E1 new save: exactly ring 1 unlocked (3x3 grid)", open_ok and S.free_slots().size() == 8 and S.grid_n == 3)
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
	_check("PC-E1 core / ring 1 cannot be bought", not BaseMeta.try_unlock(sv, BaseMeta.CORE_SLOT) and not BaseMeta.try_unlock(sv, 2 * 7 + 2))
	# FEEDBACK-1 (deliberate): the run grid is a Research unlock (3x3 -> 5x5 ->
	# 7x7 -> 8x8 -> 10x10, Core centred); Core tracks no longer open rings.
	var S1 = TowerState.new()
	S1.setup(3, BaseMeta.default_save())
	S1.cash = 1.0e9
	var e2c: int = _rc(1, 3)   # ring 2 edge (7x7 coords)
	_check("PC-E1 run: per-cell unlock is gone", S1.unlock_plot(e2c).is_empty() and not bool(S1.unlocked[e2c]))
	var rev: Array = []
	for t in TowerState.TRACK_IDS:
		for k in 3:
			rev.append_array(S1.buy_track(String(t)))
	_check("FB1 run: tracks never open grid cells", not bool(S1.unlocked[e2c]) and _evts(rev, "ring_open").is_empty() and S1.track_total() == 15)
	var gsz: Array = []
	var gopen: Array = []
	for lv in 5:
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
	_check("FB1 grid research 3/5/7/8/10 opens GxG-1 cells", gsz == [3, 5, 7, 8, 10] and gopen == [8, 24, 48, 63, 99])
	_check("FB1 even grids keep the Core inside (8x8 rows 2..9, 10x10 rows 1..10)", TowerState.grid_lo(8) == 2 and TowerState.grid_lo(10) == 1 and TowerState.in_grid_n(TowerState.CORE_SLOT, 8) and TowerState.in_grid_n(TowerState.CORE_SLOT, 10) and not TowerState.in_grid_n(0, 10))
	var G2 = TowerState.new()
	G2.setup(7, BaseMeta.default_save(), 0, {"grid": 7})
	_check("FB1 opts.grid override (tests/tools)", G2.grid_n == 7 and bool(G2.unlocked[_rc(0, 3)]) and not bool(G2.unlocked[_rc(-1, 3)]))
	var G3 = TowerState.new()
	G3.setup(7, BaseMeta.default_save(), 0, {"grid": 10})
	_check("FB1 view fits: spawn radius grows with the grid", float(G3.spawn_r()) > float(G2.spawn_r()) and float(G2.spawn_r()) > float(S1.spawn_r()))
	# Land development: +1 perm level cap per 4 outer cells (max +10).
	var ld: Dictionary = BaseMeta.default_save()
	var cap0: int = BaseMeta.perm_lvl_cap(ld)
	ld["unlocked"] = [8, 9, 10]
	var cap3: int = BaseMeta.perm_lvl_cap(ld)
	ld["unlocked"] = [8, 9, 10, 11]
	var cap4: int = BaseMeta.perm_lvl_cap(ld)
	var many: Array = []
	for i in BaseMeta.N:
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
	for i in BaseMeta.N:
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
			r_ok = r_ok and absf(off.length() - float(S2.spawn_r())) < 40.0
			if S2.wave == 1:
				sectors[posmod(int(floor(rad_to_deg(off.angle()) / 90.0)), 4)] = true
		var lw: Dictionary = S2.last_wave_spawned
		if not lw.is_empty() and not seen.has(int(lw["wave"])):
			seen[int(lw["wave"])] = true
			tot_ok = tot_ok and int((last_tele[int(lw["wave"])] as Dictionary)["total"]) == int(lw["n"])
	_check("PC-E5 wave_telegraph precedes wave_start by pc_telegraph_s", order_ok and lead_ok and start_t.size() >= 25)
	_check("FB1 telegraph carries total/boss, no quadrants", schema_ok and tele.has(1) and tele.has(25))
	_check("FB1 telegraph total == actual spawns per wave", tot_ok and seen.size() >= 10)
	_check("FB1 no lanes: wave 1 spawns on all 4 sides, on the spawn ring", sectors.size() == 4 and r_ok)
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


## (r, c) in the legacy 7x7 coordinates (Core at (3,3)) -> run board index
## (FEEDBACK-1: 11x11 board, Core at (5,5); rings are unchanged by the shift).
func _rc(r: int, c: int) -> int:
	return (r + 2) * TowerState.SIDE + (c + 2)


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
	_adds(S, [on1, on2, off])
	var fev: Array = []
	S._fire(0.01, fev)
	_sync(S, [on1, on2, off])
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
	_adds(S, [heavy])
	fev = []
	S._fire(0.01, fev)
	_sync(S, [heavy])
	_check("PC-E3 flak cannot hit ground", is_equal_approx(float(heavy["hp"]), 999.0))
	var prey: Dictionary = _enemy("drone", fpos)
	S.add_enemy(prey)
	S.cooldowns[r1] = 0.0
	S._fire(0.01, fev)
	_sync(S, [prey, heavy])
	_check("PC-E3 flak x2.5 vs flyers", is_equal_approx(999.0 - float(prey["hp"]), 8.0 * 1.35 * 2.5 * TowerState.bld_dmg()) and is_equal_approx(float(heavy["hp"]), 999.0))
	var cw: Dictionary = _weapon(S, "flak").duplicate()
	cw["crit"] = 1.0
	S.stats["weapons"] = [cw]
	var ce: Dictionary = _enemy("drone", TowerState.slot_pos(r1) + Vector2(0, -100))
	S.set_enemies([ce])
	S.cooldowns[r1] = 0.0
	fev = []
	S._fire(0.01, fev)
	var dm: Array = _evts(fev, "dmg")
	_sync(S, [ce])
	_check("PC-E3 crit hit doubles dmg + flags the event", dm.size() == 1 and bool((dm[0] as Dictionary).get("crit", false)) and is_equal_approx(999.0 - float(ce["hp"]), 2.0 * 2.5 * float(cw["dmg"])))
	S = _open_run()
	S.packs = {"pk_crit": 2}
	S.recompute()
	_check("PC-E3 Precision packs: +8% crit each (global)", is_equal_approx(float(S.stats["crit"]), 0.16))
	# FEEDBACK-1 (deliberate): lane walls are gone. Every building has HP and
	# enemies attack buildings standing in their way before the Core; the
	# Barricade is the dedicated high-HP blocker (200 HP x1.35^(L-1) x enemy
	# dmg growth; others 40 HP). Destroyed = lost for the run.
	S = _open_run()
	S.slots[r2] = {"id": "barricade", "perm": 0, "run": 2}
	S.slots[_rc(3, 1)] = {"id": "mine", "perm": 0, "run": 1}
	S.recompute()
	S.stats["weapons"] = []
	var whp: float = 200.0 * 1.35
	_check("FB1 barricade HP 200 x1.35/lv, other buildings 40", is_equal_approx(S.bld_max(r2), whp) and is_equal_approx(float(S.bld_hp[r2]), whp) and is_equal_approx(S.bld_max(_rc(3, 1)), 40.0) and S.bld_max(_rc(3, 3)) == 0.0)
	var wn: Dictionary = _enemy("drone", TowerState.slot_pos(r2) + Vector2(0, -60))
	wn["dmg"] = 10.0
	var ws: Dictionary = _enemy("drone", TowerState.CENTER + Vector2(0, 150))
	S.set_enemies([wn, ws])
	var bev: Array = []
	for k in 40:
		S._move_enemies(0.1, bev)
	_sync(S, [wn, ws])
	_check("FB1 enemy stops at a building in its way and attacks it", (wn["pos"] as Vector2).distance_to(TowerState.slot_pos(r2)) > TowerState.CELL * 0.5 and _evts(bev, "bld_hit").size() >= 3 and float(S.bld_hp[r2]) < whp and float(S.bld_hp[r2]) > 0.0)
	_check("FB1 an unblocked enemy walks on to the Core", (ws["pos"] as Vector2).distance_to(TowerState.CENTER) <= TowerState.STOP_R + 0.01)
	wn["dmg"] = 5000.0
	_push(S, wn)
	bev = []
	for k in 12:
		S._move_enemies(0.1, bev)
	_check("FB1 a building at 0 HP is destroyed and lost for the run", _evts(bev, "building_destroyed").size() == 1 and S.id_at(r2) == "" and S.bld_lost == ["barricade"] and float(S.bld_hp[r2]) == 0.0)
	_sync(S, [wn])
	var p0: Vector2 = wn["pos"]
	S._move_enemies(0.5, [])
	_sync(S, [wn])
	_check("FB1 the attacker moves on after the building falls", (wn["pos"] as Vector2).distance_to(TowerState.CENTER) < p0.distance_to(TowerState.CENTER))
	# Wave start repairs pc_bld_wave_heal (50%) of max HP; HP grows with the wave.
	S.set_enemies([])
	var mi: int = _rc(3, 1)
	S.bld_hp[mi] = 1.0
	S.wave_t = S.wave_time - 0.001
	bev = S.tick(0.05)
	_check("FB1 wave start repairs 50% of building HP (x1.06 growth)", _evts(bev, "bld_repair").size() == 1 and is_equal_approx(S.bld_max(mi), 40.0 * 1.06) and absf(float(S.bld_hp[mi]) - (1.0 + (40.0 * 1.06 - 40.0) + 0.5 * 40.0 * 1.06)) < 0.01)
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
	# The permanent (meta) base keeps its own 7x7 indexing (FEEDBACK-1).
	var a7: int = 2 * 7 + 3
	var b7: int = 2 * 7 + 2
	var c7: int = 2 * 7 + 4
	var bs: Dictionary = BaseMeta.default_save()
	bs["coins"] = 1000
	BaseMeta.try_place(bs, a7, "gun")
	BaseMeta.try_place(bs, c7, "mine")
	_check("PC-E4 base move + swap", BaseMeta.try_move(bs, a7, b7) and String(BaseMeta.slot_of(bs, b7)["id"]) == "gun" and BaseMeta.try_move(bs, b7, c7) and String(BaseMeta.slot_of(bs, c7)["id"]) == "gun" and String(BaseMeta.slot_of(bs, b7)["id"]) == "mine" and not BaseMeta.try_move(bs, c7, 0))


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
	_check("PC-E6 Haste: enemy speed +25%", is_equal_approx(float(S.enemy_list()[0]["spd"]), 45.0 * 1.25))
	S = _mod_run(["swarm"])
	S.spawn_hold = true
	S._spawn("drone", [])
	var p0: int = int(S0._build_plan(3, 0.0)["entries"].size())
	var p1: int = int(S._build_plan(3, 0.0)["entries"].size())
	_check("PC-E6 Swarm: -30% HP each, +60% count", is_equal_approx(float(S.enemy_list()[0]["hp"]), 6.0 * 0.7 * TowerState.difficulty_hp()) and float(p1) >= 1.5 * float(p0) and float(p1) <= 1.7 * float(p0))
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
	var mev: Array = E.tick(0.05)
	var mo: Array = _evts(mev, "mutation_offer")
	_check("PC-E7 mutation offer at wave 25 (3 distinct)", E.wave == 25 and mo.size() == 1 and E.mutation_offer.size() == 3 and E.mutation_offer[0] != E.mutation_offer[1] and E.mutation_offer[1] != E.mutation_offer[2] and is_equal_approx(E.time_scale(), 1.0))   # FB1: sim stays live
	E.mutation_offer = ["m_vigor", "m_rush", "m_horde"]
	var cm0: float = E.run_coin_mult()
	var tk: Array = E.choose_mutation(0)
	E._spawn("drone", [])
	var vh: float = float(_last(E)["hp"]) / E.scale()
	_check("PC-E7 mutation pays +15% coins and buffs enemies", _evts(tk, "mutation_taken").size() == 1 and is_equal_approx(E.run_coin_mult(), cm0 * 1.15) and is_equal_approx(vh, 6.0 * 1.2 * TowerState.difficulty_hp()) and E.mutation_offer.is_empty())
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
	BaseMeta.try_place(sp, 2 * 7 + 3, "gun")   # meta base: 7x7 index
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
	# The v2 -> v3 step alone (migrate(.., 3)); v4 is checked in _save_v4_stages.
	var m3: Dictionary = BaseMeta.migrate(v2, 3)
	var sl3: Dictionary = m3["slots"]
	var slot_ok: bool = String(sl3[str(_c(6))]["id"]) == "armory" and int(sl3[str(_c(6))]["lvl"]) == 4 and String(sl3[str(_c(7))]["id"]) == "gun" and String(sl3[str(_c(0))]["id"]) == "mine" and String(sl3[str(_c(24))]["id"]) == "vault" and sl3.size() == 4
	_check("PC-E9 v2 -> v3: version, cells offset (r+1,c+1)", int(m3["version"]) == 3 and slot_ok and _c(6) == 16 and _c(24) == 40)
	_check("PC-E9 v2 -> v3: unlocks land on ring 2", (m3["unlocked"] as Array) == [_c(0), _c(4), _c(24)] and BaseMeta.cell_ring(_c(0)) == 2)
	var m: Dictionary = BaseMeta.normalize(BaseMeta.migrate(v2))
	_check("PC-E9 v2 -> v4 keeps meta fields", int(m["coins"]) >= 4321 + 12 * BaseMeta.GEM_COINS and not m.has("gems") and int(m["runs"]) == 9 and int(m["best_wave_by_tier"]["1"]) == 44 and int(m["tier"]) == 2 and int(m["research"]["lvls"]["dmg"]) == 3 and int(m["stats"]["kills"]) == 999 and int(m["stats"]["bosses"]) == 4 and int(m["version"]) == 4)
	_check("PC-E9 v3 blocks filled", (m["history"] as Array).is_empty() and int(m["endless"]["best"]) == 0 and (m["stats"] as Dictionary).has("kills_by_kind"))
	_check("PC-E9 target modes remapped", String((m3["target_modes"] as Dictionary)[str(_c(7))]) == "first")
	_check("PC-E9 migrate is idempotent on v4", JSON.stringify(BaseMeta.migrate(m)) == JSON.stringify(m))
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(m)))
	_check("PC-E9 v4 JSON round-trip equality", JSON.stringify(rt) == JSON.stringify(m))
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
	_check("PC-E9 legacy save.json imports into slot 1 as v4 (base refunded)", int(imp["version"]) == 4 and int(imp["coins"]) == int(m["coins"]) and BaseMeta.slot_of(imp, _c(7)).is_empty() and Outpost.level_of(imp, "mill") == 1 and MetaSave.read_slot(2).get("coins", 0) == 222)
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
	_check("PC-E10 34 achievements, unique ids", AchievementDB.LIST.size() == 34 and AchievementDB.ids().size() == 34)
	var ring3: int = 0
	var full: Array = []
	for i in BaseMeta.N:
		if i != BaseMeta.CORE_SLOT and not BaseMeta.is_inner(i):
			full.append(i)
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
		"ACH_KILLS_100K": [{"stats": {"kills": 100000 * preload("res://Tune.gd").horde_mult()}}, [{"t": "meta"}], -1.0],
		"ACH_RING_3": [{"unlocked": [ring3]}, [{"t": "meta"}], -1.0],
		"ACH_FULL_BASE": [{"unlocked": full}, [{"t": "meta"}], -1.0],
		"ACH_ALL_SYNERGY": [{}, [{"t": "synergies", "n": AchievementDB.SYNERGY_TARGET}], -1.0],
		"ACH_ECO_ONLY": [{}, [{"t": "game_over", "wave": 30, "build": ["", "mine", "bounty"]}], -1.0],
		"ACH_NO_ECO": [{}, [{"t": "game_over", "wave": 60, "build": ["gun", "", "armory"]}], -1.0],
		"ACH_LABS_MAX": [{"research": {"lvls": {"speed": 3}, "running": []}}, [{"t": "meta"}], -1.0],
		"ACH_FIRST_PART": [{"parts": {"next_uid": 2, "items": {"1": {"id": "f_glass", "lvl": 1, "stars": 0, "locked": false}}, "sets_completed": [], "specials_unlocked": []}}, [{"t": "meta"}], -1.0],
		"ACH_FULL_SET": [{"parts": {"next_uid": 1, "items": {}, "sets_completed": ["mint"], "specials_unlocked": []}}, [{"t": "meta"}], -1.0],
		"ACH_FIRST_REFORGE": [{"reforge": {"count": 1, "nodes": {}}}, [{"t": "meta"}], -1.0],
		"ACH_REFORGE_5": [{"reforge": {"count": 5, "nodes": {}}}, [{"t": "meta"}], -1.0],
		"ACH_GEM_MINE": [{"outpost": {"buildings": {"1": {"id": "gemmine", "built": true}}, "plots": []}}, [{"t": "meta"}], -1.0],
		"ACH_COURIER": [{"stats": {"couriers": 1}}, [{"t": "meta"}], -1.0],
		"ACH_CORES_4": [{"cores": {"active": "bastion", "owned": ["bastion", "foundry", "lance", "tempest"], "levels": {}}}, [{"t": "meta"}], -1.0],
		"ACH_OUTPOST_FULL": [{"outpost": {"buildings": {}, "plots": [0, 1, 2, 3, 4, 5, 6, 7]}}, [{"t": "meta"}], -1.0],
		"ACH_INSIGHT_10": [{"insight": {"in_dmg": 6, "in_hp": 4}}, [{"t": "meta"}], -1.0],
		"ACH_SPECIAL_100": [{"stats": {"specials_cast": 100}}, [{"t": "meta"}], -1.0],
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
	_check("PC-E10 every achievement has a synthetic case", cases.size() == 34 and cases.keys().all(func(k: Variant) -> bool: return AchievementDB.ids().has(String(k))))
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
	_check("CORE normalize drops unknown ids, clamps levels, active falls back", Cores.active(bad) == "bastion" and Cores.owned(bad) == ["bastion", "lance"] and Cores.level(bad, "lance") == CoreDB.MAX_LVL)
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
	for i in [_rc(2, 2), _rc(2, 3), _rc(2, 4)]:
		T.slots[i] = {"id": "mine", "perm": 0, "run": 1}
	T.recompute()
	_check("CORE Steadfast: +1%/building x1.25 at L10 on Core dmg + cash", is_equal_approx(float(_weapon(T, "core")["dmg"]), 10.0 * pow(1.06, 9.0) * (1.0 + 0.03 * 1.25)) and is_equal_approx(float(T.stats["cash_ps"]), (2.0 * pow(1.04, 9.0) + 2.4) * (1.0 + 0.03 * 1.25)))
	var F = _core_run("foundry")
	F.tracks["eco"] = 2
	F.recompute()
	# FEEDBACK-1: Eco levels are 5x bigger (+25 cap; Compound +50 per level).
	_check("CORE Compound: interest cap +40 (+50 Compound) per Eco level", is_equal_approx(float(F.stats["interest_cap"]), 150.0 + 2.0 * 90.0) and is_equal_approx(float(F._draft_ctx("")["eco_mult"]), 1.5))
	var L = _core_run("lance")
	L.slots[_rc(2, 2)] = {"id": "gun", "perm": 0, "run": 1}
	L.recompute()
	_check("CORE Focus: buildings in Core range -10% rate", is_equal_approx(float(_weapon(L, "gun")["rate"]), 2.0 * 0.9))


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
	var S = _core_run("bastion")
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
	var S20 = _core_run("bastion", 20)
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
	S = _core_run("lance")
	S.spawn_hold = true
	var boss: Dictionary = _enemy("boss", TowerState.CENTER + Vector2(0, 300), 1.0e6)
	S.set_enemies([boss])
	S._fire(0.01, [])
	_sync(S, [boss])
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
	S = _core_run("bastion")
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
	S.draft = [Draft.card_for("pk_gambit", S._draft_ctx(""))]
	S.choose_card(0)
	S._spawn("drone", [])
	_check("DRAFT Gambit +40% dmg, enemies +15% HP", is_equal_approx(float(_weapon(S, "core")["dmg"]), dmg0 * 1.12 * 1.4) and is_equal_approx(float(_last(S)["hp"]), 6.0 * 1.15 * TowerState.difficulty_hp()))
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
	tr = []
	Troops.sync(tr, [{"slot": 6, "id": "hut_drone", "lvl": 1, "home": Vector2(0, 0), "anchor": Vector2(0, -100)}], {"cell_px": 78.0}, counter)
	var ground: Dictionary = _enemy("hauler", Vector2(0, -90), 500.0)
	ground["eid"] = 3
	var flyer: Dictionary = _enemy("drone", Vector2(60, -200), 500.0)
	flyer["eid"] = 4
	tq = _troop_q([ground, flyer])
	Troops.step(tr, tq[0], tq[1], 0.1, {"cell_px": 78.0})
	_check("TROOP drones hunt flyers first", int(tr[0]["tgt"]) == 4)
	tr[0]["hp"] = 1.0
	res = Troops.step(tr, tq[0], tq[1], 0.1, {"cell_px": 78.0})
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
	_check("COURIER spawn event, 2x drone HP, 3x speed", _evts(kev, "courier_spawn").size() == 1 and String(cour["kind"]) == "courier" and is_equal_approx(float(cour["max_hp"]), 12.0 * TowerState.difficulty_hp()) and is_equal_approx(float(cour["spd"]), 135.0))
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
	M._spawn("drone", [], Vector2.INF, true)
	_check("MARK marked enemy x3 HP + flag", bool(_last(M)["marked"]) and is_equal_approx(float(_last(M)["max_hp"]), 18.0 * TowerState.difficulty_hp()))   # FB1: x difficulty


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
	_reforge_stages()
	_save_v4_stages()


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
	_check("AC-13 2-piece active at 2 distinct members", int(Parts.set_counts(ms, "bastion").get("mint", 0)) == 2 and is_equal_approx(float(fx2.get("cash", 0.0)), 0.10) and not fx2.has("dividend") and Parts.any_set2(ms))
	var cev: Array = []
	for id in ["c_interest", "e_mintpress"]:
		var u2: String = Parts.uid_of(ms, String(id))
		for k in Parts.N_SLOTS:
			if Parts.fits(ms, u2, k) and String(Parts.preset(ms, "bastion")[k]) == "":
				cev.append_array(Parts.equip(ms, "bastion", k, u2))
				break
	var fx4: Dictionary = Parts.run_fx(ms, "bastion")
	_check("AC-13 4-piece active + full set unlocks Golden Ratio once", is_equal_approx(float(fx4.get("dividend", 0.0)), 0.20) and _evts(cev, "set_complete").size() == 1 and _evts(cev, "special_part_unlocked").size() == 1 and Parts.owns(ms, "golden_ratio") and (ms["parts"]["sets_completed"] as Array) == ["mint"])
	# Mint 4-piece Dividend: all damage scales with the Eco track (x1.20 at Eco 50).
	var dv := TowerState.new()
	dv.setup(7, ms.duplicate(true))
	var dv0: float = float(dv.stats["dmg_all"])
	dv.tracks["eco"] = 50
	dv.recompute()
	_check("AC-13 Mint 4-piece Dividend: +20% all damage at Eco 50", is_equal_approx(float(dv.stats["dmg_all"]) / dv0, 1.20), "%.4f" % (float(dv.stats["dmg_all"]) / dv0))
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
	_check("PART fx: plus x(1+0.08(L-1))x(1+0.05 stars), minus unscaled", is_equal_approx(float(gx["dmg"]), 0.40 * 1.4 * 1.05) and is_equal_approx(float(gx["core_hp"]), -0.18))
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
	_check("RUN Glass Cannon: +40% all dmg, -18% HP", is_equal_approx(float(_weapon(G, "core")["dmg"]), float(core0["dmg"]) * 1.40) and is_equal_approx(float(G.stats["max_hp"]), float(B.stats["max_hp"]) * 0.82))
	var T = _parts_run(["e_turbine", "f_ledgerframe"], "bastion", 40)
	var B40 = _parts_run([], "bastion", 40)
	_check("RUN Turbine + Ledger: flat cash/s, -dmg, -HP", float(T.stats["cash_ps"]) > float(B40.stats["cash_ps"]) and float(_weapon(T, "core")["dmg"]) < float(_weapon(B40, "core")["dmg"]) and float(T.stats["max_hp"]) < float(B40.stats["max_hp"]))
	var L = _parts_run(["b_longbore"], "bastion", 1)
	_check("RUN Long Bore: +0.72 range cells, -rate", is_equal_approx(float(_weapon(L, "core")["range_cells"]), float(core0["range_cells"]) + 0.72) and float(_weapon(L, "core")["rate"]) < float(core0["rate"]))
	var R = _parts_run(["e_railcore"], "bastion", 40)
	_check("RUN Rail Core: +42% Core dmg, no splash", is_equal_approx(float(_weapon(R, "core")["dmg"]), float(_weapon(B40, "core")["dmg"]) * 1.42) and is_equal_approx(float(_weapon(R, "core")["splash"]), 0.0))
	var C = _parts_run(["c_luckchip"], "bastion", 12)
	_check("RUN Luck Chip: +3 Luck", C.luck == 3)
	var Q = _parts_run(["c_quickcap"], "bastion", 12)
	_check("RUN Quick Cap: special cd x0.821, dmg x0.879", is_equal_approx(float(Q.mods["special_cd"]), 1.0 - 0.179) and is_equal_approx(float(Q.mods["special_dmg"]), 1.0 - 0.121))
	var H = _parts_run(["e_bastionheart"], "bastion", 20)
	# FEEDBACK-1: rings no longer open in a run; Bastion Heart's drawback is a
	# one-step-smaller grid (never below 3x3).
	var hsv: Dictionary = _parts_save(["e_bastionheart"], "bastion", 20)
	_equip_all(hsv, ["e_bastionheart"])
	hsv["research"]["lvls"]["grid"] = 2
	var H2 = TowerState.new()
	H2.setup(1234, hsv)
	_check("RUN Bastion Heart: grid one step smaller", H.grid_n == 3 and H2.grid_n == 5 and B.grid_n == 3)
	# Hunter Scope: bosses take more, normal enemies less (in _hit).
	var S = _parts_run(["c_scope"], "bastion", 12)
	var eb: Dictionary = _enemy("boss", Vector2(400, 400), 1000.0)
	var en: Dictionary = _enemy("drone", Vector2(400, 400), 1000.0)
	S._hit(S.add_enemy(eb), 100.0, [])
	S._hit(S.add_enemy(en), 100.0, [])
	_sync(S, [eb, en])
	_check("RUN Hunter Scope: +58% vs boss, -25% vs normal", is_equal_approx(float(eb["hp"]), 1000.0 - 158.0) and is_equal_approx(float(en["hp"]), 1000.0 - 75.0))
	# Mirror Hull: contact damage reflects.
	var M = _parts_run(["f_mirror"], "bastion", 12)
	var em: Dictionary = _enemy("drone", Vector2(400, 400), 1000.0)
	M._core_damage(10.0, [], "core_hit", em["pos"], M.add_enemy(em))
	_sync(M, [em])
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
	# Swarm 4-piece lifts the Queen Engine hold-fire (+13% all damage).
	var Sw = _parts_run(["f_hivecomb", "b_droneport", "c_pheromone", "e_queen"], "bastion", 40)
	_check("RUN Swarm 4-piece: Queen hold-fire lifted, +13% all damage", is_zero_approx(Sw.pf("queen_hold")) and is_equal_approx(Sw.pf("dmg"), 0.13) and Sw.pf("troop_ls") > 0.0)
	# Mint 4-piece Dividend in a run: all damage x(1 + 0.20 * Eco/cap);
	# FEEDBACK-1: the Eco cap is 8 now (was 50), so half = Eco 4.
	var Mi = _parts_run(["f_ledgerframe", "b_bounty", "c_interest", "e_mintpress"], "bastion", 40)
	var mi0: float = float(Mi.stats["dmg_all"])
	Mi.tracks["eco"] = 3
	Mi.recompute()
	_check("RUN Mint 4-piece Dividend: +10% all damage at half Eco (3/6)", is_equal_approx(float(Mi.stats["dmg_all"]) / mi0, 1.10), "%.4f" % (float(Mi.stats["dmg_all"]) / mi0))
	# interest_fast engine fx (was the Mint 4-piece until the AC-29 eco pass;
	# no data source carries it now, the mechanic stays covered): interest
	# every 15 s instead of per wave.
	Mi.pfx["interest_fast"] = 1
	Mi.spawn_hold = true
	Mi.wave_started = true
	Mi.cash = 100.0
	var iev: Array = []
	for k in 160:
		Mi._step(0.1, iev)
	_check("RUN interest_fast fx pays interest every 15 s", _evts(iev, "interest").size() == 1)
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
	# FEEDBACK-1: gems are gone — Supply/Vault open with Keys only.
	_check("CRATE refused when unaffordable", Crates.open(sp, "supply", "keys", rng3).is_empty() and Crates.open(sp, "supply", "gems", rng3).is_empty() and Crates.open(sp, "field", "coins", rng3).is_empty() and Crates.open(sp, "field", "token", rng3).is_empty())
	sp["keys"] = 1
	var sev: Array = Crates.open(sp, "supply", "keys", rng3)
	_check("CRATE Supply: 2 parts for 1 Key", (sev[0]["rarities"] as Array).size() == 2 and int(sp["keys"]) == 0 and int(sp["stats"]["crates_opened"]) == 1)
	var vr: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	vr["keys"] = 4 * 50
	var vok: bool = true
	for k in 50:
		var vv: Array = Crates.open(vr, "vault", "keys", rng3)
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
	same1["keys"] = 10
	same2["keys"] = 10
	var ra := RandomNumberGenerator.new()
	var rb := RandomNumberGenerator.new()
	ra.seed = 5
	rb.seed = 5
	_check("CRATE opens are seeded (same seed -> same parts)", JSON.stringify(Crates.open(same1, "supply", "keys", ra)) == JSON.stringify(Crates.open(same2, "supply", "keys", rb)))


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
	_check("AC-17 quantity limit (Relay 1: 2 Mills, 0 Key Forges)", _op_build(sv, "mill", 4, 6) != "" and Outpost.place_error(sv, "mill", 4, 2, 0) == "limit" and Outpost.place_error(sv, "keyforge", 4, 2, 0) == "limit")
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
	var sv: Dictionary = _parts_save(["f_glass", "b_hollow"], "bastion", 20)
	_equip_all(sv, ["f_glass", "b_hollow"])
	sv["coins"] = 50000
	sv["keys"] = 3
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
	var gu: String = Parts.uid_of(sv, "f_glass")
	(Parts.item(sv, gu) as Dictionary)["lvl"] = 4
	var mu: String = _op_build(sv, "mill", 4, 4)
	sv["outpost"]["buildings"][mu]["lvl"] = 3
	sv["outpost"]["relay_lvl"] = 3
	sv["outpost"]["plots"] = [0]
	Outpost.place_decor(sv, "dc_tree", 7, 2, 0)
	Outpost.save_blueprint(sv, "Mine")
	sv["research"]["lvls"]["dmg"] = 5
	sv["insight"]["in_dmg"] = 4
	sv["cards"]["owned"] = {"c_dmg": {"lvl": 2, "copies": 0}}
	sv["tier"] = 1
	var c_before: int = int(sv["coins"])
	var ev: Array = Reforge.reforge(sv, OT0 + 100)
	var ok_reset: bool = int(sv["coins"]) == 0 and Cores.level(sv, "bastion") == 1 and int(Parts.item(sv, gu)["lvl"]) == 1 and int(sv["outpost"]["buildings"][mu]["lvl"]) == 1 and int(sv["outpost"]["relay_lvl"]) == 1 and int(sv["research"]["lvls"]["dmg"]) == 0 and int(sv["tier"]) == 1 and Tiers.highest(sv) == 1
	_check("AC-21 resets: coins, Core levels, part levels, Outpost levels + Relay, research, tier", c_before > 0 and _evts(ev, "reforge").size() == 1 and ok_reset)
	var ok_keep: bool = Parts.owns(sv, "f_glass") and Parts.equipped(sv, "bastion").size() == 2 and (sv["outpost"]["plots"] as Array) == [0] and (sv["outpost"]["decor"] as Dictionary).size() == 1 and (sv["outpost"]["blueprints"] as Array).size() == 1 and int(sv["outpost"]["buildings"][mu]["x"]) == 4 and not sv.has("gems") and int(sv["keys"]) == 3 and int(sv["insight"]["in_dmg"]) == 4 and (sv["cards"]["owned"] as Dictionary).has("c_dmg") and int(sv["best_wave"]) == 39
	_check("AC-21 keeps: parts + presets, layout/plots/decor/blueprints, Keys, Insight, cards, best wave", ok_keep)
	_check("AC-21 part levels refund 50% Scrap", int(sv["scrap"]) == PartDB.invested("f_glass", 4) / 2)
	_check("AC-21 shards banked, count + cum, Lance unlocks, Core Cores", int(sv["shards"]) == sh1 and Reforge.count(sv) == 1 and int(sv["reforge"]["cum_shards"]) == sh1 and int(sv["reforge"]["coins_since"]) == 0 and Cores.is_owned(sv, "lance") and int(sv["stats"]["reforges"]) == 1)
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
	for id in ["bulwark_p", "prosperity", "starting_cash", "head_start", "wide_draft", "tempo", "builder2", "crate_luck", "shard_yield", "scrap_p", "outpost_p", "retain"]:
		Reforge.buy(sv, String(id))
	sv["cores"]["active"] = "bastion"
	var S = TowerState.new()
	S.setup(3, sv)
	var B = TowerState.new()
	B.setup(3, _parts_save(["f_glass", "b_hollow"], "bastion", 1))
	_equip_all(B.save, [])
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


## AC-22: v3 -> v4 migration fixture (a PC v3 save), idempotent, sanitize.
func _save_v4_stages() -> void:
	var v3: Dictionary = {
		"version": 3, "coins": 10000, "gems": 40, "core": {"dmg": 12, "hp": 9, "regen": 6},
		"slots": {"16": {"id": "gun", "lvl": 5}, "17": {"id": "mine", "lvl": 3}, "9": {"id": "mortar", "lvl": 2}},
		"unlocked": [8, 9, 10], "runs": 40, "best_wave": 52, "tier": 2, "best_wave_by_tier": {"1": 52, "2": 31},
		"labs": {"lvls": {"dmg": 7, "coin": 4, "offcap": 2}, "slots": 3, "running": [{"track": "hp", "to_lvl": 1, "start": OT0 - 100, "end": OT0 + 500}]},
		"cards": {"owned": {"c_dmg": {"lvl": 2, "copies": 1}}, "equipped": ["c_dmg"], "slots": 2},
		"last_seen": OT0 - 86400, "stats": {"kills": 5000, "bosses": 9}, "achievements": {"unlocked": {"ACH_FIRST_RUN": 5}, "missions_claimed": 3},
		"settings": {"music": 0.5, "sfx": 0.7, "mute": false}, "endless": {"best": 12}, "streak": {"day_idx": 3, "last_day": 5, "loops": 0},
		"cores": {"active": "bastion", "owned": ["bastion"], "levels": {"bastion": 3}}, "core_cores": 2, "scrap": 30, "keys": 1, "insight": {"in_dmg": 2},
		"part_drops": [{"rarity": "rare", "source": "boss"}],
	}
	var refund: int = BaseMeta.v3_base_refund(v3)
	var r_exp: int = BaseMeta.place_cost("gun") + BaseMeta.place_cost("mine") + BaseMeta.place_cost("mortar") + 3 * 500
	for l in range(1, 5):
		r_exp += BaseMeta.upgrade_cost(l)
	for l in range(1, 3):
		r_exp += BaseMeta.upgrade_cost(l)
	r_exp += BaseMeta.upgrade_cost(1)
	_check("AC-22 refund = purchases + upgrades + 500 per bought cell", refund == r_exp)
	var m: Dictionary = BaseMeta.normalize(BaseMeta.migrate(v3))
	# Bastion: 1 + floor(27 / 3) = 10; leftover dmg 12 -> levels 9..11, hp 9 -> none.
	var core_ref: int = BaseMeta.core_cost(9) + BaseMeta.core_cost(10) + BaseMeta.core_cost(11)
	_check("AC-22 refund coins credited (+ Core leftover, + 40 legacy gems as coins)", int(m["coins"]) == 10000 + refund + core_ref + 40 * BaseMeta.GEM_COINS)
	_check("AC-22 Bastion level per formula (1 + floor(sum/3))", Cores.level(m, "bastion") == 10 and int(m["core"]["dmg"]) == 0)
	var con: Dictionary = Outpost.connected(m["outpost"])
	var mill_ok: bool = false
	var hall_ok: bool = false
	for k in (m["outpost"]["buildings"] as Dictionary).keys():
		var b: Dictionary = m["outpost"]["buildings"][k]
		if String(b["id"]) == "mill":
			mill_ok = bool(b["built"]) and bool(con[k]) and int(b["lvl"]) == 1
		if String(b["id"]) == "research":
			hall_ok = bool(b["built"]) and bool(con[k]) and int(b["lvl"]) == 8
	_check("AC-22 Coin Mill + Research Hall placed and connected", mill_ok and hall_ok and (m["slots"] as Dictionary).is_empty() and (m["unlocked"] as Array).is_empty())
	_check("AC-22 Outpost starter credit = 25% of the refund (cap 50k)", int(m["outpost"]["credit"]) == mini(50000, refund / 4))
	_check("AC-22 research levels equal old labs; slots 3 -> Hall L8 (3 queues); running kept", int(m["research"]["lvls"]["dmg"]) == 7 and int(m["research"]["lvls"]["offcap"]) == 2 and Labs.slots(m) == 3 and (m["research"]["running"] as Array).size() == 1 and int(m["research"]["running"][0]["end"]) == OT0 + 500 and not m.has("labs"))
	_check("AC-22 keeps cards, tiers, stats, achievements, settings, endless, streak (gems -> coins)", not m.has("gems") and (m["cards"]["owned"] as Dictionary).has("c_dmg") and int(m["best_wave_by_tier"]["2"]) == 31 and int(m["stats"]["kills"]) == 5000 and (m["achievements"]["unlocked"] as Dictionary).has("ACH_FIRST_RUN") and is_equal_approx(float(m["settings"]["music"]), 0.5) and int(m["endless"]["best"]) == 12 and int(m["streak"]["day_idx"]) == 3)
	_check("AC-22 defaults: Bastion active, 1 free Field Crate, zero new keys", Cores.active(m) == "bastion" and Crates.tokens(m) == 1 and int(m["shards"]) == 0 and Parts.count(m) == 0 and Reforge.count(m) == 0)
	# No double offline pay: the first tick after migration only starts clocks.
	var away: Dictionary = Outpost.away_report(m, OT0)
	Outpost.tick(m, OT0)
	Outpost.tick(m, OT0 + 3600)
	_check("AC-22 no double offline pay (accrues from the migration time)", int(away["coins"]) == 0 and absf(float(Outpost.pending(m, OT0 + 3600)["coins"]) - OutpostDB.MILL_RATE * (1.0 + OutpostDB.MILL_TIER)) < 0.01)
	# Idempotent: migrating / normalizing again changes nothing.
	var m2: Dictionary = BaseMeta.normalize(BaseMeta.migrate(m))
	_check("AC-22 migration idempotent (v4 -> v4)", JSON.stringify(m2) == JSON.stringify(m) and int(BaseMeta.normalize(BaseMeta.normalize(BaseMeta.migrate(v3)))["coins"]) == 10000 + refund + core_ref + 40 * BaseMeta.GEM_COINS)
	_check("AC-22 v4 JSON round-trip", JSON.stringify(BaseMeta.normalize(JSON.parse_string(JSON.stringify(m)))) == JSON.stringify(m))
	# Sanitize: negative ints clamp, unknown part ids drop, uids stay unique.
	var bad: Dictionary = m.duplicate(true)
	bad["coins"] = -5
	bad["scrap"] = -1
	bad["parts"] = {"next_uid": 2, "items": {"1": {"id": "f_glass", "lvl": 99}, "2": {"id": "nope"}, "3": {"id": "f_glass"}, "4": {"id": "b_crit", "stars": 7}}}
	var bn: Dictionary = BaseMeta.normalize(bad)
	_check("AC-22 sanitize: clamps, unknown parts dropped, one item per id, uids unique", int(bn["coins"]) == 0 and int(bn["scrap"]) == 0 and Parts.count(bn) == 2 and int(Parts.item(bn, "1")["lvl"]) == 20 and int(Parts.item(bn, "4")["stars"]) == 2 and int(bn["parts"]["next_uid"]) == 5)
	_check("AC-22 v4 schema keys", int(m["version"]) == 4 and m.has("parts") and m.has("crates") and m.has("outpost") and m.has("research") and m.has("reforge") and m.has("shards") and m.has("cores") and m.has("insight"))
