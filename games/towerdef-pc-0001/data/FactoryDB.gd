extends RefCounted
## Factory data (PLAYTEST_FEEDBACK_2 / plan WP3): the Factorio-style Outpost.
## A 96x64 tile map cut into 16x16 land chunks; the two centre chunks are open
## from the start, the rest are bought (deposits inside a locked chunk stay
## hidden until it is unlocked). Coordinates are cells (x right, y down).
## rot: 0 = east, 1 = south, 2 = west, 3 = north (the direction a belt,
## inserter, miner or splitter pushes items).

const W: int = 96
const H: int = 64
const CHUNK: int = 16
const CW: int = W / CHUNK   # 6
const CH: int = H / CHUNK   # 4
## Chunk index = cy * CW + cx. Open from the start: the two centre chunks.
const START_CHUNKS: Array = [8, 9]
## Coins for the n-th bought chunk (n = chunks bought so far).
const CHUNK_BASE: int = 2500
const CHUNK_GROWTH: float = 1.55

## Fixed simulation step (seconds). The tick is deterministic: entities are
## processed in ascending uid order.
const DT: float = 0.2
## Measured-throughput window (sim seconds) behind the away estimate.
const METER_WINDOW: float = 60.0
## Away/in-run production is capped by storage: base hours + hours per
## storage item slot (chest 48 -> +0.96 h, vault 320 -> +6.4 h), at most MAX.
const AWAY_BASE_H: float = 4.0
const AWAY_PER_SLOT_H: float = 0.02
const AWAY_MAX_H: float = 36.0

## Belts: item spacing (fraction of a tile) and speed (tiles / s) per tier.
const GAP: float = 0.5
const BELT_SPEED: Dictionary = {"belt": 2.0, "belt2": 4.0, "ug_in": 2.0, "ug_out": 2.0, "ug2_in": 4.0, "ug2_out": 4.0, "splitter": 2.0}
const UG_RANGE: int = 5          # an underground entrance links the first exit within 5 cells ahead
const INSERTER_CYCLE: float = 0.8   # seconds per swing at full power
const MINER_RATE: float = 0.5       # items / s per miner at full power
const MINER2_RATE: float = 1.0
const MACHINE_BUF: int = 2          # ingredient batches an input buffer holds
const OUT_CAP: int = 10             # finished items a machine holds before it blocks

## Items: [name, icon tint (view), category]. Raw items come from deposits.
const ITEMS: Dictionary = {
	"iron_ore": ["Iron Ore", "6f86a8", "raw"], "copper_ore": ["Copper Ore", "c9783f", "raw"],
	"coal": ["Coal", "3b3f46", "raw"], "crystal": ["Crystal", "59d6e8", "raw"], "scrap": ["Salvage", "8b8f7a", "raw"],
	"iron_plate": ["Iron Plate", "b9c6d6", "plate"], "copper_plate": ["Copper Plate", "e89a5c", "plate"],
	"alloy": ["Scrap Alloy", "a6ab8f", "plate"], "shard": ["Crystal Shard", "8ff0ff", "plate"],
	"gear": ["Gear", "9aa4b0", "part"], "wire": ["Copper Wire", "f2b46b", "part"], "circuit": ["Circuit", "6bd46b", "part"],
	"key_blank": ["Key Blank", "f2d34b", "product"], "data_card": ["Data Card", "8f7cf2", "product"], "part_kit": ["Part Kit", "e05a7a", "product"],
}
const ITEM_IDS: Array = ["iron_ore", "copper_ore", "coal", "crystal", "scrap", "iron_plate", "copper_plate", "alloy", "shard", "gear", "wire", "circuit", "key_blank", "data_card", "part_kit"]

