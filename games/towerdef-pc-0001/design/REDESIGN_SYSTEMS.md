# Corehold PC: Redesign Systems Spec (Cores / Drafts / Parts / Outpost / Reforge)

Source brief: `/root/.claude/plans/game-idea-incremental-roguelite-flickering-ember.md`. This document turns that brief into exact tables. Every number here is a starting tune: `Tune.gd` and the playtest power-ratio gate (§9) are the final authority. Pure-module owners are named per section.

**Save version note:** `BaseMeta.VERSION` is **already 3** in the current PC code (v1 → v2 → v3). The redesign schema is therefore **save v4**, migrating from v3. The brief calls it "save v3 schema", meaning the third-generation design; the integer stored in the save is 4.

Conventions:
- `L` = level, `W` = wave, `T` = tier.
- Percentages are multiplicative with each other and additive within one source, unless stated otherwise.
- Rounding goes to an int at display time only.

---

## 1. Cores (`Cores.gd`, `data/CoreDB.gd`)

The Core is the only permanent object on the run grid. It sits at the centre cell, fires its own attack, and produces cash/s.

### 1.1 Base sheets (Core level 1)

| id | name | archetype | dmg | rate (shots/s) | range (cells) | HP | regen/s | armor | cash/s | interest (per wave, of banked cash, cap) | attack behavior | trait |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| bastion | Bastion | balanced | 10 | 1.25 | 4.0 | 120 | 1.0 | 2 | 2.0 | 2% cap 50 | **Auto Cannon**: single projectile at the nearest enemy, 0.5-cell splash at 40% | **Steadfast**: +1% dmg and +1% cash/s per building on the grid (max 20) |
| foundry | Foundry | eco | 5 | 1.0 | 3.5 | 100 | 0.8 | 1 | 4.0 | 5% cap 150 | **Slag Spitter**: lobbed blob, 1.0-cell splash, leaves a 2 s slow (-20%) | **Compound**: the interest cap grows +10 per Core cash-track "eco" level; eco picks are 1.5x as likely |
| lance | Lance | single target | 28 | 0.5 | 5.5 | 90 | 0.6 | 1 | 1.5 | 1% cap 30 | **Charging Beam**: locks onto the highest-HP enemy in range; dmg ramps +15%/s while held on one target (max +150%); resets on switch | **Focus**: +25% dmg vs bosses and elites; buildings in range of the Core get -10% rate |
| tempest | Tempest | area | 6 | 0.8 | 3.0 | 140 | 1.2 | 3 | 1.8 | 2% cap 40 | **Pulse Ring**: expanding ring to full range, hits every enemy once, 0.3 s knockback | **Static**: every 5th pulse chains 40% dmg to 3 extra targets beyond range |
| hive | Hive | troops | 4 | 1.0 | 3.0 | 110 | 1.0 | 2 | 2.0 | 2% cap 50 | **Drone Bay**: keeps 3 drones alive (drone = 30% of Core dmg, 1.5 shots/s, 8 HP, 6 s respawn); Core gun is weak | **Swarm**: every troop hut on the grid gives +1 drone; troops get +10% dmg per Hive Core level band (L10/20/30) |

### 1.2 Level curve (permanent, bought outside a run)
- Cost to go L→L+1: `coins = round(200 * 1.18^(L-1))` + `core_cores = floor(L/5)`. Core Cores come from tier clears, bosses (5%) and Reforge.
- Max level: 40, or 50 after the Reforge node `core_ceiling`.
- Per level, every stat of that Core: dmg +6%, HP +5%, regen +4%, cash/s +4%. Rate and range do not scale with level; they come from parts and cash tracks.
- Breakpoints (all Cores): L10 trait strength x1.25; L20 attack-specific upgrade (Bastion double barrel, Foundry splash 1.5, Lance max ramp +200%, Tempest 2 rings, Hive 4 drones); L30 trait x1.5.

### 1.3 Part slot unlocks (all Cores)

| Core level | 1 | 5 | 12 | 20 | 30 | 40 |
|---|---|---|---|---|---|---|
| Slots | 2 | 3 | 4 | 5 | 6 | 6 + 1 Set slot (special parts only) |

Slot types cycle Frame, Barrel, Capacitor, Engine, Frame, Barrel. A part goes only in its own slot type; slot k is the k-th entry in that cycle.

### 1.4 Unlock conditions

| Core | unlock |
|---|---|
| Bastion | start |
| Foundry | clear Tier 2 (reach wave 30 on T2) |
| Lance | first Core Reforge |
| Tempest | 2-piece of any set equipped at once, **and** best wave ≥ 60 on any tier |
| Hive | complete the full Swarm set (4 parts), **or** 40 Reforge Shards (tree node `core_hive`) |

