extends RefCounted
## Troops (REDESIGN_SPEC §2.5, SYSTEMS §2.6): units spawned by troop huts that
## walk out of the base along their lane and fight the shapes. Pure, static,
## deterministic (no RNG; fixed iteration order), stepped by TowerState's tick.
##   huts   = [{slot, id, lvl, home: Vector2, anchor: Vector2}]
##   troops = [{tid, hut, kind, pos, hp, max_hp, dmg, rate, range, spd, aoe,
##              cd, state, respawn_t, tgt, anchor, home}]
##   state: seek | engage | retreat | dead
## AI: seek the nearest enemy within SEEK cells of the hut's lane anchor
## (drones prefer flyers, sappers elites/bosses/marked), never straying more
## than LEASH cells from the anchor; engage in range; sappers and drones
## retreat home below 25% HP (infantry never retreats); the dead respawn at
## the hut after a delay. Enemies within 1 cell hit troops for 50% of their
## contact dmg; Riflemen taunt (pin) enemies within 1 cell. Troops never block
## pathing. step() returns events plus the hits TowerState applies (so shields,
## kill credit and Obelisk healing stay in one place).

const SEEK: float = 4.0
const LEASH: float = 6.0
const RETREAT_FRAC: float = 0.25
const CONTACT: float = 1.0      # cells: enemy -> troop contact / taunt radius
const MELEE: float = 0.35       # cells: sapper charge contact

const DEFS: Dictionary = {
	"hut_infantry": {"kind": "rifleman", "count": 3, "hp": 40.0, "dmg": 5.0, "rate": 1.2, "range": 2.0, "spd": 1.2, "respawn": 8.0, "aoe": 0.0, "retreat": false, "taunt": true},
	"hut_sapper": {"kind": "sapper", "count": 2, "hp": 25.0, "dmg": 30.0, "rate": 0.0, "range": 0.0, "spd": 1.6, "respawn": 12.0, "aoe": 1.0, "retreat": true, "taunt": false},
	"hut_drone": {"kind": "drone", "count": 4, "hp": 12.0, "dmg": 4.0, "rate": 2.0, "range": 2.5, "spd": 2.5, "respawn": 6.0, "aoe": 0.0, "retreat": true, "taunt": false},
}
const FLYERS: Array = ["drone", "mite"]
const ARMORED: Array = ["elite", "boss", "hauler"]
const PRIORITY: Array = ["elite", "boss"]


## Troops per hut: base count, +1 at L3 and L5 (+extra from parts).
static func count_for(hut_id: String, lvl: int, extra: int = 0) -> int:
	var d: Dictionary = DEFS.get(hut_id, {})
	return int(d.get("count", 0)) + (1 if lvl >= 3 else 0) + (1 if lvl >= 5 else 0) + maxi(0, extra)


## Stats of one troop of `hut_id` at hut level `lvl`. mods: dmg_mult, hp_mult,
## respawn_minus (s), cell_px.
static func troop_stats(hut_id: String, lvl: int, mods: Dictionary) -> Dictionary:
	var d: Dictionary = DEFS.get(hut_id, {})
	var lm: float = pow(1.25, float(clampi(lvl, 1, 5) - 1))
	var px: float = float(mods.get("cell_px", 78.0))
	return {
		"kind": String(d.get("kind", "")),
		"max_hp": float(d.get("hp", 1.0)) * lm * float(mods.get("hp_mult", 1.0)),
		"dmg": float(d.get("dmg", 0.0)) * lm * float(mods.get("dmg_mult", 1.0)),
		"rate": float(d.get("rate", 0.0)),
		"range": float(d.get("range", 0.0)) * px,
		"spd": float(d.get("spd", 1.0)) * px,
		"aoe": float(d.get("aoe", 0.0)) * px,
		"respawn": maxf(1.0, float(d.get("respawn", 8.0)) - float(mods.get("respawn_minus", 0.0))) * float(mods.get("respawn_mult", 1.0)),
	}


