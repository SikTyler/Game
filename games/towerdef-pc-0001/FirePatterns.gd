extends RefCounted
## Weapon firing patterns (V2 P3c): what one shot of a building does to the
## horde. TowerState._fire picks the target (or, for a fixed weapon, checks
## its shape is occupied) and calls fire(); the patterns only hit bodies and
## append view events. Every verb is the MASS_HORDE §D4 crowd version (the
## designed waves are the only ruleset). `S` is the TowerState run (untyped:
## a preload here would be cyclic); patterns use its store `en`, hash `eh`,
## `_hit` / `_ignite` / `_nearest` and the `_blockable` / `_blocked` flags.
##   wd   the weapon dict from compute_stats (dmg, rate, range, aim, facing,
##        arc_cos, pattern params)
##   aim  unit facing (fixed weapons fire along it)
##   te   target slot (-1 for a fixed weapon: it fires along `aim`)
## P7 adds the remaining verbs (proj, nova, bounce, homing, beam_ramp,
## mine_layer) with the weapons that use them.
## V2 P7a merge mods arrive on wd as `<key>_add` (pierce, chains, arcs,
## rounds, boss) and `<key>_m` (splash, knock, cone, burn); `lvl` is the
## pattern level of the building's tier (T1 1, T2 3, T3 5).

const TuneRef := preload("res://Tune.gd")
const EnemyStore := preload("res://EnemyStore.gd")

const BOSSY: Array = ["boss", "elite"]
const PATTERNS: Array = ["pierce_round", "lob_aoe", "chain", "cone_dot", "pierce_line", "aura_slow",
	"nova", "aura_dmg", "homing", "mine", "cone_burst", "cone_knock", "beam_ramp", "lane_burn", "bounce", "heavy"]
## Patterns that hit everything around the weapon (no target pick).
const AURAS: Array = ["aura_slow", "nova", "aura_dmg"]
## Fixed weapons: cone shapes / lane shapes (shape_occupied).
const CONES: Array = ["cone_dot", "cone_burst", "cone_knock"]
const LANES: Array = ["pierce_line", "beam_ramp", "lane_burn"]


static func fire(S, pattern: String, wd: Dictionary, from: Vector2, aim: Vector2, te: int, dmg: float, crit: bool, ev: Array) -> void:
	match pattern:
		"pierce_line":
			pierce_line(S, wd, from, aim, dmg, crit, ev)
		"cone_dot":
			cone_dot(S, wd, from, aim, dmg, crit, ev)
		"lob_aoe":
			lob_aoe(S, wd, from, te, dmg, crit, ev)
		"chain":
			chain(S, wd, from, te, dmg, crit, ev)
		"homing":
			homing(S, wd, from, te, dmg, crit, ev)
		"mine":
			mine(S, wd, from, te, dmg, crit, ev)
		"cone_burst":
			cone_burst(S, wd, from, aim, dmg, crit, ev)
		"cone_knock":
			cone_knock(S, wd, from, aim, dmg, crit, ev)
		"beam_ramp":
			beam_ramp(S, wd, from, aim, dmg, crit, ev)
		"lane_burn":
			lane_burn(S, wd, from, aim, dmg, crit, ev)
		"bounce":
			bounce(S, wd, from, te, dmg, crit, ev)
		"heavy":
			heavy(S, wd, from, te, dmg, crit, ev)
		_:
			pierce_round(S, wd, from, te, dmg, crit, ev)


## Is a fixed weapon's shape (its cone or lane along the facing) occupied?
static func shape_occupied(S, wd: Dictionary, from: Vector2) -> bool:
	var aim: Vector2 = wd["facing"]
	var pt: String = String(wd["pattern"])
	if LANES.has(pt):
		return S.eh.count_in_line(from, from + aim * float(wd["range"]), float(wd.get("pierce", 0.0)) + S.en.max_size * 0.5) > 0
	if CONES.has(pt):
		return S.eh.nearest_in_cone(from, aim, acos(clampf(float(wd["arc_cos"]), -1.0, 1.0)), cone_len(S, wd) if pt == "cone_dot" else float(wd["range"])) >= 0
	return true


## Flamer reach: 1.4 cells (+10% per level), never past its range.
static func cone_len(S, wd: Dictionary) -> float:
	return minf(float(wd["range"]), TuneRef.num("mass_flame_len", 1.4) * S.cpx() * (1.0 + 0.1 * float(int(wd.get("lvl", 1)) - 1)) * float(wd.get("cone_m", 1.0)))