### 1.5 In-run cash tracks (Core upgrades bought with run cash)

These are The Tower-style workshop tracks. Cost of the next level is `base * growth^lvl`, and the level resets every run. The starting level of each track = Reforge node `head_start` (0–5).

| track | effect per level | base | growth | cap |
|---|---|---|---|---|
| Damage | +8% Core and building dmg | 20 | 1.22 | 60 |
| Rate | +3% Core attack rate | 30 | 1.25 | 40 |
| Range | +0.1 Core range | 40 | 1.30 | 20 |
| Eco | +0.4 cash/s, +0.5% interest cap +5 | 25 | 1.24 | 50 |
| Armor | +5% HP, +0.2 regen, +0.5 armor | 25 | 1.22 | 60 |

Pricing rule: track growth ≈ the wave HP growth (1.105/wave, §9) to the power 2. Each track level is bought roughly every second wave at the frontier.

---

## 2. In-run roguelite drafts (`Draft.gd`, `data/PerkDB.gd` → `data/PickDB.gd`)

- The grid starts empty except for the Core. It is 9x9 (Core at the centre), with ring 1 open and rings 2–4 opening at Core track total levels 10/30/60.
- **Draft triggers:**
  - XP level-up. XP comes from kills: `xp_next = 10 * 1.15^n`.
  - Perk waves every 5th wave, which offer one guaranteed Rare+.
  - The boss wave, which offers one guaranteed Epic+.
- A draft shows **3 choices**, 4 with the Reforge node `wide_draft`.

### 2.1 Rarity weights

Picks below Common have no weight. Insight is never boosted by luck.

| rarity | weight | luck scaling (per Luck point) |
|---|---|---|
| Common | 60 | -1.0 |
| Rare | 28 | +0.6 |
| Epic | 10 | +0.3 |
| Legendary | 2 | +0.1 |
| Insight | 0.4 (flat; 0 if run cap reached) | none |

### 2.2 Reroll and banish
- **Reroll:**
  - 1 free per run.
  - Further rerolls cost run cash `15 * 1.6^k` (k = rerolls bought this run).
  - Lab `reroll` (now in the Research Hall) adds free rerolls.
- **Banish:**
  - 1 per run, plus 1 per Reforge node `banish+` (max 3).
  - Removes that pick id from the pool for the rest of the run.
- **Duplicates:**
  - A building already on the grid shows up as a "Level up X" card, max level 5.
  - Weights are -50% for picks already at max.

### 2.3 Buildings (12+)
- Footprint is 1 cell unless noted.
- Level-ups add +35% to the main stat per level (L2–L5).
- "Adapted" means it existed as a permanent building; it is now draft-only.

| id | name | rarity | role | L1 stats | notes |
|---|---|---|---|---|---|
| gun | Gatling (adapted) | Common | dps | 6 dmg, 2.0/s, r3 | |
| mortar | Mortar (adapted) | Common | aoe | 18 dmg, 0.4/s, r4.5, 1.0 splash, min range 1.5 | |
| tesla | Tesla Coil (adapted) | Rare | chain | 9 dmg, 0.8/s, chains 3 @70% | |
| flak | Flak (adapted) | Common | anti-air | 8 dmg, 1.5/s, x2.5 vs flyers, cannot hit ground | |
| railgun | Railgun (adapted) | Epic | pierce | 60 dmg, 0.25/s, pierces line r7 | |
| armory | Armory (adapted) | Rare | buff | adjacent buildings +15% dmg | |
| beacon | Beacon (adapted) | Rare | buff | radius 2: +10% rate, +0.3 range | |
| bulwark | Bulwark (adapted) | Common | defense | Core +40 HP, adjacent buildings +20% HP | |
| aegis | Aegis (adapted) | Epic | shield | 60-pt Core shield, regen 6/s after 4 s idle | |
| barricade | Barricade (adapted) | Common | path | 2x1, blocks/slows ground path, 200 HP | |
| mine | Gold Mine (adapted) | Common | eco | +0.8 cash/s | trades a defense cell for eco |
| oilmill | Oil Mill (adapted) | Rare | eco | +2.0 cash/s, -10% rate on adjacent buildings | |
| bounty | Bounty Post (adapted) | Rare | eco | +20% kill cash in radius 3 | |
| vault | Vault (adapted) | Epic | eco | +2% interest, +100 interest cap | |
| refinery | Refinery (adapted) | Rare | eco/xp | +15% XP, +0.5 cash/s | |
| frost | Cryo Spire (new) | Rare | control | slows 30% in r2.5, 3 dmg/s | |
| obelisk | Siphon Obelisk (new) | Legendary | sustain | 1% of all dmg dealt heals the Core | max 1 |

