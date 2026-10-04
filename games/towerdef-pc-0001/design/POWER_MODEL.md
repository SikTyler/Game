# Corehold PC — Power Model (Economy Theorist)

Status: design spec for the redesign (`/root/.claude/plans/game-idea-incremental-roguelite-flickering-ember.md`).
Owner invariant: **player power and currency grow at a similar rate to wave difficulty.**
Everything here is meant to be computed by a pure module `PowerModel.gd` (API in §10) so the
engine, the playtest bot and the balance tables share one source of truth. All knobs are `TuneRef` keys.

---

## 1. Difficulty — current curves (read from code, 2026-10)

Source: `TowerState.gd` (`scale()`, `interval_for()`, `_enemy_stats`), `Tiers.gd`, `data/EnemyDB.gd`.

| Symbol | Formula | Knobs (current) |
|---|---|---|
| HP scale | `S(w) = g_h^(w-1)` ; endless w>100: `g_h^99 * 1.12^(w-100)` | `hp_growth` 1.17 (T1), `hp_growth_t2` 1.18, `hp_growth_hi` 1.155 (T3+) |
| Tier HP | `T(t) = 1.5^(t-1)` | `tier_hp_base` |
| Enemy HP | `HP_e(w,t) = base_hp_e * S(w) * T(t)` | drone 6, skitter 3, hauler 24, elite 30, boss 200 |
| Enemy dmg | `DMG_e(w,t) = base_dmg_e * 1.06^(w-1) * T(t)` | `dmg_growth` 1.06 |
| Spawn interval | `I(w) = max(0.45, 1.8 * 0.93^(w-1))` | cap reached at **w ≈ 20** |
| Spawns / wave | `N(w) = wave_time / I(w)` , wave_time 25 s | 13.9 → 55.6 |
| Boss | every 10 waves (8 at T5+) | |

**Required DPS** (HP pressure per second, drone-equivalent):
`D(w,t) = 6 * S(w) * T(t) / I(w)`  — growth/wave: **1.258 for w<20** (HP x spawn ramp), **1.17 for w≥20** (T1).

| w | I(w) s | N(w) | drone HP | drone dmg | D(w,T1) | D(w,T3) |
|---|---|---|---|---|---|---|
| 1 | 1.80 | 13.9 | 6.0 | 4.0 | 3.3 | 7.5 |
| 5 | 1.35 | 18.6 | 11.2 | 5.0 | 8.4 | 18.8 |
| 10 | 0.94 | 26.7 | 24.7 | 6.8 | 26.3 | 59.2 |
| 20 | 0.45 | 55.1 | 118 | 12.1 | 261 | 588 |
| 30 | 0.45 | 55.6 | 570 | 21.7 | 1 266 | 2 848 |
| 40 | 0.45 | 55.6 | 2 738 | 38.8 | 6 084 | 13 689 |
| 50 | 0.45 | 55.6 | 13 160 | 69.5 | 29 245 | 65 800 |
| 60 | 0.45 | 55.6 | 63 258 | 124 | 140 574 | 316 291 |
| 100 | 0.45 | 55.6 | 3.4e7 | 1 280 | 7.5e7 | 1.7e8 |

**Damage pressure** (incoming DPS if leaks) `P(w,t) = leak_frac * N(w)/wave_time * DMG(w,t)`.
Note HP grows 1.17/w but enemy damage only 1.06/w: EHP requirement grows far slower than DPS
requirement, so EHP is a *floor* constraint, DPS is the *frontier* constraint.

---

## 2. Player power

