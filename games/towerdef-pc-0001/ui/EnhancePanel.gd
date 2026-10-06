extends RefCounted
## Core Enhancements panel (V2 P7b): the bottom of the run's right panel.
## Three tabs (Attack / Defense / Economy, TrackDB trees), a buy-mode toggle
## (x1 / x5 / MAX) and the tree's tracks as two columns of tiles: name,
## level / cap and the next level's cash cost (green when affordable).
## Overdrive tracks (the big trade-offs) carry a magenta rim and their
## drawback in the tooltip. Tile keys "TRACK <name>", tabs "ETAB <tree>",
## mode "EMODE"; Shift+1-5 buys the open tree's first five tracks. Tracks
## gated by Enhancement Theory research (V2 P8) show "Needs Theory II" etc.

const TowerState := preload("res://TowerState.gd")
const TrackDB := preload("res://data/TrackDB.gd")
const Kit := preload("res://ui/Kit.gd")
const Labs := preload("res://Labs.gd")

const MODES: Array = [1, 5, 0]   # 0 = MAX


static func mode_label(n: int) -> String:
	return "MAX" if n <= 0 else "x%d" % n


## Tabs + mode button row; the tiles fill from `top` to the panel bottom.
static func area(m) -> Rect2:
	var rr: Rect2 = m.right_rect()
	var top: float = _top(m)
	return Rect2(rr.position.x + 16.0, top, rr.size.x - 32.0, rr.end.y - top - 10.0)


static func _top(m) -> float:
	var rr: Rect2 = m.right_rect()
	var th: float = clampf((m.vh - 1080.0) * 0.05 + 62.0, 50.0, 66.0)
	return rr.end.y - 5.0 * (th + 6.0) - 46.0


static func tab_rect(m) -> Rect2:
	var a: Rect2 = area(m)
	return Rect2(a.position.x, a.position.y, a.size.x - (140.0 if has_auto(m) else 70.0), 34.0)


## V2 P8b: the Auto-Buy switch sits left of the buy mode once researched.
static func has_auto(m) -> bool:
	return Labs.level(m.save, "auto_buy") > 0


static func auto_rect(m) -> Rect2:
	var a: Rect2 = area(m)
	return Rect2(a.end.x - 134.0, a.position.y, 64.0, 34.0)


static func auto_label(mode_ab: String) -> String:
	return {"": "AUTO", "attack": "A:ATK", "defense": "A:DEF", "economy": "A:ECO", "all": "A:ALL"}.get(mode_ab, "AUTO")


static func mode_rect(m) -> Rect2:
	var a: Rect2 = area(m)
	return Rect2(a.end.x - 64.0, a.position.y, 64.0, 34.0)


static func tile_rect(m, k: int, n: int) -> Rect2:
	var a: Rect2 = area(m)
	var top: float = a.position.y + 42.0
	var rows: int = int(ceil(float(n) / 2.0))
	var rh: float = minf(52.0, (a.end.y - top - 4.0 * float(rows - 1)) / float(maxi(1, rows)))
	var cw: float = (a.size.x - 6.0) * 0.5
	return Rect2(a.position.x + float(k % 2) * (cw + 6.0), top + float(k / 2) * (rh + 4.0), cw, rh)


static func ids(m) -> Array:
	return TrackDB.tree_ids(String(m.enh_tree))


static func tip(m, tid: String) -> String:
	var S = m.S
	var d: Dictionary = TrackDB.get_def(tid)
	var c: int = S.track_cost(tid)
	var lv: int = int(S.tracks.get(tid, 0))
	var head: String = "%s enhancement%s" % [String(d["name"]), "  (OVERDRIVE)" if TrackDB.is_od(tid) else ""]
	var lines: Array = [head, "Per level: %s" % String(d["desc"])]
	if TrackDB.is_od(tid):
		lines.append("Drawback per level: %s" % String(d.get("minus", "")))
	if not S.track_unlocked(tid):
		lines.append("LOCKED: research %s in the Research Hall" % TrackDB.unlock_label(tid))
	lines.append("Level %d / %d  ·  %s" % [lv, TowerState.track_cap(tid), ("next $%s" % Kit.fmt(float(c))) if c >= 0 else "maxed"])
	lines.append("Buy mode %s (toggle at the top right)" % mode_label(int(m.enh_mode)))
	return "\n".join(PackedStringArray(lines))


