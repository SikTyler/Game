# Corehold PC: Design Spec (games/towerdef-pc-0001)

Author: PC Game Director and Game Designer. Inputs: the mobile `design/BRIEF.md`, `SPEC.md` and `ECONOMY.md` (all still in force unless overridden here) and `PC_INVENTORY.md`.
The PC game is a full fork. **Nothing in games/towerdef-0001 changes.** Every new constant goes through `Tune.num/int_of(key, default)`, with the default shown as `key=default`.
Gates: **S** = selftest.gd, **U** = uitest.gd, **P** = playtest.gd, **X** = 1920x1080 screenshot review (`_shots.gd` → scratchpad/pcshots).

---

## 0. What changes for a PC / Steam audience

| Axis | Mobile | PC ruling | Why |
|---|---|---|---|
| Session | 3–8 min runs, about 4 a day | **Runs of 15–45 min**, and endless runs of 60+ min. Waves are about 20% longer through a larger arena and more spawn directions, not through raw HP inflation. | Players sit down to play, and a Steam review punishes "nothing to do". |
| Idle vs active | Mostly idle, plus taps | **Active-first, with idle allowed.** The run is fully playable hands-off; the skill ceiling comes from placement, timing the 1–4 abilities, lane focus and drag rearranges between waves. Offline income stays (≤ 20% of active rate) but is capped at 8 h (`pc_offline_cap_h=8`). | PC TD players expect agency. "Idle" has to be a choice, not the design. |
| Depth | 10 buildings, 5x5 | **7x7 ring-unlocked base, 15 buildings, 9 synergies, endless mode, 8 modifiers, achievements, stats** | Players expect 50+ hours of content. |
| Monetisation | Already earn-only | **Premium, buy once.** No gem shop, ads, energy or real-money path. Gems are kept as an earn-only meta currency, renamed "Cores" in the UI only (the save key stays `gems`). The daily streak is kept but softened: missing a day **pauses** it instead of resetting it (`pc_streak_pause=1`). | Mobile retention crutches read as predatory on Steam. |
| Timers | Labs take real time, up to hours | Lab durations ×0.5 (`pc_lab_time_mult=0.5`). Labs can also progress **during runs at 2× speed** (`pc_lab_run_mult=2`). | Long real-time waits are a mobile pattern. |
| Input | Taps, 88 px buttons | Mouse, keyboard and controller. Minimum button height 40 px at UI scale 1.0, with hover states, tooltips and hotkeys. | |
| Speed | 1× to 2.5× (lab-gated) | 1×/2×/3× from the start, with the 4× step lab-gated. Pause on Space at any time. | Pausing a PC game has to be instant. |

Pillars 1, 2, 3 and 5 are unchanged. Pillar 4 becomes **"One more run, honestly"**: no FOMO, and the streak pauses instead of punishing.

---

## 1. Desktop UI and controls

### 1.1 Display
- `project.godot`: viewport 1920x1080, `window/stretch/mode="canvas_items"`, `aspect="expand"`, `window/size/resizable=true`, minimum window 1280x720. All layout uses anchors and containers, with no absolute pixel positions beyond the 1920x1080 reference.
- UI scale setting: 0.75–1.5 (step 0.05), applied as `get_window().content_scale_factor`. Default 1.0.

### 1.2 Layout at 1920x1080 (reference px)
```
+--------------------------------------------------------------------------------+
| TOP HUD 64px: Wave 37 · T3 | HP bar | $ cash | coins | cores | speed pill | ⏸ ⚙ |
+-----------+-----------------------------------------------------+--------------+
| LEFT 360  |              BATTLEFIELD  (center, ~1200x880)       | RIGHT 360    |
| Build/Info|   arena circle; core + 7x7 base grid at center      | Upgrades /   |
| tabs:     |   (cell 72px → 504px grid), spawn telegraphs on 4–8  | Stats tabs:  |
|  Build    |   edges, range rings on hover                        |  Core ups    |
|  Info     |                                                      |  Run stats   |
| (building |                                                      |  Perks taken |
|  palette, |                                                      |  Modifiers   |
|  selected |                                                      |  DPS meter   |
|  details) |                                                      |              |
+-----------+-----------------------------------------------------+--------------+
| BOTTOM HOTBAR 88px: [1..9,0 building slots] | [Q W E R abilities] | lane focus  |
+--------------------------------------------------------------------------------+
```
- The side panels can be collapsed with Tab and Shift+Tab; the battlefield then expands into the freed space.
- Base and meta screens (Base, Labs, Cards, Missions, Stats, History, Achievements) use the same frame: a top tab bar plus a content area. The left and right panels are replaced by tab content. START is always visible bottom-right, with the tier and mode selector beside it.
- Perk draft: a centered modal with 3 cards side by side, picked with hotkeys 1/2/3. The run pauses while it is open.
- Death and summary screen: a centered modal with the coin breakdown, a stats summary, and "Back to Base" and "Retry same seed" buttons.

