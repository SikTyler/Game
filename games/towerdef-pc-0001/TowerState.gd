extends RefCounted
## Corehold rules engine — pure, seeded, headless. Owns the whole run: waves,
## enemies, the Core's attack, roguelite drafts, specials, troops, loot and the
## run economy (cash / XP / coins). Every action returns an Array of event
## Dictionaries that the view replays; the view never owns a rule.
##
## Redesign (REDESIGN_SPEC §2 ENGINE-RUN): the Core is the main weapon and eco
## generator. Its permanent sheet comes from the active Core (CoreDB, level
## bought outside the run); inside the run cash buys 5 Core tracks (Damage,
## Rate, Range, Eco, Armor). The 7x7 grid starts EMPTY except for the Core:
## everything else is a roguelite pick (buildings, upgrade packs, specials,
## troop huts, super-rare Insight). Rings 2/3 open at track totals 10/30.
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
const PickDB := preload("res://data/PickDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const Cores := preload("res://Cores.gd")
const Specials := preload("res://Specials.gd")
const Troops := preload("res://Troops.gd")
const Drops := preload("res://Drops.gd")
const PowerModel := preload("res://PowerModel.gd")
const Parts := preload("res://Parts.gd")

const CENTER: Vector2 = Vector2(360, 470)
const CELL: float = 52.0
## PC 7x7 board. Cell index i = row * SIDE + col; the Core sits at (3,3).
## Enemies stop beyond the ring-3 corners. (REDESIGN_SPEC §2.3 asks for 9x9
## with 4 rings; the 7x7 arena geometry is kept until the UI rebuild decides
## the field size — rings 2/3 open at track totals 10/30, see RING_OPEN.)
const SIDE: int = 7
const N: int = 49
const CORE_SLOT: int = 24
const SPAWN_R: float = 470.0
const STOP_R: float = 200.0
const SLOWMO: float = 0.2
const MAX_LVL: int = 5           # building / hut level cap (duplicate picks)
const MAX_ENEMIES: int = 220
const SUBSTEP: float = 0.05
const CORE_RING: Array = [16, 17, 18, 23, 25, 30, 31, 32]
const TARGET_MODES: Array = ["nearest", "first", "strongest", "weakest"]
const HIT_FLASH: float = 0.12   # view reads e["hit_t"] for the white hit flash
const ECO_IDS: Array = ["mine", "oilmill", "bounty", "vault", "refinery"]
const FLYERS: Array = ["drone", "mite"]     # Flak prey; Flak cannot hit ground
const BOSSY: Array = ["boss", "elite"]
## Core cash tracks (REDESIGN_SPEC §2.2). cost(next) = base * growth^lvl.
## Growth tuned up from the spec's 1.16-1.20 (playtest pacing: with kill
## cash x1.10/wave the spec values hit every cap by ~w40); Tune keys
## pc_track_growth_<id> override.
const TRACK_IDS: Array = ["dmg", "rate", "range", "eco", "armor"]
const TRACKS: Dictionary = {
	"dmg": {"name": "Damage", "base": 20.0, "growth": 1.21, "cap": 60, "desc": "x1.08 Core + building dmg"},
	"rate": {"name": "Rate", "base": 30.0, "growth": 1.23, "cap": 40, "desc": "+3% Core attack rate"},
	"range": {"name": "Range", "base": 40.0, "growth": 1.25, "cap": 20, "desc": "+0.1 Core range"},
	"eco": {"name": "Eco", "base": 25.0, "growth": 1.20, "cap": 50, "desc": "+0.4 cash/s, interest cap +5"},
	"armor": {"name": "Armor", "base": 25.0, "growth": 1.19, "cap": 60, "desc": "+5% HP, +0.2 regen, +0.5 armor"},
}
## Ring -> track-level total that opens it (ring 1 is open at start).
const RING_OPEN: Dictionary = {2: 10, 3: 30}


## Building / hut level ceiling in a run (duplicate picks, L5).
static func lvl_cap() -> int:
	return PickDB.BUILDING_MAX


## Building damage scale over the PickDB L1 sheet (interim tune: picks must
## carry their POWER_MODEL share next to the Core; Tune pc_bld_dmg).
static func bld_dmg() -> float:
	return TuneRef.num("pc_bld_dmg", 1.25)


## Grid "cell" in world px for every range in the design tables.
static func cpx() -> float:
	return TuneRef.num("pc_cell_px", 78.0)


var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var drop_rng: RandomNumberGenerator = RandomNumberGenerator.new()   # loot only: never perturbs waves
var draft_rng: RandomNumberGenerator = RandomNumberGenerator.new()  # drafts / perks / mutations
var combat_rng: RandomNumberGenerator = RandomNumberGenerator.new() # crits / wave skip
# Separate streams keep the wave sequence identical whatever the player picks
# or shoots, so two policies on one seed face the same waves.
var save: Dictionary = {}
var slots: Array = []        # N × ({} | {id, perm, run}); perm is always 0 now
var unlocked: Array = []     # N × bool (rings open this run)
var cooldowns: Array = []    # N × float (core uses CORE_SLOT)
var target_modes: Array = []  # N × String (TARGET_MODES)
var next_eid: int = 1
var enemies: Array = []      # {pos, hp, max_hp, spd, dmg, kind, atk_cd, slow_t, slow_m, cash, xp, coin, size, eid}
var stats: Dictionary = {}

var wave: int = 1
var wave_t: float = 0.0
var spawn_t: float = 0.5        # legacy (mobile timer); PC waves spawn from `plan`
# PC multi-direction waves (PC_SPEC §2.3). 8 spawn points in 4 quadrants:
# 0 = N/NE, 1 = E/SE, 2 = S/SW, 3 = W/NW. Each wave is planned when it is
# telegraphed, so the telegraph counts are exactly what spawns.
var plan: Array = []              # [{t, kind, quad, [marked]}] for `plan_wave`, sorted by t
var plan_idx: int = 0
var plan_wave: int = 0
var next_plan: Dictionary = {}    # telegraphed plan for wave+1
var active_quads: Array = []      # quadrants of the current wave
var boss_dir: int = -1            # boss quadrant of the current wave (-1 none)
var wave_spawned: Dictionary = {} # quad -> planned enemies actually spawned this wave
var last_wave_spawned: Dictionary = {}  # {wave, counts} of the wave that just ended
var wave_started: bool = false    # wave 1 starts after the opening telegraph lead
var focus_quad: int = 0           # lane focus (Orbital auto-target prefers it)
var walls: Dictionary = {}        # quad -> {hp, max}: Barricade lane walls
var wave_cash0: float = 0.0       # cash_earned at wave start
var ironclad: float = 0.0         # Ironclad modifier: non-crit hits deal this much less

# PC modes (PC_SPEC §3): "normal" | "endless", challenge modifiers, mutations.
var mode: String = "normal"
var modifiers: Array = []
var mod_coin: float = 1.0
var mode_coin: float = 1.0
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
var core_run_lvl: int = 0         # mirror of tracks["dmg"] (legacy name the view reads)
var spawn_hold: bool = false      # test/tool hook: suppress wave spawns (bosses included)
var build_cap: int = 48
var count_mult: float = 1.0
var draft: Array = []
var pending_place: String = ""
var over: bool = false

# Core (REDESIGN §2.1) + cash tracks (§2.2).
var core_id: String = "bastion"
var core_def: Dictionary = {}
var core_lvl: int = 1
var tracks: Dictionary = {}
var rings_open: int = 1
var beam_eid: int = -1            # Lance: current beam target
var beam_t: float = 0.0           # Lance: seconds held on it
var pulse_n: int = 0              # Tempest: pulses fired (every 5th chains)
var shield: float = 0.0           # Aegis shield points
var shield_idle: float = 0.0      # seconds since the Core last took damage

# Roguelite picks (§2.3).
var packs: Dictionary = {}        # pack id -> stacks
var picks_taken: Array = []       # every pick id in order
var specials: Array = []          # Specials slots [{id, copies, cd, charges}]
var troops: Array = []            # Troops state
var troop_counter: Dictionary = {"next": 1}
var insight_found: Array = []     # Insight ids found this run (banked at run end)
var loot: Dictionary = {}         # Drops.empty_loot()
var banished: Array = []
var banish_left: int = 1
var free_reroll: bool = true      # 1 free reroll per draft
var paid_rerolls: int = 0         # paid rerolls in the current draft
var draft_queue: Array = []       # pending drafts: guarantee rarity ("" | "rare" | "epic")
var draft_guarantee: String = ""
var luck: int = 0
var buffs: Dictionary = {}        # overdrive_t, magnet_t, repair_t, repair_rate, warp_t
var orbitals: Array = []          # pending Orbital Strikes [{pos, t, dmg, r}]
var special_casts: int = 0
var couriers: int = 0
var ins: Dictionary = {}          # Insight values {in_dmg: 0.01, ...}
var pfx: Dictionary = {}          # Parts.run_fx of the active Core (ENGINE-META)
var last_stand_used: bool = false # Bulwark 4-piece: once per wave
var immune_t: float = 0.0         # Bulwark 4-piece immunity timer
var interest_t: float = 0.0       # Mint 4-piece: interest every 15 s
var core_shots: int = 0           # Storm 4-piece: every 10th Core attack

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
var allow_new_bldg: bool = true
var speed: float = 1.0            # game-speed multiplier (B2)
var rerolls_left: int = 0         # banked free rerolls (labs, cards, XP level-ups)
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
var hp_growth: float = 1.17
var dmg_growth: float = 1.06
var spawn_base: float = 1.8
var spawn_decay: float = 0.93
var min_spawn: float = 0.45
var xp_base: float = 6.0
var xp_growth: float = 1.3


## opts (PC): {mode: "normal"|"endless", modifiers: [ModifierDB ids], core: id}.
func setup(seed_value: int, save_data: Dictionary, now: int = 0, opts: Dictionary = {}) -> Array:
	rng.seed = seed_value
	drop_rng.seed = seed_value ^ 0x5EED_D20B
	draft_rng.seed = seed_value ^ 0x0D2A_F7C3
	combat_rng.seed = seed_value ^ 0x00C0_BA75
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
	hp_growth = PowerModel.hp_growth(tier)
	dmg_growth = TuneRef.num("dmg_growth", dmg_growth)
	spawn_base = TuneRef.num("spawn_base", spawn_base)
	spawn_decay = TuneRef.num("spawn_decay", spawn_decay)
	min_spawn = TuneRef.num("min_spawn", min_spawn)
	xp_base = TuneRef.num("xp_base", xp_base)
	xp_growth = TuneRef.num("xp_growth", xp_growth)
	# Core: the active Core (or opts.core when owned) at its permanent level.
	core_id = Cores.active(save)
	var oc: String = String(opts.get("core", ""))
	if oc != "" and Cores.is_owned(save, oc):
		core_id = oc
	core_def = CoreDB.get_def(core_id)
	core_lvl = Cores.level(save, core_id)
	# Parts (ENGINE-META): the equipped preset's summed fx; specials fold into
	# the meta bundle the Specials code already reads.
	pfx = Parts.run_fx(save, core_id)
	mods["special_dmg"] = float(mods.get("special_dmg", 1.0)) * maxf(0.1, 1.0 + pf("special_dmg"))
	mods["special_cd"] = float(mods.get("special_cd", 1.0)) * maxf(0.2, 1.0 + pf("special_cd"))
	last_stand_used = false
	immune_t = 0.0
	interest_t = 0.0
	core_shots = 0
	var head: int = _reforge_node("head_start")
	tracks = {}
	for t in TRACK_IDS:
		tracks[t] = mini(head, track_cap(t))
	core_run_lvl = int(tracks["dmg"])
	# Insight (permanent, banked from earlier runs).
	ins = {}
	for id in PickDB.INSIGHT:
		ins[id] = PickDB.insight_value(save, String(id))
	luck = mini(10, int(round(float(ins["in_luck"]))) + int(mods.get("luck", 0)) + int(pf("luck")))
	slots.clear()
	unlocked.clear()
	cooldowns.clear()
	target_modes.clear()
	build_cap = N - 1
	for i in N:
		slots.append({})
		unlocked.append(i != CORE_SLOT and BaseMeta.cell_ring(i) == 1)
		cooldowns.append(0.0)
		target_modes.append("nearest")
	rings_open = 1
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
	time_alive = 0.0
	cash = 0.0 if modifiers.has("poverty") else float(int(mods.get("start_cash", 0)))
	xp = 0.0
	level = 1
	coins_run = 0.0
	kills = 0
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
	beam_eid = -1
	beam_t = 0.0
	pulse_n = 0
	shield_idle = 0.0
	packs = {}
	picks_taken = []
	specials = []
	troops = []
	troop_counter = {"next": 1}
	insight_found = []
	loot = Drops.empty_loot()
	banished = []
	banish_left = 1 + mini(2, _reforge_node("banish_plus")) + int(mods.get("banish", 0))
	free_reroll = true
	paid_rerolls = 0
	draft_queue = []
	draft_guarantee = ""
	buffs = {"overdrive_t": 0.0, "magnet_t": 0.0, "repair_t": 0.0, "repair_rate": 0.0, "warp_t": 0.0}
	orbitals = []
	special_casts = 0
	couriers = 0
	stats = {}
	recompute()
	hp = float(stats["max_hp"])
	shield = float(stats.get("shield_max", 0.0))
	var ev0: Array = [{"t": "run_start", "tier": tier, "speed": speed, "mode": mode, "modifiers": modifiers.duplicate(), "coin_mult": mod_coin * mode_coin, "seed": run_seed, "core": core_id, "core_lvl": core_lvl}]
	ev0.append_array(pre)
	# Wave 1 is telegraphed at t=0 and starts pc_telegraph_s later.
	_adopt_plan(_build_plan(1, telegraph_s()), ev0, true)
	return ev0


## Level of a Reforge shard-tree node in the save (ENGINE-META owns the tree).
func _reforge_node(id: String) -> int:
	var rf: Variant = save.get("reforge", null)
	if rf is Dictionary:
		var nodes: Variant = (rf as Dictionary).get("nodes", {})
		if nodes is Dictionary:
			return int((nodes as Dictionary).get(id, 0))
	return 0


## One summed part fx value (0 when no equipped part carries the key).
func pf(k: String) -> float:
	return float(pfx.get(k, 0.0))


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
	mode_coin = TuneRef.num("pc_endless_coin_mult", 0.9) if mode == "endless" else 1.0
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
	coin_mult = tier_coin_mult * (1.0 + float(m.get("lab_coin", 0.0)) + float(cards.get("coin", 0.0))) * (1.0 + float(m.get("rf_coin", 0.0)))
	# Reforge tree (might / bulwark_p / prosperity) multiply the meta bundle.
	dmg_mult = (1.0 + float(m.get("lab_dmg", 0.0))) * (1.0 + float(cards.get("dmg", 0.0))) * (1.0 + float(m.get("rf_dmg", 0.0)))
	max_hp_mult = (1.0 + float(m.get("lab_hp", 0.0))) * (1.0 + float(cards.get("hp", 0.0))) * (1.0 + float(m.get("rf_hp", 0.0)))
	cash_mult = 1.0 + float(cards.get("cash", 0.0))
	xp_mod = 1.0 + float(m.get("lab_xp", 0.0)) + float(cards.get("xp", 0.0))
	boss_every = maxi(1, int(m.get("boss_every", 10)))
	allow_new_bldg = true
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


## Chebyshev cell distance on the grid.
static func cell_dist(a: int, b: int) -> int:
	return maxi(absi(a % SIDE - b % SIDE), absi(a / SIDE - b / SIDE))


func lvl_at(i: int) -> int:
	var s: Dictionary = slots[i]
	if s.is_empty():
		return 0
	return mini(lvl_cap(), int(s["perm"]) + int(s["run"]))


func id_at(i: int) -> String:
	var s: Dictionary = slots[i]
	return "" if s.is_empty() else String(s["id"])


func slot_of_id(id: String) -> int:
	for i in N:
		if id_at(i) == id:
			return i
	return -1


func is_free(i: int) -> bool:
	return i >= 0 and i < N and i != CORE_SLOT and bool(unlocked[i]) and (slots[i] as Dictionary).is_empty()


func building_count() -> int:
	var n: int = 0
	for i in N:
		if not (slots[i] as Dictionary).is_empty():
			n += 1
	return n


func hut_count() -> int:
	var n: int = 0
	for i in N:
		if PickDB.fam_of(id_at(i)) == "hut":
			n += 1
	return n


func at_cap() -> bool:
	return building_count() >= build_cap


## Can `id` go on cell i right now (free, open ring, ring rule)?
func can_place(i: int, id: String) -> bool:
	return is_free(i) and not at_cap() and BaseMeta.place_ok(i, id)


# ------------------------------------------------------------------- stats
## Run cash index e(w): kill cash, passive cash/s and interest caps are
## authored in wave-1 units and scale x pc_kill_growth per wave (POWER_MODEL §3).
func cash_index() -> float:
	return PowerModel.cash_index(wave, tier)


func pack_n(id: String) -> int:
	return int(packs.get(id, 0))


func track_total() -> int:
	var n: int = 0
	for t in TRACK_IDS:
		n += int(tracks[t])
	return n


## The single pure source of every derived number. Also returns `links`
## ([a, b, tag], a = bonus source, b = receiver) for the view to draw.
func compute_stats() -> Dictionary:
	var cd: Dictionary = core_def
	var L: int = core_lvl
	var tm: float = CoreDB.trait_mult(L)
	var legacy: Dictionary = save.get("core", {}) if save.get("core", {}) is Dictionary else {}
	var e: float = cash_index()
	var px: float = cpx()
	var nb: int = 0
	for i in N:
		if i != CORE_SLOT and id_at(i) != "":
			nb += 1
	# Bastion Steadfast: +1% dmg and cash/s per building (max 20), x trait strength.
	var steadfast: float = 1.0
	if String(cd.get("trait", "")) == "steadfast":
		steadfast = 1.0 + 0.01 * float(mini(20, nb)) * tm
	# Legacy v3 Core workshop levels (save.core) stay a small additive bonus
	# (Core-level-sized steps) until save v4 migrates them into Core levels.
	var st: Dictionary = {
		"max_hp": float(cd["hp"]) * CoreDB.lvl_mult("hp", L) * (1.0 + TuneRef.num("pc_legacy_hp", 0.03) * float(legacy.get("hp", 0))),
		"regen": float(cd["regen"]) * CoreDB.lvl_mult("regen", L) * (1.0 + TuneRef.num("pc_legacy_regen", 0.03) * float(legacy.get("regen", 0))),
		"armor": float(cd["armor"]),
		"cash_ps": float(cd["cash"]) * CoreDB.lvl_mult("cash", L),
		"xp_mult": 1.0,
		"kill_cash": 1.0,
		"weapons": [],
		"links": [],
		"walls": {},
		"bounties": [],
		"huts": [],
		"interest_rate": float(cd["irate"]),
		"interest_cap": float(cd["icap"]),
		"shield_max": 0.0,
		"shield_regen": 0.0,
		"lifesteal": 0.0,
		"crit": 0.08 * float(pack_n("pk_crit")),
		"dr": 0.0,
		"beacon": 0.0,
		"core_id": core_id,
		"core_lvl": L,
	}
	var links: Array = st["links"]
	# Global multipliers: meta (labs/cards) x packs x Insight x Damage track.
	var od_dmg: float = pow(TuneRef.num("overdrive_mult", 1.1), float(maxi(0, int(legacy.get("dmg", 0)) - BaseMeta.MAX_LVL)))
	var od_hp: float = pow(TuneRef.num("overdrive_mult", 1.1), float(maxi(0, int(legacy.get("hp", 0)) - BaseMeta.MAX_LVL)))
	var dmg_track: float = pow(TuneRef.num("pc_track_dmg_step", 1.08), float(tracks["dmg"]))
	# Legacy Core DMG levels lift every weapon (interim meta until Parts land).
	var legacy_dmg: float = 1.0 + TuneRef.num("pc_legacy_dmg", 0.03) * float(legacy.get("dmg", 0))
	var dmg_all: float = dmg_mult * od_dmg * legacy_dmg * dmg_track * (1.0 + 0.12 * float(pack_n("pk_arsenal"))) * (1.0 + 0.40 * float(pack_n("pk_gambit"))) * (1.0 + float(ins.get("in_dmg", 0.0)))
	# Parts: all-damage (+ Bastion Heart per building, max 12 buildings).
	dmg_all *= maxf(0.1, 1.0 + pf("dmg") + pf("dmg_per_bld") * float(mini(12, nb)))
	var rate_all: float = (1.0 + 0.08 * float(pack_n("pk_overclock"))) * (1.0 + float(ins.get("in_rate", 0.0)))
	var range_add: float = 0.5 * float(pack_n("pk_optics"))
	st["dmg_all"] = dmg_all
	st["dmg_track"] = dmg_track
	# Per-cell adjacency modifiers (Armory dmg, Beacon rate/range, Oil Mill rate).
	var adj_dmg: Array = []
	var adj_rate: Array = []
	var adj_range: Array = []
	for i in N:
		adj_dmg.append(1.0)
		adj_rate.append(1.0)
		adj_range.append(0.0)
	for i in N:
		var sid: String = id_at(i)
		if sid == "":
			continue
		var m: float = pow(1.35, float(lvl_at(i) - 1))
		match sid:
			"armory":
				for n in neighbors(i):
					if id_at(n) != "" or n == CORE_SLOT:
						adj_dmg[n] = float(adj_dmg[n]) + 0.15 * m
						links.append([i, n, "ARM"])
			"beacon":
				for n in N:
					if n != i and cell_dist(i, n) <= 2 and (id_at(n) != "" or n == CORE_SLOT):
						adj_rate[n] = float(adj_rate[n]) + 0.10 * m
						adj_range[n] = float(adj_range[n]) + 0.3 * m
						links.append([i, n, "BEA"])
			"oilmill":
				for n in neighbors(i):
					if id_at(n) != "":
						adj_rate[n] = float(adj_rate[n]) - 0.10
						links.append([i, n, "OIL"])
	# Core attack range (cells) first: Lance Focus taxes buildings inside it.
	var core_range_c: float = maxf(1.0, float(cd["range"]) + 0.1 * float(tracks["range"]) + range_add + float(adj_range[CORE_SLOT]) + pf("range"))
	var core_range: float = core_range_c * px
	var focus: bool = String(cd.get("trait", "")) == "focus"
	var weapons: Array = st["weapons"]
	var rr: float = TuneRef.num("pc_ring_range", 0.08)
	var hp_add: float = 0.0
	var cash_add: float = 0.0
	for i in N:
		var id: String = id_at(i)
		if id == "":
			continue
		var m2: float = pow(1.35, float(lvl_at(i) - 1))
		var ring_m: float = 1.0 + rr * float(maxi(0, ring_of(i) - 1))
		var rate_m: float = rate_all * float(adj_rate[i]) * maxf(0.1, 1.0 + pf("bld_rate"))
		if focus and slot_pos(i).distance_to(CENTER) <= core_range:
			rate_m *= 1.0 - 0.10 * tm
		var dm: float = dmg_all * float(adj_dmg[i]) * bld_dmg() * maxf(0.1, 1.0 + pf("bld_dmg"))
		var rng_c: float = float(adj_range[i]) + range_add
		match id:
			"gun":
				weapons.append({"slot": i, "kind": "gun", "dmg": 6.0 * m2 * dm, "rate": 2.0 * rate_m, "range": (3.0 + rng_c) * px * ring_m})
			"mortar":
				weapons.append({"slot": i, "kind": "mortar", "dmg": 18.0 * m2 * dm, "rate": 0.4 * rate_m, "range": (4.5 + rng_c) * px * ring_m, "splash": 1.0 * px, "min_range": 1.5 * px})
			"tesla":
				weapons.append({"slot": i, "kind": "tesla", "dmg": 9.0 * m2 * dm * (1.0 + pf("chain_dmg")), "rate": 0.8 * rate_m, "range": (3.0 + rng_c) * px * ring_m, "chains": 3 + int(pf("chain")), "chain_frac": 0.7})
			"flak":
				weapons.append({"slot": i, "kind": "flak", "dmg": 8.0 * m2 * dm, "rate": 1.5 * rate_m, "range": (3.5 + rng_c) * px * ring_m, "prey": 2.5})
			"railgun":
				weapons.append({"slot": i, "kind": "railgun", "dmg": 60.0 * m2 * dm, "rate": 0.25 * rate_m, "range": (7.0 + rng_c) * px * ring_m, "pierce": 14.0})
			"frost":
				weapons.append({"slot": i, "kind": "frost", "dmg": 1.5 * m2 * dm, "rate": 2.0, "range": (2.5 + rng_c) * px, "slow": 0.30, "slow_t": 0.6})
			"bulwark":
				hp_add += 40.0 * m2
				links.append([i, CORE_SLOT, "BUL"])
			"aegis":
				st["shield_max"] = float(st["shield_max"]) + 60.0 * m2
				st["shield_regen"] = float(st["shield_regen"]) + 6.0 * m2
			"barricade":
				var q: int = cell_quad(i)
				var wl: Dictionary = st["walls"]
				wl[q] = float(wl.get(q, 0.0)) + TuneRef.num("pc_wall_hp", 200.0) * m2 * pow(dmg_growth, float(wave - 1))
			"mine":
				cash_add += 0.8 * m2
			"oilmill":
				cash_add += 2.0 * m2
			"refinery":
				cash_add += 0.5 * m2
				st["xp_mult"] = float(st["xp_mult"]) + 0.15 * m2
			"bounty":
				(st["bounties"] as Array).append({"slot": i, "pos": slot_pos(i), "r": 3.0 * px, "mult": 0.20 * m2})
			"vault":
				st["interest_rate"] = float(st["interest_rate"]) + 0.02 * m2
				st["interest_cap"] = float(st["interest_cap"]) + 100.0 * m2
			"obelisk":
				st["lifesteal"] = float(st["lifesteal"]) + 0.01 * m2
			"hut_infantry", "hut_sapper", "hut_drone":
				var dir: Vector2 = (slot_pos(i) - CENTER).normalized()
				(st["huts"] as Array).append({"slot": i, "id": id, "lvl": lvl_at(i), "home": slot_pos(i), "anchor": CENTER + dir * (STOP_R + 0.6 * px)})
	# Core sheet with tracks, packs, legacy core levels, Insight.
	var arm_n: int = tracks["armor"]
	st["max_hp"] = (float(st["max_hp"]) + hp_add) * (1.0 + 0.05 * float(arm_n)) * (1.0 + 0.20 * float(pack_n("pk_fort"))) * maxf(0.5, 1.0 - 0.05 * float(pack_n("pk_overclock"))) * max_hp_mult * (1.0 + float(ins.get("in_hp", 0.0))) * od_hp * maxf(0.1, 1.0 + pf("core_hp"))
	st["regen"] = (float(st["regen"]) + 0.2 * float(arm_n)) * maxf(0.0, 1.0 + pf("regen"))
	st["armor"] = float(st["armor"]) + 0.5 * float(arm_n) + float(pack_n("pk_fort")) + pf("armor")
	var eco_lv: int = tracks["eco"]
	var cash_w1: float = maxf(0.0, float(st["cash_ps"]) + 0.4 * float(eco_lv) + 0.6 * float(pack_n("pk_ledger")) + cash_add + pf("cash_flat"))
	st["cash_ps"] = cash_w1 * e * cash_mult * (1.0 + float(ins.get("in_cash", 0.0))) * steadfast * maxf(0.1, 1.0 + pf("cash"))
	st["kill_cash"] = (1.0 + 0.05 * float(pack_n("pk_ledger"))) * (1.0 + float(ins.get("in_cash", 0.0))) * maxf(0.1, 1.0 + pf("kill_cash"))
	st["interest_rate"] = float(st["interest_rate"]) + pf("interest")
	var icap_w1: float = float(st["interest_cap"]) + 5.0 * float(eco_lv) + (50.0 if pf("interest") > 0.0 else 0.0)
	if String(cd.get("trait", "")) == "compound":
		icap_w1 += 10.0 * float(eco_lv) * tm
	st["interest_cap"] = icap_w1 * e
	# The Core's own weapon (always last in `weapons`; the view reads .back()).
	var core_dmg: float = float(cd["dmg"]) * CoreDB.lvl_mult("dmg", L) * dmg_all * steadfast * float(adj_dmg[CORE_SLOT]) * (1.0 + 0.30 * float(pack_n("pk_core"))) * maxf(0.1, 1.0 + pf("core_dmg"))
	var core_rate: float = float(cd["rate"]) * (1.0 + 0.03 * float(tracks["rate"])) * rate_all * float(adj_rate[CORE_SLOT]) * (1.0 + 0.10 * float(pack_n("pk_core"))) * maxf(0.1, 1.0 + pf("rate"))
	var cw: Dictionary = {"slot": CORE_SLOT, "kind": "core", "attack": String(cd["attack"]), "dmg": core_dmg, "rate": core_rate, "range": core_range, "range_cells": core_range_c}
	# Parts on the Core attack: primary-target mult, splash, pierce, free pulse.
	cw["single_mult"] = maxf(0.1, 1.0 + pf("core_single"))
	cw["pierce"] = int(pf("pierce"))
	cw["storm_pulse"] = int(pf("storm_pulse"))
	cw["pulse_mult"] = 1.0 + pf("pulse_dmg")
	var nosplash: bool = pf("nosplash") > 0.0
	match String(cd["attack"]):
		"cannon":
			cw["splash"] = 0.0 if nosplash else (float(cd["splash"]) + pf("splash")) * px
			cw["splash_frac"] = float(cd["splash_frac"])
			cw["barrels"] = 2 if L >= 20 else 1
		"slag":
			cw["splash"] = (0.25 if nosplash else (float(cd["splash"]) + pf("splash"))) * px * (1.5 if L >= 20 else 1.0)
			cw["slow"] = float(cd["slow"])
			cw["slow_t"] = float(cd["slow_t"])
		"beam":
			cw["ramp"] = float(cd["ramp"]) * (1.0 + pf("beam_ramp"))
			cw["ramp_max"] = 2.0 if L >= 20 else float(cd["ramp_max"])
			cw["boss_mult"] = 1.0 + 0.25 * tm
			cw["retarget"] = maxf(0.0, pf("retarget"))
		"pulse":
			cw["rings"] = (2 if L >= 20 else 1) + int(pf("chain"))
			cw["knock"] = float(cd["knock"])
			cw["chain_every"] = int(cd["chain_every"])
			cw["chain_frac"] = float(cd["chain_frac"]) * tm * (1.0 + pf("chain_dmg"))
			cw["chain_n"] = int(cd["chain_n"])
	if focus:
		cw["boss_mult"] = 1.0 + 0.25 * tm
	weapons.append(cw)
	st["xp_mult"] = float(st["xp_mult"]) * xp_mod
	st["crit"] = float(st["crit"]) + pf("crit")
	st["boss_mult"] = 1.0 + pf("boss")
	st["normal_mult"] = maxf(0.1, 1.0 + pf("normal_dmg"))
	st["reflect"] = pf("reflect")
	st["shred"] = pf("shred")
	# Perks (B7) multiply weapons / HP / regen / cash / XP.
	Perks.apply(st, perks_taken)
	st["cash_ps"] = float(st["cash_ps"]) * float(st["perk_cash"])
	# Display hooks the current view reads.
	st["overcharge_step"] = TuneRef.num("pc_track_dmg_step", 1.08) - 1.0
	st["overcharge"] = dmg_track
	st["bounty_mult"] = float(st["kill_cash"])
	return st


func recompute() -> void:
	var old_max: float = float(stats.get("max_hp", 0.0))
	stats = compute_stats()
	_sync_walls()
	var new_max: float = float(stats["max_hp"])
	if old_max > 0.0 and new_max > old_max:
		hp += new_max - old_max   # HP gains heal by their bonus
	hp = minf(hp, new_max)
	shield = minf(shield, float(stats.get("shield_max", 0.0)))
	troop_counter["ev"] = Troops.sync(troops, stats.get("huts", []), _troop_mods(), troop_counter)


## Troop stat modifiers: Damage track + packs + Drill Sergeant; troop HP tracks
## enemy dmg growth so troops stay relevant deep into a run.
func _troop_mods() -> Dictionary:
	var bar: float = 1.0 + 0.25 * float(pack_n("pk_barracks"))
	var tier_b: float = (1.0 + 0.10 * float(int(mods.get("barracks_tier", 0)))) * (1.0 + float(mods.get("barracks_bonus", 0.0)))
	return {
		"dmg_mult": float(stats.get("dmg_all", 1.0)) * bar * tier_b * maxf(0.1, 1.0 + pf("troop_dmg")),
		"hp_mult": bar * tier_b * pow(dmg_growth, float(wave - 1)) * hp_mult * maxf(0.1, 1.0 + pf("troop_hp")),
		"respawn_minus": 2.0 * float(pack_n("pk_barracks")),
		"respawn_mult": maxf(0.2, 1.0 + pf("troop_respawn")),
		"extra": int(pf("troop_count")),
		"extra_drone": int(pf("hut_drone")),
		"cell_px": cpx(),
	}


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


## Track level cap (Tune pc_track_cap_<id> overrides the table).
static func track_cap(t: String) -> int:
	return TuneRef.int_of("pc_track_cap_" + t, int((TRACKS[t] as Dictionary)["cap"]))


## Cost of the next level of a Core cash track (base * growth^lvl, Logistics
## packs -12% each, Miser perk); -1 when capped.
func track_cost(t: String) -> int:
	if not TRACKS.has(t):
		return -1
	var td: Dictionary = TRACKS[t]
	var lv: int = int(tracks[t])
	if lv >= track_cap(t):
		return -1
	var g: float = TuneRef.num("pc_track_growth_" + t, float(td["growth"]))
	var pm: float = float(stats.get("perk_upgrade_cost", 1.0)) * pow(0.88, float(pack_n("pk_logistics")))
	return maxi(1, int(round(float(td["base"]) * pow(g, float(lv)) * pm)))


## Legacy view hook: the Core cell's cost is the Damage track; buildings level
## only through duplicate picks now (0 = no cash upgrade).
func upgrade_cost(i: int) -> int:
	if i == CORE_SLOT:
		return track_cost("dmg")
	return 0


func unlock_cost() -> int:
	return 0


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
	hp = minf(float(stats["max_hp"]), hp + (float(stats["regen"]) + float(buffs["repair_rate"]) * (1.0 if float(buffs["repair_t"]) > 0.0 else 0.0)) * dt)
	immune_t = maxf(0.0, immune_t - dt)
	if pf("interest_fast") > 0.0 and wave_started:
		interest_t += dt
		if interest_t >= 15.0:
			interest_t -= 15.0
			_pay_interest(ev)
	_tick_buffs(dt, ev)
	_move_enemies(dt, ev)
	_fire(dt, ev)
	_troops_step(dt, ev)
	_reap(ev)
	_check_queue(ev)
	if hp <= 0.0 and not over:
		_on_death(ev)


## Buff timers, Aegis shield regen, special cooldowns, pending Orbitals.
func _tick_buffs(dt: float, ev: Array) -> void:
	for k in ["overdrive_t", "magnet_t", "repair_t", "warp_t"]:
		buffs[k] = maxf(0.0, float(buffs[k]) - dt)
	shield_idle += dt
	var smax: float = float(stats.get("shield_max", 0.0))
	if smax > 0.0 and shield < smax and shield_idle >= TuneRef.num("pc_aegis_idle", 4.0):
		shield = minf(smax, shield + float(stats.get("shield_regen", 0.0)) * dt)
	var rdy: Array = Specials.tick(specials, dt)
	# Battery Bank: a cooldown that finishes while a charge is free banks it
	# and restarts, so up to 1 + special_charges casts are stored.
	var cap: int = int(pf("special_charges"))
	if cap > 0:
		for r in rdy:
			var sk: int = int((r as Dictionary)["slot"])
			var sd: Dictionary = specials[sk]
			if int(sd.get("bank", 0)) < cap:
				sd["bank"] = int(sd.get("bank", 0)) + 1
				Specials.consume(specials, sk, float(mods.get("special_cd", 1.0)))
	ev.append_array(rdy)
	if orbitals.is_empty():
		return
	var keep: Array = []
	for o in orbitals:
		var od: Dictionary = o
		od["t"] = float(od["t"]) - dt
		if float(od["t"]) > 0.0:
			keep.append(od)
			continue
		var c: Vector2 = od["pos"]
		var n: int = 0
		for e in enemies:
			var ed: Dictionary = e
			if float(ed["hp"]) > 0.0 and (ed["pos"] as Vector2).distance_to(c) <= float(od["r"]) + float(ed["size"]) * 0.5:
				_hit(ed, float(od["dmg"]), ev)
				n += 1
		ev.append({"t": "orbital_hit", "pos": c, "r": float(od["r"]), "hits": n})
	orbitals = keep


## Interest on banked cash (Core + Vaults), paid before the next wave starts.
func _wave_end(ev: Array) -> void:
	last_stand_used = false
	if pf("interest_fast") > 0.0:
		return   # Mint 4-piece pays interest every 15 s instead (see _step)
	_pay_interest(ev)


func _pay_interest(ev: Array) -> void:
	var rate: float = float(stats.get("interest_rate", 0.0))
	var cap: float = float(stats.get("interest_cap", 0.0))
	var amt: float = minf(cash * rate, cap)
	if amt > 0.0:
		cash += amt
		cash_earned += amt
		ev.append({"t": "interest", "amt": amt, "slot": CORE_SLOT, "cap": cap})


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


## Draft cadence (REDESIGN_SPEC §2.3): after waves 1, 2, 3, then every 2nd
## wave, plus every boss wave (that one guarantees an Epic+).
func _queue_drafts(cleared: int) -> void:
	if cleared <= 3 or cleared % maxi(1, TuneRef.int_of("pc_draft_every", 2)) == 0:
		draft_queue.append("")
	if cleared % boss_every == 0:
		draft_queue.append("epic")


func _advance_wave(ev: Array) -> void:
	_queue_drafts(wave)
	_enter_wave(wave + 1)
	# Wave Skip card (B8): this wave is skipped (50% coins, no kills) and the
	# run jumps straight to the next one.
	if skip_chance > 0.0 and combat_rng.randf() < skip_chance:
		var skipped: int = wave
		var c: float = _wave_coins(skipped, 0.5)
		_enter_wave(wave + 1)
		ev.append({"t": "wave_skip", "skipped": skipped, "wave": wave, "coins": c})
	_wave_coins(wave, 1.0)
	recompute()   # cash/s, walls and troops scale with the wave
	_drain_troop_events(ev)
	ev.append({"t": "wave", "wave": wave})
	if next_plan.is_empty() or int(next_plan["wave"]) != wave:
		next_plan = _build_plan(wave, 0.0)
		ev.append(_telegraph_event(next_plan))   # late telegraph (skipped wave)
	_adopt_plan(next_plan, ev, false)
	if wave % boss_every == 0:
		_spawn("boss", ev, Vector2.INF, boss_dir)
	if Drops.courier_roll(drop_rng, wave):
		_spawn_courier(ev)


func _drain_troop_events(ev: Array) -> void:
	var tev: Variant = troop_counter.get("ev", [])
	if tev is Array and not (tev as Array).is_empty():
		ev.append_array(tev as Array)
	troop_counter["ev"] = []


func _on_death(ev: Array) -> void:
	if wind_hp > 0.0 and not wind_used:
		wind_used = true
		hp = float(stats["max_hp"]) * wind_hp
		ev.append({"t": "revive", "hp": hp})
		return
	hp = 0.0
	over = true
	var cashout: int = int(floor(TuneRef.num("cashout_frac", 0.12) * cash_earned / maxf(1.0, cash_index()) * tier_coin_mult * mod_coin * mode_coin))
	var coins: int = int(coins_run) + cashout
	var bd: Dictionary = {
		"wave": int(coins_wave), "kills": int(coins_kill), "boss": int(coins_boss),
		"cashout": cashout, "mult": run_coin_mult(), "tier": tier, "gems": gems_run,
		"mod_mult": mod_coin, "mode_mult": mode_coin,
	}
	var build: Array = []
	for i in N:
		build.append(id_at(i))
	ev.append({"t": "game_over", "wave": wave, "coins": coins, "kills": kills, "cash_earned": int(cash_earned), "breakdown": bd, "perks": perks_taken.duplicate(),
		"seed": run_seed, "tier": tier, "mode": mode, "modifiers": modifiers.duplicate(), "mutations": mutations_taken.duplicate(),
		"duration_s": time_alive, "build": build, "ts": now_unix, "dps": dps(),
		"core": core_id, "core_lvl": core_lvl, "picks": picks_taken.duplicate(), "insight": insight_found.duplicate(),
		"loot": loot.duplicate(true), "specials_cast": special_casts, "tracks": tracks.duplicate(), "couriers": _couriers_caught()})
	# Endless records its own best and never feeds the tier ladder (§3.1).
	ev.append_array(BaseMeta.bank(save, coins, wave, tier, time_alive / 60.0, now_unix, gems_run, mode != "endless"))
	if mode == "endless":
		BaseMeta.record_endless(save, wave)
	# Insight (win or loss) + loot are banked permanently.
	ev.append_array(PickDB.bank_insight(save, insight_found))
	ev.append_array(BaseMeta.bank_loot(save, loot, drop_rng))
	ev.append({"t": "dead", "wave": wave, "coins": coins, "kills": kills, "cash_earned": int(cash_earned), "breakdown": bd})


func _couriers_caught() -> int:
	var n: int = 0
	for p in loot.get("parts", []):
		if String((p as Dictionary).get("source", "")) == "courier":
			n += 1
	return n


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
## the first spawn (wave 1 opens with the telegraph lead). A marked elite
## (loot carrier, from w8) is chosen on the separate drop RNG.
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
	if entries.size() > 0 and Drops.elite_mark_roll(drop_rng, w):
		var mi: int = drop_rng.randi_range(entries.size() / 4, entries.size() - 1)
		(entries[mi] as Dictionary)["marked"] = true
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
		if _spawn(String(pe["kind"]), ev, Vector2.INF, q, bool(pe.get("marked", false))):
			wave_spawned[q] = int(wave_spawned.get(q, 0)) + 1


## Lane focus (Orbital auto-target prefers it): one of the 4 quadrants.
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


func _spawn(kind: String, ev: Array, at: Vector2 = Vector2.INF, quad: int = -1, marked: bool = false) -> bool:
	if enemies.size() >= MAX_ENEMIES:
		return false
	var d: Dictionary = EnemyDB.get_def(kind)
	var sc: float = scale() * hp_mult * float(stats.get("perk_enemy_hp", 1.0)) * enemy_hp_mod * (1.0 + 0.15 * float(pack_n("pk_gambit")))
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
		"size": float(d["size"]), "atk_cd": 0.0, "slow_t": 0.0, "slow_m": 1.0,
		"shield": 0, "fire_cd": 0.0, "shock_t": 0.0, "shock_src": -1,
		"hit_t": 0.0, "eid": next_eid, "taunt_t": 0.0,
	}
	next_eid += 1
	match kind:
		"boss":
			# Boss HP relative to EnemyDB from Tier 2 up; T1's first boss (w10)
			# stays gentle and the extra toughness phases in by wave 30.
			var r0: float = TuneRef.num("boss_ramp_from", 10.0)
			var ramp: float = clampf((float(wave) - r0) / 20.0, 0.0, 1.0)
			var bm: float = TuneRef.num("boss_hp_hi", 0.5) if tier >= 2 else 1.0 + (TuneRef.num("boss_hp_t1", 2.5) - 1.0) * ramp
			if tier == 1 and wave <= 10:
				bm *= TuneRef.num("pc_first_boss", 0.6)   # the very first boss teaches, it does not wall
			e["hp"] = float(e["hp"]) * bm
			e["max_hp"] = float(e["max_hp"]) * bm
			e["dmg"] = float(e["dmg"]) * TuneRef.num("pc_boss_dmg", 1.0)
		"elite":
			e["shield"] = TuneRef.int_of("elite_shield_base", 3) + wave / 10 + elite_shield_add
			e["max_shield"] = int(e["shield"])
		"ranged":
			e["fire_cd"] = TuneRef.num("ranged_fire", 2.0)
	if marked:
		e["marked"] = true
		e["hp"] = float(e["hp"]) * TuneRef.num("pc_mark_hp", 3.0)
		e["max_hp"] = float(e["max_hp"]) * TuneRef.num("pc_mark_hp", 3.0)
	e["quad"] = quad_of(pos)
	enemies.append(e)
	if kind == "boss":
		ev.append({"t": "boss", "pos": e["pos"], "quad": int(e["quad"])})
	if marked:
		ev.append({"t": "elite_marked", "eid": int(e["eid"]), "pos": e["pos"]})
	return true


