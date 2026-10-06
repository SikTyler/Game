extends RefCounted
## P5 selftest stage: in-run loot tokens (Drops on the loot stream), the
## per-wave item cap, and banking (Loot.realize): caches with their
## guaranteed rarity, disclosed odds + luck, visible pity over a scripted
## 200-roll sequence, inventory overflow, and determinism (the same save +
## the same loot = the same items; a run's tokens never depend on luck).
## `t` is the selftest runner.

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Drops := preload("res://Drops.gd")
const Loot := preload("res://Loot.gd")
const LootDB := preload("res://data/LootDB.gd")
const Gear := preload("res://Gear.gd")
const RarityDB := preload("res://data/RarityDB.gd")


static func run(t) -> void:
	_tokens(t)
	_engine(t)
	_caches(t)
	_pity_luck(t)
	_bank(t)


static func _rng(sd: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = sd
	return r


static func _kinds(d: Array) -> Array:
	var out: Array = []
	for x in d:
		out.append(String((x as Dictionary)["kind"]) + ":" + String((x as Dictionary).get("cache", "")))
	return out


# ------------------------------------------------------------------ tokens

static func _tokens(t) -> void:
	var r := _rng(5)
	var l := _rng(6)
	var b: Array = Drops.roll(r, "boss", {"tier": 2, "wave": 30}, l)
	t._check("P5 drops: a boss drops 5*T Scrap + a Boss Vault at the wave's item level", _kinds(b) == ["scrap:", "cache:boss"] and int(b[0]["n"]) == 10 and int(b[1]["ilvl"]) == LootDB.ilvl(30, 2) and LootDB.ilvl(30, 2) == 45)
	t._check("P5 drops: a Courier drops 10*T Scrap + an Elite Cache", _kinds(Drops.roll(r, "courier", {"tier": 1}, l)) == ["scrap:", "cache:elite"])
	var rel: int = 0
	for k in 3000:
		for d in Drops.roll(r, "boss", {"tier": 4}, l):
			rel += 1 if String((d as Dictionary).get("cache", "")) == "reliquary" else 0
	var rel_lo: int = 0
	for k in 500:
		for d in Drops.roll(r, "boss", {"tier": 3}, l):
			rel_lo += 1 if String((d as Dictionary).get("cache", "")) == "reliquary" else 0
	t._check("P5 drops: Tier 4+ bosses drop a Reliquary 10% of the time (never below T4)", rel > 230 and rel < 380 and rel_lo == 0, str(rel))
	var items: int = 0
	for k in 20000:
		for d in Drops.roll(r, "elite", {"drop_mult": 1.0, "items_left": 5}, l):
			items += 1 if String((d as Dictionary)["kind"]) == "item" else 0
	t._check("P5 drops: elites drop an item 4% of the time", items > 680 and items < 920, str(items))
	var capped: int = 0
	for k in 2000:
		for d in Drops.roll(r, "elite", {"items_left": 0}, l):
			capped += 1 if String((d as Dictionary)["kind"]) == "item" else 0
	t._check("P5 drops: no item once the wave's allowance is spent", capped == 0)
	t._check("P5 drops: without the loot stream no tokens drop (Scrap only)", _kinds(Drops.roll(_rng(1), "boss", {"tier": 1})) == ["scrap:"])
	var w5: Array = Drops.wave_clear(l, 5, 1)
	var w10: Array = Drops.wave_clear(l, 10, 2)
	var crates: int = 0
	for k in 4000:
		for d in Drops.wave_clear(l, 7, 1):
			crates += 1 if String((d as Dictionary)["cache"]) == "scrap" else 0
	t._check("P5 drops: every 5th wave cleared drops a Field Cache; others 25% a Scrap Crate", _kinds(w5) == ["cache:field"] and _kinds(w10) == ["cache:field"] and crates > 880 and crates < 1120, str(crates))
	var loot: Dictionary = Drops.empty_loot()
	Drops.add(loot, [{"kind": "scrap", "n": 3}, {"kind": "item", "src": "elite", "ilvl": 12}, {"kind": "cache", "cache": "boss", "ilvl": 20}, {"kind": "junk"}])
	t._check("P5 drops: tokens fold into run loot (items, caches, Scrap)", int(loot["scrap"]) == 3 and (loot["items"] as Array).size() == 1 and int((loot["items"][0] as Dictionary)["ilvl"]) == 12 and (loot["caches"] as Array).size() == 1 and String((loot["caches"][0] as Dictionary)["id"]) == "boss")
	t._check("P5 drops: item level = wave + 15 per tier, 1..200", LootDB.ilvl(1, 1) == 1 and LootDB.ilvl(40, 3) == 70 and LootDB.ilvl(500, 9) == 200 and LootDB.wave_cap(1) == 6 and LootDB.wave_cap(3) == 10)
	var dis: String = LootDB.disclosure()
	t._check("P5 drops: every source is disclosed", dis.contains("Boss Vault") and dis.contains("Reliquary") and dis.contains("Elite Cache") and dis.contains("Field Cache") and dis.contains("4%"))


# ------------------------------------------------------------------ engine

static func _engine(t) -> void:
	# a wave of marked elites: the item cap holds; tokens replay with the seed
	var runs: Array = []
	for luck_ins in [0, 6]:
		var sv: Dictionary = BaseMeta.default_save()
		sv["insight"] = {"in_luck": luck_ins}
		var S = TowerState.new()
		S.setup(77, BaseMeta.normalize(sv))
		S.spawn_hold = true
		var ev: Array = []
		for k in 600:
			S.add_enemy({"kind": "elite", "pos": TowerState.CENTER + Vector2(0, 300), "hp": 0.0, "max_hp": 10.0, "size": 12.0, "spd": 0.0})
			S._reap(ev)
		runs.append(S)
	var A = runs[0]
	var B = runs[1]
	t._check("P5 run: elite item drops stop at the wave cap (6 at T1)", (A.loot["items"] as Array).size() == LootDB.wave_cap(1) and int(A.wave_items[A.wave]) == LootDB.wave_cap(1))
	t._check("P5 run: the same seed drops the same tokens at any luck (rarity is rolled at bank)", JSON.stringify(A.loot["items"]) == JSON.stringify(B.loot["items"]) and int(A.luck) != int(B.luck))
	var C = TowerState.new()
	C.setup(77, BaseMeta.normalize(BaseMeta.default_save()))
	t._check("P5 run: the loot stream never touches the wave / drop RNGs", A.rng.state == C.rng.state)
	var ab: Array = A.abandon()
	var go: Dictionary = (ab.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == "game_over"))[0]
	t._check("P5 run: run end carries the loot tokens with the run's luck and tier", ((go["loot"] as Dictionary)["items"] as Array).size() == 6 and int((go["loot"] as Dictionary)["luck"]) == int(A.luck) and int((go["loot"] as Dictionary)["tier"]) == 1)
	t._check("P5 run: banking realizes the tokens into items (events in reveal order)", ab.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == "loot_item").size() == 6 and Gear.count(A.save) == 7)


