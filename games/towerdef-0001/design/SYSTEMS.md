# Corehold: Retention Systems Spec (Lead Game Designer)

Status: **authoritative design spec** for the core retention set. Code agents implement it exactly. Balance agents may retune any number through `Tune.gd` / `GF_TUNE` without editing this file. If you retune, record the new value in §14 so the doc stays the source of truth.

Engineering contract (applies to every section):
- Rules live in pure modules (`Tiers.gd`, `Labs.gd`, `Perks.gd`, `Cards.gd`, `Missions.gd`, `Offline.gd`, `data/*DB.gd`). The view only replays events.
- Every time-based function takes `now: int` (unix seconds). Every random roll takes a seeded `RandomNumberGenerator` and uses a manual Fisher-Yates shuffle.
- Every phase change emits an event dict (`{"t": "...", ...}`). The event names to use are listed per section.
- Everything is tunable. Each constant below has a key shown as `key=` (sometimes ``Tune: `key` ``), and `TuneRef.num(key, default)` must read it.

Research basis (from the approved plan): The Tower supplies Workshop / Labs / Cards / Tiers / perks / offline earnings / missions. Survivor.io and Archero supply the 1-of-3 picks and AFK rewards. Rogue Tower supplies placement synergies. Every system below goes back through Corehold's single fantasy: **a 5x5 base whose scarce slots go to eco OR defense**.

---

## 1. Tiers (long-horizon difficulty ladder)

| Tier | Unlock condition | Enemy HP & dmg mult | Coin mult | New threat |
|---|---|---|---|---|
| 1 | always | x1.00 | x1.0 | ranged from wave 8 |
| 2 | best wave in T1 >= 30 | x1.50 | x1.6 | + shielded elite |
| 3 | best wave in T2 >= 40 | x2.25 | x2.2 | + splitter |
| 4 | best wave in T3 >= 50 | x3.375 | x2.8 | elites x2 freq |
| 5 | best wave in T4 >= 60 | x5.06 | x3.4 | boss every 8 waves |
| 6+ | best wave in T(N-1) >= 20+10N (cap 100) | 1.5^(N-1) | 1+0.6(N-1) | — |

- Formulas: `tier_unlock_wave(N) = 20 + 10*N` measured in tier N-1 (`tier_unlock_base=20`, `tier_unlock_step=10`). Enemy mult `= tier_hp_base^(N-1)`, with `tier_hp_base=1.5`. Coin mult `= 1 + tier_coin_step*(N-1)`, with `tier_coin_step=0.6`. Max tier `tier_max=8`.
- The coin mult applies to **all coins earned in a run**: the per-wave coins, kill coins and boss bounty. It does not apply to offline earnings, which have their own tier term (§5).
- Choosing a lower tier is always allowed, and the selector remembers the last choice (`save.tier`).
- `best_wave_by_tier["N"]` is recorded when the run is banked. The legacy `best_wave` becomes `max` over all tiers.
- Events: `{"t":"tier_unlocked","tier":N}`, emitted by `BaseMeta.bank` when a bank crosses a threshold.

## 2. Boss bounty

A boss dies every 10th wave (every 8th in T5+). It pays:
- **coins:** `boss_bounty_base(25) * (wave/10) * tier_coin_mult`. This is added to `coins_run` immediately, so it banks even if you die one second later.
- **gems:** `+1` on the first kill of each 10-wave band per run. From T3 it is `+2` (`boss_gem_t3=2`).
- **cash:** the existing `cash: 25` drop, scaled by `bounty_mult` as before.
- Event: `{"t":"boss_bounty","coins":c,"gems":g,"pos":p}`. The view shows a gold burst plus a "+c / +g" floater.
- Design intent: a boss is a spike *and* a payday, so pushing one more boss is always the meaningful decision at death's door.

## 3. Labs (real-time research, the #1 daily-return lever)

- Slots: **2 free**, plus a 3rd for **40 gems** (one-time purchase) and a 4th for **120 gems**.
- Each running slot holds `{track, to_lvl, start, end}`. Starting research costs coins up front.
- Cost: `cost(L) = base * growth^L`. Duration: `dur(L) = dur_base * dur_growth^L` seconds, then multiplied by Lab Speed.
- `progress(now) = clamp((now-start)/(end-start), 0, 1)`. Claiming is automatic on the Base screen at boot or tab open, whenever `now >= end`.
- **Rush:** finish now for `ceil(remaining_minutes/30)` gems. This is the only gem sink besides chests and slots, and gems remain earn-only.
- Events: `lab_started`, `lab_done {track, lvl}`, `lab_rushed {gems}`.

