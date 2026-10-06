extends RefCounted
## The WEAPON and CORE tabs (V3 parts, design/V3_PARTS.md §1-§3): build an
## assembly from parts. One screen per side, three columns:
##   BUILD     the assembly drawn from its parts (PartVis) and its slot board:
##             every position the side can ever have (Barrel 1-4, Plating 1-2
##             ...); positions the chassis hasn't opened show which rarity
##             opens them. Click a position (arm:slot:<slot>:<i>) to browse
##             that part type.
##   PARTS     the inventory of the selected part type (arm:item:<uid>,
##             arm:page:-/+), best first.
##   CARD      the selected part: art, how it works, level and power, fx,
##             perks with their rarity tiers (LOCK / REROLL, the reroll
##             offer), and INSTALL / REMOVE, UPGRADE (+x5 / MAX), MERGE,
##             SMELT, FAVOURITE (arm:install, arm:remove, arm:upgrade,
##             arm:up5, arm:upmax, arm:merge (+ arm:merge:go / :cancel),
##             arm:smelt, arm:fav, arm:lock:<i>, arm:reroll:<i>,
##             arm:take:<k>, arm:keep).
## Sub-tabs (ARMTAB <name>): Build, Crates (Scrap crates: crate:open:<id>,
## Part Contracts crate:slot:<slot|any>), Presets (preset:save / load:<k>),
## and on the Core: Look and Levels (CoreView). The Core Level button
## (CORE LEVEL) sits under the Core art. View only: buttons call Parts /
## Cores and hand the events to Main.meta_act().

const Parts := preload("res://Parts.gd")
const PartDB := preload("res://data/PartDB.gd")
const PartVis := preload("res://PartVis.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const Cores := preload("res://Cores.gd")
const Labs := preload("res://Labs.gd")
const Kit := preload("res://ui/Kit.gd")
const CoreView := preload("res://ui/CoreView.gd")
const LootReveal := preload("res://ui/LootReveal.gd")

const TABS_W: Array = [["build", "Build", "", "Install parts on the Weapon"], ["crates", "Crates", "", "Open Scrap crates for parts"], ["presets", "Presets", "", "Saved loadouts (Loadout Presets research)"]]
const TABS_C: Array = [["build", "Build", "", "Install parts on the Core"], ["crates", "Crates", "", "Open Scrap crates for parts"], ["look", "Look", "", "Core colours and pattern"], ["levels", "Levels", "", "Permanent Core level and sheet"]]
const TILE: float = 112.0
const GAP: float = 8.0
const SLOT_ROWS: int = 6
const SLOT_H: float = 54.0
const REVEAL_S: float = 1.6
## What each part type is for (card subtitle).
const ROLE: Dictionary = {
	"barrel": "how the Weapon fires", "ammo": "on-hit effects", "scope": "range and precision", "power": "attack rate and damage",
	"muzzle": "shot shaping", "mag": "rate, echo and shred", "plating": "Core HP, armor and thorns", "generator": "regen and shield",
	"capacitor": "run cash and interest", "reactor": "XP, coins and run cash", "uplink": "buildings, troops and specials",
	"antenna": "loot, luck and Scrap", "emitter": "shield and damage reduction",
}
const RARITY_LETTER: Dictionary = {"common": "C", "uncommon": "U", "rare": "R", "epic": "E", "legendary": "L", "mythic": "M", "exotic": "X"}


# ------------------------------------------------------------------ layout

static func cols(m) -> Dictionary:
	var cr: Rect2 = m.content_rect()
	var top: float = cr.position.y + 12.0
	var h: float = cr.size.y - 24.0
	var aw: float = clampf(cr.size.x * 0.33, 400.0, 640.0)
	var bw: float = clampf(cr.size.x * 0.27, 300.0, 520.0)
	var a: Rect2 = Rect2(cr.position.x + 16.0, top, aw, h)
	var b: Rect2 = Rect2(a.end.x + 16.0, top, bw, h)
	var c: Rect2 = Rect2(b.end.x + 16.0, top, cr.end.x - 16.0 - (b.end.x + 16.0), h)
	return {"a": a, "b": b, "c": c, "bc": Rect2(b.position, Vector2(c.end.x - b.position.x, h))}


static func slot_rect(m, k: int) -> Rect2:
	var a: Rect2 = cols(m)["a"]
	var w: float = (a.size.x - 24.0 - 8.0) * 0.5
	var y0: float = a.end.y - 12.0 - float(SLOT_ROWS) * (SLOT_H + 6.0) + 6.0
	return Rect2(a.position.x + 12.0 + float(k % 2) * (w + 8.0), y0 + float(k / 2) * (SLOT_H + 6.0), w, SLOT_H)


static func level_rect(m) -> Rect2:
	var a: Rect2 = cols(m)["a"]
	var s0: Rect2 = slot_rect(m, 0)
	return Rect2(a.position.x + 12.0, s0.position.y - 60.0, a.size.x - 24.0, 48.0)


static func art_center(m) -> Vector2:
	var a: Rect2 = cols(m)["a"]
	return Vector2(a.get_center().x, (a.position.y + 70.0 + level_rect(m).position.y) * 0.5)


static func art_r(m) -> float:
	var a: Rect2 = cols(m)["a"]
	return clampf(minf(a.size.x * 0.30, (level_rect(m).position.y - a.position.y - 70.0) * 0.40), 60.0, 200.0)


static func grid_cols(m) -> int:
	var b: Rect2 = cols(m)["b"]
	return maxi(2, int((b.size.x - 32.0 + GAP) / (TILE + GAP)))


static func grid_rows(m) -> int:
	var b: Rect2 = cols(m)["b"]
	return maxi(2, int((b.size.y - 124.0 - 64.0 + GAP) / (TILE + GAP)))


static func tile_rect(m, k: int) -> Rect2:
	var b: Rect2 = cols(m)["b"]
	var gc: int = grid_cols(m)
	var gw: float = float(gc) * (TILE + GAP) - GAP
	var x0: float = b.position.x + (b.size.x - gw) * 0.5
	return Rect2(x0 + float(k % gc) * (TILE + GAP), b.position.y + 108.0 + float(k / gc) * (TILE + GAP), TILE, TILE)


static func _perk_row(m, i: int) -> Rect2:
	var c: Rect2 = cols(m)["c"]
	return Rect2(c.position.x + 16.0, c.position.y + 486.0 + float(i) * 50.0, c.size.x - 32.0, 44.0)


static func _act_rect(m, k: int) -> Rect2:
	var c: Rect2 = cols(m)["c"]
	var w: float = (c.size.x - 32.0 - 16.0) / 3.0
	return Rect2(c.position.x + 16.0 + float(k % 3) * (w + 8.0), c.end.y - 116.0 + float(k / 3) * 56.0, w, 48.0)


static func _bulk_rect(m, k: int) -> Rect2:
	var a: Rect2 = _act_rect(m, 1 + k)
	return Rect2(a.position.x, a.position.y - 56.0, a.size.x, a.size.y)


static func _auto_salvage_rect(m) -> Rect2:
	var b: Rect2 = cols(m)["b"]
	return Rect2(b.position.x + 16.0, b.end.y - 112.0, b.size.x - 32.0, 44.0)


static func auto_salvage_label(lv: int) -> String:
	return ["AUTO-SMELT: OFF", "AUTO-SMELT: COMMONS", "AUTO-SMELT: UP TO UNCOMMON"][clampi(lv, 0, 2)]


# ------------------------------------------------------------------ state

static func chassis_slot(side: String) -> String:
	return "receiver" if side == "weapon" else "heart"


## Every slot position a side can ever have: [[slot, idx], ...] (Exotic layout).
static func positions(side: String) -> Array:
	var out: Array = []
	var ex: Dictionary = PartDB.layout(chassis_slot(side), "exotic")
	for sl in (PartDB.WEAPON_SLOTS if side == "weapon" else PartDB.CORE_SLOTS):
		var n: int = 1 if PartDB.is_chassis(String(sl)) else int(ex.get(sl, 0))
		for i in n:
			out.append([String(sl), i])
	return out


static func _tab(m, side: String) -> String:
	return String((m.arm_tab as Dictionary).get(side, "build"))


static func sel_pos(m, side: String) -> Array:
	var raw: String = String((m.arm_slot as Dictionary).get(side, ""))
	var bits: PackedStringArray = raw.split(":")
	if bits.size() == 2 and PartDB.SLOTS.has(bits[0]) and PartDB.side_of(bits[0]) == side:
		return [bits[0], int(bits[1])]
	return ["barrel", 0] if side == "weapon" else ["plating", 0]


static func _installed_at(s: Dictionary, slot: String, idx: int) -> int:
	var arr: Array = (Parts.block(s)["equipped"] as Dictionary).get(slot, [])
	var n: int = int(Parts.layout(s, PartDB.side_of(slot)).get(slot, 0))
	return int(arr[idx]) if idx < arr.size() and idx < n else 0


static func _open(s: Dictionary, slot: String, idx: int) -> bool:
	return idx < int(Parts.layout(s, PartDB.side_of(slot)).get(slot, 0))


static func _pos_name(slot: String, idx: int, side: String) -> String:
	var nm: String = String(PartDB.SLOTS[slot]["name"])
	var ex: int = int(PartDB.layout(chassis_slot(side), "exotic").get(slot, 1))
	return nm if ex <= 1 or PartDB.is_chassis(slot) else "%s %d" % [nm, idx + 1]


## The parts of the selected slot type: installed first, then best rarity,
## level, newest.
static func _list(m, side: String) -> Array:
	var s: Dictionary = m.save
	var slot: String = String(sel_pos(m, side)[0])
	var out: Array = Parts.uids(s, slot)
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ea: int = 1 if Parts.is_equipped(s, int(a)) else 0
		var eb: int = 1 if Parts.is_equipped(s, int(b)) else 0
		if ea != eb:
			return ea > eb
		var ia: Dictionary = Parts.item(s, int(a))
		var ib: Dictionary = Parts.item(s, int(b))
		var ra: int = RarityDB.rank(String(ia["rar"]))
		var rb: int = RarityDB.rank(String(ib["rar"]))
		if ra != rb:
			return ra > rb
		if int(ia["lvl"]) != int(ib["lvl"]):
			return int(ia["lvl"]) > int(ib["lvl"])
		return int(a) > int(b))
	return out


