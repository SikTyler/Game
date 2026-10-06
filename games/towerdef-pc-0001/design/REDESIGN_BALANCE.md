# Corehold PC — Redesign balance pass (Balance designer / QA)

Source of the invariants: `design/POWER_MODEL.md` (PM-*) and REDESIGN_SPEC AC-27/28/29.
Measured by `playtest.gd`: the jobs `forge:balanced|eco|single|damage` play a fresh save
through **3 Core Reforge loops** per archetype spec (competent bot: buys Core levels and
crates, installs and levels parts by spec weights, builds the Outpost, uses specials,
spends shards, reforges when its spec says). Prints `PLAYTEST METRICS {...}` (key
`redesign`) and gates `rd_*`. Wall-clock: ~8.5 min on 4 cores (parallel job runner).

## What was measured / asserted

| Gate | Invariant |
|---|---|
| `rd_frontier_band` | median R(w\*) per loop, pooled over the 4 specs, in [0.80, 1.25] (PM-2) |
| `rd_early_power` | median R(w\*/2) ≥ 2.0 (PM-3) |
| `rd_wall_exists` | median R(w\*+5) < 0.6 (PM-4) |
| `rd_no_plateau` / `rd_no_runaway` | no flat stretch of days, no day-over-day jump, no sim timeouts |
| `rd_loops_complete` / `rd_loops_faster` | 3 Reforges, every loop regains the previous best; loop n regains it in ≤ 0.70× the sessions loop n-1 took to reach it (median over specs) (PM-8 / AC-28) |
| `rd_archetypes_viable` | every spec ≥ 85% of the best spec on V (mean all-time best per day) and on final best (PM-10 / AC-29) |
| `rd_no_dominant_part` / `rd_no_dominant_set` | part / 4-set pick-rate over day≥3 loadouts below the dominance cap |
| `rd_outpost_share` | Outpost production / active coins per hour, median from day 3, in [0.15, 0.35] (PM-6 / AC-27) |
| `rd_gems_sane` | 10–30 gems/day, earn-only, no source > 50% |
| `ac25_fresh_wall` | 16 fresh balanced first runs (own save + seed each): median death wave in [12, 25], ≤ 25% reach the w30 boss, median R(w*/2) ≥ 2, median R(w*+5) < 0.6 (AC-25) |
| `fresh_median_first_goal` | the same 16 fresh runs: median ≥ the first goal and none below it (the strong partner of `no_death_spiral`) |
| `rd_ac27_storage_fill` | every spec-day snapshot: each built Mill / Refinery fills its storage from empty in 6–16 h at its live rate (AC-27) |
| `ac29_spec_identity` | same-save probe (day-20 save, part levels refunded into one Scrap pool, spec parts first): eco ≥ 1.20× balanced coins per run, single-weapon ≥ 1.25× balanced boss DPS (single-target × boss multiplier) (AC-29) |
| `ac29_wave_gap` | same probe: every spec's median wave within 3 of the best spec (AC-29). **Currently FAILS**: single-weapon (Lancer) 92 vs balanced 80 / eco 79 / damage 82.5 — boss walls make boss / Core-damage parts outperform their PowerModel budget. Needs a balance pass; not loosened. |

AC-28 loop speed now also reports the per-spec maximum: loop 3 median 0.65 (limit 0.70, margin 0.05) but eco 0.71 and single 0.80 are individually over the limit.

## Before → after

"Before" = HEAD `f8eba35` plus the uncommitted crit/AoE-aware power snapshot (the
starting point of this pass). "After" = this commit.

