extends RefCounted
## HORDE Phase 1: struct-of-arrays enemy storage (pure, no Nodes).
## One slot per body in packed arrays; a free list recycles slots (O(1)
## alloc / release, no Dictionary churn) and a stable eid -> slot map serves
## beam locks, troop targets and view lookups. `order` holds the live slots
## in spawn order and is compacted exactly like the old `enemies` Array, so
## every rule loop ("for s in order") iterates bodies in the same order as
## the Dict implementation did -> bit-identical results.
## Floats are PackedFloat64Array (GDScript float is f64; f32 storage would
## change results). Positions were Vector2 (f32) already.

const F_MARKED: int = 1
const F_EXIT: int = 2

var pos: PackedVector2Array = PackedVector2Array()
var vel: PackedVector2Array = PackedVector2Array()     # knockback (Phase 4); unused at horde_mult 1
var exit: PackedVector2Array = PackedVector2Array()    # courier escape point (F_EXIT)
var hp: PackedFloat64Array = PackedFloat64Array()
var max_hp: PackedFloat64Array = PackedFloat64Array()
var spd: PackedFloat64Array = PackedFloat64Array()
var dmg: PackedFloat64Array = PackedFloat64Array()
var cash: PackedFloat64Array = PackedFloat64Array()
var xp: PackedFloat64Array = PackedFloat64Array()
var coin: PackedFloat64Array = PackedFloat64Array()
var size: PackedFloat64Array = PackedFloat64Array()
var atk_cd: PackedFloat64Array = PackedFloat64Array()
var slow_t: PackedFloat64Array = PackedFloat64Array()
var slow_m: PackedFloat64Array = PackedFloat64Array()
var fire_cd: PackedFloat64Array = PackedFloat64Array()
var shock_t: PackedFloat64Array = PackedFloat64Array()
var hit_t: PackedFloat64Array = PackedFloat64Array()
var taunt_t: PackedFloat64Array = PackedFloat64Array()
var kind: PackedStringArray = PackedStringArray()
var eid: PackedInt32Array = PackedInt32Array()
var shield: PackedInt32Array = PackedInt32Array()
var max_shield: PackedInt32Array = PackedInt32Array()
var shock_src: PackedInt32Array = PackedInt32Array()   # weapon SLOT index (not an eid)
var quad: PackedInt32Array = PackedInt32Array()
var shred_n: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var next_free: PackedInt32Array = PackedInt32Array()

var free_head: int = -1
var order: PackedInt32Array = PackedInt32Array()   # live slots, spawn order
var eid_slot: Dictionary = {}                      # eid -> slot
var max_size: float = 0.0                          # largest body ever stored (query padding)
var dirty: bool = true                             # positions / order changed since the hash rebuild


func capacity() -> int:
	return hp.size()


func count() -> int:
	return order.size()


func is_empty() -> bool:
	return order.is_empty()


func clear() -> void:
	pos.clear(); vel.clear(); exit.clear()
	hp.clear(); max_hp.clear(); spd.clear(); dmg.clear(); cash.clear(); xp.clear(); coin.clear()
	size.clear(); atk_cd.clear(); slow_t.clear(); slow_m.clear(); fire_cd.clear(); shock_t.clear()
	hit_t.clear(); taunt_t.clear(); kind.clear()
	eid.clear(); shield.clear(); max_shield.clear(); shock_src.clear(); quad.clear(); shred_n.clear()
	flags.clear(); next_free.clear()
	free_head = -1
	order.clear()
	eid_slot.clear()
	max_size = 0.0
	dirty = true


func _grow() -> void:
	var c: int = maxi(64, capacity() * 2)
	var old: int = capacity()
	pos.resize(c); vel.resize(c); exit.resize(c)
	hp.resize(c); max_hp.resize(c); spd.resize(c); dmg.resize(c); cash.resize(c); xp.resize(c); coin.resize(c)
	size.resize(c); atk_cd.resize(c); slow_t.resize(c); slow_m.resize(c); fire_cd.resize(c); shock_t.resize(c)
	hit_t.resize(c); taunt_t.resize(c); kind.resize(c)
	eid.resize(c); shield.resize(c); max_shield.resize(c); shock_src.resize(c); quad.resize(c); shred_n.resize(c)
	flags.resize(c); next_free.resize(c)
	# chain the new slots onto the free list, lowest index first
	for s in range(c - 1, old - 1, -1):
		next_free[s] = free_head
		free_head = s