static func _per_page(m) -> int:
	return grid_cols(m) * grid_rows(m)


static func _pages(m, side: String) -> int:
	return maxi(1, int(ceil(float(_list(m, side).size()) / float(_per_page(m)))))


static func _sel(m) -> Dictionary:
	return Parts.item(m.save, int(m.arm_sel))


## Keep a valid selection: a part of the selected slot type (the installed
## one at the selected position by default).
static func ensure_sel(m, side: String) -> void:
	var sp: Array = sel_pos(m, side)
	var it: Dictionary = _sel(m)
	if it.is_empty() or String(it["slot"]) != String(sp[0]):
		m.arm_sel = _installed_at(m.save, String(sp[0]), int(sp[1]))
		if int(m.arm_sel) == 0:
			var lst: Array = _list(m, side)
			m.arm_sel = int(lst[0]) if not lst.is_empty() else 0
	m.arm_page = clampi(int(m.arm_page), 0, _pages(m, side) - 1)


## The two partners a merge would use with the selected part: same slot and
## rarity, not favourite, not installed, lowest level first.
static func merge_set(m) -> Array:
	var s: Dictionary = m.save
	var it: Dictionary = _sel(m)
	if it.is_empty():
		return []
	var cands: Array = []
	for u in Parts.uids(s, String(it["slot"])):
		var o: Dictionary = Parts.item(s, int(u))
		if int(u) != int(it["uid"]) and String(o["rar"]) == String(it["rar"]) and not bool(o.get("fav", false)) and not Parts.is_equipped(s, int(u)):
			cands.append(int(u))
	cands.sort_custom(func(a: Variant, b: Variant) -> bool: return int(Parts.item(s, int(a))["lvl"]) * 100000 + int(a) < int(Parts.item(s, int(b))["lvl"]) * 100000 + int(b))
	if cands.size() < 2:
		return []
	return [int(it["uid"]), int(cands[0]), int(cands[1])]


static func _rar_name(r: String) -> String:
	return String(RarityDB.get_def(r)["name"])


## A perk's tier as its rarity name ("T3 RARE").
static func tier_name(t: int) -> String:
	return "T%d %s" % [t, _rar_name(String(RarityDB.IDS[clampi(t - 1, 0, RarityDB.IDS.size() - 1)])).to_upper()]


static func tier_col(t: int) -> Color:
	return Kit.rarity_col(String(RarityDB.IDS[clampi(t - 1, 0, RarityDB.IDS.size() - 1)]))


static func _act(m, ev: Array) -> void:
	m.meta_act(ev)


## What a part does, in one line.
static func how(it: Dictionary) -> String:
	var bd: Dictionary = PartDB.get_def(String(it["base"]))
	var slot: String = String(it["slot"])
	if slot == "barrel":
		return String(bd.get("desc", FrameDB.get_def(String(bd.get("frame", "autocannon"))).get("desc", "")))
	if PartDB.is_chassis(slot):
		var k: String = ("x%.2f damage, x%.2f rate" % [float(bd.get("dmg_k", 1.0)), float(bd.get("rate_k", 1.0))]) if slot == "receiver" else ("x%.2f HP, x%.2f regen" % [float(bd.get("hp_k", 1.0)), float(bd.get("regen_k", 1.0))])
		return "%s (%s). This rarity opens: %s; %d perk slots per part of the same rarity." % [String(bd.get("desc", "")), k, Parts.layout_text(slot, String(it["rar"])), int(PartDB.PERK_SLOTS[String(it["rar"])])]
	return "%s: %s. Its own effect is below; perks add more." % [String(PartDB.SLOTS[slot]["name"]), String(ROLE.get(slot, ""))]


# ------------------------------------------------------------------ build

