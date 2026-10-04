# Corehold: Balance Audit (economy designer pass)

Scope: every cost/production curve (permanent base, in-run cash, labs cost and duration,
tier multipliers, cards/chests/gems, offline), checked against `IDLE_MATH.md` heuristics
and measured with the `playtest.gd` 30-day campaign (seed 4242, plus seeds 9393 and 10504
for week 1). Changes were applied only through Tune knobs and data tables. SPEC/BRIEF-pinned
numbers (gem prices, streak ladder, chest 20, lab slots 60/150, tier unlock 20+10·T, card
values) were left alone. Where the audit suggests changing one, it is listed as a
proposal (section 4).

## 1. Method

- Baseline: one full `playtest.gd` run on HEAD (PLAYTEST OK).
- Candidates: one change at a time, each a full playtest run (about 5 min): Greed HP 1.5 and 1.7
  through `GF_TUNE`; Damage/Health lab `dur_growth` 1.45→1.40; Damage/Health lab cost
  `growth` 1.8→1.7 and 1.65.
- I kept only the change that moved the metrics I was targeting.

## 2. Findings per curve

| Curve | Formula (live) | Verdict |
|---|---|---|
| Perm base | unlock 90·1.45^n, upgrade 45·1.55^L, core 30·1.5^L; core cap 15 + 5/tier with ×1.1 Overdrive above 15 | Healthy. The base is the main coin sink through day 30, and Overdrive keeps late coins useful. The bank still climbs after about day 17 (100k to 230k idle). This is a **mild sink shortfall**, not a runaway. |
| In-run cash | level 8·1.3^n, core Overcharge 8·1.4^n (+2%+0.6%·perm core per level) | Healthy. Eco-mix wins week 1: w44 vs w30, 4.7× coins. Mono boards are below 70% of balanced. |
| Labs, cost | base·growth^L. Dmg/HP 80·1.8^L, coin/xp 1.35, startcash 1.40 | Coin/xp/startcash/offline/reroll/labspeed **all max out by day 18** (lab sum 112 of 144). After that only Damage/Health remain, and their **coin cost** is the limit (L≈13–15). Durations are not the limit: L13 takes about 4 h at 0.4× lab speed. Lowering cost growth to 1.7 or 1.65 added only 2–4 lab levels and 0 to −1 best wave by day 30, so the change was **rejected** (no gain, and it would have meant changing a selftest constant). |
| Labs, duration | dur_base·dur_growth^L × max(0.4, 1−0.06·labspeed) | First lab finishes in the first session (Starting Cash L0 = 3 min, Damage L0 = 5 min), so **the early hook is met**. dur_growth 1.45→1.40 on Damage/Health produced a **bit-identical campaign**, which confirms durations do not bind. Rejected. |
| Tiers | HP ×1.5^(T−1); coins ×(1+0.6·(T−1)); unlock at w(20+10·T) in T−1 | Tier gating is sound: T2 day 3–4, T3 day 11–12, T4 day 15–16. The T1 boss wall (boss_hp_t1 3.0 phased to w30) makes **days 1–3 flat at w30**, because T2 needs w40 in T1. AC-40 (T2 on day 3–5) requires this. The goal is visible from day 1 in the tier requirement text. |
| Perks | Greed: ×1.5 cash and coins; cost enemies +15% speed and ×`greed_enemy_hp` HP | **Greed is the coin-dominant pick.** On day 20 always-Greed earns 1.40× the median coins for −2.5 waves (`perk_top_coin_ratio` 1.38, band 1.0–1.15). It passes the gated `no_dominant_perk` check only because it costs waves. Raising its HP cost barely changes its coin edge (1.34) because damage scaling absorbs HP. The higher cost does make the *campaign* bot (which takes Greed for the tradeoff mission) pay for it in waves, which smooths the midgame (see section 3). |
| Cards/chests | chest 20 gems; 8 cards × 5 levels; slots 30/60/100 | First card arrives on **day 4** in the bot (target: day 1–2). The cause is not price: the bot spends its first 60 gems on lab slot 3. A player who opens a chest first gets one on day 2 (41 gems earned by then). Distinct cards reach 6 of 8 by day 30. The duplicate/level tail keeps chests useful long-term. |
| Gems | boss ≤3/run (T3+ 2 each, daily allowance 10), missions, streak, tier | 24 gems/day (band 15–30). Top source is missions at 44% (≤ 50%). OK. Gems pile up on days 9–12 (up to 130) while the bot saves for lab slot 4 (150). This is a visible goal, not a leak. |
| Offline | 15% of the best coin rate × min(elapsed, cap 4 h + offcap) | 455 vs 4009 coins/min active, about 11%, under the 20% cap. OK: active play always wins. |

