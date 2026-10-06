extends RefCounted
## Core Reforge prestige (REDESIGN_SPEC §3.4, SYSTEMS §6, R4-R6). Pure static:
##   save.reforge = {count, coins_since, nodes: {id: lvl}, cum_shards,
##                   last_at, best_time_to_prev}
##   save.shards  = unspent Reforge Shards
## Gate (R4): best wave >= pc_reforge_gate_wave (40) on any tier, or
## >= 1,000,000 coins earned since the last Reforge. Shards = floor(k *
## sqrt(coins_since / 10,000)), k = pc_reforge_k x (1 + 0.1 shard_yield), +5 on
## the first Reforge (R5). Resets / keeps exactly ReforgeDB.RESETS / KEEPS (R6).

const ReforgeDB := preload("res://data/ReforgeDB.gd")
const Outpost := preload("res://Outpost.gd")
const Cores := preload("res://Cores.gd")
const Stats := preload("res://Stats.gd")
const TuneRef := preload("res://Tune.gd")


static func default_block() -> Dictionary:
	return {"count": 0, "coins_since": 0, "nodes": {}, "cum_shards": 0, "last_at": 0, "best_time_to_prev": 0.0}


static func normalize_block(raw: Variant) -> Dictionary:
	var d: Dictionary = default_block()
	if not (raw is Dictionary):
		return d
	var r: Dictionary = raw
	d["count"] = maxi(0, int(r.get("count", 0)))
	d["coins_since"] = maxi(0, int(r.get("coins_since", 0)))
	d["cum_shards"] = maxi(0, int(r.get("cum_shards", 0)))
	d["last_at"] = maxi(0, int(r.get("last_at", 0)))
	d["best_time_to_prev"] = maxf(0.0, float(r.get("best_time_to_prev", 0.0)))
	var nin: Variant = r.get("nodes", r.get("tree", {}))
	var nodes: Dictionary = {}
	if nin is Dictionary:
		for k in (nin as Dictionary).keys():
			var id: String = "banish_plus" if String(k) == "banish+" else String(k)
			if ReforgeDB.NODES.has(id):
				nodes[id] = clampi(int((nin as Dictionary)[k]), 0, int((ReforgeDB.NODES[id] as Dictionary)["max"]))
	d["nodes"] = nodes
	return d


static func _rf(s: Dictionary) -> Dictionary:
	if not (s.get("reforge", null) is Dictionary):
		s["reforge"] = default_block()
	var r: Dictionary = s["reforge"]
	if not (r.get("nodes", null) is Dictionary):
		r["nodes"] = {}
	return r


static func node(s: Dictionary, id: String) -> int:
	return int((_rf(s)["nodes"] as Dictionary).get(id, 0))


static func count(s: Dictionary) -> int:
	return int(_rf(s).get("count", 0))


## Every coin the player earns (runs, Outpost) feeds the shard formula.
static func on_coins(s: Dictionary, n: int) -> void:
	if n > 0:
		var r: Dictionary = _rf(s)
		r["coins_since"] = int(r.get("coins_since", 0)) + n


static func best_wave_any(s: Dictionary) -> int:
	var b: int = int(s.get("best_wave", 0))
	var bw: Variant = s.get("best_wave_by_tier", {})
	if bw is Dictionary:
		for k in (bw as Dictionary).keys():
			b = maxi(b, int((bw as Dictionary)[k]))
	return b


## Gate (R4): best wave >= 40 since the last Reforge (tier progress resets),
## or 1,000,000 coins since the last Reforge.
static func can_reforge(s: Dictionary) -> bool:
	var bw: int = 0
	var bwt: Variant = s.get("best_wave_by_tier", {})
	if bwt is Dictionary:
		for k in (bwt as Dictionary).keys():
			bw = maxi(bw, int((bwt as Dictionary)[k]))
	return bw >= TuneRef.int_of("pc_reforge_gate_wave", 40) or int(_rf(s)["coins_since"]) >= TuneRef.int_of("pc_reforge_coin_gate", 1000000)


## Effective shard multiplier k (ReforgeDB.SHARD_K, tunable, x shard_yield node).
static func shard_k(s: Dictionary) -> float:
	return TuneRef.num("pc_reforge_k", ReforgeDB.SHARD_K) * (1.0 + 0.1 * float(node(s, "shard_yield")))


