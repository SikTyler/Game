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
const Tiers := preload("res://Tiers.gd")
const Perks := preload("res://Perks.gd")
const PerkDB := preload("res://data/PerkDB.gd")

const CENTER: Vector2 = Vector2(360, 470)
const CELL: float = 52.0
const CORE_SLOT: int = 12
const SPAWN_R: float = 420.0
const STOP_R: float = 150.0
const SLOWMO: float = 0.2
const MAX_LVL: int = 25
const MAX_ENEMIES: int = 220
const SUBSTEP: float = 0.05
const CORE_RING: Array = [6, 7, 8, 11, 13, 16, 17, 18]
const ECO_IDS: Array = ["mine", "oilmill", "bounty", "vault"]

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

# Meta modifiers (BaseMeta.run_mods at setup; SPEC B1).
var mods: Dictionary = {}
var tier: int = 1
var hp_mult: float = 1.0          # enemy hp & dmg
var tier_coin_mult: float = 1.0
var coin_mult: float = 1.0        # tier × (1 + lab_coin + card_coin)
var dmg_mult: float = 1.0
var max_hp_mult: float = 1.0
var cash_mult: float = 1.0
var xp_mod: float = 1.0
var boss_every: int = 10
var allow_new_bldg: bool = false
var speed: float = 1.0            # game-speed multiplier (B2)
var rerolls_left: int = 0
var wind_hp: float = 0.0
var wind_used: bool = false
var skip_chance: float = 0.0
var now_unix: int = 0             # injected "now" stamped into the save at bank

# Run economy bookkeeping (B3).
var cash_earned: float = 0.0
var coins_wave: float = 0.0
var coins_kill: float = 0.0
var coins_boss: float = 0.0
var gems_run: int = 0
var boss_gem_awards: int = 0

# Perks (B7).
var perks_taken: Array = []
var perk_offer: Array = []
var perk_pending: int = 0

# Tunables (GF_TUNE overridable; defaults = shipped balance).
var wave_time: float = 25.0
var hp_growth: float = 1.12
var dmg_growth: float = 1.08
var spawn_base: float = 1.8
var spawn_decay: float = 0.93
var min_spawn: float = 0.45   # MAX spawn rate cap (≈2.2/s)
var xp_base: float = 6.0
var xp_growth: float = 1.3


func setup(seed_value: int, save_data: Dictionary, now: int = 0) -> Array:
	rng.seed = seed_value
	save = save_data
	now_unix = now
	_apply_mods(BaseMeta.run_mods(save))
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
	cash = float(int(mods.get("start_cash", 0)))
	xp = 0.0
	level = 1
	coins_run = 0.0
	kills = 0
	core_run_lvl = 0
	run_unlocks = 0
	over = false
	wind_used = false
	cash_earned = 0.0
	coins_wave = 0.0
	coins_kill = 0.0
	coins_boss = 0.0
	gems_run = 0
	boss_gem_awards = 0
	perks_taken.clear()
	perk_offer.clear()
	perk_pending = 0
	stats = {}
	recompute()
	hp = float(stats["max_hp"])
	return [{"t": "run_start", "tier": tier, "speed": speed}]