### 2.4 Upgrade packs (8+)
These are one-shot instant picks that last for the run.

| id | name | rarity | effect |
|---|---|---|---|
| pk_arsenal | Arsenal Pack | Common | +12% dmg all |
| pk_overclock | Overclock Pack | Common | +8% rate all, -5% Core HP |
| pk_fort | Fortify Pack | Common | +20% Core HP, +1 armor |
| pk_ledger | Ledger Pack | Common | +0.6 cash/s, +5% kill cash |
| pk_optics | Optics Pack | Rare | +0.5 range all |
| pk_crit | Precision Pack | Rare | +8% crit chance (crit x2) |
| pk_logistics | Logistics Pack | Rare | Core cash tracks -12% cost |
| pk_core | Core Surge | Epic | Core attack +15% dmg, +5% rate (Tune `pc_core_surge_dmg` / `pc_core_surge_rate`; was +30% / +10%) |
| pk_barracks | Drill Sergeant | Rare | troops +25% HP and dmg, -2 s respawn |
| pk_gambit | Gambit | Legendary | +40% dmg all, enemies +15% HP |

### 2.5 Special attacks (6+)
- These are active abilities on hotkeys **1–4**. The first 4 taken fill the slots; a 5th pick replaces one of them (the player chooses).
- Controller: d-pad.
- Cooldowns scale -3% per extra copy, max 3 copies.

| id | name | rarity | cooldown | effect |
|---|---|---|---|---|
| sp_orbital | Orbital Strike | Rare | 30 s | target 1.5-cell circle, 25x Core dmg after a 0.8 s delay |
| sp_emp | EMP Burst | Rare | 25 s | all enemies -50% speed for 4 s, shields stripped |
| sp_repair | Repair Pulse | Common | 40 s | heal Core 35% max HP over 3 s |
| sp_overdrive | Overdrive | Rare | 45 s | Core rate x2 for 6 s |
| sp_napalm | Napalm Line | Epic | 35 s | drag a 4-cell line; burns 3x Core dmg/s for 5 s |
| sp_magnet | Cash Magnet | Common | 60 s | next 10 s of kills give x2 cash |
| sp_timewarp | Time Warp | Legendary | 90 s | enemies frozen 3 s |

### 2.6 Troop huts and troops
- A hut is a 2x2 building pick, max 3 huts per run.
- Troops spawn at the hut and **path out of the base** along the enemy lane.
- **Troop AI** (in `Troops.gd`, pure and seeded, run by the TowerState tick):
  - **seek**: the nearest enemy within 4 cells of the troop's leash anchor. The anchor is the hut's lane exit, and the leash is 6 cells.
  - **engage**: melee or ranged per its stats.
  - **retreat**: when HP < 25% and the troop is a sapper or drone; infantry never retreats.
  - Dead troops respawn at the hut after a delay.
  - Troops do not block pathing. Enemies attack troops in range with 50% of their contact dmg.

| hut id | rarity | troop | count | HP | dmg | rate | range | speed (cells/s) | respawn | special |
|---|---|---|---|---|---|---|---|---|---|---|
| hut_infantry | Common | Rifleman | 3 | 40 | 5 | 1.2/s | 2.0 | 1.2 | 8 s | taunts: enemies within 1 cell target it first |
| hut_sapper | Rare | Sapper | 2 | 25 | 30 (aoe 1.0) | on contact | melee | 1.6 | 12 s | suicide charge on elites/bosses first; x2 vs armored |
| hut_drone | Epic | Drone | 4 | 12 | 4 | 2.0/s | 2.5 | 2.5 (flies) | 6 s | ignores terrain; prioritises flyers |

- Hut level-ups (L2–L5): +1 troop at L3 and L5, +25% HP and dmg per level.
- The Outpost Barracks (§5) adds permanent troop tiers: +10% HP and dmg per tier, max 10.

### 2.7 Insight picks (super-rare, permanent)
- Effects are banked at the end of the run, whether it ends in a win or a loss.
- Per-run cap: 1. The Archive raises it to 2 at L3 and 3 at L6.
- Lifetime cap per stat is shown below. Reforge does **not** reset Insight.

