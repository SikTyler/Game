# FACTORY_PROGRESS — WP3: the Factorio-style Outpost

Governing docs: PLAYTEST_FEEDBACK_2 (newest wins), the approved plan's WP3. The owner asked for automation only: miners, belts, splitters, assemblers, power and storage, with no colonists for now. The factory runs live while the Outpost screen is open. While the player is away or in a run, production is estimated from measured throughput and capped by storage.

Toolchain: the project is mixed GDScript/C#, so every gate below ran on the **mono** editor (path in HORDE_PROGRESS.md).

## What shipped

### Rules: `Factory.gd` + `data/FactoryDB.gd`
Both are pure and static, with no autoloads, and are typed throughout. Callers inject `now`.

**Map and land**
- 96x64 tiles in 16x16 land chunks (6x4 = 24 chunks).
- Chunks 8 and 9 (x 32..63, y 16..31) are open from the start.
- A chunk can be bought when it is adjacent to open land. The cost is 2500 x 1.55^n.
- Deposits are iron, copper, coal, crystal and salvage, plus rocks. Starter patches are hand-placed and the rest are seeded (DEPOSIT_SEED 7331), so every save has the same map.
- Deposits in a locked chunk are hidden: the view and its tooltips never show them. Buying the chunk returns the deposits it reveals, and they appear in a toast.

**Buildings** (all 1x1 to 3x3)

| Group | Buildings |
|---|---|
| Logistics | Belt 1x1 (2 tiles/s), Fast Belt (4 tiles/s, research), Splitter 1x2, Underground In/Out (range 5, research), Inserter 1x1 |
| Production | Miner 2x2 (0.5/s), Deep Miner (1/s, research), Smelter 2x2, Assembler 3x3 |
| Power | Wind Turbine 2x2 (+3), Coal Generator 2x2 (+12 while burning coal, research), Power Pole 1x1 |
| Storage | Chest 1x1 (48 items), Vault 2x2 (320 items, research) |
| Hubs (3x3, fixed, cannot be removed) | Core Relay, Core Bay, Crate Depot, Research Lab, Card Hall |

**Belts**
- Items sit at a position along the tile, with a 0.5-tile gap between them.
- An item fed from behind enters at 0. An item fed from the side enters at 0.5.
- Head-on belts do not connect.
- Belts feed other belts, splitters, chests and the Relay.
- Miners drop items onto the cell their arrow points at. That can be a belt, a chest, a machine or a generator.

**Splitters**
- Up to 2 items per step, alternating between the two lanes.
- If one lane is blocked, everything goes to the other.

**Undergrounds:** the entrance links to the first matching exit up to 5 cells ahead. The tunnel works as a belt as long as the gap.

**Inserters:** each takes from the cell behind and drops into the cell ahead. It only picks an item the target will accept. One swing takes 0.8 s at full power.

**Recipe chain**
1. Ore becomes plates in a Smelter. The Smelter picks its recipe from its first ore: iron ore → iron plate, copper ore → copper plate, 2 salvage → alloy, crystal → shard.
2. Assembler recipes:
   - Gear: 2 iron plates.
   - Wire: copper plate → 2 wire.
   - Circuit: iron plate + 3 wire.
   - Data Card: circuit + shard.
   - Part Kit: 2 gears + circuit + 2 alloy.
   - Key Blank: 2 circuits + 2 shards + alloy.
3. The Core Relay converts goods into currencies:
   - Coins: ore and plates sell for coins.
   - Scrap: salvage, alloy and part kits.
   - Keys: 4 Key Blanks make 1 key.
   - Research data: 1 per Data Card.

**Power**
- Poles, generators and the Relay are network nodes. Nodes link within 6.5 cells, centre to centre.
- Each node powers cells within 2 of its footprint.
- Each network has a satisfaction of min(1, supply / demand). Machine and inserter speed are multiplied by it.
- A machine with no network covering it does not run.

**Storage**
- Chests and Vaults hold capped amounts. A full chest backs up its belt.
- Every storage slot extends away production: 4 h + 0.02 h per slot, at most 36 h. Storage Tech research adds a further +4% per level.