## Courier (REDESIGN §2.6): a rare loot runner that crosses the field on a
## chord well outside the wall at 3x speed and escapes if not killed.
func _spawn_courier(ev: Array) -> void:
	var q: int = int(active_quads[0]) if active_quads.size() > 0 else 0
	var a: float = deg_to_rad(-90.0 + 90.0 * float(q) + 22.5)
	var from: Vector2 = CENTER + Vector2.from_angle(a) * SPAWN_R
	var to: Vector2 = CENTER + Vector2.from_angle(a + deg_to_rad(110.0)) * SPAWN_R
	if not _spawn("courier", ev, from, q):
		return
	var cd: Dictionary = enemies.back()
	cd["exit"] = to
	couriers += 1
	ev.append({"t": "courier_spawn", "eid": int(cd["eid"]), "pos": from, "to": to})


func _core_damage(amt: float, ev: Array, kind: String, from: Vector2, src: Dictionary = {}) -> void:
	if immune_t > 0.0:
		return
	# Mirror Hull: contact hits reflect a share back to the attacker.
	if kind == "core_hit" and not src.is_empty() and float(stats.get("reflect", 0.0)) > 0.0 and float(src["hp"]) > 0.0:
		_hit(src, amt * float(stats["reflect"]), ev)
	var real: float = maxf(amt * TuneRef.num("pc_armor_floor", 0.25), amt - float(stats.get("armor", 0.0)))
	real *= 1.0 - float(stats.get("dr", 0.0))
	shield_idle = 0.0
	if shield > 0.0:
		var absorb: float = minf(shield, real)
		shield -= absorb
		real -= absorb
	hp -= real
	ev.append({"t": kind, "dmg": real, "pos": from})
	# Bulwark 4-piece: dropping below 30% grants 2 s immunity once per wave.
	if pf("last_stand") > 0.0 and not last_stand_used and hp > 0.0 and hp < 0.3 * float(stats["max_hp"]):
		last_stand_used = true
		immune_t = 2.0
		ev.append({"t": "last_stand", "dur": 2.0})