## What the Core Relay pays per item: {currency: amount}. Currencies: coins,
## scrap (part levels), keys (crates), data (factory research).
const VALUE: Dictionary = {
	"iron_ore": {"coins": 0.6}, "copper_ore": {"coins": 0.6}, "coal": {"coins": 0.5}, "crystal": {"coins": 1.2}, "scrap": {"scrap": 0.08},
	"iron_plate": {"coins": 1.6}, "copper_plate": {"coins": 1.6}, "alloy": {"scrap": 0.3}, "shard": {"coins": 3.5},
	"gear": {"coins": 4.0}, "wire": {"coins": 0.9}, "circuit": {"coins": 10.0},
	"key_blank": {"keys": 0.25}, "data_card": {"data": 1.0}, "part_kit": {"scrap": 2.5},
}
const CURRENCIES: Array = ["coins", "scrap", "keys", "data"]

## Recipes: {in: {item: n}, out: {item: n}, time (s at full power), at: machine, tech}.
const RECIPES: Dictionary = {
	"iron_plate": {"name": "Iron Plate", "in": {"iron_ore": 1}, "out": {"iron_plate": 1}, "time": 1.6, "at": "smelter", "tech": ""},
	"copper_plate": {"name": "Copper Plate", "in": {"copper_ore": 1}, "out": {"copper_plate": 1}, "time": 1.6, "at": "smelter", "tech": ""},
	"alloy": {"name": "Scrap Alloy", "in": {"scrap": 2}, "out": {"alloy": 1}, "time": 3.2, "at": "smelter", "tech": ""},
	"shard": {"name": "Crystal Shard", "in": {"crystal": 1}, "out": {"shard": 1}, "time": 2.4, "at": "smelter", "tech": ""},
	"gear": {"name": "Gear", "in": {"iron_plate": 2}, "out": {"gear": 1}, "time": 1.0, "at": "assembler", "tech": ""},
	"wire": {"name": "Copper Wire", "in": {"copper_plate": 1}, "out": {"wire": 2}, "time": 0.5, "at": "assembler", "tech": ""},
	"circuit": {"name": "Circuit", "in": {"iron_plate": 1, "wire": 3}, "out": {"circuit": 1}, "time": 1.5, "at": "assembler", "tech": "electronics"},
	"data_card": {"name": "Data Card", "in": {"circuit": 1, "shard": 1}, "out": {"data_card": 1}, "time": 4.0, "at": "assembler", "tech": "data"},
	"part_kit": {"name": "Part Kit", "in": {"gear": 2, "circuit": 1, "alloy": 2}, "out": {"part_kit": 1}, "time": 6.0, "at": "assembler", "tech": "parts"},
	"key_blank": {"name": "Key Blank", "in": {"circuit": 2, "shard": 2, "alloy": 1}, "out": {"key_blank": 1}, "time": 8.0, "at": "assembler", "tech": "keys"},
}
const SMELT_BY_INPUT: Dictionary = {"iron_ore": "iron_plate", "copper_ore": "copper_plate", "scrap": "alloy", "crystal": "shard"}