static func build(m, side: String) -> void:
	var s: Dictionary = m.save
	var R: Dictionary = cols(m)
	var a: Rect2 = R["a"]
	Kit.tabs(m, Rect2(a.position.x + 12.0, a.position.y + 12.0, a.size.x - 24.0, 46.0), TABS_W if side == "weapon" else TABS_C, _tab(m, side), func(id: String) -> void:
		(m.arm_tab as Dictionary)[side] = id
		m.arm_merge = []
		m._rebuild_ui(), "ARMTAB ", [] if Labs.preset_slots(s) > 0 else ["presets"], 16)
	_build_slots(m, s, side)
	if side == "core":
		var lv: int = Cores.level(s)
		var c: int = int(Cores.level_cost(lv)["coins"])
		var maxed: bool = lv >= Cores.max_level(s)
		var why: String = Cores.why_level(s)
		Kit.btn(m, "CORE MAX LEVEL" if maxed else "Core Lv %d -> %d  ·  %s coins" % [lv, lv + 1, Kit.fmt(float(c))], level_rect(m), func() -> void: m.meta_act(Cores.try_level(m.save)),
			CoreView.level_tip(lv) + ("" if why == "" or maxed else "\n" + why), Cores.can_level(s), Kit.GOLD, "CORE LEVEL", "cur_coin", 18)
	match _tab(m, side):
		"crates":
			_build_crates(m, s, side)
		"presets":
			_build_presets(m, s)
		"look":
			CoreView.build_look(m, s, R["bc"])
		"levels":
			CoreView.build_levels(m, s, R["bc"])
		_:
			ensure_sel(m, side)
			_build_inv(m, s, side)
			_build_card(m, s, side)


static func _build_slots(m, s: Dictionary, side: String) -> void:
	var ps: Array = positions(side)
	var sp: Array = sel_pos(m, side)
	for k in ps.size():
		var slot: String = String(ps[k][0])
		var idx: int = int(ps[k][1])
		var u: int = _installed_at(s, slot, idx)
		var it: Dictionary = Parts.item(s, u)
		var open: bool = _open(s, slot, idx)
		var tip: String = _pos_name(slot, idx, side) + ": "
		if not open:
			tip += "locked - a %s %s opens it" % [_rar_name(Parts.opens_at(slot, idx)), "Receiver" if side == "weapon" else "Heart"]
		elif it.is_empty():
			tip += "empty - click to pick a part"
		else:
			tip += "%s (%s, Lv %d)\n%s" % [String(it["name"]), _rar_name(String(it["rar"])), int(it["lvl"]), "\n".join(Parts.fx_lines(Parts.part_fx(it)))]
		var on: bool = String(sp[0]) == slot and int(sp[1]) == idx
		Kit.hit(m, slot_rect(m, k), func() -> void: _pick_pos(m, side, slot, idx), tip, "arm:slot:%s:%d" % [slot, idx], true, Kit.CYAN if on else (Kit.rarity_col(String(it["rar"])) if not it.is_empty() else Kit.EDGE2))


static func _pick_pos(m, side: String, slot: String, idx: int) -> void:
	(m.arm_slot as Dictionary)[side] = "%s:%d" % [slot, idx]
	(m.arm_tab as Dictionary)[side] = "build"
	m.arm_sel = _installed_at(m.save, slot, idx)
	m.arm_page = 0
	m.arm_merge = []
	m.arm_confirm = 0
	m._rebuild_ui()


static func _build_inv(m, s: Dictionary, side: String) -> void:
	var b: Rect2 = cols(m)["b"]
	var lst: Array = _list(m, side)
	var per: int = _per_page(m)
	var p0: int = int(m.arm_page) * per
	for k in mini(per, lst.size() - p0):
		var uid: int = int(lst[p0 + k])
		var it: Dictionary = Parts.item(s, uid)
		Kit.hit(m, tile_rect(m, k), func() -> void: _click_tile(m, uid), _tile_tip(m, it), "arm:item:%d" % uid, true, Kit.rarity_col(String(it["rar"])))
	var py: float = b.end.y - 56.0
	Kit.btn(m, "<", Rect2(b.position.x + 16.0, py, 64.0, 44.0), func() -> void:
		m.arm_page = int(m.arm_page) - 1
		m._rebuild_ui(), "Previous page", int(m.arm_page) > 0, Kit.NEUTRAL, "arm:page:-", "", 20)
	Kit.btn(m, ">", Rect2(b.end.x - 80.0, py, 64.0, 44.0), func() -> void:
		m.arm_page = int(m.arm_page) + 1
		m._rebuild_ui(), "Next page", int(m.arm_page) < _pages(m, side) - 1, Kit.NEUTRAL, "arm:page:+", "", 20)
	if Labs.level(s, "auto_salvage") > 0:
		Kit.btn(m, auto_salvage_label(Labs.auto_salvage_level(s)), _auto_salvage_rect(m), func() -> void:
			Labs.cycle_auto_salvage(m.save)
			m._save()
			m._rebuild_ui(), "Auto-Smelt (research): banked parts below the chosen rarity turn into Scrap on arrival. Click: off / Commons / up to Uncommon (Lv 2).", true, Kit.ENEMY if Labs.auto_salvage_level(s) > 0 else Kit.NEUTRAL, "arm:autosmelt", "cur_scrap", 15)


static func _click_tile(m, uid: int) -> void:
	m.arm_sel = uid
	m.arm_merge = []
	m.arm_confirm = 0
	Parts.mark_seen(m.save, uid)
	m._save()
	m._rebuild_ui()


static func _tile_tip(m, it: Dictionary) -> String:
	var lines: Array = ["%s\n%s %s  ·  Lv %d / %d" % [String(it["name"]), _rar_name(String(it["rar"])), String(PartDB.SLOTS[String(it["slot"])]["name"]), int(it["lvl"]), Parts.max_lvl_of(String(it["rar"]))]]
	lines.append_array(Parts.fx_lines(Parts.base_fx(it)))
	for p in it["perks"]:
		lines.append("%s  %s" % [tier_name(int((p as Dictionary)["t"])), AffixDB.text(String(p["id"]), int(p["t"]), float(p["q"]))])
	if Parts.is_equipped(m.save, int(it["uid"])):
		lines.append("INSTALLED")
	return "\n".join(lines)