## Reconcile troops with huts: each hut keeps exactly count_for() troops (new
## ones spawn at the hut now); stats refresh in place (levels, packs, waves).
static func sync(troops: Array, huts: Array, mods: Dictionary, counter: Dictionary) -> Array:
	var ev: Array = []
	var keep: Array = []
	for h in huts:
		var hd: Dictionary = h
		var hid: String = String(hd["id"])
		var want: int = count_for(hid, int(hd["lvl"]), int(mods.get("extra", 0)) + (int(mods.get("extra_drone", 0)) if hid == "hut_drone" else 0))
		var st: Dictionary = troop_stats(hid, int(hd["lvl"]), mods)
		var have: int = 0
		for t in troops:
			var td: Dictionary = t
			if int(td["hut"]) != int(hd["slot"]) or have >= want:
				continue
			have += 1
			var frac: float = float(td["hp"]) / maxf(0.001, float(td["max_hp"]))
			for k in st.keys():
				if k != "kind":
					td[k] = st[k]
			td["hp"] = float(td["max_hp"]) * frac if String(td["state"]) != "dead" else 0.0
			td["anchor"] = hd["anchor"]
			td["post"] = hd.get("post", hd["anchor"])
			td["seek"] = float(hd.get("seek", SEEK))
			td["leash"] = float(hd.get("leash", LEASH))
			td["home"] = hd["home"]
			keep.append(td)
		while have < want:
			have += 1
			var tid: int = int(counter.get("next", 1))
			counter["next"] = tid + 1
			var nt: Dictionary = st.duplicate()
			nt["tid"] = tid
			nt["hut"] = int(hd["slot"])
			nt["pos"] = hd["home"]
			nt["hp"] = float(st["max_hp"])
			nt["cd"] = 0.0
			nt["state"] = "seek"
			nt["respawn_t"] = 0.0
			nt["tgt"] = -1
			nt["anchor"] = hd["anchor"]
			nt["post"] = hd.get("post", hd["anchor"])
			nt["seek"] = float(hd.get("seek", SEEK))
			nt["leash"] = float(hd.get("leash", LEASH))
			nt["home"] = hd["home"]
			nt["retreat"] = bool((DEFS[hid] as Dictionary)["retreat"])
			nt["taunt"] = bool((DEFS[hid] as Dictionary)["taunt"])
			keep.append(nt)
			ev.append({"t": "troop_spawn", "tid": tid, "kind": String(nt["kind"]), "pos": nt["pos"], "hut": int(hd["slot"])})
	troops.clear()
	troops.append_array(keep)
	return ev


static func alive_count(troops: Array) -> int:
	var n: int = 0
	for t in troops:
		if String((t as Dictionary)["state"]) != "dead":
			n += 1
	return n


## Living slot of `eid` in the EnemyStore, or -1.
static func _eid_index(en, eid: int) -> int:
	if eid < 0:
		return -1
	var k: int = en.slot_of(eid)
	if k >= 0 and en.hp[k] > 0.0:
		return k
	return -1


## Best target for troop td: priority kinds first for its role, then nearest
## to the troop; candidates must be within SEEK cells of the anchor. Hash
## candidates arrive in spawn order, so the strict `<` keeps the old winner.
static func _seek(td: Dictionary, en, eh, px: float) -> int:
	var anchor: Vector2 = td["anchor"]
	var pos: Vector2 = td["pos"]
	var lim: float = float(td.get("seek", SEEK)) * px
	var best: int = -1
	var best_key: float = INF
	for k in eh.candidates(anchor, lim):
		var kind: String = en.kind[k]
		if en.hp[k] <= 0.0 or kind == "courier":
			continue
		var ep: Vector2 = en.pos[k]
		if anchor.distance_to(ep) > lim:
			continue
		var key: float = pos.distance_squared_to(ep)
		var pri: bool = false
		match String(td["kind"]):
			"drone":
				pri = FLYERS.has(kind)
			"sapper":
				pri = PRIORITY.has(kind) or en.is_marked(k)
		if pri:
			key -= 1.0e9
		if key < best_key:
			best_key = key
			best = k
	return best