| id | permanent effect | lifetime cap |
|---|---|---|
| in_dmg | +0.5% all dmg | 25% |
| in_hp | +0.5% Core HP | 25% |
| in_cash | +0.5% cash/s and kill cash | 20% |
| in_rate | +0.3% attack rate | 10% |
| in_luck | +1 draft Luck | 10 |
| in_drop | +1% part drop chance (relative) | 15% |
| in_crate | +0.5% crate Epic+ odds (relative) | 10% |

---

## 3. Parts, sets, crates, drops (`Parts.gd`, `Crates.gd`, `data/PartDB.gd`, `data/SetDB.gd`)

### 3.1 Rarity and leveling
- Max level by rarity: Common 5, Rare 10, Epic 15, Legendary 20.
- Benefit per level: +8% of the L1 benefit. The **drawback never scales**, so leveling rewards commitment.
- Scrap to go L→L+1: `10 * r * 1.25^(L-1)`, where r = 1/2/4/8 for Common/Rare/Epic/Legendary.
- **Salvage** (duplicates, or manually) gives Scrap = `{C:5, R:15, E:50, L:150}` + 50% of the Scrap invested. Locked parts cannot be salvaged.
- **Loadout presets:** 4 per Core. Swapping is free outside a run.

### 3.2 Parts (32)
Slots: Frame (F), Barrel (B), Capacitor (C), Engine (E). Set tag in brackets.

| id | slot | rarity | benefit (L1) | drawback | set |
|---|---|---|---|---|---|
| f_plating | F | C | +15% Core HP | -5% rate | |
| f_lightweave | F | C | +8% rate | -10% Core HP | |
| f_bulkhead | F | R | +3 armor | -0.3 range | [Bulwark] |
| f_regenmesh | F | R | +80% regen | -10% dmg | [Bulwark] |
| f_mirror | F | E | reflects 15% contact dmg | -15% cash/s | [Bulwark] |
| f_ledgerframe | F | R | +1.0 cash/s | -8% Core HP | [Mint] |
| f_hivecomb | F | E | +1 troop per hut | troops -15% HP | [Swarm] |
| f_glass | F | L | +35% dmg all | -30% Core HP | |
| b_longbore | B | C | +0.6 range | -8% rate | |
| b_shortbore | B | C | +12% rate | -0.5 range | |
| b_hollow | B | R | +20% Core dmg | -10% building dmg | [Lancer] |
| b_focuslens | B | E | Lance ramp +50% faster | +0.5 s retarget delay | [Lancer] |
| b_scatter | B | R | Core splash +0.5 cells | -15% Core single-target dmg | [Storm] |
| b_ringcaster | B | E | +1 pulse ring (Tempest) or +1 chain (others) | -10% rate | [Storm] |
| b_crit | B | R | +10% crit chance | -5% dmg | |
| b_bounty | B | R | +15% kill cash | -8% dmg | [Mint] |
| b_droneport | B | R | +2 drones (Hive) or +1 hut drone | -10% Core dmg | [Swarm] |
| c_overcharge | C | C | +15% special-attack dmg | +10% special cooldowns | |
| c_quickcap | C | R | -15% special cooldowns | -10% special dmg | |
| c_battery | C | R | +1 special slot charge (store 2 casts) | -5% rate | [Storm] |
| c_capacitor_arc | C | E | +25% chain/tesla dmg | -0.4 range | [Storm] |
| c_interest | C | R | +2% interest, +50 cap | -10% dmg | [Mint] |
| c_scope | C | E | +30% dmg vs bosses and elites | -15% dmg vs normal | [Lancer] |
| c_pheromone | C | R | troops +20% dmg | Core -10% dmg | [Swarm] |
| c_luckchip | C | E | +3 draft Luck | -1 draft choice on perk waves only | |
| e_turbine | E | C | +0.5 cash/s | -5% dmg | |
| e_reactor | E | R | +20% all dmg | -1.0 cash/s | |
| e_dynamo | E | R | +10% rate all buildings | -10% Core rate | |
| e_mintpress | E | E | +25% cash/s | -15% dmg all | [Mint] |
| e_bastionheart | E | E | +2% dmg per building (max 24%) | -1 grid ring opens later | [Bulwark] |
| e_railcore | E | L | +60% Core dmg | Core rate -25%, no splash | [Lancer] |
| e_queen | E | L | troops respawn -40% | Core cannot attack while 3+ troops are alive | [Swarm] |

**Specs supported:**
- balanced: plating, longbore, quickcap, turbine
- eco: Mint set
- single-weapon: Lancer + glass
- damage: reactor, glass, crit, overcharge
- troops: Swarm

