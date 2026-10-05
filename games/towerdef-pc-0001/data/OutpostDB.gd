extends RefCounted
## Outpost data (REDESIGN_SYSTEMS §5, REDESIGN_SPEC §3.2). The Outpost is a
## persistent 14x10 map built outside runs. Coordinates are cells (x right,
## y down). The Core Relay (2x2) is fixed centre-left; a 6x6 start area is open;
## 8 expansion plots open the rest.
## Map deviation (documented): 8 plots of 4x4/4x5 cannot fit the 104 cells
## outside a 6x6 start area on a 14x10 map, so the plots are fixed border
## chunks of 8-16 cells that tile the map exactly (terrain is decorative,
## except Crystal Veins and 3 water cells that block building).

## Coin Mill L1 coins/h (SYSTEMS 60 is "the tuning knob"; 150 measured so the
## Outpost replaces the old Offline pay in the playtest campaign).
const MILL_RATE: float = 600.0
## Coin Mill output x (1 + MILL_TIER x (highest tier - 1)) (balance pass: 0.5 -> 0.8).
const MILL_TIER: float = 0.8
## FB1: "much larger" map — 24x16 (the original 14x10 block keeps its plots 0-7).
const W: int = 24
const H: int = 16
const RELAY: Vector2i = Vector2i(2, 4)       # top-left of the 2x2 Relay
const START: Rect2i = Rect2i(0, 2, 6, 6)      # open from the start
## Expansion plots, unlocked in any order that stays adjacent to open land.
const PLOTS: Array = [
	Rect2i(6, 2, 4, 4), Rect2i(6, 6, 4, 4), Rect2i(0, 0, 6, 2), Rect2i(0, 8, 6, 2),
	Rect2i(6, 0, 4, 2), Rect2i(10, 0, 4, 4), Rect2i(10, 4, 4, 4), Rect2i(10, 8, 4, 2),
	# FB1 grid chunks (indices 8+): east band, then the south band
	Rect2i(14, 0, 5, 5), Rect2i(14, 5, 5, 5), Rect2i(19, 0, 5, 5), Rect2i(19, 5, 5, 5),
	Rect2i(0, 10, 6, 6), Rect2i(6, 10, 4, 6), Rect2i(10, 10, 4, 6), Rect2i(14, 10, 5, 6), Rect2i(19, 10, 5, 6),
]
## Crystal Veins: 1 in the start area, the rest inside plots (Gem Mine only); hidden until the plot is bought.
const VEINS: Array = [Vector2i(1, 7), Vector2i(8, 8), Vector2i(12, 1), Vector2i(21, 2), Vector2i(16, 13), Vector2i(3, 14)]
const BLOCKED: Array = [Vector2i(13, 9), Vector2i(0, 0), Vector2i(13, 4), Vector2i(17, 7), Vector2i(23, 15), Vector2i(8, 12), Vector2i(22, 9)]

## Buildings. size = [w, h] at rot 0 (rot 1 swaps). rate = L1 output per hour
## of `res`; storage_h = hours of L1 output the building stores at L1
## (+50% per level); builds are instant (owner feedback #1); power = draw.
const DEFS: Dictionary = {
	"relay": {"name": "Core Relay", "size": [2, 2], "power": 0, "coins": 3000, "time": 0, "res": "", "rate": 0.0, "storage_h": 0.0, "max_lvl": 10},
	"mill": {"name": "Coin Mill", "size": [2, 2], "power": 2, "coins": 500, "time": 0, "res": "coins", "rate": MILL_RATE, "storage_h": 8.0},
	"refinery": {"name": "Scrap Refinery", "size": [2, 2], "power": 3, "coins": 1500, "time": 0, "res": "scrap", "rate": 6.0, "storage_h": 6.0},
	"gemmine": {"name": "Deep Mine", "size": [2, 2], "power": 4, "coins": 10000, "time": 0, "res": "coins", "rate": MILL_RATE * 3.0, "storage_h": 8.0},
	"research": {"name": "Research Hall", "size": [3, 2], "power": 3, "coins": 1000, "time": 0, "res": "", "rate": 0.0, "storage_h": 0.0},
	"barracks": {"name": "Barracks", "size": [2, 2], "power": 2, "coins": 3000, "time": 0, "res": "", "rate": 0.0, "storage_h": 0.0},
	"archive": {"name": "Archive", "size": [2, 2], "power": 1, "coins": 6000, "time": 0, "res": "", "rate": 0.0, "storage_h": 0.0},
	"warehouse": {"name": "Warehouse", "size": [2, 2], "power": 1, "coins": 2000, "time": 0, "res": "", "rate": 0.0, "storage_h": 0.0},
	"scrapyard": {"name": "Salvage Yard", "size": [2, 1], "power": 1, "coins": 4000, "time": 0, "res": "", "rate": 0.0, "storage_h": 0.0},
	"conduit": {"name": "Conduit", "size": [1, 1], "power": 0, "coins": 10, "time": 0, "res": "", "rate": 0.0, "storage_h": 0.0, "max_lvl": 1},
	"beaconpost": {"name": "Outpost Beacon", "size": [1, 1], "power": 1, "coins": 2500, "time": 0, "res": "", "rate": 0.0, "storage_h": 0.0},
}
const IDS: Array = ["mill", "refinery", "gemmine", "research", "barracks", "archive", "warehouse", "scrapyard", "conduit", "beaconpost"]
const GENERATORS: Array = ["mill", "refinery", "gemmine"]
## Quantity limits by Relay level (Mill / Refinery / Deep Mine).
const LIMITS: Array = [[1, {"mill": 2, "refinery": 1, "gemmine": 1}],
	[3, {"mill": 3, "refinery": 1, "gemmine": 1}],
	[5, {"mill": 4, "refinery": 2, "gemmine": 2}],
	[8, {"mill": 5, "refinery": 2, "gemmine": 3}]]

