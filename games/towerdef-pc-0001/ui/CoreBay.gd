extends RefCounted
## Core Bay (REDESIGN_SPEC §5): the Core list (locked Cores show their unlock
## condition), the selected Core opened in its exploded view with the part
## slots around it (drag a part onto a slot, or select + Equip), loadout
## preset tabs 1-4, set progress badges, the installed totals, the inventory
## with slot / rarity / set filters, and the part detail with green "+" and
## red "-" lines, a compare against the installed part, and level-up /
## lock / salvage. View only: every action calls Cores / Parts.

const Cores := preload("res://Cores.gd")
const Parts := preload("res://Parts.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const PartDB := preload("res://data/PartDB.gd")
const SetDB := preload("res://data/SetDB.gd")
const Kit := preload("res://ui/Kit.gd")

const LIST_W: float = 330.0
const INV_W: float = 560.0
const CELL: float = 76.0
const SLOT_R: float = 46.0
const SLOT_ICON: Dictionary = {"F": "slot_frame", "B": "slot_barrel", "C": "slot_capacitor", "E": "slot_engine", "S": "slot_set"}
const SLOT_FILTERS: Array = ["", "F", "B", "C", "E"]
const RAR_FILTERS: Array = ["", "common", "rare", "epic", "legendary", "special"]
const RANK: Dictionary = {"special": 0, "legendary": 1, "epic": 2, "rare": 3, "common": 4}


static func _core(m) -> String:
	if m.bay_core == "" or not CoreDB.has(m.bay_core):
		m.bay_core = Cores.active(m.save)
	return m.bay_core


static func list_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.position.x + 16, cr.position.y + 16, LIST_W, cr.size.y - 32)


static func inv_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.end.x - INV_W - 16, cr.position.y + 16, INV_W, cr.size.y - 32)


static func view_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var l: Rect2 = list_rect(m)
	var i: Rect2 = inv_rect(m)
	return Rect2(l.end.x + 16, cr.position.y + 16, i.position.x - l.end.x - 32, cr.size.y - 32)


static func core_card(m, k: int) -> Rect2:
	var l: Rect2 = list_rect(m)
	var h: float = minf(150.0, (l.size.y - 110.0) / float(CoreDB.IDS.size()) - 10.0)
	return Rect2(l.position.x + 12, l.position.y + 48 + float(k) * (h + 10.0), l.size.x - 24, h)


## Exploded-view centre and the screen position of slot k.
static func hub_center(m) -> Vector2:
	var v: Rect2 = view_rect(m)
	return Vector2(v.get_center().x, v.position.y + 150.0 + orbit(m))


static func orbit(m) -> float:
	var v: Rect2 = view_rect(m)
	return minf(minf(v.size.x * 0.5 - SLOT_R - 20.0, 220.0), v.size.y * 0.24)


static func slot_pos(m, k: int) -> Vector2:
	var a: float = -PI * 0.5 + TAU * float(k) / float(Parts.N_SLOTS)
	return hub_center(m) + Vector2.from_angle(a) * orbit(m)


static func slot_at(m, p: Vector2) -> int:
	for k in Parts.N_SLOTS:
		if slot_pos(m, k).distance_to(p) <= SLOT_R + 6.0:
			return k
	return -1


static func _inv_ids(m) -> Array:
	var s: Dictionary = m.save
	var its: Dictionary = Parts.items(s)
	var out: Array = []
	for uid in its.keys():
		var it: Dictionary = its[uid]
		var id: String = String(it["id"])
		var f: Dictionary = m.bay_filter
		if String(f["slot"]) != "" and PartDB.slot_of(id) != String(f["slot"]):
			continue
		if String(f["rarity"]) != "" and PartDB.rarity_of(id) != String(f["rarity"]):
			continue
		if String(f["set"]) != "" and PartDB.set_of(id) != String(f["set"]):
			continue
		out.append(String(uid))
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ia: String = String(its[a]["id"])
		var ib: String = String(its[b]["id"])
		var ra: int = int(RANK.get(PartDB.rarity_of(ia), 9))
		var rb: int = int(RANK.get(PartDB.rarity_of(ib), 9))
		if ra != rb:
			return ra < rb
		if PartDB.slot_of(ia) != PartDB.slot_of(ib):
			return PartDB.slot_of(ia) < PartDB.slot_of(ib)
		return ia < ib)
	return out


static func inv_grid(m) -> Rect2:
	var i: Rect2 = inv_rect(m)
	return Rect2(i.position.x + 12, i.position.y + 176, i.size.x - 24, maxf(CELL, i.size.y * 0.5 - 150.0))


