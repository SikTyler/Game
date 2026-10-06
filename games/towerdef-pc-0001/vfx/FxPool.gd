extends RefCounted
## Fixed-size pool of fx records (tracers / rings / pops / bolts / damage
## numbers). Slots are preallocated Dictionaries reused forever: take() hands
## back a free slot (t <= 0) or recycles the oldest, so the hot path never
## grows an Array. A slot is live while its "t" (time left) is > 0.
## Fields other than t / life / age are written by the caller.

var items: Array[Dictionary] = []
var last: Dictionary = {}
var _next: int = 0


func _init(cap: int) -> void:
	for k in cap:
		items.append({"t": 0.0, "life": 0.0})


## A slot to fill. `life` seconds; returns the slot (live immediately).
func take(life: float) -> Dictionary:
	var n: int = items.size()
	var pick: int = -1
	for k in n:
		var i: int = (_next + k) % n
		if float(items[i]["t"]) <= 0.0:
			pick = i
			break
	if pick < 0:
		pick = _next   # pool full: recycle round-robin (oldest-ish)
	_next = (pick + 1) % n
	var d: Dictionary = items[pick]
	d["t"] = life
	d["life"] = life
	last = d
	return d


func update(delta: float) -> void:
	for d in items:
		var t: float = float(d["t"])
		if t > 0.0:
			d["t"] = t - delta


func clear() -> void:
	for d in items:
		d["t"] = 0.0
	last = {}


func live_count() -> int:
	var c: int = 0
	for d in items:
		if float(d["t"]) > 0.0:
			c += 1
	return c