### 2.1 Effective DPS
```
DPS_eff = (DPS_core + Σ DPS_bld + DPS_troops + DPS_special) * M_global * U(w)
DPS_core    = core_dmg * core_rate * core_mult_attack * overkill_eff
               core_dmg = core_base_dmg[core] * 1.15^core_run_lvl * (1 + perm_core_lvl * 0.08)
DPS_bld_i   = bld_base_i * 1.25^(lvl_i - 1) * adj_i * pack_mult_i
DPS_troops  = huts * troops_per_hut * troop_dps * uptime(≈0.6, roaming)
DPS_special = Σ special_dmg / special_cooldown   (amortised over a wave)
M_global    = Π(1+part_dmg_k) * (1 + insight_dmg) * shard_mult * set_bonus
U(w)        = utility factor: slows, AoE vs N(w) ( AoE value ∝ min(N_onscreen, targets) )
```
AoE is valued as `dmg * min(targets_hit, density(w))`; density saturates at w≈20, so single-target and
AoE archetypes converge after the spawn cap (good for archetype parity, §7).

### 2.2 EHP
```
EHP = core_hp * (1 + armor) * (1 + regen_s * T_fight / core_hp) * (1 + shield_frac)
Survival condition:  EHP ≥ P(w,t) * T_wave * safety(1.5)
```

### 2.3 Power ratio (the governing number)
```
R(w) = DPS_eff / D(w,t)          (offence)
R_hp(w) = EHP / (P(w,t) * wave_time)   (defence floor)
```
**Target band at the frontier wave w\*** (the wave a typical player of that progress state dies on):

| Zone | R(w) | Meaning |
|---|---|---|
| Early run (w ≤ 0.5 w\*) | 2.0 – 4.0 | power fantasy, picks feel strong |
| Mid run | 1.25 – 2.0 | |
| **Frontier w\*** | **0.80 – 1.25** | death happens here; decisions matter |
| w\* + 5 | < 0.6 | wall — must leave the run to grow |

R_hp(w\*) must stay ≥ 1.0 for any build that respects the 25% EHP floor (no instant-death via dmg).

### 2.4 Power sources and their growth law (per lifetime progress)
Each source multiplies; budget their **share of log-power at the frontier** so no layer dominates:

| Layer | Grows with | Target share of log(M_total) at w\*≈60 |
|---|---|---|
| In-run cash upgrades (core level) | cash in run | 30% |
| Roguelite picks (buildings/packs/troops/specials) | wave/XP in run | 30% |
| Parts (+ sets) | crates, drops, scrap | 20% |
| Core (type, perm level, slots) | coins | 10% |
| Reforge shards + Insight | prestige loops | 10% (grows to ~25% late) |

---

## 3. In-run cash economy (matches difficulty within a run)

Current code: kill cash is **flat** per enemy (drone 1), plus `cash_ps`. Core upgrade cost
`8 * 1.4^lvl`; building upgrade `8 * 1.3^(lvl-1)`.

Matching rule. If an upgrade costs `c0 * g_c^L` and multiplies DPS by `m`, then power from cash `C`
is `C^(ln m / ln g_c)`. To track `D(w) ∝ g_D^w`, cumulative cash must grow
```
C(w) ∝ g_D^( w * ln g_c / ln m )
```
Core: `g_c=1.4, m=1.15` ⇒ exponent 2.41 ⇒ cash must grow `1.17^(2.41 w)` — impossible with flat kills.
**Required change:** scale kill cash `cash_e(w) = base_cash_e * k_c^(w-1)` and lower cost growth.

Targets (tunable, `cash_wave_growth`, `core_run_growth`, `core_run_mult`):

| Knob | Value | Effect |
|---|---|---|
| `cash_wave_growth` k_c | 1.10 | income/wave after cap ≈ 55.6 * 1.10^w |
| `core_run_growth` g_c | 1.18 | cost per core level |
| core level DPS mult m | 1.12 | |
| → power from cash grows | `1.10^(w*ln1.12/ln1.18)=1.10^(0.686w)=1.067^w` | |
| roguelite picks (≈1 per 1.5 waves, avg ×1.08 log-step) | 1.053^w | |
| **total in-run growth** | 1.067·1.053 ≈ **1.124/w** | vs D 1.17/w ⇒ gap 1.041/w |

