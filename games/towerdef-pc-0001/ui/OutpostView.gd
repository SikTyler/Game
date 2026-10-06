extends RefCounted
## Outpost builder (V2 P6): the persistent base outside runs.
## Pannable / zoomable 48x32 map (right- or middle-drag pans, wheel zooms)
## framed on the frontier (open land + the plots you can buy next), build
## palette on the right (by category: cost, power, count / limit),
## selected-building panel (production or Core stat, storage bar, link,
## layout parts, next-upgrade delta, Collect / Upgrade / Move / Rotate /
## Demolish), Collect all and the blueprint menu (save / load / export /
## import). Buildings are drawn procedurally (OutpostArt).
## Hover preview: ghost footprint, green / red validity with the reason, a
## link line to the Relay and adjacency connector lines with +/- chips (who
## feeds the ghost, which neighbours it changes; same lines for a selected
## building).
## Hotkeys: R rotate, M move, Del demolish, U upgrade, 1-9 palette.
## View only: every action calls Outpost and replays its events.

const Outpost := preload("res://Outpost.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const Settings := preload("res://Settings.gd")
const Art := preload("res://ArtDB.gd")
const Kit := preload("res://ui/Kit.gd")
const OutpostArt := preload("res://ui/OutpostArt.gd")
const AdjDB := preload("res://data/AdjDB.gd")

const PAL_W: float = 400.0
const HEAD_H: float = 48.0
## [id, label, icon] — FB1: obvious build categories with icons.
const CATS: Array = [["prod", "Production", "op_mill_1"], ["core", "Core", "core_open"], ["scav", "Scavenge", "chest"], ["support", "Support", "op_research_1"], ["infra", "Links", "op_conduit"], ["decor", "Decor", "dc_tree"]]
## V2: the Command Plaza is gone (Core / Forge / Research are top-bar tabs).
const PLAZA_W: int = 0
const LANDMARKS: Array = []
const LM_SIZE: int = 3
const CAT_IDS: Dictionary = {
	"prod": ["mill", "refinery", "gemmine"],
	"core": ["arsenal", "reactor", "bulwark_w", "aegis_a", "optics", "rangefinder", "treasury", "training", "shrine", "forgeworks"],
	"scav": ["scav_post", "scav_den", "scav_deep"],
	"support": ["research", "barracks", "archive", "warehouse", "scrapyard", "beaconpost", "pylon"],
	"infra": ["conduit"],
	"decor": ["dc_lamp", "dc_brazier", "dc_tree", "dc_shrub", "dc_pond", "dc_crates", "dc_smelter", "dc_bookshelf", "dc_orrery", "dc_yard", "dc_dummy", "dc_banner", "dc_trophy"],
}
const DESC: Dictionary = {
	"relay": "The heart of the Outpost. Its level sets power, building limits and max levels; Lv3 unlocks Collect all.",
	"mill": "Mints coins. +10% per adjacent Mill (max +30%), +15% next to a Warehouse.",
	"refinery": "Refines Scrap for the Forge. -10% next to a Mill; a Smelter next to it adds +20%.",
	"gemmine": "Deep Mine: a big coin generator. Crystal Vein only; lit Lamps next to it +10% each.",
	"research": "Runs research projects; queues at Hall Lv1 / 4 / 8. Scholar decor speeds it.",
	"barracks": "Each level: +10% troop HP and damage in runs. Training decor adds more.",
	"archive": "Lv3 / 6: +1 / +2 Insight per run; Lv9: +1 banish per run.",
	"warehouse": "+10% storage (+2% per level) to buildings within 2 cells.",
	"scrapyard": "Salvaging parts returns more Scrap.",
	"conduit": "Carries power: buildings work only when linked to the Relay.",
	"beaconpost": "+5% to every building within 2 cells.",
	"arsenal": "Core building: +2% all damage per level in every run. A touching Reactor: +20%.",
	"reactor": "Core building: +1.5% Weapon attack rate per level. Powers a touching Arsenal (+20%); heats a touching Mill (-15%).",
	"bulwark_w": "Core building: +3% Core max HP per level. Plates a touching Aegis Array (+15%).",
	"aegis_a": "Core building: -0.6% damage taken per level.",
	"optics": "Core building: +0.5% crit chance per level. Lenses a touching Rangefinder (+15%).",
	"rangefinder": "Core building: +0.04 cell Weapon range per level.",
	"treasury": "Core building: +2% run cash per second per level. +5% to Mills within 2 cells.",
	"training": "Core building: +3% run XP per level. Drills a touching Barracks (+10%).",
	"shrine": "Core building: +1 loot luck per level when a run banks. Guides scavengers within 2 cells (+10%).",
	"forgeworks": "Core building: -2% Forge costs per level. A touching Refinery: +10%.",
	"scav_post": "Finds an item every 6 h while you are away (stores 4, +1 per 3 levels). Scavengers within 2 cells compete (-15%).",
	"scav_den": "Finds a Field Cache every 12 h (stores 2).",
	"scav_deep": "Finds an Elite Cache (Rare+) every 24 h (stores 2).",
	"pylon": "+5% to buildings exactly 2 cells away, -5% to anything touching it.",
}
## Core building stats: key -> [label, format, scale].
const CORE_FMT: Dictionary = {
	"dmg": ["Damage", "+%.1f%%", 100.0], "rate": ["Attack rate", "+%.1f%%", 100.0], "core_hp": ["Core HP", "+%.1f%%", 100.0],
	"dr": ["Damage taken", "-%.1f%%", 100.0], "crit": ["Crit chance", "+%.1f%%", 100.0], "range": ["Range", "+%.2f", 1.0],
	"cash": ["Run cash", "+%.1f%%", 100.0], "xp": ["Run XP", "+%.1f%%", 100.0], "loot_luck": ["Loot luck", "+%.1f", 1.0],
	"forge_disc": ["Forge costs", "-%.1f%%", 100.0],
}
## Short names of layout parts (AdjDB keys + decor).
const PART_NAME: Dictionary = {
	"mills": "Mills", "warehouse": "Warehouse", "noise": "Mill noise", "heat": "Reactor heat", "reactor": "Reactor",
	"plating": "Bulwark", "lenses": "Optics", "drills": "Training", "ledger": "Treasury", "smelt": "Refinery",
	"omens": "Shrine", "rivals": "Rivals", "beacon": "Beacon", "pylon": "Pylon", "pylon_hum": "Pylon hum", "decor": "Decor",
}
## Scavenger finds (res -> name).
const SCAV_NAME: Dictionary = {"item": "item", "field": "Field Cache", "elite": "Elite Cache"}
const ERR: Dictionary = {"outside": "Outside the map", "locked": "Locked land — buy the plot", "blocked": "Rock", "occupied": "Occupied", "needs_vein": "Deep Mine needs a Crystal Vein", "limit": "Limit reached — upgrade the Relay", "relay": "Needs a higher Relay level", "unknown": "?"}


static func map_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.position.x + 12, cr.position.y + HEAD_H + 16, cr.size.x - PAL_W - 36, cr.size.y - HEAD_H - 28)


static func head_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.position.x + 12, cr.position.y + 10, cr.size.x - PAL_W - 36, HEAD_H)


static func pal_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.end.x - PAL_W - 12, cr.position.y + 12, PAL_W, cr.size.y - 24)


## V2 P6c: the camera frames the frontier - open land plus the plots you
## can buy next, +1 cell - so cells stay big while the Outpost is small
## (cell units; cached on the plot list).
static func frame(m) -> Rect2:
	var o: Dictionary = _o(m)
	var key: String = str(o["plots"])
	var cache: Dictionary = m.get_meta("op_frame", {})
	if String(cache.get("key", "-")) == key:
		return cache["r"]
	var r: Rect2i = OutpostDB.START
	r = r.merge(Rect2i(OutpostDB.RELAY, Vector2i(3, 3)))
	for k in OutpostDB.PLOTS.size():
		if (o["plots"] as Array).has(k) or Outpost.plot_adjacent(o, k):
			r = r.merge(OutpostDB.PLOTS[k])
	r = r.grow(1).intersection(Rect2i(0, 0, OutpostDB.W, OutpostDB.H))
	var out := Rect2(r)
	m.set_meta("op_frame", {"key": key, "r": out})
	return out


## Open-land mask (W x H bytes, 1 = open), cached on the plot list.
static func open_mask(m) -> PackedByteArray:
	var o: Dictionary = _o(m)
	var key: String = str(o["plots"])
	var cache: Dictionary = m.get_meta("op_mask", {})
	if String(cache.get("key", "-")) == key:
		return cache["v"]
	var out := PackedByteArray()
	out.resize(OutpostDB.W * OutpostDB.H)
	for y in OutpostDB.H:
		for x in OutpostDB.W:
			out[y * OutpostDB.W + x] = 1 if Outpost.is_open(o, Vector2i(x, y)) else 0
	m.set_meta("op_mask", {"key": key, "v": out})
	return out


## A slate boulder on a rock cell (seeded by the cell).
static func _rock(m, r: Rect2, x: int, y: int) -> void:
	var c: Vector2 = r.get_center()
	var rad: float = r.size.x * 0.42
	var pts := PackedVector2Array()
	var h: int = hash([x, y])
	for k in 7:
		var an: float = TAU * float(k) / 7.0 + float(h % 7) * 0.3
		pts.append(c + Vector2(cos(an), sin(an) * 0.85) * rad * (0.8 + 0.2 * float((h >> k) & 1)))
	m.draw_colored_polygon(pts, Color("27304a"))
	var top := PackedVector2Array([pts[4], pts[5], pts[6], pts[0]])
	m.draw_polyline(top, Color("4a5678"), 1.5, true)


static func cell_px(m) -> float:
	var mr: Rect2 = map_rect(m)
	var f: Rect2 = frame(m)
	return minf(mr.size.x / f.size.x, mr.size.y / f.size.y) * 0.97 * m.op_zoom


