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
const LootDB := preload("res://data/LootDB.gd")
const PowerModel := preload("res://PowerModel.gd")
const EnemyStore := preload("res://EnemyStore.gd")
const EnemyHash := preload("res://EnemyHash.gd")
const WeaponDB := preload("res://data/WeaponDB.gd")
const MergeDB := preload("res://data/MergeDB.gd")
const TrackDB := preload("res://data/TrackDB.gd")
const DirectiveDB := preload("res://data/DirectiveDB.gd")
const EvoDB := preload("res://data/EvoDB.gd")
const SupportDB := preload("res://data/SupportDB.gd")
const FirePatterns := preload("res://FirePatterns.gd")
const Gear := preload("res://Gear.gd")
const Parts := preload("res://Parts.gd")

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
## Core cash tracks: cost(next) = base * growth^lvl (Tune keys
## pc_track_growth_<id> / pc_track_cap_<id> override).
## V2 P7b: Core Enhancements are TrackDB's three trees (Attack / Defense /
## Economy); the five V1 tracks (dmg rate range eco armor) are its Overdrive
## tracks with the big trade-offs below. Standard tracks feed `tfx` (pf).
const TRACK_IDS: Array = TrackDB.IDS
const TRACKS: Dictionary = TrackDB.DEFS
## V2 P7a: a gold perk offer every GOLD_EVERY XP levels.
const GOLD_EVERY: int = 5
## V2 P7c kill-streak combo: the meter adds every kill and decays with time
## constant COMBO_TAU (a steady R kills/s holds it near R x TAU); tiers
## [meter, cash + XP multiplier].
const COMBO_TAU: float = 2.5
const COMBO_TIERS: Array = [[20.0, 1.10], [100.0, 1.25], [400.0, 1.50], [1500.0, 2.0]]
## V2 P7c Supply Drop: a 3-reel slot spin every SUPPLY_EVERY waves (its own
## seeded stream). Symbols [id, weight]; 1 / 2 / 3 of a kind pay x1 / x3 / x8.
const SUPPLY_EVERY: int = 7
const SUPPLY_SYMS: Array = [["cash", 30.0], ["xp", 25.0], ["reroll", 15.0], ["card", 12.0], ["cache", 10.0], ["star", 8.0]]
const SUPPLY_PAY: Array = [0, 1, 3, 8]
## V2 P7c: draft cards the player may lock (kept by rerolls, carried over).
const MAX_LOCKS: int = 2
## Per-level track multipliers (gain / drawback).
const DIFF_HP: float = 2.5
## V2 P9 balance: 1.5 -> 0.9. With the Core the only thing bodies can hit
## (no building HP) and directional boards, 1.5 ended fresh runs at wave ~9
## (~225 s); the first-run gate wants 300-480 s.
const DIFF_DMG: float = 0.9
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


## Building / hut tier ceiling in a run (V2 P7a: merges, T3).
static func lvl_cap() -> int:
	return MergeDB.MAX_TIER


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
var loot_rng: RandomNumberGenerator = RandomNumberGenerator.new()   # V2 P5 item / cache tokens: never perturbs the run
var wave_items: Dictionary = {}   # wave -> item tokens dropped (LootDB.wave_cap)
var draft_rng: RandomNumberGenerator = RandomNumberGenerator.new()  # drafts / perks / mutations
var combat_rng: RandomNumberGenerator = RandomNumberGenerator.new() # crits / wave skip
var horde_rng: RandomNumberGenerator = RandomNumberGenerator.new()  # FB1 per-body horde loot (own stream)
var horde_loot_wave_val: float = 0.0
var horde_loot_total: float = 0.0
const HORDE_LOOT_FUND := 0.35     # FB2: share of each horde body's kill coins moved into the loot pool
# Separate streams keep the wave sequence identical whatever the player picks
# or shoots, so two policies on one seed face the same waves.
var save: Dictionary = {}
var slots: Array = []        # N x ({} | {id, tier, rot, mods: [[tier, k]]}) (V2 P7a merge tiers)
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
var pending_rot: int = -1          # V2 P3c: facing chosen for the pick being placed (-1 = away from the Core)
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
var merges: int = 0                # merges this run (stats)
# V2 P7c
var directives: Array = []         # Directives taken (boss rewards)
var directive_offer: Array = []    # open Directive pick (3 ids)
var directive_pending: int = 0
var rfx: Dictionary = {}           # run fx: Directives + gold perks + stat packs (read through pf; _refresh_rfx)
var sfx: Dictionary = {}           # V2 P7d: SupportDB "core" fx of the support buildings (compute_stats)
var supply_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var supply_last: Dictionary = {}   # the last Supply Drop (view)
var supply_n: int = 0
var combo: float = 0.0             # kill-streak meter
var combo_tier: int = 0
var carry_cards: Array = []        # locked draft cards carried to the next hand ([{card, at}])
var evo_done: Dictionary = {}      # anchor -> true once its evolution was offered
var beam_ramps: Dictionary = {}    # V2 P7d: Laser Lance ramp per anchor (x1 -> x3)
var merge_offer: Dictionary = {}  # V2 P7a: {slot, tier, mods: [...]} the mod pick a merge opened
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
## V2 P10 (owner playtest 2: "enemies stack infinitely and my tower won't
## die"): Core regen while under fire, armor's floor and the DR cap.
const REGEN_UNDER_FIRE: float = 0.25
const ARMOR_FLOOR: float = 0.6     # armor removes at most 40% of a hit (was 75%)
const DR_CAP: float = 0.4          # was 0.6

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
var pfx: Dictionary = {}          # summed gear fx (V2 P4: Gear.run_fx of the save's loadout)
var tfx: Dictionary = {}          # V2 P7b: Core Enhancement fx (TrackDB steps x levels)
## V2 P4 manual aim: while the player holds fire on a point, the Core's Weapon
## takes the body nearest the cursor (within AIM_R, in range) with +15% crit,
## and a focus meter fills over 4 s to +30% damage (drains when released).
## The bots never aim (auto-fire).
const AIM_R: float = 39.0           # 1.5 cells around the cursor
const AIM_CRIT: float = 0.15
const AIM_FOCUS: float = 0.30
const FOCUS_UP_S: float = 4.0
const FOCUS_DOWN_S: float = 1.5
var aim_on: bool = false
var aim_pos: Vector2 = Vector2.ZERO
var focus: float = 0.0
var core_aim_dir: Vector2 = Vector2.UP   # view only: where the turret last fired (never hashed)
## V2 P9 Core threat priority (auto fire, first volley): an Elite or Boss
## gnawing on the Core comes first; else every other volley takes the nearest
## Spitter in range. Spitters stand off at ranged_stop and outlast a Core that
## only shoots the nearest melee body, and an Elite at the Core outlived a
## wave of it (a fresh run died at wave 7). Threat eids are rescanned every
## THREAT_SCAN volleys; manual aim overrides all of it.
const THREAT_SCAN: int = 4
## V3 parts: extra barrels (Legendary+ Receivers) fire on their own
## cooldowns; barrel k of n covers the sector centred TAU*k/n from barrel 0's
## aim (+-PI/n), so two barrels fire both ways, three at 120 deg.
var barrel_cd: Array = [0.0, 0.0, 0.0, 0.0]
var _sector_k: int = 0
var _sector_n: int = 1
var thr_flip: bool = false
var thr_n: int = 0
var thr_boss: Array = []
var thr_spit: Array = []
## Gear on-hit fx of the Core's own hits (compute_stats): burn dps share,
## slow, execute threshold; _core_hook is false for a quirk-free loadout.
var core_burn: float = 0.0
var core_slow: float = 0.0
var core_exec: float = 0.0
var _core_hook: bool = false
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
var rerolls_left: int = 0         # banked free rerolls (labs, cards)
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
var xp_base: float = 4.0   # V2 P9 balance (was 6): first drafts come sooner
var xp_growth: float = 1.25   # V2 P10 (owner: "reduce total drafts"): was 1.18


## opts (PC): {mode: "normal"|"endless", modifiers: [ModifierDB ids], core: id}.
func setup(seed_value: int, save_data: Dictionary, now: int = 0, opts: Dictionary = {}) -> Array:
	rng.seed = seed_value
	drop_rng.seed = seed_value ^ 0x5EED_D20B
	draft_rng.seed = seed_value ^ 0x0D2A_F7C3
	combat_rng.seed = seed_value ^ 0x00C0_BA75
	loot_rng.seed = seed_value ^ 0x1007_CA5E
	horde_rng.seed = seed_value ^ 0x40AD_1007
	supply_rng.seed = seed_value ^ 0x5A99_17D0
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
		for k in ["lab_fx", "lab_enemy"]:
			rm[k] = {}
		for k in ["lab_aim", "lab_bounty", "lab_items"]:
			rm[k] = 0.0
		for k in ["lab_locks", "lab_choices"]:
			rm[k] = 0
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
	# Core (V2: one Core) at its permanent level, firing the equipped Weapon
	# frame; gear fx (the Weapon + socketed Modules) land in pfx.
	core_id = CoreDB.ID
	core_def = Parts.core_def(save)
	core_lvl = Cores.level(save)
	pfx = Parts.run_fx(save)
	# V2 P6 Core buildings + V2 P8 research fx
	for src in [mods.get("outpost_fx", {}), mods.get("lab_fx", {})]:
		for k in (src as Dictionary).keys():
			pfx[k] = float(pfx.get(k, 0.0)) + float((src as Dictionary)[k])
	coin_mult *= maxf(0.1, 1.0 + pf("coin_run"))
	# V2 P10 eco ramp: run cash starts lean (mass_cash_unit 0.65) and the meta
	# - Outpost Treasuries, Field Economics research - multiplies all of it.
	cash_mult *= maxf(0.1, 1.0 + pf("run_cash"))
	aim_on = false
	aim_pos = CENTER
	focus = 0.0
	thr_flip = false
	thr_n = 0
	barrel_cd = [0.0, 0.0, 0.0, 0.0]
	thr_boss = []
	thr_spit = []
	mods["special_dmg"] = float(mods.get("special_dmg", 1.0)) * maxf(0.1, 1.0 + pf("special_dmg"))
	mods["special_cd"] = float(mods.get("special_cd", 1.0)) * maxf(0.2, 1.0 + pf("special_cd"))
	last_stand_used = false
	immune_t = 0.0
	interest_t = 0.0
	core_shots = 0
	var head: int = _reforge_node("head_start")
	tracks = {}
	for t in TRACK_IDS:
		tracks[t] = mini(head, track_cap(t)) if TrackDB.is_od(String(t)) else 0
	tfx = TrackDB.fx_of(tracks)
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
	merge_offer = {}
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
	wave_items = {}
	banished = []
	banish_left = 1 + mini(2, _reforge_node("banish_plus")) + int(mods.get("banish", 0))
	free_reroll = true
	paid_rerolls = 0
	draft_queue = [""]   # V2 P7a: the opening draft
	draft_guarantee = ""
	merges = 0
	directives = []
	directive_offer = []
	directive_pending = 0
	rfx = {}
	sfx = {}
	supply_last = {}
	supply_n = 0
	combo = 0.0
	combo_tier = 0
	carry_cards = []
	evo_done = {}
	beam_ramps = {}
	buffs = {"overdrive_t": 0.0, "magnet_t": 0.0, "repair_t": 0.0, "repair_rate": 0.0, "warp_t": 0.0, "frenzy_t": 0.0}
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
	return float(pfx.get(k, 0.0)) + float(tfx.get(k, 0.0)) + float(rfx.get(k, 0.0)) + float(sfx.get(k, 0.0))


## Run-time extras only (enhancements + Directives): keys the setup reads once.
func xf(k: String) -> float:
	return float(tfx.get(k, 0.0)) + float(rfx.get(k, 0.0)) + float(sfx.get(k, 0.0))


## Re-sum the run fx (Directives + gold perks with fx + stat packs with fx).
func _refresh_rfx() -> void:
	rfx = DirectiveDB.fx_of(directives)
	for src in [Perks.fx_of(perks_taken), PickDB.pack_fx(packs)]:
		for k in (src as Dictionary).keys():
			rfx[k] = float(rfx.get(k, 0.0)) + float((src as Dictionary)[k])