The 1.041/wave gap is intentional: it is the "wall" that meta power (parts, core, shards, insight)
closes. Frontier moves when meta multiplier rises by 1.041^Δw: **+10 waves ⇔ ×1.49 meta power.**

Invariant (in run): cash income per wave grows within ±0.02 of `k_c` per wave; and
`cost(next core level) / cash_per_wave ∈ [0.5, 2.0]` from w=5 to w\*.

---

## 4. Meta currencies — income exponents

Let `w*` be the frontier, `L` = lifetime coins. Difficulty to push frontier by +1 wave costs ×1.041
meta power (§3). Every currency's **cost curve of what it buys** is set so the expected time to
earn +1 wave of power is roughly constant (≈ 1 run early, 2–3 runs late).

| Currency | Source | Income per run ∝ | Spent on (cost growth) | Power per spend |
|---|---|---|---|---|
| cash | kills in run | `1.10^w` per wave | core lvl 1.18^L, buildings 1.25^L | ×1.12 / ×1.25 |
| coins | kills (0.2 drone…), boss 10, wave clear | `coins_run ≈ c1 * 1.09^w*` (scale coin drop `coin_wave_growth` 1.09) | perm core 30·1.5^L, Outpost builds | ×1.08 / lvl |
| scrap | salvaging parts, drops | `≈ 1.06^w*` | part upgrade `20·1.35^L` | part +6%/lvl of its primary |
| gems (premium) | Gem Mine, achievements, bosses ≥w50 | ~flat (+ mine level linear) | crates, slots, cosmetics | none direct (convenience) |
| keys | boss kills (1/10 waves), missions | linear in w\* | crates | parts (power via §5) |
| shards | Reforge | `k*sqrt(L)` (§6) | perm tree 1·1.6^n | ×1.05 dmg / node (multiplicative within branch, additive across) |
| insight | super-rare picks (p≈1% per pick, ≤1 per run) | ~flat | n/a | +0.5% permanent stat, cap 25% per stat |

Matching check: coins per run grow 1.09^w\*; perm core cost grows 1.5^L, each level ×1.08.
Power bought per run ∝ `(1.09^w*)^(ln1.08/ln1.5)=1.09^(0.19w*)` — slow on purpose; coins mainly fund
the Outpost (§5) and core unlocks, while parts/shards carry the late game.

---

## 5. Outpost income

Outpost production replaces the old Offline formula (save migration: old offline rate → initial
storage; old permanent buildings → refund in coins at 100%).

```
outpost_coin_rate = Σ gen_i * lvl_mult(lvl_i) * adj_i * link_i      [coins / hour]
stored = min(rate * elapsed, storage_cap)          storage_cap = 8 h of rate by default (silo ups → 12/16 h)
active_coin_rate  = coins_run_avg(w*) / run_minutes * 60
```
**Target: outpost_coin_rate / active_coin_rate ∈ [0.15, 0.35]** at equal wall-clock time, evaluated
for an "average-invested" Outpost at each progress stage. It must never exceed 0.35 (playing must
stay best) and should reach 0.15 by the end of day 1.

| Stage | w\* | active coins/h | outpost target coins/h | Gem Mine gems/day |
|---|---|---|---|---|
| Day 1 | 20 | 600 | 90 – 210 | 5 |
| Day 3 | 35 | 2 200 | 330 – 770 | 10 |
| Week 1 | 50 | 7 500 | 1 100 – 2 600 | 15 |
| Week 3 | 70 | 42 000 | 6 300 – 14 700 | 25 |

Generator cost growth `1.45^lvl`, output growth `1.25^lvl` ⇒ ROI time grows 1.16^lvl; keep ROI
payback of the *cheapest* available upgrade between 2 h and 24 h. Adjacency/connectivity bonuses
total ≤ +60% (a good layout is worth ≈ 1.5x a random one — strategic, not mandatory).
Scrap/keys from Outpost: ≤ 20% of active rate. Gems: Gem Mine only, hard daily cap.

---

## 6. Core Reforge (prestige)