**Fixed-step tick**
- `step()` advances the factory by DT = 0.2 s, processing entities in ascending uid order. It is deterministic, and a selftest checks this.
- `live()` runs whole steps of real time while the screen is open, at most 25 steps per frame.
- A compile cache is keyed by a content hash of the layout (`rev`). This keeps JSON/normalize round-trips stable, and a simulated copy reuses its original's structure.

**Away and in-run production**
- A 60 s meter measures what the Relay actually earned (raw value).
- After any layout edit, `ensure_rate()` re-measures on a simulated copy: 60 s warm-up, then a 120 s window.
- `settle(now)` banks rate x elapsed time, capped at rate x away cap.
- Multipliers apply at payout and in the estimate, so buying one never makes the measured rate stale. They are: Logistics Tech +5%/L, Reforge outpost_p +8%/L, and the highest tier reached x(1 + 0.8(T-1)), as the Coin Mill used.
- When the player boots after more than 5 min away, the bank shows in the "While you were away" modal. Production during a run is settled and paid when the player returns to the base (a toast says so).

**Facilities**
- Research Lab, Barracks, Archive and Salvage Yard levels now live on `factory.fac` and are upgraded at the Core Relay panel.
- `Outpost.level_of` takes the larger of the legacy level and the factory level, so research queues, troop bonuses, Insight and banish keep working.
- `Parts.salvage_mult` counts a factory Salvage Yard.

**Factory technology:** 9 techs bought in the Research Lab with coins and research data: electronics, underground, coal_power, data, logistics2, storage2, parts, keys, mining2.

**Save migration:** `Factory.migrate_outpost`, run at boot, once (`factory.migrated`).
- Refunded: every Outpost generator, conduit, warehouse and beacon (what was spent plus whatever it had stored), all decor, and leftover build credit.
- Facility levels move to the factory.
- The player gets a free starter line: an iron miner belted into the Relay, plus a Wind Turbine.
- A toast reports the refund.

### View: `ui/FactoryView.gd` (replaces `ui/OutpostView.gd`, deleted)

**Camera**
- The mouse wheel zooms about the cursor, from 9 to 72 px per cell.
- Pan by dragging with the right or middle button, by left-dragging on empty ground, or with WASD or the arrow keys.

**Building**
- Categorised palette with icons: Logistics / Production / Power / Storage, with hotkeys 1-9.
- Ghost placement shows green or red with the reason, a direction arrow, the miner's output cell, and the inserter's source and target.
- When a power piece is armed, power coverage is shown.
- R rotates in 4 directions, both the armed piece and the piece under the cursor.
- Dragging lays a straight or L-shaped belt line, each piece facing the next one.
- Q copies the piece under the cursor (pipette).
- X, Del or a right click deconstructs, with a full refund.

**Information**
- Tooltips show status, the recipe, throughput per minute, power draw and satisfaction, contents, and the measured Relay output per item.
- Items visibly ride the belts. Chevrons animate at belt speed. Machines show their output icon and a progress bar, and status dots show working, low power, blocked and so on.
- Power wires are drawn between linked nodes.

**Panels**
- The header shows coins, scrap and keys per minute or hour, research data, power demand/supply, the bank, and a Collect button.
- The selection panel shows recipe buttons for machines, and facility upgrades on the Relay. A selected locked chunk shows a Buy land button.
- Hub buildings open their screens: Core Bay, Crates, Research and Cards.
- The Research tab gained a Factory Technology row.

### Art: `art/_gen_svg_factory.py` → 41 SVGs
- Buildings: `fy_*`, drawn facing east and rotated by the view.
- Items: `it_*`, 15 of them.
- Deposit tiles: `dep_*`, 5 of them.
- `fy_rock`.

The style matches the existing flat-industrial pass: INK outlines, lit faces and drop shadows.

## Tests (deliberate changes, called out)

