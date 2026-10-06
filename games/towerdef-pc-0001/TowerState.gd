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
## troop huts, super-rare Insight). The run grid size is a Research unlock.
##
## Concurrency contract (owner feedback #1): waves never pause and never slow
## down — drafts, perk offers and placement all happen with the sim live.
## Enemies spawn from every direction (no lanes) and attack any building that
## stands in their way (buildings have HP; a destroyed one is lost for the
## run) before they reach the Core.

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
const EnemyStore := preload("res://EnemyStore.gd")
const EnemyHash := preload("res://EnemyHash.gd")

const CENTER: Vector2 = Vector2(360, 470)
const CELL: float = 26.0
## V2 P3b board (owner brief: "grids feel too large ... not very creative"):
## a 21x21 index space of 26 px cells - half the old 52 px - with a 3x3 Core
## footprint centred on CORE_SLOT (row 10, col 10). The playable run grid is a
## centred GxG window whose size is a Research unlock (GRID_SIZES: 7x7 start
## -> ... -> 21x21, the old 10x10 in pixels). Cell index i = row * SIDE + col.
## Buildings occupy a footprint (1x1, or 2x2 for heavy weapons) anchored at
## its top-left cell: slots[anchor] holds the building, occ[cell] the anchor
## covering a cell (CORE_SLOT on the Core, -1 free). Rings are the Chebyshev
## distance from the Core footprint (1 = touching it); ranges stay in cpx()
## units (78 px), so the reach of every weapon is unchanged in pixels.
const SIDE: int = 21
const N: int = 441
const CORE_SLOT: int = 220
const CORE_HALF: int = 1          # the Core covers CORE_SLOT +/- 1 row/col (3x3)
const GRID_SIZES: Array = [7, 9, 11, 13, 15, 17, 19, 21]
const SPAWN_R: float = 470.0      # legacy reference radius (7x7); see spawn_r()
const STOP_R: float = 44.0        # melee contact distance from the Core centre (3x3 Core)
const MAX_LVL: int = 5           # building / hut level cap (duplicate picks)
const MAX_ENEMIES: int = 220
const SUBSTEP: float = 0.05
var step_acc: float = 0.0   # Phase 3 fixed-substep accumulator (game seconds)
## Phase 4 knockback: per-weapon impulse factor (px/s at a full-HP hit on a
## 16 px body); set by _fire/_core_fire around each weapon's hits.
const KNOCK_W: Dictionary = {"gun": 0.6, "railgun": 1.6, "flak": 0.5, "tesla": 0.3, "mortar": 0.0, "core": 1.0}
var _kb_k: float = 0.0
var _kb_from: Vector2 = Vector2.ZERO
## The 16 cells touching the 3x3 Core footprint (ring 1).
const CORE_RING: Array = [176, 177, 178, 179, 180, 197, 201, 218, 222, 239, 243, 260, 261, 262, 263, 264]
const TARGET_MODES: Array = ["nearest", "first", "strongest", "weakest"]
const HIT_FLASH: float = 0.12   # view reads e["hit_t"] for the white hit flash
const ECO_IDS: Array = ["mine", "oilmill", "bounty", "vault", "refinery"]
const BOSSY: Array = ["boss", "elite"]
## Core cash tracks (REDESIGN_SPEC §2.2). cost(next) = base * growth^lvl.
## Growth tuned up from the spec's 1.16-1.20 (playtest pacing: with kill
## cash x1.10/wave the spec values hit every cap by ~w40); Tune keys
## pc_track_growth_<id> override.
const TRACK_IDS: Array = ["dmg", "rate", "range", "eco", "armor"]
## Owner feedback #1: few, BIG, expensive levels, each with a real drawback
## (no spam-click increments). Per level: "desc" is the gain, "minus" the cost.
const TRACKS: Dictionary = {
	"dmg": {"name": "Damage", "base": 120.0, "growth": 3.0, "cap": 6, "desc": "x1.40 Core + building dmg", "minus": "-12% Core attack rate"},
	"rate": {"name": "Rate", "base": 140.0, "growth": 3.0, "cap": 6, "desc": "+30% Core attack rate", "minus": "-9% Core dmg"},
	"range": {"name": "Range", "base": 180.0, "growth": 3.2, "cap": 5, "desc": "+0.75 Core range", "minus": "-8% Core attack rate"},
	"eco": {"name": "Eco", "base": 100.0, "growth": 2.9, "cap": 6, "desc": "+3 cash/s, interest cap +40", "minus": "-8% Core max HP"},
	"armor": {"name": "Armor", "base": 120.0, "growth": 3.0, "cap": 6, "desc": "+30% HP, +1 regen, +2 armor", "minus": "-9% Core dmg"},
}
## Per-level track multipliers (gain / drawback).
const DIFF_HP: float = 2.5
const DIFF_DMG: float = 1.5
const TRACK_DMG: float = 1.40
const TRACK_DMG_RATE: float = 0.88
const TRACK_RATE: float = 1.30
const TRACK_RATE_DMG: float = 0.91
const TRACK_RANGE: float = 0.75
const TRACK_RANGE_RATE: float = 0.92
const TRACK_ECO_CASH: float = 3.0
const TRACK_ECO_ICAP: float = 40.0
const TRACK_ECO_HP: float = 0.92
const TRACK_ARMOR_HP: float = 0.30
const TRACK_ARMOR_DMG: float = 0.91


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


## Owner feedback #1: "game difficulty needs to be harder" — global enemy
## HP / contact-damage multipliers (Tune pc_enemy_hp / pc_enemy_dmg).
static func difficulty_hp() -> float:
	return TuneRef.num("pc_enemy_hp", DIFF_HP)


static func difficulty_dmg() -> float:
	return TuneRef.num("pc_enemy_dmg", DIFF_DMG)


## Grid side for a Research level (0 -> 7x7 ... 7 -> 21x21).
static func grid_for_level(lv: int) -> int:
	return int(GRID_SIZES[clampi(lv, 0, GRID_SIZES.size() - 1)])


## First row/col of a centred GxG window (the Core is centred on (10,10)).
static func grid_lo(g: int) -> int:
	return SIDE / 2 - (g - 1) / 2


## Is cell i inside a GxG run grid?
static func in_grid_n(i: int, g: int) -> bool:
	if i < 0 or i >= N:
		return false
	var lo: int = grid_lo(g)
	var r: int = i / SIDE
	var c: int = i % SIDE
	return r >= lo and r < lo + g and c >= lo and c < lo + g


var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var drop_rng: RandomNumberGenerator = RandomNumberGenerator.new()   # loot only: never perturbs waves
var draft_rng: RandomNumberGenerator = RandomNumberGenerator.new()  # drafts / perks / mutations
var combat_rng: RandomNumberGenerator = RandomNumberGenerator.new() # crits / wave skip
var horde_rng: RandomNumberGenerator = RandomNumberGenerator.new()  # FB1 per-body horde loot (own stream)
var horde_loot_wave_val: float = 0.0
var horde_loot_total: float = 0.0
const HORDE_LOOT_FUND := 0.35     # FB2: share of each horde body's kill coins moved into the loot pool
# Separate streams keep the wave sequence identical whatever the player picks
# or shoots, so two policies on one seed face the same waves.
var save: Dictionary = {}
var slots: Array = []        # N × ({} | {id, perm, run}); perm is always 0 now
var unlocked: Array = []     # N × bool (rings open this run)
var cooldowns: Array = []    # N × float (core uses CORE_SLOT)
var target_modes: Array = []  # N × String (TARGET_MODES)
var next_eid: int = 1
## HORDE Phase 1: enemies live in a struct-of-arrays store (EnemyStore: slots,
## free list, eid -> slot map, `order` = spawn order) queried through a
## uniform spatial hash (EnemyHash). Rules iterate `en.order`.
var en: EnemyStore = EnemyStore.new()
var eh: EnemyHash = EnemyHash.new(en, CENTER)
var stats: Dictionary = {}

var wave: int = 1
var wave_t: float = 0.0
var spawn_t: float = 0.5        # legacy (mobile timer); PC waves spawn from `plan`
# Waves come from every direction (owner feedback #1: no lanes). Each wave is
# planned when it is telegraphed, so the telegraph total is exactly what spawns.
var plan: Array = []              # [{t, kind, [marked]}] for `plan_wave`, sorted by t
var plan_idx: int = 0
var plan_wave: int = 0
var next_plan: Dictionary = {}    # telegraphed plan for wave+1
var wave_spawned: int = 0         # planned entries actually spawned this wave
var last_wave_spawned: Dictionary = {}  # {wave, n} of the wave that just ended
var wave_started: bool = false    # wave 1 starts after the opening telegraph lead
var grid_n: int = 7               # run grid side (Research unlock)
var occ: PackedInt32Array = PackedInt32Array()   # cell -> anchor covering it (CORE_SLOT on the Core, -1 free)
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
## MASS_HORDE (§D3/§D5): designed mass waves (100s -> 1,000s -> 10,000s of
## designed bodies). Main and the playtest bot set it (the shipping ruleset);
## false keeps the classic single-enemy ruleset the selftest pins.
## Test-harness fidelity knob (playtest campaign jobs only, never shipping):
## > 0 compresses a wave planned above this many bodies to one body per k
## (k = ceil(B / cap)) that carries k x HP / damage / pool share / kill count.
## 0 (default, shipping, every H-gate) = every planned body spawns.
var mass_lod_cap: int = 0
const RUN_GOAL_WAVE: int = 20     # §D7 first-run soft goal (Run complete panel)
## power_snapshot crowd factors for the mass verbs (see power_snapshot).
const MASS_CROWD: Dictionary = {"gun": 3.0, "tesla": 5.0, "mortar": 4.0, "flak": 3.0, "railgun": 3.0, "frost": 1.0, "core": 1.5}
const MASS_CAP: int = 16384       # alive cap (§D3): the spawner holds the queue, never drops
var mass_cap: int = MASS_CAP      # (tests lower it to exercise the hold)
var wave_acct: Dictionary = {}    # wave -> pool accounting (§D5), see _mass_acct
var mass_peak: int = 0            # peak alive bodies this run
var mass_wave_peak: int = 0       # peak alive bodies during the current wave
var mass_spawned: int = 0         # bodies spawned this run (weights)
var mass_leaked: int = 0          # bodies that reached the Core this run (weights)
var mass_kills_wave: Dictionary = {}   # wave -> kills credited while it was the current wave
var mass_wall_slowed: Dictionary = {}  # Wall slot -> {body eid: true} slowed this wave (Wall of Flesh)
const WALL_FLESH: int = 2000
var wall_tick: int = 0
var burning: PackedInt32Array = PackedInt32Array()   # slots on fire (Flamer)
var burn_acc: float = 0.0                             # Flamer burn tick accumulator
var kills_by_weapon: Dictionary = {}                  # MASS_HORDE §D6: source -> kills this run
var _src: String = ""                                 # damage source of the hits being applied
var _blockable: bool = false                          # the current hit is a frontal projectile (Shieldbearer)
var _blocked: bool = false                            # set by _hit when a Shieldbearer absorbed it
var _carry_d: int = 0                                 # overkill-smash recursion depth
var _hn: int = 0                                      # mass hit aggregation (no per-hit events at 10k)
var _hsum: float = 0.0
var _hcrit: int = 0
var _htop: Array = []
var plan_lod: Dictionary = {}          # wave -> harness LOD factor of its plan
var core_run_lvl: int = 0         # mirror of tracks["dmg"] (legacy name the view reads)
var spawn_hold: bool = false      # test/tool hook: suppress wave spawns (bosses included)
var build_cap: int = 48
var count_mult: float = 1.0
var draft: Array = []
var pending_place: String = ""
var pending_upgrade: String = ""  # a "plus" pick waiting to be applied onto a building
var over: bool = false

# Core (REDESIGN §2.1) + cash tracks (§2.2).
var core_id: String = CoreDB.ID
var core_def: Dictionary = {}
var core_lvl: int = 1
var tracks: Dictionary = {}
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
var couriers_caught: int = 0
var ins: Dictionary = {}          # Insight values {in_dmg: 0.01, ...}
var pfx: Dictionary = {}          # summed gear fx (V2 P4: Gear.run_fx; {} until then)
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
	horde_rng.seed = seed_value ^ 0x40AD_1007
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
	# Core (V2: one Core) at its permanent level; gear fx arrive in P4
	# (Gear.run_fx: the equipped Weapon + Modules).
	core_id = CoreDB.ID
	core_def = CoreDB.get_def()
	core_lvl = Cores.level(save)
	pfx = {}
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
	build_cap = TuneRef.int_of("pc_build_cap", 40)
	# Grid size: Research "grid" level (opts.grid overrides for tests/tools);
	# Bastion Heart (ring_delay) shrinks it one step.
	var glv: int = int(mods.get("grid_lvl", 0)) - int(pf("ring_delay"))
	grid_n = grid_for_level(glv)
	if opts.has("grid"):
		grid_n = clampi(int(opts["grid"]), GRID_SIZES[0], SIDE)
	for i in N:
		slots.append({})
		unlocked.append(not is_core_cell(i) and in_grid_n(i, grid_n))
		cooldowns.append(0.0)
		target_modes.append("nearest")
	en.clear()
	next_eid = 1
	draft.clear()
	pending_place = ""
	pending_upgrade = ""
	wave = 1
	wave_t = 0.0
	spawn_t = 0.5
	plan.clear()
	plan_idx = 0
	plan_wave = 0
	next_plan = {}
	wave_spawned = 0
	last_wave_spawned = {}
	wave_started = false
	wave_cash0 = 0.0
	wave_acct = {}
	mass_peak = 0
	mass_wave_peak = 0
	mass_spawned = 0
	mass_leaked = 0
	mass_kills_wave = {}
	mass_wall_slowed = {}
	burning = PackedInt32Array()
	plan_lod = {}
	surge_acc = 0.0
	burn_acc = 0.0
	kills_by_weapon = {}
	_hn = 0
	_hsum = 0.0
	_hcrit = 0
	_htop = []
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
	couriers_caught = 0
	stats = {}
	recompute()
	hp = float(stats["max_hp"])
	shield = float(stats.get("shield_max", 0.0))
	var ev0: Array = [{"t": "run_start", "tier": tier, "speed": speed, "mode": mode, "modifiers": modifiers.duplicate(), "coin_mult": mod_coin * mode_coin, "seed": run_seed, "core": core_id, "core_lvl": core_lvl, "grid": grid_n}]
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
	count_mult = (1.6 if modifiers.has("swarm") else 1.0) * (1.25 if modifiers.has("allsides") else 1.0) * (1.0 + 0.2 * float(n.get("m_horde", 0)))
	enemy_spd_mod = (1.25 if modifiers.has("haste") else 1.0) * (1.0 + 0.1 * float(n.get("m_rush", 0)))
	enemy_dmg_mod = 1.0 + 0.25 * float(n.get("m_fangs", 0))
	elite_shield_add = 2 * int(n.get("m_plating", 0))