## SPEC B1: fold the meta bundle into run multipliers. TowerState never reads
## labs or cards directly.
func _apply_mods(m: Dictionary) -> void:
	mods = m
	var cards: Dictionary = m.get("cards", {})
	tier = int(m.get("tier", 1))
	hp_mult = float(m.get("hp_mult", 1.0))
	tier_coin_mult = float(m.get("coin_mult", 1.0))
	coin_mult = tier_coin_mult * (1.0 + float(m.get("lab_coin", 0.0)) + float(cards.get("coin", 0.0)))
	dmg_mult = (1.0 + float(m.get("lab_dmg", 0.0))) * (1.0 + float(cards.get("dmg", 0.0)))
	max_hp_mult = (1.0 + float(m.get("lab_hp", 0.0))) * (1.0 + float(cards.get("hp", 0.0)))
	cash_mult = 1.0 + float(cards.get("cash", 0.0))
	xp_mod = 1.0 + float(m.get("lab_xp", 0.0)) + float(cards.get("xp", 0.0))
	boss_every = maxi(1, int(m.get("boss_every", 10)))
	allow_new_bldg = bool(m.get("allow_new_bldg", false))
	speed = maxf(0.1, float(m.get("speed", 1.0)))
	rerolls_left = int(m.get("rerolls", 0)) + int(cards.get("reroll", 0))
	wind_hp = float(cards.get("wind_hp", 0.0))
	skip_chance = float(cards.get("skip_chance", 0.0))


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
## The single pure source of every derived number. Also returns `links`
## ([a, b, "S#"], a = bonus source, b = receiver) for the view to draw.
func compute_stats() -> Dictionary:
	var core: Dictionary = save.get("core", {})
	var st: Dictionary = {
		"max_hp": 100.0 + 25.0 * float(core.get("hp", 0)),
		"regen": 0.5 + 0.3 * float(core.get("regen", 0)),
		"cash_ps": 0.0,
		"xp_mult": 1.0,
		"bounty_mult": 1.0,
		"weapons": [],
		"vaults": [],
		"links": [],
		"dr": 0.0,
	}
	var links: Array = st["links"]
	var arm_cap: float = TuneRef.num("armory_cap", 1.0)
	# Armory multiplier per slot (weapons + core), capped per target (AC-21).
	var arm: Array = []
	for i in 25:
		arm.append(1.0)
	for i in 25:
		if id_at(i) == "armory":
			for n in neighbors(i):
				arm[n] = float(arm[n]) + 0.25 * float(lvl_at(i))
	for i in 25:
		arm[i] = minf(1.0 + arm_cap, float(arm[i]))
	# Aegis (S5): per-slot fire-rate bonus for weapons, output penalty for eco.
	var aeg_rate: Array = []
	var eco_pen: Array = []
	for i in 25:
		aeg_rate.append(0.0)
		eco_pen.append(1.0)
	var aegis_dr: float = 0.0
	var pen: float = TuneRef.num("aegis_eco_pen", 0.15)
	for i in 25:
		if id_at(i) != "aegis":
			continue
		var La: float = float(lvl_at(i))
		aegis_dr += TuneRef.num("aegis_dr", 0.04) * La
		for n in neighbors(i):
			var nid: String = id_at(n)
			if BuildingDB.cat_of(nid) == "weapon":
				aeg_rate[n] = float(aeg_rate[n]) + TuneRef.num("aegis_rate", 0.10) * La
				links.append([i, n, "S5"])
			elif ECO_IDS.has(nid) and float(eco_pen[n]) >= 1.0:
				eco_pen[n] = 1.0 - pen
				links.append([i, n, "S5"])
	var bulwark_dr: float = 0.0
	var mine_scale: float = 1.0 + TuneRef.num("mine_wave_scale", 0.03) * float(wave - 1)
	for i in 25:
		var id: String = id_at(i)
		var L: float = float(lvl_at(i))
		var ep: float = float(eco_pen[i])
		match id:
			"bulwark":
				st["max_hp"] = float(st["max_hp"]) + 40.0 * L
				st["regen"] = float(st["regen"]) + 0.5 * L
				if CORE_RING.has(i):
					bulwark_dr += 0.03 * L
					links.append([i, CORE_SLOT, "S3"])
			"mine":
				st["cash_ps"] = float(st["cash_ps"]) + 1.2 * L * mine_scale * ep
			"oilmill":
				var adj_mines: int = 0
				for n in neighbors(i):
					if id_at(n) == "mine":
						adj_mines += 1
				st["xp_mult"] = float(st["xp_mult"]) + (0.25 * L + 0.15 * L * float(adj_mines)) * ep
			"bounty":
				st["bounty_mult"] = float(st["bounty_mult"]) + 0.4 * L * ep
			"vault":
				var cap: float = TuneRef.num("vault_cap", 40.0) * L
				for n in neighbors(i):
					if id_at(n) == "bounty":
						cap *= 1.5
						links.append([n, i, "S4"])
						break
				(st["vaults"] as Array).append({"slot": i, "rate": TuneRef.num("vault_rate", 0.04) * L * ep, "cap": cap * ep})
			"gun":
				var mine_lv: int = 0
				for n in neighbors(i):
					if id_at(n) == "mine":
						mine_lv += lvl_at(n)
						links.append([n, i, "S1"])
				var ammo: float = minf(0.5, 0.05 * float(mine_lv))
				(st["weapons"] as Array).append({"slot": i, "kind": "gun", "dmg": (3.0 + 2.0 * L) * float(arm[i]), "rate": (1.0 + 0.12 * L) * (1.0 + ammo + float(aeg_rate[i])), "range": 220.0})
			"mortar":
				var teslas: Array = []
				for n in neighbors(i):
					if id_at(n) == "tesla":
						teslas.append(n)
						links.append([n, i, "S2"])
				(st["weapons"] as Array).append({"slot": i, "kind": "mortar", "dmg": (8.0 + 5.0 * L) * float(arm[i]), "rate": 0.45 * (1.0 + float(aeg_rate[i])), "range": 320.0, "splash": 55.0 + 4.0 * L, "teslas": teslas})
			"tesla":
				(st["weapons"] as Array).append({"slot": i, "kind": "tesla", "dmg": (2.0 + 1.2 * L) * float(arm[i]), "rate": 0.9 * (1.0 + float(aeg_rate[i])), "range": 190.0, "chains": mini(6, 2 + int(L) / 2)})
	var core_dmg: float = 5.0 * (1.0 + 0.25 * float(core.get("dmg", 0))) * (1.0 + 0.25 * float(core_run_lvl)) * float(arm[CORE_SLOT])
	(st["weapons"] as Array).append({"slot": CORE_SLOT, "kind": "core", "dmg": core_dmg, "rate": 1.4, "range": 280.0})
	# Meta multipliers (B1), then perks (B7), then hard caps.
	st["max_hp"] = float(st["max_hp"]) * max_hp_mult
	st["cash_ps"] = float(st["cash_ps"]) * cash_mult
	st["xp_mult"] = float(st["xp_mult"]) * xp_mod
	for w in st["weapons"]:
		var wd: Dictionary = w
		wd["dmg"] = float(wd["dmg"]) * dmg_mult
	Perks.apply(st, perks_taken)
	st["cash_ps"] = float(st["cash_ps"]) * float(st["perk_cash"])
	var gun_cap: float = TuneRef.num("gun_rate_cap", 2.5)
	for w in st["weapons"]:
		var wd2: Dictionary = w
		if String(wd2["kind"]) == "gun":
			wd2["rate"] = minf(gun_cap, float(wd2["rate"]))
	st["dr_aegis"] = minf(0.32, aegis_dr)
	st["dr_bulwark"] = minf(0.30, bulwark_dr)
	st["dr"] = minf(TuneRef.num("dr_cap", 0.6), float(st["dr_aegis"]) + float(st["dr_bulwark"]))
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
	var pm: float = float(stats.get("perk_spawn", 1.0))
	return maxf(min_spawn, spawn_base * pow(spawn_decay, float(wave - 1))) * pm