### selftest: new `_factory_stages()` (29 checks)
Map and chunks; hidden deposits revealed on unlock; placement rules; belts move items (exact 0.4-tile step); drag-laid L lines; side-load and head-on; **splitters alternate (10/10)** and overflow to the free lane; undergrounds; **smelter auto-recipe**, **assembler 2:1 gear recipe**, a smelter recipe refused at an assembler, circuits gated by research; research spends coins and data; **power shortage slows machines** (satisfaction 0.4 gives fewer gears); an unpowered miner stays idle; the coal generator supplies power only while burning; **storage caps** (chest stops at 48, belt backs up) and the away cap formula; Relay conversion; **offline estimate ≈ simulated steady state (within 5%)**; away output = rate x time, capped by storage; collecting the bank; determinism; JSON + normalize round-trip; deconstruct refund; hub cannot be removed; splitter rotation; migration (refund of spent + stored, facility levels kept, starter added, idempotent); a Barracks facility reaches `run_mods`.

No existing selftest assertion was changed. The legacy `Outpost.gd` rules module stays, because its 94 selftest checks still describe valid pure rules. It now serves as the migration source and holds the facility-level hand-off.

### uitest: Outpost sections rewritten for the factory
These are deliberate literal changes:
- Palette keys `OPCAT/OPBUILD` → `FCAT/FBUILD`.
- The map-size literal 24x16 / 17 plots → ≥96x64 / 24 chunks.
- "Crates" landmark → "Crate Depot".
- The Mill/Relay "upgrade before → after" checks became the facility upgrade at the Relay plus the Relay's measured-output tooltip.
- Plots → land chunks.
- `op_cam/op_zoom` → `fc_center/fc_zoom`.
- Mill collect / Collect all → the bank Collect.
- Move (M) and blueprints → rotate-in-place, pipette and belt drag. Blueprints are not part of WP3.

The boot "away modal" check now expects the factory's measured rate x 2 h. The modal and Collect assertions are unchanged.

New checks: miner ghost on/off a deposit, armed piece stays armed, drag from the palette, R on the armed and placed piece, straight and L belt drags, Q pipette, X and right-click deconstruct, assembler recipes (circuit locked), facility upgrade, bank Collect, buying land reveals deposits, right-drag / left-drag / WASD pan, wheel zoom in and out, live ticking on the screen, and Factory Technology in the Research Lab.

### playtest bot
- `OP_PLAN/outpost_spend` became `FACTORY_PLAN/factory_spend`: 12 modules in the start chunks (iron miners, iron and copper smelting, salvage, coal power, chests and a vault for the away cap) plus tech and facility steps.
- Away pay is `factory_collect` (settle + claim).
- `outpost_h` is the factory's measured rate x 3600.
- The AC-27 "storage fill" hours are the factory's away cap.
- The gate thresholds are unchanged.

## Gates (mono editor)
--import clean · --quit-after 120 clean · SELFTEST OK · UITEST OK · PLAYTEST: see below (run once).

Shots are in `scratchpad/fb2shots`: 05_factory_new, 05b_factory_dev, 05c/05c2 ghosts, 05d_factory_land, 05e_factory_belt_drag, 05f toast, 05g_factory_zoom_items, 05h_factory_zoom_out, 05i_factory_relay, 05j_factory_research_hub, 05k_factory_tooltip, 01_offline (factory away modal), 06_research (Factory Technology row).

## Open items / blockers
- **Balance (WP5):** a fully built start area (the bot plan) makes about 8.4k coins/h at T1. The tune knobs are `factory_coin` and `factory_scrap/keys/data` in `GF_TUNE`, and `FactoryDB.VALUE`. The outpost-share gate (`rd_outpost_share`, 0.15-0.35 of active coins/h) and AC-27 (6-16 h) need re-aiming against the factory in the balance pass.
- **Top menu buttons and "Core Enhancements" (WP4):** the top menu buttons for Core, Crates, Research and Cards, the "Core Enhancements" rename, and the enemy info and loot feed panels belong to WP4 and were not touched here.
- **Bot scope:** the bot does not buy land or build circuit / data / key chains. The shots exercise those by hand.
- **Not built:** blueprints and copy-paste of areas, filtered inserters, belt lanes (one lane per belt), fluid systems, and fuel for anything except the Coal Generator.