## SPEC B1: fold the meta bundle into run multipliers. TowerState never reads
## labs or cards directly.
func _apply_mods(m: Dictionary) -> void:
	mods = m
	tier = int(m.get("tier", 1))
	hp_mult = float(m.get("hp_mult", 1.0))
	tier_coin_mult = float(m.get("coin_mult", 1.0))
	coin_mult = tier_coin_mult * (1.0 + float(m.get("lab_coin", 0.0))) * (1.0 + float(m.get("rf_coin", 0.0)))
	# Reforge tree (might / bulwark_p / prosperity) multiply the meta bundle.
	dmg_mult = (1.0 + float(m.get("lab_dmg", 0.0))) * (1.0 + float(m.get("rf_dmg", 0.0)))
	max_hp_mult = (1.0 + float(m.get("lab_hp", 0.0))) * (1.0 + float(m.get("rf_hp", 0.0)))
	cash_mult = 1.0 + float(m.get("cash", 0.0))
	xp_mod = 1.0 + float(m.get("lab_xp", 0.0))
	boss_every = maxi(1, int(m.get("boss_every", 10)))
	allow_new_bldg = true
	speed = maxf(0.1, float(m.get("speed", 1.0)))
	rerolls_left = int(m.get("rerolls", 0))
	wind_hp = float(m.get("wind_hp", 0.0))
	skip_chance = float(m.get("skip_chance", 0.0))


# ---------------------------------------------------------------- geometry
## Centre of cell i in world px.
static func slot_pos(i: int) -> Vector2:
	return CENTER + Vector2(float(i % SIDE - SIDE / 2) * CELL, float(i / SIDE - SIDE / 2) * CELL)


## Is cell i under the 3x3 Core?
static func is_core_cell(i: int) -> bool:
	return i >= 0 and i < N and absi(i / SIDE - SIDE / 2) <= CORE_HALF and absi(i % SIDE - SIDE / 2) <= CORE_HALF


## Ring of cell i: Chebyshev distance from the Core footprint (1 = touching
## it; 0 = under it).
static func ring_of(i: int) -> int:
	return maxi(0, maxi(absi(i / SIDE - SIDE / 2), absi(i % SIDE - SIDE / 2)) - CORE_HALF)


## Footprint side of a building id (1x1 default; heavy weapons 2x2).
static func size_of(id: String) -> int:
	return PickDB.size_of(id)


## Cells covered by a size x size footprint anchored (top-left) at cell i;
## empty when it would leave the board.
static func footprint(i: int, size: int) -> Array:
	var out: Array = []
	if i < 0 or i >= N:
		return out
	var r0: int = i / SIDE
	var c0: int = i % SIDE
	if r0 + size > SIDE or c0 + size > SIDE:
		return out
	for dr in size:
		for dc in size:
			out.append((r0 + dr) * SIDE + c0 + dc)
	return out


## Centre of a size x size footprint anchored at cell i (world px).
static func fp_center(i: int, size: int) -> Vector2:
	return slot_pos(i) + Vector2(CELL, CELL) * (0.5 * float(size - 1))


## Anchor (top-left cell) of a size x size footprint centred as close as
## possible to world point `pos` (placement under the cursor); -1 off-board.
static func anchor_at(pos: Vector2, size: int) -> int:
	var hs: float = float(SIDE) * 0.5 * CELL
	var rel: Vector2 = pos - CENTER + Vector2(hs, hs) - Vector2(CELL, CELL) * (0.5 * float(size - 1))
	var x: int = int(floor(rel.x / CELL))
	var y: int = int(floor(rel.y / CELL))
	if x < 0 or y < 0 or x + size > SIDE or y + size > SIDE:
		return -1
	return y * SIDE + x


## Cell (dr, dc) rows/cols from the Core's centre cell (tests, bots and tools
## place relative to the Core with this; +-2 touches the 3x3 Core).
static func cell(dr: int, dc: int) -> int:
	return (SIDE / 2 + dr) * SIDE + SIDE / 2 + dc


func in_grid(i: int) -> bool:
	return in_grid_n(i, grid_n)


## Rebuild the cell -> anchor map from slots (recompute / place call it).
func _rebuild_occ() -> void:
	occ.resize(N)
	occ.fill(-1)
	for i in N:
		if is_core_cell(i):
			occ[i] = CORE_SLOT
	for i in N:
		var sd: Dictionary = slots[i] if i < slots.size() else {}
		if sd.is_empty():
			continue
		for c in footprint(i, size_of(String(sd["id"]))):
			occ[int(c)] = i


## Anchor of the building covering cell i (CORE_SLOT on the Core), or -1.
func owner_at(i: int) -> int:
	if i < 0 or i >= N:
		return -1
	if occ.size() != N:
		_rebuild_occ()
	return occ[i]


## Footprint side of the building anchored at i (1 when empty).
func size_at(i: int) -> int:
	if i == CORE_SLOT:
		return 2 * CORE_HALF + 1
	var id: String = id_at(i)
	return 1 if id == "" else size_of(id)


## World centre of the building anchored at i (the Core: CENTER).
func fp_pos(i: int) -> Vector2:
	if i == CORE_SLOT:
		return CENTER
	return fp_center(i, size_at(i))


## Ring of the building anchored at i (its footprint cell nearest the Core).
func ring_at(i: int) -> int:
	var best: int = 99
	for c in footprint(i, size_at(i)):
		best = mini(best, ring_of(int(c)))
	return best if best < 99 else ring_of(i)


## Half-extent of the run grid in world px (the view fits the field to it).
func grid_half_px() -> float:
	return float(grid_n) * 0.5 * CELL


## Spawn radius: the grid edge plus a fixed approach (shorter on small grids,
## so the view can zoom in and keep the same travel time).
func spawn_r() -> float:
	var gap: float = TuneRef.num("pc_spawn_gap", 260.0)
	if crowd():
		gap *= TuneRef.num("pc_horde_map", 1.8)   # FB2: bigger battlefield for the x4 horde
	return grid_half_px() * 1.42 + gap


## Radius the view frames (FB2): the pre-horde spawn ring, so enlarging the
## horde battlefield never shrinks the base grid on screen.
func view_r() -> float:
	return grid_half_px() * 1.42 + TuneRef.num("pc_spawn_gap", 260.0)


## Crowd ruleset (mass waves, or the legacy split knob): big battlefield,
## event aggregation, omnidirectional barricades / riflemen.
func crowd() -> bool:
	return true


## Railgun needs ring 3+ (>= 2 old 52 px cells out); everything else goes
## anywhere on the grid.
static func ring_ok(i: int, id: String) -> bool:
	if id != "railgun":
		return true
	var fp: Array = footprint(i, size_of(id))
	for c in fp:
		if ring_of(int(c)) < 3:
			return false
	return not fp.is_empty()


## The 8 cells around cell i (cell level; buildings use adjacent()).
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


## Chebyshev gap between two footprints (1 = touching, 0 = overlapping).
func fp_dist(a: int, b: int) -> int:
	var best: int = 999
	var fa: Array = footprint(a, size_at(a)) if a != CORE_SLOT else _core_cells()
	var fb: Array = footprint(b, size_at(b)) if b != CORE_SLOT else _core_cells()
	for x in fa:
		for y in fb:
			best = mini(best, cell_dist(int(x), int(y)))
	return best


static func _core_cells() -> Array:
	return footprint(CORE_SLOT - CORE_HALF * SIDE - CORE_HALF, 2 * CORE_HALF + 1)


## Anchors of the buildings (and CORE_SLOT for the Core) touching the
## footprint of the building anchored at i.
func adjacent(i: int) -> Array:
	var out: Array = []
	var fa: Array = footprint(i, size_at(i)) if i != CORE_SLOT else _core_cells()
	for c in fa:
		for n in neighbors(int(c)):
			var o: int = owner_at(int(n))
			if o >= 0 and o != i and not out.has(o):
				out.append(o)
	return out


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


## Is cell i open ground on the run grid (unlocked, not the Core, not covered)?
func is_free(i: int) -> bool:
	return i >= 0 and i < N and bool(unlocked[i]) and owner_at(i) < 0


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


## Can `id` go with its footprint anchored at cell i right now (every
## covered cell free, under the build cap, ring rule)?
func can_place(i: int, id: String) -> bool:
	if at_cap() or not ring_ok(i, id):
		return false
	var fp: Array = footprint(i, size_of(id))
	if fp.is_empty():
		return false
	for c in fp:
		if not is_free(int(c)):
			return false
	return true


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
	var e: float = cash_index()
	var px: float = cpx()
	var nb: int = 0
	for i in N:
		if i != CORE_SLOT and id_at(i) != "":
			nb += 1
	var st: Dictionary = {
		"max_hp": float(cd["hp"]) * CoreDB.lvl_mult("hp", L),
		"regen": float(cd["regen"]) * CoreDB.lvl_mult("regen", L),
		"armor": float(cd["armor"]),
		"cash_ps": float(cd["cash"]) * CoreDB.lvl_mult("cash", L),
		"xp_mult": 1.0,
		"kill_cash": 1.0,
		"weapons": [],
		"links": [],
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
	# Global multipliers: meta (research / Reforge) x packs x Insight x Damage track.
	var dmg_track: float = pow(TuneRef.num("pc_track_dmg_step", TRACK_DMG), float(tracks["dmg"]))
	var dmg_all: float = dmg_mult * dmg_track * (1.0 + 0.12 * float(pack_n("pk_arsenal"))) * (1.0 + 0.40 * float(pack_n("pk_gambit"))) * (1.0 + float(ins.get("in_dmg", 0.0)))
	# Gear: all-damage (+ per building, max 12 buildings).
	dmg_all *= maxf(0.1, 1.0 + pf("dmg") + pf("dmg_per_bld") * float(mini(12, nb)))
	# Mint 4-piece Dividend: the Eco track pays out as damage (full at Eco 50).
	dmg_all *= 1.0 + pf("dividend") * float(mini(track_cap("eco"), int(tracks["eco"]))) / float(maxi(1, track_cap("eco")))
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
				for n in adjacent(i):
					adj_dmg[n] = float(adj_dmg[n]) + 0.15 * m
					links.append([i, n, "ARM"])
			"beacon":
				# V2 P3b: radius 4 small cells (the old 2 x 52 px)
				for n in N:
					if n != i and (id_at(n) != "" or n == CORE_SLOT) and fp_dist(i, n) <= 4:
						adj_rate[n] = float(adj_rate[n]) + 0.10 * m
						adj_range[n] = float(adj_range[n]) + 0.3 * m
						links.append([i, n, "BEA"])
			"oilmill":
				for n in adjacent(i):
					if n != CORE_SLOT:
						adj_rate[n] = float(adj_rate[n]) - 0.10
						links.append([i, n, "OIL"])
	# Core attack range (cells).
	var core_range_c: float = maxf(1.0, float(cd["range"]) + TRACK_RANGE * float(tracks["range"]) + range_add + float(adj_range[CORE_SLOT]) + pf("range"))
	var core_range: float = core_range_c * px
	var weapons: Array = st["weapons"]
	var rr: float = TuneRef.num("pc_ring_range", 0.08)
	var hp_add: float = 0.0
	var cash_add: float = 0.0
	for i in N:
		var id: String = id_at(i)
		if id == "":
			continue
		var m2: float = pow(1.35, float(lvl_at(i) - 1))
		# +pc_ring_range per old 52 px ring past the first (2 small rings each)
		var ring_m: float = 1.0 + rr * 0.5 * float(maxi(0, ring_at(i) - 1))
		var rate_m: float = rate_all * float(adj_rate[i]) * maxf(0.1, 1.0 + pf("bld_rate"))
		var dm: float = dmg_all * float(adj_dmg[i]) * bld_dmg() * maxf(0.1, 1.0 + pf("bld_dmg"))
		var rng_c: float = float(adj_range[i]) + range_add
		match id:
			"gun":
				weapons.append({"slot": i, "lvl": lvl_at(i), "kind": "gun", "dmg": 6.0 * m2 * dm, "rate": 2.0 * rate_m, "range": (3.0 + rng_c) * px * ring_m})
			"mortar":
				weapons.append({"slot": i, "lvl": lvl_at(i), "kind": "mortar", "dmg": 18.0 * m2 * dm, "rate": 0.4 * rate_m, "range": (4.5 + rng_c) * px * ring_m, "splash": 1.0 * px, "min_range": 1.5 * px})
			"tesla":
				weapons.append({"slot": i, "lvl": lvl_at(i), "kind": "tesla", "dmg": 9.0 * m2 * dm * (1.0 + pf("chain_dmg")), "rate": 0.8 * rate_m, "range": (3.0 + rng_c) * px * ring_m, "chains": 3 + int(pf("chain")), "chain_frac": 0.7})
			"flak":
				weapons.append({"slot": i, "lvl": lvl_at(i), "kind": "flak", "dmg": 8.0 * m2 * dm, "rate": 1.5 * rate_m * TuneRef.num("mass_flame_rate", 0.5), "range": (3.5 + rng_c) * px * ring_m})
			"railgun":
				weapons.append({"slot": i, "lvl": lvl_at(i), "kind": "railgun", "dmg": 60.0 * m2 * dm, "rate": 0.25 * rate_m, "range": (7.0 + rng_c) * px * ring_m, "pierce": 14.0})
			"frost":
				weapons.append({"slot": i, "lvl": lvl_at(i), "kind": "frost", "dmg": 1.5 * m2 * dm, "rate": 2.0, "range": (2.5 + rng_c) * px, "slow": 0.30, "slow_t": 0.6})
			"bulwark":
				hp_add += 40.0 * m2
				links.append([i, CORE_SLOT, "BUL"])
			"aegis":
				st["shield_max"] = float(st["shield_max"]) + 60.0 * m2
				st["shield_regen"] = float(st["shield_regen"]) + 6.0 * m2
			"barricade":
				pass   # the Wall: a cheap blocker with a slow aura (_wall_auras)
			"mine":
				cash_add += 0.8 * m2
			"oilmill":
				cash_add += 2.0 * m2
			"refinery":
				cash_add += 0.5 * m2
				st["xp_mult"] = float(st["xp_mult"]) + 0.15 * m2
			"bounty":
				(st["bounties"] as Array).append({"slot": i, "pos": fp_pos(i), "r": 3.0 * px, "mult": 0.20 * m2})
			"vault":
				st["interest_rate"] = float(st["interest_rate"]) + 0.02 * m2
				st["interest_cap"] = float(st["interest_cap"]) + 100.0 * m2
			"obelisk":
				st["lifesteal"] = float(st["lifesteal"]) + 0.01 * m2
			"hut_infantry", "hut_sapper":
				var dir: Vector2 = (fp_pos(i) - CENTER).normalized()
				var post: Vector2 = CENTER + dir * (grid_half_px() + 0.6 * px)
				var hut: Dictionary = {"slot": i, "id": id, "lvl": lvl_at(i), "home": fp_pos(i), "anchor": post}
				if id == "hut_infantry" and crowd():
					# FB2 Rifle Barracks (omnidirectional): riflemen guard the whole
					# perimeter - seek/leash around the Core, idle at their post.
					var gh: float = grid_half_px() / px
					hut["anchor"] = CENTER
					hut["post"] = post
					hut["seek"] = gh + TuneRef.num("pc_rifle_seek", 3.0)
					hut["leash"] = gh + TuneRef.num("pc_rifle_leash", 4.5)
				(st["huts"] as Array).append(hut)
	# Core sheet with tracks, packs, legacy core levels, Insight.
	var arm_n: int = tracks["armor"]
	st["max_hp"] = (float(st["max_hp"]) + hp_add) * (1.0 + TRACK_ARMOR_HP * float(arm_n)) * pow(TRACK_ECO_HP, float(tracks["eco"])) * (1.0 + 0.20 * float(pack_n("pk_fort"))) * maxf(0.5, 1.0 - 0.05 * float(pack_n("pk_overclock"))) * max_hp_mult * (1.0 + float(ins.get("in_hp", 0.0))) * maxf(0.1, 1.0 + pf("core_hp"))
	st["regen"] = (float(st["regen"]) + 1.0 * float(arm_n)) * maxf(0.0, 1.0 + pf("regen"))
	st["armor"] = float(st["armor"]) + 2.0 * float(arm_n) + float(pack_n("pk_fort")) + pf("armor")
	var eco_lv: int = tracks["eco"]
	var cash_w1: float = maxf(0.0, float(st["cash_ps"]) + TRACK_ECO_CASH * float(eco_lv) + 0.6 * float(pack_n("pk_ledger")) + cash_add + pf("cash_flat"))
	st["cash_ps"] = cash_w1 * e * cash_mult * (1.0 + float(ins.get("in_cash", 0.0))) * maxf(0.1, 1.0 + pf("cash"))
	st["kill_cash"] = (1.0 + 0.05 * float(pack_n("pk_ledger"))) * (1.0 + float(ins.get("in_cash", 0.0))) * maxf(0.1, 1.0 + pf("kill_cash"))
	st["interest_rate"] = float(st["interest_rate"]) + pf("interest")
	var icap_w1: float = float(st["interest_cap"]) + TRACK_ECO_ICAP * float(eco_lv) + (50.0 if pf("interest") > 0.0 else 0.0)
	st["interest_cap"] = icap_w1 * e
	# The Core's own weapon (always last in `weapons`; the view reads .back()).
	var core_dmg: float = float(cd["dmg"]) * CoreDB.lvl_mult("dmg", L) * dmg_all * float(adj_dmg[CORE_SLOT]) * (1.0 + TuneRef.num("pc_core_surge_dmg", 0.15) * float(pack_n("pk_core"))) * maxf(0.1, 1.0 + pf("core_dmg")) * pow(TRACK_RATE_DMG, float(tracks["rate"])) * pow(TRACK_ARMOR_DMG, float(arm_n))
	var core_rate: float = float(cd["rate"]) * pow(TRACK_RATE, float(tracks["rate"])) * pow(TRACK_DMG_RATE, float(tracks["dmg"])) * pow(TRACK_RANGE_RATE, float(tracks["range"])) * rate_all * float(adj_rate[CORE_SLOT]) * (1.0 + TuneRef.num("pc_core_surge_rate", 0.05) * float(pack_n("pk_core"))) * maxf(0.1, 1.0 + pf("rate"))
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
			cw["boss_mult"] = 1.0
			cw["retarget"] = maxf(0.0, pf("retarget"))
		"pulse":
			cw["rings"] = (2 if L >= 20 else 1) + int(pf("chain"))
			cw["knock"] = float(cd["knock"])
			cw["chain_every"] = int(cd["chain_every"])
			cw["chain_frac"] = float(cd.get("chain_frac", 0.4)) * (1.0 + pf("chain_dmg"))
			cw["chain_n"] = int(cd["chain_n"])
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
	st["overcharge_step"] = TuneRef.num("pc_track_dmg_step", TRACK_DMG) - 1.0
	st["overcharge"] = dmg_track
	st["bounty_mult"] = float(st["kill_cash"])
	return st


func recompute() -> void:
	_rebuild_occ()
	var old_max: float = float(stats.get("max_hp", 0.0))
	stats = compute_stats()
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
		"cell_px": cpx(),
	}


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


