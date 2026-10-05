# MASS_HORDE — genuine mass-horde redesign (Corehold PC)

Governing: `PLAYTEST_FEEDBACK_3.md` (owner, verbatim): waves of **100s → 1,000s → 10,000s**,
a **liquid, physics-based** crowd like *Sir, We Have an Orc Problem*; the `horde_mult` split (one designed enemy cloned into N fractional bodies) is
**REJECTED**. Then FEEDBACK_2, FEEDBACK_1, HORDE_BRIEF.

Sections are owned by role. Other roles append their own `§` section below; do not rewrite
someone else's section, add a dated note under it instead.

---

## §Design (horde-designer)

### D0. Principles

1. **Threat is volume, not HP.** A swarmling dies to almost any hit for most of a run. What
   kills the player is the *flow rate* reaching the Core, not one enemy's health bar. Scaling
   comes mainly from **more bodies per second** and **mix**, and only a little from per-body
   HP growth.
2. **Every body is designed.** Each unit has its own hand-set HP/dmg/speed/value at *mass*
   scale. Nothing is a `1/N` share of a bigger enemy. `en.share` and `horde_mult` go back to a
   legacy test knob: default **1**, never set by shipping code, no gate depends on it.
3. **The crowd is a fluid.** Units follow a flow field to the Core, push on each other
   (pressure/separation), fill gaps, pile up against walls and the Core, surge when the front
   dies, and splash back from knockback. Gameplay depends on this: chokepoints, walls and
   knockback have to change how many bodies arrive per second.
4. **Every weapon matters against masses.** Each weapon's DPS has to turn into kills per
   second against a dense crowd, or the weapon gets a clear elite/boss role.
5. **Economy is aggregated.** Each kill pays almost nothing. Each wave pays a designed total.
   Loot is common and low-value, and its total per wave is capped.
6. **Short first run.** A new player sees a crowd of 1,000+ within about 8 minutes and
   finishes or dies by about 12–15 minutes.

### D1. Unit roster (designed for mass)

Classes: **fodder** (most of the body count), **line** (shapes the flow), **heavy/special**
(answers a specific defence), **elite/boss** (kept from the current game). Existing ids are
reused where the role fits, so art and Codex entries carry over.

| id | name | class | role in the fluid | new or existing |
|---|---|---|---|---|
| `mite` | Swarmling | fodder | the "water". Tiny, fast, 1-hit. 60–80% of every wave | existing id, retuned |
| `drone` | Grunt | fodder | slower and denser. Packs behind swarmlings and forms the wall of bodies | existing, retuned |
| `skitter` | Runner | line | fast flankers. Low separation weight, so they slip through gaps in the mass and between walls | existing, retuned |
| `hauler` | Brute | heavy | high mass, so it **shoves** lighter bodies forward ("pushes the tide"). Resists knockback | existing, retuned |
| `ranged` | Spitter | line | stops at range and lobs acid at the nearest **building or wall**. Sits in the back of the mass | existing, retuned |
| `sapper` | Sapper | special | targets **buildings and walls** before the Core and explodes on contact (AoE to structures). Its flow field is aimed at structures | **new** |
| `shield` | Shieldbearer | line | frontal shield blocks projectiles in a 90° arc for itself **and bodies directly behind it** (pierce stops). Weak to AoE, chain and flank fire | **new** |
| `splitter` | Broodsac | special | on death releases 6 swarmlings (designed swarmlings, *not* shares) | existing, retuned |
| `courier` | Courier | bonus | runs **away**. Kill it for loot. Ignores the fluid (top layer) | existing |
| `elite` | Warlord | elite | shield + aura: +20% speed to fodder within 120 px (a "surge"). Killing it breaks the surge | existing, kit extended |
| `boss` | Behemoth | boss | huge mass. Knocks fodder aside and carries a crowd in its wake. One per boss wave, more at higher tiers | existing |

Physics parameters (owned by the sim; the values here are design targets):