func _move_enemies(dt: float, ev: Array) -> void:
	var r_stop: float = TuneRef.num("ranged_stop", 230.0)
	var r_fire: float = TuneRef.num("ranged_fire", 2.0)
	var wall_r: float = TuneRef.num("pc_wall_r", STOP_R + 50.0)
	var wall_slow: float = 1.0 - TuneRef.num("pc_wall_slow", 0.30)
	var frozen: bool = float(buffs.get("warp_t", 0.0)) > 0.0
	var escaped: Array = []
	for e in enemies:
		var ed: Dictionary = e
		var pos: Vector2 = ed["pos"]
		var slow_t: float = float(ed["slow_t"])
		var mult: float = float(ed.get("slow_m", 0.55)) if slow_t > 0.0 else 1.0
		ed["slow_t"] = maxf(0.0, slow_t - dt)
		if float(ed["slow_t"]) <= 0.0:
			ed["slow_m"] = 1.0
		ed["shock_t"] = maxf(0.0, float(ed.get("shock_t", 0.0)) - dt)
		ed["hit_t"] = maxf(0.0, float(ed.get("hit_t", 0.0)) - dt)
		if frozen:
			continue
		if String(ed["kind"]) == "courier":
			var to2: Vector2 = ed.get("exit", pos)
			var dd: Vector2 = to2 - pos
			var stp: float = float(ed["spd"]) * mult * dt
			if dd.length() <= stp:
				escaped.append(ed)
			else:
				ed["pos"] = pos + dd.normalized() * stp
			continue
		var taunt: float = float(ed.get("taunt_t", 0.0))
		if taunt > 0.0:
			ed["taunt_t"] = maxf(0.0, taunt - dt)
			continue   # pinned by a Rifleman (it is hitting the troop instead)
		var ranged: bool = String(ed["kind"]) == "ranged"
		var stop: float = r_stop if ranged else STOP_R
		var to_c: Vector2 = CENTER - pos
		var dist: float = to_c.length()
		if dist > stop + 0.001:
			# Barricade: a standing wall on this lane slows enemies pressing on
			# it, and they wear it down with their contact damage.
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
				_core_damage(float(ed["dmg"]), ev, "core_hit", pos, ed)
	for x in escaped:
		enemies.erase(x)
		ev.append({"t": "courier_escape", "eid": int((x as Dictionary).get("eid", -1)), "pos": (x as Dictionary)["pos"]})


