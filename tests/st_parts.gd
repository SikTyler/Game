extends RefCounted
## V3 selftest stage: the parts engine (Parts.gd / PartDB). Data validity,
## the starter kit and save hygiene (normalize, V2 gear migration), rolls
## (perk counts and per-perk rarity tiers, pools, bans, pity), chassis
## layouts, upgrade / reroll / lock / merge, Scrap crates (+ Part Contracts),
## the Fabricator shop and the Smelter queue (Outpost buildings), and the
## run hand-off (run_fx, barrel sheets, core_def). `t` is the selftest runner.

const Parts := preload("res://Parts.gd")
const PartDB := preload("res://data/PartDB.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Outpost := preload("res://Outpost.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")

const OT0: int = 1_700_000_000


static func run(t) -> void:
	_data(t)
	_blocks(t)
	_rolls(t)
	_layout(t)
	_ops(t)
	_merge(t)
	_crates(t)
	_fabricator(t)
	_smelter(t)
	_handoff(t)


static func _save(scrap: int = 0, coins: int = 0) -> Dictionary:
	var sv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	sv["scrap"] = scrap
	sv["coins"] = coins
	return sv


static func _rng(sd: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = sd
	return r


static func _lv(sv: Dictionary, id: String, n: int) -> void:
	(sv["research"]["lvls"] as Dictionary)[id] = n


static func _ev(ev: Array, kind: String) -> Array:
	return ev.filter(func(e: Variant) -> bool: return String((e as Dictionary)["t"]) == kind)


## Place + finish an Outpost building at level `lvl`; returns its uid.
static func _build(sv: Dictionary, id: String, x: int, y: int, lvl: int = 1) -> String:
	sv["coins"] = int(sv.get("coins", 0)) + 10_000_000
	sv["outpost"]["relay_lvl"] = 8
	var pe: Array = _ev(Outpost.place(sv, id, x, y, 0, OT0), "op_placed")
	if pe.is_empty():
		return ""
	Outpost.tick(sv, OT0)
	var uid: String = String(pe[0]["uid"])
	sv["outpost"]["buildings"][uid]["lvl"] = lvl
	return uid


# ------------------------------------------------------------------ data

static func _data(t) -> void:
	var bad: Array = []
	var keys: Dictionary = {}
	for b in PartDB.BASES.keys():
		var d: Dictionary = PartDB.BASES[b]
		if not PartDB.SLOTS.has(String(d.get("slot", ""))) or String(d.get("name", "")) == "" or not (d.get("fx", null) is Dictionary) or float(d.get("w", 0.0)) <= 0.0:
			bad.append(String(b))
		if String(d.get("slot", "")) == "barrel" and not FrameDB.DEFS.has(String(d.get("frame", ""))):
			bad.append("frame:" + String(b))
		if String(d.get("slot", "")) == "receiver" and (float(d.get("dmg_k", 0.0)) <= 0.0 or float(d.get("rate_k", 0.0)) <= 0.0):
			bad.append("rcv:" + String(b))
		if String(d.get("slot", "")) == "heart" and (float(d.get("hp_k", 0.0)) <= 0.0 or float(d.get("regen_k", 0.0)) <= 0.0):
			bad.append("hrt:" + String(b))
		for k in (d["fx"] as Dictionary).keys():
			keys[String(k)] = true
	t._check("V3 data: every part base has a slot, name, fx and weight; barrels name a frame; chassis carry their scales", bad.is_empty(), str(bad))
	var ts: String = FileAccess.get_file_as_string("res://TowerState.gd")
	var unused: Array = []
	for k in keys.keys():
		if not ts.contains('pf("%s")' % k) and not ts.contains('pfx.get("%s"' % k):
			unused.append(k)
	t._check("V3 data: every part fx key is read by the run (pfx)", unused.is_empty(), str(unused))
	var per_slot: Array = []
	for sl in PartDB.SLOTS.keys():
		if PartDB.bases_of(String(sl)).size() < 3:
			per_slot.append(sl)
	t._check("V3 data: every slot has at least 3 bases to find (%d bases, %d barrels)" % [PartDB.BASES.size(), PartDB.bases_of("barrel").size()], per_slot.is_empty() and PartDB.bases_of("barrel").size() >= 20, str(per_slot))
	var lay_ok: bool = true
	for r in RarityDB.IDS:
		lay_ok = lay_ok and PartDB.RECEIVER_LAYOUT.has(r) and PartDB.HEART_LAYOUT.has(r) and PartDB.PERK_SLOTS.has(r)
		for sl in (PartDB.RECEIVER_LAYOUT[r] as Dictionary).keys():
			lay_ok = lay_ok and PartDB.side_of(String(sl)) == "weapon"
		for sl in (PartDB.HEART_LAYOUT[r] as Dictionary).keys():
			lay_ok = lay_ok and PartDB.side_of(String(sl)) == "core"
	t._check("V3 data: layouts and perk slots for every rarity, each on its own side", lay_ok)
	var grow: bool = true
	for k in range(1, RarityDB.IDS.size()):
		var a: Dictionary = PartDB.HEART_LAYOUT[RarityDB.IDS[k - 1]]
		var b2: Dictionary = PartDB.HEART_LAYOUT[RarityDB.IDS[k]]
		var a2: Dictionary = PartDB.RECEIVER_LAYOUT[RarityDB.IDS[k - 1]]
		var b3: Dictionary = PartDB.RECEIVER_LAYOUT[RarityDB.IDS[k]]
		for sl in a.keys():
			grow = grow and int(b2.get(sl, 0)) >= int(a[sl])
		for sl in a2.keys():
			grow = grow and int(b3.get(sl, 0)) >= int(a2[sl])
		grow = grow and int(PartDB.PERK_SLOTS[RarityDB.IDS[k]]) >= int(PartDB.PERK_SLOTS[RarityDB.IDS[k - 1]])
	t._check("V3 data: a rarer chassis never closes a slot; perk slots never shrink (1/1/2/2/3/3/4)", grow and PartDB.PERK_SLOTS.values() == [1, 1, 2, 2, 3, 3, 4])
	t._check("V3 data: the Fabricator and the Smelter are Outpost buildings", OutpostDB.IDS.has("fabricator") and OutpostDB.IDS.has("smelter") and OutpostDB.limit("fabricator", 8) == 1)


# ------------------------------------------------------------------ blocks

static func _blocks(t) -> void:
	var sv: Dictionary = BaseMeta.default_save()
	var p: Dictionary = Parts.block(sv)
	var names: Array = []
	for sl in ["receiver", "barrel", "heart"]:
		names.append(String(Parts.equipped(sv, sl)[0]["name"]))
	t._check("V3 start: a fresh save holds a Common Receiver, Autocannon Barrel and Heart, no perks, plain names", Parts.count(sv) == 3 and names == ["Standard Receiver", "Autocannon Barrel", "Standard Heart"] and Parts.run_fx(sv).is_empty() and Parts.equipped(sv, "ammo").is_empty(), str(names))
	var junk: Dictionary = Parts.normalize_block({"items": {"5": {"base": "brl_minigun", "rar": "nope", "lvl": 99, "perks": [{"id": "w_dmg", "t": 9, "q": 3}, {"id": "w_dmg"}, {"id": "m_hp"}, {"id": "zzz"}]}, "x": {"base": "brl_minigun"}, "6": {"base": "bogus"}, "7": 3},
		"equipped": {"barrel": [5, 5, 99], "receiver": [5], "heart": "x"}, "pity": {"e": -4, "l": 9999}, "smelt": [{"name": 3, "scrap": -1, "done": 5}, 7], "next": 2})
	var it5: Dictionary = Parts.get_item(junk, 5)
	t._check("V3 normalize: invalid parts are dropped; rarity / level / perk tier and quality clamp; off-side and duplicate perks go", (junk["items"] as Dictionary).size() == 3 and String(it5["rar"]) == "common" and int(it5["lvl"]) == 10 and (it5["perks"] as Array).size() == 1 and int(it5["perks"][0]["t"]) == 7 and float(it5["perks"][0]["q"]) == 1.0)
	t._check("V3 normalize: equipped uids are re-checked (a barrel can't be a Receiver); a missing chassis gets a starter; next > every uid", (junk["equipped"]["barrel"] as Array) == [5] and (junk["equipped"]["receiver"] as Array).size() == 1 and int(junk["equipped"]["receiver"][0]) != 5 and (junk["equipped"]["heart"] as Array).size() == 1 and int(junk["next"]) > 5 and int(junk["pity"]["e"]) == 0 and int(junk["pity"]["l"]) == int(RarityDB.PITY["l"]["hard"]) and (junk["smelt"] as Array).size() == 1)
	t._check("V3 normalize: garbage becomes the starter kit", (Parts.normalize_block("x")["items"] as Dictionary).size() == 3 and (Parts.normalize_block(null)["items"] as Dictionary).size() == 3)
	# V2 gear block -> Scrap refund + starter kit (once)
	var v2: Dictionary = {"version": BaseMeta.VERSION, "scrap": 10, "gear": {"items": {"1": {"rar": "epic", "lvl": 3}, "2": {"rar": "common", "lvl": 1}, "3": "junk"}}}
	var m: Dictionary = BaseMeta.normalize(v2)
	var refund: int = int(round(float(RarityDB.get_def("epic")["salvage"]) * 1.2)) + int(RarityDB.get_def("common")["salvage"])
	t._check("V3 migration: a V2 gear block is refunded as Scrap (salvage value of every item), then a fresh kit", not m.has("gear") and int(m["scrap"]) == 10 + refund and int(m["parts_refund"]) == refund and Parts.count(m) == 3, "%d %d" % [int(m["scrap"]), refund])
	var again: Dictionary = BaseMeta.normalize(m)
	t._check("V3 migration: ... only once (re-normalizing keeps the parts, no second refund)", int(again["scrap"]) == int(m["scrap"]) and Parts.count(again) == 3)
	var rt: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(m)))
	t._check("V3 save: the parts block survives a JSON round trip", JSON.stringify(rt["parts"]["items"]) == JSON.stringify(m["parts"]["items"]) and JSON.stringify(rt["parts"]["equipped"]) == JSON.stringify(m["parts"]["equipped"]))