```
shards(L) = floor( k * sqrt(L / L0) ),   k = 1, L0 = 10 000 coins   (pc_reforge_k, pc_reforge_l0)
first reforge allowed at w* ≥ 40 (≈ 25 shards)
shard_mult = Π over tree branches (1 + 0.05 * nodes_in_branch)  (node cost 1.6^n shards)
Keeps: parts, part levels, core types, Outpost.  Resets: coins, core perm levels, frontier, run unlocks.
```
Loop speed requirement: each loop reaches previous best w\*\_prev **≥ 30% faster** (wall clock) than
the previous loop did. Since the meta power wall costs ×1.49 per 10 waves, a reforge granting
shard_mult step `σ` saves `10*ln σ/ln 1.49` waves of grind. Target σ per loop:

| Loop | lifetime L at reforge | shards gained | cum shards | shard_mult | time to prev best | loop length |
|---|---|---|---|---|---|---|
| 1 | 6e5 | 7–8 (+gate bonus to 25) | 25 | 1.6 | — | 4–6 days |
| 2 | 2.5e6 | 16 | 41 | 2.1 | ≤ 70% of loop 1 | 3–5 days |
| 3 | 8e6 | 28 | 69 | 2.9 | ≤ 70% of loop 2 | 3–5 days |
| 4 | 2.5e7 | 50 | 119 | 4.0 | ≤ 70% of loop 3 | 3–6 days |

Rule of thumb: reforge is "worth it" when `shards(L_now) ≥ 0.5 * cum_shards`; the UI shows this.
New best per loop should exceed old best by +8–15 waves.

---

## 7. Archetype viability