func scale() -> float:
	return pow(hp_growth, float(wave - 1))


func xp_need() -> float:
	return xp_base * pow(xp_growth, float(level - 1))


func upgrade_cost(i: int) -> int:
	var pm: float = float(stats.get("perk_upgrade_cost", 1.0))
	if i == CORE_SLOT:
		return int(8.0 * pow(1.5, float(core_run_lvl)) * pm)
	return int(8.0 * pow(1.55, float(maxi(0, lvl_at(i) - 1))) * pm)


func unlock_cost() -> int:
	return int(40.0 * pow(1.6, float(run_unlocks)))


func time_scale() -> float:
	return SLOWMO if (draft.size() > 0 or pending_place != "" or perk_offer.size() > 0) else 1.0


## Coins multiplier for everything earned this run (tier × lab × card × perks).
func run_coin_mult() -> float:
	return coin_mult * float(stats.get("perk_coin", 1.0))


func run_cash_mult() -> float:
	return cash_mult * float(stats.get("perk_cash", 1.0))


# ------------------------------------------------------------------ tick
## SPEC B2: `delta` is real time; the run advances delta*speed of game time in
## n = ceil(d / SUBSTEP) equal sub-steps so results are speed-invariant.
func tick(delta: float) -> Array:
	var ev: Array = []
	if over:
		return ev
	var d: float = maxf(0.0, delta) * speed
	var n: int = maxi(1, int(ceil(d / SUBSTEP - 0.000001)))
	var sub: float = d / float(n)
	for k in n:
		if over:
			break
		_step(sub, ev)
	return ev