## Targeting (pattern adapted from ape1121/Godot-4-Tower-Defense-Template, MIT:
## try_get_closest_target; first/strongest/weakest are in-house). Pure: picks
## an index into `enemies` within `rng_lim` of `from`, or -1.
func pick_target(from: Vector2, rng_lim: float, mode_s: String, flyers_only: bool = false) -> int:
	if mode_s == "nearest" and not flyers_only:
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
		if flyers_only and not FLYERS.has(String(ed["kind"])):
			continue
		var p: Vector2 = ed["pos"]
		var d2: float = from.distance_squared_to(p)
		if d2 > lim2:
			continue
		var key: float = 0.0
		match mode_s:
			"first":
				key = CENTER.distance_squared_to(p)
			"strongest":
				key = -hpv
			"nearest":
				key = d2
			_:
				key = hpv
		if key < best_key or (key == best_key and d2 < best_d):
			best_key = key
			best_d = d2
			best = k
	return best


## Set a weapon slot's targeting mode (run-scoped).
func set_target_mode(i: int, mode_s: String) -> Array:
	if i < 0 or i >= N or not TARGET_MODES.has(mode_s) or not is_weapon_slot(i):
		return []
	target_modes[i] = mode_s
	return [{"t": "target_mode", "slot": i, "mode": mode_s}]


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


