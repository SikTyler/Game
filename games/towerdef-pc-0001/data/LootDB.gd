extends RefCounted
## In-run loot (V2 P5): every item comes from a run - no crates in the shop.
## The run only records TOKENS (an item from an elite, a cache from a boss /
## Courier / wave clear) on its own `loot_rng` stream; rarities are rolled
## when the run is banked (Loot.realize: the meta RNG, disclosed drop odds,
## luck and visible pity), so a run plays identically at any luck.
##   Elites / marked elites: ITEM_P (x Insight drop mult) for one item, at
##     most WAVE_ITEM_CAP (+2 per tier) item drops a wave.
##   Bosses: a Boss Vault (Tier 4+: RELIQUARY_P a Reliquary instead).
##   Couriers: an Elite Cache.
##   Wave clears: every FIELD_EVERY-th a Field Cache, else SCRAP_CRATE_P a
##     Scrap Crate.
## A cache holds `items` items; `min` guarantees its best one at that rarity
## or better (the rest roll the drop odds); Scrap is x tier.

const ITEM_P: float = 0.04
const WAVE_ITEM_CAP: int = 6
const RELIQUARY_TIER: int = 4
const RELIQUARY_P: float = 0.10
const FIELD_EVERY: int = 5
const SCRAP_CRATE_P: float = 0.25
const IDS: Array = ["scrap", "field", "elite", "boss", "reliquary"]
const CACHES: Dictionary = {
	"scrap":     {"name": "Scrap Crate", "items": 0, "min": "", "scrap": [6, 14], "desc": "Scrap from a cleared wave"},
	"field":     {"name": "Field Cache", "items": 2, "min": "", "scrap": [0, 0], "desc": "2 items (every 5th wave cleared)"},
	"elite":     {"name": "Elite Cache", "items": 3, "min": "rare", "scrap": [0, 0], "desc": "3 items, one Rare or better (Couriers)"},
	"boss":      {"name": "Boss Vault", "items": 4, "min": "epic", "scrap": [20, 40], "desc": "4 items, one Epic or better, + Scrap (bosses)"},
	"reliquary": {"name": "Reliquary", "items": 5, "min": "legendary", "scrap": [50, 90], "desc": "5 items, one Legendary or better, + Scrap (10% of Tier 4+ bosses)"},
}


static func get_def(id: String) -> Dictionary:
	return CACHES.get(id, CACHES["field"])


## Item level of a drop: the wave, +15 per tier above 1 (perk tier = 1 + ilvl/25).
static func ilvl(wave: int, tier: int) -> int:
	return clampi(wave + 15 * (maxi(1, tier) - 1), 1, 200)


## Item drops allowed per wave at a tier.
static func wave_cap(tier: int) -> int:
	return WAVE_ITEM_CAP + 2 * (maxi(1, tier) - 1)


## One-line disclosure of every source (the reveal's odds tooltip).
static func disclosure() -> String:
	var lines: Array = ["Elites: %d%% an item (max %d a wave, +2 per tier)" % [int(round(ITEM_P * 100.0)), WAVE_ITEM_CAP]]
	for id in IDS:
		lines.append("%s: %s" % [String(CACHES[id]["name"]), String(CACHES[id]["desc"])])
	return "\n".join(lines)
