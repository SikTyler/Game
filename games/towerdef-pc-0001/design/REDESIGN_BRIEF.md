# Corehold PC — Redesign Brief (PM / creative guardian)

Source docs: REDESIGN_VISION.md (fantasy, pillars, loops), REDESIGN_SYSTEMS.md (content tables),
POWER_MODEL.md (curves). Where they disagree, **REDESIGN_SPEC.md is final** (its §0 lists every
reconciliation). This brief is the bar every work package is judged against.

## 1. Fantasy
You are the mind inside a Core: it is your weapon **and** your bank. Inside a run you grow it with
cash and build a new fortress from roguelite picks. Outside, you open it up and install Parts, and
you build your Outpost, a persistent map that keeps earning while you are away. Every system must
serve at least two of **incremental, roguelite, base builder**.

## 2. Pillars (ranked, highest wins ties)
1. **The Core is the hero.** It is the main gun and the main income. Choosing a Core changes how a run plays, not just its numbers.
2. **Every run is a new fortress.** The grid starts empty. Picks (buildings, packs, specials, troop huts, Insight) make each run different.
3. **Every choice is a trade-off.** Eco vs defence in-run, a plus and a minus on every Part, and spec commitment out of run.
4. **Growth you can see.** Numbers go up, the Core grows parts, the Outpost visibly fills in, buildings change art per level.
5. **A fair curve.** Power and currency grow at the same rate as wave difficulty (power ratio band 0.8–1.25 at the frontier).
6. **Respect the player's time.** Storage caps set a humane check-in rhythm. No dark patterns. Gems are earn-only.

## 3. Guardrails (non-negotiable; a WP that breaks one is rejected)
- **G1 Eco-vs-defence stays live.** Every in-run draft offers eco and defence options often enough that the choice recurs (spec: ≥1 eco and ≥1 non-eco card in ≥80% of drafts). Neither pure-eco nor zero-eco may be the dominant line (P-gate).
- **G2 Every part has a trade-off.** Every Part, including set-unlocked specials, has ≥1 real drawback worth ≥25% of its benefit by the PowerModel valuation. Drawbacks never scale with level. Tooltips show both.
- **G3 Power ratio in band.** At the frontier wave R ∈ [0.8, 1.25] for every progress stage and Reforge loop; early run R ≥ 2.0; frontier+5 R < 0.6 (a wall always exists).
- **G4 The Outpost is personal + strategic.** Layout matters (connectivity, adjacency, storage radius) but a good layout is worth ≤ +60% over a random one: rewarding, never mandatory. Decor, names and themes make two players' Outposts look different. Reforge never wipes the layout or decor.
- **G5 No pay-to-win; gems are earn-only.** There are no real-money purchases in this edition. Gems come only from play (Gem Mine, bosses, missions, tiers, streak). Gems buy convenience, cosmetics and crates whose odds are disclosed with pity counters. No power is purchasable only with gems.
- **G6 No duplicated HUD.** Native 1920×1080 layout. The embedded 720×1280 mobile column is deleted. Each piece of information (cash, HP, wave, currencies) appears exactly once on screen.
- **G7 Engine purity.** Rules live in pure, seeded, injectable-`now` modules. The view owns no rules and replays events. Godot 4.6 strict typing, no autoloads. Save migration is lossless and idempotent.
- **G8 Tests are never weakened.** Tests change only where this redesign deliberately changes behaviour, and every such change is listed in the commit message.
- **G9 Quality over breadth.** Anything in the spec's §9 "Cut / deferred" list stays out until all acceptance criteria pass.

## 4. Acceptance criteria
Tags: **S** = selftest.gd (pure engine/meta), **U** = uitest.gd (UI wiring), **P** = playtest.gd
(bot/balance sim), **X** = screenshot / manual review via `_shots.gd` (Director looks at PNGs).
Every S/U/P criterion must be an assertion in the named script. X criteria are checked on the
1920×1080 shot set.

