extends RefCounted
## FB2 right-panel intel (view only, owns no rules): ENEMIES (the types in this
## round — alive now or still queued in the wave plan — with threat stars, HP
## and traits; a type seen for the first time this run is tagged NEW) and LOOT
## DROPS (a live, aggregated feed of everything looted from kills: coins from
## horde bodies and bounties, scrap; P5 adds items and caches).

const TowerState := preload("res://TowerState.gd")
const EnemyDB := preload("res://data/EnemyDB.gd")
const EnemyStore := preload("res://EnemyStore.gd")
const Kit := preload("res://ui/Kit.gd")
const LootDB := preload("res://data/LootDB.gd")

## MASS_HORDE §D1 roster names (ids kept so art / Codex carry over).
const NAMES: Dictionary = {
	"drone": "Grunt", "skitter": "Runner", "hauler": "Brute", "ranged": "Spitter", "elite": "Warlord",
	"splitter": "Broodsac", "mite": "Swarmling", "courier": "Courier", "boss": "Behemoth",
	"sapper": "Sapper", "shield": "Shieldbearer",
}
const TRAITS: Dictionary = {
	"drone": "Packs behind the swarm: the wall of bodies", "skitter": "Fast flanker, slips through gaps",
	"hauler": "Heavy: shoves the tide forward, shrugs off knockback",
	"ranged": "Stops at range and spits at the Core", "elite": "Shielded, drops loot", "splitter": "Bursts into 6 swarmlings",
	"mite": "The water: tiny, fast, one hit", "courier": "Runs for the edge, carries Scrap", "boss": "Huge HP, carries a crowd in its wake",
	"sapper": "Ignores walls; detonates on the Core for 6x damage", "shield": "Front shield stops shots; flank it or use AoE / chain",
}
const ORDER: Array = ["boss", "elite", "courier", "hauler", "shield", "sapper", "splitter", "ranged", "drone", "skitter", "mite"]

## Roster / flow caches (the roster scans every body and the queued plan:
## refreshed 4x a second, not every frame, so 10k bodies stay cheap).
static var _ro_cache: Dictionary = {}
static var _ro_t: float = -1.0
static var _ro_s: Object = null
static var _flow: Array = []       # [[t, kills, spawned, leaked], ...] samples, 1 s apart
const FEED_MAX: int = 8


## Fresh per-run state (Main.start_run).
static func reset(m) -> void:
	_ro_cache = {}
	_ro_t = -1.0
	_ro_s = null
	_flow = []
	m.intel_seen = {}
	m.loot_feed = []
	m.loot_coin_seen = 0.0


## Threat stars 1..5: the round's HP scaling (1 star per x3), +1 elite, +2 boss.
static func stars(S, kind: String) -> int:
	var sc: float = maxf(1.0, float(S.scale()) * float(S.hp_mult))
	var st: int = 1 + int(floor(log(sc) / log(3.0)))
	if kind == "elite" or kind == "courier":
		st += 1
	elif kind == "boss":
		st += 2
	return clampi(st, 1, 5)


## {kind: {"n": alive, "q": queued, "hp": max hp}} for this round (cached 0.25 s).
static func roster(S) -> Dictionary:
	var now: float = float(S.time_alive)
	if _ro_s == S and _ro_t >= 0.0 and now - _ro_t < 0.25 and now >= _ro_t:
		return _ro_cache
	_ro_s = S
	_ro_t = now
	_ro_cache = _roster_scan(S)
	return _ro_cache


static func _roster_scan(S) -> Dictionary:
	var out: Dictionary = {}
	# one C# pass over the live bodies ([alive, max hp] per visual kind)
	var ks: PackedStringArray = EnemyStore.VIS_KINDS
	var sm: PackedFloat64Array = S.en.world.call("KindSummary", ks.size())
	for vi in ks.size():
		if sm[vi * 2] <= 0.0:
			continue
		out[ks[vi]] = {"n": int(sm[vi * 2]), "q": 0, "hp": sm[vi * 2 + 1]}
	for pi in range(int(S.plan_idx), S.plan.size()):
		var k2: String = String((S.plan[pi] as Dictionary).get("kind", ""))
		if k2 == "":
			continue
		var r2: Dictionary = out.get(k2, {"n": 0, "q": 0, "hp": 0.0})
		r2["q"] = int(r2["q"]) + 1
		out[k2] = r2
	for k3 in out.keys():
		var r3: Dictionary = out[k3]
		if float(r3["hp"]) <= 0.0:
			if not ["boss", "elite"].has(String(k3)):
				r3["hp"] = float(EnemyDB.mass_def(String(k3))["hp"]) * float(S.mass_hp_scale(String(k3), int(S.wave)))
			else:
				r3["hp"] = float(EnemyDB.get_def(String(k3)).get("hp", 1.0)) * float(S.scale()) * float(S.hp_mult)
	return out


