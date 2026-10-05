extends RefCounted
## Core Parts meta rules (REDESIGN_SPEC §3.1, SYSTEMS §3.1-3.3). Pure static
## functions over the save Dictionary:
##   save.parts = {next_uid, items: {"<uid>": {id, lvl, stars, locked}},
##                 sets_completed: [set ids], specials_unlocked: [part ids]}
##   save.cores.presets = {core: [[uid|""] x 7] x 4}, preset_idx = {core: k}
## One item per part id: a duplicate adds a star (max 2, +5% benefit each),
## then auto-salvages to Scrap. Slot k of a Core takes PartDB slot SLOT_TYPES[k]
## (Frame, Barrel, Capacitor, Engine, Frame, Barrel, Set); slot 6 (Core L40)
## takes set specials only, and a special also fits a normal slot of its type.
## run_fx(save, core) is the single hand-off to TowerState: every equipped
## part's plus (x level/star mult) and minus (never scaled), plus 2/4-piece
## set bonuses, summed per key (additive inside (1 + sum)).

const FactoryRef := preload("res://Factory.gd")
const PartDB := preload("res://data/PartDB.gd")
const SetDB := preload("res://data/SetDB.gd")
const Cores := preload("res://Cores.gd")
const TuneRef := preload("res://Tune.gd")

const SLOT_TYPES: Array = ["F", "B", "C", "E", "F", "B", "S"]
const N_SLOTS: int = 7
const SET_SLOT: int = 6
const PRESETS: int = 4
const MAX_STARS: int = 2
## Normal slots unlocked by Core level (SYSTEMS §1.3): 2/3/4/5/6 at L1/5/12/20/30.
const SLOT_LVLS: Array = [1, 1, 5, 12, 20, 30]
const SET_SLOT_LVL: int = 40


static func default_block() -> Dictionary:
	return {"next_uid": 1, "items": {}, "sets_completed": [], "specials_unlocked": []}


## Coerce a raw (JSON) parts block: known ids, levels/stars clamped, one item
## per id (later duplicates fold away), uids unique and below next_uid.
static func normalize_block(raw: Variant) -> Dictionary:
	var d: Dictionary = default_block()
	if not (raw is Dictionary):
		return d
	var r: Dictionary = raw
	var items: Dictionary = {}
	var seen: Dictionary = {}
	var hi: int = 0
	var it_in: Variant = r.get("items", {})
	if it_in is Dictionary:
		var keys: Array = (it_in as Dictionary).keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(String(a)) < int(String(b)))
		for k in keys:
			var e: Variant = (it_in as Dictionary)[k]
			if not (e is Dictionary):
				continue
			var id: String = String((e as Dictionary).get("id", ""))
			var uid: int = int(String(k))
			if not PartDB.has(id) or seen.has(id) or uid <= 0:
				continue
			seen[id] = true
			hi = maxi(hi, uid)
			items[str(uid)] = {
				"id": id,
				"lvl": clampi(int((e as Dictionary).get("lvl", 1)), 1, PartDB.max_lvl(id)),
				"stars": clampi(int((e as Dictionary).get("stars", 0)), 0, MAX_STARS),
				"locked": bool((e as Dictionary).get("locked", false)),
			}
	d["items"] = items
	d["next_uid"] = maxi(hi + 1, int(r.get("next_uid", 1)))
	var sc: Array = []
	for v in r.get("sets_completed", []):
		if SetDB.DEFS.has(String(v)) and not sc.has(String(v)):
			sc.append(String(v))
	d["sets_completed"] = sc
	var su: Array = []
	for v in r.get("specials_unlocked", []):
		if PartDB.is_special(String(v)) and not su.has(String(v)):
			su.append(String(v))
	d["specials_unlocked"] = su
	return d