## V2 P7b: the Core Enhancement part of pf alone.
func tf(k: String) -> float:
	return float(tfx.get(k, 0.0))


## Draft luck now: run luck + Draft Luck enhancements (cap 10).
func luck_now() -> int:
	return mini(10, luck + int(xf("draft_luck")) + int(float(pfx.get("draft_luck", 0.0))))


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
	# V2 P7c: Directive costs on the enemy side
	enemy_hp_mod *= DirectiveDB.enemy_mult(directives, "hp")
	count_mult *= DirectiveDB.enemy_mult(directives, "count")
	# V2 P8: enemy research (Weak Points, Blunting, Mire Field)
	var le: Dictionary = mods.get("lab_enemy", {})
	enemy_hp_mod *= 1.0 - clampf(float(le.get("hp", 0.0)), 0.0, 0.5)
	enemy_dmg_mod *= 1.0 - clampf(float(le.get("dmg", 0.0)), 0.0, 0.5)
	enemy_spd_mod *= 1.0 - clampf(float(le.get("spd", 0.0)), 0.0, 0.5)


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


## Merge tier of the building anchored at i (0 = empty).
func tier_at(i: int) -> int:
	var s: Dictionary = slots[i]
	if s.is_empty():
		return 0
	return clampi(int(s.get("tier", 1)), 1, lvl_cap())


## Stat multiplier of a tier: x pc_tier_mult (1.8) per tier past T1.
func tier_mult(i: int) -> float:
	return MergeDB.tier_mult(tier_at(i))


## Summed fx of the merge mods on the building at i.
func mod_fx(i: int) -> Dictionary:
	var s: Dictionary = slots[i]
	if s.is_empty():
		return {}
	var out: Dictionary = {} if (s.get("mods", []) as Array).is_empty() else MergeDB.fx_of(String(s["id"]), s["mods"])
	if bool(s.get("evo", false)) and EvoDB.has(String(s["id"])):
		var efx: Dictionary = EvoDB.get_def(String(s["id"]))["fx"]
		for k in efx.keys():
			out[k] = float(out.get(k, 0.0)) + float(efx[k])
	return out


## Display name of the building at i (an evolved weapon's evolution name).
func name_at(i: int) -> String:
	var id: String = id_at(i)
	if id == "":
		return ""
	if bool((slots[i] as Dictionary).get("evo", false)) and EvoDB.has(id):
		return String(EvoDB.get_def(id)["name"])
	return String(PickDB.get_def(id).get("name", id))


## Pattern level of a tier (the L1..L5 extras: T1 = 1, T2 = 3, T3 = 5).
func pattern_lvl(i: int) -> int:
	return 2 * tier_at(i) - 1


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


func hut_max() -> int:
	return PickDB.HUT_MAX + int(pf("hut_max"))


func at_cap() -> bool:
	return building_count() >= build_cap


## Can `id` go with its footprint anchored at cell i right now (every
## covered cell free, under the build cap, ring rule)?
func can_place(i: int, id: String) -> bool:
	if at_cap() or not ring_ok(i, id):
		return false
	if PickDB.fam_of(id) == "hut" and hut_count() >= hut_max():
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
	# V2 P7d: SupportDB "core" fx first - every pf() below reads them
	sfx = {}
	for i0 in N:
		var sid0: String = id_at(i0)
		if sid0 == "" or not SupportDB.has(sid0):
			continue
		var core0: Dictionary = SupportDB.get_def(sid0).get("core", {})
		if core0.is_empty():
			continue
		var pm0: float = tier_mult(i0) * (1.0 + float(mod_fx(i0).get("power", 0.0)))
		for k0 in core0.keys():
			sfx[k0] = float(sfx.get(k0, 0.0)) + float(core0[k0]) * pm0
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
	var adj_crit: Array = []
	for i in N:
		adj_dmg.append(1.0)
		adj_rate.append(1.0)
		adj_range.append(0.0)
		adj_crit.append(0.0)
	# V2 P7a: tier x merge mods per building (bfx: slot -> mod fx)
	var bfx: Dictionary = {}
	for i in N:
		if id_at(i) != "":
			var fx0: Dictionary = mod_fx(i)
			if not fx0.is_empty():
				bfx[i] = fx0
	st["bfx"] = bfx
	for i in N:
		var sid: String = id_at(i)
		if sid == "":
			continue
		var fx: Dictionary = bfx.get(i, {})
		var m: float = tier_mult(i) * (1.0 + float(fx.get("power", 0.0)))
		match sid:
			"armory":
				var ar: int = int(fx.get("reach", 0.0))
				for n in (adjacent(i) if ar <= 0 else _near_anchors(i, 1 + ar)):
					adj_dmg[n] = float(adj_dmg[n]) + 0.15 * m
					adj_crit[n] = float(adj_crit[n]) + float(fx.get("crit", 0.0))
					links.append([i, n, "ARM"])
			"beacon":
				# V2 P3b: radius 4 small cells (the old 2 x 52 px)
				var br: int = 4 + int(fx.get("reach", 0.0))
				for n in N:
					if n != i and (id_at(n) != "" or n == CORE_SLOT) and fp_dist(i, n) <= br:
						adj_rate[n] = float(adj_rate[n]) + 0.10 * m * (1.0 + float(fx.get("rate", 0.0)))
						adj_range[n] = float(adj_range[n]) + 0.3 * m
						links.append([i, n, "BEA"])
			"hut_engineer":
				for n in adjacent(i):
					if n != CORE_SLOT:
						adj_rate[n] = float(adj_rate[n]) + 0.10 * m
						links.append([i, n, "ENG"])
			"oilmill":
				for n in adjacent(i):
					if n != CORE_SLOT:
						if fx.get("quiet", 0.0) <= 0.0:
							adj_rate[n] = float(adj_rate[n]) - 0.10
						adj_dmg[n] = float(adj_dmg[n]) + float(fx.get("adj_dmg", 0.0))
						links.append([i, n, "OIL"])
	# V2 P7d: SupportDB auras (tier x power; mods add reach)
	for i in N:
		var aid: String = id_at(i)
		if aid == "" or not SupportDB.has(aid) or not SupportDB.get_def(aid).has("aura"):
			continue
		var au: Dictionary = SupportDB.get_def(aid)["aura"]
		var afx: Dictionary = bfx.get(i, {})
		var am: float = tier_mult(i) * (1.0 + float(afx.get("power", 0.0)))
		var ar2: int = int(au["r"]) + int(afx.get("reach", 0.0))
		for n in (adjacent(i) if ar2 <= 1 else _near_anchors(i, ar2)):
			var af: Dictionary = au["fx"]
			adj_dmg[n] = float(adj_dmg[n]) + float(af.get("dmg", 0.0)) * am
			adj_rate[n] = float(adj_rate[n]) + float(af.get("rate", 0.0)) * am
			adj_range[n] = float(adj_range[n]) + float(af.get("range", 0.0)) * am
			adj_crit[n] = float(adj_crit[n]) + float(af.get("crit", 0.0)) * am
			links.append([i, n, "AUR"])
	# Core attack range (cells).
	var core_range_c: float = maxf(1.0, float(cd["range"]) + TRACK_RANGE * float(tracks["range"]) + range_add + float(adj_range[CORE_SLOT]) + pf("range"))
	var core_range: float = core_range_c * px
	var weapons: Array = st["weapons"]
	var rr: float = TuneRef.num("pc_ring_range", 0.08)
	var hp_add: float = 0.0
	var cash_add: float = 0.0
	var hut_regen: float = 0.0
	for i in N:
		var id: String = id_at(i)
		if id == "":
			continue
		var fx2: Dictionary = bfx.get(i, {})
		var m2: float = tier_mult(i) * (1.0 + float(fx2.get("power", 0.0)))
		# +pc_ring_range per old 52 px ring past the first (2 small rings each)
		var ring_m: float = 1.0 + rr * 0.5 * float(maxi(0, ring_at(i) - 1))
		var rate_m: float = rate_all * float(adj_rate[i]) * maxf(0.1, 1.0 + pf("bld_rate"))
		var dm: float = dmg_all * float(adj_dmg[i]) * bld_dmg() * maxf(0.1, 1.0 + pf("bld_dmg"))
		var rng_c: float = float(adj_range[i]) + range_add
		if SupportDB.has(id):
			# V2 P7d generic support: auras were applied above, core fx in sfx
			cash_add += float(SupportDB.get_def(id).get("cash", 0.0)) * m2
			continue
		if WeaponDB.has(id):
			var ws: Dictionary = _weapon_sheet(i, id, tier_mult(i), dm, rate_m, rng_c, ring_m, px)
			_apply_merge_mods(ws, fx2, px)
			ws["crit"] = float(ws.get("crit", 0.0)) + float(adj_crit[i])
			weapons.append(ws)
			continue
		match id:
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
				cash_add += 0.5 * m2 * (1.0 + float(fx2.get("cash", 0.0)))
				st["xp_mult"] = float(st["xp_mult"]) + 0.15 * m2
			"bounty":
				(st["bounties"] as Array).append({"slot": i, "pos": fp_pos(i), "r": (3.0 + float(fx2.get("reach", 0.0))) * px, "mult": 0.20 * m2})
			"vault":
				st["interest_rate"] = float(st["interest_rate"]) + 0.02 * m2
				st["interest_cap"] = float(st["interest_cap"]) + 100.0 * tier_mult(i) * (1.0 + float(fx2.get("cap", 0.0)))
			"obelisk":
				st["lifesteal"] = float(st["lifesteal"]) + 0.01 * m2
			"hut_infantry", "hut_sapper", "hut_sniper", "hut_guard", "hut_medic", "hut_engineer":
				if id == "hut_medic":
					hut_regen += 1.5 * m2
				var dir: Vector2 = (fp_pos(i) - CENTER).normalized()
				var post: Vector2 = CENTER + dir * (grid_half_px() + 0.6 * px)
				var hut: Dictionary = {"slot": i, "id": id, "lvl": pattern_lvl(i), "home": fp_pos(i), "anchor": post,
					"dmg_m": (1.0 + float(fx2.get("power", 0.0))) * (1.0 + float(fx2.get("troop_dmg", 0.0))),
					"hp_m": (1.0 + float(fx2.get("power", 0.0))) * (1.0 + float(fx2.get("troop_hp", 0.0)))}
				if id == "hut_infantry" and crowd():
					# FB2 Rifle Barracks (omnidirectional): riflemen guard the whole
					# perimeter - seek/leash around the Core, idle at their post.
					var gh: float = grid_half_px() / px
					hut["anchor"] = CENTER
					hut["post"] = post
					hut["seek"] = gh + TuneRef.num("pc_rifle_seek", 3.0)
					hut["leash"] = gh + TuneRef.num("pc_rifle_leash", 4.5)
				(st["huts"] as Array).append(hut)
	# V2 P7a: merge mods that feed the Core / economy (armor, regen, kill
	# cash, XP, interest, flat cash/s on non-refinery buildings)
	var mod_armor: float = 0.0
	var mod_regen: float = 0.0
	for k in bfx.keys():
		var f3: Dictionary = bfx[k]
		mod_armor += float(f3.get("armor", 0.0))
		mod_regen += float(f3.get("regen", 0.0))
		st["kill_cash_mod"] = float(st.get("kill_cash_mod", 0.0)) + float(f3.get("kill_cash", 0.0))
		st["xp_mult"] = float(st["xp_mult"]) + float(f3.get("xp", 0.0))
		st["interest_rate"] = float(st["interest_rate"]) + float(f3.get("interest", 0.0))
		if id_at(int(k)) == "vault":
			cash_add += float(f3.get("cash", 0.0))
	# Core sheet with tracks, packs, legacy core levels, Insight.
	var arm_n: int = tracks["armor"]
	st["max_hp"] = (float(st["max_hp"]) + hp_add) * (1.0 + TRACK_ARMOR_HP * float(arm_n)) * pow(TRACK_ECO_HP, float(tracks["eco"])) * (1.0 + 0.20 * float(pack_n("pk_fort"))) * maxf(0.5, 1.0 - 0.05 * float(pack_n("pk_overclock"))) * max_hp_mult * (1.0 + float(ins.get("in_hp", 0.0))) * maxf(0.1, 1.0 + pf("core_hp"))
	st["regen"] = (float(st["regen"]) + 1.0 * float(arm_n) + mod_regen + hut_regen) * maxf(0.0, 1.0 + pf("regen"))
	st["armor"] = float(st["armor"]) + 2.0 * float(arm_n) + float(pack_n("pk_fort")) + pf("armor") + mod_armor
	var eco_lv: int = tracks["eco"]
	var cash_w1: float = maxf(0.0, float(st["cash_ps"]) + TRACK_ECO_CASH * float(eco_lv) + 0.6 * float(pack_n("pk_ledger")) + cash_add + pf("cash_flat"))
	st["cash_ps"] = cash_w1 * e * cash_mult * (1.0 + float(ins.get("in_cash", 0.0))) * maxf(0.1, 1.0 + pf("cash"))
	st["kill_cash"] = (1.0 + 0.05 * float(pack_n("pk_ledger")) + float(st.get("kill_cash_mod", 0.0))) * (1.0 + float(ins.get("in_cash", 0.0))) * maxf(0.1, 1.0 + pf("kill_cash"))
	st["interest_rate"] = float(st["interest_rate"]) + pf("interest")
	var icap_w1: float = float(st["interest_cap"]) + TRACK_ECO_ICAP * float(eco_lv) + (50.0 if pf("interest") > 0.0 else 0.0)
	st["interest_cap"] = icap_w1 * e * maxf(0.1, 1.0 + pf("icap"))
	# The Core's own weapon: V3 parts - one entry per installed barrel (each
	# with its own attack sheet, cooldown and sector; barrel 0 is the main
	# one). Barrels are appended last to first, so barrel 0 is always last in
	# `weapons` (views and tests read .back()).
	var bsheets: Array = cd.get("barrels", [cd]) if cd.get("barrels", []) is Array and not (cd.get("barrels", []) as Array).is_empty() else [cd]
	for bk in range(bsheets.size() - 1, -1, -1):
		var bcd: Dictionary = bsheets[bk]
		var b_range_c: float = maxf(1.0, core_range_c - float(cd["range"]) + float(bcd["range"]))
		core_range = b_range_c * px
		var core_dmg: float = float(bcd["dmg"]) * CoreDB.lvl_mult("dmg", L) * dmg_all * float(adj_dmg[CORE_SLOT]) * (1.0 + TuneRef.num("pc_core_surge_dmg", 0.15) * float(pack_n("pk_core"))) * maxf(0.1, 1.0 + pf("core_dmg")) * pow(TRACK_RATE_DMG, float(tracks["rate"])) * pow(TRACK_ARMOR_DMG, float(arm_n))
		var core_rate: float = float(bcd["rate"]) * pow(TRACK_RATE, float(tracks["rate"])) * pow(TRACK_DMG_RATE, float(tracks["dmg"])) * pow(TRACK_RANGE_RATE, float(tracks["range"])) * rate_all * float(adj_rate[CORE_SLOT]) * (1.0 + TuneRef.num("pc_core_surge_rate", 0.05) * float(pack_n("pk_core"))) * maxf(0.1, 1.0 + pf("rate"))
		var cw: Dictionary = {"slot": CORE_SLOT, "kind": "core", "attack": String(bcd["attack"]), "dmg": core_dmg, "rate": core_rate, "range": core_range, "range_cells": b_range_c, "barrel": bk, "nbarrels": bsheets.size()}
		# Parts on the Core attack: primary-target mult, splash, pierce, free pulse.
		cw["single_mult"] = maxf(0.1, 1.0 + pf("core_single"))
		cw["pierce"] = int(pf("pierce"))
		cw["storm_pulse"] = int(pf("storm_pulse"))
		cw["pulse_mult"] = 1.0 + pf("pulse_dmg")
		var nosplash: bool = pf("nosplash") > 0.0
		match String(bcd["attack"]):
			"minigun":
				cw["spread"] = int(bcd.get("spread", 3))
			"cannon":
				cw["splash"] = 0.0 if nosplash else (float(bcd["splash"]) + pf("splash")) * px
				cw["splash_frac"] = float(bcd["splash_frac"])
				cw["barrels"] = int(bcd.get("barrels", 1)) + (1 if L >= 20 else 0)
			"slag":
				cw["splash"] = (0.25 if nosplash else (float(bcd["splash"]) + pf("splash"))) * px * (1.5 if L >= 20 else 1.0)
				cw["slow"] = float(bcd["slow"])
				cw["slow_t"] = float(bcd["slow_t"])
			"beam":
				cw["ramp"] = float(bcd["ramp"]) * (1.0 + pf("beam_ramp"))
				cw["ramp_max"] = 2.0 if L >= 20 else float(bcd["ramp_max"])
				cw["boss_mult"] = 1.0
				cw["retarget"] = maxf(0.0, pf("retarget"))
			"pulse":
				cw["rings"] = (2 if L >= 20 else 1) + int(pf("chain"))
				cw["knock"] = float(bcd["knock"])
				cw["chain_every"] = int(bcd["chain_every"])
				cw["chain_frac"] = float(bcd.get("chain_frac", 0.4)) * (1.0 + pf("chain_dmg"))
				cw["chain_n"] = int(bcd["chain_n"])
			"scatter":
				cw["pellets"] = int(bcd.get("pellets", 6)) + (2 if L >= 20 else 0)
				cw["cone"] = float(bcd.get("cone", 40.0))
			"rail":
				cw["rail_n"] = int(bcd.get("pierce", 10)) + int(pf("pierce")) + (4 if L >= 20 else 0)
			"arc":
				cw["chain_n"] = mini(TuneRef.int_of("mass_chain_cap", 20), int(bcd.get("chain", 5)) + int(pf("chain")) + (2 if L >= 20 else 0))
				cw["chain_frac"] = minf(0.95, float(bcd.get("chain_frac", 0.8)) * (1.0 + pf("chain_dmg")))
				cw["jump"] = float(bcd.get("jump", 70.0))
			"flame":
				cw["cone"] = float(bcd.get("cone", 50.0)) + (10.0 if L >= 20 else 0.0)
				cw["flame_burn"] = float(bcd.get("flame_burn", TuneRef.num("gear_flame_burn", 0.5)))
			"missiles":
				cw["missiles"] = int(bcd.get("missiles", 4)) + (1 if L >= 20 else 0)
				cw["splash"] = 0.0 if nosplash else (float(bcd.get("splash", 0.3)) + pf("splash")) * px
			"saw":
				cw["bounces"] = int(bcd.get("bounces", 4)) + int(pf("bounce")) + (1 if L >= 20 else 0)
				cw["bounce_frac"] = float(bcd.get("bounce_frac", 0.85))
				cw["jump"] = float(bcd.get("jump", 90.0))
		# V2 P4 gear on the Weapon: extra volleys, echo, knockback, ricochet
		# (the Saw folds ricochet into its own bounces; the Pulse into its rings).
		cw["multishot"] = mini(4, int(pf("multishot")))
		cw["echo"] = clampf(pf("echo"), 0.0, 0.5)
		cw["knock_m"] = maxf(0.0, 1.0 + pf("knock"))
		cw["bounce"] = 0 if String(bcd["attack"]) == "saw" else mini(6, int(pf("bounce")))
		if String(bcd["attack"]) == "pulse":
			cw["rings"] = int(cw["rings"]) + int(cw["multishot"])
		weapons.append(cw)
	core_burn = maxf(0.0, pf("burn"))
	core_slow = clampf(pf("slow_hit"), 0.0, 0.6)
	core_exec = clampf(pf("execute"), 0.0, 0.25)
	_core_hook = core_burn > 0.0 or core_slow > 0.0 or core_exec > 0.0
	st["xp_mult"] = float(st["xp_mult"]) * xp_mod * maxf(0.1, 1.0 + pf("xp"))
	st["crit"] = float(st["crit"]) + pf("crit")
	st["crit_mult"] = TuneRef.num("pc_crit_mult", 2.0) + pf("crit_dmg")
	st["boss_mult"] = 1.0 + pf("boss")
	st["normal_mult"] = maxf(0.1, 1.0 + pf("normal_dmg"))
	st["reflect"] = pf("reflect")
	st["shred"] = pf("shred") + (TuneRef.num("gear_saw_shred", 0.04) if String(cd["attack"]) == "saw" else 0.0)
	# V2 P4 gear on the Core's body.
	st["shield_max"] = float(st["shield_max"]) + pf("shield")
	st["shield_regen"] = float(st["shield_regen"]) + 0.1 * pf("shield")
	st["lifesteal"] = float(st["lifesteal"]) + pf("lifesteal")
	st["dr"] = minf(DR_CAP, float(st["dr"]) + pf("dr"))
	# Perks (B7) multiply weapons / HP / regen / cash / XP.
	Perks.apply(st, perks_taken)
	st["cash_ps"] = float(st["cash_ps"]) * float(st["perk_cash"])
	# Display hooks the current view reads.
	st["overcharge_step"] = TuneRef.num("pc_track_dmg_step", TRACK_DMG) - 1.0
	st["overcharge"] = dmg_track
	st["bounty_mult"] = float(st["kill_cash"])
	return st


