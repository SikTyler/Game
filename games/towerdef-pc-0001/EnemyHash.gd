extends RefCounted
## HORDE Phase 1: uniform spatial hash over EnemyStore (pure, no Nodes).
## 32 px cells over CENTER +- 512 (bodies outside clamp into the edge cells,
## so no body is ever missed). Rebuilt lazily by counting sort whenever the
## store is dirty (moves, knock, spawn, reap) -> queries always see current
## positions. Cells store spawn-order RANKS, so a query's candidates come back
## in `order` (spawn) order and callers that keep the Dict code's exact
## predicate and tie operators reproduce the linear scan's result bit-for-bit.
## Candidates are a superset (AABB of the query); callers apply the exact test.

const CS: float = 32.0
const HALF: float = 512.0

var st = null                     # EnemyStore
var ox: float = 0.0
var oy: float = 0.0
var gw: int = 32
var cell_start: PackedInt32Array = PackedInt32Array()   # gw*gw + 1
var items: PackedInt32Array = PackedInt32Array()        # ranks bucketed by cell
var cell_of: PackedInt32Array = PackedInt32Array()      # per rank
var rebuilds: int = 0


func _init(store, center: Vector2) -> void:
	st = store
	ox = center.x - HALF
	oy = center.y - HALF
	gw = int(ceil(2.0 * HALF / CS))
	cell_start.resize(gw * gw + 1)


func _cx(x: float) -> int:
	return clampi(int(floor((x - ox) / CS)), 0, gw - 1)


func _cy(y: float) -> int:
	return clampi(int(floor((y - oy) / CS)), 0, gw - 1)


func ensure() -> void:
	if st.dirty:
		rebuild()


## Counting sort of every stored body (rank order) into its cell.
func rebuild() -> void:
	rebuilds += 1
	var order: PackedInt32Array = st.order
	var pos: PackedVector2Array = st.pos
	var n: int = order.size()
	var nc: int = gw * gw
	cell_start.fill(0)
	cell_of.resize(n)
	items.resize(n)
	for r in n:
		var p: Vector2 = pos[order[r]]
		var c: int = _cy(p.y) * gw + _cx(p.x)
		cell_of[r] = c
		cell_start[c + 1] += 1
	for c in nc:
		cell_start[c + 1] += cell_start[c]
	var fillp: PackedInt32Array = cell_start.duplicate()
	for r in n:
		var c2: int = cell_of[r]
		items[fillp[c2]] = r
		fillp[c2] += 1
	st.dirty = false


## Slots of every body whose position lies in the AABB [a, b] (spawn order).
func rect(a: Vector2, b: Vector2) -> PackedInt32Array:
	ensure()
	var x0: int = _cx(minf(a.x, b.x))
	var x1: int = _cx(maxf(a.x, b.x))
	var y0: int = _cy(minf(a.y, b.y))
	var y1: int = _cy(maxf(a.y, b.y))
	var order: PackedInt32Array = st.order
	if (x1 - x0 + 1) * (y1 - y0 + 1) * 2 >= gw * gw:
		return order.duplicate()   # most of the field: the whole order is the superset
	var ranks: PackedInt32Array = PackedInt32Array()
	var cells: int = 0
	for cy in range(y0, y1 + 1):
		var row: int = cy * gw
		for cx in range(x0, x1 + 1):
			var c: int = row + cx
			var e: int = cell_start[c + 1]
			var b0: int = cell_start[c]
			if e > b0:
				cells += 1
				for k in range(b0, e):
					ranks.append(items[k])
	if cells > 1:
		ranks.sort()
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(ranks.size())
	for k in ranks.size():
		out[k] = order[ranks[k]]
	return out


## Candidate slots (spawn order) for anything within r of c (+1 px slack).
func candidates(c: Vector2, r: float) -> PackedInt32Array:
	var rr: float = r + 1.0
	return rect(c - Vector2(rr, rr), c + Vector2(rr, rr))


## Living bodies with |pos - c| <= r (+ size/2 when pad_size), spawn order.
func in_radius(c: Vector2, r: float, pad_size: bool = false) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var hp: PackedFloat64Array = st.hp
	var pos: PackedVector2Array = st.pos
	var sz: PackedFloat64Array = st.size
	for s in candidates(c, r + (st.max_size * 0.5 if pad_size else 0.0)):
		if hp[s] <= 0.0:
			continue
		if pos[s].distance_to(c) <= r + (sz[s] * 0.5 if pad_size else 0.0):
			out.append(s)
	return out


## The Dict `_nearest`: living body with the smallest d^2 <= r^2 (ties: the
## later one in spawn order, `<=`), skipping slots in `exclude`. -1 if none.
func nearest(from: Vector2, rng_lim: float, exclude: Dictionary) -> int:
	var best: int = -1
	var best_d: float = rng_lim * rng_lim
	var hp: PackedFloat64Array = st.hp
	var pos: PackedVector2Array = st.pos
	for s in candidates(from, rng_lim):
		if exclude.has(s):
			continue
		if hp[s] <= 0.0:
			continue
		var d2: float = from.distance_squared_to(pos[s])
		if d2 <= best_d:
			best_d = d2
			best = s
	return best


## Number of living bodies within distance r of p (exact; `_densest`).
func density(p: Vector2, r: float) -> int:
	var n: int = 0
	var hp: PackedFloat64Array = st.hp
	var pos: PackedVector2Array = st.pos
	for s in candidates(p, r):
		if hp[s] > 0.0 and p.distance_to(pos[s]) <= r:
			n += 1
	return n


## Apply `hit.call(slot, amt)` to every living body within r of c (spawn
## order). Returns the slots hit.
func damage(c: Vector2, r: float, amt: float, hit: Callable, pad_size: bool = false) -> PackedInt32Array:
	var got: PackedInt32Array = in_radius(c, r, pad_size)
	for s in got:
		hit.call(s, amt)
	return got


## Knockback velocity (Phase 4). Off at horde_mult 1 (nothing calls it yet).
func impulse(s: int, v: Vector2) -> void:
	st.vel[s] = st.vel[s] + v


## Radial impulse with linear falloff from c (Phase 4; unused at horde_mult 1).
func radial_impulse(c: Vector2, r: float, k: float) -> void:
	for s in in_radius(c, r):
		var d: Vector2 = st.pos[s] - c
		var l: float = d.length()
		if l > 0.0:
			impulse(s, d / l * k * (1.0 - l / r))