## Presets for every owned Core: 4 x 7 uids; unknown uids and wrong-type
## placements are dropped. Call after parts and cores are normalized.
static func sanitize_presets(s: Dictionary) -> void:
	var cb: Dictionary = Cores._block(s)
	var pin: Dictionary = cb.get("presets", {}) if cb.get("presets", {}) is Dictionary else {}
	var iin: Dictionary = cb.get("preset_idx", {}) if cb.get("preset_idx", {}) is Dictionary else {}
	var pr: Dictionary = {}
	var pi: Dictionary = {}
	for c in cb["owned"]:
		var cid: String = String(c)
		var src: Array = pin.get(cid, []) if pin.get(cid, []) is Array else []
		var rows: Array = []
		for k in PRESETS:
			var row: Array = []
			var used: Dictionary = {}
			var srow: Array = src[k] if k < src.size() and src[k] is Array else []
			for j in N_SLOTS:
				var uid: String = String(srow[j]) if j < srow.size() else ""
				if uid != "" and (used.has(uid) or not fits(s, uid, j)):
					uid = ""
				if uid != "":
					used[uid] = true
				row.append(uid)
			rows.append(row)
		pr[cid] = rows
		pi[cid] = clampi(int(iin.get(cid, 0)), 0, PRESETS - 1)
	cb["presets"] = pr
	cb["preset_idx"] = pi


static func _block(s: Dictionary) -> Dictionary:
	if not (s.get("parts", null) is Dictionary):
		s["parts"] = default_block()
	return s["parts"]


static func items(s: Dictionary) -> Dictionary:
	return _block(s)["items"]


static func item(s: Dictionary, uid: String) -> Dictionary:
	return items(s).get(uid, {})


static func uid_of(s: Dictionary, id: String) -> String:
	var it: Dictionary = items(s)
	for k in it.keys():
		if String((it[k] as Dictionary)["id"]) == id:
			return String(k)
	return ""


static func owns(s: Dictionary, id: String) -> bool:
	return uid_of(s, id) != ""


static func count(s: Dictionary) -> int:
	return items(s).size()


# ------------------------------------------------------------- inventory
## Scrap multiplier on salvage: Salvage Yard (+10% +2%/L above 1), Part
## Analysis research (+2%/L), Reforge scrap_p (+10%/L).
static func salvage_mult(s: Dictionary) -> float:
	var m: float = 1.0
	var op: Variant = s.get("outpost", null)
	if op is Dictionary:
		var bl: Variant = (op as Dictionary).get("buildings", {})
		if bl is Dictionary:
			for k in (bl as Dictionary).keys():
				var b: Dictionary = (bl as Dictionary)[k]
				if String(b.get("id", "")) == "scrapyard" and bool(b.get("built", true)):
					m += 0.10 + 0.02 * float(maxi(1, int(b.get("lvl", 1))) - 1)
	# FB2 / WP3: a Salvage Yard facility on the Factory counts when no legacy yard did
	if is_equal_approx(m, 1.0) and FactoryRef.fac_level(s, "scrapyard") > 0:
		m += 0.10
	var rs: Variant = s.get("research", null)
	if rs is Dictionary and (rs as Dictionary).get("lvls", null) is Dictionary:
		m += 0.02 * float(int(((rs as Dictionary)["lvls"] as Dictionary).get("part_analysis", 0)))
	return m


static func scrap_mult(s: Dictionary) -> float:
	var rf: Variant = s.get("reforge", null)
	if rf is Dictionary and (rf as Dictionary).get("nodes", null) is Dictionary:
		return 1.0 + 0.10 * float(int(((rf as Dictionary)["nodes"] as Dictionary).get("scrap_p", 0)))
	return 1.0


static func _add_scrap(s: Dictionary, n: int) -> int:
	var got: int = maxi(0, n)
	s["scrap"] = int(s.get("scrap", 0)) + got
	return got


