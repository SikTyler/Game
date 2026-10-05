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
## move() action log opcodes: [op, arg] pairs (ACT_BLD: [op, slot, cell]),
## replayed in order by TowerState.
const ACT_BLD: int = 0       # arg = slot of a body hitting the building on `cell`
const ACT_SHOT: int = 1      # arg = slot of a ranged body firing at the Core
const ACT_HIT: int = 2       # arg = slot of a melee body hitting the Core
const ACT_ESCAPE: int = 3    # arg = slot of a courier that reached its exit

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
var share: PackedFloat64Array = PackedFloat64Array()   # horde body share 1/m (1.0 = whole entry)
var kind: PackedStringArray = PackedStringArray()
var kc: PackedInt32Array = PackedInt32Array()          # kind code for the C# hot loop: 0 other, 1 courier, 2 ranged
var eid: PackedInt32Array = PackedInt32Array()
var shield: PackedInt32Array = PackedInt32Array()
var max_shield: PackedInt32Array = PackedInt32Array()
var shock_src: PackedInt32Array = PackedInt32Array()   # weapon SLOT index (not an eid)
var quad: PackedInt32Array = PackedInt32Array()
var shred_n: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var next_free: PackedInt32Array = PackedInt32Array()
var cur_s: PackedFloat64Array = PackedFloat64Array()   # Phase 3: current seek speed (accelerates to spd)
# Phase 3 separation grid (rebuilt inside move(), old positions = Jacobi read)
const SEP_CS: float = 32.0
const SEP_GW: int = 96   # 3072 px: covers the max spawn radius (bodies outside skip separation)
var _head: PackedInt32Array = PackedInt32Array()
var _link: PackedInt32Array = PackedInt32Array()

var free_head: int = -1
var order: PackedInt32Array = PackedInt32Array()   # live slots, spawn order
var eid_slot: Dictionary = {}                      # eid -> slot
var max_size: float = 0.0                          # largest body ever stored (query padding)
var dirty: bool = true                             # positions / order changed since the hash rebuild


static func _kcode(k: String) -> int:
	return 1 if k == "courier" else (2 if k == "ranged" else 0)


## C# hot loop (HordeMove.cs). `cs_mode`: -1 = Tune "horde_cs" (default 1 = C#
## when the mono build is present), 0 = force GDScript, 1 = force C#. The
## GDScript move() body below is the reference/fallback; both paths are
## bit-identical (selftest compares the 120 s fingerprint).
const TuneR := preload("res://Tune.gd")
static var cs_mode: int = -1
static var _cs: Object = null
static var _cs_tried: bool = false


static func cs_available() -> bool:
	if not _cs_tried:
		_cs_tried = true
		if ResourceLoader.exists("res://HordeMove.cs"):
			var scr = load("res://HordeMove.cs")
			if scr is Script and (scr as Script).can_instantiate():
				_cs = scr.new()
	return _cs != null


static func use_cs() -> bool:
	var m: int = cs_mode if cs_mode >= 0 else int(TuneR.int_of("horde_cs", 1))
	return m == 1 and cs_available()


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
	hit_t.clear(); taunt_t.clear(); share.clear(); kind.clear(); kc.clear()
	eid.clear(); shield.clear(); max_shield.clear(); shock_src.clear(); quad.clear(); shred_n.clear()
	flags.clear(); next_free.clear(); cur_s.clear()
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
	hit_t.resize(c); taunt_t.resize(c); share.resize(c); kind.resize(c); kc.resize(c)
	eid.resize(c); shield.resize(c); max_shield.resize(c); shock_src.resize(c); quad.resize(c); shred_n.resize(c)
	flags.resize(c); next_free.resize(c); cur_s.resize(c)
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
	hit_t[s] = 0.0; taunt_t[s] = 0.0; share[s] = 1.0; kind[s] = k; kc[s] = _kcode(k)
	eid[s] = id; shield[s] = 0; max_shield[s] = 0; shock_src[s] = -1; quad[s] = -1; shred_n[s] = 0
	flags[s] = 0; cur_s[s] = 0.0
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


## Knockback impulse (Phase 4): v / mass, mass = (size/16)^2. Bosses and
## couriers are immune (today's pulse rule).
func knock(s: int, v: Vector2) -> void:
	var k: String = kind[s]
	if k == "boss" or k == "courier":
		return
	var m: float = size[s] / 16.0
	vel[s] = vel[s] + v / maxf(0.25, m * m)
	dirty = true


## Radial impulse with linear falloff (mortar / pulse / specials).
func radial_knock(c: Vector2, r: float, k: float) -> void:
	if r <= 0.0 or k == 0.0:
		return
	for s in order:
		if hp[s] <= 0.0:
			continue
		var d: Vector2 = pos[s] - c
		var l: float = d.length()
		if l > 0.0 and l <= r:
			knock(s, d / l * k * (1.0 - 0.5 * l / r))


