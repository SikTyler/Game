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
const ModifierDB := preload("res://data/ModifierDB.gd")

const CENTER: Vector2 = Vector2(360, 470)
const CELL: float = 52.0
## PC 7x7 board (PC_SPEC §2.1). Cell index i = row * SIDE + col; the core sits
## at (3,3). Enemies stop beyond the ring-3 corners and spawn proportionally
## farther out, so the walk-in time matches the mobile 5x5 arena.
const SIDE: int = 7
const N: int = 49
const CORE_SLOT: int = 24
const SPAWN_R: float = 470.0
const STOP_R: float = 200.0
const SLOWMO: float = 0.2
const MAX_LVL: int = 40          # default per-building level ceiling in a run (perm + run)


## Run level ceiling (GF_TUNE run_lvl_cap). Raised from 25 in the fix round so
## late in-run cash (eco income) keeps converting into building levels.
static func lvl_cap() -> int:
	return TuneRef.int_of("run_lvl_cap", MAX_LVL)
const MAX_ENEMIES: int = 220
const SUBSTEP: float = 0.05
const CORE_RING: Array = [16, 17, 18, 23, 25, 30, 31, 32]
const TARGET_MODES: Array = ["nearest", "first", "strongest", "weakest"]
const HIT_FLASH: float = 0.12   # view reads e["hit_t"] for the white hit flash
const ECO_IDS: Array = ["mine", "oilmill", "bounty", "vault", "refinery"]
const FLAK_PREY: Array = ["skitter", "mite", "drone"]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var save: Dictionary = {}
var slots: Array = []        # N × ({} | {id, perm, run})
var unlocked: Array = []     # N × bool
var cooldowns: Array = []    # N × float (core uses CORE_SLOT)
var target_modes: Array = []  # N × String (TARGET_MODES); perm slots persist in save["target_modes"]
var next_eid: int = 1
var enemies: Array = []      # {pos, hp, max_hp, spd, dmg, kind, atk_cd, slow_t, cash, xp, coin, size}
var stats: Dictionary = {}

var wave: int = 1
var wave_t: float = 0.0
var spawn_t: float = 0.5        # legacy (mobile timer); PC waves spawn from `plan`
# PC multi-direction waves (PC_SPEC §2.3). 8 spawn points (N, NE, E, SE, S, SW,
# W, NW) in 4 quadrants: 0 = N/NE, 1 = E/SE, 2 = S/SW, 3 = W/NW. Each wave is
# planned (kind + quadrant + time per spawn) when it is telegraphed, so the
# telegraph counts are exactly what spawns.
var plan: Array = []              # [{t, kind, quad}] for `plan_wave`, sorted by t
var plan_idx: int = 0
var plan_wave: int = 0
var next_plan: Dictionary = {}    # telegraphed plan for wave+1
var active_quads: Array = []      # quadrants of the current wave
var boss_dir: int = -1            # boss quadrant of the current wave (-1 none)
var wave_spawned: Dictionary = {} # quad -> planned enemies actually spawned this wave
var last_wave_spawned: Dictionary = {}  # {wave, counts} of the wave that just ended
var wave_started: bool = false    # wave 1 starts after the opening telegraph lead
var focus_quad: int = 0           # lane focus (Beacon + abilities target it)
var walls: Dictionary = {}        # quad -> {hp, max}: Barricade lane walls
var wave_cash0: float = 0.0       # cash_earned at wave start (Refinery input)
var coins_refinery: float = 0.0
var ironclad: float = 0.0         # Ironclad modifier: non-crit hits deal this much less

# PC modes (PC_SPEC §3): "normal" | "endless", challenge modifiers, mutations.
var mode: String = "normal"
var modifiers: Array = []         # ModifierDB ids picked for this run
var mod_coin: float = 1.0         # min(3, 1 + sum of modifier coin rewards)
var mode_coin: float = 1.0        # endless banks coins x pc_endless_coin_mult
var mutations_taken: Array = []
var mutation_offer: Array = []
var mutation_pending: int = 0
var enemy_hp_mod: float = 1.0
var enemy_spd_mod: float = 1.0
var enemy_dmg_mod: float = 1.0
var elite_shield_add: int = 0
var kill_cash_mod: float = 1.0
var run_seed: int = 0
var time_alive: float = 0.0
var hp: float = 100.0
var cash: float = 0.0
var xp: float = 0.0
var level: int = 1
var coins_run: float = 0.0
var kills: int = 0
var core_run_lvl: int = 0
var run_unlocks: int = 0
var spawn_hold: bool = false      # test/tool hook: suppress wave spawns (bosses included)
var build_cap: int = 40
var count_mult: float = 1.0       # enemy count multiplier (Swarm modifier, mutations)           # PC_SPEC §2.1 max buildings on the board this run
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
var boss_gem_left: int = 0       # AC-10a daily allowance left for this run

# Perks (B7).
var perks_taken: Array = []
var perk_offer: Array = []
var perk_pending: int = 0

# Tunables (GF_TUNE overridable; defaults = shipped balance).
var wave_time: float = 25.0
var hp_growth: float = 1.17     # Tier 1 ramp (fix round: slower early pace, AC-40)
var dmg_growth: float = 1.06
var spawn_base: float = 1.8
var spawn_decay: float = 0.93
var min_spawn: float = 0.45   # MAX spawn rate cap (≈2.2/s)
var xp_base: float = 6.0
var xp_growth: float = 1.3


