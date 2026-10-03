# Corehold: Creative Brief and Acceptance Criteria (Project Manager)

The implementation contract is `SPEC.md`. `SYSTEMS.md` (designer) and `ECONOMY.md` (theorist) are inputs, and where they disagree `SPEC.md` is the version that holds.

## Intent (one sentence)
A simple, blocky, The-Tower-like idle tower defense where **base building IS the upgrade system**, scarce slots force an **eco-vs-defense tradeoff**, and the game stays **playable long-term**: there is always a timer, a tier or a card to come back for.

## Pillars
1. **The grid is the build.** Every permanent and run-time power either lives on the 5x5 grid or modifies it. New systems feed it (labs, cards, perks) and never replace it.
2. **Eco OR defense.** Every eco slot is a defense slot given up. Eco must have a real payoff (cash-out, interest, mine wave-scaling), and mixing must be punished somewhere (Aegis).
3. **One more wave / one more boss.** Bosses are spikes and paydays. Death always banks something.
4. **Come back tomorrow, honestly.** Real-time labs, offline income, a daily mission draw and a streak. Gems are **earn-only**, with no store, no ads and no real-money path, ever.
5. **Blocky and readable.** Flat primitives and SVG icons. Every new mechanic is visible: shield pips, link lines, perk icons and a speed pill.

## Guardrails (cut on sight)
- No real-money purchase, ad, energy or stamina system, and no gem source tied to spending.
- Offline income can never beat active play (≤ 20% of active coins per minute).
- Game speed must not change any outcome, only wall-clock time.
- No new screen beyond the 4 Base tabs, the perk sheet and the death breakdown. No PvP, guilds, events or battle pass (out of scope for the retention set).
- No building, perk or card may dominate (see the invariants in the AC list).
- The view owns no rule. Time functions take `now`, randomness is seeded, and every phase change emits an event.
- Tests are never weakened. Tuning is fixed through `Tune` keys.

## Acceptance criteria (numbered, testable)

Each AC names the gate that proves it: **S** = selftest.gd, **U** = uitest.gd, **P** = playtest.gd, **X** = screenshot review.

### Save v2 / migration
- AC-1 (S) A v1 save (no `version`) migrates to v2 losslessly: coins, slots, core, unlocked and runs are unchanged, `best_wave_by_tier["1"] == best_wave`, and `gems == 0`, `tier == 1`, `last_seen == 0`, `version == 2`.
- AC-2 (S) A v2 save round-trips through JSON (`normalize(parse(stringify(s))) == s`).
- AC-3 (S) `normalize` clamps every level to its max, drops unknown ids and keeps `labs.running.size() <= labs.slots`.
- AC-4 (S) The first v2 boot after migration (`last_seen == 0`) pays 0 offline coins.

### Tiers
- AC-5 (S) Tier N unlocks when `best_wave_by_tier[N-1] >= 20 + 10*N`, emits `tier_unlocked` once, and grants the first-unlock gems once. Max tier is 8.
- AC-6 (S) At tier T, enemy HP and damage equal the T1 value × `1.5^(T-1)`, and all run coins (wave, kill, boss) equal the T1 value × `1 + 0.6*(T-1)`.
- AC-7 (S) Bosses spawn every 10 waves in T1–T4 and every 8 waves from T5.
- AC-8 (U) The tier selector shows only unlocked tiers as selectable, a locked one shows its unlock requirement, and the choice persists.

### Boss bounty
- AC-9 (S) Killing a boss at wave w adds `floor(25 * w/10 * tier_mult)` to `coins_run` immediately and emits `boss_bounty`.
- AC-10 (S) Boss gems are 1 each (2 from T3), with at most 3 boss-gem awards per run.
- AC-10a (S) *(fix-round amendment, needs PM sign-off)* Boss gems are also capped per calendar day (`boss_gem_daily` = 10, `save.boss_gems_today`). Reason: at T3, 3 awards × 2 gems × 4 runs = 24 boss gems/day, which cannot stay ≤ 50% of income (AC-41) while total income stays ≤ 30/day.

### Labs
- AC-11 (S) Starting research deducts `cost(L)` coins, needs a free slot, and sets `end = now + dur(L) * labspeed_mult`. It fails without mutating the save when coins or slots are short.
- AC-12 (S) `Labs.claim(s, now)` completes exactly the slots with `now >= end`, raises the level and emits `lab_done`, and is a no-op before `end`.
- AC-13 (S) Rush costs `ceil(remaining_min / 30)` gems and fails without mutation if gems are short. Buying lab slots 3 and 4 costs 60 and 150 gems.
- AC-14 (S) The lab Damage and Health tracks multiply the core and weapon damage and the core max HP by `1 + 0.05*L` inside TowerState.