### Core and run
- **AC-01 [S]** CoreDB defines bastion, foundry, lance, tempest with distinct attack ids; a seeded run with each Core produces a different `attack` event kind.
- **AC-02 [S]** A new run's grid contains only the Core at the centre cell; ring 1 is open, rings 2/3/4 open at cash-track total levels 10/30/60.
- **AC-03 [S]** The five cash tracks (dmg, rate, range, eco, armor) price as `base*growth^lvl`, reset each run, start at `head_start` level, and refuse purchase beyond the cap or without cash.
- **AC-04 [S]** Kill cash scales ×1.10 per wave (±1%), and Core cash/s scales with the eco track and Core level per spec §2.
- **AC-05 [S]** Draft offers are deterministic for a seed; they contain ≥1 eco and ≥1 non-eco option in ≥80% of 1,000 seeded drafts; the free reroll then rising costs (10, 20, 40… cash) and banish work; a duplicate building pick levels it (max L5).
- **AC-06 [S]** Every pick family resolves: building placed on a free open cell, pack applied once, special bound to the first free hotkey 1–4 (5th replaces a chosen slot), troop hut spawns troops, Insight banked at run end.
- **AC-07 [S]** Troops run seek/engage/retreat deterministically for a seed; leash 6 cells from the lane exit is never exceeded; dead troops respawn after the hut delay; max 3 huts.
- **AC-08 [S]** Special attacks respect cooldowns and emit `special_cast` events; casting during cooldown is refused.
- **AC-09 [S]** Insight respects the per-run cap (1, Archive L3→2, L6→3) and lifetime caps, and survives Reforge.
- **AC-10 [S]** Drops are seeded and replayable; per-run part cap is 3 plus Courier drops; a killed Courier always yields 1 part + 1 Key; an escaped Courier yields nothing.

### Meta
- **AC-11 [S]** Every PartDB entry has a slot, rarity, ≥1 benefit and ≥1 drawback; drawback magnitude is identical at L1 and max level.
- **AC-12 [S]** PartDB passes the PowerModel budget test (value within ±10% of budget), the trade-off test (|negative| ≥ 25% of positive), and the Pareto test (no part dominates another of the same slot and rarity).
- **AC-13 [S]** Set bonuses activate at 2 and 4 distinct equipped members; completing a full set once permanently unlocks its special part, which persists through save/load and Reforge.
- **AC-14 [S]** Part slots by Core level are 2/3/4/5/6 at L1/5/12/20/30 (+Set slot at L40); equipping into the wrong slot type or a locked slot is refused; 4 presets per Core round-trip.
- **AC-15 [S]** Crates: seeded opens match the disclosed odds within tolerance over 10,000 opens; pity counters guarantee the stated rarity and are saved; duplicates become stars (max 2) and then auto-salvage.
- **AC-16 [S]** Part level-up costs Scrap per formula; salvage returns base + 50% invested; locked parts cannot be salvaged.
- **AC-17 [S]** Outpost: a generator produces only when 4-neighbour connected to the Relay; over-budget power scales efficiency; placement on blocked, locked-plot or occupied cells is refused; Gem Mine only on Crystal Vein tiles.
- **AC-18 [S]** Outpost accrual with injected `now` equals rate × elapsed clamped at storage cap; collect empties storage; build/upgrade timers complete at `ends_at`; one job per builder.
- **AC-19 [S]** Adjacency and Warehouse/Beacon bonuses compute per spec, and the total layout bonus on any building is capped at +60%.
- **AC-20 [S]** Research Hall runs all migrated LabDB projects; queue count follows Hall level (1/2/3 at L1/L4/L8).
- **AC-21 [S]** Reforge: refused below the gate; shards = floor(k·√(coins_since/10,000)) (+5 on the first); resets exactly the spec's reset list and keeps exactly its keep list (layout and decor kept, building levels reset); shard tree nodes respect cost and max.
- **AC-22 [S]** Save v3 → v4 migration is idempotent; the v3 fixture yields the refund coins, a placed and connected Coin Mill + Research Hall, Bastion level per formula, and research levels equal to old labs; no double offline pay. (Deliberate change to the old v3 fixture assertions.)
- **AC-23 [S]** New Steam achievements are defined in AchievementDB with unlock hooks: first part, first full set, first Reforge, Gem Mine built, Courier caught, 4 Cores owned.