| id | radius px | mass | sep. weight | knockback taken | notes |
|---|---|---|---|---|---|
| mite | 5 | 1 | 1.0 | 1.0 | |
| drone | 7 | 2 | 1.0 | 0.7 | |
| skitter | 6 | 1 | 0.4 | 1.0 | squeezes through the crowd |
| hauler | 13 | 12 | 1.0 | 0.2 | pushes others |
| ranged | 7 | 2 | 1.0 | 0.8 | holds at ~260 px from its target |
| sapper | 8 | 3 | 0.8 | 0.6 | |
| shield | 10 | 6 | 1.0 | 0.3 | facing = flow direction |
| splitter | 11 | 6 | 1.0 | 0.5 | |
| elite | 12 | 15 | 1.0 | 0.15 | |
| boss | 26 | 200 | 1.0 | 0.0 | |

### D2. Per-body tables (Tier 1, wave 1 base values)

Units: HP and damage in game units (the starting Gun hit is 6 dmg); speed in px/s; dmg is per
contact tick to Core or structure, applied once per 0.5 s while the unit is touching. `cash`,
`xp` and `coin` are **weights** used to split each wave's pool (D5), not absolute payouts.

| id | HP | dmg | spd | cash w | xp w | coin w | Core dmg on arrival* |
|---|---|---|---|---|---|---|---|
| mite | 2 | 0.25 | 90 | 1 | 1 | 0 | 0.25 |
| drone | 5 | 0.5 | 50 | 2 | 2 | 0 | 0.5 |
| skitter | 3 | 0.4 | 120 | 2 | 2 | 0 | 0.4 |
| hauler | 60 | 3 | 30 | 20 | 20 | 1 | 3 |
| ranged | 8 | 1.5 (proj) | 42 | 6 | 6 | 0 | 1 |
| sapper | 12 | 25 to structures, 2 to Core | 55 | 8 | 8 | 0 | 2 |
| shield | 40 (shield 30 frontal) | 1 | 38 | 15 | 15 | 1 | 1 |
| splitter | 25 (+6 mites) | 1 | 40 | 10 | 10 | 0 | 1 |
| courier | 30 | 0 | 140 | — | — | loot | — |
| elite | 300 + shield 3 + w/10 | 8 | 34 | 150 | 150 | 10 | 8 |
| boss | 3,000 × tier boss mult | 40 | 22 | 1,500 | 1,500 | 100 | 40 |

*Core contact is a continuous drain while bodies press on the Core, so the Core's HP
(about 200 at the start of T1) loses to **pressure**. One mite does nothing. 400 mites piled on
the Core lose it in seconds. That is the fantasy.

**HP growth with waves:** fodder and line units `×1.035^(w-1)`; heavies `×1.05^(w-1)`;
elites and bosses keep the existing curves (`hp_growth`, boss ramp). Rule of thumb: an
un-upgraded Gun one-shots mites until about wave 30. A player who keeps upgrading always
one-shots mites, and their decisions are about **kills per second against inflow**.

**Damage growth:** `×1.02^(w-1)` for all units. Core pressure grows mainly because more bodies
arrive at once.

### D3. Wave composition curve

The per-wave **body count** `B(w, tier)` is the headline number, and the run plan follows the
owner's 100s → 1,000s → 10,000s:

```
B(w) = round( 120 * 1.11^(w-1) * tierB(tier) )          # T1 tierB = 1.0
tierB = [1.0, 1.6, 2.5, 4.0, 6.0, ...]                   # T2 starts at ~2x the T1 opener
```

| T1 wave | bodies in wave | peak alive (target) | feel |
|---|---|---|---|
| 1 | 120 | ~100 | "a horde already" |
| 5 | 180 | ~150 | |
| 10 (boss) | 300 + boss | ~250 | |
| 15 | 520 | ~400 | |
| 20 (boss) | 860 | ~700 | **end of short first run** |
| 25 | 1,450 | ~1,100 | thousands |
| 30 | 2,450 | ~1,800 | |
| 35 | 4,150 | ~3,000 | |
| 40 | 7,000 | ~5,000 | |
| 45 | 11,800 | ~8,500 | **10k+** |
| 50 (T1 cap) | 19,800 | ~12,000 (alive cap 16,384) | tier-climax |

