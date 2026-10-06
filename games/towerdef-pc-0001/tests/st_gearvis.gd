extends RefCounted
## P4c selftest stage: procedural gear visuals (GearVis.parts, the pure
## description every draw call renders). 1000 rolled items look different,
## the same item always looks the same, and perks / masterworks / levels /
## rarity grow the parts their text promises. `t` is the selftest runner.

const GearVis := preload("res://GearVis.gd")
const GearGen := preload("res://GearGen.gd")
const Gear := preload("res://Gear.gd")
const FrameDB := preload("res://data/FrameDB.gd")


static func run(t) -> void:
	var sigs: Dictionary = {}
	var wsigs: Dictionary = {}
	var wn: int = 0
	for i in 1000:
		var r := RandomNumberGenerator.new()
		r.seed = 777000 + i
		var it: Dictionary = GearGen.roll(r, "drop", {"ilvl": 40}, {})
		sigs[GearVis.signature(it)] = true
		if String(it["kind"]) == "weapon":
			wn += 1
			wsigs[GearVis.signature(it)] = true
	t._check("P4 vis: 1000 rolled items give >= 900 distinct looks", sigs.size() >= 900, str(sigs.size()))
	t._check("P4 vis: rolled weapons alone stay >= 90% distinct", float(wsigs.size()) >= 0.9 * float(wn), "%d/%d" % [wsigs.size(), wn])
	var a: Dictionary = Gear.make("weapon", "rail", "epic", 12)
	t._check("P4 vis: the same item always draws the same parts", GearVis.signature(a) == GearVis.signature(a.duplicate(true)))
	var want: Dictionary = {"w_crit": "scope", "w_crit_dmg": "scope", "w_multishot": "twin", "w_splash": "drum", "w_chain": "coil", "w_burn": "canister", "w_pierce": "rail", "w_slow": "vanes", "w_bounce": "twin"}
	var bad: Array = []
	for id in want.keys():
		var w: Dictionary = Gear.make("weapon", "autocannon", "rare", 1, [{"id": id, "t": 2, "q": 0.5, "lock": false}])
		if not (GearVis.parts(w)["grown"] as Array).has(want[id]):
			bad.append(id)
	t._check("P4 vis: perks grow their parts (crit scope, twin barrel, drum, coil, canister, rail, vanes)", bad.is_empty(), str(bad))
	var plain: Dictionary = GearVis.parts(Gear.make("weapon", "autocannon"))
	t._check("P4 vis: a plain Common has no grown parts, trims, fins or rim", (plain["grown"] as Array).is_empty() and int(plain["trim"]) == 0 and int(plain["mw"]) == 0 and not bool(plain["rim"]))
	var hi: Dictionary = GearVis.parts(Gear.make("weapon", "autocannon", "legendary", 22))
	t._check("P4 vis: level 20+ = 2 trims, 4 masterworks = 4 fins, Legendary+ gets the animated rim", int(hi["trim"]) == 2 and int(hi["mw"]) == 4 and bool(hi["rim"]))
	var looks: Dictionary = {}
	for id in FrameDB.IDS:
		var p: Dictionary = GearVis.parts(Gear.make("weapon", String(id)))
		looks["%d/%d/%d" % [p["body"], p["barrel"], p["muzzle"]]] = true
	t._check("P4 vis: the 10 frames have 10 different silhouettes", looks.size() == 10)
	var m: Dictionary = GearVis.parts(Gear.make("module", "overclock"))
	t._check("P4 vis: modules draw their ModuleDB look", int(m["look"]) == 22 and String(m["kind"]) == "module")