## Every hit goes through here: Ironclad, an elite's shield absorbs whole
## hits, Obelisk lifesteal heals the Core.
func _hit(ed: Dictionary, dmg_in: float, ev: Array, crit: bool = false) -> void:
	var dmg: float = dmg_in
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
	# Parts: Hunter Scope (vs bosses/elites/marked, else the normal-enemy tax)
	# and Singularity Lens shred stacks (+shred per stack, x5).
	if BOSSY.has(String(ed.get("kind", ""))) or bool(ed.get("marked", false)):
		dmg *= float(stats.get("boss_mult", 1.0))
	else:
		dmg *= float(stats.get("normal_mult", 1.0))
	if int(ed.get("shred_n", 0)) > 0:
		dmg *= 1.0 + float(stats.get("shred", 0.0)) * float(int(ed["shred_n"]))
	var real: float = minf(dmg, maxf(0.0, float(ed["hp"])))
	ed["hp"] = float(ed["hp"]) - dmg
	ed["hit_t"] = HIT_FLASH
	var ls: float = float(stats.get("lifesteal", 0.0))
	if ls > 0.0 and real > 0.0:
		hp = minf(float(stats["max_hp"]), hp + real * ls)
	if crit:
		ev.append({"t": "dmg", "eid": int(ed.get("eid", 0)), "pos": ed["pos"], "amt": dmg, "crit": true})
	else:
		ev.append({"t": "dmg", "eid": int(ed.get("eid", 0)), "pos": ed["pos"], "amt": dmg})


## Overkill carry (single-target shots): damage left over after a kill rolls
## to the nearest living enemy within range of the shooter (up to
## pc_carry_hops times), so surplus DPS becomes kill throughput when the
## field floods. Shields still eat whole hits.
func _hit_carry(ed: Dictionary, dmg: float, ev: Array, crit: bool, from: Vector2, rng_lim: float) -> void:
	var cur: Dictionary = ed
	var left: float = dmg
	var done: Dictionary = {}
	for hop in TuneRef.int_of("pc_carry_hops", 2) + 1:
		var before: float = float(cur["hp"])
		var sh: int = int(cur.get("shield", 0))
		_hit(cur, left, ev, crit)
		if sh > 0 or float(cur["hp"]) > 0.0:
			return
		left = (left * (1.0 - ironclad if not crit and ironclad > 0.0 else 1.0) - maxf(0.0, before)) * TuneRef.num("pc_carry_frac", 0.6)
		if left <= 0.0:
			return
		done[cur] = true
		var best: Dictionary = {}
		var bd: float = INF
		var cpos: Vector2 = cur["pos"]
		for e in enemies:
			var x: Dictionary = e
			if done.has(x) or float(x["hp"]) <= 0.0:
				continue
			if from.distance_squared_to(x["pos"]) > rng_lim * rng_lim:
				continue
			var d2: float = cpos.distance_squared_to(x["pos"])
			if d2 <= bd:
				bd = d2
				best = x
		if best.is_empty():
			return
		cur = best


func _roll_crit(wd: Dictionary) -> bool:
	var c: float = float(stats.get("crit", 0.0)) + float(wd.get("crit", 0.0))
	return c > 0.0 and combat_rng.randf() < c


