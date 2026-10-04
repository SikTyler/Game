# Corehold PC: balance and QA pass

This pass is for the PC edition only (`games/towerdef-pc-0001`). The mobile copy was not touched. All numbers come from `res://playtest.gd`: seed 4242, the deterministic competent bot, a 30-day campaign with 4 sessions a day, and DT 0.1. Times are simulated seconds at 1x speed.

## Changes (data and tune knobs only)

| knob | before | after | why |
|---|---|---|---|
| `ModifierDB` glass coin | +0.40 | +0.15 | cost about 0.3 waves but paid 1.39x |
| swarm | +0.25 | +0.10 | cost about 1 wave but paid 1.35x |
| ironclad | +0.35 | +0.30 | costs 2.5 waves; trimmed slightly |
| poverty (Austerity) | +0.30 | +0.10 | cost 0 waves but paid 1.30x |
| allsides (Encircled) | +0.45 | +0.10 | the bot reached a *higher* wave (+0.7 to +1.5) because the 7x7 ring covers all four lanes, yet it paid 1.46x |
| noperks (Purist) | +0.30 | +0.55 | costs about 6 waves and paid only 1.03x |
| haste | +0.30 | +0.10 | cost 0 waves but paid 1.29x |
| elitist | +0.35 | +0.40 | costs 4 to 5 waves |
| nolabs (Fresh Start) | +0.50 | +0.60 | costs about 4.5 waves and paid only 1.07x |
| `MUTATION_COIN` | 0.10 | 0.15 | each endless mutation buffs enemies by 10 to 25% |
| `pc_endless_coin_mult` | 0.8 | 0.9 | endless runs end at the same wave as normal runs, so x0.8 made endless a strict loss (0.82x) |

`COIN_CAP` stays at 3.0. The rewards now add up to 2.40, so stacking every modifier still hits the cap. The selftests now read modifier rewards from `ModifierDB.DEFS` instead of hardcoding them; they still check the same formula. The UI text and PC_SPEC were updated to the new values.

## Modifier fairness (day-20 save, seeds 4253/4300, same save vs no modifier)

Baseline: wave 55.0, 42,989 coins per run.

| modifier | wave delta | coin ratio |
|---|---|---|
| Glass Core | -0.5 | 1.14 |
| Swarm | -1.5 | 1.16 |
| Ironclad | -2.5 | 1.21 |
| Austerity | 0.0 | 1.10 |
| Encircled | +1.5 | 1.12 |
| Purist | -6.0 | 1.19 |
| Haste | 0.0 | 1.09 |
| Elite Guard | -4.0 | 1.34 |
| Fresh Start | -4.5 | 1.11 |

Before this pass the spread was 1.03 to 1.46, and the easiest modifiers paid the most. Now every modifier pays 1.09 to 1.34. The hardest ones pay the most, and no modifier gives a large reward for free. Some modifiers cost 0 waves for this bot: haste, poverty, glass, and allsides. That means their difficulty is mostly felt by human players, through tighter cash and less forgiveness, so their reward is kept small at +0.10 to +0.15.

**New gate `pc_modifiers_fair`:** each modifier's coin ratio must be between 0.9 and 1.4, and a modifier that costs 1.5 waves or less may not pay more than 1.25x.

## Endless (day-20 save)

Endless reached wave 55 with 2 mutations in 544 s, and its coin ratio vs a same-seed normal run was 0.99 (it was 0.82 before). Endless is now a real alternative that pays about the same coins. It still does not replace tier progression, because it keeps its own best and does not advance tier bests. **The `pc_endless_runs` gate now also needs a coin ratio between 0.80 and 1.15.**

## Eco vs defense on 7x7 (unchanged and still holding)

- Week 1 campaign: balanced reached T2 at wave 42, pure weapon T1 at wave 30, pure eco T1 at wave 10. Mixing wins.
- In-run policy on the same save:
  - Day 7: balanced 41.7 waves / 9.3k coins, weapon 42.0 / 8.5k, eco 19.3 / 4.8k.
  - Day 20: balanced 54.7 / 41.2k, weapon 55.3 / 39.4k, eco 20.0 / 15.5k.
  - Weapon-only matches balanced on waves but earns less. Eco-only collapses.
- Mono boards: the best was 49 waves vs 54 for balanced at day 20, under the 70% bar.
- Refinery vs Mine swap: 1.06x at day 7 and 0.97x at day 20, with 1 to 2 fewer waves. That is a real trade, not a dominant choice.
- Perks: the top always-take coin ratio is 1.36 (Greed), within the existing dominance bar.

## Campaign pacing and session length

| metric | value |
|---|---|
| day-1 best wave | 30 (band 18 to 32) |
| T2 / T3 day | 4 / 13; final tier 4 |
| best wave at T3 / day-30 best in highest tier | 53 / 63 |
| run length | about 4 min (wave 10) on run 1, 8 min (wave 20), 12 min (wave 30), about 9 min at the day-20 high tier |
| active coin rate / offline rate | 2986 / 373 per min (offline is 12% of active, within the 20% cap) |
| gems/day | 23.9 (top source: missions, 50% or less) |

At 1x speed, active runs last 8 to 12 minutes, which fits a PC sitting. With game speed up to 3x, a player can compress this. I left the wave timing alone: changing it would shift every campaign gate (day-1 band, T2 by day 5, offline cap) for no measured gain.

## Open items

- From days 19 to 28 the best wave stays at 60 to 61 at T4. The gates pass because the progress key includes tier, but the late T4 curve is flat. A future pass could add a T5 or tune `hp_growth_hi` for T4.
- Modifier difficulty is measured by one bot. Haste, Austerity, and Glass Core probably feel harder to humans than the 0-wave cost the bot shows. Revisit after human playtests.