static func _build_card(m, s: Dictionary, side: String) -> void:
	var it: Dictionary = _sel(m)
	if it.is_empty():
		return
	var uid: int = int(it["uid"])
	var ps: Array = it["perks"]
	var of: Dictionary = Parts.block(s).get("offer", {})
	var sp: Array = sel_pos(m, side)
	if not of.is_empty() and int(of["uid"]) == uid:
		var cands: Array = of["cands"]
		for k in cands.size():
			var kk: int = k
			var c: Dictionary = cands[k]
			Kit.btn(m, "%s  %s" % [tier_name(int(c["t"])), AffixDB.text(String(c["id"]), int(c["t"]), float(c["q"]))], _perk_row(m, k + 1), func() -> void: _act(m, Parts.reroll_choose(m.save, kk)),
				"Take this perk (replaces %s)" % String(AffixDB.get_def(String(((ps[int(of["idx"])]) as Dictionary)["id"])).get("name", "")), true, Kit.MAGENTA, "arm:take:%d" % k, "", 15)
		Kit.btn(m, "KEEP CURRENT", _perk_row(m, cands.size() + 1), func() -> void: _act(m, Parts.reroll_choose(m.save, -1)), "Keep the perk you have", true, Kit.NEUTRAL, "arm:keep", "", 16)
	elif not (m.arm_merge as Array).is_empty():
		var set3: Array = m.arm_merge
		var nx: String = RarityDB.next(String(it["rar"]))
		var why_g: String = Parts.why_merge(s, set3, uid)
		Kit.btn(m, "MERGE INTO %s" % _rar_name(nx).to_upper(), _perk_row(m, 2), func() -> void: _do_merge(m, set3, uid),
			"Consume the other two: rarity -> %s, new perk slots roll, level halves%s" % [_rar_name(nx), "" if why_g == "" else "\n" + why_g], why_g == "", Kit.GOLD, "arm:merge:go", "", 17)
		Kit.btn(m, "CANCEL", _perk_row(m, 3), func() -> void:
			m.arm_merge = []
			m._rebuild_ui(), "Back to the part", true, Kit.NEUTRAL, "arm:merge:cancel", "", 16)
	else:
		for i in ps.size():
			var idx: int = i
			var pr: Rect2 = _perk_row(m, i)
			var p: Dictionary = ps[i]
			var locked: bool = bool(p.get("lock", false))
			var why_l: String = Parts.why_lock(s, uid, i, not locked)
			Kit.btn(m, "LOCKED" if locked else "LOCK", Rect2(pr.end.x - 214.0, pr.position.y, 100.0, 44.0), func() -> void: _act(m, Parts.lock(m.save, uid, idx, not locked)),
				("Unlock: rerolls may change this perk again" if locked else "Lock: rerolls keep this perk (each lock x4 reroll cost)") + "\nLock slots: %d / %d" % [Parts.locks_on(it), Parts.lock_slots(s)] + ("" if why_l == "" else "\n" + why_l),
				why_l == "", Kit.GOLD if locked else Kit.NEUTRAL, "arm:lock:%d" % i, "", 15)
			var why_r: String = Parts.why_reroll(s, uid, i)
			Kit.btn(m, Kit.fmt(float(Parts.reroll_cost(it, s))), Rect2(pr.end.x - 106.0, pr.position.y, 106.0, 44.0), func() -> void: _act(m, Parts.reroll(m.save, uid, idx)),
				"Reroll this perk for %d Scrap: its effect AND its rarity tier re-roll; pick one of %d or keep it%s" % [Parts.reroll_cost(it, s), Parts.reroll_options(s), "" if why_r == "" else "\n" + why_r],
				why_r == "", Kit.MAGENTA, "arm:reroll:%d" % i, "cur_scrap", 15)
	# verbs
	var slot: String = String(it["slot"])
	var here: bool = _installed_at(s, String(sp[0]), int(sp[1])) == uid
	var eq: bool = Parts.is_equipped(s, uid)
	if here:
		var can_rm: bool = not PartDB.is_chassis(slot) and not (slot == "barrel" and (Parts.equipped(s, "barrel") as Array).size() <= 1)
		Kit.btn(m, "REMOVE", _act_rect(m, 0), func() -> void: _act(m, Parts.unequip(m.save, slot, int(sp[1]))),
			"Take it out (it stays in your parts)" if can_rm else ("The chassis can only be swapped" if PartDB.is_chassis(slot) else "The Weapon needs at least one barrel"), can_rm, Kit.ENEMY, "arm:remove", "", 17)
	else:
		var why_e: String = Parts.why_equip(s, uid, int(sp[1]) if String(sp[0]) == slot and not PartDB.is_chassis(slot) else -1)
		if String(sp[0]) == slot and not _open(s, slot, int(sp[1])):
			why_e = "That position is locked - a %s %s opens it" % [_rar_name(Parts.opens_at(slot, int(sp[1]))), "Receiver" if side == "weapon" else "Heart"]
		Kit.btn(m, "INSTALL", _act_rect(m, 0), func() -> void: _install(m, side, uid),
			("Install in %s%s" % [_pos_name(String(sp[0]), int(sp[1]), side), " (moves it from its other position)" if eq else ""]) + ("" if why_e == "" else "\n" + why_e), why_e == "", Kit.GREEN, "arm:install", "", 17)
	var why_u: String = Parts.why_upgrade(s, uid)
	Kit.btn(m, "UPGRADE %s" % Kit.fmt(float(Parts.upgrade_cost(it, m.save))), _act_rect(m, 1), func() -> void: _act(m, Parts.upgrade(m.save, uid)),
		"+1 level (+5%% power) for %d coins. Every 5th level is a MASTERWORK: +6%% power and +1 tier on a random perk (jackpot %d%%: +2 tiers)%s" % [Parts.upgrade_cost(it, m.save), int(round(Parts.jackpot_chance(s) * 100.0)), "" if why_u == "" else "\n" + why_u],
		why_u == "", Kit.GOLD, "arm:upgrade", "cur_coin", 16)
	if Labs.level(s, "bulk_upgrade") > 0:
		Kit.btn(m, "UPGRADE x5", _bulk_rect(m, 0), func() -> void: _act(m, Parts.upgrade_n(m.save, uid, 5)), "Up to five levels at once (stops when coins run out or at the cap)", why_u == "", Kit.GOLD, "arm:up5", "cur_coin", 15)
		Kit.btn(m, "UPGRADE MAX", _bulk_rect(m, 1), func() -> void: _act(m, Parts.upgrade_n(m.save, uid, 0)), "Every level your coins cover, up to the rarity's cap", why_u == "", Kit.GOLD, "arm:upmax", "cur_coin", 15)
	var ms: Array = merge_set(m)
	var why_m: String = ("Need two more %s %ss (not installed, not favourites)" % [_rar_name(String(it["rar"])), String(PartDB.SLOTS[slot]["name"])]) if ms.is_empty() else Parts.why_merge(s, ms, uid)
	Kit.btn(m, "MERGE", _act_rect(m, 2), func() -> void:
		m.arm_merge = merge_set(m)
		m._rebuild_ui(), "Merge 3 %s parts of one rarity into the next rarity (this one is the base and keeps its perks)%s" % [String(PartDB.SLOTS[slot]["name"]), "" if why_m == "" else "\n" + why_m], why_m == "", Kit.GOLD, "arm:merge", "", 17)
	var why_s: String = Parts.why_smelt(s, uid, m.now())
	var arm: bool = int(m.arm_confirm) == uid
	Kit.btn(m, ("CONFIRM +%d" if arm else "SMELT +%d") % Parts.smelt_yield(s, it), _act_rect(m, 3), func() -> void: _smelt(m, uid),
		"Send it to the Smelter: %d Scrap in %s%s%s" % [Parts.smelt_yield(s, it), Kit.dur(Parts.smelt_secs(s)), "" if RarityDB.rank(String(it["rar"])) < RarityDB.rank("rare") else " (Rare+ asks twice)", "" if why_s == "" else "\n" + why_s], why_s == "", Kit.ENEMY, "arm:smelt", "cur_scrap", 16)
	var fav: bool = bool(it.get("fav", false))
	Kit.btn(m, "UNFAVOURITE" if fav else "FAVOURITE", _act_rect(m, 4), func() -> void: _act(m, Parts.set_fav(m.save, uid, not fav)), "Favourites can't be smelted or merged away", true, Kit.MAGENTA if fav else Kit.NEUTRAL, "arm:fav", "", 15)