## Owner feedback #1: the sim stays live (no slow-mo) during drafts/placement.
func time_scale() -> float:
	return 1.0


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
	# HORDE Phase 3 (C8, owner: "Phase 3"): truly fixed-length substeps. Game
	# time accumulates; every whole SUBSTEP runs one _step(SUBSTEP). A frame
	# shorter than a substep may run none (the remainder carries over).
	step_acc += maxf(0.0, delta) * speed
	while step_acc >= SUBSTEP - 0.000001:
		step_acc -= SUBSTEP
		if over:
			break
		var at: int = ev.size()
		_step(SUBSTEP, ev)
		_flush_hits(ev)
		aggregate_events(ev, at)
	return ev


## HORDE Phase 2 event aggregation (every substep since V2 P3d: the mass
## horde is the only ruleset). Collapses this substep's per-body "kill", per-hit
## "dmg" and Core contact "core_hit"/"enemy_shot" events (from index `at`)
## into one summary each, appended at the end, so view / sfx / Missions /
## Stats cost no longer scales with bodies. Boss kills stay single events.
##   {"t":"kills","n","cash","by_kind":{kind:n},"pos_sample":[<=16]}
##   {"t":"hits","n","sum","crit_n","top":[{eid,pos,amt,crit}] (<=8 largest)}
##   {"t":"core_hits","n","dmg","shots","pos_sample":[<=8]}
const AGG_POS: int = 16
const AGG_TOP: int = 8
static func aggregate_events(ev: Array, at: int = 0) -> void:
	var keep: Array = []
	var kn: int = 0
	var kcash: float = 0.0
	var by_kind: Dictionary = {}
	var kpos: Array = []
	var hn: int = 0
	var hsum: float = 0.0
	var hcrit: int = 0
	var top: Array = []
	var cn: int = 0
	var cshots: int = 0
	var cdmg: float = 0.0
	var cpos: Array = []
	for i in range(at, ev.size()):
		var e: Dictionary = ev[i]
		var t: String = String(e.get("t", ""))
		if t == "kill" and String(e.get("kind", "")) != "boss":
			var kw: int = int(e.get("n", 1))   # bodies the kill stands for (1 unless the harness LOD)
			kn += kw
			kcash += float(e.get("cash", 0.0))
			var kk: String = String(e.get("kind", "drone"))
			by_kind[kk] = int(by_kind.get(kk, 0)) + kw
			if kpos.size() < AGG_POS:
				kpos.append(e["pos"])
		elif t == "dmg":
			hn += 1
			var a: float = float(e.get("amt", 0.0))
			hsum += a
			if bool(e.get("crit", false)):
				hcrit += 1
			if top.size() < AGG_TOP:
				top.append(e)
			else:
				var lo: int = 0
				for j in range(1, top.size()):
					if float((top[j] as Dictionary)["amt"]) < float((top[lo] as Dictionary)["amt"]):
						lo = j
				if a > float((top[lo] as Dictionary)["amt"]):
					top[lo] = e
		elif t == "core_hit" or t == "enemy_shot":
			cn += 1
			if t == "enemy_shot":
				cshots += 1
			cdmg += float(e.get("dmg", 0.0))
			if cpos.size() < AGG_TOP:
				cpos.append(e["pos"])
		else:
			keep.append(e)
	if kn == 0 and hn == 0 and cn == 0:
		return
	ev.resize(at)
	ev.append_array(keep)
	if hn > 0:
		ev.append({"t": "hits", "n": hn, "sum": hsum, "crit_n": hcrit, "top": top})
	if kn > 0:
		ev.append({"t": "kills", "n": kn, "cash": kcash, "by_kind": by_kind, "pos_sample": kpos})
	if cn > 0:
		ev.append({"t": "core_hits", "n": cn, "dmg": cdmg, "shots": cshots, "pos_sample": cpos})


## Mass runs: one "hits" summary per substep straight from counters (the
## per-hit "dmg" events would cost more than the sim at 10k bodies).
func _flush_hits(ev: Array) -> void:
	if _hn == 0:
		return
	ev.append({"t": "hits", "n": _hn, "sum": _hsum, "crit_n": _hcrit, "top": _htop})
	_hn = 0
	_hsum = 0.0
	_hcrit = 0
	_htop = []


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
		ev.append({"t": "wave_start", "wave": wave, "boss": wave % boss_every == 0})
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
	_src = ""
	_blockable = false
	_wall_auras(ev)
	_kb_k = 0.0
	_burn_step(dt, ev)
	_warlord_surge(dt)
	_src = "troop"
	_troops_step(dt, ev)
	_src = "frost"
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
		_src = "special"
		_kb_k = 0.0
		_blockable = false
		for s in eh.candidates(c, float(od["r"]) + en.max_size * 0.5):
			if en.hp[s] > 0.0 and en.pos[s].distance_to(c) <= float(od["r"]) + en.size[s] * 0.5:
				_hit(s, float(od["dmg"]), ev)
				n += 1
		_src = ""
		ev.append({"t": "orbital_hit", "pos": c, "r": float(od["r"]), "hits": n})
		# §D4 knockback special: the strike's shock wave parts the sea.
		var pushed: int = en.radial_knock(c, float(od["r"]) * 2.0, TuneRef.num("horde_knock", 60.0) * TuneRef.num("mass_orbital_knock", 3.0))
		if pushed >= 500:
			ev.append({"t": "part_sea", "n": pushed, "pos": c})
	orbitals = keep


## Interest on banked cash (Core + Vaults), paid before the next wave starts.
func _wave_end(ev: Array) -> void:
	last_stand_used = false
	_sweep_horde_loot()
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
	ev.append({"t": "wave_kills", "wave": wave, "n": int(mass_kills_wave.get(wave, 0)), "peak": mass_wave_peak})
	if wave == RUN_GOAL_WAVE and tier == 1 and mode == "normal" and Tiers.best_in(save, 1) < RUN_GOAL_WAVE:
		# §D7: the short first run's soft goal (the second boss). The view
		# offers "keep going" (to the wave-50 tide) or "bank now".
		ev.append({"t": "run_goal", "wave": wave, "kills": kills, "time": time_alive})
	if mass_wave_peak >= 10000:
		ev.append({"t": "tide", "wave": wave, "peak": mass_wave_peak})
	mass_wave_peak = 0
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
	recompute()   # cash/s, building HP and troops scale with the wave
	_drain_troop_events(ev)
	ev.append({"t": "wave", "wave": wave})
	if next_plan.is_empty() or int(next_plan["wave"]) != wave:
		next_plan = _build_plan(wave, 0.0)
		ev.append(_telegraph_event(next_plan))   # late telegraph (skipped wave)
	_adopt_plan(next_plan, ev, false)
	if wave % boss_every == 0:
		for _b in 1 + (tier - 1) / 2:
			_spawn("boss", ev)
	if Drops.courier_roll(drop_rng, wave):
		_spawn_courier(ev)
	# §D3: +1 Courier per 2,000 bodies in the wave.
	for _c in mini(6, mass_bodies(wave) / 2000):
		_spawn_courier(ev)
	mass_wall_slowed = {}


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
	_sweep_horde_loot(true)
	var cashout: int = int(floor(TuneRef.num("cashout_frac", 0.12) * cash_earned / maxf(1.0, cash_index()) * tier_coin_mult * mod_coin * mode_coin))
	var coins: int = int(coins_run) + cashout
	var bd: Dictionary = {
		"wave": int(coins_wave), "kills": int(coins_kill), "boss": int(coins_boss),
		"cashout": cashout, "mult": run_coin_mult(), "tier": tier,
		"mod_mult": mod_coin, "mode_mult": mode_coin,
	}
	var build: Array = []
	for i in N:
		build.append(id_at(i))
	ev.append({"t": "game_over", "wave": wave, "coins": coins, "kills": kills, "cash_earned": int(cash_earned), "breakdown": bd, "perks": perks_taken.duplicate(),
		"seed": run_seed, "tier": tier, "mode": mode, "modifiers": modifiers.duplicate(), "mutations": mutations_taken.duplicate(),
		"duration_s": time_alive, "build": build, "ts": now_unix, "dps": dps(),
		"core": core_id, "core_lvl": core_lvl, "picks": picks_taken.duplicate(), "insight": insight_found.duplicate(),
		"loot": loot.duplicate(true), "specials_cast": special_casts, "tracks": tracks.duplicate(), "couriers": _couriers_caught(),
			"kills_by_weapon": kills_by_weapon.duplicate(), "mass_peak": mass_peak, "mass_spawned": mass_spawned, "mass_leaked": mass_leaked})
	# Endless records its own best and never feeds the tier ladder (§3.1).
	ev.append_array(BaseMeta.bank(save, coins, wave, tier, time_alive / 60.0, now_unix, mode != "endless"))
	if mode == "endless":
		BaseMeta.record_endless(save, wave)
	# Insight (win or loss) + loot are banked permanently.
	ev.append_array(PickDB.bank_insight(save, insight_found))
	ev.append_array(BaseMeta.bank_loot(save, loot, drop_rng))
	ev.append({"t": "dead", "wave": wave, "coins": coins, "kills": kills, "cash_earned": int(cash_earned), "breakdown": bd})


