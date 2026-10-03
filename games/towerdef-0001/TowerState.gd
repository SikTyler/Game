extends RefCounted
## Corehold rules engine — pure, seeded, headless. Owns the whole run: waves,
## enemies, weapon fire, economy (cash / XP / coins), the level-up draft and
## the 5x5 base. Every action returns an Array of event Dictionaries that the
## view replays; the view never owns a rule.
##
## Tradeoff (concept gate): the 24 slots are scarce and each holds eco OR
## defense. Eco compounds cash/XP (more picks, more upgrades) but gives up the
## firepower to survive the capped-but-climbing wave ramp and the boss spike
## every 10th wave.
##
## Concurrency contract: waves never pause. While a draft is open or a building
## is waiting to be placed, simulated time runs at SLOWMO (20%), not zero.

const BuildingDB := preload("res://data/BuildingDB.gd")
const EnemyDB := preload("res://data/EnemyDB.gd")
const Draft := preload("res://Draft.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const TuneRef := preload("res://Tune.gd")

const CENTER: Vector2 = Vector2(360, 470)
const CELL: float = 52.0
const CORE_SLOT: int = 12
const SPAWN_R: float = 420.0
const STOP_R: float = 150.0
const SLOWMO: float = 0.2
const MAX_LVL: int = 25
const MAX_ENEMIES: int = 220

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var save: Dictionary = {}
var slots: Array = []        # 25 × ({} | {id, perm, run})
var unlocked: Array = []     # 25 × bool
var cooldowns: Array = []    # 25 × float (core uses CORE_SLOT)
var enemies: Array = []      # {pos, hp, max_hp, spd, dmg, kind, atk_cd, slow_t, cash, xp, coin, size}
var stats: Dictionary = {}

var wave: int = 1
var wave_t: float = 0.0
var spawn_t: float = 0.5
var time_alive: float = 0.0
var hp: float = 100.0
var cash: float = 0.0
var xp: float = 0.0
var level: int = 1
var coins_run: float = 0.0
var kills: int = 0
var core_run_lvl: int = 0
var run_unlocks: int = 0
var draft: Array = []
var pending_place: String = ""
var over: bool = false

# Tunables (GF_TUNE overridable; defaults = shipped balance).
var wave_time: float = 25.0
var hp_growth: float = 1.12
var dmg_growth: float = 1.08
var spawn_base: float = 1.8
var spawn_decay: float = 0.93
var min_spawn: float = 0.45   # MAX spawn rate cap (≈2.2/s)
var xp_base: float = 6.0
var xp_growth: float = 1.3


func setup(seed_value: int, save_data: Dictionary) -> Array:
	rng.seed = seed_value
	save = save_data
	wave_time = TuneRef.num("wave_time", wave_time)
	hp_growth = TuneRef.num("hp_growth", hp_growth)
	dmg_growth = TuneRef.num("dmg_growth", dmg_growth)
	spawn_base = TuneRef.num("spawn_base", spawn_base)
	spawn_decay = TuneRef.num("spawn_decay", spawn_decay)
	min_spawn = TuneRef.num("min_spawn", min_spawn)
	xp_base = TuneRef.num("xp_base", xp_base)
	xp_growth = TuneRef.num("xp_growth", xp_growth)
	slots.clear()
	unlocked.clear()
	cooldowns.clear()
	for i in 25:
		var perm: Dictionary = BaseMeta.slot_of(save, i)
		if perm.is_empty():
			slots.append({})
		else:
			slots.append({"id": String(perm["id"]), "perm": int(perm["lvl"]), "run": 0})
		unlocked.append(BaseMeta.is_unlocked(save, i))
		cooldowns.append(0.0)
	enemies.clear()
	draft.clear()
	pending_place = ""
	wave = 1
	wave_t = 0.0
	spawn_t = 0.5
	time_alive = 0.0
	cash = 0.0
	xp = 0.0
	level = 1
	coins_run = 0.0
	kills = 0
	core_run_lvl = 0
	run_unlocks = 0
	over = false
	recompute()
	hp = float(stats["max_hp"])
	return [{"t": "run_start"}]


# ---------------------------------------------------------------- geometry
static func slot_pos(i: int) -> Vector2:
	return CENTER + Vector2(float(i % 5 - 2) * CELL, float(i / 5 - 2) * CELL)


static func neighbors(i: int) -> Array:
	var out: Array = []
	var x: int = i % 5
	var y: int = i / 5
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + int(dx)
			var ny: int = y + int(dy)
			if nx >= 0 and nx < 5 and ny >= 0 and ny < 5:
				out.append(ny * 5 + nx)
	return out


func lvl_at(i: int) -> int:
	var s: Dictionary = slots[i]
	if s.is_empty():
		return 0
	return mini(MAX_LVL, int(s["perm"]) + int(s["run"]))


func id_at(i: int) -> String:
	var s: Dictionary = slots[i]
	return "" if s.is_empty() else String(s["id"])


func is_free(i: int) -> bool:
	return i != CORE_SLOT and bool(unlocked[i]) and (slots[i] as Dictionary).is_empty()


# ------------------------------------------------------------------- stats
## The single pure source of every derived number.
func compute_stats() -> Dictionary:
	var core: Dictionary = save.get("core", {})
	var st: Dictionary = {
		"max_hp": 100.0 + 25.0 * float(core.get("hp", 0)),
		"regen": 0.5 + 0.3 * float(core.get("regen", 0)),
		"cash_ps": 0.0,
		"xp_mult": 1.0,
		"bounty_mult": 1.0,
		"weapons": [],
	}
	# Armory multiplier per slot (weapons + core).
	var arm: Array = []
	for i in 25:
		arm.append(1.0)
	for i in 25:
		if id_at(i) == "armory":
			for n in neighbors(i):
				arm[n] = float(arm[n]) + 0.25 * float(lvl_at(i))
	for i in 25:
		var id: String = id_at(i)
		var L: float = float(lvl_at(i))
		match id:
			"bulwark":
				st["max_hp"] = float(st["max_hp"]) + 40.0 * L
				st["regen"] = float(st["regen"]) + 0.5 * L
			"mine":
				st["cash_ps"] = float(st["cash_ps"]) + 1.2 * L
			"oilmill":
				var adj_mines: int = 0
				for n in neighbors(i):
					if id_at(n) == "mine":
						adj_mines += 1
				st["xp_mult"] = float(st["xp_mult"]) + 0.25 * L + 0.15 * L * float(adj_mines)
			"bounty":
				st["bounty_mult"] = float(st["bounty_mult"]) + 0.4 * L
			"gun":
				(st["weapons"] as Array).append({"slot": i, "kind": "gun", "dmg": (3.0 + 2.0 * L) * float(arm[i]), "rate": 1.0 + 0.12 * L, "range": 220.0})
			"mortar":
				(st["weapons"] as Array).append({"slot": i, "kind": "mortar", "dmg": (8.0 + 5.0 * L) * float(arm[i]), "rate": 0.45, "range": 320.0, "splash": 55.0 + 4.0 * L})
			"tesla":
				(st["weapons"] as Array).append({"slot": i, "kind": "tesla", "dmg": (2.0 + 1.2 * L) * float(arm[i]), "rate": 0.9, "range": 190.0, "chains": mini(6, 2 + int(L) / 2)})
	var core_dmg: float = 5.0 * (1.0 + 0.25 * float(core.get("dmg", 0))) * (1.0 + 0.25 * float(core_run_lvl)) * float(arm[CORE_SLOT])
	(st["weapons"] as Array).append({"slot": CORE_SLOT, "kind": "core", "dmg": core_dmg, "rate": 1.4, "range": 280.0})
	return st


func recompute() -> void:
	var old_max: float = float(stats.get("max_hp", 0.0))
	stats = compute_stats()
	var new_max: float = float(stats["max_hp"])
	if old_max > 0.0 and new_max > old_max:
		hp += new_max - old_max   # a new Bulwark heals by its bonus
	hp = minf(hp, new_max)


# ------------------------------------------------------------------ curves
func spawn_interval() -> float:
	return maxf(min_spawn, spawn_base * pow(spawn_decay, float(wave - 1)))


func scale() -> float:
	return pow(hp_growth, float(wave - 1))


func xp_need() -> float:
	return xp_base * pow(xp_growth, float(level - 1))


func upgrade_cost(i: int) -> int:
	if i == CORE_SLOT:
		return int(8.0 * pow(1.5, float(core_run_lvl)))
	return int(8.0 * pow(1.55, float(maxi(0, lvl_at(i) - 1))))


func unlock_cost() -> int:
	return int(40.0 * pow(1.6, float(run_unlocks)))


func time_scale() -> float:
	return SLOWMO if (draft.size() > 0 or pending_place != "") else 1.0


# ------------------------------------------------------------------ tick
func tick(delta: float) -> Array:
	var ev: Array = []
	if over:
		return ev
	var dt: float = delta * time_scale()
	time_alive += dt
	wave_t += dt
	if wave_t >= wave_time:
		wave_t -= wave_time
		wave += 1
		coins_run += float(wave)
		ev.append({"t": "wave", "wave": wave})
		if wave % 10 == 0:
			_spawn("boss", ev)
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t += spawn_interval()
		_spawn(_roll_kind(), ev)
	cash += float(stats["cash_ps"]) * dt
	hp = minf(float(stats["max_hp"]), hp + float(stats["regen"]) * dt)
	_move_enemies(dt, ev)
	_fire(dt, ev)
	_reap(ev)
	_check_level(ev)
	if hp <= 0.0 and not over:
		hp = 0.0
		over = true
		var coins: int = int(coins_run)
		BaseMeta.bank(save, coins, wave)
		ev.append({"t": "dead", "wave": wave, "coins": coins, "kills": kills})
	return ev


func _roll_kind() -> String:
	var r: float = rng.randf()
	if wave >= 5 and r < 0.15:
		return "hauler"
	if wave >= 3 and r < 0.40:
		return "skitter"
	return "drone"


func _spawn(kind: String, ev: Array) -> void:
	if enemies.size() >= MAX_ENEMIES:
		return
	var d: Dictionary = EnemyDB.get_def(kind)
	var sc: float = scale()
	var a: float = rng.randf() * TAU
	var e: Dictionary = {
		"kind": kind, "pos": CENTER + Vector2.from_angle(a) * SPAWN_R,
		"hp": float(d["hp"]) * sc, "max_hp": float(d["hp"]) * sc,
		"spd": float(d["spd"]), "dmg": float(d["dmg"]) * pow(dmg_growth, float(wave - 1)),
		"cash": float(d["cash"]), "xp": float(d["xp"]), "coin": float(d["coin"]),
		"size": float(d["size"]), "atk_cd": 0.0, "slow_t": 0.0,
	}
	enemies.append(e)
	if kind == "boss":
		ev.append({"t": "boss", "pos": e["pos"]})


func _move_enemies(dt: float, ev: Array) -> void:
	for e in enemies:
		var ed: Dictionary = e
		var pos: Vector2 = ed["pos"]
		var slow_t: float = float(ed["slow_t"])
		var mult: float = 0.55 if slow_t > 0.0 else 1.0
		ed["slow_t"] = maxf(0.0, slow_t - dt)
		var to_c: Vector2 = CENTER - pos
		var dist: float = to_c.length()
		if dist > STOP_R:
			var step: float = minf(dist - STOP_R, float(ed["spd"]) * mult * dt)
			ed["pos"] = pos + to_c.normalized() * step
		else:
			ed["atk_cd"] = float(ed["atk_cd"]) - dt
			if float(ed["atk_cd"]) <= 0.0:
				ed["atk_cd"] = 1.0
				hp -= float(ed["dmg"])
				ev.append({"t": "core_hit", "dmg": float(ed["dmg"]), "pos": ed["pos"]})


func _nearest(from: Vector2, rng_lim: float, exclude: Dictionary) -> int:
	var best: int = -1
	var best_d: float = rng_lim * rng_lim
	for k in enemies.size():
		if exclude.has(k):
			continue
		var ed: Dictionary = enemies[k]
		if float(ed["hp"]) <= 0.0:
			continue
		var p: Vector2 = ed["pos"]
		var d2: float = from.distance_squared_to(p)
		if d2 <= best_d:
			best_d = d2
			best = k
	return best


func _fire(dt: float, ev: Array) -> void:
	for w in stats["weapons"]:
		var wd: Dictionary = w
		var si: int = int(wd["slot"])
		var cd: float = float(cooldowns[si]) - dt
		if cd > 0.0:
			cooldowns[si] = cd
			continue
		var from: Vector2 = slot_pos(si)
		var tgt: int = _nearest(from, float(wd["range"]), {})
		if tgt < 0:
			cooldowns[si] = 0.0
			continue
		cooldowns[si] = cd + 1.0 / float(wd["rate"])
		var kind: String = wd["kind"]
		var dmg: float = float(wd["dmg"])
		var te: Dictionary = enemies[tgt]
		var tpos: Vector2 = te["pos"]
		match kind:
			"mortar":
				var rad: float = float(wd["splash"])
				for e in enemies:
					var ed: Dictionary = e
					if (ed["pos"] as Vector2).distance_to(tpos) <= rad:
						ed["hp"] = float(ed["hp"]) - dmg
				ev.append({"t": "shot", "kind": kind, "from": from, "to": tpos, "radius": rad})
			"tesla":
				var hit: Dictionary = {}
				var prev: Vector2 = from
				var cur: int = tgt
				var n: int = int(wd["chains"])
				while cur >= 0 and hit.size() < n:
					hit[cur] = true
					var ce: Dictionary = enemies[cur]
					ce["hp"] = float(ce["hp"]) - dmg
					ce["slow_t"] = 1.2
					var cpos: Vector2 = ce["pos"]
					ev.append({"t": "shot", "kind": kind, "from": prev, "to": cpos})
					prev = cpos
					cur = _nearest(cpos, 90.0, hit)
			_:
				te["hp"] = float(te["hp"]) - dmg
				ev.append({"t": "shot", "kind": kind, "from": from, "to": tpos})


func _reap(ev: Array) -> void:
	var alive: Array = []
	for e in enemies:
		var ed: Dictionary = e
		if float(ed["hp"]) > 0.0:
			alive.append(ed)
			continue
		var gain: float = float(ed["cash"]) * float(stats["bounty_mult"])
		cash += gain
		xp += float(ed["xp"]) * float(stats["xp_mult"])
		coins_run += float(ed["coin"])
		kills += 1
		ev.append({"t": "kill", "pos": ed["pos"], "cash": gain, "kind": ed["kind"]})
	enemies = alive


func _check_level(ev: Array) -> void:
	if draft.size() > 0 or pending_place != "":
		return
	if xp >= xp_need():
		xp -= xp_need()
		level += 1
		draft = Draft.offer(rng, slots, unlocked)
		ev.append({"t": "levelup", "level": level, "cards": draft.duplicate(true)})


# ---------------------------------------------------------------- actions
func choose_card(idx: int) -> Array:
	var ev: Array = []
	if idx < 0 or idx >= draft.size():
		return ev
	var card: Dictionary = draft[idx]
	draft.clear()
	var id: String = card["id"]
	if String(card["kind"]) == "plus":
		var best: int = -1
		for i in 25:
			if id_at(i) == id and (best < 0 or lvl_at(i) < lvl_at(best)):
				best = i
		if best >= 0:
			var s: Dictionary = slots[best]
			s["run"] = int(s["run"]) + 1
			recompute()
			ev.append({"t": "upgraded", "slot": best, "level": lvl_at(best)})
		_check_level(ev)
	else:
		pending_place = id
		ev.append({"t": "place_mode", "id": id})
	return ev


func place(i: int) -> Array:
	var ev: Array = []
	if pending_place == "" or i < 0 or i > 24 or not is_free(i):
		return ev
	slots[i] = {"id": pending_place, "perm": 0, "run": 1}
	cooldowns[i] = 0.0
	pending_place = ""
	recompute()
	ev.append({"t": "placed", "slot": i, "id": id_at(i)})
	_check_level(ev)
	return ev


## Spend cash on a temporary in-run level (building or the core).
func upgrade(i: int) -> Array:
	var ev: Array = []
	if over or i < 0 or i > 24:
		return ev
	if i != CORE_SLOT and (id_at(i) == "" or lvl_at(i) >= MAX_LVL):
		return ev
	var c: int = upgrade_cost(i)
	if cash < float(c):
		return ev
	cash -= float(c)
	if i == CORE_SLOT:
		core_run_lvl += 1
	else:
		var s: Dictionary = slots[i]
		s["run"] = int(s["run"]) + 1
	recompute()
	ev.append({"t": "upgraded", "slot": i, "level": core_run_lvl if i == CORE_SLOT else lvl_at(i)})
	return ev


## Spend cash to open an outer-ring plot for the rest of this run.
func unlock_plot(i: int) -> Array:
	var ev: Array = []
	if over or i < 0 or i > 24 or i == CORE_SLOT or bool(unlocked[i]):
		return ev
	var c: int = unlock_cost()
	if cash < float(c):
		return ev
	cash -= float(c)
	unlocked[i] = true
	run_unlocks += 1
	ev.append({"t": "unlocked", "slot": i})
	return ev


func free_slots() -> Array:
	var out: Array = []
	for i in 25:
		if is_free(i):
			out.append(i)
	return out