### 3.3 Sets (5)
- A set counts distinct parts of that set that are equipped.
- A full set (4 distinct parts of it equipped at once, once ever) **permanently unlocks** its special part. The special part goes in the Set slot (Core L40), or replaces a normal slot of its listed type.

| set | members (choose any 4 for the full set) | 2-piece | 4-piece | special part unlocked (Legendary, has a drawback too) |
|---|---|---|---|---|
| Bulwark | f_bulkhead, f_regenmesh, f_mirror, e_bastionheart | +15% Core HP | Core immune to dmg for 2 s after dropping below 30% (once per wave) | **Citadel Heart** (E): +50% HP, +3 armor; -15% rate |
| Mint | f_ledgerframe, b_bounty, c_interest, e_mintpress | +10% cash/s | **Dividend:** +20% all damage at Eco track 50, scaled by Eco level (was: interest every 15 s; changed in the AC-29 eco pass) | **Golden Ratio** (C): cash/s x1.4; specials cost 5% banked cash to cast |
| Lancer | b_hollow, b_focuslens, c_scope, e_railcore | +10% Core dmg | Core attack pierces 1 extra enemy | **Singularity Lens** (B): Lance/Core hits shred 5% armor (stacks x5); -1 range |
| Storm | b_scatter, b_ringcaster, c_battery, c_capacitor_arc | +1 chain everywhere | every 10th Core attack is a free Pulse Ring | **Eye of the Storm** (F): pulse rings x2 dmg; Core HP -15% |
| Swarm | f_hivecomb, b_droneport, c_pheromone, e_queen | troops +15% HP and dmg | troops gain 1% lifesteal on hit and heal the Core 0.5 HP per kill; lifts the Queen Engine hold-fire; +13% all damage (AC-29 set pass) | **Brood Mother** (E): +1 hut max (4); buildings -10% dmg |

### 3.4 Crates
Pity counters are per crate type and are saved.

| crate | cost | parts | odds C / R / E / L | pity |
|---|---|---|---|---|
| Field Crate | 2,500 coins (x1.0 per tier) | 1 | 70 / 25 / 4.5 / 0.5 | Epic guaranteed every 20 opens without one |
| Supply Crate | 60 gems, or 1 Key | 2 | 45 / 40 / 12 / 3 | Epic every 10; Legendary every 50 |
| Vault Crate | 300 gems, or 4 Keys | 4 (1 Rare+ guaranteed) | 25 / 45 / 22 / 8 | Legendary every 15 |
| Set Crate (rotating weekly set) | 180 gems, or 3 Keys | 2, both from that week's set | 0 / 60 / 32 / 8 | Legendary every 20 |

- Duplicate handling: a duplicate becomes +1 copy. Up to 2 extra copies can be stacked into "stars" (+5% benefit each); beyond that it auto-salvages to Scrap.
- Field Crate cost scales with tier: x `(1 + 0.25*(T-1))`.
- Odds are disclosed in-game on the crate screen; this is a hard rule.

### 3.5 Drops (in-run, banked at run end)

| source | drop chance | quality |
|---|---|---|
| Boss (every 10th wave) | 12% part, 100% Scrap `5*T` | Rare+ (R 75 / E 22 / L 3) |
| Elite (marked, ~1 per 4 waves from W8) | 3% part | C 55 / R 35 / E 9 / L 1 |
| Courier (rare enemy: 0.6%/wave from W15; flees along the lane, 3x speed, 2x HP, despawns if it escapes) | 100% part + 1 Key | R 40 / E 45 / L 15 |
| Any kill | 0.05% Key | |

- Drops are seeded from the run RNG; the selftest replays them.
- Insight `in_drop` multiplies chance.
- The part cap per run is 3 plus Courier drops, which keeps it from being grindy.

---

## 4. Currencies

| currency | earned | spent |
|---|---|---|
| Coins | run end (wave reward), Outpost Coin Mill | Core levels, Field Crates, Outpost builds |
| Gems (premium) | bosses (daily cap existing), missions, streak, tiers, **Gem Mine** | Supply/Vault/Set crates, build skips, decor |
| Scrap | salvage, bosses, Scrap Refinery | part levels |
| Keys | Courier, rare kills, Key Forge, missions | crates |
| Core Cores | tier clears, bosses 5%, Reforge | Core levels (every 5th) |
| Reforge Shards | Reforge | shard tree |
| Run cash | in run | cash tracks, rerolls |

---

## 5. Outpost (`Outpost.gd`, `data/OutpostDB.gd`)

