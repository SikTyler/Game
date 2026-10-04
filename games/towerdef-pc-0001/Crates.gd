extends RefCounted
## Crate rules (REDESIGN_SPEC §3.1, SYSTEMS §3.4). Pure static over the save:
##   save.crates = {pity: {field: {epic}, supply: {epic, legendary},
##                  vault: {legendary}}, tokens: {field: n}}
## open() takes an injected RNG (seeded by the caller) so opens replay. Pity
## counts opens of that crate without the rarity (or better); the open that
## reaches the threshold upgrades its best part to that rarity. Reforge node
## crate_luck scales Epic/Legendary weights by (1 + 0.05 L) (relative odds);
## research Crate Theory cuts the Field Crate coin price 2% per level.

const CrateDB := preload("res://data/CrateDB.gd")
const Parts := preload("res://Parts.gd")
const Tiers := preload("res://Tiers.gd")
const Stats := preload("res://Stats.gd")
const TuneRef := preload("res://Tune.gd")

const RANK: Dictionary = {"common": 0, "rare": 1, "epic": 2, "legendary": 3}


static func default_block() -> Dictionary:
	return {"pity": {"field": {"epic": 0}, "supply": {"epic": 0, "legendary": 0}, "vault": {"legendary": 0}}, "tokens": {"field": 0}}


static func normalize_block(raw: Variant) -> Dictionary:
	var d: Dictionary = default_block()
	if not (raw is Dictionary):
		return d
	var r: Dictionary = raw
	var pin: Dictionary = r.get("pity", {}) if r.get("pity", {}) is Dictionary else {}
	for c in CrateDB.IDS:
		var src: Dictionary = pin.get(c, {}) if pin.get(c, {}) is Dictionary else {}
		var dst: Dictionary = (d["pity"] as Dictionary)[c]
		for k in dst.keys():
			dst[k] = clampi(int(src.get(k, 0)), 0, 1000)
	var tin: Dictionary = r.get("tokens", {}) if r.get("tokens", {}) is Dictionary else {}
	(d["tokens"] as Dictionary)["field"] = clampi(int(tin.get("field", 0)), 0, 999)
	return d


static func _block(s: Dictionary) -> Dictionary:
	if not (s.get("crates", null) is Dictionary):
		s["crates"] = default_block()
	return s["crates"]


static func pity(s: Dictionary, crate: String) -> Dictionary:
	return (_block(s)["pity"] as Dictionary).get(crate, {})


static func tokens(s: Dictionary) -> int:
	return int((_block(s)["tokens"] as Dictionary).get("field", 0))


static func _node(s: Dictionary, id: String) -> int:
	var rf: Variant = s.get("reforge", null)
	if rf is Dictionary and (rf as Dictionary).get("nodes", null) is Dictionary:
		return int(((rf as Dictionary)["nodes"] as Dictionary).get(id, 0))
	return 0


static func _research(s: Dictionary, id: String) -> int:
	var rs: Variant = s.get("research", null)
	if rs is Dictionary and (rs as Dictionary).get("lvls", null) is Dictionary:
		return int(((rs as Dictionary)["lvls"] as Dictionary).get(id, 0))
	return 0


## Field Crate coins: 2,500 x (1 + 0.25(T-1)) x (1 - 0.02 Crate Theory).
static func coin_cost(s: Dictionary, crate: String = "field") -> int:
	var d: Dictionary = CrateDB.get_def(crate)
	if int(d.get("coins", 0)) <= 0:
		return 0
	var t: int = Tiers.highest(s)
	var c: float = float(d["coins"]) * (1.0 + 0.25 * float(t - 1)) * (1.0 - 0.02 * float(mini(10, _research(s, "crate_theory"))))
	return int(round(c))


## Disclosed per-part odds in percent (crate_luck applied, renormalised).
static func odds(s: Dictionary, crate: String) -> Dictionary:
	var o: Dictionary = (CrateDB.get_def(crate).get("odds", {}) as Dictionary).duplicate()
	var lk: float = 1.0 + 0.05 * float(mini(5, _node(s, "crate_luck")))
	o["epic"] = float(o.get("epic", 0.0)) * lk
	o["legendary"] = float(o.get("legendary", 0.0)) * lk
	var tot: float = 0.0
	for r in CrateDB.RARITIES:
		tot += float(o.get(r, 0.0))
	for r in CrateDB.RARITIES:
		o[r] = 100.0 * float(o.get(r, 0.0)) / maxf(0.0001, tot)
	return o