## MASS_HORDE §D6: the four numbers that describe the fight, over the last
## ~3 s of game time: {alive, inflow/s, kills/s, leak/s}.
static func flow(S) -> Dictionary:
	var now: float = float(S.time_alive)
	if _flow.is_empty() or now - float((_flow.back() as Array)[0]) >= 1.0 or now < float((_flow.back() as Array)[0]):
		if not _flow.is_empty() and now < float((_flow.back() as Array)[0]):
			_flow = []
		_flow.append([now, int(S.kills), int(S.mass_spawned), int(S.mass_leaked)])
		while _flow.size() > 4:
			_flow.pop_front()
	var a: Array = _flow.front()
	var dt: float = maxf(0.001, now - float(a[0]))
	if _flow.size() < 2 or dt < 0.5:
		return {"alive": S.en.count(), "in": 0.0, "kills": 0.0, "leak": 0.0}
	return {"alive": S.en.count(), "in": float(int(S.mass_spawned) - int(a[2])) / dt, "kills": float(int(S.kills) - int(a[1])) / dt, "leak": float(int(S.mass_leaked) - int(a[3])) / dt}


## Note first sightings (called every frame from the panel draw).
static func observe(m, ro: Dictionary) -> void:
	for k in ro.keys():
		if not m.intel_seen.has(k):
			m.intel_seen[k] = int(m.S.wave)


static func loot_add(m, key: String, label: String, icon: String, n: float, col: Color) -> void:
	if n <= 0.0:
		return
	var feed: Array = m.loot_feed
	for i in feed.size():
		var f: Dictionary = feed[i]
		if String(f["k"]) == key:
			f["n"] = float(f["n"]) + n
			f["t"] = 1.0
			feed.remove_at(i)
			feed.push_front(f)
			return
	feed.push_front({"k": key, "label": label, "icon": icon, "n": n, "t": 1.0, "c": col})


## Main._handle: one sim event -> feed.
static func on_event(m, ev: Dictionary) -> void:
	match String(ev["t"]):
		"drop":
			match String(ev["kind"]):
				"scrap":
					loot_add(m, "scrap", "Scrap", "cur_scrap", float(ev["n"]), Kit.SCRAP)
				"item":
					loot_add(m, "item", "Items (elites)", "icon_gear", 1.0, Kit.TEXT)
				"cache":
					var cid: String = String(ev.get("cache", "field"))
					loot_add(m, "cache_" + cid, String(LootDB.get_def(cid)["name"]), "chest", 1.0, Kit.rarity_col({"scrap": "common", "field": "uncommon", "elite": "rare", "boss": "epic", "reliquary": "legendary"}.get(cid, "common")))
		"boss_bounty":
			loot_add(m, "bounty", "Boss bounty coins", "cur_coin", float(ev["coins"]), Kit.GOLD)


## Main._process: horde-body coin drops arrive as a running total.
static func poll(m, delta: float) -> void:
	var S = m.S
	var tot: float = float(S.horde_loot_total)
	if tot > float(m.loot_coin_seen):
		loot_add(m, "coins", "Coins (kill drops)", "cur_coin", tot - float(m.loot_coin_seen), Kit.GOLD)
		m.loot_coin_seen = tot
	for f in m.loot_feed:
		(f as Dictionary)["t"] = maxf(0.0, float((f as Dictionary)["t"]) - delta)


