extends SceneTree
# Screenshot harness for Corehold PC (real renderer, native 1920x1080 view).
# Captures every screen: menu, away modal, hub tabs (Play, Core Bay, Crates +
# reveal, Outpost new / developed / hover / plot, Research, Cards, Missions,
# Reforge + confirm), settings / remap / modes / records, and the run (early
# battle, draft, Insight draft, place mode, late battle, aim, pause, results)
# plus 1280x720 checks.
#   godot --path games/towerdef-pc-0001/ --script res://_shots.gd -- <outdir>
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const Labs := preload("res://Labs.gd")
const Outpost := preload("res://Outpost.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const Parts := preload("res://Parts.gd")
const Cores := preload("res://Cores.gd")
const Crates := preload("res://Crates.gd")
const Reforge := preload("res://Reforge.gd")
const TowerState := preload("res://TowerState.gd")
const PartDB := preload("res://data/PartDB.gd")
const Bot := preload("res://playtest.gd")
const T0: int = 1800000000
var live_S = null   # run kept alive between staged shots
var main: Node = null


func _initialize() -> void:
	var uargs := OS.get_cmdline_user_args()
	var outdir: String = uargs[0] if uargs.size() > 0 else "shots"
	MetaSave.clear()
	DirAccess.make_dir_recursive_absolute(outdir)
	main = load("res://Main.tscn").instantiate()
	get_root().add_child(main)
	await _wait(10)
	main.settings["controls"]["tooltip_delay"] = 0.0
	await _shot("%s/00_menu.png" % outdir)
	# ---- a mid-game save: Outpost started, a Mill ran 3 h while away
	var save: Dictionary = BaseMeta.default_save()
	save["coins"] = 60000
	save["scrap"] = 900
	save["keys"] = 3
	save["core_cores"] = 6
	save["best_wave_by_tier"] = {"1": 42, "2": 31}
	save["best_wave"] = 42
	save["tier"] = 2
	save["runs"] = 14
	Outpost.place(save, "mill", 4, 4, 0, T0 - 3 * 3600 - 200)
	Outpost.tick(save, T0 - 3 * 3600)
	save["last_seen"] = T0 - 3 * 3600
	save["research"]["lvls"]["speed"] = 2
	main.now_override = T0
	main.boot(save, T0)
	await _shot("%s/01_offline.png" % outdir)
	main.claim_offline()
	_quiet()
	var s: Dictionary = main.save
	# Core levels + parts for the bay
	(s["cores"]["levels"] as Dictionary)["bastion"] = 13
	(s["cores"]["owned"] as Array).append("foundry")
	(s["cores"]["levels"] as Dictionary)["foundry"] = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for id in ["f_plating", "f_bulkhead", "f_regenmesh", "b_longbore", "b_bounty", "c_interest", "c_scope", "e_bastionheart", "e_dynamo", "f_lightweave", "b_scatter", "c_battery", "e_railcore", "f_mirror", "b_hollow", "c_quickcap", "e_turbine", "f_ledgerframe"]:
		if PartDB.has(id):
			Parts.grant(s, id, "shots")
	Parts.grant(s, "f_plating", "shots")
	for id in ["f_bulkhead", "b_longbore", "e_bastionheart", "f_regenmesh"]:
		var uid: String = Parts.uid_of(s, id)
		if uid != "":
			var k: int = -1
			for j in Parts.N_SLOTS:
				if k < 0 and Parts.slot_open(13, j) and Parts.fits(s, uid, j) and String(Parts.preset(s, "bastion")[j]) == "":
					k = j
			if k >= 0:
				Parts.equip(s, "bastion", k, uid)
	(Parts.item(s, Parts.uid_of(s, "f_bulkhead")) as Dictionary)["lvl"] = 4
	_quiet()
	main.set_tab("play")
	await _shot("%s/02_play.png" % outdir)
	main.set_tab("bay")
	main.bay_part = Parts.uid_of(s, "f_plating")
	main._rebuild_ui()
	await _shot("%s/03_bay.png" % outdir)
	main.drag_part = Parts.uid_of(s, "c_scope")
	main.drag_start = Vector2(100, 100)
	main.mouse_pos = load("res://ui/CoreBay.gd").slot_pos(main, 2)
	await _shot("%s/03b_bay_drag.png" % outdir)
	main.drag_part = ""
	main.bay_core = "tempest"
	main.bay_part = ""
	main._rebuild_ui()
	await _shot("%s/03c_bay_locked.png" % outdir)
	main.bay_core = "bastion"
	# crates
	_quiet()
	main.set_tab("crates")
	await _shot("%s/04_crates.png" % outdir)
	main.meta_rng.seed = 77
	s["keys"] = 8
	load("res://ui/CrateView.gd").open(main, "vault", "keys")
	main.crate_anim["t"] = 1.55
	_quiet()
	await _shot("%s/04b_crate_open.png" % outdir, false)
	main.crate_anim["t"] = 9.0
	main._rebuild_ui()
	await _shot("%s/04c_crate_done.png" % outdir)
	main.crate_anim = {}
	# outpost: fresh (just the Mill + Hall), then developed
	main.set_tab("outpost")
	await _shot("%s/05_outpost_new.png" % outdir)
	main.op_arm = "mill"
	main.mouse_pos = load("res://ui/OutpostView.gd").cell_rect(main, 4, 6).get_center()
	await _shot("%s/05c_outpost_hover.png" % outdir)
	main.op_arm = ""
	s["coins"] = 400000
	for k in 3:
		Outpost.unlock_plot(s, k, "coins")
	var t: int = T0
	for k in 10:
		Bot.outpost_spend(s, t)
		t += 3 * 3600
		Outpost.tick(s, t)
	for dc in [["dc_lamp", 0, 6], ["dc_tree", 5, 2], ["dc_bookshelf", 3, 2], ["dc_shrub", 5, 7], ["dc_banner", 0, 3]]:
		Outpost.place_decor(s, String(dc[0]), int(dc[1]), int(dc[2]), 0)
	main.now_override = t
	Outpost.tick(s, t + 7200)
	main.now_override = t + 7200
	s["coins"] = 52000
	_quiet()
	main.op_sel = ""
	for uid in (s["outpost"]["buildings"] as Dictionary).keys():
		if String((s["outpost"]["buildings"][uid] as Dictionary)["id"]) == "mill":
			main.op_sel = String(uid)
	main._rebuild_ui()
	await _shot("%s/05b_outpost_dev.png" % outdir)
	# corner toast (achievement / missions banner) over the Outpost map
	main.toast_text = "Achievement: Outpost Builder  (+500 coins)"
	main.toast_t = 30.0
	main.queue_redraw()
	await _shot("%s/05f_outpost_toast.png" % outdir, false)
	_quiet()
	main.op_sel = "plot:3"
	main._rebuild_ui()
	await _shot("%s/05d_outpost_plot.png" % outdir)
	main.op_sel = ""
	main.op_arm = "conduit"
	main.mouse_pos = load("res://ui/OutpostView.gd").cell_rect(main, 7, 3).get_center()
	main._rebuild_ui()
	await _shot("%s/05e_outpost_conduit.png" % outdir)
	main.op_arm = ""
	# research / cards / missions
	Labs.start(s, "dmg", main.now_override - 120)
	_quiet()
	main.set_tab("research")
	await _shot("%s/06_research.png" % outdir)
	s["coins"] = int(s["coins"]) + 4000
	for k in 9:
		Cards.open_chest(s, rng)
	for id in Cards.owned(s).keys().slice(0, 2):
		Cards.equip(s, String(id))
	_quiet()
	main.set_tab("cards")
	await _shot("%s/07_cards.png" % outdir)
	var lst: Array = Missions.list(s)
	(lst[0] as Dictionary)["prog"] = int((lst[0] as Dictionary)["target"])
	(lst[1] as Dictionary)["prog"] = int((lst[1] as Dictionary)["target"]) / 2
	main.set_tab("missions")
	await _shot("%s/08_missions.png" % outdir)
	# reforge
	s["reforge"]["coins_since"] = 1600000
	s["shards"] = 14
	Reforge.buy(s, "root_forge")
	Reforge.buy(s, "might")
	Reforge.buy(s, "prosperity")
	main.set_tab("reforge")
	await _shot("%s/09_reforge.png" % outdir)
	main.rf_confirm = 1
	main._rebuild_ui()
	await _shot("%s/09b_reforge_confirm.png" % outdir)
	main.rf_confirm = 0
	# overlays
	for tb in ["video", "controls"]:
		main.set_tab_id = tb
		main.set_overlay("settings")
		await _shot("%s/10_settings_%s.png" % [outdir, tb])
	main.remap_action = "upgrade"
	main._rebuild_ui()
	await _shot("%s/10b_remap.png" % outdir)
	main.remap_action = ""
	main.run_opts = {"mode": "normal", "modifiers": ["swarm", "haste"]}
	main.set_overlay("modes")
	await _shot("%s/11_modes.png" % outdir)
	main.run_opts = {"mode": "normal", "modifiers": []}
	var hist: Array = []
	for k in 8:
		hist.append({"seed": 1000 + k * 37, "tier": 1 + k % 3, "mode": "endless" if k == 3 else "normal", "modifiers": ["swarm"] if k == 5 else [], "wave": 12 + k * 5, "coins": 300 + k * 140, "duration_s": 600.0 + k * 90.0, "build": [], "perks": [], "ts": T0 - k * 3600})
	s["history"] = hist
	s["stats"]["runs"] = 8
	s["stats"]["kills"] = 18450
	s["stats"]["kills_by_kind"] = {"drone": 9000, "skitter": 5200, "hauler": 2100, "elite": 900, "boss": 21}
	s["achievements"] = {"unlocked": {"ACH_FIRST_RUN": T0, "ACH_WAVE_25": T0, "ACH_FIRST_BOSS": T0, "ACH_FIRST_PART": T0}, "missions_claimed": 0}
	for ov in ["stats", "history", "achievements"]:
		main.set_overlay(ov)
		await _shot("%s/12_%s.png" % [outdir, ov])
	main.set_overlay("")
	# ---- the run
	main.view_tier = 1
	main.start_run(4242)
	var S = main.S
	live_S = S
	for k in 4000:
		S.tick(0.1)
		S.hp = float(S.stats["max_hp"])
		if k % 5 == 0:
			Bot.bot_step(S, "balanced")
		if S.wave >= 4 and S.enemy_count() > 6 and S.draft.is_empty() and S.pending_place == "":
			break
	main.sel = -1
	_quiet()
	main._rebuild_ui()
	await _wait(12)
	await _shot("%s/13_battle_early.png" % outdir)
	S.grant_draft()
	main._rebuild_ui()
	await _wait(3)
	await _shot("%s/14_draft.png" % outdir)
	S.draft[1] = {"id": "in_dmg", "fam": "insight", "rarity": "insight", "kind": "insight", "tags": []}
	main.insight_t = 2.2
	main.insight_name = "Insight: Force"
	main._rebuild_ui()
	await _wait(2)
	await _shot("%s/14b_draft_insight.png" % outdir, false)
	main.insight_t = 0.0
	var placed: bool = false
	for k in S.draft.size():
		if not placed and String((S.draft[k] as Dictionary).get("kind", "")) == "new":
			main._handle(S.choose_card(k))
			placed = true
	if not placed:
		S.draft.clear()
		S.pending_place = "gun"
	main._rebuild_ui()
	await _wait(3)
	await _shot("%s/15_place.png" % outdir)
	if S.pending_place != "":
		main._handle(S.cancel_place())
	for k in 9000:
		S.tick(0.1)
		S.hp = float(S.stats["max_hp"])
		if k % 4 == 0:
			Bot.bot_step(S, "balanced")
		if S.wave >= 22 and S.enemy_count() > 16 and S.draft.is_empty() and S.pending_place == "" and S.perk_offer.is_empty():
			break
	main.sel = TowerState.CORE_SLOT
	_quiet()
	main._rebuild_ui()
	await _wait(14)
	await _shot("%s/16_battle_late.png" % outdir)
	main.sel = -1
	var orb: int = -1
	for k in S.specials.size():
		if String((S.specials[k] as Dictionary)["id"]) == "sp_orbital":
			orb = k
	if orb < 0:
		load("res://Specials.gd").take(S.specials, "sp_orbital", 3 if S.specials.size() >= 4 else -1)
		orb = load("res://Specials.gd").find(S.specials, "sp_orbital")
	(S.specials[orb] as Dictionary)["cd"] = 0.0
	main.aim_special = orb
	main.mouse_pos = main.w2s(TowerState.CENTER + Vector2(160, -120))
	main._rebuild_ui()
	await _wait(3)
	await _shot("%s/16b_aim.png" % outdir)
	main.aim_special = -1
	main.set_overlay("pause")
	await _shot("%s/17_pause.png" % outdir)
	main.set_overlay("")
	# 1280x720 check of the run
	get_root().size = Vector2i(1280, 720)
	await _wait(6)
	await _shot("%s/20_720p_battle.png" % outdir)
	get_root().size = Vector2i(1920, 1080)
	await _wait(6)
	live_S = null
	S.wind_used = true
	S.hp = -1.0
	S.stats["regen"] = 0.0
	await _wait(30)
	await _shot("%s/18_results.png" % outdir)
	main.go_base()
	main.set_tab("outpost")
	get_root().size = Vector2i(1280, 720)
	await _wait(6)
	await _shot("%s/20b_720p_outpost.png" % outdir)
	main.set_tab("bay")
	await _shot("%s/20c_720p_bay.png" % outdir)
	get_root().size = Vector2i(1920, 1080)
	await _wait(6)
	main.go_menu()
	main.confirm_del = 1
	main._rebuild_ui()
	await _shot("%s/19_menu_delete.png" % outdir)
	MetaSave.clear()
	quit(0)


func _quiet() -> void:
	main.mouse_pos = Vector2(-1, -1)
	main.toast_queue.clear()
	main.toast_t = 0.0


func _wait(n: int) -> void:
	for k in n:
		if live_S != null and not live_S.over:
			live_S.hp = float(live_S.stats["max_hp"])
		await process_frame


func _shot(path: String, settle: bool = true) -> void:
	# xvfb/opengl3 presents a few frames late; give the view time to catch up.
	if settle:
		await _wait(16)
	else:
		await _wait(3)
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("shot ", path)