### 1.3 Hotkey map (defaults, all remappable; action names in brackets)
| Key | Action |
|---|---|
| Space | pause/resume `[pause]` |
| `F` / `G` | speed down / up `[speed_down]` `[speed_up]` |
| 1–9, 0 | select hotbar building 1–10 `[hotbar_1..10]` |
| Q W E R | abilities 1–4 (Overcharge, Repair, EMP, Airstrike; unlocked by tier) `[ability_1..4]` |
| U | upgrade hovered/selected building `[upgrade]` |
| X / Delete | sell hovered/selected `[sell]` |
| Shift+click | upgrade ×5 / place repeatedly `[modifier_bulk]` |
| Esc | cancel placement → close modal → pause menu `[cancel]` |
| Tab / Shift+Tab | toggle left / right panel `[toggle_left]` `[toggle_right]` |
| B L C M | Base / Labs / Cards / Missions (meta screen) `[tab_*]` |
| H | stats/history `[tab_stats]` |
| Z / C | focus lane prev/next (arrow camera nudge in endless) `[lane_prev]` `[lane_next]` |
| Ctrl+R | retry same seed (death screen only) `[retry]` |
| F11 / Alt+Enter | toggle fullscreen `[fullscreen]` |
| F12 | screenshot to user://screenshots `[screenshot]` |
| Mouse wheel | scroll a panel under the cursor; over the battlefield, zoom 0.8–1.4× `[zoom_in/out]` |

### 1.4 Controller mapping (Xbox layout; glyphs come from Xelu CC0 by device)
| Button | Action |
|---|---|
| Left stick / D-pad | move the grid cursor (it snaps to cells) and navigate UI focus |
| A | place/confirm, or upgrade if the cell is occupied |
| B | cancel/back |
| X | open the cell info |
| Y | sell, held for 0.6 s with a fill ring |
| LB / RB | cycle hotbar building |
| LT / RT | speed down / up |
| D-pad left/right while LT is held | lane focus |
| Right stick | battlefield pan/zoom (zoom on click) |
| Start | pause menu · View/Back: stats panel |
| A/B/X/Y while RB is held | abilities 1–4 |

Every panel has `focus_neighbor_*` set or uses containers with focus mode ALL. A first control grabs focus when each screen opens. The displayed glyphs switch on the last input device used (keyboard/mouse, xbox, ps5 or steamdeck).

### 1.5 Mouse semantics
- **Drag-to-place:** press on a hotbar or palette card, drag over the grid, and release to place. The ghost turns green (valid) or red (invalid) and its tooltip states the reason ("Locked ring", "Not enough coins", "Occupied"). Shift+release keeps the same building selected for repeated placement. Click-select then click-cell does the same thing without dragging.
- **Drag an existing building** (between waves or while paused) to another empty unlocked cell to move it for free, or onto another building to swap them. Moving during an active wave costs `pc_move_cost_frac=0.1` of the building's value. This makes the eco/defense rearrangement a skill expression. The engine owns the rule through `TowerState.move_building(a, b) -> Array[events]`.
- **Left click** a building to select it; the Info tab shows it. **Right click** a building opens the info popover (stats, synergies, Upgrade [U], Sell [X] with the refund amount). Right-click again or Esc closes it. Right click on empty ground cancels placement.
- **Hover:** a range ring and synergy link lines to adjacent partners, plus a tooltip after 350 ms (`pc_tooltip_delay=0.35`).
- **Wheel:** over a panel it scrolls that panel; over the battlefield it zooms; Ctrl+wheel over a building upgrades it by 1 (repeat-safe, cost shown).