### Game speed
- AC-15 (S/P) The same seed and save run at speed 1.0 and 2.5 give the same wave reached, kills and coins (±1 coin) over 3 minutes of game-time, because sub-steps are ≤ 0.05 s.
- AC-16 (U) The speed pill cycles only through steps unlocked by the Speed lab level, and the choice persists in `save.speed`.

### Offline
- AC-17 (S) `Offline.compute(s, now)` returns 0 for an absence under 5 min, for `now < last_seen` (and resets `last_seen`), and for `last_seen == 0`. Payout is capped at `(4 + offcap_lvl)` hours, max 12.
- AC-18 (S/P) The offline coins-per-minute rate is ≤ 0.20 × the best run's active coins-per-minute at every `offrate` level.

### Synergies and new buildings
- AC-19 (S) Each synergy S1–S5 changes the targeted stat by exactly its spec value when its pair is adjacent, by 0 when it is not, and adds an entry to `compute_stats().links`.
- AC-20 (S) Vault pays `min(held_cash * 0.04 * L, 40 * L)` at wave end (cap ×1.5 next to a Bounty Office). Aegis applies its core damage reduction, its +fire rate to adjacent weapons and its −15% output to adjacent eco.
- AC-21 (S) Armory's per-target bonus caps at +100%, and Gun fire rate caps at 2.5/s.
- AC-22 (S) Cash-out: at death, `floor(0.02 * cash_earned * tier_mult)` coins are added to the run's coins and itemised in the `game_over` event.

### Perks
- AC-23 (S) `perk_offer` fires on waves 5, 10, 15 and so on with 3 distinct, untaken ids, one per family when available. It is deterministic for a given seed and queues behind an open building draft.
- AC-24 (S) Each perk applies exactly its spec effect. No tradeoff combination takes max HP below 50% of base or regen below 0.

### Enemies
- AC-25 (S) Ranged enemies stop at 230 px and fire every 2.0 s, and only spawn from wave 8.
- AC-26 (S) Elites appear only from T2, and their shield absorbs exactly `3 + floor(w/10)` hits (Tesla chain hits count) before taking damage.
- AC-27 (S) Splitters appear only from T3 and spawn exactly 2 mites once on death. Mites never spawn directly.

### Missions and streak
- AC-28 (S) The same `day` always rolls the same 3 distinct templates, and a new day re-rolls and resets progress.
- AC-29 (S) Mission progress advances only from run events. Claiming pays gems once, and clearing all three pays a +5 bonus once.
- AC-30 (S) The streak advances once per day, resets to day 1 after a missed day, and day 7 pays 10 gems plus a free chest.

### Cards
- AC-31 (S) A chest costs 20 gems and gives a seeded card. Duplicates level the card at `copies >= L`, up to max level 5.
- AC-32 (S) Only equipped cards (≤ owned slots: 2, then 30/60/100 gems for slots 3–5) modify TowerState at `setup()`.
- AC-33 (S) Second Wind revives at most once per run. Wave Skip grants 50% wave coins and no kill coins for the skipped wave.

### UI
- AC-34 (U) The Base screen shows the Base | Labs | Cards | Missions tabs. The tier selector and START are visible on every tab, and START starts a run from any tab.
- AC-35 (U) Every new Button uses ACTION_MODE_BUTTON_PRESS with a height ≥ 88 px, and overlay Controls use MOUSE_FILTER_IGNORE.
- AC-36 (U) The perk sheet shows 3 cards, and tapping one takes that perk. The death screen shows the coin breakdown and "Back to Base".
- AC-37 (X) Screenshots exist for the Base tab, Labs, Cards, Missions, the run HUD with the speed pill and perk icons, the perk sheet and the death breakdown, with no overlapping text.

### Long-term balance (playtest invariants)
- AC-38 (P) Eco-mix beats pure weapon: best wave ≥ 1.10× and coins/run ≥ 1.25×, with the same save.
- AC-39 (P) No building dominates: a mono-building board reaches < 70% of the balanced best wave.
  - Measurement (fix round): AC-38 compares the week-1 strategies from the same fresh save (best wave + gross coins); AC-39 compares 8 fresh-save runs of mono gun / mortar / tesla boards with the balanced policy. Both are gated in `playtest.gd`, and AC-38/AC-40 are re-checked on two extra seeds.
- AC-40 (P) Over a simulated 7 days (4 runs a day plus 8 h offline gaps, injected `now`), T2 unlocks by day 3–5 and best wave or tier rises in every 3-day window.
- AC-41 (P) Simulated gem income is 10–30 a day, and no single source is more than 50% of it.
- AC-42 (all) Every gate passes: import, boot with no errors, SELFTEST OK, UITEST OK and PLAYTEST OK.