func _step(sub: float, ev: Array) -> void:
	var dt: float = sub * time_scale()
	time_alive += dt
	wave_t += dt
	if wave_t >= wave_time:
		wave_t -= wave_time
		_wave_end(ev)
		_advance_wave(ev)
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t += spawn_interval()
		_spawn(_roll_kind(), ev)
	var cg: float = float(stats["cash_ps"]) * dt
	cash += cg
	cash_earned += cg
	hp = minf(float(stats["max_hp"]), hp + float(stats["regen"]) * dt)
	_move_enemies(dt, ev)
	_fire(dt, ev)
	_reap(ev)
	_check_queue(ev)
	if hp <= 0.0 and not over:
		_on_death(ev)


## Vault interest on held cash (B5), paid before the next wave starts.
func _wave_end(ev: Array) -> void:
	var held: float = cash
	for v in stats.get("vaults", []):
		var vd: Dictionary = v
		var amt: float = minf(held * float(vd["rate"]), float(vd["cap"]))
		if amt <= 0.0:
			continue
		cash += amt
		cash_earned += amt
		ev.append({"t": "interest", "amt": amt, "slot": int(vd["slot"])})


func _wave_coins(w: int, frac: float) -> float:
	var c: float = float(w) * run_coin_mult() * frac
	coins_run += c
	coins_wave += c
	return c


func _enter_wave(w: int) -> void:
	wave = w
	if wave % maxi(1, TuneRef.int_of("perk_every", 5)) == 0 and not Perks.available(perks_taken).is_empty():
		perk_pending += 1


func _advance_wave(ev: Array) -> void:
	_enter_wave(wave + 1)
	# Wave Skip card (B8): this wave is skipped (50% coins, no kills) and the
	# run jumps straight to the next one.
	if skip_chance > 0.0 and rng.randf() < skip_chance:
		var skipped: int = wave
		var c: float = _wave_coins(skipped, 0.5)
		_enter_wave(wave + 1)
		ev.append({"t": "wave_skip", "skipped": skipped, "wave": wave, "coins": c})
	_wave_coins(wave, 1.0)
	recompute()   # mine output scales with wave
	ev.append({"t": "wave", "wave": wave})
	if wave % boss_every == 0:
		_spawn("boss", ev)


