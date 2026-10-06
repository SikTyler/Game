# Corehold V3 — Parts (Weapon + Core built from parts)

Owner playtest 2 (2026-10-06): "The forge and core confuse me. Bring back core parts … I wanted a part system where weapons are built: ammo, barrels, power, etc. These combinations make a weapon artwork that is procedurally generated and unique … The core with its parts system is meant to do the same thing, focused on defense and eco, while the weapon is focused on attack."

V3 replaces the V2 gear engine (one Weapon item, up to 8 generic Modules, the Forge; `Gear.gd`) with two **assemblies** built from typed **parts**. A part's slot says what it does, so it is clear what you install and why.

Code: `Parts.gd` (rules), `data/PartDB.gd` (bases, slots, layouts), `PartVis.gd` (art), `ui/ArmoryView.gd` (WEAPON and CORE tabs), `ui/WorkshopView.gd` (Fabricator and Smelter), tests in `tests/st_parts.gd`, `tests/st_partvis.gd` and `tests/st_core_weapon.gd`.

## 1. Assemblies

### Weapon (attack), mounted on the Core
| Slot | Count | Role |
|---|---|---|
| **Receiver** (chassis) | 1 | Its rarity sets the layout. It also scales damage and rate (Heavy ×1.2 / ×0.85, Rapid ×0.85 / ×1.2 …), and half its power is added to every barrel. |
| **Barrel** | 1–4 | **The archetype**: how the Weapon fires. With several barrels, barrel 0 aims and each extra barrel fires on its own cooldown at the nearest body in its own sector (2 barrels opposite each other, 3 at 120°, 4 at 90°). An extra barrel with nothing in its sector holds fire. |
| **Ammo** | 1–2 | On-hit effects. |
| **Scope** | 0–1 | Range and precision. |
| **Power cell** | 0–1 | Attack rate and damage, with trade-offs. |
| **Muzzle** | 0–1 | Shot shaping: knockback, pierce, splash, chain. |
| **Magazine** | 0–1 | Rate, echo and shred. |

| Receiver rarity | Barrels | Attachments | Perk slots |
|---|---|---|---|
| Common | 1 | Ammo | 1 |
| Uncommon | 1 | Ammo, Scope | 1 |
| Rare | 1 | + Power, Muzzle | 2 |
| Epic | 1 | + Magazine | 2 |
| Legendary | 2 | all | 3 |
| Mythic | 3 | all | 3 |
| Exotic | 4 | all, 2 Ammo | 4 |

**Barrels**: 23 on 11 fire patterns. Each variant re-tunes its frame with a `sheet` (damage / rate / range multipliers and overrides).

| Barrel | Fires |
|---|---|
| Autocannon | Balanced shells with a small blast. |
| **Minigun** (new frame) | 6 light rounds a second, each at a random body among the nearest 3 around the target. |
| Sniper Rail | Huge damage that pierces the whole line, slow, long range. |
| Blast Emitter | A pulse in all directions around the Core. |
| Scattergun | A short cone of pellets. |
| Slag Lobber | Lobbed shells with a burning, slowing blast. |
| Arc Coil | Chain lightning between bodies. |
| Flame Nozzle | A cone that sets bodies on fire. |
| Missile Rack | Homing missiles. |
| Saw Launcher | Ricochet blades that shred. |
| Lance Emitter | A ramping beam. |
| Siege Mortar · Burst Carbine · Flechette Gun · Coilgun · Storm Coil · Plasma Caster · Frost Projector · Quake Hammer · Hornet Pod · Disc Thrower · Pulse Laser · Vulcan Cannon | Variants: huge slow craters, 3-round bursts, 10 piercing darts, rapid 4-pierce slugs, 9-body lightning, heavy burning bolts, a slowing no-burn cone, a crushing shockwave, 7 seekers, 9-body discs, fast ramping pulses, heavier rotary rounds. |

**Ammo** (14): Standard, Incendiary, Toxic, Armor-Piercing, Explosive, Cryo, Shock, Hollow Point, Ricochet, Reaper, Heavy Slugs, Siphon, Bounty, Seeker. **Scopes** (7), **power cells** (7), **muzzles** (6), **magazines** (6). See `PartDB.BASES` for the numbers.

### Core (defense and economy)
| Slot | Count | Role |
|---|---|---|
| **Heart** (chassis) | 1 | Its rarity sets the layout. It scales max HP and regen (Fortress ×1.25 / ×0.8, Dynamo ×0.9 / ×1.35 …); HP also gains 15% of its power. |
| **Plating** | 1–2 | Max HP, armor, thorns, damage reduction. |
| **Generator** | 1–2 | Regen, shield, lifesteal. |
| **Capacitor** | 0–1 | Run cash, interest, kill cash. |
| **Reactor** | 0–1 | XP, coins and run cash. |
| **Uplink** | 0–2 | Building damage and rate, troops, specials. |
| **Antenna** | 0–1 | Loot luck, draft luck, Scrap find. |
| **Shield Emitter** | 0–1 | Shield, damage reduction, thorns, slow. |

