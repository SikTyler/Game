# Corehold PC — Reconciled Redesign Spec (final numbers + work packages)

This is the **single source of truth** for the redesign. Content tables not repeated here (the
part list, picks list, shard tree, Outpost building table) are adopted **verbatim from
REDESIGN_SYSTEMS.md** except where §0 or this doc overrides them. Acceptance criteria (AC-xx) live
in REDESIGN_BRIEF.md §4. Constants are read via `TuneRef.num(key, default)` and the defaults equal
this document.

## 0. Reconciliation log (conflicts between VISION / SYSTEMS / POWER_MODEL)

| # | Topic | Conflict | Final decision | Why |
|---|---|---|---|---|
| R1 | Wave HP growth | SYSTEMS §9 says ×1.105/wave; POWER_MODEL measured the code | **Code is truth:** HP ×1.17/wave (T1), 1.18 (T2), 1.155 (T3+), ×1.5^(t-1) per tier; required DPS ×1.258/wave before w20, ×1.17 after | Measured, not assumed |
| R2 | In-run economy | SYSTEMS track growth 1.22–1.30 was keyed to 1.105² | Kill cash ×1.10/wave; track growth **1.16–1.20**; Damage track is multiplicative ×1.08/level | In-run power ≈ ×1.124/wave vs difficulty ×1.17; the 1.041 gap is closed by meta (POWER_MODEL §5) |
| R3 | Part slots | SYSTEMS 2→6 at L1/5/12/20/30 + Set slot L40; PM 3→7 at L1/5/10/20/35 | **SYSTEMS table** (2/3/4/5/6 + Set slot at L40) | Matches the 4-slot-type cycle; PM's valuation (≈+1.5 waves per slot) still holds |
| R4 | Reforge gate | SYSTEMS: tier ≥3 or 1M coins; PM: w* ≥ 40 | **best wave ≥ 40 on any tier, or ≥1,000,000 coins since last Reforge** | Wave gate is legible; coin gate rescues stuck players |
| R5 | First-Reforge shards | PM table assumed a "gate bonus to 25" | **+5 flat bonus** on the first Reforge only; loop table in §4.6 recomputed | 25 free shards trivialises the tree |
| R6 | What Reforge keeps | VISION/SYSTEMS reset the Outpost and part levels; PM keeps both | **Keeps:** owned parts + stars, set unlocks, specials, Cores, cards, gems, Keys, Insight, shards/tree, Outpost **layout, plots, decor, blueprints**. **Resets:** coins, Core levels, part levels (50% Scrap refund), Outpost building **levels** (to 1, `retain` node keeps 10/20/30%), Research levels, tier | Personal Outpost (G4) must survive; levels still reset so loops have something to regrow |
| R7 | Save version | Plan says "save v3"; PC save is already v3 | **v4**, migration v3 → v4 | Fact of the code |
| R8 | Core roster | 5 Cores | **4 Cores ship** (Bastion, Foundry, Lance, Tempest); Hive is deferred (§9) | Quality: troop huts already deliver the troop fantasy |
| R9 | Storage cap | — | 8 h default; Storage Tech raises it to 12 h at L4 and 16 h at L10 | Both docs agree |
| R10 | Insight lifetime cap | PM-12 says 25% per stat; SYSTEMS has per-stat caps | **SYSTEMS per-stat caps** (all ≤ 25%) | Stricter, compatible |

## 1. Governing invariant
Power ratio `R = effective_DPS / required_DPS(w, tier)` (PowerModel). Bands: early (w ≤ w*/2) ≥ 2.0;
frontier [0.8, 1.25]; frontier+5 < 0.6. Log-power shares at the frontier: cash tracks 30%,
picks 30%, parts 20%, Core level 10%, shards + Insight 10%. +10 waves needs ×1.35–1.65 meta power.

## 2. WP ENGINE-RUN

**Files:** `data/CoreDB.gd` (new), `data/PickDB.gd` (replaces PerkDB; PerkDB ids kept as aliases for cards), `Draft.gd` (rewrite), `Troops.gd` (new), `Specials.gd` (new), `Drops.gd` (new), `PowerModel.gd` (new), `TowerState.gd` (refactor), `selftest.gd`, `playtest.gd`.

