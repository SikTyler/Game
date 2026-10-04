extends RefCounted
## Corehold power model (POWER_MODEL.md §10, REDESIGN_SPEC §2.7). Pure, static,
## no RNG, no autoload: the engine, the playtest bot and the balance tables
## share this one source of truth for "how hard is wave w" vs "how strong is
## the player". The governing invariant is the power ratio
## R = effective_dps / required_dps(w, tier) staying inside band("frontier")
## at the wave a player dies on. All constants read via TuneRef with defaults
## equal to the design tables. The view never calls this for rules.

const TuneRef := preload("res://Tune.gd")
const EnemyDB := preload("res://data/EnemyDB.gd")

## Log-power weights for part valuation (POWER_MODEL §8).
const PART_W: Dictionary = {
	"dmg": 1.0, "rate": 1.0, "core_hp": 0.5, "regen": 0.4, "cash": 0.69, "coin": 0.3,
	"range": 0.3, "crit": 1.0, "core_dmg": 0.7, "bld_dmg": 0.5, "special": 0.3,
	"troop": 0.3, "armor": 0.3, "interest": 0.3, "luck": 0.3, "boss": 0.4,
}
const PART_BUDGET: Dictionary = {"common": 0.08, "rare": 0.12, "epic": 0.17, "legendary": 0.24, "special": 0.30}
const BANDS: Dictionary = {
	"early": Vector2(2.0, 4.0), "mid": Vector2(1.25, 2.0),
	"frontier": Vector2(0.8, 1.25), "wall": Vector2(0.0, 0.6),
}
const TROOP_UPTIME: float = 0.6


# ------------------------------------------------------------ difficulty
## HP growth per wave for a tier (R1: code is truth).
static func hp_growth(tier: int) -> float:
	if tier >= 3:
		return TuneRef.num("hp_growth_hi", 1.155)
	if tier == 2:
		return TuneRef.num("hp_growth_t2", 1.18)
	return TuneRef.num("hp_growth", 1.17)


## S(w): wave HP scale (tier only picks the growth rate; the tier HP factor is
## tier_hp()). Endless past pc_endless_soft_wave continues on a softer exponent.
static func hp_scale(wave: int, tier: int, endless: bool = false) -> float:
	var g: float = hp_growth(tier)
	var cap_w: int = TuneRef.int_of("pc_endless_soft_wave", 100)
	if endless and wave > cap_w:
		return pow(g, float(cap_w - 1)) * pow(TuneRef.num("pc_endless_hp_exp", 1.12), float(wave - cap_w))
	return pow(g, float(maxi(1, wave) - 1))


static func tier_hp(tier: int) -> float:
	return pow(TuneRef.num("tier_hp_base", 1.5), float(maxi(1, tier) - 1))


static func spawn_interval(wave: int) -> float:
	var base: float = TuneRef.num("spawn_base", 1.8)
	var decay: float = TuneRef.num("spawn_decay", 0.93)
	return maxf(TuneRef.num("min_spawn", 0.45), base * pow(decay, float(maxi(1, wave) - 1)))


static func spawns_per_wave(wave: int) -> float:
	return TuneRef.num("wave_time", 25.0) / spawn_interval(wave)


static func enemy_hp(kind: String, wave: int, tier: int) -> float:
	var d: Dictionary = EnemyDB.get_def(kind)
	return float(d.get("hp", 6.0)) * hp_scale(wave, tier) * tier_hp(tier)


static func enemy_dmg(kind: String, wave: int, tier: int) -> float:
	var d: Dictionary = EnemyDB.get_def(kind)
	return float(d.get("dmg", 4.0)) * pow(TuneRef.num("dmg_growth", 1.06), float(maxi(1, wave) - 1)) * tier_hp(tier)


## D(w, t): drone-equivalent HP arriving per second.
static func required_dps(wave: int, tier: int) -> float:
	return enemy_hp("drone", wave, tier) / spawn_interval(wave)