# ------------------------------------------------------------------ rolls

static func _rolls(t) -> void:
	var a: Dictionary = Parts.roll(_rng(9), "drop", {"luck": 2.0}, {"e": 0, "l": 0, "m": 0})
	var b: Dictionary = Parts.roll(_rng(9), "drop", {"luck": 2.0}, {"e": 0, "l": 0, "m": 0})
	t._check("V3 roll: the same seed rolls the same part", JSON.stringify(a) == JSON.stringify(b))
	var bad: Array = []
	var side_bad: Array = []
	var tiers: Dictionary = {}
	var r := _rng(4)
	var pity: Dictionary = {"e": 0, "l": 0, "m": 0}
	var slots_seen: Dictionary = {}
	for k in 3000:
		var it: Dictionary = Parts.roll(r, "drop", {}, pity)
		slots_seen[String(it["slot"])] = true
		if (it["perks"] as Array).size() != int(PartDB.PERK_SLOTS[String(it["rar"])]):
			bad.append("%s %d" % [it["rar"], (it["perks"] as Array).size()])
		var side: String = PartDB.side_of(String(it["slot"]))
		var ids: Dictionary = {}
		for pk in it["perks"]:
			var id: String = String((pk as Dictionary)["id"])
			if not Parts.perk_pool(side, String(PartDB.get_def(String(it["base"])).get("frame", ""))).has(id) or ids.has(id) or id == "w_multishot":
				side_bad.append("%s:%s" % [side, id])
			ids[id] = true
			var dt: int = int((pk as Dictionary)["t"]) - 1 - RarityDB.rank(String(it["rar"]))
			if String(it["rar"]) == "common":
				tiers[int((pk as Dictionary)["t"])] = int(tiers.get(int((pk as Dictionary)["t"]), 0)) + 1
			if dt > 2 or (dt < -1 and RarityDB.rank(String(it["rar"])) > 0):
				bad.append("tier %s T%d" % [it["rar"], int((pk as Dictionary)["t"])])
	t._check("V3 roll: perk slots by rarity (1/1/2/2/3/3/4); every slot drops", bad.is_empty() and slots_seen.size() == PartDB.SLOTS.size(), str(bad.slice(0, 5)))
	t._check("V3 roll: weapon parts roll attack perks, core parts defense / eco perks; no duplicates; never Twin Feed", side_bad.is_empty(), str(side_bad.slice(0, 5)))
	var tot: int = 0
	for v in tiers.values():
		tot += int(v)
	var t1: float = float(tiers.get(1, 0)) / float(maxi(1, tot))
	var t3: float = float(tiers.get(3, 0)) / float(maxi(1, tot))
	t._check("V3 perk tiers: each perk rolls its own rarity tier around the part's (Common part: ~75% T1, ~20% T2, ~5% T3, never T4+)", t1 > 0.68 and t1 < 0.82 and t3 > 0.02 and t3 < 0.09 and not tiers.has(4), str(tiers))
	var ex: Dictionary = Parts.roll(_rng(2), "drop", {"rarity": "exotic", "slot": "barrel"}, {})
	var ex_ok: bool = (ex["perks"] as Array).size() == 4
	for pk in ex["perks"]:
		ex_ok = ex_ok and int((pk as Dictionary)["t"]) >= 6
	t._check("V3 perk tiers: an Exotic part's perks are T6-T7", ex_ok, str(ex["perks"]))
	var hi: Array = [0, 0]
	for li in 2:
		var rr := _rng(55)
		for k in 4000:
			var it2: Dictionary = Parts.roll(rr, "drop", {"slot": "ammo", "rarity": "rare", "luck": 10.0 * li}, {})
			for pk in it2["perks"]:
				hi[li] = int(hi[li]) + (1 if int((pk as Dictionary)["t"]) > 3 else 0)
	t._check("V3 perk tiers: luck nudges perk tiers up", int(hi[1]) > int(hi[0]), str(hi))
	# disclosed odds and pity
	var od: Dictionary = Parts.odds_now("drop", 0.0, {"e": 0, "l": 0, "m": 0})
	var sum: float = 0.0
	for v in od.values():
		sum += float(v)
	t._check("V3 odds: drop odds sum to 100%", absf(sum - 100.0) < 0.001)
	var pp: Dictionary = {"e": int(RarityDB.PITY["e"]["hard"]) - 1, "l": 0, "m": 0}
	var pr: String = Parts.roll_rarity(_rng(1), "drop", 0.0, pp)
	t._check("V3 pity: the roll at the Epic hard pity is Epic+ and resets the counter", RarityDB.at_least(pr, "epic") and int(pp["e"]) == 0)
	# bans
	var sv: Dictionary = _save()
	t._check("V3 bans: banning needs Blacklist research", not Parts.why_ban(sv, "weapon", "w_dmg", true).is_empty() and Parts.ban(sv, "weapon", "w_dmg", true).is_empty())
	_lv(sv, "blacklist", 1)
	Parts.ban(sv, "weapon", "w_dmg", true)
	var hit: int = 0
	var rb := _rng(8)
	for k in 1500:
		var it3: Dictionary = Parts.roll(rb, "drop", {"side": "weapon"}, {}, Parts.block(sv)["bans"])
		for pk in it3["perks"]:
			hit += 1 if String((pk as Dictionary)["id"]) == "w_dmg" else 0
	t._check("V3 bans: a banned perk never rolls on that side; 1 ban slot at Blacklist 1", hit == 0 and not Parts.why_ban(sv, "weapon", "w_rate", true).is_empty() and Parts.why_ban(sv, "core", "m_hp", true).is_empty())


