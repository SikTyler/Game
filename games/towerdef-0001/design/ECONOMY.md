# Corehold — Economy & Progression Design (Game Theorist)

Status: design spec for the "core retention set" (Tiers, Boss bounty, Labs, Speed,
Offline, Adjacency, Perks, Enemy roster, Missions/Streak, Cards, Save v2).
All numbers are **starting tunings** — every constant below must be a `Tune.num()`
key so the Balance stage can sweep it via `GF_TUNE` without code edits.
Gems are **earn-only**. No real-money path exists or is planned.

## 0. Baseline (current code, measured)

| Quantity | Current value | Source |
|---|---|---|
| Wave length | 25 s (`wave_time`) | TowerState |
| Enemy HP | base × 1.12^(w−1) | `hp_growth` |
| Enemy dmg | base × 1.08^(w−1) | `dmg_growth` |
| Spawn interval | max(0.45, 1.8 × 0.93^(w−1)) — cap hit ≈ w20 | |
| XP to level | 6 × 1.3^(L−1) | |
| Coins/run | Σwave (+w per wave) + kill coin (0.15–0.6, boss 10) | ≈ 0.5·w² + 0.4/s·t |
| Perm costs | unlock 30·1.45^n, upgrade 15·1.55^L, core 10·1.5^L, place 15–20 | BaseMeta |

Playtest (balanced bot, 8 runs): best wave 18,20,28,29,29,30,30,30 → **plateau ≈ w30 by run 6**.
Pure eco best 7, pure weapon 25. A wave-30 run ≈ 12.5 min and banks ≈ 700–800 coins.

**Diagnosis.** (1) Enemy HP grows 1.12^w (×~27 at w30) while permanent power grows
roughly linearly in coins spent against exponential costs → hard wall ~w30.
(2) Coins/run ∝ w², so the wall also caps income — no escape velocity.
(3) Eco has no *terminal* value: cash only buys in-run levels, so eco's payoff is
only realised if weapons exist to spend it on (hence "only works mixed").

## 1. Currencies — sources & sinks

### Cash ($, run-only)
- **Sources:** Mine 1.2·L $/s; kills `cash × bounty_mult` (Bounty +0.4·L); perks (+50% cash tradeoff); card *Cash* (+10%/lvl); lab *Starting Cash* (25 + 25·lvl at run start).
- **Sinks:** in-run level-ups `8 × 1.55^(L−1)` (core `8 × 1.5^Lc`); outer-plot unlock `40 × 1.6^k`.
- **NEW sink (eco terminal value): "Cash-out" conversion** — at death, 2% of *cash earned this run* (not held) converts to coins (lab *Coin Bonus* does not apply; Tier multiplier does). This gives eco a meta payoff without letting it skip combat (cash earned still scales with waves survived).
- Recommended curve: keep in-run level cost growth (1.55) **below** enemy HP growth per level gained so cash spending stays meaningful through w40+; per-level weapon dmg is linear (+2/+5/+1.2), so effective value per $ decays — intended.

### XP (run-only)
- **Sources:** kills; Oil Mill +25%·L (+15%·L per adjacent Mine); lab *XP Bonus* +5%/lvl; card *XP*.
- **Sinks:** level-up → building-card draft (3 choices). Rerolls cost nothing but a lab/card charge.
- Curve: `xp_need = 6 × 1.3^(L−1)` — keep. Target ≈ 1 draft per wave early (w1–10), 1 per 2–3 waves by w30. If the level rate falls below 1 per 4 waves, drafts stop mattering: playtest invariant I-9.

### Coins (permanent, banked at death)
- **Sources:** per wave `+w`; kills; **Boss bounty** `25 × w/10` coins per boss (+1 gem); **Tier multiplier** `×(1 + 0.6·(T−1))`; lab *Coin Bonus* +4%/lvl (max 25); card *Coins* +5%/lvl; **Offline**; Cash-out (above); daily missions (small).
- **Sinks:** Base grid (unlock/place/upgrade/core); **Labs** (research cost); nothing else — keep coins a single clear sink-pool.
- Run formula (target): `coins_run = (0.5·w² + kill_coin + boss_bounty + cashout) × tier_mult × (1 + lab_coin + card_coin)`.