## Buildings. size [w, h] at rot 0 (odd rots swap); power = draw (+ supply);
## cat = palette category; tech = research needed ("" = from the start);
## hub = fixed landmark that opens a meta screen (never deconstructed).
const DEFS: Dictionary = {
	"relay": {"name": "Core Relay", "size": [3, 3], "coins": 0, "power": 0, "supply": 4.0, "cat": "hub", "tech": "", "hub": "relay",
		"desc": "The factory's hub. Belts and inserters feed it; it converts goods into coins, scrap, keys and research data. Supplies 4 power."},
	"bay": {"name": "Core Bay", "size": [3, 3], "coins": 0, "power": 0, "cat": "hub", "tech": "", "hub": "bay", "desc": "Choose your Core, install and compare parts."},
	"crates": {"name": "Crate Depot", "size": [3, 3], "coins": 0, "power": 0, "cat": "hub", "tech": "", "hub": "crates", "desc": "Open crates for Core parts."},
	"research": {"name": "Research Lab", "size": [3, 3], "coins": 0, "power": 0, "cat": "hub", "tech": "", "hub": "research", "desc": "Run upgrades and factory technology."},
	"cards": {"name": "Card Hall", "size": [3, 3], "coins": 0, "power": 0, "cat": "hub", "tech": "", "hub": "cards", "desc": "Equip cards and open card chests."},
	"belt": {"name": "Belt", "size": [1, 1], "coins": 4, "power": 0, "cat": "logistics", "tech": "", "desc": "Moves items 2 tiles/s (4 items/s). Drag to lay a line."},
	"belt2": {"name": "Fast Belt", "size": [1, 1], "coins": 12, "power": 0, "cat": "logistics", "tech": "logistics2", "desc": "Moves items 4 tiles/s (8 items/s)."},
	"splitter": {"name": "Splitter", "size": [1, 2], "coins": 60, "power": 0, "cat": "logistics", "tech": "", "desc": "Takes items from the two belts behind it and alternates them between its two outputs."},
	"ug_in": {"name": "Underground Entrance", "size": [1, 1], "coins": 40, "power": 0, "cat": "logistics", "tech": "underground", "desc": "Items dive here and surface at the first Underground Exit up to 5 cells ahead."},
	"ug_out": {"name": "Underground Exit", "size": [1, 1], "coins": 40, "power": 0, "cat": "logistics", "tech": "underground", "desc": "Where items from an Underground Entrance surface."},
	"inserter": {"name": "Inserter", "size": [1, 1], "coins": 20, "power": 1.0, "cat": "logistics", "tech": "", "desc": "Picks items from behind it and drops them ahead: belts, chests, machines, the Relay."},
	"miner": {"name": "Miner", "size": [2, 2], "coins": 120, "power": 2.0, "cat": "production", "tech": "", "desc": "Mines the deposit under it (0.5 items/s) and drops onto the cell its arrow points at."},
	"miner2": {"name": "Deep Miner", "size": [2, 2], "coins": 900, "power": 4.0, "cat": "production", "tech": "mining2", "desc": "Mines 1 item/s."},
	"smelter": {"name": "Smelter", "size": [2, 2], "coins": 180, "power": 3.0, "cat": "production", "tech": "", "desc": "Smelts ore into plates (picks the recipe from its first ore). Needs inserters in and out."},
	"assembler": {"name": "Assembler", "size": [3, 3], "coins": 500, "power": 4.0, "cat": "production", "tech": "", "desc": "Builds components and products from a chosen recipe. Needs inserters in and out."},
	"chest": {"name": "Chest", "size": [1, 1], "coins": 40, "power": 0, "cat": "storage", "tech": "", "cap": 48, "desc": "Holds 48 items. Belts and inserters fill it. Every storage slot extends how long the factory keeps producing while you're away."},
	"vault": {"name": "Vault", "size": [2, 2], "coins": 700, "power": 0, "cat": "storage", "tech": "storage2", "cap": 320, "desc": "Holds 320 items and extends away production."},
	"windmill": {"name": "Wind Turbine", "size": [2, 2], "coins": 200, "power": 0, "supply": 3.0, "cat": "power", "tech": "", "desc": "Supplies 3 power to its network, no fuel."},
	"coal_gen": {"name": "Coal Generator", "size": [2, 2], "coins": 800, "power": 0, "supply": 12.0, "cat": "power", "tech": "coal_power", "fuel": "coal", "burn": 5.0,
		"desc": "Supplies 12 power while it burns coal (1 per 5 s). Feed it with an inserter or a belt."},
	"pole": {"name": "Power Pole", "size": [1, 1], "coins": 15, "power": 0, "cat": "power", "tech": "", "desc": "Powers machines within 2 cells and links to poles / generators within 6 cells."},
}
const PALETTE: Array = [
	["logistics", "Logistics", "fy_belt"], ["production", "Production", "fy_assembler"], ["power", "Power", "fy_windmill"], ["storage", "Storage", "fy_chest"],
]
const CAT_IDS: Dictionary = {
	"logistics": ["belt", "belt2", "splitter", "ug_in", "ug_out", "inserter"],
	"production": ["miner", "miner2", "smelter", "assembler"],
	"power": ["windmill", "coal_gen", "pole"],
	"storage": ["chest", "vault"],
}
const HUBS: Array = ["relay", "bay", "crates", "research", "cards"]
## Fixed hub positions (top-left), inside the start chunks (x 32..63, y 16..31).
const HUB_POS: Dictionary = {"relay": Vector2i(46, 22), "bay": Vector2i(34, 17), "crates": Vector2i(34, 26), "research": Vector2i(59, 17), "cards": Vector2i(59, 26)}
## Power nodes: supply radius (Chebyshev, cells around the footprint) and link range.
const POLE_REACH: int = 2
const LINK_RANGE: float = 6.5