### 1.6 Tooltip content rules
Implement with `tooltip_text` plus `_make_custom_tooltip` returning a shared `ui/Tip.gd` panel. Every interactive control must have a non-empty tooltip, and uitest walks the tree to check this.
1. Title line: the name, plus the hotkey glyph right-aligned.
2. One line saying what it does, using the same wording as the DB `desc`.
3. Numbers as **current → next** at the next level, with the delta coloured (green for a gain, red for a cost or penalty).
4. Synergy lines (active ones lit, inactive ones dimmed, naming the partner).
5. Cost and refund on the last line. When disabled, a red reason line is shown instead ("Requires T3", "Max level").
Tooltips are at most 320 px wide with no scrolling, and must not cover the hovered cell: they flip sides at screen edges. The Info tab shows the same content persistently for the selected item.

---

## 2. Bigger base and battlefield

### 2.1 The 7x7 base and ring unlocks
- Rings by Chebyshev distance from the core cell (3,3): ring 0 is the core, ring 1 is 8 cells, ring 2 is 16 cells, ring 3 is 24 cells.
- **Permanent unlocks** (BaseMeta, bought with coins): the ring 1 inner cells start unlocked (the mobile 5x5 is 24 cells, but we start smaller to keep the early game readable). Ring 2 cells unlock one at a time at `pc_cell_cost_r2=400×1.18^n` coins. Ring 3 cells need **best tier ≥ 3** and cost `pc_cell_cost_r3=2500×1.22^n`. Corners in each ring cost +50%.
- **Run slot cap:** you can build on at most `pc_build_cap = 12 + 2*(highest_tier-1)`, capped at 40, unlocked cells per run. This keeps scarcity, and so the eco-vs-defense tradeoff, even with 48 cells.
- Outer rings get a range bonus for weapons (+8% per ring, `pc_ring_range=0.08`), while support and eco auras reach only adjacent cells. That creates a real inner-vs-outer placement puzzle.

### 2.2 New buildings (5 new, 15 total)
| id | name | cat | coin | effect | synergy (adjacent) |
|---|---|---|---|---|---|
| railgun | Railgun | weapon | 28 | Pierces in a line, 1 shot per 2.5 s, huge damage, outer rings only (ring ≥ 2) | **S6 "Capacitor Bank"**: next to a Tesla, +20% damage per Tesla level/5 (capped at +60%) |
| flak | Flak Battery | weapon | 22 | Fast splash against fast and small enemies (skitter, mite, drone ×1.5) | **S7 "Crossfire"**: next to a Gun, both get +10% crit chance |
| beacon | Lane Beacon | support | 20 | Marks the focused lane; weapons +15%/lv damage toward that quadrant only | **S8 "Spotter"**: next to a Mortar, the Mortar gets +25% range |
| refinery | Refinery | eco | 24 | Converts 10% of cash income into coins at the end of each wave (cap 5 coins/lv/wave) | **S9 "Smelter"**: next to a Mine, Mine output +20%. The Aegis −15% eco penalty still applies. |
| barricade | Barricade | support | 16 | Spawns a wall segment on its quadrant's lane that slows by 30% and has HP 60×lv; it rebuilds each wave | none (pure defense; eco players give it up) |

The eco/defense tradeoff is preserved because Refinery is the only new eco building and it is worth less than Mine plus Vault unless it sits next to a Mine, which then takes a cell that could go to Aegis. AC-38 and AC-39 are re-run on the PC roster.

### 2.3 Multi-direction spawns
- The arena has 8 spawn points (N, NE, E, SE, S, SW, W, NW), grouped into 4 quadrants.
- Active directions: waves 1–9 use 1 random quadrant per wave; 10–24 use 2; 25–49 use 3; 50+ use all 4. Bosses always come from a single, telegraphed direction. All choices come from the seeded RNG (`TowerState.rng`).
- **Telegraph:** 3 s before a wave (`pc_telegraph_s=3`), the active edges show a pulsing chevron and a count badge ("×24 · 3 elite"). The engine emits `wave_telegraph {quadrants:[..], counts:{..}, boss_dir}` before `wave_start`.
- Lane focus: the selected quadrant gets a highlighted rim. Beacon and abilities target it.

---

## 3. Modes

