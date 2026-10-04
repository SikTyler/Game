extends RefCounted
## Roguelite draft (REDESIGN_SPEC §2.3). Pure + seeded: a hand of 3 (4 with
## wide_draft) picks rolled from PickDB by rarity, filtered by what the run can
## use right now. Cards:
##   {kind, id, fam, rarity, tags, [lvl, to]}
##   kind: "new" (place a building / hut on a free cell), "plus" (level up the
##   owned building, Lv lvl -> to), "pack", "special", "insight".
## Rarity weights C60/R28/E10/L2; each Luck point (max 10) moves 1 point of
## Common weight into Epic+ (split 10:2 between Epic and Legendary). Insight
## replaces a slot with p = insight_p per slot, at most one per hand, and is
## never luck-boosted beyond its own (1 + Luck*0.05) factor (computed by the
## caller). Eco guarantee G1: a hand with no eco card, or no non-eco card,
## rerolls its last slot once from the missing pool. Never Array.shuffle.
## ctx keys (all optional):
##   owned {id: lvl} buildings+huts on the grid, free (bool), free_outer (bool),
##   huts (int), packs {id: n}, specials {id: copies}, banished [ids], luck,
##   eco_mult, choices, insight_p, insight_ok, insight_blocked [ids],
##   guarantee ("" | "rare" | "epic"), weapons (weapon buildings owned).
## G2 starter guarantee: below 2 weapon buildings (and with a free cell) a
## hand always holds a weapon building.

const PickDB := preload("res://data/PickDB.gd")


const WEAPONS: Array = ["gun", "mortar", "tesla", "flak", "railgun", "frost"]


static func is_weapon(c: Dictionary) -> bool:
	return WEAPONS.has(String(c.get("id", "")))


static func rarity_weights(luck: int) -> Dictionary:
	var l: float = float(clampi(luck, 0, 10))
	return {
		"common": PickDB.RARITY_W["common"] - l,
		"rare": PickDB.RARITY_W["rare"],
		"epic": PickDB.RARITY_W["epic"] + l * 10.0 / 12.0,
		"legendary": PickDB.RARITY_W["legendary"] + l * 2.0 / 12.0,
	}


## The card this id would be right now, or {} when it is not offerable.
static func card_for(id: String, ctx: Dictionary) -> Dictionary:
	var d: Dictionary = PickDB.get_def(id)
	if d.is_empty():
		return {}
	if (ctx.get("banished", []) as Array).has(id):
		return {}
	var fam: String = String(d["fam"])
	var base: Dictionary = {"id": id, "fam": fam, "rarity": String(d["rarity"]), "tags": (d["tags"] as Array).duplicate()}
	match fam:
		"building", "hut":
			var owned: Dictionary = ctx.get("owned", {})
			if owned.has(id):
				var lv: int = int(owned[id])
				if lv >= PickDB.max_of(id):
					return {}
				base["kind"] = "plus"
				base["lvl"] = lv
				base["to"] = lv + 1
				return base
			if not bool(ctx.get("free", false)):
				return {}
			if id == "railgun" and not bool(ctx.get("free_outer", false)):
				return {}
			if fam == "hut" and int(ctx.get("huts", 0)) >= PickDB.HUT_MAX:
				return {}
			base["kind"] = "new"
			return base
		"pack":
			if int((ctx.get("packs", {}) as Dictionary).get(id, 0)) >= PickDB.max_of(id):
				return {}
			if id == "pk_barracks" and int(ctx.get("huts", 0)) <= 0:
				return {}
			base["kind"] = "pack"
			return base
		"special":
			var sp: Dictionary = ctx.get("specials", {})
			if int(sp.get(id, 0)) >= PickDB.SPECIAL_COPIES:
				return {}
			base["kind"] = "special"
			base["lvl"] = int(sp.get(id, 0))
			return base
		"insight":
			if (ctx.get("insight_blocked", []) as Array).has(id):
				return {}
			base["kind"] = "insight"
			return base
	return {}


