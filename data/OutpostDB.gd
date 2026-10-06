extends RefCounted
## Outpost data (V2 P6). The Outpost is a persistent 48x32 map of small
## cells built outside runs (V2: the old 24x16 at half the cell size, so the
## same land holds about four times the buildings). Coordinates are cells (x
## right, y down). The Core Relay (3x3) is fixed centre-left with the
## Research Hall above it; a 12x12 start area is open; 17 plots open the rest.
## Terrain: Crystal Veins (the Deep Mine needs one) and 2x2 rocks.
##
## Building schema:
##   name, cat     production | core | scavenge | support | links
##   size          [w, h] at rot 0 (rot 1 swaps)
##   power         draw (Relay supply 10 + 4 / level)
##   coins         L1 price; level L -> L+1 costs coins x 1.6^(L-1)
##   max_lvl       (and never above Relay level + 2)
##   res, rate     generators: L1 output per hour of res (coins / scrap) or,
##                 for scavengers, item / cache tokens per hour
##   storage_h     hours of output a generator stores ("store": a token cap)
##   core          {pfx key: per level} permanent Core stats (core buildings)
##   relay         Relay level that unlocks it (P8 adds research licences)
##   tags, desc
## Quantity limits by Relay level: LIMITS (anything unlisted: 1).

## Coin Mill L1 coins/h (measured so the Outpost replaces the old Offline pay).
const MILL_RATE: float = 150.0   # V2 P10 eco ramp (owner: 2 Mills out-earned early runs): was 600
## V2 P10: coin producers (Mill, Deep Mine) grow x COIN_LVL a level (was +25%
## linear), so levelling - not spamming cheap Mills - is the road to a big
## hourly income: a Mill makes 150 / h at Lv1, ~1,600 / h at Lv10.
const COIN_LVL: float = 1.30
## Coin Mill output x (1 + MILL_TIER x (highest tier - 1)).
const MILL_TIER: float = 0.8
const W: int = 48
const H: int = 32
const RELAY: Vector2i = Vector2i(4, 8)        # top-left of the 3x3 Relay
const START: Rect2i = Rect2i(0, 4, 12, 12)    # open from the start
## Expansion plots (the V1 plots x2), unlocked in any order that stays
## adjacent to open land.
const PLOTS: Array = [
	Rect2i(12, 4, 8, 8), Rect2i(12, 12, 8, 8), Rect2i(0, 0, 12, 4), Rect2i(0, 16, 12, 4),
	Rect2i(12, 0, 8, 4), Rect2i(20, 0, 8, 8), Rect2i(20, 8, 8, 8), Rect2i(20, 16, 8, 4),
	Rect2i(28, 0, 10, 10), Rect2i(28, 10, 10, 10), Rect2i(38, 0, 10, 10), Rect2i(38, 10, 10, 10),
	Rect2i(0, 20, 12, 12), Rect2i(12, 20, 8, 12), Rect2i(20, 20, 8, 12), Rect2i(28, 20, 10, 12), Rect2i(38, 20, 10, 12),
]
## Crystal Veins: 1 in the start area, the rest inside plots (Deep Mine only).
const VEINS: Array = [Vector2i(2, 14), Vector2i(16, 16), Vector2i(24, 2), Vector2i(42, 4), Vector2i(32, 26), Vector2i(6, 28)]
## Rocks: 2x2 each (the V1 single rocks at the new scale).
const BLOCKED: Array = [Vector2i(26, 18), Vector2i(27, 18), Vector2i(26, 19), Vector2i(27, 19), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
	Vector2i(26, 8), Vector2i(27, 8), Vector2i(26, 9), Vector2i(27, 9), Vector2i(34, 14), Vector2i(35, 14), Vector2i(34, 15), Vector2i(35, 15),
	Vector2i(46, 30), Vector2i(47, 30), Vector2i(46, 31), Vector2i(47, 31), Vector2i(16, 24), Vector2i(17, 24), Vector2i(16, 25), Vector2i(17, 25),
	Vector2i(44, 18), Vector2i(45, 18), Vector2i(44, 19), Vector2i(45, 19)]