### 3.1 Endless mode
Unlocked after you reach wave 50 in any tier. There is no tier wave target. HP scaling continues past wave 100 with a soft exponent (`pc_endless_hp_exp=1.12`). Every 25 waves the player chooses one of 3 **mutation cards** (enemy buffs that pay +15% coins each). Leaderboard hooks: `SteamService.upload_score("endless_best_wave")`, which is a no-op offline. Banking works as in normal mode, but coins are ×0.9 (`pc_endless_coin_mult=0.9`, retuned in PC_BALANCE.md) so endless does not replace tier progression.

### 3.2 Challenge modifiers (pick any before a run; rewards stack additively, then cap at ×3.0)
| id | name | effect | coin mult |
|---|---|---|---|
| glass | Glass Core | Core max HP −50% | +0.15 |
| swarm | Swarm | +60% enemy count, −30% HP each | +0.10 |
| ironclad | Ironclad | All enemies take −20% damage from non-crit hits | +0.30 |
| poverty | Austerity | Start cash 0, kill cash −30% | +0.10 |
| allsides | Encircled | All 4 quadrants from wave 1 | +0.10 |
| noperks | Purist | No perk drafts | +0.55 |
| haste | Haste | Enemy speed +25% | +0.10 |
| elitist | Elite Guard | Elite weight ×3, from T1 | +0.40 |
| nolabs | Fresh Start | Lab bonuses disabled for the run | +0.60 |

Rewards retuned from the original spec by measured difficulty (see PC_BALANCE.md).

Modifiers are a pure data module `data/ModifierDB.gd` and are applied in `TowerState.setup(opts.modifiers)`. Achievements key off them.

---

## 4. Meta: stats, history and save slots
- **Stats screen** (`Stats.gd`, engine): lifetime kills by enemy kind, waves cleared, bosses, coins earned/spent, buildings placed by id, play time, best wave per tier and per mode, favourite build (the most-placed set), highest DPS. It is updated only from events, through `Stats.on_event(s, ev)`.
- **Run history:** the last 50 runs (a ring buffer) as `{seed, tier, mode, modifiers, wave, coins, duration_s, build:[ids by cell], perks, ts}`. You can **retry the same seed** from history.
- **Save slots:** 3 slots at `user://slot_{1,2,3}.json`, plus `user://slot_n.bak` written before each save, and an atomic write (write to `.tmp`, then rename). Settings are global at `user://settings.cfg` and never in a slot. The slot picker shows the best tier, best wave, play time and last played. You can copy a slot into an empty slot, and deleting a slot needs a typed confirmation.
- **Steam Cloud:** Auto-Cloud on `user://slot_*.json` and `user://settings.cfg` (configured in Steamworks, so no code is needed). `SteamService.cloud_write/read` is the fallback for Remote Storage. Conflicts use the slot with the higher `playtime_s`, keeping the other as `.conflict`.
- Save schema v3: adds `version:3`, `stats{}`, `history[]`, `achievements{}`, `base7{unlocked_cells:[int]}`, `endless{best}`, and `streak.paused`. `migrate()` v2 → v3 maps the 5x5 coordinates (r,c) to (r+1,c+1) on the 7x7. This only matters for importing the mobile save, which is optional.

---

## 5. Achievements (`data/AchievementDB.gd`; the engine module `Achievements.gd` evaluates events, and SteamService mirrors it)
| id | name | condition |
|---|---|---|
| ACH_FIRST_RUN | First Light | Finish any run |
| ACH_WAVE_25 | Holding Pattern | Reach wave 25 |
| ACH_WAVE_100 | Centurion | Reach wave 100 |
| ACH_WAVE_250 | Unbreakable | Reach wave 250 (endless) |
| ACH_TIER_3 | Tiered Up | Unlock T3 |
| ACH_TIER_8 | Apex | Unlock T8 |
| ACH_FIRST_BOSS | Big Game | Kill a boss |
| ACH_BOSS_50 | Boss Hunter | 50 lifetime bosses |
| ACH_KILLS_100K | Exterminator | 100,000 lifetime kills |
| ACH_RING_3 | Outer Walls | Unlock a ring 3 cell |
| ACH_FULL_BASE | Fortress | Unlock all 48 cells |
| ACH_ALL_SYNERGY | Networked | Have all 9 synergies active at once in a run (is this possible within the build cap? Validate it in the playtest, or change it to 6) |
| ACH_ECO_ONLY | Merchant Prince | Reach wave 30 with no weapon buildings |
| ACH_NO_ECO | Iron Doctrine | Reach wave 60 with no eco buildings |
| ACH_LABS_MAX | Mad Scientist | Max any lab track |
| ACH_CARD_MAX | Collector | Get a card to level 5 |
| ACH_MOD_3 | Masochist | Clear wave 50 with 3 or more modifiers |
| ACH_GLASS_50 | Glass Cannon | Wave 50 with Glass Core |
| ACH_ENCIRCLED_100 | Surrounded | Wave 100 with Encircled |
| ACH_NO_DAMAGE_10 | Untouched | Clear waves 1–10 with no core damage |
| ACH_SPEEDRUN | Overclocked | Reach wave 40 in 10 minutes or less of game time |
| ACH_STREAK_7 | Regular | 7-day streak |
| ACH_MISSIONS_50 | Contractor | Claim 50 missions |
| ACH_ENDLESS | No End | Unlock endless mode |