## Cell (0, 0) on screen: the frontier's centre sits at the map's centre,
## then the pan offset.
static func origin(m) -> Vector2:
	var mr: Rect2 = map_rect(m)
	return mr.get_center() - frame(m).get_center() * cell_px(m) + m.op_cam


static func landmark_rect(m, tab: String) -> Rect2:
	for lm in LANDMARKS:
		if String((lm as Array)[0]) == tab:
			var c: Vector2i = (lm as Array)[3]
			return cell_rect(m, c.x, c.y, LM_SIZE, LM_SIZE)
	return Rect2()


## Landmark under a cell ("" = none).
static func landmark_at(c: Vector2i) -> String:
	for lm in LANDMARKS:
		var p: Vector2i = (lm as Array)[3]
		if Rect2i(p, Vector2i(LM_SIZE, LM_SIZE)).has_point(c):
			return String((lm as Array)[0])
	return ""


static func _landmark(tab: String) -> Array:
	for lm in LANDMARKS:
		if String((lm as Array)[0]) == tab:
			return lm
	return []


static func cell_at(m, p: Vector2) -> Vector2i:
	var c: float = cell_px(m)
	var q: Vector2 = (p - origin(m)) / c
	return Vector2i(int(floor(q.x)), int(floor(q.y)))


static func cell_rect(m, x: int, y: int, w: int = 1, h: int = 1) -> Rect2:
	var c: float = cell_px(m)
	return Rect2(origin(m) + Vector2(float(x), float(y)) * c, Vector2(float(w), float(h)) * c)


static func _o(m) -> Dictionary:
	return Outpost._o(m.save)


static func is_decor(id: String) -> bool:
	return OutpostDB.DECOR.has(id)


static func name_of(id: String) -> String:
	if is_decor(id):
		return String((OutpostDB.DECOR[id] as Dictionary)["name"])
	return String(OutpostDB.get_def(id).get("name", id))


static func cost_of(id: String) -> Dictionary:
	if is_decor(id):
		var d: Dictionary = OutpostDB.DECOR[id]
		return {"coins": int(d["coins"])}
	var b: Dictionary = OutpostDB.get_def(id)
	return {"coins": int(b.get("coins", 0))}


static func size_of(id: String, rot: int) -> Vector2i:
	if is_decor(id):
		var sz: Array = (OutpostDB.DECOR[id] as Dictionary)["size"]
		return Vector2i(int(sz[1]), int(sz[0])) if rot % 2 == 1 else Vector2i(int(sz[0]), int(sz[1]))
	return OutpostDB.size_of(id, rot)


static func art_of(id: String, lvl: int) -> String:
	if is_decor(id):
		return id
	if id == "conduit":
		return "op_conduit"
	return OutpostDB.art_id(id, lvl)


## Palette category of a building / decor id ("" if none).
static func cat_of(id: String) -> String:
	for k in CAT_IDS.keys():
		if (CAT_IDS[k] as Array).has(id):
			return String(k)
	return "prod"


## The uid of the best-level placed building of `id` ("" if none).
static func uid_of(m, id: String) -> String:
	var o: Dictionary = _o(m)
	var best: String = ""
	var bl: int = -1
	for k in o["buildings"].keys():
		var b: Dictionary = o["buildings"][k]
		if String(b["id"]) == id and int(b["x"]) >= 0 and int(b["lvl"]) > bl:
			bl = int(b["lvl"])
			best = String(k)
	return best


## Centre the map camera on a building ("relay" or a uid).
static func focus_on(m, uid: String) -> void:
	var o: Dictionary = _o(m)
	var cell: Vector2
	var sz: Vector2i
	if uid == "relay":
		cell = Vector2(OutpostDB.RELAY)
		sz = OutpostDB.size_of("relay", 0)
	elif (o["buildings"] as Dictionary).has(uid):
		var b: Dictionary = o["buildings"][uid]
		cell = Vector2(int(b["x"]), int(b["y"]))
		sz = OutpostDB.size_of(String(b["id"]), int(b["rot"]))
	else:
		return
	var c: float = cell_px(m)
	m.op_cam = (frame(m).get_center() - (cell + Vector2(sz) * 0.5)) * c


## Rect of a building / the Relay on screen (pulse after a jump).
static func building_rect(m, uid: String) -> Rect2:
	var o: Dictionary = _o(m)
	if uid == "relay":
		return cell_rect(m, OutpostDB.RELAY.x, OutpostDB.RELAY.y, 3, 3)
	if not (o["buildings"] as Dictionary).has(uid):
		return Rect2()
	var b: Dictionary = o["buildings"][uid]
	var sz: Vector2i = OutpostDB.size_of(String(b["id"]), int(b["rot"]))
	return cell_rect(m, int(b["x"]), int(b["y"]), sz.x, sz.y)


## Draw a building (procedural neon, OutpostArt) or a decor / Conduit
## texture inside a footprint rect.
static func _bld(m, id: String, lvl: int, r: Rect2, linked: bool = true, alpha: float = 1.0) -> void:
	if OutpostArt.has_art(id):
		OutpostArt.draw(m, id, lvl, r, float(m.t_anim), {"linked": linked, "alpha": alpha, "max": int(OutpostDB.get_def(id).get("max_lvl", 10))})
	else:
		_art(m, art_of(id, lvl), r, Color(1, 1, 1, alpha))


## Draw an Outpost texture inside a footprint rect, aspect kept.
static func _art(m, id: String, r: Rect2, mod: Color = Color.WHITE) -> void:
	var tx: Texture2D = Art.tex(id)
	if tx == null:
		m.draw_rect(r.grow(-4), Color(Kit.RUST, 0.5 * mod.a))
		return
	var ts: Vector2 = tx.get_size()
	var k: float = minf(r.size.x / ts.x, r.size.y / ts.y)
	var sz: Vector2 = ts * k
	m.draw_texture_rect(tx, Rect2(r.get_center() - sz * 0.5, sz), false, mod)


# ===================================================================== input
## Mouse inside the map (Main._input). True = consumed.
static func mouse(m, mb: InputEventMouseButton) -> bool:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return true
			var before: Vector2 = (mb.position - origin(m)) / cell_px(m)
			m.op_zoom = clampf(m.op_zoom * (1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), 0.6, 2.0)
			var after: Vector2 = origin(m) + before * cell_px(m)
			m.op_cam += mb.position - after
			return true
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				m.op_pan = true
				m.op_pan_from = mb.position
				m.op_pan_moved = false
			else:
				m.op_pan = false
				if not m.op_pan_moved and mb.button_index == MOUSE_BUTTON_RIGHT:
					cancel(m)
			return true
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				click(m, cell_at(m, mb.position))
			return true
	return false


static func cancel(m) -> void:
	m.op_arm = ""
	m.op_moving = false
	m.op_sel = ""
	m.op_msg = ""
	m._rebuild_ui()


static func arm(m, id: String) -> void:
	m.op_arm = "" if m.op_arm == id and not m.op_drag else id
	m.op_moving = false
	m.op_sel = ""
	m.op_rot = 0
	m.op_msg = ""
	m._rebuild_ui()


static func _press_palette(m, id: String) -> void:
	arm(m, id)
	if m.op_arm != "" and String(m.last_device) != "pad":
		m.op_drag = true
		m.drag_start = m.mouse_pos


static func click(m, c: Vector2i) -> void:
	m.op_focus = c
	var lm: String = landmark_at(c)
	if lm != "" and m.op_arm == "" and not m.op_moving:
		m.set_tab(lm)
		return
	if m.op_arm != "":
		place_at(m, c)
		return
	if m.op_moving and m.op_sel != "":
		_move_to(m, c)
		return
	var o: Dictionary = _o(m)
	if not Outpost.in_map(c):
		m.op_sel = ""
		m._rebuild_ui()
		return
	var p: int = Outpost.plot_of(c)
	if p >= 0 and not (o["plots"] as Array).has(p):
		m.op_sel = "plot:%d" % p
		m._rebuild_ui()
		return
	var who: String = String(Outpost.occupancy(o).get(c, ""))
	m.op_sel = who
	m.op_msg = ""
	# one-click harvest: clicking a generator with stock collects it
	if who != "" and who != "relay" and not who.begins_with("d"):
		var b: Dictionary = o["buildings"][who]
		if OutpostDB.GENERATORS.has(String(b["id"])) and float(b["stored"]) >= 1.0:
			m.meta_act(Outpost.collect(m.save, who, m.now()))
			return
	m._rebuild_ui()


static func place_at(m, c: Vector2i) -> void:
	var id: String = m.op_arm
	if id == "":
		return
	var ev: Array = []
	if is_decor(id):
		ev = Outpost.place_decor(m.save, id, c.x, c.y, m.op_rot)
	else:
		ev = Outpost.place(m.save, id, c.x, c.y, m.op_rot, m.now())
	if ev.is_empty():
		m.op_msg = _why(m, id, c)
		m._rebuild_ui()
		return
	m.op_msg = ""
	if not (id == "conduit" or is_decor(id)):
		m.op_arm = ""   # conduits and decor stay armed for painting
		for e in ev:
			if String((e as Dictionary)["t"]) == "op_placed":
				m.op_sel = String(e["uid"])
	m.meta_act(ev)


static func _why(m, id: String, c: Vector2i) -> String:
	var err: String = Outpost.place_error(m.save, id, c.x, c.y, m.op_rot)
	if err != "":
		return String(ERR.get(err, err))
	var cc: Dictionary = cost_of(id)
	if not Outpost.can_afford(m.save, int(cc["coins"])):
		return "Not enough coins"
	return "Can't build here"


static func _move_to(m, c: Vector2i) -> void:
	var who: String = m.op_sel
	var ev: Array = []
	if who.begins_with("d"):
		ev = Outpost.move_decor(m.save, who.substr(1), c.x, c.y, m.op_rot)
	else:
		ev = Outpost.move(m.save, who, c.x, c.y, m.op_rot, m.now())
	if ev.is_empty():
		m.op_msg = "Can't move there"
		m._rebuild_ui()
		return
	m.op_moving = false
	m.meta_act(ev)