At T3 and above, wave 1 already has ~300 bodies and the tier reaches 10k around wave 30.

**Spawn delivery:** a wave arrives as **3–6 surges** (pulses 4–8 s apart). Each surge is a
dense arc 60–120° wide from one or two sides (the "allsides" modifier uses every side). The
alive cap is **16,384** (MultiMesh and sim budget). When the cap is reached, the spawner
**holds the queue** and never drops bodies. This replaces `MAX_ENEMIES * horde_mult`.

**Mix by wave** (share of body count. Elites and bosses are counted separately and added on
top):

| waves | mite | drone | skitter | ranged | shield | sapper | splitter | hauler |
|---|---|---|---|---|---|---|---|---|
| 1–4 | 80% | 20% | – | – | – | – | – | – |
| 5–9 | 65% | 20% | 10% | 5% | – | – | – | – |
| 10–19 | 55% | 18% | 10% | 6% | 4% | 3% | 2% | 2% |
| 20–34 | 50% | 16% | 10% | 7% | 6% | 4% | 4% | 3% |
| 35+ | 48% | 14% | 10% | 8% | 7% | 5% | 4% | 4% |

Elites: `floor(w/5)` from wave 5 (T1); Tiers.elite_weight raises this. Bosses: every
`boss_every` (10), with `1 + floor((tier-1)/2)` bosses. Couriers: 1 per wave from wave 3, plus
1 per 2,000 bodies.

Existing modifiers keep their meaning, but they act on **body count and mix**, never on a
split: `swarm` gives ×1.6 bodies and +15% mite share, with no HP cut; `allsides` spreads
surges to every side; `elitist` gives ×3 elites.

### D4. Weapon redesign for hordes

Current weapons: `gun, mortar, tesla, flak, railgun, frost`, plus troops, specials and walls.
Every weapon gets a **mass verb**. Damage stays in its current range, so the existing upgrade
and Labs math still apply. The *shape* changes.

| weapon | mass verb (new) | elite/boss role | target kills/s vs dense mites, T1 mid-upgrades |
|---|---|---|---|
| **Gun** | **pierce 3 (+1 per pierce upgrade, cap 12)**. Rounds pass through bodies in a line, and the falloff is ×0.85 per body | steady DPS | 8–15 |
| **Mortar** | AoE r=60 (upgrade to 110). **Knockback ring**: bodies in the outer half are pushed out, which parts the sea | heavy hitter vs Brute and Shield clusters | 30–80 per volley |
| **Tesla** | **chain 6 (upgrade to 20)**, jump 70 px, ×0.9 per jump. The best weapon against dense crowds | stun 0.2 s on elites | 20–60 |
| **Flak** → *Flamer* (keeps the id `flak`, renamed in the UI) | **cone 40°, 160 px**. Damage over time (burn 2 s) and spread: a burning body ignites neighbours that touch it for 0.5 s | weak vs bosses | 40–120 sustained |
| **Railgun** | Single target, **infinite pierce along the line**, no falloff. Charge 1.5 s. Against bosses: ×4 dmg to the first body hit if it is elite/boss | **elite/boss killer** | 20–200 in bursts (line through the mass) |
| **Frost** | Slow field r=90: −50% speed and **+viscosity** (bodies in the field resist pressure, so the flow backs up behind it). Freeze-shatter: frozen bodies that die deal 20% max HP to neighbours | applies Brittle (+25% dmg taken) to elites | 5–20 directly. It is a force multiplier |

Structures and specials:

- **Walls** are the fluid's terrain: they block flow, and the crowd piles against them and
  flows around. Wall HP is designed against Sapper and Spitter damage (a T1 wall holds about
  3 sappers). Walls only make sense against a liquid crowd, and they are the main skill
  expression for "chokepoint" play.
- **Knockback specials** (Shockwave/Nova specials and the mortar ring) push bodies with an
  impulse that scales with `1/mass`. The crowd splashes back and then refills the gap.
