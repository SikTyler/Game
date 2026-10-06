# TODO status (polish-leftovers pass)

1. Lane logic in Lane Beacon / Barricade / Rifle Barracks: none left. Data text is omnidirectional ("every direction", "any side", "whole perimeter"); engine uses radius auras (beacon adjacency, `_wall_auras`) and Core-anchored rifle seek/leash. Stale "lane" comments in Troops.gd / selftest labels updated.
2. Gore ground layer: periodic fade (vfx/Gore.gd, MUL-blend rect every 3 s x0.97, half-life ~70 s). 8-bit floor leaves a faint (<~7% alpha) residue by design.
3. Per-body colour effects now stack in HordeWorld.RenderPrep: density shade -> slow tint (fades over last 0.3 s) -> surge flare -> hit flash.
4. Intel.roster now uses HordeWorld.KindSummary (one C# pass; max hp passed via SetVis). GDScript only walks the queued plan.
5. _shots: early horde stage clears bodies, orbitals, C# corpse ring and the ground layer first. The early shot still shows pools from the 300-body stage itself plus live wave spawns (wave 22 keeps flowing); acceptable, not tuned further.
6. Leftovers: no horde_mult UI/text exists (legacy knob is engine/test only, default 1, asserted). No stale lane/seed/wall tooltip text found.