func _on_death(ev: Array) -> void:
	if wind_hp > 0.0 and not wind_used:
		wind_used = true
		hp = float(stats["max_hp"]) * wind_hp
		ev.append({"t": "revive", "hp": hp})
		return
	hp = 0.0
	over = true
	var cashout: int = int(floor(TuneRef.num("cashout_frac", 0.02) * cash_earned * tier_coin_mult))
	var coins: int = int(coins_run) + cashout
	var bd: Dictionary = {
		"wave": int(coins_wave), "kills": int(coins_kill), "boss": int(coins_boss),
		"cashout": cashout, "mult": run_coin_mult(), "tier": tier, "gems": gems_run,
	}
	ev.append({"t": "game_over", "wave": wave, "coins": coins, "kills": kills, "cash_earned": int(cash_earned), "breakdown": bd, "perks": perks_taken.duplicate()})
	ev.append_array(BaseMeta.bank(save, coins, wave, tier, time_alive / 60.0, now_unix, gems_run))
	ev.append({"t": "dead", "wave": wave, "coins": coins, "kills": kills, "cash_earned": int(cash_earned), "breakdown": bd})


## Weighted roll in SPEC order: hauler, splitter, elite, ranged, skitter, drone.
func _roll_kind() -> String:
	var r: float = rng.randf()
	var acc: float = 0.0
	for kind in EnemyDB.ROLL_ORDER:
		var k: String = kind
		var w: float = 0.0
		match k:
			"hauler":
				w = float(EnemyDB.WEIGHTS["hauler"]) if wave >= 5 else 0.0
			"skitter":
				if wave >= 3:
					w = float(EnemyDB.WEIGHTS["skitter"]) + (0.0 if wave >= 5 else float(EnemyDB.WEIGHTS["hauler"]))
			"elite":
				w = Tiers.elite_weight(tier) if Tiers.allows(k, tier, wave) else 0.0
			_:
				w = float(EnemyDB.WEIGHTS[k]) if Tiers.allows(k, tier, wave) else 0.0
		if w <= 0.0:
			continue
		acc += w
		if r < acc:
			return k
	return "drone"


func _spawn(kind: String, ev: Array, at: Vector2 = Vector2.INF) -> void:
	if enemies.size() >= MAX_ENEMIES:
		return
	var d: Dictionary = EnemyDB.get_def(kind)
	var sc: float = scale() * hp_mult
	var pos: Vector2 = at
	if at == Vector2.INF:
		var a: float = rng.randf() * TAU
		pos = CENTER + Vector2.from_angle(a) * SPAWN_R
	var e: Dictionary = {
		"kind": kind, "pos": pos,
		"hp": float(d["hp"]) * sc, "max_hp": float(d["hp"]) * sc,
		"spd": float(d["spd"]) * float(stats.get("perk_enemy_spd", 1.0)),
		"dmg": float(d["dmg"]) * pow(dmg_growth, float(wave - 1)) * hp_mult,
		"cash": float(d["cash"]), "xp": float(d["xp"]), "coin": float(d["coin"]),
		"size": float(d["size"]), "atk_cd": 0.0, "slow_t": 0.0,
		"shield": 0, "fire_cd": 0.0, "shock_t": 0.0, "shock_src": -1,
	}
	match kind:
		"elite":
			e["shield"] = TuneRef.int_of("elite_shield_base", 3) + wave / 10
			e["max_shield"] = int(e["shield"])
		"ranged":
			e["fire_cd"] = TuneRef.num("ranged_fire", 2.0)
	enemies.append(e)
	if kind == "boss":
		ev.append({"t": "boss", "pos": e["pos"]})


func _core_damage(amt: float, ev: Array, kind: String, from: Vector2) -> void:
	var real: float = amt * (1.0 - float(stats.get("dr", 0.0)))
	hp -= real
	ev.append({"t": kind, "dmg": real, "pos": from})


