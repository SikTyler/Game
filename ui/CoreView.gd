extends RefCounted
## Core Look and Levels panels (V2 P4d; V3: hosted by ArmoryView's CORE
## tab, which owns the Core's parts). Each panel draws into the rect it is
## given.
##   LOOK     pattern (core:pat:<k>) and three colours (core:col:<p|s|g>:<hex>);
##            the Core and Weapon shapes come from their parts
##   LEVELS   the permanent level, its next milestone's requirement chips
##            (jump to what's missing) and the permanent sheet
## View only: buttons call Cores and hand the events to Main.meta_act().

const Cores := preload("res://Cores.gd")
const CoreLevelDB := preload("res://data/CoreLevelDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const Parts := preload("res://Parts.gd")
const Kit := preload("res://ui/Kit.gd")

const SWATCHES: Array = ["1b2440", "2a1640", "103a3a", "3a1010", "202020", "e8f0ff", "39e6ff", "ff3ea5", "ffd34d", "4ade80", "b26bff", "ff8a3d"]


## Requirements of the next milestone level (shown as chips).
static func milestone_reqs(s: Dictionary) -> Array:
	var ms: int = CoreLevelDB.next_milestone(Cores.level(s))
	return CoreLevelDB.reqs_for(ms) if ms > 0 and ms <= Cores.max_level(s) else []


static func level_tip(lv: int) -> String:
	var c: int = int(Cores.level_cost(lv)["coins"])
	return "Core Level %d -> %d: %s coins\nEach level: dmg x%.2f  ·  HP x%.2f  ·  regen and cash x%.2f\nSlots come from parts: a rarer Receiver / Heart opens more" % [lv, lv + 1, Kit.fmt(float(c)), float(CoreDB.PER_LVL["dmg"]), float(CoreDB.PER_LVL["hp"]), float(CoreDB.PER_LVL["regen"])]


# ------------------------------------------------------------------ look

static func _swatch_rect(p: Rect2, j: int, k: int) -> Rect2:
	var w: float = minf(52.0, (p.size.x - 32.0) / float(SWATCHES.size()))
	return Rect2(p.position.x + 16.0 + float(k) * w, p.position.y + 230.0 + float(j) * 94.0, w - 6.0, 46.0)


static func build_look(m, s: Dictionary, p: Rect2) -> void:
	var look: Dictionary = Cores.look(s)
	for k in int(Cores.LOOK_PATTERNS):
		var kk: int = k
		var on: bool = int(look.get("pat", 0)) == k
		Kit.btn(m, str(k + 1), Rect2(p.position.x + 16.0 + float(k) * 62.0, p.position.y + 120.0, 56.0, 46.0), func() -> void: m.meta_act(Cores.set_look(m.save, "pat", kk)),
			"Pattern %d" % (k + 1), true, Kit.CYAN if on else Kit.NEUTRAL, "core:pat:%d" % k, "", 16)
	for j in 3:
		var slot: String = ["p", "s", "g"][j]
		for k in SWATCHES.size():
			var hex: String = String(SWATCHES[k])
			Kit.hit(m, _swatch_rect(p, j, k), func() -> void: m.meta_act(Cores.set_look(m.save, slot, hex)), "%s colour #%s" % [["Primary", "Secondary", "Glow"][j], hex], "core:col:%s:%s" % [slot, hex], true, Color("#" + hex))


static func draw_look(m, s: Dictionary, p: Rect2) -> void:
	Kit.panel(m, p, Kit.EDGE, Kit.PANEL)
	Kit.th(m, "CORE LOOK", p.position + Vector2(18, 40), 22, Kit.TEXT)
	Kit.wrap(m, "Free to change any time. The shapes come from the installed parts - every Plating, Generator, Barrel and Scope shows - and these colours paint them, in every run and on the Outpost.", p.position + Vector2(18, 56), 15, Kit.DIM, p.size.x - 36.0, 2)
	Kit.th(m, "PATTERN", Vector2(p.position.x + 18, p.position.y + 110.0), 15, Kit.DIM)
	var look: Dictionary = Cores.look(s)
	for j in 3:
		var slot: String = ["p", "s", "g"][j]
		Kit.th(m, ["PRIMARY", "SECONDARY", "GLOW"][j], Vector2(p.position.x + 18, _swatch_rect(p, j, 0).position.y - 10.0), 15, Kit.DIM)
		for k in SWATCHES.size():
			var r: Rect2 = _swatch_rect(p, j, k)
			m.draw_rect(r, Color("#" + String(SWATCHES[k])))
			var on: bool = String(look.get(slot, "")) == String(SWATCHES[k])
			m.draw_rect(r.grow(2.0 if on else 0.0), Color.WHITE if on else Kit.EDGE2, false, 3.0 if on else 1.0)


# ------------------------------------------------------------------ levels

static func chip_rect(p: Rect2, k: int, n: int) -> Rect2:
	var w: float = minf(216.0, (p.size.x - 32.0 - float(n - 1) * 8.0) / float(maxi(1, n)))
	return Rect2(p.position.x + 16.0 + float(k) * (w + 8.0), p.position.y + 96.0, w, 44.0)


static func build_levels(m, s: Dictionary, p: Rect2) -> void:
	var reqs: Array = milestone_reqs(s)
	for k in reqs.size():
		var rq: Array = reqs[k]
		var met: bool = Cores.req_have(s, rq) >= int(rq[2])
		var kind: String = String(rq[0])
		var rid: String = String(rq[1])
		Kit.req_chip(m, chip_rect(p, k, reqs.size()), kind, rid, Cores.req_label(rq), met, func() -> void: m.jump_to(kind, rid),
			("%s - done" % Cores.req_label(rq)) if met else ("%s (have %d) - click to go there" % [Cores.req_label(rq), Cores.req_have(s, rq)]), "")


static func draw_levels(m, s: Dictionary, p: Rect2) -> void:
	Kit.panel(m, p, Kit.EDGE, Kit.PANEL)
	var lv: int = Cores.level(s)
	Kit.th(m, "THE CORE  ·  Lv %d / %d" % [lv, Cores.max_level(s)], p.position + Vector2(20, 40), 22, Kit.GOLD)
	var reqs: Array = milestone_reqs(s)
	if not reqs.is_empty():
		Kit.th(m, "CORE Lv%d NEEDS" % CoreLevelDB.next_milestone(lv), Vector2(p.position.x + 20, p.position.y + 84.0), 15, Kit.DIM)
	var y0: float = p.position.y + (172.0 if not reqs.is_empty() else 92.0)
	Kit.head(m, "PERMANENT SHEET (before parts, research and run bonuses)", Vector2(p.position.x + 20, y0), p.size.x - 40.0)
	var rows: Array = sheet(s, lv)
	for k in rows.size():
		var rw: Array = rows[k]
		var y: float = y0 + 52.0 + float(k) * 44.0
		Kit.icon(m, String(rw[2]), Rect2(p.position.x + 20, y - 24, 30, 30))
		Kit.row(m, String(rw[0]), String(rw[1]), Vector2(p.position.x + 60, y), p.size.x - 84.0)
	Kit.wrap(m, "Each level: dmg x%.2f, HP x%.2f, regen and cash x%.2f. The Level button sits under the Core. Parts, research, Outpost buildings and in-run Enhancements multiply this sheet." % [float(CoreDB.PER_LVL["dmg"]), float(CoreDB.PER_LVL["hp"]), float(CoreDB.PER_LVL["regen"])], Vector2(p.position.x + 20, y0 + 52.0 + float(rows.size()) * 44.0), 15, Kit.DIM, p.size.x - 40.0, 4)


## Permanent sheet at level L with the installed parts' chassis and first
## barrel (before research, buildings, in-run Enhancements and part fx).
static func sheet(s: Dictionary, lv: int) -> Array:
	var cd: Dictionary = Parts.core_def(s)
	return [
		["Weapon", String(cd["attack_name"]), "core_open"],
		["Damage", "%.1f" % (float(cd["dmg"]) * CoreDB.lvl_mult("dmg", lv)), "in_dmg"],
		["Attack rate", "%.2f/s" % float(cd["rate"]), "in_rate"],
		["Range", "%.1f cells" % float(cd["range"]), "pk_optics"],
		["Barrels", "%d" % (cd["barrels"] as Array).size(), "core_open"],
		["Max HP", "%d" % int(round(float(cd["hp"]) * CoreDB.lvl_mult("hp", lv))), "in_hp"],
		["Regen", "%.2f/s" % (float(cd["regen"]) * CoreDB.lvl_mult("regen", lv)), "in_hp"],
		["Armor", "%d" % int(cd["armor"]), "pk_fort"],
		["Cash", "%.2f/s" % (float(cd["cash"]) * CoreDB.lvl_mult("cash", lv)), "cur_cash"],
	]