| Track | id | Max | Effect per level | base cost | growth | dur_base | dur_growth |
|---|---|---|---|---|---|---|---|
| Game Speed | `speed` | 3 | unlocks next speed step (§4) | 400 | x4.0 | 30 min | x3.0 (30m/1.5h/4.5h) |
| Coin Bonus | `coin` | 20 | +5% coins (multiplicative with tier) | 60 | x1.35 | 5 min | x1.30 |
| XP Bonus | `xp` | 20 | +4% run XP | 50 | x1.35 | 4 min | x1.30 |
| Starting Cash | `startcash` | 15 | +$15 at run start | 40 | x1.40 | 3 min | x1.30 |
| Offline Cap | `offcap` | 8 | +1 h offline cap (4h to 12h) | 150 | x1.60 | 20 min | x1.45 |
| Offline Rate | `offrate` | 10 | +10% offline coin rate | 120 | x1.50 | 15 min | x1.40 |
| Draft Reroll | `reroll` | 3 | +1 free reroll per run | 250 | x3.0 | 45 min | x2.5 |
| Lab Speed | `labspeed` | 10 | -6% research duration (floor 0.4x) | 200 | x1.55 | 30 min | x1.45 |
| Core Plating | `armor` | 15 | -1.5% damage taken by core (cap 22.5%) | 80 | x1.40 | 6 min | x1.35 |

Pacing target: early levels finish within one session (3-10 min). By about day 5 the levels run 1-8 h, so there is always a timer to come back to.

## 4. Game speed

- Steps: `[1.0, 1.5, 2.0, 2.5]`. Speed Lab L unlocks steps `0..L`.
- The run HUD has a pill toggle that cycles through unlocked steps. The setting persists in `save.speed`.
- The engine multiplies `delta` by `speed` **before** `time_scale()`, and draft slow-mo still applies on top. Sub-stepping: if `delta*speed > 0.05`, split into equal steps of 0.05 s or less so collision and fire stay deterministic.
- Speed changes no rules and no economy per second of game-time. It only saves wall-clock.

## 5. Offline earnings

```
rate_per_min = offline_base(0.5) * best_wave_overall^1.15 * (1 + 0.6*(highest_unlocked_tier-1)) * 0.25 * (1 + 0.10*offrate_lvl)
minutes      = clamp((now - last_seen)/60, 0, cap_hours*60);   cap_hours = 4 + offcap_lvl
coins        = floor(rate_per_min * minutes)
```
- The trailing `0.25` is `offline_eff`: idle earns about 25% of active play. Active play must always dominate.
- Minimum absence is 5 min (`offline_min=300`). `now < last_seen` (a clock moved backwards) earns 0, and `last_seen` is reset to `now`.
- It is claimed via a modal on boot ("While you were away: +N coins"). An optional **x2 for 2 gems** is offered, as a gem sink.
- `last_seen` is written on every save, on run start and on app pause.
- Event: `{"t":"offline","coins":n,"minutes":m}`.

## 6. Adjacency synergies (4-neighbour, the grid puzzle)

Existing synergies, kept:
- Armory: +25%/lv dmg to adjacent weapons and the core.
- Oil Mill: +15%/lv XP per adjacent Mine.

New synergies:

| # | Pair | Rule | Why it deepens the puzzle |
|---|---|---|---|
| S1 | **Bounty Office + Mine** | Each Mine adjacent to a Bounty adds +0.3 $/s per Bounty lvl | eco clusters want to touch, which competes with the core-adjacent defense ring |
| S2 | **Tesla next to Mortar** | Enemies shocked by an adjacent Tesla in the last 1.5 s take mortar splash x1.3 | rewards a weapon pair, so it costs 2 slots of defense |
| S3 | **Bulwark on the core ring** (slots 6,7,8,11,13,16,17,18) | +3% damage reduction per lvl (cap 30%) | the inner ring is the most valuable real estate for eco (Armory reach), so this is a real choice |
| S4 | **Vault + Bounty** (new bldg, §11) | Vault interest cap +50% | links the two new eco pieces |
| S5 | **Aegis + weapon** (new bldg, §11) | adjacent weapons +10% fire rate per Aegis lvl, but adjacent **eco** buildings -15% output | the explicit eco-vs-defense spatial conflict |

