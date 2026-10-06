# Corehold V2 — design + phase plan (source of truth for V2 schemas and numbers)

> Copied from the approved plan; numbers here are the starting point and are re-tuned in P9 (deviations recorded in V2_PROGRESS.md).

## Context

Corehold PC (`games/towerdef-pc-0001`, Godot 4.6.3 mono, GDScript + C# `HordeWorld.cs`) lives only on branch `origin/towerdef-0001`. It is a mass-horde tower defense × roguelite × incremental × base-builder. The owner's verdict: the game is good, but runs don't feel unique, the meta feels "split up" across too many screens, the UI is crowded and boring, and the loot layer is too shallow to stay fresh.

The redesign refocuses the game on five pillars: **Outpost, Buildings, Core, Research, Weapon**. Its spine is a deep procedural gear system (weapons + Core modules) that the player gradually takes control of through research and buildings (luck, locks, bans, merges). The game wraps this in a neon-casino presentation.

Owner decisions (asked this session):
- **Weapon:** the forged weapon mounts in the Core's center slot. It auto-fires, and the player can take manual aim (mouse-aim, hold to fire) for a focus bonus.
- **Art:** neon casino sci-fi.
- **Saves:** hard reset, new save version, old saves ignored.
- **Delivery:** all phases in order. Commit and push after each phase with tests green, and keep a progress doc.

Branch: `claude/hopeful-johnson-5n1y7a` currently equals `main`, and `main` is an ancestor of `origin/towerdef-0001`. So step 0 is `git merge --ff-only origin/towerdef-0001`. All work then lands on the designated branch. `towerdef-0001-wip` (one interrupted tuning commit) is ignored.

## Competitor analysis → what we borrow

| Reference | What hooks players | Corehold V2 borrow |
|---|---|---|
| **The Tower** (closest analog) | In-run Attack/Defense/Utility trees with ~30 stats; Game Speed lab; modules with substats, reroll with **exponential lock cost** (0→10, 1→40, 2→160…), bans | Core Enhancement trees ×3 with ~10 tracks each; lock cost ×4 per locked perk; research-earned ban slots; steep Game Speed research |
| **Brotato** | Merge 2 identical same-tier weapons → next tier; shop lock; escalating reroll; luck; synergy-weighted offers | Merge-only building upgrades; draft-card lock; synergy weighting in drafts |
| **Vampire Survivors** | Evolutions (max weapon + passive); Arcana rule-changers at bosses; chest slot-machine | Evolutions (tier-3 weapon + adjacent support); boss-milestone Directives; Supply Drop slot spin |
| **Diablo 4 / Last Epoch / PoE** | Enchant one affix (2 options + keep); masterwork jackpots at ranks 4/8/12; top tiers drop-only; crafting verbs | Reroll one perk (pick of 2 + keep); masterwork jackpot every 5 levels; T6–T7 perks drop-only; Imprint/Merge/Reroll/Lock verbs |
| **Borderlands** | Parts × manufacturer × rarity gives billions of guns; brand quirks and palettes; generated names | Frame × Brand × Rarity × Perks × visual seed; brand quirk + palette; generated names |
| **Dome Keeper** | The center weapon defines its tree; gadget modules | Core center weapon + ring of modules that modify it |
| **Mindustry** | Damage-shape taxonomy (line, cone, chain, artillery, beam); overdrive buff-with-cost | Directional vs radius weapon families; support buildings with buffs that carry costs |
| **Islanders / Backpack Battles / Luck be a Landlord** | Live adjacency score preview; connector lines while dragging; "the slot machine is your build" | Hover shows +/− deltas over neighbours on both grids; merge and evolution lines while dragging |
| **Balatro / gacha (ethical)** | Staged scoring, rising pitch, number reels, shake scaled to size; visible pity; disclosed odds | Cache reveal sequence (beam colour → shake → perks one by one), visible pity bar, published odds, never paid |
| **Idle Slayer / Halls of Torment** | Rage/combo rewards active play; extraction risk | Combo meter in runs; Scavenger buildings as "loot you'd otherwise earn" |

The full write-up goes into the repo as `design/V2_VISION.md`, with sources.

## Requirement → phase traceability

| Owner ask | Where |
|---|---|
| Remove Core Bay / Crate Depot / Card Hall from the map; revert to the original buildings; no Factory | P1 |
| Outpost: building upgrades, adjacency buffs and nerfs, permanent Core-stat buildings, more buildings, loot Scavengers, finer grid | P6 |
| Single Core; customizable procedural look and colours; center weapon slot plus modifier ring | P1 (single Core), P4 |
| Crates removed; all drops from in-run looting (items or caches) | P1 (remove), P5 |
| Research: much steeper Speed/Grid/Lab-Discount costs; building unlocks and counts; loot/resist/enemy/atk-speed researches; QOL | P8 |
| Cards → Weapon Forge: forge, merge, upgrade, build, customize; perks rerolled for Scrap and lockable; procedural looks | P4 |
| Weapon used in runs (Core center; auto plus optional manual aim) | P4 |
| No building HP; enemies always attack the Core | P3a |
| Roguelite drafts on XP level-up, not per wave | P7 |
| 3× perks, buildings, weapons; merge-only upgrades; more roguelite engagement | P7 |
| Finer run grid; directional weapons alongside radius weapons | P3b, P3c |
| Remove all air | P1 |
| Core Enhancements: cheaper, many more types, Attack/Defense/Economy trees | P7 |
| Currencies: Coins, Scrap, Reforge Shards only | P1 |
| Core Upgrades need buildings, building levels and coins; requirements jump to the building or research | P6 |
| Massive UI and visual improvement (neon casino) | P2 foundation, every phase builds in it, P9 audit |

## Key design decisions (recorded in `design/V2_DESIGN.md` for owner review)

- **Gear engine.** One engine serves both Weapons (Core center) and Core Modules (ring sockets).
  - Variety comes from Frame × Brand × Rarity (C/U/R/E/L/Mythic/Exotic) × Perks (affix tiers T1–T7) × visual seed × paint.
  - **Reforge keeps all gear.** That makes gear the long-term chase.
- **Directional vs radius weapons.**
  - Radial: 360°, damage ×0.85.
  - Arc: a traverse limit around the facing.
  - Fixed cone or lane: damage ×1.4–1.8, fires only when a body is in its shape.
  - The flow field funnels enemies around buildings, so placement and facing matter.
- **No building HP.** Bodies flow around buildings. When the route is sealed they *squeeze through* at 0.35× speed, so they never attack structures. Sappers and Spitters hit only the Core. Barricade becomes a cheap 1×1 **Wall** that slows bodies.
- **Classic (non-mass) ruleset is dropped** in P3d. The mass horde is the only path, which cuts about 42 branches and a lot of brittle tests.
- **Insight jackpot picks and Missions stay.** Missions moves to a badge button. Keys, Core Cores, crate tokens and factory data are deleted.
- **Hard reset:** `BaseMeta.VERSION = 5`. Any older save normalizes to v5 defaults and shows a one-time "Corehold V2: fresh start" banner. The migrations v1–v4 are deleted.
- **"Lab cost"** is read as a steep **Lab Discount** research (−3% on all research per level).

## Phases (commit and push to `claude/hopeful-johnson-5n1y7a` at each phase end, with tests green)

All paths are relative to `games/towerdef-pc-0001/`.

### P0 — Setup, baseline, docs, test infra
- `git merge --ff-only origin/towerdef-0001`.
- `tools/setup_godot.sh` (idempotent): installs Godot 4.6.3 **mono** (GitHub release zip) and .NET 8 (`dotnet-install.sh`) under `~`, using `SSL_CERT_FILE=/root/.ccr/ca-bundle.crt`. NuGet goes through the proxy; see `/root/.ccr/README.md` if a restore fails.
- `tools/test_all.sh` runs, in order: import → `--build-solutions --quit` → `tools/parse_all.gd` → selftest → uitest → horde_fp twice (same hash) → `playtest -- job=smoke`.
- `tools/parse_all.gd`: loads every `res://**/*.gd`.
- Add `playtest.gd job=smoke` (about 2 minutes): a fresh T1 run (wave ≥ 5, coins > 0, no stall), a 3-run mini-campaign through a pluggable `MetaPolicy`, and a same-seed fingerprint check.
- Record the baseline: selftest 758 / uitest 182, golden hash, coins/day from `playtest only=main` (used to calibrate P8 costs). The 7 mass gates already fail today, so the full playtest is a P9-only gate.
- Docs:
  - `design/V2_VISION.md`: pillars and the competitor analysis.
  - `design/V2_DESIGN.md`: every schema and number in this plan.
  - `design/V2_PROGRESS.md`: phase log plus a **test ledger** (each deleted, rewritten or added check with its reason) and the golden-hash history.
- New selftest checks live in `tests/st_<module>.gd` (`static func run(t)`) and are called from `selftest._initialize`. Stages for removed systems are deleted whole, never loosened.

### P1 — Strip and hard reset
- **Delete:**
  - Factory: `Factory.gd`, `data/FactoryDB.gd`, `ui/FactoryView.gd`, `art/_gen_svg_factory.py`, `fy_*`/`dep_*`/`it_*` art. `FACTORY_PROGRESS.md` moves to `design/archive/`.
  - Crates: `Crates.gd`, `data/CrateDB.gd`, `ui/CrateView.gd`.
  - Cards: `Cards.gd`, `data/CardDB.gd`.
  - Parts and sets: `Parts.gd`, `data/PartDB.gd`, `data/SetDB.gd`, `ui/CoreBay.gd`, plus their art and the removed-Core art.
- **Restore** `ui/OutpostView.gd` from `5b10ce8`, minus `LANDMARKS`/`_draw_plaza`/`landmark_*`, minus the Key Forge. Re-apply the pre-Factory Main hooks (`git diff 5b10ce8 origin/towerdef-0001 -- Main.gd`):
  - `boot` uses `Outpost.away_report/claim_away` instead of `Factory.migrate_outpost`;
  - `_process` → `Outpost.tick`;
  - Outpost input and palette drag.
  - Also restore uitest `_outpost` from `5b10ce8`.
- `ui/Hub.gd` / `ui/Desktop.gd`: tabs Outpost (home) / Core / Research / Reforge, Missions as a badge. Top bar shows Coins / Scrap / Shards.
- `BaseMeta.gd`: v5 reset as above. Remove the cards, crates, parts, keys, core_cores, part_drops and factory blocks.
- `data/CoreDB.gd` / `Cores.gd`: a single `core` sheet (Bastion numbers), coin-only levels.
- **Air removal:** `FLYERS`, `flyers_only`, flak `prey`, `extra_drone` (`TowerState.gd:67,808,946,2125,2392,2433,3575`), the drone troop (`Troops.gd:12,29,31,150`), `hut_drone`, `in_crate` (`data/PickDB.gd`), `b_droneport`, related selftest and playtest literals.
- Interim `Drops.gd`: scrap from bosses and elites; couriers pay coins.
- Remove `crate_luck` and the Parts reset from Reforge; remove `part_analysis` and `crate_theory` from Labs.
- Clean up Achievements, Missions, PowerModel (PartDB reference), Intel/Battle feed (keys, core_cores) and `_shots.gd`.
- Keep the Reforge Outpost nodes (`builder2`, `bp_*`, `retain`): they work again now that the Outpost is restored.
- New interim `ui/CoreView.gd`: level, stat sheet, Level button.
- `horde_fp.gd`: one Core, no `hut_drone`; re-record `HORDE_FP_GOLDEN` with a rationale comment.
- **Tests:**
  - Delete the crate, parts, factory and save-v4 stages and the 4-Core and FLYERS checks.
  - Add `st_reset_v5` (v1–v4 saves and garbage → v5 defaults, banner once) and `st_outpost_restore` (place / upgrade / collect / away pay / plots).
  - Add a uitest for the Core tab.

### P2 — Neon casino UI foundation
- **Fonts:** `fonts/` gets Chakra Petch (headings and numbers) and Inter (body), plus `OFL.txt`, all from github.com/google/fonts.
- **`ui/Theme.gd`:** a Godot `Theme` built at boot — default font, and Button/Panel/Tooltip/Scroll/LineEdit styleboxes with a neon glow via shadow.
- **`ui/Kit.gd` tokens:**
  - Background `#070a12` → `#0d1220`; panel `#111827` at α 0.92; edge `#1f2a44`.
  - Accents: cyan `#39e6ff`, magenta `#ff3ea5`, gold `#ffd34d`.
  - Rarity: C `#9aa4b2`, U `#4ade80`, R `#38bdf8`, E `#a855f7`, L `#f59e0b`, Mythic `#ff3e6c`, Exotic animated prismatic.
  - New widgets: `panel_glow`, `card_frame(rarity)`, `tabs`, `big_number`, `req_chip`, `bar_glow`, `rarity_beam`.
- **Juice:** `vfx/Roll.gd` (number roll-up with a pop), `vfx/Beam.gd` (loot beam / shimmer), `Juice.shake(mag)` scaled by event size, and `Sfx.play(clip, pitch)` for rising-pitch sequences.
- **Nav:** OUTPOST / CORE / FORGE (enabled in P4) / RESEARCH / REFORGE, with a big PLAY button. Surviving screens (Battle, Reforge, Outpost, DraftPanel) are restyled by token only, because later phases replace them.
- **Tests:**
  - uitest layout audit extended: font ≥ 14, computed WCAG contrast ≥ 4.5 for every text/panel token pair, no overlaps, every button has a tooltip.
  - `st_kit`: roll-up is deterministic.
  - First visual-audit pass.

### P3 — Run engine (sub-commits a–d, each green)
- **P3a — squeeze instead of attack (HordeWorld.cs + TowerState):**
  - Derive `FLOW_PER_CELL`/`FLOW_MARGIN` from `cellPx`. Make the `ResolveBuildings` scan reach ⌈(r+0.5)/cell⌉, with a dilated near-building mask so distant bodies skip the scan.
  - **Squeeze rule:** set `F_SQUEEZE` when `RouteThroughBuilding` is true or the body stands in a building cell; skip the push-out and move at `horde_squeeze` 0.35×. This replaces the attack branch.
  - Delete `ACT_BLD`, `bldHits`, `bldDmg`. Sappers boom only on the Core (6×).
  - GDScript: delete `bld_hp`, `bld_lost`, `_sync_bld_hp`, `_repair_buildings`, `_destroy_building`, `_spit_target` and the building events.
  - Barricade → Wall (slow aura). "Wall of Flesh" now counts bodies squeezed past a Wall.
  - **Tests:** a sealed ring is crossed at ≤ 0.4× speed with zero building events; the open-wall flow (H9) still holds.
- **P3b — finer board:**
  - `CELL = 26`, `SIDE = 21` (N = 441), Core 3×3 at the center (`CORE_SLOT = 220`), `STOP_R = 44`.
  - `GRID_SIZES = [7,9,11,13,15,17,19,21]`. A 21-cell grid ≈ the old 10×10 in pixels, so view framing is unchanged. The range unit stays 78 px.
  - **Occupancy:** `slots[anchor] = {id, perm, run, rot, tier, mods}` plus `occ` (cell → anchor). New `owner_at`, `footprint`, footprint-aware `can_place` / `neighbors` / `ring_of` / `slot_pos`. `build_cap = 40`.
  - View: footprint ghost and sprites.
  - **Tests:** a relative-cell helper `t.cell(dr, dc)` replaces the `_r`/`_rc` mappings. Expect about 150–250 checks rewritten, each listed in the ledger.
- **P3c — directional framework:**
  - `data/WeaponDB.gd`: `{name, size, aim: radial|arc|fixed, arc, pattern, dmg, rate, range, p{}, tags, rarity}`.
  - `FirePatterns.gd`: `proj`, `pierce_round`, `pierce_line`, `cone_dot`, `lob_aoe`, `chain`, `beam_ramp`, `nova`, `bounce`, `homing`, `aura_slow`, `mine_layer`. The bodies of `_fire_mass` and `_core_fire` move here.
  - C#: `NearestInCone`, `AnyInCone`, `StrongestInCone`, `CountInLine`.
  - `rot` 0–7 in 45° steps. While placing, the wheel rotates; the new `rotate` action is **Z** (R is already taken). Click a building then Z rotates it for free. The ghost draws the wedge or lane.
  - Migrate the 6 weapons: Gatling arc 120°; Mortar radial 2×2; Tesla radial; Flamer fixed 50° cone; Railgun fixed lane 2×2; Cryo radial aura.
  - **Tests (`st_directional`):** never hits outside the arc; a fixed lane fires only when occupied; rotation persists; footprint collisions are rejected.
- **P3d — drop classic:**
  - Delete the classic branches and their stages (`_pc_spawn_stages`, `_horde_p34`, `_horde_stages`, `horde_mult`).
  - `horde_fp.gd` becomes mass sims on two boards; re-record the golden.
  - `horde_prof`: 10k bodies + 40 buildings ≤ 8 ms per tick.
  - Bot: places footprints and faces weapons toward the densest approach bearing.
  - uitest: place, rotate, drag a 2×2.

### P4 — Gear engine, Core + Weapon, Forge
- **Data:**
  - `data/RarityDB.gd`
  - `data/FrameDB.gd` — 10 frames: Autocannon, Slag Lobber, Lance, Pulse Nova (today's 4 Core attacks), Scatter (cone), Rail Driver, Arc Caster, Flame Projector, Swarm Missiles, Saw Launcher.
  - `data/BrandDB.gd` — 6 brands, each with a quirk, palette and name syllables.
  - `data/AffixDB.gd` — about 60 affixes. Value = `base·TSCALE[t]·(0.8+0.4q)`, with `TSCALE = [1, 1.5, 2.1, 2.8, 3.6, 4.6, 6.0]`.
  - `data/ModuleDB.gd` — about 22 modules: Twin Feed (double-shot), Echo, Splash Chamber, Penetrator, Ricochet, Arc Coupler, Crit Matrix/Lens, Accelerator, Rangefinder, Igniter, Cryo Core, Kinetic Ram, Shield Gen, Regen Cell, Thorn Plate, Siphon, Executioner, Giant Slayer, Bounty/Learning/Fortune Chips, Overclock (a trade-off module).
  - `data/NameDB.gd`
- **Item schema** (`save.gear.items[uid]`):
  - Fields: `{uid, kind: weapon|module, base, brand, rar, ilvl, lvl, mw, seed, rr, perks: [{id, t, q, lock}], paint: {p, s, g, pat}, name, fav, new, src}`.
  - `save.gear` holds `{items, next, equipped: {weapon, sockets[]}, pity: {e, l, m}, bans, forged, presets}`.
  - `save.core.look` holds `{shell, trim, paint}`.
- **`GearGen.gd`:** a seeded roll from one RNG stream, in this order:
  1. kind and base;
  2. rarity (luck-shifted, then pity);
  3. brand;
  4. perks drawn without replacement (respecting bans and groups), tier = `1+floor(ilvl/25)` capped at 7 — T6–T7 only from drops;
  5. name and paint.
- **`Gear.gd` operations** (pure functions that return events):
  - **upgrade:** costs `120·RM·1.17^L` coins. Every 5 levels is a masterwork: +6% base and +1 tier on a random perk. A jackpot (15%, up to 30% via research) gives +2 tiers or a new perk, shown with a slot-machine highlight.
  - **reroll one perk:** costs `10·RM·1.25^rr·4^locks` scrap. You get 2 candidates or keep the current perk (3 candidates with research).
  - **lock:** 0–3 per item via the Stabilizer research.
  - **ban:** Blacklist research, ≤ 3 per kind.
  - **merge:** 3 items of the same kind and rarity → rarity +1. The player chooses the base; the base keeps its frame, brand, seed and paint, gains a new perk slot (pick 1 of 2 from the sacrifices or a fresh roll), and keeps lvl `floor(max·0.5)`. Mythic needs research.
  - **imprint:** `50·RM` scrap. Destroys B and copies one of its perks onto A.
  - **salvage:** returns scrap.
  - **forge_new(frame, brand?):** `1500·1.08^min(forged, 40)` coins + 40 scrap; uses the forge odds and advances pity.
  - **paint / rename / favorite.**
- **Gear table:**

  | Rarity | C | U | R | E | L | M | X |
  |---|---|---|---|---|---|---|---|
  | Perks | 1 | 2 | 2 | 3 | 3 | 4 | 4 + sig |
  | Base mult | 1.00 | 1.12 | 1.28 | 1.48 | 1.72 | 2.00 | 2.30 |
  | Max level | 10 | 15 | 20 | 25 | 30 | 40 | 50 |
  | RM | 1 | 1.6 | 2.5 | 4 | 6.5 | 10 | 15 |
  | Drop % | 58 | 26 | 11 | 4 | 0.85 | 0.14 | 0.01 |
  | Forge % | 50 | 30 | 15 | 4.5 | 0.5 | 0 | 0 |

  Visible pity: Epic+ hard at 30 (soft from 22), Legendary+ hard at 150 (soft from 110), Mythic hard at 1000.
- **`Gear.run_fx`** feeds the existing `pfx`/`pf()` seam (`TowerState.gd:371,499`) plus new fx keys: `multishot`, `bounce`, `echo`, `burn`, `knock`, `thorns`, `execute`, `luck_run`.
- **`_core_fire`** dispatches the equipped frame through `FirePatterns`.
- **Manual aim:**
  - Hold LMB on the open field for ≥ 150 ms, or press `fire`; on a pad, the right stick aims and RB fires.
  - Bonus: +15% crit, plus a focus meter that fills over 4 s and gives up to +30% damage.
  - New `TowerState.set_aim(pos, firing)`. The bot always uses auto.
- **Sockets by Core level:** 2 at L1, 3 at L5, 4 at L10, 5 at L18, 6 at L28, 7 at L40, 8 at L55. The game starts with a Common Autocannon.
- **`GearVis.gd`** draws everything procedurally with `_draw`:
  - Weapons:
    - Frame body and barrel variants.
    - Seeded stock, sight and decal.
    - Perk-driven parts: crit → scope, multishot → twin barrel, splash → drum, chain → coil, burn → canister, pierce → long rail.
    - Masterwork fins and lights; level trims at 10/20/30; an animated rim for Legendary+.
  - The Core: 8 shells × 5 inner rings, a pod per module (rarity tint), and the player's paint and pattern.
  - Used in menus and in-run (the turret turns toward the target or cursor; reticle plus focus ring).
- **UI:**
  - `ui/ForgeView.gd`: inventory grid with filters; item card with stat compare; Upgrade / Reroll / Lock / Merge / Imprint / Salvage / Forge New; pity bars; disclosed odds.
  - `ui/CoreView.gd` tabs: Loadout (center plus sockets, drag or double-click), Look (shell, trim, colour pickers, pattern), Levels.
- **Tests:**
  - `st_gear`:
    - Roll determinism; rarity frequencies within ±10% over 100k rolls; hard pity.
    - Tier cap; rerolls never produce T6+.
    - Cost literals; lock limit; merge rules and rejections; salvage.
    - Masterwork with a fixed seed.
    - Every affix/module fx key is consumed.
    - Each frame kills in a field test; aim within 3°; focus meter.
    - 1000 seeds give ≥ 900 unique visual signatures.
  - uitest Forge keys: `forge:reroll`, `forge:lock:i`, `forge:merge`, `forge:salvage`, `forge:new:<frame>`; socket drag; paint picker.

### P5 — Loot, caches, casino reveal
- **New files:**
  - `data/LootDB.gd`: drop tables, caches, pity, disclosed odds.
  - `Loot.gd`: `realize(save, drops, rng)` and the scavenger API `roll_scavenge`.
  - `ui/LootReveal.gd`.
- **`Drops.gd`** emits items, caches, scrap and coins:
  - Elites have a 4% item chance.
  - Boss → Boss Vault; Courier → Elite Cache.
  - Per-wave item cap: 6, +2 per tier.
  - Drops use `drop_rng` only, and the run fingerprint must be invariant to luck.
- **Caches:**

  | Cache | Contents |
  |---|---|
  | Scrap Crate | scrap |
  | Field Cache | 2 items |
  | Elite Cache | 3 items, Rare+ guaranteed |
  | Boss Vault | 4 items, Epic+ guaranteed, plus scrap |
  | Reliquary (T4+ boss, 10%) | 5 items, Legendary+ guaranteed |

- **Banking:** `BaseMeta.bank_loot` realizes items on a meta RNG and applies pity.
- **In run:** loot beams in rarity colours in the world, plus Intel feed rows.
- **Reveal (Results → LootReveal):**
  1. A beam climbs white → highest rarity with rising pitch.
  2. Shake scaled to rarity.
  3. Cards flip; perks tick in one by one.
  4. Skip and Reveal All are always available; the Fast Reveal research halves the timings.
  5. Pity bars and the odds tooltip are shown.
- **Tests:** drop determinism, caps, odds sum to 100, a scripted 200-roll pity sequence, bank determinism. uitest: skip, reveal all, equip from the reveal.

### P6 — Outpost V2
- **`data/OutpostDB.gd` rewrite:**
  - 48×32 cells at half the old size; Relay 3×3; start area 12×12; the 17 plots scaled ×2 (cost `5000·2.2^n`).
  - Footprints: 1×1 for conduits, decor and pylons; 2×2 standard; 3×3 for Relay, Research Hall and Deep Scavenger.
- **Buildings:**
  - **Kept:** Mill, Refinery, Deep Mine, Research Hall, Barracks, Archive, Warehouse, Salvage Yard, Beacon, Conduit, decor.
  - **Core-stat buildings** (per level): Arsenal +2% damage, Reactor +1.5% rate, Bulwark Works +3% HP, Aegis Array +0.6% DR, Optics Lab +0.5% crit, Rangefinder +0.04 range, Treasury +2% run cash, Training Grounds +3% XP, Fortune Shrine +2 loot luck, Forge Works −2% forge costs.
  - **Scavengers:** Scavenger Post (item rolls, 1 per 6 h, stores 4), Scavenger Den (Field Caches), Deep Scavenger (Elite Caches).
  - **Pylon:** +5% within r2, but −5% to anything touching it.
- **Schema:** `{name, cat, size, power, coins, growth, max_lvl, core{}, limit[[relay_or_res, n]], unlock{res}, tags, desc}`.
- **`data/AdjDB.gd`:** signed rules `{src, dst, r, eff, text}`. Examples:
  - Reactor → Arsenal +20%
  - Reactor → Mill −15% (heat)
  - Scavenger ↔ Scavenger −15% within r2
  - Mill ↔ Mill +10%
  - Warehouse → Mill +15%

  Buffs are capped at +60% and nerfs floored at −40%. A research scales buff strength.
- **`Outpost.core_bonus(save)`** (built and connected buildings only) feeds `BaseMeta.run_mods`. Scavenger accrual and offline gains are capped by storage.
- **Core Upgrades:** `data/CoreLevelDB.gd`.
  - Cost: `300·1.2^(L−1)` coins.
  - Requirements every 5 levels:
    - L5: Arsenal L1
    - L10: Arsenal L3 + Core Theory I
    - L15: Reactor L3 + Relay L4
    - L20: Optics L2 + Core Theory II
    - …
  - `Cores.can_level` enforces them.
- **`ui/OutpostView.gd`:**
  - Pan (right/middle drag, WASD) and zoom 0.5–2.0, borrowing the patterns from `git show d35f8ec:…/ui/FactoryView.gd`.
  - Palette categories: Production, Core Systems, Scavenging, Support, Links, Decor.
  - While dragging: adjacency connector lines with green/red ± chips and the total.
  - Upgrade panel shows before → after.
- **Jump chips:** `Kit.req_chip` (key `req:<t>:<id>`) calls `Main.jump_to`:
  - A building that exists: select it, centre the camera, pulse it.
  - A building not yet built: open its palette category and flash the entry.
  - A research: open Research, scroll to it, pulse it.
- **Tests:** adjacency literals and cap/floor; `core_bonus` → TowerState stats; requirement gating; scavenger accrual, cap and offline. uitest: requirement chip → `op_sel` / palette flash / `res_focus`.

### P7 — Run roguelite (P7a mechanics, then P7b content)
- **XP drafts:**
  - `_check_level` loops `while xp ≥ need(L)`: level up and queue a draft.
  - Every 5th level also queues a gold perk.
  - `need = xp_base·1.18^(L−1)`, tuned so a neutral build is at level 12–18 by wave 20.
  - Remove the per-wave `_queue_drafts` and the XP reroll bank; keep one opening draft.
  - XP sources (kill XP, the Refinery/Training buildings, XP enhancement and research) make early XP investment pay off.
  - A boss kill gives a **Directive** (1 of 3 rule-changers) plus a cache.
- **Merges:**
  - Drag a building onto another with the same id and tier, or drop a duplicate card on it. The target's tier rises (T1→T2→T3) at ×1.8 base each.
  - T2 offers 3 merge-only mods unique to that building, pick 1. T3 offers 2 capstones.
  - Data: `data/MergeDB.gd`, using the generic fx vocabulary plus ≤ 1 bespoke capstone flag per weapon in FirePatterns.
- **Evolutions** (`data/EvoDB.gd`): a T3 weapon with a specific support building adjacent → a legendary evolution card.
- Also: **draft card lock**, a **Supply Drop** slot-spin event, and a **combo meter** (kill streak → cash and XP multiplier).
- **Core Enhancements** (`data/TrackDB.gd`, `ui/EnhancePanel.gd`, buy ×1 / ×5 / Max):
  - Attack / Defense / Economy, about 10 tracks each.
  - Schema: `{id, tree, base, growth, cap, step{}, minus{}, unlock}`.
  - Standard tracks: base 30–80, growth 1.35–1.5, cap 10–25. That is much cheaper per level than today's 120·3^L, with smaller steps.
  - A few **Overdrive** tracks keep the big trade-offs: base 300, growth 2.5, cap 4.
  - Some tracks unlock through research.

  | Tree | Tracks |
  |---|---|
  | Attack | damage, attack speed, crit chance, crit damage, range, multishot, pierce, splash, chain/bounce, boss damage, execute |
  | Defense | max HP, regen, armor, damage reduction, shield, thorns, lifesteal, knockback, slow aura, last stand |
  | Economy | cash/kill, cash/wave, interest rate, interest cap, XP gain, loot luck, free-upgrade chance, draft luck, scrap find, coin bonus |

- **3× content (no air):**
  - Weapons 6 → **18** in `WeaponDB`:
    - 8 radial: Gatling, Mortar, Tesla, Cryo, Pulse, Missile Battery, Spike Pylon, Minelayer.
    - 10 arc/fixed: Railgun, Flamer, Scatter, Laser Lance, Saw Launcher, Arc Projector, Sonic Cannon, Harpoon, Plasma Fence, Flak Burst.
  - Support/eco 11 → **~33**, e.g. Amplifier, Overclock Relay, Targeting Uplink, Crit Lens, Coolant Tower, Ammo Depot, Lure, Shield Pylon, Bank, Capacitor, Market, XP Siphon, Loot Magnet, Salvager, Luck Totem, Slot Machine (spins each wave), Gate.
  - Gold perks 12 → **36** (6 families). Stat packs 10 → **30**. Huts 3 → 6 (ground only). Specials 6 → 12.
- **Tests:** XP cadence on a scripted kill feed; gold perk every 5 levels; merge rules and rejections; mod-offer determinism; evolution trigger; track cost literals and caps; content validation loops (every id has its fields, fx keys are in the vocabulary, every weapon kills, every pattern is used); Directives apply; `horde_prof` ≤ 8 ms with a full board.

### P8 — Research expansion and QOL
- **`data/LabDB.gd` rewrite** (about 48 entries). Schema: `{name, cat, max, costs | base+growth, hall, req, fx}`.
- **`Labs.gd`:** prerequisites, Research Hall tiers (Hall L1/3/5/8 unlock rows), Lab Discount applied to every cost.
- **`ui/ResearchView.gd`:** category tabs and a focus/pulse API.
- **Steep key costs** (coins; re-anchored to P0's coins/day baseline):

  | Research | Cost per step |
  |---|---|
  | Grid (7 steps) | 2k, 10k, 50k, 200k, 750k, 2.5M, 8M |
  | Game Speed (1.5× / 2× / 2.5× / 3×) | 8k, 60k, 400k, 2.5M |
  | Lab Discount (−3% per level, 10 levels) | 25k·2.4^L |
  | Draft Choices (4 / 5) | 150k, 2M |

- **Categories:**
  - **Core:** Core Theory I–V (gates Core levels), Calibration, Plating, Targeting AI, Optics, Reactor Tuning, Aegis, Manual Mastery.
  - **Enemy:** −HP, −attack, −speed, Boss Breaker, Elite −HP, Sapper Dampening.
  - **Economy:** Coin Bonus, Lab Discount, Interest, Starting Cash, Clear Bounty, Storage, plus **building licences** (+1 Mill / Mine / Scavenger, and unlocks for new building types).
  - **Loot:** Loot Theory (drop rate), Appraisal (rarity luck), Scavenger rate, Cache luck, Pity Insight.
  - **Forge:** Stabilizer I–III (lock slots), Blacklist I–III (bans), Reroll Discount, Enchanter's Eye (3 reroll options), Masterwork Odds, Mythic Fusion, Brand Contracts, Greater Calibration.
  - **Run:** Grid, Speed, Draft Choices, Reroll Bank, Banish, Draft Lock, XP Theory, Enhancement Theory I–III.
  - **QOL:** Auto-Collect, Auto-Buy Enhancements (a rule list, deterministic in TowerState), Auto-Salvage filter, Fast Reveal, Loadout Presets, Auto-Restart, Bulk Upgrade, Blueprint slots.
- **Tests:** table-driven (set each id's level and assert its target stat moves); cost literals for Speed / Grid / Lab Discount; Hall-tier gating; uitest research focus.

### P9 — Playtest bot, balance, visual audit, docs
- **`playtest.gd` policy rewrite:** Outpost build order, best-gear equip, reroll/forge thresholds, research priority, enhancement buying, directional placement, merge when possible.
- **Gates.** The H1–H10 mass gates are kept. Added:
  - solvent; first goal (wave ≥ 10 on day 1); no death spiral; first run 300–480 s
  - T2 by day 3–6; Speed 2× reached on day 4–8
  - Gear matters: best gear reaches ≥ 1.25× the wave of a Common loadout
  - Core buildings matter: ≥ 1.10×
  - XP focus gives ≥ 20% more drafts
  - Radial vs directional within 1.25× of each other
  - No dominant perk or weapon
  - Pity holds over the campaign
- **Tuning:** through `Tune` / `GF_TUNE`.
- **Visual audit:** run the skill over every screen and fix what it finds.
- **Docs:** finish V2_PROGRESS, update the MASS_HORDE notes, add a controls page.

## Critical files
- `TowerState.gd` (run engine) and `HordeWorld.cs` (flow field, squeeze, cone/line queries)
- `Main.gd`, `ui/Desktop.gd`, `ui/Hub.gd`, `ui/Kit.gd`, `ui/Battle.gd`, `ui/DraftPanel.gd`
- `Outpost.gd`, `data/OutpostDB.gd`, `ui/OutpostView.gd` (restored from `5b10ce8`)
- `BaseMeta.gd`, `Cores.gd`, `data/CoreDB.gd`, `Drops.gd`, `Labs.gd`, `data/LabDB.gd`, `Draft.gd`, `data/PickDB.gd`, `data/PerkDB.gd`
- New: `Gear.gd`, `GearGen.gd`, `GearVis.gd`, `FirePatterns.gd`, `Loot.gd`, `data/{Weapon,Frame,Brand,Affix,Module,Name,Rarity,Loot,Adj,CoreLevel,Track,Merge,Evo,Directive}DB.gd`, `ui/{Forge,Core,Research,Enhance}View/Panel.gd`, `ui/LootReveal.gd`, `ui/Theme.gd`
- Tests: `selftest.gd` plus `tests/st_*.gd`, `uitest.gd`, `playtest.gd`, `horde_fp.gd`, `horde_prof.gd`, `_shots.gd`

## Risks
- **C# rebuilds** need the mono toolchain and NuGet over the proxy. `Configure` is kept geometry-agnostic so P3a is green on the old board before P3b switches it.
- **Performance at 10k bodies:**
  - Wider building scans → near-building mask.
  - Cone queries → done in C#.
  - More weapons → existing hit aggregation.
  - Gate: `horde_prof` ≤ 8 ms at P3d and P7.
- **Test brittleness:**
  - P3b and P3d are the big rewrites → relative-cell helper, test ledger, golden re-records with written rationale.
  - Stable button-key naming (`forge:*`, `req:*`, `op:*`).
- **Scope minimums if time runs short:**
  - P4: 6 frames, 12 modules, 40 affixes.
  - P7: mechanics before content.
  - Merge mods are data-only: 3 at T2 + 2 at T3 for weapons, 2 + 1 for support.
- **Balance** is not fixed per phase (only smoke invariants); the full tuning happens in P9.

## Verification
- **Toolchain:** `tools/setup_godot.sh`, then `export DOTNET_ROOT=~/.dotnet PATH=~/.dotnet:$PATH SSL_CERT_FILE=/root/.ccr/ca-bundle.crt`.
- **Every phase** (`tools/test_all.sh` from `games/towerdef-pc-0001`):
  - `$G --headless --path . --import`
  - `--build-solutions --quit`
  - `--script res://tools/parse_all.gd`
  - `--script res://selftest.gd` → `SELFTEST OK`
  - `--script res://uitest.gd` → `UITEST OK`
  - `horde_fp.gd` twice → same hash
  - `playtest.gd -- job=smoke`
- **P3d and P7:** `horde_prof.gd`.
- **P9:** the full `playtest.gd -- workers=4` (≥ 35 min) with every gate green.
- **Screenshots** (every phase; visual-audit skill at P2 and P9):
  - Command: `xvfb-run -a -s "-screen 0 1920x1080x24" $G --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script res://_shots.gd -- <scratchpad>/shots`.
  - `_shots.gd` gains Forge, Core Look, mid-reveal, adjacency drag, enhancement trees and the directional ghost.
- **Each push** appends a V2_PROGRESS entry: test counts, golden-hash changes, deviations, and screenshots of new screens sent to the user.