static func _pool(ctx: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	for id in PickDB.ids():
		if used.has(id):
			continue
		var c: Dictionary = card_for(String(id), ctx)
		if not c.is_empty():
			out.append(c)
	return out


static func _weight(c: Dictionary, ctx: Dictionary) -> float:
	return float(ctx.get("eco_mult", 1.0)) if (c["tags"] as Array).has("eco") else 1.0


## Weighted pick from `pool` (seeded); -1 when empty.
static func _pick(rng: RandomNumberGenerator, pool: Array, ctx: Dictionary) -> int:
	if pool.is_empty():
		return -1
	var tot: float = 0.0
	for c in pool:
		tot += _weight(c, ctx)
	var r: float = rng.randf() * tot
	var acc: float = 0.0
	for k in pool.size():
		acc += _weight(pool[k], ctx)
		if r < acc:
			return k
	return pool.size() - 1


static func _roll_rarity(rng: RandomNumberGenerator, w: Dictionary, floor_r: String) -> String:
	var lo: int = maxi(0, PickDB.RARITIES.find(floor_r))
	var tot: float = 0.0
	for k in range(lo, PickDB.RARITIES.size()):
		tot += maxf(0.0, float(w[PickDB.RARITIES[k]]))
	var r: float = rng.randf() * tot
	var acc: float = 0.0
	for k in range(lo, PickDB.RARITIES.size()):
		acc += maxf(0.0, float(w[PickDB.RARITIES[k]]))
		if r < acc:
			return String(PickDB.RARITIES[k])
	return String(PickDB.RARITIES[PickDB.RARITIES.size() - 1])


## One non-Insight card of rarity >= floor_r (falls back to any rarity, nearest
## first, when that rarity has nothing offerable).
static func _roll_card(rng: RandomNumberGenerator, ctx: Dictionary, used: Dictionary, floor_r: String, only: String = "") -> Dictionary:
	var pool: Array = _pool(ctx, used)
	if only == "eco":
		pool = pool.filter(func(c: Variant) -> bool: return ((c as Dictionary)["tags"] as Array).has("eco"))
	elif only == "noneco":
		pool = pool.filter(func(c: Variant) -> bool: return not ((c as Dictionary)["tags"] as Array).has("eco"))
	if pool.is_empty():
		return {}
	var rar: String = _roll_rarity(rng, rarity_weights(int(ctx.get("luck", 0))), floor_r)
	var ri: int = PickDB.RARITIES.find(rar)
	var order: Array = [ri]
	for step in range(1, PickDB.RARITIES.size()):
		if ri + step < PickDB.RARITIES.size():
			order.append(ri + step)
		if ri - step >= 0:
			order.append(ri - step)
	var lo: int = maxi(0, PickDB.RARITIES.find(floor_r))
	for pass_n in 2:
		for k in order:
			if pass_n == 0 and int(k) < lo:
				continue
			var want: String = PickDB.RARITIES[int(k)]
			var sub: Array = pool.filter(func(c: Variant) -> bool: return String((c as Dictionary)["rarity"]) == want)
			var j: int = _pick(rng, sub, ctx)
			if j >= 0:
				return sub[j]
	return {}


static func roll_hand(rng: RandomNumberGenerator, ctx: Dictionary) -> Array:
	var n: int = maxi(1, int(ctx.get("choices", 3)))
	var hand: Array = []
	var used: Dictionary = {}
	var insight_done: bool = not bool(ctx.get("insight_ok", false))
	var p_in: float = float(ctx.get("insight_p", 0.0))
	for slot in n:
		if not insight_done and rng.randf() < p_in:
			var ins: Array = []
			for id in PickDB.INSIGHT:
				var ic: Dictionary = card_for(String(id), ctx)
				if not ic.is_empty():
					ins.append(ic)
			if not ins.is_empty():
				var c_in: Dictionary = ins[rng.randi_range(0, ins.size() - 1)]
				hand.append(c_in)
				used[String(c_in["id"])] = true
				insight_done = true
				continue
		var fl: String = String(ctx.get("guarantee", "common")) if slot == 0 else "common"
		if fl == "":
			fl = "common"
		var c: Dictionary = _roll_card(rng, ctx, used, fl)
		if c.is_empty():
			break
		hand.append(c)
		used[String(c["id"])] = true
	# G1 eco guarantee (seeded, once): the last non-Insight slot from the missing pool.
	var eco_n: int = 0
	var non_n: int = 0
	var last: int = -1
	for k in hand.size():
		var hc: Dictionary = hand[k]
		if String(hc["kind"]) == "insight":
			continue
		last = k
		if (hc["tags"] as Array).has("eco"):
			eco_n += 1
		else:
			non_n += 1
	if last >= 0 and hand.size() >= 2 and (eco_n == 0 or non_n == 0):
		var want: String = "eco" if eco_n == 0 else "noneco"
		var used2: Dictionary = used.duplicate()
		var rc: Dictionary = _roll_card(rng, ctx, used2, "common", want)
		# A guaranteed-rarity slot 0 is never the one swapped out.
		var keep0: bool = last == 0 and String(ctx.get("guarantee", "")) not in ["", "common"]
		if not rc.is_empty() and not keep0:
			hand[last] = rc
	# G2 starter guarantee: while fewer than 2 weapon buildings stand and a cell
	# is free, the middle slot is a weapon building (keeps early runs fair).
	if int(ctx.get("weapons", 99)) < 2 and bool(ctx.get("free", false)) and hand.size() >= 2:
		var has_w: bool = false
		for c in hand:
			has_w = has_w or is_weapon(c)
		if not has_w:
			var used3: Dictionary = {}
			for c in hand:
				used3[String((c as Dictionary)["id"])] = true
			var wp: Array = _pool(ctx, used3).filter(func(c: Variant) -> bool: return is_weapon(c) and String((c as Dictionary)["kind"]) == "new")
			var wi: int = _pick(rng, wp, ctx)
			if wi >= 0:
				# replace a non-eco, non-Insight slot (keeps G1 + Insight intact)
				var slot: int = -1
				for k in range(hand.size() - 1, -1, -1):
					var hk: Dictionary = hand[k]
					if String(hk["kind"]) != "insight" and not (hk["tags"] as Array).has("eco"):
						slot = k
						break
				if slot >= 0:
					hand[slot] = wp[wi]
	return hand


## One replacement card for slot `idx` of `hand` (banish), never a duplicate.
static func replace_card(rng: RandomNumberGenerator, ctx: Dictionary, hand: Array, idx: int) -> Dictionary:
	var used: Dictionary = {}
	for c in hand:
		used[String((c as Dictionary)["id"])] = true
	return _roll_card(rng, ctx, used, "common")