### 5.1 Map
- Map size is **14x10** cells. Only a 6x6 area around the **Core Relay** (2x2, fixed, centre-left) is open at start.
- **Expansion:** 8 plots (4x4 or 4x5 border chunks).
  - Plot k cost: `5,000 * 2.2^k` coins, plus `20*k` gems for k ≥ 4.
  - Plots unlock in any order that keeps them adjacent to an open area.
- Placement is free. Rotate with R, move for free, and demolish for a 100% refund while a build is queued or a 50% refund after.
- **Power:** a generator building produces only if it is **connected** to the Relay via Conduits (1x1, 10 coins) or adjacent buildings, using 4-neighbour flood fill. Unconnected buildings show a red plug icon.
- **Power budget:**
  - Relay supplies 10 power + 4 per Relay level (max 10).
  - Each building costs its listed power.
  - Generators over budget run at budget/demand efficiency.
- **Builders:** 1 at start, a 2nd from the Reforge tree, and a 3rd for 500 gems one-time. A builder runs one build/upgrade timer at a time.
- **Build-time skip:** 1 gem per 3 minutes remaining, rounded up.

### 5.2 Buildings
- Upgrade cost at level L: `cost * 1.6^(L-1)`. Time is `time * 1.4^(L-1)`.
- Production per level is +25% of L1, multiplicative with adjacency.
- Max level 10 unless noted.

| id | name | footprint | power | L1 cost | L1 build time | L1 production / effect | storage (L1, +50%/L) | adjacency |
|---|---|---|---|---|---|---|---|---|
| relay | Core Relay | 2x2 | supplies | fixed | | power, cap source; level gates the max level of other buildings (= Relay L+2) | | |
| mill | Coin Mill | 2x2 | 2 | 500 coins | 2 min | 60 coins/h, x tier mult `(1+0.5*(T-1))` | 8 h of output | +10% per adjacent Mill (max +30%); +15% next to a Warehouse |
| refinery | Scrap Refinery | 2x2 | 3 | 1,500 coins | 10 min | 6 Scrap/h | 12 h | +20% next to a Smelter decor-industrial; -10% next to Mill (noise) |
| gemmine | Gem Mine | 2x2 | 4 | 10,000 coins + 50 gems | 4 h | 1 gem / 3 h (L1) → 1 gem/h (L10) | 24 gems hard cap | must sit on a **Crystal Vein** tile (3 on the map: 1 in the start area, 2 in plots); +10% per adjacent Conduit-lit Lamp decor (max +20%) |
| keyforge | Key Forge | 2x1 | 3 | 8,000 coins | 1 h | 1 Key / 24 h (L1) → 1 Key / 10 h (L10) | 3 Keys | +10% next to a Gem Mine |
| research | Research Hall | 3x2 | 3 | 1,000 coins | 15 min | runs Labs (§5.4); 1 queue at L1, 2 at L4, 3 at L8 | | +5% lab speed per adjacent decor-scholar (max +15%) |
| barracks | Barracks | 2x2 | 2 | 3,000 coins | 30 min | permanent troop tier = level (+10% HP and dmg each) | | +5% per adjacent Training Yard decor |
| archive | Archive | 2x2 | 1 | 6,000 coins | 1 h | Insight per-run cap 2 at L3, 3 at L6; +1 Banish at L9 | | |
| warehouse | Warehouse | 2x2 | 1 | 2,000 coins | 20 min | +25% storage cap to buildings within radius 2 (+5% per level) | | |
| scrapyard | Salvage Yard | 2x1 | 1 | 4,000 coins | 30 min | +10% Scrap from salvage (+2%/L) | | |
| conduit | Conduit | 1x1 | 0 | 10 coins | instant | carries power | | |
| beaconpost | Outpost Beacon | 1x1 | 1 | 2,500 coins | 10 min | +5% production to all buildings within radius 2 (no stacking) | | |

Quantity limits by Relay level (Mill / Refinery / Gem Mine / Key Forge):
- Relay 1: 2 / 1 / 1 / 0
- Relay 3: 3 / 1 / 1 / 1
- Relay 5: 4 / 2 / 2 / 1
- Relay 8: 5 / 2 / 3 / 1

Every other building is limited to 1.

### 5.3 Storage, idle and offline
- Production accrues in real time into each building's own storage, up to its cap. **Collect** by clicking it, or with "Collect all" (unlocked at Relay 3).
- This **replaces** `Offline.gd`'s flat formula. Offline earnings = Outpost accrual over `now - last_seen`, clamped by caps and taking an injectable `now`.
- Cap rationale: 8 h means two check-ins a day are optimal and missing one costs at most about 1/3 of a day.

