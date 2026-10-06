extends RefCounted
## P4a selftest stage: the gear engine's pure rules (GearGen + Gear + the
## save block). Roll determinism, disclosed odds and visible pity, perk rules,
## tier caps, every op's cost literal and refusal, masterworks, merges, the
## run hand-off and save normalisation. `t` is the selftest runner.

const GearGen := preload("res://GearGen.gd")
const Gear := preload("res://Gear.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const BrandDB := preload("res://data/BrandDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const ModuleDB := preload("res://data/ModuleDB.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Cores := preload("res://Cores.gd")

## fx keys TowerState does not read yet (P4a listed 14; P4b wired them all).
const PENDING_FX: Array = []


static func run(t) -> void:
	_data(t)
	_rolls(t)
	_odds(t)
	_pity(t)
	_perks(t)
	_costs(t)
	_upgrade(t)
	_reroll_lock(t)
	_merge(t)
	_imprint_salvage(t)
	_forge(t)
	_equip(t)
	_hand_off(t)
	_save(t)


static func _rng(sd: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = sd
	return r


## A save with coins / scrap and a forced item set.
static func _save_with(items: Array, coins: int = 10_000_000, scrap: int = 1_000_000) -> Dictionary:
	var s: Dictionary = BaseMeta.default_save()
	s["coins"] = coins
	s["scrap"] = scrap
	for it in items:
		Gear.add_item(s, it)
	return s


static func _mk(kind: String, base: String, rar: String, sd: int = 1, ilvl: int = 10) -> Dictionary:
	return GearGen.roll(_rng(sd), "drop", {"kind": kind, "base": base, "rarity": rar, "ilvl": ilvl}, {})


static func _last(s: Dictionary) -> int:
	return int(Gear.block(s)["next"]) - 1


# ------------------------------------------------------------------ data

static func _data(t) -> void:
	var bad: Array = []
	for id in FrameDB.IDS:
		var d: Dictionary = FrameDB.DEFS[id]
		for k in ["name", "attack", "dmg", "rate", "range", "p", "desc", "look", "affinity"]:
			if not d.has(k):
				bad.append("%s.%s" % [id, k])
		for a in d.get("affinity", []):
			if not AffixDB.pool("weapon", String(id)).has(a):
				bad.append("%s affinity %s" % [id, a])
	t._check("P4 data: 10 frames, each with a sheet, look and rollable affinities", FrameDB.IDS.size() == 10 and bad.is_empty(), str(bad))
	var mb: Array = []
	for id in ModuleDB.IDS:
		var d: Dictionary = ModuleDB.DEFS[id]
		if not (d.has("name") and d.has("fx") and d.has("desc") and d.has("look")) or (d["fx"] as Dictionary).is_empty():
			mb.append(id)
	t._check("P4 data: 23 modules, each with fx and a description", ModuleDB.IDS.size() == 23 and mb.is_empty() and ModuleDB.DEFS.size() == 23, str(mb))
	var ab: Array = []
	for id in AffixDB.DEFS.keys():
		var d: Dictionary = AffixDB.DEFS[id]
		if not ["weapon", "module", "any"].has(String(d["kind"])) or not ["pct", "flat", "int"].has(String(d["fmt"])) or float(d["w"]) <= 0.0 or String(d["text"]).find("%s") < 0:
			ab.append(id)
	t._check("P4 data: every perk has a kind, format, weight and value slot in its text", ab.is_empty() and AffixDB.DEFS.size() >= 40, str(ab))
	t._check("P4 data: perk values scale with tier (T1 < T5 < T7) and quality", AffixDB.value("w_dmg", 1, 0.5) < AffixDB.value("w_dmg", 5, 0.5) and AffixDB.value("w_dmg", 5, 0.5) < AffixDB.value("w_dmg", 7, 0.5) and AffixDB.value("w_dmg", 3, 0.0) < AffixDB.value("w_dmg", 3, 1.0))
	t._check("P4 data: count perks stay whole, >= 1 and capped", AffixDB.value("w_multishot", 1, 0.0) == 1.0 and AffixDB.value("w_multishot", 7, 1.0) == 3.0 and AffixDB.value("w_pierce", 7, 1.0) == 6.0)
	t._check("P4 data: perk text shows the value (\"+6.0% weapon damage\")", AffixDB.text("w_dmg", 1, 0.5) == "+6.0% weapon damage", AffixDB.text("w_dmg", 1, 0.5))
	t._check("P4 data: item tier = 1 + ilvl/25, Forge-capped at T5, T7 max", AffixDB.tier_for(1) == 1 and AffixDB.tier_for(49) == 2 and AffixDB.tier_for(200) == 7 and AffixDB.tier_for(200, AffixDB.FORGE_TIER_CAP) == 5)
	var pb: Array = []
	for b in BrandDB.IDS:
		var d: Dictionary = BrandDB.DEFS[b]
		if (d["palette"] as Array).size() != 3 or (d["syl"] as Array).is_empty() or (d["quirk"] as Dictionary).is_empty():
			pb.append(b)
	t._check("P4 data: 6 brands with a quirk, 3-colour palette and name syllables", BrandDB.IDS.size() == 6 and pb.is_empty(), str(pb))
	t._check("P4 data: frame-only perks roll only on their frame", AffixDB.pool("weapon", "lance").has("w_ramp") and not AffixDB.pool("weapon", "autocannon").has("w_ramp") and not AffixDB.pool("module", "").has("w_ramp"))
	t._check("P4 data: 'any' perks roll on weapons and modules; kinds don't cross", AffixDB.pool("weapon", "rail").has("a_dmg") and AffixDB.pool("module", "").has("a_dmg") and not AffixDB.pool("weapon", "rail").has("m_hp") and not AffixDB.pool("module", "").has("w_dmg"))


# ------------------------------------------------------------------ rolls

static func _rolls(t) -> void:
	var a: Dictionary = GearGen.roll(_rng(777), "drop", {"ilvl": 40}, {"e": 3, "l": 5, "m": 9})
	var b: Dictionary = GearGen.roll(_rng(777), "drop", {"ilvl": 40}, {"e": 3, "l": 5, "m": 9})
	t._check("P4 roll: the same seed and pity give the identical item", JSON.stringify(a) == JSON.stringify(b))
	var seen: Dictionary = {}
	var shapes_ok: bool = true
	for i in 300:
		var it: Dictionary = GearGen.roll(_rng(1000 + i), "drop", {"ilvl": 30}, {})
		seen[String(it["base"]) + String(it["brand"]) + String(it["rar"])] = true
		var n: int = int(RarityDB.get_def(String(it["rar"]))["perks"]) + (1 if String(it["rar"]) == "exotic" else 0)
		shapes_ok = shapes_ok and (it["perks"] as Array).size() == n and int(it["lvl"]) == 1 and String(it["name"]) != ""
	t._check("P4 roll: varied items, each with its rarity's perk count, L1 and a name", seen.size() > 60 and shapes_ok, str(seen.size()))
	var c: Dictionary = _mk("weapon", "rail", "common", 5)
	var e: Dictionary = _mk("weapon", "rail", "epic", 5)
	t._check("P4 roll: names mark rarity (Common plain, Epic 'Mk III' with an epithet)", String(c["name"]).find("'") < 0 and String(e["name"]).ends_with("Mk III") and String(e["name"]).find("'") > 0, "%s | %s" % [c["name"], e["name"]])
	var pal: Array = BrandDB.get_def(String(c["brand"]))["palette"]
	t._check("P4 roll: paint starts on the brand palette with a pattern 0-7", String(c["paint"]["p"]) == String(pal[0]) and int(c["paint"]["pat"]) >= 0 and int(c["paint"]["pat"]) < GearGen.PATTERNS)
	var x: Dictionary = _mk("weapon", "arc", "exotic", 9, 100)
	var sig: int = 0
	for p in x["perks"]:
		sig += 1 if bool((p as Dictionary).get("sig", false)) else 0
	t._check("P4 roll: an Exotic carries 4 perks plus one signature perk", (x["perks"] as Array).size() == 5 and sig == 1)
	var p0: Dictionary = {"e": 4, "l": 9, "m": 2}
	GearGen.roll(_rng(3), "drop", {"rarity": "rare"}, p0)
	t._check("P4 roll: a forced rarity leaves pity untouched", int(p0["e"]) == 4 and int(p0["l"]) == 9 and int(p0["m"]) == 2)


# ------------------------------------------------------------------ odds

static func _odds(t) -> void:
	var sums_ok: bool = true
	for src in ["drop", "forge"]:
		for luck in [0.0, 3.0, 10.0, 40.0]:
			for pi in [{}, {"e": 25}, {"e": 29, "l": 149, "m": 999}, {"l": 120}]:
				var o: Dictionary = GearGen.odds_now(String(src), float(luck), pi)
				var tot: float = 0.0
				for r in RarityDB.IDS:
					tot += float(o[r])
					sums_ok = sums_ok and float(o[r]) >= -0.0001
				sums_ok = sums_ok and absf(tot - 100.0) < 0.001
	t._check("P4 odds: every disclosed table sums to 100% (sources x luck x pity)", sums_ok)
	var f: Dictionary = RarityDB.odds("forge")
	t._check("P4 odds: the Forge tops out at Legendary (no Mythic / Exotic)", float(f["mythic"]) == 0.0 and float(f["exotic"]) == 0.0 and float(f["legendary"]) > 0.0)
	var l0: Dictionary = RarityDB.odds("drop", 0.0)
	var l5: Dictionary = RarityDB.odds("drop", 5.0)
	t._check("P4 odds: luck moves odds off Common, up the ladder", float(l5["common"]) < float(l0["common"]) and float(l5["epic"]) > float(l0["epic"]) and float(l5["legendary"]) > float(l0["legendary"]))
	# 100k drop rolls, no pity: each rarity lands within +-10% of its odds
	var r := _rng(424242)
	var cnt: Dictionary = {}
	for id in RarityDB.IDS:
		cnt[id] = 0
	var n: int = 100000
	for i in n:
		var rr: String = GearGen.roll_rarity(r, "drop", 0.0, {})
		cnt[rr] = int(cnt[rr]) + 1
	var off: Array = []
	for id in ["common", "uncommon", "rare", "epic", "legendary"]:
		var exp: float = float(RarityDB.get_def(String(id))["drop"]) * float(n) / 100.0
		if absf(float(cnt[id]) - exp) > 0.1 * exp:
			off.append("%s %d/%d" % [id, cnt[id], int(exp)])
	var exp_m: float = 0.14 * float(n) / 100.0
	if absf(float(cnt["mythic"]) - exp_m) > 0.4 * exp_m:
		off.append("mythic %d/%d" % [cnt["mythic"], int(exp_m)])
	t._check("P4 odds: 100k drop rolls match the disclosed odds (+-10%)", off.is_empty(), str(off))


# ------------------------------------------------------------------ pity

static func _pity(t) -> void:
	var all_epic: bool = true
	for i in 200:
		var pi: Dictionary = {"e": 29}
		var rr: String = GearGen.roll_rarity(_rng(9000 + i), "forge", 0.0, pi)
		all_epic = all_epic and RarityDB.at_least(rr, "epic") and int(pi["e"]) == 0
	t._check("P4 pity: roll 30 without an Epic is a guaranteed Epic+ (and resets)", all_epic)
	var all_leg: bool = true
	for i in 100:
		var pi: Dictionary = {"e": 5, "l": 149}
		all_leg = all_leg and RarityDB.at_least(GearGen.roll_rarity(_rng(7000 + i), "forge", 0.0, pi), "legendary")
	t._check("P4 pity: roll 150 without a Legendary is a guaranteed Legendary", all_leg)
	var o0: Dictionary = GearGen.odds_now("forge", 0.0, {"e": 20})
	var o1: Dictionary = GearGen.odds_now("forge", 0.0, {"e": 21})
	var o2: Dictionary = GearGen.odds_now("forge", 0.0, {"e": 25})
	var ep: Callable = func(o: Dictionary) -> float: return float(o["epic"]) + float(o["legendary"])
	t._check("P4 pity: soft pity from roll 22 raises Epic+ odds steadily", is_equal_approx(ep.call(o0), ep.call(RarityDB.odds("forge"))) and ep.call(o1) > ep.call(o0) and ep.call(o2) > ep.call(o1) and ep.call(o2) < 100.0)
	# a scripted campaign: 3000 forge rolls never go 30 without an Epic+ / 150 without a Legendary
	var r := _rng(31337)
	var pi2: Dictionary = {}
	var gap_e: int = 0
	var gap_l: int = 0
	var max_e: int = 0
	var max_l: int = 0
	for i in 3000:
		var rr: String = GearGen.roll_rarity(r, "forge", 0.0, pi2)
		gap_e = 0 if RarityDB.at_least(rr, "epic") else gap_e + 1
		gap_l = 0 if RarityDB.at_least(rr, "legendary") else gap_l + 1
		max_e = maxi(max_e, gap_e)
		max_l = maxi(max_l, gap_l)
	t._check("P4 pity: 3000 Forge rolls never miss 30 for Epic+ or 150 for Legendary", max_e < 30 and max_l < 150 and max_e >= 10, "%d %d" % [max_e, max_l])
	var r2 := _rng(99)
	var pm: Dictionary = {}
	var gap_m: int = 0
	var max_m: int = 0
	for i in 6000:
		var rr: String = GearGen.roll_rarity(r2, "drop", 0.0, pm)
		gap_m = 0 if RarityDB.at_least(rr, "mythic") else gap_m + 1
		max_m = maxi(max_m, gap_m)
	t._check("P4 pity: drops never miss 1000 for a Mythic; the Forge never counts it", max_m < 1000 and not GearGen.odds_now("forge", 0.0, {"m": 999}).is_empty() and float(GearGen.odds_now("forge", 0.0, {"m": 999})["mythic"]) == 0.0, str(max_m))
	var pf: Dictionary = {"m": 7}
	GearGen.note_pity(pf, "common", "forge")
	t._check("P4 pity: Forge rolls advance Epic / Legendary pity but not Mythic", int(pf["m"]) == 7 and int(pf["e"]) == 1 and int(pf["l"]) == 1)


# ------------------------------------------------------------------ perks

static func _perks(t) -> void:
	var dup: bool = false
	var wrong_kind: bool = false
	var ramp_off_lance: bool = false
	var banned_seen: bool = false
	var bans: Dictionary = {"weapon": ["w_dmg", "w_rate", "a_dmg"]}
	for i in 600:
		var it: Dictionary = GearGen.roll(_rng(50000 + i), "drop", {"ilvl": 60, "bans": bans if i % 2 == 0 else {}}, {})
		var ids: Dictionary = {}
		for p in it["perks"]:
			var id: String = String((p as Dictionary)["id"])
			dup = dup or ids.has(id)
			ids[id] = true
			var k: String = String((AffixDB.DEFS[id] as Dictionary)["kind"])
			wrong_kind = wrong_kind or (k != "any" and k != String(it["kind"]))
			ramp_off_lance = ramp_off_lance or (id == "w_ramp" and String(it["base"]) != "lance")
			banned_seen = banned_seen or (i % 2 == 0 and String(it["kind"]) == "weapon" and (bans["weapon"] as Array).has(id))
	t._check("P4 perks: no duplicates on an item; kinds and frame-only perks respected", not dup and not wrong_kind and not ramp_off_lance)
	t._check("P4 perks: banned perks never roll", not banned_seen)
	var top_forge: int = 0
	var top_drop: int = 0
	for i in 200:
		for p in GearGen.roll(_rng(i), "forge", {"ilvl": 250}, {})["perks"]:
			top_forge = maxi(top_forge, int((p as Dictionary)["t"]))
		for p in GearGen.roll(_rng(i), "drop", {"ilvl": 250}, {})["perks"]:
			top_drop = maxi(top_drop, int((p as Dictionary)["t"]))
	t._check("P4 perks: Forge rolls cap at T5 at any item level; drops reach T7", top_forge == 5 and top_drop == 7, "%d %d" % [top_forge, top_drop])
	var aff: int = 0
	for i in 2000:
		var ps: Array = GearGen.roll_perks(_rng(i), "weapon", "rail", 1, 1, [], [])
		if (FrameDB.get_def("rail")["affinity"] as Array).has(String((ps[0] as Dictionary)["id"])):
			aff += 1
	var share: float = 0.0
	var tot: float = 0.0
	for id in AffixDB.pool("weapon", "rail"):
		var w: float = float((AffixDB.DEFS[id] as Dictionary)["w"]) * (2.0 if (FrameDB.get_def("rail")["affinity"] as Array).has(id) else 1.0)
		tot += w
		if (FrameDB.get_def("rail")["affinity"] as Array).has(id):
			share += w
	t._check("P4 perks: a frame's affinity perks roll at double weight", absf(float(aff) / 2000.0 - share / tot) < 0.04, "%.3f vs %.3f" % [float(aff) / 2000.0, share / tot])


# ------------------------------------------------------------------ costs

static func _costs(t) -> void:
	var c: Dictionary = _mk("weapon", "autocannon", "common")
	var r: Dictionary = _mk("weapon", "autocannon", "rare")
	var e: Dictionary = _mk("weapon", "autocannon", "epic")
	t._check("P4 cost: upgrade = 120 x RM x 1.17^(L-1) coins", Gear.upgrade_cost(c) == 120 and Gear.upgrade_cost(r) == 300 and Gear.upgrade_cost(e) == 480)
	c["lvl"] = 2
	t._check("P4 cost: upgrade L2 -> L3 of a Common is 140", Gear.upgrade_cost(c) == 140)
	c["lvl"] = 1
	t._check("P4 cost: reroll = 10 x RM Scrap at first", Gear.reroll_cost(c) == 10 and Gear.reroll_cost(e) == 40)
	c["rr"] = 1
	((c["perks"] as Array)[0] as Dictionary)["lock"] = true
	t._check("P4 cost: reroll grows x1.25 per reroll and x4 per locked perk", Gear.reroll_cost(c) == 50, str(Gear.reroll_cost(c)))
	t._check("P4 cost: imprint = 50 x RM Scrap", Gear.imprint_cost(c) == 50 and Gear.imprint_cost(e) == 200)
	var s: Dictionary = _save_with([])
	t._check("P4 cost: the first forge is 1500 coins + 40 Scrap", Gear.forge_cost(s)["coins"] == 1500 and Gear.forge_cost(s)["scrap"] == 40)
	Gear.block(s)["forged"] = 1
	var f1: int = int(Gear.forge_cost(s)["coins"])
	Gear.block(s)["forged"] = 40
	var f40: int = int(Gear.forge_cost(s)["coins"])
	Gear.block(s)["forged"] = 400
	t._check("P4 cost: forging ramps x1.08 per item and stops ramping at 40", f1 == 1620 and f40 == int(round(1500.0 * pow(1.08, 40.0))) and int(Gear.forge_cost(s)["coins"]) == f40)
	t._check("P4 cost: salvage pays the rarity's Scrap, +10% per level", Gear.salvage_value(_mk("module", "echo", "epic")) == 60 and Gear.salvage_value(_mk("module", "echo", "common")) == 4)


# ------------------------------------------------------------------ upgrade

static func _upgrade(t) -> void:
	var s: Dictionary = _save_with([_mk("weapon", "lance", "rare", 11)])
	var u: int = _last(s)
	var c0: int = int(s["coins"])
	var ev: Array = Gear.upgrade(s, u)
	t._check("P4 upgrade: spends the cost and raises the level", ev.size() == 1 and int(Gear.item(s, u)["lvl"]) == 2 and int(s["coins"]) == c0 - 300)
	var pw2: float = Gear.power(Gear.item(s, u))
	for i in 2:
		Gear.upgrade(s, u)
	var t_before: int = 0
	for p in Gear.item(s, u)["perks"]:
		t_before += int((p as Dictionary)["t"])
	var ev5: Array = Gear.upgrade(s, u)
	var t_after: int = 0
	for p in Gear.item(s, u)["perks"]:
		t_after += int((p as Dictionary)["t"])
	var it5: Dictionary = Gear.item(s, u)
	var mw_ok: bool = int(it5["mw"]) == 1 and int((ev5[0] as Dictionary).get("mw", 0)) == 1
	var gain: int = t_after - t_before + (1 if (ev5[0] as Dictionary).has("new_perk") else 0)
	t._check("P4 upgrade: level 5 is a masterwork (+1 tier, or a jackpot)", mw_ok and gain >= 1, str(ev5))
	t._check("P4 upgrade: levels and masterworks raise item power", Gear.power(it5) > pw2 and is_equal_approx(Gear.power(it5), 1.28 * 1.2 * 1.06))
	it5["lvl"] = Gear.max_lvl_of("rare")
	t._check("P4 upgrade: refused at the rarity's max level", Gear.upgrade(s, u).is_empty() and Gear.why_upgrade(s, u).begins_with("Max level"))
	it5["lvl"] = 3
	s["coins"] = 0
	t._check("P4 upgrade: refused without coins (the reason names the cost)", Gear.upgrade(s, u).is_empty() and Gear.why_upgrade(s, u) == "Need %d coins" % Gear.upgrade_cost(it5))
	# masterwork with a fixed op seed is reproducible; jackpots land near 15%
	var a: Dictionary = _save_with([_mk("weapon", "rail", "epic", 3)])
	var b: Dictionary = a.duplicate(true)
	for i in 4:
		Gear.upgrade(a, _last(a))
		Gear.upgrade(b, _last(b))
	t._check("P4 upgrade: the same save + clicks give the same masterwork", JSON.stringify(Gear.upgrade(a, _last(a))) == JSON.stringify(Gear.upgrade(b, _last(b))))
	var jack: int = 0
	var mws: int = 0
	var lvl10_mw: bool = true
	var s2: Dictionary = _save_with([])
	for i in 300:
		Gear.add_item(s2, _mk("module", "siphon", "common", 400 + i))
		var uu: int = _last(s2)
		for k in 9:
			for e in Gear.upgrade(s2, uu):
				if (e as Dictionary).has("mw"):
					mws += 1
					jack += 1 if bool(e["jackpot"]) else 0
		lvl10_mw = lvl10_mw and int(Gear.item(s2, uu)["mw"]) == 2 and int(Gear.item(s2, uu)["lvl"]) == 10
		Gear.salvage(s2, uu)   # stay under the inventory cap
	t._check("P4 upgrade: masterworks at L5 and L10; jackpots ~15%", lvl10_mw and mws == 600 and jack > 55 and jack < 125, "%d/%d" % [jack, mws])
	var it6: Dictionary = _mk("weapon", "rail", "common", 2)
	it6["lvl"] = 5
	it6["mw"] = 1
	var s3: Dictionary = _save_with([it6])
	var uid6: int = _last(s3)
	Gear.block(s3)["items"][str(uid6)]["lvl"] = 4
	var evr: Array = Gear.upgrade(s3, uid6)
	t._check("P4 upgrade: a milestone already masterworked doesn't pay twice", not (evr[0] as Dictionary).has("mw"))


# ------------------------------------------------------------------ reroll / lock

static func _reroll_lock(t) -> void:
	var it: Dictionary = _mk("weapon", "autocannon", "epic", 21, 30)
	var s: Dictionary = _save_with([it])
	var u: int = _last(s)
	var sc0: int = int(s["scrap"])
	var ev: Array = Gear.reroll(s, u, 0)
	var of: Dictionary = Gear.block(s)["offer"]
	var cands: Array = of.get("cands", [])
	var ids_ok: bool = cands.size() == 2 and String((cands[0] as Dictionary)["id"]) != String((cands[1] as Dictionary)["id"])
	for c in cands:
		for p in Gear.item(s, u)["perks"]:
			ids_ok = ids_ok and String((c as Dictionary)["id"]) != String((p as Dictionary)["id"])
	t._check("P4 reroll: pays Scrap, offers 2 new distinct perks (none already on the item)", ev.size() == 1 and int(s["scrap"]) == sc0 - 40 and ids_ok and int(Gear.item(s, u)["rr"]) == 1)
	t._check("P4 reroll: one open offer at a time", Gear.reroll(s, u, 1).is_empty() and Gear.why_reroll(s, u, 1).begins_with("Choose"))
	var old: Dictionary = ((Gear.item(s, u)["perks"] as Array)[0] as Dictionary).duplicate()
	Gear.reroll_choose(s, -1)
	t._check("P4 reroll: keep leaves the perk and closes the offer", JSON.stringify((Gear.item(s, u)["perks"] as Array)[0]) == JSON.stringify(old) and (Gear.block(s)["offer"] as Dictionary).is_empty())
	Gear.reroll(s, u, 0)
	var pick: Dictionary = ((Gear.block(s)["offer"]["cands"] as Array)[1] as Dictionary).duplicate()
	Gear.reroll_choose(s, 1)
	t._check("P4 reroll: take swaps in the chosen candidate", String(((Gear.item(s, u)["perks"] as Array)[0] as Dictionary)["id"]) == String(pick["id"]))
	t._check("P4 reroll: cost grows with each reroll (x1.25)", Gear.reroll_cost(Gear.item(s, u)) == int(round(40.0 * 1.25 * 1.25)))
	# rerolls never produce T6+, even on a T7 perk
	var hi: Dictionary = _mk("weapon", "autocannon", "rare", 5, 250)
	var s2: Dictionary = _save_with([hi], 0, 100_000_000)
	var u2: int = _last(s2)
	var top: int = 0
	for i in 30:
		Gear.reroll(s2, u2, i % 2)
		for c in Gear.block(s2)["offer"]["cands"]:
			top = maxi(top, int((c as Dictionary)["t"]))
		Gear.reroll_choose(s2, -1)
	t._check("P4 reroll: candidates never exceed T5 (T6-T7 are drop-only)", top == 5 and int(((Gear.item(s2, u2)["perks"] as Array)[0] as Dictionary)["t"]) == 7, str(top))
	# locks
	var s3: Dictionary = _save_with([_mk("weapon", "rail", "epic", 8)])
	var u3: int = _last(s3)
	t._check("P4 lock: one lock slot at first", Gear.lock(s3, u3, 0, true).size() == 1 and Gear.lock(s3, u3, 1, true).is_empty() and Gear.why_lock(s3, u3, 1, true).begins_with("Lock slots full"))
	t._check("P4 lock: a locked perk can't be rerolled; lock raises reroll cost x4", Gear.reroll(s3, u3, 0).is_empty() and Gear.reroll_cost(Gear.item(s3, u3)) == 160)
	(s3["research"]["lvls"] as Dictionary)["stabilizer"] = 2
	t._check("P4 lock: Stabilizer research opens up to 3 lock slots", Gear.lock(s3, u3, 1, true).size() == 1 and Gear.lock(s3, u3, 2, true).size() == 1 and Gear.locks_on(Gear.item(s3, u3)) == 3)
	Gear.lock(s3, u3, 2, false)
	t._check("P4 lock: unlocking is free and frees the slot", Gear.locks_on(Gear.item(s3, u3)) == 2)
	(s3["research"]["lvls"] as Dictionary)["enchanters_eye"] = 1
	Gear.reroll(s3, u3, 2)
	t._check("P4 reroll: Enchanter's Eye research offers 3 candidates", (Gear.block(s3)["offer"]["cands"] as Array).size() == 3)
	# bans
	var s4: Dictionary = _save_with([])
	t._check("P4 ban: none without Blacklist research", Gear.ban(s4, "weapon", "w_dmg", true).is_empty())
	(s4["research"]["lvls"] as Dictionary)["blacklist"] = 1
	t._check("P4 ban: Blacklist I bans one perk per kind", Gear.ban(s4, "weapon", "w_dmg", true).size() == 1 and Gear.ban(s4, "weapon", "w_rate", true).is_empty() and Gear.ban(s4, "module", "m_hp", true).size() == 1)
	t._check("P4 ban: kinds don't cross", Gear.why_ban(s4, "module", "w_dmg", true) != "")


# ------------------------------------------------------------------ merge

static func _merge(t) -> void:
	var s: Dictionary = _save_with([_mk("weapon", "autocannon", "common", 1), _mk("weapon", "rail", "common", 2), _mk("weapon", "arc", "common", 3)])
	var u3: int = _last(s)
	var set3: Array = [u3 - 2, u3 - 1, u3]
	Gear.block(s)["items"][str(u3 - 1)]["lvl"] = 7
	var ch: Array = Gear.merge_choices(s, set3, u3 - 2)
	var ch2: Array = Gear.merge_choices(s, set3, u3 - 2)
	t._check("P4 merge: C -> U adds a perk slot: choices = sacrifices' perks + 1 fresh roll", ch.size() >= 2 and ch.size() <= 3 and JSON.stringify(ch) == JSON.stringify(ch2))
	var want: Dictionary = (ch[ch.size() - 1] as Dictionary).duplicate()
	var ev: Array = Gear.merge(s, set3, u3 - 2, ch.size() - 1)
	var b: Dictionary = Gear.item(s, u3 - 2)
	t._check("P4 merge: rarity +1, the chosen perk added, level = half the best input", ev.size() == 1 and String(b["rar"]) == "uncommon" and (b["perks"] as Array).size() == 2 and String(((b["perks"] as Array)[1] as Dictionary)["id"]) == String(want["id"]) and int(b["lvl"]) == 3)
	t._check("P4 merge: the two sacrifices are consumed", not Gear.has_item(Gear.block(s), u3 - 1) and not Gear.has_item(Gear.block(s), u3))
	t._check("P4 merge: the base keeps frame, brand, seed and paint", String(b["base"]) == "autocannon" and int(b["seed"]) == int(_mk("weapon", "autocannon", "common", 1)["seed"]))
	# U -> R: same slot count -> +1 tier on the weakest perk
	var s2: Dictionary = _save_with([_mk("module", "echo", "uncommon", 4), _mk("module", "siphon", "uncommon", 5), _mk("module", "overclock", "uncommon", 6)])
	var v3: int = _last(s2)
	var tsum0: int = 0
	for p in Gear.item(s2, v3)["perks"]:
		tsum0 += int((p as Dictionary)["t"])
	t._check("P4 merge: U -> R adds no slot (no choices)", Gear.merge_choices(s2, [v3 - 2, v3 - 1, v3], v3).is_empty())
	Gear.merge(s2, [v3 - 2, v3 - 1, v3], v3)
	var tsum1: int = 0
	for p in Gear.item(s2, v3)["perks"]:
		tsum1 += int((p as Dictionary)["t"])
	t._check("P4 merge: ... and raises its weakest perk one tier", String(Gear.item(s2, v3)["rar"]) == "rare" and tsum1 == tsum0 + 1 and (Gear.item(s2, v3)["perks"] as Array).size() == 2)
	# refusals
	var s3: Dictionary = _save_with([_mk("weapon", "autocannon", "rare", 1), _mk("weapon", "rail", "rare", 2), _mk("weapon", "arc", "epic", 3), _mk("module", "echo", "rare", 4)])
	var w3: int = _last(s3)
	t._check("P4 merge: refuses mixed rarities", Gear.why_merge(s3, [w3 - 3, w3 - 2, w3 - 1], w3 - 3) == "Same rarity only")
	t._check("P4 merge: refuses mixed kinds", Gear.why_merge(s3, [w3 - 3, w3 - 2, w3], w3 - 3).begins_with("Same kind"))
	t._check("P4 merge: refuses a base outside the three / repeats / wrong count", Gear.why_merge(s3, [w3 - 3, w3 - 2, w3 - 3], w3 - 3) != "" and Gear.why_merge(s3, [w3 - 3, w3 - 2], w3 - 3) != "")
	Gear.block(s3)["items"][str(w3 - 2)]["fav"] = true
	Gear.add_item(s3, _mk("weapon", "saw", "rare", 9))
	t._check("P4 merge: refuses to consume a favourite", Gear.why_merge(s3, [w3 - 3, w3 - 2, _last(s3)], w3 - 3).begins_with("A favourite"))
	t._check("P4 merge: a favourite may be the base", Gear.why_merge(s3, [w3 - 3, w3 - 2, _last(s3)], w3 - 2) == "")
	var s4: Dictionary = _save_with([_mk("weapon", "rail", "legendary", 1), _mk("weapon", "rail", "legendary", 2), _mk("weapon", "rail", "legendary", 3)])
	var x3: int = _last(s4)
	t._check("P4 merge: Legendary -> Mythic needs Mythic Fusion research", Gear.why_merge(s4, [x3 - 2, x3 - 1, x3], x3) == "Mythic Fusion research needed")
	(s4["research"]["lvls"] as Dictionary)["mythic_fusion"] = 1
	Gear.merge(s4, [x3 - 2, x3 - 1, x3], x3)
	t._check("P4 merge: ... and with it makes a Mythic with a 4th perk", String(Gear.item(s4, x3)["rar"]) == "mythic" and (Gear.item(s4, x3)["perks"] as Array).size() == 4 and String(Gear.item(s4, x3)["name"]).ends_with("Apex"))
	var s5: Dictionary = _save_with([_mk("weapon", "rail", "mythic", 1), _mk("weapon", "rail", "mythic", 2), _mk("weapon", "rail", "mythic", 3)])
	var y3: int = _last(s5)
	t._check("P4 merge: Mythic never merges into an Exotic (drop-only)", Gear.why_merge(s5, [y3 - 2, y3 - 1, y3], y3) == "Exotics only drop")
	# an equipped weapon sacrificed hands the slot to the merged base
	var s6: Dictionary = _save_with([_mk("weapon", "pulse", "common", 1), _mk("weapon", "pulse", "common", 2)])
	var z: int = _last(s6)
	var start: int = int(Gear.block(s6)["equipped"]["weapon"])
	Gear.merge(s6, [start, z - 1, z], z)
	t._check("P4 merge: consuming the equipped weapon equips the merged one", int(Gear.block(s6)["equipped"]["weapon"]) == z and not Gear.has_item(Gear.block(s6), start))


# ------------------------------------------------------------------ imprint / salvage

static func _imprint_salvage(t) -> void:
	var a: Dictionary = _mk("weapon", "rail", "rare", 12)
	var b: Dictionary = _mk("weapon", "rail", "common", 13)
	(b["perks"] as Array)[0] = {"id": "w_crit_dmg", "t": 4, "q": 0.9, "lock": false}
	(a["perks"] as Array)[0] = {"id": "w_dmg", "t": 1, "q": 0.1, "lock": false}
	(a["perks"] as Array)[1] = {"id": "w_rate", "t": 2, "q": 0.5, "lock": false}
	var s: Dictionary = _save_with([a, b])
	var ub: int = _last(s)
	var ua: int = ub - 1
	var sc0: int = int(s["scrap"])
	var ev: Array = Gear.imprint(s, ua, ub, 0, 0)
	var p0: Dictionary = (Gear.item(s, ua)["perks"] as Array)[0]
	t._check("P4 imprint: copies the donor's perk over the slot, consumes the donor, costs 50 x RM", ev.size() == 1 and String(p0["id"]) == "w_crit_dmg" and int(p0["t"]) == 4 and not Gear.has_item(Gear.block(s), ub) and int(s["scrap"]) == sc0 - 125)
	var c: Dictionary = _mk("weapon", "rail", "common", 14)
	(c["perks"] as Array)[0] = {"id": "w_rate", "t": 5, "q": 0.5, "lock": false}
	Gear.add_item(s, c)
	t._check("P4 imprint: refuses a perk the target already has elsewhere", Gear.why_imprint(s, ua, _last(s), 0, 0) == "The target already has that perk")
	((Gear.item(s, ua)["perks"] as Array)[1] as Dictionary)["lock"] = true
	t._check("P4 imprint: refuses a locked target slot / cross-kind donors", Gear.why_imprint(s, ua, _last(s), 0, 1) == "That slot is locked")
	Gear.add_item(s, _mk("module", "echo", "rare", 15))
	var um: int = _last(s)
	Gear.equip(s, um, 0)
	var sc1: int = int(s["scrap"])
	var w0: int = int(Gear.block(s)["equipped"]["weapon"])
	t._check("P4 salvage: refuses the equipped weapon", Gear.salvage(s, w0).is_empty())
	Gear.set_fav(s, ua, true)
	t._check("P4 salvage: refuses a favourite", Gear.salvage(s, ua).is_empty() and Gear.why_salvage(s, ua).begins_with("Unfavourite"))
	t._check("P4 salvage: pays Scrap and empties the socket it held", Gear.salvage(s, um).size() == 1 and int(s["scrap"]) == sc1 + 25 and int((Gear.block(s)["equipped"]["sockets"] as Array)[0]) == 0)


# ------------------------------------------------------------------ forge

static func _forge(t) -> void:
	var s: Dictionary = _save_with([], 5000, 100)
	var n0: int = Gear.count(s)
	var ev: Array = Gear.forge_new(s, "weapon", "scatter")
	var it: Dictionary = Gear.item(s, _last(s))
	t._check("P4 forge: makes the chosen frame, pays 1500 coins + 40 Scrap", ev.size() == 1 and Gear.count(s) == n0 + 1 and String(it["base"]) == "scatter" and int(s["coins"]) == 3500 and int(s["scrap"]) == 60 and int(Gear.block(s)["forged"]) == 1)
	t._check("P4 forge: item level = 10 + 2 x Core level, marked new", int(it["ilvl"]) == 12 and bool(it["new"]) and String(it["src"]) == "forge")
	var pe: int = int(Gear.block(s)["pity"]["e"])
	t._check("P4 forge: advances visible pity", (pe == 1) != RarityDB.at_least(String(it["rar"]), "epic"))
	s["coins"] = 100
	t._check("P4 forge: refused when poor (reason names the coins)", Gear.forge_new(s, "weapon", "scatter").is_empty() and Gear.why_forge(s, "weapon", "scatter").begins_with("Need"))
	s["coins"] = 1_000_000
	t._check("P4 forge: a brand pick needs Brand Contracts research", Gear.why_forge(s, "weapon", "rail", "nyx") != "")
	(s["research"]["lvls"] as Dictionary)["brand_contracts"] = 1
	Gear.forge_new(s, "module", "regen_cell", "nyx")
	t._check("P4 forge: ... and with it forges that brand; modules forge too", String(Gear.item(s, _last(s))["brand"]) == "nyx" and String(Gear.item(s, _last(s))["kind"]) == "module")
	t._check("P4 forge: unknown frames are refused", Gear.forge_new(s, "weapon", "nope").is_empty())
	var a: Dictionary = _save_with([])
	var b: Dictionary = _save_with([])
	for i in 5:
		Gear.forge_new(a, "weapon", "rail")
		Gear.forge_new(b, "weapon", "rail")
	t._check("P4 forge: the same save + clicks forge the same items", JSON.stringify(Gear.block(a)["items"]) == JSON.stringify(Gear.block(b)["items"]))


# ------------------------------------------------------------------ equip

static func _equip(t) -> void:
	t._check("P4 sockets: 2 at Core L1, +1 at L5 / 10 / 18 / 28 / 40 / 55 (max 8)", Gear.sockets_for(1) == 2 and Gear.sockets_for(4) == 2 and Gear.sockets_for(5) == 3 and Gear.sockets_for(10) == 4 and Gear.sockets_for(18) == 5 and Gear.sockets_for(28) == 6 and Gear.sockets_for(40) == 7 and Gear.sockets_for(55) == 8 and Gear.sockets_for(75) == 8)
	var s: Dictionary = _save_with([_mk("module", "echo", "rare", 1), _mk("module", "siphon", "rare", 2), _mk("module", "crit_lens", "rare", 3), _mk("weapon", "lance", "epic", 4)])
	var u: int = _last(s)
	Gear.equip(s, u - 3)
	Gear.equip(s, u - 2)
	var so: Array = Gear.block(s)["equipped"]["sockets"]
	t._check("P4 equip: modules fill the first empty sockets", so.size() == 2 and int(so[0]) == u - 3 and int(so[1]) == u - 2)
	t._check("P4 equip: socket 3 opens at Core L5", Gear.equip(s, u - 1, 2).is_empty() and Gear.why_equip(s, u - 1, 2) == "Socket opens at Core level 5")
	Gear.equip(s, u - 2, 0)
	t._check("P4 equip: moving a module to an occupied socket swaps them", int(so[0]) == u - 2 and int(so[1]) == u - 3)
	Gear.equip(s, u)
	t._check("P4 equip: a weapon goes to the centre slot", int(Gear.block(s)["equipped"]["weapon"]) == u and String(Gear.weapon(s)["base"]) == "lance")
	s["core"]["lvl"] = 10
	Gear.equip(s, u - 1, 3)
	t._check("P4 equip: a higher Core level opens more sockets", (Gear.block(s)["equipped"]["sockets"] as Array).size() == 4 and int((Gear.block(s)["equipped"]["sockets"] as Array)[3]) == u - 1 and Gear.modules(s).size() == 3)
	Gear.unequip(s, 3)
	t._check("P4 equip: unequip empties the socket", Gear.modules(s).size() == 2)


# ------------------------------------------------------------------ run hand-off

static func _hand_off(t) -> void:
	var s: Dictionary = BaseMeta.default_save()
	var w: Dictionary = Gear.weapon(s)
	t._check("P4 start: a fresh save equips a Standard Issue Autocannon (Common, no perks, no quirk)", String(w["base"]) == "autocannon" and String(w["rar"]) == "common" and String(w["brand"]) == "standard" and (w["perks"] as Array).is_empty() and Gear.count(s) == 1 and String(w["name"]) == "Standard Issue Autocannon")
	t._check("P4 start: ... so a fresh run's gear fx are empty (the base Core sheet)", Gear.run_fx(s).is_empty())
	t._check("P4 start: the standard brand is never rolled", not BrandDB.IDS.has("standard") and BrandDB.has("standard") and (BrandDB.get_def("standard")["quirk"] as Dictionary).is_empty())
	var kw: Dictionary = _mk("weapon", "autocannon", "rare", 31)
	kw["brand"] = "kessler"
	Gear.add_item(s, kw)
	Gear.equip(s, _last(s))
	var fx: Dictionary = Gear.run_fx(s)
	var want: Dictionary = {}
	for p in kw["perks"]:
		var key: String = String((AffixDB.DEFS[String((p as Dictionary)["id"])] as Dictionary)["key"])
		want[key] = float(want.get(key, 0.0)) + AffixDB.value(String(p["id"]), int(p["t"]), float(p["q"]))
	for k in (BrandDB.get_def("kessler")["quirk"] as Dictionary).keys():
		want[k] = float(want.get(k, 0.0)) + float(BrandDB.get_def("kessler")["quirk"][k])
	var same: bool = want.size() == fx.size()
	for k in want.keys():
		same = same and is_equal_approx(float(want[k]), float(fx.get(k, -99.0)))
	t._check("P4 fx: run_fx = weapon perks + brand quirk", same, "%s vs %s" % [want, fx])
	var m: Dictionary = _mk("module", "twin_feed", "epic", 7)
	m["perks"] = []
	m["brand"] = "volt"
	m["mw"] = 4
	m["lvl"] = 20
	Gear.add_item(s, m)
	Gear.equip(s, _last(s))
	var fx2: Dictionary = Gear.run_fx(s)
	t._check("P4 fx: count fx stay whole and grow +1 per 2 masterworks", is_equal_approx(float(fx2["multishot"]) - float(fx.get("multishot", 0.0)), 3.0))
	t._check("P4 fx: a module's brand quirk counts half", is_equal_approx(float(fx2.get("chain_dmg", 0.0)) - float(fx.get("chain_dmg", 0.0)), 0.075))
	var oc: Dictionary = _mk("module", "overclock", "legendary", 8)
	var ofx: Dictionary = Gear.module_fx(oc)
	t._check("P4 fx: module fx scale with power; a trade-off's cost does not", is_equal_approx(float(ofx["rate"]), 0.25 * 1.72) and is_equal_approx(float(ofx["core_hp"]), -0.15))
	var lance: Dictionary = _mk("weapon", "lance", "epic", 9)
	lance["lvl"] = 3
	Gear.add_item(s, lance)
	Gear.equip(s, _last(s))
	var ws: Dictionary = Gear.weapon_sheet(s)
	t._check("P4 sheet: the equipped frame decides the attack; damage x item power", String(ws["attack"]) == "beam" and is_equal_approx(float(ws["dmg"]), 28.0 * 1.48 * 1.1) and float(ws["ramp"]) == 0.15)
	# every fx key gear can produce is read by the run (TowerState.pf) or pending P4b
	var src: String = FileAccess.get_file_as_string("res://TowerState.gd")
	var keys: Dictionary = {}
	for id in AffixDB.DEFS.keys():
		keys[String((AffixDB.DEFS[id] as Dictionary)["key"])] = true
	for id in ModuleDB.IDS:
		for k in (ModuleDB.DEFS[id]["fx"] as Dictionary).keys():
			keys[String(k)] = true
	for b in BrandDB.IDS:
		for k in (BrandDB.DEFS[b]["quirk"] as Dictionary).keys():
			keys[String(k)] = true
	var unread: Array = []
	var stale: Array = []
	for k in keys.keys():
		var read: bool = src.find("pf(\"%s\")" % k) >= 0
		if not read and not PENDING_FX.has(k):
			unread.append(k)
		if read and PENDING_FX.has(k):
			stale.append(k)
	t._check("P4 fx: every gear fx key is read by the run (TowerState.pf)", unread.is_empty() and stale.is_empty(), "unread %s stale %s" % [unread, stale])


# ------------------------------------------------------------------ save

static func _save(t) -> void:
	var s: Dictionary = _save_with([_mk("weapon", "rail", "epic", 1), _mk("module", "echo", "rare", 2)])
	Gear.equip(s, _last(s))
	Gear.reroll(s, _last(s), 0)
	var js: Dictionary = JSON.parse_string(JSON.stringify(s))
	var n1: Dictionary = BaseMeta.normalize(js)
	var n2: Dictionary = BaseMeta.normalize(JSON.parse_string(JSON.stringify(n1)))
	t._check("P4 save: the gear block survives a JSON round trip (and normalize is idempotent)", JSON.stringify(n1["gear"]) == JSON.stringify(n2["gear"]) and Gear.count(n1) == 3 and int((n1["gear"]["equipped"]["sockets"] as Array)[0]) == _last(s) and not (n1["gear"]["offer"] as Dictionary).is_empty())
	t._check("P4 save: uids and levels come back as ints", typeof(n1["gear"]["equipped"]["weapon"]) == TYPE_INT and typeof(Gear.item(n1, _last(s))["lvl"]) == TYPE_INT and typeof(n1["gear"]["next"]) == TYPE_INT)
	var bad: Dictionary = BaseMeta.default_save()
	bad["gear"] = {"items": {"5": {"kind": "weapon", "base": "nope"}, "x": {"kind": "module", "base": "echo"}, "7": {"kind": "module", "base": "echo", "rar": "rare", "perks": [{"id": "w_dmg", "t": 9}, {"id": "m_hp", "t": 99, "q": 7}, {"id": "m_hp"}]}},
		"equipped": {"weapon": 7, "sockets": [7, 7, 7, 99]}, "pity": {"e": -4, "l": 9999}, "bans": {"weapon": ["m_hp", "w_dmg", "zzz"]}, "next": -3}
	var nb: Dictionary = BaseMeta.normalize(bad)
	var g: Dictionary = nb["gear"]
	var m7: Dictionary = Gear.get_item(g, 7)
	t._check("P4 save: garbage items are dropped; bad perks filtered and clamped", Gear.has_item(g, 7) and not Gear.has_item(g, 5) and (m7["perks"] as Array).size() == 1 and int(((m7["perks"] as Array)[0] as Dictionary)["t"]) == 7 and float(((m7["perks"] as Array)[0] as Dictionary)["q"]) == 1.0)
	t._check("P4 save: a missing weapon falls back to a starter; sockets de-duplicated to the Core's count", String(Gear.weapon(nb)["base"]) == "autocannon" and (g["equipped"]["sockets"] as Array) == [7, 0] and int(g["next"]) > 7)
	t._check("P4 save: pity clamped; bans keep valid same-kind perks only", int(g["pity"]["e"]) == 0 and int(g["pity"]["l"]) == 150 and (g["bans"]["weapon"] as Array) == ["w_dmg"])
	var nn: Dictionary = BaseMeta.normalize({"version": 5})
	t._check("P4 save: a v5 save without gear gets the starter loadout", String(Gear.weapon(nn)["base"]) == "autocannon" and Gear.count(nn) == 1)
	var old: Dictionary = BaseMeta.normalize({"version": 4, "coins": 500, "cards": {}})
	t._check("P4 save: the V2 hard reset also starts with the starter weapon", Gear.count(old) == 1 and bool(old.get("reset_v2", false)))
	# Core look
	var c: Dictionary = BaseMeta.default_save()
	t._check("P4 look: the Core starts on the default look", Cores.look(c)["shell"] == 0 and String(Cores.look(c)["s"]) == "39e6ff")
	var e1: Array = Cores.set_look(c, "shell", 5)
	var e2: Array = Cores.set_look(c, "p", "#FF8800")
	var e3: Array = Cores.set_look(c, "g", "zzzzzz")
	t._check("P4 look: shell / colours change; bad hex is refused", e1.size() == 1 and e2.size() == 1 and e3.is_empty() and int(Cores.look(c)["shell"]) == 5 and String(Cores.look(c)["p"]) == "ff8800")
	var nl: Dictionary = BaseMeta.normalize({"version": 5, "core": {"lvl": 3, "look": {"shell": 99, "trim": -2, "p": "12345g", "s": "abcdef"}}})
	t._check("P4 look: normalize clamps shapes and keeps valid colours", int(Cores.look(nl)["shell"]) == Cores.SHELLS - 1 and int(Cores.look(nl)["trim"]) == 0 and String(Cores.look(nl)["p"]) == "1b2440" and String(Cores.look(nl)["s"]) == "abcdef")