static func build(m) -> void:
	var S = m.S
	var items: Array = []
	for tr in TrackDB.TREES:
		var tid: String = String((tr as Array)[0])
		items.append([tid, String((tr as Array)[1]), "", "Core Enhancements: %s tree" % String((tr as Array)[1])])
	Kit.tabs(m, tab_rect(m), items, String(m.enh_tree), func(id: String) -> void: m.enh_tree = id; m._rebuild_ui(), "ETAB ", [], 15)
	Kit.btn(m, mode_label(int(m.enh_mode)), mode_rect(m), func() -> void: m.cycle_enh_mode(), "Buy mode: x1 / x5 / MAX levels per click", true, Kit.GOLD, "EMODE", "", 15)
	if has_auto(m):
		var ab: String = String(S.mods.get("auto_buy", ""))
		Kit.btn(m, auto_label(ab), auto_rect(m), func() -> void: m.cycle_auto_buy(),
			"Auto-Buy (research): at each wave start, buy the cheapest open track of a tree, keeping 25%% of your cash.\nNow: %s. Click: off / Attack / Defense / Economy / all trees" % ("off" if ab == "" else ab.capitalize()), true, Kit.GREEN if ab != "" else Kit.NEUTRAL, "EAUTO", "", 14)
	var li: Array = ids(m)
	for k in li.size():
		var tid: String = String(li[k])
		var c: int = S.track_cost(tid)
		Kit.hit(m, tile_rect(m, k, li.size()), func() -> void: m.buy_track(tid), tip(m, tid), "TRACK " + String(TrackDB.get_def(tid)["name"]), c >= 0 and S.cash >= float(c) and S.track_unlocked(tid), Kit.GREEN)


static func draw(m) -> void:
	var S = m.S
	var a: Rect2 = area(m)
	Kit.head(m, "CORE ENHANCEMENTS  (cash, this run)", Vector2(a.position.x, a.position.y - 12), a.size.x)
	var li: Array = ids(m)
	for k in li.size():
		var tid: String = String(li[k])
		var d: Dictionary = TrackDB.get_def(tid)
		var r: Rect2 = tile_rect(m, k, li.size())
		var c: int = S.track_cost(tid)
		var lv: int = int(S.tracks.get(tid, 0))
		var can: bool = c >= 0 and S.cash >= float(c) and S.track_unlocked(tid)
		var od: bool = TrackDB.is_od(tid)
		var locked: bool = not S.track_unlocked(tid)
		var rim: Color = Kit.MAGENTA if od else (Kit.GREEN if can else Kit.EDGE)
		Kit.panel(m, r, rim, Kit.tint(Kit.GREEN, 0.12) if can else (Kit.tint(Kit.MAGENTA, 0.08) if od else Kit.PANEL), 1)
		# level bar along the bottom edge
		var cap: int = maxi(1, TowerState.track_cap(tid))
		var fr: float = float(lv) / float(cap)
		m.draw_rect(Rect2(r.position.x + 3, r.end.y - 4, (r.size.x - 6) * fr, 2), Kit.MAGENTA if od else Kit.CYAN)
		var ty: float = r.position.y + maxf(16.0, r.size.y * 0.46)
		Kit.t(m, String(d["name"]), Vector2(r.position.x + 7, ty), 14, Kit.TEXT if (can or lv > 0) else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 14)
		var ly: float = r.end.y - 6.0
		if locked:
			# V2 P8: research-gated track - the Theory that opens it
			Kit.t(m, TrackDB.unlock_label(tid).replace("Enhancement Theory", "Needs Theory"), Vector2(r.position.x + 7, ly), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 14)
			continue
		Kit.t(m, ("Lv %d" % lv) if c >= 0 else "MAX", Vector2(r.position.x + 7, ly), 14, Kit.DIM if c >= 0 else Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.5)
		if c >= 0:
			Kit.t(m, "$" + Kit.fmt(float(c)), Vector2(r.end.x - 7, ly), 14, Kit.GREEN if can else Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x * 0.6)