### 5.4 Research Hall absorbs Labs
- All 10 existing `LabDB` entries move unchanged in effect and cost and become Research Hall projects: speed, dmg, hp, coin, xp, startcash, offcap, offrate, reroll, labspeed.
- `offcap` is renamed **Storage Tech**: +10% all Outpost storage per level.
- `offrate` is renamed **Logistics Tech**: +5% Outpost production per level.
- New projects:
  - **Part Analysis**: +2% salvage Scrap per level, max 10.
  - **Crate Theory**: -2% Field Crate cost per level, max 10.
- Lab slots are now the Research Hall queue count.

### 5.5 Decor and blueprints
- Decor is 1x1 or 2x1. It costs coins (50–2,000) or gems (premium skins), and uses no power except Lamps (power 0.5).
- **Tags:**
  - industrial: Smelter, Crate Stack
  - scholar: Bookshelf, Orrery
  - training: Training Yard, Target Dummy
  - light: Lamp, Brazier
  - nature: Tree, Shrub, Pond
- Adjacency effects are capped at +20% per building.
- **Charm:** every 10 distinct decor placed gives +1% Outpost production, max +10%. This rewards personal styling without making it mandatory.
- **Blueprints:**
  - Save, name and load up to 5 layouts (positions + rotations).
  - Loading auto-places owned buildings and reports anything missing.
  - Reforge-tree blueprints are prebuilt templates (e.g. "Mint Ring") that unlock their layouts and give a one-time 20% build discount.
- **Themes:** ground tile palette sets (Ash, Verdant, Frost, Neon) from tier rewards.

---

## 6. Core Reforge (prestige) (`Reforge.gd`, `data/ReforgeDB.gd`)

**Requirement:** best tier ≥ 3, **or** lifetime coins since the last Reforge ≥ 1,000,000.

**Shard formula:** `shards = floor(k * sqrt(coins_since / 10,000))`, with k = 1.0 and +10% per Reforge node `shard_yield` level.
- Example: 1M coins gives 10 shards; 4M gives 20.
- The first Reforge gets a +5 bonus.

**Resets:**
- coins
- Outpost buildings and plots (Relay back to L1; decor and blueprints are kept)
- part **levels** (Scrap invested is refunded at 50%)
- Core levels (back to 1)
- Research Hall levels
- tier (back to 1)

**Keeps:**
- owned parts and stars, set unlocks, special parts
- Cores unlocked, cards, gems, Keys, Insight
- achievements, stats, cosmetics, shards and the tree

### 6.1 Shard tree (one tree, 3 branches + root)

| node | branch | cost per level | max | effect |
|---|---|---|---|---|
| root_forge | root | 1 | 1 | unlocks the tree; Lance Core |
| might | Power | 2 + L | 20 | +5% all dmg |
| bulwark_p | Power | 2 + L | 20 | +5% Core HP |
| head_start | Power | 4 + 2L | 5 | +1 starting level on every cash track |
| core_ceiling | Power | 15 | 1 | Core max level 50 |
| wide_draft | Power | 25 | 1 | 4 draft choices |
| banish+ | Power | 6 | 2 | +1 banish |
| prosperity | Economy | 2 + L | 20 | +6% coins earned |
| outpost_p | Economy | 3 + L | 10 | +8% Outpost production |
| starting_cash | Economy | 2 + L | 10 | +25 starting run cash |
| shard_yield | Economy | 5 + 2L | 10 | +10% shards |
| builder2 | Economy | 12 | 1 | 2nd Outpost builder |
| bp_mint | Economy | 6 | 1 | Mint Ring blueprint |
| bp_fortress | Economy | 6 | 1 | Fortress Grid blueprint |
| tempo | Mastery | 5 + 3L | 4 | +0.25x max game speed (stacks on the Labs speed) |
| scrap_p | Mastery | 2 + L | 10 | +10% Scrap |
| crate_luck | Mastery | 4 + 2L | 5 | +5% relative Epic+ crate odds |
| core_hive | Mastery | 40 | 1 | unlock the Hive Core |
| retain | Mastery | 10 + 5L | 3 | keep 10/20/30% of Outpost building levels through Reforge (rounded down) |

**Loop targets (§9):** Reforge #n should reach the previous best wave in ≤ 70% of the previous loop's time.

---

## 7. Cards, Tiers, Missions, Endless, Steam
- These stay as they are.
- Card effects that referenced permanent buildings are re-pointed to the draft equivalents (same ids).
- Tier rewards add Core Cores and Outpost themes.
- Missions gain "Collect from Outpost x3", "Open a crate" and "Upgrade a part".

