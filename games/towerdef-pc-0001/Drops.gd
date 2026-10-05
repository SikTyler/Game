extends RefCounted
## In-run loot (REDESIGN_SPEC §2.6, SYSTEMS §3.5). Pure + seeded from the run
## RNG so a selftest replays the same drops. Emits generic drop dicts; the
## Parts module (ENGINE-META) turns {kind:"part", rarity} into a concrete part
## when BaseMeta banks the run's loot:
##   {kind: "part", rarity, source} | {kind: "scrap", n, source} | {kind: "key", n, source}
##   | {kind: "core_core", n, source} (boss 25% x T, interim tune)
## Part cap per run = 3 plus Courier drops (Courier parts ignore the cap).

const TuneRef := preload("res://Tune.gd")

const PART_CAP: int = 3
const SOURCES: Dictionary = {
	"boss": {"p": 0.12, "odds": {"rare": 75.0, "epic": 22.0, "legendary": 3.0}},
	"elite": {"p": 0.03, "odds": {"common": 55.0, "rare": 35.0, "epic": 9.0, "legendary": 1.0}},
	"courier": {"p": 1.0, "odds": {"rare": 40.0, "epic": 45.0, "legendary": 15.0}},
}
const RARITY_ORDER: Array = ["common", "rare", "epic", "legendary"]
const KEY_P: float = 0.0005


static func empty_loot() -> Dictionary:
	return {"parts": [], "scrap": 0, "keys": 0, "core_cores": 0, "capped_parts": 0}


static func roll_rarity(rng: RandomNumberGenerator, odds: Dictionary) -> String:
	var tot: float = 0.0
	for r in RARITY_ORDER:
		tot += float(odds.get(r, 0.0))
	var x: float = rng.randf() * tot
	var acc: float = 0.0
	for r in RARITY_ORDER:
		acc += float(odds.get(r, 0.0))
		if x < acc:
			return String(r)
	return "rare"


## Roll the drops for one kill. ctx: {tier, drop_mult (Insight in_drop: 1+x),
## parts_so_far (non-Courier parts this run)}. Fixed RNG call order per source
## so replays are exact.
static func roll(rng: RandomNumberGenerator, source: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var dm: float = maxf(0.0, float(ctx.get("drop_mult", 1.0)))
	if SOURCES.has(source):
		var sd: Dictionary = SOURCES[source]
		var p: float = float(sd["p"]) * (1.0 if source == "courier" else dm)
		var hit: bool = source == "courier" or rng.randf() < p
		if hit:
			var rar: String = roll_rarity(rng, sd["odds"])
			if source == "courier" or int(ctx.get("parts_so_far", 0)) < TuneRef.int_of("pc_part_cap", PART_CAP):
				out.append({"kind": "part", "rarity": rar, "source": source})
			else:
				out.append({"kind": "part_capped", "rarity": rar, "source": source})
	if source == "boss":
		out.append({"kind": "scrap", "n": 5 * maxi(1, int(ctx.get("tier", 1))), "source": "boss"})
		if rng.randf() < minf(1.0, TuneRef.num("pc_boss_corecore_p", 0.25) * (1.0 + TuneRef.num("pc_corecore_tier", 1.0) * float(maxi(1, int(ctx.get("tier", 1))) - 1))):
			out.append({"kind": "core_core", "n": 1, "source": "boss"})
	if source == "courier":
		out.append({"kind": "key", "n": 1, "source": "courier"})
	elif rng.randf() < TuneRef.num("pc_key_p", KEY_P) * float(ctx.get("share", 1.0)):   # horde body: 1/m odds (per-wave keys conserved)
		out.append({"kind": "key", "n": 1, "source": "kill"})
	return out


## Fold drops into run.loot; returns the drops that counted.
static func add(loot: Dictionary, drops: Array) -> Array:
	var got: Array = []
	for x in drops:
		var d: Dictionary = x
		match String(d["kind"]):
			"part":
				(loot["parts"] as Array).append({"rarity": String(d["rarity"]), "source": String(d["source"])})
				got.append(d)
			"part_capped":
				loot["capped_parts"] = int(loot.get("capped_parts", 0)) + 1
			"scrap":
				loot["scrap"] = int(loot["scrap"]) + int(d["n"])
				got.append(d)
			"key":
				loot["keys"] = int(loot["keys"]) + int(d["n"])
				got.append(d)
			"core_core":
				loot["core_cores"] = int(loot.get("core_cores", 0)) + int(d["n"])
				got.append(d)
	return got


## Non-Courier parts already in the loot (the 3-part cap counts these).
static func capped_count(loot: Dictionary) -> int:
	var n: int = 0
	for p in loot.get("parts", []):
		if String((p as Dictionary)["source"]) != "courier":
			n += 1
	return n


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
