extends Node2D
## Corehold PC — native 1920x1080 desktop view (REDESIGN_SPEC §5).
## One unscaled Control layer (`ui`) holds every button; everything else is
## drawn in _draw() by the screen modules under ui/. The view owns no rules:
## every action calls a pure module (TowerState, Cores, Outpost, Reforge,
## Labs, Missions) and replays the returned events.
## Screens: menu (save slots) | base (the hub: Outpost home, Core, Research,
## Missions, Reforge) | run (battlefield) | results.
## Layout: top bar 56 px; run = left panel | centred field | right panel over a
## 96 px specials hotbar. Resizable: everything is laid out from vw/vh.

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const TuneRef := preload("res://Tune.gd")
const Labs := preload("res://Labs.gd")
const Missions := preload("res://Missions.gd")
const Outpost := preload("res://Outpost.gd")
const Tiers := preload("res://Tiers.gd")
const Cores := preload("res://Cores.gd")
const Specials := preload("res://Specials.gd")
const PickDB := preload("res://data/PickDB.gd")
const LabDB := preload("res://data/LabDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")
const ReforgeDB := preload("res://data/ReforgeDB.gd")
const SfxScript := preload("res://Sfx.gd")
const FxPool := preload("res://vfx/FxPool.gd")
const Juice := preload("res://vfx/Juice.gd")
const BurstsScript := preload("res://vfx/Bursts.gd")
const GoreScript := preload("res://vfx/Gore.gd")
const Settings := preload("res://Settings.gd")
const SteamService := preload("res://SteamService.gd")
const Achievements := preload("res://Achievements.gd")
const Keybinds := preload("res://Keybinds.gd")
const Stats := preload("res://Stats.gd")
const Kit := preload("res://ui/Kit.gd")
const Desktop := preload("res://ui/Desktop.gd")
const Battle := preload("res://ui/Battle.gd")
const RunArt := preload("res://ui/RunArt.gd")
## V2 P7d: the new weapons borrow the nearest existing shot sound.
## V2 P9: every weapon has its own shot clip; kinds without one fall back here.
const SHOT_CLIP: Dictionary = {}
const Intel := preload("res://ui/Intel.gd")
const Hub := preload("res://ui/Hub.gd")
const OutpostView := preload("res://ui/OutpostView.gd")
const WeaponDB := preload("res://data/WeaponDB.gd")
const Fonts := preload("res://ui/Fonts.gd")
const NeonTheme := preload("res://ui/NeonTheme.gd")
const Roll := preload("res://vfx/Roll.gd")
const Gear := preload("res://Gear.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const FrameDB := preload("res://data/FrameDB.gd")
const ModuleDB := preload("res://data/ModuleDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const LootReveal := preload("res://ui/LootReveal.gd")

const GOLD: Color = Kit.GOLD
const GEM: Color = Kit.GEM
const ENEMY: Color = Kit.ENEMY
const ENEMY2: Color = Kit.MAGENTA
const SHIELD: Color = Color("7fd8ff")
const TEXT: Color = Kit.TEXT
const GREEN: Color = Kit.GREEN
const TOP_H: float = 56.0
const HOT_H: float = 96.0
const NAV_H: float = 60.0
const FADE_TIME: float = 0.25
const DMG_MERGE: float = 0.1
## V2 P9 audit: hits this close (px) to a young number add to it (any body).
const DMG_NEAR: float = 30.0
## World extent shown by the run field (spawn ring diameter + margin).
const WORLD_SPAN: float = 2.0 * TowerState.SPAWN_R * 0.78   # was 0.84: larger run-grid cells (PM fix round)

var save: Dictionary = {}
var settings: Dictionary = {}        # global user://settings.cfg (Settings.gd), never in a slot
var ach_run: Dictionary = {}         # Achievements.new_run() context for the live run
var S: RefCounted = null
var screen: String = "menu"          # menu | base | run | results
var tab: String = "play"             # hub tab (Hub.TABS)
var overlay: String = ""             # "" | pause | settings | credits | stats | history | achievements | modes
var sel: int = -1                    # run: selected grid cell
var last_result: Dictionary = {}
var last_breakdown: Dictionary = {}
var ui: Control
var font: Font                       # Inter (body); Kit picks Chakra Petch for headings
var font_head: Font
## Top-bar currency counters roll up to their new value (vfx/Roll.gd).
var rolls: Dictionary = {"coins": Roll.new(), "scrap": Roll.new(), "shards": Roll.new()}
var t_anim: float = 0.0
var results_t0: float = 0.0          # t_anim when the results screen opened (coin roll-up)
var ui_t: float = 0.0
var poll_t: float = 0.0
var last_tap_ms: int = -1000
var now_override: int = 0            # tests inject unix time here
var offline_offer: Dictionary = {}   # Outpost.away_report while the boot modal is up
var toast_text: String = ""
var toast_t: float = 0.0
var toast_queue: Array = []
var view_tier: int = 1
var run_missions: int = 0
var intel_seen: Dictionary = {}       # FB2 right panel: enemy kind -> first wave seen
var loot_feed: Array = []             # FB2 right panel: aggregated loot-drop feed
var loot_coin_seen: float = 0.0
var run_loot: Array = []             # meta events banked at run end (loot, insight)
var meta_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var sfx: Node = null                 # Sfx.gd (owned child, not an autoload)
var fader: ColorRect
var fade: float = 0.0
# view-only fx (replayed from engine events)
var tracers: FxPool = FxPool.new(96)  # {a, b, t, color, w}
var rings: FxPool = FxPool.new(64)    # {pos, r, t, color}
var pops: FxPool = FxPool.new(24)     # {pos, text, t, color, size}
## V2 P10 (owner: "see your looting in action"): a loot icon pops over the
## body that dropped it - {pos, icon, color, text, t}.
var loot_pops: FxPool = FxPool.new(32)
const LOOT_POP_S: float = 1.1
var dmgnums: FxPool = FxPool.new(48)  # {pos, amt, eid, t, size}
var bolts: FxPool = FxPool.new(24)    # {a, t}
var juice: Juice = Juice.new()
var bursts: Node2D = null
var gore: Node2D = null                 # HORDE P5: blood bursts + never-cleared ground layer
var dbg_overlay: bool = false           # HORDE P6: F3 debug overlay
var dbg_sim_ms: float = 0.0
var dbg_render_ms: float = 0.0       # MASS_HORDE §View: C# fill + upload of the horde MultiMeshes
var frame_k: float = 0.0              # MASS_HORDE §View: 0 = frame the base, 1 = frame the horde spawn ring
var dbg_fps: float = 0.0
var fclip: Control                   # clips kill particles to the battlefield
var slot_pop: Dictionary = {}
var flash: float = 0.0
var flash_cd: float = 0.0              # FB2: Core-hit flash rate limit (hordes hit every substep)
var heal_flash: float = 0.0
var level_burst: float = 0.0
var insight_t: float = 0.0           # Insight fanfare timer
var insight_name: String = ""
# layout
var vw: float = 1920.0
var vh: float = 1080.0
var side_w: float = 400.0
var zoom: float = 1.0                # battlefield wheel zoom (0.8 - 1.4)
# tooltips
var tipbox: PanelContainer
var tip_label: Label
var tip_rich: RichTextLabel
var mouse_pos: Vector2 = Vector2(-1, -1)
var tip_text: String = ""
var tip_t: float = 0.0
var stat_tips: Array = []            # [[Rect2, text]] regions registered while drawing
# input state
var last_device: String = "kbm"      # "kbm" | "pad"
var pad_style: String = "xbox"
var remap_action: String = ""
var set_tab_id: String = "video"
var keymap_page: int = 0
var confirm_del: int = 0
var run_opts: Dictionary = {"mode": "normal", "modifiers": []}
var last_seed: int = 0
var menu_msg: String = ""
var drag_card: int = -1              # run: draft card being dragged onto the grid
var bld_drag: int = -1               # run: placed building pressed (V2 P7a drag-merge)
var enh_tree: String = "attack"      # run: open Core Enhancement tree (V2 P7b)
var enh_mode: int = 1                # run: buy 1 / 5 / 0 = MAX levels per click
var supply_show: Dictionary = {}     # run: the Supply Drop on screen (V2 P7c)
var supply_t0: float = -99.0
var supply_clicks: int = 0
var drag_start: Vector2 = Vector2.ZERO
var aim_special: int = -1            # run: targeted special waiting for a field click
var banish_mode: bool = false        # run: next card click banishes
# Outpost builder
var op_cam: Vector2 = Vector2.ZERO   # map pan offset (screen px)
var op_zoom: float = 1.0
var op_arm: String = ""              # building / decor id armed for placement
var op_rot: int = 0
var op_sel: String = ""              # selected uid ("relay", "<uid>", "d<uid>")
var op_moving: bool = false
var op_cat: String = "prod"
var op_pan: bool = false
var op_pan_from: Vector2 = Vector2.ZERO
var op_pan_moved: bool = false
var op_drag: bool = false            # palette -> map drag in progress
var op_msg: String = ""
var op_bp_text: String = ""
var op_focus: Vector2i = Vector2i(4, 4)   # keyboard / pad map cursor
# Reforge
var rf_confirm: int = 0              # two-step confirm
# V2 P4 Forge / Core screens (ForgeView, CoreView)
var forge_sel: int = 0               # selected item uid
var forge_filter: String = "all"     # all | weapon | module
var forge_page: int = 0
var forge_kind: String = "weapon"    # Forge-new panel: weapon | module
var forge_merge: Array = []          # [base, a, b] while the merge panel is open
var forge_imprint: int = 0           # target uid while imprinting
var forge_donor: int = 0
var forge_confirm: int = 0           # salvage two-step confirm (Rare+)
var forge_t: float = -10.0           # t_anim of the last forge / merge (reveal beam)
var core_tab: String = "loadout"     # loadout | look | levels
var core_sock: int = -1              # -1 the Weapon slot, 0.. a Module socket
var core_page: int = 0
# V2 P4 manual aim (run): hold LMB on open field, or deflect the right stick
var aim_down: bool = false
var aim_t: float = 0.0
var pad_aim: bool = false
var turret_ang: float = -PI * 0.5     # drawn turret angle (eases toward the engine's aim)
const AIM_HOLD_S: float = 0.15
# V2 P5 loot: the reveal overlay (LootReveal) and in-world drop beams
var reveal_uids: Array = []
var reveal_t0: float = 0.0
var reveal_fired: int = 0
var reveal_skip: bool = false
var reveal_page: int = 0
var loot_beams: Array = []          # [{pos, col, t}] item / cache drops in the run
# V2 P6 requirement jumps (Kit.req_chip -> jump_to): what to pulse / flash
var op_pulse: String = ""            # Outpost uid ("relay") pulsing after a jump
var op_pulse_t: float = -10.0
var op_flash: String = ""            # palette entry flashing (a building not built yet)
var op_flash_t: float = -10.0
var res_focus: String = ""           # research card pulsing
var res_cat: String = "core"          # Research tab category (LabDB.CATS)
var auto_collect_t: float = 0.0       # V2 P8b Auto-Collect cadence (menus)
const AUTO_COLLECT_S: float = 30.0
var res_focus_t: float = -10.0
var credits_scroll: float = 0.0


func _ready() -> void:
	font = Fonts.body()
	font_head = Fonts.head()
	settings = Settings.read()
	Settings.apply(settings, get_tree())
	SteamService.init()
	ach_run = Achievements.new_run()
	meta_rng.seed = int(Time.get_ticks_usec() % 1000000007)
	fclip = Control.new()
	fclip.clip_contents = true
	fclip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fclip)    # before ui: particles under the widgets, clipped to the field
	bursts = BurstsScript.new()
	fclip.add_child(bursts)
	gore = GoreScript.new()
	fclip.add_child(gore)
	gore.call("setup", TowerState.CENTER, gore_level())
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = NeonTheme.get_theme()
	add_child(ui)
	tipbox = PanelContainer.new()
	tipbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tipbox.visible = false
	tipbox.add_theme_stylebox_override("panel", Kit.tip_style())
	tipbox.theme = NeonTheme.get_theme()
	tip_label = Label.new()
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_label.add_theme_font_size_override("font_size", 17)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(320, 0)
	# tip_label holds the canonical text; tip_rich renders it structured
	# (header + one stat line per row with icons; owner feedback #1).
	tip_label.visible = false
	var tvb := VBoxContainer.new()
	tvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tvb.add_child(tip_label)
	tip_rich = RichTextLabel.new()
	tip_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_rich.bbcode_enabled = true
	tip_rich.fit_content = true
	tip_rich.scroll_active = false
	tip_rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_rich.custom_minimum_size = Vector2(340, 0)
	tip_rich.add_theme_font_size_override("normal_font_size", 16)
	tip_rich.add_theme_font_size_override("bold_font_size", 19)
	tvb.add_child(tip_rich)
	tipbox.add_child(tvb)
	add_child(tipbox)
	fader = ColorRect.new()
	fader.color = Kit.BG
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fader.modulate = Color(1, 1, 1, 0)
	add_child(fader)
	get_viewport().size_changed.connect(_on_resize)
	_layout()
	sfx = SfxScript.new()
	sfx.name = "Sfx"
	add_child(sfx)
	boot(MetaSave.read(), now())
	screen = "menu"   # PC: boot to the main menu / save-slot picker
	_rebuild_ui()


## Recompute the frame from the live viewport size (resizable window).
func _layout() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	vw = maxf(vs.x, 1024.0)
	vh = maxf(vs.y, 600.0)
	side_w = clampf(roundf(vw * 0.2083), 300.0, 400.0)
	ui.size = Vector2(vw, vh)
	fader.size = Vector2(vw, vh)
	var fr: Rect2 = field_rect()
	fclip.position = fr.position
	fclip.size = fr.size


func _on_resize() -> void:
	_layout()
	_rebuild_ui()


# ---------------------------------------------------------------- frames
func left_rect() -> Rect2:
	return Rect2(0, TOP_H, side_w, vh - TOP_H)


func right_rect() -> Rect2:
	return Rect2(vw - side_w, TOP_H, side_w, vh - TOP_H)


## Owner feedback #1: no bottom bar — abilities float over the bottom of the field.
func hot_rect() -> Rect2:
	var fr: Rect2 = field_rect()
	return Rect2(fr.position.x, fr.end.y - HOT_H, fr.size.x, HOT_H)


func field_rect() -> Rect2:
	return Rect2(side_w, TOP_H, vw - 2.0 * side_w, vh - TOP_H)


## Hub content area (below the top bar and the hub nav row).
func content_rect() -> Rect2:
	return Rect2(0, TOP_H + NAV_H, vw, vh - TOP_H - NAV_H)


## Battlefield transform: world (engine) space -> screen, zoomed about the Core.
func world_xform() -> Transform2D:
	var fr: Rect2 = field_rect()
	# Owner feedback #1: the field zooms to the run grid (bigger grid -> smaller
	# scale), framing the spawn ring of this run.
	var span: float = WORLD_SPAN if S == null else 2.0 * lerpf(float(S.view_r()) * 0.78, float(S.spawn_r()) * 0.9, frame_k)
	var k: float = minf(fr.size.x, fr.size.y) / span * zoom
	return Transform2D(0.0, Vector2(k, k), 0.0, fr.get_center() - TowerState.CENTER * k)


func w2s(p: Vector2) -> Vector2:
	return world_xform() * p


func s2w(p: Vector2) -> Vector2:
	return world_xform().affine_inverse() * p


func world_scale() -> float:
	return world_xform().get_scale().x


## Building under a world point: the anchor of the footprint covering the
## cell (CORE_SLOT on the Core), else the bare cell (-1 off the board).
func pick_at(pos: Vector2) -> int:
	var c: int = slot_at(pos)
	if c < 0 or S == null:
		return c
	var o: int = S.owner_at(c)
	return o if o >= 0 else c


## Anchor for placing `id` with its footprint centred under a world point.
func place_anchor(pos: Vector2, id: String) -> int:
	return TowerState.anchor_at(pos, TowerState.size_of(id))


## Grid cell under a world point (-1 = none).
func slot_at(pos: Vector2) -> int:
	var hs: float = float(TowerState.SIDE) * 0.5 * TowerState.CELL
	var rel: Vector2 = pos - TowerState.CENTER + Vector2(hs, hs)
	if rel.x < 0.0 or rel.y < 0.0:
		return -1
	var x: int = int(rel.x / TowerState.CELL)
	var y: int = int(rel.y / TowerState.CELL)
	if x >= TowerState.SIDE or y >= TowerState.SIDE:
		return -1
	return y * TowerState.SIDE + x


# ------------------------------------------------------------------ boot
## Boot: normalize (V2 hard reset) -> Outpost tick -> Labs.claim -> Missions.roll
## -> "while you were away" modal (the Outpost's stored production).
func boot(raw: Dictionary, t: int) -> void:
	save = BaseMeta.normalize(raw)
	var ev: Array = []
	if bool(save.get("reset_v2", false)):
		save.erase("reset_v2")
		ev.append({"t": "msg", "text": "Corehold V2: a fresh start. Your old save was reset for the redesign."})
	ev.append_array(Outpost.tick(save, t))
	ev.append_array(Labs.claim(save, t))
	ev.append_array(Missions.roll(save, t))
	var off: Dictionary = Outpost.away_report(save, t)
	var any: bool = false
	for k in ["coins", "scrap"]:
		if int(off[k]) > 0:
			any = true
	if any:
		offline_offer = off
	else:
		offline_offer = {}
		save["last_seen"] = t
	view_tier = int(save["tier"])
	screen = "base"
	tab = "play"
	sel = -1
	overlay = ""
	_queue_toasts(ev)
	MetaSave.write(save)
	if sfx != null:
		sfx.apply_settings(save["settings"])
		sfx.music_play()
	_rebuild_ui()


func now() -> int:
	if now_override > 0:
		return now_override
	return int(Time.get_unix_time_from_system())


static func fmt_num(v: int) -> String:
	return Kit.fmt(float(v))


static func fmt_dur(sec: int) -> String:
	return Kit.dur(sec)


# ------------------------------------------------------------------ flow
func start_run(seed_override: int = 0) -> void:
	if not Tiers.is_unlocked(save, view_tier):
		return
	BaseMeta.select_tier(save, view_tier)
	S = TowerState.new()
	_clear_fx()
	run_missions = 0
	run_loot = []
	loot_beams = []
	Intel.reset(self)
	last_breakdown = {}
	var sd: int = seed_override if seed_override != 0 else TuneRef.seed_of(int(Time.get_ticks_usec() % 1000000))
	last_seed = sd
	var opts: Dictionary = run_opts.duplicate(true)
	if String(opts.get("mode", "normal")) == "endless" and not BaseMeta.endless_unlocked(save):
		opts["mode"] = "normal"
	ach_run = Achievements.new_run()
	_handle(S.setup(sd, save, now(), opts))
	screen = "run"
	sel = -1
	overlay = ""
	drag_card = -1
	aim_special = -1
	banish_mode = false
	_fade_in()
	_rebuild_ui()


## Results -> hub (Play tab).
func go_base() -> void:
	screen = "base"
	tab = "play"
	sel = -1
	overlay = ""
	_fade_in()
	_clear_fx()
	view_tier = int(save["tier"])
	var lev: Array = Labs.claim(save, now())
	lev.append_array(Outpost.tick(save, now()))
	_queue_toasts(lev)
	_meta_sfx(lev)
	_rebuild_ui()


## PC main menu / save-slot picker.
func go_menu() -> void:
	if S != null and screen == "run":
		return
	_save()
	screen = "menu"
	overlay = ""
	confirm_del = 0
	_fade_in()
	_rebuild_ui()


func load_slot(n: int) -> void:
	if not MetaSave.set_active(n):
		return
	menu_msg = ""
	boot(MetaSave.read(), now())
	_fade_in()


func ask_delete(n: int) -> void:
	confirm_del = n
	_rebuild_ui()


func delete_slot(n: int) -> void:
	if confirm_del == n and MetaSave.delete_slot(n, MetaSave.DELETE_CONFIRM):
		menu_msg = "Slot %d deleted" % n
		if MetaSave.active == n:
			save = BaseMeta.normalize({})
	confirm_del = 0
	_rebuild_ui()


func copy_slot(n: int) -> void:
	for d in range(1, MetaSave.SLOT_COUNT + 1):
		if not MetaSave.slot_exists(d) and MetaSave.copy_slot(n, d):
			menu_msg = "Copied slot %d to slot %d" % [n, d]
			_rebuild_ui()
			return
	menu_msg = "No empty slot to copy into"
	_rebuild_ui()




func _fade_in() -> void:
	fade = FADE_TIME


## Modal overlays. While one is up on the run screen the engine is not ticked.
func set_overlay(id: String) -> void:
	overlay = id
	remap_action = ""
	confirm_del = 0
	credits_scroll = 0.0
	_rebuild_ui()


func is_paused() -> bool:
	return screen == "run" and overlay != ""


## Pause menu "Abandon run": the engine banks coins via its normal death path
## and emits game_over / dead, which the view replays like a real death.
func abandon_run() -> void:
	if S == null or screen != "run":
		return
	overlay = ""
	_handle(S.abandon())
	_fade_in()
	_rebuild_ui()


func set_tab(id: String) -> void:
	if screen != "base":
		return
	if tab == "forge" and id != "forge":
		# V2 P9 audit: leaving the Forge marks what it showed as seen, so the
		# "new" dots / Forge badge mean new since the last visit
		for u in Gear.uids(save):
			Gear.mark_seen(save, int(u))
	tab = id
	op_arm = ""
	op_moving = false
	rf_confirm = 0
	_rebuild_ui()


func _save() -> void:
	if offline_offer.is_empty():
		save["last_seen"] = now()
	MetaSave.write(save)


## Every meta action funnels through here: toast, sfx, achievements, persist.
func meta_act(ev: Array) -> void:
	if not ev.is_empty():
		ev.append_array(Achievements.on_events(save, ach_run, ev, now()))
		_queue_toasts(ev)
		_meta_sfx(ev)
		_save()
	_rebuild_ui()


func claim_offline() -> void:
	var ev: Array = Outpost.claim_away(save, now())
	offline_offer = {}
	meta_act(ev)


func shift_tier(d: int) -> void:
	view_tier = clampi(view_tier + d, 1, mini(Tiers.tier_max(), Tiers.highest(save) + 1))
	if BaseMeta.select_tier(save, view_tier):
		_save()
	_rebuild_ui()


func cycle_speed(d: int = 1) -> void:
	if S == null:
		return
	var steps: Array = Labs.speed_steps(save)
	if steps.size() <= 1:
		return
	var idx: int = 0
	for k in steps.size():
		if absf(float(steps[k]) - S.speed) < 0.01:
			idx = k
	var v: float = float(steps[(idx + d + steps.size()) % steps.size()])
	BaseMeta.set_speed(save, v)
	_handle(S.set_speed(v))
	_rebuild_ui()


# ------------------------------------------------------------ run actions
func pick_card(k: int) -> void:
	if S == null or k < 0 or k >= S.draft.size():
		return
	if banish_mode:
		banish_mode = false
		_handle(S.banish(k))
	else:
		_handle(S.choose_card(k))
	_rebuild_ui()


func reroll() -> void:
	if S != null and not S.draft.is_empty():
		_handle(S.reroll_draft())
		_rebuild_ui()


func toggle_banish() -> void:
	if S != null and not S.draft.is_empty() and S.banish_left > 0:
		banish_mode = not banish_mode
		_rebuild_ui()


## V2 P7b: buys 1 / 5 / MAX levels of an enhancement (the panel's mode).
func buy_track(t: String) -> void:
	if S != null:
		_handle(S.buy_tracks(t, int(enh_mode) if int(enh_mode) > 0 else 999))
		_rebuild_ui()


func cycle_enh_mode() -> void:
	enh_mode = 5 if enh_mode == 1 else (0 if enh_mode == 5 else 1)
	_rebuild_ui()


## Hotkeys 1-4: cast a special; a targeted one (Orbital) arms the aim cursor —
## click the field to drop it, or press the key again to auto-target.
func cast(k: int) -> void:
	if S == null or k < 0 or k >= S.specials.size():
		return
	var id: String = String((S.specials[k] as Dictionary)["id"])
	if Specials.is_targeted(id) and aim_special != k:
		aim_special = k
		_rebuild_ui()
		return
	var r: Dictionary = S.cast_special(k, -1)
	aim_special = -1
	_cast_result(r)


func cast_at(screen_pos: Vector2) -> void:
	if S == null or aim_special < 0:
		return
	var k: int = aim_special
	aim_special = -1
	_cast_result(S.cast_special(k, s2w(screen_pos)))


func _cast_result(r: Dictionary) -> void:
	var res: String = String(r.get("result", ""))
	if res == "cooldown":
		_queue_toasts([{"t": "msg", "text": "Special is recharging"}])
	elif res == "no_target":
		_queue_toasts([{"t": "msg", "text": "No target in range"}])
	_handle(r.get("ev", []))
	_rebuild_ui()


## V2 P3c: turn the pick being placed (from the facing its ghost shows) or
## the selected directional weapon by d x 45 deg. Free.
func rotate_weapon(d: int = 1) -> void:
	if S == null:
		return
	if S.pending_place != "":
		_handle(S.rotate_pending(d, place_anchor(s2w(mouse_pos), S.pending_place)))
	elif sel >= 0:
		_handle(S.rotate(sel, d))
	_rebuild_ui()


func place_at(i: int) -> void:
	if S != null and S.pending_place != "" and i >= 0:
		# V2 P7a: a duplicate card dropped on its T1 twin merges into it
		var tw: int = S.owner_at(i)
		if tw >= 0 and S.card_merge_targets(S.pending_place).has(tw):
			_handle(S.merge_card(tw))
		else:
			_handle(S.place(i))
		_rebuild_ui()


## V2 P7a: fold building `a` into its twin `b` (drag-merge / Merge button).
func merge_into(a: int, b: int) -> void:
	if S == null or a < 0 or b < 0:
		return
	var ev: Array = S.merge(a, b)
	if not ev.is_empty():
		sel = b
	_handle(ev)
	_rebuild_ui()


# ------------------------------------------------------------- fx helpers
func _tracer(a: Vector2, b: Vector2, col: Color, w: float, life: float = 0.12) -> void:
	var d: Dictionary = tracers.take(life)
	d["a"] = a
	d["b"] = b
	d["color"] = col
	d["w"] = w


func _ring(pos: Vector2, r: float, t: float, col: Color) -> void:
	var d: Dictionary = rings.take(t)
	d["pos"] = pos
	d["r"] = r
	d["color"] = col


func _pop(pos: Vector2, text: String, t: float, col: Color, size: int) -> void:
	var d: Dictionary = pops.take(t)
	d["pos"] = pos
	d["text"] = text
	d["color"] = col
	d["size"] = size


## Loot icon over the body that dropped it (Scrap, an item, a cache, coins).
func _loot_pop(ev: Dictionary) -> void:
	var kind: String = String(ev.get("kind", ""))
	var icon: String = "cur_scrap"
	var col: Color = Color.WHITE
	var text: String = ""
	match kind:
		"scrap":
			text = "+%d" % int(ev.get("n", 1))
		"item":
			icon = "icon_gear"
			col = Kit.rarity_text(drop_rar(ev))
		"cache":
			icon = "chest"
			col = Kit.rarity_text(drop_rar(ev))
		"coins":
			icon = "cur_coin"
			text = "+%d" % int(ev.get("n", ev.get("coins", 1)))
		_:
			return
	var n: Dictionary = loot_pops.take(LOOT_POP_S)
	n["pos"] = ev.get("pos", TowerState.CENTER)
	n["icon"] = icon
	n["color"] = col
	n["text"] = text


## Floating damage number: hits on one enemy within DMG_MERGE merge.
func _dmg_num(eid: int, pos: Vector2, amt: float) -> void:
	var mode: String = String((Settings.normalize(settings)["video"] as Dictionary).get("dmg_numbers", "all"))
	if mode == "off":
		return
	for d in dmgnums.items:
		if float(d["t"]) > 0.0 and int(d.get("eid", -1)) == eid and float(d["life"]) - float(d["t"]) < DMG_MERGE:
			d["amt"] = float(d["amt"]) + amt
			d["pos"] = pos
			d["size"] = dmg_size(float(d["amt"]))
			return
	# V2 P9 audit: a young number within DMG_NEAR px absorbs the hit too (splash
	# and mass hits sum into one readable figure instead of a pile of overlaps)
	for d in dmgnums.items:
		if float(d["t"]) > 0.0 and float(d["life"]) - float(d["t"]) < DMG_MERGE and (d["pos"] as Vector2).distance_squared_to(pos) < DMG_NEAR * DMG_NEAR:
			d["amt"] = float(d["amt"]) + amt
			d["size"] = dmg_size(float(d["amt"]))
			return
	var n: Dictionary = dmgnums.take(0.6)
	n["eid"] = eid
	n["pos"] = pos
	n["amt"] = amt
	n["size"] = dmg_size(amt)


static func dmg_size(amt: float) -> int:
	return clampi(int(13.0 + 4.0 * log(maxf(1.0, amt)) / log(10.0)), 14, 34)


static func kill_color(kind: String) -> Color:
	match kind:
		"boss":
			return GOLD
		"elite":
			return SHIELD
		"skitter", "mite", "splitter":
			return ENEMY2
	return ENEMY


func _clear_fx() -> void:
	tracers.clear()
	rings.clear()
	pops.clear()
	loot_pops.clear()
	bolts.clear()
	dmgnums.clear()
	if bursts != null:
		bursts.call("clear")
	if gore != null:
		gore.call("clear")
	slot_pop.clear()
	juice.reset()
	flash = 0.0
	flash_cd = 0.0
	heal_flash = 0.0
	level_burst = 0.0
	insight_t = 0.0


func enemy_pos(eid: int) -> Variant:
	if S == null:
		return null
	var s: int = S.en.slot_of(eid)
	return S.en.pos[s] if s >= 0 else null


# ---------------------------------------------------------------- events
func ev_text(e: Dictionary) -> String:
	match String(e.get("t", "")):
		"msg":
			return String(e["text"])
		"lab_done":
			return "Research done: %s Lv%d" % [String((LabDB.DEFS[String(e["track"])] as Dictionary)["name"]), int(e["lvl"])]
		"lab_started":
			return "Researching %s" % String((LabDB.DEFS[String(e["track"])] as Dictionary)["name"])
		"achievement":
			return "Achievement: " + String(e.get("name", ""))
		"mission_claimed":
			return "Mission reward +%d coins" % int(e.get("coins", 0))
		"mission_bonus":
			return "All-clear bonus +%d coins" % int(e.get("coins", 0))
		"mission_done":
			return "Mission complete!"
		"streak_claimed":
			return "Day %d reward: +%d coins" % [int(e["day"]), int(e["coins"])]
		"offline":
			return "Collected the Outpost: +%s coins" % fmt_num(int(e["coins"]))
		"tier_unlocked":
			return "Tier %d unlocked! +%d coins" % [int(e["tier"]), int(e.get("coins", 0))]
		"missions_rolled":
			return "New daily missions"
		"core_level":
			return "Core -> Lv%d" % int(e["level"])
		"op_placed":
			return "%s placed" % String(OutpostDB.get_def(String(e["id"])).get("name", ""))
		"build_done":
			return "%s finished building" % String(OutpostDB.get_def(String(e["id"])).get("name", ""))
		"upgrade_done":
			return "%s -> Lv%d" % [String(OutpostDB.get_def(String(e["id"])).get("name", "")), int(e["lvl"])]
		"relay_done":
			return "Core Relay -> Lv%d" % int(e["lvl"])
		"collect":
			return "+%d %s" % [int(e["n"]), String(e["res"])]
		"auto_collect":
			return "Auto-collected +%s coins%s" % [Kit.fmt(float(e["coins"])), ("  +%d Scrap" % int(e["scrap"])) if int(e["scrap"]) > 0 else ""]
		"preset_saved":
			return "Loadout %d saved" % (int(e["k"]) + 1)
		"preset_loaded":
			return "Loadout %d equipped%s" % [int(e["k"]) + 1, ("  (%d missing)" % int(e["missing"])) if int(e["missing"]) > 0 else ""]
		"plot_open":
			return "New land opened"
		"blueprint_saved":
			return "Blueprint saved: %s" % String(e["name"])
		"blueprint_loaded":
			return "Blueprint rebuilt %d buildings" % int(e["placed"])
		"reforge":
			return "Core Reforged! +%d shards" % int(e["shards"])
		"shard_node":
			return "%s -> Lv%d" % [String((ReforgeDB.NODES[String(e["id"])] as Dictionary)["name"]), int(e["lvl"])]
		"gear_forge":
			return "Forged a %s %s!" % [String(RarityDB.get_def(String(e["rar"]))["name"]), _gear_name(e)]
		"gear_upgrade":
			if e.has("mw"):
				return ("JACKPOT MASTERWORK! Lv%d" if bool(e.get("jackpot", false)) else "MASTERWORK! Lv%d") % int(e["lvl"])
			return "Upgraded to Lv%d" % int(e["lvl"])
		"gear_merge":
			return "Merged into %s!" % String(RarityDB.get_def(String(e["to"]))["name"])
		"gear_salvage":
			return "Salvaged: +%d Scrap" % int(e["scrap"])
		"gear_imprint":
			return "Perk imprinted"
		"gear_reroll_take":
			return "New perk: %s" % String(AffixDB.get_def(String((e["perk"] as Dictionary)["id"])).get("name", ""))
		"gear_equip":
			return "Equipped %s" % String(Gear.item(save, int(e["uid"])).get("name", ""))
		"core_look":
			return ""
	return ""


## Beam colour of an in-run drop token (rarity is rolled at bank time): a
## cache shows its guaranteed rarity, a loose item white.
func drop_rar(ev: Dictionary) -> String:
	if String(ev.get("kind", "")) == "cache":
		return {"scrap": "common", "field": "uncommon", "elite": "rare", "boss": "epic", "reliquary": "legendary"}.get(String(ev.get("cache", "")), "common")
	return "common"


## A requirement chip's jump (V2 P6): a building that exists -> select it,
## centre the Outpost camera on it and pulse it; one not built yet -> open
## its palette category and flash the entry; a research -> open Research and
## pulse its card.
func jump_to(kind: String, id: String) -> void:
	match kind:
		"bld", "relay":
			set_tab("outpost")
			var uid: String = "relay" if kind == "relay" else OutpostView.uid_of(self, id)
			if uid != "":
				op_sel = uid
				op_pulse = uid
				op_pulse_t = t_anim
				OutpostView.focus_on(self, uid)
			else:
				op_cat = OutpostView.cat_of(id)
				op_arm = ""
				op_flash = id
				op_flash_t = t_anim
		"res":
			set_tab("research")
			res_focus = id
			res_focus_t = t_anim
	_rebuild_ui()


## V2 P8b Auto-Buy switch (run panel): cycles the save's rule and the live run.
func cycle_auto_buy() -> void:
	var mode_ab: String = Labs.cycle_auto_buy(save)
	if S != null:
		S.set_auto_buy(mode_ab)
	_save()
	_rebuild_ui()


## V2 P8b Auto-Restart: the results screen starts the next run after
## Labs.AUTO_RESTART_S unless an overlay (loot reveal, menus) is up.
func auto_restart_left() -> float:
	if screen != "results" or not Labs.auto_restart_on(save):
		return -1.0
	return maxf(0.0, Labs.AUTO_RESTART_S - (t_anim - results_t0))


## Open the casino reveal over this run's banked items (results screen).
func open_loot() -> void:
	var uids: Array = []
	for e in run_loot:
		if String((e as Dictionary).get("t", "")) == "loot_item":
			uids.append(int((e as Dictionary)["uid"]))
	LootReveal.open(self, uids)


func _gear_name(e: Dictionary) -> String:
	var kind: String = String(e.get("kind", "weapon"))
	var base: String = String(e.get("base", ""))
	return String((FrameDB.get_def(base) if kind == "weapon" else ModuleDB.get_def(base)).get("name", base))


## Audio for meta (hub) events: event -> clip only.
func _meta_sfx(ev: Array) -> void:
	for x in ev:
		match String((x as Dictionary)["t"]):
			"lab_done", "build_done", "upgrade_done", "relay_done":
				sfx_play("lab_done")
			"chest_opened", "crate_open":
				sfx_play("card_open")
			"lab_started", "card_slot", "core_level", "part_level", "op_upgrade", "shard_node", "part_equipped":
				sfx_play("upgrade")
			"op_placed", "decor_placed", "op_moved", "plot_open":
				sfx_play("place")
			"tier_unlocked", "set_complete", "core_unlocked", "reforge", "gear_merge":
				sfx_play("levelup")
			"gear_upgrade":
				sfx_play("levelup" if (x as Dictionary).has("mw") else "upgrade")
			"gear_reroll", "gear_lock", "gear_equip", "gear_imprint", "gear_reroll_take":
				sfx_play("upgrade")
			"gear_salvage":
				sfx_play("coin")
			"offline", "mission_claimed", "streak_claimed", "mission_bonus", "collect":
				sfx_play("coin")


func sfx_play(clip: String, pitch: float = -1.0) -> void:
	if sfx != null:
		sfx.play(clip, pitch)


## Volume / mute API: persists in save["settings"] and re-applies to the buses.
func set_audio(key: String, v: Variant) -> void:
	var st: Dictionary = save["settings"]
	st[key] = v
	if sfx != null:
		sfx.apply_settings(st)
	_save()


func toggle_mute() -> void:
	set_audio("mute", not bool((save["settings"] as Dictionary)["mute"]))


func _queue_toasts(ev: Array) -> void:
	for x in ev:
		var s: String = ev_text(x as Dictionary)
		if s != "":
			toast_queue.append(s)


## Run-event -> clip map ("shot" picks shot_<weapon kind>).
const EVENT_CLIP: Dictionary = {
	"kill": "kill", "shield_hit": "hit", "shield_break": "shield_break", "boss": "boss_spawn",
	"boss_bounty": "boss_kill", "wave": "wave_start", "run_start": "wave_start", "wave_skip": "wave_start", "levelup": "levelup",
	"perk_taken": "perk", "placed": "place", "upgraded": "upgrade", "track": "upgrade", "special_cast": "perk",
	"core_hit": "core_hit", "interest": "coin", "revive": "levelup", "dead": "game_over",
	"tier_unlocked": "levelup", "insight_found": "levelup", "draft_offer": "card_open", "ring_open": "levelup",
	"core_attack": "shot_core", "kills": "kill", "core_hits": "core_hit",
}


## Replays engine events as view effects (the view never decides outcomes).
func _handle(events: Array) -> void:
	var rebuild: bool = false
	var ach: Array = Achievements.on_events(save, ach_run, events, now(), float(S.time_alive) if S != null else -1.0)
	if not ach.is_empty():
		_queue_toasts(ach)
	if S != null and screen == "run":
		for x in Missions.on_run_events(save, events):
			if String((x as Dictionary)["t"]) == "mission_done":
				run_missions += 1
				_pop(TowerState.CENTER + Vector2(0, -300), "MISSION COMPLETE", 1.4, GEM, 26)
	for e in events:
		var ev: Dictionary = e
		var et: String = String(ev["t"])
		var clip: String = String(EVENT_CLIP.get(et, ""))
		if et == "shot":
			clip = "shot_" + String(SHOT_CLIP.get(String(ev["kind"]), ev["kind"]))
		if clip != "":
			sfx_play(clip)
		if et == "drop":
			Intel.on_event(self, ev)   # FB2 Loot Drops feed
			_loot_pop(ev)
		elif et == "loot_drop":
			_loot_pop({"kind": "coins", "n": maxi(1, int(round(float(ev.get("coins", 1.0))))), "pos": ev.get("pos", TowerState.CENTER)})
			if String(ev.get("kind", "")) in ["item", "cache"]:
				loot_beams.append({"pos": ev.get("pos", TowerState.CENTER), "rar": drop_rar(ev), "t": 0.0})
				sfx_play("card_open", 1.4)
		match et:
			"shot":
				var kind: String = ev["kind"]
				var col: Color = Color("ffcf6b")
				match kind:
					"tesla":
						col = Color("b48cff")
					"frost":
						col = Color("8fe3ff")
					"railgun":
						col = Color("ff6b6b")
					"flak":
						col = Color("c8f07a")
					_:
						if RunArt.GLYPH.has(kind):
							col = Color(String((RunArt.GLYPH[kind] as Array)[1]))   # V2 P7d weapons
				if kind in ["frost", "pulse", "spike"]:
					_ring(ev["from"], float(ev.get("radius", 60.0)), 0.3, col)
				else:
					_tracer(ev["from"], ev["to"], col, 4.0 if kind in ["mortar", "railgun", "laser", "harpoon"] else 2.0)
				if kind in ["mortar", "missile", "flakburst"] and ev.has("radius"):
					_ring(ev["to"], float(ev.get("radius", 40.0)), 0.3, col if kind != "mortar" else Kit.RUST)
			"core_attack":
				Battle.core_attack_fx(self, ev)
			"dmg":
				_dmg_num(int(ev["eid"]), ev["pos"], float(ev["amt"]))
			"kill":
				var kk: String = String(ev["kind"])
				if bursts != null:
					bursts.call("burst", ev["pos"], kill_color(kk), kk == "boss")
				if gore != null:
					gore.call("kill", ev["pos"], kill_color(kk), kk == "boss", false)   # ground stamp comes from the C# corpse ring
				if kk == "boss":
					juice.hit_pause(0.06)
					juice.add_trauma(0.5)
				_ring(ev["pos"], 18.0, 0.2, ENEMY)
			"core_hit":
				juice.add_trauma(0.22)
				core_flash()
			# HORDE aggregates: one summary per substep.
			"hits":
				for h in ev["top"]:
					var hd: Dictionary = h
					var hp2: Vector2 = hd["pos"]
					# merge popups by 64 px cell, not body: no stacked numbers
					_dmg_num(-1 - (int(floor(hp2.x / 64.0)) * 4096 + int(floor(hp2.y / 64.0))), hp2, float(hd["amt"]))
			"kills":
				var ks: Array = ev["pos_sample"]
				for kp in ks:
					if bursts != null:
						bursts.call("burst", kp, ENEMY, false)
					_ring(kp, 14.0, 0.2, ENEMY)
				if int(ev["n"]) >= 25 and not ks.is_empty():
					# aggregated damage feedback: one kill-count callout per mass kill
					_pop((ks[0] as Vector2) + Vector2(0, -20), "x%d" % int(ev["n"]), 0.7, Color("ffb36b"), mini(34, 16 + int(ev["n"]) / 20))
				if int(ev["n"]) >= 40:
					juice.hit_pause(0.03)   # mass-kill hit-stop (Juice caps + cools it down)
			"core_hits":
				juice.add_trauma(minf(0.4, 0.22 + 0.02 * float(ev["n"])))
				core_flash()
				if int(ev["shots"]) > 0:
					var bo2: Dictionary = bolts.take(0.25)
					bo2["a"] = (ev["pos_sample"] as Array)[0]
			"enemy_shot":
				var bo: Dictionary = bolts.take(0.25)
				bo["a"] = ev["pos"]
				if flash_cd <= 0.0:
					flash = minf(0.2, flash + 0.06)
			"shield_hit":
				_ring(ev["pos"], 26.0, 0.2, SHIELD)
			"shield_break":
				_ring(ev["pos"], 44.0, 0.4, SHIELD)
				_pop(ev["pos"], "BREAK", 0.7, SHIELD, 20)
			"split":
				_ring(ev["pos"], 30.0, 0.3, ENEMY2)
			"interest":
				_pop(TowerState.CENTER + Vector2(0, -44), "+$%d interest" % int(round(float(ev["amt"]))), 1.0, GOLD, 18)
			"boss_bounty":
				Intel.on_event(self, ev)
				_ring(ev["pos"], 120.0, 0.6, GOLD)
				var bt: String = "BOUNTY +%d coins" % int(ev["coins"])
				# Banner sits below the grid (never over cells).
				_pop(TowerState.CENTER + Vector2(0, (float(TowerState.SIDE) * 0.5 + 1.4) * TowerState.CELL), bt, 1.6, GOLD, 24)
			"revive":
				heal_flash = 0.6
				_pop(TowerState.CENTER + Vector2(0, -230), "SECOND WIND!", 1.6, GREEN, 34)
			"wave_skip":
				_pop(TowerState.CENTER + Vector2(0, -260), "WAVE SKIP +%d" % int(ev["skipped"]), 1.4, GEM, 28)
			"wave":
				_pop(TowerState.CENTER + Vector2(0, -300), "WAVE %d" % int(ev["wave"]), 1.4, TEXT, 40)
				rebuild = true
			"run_goal":
				set_overlay("goal")   # §D7 first-run soft goal: keep going or bank
			"wave_clear":
				if float(ev.get("cash", 0.0)) >= 1.0:
					_pop(TowerState.CENTER + Vector2(0, -340), "WAVE %d CLEARED  +$%s" % [int(ev["wave"]), Kit.fmt(float(ev["cash"]))], 1.4, GOLD, 22)
			"part_sea":
				_pop(ev["pos"], "PARTED %d" % int(ev["n"]), 1.2, GEM, 22)
			"boss":
				_pop(TowerState.CENTER + Vector2(0, -250), "BOSS INBOUND", 1.8, ENEMY2, 30)
				juice.add_trauma(0.55)
			"courier_spawn":
				_pop(ev["pos"], "COURIER!", 1.4, GOLD, 22)
			"courier_escape":
				_pop(ev["pos"], "escaped", 1.0, Kit.DIM, 18)
			"elite_marked":
				_ring(ev["pos"], 30.0, 0.5, GOLD)
			"ring_open":
				level_burst = 0.6
				for c in ev["cells"]:
					slot_pop[int(c)] = 0.3
				_pop(TowerState.CENTER + Vector2(0, -270), "RING %d OPEN" % int(ev["ring"]), 1.6, Kit.GREEN, 30)
				rebuild = true
			"insight_found":
				insight_t = 2.4
				insight_name = String(ev.get("name", ""))
				rebuild = true
			"special_cast":
				Battle.special_fx(self, ev)
				rebuild = true
			"orbital_hit":
				_ring(ev["pos"], float(ev["r"]), 0.6, Color("ffd36b"))
				_ring(ev["pos"], float(ev["r"]) * 0.6, 0.4, Color.WHITE)
				juice.add_trauma(0.35)
			"special_ready", "special_slot":
				rebuild = true
			"troop_spawn":
				_ring(ev["pos"], 10.0, 0.25, Kit.GREEN)
			"troop_hit":
				if float(ev.get("aoe", 0.0)) > 0.0:
					_ring(ev["pos"], float(ev["aoe"]), 0.35, Kit.RUST)
			"troop_die":
				_ring(ev["pos"], 14.0, 0.3, Kit.DIM)
			"sapper_blast":
				_ring(ev["pos"], 56.0, 0.45, ENEMY)
				juice.shake(1.0)
			"merged":
				slot_pop[int(ev["slot"])] = 0.45
				level_burst = 0.5
				juice.shake(0.6 + 0.3 * float(int(ev["tier"])))
				sfx_play("click", 0.9 + 0.15 * float(int(ev["tier"])))
				_pop(S.fp_pos(int(ev["slot"])) + Vector2(0, -40), "T%d!" % int(ev["tier"]), 1.2, GOLD, 34)
				rebuild = true
			"merge_offer", "mod_taken", "directive_offer", "draft_lock", "evo_ready":
				rebuild = true
				if String(ev["t"]) == "evo_ready":
					_pop(S.fp_pos(int(ev["slot"])) + Vector2(0, -44), "EVOLUTION READY", 1.6, GOLD, 26)
			"directive_taken":
				_pop(TowerState.CENTER + Vector2(0, -230), String(ev["name"]), 1.6, Kit.MAGENTA, 32)
				juice.shake(0.8)
				rebuild = true
			"evolved":
				_pop(S.fp_pos(int(ev["slot"])) + Vector2(0, -46), String(ev["name"]).to_upper() + "!", 1.8, GOLD, 34)
				juice.shake(1.4)
				level_burst = 0.6
				sfx_play("levelup", 0.8)
				rebuild = true
			"combo_tier":
				# V2 P9 audit: no centre COMBO pop while the Supply Drop panel is up
				if bool(ev["up"]) and int(ev["tier"]) >= 1 and (supply_show.is_empty() or t_anim - supply_t0 > 4.0):
					_pop(TowerState.CENTER + Vector2(0, -200), "COMBO x%.2f" % float(ev["mult"]), 1.0, [Kit.CYAN, Kit.GREEN, GOLD, Kit.MAGENTA][mini(3, int(ev["tier"]) - 1)], 24 + 4 * int(ev["tier"]))
					sfx_play("click", 1.0 + 0.15 * float(int(ev["tier"])))
					if int(ev["tier"]) >= 3:
						juice.shake(0.4 * float(int(ev["tier"])))
			"slot_spin":
				var big: bool = int(ev["mult"]) >= 6
				_pop(S.fp_pos(int(ev["slot"])) + Vector2(0, -34), ("x%d  +$%s" % [int(ev["mult"]), Kit.fmt(float(ev["cash"]))]), 1.3 if big else 0.9, GOLD if big else Kit.GREEN, 26 if big else 18)
				if big:
					sfx_play("coin", 1.3)
			"supply_drop":
				supply_show = ev
				supply_t0 = t_anim
				supply_clicks = 0
				sfx_play("card_open", 1.0)
			"perk_taken":
				_pop(TowerState.CENTER + Vector2(0, -230), String(ev["name"]), 1.4, GOLD, 30)
				rebuild = true
			"pick_applied":
				level_burst = 0.35
				rebuild = true
			"levelup", "perk_offer", "draft_offer", "draft_reroll", "draft_banish", "speed", "mutation_offer", "mutation_taken", "track", "target_mode", "place_cancelled":
				rebuild = true
			"rotated":
				sfx_play("click", 1.15)
				if int(ev["slot"]) >= 0:
					slot_pop[int(ev["slot"])] = 0.15
				rebuild = true
			"placed", "upgraded", "building_level":
				slot_pop[int(ev["slot"])] = 0.3
				rebuild = true
			"place_mode":
				rebuild = true
			"tier_unlocked":
				_queue_toasts([ev])
			"game_over":
				last_breakdown = ev
			"insight_banked", "loot_banked", "loot_item", "cache_open", "loot_salvaged":
				run_loot.append(ev)
			"dead":
				last_result = ev
				screen = "results"
				results_t0 = t_anim
				aim_special = -1
				juice.add_trauma(0.9)
				flash = 0.6
				MetaSave.write(save)
				rebuild = true
	if rebuild:
		_rebuild_ui()


# ----------------------------------------------------------------- input
## Pre-GUI input: device switching, remap capture, mouse tracking, drag
## release, wheel zoom, Outpost pan.
func _input(event: InputEvent) -> void:
	if Keybinds.is_pad(event):
		if last_device != "pad":
			last_device = "pad"
			if event.device >= 0:
				pad_style = Keybinds.pad_style(Input.get_joy_name(event.device))
			_rebuild_ui()
	elif event is InputEventKey or event is InputEventMouseButton:
		if last_device != "kbm":
			last_device = "kbm"
			_rebuild_ui()
	if remap_action != "":
		Desktop.capture_remap(self, event)
		return
	if event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
		if S != null and screen == "run" and bool(S.aim_on) and not pad_aim:
			S.set_aim(s2w(mouse_pos), true)
		if op_pan:
			var dlt: Vector2 = (event as InputEventMouseMotion).relative
			if mouse_pos.distance_to(op_pan_from) > 6.0:
				op_pan_moved = true
			op_cam += dlt
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	mouse_pos = mb.position
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		if aim_down:
			end_aim()
		if bld_drag >= 0:
			_end_bld_drag(mb.position)
		if drag_card >= 0 or op_drag:
			_end_drag(mb.position)
			get_viewport().set_input_as_handled()
		return
	if overlay != "" or screen == "menu":
		return
	if screen == "base" and Hub.is_home(tab) and offline_offer.is_empty() and OutpostView.map_rect(self).has_point(mb.position):
		if OutpostView.mouse(self, mb):
			get_viewport().set_input_as_handled()
		return
	var in_field: bool = screen == "run" and field_rect().has_point(mb.position)
	if not mb.pressed or not in_field:
		return
	match mb.button_index:
		MOUSE_BUTTON_RIGHT:
			if aim_special >= 0:
				aim_special = -1
			elif S != null and S.pending_place != "":
				_handle(S.cancel_place())
			else:
				sel = pick_at(s2w(mb.position))
			_rebuild_ui()
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_UP:
			# V2 P3c: while placing a directional weapon the wheel turns it
			if S != null and S.pending_place != "" and WeaponDB.directional(S.pending_place):
				rotate_weapon(-1)
			else:
				set_zoom(zoom + (-0.1 if bool(_ctl("invert_zoom")) else 0.1))
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if S != null and S.pending_place != "" and WeaponDB.directional(S.pending_place):
				rotate_weapon(1)
			else:
				set_zoom(zoom + (0.1 if bool(_ctl("invert_zoom")) else -0.1))
			get_viewport().set_input_as_handled()


func _ctl(key: String) -> Variant:
	var c: Variant = settings.get("controls", {})
	return (c as Dictionary).get(key, false) if c is Dictionary else false


func set_zoom(z: float) -> void:
	zoom = clampf(snappedf(z, 0.01), 0.8, 1.4)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_F3:
		dbg_overlay = not dbg_overlay
		get_viewport().set_input_as_handled()
		return
	if Desktop.handle_action(self, event):
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var t: int = Time.get_ticks_msec()
	if t - last_tap_ms < 60:
		return
	last_tap_ms = t
	tap_at(mb.position)


## Left click that no button took: run field (aim / place / select).
func tap_at(pos: Vector2) -> void:
	if screen != "run" or overlay != "" or S == null:
		return
	if not field_rect().has_point(pos):
		return
	if aim_special >= 0:
		cast_at(pos)
		return
	var wp: Vector2 = s2w(pos)
	if S.pending_place != "":
		var u: int = pick_at(wp)
		if u >= 0 and S.card_merge_targets(S.pending_place).has(u):
			place_at(u)
			return
		var a: int = place_anchor(wp, S.pending_place)
		if a >= 0:
			place_at(a)
		return
	sel = pick_at(wp)
	if sel >= 0 and S.id_at(sel) != "":
		bld_drag = sel   # V2 P7a: release over a twin merges (_end_bld_drag)
		drag_start = pos
	if sel < 0 or (S.id_at(sel) == "" and not TowerState.is_core_cell(sel)):
		aim_down = true   # held >= AIM_HOLD_S off any building: manual aim (V2 P4)
		aim_t = 0.0
	_rebuild_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and aim_down:
		end_aim()


## V2 P4 manual aim release (mouse up / stick centred): auto-fire resumes.
func end_aim() -> void:
	aim_down = false
	aim_t = 0.0
	if S != null and bool(S.aim_on):
		S.set_aim(s2w(mouse_pos), false)


## Per-frame aim input: the LMB hold timer and the pad's right stick.
func _aim_input(delta: float) -> void:
	if S == null or screen != "run" or overlay != "":
		if aim_down or pad_aim:
			aim_down = false
			pad_aim = false
			if S != null:
				S.set_aim(TowerState.CENTER, false)
		return
	if aim_down:
		# the release event ends the hold (_input: a press captures the mouse,
		# so the release arrives even outside the window; focus loss ends it too)
		aim_t += delta
		if aim_t >= AIM_HOLD_S and not bool(S.aim_on):
			S.set_aim(s2w(mouse_pos), true)
			sel = -1
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > Keybinds.DEADZONE:
		pad_aim = true
		var cw: Dictionary = (S.stats["weapons"] as Array).back()
		S.set_aim(TowerState.CENTER + rs.normalized() * float(cw.get("range", 200.0)) * 0.75, true)
	elif pad_aim:
		pad_aim = false
		S.set_aim(TowerState.CENTER, false)


func begin_drag_card(idx: int) -> void:
	drag_card = idx
	drag_start = mouse_pos


## Drag release: draft card -> grid cell (choose + place); Outpost palette ->
## map (place).
## V2 P7a: a building pressed and released over its same-id, same-tier twin
## merges into the twin.
func _end_bld_drag(pos: Vector2) -> void:
	var a: int = bld_drag
	bld_drag = -1
	if S == null or screen != "run" or pos.distance_to(drag_start) <= 12.0 or not field_rect().has_point(pos):
		return
	var b: int = pick_at(s2w(pos))
	if b >= 0 and S.merge_targets(a).has(b):
		merge_into(a, b)


func _end_drag(pos: Vector2) -> void:
	var card: int = drag_card
	var opd: bool = op_drag
	drag_card = -1
	op_drag = false
	var moved: bool = pos.distance_to(drag_start) > 12.0
	if card >= 0 and screen == "run" and S != null:
		if moved and field_rect().has_point(pos) and card < S.draft.size():
			var cd: Dictionary = S.draft[card]
			# V2 P7a: a duplicate card dropped on its T1 twin merges into it
			var tw: int = pick_at(s2w(pos))
			if tw >= 0 and String(cd.get("kind", "")) == "new" and S.card_merge_targets(String(cd["id"])).has(tw):
				_handle(S.choose_card(card))
				if S.pending_place != "":
					_handle(S.merge_card(tw))
				_rebuild_ui()
				return
			var i: int = place_anchor(s2w(pos), String(cd["id"])) if String(cd.get("kind", "")) == "new" else pick_at(s2w(pos))
			if i >= 0 and String(cd.get("kind", "")) == "new" and Battle.place_reason(self, i, String(cd["id"])) == "":
				_handle(S.choose_card(card))
				if S.pending_place != "":
					_handle(S.place(i))
				_rebuild_ui()
				return
		elif not moved:
			pick_card(card)
			return
	elif opd and screen == "base" and Hub.is_home(tab):
		if moved and OutpostView.map_rect(self).has_point(pos):
			OutpostView.place_at(self, OutpostView.cell_at(self, pos))
			return
	_rebuild_ui()


# ---------------------------------------------------------------- update
## FB2: Core-hit screen flash, capped and rate-limited so a horde gnawing the
## Core every substep pulses gently instead of holding the screen red.
const FLASH_CAP: float = 0.3
const FLASH_CD: float = 0.6


func core_flash() -> void:
	if flash_cd > 0.0:
		return
	flash = minf(FLASH_CAP, flash + 0.18)
	flash_cd = FLASH_CD


## V2 P7c Supply Drop sound: a click per reel stop (rising), then the payout.
func _supply_tick() -> void:
	if supply_show.is_empty():
		return
	var age: float = t_anim - supply_t0
	var stops: Array = Battle.SUPPLY_STOP
	while supply_clicks < 3 and age >= float(stops[supply_clicks]):
		sfx_play("click", 1.0 + 0.2 * float(supply_clicks))
		supply_clicks += 1
	if supply_clicks == 3 and age >= float(stops[2]) + 0.25:
		supply_clicks = 4
		if bool(supply_show.get("jackpot", false)):
			sfx_play("levelup", 1.2)
			juice.shake(2.0)
		else:
			sfx_play("coin", 1.1)
	if age > Battle.SUPPLY_SHOW:
		supply_show = {}


func _process(delta: float) -> void:
	t_anim += delta
	_update_rolls(delta)
	SteamService.tick()
	if S != null and screen == "run":
		SteamService.update_presence("run", int(S.wave), int(S.tier), String(S.mode), float(S.mod_coin))
	else:
		SteamService.update_presence(screen)
	if fade > 0.0:
		fade = maxf(0.0, fade - delta)
		fader.modulate = Color(1, 1, 1, 0.9 * fade / FADE_TIME)
	_aim_input(delta)
	_supply_tick()
	if overlay == "loot":
		LootReveal.tick(self)
	for b in loot_beams:
		(b as Dictionary)["t"] = float((b as Dictionary)["t"]) + delta
	loot_beams = loot_beams.filter(func(b: Variant) -> bool: return float((b as Dictionary)["t"]) < 2.6)
	if screen == "run" and S != null and overlay == "" and not _draft_hold():
		var t0: int = Time.get_ticks_usec()
		var tev: Array = S.tick(juice.engine_delta(delta))
		dbg_sim_ms = lerpf(dbg_sim_ms, float(Time.get_ticks_usec() - t0) / 1000.0, 0.2)
		_handle(tev)
		Intel.poll(self, delta)
		ui_t += delta
		if ui_t >= 0.25 and screen == "run":
			ui_t = 0.0
			_rebuild_ui()   # refresh affordability (buttons fire on PRESS, so safe)
	elif screen == "results" and overlay == "" and auto_restart_left() == 0.0:
		start_run()   # V2 P8b Auto-Restart
	elif screen == "base" and overlay == "" and offline_offer.is_empty():
		poll_t += delta
		if poll_t >= 1.0:
			poll_t = 0.0
			var t: int = now()
			var ev: Array = Labs.claim(save, t)
			ev.append_array(Missions.roll(save, t))
			auto_collect_t += 1.0
			if auto_collect_t >= AUTO_COLLECT_S:
				auto_collect_t = 0.0
				ev.append_array(Outpost.auto_collect(save, t))
			if not ev.is_empty():
				meta_act(ev)
			elif not op_drag and not op_pan:
				_rebuild_ui()   # live timers / affordability
	if toast_t > 0.0:
		toast_t -= delta
	elif not toast_queue.is_empty():
		toast_text = String(toast_queue.pop_front())
		toast_t = 2.4
	tracers.update(delta)
	rings.update(delta)
	pops.update(delta)
	loot_pops.update(delta)
	bolts.update(delta)
	dmgnums.update(delta)
	for k in slot_pop.keys():
		slot_pop[k] = float(slot_pop[k]) - delta
		if float(slot_pop[k]) <= 0.0:
			slot_pop.erase(k)
	juice.update(delta)
	if gore != null:
		if String(gore.get("level")) != gore_level():
			gore.call("set_level", gore_level())
		if S != null and screen == "run":
			# MASS_HORDE §View: exact corpse positions from the C# death ring,
			# drained under the ground layer's per-frame stamp budget
			var cp: PackedFloat32Array = S.en.world.call("DrainCorpses", int(gore.call("stamps_per_frame")))
			gore.call("stamp_packed", cp)
		gore.call("flush")
	if S != null and screen == "run":
		# camera framing: a big horde pulls the view out toward its spawn ring
		var nb: int = S.en.order.size()
		var want: float = clampf(float(nb - 300) / 4000.0, 0.0, 1.0)
		frame_k = move_toward(frame_k, want, delta * (0.35 if want > frame_k else 0.12))
	else:
		frame_k = 0.0
	dbg_fps = Engine.get_frames_per_second()
	flash = maxf(0.0, flash - 1.5 * delta)
	flash_cd = maxf(0.0, flash_cd - delta)
	heal_flash = maxf(0.0, heal_flash - delta)
	level_burst = maxf(0.0, level_burst - delta)
	insight_t = maxf(0.0, insight_t - delta)
	Desktop.update_tip(self, delta)
	queue_redraw()


## Settings > Gameplay "Pause on draft": an open offer freezes engine time
## (otherwise the engine's own 20% slow-mo applies).
func _draft_hold() -> bool:
	if S == null or not bool(((Settings.normalize(settings)["gameplay"]) as Dictionary).get("pause_on_draft", false)):
		return false
	return S.draft.size() > 0 or S.perk_offer.size() > 0 or S.mutation_offer.size() > 0


# -------------------------------------------------------------------- UI
func _rebuild_ui() -> void:
	if ui == null:
		return
	for c in ui.get_children():
		ui.remove_child(c)
		c.queue_free()
	Desktop.build(self)


func _draw() -> void:
	stat_tips = []
	Kit.frame_begin()
	fclip.visible = screen == "run" or screen == "results"
	Kit.bg(self, Rect2(0, 0, vw, vh), t_anim if not _reduce_motion() else 0.0)
	match screen:
		"menu":
			Desktop.draw_menu(self)
		"base":
			Hub.draw(self)
		"run", "results":
			var off: Vector2 = (juice.offset() if shake_on() else Vector2.ZERO) * world_scale()
			if bursts != null:
				bursts.transform = Transform2D(0.0, off - fclip.position) * world_xform()
			if gore != null:
				gore.transform = Transform2D(0.0, off - fclip.position) * world_xform()
			Battle.draw(self, off)
	if screen != "menu":
		Desktop.draw_topbar(self)
	Desktop.draw_overlay(self)
	Desktop.draw_toast(self)
	if dbg_overlay:
		_draw_debug_overlay()


## Top-bar counters: banked amount (+ this run's live coins / scrap).
func roll_targets() -> Dictionary:
	var c: float = float(save.get("coins", 0))
	var sc: float = float(save.get("scrap", 0))
	if screen == "run" and S != null and not S.over:
		c += float(S.coins_run)
		sc += float((S.loot as Dictionary).get("scrap", 0))
	return {"coins": c, "scrap": sc, "shards": float(save.get("shards", 0))}


func _update_rolls(delta: float) -> void:
	if save.is_empty():
		return
	var tg: Dictionary = roll_targets()
	var snap: bool = _reduce_motion() or screen == "menu"
	for k in rolls:
		var r: Roll = rolls[k]
		r.set_target(float(tg[k]), snap)
		r.update(delta)


func _reduce_motion() -> bool:
	var v: Variant = settings.get("video", {})
	return v is Dictionary and bool((v as Dictionary).get("reduce_motion", false))


## Settings > Video "Gore" level (off / low / full; default low).
func gore_level() -> String:
	var v: Variant = settings.get("video", {})
	return String((v as Dictionary).get("gore", "low")) if v is Dictionary else "low"


## Shake honours Settings > Video "Screen shake" (and reduce motion).
func shake_on() -> bool:
	var v: Variant = settings.get("video", {})
	if not (v is Dictionary):
		return true
	return bool((v as Dictionary).get("shake", true)) and not bool((v as Dictionary).get("reduce_motion", false))


## HORDE P6 debug overlay (F3): bodies, FPS, sim ms, hash ms, hash cells.
func debug_stats() -> Dictionary:
	var out: Dictionary = {"bodies": 0, "fps": dbg_fps, "sim_ms": dbg_sim_ms, "render_ms": dbg_render_ms, "frame_ms": 1000.0 / maxf(1.0, dbg_fps), "hash_ms": 0.0, "hash_cells": 0}
	if S != null:
		out["bodies"] = S.en.order.size()
		var cst: Dictionary = S.en.world.call("Stats")
		out["hash_ms"] = float(cst.get("step_us", 0)) / 1000.0   # C# crowd step (move + hash + pressure)
		out["hash_cells"] = int(S.en.world.call("PendingCorpses"))
	return out


func _draw_debug_overlay() -> void:
	var d: Dictionary = debug_stats()
	var lines: Array = ["Bodies  %d" % int(d["bodies"]), "FPS  %d" % int(d["fps"]), "Sim  %.2f ms" % float(d["sim_ms"]), "Render  %.2f ms" % float(d["render_ms"]), "Frame  %.1f ms" % float(d["frame_ms"]),
		"C# step  %.2f ms" % float(d["hash_ms"]), "Corpses pending  %d" % int(d["hash_cells"])]
	if gore != null:
		lines.append("Gore  %s  (%d queued)" % [String(gore.get("level")), int(gore.call("pending"))])
	var fr: Rect2 = field_rect()
	var box: Rect2 = Rect2(fr.position + Vector2(12, 64), Vector2(230, 12 + 24 * lines.size()))
	draw_rect(box, Color(0, 0, 0, 0.72))
	for i in lines.size():
		draw_string(font, box.position + Vector2(10, 28 + 24 * i), String(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("b8f5c8"))
