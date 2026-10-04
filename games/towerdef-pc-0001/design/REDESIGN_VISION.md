# Corehold PC — Redesign Vision (Game Director)

Source brief: Tyler's redesign request plus the approved plan (`/root/.claude/plans/game-idea-incremental-roguelite-flickering-ember.md`). This document says **why** and **how it should feel**. Exact numbers live in PC_SPEC.md, ECONOMY.md and PC_BALANCE.md. If this doc and the spec disagree on a number, the spec wins. If they disagree on intent, raise it with the Director.

## 1. One-line fantasy
> *You are the mind inside a Core.* The Core is your weapon and your engine. Each run, you grow a fresh fortress around it out of luck and judgement. Between runs, you open the Core up, wire in the parts you have earned, and tend an Outpost that is unmistakably yours.

Genre: **incremental × roguelite × base builder.** Every system has to serve at least two of those three words.

## 2. Pillars (ranked; use them to break ties)
1. **The Core is the hero.** It is your main weapon and your main economy. Every system either makes the Core feel stronger or lets you express what kind of Core you are running. Nothing on the grid should outshine the Core for long.
2. **Every run is a new fortress.** The in-run grid starts empty. Picks are surprising, synergistic and occasionally game-breaking. No two runs should build the same base.
3. **Every choice is a trade-off.** Parts, picks and Outpost tiles all cost something. The player is always asking: *eco or defence? Breadth or depth? This weapon or that one?*
4. **Growth you can see.** Numbers rise, the Outpost visibly sprawls, the Core visibly changes. Progress is never just a hidden multiplier.
5. **Fair curve.** Power and currency grow at the same rate as wave difficulty, so the power ratio stays in its band (0.8–1.25 at the frontier). Walls should feel like puzzles, not paywalls, and power should never run away until the game becomes boring.
6. **Respect the player's time.** Check-ins are short and satisfying. Runs are long and active. Idle income complements play and never replaces it: it is capped by storage.

## 3. Session loops
| Loop | Length | What happens | Emotional beat |
|---|---|---|---|
| **Run** | 15–40 min active | Pick a Core and loadout, defend waves, draft picks on level-up and perk waves, buy cash upgrades for the Core, fire specials, collect drops | Mastery, surprise, "one more wave" |
| **Bay** (post-run) | 1–3 min | Bank Insight, open crates and drops, install or upgrade parts, push the Core's level | Loot dopamine, build-crafting |
| **Outpost check-in** | 2–5 min, a few times a day | Collect capped storage, start real-time builds, rearrange for adjacency, place decor, upgrade the Gem Mine | Tending, ownership, calm |
| **Reforge** | every ~1–3 days early, ~week later | Cash out lifetime coins for √-scaled shards; spend them on the tree, new Cores and blueprints; rebuild faster | Renewal, "I'm so much stronger now" |
| **Week** | — | Complete sets, unlock special parts, a new Core, a layout you are proud of | Long-term identity |

**Rule:** each loop must feed the others. Runs drop parts and coins that pay for the Outpost. The Outpost feeds runs through troop tiers, labs, Insight cap and a starting kit. Reforge multiplies both.

## 4. What makes runs exciting
- **Draft variety.** There are five pick families: buildings, upgrade packs, specials, troop huts and Insight. Each draft offers a mix, never three of the same family. Rarity weights, rerolls and banish give the player agency against bad luck. Synergy tags (e.g. *Arc*, *Forge*, *Swarm*) make picks call out to each other.
- **Troops on the field.** Troop huts send units out past the walls, where they skirmish with shapes. The battlefield stops being a static shooting gallery. Hive Core runs should feel like commanding a swarm.
- **Specials (hotkeys 1–4).** These are big, readable, cooldown moments: Orbital Strike, EMP, Repair Pulse, Overcharge. They give the player active decisions during long waves and clutch saves against bosses.
- **Insight jackpots.** A super-rare gold pick gives a permanent +0.5–1%. It gets its own fanfare, screen flash and sound. Insight is capped per run, and the Archive raises the cap. These are the "I'll remember this run" moments.
- **Drops.** Elites and bosses can drop parts. The rare **Courier** enemy flees across the map and is worth chasing with your specials. Drops show on the field immediately, and you open them in the Bay.
- **Eco vs defence tension.** Eco picks and the Core's interest compound, but greed gets punished on boss waves. This tension survives from the original design and stays the heartbeat.
- **Core cash upgrades.** Inside a run, cash buys damage, rate, range, eco and armour tracks for the Core, so the Core grows visibly in every run.

## 5. Core identity and feel
Each Core is different in its silhouette, its sound, its attack read, and the way it wants you to draft.
| Core | Unlock | Fantasy | Attack feel | Drafts toward | Weakness |
|---|---|---|---|---|---|
| **Bastion** | start | dependable fortress | steady auto-cannon thump, crisp tracers | anything; teaches the game | no extremes |
| **Foundry** | tier 2 | greedy industrialist | weak sparks; coins pour out with chunky clinks; interest ticks | eco buildings, packs that convert cash into power | fragile early; must survive greed |
| **Lance** | first Reforge | sniper | charge hum, then a piercing beam crack | single-target, crit, boss-killers | swarms |
| **Tempest** | set unlock | storm | expanding pulse rings, electric crackle | area, slow, chain | low boss damage |
| **Hive** | set unlock | broodmother | drones pour out with a buzzing swell | troop huts, Barracks tiers | weak Core defence when drones are dead |

Each Core has its own part slots (2 → 6 with level), so the Bay loadout *is* the spec: balanced, eco, single-weapon or raw damage. Loadout presets are stored per Core.