static func begin_move(m) -> void:
	var who: String = m.op_sel
	if who == "" or who == "relay" or who.begins_with("plot"):
		return
	var o: Dictionary = _o(m)
	if who.begins_with("d"):
		m.op_rot = int((o["decor"][who.substr(1)] as Dictionary)["rot"])
	else:
		m.op_rot = int((o["buildings"][who] as Dictionary)["rot"])
	m.op_moving = true
	m.op_arm = ""
	m._rebuild_ui()


static func demolish(m) -> void:
	var who: String = m.op_sel
	if who == "" or who == "relay" or who.begins_with("plot"):
		return
	var confirm: bool = bool((Settings.normalize(m.settings)["gameplay"] as Dictionary).get("confirm_sell", false))
	if confirm and m.op_msg != "Press Demolish again to confirm":
		m.op_msg = "Press Demolish again to confirm"
		m._rebuild_ui()
		return
	m.op_msg = ""
	m.op_sel = ""
	m.op_moving = false
	if who.begins_with("d"):
		m.meta_act(Outpost.remove_decor(m.save, who.substr(1)))
	else:
		m.meta_act(Outpost.demolish(m.save, who, m.now()))


static func rotate(m) -> void:
	if m.op_arm != "" or m.op_moving:
		m.op_rot = (m.op_rot + 1) % 2
		m._rebuild_ui()


static func upgrade(m) -> void:
	var who: String = m.op_sel
	if who == "" or who.begins_with("d") or who.begins_with("plot"):
		return
	m.meta_act(Outpost.upgrade(m.save, who, m.now()))


static func action(m, event: InputEvent) -> bool:
	var pr: Callable = func(a: String) -> bool: return InputMap.has_action(a) and event.is_action_pressed(a, false, true)
	if pr.call("ability_4"):
		rotate(m)
		return true
	if m.op_sel != "" and pr.call("tab_missions"):
		begin_move(m)
		return true
	if m.op_sel != "" and pr.call("sell"):
		demolish(m)
		return true
	if m.op_sel != "" and pr.call("upgrade"):
		upgrade(m)
		return true
	var ids: Array = CAT_IDS[m.op_cat]
	for k in mini(9, ids.size()):
		if pr.call("hotbar_%d" % (k + 1)):
			arm(m, String(ids[k]))
			return true
	for d in [["cursor_up", Vector2i(0, -1)], ["cursor_down", Vector2i(0, 1)], ["cursor_left", Vector2i(-1, 0)], ["cursor_right", Vector2i(1, 0)]]:
		if pr.call(String(d[0])):
			m.op_focus = Vector2i(clampi(m.op_focus.x + (d[1] as Vector2i).x, -PLAZA_W, OutpostDB.W - 1), clampi(m.op_focus.y + (d[1] as Vector2i).y, 0, OutpostDB.H - 1))
			m._rebuild_ui()
			return true
	if pr.call("confirm"):
		click(m, m.op_focus)
		return true
	return false


# ===================================================================== build
static func build(m) -> void:
	var s: Dictionary = m.save
	var o: Dictionary = _o(m)
	var pr: Rect2 = pal_rect(m)
	var x: float = pr.position.x + 12.0
	var w: float = pr.size.x - 24.0
	# category tabs
	var cw: float = (w - 12.0) / 3.0
	for k in CATS.size():
		var cat: String = String((CATS[k] as Array)[0])
		Kit.btn(m, String((CATS[k] as Array)[1]), Rect2(x + float(k % 3) * (cw + 6.0), pr.position.y + 98 + float(k / 3) * 50.0, cw, 46), func() -> void: m.op_cat = cat; m._rebuild_ui(), "Build category: %s" % String((CATS[k] as Array)[1]), true, Kit.RUST if m.op_cat == cat else Kit.NEUTRAL, "OPCAT " + cat, String((CATS[k] as Array)[2]), 14)
	# palette entries
	var ids: Array = CAT_IDS[m.op_cat]
	for k in ids.size():
		var id: String = ids[k]
		var r: Rect2 = pal_entry(m, k)
		var cc: Dictionary = cost_of(id)
		var lim_ok: bool = is_decor(id) or Outpost.count_of(o, id) < Outpost.limit_of(s, id)
		var ok: bool = Outpost.can_afford(s, int(cc["coins"])) and lim_ok
		var tip: String = "%s\n%s\n%s coins%s  ·  click, then click the map (or drag it there)" % [name_of(id), String(DESC.get(id, "Decor: +1% Charm per 10 pieces; tags buff neighbours")), Kit.fmt(float(cc["coins"])), ("" if is_decor(id) else "  ·  power %d" % int(OutpostDB.get_def(id).get("power", 0)))]
		Kit.hit(m, r, func() -> void: _press_palette(m, id), tip, "OPBUILD " + id, ok, Kit.GREEN)
	# selected panel buttons
	var sr: Rect2 = sel_rect(m)
	var who: String = m.op_sel
	var bw: float = (sr.size.x - 30.0) / 3.0
	var by: float = sr.end.y - 52.0
	if who == "relay":
		Kit.btn(m, "Upgrade  %s" % Kit.fmt(float(Outpost.relay_cost(int(o["relay_lvl"])))), Rect2(sr.position.x + 10, by, sr.size.x - 20, 44), func() -> void: upgrade(m), "Relay Lv%d -> %d\n%s" % [int(o["relay_lvl"]), int(o["relay_lvl"]) + 1, _delta_text(upgrade_delta(s, "relay"))], Outpost.can_upgrade(s, "relay"), Kit.GREEN, "OP UPGRADE", "cur_coin", 15)
	elif who.begins_with("plot:"):
		var k2: int = int(who.substr(5))
		var pc: Dictionary = Outpost.plot_cost(s)
		var adj: bool = Outpost.plot_adjacent(o, k2)
		Kit.btn(m, "Buy  %s coins" % Kit.fmt(float(pc["coins_alt"])), Rect2(sr.position.x + 10, by, bw * 1.5, 44), func() -> void: m.op_sel = ""; m.meta_act(Outpost.unlock_plot(m.save, k2, "coins")), "Open this plot for coins", adj and int(s["coins"]) >= int(pc["coins_alt"]), Kit.GOLD, "OP PLOT COINS", "cur_coin", 15)
	elif who != "":
		var is_d: bool = who.begins_with("d")
		if not is_d:
			var b: Dictionary = o["buildings"][who]
			var bid: String = String(b["id"])
			if OutpostDB.GENERATORS.has(bid):
				Kit.btn(m, "Collect", Rect2(sr.position.x + 10, by - 50, bw, 44), func() -> void: m.meta_act(Outpost.collect(m.save, who, m.now())), "Collect what this building stored", float(b["stored"]) >= 1.0, Kit.GOLD, "OP COLLECT", "ui_collect", 15)
			var uc: int = Outpost.cost(bid, int(b["lvl"]))
			Kit.btn(m, "Upgrade  %s" % Kit.fmt(float(uc)), Rect2(sr.position.x + 20 + bw, by - 50, bw * 2.0, 44), func() -> void: upgrade(m), "Lv%d -> %d: %s coins (max Lv%d at this Relay level)\n%s" % [int(b["lvl"]), int(b["lvl"]) + 1, Kit.fmt(float(uc)), Outpost.max_lvl(s, bid), _delta_text(upgrade_delta(s, who))], Outpost.can_upgrade(s, who), Kit.GREEN, "OP UPGRADE", "cur_coin", 15)
			if bid == "research":
				Kit.btn(m, "Open", Rect2(sr.position.x + 10, by - 50, bw, 44), func() -> void: m.set_tab("research"), "Open the Research Lab", true, Kit.LAB, "OP OPEN RESEARCH", "icon_lab", 15)
		Kit.btn(m, "Move", Rect2(sr.position.x + 10, by, bw, 44), func() -> void: begin_move(m), "Pick it up and click a new spot (R rotates)", true, Kit.GEM if m.op_moving else Kit.NEUTRAL, "OP MOVE", "ui_move", 15)
		Kit.btn(m, "Rotate", Rect2(sr.position.x + 15 + bw, by, bw, 44), func() -> void: _rotate_selected(m), "Rotate in place (where it fits)", true, Kit.NEUTRAL, "OP ROTATE", "ui_rotate", 15)
		Kit.btn(m, "Demolish", Rect2(sr.position.x + 20 + bw * 2.0, by, bw, 44), func() -> void: demolish(m), "Remove it: refunds half (all if still queued)", true, Kit.ENEMY, "OP DEMOLISH", "ui_demolish", 15)
	# blueprints
	var bp: Rect2 = bp_rect(m)
	var b4: float = (bp.size.x - 18.0) / 4.0
	var bps: Array = o["blueprints"]
	Kit.btn(m, "Save", Rect2(bp.position.x, bp.position.y + 30, b4, 40), func() -> void: m.meta_act(Outpost.save_blueprint(m.save, "Layout %d" % (bps.size() + 1))), "Save the current layout as a blueprint (max %d)" % Outpost.BLUEPRINTS_MAX, bps.size() < Outpost.BLUEPRINTS_MAX, Kit.NEUTRAL, "BP SAVE", "ui_blueprint", 14)
	Kit.btn(m, "Export", Rect2(bp.position.x + b4 + 6, bp.position.y + 30, b4, 40), func() -> void: _export(m), "Copy the layout as a text code (clipboard)", true, Kit.NEUTRAL, "BP EXPORT", "", 14)
	Kit.btn(m, "Import", Rect2(bp.position.x + 2.0 * (b4 + 6), bp.position.y + 30, b4, 40), func() -> void: _import(m), "Rebuild a layout code from the clipboard with buildings you own", true, Kit.NEUTRAL, "BP IMPORT", "", 14)
	for k in mini(bps.size(), 5):
		var lay: Array = (bps[k] as Dictionary)["layout"]
		Kit.btn(m, "%d" % (k + 1), Rect2(bp.position.x + 3.0 * (b4 + 6) + float(k) * (b4 / 5.0 + 0.5), bp.position.y + 30, b4 / 5.0 - 2.0, 40), func() -> void: m.meta_act(Outpost.load_blueprint(m.save, lay, m.now())["ev"]), "Load blueprint '%s' (moves buildings you own into it)" % String((bps[k] as Dictionary)["name"]), true, Kit.EDGE, "BP LOAD %d" % k, "", 13)
	# collect all (header strip; builds are instant, so no builder queue)
	var hr: Rect2 = head_rect(m)
	Kit.btn(m, "Collect all", Rect2(hr.end.x - 190, hr.position.y + 2, 190, hr.size.y - 4), func() -> void: m.meta_act(Outpost.collect_all(m.save, m.now())), "Collect every building at once (Relay Lv3)" if Outpost.collect_all_unlocked(s) else "Collect all unlocks at Relay Lv3 — click buildings to collect them one by one", Outpost.collect_all_unlocked(s), Kit.GOLD, "OP COLLECT ALL", "ui_collect", 16)