---

## 8. Save v4 schema and migration (`BaseMeta.gd`, VERSION 3 → 4)

```
{ version:4, coins, gems, scrap, keys, core_cores, shards,
  cores: { owned:["bastion",...], active:"bastion",
           lvls:{"bastion":1,...}, presets:{"bastion":[[part_uid|""]*7]*4}, preset_idx:{"bastion":0} },
  parts: { next_uid:int, items:{ "<uid>":{id, lvl, stars, locked:bool} },
           sets_completed:["mint",...], specials_unlocked:["golden_ratio",...] },
  crates:{ pity:{ "field":{epic:0}, "supply":{epic:0,leg:0}, "vault":{leg:0}, "set":{leg:0} }, set_week:int },
  insight:{ "in_dmg":0.0, ... },                 # lifetime %, capped
  outpost:{ relay_lvl:1, plots:[int], buildings:{ "<uid>":{id,x,y,rot,lvl,stored:float,last_tick:int} },
            queue:[{uid, kind:"build"|"upgrade", ends_at:int}], builders:1,
            decor:{ "<uid>":{id,x,y,rot} }, blueprints:[{name, layout:[...]}], theme:"ash" },
  research:{ lvls:{...LabDB ids + part_analysis, crate_theory}, running:[...] },   # was "labs"
  reforge:{ count:0, coins_since:0, tree:{node:lvl}, best_time_to_prev:float },
  runs, best_wave, tier, best_wave_by_tier, tiers_rewarded, best_coin_rate, speed,
  cards, missions, streak, last_seen, stats, history, gem_log, boss_gems_today,
  settings, endless, achievements }
```

**Removed:** `core:{dmg,hp,regen}`, `slots`, `unlocked`, `labs` (renamed to `research`), `target_modes` (it moves to the per-run state).

### Migration v3 → v4
Pure, lossless where meaningful, idempotent, and run by `BaseMeta.migrate`.
1. **Permanent buildings** (`slots`): refund = Σ over slots of the total coins spent buying and upgrading them (using BuildingDB cost curves).
   - Credit 100% of the refund as coins.
   - Also grant a one-time **Outpost starter credit**: Coin Mill L1 placed and connected, plus `outpost_credit = 25%` of the refund (capped at 50,000), spendable only on Outpost builds.
   - `unlocked` cells are worth 500 coins each, added to the same refund.
2. **Core** `{dmg,hp,regen}` levels: the Bastion level becomes `1 + floor((dmg+hp+regen)/3)`, capped at 20. Any leftover goes into coin refunds at the old cost curve.
3. **Labs**: `labs.lvls` moves to `research.lvls` 1:1, and `labs.slots` becomes the Research Hall level (slots 1 → L1, 2 → L4, 3 → L8). The Research Hall is pre-placed and connected. Running labs keep their ends_at.
4. **Offline**: `last_seen` is kept. The first Outpost tick after migration accrues from the migration time, not from last_seen, so there is no double pay.
5. **Kept:** cards, tiers, missions, streak, stats, achievements, gems, settings, endless.
6. **Defaults:**
   - Bastion owned and active, Foundry owned if tier ≥ 2 is cleared.
   - 1 free Field Crate token.
   - Zero values for every other new key.
7. **Sanitize:** clamp all ints ≥ 0, drop unknown part ids, keep uids unique, and pull buildings back inside open plots (or return them to inventory as unplaced).

**Tests to add or update** (the behaviour change is deliberate):
- The selftest v3-save fixture now asserts that the refund total and the Outpost starter appear.
- Assertions on permanent-building purchases are replaced by assertions on Outpost builds.

---

## 9. Power-curve invariant (governing)

| quantity | growth per wave (frontier) |
|---|---|
| enemy HP | x1.105 |
| enemy count | +4%/wave until cap |
| enemy dmg | x1.06 |
| required effective DPS | ≈ x1.13 |

**Power ratio** = (player eff. DPS × EHP) / (wave HP × count × dmg) at the frontier wave.
- It must stay in **[0.8, 1.25]** across days 1–30 and reforge loops 0–3.
- In-run, cash income must keep pace: track growth 1.22–1.30 is bought on a rhythm of ~2 waves.
- Meta income (coins/day from the Outpost plus runs) must grow at the rate Core level costs grow (1.18/level), so roughly 1 Core level per 1–2 days at steady state.
- `playtest.gd` logs the ratio per wave, day and loop, and fails outside the band, on a plateau of more than 5 days without a frontier gain, or on loop time-to-previous-best > 70%.
