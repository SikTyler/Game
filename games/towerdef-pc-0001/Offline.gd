extends RefCounted
## Offline earnings (SPEC A5). 15% of the best recorded coins/min, +5% per
## Offline Rate lab level, capped at (4 + offcap) hours. Never beats active.

const TuneRef := preload("res://Tune.gd")
const Labs := preload("res://Labs.gd")


static func rate_per_min(s: Dictionary) -> float:
	var frac: float = TuneRef.num("offline_frac", 0.15)
	return frac * float(s.get("best_coin_rate", 0.0)) * (1.0 + 0.05 * float(Labs.level(s, "offrate")))


static func cap_minutes(s: Dictionary) -> int:
	return (TuneRef.int_of("offline_cap_base", 4) + Labs.level(s, "offcap")) * 60


static func compute(s: Dictionary, now: int) -> Dictionary:
	var last: int = int(s.get("last_seen", 0))
	if last == 0:
		return {"coins": 0, "minutes": 0}
	if now < last:
		s["last_seen"] = now
		return {"coins": 0, "minutes": 0}
	if now - last < TuneRef.int_of("offline_min", 300):
		return {"coins": 0, "minutes": 0}
	var minutes: int = clampi((now - last) / 60, 0, cap_minutes(s))
	return {"coins": int(floor(rate_per_min(s) * float(minutes))), "minutes": minutes}


## Pays the absence and stamps last_seen. double costs 2 gems (fails w/o mutation).
static func claim(s: Dictionary, now: int, double: bool = false) -> Array:
	var r: Dictionary = compute(s, now)
	var coins: int = int(r["coins"])
	if double:
		if int(s["gems"]) < 2 or coins <= 0:
			return []
		s["gems"] = int(s["gems"]) - 2
		coins *= 2
	s["last_seen"] = now
	if coins <= 0:
		return []
	s["coins"] = int(s["coins"]) + coins
	return [{"t": "offline", "coins": coins, "minutes": int(r["minutes"]), "doubled": double}]