## Railgun (fixed lane): infinite pierce along the facing, no falloff; x4 on
## the first elite / boss it meets. Bodies in line order.
static func pierce_line(S, wd: Dictionary, from: Vector2, dir: Vector2, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var reach: float = float(wd["range"])
	var tip: Vector2 = from + dir * reach
	var on: Array = []
	for ed in S.eh.line(from, tip, float(wd["pierce"]) + en.max_size * 0.5 + 1.0):
		if en.hp[ed] <= 0.0:
			continue
		var rel: Vector2 = en.pos[ed] - from
		var along: float = rel.dot(dir)
		if along < 0.0 or along > reach or absf(rel.cross(dir)) > float(wd["pierce"]) + en.size[ed] * 0.5:
			continue
		on.append([along, ed])
	on.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
	var boss_hit: bool = false
	S._blockable = true
	for x in on:
		var ed2: int = int((x as Array)[1])
		var m: float = 1.0
		if not boss_hit and (BOSSY.has(en.kind[ed2]) or en.is_marked(ed2)):
			boss_hit = true
			m = TuneRef.num("mass_rail_boss", 4.0) + float(wd.get("boss_add", 0.0))
		S._hit(ed2, dmg * m, ev, crit)
	S._blockable = false
	ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": tip})


## Flamer (fixed cone): a gout along the facing into its cone: a light lick
## plus a 2 s burn that spreads to touching bodies.
static func cone_dot(S, wd: Dictionary, from: Vector2, dir: Vector2, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var cl: float = cone_len(S, wd)
	var half: float = acos(clampf(float(wd["arc_cos"]), -1.0, 1.0))
	var bdps: float = dmg * TuneRef.num("mass_flame_burn", 0.3) * float(wd.get("burn_m", 1.0))
	for ed in S.eh.cone(from, dir, half, cl):
		if en.hp[ed] <= 0.0:
			continue
		S._hit(ed, dmg * TuneRef.num("mass_flame_hit", 0.15), ev, crit)
		S._ignite(ed, TuneRef.num("mass_burn_s", 2.0), bdps)
	ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": from + dir * cl, "cone": rad_to_deg(half * 2.0)})


## Mortar (radial lob): AoE r 0.75 cell (+20%/lv); the outer ring is a
## knockback blast that parts the sea; 500+ pushed = Parting the Sea.
static func lob_aoe(S, wd: Dictionary, from: Vector2, te: int, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var tpos: Vector2 = en.pos[te]
	var lvl: int = int(wd.get("lvl", 1))
	var rad: float = float(wd.get("lob_r", TuneRef.num("mass_mortar_r", 0.75))) * S.cpx() * (1.0 + 0.2 * float(lvl - 1)) * float(wd.get("splash_m", 1.0))
	for ed in S.eh.candidates(tpos, rad):
		if en.hp[ed] > 0.0 and en.pos[ed].distance_to(tpos) <= rad:
			S._hit(ed, dmg, ev, crit)
	var pushed: int = en.radial_knock(tpos, rad * 1.5, TuneRef.num("horde_knock", 60.0) * float(wd.get("lob_knock", TuneRef.num("mass_mortar_knock", 2.0))) * float(wd.get("knock_m", 1.0)))
	if pushed >= 500:
		ev.append({"t": "part_sea", "n": pushed, "pos": tpos})
	ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": tpos, "radius": rad})


## Tesla (radial chain): each discharge forks into 3 arcs (the nearest 3
## bodies), each chaining on (6 +3/lv + chain parts, cap 20; 70 px jumps,
## x0.9 per jump) to bodies no arc has hit; stuns elites / bosses 0.2 s.
static func chain(S, wd: Dictionary, from: Vector2, te: int, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var lvl: int = int(wd.get("lvl", 1))
	var ca: int = int(wd.get("chains_add", 0.0))
	var n: int = mini(TuneRef.int_of("mass_chain_cap", 20) + ca, int(wd.get("chain_base", TuneRef.int_of("mass_chain", 6))) + 3 * (lvl - 1) + int(S.pf("chain")) + ca)
	var arcs: int = TuneRef.int_of("mass_tesla_arcs", 3) + int(wd.get("arcs_add", 0.0))
	var jr: float = TuneRef.num("mass_chain_r", 70.0)
	var hit: Dictionary = {}
	var starts: Array = [te]
	for st in S.eh.nearest_n(from, arcs + 1, float(wd["range"])):
		if starts.size() >= arcs:
			break
		if st != te:
			starts.append(st)
	for s0 in starts:
		var ce: int = s0
		var d2: float = dmg
		var prev: Vector2 = from
		var jumps: int = 0
		while ce >= 0 and jumps < n:
			jumps += 1
			hit[ce] = true
			var cpos: Vector2 = en.pos[ce]
			if en.hp[ce] > 0.0:
				S._hit(ce, d2, ev, crit)
				en.set_shock(ce, 1.5)
				en.shock_src[ce] = int(wd["slot"])
				if BOSSY.has(en.kind[ce]):
					en.apply_slow(ce, 0.2, 0.0)
			ev.append({"t": "shot", "kind": String(wd["kind"]), "from": prev, "to": cpos})
			prev = cpos
			d2 *= TuneRef.num("mass_chain_frac", 0.9)
			ce = S._nearest(cpos, jr, hit)


## Gatling (arc): two rounds per shot against a crowd - the target and the
## next nearest body the turret can turn to; each pierces 3 bodies (+2/lv,
## cap 12), x0.85 per body; a Shieldbearer's front stops it.
static func pierce_round(S, wd: Dictionary, from: Vector2, te: int, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var lvl: int = int(wd.get("lvl", 1))
	var pa: int = int(wd.get("pierce_add", 0.0))
	var pn: int = mini(12 + pa, 3 + 2 * (lvl - 1) + pa)
	var rounds: int = TuneRef.int_of("mass_gun_rounds", 2) + int(wd.get("rounds_add", 0.0))
	var reach3: float = float(wd["range"])
	var aims: Array = [te]
	var face: Vector2 = wd.get("facing", Vector2.ZERO)
	var arc_cos: float = float(wd.get("arc_cos", -1.0))
	for t2 in S.eh.nearest_n(from, rounds + 1, reach3):
		if aims.size() >= rounds:
			break
		if t2 == te:
			continue
		if arc_cos > -1.0 and not in_arc(from, en.pos[t2], face, arc_cos):
			continue
		aims.append(t2)
	for ai in aims:
		_round(S, from, en.pos[int(ai)], int(ai), pn, reach3, dmg, crit, ev)


## Is `p` inside the arc (cos of the half angle) around `face` from `from`?
static func in_arc(from: Vector2, p: Vector2, face: Vector2, arc_cos: float) -> bool:
	var d: Vector2 = p - from
	var l: float = d.length()
	return l < 1e-6 or d.dot(face) >= arc_cos * l


static func _round(S, from: Vector2, tpos: Vector2, te: int, pn: int, reach3: float, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var dir3: Vector2 = (tpos - from).normalized()
	var on3: Array = []
	for ed in S.eh.line(from, from + dir3 * reach3, en.max_size * 0.5 + 2.0):
		if en.hp[ed] <= 0.0:
			continue
		var rel3: Vector2 = en.pos[ed] - from
		var al: float = rel3.dot(dir3)
		if al < 0.0 or al > reach3 or absf(rel3.cross(dir3)) > en.size[ed] * 0.5 + 2.0:
			continue
		on3.append([al, ed])
	on3.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
	var d3: float = dmg
	var hitn: int = 0
	var last: Vector2 = tpos
	S._blockable = true
	for x in on3:
		if hitn >= pn:
			break
		var ed3: int = int((x as Array)[1])
		S._hit(ed3, d3, ev, crit)
		last = en.pos[ed3]
		hitn += 1
		if S._blocked:
			break
		d3 *= TuneRef.num("mass_pierce_fall", 0.85)
	S._blockable = false
	if hitn == 0 and en.hp[te] > 0.0:
		S._hit(te, dmg, ev, crit)
	ev.append({"t": "shot", "kind": "gun", "from": from, "to": last})


## Cryo Spire (radial aura): every pulse slows (-50%, MASS §D4) and chills
## every body in range for 10% of its damage; slowed bodies block the flow
## behind them, chilled ones shatter / turn Brittle. True when any was hit.
static func aura_slow(S, wd: Dictionary, from: Vector2, ev: Array) -> bool:
	var en = S.en
	var any: bool = false
	var frange: float = float(wd["range"])
	var fslow: float = maxf(float(wd["slow"]), TuneRef.num("mass_frost_slow", 0.5))
	for fe in S.eh.candidates(from, frange):
		if en.hp[fe] > 0.0 and from.distance_to(en.pos[fe]) <= frange:
			any = true
			en.apply_slow(fe, float(wd["slow_t"]), 1.0 - fslow)
			en.flags[fe] = en.flags[fe] | EnemyStore.F_FROST
			S._hit(fe, float(wd["dmg"]) * TuneRef.num("mass_frost_dmg", 0.1), ev)
	if any:
		ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": from, "radius": frange})
	return any


# ======================================================== V2 P7d patterns
## Radial aura weapons (Pulse Emitter nova, Spike Pylon stabs): every body
## within range takes the hit; the nova also shoves them a little. True when
## any was hit (the cooldown only runs when it hits something).
static func aura_hit(S, wd: Dictionary, from: Vector2, ev: Array) -> bool:
	var en = S.en
	var r: float = float(wd["range"])
	var nova: bool = String(wd["pattern"]) == "nova"
	var dmg: float = float(wd["dmg"])
	var crit: bool = S._roll_crit(wd)
	if crit:
		dmg *= S.crit_mult()
	var any: bool = false
	for ed in S.eh.candidates(from, r):
		if en.hp[ed] > 0.0 and from.distance_to(en.pos[ed]) <= r + en.size[ed] * 0.5:
			S._hit(ed, dmg, ev, crit)
			any = true
	if any:
		if nova:
			en.radial_knock(from, r, TuneRef.num("horde_knock", 60.0) * 0.6 * float(wd.get("knock_m", 1.0)))
		ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": from, "radius": r})
	return any


## Missile Battery (radial homing): the target plus the nearest bodies in
## range, one missile each (4 + mods), each with a small blast (50%).
static func homing(S, wd: Dictionary, from: Vector2, te: int, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var n: int = int(wd.get("missiles", 4)) + int(wd.get("missiles_add", 0.0))
	var aims: Array = [te]
	for t2 in S.eh.nearest_n(from, n + 1, float(wd["range"])):
		if aims.size() >= n:
			break
		if t2 != te:
			aims.append(t2)
	var br: float = float(wd.get("blast", 0.4 * S.cpx())) * float(wd.get("splash_m", 1.0))
	for ai in aims:
		var tp: Vector2 = en.pos[int(ai)]
		S._hit(int(ai), dmg, ev, crit)
		for ed in S.eh.candidates(tp, br):
			if ed != int(ai) and en.hp[ed] > 0.0 and en.pos[ed].distance_to(tp) <= br:
				S._hit(ed, dmg * 0.5, ev)
		ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": tp, "radius": br})


## Minelayer (radial): a mine under the target that blows after its fuse
## (TowerState.orbitals: the delayed-blast list the Orbital Strike uses).
static func mine(S, wd: Dictionary, from: Vector2, te: int, dmg: float, crit: bool, ev: Array) -> void:
	var tp: Vector2 = S.en.pos[te]
	var br: float = float(wd.get("blast", 0.8 * S.cpx())) * float(wd.get("splash_m", 1.0))
	S.orbitals.append({"pos": tp, "t": float(wd.get("fuse", 1.0)), "dmg": dmg, "r": br, "src": String(wd["kind"]), "knock": 1.0})
	ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": tp})


## Scatter Gun (fixed cone): a fan of pellets, one per body nearest first.
static func cone_burst(S, wd: Dictionary, from: Vector2, dir: Vector2, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var half: float = acos(clampf(float(wd["arc_cos"]), -1.0, 1.0))
	var n: int = int(wd.get("pellets", 6)) + int(wd.get("pellets_add", 0.0))
	var on: Array = []
	for ed in S.eh.cone(from, dir, half, float(wd["range"])):
		if en.hp[ed] > 0.0:
			on.append([from.distance_squared_to(en.pos[ed]), ed])
	on.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
	var k: int = 0
	for x in on:
		if k >= n:
			break
		S._hit(int((x as Array)[1]), dmg, ev, crit)
		k += 1
	# leftover pellets land on the nearest again (a tight crowd eats the fan)
	if k > 0 and k < n:
		S._hit(int((on[0] as Array)[1]), dmg * float(n - k) * 0.5, ev, crit)
	ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": from + dir * float(wd["range"]), "cone": rad_to_deg(half * 2.0)})


## Sonic Cannon (fixed cone): a shock wave - every body in the cone is hit
## and the pile is hurled back from the cannon.
static func cone_knock(S, wd: Dictionary, from: Vector2, dir: Vector2, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var half: float = acos(clampf(float(wd["arc_cos"]), -1.0, 1.0))
	var reach: float = float(wd["range"])
	for ed in S.eh.cone(from, dir, half, reach):
		if en.hp[ed] > 0.0:
			S._hit(ed, dmg, ev, crit)
	en.radial_knock(from + dir * reach * 0.35, reach * 0.8, TuneRef.num("horde_knock", 60.0) * float(wd.get("knock", 2.5)) * float(wd.get("knock_m", 1.0)))
	ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": from + dir * reach, "cone": rad_to_deg(half * 2.0)})


## Laser Lance (fixed lane): a beam through the whole lane whose damage
## ramps while it keeps firing (x1 -> x`ramp`, +0.25 per shot; resets when
## the lane empties - TowerState._fire).
static func beam_ramp(S, wd: Dictionary, from: Vector2, dir: Vector2, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var si: int = int(wd["slot"])
	var top: float = float(wd.get("ramp", 3.0)) + float(wd.get("ramp_add", 0.0))
	var m: float = minf(top, float(S.beam_ramps.get(si, 1.0)))
	S.beam_ramps[si] = minf(top, m + 0.25)
	var reach: float = float(wd["range"])
	var w: float = float(wd.get("pierce", 8.0))
	for ed in S.eh.line(from, from + dir * reach, w + en.max_size * 0.5 + 1.0):
		if en.hp[ed] <= 0.0:
			continue
		var rel: Vector2 = en.pos[ed] - from
		var along: float = rel.dot(dir)
		if along < 0.0 or along > reach or absf(rel.cross(dir)) > w + en.size[ed] * 0.5:
			continue
		S._hit(ed, dmg * m, ev, crit)
	ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": from + dir * reach, "ramp": m})


## Plasma Fence (fixed lane): everything on the line catches fire (burn for
## burn_s seconds at 60% of the damage per second) plus a light touch.
static func lane_burn(S, wd: Dictionary, from: Vector2, dir: Vector2, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var reach: float = float(wd["range"])
	var w: float = float(wd.get("pierce", 10.0))
	var bs: float = float(wd.get("burn_s", 2.0))
	for ed in S.eh.line(from, from + dir * reach, w + en.max_size * 0.5 + 1.0):
		if en.hp[ed] <= 0.0:
			continue
		var rel: Vector2 = en.pos[ed] - from
		var along: float = rel.dot(dir)
		if along < 0.0 or along > reach or absf(rel.cross(dir)) > w + en.size[ed] * 0.5:
			continue
		S._hit(ed, dmg * 0.2, ev, crit)
		S._ignite(ed, bs, dmg * 0.6 * float(wd.get("burn_m", 1.0)))
	ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": from + dir * reach})


## Saw Launcher (arc): the blade hits its target then ricochets to the
## nearest unhit body within 1.2 cells, 4 more times (+ mods), x0.85 each.
static func bounce(S, wd: Dictionary, from: Vector2, te: int, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var n: int = int(wd.get("bounces", 4)) + int(wd.get("bounces_add", 0.0))
	var jr: float = 1.2 * S.cpx()
	var hit: Dictionary = {}
	var ce: int = te
	var d: float = dmg
	var prev: Vector2 = from
	var k: int = 0
	while ce >= 0 and k <= n:
		hit[ce] = true
		var cp: Vector2 = en.pos[ce]
		if en.hp[ce] > 0.0:
			S._hit(ce, d, ev, crit)
		ev.append({"t": "shot", "kind": String(wd["kind"]), "from": prev, "to": cp})
		prev = cp
		d *= 0.85
		k += 1
		ce = S._nearest(cp, jr, hit)


## Harpoon (arc): one heavy bolt, x`elite` on elites / bosses, and the
## struck body is slowed hard for 1.5 s.
static func heavy(S, wd: Dictionary, from: Vector2, te: int, dmg: float, crit: bool, ev: Array) -> void:
	var en = S.en
	var m: float = 1.0
	if BOSSY.has(en.kind[te]) or en.is_marked(te):
		m = float(wd.get("elite", 2.5)) + float(wd.get("elite_add", 0.0))
	S._hit(te, dmg * m, ev, crit)
	if en.hp[te] > 0.0:
		en.apply_slow(te, 1.5, 1.0 - float(wd.get("slow", 0.4)))
	ev.append({"t": "shot", "kind": String(wd["kind"]), "from": from, "to": en.pos[te]})