Heart layouts:
- Common: Plating + Generator.
- Uncommon: adds a Capacitor.
- Rare: adds a Reactor and an Uplink.
- Epic: adds an Antenna.
- Legendary: adds a Shield Emitter and a 2nd Plating.
- Mythic: adds a 2nd Generator.
- Exotic: adds a 2nd Uplink.

**A fresh save** has a Common Receiver, an Autocannon Barrel and a Heart, with no perks. That is exactly the base Core sheet. The other slots start empty, and the first drops and crates fill them.

## 2. Parts
`{uid, slot, base, rar, lvl, mw, seed, rr, perks: [{id, t, q, lock}], name, fav, new, src}`

- **Own effect**: the base's fx × power. Power = rarity base × (1 + 5% per level) × 1.06 per masterwork. Negative trade-offs never scale. Count keys (pierce, chain, luck …) gain +1 per 2 masterworks.
- **Perks**: a part has 1 / 1 / 2 / 2 / 3 / 3 / 4 perk slots by rarity. Weapon parts roll attack perks and Core parts roll defense / eco perks; Twin Feed never rolls.
- **Perk tiers**: **each perk has its own rarity tier** (T1 Common … T7 Exotic). The tier is rolled around the part's rarity: −1 25%, same 50%, +1 20%, +2 5%. Luck and a deep drop's item level (wave) push it up. The tier scales the value (×1 / 1.5 / 2.1 / 2.8 / 3.6 / 4.6 / 6.0).
- **Reroll** a perk for Scrap: `10 × RM × 1.25^rerolls × 4^locks`. Both the perk and its tier re-roll; pick 1 of 2 (3 with Enchanter's Eye) or keep the current one.
- **Lock**: 1 slot, up to 3 with Stabilizer. **Ban**: Blacklist research, per assembly.
- **Upgrade** for coins: `60 × RM × 1.17^(L−1)`, up to the rarity's max level. Every 5th level is a masterwork: +6% power and +1 tier on a random perk (jackpot +2).
- **Merge** 3 of one part type and rarity into the next rarity. The base keeps its look and perks, new slots roll, and the level halves.
- Names: Common and Uncommon parts carry their base name ("Minigun Barrel"). Rare and above get a seeded epithet and mark ("'Stormjaw' Minigun Barrel Mk II").

## 3. Getting parts
1. **Run loot**: elites, bosses, Couriers and caches drop parts (the V2 loot pipeline, with visible pity).
2. **Scrap crates**: Standard (120 Scrap, 1 part), Advanced (600, 3 parts, the first Uncommon+, +4 luck), Elite (2500, 5 parts, the first Rare+, +10 luck). Odds are disclosed live, and every crate counts toward pity. The **Part Contracts** research picks the part type at ×1.5 price.
3. **Fabricator** (Outpost building, Scavenge category, Relay 2, 6000 coins): a rotating shop paid in Scrap. At Lv1 it shows 3 offers every 8 h. Each level adds an offer every 2 levels (max 6), cuts 0.6 h from the restock (min 2 h) and 4% from prices, and adds 1.5 rarity luck. Forge Works buildings cut prices 2% per level. A manual restock costs 200 Scrap.
4. **Smelter** (Outpost building, Relay 1, 2500 coins): parts melt into Scrap (their salvage value) over 20 minutes, in parallel furnaces. It has 2 furnaces at Lv1 and +1 per 2 levels; each level is −6% time and +6% Scrap. A finished melt frees its furnace and pays out on its own. **Auto-Smelt** (research) melts low-rarity drops on arrival.

## 4. Looks (`PartVis.gd`)
- **Weapon** (a top-down turret):
  - the Receiver hub: shape by base, size by rarity;
  - 1–4 barrels fanned around it: each archetype has its own silhouette, and variants re-shape it;
  - a muzzle on every barrel tip;
  - the scope on top, the power cell behind, the magazine below, and ammo canisters coloured by ammo type.
- **Core**:
  - the Heart glow;
  - the plating shell: octagon, hex, spiked star, round, layered decagon or faceted crystal, and a second shell for the 2nd plating;
  - generator rings;
  - capacitor coils;
  - a reactor ring;
  - uplink dishes;
  - antenna masts;
  - a shield dome.
- The Core Look (pattern and three colours) paints the parts.
- The combined build appears in the run (turret on the Core), on the WEAPON and CORE screens, and on the Outpost Relay.

## 5. Migration
A V2 gear block is refunded as Scrap: the salvage value of every item. Then the starter kit is installed. Outpost, research, coins and progress are kept. The refund happens once; the save keeps `parts_refund` for a notice.

## 6. Build order (done)
B1 data and pure engine with tests → B2 run integration (multi-barrel fire, the Minigun, Heart-scaled HP) and the golden → B3 procedural visuals → B4 screens (Weapon and Core builders, crates, Fabricator and Smelter modals, the loot reveal) → B5 retire `Gear*`, ModuleDB, BrandDB and ForgeView, then the bot and the docs.