That is 24 achievements. Stats mirrored to Steam: `stat_kills`, `stat_bosses`, `stat_best_wave`, `stat_runs`, `stat_playtime_min`.

---

## 6. Settings menu (`Settings.gd`, static, ConfigFile at user://settings.cfg; patterns from Maaack app_settings and the Godot window_management demo)
- **Video:** display mode (Windowed, Borderless Fullscreen, Exclusive Fullscreen), resolution (a list filtered to ≤ the screen size, windowed only), monitor, VSync (Off, On, Adaptive), FPS cap (30/60/120/144/165/240/Unlimited → `Engine.max_fps`), UI scale (0.75–1.5), screen shake (on/off), damage numbers (Off, Compact, Full), reduce motion.
- **Audio:** Master, Music, SFX and UI sliders (0–100 → dB through `linear_to_db`), mute when unfocused.
- **Controls:** a remap list for every action in §1.3, with 2 key slots plus 1 pad slot each. Capture runs in a modal; a conflict swaps the two bindings (input_helper pattern), and there is reset-to-default per action and for all actions. Also: tooltip delay, edge-pan on/off, invert zoom, glyph style (Auto, Xbox, PS, Deck).
- **Gameplay:** auto-pause on draft, auto-pause on focus loss, confirm before sell, default speed, colourblind palette (Off, Deuteranopia, Protanopia, Tritanopia, applied to the lane, valid/invalid and HP colours), and language (English only, but the strings go through `tr()`).
- Apply takes effect immediately. Video changes revert after 10 s unless confirmed. Settings round-trip through ConfigFile, with keybinds serialised as `{action: [event dicts]}`.

---

## 7. Steam service (`SteamService.gd`, static, no typed reference to the extension)
```gdscript
static func init(app_id: int = 0) -> bool          # Engine.has_singleton("Steam") && steamInitEx ok; else false, mock mode
static func is_active() -> bool
static func tick() -> void                          # run_callbacks when active (called from Main._process)
static func unlock_achievement(id: String) -> bool  # setAchievement + storeStats; mock: append to mock_log
static func set_stat_int(id: String, v: int) -> bool
static func store_stats() -> bool
static func upload_score(board: String, v: int) -> bool
static func set_rich_presence(key: String, value: String) -> bool   # "steam_display" -> "#Status_Wave" with tokens wave/tier/mode
static func cloud_write(path: String, data: PackedByteArray) -> bool
static func cloud_read(path: String) -> PackedByteArray
static func overlay_active() -> bool                # pause the game when the overlay opens
static func mock_log() -> Array[Dictionary]         # {op, args, t}; tests inspect it
static func reset_mock() -> void
```
- All calls go through `Engine.get_singleton("Steam").call(...)`, so the project parses and runs without GodotSteam installed.
- The App ID comes from `steam_appid.txt` next to the executable, and only in dev. That file is never committed, and neither are the SDK redistributables (.gitignore `*.dll`, `*.so` under addons/godotsteam, and `steam_appid.txt`).
- Rich presence states: `Menu`, `Base`, `Run: Wave {w} · T{t}`, `Endless: Wave {w}`, `Challenge ×{mult}`.
- The game calls only SteamService. Achievement unlocks flow from engine events through Achievements.gd to SteamService.

---