## P(w, t): incoming DPS on the Core when `leak_frac` of spawns reach the wall.
static func damage_pressure(wave: int, tier: int, leak_frac: float) -> float:
	return leak_frac * spawns_per_wave(wave) / TuneRef.num("wave_time", 25.0) * enemy_dmg("drone", wave, tier)


# ---------------------------------------------------------------- player
## snap = TowerState.power_snapshot(): core_dmg, core_rate, core_targets,
## buildings [{dps}], troops [{dps}], specials [{dps}], mult (global, default 1).
static func effective_dps(snap: Dictionary) -> float:
	var core: float = float(snap.get("core_dmg", 0.0)) * float(snap.get("core_rate", 0.0)) * maxf(1.0, float(snap.get("core_targets", 1.0)))
	var bld: float = 0.0
	for b in snap.get("buildings", []):
		bld += float((b as Dictionary).get("dps", 0.0))
	var trp: float = 0.0
	for t in snap.get("troops", []):
		trp += float((t as Dictionary).get("dps", 0.0))
	var spc: float = 0.0
	for s in snap.get("specials", []):
		spc += float((s as Dictionary).get("dps", 0.0))
	return (core + bld + trp * TROOP_UPTIME + spc) * float(snap.get("mult", 1.0))


## EHP = hp * (1 + armor_frac) * (1 + regen * T / hp) * (1 + shield_frac).
static func ehp(snap: Dictionary) -> float:
	var hp: float = maxf(1.0, float(snap.get("core_hp", 1.0)))
	var t_fight: float = TuneRef.num("wave_time", 25.0)
	return hp * (1.0 + float(snap.get("armor_frac", 0.0))) * (1.0 + float(snap.get("core_regen", 0.0)) * t_fight / hp) * (1.0 + float(snap.get("shield", 0.0)) / hp)


static func power_ratio(snap: Dictionary, wave: int, tier: int) -> float:
	return effective_dps(snap) / maxf(0.0001, required_dps(wave, tier))


static func hp_ratio(snap: Dictionary, wave: int, tier: int) -> float:
	var p: float = damage_pressure(wave, tier, TuneRef.num("pc_leak_frac", 0.25)) * TuneRef.num("wave_time", 25.0)
	return ehp(snap) / maxf(0.0001, p)


## First wave whose power ratio drops below 1.0 (the snapshot held fixed).
static func frontier_wave(snap: Dictionary, tier: int, max_wave: int = 300) -> int:
	for w in range(1, max_wave + 1):
		if power_ratio(snap, w, tier) < 1.0:
			return w
	return max_wave


## Product of the meta layers: {parts, core, shards, insight} multipliers.
static func meta_mult(meta: Dictionary) -> float:
	var m: float = 1.0
	for k in ["parts", "core", "shards", "insight"]:
		m *= maxf(0.0, float(meta.get(k, 1.0)))
	return m


static func band(zone: String) -> Vector2:
	return BANDS.get(zone, Vector2(0.0, INF))


# --------------------------------------------------------------- economy
## Run-cash index e(w, t) = k_c^(w-1) * (1 + 0.5 (t-1)): kill cash, passive
## cash/s and interest caps are authored in wave-1 units and scaled by this.
static func cash_index(wave: int, tier: int) -> float:
	return pow(TuneRef.num("pc_kill_growth", 1.10), float(maxi(1, wave) - 1)) * (1.0 + TuneRef.num("pc_tier_cash", 0.5) * float(maxi(1, tier) - 1))


## Expected kill cash of a whole wave (drone-equivalent spawns, 1 cash each).
static func cash_per_wave(wave: int, tier: int) -> float:
	return spawns_per_wave(wave) * cash_index(wave, tier)


static func coins_per_run(frontier: int, tier: int) -> float:
	return TuneRef.num("pc_coins_c1", 20.0) * pow(TuneRef.num("coin_wave_growth", 1.09), float(maxi(1, frontier))) * (1.0 + 0.6 * float(maxi(1, tier) - 1))


