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

---

## §Architecture (sim-engine)

> Restored verbatim from 6c0b627: the §Design commit (2af198d) rewrote the file and dropped this
> section. The as-built implementation and its deliberate deviations are in §Sim engine below.


### A1. HordeWorld — C#-resident body store
- `HordeWorld` is a plain C# class (no `Node`) owning every body array as SoA `double[]`/`int[]`/`byte[]`: `px, py, vx, vy, hp, maxHp, radius, mass, speed, dmg, atkCd, slowT, slowM, shockT, hitT, kind, flags, gen`, plus a free list. The arrays stay on the C# side for the whole run. **No arrays are copied across the boundary on a tick.**
- GDScript gets a thin `[GlobalClass] HordeWorldHandle : RefCounted` that wraps one `HordeWorld`. Its methods take and return scalars or small packed results only: `Spawn(kind, x, y, count, seed)`, `Step(dt)`, `Count()`, the query API (§5), `DrainEvents()`, `FillMultiMesh(rid)`, `Save()/Load()`.
- Body identity is `(slot, gen)` packed into an `int` (a 20-bit slot and a 12-bit generation), so stale handles can be detected. Kind stats come from a `KindTable` that GDScript pushes once at boot from `Tune.gd`/the enemy defs. Rules data stays authored in GDScript; C# executes it.
- Capacity: grow-only, with power-of-two doubling and a hard cap of 65,536. A spawn past the cap is queued (the queue is a ring buffer in C#) and emerges as bodies die. That turns the hard cap into "the gate is full" pressure instead of dropped units.

### A2. Flow field toward the core
- Coarse grid of 32 px cells (128×128 for the 4096 px arena). Every cell stores an integrated-cost distance and a unit flow vector.
- Recomputed **only when the building set changes** (place, sell, destroy, or Core upgrade). TowerState bumps `buildings_version` and the handle calls `RebuildFlow(blockedCells, targetCells)` with packed int arrays. The recompute is a Dijkstra from the core cells, with 8-neighbour moves, weights 1/√2, and no corner cutting. Building cells are **obstacles with a high cost (e.g. 40)** rather than walls. A walled-in core still has a finite path, so the horde flows *into* the wall and chews through it. This is the Orc-Problem siege behaviour.
- Cost: about 16k cells, under 1 ms in C#. It runs on build events, not per tick. Each body samples its cell's vector with a bilinear blend of 4 cells to avoid lane banding.

### A3. Fluid crowd model (fixed step 1/60 s)
Per body, in ascending slot order:
1. **Seek:** `a = (flow·speed·slowMul − v) · k_accel`.
2. **Pressure/separation:** a uniform hash with a cell equal to 2× the max swarm radius (16 px). It is rebuilt each step with a counting sort (`head/link`, no allocation). Over the 3×3 neighbourhood, overlapping pairs push apart with `k_p · overlap/(r_i+r_j)`, weighted by `mass_j/(mass_i+mass_j)`. Heavies plough through swarmers, and swarmers pile against heavies and walls.
3. **Damping and limit:** `v *= (1 − k_damp·dt)`, then clamp `|v| ≤ vmax`. `vmax` is above the seek speed, so impulses can briefly overshoot. That gives the splash.
4. **Integrate:** `p += v·dt`. Then resolve against building discs and the core disc by projecting out and zeroing the inward normal velocity. The crowd **piles up** at a wall, and back-pressure propagates through the separation term. Gaps fill naturally, and when a wall dies the dammed mass **surges** through.
5. **Impulses:** `ApplyImpulse(x, y, r, strength, falloff)` adds `Δv = strength·(1−d/r)/mass` radially. Explosions part the sea, and the sea refills it.

### A4. Contact rule
A body whose disc touches a building disc (or the core) with `atkCd ≤ 0` emits an `ATTACK(target, dmg)` event and resets its cooldown. Ranged kinds emit `SHOT` within `r_fire`. Couriers emit `ESCAPE` at their exit. Events go into a C# ring buffer. GDScript calls `DrainEvents()` once per tick and gets one `PackedInt32Array` plus one `PackedFloat64Array`, **aggregated per target**: (target, hits, dmgSum). There are no per-body events, so 10k bodies on a wall give one row per building.

### A5. Combat query API (for GDScript weapons)
Every query runs against the same spatial hash. It returns aggregates, never per-body arrays, unless a small N is requested:
- `DamageRadius(x, y, r, dmg, impulse, flagsMask) -> [kills, hits, dmgDealt, cashSum, xpSum, coinSum]`
- `DamageCone(x, y, dirX, dirY, halfAngle, range, dmg, impulse)` and `DamageLine(x0, y0, x1, y1, width, dmg, pierceMax)`, both returning the same aggregate.
- `NearestN(x, y, n, maxR) -> PackedInt32Array ids` (targeting; n is at most 64). `DensestCell(x, y, range)` for splash towers aiming at the thickest knot.
- `Chain(startId, jumps, jumpR, dmg, falloff) -> aggregate + PackedVector2Array hop positions` (for the VFX).
- `ApplyImpulse` (§3), `ApplyStatus(x, y, r, slow, shock, dur)`.
- Death pass: a killed body credits `cash/xp/coin` into the aggregate, pushes a corpse decal `(x, y, kind)` into a capped ring (for example 4,096) for the view, and frees the slot at the end of the step. Kill counts, missions and achievements read the aggregates. The economy is designed per kill at swarm scale (see the balance section later), not scaled-down single-enemy values.
- Sample positions: each damage query also returns up to 8 hit positions for VFX. The view never iterates bodies.

### A6. Elites and bosses
These are the same world and the same arrays, with `flags` bits `ELITE` and `BOSS` and high `mass/radius/hp`. They take part in pressure, so a boss shoves the swarm aside. Their special abilities (aura, summon, charge) are C# switch cases keyed by kind code and run after the move pass. Summons call the internal `Spawn`. GDScript can ask `Bosses() -> PackedInt32Array` (fewer than 16) for health bars and the Intel panel.

### A7. Determinism
- All sim state is `double`, and Godot `Vector2` (float32) is never used in HordeWorld. Iteration always runs in ascending slot order. The hash is built deterministically, so bucket order follows slot order. There is no `Parallel.For` in the step: any future threading must be partitioned so the results do not depend on order (two-phase compute and apply).
- RNG: a per-world `xorshift64*` seeded from the run seed and the wave index. It is consumed only on the sim thread. `Math.Sqrt` is IEEE-exact. Avoid `Math.Sin/Cos` in the step, or table them, because cross-platform libm can differ.
- Bench verified: two fresh worlds stepped 60 times are bit-identical (below).

### A8. Budgets (60 fps = 16.7 ms frame)
| Item | 10k | 20k |
|---|---|---|
| Sim step (move + hash + pressure) | ≤ 2 ms | ≤ 4 ms |
| Weapon queries (all towers) | ≤ 1 ms | ≤ 1.5 ms |
| MultiMesh fill + upload | ≤ 0.5 ms | ≤ 1 ms |
| Flow rebuild (event only) | < 1 ms | < 1 ms |
At 40k the dense core pile is roughly 4× the 20k cost, from neighbour counts. **Shipping caps live bodies at 20k**, with the excess queued at the gates (§1). "10,000s" waves are sustained streams of 10–30k total across the wave, with no more than 20k alive.

### A9. Rendering
- One `MultiMeshInstance2D` per visual class (swarm, heavy, elite/boss) with `use_custom_data` for tint and flash. `HordeWorldHandle.FillMultiMesh(rid, class)` writes a reused `float[]` (12 floats per instance for a 2D transform, plus colour and custom) and calls `RenderingServer.MultimeshSetBuffer` once per class per frame. `visible_instance_count` is set to the live count. The interpolation alpha is applied in C# from the previous and current positions.
- Corpses are drawn as a second MultiMesh from the corpse ring (blood decals). There is no per-body Node, and there are no `_draw` loops over bodies.
- Fallback: if the C# runtime is unavailable, there is no horde. Mass horde is C#-only; the mono build is the shipping target. GPU compute is not needed at 20k (bench). We will propose it only if the 50k+ ambition comes back.

### A10. Save and test hooks
- `Save()` returns a `PackedByteArray` (live bodies + RNG + queue + flow version). `Load(bytes)` restores it. Wave-boundary saves remain the default.
- `Checksum() -> int64` (FNV over px/py/hp bits) for determinism assertions in selftest: the same seed and inputs must give the same checksum after N steps.
- `Stats() -> Dictionary` (alive, queued, kills, max pile density, step µs) for the Intel panel and playtest metrics.
- selftest cases: spawn → flow reaches core; wall blocks → pile → surge on destroy; impulse parts the crowd; radius damage aggregates are correct; save/load round-trip checksum.

### A11. Migration
- **EnemyStore.gd** becomes a facade over `HordeWorldHandle`. Its public query/damage methods keep their signatures where weapons rely on them, but delegate. The GDScript SoA path is retired. The per-body fields (`share`, the `horde_mult` split) are removed. `horde_mult` stays a legacy test knob that defaults to 1 and is not exposed in shipping UI.
- **EnemyHash.gd** is replaced by the C# hash. Its tests are re-aimed at the C# queries (assertions updated deliberately and documented, not deleted).
- **HordeMove.cs** is folded into `HordeWorld.Step`. Its float32 bit-parity contract with GDScript is dropped deliberately: it existed only to mirror the GDScript path, which goes away. The determinism contract moves to the double-precision C# checksum.
- **TowerState** keeps rules, economy and waves. It owns `buildings_version`, drives `RebuildFlow`, consumes `DrainEvents` for building/core damage, and consumes query aggregates for the economy. Wave defs move from enemy counts × mult to **designed swarm compositions**: an early tier in the hundreds, mid tiers in the thousands, late tiers at 10k+.

### A12. Feasibility microbenchmark (measured 2026-10-05)
Standalone .NET 8 console (Release), 4-core Xeon @ 2.1 GHz (cloud container, much slower than the owner's desktop). Bodies were ring-spawned and converging on the core through the flow field + 16 px uniform-hash pressure + damping + vmax + core-disc projection. Timing covers 600 steps after a 120-step warmup, by which point a dense pile has formed at the core.

| Bodies | step ms | MultiMesh fill ms | deterministic |
|---|---|---|---|
| 10,000 | 1.09 | 0.03 | yes |
| 20,000 | 3.08 | 0.04 | yes |
| 40,000 | 11.77 | 0.12 | yes |

Verdict: 10k and 20k fit the 60 fps budget comfortably on single-threaded C# with doubles, even on this weak CPU. The super-linear 40k figure comes from pile density, which the per-pair cap and the 20k live cap address. Bench source: the scratchpad `hbench/Program.cs`. It is deliberately kept out of the Godot project so it is not compiled into the game assembly.


---

## §Sim engine — as built (sim-engine, 2026-10-05)

Code: `HordeWorld.cs` (C#, `[GlobalClass] RefCounted`), `EnemyStore.gd` (rules facade),
`EnemyHash.gd` (query facade), `TowerState._move_enemies / _hit / _reap / _densest`,
`Troops.gd` (taunt setter). `HordeMove.cs` deleted.

### S1. Ownership split (deviation from A1/A5, deliberate)
- **C# owns** every body's kinematics and status timers as `double[]` SoA: position, knockback
  velocity, seek speed, radius, speed, contact dmg, slow/shock/hit-flash/taunt timers, attack and
  fire cooldowns, courier exit, kind code, flags, alive flag. Nothing is copied INTO C# per step.
- **GDScript keeps** slot allocation (free list, eid map, spawn `order`) and the **rules data**
  (hp, shields, cash/xp/coin, kind strings, marks, shred). Reason: `_hit` carries shields, crits,
  Ironclad, Hunter Scope, shred, lifesteal and knockback-by-damage; moving those to C# would
  duplicate the rules engine. "Rules authored in GDScript, C# executes motion" (A1) is kept.
- Boundary traffic: `commit(s)` once per spawn (one `Put` with a packed row); small setters for
  status writes (`apply_slow`, `flash`, `set_shock`, `set_taunt`, `knock`, `kill`); one `Pull(n)`
  per step returning one packed array per mirrored field (pos, vel, cur_s, slow_t, slow_m,
  shock_t, hit_t, taunt_t, atk_cd, fire_cd) so every existing rules/view reader keeps working.
- Death: `_hit` calls `en.kill(s)` when hp crosses 0, so the body leaves C# motion and queries
  immediately; `_reap` asks C# for the `[alive, dead]` split of `order` (no 10k GDScript scan).
- `HordeWorldHandle` (A1) is not a separate class: `HordeWorld` itself is the RefCounted handle.

### S2. Flow field (A2, refined)
- 13 px cells (4 per 52 px building cell, aligned to the building grid), 13 building cells of
  open ground beyond the 11x11 grid (148x148 cells). Outside it bodies seek the Core directly.
- Dijkstra over a **16-neighbourhood** (orthogonal, diagonal, knight moves; no sweeping past a
  building corner from an open cell). The 8-neighbour octile metric made a wall's whole upwind
  side flow "down, then sideways"; the knight moves aim the crowd at the wall's ends.
- A walker pays to **enter** a building cell (`bld_cost` 40 x step length), so buildings are
  passable at high cost: a sealed Core still has a finite path through its wall.
- Flow vector = negative central-difference gradient of the cost field (a building neighbour of
  an open cell reads as the cell itself, so walls never repel the flow), bilinear-sampled.
- Rebuilt only when the per-slot building occupancy changes (`SetBuildings` compares bytes).
  Cost ~10–25 ms on the reference container (a hitch on place/sell/destroy, not per frame).

### S3. Liquid crowd step (A3, as built; fixed 0.05 s substep from TowerState)
1. Timers; courier straight run (top layer, no fluid); taunt pin; desired direction from the flow
   (direct to the Core within 2 flow cells of the stop ring); seek speed ramps to `spd x slow`.
2. Counting-sorted uniform hash (16 px cells) over the step-start positions; each bucket is a
   contiguous run, stable in slot order (cache friendly; Jacobi reads).
3. Pairs: bodies with radius > 8 px ("big": splitter, elite, hauler, boss) scan a wider reach and
   push both sides; small–small pairs scan 3x3 cells, at most `kmax` (24) overlapping
   neighbours. Push = overlap x `m_j/(m_i+m_j)` (m = r^2), capped at `0.35 x size`, scaled 0.5.
4. **Front blocking:** a body slows by `1 - 10 x (overlap ahead)`, where each body ahead counts
   only as much as it is NOT already moving away (last-step realised velocity). This is what
   makes the crowd queue and pile instead of compressing into itself, and lets a stream flow.
5. Knockback velocity with friction `exp(-6 dt)`; Core stop ring and building squares (inset
   1 px, so adjacent buildings leave no gap) are hard walls: project out, zero inward velocity.
6. Contact: pressing a building face whose cheapest route runs **through** a building ->
   attack it (sealed path). Otherwise slide along the face toward the cheaper side (exact ties
   split by slot parity): open-ground buildings are flowed around, not chewed. Core contact
   rule unchanged (front rank only).
7. Building hits are **summed per building** in C# (one `bld_hit` row per building per step,
   with `n` and `dmg`); Core hits/shots/escapes stay per body (bounded by the ring perimeter).

### S4. Query API (A5, as built)
`InRadius, Candidates, InRect, InLine, InCone, Nearest(exclude), NearestN, Density, Densest,
Chain, RadialImpulse, Impulse, SlowRadius`, all over living bodies in ascending slot order,
through a lazily rebuilt query hash. Damage application stays in GDScript (`_hit`), see S1.
`DamageRadius`-style aggregate damage calls were not added: weapons already aggregate events at
`horde_mult > 1`, and per-kill economy moves to the D5 pool (balance role).

### S5. Determinism
Doubles throughout, ascending slot order, Jacobi step-start reads, no RNG/threads/trig in the
step. `Checksum()` (FNV-1a over live slots' position/velocity bits) is gated in selftest (two
fresh 1,540-body worlds, 120 steps). The 120 s seeded fingerprint golden was re-recorded
(motion changed). The HordeMove float32 parity gate is retired with the GDScript move path.

### S6. Profile (headless, reference container: 4-core Xeon @ 2.1 GHz, Godot mono Debug build)
`horde_prof.gd`: full `TowerState` tick (spawns, C# step + mirror pull, every weapon's targeting
and damage through the C# queries, troops, reap), N live bodies (fodder mix + haulers) topped
up each tick on a 10-building board, after a 6 s warm-up so the pile has formed:

| bodies | full sim tick | C# step | rules + pull | mean overlap |
|---|---|---|---|---|
| 1,000 | 1.5 ms | 0.5 ms | 1.0 ms | 0.12 |
| 10,000 | **7.1 ms** (target ≤ 8) | 4.8 ms | 2.4 ms | 0.17 |
| 20,000 | 16.3 ms | 12.8 ms | 3.5 ms | 0.25 |

The sim runs 20 substeps/s, so 10k costs ~14% of one core; 20k ~33%.
**Bench correction:** the A12 microbenchmark (1.09 ms at 10k) spawned bodies 900–1800 px out
and timed 2 s of travel, so no pile had formed; dense-pile pair counts are 3–4x higher. The
numbers above are the real ones. H11's "≤ 4 ms headless at 10k" is not met on this CPU (C# step
alone 4.8 ms); it is a logged, not asserted, target.

### S7. Blockers / open items
- **horde_mult x4 still ships** (`Tune.horde_mult` default 4, `Main` sets it). Retiring it needs
  the D3 designed swarm compositions and the D5 economy (horde-designer / balance roles); the
  engine no longer depends on it.
- **Rendering**: `Battle.gd` still fills its MultiMesh from GDScript over the mirror (one pass per
  frame over every body). A9's C# `FillMultiMesh` is the render role's next step.
- **Intel roster** (`Intel.roster`) scans every body per frame in GDScript: fine at 1k, should
  read per-kind counts from C# at 10k+.
- Save/Load of live bodies (A10) not implemented: saves stay wave-boundary.
- Over 20k alive the pile cost grows super-linearly; keep the D3 alive cap (16,384).
- **playtest.gd FAILS 7 balance gates after the engine swap** (run once, 34 min, 2026-10-05):
  `mix_beats_weapon`, `first_run_short` (first run 494 s), `no_plateau_after_t3`,
  `rd_frontier_band`, `rd_no_runaway`, `ac29_wave_gap`, `ac25_fresh_wall`. All other
  playtest invariants pass (no death spiral, first goal reachable, determinism seeds, etc.).
  Cause: the motion model changed (open-ground buildings are flowed around instead of
  attacked; liquid pressure at the Core), which moves the balance of the still-shipping
  split-model waves. These are balance gates for the pre-FB3 model; per D8 they are to be
  re-aimed at H1–H12 by the balance/playtest role together with the D3 waves. Not weakened
  here.

---

## §Content — as built (content-weapons-economy, 2026-10-05)

Code: `data/EnemyDB.gd` (`MASS`, `MASS_MIX`, `TIER_B`), `TowerState.gd` (`mass`, `_build_mass_plan`,
`_spawn_mass`, `_reap_mass`, `_mass_try_clear`, `_fire_mass`, `_burn_step`), `HordeWorld.cs`
(`KC_SAPPER`, `ACT_BOOM`), `Troops.gd` (cleave), `data/MissionDB.gd`, `data/AchievementDB.gd`,
`Stats.gd`, `ui/Intel.gd`, `ui/Desktop.gd` (goal overlay), `art/sapper.svg`, `art/shield.svg`.

### C1. Retirement of the split (D9) — done
- `TowerState.mass` is the shipping ruleset (Main and the playtest bot set it). `Tune.horde_mult()`
  now reads `legacy_horde_mult`, **default 1**; nothing in shipping code raises it. `_spawn_clones`,
  the `share < 1` branch and the `pc_horde_*` keys are reachable only through that knob (the classic
  selftest still pins them). The crowd features that used to key off `horde_mult > 1` (big map,
  event aggregation, omnidirectional barricade aura / riflemen, carry hops) now key off `crowd()`
  (= mass or the legacy knob).
- H3 is gated twice (selftest + playtest `h3_no_split`): every body `share == 1`, knob == 1.

### C2. Roster (D1/D2) as built
`EnemyDB.MASS` holds the D2 table (hp, dmg, spd, cash/xp/coin **weights**, size = 2 x radius).
Deviations, all deliberate and re-derived from bot runs (D10):
- **Per-body HP growth** is `hp_growth(tier) / 1.11 x 1.04` (T1 ~1.096 / wave; heavies x1.015),
  not D2's 1.035. With 1.035 the total wave HP grew x1.149 / wave against a player whose power grows
  on the classic curve: a fresh bot reached wave 73 (1,800 s cap) and the run never ended. The body
  count still carries most of the growth (x1.11); the body HP carries the rest of the tier curve.
  Global `mass_hp_k` = 0.5 (x the existing `pc_enemy_hp` 2.5).
- **Contact damage** x `mass_dmg_k` 0.6 (and x1.02^(w-1) growth as designed): with D2's values a
  fresh first run walled at wave 8-11; at 0.6 the fresh wall is wave 12-15 (FB2 "short first runs").
- **Elites and bosses keep the classic HP curve** (D2 says they keep their curves); the boss also
  keeps the classic contact damage (D2's 40 per hit walled the first boss at wave 10). Elites use
  the designed 8 contact damage. Elites spawn `floor(w/5)` from wave 5 at every tier (+1 at T2-3,
  +2 at T4+; x3 with Elite Guard).
- **Sapper**: C# `KC_SAPPER` detonates on the first structure face it presses (sealed or not) and
  is reaped with no reward and no kill credit (`F_BOOM`); the blast is `bld / dmg` (12.5) x its Core
  hit. Its own structure-seeking flow field is **not** built (open item): it follows the shared
  field and blows up whatever it meets on the way.
- **Shieldbearer**: `guard` points (30 x HP scale) soak projectile hits whose shooter is within 45
  deg of its facing (it faces the Core); AoE, chain, burn and flank fire are not blocked. A Gun round
  stops at the shield. "Protects the bodies directly behind it" is modelled only through that stop.
- **Broodsac** releases 6 designed swarmlings (`mass_brood`), worth 0 cash (their value is inside the
  Broodsac's share), counted in the wave so the clear waits for them.
- **Not built** (open items): the Warlord's +20% speed aura, Spitters aiming at buildings/walls (they
  still fire at the Core from 230 px), per-unit separation weights / mass in C# (mass = radius^2).
- Art: `art/sapper.svg` (bomb-carrying crawler, lit fuse) and `art/shield.svg` (front plate facing
  the direction of travel), same 64 px outline style as the roster; Intel / tooltips use the D1 names
  (Swarmling, Grunt, Runner, Brute, Spitter, Sapper, Shieldbearer, Broodsac, Warlord, Behemoth).

### C3. Waves (D3) as built
- `B(w) = round(120 x 1.11^(w-1) x tierB x count modifiers)`, capped at 20,000 (`mass_b_cap`).
  T1: w1 120, w25 1,469, w45 11,841, w50 19,953. T3: w1 300, w30 6,187.
- 3-6 surges (`3 + w/10`) spread over the 25 s wave, each a dense 60-120 deg arc 0-140 px deep at
  the spawn ring, 35% of surges from two opposite sides; Encircled (allsides) scatters every body.
- Alive cap 16,384 (`mass_cap`): the plan **holds** (never drops); a held remainder spawns first in
  the next wave. Bosses, couriers and Broodsac young are never held.
- `wave_time` stays **25 s** (not D7's 35-45 s): it is the POWER_MODEL / IDLE_MATH clock that the
  economy, Outpost and every campaign gate are built on, and the owner's FB2 asked for 5-8 minute
  first runs (see C6).

### C4. Weapons (D4) as built — the mass verbs
| weapon | as built (mass) | H8 kills/s vs dense swarmlings, w10, Lv1 / Lv5 |
|---|---|---|
| Gun | 2 rounds per shot (target + next nearest), each pierces 3 (+2/lv, cap 12) x0.85 per body; a Shieldbearer front stops it | see C7 |
| Mortar | 0.75-cell blast (~60 px, +20%/lv), knockback ring 1.5 r; retargets past its min range when the crowd is at the wall | |
| Tesla | 3 arcs per discharge, each chains 6 (+3/lv + parts, cap 20), 70 px jumps, x0.9 per jump; 0.2 s stun on elites/bosses | |
| Flamer (`flak`) | a gout every ~1.3 s (rate x0.5) into a 40 deg cone 1.4 cells (+10%/lv): 0.15x lick + 0.3x/s burn for 2 s; burns tick 4x/s and spread to the nearest touching unburnt body | |
| Railgun | infinite pierce along the line in order, x4 on the first elite/boss/marked hit | |
| Cryo | -50% in the field (slowed bodies block the ones behind: the C# front-blocking rule = viscosity), Brittle x1.25 on chilled elites/bosses, freeze-shatter 20% max HP to up to 4 neighbours; direct damage x0.1 (it is the force multiplier) | |
- **Overkill smash** (every weapon, mass only): a killing hit's surplus x0.6 carries into the nearest
  touching body, up to 3 hops. Without it damage upgrades stopped buying kills once the swarm was
  one-shot (a x60-damage bot died at wave 36, a x1 bot at 24: the run was purely throughput-bound,
  which flattened meta progression). With it: x1 -> w13, x4 -> w26, x20 -> w40.
- **Troops** cleave: every troop attack also hits up to 3 more bodies in a 90 deg arc in reach.
- **Specials**: the Orbital Strike adds a shock wave (radial impulse 2r) that parts the sea; EMP /
  Time Warp already act on every body. Tempest's Static chain uses C# nearest-N (no 10k sort).
- **Cores**: Bastion cannon / Foundry slag / Tempest pulse are area attacks and need no change;
  the Lance beam targets the strongest body (an elite/boss tool by construction).
- Not built: Mortar "outer half only" knockback (the whole 1.5 r disc is pushed, falloff with
  distance); Frost viscosity as a separate pressure term.

### C5. Economy (D5) as built
- **Per-wave pools.** `cash_pool(w)` = the classic per-wave kill income (`wave_time / interval(w)`
  x `mass_cash_unit` 1.0, wave-1 units, paid x `cash_index` and the run multipliers), not D5's
  `40 + 14w + 0.6w^2`: D5 itself requires "a T1 run that reaches wave 20 earns about the same meta
  as the current one, so IDLE_MATH / POWER_MODEL stay valid", and this keeps that spine exactly.
  XP pool = 1.25 x the cash pool (the classic XP per wave). Per-kill cash/XP = pool x unit weight /
  sum of the planned roster's weights (boss and elites included).
- **Leak penalty**: a body's first Core contact flags it (`F_LEAK`): it pays nothing when it dies.
- **Clear bonus**: when every body of wave w is dead (and its plan fully spawned), the wave pays
  `0.3 x pool x (1 - leaked share)` cash and the clear half of its coins (`wave_clear` event).
- **Coins**: `coin_pool(w) = (2 + 0.4w) x 1.2` x the run coin multiplier; half is split over the
  coin-weighted units (heavies, elites, boss), half paid on clear (all of it on clear when the wave
  has no coin units). 35% of the kill half funds the wave's common-loot pool.
- **Drops**: each kill rolls `p = drops_left / bodies_left` against the wave's cap (6 at T1, +2 per
  tier); a drop pays `loot_pool / drops_left`. Parts / Keys odds per body = a classic plan entry's
  odds x (classic entries / bodies), so per-wave drop rates do not grow 100x with the body count.
- The UI shows wave-clear totals (`WAVE n CLEARED +$x`), never one popup per kill.

### C6. Kill counts, missions, achievements, first run, difficulty (D6/D7)
- Missions: "kill N" 5,000 / 15,000 (best wave 25+) / 40,000 (35+); new "kill N in one wave"
  1,000 / 5,000 (fed by the `wave_kills` event at each wave end). Per-weapon missions are not built
  (no per-weapon mission template existed); per-weapon kills are tracked (`kills_by_weapon` in the
  game_over event and `stats.kills_by_weapon`).
- Achievements (34 -> 39): Exterminator 100k (no split factor), Exterminator II 1M, III 10M, The Tide
  (a wave survived with 10,000 alive), Wall of Flesh (one Barricade takes 2,000 body hits in a wave;
  2,000 bodies cannot physically touch one 52 px wall, so it counts hits), Parting the Sea (500+
  bodies pushed by one Mortar / Orbital blast).
- Intel panel: ALIVE / IN/s / KILLS/s / LEAK/s over the last ~3 s; the roster is cached 4x a second.
- **First run**: T1 wave 20 (the second boss) is the soft goal: the first time a T1 normal run
  clears it, a "RUN COMPLETE" overlay offers *keep going* (to the wave-50 tide) or *bank now*.
  Fresh first runs die at wave ~12-15 (5-6 min at 25 s waves), the owner's FB2 "short first runs
  5-8 min" (the 300-480 s gate) rather than D7's 12-15 min; the campaign bot holds wave 20 on day 1.
- **Difficulty settings**: the game has no difficulty selector, so D7's Easy/Hard/Brutal body-count
  scaling is exposed only as the Tune knob `mass_body_mult` (open item for the UI owner).

### C7. Playtest invariants (D8) as built — gate changes
New job `mass` (1:1, no harness LOD) and gates `h1_wave_bodies`, `h2_peak_10k_held`, `h3_no_split`,
`h4_designed_hp`, `h5_pool_cash`, `h6_drops`, `h8_weapons_matter`, `h10_mass_determinism`; H7 from
the main campaign (`h7_first_goal_day1`). H9 (fluid sanity) stays in selftest (MASS-HORDE world
checks: 70% around a wall, none through, knockback spreads); H11 is logged (`ms_per_substep_at_peak`
in the H2 probe); H12 is the existing `no_death_spiral`.
- **H7 re-aimed**: "the bot clears T1 wave 20 in 10-18 min" -> "the campaign bot holds T1 wave 20
  within its first day (4 runs) and that run lasts <= 18 min" (with 25 s waves wave 20 is 8.3 min,
  so the 10-minute floor cannot hold; see C3).
- **H8 re-aimed**: the Cryo Spire is excluded from the kill-share rule and must instead lift a Gun's
  kills by >= 10% (D4 makes it the force multiplier with 5-20 direct kills/s, which cannot be 25% of
  a Mortar's). The Railgun's Lv5 exemption requires its elite/boss single-target DPS to lead.
- **Harness LOD** (`BOT_LOD_CAP` 2500, campaign jobs only): the 30-day campaign plays hundreds of
  runs; a wave planned above 2,500 bodies spawns one body per k carrying k x HP / damage / pool
  share / kill count. All first runs (T1 wave <= 28) and every H-gate run at 1:1.