## 8. Export presets and CI
- `export_presets.cfg`: **"Windows Desktop"** (x86_64, `Corehold.exe`, embed PCK, icon .ico, product/file version from the manifest, no codesign) and **"Linux"** (x86_64, `Corehold.x86_64`, embed PCK). Both use a `custom_features="steam"` feature tag, and `exclude_filter` drops `*test.gd`, `_shots.gd`, `playtest.gd` and `design/*`.
- CI (adapted from abarichello/godot-ci, MIT): a workflow that exports both presets headless with Godot 4.6.3 templates and uploads the artifacts. SteamPipe upload (steamcmd with depot VDFs for depots win/linux) is a documented manual step with VDF templates in `steam/` and no secrets.
- Steam Deck: the default 1280x800 must be playable, with controller support (§1.4) and UI scale 1.0. Aim for "Verified".

## 9. Store-page checklist (sizes from memory; check them against Steamworks before submission)
- [ ] Header capsule 920x430 · Small 462x174 · Main 1232x706 · Vertical 748x896
- [ ] Library capsule 600x900 · Library hero 3840x1240 · Library logo 1280x720 (transparent PNG)
- [ ] At least 5 screenshots at 1920x1080 (from `_shots.gd`: battlefield late wave, 7x7 base, draft, labs, endless/challenge)
- [ ] Trailer of 30–60 s (gameplay first 5 s)
- [ ] Short description of 300 characters or fewer; long description with GIFs; tags (Tower Defense, Roguelite, Incremental, Idler, Strategy, Singleplayer, Controller)
- [ ] System requirements (GL Compatibility/Vulkan; 2 GB RAM; integrated GPU)
- [ ] Achievements uploaded (24, with icons 64x64 in unlocked and locked versions) · Cloud quota and Auto-Cloud paths · Rich presence localisation file
- [ ] Controller-support declaration · Deck compatibility review
- [ ] Credits/legal: Xelu prompts, Maaack, Nathan Hoad, Godot demo contributors, plus every CC-BY item from third_party/README.md
- [ ] Price, regions, age rating questionnaire (IARC), privacy (no data collected)

---

## 10. Work packages and acceptance criteria

### ENGINE (pure static modules; selftest)
| AC | Gate | Criterion |
|---|---|---|
| PC-E1 | S | The base is 7x7. `BaseMeta.cell_ring(r,c)` returns 0–3. A new save has exactly the ring 1 cells unlocked. Unlocking a ring 3 cell fails while highest tier < 3 and succeeds at ≥ 3. Cell costs follow §2.1, including the +50% corners. |
| PC-E2 | S | `build_cap(s)` = 12+2(t−1), capped at 40. Placing past the cap returns `[]` and does not mutate the state. |
| PC-E3 | S | Each of the 5 new buildings applies its effect. S6–S9 change the targeted stat by exactly the spec value when adjacent and by 0 when not, and appear in the compute breakdown. Railgun is rejected on ring < 2. |
| PC-E4 | S | `move_building` is free between waves or when paused, costs 10% during a wave, swaps occupied targets, and emits `building_moved`. |
| PC-E5 | S | Spawn quadrant count per wave follows the §2.3 schedule. `wave_telegraph` precedes `wave_start` by `pc_telegraph_s` and its counts match the actual spawns. Same seed gives the same directions. |
| PC-E6 | S | Each of the 9 modifiers applies its effect. The coin multiplier is `min(3.0, 1+Σ)`. Purist suppresses `perk_offer`. Encircled forces 4 quadrants from wave 1. |
| PC-E7 | S | Endless needs best_wave ≥ 50. It has no wave cap, offers a mutation every 25 waves, and banks coins ×0.9. |
| PC-E8 | S | Stats are updated only through `on_event`. History keeps 50 entries (the 51st evicts the oldest). Retry-seed reproduces an identical first 10 waves (event hash equality). |
| PC-E9 | S | Save v3: v2 migrates to v3 losslessly (5x5 → 7x7 offset), JSON round-trip equality holds, slots 1–3 are independent, and a corrupted primary falls back to `.bak`. |
| PC-E10 | S | Achievements: each of the 24 conditions fires exactly once from synthetic event streams, with no false positives in a 10-wave normal run, and each unlock calls `SteamService.unlock_achievement` (seen in mock_log). |
| PC-E11 | S | SteamService with no singleton: `init()` returns false, every call returns false or empty and logs to the mock, nothing errors, and the run never crashes. |
| PC-E12 | S | Settings: defaults are valid. Save and load through ConfigFile round-trip. The keybind serialise/deserialise round-trip covers keys, mouse and joypad. A remap conflict swaps the bindings. |
| PC-E13 | S | Speed 1–4× changes no outcome (same seed gives the same final state hash). The pause freezes the simulation tick. |
| PC-E14 | P | AC-38/39 hold on the PC roster: eco-mix ≥ 1.10× wave and ≥ 1.25× coins, and no mono board reaches ≥ 70%. Refinery+Mine does not beat a balanced build by more than 15%. |
| PC-E15 | P | A campaign sim of 7 days gives a median run length of 15–45 min of game time in T1–T3. T3 unlocks by day 4–7. Offline income is ≤ 20% of the active rate. Gem/Core income is 10–30 a day with no source above 50%. |
| PC-E16 | P | Endless with a competent bot reaches wave 100+ at T3 with labs, and the death-spiral check passes. Every modifier run stays winnable to wave 25 with a mid save. |