- All bonuses are computed in `compute_stats()`. Its output adds `"links": [[a,b,"S1"],...]`, which the view draws as thin coloured lines (the cat colour of the bonus receiver).

## 7. Perks (every 5 waves, second draft cadence)

- On waves 5, 10, 15... (`perk_every=5`): emit `{"t":"perk_offer","ids":[3]}`. The 3 picks are drawn seeded and without replacement from the not-yet-taken pool.
- The perk pick uses the same slow-mo rule as the building draft. If both are open at once, the perk queues behind the building draft.
- Taken perks persist only for the run. Each perk can be taken once (stack=1) unless stated otherwise. Selecting emits `perk_taken`.

| id | Name | Effect | Type |
|---|---|---|---|
| `p_dmg` | Overcharge | +20% all weapon dmg (stack 3) | pure |
| `p_hp` | Reinforced Core | +25% max HP, heal to full | pure |
| `p_cash` | Prospector | +25% cash/s from Mines (stack 2) | pure |
| `p_xp` | Scholar | +30% XP | pure |
| `p_rate` | Hair Trigger | +15% fire rate (stack 2) | pure |
| `p_range` | Long Barrels | +20% range | pure |
| `p_glass` | **Glass Cannon** | +40% dmg / -25% max HP | tradeoff |
| `p_greed` | **Greed** | +50% cash & coins / enemies +15% speed | tradeoff |
| `p_fort` | **Fortress** | +60% max HP & +100% regen / -20% dmg | tradeoff |
| `p_frenzy` | **Frenzy** | +30% fire rate / regen disabled | tradeoff |
| `p_miser` | **Miser** | cash upgrades -30% cost / XP -30% | tradeoff |
| `p_bloodmoon` | **Blood Moon** | coins x1.75 / spawn interval x0.8 (more enemies) | tradeoff |

That is 12 perks, 6 of them tradeoffs. Perks are rejected if their invariant fails: no tradeoff perk may take max HP below 50% of base or make regen negative.

## 8. Enemy roster (additions to `EnemyDB`; base stats at wave 1, scaled as usual)

| kind | hp | spd | dmg | cash | xp | coin | size | Behaviour | Unlock / spawn weight |
|---|---|---|---|---|---|---|---|---|---|
| `ranged` | 8 | 40 | 3 | 2 | 2 | 0.3 | 15 | Stops at 230 px from the core and fires a bolt every 2.0 s (dmg x scale). That is inside gun/core range, so it must be killed rather than out-healed | T1 wave >= 8, 12% |
| `elite` | 30 | 32 | 12 | 5 | 5 | 1.0 | 24 | **Shield**: absorbs the first `3 + wave/10` hits fully, regardless of damage. Each absorbed hit emits `shield_hit` and the shield breaks with `shield_break`. Tesla chain hits count as hits, so Tesla is the counter | T2+, wave >= 5, 8% (T4+: 16%) |
| `splitter` | 18 | 38 | 6 | 2 | 2 | 0.4 | 22 | On death spawns 2 `mite` at its position (event `split`). The split happens once only | T3+, wave >= 5, 10% |
| `mite` | 3 | 95 | 1.5 | 0.5 | 0.5 | 0.05 | 10 | child of splitter, never spawned directly. Mortar splash is the counter | — |

- Roll order in `_roll_kind`: hauler, splitter, elite, ranged, skitter, then drone. Weights sum to 1 or less, and the remainder goes to drone.
- Each new enemy has a hard counter in the existing roster, so the draft stays the answer to roster variety.

## 9. Daily missions and login streak

- Daily seed: `day = floor((now + tz_offset)/86400)`. Missions are rolled with `rng.seed = hash(day)`: 3 templates without replacement, so the same day gives the same missions.
- Missions refresh at the day rollover, and unclaimed completed missions are lost. Progress is tracked from run events.

| template | Text | Target (scaled by best wave B) | Reward |
|---|---|---|---|
| `kill` | Kill N enemies | 150 + 10*B | 3 gems |
| `wave` | Reach wave N | max(10, floor(B*0.8)) | 4 gems |
| `boss` | Defeat N bosses | 1 + B/30 | 4 gems |
| `eco` | Place N eco buildings in runs | 4 | 2 gems |
| `cash` | Earn $N cash in one run | 300 + 25*B | 3 gems |
| `perk` | Take N tradeoff perks | 2 | 2 gems |
| `lab` | Start N lab researches | 2 | 2 gems |
| `upgrade` | Buy N permanent upgrades | 3 | 2 gems |