func _couriers_caught() -> int:
	return couriers_caught


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


## Spawn interval for wave w (the mobile curve, then perks / modifiers).
func interval_for(w: int) -> float:
	var pm: float = float(stats.get("perk_spawn", 1.0))
	return maxf(min_spawn, spawn_base * pow(spawn_decay, float(w - 1))) * pm / maxf(0.01, count_mult)


## Seeded plan for wave w: one entry per spawn tick. `lead` delays the first
## spawn (wave 1 opens with the telegraph lead). A marked elite (loot carrier,
## from w8) is chosen on the separate drop RNG. Directions are rolled at spawn
## time, uniformly around the Core.
func _build_plan(w: int, lead: float) -> Dictionary:
	return _build_mass_plan(w, lead)


func _telegraph_event(p: Dictionary) -> Dictionary:
	var tot: int = int(p.get("bodies", (p["entries"] as Array).size()))
	return {"t": "wave_telegraph", "wave": int(p["wave"]), "total": tot, "elites": int(p["elites"]), "boss": bool(p["boss"]), "lead": telegraph_s(), "mix": p.get("mix", {})}


# ---------------------------------------------------------------- MASS_HORDE
## §D3 body count of wave w (before the harness LOD): 120 x 1.11^(w-1) x
## tierB, x modifiers / perks that change enemy counts, capped (Tune mass_b_cap).
func mass_bodies(w: int) -> int:
	var b: float = TuneRef.num("mass_b0", 120.0) * pow(TuneRef.num("mass_b_growth", 1.11), float(maxi(1, w) - 1)) * EnemyDB.tier_b(tier)
	b *= TuneRef.num("mass_body_mult", 1.0) * count_mult / maxf(0.1, float(stats.get("perk_spawn", 1.0)))
	return clampi(int(round(b)), 1, TuneRef.int_of("mass_b_cap", 20000))


## Harness LOD factor for a wave of `b` bodies (1 = every body spawns).
func mass_lod(b: int) -> int:
	if mass_lod_cap <= 0 or b <= mass_lod_cap:
		return 1
	return int(ceil(float(b) / float(mass_lod_cap)))


## §D5 per-wave pools in wave-1 units (kill cash / XP are x cash_index and the
## run multipliers when paid). Shape: the classic per-wave kill income (the
## POWER_MODEL / IDLE_MATH spine, so meta pacing stays valid) x mass_cash_unit;
## a full clear adds mass_clear (30%) on top.
func mass_cash_pool(w: int) -> float:
	return wave_time / interval_for(w) * TuneRef.num("mass_cash_unit", 1.0)


func mass_coin_pool(w: int) -> float:
	return (2.0 + 0.4 * float(w)) * TuneRef.num("mass_coin_unit", 1.2)


## Drops cap per wave (§D5): 6 at T1, +2 per tier.
func mass_drop_cap() -> int:
	return TuneRef.int_of("mass_drop_cap", 6) + 2 * (tier - 1)


func _mass_acct(w: int) -> Dictionary:
	if not wave_acct.has(w):
		wave_acct[w] = {"n": 0, "spawned": 0, "dead": 0, "leak": 0, "pool": 0.0, "W": 1.0, "xpool": 0.0, "cpool": 0.0, "CW": 0.0,
			"cclear": 0.0, "loot": 0.0, "drops": 0, "ks": 1.0, "planned_done": false, "paid": false}
	return wave_acct[w]


## Seeded §D3 plan: B(w) designed bodies in 3-6 surges (dense 60-120 deg arcs
## from one or two sides; Encircled uses every side), mix by wave band, elites
## floor(w/5) from wave 5, a marked loot carrier on the drop RNG. Entries
## carry their own angle / depth so the spawn is a dense arc, not a ring.
func _build_mass_plan(w: int, lead: float) -> Dictionary:
	var B: int = mass_bodies(w)
	var lod: int = mass_lod(B)
	var n: int = int(ceil(float(B) / float(lod)))
	var mix: Dictionary = EnemyDB.mass_mix(w, tier)
	var kinds: Array = []
	var cum: Array = []
	var acc: float = 0.0
	for k in EnemyDB.MASS_ORDER:
		if mix.has(k) and float(mix[k]) > 0.0:
			acc += float(mix[k])
			kinds.append(k)
			cum.append(acc)
	var ns: int = clampi(3 + w / 10, 3, 6)
	var t0: float = lead + 0.5 if lead > 0.0 else 0.5
	var gap: float = maxf(1.0, (wave_time - 1.5 - t0) / float(ns))
	var span: float = minf(TuneRef.num("mass_surge_s", 2.5), gap * 0.8)
	var depth: float = TuneRef.num("mass_spawn_depth", 140.0)
	var entries: Array = []
	var elites: int = 0
	var all_sides: bool = modifiers.has("allsides")
	var cash_w: float = 0.0
	var coin_w: float = 0.0
	var by_kind: Dictionary = {}
	for si in ns:
		var cnt: int = n / ns + (1 if si < n % ns else 0)
		var a0: float = rng.randf() * TAU
		var arc: float = deg_to_rad(60.0 + 60.0 * rng.randf())
		var two: bool = rng.randf() < 0.35
		var ts: float = t0 + gap * float(si)
		for j in cnt:
			var r: float = rng.randf()
			var kind: String = String(kinds[kinds.size() - 1]) if kinds.size() > 0 else "mite"
			for q in kinds.size():
				if r * acc < float(cum[q]):
					kind = String(kinds[q])
					break
			var a: float = a0 + (rng.randf() - 0.5) * arc
			if all_sides:
				a = rng.randf() * TAU
			elif two and (j & 1) == 1:
				a += PI
			var ent: Dictionary = {"t": ts + span * float(j) / float(maxi(1, cnt)), "kind": kind, "a": a, "j": rng.randf() * depth, "w": w}
			entries.append(ent)
			var md: Dictionary = EnemyDB.mass_def(kind)
			cash_w += float(md["cash"]) * float(lod)
			coin_w += float(md["coin"]) * float(lod)
			by_kind[kind] = int(by_kind.get(kind, 0)) + lod
	# Elites (kept units, §D1): floor(w/5) from wave 5 (Elite Guard x3, tiers add).
	var ne: int = 0
	if w >= 5:
		ne = w / 5 + int(round(Tiers.elite_weight(tier) * 10.0))
		if modifiers.has("elitist"):
			ne *= 3
	for k in ne:
		var ta: float = t0 + (wave_time - 2.0 - t0) * float(k + 1) / float(ne + 1)
		entries.append({"t": ta, "kind": "elite", "a": rng.randf() * TAU, "j": 0.0, "w": w})
		elites += 1
		cash_w += float(EnemyDB.mass_def("elite")["cash"])
		coin_w += float(EnemyDB.mass_def("elite")["coin"])
	entries.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["t"]) < float(y["t"]))
	var boss: bool = w % boss_every == 0
	var nboss: int = (1 + (tier - 1) / 2) if boss else 0
	cash_w += float(nboss) * float(EnemyDB.mass_def("boss")["cash"])
	coin_w += float(nboss) * float(EnemyDB.mass_def("boss")["coin"])
	# Marked loot carrier (drop RNG): a heavy or an elite, never a swarmling.
	if entries.size() > 0 and Drops.elite_mark_roll(drop_rng, w):
		var mi: int = drop_rng.randi_range(entries.size() / 4, entries.size() - 1)
		for q in entries.size():
			var x: Dictionary = entries[(mi + q) % entries.size()]
			if ["elite", "hauler", "shield", "splitter"].has(String(x["kind"])):
				x["marked"] = true
				break
	return {"wave": w, "entries": entries, "elites": elites, "boss": boss, "nboss": nboss, "bodies": B + elites, "lod": lod,
		"cash_w": maxf(1.0, cash_w), "coin_w": coin_w, "mix": by_kind}


## Register a wave's pools when its plan is adopted (§D5).
func _mass_open(p: Dictionary) -> void:
	var w: int = int(p["wave"])
	var a: Dictionary = _mass_acct(w)
	plan_lod[w] = int(p.get("lod", 1))
	a["n"] = int(a["n"]) + (p["entries"] as Array).size() * int(p.get("lod", 1)) + int(p.get("nboss", 0))   # in body weights
	a["pool"] = mass_cash_pool(w)
	a["W"] = float(p["cash_w"])
	a["xpool"] = mass_cash_pool(w) * TuneRef.num("mass_xp_unit", 1.25) / maxf(0.01, TuneRef.num("mass_cash_unit", 1.0))
	var cp: float = mass_coin_pool(w) * run_coin_mult()
	var kill_half: float = cp * 0.5 if float(p["coin_w"]) > 0.0 else 0.0
	a["cpool"] = kill_half
	a["CW"] = float(p["coin_w"])
	a["cclear"] = cp - kill_half
	a["drops"] = mass_drop_cap()
	# Key / part odds per body: a classic plan entry's odds spread over the
	# wave's bodies (per-wave drop rates unchanged as the count grows 100x).
	a["ks"] = clampf(wave_time / interval_for(w) / maxf(1.0, float(int(p["bodies"]))), 0.0, 1.0)


## Pay a wave's clear bonus once all of its bodies are dead (§D5): 30% of the
## cash pool and the clear half of its coins, minus the leaked share.
func _mass_try_clear(w: int, ev: Array) -> void:
	var a: Dictionary = wave_acct.get(w, {})
	if a.is_empty() or bool(a["paid"]) or not bool(a["planned_done"]) or int(a["dead"]) < int(a["spawned"]):
		return
	a["paid"] = true
	var kept: float = 1.0 - clampf(float(a["leak"]) / maxf(1.0, float(a["spawned"])), 0.0, 1.0)
	var cg: float = float(a["pool"]) * TuneRef.num("mass_clear", 0.3) * kept * cash_index() * run_cash_mult() * kill_cash_mod
	cash += cg
	cash_earned += cg
	var coins: float = float(a["cclear"]) * kept
	coins_run += coins
	coins_wave += coins
	_mass_sweep_loot(a)
	ev.append({"t": "wave_clear", "wave": w, "cash": cg, "coins": coins, "kept": kept, "kills": int(a["dead"]) - int(a["leak"]), "leaked": int(a["leak"])})
	wave_acct.erase(w)


## Make `p` the current wave's plan. The opening wave telegraphs here (it has
## no previous wave to do it); later waves emit wave_start here.
func _adopt_plan(p: Dictionary, ev: Array, opening: bool) -> void:
	if plan_wave > 0:
		last_wave_spawned = {"wave": plan_wave, "n": wave_spawned}
	# The alive cap held part of the previous wave: it spawns first (never dropped).
	var left: Array = plan.slice(plan_idx) if plan_wave > 0 else []
	for x in left:
		(x as Dictionary)["t"] = 0.0
	if plan_wave > 0 and left.is_empty() and wave_acct.has(plan_wave):
		(wave_acct[plan_wave] as Dictionary)["planned_done"] = true
	_mass_open(p)
	left.append_array(p["entries"])
	p["entries"] = left
	plan = p["entries"]
	plan_idx = 0
	plan_wave = int(p["wave"])
	wave_spawned = 0
	next_plan = {}
	wave_cash0 = cash_earned
	if opening:
		ev.append(_telegraph_event(p))
	else:
		ev.append({"t": "wave_start", "wave": wave, "boss": wave % boss_every == 0})


func _spawn_due(ev: Array) -> void:
	if plan_wave != wave:
		# The wave was entered without a telegraph (tests / tools jump waves).
		_adopt_plan(_build_plan(wave, 0.0), ev, true)
	if spawn_hold:
		return
	_spawn_mass_due(ev)


## Mass plan spawns (§D3): everything due spawns now unless the alive cap is
## reached, in which case the queue HOLDS (the rest spawn as bodies die).
func _spawn_mass_due(ev: Array) -> void:
	var lod: int = 1
	while plan_idx < plan.size() and float((plan[plan_idx] as Dictionary)["t"]) <= wave_t:
		if en.count() >= mass_cap:
			return
		var pe: Dictionary = plan[plan_idx]
		plan_idx += 1
		var pw: int = int(pe.get("w", wave))
		lod = int(plan_lod.get(pw, 1))
		var at: Vector2 = CENTER + Vector2.from_angle(float(pe.get("a", 0.0))) * (spawn_r() + float(pe.get("j", 0.0)))
		if _spawn(String(pe["kind"]), ev, at, bool(pe.get("marked", false)), 1.0, pw, lod):
			wave_spawned += 1
	if plan_idx >= plan.size():
		# every wave up to this plan (incl. a held remainder carried into it) is fully spawned
		for aw in wave_acct.keys():
			var a: Dictionary = wave_acct[aw]
			if int(aw) <= plan_wave and not bool(a["planned_done"]):
				a["planned_done"] = true
				_mass_try_clear(int(aw), ev)


## Body budget: the mass alive cap.
func max_bodies() -> int:
	return mass_cap


## Spawn one designed mass body (the alive cap is enforced where the plan
## spawns: it HOLDS the queue; bosses, couriers and Broodsac young are never
## dropped). `share` is unused since V2 P3d (no legacy split knob).
func _spawn(kind: String, ev: Array, at: Vector2 = Vector2.INF, marked: bool = false, _share: float = 1.0, pw: int = -1, lod: int = 1) -> bool:
	return _spawn_mass(kind, ev, at, marked, pw if pw > 0 else wave, lod)


## §D2 per-body HP scale of `kind` at wave w: fodder / line x1.035^(w-1),
## heavies x1.05^(w-1) (Tune mass_hp_g_f / mass_hp_g_h), x tier / perks /
## modifiers / global difficulty x mass_hp_k. Elites and bosses keep the
## classic curves (§D2: "elites and bosses keep the existing curves").
func mass_hp_scale(kind: String, w: int) -> float:
	var g: String = String(EnemyDB.mass_def(kind).get("grow", "f"))
	var gr: float = mass_hp_growth(tier) * (TuneRef.num("mass_hp_heavy", 1.015) if g == "h" else 1.0)
	var cap_w: int = TuneRef.int_of("pc_endless_soft_wave", 100)
	var ww: int = mini(w, cap_w) if mode == "endless" else w
	var sc: float = pow(gr, float(ww - 1)) * TuneRef.num("mass_hp_k", 0.5)
	if mode == "endless" and w > cap_w:
		sc *= pow(TuneRef.num("mass_endless_hp_exp", 1.04), float(w - cap_w))
	return sc * mass_tier_hp() * float(stats.get("perk_enemy_hp", 1.0)) * enemy_hp_mod * (1.0 + 0.15 * float(pack_n("pk_gambit"))) * difficulty_hp()