func _fire(dt: float, ev: Array) -> void:
	for w in stats["weapons"]:
		var wd: Dictionary = w
		var si: int = int(wd["slot"])
		var rate: float = float(wd["rate"])
		if si == CORE_SLOT and float(buffs.get("overdrive_t", 0.0)) > 0.0:
			rate *= 2.0
		var cd: float = float(cooldowns[si]) - dt
		if cd > 0.0:
			cooldowns[si] = cd
			if si == CORE_SLOT and String(wd.get("attack", "")) == "beam":
				_beam_hold(wd, dt)
			continue
		if si == CORE_SLOT:
			# Queen Engine: the Core holds fire while 3+ troops are alive.
			if pf("queen_hold") > 0.0 and Troops.alive_count(troops) >= 3:
				cooldowns[si] = 0.0
				continue
			if _core_fire(wd, ev):
				cooldowns[si] = cd + 1.0 / rate
				core_shots += 1
				if int(wd.get("storm_pulse", 0)) > 0 and core_shots % 10 == 0:
					_free_pulse(wd, ev)
			else:
				cooldowns[si] = 0.0
			continue
		var kind: String = wd["kind"]
		var from: Vector2 = slot_pos(si)
		if kind == "frost":
			# Aura: every pulse slows and chills every enemy in range.
			var any: bool = false
			for e in enemies:
				var fe: Dictionary = e
				if float(fe["hp"]) > 0.0 and from.distance_to(fe["pos"]) <= float(wd["range"]):
					any = true
					fe["slow_t"] = maxf(float(fe["slow_t"]), float(wd["slow_t"]))
					fe["slow_m"] = minf(float(fe.get("slow_m", 1.0)) if float(fe["slow_t"]) > 0.0 else 1.0, 1.0 - float(wd["slow"]))
					_hit(fe, float(wd["dmg"]), ev)
			if any:
				ev.append({"t": "shot", "kind": "frost", "from": from, "to": from, "radius": float(wd["range"])})
				cooldowns[si] = cd + 1.0 / rate
			else:
				cooldowns[si] = 0.0
			continue
		var tgt: int = pick_target(from, float(wd["range"]), String(target_modes[si]) if si < target_modes.size() else "nearest", kind == "flak")
		if kind == "mortar" and tgt >= 0 and from.distance_to((enemies[tgt] as Dictionary)["pos"]) < float(wd.get("min_range", 0.0)):
			tgt = -1
		if tgt < 0:
			cooldowns[si] = 0.0
			continue
		cooldowns[si] = cd + 1.0 / rate
		var dmg: float = float(wd["dmg"])
		var te: Dictionary = enemies[tgt]
		var tpos: Vector2 = te["pos"]
		var crit: bool = _roll_crit(wd)
		if crit:
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
				_hit(te, dmg * float(wd.get("prey", 2.5)), ev, crit)
				ev.append({"t": "shot", "kind": kind, "from": from, "to": tpos, "radius": 20.0})
			"mortar":
				var rad: float = float(wd["splash"])
				for e in enemies:
					var ed: Dictionary = e
					if float(ed["hp"]) <= 0.0:
						continue
					if (ed["pos"] as Vector2).distance_to(tpos) <= rad:
						_hit(ed, dmg, ev, crit)
				ev.append({"t": "shot", "kind": kind, "from": from, "to": tpos, "radius": rad})
			"tesla":
				var hit: Dictionary = {}
				var prev: Vector2 = from
				var cur: int = tgt
				var n: int = int(wd["chains"])
				var d2: float = dmg
				while cur >= 0 and hit.size() < n:
					hit[cur] = true
					var ce: Dictionary = enemies[cur]
					_hit(ce, d2, ev, crit)
					ce["slow_t"] = maxf(float(ce["slow_t"]), 0.6)
					ce["shock_t"] = 1.5
					ce["shock_src"] = si
					var cpos: Vector2 = ce["pos"]
					ev.append({"t": "shot", "kind": kind, "from": prev, "to": cpos})
					prev = cpos
					d2 *= float(wd.get("chain_frac", 0.7))
					cur = _nearest(cpos, 90.0, hit)
			_:
				_hit_carry(te, dmg, ev, crit, from, float(wd["range"]))
				ev.append({"t": "shot", "kind": kind, "from": from, "to": tpos})


## Lance beam: the ramp builds while the beam stays on one living target.
func _beam_hold(wd: Dictionary, dt: float) -> void:
	if beam_eid < 0:
		return
	for e in enemies:
		var ed: Dictionary = e
		if int(ed.get("eid", -1)) == beam_eid and float(ed["hp"]) > 0.0 and CENTER.distance_to(ed["pos"]) <= float(wd["range"]):
			beam_t += dt
			return
	beam_eid = -1
	beam_t = 0.0


## The Core's attack (REDESIGN §2.1). Emits core_attack{kind, targets} and a
## legacy `shot` (kind "core") the current view already draws. Returns false
## when nothing is in range (the attack stays ready).
func _core_fire(wd: Dictionary, ev: Array) -> bool:
	var atk: String = String(wd.get("attack", "cannon"))
	var rng_lim: float = float(wd["range"])
	var dmg: float = float(wd["dmg"])
	var targets: Array = []
	match atk:
		"cannon":
			var barrels: int = int(wd.get("barrels", 1))
			var hit_any: bool = false
			var skip: Dictionary = {}
			for b in barrels:
				var tgt: int = pick_target(CENTER, rng_lim, String(target_modes[CORE_SLOT]))
				if b > 0:
					var alt: int = _nearest(CENTER, rng_lim, skip)
					tgt = alt if alt >= 0 else tgt
				if tgt < 0:
					break
				skip[tgt] = true
				hit_any = true
				var te: Dictionary = enemies[tgt]
				var tpos: Vector2 = te["pos"]
				var crit: bool = _roll_crit(wd)
				var d: float = dmg * (TuneRef.num("pc_crit_mult", 2.0) if crit else 1.0)
				_hit_carry(te, d * float(wd.get("single_mult", 1.0)), ev, crit, CENTER, rng_lim)
				_shred(te, wd)
				targets.append(int(te.get("eid", -1)))
				_pierce(te, d, wd, ev, targets)
				var rad: float = float(wd.get("splash", 0.0))
				for e in enemies:
					var ed: Dictionary = e
					if ed != te and float(ed["hp"]) > 0.0 and (ed["pos"] as Vector2).distance_to(tpos) <= rad:
						_hit(ed, d * float(wd.get("splash_frac", 0.4)), ev)
						targets.append(int(ed.get("eid", -1)))
				ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": tpos, "radius": rad})
			if not hit_any:
				return false
		"slag":
			var tgt2: int = pick_target(CENTER, rng_lim, String(target_modes[CORE_SLOT]))
			if tgt2 < 0:
				return false
			var tpos2: Vector2 = (enemies[tgt2] as Dictionary)["pos"]
			var crit2: bool = _roll_crit(wd)
			var d2: float = dmg * (TuneRef.num("pc_crit_mult", 2.0) if crit2 else 1.0)
			var rad2: float = float(wd["splash"])
			for e in enemies:
				var ed: Dictionary = e
				if float(ed["hp"]) > 0.0 and (ed["pos"] as Vector2).distance_to(tpos2) <= rad2:
					_hit(ed, d2, ev, crit2)
					ed["slow_t"] = maxf(float(ed["slow_t"]), float(wd["slow_t"]))
					ed["slow_m"] = minf(float(ed.get("slow_m", 1.0)) if float(ed["slow_t"]) > 0.0 else 1.0, 1.0 - float(wd["slow"]))
					targets.append(int(ed.get("eid", -1)))
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": tpos2, "radius": rad2})
		"beam":
			# Lock the highest-HP enemy in range; the ramp resets on a switch.
			var tgt3: int = pick_target(CENTER, rng_lim, "strongest")
			if tgt3 < 0:
				beam_eid = -1
				beam_t = 0.0
				return false
			var te3: Dictionary = enemies[tgt3]
			if int(te3.get("eid", -1)) != beam_eid:
				beam_eid = int(te3.get("eid", -1))
				beam_t = -float(wd.get("retarget", 0.0))   # Focus Lens retarget delay
			var ramp: float = clampf(float(wd["ramp"]) * beam_t, 0.0, float(wd["ramp_max"]))
			var d3: float = dmg * (1.0 + ramp) * float(wd.get("single_mult", 1.0))
			if BOSSY.has(String(te3["kind"])) or bool(te3.get("marked", false)):
				d3 *= float(wd.get("boss_mult", 1.0))
			var crit3: bool = _roll_crit(wd)
			if crit3:
				d3 *= TuneRef.num("pc_crit_mult", 2.0)
			_hit_carry(te3, d3, ev, crit3, CENTER, rng_lim)
			_shred(te3, wd)
			targets.append(int(te3.get("eid", -1)))
			_pierce(te3, d3, wd, ev, targets)
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": te3["pos"], "beam": true, "ramp": ramp})
		"pulse":
			var rings: int = int(wd.get("rings", 1))
			var inside: Array = []
			for e in enemies:
				var ed: Dictionary = e
				if float(ed["hp"]) > 0.0 and CENTER.distance_to(ed["pos"]) <= rng_lim + float(ed["size"]) * 0.5:
					inside.append(ed)
			if inside.is_empty():
				return false
			pulse_n += 1
			var crit4: bool = _roll_crit(wd)
			var d4: float = dmg * float(rings) * float(wd.get("pulse_mult", 1.0)) * (TuneRef.num("pc_crit_mult", 2.0) if crit4 else 1.0)
			var kb: float = float(wd.get("knock", 0.3)) * 40.0
			for x in inside:
				var xd: Dictionary = x
				_hit(xd, d4, ev, crit4)
				targets.append(int(xd.get("eid", -1)))
				if String(xd["kind"]) != "boss" and String(xd["kind"]) != "courier":
					var away: Vector2 = ((xd["pos"] as Vector2) - CENTER).normalized()
					xd["pos"] = (xd["pos"] as Vector2) + away * kb
			# Static: every 5th pulse chains 40% dmg to 3 targets beyond range.
			if int(wd.get("chain_every", 0)) > 0 and pulse_n % int(wd["chain_every"]) == 0:
				var outer: Array = []
				for e in enemies:
					var od: Dictionary = e
					if float(od["hp"]) > 0.0 and not inside.has(od):
						outer.append(od)
				outer.sort_custom(func(a: Variant, b: Variant) -> bool: return CENTER.distance_squared_to((a as Dictionary)["pos"]) < CENTER.distance_squared_to((b as Dictionary)["pos"]))
				for k in mini(int(wd["chain_n"]), outer.size()):
					var cd2: Dictionary = outer[k]
					_hit(cd2, dmg * float(wd["chain_frac"]), ev)
					targets.append(int(cd2.get("eid", -1)))
					ev.append({"t": "shot", "kind": "tesla", "from": CENTER, "to": cd2["pos"]})
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": CENTER, "radius": rng_lim, "pulse": true})
	ev.append({"t": "core_attack", "kind": atk, "core": core_id, "targets": targets})
	return true


## Lancer 4-piece: the Core shot also hits the nearest other enemy to its target.
func _pierce(te: Dictionary, d: float, wd: Dictionary, ev: Array, targets: Array) -> void:
	if int(wd.get("pierce", 0)) <= 0:
		return
	var skip: Dictionary = {}
	for k in enemies.size():
		if enemies[k] == te:
			skip[k] = true
	for n in int(wd["pierce"]):
		var j: int = _nearest(te["pos"], cpx() * 1.5, skip)
		if j < 0:
			return
		skip[j] = true
		_hit(enemies[j], d, ev)
		targets.append(int((enemies[j] as Dictionary).get("eid", -1)))


## Singularity Lens: Core hits stack armor shred on the target (max 5).
func _shred(te: Dictionary, _wd: Dictionary) -> void:
	if float(stats.get("shred", 0.0)) > 0.0:
		te["shred_n"] = mini(5, int(te.get("shred_n", 0)) + 1)


## Storm 4-piece: a free Pulse Ring (Core dmg, Core range, x pulse_mult).
func _free_pulse(wd: Dictionary, ev: Array) -> void:
	var targets: Array = []
	var d: float = float(wd["dmg"]) * float(wd.get("pulse_mult", 1.0))
	for e in enemies:
		var ed: Dictionary = e
		if float(ed["hp"]) > 0.0 and CENTER.distance_to(ed["pos"]) <= float(wd["range"]) + float(ed["size"]) * 0.5:
			_hit(ed, d, ev)
			targets.append(int(ed.get("eid", -1)))
	ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": CENTER, "radius": float(wd["range"]), "pulse": true})
	ev.append({"t": "core_attack", "kind": "pulse", "core": core_id, "targets": targets, "free": true})


