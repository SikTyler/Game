extends RefCounted
## The Factory (Outpost home screen; PLAYTEST_FEEDBACK_2 / WP3). A pannable,
## zoomable 96x64 tile map: wheel zooms about the cursor; right / middle drag
## (or left drag on empty ground, or WASD / arrows) pans. Categorised build
## palette with icons on the right; ghost placement (green / red + reason);
## R rotates; drag lays belts; Q pipettes the piece under the cursor; X / Del
## or a right click deconstructs (full refund). Hover tooltips show recipe,
## throughput, power and contents; items visibly ride the belts. Hub
## buildings (Core Bay, Crate Depot, Research Lab, Card Hall) open their
## screens; the Core Relay panel holds the bank, facilities and land.
## View only: every rule lives in Factory.gd.

const Factory := preload("res://Factory.gd")
const DB := preload("res://data/FactoryDB.gd")
const Art := preload("res://ArtDB.gd")
const Kit := preload("res://ui/Kit.gd")
const Settings := preload("res://Settings.gd")

const PAL_W: float = 380.0
const HEAD_H: float = 54.0
const ZOOM_MIN: float = 9.0
const ZOOM_MAX: float = 72.0
const ZOOM_DEFAULT: float = 34.0
const PAN_SPEED: float = 900.0      # screen px / s for WASD
const NONE: Vector2i = Vector2i(-9999, -9999)
const ERR: Dictionary = {"outside": "Outside the map", "locked": "Locked land: buy this chunk first", "rock": "Rock", "occupied": "Occupied",
	"no_deposit": "Miners must sit on a deposit", "tech": "Needs research at the Research Lab", "hub": "Fixed building", "coins": "Not enough coins", "unknown": "?"}
const HUB_TAB: Dictionary = {"bay": "bay", "crates": "crates", "research": "research", "cards": "cards"}
const ST_COL: Dictionary = {"working": Color("6bd46b"), "low power": Color("f2c94c"), "starved": Color("f2c94c"), "waiting": Color("9aa4b0"),
	"no power": Color("e8434f"), "output blocked": Color("e8434f"), "output full": Color("e8434f"), "blocked": Color("e8434f"), "target full": Color("f2c94c"),
	"no recipe": Color("e8434f"), "needs research": Color("e8434f"), "no deposit": Color("e8434f"), "no fuel": Color("e8434f"), "on": Color("6bd46b")}


# ===================================================================== frame
static func map_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.position.x + 12, cr.position.y + HEAD_H + 16, cr.size.x - PAL_W - 36, cr.size.y - HEAD_H - 28)


static func head_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.position.x + 12, cr.position.y + 8, cr.size.x - PAL_W - 36, HEAD_H)


static func pal_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.end.x - PAL_W - 12, cr.position.y + 8, PAL_W, cr.size.y - 20)


static func cell_px(m) -> float:
	return float(m.fc_zoom)


static func origin(m) -> Vector2:
	return map_rect(m).get_center() - (m.fc_center as Vector2) * cell_px(m)


static func cell_at(m, p: Vector2) -> Vector2i:
	var q: Vector2 = (p - origin(m)) / cell_px(m)
	return Vector2i(int(floor(q.x)), int(floor(q.y)))


static func cell_rect(m, x: int, y: int, w: int = 1, h: int = 1) -> Rect2:
	var c: float = cell_px(m)
	return Rect2(origin(m) + Vector2(float(x), float(y)) * c, Vector2(float(w), float(h)) * c)


static func landmark_rect(m, tab: String) -> Rect2:
	if not DB.HUB_POS.has(tab):
		return Rect2()
	var p: Vector2i = DB.HUB_POS[tab]
	return cell_rect(m, p.x, p.y, 3, 3)


static func clamp_cam(m) -> void:
	m.fc_zoom = clampf(float(m.fc_zoom), ZOOM_MIN, ZOOM_MAX)
	m.fc_center = Vector2(clampf((m.fc_center as Vector2).x, 0.0, float(DB.W)), clampf((m.fc_center as Vector2).y, 0.0, float(DB.H)))


static func pan_by(m, d: Vector2) -> void:
	m.fc_center = (m.fc_center as Vector2) - d / cell_px(m)
	clamp_cam(m)


static func zoom_at(m, p: Vector2, k: float) -> void:
	var before: Vector2 = (p - origin(m)) / cell_px(m)
	m.fc_zoom = clampf(float(m.fc_zoom) * k, ZOOM_MIN, ZOOM_MAX)
	var after: Vector2 = (p - origin(m)) / cell_px(m)
	m.fc_center = (m.fc_center as Vector2) + (before - after)
	clamp_cam(m)


## WASD / arrows pan (Main._process while the factory is open).
static func pan_keys(m, delta: float) -> void:
	var v: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if v != Vector2.ZERO:
		pan_by(m, -v.normalized() * PAN_SPEED * delta)


# ===================================================================== input
static func _hover_uid(m) -> String:
	if not map_rect(m).has_point(m.mouse_pos):
		return ""
	return Factory.uid_at(m.save, cell_at(m, m.mouse_pos))


static func is_line(id: String) -> bool:
	return id == "belt" or id == "belt2"


## Mouse inside the map (Main._input). True = consumed.
static func mouse(m, mb: InputEventMouseButton) -> bool:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var up: bool = mb.button_index == MOUSE_BUTTON_WHEEL_UP
				if bool(m._ctl("invert_zoom")):
					up = not up
				zoom_at(m, mb.position, 1.15 if up else 1.0 / 1.15)
			return true
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				m.op_pan = true
				m.op_pan_from = mb.position
				m.op_pan_moved = false
			else:
				var was: bool = m.op_pan and not m.op_pan_moved
				m.op_pan = false
				if was and mb.button_index == MOUSE_BUTTON_RIGHT:
					if m.op_arm != "":
						cancel(m)
					else:
						deconstruct_at(m, cell_at(m, mb.position))
			return true
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				press(m, cell_at(m, mb.position), mb.position)
			return true
	return false