## §D7 "tier HP multipliers stay modest": a tier's threat is its body count
## (tierB); the tier HP factor is only what tierB does not already carry:
## max(1, Tiers.hp_mult / tierB) (1.0 at T1-T6), so a tier's total wave HP
## tracks the classic tier step instead of compounding with x1.6-x6 bodies.
func mass_tier_hp() -> float:
	return maxf(1.0, hp_mult / EnemyDB.tier_b(tier))


## Per-body HP growth per wave (fodder / line). Re-derived from bot runs
## (MASS_HORDE §D10 dated note): §D2's 1.035 left total wave HP growing x1.149
## per wave against a player whose power grows with the classic curve, so runs
## never ended (a fresh bot reached wave 73). The body count carries most of
## the growth (x1.11); the body HP carries the rest of the classic tier curve:
## hp_growth(tier) / mass_b_growth x mass_hp_track (1.04 = the classic
## per-wave spawn-count growth averaged over waves 1-40).
static func mass_hp_growth(t: int) -> float:
	var g: float = TuneRef.num("mass_hp_g_f", 0.0)
	if g > 0.0:
		return g
	return PowerModel.hp_growth(t) / TuneRef.num("mass_b_growth", 1.11) * TuneRef.num("mass_hp_track", 1.006)


## One designed mass body (§D1/§D2). `lod` > 1 only under the harness LOD.
func _spawn_mass(kind: String, ev: Array, at: Vector2, marked: bool, pw: int, lod: int) -> bool:
	var md: Dictionary = EnemyDB.mass_def(kind)
	var bossy: bool = kind == "boss" or kind == "elite"
	var pos: Vector2 = at
	if at == Vector2.INF:
		pos = CENTER + Vector2.from_angle(rng.randf() * TAU) * spawn_r()
	var e: int = en.alloc(next_eid, kind, pos)
	next_eid += 1
	var lw: float = float(lod)
	if kind == "courier":
		# Loot runner (top layer): classic rewards, outside the wave pools.
		var cdef: Dictionary = EnemyDB.get_def("courier")
		en.hp[e] = float(md["hp"]) * mass_hp_scale(kind, pw)
		en.max_hp[e] = en.hp[e]
		en.spd[e] = float(md["spd"]) * enemy_spd_mod
		en.cash[e] = float(cdef["cash"])
		en.xp[e] = float(cdef["xp"])
		en.coin[e] = float(cdef["coin"])
		en.set_size(e, float(md["size"]))
		en.commit(e)
		return true
	var a: Dictionary = _mass_acct(pw)
	if bossy:
		# Kept units: classic HP curve (boss ramps below), designed contact damage.
		var cd: Dictionary = EnemyDB.get_def(kind)
		var sc: float = scale() * hp_mult * float(stats.get("perk_enemy_hp", 1.0)) * enemy_hp_mod * (1.0 + 0.15 * float(pack_n("pk_gambit"))) * difficulty_hp()
		en.hp[e] = float(cd["hp"]) * sc * TuneRef.num("mass_" + kind + "_hp", 1.0)
	else:
		en.hp[e] = float(md["hp"]) * mass_hp_scale(kind, pw) * lw
	en.max_hp[e] = en.hp[e]
	en.spd[e] = float(md["spd"]) * float(stats.get("perk_enemy_spd", 1.0)) * enemy_spd_mod
	if kind == "boss":
		# The boss keeps the classic contact damage curve too (tuned against the
		# Core's HP track; §D2's 40 per hit walled the first boss).
		en.dmg[e] = float(EnemyDB.get_def(kind)["dmg"]) * pow(dmg_growth, float(wave - 1)) * hp_mult * enemy_dmg_mod * difficulty_dmg()
	else:
		en.dmg[e] = float(md["dmg"]) * pow(TuneRef.num("mass_dmg_g", dmg_growth), float(pw - 1)) * mass_tier_hp() * enemy_dmg_mod * difficulty_dmg() * TuneRef.num("mass_dmg_k", 0.4) * lw
		if kind == "elite":
			en.dmg[e] *= TuneRef.num("mass_elite_dmg", 1.0)
	en.cash[e] = float(a["pool"]) * float(md["cash"]) / float(a["W"]) * lw
	en.xp[e] = float(a["xpool"]) * float(md["xp"]) / float(a["W"]) * lw
	en.coin[e] = float(a["cpool"]) * float(md["coin"]) / float(a["CW"]) * lw if float(a["CW"]) > 0.0 else 0.0
	en.set_size(e, float(md["size"]) * minf(3.0, sqrt(lw)))
	en.wv[e] = pw
	en.wt[e] = lod
	a["spawned"] = int(a["spawned"]) + lod
	mass_spawned += lod
	match kind:
		"boss":
			var r0: float = TuneRef.num("boss_ramp_from", 10.0)
			var ramp: float = clampf((float(wave) - r0) / 20.0, 0.0, 1.0)
			var bm: float = TuneRef.num("boss_hp_hi", 0.5) if tier >= 2 else 1.0 + (TuneRef.num("boss_hp_t1", 3.0) - 1.0) * ramp
			if tier == 1 and wave <= 10:
				bm *= TuneRef.num("pc_first_boss", 0.6)
			en.hp[e] = en.hp[e] * bm
			en.max_hp[e] = en.hp[e]
			en.dmg[e] = en.dmg[e] * TuneRef.num("pc_boss_dmg", 1.0) * TuneRef.num("mass_boss_dmg", 0.5)
		"elite":
			en.shield[e] = TuneRef.int_of("elite_shield_base", 3) + pw / 10 + elite_shield_add
			en.max_shield[e] = en.shield[e]
		"ranged":
			en.fire_cd[e] = TuneRef.num("ranged_fire", 2.0)
		"shield":
			en.guard[e] = float(md.get("guard", 0.0)) * mass_hp_scale(kind, pw) * lw
	if marked:
		en.flags[e] = en.flags[e] | EnemyStore.F_MARKED
		en.hp[e] = en.hp[e] * TuneRef.num("pc_mark_hp", 3.0)
		en.max_hp[e] = en.max_hp[e] * TuneRef.num("pc_mark_hp", 3.0)
	en.commit(e)
	mass_peak = maxi(mass_peak, en.count())
	mass_wave_peak = maxi(mass_wave_peak, en.count())
	if kind == "boss":
		ev.append({"t": "boss", "pos": en.pos[e]})
	if marked:
		ev.append({"t": "elite_marked", "eid": en.eid[e], "pos": en.pos[e]})
	return true


## ---- EnemyStore accessors for views / tools / tests (rules use en.* directly)
## Inject a body from a legacy Dict (missing keys -> Dict-code defaults); a
## missing eid gets the next one, written back into `d`. Returns its slot.
func add_enemy(d: Dictionary) -> int:
	if not d.has("eid"):
		d["eid"] = next_eid
		next_eid += 1
	var s: int = en.alloc(int(d["eid"]), String(d.get("kind", "drone")), d.get("pos", CENTER))
	en.fill(s, d)
	d["slot"] = s
	return s


## Replace the whole field (tests): clears the store, injects in order, so
## slots are 0..n-1 in list order.
func set_enemies(list: Array) -> void:
	en.clear()
	for d in list:
		add_enemy(d)


## Fresh Dict copy of a stored body by eid ({} when it is gone).
func enemy_dict(id: int) -> Dictionary:
	var s: int = en.slot_of(id)
	return en.get_dict(s) if s >= 0 else {}


## Dict copies of every stored body, spawn order (debug / tests / tools).
func enemy_list() -> Array:
	return en.to_dicts()


func enemy_count() -> int:
	return en.count()


## Write fields of a stored body (tests / tools). Keys as in get_dict.
func set_enemy(id: int, fields: Dictionary) -> void:
	var s: int = en.slot_of(id)
	if s < 0:
		return
	var d: Dictionary = en.get_dict(s)
	d.merge(fields, true)
	en.fill(s, d)


## Courier (REDESIGN §2.6): a rare loot runner that crosses the field on a
## chord well outside the wall at 3x speed and escapes if not killed.
func _spawn_courier(ev: Array) -> void:
	var a: float = drop_rng.randf() * TAU
	var from: Vector2 = CENTER + Vector2.from_angle(a) * spawn_r()
	var to: Vector2 = CENTER + Vector2.from_angle(a + deg_to_rad(110.0)) * spawn_r()
	if not _spawn("courier", ev, from):
		return
	var cd: int = en.order[en.order.size() - 1]
	en.set_exit(cd, to)
	couriers += 1
	ev.append({"t": "courier_spawn", "eid": en.eid[cd], "pos": from, "to": to})


func _core_damage(amt: float, ev: Array, kind: String, from: Vector2, src: int = -1, share: float = 1.0) -> void:
	if immune_t > 0.0:
		return
	# Mirror Hull: contact hits reflect a share back to the attacker (slot src).
	if kind == "core_hit" and src >= 0 and float(stats.get("reflect", 0.0)) > 0.0 and en.hp[src] > 0.0:
		_hit(src, amt * float(stats["reflect"]), ev)
	var real: float = maxf(amt * TuneRef.num("pc_armor_floor", 0.25), amt - float(stats.get("armor", 0.0)) * share)   # flat armor split per horde body (owner C4)
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
	var frozen: bool = float(buffs.get("warp_t", 0.0)) > 0.0
	# Occupancy of every building footprint cell (the Core is never a blocker:
	# its contact ring is STOP_R).
	var blk: PackedByteArray = PackedByteArray()
	blk.resize(N)
	if occ.size() != N:
		_rebuild_occ()
	for i in N:
		if occ[i] >= 0 and occ[i] != CORE_SLOT:
			blk[i] = 1
	# MASS_HORDE: the step runs in the C# HordeWorld (flow field, pressure,
	# knockback, contact). It returns an ordered action log of Core effects,
	# replayed in slot order. V2 P3a: structures have no HP - bodies flow
	# around them, or squeeze through (horde_squeeze speed) when they seal the
	# route; every attack lands on the Core.
	var acts: PackedInt32Array = en.move(dt, frozen, CENTER, STOP_R, r_stop, r_fire, blk, SIDE, CELL, PackedFloat64Array([TuneRef.num("horde_accel", 6.0), TuneRef.num("horde_sep", 0.5), TuneRef.num("horde_sep_cap", 0.35), TuneRef.num("horde_friction", 6.0), TuneRef.num("horde_kmax", 24.0), TuneRef.num("horde_front", 10.0), TuneRef.num("horde_bld_cost", 40.0), TuneRef.num("horde_knock_max", 600.0), TuneRef.num("mass_press", 48.0), TuneRef.num("horde_squeeze", 0.35)]))
	var k: int = 0
	var escaped: Array = []
	while k < acts.size():
		var op: int = acts[k]
		var e: int = acts[k + 1]
		k += 2
		match op:
			EnemyStore.ACT_BOOM:
				# MASS_HORDE §D1 / V2: a Sapper reaches the Core and detonates for
				# horde_sapper_core x its hit; it is gone (no kill, no reward).
				k += 1
				en.hp[e] = 0.0
				en.flags[e] = en.flags[e] | EnemyStore.F_BOOM
				_leak(e)
				var bamt: float = en.dmg[e] * TuneRef.num("horde_sapper_core", 6.0)
				ev.append({"t": "sapper_blast", "slot": CORE_SLOT, "dmg": bamt, "pos": en.pos[e]})
				_core_damage(bamt, ev, "core_hit", en.pos[e], -1, _armor_share(e))
			EnemyStore.ACT_SHOT:
				# MASS_HORDE §D1 Spitter: lobs acid at the Core from its stand-off ring.
				_core_damage(en.dmg[e], ev, "enemy_shot", en.pos[e], -1, _armor_share(e))
			EnemyStore.ACT_HIT:
				_leak(e)
				_core_damage(en.dmg[e], ev, "core_hit", en.pos[e], e, _armor_share(e))
			EnemyStore.ACT_ESCAPE:
				escaped.append(e)
	for x in escaped:
		var xs: int = x
		ev.append({"t": "courier_escape", "eid": en.eid[xs], "pos": en.pos[xs]})
		en.remove(xs)


## MASS_HORDE §D5: a body reaching the Core forfeits its share of the wave's
## cash pool (counted once).
func _leak(e: int) -> void:
	if (en.flags[e] & EnemyStore.F_LEAK) == 0:
		en.flags[e] = en.flags[e] | EnemyStore.F_LEAK
		mass_leaked += en.wt[e]
		var la: Dictionary = wave_acct.get(en.wv[e], {})
		if not la.is_empty():
			la["leak"] = int(la["leak"]) + en.wt[e]


## Flat Core armor per contact hit (owner C4): the classic split carried
## `share`; a designed mass body is armored against in proportion to its hit
## vs the classic drone's hit at this wave, so armor blunts the tide exactly as
## much as it blunted classic hits, without making a swarmling hit vanish.
func _armor_share(e: int) -> float:
	# armor takes the same FRACTION off a body's hit as off a classic drone's hit this wave
	var ref: float = float(EnemyDB.get_def("drone")["dmg"]) * pow(dmg_growth, float(wave - 1)) * hp_mult * enemy_dmg_mod * difficulty_dmg()
	return clampf(en.dmg[e] / maxf(0.001, ref), 0.0, 4.0)


## Targeting (pattern adapted from ape1121/Godot-4-Tower-Defense-Template, MIT:
## try_get_closest_target; first/strongest/weakest are in-house). Pure: picks
## a slot of `en` within `rng_lim` of `from`, or -1. Hash candidates come in
## spawn order, so the `<` + d^2 tie-break picks what the linear scan did.
func pick_target(from: Vector2, rng_lim: float, mode_s: String) -> int:
	if mode_s == "nearest":
		return _nearest(from, rng_lim, {})
	var best: int = -1
	var best_key: float = INF
	var best_d: float = INF
	var lim2: float = rng_lim * rng_lim
	for k in eh.candidates(from, rng_lim):
		var hpv: float = en.hp[k]
		if hpv <= 0.0:
			continue
		var p: Vector2 = en.pos[k]
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
	return eh.nearest(from, rng_lim, exclude)