## Pop a slot, reset it to spawn defaults, register eid, append to `order`.
func alloc(id: int, k: String, p: Vector2) -> int:
	if free_head < 0:
		_grow()
	var s: int = free_head
	free_head = next_free[s]
	next_free[s] = -1
	pos[s] = p; vel[s] = Vector2.ZERO; exit[s] = p
	hp[s] = 0.0; max_hp[s] = 0.0; spd[s] = 0.0; dmg[s] = 0.0; cash[s] = 0.0; xp[s] = 0.0; coin[s] = 0.0
	size[s] = 16.0; atk_cd[s] = 0.0; slow_t[s] = 0.0; slow_m[s] = 1.0; fire_cd[s] = 0.0; shock_t[s] = 0.0
	hit_t[s] = 0.0; taunt_t[s] = 0.0; kind[s] = k
	eid[s] = id; shield[s] = 0; max_shield[s] = 0; shock_src[s] = -1; quad[s] = -1; shred_n[s] = 0
	flags[s] = 0
	eid_slot[id] = s
	order.append(s)
	dirty = true
	return s


## Return a slot to the free list (the caller fixes `order`).
func release(s: int) -> void:
	if eid_slot.get(eid[s], -1) == s:
		eid_slot.erase(eid[s])
	flags[s] = 0
	next_free[s] = free_head
	free_head = s
	dirty = true


## Slot of a live (still stored) body, or -1.
func slot_of(id: int) -> int:
	return int(eid_slot.get(id, -1))


## Remove one slot from `order` (courier escape) and free it.
func remove(s: int) -> void:
	var k: int = order.find(s)
	if k >= 0:
		order.remove_at(k)
	release(s)


func set_size(s: int, v: float) -> void:
	size[s] = v
	max_size = maxf(max_size, v)


func is_marked(s: int) -> bool:
	return (flags[s] & F_MARKED) != 0


func has_exit(s: int) -> bool:
	return (flags[s] & F_EXIT) != 0


## Fill slot s from a legacy enemy Dictionary (selftest / tool injection).
## Missing keys take the defaults the Dict code's .get() fallbacks used.
func fill(s: int, d: Dictionary) -> void:
	pos[s] = d.get("pos", Vector2.ZERO)
	hp[s] = float(d.get("hp", 1.0))
	max_hp[s] = float(d.get("max_hp", hp[s]))
	spd[s] = float(d.get("spd", 0.0))
	dmg[s] = float(d.get("dmg", 0.0))
	cash[s] = float(d.get("cash", 0.0))
	xp[s] = float(d.get("xp", 0.0))
	coin[s] = float(d.get("coin", 0.0))
	set_size(s, float(d.get("size", 16.0)))
	atk_cd[s] = float(d.get("atk_cd", 0.0))
	slow_t[s] = float(d.get("slow_t", 0.0))
	# the Dict move code read .get("slow_m", 0.55) while slowed, 1.0 elsewhere
	slow_m[s] = float(d.get("slow_m", 0.55 if slow_t[s] > 0.0 else 1.0))
	fire_cd[s] = float(d.get("fire_cd", 0.0))
	shock_t[s] = float(d.get("shock_t", 0.0))
	hit_t[s] = float(d.get("hit_t", 0.0))
	taunt_t[s] = float(d.get("taunt_t", 0.0))
	kind[s] = String(d.get("kind", "drone"))
	shield[s] = int(d.get("shield", 0))
	max_shield[s] = int(d.get("max_shield", shield[s]))
	shock_src[s] = int(d.get("shock_src", -1))
	quad[s] = int(d.get("quad", -1))
	shred_n[s] = int(d.get("shred_n", 0))
	var f: int = 0
	if bool(d.get("marked", false)):
		f |= F_MARKED
	if d.has("exit"):
		f |= F_EXIT
		exit[s] = d["exit"]
	flags[s] = f
	dirty = true


## Debug / test / tool view of one body (a fresh copy, not a live reference).
func get_dict(s: int) -> Dictionary:
	var d: Dictionary = {
		"kind": kind[s], "pos": pos[s], "hp": hp[s], "max_hp": max_hp[s], "spd": spd[s], "dmg": dmg[s],
		"cash": cash[s], "xp": xp[s], "coin": coin[s], "size": size[s], "atk_cd": atk_cd[s],
		"slow_t": slow_t[s], "slow_m": slow_m[s], "shield": shield[s], "max_shield": max_shield[s],
		"fire_cd": fire_cd[s], "shock_t": shock_t[s], "shock_src": shock_src[s], "hit_t": hit_t[s],
		"eid": eid[s], "taunt_t": taunt_t[s], "quad": quad[s], "shred_n": shred_n[s],
		"marked": is_marked(s), "slot": s,
	}
	if has_exit(s):
		d["exit"] = exit[s]
	return d


func to_dicts() -> Array:
	var out: Array = []
	for s in order:
		out.append(get_dict(s))
	return out