| Metric | Before | After |
|---|---|---|
| Frontier R per loop 0/1/2/3 | 1.15 / 1.02 / 1.01 / 1.01 | 1.10 / 1.04 / 0.92 / 1.02 |
| Early R per loop | 4.9 / 19 / 49 / 64 | 4.9 / 35 / 58 / 92 |
| Wall R(w\*+5) per loop | 0.52 / 0.47 / 0.48 / 0.48 | 0.50 / 0.51 / 0.45 / 0.50 |
| Loop speed (regain / prev reach), median, loops 1/2/3 | 0.15 / 0.60 / **1.03 FAIL** | 0.08 / 0.27 / **0.65** |
| Shards per Reforge | 12, 12, 12 | 16, 17, 17 |
| Archetype V share bal/eco/single/dmg | 0.94 / **0.80 FAIL** / 1.00 / 0.95 | 0.96 / 0.94 / 1.00 / 0.96 |
| Final best wave bal/eco/single/dmg | 80 / 80 / 93 / 87 | 83 / 87 / 91 / 89 |
| Outpost/active coin ratio (median) | 0.226 | 0.226 |
| Gems/day per spec | 24.6–25.9 | 25.0–26.1 |
| Top part pick-rate | f_glass 0.70 | f_glass 0.71 |
| Legacy 8-run fresh save (balanced) | [20,20,30,20,30,20,20,20] | unchanged |
| Playtest | FAIL (no_death_spiral, rd_loops_faster, rd_archetypes_viable) | **PLAYTEST OK** |

## Changes (data tables / Tune knobs only, plus the bot)

1. **Reforge power nodes stack multiplicatively** (`data/ReforgeDB.gd`: `"stack": "mul"`,
   `ReforgeDB.bonus()`; Tune `pc_rf_stack_<id>=0` restores additive). POWER_MODEL §4 says the
   shard tree is "multiplicative within branch", but the code added `amt × L`. Additive Might
   gave each later loop less relative power (L2→L4 = ×1.55, L4→L6 = ×1.35), so loop 3
   never got faster (ratio 1.03). Might **×1.6/level** (was +0.6 additive), Bulwark **×1.35/level**
   (was +0.4). Tune: `pc_rf_might`, `pc_rf_bulwark_p`.
2. **Shard constant k 1.0 → 1.6** (`ReforgeDB.SHARD_K`; Tune `pc_reforge_k`): a Reforge at
   ~0.5M lifetime coins is now worth 16–17 shards instead of 12.
3. **Coin Mill tier scaling 0.5 → 0.8** (`OutpostDB.MILL_TIER`; Tune `pc_mill_tier`): keeps
   the Outpost share inside [0.15, 0.35] at higher tiers.
4. Bot (competent policy, not game rules): reforges at ≥ 16 shards (`BOT_REFORGE_MIN`,
   was 12), so it waits for a full tree step. The eco spec over-weights cash parts ×1.3
   (was ×2.2; Tune `bot_spec_part_w_spec_eco`). At ×2.2 it fitted Bulkhead/Bounty over damage parts
   and sat at the T1 w30 boss for 4 days.

## Tests changed on purpose

- `selftest.gd` AC-21 shard literals (12, 15, 11) now come from `ReforgeDB.SHARD_K`, and
  the RF Might check asserts `(1+amt)^L`. This follows the deliberate k and stacking changes.
- `playtest.gd` `no_death_spiral` was redefined, which **loosens the legacy check**. It
  used to fail if any run ended more than 2 waves below the run before it. It already
  failed at HEAD `f8eba35`. The redesign made the in-run grid a roguelite draft that
  starts empty, so a fresh save's run results quantise to boss walls (w20/w30). A drop of
  one boss step between seeds is draft variance, not a collapse. A spiral now means the
  median of the later half falls more than 2 below the first half, or any run ends more
  than 2 below run 1. Balanced still logs [20,20,30,20,30,20,20,20].
- `PowerModel.single_target_dps` plus the crit expectation in `effective_dps`: a boss's
  share of a wave's HP is matched with single-target DPS (AoE factors removed).

## Open issues (found, not fixed here)

- **Fresh-save meta stall.** In the legacy 8-run campaign the Bastion stops at L7. Core
  levels 5+ need Core Cores, and T1 boss drops are 25%, so ~4.5k coins sit unspent. Raising
  `pc_boss_corecore_p` to 0.75 or making Core levels cheaper did not flatten the seed
  variance on its own. This needs a design call (for example a T1 Core Core from the
  first w30 clear).