## Every hit goes through here: Ironclad, an elite's shield absorbs whole
## hits, Obelisk lifesteal heals the Core.
func _hit(e: int, dmg_in: float, ev: Array, crit: bool = false) -> void:
	var dmg: float = dmg_in
	if not crit and ironclad > 0.0:
		dmg *= 1.0 - ironclad
	_blocked = false
	if en.guard[e] > 0.0 and _blockable:
		# Shieldbearer (§D1): its frontal shield (facing the Core, the way it
		# walks) soaks projectiles from the front; AoE / chain / flank get by.
		var to_shooter: Vector2 = _kb_from - en.pos[e]
		var facing: Vector2 = CENTER - en.pos[e]
		if to_shooter.dot(facing) > 0.7071 * to_shooter.length() * facing.length():
			_blocked = true
			var g: float = en.guard[e] - dmg
			en.guard[e] = maxf(0.0, g)
			ev.append({"t": "shield_hit", "pos": en.pos[e], "left": int(ceil(maxf(0.0, g)))})
			if g >= 0.0:
				return
			dmg = -g
	var sh: int = en.shield[e]
	if sh > 0:
		sh -= 1
		en.shield[e] = sh
		ev.append({"t": "shield_hit", "pos": en.pos[e], "left": sh})
		if sh == 0:
			ev.append({"t": "shield_break", "pos": en.pos[e]})
		return
	# Parts: Hunter Scope (vs bosses/elites/marked, else the normal-enemy tax)
	# and Singularity Lens shred stacks (+shred per stack, x5).
	if BOSSY.has(en.kind[e]) or en.is_marked(e):
		dmg *= float(stats.get("boss_mult", 1.0))
	else:
		dmg *= float(stats.get("normal_mult", 1.0))
	if en.shred_n[e] > 0:
		dmg *= 1.0 + float(stats.get("shred", 0.0)) * float(en.shred_n[e])
	if (en.flags[e] & EnemyStore.F_FROST) != 0 and en.slow_t[e] > 0.0 and BOSSY.has(en.kind[e]):
		dmg *= TuneRef.num("mass_brittle", 1.25)   # Cryo Brittle (§D4)
	var real: float = minf(dmg, maxf(0.0, en.hp[e]))
	if _kb_k > 0.0 and en.max_hp[e] > 0.0:
		# Phase 4: hit impulse scaled by damage share and the weapon factor
		var away: Vector2 = en.pos[e] - _kb_from
		if away != Vector2.ZERO:
			en.knock(e, away.normalized() * (_kb_k * TuneRef.num("horde_knock", 60.0) * (0.25 + minf(1.0, dmg / en.max_hp[e]))))
	var was: float = en.hp[e]
	en.hp[e] = en.hp[e] - dmg
	if en.hp[e] <= 0.0:
		en.kill(e)
		if was > 0.0:
			var sk: String = _src if _src != "" else "other"
			kills_by_weapon[sk] = int(kills_by_weapon.get(sk, 0)) + en.wt[e]
			# Overkill smash (§D4 "DPS must turn into kills against a crowd"):
			# the surplus of a killing hit carries into the nearest touching
			# body (x0.6, up to mass_carry hops), so damage upgrades keep
			# buying kills after the swarm is one-shot.
			var sur: float = (dmg - was) * TuneRef.num("mass_carry_frac", 0.6)
			if sur > 0.0 and _carry_d < TuneRef.int_of("mass_carry", 3):
				var nb: int = eh.nearest(en.pos[e], en.size[e] + 8.0, {e: true})
				if nb >= 0:
					_carry_d += 1
					_hit(nb, sur, ev, crit)
					_carry_d -= 1
	en.flash(e, HIT_FLASH)
	var ls: float = float(stats.get("lifesteal", 0.0))
	if ls > 0.0 and real > 0.0:
		hp = minf(float(stats["max_hp"]), hp + real * ls)
	# one "hits" summary per substep (_flush_hits): per-hit events would cost
	# more than the sim at 10k bodies
	_hn += 1
	_hsum += dmg
	if crit:
		_hcrit += 1
	if _htop.size() < AGG_TOP:
		_htop.append({"t": "dmg", "eid": en.eid[e], "pos": en.pos[e], "amt": dmg, "crit": crit})
	elif dmg > float((_htop[_hn % AGG_TOP] as Dictionary)["amt"]):
		_htop[_hn % AGG_TOP] = {"t": "dmg", "eid": en.eid[e], "pos": en.pos[e], "amt": dmg, "crit": crit}


## Overkill carry (single-target shots): damage left over after a kill rolls
## to the nearest living enemy within range of the shooter (up to
## pc_carry_hops times), so surplus DPS becomes kill throughput when the
## field floods. Shields still eat whole hits. Candidates: hash cells around
## the shooter's range (spawn order, `<=` tie as the linear scan).
func _hit_carry(e0: int, dmg: float, ev: Array, crit: bool, from: Vector2, rng_lim: float) -> void:
	var cur: int = e0
	var left: float = dmg
	var done: Dictionary = {}
	var cands: PackedInt32Array = PackedInt32Array()
	var have_cands: bool = false
	# FB2 crowd tool: the Gun's overkill carry hops further through a horde
	var hops: int = TuneRef.int_of("pc_carry_hops", 2) + (TuneRef.int_of("pc_horde_carry_hops", 2) if crowd() else 0)
	for hop in hops + 1:
		var before: float = en.hp[cur]
		var sh: int = en.shield[cur]
		_hit(cur, left, ev, crit)
		if sh > 0 or en.hp[cur] > 0.0:
			return
		left = (left * (1.0 - ironclad if not crit and ironclad > 0.0 else 1.0) - maxf(0.0, before)) * TuneRef.num("pc_carry_frac", 0.6)
		if left <= 0.0:
			return
		done[cur] = true
		if not have_cands:
			cands = eh.candidates(from, rng_lim)
			have_cands = true
		var best: int = -1
		var bd: float = INF
		var cpos: Vector2 = en.pos[cur]
		for x in cands:
			if done.has(x) or en.hp[x] <= 0.0:
				continue
			if from.distance_squared_to(en.pos[x]) > rng_lim * rng_lim:
				continue
			var d2: float = cpos.distance_squared_to(en.pos[x])
			if d2 <= bd:
				bd = d2
				best = x
		if best < 0:
			return
		cur = best


func _roll_crit(wd: Dictionary) -> bool:
	var c: float = float(stats.get("crit", 0.0)) + float(wd.get("crit", 0.0))
	return c > 0.0 and combat_rng.randf() < c


## Wall (id "barricade"; omnidirectional): with spawns from every side there is
## no lane to wall off, so each Wall drags every body within its radius (-30%
## speed) on top of being a blocker the horde must flow around or squeeze
## through. Wall of Flesh: one Wall slows 2,000 distinct bodies in a wave.
func _wall_auras(ev: Array) -> void:
	wall_tick += 1
	var r: float = TuneRef.num("pc_wall_aura", 1.5) * cpx()
	var sm: float = 1.0 - TuneRef.num("pc_wall_slow", 0.30)
	for i in slots.size():
		if id_at(i) != "barricade":
			continue
		var c: Vector2 = fp_pos(i)
		var hit: PackedInt32Array = en.slow_radius(c, r, 0.2, sm)   # one C# call per Wall (P3d perf)
		# Wall of Flesh: distinct bodies, sampled every 4th substep (a body
		# stays in the aura for many substeps, so no one is missed).
		var seen: Dictionary = mass_wall_slowed.get(i, {})
		var n0: int = seen.size()
		if n0 < WALL_FLESH and (wall_tick % 4) == 0:
			for fe in hit:
				seen[en.eid[fe]] = true
			mass_wall_slowed[i] = seen
			if seen.size() >= WALL_FLESH:
				ev.append({"t": "wall_of_flesh", "slot": i, "n": seen.size()})


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
		_kb_k = 0.0
		_blockable = false
		if si == CORE_SLOT:
			_kb_k = float(KNOCK_W["core"])
			_kb_from = CENTER
			_src = "core"
			_blockable = ["cannon", "beam"].has(String(wd.get("attack", "")))
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
		var from: Vector2 = fp_pos(si)
		_kb_k = float(KNOCK_W.get(kind, 0.0))
		_kb_from = from
		_src = kind
		if kind == "frost":
			# Aura: every pulse slows and chills every enemy in range.
			# MASS_HORDE §D4: -50% in the field; slowed bodies block the ones
			# behind (the C# front-blocking rule), so the flow backs up behind
			# the field (viscosity); chilled bodies shatter / turn Brittle.
			var any: bool = false
			var frange: float = float(wd["range"])
			var fslow: float = maxf(float(wd["slow"]), TuneRef.num("mass_frost_slow", 0.5))
			for fe in eh.candidates(from, frange):
				if en.hp[fe] > 0.0 and from.distance_to(en.pos[fe]) <= frange:
					any = true
					en.apply_slow(fe, float(wd["slow_t"]), 1.0 - fslow)
					en.flags[fe] = en.flags[fe] | EnemyStore.F_FROST
					_hit(fe, float(wd["dmg"]) * TuneRef.num("mass_frost_dmg", 0.1), ev)   # a force multiplier, not a blender (§D4: 5-20 kills/s direct)
			if any:
				ev.append({"t": "shot", "kind": "frost", "from": from, "to": from, "radius": float(wd["range"])})
				cooldowns[si] = cd + 1.0 / rate
			else:
				cooldowns[si] = 0.0
			continue
		var tgt: int = pick_target(from, float(wd["range"]), String(target_modes[si]) if si < target_modes.size() else "nearest")
		if kind == "mortar" and tgt >= 0 and from.distance_to(en.pos[tgt]) < float(wd.get("min_range", 0.0)):
			# A crowd at the wall must not silence the mortar: lob at the
			# nearest body beyond the minimum range instead.
			tgt = -1
			var mr2: float = float(wd["min_range"]) * float(wd["min_range"])
			for cand in eh.nearest_n(from, 96, float(wd["range"])):
				if from.distance_squared_to(en.pos[cand]) >= mr2:
					tgt = cand
					break
		if tgt < 0:
			cooldowns[si] = 0.0
			continue
		cooldowns[si] = cd + 1.0 / rate
		var dmg: float = float(wd["dmg"])
		var te: int = tgt
		var crit: bool = _roll_crit(wd)
		if crit:
			dmg *= TuneRef.num("pc_crit_mult", 2.0)
		_fire_mass(kind, wd, from, te, dmg, crit, ev)


## MASS_HORDE §D4 weapon verbs (mass runs). Damage stays in each weapon's
## classic range (upgrades / Labs / parts apply unchanged); the SHAPE changes
## so every weapon turns its DPS into kills per second against a dense crowd.
func _fire_mass(kind: String, wd: Dictionary, from: Vector2, te: int, dmg: float, crit: bool, ev: Array) -> void:
	var tpos: Vector2 = en.pos[te]
	var lvl: int = int(wd.get("lvl", 1))
	match kind:
		"railgun":
			# Infinite pierce along the line, no falloff; x4 on the first elite /
			# boss it meets (the elite/boss killer). Bodies in line order.
			var dir: Vector2 = (tpos - from).normalized()
			var reach: float = float(wd["range"])
			var tip: Vector2 = from + dir * reach
			var on: Array = []
			for ed in eh.line(from, tip, float(wd["pierce"]) + en.max_size * 0.5 + 1.0):
				if en.hp[ed] <= 0.0:
					continue
				var rel: Vector2 = en.pos[ed] - from
				var along: float = rel.dot(dir)
				if along < 0.0 or along > reach or absf(rel.cross(dir)) > float(wd["pierce"]) + en.size[ed] * 0.5:
					continue
				on.append([along, ed])
			on.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
			var boss_hit: bool = false
			_blockable = true
			for x in on:
				var ed2: int = int((x as Array)[1])
				var m: float = 1.0
				if not boss_hit and (BOSSY.has(en.kind[ed2]) or en.is_marked(ed2)):
					boss_hit = true
					m = TuneRef.num("mass_rail_boss", 4.0)
				_hit(ed2, dmg * m, ev, crit)
			_blockable = false
			ev.append({"t": "shot", "kind": kind, "from": from, "to": tip})
		"flak":
			# Flamer: a gout every ~1.3 s into a 40 deg cone (1.4 cells, +10%/lv):
			# a light lick plus a 2 s burn that spreads to touching bodies.
			var dir2: Vector2 = (tpos - from).normalized()
			var cl: float = minf(float(wd["range"]), TuneRef.num("mass_flame_len", 1.4) * cpx() * (1.0 + 0.1 * float(lvl - 1)))
			var bdps: float = dmg * TuneRef.num("mass_flame_burn", 0.3)
			for ed in eh.cone(from, dir2, deg_to_rad(20.0), cl):
				if en.hp[ed] <= 0.0:
					continue
				_hit(ed, dmg * TuneRef.num("mass_flame_hit", 0.15), ev, crit)
				_ignite(ed, TuneRef.num("mass_burn_s", 2.0), bdps)
			ev.append({"t": "shot", "kind": kind, "from": from, "to": from + dir2 * cl, "cone": 40.0})
		"mortar":
			# AoE r 0.75 cell (~60 px, +20%/lv); the outer ring is a knockback blast that
			# parts the sea (impulse / mass); 500+ pushed = Parting the Sea.
			var rad: float = TuneRef.num("mass_mortar_r", 0.75) * cpx() * (1.0 + 0.2 * float(lvl - 1))
			for ed in eh.candidates(tpos, rad):
				if en.hp[ed] > 0.0 and en.pos[ed].distance_to(tpos) <= rad:
					_hit(ed, dmg, ev, crit)
			var pushed: int = en.radial_knock(tpos, rad * 1.5, TuneRef.num("horde_knock", 60.0) * TuneRef.num("mass_mortar_knock", 2.0))
			if pushed >= 500:
				ev.append({"t": "part_sea", "n": pushed, "pos": tpos})
			ev.append({"t": "shot", "kind": kind, "from": from, "to": tpos, "radius": rad})
		"tesla":
			# Chain 6 (+3/lv, + chain parts, cap 20), 70 px jumps, x0.9 per jump;
			# stuns elites / bosses for 0.2 s.
			# Each discharge forks into 3 arcs (the nearest 3 bodies), each one
			# chaining on to bodies no arc has hit yet.
			var n: int = mini(TuneRef.int_of("mass_chain_cap", 20), TuneRef.int_of("mass_chain", 6) + 3 * (lvl - 1) + int(pf("chain")))
			var jr: float = TuneRef.num("mass_chain_r", 70.0)
			var hit: Dictionary = {}
			var starts: Array = [te]
			for st in eh.nearest_n(from, TuneRef.int_of("mass_tesla_arcs", 3) + 1, float(wd["range"])):
				if starts.size() >= TuneRef.int_of("mass_tesla_arcs", 3):
					break
				if st != te:
					starts.append(st)
			for s0 in starts:
				var ce: int = s0
				var d2: float = dmg
				var prev: Vector2 = from
				var jumps: int = 0
				while ce >= 0 and jumps < n:
					jumps += 1
					hit[ce] = true
					var cpos: Vector2 = en.pos[ce]
					if en.hp[ce] > 0.0:
						_hit(ce, d2, ev, crit)
						en.set_shock(ce, 1.5)
						en.shock_src[ce] = int(wd["slot"])
						if BOSSY.has(en.kind[ce]):
							en.apply_slow(ce, 0.2, 0.0)
					ev.append({"t": "shot", "kind": kind, "from": prev, "to": cpos})
					prev = cpos
					d2 *= TuneRef.num("mass_chain_frac", 0.9)
					ce = _nearest(cpos, jr, hit)
		_:
			# Gun: rounds pierce 3 bodies (+2/lv, cap 12), x0.85 per body;
			# a Shieldbearer's front stops the round.
			var pn: int = mini(12, 3 + 2 * (lvl - 1))
			var reach3: float = float(wd["range"])
			# Two rounds per shot against a crowd: the target and the next nearest.
			var aims: Array = [te]
			for t2 in eh.nearest_n(from, 2, reach3):
				if aims.size() < TuneRef.int_of("mass_gun_rounds", 2) and t2 != te:
					aims.append(t2)
			for ai in aims:
				_gun_round(from, en.pos[int(ai)], int(ai), pn, reach3, dmg, crit, ev)


