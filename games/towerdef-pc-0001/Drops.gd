extends RefCounted
## In-run loot (V2 P5): pure + seeded so a selftest replays the same drops.
## Scrap and Courier / marked-elite rolls use the run's `drop_rng` (as before
## P5: they shape the run); item and cache tokens use its own `loot_rng`, so
## the loot layer never perturbs a run. Rarities are rolled at bank time
## (Loot.realize). Entries:
##   {kind: "scrap", n, source}
##   {kind: "item", src, ilvl}            an item token (elites)
##   {kind: "cache", cache, ilvl, source} a cache token (LootDB.CACHES)
## Run loot: {scrap, items: [{src, ilvl}], caches: [{id, ilvl}], luck, tier}

const TuneRef := preload("res://Tune.gd")
const LootDB := preload("res://data/LootDB.gd")


static func empty_loot() -> Dictionary:
	return {"scrap": 0, "items": [], "caches": [], "luck": 0, "tier": 1}


## Roll the drops for one kill. ctx: {tier, wave, drop_mult (Insight in_drop:
## 1+x), items_left (this wave's item allowance), item_mult (Loot Theory)}. `lrng` = the loot stream
## (tokens); `rng` = drop_rng (Scrap). Fixed call order per source.
static func roll(rng: RandomNumberGenerator, source: String, ctx: Dictionary, lrng: RandomNumberGenerator = null) -> Array:
	var out: Array = []
	var t: int = maxi(1, int(ctx.get("tier", 1)))
	var dm: float = maxf(0.0, float(ctx.get("drop_mult", 1.0)))
	var il: int = LootDB.ilvl(int(ctx.get("wave", 1)), t)
	match source:
		"boss":
			out.append({"kind": "scrap", "n": 5 * t, "source": "boss"})
			if lrng != null:
				var rel: bool = t >= LootDB.RELIQUARY_TIER and lrng.randf() < LootDB.RELIQUARY_P
				out.append({"kind": "cache", "cache": "reliquary" if rel else "boss", "ilvl": il, "source": "boss"})
		"courier":
			out.append({"kind": "scrap", "n": 10 * t, "source": "courier"})
			if lrng != null:
				out.append({"kind": "cache", "cache": "elite", "ilvl": il, "source": "courier"})
		"elite":
			if rng.randf() < TuneRef.num("pc_elite_scrap_p", 0.25) * dm:
				out.append({"kind": "scrap", "n": t, "source": "elite"})
			if lrng != null and lrng.randf() < LootDB.ITEM_P * dm * maxf(0.0, float(ctx.get("item_mult", 1.0))) and int(ctx.get("items_left", 1)) > 0:
				out.append({"kind": "item", "src": "elite", "ilvl": il, "source": "elite"})
	return out


## A cleared wave: every FIELD_EVERY-th a Field Cache, else a chance at a
## Scrap Crate (loot stream only).
static func wave_clear(lrng: RandomNumberGenerator, wave: int, tier: int) -> Array:
	var il: int = LootDB.ilvl(wave, tier)
	if wave > 0 and wave % LootDB.FIELD_EVERY == 0:
		return [{"kind": "cache", "cache": "field", "ilvl": il, "source": "wave"}]
	if lrng.randf() < LootDB.SCRAP_CRATE_P:
		return [{"kind": "cache", "cache": "scrap", "ilvl": il, "source": "wave"}]
	return []


## Fold drops into run.loot; returns the drops that counted.
static func add(loot: Dictionary, drops: Array) -> Array:
	var got: Array = []
	for x in drops:
		var d: Dictionary = x
		match String(d["kind"]):
			"scrap":
				loot["scrap"] = int(loot.get("scrap", 0)) + int(d["n"])
				got.append(d)
			"item":
				if not (loot.get("items", null) is Array):
					loot["items"] = []
				(loot["items"] as Array).append({"src": String(d.get("src", "elite")), "ilvl": int(d.get("ilvl", 1))})
				got.append(d)
			"cache":
				if not (loot.get("caches", null) is Array):
					loot["caches"] = []
				(loot["caches"] as Array).append({"id": String(d["cache"]), "ilvl": int(d.get("ilvl", 1))})
				got.append(d)
	return got


## Courier: from wave 15, p = pc_courier_p per wave.
static func courier_roll(rng: RandomNumberGenerator, wave: int) -> bool:
	if wave < TuneRef.int_of("pc_courier_wave", 15):
		return false
	return rng.randf() < TuneRef.num("pc_courier_p", 0.006)


## Marked elite: from wave 8, ~1 per 4 waves.
static func elite_mark_roll(rng: RandomNumberGenerator, wave: int) -> bool:
	if wave < TuneRef.int_of("pc_mark_wave", 8):
		return false
	return rng.randf() < TuneRef.num("pc_mark_p", 0.25)