## outpost = {buildings: [{rate (coins/h at L1), lvl, adj (bonus frac), linked}]}.
static func outpost_rate(outpost: Dictionary) -> float:
	var r: float = 0.0
	var cap: float = TuneRef.num("pc_layout_cap", 0.60)
	for b in outpost.get("buildings", []):
		var bd: Dictionary = b
		if not bool(bd.get("linked", true)):
			continue
		var lvl: int = maxi(1, int(bd.get("lvl", 1)))
		r += float(bd.get("rate", 0.0)) * (1.0 + 0.25 * float(lvl - 1)) * (1.0 + minf(cap, float(bd.get("adj", 0.0))))
	return r


static func outpost_ratio(outpost: Dictionary, frontier: int, tier: int, run_minutes: float) -> float:
	var active: float = coins_per_run(frontier, tier) / maxf(0.1, run_minutes) * 60.0
	return outpost_rate(outpost) / maxf(0.0001, active)


## Coins accrued over elapsed_s, capped at storage_h hours of output.
static func outpost_collect(outpost: Dictionary, elapsed_s: float) -> float:
	var rate: float = outpost_rate(outpost)
	var cap_h: float = float(outpost.get("storage_h", TuneRef.num("pc_storage_h", 8.0)))
	return minf(rate * maxf(0.0, elapsed_s) / 3600.0, rate * cap_h)


static func shards_for(lifetime_coins: float) -> int:
	var l0: float = TuneRef.num("pc_reforge_l0", 10000.0)
	return int(floor(TuneRef.num("pc_reforge_k", 1.0) * sqrt(maxf(0.0, lifetime_coins) / l0)))


## tree = {branch: nodes_owned}: Π (1 + 0.05 * nodes).
static func shard_mult(tree: Dictionary) -> float:
	var m: float = 1.0
	for k in tree.keys():
		m *= 1.0 + 0.05 * float(maxi(0, int(tree[k])))
	return m


static func reforge_worth(lifetime_coins: float, cum_shards: int) -> bool:
	return float(shards_for(lifetime_coins)) >= 0.5 * float(cum_shards)


# ----------------------------------------------------------------- parts
## part = {rarity, lvl, stats: {key: signed frac}}. Benefits (positive) scale
## +8% of L1 per level; drawbacks never scale (SYSTEMS §3.1).
## `weights` overrides PART_W per key (PartDB.val_weights() for engine fx keys).
static func part_value(part: Dictionary, weights: Dictionary = {}) -> float:
	var lvl: int = maxi(1, int(part.get("lvl", 1)))
	var v: float = 0.0
	var st: Dictionary = part.get("stats", {})
	for k in st.keys():
		var x: float = float(st[k])
		if x > 0.0:
			x *= 1.0 + 0.08 * float(lvl - 1)
		var wk: float = float(weights.get(String(k), PART_W.get(String(k), 0.5)))
		v += wk * log(maxf(0.01, 1.0 + x))
	return v


static func part_budget(rarity: String, lvl: int) -> float:
	return float(PART_BUDGET.get(rarity, 0.08)) * (1.0 + 0.06 * float(maxi(1, lvl) - 1))


## a weakly dominates b: same slot, >= on every stat, > on at least one.
static func dominates(a: Dictionary, b: Dictionary) -> bool:
	if String(a.get("slot", "")) != String(b.get("slot", "")):
		return false
	var sa: Dictionary = a.get("stats", {})
	var sb: Dictionary = b.get("stats", {})
	var keys: Dictionary = {}
	for k in sa.keys():
		keys[k] = true
	for k in sb.keys():
		keys[k] = true
	var strict: bool = false
	for k in keys.keys():
		var x: float = float(sa.get(k, 0.0))
		var y: float = float(sb.get(k, 0.0))
		if x < y:
			return false
		if x > y:
			strict = true
	return strict


## Normalised spec value (POWER_MODEL §7): eco converts its cash bonus to DPS.
static func spec_score(snap: Dictionary, spec: String, wave: int, tier: int) -> float:
	var v: float = power_ratio(snap, wave, tier)
	if spec == "eco":
		v *= pow(1.0 + float(snap.get("cash_bonus", 0.0)), 0.69)
	return v