- Clearing all 3 missions gives a bonus of **+5 gems**.
- **Login streak:** claim once per `day`. Missing a day (`day > last_day+1`) resets the streak to day 1.

| Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Reward | 50 coins | 2 gems | 100 coins | 3 gems | 200 coins | 4 gems | **10 gems + free chest** |

After day 7 the ladder loops back to day 1, and coin rewards scale by `1 + 0.1*loops` (capped at 2x).
- Events: `missions_rolled`, `mission_done`, `mission_claimed`, `streak_claimed {day}`.
- Gem economy check: an engaged player earns about 15-25 gems a day (missions about 14, streak about 3.5 average, bosses about 3-6). A chest is 20 gems, which works out to roughly one card a day.

## 10. Cards (gems)

- Chest: **20 gems** gives 1 card. Picks are seeded and uniformly random over the 8 cards.
- A duplicate adds +1 copy. A card levels up when its copies reach `copies_needed(L) = L` (so L1 to L2 needs 1 extra, L2 to L3 needs 2, and so on). Max level is **5**.
- Equip slots: **2 free**. Slot 3 costs 30 gems, slot 4 costs 60 and slot 5 costs 100. Only equipped cards apply, and they apply at `setup()`.
- Events: `chest_opened {card, new, lvl_up}`, `card_equipped`, `card_unequipped`.

| id | Name | L1 | L2 | L3 | L4 | L5 |
|---|---|---|---|---|---|---|
| `c_dmg` | Damage | +10% dmg | +16% | +22% | +30% | +40% |
| `c_hp` | Health | +15% HP | +22% | +30% | +40% | +50% |
| `c_cash` | Cash | +10% cash | +15% | +20% | +27% | +35% |
| `c_coin` | Coins | +8% coins | +12% | +16% | +22% | +30% |
| `c_xp` | XP | +10% XP | +15% | +20% | +27% | +35% |
| `c_reroll` | Free Reroll | +1 reroll | +1 | +2 | +2 | +3 |
| `c_wind` | Second Wind | revive once at 20% HP | 25% | 30% | 40% | 50% |
| `c_skip` | Wave Skip | 3% chance a wave advances double (coins for both) | 5% | 7% | 9% | 12% |

## 11. New buildings (2)

Both deepen the scarce-slot eco-vs-defense puzzle. Neither is a pure stat stick: each one's value depends on *where* it sits.

| id | Name | cat | coin | Effect / lvl | Justification |
|---|---|---|---|---|---|
| `vault` | Vault | eco | 20 | At each wave end: +`(4% * L)` of held cash as interest, capped at `40*L` (+50% cap if adjacent to a Bounty Office, S4) | It rewards *not spending* cash, which creates a spend-now-vs-hoard tension with cash upgrades. Its cap ties it to Bounty adjacency, so the eco cluster gets a 3rd piece fighting for the core ring |
| `aegis` | Aegis Pylon | support | 22 | Core takes -4%/lv damage (cap 32%). Adjacent weapons get +10%/lv fire rate. **Adjacent eco buildings lose 15% output** (S5) | The first building that actively *punishes* mixed placement. It forces players to zone the grid into a defense quadrant and an eco quadrant, and that is the spatial puzzle |

- Draft weights: both enter the draft from run 3 (`save.runs >= 2`) so the opening stays simple.
- Art: `art/vault.svg` (gold strongbox, eco amber) and `art/aegis.svg` (hex pylon, support green).

## 12. Save v2 schema

