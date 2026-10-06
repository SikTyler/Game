extends RefCounted
## The loot reveal (V2 P5, an overlay on the results screen): the run's
## banked items, one card at a time, casino style. Each card starts face
## down while a beam climbs from white to its rarity colour, then flips with
## a rising-pitch sting and a shake scaled to the rarity, and its perks tick
## in one by one. Caches reveal worst to best (Loot.realize order). REVEAL
## ALL skips the show; the Fast Reveal research halves it. Visible pity bars
## and the disclosed odds sit at the bottom; EQUIP works from a revealed card.
## Button keys (uitest): loot:all, loot:done, loot:page:+, loot:equip:<uid>.
## State on Main: reveal_uids, reveal_t0, reveal_fired, reveal_skip, reveal_page.

const Gear := preload("res://Gear.gd")
const GearVis := preload("res://GearVis.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const LootDB := preload("res://data/LootDB.gd")
const Labs := preload("res://Labs.gd")
const Sfx := preload("res://Sfx.gd")
const Kit := preload("res://ui/Kit.gd")

const PER_PAGE: int = 10
const STEP: float = 0.9          # seconds per card (Fast Reveal: half)
const FLIP: float = 0.55         # share of a card's step spent face down
const PERK_S: float = 0.12       # perk tick-in spacing
const CARD: Vector2 = Vector2(252, 300)


static func step_s(m) -> float:
	return STEP * (0.5 if Labs.level(m.save, "fast_reveal") > 0 else 1.0)


## Open the reveal over the given uids (from Loot.realize events).
static func open(m, uids: Array) -> void:
	m.reveal_uids = uids.duplicate()
	m.reveal_t0 = m.t_anim
	m.reveal_fired = 0
	m.reveal_skip = false
	m.reveal_page = 0
	m.set_overlay("loot")


static func modal(m) -> Rect2:
	return Rect2(floorf((m.vw - 1500.0) * 0.5), floorf((m.vh - 940.0) * 0.5), minf(1500.0, m.vw - 16.0), minf(940.0, m.vh - 16.0))


static func card_rect(m, k: int) -> Rect2:
	var r: Rect2 = modal(m)
	var cols: int = 5
	var gap: float = (r.size.x - 48.0 - float(cols) * CARD.x) / float(cols - 1)
	return Rect2(r.position.x + 24.0 + float(k % cols) * (CARD.x + gap), r.position.y + 92.0 + float(k / cols) * (CARD.y + 64.0), CARD.x, CARD.y)


static func _page_uids(m) -> Array:
	var all: Array = m.reveal_uids
	var p0: int = int(m.reveal_page) * PER_PAGE
	return all.slice(p0, mini(all.size(), p0 + PER_PAGE))


static func _pages(m) -> int:
	return maxi(1, int(ceil(float((m.reveal_uids as Array).size()) / float(PER_PAGE))))


## Seconds into card k's show (huge when skipped).
static func card_t(m, k: int) -> float:
	if bool(m.reveal_skip):
		return 999.0
	return float(m.t_anim) - float(m.reveal_t0) - float(k) * step_s(m)


static func flipped(m, k: int) -> bool:
	return card_t(m, k) >= FLIP * step_s(m)


static func done(m) -> bool:
	return flipped(m, _page_uids(m).size() - 1) or _page_uids(m).is_empty()


# ------------------------------------------------------------------ tick

## Main._process while the overlay is up: one sting + shake per flip, and a
## rebuild so the revealed card's EQUIP button appears.
static func tick(m) -> void:
	var lst: Array = _page_uids(m)
	var n: int = 0
	for k in lst.size():
		if flipped(m, k):
			n = k + 1
	if n > int(m.reveal_fired):
		for k in range(int(m.reveal_fired), n):
			var it: Dictionary = Gear.item(m.save, int(lst[k]))
			var rk: int = maxi(0, RarityDB.rank(String(it.get("rar", "common"))))
			if not bool(m.reveal_skip):
				m.sfx_play("card_open" if rk < 3 else "levelup", Sfx.seq_pitch(k + rk))
				m.juice.shake(float(rk))
		m.reveal_fired = n
		m._rebuild_ui()


# ------------------------------------------------------------------ build

static func build(m) -> void:
	var r: Rect2 = modal(m)
	var lst: Array = _page_uids(m)
	for k in lst.size():
		if not flipped(m, k):
			continue
		var uid: int = int(lst[k])
		var it: Dictionary = Gear.item(m.save, uid)
		if it.is_empty():
			continue
		var cr: Rect2 = card_rect(m, k)
		var eq: bool = Gear.is_equipped(m.save, uid)
		var why: String = Gear.why_equip(m.save, uid)
		Kit.btn(m, "EQUIPPED" if eq else "EQUIP", Rect2(cr.position.x, cr.end.y + 10.0, cr.size.x, 44.0), func() -> void: m.meta_act(Gear.equip(m.save, uid)),
			("Mount on the Core" if String(it["kind"]) == "weapon" else "Socket into a free Module slot") + ("" if why == "" else "\n" + why), not eq and why == "", Kit.GREEN, "loot:equip:%d" % uid, "", 16)
	var bw: float = 260.0
	if not done(m):
		Kit.btn(m, "REVEAL ALL", Rect2(r.end.x - 2.0 * bw - 40.0, r.end.y - 70.0, bw, 54.0), func() -> void:
			m.reveal_skip = true
			m.reveal_fired = PER_PAGE
			m._rebuild_ui(), "Skip the show", true, Kit.MAGENTA, "loot:all", "", 18)
	elif int(m.reveal_page) < _pages(m) - 1:
		Kit.btn(m, "NEXT  %d / %d" % [int(m.reveal_page) + 2, _pages(m)], Rect2(r.end.x - 2.0 * bw - 40.0, r.end.y - 70.0, bw, 54.0), func() -> void:
			m.reveal_page = int(m.reveal_page) + 1
			m.reveal_t0 = m.t_anim
			m.reveal_fired = 0
			m.reveal_skip = false
			m._rebuild_ui(), "The next items", true, Kit.GOLD, "loot:page:+", "", 18)
	Kit.btn(m, "DONE", Rect2(r.end.x - bw - 24.0, r.end.y - 70.0, bw, 54.0), func() -> void:
		Gear.block(m.save)   # items stay NEW until seen in the Forge
		m.set_overlay(""), "Close (everything is already in your inventory)", true, Kit.GOLD, "loot:done", "", 20)


# ------------------------------------------------------------------ draw

static func draw(m) -> void:
	var r: Rect2 = modal(m)
	Kit.panel_glow(m, r, Kit.GOLD, Kit.PANEL2, 1.4, 2)
	var all: Array = m.reveal_uids
	Kit.th(m, "LOOT", Vector2(r.position.x + 28, r.position.y + 54), 34, Kit.GOLD)
	# V2 P9 audit: no "best: Legendary" spoiler before the cards flip
	Kit.t(m, "%d items  ·  everything is already in your inventory" % all.size(), Vector2(r.position.x + 140, r.position.y + 50), 17, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 400.0)
	var lst: Array = _page_uids(m)
	for k in lst.size():
		_card(m, k, Gear.item(m.save, int(lst[k])))
	if all.is_empty():
		Kit.t(m, "No items this run - elites, bosses, Couriers and every 5th wave drop them.", Vector2(r.get_center().x, r.get_center().y), 20, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# visible pity + disclosed odds
	var pity: Dictionary = Gear.block(m.save)["pity"]
	var px: float = r.position.x + 28.0
	var py: float = r.end.y - 64.0
	var pw: float = (r.size.x - 640.0) / 3.0
	var names: Dictionary = {"e": "Epic+", "l": "Legendary+", "m": "Mythic+"}
	var ks: Array = ["e", "l", "m"]
	for i in ks.size():
		var g: String = ks[i]
		var pd: Dictionary = RarityDB.PITY[g]
		var x: float = px + float(i) * (pw + 16.0)
		var col: Color = Kit.rarity_col(String(pd["min"]))
		Kit.th(m, "%s within %d drops" % [names[g], maxi(1, int(pd["hard"]) - int(pity.get(g, 0)))], Vector2(x, py), 15, Kit.rarity_text(String(pd["min"])), HORIZONTAL_ALIGNMENT_LEFT, pw)
		Kit.bar_glow(m, Rect2(x, py + 10.0, pw, 10.0), float(pity.get(g, 0)) / float(pd["hard"]), col)
	var od: Dictionary = RarityDB.odds("drop")
	var lines: Array = ["Drop odds (before luck):"]
	for rid in RarityDB.IDS:
		lines.append("%s  %.2f%%" % [String(RarityDB.get_def(String(rid))["name"]), float(od[rid])])
	lines.append("")
	lines.append(LootDB.disclosure())
	m.stat_tips.append([Rect2(px, py - 22.0, 3.0 * pw + 32.0, 44.0), "\n".join(lines)])


static func _card(m, k: int, it: Dictionary) -> void:
	if it.is_empty():
		return
	var r: Rect2 = card_rect(m, k)
	var ct: float = card_t(m, k)
	if ct < 0.0:
		# not yet: a dim slot
		m.draw_style_box(Kit.sb(Kit.EDGE2, Color(Kit.BG2, 0.6), 1, 10), r)
		return
	var rar: String = String(it["rar"])
	var col: Color = Kit.rarity_col_t(rar, m.t_anim)
	var st: float = step_s(m)
	if ct < FLIP * st:
		# face down: the beam climbs, white -> the rarity colour
		var f: float = clampf(ct / (FLIP * st), 0.0, 1.0)
		var bc: Color = Color.WHITE.lerp(col, f * f)
		m.draw_style_box(Kit.sb(bc, Kit.CARD, 2, 10, 0.4 + 1.2 * f), r)
		for j in 5:
			var y: float = r.position.y + 30.0 + float(j) * 50.0
			m.draw_line(Vector2(r.position.x + 20, y), Vector2(r.end.x - 20, y + 30), Color(bc, 0.10), 2.0)
		Kit.beam_col(m, Vector2(r.get_center().x, r.end.y - 20.0), bc, (r.size.y + 120.0) * f, 70.0, m.t_anim, 0.3 + 0.5 * f)
		Kit.th(m, "?", Vector2(r.get_center().x, r.get_center().y + 20), 64, Color(bc, 0.8), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	# face up
	var since: float = ct - FLIP * st
	Kit.card_frame(m, r, rar, m.t_anim, since < 0.4)
	if since < 0.6:
		Kit.glow(m, r.get_center(), r.size.x * (0.9 + since), col, 0.45 * (1.0 - since / 0.6))
	var art: Vector2 = Vector2(r.get_center().x, r.position.y + 80.0)
	if String(it["kind"]) == "weapon":
		GearVis.draw_weapon(m, it, art, r.size.x * 0.78, 0.0, m.t_anim)
	else:
		GearVis.draw_module(m, it, art, 84.0, m.t_anim)
	Kit.th(m, String(RarityDB.get_def(rar)["name"]).to_upper(), Vector2(r.get_center().x, r.position.y + 150.0), 16, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 16.0)
	Kit.wrap(m, String(it["name"]), Vector2(r.position.x + 12.0, r.position.y + 158.0), 15, Kit.TEXT, r.size.x - 24.0, 2, HORIZONTAL_ALIGNMENT_CENTER)
	var ps: Array = it["perks"]
	for i in ps.size():
		if since < PERK_S * float(i + 1) and not bool(m.reveal_skip):
			break
		var p: Dictionary = ps[i]
		var y: float = r.position.y + 222.0 + float(i) * 19.0
		if y > r.end.y - 6.0:
			break
		Kit.t(m, Kit.fit(m, "T%d %s" % [int(p["t"]), AffixDB.text(String(p["id"]), int(p["t"]), float(p["q"]))], 14, r.size.x - 24.0), Vector2(r.position.x + 12.0, y), 14, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24.0)