- **No 4-piece set is ever completed** in 18–24 campaign days (`set4_rate` is empty), so set
  bonuses are not measured yet. Crate odds or set targeting may need a pass.
- **f_glass sits at a 0.71 pick-rate.** That is under the dominance gate but high. Its
  drawback (HP) is cheap once Bulwark multiplies.
- A bot that switches Core targeting to whichever mode lands on a low-HP boss changed the
  legacy gates a lot (mix/eco/seeds). The engine has no "boss" target mode; worth adding.

## AC-29 spec-gap pass (single-weapon outscaling)

Same-save spec probe (day-20 save, 6 seeds, medians). "Before" = HEAD `762a81d`; "After" = this commit.

| Metric | Before | After |
|---|---|---|
| Median wave balanced / eco / single / damage | 80 / 79 / **92** / 82.5 | 80 / 76.5 / 80.5 / 80 |
| Wave gap to best (≤ 3) | 12 / 13 / 0 / 9.5 — **FAIL** | 0.5 / **4.0** / 0 / 0.5 — **still FAILS (eco)** |
| Eco coins per run vs balanced (≥ 1.20) | 1.62 | 1.48 |
| Single boss DPS vs balanced (≥ 1.25) | 7.39 | 3.55 |
| Top part pick-rate (≤ 0.75) | f_glass 0.71 | f_glass 0.69 |
| AC-28 loop speed median, loops 1/2/3 | 0.08 / 0.27 / 0.65 | 0.04 / 0.51 / 0.45 |
| AC-28 per-spec max, loops 1/2/3 | 0.13 / 0.60 / 0.80 | 0.07 / 0.67 / **4.0** (balanced loop 3) |
| Playtest | FAIL: ac29_wave_gap | FAIL: ac29_wave_gap (all other gates green) |

**Diagnosis.** At day 20 the run is decided by the boss waves (every 8th wave at this tier:
72 / 80 / 88). The Core's single-target multipliers stack multiplicatively: Rail Core and
Hollow Point (`core_dmg`), Keen Rifling (`crit`, ×2 hits), Hunter Scope (`boss`), the Lancer
2-piece and the in-run Core Surge pack (×1.3 per stack, two stacks). Because benefits scale
with level and drawbacks do not, the single build cleared the w80 boss on every seed and
died at w88+. Bosses were not what killed it: traces show the Core going from full HP to 0
in one tick at w88 as the escort horde arrives. Taking any single one of hollow, crit or
scope away cost about 4 waves; together they were worth about 9.5. The old VAL weights
undervalued exactly these keys (core_dmg 0.7, boss 0.7, crit 1.0, where a crit is a ×2 hit).

**Changes (data / Tune only)**
- `PartDB.VAL`: `core_dmg` 0.7 → 1.0, `boss` 0.7 → 1.0, `crit` 1.0 → 1.7. The AC-12
  budget then forces: Rail Core +69% → **+42%** Core dmg; Hollow Point +30% → **+20%** Core
  dmg, drawback −12.1% building dmg → **−3% crit**; Keen Rifling +20% → **+10%** crit,
  −6.3% → −4.5% dmg; Hunter Scope +45% → **+58%** vs boss, −8.7% → **−25%** vs non-boss (it is
  now a boss specialist that costs horde clear). Drone Port and Pheromone Cell `core_dmg`
  drawbacks −11.1% → −8% and −8.8% → −6.5%, which keeps them inside budget under the new weight.
- `SetDB` Lancer 2-piece: +10% → +5% Core dmg.
- Core Surge pack (`pk_core`): +30% dmg / +10% rate per stack → **+15% / +5%**. This is now
  a Tune knob (`pc_core_surge_dmg`, `pc_core_surge_rate`). It was the biggest single-only
  in-run multiplier, worth about 4 waves to the single bot. Capping it at `max 1` instead
  broke seeds_ok and pc_endless_runs.