### 2.1 Cores
- Base sheets, traits and L10/L20/L30 breakpoints: SYSTEMS §1.1–1.2 for bastion, foundry, lance, tempest.
- Per Core level: dmg ×1.06, HP ×1.05, regen ×1.04, cash/s ×1.04 (multiplicative).
- Level cost: `round(200·1.18^(L-1))` coins + `floor(L/5)` Core Cores. Max level 40 (50 with `core_ceiling`).
- Unlocks: Bastion at start; Foundry when T2 is cleared; Lance with the first Reforge (`root_forge`); Tempest when a 2-piece set is equipped and best wave ≥ 60.
- The Core's attack emits `core_attack{kind, targets}` events; the view only replays them.

### 2.2 Cash tracks (reset each run)
| track | per level | base | growth | cap |
|---|---|---|---|---|
| Damage | ×1.08 Core + building dmg | 20 | 1.18 | 60 |
| Rate | +3% Core rate | 30 | 1.20 | 40 |
| Range | +0.1 Core range | 40 | 1.20 | 20 |
| Eco | +0.4 cash/s, interest cap +5 | 25 | 1.17 | 50 |
| Armor | +5% HP, +0.2 regen, +0.5 armor | 25 | 1.16 | 60 |

- Starting level = `head_start` node level.
- Kill cash = `base_kill · 1.10^(w-1)`, tier-multiplied ×(1 + 0.5(t-1)).
- Interest is paid per wave on banked cash up to the Core's cap.

### 2.3 Grid and drafts
- 9×9 grid with the Core at the centre and nothing else. Ring 1 is open; rings 2/3/4 open at track total levels 10/30/60.
- A draft appears after waves 1, 2, 3, then every 2nd wave, plus every boss wave. 3 choices (4 with `wide_draft`).
- Rarity weights: Common 60 / Rare 28 / Epic 10 / Legendary 2. Luck moves 1 point from Common into Epic+ per Luck point (max 10).
- **Eco guarantee (G1):** if a rolled hand has no eco card or no non-eco card, the last slot is rerolled once from the missing pool (seeded).
- Reroll: 1 free per draft, then 10 cash doubling within the draft (×1.10^w scaling). Banish: 1 per run (+1 Archive L9, +2 `banish+`). Banished ids leave the run pool.
- Duplicate building pick = level up that building (+35% main stat per level, max L5); it is offered only if one is owned.
- Pick families and content, from SYSTEMS §2.3–2.7:
  - 17 buildings
  - 10 packs
  - 6 specials (Napalm Line is cut, §9)
  - 3 troop huts
  - 7 Insight picks. Insight appears with p = 1% per draft slot (×(1 + Luck·0.05)), at most 1 per run before Archive.
- Every pick carries `tags` (eco, dps, aoe, control, troop, special, sustain) used for synergy display and the card filter.

### 2.4 Specials
- Hotkeys 1–4. Cooldown ticks in sim time (respects game speed). Targeted specials (Orbital) take a grid cell argument.
- `cast_special(slot, cell)` returns `ok|cooldown|no_target`; a successful cast emits `special_cast`.

### 2.5 Troops
- SYSTEMS §2.6 stats and AI, in `Troops.gd`: pure, seeded, stepped by the TowerState tick.
- Events: `troop_spawn`, `troop_move`, `troop_hit`, `troop_die`.
- Barracks tier (Outpost) gives +10% HP and dmg per level.

### 2.6 Drops
- Rates per SYSTEMS §3.5.
- Courier: from W15 at 0.6% per wave; 2× HP, 3× speed; flees along the lane.
- Drops are collected into `run.loot` and banked by `BaseMeta.bank_run()`. Part cap 3 + Courier.

### 2.7 PowerModel.gd
- API exactly as in POWER_MODEL §10: pure, static, no RNG.
- `TowerState.power_snapshot() -> Dictionary` exposes Core dmg/rate/hp/regen, the building DPS list, troops, specials and global multipliers.

**Removed from TowerState:** permanent building slots and the Offline coupling.

## 3. WP ENGINE-META

**Files:** `data/PartDB.gd`, `data/SetDB.gd`, `data/CrateDB.gd`, `data/OutpostDB.gd`, `data/ReforgeDB.gd` (new); `Parts.gd`, `Crates.gd`, `Outpost.gd`, `Reforge.gd` (new); `Labs.gd` → research functions driven by Outpost; `Offline.gd` deleted (its tests are rewritten to Outpost accrual — a deliberate change); `BaseMeta.gd` v4; `data/AchievementDB.gd`; `SteamService.gd`.