## One Gun round (§D4): pierces up to `pn` bodies along the line, x0.85 each;
## a Shieldbearer's front stops it.
func _gun_round(from: Vector2, tpos: Vector2, te: int, pn: int, reach3: float, dmg: float, crit: bool, ev: Array) -> void:
	var dir3: Vector2 = (tpos - from).normalized()
	var on3: Array = []
	for ed in eh.line(from, from + dir3 * reach3, en.max_size * 0.5 + 2.0):
		if en.hp[ed] <= 0.0:
			continue
		var rel3: Vector2 = en.pos[ed] - from
		var al: float = rel3.dot(dir3)
		if al < 0.0 or al > reach3 or absf(rel3.cross(dir3)) > en.size[ed] * 0.5 + 2.0:
			continue
		on3.append([al, ed])
	on3.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
	var d3: float = dmg
	var hitn: int = 0
	var last: Vector2 = tpos
	_blockable = true
	for x in on3:
		if hitn >= pn:
			break
		var ed3: int = int((x as Array)[1])
		_hit(ed3, d3, ev, crit)
		last = en.pos[ed3]
		hitn += 1
		if _blocked:
			break
		d3 *= TuneRef.num("mass_pierce_fall", 0.85)
	_blockable = false
	if hitn == 0 and en.hp[te] > 0.0:
		_hit(te, dmg, ev, crit)
	ev.append({"t": "shot", "kind": "gun", "from": from, "to": last})


## Warlord aura (§D1): every 0.25 s each living Warlord hastes the fodder
## within 120 px by +20% (a surge); killing it breaks the surge.
var surge_acc: float = 0.0
const FODDER: Array = ["mite", "drone", "skitter"]
func _warlord_surge(dt: float) -> void:
	surge_acc += dt
	if surge_acc < 0.25 - 0.000001:
		return
	surge_acc = 0.0
	var r: float = TuneRef.num("mass_surge_r", 120.0)
	var m: float = TuneRef.num("mass_surge", 1.2)
	for e in en.order:
		if en.kind[e] != "elite" or en.hp[e] <= 0.0:
			continue
		var c: Vector2 = en.pos[e]
		for f in eh.in_radius(c, r):
			if FODDER.has(en.kind[f]):
				en.haste(f, 0.35, m)


## Flamer burn (§D4): `t` seconds at `dps`, refreshed to the longer burn.
func _ignite(e: int, t: float, dps: float) -> void:
	if en.burn_t[e] <= 0.0:
		burning.append(e)
	en.burn_t[e] = maxf(en.burn_t[e], t)
	en.burn_d[e] = maxf(en.burn_d[e], dps)


## Burns tick every 0.25 s; each burning body with >= 0.5 s left lights one
## touching neighbour (half its remaining time): fire spreads through a pile.
func _burn_step(dt: float, ev: Array) -> void:
	if burning.is_empty():
		return
	burn_acc += dt
	if burn_acc < 0.25 - 0.000001:
		return
	var tk: float = burn_acc
	burn_acc = 0.0
	_src = "flak"
	_kb_k = 0.0
	_blockable = false
	var keep: PackedInt32Array = PackedInt32Array()
	var lit: Array = []
	for b in burning:
		if en.hp[b] <= 0.0 or en.burn_t[b] <= 0.0 or not en.world.call("IsLive", b):
			en.burn_t[b] = 0.0
			continue
		var bt: float = minf(tk, en.burn_t[b])
		_hit(b, en.burn_d[b] * bt, ev)
		en.burn_t[b] = en.burn_t[b] - bt
		if en.burn_t[b] >= 0.5 and en.hp[b] > 0.0:
			lit.append([b, en.burn_t[b] * 0.5, en.burn_d[b]])
		if en.burn_t[b] > 0.0 and en.hp[b] > 0.0:
			keep.append(b)
	burning = keep
	for l in lit:
		var src: int = int((l as Array)[0])
		# the nearest touching body that is not already on fire
		var sp: Vector2 = en.pos[src]
		var nb: int = -1
		var nd: float = INF
		for x in eh.in_radius(sp, en.size[src] * 0.5 + 6.0, true):
			if x == src or en.burn_t[x] > 0.0 or en.hp[x] <= 0.0:
				continue
			var d2: float = sp.distance_squared_to(en.pos[x])
			if d2 < nd:
				nd = d2
				nb = x
		if nb >= 0:
			_ignite(nb, float((l as Array)[1]), float((l as Array)[2]))
	_src = ""


## Lance beam: the ramp builds while the beam stays on one living target.
func _beam_hold(wd: Dictionary, dt: float) -> void:
	if beam_eid < 0:
		return
	var b: int = en.slot_of(beam_eid)
	if b >= 0 and en.hp[b] > 0.0 and CENTER.distance_to(en.pos[b]) <= float(wd["range"]):
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
				var te: int = tgt
				var tpos: Vector2 = en.pos[te]
				var crit: bool = _roll_crit(wd)
				var d: float = dmg * (TuneRef.num("pc_crit_mult", 2.0) if crit else 1.0)
				_hit_carry(te, d * float(wd.get("single_mult", 1.0)), ev, crit, CENTER, rng_lim)
				_shred(te, wd)
				targets.append(en.eid[te])
				_pierce(te, d, wd, ev, targets)
				var rad: float = float(wd.get("splash", 0.0))
				for ed in eh.candidates(tpos, rad):
					if ed != te and en.hp[ed] > 0.0 and en.pos[ed].distance_to(tpos) <= rad:
						_hit(ed, d * float(wd.get("splash_frac", 0.4)), ev)
						targets.append(en.eid[ed])
				ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": tpos, "radius": rad})
			if not hit_any:
				return false
		"slag":
			var tgt2: int = pick_target(CENTER, rng_lim, String(target_modes[CORE_SLOT]))
			if tgt2 < 0:
				return false
			var tpos2: Vector2 = en.pos[tgt2]
			var crit2: bool = _roll_crit(wd)
			var d2: float = dmg * (TuneRef.num("pc_crit_mult", 2.0) if crit2 else 1.0)
			var rad2: float = float(wd["splash"])
			for ed in eh.candidates(tpos2, rad2):
				if en.hp[ed] > 0.0 and en.pos[ed].distance_to(tpos2) <= rad2:
					_hit(ed, d2, ev, crit2)
					en.apply_slow(ed, float(wd["slow_t"]), 1.0 - float(wd["slow"]))
					targets.append(en.eid[ed])
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": tpos2, "radius": rad2})
		"beam":
			# Lock the highest-HP enemy in range; the ramp resets on a switch.
			var tgt3: int = pick_target(CENTER, rng_lim, "strongest")
			if tgt3 < 0:
				beam_eid = -1
				beam_t = 0.0
				return false
			var te3: int = tgt3
			if en.eid[te3] != beam_eid:
				beam_eid = en.eid[te3]
				beam_t = -float(wd.get("retarget", 0.0))   # Focus Lens retarget delay
			var ramp: float = clampf(float(wd["ramp"]) * beam_t, 0.0, float(wd["ramp_max"]))
			var d3: float = dmg * (1.0 + ramp) * float(wd.get("single_mult", 1.0))
			if BOSSY.has(en.kind[te3]) or en.is_marked(te3):
				d3 *= float(wd.get("boss_mult", 1.0))
			var crit3: bool = _roll_crit(wd)
			if crit3:
				d3 *= TuneRef.num("pc_crit_mult", 2.0)
			_hit_carry(te3, d3, ev, crit3, CENTER, rng_lim)
			_shred(te3, wd)
			targets.append(en.eid[te3])
			_pierce(te3, d3, wd, ev, targets)
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": en.pos[te3], "beam": true, "ramp": ramp})
		"pulse":
			var rings: int = int(wd.get("rings", 1))
			var inside: PackedInt32Array = PackedInt32Array()
			var in_set: Dictionary = {}
			for ed in eh.candidates(CENTER, rng_lim + en.max_size * 0.5):
				if en.hp[ed] > 0.0 and CENTER.distance_to(en.pos[ed]) <= rng_lim + en.size[ed] * 0.5:
					inside.append(ed)
					in_set[ed] = true
			if inside.is_empty():
				return false
			pulse_n += 1
			var crit4: bool = _roll_crit(wd)
			var d4: float = dmg * float(rings) * float(wd.get("pulse_mult", 1.0)) * (TuneRef.num("pc_crit_mult", 2.0) if crit4 else 1.0)
			var kb: float = float(wd.get("knock", 0.3)) * 40.0
			for xd in inside:
				_hit(xd, d4, ev, crit4)
				targets.append(en.eid[xd])
				# Phase 4: the old 12 px teleport is now an outward impulse
				# (mass-scaled; bosses / couriers immune inside knock()).
				var away: Vector2 = en.pos[xd] - CENTER
				if away != Vector2.ZERO:
					en.knock(xd, away.normalized() * kb * TuneRef.num("horde_pulse_knock", 6.0))
			# Static: every 5th pulse chains 40% dmg to 3 targets beyond range.
			if int(wd.get("chain_every", 0)) > 0 and pulse_n % int(wd["chain_every"]) == 0:
				var outer: Array = []
				# C# nearest-N (sorted) instead of a 10k-body GDScript sort
				for od in eh.nearest_n(CENTER, inside.size() + int(wd["chain_n"]), spawn_r() * 2.0):
					if en.hp[od] > 0.0 and not in_set.has(od):
						outer.append(od)
				for k in mini(int(wd["chain_n"]), outer.size()):
					var cd2: int = outer[k]
					_hit(cd2, dmg * float(wd["chain_frac"]), ev)
					targets.append(en.eid[cd2])
					ev.append({"t": "shot", "kind": "tesla", "from": CENTER, "to": en.pos[cd2]})
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": CENTER, "radius": rng_lim, "pulse": true})
	ev.append({"t": "core_attack", "kind": atk, "core": core_id, "targets": targets})
	return true


## Lancer 4-piece: the Core shot also hits the nearest other enemy to its target.
func _pierce(te: int, d: float, wd: Dictionary, ev: Array, targets: Array) -> void:
	if int(wd.get("pierce", 0)) <= 0:
		return
	var skip: Dictionary = {te: true}
	for n in int(wd["pierce"]):
		var j: int = _nearest(en.pos[te], cpx() * 1.5, skip)
		if j < 0:
			return
		skip[j] = true
		_hit(j, d, ev)
		targets.append(en.eid[j])


## Singularity Lens: Core hits stack armor shred on the target (max 5).
func _shred(te: int, _wd: Dictionary) -> void:
	if float(stats.get("shred", 0.0)) > 0.0:
		en.shred_n[te] = mini(5, en.shred_n[te] + 1)


## Storm 4-piece: a free Pulse Ring (Core dmg, Core range, x pulse_mult).
func _free_pulse(wd: Dictionary, ev: Array) -> void:
	var targets: Array = []
	var d: float = float(wd["dmg"]) * float(wd.get("pulse_mult", 1.0))
	var r: float = float(wd["range"])
	for ed in eh.candidates(CENTER, r + en.max_size * 0.5):
		if en.hp[ed] > 0.0 and CENTER.distance_to(en.pos[ed]) <= r + en.size[ed] * 0.5:
			_hit(ed, d, ev)
			targets.append(en.eid[ed])
	ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": CENTER, "radius": float(wd["range"]), "pulse": true})
	ev.append({"t": "core_attack", "kind": "pulse", "core": core_id, "targets": targets, "free": true})


## Troops: reconcile with huts, step the AI, apply their hits through _hit.
func _troops_step(dt: float, ev: Array) -> void:
	_drain_troop_events(ev)
	if troops.is_empty():
		return
	var res: Dictionary = Troops.step(troops, en, eh, dt, {"cell_px": cpx(), "cleave": TuneRef.int_of("mass_cleave", 4)})
	ev.append_array(res["ev"])
	for h in res["hits"]:
		var hd: Dictionary = h
		var ed: int = en.slot_of(int(hd["eid"]))
		if ed >= 0 and en.hp[ed] > 0.0:
			_hit(ed, float(hd["dmg"]), ev)
			# Swarm 4-piece: troops lifesteal 1%; a troop kill heals the Core.
			if pf("troop_ls") > 0.0:
				_troop_heal(int(hd.get("tid", -1)), 0.01 * float(hd["dmg"]))
				if en.hp[ed] <= 0.0:
					hp = minf(float(stats["max_hp"]), hp + 0.5)


