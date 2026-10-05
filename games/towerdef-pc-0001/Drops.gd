extends RefCounted
## In-run loot (V2 interim, P1): pure + seeded from the run's drop RNG so a
## selftest replays the same drops. P5 replaces this with LootDB items and
## caches; until then bosses, elites and Couriers drop Scrap:
##   {kind: "scrap", n, source}

const TuneRef := preload("res://Tune.gd")


static func empty_loot() -> Dictionary:
	return {"scrap": 0}


## Roll the drops for one kill. ctx: {tier, drop_mult (Insight in_drop: 1+x)}.
## Fixed RNG call order per source so replays are exact.
static func roll(rng: RandomNumberGenerator, source: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var t: int = maxi(1, int(ctx.get("tier", 1)))
	var dm: float = maxf(0.0, float(ctx.get("drop_mult", 1.0)))
	match source:
		"boss":
			out.append({"kind": "scrap", "n": 5 * t, "source": "boss"})
		"courier":
			out.append({"kind": "scrap", "n": 10 * t, "source": "courier"})
		"elite":
			if rng.randf() < TuneRef.num("pc_elite_scrap_p", 0.25) * dm:
				out.append({"kind": "scrap", "n": t, "source": "elite"})
	return out


## Fold drops into run.loot; returns the drops that counted.
static func add(loot: Dictionary, drops: Array) -> Array:
	var got: Array = []
	for x in drops:
		var d: Dictionary = x
		if String(d["kind"]) == "scrap":
			loot["scrap"] = int(loot.get("scrap", 0)) + int(d["n"])
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