### 3.1 Parts / sets / crates / salvage
- 32 parts per SYSTEMS §3.2. Hive-only effects fall back to their listed "others" branch (b_droneport: +1 hut drone; f_hivecomb unchanged).
- Rarity, levels, Scrap and salvage per SYSTEMS §3.1.
- Before data lands, every part must pass PowerModel `part_value` within ±10% of `part_budget` (B: C .08, R .12, E .17, L .24, special .30, ×(1 + 0.06(lvl-1))). Any table entry that fails is re-tuned **in the data**; the test is never loosened.
- Sets and specials per SYSTEMS §3.3. 2-piece ≤ 0.5·B; 4-piece ≤ 1.2·B.
- Stacking the same stat is additive within `(1 + Σ)`.
- Crates: Field / Supply / Vault per SYSTEMS §3.4 (odds disclosed, pity saved). Set Crate is cut (§9).
- Field Crate cost: 2,500 × (1 + 0.25(T-1)) coins.

### 3.2 Outpost
- 14×10 map, Relay 2×2, starting 6×6 open area, 8 expansion plots costing `5,000·2.2^k` coins (+20·k gems for k ≥ 4, **or** an equivalent coin price ×3, so gems never gate).
- Buildings, power, adjacency, quantity limits: SYSTEMS §5.1–5.2.
- Upgrade cost ×1.6^(L-1), time ×1.4^(L-1), production +25% of L1 per level. Max level = min(10, Relay L+2).
- Connectivity is a 4-neighbour flood fill from the Relay through Conduits and buildings; unconnected generators produce 0.
- **Layout bonus cap:** the sum of adjacency, Warehouse and Beacon bonuses on one building is capped at +60%.
- Storage: own cap per building (8 h of output at L1; Warehouse radius 2 +25%). Accrual is `min(rate·(now - last_tick), cap)`, with `now` injected.
- Collect per building; Collect all at Relay 3.
- Builders: 1, plus a 2nd from the `builder2` shard node. The gem-bought 3rd builder is cut. Skip cost: 1 gem per 3 remaining minutes.
- Gem Mine: Crystal Vein tiles only (1 in the start area, 2 in plots). 1 gem/3 h at L1 → 1/h at L10, hard cap 24 stored, daily cap 25.
- Decor tags, Charm (+1% per 10 distinct decor, max +10%), blueprints (5 save slots; one-click rebuild of owned buildings; export/import as a base64 string).
- Building art bands at L1–3, L4–7 and L8–10.
- Outpost/active coin ratio target 0.15–0.35 (POWER_MODEL §5 stage table). Coin Mill base 60/h is the tuning knob.

### 3.3 Research Hall
- All 10 LabDB projects move unchanged. `offcap` → **Storage Tech** (+10% storage per level), `offrate` → **Logistics Tech** (+5% production per level).
- New projects: **Part Analysis** and **Crate Theory** (SYSTEMS §5.4).
- Queues 1/2/3 at Hall L1/L4/L8.

### 3.4 Reforge
- Gate: R4. Shards: `floor(k·√(coins_since/10,000))`, k = 1 × (1 + 0.1·shard_yield); +5 on the first Reforge.
- Reset/keep: R6. Shard tree: SYSTEMS §6.1, minus `core_hive` (deferred), with `retain` re-pointed to building levels.
- The preview shows the shards gained now, the reset/keep lists, and "worth it" when `new ≥ 0.5·cumulative`.
- Loop target: ≤ 70% of the prior loop's time to previous best.

Recomputed loop table (R5):

| Loop | coins_since | shards | cumulative |
|---|---|---|---|
| 1 | 6e5 | 7 + 5 | 12 |
| 2 | 2.5e6 | 15 | 27 |
| 3 | 8e6 | 28 | 55 |
| 4 | 2.5e7 | 50 | 105 |

The playtest sim validates AC-28 against these; if it fails, tune the tree's node values, not the gate.

### 3.5 Save v4 + migration
- Schema and migration steps exactly as in SYSTEMS §8, with these changes:
  - `cores.owned` never includes hive.
  - `outpost.buildings[*]` survives Reforge with `lvl` reset.
  - `outpost.blueprints` cap 5.
- The migration is pure and idempotent; sanitize step included. The v3 fixture assertions are updated (deliberate; AC-22).