### Gems (premium-feel, earn-only)
- **Sources:** boss kill 1 (first 3 bosses/run only → cap 3/run to stop grind-farming); daily missions 3 × 5 = 15/day; login streak day1..7 = 5,5,10,10,15,15,30 (90/week); first-time tier clear 50; first time reaching w50/100 in any tier 25.
- **Sinks:** Card chest 40; 3rd lab slot 300 (one-time); card equip slot +1: 200, +2: 400; daily-mission reroll 10.
- Target income: ≈ 30–40 gems/day active → 1 chest/day, 3rd lab slot ≈ day 9, 3rd card slot ≈ day 14.

## 2. Recommended curves (formulas)

| System | Formula | Notes |
|---|---|---|
| Tier difficulty | HP, dmg × 1.5^(T−1) | per plan |
| Tier unlock | best wave in T ≥ 20 + 10·T | T1→T2 at w30, T2→T3 at w40, T3→T4 w50 |
| Tier coin mult | 1 + 0.6·(T−1) | **Raise to 1 + 0.8·(T−1) if I-2 fails**: tier must pay more per minute than farming T−1 at its plateau |
| Boss bounty | 25·(w/10)·tier_mult coins + 1 gem | |
| Lab cost | `base_i × 1.8^lvl` coins; duration `d_i × 1.6^lvl` min, ÷ (1 + 0.1·LabSpeed) | base 50–150, d 5 min → hours by lvl 8 |
| Lab tracks | Game Speed (+0.25×/lvl, max 3.0× at lvl 8… cap 4 lvls early = 2.0×), Coin Bonus +4%, XP Bonus +5%, Starting Cash +25$, Offline Cap +1 h (base 4 h, max 12 h), Draft Reroll +1/run, Lab Speed +10%, **Damage +5%/lvl, Health +5%/lvl** (multiplicative to core & weapons) | the two multiplicative tracks are the plateau-breakers |
| Offline | coins/min = 0.25 × (best_wave_in_tier²/w30-run-minutes-normalised) ≈ `0.04 × best_wave² × tier_mult / 60` per min … simpler: **offline = 15% of the coin rate (coins/min) of the player's best run in the current tier**, capped by Offline Cap | must stay ≤ 20% of active rate (I-6) |
| Perm costs | keep 1.45/1.55/1.5 bases; ADD per-building level cap 10 (base), +5 per tier unlocked | the cap stops coin-dumping into one Gun |
| Game speed | run-sim multiplier only; coins/sec scales, coins/run unchanged | speed = a time-saver, never a power-gain |

Why labs/tiers break the plateau without trivializing:
- The wall is exponential (1.12^w). Linear perm stats cannot beat it; **multiplicative labs** (+5%/lvl dmg/HP, compounding to ~×1.6 at lvl 10) push the wall by log(1.6)/log(1.12) ≈ **+4 waves per 10 lab levels** — slow, gated by real time, not grind.
- **Tiers** reset the wave counter but multiply coins, converting "stuck at w30" into "T2 at w20 pays like w30+". Unlock at 20+10·T means the player must actually beat the previous wall, so tiers are earned, never skipped.
- Real-time lab durations bound progress per *day*, not per *hour played* — this is the rate limiter that prevents a binge from trivializing a week of content.

## 3. Target pacing (≈4 runs/day + offline, balanced play)

| Day | Best wave (current tier) | Tier | Lab levels (sum) | Cards owned | Notes |
|---|---|---|---|---|---|
| 1 | 22–28 (T1) | 1 | 2–3 | 0–1 | learn loop; first boss bounty |
| 3 | 30–34 (T1) → T2 unlocked | 1→2 | 6–8 | 2 | first tier jump = day-3 hook |
| 7 | 25–32 (T2) | 2 | 14–18 | 4 | 7-day streak complete, 3rd lab slot near |
| 14 | 40+ (T2) → T3 | 3 | 25–30 | 6 | 3rd card slot |
| 30 | 30–45 (T3) / T4 in reach | **≥3** | 40–50 | 8 (most lvl 2–3) | long tail = labs + card levels |