static func per_page(m) -> int:
	var g: Rect2 = inv_grid(m)
	var cols: int = int(floor((g.size.x + 6.0) / (CELL + 6.0)))
	var rows: int = int(floor((g.size.y + 6.0) / (CELL + 6.0)))
	return maxi(1, cols * rows)


static func inv_cell(m, j: int) -> Rect2:
	var g: Rect2 = inv_grid(m)
	var cols: int = int(floor((g.size.x + 6.0) / (CELL + 6.0)))
	return Rect2(g.position.x + float(j % cols) * (CELL + 6.0), g.position.y + float(j / cols) * (CELL + 6.0), CELL, CELL)


static func detail_rect(m) -> Rect2:
	var i: Rect2 = inv_rect(m)
	var g: Rect2 = inv_grid(m)
	return Rect2(i.position.x + 12, g.end.y + 50, i.size.x - 24, i.end.y - g.end.y - 62)


## Best slot for a part: an open, fitting, empty slot first; else the first
## fitting open slot (replaces).
static func target_slot(m, uid: String) -> int:
	var s: Dictionary = m.save
	var core: String = _core(m)
	var lv: int = Cores.level(s, core)
	var row: Array = Parts.preset(s, core)
	var first: int = -1
	for k in Parts.N_SLOTS:
		if Parts.slot_open(lv, k) and Parts.fits(s, uid, k):
			if String(row[k]) == "":
				return k
			if first < 0:
				first = k
	return first


static func installed_slot(m, uid: String) -> int:
	var row: Array = Parts.preset(m.save, _core(m))
	for k in row.size():
		if String(row[k]) == uid:
			return k
	return -1