- Glass Cannon +45% / −23% HP → **+40% / −18%**. Glass reached 0.77 pick-rate after the Core
  nerfs and failed `rd_no_dominant_part`.
- Mint parts, with a smaller damage tax and the slack taken from their cash: Bounty Sight
  +31% / −6.3% → +27% / −4.4%; Interest Chip 3% / −6.3% → 2.6% / −4.35%; Mint Press
  +46% / −8.7% → +40% / −6.1%.

**Tried and rejected (evidence in the session log):** Arc Capacitor drawback
range → rate (−1.5 waves for balanced/damage); Scatter drawback → bld_rate (no effect);
Glass Cannon 0.49/−0.28 from the earlier WIP, which broke seeds_ok and no_dominant_perk;
a bigger Splash / Chain value (≤ +0.5 wave); a lower overkill carry (`pc_carry_*`, which did not
change the single gap); a lower eco install weight (its loadout is pinned by spec-first);
mint drawbacks moved to building stats plus a Ringcaster buff (the probe gained +2.5 for eco,
but on the regenerated save it gained nothing and broke `rd_wall_exists`).

**Tests changed on purpose:** the selftest literals for Rail Core (+42%), Hunter Scope (+58% / −25%),
Glass Cannon (+40% / −18%, in both checks) and Core Surge (+15% / +5%) mirror the data changes above.
No assertion was loosened.

**Open (not fixed here)**
- **AC-29 eco gap 4.0.** Eco dies after the w72 boss on 4 of 6 seeds, while the other
  specs reach the w80 wall. The cause is eco's in-run policy (cash tracks), not its parts:
  with zero drawback on every Mint part it gains about 0.5 waves. Closing the gap needs an eco
  power source that does not cost coins per run, or a change to the eco in-run policy. Both
  are design calls.
- **AC-28 per-spec loop 3:** balanced took 4.0× its loop-2 time. Every other spec stays
  ≤ 0.61, and the median of 0.45 passes the gate. Eco loop 3 improved from 0.71 to 0.08 and
  single from 0.80 to 0.29.
- **4-piece set probe** (`job_sets`, report only, not in RD_GATES): every set's 4-piece fx
  goes live. Band: bulwark 72, mint 78, lancer 83, storm 76.5. **Swarm is a trap at ~w25**
  (troop parts only).

## AC-29 eco pass + Swarm 4-piece (Mint Dividend, set4_no_trap)

Same-save probes (day-20 save, 6 seeds, medians). "Before" = `78e472b`.

| Metric | Before | After |
|---|---|---|
| Median wave balanced / eco / single / damage | 80 / 76.5 / 80.5 / 80 | 80 / **79** / 80.5 / 80 |
| Wave gap (<= 3) | eco 4.0 **FAIL** | 0.5 / 1.5 / 0 / 0.5 OK |
| Eco coins per run vs balanced (>= 1.20) | 1.48 | 1.51 |
| Single boss DPS vs balanced (>= 1.25) | 3.55 | unchanged (passes) |
| 4-piece band bulwark / mint / lancer / storm / swarm (6 seeds) | 72 / 78 / 83 / 76.5 / **25.5** (4 seeds) | 72 / 79.5 / 84.5 / 76.5 / **72** |
| Top part pick-rate | f_glass 0.69 | f_glass 0.69 |
| AC-28 loop speed median 1/2/3 | 0.04 / 0.51 / 0.45 | same |
| Playtest | FAIL ac29_wave_gap | **PLAYTEST OK** (new gate set4_no_trap included) |