static func _rotate_selected(m) -> void:
	var who: String = m.op_sel
	var o: Dictionary = _o(m)
	if who == "" or who == "relay" or who.begins_with("plot"):
		return
	if who.begins_with("d"):
		var d: Dictionary = o["decor"][who.substr(1)]
		m.meta_act(Outpost.move_decor(m.save, who.substr(1), int(d["x"]), int(d["y"]), (int(d["rot"]) + 1) % 2))
	else:
		var b: Dictionary = o["buildings"][who]
		var ev: Array = Outpost.move(m.save, who, int(b["x"]), int(b["y"]), (int(b["rot"]) + 1) % 2, m.now())
		if ev.is_empty():
			m.op_msg = "No room to rotate here — Move it first"
		m.meta_act(ev)


static func _export(m) -> void:
	m.op_bp_text = Outpost.export_layout(_o(m))
	DisplayServer.clipboard_set(m.op_bp_text)
	m.op_msg = "Layout code copied to the clipboard"
	m._rebuild_ui()


static func _import(m) -> void:
	var txt: String = DisplayServer.clipboard_get()
	if txt.strip_edges() == "" and m.op_bp_text != "":
		txt = m.op_bp_text
	var lay: Array = Outpost.import_layout(txt)
	if lay.is_empty():
		m.op_msg = "No layout code on the clipboard"
		m._rebuild_ui()
		return
	var res: Dictionary = Outpost.load_blueprint(m.save, lay, m.now())
	m.op_msg = "Imported: %d placed, %d missing" % [lay.size() - (res["missing"] as Array).size(), (res["missing"] as Array).size()]
	m.meta_act(res["ev"])


static func pal_entry(m, k: int) -> Rect2:
	var pr: Rect2 = pal_rect(m)
	var ids: Array = CAT_IDS[m.op_cat]
	var top: float = pr.position.y + 202.0
	var avail: float = sel_rect(m).position.y - top - 10.0
	var cols: int = 3 if ids.size() > 9 else (2 if ids.size() > 4 else 1)
	var rows: int = int(ceil(float(ids.size()) / float(cols)))
	var h: float = minf(64.0, avail / float(maxi(1, rows)) - 4.0)
	var w: float = (pr.size.x - 24.0 - 6.0 * float(cols - 1)) / float(cols)
	return Rect2(pr.position.x + 12 + float(k % cols) * (w + 6.0), top + float(k / cols) * (h + 4.0), w, h)


static func sel_rect(m) -> Rect2:
	var pr: Rect2 = pal_rect(m)
	return Rect2(pr.position.x + 12, pr.end.y - 490, pr.size.x - 24, 380)


static func bp_rect(m) -> Rect2:
	var pr: Rect2 = pal_rect(m)
	return Rect2(pr.position.x + 12, pr.end.y - 98, pr.size.x - 24, 86)


# ===================================================================== tips
static func map_tip(m, p: Vector2) -> String:
	var s: Dictionary = m.save
	var o: Dictionary = _o(m)
	var c: Vector2i = cell_at(m, p)
	var lm: String = landmark_at(c)
	if lm != "":
		var la: Array = _landmark(lm)
		return "%s\n%s\nClick to open" % [String(la[1]), String(la[4])]
	if not Outpost.in_map(c):
		return ""
	var pl: int = Outpost.plot_of(c)
	if pl >= 0 and not (o["plots"] as Array).has(pl):
		var pc: Dictionary = Outpost.plot_cost(s)
		return "Locked land (plot %d)\nCost: %s coins\nWhat lies inside is unknown until you buy it\n%s" % [pl + 1, Kit.fmt(float(pc["coins_alt"])), "Click to select, then Buy" if Outpost.plot_adjacent(o, pl) else "Must touch open land"]
	var who: String = String(Outpost.occupancy(o).get(c, ""))
	if who == "relay":
		return "Core Relay  Lv%d\n%s\nPower %d / %d" % [int(o["relay_lvl"]), String(DESC["relay"]), int(Outpost.demand(o)), int(Outpost.supply(o))]
	if who.begins_with("d"):
		var d: Dictionary = o["decor"][who.substr(1)]
		return "%s (decor, %s)" % [name_of(String(d["id"])), String((OutpostDB.DECOR[String(d["id"])] as Dictionary)["tag"])]
	if who != "":
		return building_text(m, who)
	if OutpostDB.VEINS.has(c):
		return "Crystal Vein — the Deep Mine must stand on one"
	if OutpostDB.BLOCKED.has(c):
		return "Rock — can't build here"
	return ""


static func building_text(m, uid: String) -> String:
	var s: Dictionary = m.save
	var o: Dictionary = _o(m)
	var b: Dictionary = o["buildings"][uid]
	var id: String = String(b["id"])
	var con: Dictionary = Outpost.connected(o)
	var lines: Array = ["%s  Lv%d%s" % [name_of(id), int(b["lvl"]), "" if bool(b["built"]) else "  (building)"], String(DESC.get(id, ""))]
	if OutpostDB.SCAVENGERS.has(id):
		lines.append("%s  ·  stored %d / %d" % [scav_text(id, Outpost.rate(s, uid, con)), int(float(b["stored"])), int(Outpost.cap(s, uid, con))])
	elif OutpostDB.GENERATORS.has(id):
		var res: String = String(OutpostDB.get_def(id)["res"])
		lines.append("%s %s/h  ·  stored %d / %d" % [_rate_txt(Outpost.rate(s, uid, con)), res, int(float(b["stored"])), int(Outpost.cap(s, uid, con))])
	if OutpostDB.CORE_IDS.has(id) and bool(con.get(uid, false)) and bool(b["built"]):
		var part: Dictionary = Outpost.core_part(o, uid, con)
		var ct: Array = []
		for k in part.keys():
			ct.append(core_text(String(k), float(part[k])))
		lines.append("Core: " + ", ".join(PackedStringArray(ct)))
	if AdjDB.receives(id):
		var lb: Dictionary = Outpost.layout_bonus(o, uid, con)
		if float(lb["total"]) != 0.0:
			lines.append("Layout bonus %+d%%" % int(round(float(lb["total"]) * 100.0)))
	if id != "conduit":
		lines.append("Linked to the Relay" if bool(con.get(uid, false)) else "NOT LINKED — connect it with Conduits")
	return "\n".join(PackedStringArray(lines))


static func _rate_txt(r: float) -> String:
	return Kit.fmt(r) if r >= 10.0 else "%.2f" % r


## "+4.0% damage" style readout of one Core stat.
static func core_text(key: String, v: float, with_label: bool = true) -> String:
	var f: Array = CORE_FMT.get(key, [key, "+%.2f", 1.0])
	var num: String = String(f[1]) % (v * float(f[2]))
	return ("%s %s" % [num, String(f[0]).to_lower()]) if with_label else num


## Scavenger pace: "1 item / 5.5 h" (or "paused" when it is not producing).
static func scav_text(id: String, rate: float) -> String:
	var nm: String = String(SCAV_NAME.get(String(OutpostDB.get_def(id).get("res", "")), "find"))
	return ("1 %s / %.1f h" % [nm, 1.0 / rate]) if rate > 0.0 else "paused"


# ===================================================================== draw
static func draw(m, _cr: Rect2) -> void:
	var s: Dictionary = m.save
	var o: Dictionary = _o(m)
	var mr: Rect2 = map_rect(m)
	Kit.panel(m, mr.grow(4), Kit.EDGE, Kit.BG)
	_draw_map(m, s, o, mr)
	# mask map overflow (panned / zoomed) outside its frame
	var cr: Rect2 = m.content_rect()
	m.draw_rect(Rect2(cr.position.x, cr.position.y, cr.size.x, mr.position.y - cr.position.y - 3), Kit.BG)
	m.draw_rect(Rect2(cr.position.x, mr.position.y - 3, mr.position.x - cr.position.x - 3, mr.size.y + 6), Kit.BG)
	m.draw_rect(Rect2(mr.end.x + 3, mr.position.y - 3, cr.end.x - mr.end.x - 3, mr.size.y + 6), Kit.BG)
	m.draw_rect(Rect2(cr.position.x, mr.end.y + 3, cr.size.x, cr.end.y - mr.end.y - 3), Kit.BG)
	m.draw_rect(mr.grow(4), Kit.EDGE, false, 2.0)
	_draw_map_header(m, s, o, mr)
	_draw_palette(m, s, o)