## opts (PC): {mode: "normal"|"endless", modifiers: [ModifierDB ids]}.
func setup(seed_value: int, save_data: Dictionary, now: int = 0, opts: Dictionary = {}) -> Array:
	rng.seed = seed_value
	run_seed = seed_value
	save = save_data
	now_unix = now
	var pre: Array = _apply_run_opts(opts)
	var rm: Dictionary = BaseMeta.run_mods(save)
	if modifiers.has("nolabs"):
		for k in ["lab_dmg", "lab_hp", "lab_coin", "lab_xp"]:
			rm[k] = 0.0
		rm["start_cash"] = 0
		rm["rerolls"] = 0
	_apply_mods(rm)
	_apply_challenge()
	wave_time = TuneRef.num("wave_time", wave_time)
	hp_growth = TuneRef.num("hp_growth", hp_growth)
	# Balance knobs: per-tier enemy HP ramp (T1 1.17, T2 1.18, T3+ 1.155).
	if tier == 2:
		hp_growth = TuneRef.num("hp_growth_t2", 1.18)
	elif tier >= 3:
		hp_growth = TuneRef.num("hp_growth_hi", 1.155)
	dmg_growth = TuneRef.num("dmg_growth", dmg_growth)
	spawn_base = TuneRef.num("spawn_base", spawn_base)
	spawn_decay = TuneRef.num("spawn_decay", spawn_decay)
	min_spawn = TuneRef.num("min_spawn", min_spawn)
	xp_base = TuneRef.num("xp_base", xp_base)
	xp_growth = TuneRef.num("xp_growth", xp_growth)
	slots.clear()
	unlocked.clear()
	cooldowns.clear()
	target_modes.clear()
	build_cap = BaseMeta.build_cap(save)
	for i in N:
		var perm: Dictionary = BaseMeta.slot_of(save, i)
		if perm.is_empty():
			slots.append({})
		else:
			slots.append({"id": String(perm["id"]), "perm": int(perm["lvl"]), "run": 0})
		unlocked.append(BaseMeta.is_unlocked(save, i))
		cooldowns.append(0.0)
		var tm: String = String((save.get("target_modes", {}) as Dictionary).get(str(i), "nearest")) if save.get("target_modes", {}) is Dictionary else "nearest"
		target_modes.append(tm if TARGET_MODES.has(tm) else "nearest")
	enemies.clear()
	next_eid = 1
	draft.clear()
	pending_place = ""
	wave = 1
	wave_t = 0.0
	spawn_t = 0.5
	plan.clear()
	plan_idx = 0
	plan_wave = 0
	next_plan = {}
	active_quads.clear()
	boss_dir = -1
	wave_spawned = {}
	last_wave_spawned = {}
	wave_started = false
	focus_quad = 0
	walls = {}
	wave_cash0 = 0.0
	coins_refinery = 0.0
	time_alive = 0.0
	cash = 0.0 if modifiers.has("poverty") else float(int(mods.get("start_cash", 0)))
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
	boss_gem_left = BaseMeta.boss_gem_allowance(save, now)
	perks_taken.clear()
	perk_offer.clear()
	perk_pending = 0
	stats = {}
	recompute()
	hp = float(stats["max_hp"])
	var ev0: Array = [{"t": "run_start", "tier": tier, "speed": speed, "mode": mode, "modifiers": modifiers.duplicate(), "coin_mult": mod_coin * mode_coin, "seed": run_seed}]
	ev0.append_array(pre)
	# Wave 1 is telegraphed at t=0 and starts pc_telegraph_s later.
	_adopt_plan(_build_plan(1, telegraph_s()), ev0, true)
	return ev0


## Mode + modifier selection (validated). Endless needs best wave >= 50.
func _apply_run_opts(opts: Dictionary) -> Array:
	var ev: Array = []
	modifiers = ModifierDB.clean(opts.get("modifiers", []))
	mode = String(opts.get("mode", "normal"))
	if mode == "endless" and not BaseMeta.endless_unlocked(save):
		ev.append({"t": "endless_locked", "need": TuneRef.int_of("pc_endless_unlock", 50)})
		mode = "normal"
	if mode != "endless":
		mode = "normal"
	mod_coin = ModifierDB.coin_mult(modifiers)
	mode_coin = TuneRef.num("pc_endless_coin_mult", 0.8) if mode == "endless" else 1.0
	mutations_taken = []
	mutation_offer = []
	mutation_pending = 0
	return ev


## Challenge modifiers on top of the meta bundle (PC_SPEC §3.2).
func _apply_challenge() -> void:
	ironclad = 0.2 if modifiers.has("ironclad") else 0.0
	kill_cash_mod = 0.7 if modifiers.has("poverty") else 1.0
	if modifiers.has("glass"):
		max_hp_mult *= 0.5
	coin_mult *= mod_coin * mode_coin
	_refresh_enemy_mods()


## Enemy-side multipliers from modifiers x endless mutations.
func _refresh_enemy_mods() -> void:
	var n: Dictionary = {}
	for m in mutations_taken:
		n[m] = int(n.get(m, 0)) + 1
	enemy_hp_mod = (0.7 if modifiers.has("swarm") else 1.0) * (1.0 + 0.2 * float(n.get("m_vigor", 0)))
	count_mult = (1.6 if modifiers.has("swarm") else 1.0) * (1.0 + 0.2 * float(n.get("m_horde", 0)))
	enemy_spd_mod = (1.25 if modifiers.has("haste") else 1.0) * (1.0 + 0.1 * float(n.get("m_rush", 0)))
	enemy_dmg_mod = 1.0 + 0.25 * float(n.get("m_fangs", 0))
	elite_shield_add = 2 * int(n.get("m_plating", 0))


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
	return CENTER + Vector2(float(i % SIDE - SIDE / 2) * CELL, float(i / SIDE - SIDE / 2) * CELL)


static func ring_of(i: int) -> int:
	return BaseMeta.cell_ring(i)


static func neighbors(i: int) -> Array:
	var out: Array = []
	var x: int = i % SIDE
	var y: int = i / SIDE
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + int(dx)
			var ny: int = y + int(dy)
			if nx >= 0 and nx < SIDE and ny >= 0 and ny < SIDE:
				out.append(ny * SIDE + nx)
	return out


func lvl_at(i: int) -> int:
	var s: Dictionary = slots[i]
	if s.is_empty():
		return 0
	return mini(lvl_cap(), int(s["perm"]) + int(s["run"]))


func id_at(i: int) -> String:
	var s: Dictionary = slots[i]
	return "" if s.is_empty() else String(s["id"])


func is_free(i: int) -> bool:
	return i >= 0 and i < N and i != CORE_SLOT and bool(unlocked[i]) and (slots[i] as Dictionary).is_empty()


func building_count() -> int:
	var n: int = 0
	for i in N:
		if not (slots[i] as Dictionary).is_empty():
			n += 1
	return n


func at_cap() -> bool:
	return building_count() >= build_cap