### UI (view only; uitest and shots)
| AC | Gate | Criterion |
|---|---|---|
| PC-U1 | U | At 1920x1080 the top HUD, left panel, battlefield, right panel and hotbar exist with no overlapping rects. At 1280x720 and 1280x800 every control stays in the viewport, and resizing re-lays out the screen without errors. |
| PC-U2 | U | Every visible Button and interactive Control has a non-empty tooltip (tree walk), ACTION_MODE_BUTTON_PRESS, and height ≥ 40 px at scale 1. Overlays use MOUSE_FILTER_IGNORE. |
| PC-U3 | U | Simulated InputEventKey for every default hotkey in §1.3 triggers its action (pause toggles, 1 selects hotbar slot 1, U upgrades, X sells, Esc cancels). |
| PC-U4 | U | Simulated mouse drag from a hotbar slot to a valid cell places the building. A drag to a locked cell does not, and its ghost shows the reason. Right-click opens the info popover with Upgrade/Sell. Wheel over the battlefield changes the zoom within 0.8–1.4. |
| PC-U5 | U | Joypad events: the stick moves the grid cursor and A places. The focus chain reaches every button on Base, Settings and the draft with no dead ends. Glyphs switch on the device. |
| PC-U6 | U | The perk draft modal accepts 1/2/3. The death modal shows the breakdown, Back to Base and Retry seed. The slot picker shows 3 slots, and delete needs confirmation. |
| PC-U7 | U | The Stats, History (retry button) and Achievements screens render from engine data, and the counts match the save. |
| PC-U8 | X | Shots at 1920x1080: main menu, slot picker, base 7x7 (rings visible), run early, run late with 4-way telegraphs, drag ghost valid and invalid, tooltip, info popover, perk draft, death, stats, history, achievements, settings (4 tabs), remap capture, endless mutation pick, and modifier select. A human or the visual-audit lenses find no clipped text, overlaps or illegible contrast. |