static func press(m, c: Vector2i, pos: Vector2) -> void:
	m.op_focus = c
	if m.op_arm != "":
		if is_line(String(m.op_arm)):
			m.fc_line = c
			return
		place_at(m, c)
		return
	var u: String = Factory.uid_at(m.save, c)
	if u != "":
		var id: String = String(Factory.ent(m.save, u)["id"])
		if HUB_TAB.has(id):
			m.set_tab(String(HUB_TAB[id]))
			return
		m.op_sel = u
		m.op_msg = ""
		m._rebuild_ui()
		return
	if Factory.in_map(c) and not Factory.is_open(m.save, c):
		m.op_sel = "chunk:%d" % Factory.chunk_of(c)
		m._rebuild_ui()
		return
	# empty ground: left drag pans; a click clears the selection
	m.op_pan = true
	m.op_pan_from = pos
	m.op_pan_moved = false
	m.fc_pan_left = true


## Left release (Main._input): finish a belt drag or a left-drag pan.
static func release(m, pos: Vector2) -> void:
	if m.fc_line != NONE:
		var a: Vector2i = m.fc_line
		m.fc_line = NONE
		var b: Vector2i = cell_at(m, pos)
		var ev: Array = Factory.place_line(m.save, String(m.op_arm), a, b, int(m.op_rot))
		if ev.is_empty() and a == b:
			m.op_msg = _why(m, String(m.op_arm), a)
		else:
			m.op_msg = ""
		m.meta_act(ev)
		return
	if m.fc_pan_left:
		m.fc_pan_left = false
		var moved: bool = m.op_pan_moved
		m.op_pan = false
		if not moved and m.op_sel != "":
			m.op_sel = ""
			m._rebuild_ui()


static func cancel(m) -> void:
	m.op_arm = ""
	m.op_sel = ""
	m.op_msg = ""
	m.fc_line = NONE
	m._rebuild_ui()


static func arm(m, id: String) -> void:
	m.op_arm = "" if m.op_arm == id and not m.op_drag else id
	m.op_sel = ""
	m.op_msg = ""
	m._rebuild_ui()


static func _press_palette(m, id: String) -> void:
	arm(m, id)
	if m.op_arm != "" and String(m.last_device) != "pad" and not is_line(id):
		m.op_drag = true
		m.drag_start = m.mouse_pos


static func place_at(m, c: Vector2i) -> void:
	var id: String = m.op_arm
	if id == "":
		return
	var ev: Array = Factory.place(m.save, id, c.x, c.y, int(m.op_rot))
	if ev.is_empty():
		m.op_msg = _why(m, id, c)
		m._rebuild_ui()
		return
	m.op_msg = ""
	m.meta_act(ev)


static func _why(m, id: String, c: Vector2i) -> String:
	var err: String = Factory.place_error(m.save, id, c.x, c.y, int(m.op_rot))
	return String(ERR.get(err, err)) if err != "" else ""


static func deconstruct_at(m, c: Vector2i) -> void:
	var u: String = Factory.uid_at(m.save, c)
	if u == "":
		return
	if m.op_sel == u:
		m.op_sel = ""
	m.meta_act(Factory.remove(m.save, u))


static func rotate(m) -> void:
	if m.op_arm != "":
		m.op_rot = (int(m.op_rot) + 1) % 4
		m._rebuild_ui()
		return
	var u: String = _hover_uid(m)
	if u == "":
		u = m.op_sel if not String(m.op_sel).begins_with("chunk:") else ""
	if u != "":
		var ev: Array = Factory.rotate(m.save, u, int(Factory.ent(m.save, u)["rot"]) + 1)
		if ev.is_empty():
			m.op_msg = "No room to rotate it here"
		m.meta_act(ev)


## Q: copy the piece under the cursor (id + direction) into the cursor.
static func pipette(m) -> void:
	var u: String = _hover_uid(m)
	if u == "":
		return
	var e: Dictionary = Factory.ent(m.save, u)
	if DB.HUBS.has(String(e["id"])):
		return
	m.op_arm = String(e["id"])
	m.op_rot = int(e["rot"])
	m.op_cat = String(DB.get_def(m.op_arm)["cat"])
	m.op_sel = ""
	m._rebuild_ui()


static func action(m, event: InputEvent) -> bool:
	var pr: Callable = func(a: String) -> bool: return InputMap.has_action(a) and event.is_action_pressed(a, false, true)
	if pr.call("ability_4"):
		rotate(m)
		return true
	if pr.call("ability_1"):
		pipette(m)
		return true
	if pr.call("sell"):
		var u: String = _hover_uid(m)
		if u == "" and m.op_sel != "" and not String(m.op_sel).begins_with("chunk:"):
			u = m.op_sel
		if u != "":
			var e: Dictionary = Factory.ent(m.save, u)
			deconstruct_at(m, Vector2i(int(e["x"]), int(e["y"])))
		return true
	var ids: Array = DB.CAT_IDS[m.op_cat]
	for k in mini(9, ids.size()):
		if pr.call("hotbar_%d" % (k + 1)):
			arm(m, String(ids[k]))
			return true
	if pr.call("confirm") and String(m.last_device) == "pad":
		press(m, m.op_focus, cell_rect(m, m.op_focus.x, m.op_focus.y).get_center())
		return true
	return false


# ===================================================================== build
static func pal_entry(m, k: int) -> Rect2:
	var pr: Rect2 = pal_rect(m)
	var cols: int = 3
	var w: float = (pr.size.x - 24.0 - float(cols - 1) * 8.0) / float(cols)
	return Rect2(pr.position.x + 12.0 + float(k % cols) * (w + 8.0), pr.position.y + 150.0 + float(k / cols) * 104.0, w, 96.0)


static func sel_rect(m) -> Rect2:
	var pr: Rect2 = pal_rect(m)
	var top: float = pr.position.y + 370.0
	return Rect2(pr.position.x + 12, top, pr.size.x - 24, pr.end.y - top - 10)


