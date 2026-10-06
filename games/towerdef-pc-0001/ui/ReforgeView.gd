extends RefCounted
## Core Reforge (REDESIGN_SPEC §5): the prestige screen. Left: shard preview
## (shards now, cumulative, the gate, "worth it"), the keep / reset lists and
## a two-step Reforge confirm. Right: the permanent shard tree — root plus the
## Power, Economy and Mastery branches; node tooltips show effect, level and
## cost. View only: Reforge.preview / reforge / buy.

const Reforge := preload("res://Reforge.gd")
const ReforgeDB := preload("res://data/ReforgeDB.gd")
const Kit := preload("res://ui/Kit.gd")
const TuneRef := preload("res://Tune.gd")

const BRANCHES: Array = [["power", "POWER", "rf_power", Kit.ENEMY], ["economy", "ECONOMY", "rf_economy", Kit.GOLD], ["mastery", "MASTERY", "rf_mastery", Kit.CYAN]]
const NODE_R: float = 34.0


static func left_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.position.x + 16, cr.position.y + 16, 560, cr.size.y - 32)


static func tree_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var l: Rect2 = left_rect(m)
	return Rect2(l.end.x + 16, cr.position.y + 16, cr.end.x - l.end.x - 32, cr.size.y - 32)


## Node labels hang to the right of each node; shift columns left so the
## rightmost (Mastery) labels stay inside the tree panel at 1080p.
const LABEL_SHIFT: float = 60.0


static func _branch_ids(br: String) -> Array:
	var out: Array = []
	for id in ReforgeDB.IDS:
		if String((ReforgeDB.NODES[id] as Dictionary)["branch"]) == br:
			out.append(String(id))
	return out


static func node_pos(m, id: String) -> Vector2:
	var tr: Rect2 = tree_rect(m)
	if id == "root_forge":
		return Vector2(tr.get_center().x, tr.position.y + 110)
	var d: Dictionary = ReforgeDB.NODES[id]
	var bi: int = 0
	for k in BRANCHES.size():
		if String((BRANCHES[k] as Array)[0]) == String(d["branch"]):
			bi = k
	var ids: Array = _branch_ids(String(d["branch"]))
	var j: int = ids.find(id)
	var colw: float = tr.size.x / 3.0
	var top: float = tr.position.y + 260.0
	var step: float = minf(118.0, (tr.end.y - top - 60.0) / float(maxi(1, ids.size() - 1)))
	var zig: float = (-1.0 if j % 2 == 0 else 1.0) * colw * 0.16
	return Vector2(tr.position.x + colw * (float(bi) + 0.5) - LABEL_SHIFT + zig, top + float(j) * step)


static func build(m) -> void:
	var s: Dictionary = m.save
	var pv: Dictionary = Reforge.preview(s)
	var l: Rect2 = left_rect(m)
	var ok: bool = bool(pv["ok"])
	if m.rf_confirm == 0:
		Kit.btn(m, "Reforge the Core  (+%d shards)" % int(pv["shards"]), Rect2(l.position.x + 20, l.end.y - 76, l.size.x - 40, 58), func() -> void: m.rf_confirm = 1; m._rebuild_ui(), "Reset this loop's progress for permanent shards (asks to confirm)", ok, Kit.SHARD, "REFORGE", "cur_shard", 22)
	else:
		var bw: float = (l.size.x - 52.0) * 0.5
		Kit.btn(m, "Confirm Reforge", Rect2(l.position.x + 20, l.end.y - 76, bw, 58), func() -> void: m.rf_confirm = 0; m.meta_act(Reforge.reforge(m.save, m.now())), "Reset now: +%d shards" % int(pv["shards"]), ok, Kit.ENEMY, "REFORGE CONFIRM", "", 20)
		Kit.btn(m, "Keep playing", Rect2(l.position.x + 32 + bw, l.end.y - 76, bw, 58), func() -> void: m.rf_confirm = 0; m._rebuild_ui(), "Cancel", true, Kit.NEUTRAL, "REFORGE CANCEL", "", 20)
	for id in ReforgeDB.IDS:
		var nid: String = id
		var d: Dictionary = ReforgeDB.NODES[id]
		var lv: int = Reforge.node(s, id)
		var c: Vector2 = node_pos(m, id)
		var tip: String = "%s  (%d / %d)\n%s\n%s" % [String(d["name"]), lv, int(d["max"]), String(d["desc"]), ("Next: %d shards" % ReforgeDB.cost(id, lv)) if lv < int(d["max"]) else "Maxed"]
		if id != "root_forge" and Reforge.node(s, "root_forge") <= 0:
			tip += "\nBuy Forge Root first"
		Kit.hit(m, Rect2(c - Vector2(NODE_R, NODE_R), Vector2(NODE_R, NODE_R) * 2.0), func() -> void: m.meta_act(Reforge.buy(m.save, nid)), tip, "RF " + id, Reforge.can_buy(s, id), Kit.SHARD)