## Add one copy of part `id` (crate, drop, special unlock). New -> a fresh item;
## owned -> +1 star (max 2); beyond that -> auto-salvage for Scrap.
static func grant(s: Dictionary, id: String, source: String = "") -> Array:
	if not PartDB.has(id):
		return []
	var uid: String = uid_of(s, id)
	if uid == "":
		var b: Dictionary = _block(s)
		var n: int = int(b["next_uid"])
		b["next_uid"] = n + 1
		(b["items"] as Dictionary)[str(n)] = {"id": id, "lvl": 1, "stars": 0, "locked": false}
		_bump_stat(s, "parts_found", 1)
		return [{"t": "part_new", "uid": str(n), "id": id, "rarity": PartDB.rarity_of(id), "source": source}]
	var it: Dictionary = item(s, uid)
	if int(it["stars"]) < MAX_STARS:
		it["stars"] = int(it["stars"]) + 1
		return [{"t": "part_star", "uid": uid, "id": id, "stars": int(it["stars"]), "source": source}]
	var sc: int = _add_scrap(s, int(round(float(PartDB.SALVAGE_BASE.get(PartDB.rarity_of(id), 5)) * salvage_mult(s))))
	return [{"t": "part_dup_salvaged", "uid": uid, "id": id, "scrap": sc, "source": source}]


static func _bump_stat(s: Dictionary, key: String, n: int) -> void:
	if not (s.get("stats", null) is Dictionary):
		return
	var st: Dictionary = s["stats"]
	st[key] = int(st.get(key, 0)) + n


## A uniformly random part id of `rarity` (seeded, crate / drop pools).
static func roll_id(rng: RandomNumberGenerator, rarity: String) -> String:
	var p: Array = PartDB.pool(rarity)
	if p.is_empty():
		p = PartDB.pool("common")
	return String(p[rng.randi_range(0, p.size() - 1)])