# ===================================================================== build
static func build(m) -> void:
	var s: Dictionary = m.save
	var core: String = _core(m)
	var owned: bool = Cores.is_owned(s, core)
	# core list
	for k in CoreDB.IDS.size():
		var id: String = CoreDB.IDS[k]
		var d: Dictionary = CoreDB.get_def(id)
		var tip: String = "%s Core — %s\n%s" % [String(d["name"]), String(d["attack_name"]), String(d["attack_desc"])]
		if not Cores.is_owned(s, id):
			tip += "\nLocked: " + String(CoreDB.UNLOCK_TEXT.get(id, ""))
		Kit.hit(m, core_card(m, k), func() -> void: m.bay_core = id; m.bay_part = ""; m._rebuild_ui(), tip, "BAY CORE " + id)
	var l: Rect2 = list_rect(m)
	var bw: float = (l.size.x - 36.0) * 0.5
	var lc: Dictionary = Cores.level_cost(Cores.level(s, core))
	Kit.btn(m, "Make active", Rect2(l.position.x + 12, l.end.y - 56, bw, 46), func() -> void: m.meta_act(Cores.select(m.save, core)), "Fight with this Core in your next run", owned and Cores.active(s) != core, Kit.RUST, "BAY ACTIVE")
	var lvl_tip: String = "Level %d -> %d: %s coins%s. Each level: dmg x1.06, HP x1.05, regen and cash x1.04; slots open at L5 / 12 / 20 / 30 (Set slot L40)." % [Cores.level(s, core), Cores.level(s, core) + 1, Kit.fmt(float(lc["coins"])), (" + %d Core Cores" % int(lc["core_cores"])) if int(lc["core_cores"]) > 0 else ""]
	Kit.btn(m, "Level up [%s]" % Kit.hint(m, "upgrade"), Rect2(l.position.x + 24 + bw, l.end.y - 56, bw, 46), func() -> void: m.meta_act(Cores.try_level(m.save, core)), lvl_tip, Cores.can_level(s, core), Kit.GREEN, "BAY LEVEL")
	if not owned:
		return
	# presets
	var v: Rect2 = view_rect(m)
	var pi: int = Parts.preset_idx(s, core)
	for k in Parts.PRESETS:
		var idx: int = k
		Kit.btn(m, "Loadout %d [%s]" % [k + 1, Kit.hint(m, "hotbar_%d" % (k + 1))], Rect2(v.position.x + 12 + k * ((v.size.x - 24.0) / 4.0), v.position.y + 10, (v.size.x - 24.0) / 4.0 - 8.0, 42), func() -> void: m.meta_act(Parts.select_preset(m.save, core, idx)), "Switch to loadout preset %d (each Core keeps 4)" % (k + 1), true, Kit.RUST if pi == k else Kit.NEUTRAL, "PRESET %d" % (k + 1), "", 15)
	# slots
	var lv: int = Cores.level(s, core)
	var row: Array = Parts.preset(s, core)
	for k in Parts.N_SLOTS:
		var sk: int = k
		var c: Vector2 = slot_pos(m, k)
		var r := Rect2(c - Vector2(SLOT_R, SLOT_R), Vector2(SLOT_R, SLOT_R) * 2.0)
		var typ: String = String(Parts.SLOT_TYPES[k])
		var open: bool = Parts.slot_open(lv, k)
		var uid: String = String(row[k])
		var tip2: String = "%s slot" % String(PartDB.SLOT_NAMES[typ])
		if not open:
			tip2 += " — opens at Core level %d" % (Parts.SET_SLOT_LVL if k == Parts.SET_SLOT else int(Parts.SLOT_LVLS[k]))
		elif uid != "":
			var it: Dictionary = Parts.item(s, uid)
			tip2 = _part_tip(String(it.get("id", "")), int(it.get("lvl", 1)), int(it.get("stars", 0))) + "\nClick to select · right-click / Unequip to remove"
		else:
			tip2 += " — drag a part here, or select a part and press Equip"
		Kit.hit(m, r, func() -> void: _slot_click(m, sk), tip2, "SLOT %d" % k, open, Kit.SLOT_COL.get(typ, Kit.GOLD))
	# inventory filters
	var i: Rect2 = inv_rect(m)
	var fx: float = i.position.x + 12.0
	var fw: float = (i.size.x - 24.0) / float(SLOT_FILTERS.size())
	for k in SLOT_FILTERS.size():
		var sf: String = SLOT_FILTERS[k]
		Kit.btn(m, "All slots" if sf == "" else String(PartDB.SLOT_NAMES[sf]), Rect2(fx + k * fw, i.position.y + 44, fw - 6, 40), func() -> void: m.bay_filter["slot"] = sf; m.bay_page = 0; m._rebuild_ui(), "Filter the inventory by slot", true, Kit.RUST if String(m.bay_filter["slot"]) == sf else Kit.NEUTRAL, "FILTER SLOT " + (sf if sf != "" else "ALL"), "", 14)
	fw = (i.size.x - 24.0) / float(RAR_FILTERS.size())
	for k in RAR_FILTERS.size():
		var rf: String = RAR_FILTERS[k]
		Kit.btn(m, "All" if rf == "" else rf.capitalize(), Rect2(fx + k * fw, i.position.y + 88, fw - 6, 40), func() -> void: m.bay_filter["rarity"] = rf; m.bay_page = 0; m._rebuild_ui(), "Filter the inventory by rarity", true, Kit.rarity_col(rf) if String(m.bay_filter["rarity"]) == rf and rf != "" else (Kit.RUST if String(m.bay_filter["rarity"]) == rf else Kit.NEUTRAL), "FILTER RARITY " + (rf if rf != "" else "ALL"), "", 14)
	var sets: Array = [""] + SetDB.IDS
	var cur: int = sets.find(String(m.bay_filter["set"]))
	var nxt: String = String(sets[(cur + 1) % sets.size()])
	Kit.btn(m, "Set: %s" % ("any" if String(m.bay_filter["set"]) == "" else String(SetDB.get_def(String(m.bay_filter["set"]))["name"])), Rect2(fx, i.position.y + 132, (i.size.x - 24.0) * 0.5 - 6, 40), func() -> void: m.bay_filter["set"] = nxt; m.bay_page = 0; m._rebuild_ui(), "Cycle the set filter", true, Kit.NEUTRAL, "FILTER SET", "", 14)
	# inventory grid
	var ids: Array = _inv_ids(m)
	var pp: int = per_page(m)
	var pages: int = maxi(1, int(ceil(float(ids.size()) / float(pp))))
	m.bay_page = clampi(m.bay_page, 0, pages - 1)
	Kit.btn(m, "<", Rect2(i.end.x - 12 - 130, i.position.y + 132, 60, 40), func() -> void: m.bay_page -= 1; m._rebuild_ui(), "Previous page", m.bay_page > 0, Kit.NEUTRAL, "INV PREV")
	Kit.btn(m, ">", Rect2(i.end.x - 12 - 64, i.position.y + 132, 60, 40), func() -> void: m.bay_page += 1; m._rebuild_ui(), "Next page", m.bay_page < pages - 1, Kit.NEUTRAL, "INV NEXT")
	var start: int = m.bay_page * pp
	for j in range(start, mini(ids.size(), start + pp)):
		var uid2: String = ids[j]
		var it2: Dictionary = Parts.item(s, uid2)
		var hb: Button = Kit.hit(m, inv_cell(m, j - start), func() -> void: _press_part(m, uid2), _part_tip(String(it2["id"]), int(it2["lvl"]), int(it2["stars"])) + "\nDrag onto a slot to install", "PART " + String(it2["id"]), true, Kit.rarity_col(PartDB.rarity_of(String(it2["id"]))))
		hb.set_meta("uid", uid2)
	# detail actions
	var pu: String = m.bay_part
	if pu != "" and not Parts.item(s, pu).is_empty():
		var it3: Dictionary = Parts.item(s, pu)
		var pid: String = String(it3["id"])
		var dr: Rect2 = detail_rect(m)
		var b4: float = (dr.size.x - 18.0) / 4.0
		var y4: float = dr.end.y - 48.0
		var at: int = installed_slot(m, pu)
		if at >= 0:
			Kit.btn(m, "Unequip", Rect2(dr.position.x, y4, b4, 44), func() -> void: m.meta_act(Parts.unequip(m.save, core, at)), "Remove from slot %d" % (at + 1), true, Kit.NEUTRAL, "BAY UNEQUIP", "", 15)
		else:
			var ts: int = target_slot(m, pu)
			Kit.btn(m, "Equip", Rect2(dr.position.x, y4, b4, 44), func() -> void: m.meta_act(Parts.equip(m.save, core, ts, pu)), "Install into the best open %s slot" % String(PartDB.SLOT_NAMES.get(PartDB.slot_of(pid), "")), ts >= 0, Kit.GREEN, "BAY EQUIP", "", 15)
		var lcst: int = PartDB.level_cost(pid, int(it3["lvl"]))
		Kit.btn(m, "Lv up %s" % Kit.fmt(float(lcst)), Rect2(dr.position.x + b4 + 6, y4, b4, 44), func() -> void: m.meta_act(Parts.level_up(m.save, pu)), "Spend %d Scrap: Lv%d -> %d (+6%% of the + lines per level)" % [lcst, int(it3["lvl"]), int(it3["lvl"]) + 1], Parts.can_level(s, pu), Kit.SCRAP, "BAY PART LEVEL", "cur_scrap", 15)
		var lk: bool = bool(it3["locked"])
		Kit.btn(m, "Unlock" if lk else "Lock", Rect2(dr.position.x + 2.0 * (b4 + 6), y4, b4, 44), func() -> void: Parts.set_locked(m.save, pu, not lk); m.meta_act([{"t": "part_lock"}]), "Locked parts can't be salvaged", true, Kit.GOLD if lk else Kit.NEUTRAL, "BAY LOCK", "icon_lock", 15)
		Kit.btn(m, "Salvage +%d" % Parts.salvage_value(s, pu), Rect2(dr.position.x + 3.0 * (b4 + 6), y4, b4, 44), func() -> void: m.bay_part = ""; m.meta_act(Parts.salvage(m.save, pu)), "Destroy this part for Scrap (not locked / special parts)", not lk and not PartDB.is_special(pid), Kit.ENEMY, "BAY SALVAGE", "", 15)