## Can `id` go on cell i right now (free, under the build cap, ring rule)?
func can_place(i: int, id: String) -> bool:
	return is_free(i) and not at_cap() and BaseMeta.place_ok(i, id)


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
		"refineries": [],
		"walls": {},
		"beacon": 0.0,
	}
	var links: Array = st["links"]
	var arm_cap: float = TuneRef.num("armory_cap", 1.0)
	# Armory multiplier per slot (weapons + core), capped per target (AC-21).
	var arm: Array = []
	for i in N:
		arm.append(1.0)
	for i in N:
		if id_at(i) == "armory":
			for n in neighbors(i):
				arm[n] = float(arm[n]) + 0.25 * float(lvl_at(i))
	for i in N:
		arm[i] = minf(1.0 + arm_cap, float(arm[i]))
	# Aegis (S5): per-slot fire-rate bonus for weapons, output penalty for eco.
	var aeg_rate: Array = []
	var eco_pen: Array = []
	for i in N:
		aeg_rate.append(0.0)
		eco_pen.append(1.0)
	var aegis_dr: float = 0.0
	var pen: float = TuneRef.num("aegis_eco_pen", 0.15)
	for i in N:
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
	# S6 Bounty Hunters / S7 Oil Shells (fix round): eco buildings feed their
	# adjacent weapons, so an eco slot also buys wave survival (AC-38) and a
	# mono-weapon board leaves damage on the table (AC-39).
	var eco_dmg: Array = []
	for i in N:
		eco_dmg.append(0.0)
	var b_adj: float = TuneRef.num("bounty_adj", 0.05)
	var o_adj: float = TuneRef.num("oil_adj", 0.05)
	for i in N:
		var sid: String = id_at(i)
		if sid != "bounty" and sid != "oilmill":
			continue
		var Ls: float = float(lvl_at(i)) * float(eco_pen[i])
		for n in neighbors(i):
			var nid2: String = id_at(n)
			if sid == "bounty" and BuildingDB.cat_of(nid2) == "weapon":
				eco_dmg[n] = float(eco_dmg[n]) + b_adj * Ls
				links.append([i, n, "S6"])
			elif sid == "oilmill" and (nid2 == "mortar" or nid2 == "tesla"):
				eco_dmg[n] = float(eco_dmg[n]) + o_adj * Ls
				links.append([i, n, "S7"])
	var e_cap: float = TuneRef.num("eco_adj_cap", 2.0)
	for i in N:
		eco_dmg[i] = 1.0 + minf(e_cap, float(eco_dmg[i]))
	var bulwark_dr: float = 0.0
	var mine_scale: float = 1.0 + TuneRef.num("mine_wave_scale", 0.03) * float(wave - 1)
	for i in N:
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
				var smelt: float = 1.0
				for n in neighbors(i):
					if id_at(n) == "refinery":
						smelt = 1.0 + TuneRef.num("pc_smelter", 0.20)
						links.append([n, i, "S11"])
						break
				st["cash_ps"] = float(st["cash_ps"]) + 1.2 * L * mine_scale * ep * smelt
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
				(st["weapons"] as Array).append({"slot": i, "kind": "gun", "dmg": (3.0 + 2.0 * L) * float(arm[i]) * float(eco_dmg[i]), "rate": (1.0 + 0.12 * L) * (1.0 + ammo + float(aeg_rate[i])), "range": 220.0})
			"mortar":
				var teslas: Array = []
				for n in neighbors(i):
					if id_at(n) == "tesla":
						teslas.append(n)
						links.append([n, i, "S2"])
				(st["weapons"] as Array).append({"slot": i, "kind": "mortar", "dmg": (8.0 + 5.0 * L) * float(arm[i]) * float(eco_dmg[i]), "rate": 0.45 * (1.0 + float(aeg_rate[i])), "range": 320.0, "splash": 55.0 + 4.0 * L, "teslas": teslas})
			"tesla":
				(st["weapons"] as Array).append({"slot": i, "kind": "tesla", "dmg": (2.0 + 1.2 * L) * float(arm[i]) * float(eco_dmg[i]), "rate": 0.9 * (1.0 + float(aeg_rate[i])), "range": 190.0, "chains": mini(6, 2 + int(L) / 2)})
	_pc_buildings(st, arm, eco_dmg, aeg_rate, eco_pen)
	var core_dmg: float = 5.0 * (1.0 + 0.25 * float(core.get("dmg", 0))) * float(arm[CORE_SLOT])
	(st["weapons"] as Array).append({"slot": CORE_SLOT, "kind": "core", "dmg": core_dmg, "rate": 1.4, "range": 280.0})
	# Core Overdrive (late sink): core stat levels above BaseMeta.MAX_LVL —
	# opened by tiers via BaseMeta.core_cap — compound x overdrive_mult each,
	# on ALL weapon damage / max HP / regen, so late coins (and the HP lab
	# multiplying a bigger pool) keep mattering against exponential waves.
	var odm: float = TuneRef.num("overdrive_mult", 1.1)
	var od_dmg: float = pow(odm, float(maxi(0, int(core.get("dmg", 0)) - BaseMeta.MAX_LVL)))
	var od_hp: float = pow(odm, float(maxi(0, int(core.get("hp", 0)) - BaseMeta.MAX_LVL)))
	var od_regen: float = pow(odm, float(maxi(0, int(core.get("regen", 0)) - BaseMeta.MAX_LVL)))
	st["overdrive"] = {"dmg": od_dmg, "hp": od_hp, "regen": od_regen}
	# Core Overcharge (in-run cash sink): each cash level on the core compounds
	# ALL weapon damage, so eco income converts into wave survival all run long.
	# Its strength grows with the permanent Core DMG level (a meta hook: early
	# runs convert cash weakly, a built-up core converts it hard).
	var oc_step: float = TuneRef.num("overcharge", 0.02) + TuneRef.num("overcharge_per_core", 0.006) * float(core.get("dmg", 0))
	st["overcharge_step"] = oc_step
	var oc: float = pow(1.0 + oc_step, float(core_run_lvl))
	st["overcharge"] = oc
	# Meta multipliers (B1), then perks (B7), then hard caps.
	st["max_hp"] = float(st["max_hp"]) * max_hp_mult * od_hp
	st["regen"] = float(st["regen"]) * od_regen
	st["cash_ps"] = float(st["cash_ps"]) * cash_mult
	st["xp_mult"] = float(st["xp_mult"]) * xp_mod
	for w in st["weapons"]:
		var wd: Dictionary = w
		wd["dmg"] = float(wd["dmg"]) * dmg_mult * od_dmg * oc
	# PC arena geometry: the 7x7 board pushes the enemy stop ring out from 150
	# to 200 px, so every weapon's reach scales with it (pc_range_scale), and
	# weapons on outer rings reach further still (+8% per ring past ring 1).
	var rs: float = TuneRef.num("pc_range_scale", STOP_R / 150.0)
	var rr: float = TuneRef.num("pc_ring_range", 0.08)
	for w in st["weapons"]:
		var wr: Dictionary = w
		var ring: int = ring_of(int(wr["slot"]))
		wr["range"] = float(wr["range"]) * rs * (1.0 + rr * float(maxi(0, ring - 1)))
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