## Facilities (levels kept on the factory; Outpost.level_of reads them).
const FACILITIES: Dictionary = {
	"research": {"name": "Research Lab", "coins": 1000, "max": 10, "desc": "Research queues: 1 / 2 / 3 at Lv1 / 4 / 8."},
	"barracks": {"name": "Barracks", "coins": 3000, "max": 10, "desc": "Each level: +10% troop HP and damage in runs."},
	"archive": {"name": "Archive", "coins": 6000, "max": 10, "desc": "Lv3 / 6: +1 / +2 Insight per run; Lv9: +1 banish per run."},
	"scrapyard": {"name": "Salvage Yard", "coins": 4000, "max": 1, "desc": "Salvaging parts returns more Scrap."},
}
const FAC_IDS: Array = ["research", "barracks", "archive", "scrapyard"]

## Factory technology (bought at the Research Lab with coins + data cards).
const TECH: Dictionary = {
	"electronics": {"name": "Electronics", "coins": 1500, "data": 0, "req": "", "desc": "Assembler recipe: Circuit (iron plate + 3 wire)."},
	"underground": {"name": "Underground Belts", "coins": 2000, "data": 0, "req": "", "desc": "Belts that tunnel up to 5 cells under other buildings."},
	"coal_power": {"name": "Coal Power", "coins": 3000, "data": 0, "req": "", "desc": "Coal Generator: 12 power while burning coal."},
	"data": {"name": "Data Science", "coins": 5000, "data": 0, "req": "electronics", "desc": "Assembler recipe: Data Card (circuit + shard) -> research data."},
	"logistics2": {"name": "Fast Logistics", "coins": 6000, "data": 20, "req": "underground", "desc": "Fast Belt: 4 tiles/s."},
	"storage2": {"name": "Vaults", "coins": 6000, "data": 20, "req": "", "desc": "Vault: 320 storage, +6.4 h away production."},
	"parts": {"name": "Part Fabrication", "coins": 9000, "data": 40, "req": "data", "desc": "Assembler recipe: Part Kit -> scrap for part levels."},
	"keys": {"name": "Key Forging", "coins": 12000, "data": 60, "req": "data", "desc": "Assembler recipe: Key Blank -> crate keys."},
	"mining2": {"name": "Deep Mining", "coins": 15000, "data": 80, "req": "coal_power", "desc": "Deep Miner: 1 item/s."},
}
const TECH_IDS: Array = ["electronics", "underground", "coal_power", "data", "logistics2", "storage2", "parts", "keys", "mining2"]

## Deposits: hand-placed starter patches in the open chunks + seeded patches
## elsewhere (DEPOSIT_SEED keeps every save's map identical). [res, x, y, w, h]
const STARTER_DEPOSITS: Array = [
	["iron_ore", 40, 18, 5, 4], ["copper_ore", 52, 26, 4, 4], ["coal", 40, 27, 4, 3], ["scrap", 53, 17, 3, 3],
]
const DEPOSIT_SEED: int = 7331
const DEPOSIT_RES: Array = ["iron_ore", "copper_ore", "coal", "crystal", "scrap", "iron_ore", "copper_ore", "crystal"]
## Rock cells (block building) per chunk, seeded.
const ROCKS_PER_CHUNK: int = 5


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func size_of(id: String, rot: int) -> Vector2i:
	var sz: Array = get_def(id).get("size", [1, 1])
	if rot % 2 == 1:
		return Vector2i(int(sz[1]), int(sz[0]))
	return Vector2i(int(sz[0]), int(sz[1]))


static func item_name(id: String) -> String:
	return String((ITEMS.get(id, [id]) as Array)[0])


static func chunk_rect(k: int) -> Rect2i:
	return Rect2i((k % CW) * CHUNK, (k / CW) * CHUNK, CHUNK, CHUNK)
