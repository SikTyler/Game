extends RefCounted
## V3 selftest stage: procedural parts art (PartVis.weapon_desc / core_desc,
## the pure descriptions every draw call renders). Every base has its own
## silhouette in its slot, installed parts show on the build, Legendary+
## Receivers fan their barrels, and random builds look different. `t` is the
## selftest runner.

const PartVis := preload("res://PartVis.gd")
const Parts := preload("res://Parts.gd")
const PartDB := preload("res://data/PartDB.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const BaseMeta := preload("res://BaseMeta.gd")


static func run(t) -> void:
	var dup: Array = []
	for sl in PartDB.SLOTS.keys():
		var seen: Dictionary = {}
		for b in PartDB.bases_of(String(sl)):
			var lk: int = int(PartDB.get_def(String(b))["look"])
			var key: String = "%s/%d" % [PartDB.get_def(String(b)).get("frame", ""), lk]
			if seen.has(key):
				dup.append("%s:%s" % [sl, b])
			seen[key] = true
	t._check("V3 vis: every part base has its own silhouette in its slot", dup.is_empty(), str(dup))
	var sv: Dictionary = BaseMeta.default_save()
	var w0: Dictionary = PartVis.weapon_desc(sv)
	var c0: Dictionary = PartVis.core_desc(sv)
	t._check("V3 vis: the starter kit draws one Autocannon barrel on a bare hub and an unplated Core", (w0["brl"] as Array).size() == 1 and String(w0["brl"][0]["frame"]) == "autocannon" and (w0["ammo"] as Array).is_empty() and (w0["scope"] as Dictionary).is_empty() and (c0["plating"] as Array).is_empty() and (c0["emitter"] as Dictionary).is_empty())
	Parts.equip(sv, Parts.add_item(sv, Parts.make("rcv_heavy", "legendary")))
	Parts.equip(sv, Parts.add_item(sv, Parts.make("brl_minigun")))
	Parts.equip(sv, Parts.add_item(sv, Parts.make("amm_cryo")))
	Parts.equip(sv, Parts.add_item(sv, Parts.make("scp_thermal")))
	Parts.equip(sv, Parts.add_item(sv, Parts.make("mzl_split")))
	Parts.equip(sv, Parts.add_item(sv, Parts.make("hrt_bastion", "legendary")))
	Parts.equip(sv, Parts.add_item(sv, Parts.make("plt_spiked")))
	Parts.equip(sv, Parts.add_item(sv, Parts.make("plt_crystal")))
	Parts.equip(sv, Parts.add_item(sv, Parts.make("emi_thorns")))
	Parts.equip(sv, Parts.add_item(sv, Parts.make("ant_luck")))
	var w1: Dictionary = PartVis.weapon_desc(sv)
	var c1: Dictionary = PartVis.core_desc(sv)
	t._check("V3 vis: installed parts show on the Weapon (2 barrels on a Legendary hub, ammo canister, scope, muzzle)", (w1["brl"] as Array).size() == 2 and String(w1["brl"][1]["frame"]) == "minigun" and String(w1["rcv"]["rar"]) == "legendary" and (w1["ammo"] as Array) == [5] and int(w1["scope"]["look"]) == 3 and int(w1["muzzle"]["look"]) == 5)
	t._check("V3 vis: ... and on the Core (two platings, thorn dome, antenna masts)", (c1["plating"] as Array).size() == 2 and int(c1["emitter"]["look"]) == 2 and not (c1["antenna"] as Dictionary).is_empty())
	t._check("V3 vis: the same build always draws the same", PartVis.signature(sv) == PartVis.signature(sv.duplicate(true)))
	# random builds look different
	var sigs: Dictionary = {}
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	for i in 400:
		var s2: Dictionary = BaseMeta.default_save()
		Parts.equip(s2, Parts.add_item(s2, Parts.roll(r, "drop", {"slot": "receiver", "rarity": RarityDB.IDS[r.randi_range(0, 6)]}, {})))
		Parts.equip(s2, Parts.add_item(s2, Parts.roll(r, "drop", {"slot": "heart", "rarity": RarityDB.IDS[r.randi_range(0, 6)]}, {})))
		for sl in PartDB.SLOTS.keys():
			if PartDB.is_chassis(String(sl)):
				continue
			for k in 2:
				if r.randf() < 0.7:
					Parts.equip(s2, Parts.add_item(s2, Parts.roll(r, "drop", {"slot": String(sl)}, {})))
		sigs[PartVis.signature(s2)] = true
	t._check("V3 vis: 400 random builds give >= 390 distinct looks", sigs.size() >= 390, str(sigs.size()))
