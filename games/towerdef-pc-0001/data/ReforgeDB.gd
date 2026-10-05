extends RefCounted
## Core Reforge shard tree (REDESIGN_SYSTEMS §6.1, REDESIGN_SPEC §3.4). One
## tree: root + Power / Economy / Mastery branches. Cost of the next level =
## base + step * L (L = levels owned). `core_hive` is deferred (§9); `retain`
## keeps a share of Outpost building levels through a Reforge (R6). Every
## node but the root needs root_forge.

const TuneRef := preload("res://Tune.gd")

## Shards = floor(SHARD_K x sqrt(coins since / L0)) (POWER_MODEL §6 k; balance pass 1.0 -> 1.6).
const SHARD_K: float = 1.6

const NODES: Dictionary = {
	"root_forge": {"name": "Forge Root", "branch": "root", "base": 1, "step": 0, "max": 1, "desc": "Unlocks the tree and the Lance Core"},
	"might": {"name": "Might", "branch": "power", "base": 2, "step": 1, "max": 20, "amt": 0.6, "stack": "mul", "desc": "x1.6 all damage per level (multiplies)"},
	"bulwark_p": {"name": "Bulwark", "branch": "power", "base": 2, "step": 1, "max": 20, "amt": 0.35, "stack": "mul", "desc": "x1.35 Core HP per level (multiplies)"},
	"head_start": {"name": "Head Start", "branch": "power", "base": 4, "step": 2, "max": 5, "desc": "+1 starting level on every Core Enhancement"},
	"core_ceiling": {"name": "Core Ceiling", "branch": "power", "base": 15, "step": 0, "max": 1, "desc": "Core max level 75"},
	"wide_draft": {"name": "Wide Draft", "branch": "power", "base": 25, "step": 0, "max": 1, "desc": "4 draft choices"},
	"banish_plus": {"name": "Banish+", "branch": "power", "base": 6, "step": 0, "max": 2, "desc": "+1 banish per run"},
	"prosperity": {"name": "Prosperity", "branch": "economy", "base": 2, "step": 1, "max": 20, "amt": 0.06, "desc": "+6% coins earned"},
	"outpost_p": {"name": "Outpost Output", "branch": "economy", "base": 3, "step": 1, "max": 10, "desc": "+8% Outpost production"},
	"starting_cash": {"name": "Starting Cash", "branch": "economy", "base": 2, "step": 1, "max": 10, "desc": "+25 starting run cash"},
	"shard_yield": {"name": "Shard Yield", "branch": "economy", "base": 5, "step": 2, "max": 10, "desc": "+10% Reforge shards"},
	"builder2": {"name": "Second Builder", "branch": "economy", "base": 12, "step": 0, "max": 1, "desc": "A 2nd Outpost builder"},
	"bp_mint": {"name": "Mint Ring", "branch": "economy", "base": 6, "step": 0, "max": 1, "desc": "Mint Ring blueprint + 20% build credit"},
	"bp_fortress": {"name": "Fortress Grid", "branch": "economy", "base": 6, "step": 0, "max": 1, "desc": "Fortress Grid blueprint + 20% build credit"},
	"tempo": {"name": "Tempo", "branch": "mastery", "base": 5, "step": 3, "max": 4, "desc": "+0.25x max game speed"},
	"scrap_p": {"name": "Scrapper", "branch": "mastery", "base": 2, "step": 1, "max": 10, "desc": "+10% Scrap"},
	"crate_luck": {"name": "Crate Luck", "branch": "mastery", "base": 4, "step": 2, "max": 5, "desc": "+5% relative Epic+ crate odds"},
	"retain": {"name": "Retain", "branch": "mastery", "base": 10, "step": 5, "max": 3, "desc": "Keep 10/20/30% of Outpost building levels"},
}
const IDS: Array = ["root_forge", "might", "bulwark_p", "head_start", "core_ceiling", "wide_draft", "banish_plus",
	"prosperity", "outpost_p", "starting_cash", "shard_yield", "builder2", "bp_mint", "bp_fortress",
	"tempo", "scrap_p", "crate_luck", "retain"]
## Prebuilt Outpost templates unlocked by bp_* nodes (start-area coordinates).
const TEMPLATES: Dictionary = {
	"bp_mint": {"name": "Mint Ring", "layout": [{"id": "mill", "x": 4, "y": 4, "rot": 0}, {"id": "mill", "x": 4, "y": 6, "rot": 0}, {"id": "warehouse", "x": 4, "y": 2, "rot": 0}]},
	"bp_fortress": {"name": "Fortress Grid", "layout": [{"id": "barracks", "x": 4, "y": 4, "rot": 0}, {"id": "archive", "x": 4, "y": 6, "rot": 0}, {"id": "conduit", "x": 2, "y": 6, "rot": 0}]},
}
const RESETS: Array = ["Coins", "Core levels", "Part levels (50% Scrap refund)", "Outpost building levels and Relay", "Research levels", "Tier progress (back to Tier 1)"]
const KEEPS: Array = ["Owned parts, stars, set unlocks, set specials", "Cores unlocked", "Cards, gems, Keys, Scrap, Insight", "Outpost layout, plots, decor, blueprints", "Achievements, stats, shards and the tree"]


## Per-level effect of a stat node (data "amt"; Tune seam pc_rf_<id>).
static func amt(id: String) -> float:
	return TuneRef.num("pc_rf_" + id, float((NODES.get(id, {}) as Dictionary).get("amt", 0.0)))


## Total bonus of a stat node at level L (POWER_MODEL §4: multiplicative
## within a branch when data "stack" == "mul": (1+amt)^L - 1; else amt x L).
## Tune seam pc_rf_stack_<id> = 0 forces additive.
static func bonus(id: String, lvl: int) -> float:
	var d: Dictionary = NODES.get(id, {})
	var a: float = amt(id)
	if String(d.get("stack", "")) == "mul" and TuneRef.int_of("pc_rf_stack_" + id, 1) != 0:
		return pow(1.0 + a, float(maxi(0, lvl))) - 1.0
	return a * float(maxi(0, lvl))


static func cost(id: String, lvl: int) -> int:
	var d: Dictionary = NODES.get(id, {})
	return int(d.get("base", 0)) + int(d.get("step", 0)) * maxi(0, lvl)
