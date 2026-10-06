# Corehold V3 — Parts (Weapon + Core built from parts)

Owner playtest 2 (2026-10-06): "The forge and core confuse me. Bring back core parts … I wanted a part system where weapons are built: ammo, barrels, power, etc. These combinations make a weapon artwork that is procedurally generated and unique … The core with its parts system is meant to do the same thing, focused on defense and eco, while the weapon is focused on attack."

V3 replaces the V2 gear engine (one Weapon item + up to 8 generic Modules, `Gear.gd`) with two **assemblies** built from typed **parts**. What a part does follows from its slot, so it is clear what you are installing and why.

## 1. Assemblies

### Weapon (attack), mounted in the Core
| Slot | Count | Role |
|---|---|---|
| **Receiver** (chassis) | 1 | Its rarity sets the layout: how many barrels, which attachment slots open, and how many perk slots. It also sets the base damage / rate scale. |
| **Barrel** | 1–4 | **The archetype**, i.e. how it fires. Each barrel fires on its own. With several barrels, each one covers its own sector around the Core (multi-directional fire). |
| **Ammo** | 1 | On-hit effects: burn, poison, armor-piercing, explosive, cryo, shock … |
| **Scope** | 0–1 | Range, crit, precision vs elites / bosses. |
| **Power cell** | 0–1 | Fire rate, damage, overcharge trade-offs. |
| **Magazine** | 0–1 | Burst, reload, echo (a free repeat volley). |

Receiver layouts:

| Receiver rarity | Barrels | Attachments | Perk slots |
|---|---|---|---|
| Common | 1 | Ammo | 1 |
| Uncommon | 1 | Ammo, Scope | 1 |
| Rare | 1 | Ammo, Scope, Power | 2 |
| Epic | 1 | Ammo, Scope, Power, Magazine | 2 |
| Legendary | 2 (opposed) | all | 3 |
| Mythic | 3 (120°) | all | 3 |
| Exotic | 4 (90°) | all | 4 |

**Barrel archetypes** (the run's fire patterns; each has a distinct feel):

| Barrel | Fires |
|---|---|
| Autocannon | Balanced single shells with a small blast. |
| Minigun | Many projectiles, very high rate, low damage per hit, slight spread. |
| Sniper Rail | Huge damage, pierces the whole lane, slow reload, long range. |
| Blast Emitter | A pulse in all directions around the Core (nova). |
| Scattergun | A short cone of pellets. |
| Slag Lobber | Lobbed shells with a big blast radius. |
| Arc Coil | Chain lightning between bodies. |
| Flame Nozzle | A cone that sets bodies on fire. |
| Missile Rack | Homing missiles with small blasts. |
| Saw Launcher | Ricochet blades that bounce through the crowd. |

**Ammo**: Standard (+damage), Incendiary (burn), Toxic (stacking poison; ignores armor), Armor-Piercing (+pierce), Explosive (+splash), Cryo (slow; crowd-scaled), Shock (+1 chain jump), Hollow Point (+crit damage).

**Scope**: Long Optic (+range), Red Dot (+crit), Hunter Sight (+damage vs elites / bosses), Thermal (+range and +crit).

**Power cell**: Overclock Cell (+rate), Dense Cell (+damage), Surge Cell (+rate and +damage, −max HP), Capacitor Bank (every 5th volley is a big one).

**Magazine**: Drum (+burst), Echo Chamber (+echo chance), Quickload (+rate after a kill streak).

### Core (defense and economy)
| Slot | Count | Role |
|---|---|---|
| **Heart** (chassis) | 1 | Its rarity sets the layout and perk slots, and the base HP / regen scale. |
| **Plating** | 1–2 | Max HP, armor, thorns. |
| **Generator** | 1 | Regen, shield. |
| **Capacitor** | 0–1 | Economy: cash per second, interest, kill cash. |
| **Reactor** | 0–1 | Economy: XP, coins from runs. |
| **Antenna** | 0–1 | Loot: loot luck, Scrap find, draft luck. |
| **Shield Emitter** | 0–1 | Shield, damage reduction (capped). |

Heart layouts: Common = Plating + Generator; Uncommon = + Capacitor; Rare = + Reactor; Epic = + Antenna; Legendary = + Shield Emitter and a 2nd Plating; Mythic and Exotic add perk slots.

## 2. Parts
`{uid, slot, base, rar, lvl, perks: [{id, tier, q, lock}], seed, name, fav, new, src}`
- **Base stats** come from the base (for example "Minigun Barrel") × rarity mult × level.
- **Perks**: each perk has its **own rarity tier** (Common … Mythic), rolled independently and shifted by the part's rarity and luck. The tier scales its value (×1.0 / 1.4 / 1.9 / 2.6 / 3.5 / 4.6). Perk slots by part rarity: 1 / 1 / 2 / 2 / 3 / 3 / 4. Perk pools are per slot family: attack perks on weapon parts, defense / eco perks on core parts.
- **Reroll** a perk for Scrap: it re-rolls the id and the tier (pick 1 of 2, or 3 with Enchanter's Eye) or keeps the current one. **Lock** up to the Stabilizer slots. Cost ×4 per locked perk.
- **Upgrade** with coins up to the rarity's max level; every 5th level is a masterwork (+1 tier on a random perk).
- **Merge** three of a slot type and rarity into the next rarity (kept from V2).

## 3. Getting parts
1. **Run loot**: elites, bosses and couriers drop parts and caches (the V2 loot pipeline, with parts instead of items).
2. **Scrap crates**: spend Scrap to open crates (Standard / Advanced / Elite) with disclosed odds and visible pity.
3. **Fabricator** (new Outpost building): a **rotating shop** of parts for large amounts of Scrap. Upgrades add offers (3 → 6), refresh faster (8 h → 2 h), lower prices and raise the rarity odds. A manual reroll of the shop costs Scrap.
4. **Smelter** (new Outpost building): a queue where parts melt into Scrap over time. Its level adds slots, speed and yield. It replaces instant Salvage; Auto-Salvage feeds the Smelter queue.

## 4. Looks
- **Weapon art** is drawn procedurally from its parts: receiver body (by rarity), barrels (the archetype's silhouette, 1–4, fanned), ammo canister / belt, scope, power cell, magazine; paint, and a rarity rim.
- **Core art** is drawn from its parts: plating shell (shape per base, spikes for thorns), generator rings, capacitor coils, reactor glow, antenna masts, shield dome.
- The combined Core + Weapon shows in the run (turret on the Core) and on the Outpost (on the Relay).

## 5. Migration
Save v6: a V2 gear block is refunded as Scrap (the salvage value of every item). A starter kit is added: a Common Receiver + Autocannon Barrel + Standard Ammo, and a Common Heart + Basic Plating + Basic Generator. Outpost, research, coins and progress are kept.

## 6. Build order
B1 data and pure engine (PartDB, Parts.gd, perks with tiers, crates, Fabricator, Smelter, migration) + tests → B2 run integration (core_def / run_fx, multi-barrel fire, ammo fx) + golden → B3 procedural visuals → B4 screens (Weapon and Core builders, crates, Fabricator / Smelter panels, loot reveal) → B5 retire `Gear*` / Forge, bot and docs.