## V2 P3c: one weapon building's live sheet from WeaponDB - base numbers x
## level (m2) x damage / rate / range modifiers x its direction commitment
## (dir_mult), plus its aim (radial / arc / fixed), facing and pattern params.
func _weapon_sheet(i: int, id: String, m2: float, dm: float, rate_m: float, rng_c: float, ring_m: float, px: float) -> Dictionary:
	var d: Dictionary = WeaponDB.get_def(id)
	var p: Dictionary = d.get("p", {})
	var w: Dictionary = {"slot": i, "lvl": pattern_lvl(i), "tier": tier_at(i), "kind": id, "pattern": String(d["pattern"]), "aim": String(d["aim"]),
		"arc_cos": cos(deg_to_rad(float(d["arc"]) * 0.5)), "facing": WeaponDB.facing(rot_at(i)),
		"dmg": float(d["dmg"]) * m2 * dm * float(d["dir_mult"]), "rate": float(d["rate"]) * rate_m, "range": (float(d["range"]) + rng_c) * px * ring_m}
	match id:
		"mortar":
			w["splash"] = float(p["splash"]) * px
			w["min_range"] = float(p["min_range"]) * px
		"tesla":
			w["dmg"] = float(w["dmg"]) * (1.0 + pf("chain_dmg"))
			w["chains"] = int(p["chains"]) + int(pf("chain"))
			w["chain_frac"] = float(p["chain_frac"])
		"flak":
			w["rate"] = float(w["rate"]) * TuneRef.num("mass_flame_rate", 0.5)
		"railgun":
			w["pierce"] = float(p["pierce"])
		"frost":
			# an aura: fixed pulse rate, no ring reach bonus
			w["rate"] = float(d["rate"])
			w["range"] = (float(d["range"]) + rng_c) * px
			w["slow"] = float(p["slow"])
			w["slow_t"] = float(p["slow_t"])
		"spike", "pulse":
			# auras: no ring reach bonus
			w["range"] = (float(d["range"]) + rng_c) * px
	# V2 P7d: the newer weapons' pattern params ride on the sheet (blast in
	# cells -> px; lob_r stays in cells, the pattern scales it)
	for k in p.keys():
		if not w.has(k):
			w[k] = float(p[k]) * px if String(k) == "blast" else p[k]
	return w


## V2 P7a: a weapon's merge mods onto its sheet (MergeDB fx vocabulary).
func _apply_merge_mods(w: Dictionary, fx: Dictionary, px: float) -> void:
	if fx.is_empty():
		return
	w["dmg"] = float(w["dmg"]) * (1.0 + float(fx.get("dmg", 0.0)))
	w["rate"] = float(w["rate"]) * (1.0 + float(fx.get("rate", 0.0)))
	w["range"] = float(w["range"]) + float(fx.get("range", 0.0)) * px
	w["crit"] = float(w.get("crit", 0.0)) + float(fx.get("crit", 0.0))
	if fx.has("arc"):
		var d: Dictionary = WeaponDB.get_def(String(w["kind"]))
		w["arc_cos"] = cos(deg_to_rad(minf(359.0, float(d["arc"]) + float(fx["arc"])) * 0.5))
	for k in ["pierce", "chains", "arcs", "rounds", "boss", "missiles", "pellets", "bounces", "ramp", "elite"]:
		if fx.has(k):
			w[k + "_add"] = float(fx[k])
	for k2 in ["splash", "knock", "cone", "burn"]:
		if fx.has(k2):
			w[k2 + "_m"] = 1.0 + float(fx[k2])
	if fx.has("slow") and w.has("slow"):
		w["slow"] = minf(0.85, float(w["slow"]) + float(fx["slow"]))
	if w.has("pierce") and fx.has("pierce"):
		w["pierce"] = float(w["pierce"]) + float(fx["pierce"])