static func _slot_click(m, k: int) -> void:
	var s: Dictionary = m.save
	var core: String = _core(m)
	var row: Array = Parts.preset(s, core)
	if m.bay_part != "" and installed_slot(m, m.bay_part) < 0 and Parts.fits(s, m.bay_part, k):
		m.meta_act(Parts.equip(s, core, k, m.bay_part))
		return
	m.bay_part = String(row[k])
	m._rebuild_ui()


static func _press_part(m, uid: String) -> void:
	if String(m.last_device) == "pad":
		m.bay_part = uid
		m._rebuild_ui()
		return
	m.begin_drag_part(uid)


static func _part_tip(id: String, lvl: int, stars: int) -> String:
	var d: Dictionary = PartDB.get_def(id)
	var ln: Dictionary = PartDB.lines(id, lvl, stars)
	var st: String = PartDB.set_of(id)
	var head: String = "%s  Lv%d%s  (%s %s%s)" % [String(d.get("name", id)), lvl, "  " + "*".repeat(stars) if stars > 0 else "", PartDB.rarity_of(id).capitalize(), String(PartDB.SLOT_NAMES.get(PartDB.slot_of(id), "")), (", " + String(SetDB.get_def(st)["name"]) + " set") if st != "" else ""]
	var out: Array = [head]
	for l in (ln["plus"] as Array) + (ln["minus"] as Array):
		out.append(Kit.fx_line(String(l)))
	return "\n".join(PackedStringArray(out))