func _move_enemies(dt: float, ev: Array) -> void:
	var r_stop: float = TuneRef.num("ranged_stop", 230.0)
	var r_fire: float = TuneRef.num("ranged_fire", 2.0)
	for e in enemies:
		var ed: Dictionary = e
		var pos: Vector2 = ed["pos"]
		var slow_t: float = float(ed["slow_t"])
		var mult: float = 0.55 if slow_t > 0.0 else 1.0
		ed["slow_t"] = maxf(0.0, slow_t - dt)
		ed["shock_t"] = maxf(0.0, float(ed.get("shock_t", 0.0)) - dt)
		var ranged: bool = String(ed["kind"]) == "ranged"
		var stop: float = r_stop if ranged else STOP_R
		var to_c: Vector2 = CENTER - pos
		var dist: float = to_c.length()
		if dist > stop + 0.001:
			var step: float = minf(dist - stop, float(ed["spd"]) * mult * dt)
			ed["pos"] = pos + to_c.normalized() * step
		elif ranged:
			ed["fire_cd"] = float(ed["fire_cd"]) - dt
			if float(ed["fire_cd"]) <= 0.0:
				ed["fire_cd"] = float(ed["fire_cd"]) + r_fire
				_core_damage(float(ed["dmg"]), ev, "enemy_shot", pos)
		else:
			ed["atk_cd"] = float(ed["atk_cd"]) - dt
			if float(ed["atk_cd"]) <= 0.0:
				ed["atk_cd"] = 1.0
				_core_damage(float(ed["dmg"]), ev, "core_hit", pos)


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


## Every weapon hit goes through here: an elite's shield absorbs whole hits.
func _hit(ed: Dictionary, dmg: float, ev: Array) -> void:
	var sh: int = int(ed.get("shield", 0))
	if sh > 0:
		sh -= 1
		ed["shield"] = sh
		ev.append({"t": "shield_hit", "pos": ed["pos"], "left": sh})
		if sh == 0:
			ev.append({"t": "shield_break", "pos": ed["pos"]})
		return
	ed["hp"] = float(ed["hp"]) - dmg


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
				var teslas: Array = wd.get("teslas", [])
				for e in enemies:
					var ed: Dictionary = e
					if float(ed["hp"]) <= 0.0:
						continue
					if (ed["pos"] as Vector2).distance_to(tpos) <= rad:
						var mul: float = 1.0
						if float(ed.get("shock_t", 0.0)) > 0.0 and teslas.has(int(ed.get("shock_src", -1))):
							mul = 1.3
						_hit(ed, dmg * mul, ev)
				ev.append({"t": "shot", "kind": kind, "from": from, "to": tpos, "radius": rad})
			"tesla":
				var hit: Dictionary = {}
				var prev: Vector2 = from
				var cur: int = tgt
				var n: int = int(wd["chains"])
				while cur >= 0 and hit.size() < n:
					hit[cur] = true
					var ce: Dictionary = enemies[cur]
					_hit(ce, dmg, ev)
					ce["slow_t"] = 1.2
					ce["shock_t"] = 1.5
					ce["shock_src"] = si
					var cpos: Vector2 = ce["pos"]
					ev.append({"t": "shot", "kind": kind, "from": prev, "to": cpos})
					prev = cpos
					cur = _nearest(cpos, 90.0, hit)
			_:
				_hit(te, dmg, ev)
				ev.append({"t": "shot", "kind": kind, "from": from, "to": tpos})


func _reap(ev: Array) -> void:
	var alive: Array = []
	var splits: Array = []
	var cm: float = run_coin_mult()
	for e in enemies:
		var ed: Dictionary = e
		if float(ed["hp"]) > 0.0:
			alive.append(ed)
			continue
		var gain: float = float(ed["cash"]) * float(stats["bounty_mult"]) * run_cash_mult()
		cash += gain
		cash_earned += gain
		xp += float(ed["xp"]) * float(stats["xp_mult"])
		var cg: float = float(ed["coin"]) * cm
		coins_run += cg
		coins_kill += cg
		kills += 1
		var kind: String = ed["kind"]
		ev.append({"t": "kill", "pos": ed["pos"], "cash": gain, "kind": kind})
		if kind == "boss":
			_boss_bounty(ed["pos"], ev)
		elif kind == "splitter":
			splits.append(ed["pos"])
	enemies = alive
	var nc: int = TuneRef.int_of("splitter_children", 2)
	for p in splits:
		var sp: Vector2 = p
		for k in nc:
			_spawn("mite", ev, sp + Vector2.from_angle(TAU * float(k) / float(maxi(1, nc))) * 10.0)
		ev.append({"t": "split", "pos": sp, "n": nc})