### SHELL (Steam readiness; selftest, uitest, file checks)
| AC | Gate | Criterion |
|---|---|---|
| PC-S1 | S/U | The settings menu has the Video, Audio, Controls and Gameplay tabs from §6. Changing display mode, vsync, FPS cap and UI scale applies to DisplayServer/Engine (checked headless where possible) and persists across restart. The video-revert timer reverts unconfirmed changes. |
| PC-S2 | U | The remap UI captures a key, shows the glyph, swaps on conflict, and reset restores the defaults. Bindings persist in settings.cfg, not in a slot. |
| PC-S3 | file | `export_presets.cfg` holds valid Windows Desktop and Linux presets. `--export-release` with templates present produces binaries; this is optional in CI when templates are absent. The exclude filter drops test scripts. |
| PC-S4 | file | No Steam SDK binaries or steam_appid.txt are tracked, and .gitignore covers them. Boot with no GodotSteam gives 0 errors (`--quit-after 120`). |
| PC-S5 | S | Rich presence strings are set on Base, Run and Endless transitions (mock_log). The overlay-active hook pauses the run. |
| PC-S6 | file | third_party/README.md has rows for Maaack (#1), input_helper (#3), controller_icons code and Xelu glyphs (#4), godot-demo-projects (#5) and godot-ci (#6, if copied), with LICENSE files vendored next to the code. Only the key/mouse/xbox/ps5/steamdeck glyphs are vendored, and the Godot-logo plugin icon is not. The credits screen lists Xelu, Maaack, Nathan Hoad and the Godot demo contributors. |
| PC-S7 | all | Mobile games/towerdef-0001 is byte-unchanged by PC work (`git diff --stat` on it is empty). All PC gates pass: import, boot, SELFTEST OK, UITEST OK, PLAYTEST OK, and npm test green. |

### Suggested order
1. SHELL-0: fork, manifest, project.godot 1920x1080, then SteamService and Settings modules (PC-E11, E12).
2. ENGINE: 7x7 and cap (E1, E2), spawns (E5), buildings and synergy (E3), move (E4), save v3 and slots (E9), stats and history (E8), achievements (E10), modifiers and endless (E6, E7).
3. UI: the layout rewrite (U1, U2), input (U3–U5), screens (U6, U7), settings and remap (S1, S2).
4. Balance (E14–E16), then shots (U8), then exports, CI and credits (S3–S6), then final gates (S7).

### ENGINE implementation notes (as built)
- **Board:** `BaseMeta.SIDE=7`, `N=49`, `CORE_SLOT=24`; `cell_ring`, `is_corner`, `unlock_cost(s, i)`, `ring_open` (ring 3 needs T3), `build_cap`, `place_ok` (Railgun ring ≥ 2). `TowerState.can_place` / `at_cap()` gate placement and `Draft.offer(..., cap)` offers no NEW cards at the cap.
- **Land development (added):** every 4 outer cells bought raise every building's permanent level cap by 1 (`pc_land_cells=4`, max `pc_land_max=10`), so the 48-cell base stays a coin sink under the build cap.
- **Geometry:** the enemy stop ring is 200 px (it was 150) and the spawn ring is 470 px. All weapon ranges scale by `pc_range_scale = 200/150`, and weapons get +8% range per ring past ring 1 (`pc_ring_range`).
- **Refinery cap** tuned to 2.5 coins/lv/wave (`pc_refinery_cap`; spec said 5). At 5 the playtest PC-E14 probe earned 1.5x coins with Mines half-swapped for Refineries; at 2.5 it earns 0.97-1.06x and loses about 1-2 waves, so it is a real coin-for-waves trade.
- **Synergy tags** continue the mobile numbering (mobile S6/S7 are Bounty Hunters/Oil Shells): **S8** Capacitor Bank (Railgun+Tesla), **S9** Crossfire (Flak+Gun), **S10** Spotter (Beacon+Mortar), **S11** Smelter (Refinery+Mine). Crits exist only through Crossfire (`pc_crit_mult=2`), with one seeded roll per shot. Ironclad reduces non-crit hits.
- **Waves:** each wave is *planned* when it is telegraphed (`_build_plan`): its quadrants, then one entry `{t, kind, quad}` per spawn tick, round-robin over the quadrants. `wave_telegraph {wave, quadrants, counts{quad:n}, total, elites, boss_dir, lead}` fires `pc_telegraph_s` before `wave_start`. Wave 1 is telegraphed at t=0 and starts at t=3 s. Quadrants: 0 = N/NE, 1 = E/SE, 2 = S/SW, 3 = W/NW. `spawn_hold` is the test hook (it replaces the mobile `spawn_t = 999`).
- **Barricade** walls sit at `STOP_R+50` on the Barricade's lane (`cell_quad`). Enemies pressing on a wall are slowed 30% and wear it down with their contact damage. Events: `wall_up` (each wave), `wall_broken`.
- **Move:** `TowerState.move_building(a, b, paused)` (free while paused or when the field is clear; otherwise 10% of `building_value`) and `BaseMeta.try_move` (free). `cancel_place()` drops a pending card.
- **Modes:** `setup(seed, save, now, {mode, modifiers})`. Endless doesn't feed the tier ladder; it records `save.endless.best`. Mutations: `mutation_offer` / `choose_mutation`, +10% coins each.
- **Stats/history:** `Stats.on_event` is fed by `Missions.on_run_events` (one call from the view) plus BaseMeta/Labs `coins_spent`. `game_over` carries `seed, tier, mode, modifiers, mutations, duration_s, build, ts, dps`. `Stats.retry_opts(entry)` replays a history entry.
- **Slots:** `MetaSave.read_slot/write_slot/delete_slot(n, "DELETE")/copy_slot/slot_summary/set_active`. `read()/write()/clear()` act on the active slot. The legacy mobile `user://save.json` is imported into an empty slot 1.
