# Corehold: Reconciled Implementation Spec (retention set)

**This file is the source of truth.** It supersedes `SYSTEMS.md` and `ECONOMY.md` wherever they conflict. Acceptance criteria are listed in `BRIEF.md` (AC-n). Every constant is read through `Tune.num(key, default)` / `Tune.int_of(key, default)`, with the default shown as `key=default`.

## 0. Conflict resolutions (PM rulings)

| Topic | SYSTEMS | ECONOMY | **Ruling** | Why |
|---|---|---|---|---|
| Gem scale | chest 20, ~15–25/day | chest 40, slot 300, 30–40/day | **SYSTEMS scale.** Chest 20; lab slot 3/4 cost **60/150**; card slots 30/60/100 | smaller numbers are easier to read, and the lab slot is reachable in about 4 days rather than one sitting |
| Streak | 50c,2g,100c,3g,200c,4g,10g+chest | 5..30 gems (90/wk) | **SYSTEMS** | keeps gems ≤ 30/day |
| Boss gems | 1 per band (2 from T3), uncapped | 1, cap 3/run | **1 (2 from T3), cap 3 awards/run** | stops long runs from farming gems |
| First tier unlock | — | 50 gems | **+10 gems** once per tier | a milestone treat that stays inside the gem band |
| Lab tracks | 9 incl. armor, offrate | adds multiplicative Damage/Health | **10 tracks:** speed, dmg, hp, coin, xp, startcash, offcap, offrate, reroll, labspeed. **Cut `armor`** (Aegis and Bulwark already cover damage reduction) | the plateau needs multiplicative tracks |
| Lab curves | per-track growth | 1.8 / 1.6 | **per-track table below** (dmg/hp use 1.8 / 1.6) | |
| Offline formula | best_wave^1.15 × 0.25 | 15% of the best run's coin rate | **15% of the best recorded coins/min**, offrate +5%/lvl, max 5 levels (max 0.1875 ≤ 0.20) | makes AC-18 hold by construction |
| Synergy S1 | Bounty+Mine | cross-category Mine+Gun | **S1 = Mine + Gun "Ammo Works"** | gives eco a bridge to defense, and Aegis on the other side makes it a real choice |
| Other cross-pairs (Oil Mill+Tesla, Bounty+Mortar) | — | proposed | **Cut** | scope; 5 synergies is enough |
| Eco payoff | Vault | cash-out 2%, mine ×(1+0.03w) | **All three** | pillar 2 |
| Caps | — | armory +100%, gun 2.5/s, perm lvl cap 10(+5/tier) | **Adopt all** | dominance counters |
| Perk offer | 3 random | one per family | **one per family (offense/defense/economy)**, falling back to random untaken | supports AC-23 and the 40% pick cap |
| Wave Skip | coins for both | 50% wave coins, no kills | **ECONOMY** | |
| Second Wind | 20–50% | 30% | **SYSTEMS table**, once per run | |
| Speed lab | 3 levels → 2.5× | up to 3.0× | **3 levels → [1,1.5,2,2.5]** | |
| Mission reroll (10 gems) | — | proposed | **Cut** | scope |
| Elite x2 frequency at T4 | yes | — | keep | |

## ENGINE-A: meta systems (pure static modules, no Node)

Every module is `extends RefCounted`, static funcs only, preloaded with `const X = preload("res://X.gd")`. Every function takes the save `s: Dictionary` and mutates it in place. Functions that report something return `Array` of events (empty on failure); getters return values. Every time function takes `now: int`.

### A1 Save v2: `BaseMeta.gd` (extend) and `MetaSave.gd`
Schema (as in SYSTEMS §12, plus these changes): drop `labs.lvls.armor`; add `labs.lvls.dmg`, `labs.lvls.hp`; add `best_coin_rate: float` (coins per minute of the best banked run in the highest tier); add `gem_log: {"boss":0,"mission":0,"streak":0,"tier":0}` (lifetime totals, used by the playtest); add `tiers_rewarded: [int]`.
- `static func migrate(s) -> Dictionary` runs before `normalize`. v1 → v2 per AC-1.
- `static func normalize(s)` coerces, clamps and drops unknowns (AC-3).
- `static func bank(s, coins: int, wave: int, tier: int, run_minutes: float, now: int) -> Array` records `best_wave_by_tier`, `best_wave = max`, `best_coin_rate`, `last_seen = now`, and emits `tier_unlocked` (+10 gems).
- `perm_lvl_cap(s) = perm_lvl_cap(10) + 5*(highest_unlocked_tier-1)`, enforced in `try_upgrade`.