## Install the selected part at the selected position (a chassis swaps; a
## part of another type goes to its first free position).
static func _install(m, side: String, uid: int) -> void:
	var sp: Array = sel_pos(m, side)
	var it: Dictionary = Parts.item(m.save, uid)
	var idx: int = int(sp[1]) if String(sp[0]) == String(it.get("slot", "")) and not PartDB.is_chassis(String(it.get("slot", ""))) else -1
	m.sfx_play("build", 1.0)
	_act(m, Parts.equip(m.save, uid, idx))


static func _do_merge(m, set3: Array, base: int) -> void:
	m.arm_merge = []
	m.arm_t = m.t_anim
	var ev: Array = Parts.merge(m.save, set3, base)
	if not ev.is_empty():
		m.sfx_play("levelup", 1.0 + 0.1 * float(RarityDB.rank(String((ev[0] as Dictionary)["to"]))))
	_act(m, ev)


static func _smelt(m, uid: int) -> void:
	var it: Dictionary = Parts.item(m.save, uid)
	if RarityDB.rank(String(it.get("rar", "common"))) >= RarityDB.rank("rare") and int(m.arm_confirm) != uid:
		m.arm_confirm = uid
		m._rebuild_ui()
		return
	m.arm_confirm = 0
	var ev: Array = Parts.smelt(m.save, uid, m.now())
	if not ev.is_empty():
		m.arm_sel = 0
	_act(m, ev)


# ------------------------------------------------------------------ crates

static func _crate_rect(m, k: int) -> Rect2:
	var bc: Rect2 = cols(m)["bc"]
	var w: float = (bc.size.x - 32.0 - 32.0) / 3.0
	return Rect2(bc.position.x + 16.0 + float(k) * (w + 16.0), bc.position.y + 150.0, w, 380.0)


static func _contract_rect(m, k: int, n: int) -> Rect2:
	var bc: Rect2 = cols(m)["bc"]
	var w: float = minf(150.0, (bc.size.x - 32.0 - float(n - 1) * 8.0) / float(n))
	return Rect2(bc.position.x + 16.0 + float(k) * (w + 8.0), bc.position.y + 86.0, w, 44.0)


static func _contract_slots(side: String) -> Array:
	var out: Array = [""]
	for sl in (PartDB.WEAPON_SLOTS if side == "weapon" else PartDB.CORE_SLOTS):
		out.append(String(sl))
	return out


static func _build_crates(m, s: Dictionary, side: String) -> void:
	var cslot: String = String(m.arm_crate_slot)
	if cslot != "" and PartDB.side_of(cslot) != side:
		cslot = ""
	if Labs.level(s, "brand_contracts") > 0:
		var cs: Array = _contract_slots(side)
		for k in cs.size():
			var sl: String = String(cs[k])
			Kit.btn(m, "ANY" if sl == "" else String(PartDB.SLOTS[sl]["name"]).to_upper(), _contract_rect(m, k, cs.size()), func() -> void:
				m.arm_crate_slot = sl
				m._rebuild_ui(), "Part Contracts: every part in the crate is %s (x%.1f price)" % ["any type" if sl == "" else "a " + String(PartDB.SLOTS[sl]["name"]), Parts.CONTRACT_K] if sl != "" else "Any part type (normal price)", true, Kit.CYAN if cslot == sl else Kit.NEUTRAL, "crate:slot:%s" % ("any" if sl == "" else sl), "", 14)
	for k in Parts.CRATE_IDS.size():
		var id: String = String(Parts.CRATE_IDS[k])
		var cd: Dictionary = Parts.CRATES[id]
		var r: Rect2 = _crate_rect(m, k)
		var why: String = Parts.why_crate(s, id, cslot)
		Kit.btn(m, "OPEN  ·  %s" % Kit.fmt(float(Parts.crate_price(id, cslot))), Rect2(r.position.x + 16.0, r.end.y - 64.0, r.size.x - 32.0, 50.0), func() -> void: _open_crate(m, id, cslot),
			"%s: %d part%s for %d Scrap%s%s" % [String(cd["name"]), int(cd["n"]), "" if int(cd["n"]) == 1 else "s", Parts.crate_price(id, cslot), ("" if String(cd["min"]) == "" else ", the first %s+" % _rar_name(String(cd["min"]))), "" if why == "" else "\n" + why],
			why == "", Kit.GOLD, "crate:open:%s" % id, "cur_scrap", 17)


static func _open_crate(m, id: String, slot: String) -> void:
	var ev: Array = Parts.open_crate(m.save, id, slot)
	if ev.is_empty():
		return
	m.sfx_play("card_open", 1.0)
	m.meta_act(ev)
	LootReveal.open(m, (ev[0] as Dictionary)["uids"])


# ------------------------------------------------------------------ presets

static func _preset_rect(m, k: int) -> Rect2:
	var bc: Rect2 = cols(m)["bc"]
	var h: float = minf(170.0, (bc.size.y - 120.0 - 2.0 * 14.0) / 3.0)
	return Rect2(bc.position.x + 16.0, bc.position.y + 100.0 + float(k) * (h + 14.0), bc.size.x - 32.0, h)


static func _build_presets(m, s: Dictionary) -> void:
	for k in mini(Parts.PRESETS_MAX, Labs.preset_slots(s)):
		var kk: int = k
		var r: Rect2 = _preset_rect(m, k)
		var has: bool = not Parts.preset(s, k).is_empty()
		Kit.btn(m, "LOAD", Rect2(r.end.x - 252.0, r.end.y - 58.0, 116.0, 46.0), func() -> void: m.meta_act(Parts.load_preset(m.save, kk)), "Install loadout %d (missing parts leave their slot empty)" % (k + 1), has, Kit.GREEN, "preset:load:%d" % k, "", 16)
		Kit.btn(m, "SAVE", Rect2(r.end.x - 128.0, r.end.y - 58.0, 116.0, 46.0), func() -> void: m.meta_act(Parts.save_preset(m.save, kk)), "Store every installed part (Weapon + Core) as loadout %d" % (k + 1), true, Kit.GOLD, "preset:save:%d" % k, "", 16)


# ------------------------------------------------------------------ draw

static func draw(m, side: String) -> void:
	var s: Dictionary = m.save
	var R: Dictionary = cols(m)
	_draw_build(m, s, side, R["a"])
	match _tab(m, side):
		"crates":
			_draw_crates(m, s, side)
		"presets":
			_draw_presets(m, s)
		"look":
			CoreView.draw_look(m, s, R["bc"])
		"levels":
			CoreView.draw_levels(m, s, R["bc"])
		_:
			ensure_sel(m, side)
			_draw_inv(m, s, side, R["b"])
			_draw_card(m, s, side, R["c"])