const DEFS: Dictionary = {
	"relay": {"name": "Core Relay", "cat": "support", "size": [3, 3], "power": 0, "coins": 3000, "res": "", "rate": 0.0, "storage_h": 0.0, "max_lvl": 10,
		"desc": "Powers and links the Outpost; its level caps every building's"},
	# ---- production
	"mill": {"name": "Coin Mill", "cat": "production", "size": [2, 2], "power": 2, "coins": 500, "growth": 1.45, "max_lvl": 15, "res": "coins", "rate": MILL_RATE, "storage_h": 8.0,
		"desc": "Coins per hour: x1.3 per level, +80% per tier above 1; +10% next to each Mill, +15% next to a Warehouse"},
	"refinery": {"name": "Scrap Refinery", "cat": "production", "size": [2, 2], "power": 3, "coins": 1500, "res": "scrap", "rate": 6.0, "storage_h": 6.0,
		"desc": "Scrap per hour; noisy Mills next door cost it 10%"},
	"gemmine": {"name": "Deep Mine", "cat": "production", "size": [2, 2], "power": 4, "coins": 10000, "res": "coins", "rate": MILL_RATE * 3.0, "storage_h": 8.0,
		"desc": "A big coin generator - needs a Crystal Vein"},
	# ---- permanent Core stats (built + linked; adjacency scales them)
	"arsenal": {"name": "Arsenal", "cat": "core", "size": [2, 2], "power": 2, "coins": 2500, "core": {"dmg": 0.07}, "relay": 1, "desc": "+7% all damage per level"},
	"reactor": {"name": "Reactor", "cat": "core", "size": [2, 2], "power": 1, "coins": 3000, "core": {"rate": 0.05}, "relay": 1, "desc": "+5% Weapon attack rate per level; heats Mills next to it"},
	"bulwark_w": {"name": "Bulwark Works", "cat": "core", "size": [2, 2], "power": 2, "coins": 2500, "core": {"core_hp": 0.05}, "relay": 1, "desc": "+5% Core max HP per level"},
	"aegis_a": {"name": "Aegis Array", "cat": "core", "size": [2, 2], "power": 2, "coins": 4000, "core": {"dr": 0.012}, "relay": 2, "desc": "-1.2% damage taken per level"},
	"optics": {"name": "Optics Lab", "cat": "core", "size": [2, 2], "power": 2, "coins": 4000, "core": {"crit": 0.01}, "relay": 2, "desc": "+1% crit chance per level"},
	"rangefinder": {"name": "Rangefinder", "cat": "core", "size": [2, 2], "power": 1, "coins": 3500, "core": {"range": 0.04}, "relay": 2, "desc": "+0.04 cell Weapon range per level"},
	"treasury": {"name": "Treasury", "cat": "core", "size": [2, 2], "power": 1, "coins": 3000, "core": {"run_cash": 0.06}, "relay": 1, "desc": "+6% all run cash per level"},
	"training": {"name": "Training Grounds", "cat": "core", "size": [2, 2], "power": 1, "coins": 3000, "core": {"xp": 0.03}, "relay": 3, "desc": "+3% run XP per level"},
	"shrine": {"name": "Fortune Shrine", "cat": "core", "size": [2, 2], "power": 1, "coins": 6000, "core": {"loot_luck": 1.0}, "relay": 3, "desc": "+1 loot luck per level (rarer drops when a run banks)"},
	"forgeworks": {"name": "Forge Works", "cat": "core", "size": [2, 2], "power": 2, "coins": 5000, "core": {"forge_disc": 0.02}, "relay": 4, "desc": "-2% Forge costs per level"},
	# ---- scavenging: gear while you are away (tokens bank like run loot)
	"scav_post": {"name": "Scavenger Post", "cat": "scavenge", "size": [2, 2], "power": 2, "coins": 4000, "res": "item", "rate": 1.0 / 6.0, "store": 4, "relay": 2,
		"desc": "Finds an item every 6 h (stores 4)"},
	"scav_den": {"name": "Scavenger Den", "cat": "scavenge", "size": [2, 2], "power": 3, "coins": 12000, "res": "field", "rate": 1.0 / 12.0, "store": 2, "relay": 4,
		"desc": "Finds a Field Cache every 12 h (stores 2)"},
	"scav_deep": {"name": "Deep Scavenger", "cat": "scavenge", "size": [3, 3], "power": 5, "coins": 40000, "res": "elite", "rate": 1.0 / 24.0, "store": 2, "relay": 7,
		"desc": "Finds an Elite Cache every 24 h (stores 2)"},
	# ---- support
	"research": {"name": "Research Hall", "cat": "support", "size": [3, 3], "power": 3, "coins": 1000, "res": "", "rate": 0.0, "storage_h": 0.0, "desc": "Research queues: 1 / 2 / 3 at Lv 1 / 4 / 8"},
	"barracks": {"name": "Barracks", "cat": "support", "size": [2, 2], "power": 2, "coins": 3000, "res": "", "rate": 0.0, "storage_h": 0.0, "desc": "Run troops: tier = level"},
	"archive": {"name": "Archive", "cat": "support", "size": [2, 2], "power": 1, "coins": 6000, "res": "", "rate": 0.0, "storage_h": 0.0, "desc": "Insight cap +1 / +2 at Lv 3 / 6; a banish at Lv 9"},
	"warehouse": {"name": "Warehouse", "cat": "support", "size": [2, 2], "power": 1, "coins": 2000, "res": "", "rate": 0.0, "storage_h": 0.0, "desc": "+10% storage within 2 cells; +15% to a touching Mill"},
	"scrapyard": {"name": "Salvage Yard", "cat": "support", "size": [2, 1], "power": 1, "coins": 4000, "res": "", "rate": 0.0, "storage_h": 0.0, "desc": "Salvage yard (Scrap logistics)"},
	"beaconpost": {"name": "Outpost Beacon", "cat": "support", "size": [1, 1], "power": 1, "coins": 2500, "res": "", "rate": 0.0, "storage_h": 0.0, "desc": "+5% to every building within 2 cells"},
	"pylon": {"name": "Pylon", "cat": "support", "size": [1, 1], "power": 1, "coins": 1500, "res": "", "rate": 0.0, "relay": 2, "desc": "+5% to buildings 2 cells away, -5% to anything touching it"},
	# ---- links
	"conduit": {"name": "Conduit", "cat": "links", "size": [1, 1], "power": 0, "coins": 10, "res": "", "rate": 0.0, "storage_h": 0.0, "max_lvl": 1, "desc": "Links buildings to the Relay"},
}
const IDS: Array = ["mill", "refinery", "gemmine", "arsenal", "reactor", "bulwark_w", "aegis_a", "optics", "rangefinder", "treasury", "training", "shrine", "forgeworks",
	"scav_post", "scav_den", "scav_deep", "research", "barracks", "archive", "warehouse", "scrapyard", "beaconpost", "pylon", "conduit"]