## SPEC B3: boss kill pays a coin bounty plus gems (capped awards per run).
func _boss_bounty(pos: Vector2, ev: Array) -> void:
	var c: int = int(floor(TuneRef.num("boss_bounty_base", 25.0) * float(wave) / 10.0 * coin_mult))
	coins_run += float(c)
	coins_boss += float(c)
	var g: int = 0
	if boss_gem_awards < TuneRef.int_of("boss_gem_cap", 3):
		boss_gem_awards += 1
		g = TuneRef.int_of("boss_gem_t3", 2) if tier >= 3 else 1
		gems_run += g
	ev.append({"t": "boss_bounty", "coins": c, "gems": g, "pos": pos})


func _check_queue(ev: Array) -> void:
	_check_level(ev)
	_check_perk(ev)


func _check_level(ev: Array) -> void:
	if draft.size() > 0 or pending_place != "" or perk_offer.size() > 0:
		return
	if xp >= xp_need():
		xp -= xp_need()
		level += 1
		draft = Draft.offer(rng, slots, unlocked, allow_new_bldg)
		ev.append({"t": "levelup", "level": level, "cards": draft.duplicate(true)})


## Perk offers queue behind the building draft (B7).
func _check_perk(ev: Array) -> void:
	if perk_pending <= 0 or draft.size() > 0 or pending_place != "" or perk_offer.size() > 0:
		return
	perk_pending -= 1
	perk_offer = Perks.offer(rng, perks_taken)
	if perk_offer.is_empty():
		perk_pending = 0
		return
	ev.append({"t": "perk_offer", "ids": perk_offer.duplicate(), "wave": wave})


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
		_check_queue(ev)
	else:
		pending_place = id
		ev.append({"t": "place_mode", "id": id})
	return ev


## Spend one free reroll (Labs reroll track + Free Reroll card) on the draft.
func reroll_draft() -> Array:
	var ev: Array = []
	if draft.is_empty() or rerolls_left <= 0:
		return ev
	rerolls_left -= 1
	draft = Draft.offer(rng, slots, unlocked, allow_new_bldg)
	ev.append({"t": "draft_reroll", "cards": draft.duplicate(true), "left": rerolls_left})
	return ev


func choose_perk(idx: int) -> Array:
	var ev: Array = []
	if idx < 0 or idx >= perk_offer.size():
		return ev
	var id: String = perk_offer[idx]
	perk_offer.clear()
	perks_taken.append(id)
	recompute()
	if id == "p_hp":
		hp = float(stats["max_hp"])
	var d: Dictionary = PerkDB.get_def(id)
	ev.append({"t": "perk_taken", "id": id, "name": String(d.get("name", id)), "tradeoff": PerkDB.is_tradeoff(id)})
	_check_queue(ev)
	return ev


## Game-speed pill (B2). The view passes a value from Labs.speed_steps.
func set_speed(v: float) -> Array:
	speed = clampf(v, 0.1, 4.0)
	return [{"t": "speed", "speed": speed}]


func place(i: int) -> Array:
	var ev: Array = []
	if pending_place == "" or i < 0 or i > 24 or not is_free(i):
		return ev
	slots[i] = {"id": pending_place, "perm": 0, "run": 1}
	cooldowns[i] = 0.0
	pending_place = ""
	recompute()
	ev.append({"t": "placed", "slot": i, "id": id_at(i)})
	_check_queue(ev)
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