### A2 Tiers: `Tiers.gd`
`unlock_wave(n)=tier_unlock_base(20)+tier_unlock_step(10)*n`; `is_unlocked(s,n)`; `highest(s)`; `hp_mult(t)=tier_hp_base(1.5)^(t-1)`; `coin_mult(t)=1+tier_coin_step(0.6)*(t-1)`; `boss_every(t)= 8 if t>=5 else 10`; `elite_weight(t)`; `tier_max=8`. Roster gates live here as `allows(kind, t, wave) -> bool`.

### A3 Labs: `Labs.gd` + `data/LabDB.gd`
`LabDB.DEFS[id] = {name, max, base, growth, dur_base_s, dur_growth, effect}`:

| id | max | effect/lvl | base | growth | dur_base | dur_growth |
|---|---|---|---|---|---|---|
| speed | 3 | next speed step | 400 | 4.0 | 1800 | 3.0 |
| dmg | 30 | +5% dmg (core+weapons) | 80 | 1.8 | 300 | 1.6 |
| hp | 30 | +5% core max HP | 80 | 1.8 | 300 | 1.6 |
| coin | 20 | +5% coins | 60 | 1.35 | 300 | 1.30 |
| xp | 20 | +4% XP | 50 | 1.35 | 240 | 1.30 |
| startcash | 15 | +$15 start cash | 40 | 1.40 | 180 | 1.30 |
| offcap | 8 | +1 h offline cap | 150 | 1.60 | 1200 | 1.45 |
| offrate | 5 | +5% offline rate | 120 | 1.50 | 900 | 1.40 |
| reroll | 3 | +1 free reroll / run | 250 | 3.0 | 2700 | 2.5 |
| labspeed | 10 | −6% duration (floor 0.4×) | 200 | 1.55 | 1800 | 1.45 |

API: `cost(id,lvl)`, `duration(s,id,lvl)`, `start(s,id,now)->Array`, `claim(s,now)->Array`, `rush(s,slot,now)->Array` (gems = `ceil(rem_min/lab_rush_min_per_gem(30))`), `buy_slot(s)->Array` (`lab_slot3_gems=60`, `lab_slot4_gems=150`), `progress(s,slot,now)->float`, `level(s,id)->int`. Events: `lab_started`, `lab_done{track,lvl}`, `lab_rushed{gems}`, `lab_slot{n}`.

### A4 Game speed: `Labs.speed_steps(s) -> Array` (`[1.0,1.5,2.0,2.5]` up to the lab level) and `save.speed`. Sub-stepping lives in ENGINE-B.

### A5 Offline: `Offline.gd`
`compute(s, now) -> Dictionary {coins, minutes}`, `claim(s, now, double: bool) -> Array`. `rate = offline_frac(0.15) * s.best_coin_rate * (1 + 0.05*offrate_lvl)`; `minutes = clamp((now-last_seen)/60, 0, (offline_cap_base(4)+offcap_lvl)*60)`; returns 0 if `last_seen==0`, if the absence is `< offline_min(300)`, or if `now<last_seen` (and then sets `last_seen=now`). ×2 costs 2 gems. Event `offline{coins,minutes}`.

### A6 Missions and streak: `Missions.gd` + `data/MissionDB.gd`
`day_of(now, tz_offset) = floor((now+tz)/86400)`; `roll(s, now)` rolls once per day with `rng.seed = hash(day)` and Fisher-Yates over the 8 templates (SYSTEMS §9 table, targets/rewards unchanged). `on_run_events(s, events: Array)` advances progress from run events. `claim(s, idx)`, `claim_bonus(s)` (`mission_bonus_gems=5`), `streak_claim(s, now)` (SYSTEMS ladder; coin rewards × `min(2, 1+0.1*loops)`). Day-7 chest calls `Cards.open_chest(s, rng, free=true)`. Events: `missions_rolled`, `mission_done`, `mission_claimed`, `streak_claimed{day}`.

### A7 Cards: `Cards.gd` + `data/CardDB.gd`
The 8 cards and per-level values from SYSTEMS §10. `open_chest(s, rng, free=false)` (`chest_gems=20`); `equip(s,id)`, `unequip(s,id)`, `buy_slot(s)` (30/60/100, max 5); `mods(s) -> Dictionary` (merged equipped effects: `dmg, hp, cash, coin, xp, reroll, wind_hp, skip_chance`). Events: `chest_opened{card,new,lvl_up}`, `card_equipped`, `card_unequipped`, `card_slot`.

