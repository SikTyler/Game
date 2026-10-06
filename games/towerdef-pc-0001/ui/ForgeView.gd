extends RefCounted
## The Forge tab (V2 P4d): the gear workshop. Three columns:
##   INVENTORY  filters, a paged grid of item tiles (procedural art, rarity
##              frame, level, NEW / equipped / favourite marks)
##   ITEM CARD  the selected item: art, name, rarity, brand quirk, level,
##              power, est. DPS vs the equipped weapon, perks with LOCK and
##              REROLL (the reroll offer: take one or keep), and the verbs
##              Equip / Upgrade / Merge / Imprint / Salvage / Favourite
##   FORGE      forge a chosen frame or module, its cost, visible pity bars
##              and the disclosed odds (live: luck + pity)
## View only: buttons call Gear and hand events to Main.meta_act(). Button
## keys (uitest): forge:filter:<f>, forge:item:<uid>, forge:page:-/+,
## forge:lock:<i>, forge:reroll:<i>, forge:take:<k>, forge:keep, forge:equip,
## forge:upgrade, forge:merge (+ forge:merge:pick:<k> / :go / :cancel),
## forge:imprint (+ forge:imp:<b>:<a> / forge:imprint:cancel), forge:salvage,
## forge:fav, forge:kind:<weapon|module>, forge:new:<frame|module>.