# ------------------------------------------------------------------ layout

static func _layout(t) -> void:
	var sv: Dictionary = _save()
	var sc: int = Parts.add_item(sv, Parts.make("scp_long"))
	t._check("V3 layout: a Common Receiver has no Scope slot (install refused with the reason)", Parts.why_equip(sv, sc).contains("rarer Receiver") and Parts.equip(sv, sc).is_empty())
	var rc: int = Parts.add_item(sv, Parts.make("rcv_standard", "epic"))
	var ev: Array = Parts.equip(sv, rc)
	t._check("V3 layout: an Epic Receiver swaps in and opens Scope / Power / Muzzle / Magazine", ev.size() == 1 and int(ev[0]["old"]) > 0 and Parts.layout(sv, "weapon").has("mag") and Parts.equip(sv, sc).size() == 1 and Parts.equipped(sv, "scope").size() == 1)
	var old: int = int(ev[0]["old"])
	Parts.equip(sv, old)
	t._check("V3 layout: swapping back to a Common Receiver unequips what no longer fits (the part stays in the inventory)", Parts.equipped(sv, "scope").is_empty() and Parts.has_item(Parts.block(sv), sc) and not Parts.is_equipped(sv, sc))
	t._check("V3 layout: the last barrel and a chassis can't be removed", Parts.unequip(sv, "barrel", 0).is_empty() and Parts.unequip(sv, "receiver", 0).is_empty())
	var lg: Dictionary = _save()
	Parts.equip(lg, Parts.add_item(lg, Parts.make("rcv_standard", "legendary")))
	var b2: int = Parts.add_item(lg, Parts.make("brl_minigun"))
	Parts.equip(lg, b2)
	var b3: int = Parts.add_item(lg, Parts.make("brl_sniper"))
	Parts.equip(lg, b3)
	t._check("V3 layout: a Legendary Receiver holds 2 barrels (a 3rd replaces barrel 0)", Parts.equipped(lg, "barrel").size() == 2 and Parts.is_equipped(lg, b2) and Parts.is_equipped(lg, b3))
	var hu: int = Parts.add_item(lg, Parts.make("hrt_standard", "legendary"))
	Parts.equip(lg, hu)
	Parts.equip(lg, Parts.add_item(lg, Parts.make("plt_basic")))
	Parts.equip(lg, Parts.add_item(lg, Parts.make("plt_spiked")))
	t._check("V3 layout: a Legendary Heart holds 2 Platings and a Shield Emitter", Parts.equipped(lg, "plating").size() == 2 and int(Parts.layout(lg, "core").get("emitter", 0)) == 1)