static func _star(m, c: Vector2, r: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 10:
		var a: float = -PI * 0.5 + float(i) * PI / 5.0
		pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
	m.draw_colored_polygon(pts, col)


## Draws ENEMIES then LOOT DROPS inside [y0, y1]; returns nothing.
static func draw(m, x: float, w: float, y0: float, y1: float) -> void:
	var S = m.S
	var ro: Dictionary = roster(S)
	observe(m, ro)
	# loot gets just the rows it shows (1..4); enemies take the rest
	var half: float = maxf((y1 - y0) * 0.45, (y1 - y0) - 30.0 - 22.0 * float(clampi(m.loot_feed.size(), 1, 4)))
	var y: float = y0
	Kit.head(m, "ENEMIES  ·  wave %d" % int(S.wave), Vector2(x, y + 16), w)
	m.stat_tips.append([Rect2(x, y, w, 22), "Enemy types in this round (alive now or still to spawn).\nStars = threat (HP scaling this wave; elites +1, bosses +2). NEW = first seen this run."])
	y += 26.0
	# The fight in four numbers: bodies alive, arriving, dying, reaching the Core.
	var fl: Dictionary = flow(S)
	var cols: Array = [["ALIVE", Kit.fmt(float(fl["alive"])), Kit.ENEMY], ["IN/s", Kit.fmt(float(fl["in"])), Kit.TEXT], ["KILLS/s", Kit.fmt(float(fl["kills"])), Kit.GREEN], ["LEAK/s", "%.1f" % float(fl["leak"]), Kit.ENEMY if float(fl["leak"]) > 0.05 else Kit.DIM]]
	var cw: float = w / 4.0
	for ci in 4:
		var c: Array = cols[ci]
		Kit.th(m, String(c[0]), Vector2(x + cw * float(ci), y + 12), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw)
		Kit.th(m, String(c[1]), Vector2(x + cw * float(ci), y + 32), 18, c[2], HORIZONTAL_ALIGNMENT_LEFT, cw)
	m.stat_tips.append([Rect2(x, y, w, 38), "The horde in four numbers (last ~3 s):\nALIVE bodies on the field · IN/s spawning · KILLS/s you deal · LEAK/s reaching the Core (a leaked body pays no cash).\nKeep KILLS/s above IN/s or the tide piles up on the Core."])
	y += 44.0
	var rh: float = 34.0
	var kinds: Array = []
	for k in ORDER:
		if ro.has(k):
			kinds.append(k)
	var room: int = maxi(1, int((y0 + half - y) / rh))
	if kinds.is_empty():
		Kit.t(m, "No enemies on the field", Vector2(x, y + 18), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	for i in mini(kinds.size(), room):
		var k: String = kinds[i]
		var r: Dictionary = ro[k]
		var ry: float = y + float(i) * rh
		if not Kit.icon(m, k, Rect2(x, ry, 26, 26)):
			m.draw_rect(Rect2(x + 5, ry + 5, 16, 16), Kit.ENEMY)
		var nw: bool = int(m.intel_seen.get(k, 0)) == int(S.wave) and int(S.wave) > 1
		Kit.t(m, String(NAMES.get(k, k.capitalize())), Vector2(x + 32, ry + 14), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 110)
		if nw:
			Kit.th(m, "NEW", Vector2(x + 32, ry + 31), 14, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 40)
		var st: int = stars(S, k)
		for j in 5:
			_star(m, Vector2(x + 152 + float(j) * 13.0, ry + 10), 6.0, Kit.GOLD if j < st else Color(1, 1, 1, 0.15))
		Kit.t(m, "HP %s" % Kit.fmt(float(r["hp"])), Vector2(x + 152, ry + 31), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 90)
		Kit.t(m, "%d%s" % [int(r["n"]), (" +%d" % int(r["q"])) if int(r["q"]) > 0 else ""], Vector2(x + w, ry + 18), 15, Kit.ENEMY, HORIZONTAL_ALIGNMENT_RIGHT, 80)
		var d: Dictionary = EnemyDB.mass_def(k)
		m.stat_tips.append([Rect2(x, ry, w, rh), "%s  ·  %d star%s\n%s\nHP %s  ·  speed %d  ·  hits for %s\n%d alive, %d still to spawn" % [String(NAMES.get(k, k)), st, "" if st == 1 else "s", String(TRAITS.get(k, "")), Kit.fmt(float(r["hp"])), int(float(d.get("spd", 0.0))), Kit.fmt(float(d.get("dmg", 0.0)) * float(S.hp_mult)), int(r["n"]), int(r["q"])]])
	if kinds.size() > room:
		Kit.t(m, "+%d more types" % (kinds.size() - room), Vector2(x + w, y0 + 16), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 120)
	# loot
	y = y0 + half + 4.0
	Kit.head(m, "LOOT DROPS  (this run)", Vector2(x, y + 16), w, Kit.GOLD)
	m.stat_tips.append([Rect2(x, y, w, 22), "Everything looted from enemy kills this run, newest first. Banked when the run ends."])
	y += 26.0
	var lh: float = 22.0
	var lroom: int = maxi(1, int((y1 - y) / lh))
	if m.loot_feed.is_empty():
		Kit.t(m, "Kill enemies to collect loot", Vector2(x, y + 16), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	for i in mini(mini(m.loot_feed.size(), lroom), FEED_MAX):
		var f: Dictionary = m.loot_feed[i]
		var ly: float = y + float(i) * lh
		var hl: float = float(f["t"])
		if hl > 0.0:
			m.draw_rect(Rect2(x - 4, ly, w + 8, lh - 2), Color(1, 0.85, 0.3, 0.12 * hl))
		Kit.icon(m, String(f["icon"]), Rect2(x, ly + 1, 18, 18))
		Kit.t(m, String(f["label"]), Vector2(x + 26, ly + 16), 14, f["c"], HORIZONTAL_ALIGNMENT_LEFT, w - 110)
		var n: float = float(f["n"])
		Kit.t(m, ("+%s" % Kit.fmt(n)) if n >= 10.0 or is_equal_approx(n, round(n)) else "+%.1f" % n, Vector2(x + w, ly + 16), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 90)