## PC roster (PC_SPEC §2.2) and its synergies. Link tags continue the mobile
## S1-S7 numbering: S8 Capacitor Bank, S9 Crossfire, S10 Spotter, S11 Smelter.
func _pc_buildings(st: Dictionary, arm: Array, eco_dmg: Array, aeg_rate: Array, eco_pen: Array) -> void:
	var links: Array = st["links"]
	var weapons: Array = st["weapons"]
	var crit_x: float = TuneRef.num("pc_crossfire", 0.10)
	for i in N:
		var id: String = id_at(i)
		if id == "":
			continue
		var L: float = float(lvl_at(i))
		match id:
			"railgun":
				var capb: float = 0.0
				for n in neighbors(i):
					if id_at(n) == "tesla":
						capb += TuneRef.num("pc_capacitor", 0.20) * float(lvl_at(n)) / 5.0
						links.append([n, i, "S8"])
				capb = minf(TuneRef.num("pc_capacitor_cap", 0.60), capb)
				weapons.append({"slot": i, "kind": "railgun", "dmg": (30.0 + 18.0 * L) * float(arm[i]) * float(eco_dmg[i]) * (1.0 + capb), "rate": 0.4 * (1.0 + float(aeg_rate[i])), "range": 380.0, "pierce": 14.0, "capacitor": capb, "crit": 0.0})
			"flak":
				var fc: float = 0.0
				for n in neighbors(i):
					if id_at(n) == "gun":
						fc = crit_x
						links.append([i, n, "S9"])
						links.append([n, i, "S9"])
						break
				weapons.append({"slot": i, "kind": "flak", "dmg": (2.0 + 1.0 * L) * float(arm[i]) * float(eco_dmg[i]), "rate": 2.0 * (1.0 + float(aeg_rate[i])), "range": 200.0, "splash": 40.0, "crit": fc})
			"beacon":
				st["beacon"] = float(st["beacon"]) + TuneRef.num("pc_beacon", 0.15) * L
			"refinery":
				var ep: float = float(eco_pen[i])
				(st["refineries"] as Array).append({"slot": i, "rate": TuneRef.num("pc_refinery_rate", 0.10) * ep, "cap": TuneRef.num("pc_refinery_cap", 5.0) * L * ep})
			"barricade":
				var q: int = cell_quad(i)
				var wl: Dictionary = st["walls"]
				wl[q] = float(wl.get(q, 0.0)) + TuneRef.num("pc_wall_hp", 60.0) * L
	# Crossfire crit on guns + Spotter range on mortars (set after all weapons exist).
	for w in weapons:
		var wd: Dictionary = w
		var si: int = int(wd["slot"])
		if not wd.has("crit"):
			wd["crit"] = 0.0
		match String(wd["kind"]):
			"gun":
				for n in neighbors(si):
					if id_at(n) == "flak":
						wd["crit"] = float(wd["crit"]) + crit_x
						break
			"mortar":
				for n in neighbors(si):
					if id_at(n) == "beacon":
						wd["range"] = float(wd["range"]) * (1.0 + TuneRef.num("pc_spotter", 0.25))
						links.append([n, si, "S10"])
						break


func recompute() -> void:
	var old_max: float = float(stats.get("max_hp", 0.0))
	stats = compute_stats()
	_sync_walls()
	var new_max: float = float(stats["max_hp"])
	if old_max > 0.0 and new_max > old_max:
		hp += new_max - old_max   # a new Bulwark heals by its bonus
	hp = minf(hp, new_max)


## Barricade walls follow the board: a new/upgraded Barricade adds its HP now,
## a sold one removes its lane's wall.
func _sync_walls() -> void:
	var want: Dictionary = stats.get("walls", {})
	for q in walls.keys():
		if not want.has(q):
			walls.erase(q)
	for q in want.keys():
		var mx: float = float(want[q])
		if not walls.has(q):
			walls[q] = {"hp": mx, "max": mx}
		else:
			var wd: Dictionary = walls[q]
			var grow: float = maxf(0.0, mx - float(wd["max"]))
			wd["max"] = mx
			wd["hp"] = minf(mx, float(wd["hp"]) + grow)


func _rebuild_walls(ev: Array) -> void:
	for q in walls.keys():
		var wd: Dictionary = walls[q]
		wd["hp"] = float(wd["max"])
		ev.append({"t": "wall_up", "quad": int(q), "hp": float(wd["hp"])})


# ------------------------------------------------------------------ curves
func spawn_interval() -> float:
	return interval_for(wave)


func scale() -> float:
	var cap_w: int = TuneRef.int_of("pc_endless_soft_wave", 100)
	if mode == "endless" and wave > cap_w:
		# Endless past wave 100: the ramp continues on a softer exponent.
		return pow(hp_growth, float(cap_w - 1)) * pow(TuneRef.num("pc_endless_hp_exp", 1.12), float(wave - cap_w))
	return pow(hp_growth, float(wave - 1))


func xp_need() -> float:
	return xp_base * pow(xp_growth, float(level - 1))


func upgrade_cost(i: int) -> int:
	var pm: float = float(stats.get("perk_upgrade_cost", 1.0))
	if i == CORE_SLOT:
		return int(8.0 * pow(TuneRef.num("core_run_growth", 1.4), float(core_run_lvl)) * pm)
	return int(8.0 * pow(TuneRef.num("run_upgrade_growth", 1.3), float(maxi(0, lvl_at(i) - 1))) * pm)


func unlock_cost() -> int:
	return int(40.0 * pow(1.6, float(run_unlocks)))


func time_scale() -> float:
	return SLOWMO if (draft.size() > 0 or pending_place != "" or perk_offer.size() > 0 or mutation_offer.size() > 0) else 1.0


## Coins multiplier for everything earned this run (tier × lab × card × perks).
func run_coin_mult() -> float:
	return coin_mult * float(stats.get("perk_coin", 1.0)) * mutation_coin()