## Turn banked generic drops (save.part_drops [{rarity, source}]) into parts.
static func resolve_drops(s: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ev: Array = []
	var pd: Variant = s.get("part_drops", [])
	if not (pd is Array):
		s["part_drops"] = []
		return ev
	for x in (pd as Array):
		var d: Dictionary = x
		ev.append_array(grant(s, roll_id(rng, String(d.get("rarity", "common"))), String(d.get("source", "drop"))))
	s["part_drops"] = []
	return ev


static func can_level(s: Dictionary, uid: String) -> bool:
	var it: Dictionary = item(s, uid)
	if it.is_empty():
		return false
	var id: String = String(it["id"])
	return int(it["lvl"]) < PartDB.max_lvl(id) and int(s.get("scrap", 0)) >= PartDB.level_cost(id, int(it["lvl"]))


static func level_up(s: Dictionary, uid: String) -> Array:
	if not can_level(s, uid):
		return []
	var it: Dictionary = item(s, uid)
	var id: String = String(it["id"])
	var c: int = PartDB.level_cost(id, int(it["lvl"]))
	s["scrap"] = int(s["scrap"]) - c
	it["lvl"] = int(it["lvl"]) + 1
	return [{"t": "part_level", "uid": uid, "id": id, "lvl": int(it["lvl"]), "scrap": c}]


static func set_locked(s: Dictionary, uid: String, on: bool) -> bool:
	var it: Dictionary = item(s, uid)
	if it.is_empty():
		return false
	it["locked"] = on
	return true


## Salvage value: base + 50% of the Scrap invested, x salvage_mult.
static func salvage_value(s: Dictionary, uid: String) -> int:
	var it: Dictionary = item(s, uid)
	if it.is_empty():
		return 0
	var id: String = String(it["id"])
	var base: float = float(PartDB.SALVAGE_BASE.get(PartDB.rarity_of(id), 5)) + 0.5 * float(PartDB.invested(id, int(it["lvl"])))
	return int(round(base * salvage_mult(s)))


## Destroy a part for Scrap. Locked parts (and set specials) are refused;
## the part leaves every preset.
static func salvage(s: Dictionary, uid: String) -> Array:
	var it: Dictionary = item(s, uid)
	if it.is_empty() or bool(it["locked"]) or PartDB.is_special(String(it["id"])):
		return []
	var sc: int = _add_scrap(s, salvage_value(s, uid))
	items(s).erase(uid)
	_strip_uid(s, uid)
	return [{"t": "part_salvaged", "uid": uid, "id": String(it["id"]), "scrap": sc}]


static func _strip_uid(s: Dictionary, uid: String) -> void:
	var pr: Variant = Cores._block(s).get("presets", {})
	if not (pr is Dictionary):
		return
	for c in (pr as Dictionary).keys():
		for row in (pr as Dictionary)[c]:
			var r: Array = row
			for j in r.size():
				if String(r[j]) == uid:
					r[j] = ""


# ----------------------------------------------------------------- slots
## Normal slots open at a Core level (2..6).
static func slot_count(core_lvl: int) -> int:
	var n: int = 0
	for l in SLOT_LVLS:
		if core_lvl >= int(l):
			n += 1
	return n


static func slot_open(core_lvl: int, k: int) -> bool:
	if k == SET_SLOT:
		return core_lvl >= SET_SLOT_LVL
	return k >= 0 and k < slot_count(core_lvl)


## Can item `uid` sit in slot k (type rule only; locks are checked by equip)?
static func fits(s: Dictionary, uid: String, k: int) -> bool:
	var it: Dictionary = item(s, uid)
	if it.is_empty() or k < 0 or k >= N_SLOTS:
		return false
	var id: String = String(it["id"])
	if k == SET_SLOT:
		return PartDB.is_special(id)
	return PartDB.slot_of(id) == String(SLOT_TYPES[k])


static func preset_idx(s: Dictionary, core: String) -> int:
	var pi: Variant = Cores._block(s).get("preset_idx", {})
	return clampi(int((pi as Dictionary).get(core, 0)), 0, PRESETS - 1) if pi is Dictionary else 0


## The active preset row (7 uids) of a Core, created on demand.
static func preset(s: Dictionary, core: String, idx: int = -1) -> Array:
	var cb: Dictionary = Cores._block(s)
	if not (cb.get("presets", null) is Dictionary):
		cb["presets"] = {}
	var pr: Dictionary = cb["presets"]
	if not (pr.get(core, null) is Array) or (pr[core] as Array).size() != PRESETS:
		var rows: Array = []
		for k in PRESETS:
			var row: Array = []
			for j in N_SLOTS:
				row.append("")
			rows.append(row)
		pr[core] = rows
	var i: int = preset_idx(s, core) if idx < 0 else clampi(idx, 0, PRESETS - 1)
	return (pr[core] as Array)[i]


static func select_preset(s: Dictionary, core: String, idx: int) -> Array:
	if idx < 0 or idx >= PRESETS or not Cores.is_owned(s, core):
		return []
	var cb: Dictionary = Cores._block(s)
	if not (cb.get("preset_idx", null) is Dictionary):
		cb["preset_idx"] = {}
	(cb["preset_idx"] as Dictionary)[core] = idx
	preset(s, core)
	return [{"t": "preset_selected", "core": core, "idx": idx}]


## Install `uid` into slot k of the Core's active preset (free outside a run).
## Refused: unknown part, locked slot, wrong slot type. A part already in
## another slot of the same preset moves.
static func equip(s: Dictionary, core: String, k: int, uid: String) -> Array:
	if not Cores.is_owned(s, core) or not slot_open(Cores.level(s, core), k) or not fits(s, uid, k):
		return []
	var row: Array = preset(s, core)
	for j in row.size():
		if String(row[j]) == uid:
			row[j] = ""
	row[k] = uid
	var ev: Array = [{"t": "part_equipped", "core": core, "slot": k, "uid": uid, "id": String(item(s, uid)["id"])}]
	ev.append_array(check_sets(s, core))
	return ev


static func unequip(s: Dictionary, core: String, k: int) -> Array:
	if k < 0 or k >= N_SLOTS or not Cores.is_owned(s, core):
		return []
	var row: Array = preset(s, core)
	if String(row[k]) == "":
		return []
	var uid: String = String(row[k])
	row[k] = ""
	return [{"t": "part_unequipped", "core": core, "slot": k, "uid": uid}]


## Equipped items [{uid, id, lvl, stars, slot}] of the Core's active preset,
## only slots open at its current level.
static func equipped(s: Dictionary, core: String) -> Array:
	var out: Array = []
	var lv: int = Cores.level(s, core)
	var row: Array = preset(s, core)
	for k in row.size():
		var uid: String = String(row[k])
		if uid == "" or not slot_open(lv, k) or not fits(s, uid, k):
			continue
		var it: Dictionary = item(s, uid)
		out.append({"uid": uid, "id": String(it["id"]), "lvl": int(it["lvl"]), "stars": int(it["stars"]), "slot": k})
	return out


## Distinct equipped members per set: {set: n}.
static func set_counts(s: Dictionary, core: String) -> Dictionary:
	var seen: Dictionary = {}
	var out: Dictionary = {}
	for e in equipped(s, core):
		var id: String = String((e as Dictionary)["id"])
		var st: String = PartDB.set_of(id)
		if st == "" or PartDB.is_special(id) or seen.has(id):
			continue
		seen[id] = true
		out[st] = int(out.get(st, 0)) + 1
	return out


## Any 2-piece active on any owned Core (Tempest unlock condition).
static func any_set2(s: Dictionary) -> bool:
	for c in Cores.owned(s):
		for st in set_counts(s, String(c)).keys():
			if int(set_counts(s, String(c))[st]) >= 2:
				return true
	return false


## Record full sets (4 distinct members at once) and unlock their specials.
static func check_sets(s: Dictionary, core: String) -> Array:
	var ev: Array = []
	var b: Dictionary = _block(s)
	var sc: Array = b["sets_completed"]
	var su: Array = b["specials_unlocked"]
	var cnt: Dictionary = set_counts(s, core)
	for st in SetDB.IDS:
		if int(cnt.get(st, 0)) < 4 or sc.has(st):
			continue
		sc.append(st)
		ev.append({"t": "set_complete", "set": st})
		var sp: String = SetDB.special_of(String(st))
		if sp != "" and not su.has(sp):
			su.append(sp)
			ev.append({"t": "special_part_unlocked", "id": sp, "set": st})
			ev.append_array(grant(s, sp, "set"))
	return ev


# ------------------------------------------------------------- run fx
static func _add_fx(acc: Dictionary, fx: Dictionary, mult: float) -> void:
	for k in fx.keys():
		var key: String = String(k)
		var v: float = float(fx[k])
		if mult != 1.0 and not PartDB.INT_KEYS.has(key):
			v *= mult
		acc[key] = float(acc.get(key, 0.0)) + v


## The summed fx of a Core's equipped parts + active set bonuses (the
## TowerState hand-off). Plus scales with level and stars; minus never scales.
static func run_fx(s: Dictionary, core: String) -> Dictionary:
	var acc: Dictionary = {}
	for e in equipped(s, core):
		var ed: Dictionary = e
		var d: Dictionary = PartDB.get_def(String(ed["id"]))
		_add_fx(acc, d.get("plus", {}), PartDB.plus_mult(int(ed["lvl"]), int(ed["stars"])))
		_add_fx(acc, d.get("minus", {}), 1.0)
	var cnt: Dictionary = set_counts(s, core)
	for st in cnt.keys():
		var sd: Dictionary = SetDB.get_def(String(st))
		if int(cnt[st]) >= 2:
			_add_fx(acc, sd.get("two", {}), 1.0)
		if int(cnt[st]) >= 4:
			_add_fx(acc, sd.get("four", {}), 1.0)
	return acc


## Reforge (R6): every part level resets to 1; 50% of the invested Scrap is
## refunded. Items, stars, locks, set unlocks and specials are kept.
static func reforge_reset(s: Dictionary) -> int:
	var refund: int = 0
	for k in items(s).keys():
		var it: Dictionary = items(s)[k]
		refund += PartDB.invested(String(it["id"]), int(it["lvl"])) / 2
		it["lvl"] = 1
	_add_scrap(s, refund)
	return refund