static func build(m) -> void:
	if m.fc_zoom <= 0.0:
		m.fc_zoom = ZOOM_DEFAULT
	var s: Dictionary = m.save
	var pr: Rect2 = pal_rect(m)
	var x: float = pr.position.x + 12.0
	var w: float = pr.size.x - 24.0
	var cw: float = (w - 6.0) / 2.0
	for k in DB.PALETTE.size():
		var row: Array = DB.PALETTE[k]
		var cat: String = String(row[0])
		Kit.btn(m, String(row[1]), Rect2(x + float(k % 2) * (cw + 6.0), pr.position.y + 44 + float(k / 2) * 50.0, cw, 46), func() -> void: m.op_cat = cat; m._rebuild_ui(), "Build category: %s" % String(row[1]), true, Kit.RUST if m.op_cat == cat else Kit.NEUTRAL, "FCAT " + cat, String(row[2]), 15)
	var ids: Array = DB.CAT_IDS.get(m.op_cat, [])
	for k in ids.size():
		var id: String = ids[k]
		var d: Dictionary = DB.get_def(id)
		var unlocked: bool = Factory.has_tech(s, String(d["tech"]))
		var tip: String = "%s\n%s\n%s coins  ·  %s%s\n%s" % [String(d["name"]), String(d["desc"]), Kit.fmt(float(d["coins"])),
			("power %s" % _pw(float(d.get("power", 0.0)))) if float(d.get("power", 0.0)) > 0.0 else ("supplies %s power" % _pw(float(d.get("supply", 0.0))) if d.has("supply") else "no power"),
			"" if unlocked else "\nLocked: research %s at the Research Lab" % String((DB.TECH[String(d["tech"])] as Dictionary)["name"]),
			"Drag across the map to lay a line (R turns)" if is_line(id) else "Click the map to place (R rotates, right click cancels)"]
		Kit.hit(m, pal_entry(m, k), func() -> void: _press_palette(m, id), tip, "FBUILD " + id, unlocked and int(s["coins"]) >= int(d["coins"]), Kit.GREEN)
	_build_selected(m, s)
	var hr: Rect2 = head_rect(m)
	var bank: float = _bank_total(s)
	Kit.btn(m, "Collect", Rect2(hr.end.x - 150, hr.position.y + 6, 150, hr.size.y - 12), func() -> void: m.meta_act(Factory.claim_bank(m.save)),
		"Collect what the factory banked while you were away or in a run (%s)" % _bank_text(s), bank >= 1.0, Kit.GOLD, "FCOLLECT", "ui_collect", 16)