# ------------------------------------------------------------------ upgrade / reroll / lock

static func _ops(t) -> void:
	var sv: Dictionary = _save(100000, 10_000_000)
	var u: int = Parts.add_item(sv, Parts.make("amm_toxic", "rare", 1, [{"id": "w_dmg", "t": 3, "q": 0.5, "lock": false}, {"id": "w_rate", "t": 3, "q": 0.5, "lock": false}]))
	var it: Dictionary = Parts.item(sv, u)
	t._check("V3 upgrade: 60 x RM x 1.17^(L-1) coins (Rare L1 = 150)", Parts.upgrade_cost(it) == 150)
	var c0: int = int(sv["coins"])
	var ev: Array = []
	for k in 4:
		ev.append_array(Parts.upgrade(sv, u))
	var tsum: int = int(it["perks"][0]["t"]) + int(it["perks"][1]["t"])
	t._check("V3 upgrade: every 5th level is a masterwork (+1 or +2 perk tier, +6% power)", int(it["lvl"]) == 5 and int(it["mw"]) == 1 and tsum >= 7 and bool(ev.back().has("mw")) and int(sv["coins"]) < c0)
	it["lvl"] = Parts.max_lvl_of("rare")
	t._check("V3 upgrade: max level is refused (merge raises the cap)", Parts.why_upgrade(sv, u).begins_with("Max level") and Parts.upgrade(sv, u).is_empty())
	it["lvl"] = 5
	t._check("V3 reroll: 10 x RM x 1.25^rerolls x 4^locks Scrap (Rare: 25)", Parts.reroll_cost(it) == 25)
	var rr: Array = Parts.reroll(sv, u, 0)
	var cands: Array = rr[0]["cands"] if not rr.is_empty() else []
	t._check("V3 reroll: 2 candidates (id and tier re-roll); a second reroll waits for the choice", cands.size() == 2 and not Parts.why_reroll(sv, u, 1).is_empty() and String(cands[0]["id"]) != "w_rate")
	Parts.reroll_choose(sv, 1)
	t._check("V3 reroll: choosing takes the candidate into that perk slot", JSON.stringify(it["perks"][0]) == JSON.stringify(cands[1]) and int(it["rr"]) == 1)
	Parts.reroll(sv, u, 0)
	var keep: Dictionary = (it["perks"][0] as Dictionary).duplicate()
	Parts.reroll_choose(sv, -1)
	t._check("V3 reroll: or keep the current perk; the price climbs (x1.25 per reroll)", JSON.stringify(it["perks"][0]) == JSON.stringify(keep) and Parts.reroll_cost(it) == int(round(25.0 * pow(1.25, 2.0))))
	t._check("V3 lock: 1 lock slot without research; a locked perk doesn't reroll; locks x4 the reroll", Parts.lock(sv, u, 0, true).size() == 1 and not Parts.why_lock(sv, u, 1, true).is_empty() and Parts.why_reroll(sv, u, 0).contains("Locked") and Parts.reroll_cost(it) == int(round(25.0 * pow(1.25, 2.0) * 4.0)))
	_lv(sv, "stabilizer", 1)
	t._check("V3 lock: Stabilizer 1 = 2 lock slots", Parts.lock(sv, u, 1, true).size() == 1 and Parts.locks_on(it) == 2)
	var fv: Array = Parts.set_fav(sv, u, true)
	t._check("V3 favourite / rename: names are sanitized and capped", fv.size() == 1 and Parts.rename(sv, u, "  Ma\nko  ").size() == 1 and String(it["name"]) == "Mako" and Parts.rename(sv, u, "   ").is_empty())
	var nw: int = Parts.add_item(sv, Parts.roll(_rng(3), "drop", {"side": "core"}, {}))
	var n0: int = Parts.new_count(sv, "core")
	Parts.mark_seen(sv, nw)
	t._check("V3 NEW badges: new parts count per side until seen", n0 >= 1 and Parts.new_count(sv, "core") == n0 - 1)


