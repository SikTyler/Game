extends RefCounted
## Core tab (V2 P4d): the player's one Core, three sub-tabs.
##   LOADOUT  the Core drawn with its turret and Module sockets; click the
##            centre (key core:weapon) or a socket (core:sock:<k>) and pick
##            from the inventory on the right (core:pick:<uid>, core:unsock);
##            the summed loadout bonuses below the Core
##   LOOK     shell (core:shell:<k>), inner trim (core:trim:<k>), pattern
##            (core:pat:<k>) and three colours (core:col:<p|s|g>:<hex>)
##   LEVELS   the permanent level and sheet (P6 adds building / research
##            requirements with jump chips)
## The Level button (key CORE LEVEL) shows on every sub-tab. View only:
## buttons call Cores / Gear and hand the events to Main.meta_act().

const Cores := preload("res://Cores.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const Gear := preload("res://Gear.gd")
const GearVis := preload("res://GearVis.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const ModuleDB := preload("res://data/ModuleDB.gd")
const Kit := preload("res://ui/Kit.gd")

const TABS: Array = [["loadout", "Loadout", "core_open", "The Weapon and Module sockets"], ["look", "Look", "", "Shell, trim, pattern and colours"], ["levels", "Levels", "", "Permanent Core level and sheet"]]
const ROWS: int = 9
const SWATCHES: Array = ["1b2440", "2a1640", "103a3a", "3a1010", "202020", "e8f0ff", "39e6ff", "ff3ea5", "ffd34d", "4ade80", "b26bff", "ff8a3d"]
const R_CORE: float = 150.0


# ------------------------------------------------------------------ layout

static func core_center(m) -> Vector2:
	var cr: Rect2 = m.content_rect()
	return Vector2(cr.position.x + cr.size.x * 0.27, cr.position.y + 300.0)


static func level_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var c: Vector2 = core_center(m)
	return Rect2(c.x - 220.0, cr.end.y - 72.0, 440.0, 58.0)


static func panel_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var x: float = cr.position.x + cr.size.x * 0.54
	return Rect2(x, cr.position.y + 14.0, cr.end.x - x - 20.0, cr.size.y - 28.0)


static func sock_pos(m, k: int, n: int) -> Vector2:
	return core_center(m) + Vector2.from_angle(-PI * 0.5 + TAU * float(k) / float(maxi(1, n))) * R_CORE


static func _row_rect(m, k: int) -> Rect2:
	var p: Rect2 = panel_rect(m)
	return Rect2(p.position.x + 16.0, p.position.y + 90.0 + float(k) * 64.0, p.size.x - 32.0, 58.0)


# ------------------------------------------------------------------ build

static func build(m) -> void:
	var s: Dictionary = m.save
	var cr: Rect2 = m.content_rect()
	Kit.tabs(m, Rect2(cr.position.x + 20.0, cr.position.y + 14.0, 520.0, 48.0), TABS, String(m.core_tab), func(id: String) -> void:
		m.core_tab = id
		m.core_page = 0
		m._rebuild_ui(), "CORETAB ", [], 17)
	var lv: int = Cores.level(s)
	var c: int = int(Cores.level_cost(lv)["coins"])
	var maxed: bool = lv >= Cores.max_level(s)
	var label: String = "MAX LEVEL" if maxed else "Level up  ·  %s coins" % Kit.fmt(float(c))
	Kit.btn(m, label, level_rect(m), func() -> void: m.meta_act(Cores.try_level(m.save)), level_tip(lv), Cores.can_level(s), Kit.GOLD, "CORE LEVEL", "cur_coin", 22)
	match String(m.core_tab):
		"loadout":
			_build_loadout(m, s)
		"look":
			_build_look(m, s)


static func level_tip(lv: int) -> String:
	var c: int = int(Cores.level_cost(lv)["coins"])
	var nxt: String = ""
	for k in Gear.SOCKET_LVLS.size():
		if int(Gear.SOCKET_LVLS[k]) > lv:
			nxt = "\nNext Module socket at Core Lv%d" % int(Gear.SOCKET_LVLS[k])
			break
	return "Core Level %d -> %d: %s coins\nEach level: dmg x%.2f  ·  HP x%.2f  ·  regen and cash x%.2f%s" % [lv, lv + 1, Kit.fmt(float(c)), float(CoreDB.PER_LVL["dmg"]), float(CoreDB.PER_LVL["hp"]), float(CoreDB.PER_LVL["regen"]), nxt]


static func _build_loadout(m, s: Dictionary) -> void:
	var c: Vector2 = core_center(m)
	var w: Dictionary = Gear.weapon(s)
	Kit.hit(m, Rect2(c - Vector2(66, 66), Vector2(132, 132)), func() -> void: _pick_slot(m, -1), "Weapon slot: %s\nClick to swap the Weapon" % String(w.get("name", "")), "core:weapon", true, Kit.CYAN)
	var n: int = Gear.sockets_for(Cores.level(s))
	var so: Array = (Gear.block(s)["equipped"] as Dictionary)["sockets"]
	for k in n:
		var kk: int = k
		var u: int = int(so[k]) if k < so.size() else 0
		var it: Dictionary = Gear.item(s, u)
		Kit.hit(m, Rect2(sock_pos(m, k, n) - Vector2(32, 32), Vector2(64, 64)), func() -> void: _pick_slot(m, kk),
			"Socket %d: %s\nClick to choose a Module" % [k + 1, "empty" if it.is_empty() else String(it["name"])], "core:sock:%d" % k, true, Kit.GOLD)
	# picker
	var lst: Array = _candidates(m, s)
	var p0: int = int(m.core_page) * ROWS
	var slot: int = int(m.core_sock)
	var rows: int = 0
	if slot >= 0 and slot < so.size() and int(so[slot]) != 0:
		Kit.btn(m, "EMPTY THIS SOCKET", _row_rect(m, 0), func() -> void: m.meta_act(Gear.unequip(m.save, slot)), "Take the Module out of socket %d" % (slot + 1), true, Kit.ENEMY, "core:unsock", "", 16)
		rows = 1
	for k in mini(ROWS - rows, lst.size() - p0):
		var uid: int = int(lst[p0 + k])
		var it2: Dictionary = Gear.item(s, uid)
		Kit.hit(m, _row_rect(m, k + rows), func() -> void: _equip(m, uid), _row_tip(it2), "core:pick:%d" % uid, not Gear.is_equipped(s, uid) or String(it2["kind"]) == "module", Kit.rarity_col(String(it2["rar"])))
	var p: Rect2 = panel_rect(m)
	var pages: int = maxi(1, int(ceil(float(lst.size()) / float(ROWS - rows))))
	Kit.btn(m, "<", Rect2(p.position.x + 16.0, p.end.y - 54.0, 64.0, 44.0), func() -> void:
		m.core_page = int(m.core_page) - 1
		m._rebuild_ui(), "Previous page", int(m.core_page) > 0, Kit.NEUTRAL, "core:page:-", "", 20)
	Kit.btn(m, ">", Rect2(p.end.x - 80.0, p.end.y - 54.0, 64.0, 44.0), func() -> void:
		m.core_page = int(m.core_page) + 1
		m._rebuild_ui(), "Next page", int(m.core_page) < pages - 1, Kit.NEUTRAL, "core:page:+", "", 20)


static func _pick_slot(m, k: int) -> void:
	m.core_sock = k
	m.core_page = 0
	m._rebuild_ui()


static func _equip(m, uid: int) -> void:
	var it: Dictionary = Gear.item(m.save, uid)
	m.meta_act(Gear.equip(m.save, uid, int(m.core_sock) if String(it.get("kind", "")) == "module" else -1))


## The items the selected slot can take: weapons (best est. DPS first) or
## modules (best rarity first).
static func _candidates(m, s: Dictionary) -> Array:
	var kind: String = "weapon" if int(m.core_sock) < 0 else "module"
	var lst: Array = Gear.uids(s, kind)
	if kind == "weapon":
		lst.sort_custom(func(a: Variant, b: Variant) -> bool: return Gear.est_dps(Gear.item(s, int(a))) > Gear.est_dps(Gear.item(s, int(b))))
	else:
		lst.sort_custom(func(a: Variant, b: Variant) -> bool:
			var ra: int = RarityDB.rank(String(Gear.item(s, int(a))["rar"]))
			var rb: int = RarityDB.rank(String(Gear.item(s, int(b))["rar"]))
			return ra > rb or (ra == rb and int(a) > int(b)))
	return lst


static func _row_tip(it: Dictionary) -> String:
	var lines: Array = ["%s  (%s, Lv %d)" % [String(it["name"]), String(RarityDB.get_def(String(it["rar"]))["name"]), int(it["lvl"])]]
	lines.append_array(Gear.fx_lines(Gear.item_fx(it)))
	return "\n".join(lines)


static func _build_look(m, s: Dictionary) -> void:
	var p: Rect2 = panel_rect(m)
	var look: Dictionary = Cores.look(s)
	var x0: float = p.position.x + 16.0
	var rows: Array = [["shell", Cores.SHELLS, 120.0], ["trim", Cores.TRIMS, 214.0], ["pat", Cores.LOOK_PATTERNS, 308.0]]
	for rw in rows:
		var key: String = String(rw[0])
		for k in int(rw[1]):
			var kk: int = k
			var on: bool = int(look.get(key, 0)) == k
			Kit.btn(m, str(k + 1), Rect2(x0 + float(k) * 62.0, p.position.y + float(rw[2]), 56.0, 46.0), func() -> void: m.meta_act(Cores.set_look(m.save, key, kk)),
				"%s %d" % [{"shell": "Shell", "trim": "Inner trim", "pat": "Pattern"}[key], k + 1], true, Kit.CYAN if on else Kit.NEUTRAL, "core:%s:%d" % [key, k], "", 16)
	for j in 3:
		var slot: String = ["p", "s", "g"][j]
		for k in SWATCHES.size():
			var hex: String = String(SWATCHES[k])
			Kit.hit(m, _swatch_rect(m, j, k), func() -> void: m.meta_act(Cores.set_look(m.save, slot, hex)), "%s colour #%s" % [["Primary", "Secondary", "Glow"][j], hex], "core:col:%s:%s" % [slot, hex], true, Color("#" + hex))


static func _swatch_rect(m, j: int, k: int) -> Rect2:
	var p: Rect2 = panel_rect(m)
	return Rect2(p.position.x + 16.0 + float(k) * 52.0, p.position.y + 420.0 + float(j) * 94.0, 46.0, 46.0)


# ------------------------------------------------------------------ draw

static func draw(m, cr: Rect2) -> void:
	var s: Dictionary = m.save
	var lv: int = Cores.level(s)
	var c: Vector2 = core_center(m)
	for k in 4:
		var a: float = m.t_anim * (0.25 + 0.1 * float(k)) + float(k) * 1.4
		m.draw_arc(c, R_CORE + 40.0 + 22.0 * float(k), a, a + 2.0, 40, Color(Kit.GEM, 0.10 + 0.04 * float(k)), 3.0)
	Kit.glow(m, c, R_CORE * 1.9, Kit.CYAN, 0.16 + 0.05 * sin(m.t_anim * 1.7))
	var n: int = Gear.sockets_for(lv)
	var mods: Array = []
	var so: Array = (Gear.block(s)["equipped"] as Dictionary)["sockets"]
	for k in n:
		mods.append(Gear.item(s, int(so[k])) if k < so.size() else {})
	GearVis.draw_core(m, Cores.look(s), mods, Gear.weapon(s), c, R_CORE, -PI * 0.5 + 0.25 * sin(m.t_anim * 0.6), m.t_anim)
	Kit.th(m, "THE CORE  ·  Lv %d / %d" % [lv, Cores.max_level(s)], Vector2(c.x, c.y + R_CORE + 64.0), 24, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 600.0)
	match String(m.core_tab):
		"loadout":
			_draw_loadout(m, s, c, n)
		"look":
			_draw_look(m, s)
		_:
			_draw_levels(m, s, lv)


static func _draw_loadout(m, s: Dictionary, c: Vector2, n: int) -> void:
	# selection ring
	var slot: int = int(m.core_sock)
	var sp: Vector2 = c if slot < 0 else sock_pos(m, slot, n)
	m.draw_arc(sp, 70.0 if slot < 0 else 36.0, 0.0, TAU, 40, Color(Kit.CYAN, 0.6 + 0.3 * sin(m.t_anim * 4.0)), 3.0)
	var nxt: int = -1
	for k in Gear.SOCKET_LVLS.size():
		if int(Gear.SOCKET_LVLS[k]) > Cores.level(s):
			nxt = int(Gear.SOCKET_LVLS[k])
			break
	if nxt > 0:
		Kit.t(m, "%d sockets open  ·  the next at Core Lv%d" % [n, nxt], Vector2(c.x, c.y + R_CORE + 90.0), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, 500.0)
	# loadout bonuses
	var cr: Rect2 = m.content_rect()
	var ln: Array = Gear.fx_lines(Gear.run_fx(s))
	var bx: float = cr.position.x + 40.0
	var by: float = c.y + R_CORE + 116.0
	var bw: float = cr.size.x * 0.5 - 60.0
	Kit.head(m, "LOADOUT BONUSES", Vector2(bx, by), bw)
	if ln.is_empty():
		Kit.t(m, "None yet: forge Weapons and Modules in the Forge (J)", Vector2(bx, by + 34), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, bw)
	var half: int = int(ceil(float(ln.size()) / 2.0))
	for k in ln.size():
		var col: int = k / maxi(1, half)
		var row: int = k % maxi(1, half)
		var yy: float = by + 34.0 + float(row) * 22.0
		if yy > level_rect(m).position.y - 10.0:
			continue
		Kit.t(m, String(ln[k]), Vector2(bx + float(col) * bw * 0.5, yy), 15, Kit.ENEMY if String(ln[k]).begins_with("-") else Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, bw * 0.5 - 10.0)
	# picker
	var p: Rect2 = panel_rect(m)
	Kit.panel(m, p, Kit.EDGE, Kit.PANEL)
	Kit.th(m, ("WEAPON  ·  pick the Core's Weapon" if slot < 0 else "SOCKET %d  ·  pick a Module" % (slot + 1)), p.position + Vector2(18, 40), 20, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, p.size.x - 36.0)
	var lst: Array = _candidates(m, s)
	var so: Array = (Gear.block(s)["equipped"] as Dictionary)["sockets"]
	var rows: int = 1 if slot >= 0 and slot < so.size() and int(so[slot]) != 0 else 0
	var p0: int = int(m.core_page) * ROWS
	if lst.is_empty():
		Kit.t(m, "No %s yet - forge one in the Forge" % ("Weapons" if slot < 0 else "Modules"), _row_rect(m, rows).position + Vector2(8, 34), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, p.size.x - 40.0)
	for k in mini(ROWS - rows, lst.size() - p0):
		var it: Dictionary = Gear.item(s, int(lst[p0 + k]))
		var r: Rect2 = _row_rect(m, k + rows)
		var eq: bool = Gear.is_equipped(s, int(it["uid"]))
		Kit.card_frame(m, r, String(it["rar"]), m.t_anim, eq)
		if String(it["kind"]) == "weapon":
			GearVis.draw_weapon(m, it, Vector2(r.position.x + 60.0, r.get_center().y), 96.0, 0.0, m.t_anim)
		else:
			GearVis.draw_module(m, it, Vector2(r.position.x + 40.0, r.get_center().y), 40.0, m.t_anim)
		Kit.th(m, String(it["name"]), Vector2(r.position.x + 124.0, r.position.y + 26.0), 17, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 250.0)
		var sub: String = "%s  ·  Lv %d" % [String(RarityDB.get_def(String(it["rar"]))["name"]), int(it["lvl"])]
		if String(it["kind"]) == "weapon":
			sub += "  ·  DPS %.1f" % Gear.est_dps(it)
		else:
			var fl: Array = Gear.fx_lines(Gear.module_fx(it))
			if not fl.is_empty():
				sub += "  ·  " + String(fl[0])
		Kit.t(m, sub, Vector2(r.position.x + 124.0, r.position.y + 48.0), 14, Kit.rarity_col(String(it["rar"])), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 140.0)
		if eq:
			Kit.th(m, "EQUIPPED", Vector2(r.end.x - 12.0, r.position.y + 26.0), 14, Kit.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)


static func _draw_look(m, s: Dictionary) -> void:
	var p: Rect2 = panel_rect(m)
	Kit.panel(m, p, Kit.EDGE, Kit.PANEL)
	Kit.th(m, "CORE LOOK", p.position + Vector2(18, 40), 22, Kit.TEXT)
	Kit.t(m, "Free to change any time. Your Core looks like this in every run.", p.position + Vector2(18, 70), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, p.size.x - 36.0)
	for rw in [["SHELL", 110.0], ["INNER TRIM", 204.0], ["PATTERN", 298.0]]:
		Kit.th(m, String(rw[0]), Vector2(p.position.x + 18, p.position.y + float(rw[1])), 15, Kit.DIM)
	var look: Dictionary = Cores.look(s)
	for j in 3:
		var slot: String = ["p", "s", "g"][j]
		Kit.th(m, ["PRIMARY", "SECONDARY", "GLOW"][j], Vector2(p.position.x + 18, _swatch_rect(m, j, 0).position.y - 10.0), 15, Kit.DIM)
		for k in SWATCHES.size():
			var r: Rect2 = _swatch_rect(m, j, k)
			m.draw_rect(r, Color("#" + String(SWATCHES[k])))
			var on: bool = String(look.get(slot, "")) == String(SWATCHES[k])
			m.draw_rect(r.grow(2.0 if on else 0.0), Color.WHITE if on else Kit.EDGE2, false, 3.0 if on else 1.0)


static func _draw_levels(m, s: Dictionary, lv: int) -> void:
	var p: Rect2 = panel_rect(m)
	Kit.panel(m, p, Kit.EDGE, Kit.PANEL)
	Kit.head(m, "PERMANENT SHEET", p.position + Vector2(20, 40), p.size.x - 40.0)
	var rows: Array = sheet(s, lv)
	for k in rows.size():
		var rw: Array = rows[k]
		var y: float = p.position.y + 92.0 + float(k) * 46.0
		Kit.icon(m, String(rw[2]), Rect2(p.position.x + 20, y - 24, 30, 30))
		Kit.row(m, String(rw[0]), String(rw[1]), Vector2(p.position.x + 60, y), p.size.x - 84.0)
	Kit.wrap(m, "Each level: dmg x%.2f, HP x%.2f, regen and cash x%.2f. Module sockets open at Core Lv 1 (2), 5, 10, 18, 28, 40 and 55. Research, Outpost buildings, gear and in-run Enhancements multiply this sheet." % [float(CoreDB.PER_LVL["dmg"]), float(CoreDB.PER_LVL["hp"]), float(CoreDB.PER_LVL["regen"])], Vector2(p.position.x + 20, p.position.y + 92.0 + float(rows.size()) * 46.0), 15, Kit.DIM, p.size.x - 40.0, 4)


## Permanent sheet at level L with the equipped Weapon (before research,
## buildings, in-run Enhancements and the loadout's fx).
static func sheet(s: Dictionary, lv: int) -> Array:
	var d: Dictionary = CoreDB.get_def()
	var ws: Dictionary = Gear.weapon_sheet(s)
	return [
		["Weapon", String(ws["name"]), "core_open"],
		["Damage", "%.1f" % (float(ws["dmg"]) * CoreDB.lvl_mult("dmg", lv)), "in_dmg"],
		["Attack rate", "%.2f/s" % float(ws["rate"]), "in_rate"],
		["Range", "%.1f cells" % float(ws["range"]), "pk_optics"],
		["Max HP", "%d" % int(round(float(d["hp"]) * CoreDB.lvl_mult("hp", lv))), "in_hp"],
		["Regen", "%.2f/s" % (float(d["regen"]) * CoreDB.lvl_mult("regen", lv)), "in_hp"],
		["Armor", "%d" % int(d["armor"]), "pk_fort"],
		["Cash", "%.2f/s" % (float(d["cash"]) * CoreDB.lvl_mult("cash", lv)), "cur_cash"],
		["Module sockets", "%d" % Gear.sockets_for(lv), "icon_gear"],
	]