## Troops: reconcile with huts, step the AI, apply their hits through _hit.
func _troops_step(dt: float, ev: Array) -> void:
	_drain_troop_events(ev)
	if troops.is_empty():
		return
	var res: Dictionary = Troops.step(troops, enemies, dt, {"cell_px": cpx()})
	ev.append_array(res["ev"])
	for h in res["hits"]:
		var hd: Dictionary = h
		var eid: int = int(hd["eid"])
		for e in enemies:
			var ed: Dictionary = e
			if int(ed.get("eid", -2)) == eid and float(ed["hp"]) > 0.0:
				_hit(ed, float(hd["dmg"]), ev)
				# Swarm 4-piece: troops lifesteal 1%; a troop kill heals the Core.
				if pf("troop_ls") > 0.0:
					_troop_heal(int(hd.get("tid", -1)), 0.01 * float(hd["dmg"]))
					if float(ed["hp"]) <= 0.0:
						hp = minf(float(stats["max_hp"]), hp + 0.5)
				break


func _troop_heal(tid: int, amt: float) -> void:
	for t in troops:
		var td: Dictionary = t
		if int(td["tid"]) == tid and String(td["state"]) != "dead":
			td["hp"] = minf(float(td["max_hp"]), float(td["hp"]) + amt)
			return


func _reap(ev: Array) -> void:
	var alive: Array = []
	var splits: Array = []
	var cm: float = run_coin_mult()
	var ci: float = cash_index()
	var magnet: float = 2.0 if float(buffs.get("magnet_t", 0.0)) > 0.0 else 1.0
	for e in enemies:
		var ed: Dictionary = e
		if float(ed["hp"]) > 0.0:
			alive.append(ed)
			continue
		var pos: Vector2 = ed["pos"]
		var bm: float = 1.0
		for b in stats.get("bounties", []):
			var bd: Dictionary = b
			if (bd["pos"] as Vector2).distance_to(pos) <= float(bd["r"]):
				bm += float(bd["mult"])
		var gain: float = float(ed["cash"]) * ci * bm * float(stats.get("kill_cash", 1.0)) * run_cash_mult() * kill_cash_mod * magnet
		cash += gain
		cash_earned += gain
		xp += float(ed["xp"]) * float(stats["xp_mult"])
		var cg: float = float(ed["coin"]) * cm
		coins_run += cg
		coins_kill += cg
		kills += 1
		var kind: String = ed["kind"]
		ev.append({"t": "kill", "pos": pos, "cash": gain, "kind": kind})
		if kind == "boss":
			_boss_bounty(pos, ev)
		elif kind == "splitter":
			splits.append(pos)
		_roll_drops(ed, ev)
	enemies = alive
	var nc: int = TuneRef.int_of("splitter_children", 2)
	for p in splits:
		var sp: Vector2 = p
		for k in nc:
			_spawn("mite", ev, sp + Vector2.from_angle(TAU * float(k) / float(maxi(1, nc))) * 10.0)
		ev.append({"t": "split", "pos": sp, "n": nc})


## Loot (REDESIGN §2.6) on the separate drop RNG: boss / elite / marked /
## Courier parts, boss Scrap, rare Keys.
func _roll_drops(ed: Dictionary, ev: Array) -> void:
	var kind: String = String(ed["kind"])
	var src: String = "kill"
	if kind == "boss":
		src = "boss"
	elif kind == "courier":
		src = "courier"
	elif kind == "elite" or bool(ed.get("marked", false)):
		src = "elite"
	var ctx: Dictionary = {"tier": tier, "drop_mult": 1.0 + float(ins.get("in_drop", 0.0)), "parts_so_far": Drops.capped_count(loot)}
	var got: Array = Drops.add(loot, Drops.roll(drop_rng, src, ctx))
	for x in got:
		var d: Dictionary = (x as Dictionary).duplicate()
		d["t"] = "drop"
		d["pos"] = ed["pos"]
		ev.append(d)


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
	_check_draft(ev)
	_check_perk(ev)


func _busy() -> bool:
	return draft.size() > 0 or pending_place != "" or perk_offer.size() > 0 or mutation_offer.size() > 0


## Endless mutation pick (every 25 waves): 3 distinct, non-maxed mutations.
func _check_mutation(ev: Array) -> void:
	if mutation_pending <= 0 or _busy():
		return
	mutation_pending -= 1
	var pool: Array = []
	for id in ModifierDB.MUTATION_IDS:
		if mutations_taken.count(id) < ModifierDB.MUTATION_STACK:
			pool.append(id)
	for i in range(pool.size() - 1, 0, -1):
		var j: int = draft_rng.randi_range(0, i)
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


## XP level-ups bank a free draft reroll (drafts follow the wave cadence).
func _check_level(ev: Array) -> void:
	while xp >= xp_need():
		xp -= xp_need()
		level += 1
		rerolls_left += 1
		ev.append({"t": "levelup", "level": level, "rerolls": rerolls_left})


## Draft context for Draft.roll_hand (what the run can use right now).
func _draft_ctx(guarantee: String) -> Dictionary:
	var owned: Dictionary = {}
	var free: bool = false
	var free_outer: bool = false
	for i in N:
		var id: String = id_at(i)
		if id != "":
			owned[id] = lvl_at(i)
		elif is_free(i):
			free = true
			if ring_of(i) >= 2:
				free_outer = true
	var sp: Dictionary = {}
	for s in specials:
		sp[String((s as Dictionary)["id"])] = int((s as Dictionary)["copies"])
	var ins_cap: int = 1 + int(mods.get("insight_cap", 0))
	var blocked: Array = []
	for id in PickDB.INSIGHT:
		if PickDB.insight_capped(save, String(id)) or insight_found.has(id):
			blocked.append(id)
	return {
		"owned": owned, "free": free and not at_cap(), "free_outer": free_outer and not at_cap(), "huts": hut_count(),
		"hut_max": PickDB.HUT_MAX + int(pf("hut_max")),
		"packs": packs, "specials": sp, "banished": banished, "luck": luck,
		"eco_mult": 1.5 if String(core_def.get("trait", "")) == "compound" else 1.0,
		"choices": 3 + mini(1, _reforge_node("wide_draft")),
		"insight_p": TuneRef.num("pc_insight_p", 0.01) * (1.0 + float(luck) * 0.05),
		"insight_ok": insight_found.size() < ins_cap, "insight_blocked": blocked,
		"guarantee": guarantee, "weapons": _weapon_buildings(),
	}


func _weapon_buildings() -> int:
	var n: int = 0
	for i in N:
		if Draft.WEAPONS.has(id_at(i)):
			n += 1
	return n


func _check_draft(ev: Array) -> void:
	if _busy() or draft_queue.is_empty():
		return
	draft_guarantee = String(draft_queue.pop_front())
	draft = Draft.roll_hand(draft_rng, _draft_ctx(draft_guarantee))
	free_reroll = true
	paid_rerolls = 0
	if draft.is_empty():
		return
	ev.append({"t": "draft_offer", "cards": draft.duplicate(true), "wave": wave, "guarantee": draft_guarantee})
	for c in draft:
		if String((c as Dictionary)["kind"]) == "insight":
			ev.append({"t": "insight_offer", "id": String((c as Dictionary)["id"])})


## Test / tool hook: queue a draft now (opens on the next queue check).
func grant_draft(guarantee: String = "") -> Array:
	draft_queue.append(guarantee)
	var ev: Array = []
	_check_queue(ev)
	return ev


## Perk offers queue behind the draft (B7).
func _check_perk(ev: Array) -> void:
	if modifiers.has("noperks"):
		perk_pending = 0
	if perk_pending <= 0 or _busy():
		return
	perk_pending -= 1
	perk_offer = Perks.offer(draft_rng, perks_taken)
	# Luck Chip: -1 choice on perk waves (never below 1).
	var pc: int = int(pf("perk_choices"))
	if pc < 0 and perk_offer.size() > 1:
		perk_offer = perk_offer.slice(0, maxi(1, perk_offer.size() + pc))
	if perk_offer.is_empty():
		perk_pending = 0
		return
	ev.append({"t": "perk_offer", "ids": perk_offer.duplicate(), "wave": wave})


# ---------------------------------------------------------------- actions
## Take draft card idx. `arg`: for a special when all 4 slots are full, the
## slot it replaces (default: the slot with the fewest copies).
func choose_card(idx: int, arg: int = -1) -> Array:
	var ev: Array = []
	if idx < 0 or idx >= draft.size():
		return ev
	var card: Dictionary = draft[idx]
	draft.clear()
	var id: String = card["id"]
	var kind: String = String(card["kind"])
	picks_taken.append(id)
	match kind:
		"new":
			pending_place = id
			ev.append({"t": "place_mode", "id": id})
			ev.append({"t": "pick_applied", "id": id, "fam": String(card["fam"]), "kind": kind, "rarity": String(card["rarity"])})
			return ev
		"plus":
			var si: int = slot_of_id(id)
			if si >= 0:
				var s: Dictionary = slots[si]
				s["run"] = mini(lvl_cap(), int(s["run"]) + 1)
				recompute()
				ev.append({"t": "building_level", "slot": si, "id": id, "level": lvl_at(si)})
				ev.append({"t": "upgraded", "slot": si, "level": lvl_at(si)})
		"pack":
			packs[id] = pack_n(id) + 1
			recompute()
			if id == "pk_fort":
				hp = minf(float(stats["max_hp"]), hp)
		"special":
			var r: int = arg
			if specials.size() >= PickDB.SPECIAL_SLOTS and Specials.find(specials, id) < 0 and r < 0:
				r = 0
				for k in specials.size():
					if int((specials[k] as Dictionary)["copies"]) < int((specials[r] as Dictionary)["copies"]):
						r = k
			var res: Dictionary = Specials.take(specials, id, r)
			ev.append({"t": "special_slot", "slot": int(res["slot"]), "id": id, "copies": int(res["copies"]), "replaced": String(res["replaced"])})
		"insight":
			insight_found.append(id)
			ev.append({"t": "insight_found", "id": id, "name": String(PickDB.get_def(id).get("name", id))})
	ev.append({"t": "pick_applied", "id": id, "fam": String(card["fam"]), "kind": kind, "rarity": String(card["rarity"])})
	_drain_troop_events(ev)
	_check_queue(ev)
	return ev


## Cash cost of the next paid reroll in this draft: 10 doubling, x1.10^(w-1).
func reroll_cost() -> int:
	if free_reroll or rerolls_left > 0:
		return 0
	return int(round(TuneRef.num("pc_reroll_base", 10.0) * pow(2.0, float(paid_rerolls)) * pow(TuneRef.num("pc_kill_growth", 1.10), float(wave - 1))))