# ------------------------------------------------------------------ merge

static func _merge(t) -> void:
	var sv: Dictionary = _save()
	var a: int = Parts.add_item(sv, Parts.make("plt_basic", "rare", 8, [{"id": "m_hp", "t": 3, "q": 0.5, "lock": false}]))
	var b: int = Parts.add_item(sv, Parts.make("plt_spiked", "rare", 2))
	var c: int = Parts.add_item(sv, Parts.make("plt_reactive", "rare", 4))
	var x: int = Parts.add_item(sv, Parts.make("gen_basic", "rare"))
	var y: int = Parts.add_item(sv, Parts.make("plt_basic", "epic"))
	t._check("V3 merge: 3 of one part type and rarity only; the base is one of them", Parts.why_merge(sv, [a, b, x], a) == "Same part type only" and Parts.why_merge(sv, [a, b, y], a) == "Same rarity only" and Parts.why_merge(sv, [a, b], a) != "" and Parts.why_merge(sv, [a, b, c], x) != "")
	var ev: Array = Parts.merge(sv, [a, b, c], a)
	var it: Dictionary = Parts.item(sv, a)
	t._check("V3 merge: Rare -> Epic on the base (its look and perks kept; new perk slots roll; level = half the best)", ev.size() == 1 and String(it["rar"]) == "epic" and (it["perks"] as Array).size() == 2 and String(it["perks"][0]["id"]) == "m_hp" and int(it["lvl"]) == 4 and not Parts.has_item(Parts.block(sv), b) and not Parts.has_item(Parts.block(sv), c) and String(it["base"]) == "plt_basic")
	var l3: Array = []
	for k in 3:
		l3.append(Parts.add_item(sv, Parts.make("plt_basic", "legendary")))
	t._check("V3 merge: Legendary -> Mythic needs Mythic Fusion research", Parts.why_merge(sv, l3, int(l3[0])).contains("Mythic Fusion"))
	var m3: Array = []
	for k in 3:
		m3.append(Parts.add_item(sv, Parts.make("plt_basic", "mythic")))
	t._check("V3 merge: Exotics only drop", Parts.why_merge(sv, m3, int(m3[0])) == "Exotics only drop")