## Buildings that accrue stored output (coins / Scrap / tokens).
const GENERATORS: Array = ["mill", "refinery", "gemmine", "scav_post", "scav_den", "scav_deep"]
const SCAVENGERS: Array = ["scav_post", "scav_den", "scav_deep"]
const CORE_IDS: Array = ["arsenal", "reactor", "bulwark_w", "aegis_a", "optics", "rangefinder", "treasury", "training", "shrine", "forgeworks"]
const CATS: Array = ["production", "core", "scavenge", "support", "links"]
## Quantity limits by Relay level.
const LIMITS: Array = [[1, {"mill": 2, "refinery": 1, "gemmine": 1, "scav_post": 1, "pylon": 2}],
	[3, {"mill": 3, "refinery": 1, "gemmine": 1, "pylon": 3}],
	[5, {"mill": 4, "refinery": 2, "gemmine": 2, "scav_post": 2, "pylon": 4}],
	[6, {"arsenal": 2, "reactor": 2, "bulwark_w": 2, "aegis_a": 2, "optics": 2, "rangefinder": 2, "treasury": 2, "training": 2}],
	[8, {"mill": 5, "refinery": 2, "gemmine": 3, "scav_den": 2, "pylon": 6}]]

## Decor: 1x1 or 2x1, coins, tags drive adjacency (AdjDB).
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
	for row in LIMITS:
		var r: Array = row
		if relay_lvl >= int(r[0]) and (r[1] as Dictionary).has(id):
			lim = int((r[1] as Dictionary)[id])
	return lim


## Relay level a building needs (1 = from the start).
static func relay_req(id: String) -> int:
	return int(DEFS.get(id, {}).get("relay", 1))


## Art band suffix for a building level: _1 (L1-3), _2 (L4-7), _3 (L8-10).
static func art_id(id: String, lvl: int) -> String:
	if id == "conduit":
		return "op_conduit"
	var base: String = "op_beacon" if id == "beaconpost" else "op_" + id
	return base + ("_3" if lvl >= 8 else ("_2" if lvl >= 4 else "_1"))