static func draw(m, _cr: Rect2) -> void:
	var s: Dictionary = m.save
	var pv: Dictionary = Reforge.preview(s)
	var l: Rect2 = left_rect(m)
	Kit.panel(m, l, Kit.SHARD if bool(pv["ok"]) else Kit.EDGE, Kit.PANEL)
	var x: float = l.position.x + 24.0
	var w: float = l.size.x - 48.0
	Kit.t(m, "CORE REFORGE", Vector2(x, l.position.y + 40), 28, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
	var fb: String = " (+%d first-Reforge bonus)" % TuneRef.int_of("pc_reforge_first_bonus", 5) if Reforge.count(s) == 0 else ""
	Kit.wrap(m, "Melt this loop's progress into shards that buy permanent upgrades. Shards = %s × sqrt(coins earned since the last Reforge / %s)%s." % [String.num(Reforge.shard_k(s), 2), _commas(int(TuneRef.num("pc_reforge_l0", 10000.0))), fb], Vector2(x, l.position.y + 62), 15, Kit.DIM, w, 3)
	var y: float = l.position.y + 140.0
	Kit.icon(m, "cur_shard", Rect2(x, y, 64, 64))
	Kit.t(m, "+%d shards now" % int(pv["shards"]), Vector2(x + 80, y + 36), 30, Kit.SHARD, HORIZONTAL_ALIGNMENT_LEFT, w - 80)
	Kit.t(m, "%d banked  ·  %d earned all-time  ·  Reforges %d" % [int(s.get("shards", 0)), int(pv["cumulative"]), Reforge.count(s)], Vector2(x + 80, y + 62), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 80)
	y += 92.0
	var gate: String = "Ready to Reforge" if bool(pv["ok"]) else "Locked: reach wave %d on any tier, or earn 1,000,000 coins since the last Reforge (%s so far)" % [int(pv["gate_wave"]), Kit.fmt(float(pv["coins_since"]))]
	y += Kit.wrap(m, gate, Vector2(x, y), 16, Kit.GREEN if bool(pv["ok"]) else Kit.ENEMY, w, 3) + 8.0
	if bool(pv["ok"]):
		Kit.t(m, "Worth it: +%d is at least half of everything earned so far" % int(pv["shards"]) if bool(pv["worth"]) else "Tip: push further first — this Reforge is under half your lifetime shards", Vector2(x, y + 10), 15, Kit.GREEN if bool(pv["worth"]) else Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
		y += 30.0
	y += 16.0
	var cw: float = (w - 20.0) * 0.5
	Kit.head(m, "RESETS", Vector2(x, y), cw, Kit.ENEMY)
	Kit.head(m, "KEEPS", Vector2(x + cw + 20, y), cw, Kit.GREEN)
	var ry: float = y + 26.0
	for r in pv["resets"]:
		ry += Kit.wrap(m, "- " + String(r), Vector2(x, ry), 15, Kit.ENEMY, cw, 3) + 6.0
	var ky: float = y + 26.0
	for k in pv["keeps"]:
		ky += Kit.wrap(m, "+ " + String(k), Vector2(x + cw + 20, ky), 15, Kit.GREEN, cw, 3) + 6.0
	if m.rf_confirm == 1:
		Kit.panel(m, Rect2(x - 8, l.end.y - 140, w + 16, 52), Kit.ENEMY, Color(0.2, 0.05, 0.06, 0.95))
		Kit.t(m, "Are you sure? Coins, Core levels, part levels and research reset.", Vector2(l.get_center().x, l.end.y - 108), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	_draw_tree(m, s)


static func _draw_tree(m, s: Dictionary) -> void:
	var tr: Rect2 = tree_rect(m)
	Kit.panel(m, tr, Kit.EDGE, Kit.BG2)
	Kit.t(m, "SHARD TREE", Vector2(tr.position.x + 20, tr.position.y + 36), 22, Kit.SHARD, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
	Kit.chip(m, "cur_shard", "%d shards" % int(s.get("shards", 0)), Vector2(tr.end.x - 190, tr.position.y + 38), Kit.SHARD, "Shards to spend", 180.0)
	var root: Vector2 = node_pos(m, "root_forge")
	var colw: float = tr.size.x / 3.0
	for k in BRANCHES.size():
		var b: Array = BRANCHES[k]
		var hx: float = tr.position.x + colw * (float(k) + 0.5) - LABEL_SHIFT
		var hy: float = tr.position.y + 200.0
		var col: Color = b[3]
		m.draw_line(root, Vector2(hx, hy - 24), Color(col, 0.4), 3.0)
		Kit.icon(m, String(b[2]), Rect2(hx - 24, hy - 46, 48, 48))
		Kit.t(m, String(b[1]), Vector2(hx, hy + 18), 16, col, HORIZONTAL_ALIGNMENT_CENTER, colw)
		var ids: Array = _branch_ids(String(b[0]))
		var prev: Vector2 = Vector2(hx, hy + 24)
		for id in ids:
			var p: Vector2 = node_pos(m, String(id))
			m.draw_line(prev, p, Color(col, 0.3), 2.0)
			prev = p
	for id in ReforgeDB.IDS:
		var d: Dictionary = ReforgeDB.NODES[id]
		var lv: int = Reforge.node(s, id)
		var p2: Vector2 = node_pos(m, String(id))
		var col2: Color = Kit.SHARD
		for b2 in BRANCHES:
			if String((b2 as Array)[0]) == String(d["branch"]):
				col2 = (b2 as Array)[3]
		var can: bool = Reforge.can_buy(s, String(id))
		var r := Rect2(p2 - Vector2(NODE_R, NODE_R), Vector2(NODE_R, NODE_R) * 2.0)
		Kit.icon(m, "rf_node_owned" if lv > 0 else "rf_node_locked", r, Color.WHITE if lv > 0 or can else Color(1, 1, 1, 0.5))
		if id == "root_forge":
			Kit.icon(m, "rf_root", r.grow(-10))
		if can:
			m.draw_arc(p2, NODE_R + 4.0, 0, TAU, 40, Color(col2, 0.5 + 0.4 * sin(m.t_anim * 4.0)), 3.0)
		var lx: float = p2.x + NODE_R + 8.0
		var l1: String = "%s  %d/%d" % [String(d["name"]), lv, int(d["max"])]
		var l2: String = ("%d shards" % ReforgeDB.cost(String(id), lv)) if lv < int(d["max"]) else "max"
		# V2 P9 audit: a backing plate so connector lines never strike through labels
		var lw: float = maxf(m.font.get_string_size(l1, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, m.font.get_string_size(l2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
		m.draw_rect(Rect2(lx - 3, p2.y - 17, minf(lw, 200.0) + 6, 40), Color(Kit.BG2, 0.92))
		Kit.t(m, l1, Vector2(lx, p2.y - 2), 15, col2 if lv > 0 else Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
		Kit.t(m, l2, Vector2(lx, p2.y + 17), 14, Kit.SHARD if can else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 170.0)


static func _commas(n: int) -> String:
	var d: String = str(absi(n))
	var o: String = ""
	while d.length() > 3:
		o = "," + d.substr(d.length() - 3) + o
		d = d.substr(0, d.length() - 3)
	return ("-" if n < 0 else "") + d + o