static func roll_rarity(rng: RandomNumberGenerator, o: Dictionary) -> String:
	var x: float = rng.randf() * 100.0
	var acc: float = 0.0
	for r in CrateDB.RARITIES:
		acc += float(o.get(r, 0.0))
		if x < acc:
			return String(r)
	return "common"


## How the crate can be paid: "token" | "coins" | "keys" | "gems" ("" = none).
static func can_pay(s: Dictionary, crate: String, pay: String) -> bool:
	var d: Dictionary = CrateDB.get_def(crate)
	if d.is_empty():
		return false
	match pay:
		"token":
			return crate == "field" and tokens(s) > 0
		"coins":
			return int(d.get("coins", 0)) > 0 and int(s.get("coins", 0)) >= coin_cost(s, crate)
		"keys":
			return int(d.get("keys", 0)) > 0 and int(s.get("keys", 0)) >= int(d["keys"])
		"gems":
			return int(d.get("gems", 0)) > 0 and int(s.get("gems", 0)) >= int(d["gems"])
	return false


static func _pay(s: Dictionary, crate: String, pay: String) -> Dictionary:
	var d: Dictionary = CrateDB.get_def(crate)
	match pay:
		"token":
			var t: Dictionary = _block(s)["tokens"]
			t["field"] = int(t["field"]) - 1
			return {"token": 1}
		"coins":
			var c: int = coin_cost(s, crate)
			s["coins"] = int(s["coins"]) - c
			Stats.on_event(s, {"t": "coins_spent", "n": c})
			return {"coins": c}
		"keys":
			s["keys"] = int(s["keys"]) - int(d["keys"])
			return {"keys": int(d["keys"])}
		"gems":
			s["gems"] = int(s["gems"]) - int(d["gems"])
			return {"gems": int(d["gems"])}
	return {}


## Roll a crate's rarities with pity (mutates the pity counters).
static func roll(s: Dictionary, crate: String, rng: RandomNumberGenerator) -> Array:
	var d: Dictionary = CrateDB.get_def(crate)
	var o: Dictionary = odds(s, crate)
	var out: Array = []
	for k in int(d["parts"]):
		out.append(roll_rarity(rng, o))
	# Vault: at least one Rare+.
	if int(d.get("rare_plus", 0)) > 0:
		var best: int = 0
		for r in out:
			best = maxi(best, int(RANK[r]))
		if best < 1:
			out[0] = "rare"
	# Pity: each tracked rarity (lowest first) after N-1 misses.
	var pt: Dictionary = pity(s, crate)
	var keys: Array = (d.get("pity", {}) as Dictionary).keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(RANK[a]) < int(RANK[b]))
	for pr in keys:
		var need: int = int(RANK[pr])
		var hit: bool = false
		for r in out:
			if int(RANK[r]) >= need:
				hit = true
		if not hit and int(pt.get(pr, 0)) + 1 >= int((d["pity"] as Dictionary)[pr]):
			var lo: int = 0
			for j in out.size():
				if int(RANK[out[j]]) < int(RANK[out[lo]]):
					lo = j
			out[lo] = pr
			hit = true
		pt[pr] = 0 if hit else int(pt.get(pr, 0)) + 1
	# A legendary also satisfies a lower pity on the same open.
	for pr in keys:
		for r in out:
			if int(RANK[r]) >= int(RANK[pr]):
				pt[pr] = 0
	return out


## Open a crate: pay, roll (seeded), grant parts. [] when unaffordable.
static func open(s: Dictionary, crate: String, pay: String, rng: RandomNumberGenerator) -> Array:
	if not can_pay(s, crate, pay):
		return []
	var paid: Dictionary = _pay(s, crate, pay)
	var rar: Array = roll(s, crate, rng)
	var ev: Array = [{"t": "crate_open", "crate": crate, "paid": paid, "rarities": rar.duplicate()}]
	for r in rar:
		ev.append_array(Parts.grant(s, Parts.roll_id(rng, String(r)), crate))
	Parts._bump_stat(s, "crates_opened", 1)
	return ev