# ------------------------------------------------------------------ crates

static func _crates(t) -> void:
	var sv: Dictionary = _save(119)
	t._check("V3 crates: a Standard Crate is 120 Scrap", Parts.why_crate(sv, "standard") == "Need 120 Scrap" and Parts.open_crate(sv, "standard").is_empty())
	sv["scrap"] = 120 + 600 + 2500
	var ev1: Array = Parts.open_crate(sv, "standard")
	var ev2: Array = Parts.open_crate(sv, "advanced")
	var ev3: Array = Parts.open_crate(sv, "elite")
	t._check("V3 crates: Standard 1 part / Advanced 3 / Elite 5, paid in Scrap", (ev1[0]["uids"] as Array).size() == 1 and (ev2[0]["uids"] as Array).size() == 3 and (ev3[0]["uids"] as Array).size() == 5 and int(sv["scrap"]) == 0 and Parts.count(sv) == 3 + 9)
	var fl_ok: bool = true
	var tsv: Dictionary = _save(1_000_000)
	for k in 60:
		var e: Array = Parts.open_crate(tsv, "advanced")
		fl_ok = fl_ok and RarityDB.at_least(String(Parts.item(tsv, int(e[0]["uids"][0]))["rar"]), "uncommon")
		var e2: Array = Parts.open_crate(tsv, "elite")
		fl_ok = fl_ok and RarityDB.at_least(String(Parts.item(tsv, int(e2[0]["uids"][0]))["rar"]), "rare")
		for u in Parts.uids(tsv):
			if not Parts.is_equipped(tsv, int(u)):
				Parts.salvage(tsv, int(u))
	t._check("V3 crates: Advanced guarantees an Uncommon+, Elite a Rare+", fl_ok)
	var cs: Dictionary = _save(10_000)
	t._check("V3 Part Contracts: picking the part type needs the research", Parts.why_crate(cs, "advanced", "barrel").contains("Part Contracts"))
	_lv(cs, "brand_contracts", 1)
	var ce: Array = Parts.open_crate(cs, "advanced", "barrel")
	var all_b: bool = not ce.is_empty()
	for u in (ce[0]["uids"] if not ce.is_empty() else []):
		all_b = all_b and String(Parts.item(cs, int(u))["slot"]) == "barrel"
	t._check("V3 Part Contracts: a targeted crate is all that part type at x1.5 price", all_b and int(cs["scrap"]) == 10_000 - 900)
	var full: Dictionary = _save(1_000_000)
	while Parts.count(full) < Parts.INV_CAP - 2:
		Parts.add_item(full, Parts.make("mag_drum"))
	t._check("V3 crates: refused when the parts wouldn't fit", Parts.why_crate(full, "advanced").begins_with("Inventory full"))


# ------------------------------------------------------------------ Fabricator