### A8 Run modifiers bundle: `BaseMeta.run_mods(s) -> Dictionary`
This is the single hand-off to TowerState: `{tier, hp_mult, coin_mult, boss_every, lab_dmg, lab_hp, lab_coin, lab_xp, start_cash, rerolls, cards:{...}, speed, allow_new_bldg: runs>=2}`. TowerState never reads labs or cards directly.

## ENGINE-B: run systems (`TowerState.gd`, data DBs, `Perks.gd`)

### B1 Modifier application
`setup(seed, save)` calls `BaseMeta.run_mods(save)`. Enemy hp/dmg × `hp_mult`. All run coins × `coin_mult * (1+lab_coin+card_coin)`. Damage × `(1+lab_dmg)(1+card_dmg)`; max HP × `(1+lab_hp)(1+card_hp)`. Cash × `(1+card_cash)`; XP × `(1+lab_xp+card_xp)`. Starting cash += `start_cash`; `rerolls_left = rerolls + card_reroll`.

### B2 Speed and sub-step
`tick(delta)`: `d = delta * speed`; `n = ceil(d / 0.05)`; run `n` sub-steps of `d/n` through the existing `time_scale()` path. Results must be speed-invariant (AC-15).

### B3 Boss bounty / cash-out / mine scaling
On a boss kill: `coins_run += floor(boss_bounty_base(25) * wave/10 * coin_mult)`, plus gems per A-rules capped by `boss_gem_cap(3)`. Emit `boss_bounty{coins,gems,pos}`, and track `gems_run` (banked by BaseMeta). Mine $/s = `1.2*L*(1+mine_wave_scale(0.03)*wave)`. On death, `cashout = floor(cashout_frac(0.02)*cash_earned*tier coin_mult)`, itemised in `game_over{breakdown:{wave,kills,boss,cashout,mult,gems}}`.

### B4 Enemies (`data/EnemyDB.gd`)
Add `ranged`, `elite`, `splitter` and `mite` with SYSTEMS §8 stats and weights, gated by `Tiers.allows`. Behaviour: ranged `ranged_stop=230`, `ranged_fire=2.0` (event `enemy_shot`); elite shield `elite_shield_base(3)+floor(w/10)` hits (`shield_hit`, `shield_break`); splitter → `splitter_children(2)` mites (`split`). Roll order: hauler, splitter, elite, ranged, skitter, drone.

### B5 Buildings (`data/BuildingDB.gd`)
Add `vault` (eco, 20 coin) and `aegis` (support, 22 coin), drafted only if `allow_new_bldg`. Vault: at wave end `+min(cash*vault_rate(0.04)*L, vault_cap(40)*L)` (cap ×1.5 next to a Bounty), event `interest{amt}`. Aegis: core damage reduction `aegis_dr(0.04)*L` (cap 0.32), adjacent weapons +`aegis_rate(0.10)*L` fire rate, adjacent eco output ×(1−`aegis_eco_pen(0.15)`). Caps: `armory_cap(1.0)` per target, `gun_rate_cap(2.5)`.

### B6 Synergies (in `compute_stats()`, output `links: [[a,b,"S#"]]`)
- S1 Mine+Gun (Ammo Works): gun fire rate +5% per adjacent Mine level (cap +50%).
- S2 Tesla→Mortar: an enemy shocked within 1.5 s by a Tesla adjacent to the firing Mortar takes splash ×1.3.
- S3 Bulwark on the core ring (slots 6,7,8,11,13,16,17,18): +3% damage reduction per level (cap 30%).
- S4 Vault+Bounty: vault cap ×1.5.
- S5 Aegis: as in B5.
Total core damage reduction from all sources is capped at 60% (`dr_cap`).

### B7 Perks: `Perks.gd` + `data/PerkDB.gd`
The 12 perks from SYSTEMS §7, each tagged with a family: offense {p_dmg, p_rate, p_range, p_glass, p_frenzy}, defense {p_hp, p_fort}, economy {p_cash, p_xp, p_greed, p_miser, p_bloodmoon}. `offer(state_rng, taken) -> Array[3]`: one per family where an untaken perk exists, filled from untaken perks via Fisher-Yates. `apply(stats, taken) -> stats` with the clamps from AC-24. TowerState: on waves `% perk_every(5) == 0` it emits `perk_offer{ids}` (queued behind the draft), `choose_perk(idx) -> Array` emits `perk_taken`, and `perks_taken` is exposed for the HUD.