static func shards_now(s: Dictionary) -> int:
	var k: float = shard_k(s)
	var l0: float = TuneRef.num("pc_reforge_l0", 10000.0)
	var n: int = int(floor(k * sqrt(maxf(0.0, float(_rf(s)["coins_since"])) / l0)))
	if count(s) == 0:
		n += TuneRef.int_of("pc_reforge_first_bonus", 5)
	return n


## Preview (AC-37 data): shards gained now, cumulative, worth-it, reset/keep.
static func preview(s: Dictionary) -> Dictionary:
	var n: int = shards_now(s)
	var cum: int = int(_rf(s)["cum_shards"])
	return {"ok": can_reforge(s), "shards": n, "cumulative": cum, "worth": n >= int(ceil(0.5 * float(cum))),
		"resets": ReforgeDB.RESETS.duplicate(), "keeps": ReforgeDB.KEEPS.duplicate(),
		"gate_wave": TuneRef.int_of("pc_reforge_gate_wave", 40), "coins_since": int(_rf(s)["coins_since"])}


## Reforge: pay shards, reset per R6, keep the rest. `now` stamps the loop.
static func reforge(s: Dictionary, now: int) -> Array:
	if not can_reforge(s):
		return []
	var r: Dictionary = _rf(s)
	var n: int = shards_now(s)
	var first: bool = int(r["count"]) == 0
	# Resets.
	s["coins"] = 0
	Cores._block(s)["lvl"] = 1
	var retain: float = 0.1 * float(node(s, "retain"))
	Outpost.reforge_reset(s, retain, now)
	if s.get("research", null) is Dictionary:
		var lv: Dictionary = (s["research"] as Dictionary).get("lvls", {})
		for k in lv.keys():
			lv[k] = 0
		(s["research"] as Dictionary)["running"] = []
	s["tier"] = 1
	s["best_wave_by_tier"] = {"1": 0}
	# Shards + bookkeeping.
	s["shards"] = int(s.get("shards", 0)) + n
	r["cum_shards"] = int(r["cum_shards"]) + n
	r["count"] = int(r["count"]) + 1
	r["coins_since"] = 0
	r["last_at"] = now
	if s.get("stats", null) is Dictionary:
		(s["stats"] as Dictionary)["reforges"] = int((s["stats"] as Dictionary).get("reforges", 0)) + 1
	return [{"t": "reforge", "count": int(r["count"]), "shards": n, "first": first}]


static func can_buy(s: Dictionary, id: String) -> bool:
	if not ReforgeDB.NODES.has(id):
		return false
	var lv: int = node(s, id)
	if lv >= int((ReforgeDB.NODES[id] as Dictionary)["max"]):
		return false
	if id != "root_forge" and node(s, "root_forge") <= 0:
		return false
	return int(s.get("shards", 0)) >= ReforgeDB.cost(id, lv)


static func buy(s: Dictionary, id: String) -> Array:
	if not can_buy(s, id):
		return []
	var lv: int = node(s, id)
	var c: int = ReforgeDB.cost(id, lv)
	s["shards"] = int(s["shards"]) - c
	(_rf(s)["nodes"] as Dictionary)[id] = lv + 1
	var ev: Array = [{"t": "shard_node", "id": id, "lvl": lv + 1, "shards": c}]
	if ReforgeDB.TEMPLATES.has(id):
		var tpl: Dictionary = ReforgeDB.TEMPLATES[id]
		var o: Dictionary = Outpost._o(s)
		var bps: Array = o["blueprints"]
		if bps.size() < Outpost.BLUEPRINTS_MAX:
			bps.append({"name": String(tpl["name"]), "layout": (tpl["layout"] as Array).duplicate(true)})
		var tot: int = 0
		for e in tpl["layout"]:
			tot += Outpost.cost(String((e as Dictionary)["id"]), 1)
		o["credit"] = int(o.get("credit", 0)) + tot / 5
		ev.append({"t": "blueprint_unlocked", "name": String(tpl["name"]), "credit": tot / 5})
	return ev


## Run-facing bundle (folded by BaseMeta.run_mods).
static func run_mods(s: Dictionary) -> Dictionary:
	return {
		"rf_dmg": ReforgeDB.bonus("might", node(s, "might")),
		"rf_hp": ReforgeDB.bonus("bulwark_p", node(s, "bulwark_p")),
		"rf_coin": ReforgeDB.amt("prosperity") * float(node(s, "prosperity")),
		"rf_start_cash": 25 * node(s, "starting_cash"),
	}
