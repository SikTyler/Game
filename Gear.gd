extends RefCounted
## Gear meta rules (V2 P4): pure static operations over save.gear. Every op
## validates, spends, mutates and returns events ([] when refused); a matching
## `why_*` returns the refusal reason ("" = allowed) for buttons and tooltips.
## Meta randomness (rerolls, masterworks, merges, forging) draws from a stream
## keyed by the block's op counter `rs`, so the same save + the same clicks
## always give the same items.
##   save.gear = {items: {"uid": item}, next, rs, equipped: {weapon: uid,
##     sockets: [uid | 0]}, pity: {e, l, m}, bans: {weapon: [], module: []},
##     forged, offer: {} | {uid, idx, cands}, presets: []}
## Items are GearGen items (uid keys are strings: the save is JSON).

const GearGen := preload("res://GearGen.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const BrandDB := preload("res://data/BrandDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const ModuleDB := preload("res://data/ModuleDB.gd")
const NameDB := preload("res://data/NameDB.gd")
const Labs := preload("res://Labs.gd")
const Cores := preload("res://Cores.gd")
const Outpost := preload("res://Outpost.gd")
const CoreDB := preload("res://data/CoreDB.gd")

## Module sockets by Core level: 2 at L1, then +1 at each threshold (8 at L55).
const SOCKET_LVLS: Array = [1, 1, 5, 10, 18, 28, 40, 55]
const MAX_SOCKETS: int = 8
const INV_CAP: int = 200
const LVL_STEP: float = 0.05        # +5% item power per level
const MW_EVERY: int = 5             # a masterwork every 5 levels
const MW_BASE: float = 0.06         # +6% item power per masterwork
const JACKPOT: float = 0.15         # masterwork jackpot chance (research raises it to 0.30)
const UP_BASE: float = 120.0        # upgrade coins: 120 * RM * 1.17^(L-1)
const UP_GROWTH: float = 1.17
const RR_BASE: float = 10.0         # reroll Scrap: 10 * RM * 1.25^rr * 4^locks
const RR_GROWTH: float = 1.25
const RR_LOCK: float = 4.0
const IMPRINT_BASE: float = 50.0    # imprint Scrap: 50 * RM
const FORGE_COINS: float = 1500.0   # forge: 1500 * 1.08^min(forged, 40) coins + 40 Scrap
const FORGE_GROWTH: float = 1.08
const FORGE_RAMP_MAX: int = 40
const FORGE_SCRAP: int = 40
const MODULE_QUIRK: float = 0.5     # a module's brand quirk counts half
const PAINT_SLOTS: Array = ["p", "s", "g"]
const NAME_MAX: int = 28
const PRESETS_MAX: int = 4
const START_SEED: int = 0x5EED_C0DE


# ------------------------------------------------------------------ block

static func default_block() -> Dictionary:
	var so: Array = []
	so.resize(sockets_for(1))
	so.fill(0)
	var g: Dictionary = {"items": {}, "next": 1, "rs": 0, "equipped": {"weapon": 0, "sockets": so},
		"pity": {"e": 0, "l": 0, "m": 0}, "bans": {"weapon": [], "module": []}, "forged": 0, "offer": {}, "presets": []}
	var uid: int = _add(g, starter())
	(g["equipped"] as Dictionary)["weapon"] = uid
	return g


## The weapon every fresh save starts with: a Standard Issue Autocannon
## (Common, no perks, the quirk-free "standard" brand), so a fresh run plays
## exactly the base Core sheet.
static func starter() -> Dictionary:
	var it: Dictionary = make("weapon", "autocannon", "common")
	it["src"] = "start"
	return it


## A plain item (no perks unless given; "standard" brand: no quirk) for the
## starter, tests and tools. Deterministic per (kind, base, rarity).
static func make(kind: String, base: String, rar: String = "common", lvl: int = 1, perks: Array = [], brand: String = BrandDB.STANDARD) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash([START_SEED, kind, base, rar])
	var it: Dictionary = GearGen.roll(r, "start", {"kind": kind, "base": base, "rarity": rar, "brand": "kessler", "ilvl": 1}, {})
	var bd: Dictionary = BrandDB.get_def(brand)
	it["brand"] = brand
	it["perks"] = perks.duplicate(true)
	it["lvl"] = clampi(lvl, 1, max_lvl_of(rar))
	it["mw"] = it["lvl"] / MW_EVERY
	it["paint"] = {"p": String((bd["palette"] as Array)[0]), "s": String((bd["palette"] as Array)[1]), "g": String((bd["palette"] as Array)[2]), "pat": 0}
	it["name"] = NameDB.make(int(it["seed"]), bd["syl"], _base_name(kind, base), rar)
	it["new"] = false
	return it


## Coerce a raw (JSON) gear block: valid items only, ints cast, levels and
## tiers clamped, equipped uids re-checked against the inventory and the
## socket count of `core_lvl`. An empty inventory gets the starter weapon.
static func normalize_block(raw: Variant, core_lvl: int = 1) -> Dictionary:
	if not (raw is Dictionary):
		return default_block()
	var src: Dictionary = raw
	var g: Dictionary = {"items": {}, "next": 1, "rs": maxi(0, int(src.get("rs", 0))), "equipped": {"weapon": 0, "sockets": []},
		"pity": {"e": 0, "l": 0, "m": 0}, "bans": {"weapon": [], "module": []}, "forged": maxi(0, int(src.get("forged", 0))), "offer": {}, "presets": []}
	var top: int = 0
	var it_in: Dictionary = src.get("items", {}) if src.get("items", {}) is Dictionary else {}
	for k in it_in.keys():
		var it: Dictionary = normalize_item(it_in[k])
		var uid: int = int(String(k).to_int()) if String(k).is_valid_int() else 0
		if it.is_empty() or uid <= 0:
			continue
		it["uid"] = uid
		(g["items"] as Dictionary)[str(uid)] = it
		top = maxi(top, uid)
	g["next"] = maxi(top + 1, int(src.get("next", 1)))
	if _first_weapon(g) == 0:
		_add(g, starter())   # the Core always has a weapon to mount
	var pi: Dictionary = src.get("pity", {}) if src.get("pity", {}) is Dictionary else {}
	for p in ["e", "l", "m"]:
		(g["pity"] as Dictionary)[p] = clampi(int(pi.get(p, 0)), 0, int((RarityDB.PITY[p] as Dictionary)["hard"]))
	var bn: Dictionary = src.get("bans", {}) if src.get("bans", {}) is Dictionary else {}
	for kind in GearGen.KINDS:
		var out: Array = []
		for id in (bn.get(kind, []) if bn.get(kind, []) is Array else []):
			var sid: String = String(id)
			if not AffixDB.DEFS.has(sid) or out.has(sid) or out.size() >= 3:
				continue
			var pk: String = String((AffixDB.DEFS[sid] as Dictionary)["kind"])
			if pk == String(kind) or pk == "any":
				out.append(sid)
		(g["bans"] as Dictionary)[kind] = out
	# equipped: a weapon uid of a weapon item; sockets: unique module uids
	var eq: Dictionary = src.get("equipped", {}) if src.get("equipped", {}) is Dictionary else {}
	var w: int = int(eq.get("weapon", 0))
	if not _is_kind(g, w, "weapon"):
		w = _first_weapon(g)
	(g["equipped"] as Dictionary)["weapon"] = w
	var n: int = sockets_for(core_lvl)
	var so: Array = []
	var seen: Dictionary = {}
	var so_in: Array = eq.get("sockets", []) if eq.get("sockets", []) is Array else []
	for i in n:
		var u: int = int(so_in[i]) if i < so_in.size() else 0
		if u > 0 and _is_kind(g, u, "module") and not seen.has(u):
			seen[u] = true
			so.append(u)
		else:
			so.append(0)
	(g["equipped"] as Dictionary)["sockets"] = so
	var of: Dictionary = src.get("offer", {}) if src.get("offer", {}) is Dictionary else {}
	if not of.is_empty() and has_item(g, int(of.get("uid", 0))):
		var cands: Array = []
		for c in (of.get("cands", []) if of.get("cands", []) is Array else []):
			var pc: Dictionary = _perk(c)
			if not pc.is_empty():
				cands.append(pc)
		var it_o: Dictionary = get_item(g, int(of["uid"]))
		var idx: int = int(of.get("idx", -1))
		if not cands.is_empty() and idx >= 0 and idx < (it_o["perks"] as Array).size():
			g["offer"] = {"uid": int(of["uid"]), "idx": idx, "cands": cands}
	for pr in (src.get("presets", []) if src.get("presets", []) is Array else []):
		if pr is Dictionary and (g["presets"] as Array).size() < PRESETS_MAX:
			var pw: int = int((pr as Dictionary).get("weapon", 0))
			var ps: Array = []
			for u in ((pr as Dictionary).get("sockets", []) if (pr as Dictionary).get("sockets", []) is Array else []):
				ps.append(int(u))
			(g["presets"] as Array).append({"name": String((pr as Dictionary).get("name", "Loadout")).left(NAME_MAX), "weapon": pw, "sockets": ps})
	return g


## Coerce one raw item; {} if it is not a valid item.
static func normalize_item(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var r: Dictionary = raw
	var kind: String = String(r.get("kind", ""))
	var base: String = String(r.get("base", ""))
	if kind == "weapon" and not FrameDB.has(base):
		return {}
	if kind == "module" and not ModuleDB.has(base):
		return {}
	if kind != "weapon" and kind != "module":
		return {}
	var rar: String = String(r.get("rar", "common"))
	if not RarityDB.IDS.has(rar):
		rar = "common"
	var brand: String = String(r.get("brand", "kessler"))
	if not BrandDB.has(brand):
		brand = "kessler"
	var perks: Array = []
	var ids: Dictionary = {}
	for p in (r.get("perks", []) if r.get("perks", []) is Array else []):
		var pc: Dictionary = _perk(p)
		if pc.is_empty() or ids.has(pc["id"]):
			continue
		var pk: String = String((AffixDB.DEFS[pc["id"]] as Dictionary)["kind"])
		if pk != "any" and pk != kind:
			continue
		ids[pc["id"]] = true
		perks.append(pc)
	var bd: Dictionary = BrandDB.get_def(brand)
	var pa: Dictionary = r.get("paint", {}) if r.get("paint", {}) is Dictionary else {}
	var paint: Dictionary = {}
	for i in PAINT_SLOTS.size():
		paint[PAINT_SLOTS[i]] = _hex(pa.get(PAINT_SLOTS[i], ""), String((bd["palette"] as Array)[i]))
	paint["pat"] = clampi(int(pa.get("pat", 0)), 0, GearGen.PATTERNS - 1)
	var seed_v: int = int(r.get("seed", 0))
	var nm: String = _clean_name(r.get("name", ""))
	if nm == "":
		nm = NameDB.make(seed_v, bd["syl"], _base_name(kind, base), rar)
	return {
		"uid": maxi(0, int(r.get("uid", 0))), "kind": kind, "base": base, "brand": brand, "rar": rar,
		"ilvl": clampi(int(r.get("ilvl", 1)), 1, 999), "lvl": clampi(int(r.get("lvl", 1)), 1, max_lvl_of(rar)),
		"mw": maxi(0, int(r.get("mw", 0))), "seed": seed_v, "rr": maxi(0, int(r.get("rr", 0))), "perks": perks,
		"paint": paint, "name": nm, "fav": bool(r.get("fav", false)), "new": bool(r.get("new", false)),
		"src": String(r.get("src", "drop")),
	}


static func _perk(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var p: Dictionary = raw
	var id: String = String(p.get("id", ""))
	if not AffixDB.DEFS.has(id):
		return {}
	var out: Dictionary = {"id": id, "t": clampi(int(p.get("t", 1)), 1, AffixDB.MAX_TIER), "q": clampf(float(p.get("q", 0.5)), 0.0, 1.0), "lock": bool(p.get("lock", false))}
	if bool(p.get("sig", false)):
		out["sig"] = true
	if bool(p.get("mwp", false)):
		out["mwp"] = true
	return out


static func _hex(v: Variant, fallback: String) -> String:
	var s: String = String(v).strip_edges().trim_prefix("#").to_lower()
	return s if s.length() == 6 and s.is_valid_hex_number(false) else fallback


static func _clean_name(v: Variant) -> String:
	var s: String = String(v).strip_edges()
	var out: String = ""
	for ch in s:
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.left(NAME_MAX).strip_edges()


static func _base_name(kind: String, base: String) -> String:
	return String((FrameDB.get_def(base) if kind == "weapon" else ModuleDB.get_def(base)).get("name", base))


# ------------------------------------------------------------------ access

static func block(s: Dictionary) -> Dictionary:
	if not (s.get("gear", null) is Dictionary):
		s["gear"] = default_block()
	return s["gear"]


static func items(g: Dictionary) -> Dictionary:
	return g["items"]


static func has_item(g: Dictionary, uid: int) -> bool:
	return (g["items"] as Dictionary).has(str(uid))


static func get_item(g: Dictionary, uid: int) -> Dictionary:
	return (g["items"] as Dictionary).get(str(uid), {})


static func item(s: Dictionary, uid: int) -> Dictionary:
	return get_item(block(s), uid)


## Item uids, newest first (the inventory's default order).
static func uids(s: Dictionary, kind: String = "") -> Array:
	var out: Array = []
	for k in items(block(s)).keys():
		var it: Dictionary = items(block(s))[k]
		if kind == "" or String(it["kind"]) == kind:
			out.append(int(it["uid"]))
	out.sort()
	out.reverse()
	return out


static func count(s: Dictionary) -> int:
	return items(block(s)).size()


static func _is_kind(g: Dictionary, uid: int, kind: String) -> bool:
	return uid > 0 and has_item(g, uid) and String(get_item(g, uid)["kind"]) == kind


static func _first_weapon(g: Dictionary) -> int:
	var best: int = 0
	for k in (g["items"] as Dictionary).keys():
		var it: Dictionary = (g["items"] as Dictionary)[k]
		if String(it["kind"]) == "weapon" and (best == 0 or int(it["uid"]) < best):
			best = int(it["uid"])
	return best


## Add an item (assigns its uid). Returns the uid.
static func _add(g: Dictionary, it: Dictionary) -> int:
	var uid: int = int(g["next"])
	g["next"] = uid + 1
	it["uid"] = uid
	(g["items"] as Dictionary)[str(uid)] = it
	return uid


## Add a found / forged item to the save's inventory (0 if the inventory is full).
static func add_item(s: Dictionary, it: Dictionary) -> int:
	var g: Dictionary = block(s)
	if items(g).size() >= INV_CAP:
		return 0
	return _add(g, it)


static func _remove(g: Dictionary, uid: int) -> void:
	(g["items"] as Dictionary).erase(str(uid))
	var so: Array = (g["equipped"] as Dictionary)["sockets"]
	for i in so.size():
		if int(so[i]) == uid:
			so[i] = 0
	if int((g["equipped"] as Dictionary)["weapon"]) == uid:
		(g["equipped"] as Dictionary)["weapon"] = _first_weapon(g)
	var of: Dictionary = g.get("offer", {})
	if not of.is_empty() and int(of.get("uid", 0)) == uid:
		g["offer"] = {}


static func is_equipped(s: Dictionary, uid: int) -> bool:
	var eq: Dictionary = block(s)["equipped"]
	return int(eq["weapon"]) == uid or (eq["sockets"] as Array).has(uid)


## A meta RNG for one op; advances the block's op counter.
static func _rng(g: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(["gear", int(g.get("rs", 0))])
	g["rs"] = int(g.get("rs", 0)) + 1
	return r


static func _rm(it: Dictionary) -> float:
	return float(RarityDB.get_def(String(it["rar"]))["rm"])


static func max_lvl_of(rar: String) -> int:
	return int(RarityDB.get_def(rar)["max_lvl"])


static func _lab(s: Dictionary, id: String) -> int:
	return Labs.level(s, id)


# ------------------------------------------------------------------ numbers

## Item power multiplier on its base sheet: rarity base x (1 + 5%/level) x 1.06^masterworks.
static func power(it: Dictionary) -> float:
	return float(RarityDB.get_def(String(it["rar"]))["base"]) * (1.0 + LVL_STEP * float(int(it["lvl"]) - 1)) * pow(1.0 + MW_BASE, float(int(it["mw"])))


## Module sockets open at Core level `lvl`.
static func sockets_for(lvl: int) -> int:
	var n: int = 0
	for v in SOCKET_LVLS:
		if lvl >= int(v):
			n += 1
	return mini(n, MAX_SOCKETS)


## Core level that opens socket number `k` (0-based); -1 if none.
static func socket_level(k: int) -> int:
	return int(SOCKET_LVLS[k]) if k >= 0 and k < SOCKET_LVLS.size() else -1


static func lock_slots(s: Dictionary) -> int:
	return 1 + mini(2, _lab(s, "stabilizer"))


static func ban_slots(s: Dictionary) -> int:
	return mini(3, _lab(s, "blacklist"))


static func reroll_options(s: Dictionary) -> int:
	return 2 + mini(1, _lab(s, "enchanters_eye"))


static func jackpot_chance(s: Dictionary) -> float:
	return minf(0.30, JACKPOT + 0.05 * float(_lab(s, "masterwork_odds")))


static func locks_on(it: Dictionary) -> int:
	var n: int = 0
	for p in it["perks"]:
		if bool((p as Dictionary).get("lock", false)):
			n += 1
	return n


## Upgrade coins; with a save, Greater Calibration research cuts 5% / level.
static func upgrade_cost(it: Dictionary, s: Dictionary = {}) -> int:
	var disc: float = 0.05 * float(mini(5, _lab(s, "greater_cal"))) if not s.is_empty() else 0.0
	return int(round(UP_BASE * _rm(it) * pow(UP_GROWTH, float(int(it["lvl"]) - 1)) * (1.0 - disc)))


## Reroll Scrap; with a save, Reroll Discount research cuts 8% / level.
static func reroll_cost(it: Dictionary, s: Dictionary = {}) -> int:
	var disc: float = 0.08 * float(mini(5, _lab(s, "reroll_disc"))) if not s.is_empty() else 0.0
	return int(round(RR_BASE * _rm(it) * pow(RR_GROWTH, float(int(it["rr"]))) * pow(RR_LOCK, float(locks_on(it))) * (1.0 - disc)))


static func imprint_cost(it: Dictionary) -> int:
	return int(round(IMPRINT_BASE * _rm(it)))


## Salvage Scrap; with a save, Reclamation research adds 10% / level.
static func salvage_value(it: Dictionary, s: Dictionary = {}) -> int:
	var bonus: float = 0.10 * float(mini(5, _lab(s, "reclaim"))) if not s.is_empty() else 0.0
	return int(round(float(RarityDB.get_def(String(it["rar"]))["salvage"]) * (1.0 + 0.1 * float(int(it["lvl"]) - 1)) * (1.0 + bonus)))


static func forge_cost(s: Dictionary) -> Dictionary:
	var f: int = mini(int(block(s).get("forged", 0)), FORGE_RAMP_MAX)
	var disc: float = clampf(forge_discount(s), 0.0, 0.5)
	return {"coins": int(round(FORGE_COINS * pow(FORGE_GROWTH, float(f)) * (1.0 - disc))), "scrap": FORGE_SCRAP}


## Forge cost discount: the Forge Works building (-2% per level, max -50%).
static func forge_discount(s: Dictionary) -> float:
	if not (s.get("outpost", null) is Dictionary):
		return 0.0
	return clampf(float(Outpost.core_bonus(s).get("forge_disc", 0.0)), 0.0, 0.5)


## Rarity luck of Forge rolls (Appraisal research, P8).
static func forge_luck(s: Dictionary) -> float:
	return float(_lab(s, "appraisal"))


## Item level of a Forge roll (perk tier = 1 + ilvl / 25, capped at T5).
static func forge_ilvl(s: Dictionary) -> int:
	return 10 + 2 * Cores.level(s)


# ------------------------------------------------------------------ equip

static func why_equip(s: Dictionary, uid: int, slot: int = -1) -> String:
	var g: Dictionary = block(s)
	if not has_item(g, uid):
		return "No such item"
	var it: Dictionary = get_item(g, uid)
	if String(it["kind"]) == "module":
		var n: int = sockets_for(Cores.level(s))
		if slot >= n:
			return "Socket opens at Core level %d" % socket_level(slot)
		if slot < -1:
			return "No such socket"
	return ""


## Equip a weapon (slot ignored) or a module (slot -1: the first empty socket,
## else that socket; a module already socketed elsewhere moves).
static func equip(s: Dictionary, uid: int, slot: int = -1) -> Array:
	if why_equip(s, uid, slot) != "":
		return []
	var g: Dictionary = block(s)
	var it: Dictionary = get_item(g, uid)
	it["new"] = false
	var eq: Dictionary = g["equipped"]
	if String(it["kind"]) == "weapon":
		var old: int = int(eq["weapon"])
		eq["weapon"] = uid
		return [{"t": "gear_equip", "uid": uid, "kind": "weapon", "old": old}]
	_fit_sockets(s)
	var so: Array = eq["sockets"]
	if slot < 0:
		slot = so.find(uid)
		if slot < 0:
			slot = so.find(0)
		if slot < 0:
			return []
	var old_m: int = int(so[slot])
	var from: int = so.find(uid)
	if from >= 0:
		so[from] = old_m   # swap
	so[slot] = uid
	return [{"t": "gear_equip", "uid": uid, "kind": "module", "slot": slot, "old": old_m}]


static func unequip(s: Dictionary, slot: int) -> Array:
	var so: Array = (block(s)["equipped"] as Dictionary)["sockets"]
	if slot < 0 or slot >= so.size() or int(so[slot]) == 0:
		return []
	var old: int = int(so[slot])
	so[slot] = 0
	return [{"t": "gear_unequip", "uid": old, "slot": slot}]


# ------------------------------------------------------------------ presets
## V2 P8b Loadout Presets: slot k (< Labs.preset_slots) stores the equipped
## Weapon + sockets; loading equips what still exists (missing items leave
## their socket empty).
static func save_preset(s: Dictionary, k: int) -> Array:
	if k < 0 or k >= mini(PRESETS_MAX, Labs.preset_slots(s)):
		return []
	var g: Dictionary = block(s)
	var pr: Array = g["presets"]
	while pr.size() <= k:
		pr.append({})
	var eq: Dictionary = g["equipped"]
	pr[k] = {"name": "Loadout %d" % (k + 1), "weapon": int(eq["weapon"]), "sockets": (eq["sockets"] as Array).duplicate()}
	return [{"t": "preset_saved", "k": k}]


static func preset(s: Dictionary, k: int) -> Dictionary:
	var pr: Array = block(s)["presets"]
	return pr[k] if k >= 0 and k < pr.size() and pr[k] is Dictionary else {}


static func load_preset(s: Dictionary, k: int) -> Array:
	if k < 0 or k >= mini(PRESETS_MAX, Labs.preset_slots(s)):
		return []
	var p: Dictionary = preset(s, k)
	if p.is_empty() or not p.has("weapon"):
		return []
	var g: Dictionary = block(s)
	var eq: Dictionary = g["equipped"]
	if has_item(g, int(p["weapon"])) and String(get_item(g, int(p["weapon"]))["kind"]) == "weapon":
		eq["weapon"] = int(p["weapon"])
	_fit_sockets(s)
	var so: Array = eq["sockets"]
	var ps: Array = p.get("sockets", [])
	var missing: int = 0
	for i in so.size():
		var u: int = int(ps[i]) if i < ps.size() else 0
		if u != 0 and has_item(g, u) and String(get_item(g, u)["kind"]) == "module" and not so.slice(0, i).has(u):
			so[i] = u
		else:
			if u != 0:
				missing += 1
			so[i] = 0
	return [{"t": "preset_loaded", "k": k, "missing": missing}]


## V2 P8b Bulk Upgrade: up to n levels (0 = until max or broke).
static func upgrade_n(s: Dictionary, uid: int, n: int) -> Array:
	if Labs.level(s, "bulk_upgrade") <= 0:
		return upgrade(s, uid)
	var ev: Array = []
	var k: int = 0
	while (n <= 0 or k < n) and k < 200:
		var e1: Array = upgrade(s, uid)
		if e1.is_empty():
			break
		ev.append_array(e1)
		k += 1
	return ev


## Grow / shrink the socket list to the Core level's count.
static func _fit_sockets(s: Dictionary) -> void:
	var so: Array = (block(s)["equipped"] as Dictionary)["sockets"]
	var n: int = sockets_for(Cores.level(s))
	while so.size() < n:
		so.append(0)
	while so.size() > n:
		so.pop_back()


## The equipped weapon (the starter if none). Read-only: never writes the save.
static func weapon(s: Dictionary) -> Dictionary:
	var g: Variant = s.get("gear", null)
	if not (g is Dictionary):
		return starter()
	var it: Dictionary = get_item(g, int(((g as Dictionary).get("equipped", {}) as Dictionary).get("weapon", 0)))
	return it if not it.is_empty() else starter()


## The socketed modules the Core's level has opened, in socket order. Read-only.
static func modules(s: Dictionary) -> Array:
	var out: Array = []
	var g: Variant = s.get("gear", null)
	if not (g is Dictionary):
		return out
	var so: Array = ((g as Dictionary).get("equipped", {}) as Dictionary).get("sockets", [])
	var n: int = mini(so.size(), sockets_for(Cores.level(s)))
	for i in n:
		var it: Dictionary = get_item(g, int(so[i]))
		if not it.is_empty():
			out.append(it)
	return out


# ------------------------------------------------------------------ upgrade

static func why_upgrade(s: Dictionary, uid: int) -> String:
	var it: Dictionary = item(s, uid)
	if it.is_empty():
		return "No such item"
	if int(it["lvl"]) >= max_lvl_of(String(it["rar"])):
		return "Max level - merge to raise the cap"
	if int(s.get("coins", 0)) < upgrade_cost(it, s):
		return "Need %d coins" % upgrade_cost(it, s)
	return ""


## +1 level for coins. Every 5th level is a masterwork: +6% power and +1 tier
## on a random perk; a jackpot (15%+) gives +2 tiers or a bonus perk instead.
static func upgrade(s: Dictionary, uid: int) -> Array:
	if why_upgrade(s, uid) != "":
		return []
	var g: Dictionary = block(s)
	var it: Dictionary = get_item(g, uid)
	var c: int = upgrade_cost(it, s)
	s["coins"] = int(s["coins"]) - c
	it["lvl"] = int(it["lvl"]) + 1
	var ev: Dictionary = {"t": "gear_upgrade", "uid": uid, "lvl": int(it["lvl"]), "coins": c}
	var ms: int = int(it["lvl"]) / MW_EVERY
	if int(it["lvl"]) % MW_EVERY == 0 and ms > int(it["mw"]):
		it["mw"] = ms
		ev["mw"] = ms
		var r: RandomNumberGenerator = _rng(g)
		var jack: bool = r.randf() < jackpot_chance(s)
		ev["jackpot"] = jack
		var bonus: bool = false
		for p in it["perks"]:
			bonus = bonus or bool((p as Dictionary).get("mwp", false))
		if jack and not bonus:
			var np: Array = GearGen.roll_perks(r, String(it["kind"]), String(it["base"]), 1, AffixDB.tier_for(int(it["ilvl"]), AffixDB.FORGE_TIER_CAP), it["perks"], (g["bans"] as Dictionary).get(String(it["kind"]), []))
			if not np.is_empty():
				(np[0] as Dictionary)["mwp"] = true
				(it["perks"] as Array).append(np[0])
				ev["new_perk"] = (it["perks"] as Array).size() - 1
				return [ev]
		var ps: Array = it["perks"]
		if not ps.is_empty():
			var k: int = r.randi_range(0, ps.size() - 1)
			var p: Dictionary = ps[k]
			var up: int = 2 if jack else 1
			p["t"] = mini(AffixDB.MAX_TIER, int(p["t"]) + up)
			ev["perk"] = k
			ev["tiers"] = up
	return [ev]


# ------------------------------------------------------------------ reroll

static func why_reroll(s: Dictionary, uid: int, idx: int) -> String:
	var g: Dictionary = block(s)
	var it: Dictionary = get_item(g, uid)
	if it.is_empty():
		return "No such item"
	if not (g.get("offer", {}) as Dictionary).is_empty():
		return "Choose from the open reroll first"
	if idx < 0 or idx >= (it["perks"] as Array).size():
		return "No such perk"
	var p: Dictionary = (it["perks"] as Array)[idx]
	if bool(p.get("lock", false)):
		return "Locked perks don't reroll"
	if bool(p.get("sig", false)):
		return "A signature perk can't be rerolled"
	if int(s.get("scrap", 0)) < reroll_cost(it, s):
		return "Need %d Scrap" % reroll_cost(it, s)
	return ""


## Pay Scrap to roll candidates for one perk (2, or 3 with research; never
## above T5). The offer persists in the save until reroll_choose().
static func reroll(s: Dictionary, uid: int, idx: int) -> Array:
	if why_reroll(s, uid, idx) != "":
		return []
	var g: Dictionary = block(s)
	var it: Dictionary = get_item(g, uid)
	var c: int = reroll_cost(it, s)
	s["scrap"] = int(s["scrap"]) - c
	it["rr"] = int(it["rr"]) + 1
	var cur: Dictionary = (it["perks"] as Array)[idx]
	var t: int = clampi(maxi(int(cur["t"]), AffixDB.tier_for(int(it["ilvl"]), AffixDB.FORGE_TIER_CAP)), 1, AffixDB.FORGE_TIER_CAP)
	var r: RandomNumberGenerator = _rng(g)
	var cands: Array = GearGen.roll_perks(r, String(it["kind"]), String(it["base"]), reroll_options(s), t, it["perks"], (g["bans"] as Dictionary).get(String(it["kind"]), []))
	g["offer"] = {"uid": uid, "idx": idx, "cands": cands}
	return [{"t": "gear_reroll", "uid": uid, "idx": idx, "scrap": c, "cands": cands.duplicate(true)}]


## Resolve the open reroll: k = -1 keeps the current perk, else takes cands[k].
static func reroll_choose(s: Dictionary, k: int) -> Array:
	var g: Dictionary = block(s)
	var of: Dictionary = g.get("offer", {})
	if of.is_empty():
		return []
	var cands: Array = of["cands"]
	if k >= cands.size() or k < -1:
		return []
	var it: Dictionary = get_item(g, int(of["uid"]))
	g["offer"] = {}
	if it.is_empty():
		return []
	if k == -1:
		return [{"t": "gear_reroll_keep", "uid": int(of["uid"]), "idx": int(of["idx"])}]
	var np: Dictionary = (cands[k] as Dictionary).duplicate()
	var old: Dictionary = (it["perks"] as Array)[int(of["idx"])]
	if bool(old.get("mwp", false)):
		np["mwp"] = true
	(it["perks"] as Array)[int(of["idx"])] = np
	return [{"t": "gear_reroll_take", "uid": int(of["uid"]), "idx": int(of["idx"]), "perk": np.duplicate()}]


# ------------------------------------------------------------------ lock / ban

static func why_lock(s: Dictionary, uid: int, idx: int, on: bool) -> String:
	var it: Dictionary = item(s, uid)
	if it.is_empty():
		return "No such item"
	if idx < 0 or idx >= (it["perks"] as Array).size():
		return "No such perk"
	if on and not bool(((it["perks"] as Array)[idx] as Dictionary).get("lock", false)) and locks_on(it) >= lock_slots(s):
		return "Lock slots full (%d) - Stabilizer research adds more" % lock_slots(s)
	return ""


static func lock(s: Dictionary, uid: int, idx: int, on: bool) -> Array:
	if why_lock(s, uid, idx, on) != "":
		return []
	var p: Dictionary = (item(s, uid)["perks"] as Array)[idx]
	if bool(p.get("lock", false)) == on:
		return []
	p["lock"] = on
	return [{"t": "gear_lock", "uid": uid, "idx": idx, "on": on}]


static func why_ban(s: Dictionary, kind: String, id: String, on: bool) -> String:
	if not GearGen.KINDS.has(kind) or not AffixDB.DEFS.has(id):
		return "No such perk"
	var k2: String = String((AffixDB.DEFS[id] as Dictionary)["kind"])
	if k2 != kind and k2 != "any":
		return "That perk can't roll on this kind"
	var bl: Array = (block(s)["bans"] as Dictionary)[kind]
	if on and not bl.has(id) and bl.size() >= ban_slots(s):
		return "Ban slots full (%d) - Blacklist research adds more" % ban_slots(s) if ban_slots(s) > 0 else "Blacklist research unlocks bans"
	return ""


static func ban(s: Dictionary, kind: String, id: String, on: bool) -> Array:
	if why_ban(s, kind, id, on) != "":
		return []
	var bl: Array = (block(s)["bans"] as Dictionary)[kind]
	if on == bl.has(id):
		return []
	if on:
		bl.append(id)
	else:
		bl.erase(id)
	return [{"t": "gear_ban", "kind": kind, "id": id, "on": on}]


# ------------------------------------------------------------------ merge

static func why_merge(s: Dictionary, uids_in: Array, base_uid: int) -> String:
	var g: Dictionary = block(s)
	if uids_in.size() != 3:
		return "Merge takes 3 items"
	var seen: Dictionary = {}
	var kind: String = ""
	var rar: String = ""
	for u in uids_in:
		var it: Dictionary = get_item(g, int(u))
		if it.is_empty() or seen.has(int(u)):
			return "Pick 3 different items"
		seen[int(u)] = true
		if kind == "":
			kind = String(it["kind"])
			rar = String(it["rar"])
		elif String(it["kind"]) != kind:
			return "Same kind only (weapons or modules)"
		elif String(it["rar"]) != rar:
			return "Same rarity only"
		if int(u) != base_uid and bool(it.get("fav", false)):
			return "A favourite can't be merged away"
	if not seen.has(base_uid):
		return "The base must be one of the three"
	var nx: String = RarityDB.next(rar)
	if nx == "" or nx == "exotic":
		return "Exotics only drop"
	if nx == "mythic" and _lab(s, "mythic_fusion") <= 0:
		return "Mythic Fusion research needed"
	return ""


## The perk choices a merge offers when the new rarity adds a slot: up to two
## of the sacrifices' perks (best first, not already on the base, not banned)
## plus one fresh roll. [] when the rarity adds no slot (+1 tier instead).
static func merge_choices(s: Dictionary, uids_in: Array, base_uid: int) -> Array:
	if why_merge(s, uids_in, base_uid) != "":
		return []
	var g: Dictionary = block(s)
	var base: Dictionary = get_item(g, base_uid)
	var nx: String = RarityDB.next(String(base["rar"]))
	if int(RarityDB.get_def(nx)["perks"]) <= int(RarityDB.get_def(String(base["rar"]))["perks"]):
		return []
	var have: Dictionary = {}
	for p in base["perks"]:
		have[String((p as Dictionary)["id"])] = true
	var bans: Array = (g["bans"] as Dictionary).get(String(base["kind"]), [])
	var from: Array = []
	for u in uids_in:
		if int(u) == base_uid:
			continue
		for p in get_item(g, int(u))["perks"]:
			var pd: Dictionary = p
			var id: String = String(pd["id"])
			if have.has(id) or bans.has(id) or not AffixDB.pool(String(base["kind"]), String(base["base"])).has(id):
				continue
			from.append(pd)
	from.sort_custom(func(a, b): return int(a["t"]) * 10 + float(a["q"]) > int(b["t"]) * 10 + float(b["q"]))
	var out: Array = []
	for pd in from:
		if out.size() >= 2:
			break
		var dup: bool = false
		for o in out:
			dup = dup or String((o as Dictionary)["id"]) == String(pd["id"])
		if not dup:
			var c: Dictionary = {"id": String(pd["id"]), "t": mini(int(pd["t"]), AffixDB.FORGE_TIER_CAP), "q": float(pd["q"]), "lock": false}
			out.append(c)
	# the fresh roll is peeked from the next op's stream (merge() uses the same draw)
	var r := RandomNumberGenerator.new()
	r.seed = hash(["gear", int(g.get("rs", 0))])
	var taken: Array = (base["perks"] as Array).duplicate()
	taken.append_array(out)
	var fresh: Array = GearGen.roll_perks(r, String(base["kind"]), String(base["base"]), 1, AffixDB.tier_for(int(base["ilvl"]), AffixDB.FORGE_TIER_CAP), taken, bans)
	out.append_array(fresh)
	return out


## Merge 3 same-kind, same-rarity items into the base: rarity +1; a new perk
## slot (choice indexes merge_choices) or +1 tier on its weakest perk (to T5);
## level = half the best input's; the other two are consumed.
static func merge(s: Dictionary, uids_in: Array, base_uid: int, choice: int = 0) -> Array:
	if why_merge(s, uids_in, base_uid) != "":
		return []
	var g: Dictionary = block(s)
	var choices: Array = merge_choices(s, uids_in, base_uid)
	_rng(g)   # consume the stream merge_choices peeked
	var base: Dictionary = get_item(g, base_uid)
	var top_lvl: int = 1
	for u in uids_in:
		top_lvl = maxi(top_lvl, int(get_item(g, int(u))["lvl"]))
	var was_weapon: bool = false
	for u in uids_in:
		if int(u) != base_uid:
			was_weapon = was_weapon or int((g["equipped"] as Dictionary)["weapon"]) == int(u)
			_remove(g, int(u))
	var old_r: String = String(base["rar"])
	base["rar"] = RarityDB.next(old_r)
	base["lvl"] = clampi(top_lvl / 2, 1, max_lvl_of(String(base["rar"])))
	base["new"] = false
	var ev: Dictionary = {"t": "gear_merge", "uid": base_uid, "from": old_r, "to": String(base["rar"]), "lvl": int(base["lvl"]), "used": uids_in.duplicate()}
	if not choices.is_empty():
		var pk: Dictionary = (choices[clampi(choice, 0, choices.size() - 1)] as Dictionary).duplicate()
		pk["lock"] = false
		(base["perks"] as Array).append(pk)
		ev["perk"] = pk.duplicate()
	else:
		var low: int = -1
		var ps: Array = base["perks"]
		for i in ps.size():
			var t: int = int((ps[i] as Dictionary)["t"])
			if t < AffixDB.FORGE_TIER_CAP and (low < 0 or t < int((ps[low] as Dictionary)["t"])):
				low = i
		if low >= 0:
			(ps[low] as Dictionary)["t"] = int((ps[low] as Dictionary)["t"]) + 1
			ev["tier_up"] = low
	if String(base["rar"]) == "exotic" or base["name"] == NameDB.make(int(base["seed"]), BrandDB.get_def(String(base["brand"]))["syl"], _base_name(String(base["kind"]), String(base["base"])), old_r):
		base["name"] = NameDB.make(int(base["seed"]), BrandDB.get_def(String(base["brand"]))["syl"], _base_name(String(base["kind"]), String(base["base"])), String(base["rar"]))
	if was_weapon and String(base["kind"]) == "weapon":
		(g["equipped"] as Dictionary)["weapon"] = base_uid
	return [ev]


# ------------------------------------------------------------------ imprint / salvage

static func why_imprint(s: Dictionary, a_uid: int, b_uid: int, b_idx: int, a_idx: int) -> String:
	var g: Dictionary = block(s)
	var a: Dictionary = get_item(g, a_uid)
	var b: Dictionary = get_item(g, b_uid)
	if a.is_empty() or b.is_empty() or a_uid == b_uid:
		return "Pick a target and a different donor"
	if String(a["kind"]) != String(b["kind"]):
		return "Same kind only"
	if bool(b.get("fav", false)):
		return "A favourite can't be consumed"
	if int((g["equipped"] as Dictionary)["weapon"]) == b_uid:
		return "Unequip the donor first"
	if b_idx < 0 or b_idx >= (b["perks"] as Array).size() or a_idx < 0 or a_idx >= (a["perks"] as Array).size():
		return "No such perk"
	var bp: Dictionary = (b["perks"] as Array)[b_idx]
	var ap: Dictionary = (a["perks"] as Array)[a_idx]
	if bool(ap.get("lock", false)) or bool(ap.get("sig", false)):
		return "That slot is locked"
	if not AffixDB.pool(String(a["kind"]), String(a["base"])).has(String(bp["id"])):
		return "That perk can't roll on this frame"
	for i in (a["perks"] as Array).size():
		if i != a_idx and String(((a["perks"] as Array)[i] as Dictionary)["id"]) == String(bp["id"]):
			return "The target already has that perk"
	if int(s.get("scrap", 0)) < imprint_cost(a):
		return "Need %d Scrap" % imprint_cost(a)
	return ""


## Destroy item B and copy its perk b_idx over item A's perk a_idx.
static func imprint(s: Dictionary, a_uid: int, b_uid: int, b_idx: int, a_idx: int) -> Array:
	if why_imprint(s, a_uid, b_uid, b_idx, a_idx) != "":
		return []
	var g: Dictionary = block(s)
	var a: Dictionary = get_item(g, a_uid)
	var b: Dictionary = get_item(g, b_uid)
	var c: int = imprint_cost(a)
	s["scrap"] = int(s["scrap"]) - c
	var np: Dictionary = ((b["perks"] as Array)[b_idx] as Dictionary).duplicate()
	np["lock"] = false
	np.erase("sig")
	np.erase("mwp")
	if bool(((a["perks"] as Array)[a_idx] as Dictionary).get("mwp", false)):
		np["mwp"] = true
	(a["perks"] as Array)[a_idx] = np
	_remove(g, b_uid)
	return [{"t": "gear_imprint", "uid": a_uid, "donor": b_uid, "idx": a_idx, "perk": np.duplicate(), "scrap": c}]


static func why_salvage(s: Dictionary, uid: int) -> String:
	var g: Dictionary = block(s)
	var it: Dictionary = get_item(g, uid)
	if it.is_empty():
		return "No such item"
	if bool(it.get("fav", false)):
		return "Unfavourite it first"
	if int((g["equipped"] as Dictionary)["weapon"]) == uid:
		return "The equipped weapon can't be salvaged"
	return ""


static func salvage(s: Dictionary, uid: int) -> Array:
	if why_salvage(s, uid) != "":
		return []
	var g: Dictionary = block(s)
	var v: int = salvage_value(get_item(g, uid), s)
	_remove(g, uid)
	s["scrap"] = int(s.get("scrap", 0)) + v
	return [{"t": "gear_salvage", "uid": uid, "scrap": v}]


# ------------------------------------------------------------------ forge

static func why_forge(s: Dictionary, kind: String, base: String, brand: String = "") -> String:
	if kind == "weapon" and not FrameDB.has(base):
		return "Pick a frame"
	if kind == "module" and not ModuleDB.has(base):
		return "Pick a module"
	if kind != "weapon" and kind != "module":
		return "Pick a frame"
	if brand != "" and (not BrandDB.has(brand) or _lab(s, "brand_contracts") <= 0):
		return "Brand Contracts research needed"
	if count(s) >= INV_CAP:
		return "Inventory full - salvage something"
	var c: Dictionary = forge_cost(s)
	if int(s.get("coins", 0)) < int(c["coins"]):
		return "Need %d coins" % int(c["coins"])
	if int(s.get("scrap", 0)) < int(c["scrap"]):
		return "Need %d Scrap" % int(c["scrap"])
	return ""


## Forge a new item of a chosen frame / module: Forge odds (Legendary at best),
## pity advances, perk tiers from forge_ilvl capped at T5.
static func forge_new(s: Dictionary, kind: String, base: String, brand: String = "") -> Array:
	if why_forge(s, kind, base, brand) != "":
		return []
	var g: Dictionary = block(s)
	var c: Dictionary = forge_cost(s)
	s["coins"] = int(s["coins"]) - int(c["coins"])
	s["scrap"] = int(s["scrap"]) - int(c["scrap"])
	g["forged"] = int(g.get("forged", 0)) + 1
	var opts: Dictionary = {"kind": kind, "base": base, "ilvl": forge_ilvl(s), "luck": forge_luck(s), "bans": g["bans"]}
	if brand != "":
		opts["brand"] = brand
	var it: Dictionary = GearGen.roll(_rng(g), "forge", opts, g["pity"])
	var uid: int = _add(g, it)
	return [{"t": "gear_forge", "uid": uid, "rar": String(it["rar"]), "kind": kind, "base": base, "coins": int(c["coins"]), "scrap": int(c["scrap"])}]


# ------------------------------------------------------------------ cosmetic

static func paint(s: Dictionary, uid: int, slot: String, hex: String) -> Array:
	var it: Dictionary = item(s, uid)
	if it.is_empty():
		return []
	var pa: Dictionary = it["paint"]
	if slot == "pat":
		pa["pat"] = clampi(hex.to_int(), 0, GearGen.PATTERNS - 1)
	elif PAINT_SLOTS.has(slot):
		var h: String = _hex(hex, "")
		if h == "":
			return []
		pa[slot] = h
	else:
		return []
	return [{"t": "gear_paint", "uid": uid, "slot": slot}]


static func rename(s: Dictionary, uid: int, nm: String) -> Array:
	var it: Dictionary = item(s, uid)
	var c: String = _clean_name(nm)
	if it.is_empty() or c == "":
		return []
	it["name"] = c
	return [{"t": "gear_rename", "uid": uid, "name": c}]


static func set_fav(s: Dictionary, uid: int, on: bool) -> Array:
	var it: Dictionary = item(s, uid)
	if it.is_empty() or bool(it.get("fav", false)) == on:
		return []
	it["fav"] = on
	return [{"t": "gear_fav", "uid": uid, "on": on}]


static func mark_seen(s: Dictionary, uid: int) -> void:
	var it: Dictionary = item(s, uid)
	if not it.is_empty():
		it["new"] = false


static func new_count(s: Dictionary) -> int:
	var n: int = 0
	for k in items(block(s)).keys():
		if bool((items(block(s))[k] as Dictionary).get("new", false)):
			n += 1
	return n


# ------------------------------------------------------------------ run hand-off

## One perk's value (scaled like AffixDB.value).
static func perk_value(p: Dictionary) -> float:
	return AffixDB.value(String(p["id"]), int(p["t"]), float(p["q"]))


## A module's built-in fx at its rarity / level: numeric values scale with
## power(); count values (ModuleDB.INT_KEYS) gain +1 per 2 masterworks; a
## trade-off's negative part never scales.
static func module_fx(it: Dictionary) -> Dictionary:
	var d: Dictionary = ModuleDB.get_def(String(it["base"]))
	var out: Dictionary = {}
	var pw: float = power(it)
	for k in (d.get("fx", {}) as Dictionary).keys():
		var v: float = float(d["fx"][k])
		if ModuleDB.INT_KEYS.has(k):
			out[k] = v + float(int(it["mw"]) / 2)
		elif v > 0.0:
			out[k] = v * pw
		else:
			out[k] = v
	return out


## Summed gear fx for a run (TowerState.pfx): the equipped weapon's perks and
## brand quirk, then each socketed module's built-in fx, perks and half quirk.
static func run_fx(s: Dictionary) -> Dictionary:
	var fx: Dictionary = {}
	var w: Dictionary = weapon(s)
	_item_fx(fx, w, 1.0)
	for m in modules(s):
		var mfx: Dictionary = module_fx(m)
		for k in mfx.keys():
			fx[k] = float(fx.get(k, 0.0)) + float(mfx[k])
		_item_fx(fx, m, MODULE_QUIRK)
	return fx


static func _item_fx(fx: Dictionary, it: Dictionary, quirk_k: float) -> void:
	for p in it["perks"]:
		var k: String = String((AffixDB.DEFS[String((p as Dictionary)["id"])] as Dictionary)["key"])
		fx[k] = float(fx.get(k, 0.0)) + perk_value(p)
	var q: Dictionary = BrandDB.get_def(String(it["brand"]))["quirk"]
	for k in q.keys():
		fx[k] = float(fx.get(k, 0.0)) + float(q[k]) * quirk_k


## The run's Core sheet (TowerState.core_def): the Core's body (CoreDB: HP,
## regen, armor, cash, interest) with the equipped weapon's attack on top.
static func core_def(s: Dictionary) -> Dictionary:
	var d: Dictionary = CoreDB.get_def().duplicate()
	var ws: Dictionary = weapon_sheet(s)
	for k in ws.keys():
		d[k] = ws[k]
	d["attack_name"] = String(ws["name"])
	d["attack_desc"] = String(ws["desc"])
	return d


## The Core's weapon sheet for a run: the equipped frame's attack and L1
## numbers, damage x item power. TowerState folds Core level / tracks on top.
static func weapon_sheet(s: Dictionary) -> Dictionary:
	var w: Dictionary = weapon(s)
	var fd: Dictionary = FrameDB.get_def(String(w["base"]))
	var out: Dictionary = {"frame": String(w["base"]), "attack": String(fd["attack"]), "name": String(w["name"]),
		"dmg": float(fd["dmg"]) * power(w), "rate": float(fd["rate"]), "range": float(fd["range"]),
		"rar": String(w["rar"]), "brand": String(w["brand"]), "desc": String(fd["desc"])}
	var p: Dictionary = fd.get("p", {})
	for k in p.keys():
		out[k] = p[k]
	return out


# ------------------------------------------------------------------ text

## pfx key -> [label, format] for loadout / item readouts.
const FX_TEXT: Dictionary = {
	"core_dmg": ["Weapon damage", "pct"], "dmg": ["All damage", "pct"], "rate": ["Weapon attack rate", "pct"],
	"range": ["Weapon range", "cells"], "crit": ["Crit chance", "pct"], "crit_dmg": ["Crit damage", "pct"],
	"pierce": ["Pierce", "int"], "splash": ["Splash radius", "cells"], "chain": ["Chain jumps / rings", "int"],
	"chain_dmg": ["Chain damage", "pct"], "multishot": ["Extra volleys", "int"], "bounce": ["Ricochets", "int"],
	"burn": ["Burn per second (of hit)", "pct"], "slow_hit": ["Slow on hit", "pct"], "knock": ["Knockback", "pct"],
	"boss": ["Damage vs elites / bosses", "pct"], "normal_dmg": ["Damage vs the horde", "pct"], "execute": ["Execute below HP", "pct"],
	"shred": ["Shred per hit", "pct"], "echo": ["Echo chance", "pct"], "core_single": ["Main-target damage", "pct"],
	"beam_ramp": ["Beam ramp", "pct"], "pulse_dmg": ["Pulse damage", "pct"], "core_hp": ["Core max HP", "pct"],
	"regen": ["Core regen", "pct"], "armor": ["Core armor", "flat"], "shield": ["Core shield", "flat"],
	"lifesteal": ["Lifesteal", "pct"], "reflect": ["Thorns", "pct"], "dr": ["Damage reduction", "pct"],
	"kill_cash": ["Kill cash", "pct"], "cash_flat": ["Cash per second", "flat"], "cash": ["Cash per second", "pct"],
	"interest": ["Interest", "pct"], "xp": ["Run XP", "pct"], "luck": ["Luck", "int"], "bld_dmg": ["Building damage", "pct"],
	"bld_rate": ["Building attack rate", "pct"], "troop_dmg": ["Troop damage", "pct"], "troop_hp": ["Troop HP", "pct"],
	"special_dmg": ["Special damage", "pct"], "scrap_find": ["Scrap from runs", "pct"], "coin_run": ["Coins from runs", "pct"],
	"run_cash": ["Run cash", "pct"],
}


## "+12% Weapon damage" / "-15% Core max HP" / "+0.40 cells Weapon range" / "+2 Extra volleys".
static func fx_text(key: String, v: float) -> String:
	var d: Array = FX_TEXT.get(key, [key, "flat"])
	var sg: String = "+" if v >= 0.0 else "-"
	var a: float = absf(v)
	match String(d[1]):
		"pct":
			var p: float = a * 100.0
			return "%s%s%% %s" % [sg, ("%.1f" % p) if p < 10.0 else str(int(round(p))), String(d[0])]
		"int":
			return "%s%d %s" % [sg, int(round(a)), String(d[0])]
		"cells":
			return "%s%.2f %s (cells)" % [sg, a, String(d[0])]
	return "%s%s %s" % [sg, ("%.1f" % a) if a < 100.0 else str(int(round(a))), String(d[0])]


## Sorted readout lines of an fx dict (biggest magnitude first, zeros dropped).
static func fx_lines(fx: Dictionary) -> Array:
	var keys: Array = fx.keys().filter(func(k: Variant) -> bool: return absf(float(fx[k])) > 1e-6)
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var out: Array = []
	for k in keys:
		out.append(fx_text(String(k), float(fx[k])))
	return out


## One item's own fx (perks + brand quirk + a module's built-in fx).
static func item_fx(it: Dictionary) -> Dictionary:
	var fx: Dictionary = {}
	if String(it.get("kind", "")) == "module":
		fx = module_fx(it)
	_item_fx(fx, it, 1.0 if String(it.get("kind", "")) == "weapon" else MODULE_QUIRK)
	return fx


## Rough damage-per-second of a weapon on its own (the Forge's compare line):
## frame damage x power x its damage / rate / crit / volley fx.
static func est_dps(it: Dictionary) -> float:
	if String(it.get("kind", "")) != "weapon":
		return 0.0
	var fd: Dictionary = FrameDB.get_def(String(it["base"]))
	var fx: Dictionary = item_fx(it)
	var d: float = float(fd["dmg"]) * power(it) * maxf(0.1, 1.0 + float(fx.get("core_dmg", 0.0)) + float(fx.get("dmg", 0.0)))
	var r: float = float(fd["rate"]) * maxf(0.1, 1.0 + float(fx.get("rate", 0.0)))
	var c: float = clampf(float(fx.get("crit", 0.0)), 0.0, 1.0)
	var cm: float = 2.0 + float(fx.get("crit_dmg", 0.0))
	return d * r * (1.0 + c * (cm - 1.0)) * (1.0 + float(fx.get("multishot", 0.0))) * (1.0 + float(fx.get("echo", 0.0)))