### B8 Cards in-run
Second Wind: on the first death, revive at the card's HP%, emit `revive`. Wave Skip: at wave start, with chance `skip_chance`, advance the wave by 2, giving 50% wave coins for the skipped one and no kills (`wave_skip`).

## ART (SVG, `art/`, blocky flat style, category colours: weapon red, support green, eco amber)
Buildings: `vault`, `aegis`. Enemies: `ranged`, `elite`, `elite_shield` (overlay ring), `splitter`, `mite`, `bolt` (ranged projectile). Perks (12): `perk_dmg, perk_hp, perk_cash, perk_xp, perk_rate, perk_range, perk_glass, perk_greed, perk_fort, perk_frenzy, perk_miser, perk_bloodmoon`. Cards (8): `card_dmg, card_hp, card_cash, card_coin, card_xp, card_reroll, card_wind, card_skip`, plus `card_back`, `chest`. Labs (10): `lab_speed, lab_dmg, lab_hp, lab_coin, lab_xp, lab_startcash, lab_offcap, lab_offrate, lab_reroll, lab_labspeed`. Currency/UI: `icon_gem`, `icon_coin`, `icon_clock`, `icon_lock`, `icon_streak`, `icon_tier`, `tab_base`, `tab_labs`, `tab_cards`, `tab_missions`, `badge_dot`, `speed_pill`. Missions (8): `mis_kill, mis_wave, mis_boss, mis_eco, mis_cash, mis_perk, mis_lab, mis_upgrade`. FX are drawn as primitives (link lines, gold boss burst, shield pips), not sprites. A missing sprite falls back to the primitive `_draw`.

## UI (Main.gd, view only; layout per SYSTEMS §13)
- **Base screen:** top bar (coins, gems, streak day, gear) at y0–90; toast banner at 90–150; tab content at 150–1010; tier selector `< T2 ×1.6 >` at 1010–1090 (a locked tier shows "T3 @ w40 in T2"); START at 1090–1180; tab bar Base|Labs|Cards|Missions at 1180–1280 with red-dot badges. The tier selector and START are always visible.
- **Boot:** `migrate → normalize → Labs.claim(now) → Missions.roll(now) → Offline modal (if coins > 0)`.
- **Labs tab:** slot cards (track, progress bar, timer, Rush N gems, buy-slot lock) and a scroll list of tracks (lvl, next effect, cost, duration, Start).
- **Cards tab:** equipped row (locks show gem cost), a 4×2 collection (lvl pips, copies bar), and [Open Chest 20 gems].
- **Missions tab:** streak ladder (7 pips plus Claim), 3 mission rows (bar, reward, Claim) and the all-clear bonus row.
- **Run HUD:** speed pill top-right, gem counter beside coins, perk icon row under the HP bar, shield pips on elites, synergy link lines on the grid.
- **Perk sheet:** a bottom sheet with 3 tall cards, a red COST line on tradeoffs and the banner "PERK - wave N".
- **Death screen:** breakdown rows for wave, kills, boss bounty, cash-out, × tier, × lab/card, then gems and missions progressed, then "Back to Base".
- All Buttons use ACTION_MODE_BUTTON_PRESS and are ≥ 88 px tall. Overlays use MOUSE_FILTER_IGNORE.

## Tune keys (complete)
`tier_unlock_base 20, tier_unlock_step 10, tier_hp_base 1.5, tier_coin_step 0.6, tier_max 8, tier_gems 10, boss_bounty_base 25, boss_gem_t3 2, boss_gem_cap 3, lab_slot3_gems 60, lab_slot4_gems 150, lab_rush_min_per_gem 30, offline_frac 0.15, offline_min 300, offline_cap_base 4, perk_every 5, chest_gems 20, card_slot_gems_3 30, card_slot_gems_4 60, card_slot_gems_5 100, mission_bonus_gems 5, vault_rate 0.04, vault_cap 40, aegis_dr 0.04, aegis_rate 0.10, aegis_eco_pen 0.15, ranged_stop 230, ranged_fire 2.0, elite_shield_base 3, splitter_children 2, cashout_frac 0.02, mine_wave_scale 0.03, armory_cap 1.0, gun_rate_cap 2.5, perm_lvl_cap 10, dr_cap 0.6`. If AC-40 fails on tier pacing, change `tier_coin_step` to 0.8 first.

## Build order
1. ENGINE-A A1 (save) → A2 → A3/A4 → A5 → A6 → A7 → A8, with selftests for each.
2. ENGINE-B B1/B2 → B3 → B4 → B5/B6 → B7 → B8, with selftests.
3. UI, then uitest. 4. ART. 5. Playtest invariants AC-38..41.
