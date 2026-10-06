# Owner feedback #3 (verbatim) — overrides the horde_mult "split" approach

> Enemies need to come in waves of 100s and then 1000s and then 10,000s. 4x has too few, it needs a liquid type physics based mass hoard enemy system similar to Sir, We have an Orc Problem. I dont like that we're just splitting one enemy into 8 and calling it a day. This doesnt feel like a genuine attempt at low HP hoard attack.

## What this means (binding for the mass-horde redesign)
- REJECTED: horde_mult splitting (one designed enemy → N fractional bodies). Keep it only as a legacy/test knob, off.
- REQUIRED: genuine horde units — enemy types DESIGNED as low-HP swarm bodies (cheap, numerous, weak individually, lethal en masse), plus heavier units, elites and bosses mixed in.
- Wave scale progression: early waves hundreds of bodies → mid-game thousands → late/tier waves tens of thousands (10,000+ alive).
- Liquid, physics-based crowd: flow toward the core around obstacles (flow field), pressure/separation so the mass behaves like a fluid (fills gaps, piles up, surges, splashes back under knockback), knockback/explosions part the sea, corpses/blood.
- Weapons, economy, loot, kill counts, missions, achievements and balance must be designed for these numbers (not scaled-down copies of single-enemy values).
- Performance: 10,000+ bodies at 60 fps on PC (owner's RTX 5080) — simulation in C# with arrays resident on the C# side, rendering via MultiMesh buffers written in bulk (or GPU compute if needed — propose before doing).
