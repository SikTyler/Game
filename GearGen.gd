extends RefCounted
## Seeded gear rolls (V2 P4). One RNG stream in, one item out, in a fixed
## order: kind -> base -> rarity (luck, then visible pity) -> brand -> perks
## (drawn without replacement, weighted, bans and frame-only perks respected,
## tier from item level; the Forge caps at T5) -> name -> paint -> visual seed.
## Pity counters live in save.gear.pity and are updated here.
## Item: {uid, kind, base, brand, rar, ilvl, lvl, mw, seed, rr, perks:
##   [{id, t, q, lock}], paint: {p, s, g, pat}, name, fav, new, src}

const RarityDB := preload("res://data/RarityDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const BrandDB := preload("res://data/BrandDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const ModuleDB := preload("res://data/ModuleDB.gd")
const NameDB := preload("res://data/NameDB.gd")

const KINDS: Array = ["weapon", "module"]
const PATTERNS: int = 8   # paint pattern ids 0..7 (GearVis)


## Roll a new item. src: "forge" | "drop" | "start".
## opts: {kind, base, brand, rarity (forced), ilvl, luck, bans: {kind: [ids]}}
## pity: the save's {e, l, m} counters (mutated; ignored for a forced rarity).
static func roll(rng: RandomNumberGenerator, src: String, opts: Dictionary, pity: Dictionary) -> Dictionary:
	var kind: String = String(opts.get("kind", ""))
	if not KINDS.has(kind):
		kind = "weapon" if rng.randf() < 0.5 else "module"
	var base: String = String(opts.get("base", ""))
	var ids: Array = FrameDB.IDS if kind == "weapon" else ModuleDB.IDS
	if not ids.has(base):
		base = String(ids[rng.randi_range(0, ids.size() - 1)])
	var rar: String = String(opts.get("rarity", ""))
	if not RarityDB.IDS.has(rar):
		rar = roll_rarity(rng, src, float(opts.get("luck", 0.0)), pity)
	var brand: String = String(opts.get("brand", ""))
	if not BrandDB.IDS.has(brand):
		brand = String(BrandDB.IDS[rng.randi_range(0, BrandDB.IDS.size() - 1)])
	var ilvl: int = maxi(1, int(opts.get("ilvl", 1)))
	var cap: int = AffixDB.FORGE_TIER_CAP if src != "drop" else AffixDB.MAX_TIER
	var n: int = int(RarityDB.get_def(rar)["perks"])
	var bans: Array = (opts.get("bans", {}) as Dictionary).get(kind, []) if opts.get("bans", {}) is Dictionary else []
	var perks: Array = roll_perks(rng, kind, base, n, AffixDB.tier_for(ilvl, cap), [], bans)
	if rar == "exotic":
		# the signature perk: one more, at the top tier the source allows
		var sig: Array = roll_perks(rng, kind, base, 1, cap, perks, bans)
		for sp in sig:
			(sp as Dictionary)["sig"] = true
		perks.append_array(sig)
	var seed_v: int = rng.randi()
	var bd: Dictionary = BrandDB.get_def(brand)
	var base_name: String = String((FrameDB.get_def(base) if kind == "weapon" else ModuleDB.get_def(base))["name"])
	return {
		"uid": 0, "kind": kind, "base": base, "brand": brand, "rar": rar, "ilvl": ilvl, "lvl": 1, "mw": 0,
		"seed": seed_v, "rr": 0, "perks": perks,
		"paint": {"p": String((bd["palette"] as Array)[0]), "s": String((bd["palette"] as Array)[1]), "g": String((bd["palette"] as Array)[2]), "pat": rng.randi_range(0, PATTERNS - 1)},
		"name": NameDB.make(seed_v, bd["syl"], base_name, rar), "fav": false, "new": true, "src": src,
	}


## The live odds (percent, sums to 100) of the next roll from `src`: the
## source table, luck-shifted, then visible pity - from a group's soft count
## its share rises linearly to 100% on the hard roll. The Forge shows these.
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
			continue   # this source cannot roll the group (the Forge never rolls Mythic)
		var boost: float = clampf(float(n + 2 - soft) / float(hard - soft + 1), 0.0, 1.0)
		var target: float = pg + (100.0 - pg) * boost
		var below: float = 100.0 - pg
		for r in RarityDB.IDS:
			if RarityDB.at_least(String(r), floor_r):
				odds[r] = float(odds[r]) * target / pg
			elif below > 0.0:
				odds[r] = float(odds[r]) * (100.0 - target) / below
	return odds


## Roll a rarity at odds_now() and advance / reset the pity counters.
static func roll_rarity(rng: RandomNumberGenerator, src: String, luck: float, pity: Dictionary) -> String:
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
		# float rounding at the very top: the best rarity with odds
		for r in RarityDB.IDS:
			if float(odds[r]) > 0.0:
				out = String(r)
	note_pity(pity, out, src)
	return out


## Advance / reset the pity counters for a landed rarity.
static func note_pity(pity: Dictionary, rar: String, src: String) -> void:
	for g in ["e", "l", "m"]:
		if g == "m" and src != "drop":
			continue
		if RarityDB.at_least(rar, String((RarityDB.PITY[g] as Dictionary)["min"])):
			pity[g] = 0
		else:
			pity[g] = int(pity.get(g, 0)) + 1


## Draw n perks for an item without replacement (weights; frame affinity x2;
## bans and `have` ids excluded). Tier t for all; quality uniform.
static func roll_perks(rng: RandomNumberGenerator, kind: String, base: String, n: int, t: int, have: Array, bans: Array) -> Array:
	var pool: Array = AffixDB.pool(kind, base)
	var taken: Dictionary = {}
	for p in have:
		taken[String((p as Dictionary)["id"])] = true
	var aff: Array = (FrameDB.get_def(base)["affinity"] as Array) if kind == "weapon" else []
	var out: Array = []
	for k in n:
		var cands: Array = []
		var tot: float = 0.0
		for id in pool:
			if taken.has(id) or bans.has(id):
				continue
			var w: float = float((AffixDB.DEFS[id] as Dictionary)["w"]) * (2.0 if aff.has(id) else 1.0)
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
		out.append({"id": pick, "t": t, "q": snappedf(rng.randf(), 0.001), "lock": false})
	return out