static func _fabricator(t) -> void:
	var sv: Dictionary = _save(1_000_000)
	t._check("V3 Fabricator: no building, no shop", Parts.fab_level(sv) == 0 and Parts.fab_offers(sv, OT0).is_empty())
	var fu: String = _build(sv, "fabricator", 7, 8)
	var of: Array = Parts.fab_offers(sv, OT0)
	t._check("V3 Fabricator: Lv1 stocks 3 parts for 8 h", fu != "" and of.size() == 3 and is_equal_approx(Parts.fab_period_h(sv), 8.0) and Parts.fab_next_refresh(sv) == OT0 + 8 * 3600)
	var first: String = JSON.stringify(of)
	t._check("V3 Fabricator: the stock holds until the refresh, then rotates", JSON.stringify(Parts.fab_offers(sv, OT0 + 7 * 3600)) == first and JSON.stringify(Parts.fab_offers(sv, OT0 + 8 * 3600)) != first)
	var of2: Array = Parts.fab_offers(sv, OT0 + 8 * 3600)
	var price: int = Parts.fab_price(sv, of2[0])
	var s0: int = int(sv["scrap"])
	var n0: int = Parts.count(sv)
	var bev: Array = Parts.fab_buy(sv, 0, OT0 + 8 * 3600)
	t._check("V3 Fabricator: buying pays the Scrap price (Common 150 .. Exotic 80000) and adds the part, NEW", bev.size() == 1 and int(sv["scrap"]) == s0 - price and Parts.count(sv) == n0 + 1 and bool(Parts.item(sv, int(bev[0]["uid"]))["new"]) and price == int(Parts.FAB_PRICE[String(of2[0]["rar"])]))
	t._check("V3 Fabricator: a sold offer is gone until the refresh", Parts.why_fab_buy(sv, 0, OT0 + 8 * 3600).begins_with("Sold") and Parts.fab_buy(sv, 0, OT0 + 8 * 3600).is_empty())
	var s1: int = int(sv["scrap"])
	var rr: Array = Parts.fab_reroll(sv, OT0 + 9 * 3600)
	t._check("V3 Fabricator: a manual refresh costs 200 Scrap and restocks", rr.size() == 1 and int(sv["scrap"]) == s1 - Parts.FAB_REROLL and not bool((Parts.fab_offers(sv, OT0 + 9 * 3600)[0] as Dictionary).get("sold", false)))
	sv["outpost"]["buildings"][fu]["lvl"] = 5
	var l5: Array = Parts.fab_offers(sv, OT0 + 30 * 3600)
	t._check("V3 Fabricator: Lv5 = 5 offers, a 5.6 h refresh, -16% prices", l5.size() == 5 and is_equal_approx(Parts.fab_period_h(sv), 5.6) and Parts.fab_price(sv, {"rar": "rare"}) == int(round(1100.0 * 0.84)))
	sv["outpost"]["buildings"][fu]["lvl"] = 10
	t._check("V3 Fabricator: Lv10 caps at 6 offers, a 2.6 h refresh", Parts.fab_slots(sv) == 6 and is_equal_approx(Parts.fab_period_h(sv), 2.6))
	var lo: Array = [0, 0]
	for li in 2:
		var fs: Dictionary = _save(0)
		var u2: String = _build(fs, "fabricator", 7, 8, 1 if li == 0 else 10)
		for k in 150:
			for o in Parts.fab_offers(fs, OT0 + k * 30 * 3600):
				lo[li] = int(lo[li]) + (1 if RarityDB.at_least(String((o as Dictionary)["rar"]), "rare") else 0)
		lo[li] = float(lo[li]) / float(Parts.fab_slots(fs))
		t._check("V3 Fabricator: built (%d)" % li, u2 != "")
	t._check("V3 Fabricator: higher levels stock rarer parts (Rare+ per offer)", float(lo[1]) > float(lo[0]) * 1.1, str(lo))


# ------------------------------------------------------------------ Smelter