### Balance
- **AC-24 [P]** PM-1: PowerModel `required_dps` matches the engine's measured spawn HP/s within 5% at waves 1/10/20/40.
- **AC-25 [P]** Fresh save, balanced bot: dies in waves 12–25 with R(w*) ∈ [0.8, 1.25]; R ≥ 2.0 for w ≤ w*/2; R(w*+5) < 0.6.
- **AC-26 [P]** Simulated progression snapshots (day 1, day 3, week 1, week 3, Reforge loops 1–3) keep frontier R in [0.8, 1.25] and never plateau for more than 5 simulated days.
- **AC-27 [P]** The Outpost/active coin ratio ∈ [0.15, 0.35] at every stage snapshot; storage fills in 6–16 h.
- **AC-28 [P]** Each Reforge loop reaches the previous best wave in ≤ 70% of the prior loop's time.
- **AC-29 [P]** Each spec (balanced, eco, single-weapon, damage) reaches within 3 waves of the best spec with V ≥ 0.85·V_best; eco gives ≥ +20% coins per run, single-weapon ≥ +25% boss DPS.
- **AC-30 [P]** Eco-vs-defence: the bot's all-eco and zero-eco pick policies both reach a lower frontier than the mixed policy (G1).

### UI
- **AC-31 [U]** The root viewport is 1920×1080 with no node of the old 720×1280 mobile column in the tree; HUD labels for cash, Core HP, wave and each currency each exist exactly once.
- **AC-32 [U]** Battlefield layout: left panel (draft/build/info), centre field, right panel (Core stats + cash tracks), top bar (currencies, wave, tier), bottom hotbar (specials 1–4). Pressing keys 1–4 casts the bound special.
- **AC-33 [U]** The draft panel shows 3 (or 4 with `wide_draft`) cards with rarity, family and tag; reroll and banish buttons are wired; selecting a card emits exactly one pick.
- **AC-34 [U]** The Core Bay lists owned Cores, slots and presets; equip/unequip by click works; every part tooltip has both a "+" line and a "−" line.
- **AC-35 [U]** Crate screen: shows odds and pity before opening; opening reveals the parts and updates inventory.
- **AC-36 [U]** Outpost builder: placing, moving, rotating (R) and demolishing work; the hover preview shows the adjacency/connectivity delta before placement; unconnected buildings show the plug icon; Collect all appears at Relay 3.
- **AC-37 [U]** Reforge screen: previews shards gained and the reset/keep lists before confirmation; confirm requires a second click.
- **AC-38 [U]** All Buttons use ACTION_MODE_BUTTON_PRESS; decorative overlays use MOUSE_FILTER_IGNORE.

### Visual / review
- **AC-39 [X]** Shots at 1920×1080 for battlefield (early and late run), draft, Core Bay, crate open, Outpost (empty and developed), Reforge: no clipped or overlapping text, no duplicated HUD, no placeholder art.
- **AC-40 [X]** Two seeded late-run grids with the same Core look visibly different; two seeded Outposts (different layouts and decor) look visibly different.
- **AC-41 [X]** Every ArtDB id listed in REDESIGN_SPEC §6 resolves to a real SVG (also asserted in S); Outpost buildings show distinct art at level bands 1–3/4–7/8–10.
- **AC-42 [X]** Gates are green: import, `--quit-after 120` with no SCRIPT ERROR/ERROR:/Failed to load, SELFTEST OK, UITEST OK, PLAYTEST OK, `npm test`.