Rule of thumb: **best wave in a new tier starts ~10 below the unlock threshold** and climbs to threshold in 3–6 days.

## 4. Dominant-strategy analysis & counters

| Risk | Why it could dominate | Counter-design |
|---|---|---|
| **Armory cluster** (Armory ringed by guns/core) | +25%·L to ALL neighbours, multiplicative with core; one Armory lvl 5 = ×2.25 on up to 4 weapons | Cap armory bonus per target at +100%; neighbours count is limited by the 5x5 grid already; adjacency synergy list should give eco/defense equally strong pairs |
| **Gun stacking** | cheapest weapon, linear +2 dmg & +12% rate → quadratic DPS in L | Rate bonus cap (gun rate ≤ 2.5/s); ranged/shielded elites (shield absorbs first N hits → favours Mortar/Tesla big hits) |
| **Bulwark tank** | HP+regen outscale dmg_growth 1.08 | Ranged enemies attack from range (no contact), splitters overwhelm; regen % not flat in tier ≥2 |
| **Pure weapon** (25) vs mix (30) | — fine now; protect it | Invariant I-3 |
| **"+cash" perk** always picked | cash ⇒ levels ⇒ everything | Every perk carries an opportunity cost; tradeoff perks have real downside (+50% cash / enemies +15% speed) |
| **Second Wind card** | revive = +2–4 waves always | 1 per run, revive at 30% HP, card levels improve HP % not count |
| **Wave Skip card** | skips HP-scaled waves for free coins | Skipped waves grant 50% wave coins and no kill coins |
| **Offline > active** | AFK beats play | offline ≤ 20% of active coins/min (I-6) |
| **Game speed** as power | — | speed never changes per-run outcomes (I-8) |
| **Tier farming lower tier** | lower tier faster coins/min | tier_mult must make T_max the best coins/min (I-2) |

Perk design principle: ~12 perks in 3 families (offense, defense, economy), each draft offers one per family; at least 4 are explicit tradeoffs. No perk should be picked >40% by an optimising bot when offered (I-4).

## 5. Eco's value proposition

Currently eco only compounds *cash*, which only matters if spent on weapons → pure eco = w7.
Fixes (pick all three; small numbers):
1. **Cash-out → coins** (2% of earned cash at death) — eco becomes the *meta-income* build, i.e. the "farm" choice for players saving for labs.
2. **Adjacency synergies that cross categories**: Mine next to Gun = +10% gun rate per Mine level ("ammo works"); Oil Mill next to Tesla = +1 chain; Bounty next to Mortar = splash kills +25% cash. Eco slots then directly feed defense.
3. **Eco scales with wave** not time: Mine yield `1.2·L·(1 + 0.03·w)` so it keeps relevance vs exponential enemies.
Target: balanced eco-mix earns ≥ 25% more coins/run than pure weapon *and* reaches ≥ 10% higher best wave.

## 6. Playtest invariants for the Balance stage

Implement as asserts in `playtest.gd` (simulated clock via injectable `now`; 4 runs/day + offline at 8 h gaps):

- **I-1 Progress:** simulated day-30 player has tier ≥ 3; day-3 has unlocked T2; day-1 best wave ∈ [18, 32].
- **I-2 Tier worth it:** at the plateau of tier T, coins/min in T+1 (fresh unlock) ≥ 1.1 × coins/min farming T.
- **I-3 Eco-mix wins:** balanced eco-mix best wave ≥ 1.10 × pure weapon best wave (same save) AND coins/run ≥ 1.25×.
- **I-4 No dominant perk:** across 200 seeded drafts, no perk's win-rate-optimal pick rate > 40%; every perk picked ≥ 5% by the optimiser.
- **I-5 No dominant building:** removing any single building id from the pool reduces best wave by ≤ 20%; mono-building boards (any id) reach < 70% of balanced best wave.
- **I-6 Offline cap:** offline coins/min ≤ 0.20 × active coins/min, and offline 24 h ≤ cap-hours worth.
- **I-7 No plateau stall:** day 7→14 and 14→30 each show best-wave-in-highest-tier or tier rising; no 5-day window with zero gain.
- **I-8 Speed neutral:** same seed at 1× and 3× speed yields identical wave & coins (± rounding).
- **I-9 Draft cadence:** levels/wave ≥ 1.0 for w1–10, ≥ 0.25 at w30.
- **I-10 Gem economy:** day-30 gems earned ∈ [800, 1400]; no single source > 50% of gems; boss gems ≤ 3/run.
- **I-11 No trivialization:** day-30 player still dies by wave ≤ 2 × tier unlock threshold in highest tier (game remains a challenge).
- **I-12 Card fairness:** best card loadout improves best wave ≤ 25% over empty loadout.