### 3.6 Steam achievements (add to AchievementDB + SteamService map)
`ach_first_part`, `ach_full_set`, `ach_first_reforge`, `ach_reforge_5`, `ach_gem_mine`, `ach_courier`, `ach_cores_4`, `ach_outpost_full` (all 8 plots), `ach_insight_10`, `ach_special_100` (100 special casts).

## 4. WP ART (SVG via `art/_gen_svg_pc.py`; ids resolve through ArtDB)
Every id below must exist as `art/<id>.svg` (AC-41). The 15 adapted building ids (gun, mortar, tesla, flak, railgun, armory, beacon, bulwark, aegis, barricade, mine, oilmill, bounty, vault, refinery) already exist and are kept.

- **Cores:** `core_bastion`, `core_foundry`, `core_lance`, `core_tempest`, `core_locked`, `core_open` (exploded view for the Bay).
- **Core attacks / fx:** `fx_cannon`, `fx_slag`, `fx_beam`, `fx_pulse_ring`, `fx_chain`, `fx_splash`.
- **New buildings:** `frost`, `obelisk`.
- **Huts / troops:** `hut_infantry`, `hut_sapper`, `hut_drone`, `troop_rifleman`, `troop_sapper`, `troop_drone`.
- **Packs (icons):** `pk_arsenal`, `pk_overclock`, `pk_fort`, `pk_ledger`, `pk_optics`, `pk_crit`, `pk_logistics`, `pk_core`, `pk_barracks`, `pk_gambit`.
- **Specials (icons):** `sp_orbital`, `sp_emp`, `sp_repair`, `sp_overdrive`, `sp_magnet`, `sp_timewarp`; plus `fx_orbital`, `fx_emp`.
- **Insight:** `insight` (card frame glow) and `in_dmg`, `in_hp`, `in_cash`, `in_rate`, `in_luck`, `in_drop`, `in_crate`.
- **Draft frames:** `card_common`, `card_rare`, `card_epic`, `card_legendary`, `card_insight`; tag chips `tag_eco`, `tag_dps`, `tag_aoe`, `tag_control`, `tag_troop`, `tag_special`, `tag_sustain`.
- **Enemies:** `courier`.
- **Parts:** slot glyphs `slot_frame`, `slot_barrel`, `slot_capacitor`, `slot_engine`, `slot_set`, `slot_locked`. Part icons use the 32 PartDB ids (e.g. `f_plating` … `e_queen`); specials `citadel_heart`, `golden_ratio`, `singularity_lens`, `eye_of_storm`, `brood_mother`. Set badges `set_bulwark`, `set_mint`, `set_lancer`, `set_storm`, `set_swarm`.
- **Crates:** `crate_field`, `crate_supply`, `crate_vault`, `crate_open_fx`.
- **Currencies:** `cur_coin`, `cur_gem`, `cur_scrap`, `cur_key`, `cur_corecore`, `cur_shard`, `cur_cash`.
- **Outpost buildings:** each of `op_relay`, `op_mill`, `op_refinery`, `op_gemmine`, `op_keyforge`, `op_research`, `op_barracks`, `op_archive`, `op_warehouse`, `op_scrapyard`, `op_beacon` with suffix `_1`, `_2`, `_3` (level bands).
- **Outpost misc:** `op_conduit` (auto-tiled via `op_conduit_n`, `_e`, `_s`, `_w` overlay stubs), `op_plug` (unconnected), `op_vein`, `op_plot_locked`, `op_builder`, `op_timer`.
- **Outpost terrain:** `tile_ash`, `tile_rock`, `tile_water`.
- **Decor:** `dc_smelter`, `dc_crates`, `dc_bookshelf`, `dc_orrery`, `dc_yard`, `dc_dummy`, `dc_lamp`, `dc_brazier`, `dc_tree`, `dc_shrub`, `dc_pond`, `dc_banner`, `dc_trophy`.
- **Reforge:** `rf_root`, `rf_power`, `rf_economy`, `rf_mastery`, `rf_node_locked`, `rf_node_owned`.
- **UI:** `ui_hotkey_frame`, `ui_cooldown`, `ui_reroll`, `ui_banish`, `ui_collect`, `ui_rotate`, `ui_demolish`, `ui_move`, `ui_blueprint`.