const Gear := preload("res://Gear.gd")
const GearGen := preload("res://GearGen.gd")
const GearVis := preload("res://GearVis.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const ModuleDB := preload("res://data/ModuleDB.gd")
const BrandDB := preload("res://data/BrandDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const Kit := preload("res://ui/Kit.gd")
const Labs := preload("res://Labs.gd")

const COLS: int = 5
const ROWS: int = 6
const TILE: float = 108.0
const GAP: float = 8.0
const FILTERS: Array = [["all", "All"], ["weapon", "Weapons"], ["module", "Modules"]]
const REVEAL_S: float = 1.6


# ------------------------------------------------------------------ layout

static func rects(m) -> Dictionary:
	var cr: Rect2 = m.content_rect()
	var top: float = cr.position.y + 12.0
	var h: float = cr.size.y - 24.0
	var lw: float = float(COLS) * (TILE + GAP) - GAP + 32.0
	var rest: float = cr.size.x - lw - 80.0
	var mw: float = rest * 0.5
	return {
		"inv": Rect2(cr.position.x + 20.0, top, lw, h),
		"card": Rect2(cr.position.x + 40.0 + lw, top, mw, h),
		"new": Rect2(cr.position.x + 60.0 + lw + mw, top, rest - mw, h),
	}


static func tile_rect(m, k: int) -> Rect2:
	var inv: Rect2 = rects(m)["inv"]
	return Rect2(inv.position.x + 16.0 + float(k % COLS) * (TILE + GAP), inv.position.y + 112.0 + float(k / COLS) * (TILE + GAP), TILE, TILE)


static func _perk_row(m, i: int) -> Rect2:
	var c: Rect2 = rects(m)["card"]
	return Rect2(c.position.x + 16.0, c.position.y + 496.0 + float(i) * 50.0, c.size.x - 32.0, 44.0)


static func _act_rect(m, k: int) -> Rect2:
	var c: Rect2 = rects(m)["card"]
	var w: float = (c.size.x - 32.0 - 16.0) / 3.0
	return Rect2(c.position.x + 16.0 + float(k % 3) * (w + 8.0), c.end.y - 116.0 + float(k / 3) * 56.0, w, 48.0)


## Bulk Upgrade row: right two thirds above the verb grid.
static func _bulk_rect(m, k: int) -> Rect2:
	var a: Rect2 = _act_rect(m, 1 + k)
	return Rect2(a.position.x, a.position.y - 56.0, a.size.x, a.size.y)


## Auto-Salvage switch: the bottom of the Forge panel.
static func _auto_salvage_rect(m) -> Rect2:
	var n: Rect2 = rects(m)["new"]
	return Rect2(n.position.x + 16.0, n.end.y - 60.0, n.size.x - 32.0, 44.0)


static func auto_salvage_label(lv: int) -> String:
	return ["AUTO-SALVAGE: OFF", "AUTO-SALVAGE: COMMONS", "AUTO-SALVAGE: UP TO UNCOMMON"][clampi(lv, 0, 2)]


static func _new_rect(m, k: int, kind: String) -> Rect2:
	var n: Rect2 = rects(m)["new"]
	var cols: int = 2 if kind == "weapon" else 3
	var h: float = 62.0 if kind == "weapon" else 44.0
	var w: float = (n.size.x - 32.0 - float(cols - 1) * 8.0) / float(cols)
	return Rect2(n.position.x + 16.0 + float(k % cols) * (w + 8.0), n.position.y + 116.0 + float(k / cols) * (h + 6.0), w, h)


# ------------------------------------------------------------------ data

## Visible uids for the filter: best rarity first, newest first within it.
static func _list(m) -> Array:
	var s: Dictionary = m.save
	var f: String = String(m.forge_filter)
	var out: Array = Gear.uids(s, "" if f == "all" else f)
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ra: int = RarityDB.rank(String(Gear.item(s, int(a))["rar"]))
		var rb: int = RarityDB.rank(String(Gear.item(s, int(b))["rar"]))
		return ra > rb or (ra == rb and int(a) > int(b)))
	return out


static func _pages(m) -> int:
	return maxi(1, int(ceil(float(_list(m).size()) / float(COLS * ROWS))))


static func _sel(m) -> Dictionary:
	return Gear.item(m.save, int(m.forge_sel))


## Keep a valid selection (the equipped weapon by default).
static func _ensure_sel(m) -> void:
	if Gear.item(m.save, int(m.forge_sel)).is_empty():
		m.forge_sel = int((Gear.block(m.save)["equipped"] as Dictionary)["weapon"])
	m.forge_page = clampi(int(m.forge_page), 0, _pages(m) - 1)


## The two partners a merge would consume with the selected item: same kind
## and rarity, not favourite, unequipped and lowest level first ([] if fewer
## than two).
static func merge_set(m) -> Array:
	var s: Dictionary = m.save
	var it: Dictionary = _sel(m)
	if it.is_empty():
		return []
	var cands: Array = []
	for u in Gear.uids(s, String(it["kind"])):
		var o: Dictionary = Gear.item(s, int(u))
		if int(u) != int(it["uid"]) and String(o["rar"]) == String(it["rar"]) and not bool(o.get("fav", false)):
			cands.append(int(u))
	cands.sort_custom(func(a: Variant, b: Variant) -> bool: return _merge_key(s, int(a)) < _merge_key(s, int(b)))
	if cands.size() < 2:
		return []
	return [int(it["uid"]), int(cands[0]), int(cands[1])]


## Partner order: unequipped first, then the lowest level, then the oldest.
static func _merge_key(s: Dictionary, u: int) -> int:
	return (1_000_000 if Gear.is_equipped(s, u) else 0) + int(Gear.item(s, u)["lvl"]) * 10_000 + mini(9_999, u)


static func _rar_name(r: String) -> String:
	return String(RarityDB.get_def(r)["name"])


static func _act(m, ev: Array) -> void:
	m.meta_act(ev)


# ------------------------------------------------------------------ build

static func build(m) -> void:
	_ensure_sel(m)
	var s: Dictionary = m.save
	var g: Dictionary = Gear.block(s)
	var R: Dictionary = rects(m)
	var inv: Rect2 = R["inv"]
	# filters
	var fw: float = (inv.size.x - 32.0 - 16.0) / 3.0
	for k in FILTERS.size():
		var fid: String = String(FILTERS[k][0])
		var on: bool = String(m.forge_filter) == fid
		Kit.btn(m, String(FILTERS[k][1]), Rect2(inv.position.x + 16.0 + float(k) * (fw + 8.0), inv.position.y + 56.0, fw, 44.0), func() -> void:
			m.forge_filter = fid
			m.forge_page = 0
			m._rebuild_ui(), "Show %s" % String(FILTERS[k][1]).to_lower(), true, Kit.CYAN if on else Kit.NEUTRAL, "forge:filter:" + fid, "", 16)
	# V2 P8b Auto-Salvage switch (bottom of the Forge panel)
	if Labs.level(s, "auto_salvage") > 0:
		Kit.btn(m, auto_salvage_label(Labs.auto_salvage_level(s)), _auto_salvage_rect(m), func() -> void:
			Labs.cycle_auto_salvage(m.save)
			m._save()
			m._rebuild_ui(), "Auto-Salvage (research): banked items below the chosen rarity turn into Scrap on arrival. Click: off / Commons / up to Uncommon (Lv 2).", true, Kit.ENEMY if Labs.auto_salvage_level(s) > 0 else Kit.NEUTRAL, "forge:autosalvage", "cur_scrap", 15)
	# tiles
	var lst: Array = _list(m)
	var per: int = COLS * ROWS
	var p0: int = int(m.forge_page) * per
	for k in mini(per, lst.size() - p0):
		var uid: int = int(lst[p0 + k])
		var it: Dictionary = Gear.item(s, uid)
		Kit.hit(m, tile_rect(m, k), func() -> void: _click_tile(m, uid), _tile_tip(m, it), "forge:item:%d" % uid, true, Kit.rarity_col(String(it["rar"])))
	var py: float = inv.end.y - 54.0
	Kit.btn(m, "<", Rect2(inv.position.x + 16.0, py, 64.0, 44.0), func() -> void:
		m.forge_page = int(m.forge_page) - 1
		m._rebuild_ui(), "Previous page", int(m.forge_page) > 0, Kit.NEUTRAL, "forge:page:-", "", 20)
	Kit.btn(m, ">", Rect2(inv.end.x - 80.0, py, 64.0, 44.0), func() -> void:
		m.forge_page = int(m.forge_page) + 1
		m._rebuild_ui(), "Next page", int(m.forge_page) < _pages(m) - 1, Kit.NEUTRAL, "forge:page:+", "", 20)
	_build_card(m, s, g)
	_build_new(m, s)


static func _click_tile(m, uid: int) -> void:
	if int(m.forge_imprint) > 0 and uid != int(m.forge_imprint):
		m.forge_donor = uid
	else:
		m.forge_sel = uid
		m.forge_merge = []
		m.forge_imprint = 0
		m.forge_donor = 0
		m.forge_confirm = 0
		Gear.mark_seen(m.save, uid)
		m._save()
	m._rebuild_ui()


static func _tile_tip(m, it: Dictionary) -> String:
	var lines: Array = ["%s\n%s %s  ·  Lv %d / %d" % [String(it["name"]), _rar_name(String(it["rar"])), "Weapon" if String(it["kind"]) == "weapon" else "Module", int(it["lvl"]), Gear.max_lvl_of(String(it["rar"]))]]
	for p in it["perks"]:
		lines.append("T%d  %s" % [int((p as Dictionary)["t"]), AffixDB.text(String(p["id"]), int(p["t"]), float(p["q"]))])
	if Gear.is_equipped(m.save, int(it["uid"])):
		lines.append("EQUIPPED")
	if int(m.forge_imprint) > 0 and int(it["uid"]) != int(m.forge_imprint):
		lines.append("Click: use as the imprint donor")
	return "\n".join(lines)


static func _build_card(m, s: Dictionary, g: Dictionary) -> void:
	var it: Dictionary = _sel(m)
	if it.is_empty():
		return
	var uid: int = int(it["uid"])
	var ps: Array = it["perks"]
	var of: Dictionary = g.get("offer", {})
	var panel_open: bool = (not of.is_empty() and int(of["uid"]) == uid) or not (m.forge_merge as Array).is_empty() or int(m.forge_imprint) == uid
	if not panel_open:
		for i in ps.size():
			var idx: int = i
			var pr: Rect2 = _perk_row(m, i)
			var p: Dictionary = ps[i]
			var locked: bool = bool(p.get("lock", false))
			var why_l: String = Gear.why_lock(s, uid, i, not locked)
			Kit.btn(m, "LOCKED" if locked else "LOCK", Rect2(pr.end.x - 214.0, pr.position.y, 100.0, 44.0), func() -> void: _act(m, Gear.lock(m.save, uid, idx, not locked)),
				("Unlock: rerolls may change this perk again" if locked else "Lock: rerolls keep this perk (each lock x4 reroll cost)") + "\nLock slots: %d / %d" % [Gear.locks_on(it), Gear.lock_slots(s)] + ("" if why_l == "" else "\n" + why_l),
				why_l == "", Kit.GOLD if locked else Kit.NEUTRAL, "forge:lock:%d" % i, "", 15)
			var why_r: String = Gear.why_reroll(s, uid, i)
			Kit.btn(m, "%s" % Kit.fmt(float(Gear.reroll_cost(it, s))), Rect2(pr.end.x - 106.0, pr.position.y, 106.0, 44.0), func() -> void: _act(m, Gear.reroll(m.save, uid, idx)),
				"Reroll this perk for %d Scrap: pick one of %d new perks or keep it (never above T5)%s" % [Gear.reroll_cost(it, s), Gear.reroll_options(s), "" if why_r == "" else "\n" + why_r],
				why_r == "", Kit.MAGENTA, "forge:reroll:%d" % i, "cur_scrap", 15)
	elif not of.is_empty() and int(of["uid"]) == uid:
		var cands: Array = of["cands"]
		for k in cands.size():
			var kk: int = k
			var c: Dictionary = cands[k]
			Kit.btn(m, "T%d  %s" % [int(c["t"]), AffixDB.text(String(c["id"]), int(c["t"]), float(c["q"]))], _perk_row(m, k + 1), func() -> void: _act(m, Gear.reroll_choose(m.save, kk)),
				"Take this perk (replaces %s)" % String(AffixDB.get_def(String(((ps[int(of["idx"])]) as Dictionary)["id"])).get("name", "")), true, Kit.MAGENTA, "forge:take:%d" % k, "", 16)
		Kit.btn(m, "KEEP CURRENT", _perk_row(m, cands.size() + 1), func() -> void: _act(m, Gear.reroll_choose(m.save, -1)), "Keep the perk you have", true, Kit.NEUTRAL, "forge:keep", "", 16)
	elif not (m.forge_merge as Array).is_empty():
		var set3: Array = m.forge_merge
		var ch: Array = Gear.merge_choices(s, set3, uid)
		var nx: String = RarityDB.next(String(it["rar"]))
		if ch.is_empty():
			Kit.btn(m, "MERGE INTO %s" % _rar_name(nx).to_upper(), _perk_row(m, 2), func() -> void: _do_merge(m, set3, uid, 0),
				"Consume the other two: rarity -> %s, +1 tier on the weakest perk, level halves" % _rar_name(nx), Gear.why_merge(s, set3, uid) == "", Kit.GOLD, "forge:merge:go", "", 17)
		else:
			for k in ch.size():
				var kk2: int = k
				var c2: Dictionary = ch[k]
				Kit.btn(m, "+ T%d  %s" % [int(c2["t"]), AffixDB.text(String(c2["id"]), int(c2["t"]), float(c2["q"]))], _perk_row(m, k + 1), func() -> void: _do_merge(m, set3, uid, kk2),
					"Merge into %s and take this perk in the new slot" % _rar_name(nx), Gear.why_merge(s, set3, uid) == "", Kit.GOLD, "forge:merge:pick:%d" % k, "", 16)
		Kit.btn(m, "CANCEL", _perk_row(m, 5), func() -> void:
			m.forge_merge = []
			m._rebuild_ui(), "Back to the item", true, Kit.NEUTRAL, "forge:merge:cancel", "", 16)
	else:
		# imprint: a donor's perk over one of this item's slots
		var donor: Dictionary = Gear.item(s, int(m.forge_donor))
		if not donor.is_empty():
			var row: int = 0
			for b in (donor["perks"] as Array).size():
				for a in ps.size():
					if row >= 5:
						break
					var why_i: String = Gear.why_imprint(s, uid, int(donor["uid"]), b, a)
					if why_i != "" and not why_i.begins_with("Need"):
						continue
					var bb: int = b
					var aa: int = a
					var dp: Dictionary = (donor["perks"] as Array)[b]
					var ap: Dictionary = ps[a]
					Kit.btn(m, "%s  ->  slot %d" % [String(AffixDB.get_def(String(dp["id"])).get("name", "")), a + 1], _perk_row(m, row), func() -> void: _do_imprint(m, uid, int(donor["uid"]), bb, aa),
						"Destroy %s and copy T%d %s over %s (%d Scrap)%s" % [String(donor["name"]), int(dp["t"]), AffixDB.text(String(dp["id"]), int(dp["t"]), float(dp["q"])), String(AffixDB.get_def(String(ap["id"])).get("name", "")), Gear.imprint_cost(it), "" if why_i == "" else "\n" + why_i],
						why_i == "", Kit.LAB, "forge:imp:%d:%d" % [b, a], "", 15)
					row += 1
		Kit.btn(m, "CANCEL", _perk_row(m, 5), func() -> void:
			m.forge_imprint = 0
			m.forge_donor = 0
			m._rebuild_ui(), "Stop imprinting", true, Kit.NEUTRAL, "forge:imprint:cancel", "", 16)
	# verbs
	var eq: bool = Gear.is_equipped(s, uid)
	var why_e: String = Gear.why_equip(s, uid)
	Kit.btn(m, "EQUIPPED" if eq else "EQUIP", _act_rect(m, 0), func() -> void: _act(m, Gear.equip(m.save, uid)),
		("Mount on the Core's centre" if String(it["kind"]) == "weapon" else "Socket into the first free Module slot") + ("" if why_e == "" else "\n" + why_e), not eq and why_e == "", Kit.GREEN, "forge:equip", "", 17)
	var why_u: String = Gear.why_upgrade(s, uid)
	Kit.btn(m, "UPGRADE %s" % Kit.fmt(float(Gear.upgrade_cost(it, m.save))), _act_rect(m, 1), func() -> void: _act(m, Gear.upgrade(m.save, uid)),
		"+1 level (+5%% power) for %d coins. Every 5th level is a MASTERWORK: +6%% power and a perk +1 tier (jackpot %d%%: +2 tiers or a bonus perk)%s" % [Gear.upgrade_cost(it, m.save), int(round(Gear.jackpot_chance(s) * 100.0)), "" if why_u == "" else "\n" + why_u],
		why_u == "", Kit.GOLD, "forge:upgrade", "cur_coin", 16)
	if Labs.level(s, "bulk_upgrade") > 0:
		# V2 P8b Bulk Upgrade: a row above the verbs
		Kit.btn(m, "UPGRADE x5", _bulk_rect(m, 0), func() -> void: _act(m, Gear.upgrade_n(m.save, uid, 5)), "Up to five levels at once (stops when coins run out or at the cap)", why_u == "", Kit.GOLD, "forge:up5", "cur_coin", 15)
		Kit.btn(m, "UPGRADE MAX", _bulk_rect(m, 1), func() -> void: _act(m, Gear.upgrade_n(m.save, uid, 0)), "Every level your coins cover, up to the rarity's cap", why_u == "", Kit.GOLD, "forge:upmax", "cur_coin", 15)
	var ms: Array = merge_set(m)
	var why_m: String = "Need two more %s %ss (not favourites)" % [_rar_name(String(it["rar"])), String(it["kind"])] if ms.is_empty() else Gear.why_merge(s, ms, uid)
	Kit.btn(m, "MERGE", _act_rect(m, 2), func() -> void:
		m.forge_merge = merge_set(m)
		m._rebuild_ui(), "Merge 3 of the same kind and rarity into the next rarity (this one is the base)%s" % ("" if why_m == "" else "\n" + why_m), why_m == "", Kit.GOLD, "forge:merge", "", 17)
	Kit.btn(m, "IMPRINT", _act_rect(m, 3), func() -> void:
		m.forge_imprint = uid
		m.forge_donor = 0
		m._rebuild_ui(), "Copy one perk from another %s onto this one (the donor is destroyed; %d Scrap)" % [String(it["kind"]), Gear.imprint_cost(it)], int(m.forge_imprint) != uid, Kit.LAB, "forge:imprint", "", 17)
	var why_s: String = Gear.why_salvage(s, uid)
	var arm: bool = int(m.forge_confirm) == uid
	Kit.btn(m, ("CONFIRM +%d" if arm else "SALVAGE +%d") % Gear.salvage_value(it, m.save), _act_rect(m, 4), func() -> void: _salvage(m, uid),
		"Break it down for %d Scrap%s%s" % [Gear.salvage_value(it, m.save), "" if RarityDB.rank(String(it["rar"])) < RarityDB.rank("rare") else " (Rare+ asks twice)", "" if why_s == "" else "\n" + why_s], why_s == "", Kit.ENEMY, "forge:salvage", "cur_scrap", 16)
	var fav: bool = bool(it.get("fav", false))
	Kit.btn(m, "UNFAVOURITE" if fav else "FAVOURITE", _act_rect(m, 5), func() -> void: _act(m, Gear.set_fav(m.save, uid, not fav)), "Favourites can't be salvaged, merged away or used as an imprint donor", true, Kit.MAGENTA if fav else Kit.NEUTRAL, "forge:fav", "", 15)


static func _do_merge(m, set3: Array, base: int, choice: int) -> void:
	m.forge_merge = []
	m.forge_t = m.t_anim
	_act(m, Gear.merge(m.save, set3, base, choice))


static func _do_imprint(m, a: int, b: int, bi: int, ai: int) -> void:
	m.forge_imprint = 0
	m.forge_donor = 0
	_act(m, Gear.imprint(m.save, a, b, bi, ai))


static func _salvage(m, uid: int) -> void:
	var it: Dictionary = Gear.item(m.save, uid)
	if RarityDB.rank(String(it.get("rar", "common"))) >= RarityDB.rank("rare") and int(m.forge_confirm) != uid:
		m.forge_confirm = uid
		m._rebuild_ui()
		return
	m.forge_confirm = 0
	var ev: Array = Gear.salvage(m.save, uid)
	if not ev.is_empty():
		m.forge_sel = 0
	_act(m, ev)


static func _build_new(m, s: Dictionary) -> void:
	var n: Rect2 = rects(m)["new"]
	var kw: float = (n.size.x - 32.0 - 8.0) * 0.5
	for k in 2:
		var kid: String = "weapon" if k == 0 else "module"
		Kit.btn(m, "WEAPONS" if k == 0 else "MODULES", Rect2(n.position.x + 16.0 + float(k) * (kw + 8.0), n.position.y + 56.0, kw, 44.0), func() -> void:
			m.forge_kind = kid
			m._rebuild_ui(), "Forge a %s" % ("Weapon frame" if k == 0 else "Core Module"), true, Kit.CYAN if String(m.forge_kind) == kid else Kit.NEUTRAL, "forge:kind:" + kid, "", 16)
	var kind: String = String(m.forge_kind)
	var ids: Array = FrameDB.IDS if kind == "weapon" else ModuleDB.IDS
	var c: Dictionary = Gear.forge_cost(s)
	for k in ids.size():
		var id: String = String(ids[k])
		var d: Dictionary = FrameDB.get_def(id) if kind == "weapon" else ModuleDB.get_def(id)
		var why: String = Gear.why_forge(s, kind, id)
		var lbl: String = String(d["name"])
		Kit.hit(m, _new_rect(m, k, kind), func() -> void: _forge(m, kind, id),
			"%s\n%s\nForge: %s coins + %d Scrap (Forge odds; perks up to T5)%s" % [lbl, String(d["desc"]), Kit.fmt(float(c["coins"])), int(c["scrap"]), "" if why == "" else "\n" + why],
			"forge:new:" + id, why == "", Kit.GOLD)


static func _forge(m, kind: String, id: String) -> void:
	var ev: Array = Gear.forge_new(m.save, kind, id)
	if not ev.is_empty():
		m.forge_sel = int((ev[0] as Dictionary)["uid"])
		m.forge_t = m.t_anim
		m.forge_filter = "all"
		var lst: Array = _list(m)
		m.forge_page = lst.find(int(m.forge_sel)) / (COLS * ROWS)
		m.sfx_play("levelup", 0.9 + 0.12 * float(RarityDB.rank(String((ev[0] as Dictionary)["rar"]))))
	_act(m, ev)


# ------------------------------------------------------------------ draw

static func draw(m, _cr: Rect2) -> void:
	_ensure_sel(m)
	var s: Dictionary = m.save
	var R: Dictionary = rects(m)
	_draw_inv(m, s, R["inv"])
	_draw_card(m, s, R["card"])
	_draw_new(m, s, R["new"])


const RARITY_LETTER: Dictionary = {"common": "C", "uncommon": "U", "rare": "R", "epic": "E", "legendary": "L", "mythic": "M", "exotic": "X"}


static func _draw_inv(m, s: Dictionary, inv: Rect2) -> void:
	Kit.panel(m, inv, Kit.EDGE, Kit.PANEL)
	Kit.th(m, "INVENTORY", inv.position + Vector2(18, 36), 24, Kit.TEXT)
	Kit.t(m, "%d / %d" % [Gear.count(s), Gear.INV_CAP], Vector2(inv.end.x - 18, inv.position.y + 34), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 200.0)
	var lst: Array = _list(m)
	var per: int = COLS * ROWS
	var p0: int = int(m.forge_page) * per
	for k in mini(per, lst.size() - p0):
		var it: Dictionary = Gear.item(s, int(lst[p0 + k]))
		var r: Rect2 = tile_rect(m, k)
		var sel: bool = int(it["uid"]) == int(m.forge_sel)
		var inset: bool = (m.forge_merge as Array).has(int(it["uid"])) or int(it["uid"]) == int(m.forge_donor)
		Kit.card_frame(m, r, String(it["rar"]), m.t_anim, sel or inset)
		if sel:
			m.draw_rect(r.grow(3.0), Color(1, 1, 1, 0.9), false, 2.0)
		if inset:
			m.draw_rect(r.grow(3.0), Kit.GOLD, false, 2.0)
		if String(it["kind"]) == "weapon":
			GearVis.draw_weapon(m, it, r.get_center() + Vector2(0, -4), TILE * 0.70, 0.0, m.t_anim)   # V2 P9 audit: muzzles stay inside the tile
		else:
			GearVis.draw_module(m, it, r.get_center() + Vector2(0, -4), TILE * 0.48, m.t_anim)
		# V2 P9 audit: rarity is not hue-only — a rank letter in the corner
		var rl: String = RARITY_LETTER.get(String(it["rar"]), "?")
		m.draw_style_box(Kit.sb(Color(Kit.rarity_col(String(it["rar"])), 0.9), Color(Kit.BG, 0.9), 1, 6), Rect2(r.position.x + 4, r.position.y + 4, 20, 20))
		Kit.th(m, rl, Vector2(r.position.x + 14, r.position.y + 19), 14, Kit.rarity_text(String(it["rar"])), HORIZONTAL_ALIGNMENT_CENTER, 20.0)
		Kit.th(m, "Lv%d" % int(it["lvl"]), Vector2(r.position.x + 8, r.end.y - 8), 14, Kit.TEXT)
		if Gear.is_equipped(s, int(it["uid"])):
			Kit.th(m, "EQ", Vector2(r.end.x - 8, r.end.y - 8), 14, Kit.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 40.0)
		if bool(it.get("new", false)):
			m.draw_circle(Vector2(r.end.x - 12, r.position.y + 16), 6.0, Kit.MAGENTA)
		if bool(it.get("fav", false)):
			_star(m, Vector2(r.position.x + 14, r.position.y + 38), 7.0, Kit.GOLD)
	if lst.is_empty():
		Kit.t(m, "Nothing here yet", Vector2(inv.get_center().x, inv.position.y + 200), 18, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, inv.size.x)
	Kit.t(m, "Page %d / %d" % [int(m.forge_page) + 1, _pages(m)], Vector2(inv.get_center().x, inv.end.y - 24), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, 200.0)


static func _star(m, c: Vector2, r: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 10:
		pts.append(c + Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 10.0) * (r if i % 2 == 0 else r * 0.45))
	m.draw_colored_polygon(pts, col)


static func _draw_card(m, s: Dictionary, c: Rect2) -> void:
	var it: Dictionary = _sel(m)
	if it.is_empty():
		Kit.panel(m, c, Kit.EDGE, Kit.PANEL)
		return
	var rar: String = String(it["rar"])
	var rc: Color = Kit.rarity_col_t(rar, m.t_anim)
	Kit.card_frame(m, c, rar, m.t_anim, false)
	var art_c: Vector2 = Vector2(c.get_center().x, c.position.y + 150.0)
	var since: float = float(m.t_anim) - float(m.forge_t)
	if since >= 0.0 and since < REVEAL_S:
		Kit.rarity_beam(m, art_c + Vector2(0, 110), rar, 260.0 * minf(1.0, since * 3.0), m.t_anim, 120.0)
	Kit.glow(m, art_c, 170.0, rc, 0.10 + 0.04 * float(RarityDB.rank(rar)))
	if String(it["kind"]) == "weapon":
		GearVis.draw_weapon(m, it, art_c, minf(c.size.x * 0.78, 440.0), 0.0, m.t_anim)
	else:
		GearVis.draw_module(m, it, art_c, 150.0, m.t_anim)
	var x: float = c.position.x + 20.0
	var w: float = c.size.x - 40.0
	Kit.th(m, String(it["name"]), Vector2(x, c.position.y + 290), 24, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
	var bd: Dictionary = BrandDB.get_def(String(it["brand"]))
	var kind_s: String = String(FrameDB.get_def(String(it["base"]))["name"]) if String(it["kind"]) == "weapon" else String(ModuleDB.get_def(String(it["base"]))["name"]) + " Module"
	Kit.th(m, "%s  ·  %s  ·  %s" % [_rar_name(rar).to_upper(), kind_s, String(bd["name"])], Vector2(x, c.position.y + 316), 16, rc, HORIZONTAL_ALIGNMENT_LEFT, w)
	Kit.t(m, "Brand quirk: %s" % String(bd["quirk_text"]), Vector2(x, c.position.y + 340), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	var mx: int = Gear.max_lvl_of(rar)
	Kit.th(m, "Lv %d / %d   ·   Power x%.2f   ·   Masterworks %d   ·   iLvl %d" % [int(it["lvl"]), mx, Gear.power(it), int(it["mw"]), int(it["ilvl"])], Vector2(x, c.position.y + 368), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
	Kit.bar_glow(m, Rect2(x, c.position.y + 378, w, 10), float(int(it["lvl"])) / float(mx), rc, mx / Gear.MW_EVERY)
	var y: float = c.position.y + 414.0
	if String(it["kind"]) == "weapon":
		var dps: float = Gear.est_dps(it)
		var eqw: Dictionary = Gear.weapon(s)
		var d0: float = Gear.est_dps(eqw)
		var cmp: String = ""
		var cc: Color = Kit.DIM
		if int(eqw.get("uid", 0)) != int(it["uid"]) and d0 > 0.0:
			var pct: float = (dps / d0 - 1.0) * 100.0
			cmp = "   (%s%d%% vs equipped)" % ["+" if pct >= 0.0 else "", int(round(pct))]
			cc = Kit.GREEN if pct >= 0.0 else Kit.ENEMY
		Kit.th(m, "Est. DPS %.1f" % dps, Vector2(x, y), 18, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
		if cmp != "":
			Kit.th(m, cmp, Vector2(x + 150.0, y), 16, cc, HORIZONTAL_ALIGNMENT_LEFT, w - 150.0)
		Kit.wrap(m, String(FrameDB.get_def(String(it["base"]))["desc"]), Vector2(x, y + 8.0), 14, Kit.DIM, w, 2)
	else:
		var ln: Array = Gear.fx_lines(Gear.module_fx(it))
		Kit.wrap(m, "  ·  ".join(ln), Vector2(x, y - 16.0), 16, Kit.GOLD, w, 2)
		Kit.wrap(m, String(ModuleDB.get_def(String(it["base"]))["desc"]), Vector2(x, y + 26.0), 14, Kit.DIM, w, 1)
	# perks / offer / merge / imprint panel
	var g: Dictionary = Gear.block(s)
	var of: Dictionary = g.get("offer", {})
	var ps: Array = it["perks"]
	var uid: int = int(it["uid"])
	if not of.is_empty() and int(of["uid"]) == uid:
		Kit.head(m, "REROLL: TAKE ONE OR KEEP", Vector2(x, c.position.y + 486), w, Kit.MAGENTA)
		var cur: Dictionary = ps[int(of["idx"])]
		Kit.t(m, "Current: T%d  %s" % [int(cur["t"]), AffixDB.text(String(cur["id"]), int(cur["t"]), float(cur["q"]))], _perk_row(m, 0).position + Vector2(4, 28), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	elif not (m.forge_merge as Array).is_empty():
		var nx: String = RarityDB.next(rar)
		Kit.head(m, "MERGE  ->  %s" % _rar_name(nx).to_upper(), Vector2(x, c.position.y + 486), w, Kit.GOLD)
		var names: Array = []
		for u in m.forge_merge:
			if int(u) != uid:
				names.append(String(Gear.item(s, int(u)).get("name", "")))
		Kit.wrap(m, "Consumes: %s. Level -> %d. %s" % [", ".join(names), maxi(1, _merge_lvl(s, m.forge_merge) / 2), "Pick the new perk slot:" if not Gear.merge_choices(s, m.forge_merge, uid).is_empty() else "No new slot at this rarity: +1 tier on the weakest perk."], _perk_row(m, 0).position + Vector2(4, 2), 15, Kit.DIM, w, 2)
	elif int(m.forge_imprint) == uid:
		Kit.head(m, "IMPRINT", Vector2(x, c.position.y + 486), w, Kit.LAB)
		if int(m.forge_donor) == 0:
			Kit.wrap(m, "Pick a donor %s in the inventory. Its chosen perk overwrites one of this item's unlocked slots; the donor is destroyed." % String(it["kind"]), _perk_row(m, 0).position + Vector2(4, 2), 16, Kit.DIM, w, 3)
	else:
		Kit.head(m, "PERKS   (locks %d / %d)" % [Gear.locks_on(it), Gear.lock_slots(s)], Vector2(x, c.position.y + 486), w, rc)
		for i in ps.size():
			var p: Dictionary = ps[i]
			var pr: Rect2 = _perk_row(m, i)
			var tc: Color = Kit.rarity_col(String(RarityDB.IDS[clampi(int(p["t"]) - 1, 0, 6)]))
			Kit.panel(m, Rect2(pr.position, Vector2(pr.size.x - 222.0, pr.size.y)), Kit.GOLD if bool(p.get("lock", false)) else Kit.EDGE, Kit.PANEL2, 1)
			Kit.th(m, "T%d" % int(p["t"]), pr.position + Vector2(10, 29), 18, tc)
			var tag: String = "  SIGNATURE" if bool(p.get("sig", false)) else ("  MASTERWORK" if bool(p.get("mwp", false)) else "")
			Kit.t(m, AffixDB.text(String(p["id"]), int(p["t"]), float(p["q"])) + tag, pr.position + Vector2(48, 28), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 280.0)
	if Gear.is_equipped(s, uid):
		Kit.th(m, "EQUIPPED", Vector2(c.end.x - 20, c.position.y + 34), 16, Kit.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 200.0)


static func _merge_lvl(s: Dictionary, set3: Array) -> int:
	var top: int = 1
	for u in set3:
		top = maxi(top, int(Gear.item(s, int(u)).get("lvl", 1)))
	return top


static func _draw_new(m, s: Dictionary, n: Rect2) -> void:
	Kit.panel(m, n, Kit.EDGE, Kit.PANEL)
	Kit.th(m, "FORGE", n.position + Vector2(18, 36), 24, Kit.GOLD)
	var c: Dictionary = Gear.forge_cost(s)
	Kit.t(m, "%s coins + %d Scrap  ·  forged %d" % [Kit.fmt(float(c["coins"])), int(c["scrap"]), int(Gear.block(s).get("forged", 0))], Vector2(n.end.x - 18, n.position.y + 34), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, n.size.x - 140.0)
	var kind: String = String(m.forge_kind)
	var ok: bool = Gear.why_forge(s, kind, String((FrameDB.IDS if kind == "weapon" else ModuleDB.IDS)[0])) == ""
	var ids: Array = FrameDB.IDS if kind == "weapon" else ModuleDB.IDS
	for k in ids.size():
		var r: Rect2 = _new_rect(m, k, kind)
		var id: String = String(ids[k])
		Kit.panel(m, r, Color(Kit.GOLD, 0.8) if ok else Kit.EDGE2, Kit.tint(Kit.GOLD, 0.10) if ok else Kit.PANEL2, 1)
		if kind == "weapon":
			GearVis.draw_weapon(m, Gear.make("weapon", id), Vector2(r.position.x + 56.0, r.get_center().y), 92.0, 0.0, m.t_anim)
			Kit.th(m, String(FrameDB.get_def(id)["name"]), Vector2(r.end.x - 12.0, r.get_center().y + 6.0), 16, Kit.TEXT if ok else Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 120.0)
		else:
			GearVis.draw_module(m, Gear.make("module", id), Vector2(r.position.x + 22.0, r.get_center().y), 30.0, m.t_anim)
			Kit.th(m, String(ModuleDB.get_def(id)["name"]), Vector2(r.position.x + 44.0, r.get_center().y + 6.0), 14, Kit.TEXT if ok else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 50.0)
	var last: Rect2 = _new_rect(m, ids.size() - 1, kind)
	var y: float = last.end.y + 30.0
	# visible pity
	var pity: Dictionary = Gear.block(s)["pity"]
	for g in ["e", "l"]:
		var pd: Dictionary = RarityDB.PITY[g]
		var left: int = maxi(1, int(pd["hard"]) - int(pity.get(g, 0)))
		var nm: String = "Epic+" if g == "e" else "Legendary"
		Kit.th(m, "%s guaranteed within %d forges" % [nm, left], Vector2(n.position.x + 18, y), 16, Kit.rarity_text("epic" if g == "e" else "legendary"), HORIZONTAL_ALIGNMENT_LEFT, n.size.x - 36.0)
		Kit.bar_glow(m, Rect2(n.position.x + 18, y + 8, n.size.x - 36, 10), float(pity.get(g, 0)) / float(pd["hard"]), Kit.rarity_col("epic" if g == "e" else "legendary"))
		y += 42.0
	# disclosed odds: live (luck + pity) for the Forge, the base drop table
	var fo: Dictionary = GearGen.odds_now("forge", Gear.forge_luck(s), pity)
	var dro: Dictionary = RarityDB.odds("drop")
	Kit.th(m, "ODDS", Vector2(n.position.x + 18, y + 4), 16, Kit.DIM)
	Kit.th(m, "Forge now", Vector2(n.end.x - 150, y + 4), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
	Kit.th(m, "Run drops", Vector2(n.end.x - 18, y + 4), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
	for i in RarityDB.IDS.size():
		var r2: String = String(RarityDB.IDS[i])
		var yy: float = y + 26.0 + float(i) * 21.0
		if yy > n.end.y - (68.0 if Labs.level(s, "auto_salvage") > 0 else 8.0):
			break
		Kit.t(m, _rar_name(r2), Vector2(n.position.x + 18, yy), 15, Kit.rarity_col_t(r2, m.t_anim).lerp(Kit.TEXT, 0.3))
		Kit.t(m, _pct(float(fo[r2])), Vector2(n.end.x - 150, yy), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
		Kit.t(m, _pct(float(dro[r2])), Vector2(n.end.x - 18, yy), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)


static func _pct(v: float) -> String:
	if v <= 0.0:
		return "—"
	if v < 0.1:
		return "%.2f%%" % v
	return "%.1f%%" % v