# ------------------------------------------------------------------ caches

static func _bank_one(cache: String, ilvl: int = 30, tier: int = 1, luck: int = 0, s: Dictionary = {}) -> Array:
	var sv: Dictionary = s if not s.is_empty() else BaseMeta.default_save()
	return Loot.realize(sv, {"scrap": 0, "items": [], "caches": [{"id": cache, "ilvl": ilvl}], "luck": luck, "tier": tier})


static func _caches(t) -> void:
	var bad: Array = []
	for id in ["field", "elite", "boss", "reliquary"]:
		var d: Dictionary = LootDB.get_def(String(id))
		for k in 60:
			var sv: Dictionary = BaseMeta.default_save()
			for j in k:
				Gear._rng(Gear.block(sv))   # vary the op stream
			var ev: Array = _bank_one(String(id), 40, 2, 0, sv)
			var its: Array = ev.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == "loot_item")
			var head: Dictionary = ev[0]
			var best: int = -1
			for e in its:
				best = maxi(best, RarityDB.rank(String((e as Dictionary)["rar"])))
			if its.size() != int(d["items"]) or String(head["t"]) != "cache_open" or (head["uids"] as Array).size() != its.size():
				bad.append("%s count" % id)
			elif String(d["min"]) != "" and best < RarityDB.rank(String(d["min"])):
				bad.append("%s min %d" % [id, best])
	t._check("P5 caches: Field 2 / Elite 3 (Rare+) / Boss Vault 4 (Epic+) / Reliquary 5 (Legendary+), header first", bad.is_empty(), str(bad))
	var asc: bool = true
	var ev2: Array = _bank_one("boss")
	var prev: int = -1
	for e in ev2:
		if String((e as Dictionary)["t"]) == "loot_item":
			asc = asc and RarityDB.rank(String(e["rar"])) >= prev
			prev = RarityDB.rank(String(e["rar"]))
	t._check("P5 caches: items reveal worst to best (the best comes last)", asc)
	var sv2: Dictionary = BaseMeta.default_save()
	var sc0: int = int(sv2["scrap"])
	var ev3: Array = _bank_one("boss", 30, 3, 0, sv2)
	var cs: int = int((ev3[0] as Dictionary)["scrap"])
	t._check("P5 caches: a Boss Vault adds 20-40 x tier Scrap", cs >= 60 and cs <= 120 and int(sv2["scrap"]) == sc0 + cs)
	var sv3: Dictionary = BaseMeta.default_save()
	var ev4: Array = _bank_one("scrap", 10, 2, 0, sv3)
	t._check("P5 caches: a Scrap Crate is 6-14 x tier Scrap, no items", ev4.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == "loot_item").is_empty() and int(sv3["scrap"]) >= 12 and int(sv3["scrap"]) <= 28)
	var top_t: int = 0
	var sv6: Dictionary = BaseMeta.default_save()
	_bank_one("field", 150, 1, 0, sv6)
	for u in Gear.uids(sv6):
		for p in Gear.item(sv6, int(u))["perks"]:
			top_t = maxi(top_t, int((p as Dictionary)["t"]))
	t._check("P5 caches: drops reach T7 perks at item level 150+ (the Forge caps at T5)", top_t == 7)