## The per-substep hot pass, ONE loop in spawn order (HORDE Phase 3+4):
## timers, courier run, taunt pin, seek the Core with acceleration up to the
## max speed, soft separation from grid neighbours (Jacobi: reads the
## positions as they were at substep start, weighted by mass so heavy bodies
## shove light ones), knockback velocity with exponential friction, the Core
## stop ring as a hard wall, and the contact rule: only a body actually
## touching a building (leading edge in a standing building's cell) or the
## Core ring (|p-C| <= stop + size/2) attacks. Effects are an ordered action
## log replayed by TowerState. `prm` = [accel_k, sep_k, sep_cap, friction].
func move(dt: float, frozen: bool, center: Vector2, stop_r: float, r_stop: float, r_fire: float, blk: PackedByteArray, side: int, cell: float, prm: PackedFloat64Array = PackedFloat64Array([6.0, 0.5, 0.35, 6.0])) -> PackedInt32Array:
	if use_cs():
		return _move_cs(dt, frozen, center, stop_r, r_stop, r_fire, blk, side, cell, prm)
	var acts: PackedInt32Array = PackedInt32Array()
	var has_b: bool = not blk.is_empty()
	var half: int = side / 2
	var accel_k: float = prm[0]
	var sep_k: float = prm[1]
	var sep_cap: float = prm[2]
	var fr: float = exp(-prm[3] * dt)
	# --- separation grid over the old positions (linked cell lists)
	var old: PackedVector2Array = pos.duplicate()
	var gw: int = SEP_GW
	var ox: float = center.x - SEP_CS * gw * 0.5
	var oy: float = center.y - SEP_CS * gw * 0.5
	var do_sep: bool = sep_k > 0.0 and order.size() > 1 and not frozen
	var reach: int = 1   # 3x3 cells; bigger bodies under-push slightly (they are heavy anyway)
	var kmax: int = int(prm[4]) if prm.size() > 4 else 12   # candidates scanned per body (cap) (spawn-order deterministic)
	if do_sep:
		if _head.size() != gw * gw:
			_head.resize(gw * gw)
		_head.fill(-1)
		if _link.size() < capacity():
			_link.resize(capacity())
		for ri in range(order.size() - 1, -1, -1):
			var q: int = order[ri]
			var qp: Vector2 = old[q]
			var gx: int = int(floor((qp.x - ox) / SEP_CS))
			var gy: int = int(floor((qp.y - oy) / SEP_CS))
			if gx < 0 or gy < 0 or gx >= gw or gy >= gw:
				continue   # off-grid bodies (far out) neither push nor get pushed
			var ci: int = gy * gw + gx
			_link[q] = _head[ci]
			_head[ci] = q
	for e in order:
		var p: Vector2 = old[e]
		var st: float = slow_t[e]
		var mult: float = slow_m[e] if st > 0.0 else 1.0
		var st2: float = maxf(0.0, st - dt)
		slow_t[e] = st2
		if st2 <= 0.0:
			slow_m[e] = 1.0
		shock_t[e] = maxf(0.0, shock_t[e] - dt)
		hit_t[e] = maxf(0.0, hit_t[e] - dt)
		if frozen:
			continue
		var k: String = kind[e]
		if k == "courier":
			var to2: Vector2 = exit[e] if (flags[e] & F_EXIT) != 0 else p
			var dd: Vector2 = to2 - p
			var stp: float = spd[e] * mult * dt
			if dd.length() <= stp:
				acts.append(ACT_ESCAPE)
				acts.append(e)
			else:
				pos[e] = p + dd.normalized() * stp
			continue
		var taunt: float = taunt_t[e]
		var pinned: bool = taunt > 0.0
		if pinned:
			taunt_t[e] = maxf(0.0, taunt - dt)   # pinned by a Rifleman (hitting the troop)
		var ranged: bool = k == "ranged"
		var stop: float = r_stop if ranged else stop_r
		var to_c: Vector2 = center - p
		var dist: float = to_c.length()
		var mv: Vector2 = Vector2.ZERO
		var bc: int = -1
		if not pinned and dist > stop + 0.001:
			var dir: Vector2 = to_c / dist
			if has_b:
				var ahead: Vector2 = p + dir * (size[e] * 0.5 + 2.0) - center
				var col: int = int(floor(ahead.x / cell + 0.5)) + half
				var row: int = int(floor(ahead.y / cell + 0.5)) + half
				if col >= 0 and col < side and row >= 0 and row < side and blk[row * side + col] == 1:
					bc = row * side + col
			if bc >= 0:
				cur_s[e] = 0.0
				atk_cd[e] = atk_cd[e] - dt
				if atk_cd[e] <= 0.0:
					atk_cd[e] = r_fire if ranged else 1.0
					acts.append(ACT_BLD)
					acts.append(e)
					acts.append(bc)
			else:
				var vmax: float = spd[e] * mult
				var cs: float = minf(vmax, cur_s[e] + vmax * accel_k * dt)
				cur_s[e] = cs
				mv = dir * minf(dist - stop, cs * dt)
		else:
			cur_s[e] = 0.0
		# soft separation (mass-weighted, capped per substep)
		if do_sep:
			var push: Vector2 = Vector2.ZERO
			var seen: int = 0
			var si: float = size[e]
			var mi: float = si * si
			var cx: int = int(floor((p.x - ox) / SEP_CS))
			var cy: int = int(floor((p.y - oy) / SEP_CS))
			for yy in range(maxi(0, cy - reach), mini(gw - 1, cy + reach) + 1):
				for xx in range(maxi(0, cx - reach), mini(gw - 1, cx + reach) + 1):
					var j: int = _head[yy * gw + xx]
					while j >= 0 and seen < kmax:
						seen += 1
						if j != e:
							var dv: Vector2 = p - old[j]
							var sj: float = size[j]
							var rr: float = (si + sj) * 0.5
							var d2: float = dv.length_squared()
							if d2 < rr * rr:
								var l: float = sqrt(d2)
								var w: float = sj * sj / (mi + sj * sj)
								if l > 0.0001:
									push += dv / l * ((rr - l) * w)
								else:
									# exact overlap: split by slot parity (deterministic)
									push += Vector2(1.0 if e > j else -1.0, 0.0) * (rr * w)
						j = _link[j]
			if push != Vector2.ZERO:
				push *= sep_k
				var cap: float = si * sep_cap
				var pl: float = push.length()
				if pl > cap:
					push *= cap / pl
				mv += push
		# knockback velocity + friction
		var kv: Vector2 = vel[e]
		if kv != Vector2.ZERO:
			mv += kv * dt
			kv *= fr
			if kv.length_squared() < 0.01:
				kv = Vector2.ZERO
			vel[e] = kv
		var np: Vector2 = p + mv
		var rel: Vector2 = np - center
		var nd: float = rel.length()
		if nd < stop and nd > 0.0:
			np = center + rel / nd * stop   # the stop ring is a wall
			nd = stop
		pos[e] = np
		if pinned or bc >= 0:
			continue
		# contact rule: only the touching rank attacks
		if nd > stop + size[e] * 0.5 + 0.5:
			continue
		if ranged:
			fire_cd[e] = fire_cd[e] - dt
			if fire_cd[e] <= 0.0:
				fire_cd[e] = fire_cd[e] + r_fire
				acts.append(ACT_SHOT)
				acts.append(e)
		else:
			atk_cd[e] = atk_cd[e] - dt
			if atk_cd[e] <= 0.0:
				atk_cd[e] = 1.0
				acts.append(ACT_HIT)
				acts.append(e)
	dirty = true
	return acts


