extends RefCounted
## Banking a run's loot (V2 P5). The run recorded tokens (Drops: items from
## elites, caches from bosses / Couriers / wave clears); here they become
## gear on the meta RNG (Gear's op stream: the same save + the same loot give
## the same items), at the disclosed drop odds shifted by luck, with visible
## pity counting every rolled item. A cache's best item is lifted to its
## guaranteed rarity if the roll fell short (that also resets the pity it
## satisfies). A full inventory salvages the overflow for Scrap.
## Events (in reveal order: caches, then loose items):
##   {t: "cache_open", cache, uids, scrap}
##   {t: "loot_item", uid, rar, kind, base, src, cache}
##   {t: "loot_salvaged", rar, scrap}         (inventory full)
##   {t: "loot_banked", scrap}                (all Scrap: loose + caches + salvage)

const Gear := preload("res://Gear.gd")
const GearGen := preload("res://GearGen.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const LootDB := preload("res://data/LootDB.gd")
const Labs := preload("res://Labs.gd")
const Outpost := preload("res://Outpost.gd")


## Rarity luck of a bank: the run's luck (Insight, gear Fortune Chips,
## drafts) + Appraisal research (P8) + Fortune Shrines (Outpost).
static func luck_of(s: Dictionary, loot: Dictionary) -> float:
	var shrine: float = float(Outpost.core_bonus(s).get("loot_luck", 0.0)) if s.get("outpost", null) is Dictionary else 0.0
	return float(int(loot.get("luck", 0))) + float(Labs.level(s, "appraisal")) + shrine


## Turn the run's tokens into items in the save. `scrap_mult` scales the
## Scrap (Reforge Scrapper). Returns events.
static func realize(s: Dictionary, loot: Dictionary, scrap_mult: float = 1.0) -> Array:
	var ev: Array = []
	var g: Dictionary = Gear.block(s)
	var luck: float = luck_of(s, loot)
	var tier: int = maxi(1, int(loot.get("tier", 1)))
	var scrap: int = maxi(0, int(loot.get("scrap", 0)))
	var items_ev: Array = []
	for c in (loot.get("caches", []) if loot.get("caches", []) is Array else []):
		var cd: Dictionary = c
		var id: String = String(cd.get("id", "field"))
		var d: Dictionary = LootDB.get_def(id)
		var r: RandomNumberGenerator = Gear._rng(g)
		var sc_rng: Array = d["scrap"]
		var cs: int = 0
		if int(sc_rng[1]) > 0:
			cs = r.randi_range(int(sc_rng[0]), int(sc_rng[1])) * tier
		scrap += cs
		var rolled: Array = []
		var cluck: float = luck + 2.0 * float(Labs.level(s, "cache_luck"))   # V2 P8 Cache Luck
		for k in int(d["items"]):
			rolled.append(GearGen.roll(r, "drop", {"ilvl": int(cd.get("ilvl", 1)), "luck": cluck, "bans": g["bans"]}, g["pity"]))
		var mn: String = String(d["min"])
		if mn != "" and not rolled.is_empty():
			var best: int = 0
			for k in rolled.size():
				if RarityDB.rank(String((rolled[k] as Dictionary)["rar"])) > RarityDB.rank(String((rolled[best] as Dictionary)["rar"])):
					best = k
			if not RarityDB.at_least(String((rolled[best] as Dictionary)["rar"]), mn):
				rolled[best] = GearGen.roll(r, "drop", {"kind": String((rolled[best] as Dictionary)["kind"]), "base": String((rolled[best] as Dictionary)["base"]), "rarity": mn, "ilvl": int(cd.get("ilvl", 1)), "bans": g["bans"]}, {})
				GearGen.note_pity(g["pity"], mn, "drop")
		rolled.sort_custom(func(a: Variant, b: Variant) -> bool: return RarityDB.rank(String((a as Dictionary)["rar"])) < RarityDB.rank(String((b as Dictionary)["rar"])))
		var uids: Array = []
		var cev: Array = []
		for it in rolled:
			var e: Dictionary = _keep(s, it, id, "cache")
			cev.append_array(e["ev"])
			scrap += int(e["scrap"])
			if int(e["uid"]) > 0:
				uids.append(int(e["uid"]))
		ev.append({"t": "cache_open", "cache": id, "uids": uids, "scrap": cs})
		ev.append_array(cev)
	for x in (loot.get("items", []) if loot.get("items", []) is Array else []):
		var xd: Dictionary = x
		var it2: Dictionary = GearGen.roll(Gear._rng(g), "drop", {"ilvl": int(xd.get("ilvl", 1)), "luck": luck, "bans": g["bans"]}, g["pity"])
		var e2: Dictionary = _keep(s, it2, "", String(xd.get("src", "elite")))
		items_ev.append_array(e2["ev"])
		scrap += int(e2["scrap"])
	ev.append_array(items_ev)
	var sc: int = int(round(float(scrap) * scrap_mult))
	s["scrap"] = int(s.get("scrap", 0)) + sc
	if sc > 0:
		ev.append({"t": "loot_banked", "scrap": sc})
	return ev


## Add one rolled item (or salvage it when the inventory is full).
static func _keep(s: Dictionary, it: Dictionary, cache: String, src: String) -> Dictionary:
	it["src"] = "cache:" + cache if cache != "" else src
	it["new"] = true
	var uid: int = Gear.add_item(s, it)
	if uid > 0:
		return {"uid": uid, "scrap": 0, "ev": [{"t": "loot_item", "uid": uid, "rar": String(it["rar"]), "kind": String(it["kind"]), "base": String(it["base"]), "src": src, "cache": cache}]}
	var v: int = Gear.salvage_value(it, s)
	return {"uid": 0, "scrap": v, "ev": [{"t": "loot_salvaged", "rar": String(it["rar"]), "scrap": v}]}


## Reveal order of a bank's events: the uids of every kept item.
static func revealed(ev: Array) -> Array:
	var out: Array = []
	for e in ev:
		if String((e as Dictionary).get("t", "")) == "loot_item":
			out.append(int((e as Dictionary)["uid"]))
	return out