func _troop_heal(tid: int, amt: float) -> void:
	for t in troops:
		var td: Dictionary = t
		if int(td["tid"]) == tid and String(td["state"]) != "dead":
			td["hp"] = minf(float(td["max_hp"]), float(td["hp"]) + amt)
			return


## Run end sweeps every wave's undropped loot pool, so a wave's loot value is
## exactly what its kills were worth (drops only change how it arrives).
func _sweep_horde_loot(all_waves: bool = false) -> void:
	if all_waves:
		for w in wave_acct.keys():
			_mass_sweep_loot(wave_acct[w])


func _reap(ev: Array) -> void:
	var alive: PackedInt32Array = PackedInt32Array()
	var ci: float = cash_index()
	var magnet: float = 2.0 if float(buffs.get("magnet_t", 0.0)) > 0.0 else 1.0
	var split: Array = en.split_order()   # C#: [alive, dead] in spawn order (no 10k GDScript scan)
	var dead_in: PackedInt32Array = split[1]
	if dead_in.is_empty():
		return
	alive = split[0]
	_reap_mass(alive, dead_in, ev, ci, magnet)


## MASS_HORDE reap (§D5): kill cash / XP / coins are each body's designed
## share of its wave's pool; a leaked body (reached the Core) forfeits it, a
## detonated Sapper is not a kill. Common loot draws from the wave's bounded
## pool with p = drops_left / bodies_left, so drops spread over a wave of any
## size. Freeze-shatter (Cryo) and Broodsac young happen here.
func _reap_mass(alive: PackedInt32Array, dead_in: PackedInt32Array, ev: Array, ci: float, magnet: float) -> void:
	var waves: Dictionary = {}
	var splits: Array = []
	var shatter: Array = []
	var dead: PackedInt32Array = PackedInt32Array()
	var kc_mult: float = float(stats.get("kill_cash", 1.0)) * run_cash_mult() * kill_cash_mod * magnet
	for ed in dead_in:
		dead.append(ed)
		var pos: Vector2 = en.pos[ed]
		var kind: String = en.kind[ed]
		var wt: int = en.wt[ed]
		var w: int = en.wv[ed]
		var a: Dictionary = wave_acct.get(w, {})
		if not a.is_empty():
			a["dead"] = int(a["dead"]) + wt
			waves[w] = true
		if (en.flags[ed] & EnemyStore.F_BOOM) != 0:
			ev.append({"t": "sapper_gone", "pos": pos})
			continue
		var leaked: bool = (en.flags[ed] & EnemyStore.F_LEAK) != 0
		var gain: float = 0.0
		if not leaked:
			var bm: float = 1.0
			for b in stats.get("bounties", []):
				var bd: Dictionary = b
				if (bd["pos"] as Vector2).distance_to(pos) <= float(bd["r"]):
					bm += float(bd["mult"])
			gain = en.cash[ed] * ci * bm * kc_mult
			cash += gain
			cash_earned += gain
			xp += en.xp[ed] * float(stats["xp_mult"])
			var cg: float = en.coin[ed] * (run_coin_mult() if kind == "courier" else 1.0)
			if not a.is_empty() and cg > 0.0:
				var fund: float = cg * HORDE_LOOT_FUND
				a["loot"] = float(a["loot"]) + fund
				cg -= fund
			coins_run += cg
			coins_kill += cg
		kills += wt
		mass_kills_wave[wave] = int(mass_kills_wave.get(wave, 0)) + wt
		ev.append({"t": "kill", "pos": pos, "cash": gain, "kind": kind, "n": wt})
		if not a.is_empty() and int(a["drops"]) > 0 and float(a["loot"]) > 0.0:
			var left: int = maxi(1, int(a["n"]) - int(a["dead"]) + 1)
			if horde_rng.randf() < float(a["drops"]) / float(left):
				var g: float = float(a["loot"]) / float(a["drops"])
				a["loot"] = float(a["loot"]) - g
				a["drops"] = int(a["drops"]) - 1
				coins_run += g
				horde_loot_total += g
				horde_loot_wave_val += g
				ev.append({"t": "loot_drop", "pos": pos, "coins": g, "wave": w})
		if kind == "boss":
			_boss_bounty(pos, ev)
		elif kind == "splitter":
			splits.append([pos, w, wt])
		if (en.flags[ed] & EnemyStore.F_FROST) != 0 and en.slow_t[ed] > 0.0:
			shatter.append([pos, en.max_hp[ed] * TuneRef.num("mass_shatter", 0.2)])
		_roll_drops(ed, ev, float(a.get("ks", 1.0)))
	en.order = alive
	for ds in dead:
		en.release(ds)
	# Broodsac: 6 designed swarmlings (their value is inside the Broodsac's share).
	var nc: int = TuneRef.int_of("mass_brood", 6)
	for p in splits:
		var sp: Vector2 = (p as Array)[0]
		for k in nc:
			if _spawn("mite", ev, sp + Vector2.from_angle(TAU * float(k) / float(nc)) * 9.0, false, 1.0, int((p as Array)[1]), int((p as Array)[2])):
				var cs: int = en.order[en.order.size() - 1]
				en.cash[cs] = 0.0
				en.xp[cs] = 0.0
		ev.append({"t": "split", "pos": sp, "n": nc})
	# Cryo freeze-shatter: a chilled body that dies hits its neighbours for 20% of its max HP.
	for sh in shatter:
		var c: Vector2 = (sh as Array)[0]
		var amt: float = float((sh as Array)[1])
		var hits: int = 0
		for fe in eh.candidates(c, 22.0):
			if en.hp[fe] > 0.0 and en.pos[fe].distance_to(c) <= 22.0:
				_hit(fe, amt, ev)
				hits += 1
				if hits >= 4:
					break
	for w2 in waves.keys():
		_mass_try_clear(int(w2), ev)


func _mass_sweep_loot(a: Dictionary) -> void:
	var l: float = float(a.get("loot", 0.0))
	if l > 0.0:
		coins_run += l
		horde_loot_total += l
		a["loot"] = 0.0


## Loot (REDESIGN §2.6) on the separate drop RNG: boss / elite / marked /
## Courier parts, boss Scrap, rare Keys.
func _roll_drops(ed: int, ev: Array, ks: float = -1.0) -> void:
	var kind: String = en.kind[ed]
	var src: String = "kill"
	if kind == "boss":
		src = "boss"
	elif kind == "courier":
		src = "courier"
		couriers_caught += 1
	elif kind == "elite" or en.is_marked(ed):
		src = "elite"
	var ctx: Dictionary = {"tier": tier, "drop_mult": 1.0 + float(ins.get("in_drop", 0.0)), "share": ks if ks >= 0.0 else en.share[ed]}
	var got: Array = Drops.add(loot, Drops.roll(drop_rng, src, ctx))
	for x in got:
		var d: Dictionary = (x as Dictionary).duplicate()
		d["t"] = "drop"
		d["pos"] = en.pos[ed]
		ev.append(d)


## SPEC B3: boss kill pays a coin bounty (gems removed, owner feedback #1).
func _boss_bounty(pos: Vector2, ev: Array) -> void:
	var c: int = int(floor(TuneRef.num("boss_bounty_base", 25.0) * float(wave) / 10.0 * coin_mult))
	coins_run += float(c)
	coins_boss += float(c)
	ev.append({"t": "boss_bounty", "coins": c, "pos": pos})


func _check_queue(ev: Array) -> void:
	_check_mutation(ev)
	_check_level(ev)
	_check_draft(ev)
	_check_perk(ev)


func _busy() -> bool:
	return draft.size() > 0 or pending_place != "" or pending_upgrade != "" or perk_offer.size() > 0 or mutation_offer.size() > 0


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
	var copies: Dictionary = {}
	var free: bool = false
	var free_outer: bool = false
	for i in N:
		var id: String = id_at(i)
		if id != "":
			owned[id] = mini(int(owned.get(id, 99)), lvl_at(i))
			copies[id] = int(copies.get(id, 0)) + 1
		elif is_free(i):
			free = true
			if ring_of(i) >= 3:
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
		"owned": owned, "copies": copies, "free": free and not at_cap(), "free_outer": free_outer and not at_cap(), "huts": hut_count(),
		"hut_max": PickDB.HUT_MAX + int(pf("hut_max")),
		"packs": packs, "specials": sp, "banished": banished, "luck": luck,
		"eco_mult": 1.0,
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
			ev.append({"t": "place_mode", "id": id, "dup": bool(card.get("dup", false))})
			ev.append({"t": "pick_applied", "id": id, "fam": String(card["fam"]), "kind": kind, "rarity": String(card["rarity"]), "reward": "building"})
			return ev
		"plus":
			# Owner feedback #1: an upgrade is applied by clicking / dragging it
			# onto the building (apply_upgrade), never silently.
			var cand: Array = upgrade_targets(id)
			if not cand.is_empty():
				pending_upgrade = id
				ev.append({"t": "upgrade_mode", "id": id, "slots": cand})
				ev.append({"t": "pick_applied", "id": id, "fam": String(card["fam"]), "kind": kind, "rarity": String(card["rarity"]), "reward": "upgrade"})
				return ev
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
	ev.append({"t": "pick_applied", "id": id, "fam": String(card["fam"]), "kind": kind, "rarity": String(card["rarity"]), "reward": Draft.reward_of(kind)})
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


## Cells holding `id` below the level cap (targets of a pending upgrade).
func upgrade_targets(id: String) -> Array:
	var out: Array = []
	for i in N:
		if id_at(i) == id and lvl_at(i) < mini(lvl_cap(), PickDB.max_of(id)):
			out.append(i)
	return out


## Apply the pending upgrade onto the building on cell i (click / drag-drop).
func apply_upgrade(i: int) -> Array:
	var ev: Array = []
	if pending_upgrade == "" or i < 0 or i >= N or not upgrade_targets(pending_upgrade).has(i):
		return ev
	var id: String = pending_upgrade
	pending_upgrade = ""
	var s: Dictionary = slots[i]
	s["run"] = mini(lvl_cap(), int(s["run"]) + 1)
	recompute()
	ev.append({"t": "building_level", "slot": i, "id": id, "level": lvl_at(i)})
	ev.append({"t": "upgraded", "slot": i, "level": lvl_at(i)})
	_drain_troop_events(ev)
	_check_queue(ev)
	return ev


## Drop a pending upgrade (Esc / its building was destroyed).
func cancel_upgrade() -> Array:
	if pending_upgrade == "":
		return []
	var id: String = pending_upgrade
	pending_upgrade = ""
	var ev: Array = [{"t": "upgrade_cancelled", "id": id}]
	_check_queue(ev)
	return ev


## Everything that buffs the run without a building (owner feedback #1: the
## left "Perks" list): upgrade packs, gold perks and Insight found.
func perk_list() -> Array:
	var out: Array = []
	for id in packs.keys():
		out.append({"id": String(id), "kind": "pack", "n": int(packs[id]), "name": String(PickDB.get_def(String(id)).get("name", id)), "desc": String(PickDB.get_def(String(id)).get("desc", ""))})
	for id in perks_taken:
		var d: Dictionary = PerkDB.get_def(String(id))
		out.append({"id": String(id), "kind": "gold", "n": 1, "name": String(d.get("name", id)), "desc": String(d.get("desc", ""))})
	for id in insight_found:
		out.append({"id": String(id), "kind": "insight", "n": 1, "name": String(PickDB.get_def(String(id)).get("name", id)), "desc": String(PickDB.get_def(String(id)).get("desc", ""))})
	return out


## Drop a pending placement (no legal cell / player cancels with Esc).
func cancel_place() -> Array:
	if pending_place == "":
		return []
	var id: String = pending_place
	pending_place = ""
	var ev: Array = [{"t": "place_cancelled", "id": id}]
	_check_queue(ev)
	return ev


## Buy one level of a Core cash track (REDESIGN §2.2, owner feedback #1:
## few, big, expensive levels with a drawback each).
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
	return ev


## Legacy view hook: the Core cell buys the Damage track; buildings level only
## through duplicate draft picks now.
func upgrade(i: int) -> Array:
	if i == CORE_SLOT:
		return buy_track("dmg")
	return []


## The grid size is a Research unlock (no per-cell cash unlocks in a run).
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
	for e in en.order:
		if en.hp[e] > 0.0:
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
			for ed in en.order:
				en.apply_slow(ed, float(fx["dur"]), 1.0 - float(fx["slow"]))
				en.shield[ed] = 0
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


## Centre of the enemy with the most neighbours within r (ties: the closest
## to the Core) — deterministic Orbital auto-aim.
func _densest(r: float) -> Vector2:
	return eh.densest(r)   # C# HordeWorld.Densest (exact neighbour counts via its hash)


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
	if String(core_w.get("attack", "cannon")) != "beam":
		targets *= float(MASS_CROWD["core"])   # overkill smash + splash into a packed crowd
	var blds: Array = []
	for w in ws:
		var wd: Dictionary = w
		if int(wd["slot"]) == CORE_SLOT:
			continue
		# MASS_HORDE §D4 crowd factors: bodies a hit is worth against the horde
		# at in-game density (about a third of the dense-field H8 probe).
		var mult: float = float(MASS_CROWD.get(String(wd["kind"]), 1.0))
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
		"crit": minf(1.0, float(stats.get("crit", 0.0)) + float(core_w.get("crit", 0.0))), "crit_mult": TuneRef.num("pc_crit_mult", 2.0),
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
	if paused or en.is_empty():
		return 0
	var f: float = TuneRef.num("pc_move_cost_frac", 0.1)
	return int(ceil(f * float(building_value(a) + building_value(b))))


func move_building(a: int, b: int, paused: bool = false) -> Array:
	if over or a == b or a < 0 or b < 0 or a >= N or b >= N or a == CORE_SLOT or b == CORE_SLOT:
		return []
	var ida: String = id_at(a)
	var idb: String = id_at(b)
	if ida == "" or not bool(unlocked[b]) or not ring_ok(b, ida):
		return []
	if idb != "" and not ring_ok(a, idb):
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