func _move_cs(dt: float, frozen: bool, center: Vector2, stop_r: float, r_stop: float, r_fire: float, blk: PackedByteArray, side: int, cell: float, prm: PackedFloat64Array) -> PackedInt32Array:
	var kmax: float = prm[4] if prm.size() > 4 else 12.0
	var sc: PackedFloat64Array = PackedFloat64Array([dt, 1.0 if frozen else 0.0, center.x, center.y, stop_r, r_stop, r_fire, float(side), cell, prm[0], prm[1], prm[2], exp(-prm[3] * dt), kmax])
	var r: Array = _cs.call("Move", order, pos, vel, exit, spd, size, kc, flags, slow_t, slow_m, shock_t, hit_t, taunt_t, cur_s, atk_cd, fire_cd, blk, sc)
	pos = r[0]; vel = r[1]; slow_t = r[2]; slow_m = r[3]; shock_t = r[4]; hit_t = r[5]
	taunt_t = r[6]; cur_s = r[7]; atk_cd = r[8]; fire_cd = r[9]
	dirty = true
	return r[10]


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
	share[s] = float(d.get("share", 1.0))
	slow_t[s] = float(d.get("slow_t", 0.0))
	# the Dict move code read .get("slow_m", 0.55) while slowed, 1.0 elsewhere
	slow_m[s] = float(d.get("slow_m", 0.55 if slow_t[s] > 0.0 else 1.0))
	fire_cd[s] = float(d.get("fire_cd", 0.0))
	shock_t[s] = float(d.get("shock_t", 0.0))
	hit_t[s] = float(d.get("hit_t", 0.0))
	taunt_t[s] = float(d.get("taunt_t", 0.0))
	kind[s] = String(d.get("kind", "drone"))
	kc[s] = _kcode(kind[s])
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
		"marked": is_marked(s), "slot": s, "share": share[s],
	}
	if has_exit(s):
		d["exit"] = exit[s]
	return d


func to_dicts() -> Array:
	var out: Array = []
	for s in order:
		out.append(get_dict(s))
	return out