## Anchors whose footprints lie within `r` cells of the one at i.
func _near_anchors(i: int, r: int) -> Array:
	var out: Array = []
	for n in N:
		if n != i and (id_at(n) != "" or n == CORE_SLOT) and fp_dist(i, n) <= r:
			out.append(n)
	return out


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
	return coin_mult * float(stats.get("perk_coin", 1.0)) * mutation_coin() * (1.0 + xf("coin_run"))


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
	# V2 P10: regen stalls to REGEN_UNDER_FIRE while bodies are hitting the
	# Core (shield_idle < 1 s), so a pile that out-damages it always wins.
	var rg: float = float(stats["regen"]) * (TuneRef.num("regen_under_fire", REGEN_UNDER_FIRE) if shield_idle < 1.0 else 1.0)
	hp = minf(float(stats["max_hp"]), hp + (rg + float(buffs["repair_rate"]) * (1.0 if float(buffs["repair_t"]) > 0.0 else 0.0)) * dt)
	immune_t = maxf(0.0, immune_t - dt)
	if pf("interest_fast") > 0.0 and wave_started:
		interest_t += dt
		if interest_t >= 15.0:
			interest_t -= 15.0
			_pay_interest(ev)
	_tick_buffs(dt, ev)
	if combo > 0.0:
		combo *= exp(-dt / COMBO_TAU)
		if combo < 0.5:
			combo = 0.0
		_combo_check(ev)
	en.cc_scale = cc_crowd_scale()
	_move_enemies(dt, ev)
	_fire(dt, ev)
	_src = ""
	_blockable = false
	_wall_auras(dt, ev)
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
	for k in ["overdrive_t", "magnet_t", "repair_t", "warp_t", "frenzy_t"]:
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
		_src = String(od.get("src", "special"))
		_kb_k = 0.0
		_blockable = false
		var cap_n: int = en.hp.size()
		for s in eh.candidates(c, float(od["r"]) + en.max_size * 0.5):
			# the hash is from the last step: skip a slot the store no longer has
			if s < 0 or s >= cap_n:
				continue
			if en.hp[s] > 0.0 and en.pos[s].distance_to(c) <= float(od["r"]) + en.size[s] * 0.5:
				_hit(s, float(od["dmg"]), ev)
				n += 1
		_src = ""
		ev.append({"t": "orbital_hit", "pos": c, "r": float(od["r"]), "hits": n})
		# §D4 knockback special: the strike's shock wave parts the sea.
		var pushed: int = en.radial_knock(c, float(od["r"]) * 2.0, TuneRef.num("horde_knock", 60.0) * float(od.get("knock", TuneRef.num("mass_orbital_knock", 3.0))))
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
	if mode == "endless" and wave % ModifierDB.MUTATION_EVERY == 0:
		mutation_pending += 1


## V2 P7a: drafts come from XP level-ups (_check_level) and the opening
## draft. V2 P7c: a cleared boss wave offers a Directive instead.
func _queue_drafts(cleared: int) -> void:
	if cleared % boss_every == 0 and directives.size() < DirectiveDB.IDS.size():
		directive_pending += 1


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
	if wave % SUPPLY_EVERY == 0:
		_supply_drop(ev)
	_slot_spins(ev)
	_auto_buy(ev)
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
	loot["luck"] = luck + int(xf("loot_luck")) + int(float(pfx.get("loot_luck", 0.0)))   # V2 P5: bank-time rarity luck (the run never rolls it); P7b Loot Luck
	loot["tier"] = tier
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
	return wave_time / interval_for(w) * TuneRef.num("mass_cash_unit", 0.65)   # V2 P10: was 1.0 (eco too easy)


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
	a["xpool"] = mass_cash_pool(w) * TuneRef.num("mass_xp_unit", 1.0) / maxf(0.01, TuneRef.num("mass_cash_unit", 0.65))   # V2 P10: XP x0.8 (was 1.25), independent of the cash cut
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
	var coins: float = float(a["cclear"]) * kept * (1.0 + float(mods.get("lab_bounty", 0.0)))
	coins_run += coins
	coins_wave += coins
	_mass_sweep_loot(a)
	ev.append({"t": "wave_clear", "wave": w, "cash": cg, "coins": coins, "kept": kept, "kills": int(a["dead"]) - int(a["leak"]), "leaked": int(a["leak"])})
	# V2 P5: cleared waves drop caches (loot stream only)
	for x in Drops.add(loot, Drops.wave_clear(loot_rng, w, tier)):
		var dx: Dictionary = (x as Dictionary).duplicate()
		dx["t"] = "drop"
		dx["pos"] = CENTER
		ev.append(dx)
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
	var sc: float = pow(gr, float(ww - 1)) * TuneRef.num("mass_hp_k", 0.35)
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
## V2 P9 balance: mass_hp_k 0.5 -> 0.35 (a softer start: fresh runs reach
## wave ~16 in ~400 s) and mass_hp_track 1.006 -> 1.03 (a steeper climb:
## a meta-boosted run used to coast to wave 50 on day 2, the wall now
## moves with the meta instead).
static func mass_hp_growth(t: int) -> float:
	var g: float = TuneRef.num("mass_hp_g_f", 0.0)
	if g > 0.0:
		return g
	return PowerModel.hp_growth(t) / TuneRef.num("mass_b_growth", 1.11) * TuneRef.num("mass_hp_track", 1.03)


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
			en.dmg[e] *= TuneRef.num("mass_elite_dmg", 0.6)   # V2 P10: Elites walk straight to the Core now (no building ring)
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
			var ecut: float = clampf(float((mods.get("lab_enemy", {}) as Dictionary).get("elite", 0.0)), 0.0, 0.5)
			if ecut > 0.0:   # V2 P8 Elite Profiling
				en.hp[e] = en.hp[e] * (1.0 - ecut)
				en.max_hp[e] = en.hp[e]
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
	burning = PackedInt32Array()   # slot lists die with the store
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
	var real: float = maxf(amt * TuneRef.num("pc_armor_floor", ARMOR_FLOOR), amt - float(stats.get("armor", 0.0)) * share)   # flat armor split per horde body (owner C4)
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


## V2 P10 (owner playtest 2: "with enough targets, enemies are pretty much
## stun-locked"): knockback and slows fade with the crowd. Up to cc_full
## bodies alive they work in full; above it they are x(cc_full / alive)^cc_exp
## (never below cc_min): 200 alive ~x0.38, 1,000 ~x0.12, 5,000+ x0.05.
func cc_crowd_scale() -> float:
	var n: float = float(en.count())
	var full: float = TuneRef.num("cc_full", 50.0)
	if n <= full:
		return 1.0
	return clampf(pow(full / n, TuneRef.num("cc_exp", 0.7)), TuneRef.num("cc_min", 0.05), 1.0)


func _move_enemies(dt: float, ev: Array) -> void:
	var r_stop: float = TuneRef.num("ranged_stop", 230.0)
	var r_fire: float = TuneRef.num("ranged_fire", 2.0)
	var frozen: bool = float(buffs.get("warp_t", 0.0)) > 0.0
	# V2 P10 (owner playtest 2): bodies walk through buildings as if they were
	# not there - no routing around them and no squeeze slowdown - so the
	# occupancy mask handed to the C# step is always empty (the Core is never
	# a blocker either: its contact ring is STOP_R).
	var blk: PackedByteArray = PackedByteArray()
	blk.resize(N)
	# MASS_HORDE: the step runs in the C# HordeWorld (flow field, pressure,
	# knockback, contact). It returns an ordered action log of Core effects,
	# replayed in slot order; every attack lands on the Core.
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
				var bamt: float = en.dmg[e] * TuneRef.num("horde_sapper_core", 4.5) * (1.0 - clampf(float((mods.get("lab_enemy", {}) as Dictionary).get("sapper", 0.0)), 0.0, 0.6))
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
	if _core_hook and _src == "core" and core_exec > 0.0 and not BOSSY.has(en.kind[e]) and en.hp[e] - dmg < core_exec * en.max_hp[e]:
		dmg = maxf(dmg, en.hp[e])   # gear Executioner
	var was: float = en.hp[e]
	en.hp[e] = en.hp[e] - dmg
	if _core_hook and _src == "core" and en.hp[e] > 0.0:
		if core_slow > 0.0:
			en.apply_slow(e, 1.5, 1.0 - core_slow)
		if core_burn > 0.0:
			_ignite(e, TuneRef.num("mass_burn_s", 2.0), dmg * core_burn)
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
	if aim_on and int(wd.get("slot", -1)) == CORE_SLOT:
		c += AIM_CRIT
	return c > 0.0 and combat_rng.randf() < c


## Crit damage multiplier (pc_crit_mult 2.0 + gear crit damage).
func crit_mult() -> float:
	return float(stats.get("crit_mult", TuneRef.num("pc_crit_mult", 2.0)))


## V2 P4 manual aim (the view: hold LMB on the field, or the pad's right
## stick + RB). `firing` false releases it (auto-fire resumes).
func set_aim(pos: Vector2, firing: bool) -> void:
	aim_on = firing
	aim_pos = pos


## Wall (id "barricade"; omnidirectional): with spawns from every side there is
## no lane to wall off, so each Wall drags every body within its radius (-30%
## speed) on top of being a blocker the horde must flow around or squeeze
## through. Wall of Flesh: one Wall slows 2,000 distinct bodies in a wave.
func _wall_auras(dt: float, ev: Array) -> void:
	wall_tick += 1
	var r0: float = TuneRef.num("pc_wall_aura", 1.5)
	var s0: float = TuneRef.num("pc_wall_slow", 0.30)
	var bfx: Dictionary = stats.get("bfx", {})
	for i in slots.size():
		var wid: String = id_at(i)
		if wid != "barricade" and wid != "gate":
			continue
		# V2 P7a: tiers widen the aura (+0.25 cell) and deepen it (+5%); mods add
		# V2 P7d: the Spike Gate is a Wall with its own slow and built-in spikes
		var fx: Dictionary = bfx.get(i, {})
		var gw: Dictionary = SupportDB.get_def("gate").get("wall", {}) if wid == "gate" else {}
		var tn: float = float(tier_at(i) - 1)
		var r: float = (r0 + 0.25 * tn + float(fx.get("range", 0.0))) * cpx()
		var sm: float = 1.0 - minf(0.8, float(gw.get("slow", s0)) + 0.05 * tn + float(fx.get("slow", 0.0)))
		var c: Vector2 = fp_pos(i)
		var hit: PackedInt32Array = en.slow_radius(c, r, 0.2, sm)   # one C# call per Wall (P3d perf)
		var spike: float = (float(fx.get("dmg", 0.0)) + float(gw.get("dmg", 0.0)) * tier_mult(i)) * float(stats.get("dmg_all", 1.0)) * bld_dmg() * dt
		if spike > 0.0:
			_src = "barricade"
			for fe in hit:
				if en.hp[fe] > 0.0:
					_hit(fe, spike, ev)
			_src = ""
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
	if aim_on:
		focus = minf(1.0, focus + dt / FOCUS_UP_S)
	elif focus > 0.0:
		focus = maxf(0.0, focus - dt / FOCUS_DOWN_S)
	for w in stats["weapons"]:
		var wd: Dictionary = w
		var si: int = int(wd["slot"])
		var rate: float = float(wd["rate"])
		if si == CORE_SLOT and float(buffs.get("overdrive_t", 0.0)) > 0.0:
			rate *= 2.0
		elif si != CORE_SLOT and float(buffs.get("frenzy_t", 0.0)) > 0.0:
			rate *= float((Specials.FX["sp_frenzy"] as Dictionary)["rate"])   # V2 P7d Frenzy
		var bk: int = int(wd.get("barrel", 0)) if si == CORE_SLOT else 0
		var cd: float = (float(barrel_cd[bk]) if bk > 0 else float(cooldowns[si])) - dt
		if cd > 0.0:
			if bk > 0:
				barrel_cd[bk] = cd
			else:
				cooldowns[si] = cd
			if si == CORE_SLOT and bk == 0 and String(wd.get("attack", "")) == "beam":
				_beam_hold(wd, dt)
			continue
		_kb_k = 0.0
		_blockable = false
		if si == CORE_SLOT:
			_kb_k = float(KNOCK_W["core"]) * float(wd.get("knock_m", 1.0))
			_kb_from = CENTER
			_src = "core"
			_blockable = ["cannon", "beam", "scatter", "rail", "missiles", "saw"].has(String(wd.get("attack", "")))
			# Queen Engine: the Core holds fire while 3+ troops are alive.
			if pf("queen_hold") > 0.0 and Troops.alive_count(troops) >= 3:
				cooldowns[si] = 0.0
				continue
			_sector_k = bk
			_sector_n = int(wd.get("nbarrels", 1))
			var fired_c: bool = _core_fire(wd, ev)
			_sector_k = 0
			_sector_n = 1
			if bk > 0:
				barrel_cd[bk] = cd + 1.0 / rate if fired_c else 0.0
				continue
			if fired_c:
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
		var pattern: String = String(wd.get("pattern", "pierce_round"))
		if FirePatterns.AURAS.has(pattern):
			var hit_any: bool = FirePatterns.aura_slow(self, wd, from, ev) if pattern == "aura_slow" else FirePatterns.aura_hit(self, wd, from, ev)
			cooldowns[si] = (cd + 1.0 / rate) if hit_any else 0.0
			continue
		var tgt: int = -1
		if String(wd.get("aim", "radial")) == "fixed":
			# V2 P3c: a fixed weapon fires along its facing, only when a body
			# stands in its cone / lane.
			if not FirePatterns.shape_occupied(self, wd, from):
				cooldowns[si] = 0.0
				beam_ramps.erase(si)   # V2 P7d: an idle Laser Lance cools down
				continue
		else:
			tgt = pick_target_for(wd, from, String(target_modes[si]) if si < target_modes.size() else "nearest")
			if pattern == "lob_aoe" and tgt >= 0 and from.distance_to(en.pos[tgt]) < float(wd.get("min_range", 0.0)):
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
		var crit: bool = _roll_crit(wd)
		if crit:
			dmg *= crit_mult()
		FirePatterns.fire(self, pattern, wd, from, wd.get("facing", Vector2.UP), tgt, dmg, crit, ev)


