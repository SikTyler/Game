# HORDE BRIEF (owner's prompt, verbatim — source of truth for every horde phase)

My Godot 4.6 tower defense games/towerdef-pc-0001 (branch towerdef-0001) runs ~10–220 enemies. They are Dictionaries in TowerState.enemies, simulated in a deterministic, seeded, headless TowerState.tick() and drawn immediate-mode in ui/Battle.gd. I want a mass horde like Sir, We Have an Orc Problem. Thousands of enemies flow like liquid, jostle, get blasted back, and leave blood and corpses. The game must not break or become unbalanced at any step.

Phase 0 — Audit (change nothing). Confirm or correct my description above. For every system touching enemies (spawn plan, movement, _fire/_core_fire/specials, _hit/_reap, troops, walls, drops, missions/stats/achievements, Main._handle fx/sfx, Battle._draw_world), rate it untouched / adapt / rewrite. List every per-enemy balance value. Run selftest.gd, uitest.gd and playtest.gd and save the results as the baseline. Propose a plan and a realistic enemy-count target for PC. Stop.

Balance rule (applies to every phase). Add a single tunable horde_mult (default 1). The spawn plan emits horde_mult bodies per current enemy. Each body gets 1/horde_mult of HP, cash, xp, coin and contact damage, so per-wave totals are conserved. Bosses stay single bodies. At horde_mult = 1 the game must be bit-identical to today: selftest, uitest and all playtest gates pass with the same numbers. At every higher mult, report the playtest gate deltas against the baseline. If a gate fails, flag it. Don't retune silently. AoE vs single-target value will shift, so report it per weapon.

Architecture.

Move TowerState.enemies from Dicts to packed arrays (struct-of-arrays) with a free list. Keep eid as the stable external handle (eid→slot map) for the beam, troops and shock_src. Keep all logic in TowerState, seeded and fixed-substep. No nodes, no physics engine.
Add a uniform spatial hash (name it EnemyHash, not "grid"; the 7×7 build grid is separate), rebuilt each substep. Port pick_target, _nearest, splash, railgun, frost, tesla chains, _hit_carry, _densest (currently O(n²)), troops and cast_special to it. API: in_radius, nearest, damage, impulse, radial_impulse.
Movement and crowd: seek CENTER with accel and max speed, plus soft separation from hash neighbours in the same single pass, so enemies pile up around STOP_R. Only enemies actually touching STOP_R attack the core.
Knockback: hit impulse scaled by damage and weapon, radial impulse with falloff for mortar/explosions, friction, mass resists.
View only (Battle.gd, Main, vfx/): a MultiMesh per enemy kind using the current SVG icons, hit flash via per-instance colour, and HP bars only for elites and bosses. Gore uses pooled GPUParticles2D and corpse/blood stamped into a never-clearing SubViewport ground layer, with a gore setting of off / low / full in settings.cfg. Hit-stop and shake go through the existing Juice, capped.
Events: aggregate per-hit and per-kill events per substep (counts and sums) so _handle, damage numbers, sfx, Missions and Stats don't scale with body count. Mission, stat and achievement kill counts must still match.
Debug overlay toggle: body count, FPS, sim ms and hash ms, hash cells.
Phases (stop for my approval after each, with selftest/uitest/playtest results and a profile at 1k/5k/10k bodies):

SoA arrays + eid map + EnemyHash, all targeting ported. horde_mult = 1 must be identical to the baseline.
MultiMesh rendering + event aggregation + horde_mult, with no separation yet.
Separation and the contact-attack rule.
Knockback.
Gore + ground layer + gore setting.
Feedback polish + debug overlay.
Performance. The hot loop (move + separation) is one pass. If GDScript can't hold 60 fps at the target count, say so and propose moving only the hot loop to C# or a compute shader. Don't do that without asking. Keep all towers, upgrades, cores, troops, walls, perks, cards and UI working at every phase. Update selftest for the new schema rather than deleting assertions. If anything conflicts with this plan, flag it instead of rewriting.
