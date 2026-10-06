extends RefCounted
## V3 parts engine (design/V3_PARTS.md). Pure static rules over save.parts:
## the Weapon (attack) and the Core (defense / economy) are assemblies of
## typed parts; the chassis (Receiver / Heart) opens the other slots by its
## rarity. Every op returns events (like Gear / Outpost) and only touches
## the save it is given.
##   save.parts = {items: {uid: part}, next, rs, equipped: {slot: [uids]},
##     pity: {e, l, m}, bans: {weapon: [], core: []}, offer: {},
##     fab: {at, offers: [part], n}, smelt: [{uid, scrap, done}], presets: []}
##   part = {uid, slot, base, rar, lvl, mw, seed, rr, perks: [{id, t, q, lock}],
##     name, fav, new, src}
## A perk's tier t (1-7) is its own rarity (Common .. Exotic), rolled per perk
## around the part's rarity and scaled by AffixDB.TSCALE.

const PartDB := preload("res://data/PartDB.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const NameDB := preload("res://data/NameDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const Labs := preload("res://Labs.gd")
const Outpost := preload("res://Outpost.gd")
const Cores := preload("res://Cores.gd")

const INV_CAP: int = 300
const LVL_STEP: float = 0.05        # +5% part power per level
const MW_EVERY: int = 5             # a masterwork every 5 levels
const MW_BASE: float = 0.06         # +6% part power per masterwork
const JACKPOT: float = 0.15         # masterwork jackpot (+2 tiers) chance
const UP_BASE: float = 60.0         # upgrade coins: 60 * RM * 1.17^(L-1)
const UP_GROWTH: float = 1.17
const RR_BASE: float = 10.0         # reroll Scrap: 10 * RM * 1.25^rr * 4^locks
const RR_GROWTH: float = 1.25
const RR_LOCK: float = 4.0
const PRESETS_MAX: int = 4
const NAME_MAX: int = 48
const START_SEED: int = 0x5EED_C0DE
## Perk tier spread around the part's rarity rank: [delta, weight].
const PERK_SPREAD: Array = [[-1, 25.0], [0, 50.0], [1, 20.0], [2, 5.0]]
## A fresh save: the chassis and one barrel, which together are exactly the
## base Core sheet. Ammo / plating / generator slots start empty; the first
## drops and crates fill them.
const STARTER: Dictionary = {"receiver": "rcv_standard", "barrel": "brl_autocannon", "heart": "hrt_standard"}

## Scrap crates: price, parts, rarity luck, guaranteed floor.
const CRATES: Dictionary = {
	"standard": {"name": "Standard Crate", "scrap": 120, "n": 1, "luck": 0.0, "min": ""},
	"advanced": {"name": "Advanced Crate", "scrap": 600, "n": 3, "luck": 4.0, "min": "uncommon"},
	"elite":    {"name": "Elite Crate", "scrap": 2500, "n": 5, "luck": 10.0, "min": "rare"},
}
const CRATE_IDS: Array = ["standard", "advanced", "elite"]
const CONTRACT_K: float = 1.5

## Fabricator (Outpost building): a rotating shop. Lv1: 3 offers every 8 h;
## +1 offer per 2 levels (max 6), -0.6 h per level (min 2 h), -4% price per
## level, +1.5 rarity luck per level. Manual refresh: FAB_REROLL Scrap.
const FAB_BASE_H: float = 8.0
const FAB_STEP_H: float = 0.6
const FAB_MIN_H: float = 2.0
const FAB_PRICE: Dictionary = {"common": 150, "uncommon": 400, "rare": 1100, "epic": 3200, "legendary": 9000, "mythic": 26000, "exotic": 80000}
const FAB_REROLL: int = 200

## Smelter (Outpost building): parts melt into Scrap over time. Lv1: 2 slots,
## 20 min a part; +1 slot per 2 levels, -6% time and +6% yield per level.
const SMELT_MIN: float = 20.0


# ------------------------------------------------------------------ blocks

static func default_block() -> Dictionary:
	var p: Dictionary = {"items": {}, "next": 1, "rs": 0, "equipped": {}, "pity": {"e": 0, "l": 0, "m": 0},
		"bans": {"weapon": [], "core": []}, "offer": {}, "fab": {"at": 0, "offers": []}, "smelt": [], "presets": []}
	for slot in STARTER.keys():
		var uid: int = _add(p, starter(String(STARTER[slot])))
		(p["equipped"] as Dictionary)[slot] = [uid]
	_fit(p)
	return p


## A plain Common starter part (no perks), deterministic per base.
static func starter(base: String) -> Dictionary:
	var it: Dictionary = make(base, "common")
	it["src"] = "start"
	it["perks"] = []
	return it


## A part of `base` at `rar` / `lvl` with the given perks (tests, tools).
static func make(base: String, rar: String = "common", lvl: int = 1, perks: Array = []) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash([START_SEED, base, rar])
	var seed_v: int = r.randi()
	return {"uid": 0, "slot": PartDB.slot_of(base), "base": base, "rar": rar, "lvl": clampi(lvl, 1, max_lvl_of(rar)),
		"mw": clampi(lvl, 1, max_lvl_of(rar)) / MW_EVERY, "seed": seed_v, "rr": 0, "perks": perks.duplicate(true),
		"name": part_name(seed_v, base, rar), "fav": false, "new": false, "src": "make"}


## Common / Uncommon parts go by their base name ("Minigun Barrel"); Rare+
## get a seeded epithet and mark ("'Stormjaw' Minigun Barrel Mk II").
static func part_name(seed_v: int, base: String, rar: String) -> String:
	var bn: String = String(PartDB.get_def(base).get("name", base))
	if RarityDB.rank(rar) < 2:
		return bn
	return NameDB.make(seed_v, [], bn, rar).strip_edges()


## The save's parts block (created on first touch). V2 gear is migrated:
## every V2 item is refunded as Scrap at its salvage value.
static func block(s: Dictionary) -> Dictionary:
	if not (s.get("parts", null) is Dictionary):
		s["parts"] = default_block()
	return s["parts"]


## V3 hard switch from the V2 gear block: Scrap for every old item, then
## a fresh starter kit. Returns the Scrap refunded (0 if nothing to do).
static func migrate_gear(s: Dictionary) -> int:
	if not (s.get("gear", null) is Dictionary):
		return 0
	var g: Dictionary = s["gear"]
	var refund: int = 0
	var its: Dictionary = g.get("items", {}) if g.get("items", {}) is Dictionary else {}
	for k in its.keys():
		var it: Variant = its[k]
		if it is Dictionary:
			var rar: String = String((it as Dictionary).get("rar", "common"))
			refund += int(round(float(RarityDB.get_def(rar)["salvage"]) * (1.0 + 0.1 * float(maxi(1, int((it as Dictionary).get("lvl", 1))) - 1))))
	s.erase("gear")
	s["scrap"] = int(s.get("scrap", 0)) + refund
	if not (s.get("parts", null) is Dictionary):
		s["parts"] = default_block()
	return refund


## Coerce a raw (JSON) parts block: valid parts only, ints cast, equipped uids
## re-checked against the inventory and the chassis layouts; a missing
## chassis gets its starter.
static func normalize_block(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return default_block()
	var src: Dictionary = raw
	var p: Dictionary = {"items": {}, "next": 1, "rs": maxi(0, int(src.get("rs", 0))), "equipped": {}, "pity": {"e": 0, "l": 0, "m": 0},
		"bans": {"weapon": [], "core": []}, "offer": {}, "fab": {"at": 0, "offers": []}, "smelt": [], "presets": []}
	var top: int = 0
	var it_in: Dictionary = src.get("items", {}) if src.get("items", {}) is Dictionary else {}
	for k in it_in.keys():
		var it: Dictionary = normalize_item(it_in[k])
		var uid: int = int(String(k).to_int()) if String(k).is_valid_int() else 0
		if it.is_empty() or uid <= 0:
			continue
		it["uid"] = uid
		(p["items"] as Dictionary)[str(uid)] = it
		top = maxi(top, uid)
	p["next"] = maxi(top + 1, int(src.get("next", 1)))
	var pi: Dictionary = src.get("pity", {}) if src.get("pity", {}) is Dictionary else {}
	for g in ["e", "l", "m"]:
		(p["pity"] as Dictionary)[g] = clampi(int(pi.get(g, 0)), 0, int((RarityDB.PITY[g] as Dictionary)["hard"]))
	var bn: Dictionary = src.get("bans", {}) if src.get("bans", {}) is Dictionary else {}
	for side in ["weapon", "core"]:
		var out: Array = []
		for id in (bn.get(side, []) if bn.get(side, []) is Array else []):
			if perk_pool(side).has(String(id)) and not out.has(String(id)) and out.size() < 3:
				out.append(String(id))
		(p["bans"] as Dictionary)[side] = out
	var eq: Dictionary = src.get("equipped", {}) if src.get("equipped", {}) is Dictionary else {}
	for slot in PartDB.SLOTS.keys():
		var arr: Array = []
		for u in (eq.get(slot, []) if eq.get(slot, []) is Array else []):
			var ui: int = int(u)
			if ui > 0 and _slot_is(p, ui, String(slot)) and not arr.has(ui):
				arr.append(ui)
		(p["equipped"] as Dictionary)[slot] = arr
	for chassis in ["receiver", "heart"]:
		if ((p["equipped"] as Dictionary)[chassis] as Array).is_empty():
			var best: int = _first_of(p, chassis)
			if best == 0:
				best = _add(p, starter(String(STARTER[chassis])))
			(p["equipped"] as Dictionary)[chassis] = [best]
	if ((p["equipped"] as Dictionary)["barrel"] as Array).is_empty():
		var b: int = _first_of(p, "barrel")
		if b == 0:
			b = _add(p, starter(String(STARTER["barrel"])))
		(p["equipped"] as Dictionary)["barrel"] = [b]
	_fit(p)
	var fb: Dictionary = src.get("fab", {}) if src.get("fab", {}) is Dictionary else {}
	var offers: Array = []
	for o in (fb.get("offers", []) if fb.get("offers", []) is Array else []):
		var oi: Dictionary = normalize_item(o)
		if not oi.is_empty():
			oi["sold"] = bool((o as Dictionary).get("sold", false))
			offers.append(oi)
	p["fab"] = {"at": maxi(0, int(fb.get("at", 0))), "offers": offers}
	for sm in (src.get("smelt", []) if src.get("smelt", []) is Array else []):
		if sm is Dictionary:
			(p["smelt"] as Array).append({"name": _clean_name((sm as Dictionary).get("name", "Part")), "scrap": maxi(0, int((sm as Dictionary).get("scrap", 0))), "done": maxi(0, int((sm as Dictionary).get("done", 0)))})
	for pr in (src.get("presets", []) if src.get("presets", []) is Array else []):
		if pr is Dictionary and (p["presets"] as Array).size() < PRESETS_MAX:
			(p["presets"] as Array).append((pr as Dictionary).duplicate(true))
	return p


## Coerce one raw part; {} if it is not a valid part.
static func normalize_item(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var r: Dictionary = raw
	var base: String = str(r.get("base", ""))
	if not PartDB.has(base):
		return {}
	var slot: String = PartDB.slot_of(base)
	var rar: String = str(r.get("rar", "common"))
	if not RarityDB.IDS.has(rar):
		rar = "common"
	var side: String = PartDB.side_of(slot)
	var perks: Array = []
	var ids: Dictionary = {}
	for pk in (r.get("perks", []) if r.get("perks", []) is Array else []):
		var pc: Dictionary = _perk(pk)
		if pc.is_empty() or ids.has(pc["id"]) or not perk_pool(side).has(String(pc["id"])):
			continue
		ids[pc["id"]] = true
		perks.append(pc)
	var seed_v: int = int(r.get("seed", 0))
	var nm: String = _clean_name(r.get("name", ""))
	if nm == "":
		nm = part_name(seed_v, base, rar)
	return {"uid": maxi(0, int(r.get("uid", 0))), "slot": slot, "base": base, "rar": rar,
		"lvl": clampi(int(r.get("lvl", 1)), 1, max_lvl_of(rar)), "mw": maxi(0, int(r.get("mw", 0))), "seed": seed_v,
		"rr": maxi(0, int(r.get("rr", 0))), "perks": perks, "name": nm, "fav": bool(r.get("fav", false)),
		"new": bool(r.get("new", false)), "src": str(r.get("src", "drop"))}


static func _perk(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var p: Dictionary = raw
	var id: String = str(p.get("id", ""))
	if not AffixDB.DEFS.has(id):
		return {}
	return {"id": id, "t": clampi(int(p.get("t", 1)), 1, AffixDB.MAX_TIER), "q": clampf(float(p.get("q", 0.5)), 0.0, 1.0), "lock": bool(p.get("lock", false))}


static func _clean_name(v: Variant) -> String:
	var out: String = ""
	for ch in str(v).strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.left(NAME_MAX).strip_edges()


# ------------------------------------------------------------------ access

static func items(p: Dictionary) -> Dictionary:
	return p["items"]


static func has_item(p: Dictionary, uid: int) -> bool:
	return (p["items"] as Dictionary).has(str(uid))


static func get_item(p: Dictionary, uid: int) -> Dictionary:
	return (p["items"] as Dictionary).get(str(uid), {})


static func item(s: Dictionary, uid: int) -> Dictionary:
	return get_item(block(s), uid)


## Part uids (newest first), optionally of one slot.
static func uids(s: Dictionary, slot: String = "") -> Array:
	var out: Array = []
	for k in items(block(s)).keys():
		var it: Dictionary = items(block(s))[k]
		if slot == "" or String(it["slot"]) == slot:
			out.append(int(it["uid"]))
	out.sort()
	out.reverse()
	return out


static func count(s: Dictionary) -> int:
	return items(block(s)).size()


static func _slot_is(p: Dictionary, uid: int, slot: String) -> bool:
	return uid > 0 and has_item(p, uid) and String(get_item(p, uid)["slot"]) == slot


static func _first_of(p: Dictionary, slot: String) -> int:
	var best: int = 0
	for k in (p["items"] as Dictionary).keys():
		var it: Dictionary = (p["items"] as Dictionary)[k]
		if String(it["slot"]) == slot and (best == 0 or int(it["uid"]) < best):
			best = int(it["uid"])
	return best


static func _add(p: Dictionary, it: Dictionary) -> int:
	var uid: int = int(p["next"])
	p["next"] = uid + 1
	it["uid"] = uid
	(p["items"] as Dictionary)[str(uid)] = it
	return uid


## Add a found / bought part (0 if the inventory is full).
static func add_item(s: Dictionary, it: Dictionary) -> int:
	var p: Dictionary = block(s)
	if items(p).size() >= INV_CAP:
		return 0
	return _add(p, it)


static func _remove(p: Dictionary, uid: int) -> void:
	(p["items"] as Dictionary).erase(str(uid))
	for slot in (p["equipped"] as Dictionary).keys():
		var arr: Array = (p["equipped"] as Dictionary)[slot]
		arr.erase(uid)
	if not (p.get("offer", {}) as Dictionary).is_empty() and int((p["offer"] as Dictionary).get("uid", 0)) == uid:
		p["offer"] = {}


static func is_equipped(s: Dictionary, uid: int) -> bool:
	for slot in (block(s)["equipped"] as Dictionary).keys():
		if ((block(s)["equipped"] as Dictionary)[slot] as Array).has(uid):
			return true
	return false


static func _rng(p: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(["parts", int(p.get("rs", 0))])
	p["rs"] = int(p.get("rs", 0)) + 1
	return r


static func _rm(it: Dictionary) -> float:
	return float(RarityDB.get_def(String(it["rar"]))["rm"])


static func max_lvl_of(rar: String) -> int:
	return int(RarityDB.get_def(rar)["max_lvl"])


# ------------------------------------------------------------------ layout

## The chassis part of a side (Receiver / Heart) of a block.
static func _chassis(p: Dictionary, side: String) -> Dictionary:
	var arr: Array = (p["equipped"] as Dictionary).get("receiver" if side == "weapon" else "heart", [])
	return get_item(p, int(arr[0])) if not arr.is_empty() else {}


## slot -> how many the equipped chassis opens (chassis slots: 1).
static func layout_of(p: Dictionary, side: String) -> Dictionary:
	var ch: Dictionary = _chassis(p, side)
	var cs: String = "receiver" if side == "weapon" else "heart"
	var out: Dictionary = (PartDB.layout(cs, String(ch.get("rar", "common")))).duplicate()
	out[cs] = 1
	return out


static func layout(s: Dictionary, side: String) -> Dictionary:
	return layout_of(block(s), side)


## Trim / pad every equipped list to its layout count (extra parts unequip).
static func _fit(p: Dictionary) -> void:
	var eq: Dictionary = p["equipped"]
	for side in ["weapon", "core"]:
		var lo: Dictionary = layout_of(p, side)
		for slot in (PartDB.WEAPON_SLOTS if side == "weapon" else PartDB.CORE_SLOTS):
			var arr: Array = eq.get(slot, [])
			var n: int = int(lo.get(slot, 0))
			while arr.size() > n:
				arr.pop_back()
			eq[slot] = arr


## Equipped parts of a slot (read-only; never writes the save).
static func equipped(s: Dictionary, slot: String) -> Array:
	var out: Array = []
	var p: Variant = s.get("parts", null)
	if not (p is Dictionary):
		return [starter(String(STARTER[slot]))] if STARTER.has(slot) else out
	var n: int = int(layout_of(p, PartDB.side_of(slot)).get(slot, 0))
	var arr: Array = ((p as Dictionary)["equipped"] as Dictionary).get(slot, [])
	for i in mini(n, arr.size()):
		var it: Dictionary = get_item(p, int(arr[i]))
		if not it.is_empty():
			out.append(it)
	return out


## Every equipped part of a side (chassis first, then slot order).
static func side_parts(s: Dictionary, side: String) -> Array:
	var out: Array = []
	for slot in (PartDB.WEAPON_SLOTS if side == "weapon" else PartDB.CORE_SLOTS):
		out.append_array(equipped(s, String(slot)))
	return out


static func why_equip(s: Dictionary, uid: int, idx: int = -1) -> String:
	var p: Dictionary = block(s)
	var it: Dictionary = get_item(p, uid)
	if it.is_empty():
		return "No such part"
	var slot: String = String(it["slot"])
	var n: int = int(layout_of(p, PartDB.side_of(slot)).get(slot, 0))
	if n <= 0:
		return "The %s has no %s slot - a rarer %s opens it" % ["Receiver" if PartDB.side_of(slot) == "weapon" else "Heart", String(PartDB.SLOTS[slot]["name"]), "Receiver" if PartDB.side_of(slot) == "weapon" else "Heart"]
	if idx >= n:
		return "No such slot"
	return ""


## Install a part: into slot list position idx (-1: the first free position,
## else replacing the first). A chassis swap re-fits both lists.
static func equip(s: Dictionary, uid: int, idx: int = -1) -> Array:
	if why_equip(s, uid, idx) != "":
		return []
	var p: Dictionary = block(s)
	var it: Dictionary = get_item(p, uid)
	it["new"] = false
	var slot: String = String(it["slot"])
	var eq: Dictionary = p["equipped"]
	var arr: Array = eq.get(slot, [])
	var n: int = int(layout_of(p, PartDB.side_of(slot)).get(slot, 0))
	var old: int = 0
	var at: int = arr.find(uid)
	if at >= 0 and (idx < 0 or idx == at):
		return []
	if at >= 0:
		arr.remove_at(at)
	if idx < 0:
		idx = arr.size() if arr.size() < n else 0
	if idx < arr.size():
		old = int(arr[idx])
		arr[idx] = uid
	else:
		arr.append(uid)
	eq[slot] = arr
	if PartDB.is_chassis(slot):
		_fit(p)
	return [{"t": "part_equip", "uid": uid, "slot": slot, "idx": idx, "old": old}]


static func unequip(s: Dictionary, slot: String, idx: int) -> Array:
	var p: Dictionary = block(s)
	var arr: Array = (p["equipped"] as Dictionary).get(slot, [])
	if idx < 0 or idx >= arr.size() or PartDB.is_chassis(slot) or (slot == "barrel" and arr.size() <= 1):
		return []
	var old: int = int(arr[idx])
	arr.remove_at(idx)
	return [{"t": "part_unequip", "uid": old, "slot": slot}]


# ------------------------------------------------------------------ numbers

## Part power: rarity base x (1 + 5% a level) x 1.06^masterworks.
static func power(it: Dictionary) -> float:
	return float(RarityDB.get_def(String(it["rar"]))["base"]) * (1.0 + LVL_STEP * float(int(it["lvl"]) - 1)) * pow(1.0 + MW_BASE, float(int(it["mw"])))


## A part's own fx (positive values x power; count keys +1 per 2 masterworks).
static func base_fx(it: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var pw: float = power(it)
	var fx: Dictionary = PartDB.get_def(String(it["base"])).get("fx", {})
	for k in fx.keys():
		var v: float = float(fx[k])
		if PartDB.INT_KEYS.has(k):
			out[k] = v + float(int(it["mw"]) / 2)
		elif v > 0.0:
			out[k] = v * pw
		else:
			out[k] = v
	return out


static func perk_value(pk: Dictionary) -> float:
	return AffixDB.value(String(pk["id"]), int(pk["t"]), float(pk["q"]))


## A part's fx: its own fx plus its perks.
static func part_fx(it: Dictionary) -> Dictionary:
	var fx: Dictionary = base_fx(it)
	for pk in it["perks"]:
		var k: String = String((AffixDB.DEFS[String((pk as Dictionary)["id"])] as Dictionary)["key"])
		fx[k] = float(fx.get(k, 0.0)) + perk_value(pk)
	return fx


static func lock_slots(s: Dictionary) -> int:
	return 1 + mini(2, Labs.level(s, "stabilizer"))


static func ban_slots(s: Dictionary) -> int:
	return mini(3, Labs.level(s, "blacklist"))


static func reroll_options(s: Dictionary) -> int:
	return 2 + mini(1, Labs.level(s, "enchanters_eye"))


static func jackpot_chance(s: Dictionary) -> float:
	return minf(0.30, JACKPOT + 0.05 * float(Labs.level(s, "masterwork_odds")))


static func locks_on(it: Dictionary) -> int:
	var n: int = 0
	for pk in it["perks"]:
		if bool((pk as Dictionary).get("lock", false)):
			n += 1
	return n


static func upgrade_cost(it: Dictionary, s: Dictionary = {}) -> int:
	var disc: float = 0.05 * float(mini(5, Labs.level(s, "greater_cal"))) if not s.is_empty() else 0.0
	return int(round(UP_BASE * _rm(it) * pow(UP_GROWTH, float(int(it["lvl"]) - 1)) * (1.0 - disc)))


static func reroll_cost(it: Dictionary, s: Dictionary = {}) -> int:
	var disc: float = 0.08 * float(mini(5, Labs.level(s, "reroll_disc"))) if not s.is_empty() else 0.0
	return int(round(RR_BASE * _rm(it) * pow(RR_GROWTH, float(int(it["rr"]))) * pow(RR_LOCK, float(locks_on(it))) * (1.0 - disc)))


## Scrap a part melts into (Reclamation research +10% a level).
static func salvage_value(it: Dictionary, s: Dictionary = {}) -> int:
	var bonus: float = 0.10 * float(mini(5, Labs.level(s, "reclaim"))) if not s.is_empty() else 0.0
	return int(round(float(RarityDB.get_def(String(it["rar"]))["salvage"]) * (1.0 + 0.1 * float(int(it["lvl"]) - 1)) * (1.0 + bonus)))


# ------------------------------------------------------------------ rolls

## Perk ids a side may roll (AffixDB kinds: weapon / module / any).
static func perk_pool(side: String, frame: String = "") -> Array:
	var out: Array = []
	for id in AffixDB.pool("weapon" if side == "weapon" else "module", frame):
		if not PartDB.NO_PERKS.has(id):
			out.append(id)
	return out


## A perk's tier (1-7): the part's rarity rank + PERK_SPREAD, luck nudging up.
static func roll_tier(rng: RandomNumberGenerator, rar: String, luck: float = 0.0) -> int:
	var tot: float = 0.0
	for e in PERK_SPREAD:
		tot += float((e as Array)[1]) * (1.0 + (0.05 * luck if int((e as Array)[0]) > 0 else 0.0))
	var x: float = rng.randf() * tot
	var d: int = 0
	for e in PERK_SPREAD:
		x -= float((e as Array)[1]) * (1.0 + (0.05 * luck if int((e as Array)[0]) > 0 else 0.0))
		if x < 0.0:
			d = int((e as Array)[0])
			break
	return clampi(RarityDB.rank(rar) + d, 0, AffixDB.MAX_TIER - 1) + 1


## Draw n perks without replacement (AffixDB weights; bans / `have` excluded).
static func roll_perks(rng: RandomNumberGenerator, it: Dictionary, n: int, have: Array, bans: Array, luck: float = 0.0) -> Array:
	var side: String = PartDB.side_of(String(it["slot"]))
	var frame: String = String(PartDB.get_def(String(it["base"])).get("frame", ""))
	var pool: Array = perk_pool(side, frame)
	var taken: Dictionary = {}
	for pk in have:
		taken[String((pk as Dictionary)["id"])] = true
	var out: Array = []
	for k in n:
		var cands: Array = []
		var tot: float = 0.0
		for id in pool:
			if taken.has(id) or bans.has(id):
				continue
			var w: float = float((AffixDB.DEFS[id] as Dictionary)["w"])
			cands.append([id, w])
			tot += w
		if cands.is_empty():
			break
		var x: float = rng.randf() * tot
		var pick: String = String((cands[cands.size() - 1] as Array)[0])
		for c in cands:
			x -= float((c as Array)[1])
			if x < 0.0:
				pick = String((c as Array)[0])
				break
		taken[pick] = true
		out.append({"id": pick, "t": roll_tier(rng, String(it["rar"]), luck), "q": snappedf(rng.randf(), 0.001), "lock": false})
	return out


## Live rarity odds of the next roll from `src` (RarityDB table, luck, pity).
static func odds_now(src: String, luck: float, pity: Dictionary) -> Dictionary:
	var odds: Dictionary = RarityDB.odds(src, luck)
	for g in ["e", "l", "m"]:
		var pd: Dictionary = RarityDB.PITY[g]
		var n: int = int(pity.get(g, 0))
		var soft: int = int(pd["soft"])
		var hard: int = int(pd["hard"])
		if n + 1 < soft:
			continue
		var floor_r: String = String(pd["min"])
		var pg: float = 0.0
		for r in RarityDB.IDS:
			if RarityDB.at_least(String(r), floor_r):
				pg += float(odds[r])
		if pg <= 0.0:
			continue
		var boost: float = clampf(float(n + 2 - soft) / float(hard - soft + 1), 0.0, 1.0)
		var target: float = pg + (100.0 - pg) * boost
		var below: float = 100.0 - pg
		for r in RarityDB.IDS:
			if RarityDB.at_least(String(r), floor_r):
				odds[r] = float(odds[r]) * target / pg
			elif below > 0.0:
				odds[r] = float(odds[r]) * (100.0 - target) / below
	return odds


static func roll_rarity(rng: RandomNumberGenerator, src: String, luck: float, pity: Dictionary, floor_r: String = "") -> String:
	var odds: Dictionary = odds_now(src, luck, pity)
	var x: float = rng.randf() * 100.0
	var acc: float = 0.0
	var out: String = ""
	for r in RarityDB.IDS:
		acc += float(odds[r])
		if x < acc:
			out = String(r)
			break
	if out == "":
		for r in RarityDB.IDS:
			if float(odds[r]) > 0.0:
				out = String(r)
	if floor_r != "" and not RarityDB.at_least(out, floor_r):
		out = floor_r
	for g in ["e", "l", "m"]:
		if g == "m" and src != "drop":
			continue
		if RarityDB.at_least(out, String((RarityDB.PITY[g] as Dictionary)["min"])):
			pity[g] = 0
		else:
			pity[g] = int(pity.get(g, 0)) + 1
	return out


## Roll a new part. src: "drop" | "crate" | "fab" | "start".
## opts: {slot, base, rarity (forced), floor, luck, tluck (perk tiers only),
## side}; pity mutated unless forced.
static func roll(rng: RandomNumberGenerator, src: String, opts: Dictionary, pity: Dictionary, bans: Dictionary = {}) -> Dictionary:
	var slot: String = String(opts.get("slot", ""))
	if not PartDB.SLOTS.has(slot):
		var side: String = String(opts.get("side", ""))
		var tot: float = 0.0
		for sl in PartDB.SLOTS.keys():
			if side == "" or PartDB.side_of(String(sl)) == side:
				tot += float((PartDB.SLOTS[sl] as Dictionary)["w"])
		var x: float = rng.randf() * tot
		for sl in PartDB.SLOTS.keys():
			if side != "" and PartDB.side_of(String(sl)) != side:
				continue
			x -= float((PartDB.SLOTS[sl] as Dictionary)["w"])
			if x < 0.0:
				slot = String(sl)
				break
		if slot == "":
			slot = "barrel"
	var base: String = String(opts.get("base", ""))
	if PartDB.slot_of(base) != slot:
		var bs: Array = PartDB.bases_of(slot)
		var tw: float = 0.0
		for b in bs:
			tw += float((PartDB.BASES[b] as Dictionary)["w"])
		var y: float = rng.randf() * tw
		base = String(bs[bs.size() - 1])
		for b in bs:
			y -= float((PartDB.BASES[b] as Dictionary)["w"])
			if y < 0.0:
				base = String(b)
				break
	var rar: String = String(opts.get("rarity", ""))
	if not RarityDB.IDS.has(rar):
		rar = roll_rarity(rng, "forge" if src == "fab" else "drop", float(opts.get("luck", 0.0)), pity, String(opts.get("floor", "")))
	var it: Dictionary = {"uid": 0, "slot": slot, "base": base, "rar": rar, "lvl": 1, "mw": 0, "seed": 0, "rr": 0, "perks": [],
		"name": "", "fav": false, "new": true, "src": src}
	var side2: String = PartDB.side_of(slot)
	it["perks"] = roll_perks(rng, it, int(PartDB.PERK_SLOTS[rar]), [], (bans.get(side2, []) if bans.get(side2, []) is Array else []), float(opts.get("luck", 0.0)) + float(opts.get("tluck", 0.0)))
	it["seed"] = rng.randi()
	it["name"] = part_name(int(it["seed"]), base, rar)
	return it


# ------------------------------------------------------------------ upgrade / reroll / lock / ban

static func why_upgrade(s: Dictionary, uid: int) -> String:
	var it: Dictionary = item(s, uid)
	if it.is_empty():
		return "No such part"
	if int(it["lvl"]) >= max_lvl_of(String(it["rar"])):
		return "Max level - merge to raise the cap"
	if int(s.get("coins", 0)) < upgrade_cost(it, s):
		return "Need %d coins" % upgrade_cost(it, s)
	return ""


## +1 level for coins; every 5th a masterwork: +6% power and +1 perk tier
## (a jackpot: +2).
static func upgrade(s: Dictionary, uid: int) -> Array:
	if why_upgrade(s, uid) != "":
		return []
	var p: Dictionary = block(s)
	var it: Dictionary = get_item(p, uid)
	var c: int = upgrade_cost(it, s)
	s["coins"] = int(s["coins"]) - c
	it["lvl"] = int(it["lvl"]) + 1
	var ev: Dictionary = {"t": "part_upgrade", "uid": uid, "lvl": int(it["lvl"]), "coins": c}
	var ms: int = int(it["lvl"]) / MW_EVERY
	if int(it["lvl"]) % MW_EVERY == 0 and ms > int(it["mw"]):
		it["mw"] = ms
		ev["mw"] = ms
		var r: RandomNumberGenerator = _rng(p)
		var jack: bool = r.randf() < jackpot_chance(s)
		ev["jackpot"] = jack
		var ps: Array = it["perks"]
		if not ps.is_empty():
			var k: int = r.randi_range(0, ps.size() - 1)
			var up: int = 2 if jack else 1
			(ps[k] as Dictionary)["t"] = mini(AffixDB.MAX_TIER, int((ps[k] as Dictionary)["t"]) + up)
			ev["perk"] = k
			ev["tiers"] = up
	return [ev]


## Bulk Upgrade research: x n levels (0 = up to the cap); without it one.
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


static func why_reroll(s: Dictionary, uid: int, idx: int) -> String:
	var p: Dictionary = block(s)
	var it: Dictionary = get_item(p, uid)
	if it.is_empty():
		return "No such part"
	if not (p.get("offer", {}) as Dictionary).is_empty():
		return "Choose from the open reroll first"
	if idx < 0 or idx >= (it["perks"] as Array).size():
		return "No such perk"
	if bool(((it["perks"] as Array)[idx] as Dictionary).get("lock", false)):
		return "Locked perks don't reroll"
	if int(s.get("scrap", 0)) < reroll_cost(it, s):
		return "Need %d Scrap" % reroll_cost(it, s)
	return ""


## Pay Scrap for 2 (3 with Enchanter's Eye) fresh perks - id and rarity tier
## both re-roll; the offer waits in the save until reroll_choose().
static func reroll(s: Dictionary, uid: int, idx: int) -> Array:
	if why_reroll(s, uid, idx) != "":
		return []
	var p: Dictionary = block(s)
	var it: Dictionary = get_item(p, uid)
	var c: int = reroll_cost(it, s)
	s["scrap"] = int(s["scrap"]) - c
	it["rr"] = int(it["rr"]) + 1
	var others: Array = []
	for i in (it["perks"] as Array).size():
		if i != idx:
			others.append((it["perks"] as Array)[i])
	var side: String = PartDB.side_of(String(it["slot"]))
	var cands: Array = []
	var r: RandomNumberGenerator = _rng(p)
	for k in reroll_options(s):
		var have: Array = others.duplicate()
		have.append_array(cands)
		var one: Array = roll_perks(r, it, 1, have, (p["bans"] as Dictionary).get(side, []), float(Labs.level(s, "appraisal")))
		cands.append_array(one)
	p["offer"] = {"uid": uid, "idx": idx, "cands": cands}
	return [{"t": "part_reroll", "uid": uid, "idx": idx, "scrap": c, "cands": cands.duplicate(true)}]


static func reroll_choose(s: Dictionary, k: int) -> Array:
	var p: Dictionary = block(s)
	var of: Dictionary = p.get("offer", {})
	if of.is_empty():
		return []
	var cands: Array = of["cands"]
	if k >= cands.size() or k < -1:
		return []
	var it: Dictionary = get_item(p, int(of["uid"]))
	p["offer"] = {}
	if it.is_empty():
		return []
	if k == -1:
		return [{"t": "part_reroll_keep", "uid": int(of["uid"]), "idx": int(of["idx"])}]
	var np: Dictionary = (cands[k] as Dictionary).duplicate()
	(it["perks"] as Array)[int(of["idx"])] = np
	return [{"t": "part_reroll_take", "uid": int(of["uid"]), "idx": int(of["idx"]), "perk": np.duplicate()}]


static func why_lock(s: Dictionary, uid: int, idx: int, on: bool) -> String:
	var it: Dictionary = item(s, uid)
	if it.is_empty():
		return "No such part"
	if idx < 0 or idx >= (it["perks"] as Array).size():
		return "No such perk"
	if on and not bool(((it["perks"] as Array)[idx] as Dictionary).get("lock", false)) and locks_on(it) >= lock_slots(s):
		return "Lock slots full (%d) - Stabilizer research adds more" % lock_slots(s)
	return ""


static func lock(s: Dictionary, uid: int, idx: int, on: bool) -> Array:
	if why_lock(s, uid, idx, on) != "":
		return []
	var pk: Dictionary = (item(s, uid)["perks"] as Array)[idx]
	if bool(pk.get("lock", false)) == on:
		return []
	pk["lock"] = on
	return [{"t": "part_lock", "uid": uid, "idx": idx, "on": on}]


static func why_ban(s: Dictionary, side: String, id: String, on: bool) -> String:
	if not ["weapon", "core"].has(side) or not perk_pool(side).has(id):
		return "That perk can't roll there"
	var bl: Array = (block(s)["bans"] as Dictionary)[side]
	if on and not bl.has(id) and bl.size() >= ban_slots(s):
		return "Ban slots full (%d) - Blacklist research adds more" % ban_slots(s) if ban_slots(s) > 0 else "Blacklist research unlocks bans"
	return ""


static func ban(s: Dictionary, side: String, id: String, on: bool) -> Array:
	if why_ban(s, side, id, on) != "":
		return []
	var bl: Array = (block(s)["bans"] as Dictionary)[side]
	if on == bl.has(id):
		return []
	if on:
		bl.append(id)
	else:
		bl.erase(id)
	return [{"t": "part_ban", "side": side, "id": id, "on": on}]


# ------------------------------------------------------------------ merge

static func why_merge(s: Dictionary, uids_in: Array, base_uid: int) -> String:
	var p: Dictionary = block(s)
	if uids_in.size() != 3:
		return "Merge takes 3 parts"
	var seen: Dictionary = {}
	var slot: String = ""
	var rar: String = ""
	for u in uids_in:
		var it: Dictionary = get_item(p, int(u))
		if it.is_empty() or seen.has(int(u)):
			return "Pick 3 different parts"
		seen[int(u)] = true
		if slot == "":
			slot = String(it["slot"])
			rar = String(it["rar"])
		elif String(it["slot"]) != slot:
			return "Same part type only"
		elif String(it["rar"]) != rar:
			return "Same rarity only"
		if int(u) != base_uid and bool(it.get("fav", false)):
			return "A favourite can't be merged away"
	if not seen.has(base_uid):
		return "The base must be one of the three"
	var nx: String = RarityDB.next(rar)
	if nx == "" or nx == "exotic":
		return "Exotics only drop"
	if nx == "mythic" and Labs.level(s, "mythic_fusion") <= 0:
		return "Mythic Fusion research needed"
	return ""


## Merge 3 same-type, same-rarity parts into the base: rarity +1, new perk
## slots roll fresh (around the new rarity), level = half the best input's.
static func merge(s: Dictionary, uids_in: Array, base_uid: int) -> Array:
	if why_merge(s, uids_in, base_uid) != "":
		return []
	var p: Dictionary = block(s)
	var base: Dictionary = get_item(p, base_uid)
	var top: int = 1
	for u in uids_in:
		top = maxi(top, int(get_item(p, int(u))["lvl"]))
	for u in uids_in:
		if int(u) != base_uid:
			_remove(p, int(u))
	var old_r: String = String(base["rar"])
	base["rar"] = RarityDB.next(old_r)
	base["lvl"] = clampi(top / 2, 1, max_lvl_of(String(base["rar"])))
	base["new"] = false
	var add: int = int(PartDB.PERK_SLOTS[String(base["rar"])]) - (base["perks"] as Array).size()
	var r: RandomNumberGenerator = _rng(p)
	if add > 0:
		(base["perks"] as Array).append_array(roll_perks(r, base, add, base["perks"], (p["bans"] as Dictionary).get(PartDB.side_of(String(base["slot"])), [])))
	if String(base["name"]) == part_name(int(base["seed"]), String(base["base"]), old_r):
		base["name"] = part_name(int(base["seed"]), String(base["base"]), String(base["rar"]))
	if PartDB.is_chassis(String(base["slot"])) and is_equipped(s, base_uid):
		_fit(p)
	return [{"t": "part_merge", "uid": base_uid, "from": old_r, "to": String(base["rar"]), "lvl": int(base["lvl"]), "used": uids_in.duplicate()}]


# ------------------------------------------------------------------ crates

## A crate's Scrap price; a targeted crate (one part type, Part Contracts
## research) costs x CONTRACT_K.
static func crate_price(id: String, slot: String = "") -> int:
	var c: int = int((CRATES.get(id, CRATES["standard"]) as Dictionary)["scrap"])
	return int(round(float(c) * CONTRACT_K)) if slot != "" else c


static func why_crate(s: Dictionary, id: String, slot: String = "") -> String:
	if not CRATES.has(id):
		return "No such crate"
	if slot != "" and not PartDB.SLOTS.has(slot):
		return "No such part type"
	if slot != "" and Labs.level(s, "brand_contracts") <= 0:
		return "Part Contracts research picks the part type"
	if count(s) + int((CRATES[id] as Dictionary)["n"]) > INV_CAP:
		return "Inventory full - smelt something"
	if int(s.get("scrap", 0)) < crate_price(id, slot):
		return "Need %d Scrap" % crate_price(id, slot)
	return ""


## Open a Scrap crate: n parts at the drop odds + crate luck + Appraisal
## research; the first part is at least the crate's floor; pity advances.
## `slot` (Part Contracts) makes every part that type.
static func open_crate(s: Dictionary, id: String, slot: String = "") -> Array:
	if why_crate(s, id, slot) != "":
		return []
	var p: Dictionary = block(s)
	var cd: Dictionary = CRATES[id]
	var price: int = crate_price(id, slot)
	s["scrap"] = int(s["scrap"]) - price
	var r: RandomNumberGenerator = _rng(p)
	var got: Array = []
	for k in int(cd["n"]):
		var it: Dictionary = roll(r, "crate", {"slot": slot, "luck": float(cd["luck"]) + float(Labs.level(s, "appraisal")), "floor": String(cd["min"]) if k == 0 else ""}, p["pity"], p["bans"])
		got.append(_add(p, it))
	return [{"t": "crate_open", "crate": id, "uids": got, "scrap": price, "slot": slot}]


# ------------------------------------------------------------------ Fabricator (Outpost)

static func fab_level(s: Dictionary) -> int:
	return Outpost.level_of(s, "fabricator") if s.get("outpost", null) is Dictionary else 0


static func fab_period_h(s: Dictionary) -> float:
	return maxf(FAB_MIN_H, FAB_BASE_H - FAB_STEP_H * float(maxi(0, fab_level(s) - 1)))


static func fab_slots(s: Dictionary) -> int:
	return mini(6, 3 + maxi(0, fab_level(s) - 1) / 2)


## Fabricator price: -4% a level, and Forge Works (Outpost) -2% a level.
static func fab_price(s: Dictionary, it: Dictionary) -> int:
	var fw: float = float(Outpost.core_bonus(s).get("forge_disc", 0.0)) if s.get("outpost", null) is Dictionary else 0.0
	var disc: float = clampf(0.04 * float(maxi(0, fab_level(s) - 1)) + fw, 0.0, 0.5)
	return int(round(float(FAB_PRICE.get(String(it["rar"]), 150)) * (1.0 - disc)))


## The Fabricator's current offers (rolls a fresh set when the period ran out).
static func fab_offers(s: Dictionary, now: int) -> Array:
	if fab_level(s) <= 0:
		return []
	var p: Dictionary = block(s)
	var fb: Dictionary = p["fab"]
	var per: int = int(fab_period_h(s) * 3600.0)
	if (fb["offers"] as Array).is_empty() or now - int(fb["at"]) >= per:
		_fab_roll(s, now)
	return (p["fab"] as Dictionary)["offers"]


static func fab_next_refresh(s: Dictionary) -> int:
	return int((block(s)["fab"] as Dictionary)["at"]) + int(fab_period_h(s) * 3600.0)


static func _fab_roll(s: Dictionary, now: int) -> void:
	var p: Dictionary = block(s)
	var r: RandomNumberGenerator = _rng(p)
	var offers: Array = []
	var luck: float = 1.5 * float(fab_level(s)) + float(Labs.level(s, "appraisal"))
	var no_pity: Dictionary = {"e": 0, "l": 0, "m": 0}
	for k in fab_slots(s):
		var it: Dictionary = roll(r, "fab", {"luck": luck}, no_pity, p["bans"])
		it["sold"] = false
		offers.append(it)
	p["fab"] = {"at": now, "offers": offers}


static func why_fab_buy(s: Dictionary, k: int, now: int) -> String:
	var of: Array = fab_offers(s, now)
	if k < 0 or k >= of.size():
		return "No such offer"
	if bool((of[k] as Dictionary).get("sold", false)):
		return "Sold - the next refresh restocks"
	if count(s) >= INV_CAP:
		return "Inventory full - smelt something"
	if int(s.get("scrap", 0)) < fab_price(s, of[k]):
		return "Need %d Scrap" % fab_price(s, of[k])
	return ""


static func fab_buy(s: Dictionary, k: int, now: int) -> Array:
	if why_fab_buy(s, k, now) != "":
		return []
	var of: Array = fab_offers(s, now)
	var o: Dictionary = of[k]
	var c: int = fab_price(s, o)
	s["scrap"] = int(s["scrap"]) - c
	var it: Dictionary = o.duplicate(true)
	it.erase("sold")
	it["new"] = true
	it["src"] = "fab"
	var uid: int = _add(block(s), it)
	o["sold"] = true
	return [{"t": "fab_buy", "uid": uid, "scrap": c, "rar": String(it["rar"])}]


static func fab_reroll(s: Dictionary, now: int) -> Array:
	if fab_level(s) <= 0 or int(s.get("scrap", 0)) < FAB_REROLL:
		return []
	s["scrap"] = int(s["scrap"]) - FAB_REROLL
	_fab_roll(s, now)
	return [{"t": "fab_reroll", "scrap": FAB_REROLL}]


# ------------------------------------------------------------------ Smelter (Outpost)

static func smelt_level(s: Dictionary) -> int:
	return Outpost.level_of(s, "smelter") if s.get("outpost", null) is Dictionary else 0


static func smelt_slots(s: Dictionary) -> int:
	return 0 if smelt_level(s) <= 0 else 2 + (smelt_level(s) - 1) / 2


static func smelt_secs(s: Dictionary) -> int:
	return int(SMELT_MIN * 60.0 * pow(0.94, float(maxi(0, smelt_level(s) - 1))))


static func smelt_yield(s: Dictionary, it: Dictionary) -> int:
	return int(round(float(salvage_value(it, s)) * (1.0 + 0.06 * float(maxi(0, smelt_level(s) - 1)))))


static func why_smelt(s: Dictionary, uid: int, now: int) -> String:
	var it: Dictionary = item(s, uid)
	if it.is_empty():
		return "No such part"
	if smelt_level(s) <= 0:
		return "Build a Smelter in the Outpost"
	if bool(it.get("fav", false)):
		return "Unfavourite it first"
	if is_equipped(s, uid):
		return "Unequip it first"
	if smelt_busy(s, now) >= smelt_slots(s):
		return "Smelter full (%d) - upgrade it for more slots" % smelt_slots(s)
	return ""


## Parts still melting at `now` (finished ones wait for smelt_claim but
## free their furnace slot).
static func smelt_busy(s: Dictionary, now: int) -> int:
	var n: int = 0
	for e in (block(s)["smelt"] as Array):
		if int((e as Dictionary)["done"]) > now:
			n += 1
	return n


## Queue a part in the Smelter: it is consumed now; its Scrap is ready later.
static func smelt(s: Dictionary, uid: int, now: int) -> Array:
	if why_smelt(s, uid, now) != "":
		return []
	var p: Dictionary = block(s)
	var it: Dictionary = get_item(p, uid)
	var done: int = now + smelt_secs(s)   # slots melt in parallel
	var ev: Array = [{"t": "smelt_start", "uid": uid, "done": done}]
	(p["smelt"] as Array).append({"name": String(it["name"]), "scrap": smelt_yield(s, it), "done": done})
	_remove(p, uid)
	return ev


## Collect every finished smelt; returns the Scrap paid.
static func smelt_claim(s: Dictionary, now: int) -> Array:
	var p: Dictionary = block(s)
	var q: Array = p["smelt"]
	var keep: Array = []
	var got: int = 0
	for e in q:
		if int((e as Dictionary)["done"]) <= now:
			got += int((e as Dictionary)["scrap"])
		else:
			keep.append(e)
	p["smelt"] = keep
	if got <= 0:
		return []
	s["scrap"] = int(s.get("scrap", 0)) + got
	return [{"t": "smelt_done", "scrap": got}]


## Instant salvage (tools, Auto-Salvage QOL and tests): the Smelter's yield
## without the wait.
static func salvage(s: Dictionary, uid: int) -> Array:
	var p: Dictionary = block(s)
	var it: Dictionary = get_item(p, uid)
	if it.is_empty() or bool(it.get("fav", false)) or is_equipped(s, uid):
		return []
	var v: int = salvage_value(it, s)
	_remove(p, uid)
	s["scrap"] = int(s.get("scrap", 0)) + v
	return [{"t": "part_salvage", "uid": uid, "scrap": v}]


# ------------------------------------------------------------------ cosmetic

static func set_fav(s: Dictionary, uid: int, on: bool) -> Array:
	var it: Dictionary = item(s, uid)
	if it.is_empty() or bool(it.get("fav", false)) == on:
		return []
	it["fav"] = on
	return [{"t": "part_fav", "uid": uid, "on": on}]


static func rename(s: Dictionary, uid: int, nm: String) -> Array:
	var it: Dictionary = item(s, uid)
	var c: String = _clean_name(nm)
	if it.is_empty() or c == "":
		return []
	it["name"] = c
	return [{"t": "part_rename", "uid": uid, "name": c}]


static func mark_seen(s: Dictionary, uid: int) -> void:
	var it: Dictionary = item(s, uid)
	if not it.is_empty():
		it["new"] = false


static func new_count(s: Dictionary, side: String = "") -> int:
	var n: int = 0
	for k in items(block(s)).keys():
		var it: Dictionary = items(block(s))[k]
		if bool(it.get("new", false)) and (side == "" or PartDB.side_of(String(it["slot"])) == side):
			n += 1
	return n


# ------------------------------------------------------------------ presets

static func save_preset(s: Dictionary, k: int) -> Array:
	if k < 0 or k >= mini(PRESETS_MAX, Labs.preset_slots(s)):
		return []
	var p: Dictionary = block(s)
	var pr: Array = p["presets"]
	while pr.size() <= k:
		pr.append({})
	pr[k] = {"name": "Loadout %d" % (k + 1), "equipped": (p["equipped"] as Dictionary).duplicate(true)}
	return [{"t": "preset_saved", "k": k}]


static func preset(s: Dictionary, k: int) -> Dictionary:
	var pr: Array = block(s)["presets"]
	return pr[k] if k >= 0 and k < pr.size() and pr[k] is Dictionary else {}


static func load_preset(s: Dictionary, k: int) -> Array:
	if k < 0 or k >= mini(PRESETS_MAX, Labs.preset_slots(s)):
		return []
	var pr: Dictionary = preset(s, k)
	if pr.is_empty() or not pr.has("equipped"):
		return []
	var p: Dictionary = block(s)
	var missing: int = 0
	var eq: Dictionary = {}
	for slot in PartDB.SLOTS.keys():
		var arr: Array = []
		for u in ((pr["equipped"] as Dictionary).get(slot, []) as Array):
			if _slot_is(p, int(u), String(slot)) and not arr.has(int(u)):
				arr.append(int(u))
			else:
				missing += 1
		eq[slot] = arr
	for chassis in ["receiver", "heart", "barrel"]:
		if (eq[chassis] as Array).is_empty():
			eq[chassis] = ((p["equipped"] as Dictionary)[chassis] as Array).duplicate()
	p["equipped"] = eq
	_fit(p)
	return [{"t": "preset_loaded", "k": k, "missing": missing}]


# ------------------------------------------------------------------ run hand-off

## Summed fx of every installed part (both assemblies) for the run's pfx.
## Barrels and chassis carry no fx of their own except their perks / base fx.
static func run_fx(s: Dictionary) -> Dictionary:
	var fx: Dictionary = {}
	for side in ["weapon", "core"]:
		for it in side_parts(s, side):
			var pf: Dictionary = part_fx(it)
			for k in pf.keys():
				fx[k] = float(fx.get(k, 0.0)) + float(pf[k])
	return fx


## One barrel's attack sheet: its frame's L1 numbers x receiver x the
## barrel's power.
static func barrel_sheet(barrel: Dictionary, receiver: Dictionary) -> Dictionary:
	var bd: Dictionary = PartDB.get_def(String(barrel["base"]))
	var fd: Dictionary = FrameDB.get_def(String(bd.get("frame", "autocannon")))
	var rd: Dictionary = PartDB.get_def(String(receiver.get("base", "rcv_standard")))
	var out: Dictionary = {"frame": String(bd.get("frame", "autocannon")), "attack": String(fd["attack"]), "name": String(barrel["name"]),
		"dmg": float(fd["dmg"]) * power(barrel) * float(rd.get("dmg_k", 1.0)) * (0.5 + 0.5 * power(receiver)),
		"rate": float(fd["rate"]) * float(rd.get("rate_k", 1.0)), "range": float(fd["range"]),
		"rar": String(barrel["rar"]), "desc": String(fd["desc"])}
	var pp: Dictionary = fd.get("p", {})
	for k in pp.keys():
		out[k] = pp[k]
	# barrel variants re-tune their frame (PartDB "sheet")
	var sh: Dictionary = bd.get("sheet", {})
	for k in sh.keys():
		match String(k):
			"dmg_k":
				out["dmg"] = float(out["dmg"]) * float(sh[k])
			"rate_k":
				out["rate"] = float(out["rate"]) * float(sh[k])
			"range_k":
				out["range"] = float(out["range"]) * float(sh[k])
			_:
				out[k] = sh[k]
	out["desc"] = String(bd.get("desc", out["desc"]))
	return out


## The run's Core sheet (TowerState.core_def): the Core body (CoreDB, scaled
## by the Heart), the first barrel's attack on top (back-compat keys) and
## `barrels`: every installed barrel's sheet.
static func core_def(s: Dictionary) -> Dictionary:
	var d: Dictionary = CoreDB.get_def().duplicate()
	var rc: Array = equipped(s, "receiver")
	var receiver: Dictionary = rc[0] if not rc.is_empty() else starter("rcv_standard")
	var bl: Array = equipped(s, "barrel")
	if bl.is_empty():
		bl = [starter("brl_autocannon")]
	var sheets: Array = []
	for b in bl:
		sheets.append(barrel_sheet(b, receiver))
	for k in (sheets[0] as Dictionary).keys():
		d[k] = (sheets[0] as Dictionary)[k]
	d["barrels"] = sheets
	var hr: Array = equipped(s, "heart")
	var heart: Dictionary = hr[0] if not hr.is_empty() else starter("hrt_standard")
	var hd: Dictionary = PartDB.get_def(String(heart["base"]))
	var hp_scale: float = 0.85 + 0.15 * power(heart)
	d["hp"] = float(CoreDB.get_def()["hp"]) * float(hd.get("hp_k", 1.0)) * hp_scale
	d["regen"] = float(CoreDB.get_def()["regen"]) * float(hd.get("regen_k", 1.0)) * hp_scale
	d["attack_name"] = String(receiver["name"]) if sheets.size() > 1 else String((sheets[0] as Dictionary)["name"])
	d["attack_desc"] = String((sheets[0] as Dictionary)["desc"]) + ("" if sheets.size() == 1 else "  (+%d more barrel%s)" % [sheets.size() - 1, "" if sheets.size() == 2 else "s"])
	return d


## Average bodies a volley of `bs` hits (readouts only).
static func _hits(bs: Dictionary) -> float:
	match String(bs["attack"]):
		"scatter":
			return float(bs.get("pellets", 6)) * 0.5
		"missiles":
			return float(bs.get("missiles", 4))
		"arc":
			return 1.0 + float(bs.get("chain", 5)) * 0.6
		"saw":
			return 1.0 + float(bs.get("bounces", 4)) * 0.7
		"rail":
			return minf(3.0, float(bs.get("pierce", 10)) * 0.5)
		"pulse":
			return 4.0
		"slag":
			return 1.0 + 2.0 * float(bs.get("splash", 0.6))
		"cannon":
			return float(bs.get("barrels", 1)) + float(bs.get("splash", 0.4)) * float(bs.get("splash_frac", 0.4)) * 2.0
		"flame":
			return 2.5
	return 1.0


## Rough weapon DPS for readouts (sum of barrels; hit-weighted).
static func est_dps(s: Dictionary) -> float:
	var d: Dictionary = core_def(s)
	var fx: Dictionary = run_fx(s)
	var tot: float = 0.0
	for b in d["barrels"]:
		tot += float((b as Dictionary)["dmg"]) * float((b as Dictionary)["rate"]) * _hits(b)
	return tot * (1.0 + float(fx.get("core_dmg", 0.0)) + float(fx.get("dmg", 0.0))) * maxf(0.1, 1.0 + float(fx.get("rate", 0.0)))


## One barrel part's DPS on the equipped Receiver (before other parts' fx).
static func barrel_dps(s: Dictionary, barrel: Dictionary) -> float:
	var rc: Array = equipped(s, "receiver")
	var bs: Dictionary = barrel_sheet(barrel, rc[0] if not rc.is_empty() else starter("rcv_standard"))
	return float(bs["dmg"]) * float(bs["rate"]) * _hits(bs)


# ------------------------------------------------------------------ readouts

const FX_TEXT: Dictionary = {
	"core_dmg": ["Weapon damage", "pct"], "dmg": ["All damage", "pct"], "rate": ["Weapon attack rate", "pct"],
	"range": ["Weapon range", "cells"], "crit": ["Crit chance", "pct"], "crit_dmg": ["Crit damage", "pct"],
	"pierce": ["Pierce", "int"], "splash": ["Splash radius", "cells"], "chain": ["Chain jumps / rings", "int"],
	"chain_dmg": ["Chain damage", "pct"], "bounce": ["Ricochets", "int"],
	"burn": ["Burn per second (of hit)", "pct"], "slow_hit": ["Slow on hit", "pct"], "knock": ["Knockback", "pct"],
	"boss": ["Damage vs elites / bosses", "pct"], "normal_dmg": ["Damage vs the horde", "pct"], "execute": ["Execute below HP", "pct"],
	"shred": ["Shred per hit", "pct"], "echo": ["Echo chance", "pct"], "core_single": ["Main-target damage", "pct"],
	"beam_ramp": ["Beam ramp", "pct"], "pulse_dmg": ["Pulse damage", "pct"], "core_hp": ["Core max HP", "pct"],
	"regen": ["Core regen", "pct"], "armor": ["Core armor", "flat"], "shield": ["Core shield", "flat"],
	"lifesteal": ["Lifesteal", "pct"], "reflect": ["Thorns", "pct"], "dr": ["Damage reduction", "pct"],
	"kill_cash": ["Kill cash", "pct"], "cash_flat": ["Cash per second", "flat"], "cash": ["Cash per second", "pct"],
	"interest": ["Interest", "pct"], "icap": ["Interest cap", "pct"], "xp": ["Run XP", "pct"], "luck": ["Luck", "int"],
	"loot_luck": ["Loot luck", "int"], "draft_luck": ["Draft luck", "int"], "bld_dmg": ["Building damage", "pct"],
	"bld_rate": ["Building attack rate", "pct"], "troop_dmg": ["Troop damage", "pct"], "troop_hp": ["Troop HP", "pct"],
	"special_dmg": ["Special damage", "pct"], "scrap_find": ["Scrap from runs", "pct"], "coin_run": ["Coins from runs", "pct"],
	"run_cash": ["Run cash", "pct"],
}


## "+12% Weapon damage" / "-15% Core max HP" / "+0.40 cells Weapon range" / "+2 Pierce".
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


## Sorted readout lines of an fx dict (zeros dropped).
static func fx_lines(fx: Dictionary) -> Array:
	var keys: Array = fx.keys().filter(func(k: Variant) -> bool: return absf(float(fx[k])) > 1e-6)
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var out: Array = []
	for k in keys:
		out.append(fx_text(String(k), float(fx[k])))
	return out


## What a chassis of this rarity opens ("2 Barrels, Ammo, Scope ...").
static func layout_text(chassis_slot: String, rar: String) -> String:
	var lo: Dictionary = PartDB.layout(chassis_slot, rar)
	var out: Array = []
	for sl in (PartDB.WEAPON_SLOTS if chassis_slot == "receiver" else PartDB.CORE_SLOTS):
		var n: int = int(lo.get(sl, 0))
		if n <= 0 or PartDB.is_chassis(String(sl)):
			continue
		var nm: String = String(PartDB.SLOTS[sl]["name"])
		out.append(("%d %ss" % [n, nm]) if n > 1 else nm)
	return ", ".join(out)


## The lowest chassis rarity that opens position `idx` of `slot` ("" if none).
static func opens_at(slot: String, idx: int) -> String:
	var cs: String = "receiver" if PartDB.side_of(slot) == "weapon" else "heart"
	for r in RarityDB.IDS:
		if int(PartDB.layout(cs, String(r)).get(slot, 0)) > idx:
			return String(r)
	return ""