## 7. Tune keys to expose
`tier_hp_base 1.5`, `tier_coin_step 0.6`, `boss_bounty 25`, `boss_gem_cap 3`, `lab_cost_growth 1.8`,
`lab_time_growth 1.6`, `offline_frac 0.15`, `offline_cap_h 4`, `cashout_frac 0.02`,
`armory_cap 1.0`, `gun_rate_cap 2.5`, `mine_wave_scale 0.03`, `perm_lvl_cap 10`, `chest_gems 40`.

## 8. Balance pass (playtest CAMPAIGN sim) — what was measured and tuned

`playtest.gd` now runs, after the legacy 8-run T1 audit, a **30-day campaign** with an
injected clock (2 sessions × 2 runs per day, 8 h / 16 h offline gaps): login streak →
missions roll/claim → offline claim → gems (lab slot 3/4, card slots, chests, equip) →
labs (start ≤ 50% of the bank, then the base, then research with the rest) → base →
fastest unlocked speed → tier pick (push the highest tier; farm T−1 on alternate runs
only if the top tier pays < 80% of its coins/min) → run (bot chases the tradeoff-perk
mission). Plus: 7-day pure-weapon / pure-eco campaigns from the same fresh save, and
same-save snapshot comparisons (in-run policy, always-take-perk-X) on days 7 and 20.

Findings that drove the tuning (all via data tables / Tune knobs; SPEC-pinned values untouched):
- **Hard ceiling at T2 w48 for ~25 days, T3 only on day 29.** Late power is additive
  (+5%/lab level, linear building stats) against a 1.12^w ramp, and the boss every 10
  waves was a deterministic wall (every policy and perk died on the same boss).
  → `hp_growth_hi` 1.11 (T2+ only; T1 keeps the classic 1.12/w30 wall the legacy audit
  relies on), `boss_hp_hi` 0.5 (T2+ only), labs Damage/Health `dur_growth` 1.6 → 1.45.
- **Coins saturated the base by day 4.** → perm costs ×3 (`perm_upgrade_base` 45,
  `perm_core_base` 30, `perm_unlock_base` 90).
- **Eco-mix lost to pure weapon** (half-mine boards bought almost nothing with cash late,
  because in-run level cost compounds on the *total* level). → `run_upgrade_growth` 1.3
  (was 1.55): cash now buys real in-run levels, so the eco half of a board pays in waves.
- **Greed was a free +50% coins** (its "+15% enemy speed" cost never bit). → new cost
  `greed_enemy_hp` 1.25 (Greed: enemies +15% speed, +25% HP).
- **Boss gems would pass 50% of gem income once T3 doubled them.** → `boss_gem_t3` 1.

Result (seed 4242): T2 day 2, T3 day 12, no 5-day stall before T3, 25.5 gems/day
(boss 46%), offline ≈ 11% of active coins/min, eco-mix week-1 = 2.4× pure-weapon coins
at ≥ its best wave, no dominant perk (top coin ratio 1.06). Known gaps (reported, not
gated): day-1 best wave 39 (target 18–32) and T2 on day 2 (AC-40 wants 3–5) — the early
game is faster than the brief; after T3 the best wave creeps 47 → 48 over days 13–30
(a post-T3 plateau: T4 at w60 in T3 is out of reach within 30 days).