func mutation_coin() -> float:
	return 1.0 + ModifierDB.MUTATION_COIN * float(mutations_taken.size())


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
	_spawn_due(ev)   # every planned spawn has t < wave_time: none is lost at rollover
	if wave_t >= wave_time:
		wave_t -= wave_time
		_wave_end(ev)
		_advance_wave(ev)
		_spawn_due(ev)
	if not wave_started and wave == 1 and wave_t >= telegraph_s():
		wave_started = true
		ev.append({"t": "wave_start", "wave": wave, "quadrants": active_quads.duplicate(), "boss_dir": boss_dir})
	if next_plan.is_empty() and wave_t >= wave_time - telegraph_s():
		next_plan = _build_plan(wave + 1, 0.0)
		ev.append(_telegraph_event(next_plan))
	_spawn_due(ev)
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
	var income: float = maxf(0.0, cash_earned - wave_cash0)
	for r in stats.get("refineries", []):
		var rd: Dictionary = r
		var c: float = minf(income * float(rd["rate"]), float(rd["cap"]))
		if c <= 0.0:
			continue
		coins_run += c
		coins_refinery += c
		ev.append({"t": "refined", "slot": int(rd["slot"]), "coins": c, "income": income})
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
	if not modifiers.has("noperks") and wave % maxi(1, TuneRef.int_of("perk_every", 5)) == 0 and not Perks.available(perks_taken).is_empty():
		perk_pending += 1
	if mode == "endless" and wave % ModifierDB.MUTATION_EVERY == 0:
		mutation_pending += 1


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
	if next_plan.is_empty() or int(next_plan["wave"]) != wave:
		next_plan = _build_plan(wave, 0.0)
		ev.append(_telegraph_event(next_plan))   # late telegraph (skipped wave)
	_adopt_plan(next_plan, ev, false)
	if wave % boss_every == 0:
		_spawn("boss", ev, Vector2.INF, boss_dir)


func _on_death(ev: Array) -> void:
	if wind_hp > 0.0 and not wind_used:
		wind_used = true
		hp = float(stats["max_hp"]) * wind_hp
		ev.append({"t": "revive", "hp": hp})
		return
	hp = 0.0
	over = true
	var cashout: int = int(floor(TuneRef.num("cashout_frac", 0.02) * cash_earned * tier_coin_mult * mod_coin * mode_coin))
	var coins: int = int(coins_run) + cashout
	var bd: Dictionary = {
		"wave": int(coins_wave), "kills": int(coins_kill), "boss": int(coins_boss),
		"cashout": cashout, "mult": run_coin_mult(), "tier": tier, "gems": gems_run,
		"refinery": int(coins_refinery), "mod_mult": mod_coin, "mode_mult": mode_coin,
	}
	var build: Array = []
	for i in N:
		build.append(id_at(i))
	ev.append({"t": "game_over", "wave": wave, "coins": coins, "kills": kills, "cash_earned": int(cash_earned), "breakdown": bd, "perks": perks_taken.duplicate(),
		"seed": run_seed, "tier": tier, "mode": mode, "modifiers": modifiers.duplicate(), "mutations": mutations_taken.duplicate(),
		"duration_s": time_alive, "build": build, "ts": now_unix})
	# Endless records its own best and never feeds the tier ladder (§3.1).
	ev.append_array(BaseMeta.bank(save, coins, wave, tier, time_alive / 60.0, now_unix, gems_run, mode != "endless"))
	if mode == "endless":
		BaseMeta.record_endless(save, wave)
	ev.append({"t": "dead", "wave": wave, "coins": coins, "kills": kills, "cash_earned": int(cash_earned), "breakdown": bd})


## Player quit (pause menu "Abandon run"): skips any revive and banks coins
## through the normal death path, so rewards/stats match a real death.
func abandon() -> Array:
	if over:
		return []
	wind_used = true
	var ev: Array = [{"t": "abandon", "wave": wave}]
	_on_death(ev)
	return ev


# ------------------------------------------------------- PC wave directions
static func telegraph_s() -> float:
	return TuneRef.num("pc_telegraph_s", 3.0)


## PC_SPEC §2.3 schedule: waves 1-9 one quadrant, 10-24 two, 25-49 three, 50+ four.
func quad_count(w: int) -> int:
	if w >= 50 or modifiers.has("allsides"):
		return 4
	if w >= 25:
		return 3
	if w >= 10:
		return 2
	return 1


## Quadrant of a battlefield point: sectors [-112.5 + 90q, -22.5 + 90q) deg.
static func quad_of(p: Vector2) -> int:
	var d: Vector2 = p - CENTER
	var deg: float = rad_to_deg(atan2(d.y, d.x))
	return posmod(int(floor((deg + 112.5) / 90.0)), 4)


## Quadrant of a base cell (Barricade lanes); the core cell has none.
static func cell_quad(i: int) -> int:
	if i == CORE_SLOT:
		return -1
	return quad_of(slot_pos(i))


## Spawn interval for wave w (the mobile curve, then perks / modifiers).
func interval_for(w: int) -> float:
	var pm: float = float(stats.get("perk_spawn", 1.0))
	return maxf(min_spawn, spawn_base * pow(spawn_decay, float(w - 1))) * pm / maxf(0.01, count_mult)