## V2 P3c target choice: a radial weapon takes any body in range (by its
## targeting mode); an arc weapon only bodies within +-arc/2 of its facing.
func pick_target_for(wd: Dictionary, from: Vector2, mode_s: String) -> int:
	var rng_lim: float = float(wd["range"])
	if String(wd.get("aim", "radial")) != "arc":
		return pick_target(from, rng_lim, mode_s)
	var face: Vector2 = wd["facing"]
	var ac: float = float(wd["arc_cos"])
	if mode_s == "nearest":
		return eh.nearest_in_cone(from, face, acos(clampf(ac, -1.0, 1.0)), rng_lim)
	var best: int = -1
	var best_key: float = INF
	var best_d: float = INF
	for k in eh.cone(from, face, acos(clampf(ac, -1.0, 1.0)), rng_lim):
		var hpv: float = en.hp[k]
		if hpv <= 0.0:
			continue
		var p: Vector2 = en.pos[k]
		var d2: float = from.distance_squared_to(p)
		if d2 > rng_lim * rng_lim or not FirePatterns.in_arc(from, p, face, ac):
			continue
		var key: float = CENTER.distance_squared_to(p) if mode_s == "first" else (-hpv if mode_s == "strongest" else hpv)
		if key < best_key or (key == best_key and d2 < best_d):
			best_key = key
			best_d = d2
			best = k
	return best


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
		if b < 0 or b >= en.hp.size():
			continue   # a slot the store no longer has
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


## The Core's attack (REDESIGN §2.1; V2 P4: the equipped Weapon frame picks
## it). A shot is one volley, +1 per multishot at another target (the Pulse
## adds rings instead); an echo repeats the first volley. Emits
## core_attack{kind, targets} and `shot` events (kind "core") the view draws.
## Returns false when nothing is in range (the attack stays ready).
func _core_fire(wd: Dictionary, ev: Array) -> bool:
	var atk: String = String(wd.get("attack", "cannon"))
	var targets: Array = []
	var used: Dictionary = {}
	var vols: int = 1 if atk == "pulse" else 1 + int(wd.get("multishot", 0))
	var fired: bool = false
	for k in vols:
		if not _core_volley(atk, wd, ev, targets, used, k):
			break
		fired = true
	if not fired:
		return false
	if float(wd.get("echo", 0.0)) > 0.0 and combat_rng.randf() < float(wd["echo"]):
		_core_volley(atk, wd, ev, targets, {}, 0)
		ev.append({"t": "core_echo", "kind": atk})
	ev.append({"t": "core_attack", "kind": atk, "core": core_id, "targets": targets})
	return true


## A volley's primary target: the aimed body (manual aim, in range), else the
## Core's targeting mode for the first volley and the nearest unused body for
## the extra ones.
func _core_target(rng_lim: float, mode_s: String, used: Dictionary, k: int) -> int:
	var t: int = -1
	if aim_on:
		var a: int = _nearest(aim_pos, AIM_R, used)
		if a >= 0 and CENTER.distance_to(en.pos[a]) <= rng_lim + en.size[a] * 0.5:
			t = a
	if _sector_k > 0 and _sector_n > 1:
		# an extra barrel: the nearest body in its own sector (else it holds)
		var sdir: Vector2 = core_aim_dir.rotated(TAU * float(_sector_k) / float(_sector_n))
		var st: int = eh.nearest_in_cone(CENTER, sdir, PI / float(_sector_n), rng_lim)
		return st if st >= 0 and not used.has(st) else -1
	if t < 0 and not aim_on and k == 0 and used.is_empty():
		t = _core_threat(rng_lim)
	if t < 0:
		t = pick_target(CENTER, rng_lim, mode_s) if k == 0 and used.is_empty() else _nearest(CENTER, rng_lim, used)
	if t >= 0 and k == 0:
		core_aim_dir = _dir_to(CENTER, en.pos[t])
	return t


## Threat priority target (see THREAT_SCAN), or -1 for the targeting mode.
func _core_threat(rng_lim: float) -> int:
	if thr_n % THREAT_SCAN == 0:
		thr_boss.clear()
		thr_spit.clear()
		var lim2: float = rng_lim * rng_lim * 1.44   # in range, or about to be
		for s in en.order:
			if en.hp[s] <= 0.0:
				continue
			var kd: String = String(en.kind[s])
			if (kd == "ranged" or kd == "elite" or kd == "boss") and CENTER.distance_squared_to(en.pos[s]) <= lim2:
				(thr_spit if kd == "ranged" else thr_boss).append(en.eid[s])
	thr_n += 1
	thr_flip = not thr_flip
	var b: int = _nearest_of(thr_boss, rng_lim, true)
	if b >= 0:
		return b
	return _nearest_of(thr_spit, rng_lim, false) if thr_flip else -1


## The living body of `eids` nearest the Core within rng_lim (only those in
## contact with the Core when `contact`), or -1.
func _nearest_of(eids: Array, rng_lim: float, contact: bool) -> int:
	var lim2: float = rng_lim * rng_lim
	var best: int = -1
	var best_d: float = INF
	for id in eids:
		var s: int = en.slot_of(int(id))
		if s < 0 or en.hp[s] <= 0.0 or (contact and (en.flags[s] & EnemyStore.F_LEAK) == 0):
			continue
		var d2: float = CENTER.distance_squared_to(en.pos[s])
		if d2 <= lim2 and d2 < best_d:
			best_d = d2
			best = s
	return best


static func _dir_to(from: Vector2, to: Vector2) -> Vector2:
	var d: Vector2 = to - from
	return d.normalized() if d.length_squared() > 1e-6 else Vector2.UP