static func _draw_build(m, s: Dictionary, side: String, a: Rect2) -> void:
	Kit.panel(m, a, Kit.EDGE, Kit.PANEL)
	var c: Vector2 = art_center(m)
	var r: float = art_r(m)
	var look: Dictionary = Cores.look(s)
	for k in 3:
		var an: float = m.t_anim * (0.25 + 0.1 * float(k)) + float(k) * 1.4
		m.draw_arc(c, r * 1.25 + 14.0 * float(k), an, an + 2.0, 40, Color(Kit.GEM, 0.10 + 0.04 * float(k)), 2.0)
	Kit.glow(m, c, r * 2.2, Kit.CYAN if side == "weapon" else Kit.GOLD, 0.12 + 0.04 * sin(m.t_anim * 1.7))
	var aim: float = -PI * 0.5 + 0.35 * sin(m.t_anim * 0.5)
	if side == "weapon":
		PartVis.draw_weapon(m, PartVis.weapon_desc(s), look, c, r * 1.45, aim, m.t_anim)
	else:
		PartVis.draw_assembly(m, s, look, c, r * 0.9, aim, m.t_anim)
	# summary line + fx tooltip on the art
	var fx: Array = []
	for it in Parts.side_parts(s, side):
		var pf: Dictionary = Parts.part_fx(it)
		for k2 in pf.keys():
			fx.append([k2, pf[k2]])
	var sum: Dictionary = {}
	for e in fx:
		sum[e[0]] = float(sum.get(e[0], 0.0)) + float(e[1])
	var line: String = ""
	if side == "weapon":
		var cd: Dictionary = Parts.core_def(s)
		line = "WEAPON  ·  ~%.0f DPS  ·  %d barrel%s  ·  %s" % [Parts.est_dps(s), (cd["barrels"] as Array).size(), "" if (cd["barrels"] as Array).size() == 1 else "s", String(cd["attack_name"])]
	else:
		var cd2: Dictionary = Parts.core_def(s)
		line = "CORE  ·  Lv %d  ·  %d HP  ·  %.1f regen/s" % [Cores.level(s), int(round(float(cd2["hp"]) * CoreDB.lvl_mult("hp", Cores.level(s)) * (1.0 + float(sum.get("core_hp", 0.0))))), float(cd2["regen"]) * CoreDB.lvl_mult("regen", Cores.level(s)) * (1.0 + float(sum.get("regen", 0.0)))]
	Kit.th(m, Kit.fit(m, line, 17, a.size.x - 32.0), Vector2(a.get_center().x, a.position.y + 84.0), 17, Kit.GOLD if side == "core" else Kit.CYAN, HORIZONTAL_ALIGNMENT_CENTER, a.size.x - 32.0)
	var tip: Array = ["%s parts: what they add (before Core level, research and run bonuses)" % ("Weapon" if side == "weapon" else "Core")]
	tip.append_array(Parts.fx_lines(sum))
	if tip.size() == 1:
		tip.append("Nothing yet - install parts from runs, crates and the Fabricator")
	m.stat_tips.append([Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), "\n".join(tip)])
	# slot board
	var ps: Array = positions(side)
	var sp: Array = sel_pos(m, side)
	for k in ps.size():
		var slot: String = String(ps[k][0])
		var idx: int = int(ps[k][1])
		var rr: Rect2 = slot_rect(m, k)
		var u: int = _installed_at(s, slot, idx)
		var it: Dictionary = Parts.item(s, u)
		var open: bool = _open(s, slot, idx)
		var on: bool = String(sp[0]) == slot and int(sp[1]) == idx
		if not open:
			m.draw_style_box(Kit.sb(Kit.EDGE2, Color(Kit.BG2, 0.7), 1, 8), rr)
			Kit.th(m, _pos_name(slot, idx, side).to_upper(), rr.position + Vector2(12, 24), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 20.0)
			Kit.t(m, Kit.fit(m, "Locked: %s %s" % [_rar_name(Parts.opens_at(slot, idx)), "Receiver" if side == "weapon" else "Heart"], 14, rr.size.x - 20.0), rr.position + Vector2(12, 45), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 20.0)
		elif it.is_empty():
			m.draw_style_box(Kit.sb(Kit.CYAN if on else Kit.EDGE, Kit.PANEL2, 2 if on else 1, 8), rr)
			Kit.th(m, _pos_name(slot, idx, side).to_upper(), rr.position + Vector2(12, 24), 14, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 20.0)
			Kit.t(m, "Empty", rr.position + Vector2(12, 45), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 20.0)
		else:
			Kit.card_frame(m, rr, String(it["rar"]), m.t_anim, on)
			if on:
				m.draw_rect(rr.grow(2.0), Kit.CYAN, false, 2.0)
			PartVis.draw_part(m, it, look, Vector2(rr.position.x + 26.0, rr.get_center().y), 44.0, m.t_anim)
			Kit.th(m, _pos_name(slot, idx, side).to_upper(), rr.position + Vector2(54, 24), 14, Kit.rarity_text(String(it["rar"])), HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 62.0)
			Kit.t(m, Kit.fit(m, "%s  ·  Lv %d" % [String(it["name"]), int(it["lvl"])], 14, rr.size.x - 62.0), rr.position + Vector2(54, 45), 14, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 62.0)


static func _draw_inv(m, s: Dictionary, side: String, b: Rect2) -> void:
	Kit.panel(m, b, Kit.EDGE, Kit.PANEL)
	var sp: Array = sel_pos(m, side)
	var slot: String = String(sp[0])
	var lst: Array = _list(m, side)
	Kit.th(m, "%sS" % String(PartDB.SLOTS[slot]["name"]).to_upper(), b.position + Vector2(18, 36), 22, Kit.TEXT)
	Kit.t(m, "%d  ·  %d / %d parts" % [lst.size(), Parts.count(s), Parts.INV_CAP], Vector2(b.end.x - 18, b.position.y + 34), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 220.0)
	Kit.t(m, Kit.fit(m, "For %s  ·  click a part, then INSTALL" % _pos_name(slot, int(sp[1]), side), 14, b.size.x - 36.0), b.position + Vector2(18, 66), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, b.size.x - 36.0)
	var per: int = _per_page(m)
	var p0: int = int(m.arm_page) * per
	var look: Dictionary = Cores.look(s)
	for k in mini(per, lst.size() - p0):
		var it: Dictionary = Parts.item(s, int(lst[p0 + k]))
		var r: Rect2 = tile_rect(m, k)
		var sel: bool = int(it["uid"]) == int(m.arm_sel)
		var inset: bool = (m.arm_merge as Array).has(int(it["uid"]))
		Kit.card_frame(m, r, String(it["rar"]), m.t_anim, sel or inset)
		if sel:
			m.draw_rect(r.grow(3.0), Color(1, 1, 1, 0.9), false, 2.0)
		if inset:
			m.draw_rect(r.grow(3.0), Kit.GOLD, false, 2.0)
		PartVis.draw_part(m, it, look, r.get_center() + Vector2(0, -6), TILE * 0.66, m.t_anim)
		var rl: String = RARITY_LETTER.get(String(it["rar"]), "?")
		m.draw_style_box(Kit.sb(Color(Kit.rarity_col(String(it["rar"])), 0.9), Color(Kit.BG, 0.9), 1, 6), Rect2(r.position.x + 4, r.position.y + 4, 20, 20))
		Kit.th(m, rl, Vector2(r.position.x + 14, r.position.y + 19), 14, Kit.rarity_text(String(it["rar"])), HORIZONTAL_ALIGNMENT_CENTER, 20.0)
		Kit.th(m, "Lv%d" % int(it["lvl"]), Vector2(r.position.x + 8, r.end.y - 8), 14, Kit.TEXT)
		if Parts.is_equipped(s, int(it["uid"])):
			Kit.th(m, "IN", Vector2(r.end.x - 8, r.end.y - 8), 14, Kit.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 40.0)
		if bool(it.get("new", false)):
			m.draw_circle(Vector2(r.end.x - 12, r.position.y + 16), 6.0, Kit.MAGENTA)
		if bool(it.get("fav", false)):
			m.draw_circle(Vector2(r.position.x + 14, r.position.y + 36), 5.0, Kit.GOLD)
	if lst.is_empty():
		Kit.wrap(m, "No %ss yet. Elites, bosses and caches drop parts; Scrap crates and the Fabricator (Outpost) sell them." % String(PartDB.SLOTS[slot]["name"]), Vector2(b.position.x + 24.0, b.position.y + 160.0), 16, Kit.DIM, b.size.x - 48.0, 4)
	Kit.t(m, "Page %d / %d" % [int(m.arm_page) + 1, _pages(m, side)], Vector2(b.get_center().x, b.end.y - 26), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, 200.0)