## 5. WP UI (native 1920×1080; `Main.gd`, `ui/Desktop.gd` rewrite, new `ui/CoreBay.gd`, `ui/Crates.gd`, `ui/OutpostView.gd`, `ui/ReforgeView.gd`, `ui/DraftPanel.gd`, `ui/Hotbar.gd`)
- **Delete** the embedded 720×1280 column and every duplicated HUD label (G6). One `Desktop` root with a top bar plus a content area that swaps screens.
- **Top bar (56 px):** currencies (coin, gem, scrap, key, Core Core, shard) left; wave/tier/speed centre; menu/settings right. In-run, cash and Core HP live only in the right panel.
- **Battlefield screen:**
  - Left panel 400 px: draft panel when a draft is pending, otherwise build/info for the hovered cell or pick.
  - Centre field.
  - Right panel 400 px: Core portrait, stats, HP bar, cash, interest, and the 5 cash-track buttons with cost.
  - Bottom hotbar 96 px: specials 1–4 with cooldown sweep and key label.
- **Draft panel:** 3–4 cards (rarity frame, family icon, name, effect, tags, "Lv N→N+1" for duplicates), reroll (shows cost), banish. Insight cards play a distinct reveal (fanfare event).
- **Core Bay:** Core list (locked ones show the unlock condition); the selected Core opens in its exploded view with slots around it; inventory grid with slot/rarity/set filters; part tooltip with **+** lines in green and **−** in red; preset tabs 1–4; set progress badges; level-up / salvage / lock buttons.
- **Crate screen:** crate cards with price and disclosed odds and pity; open animation driven by an `opened` event list; a results row.
- **Outpost builder:**
  - Map centred and pannable; build palette right (by category, showing cost, power and limits); builder/timer queue bottom; Collect all.
  - Hover preview: ghost footprint, green/red validity, connectivity line, and an adjacency delta number (e.g. "+15%").
  - Hotkeys: R rotate, M move, Del demolish. Blueprint menu: save/load/export.
- **Reforge screen:** shard preview, keep/reset two-column list, tree with 3 branches (node tooltip with cost/effect), two-step confirm.
- Global: tooltips on every interactive element; keyboard and controller focus order; Buttons `ACTION_MODE_BUTTON_PRESS`; overlays `MOUSE_FILTER_IGNORE`.
- `_shots.gd` adds: battle_early, battle_late, draft, draft_insight, bay, crate_open, outpost_new, outpost_dev, outpost_hover, reforge.

## 6. Sequencing
1. ENGINE-RUN (PowerModel first, then Cores/tracks, grid/draft, specials, troops, drops)
2. ENGINE-META (Parts → Crates → Outpost → Research move → Reforge → save v4)
3. ART (can run in parallel after the id list freezes)
4. UI
5. Balance tuning pass until P gates are green
6. Visual review

Each step keeps every gate green before commit.

## 7. Tuning knobs (Tune keys)
`pc_kill_growth` 1.10, `pc_track_growth_*`, `pc_core_cost_growth` 1.18, `pc_mill_rate` 60, `pc_storage_h` 8, `pc_layout_cap` 0.60, `pc_reforge_k` 1, `pc_reforge_l0` 10000, `pc_reforge_gate_wave` 40, `pc_insight_p` 0.01, `pc_courier_p` 0.006.

## 8. Event additions (view replays, owns no rules)
`core_attack`, `draft_offer`, `pick_applied`, `building_level`, `special_cast`, `special_ready`, `troop_spawn`, `troop_move`, `troop_hit`, `troop_die`, `insight_found`, `drop`, `courier_spawn`, `courier_escape`, `ring_open`.

## 9. Cut / deferred (protect quality)
- **Hive Core** and the `core_hive` node. Troop huts cover the fantasy. Swarm set stays.
- **Set Crate** (weekly rotation): needs live-ops cadence.
- **Napalm Line special**: drag-input complexity across mouse and controller.
- **Gem-bought 3rd builder**: G5 optics.
- **Outpost themes** (Verdant/Frost/Neon): only the `ash` palette ships; tier rewards give decor instead.
- **Workers walking roads**: cosmetic; replaced by builder icons on active jobs.
- **Terrain-aware expansion**: plots are fixed chunks; terrain is decorative except Crystal Veins.
- **Loadout presets beyond 4**, and part "lock-in" re-rolling of stats: no stat re-rolls at all.