func _core_volley(atk: String, wd: Dictionary, ev: Array, targets: Array, used: Dictionary, k: int) -> bool:
	var rng_lim: float = float(wd["range"])
	var dmg: float = float(wd["dmg"]) * (1.0 + (AIM_FOCUS + float(mods.get("lab_aim", 0.0))) * focus)
	var mode_s: String = String(target_modes[CORE_SLOT])
	match atk:
		"minigun":
			# V3 Minigun barrel: light rounds, each at a random body among the
			# nearest `spread` around the main target (no splash)
			var tgt_m: int = _core_target(rng_lim, mode_s, used, k)
			if tgt_m < 0:
				return false
			var cand: Array = [tgt_m]
			for ed in eh.candidates(en.pos[tgt_m], 40.0):
				if ed != tgt_m and en.hp[ed] > 0.0 and cand.size() < int(wd.get("spread", 3)) and CENTER.distance_to(en.pos[ed]) <= rng_lim:
					cand.append(ed)
			var te_m: int = int(cand[combat_rng.randi_range(0, cand.size() - 1)])
			used[te_m] = true
			var crit_m: bool = _roll_crit(wd)
			var d_m: float = dmg * (crit_mult() if crit_m else 1.0)
			_hit_carry(te_m, d_m * float(wd.get("single_mult", 1.0)), ev, crit_m, CENTER, rng_lim)
			_shred(te_m, wd)
			targets.append(en.eid[te_m])
			_pierce(te_m, d_m, wd, ev, targets)
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": en.pos[te_m], "pellet": true})
		"cannon":
			var barrels: int = int(wd.get("barrels", 1))
			var hit_any: bool = false
			for b in barrels:
				var tgt: int = _core_target(rng_lim, mode_s, used if b == 0 else {}, k)
				if b > 0:
					var alt: int = _nearest(CENTER, rng_lim, used)
					tgt = alt if alt >= 0 else tgt
				if tgt < 0:
					break
				used[tgt] = true
				hit_any = true
				var te: int = tgt
				var tpos: Vector2 = en.pos[te]
				var crit: bool = _roll_crit(wd)
				var d: float = dmg * (crit_mult() if crit else 1.0)
				_hit_carry(te, d * float(wd.get("single_mult", 1.0)), ev, crit, CENTER, rng_lim)
				_shred(te, wd)
				targets.append(en.eid[te])
				_pierce(te, d, wd, ev, targets)
				var rad: float = float(wd.get("splash", 0.0))
				for ed in eh.candidates(tpos, rad):
					if ed != te and en.hp[ed] > 0.0 and en.pos[ed].distance_to(tpos) <= rad:
						_hit(ed, d * float(wd.get("splash_frac", 0.4)), ev)
						targets.append(en.eid[ed])
				_core_bounce(te, d, wd, ev, targets)
				ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": tpos, "radius": rad})
			if not hit_any:
				return false
		"slag":
			var tgt2: int = _core_target(rng_lim, mode_s, used, k)
			if tgt2 < 0:
				return false
			used[tgt2] = true
			var tpos2: Vector2 = en.pos[tgt2]
			var crit2: bool = _roll_crit(wd)
			var d2: float = dmg * (crit_mult() if crit2 else 1.0)
			var rad2: float = float(wd["splash"])
			for ed in eh.candidates(tpos2, rad2):
				if en.hp[ed] > 0.0 and en.pos[ed].distance_to(tpos2) <= rad2:
					_hit(ed, d2, ev, crit2)
					en.apply_slow(ed, float(wd["slow_t"]), 1.0 - float(wd["slow"]))
					targets.append(en.eid[ed])
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": tpos2, "radius": rad2})
		"beam":
			# Lock the highest-HP enemy in range; the ramp resets on a switch.
			# Extra volleys (multishot) are unramped side beams.
			var tgt3: int = _core_target(rng_lim, "strongest", used, k)
			if tgt3 < 0:
				if k == 0:
					beam_eid = -1
					beam_t = 0.0
				return false
			used[tgt3] = true
			var te3: int = tgt3
			var ramp: float = 0.0
			if k == 0:
				if en.eid[te3] != beam_eid:
					beam_eid = en.eid[te3]
					beam_t = -float(wd.get("retarget", 0.0))   # Focus Lens retarget delay
				ramp = clampf(float(wd["ramp"]) * beam_t, 0.0, float(wd["ramp_max"]))
			var d3: float = dmg * (1.0 + ramp) * float(wd.get("single_mult", 1.0))
			if BOSSY.has(en.kind[te3]) or en.is_marked(te3):
				d3 *= float(wd.get("boss_mult", 1.0))
			var crit3: bool = _roll_crit(wd)
			if crit3:
				d3 *= crit_mult()
			_hit_carry(te3, d3, ev, crit3, CENTER, rng_lim)
			_shred(te3, wd)
			targets.append(en.eid[te3])
			_pierce(te3, d3, wd, ev, targets)
			_core_bounce(te3, d3, wd, ev, targets)
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
			var d4: float = dmg * float(rings) * float(wd.get("pulse_mult", 1.0)) * (crit_mult() if crit4 else 1.0)
			var kb: float = float(wd.get("knock", 0.3)) * 40.0 * float(wd.get("knock_m", 1.0))
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
				for kk in mini(int(wd["chain_n"]), outer.size()):
					var cd2: int = outer[kk]
					_hit(cd2, dmg * float(wd["chain_frac"]), ev)
					targets.append(en.eid[cd2])
					ev.append({"t": "shot", "kind": "tesla", "from": CENTER, "to": en.pos[cd2]})
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": CENTER, "radius": rng_lim, "pulse": true})
		"scatter":
			# Scatter Cannon: pellets fanned evenly across the cone at the
			# target; each stops in the first body its line touches.
			var ts: int = _core_target(rng_lim, mode_s, used, k)
			if ts < 0:
				return false
			used[ts] = true
			var dir_s: Vector2 = _dir_to(CENTER, en.pos[ts])
			var n_p: int = maxi(1, int(wd.get("pellets", 6)))
			var half_s: float = deg_to_rad(float(wd.get("cone", 40.0))) * 0.5
			var slice: float = half_s / float(n_p)
			var crit_s: bool = _roll_crit(wd)
			var d_s: float = dmg * (crit_mult() if crit_s else 1.0)
			for pp in n_p:
				var pd: Vector2 = dir_s.rotated(-half_s + slice * (2.0 * float(pp) + 1.0))
				var pe: int = _first_on_ray(CENTER, pd, rng_lim)
				if pe >= 0:
					_hit(pe, d_s, ev, crit_s)
					targets.append(en.eid[pe])
					ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": en.pos[pe], "pellet": true})
				else:
					ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": CENTER + pd * rng_lim, "pellet": true})
		"rail":
			# Rail Driver: a slug through the first rail_n bodies on the line
			# to the target, no falloff (a Shieldbearer's front stops it).
			var tr: int = _core_target(rng_lim, mode_s, used, k)
			if tr < 0:
				return false
			used[tr] = true
			var dir_r: Vector2 = _dir_to(CENTER, en.pos[tr])
			var tip: Vector2 = CENTER + dir_r * rng_lim
			var crit_r: bool = _roll_crit(wd)
			var d_r: float = dmg * (crit_mult() if crit_r else 1.0) * float(wd.get("single_mult", 1.0))
			var on: Array = []
			for ed in eh.line(CENTER, tip, en.max_size * 0.5 + 3.0):
				if en.hp[ed] <= 0.0:
					continue
				var rel: Vector2 = en.pos[ed] - CENTER
				var al: float = rel.dot(dir_r)
				if al < 0.0 or al > rng_lim or absf(rel.cross(dir_r)) > en.size[ed] * 0.5 + 3.0:
					continue
				on.append([al, ed])
			on.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
			var hn: int = 0
			for x in on:
				if hn >= int(wd.get("rail_n", 10)):
					break
				var er: int = int((x as Array)[1])
				_hit(er, d_r, ev, crit_r)
				targets.append(en.eid[er])
				hn += 1
				if _blocked:
					break
			if hn == 0:
				_hit(tr, d_r, ev, crit_r)
				targets.append(en.eid[tr])
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": tip, "rail": true})
		"arc":
			# Arc Caster: lightning from the target through chain_n more bodies
			# (jump px, x chain_frac each); every struck body is shocked.
			var ta: int = _core_target(rng_lim, mode_s, used, k)
			if ta < 0:
				return false
			used[ta] = true
			var crit_a: bool = _roll_crit(wd)
			var d_a: float = dmg * (crit_mult() if crit_a else 1.0)
			var seen_a: Dictionary = {}
			var ce: int = ta
			var prev: Vector2 = CENTER
			for j in int(wd.get("chain_n", 5)) + 1:
				if ce < 0:
					break
				seen_a[ce] = true
				var cpos: Vector2 = en.pos[ce]
				_hit(ce, d_a, ev, crit_a)
				en.set_shock(ce, 1.0)
				en.shock_src[ce] = CORE_SLOT
				targets.append(en.eid[ce])
				ev.append({"t": "shot", "kind": "tesla", "from": prev, "to": cpos})
				prev = cpos
				d_a *= float(wd.get("chain_frac", 0.8))
				ce = _nearest(cpos, float(wd.get("jump", 70.0)), seen_a)
		"flame":
			# Flame Projector: a cone of fire at the target - every body in it
			# takes a light hit and burns (the burn spreads through a pile).
			var tf: int = _core_target(rng_lim, mode_s, used, k)
			if tf < 0:
				return false
			used[tf] = true
			var dir_f: Vector2 = _dir_to(CENTER, en.pos[tf])
			var half_f: float = deg_to_rad(float(wd.get("cone", 50.0))) * 0.5
			var crit_f: bool = _roll_crit(wd)
			var d_f: float = dmg * (crit_mult() if crit_f else 1.0)
			var bdps: float = d_f * float(wd.get("flame_burn", 0.5))
			for ed in eh.cone(CENTER, dir_f, half_f, rng_lim):
				if en.hp[ed] <= 0.0:
					continue
				_hit(ed, d_f, ev, crit_f)
				if en.hp[ed] > 0.0:
					_ignite(ed, TuneRef.num("mass_burn_s", 2.0), bdps)
				targets.append(en.eid[ed])
			ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": CENTER + dir_f * rng_lim, "cone": rad_to_deg(half_f * 2.0)})
		"missiles":
			# Swarm Missiles: seekers at the target and the nearest others in
			# range; each blasts a small splash at half damage.
			var t0: int = _core_target(rng_lim, mode_s, used, k)
			if t0 < 0:
				return false
			var aims: Array = [t0]
			used[t0] = true
			var nm: int = maxi(1, int(wd.get("missiles", 4)))
			for c in eh.nearest_n(CENTER, nm + used.size(), rng_lim):
				if aims.size() >= nm:
					break
				if used.has(c) or en.hp[c] <= 0.0:
					continue
				aims.append(c)
				used[c] = true
			var crit_m: bool = _roll_crit(wd)
			var d_m: float = dmg * (crit_mult() if crit_m else 1.0)
			var rad_m: float = float(wd.get("splash", 0.0))
			for te_m in aims:
				var tm: int = int(te_m)
				var tp: Vector2 = en.pos[tm]
				_hit(tm, d_m, ev, crit_m)
				targets.append(en.eid[tm])
				if rad_m > 0.0:
					for ed in eh.candidates(tp, rad_m):
						if ed != tm and en.hp[ed] > 0.0 and en.pos[ed].distance_to(tp) <= rad_m:
							_hit(ed, d_m * 0.5, ev)
				_core_bounce(tm, d_m, wd, ev, targets)
				ev.append({"t": "shot", "kind": "core", "from": CENTER, "to": tp, "radius": rad_m, "missile": true})
		"saw":
			# Saw Launcher: ricochets through `bounces` more bodies (x bounce_frac
			# each) and stacks armor shred on every body it cuts.
			var tw: int = _core_target(rng_lim, mode_s, used, k)
			if tw < 0:
				return false
			used[tw] = true
			var crit_w: bool = _roll_crit(wd)
			var d_w: float = dmg * (crit_mult() if crit_w else 1.0) * float(wd.get("single_mult", 1.0))
			var seen_w: Dictionary = {}
			var cw_e: int = tw
			var prev_w: Vector2 = CENTER
			for j in int(wd.get("bounces", 4)) + 1:
				if cw_e < 0:
					break
				seen_w[cw_e] = true
				var p_w: Vector2 = en.pos[cw_e]
				_hit(cw_e, d_w, ev, crit_w)
				en.shred_n[cw_e] = mini(5, en.shred_n[cw_e] + 1)
				targets.append(en.eid[cw_e])
				ev.append({"t": "shot", "kind": "core", "from": prev_w, "to": p_w, "saw": true})
				prev_w = p_w
				d_w *= float(wd.get("bounce_frac", 0.85))
				cw_e = _nearest(p_w, float(wd.get("jump", 90.0)), seen_w)
		_:
			return false
	return true


## The first living body a ray from `from` along `dir` touches within `reach`
## (body size counts; ties by slot), or -1.
func _first_on_ray(from: Vector2, dir: Vector2, reach: float) -> int:
	var best: int = -1
	var best_al: float = INF
	for ed in eh.line(from, from + dir * reach, en.max_size * 0.5 + 2.0):
		if en.hp[ed] <= 0.0:
			continue
		var rel: Vector2 = en.pos[ed] - from
		var al: float = rel.dot(dir)
		if al < 0.0 or al > reach or absf(rel.cross(dir)) > en.size[ed] * 0.5 + 2.0:
			continue
		if al < best_al or (al == best_al and ed < best):
			best_al = al
			best = ed
	return best


## Gear Ricochet: a Core hit bounces on to `bounce` more bodies (x0.7 each,
## 80 px jumps).
func _core_bounce(te: int, d: float, wd: Dictionary, ev: Array, targets: Array) -> void:
	var n: int = int(wd.get("bounce", 0))
	if n <= 0:
		return
	var seen: Dictionary = {te: true}
	var cur: Vector2 = en.pos[te]
	var dd: float = d
	for j in n:
		dd *= TuneRef.num("gear_bounce_frac", 0.7)
		var nx: int = _nearest(cur, TuneRef.num("gear_bounce_r", 80.0), seen)
		if nx < 0:
			return
		seen[nx] = true
		_hit(nx, dd, ev)
		targets.append(en.eid[nx])
		ev.append({"t": "shot", "kind": "core", "from": cur, "to": en.pos[nx], "bounce": true})
		cur = en.pos[nx]


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
	var cmb: float = combo_mult()   # V2 P7c kill-streak combo
	var streak: int = 0
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
			gain = en.cash[ed] * ci * bm * kc_mult * cmb
			cash += gain
			cash_earned += gain
			xp += en.xp[ed] * float(stats["xp_mult"]) * cmb
			streak += wt
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
	if streak > 0:
		combo += float(streak)
		_combo_check(ev)


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
	var ctx: Dictionary = {"tier": tier, "wave": wave, "drop_mult": 1.0 + float(ins.get("in_drop", 0.0)), "share": ks if ks >= 0.0 else en.share[ed],
		"items_left": LootDB.wave_cap(tier) - int(wave_items.get(wave, 0)), "item_mult": 1.0 + float(mods.get("lab_items", 0.0))}
	var drops: Array = Drops.roll(drop_rng, src, ctx, loot_rng)
	for d1 in drops:
		if String((d1 as Dictionary)["kind"]) == "item":
			wave_items[wave] = int(wave_items.get(wave, 0)) + 1
	if pf("scrap_find") > 0.0:
		for d0 in drops:
			if String((d0 as Dictionary)["kind"]) == "scrap":
				d0["n"] = int(round(float(d0["n"]) * (1.0 + pf("scrap_find"))))
	var got: Array = Drops.add(loot, drops)
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
	_check_directive(ev)
	_check_level(ev)
	_check_evo(ev)
	_check_draft(ev)
	_check_perk(ev)


func _busy() -> bool:
	return draft.size() > 0 or pending_place != "" or not merge_offer.is_empty() or perk_offer.size() > 0 or mutation_offer.size() > 0 or directive_offer.size() > 0


# ------------------------------------------------------- V2 P7c run events
## Kill-streak combo multiplier on kill cash and XP (COMBO_TIERS).
func combo_mult() -> float:
	return 1.0 if combo_tier <= 0 else float((COMBO_TIERS[combo_tier - 1] as Array)[1])


