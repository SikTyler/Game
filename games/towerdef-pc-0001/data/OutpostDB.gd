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
const W: int = 14
const H: int = 10
const RELAY: Vector2i = Vector2i(2, 4)       # top-left of the 2x2 Relay
const START: Rect2i = Rect2i(0, 2, 6, 6)      # open from the start
## Expansion plots, unlocked in any order that stays adjacent to open land.
const PLOTS: Array = [
	Rect2i(6, 2, 4, 4), Rect2i(6, 6, 4, 4), Rect2i(0, 0, 6, 2), Rect2i(0, 8, 6, 2),
	Rect2i(6, 0, 4, 2), Rect2i(10, 0, 4, 4), Rect2i(10, 4, 4, 4), Rect2i(10, 8, 4, 2),
]
## Crystal Veins: 1 in the start area, 2 in plots (Gem Mine only).
const VEINS: Array = [Vector2i(1, 7), Vector2i(8, 8), Vector2i(12, 1)]
const BLOCKED: Array = [Vector2i(13, 9), Vector2i(0, 0), Vector2i(13, 4)]

## Buildings. size = [w, h] at rot 0 (rot 1 swaps). rate = L1 output per hour
## of `res`; storage_h = hours of L1 output the building stores at L1
## (+50% per level); time = L1 build seconds; power = draw.
const DEFS: Dictionary = {
	"relay": {"name": "Core Relay", "size": [2, 2], "power": 0, "coins": 3000, "gems": 0, "time": 600, "res": "", "rate": 0.0, "storage_h": 0.0, "max_lvl": 10},
	"mill": {"name": "Coin Mill", "size": [2, 2], "power": 2, "coins": 500, "gems": 0, "time": 120, "res": "coins", "rate": MILL_RATE, "storage_h": 8.0},
	"refinery": {"name": "Scrap Refinery", "size": [2, 2], "power": 3, "coins": 1500, "gems": 0, "time": 600, "res": "scrap", "rate": 6.0, "storage_h": 12.0},
	"gemmine": {"name": "Gem Mine", "size": [2, 2], "power": 4, "coins": 10000, "gems": 50, "time": 14400, "res": "gems", "rate": 1.0 / 3.0, "storage_h": 0.0, "hard_cap": 24.0},
	"keyforge": {"name": "Key Forge", "size": [2, 1], "power": 3, "coins": 8000, "gems": 0, "time": 3600, "res": "keys", "rate": 1.0 / 24.0, "storage_h": 0.0, "hard_cap": 3.0},
	"research": {"name": "Research Hall", "size": [3, 2], "power": 3, "coins": 1000, "gems": 0, "time": 900, "res": "", "rate": 0.0, "storage_h": 0.0},
	"barracks": {"name": "Barracks", "size": [2, 2], "power": 2, "coins": 3000, "gems": 0, "time": 1800, "res": "", "rate": 0.0, "storage_h": 0.0},
	"archive": {"name": "Archive", "size": [2, 2], "power": 1, "coins": 6000, "gems": 0, "time": 3600, "res": "", "rate": 0.0, "storage_h": 0.0},
	"warehouse": {"name": "Warehouse", "size": [2, 2], "power": 1, "coins": 2000, "gems": 0, "time": 1200, "res": "", "rate": 0.0, "storage_h": 0.0},
	"scrapyard": {"name": "Salvage Yard", "size": [2, 1], "power": 1, "coins": 4000, "gems": 0, "time": 1800, "res": "", "rate": 0.0, "storage_h": 0.0},
	"conduit": {"name": "Conduit", "size": [1, 1], "power": 0, "coins": 10, "gems": 0, "time": 0, "res": "", "rate": 0.0, "storage_h": 0.0, "max_lvl": 1},
	"beaconpost": {"name": "Outpost Beacon", "size": [1, 1], "power": 1, "coins": 2500, "gems": 0, "time": 600, "res": "", "rate": 0.0, "storage_h": 0.0},
}
const IDS: Array = ["mill", "refinery", "gemmine", "keyforge", "research", "barracks", "archive", "warehouse", "scrapyard", "conduit", "beaconpost"]
const GENERATORS: Array = ["mill", "refinery", "gemmine", "keyforge"]
## Quantity limits by Relay level (Mill / Refinery / Gem Mine / Key Forge).
const LIMITS: Array = [[1, {"mill": 2, "refinery": 1, "gemmine": 1, "keyforge": 0}],
	[3, {"mill": 3, "refinery": 1, "gemmine": 1, "keyforge": 1}],
	[5, {"mill": 4, "refinery": 2, "gemmine": 2, "keyforge": 1}],
	[8, {"mill": 5, "refinery": 2, "gemmine": 3, "keyforge": 1}]]

## Decor (SYSTEMS §5.5): 1x1 or 2x1, coins or gems, tags drive adjacency.
const DECOR: Dictionary = {
	"dc_smelter": {"name": "Smelter", "size": [2, 1], "coins": 800, "gems": 0, "tag": "industrial"},
	"dc_crates": {"name": "Crate Stack", "size": [1, 1], "coins": 150, "gems": 0, "tag": "industrial"},
	"dc_bookshelf": {"name": "Bookshelf", "size": [1, 1], "coins": 300, "gems": 0, "tag": "scholar"},
	"dc_orrery": {"name": "Orrery", "size": [1, 1], "coins": 2000, "gems": 0, "tag": "scholar"},
	"dc_yard": {"name": "Training Yard", "size": [2, 1], "coins": 1200, "gems": 0, "tag": "training"},
	"dc_dummy": {"name": "Target Dummy", "size": [1, 1], "coins": 200, "gems": 0, "tag": "training"},
	"dc_lamp": {"name": "Lamp", "size": [1, 1], "coins": 100, "gems": 0, "tag": "light", "power": 0.5},
	"dc_brazier": {"name": "Brazier", "size": [1, 1], "coins": 250, "gems": 0, "tag": "light"},
	"dc_tree": {"name": "Ash Tree", "size": [1, 1], "coins": 50, "gems": 0, "tag": "nature"},
	"dc_shrub": {"name": "Shrub", "size": [1, 1], "coins": 50, "gems": 0, "tag": "nature"},
	"dc_pond": {"name": "Pond", "size": [2, 1], "coins": 600, "gems": 0, "tag": "nature"},
	"dc_banner": {"name": "Banner", "size": [1, 1], "coins": 0, "gems": 20, "tag": "nature"},
	"dc_trophy": {"name": "Trophy", "size": [1, 1], "coins": 0, "gems": 40, "tag": "nature"},
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
