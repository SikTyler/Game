extends RefCounted
## MASS_HORDE: rules-side store over the C#-resident HordeWorld (HordeWorld.cs).
## Kinematics + status timers live in C# (`world`); this script owns slot
## allocation and the rules data (hp, cash, shields, kinds). Every body is
## pushed once with commit(s); status writes go through the setters below
## (apply_slow / flash / set_shock / set_taunt / knock), which update the C#
## state and the GDScript mirror. move() runs one HordeWorld.Step and pulls a
## single packed mirror (pos, vel, timers) for the rules and the view to read:
## nothing is copied INTO C# per step. The GDScript move path and the
## HordeMove.cs float32 parity port are retired (MASS_HORDE §11).
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
const ACT_BOOM: int = 4      # [op, slot, cell]: a Sapper detonated on the building on `cell`
const F_LEAK: int = 4        # MASS_HORDE §D5: reached the Core (forfeits its pool share)
const F_FROST: int = 8       # chilled by a Cryo Spire (freeze-shatter / Brittle)
const F_BOOM: int = 16       # Sapper that detonated (reaped without a kill / reward)

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
var kc: PackedInt32Array = PackedInt32Array()          # kind code for HordeWorld: 0 other, 1 courier, 2 ranged, 3 boss, 4 sapper
var wv: PackedInt32Array = PackedInt32Array()          # MASS_HORDE: wave the body belongs to (pool accounting)
var wt: PackedInt32Array = PackedInt32Array()          # bodies this one stands for (1; >1 only under the test-harness LOD)
var guard: PackedFloat64Array = PackedFloat64Array()   # Shieldbearer frontal shield points
var burn_t: PackedFloat64Array = PackedFloat64Array()  # Flamer burn seconds left
var burn_d: PackedFloat64Array = PackedFloat64Array()  # Flamer burn damage per second
var eid: PackedInt32Array = PackedInt32Array()
var shield: PackedInt32Array = PackedInt32Array()
var max_shield: PackedInt32Array = PackedInt32Array()
var shock_src: PackedInt32Array = PackedInt32Array()   # weapon SLOT index (not an eid)
var quad: PackedInt32Array = PackedInt32Array()
var shred_n: PackedInt32Array = PackedInt32Array()
var flags: PackedInt32Array = PackedInt32Array()
var next_free: PackedInt32Array = PackedInt32Array()
var cur_s: PackedFloat64Array = PackedFloat64Array()   # Phase 3: current seek speed (accelerates to spd)
var free_head: int = -1
var order: PackedInt32Array = PackedInt32Array()   # live slots, spawn order
var eid_slot: Dictionary = {}                      # eid -> slot
var max_size: float = 0.0                          # largest body ever stored (query padding)
var dirty: bool = true                             # positions / order changed since the hash rebuild


static func _kcode(k: String) -> int:
	match k:
		"courier":
			return 1
		"ranged":
			return 2
		"boss":
			return 3
		"sapper":
			return 4
	return 0


## C# HordeWorld (mono build required: the mass horde is C#-only).
var world: Object = null
## Last step's building contact damage (per building slot), from HordeWorld.
var bld_dmg: PackedFloat64Array = PackedFloat64Array()


func _init() -> void:
	var scr = load("res://HordeWorld.cs")
	assert(scr is Script and (scr as Script).can_instantiate(), "HordeWorld.cs needs the mono build")
	world = scr.new()


static func cs_available() -> bool:
	if not ResourceLoader.exists("res://HordeWorld.cs"):
		return false
	var scr = load("res://HordeWorld.cs")
	return scr is Script and (scr as Script).can_instantiate()


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
	wv.clear(); wt.clear(); guard.clear(); burn_t.clear(); burn_d.clear()
	eid.clear(); shield.clear(); max_shield.clear(); shock_src.clear(); quad.clear(); shred_n.clear()
	flags.clear(); next_free.clear(); cur_s.clear()
	world.call("Clear")
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
	wv.resize(c); wt.resize(c); guard.resize(c); burn_t.resize(c); burn_d.resize(c)
	eid.resize(c); shield.resize(c); max_shield.resize(c); shock_src.resize(c); quad.resize(c); shred_n.resize(c)
	flags.resize(c); next_free.resize(c); cur_s.resize(c)
	world.call("Ensure", c)
	# chain the new slots onto the free list, lowest index first
	for s in range(c - 1, old - 1, -1):
		next_free[s] = free_head
		free_head = s


## Pop a slot, reset it to spawn defaults, register eid, append to `order`.
## The caller sets the rules fields and then calls commit(s) (fill() does).
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
	wv[s] = 0; wt[s] = 1; guard[s] = 0.0; burn_t[s] = 0.0; burn_d[s] = 0.0
	eid_slot[id] = s
	order.append(s)
	dirty = true
	return s


## Return a slot to the free list (the caller fixes `order`).
func release(s: int) -> void:
	if eid_slot.get(eid[s], -1) == s:
		eid_slot.erase(eid[s])
	flags[s] = 0
	world.call("Remove", s)
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


## Push slot s (all fields) into the C# world. Call after alloc + field
## writes, and after any bulk edit of a body (fill / set_enemy).
func commit(s: int) -> void:
	var p: Vector2 = pos[s]
	var v: Vector2 = vel[s]
	var x: Vector2 = exit[s]
	world.call("Put", s, kc[s], flags[s], PackedFloat64Array([p.x, p.y, size[s], spd[s], dmg[s], x.x, x.y, atk_cd[s], fire_cd[s], slow_t[s], slow_m[s], shock_t[s], hit_t[s], taunt_t[s], cur_s[s], v.x, v.y, hp[s]]))
	dirty = true