### Heuristic checks
- **No runaway:** coins per day grow about 1.1× per day late, and enemy HP (1.155^w) still sets the death point. Day-30 best wave is w65 in T4, below 2× the unlock threshold (I-11).
- **Plateaus:** days 1–3 at w30 (by design, see the tier row); late T4 gains about 0.5 wave/day (w56→w65 over days 16–30). No 5-day zero-gain window (`stall_days` empty). The post-day-18 slowdown is **structural**: every non-combat lab is maxed, and T5 (w70 in T4) is out of reach within 30 days.
- **Meaningful choices:** eco vs weapon is live (week 1). Perks are close except Greed. Lab order matters until day 18.

## 3. Change applied

| Knob | Old | New | Where |
|---|---|---|---|
| `greed_enemy_hp` (Tune) | 1.25 | **1.7** | `Perks.gd` default; `PerkDB` cost text "+70% HP"; added to `balance.spec.json` search space |

### Before → after (seed 4242, balanced campaign; best wave in highest tier)

| Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Before tier/wave | T1 30 | T1 30 | T1 30 | T2 34 | T2 40 | T2 40 | T2 44 | T2 44 | T2 47 | T2 47 | T3 50 | T3 53 | T3 55 | T3 58 | T4 0 | T4 57 | T4 60 | T4 63 | T4 65 |
| After tier/wave  | T1 30 | T1 30 | T1 30 | T2 34 | T2 42 | T2 42 | T2 44 | T2 45 | T2 47 | T2 48 | T2 49 | T3 53 | T3 56 | T3 56 | T3 58 | T4 56 | T4 58 | T4 63 | T4 65 |

| Metric | Before | After |
|---|---|---|
| T2 day / T3 day (band 12–24) | 4 / **11** | 4 / **12** |
| Midgame days 5–6 (previously noted stall) | w40, w40 | **w42, w42** |
| Days 7–11 per-day gain | 0,+3,0,+3(T3) | +1,+2,+1,+1 (one wave nearly every day) |
| Day-30 best wave / tier | w65 / T4 | w65 / T4 |
| Gems/day, top source | 23.9, mission 44% | 24.0, mission 44% |
| Cards owned d7 / d30 | 4 / 6 | 4 / 6 |
| Labs sum d30 | 114 | 114 |
| Gates | PLAYTEST OK | PLAYTEST OK (selftest/uitest/npm unchanged, no test constant edited) |

Why it works: the campaign bot takes Greed to clear the daily tradeoff-perk mission.
Before this change, Greed was nearly free and front-loaded coins, which pulled T3 a day
early. At +70% HP, a Greed run gives up 2–3 waves. The bot then advances one wave a day
instead of in 3-wave jumps, and the tier timing lands inside the SPEC band. A player who
takes Greed now trades waves for coins visibly, instead of getting free money.

## 4. Proposals (need a SPEC/BRIEF change, so not applied)

1. **Card hook (day 1–2):** make streak day 2 a free chest (AC-30 currently pins only day 7),
   or have the Cards tab open with one starter chest. Either one makes the first card
   arrive on day 1–2 for every player.
2. **Greed coin edge:** change Greed to ×1.35 coins (PerkDB text plus a `greed_coin` knob)
   to bring `perk_top_coin_ratio` into its 1.0–1.15 band. HP cost alone cannot get there.
3. **Late sink (day 17+):** add a coin sink that scales with income: a 31st+ "Mastery"
   level on Damage/Health at ×1.5 cost growth, or a coin-to-gem-shard exchange. This
   would absorb the 100k–230k idle bank and give about +1 wave/2 days in T4.
4. **T1 wall days 1–3:** if AC-40 allows T2 on day 2–4, set `boss_hp_t1` to 2.5 so day 2 shows a gain.

## 5. Open items for the next deepen pass (tracked, not fixed)

- [ ] **Labs maxed by ~day 18** — lab caps/costs run out; extend lab levels or add new labs (deepen: run-meta).
- [ ] **Coin bank piles up (100k–230k idle)** — add the late coin sink from Proposal 3.
- [ ] **T5 out of reach by day 30** — retune tier unlock or late scaling so T5 lands in the SPEC band.
- [ ] **Icons (plan item 8)** — game-icons SVGs not adopted yet; if adopted, credit each icon's CC BY 3.0 author in CreditsDB (enforced by tools/credits.test.mjs).