# ------------------------------------------------------------------ pity + luck

static func _pity_luck(t) -> void:
	# a scripted 200-item sequence: Epic+ never misses 30 in a row
	var sv: Dictionary = BaseMeta.default_save()
	var toks: Array = []
	for k in 200:
		toks.append({"src": "elite", "ilvl": 20})
	var ev: Array = Loot.realize(sv, {"items": toks, "caches": [], "luck": 0, "tier": 1})
	var gap: int = 0
	var worst: int = 0
	var n: int = 0
	for e in ev:
		if String((e as Dictionary)["t"]) in ["loot_item", "loot_salvaged"]:   # the 200th overflows the inventory
			n += 1
			gap = 0 if RarityDB.at_least(String(e["rar"]), "epic") else gap + 1
			worst = maxi(worst, gap)
	t._check("P5 pity: 200 scripted drops never go 30 without an Epic+ (visible pity carries over)", n == 200 and worst < 30 and worst >= 10, str(worst))
	t._check("P5 pity: drops advance the save's pity counters", int(Gear.block(sv)["pity"]["l"]) > 0 and int(Gear.block(sv)["pity"]["m"]) > 0)
	var sv2: Dictionary = BaseMeta.default_save()
	Gear.block(sv2)["pity"]["e"] = 15
	_bank_one("boss", 30, 1, 0, sv2)
	var ep: int = int(Gear.block(sv2)["pity"]["e"])
	t._check("P5 pity: a Boss Vault's guaranteed Epic resets Epic pity", ep <= 3, str(ep))
	# luck: more Epic+ at luck 10 than at luck 0 (300 Field Caches each)
	var hi: Array = [0, 0]
	for li in 2:
		var s3: Dictionary = BaseMeta.default_save()
		var cs: Array = []
		for k in 1000:
			cs.append({"id": "field", "ilvl": 20})
		for e in Loot.realize(s3, {"items": [], "caches": cs, "luck": 10 * li, "tier": 1}):
			if String((e as Dictionary)["t"]) == "loot_item" and RarityDB.at_least(String(e["rar"]), "rare"):
				hi[li] = int(hi[li]) + 1
	t._check("P5 luck: the run's luck shifts drop odds up the ladder (Rare+ x1.28 at luck 10)", float(hi[1]) > float(hi[0]) * 1.12, str(hi))


# ------------------------------------------------------------------ bank

static func _bank(t) -> void:
	var loot: Dictionary = {"scrap": 12, "items": [{"src": "elite", "ilvl": 33}, {"src": "elite", "ilvl": 40}], "caches": [{"id": "elite", "ilvl": 30}, {"id": "field", "ilvl": 25}], "luck": 2, "tier": 2}
	var a: Dictionary = BaseMeta.default_save()
	var b: Dictionary = a.duplicate(true)
	var ea: Array = BaseMeta.bank_loot(a, loot.duplicate(true))
	var eb: Array = BaseMeta.bank_loot(b, loot.duplicate(true))
	t._check("P5 bank: the same save + the same loot = the same items and Scrap", JSON.stringify(Gear.block(a)["items"]) == JSON.stringify(Gear.block(b)["items"]) and int(a["scrap"]) == int(b["scrap"]) and JSON.stringify(ea) == JSON.stringify(eb))
	t._check("P5 bank: 2 loose items + 3 + 2 cache items, two cache headers, one Scrap total", Loot.revealed(ea).size() == 7 and ea.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == "cache_open").size() == 2 and ea.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == "loot_banked").size() == 1)
	var nw: bool = true
	for u in Loot.revealed(ea):
		nw = nw and bool(Gear.item(a, int(u))["new"]) and String(Gear.item(a, int(u))["src"]) != ""
	t._check("P5 bank: banked items are marked NEW with their source", nw)
	# a full inventory salvages the overflow
	var f: Dictionary = BaseMeta.default_save()
	while Gear.count(f) < Gear.INV_CAP:
		Gear.add_item(f, Gear.make("module", "echo"))
	var sc0: int = int(f["scrap"])
	var ef: Array = Loot.realize(f, {"items": [], "caches": [{"id": "field", "ilvl": 10}], "luck": 0, "tier": 1})
	t._check("P5 bank: a full inventory salvages the overflow for Scrap", Gear.count(f) == Gear.INV_CAP and ef.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == "loot_salvaged").size() == 2 and int(f["scrap"]) > sc0)
	var e0: Dictionary = BaseMeta.default_save()
	t._check("P5 bank: an empty run banks nothing", BaseMeta.bank_loot(e0, Drops.empty_loot()).is_empty() and Gear.count(e0) == 1)