static func _move(td: Dictionary, to: Vector2, dt: float) -> void:
	var pos: Vector2 = td["pos"]
	var d: Vector2 = to - pos
	var step: float = float(td["spd"]) * dt
	td["pos"] = to if d.length() <= step else pos + d.normalized() * step


## Advance every troop by dt. Returns {ev: [...], hits: [{eid, dmg, tid}]}.
## ctx: cell_px, heal_frac (retreat heal per s, default 0.2).
## en / eh: the TowerState EnemyStore + EnemyHash (query object).
static func step(troops: Array, en, eh, dt: float, ctx: Dictionary) -> Dictionary:
	var ev: Array = []
	var hits: Array = []
	var px: float = float(ctx.get("cell_px", 78.0))
	var contact: float = CONTACT * px * 0.5
	for t in troops:
		var td: Dictionary = t
		var st: String = String(td["state"])
		if st == "dead":
			td["respawn_t"] = float(td["respawn_t"]) - dt
			if float(td["respawn_t"]) <= 0.0:
				td["state"] = "seek"
				td["hp"] = float(td["max_hp"])
				td["pos"] = td["home"]
				td["tgt"] = -1
				td["cd"] = 0.0
				ev.append({"t": "troop_spawn", "tid": int(td["tid"]), "kind": String(td["kind"]), "pos": td["pos"], "hut": int(td["hut"]), "respawn": true})
			continue
		td["cd"] = maxf(0.0, float(td["cd"]) - dt)
		# Enemies in contact hit the troop (50% of contact dmg); Riflemen taunt.
		var pos: Vector2 = td["pos"]
		for ed in eh.candidates(pos, contact + en.max_size * 0.5):
			if en.hp[ed] <= 0.0 or en.kind[ed] == "courier":
				continue
			if pos.distance_to(en.pos[ed]) <= contact + en.size[ed] * 0.5:
				td["hp"] = float(td["hp"]) - 0.5 * en.dmg[ed] * dt
				if bool(td.get("taunt", false)):
					en.set_taunt(ed, 0.15)
		if float(td["hp"]) <= 0.0:
			td["state"] = "dead"
			td["hp"] = 0.0
			td["respawn_t"] = float(td["respawn"])
			td["tgt"] = -1
			ev.append({"t": "troop_die", "tid": int(td["tid"]), "kind": String(td["kind"]), "pos": td["pos"]})
			continue
		# Retreat (sappers / drones) below 25%; heal at home, then go again.
		if bool(td.get("retreat", false)) and (st == "retreat" or float(td["hp"]) < RETREAT_FRAC * float(td["max_hp"])):
			if st != "retreat":
				td["state"] = "retreat"
				td["tgt"] = -1
				ev.append({"t": "troop_move", "tid": int(td["tid"]), "to": td["home"], "state": "retreat"})
			_move(td, td["home"], dt)
			if (td["pos"] as Vector2).distance_to(td["home"]) < 1.0:
				td["hp"] = minf(float(td["max_hp"]), float(td["hp"]) + float(ctx.get("heal_frac", 0.2)) * float(td["max_hp"]) * dt)
				if float(td["hp"]) >= float(td["max_hp"]):
					td["state"] = "seek"
			continue
		var k: int = _eid_index(en, int(td["tgt"]))
		var anchor: Vector2 = td["anchor"]
		var leash: float = float(td.get("leash", LEASH)) * px
		if k >= 0 and anchor.distance_to(en.pos[k]) > leash:
			k = -1
		if k < 0:
			k = _seek(td, en, eh, px)
			var new_tgt: int = en.eid[k] if k >= 0 else -1
			if new_tgt != int(td["tgt"]):
				td["tgt"] = new_tgt
				ev.append({"t": "troop_move", "tid": int(td["tid"]), "to": en.pos[k] if k >= 0 else anchor, "state": "engage" if k >= 0 else "seek"})
		if k < 0:
			td["state"] = "seek"
			_move(td, td.get("post", anchor), dt)
			continue
		td["state"] = "engage"
		var e2: int = k
		var ep: Vector2 = en.pos[e2]
		var reach: float = float(td["range"]) if float(td["range"]) > 0.0 else MELEE * px + en.size[e2] * 0.5
		var dist: float = (td["pos"] as Vector2).distance_to(ep)
		if dist > reach:
			# chase, but never past the leash
			var to: Vector2 = ep
			if anchor.distance_to(to) > leash:
				to = anchor + (to - anchor).normalized() * leash
			_move(td, to, dt)
			continue
		if String(td["kind"]) == "sapper":
			# suicide charge: aoe blast, x2 vs armored, then respawn
			var rad: float = float(td["aoe"])
			for xd in eh.candidates(ep, rad):
				if en.hp[xd] <= 0.0 or en.kind[xd] == "courier":
					continue
				if en.pos[xd].distance_to(ep) <= rad:
					var m: float = 2.0 if ARMORED.has(en.kind[xd]) else 1.0
					hits.append({"eid": en.eid[xd], "dmg": float(td["dmg"]) * m, "tid": int(td["tid"])})
			ev.append({"t": "troop_hit", "tid": int(td["tid"]), "eid": en.eid[e2], "pos": ep, "aoe": rad, "kind": "sapper"})
			td["state"] = "dead"
			td["hp"] = 0.0
			td["respawn_t"] = float(td["respawn"])
			td["tgt"] = -1
			ev.append({"t": "troop_die", "tid": int(td["tid"]), "kind": "sapper", "pos": td["pos"], "blast": true})
			continue
		if float(td["cd"]) <= 0.0 and float(td["rate"]) > 0.0:
			td["cd"] = 1.0 / float(td["rate"])
			hits.append({"eid": en.eid[e2], "dmg": float(td["dmg"]), "tid": int(td["tid"])})
			ev.append({"t": "troop_hit", "tid": int(td["tid"]), "eid": en.eid[e2], "pos": ep, "kind": String(td["kind"])})
			# MASS_HORDE §D4: against a mass every troop attack cleaves -- it also
			# hits up to cleave-1 more bodies within reach in a 90 deg arc toward
			# the target (spawn order, deterministic), or a troop evaporates.
			var cl: int = int(ctx.get("cleave", 0))
			if cl > 1:
				var tp: Vector2 = td["pos"]
				var fwd: Vector2 = (ep - tp).normalized()
				var got: int = 1
				for xd in eh.candidates(tp, reach + en.max_size * 0.5):
					if got >= cl:
						break
					if xd == e2 or en.hp[xd] <= 0.0 or en.kind[xd] == "courier":
						continue
					var rel: Vector2 = en.pos[xd] - tp
					var rl: float = rel.length()
					if rl > reach + en.size[xd] * 0.5 or (rl > 0.0 and rel.dot(fwd) < 0.7071 * rl):
						continue
					hits.append({"eid": en.eid[xd], "dmg": float(td["dmg"]), "tid": int(td["tid"])})
					got += 1
	return {"ev": ev, "hits": hits}


## Theoretical DPS of the living troops (PowerModel snapshot).
static func dps_list(troops: Array) -> Array:
	var out: Array = []
	for t in troops:
		var td: Dictionary = t
		var d: float = float(td["dmg"]) * float(td["rate"])
		if String(td["kind"]) == "sapper":
			d = float(td["dmg"]) / maxf(1.0, float(td["respawn"]) + 3.0)
		out.append({"kind": String(td["kind"]), "dps": d})
	return out
