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

	if fails.is_empty():
		print("SELFTEST OK")
		quit(0)
	else:
		print("SELFTEST FAIL: %d checks" % fails.size())
		quit(1)