## 6. Parts: the build-craft layer
- **Every part has a plus and a minus**, e.g. *Focusing Lens: +30% Lance damage / −15% range*. There are no strict upgrades. Rarity widens both sides and adds a quirk.
- **Sets** grant a 2-piece and a 4-piece bonus. A full set unlocks a special part that bends the rules (e.g. troops inherit Core crits). Sets pull players toward an identity without forcing one.
- **Sources:** coin, gem and key crates, boss and elite drops, and Couriers. Duplicates salvage into Scrap, which upgrades parts. Crate opening is a short, skippable, satisfying reveal.
- **Reforge keeps owned parts** and resets their levels, so the collection is permanent while power re-climbs.

## 7. The Outpost: strategic, personal, fun
The Outpost is a separate persistent map (about 14×10, with an expandable border) built only outside runs.
**Strategic** (spatial puzzles)
- **Connectivity:** generators must link to the Core Relay through power and road tiles. Routing is the main puzzle, and space is scarce.
- **Adjacency:** Coin Mills next to Warehouses fill faster. A Refinery next to a Gem Mine doubles shard dust. Research Halls dislike noisy Forges. A hover preview shows every adjacency delta before you place.
- **Storage caps** create the check-in rhythm, and the Warehouse lets you choose between "check in more often" and "build bigger buffers".
- **Border expansion** buys new terrain with features (ore veins boost Mines, rivers boost Mills), so where you expand is a real choice.
**Personal**
- **Decorations** are free-placed, cosmetic, sometimes earned (set trophies, boss banners). Some give a tiny morale aura, so they are never mandatory.
- **Blueprints** save a layout, rebuild it after a Reforge in one click (once you have unlocked it), and can be shared as a string.
- The Outpost should **look like your history**: boss banners, Core statues and set trophies mark your milestones.
**Fun**
- **Visible growth:** buildings change art per level, workers and carts move along roads, and coins visibly pile up in storage.
- **Small run-impacting choices:** Barracks pick troop tiers, Research Hall holds the labs, Archive raises the Insight cap, the Key Forge makes crate keys, and a "starting kit" pad picks one free building for the next run. The Outpost matters to runs without dictating them.
- **Gem Mine:** slow premium income that rewards care. It is never pay-to-win; gems speed things up and buy cosmetics or crates.
- Idle and offline income **is** Outpost production, so the old flat offline formula is retired.

## 8. Core Reforge (prestige)
- Available at tier ≥ 3 or at a lifetime-coin threshold. A preview shows the shard gain (≈ k·√lifetime coins) and "time to previous best" estimates.
- **Resets:** coins, the Outpost and part levels. **Keeps:** owned parts, Cores, cards, shards and Insight.
- The **tree** buys permanent % stats, game speed, starting cash, an extra draft choice, new Cores and Outpost blueprints.
- Success criterion: each loop reaches the previous best at least 30% faster, and the first Reforge should feel like a power fantasy, not a punishment.

## 9. Onboarding and unlock timeline
Introduce **one system at a time**, each unlocked by an achievement the player can see coming ("Clear wave 20 to open the Bay").
**First ~3 hours**
| Time | Unlock | Teaches |
|---|---|---|
| 0–10 min | Bastion run, cash upgrades, first draft (buildings only) | Core-as-hero, eco vs defence |
| ~10 min | Upgrade packs + specials (1 slot) in drafts | Active play |
| ~20 min | **Bay**: first part drop from a boss; 2 slots | Trade-off parts |
| ~30 min | **Outpost**: Core Relay + Coin Mill + road; storage cap | Connectivity, check-ins |
| ~45 min | Troop huts in drafts; Barracks in the Outpost | Field troops |
| ~60 min | Coin crates; Scrap and salvage | Loot loop |
| ~90 min | Tier 2 → **Foundry Core**; Core level 2 (3 slots) | Archetypes, specs |
| ~2 h | Adjacency bonuses revealed; Warehouse; Research Hall (labs move in) | Spatial optimisation |
| ~2.5 h | First Insight pick guaranteed in a run (tutorialised jackpot); Archive | Permanent % |
| ~3 h | First set 2-piece bonus; decorations | Identity, personalisation |
**First week**
| Day | Unlock |
|---|---|
| 1 | Gem Mine, Key Forge, key crates; border expansion #1 |
| 1–2 | **First Core Reforge** → shard tree; Lance Core in the tree |
| 2–3 | Blueprints; 4-piece set bonuses; Courier enemy |
| 3–4 | Tier 3–4, special slots 3–4, Core level 4 (5 slots) |
| 4–5 | Tempest Core (set unlock); first full set → special part |
| 6–7 | Hive Core; 6 slots; endless pressure tuned by the power-curve band; Outpost fully expanded zone 1 |
**Guardrails:** never more than one new screen per session. Every unlock gets a single tooltip tour that the player can skip. No system is ever locked behind gems.

## 10. Desktop presentation (native 1920×1080)
- Battlefield in the centre.
- Left panel: draft, build and info.
- Right panel: Core stats and cash upgrades.
- Top bar: currencies, wave and tier.
- Bottom: special hotbar.
- The embedded mobile column goes away, and with it the duplicated HUD.
- Tooltips everywhere, hotkeys, controller support.
- Separate screens: Outpost builder, Core Bay, crate opening, Reforge tree.

## 11. Director's acceptance checks
- A new player can say "the Core is my weapon and my bank" after 10 minutes.
- Two runs with the same Core produce visibly different grids.
- Every part tooltip shows both a plus and a minus.
- An Outpost screenshot from two different players looks different.
- The playtest power ratio stays in the 0.8–1.25 band at the frontier for every loop, and each Reforge loop reaches the previous best at least 30% faster.
- One screen, no duplicated HUD at 1920×1080.