## Decor (SYSTEMS §5.5): 1x1 or 2x1, coins, tags drive adjacency.
const DECOR: Dictionary = {
	"dc_smelter": {"name": "Smelter", "size": [2, 1], "coins": 800, "tag": "industrial"},
	"dc_crates": {"name": "Crate Stack", "size": [1, 1], "coins": 150, "tag": "industrial"},
	"dc_bookshelf": {"name": "Bookshelf", "size": [1, 1], "coins": 300, "tag": "scholar"},
	"dc_orrery": {"name": "Orrery", "size": [1, 1], "coins": 2000, "tag": "scholar"},
	"dc_yard": {"name": "Training Yard", "size": [2, 1], "coins": 1200, "tag": "training"},
	"dc_dummy": {"name": "Target Dummy", "size": [1, 1], "coins": 200, "tag": "training"},
	"dc_lamp": {"name": "Lamp", "size": [1, 1], "coins": 100, "tag": "light", "power": 0.5},
	"dc_brazier": {"name": "Brazier", "size": [1, 1], "coins": 250, "tag": "light"},
	"dc_tree": {"name": "Ash Tree", "size": [1, 1], "coins": 50, "tag": "nature"},
	"dc_shrub": {"name": "Shrub", "size": [1, 1], "coins": 50, "tag": "nature"},
	"dc_pond": {"name": "Pond", "size": [2, 1], "coins": 600, "tag": "nature"},
	"dc_banner": {"name": "Banner", "size": [1, 1], "coins": 400, "tag": "nature"},
	"dc_trophy": {"name": "Trophy", "size": [1, 1], "coins": 800, "tag": "nature"},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func has(id: String) -> bool:
	return DEFS.has(id)


static func size_of(id: String, rot: int) -> Vector2i:
	var d: Dictionary = DEFS.get(id, DECOR.get(id, {"size": [1, 1]}))
	var sz: Array = d["size"]
	if rot % 2 == 1:
		return Vector2i(int(sz[1]), int(sz[0]))
	return Vector2i(int(sz[0]), int(sz[1]))


## Quantity limit of `id` at a Relay level (others: 1; conduits: unlimited).
static func limit(id: String, relay_lvl: int) -> int:
	if id == "conduit":
		return 999
	var lim: int = 1
	var found: bool = false
	for row in LIMITS:
		var r: Array = row
		if relay_lvl >= int(r[0]) and (r[1] as Dictionary).has(id):
			lim = int((r[1] as Dictionary)[id])
			found = true
	return lim if found else 1


## Art band suffix for a building level: _1 (L1-3), _2 (L4-7), _3 (L8-10).
static func art_id(id: String, lvl: int) -> String:
	if id == "conduit":
		return "op_conduit"
	var base: String = "op_beacon" if id == "beaconpost" else "op_" + id
	return base + ("_3" if lvl >= 8 else ("_2" if lvl >= 4 else "_1"))