## Reroll the open draft: the free one first, then banked rerolls, then cash.
func reroll_draft() -> Array:
	var ev: Array = []
	if draft.is_empty():
		return ev
	var cost: int = reroll_cost()
	if cost > 0 and cash < float(cost):
		return ev
	if free_reroll:
		free_reroll = false
	elif rerolls_left > 0:
		rerolls_left -= 1
	else:
		cash -= float(cost)
		paid_rerolls += 1
	draft = Draft.roll_hand(draft_rng, _draft_ctx(draft_guarantee))
	ev.append({"t": "draft_reroll", "cards": draft.duplicate(true), "left": rerolls_left, "cost": cost, "next_cost": reroll_cost()})
	return ev


## Banish draft card idx: its id leaves the run pool; the slot is re-rolled.
func banish(idx: int) -> Array:
	if idx < 0 or idx >= draft.size() or banish_left <= 0:
		return []
	var id: String = String((draft[idx] as Dictionary)["id"])
	if PickDB.fam_of(id) == "insight":
		return []
	banish_left -= 1
	banished.append(id)
	var rep: Dictionary = Draft.replace_card(draft_rng, _draft_ctx(""), draft, idx)
	if rep.is_empty():
		draft.remove_at(idx)
	else:
		draft[idx] = rep
	return [{"t": "draft_banish", "id": id, "left": banish_left, "cards": draft.duplicate(true)}]


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
	_drain_troop_events(ev)
	_check_queue(ev)
	return ev


## Drop a pending placement (no legal cell / player cancels with Esc).
func cancel_place() -> Array:
	if pending_place == "":
		return []
	var id: String = pending_place
	pending_place = ""
	var ev: Array = [{"t": "place_cancelled", "id": id}]
	_check_queue(ev)
	return ev


## Buy one level of a Core cash track (REDESIGN §2.2); opens rings 2/3 at
## track totals 10/30.
func buy_track(t: String) -> Array:
	var ev: Array = []
	if over or not TRACKS.has(t):
		return ev
	var c: int = track_cost(t)
	if c < 0 or cash < float(c):
		return ev
	cash -= float(c)
	tracks[t] = int(tracks[t]) + 1
	core_run_lvl = int(tracks["dmg"])
	recompute()
	ev.append({"t": "track", "track": t, "level": int(tracks[t]), "cost": c})
	ev.append({"t": "upgraded", "slot": CORE_SLOT, "level": int(tracks[t]), "track": t})
	_open_rings(ev)
	return ev


## Track total that opens ring r; Bastion Heart (ring_delay) opens each ring
## one step later (ring 2 at ring 3's threshold, ring 3 at 60).
func ring_threshold(r: int) -> int:
	var steps: Array = [int(RING_OPEN[2]), int(RING_OPEN[3]), 60, 100]
	return int(steps[clampi(r - 2 + int(pf("ring_delay")), 0, steps.size() - 1)])


func _open_rings(ev: Array) -> void:
	var tot: int = track_total()
	for r in [2, 3]:
		var ring: int = r
		if rings_open >= ring or tot < ring_threshold(ring):
			continue
		rings_open = ring
		var cells: Array = []
		for i in N:
			if ring_of(i) == ring:
				unlocked[i] = true
				cells.append(i)
		ev.append({"t": "ring_open", "ring": ring, "cells": cells})


## Legacy view hook: the Core cell buys the Damage track; buildings level only
## through duplicate draft picks now.
func upgrade(i: int) -> Array:
	if i == CORE_SLOT:
		return buy_track("dmg")
	return []


## Rings open through Core track totals now (no per-cell cash unlocks).
func unlock_plot(_i: int) -> Array:
	return []


func free_slots() -> Array:
	var out: Array = []
	for i in N:
		if is_free(i):
			out.append(i)
	return out


## Cast special slot k (hotkeys 1-4). `cell`: Orbital target — a grid cell
## index, a world Vector2, or -1 to auto-target the densest enemy cluster.
## Returns {result: ok|cooldown|no_target|empty, ev: [...]}.
func cast_special(k: int, cell: Variant = -1) -> Dictionary:
	if over or k < 0 or k >= specials.size():
		return {"result": "empty", "ev": []}
	var banked: bool = false
	if not Specials.ready(specials, k):
		# Battery Bank: a stored extra charge casts during the cooldown.
		if int((specials[k] as Dictionary).get("bank", 0)) <= 0:
			return {"result": "cooldown", "ev": []}
		banked = true
	var id: String = String((specials[k] as Dictionary)["id"])
	var fx: Dictionary = Specials.FX.get(id, {})
	var ev: Array = []
	var live: int = 0
	for e in enemies:
		if float((e as Dictionary)["hp"]) > 0.0:
			live += 1
	var spec_mult: float = float(mods.get("special_dmg", 1.0))
	var cast: Dictionary = {"t": "special_cast", "slot": k, "id": id}
	match id:
		"sp_orbital":
			var pos: Vector2 = Vector2.INF
			if cell is Vector2:
				pos = cell
			elif (cell is int or cell is float) and int(cell) >= 0 and int(cell) < N:
				pos = slot_pos(int(cell))
			else:
				pos = _densest(float(fx["radius"]) * cpx())
			if pos == Vector2.INF or live == 0:
				return {"result": "no_target", "ev": []}
			var core_w: Dictionary = (stats["weapons"] as Array).back()
			orbitals.append({"pos": pos, "t": float(fx["delay"]), "dmg": float(fx["mult"]) * float(core_w["dmg"]) * spec_mult, "r": float(fx["radius"]) * cpx()})
			cast["pos"] = pos
			cast["r"] = float(fx["radius"]) * cpx()
		"sp_emp":
			if live == 0:
				return {"result": "no_target", "ev": []}
			for e in enemies:
				var ed: Dictionary = e
				ed["slow_t"] = maxf(float(ed["slow_t"]), float(fx["dur"]))
				ed["slow_m"] = minf(float(ed.get("slow_m", 1.0)), 1.0 - float(fx["slow"]))
				ed["shield"] = 0
		"sp_timewarp":
			if live == 0:
				return {"result": "no_target", "ev": []}
			buffs["warp_t"] = float(fx["dur"])
		"sp_repair":
			buffs["repair_t"] = float(fx["dur"])
			buffs["repair_rate"] = float(fx["heal"]) * float(stats["max_hp"]) / float(fx["dur"])
		"sp_overdrive":
			buffs["overdrive_t"] = float(fx["dur"])
		"sp_magnet":
			buffs["magnet_t"] = float(fx["dur"])
	if banked:
		(specials[k] as Dictionary)["bank"] = int((specials[k] as Dictionary)["bank"]) - 1
	else:
		Specials.consume(specials, k, float(mods.get("special_cd", 1.0)))
	# Golden Ratio: every cast costs a share of banked cash.
	if pf("special_tax") > 0.0:
		var tax: float = cash * pf("special_tax")
		cash -= tax
		cast["tax"] = tax
	special_casts += 1
	ev.append(cast)
	return {"result": "ok", "ev": ev}


## Centre of the enemy with the most neighbours within r (ties: the focused
## lane, then the closest to the Core) — deterministic Orbital auto-aim.
func _densest(r: float) -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_n: int = -1
	var best_d: float = INF
	for e in enemies:
		var ed: Dictionary = e
		if float(ed["hp"]) <= 0.0:
			continue
		var p: Vector2 = ed["pos"]
		var n: int = 0
		for x in enemies:
			if float((x as Dictionary)["hp"]) > 0.0 and p.distance_to((x as Dictionary)["pos"]) <= r:
				n += 1
		if int(ed.get("quad", -1)) == focus_quad:
			n += 1
		var d: float = CENTER.distance_squared_to(p)
		if n > best_n or (n == best_n and d < best_d):
			best_n = n
			best_d = d
			best = p
	return best


## Theoretical damage per second of the whole board (stats screen "highest DPS").
func dps() -> float:
	var t: float = 0.0
	for w in stats.get("weapons", []):
		var wd: Dictionary = w
		t += float(wd["dmg"]) * float(wd["rate"])
	return t


## Everything PowerModel needs (REDESIGN §2.7): Core dmg/rate/hp/regen, the
## building DPS list, troops, specials and global multipliers.
func power_snapshot() -> Dictionary:
	var ws: Array = stats.get("weapons", [])
	var core_w: Dictionary = ws.back() if ws.size() > 0 else {}
	var targets: float = 1.0
	match String(core_w.get("attack", "cannon")):
		"cannon":
			targets = float(core_w.get("barrels", 1)) * 1.2
		"slag":
			targets = 2.0
		"pulse":
			targets = 3.0 * float(core_w.get("rings", 1))
		"beam":
			targets = 1.0 + 0.5 * float(core_w.get("ramp_max", 1.5))
	var blds: Array = []
	for w in ws:
		var wd: Dictionary = w
		if int(wd["slot"]) == CORE_SLOT:
			continue
		var mult: float = 1.0
		match String(wd["kind"]):
			"mortar":
				mult = 2.0
			"tesla":
				mult = 1.0 + 0.7 + 0.49
			"railgun":
				mult = 2.0
			"frost":
				mult = 3.0
			"flak":
				mult = 0.6 * float(wd.get("prey", 2.5))
		blds.append({"id": id_at(int(wd["slot"])), "kind": String(wd["kind"]), "dps": float(wd["dmg"]) * float(wd["rate"]) * mult})
	var sps: Array = []
	for s in specials:
		var sd: Dictionary = s
		var sdps: float = 0.0
		if String(sd["id"]) == "sp_orbital":
			sdps = 25.0 * float(core_w.get("dmg", 0.0)) * 2.0 / maxf(1.0, Specials.cooldown("sp_orbital", int(sd["copies"])))
		sps.append({"id": String(sd["id"]), "dps": sdps})
	var drone_dmg: float = PowerModel.enemy_dmg("drone", wave, tier)
	var arm: float = float(stats.get("armor", 0.0))
	return {
		"wave": wave, "tier": tier, "core": core_id, "core_lvl": core_lvl,
		"core_dmg": float(core_w.get("dmg", 0.0)), "core_rate": float(core_w.get("rate", 0.0)), "core_targets": targets,
		"core_range": float(core_w.get("range", 0.0)),
		"core_hp": float(stats.get("max_hp", 0.0)), "core_regen": float(stats.get("regen", 0.0)),
		"armor": arm, "armor_frac": minf(3.0, arm / maxf(0.001, drone_dmg - minf(arm, drone_dmg * 0.75))) if drone_dmg > 0.0 else 0.0,
		"shield": float(stats.get("shield_max", 0.0)),
		"buildings": blds, "troops": Troops.dps_list(troops), "specials": sps,
		"mult": 1.0, "dmg_all": float(stats.get("dmg_all", 1.0)), "tracks": tracks.duplicate(),
		"cash_ps": float(stats.get("cash_ps", 0.0)), "cash_bonus": float(stats.get("kill_cash", 1.0)) - 1.0,
	}


## Cash a building represents (move cost): its rarity tier x level, in
## current cash units.
func building_value(i: int) -> int:
	if id_at(i) == "":
		return 0
	return int(20.0 * float(lvl_at(i)) * cash_index())


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
