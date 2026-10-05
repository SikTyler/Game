extends RefCounted
## MASS_HORDE §5: thin GDScript facade over the C# HordeWorld query API
## (HordeWorld.cs keeps its own uniform hash, rebuilt lazily after a step,
## spawn or death). Results hold LIVING bodies only (hp > 0: the rules mark a
## death with EnemyStore.kill), in ascending SLOT order. The old GDScript
## (cell, spawn-rank) sorted-key hash is retired: candidates come back in slot
## order instead of spawn order (deterministic either way; the determinism
## golden was re-recorded, see selftest HORDE_FP_GOLDEN).

var st = null                     # EnemyStore
var rebuilds: int = 0
var last_us: int = 0              # view-only profile (debug overlay): last C# step


func _init(store, _center: Vector2 = Vector2.ZERO) -> void:
	st = store


func _w() -> Object:
	return st.world


## Kept for callers/tests that forced a rebuild: the C# hash is always current.
func ensure() -> void:
	pass


func rebuild() -> void:
	rebuilds += 1
	last_us = int((_w().call("Stats") as Dictionary).get("step_us", 0))


## Debug overlay: living bodies (the C# hash has no cheap occupied-cell count).
func cell_count() -> int:
	return int(_w().call("Alive"))


## Living bodies whose position lies in the AABB [a, b].
func rect(a: Vector2, b: Vector2) -> PackedInt32Array:
	return _w().call("InRect", a.x, a.y, b.x, b.y)


## Candidate slots for anything within r of c: centre within r + own radius
## (a superset of every caller's exact predicate).
func candidates(c: Vector2, r: float) -> PackedInt32Array:
	return _w().call("Candidates", c.x, c.y, r)


## Living bodies with |pos - c| <= r (+ size/2 when pad_size).
func in_radius(c: Vector2, r: float, pad_size: bool = false) -> PackedInt32Array:
	return _w().call("InRadius", c.x, c.y, r, pad_size)


## Living bodies within `width` (+ size/2) of the segment a-b.
func line(a: Vector2, b: Vector2, width: float) -> PackedInt32Array:
	return _w().call("InLine", a.x, a.y, b.x, b.y, width)


## Living bodies in a cone from `apex` along unit `dir`, half angle (rad), range.
func cone(apex: Vector2, dir: Vector2, half_angle: float, rng: float) -> PackedInt32Array:
	return _w().call("InCone", apex.x, apex.y, dir.x, dir.y, cos(half_angle), rng)


## Living body with the smallest d^2 <= r^2 (ties: the higher slot, `<=`),
## skipping slots in `exclude`. -1 if none.
func nearest(from: Vector2, rng_lim: float, exclude: Dictionary) -> int:
	return int(_w().call("Nearest", from.x, from.y, rng_lim, PackedInt32Array(exclude.keys())))


## Up to n nearest living bodies within r (nearest first).
func nearest_n(from: Vector2, n: int, r: float) -> PackedInt32Array:
	return _w().call("NearestN", from.x, from.y, n, r)


## Number of living bodies within distance r of p (exact).
func density(p: Vector2, r: float) -> int:
	return int(_w().call("Density", p.x, p.y, r))


## Position of the living body with the most neighbours within r (ties: the
## closest to the Core). Vector2.INF when the field is empty.
func densest(r: float) -> Vector2:
	return _w().call("Densest", r)


## Tesla-style hop list from slot `start` (nearest unvisited within jump_r).
func chain(start: int, jumps: int, jump_r: float) -> PackedInt32Array:
	return _w().call("Chain", start, jumps, jump_r)


## Apply `hit.call(slot, amt)` to every living body within r of c (slot
## order). Returns the slots hit.
func damage(c: Vector2, r: float, amt: float, hit: Callable, pad_size: bool = false) -> PackedInt32Array:
	var got: PackedInt32Array = in_radius(c, r, pad_size)
	for s in got:
		hit.call(s, amt)
	return got


## Knockback velocity on one body (mass rule in EnemyStore.knock).
func impulse(s: int, v: Vector2) -> void:
	st.knock(s, v)


## Radial impulse with falloff from c (C#). Returns the bodies pushed.
func radial_impulse(c: Vector2, r: float, k: float) -> int:
	return st.radial_knock(c, r, k)