## hp crossed 0 (rules killed it): C# stops moving / querying it; _reap frees it.
func kill(s: int) -> void:
	world.call("MarkDead", s)


## Status writes (rules -> C# + mirror). apply_slow keeps the rules' merge:
## duration = max, multiplier = min while slowed.
func apply_slow(s: int, t: float, m: float) -> void:
	slow_t[s] = maxf(slow_t[s], t)
	slow_m[s] = minf(slow_m[s] if slow_t[s] > 0.0 else 1.0, m)
	world.call("SetSlow", s, slow_t[s], slow_m[s])


func flash(s: int, t: float) -> void:
	hit_t[s] = t
	world.call("SetHit", s, t)


func set_shock(s: int, t: float) -> void:
	shock_t[s] = t
	world.call("SetShock", s, t)


func set_taunt(s: int, t: float) -> void:
	taunt_t[s] = t
	world.call("SetTaunt", s, t)


func set_exit(s: int, to: Vector2) -> void:
	exit[s] = to
	flags[s] = flags[s] | F_EXIT
	commit(s)


## Knockback impulse (Phase 4): v / mass, mass = (size/16)^2. Bosses and
## couriers are immune (today's pulse rule).
func knock(s: int, v: Vector2) -> void:
	var k: String = kind[s]
	if k == "boss" or k == "courier":
		return
	var m: float = size[s] / 16.0
	vel[s] = vel[s] + v / maxf(0.25, m * m)
	world.call("SetVel", s, vel[s].x, vel[s].y)
	dirty = true


## Radial impulse with linear falloff (mortar / pulse / specials), in C#.
## Returns the number of bodies pushed (the vel mirror refreshes next step).
func radial_knock(c: Vector2, r: float, k: float) -> int:
	if r <= 0.0 or k == 0.0:
		return 0
	dirty = true
	return int(world.call("RadialImpulse", c.x, c.y, r, k))


## One fixed sim step in C# (MASS_HORDE §3/§4): flow-field seek, pressure,
## knockback, Core ring + building projection, contact attacks. `blk` is the
## per-building-slot occupancy (the flow field rebuilds only when it changes).
## Returns the action log ([op, slot] pairs; then [ACT_BLD, building, hits]
## rows whose damage sums are in `bld_dmg`). `prm` = [accel_k, sep_k,
## sep_cap, friction, kmax, front_k, bld_cost].
func move(dt: float, frozen: bool, center: Vector2, stop_r: float, r_stop: float, r_fire: float, blk: PackedByteArray, side: int, cell: float, prm: PackedFloat64Array = PackedFloat64Array([6.0, 0.5, 0.35, 6.0])) -> PackedInt32Array:
	_configure(center, stop_r, side, cell)
	world.call("SetParams", prm)
	var acts: PackedInt32Array = world.call("Step", dt, frozen, r_stop, r_fire, blk)
	bld_dmg = world.call("LastBuildingDamage")
	pull()
	return acts


var _cfg: Array = []


func _configure(center: Vector2, stop_r: float, side: int, cell: float) -> void:
	var want: Array = [center, stop_r, side, cell]
	if _cfg != want:
		_cfg = want
		world.call("Configure", center.x, center.y, stop_r, side, cell)


## Refresh the GDScript mirror from the C# world (one packed pull).
func pull() -> void:
	var n: int = capacity()
	var r: Array = world.call("Pull", n)
	pos = r[0]; vel = r[1]; cur_s = r[2]; slow_t = r[3]; slow_m = r[4]
	shock_t = r[5]; hit_t = r[6]; taunt_t = r[7]; atk_cd = r[8]; fire_cd = r[9]
	dirty = true


## Spawn-order reap split in C#: [alive order, dead slots in spawn order].
func split_order() -> Array:
	return world.call("SplitOrder", order)


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
	vel[s] = d.get("vel", Vector2.ZERO)
	cur_s[s] = float(d.get("cur_s", 0.0))
	wv[s] = int(d.get("wv", 0))
	wt[s] = maxi(1, int(d.get("wt", 1)))
	guard[s] = float(d.get("guard", 0.0))
	burn_t[s] = float(d.get("burn_t", 0.0))
	burn_d[s] = float(d.get("burn_d", 0.0))
	commit(s)


## Debug / test / tool view of one body (a fresh copy, not a live reference).
func get_dict(s: int) -> Dictionary:
	var d: Dictionary = {
		"kind": kind[s], "pos": pos[s], "hp": hp[s], "max_hp": max_hp[s], "spd": spd[s], "dmg": dmg[s],
		"cash": cash[s], "xp": xp[s], "coin": coin[s], "size": size[s], "atk_cd": atk_cd[s],
		"slow_t": slow_t[s], "slow_m": slow_m[s], "shield": shield[s], "max_shield": max_shield[s],
		"fire_cd": fire_cd[s], "shock_t": shock_t[s], "shock_src": shock_src[s], "hit_t": hit_t[s],
		"eid": eid[s], "taunt_t": taunt_t[s], "quad": quad[s], "shred_n": shred_n[s],
		"marked": is_marked(s), "slot": s, "share": share[s], "vel": vel[s], "cur_s": cur_s[s],
		"wv": wv[s], "wt": wt[s], "guard": guard[s], "burn_t": burn_t[s], "burn_d": burn_d[s],
	}
	if has_exit(s):
		d["exit"] = exit[s]
	return d


func to_dicts() -> Array:
	var out: Array = []
	for s in order:
		out.append(get_dict(s))
	return out
