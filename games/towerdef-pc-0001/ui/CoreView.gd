extends RefCounted
## Core tab (V2). P1 interim: the one Core's permanent level, its stat sheet
## and the Level button. P4 grows it into Loadout (centre Weapon + Module
## ring) / Look (shell, colours, pattern) / Levels (P6: building + research
## requirements with jump chips). View only: buttons call Cores and hand the
## events to Main.meta_act().

const Cores := preload("res://Cores.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const Kit := preload("res://ui/Kit.gd")


static func level_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.get_center().x - 220.0, cr.end.y - 120.0, 440.0, 64.0)


static func build(m) -> void:
	var s: Dictionary = m.save
	var lv: int = Cores.level(s)
	var c: int = int(Cores.level_cost(lv)["coins"])
	var maxed: bool = lv >= Cores.max_level(s)
	var label: String = "MAX LEVEL" if maxed else "Level up  ·  %s coins" % Kit.fmt(float(c))
	Kit.btn(m, label, level_rect(m), func() -> void: m.meta_act(Cores.try_level(m.save)), level_tip(lv), Cores.can_level(s), Kit.GOLD, "CORE LEVEL", "cur_coin", 22)


static func level_tip(lv: int) -> String:
	var c: int = int(Cores.level_cost(lv)["coins"])
	return "Core Level %d -> %d: %s coins\nEach level: dmg x%.2f  ·  HP x%.2f  ·  regen and cash x%.2f" % [lv, lv + 1, Kit.fmt(float(c)), float(CoreDB.PER_LVL["dmg"]), float(CoreDB.PER_LVL["hp"]), float(CoreDB.PER_LVL["regen"])]


## Permanent sheet at level L (before run-time Enhancements, research and gear).
static func sheet(lv: int) -> Array:
	var d: Dictionary = CoreDB.get_def()
	return [
		["Damage", "%.1f" % (float(d["dmg"]) * CoreDB.lvl_mult("dmg", lv)), "in_dmg"],
		["Attack rate", "%.2f/s" % float(d["rate"]), "in_rate"],
		["Range", "%.1f cells" % float(d["range"]), "pk_optics"],
		["Max HP", "%d" % int(round(float(d["hp"]) * CoreDB.lvl_mult("hp", lv))), "in_hp"],
		["Regen", "%.2f/s" % (float(d["regen"]) * CoreDB.lvl_mult("regen", lv)), "in_hp"],
		["Armor", "%d" % int(d["armor"]), "pk_fort"],
		["Cash", "%.2f/s" % (float(d["cash"]) * CoreDB.lvl_mult("cash", lv)), "cur_cash"],
	]


static func draw(m, cr: Rect2) -> void:
	var s: Dictionary = m.save
	var lv: int = Cores.level(s)
	var c: Vector2 = Vector2(cr.position.x + cr.size.x * 0.32, cr.position.y + cr.size.y * 0.45)
	for k in 4:
		var a: float = m.t_anim * (0.25 + 0.1 * float(k)) + float(k) * 1.4
		m.draw_arc(c, 150.0 + 26.0 * float(k), a, a + 2.0, 40, Color(Kit.GEM, 0.12 + 0.05 * float(k)), 3.0)
	Kit.icon(m, "core_bastion", Rect2(c - Vector2(110, 110), Vector2(220, 220)))
	Kit.t(m, "THE CORE", Vector2(c.x, cr.position.y + 60), 34, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 600.0)
	Kit.t(m, "Level %d / %d" % [lv, Cores.max_level(s)], Vector2(c.x, c.y + 190), 26, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 400.0)
	var px: float = cr.position.x + cr.size.x * 0.6
	var pw: float = minf(560.0, cr.end.x - px - 30.0)
	var pr: Rect2 = Rect2(px, cr.position.y + 90, pw, 420)
	Kit.panel(m, pr, Kit.EDGE, Kit.PANEL)
	Kit.head(m, "PERMANENT SHEET", pr.position + Vector2(20, 34), pw - 40)
	var rows: Array = sheet(lv)
	for k in rows.size():
		var rw: Array = rows[k]
		var y: float = pr.position.y + 84.0 + float(k) * 44.0
		Kit.icon(m, String(rw[2]), Rect2(pr.position.x + 20, y - 24, 30, 30))
		Kit.row(m, String(rw[0]), String(rw[1]), Vector2(pr.position.x + 60, y), pw - 84)
	Kit.wrap(m, "Weapon and Module slots arrive with the Forge. Research, Outpost buildings and in-run Enhancements multiply this sheet.", Vector2(pr.position.x + 20, pr.end.y + 16), 15, Kit.DIM, pw - 40, 3)