func _combo_tier_of(v: float) -> int:
	var t: int = 0
	for k in COMBO_TIERS.size():
		if v >= float((COMBO_TIERS[k] as Array)[0]):
			t = k + 1
	return t


func _combo_check(ev: Array) -> void:
	var t: int = _combo_tier_of(combo)
	if t != combo_tier:
		var up: bool = t > combo_tier
		combo_tier = t
		ev.append({"t": "combo_tier", "tier": t, "mult": combo_mult(), "up": up})


## Draft choices the taken Directives add.
func _directive_choices() -> int:
	var n: int = 0
	for id in directives:
		n += int(DirectiveDB.get_def(String(id)).get("choices", 0))
	return n


func _check_directive(ev: Array) -> void:
	if directive_pending <= 0 or _busy():
		return
	directive_pending -= 1
	directive_offer = DirectiveDB.offer(draft_rng, directives)
	if not directive_offer.is_empty():
		ev.append({"t": "directive_offer", "ids": directive_offer.duplicate(), "wave": wave})


## Take Directive k of the open offer: its fx join the run, its enemy cost too.
func choose_directive(k: int) -> Array:
	if k < 0 or k >= directive_offer.size():
		return []
	var id: String = String(directive_offer[k])
	directive_offer = []
	directives.append(id)
	_refresh_rfx()
	_refresh_enemy_mods()
	recompute()
	var d: Dictionary = DirectiveDB.get_def(id)
	var ev: Array = [{"t": "directive_taken", "id": id, "name": String(d["name"]), "desc": String(d["desc"]), "cost": String(d["cost"])}]
	_check_queue(ev)
	return ev


func _supply_sym() -> String:
	var tot: float = 0.0
	for sy in SUPPLY_SYMS:
		tot += float((sy as Array)[1])
	var r: float = supply_rng.randf() * tot
	for sy in SUPPLY_SYMS:
		r -= float((sy as Array)[1])
		if r < 0.0:
			return String((sy as Array)[0])
	return "cash"


## Supply Drop (every SUPPLY_EVERY waves): spin 3 reels and pay out. Each
## symbol pays x1 / x3 / x8 for 1 / 2 / 3 of a kind; three stars = JACKPOT.
func _supply_drop(ev: Array) -> void:
	supply_n += 1
	_supply_pay([_supply_sym(), _supply_sym(), _supply_sym()], ev)


## Pay a Supply Drop's reels (tests call it with fixed reels).
func _supply_pay(reels: Array, ev: Array) -> void:
	var counts: Dictionary = {}
	for r in reels:
		counts[r] = int(counts.get(r, 0)) + 1
	var pays: Dictionary = {}
	var jackpot: bool = int(counts.get("star", 0)) >= 3
	for sym in counts.keys():
		var m: int = int(SUPPLY_PAY[int(counts[sym])])
		match String(sym):
			"cash":
				var c: float = 120.0 * cash_index() * float(m)
				cash += c
				cash_earned += c
				pays["cash"] = c
			"xp":
				var x: float = 0.35 * xp_need() * float(m)
				xp += x
				pays["xp"] = x
			"reroll":
				rerolls_left += m
				pays["reroll"] = m
			"card":
				for k in mini(3, m):
					draft_queue.append("rare" if m >= 3 else "")
				pays["card"] = mini(3, m)
			"cache":
				var il: int = LootDB.ilvl(wave, tier)
				for k in mini(3, m):
					Drops.add(loot, [{"kind": "cache", "cache": "elite" if m >= 3 else "field", "ilvl": il, "source": "supply"}])
				pays["cache"] = mini(3, m)
			"star":
				if int(counts[sym]) == 2:
					perk_pending += 1
					pays["star"] = 1
	if jackpot:
		var jc: float = 400.0 * cash_index()
		cash += jc
		cash_earned += jc
		draft_queue.append("epic")
		Drops.add(loot, [{"kind": "cache", "cache": "elite", "ilvl": LootDB.ilvl(wave, tier), "source": "supply"}])
		pays["jackpot"] = jc
	supply_last = {"reels": reels, "pays": pays, "jackpot": jackpot, "wave": wave}
	ev.append({"t": "supply_drop", "reels": reels, "pays": pays, "jackpot": jackpot, "wave": wave})


## V2 P7d Slot Machines: each spins at the start of every wave (Supply Drop
## stream): x1 55% / x3 30% / x6 12% / x20 3% of its stake x cash index x tier.
func _slot_spins(ev: Array) -> void:
	for i in N:
		if id_at(i) != "slots":
			continue
		var r: float = supply_rng.randf()
		var mul: int = 1 if r < 0.55 else (3 if r < 0.85 else (6 if r < 0.97 else 20))
		var c: float = float(SupportDB.get_def("slots")["spin"]) * float(mul) * cash_index() * tier_mult(i) * (1.0 + float(mod_fx(i).get("power", 0.0)))
		cash += c
		cash_earned += c
		ev.append({"t": "slot_spin", "slot": i, "mult": mul, "cash": c})


## Draft card locks: MAX_LOCKS + the Draft Lock research.
func lock_cap() -> int:
	return MAX_LOCKS + clampi(int(mods.get("lab_locks", 0)), 0, 1)


## Lock / unlock draft card idx (max lock_cap()): kept by rerolls, carried to
## the next hand when another card is taken.
func toggle_lock(idx: int) -> Array:
	if idx < 0 or idx >= draft.size():
		return []
	var c: Dictionary = draft[idx]
	if String(c.get("kind", "")) == "evo":
		return []
	if bool(c.get("lock", false)):
		c.erase("lock")
	else:
		var n: int = draft.filter(func(x: Variant) -> bool: return bool((x as Dictionary).get("lock", false)) and String((x as Dictionary).get("kind", "")) != "evo").size()
		if n >= lock_cap():
			return []
		c["lock"] = true
	return [{"t": "draft_lock", "idx": idx, "lock": bool(c.get("lock", false))}]


## Put carried (locked) cards back into the open hand: re-validated against
## the run now (a building may have become a merge, or be unplaceable).
func _apply_carry() -> void:
	if carry_cards.is_empty():
		return
	var ctx: Dictionary = _draft_ctx("")
	for cc in carry_cards:
		var old: Dictionary = (cc as Dictionary)["card"]
		var nc: Dictionary = old if String(old.get("kind", "")) == "evo" else Draft.card_for(String(old["id"]), ctx)
		if nc.is_empty():
			continue
		nc["lock"] = true
		# its old slot, or the next one not holding an evolution / another lock
		var slot: int = int((cc as Dictionary)["at"])
		while slot < draft.size() and (String((draft[slot] as Dictionary).get("kind", "")) == "evo" or bool((draft[slot] as Dictionary).get("lock", false))):
			slot += 1
		# never two copies of an id in one hand
		for k in draft.size():
			if k != slot and String((draft[k] as Dictionary)["id"]) == String(nc["id"]) and not bool((draft[k] as Dictionary).get("lock", false)):
				var used: Array = draft.duplicate()
				used.append(nc)
				var rep_c: Dictionary = Draft.replace_card(draft_rng, ctx, used, k)
				if not rep_c.is_empty():
					draft[k] = rep_c
		if slot < draft.size():
			draft[slot] = nc
		else:
			draft.append(nc)
	carry_cards = []


## Evolution check: a T3 weapon with its EvoDB partner touching it queues a
## draft led by its evolution card (once per anchor).
func _check_evo(ev: Array) -> void:
	for i in N:
		var id: String = id_at(i)
		if id == "" or not EvoDB.has(id) or tier_at(i) < lvl_cap() or evo_done.has(i) or bool((slots[i] as Dictionary).get("evo", false)):
			continue
		var partner: String = String(EvoDB.get_def(id)["partner"])
		for n in adjacent(i):
			if id_at(int(n)) == partner:
				evo_done[i] = true
				draft_queue.push_front("evo:%d" % i)
				ev.append({"t": "evo_ready", "slot": i, "id": id, "name": String(EvoDB.get_def(id)["name"])})
				break


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


## V2 P7a: every XP level-up queues a draft; every GOLD_EVERY-th level also
## a gold perk offer.
func _check_level(ev: Array) -> void:
	while xp >= xp_need():
		xp -= xp_need()
		level += 1
		draft_queue.append("")
		var gold: bool = level % GOLD_EVERY == 0 and not modifiers.has("noperks") and not Perks.available(perks_taken).is_empty()
		if gold:
			perk_pending += 1
		ev.append({"t": "levelup", "level": level, "gold": gold})


## Draft context for Draft.roll_hand (what the run can use right now).
func _draft_ctx(guarantee: String) -> Dictionary:
	var owned: Dictionary = {}
	var copies: Dictionary = {}
	var free: bool = false
	var free_outer: bool = false
	for i in N:
		var id: String = id_at(i)
		if id != "":
			owned[id] = mini(int(owned.get(id, 99)), tier_at(i))
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
		"hut_max": hut_max(), "t1": _t1_ids(),
		"packs": packs, "specials": sp, "banished": banished, "luck": luck_now(),
		"eco_mult": 1.0,
		"choices": 3 + mini(1, _reforge_node("wide_draft")) + _directive_choices() + clampi(int(mods.get("lab_choices", 0)), 0, 2),
		"insight_p": TuneRef.num("pc_insight_p", 0.01) * (1.0 + float(luck) * 0.05),
		"insight_ok": insight_found.size() < ins_cap, "insight_blocked": blocked,
		"guarantee": guarantee, "weapons": _weapon_buildings(),
	}


## {id: true} for every id with a T1 on the grid (a duplicate card can merge).
func _t1_ids() -> Dictionary:
	var out: Dictionary = {}
	for i in N:
		if id_at(i) != "" and tier_at(i) == 1:
			out[id_at(i)] = true
	return out


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
	var evo: Dictionary = {}
	if draft_guarantee.begins_with("evo:"):
		var es: int = int(draft_guarantee.substr(4))
		draft_guarantee = "legendary"
		if EvoDB.has(id_at(es)) and not bool((slots[es] as Dictionary).get("evo", false)):
			evo = EvoDB.card(id_at(es), es)
			evo["lock"] = true
	draft = Draft.roll_hand(draft_rng, _draft_ctx("" if not evo.is_empty() else draft_guarantee))
	if not evo.is_empty():
		draft_guarantee = ""
		if draft.is_empty():
			draft = [evo]
		else:
			draft[0] = evo
	_apply_carry()
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
	# V2 P7c: locked cards the player did not take wait for the next hand
	carry_cards = []
	for k in draft.size():
		var ck: Dictionary = draft[k]
		if k != idx and bool(ck.get("lock", false)) and String(ck.get("kind", "")) != "evo":
			carry_cards.append({"card": ck, "at": k})
	draft.clear()
	var id: String = card["id"]
	var kind: String = String(card["kind"])
	picks_taken.append(id)
	match kind:
		"evo":
			var es: int = int(card["slot"])
			if EvoDB.has(id_at(es)):
				(slots[es] as Dictionary)["evo"] = true
				recompute()
				ev.append({"t": "evolved", "slot": es, "id": id_at(es), "name": String(EvoDB.get_def(id_at(es))["name"])})
		"new":
			# V2 P7a: placed on a free cell, or dropped on a T1 twin to merge
			pending_place = id
			ev.append({"t": "place_mode", "id": id, "dup": bool(card.get("dup", false)), "merge": card_merge_targets(id)})
			ev.append({"t": "pick_applied", "id": id, "fam": String(card["fam"]), "kind": kind, "rarity": String(card["rarity"]), "reward": "building"})
			return ev
		"pack":
			packs[id] = pack_n(id) + 1
			_refresh_rfx()
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
	var kept: Array = []
	for k in draft.size():
		if bool((draft[k] as Dictionary).get("lock", false)):
			kept.append({"card": draft[k], "at": k})
	draft = Draft.roll_hand(draft_rng, _draft_ctx(draft_guarantee))
	carry_cards = kept
	_apply_carry()
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
	_refresh_rfx()
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
	var r: int = pending_rot if pending_rot >= 0 else default_rot(i, pending_place)
	slots[i] = {"id": pending_place, "tier": 1, "rot": r, "mods": []}
	cooldowns[i] = 0.0
	pending_place = ""
	pending_rot = -1
	recompute()
	ev.append({"t": "placed", "slot": i, "id": id_at(i)})
	_drain_troop_events(ev)
	_check_queue(ev)
	return ev