static func _draw_card(m, s: Dictionary, side: String, c: Rect2) -> void:
	var it: Dictionary = _sel(m)
	if it.is_empty():
		Kit.panel(m, c, Kit.EDGE, Kit.PANEL)
		var sp0: Array = sel_pos(m, side)
		Kit.wrap(m, "Pick a %s on the left. %s" % [String(PartDB.SLOTS[String(sp0[0])]["name"]), "Each part type does one job; the chassis rarity opens more slots."], Vector2(c.position.x + 24.0, c.position.y + 60.0), 17, Kit.DIM, c.size.x - 48.0, 4)
		return
	var rar: String = String(it["rar"])
	var rc: Color = Kit.rarity_col_t(rar, m.t_anim)
	Kit.card_frame(m, c, rar, m.t_anim, false)
	var art_c: Vector2 = Vector2(c.get_center().x, c.position.y + 124.0)
	var since: float = float(m.t_anim) - float(m.arm_t)
	if since >= 0.0 and since < REVEAL_S:
		Kit.rarity_beam(m, art_c + Vector2(0, 100), rar, 240.0 * minf(1.0, since * 3.0), m.t_anim, 110.0)
	Kit.glow(m, art_c, 150.0, rc, 0.10 + 0.04 * float(RarityDB.rank(rar)))
	PartVis.draw_part(m, it, Cores.look(s), art_c, 190.0, m.t_anim)
	var x: float = c.position.x + 20.0
	var w: float = c.size.x - 40.0
	var slot: String = String(it["slot"])
	Kit.th(m, Kit.fit(m, String(it["name"]), 24, w), Vector2(x, c.position.y + 252), 24, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
	Kit.th(m, "%s  ·  %s  ·  %s" % [_rar_name(rar).to_upper(), String(PartDB.SLOTS[slot]["name"]).to_upper(), String(PartDB.get_def(String(it["base"]))["name"])], Vector2(x, c.position.y + 278), 16, rc, HORIZONTAL_ALIGNMENT_LEFT, w)
	Kit.wrap(m, how(it), Vector2(x, c.position.y + 284), 14, Kit.DIM, w, 2)
	var mx: int = Parts.max_lvl_of(rar)
	Kit.th(m, "Lv %d / %d   ·   Power x%.2f   ·   Masterworks %d" % [int(it["lvl"]), mx, Parts.power(it), int(it["mw"])], Vector2(x, c.position.y + 346), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
	Kit.bar_glow(m, Rect2(x, c.position.y + 356, w, 10), float(int(it["lvl"])) / float(mx), rc, mx / Parts.MW_EVERY)
	var y: float = c.position.y + 392.0
	if slot == "barrel":
		var dps: float = Parts.barrel_dps(s, it)
		var sp: Array = sel_pos(m, side)
		var cur: Dictionary = Parts.item(s, _installed_at(s, "barrel", int(sp[1]) if String(sp[0]) == "barrel" else 0))
		Kit.th(m, "Barrel DPS ~%.1f" % dps, Vector2(x, y), 18, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
		if not cur.is_empty() and int(cur["uid"]) != int(it["uid"]):
			var d0: float = Parts.barrel_dps(s, cur)
			if d0 > 0.0:
				var pct: float = (dps / d0 - 1.0) * 100.0
				Kit.th(m, "(%s%d%% vs %s)" % ["+" if pct >= 0.0 else "", int(round(pct)), Kit.fit(m, String(cur["name"]), 16, w - 260.0)], Vector2(x + 190.0, y), 16, Kit.GREEN if pct >= 0.0 else Kit.ENEMY, HORIZONTAL_ALIGNMENT_LEFT, w - 190.0)
	var fl: Array = Parts.fx_lines(Parts.base_fx(it))
	if not fl.is_empty():
		Kit.wrap(m, "  ·  ".join(fl), Vector2(x, y + 6.0), 15, Kit.TEXT, w, 2)
	# perks / offer / merge
	var of: Dictionary = Parts.block(s).get("offer", {})
	var ps: Array = it["perks"]
	var uid: int = int(it["uid"])
	if not of.is_empty() and int(of["uid"]) == uid:
		Kit.head(m, "REROLL: TAKE ONE OR KEEP", Vector2(x, c.position.y + 476), w, Kit.MAGENTA)
		var cur2: Dictionary = ps[int(of["idx"])]
		Kit.t(m, "Current: %s  %s" % [tier_name(int(cur2["t"])), AffixDB.text(String(cur2["id"]), int(cur2["t"]), float(cur2["q"]))], _perk_row(m, 0).position + Vector2(4, 28), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	elif not (m.arm_merge as Array).is_empty():
		var nx: String = RarityDB.next(rar)
		Kit.head(m, "MERGE  ->  %s" % _rar_name(nx).to_upper(), Vector2(x, c.position.y + 476), w, Kit.GOLD)
		var names: Array = []
		var top: int = 1
		for u in m.arm_merge:
			top = maxi(top, int(Parts.item(s, int(u)).get("lvl", 1)))
			if int(u) != uid:
				names.append(String(Parts.item(s, int(u)).get("name", "")))
		Kit.wrap(m, "Consumes: %s. Level -> %d. New perk slots roll around the new rarity." % [", ".join(names), maxi(1, top / 2)], _perk_row(m, 0).position + Vector2(4, 2), 15, Kit.DIM, w, 2)
	else:
		Kit.head(m, "PERKS   (locks %d / %d)" % [Parts.locks_on(it), Parts.lock_slots(s)], Vector2(x, c.position.y + 476), w, rc)
		for i in ps.size():
			var p: Dictionary = ps[i]
			var pr: Rect2 = _perk_row(m, i)
			var tc: Color = tier_col(int(p["t"]))
			Kit.panel(m, Rect2(pr.position, Vector2(pr.size.x - 222.0, pr.size.y)), Kit.GOLD if bool(p.get("lock", false)) else tc.darkened(0.2), Kit.PANEL2, 1)
			Kit.th(m, "T%d" % int(p["t"]), pr.position + Vector2(10, 29), 18, Kit.rarity_text(String(RarityDB.IDS[clampi(int(p["t"]) - 1, 0, 6)])))
			Kit.t(m, Kit.fit(m, AffixDB.text(String(p["id"]), int(p["t"]), float(p["q"])), 15, pr.size.x - 290.0), pr.position + Vector2(48, 28), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 290.0)
		if ps.is_empty():
			Kit.t(m, "No perks (starter part). Parts from drops, crates and the Fabricator roll perks.", _perk_row(m, 0).position + Vector2(4, 28), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	if Parts.is_equipped(s, uid):
		Kit.th(m, "INSTALLED", Vector2(c.end.x - 20, c.position.y + 34), 16, Kit.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 200.0)


static func _draw_crates(m, s: Dictionary, side: String) -> void:
	var bc: Rect2 = cols(m)["bc"]
	Kit.panel(m, bc, Kit.EDGE, Kit.PANEL)
	Kit.th(m, "SCRAP CRATES", bc.position + Vector2(18, 40), 24, Kit.GOLD)
	Kit.t(m, "Scrap: %s  ·  every crate counts toward pity  ·  Appraisal research adds luck" % Kit.fmt(float(s.get("scrap", 0))), Vector2(bc.position.x + 18, bc.position.y + 70), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, bc.size.x - 36.0)
	if Labs.level(s, "brand_contracts") <= 0:
		Kit.t(m, "Part Contracts research lets you pick the part type.", Vector2(bc.end.x - 18, bc.position.y + 40), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, bc.size.x * 0.5)
	var pity: Dictionary = Parts.block(s)["pity"]
	for k in Parts.CRATE_IDS.size():
		var id: String = String(Parts.CRATE_IDS[k])
		var cd: Dictionary = Parts.CRATES[id]
		var r: Rect2 = _crate_rect(m, k)
		var col: Color = [Kit.rarity_col("uncommon"), Kit.rarity_col("rare"), Kit.rarity_col("epic")][k]
		Kit.panel_glow(m, r, col, Kit.PANEL2, 1.0, 1)
		Kit.th(m, String(cd["name"]).to_upper(), Vector2(r.get_center().x, r.position.y + 36), 20, col.lerp(Kit.TEXT, 0.3), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 20.0)
		# the crate: a lidded box with a beam
		var bx: Vector2 = Vector2(r.get_center().x, r.position.y + 128.0)
		var bob: float = 3.0 * sin(m.t_anim * 2.0 + float(k))
		Kit.beam_col(m, bx + Vector2(0, 46), col, 120.0, 60.0, m.t_anim, 0.25)
		m.draw_rect(Rect2(bx + Vector2(-46, -20 + bob), Vector2(92, 60)), Color(0.08, 0.1, 0.16))
		m.draw_rect(Rect2(bx + Vector2(-50, -34 + bob), Vector2(100, 18)), col.darkened(0.3))
		m.draw_rect(Rect2(bx + Vector2(-46, -20 + bob), Vector2(92, 60)), col, false, 2.0)
		m.draw_rect(Rect2(bx + Vector2(-8, -20 + bob), Vector2(16, 60)), Color(col, 0.5))
		var lines: Array = ["%d part%s" % [int(cd["n"]), "" if int(cd["n"]) == 1 else "s"]]
		if String(cd["min"]) != "":
			lines.append("the first is %s or better" % _rar_name(String(cd["min"])))
		if float(cd["luck"]) > 0.0:
			lines.append("+%d rarity luck" % int(cd["luck"]))
		var luck: float = float(cd["luck"]) + float(Labs.level(s, "appraisal"))
		var od: Dictionary = Parts.odds_now("drop", luck, pity)
		var ep: float = 0.0
		for rid in RarityDB.IDS:
			if RarityDB.at_least(String(rid), "epic"):
				ep += float(od[rid])
		lines.append("Epic+ per part: %.1f%%" % ep)
		for j in lines.size():
			Kit.t(m, String(lines[j]), Vector2(r.get_center().x, r.position.y + 214.0 + float(j) * 24.0), 15, Kit.TEXT if j == 0 else Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 20.0)
		var tip: Array = ["%s odds now (luck %d + pity):" % [String(cd["name"]), int(luck)]]
		for rid in RarityDB.IDS:
			tip.append("%s  %.2f%%" % [_rar_name(String(rid)), float(od[rid])])
		m.stat_tips.append([Rect2(r.position.x, r.position.y + 200.0, r.size.x, 100.0), "\n".join(tip)])
	# visible pity
	var py: float = _crate_rect(m, 0).end.y + 40.0
	var pw: float = (bc.size.x - 32.0 - 32.0) / 3.0
	var names: Dictionary = {"e": "Epic+", "l": "Legendary+", "m": "Mythic+"}
	var ks: Array = ["e", "l", "m"]
	for i in ks.size():
		var g: String = ks[i]
		var pd: Dictionary = RarityDB.PITY[g]
		var xx: float = bc.position.x + 16.0 + float(i) * (pw + 16.0)
		Kit.th(m, "%s guaranteed within %d" % [names[g], maxi(1, int(pd["hard"]) - int(pity.get(g, 0)))], Vector2(xx, py), 15, Kit.rarity_text(String(pd["min"])), HORIZONTAL_ALIGNMENT_LEFT, pw)
		Kit.bar_glow(m, Rect2(xx, py + 10.0, pw, 10.0), float(pity.get(g, 0)) / float(pd["hard"]), Kit.rarity_col(String(pd["min"])))
	Kit.wrap(m, "Parts also drop in runs (elites, bosses, Couriers, caches) and the Fabricator in the Outpost sells a rotating stock. Unwanted parts melt into Scrap in the Smelter.", Vector2(bc.position.x + 18.0, py + 52.0), 15, Kit.DIM, bc.size.x - 36.0, 3)


static func _draw_presets(m, s: Dictionary) -> void:
	var bc: Rect2 = cols(m)["bc"]
	Kit.panel(m, bc, Kit.EDGE, Kit.PANEL)
	Kit.th(m, "LOADOUT PRESETS", bc.position + Vector2(18, 40), 22, Kit.TEXT)
	Kit.t(m, "Save every installed part (Weapon + Core), swap back in one click. More slots: Loadout Presets research.", bc.position + Vector2(18, 70), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, bc.size.x - 36.0)
	var look: Dictionary = Cores.look(s)
	for k in mini(Parts.PRESETS_MAX, Labs.preset_slots(s)):
		var r: Rect2 = _preset_rect(m, k)
		var pr: Dictionary = Parts.preset(s, k)
		Kit.panel(m, r, Kit.EDGE2, Kit.CARD, 1)
		Kit.th(m, "LOADOUT %d" % (k + 1), Vector2(r.position.x + 16, r.position.y + 30), 18, Kit.GOLD)
		if pr.is_empty():
			Kit.t(m, "Empty - SAVE stores every installed part", Vector2(r.position.x + 16, r.position.y + 58), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 290.0)
			continue
		var x: float = r.position.x + 16.0
		var eqd: Dictionary = pr.get("equipped", {})
		for sl in PartDB.SLOTS.keys():
			for u in (eqd.get(sl, []) as Array):
				var it: Dictionary = Parts.item(s, int(u))
				if it.is_empty():
					continue
				PartVis.draw_part(m, it, look, Vector2(x + 22.0, r.position.y + 84.0), 44.0, m.t_anim)
				x += 48.0
				if x > r.end.x - 300.0:
					break
