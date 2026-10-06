extends RefCounted
## P6 selftest stage: Core level costs and milestone requirements
## (CoreLevelDB / Cores). Every 5th level needs Outpost buildings, the Relay
## or Core Theory research; Cores.missing() names what is missing (the Core
## tab's jump chips). `t` is the selftest runner.

const Cores := preload("res://Cores.gd")
const CoreLevelDB := preload("res://data/CoreLevelDB.gd")
const Outpost := preload("res://Outpost.gd")
const BaseMeta := preload("res://BaseMeta.gd")

const OT0: int = 1767225600


static func run(t) -> void:
	t._check("P6 core level: cost = round(300 x 1.2^(L-1)) coins", CoreLevelDB.cost(1) == 300 and CoreLevelDB.cost(2) == 360 and CoreLevelDB.cost(10) == int(round(300.0 * pow(1.2, 9.0))))
	var mil: bool = true
	for L in range(2, 76):
		mil = mil and ((L % 5 == 0) == not CoreLevelDB.reqs_for(L).is_empty())
	t._check("P6 core level: requirements on every 5th level only (5 .. 75)", mil and CoreLevelDB.next_milestone(1) == 5 and CoreLevelDB.next_milestone(5) == 10 and CoreLevelDB.next_milestone(75) == 0)
	var sv: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	sv["coins"] = 1 << 40
	sv["core"]["lvl"] = 4
	var c0: int = int(sv["coins"])
	t._check("P6 core level: L4 -> L5 needs an Arsenal (try_level refuses, nothing spent)", not Cores.can_level(sv) and Cores.try_level(sv).is_empty() and int(sv["coins"]) == c0 and Cores.level(sv) == 4)
	var miss: Array = Cores.missing(sv)
	t._check("P6 core level: missing() names it (Arsenal Lv1, have 0)", miss.size() == 1 and String((miss[0] as Dictionary)["label"]) == "Arsenal Lv1" and int((miss[0] as Dictionary)["have"]) == 0 and Cores.why_level(sv) == "Core Lv5 needs: Arsenal Lv1")
	sv["outpost"]["relay_lvl"] = 8
	Outpost.place(sv, "arsenal", 7, 8, 0, OT0)
	t._check("P6 core level: an Arsenal (even unlinked counts by level) opens L5", Cores.can_level(sv) and not Cores.try_level(sv).is_empty() and Cores.level(sv) == 5)
	for k in 4:
		Cores.try_level(sv)
	t._check("P6 core level: L9 -> L10 needs Arsenal Lv3 + Core Theory I", Cores.level(sv) == 9 and Cores.missing(sv).size() == 2 and Cores.why_level(sv).contains("Arsenal Lv3") and Cores.why_level(sv).contains("Core Theory I"))
	for k in sv["outpost"]["buildings"].keys():
		if String(sv["outpost"]["buildings"][k]["id"]) == "arsenal":
			sv["outpost"]["buildings"][k]["lvl"] = 3
	t._check("P6 core level: one requirement met, one still missing", Cores.missing(sv).size() == 1 and String((Cores.missing(sv)[0] as Dictionary)["req"][0]) == "res")
	sv["research"]["lvls"]["core_theory"] = 1
	t._check("P6 core level: ... both met -> L10", not Cores.try_level(sv).is_empty() and Cores.level(sv) == 10)
	sv["core"]["lvl"] = 14
	sv["outpost"]["relay_lvl"] = 3
	var m15: Array = Cores.missing(sv)
	var kinds: Array = []
	for m in m15:
		kinds.append(String((m as Dictionary)["req"][0]))
	t._check("P6 core level: L15 needs a Reactor Lv3 and the Relay at Lv4", kinds.has("bld") and kinds.has("relay") and Cores.req_label(["relay", "relay", 4]) == "Core Relay Lv4")
	t._check("P6 core level: labels read naturally", Cores.req_label(["res", "core_theory", 3]) == "Core Theory III" and Cores.req_label(["bld", "bulwark_w", 4]) == "Bulwark Works Lv4")
	var top: Dictionary = BaseMeta.normalize(BaseMeta.default_save())
	top["core"]["lvl"] = 60
	t._check("P6 core level: max level still refuses (60, 75 with the ceiling node)", Cores.why_level(top) == "Max level")