## Keys in the bay: 1-4 loadout presets, U levels the viewed Core.
static func action(m, event: InputEvent) -> bool:
	var core: String = _core(m)
	for k in Parts.PRESETS:
		if event.is_action_pressed("hotbar_%d" % (k + 1), false, true):
			m.meta_act(Parts.select_preset(m.save, core, k))
			return true
	if event.is_action_pressed("upgrade", false, true):
		m.meta_act(Cores.try_level(m.save, core))
		return true
	return false


# ===================================================================== draw
static func draw(m, _cr: Rect2) -> void:
	var s: Dictionary = m.save
	var core: String = _core(m)
	_draw_list(m, s, core)
	_draw_view(m, s, core)
	_draw_inventory(m, s, core)
	# drag ghost
	if m.drag_part != "" and m.mouse_pos.distance_to(m.drag_start) > 12.0:
		var it: Dictionary = Parts.item(s, m.drag_part)
		var k: int = slot_at(m, m.mouse_pos)
		if k >= 0:
			var ok: bool = Parts.slot_open(Cores.level(s, core), k) and Parts.fits(s, m.drag_part, k)
			m.draw_arc(slot_pos(m, k), SLOT_R + 6.0, 0, TAU, 40, Kit.GREEN if ok else Kit.ENEMY, 4.0)
		Kit.icon(m, String(it.get("id", "")), Rect2(m.mouse_pos - Vector2(32, 32), Vector2(64, 64)), Color(1, 1, 1, 0.85))


static func _draw_list(m, s: Dictionary, core: String) -> void:
	var l: Rect2 = list_rect(m)
	Kit.panel(m, l, Kit.EDGE, Kit.PANEL)
	Kit.t(m, "CORES", Vector2(l.position.x + 16, l.position.y + 32), 20, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, l.size.x)
	for k in CoreDB.IDS.size():
		var id: String = CoreDB.IDS[k]
		var d: Dictionary = CoreDB.get_def(id)
		var r: Rect2 = core_card(m, k)
		var own: bool = Cores.is_owned(s, id)
		var act: bool = Cores.active(s) == id
		Kit.panel(m, r, Kit.GOLD if id == core else (Kit.RUST if act else Kit.EDGE), Kit.PANEL2 if own else Color("181c22"), 3 if id == core else 2)
		var isz: float = minf(r.size.y - 16.0, 96.0)
		Kit.icon(m, "core_" + id if own else "core_locked", Rect2(r.position.x + 8, r.position.y + (r.size.y - isz) * 0.5, isz, isz), Color.WHITE if own else Color(1, 1, 1, 0.7))
		var tx: float = r.position.x + isz + 18.0
		var tw: float = r.end.x - tx - 8.0
		Kit.t(m, String(d["name"]), Vector2(tx, r.position.y + 30), 20, Kit.TEXT if own else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, tw)
		if own:
			Kit.t(m, "Lv %d  ·  %s" % [Cores.level(s, id), String(d["arch"]).capitalize()], Vector2(tx, r.position.y + 54), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, tw)
			Kit.t(m, String(d["attack_name"]), Vector2(tx, r.position.y + 78), 14, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, tw)
			if act:
				Kit.t(m, "ACTIVE", Vector2(tx, r.end.y - 12), 13, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, tw)
		else:
			Kit.wrap(m, "Unlock: " + String(CoreDB.UNLOCK_TEXT.get(id, "")), Vector2(tx, r.position.y + 46), 13, Color("ff8a8a"), tw, 3)
	var lc: Dictionary = Cores.level_cost(Cores.level(s, core))
	Kit.t(m, "Next level: %s coins%s" % [Kit.fmt(float(lc["coins"])), ("  +%d Core Cores" % int(lc["core_cores"])) if int(lc["core_cores"]) > 0 else ""], Vector2(l.position.x + 16, l.end.y - 70), 14, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, l.size.x - 32)