static func _pw(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0")


static func _bank_total(s: Dictionary) -> float:
	var b: Dictionary = Factory._f(s)["bank"]
	var t: float = 0.0
	for c in DB.CURRENCIES:
		t += float(b.get(c, 0.0))
	return t


static func _bank_text(s: Dictionary) -> String:
	var b: Dictionary = Factory._f(s)["bank"]
	var parts: Array = []
	for c in DB.CURRENCIES:
		if float(b.get(c, 0.0)) >= 1.0:
			parts.append("%s %s" % [Kit.fmt(floor(float(b[c]))), c])
	return "nothing yet" if parts.is_empty() else ", ".join(parts)


static func _build_selected(m, s: Dictionary) -> void:
	var sr: Rect2 = sel_rect(m)
	var who: String = m.op_sel
	if who == "":
		return
	var bx: float = sr.position.x + 10.0
	var bw: float = sr.size.x - 20.0
	if who.begins_with("chunk:"):
		var k: int = int(who.substr(6))
		var c: int = Factory.chunk_cost(s)
		var adj: bool = Factory.chunk_adjacent(s, k)
		Kit.btn(m, "Buy land  %s" % Kit.fmt(float(c)), Rect2(bx, sr.position.y + 110, bw, 46), func() -> void: m.op_sel = ""; m.meta_act(Factory.unlock_chunk(m.save, k)),
			"Open this 16x16 chunk and reveal its deposits" if adj else "Buy a chunk next to your open land first", adj and int(s["coins"]) >= c, Kit.GOLD, "FBUY LAND", "cur_coin", 16)
		return
	var e: Dictionary = Factory.ent(s, who)
	if e.is_empty():
		m.op_sel = ""
		return
	var id: String = String(e["id"])
	var y: float = sr.position.y + 120.0
	if id == "assembler" or id == "smelter":
		var recs: Array = []
		for r in DB.RECIPES.keys():
			if String((DB.RECIPES[r] as Dictionary)["at"]) == id:
				recs.append(r)
		var cols: int = 2
		var rw: float = (bw - 6.0) / float(cols)
		for i in recs.size():
			var rid: String = recs[i]
			var rd: Dictionary = DB.RECIPES[rid]
			var ok: bool = Factory.has_tech(s, String(rd["tech"]))
			Kit.btn(m, String(rd["name"]), Rect2(bx + float(i % cols) * (rw + 6.0), y + float(i / cols) * 46.0, rw, 42), func() -> void: m.meta_act(Factory.set_recipe(m.save, who, rid)),
				_recipe_text(rid) + ("" if ok else "\nLocked: research %s" % String((DB.TECH[String(rd["tech"])] as Dictionary)["name"])), ok, Kit.GEM if String(e["rec"]) == rid else Kit.NEUTRAL, "FREC " + rid, "it_" + String((rd["out"] as Dictionary).keys()[0]), 13)
	if id == "relay":
		_build_relay(m, s, sr)
		return
	if not DB.HUBS.has(id):
		var by: float = sr.end.y - 52.0
		var hw: float = (bw - 6.0) / 2.0
		Kit.btn(m, "Rotate (R)", Rect2(bx, by, hw, 44), func() -> void: m.meta_act(Factory.rotate(m.save, who, int(Factory.ent(m.save, who)["rot"]) + 1)), "Turn it clockwise", true, Kit.NEUTRAL, "FROTATE", "ui_rotate", 15)
		Kit.btn(m, "Deconstruct (X)", Rect2(bx + hw + 6.0, by, hw, 44), func() -> void: m.op_sel = ""; m.meta_act(Factory.remove(m.save, who)), "Remove it: full refund (contents are lost)", true, Kit.ENEMY, "FREMOVE", "ui_demolish", 15)


static func _build_relay(m, s: Dictionary, sr: Rect2) -> void:
	var bx: float = sr.position.x + 10.0
	var bw: float = sr.size.x - 20.0
	var y: float = sr.position.y + 214.0
	for i in DB.FAC_IDS.size():
		var fid: String = DB.FAC_IDS[i]
		var fd: Dictionary = DB.FACILITIES[fid]
		var lvl: int = Factory.fac_level(s, fid)
		var mx: bool = lvl >= int(fd["max"])
		var c: int = Factory.fac_cost(fid, lvl)
		Kit.btn(m, ("%s Lv%d  (max)" % [String(fd["name"]), lvl]) if mx else ("%s Lv%d -> %d   %s" % [String(fd["name"]), lvl, lvl + 1, Kit.fmt(float(c))]), Rect2(bx, y + float(i) * 48.0, bw, 44),
			func() -> void: m.meta_act(Factory.fac_upgrade(m.save, fid)), "%s\n%s" % [String(fd["name"]), String(fd["desc"])], not mx and int(s["coins"]) >= c, Kit.GREEN, "FFAC " + fid, "cur_coin", 14)


static func _recipe_text(rid: String) -> String:
	var rd: Dictionary = DB.RECIPES[rid]
	var ins: Array = []
	for it in (rd["in"] as Dictionary).keys():
		ins.append("%d %s" % [int((rd["in"] as Dictionary)[it]), DB.item_name(String(it))])
	var outs: Array = []
	for it in (rd["out"] as Dictionary).keys():
		outs.append("%d %s" % [int((rd["out"] as Dictionary)[it]), DB.item_name(String(it))])
	return "%s: %s -> %s in %.1fs" % [String(rd["name"]), " + ".join(ins), " + ".join(outs), float(rd["time"])]


# ===================================================================== tooltips
static func map_tip(m, p: Vector2) -> String:
	var s: Dictionary = m.save
	var c: Vector2i = cell_at(m, p)
	if not Factory.in_map(c):
		return ""
	if m.op_arm != "":
		var err: String = Factory.place_error(s, String(m.op_arm), c.x, c.y, int(m.op_rot))
		return "" if err == "" else String(ERR.get(err, err))
	if not Factory.is_open(s, c):
		var k: int = Factory.chunk_of(c)
		return "Locked land (chunk %d)\n%s\nClick, then Buy land: %s coins" % [k, "Next to your land: buyable" if Factory.chunk_adjacent(s, k) else "Buy a neighbouring chunk first", Kit.fmt(float(Factory.chunk_cost(s)))]
	var u: String = Factory.uid_at(s, c)
	if u != "":
		return entity_tip(s, u)
	var dep: String = Factory.deposit_at(c)
	if dep != "":
		return "%s deposit\nPlace a Miner on it (2x2); output is endless." % DB.item_name(dep)
	if Factory.is_rock(c):
		return "Rock: can't build here"
	return ""


static func entity_tip(s: Dictionary, u: String) -> String:
	var e: Dictionary = Factory.ent(s, u)
	var id: String = String(e["id"])
	var d: Dictionary = DB.get_def(id)
	var lines: Array = [String(d["name"])]
	if id == "relay":
		var f: Dictionary = Factory._f(s)
		var r: Dictionary = Factory.rate_now(s)
		lines.append("Turns goods into currencies (steady state):")
		lines.append("+%s coins/min  ·  +%s scrap/min  ·  +%s keys/h  ·  +%s data/min" % [Kit.fmt(float(r["coins"]) * 60.0), _f1(float(r["scrap"]) * 60.0), _f1(float(r["keys"]) * 3600.0), _f1(float(r["data"]) * 60.0)])
		var ir: Dictionary = f.get("items_rate", {})
		for it in DB.ITEM_IDS:
			if float(ir.get(it, 0.0)) > 0.0:
				lines.append("  %s: %s/min" % [DB.item_name(String(it)), _f1(float(ir[it]) * 60.0)])
		lines.append("Banked: %s  ·  away cap %.1f h (storage extends it)" % [_bank_text(s), Factory.away_cap_s(s) / 3600.0])
		return "\n".join(lines)
	if HUB_TAB.has(id):
		lines.append(String(d["desc"]))
		lines.append("Click to open")
		return "\n".join(lines)
	var st: String = String(e.get("st", ""))
	if st != "":
		lines.append("Status: %s" % st)
	if id == "smelter" or id == "assembler":
		lines.append(_recipe_text(String(e["rec"])) if String(e["rec"]) != "" else ("Recipe: picks itself from the first ore" if id == "smelter" else "No recipe: select it and pick one"))
	var tp: Dictionary = Factory.throughput(s, u)
	for k in tp.keys():
		lines.append("Throughput: %s %s/min" % [_f1(float(tp[k])), "items" if String(k) == "items" else DB.item_name(String(k))])
	var pw: float = float(d.get("power", 0.0))
	if pw > 0.0:
		lines.append("Power: draws %s  ·  satisfaction %d%%" % [_pw(pw), int(round(Factory.sat_of(s, u) * 100.0))])
	elif d.has("supply"):
		lines.append("Power: supplies %s%s" % [_pw(float(d["supply"])), "" if id != "coal_gen" else "  ·  fuel %d" % int(e["fuel"])])
	var inv: Dictionary = {}
	for key in ["inv", "in", "out"]:
		if e.get(key, null) is Dictionary:
			for it in (e[key] as Dictionary).keys():
				inv[it] = int(inv.get(it, 0)) + int((e[key] as Dictionary)[it])
	if e.has("it"):
		for a in e["it"]:
			inv[String(a[0])] = int(inv.get(String(a[0]), 0)) + 1
	if String(e.get("hand", "")) != "":
		inv[String(e["hand"])] = int(inv.get(String(e["hand"]), 0)) + 1
	if not inv.is_empty():
		var parts: Array = []
		for it in inv.keys():
			parts.append("%d %s" % [int(inv[it]), DB.item_name(String(it))])
		lines.append("Holds: " + ", ".join(parts) + ((" / %d" % int(d["cap"])) if d.has("cap") else ""))
	lines.append("R rotate · Q copy · X / right click remove")
	return "\n".join(lines)


static func _f1(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0")


# ===================================================================== draw
static func draw(m, _cr: Rect2) -> void:
	var s: Dictionary = m.save
	var mr: Rect2 = map_rect(m)
	m.draw_rect(mr, Color("101317"))
	_draw_map(m, s, mr)
	# cover overdraw outside the map frame (cells are culled per cell, not clipped)
	var cr: Rect2 = m.content_rect()
	m.draw_rect(Rect2(cr.position.x, cr.position.y, cr.size.x, mr.position.y - cr.position.y), Kit.BG)
	m.draw_rect(Rect2(cr.position.x, mr.end.y, cr.size.x, cr.end.y - mr.end.y), Kit.BG)
	m.draw_rect(Rect2(cr.position.x, mr.position.y, mr.position.x - cr.position.x, mr.size.y), Kit.BG)
	m.draw_rect(Rect2(mr.end.x, mr.position.y, cr.end.x - mr.end.x, mr.size.y), Kit.BG)
	m.draw_rect(mr, Kit.EDGE, false, 2.0)
	_draw_head(m, s, head_rect(m))
	_draw_palette(m, s)


static func _vis(m, mr: Rect2) -> Rect2i:
	var a: Vector2i = cell_at(m, mr.position)
	var b: Vector2i = cell_at(m, mr.end)
	a = Vector2i(maxi(0, a.x), maxi(0, a.y))
	b = Vector2i(mini(DB.W - 1, b.x), mini(DB.H - 1, b.y))
	return Rect2i(a, b - a + Vector2i.ONE)


static func _draw_map(m, s: Dictionary, mr: Rect2) -> void:
	var f: Dictionary = Factory._f(s)
	var cp: float = cell_px(m)
	var vis: Rect2i = _vis(m, mr)
	# ground per chunk
	for k in DB.CW * DB.CH:
		var ck: Rect2i = DB.chunk_rect(k)
		if not ck.intersects(vis):
			continue
		var r: Rect2 = cell_rect(m, ck.position.x, ck.position.y, DB.CHUNK, DB.CHUNK).intersection(mr)
		var open: bool = (f["chunks"] as Array).has(k)
		m.draw_rect(r, Color("2a3036") if open else Color("15181c"))
		if not open:
			for i in range(0, 12):
				var t0: float = float(i) / 12.0
				m.draw_line(r.position + Vector2(r.size.x * t0, 0), r.position + Vector2(0, r.size.y * t0), Color(1, 1, 1, 0.025), 1.0)
	# grid
	if cp >= 14.0:
		var gc: Color = Color(1, 1, 1, 0.045)
		for x in range(vis.position.x, vis.end.x + 1):
			m.draw_line(origin(m) + Vector2(float(x), float(vis.position.y)) * cp, origin(m) + Vector2(float(x), float(vis.end.y)) * cp, gc, 1.0)
		for y in range(vis.position.y, vis.end.y + 1):
			m.draw_line(origin(m) + Vector2(float(vis.position.x), float(y)) * cp, origin(m) + Vector2(float(vis.end.x), float(y)) * cp, gc, 1.0)
	# deposits + rocks (only on open land: locked deposits stay hidden)
	for y in range(vis.position.y, vis.end.y):
		for x in range(vis.position.x, vis.end.x):
			var c: Vector2i = Vector2i(x, y)
			if not Factory.is_open(s, c):
				continue
			var dep: String = Factory.deposit_at(c)
			if dep != "":
				var dr: Rect2 = cell_rect(m, x, y)
				m.draw_rect(dr, Color(Color(String((DB.ITEMS[dep] as Array)[1])), 0.16))
				Kit.icon(m, "dep_" + dep, dr)
			elif Factory.is_rock(c):
				Kit.icon(m, "fy_rock", cell_rect(m, x, y))
	# chunk borders (open/locked edge) + buy labels
	for k in DB.CW * DB.CH:
		var ck2: Rect2i = DB.chunk_rect(k)
		if not ck2.intersects(vis):
			continue
		var r2: Rect2 = cell_rect(m, ck2.position.x, ck2.position.y, DB.CHUNK, DB.CHUNK)
		if not (f["chunks"] as Array).has(k):
			m.draw_rect(r2.intersection(mr), Color(1, 1, 1, 0.06), false, 1.0)
			if Factory.chunk_adjacent(s, k) and cp >= 10.0 and mr.grow(-40).has_point(r2.get_center()):
				var sel: bool = String(m.op_sel) == "chunk:%d" % k
				Kit.icon(m, "slot_locked", Rect2(r2.get_center() - Vector2(18, 34), Vector2(36, 36)), Color(1, 1, 1, 0.8))
				Kit.t(m, "Buy land  %s" % Kit.fmt(float(Factory.chunk_cost(s))), r2.get_center() + Vector2(0, 22), 16, Kit.GOLD if sel else Color(Kit.GOLD, 0.7), HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)
				if sel:
					m.draw_rect(r2.grow(-2), Kit.GOLD, false, 3.0)
	# power wires (pole to pole within a net)
	_draw_wires(m, s, vis)
	# entities
	var ents: Dictionary = f["ents"]
	var hover: String = _hover_uid(m)
	for uid in ents.keys():
		var e: Dictionary = ents[uid]
		var id: String = String(e["id"])
		var sz: Vector2i = DB.size_of(id, int(e["rot"]))
		if not Rect2i(int(e["x"]), int(e["y"]), sz.x, sz.y).intersects(vis.grow(1)):
			continue
		_draw_ent(m, s, String(uid), e, cp)
		if String(uid) == String(m.op_sel) or String(uid) == hover:
			m.draw_rect(cell_rect(m, int(e["x"]), int(e["y"]), sz.x, sz.y), Kit.GOLD if String(uid) == String(m.op_sel) else Color(1, 1, 1, 0.5), false, 2.0)
	# hub names (above neighbouring pieces)
	if cp >= 16.0:
		for h in DB.HUBS:
			var hr: Rect2 = landmark_rect(m, String(h)) if String(h) != "relay" else cell_rect(m, DB.HUB_POS["relay"].x, DB.HUB_POS["relay"].y, 3, 3)
			if mr.has_point(hr.get_center()):
				var fs: int = clampi(int(cp * 0.42), 12, 20)
				var nm: String = String(DB.get_def(String(h))["name"])
				var tw: float = float(fs) * 0.56 * float(nm.length()) + 12.0
				m.draw_rect(Rect2(hr.get_center().x - tw * 0.5, hr.end.y + 2, tw, float(fs) + 6.0), Color(0.06, 0.07, 0.09, 0.78))
				Kit.t(m, nm, Vector2(hr.get_center().x, hr.end.y + float(fs) + 2.0), fs, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r_w(hr))
	# items on belts (above every belt)
	for uid in ents.keys():
		var e2: Dictionary = ents[uid]
		if e2.has("it") and not (e2["it"] as Array).is_empty() and vis.grow(1).has_point(Vector2i(int(e2["x"]), int(e2["y"]))):
			_draw_belt_items(m, e2, cp)
	_draw_ghost(m, s, cp)
	# keyboard / pad focus
	if String(m.last_device) == "pad":
		m.draw_rect(cell_rect(m, m.op_focus.x, m.op_focus.y), Kit.GEM, false, 3.0)


static func r_w(r: Rect2) -> float:
	return r.size.x * 1.8


static func _draw_wires(m, s: Dictionary, vis: Rect2i) -> void:
	var f: Dictionary = Factory._f(s)
	var c: Dictionary = Factory._compile(f)
	var ents: Dictionary = f["ents"]
	var cp: float = cell_px(m)
	var show: bool = String(m.op_arm) == "pole" or DB.CAT_IDS["power"].has(String(m.op_arm)) or float(DB.get_def(String(m.op_arm)).get("power", 0.0)) > 0.0
	for net in c["nets"]:
		var nodes: Array = (net as Dictionary)["nodes"]
		for i in nodes.size():
			var a: Dictionary = ents[nodes[i]]
			var pa: Vector2 = origin(m) + Factory._center(a) * cp
			for j in range(i + 1, nodes.size()):
				var b: Dictionary = ents[nodes[j]]
				if Factory._center(a).distance_to(Factory._center(b)) <= DB.LINK_RANGE:
					m.draw_line(pa, origin(m) + Factory._center(b) * cp, Color(1.0, 0.83, 0.28, 0.35), maxf(1.0, cp / 24.0))
			if show:
				var sz: Vector2i = DB.size_of(String(a["id"]), int(a["rot"]))
				var rr: Rect2 = cell_rect(m, int(a["x"]) - DB.POLE_REACH, int(a["y"]) - DB.POLE_REACH, sz.x + 2 * DB.POLE_REACH, sz.y + 2 * DB.POLE_REACH)
				m.draw_rect(rr, Color(0.25, 0.85, 0.91, 0.07))
				m.draw_rect(rr, Color(0.25, 0.85, 0.91, 0.25), false, 1.0)


static func _art_id(id: String) -> String:
	return "fy_" + id


## Texture drawn at rot 0 dims, rotated about the footprint centre.
static func _draw_rot(m, tex_id: String, e: Dictionary, mod: Color = Color.WHITE) -> void:
	var id: String = String(e["id"])
	var r0: Vector2i = DB.size_of(id, 0)
	var szr: Vector2i = DB.size_of(id, int(e["rot"]))
	var cp: float = cell_px(m)
	var ctr: Vector2 = origin(m) + (Vector2(float(e["x"]), float(e["y"])) + Vector2(szr) * 0.5) * cp
	var tx: Texture2D = Art.tex(tex_id)
	var half: Vector2 = Vector2(r0) * cp * 0.5
	m.draw_set_transform(ctr, float(int(e["rot"])) * PI * 0.5, Vector2.ONE)
	if tx != null:
		m.draw_texture_rect(tx, Rect2(-half, half * 2.0), false, mod)
	else:
		m.draw_rect(Rect2(-half, half * 2.0), Color(Kit.RUST, 0.6 * mod.a))
	m.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_ent(m, s: Dictionary, uid: String, e: Dictionary, cp: float) -> void:
	var id: String = String(e["id"])
	var sz: Vector2i = DB.size_of(id, int(e["rot"]))
	var r: Rect2 = cell_rect(m, int(e["x"]), int(e["y"]), sz.x, sz.y)
	_draw_rot(m, _art_id(id), e)
	if id == "belt" or id == "belt2" or id == "ug_in" or id == "ug_out" or id == "splitter":
		_draw_chevrons(m, e, cp)
	if DB.HUBS.has(id):
		if id == "relay" and _bank_total(s) >= 1.0:
			m.draw_circle(r.position + Vector2(r.size.x - 10, 10), 8.0, Kit.GOLD)
		return
	if id == "inserter" and String(e["hand"]) != "":
		var d: Vector2 = Vector2(Factory.DIRS[int(e["rot"])])
		var frac: float = clampf(float(e["t"]) / DB.INSERTER_CYCLE, 0.5, 1.0)
		var p: Vector2 = r.get_center() + d * cp * (frac - 0.75) * 1.4
		Kit.icon(m, "it_" + String(e["hand"]), Rect2(p - Vector2(cp, cp) * 0.22, Vector2(cp, cp) * 0.44))
	if id == "smelter" or id == "assembler":
		var rec: String = String(e["rec"])
		if rec != "" and cp >= 12.0:
			var out_it: String = String((DB.RECIPES[rec]["out"] as Dictionary).keys()[0])
			var ir: float = cp * (0.55 if id == "smelter" else 0.8)
			m.draw_circle(r.get_center(), ir * 0.62, Color(0, 0, 0, 0.55))
			Kit.icon(m, "it_" + out_it, Rect2(r.get_center() - Vector2(ir, ir) * 0.5, Vector2(ir, ir)))
		if float(e["p"]) > 0.0:
			Kit.bar(m, Rect2(r.position.x + 4, r.end.y - 7, r.size.x - 8, 4), float(e["p"]), Kit.GREEN)
	if (id == "chest" or id == "vault") and cp >= 14.0:
		var n: int = Factory.items_on(e)
		if n > 0:
			Kit.t(m, str(n), Vector2(r.get_center().x, r.end.y - 3), clampi(int(cp * 0.32), 10, 16), Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var st: String = String(e.get("st", ""))
	if ST_COL.has(st) and cp >= 12.0 and (float(DB.get_def(id).get("power", 0.0)) > 0.0 or id == "coal_gen"):
		if true:
			var dot: Vector2 = r.position + Vector2(r.size.x - maxf(5.0, cp * 0.16), maxf(5.0, cp * 0.16))
			m.draw_circle(dot, maxf(3.0, cp * 0.1), Color(0, 0, 0, 0.6))
			m.draw_circle(dot, maxf(2.0, cp * 0.07), ST_COL[st])


## Moving chevrons on belt surfaces (flow direction + speed at a glance).
static func _draw_chevrons(m, e: Dictionary, cp: float) -> void:
	if cp < 14.0:
		return
	var id: String = String(e["id"])
	var spd: float = float(DB.BELT_SPEED.get(id, 2.0))
	var d: Vector2 = Vector2(Factory.DIRS[int(e["rot"])])
	var n: Vector2 = Vector2(-d.y, d.x)
	var cells: Array = Factory.footprint(id, int(e["x"]), int(e["y"]), int(e["rot"]))
	var ph: float = fmod(float(m.t_anim) * spd, 1.0)
	var col: Color = Color(1, 1, 1, 0.13)
	for c in cells:
		var ctr: Vector2 = cell_rect(m, (c as Vector2i).x, (c as Vector2i).y).get_center()
		for k in 2:
			var off: float = (fmod(ph + float(k) * 0.5, 1.0) - 0.5) * cp
			var tip: Vector2 = ctr + d * (off + cp * 0.1)
			m.draw_line(tip - d * cp * 0.14 + n * cp * 0.2, tip, col, maxf(1.0, cp / 20.0))
			m.draw_line(tip - d * cp * 0.14 - n * cp * 0.2, tip, col, maxf(1.0, cp / 20.0))


static func _draw_belt_items(m, e: Dictionary, cp: float) -> void:
	var d: Vector2 = Vector2(Factory.DIRS[int(e["rot"])])
	var base: Vector2 = cell_rect(m, int(e["x"]), int(e["y"])).get_center()
	var isz: float = cp * 0.42
	for a in e["it"]:
		var p: float = float((a as Array)[1])
		if String(e["id"]) == "ug_in" and p > 0.5:
			continue      # in the tunnel
		var c: Vector2 = base + d * (minf(p, 1.0) - 0.5) * cp
		Kit.icon(m, "it_" + String((a as Array)[0]), Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)))


static func _draw_ghost(m, s: Dictionary, cp: float) -> void:
	var id: String = m.op_arm
	if id == "" or not map_rect(m).has_point(m.mouse_pos):
		return
	var cells: Array = []
	if is_line(id) and m.fc_line != NONE:
		var lc: Array = Factory.line_cells(m.fc_line, cell_at(m, m.mouse_pos))
		for i in lc.size():
			var rot: int = int(m.op_rot)
			if i + 1 < lc.size():
				rot = Factory.dir_index((lc[i + 1] as Vector2i) - (lc[i] as Vector2i))
			elif i > 0:
				rot = Factory.dir_index((lc[i] as Vector2i) - (lc[i - 1] as Vector2i))
			cells.append([lc[i], rot])
	else:
		cells.append([cell_at(m, m.mouse_pos), int(m.op_rot)])
	for a in cells:
		var c: Vector2i = a[0]
		var rot2: int = int(a[1])
		var err: String = Factory.place_error(s, id, c.x, c.y, rot2)
		var sz: Vector2i = DB.size_of(id, rot2)
		var ok: bool = err == ""
		var r: Rect2 = cell_rect(m, c.x, c.y, sz.x, sz.y)
		m.draw_rect(r, Color(0.42, 0.83, 0.42, 0.22) if ok else Color(0.91, 0.26, 0.31, 0.25))
		_draw_rot(m, _art_id(id), {"id": id, "x": c.x, "y": c.y, "rot": rot2}, Color(1, 1, 1, 0.6))
		m.draw_rect(r, Kit.GREEN if ok else Kit.ENEMY, false, 2.0)
		# direction arrow
		var d: Vector2 = Vector2(Factory.DIRS[rot2])
		var ctr: Vector2 = r.get_center()
		m.draw_line(ctr - d * cp * 0.25, ctr + d * cp * 0.3, Color(1, 1, 1, 0.9), maxf(2.0, cp / 14.0))
		if Factory.MINERS.has(id):
			var oc: Vector2i = Factory.miner_out(id, c.x, c.y, rot2)
			m.draw_rect(cell_rect(m, oc.x, oc.y), Color(1.0, 0.83, 0.28, 0.6), false, 2.0)
		if id == "inserter":
			var src: Rect2 = cell_rect(m, c.x - int(d.x), c.y - int(d.y))
			var dst: Rect2 = cell_rect(m, c.x + int(d.x), c.y + int(d.y))
			m.draw_rect(src, Color(0.35, 0.82, 0.94, 0.6), false, 2.0)
			m.draw_rect(dst, Color(1.0, 0.83, 0.28, 0.6), false, 2.0)
	if cells.size() == 1:
		var err2: String = Factory.place_error(s, id, (cells[0][0] as Vector2i).x, (cells[0][0] as Vector2i).y, int(m.op_rot))
		m.set_meta("op_ghost", {"id": id, "cell": cells[0][0], "err": err2})
		if err2 != "" and String(m.op_msg) == "":
			Kit.t(m, String(ERR.get(err2, err2)), m.mouse_pos + Vector2(18, -14), 15, Color("ff8a8a"), HORIZONTAL_ALIGNMENT_LEFT, 360.0)


static func _draw_head(m, s: Dictionary, hr: Rect2) -> void:
	Kit.panel(m, hr)
	var f: Dictionary = Factory._f(s)
	var r: Dictionary = Factory.rate_now(s)
	Kit.icon(m, "fy_relay", Rect2(hr.position.x + 8, hr.position.y + 6, hr.size.y - 12, hr.size.y - 12))
	var x: float = hr.position.x + hr.size.y + 4
	Kit.t(m, "FACTORY", Vector2(x, hr.position.y + 24), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 120)
	Kit.t(m, "Relay output", Vector2(x, hr.position.y + 44), 13, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 120)
	x += 118
	var chips: Array = [["cur_coin", "%s/min" % Kit.fmt(float(r["coins"]) * 60.0), Kit.GOLD, "Coins per minute from the Core Relay"],
		["cur_scrap", "%s/min" % _f1(float(r["scrap"]) * 60.0), Kit.SCRAP, "Scrap per minute (part levels)"],
		["cur_key", "%s/h" % _f1(float(r["keys"]) * 3600.0), Kit.KEYC, "Keys per hour (crates)"],
		["it_data_card", "%d data" % int(f["data"]), Kit.LAB, "Research data (factory technology) · +%s/min" % _f1(float(r["data"]) * 60.0)]]
	for ch in chips:
		Kit.chip(m, String(ch[0]), String(ch[1]), Vector2(x, hr.position.y + 12), ch[2], String(ch[3]), 132.0)
		x += 140.0
	# power summary (worst net)
	var pw: Array = Factory.power_report(s)
	var sup: float = 0.0
	var dem: float = 0.0
	var worst: float = 1.0
	for n in pw:
		sup += float((n as Dictionary)["supply"])
		dem += float((n as Dictionary)["demand"])
		worst = minf(worst, float((n as Dictionary)["sat"]))
	var pc: Color = Kit.GREEN if worst >= 0.999 else (Kit.GOLD if worst >= 0.5 else Kit.ENEMY)
	Kit.chip(m, "fy_windmill", "%s / %s power" % [_pw(dem), _pw(sup)], Vector2(x, hr.position.y + 12), pc, "Power demand / supply across %d network(s). Lowest satisfaction %d%%: machines on a short network slow down." % [pw.size(), int(round(worst * 100.0))], 170.0)
	x += 180.0
	if _bank_total(s) >= 1.0:
		Kit.t(m, "Banked: " + _bank_text(s), Vector2(x, hr.position.y + 34), 14, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, hr.end.x - 160 - x)
	if String(m.op_msg) != "":
		Kit.t(m, String(m.op_msg), Vector2(hr.position.x + 12, hr.end.y + 28), 16, Color("ff8a8a"), HORIZONTAL_ALIGNMENT_LEFT, hr.size.x)
	# controls hint (bottom of the map)
	var mr: Rect2 = map_rect(m)
	Kit.t(m, "Wheel zoom · drag / WASD pan · R rotate · Q copy · X / right click remove · drag to lay belts", Vector2(mr.position.x + 10, mr.end.y - 10), 14, Color(Kit.DIM, 0.85), HORIZONTAL_ALIGNMENT_LEFT, mr.size.x - 20)


static func _draw_palette(m, s: Dictionary) -> void:
	var pr: Rect2 = pal_rect(m)
	Kit.panel(m, pr)
	Kit.head(m, "BUILD", Vector2(pr.position.x + 14, pr.position.y + 28), pr.size.x - 28)
	var ids: Array = DB.CAT_IDS.get(m.op_cat, [])
	for k in ids.size():
		var id: String = ids[k]
		var d: Dictionary = DB.get_def(id)
		var r: Rect2 = pal_entry(m, k)
		var unlocked: bool = Factory.has_tech(s, String(d["tech"]))
		var armed: bool = String(m.op_arm) == id
		Kit.panel(m, r, Kit.GOLD if armed else Kit.EDGE, Color("1a1f26") if unlocked else Color("14171b"), 3 if armed else 2)
		var isz: float = 50.0
		Kit.icon(m, _art_id(id), Rect2(r.get_center().x - isz * 0.5, r.position.y + 6, isz, isz), Color.WHITE if unlocked else Color(1, 1, 1, 0.35))
		Kit.t(m, String(d["name"]), Vector2(r.get_center().x, r.position.y + 72), 12 if String(d["name"]).length() > 13 else 13, Kit.TEXT if unlocked else Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 4)
		Kit.t(m, Kit.fmt(float(d["coins"])) if unlocked else "Research", Vector2(r.get_center().x, r.position.y + 89), 13, (Kit.GOLD if int(s["coins"]) >= int(d["coins"]) else Color("ff8a8a")) if unlocked else Kit.LAB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 4)
		if k < 9:
			Kit.t(m, str(k + 1), r.position + Vector2(6, 16), 12, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 20)
	_draw_selected(m, s, sel_rect(m))


static func _draw_selected(m, s: Dictionary, sr: Rect2) -> void:
	Kit.panel(m, sr, Kit.EDGE, Color("161a20"))
	var who: String = m.op_sel
	var x: float = sr.position.x + 14.0
	var w: float = sr.size.x - 28.0
	if who == "":
		if String(m.op_arm) != "":
			var d0: Dictionary = DB.get_def(String(m.op_arm))
			Kit.head(m, String(d0["name"]).to_upper(), Vector2(x, sr.position.y + 28), w)
			Kit.wrap(m, String(d0["desc"]), Vector2(x, sr.position.y + 54), 15, Kit.TEXT, w, 6)
			Kit.t(m, "R rotate (facing %s) · right click / Esc cancel" % ["east", "south", "west", "north"][int(m.op_rot)], Vector2(x, sr.position.y + 170), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
			return
		Kit.head(m, "YOUR FACTORY", Vector2(x, sr.position.y + 28), w)
		Kit.wrap(m, "Miners on deposits -> belts -> Smelters / Assemblers (inserters in and out) -> the Core Relay, which turns goods into coins, scrap, keys and research data. Machines need power: Wind Turbines, Coal Generators and Poles. Buy land to find new deposits. It runs live here and keeps producing (at the measured rate) while you're away or in a run, up to your storage cap.", Vector2(x, sr.position.y + 54), 15, Kit.TEXT, w, 12)
		return
	if who.begins_with("chunk:"):
		var k: int = int(who.substr(6))
		Kit.head(m, "LOCKED LAND", Vector2(x, sr.position.y + 28), w)
		Kit.wrap(m, "A 16x16 chunk. Deposits inside are hidden until you buy it.", Vector2(x, sr.position.y + 54), 15, Kit.TEXT, w, 3)
		if not Factory.chunk_adjacent(s, k):
			Kit.t(m, "Not next to your land yet", Vector2(x, sr.position.y + 100), 14, Color("ff8a8a"), HORIZONTAL_ALIGNMENT_LEFT, w)
		return
	var e: Dictionary = Factory.ent(s, who)
	if e.is_empty():
		return
	var id: String = String(e["id"])
	Kit.icon(m, _art_id(id), Rect2(x, sr.position.y + 10, 40, 40))
	Kit.t(m, String(DB.get_def(id)["name"]).to_upper(), Vector2(x + 48, sr.position.y + 36), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 48)
	var info: String = entity_tip(s, who).split("\n", false, 1)[1] if entity_tip(s, who).contains("\n") else ""
	var lines: PackedStringArray = info.split("\n")
	var y: float = sr.position.y + 66.0
	var max_lines: int = 2 if (id == "assembler" or id == "smelter") else (6 if id == "relay" else 12)
	if id == "relay":
		Kit.head(m, "FACILITIES", Vector2(x, sr.position.y + 206), w)
	for i in mini(lines.size(), max_lines):
		if lines[i].begins_with("R rotate") and id != "relay":
			continue
		Kit.t(m, lines[i], Vector2(x, y), 14, Kit.DIM if i > 0 else Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
		y += 20.0
	if id == "assembler" or id == "smelter":
		var nr: int = 0
		for r in DB.RECIPES.keys():
			if String((DB.RECIPES[r] as Dictionary)["at"]) == id:
				nr += 1
		var ty: float = sr.position.y + 120.0 + float((nr + 1) / 2) * 46.0 + 20.0
		var tl: PackedStringArray = entity_tip(s, who).split("\n")
		for i in range(2, tl.size()):
			if tl[i].begins_with("R rotate"):
				continue
			Kit.t(m, tl[i], Vector2(x, ty), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
			ty += 20.0