```jsonc
{
  "version": 2,
  "coins": 0, "gems": 0,
  "core": {"dmg":0,"hp":0,"regen":0},
  "slots": {"<idx>": {"id":"mine","lvl":1}},
  "unlocked": [int],
  "runs": 0,
  "best_wave": 0,                         // = max of best_wave_by_tier
  "tier": 1, "best_wave_by_tier": {"1": 0},
  "speed": 1.0,
  "labs": {"lvls": {"coin":0, ...}, "slots": 2,
           "running": [{"track":"coin","to_lvl":1,"start":0,"end":0}]},
  "cards": {"owned": {"c_dmg": {"lvl":1,"copies":0}}, "equipped": ["c_dmg"], "slots": 2},
  "missions": {"day": 0, "list": [{"tpl":"kill","target":200,"prog":0,"claimed":false}], "bonus_claimed": false},
  "streak": {"day_idx": 0, "last_day": -1, "loops": 0},
  "last_seen": 0,
  "stats": {"kills": 0, "bosses": 0}
}
```
- `BaseMeta.migrate(s)` runs before `normalize`.
- A missing `version` means v1. Migration copies `best_wave` into `best_wave_by_tier["1"]`, sets `gems=0`, `tier=1` and `last_seen=0`. A `last_seen` of 0 means **no offline payout on the first v2 boot**.
- After migration, `version` is set to 2.
- `normalize` coerces every int, drops unknown ids, clamps levels, and guarantees `running.size() <= labs.slots`.
- Selftest must cover two cases: v1 to v2 migration is lossless, and v2 round-trips through JSON unchanged.

## 13. Base-screen UI information architecture (portrait 720x1280, one thumb)

```
+------------------------------ 720 ------------------------------+
| TOP BAR (y0-90)   coins 12.4k   gems 37   streak d4   [gear]     |
| BANNER (90-150)   offline / lab-done / mission-done toasts       |
| ---------------- TAB CONTENT (150-1010) ----------------------  |
|  Base:     5x5 grid (centre, 600px) + selected-slot action strip |
|  Labs:     slot cards (progress bar, timer, Rush N gems)         |
|            + scrolling track list (lvl, effect next, cost, dur)  |
|  Cards:    equipped row (slots, lock shows gem cost)             |
|            + 4x2 collection grid (lvl pips, copies bar)          |
|            + [Open Chest 20 gems] button                         |
|  Missions: streak ladder (7 pips, claim) + 3 mission rows        |
|            (bar, reward, Claim) + all-clear bonus row            |
| TIER SELECTOR (1010-1090)  < T2 x1.6 coins >  (locked: "T3 @ w40 in T2") |
| START RUN (1090-1180)   full-width primary button                |
| TAB BAR  (1180-1280)   Base | Labs | Cards | Missions  (badges)   |
+-----------------------------------------------------------------+
```
- All primary actions sit in the bottom 45%, within thumb reach. The tab bar is at the very bottom, with a red-dot badge when a lab is done, a mission is claimable or the streak is unclaimed.
- The tier selector and START are **always visible** across tabs, so one tap starts a run from anywhere.
- Hit targets are at least 88 px tall. Buttons use `ACTION_MODE_BUTTON_PRESS`, and overlay Controls use `MOUSE_FILTER_IGNORE`.
- **Run HUD additions:**
  - Top-right: a speed pill (`1x` / `1.5x` / `2x` / `2.5x`, greyed out until unlocked).
  - Next to the coin counter: the gem counter.
  - Top-left under the HP bar: a row of small perk icons (tap shows a tooltip).
- **Perk overlay:** a bottom sheet with 3 tall cards (same layout as the building draft), each with its name, effect lines and a red "COST" line on tradeoff perks. A slow-mo banner reads "PERK - wave 10".
- **Death screen:** the coin breakdown (wave coins, kills, boss bounty, tier mult, card/lab mult), gems earned, missions progressed, then a "Back to Base" button.

## 14. Tune keys (defaults above)
`tier_unlock_base, tier_unlock_step, tier_hp_base, tier_coin_step, tier_max, boss_bounty_base, boss_gem_t3, lab_slot3_gems, lab_slot4_gems, lab_rush_min_per_gem, offline_base, offline_eff, offline_min, offline_cap_base, perk_every, chest_gems, card_slot_gems_3/4/5, mission_bonus_gems, vault_rate, vault_cap, aegis_dr, aegis_rate, aegis_eco_pen, ranged_stop, ranged_fire, elite_shield_base, splitter_children`.

## 15. Invariants for QA / playtest
1. No dominant pure-eco or pure-defense base: the playtest's no-trivial-dominant check must still hold with vault and aegis in the pool.
2. Active play beats offline: 1 h of active play is at least 4x one hour of offline earnings.
3. Tier N+1 is reachable by a competent bot within 8 or fewer more runs of the tier N unlock (at the current meta).
4. Gem income is between 10 and 30 per day with every source maxed. There is no gem source tied to purchases.
5. All time systems are deterministic under an injected `now`.