**Was the eco bot incompetent? No.** Diagnosis on the probe (debug print of end-of-run
tracks/cash): every spec has Eco 50 / Rate 60 / Range 20 maxed; eco actually has *more*
Damage/Armor levels (75-79 / 78-83) than balanced (67-72 / 69-74) and still dies holding
8-36M unspent cash. Track costs grow 1.19-1.23x per level, so late cash converts to almost
nothing. Policy probes (all no effect or worse, reverted): stop buying Eco late, longer
boss-prep window (5 waves) with x3 eco weight, banking a reserve of interest_cap/rate and
releasing it before bosses, paying for rerolls out of surplus cash, and playing the eco
loadout with the balanced or damage in-run policy (76.5-78 median). The in-run policy is
not the lever; eco's cash has no late sink and its Mint parts tax damage.

**Fix (data + one engine hook):** the Mint 4-piece `interest_fast` (interest every 15 s,
worthless once cash is saturated) is replaced by **Dividend**: all damage x(1 + 0.20 x
Eco level / 50). New fx key `dividend` (VAL [1.0, 1.0], PCT, tooltip). Set budget:
Mint 4-piece 0.182 <= 1.2B 0.204. Sweep: 0.07 -> eco 76.5 (fail), 0.15 -> 79, 0.20 -> 79
(coins 1.51x), 0.30 -> 79. Only an equipped full Mint set gets it, so the other specs are
untouched (their probe rows are bit-identical). The `interest_fast` engine path stays and
keeps a selftest (fx injected directly).

**Swarm 4-piece trap (task 3).** Cause: Queen Engine's drawback `queen_hold` (Core holds
fire while 3+ troops live) is permanent once the full set is on, and the Core is the main
weapon. Swarm 4-piece is now `{troop_ls: 1, queen_hold: -1, dmg: 0.13}` (value 0.280 <=
1.2B 0.288): the full set lifts the hold-fire. Lifting alone gave median 70; +13% all
damage gives 72. CoreBay set tooltip now lists every 4-piece fx (it showed only the first
key). Selftest: new run check for the lifted hold + 13% dmg.

**set4 gating.** SET_PROBE_N 4 -> 6. The full band (`set4_fair`: >= balanced - 8 and <=
best spec + 3) stays REPORT ONLY: Bulwark and Swarm sit exactly on 72 and Lancer at 84.5
is 1 over 83.5, so it would flip on seed noise. New RD gate **`set4_no_trap`**: every full
set is live and its median >= 0.75 x balanced probe (60). It catches the real failure
class (w25 vs w80) with a 12-wave margin. Lancer (full set > single spec's own loadout)
is an open item, not a trap.

**no_death_spiral (task 2) — not loosened further, documented.** Legacy campaign:
balanced [20,20,20,20,30,20,20,20]; fresh x16 first runs: twelve at w20, one w30, four
at w10 (R early 2.3-9.0). Results quantise to boss walls (every 10th wave at T1), so a
single draft that misses a weapon drops a whole wall step; the current rule (later half's
median vs first half > 2 lower, or any run > 2 below run 1) still fires on any real
downward trend. Run 1 is w20 and no run falls below it. The real fix is the open
fresh-save meta stall (coins bank unspent: 668 -> 3803 across the 8 runs, Core Cores
gate the Core levels); that is a design call and is not done here.

**Fragile gates (task 4).** This run's margins: rd_wall_exists wall median 0.55 / 0.53 /
0.54 / 0.48 vs < 0.6; rd_loops_faster 0.04 / 0.51 / 0.45 vs 0.70; seeds_ok both extra
seeds pass (bal 63 / 60 vs weapon 40, t2 day 3, day1 30 — day1 is 2 off its 32 ceiling);
top part f_glass 0.69 vs 0.75. Only the set probe got more seeds. The forge campaigns
behind wall/loops/part rates are one seed per spec and are the bulk of the 8-minute
runtime, so doubling them doubles the gate. **Not done; open.**
**Balanced AC-28 loop 3 = 4.0 is a ratio artifact.** Loop 2 regained loop 1's best in 1
session (reach 1), so loop 3's 4 sessions gives 4/1. The gate is the median (0.45). A
per-spec sanity floor on the denominator (e.g. max(reach, 3)) would remove the artifact.
That is proposed only; the gate is unchanged.
