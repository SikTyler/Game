extends RefCounted
## Core levels (V2 P6): coins + milestone requirements. Every 5th level asks
## for Outpost buildings, the Relay or Core Theory research - and the Core
## tab shows each as a chip that jumps straight to it (Main.jump_to).
## Level L -> L+1 costs round(300 x 1.2^(L-1)) coins (Tune pc_core_cost_*).
## REQS[L] = what reaching level L needs: [kind, id, n] with kind
##   bld    an Outpost building of `id` built at level n or higher
##   relay  the Core Relay at level n
##   res    research `id` at level n

const TuneRef := preload("res://Tune.gd")

const COST_BASE: float = 300.0
const COST_GROWTH: float = 1.2
const REQS: Dictionary = {
	5: [["bld", "arsenal", 1]],
	10: [["bld", "arsenal", 3], ["res", "core_theory", 1]],
	15: [["bld", "reactor", 3], ["relay", "relay", 4]],
	20: [["bld", "optics", 2], ["res", "core_theory", 2]],
	25: [["bld", "bulwark_w", 4], ["relay", "relay", 5]],
	30: [["bld", "arsenal", 6], ["res", "core_theory", 3]],
	35: [["bld", "aegis_a", 4], ["relay", "relay", 6]],
	40: [["bld", "rangefinder", 5], ["res", "core_theory", 4]],
	45: [["bld", "reactor", 7], ["relay", "relay", 8]],
	50: [["bld", "arsenal", 9], ["res", "core_theory", 5]],
	55: [["bld", "forgeworks", 6], ["relay", "relay", 9]],
	60: [["relay", "relay", 10]],
	65: [["bld", "arsenal", 10]],
	70: [["bld", "reactor", 10]],
	75: [["bld", "optics", 10]],
}


## Coins for level L -> L+1.
static func cost(lvl: int) -> int:
	return int(round(TuneRef.num("pc_core_cost_base", COST_BASE) * pow(TuneRef.num("pc_core_cost_growth", COST_GROWTH), float(maxi(1, lvl) - 1))))


## What reaching level `to_lvl` needs ([] off the milestones).
static func reqs_for(to_lvl: int) -> Array:
	return REQS.get(to_lvl, [])


## The next level from `lvl` with requirements (0 if none left).
static func next_milestone(lvl: int) -> int:
	var best: int = 0
	for k in REQS.keys():
		if int(k) > lvl and (best == 0 or int(k) < best):
			best = int(k)
	return best