## Seeded plan for wave w: n distinct quadrants (manual Fisher-Yates), then
## one entry per spawn tick, round-robin over the quadrants. `lead` delays
## the first spawn (wave 1 opens with the telegraph lead).
func _build_plan(w: int, lead: float) -> Dictionary:
	var all_q: Array = [0, 1, 2, 3]
	for i in range(all_q.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = all_q[i]
		all_q[i] = all_q[j]
		all_q[j] = tmp
	var qs: Array = all_q.slice(0, quad_count(w))
	qs.sort()
	var iv: float = interval_for(w)
	var t: float = lead + 0.5 * iv if lead > 0.0 else 0.5 * iv
	var entries: Array = []
	var counts: Dictionary = {}
	for q in qs:
		counts[int(q)] = 0
	var elites: int = 0
	var start: int = rng.randi_range(0, qs.size() - 1)
	var k: int = 0
	var cap: int = TuneRef.int_of("pc_plan_max", 400)
	while t < wave_time - 0.001 and entries.size() < cap:
		var kind: String = _roll_kind(w)
		var q2: int = int(qs[(start + k) % qs.size()])
		entries.append({"t": t, "kind": kind, "quad": q2})
		counts[q2] = int(counts[q2]) + 1
		if kind == "elite":
			elites += 1
		t += iv
		k += 1
	var bd: int = -1
	if w % boss_every == 0:
		bd = int(qs[rng.randi_range(0, qs.size() - 1)])
	return {"wave": w, "entries": entries, "quads": qs, "counts": counts, "elites": elites, "boss_dir": bd}


func _telegraph_event(p: Dictionary) -> Dictionary:
	return {"t": "wave_telegraph", "wave": int(p["wave"]), "quadrants": (p["quads"] as Array).duplicate(), "counts": (p["counts"] as Dictionary).duplicate(), "total": (p["entries"] as Array).size(), "elites": int(p["elites"]), "boss_dir": int(p["boss_dir"]), "lead": telegraph_s()}


## Make `p` the current wave's plan. The opening wave telegraphs here (it has
## no previous wave to do it); later waves emit wave_start here.
func _adopt_plan(p: Dictionary, ev: Array, opening: bool) -> void:
	if plan_wave > 0:
		last_wave_spawned = {"wave": plan_wave, "counts": wave_spawned}
	plan = p["entries"]
	plan_idx = 0
	plan_wave = int(p["wave"])
	active_quads = (p["quads"] as Array).duplicate()
	boss_dir = int(p["boss_dir"])
	wave_spawned = {}
	next_plan = {}
	wave_cash0 = cash_earned
	_rebuild_walls(ev)
	if opening:
		ev.append(_telegraph_event(p))
	else:
		ev.append({"t": "wave_start", "wave": wave, "quadrants": active_quads.duplicate(), "boss_dir": boss_dir})


func _spawn_due(ev: Array) -> void:
	if plan_wave != wave:
		# The wave was entered without a telegraph (tests / tools jump waves).
		_adopt_plan(_build_plan(wave, 0.0), ev, true)
	if spawn_hold:
		return
	while plan_idx < plan.size() and float((plan[plan_idx] as Dictionary)["t"]) <= wave_t:
		var pe: Dictionary = plan[plan_idx]
		plan_idx += 1
		var q: int = int(pe["quad"])
		if _spawn(String(pe["kind"]), ev, Vector2.INF, q):
			wave_spawned[q] = int(wave_spawned.get(q, 0)) + 1


## Lane focus (Beacon bonus + abilities): one of the 4 quadrants.
func set_focus(q: int) -> Array:
	if q < 0 or q > 3:
		return []
	focus_quad = q
	return [{"t": "lane_focus", "quad": q}]


## Weighted roll in SPEC order: hauler, splitter, elite, ranged, skitter, drone.
## `w` defaults to the current wave (plans roll the upcoming wave's roster).
func _roll_kind(for_wave: int = -1) -> String:
	var wv: int = wave if for_wave < 0 else for_wave
	var r: float = rng.randf()
	var acc: float = 0.0
	for kind in EnemyDB.ROLL_ORDER:
		var k: String = kind
		var w: float = 0.0
		match k:
			"hauler":
				w = float(EnemyDB.WEIGHTS["hauler"]) if wv >= 5 else 0.0
			"skitter":
				if wv >= 3:
					w = float(EnemyDB.WEIGHTS["skitter"]) + (0.0 if wv >= 5 else float(EnemyDB.WEIGHTS["hauler"]))
			"elite":
				if modifiers.has("elitist"):
					w = 3.0 * maxf(Tiers.elite_weight(tier), Tiers.elite_weight(2)) if wv >= 5 else 0.0
				else:
					w = Tiers.elite_weight(tier) if Tiers.allows(k, tier, wv) else 0.0
			_:
				w = float(EnemyDB.WEIGHTS[k]) if Tiers.allows(k, tier, wv) else 0.0
		if w <= 0.0:
			continue
		acc += w
		if r < acc:
			return k
	return "drone"


func _spawn(kind: String, ev: Array, at: Vector2 = Vector2.INF, quad: int = -1) -> bool:
	if enemies.size() >= MAX_ENEMIES:
		return false
	var d: Dictionary = EnemyDB.get_def(kind)
	var sc: float = scale() * hp_mult * float(stats.get("perk_enemy_hp", 1.0)) * enemy_hp_mod
	var pos: Vector2 = at
	if at == Vector2.INF:
		var q: int = quad
		if q < 0:
			q = int(active_quads[rng.randi_range(0, active_quads.size() - 1)]) if active_quads.size() > 0 else rng.randi_range(0, 3)
		var pt: int = 2 * q + rng.randi_range(0, 1)
		var a: float = deg_to_rad(-90.0 + 45.0 * float(pt)) + rng.randf_range(-0.2, 0.2)
		pos = CENTER + Vector2.from_angle(a) * SPAWN_R
	var e: Dictionary = {
		"kind": kind, "pos": pos,
		"hp": float(d["hp"]) * sc, "max_hp": float(d["hp"]) * sc,
		"spd": float(d["spd"]) * float(stats.get("perk_enemy_spd", 1.0)) * enemy_spd_mod,
		"dmg": float(d["dmg"]) * pow(dmg_growth, float(wave - 1)) * hp_mult * enemy_dmg_mod,
		"cash": float(d["cash"]), "xp": float(d["xp"]), "coin": float(d["coin"]),
		"size": float(d["size"]), "atk_cd": 0.0, "slow_t": 0.0,
		"shield": 0, "fire_cd": 0.0, "shock_t": 0.0, "shock_src": -1,
		"hit_t": 0.0, "eid": next_eid,
	}
	next_eid += 1
	match kind:
		"boss":
			# Balance knob: boss HP relative to EnemyDB from Tier 2 up (softens the
			# every-10-waves wall once the base is maxed; T1 keeps the classic spike).
			# T1: the first boss (w10) stays gentle for new players; the extra
			# boss_hp_t1 toughness phases in to full by wave 30 (the T1 wall).
			var ramp: float = clampf(float(wave - 10) / 20.0, 0.0, 1.0)
			var bm: float = TuneRef.num("boss_hp_hi", 0.5) if tier >= 2 else 1.0 + (TuneRef.num("boss_hp_t1", 3.0) - 1.0) * ramp
			e["hp"] = float(e["hp"]) * bm
			e["max_hp"] = float(e["max_hp"]) * bm
		"elite":
			e["shield"] = TuneRef.int_of("elite_shield_base", 3) + wave / 10 + elite_shield_add
			e["max_shield"] = int(e["shield"])
		"ranged":
			e["fire_cd"] = TuneRef.num("ranged_fire", 2.0)
	e["quad"] = quad_of(pos)
	enemies.append(e)
	if kind == "boss":
		ev.append({"t": "boss", "pos": e["pos"], "quad": int(e["quad"])})
	return true


func _core_damage(amt: float, ev: Array, kind: String, from: Vector2) -> void:
	var real: float = amt * (1.0 - float(stats.get("dr", 0.0)))
	hp -= real
	ev.append({"t": kind, "dmg": real, "pos": from})


func _move_enemies(dt: float, ev: Array) -> void:
	var r_stop: float = TuneRef.num("ranged_stop", 230.0)
	var r_fire: float = TuneRef.num("ranged_fire", 2.0)
	var wall_r: float = TuneRef.num("pc_wall_r", STOP_R + 50.0)
	var wall_slow: float = 1.0 - TuneRef.num("pc_wall_slow", 0.30)
	for e in enemies:
		var ed: Dictionary = e
		var pos: Vector2 = ed["pos"]
		var slow_t: float = float(ed["slow_t"])
		var mult: float = 0.55 if slow_t > 0.0 else 1.0
		ed["slow_t"] = maxf(0.0, slow_t - dt)
		ed["shock_t"] = maxf(0.0, float(ed.get("shock_t", 0.0)) - dt)
		ed["hit_t"] = maxf(0.0, float(ed.get("hit_t", 0.0)) - dt)
		var ranged: bool = String(ed["kind"]) == "ranged"
		var stop: float = r_stop if ranged else STOP_R
		var to_c: Vector2 = CENTER - pos
		var dist: float = to_c.length()
		if dist > stop + 0.001:
			# Barricade (PC_SPEC §2.2): a standing wall on this lane slows enemies
			# pressing on it, and they wear it down with their contact damage.
			var wq: int = int(ed.get("quad", -1))
			if not walls.is_empty() and dist <= wall_r + 15.0 and walls.has(wq):
				var wd: Dictionary = walls[wq]
				if float(wd["hp"]) > 0.0:
					mult *= wall_slow
					wd["hp"] = float(wd["hp"]) - float(ed["dmg"]) * dt
					if float(wd["hp"]) <= 0.0:
						wd["hp"] = 0.0
						ev.append({"t": "wall_broken", "quad": wq})
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


## Targeting (pattern adapted from ape1121/Godot-4-Tower-Defense-Template, MIT:
## try_get_closest_target; first/strongest/weakest are in-house). Pure: picks
## an index into `enemies` within `rng_lim` of `from`, or -1.
##   nearest   – closest to the weapon
##   first     – closest to the core (most dangerous)
##   strongest – highest current hp (ties -> nearest)
##   weakest   – lowest current hp (ties -> nearest)
func pick_target(from: Vector2, rng_lim: float, mode: String) -> int:
	if mode == "nearest":
		return _nearest(from, rng_lim, {})
	var best: int = -1
	var best_key: float = INF
	var best_d: float = INF
	var lim2: float = rng_lim * rng_lim
	for k in enemies.size():
		var ed: Dictionary = enemies[k]
		var hpv: float = float(ed["hp"])
		if hpv <= 0.0:
			continue
		var p: Vector2 = ed["pos"]
		var d2: float = from.distance_squared_to(p)
		if d2 > lim2:
			continue
		var key: float = 0.0
		match mode:
			"first":
				key = CENTER.distance_squared_to(p)
			"strongest":
				key = -hpv
			_:
				key = hpv
		if key < best_key or (key == best_key and d2 < best_d):
			best_key = key
			best_d = d2
			best = k
	return best


## Set a weapon slot's targeting mode (run-scoped; permanent buildings also
## remember it in the save).
func set_target_mode(i: int, mode: String) -> Array:
	if i < 0 or i >= N or not TARGET_MODES.has(mode) or not is_weapon_slot(i):
		return []
	target_modes[i] = mode
	if i == CORE_SLOT or int((slots[i] as Dictionary).get("perm", 0)) > 0:
		if not (save.get("target_modes", null) is Dictionary):
			save["target_modes"] = {}
		(save["target_modes"] as Dictionary)[str(i)] = mode
	return [{"t": "target_mode", "slot": i, "mode": mode}]


func is_weapon_slot(i: int) -> bool:
	for w in stats.get("weapons", []):
		if int((w as Dictionary)["slot"]) == i:
			return true
	return false


func cycle_target_mode(i: int) -> Array:
	if i < 0 or i >= target_modes.size():
		return []
	var k: int = TARGET_MODES.find(String(target_modes[i]))
	return set_target_mode(i, String(TARGET_MODES[(k + 1) % TARGET_MODES.size()]))


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


## Every weapon hit goes through here: Lane Beacon bonus vs the focused lane,
## then an elite's shield absorbs whole hits.
func _hit(ed: Dictionary, dmg_in: float, ev: Array, crit: bool = false) -> void:
	var dmg: float = dmg_in
	var bb: float = float(stats.get("beacon", 0.0))
	if bb > 0.0 and int(ed.get("quad", quad_of(ed["pos"]))) == focus_quad:
		dmg *= 1.0 + bb
	if not crit and ironclad > 0.0:
		dmg *= 1.0 - ironclad
	var sh: int = int(ed.get("shield", 0))
	if sh > 0:
		sh -= 1
		ed["shield"] = sh
		ev.append({"t": "shield_hit", "pos": ed["pos"], "left": sh})
		if sh == 0:
			ev.append({"t": "shield_break", "pos": ed["pos"]})
		return
	ed["hp"] = float(ed["hp"]) - dmg
	ed["hit_t"] = HIT_FLASH
	if crit:
		ev.append({"t": "dmg", "eid": int(ed.get("eid", 0)), "pos": ed["pos"], "amt": dmg, "crit": true})
	else:
		ev.append({"t": "dmg", "eid": int(ed.get("eid", 0)), "pos": ed["pos"], "amt": dmg})


func _fire(dt: float, ev: Array) -> void:
	for w in stats["weapons"]:
		var wd: Dictionary = w
		var si: int = int(wd["slot"])
		var cd: float = float(cooldowns[si]) - dt
		if cd > 0.0:
			cooldowns[si] = cd
			continue
		var from: Vector2 = slot_pos(si)
		var tgt: int = pick_target(from, float(wd["range"]), String(target_modes[si]) if si < target_modes.size() else "nearest")
		if tgt < 0:
			cooldowns[si] = 0.0
			continue
		cooldowns[si] = cd + 1.0 / float(wd["rate"])
		var kind: String = wd["kind"]
		var dmg: float = float(wd["dmg"])
		var te: Dictionary = enemies[tgt]
		var tpos: Vector2 = te["pos"]
		# Crit (Crossfire): one seeded roll per shot, only when the weapon can crit.
		var crit: bool = false
		if float(wd.get("crit", 0.0)) > 0.0 and rng.randf() < float(wd["crit"]):
			crit = true
			dmg *= TuneRef.num("pc_crit_mult", 2.0)
		match kind:
			"railgun":
				# Pierces every enemy on the line from the gun through the target.
				var dir: Vector2 = (tpos - from).normalized()
				var reach: float = float(wd["range"])
				for e in enemies:
					var ed: Dictionary = e
					if float(ed["hp"]) <= 0.0:
						continue
					var rel: Vector2 = (ed["pos"] as Vector2) - from
					var along: float = rel.dot(dir)
					if along < 0.0 or along > reach:
						continue
					if absf(rel.cross(dir)) <= float(wd["pierce"]) + float(ed["size"]) * 0.5:
						_hit(ed, dmg, ev, crit)
				ev.append({"t": "shot", "kind": kind, "from": from, "to": from + dir * reach})
			"flak":
				var frad: float = float(wd["splash"])
				for e in enemies:
					var ed: Dictionary = e
					if float(ed["hp"]) <= 0.0:
						continue
					if (ed["pos"] as Vector2).distance_to(tpos) <= frad:
						var fm: float = TuneRef.num("pc_flak_prey", 1.5) if FLAK_PREY.has(String(ed["kind"])) else 1.0
						_hit(ed, dmg * fm, ev, crit)
				ev.append({"t": "shot", "kind": kind, "from": from, "to": tpos, "radius": frad})
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
				_hit(te, dmg, ev, crit)
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
		var gain: float = float(ed["cash"]) * float(stats["bounty_mult"]) * run_cash_mult() * kill_cash_mod
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
		g = mini(boss_gem_left, TuneRef.int_of("boss_gem_t3", 2) if tier >= 3 else 1)
		boss_gem_left -= g
		gems_run += g
	ev.append({"t": "boss_bounty", "coins": c, "gems": g, "pos": pos})


func _check_queue(ev: Array) -> void:
	_check_mutation(ev)
	_check_level(ev)
	_check_perk(ev)


## Endless mutation pick (every 25 waves): 3 distinct, non-maxed mutations.
func _check_mutation(ev: Array) -> void:
	if mutation_pending <= 0 or draft.size() > 0 or pending_place != "" or perk_offer.size() > 0 or mutation_offer.size() > 0:
		return
	mutation_pending -= 1
	var pool: Array = []
	for id in ModifierDB.MUTATION_IDS:
		if mutations_taken.count(id) < ModifierDB.MUTATION_STACK:
			pool.append(id)
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	mutation_offer = pool.slice(0, 3)
	if mutation_offer.is_empty():
		return
	ev.append({"t": "mutation_offer", "ids": mutation_offer.duplicate(), "wave": wave})


func choose_mutation(idx: int) -> Array:
	var ev: Array = []
	if idx < 0 or idx >= mutation_offer.size():
		return ev
	var id: String = mutation_offer[idx]
	mutation_offer.clear()
	mutations_taken.append(id)
	_refresh_enemy_mods()
	var d: Dictionary = ModifierDB.MUTATIONS.get(id, {})
	ev.append({"t": "mutation_taken", "id": id, "name": String(d.get("name", id)), "coin_mult": mutation_coin()})
	_check_queue(ev)
	return ev


func _check_level(ev: Array) -> void:
	if draft.size() > 0 or pending_place != "" or perk_offer.size() > 0 or mutation_offer.size() > 0:
		return
	if xp >= xp_need():
		xp -= xp_need()
		level += 1
		draft = Draft.offer(rng, slots, unlocked, allow_new_bldg, build_cap)
		ev.append({"t": "levelup", "level": level, "cards": draft.duplicate(true)})


## Perk offers queue behind the building draft (B7).
func _check_perk(ev: Array) -> void:
	if modifiers.has("noperks"):
		perk_pending = 0
	if perk_pending <= 0 or draft.size() > 0 or pending_place != "" or perk_offer.size() > 0 or mutation_offer.size() > 0:
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
		for i in N:
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
	draft = Draft.offer(rng, slots, unlocked, allow_new_bldg, build_cap)
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
	if pending_place == "" or not can_place(i, pending_place):
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
	if over or i < 0 or i >= N:
		return ev
	if i != CORE_SLOT and (id_at(i) == "" or lvl_at(i) >= lvl_cap()):
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
	if over or i < 0 or i >= N or i == CORE_SLOT or bool(unlocked[i]) or not BaseMeta.ring_open(save, i):
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
	for i in N:
		if is_free(i):
			out.append(i)
	return out


## Cash a building represents: its base price plus every run level bought.
func building_value(i: int) -> int:
	if id_at(i) == "":
		return 0
	var v: int = 8
	for k in maxi(0, lvl_at(i) - 1):
		v += int(8.0 * pow(TuneRef.num("run_upgrade_growth", 1.3), float(k)))
	return v


## PC_SPEC §1.5 drag-move: move the building on `a` to `b` (empty unlocked
## cell) or swap it with the building on `b`. Free while paused or when the
## field is clear between waves; during an active wave it costs
## pc_move_cost_frac of the moved building(s) value in cash.
func move_cost(a: int, b: int, paused: bool = false) -> int:
	if paused or enemies.is_empty():
		return 0
	var f: float = TuneRef.num("pc_move_cost_frac", 0.1)
	return int(ceil(f * float(building_value(a) + building_value(b))))


func move_building(a: int, b: int, paused: bool = false) -> Array:
	if over or a == b or a < 0 or b < 0 or a >= N or b >= N or a == CORE_SLOT or b == CORE_SLOT:
		return []
	var ida: String = id_at(a)
	var idb: String = id_at(b)
	if ida == "" or not bool(unlocked[b]) or not BaseMeta.place_ok(b, ida):
		return []
	if idb != "" and not BaseMeta.place_ok(a, idb):
		return []
	var c: int = move_cost(a, b, paused)
	if cash < float(c):
		return []
	cash -= float(c)
	var sa: Dictionary = slots[a]
	slots[a] = slots[b]
	slots[b] = sa
	var cd: float = float(cooldowns[a])
	cooldowns[a] = cooldowns[b]
	cooldowns[b] = cd
	var tm: String = String(target_modes[a])
	target_modes[a] = target_modes[b]
	target_modes[b] = tm
	recompute()
	return [{"t": "building_moved", "from": a, "to": b, "id": ida, "swapped": idb, "cost": c}]

