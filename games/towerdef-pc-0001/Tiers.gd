extends RefCounted
## Tier ladder (SPEC A2). Pure static rules over the save Dictionary.
## Tier N unlocks when best_wave_by_tier[N-1] >= unlock_wave(N) and N-1 is
## itself unlocked. Tier 1 is always open.

const TuneRef := preload("res://Tune.gd")


static func tier_max() -> int:
	return TuneRef.int_of("tier_max", 8)


static func unlock_wave(n: int) -> int:
	# Meta-economy pass (mass-horde short runs): base 10 -> T2 @ w30, T3 @ w40
	# (was base 20: w40 / w50, tuned before the horde made runs shorter).
	return TuneRef.int_of("tier_unlock_base", 10) + TuneRef.int_of("tier_unlock_step", 10) * n


static func best_in(s: Dictionary, t: int) -> int:
	var bw: Dictionary = s.get("best_wave_by_tier", {})
	return int(bw.get(str(t), 0))


static func is_unlocked(s: Dictionary, n: int) -> bool:
	if n < 1 or n > tier_max():
		return false
	return n <= highest(s)


static func highest(s: Dictionary) -> int:
	var h: int = 1
	var mx: int = tier_max()
	while h < mx and best_in(s, h) >= unlock_wave(h + 1):
		h += 1
	return h


static func hp_mult(t: int) -> float:
	return pow(TuneRef.num("tier_hp_base", 1.5), float(maxi(1, t) - 1))


static func coin_mult(t: int) -> float:
	return 1.0 + TuneRef.num("tier_coin_step", 0.6) * float(maxi(1, t) - 1)


static func boss_every(t: int) -> int:
	return 8 if t >= 5 else 10


static func elite_weight(t: int) -> float:
	if t < 2:
		return 0.0
	return 0.16 if t >= 4 else 0.08


## Roster gate: may `kind` spawn at tier t, wave w?
static func allows(kind: String, t: int, wave: int) -> bool:
	match kind:
		"ranged":
			return wave >= 8
		"elite":
			return t >= 2 and wave >= 5
		"splitter":
			return t >= 3 and wave >= 5
		"mite":
			return false
	return true


## "T3 @ w40 in T2" style requirement text for a locked tier selector.
static func requirement(n: int) -> String:
	return "T%d @ w%d in T%d" % [n, unlock_wave(n), n - 1]