static func _smelter(t) -> void:
	var sv: Dictionary = _save()
	var a: int = Parts.add_item(sv, Parts.make("mag_drum", "rare", 3))
	t._check("V3 Smelter: no building, no smelting", Parts.why_smelt(sv, a, OT0).begins_with("Build a Smelter") and Parts.smelt(sv, a, OT0).is_empty())
	var su: String = _build(sv, "smelter", 7, 8)
	var b: int = Parts.add_item(sv, Parts.make("mag_drum", "common"))
	var c: int = Parts.add_item(sv, Parts.make("mag_drum", "common"))
	var y: int = Parts.smelt_yield(sv, Parts.item(sv, a))
	var ev: Array = Parts.smelt(sv, a, OT0)
	Parts.smelt(sv, b, OT0)
	t._check("V3 Smelter: Lv1 melts 2 parts at once, 20 min each; the part is consumed now", su != "" and ev.size() == 1 and int(ev[0]["done"]) == OT0 + 1200 and not Parts.has_item(Parts.block(sv), a) and Parts.smelt_busy(sv, OT0) == 2 and Parts.why_smelt(sv, c, OT0).begins_with("Smelter full"))
	t._check("V3 Smelter: yield = the part's salvage value (Rare L3 = 25 x 1.2)", y == int(round(25.0 * 1.2)))
	var s0: int = int(sv["scrap"])
	t._check("V3 Smelter: nothing to claim while melting", Parts.smelt_claim(sv, OT0 + 1199).is_empty() and int(sv["scrap"]) == s0)
	t._check("V3 Smelter: a finished melt frees its furnace before it is claimed", Parts.why_smelt(sv, c, OT0 + 1200) == "")
	var cl: Array = Parts.smelt_claim(sv, OT0 + 1200)
	t._check("V3 Smelter: claiming pays every finished melt", cl.size() == 1 and int(cl[0]["scrap"]) == y + Parts.smelt_yield(sv, Parts.make("mag_drum", "common")) and int(sv["scrap"]) == s0 + int(cl[0]["scrap"]) and (Parts.block(sv)["smelt"] as Array).is_empty())
	Parts.set_fav(sv, c, true)
	t._check("V3 Smelter: favourites and installed parts are refused", Parts.why_smelt(sv, c, OT0).begins_with("Unfavourite") and Parts.why_smelt(sv, int(Parts.block(sv)["equipped"]["barrel"][0]), OT0).begins_with("Unequip"))
	sv["outpost"]["buildings"][su]["lvl"] = 3
	t._check("V3 Smelter: Lv3 = 3 furnaces, x0.94^2 time, +12% yield", Parts.smelt_slots(sv) == 3 and Parts.smelt_secs(sv) == int(1200.0 * 0.94 * 0.94) and Parts.smelt_yield(sv, Parts.make("mag_drum", "rare", 3)) == int(round(30.0 * 1.12)))


# ------------------------------------------------------------------ run hand-off

static func _handoff(t) -> void:
	var it: Dictionary = Parts.make("plt_ablative", "epic", 10)
	var fx: Dictionary = Parts.base_fx(it)
	var pw: float = Parts.power(it)
	t._check("V3 fx: part power = rarity base x (1 + 5%/level) x 1.06^masterworks", is_equal_approx(pw, 1.48 * 1.45 * pow(1.06, 2.0)))
	t._check("V3 fx: positive fx scale with power; trade-offs (negatives) don't", is_equal_approx(float(fx["core_hp"]), 0.18 * pw) and is_equal_approx(float(fx["regen"]), -0.10))
	var cnt: Dictionary = Parts.base_fx(Parts.make("amm_ap", "epic", 20))
	t._check("V3 fx: count keys stay whole (+1 per 2 masterworks)", is_equal_approx(float(cnt["pierce"]), 1.0 + 2.0))
	var pk: Dictionary = Parts.part_fx(Parts.make("amm_standard", "common", 1, [{"id": "w_dmg", "t": 4, "q": 0.5, "lock": false}]))
	t._check("V3 fx: a part's fx = its own + its perks", is_equal_approx(float(pk["core_dmg"]), 0.10 + AffixDB.value("w_dmg", 4, 0.5)))
	var sv: Dictionary = _save()
	var inv: int = Parts.add_item(sv, Parts.make("amm_standard"))
	t._check("V3 run_fx: parts in the inventory do nothing until installed", Parts.run_fx(sv).is_empty())
	Parts.equip(sv, inv)
	t._check("V3 run_fx: ... and count once installed", is_equal_approx(float(Parts.run_fx(sv).get("core_dmg", 0.0)), 0.10))
	var dps: Array = []
	for b in PartDB.bases_of("barrel"):
		var bs: Dictionary = Parts.barrel_sheet(Parts.make(String(b)), Parts.starter("rcv_standard"))
		if float(bs["dmg"]) <= 0.0 or float(bs["rate"]) <= 0.0 or float(bs["range"]) <= 0.0:
			dps.append(String(b))
	t._check("V3 barrels: every barrel sheet has damage, rate and range", dps.is_empty(), str(dps))
	var nd: Array = []
	for b in PartDB.bases_of("barrel"):
		var s2: Dictionary = _save()
		Parts.equip(s2, Parts.add_item(s2, Parts.make(String(b))), 0)
		if Parts.est_dps(s2) <= 0.0:
			nd.append(String(b))
	t._check("V3 barrels: every barrel has a DPS readout", nd.is_empty(), str(nd))
	var cd: Dictionary = Parts.core_def(BaseMeta.default_save())
	t._check("V3 core_def: the starter kit is exactly the CoreDB sheet + the Autocannon frame", is_equal_approx(float(cd["hp"]), float(CoreDB.get_def()["hp"])) and is_equal_approx(float(cd["dmg"]), float(FrameDB.get_def("autocannon")["dmg"])) and (cd["barrels"] as Array).size() == 1)