# ------------------------------------------------------------------ facing (V2 P3c)
## Default facing of `id` anchored at cell i: away from the Core.
func default_rot(i: int, id: String) -> int:
	return WeaponDB.rot_toward(fp_center(i, size_of(id)) - CENTER)


## Facing step (0-7) of the building anchored at i (its default when unset).
func rot_at(i: int) -> int:
	var sd: Dictionary = slots[i] if i >= 0 and i < slots.size() else {}
	if sd.is_empty():
		return 6
	return int(sd["rot"]) if sd.has("rot") else default_rot(i, String(sd["id"]))


## Rotate the directional weapon anchored at i by `d` steps of 45 deg (free).
func rotate(i: int, d: int = 1) -> Array:
	if i < 0 or i >= N or id_at(i) == "" or not WeaponDB.directional(id_at(i)):
		return []
	var r: int = posmod(rot_at(i) + d, 8)
	(slots[i] as Dictionary)["rot"] = r
	recompute()
	return [{"t": "rotated", "slot": i, "rot": r}]


## Rotate the pick being placed. `hint` is the anchor under the cursor, so the
## first turn starts from the facing the ghost shows (its default there).
func rotate_pending(d: int = 1, hint: int = -1) -> Array:
	if pending_place == "" or not WeaponDB.directional(pending_place):
		return []
	var base: int = pending_rot
	if base < 0:
		base = default_rot(hint, pending_place) if hint >= 0 else 6
	pending_rot = posmod(base + d, 8)
	return [{"t": "rotated", "slot": -1, "rot": pending_rot}]


## Facing the ghost of the pending pick shows at anchor i.
func pending_rot_at(i: int) -> int:
	return pending_rot if pending_rot >= 0 else default_rot(i, pending_place)


# ------------------------------------------------------------ merges (V2 P7a)
## Anchors the building at `a` can merge into (same id and tier, below T3).
func merge_targets(a: int) -> Array:
	var out: Array = []
	if a < 0 or a >= N or id_at(a) == "" or tier_at(a) >= lvl_cap():
		return out
	for b in N:
		if b != a and id_at(b) == id_at(a) and tier_at(b) == tier_at(a):
			out.append(b)
	return out


## T1 buildings of `id` a duplicate draft card can merge into (a card is a T1).
func card_merge_targets(id: String) -> Array:
	var out: Array = []
	for b in N:
		if id_at(b) == id and tier_at(b) == 1 and lvl_cap() > 1:
			out.append(b)
	return out


## The nearest merge partner of the building at i (-1 = none): the panel's
## Merge button folds it into i.
func merge_partner(i: int) -> int:
	var best: int = -1
	var bd: int = 1 << 30
	for b in merge_targets(i):
		var d: int = fp_dist(i, int(b))
		if d < bd:
			bd = d
			best = int(b)
	return best


## Merge the building at `a` into the one at `b` (same id + tier): b rises a
## tier and keeps its cell and facing, with its mods plus a's; a leaves the
## grid. Opens b's mod pick (MergeDB).
func merge(a: int, b: int) -> Array:
	if over or not merge_offer.is_empty() or not merge_targets(a).has(b):
		return []
	var sa: Dictionary = slots[a]
	var sb: Dictionary = slots[b]
	var mods: Array = (sb.get("mods", []) as Array).duplicate(true)
	mods.append_array((sa.get("mods", []) as Array).duplicate(true))
	slots[a] = {}
	cooldowns[a] = 0.0
	sb["tier"] = tier_at(b) + 1
	sb["mods"] = mods
	return _merged(b, String(sb["id"]), a)


## Drop the pending duplicate card onto the T1 at b: it becomes a T2.
func merge_card(b: int) -> Array:
	if pending_place == "" or not card_merge_targets(pending_place).has(b):
		return []
	var id: String = pending_place
	pending_place = ""
	pending_rot = -1
	(slots[b] as Dictionary)["tier"] = 2
	return _merged(b, id, -1)


func _merged(b: int, id: String, from: int) -> Array:
	recompute()
	var tr: int = tier_at(b)
	merges += 1
	var ev: Array = [{"t": "merged", "slot": b, "from": from, "id": id, "tier": tr}]
	var offer: Array = MergeDB.offer(id, tr)
	if not offer.is_empty():
		merge_offer = {"slot": b, "tier": tr, "id": id, "n": offer.size()}
		ev.append({"t": "merge_offer", "slot": b, "tier": tr, "id": id, "mods": offer.duplicate(true)})
	_drain_troop_events(ev)
	_check_queue(ev)
	return ev


## Take mod k of the open merge offer.
func choose_mod(k: int) -> Array:
	if merge_offer.is_empty() or k < 0 or k >= int(merge_offer["n"]):
		return []
	var b: int = int(merge_offer["slot"])
	var tr: int = int(merge_offer["tier"])
	var id: String = String(merge_offer["id"])
	merge_offer = {}
	var ev: Array = []
	if id_at(b) == id:
		var sb: Dictionary = slots[b]
		if not sb.has("mods"):
			sb["mods"] = []
		(sb["mods"] as Array).append([tr, k])
		recompute()
		var md: Dictionary = MergeDB.mod_of(id, tr, k)
		ev.append({"t": "mod_taken", "slot": b, "id": id, "tier": tr, "k": k, "name": String(md.get("name", "")), "desc": String(md.get("desc", ""))})
	_drain_troop_events(ev)
	_check_queue(ev)
	return ev


## Merge mods on the building at i, as their MergeDB defs.
func mods_at(i: int) -> Array:
	var out: Array = []
	if id_at(i) == "":
		return out
	for m in ((slots[i] as Dictionary).get("mods", []) as Array):
		out.append(MergeDB.mod_of(id_at(i), int((m as Array)[0]), int((m as Array)[1])))
	return out


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


## Buy one level of a Core Enhancement (V2 P7b: TrackDB; Lucky Purchase may
## refund it, rolled on the draft stream only when that track is owned).
func buy_track(t: String) -> Array:
	var ev: Array = []
	if over or not TRACKS.has(t) or not track_unlocked(t):
		return ev
	var c: int = track_cost(t)
	if c < 0 or cash < float(c):
		return ev
	var free: bool = tf("free_buy") > 0.0 and draft_rng.randf() < tf("free_buy")
	if not free:
		cash -= float(c)
	tracks[t] = int(tracks[t]) + 1
	tfx = TrackDB.fx_of(tracks)
	core_run_lvl = int(tracks["dmg"])
	recompute()
	ev.append({"t": "track", "track": t, "level": int(tracks[t]), "cost": 0 if free else c, "free": free})
	ev.append({"t": "upgraded", "slot": CORE_SLOT, "level": int(tracks[t]), "track": t})
	return ev


## Buy up to n levels of track t (the panel's x5 / MAX); stops when broke.
func buy_tracks(t: String, n: int) -> Array:
	var ev: Array = []
	for k in n:
		var e1: Array = buy_track(t)
		if e1.is_empty():
			break
		ev.append_array(e1)
	return ev


## V2 P8b Auto-Buy research: at each wave start, buy the cheapest open
## standard track of the chosen tree ("all": any tree) while it costs at most
## the cash above a 25% reserve. Off ("") without the research.
func _auto_buy(ev: Array) -> void:
	var mode_ab: String = String(mods.get("auto_buy", ""))
	if mode_ab == "" or over:
		return
	var floor_cash: float = cash * 0.25
	for n in 60:
		var best: String = ""
		var bc: int = -1
		for t in TrackDB.IDS:
			var tid: String = String(t)
			if TrackDB.is_od(tid) or not track_unlocked(tid):
				continue
			if mode_ab != "all" and String(TrackDB.get_def(tid)["tree"]) != mode_ab:
				continue
			var c: int = track_cost(tid)
			if c >= 0 and (bc < 0 or c < bc):
				bc = c
				best = tid
		if best == "" or cash - float(bc) < floor_cash:
			return
		var e1: Array = buy_track(best)
		if e1.is_empty():
			return
		for e in e1:
			(e as Dictionary)["auto"] = true
		ev.append_array(e1)


## Live switch from the run panel (EAUTO): the next wave start uses it.
func set_auto_buy(mode_ab: String) -> void:
	mods["auto_buy"] = mode_ab


## V2 P8 research unlocks (TrackDB `unlock` = [research id, level]).
func track_unlocked(t: String) -> bool:
	var u: Variant = (TRACKS.get(t, {}) as Dictionary).get("unlock", [])
	if not (u is Array) or (u as Array).size() < 2:
		return true
	return int((mods.get("res", {}) as Dictionary).get(String(u[0]), 0)) >= int(u[1])


## Legacy view hook: the Core cell buys the Damage track; buildings level only
## through merges.
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
		# ---- V2 P7d specials
		"sp_nuke", "sp_blackhole":
			var pos2: Vector2 = Vector2.INF
			if cell is Vector2:
				pos2 = cell
			elif (cell is int or cell is float) and int(cell) >= 0 and int(cell) < N:
				pos2 = slot_pos(int(cell))
			else:
				pos2 = _densest(float(fx["radius"]) * cpx())
			if pos2 == Vector2.INF or live == 0:
				return {"result": "no_target", "ev": []}
			var cw2: Dictionary = (stats["weapons"] as Array).back()
			var rr2: float = float(fx["radius"]) * cpx()
			if id == "sp_nuke":
				orbitals.append({"pos": pos2, "t": float(fx["delay"]), "dmg": float(fx["mult"]) * float(cw2["dmg"]) * spec_mult, "r": rr2, "knock": 6.0})
			else:
				_src = "special"
				for ed in eh.candidates(pos2, rr2 + en.max_size * 0.5):
					if ed < en.hp.size() and en.hp[ed] > 0.0 and en.pos[ed].distance_to(pos2) <= rr2 + en.size[ed] * 0.5:
						en.apply_slow(ed, float(fx["dur"]), 1.0 - float(fx["slow"]))
						_hit(ed, float(fx["mult"]) * float(cw2["dmg"]) * spec_mult, ev)
				_src = ""
			cast["pos"] = pos2
			cast["r"] = rr2
		"sp_shield":
			immune_t = maxf(immune_t, float(fx["dur"]))
		"sp_frenzy":
			buffs["frenzy_t"] = float(fx["dur"])
		"sp_meteor":
			var mr: float = float(fx["radius"]) * cpx()
			var mc: Vector2 = _densest(mr)
			if mc == Vector2.INF or live == 0:
				return {"result": "no_target", "ev": []}
			var cw3: Dictionary = (stats["weapons"] as Array).back()
			for mk in int(fx["n"]):
				var off: Vector2 = Vector2.ZERO if mk == 0 else Vector2.from_angle(TAU * float(mk) / float(int(fx["n"]) - 1)) * float(fx["spread"]) * cpx()
				orbitals.append({"pos": mc + off, "t": 0.5 + 0.2 * float(mk), "dmg": float(fx["mult"]) * float(cw3["dmg"]) * spec_mult, "r": mr})
			cast["pos"] = mc
		"sp_jackpot":
			_supply_drop(ev)
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
		"scatter":
			targets = 0.5 * float(core_w.get("pellets", 6))
		"rail":
			targets = 3.0
		"arc":
			targets = 1.0 + 0.6 * float(core_w.get("chain_n", 5))
		"flame":
			targets = 4.0
		"missiles":
			targets = float(core_w.get("missiles", 4))
		"saw":
			targets = 1.0 + 0.7 * float(core_w.get("bounces", 4))
	if String(core_w.get("attack", "cannon")) != "pulse":
		targets *= 1.0 + float(core_w.get("multishot", 0))
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
		"crit": minf(1.0, float(stats.get("crit", 0.0)) + float(core_w.get("crit", 0.0))), "crit_mult": crit_mult(),
	}


## Cash a building represents (move cost): its rarity tier x level, in
## current cash units.
func building_value(i: int) -> int:
	if id_at(i) == "":
		return 0
	return int(20.0 * float(tier_at(i)) * cash_index())


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
