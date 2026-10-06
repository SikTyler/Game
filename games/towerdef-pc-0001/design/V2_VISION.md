# Corehold V2 — "Forge & Outpost" vision

Owner brief (2026-10-05, condensed): the game is good but lacks something unique; runs need to feel exciting and different, with "casino"-style addictive loot and UI, more upgrades and features. The game feels split up. The focus is **Outpost, Buildings, Core, Research and Weapon**, built on a deep procedural list of parts, weapons, colours, skins and models that keeps everything fresh. Research and buildings support weapon building and turn it from pure RNG into player control (luck, locking items and stats).

Owner decisions:
- The forged Weapon mounts in the Core's centre slot. It auto-fires, with optional manual aim for a focus bonus.
- Art direction is neon casino sci-fi.
- Saves are hard reset.
- All phases are delivered in order.

## Pillars (ranked)
1. **The Core + Weapon is the hero.** There is one Core. Its centre Weapon and the ring of Modules around it are the build. You can see it change, recolour it, and name it.
2. **Loot you chase, luck you tame.** Everything drops procedurally (frame × brand × rarity × perks × visual seed). Research and buildings hand the player levers over time: luck, perk locks, bans, merges, imprints and visible pity.
3. **The Outpost is where you grow.** Its buildings level up and buff or nerf their neighbours. Some give the Core permanent stats, Scavengers dig up loot, and Core Upgrades require the right buildings, so base building drives everything.
4. **Every run is a new fortress.** XP level-ups draft from a 3× larger pool (weapons, support, perks). Merging identical buildings unlocks merge-only mods. Directional weapons make placement and facing a real decision.
5. **Juice proportional to the moment.** Casino reveals, loot beams, number roll-ups and rising pitch, all sized to the event and all skippable. No paid currency, ever.

## Currencies
**Coins** (everything), **Scrap** (forge verbs) and **Reforge Shards** (prestige). Keys, Core Cores, crate tokens, gems and factory data are gone.

## Competitor analysis — what hooks players, what we take

| Reference | What hooks | Corehold V2 takes |
|---|---|---|
| **The Tower** (Tech Tree Games), the closest analog | ~30 shared stats across in-run Attack/Defense/Utility trees and the permanent Workshop. Game Speed lab first. Modules have rarity, substats and reroll shards, and **locking a substat makes rerolls exponentially pricier** (0→10, 1→40, 2→160, 3→500…). Bans remove useless outcomes. Shattering returns duplicates. | Core Enhancement trees (Attack/Defense/Economy, ~10 tracks each). Lock cost ×4 per lock. Blacklist (ban) research. Salvage → Scrap. A steep Game Speed research. |
| **Brotato** | Merge 2 identical same-tier weapons → next tier. Shop lock. Escalating reroll. Luck shifts odds. Offers are weighted toward what you own (20% same type, 15% same class). | Merge-only building upgrades. Draft card lock. Synergy-weighted drafts. A visible Luck stat. |
| **Vampire Survivors** | Evolutions (max weapon + passive). Reroll/Skip/Banish charges. Arcana rule-changers at boss milestones. Slot-machine chest. | Evolutions (tier-3 weapon + a specific adjacent support). Boss Directives. Supply Drop slot spin. |
| **Diablo 4** | Enchant rerolls one affix (2 options + keep). Masterwork ranks 4/8/12 give +25% to a random affix, a jackpot inside steady progress. Greater affixes are drop-only. | Reroll one perk with a pick-of-2-or-keep choice. Masterwork jackpot every 5 levels. T6–T7 perks come only from drops. |
| **Last Epoch / Path of Exile** | Forging potential as a craft budget. Top tiers drop-only. Currency items as crafting verbs. Essences guarantee a chosen modifier. | A small verb set: Upgrade, Reroll, Lock, Merge, Imprint, Salvage, Forge. Imprint guarantees a chosen perk. |
| **Borderlands** | Parts × manufacturer × rarity gives billions of guns. Brand quirks and palettes. Generated names. | Frame × Brand × Rarity × Perks × seed. Brands carry a quirk and a palette. Names are generated from brand, frame and perks. |
| **Dome Keeper** | The defended object's weapon defines its tree. Gadget modules ride along. | Core centre Weapon plus a ring of Modules (double-shot, splash, pierce, ricochet, chain…). |
| **Mindustry** (open source, GPL) | A damage-shape taxonomy: line, cone, chain, artillery, beam. The Overdrive projector buffs a radius but raises upkeep. | Radial vs Arc vs Fixed (cone/lane) weapon classes. Support buildings whose buffs carry a cost. |
| **BTD6 / Defense Grid 2** | Paragon merges consume the investment. A boost pedestal. | Merge tiers scale the base sheet; capstone mods at tier 3. |
| **Islanders / Backpack Battles / Luck be a Landlord** | A live score preview while hovering. Connector lines while dragging. "The slot machine is your build." | Hover shows ± adjacency chips and connector lines on both grids. Merge and evolution lines while dragging. |
| **Balatro / ethical gacha** | Staged scoring with rising pitch, number reels and shake scaled to size. A visible pity bar. Disclosed odds. | The cache reveal: beam colour climbs, shake by rarity, perks tick in one by one. Pity bars. Odds tooltips. Never paid. |
| **Idle Slayer / Halls of Torment** | Rage and combo reward active play. Extraction risk. | A combo meter in runs. Manual aim focus. Scavengers as "loot you would have earned". |
| **Against the Storm / 20MTD / Antimatter Dimensions** | Run blueprints. Conditional trees. Automation unlocked as a reward. | QOL research: Auto-Buy enhancements, Auto-Collect, Auto-Salvage. Enhancement tracks unlocked by research. |

Open-source references studied:
- **Mindustry**: turret and bullet taxonomy.
- **Godot-4-VectorFieldNavigation** (MIT): its flow-field model matches our C# HordeWorld.
- **zfedoran/pixel-sprite-generator**: mask-based procedural silhouettes, the idea behind GearVis part masks.
- **Lootie** (MIT): weighted loot tables; we add luck and pity.
- **quiver-dev tower-defense-tutorial** and **SurvivorsStarterKit** (MIT): structure only.

## UI and visual principles (neon casino sci-fi)
- **Palette.** Near-black navy backdrop with low-saturation panels. Rarity colours appear only for rarity. Each stat family has one fixed hue and icon.
- **Unlocks.** Reveal systems gradually: a tab shows a pulsing badge when it unlocks.
- **Previews.** Preview before committing: adjacency deltas, stat compare arrows, the cost of the next lock.
- **In-world information.** Buff links are lines on the grid. Arcs and lanes are drawn while placing and fade afterwards.
- **One clear priority per screen.** Fewer, bigger panels, with tabs instead of walls of buttons.
- **Numbers.** Roll-ups with fixed-width digits and K/M/B suffixes.
- **Juice scaled to the event, plus reduced motion.** Routine events get no shake.