- **Troops** fight at the front of the mass. They need mass-scale stats (a troop melee
  **cleave** hits 3–5 bodies in a 90° arc) or they evaporate.
- Single-target-only effects that can't sensibly gain area (for example a "mark" crit) are
  re-scoped as **elite/boss** tools and say so in their tooltip.

**Weapon invariant:** with the starting kit and no upgrades, each weapon's kills per second
against a dense mite crowd at wave 10 must be ≥ 25% of the best weapon's. With upgrades, no
weapon may fall below 15% of the best weapon's mass kills per second **unless** it has an
elite/boss role and leads elite/boss DPS (that exception is the Railgun's).

### D5. Economy at mass scale

The economy is defined **per wave**. Per-kill values are derived from the wave pool, so the
player's total income does **not** explode when the body count goes up 100×.

```
cash_pool(w)  = 40 + 14*w + 0.6*w^2            # T1 wave 1 = 55, w20 = 560, w45 = 1,890
xp_pool(w)    = same shape * 0.8
cash per kill = cash_pool(w) * unit_cash_w / sum(unit_cash_w over the wave's planned roster)
```

A wave-1 mite is worth about 0.4 cash and a wave-45 mite about 0.13 cash. The value is stored
as a float and paid out through a **cash accumulator**. The UI shows the aggregate ("+124" per
surge, ticking), never one popup per kill.

- **Leak penalty:** a body that reaches the Core forfeits its share. Clearing everything
  earns 100% of the pool. A typical good wave earns 85–95%.
- **Coins/meta:** only from heavies and above, plus wave clear. Per wave
  `coin_pool(w) = 2 + 0.4*w`, of which 50% is paid on wave clear.
- **Loot/drops:** a per-wave drop **pool** (FB2 bounded pool, kept). Each drop rolls on
  **kills** with `p = pool_left / bodies_left`, so the drops spread across the wave regardless
  of its size. Common/low-value: 80% common, 18% rare, 2% epic at T1. Couriers and elites
  always drop. Hard cap of 6 drops per wave at T1, +2 per tier.
- **Wave-clear bonus:** 30% of cash_pool(w), paid at the end, which rewards holding the line.
- **Rewarded-per-run target:** a T1 run that reaches wave 20 earns about the same meta as the
  current T1 run that reaches its wave 20, so the meta pacing in IDLE_MATH and POWER_MODEL
  stays valid.

### D6. Kill counts, missions, achievements (rescaled)

Kill totals go up roughly 50–500× compared with the split model. Rescale every kill target to
the new numbers:

| item | old scale | new scale |
|---|---|---|
| Mission "kill N enemies" (daily) | 200–800 | **5,000 / 15,000 / 40,000** |
| Mission "kill N in one wave" | — | **new:** 1,000 / 5,000 |
| Mission "kill N with <weapon>" | 100 | 2,000 (Railgun/elite missions count **elites+bosses**: 10/25) |
| Achievement "Exterminator" ladder | 1k / 10k / 100k | **100k / 1M / 10M** lifetime |
| Achievement "The Tide" | — | **new:** 10,000 alive at once and survive the wave |
| Achievement "Wall of Flesh" | — | **new:** 2,000 bodies pressing on a single wall |
| Achievement "Parting the Sea" | — | **new:** knock back 500 bodies with a single impulse |
| Boss/elite counts | unchanged | unchanged |

Stats keep **per-unit-id kill counters** (int64) and **kills per weapon**. The Intel panel
shows kills/s, inflow/s, alive, and leak/s, which are the four numbers that describe the
fight.

### D7. Short first runs and the difficulty curve

- **The T1 first run ends at wave 20** (the second boss) as a soft goal: a "Run complete" panel
  with an offer to continue to wave 50. Target time: about 12–15 min, at ~35–45 s per wave.
  Waves 21–50 are optional endless-within-tier for the 10k climax.
- **Difficulty curve:** pressure index `P(w) = inflow_bodies_per_s * avg_dmg / player_kill_rate`.
  Targets: P ≤ 0.6 in waves 1–9 (learn), 0.6–0.9 in waves 10–19 (tension: the crowd reaches
  the walls), 0.9–1.1 at wave 20+ (it reaches the Core when you misplay), and > 1 at wave 40+
  unless the player builds well (the 10k wall).
- **Difficulty settings** scale **body count** (Easy ×0.6, Hard ×1.4, Brutal ×2.0) and only
  slightly scale HP (Easy ×0.9 … Brutal ×1.2), which keeps the identity of the mass.
- **Tiers:** each tier raises `tierB`, unlocks new units earlier (sappers from wave 1 at T3+),
  and adds bosses. Tier HP multipliers stay modest, at ≤ ×1.6 per tier for fodder.

### D8. Playtest invariants (replace the split-model gates)

These replace every gate that assumes `horde_mult`, `share`, or `MAX_ENEMIES * horde_mult`.
They are a **deliberate redesign** per FEEDBACK_3, not a weakening. Each old assertion is
re-aimed at the owner's intent:

| # | invariant | replaces |
|---|---|---|
| H1 | Bodies spawned in T1 wave 1 ≥ 100. By wave 25, ≥ 1,000. By wave 45, ≥ 10,000 per wave | x4 horde body-count gates |
| H2 | Peak alive reaches ≥ 10,000 in a T1 wave-45+ (or forced-wave) playtest without dropping a spawn (the queue holds at the 16,384 cap) | `max_bodies()` gate |
| H3 | No spawned body has `share < 1` in shipping config (`horde_mult == 1`) | split-ratio checks |
| H4 | Each body's HP equals its EnemyDB value × the designed growth (no `share` factor) | `pc_horde_hp` checks |
| H5 | Cash earned on a full-clear wave is within ±5% of `cash_pool(w) * 1.3` (pool plus clear bonus). Income does not grow linearly with body count | per-kill economy gates |
| H6 | Drops per wave ≤ the cap. Over a T1 run, drops ≥ 1 per 2 waves | loot cap gate |
| H7 | The bot clears T1 wave 20 (the first run is winnable) in 10–18 min of sim time | first-goal reachability |
| H8 | Weapon invariant from D4 (kills/s ratios measured headless against a dense mite field) | — (new) |
| H9 | Fluid sanity: with a wall between spawn and Core, ≥ 70% of bodies path around it (flow field), and none pass through. Knockback makes the mean radial distance increase within 0.3 s | — (new) |
| H10 | Determinism: same seed gives the same per-wave kills, leaks and cash, bit-exact over 3 runs | existing determinism gate, kept |
| H11 | Perf (PC, not CI-gated): 10,000 alive at ≥ 60 fps sim+render on the reference GPU; headless sim step ≤ 4 ms at 10k | — (new; logged, not asserted in CI) |
| H12 | No death spiral: a bot that loses the Core at wave N can reach wave N+3 on the next run with meta it earned | existing, kept |

### D9. Retirement of the split model

- `horde_mult` defaults to 1. It stays as a legacy/test knob (`Tune` key `legacy_horde_mult`)
  that is hidden from the shipping Settings UI. `_spawn_clones` and the `share < 1.0` branch in
  `_spawn` are reached only through that knob.
- The `pc_horde_hp`, `pc_horde_dmg` and `pc_horde_size_floor` tune keys become legacy-only.
- Body art size comes from the D1 radius table, not from `sqrt(share)`.

### D10. Hand-off notes to other roles

- **sim/engine:** C#-resident SoA (no per-call array copies), spatial hash, flow field (BFS
  over a 16 px grid, rebuilt only when walls or buildings change), pressure plus separation
  weighted by mass, impulse API for knockback, and a cap of 16,384.
- **render:** one MultiMesh per unit id (or one with per-instance custom data), with buffers
  written in bulk from C#. Corpses go into a decal accumulation texture.
- **balance/playtest:** implement H1–H12. Re-derive D2 and D5 numbers from bot runs and log
  any changes in a dated note under this section.
