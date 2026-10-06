extends RefCounted
## Outpost adjacency (V2 P6): signed rules between buildings. A rule gives
## its target `dst` the bonus `eff` for each `src` building near it:
##   r      reach: 1 = touching (4-neighbour), N = within N cells (Chebyshev)
##   rmin   (optional) minimum distance (Pylon: only the ring 2 cells away)
##   max    (optional) cap of this rule's stacked total
##   once   (optional) counts once however many sources are near
##   key    the readout part (OutpostView lines / tests)
## Sources must be built and linked to the Relay; "*" matches any building
## (not the source itself, Conduits never receive). A building's layout
## total is capped at +60% and floored at -40% (the Research tree scales the
## buffs, P8). Decor rules live in Outpost (lit Lamps, tags).

const BUFF_CAP: float = 0.60
const NERF_FLOOR: float = -0.40
const RULES: Array = [
	{"key": "mills", "src": "mill", "dst": "mill", "r": 1, "eff": 0.10, "max": 0.30, "text": "Mills next to each other share crews (+10% each, max +30%)"},
	{"key": "warehouse", "src": "warehouse", "dst": "mill", "r": 1, "eff": 0.15, "once": true, "text": "A touching Warehouse stores the coin (+15%)"},
	{"key": "noise", "src": "mill", "dst": "refinery", "r": 1, "eff": -0.10, "once": true, "text": "Mill noise slows a touching Refinery (-10%)"},
	{"key": "heat", "src": "reactor", "dst": "mill", "r": 1, "eff": -0.15, "once": true, "text": "Reactor heat warps a touching Mill (-15%)"},
	{"key": "reactor", "src": "reactor", "dst": "arsenal", "r": 1, "eff": 0.20, "once": true, "text": "A touching Reactor powers the Arsenal (+20%)"},
	{"key": "plating", "src": "bulwark_w", "dst": "aegis_a", "r": 1, "eff": 0.15, "once": true, "text": "Bulwark Works plates the Aegis Array (+15%)"},
	{"key": "lenses", "src": "optics", "dst": "rangefinder", "r": 1, "eff": 0.15, "once": true, "text": "Optics Lab lenses the Rangefinder (+15%)"},
	{"key": "drills", "src": "training", "dst": "barracks", "r": 1, "eff": 0.10, "once": true, "text": "Training Grounds drill the Barracks (+10%)"},
	{"key": "ledger", "src": "treasury", "dst": "mill", "r": 2, "eff": 0.05, "once": true, "text": "A Treasury within 2 cells keeps the books (+5%)"},
	{"key": "smelt", "src": "refinery", "dst": "forgeworks", "r": 1, "eff": 0.10, "once": true, "text": "A touching Refinery feeds the Forge Works (+10%)"},
	{"key": "omens", "src": "shrine", "dst": "scav_post", "r": 2, "eff": 0.10, "once": true, "text": "A Fortune Shrine within 2 cells guides the scavengers (+10%)"},
	{"key": "omens", "src": "shrine", "dst": "scav_den", "r": 2, "eff": 0.10, "once": true, "text": "A Fortune Shrine within 2 cells guides the scavengers (+10%)"},
	{"key": "omens", "src": "shrine", "dst": "scav_deep", "r": 2, "eff": 0.10, "once": true, "text": "A Fortune Shrine within 2 cells guides the scavengers (+10%)"},
	{"key": "rivals", "src": "scav_post", "dst": "scavenger", "r": 2, "eff": -0.15, "once": true, "text": "Scavengers within 2 cells compete (-15%)"},
	{"key": "rivals", "src": "scav_den", "dst": "scavenger", "r": 2, "eff": -0.15, "once": true, "text": "Scavengers within 2 cells compete (-15%)"},
	{"key": "rivals", "src": "scav_deep", "dst": "scavenger", "r": 2, "eff": -0.15, "once": true, "text": "Scavengers within 2 cells compete (-15%)"},
	{"key": "beacon", "src": "beaconpost", "dst": "*", "r": 2, "eff": 0.05, "once": true, "text": "An Outpost Beacon within 2 cells (+5%)"},
	{"key": "pylon", "src": "pylon", "dst": "*", "r": 2, "rmin": 2, "eff": 0.05, "once": true, "text": "A Pylon 2 cells away (+5%)"},
	{"key": "pylon_hum", "src": "pylon", "dst": "*", "r": 1, "eff": -0.05, "once": true, "text": "A touching Pylon hums (-5%)"},
]
## Targets a "scavenger" rule matches.
const SCAVENGERS: Array = ["scav_post", "scav_den", "scav_deep"]
## Buildings whose output a layout bonus scales ("*" rules reach only these):
## generators + scavengers (rate), Core buildings (stat), the Barracks (troops)
## and the Research Hall (lab speed).
const RECEIVERS: Array = ["mill", "refinery", "gemmine", "scav_post", "scav_den", "scav_deep",
	"arsenal", "reactor", "bulwark_w", "aegis_a", "optics", "rangefinder", "treasury", "training", "shrine", "forgeworks",
	"barracks", "research"]


## Does rule `rule` target a building of id `dst`?
static func targets(rule: Dictionary, dst: String) -> bool:
	var t: String = String(rule["dst"])
	if not RECEIVERS.has(dst):
		return false
	if t == "*":
		return true
	if t == "scavenger":
		return SCAVENGERS.has(dst)
	return t == dst


## Every rule that could touch a building of id `id` (as source or target):
## the Outpost palette's "works with" lines.
static func rules_for(id: String) -> Array:
	var out: Array = []
	for r in RULES:
		var rd: Dictionary = r
		if String(rd["src"]) == id or (String(rd["dst"]) != "*" and targets(rd, id)):
			out.append(rd)
	return out


## Does a layout bonus change anything for a building of id `id`?
static func receives(id: String) -> bool:
	return RECEIVERS.has(id)


## Rule rows sharing `key` count once (not per source)?
static func is_once(key: String) -> bool:
	for r in RULES:
		if String((r as Dictionary)["key"]) == key:
			return bool((r as Dictionary).get("once", false))
	return true


## Readout text of a part key ("decor" = decor tags).
static func text_of(key: String) -> String:
	if key == "decor":
		return "Decor next to it"
	for r in RULES:
		if String((r as Dictionary)["key"]) == key:
			return String((r as Dictionary)["text"])
	return key