Specs: **balanced, eco, single-weapon, damage (overall)**, plus troops and specials as sub-specs.
For each spec, the playtest bot builds a canonical loadout (parts + core + pick policy) of equal
total investment and measures frontier wave w\*\_spec and normalised score
`V_spec = DPS_eff(w*_best) * (eco ? (1 + cash_bonus)^0.69 : 1)` (eco's extra cash converted via §3).

**Invariant:** `w*_spec ≥ w*_best - 3` AND `V_spec ≥ 0.85 * V_best` for every spec at every
stage (day 1, day 3, week 1, week 3). Eco must also yield ≥ +20% coins/run vs balanced (its payoff),
single-weapon ≥ +25% boss DPS (its payoff), damage ≥ +15% raw DPS with ≥ −20% EHP (its cost).

---

## 8. Part trade-off valuation (no dominant part)

Every part has a **budget** in log-power units:
```
value(part) = Σ_k  w_k * ln(1 + stat_k)      (stat_k signed; negatives are the trade-off)
weights w_k: dmg 1.0, rate 1.0, core_hp 0.5, regen 0.4, cash 0.69, coin 0.3, range 0.3, crit (expected) 1.0
budget(rarity, lvl) = B_r * (1 + 0.06*(lvl-1))      B_r: common .08, rare .12, epic .17, legendary .24, special .30
```
Rules:
1. `|value(part) - budget| ≤ 0.10 * budget` — validated by a data test over `PartDB`.
2. Every part has ≥ 1 negative stat with `|neg contribution| ≥ 0.25 * positive contribution`.
3. **Pareto check:** no part may weakly dominate another of the same slot & rarity on all stats.
4. Set bonuses: 2-piece ≤ +0.5 B_r, 4-piece ≤ +1.2 B_r, and only conditional on the set's spec
   (e.g. eco set's 4p only boosts cash), so mixing sets ≈ full set ± 10% for balanced.
5. Diminishing stacking: same stat from multiple parts sums additively inside `(1 + Σ)` (not
   multiplicatively), so piling one stat loses ~15–25% vs spreading, unless it is the spec's focus
   stat, which gets the set multiplier — this is what makes specs real choices.
6. Slots: core level adds slots at levels 1/5/10/20/35 (3→7); each slot ≈ +B_r log-power ≈ +1.5 waves.

---

## 9. Concrete playtest invariants (for `playtest.gd`)

| ID | Invariant |
|---|---|
| PM-1 | `D(w)` from PowerModel equals engine's measured spawn HP/s within 5% for w∈{1,10,20,40}. |
| PM-2 | Fresh save, bot balanced: dies in w∈[12,25]; `R(w*) ∈ [0.8, 1.25]` at death wave. |
| PM-3 | Early-run R(w ≤ w*/2) ≥ 2.0. |
| PM-4 | R(w*+5) < 0.6 (wall exists — no infinite runs at any stage). |
| PM-5 | Cash/wave growth ratio within [1.08, 1.12] for w∈[20,w*]. |
| PM-6 | Outpost/active coin ratio ∈ [0.15, 0.35] for the 4 stage snapshots. |
| PM-7 | Storage cap reached between 6 h and 16 h. |
| PM-8 | Reforge loop n reaches prev best in ≤ 0.70× loop n-1 time (sim). |
| PM-9 | shards(L) = floor(k*sqrt(L/L0)); monotonic, deterministic. |
| PM-10 | Each spec frontier ≥ best−3 and V ≥ 0.85 V_best. |
| PM-11 | All parts within budget ±10%, each has a real negative, no Pareto domination. |
| PM-12 | Insight per stat capped at +25%; drop rate ≤ 1 per run, p≈1% per pick. |
| PM-13 | Meta multiplier needed for +10 waves ∈ [1.35, 1.65]. |
| PM-14 | R_hp(w*) ≥ 1.0 for builds honoring the 25% EHP floor. |

---

## 10. `PowerModel.gd` API (pure, static, no autoload, no RNG)

```gdscript
class_name PowerModel  # preload("res://PowerModel.gd"); all funcs static, all args typed
# difficulty
static func hp_scale(wave: int, tier: int, endless: bool = false) -> float
static func spawn_interval(wave: int) -> float
static func spawns_per_wave(wave: int) -> float
static func enemy_hp(kind: String, wave: int, tier: int) -> float
static func enemy_dmg(kind: String, wave: int, tier: int) -> float
static func required_dps(wave: int, tier: int) -> float
static func damage_pressure(wave: int, tier: int, leak_frac: float) -> float
# player
static func effective_dps(snap: Dictionary) -> float        # snap from TowerState.power_snapshot()
static func ehp(snap: Dictionary) -> float
static func power_ratio(snap: Dictionary, wave: int, tier: int) -> float
static func hp_ratio(snap: Dictionary, wave: int, tier: int) -> float
static func frontier_wave(snap: Dictionary, tier: int, max_wave: int = 300) -> int  # first w with R<0.8... returns w where R crosses 1.0
static func meta_mult(meta: Dictionary) -> float            # parts*core*shards*insight
static func band(zone: String) -> Vector2                   # "early","mid","frontier","wall"
# economy
static func cash_per_wave(wave: int, tier: int) -> float
static func coins_per_run(frontier: int, tier: int) -> float
static func outpost_rate(outpost: Dictionary) -> float      # coins/hour
static func outpost_ratio(outpost: Dictionary, frontier: int, tier: int, run_minutes: float) -> float
static func outpost_collect(outpost: Dictionary, elapsed_s: float) -> float  # capped, now injected by caller
static func shards_for(lifetime_coins: float) -> int
static func shard_mult(tree: Dictionary) -> float
static func reforge_worth(lifetime_coins: float, cum_shards: int) -> bool
# parts
static func part_value(part: Dictionary) -> float
static func part_budget(rarity: String, lvl: int) -> float
static func dominates(a: Dictionary, b: Dictionary) -> bool
static func spec_score(snap: Dictionary, spec: String, wave: int, tier: int) -> float
```
`TowerState` exposes `power_snapshot() -> Dictionary` (core dmg/rate/hp/regen, building DPS list,
troops, specials, global mults); the view never calls PowerModel for rules. All constants read via
`TuneRef.num(key, default)` with defaults equal to this document's tables.