static func _draw_map(m, s: Dictionary, o: Dictionary, mr: Rect2) -> void:
	var c: float = cell_px(m)
	var con: Dictionary = Outpost.connected(o)
	var occ: Dictionary = Outpost.occupancy(o)
	var t: int = m.now()
	# terrain (V2 P6c neon blueprint): open land navy with a cyan grid and a
	# glowing frontier edge; locked land near-black; rocks as slate boulders
	var mask: PackedByteArray = open_mask(m)
	var grid := Color(Kit.CYAN, 0.07)
	var edge := Color(Kit.CYAN, 0.55)
	var ew: float = maxf(1.5, c * 0.05)
	for y in OutpostDB.H:
		for x in OutpostDB.W:
			var cv := Vector2i(x, y)
			var r: Rect2 = cell_rect(m, x, y)
			if not mr.intersects(r):
				continue
			var open: bool = mask[y * OutpostDB.W + x] == 1
			if open:
				m.draw_rect(r, Color("0f182d") if (x + y) % 2 == 0 else Color("111b33"))
				m.draw_rect(r, grid, false, 1.0)
				if OutpostDB.BLOCKED.has(cv):
					_rock(m, r, x, y)
				elif OutpostDB.VEINS.has(cv):
					Kit.icon(m, "op_vein", r)
				# frontier edge where open land meets locked land / the map edge
				if y == 0 or mask[(y - 1) * OutpostDB.W + x] == 0:
					m.draw_line(r.position, Vector2(r.end.x, r.position.y), edge, ew)
				if y == OutpostDB.H - 1 or mask[(y + 1) * OutpostDB.W + x] == 0:
					m.draw_line(Vector2(r.position.x, r.end.y), r.end, edge, ew)
				if x == 0 or mask[y * OutpostDB.W + x - 1] == 0:
					m.draw_line(r.position, Vector2(r.position.x, r.end.y), edge, ew)
				if x == OutpostDB.W - 1 or mask[y * OutpostDB.W + x + 1] == 0:
					m.draw_line(Vector2(r.end.x, r.position.y), r.end, edge, ew)
			else:
				m.draw_rect(r, Color("070b15"))   # FB1: resources hidden until bought
				m.draw_rect(r, Color(1, 1, 1, 0.025), false, 1.0)
	# locked plots: buyable ones (touching open land) show a gold frame + price
	var price: String = Kit.fmt(float(Outpost.plot_cost(s)["coins"]))
	for k in OutpostDB.PLOTS.size():
		if (o["plots"] as Array).has(k):
			continue
		var pr: Rect2i = OutpostDB.PLOTS[k]
		var rr: Rect2 = cell_rect(m, pr.position.x, pr.position.y, pr.size.x, pr.size.y)
		if not mr.intersects(rr):
			continue
		var sel: bool = m.op_sel == "plot:%d" % k
		var buy: bool = Outpost.plot_adjacent(o, k)
		m.draw_rect(rr.grow(-3), Kit.GOLD if sel else (Color(Kit.GOLD, 0.35) if buy else Color(1, 1, 1, 0.08)), false, 3.0 if sel else 1.5)
		var isz: float = minf(c * 1.2, minf(rr.size.x, rr.size.y) - 8.0)
		var ic: Vector2 = rr.get_center() - Vector2(0.0, 10.0 if buy else 0.0)
		Kit.icon(m, "op_plot_locked", Rect2(ic - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), Color(1, 1, 1, 0.8 if buy else 0.25))
		if buy and rr.size.y > isz + 30.0:
			Kit.th(m, price, Vector2(ic.x, ic.y + isz * 0.5 + 20.0), 15, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
	# Relay
	var rl: int = int(o["relay_lvl"])
	var rrr: Rect2 = cell_rect(m, OutpostDB.RELAY.x, OutpostDB.RELAY.y, 3, 3)
	_bld(m, "relay", rl, rrr.grow(-2))
	if m.op_sel == "relay":
		Kit.outline(m, rrr, Kit.GOLD)
	# buildings
	for uid in o["buildings"].keys():
		var b: Dictionary = o["buildings"][uid]
		if int(b["x"]) < 0:
			continue
		var id: String = String(b["id"])
		var sz: Vector2i = OutpostDB.size_of(id, int(b["rot"]))
		var r2: Rect2 = cell_rect(m, int(b["x"]), int(b["y"]), sz.x, sz.y)
		var moving: bool = m.op_moving and m.op_sel == String(uid)
		var linked: bool = bool(con.get(String(uid), false))
		if id == "conduit":
			_draw_conduit(m, o, occ, int(b["x"]), int(b["y"]), r2, linked)
			if m.op_sel == String(uid):
				Kit.outline(m, r2, Kit.GOLD)
			continue
		_bld(m, id, int(b["lvl"]), r2.grow(-2), linked, 0.35 if moving else (1.0 if bool(b["built"]) else 0.5))
		if not bool(b["built"]):
			var job: Dictionary = _job_of(o, String(uid))
			Kit.icon(m, "op_timer", Rect2(r2.get_center() - Vector2(c * 0.3, c * 0.3), Vector2(c * 0.6, c * 0.6)))
			if not job.is_empty():
				Kit.t(m, Kit.dur(int(job["ends_at"]) - t), r2.get_center() + Vector2(0, c * 0.5), 14, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)
		elif not _job_of(o, String(uid)).is_empty():
			Kit.icon(m, "op_builder", Rect2(r2.position + Vector2(4, 4), Vector2(c * 0.45, c * 0.45)))
		if not linked:
			Kit.icon(m, "op_plug", Rect2(r2.end - Vector2(c * 0.45, c * 0.45), Vector2(c * 0.4, c * 0.4)))
		# level pip + storage bar
		Kit.panel(m, Rect2(r2.position.x + 4, r2.position.y + 4, 30, 20), Kit.EDGE, Color(0, 0, 0, 0.7), 1)
		Kit.t(m, "%d" % int(b["lvl"]), Vector2(r2.position.x + 19, r2.position.y + 19), 14, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
		if OutpostDB.GENERATORS.has(id) and bool(b["built"]):
			var cp: float = maxf(0.001, Outpost.cap(s, String(uid), con))
			var fr: float = clampf(float(b["stored"]) / cp, 0.0, 1.0)
			var bcol: Color = Kit.GOLD if id == "mill" else (Kit.SCRAP if id == "refinery" else Kit.GEM)
			Kit.bar(m, Rect2(r2.position.x + 6, r2.end.y - 12, r2.size.x - 12, 7), fr, bcol if fr < 0.999 else Kit.ENEMY)
			if float(b["stored"]) >= 1.0:
				var bounce: float = 3.0 * sin(m.t_anim * 4.0 + float(int(String(uid))))
				Kit.icon(m, "ui_collect", Rect2(r2.get_center() + Vector2(-c * 0.22, -r2.size.y * 0.5 - c * 0.2 + bounce), Vector2(c * 0.44, c * 0.44)))
		if m.op_sel == String(uid):
			Kit.outline(m, r2, Kit.GOLD)
	# decor
	for du in o["decor"].keys():
		var d: Dictionary = o["decor"][du]
		var dsz: Vector2i = size_of(String(d["id"]), int(d["rot"]))
		var r3: Rect2 = cell_rect(m, int(d["x"]), int(d["y"]), dsz.x, dsz.y)
		var mv: bool = m.op_moving and m.op_sel == "d" + String(du)
		_art(m, String(d["id"]), r3.grow(-2), Color(1, 1, 1, 0.35 if mv else 1.0))
		if m.op_sel == "d" + String(du):
			Kit.outline(m, r3, Kit.GOLD)
	# V2 P6c: a selected building shows its adjacency links
	var sel: String = String(m.op_sel)
	if m.op_arm == "" and not m.op_moving and (o["buildings"] as Dictionary).has(sel):
		var lk: Dictionary = links(m, sel)
		_draw_links(m, building_rect(m, sel), lk["ins"], lk["outs"])
	_draw_ghost(m, s, o, mr)
	# V2 P6: a requirement jump pulses its building for 2.5 s
	var pt: float = float(m.t_anim) - float(m.op_pulse_t)
	if String(m.op_pulse) != "" and pt < 2.5:
		var pr2: Rect2 = building_rect(m, String(m.op_pulse))
		if pr2.size.x > 0.0:
			var k2: float = 0.5 + 0.5 * sin(pt * 9.0)
			Kit.panel_glow(m, pr2.grow(4.0 + 6.0 * k2), Kit.GOLD, Color(0, 0, 0, 0), 1.0 + 1.5 * k2, 3)
	# pad / keyboard cursor
	if String(m.last_device) == "pad":
		Kit.outline(m, cell_rect(m, m.op_focus.x, m.op_focus.y), Kit.GEM, 2.0)
## FB1 Command Plaza: the buildings that open the Core Bay, Crates,
## Research and Cards screens (click one to enter).
static func _draw_map_header(m, s: Dictionary, o: Dictionary, mr: Rect2) -> void:
	var con: Dictionary = Outpost.connected(o)
	var rl: int = int(o["relay_lvl"])
	var eff: float = Outpost.efficiency(o, con)
	var hr: Rect2 = head_rect(m)
	Kit.panel(m, Rect2(hr.position.x, hr.position.y, hr.size.x - 200, hr.size.y), Kit.EDGE, Kit.PANEL, 1)
	var x: float = hr.position.x + 14.0
	var cy: float = hr.get_center().y
	var prod: Dictionary = Outpost.production(s)
	var items: Array = [
		["op_relay_1", "Relay Lv%d" % rl, Kit.TEXT, "Core Relay level: sets power, building limits and max levels"],
		["bolt", "Power %d / %d" % [int(Outpost.demand(o, con)), int(Outpost.supply(o))], Kit.TEXT if eff >= 0.999 else Kit.GOLD, "Linked buildings draw power from the Relay; over budget, every generator slows down%s" % ((" (output x%.2f)" % eff) if eff < 0.999 else "")],
		["cur_coin", "%s/h" % _rate_txt(float(prod["coins"])), Kit.GOLD, "Coins per hour from linked Mills and Deep Mines"],
		["cur_scrap", "%s/h" % _rate_txt(float(prod["scrap"])), Kit.SCRAP, "Scrap per hour from Refineries"],
		["dc_lamp", "Charm +%d%%" % int(round(Outpost.charm(o) * 100.0)), Kit.TEXT, "+1% production per 10 decor pieces (max +10%)"],
	]
	for it in items:
		var a: Array = it
		var lw: float = 34.0 + m.font.get_string_size(String(a[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		Kit.icon(m, String(a[0]), Rect2(x, cy - 13, 26, 26))
		Kit.t(m, String(a[1]), Vector2(x + 32, cy + 6), 16, a[2], HORIZONTAL_ALIGNMENT_LEFT, lw)
		m.stat_tips.append([Rect2(x - 4, hr.position.y, lw + 8, hr.size.y), String(a[3])])
		x += lw + 22.0
	Kit.panel(m, Rect2(mr.end.x - 560, mr.end.y - 32, 552, 26), Color(0, 0, 0, 0), Color(0.05, 0.06, 0.08, 0.7), 0)
	Kit.t(m, "Click a building to select it  ·  right-drag pans  ·  wheel zooms", Vector2(mr.end.x - 14, mr.end.y - 13), 14, Color(Kit.DIM, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, 560.0)
	if m.op_msg != "":
		Kit.panel(m, Rect2(mr.get_center().x - 260, mr.end.y - 60, 520, 36), Kit.GOLD, Color(0.14, 0.12, 0.06, 0.92))
		Kit.t(m, m.op_msg, Vector2(mr.get_center().x, mr.end.y - 36), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 500.0)




static func _job_of(o: Dictionary, uid: String) -> Dictionary:
	for j in o["queue"]:
		if String((j as Dictionary)["uid"]) == uid:
			return j
	return {}


## Conduit hub + a stub toward every linked neighbour (auto-tiling).
static func _draw_conduit(m, o: Dictionary, occ: Dictionary, x: int, y: int, r: Rect2, linked: bool) -> void:
	var mod: Color = Color.WHITE if linked else Color(1, 0.55, 0.55)
	var dirs: Array = [[Vector2i(0, -1), "op_conduit_n"], [Vector2i(1, 0), "op_conduit_e"], [Vector2i(0, 1), "op_conduit_s"], [Vector2i(-1, 0), "op_conduit_w"]]
	for d in dirs:
		var n: Vector2i = Vector2i(x, y) + (d[0] as Vector2i)
		var who: String = String(occ.get(n, ""))
		if who != "" and not who.begins_with("d"):
			Kit.icon(m, String(d[1]), r, mod)
	Kit.icon(m, "op_conduit", r, mod)


## Placement / move preview: footprint, validity, link line, adjacency delta.
static func _draw_ghost(m, s: Dictionary, o: Dictionary, mr: Rect2) -> void:
	var id: String = m.op_arm
	var skip: String = ""
	if id == "" and m.op_moving and m.op_sel != "":
		skip = m.op_sel
		id = String((o["decor"][skip.substr(1)] as Dictionary)["id"]) if skip.begins_with("d") else String((o["buildings"][skip] as Dictionary)["id"])
	if id == "":
		return
	var p: Vector2 = m.mouse_pos
	var cell: Vector2i = m.op_focus
	if mr.has_point(p):
		cell = cell_at(m, p)
	elif String(m.last_device) != "pad":
		return
	var sz: Vector2i = size_of(id, m.op_rot)
	var r: Rect2 = cell_rect(m, cell.x, cell.y, sz.x, sz.y)
	var info: Dictionary = preview(m, id, cell, m.op_rot, skip)
	var ok: bool = String(info["err"]) == ""
	m.draw_rect(r, Color(Kit.GREEN, 0.22) if ok else Color(Kit.ENEMY, 0.25))
	_bld(m, id, 1, r.grow(-3), ok and (is_decor(id) or bool(info["linked"])), 0.7)
	m.draw_rect(r, Kit.GREEN if ok else Kit.ENEMY, false, 3.0)
	if ok and not is_decor(id):
		var relay_c: Vector2 = cell_rect(m, OutpostDB.RELAY.x, OutpostDB.RELAY.y, 3, 3).get_center()
		var linked: bool = bool(info["linked"])
		var col: Color = Color(Kit.GREEN, 0.8) if linked else Color(Kit.ENEMY, 0.8)
		if linked:
			m.draw_line(r.get_center(), relay_c, col, 2.0)
		else:
			var a: Vector2 = r.get_center()
			var steps: int = int(a.distance_to(relay_c) / 14.0)
			for k in steps:
				if k % 2 == 0:
					m.draw_line(a.lerp(relay_c, float(k) / float(steps)), a.lerp(relay_c, float(k + 1) / float(steps)), col, 2.0)
	if ok:
		_draw_links(m, r, info["ins"], info["outs"])
	var label: String = String(ERR.get(String(info["err"]), String(info["err"])))
	if ok:
		label = name_of(id)
		if not is_decor(id) and id != "conduit":
			label += "  ·  linked" if bool(info["linked"]) else "  ·  not linked (add Conduits)"
		if AdjDB.receives(id):
			label += "  ·  layout %+d%%" % int(round(float(info["bonus"]) * 100.0))
		if absf(float(info["delta"])) > 0.0001:
			label += "  ·  neighbours %+d%%" % int(round(float(info["delta"]) * 100.0))
	var lw: float = 20.0 + m.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	Kit.panel(m, Rect2(r.position.x, r.position.y - 34, lw, 30), Kit.GREEN if ok else Kit.ENEMY, Color(0.05, 0.06, 0.08, 0.92))
	Kit.t(m, label, Vector2(r.position.x + 10, r.position.y - 13), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, lw)
	m.set_meta("op_ghost", info)


## Pure preview on a copy of the Outpost block: validity, Relay link, the
## ghost's own layout bonus and parts, who feeds it (ins: {uid: share}) and
## how each neighbour's bonus moves (outs: {uid: delta}, summed in delta).
static func preview(m, id: String, c: Vector2i, rot: int, skip: String = "") -> Dictionary:
	var key: String = "%s|%d|%d|%d|%s|%d" % [id, c.x, c.y, rot, skip, _fp(_o(m))]
	var cache: Dictionary = m.get_meta("op_prev_cache", {})
	if String(cache.get("key", "")) == key:
		return cache["info"]
	var err: String = Outpost.place_error(m.save, id, c.x, c.y, rot, skip)
	var info: Dictionary = {"err": err, "linked": false, "bonus": 0.0, "delta": 0.0, "parts": {}, "ins": {}, "outs": {}}
	if err == "":
		var o: Dictionary = _o(m).duplicate(true)
		var before: Dictionary = _bonuses(o)
		var uid: String = skip
		if is_decor(id):
			uid = ""
			if skip == "":
				(o["decor"] as Dictionary)["ghost"] = {"id": id, "x": c.x, "y": c.y, "rot": rot % 2}
			else:
				var dd: Dictionary = o["decor"][skip.substr(1)]
				dd["x"] = c.x
				dd["y"] = c.y
		elif skip != "":
			var b: Dictionary = o["buildings"][skip]
			b["x"] = c.x
			b["y"] = c.y
			b["rot"] = rot % 2
		else:
			uid = Outpost._add_building(o, id, c.x, c.y, rot % 2, true)
		var con: Dictionary = Outpost.connected(o)
		if uid != "":
			info["linked"] = bool(con.get(uid, false))
			var lb: Dictionary = Outpost.layout_bonus(o, uid, con)
			if AdjDB.receives(id):
				info["bonus"] = float(lb["total"])
				info["parts"] = lb["parts"]
			info["ins"] = _ins(lb)
		var after: Dictionary = _bonuses(o)
		var outs: Dictionary = {}
		var dl: float = 0.0
		for k in after.keys():
			if String(k) == uid or (skip != "" and String(k) == skip):
				continue
			var dv: float = float(after[k]) - float(before.get(k, 0.0))
			if absf(dv) > 0.0001:
				outs[String(k)] = dv
				dl += dv
		info["outs"] = outs
		info["delta"] = dl
	m.set_meta("op_prev_cache", {"key": key, "info": info})
	return info


## Layout fingerprint for the preview / link caches: positions, build state,
## decor, Relay level, plots.
static func _fp(o: Dictionary) -> int:
	var parts: Array = [int(o["relay_lvl"]), (o["plots"] as Array).size()]
	for uid in o["buildings"].keys():
		var b: Dictionary = o["buildings"][uid]
		parts.append([String(uid), int(b["x"]), int(b["y"]), int(b["rot"]), bool(b["built"])])
	for du in o["decor"].keys():
		var d: Dictionary = o["decor"][du]
		parts.append([String(du), int(d["x"]), int(d["y"])])
	return hash(parts)


## Layout bonus of every receiving building (AdjDB.RECEIVERS).
static func _bonuses(o: Dictionary) -> Dictionary:
	var con: Dictionary = Outpost.connected(o)
	var out: Dictionary = {}
	for uid in o["buildings"].keys():
		var b: Dictionary = o["buildings"][uid]
		if AdjDB.receives(String(b["id"])) and int(b["x"]) >= 0:
			out[String(uid)] = float(Outpost.layout_bonus(o, String(uid), con)["total"])
	return out


## {source uid: share} of a layout_bonus result: a "once" part credits its
## first source, a stacking part splits evenly over its sources.
static func _ins(lb: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in (lb["srcs"] as Dictionary).keys():
		var who: Array = lb["srcs"][key]
		if who.is_empty():
			continue
		var v: float = float((lb["parts"] as Dictionary).get(key, 0.0))
		if AdjDB.is_once(String(key)):
			out[String(who[0])] = float(out.get(String(who[0]), 0.0)) + v
		else:
			for w in who:
				out[String(w)] = float(out.get(String(w), 0.0)) + v / float(who.size())
	return out


## Adjacency links of a placed building: {ins: {src: share}, outs: {dst:
## share}} (cached on the layout fingerprint).
static func links(m, uid: String) -> Dictionary:
	var o: Dictionary = _o(m)
	var key: String = "%s|%d" % [uid, _fp(o)]
	var cache: Dictionary = m.get_meta("op_link_cache", {})
	if String(cache.get("key", "")) == key:
		return cache["v"]
	var res: Dictionary = {"ins": {}, "outs": {}}
	if (o["buildings"] as Dictionary).has(uid):
		var con: Dictionary = Outpost.connected(o)
		var me: String = String((o["buildings"][uid] as Dictionary)["id"])
		if AdjDB.receives(me):
			res["ins"] = _ins(Outpost.layout_bonus(o, uid, con))
		for k in o["buildings"].keys():
			var b: Dictionary = o["buildings"][k]
			if String(k) == uid or not AdjDB.receives(String(b["id"])) or int(b["x"]) < 0:
				continue
			var share: float = float(_ins(Outpost.layout_bonus(o, String(k), con)).get(uid, 0.0))
			if absf(share) > 0.0001:
				res["outs"][String(k)] = share
	m.set_meta("op_link_cache", {"key": key, "v": res})
	return res


## Connector lines (Islanders-style): solid from `from` to each neighbour it
## changes (chip on the neighbour), dashed from each source feeding it (chip
## near `from`). Green = buff, red = nerf; arrowheads point at the receiver.
static func _draw_links(m, from: Rect2, ins: Dictionary, outs: Dictionary) -> void:
	var c0: Vector2 = from.get_center()
	for uid in outs.keys():
		var v: float = float(outs[uid])
		var r: Rect2 = building_rect(m, String(uid))
		if r.size.x <= 0.0 or absf(v) < 0.005:
			continue
		var col: Color = Kit.GREEN if v > 0.0 else Kit.ENEMY
		_link_line(m, c0, r.get_center(), col, false)
		_chip(m, r.get_center(), "%+d%%" % int(round(v * 100.0)), col)
	for uid in ins.keys():
		var v2: float = float(ins[uid])
		var r2: Rect2 = building_rect(m, String(uid))
		if r2.size.x <= 0.0 or absf(v2) < 0.005:
			continue
		var col2: Color = Kit.GREEN if v2 > 0.0 else Kit.ENEMY
		_link_line(m, r2.get_center(), c0, col2, true)
		_chip(m, c0.lerp(r2.get_center(), 0.42), "%+d%%" % int(round(v2 * 100.0)), col2)


static func _link_line(m, a: Vector2, b: Vector2, col: Color, dashed: bool) -> void:
	var ln: float = a.distance_to(b)
	if ln < 4.0:
		return
	var d: Vector2 = (b - a) / ln
	var tip: Vector2 = b - d * minf(ln * 0.3, 18.0)
	m.draw_line(a, tip, Color(col, 0.25), 6.0)
	if dashed:
		var n: int = maxi(1, int(a.distance_to(tip) / 10.0))
		for k in n:
			if k % 2 == 0:
				m.draw_line(a.lerp(tip, float(k) / float(n)), a.lerp(tip, float(k + 1) / float(n)), col, 2.5)
	else:
		m.draw_line(a, tip, col, 2.5)
	var nn := Vector2(-d.y, d.x)
	m.draw_colored_polygon(PackedVector2Array([tip + d * 9.0, tip - nn * 6.0, tip + nn * 6.0]), col)


static func _chip(m, c: Vector2, txt: String, col: Color) -> void:
	var w: float = 14.0 + m.font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var r := Rect2(c - Vector2(w * 0.5, 12.0), Vector2(w, 24.0))
	Kit.panel(m, r, col, Color(0.03, 0.05, 0.09, 0.94), 2)
	Kit.th(m, txt, Vector2(c.x, c.y + 6.0), 15, col, HORIZONTAL_ALIGNMENT_CENTER, w)


static func _draw_palette(m, s: Dictionary, o: Dictionary) -> void:
	var pr: Rect2 = pal_rect(m)
	Kit.panel(m, pr, Kit.EDGE, Kit.PANEL)
	var x: float = pr.position.x + 16.0
	var w: float = pr.size.x - 32.0
	Kit.icon(m, "op_builder", Rect2(x - 2, pr.position.y + 10, 40, 40))
	Kit.t(m, "BUILD", Vector2(x + 46, pr.position.y + 40), 26, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
	var cred: int = int(o.get("credit", 0))
	Kit.t(m, ("Build credit %s coins" % Kit.fmt(float(cred))) if cred > 0 else "Pick one, then click the map", Vector2(x + 140, pr.position.y + 38), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 140)
	Kit.t(m, "Categories", Vector2(x, pr.position.y + 88), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	# entries
	var ids: Array = CAT_IDS[m.op_cat]
	for k in ids.size():
		var id: String = ids[k]
		var r: Rect2 = pal_entry(m, k)
		var cc: Dictionary = cost_of(id)
		var lim: int = 99 if is_decor(id) else Outpost.limit_of(s, id)
		var n: int = 0 if is_decor(id) else Outpost.count_of(o, id)
		var ok: bool = Outpost.can_afford(s, int(cc["coins"])) and n < lim
		var armed: bool = m.op_arm == id
		Kit.panel(m, r, Kit.GOLD if armed else (Kit.EDGE2 if ok else Kit.EDGE), Kit.CARD if ok else Kit.PANEL, 3 if armed else 1)
		var ft: float = float(m.t_anim) - float(m.op_flash_t)
		if String(m.op_flash) == id and ft < 2.5:
			Kit.panel_glow(m, r.grow(3.0), Kit.GOLD, Color(Kit.GOLD, 0.10), 1.0 + 1.5 * (0.5 + 0.5 * sin(ft * 9.0)), 3)
		var isz: float = r.size.y - 10.0
		_bld(m, id, 1, Rect2(r.position.x + 5, r.position.y + 5, isz, isz), true, 1.0 if ok else 0.45)
		var tx: float = r.position.x + isz + 12.0
		var tw: float = r.end.x - tx - 6.0
		Kit.t(m, name_of(id), Vector2(tx, r.position.y + r.size.y * 0.42), 15 if r.size.x < 250.0 else 17, Kit.TEXT if ok else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, tw)
		var sub: String = Kit.fmt(float(cc["coins"]))
		if not is_decor(id) and r.size.x >= 180.0:
			sub += "  ·  %d/%d" % [n, lim]
		Kit.icon(m, "cur_coin", Rect2(tx, r.position.y + r.size.y * 0.42 + 5, 16, 16))
		Kit.t(m, sub, Vector2(tx + 19, r.position.y + r.size.y * 0.42 + 18), 14, Kit.GOLD if ok else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, tw - 19)
	# selected
	var sr: Rect2 = sel_rect(m)
	Kit.panel(m, sr, Kit.EDGE, Kit.PANEL2)
	_draw_selected(m, s, o, sr)
	# blueprints
	var bp: Rect2 = bp_rect(m)
	Kit.t(m, "BLUEPRINTS  (%d / %d)" % [(o["blueprints"] as Array).size(), Outpost.BLUEPRINTS_MAX], Vector2(bp.position.x, bp.position.y + 18), 15, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, bp.size.x)


static func _draw_selected(m, s: Dictionary, o: Dictionary, sr: Rect2) -> void:
	var x: float = sr.position.x + 12.0
	var w: float = sr.size.x - 24.0
	var who: String = m.op_sel
	if m.op_arm != "":
		Kit.t(m, "PLACING  " + name_of(m.op_arm), Vector2(x, sr.position.y + 30), 18, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
		Kit.wrap(m, String(DESC.get(m.op_arm, "Decor: every 10 pieces add +1% Charm; tags buff neighbours (lamps light Deep Mines, scholars speed research, training helps the Barracks).")), Vector2(x, sr.position.y + 48), 15, Kit.DIM, w, 4)
		Kit.wrap(m, "Click the map to place  ·  %s rotates  ·  right-click / %s cancels%s" % [Kit.hint(m, "ability_4"), Kit.hint(m, "cancel"), "  ·  stays armed: paint a line" if m.op_arm == "conduit" or is_decor(m.op_arm) else ""], Vector2(x, sr.position.y + 160), 14, Kit.TEXT, w, 3)
		return
	if who == "":
		Kit.t(m, "SELECT", Vector2(x, sr.position.y + 30), 18, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
		Kit.wrap(m, "Click a building to inspect it, or pick one from the palette to build. Buildings only work when linked to the Relay (directly or through Conduits). Neighbours matter: Mills love Mills, Refineries hate them, Warehouses stretch storage.", Vector2(x, sr.position.y + 50), 15, Kit.DIM, w, 8)
		return
	if who.begins_with("plot:"):
		var k: int = int(who.substr(5))
		var pc: Dictionary = Outpost.plot_cost(s)
		Kit.t(m, "LOCKED LAND  (plot %d)" % (k + 1), Vector2(x, sr.position.y + 30), 18, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
		Kit.wrap(m, "Expand the Outpost: more room for Mills, a second Crystal Vein and decor. Each plot costs more than the last." + ("" if Outpost.plot_adjacent(o, k) else "\nThis plot must touch open land first."), Vector2(x, sr.position.y + 50), 15, Kit.DIM, w, 5)
		Kit.t(m, "%s coins%s" % [Kit.fmt(float(pc["coins_alt"])), ""], Vector2(x, sr.position.y + 170), 17, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
		return
	if who == "relay":
		_bld(m, "relay", int(o["relay_lvl"]), Rect2(x, sr.position.y + 10, 72, 72))
		Kit.t(m, "Core Relay  Lv%d" % int(o["relay_lvl"]), Vector2(x + 84, sr.position.y + 40), 19, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 84)
		Kit.wrap(m, String(DESC["relay"]), Vector2(x + 84, sr.position.y + 54), 14, Kit.DIM, w - 84, 3)
		Kit.t(m, "Power %d / %d" % [int(Outpost.demand(o)), int(Outpost.supply(o))], Vector2(x, sr.position.y + 118), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
		_draw_delta(m, s, "relay", x, sr.position.y + 150.0, w)
		return
	if who.begins_with("d"):
		var d: Dictionary = o["decor"][who.substr(1)]
		var dd: Dictionary = OutpostDB.DECOR[String(d["id"])]
		_art(m, String(d["id"]), Rect2(x, sr.position.y + 10, 72, 72))
		Kit.t(m, String(dd["name"]), Vector2(x + 84, sr.position.y + 40), 19, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 84)
		Kit.t(m, "Decor  ·  %s" % String(dd["tag"]), Vector2(x + 84, sr.position.y + 64), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 84)
		return
	if not (o["buildings"] as Dictionary).has(who):
		return
	var b: Dictionary = o["buildings"][who]
	var id: String = String(b["id"])
	_bld(m, id, int(b["lvl"]), Rect2(x, sr.position.y + 10, 72, 72))
	Kit.t(m, "%s  Lv%d / %d" % [name_of(id), int(b["lvl"]), Outpost.max_lvl(s, id)], Vector2(x + 84, sr.position.y + 34), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 84)
	Kit.wrap(m, String(DESC.get(id, "")), Vector2(x + 84, sr.position.y + 50), 14, Kit.DIM, w - 84, 3)
	var con: Dictionary = Outpost.connected(o)
	var y: float = sr.position.y + 110.0
	var lnk: bool = bool(con.get(who, false))
	Kit.t(m, ("Linked to the Relay" if lnk else "NOT LINKED — add Conduits") if id != "conduit" else "Conduit", Vector2(x, y), 15, Kit.GREEN if lnk else Kit.ENEMY, HORIZONTAL_ALIGNMENT_LEFT, w)
	var ly: float = y + 30.0
	if OutpostDB.GENERATORS.has(id):
		var rt: float = Outpost.rate(s, who, con)
		var rtxt: String = scav_text(id, rt) if OutpostDB.SCAVENGERS.has(id) else "%s %s/h" % [_rate_txt(rt), String(OutpostDB.get_def(id)["res"])]
		Kit.t(m, rtxt, Vector2(x + w, y), 15, Kit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.6)
		var cp: float = maxf(0.001, Outpost.cap(s, who, con))
		Kit.bar(m, Rect2(x, y + 10, w, 12), float(b["stored"]) / cp, Kit.MAGENTA if OutpostDB.SCAVENGERS.has(id) else Kit.GOLD)
		Kit.t(m, "stored %d / %d" % [int(float(b["stored"])), int(cp)], Vector2(x + w * 0.5, y + 40), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
		ly = y + 62.0
	elif OutpostDB.CORE_IDS.has(id):
		# V2 P6c: what this building gives the Core right now
		var part: Dictionary = Outpost.core_part(o, who, con) if (lnk and bool(b["built"])) else {}
		var keys: Array = (OutpostDB.get_def(id)["core"] as Dictionary).keys()
		var ct: Array = []
		for k in keys:
			ct.append(core_text(String(k), float(part.get(k, 0.0))))
		Kit.th(m, "CORE  " + "  ·  ".join(PackedStringArray(ct)), Vector2(x, y + 30), 17, Kit.CYAN if lnk else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
		ly = y + 62.0
	if AdjDB.receives(id):
		_draw_parts(m, Outpost.layout_bonus(o, who, con), x, ly, w)
	_draw_delta(m, s, who, x, sr.position.y + 206.0, w)


## "Layout +25%" + one chip per part (green buff / red nerf; tooltips say
## which rule).
static func _draw_parts(m, lb: Dictionary, x: float, y: float, w: float) -> void:
	var tot: float = float(lb["total"])
	var head: String = "Layout %+d%%" % int(round(tot * 100.0))
	Kit.t(m, head, Vector2(x, y), 14, Kit.GREEN if tot > 0.0 else (Kit.ENEMY if tot < 0.0 else Kit.DIM), HORIZONTAL_ALIGNMENT_LEFT, w)
	var cx: float = x + 22.0 + m.font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var parts: Dictionary = lb["parts"]
	if parts.is_empty():
		Kit.t(m, "no neighbours", Vector2(cx, y), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, x + w - cx)
		return
	for k in parts.keys():
		var v: float = float(parts[k])
		var txt: String = "%s %+d%%" % [String(PART_NAME.get(String(k), String(k))), int(round(v * 100.0))]
		var cw: float = 14.0 + m.font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if cx + cw > x + w:
			Kit.t(m, "…", Vector2(cx, y), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 20.0)
			break
		var col: Color = Kit.GREEN if v > 0.0 else Kit.ENEMY
		var cr := Rect2(cx, y - 15.0, cw, 21.0)
		Kit.panel(m, cr, Color(col, 0.7), Color(col, 0.10), 1)
		Kit.t(m, txt, Vector2(cx + 7.0, y), 14, col, HORIZONTAL_ALIGNMENT_LEFT, cw)
		m.stat_tips.append([cr, AdjDB.text_of(String(k))])
		cx += cw + 6.0


# ============================================================ upgrade delta
## FB1: what the next upgrade does, as [label, before, after] rows. Pure:
## computed on a copy of the save with the level bumped.
static func upgrade_delta(s: Dictionary, uid: String) -> Array:
	var o: Dictionary = Outpost._o(s)
	var s2: Dictionary = s.duplicate(true)
	var o2: Dictionary = Outpost._o(s2)
	var out: Array = []
	if uid == "relay":
		var rl: int = int(o["relay_lvl"])
		o2["relay_lvl"] = rl + 1
		out.append(["Power", "%d" % int(Outpost.supply(o)), "%d" % int(Outpost.supply(o2))])
		out.append(["Max building level", "%d" % Outpost.max_lvl(s, "mill"), "%d" % Outpost.max_lvl(s2, "mill")])
		for id in ["mill", "refinery", "gemmine"]:
			var a: int = OutpostDB.limit(id, rl)
			var b: int = OutpostDB.limit(id, rl + 1)
			if a != b:
				out.append(["%s limit" % name_of(id), "%d" % a, "%d" % b])
		if rl + 1 == 3:
			out.append(["Collect all", "no", "yes"])
		return out
	if not (o["buildings"] as Dictionary).has(uid):
		return out
	var b0: Dictionary = o["buildings"][uid]
	var id2: String = String(b0["id"])
	var lv: int = int(b0["lvl"])
	(o2["buildings"][uid] as Dictionary)["lvl"] = lv + 1
	out.append(["Level", "%d" % lv, "%d" % (lv + 1)])
	var c1: Dictionary = Outpost.connected(o)
	var c2: Dictionary = Outpost.connected(o2)
	if OutpostDB.SCAVENGERS.has(id2):
		var r1: float = Outpost.nominal_rate(s, uid, c1)
		var r2: float = Outpost.nominal_rate(s2, uid, c2)
		out.append(["Finds every", "%.1f h" % (1.0 / maxf(0.0001, r1)), "%.1f h" % (1.0 / maxf(0.0001, r2))])
		out.append(["Storage", "%d" % int(Outpost.cap(s, uid, c1)), "%d" % int(Outpost.cap(s2, uid, c2))])
	elif OutpostDB.GENERATORS.has(id2):
		var res: String = String(OutpostDB.get_def(id2)["res"])
		out.append(["%s / hour" % res.capitalize(), _rate_txt(Outpost.rate(s, uid, c1)), _rate_txt(Outpost.rate(s2, uid, c2))])
		out.append(["Storage", "%d" % int(Outpost.cap(s, uid, c1)), "%d" % int(Outpost.cap(s2, uid, c2))])
	if OutpostDB.CORE_IDS.has(id2):
		# nominal (as if linked & powered): the upgrade's own step
		var p1: Dictionary = Outpost.core_part(o, uid, c1, 1.0)
		var p2: Dictionary = Outpost.core_part(o2, uid, c2, 1.0)
		for k in p1.keys():
			out.append([String((CORE_FMT.get(String(k), [String(k)]) as Array)[0]), core_text(String(k), float(p1[k]), false), core_text(String(k), float(p2.get(k, 0.0)), false)])
	match id2:
		"research":
			out.append(["Research queues", "%d" % Outpost.research_queues(s), "%d" % Outpost.research_queues(s2)])
		"barracks":
			out.append(["Troop HP / damage", "+%d%%" % (10 * Outpost.level_of(s, "barracks")), "+%d%%" % (10 * Outpost.level_of(s2, "barracks"))])
		"archive":
			var r1: Dictionary = Outpost.run_mods(s)
			var r2: Dictionary = Outpost.run_mods(s2)
			out.append(["Insights per run", "+%d" % int(r1["insight_cap"]), "+%d" % int(r2["insight_cap"])])
			out.append(["Banishes per run", "+%d" % int(r1["banish"]), "+%d" % int(r2["banish"])])
		"warehouse":
			out.append(["Nearby storage", "+%d%%" % (25 + 5 * (lv - 1)), "+%d%%" % (25 + 5 * lv)])
		"scrapyard":
			out.append(["Salvage Scrap", "+%d%%" % (10 + 2 * (lv - 1)), "+%d%%" % (10 + 2 * lv)])
	return out


static func _delta_text(rows: Array) -> String:
	var lines: Array = []
	for r in rows:
		var a: Array = r
		lines.append("%s: %s -> %s" % [String(a[0]), String(a[1]), String(a[2])])
	return "\n".join(PackedStringArray(lines))


## "NEXT UPGRADE" block: label, before (dim) -> after (green), one row each.
static func _draw_delta(m, s: Dictionary, uid: String, x: float, y: float, w: float) -> void:
	var rows: Array = upgrade_delta(s, uid)
	if rows.is_empty():
		return
	Kit.t(m, "NEXT UPGRADE", Vector2(x, y), 14, Kit.GREEN, HORIZONTAL_ALIGNMENT_LEFT, w)
	m.draw_line(Vector2(x, y + 6), Vector2(x + w, y + 6), Color(Kit.GREEN, 0.3), 1.0)
	var ry: float = y + 24.0
	for r in rows.slice(0, 4 if uid == "relay" else 3):
		var a: Array = r
		Kit.t(m, String(a[0]), Vector2(x, ry), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w * 0.5)
		Kit.t(m, String(a[1]), Vector2(x + w * 0.62, ry), 14, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.2)
		Kit.t(m, "->", Vector2(x + w * 0.69, ry), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
		Kit.t(m, String(a[2]), Vector2(x + w, ry), 14, Kit.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.26)
		ry += 18.0