static func _draw_view(m, s: Dictionary, core: String) -> void:
	var v: Rect2 = view_rect(m)
	Kit.panel(m, v, Kit.EDGE, Color("161b21"))
	var d: Dictionary = CoreDB.get_def(core)
	var c: Vector2 = hub_center(m)
	var R: float = orbit(m)
	if not Cores.is_owned(s, core):
		Kit.icon(m, "core_locked", Rect2(c - Vector2(110, 110), Vector2(220, 220)))
		Kit.t(m, "%s Core — locked" % String(d["name"]), Vector2(c.x, c.y + 160), 24, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, v.size.x)
		Kit.t(m, String(CoreDB.UNLOCK_TEXT.get(core, "")), Vector2(c.x, c.y + 192), 17, Color("ff8a8a"), HORIZONTAL_ALIGNMENT_CENTER, v.size.x - 40)
		Kit.wrap(m, "%s: %s\nTrait %s: %s" % [String(d["attack_name"]), String(d["attack_desc"]), String(d["trait_name"]), String(d["trait_desc"])], Vector2(v.position.x + 40, c.y + 230), 16, Kit.DIM, v.size.x - 80, 4, HORIZONTAL_ALIGNMENT_CENTER)
		return
	# exploded view
	var g: float = 0.5 + 0.5 * sin(m.t_anim * 1.5)
	m.draw_arc(c, R, 0, TAU, 96, Color(Kit.RUST, 0.25), 2.0)
	m.draw_circle(c, R * 0.55 + 4.0 * g, Color(Kit.RUST, 0.05))
	var cs: float = R * 0.95
	if not Kit.icon(m, "core_open", Rect2(c - Vector2(cs, cs) * 0.5, Vector2(cs, cs))):
		Kit.icon(m, "core_" + core, Rect2(c - Vector2(cs, cs) * 0.5, Vector2(cs, cs)))
	Kit.icon(m, "core_" + core, Rect2(c - Vector2(40, 40), Vector2(80, 80)))
	var lv: int = Cores.level(s, core)
	var row: Array = Parts.preset(s, core)
	for k in Parts.N_SLOTS:
		var p: Vector2 = slot_pos(m, k)
		var typ: String = String(Parts.SLOT_TYPES[k])
		var open: bool = Parts.slot_open(lv, k)
		var col: Color = Kit.SLOT_COL.get(typ, Kit.DIM)
		m.draw_line(c + (p - c).normalized() * cs * 0.45, p - (p - c).normalized() * SLOT_R, Color(col, 0.35 if open else 0.1), 2.0)
		var uid: String = String(row[k])
		var sel: bool = uid != "" and uid == m.bay_part
		m.draw_circle(p, SLOT_R, Color("0f1317"))
		m.draw_arc(p, SLOT_R, 0, TAU, 40, Kit.GOLD if sel else (col if open else Color(col, 0.25)), 4.0 if sel else 3.0)
		if not open:
			Kit.icon(m, "slot_locked", Rect2(p - Vector2(26, 26), Vector2(52, 52)), Color(1, 1, 1, 0.5))
			Kit.t(m, "Lv %d" % (Parts.SET_SLOT_LVL if k == Parts.SET_SLOT else int(Parts.SLOT_LVLS[k])), p + Vector2(0, SLOT_R + 18), 13, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
		elif uid != "":
			var it: Dictionary = Parts.item(s, uid)
			var pid: String = String(it.get("id", ""))
			m.draw_circle(p, SLOT_R - 4.0, Color(Kit.rarity_col(PartDB.rarity_of(pid)), 0.15))
			Kit.icon(m, pid, Rect2(p - Vector2(34, 34), Vector2(68, 68)))
			Kit.t(m, "Lv%d" % int(it.get("lvl", 1)), p + Vector2(0, SLOT_R + 18), 13, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
		else:
			Kit.icon(m, String(SLOT_ICON.get(typ, "slot_frame")), Rect2(p - Vector2(26, 26), Vector2(52, 52)), Color(1, 1, 1, 0.55))
			Kit.t(m, String(PartDB.SLOT_NAMES[typ]), p + Vector2(0, SLOT_R + 18), 13, Color(col, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 90.0)
	Kit.t(m, "%s Core  ·  Lv %d / %d  ·  %d / %d slots open" % [String(d["name"]), lv, Cores.max_level(s), Parts.slot_count(lv) + (1 if lv >= Parts.SET_SLOT_LVL else 0), Parts.N_SLOTS], Vector2(v.get_center().x, v.position.y + 84), 17, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, v.size.x)
	# set badges + totals
	var y: float = c.y + R + SLOT_R + 46.0
	var cnt: Dictionary = Parts.set_counts(s, core)
	var done: Array = (s.get("parts", {}) as Dictionary).get("sets_completed", []) if s.get("parts", null) is Dictionary else []
	var bw: float = (v.size.x - 24.0) / float(SetDB.IDS.size())
	for k in SetDB.IDS.size():
		var st: String = SetDB.IDS[k]
		var sd: Dictionary = SetDB.get_def(st)
		var n: int = int(cnt.get(st, 0))
		var bx: float = v.position.x + 12.0 + float(k) * bw
		var on: bool = n >= 2
		Kit.icon(m, "set_" + st, Rect2(bx + 4, y - 4, 40, 40), Color.WHITE if n > 0 or done.has(st) else Color(1, 1, 1, 0.3))
		Kit.t(m, String(sd["name"]), Vector2(bx + 50, y + 12), 15, Kit.TEXT if on else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, bw - 52)
		Kit.t(m, "%d/4%s" % [n, "  done" if done.has(st) else ""], Vector2(bx + 50, y + 32), 13, Kit.GREEN if n >= 4 else (Kit.GOLD if on else Kit.DIM), HORIZONTAL_ALIGNMENT_LEFT, bw - 52)
		var two: Array = []
		for key in (sd["two"] as Dictionary).keys():
			two.append(PartDB.fmt_fx(String(key), float(sd["two"][key])))
		m.stat_tips.append([Rect2(bx, y - 6, bw - 4, 46), "%s set (%s)\n2 pieces: %s\n4 pieces: %s\nComplete it once to unlock the special part %s." % [String(sd["name"]), String(sd["spec"]), ", ".join(two), String((sd["four"] as Dictionary).keys()[0]).replace("_", " "), String(PartDB.get_def(String(sd["special"])).get("name", ""))]])
	y += 60.0
	Kit.head(m, "INSTALLED TOTALS (this loadout)", Vector2(v.position.x + 16, y), v.size.x - 32)
	var fx: Dictionary = Parts.run_fx(s, core)
	var keys: Array = fx.keys()
	keys.sort()
	var col_w: float = (v.size.x - 32.0) / 2.0
	var j: int = 0
	for key in keys:
		var val: float = float(fx[key])
		if absf(val) < 0.0001:
			continue
		var ty: float = y + 26.0 + float(j / 2) * 22.0
		if ty > v.end.y - 10.0:
			break
		var good: bool = val > 0.0 and not (String(key) in PartDB.UNSIGNED_PCT)
		Kit.t(m, PartDB.fmt_fx(String(key), val), Vector2(v.position.x + 16 + float(j % 2) * col_w, ty), 15, Kit.GREEN if good else Color("ff6b6b"), HORIZONTAL_ALIGNMENT_LEFT, col_w - 8)
		j += 1
	if j == 0:
		Kit.t(m, "No parts installed. Every part trades a strength for a weakness — spec balanced, eco, single-target or area.", Vector2(v.position.x + 16, y + 28), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, v.size.x - 32)


static func _draw_inventory(m, s: Dictionary, core: String) -> void:
	var i: Rect2 = inv_rect(m)
	Kit.panel(m, i, Kit.EDGE, Kit.PANEL)
	var ids: Array = _inv_ids(m)
	Kit.t(m, "PARTS  (%d)" % Parts.items(s).size(), Vector2(i.position.x + 16, i.position.y + 32), 20, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
	Kit.chip(m, "cur_scrap", Kit.fmt(float(int(s.get("scrap", 0)))), Vector2(i.end.x - 140, i.position.y + 34), Kit.SCRAP, "Scrap levels up parts", 130.0)
	var pp: int = per_page(m)
	var pages: int = maxi(1, int(ceil(float(ids.size()) / float(pp))))
	Kit.t(m, "page %d / %d" % [m.bay_page + 1, pages], Vector2(i.end.x - 150, i.position.y + 158), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
	var row: Array = Parts.preset(s, core)
	var start: int = m.bay_page * pp
	for j in range(start, mini(ids.size(), start + pp)):
		var uid: String = ids[j]
		var it: Dictionary = Parts.item(s, uid)
		var pid: String = String(it["id"])
		var r: Rect2 = inv_cell(m, j - start)
		var rc: Color = Kit.rarity_col(PartDB.rarity_of(pid))
		Kit.panel(m, r, Kit.GOLD if uid == m.bay_part else rc, Color(rc.darkened(0.8), 1.0), 3 if uid == m.bay_part else 2)
		Kit.icon(m, pid, r.grow(-6))
		Kit.t(m, "%d" % int(it["lvl"]), r.position + Vector2(6, r.size.y - 6), 13, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 30.0)
		for st in int(it["stars"]):
			m.draw_circle(r.position + Vector2(r.size.x - 8 - st * 9, 8), 3.5, Kit.GOLD)
		if row.has(uid):
			m.draw_rect(Rect2(r.end.x - 14, r.end.y - 14, 10, 10), Kit.GREEN)
		if bool(it["locked"]):
			Kit.icon(m, "icon_lock", Rect2(r.position.x + 4, r.position.y + 4, 16, 16))
	if ids.is_empty():
		Kit.wrap(m, "No parts match. Open crates or beat bosses, marked elites and Couriers to find parts.", inv_grid(m).position + Vector2(0, 30), 16, Kit.DIM, inv_grid(m).size.x, 3)
	# detail
	var dr: Rect2 = detail_rect(m)
	Kit.panel(m, dr.grow(4), Kit.EDGE, Kit.PANEL2)
	var pu: String = m.bay_part
	if pu == "" or Parts.item(s, pu).is_empty():
		Kit.wrap(m, "Select a part to see its trade-off, compare it with what is installed, level it with Scrap, lock or salvage it.", dr.position + Vector2(10, 30), 16, Kit.DIM, dr.size.x - 20, 4)
		return
	var it2: Dictionary = Parts.item(s, pu)
	var id2: String = String(it2["id"])
	var rc2: Color = Kit.rarity_col(PartDB.rarity_of(id2))
	Kit.panel(m, Rect2(dr.position.x + 6, dr.position.y + 6, 84, 84), rc2, Color("0f1317"))
	Kit.icon(m, id2, Rect2(dr.position.x + 12, dr.position.y + 12, 72, 72))
	var tx: float = dr.position.x + 104.0
	var tw: float = dr.end.x - tx - 8.0
	Kit.t(m, String(PartDB.get_def(id2).get("name", id2)), Vector2(tx, dr.position.y + 30), 22, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, tw)
	var st2: String = PartDB.set_of(id2)
	Kit.t(m, "%s %s  ·  Lv %d / %d%s%s" % [PartDB.rarity_of(id2).capitalize(), String(PartDB.SLOT_NAMES.get(PartDB.slot_of(id2), "")), int(it2["lvl"]), PartDB.max_lvl(id2), ("  ·  " + "*".repeat(int(it2["stars"]))) if int(it2["stars"]) > 0 else "", ("  ·  " + String(SetDB.get_def(st2)["name"]) + " set") if st2 != "" else ""], Vector2(tx, dr.position.y + 54), 15, rc2, HORIZONTAL_ALIGNMENT_LEFT, tw)
	var ln: Dictionary = PartDB.lines(id2, int(it2["lvl"]), int(it2["stars"]))
	var y: float = dr.position.y + 82.0
	for p in ln["plus"]:
		Kit.t(m, Kit.fx_line(String(p)), Vector2(tx, y), 16, Kit.GREEN, HORIZONTAL_ALIGNMENT_LEFT, tw)
		y += 21.0
	for p2 in ln["minus"]:
		Kit.t(m, Kit.fx_line(String(p2)), Vector2(tx, y), 16, Color("ff6b6b"), HORIZONTAL_ALIGNMENT_LEFT, tw)
		y += 21.0
	# compare with the installed part of the same slot type
	var at: int = installed_slot(m, pu)
	if at < 0:
		var other: String = ""
		for k in Parts.N_SLOTS:
			var u: String = String(row[k])
			if u != "" and PartDB.slot_of(String(Parts.item(s, u).get("id", ""))) == PartDB.slot_of(id2):
				other = u
				break
		y += 6.0
		if other != "" and y < dr.end.y - 70.0:
			var io: Dictionary = Parts.item(s, other)
			Kit.t(m, "vs installed %s  Lv%d:" % [String(PartDB.get_def(String(io["id"])).get("name", "")), int(io["lvl"])], Vector2(dr.position.x + 12, y + 6), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 24)
			var lo: Dictionary = PartDB.lines(String(io["id"]), int(io["lvl"]), int(io["stars"]))
			var all: Array = []
			for ln2 in (lo["plus"] as Array) + (lo["minus"] as Array):
				all.append(Kit.fx_line(String(ln2)))
			Kit.t(m, "   ".join(PackedStringArray(all)), Vector2(dr.position.x + 12, y + 26), 14, Color(Kit.DIM, 0.9), HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 24)
		elif y < dr.end.y - 70.0:
			Kit.t(m, "Its slot is empty in this loadout — Equip adds it free of trade-ins.", Vector2(dr.position.x + 12, y + 6), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 24)
	else:
		Kit.t(m, "Installed in slot %d" % (at + 1), Vector2(dr.position.x + 12, minf(y + 12, dr.end.y - 60)), 14, Kit.GREEN, HORIZONTAL_ALIGNMENT_LEFT, dr.size.x - 24)
