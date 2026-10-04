extends SceneTree
# Screenshot harness for Corehold (real renderer). Captures the offline modal,
# base / labs / cards / missions tabs, a tier-3 mid-run (wave 15+, mixed
# roster), the perk overlay, the building draft, place mode and results.
#   godot --path games/towerdef-pc-0001/ --script res://_shots.gd -- <outdir>
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const Labs := preload("res://Labs.gd")
const Outpost := preload("res://Outpost.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const TowerState := preload("res://TowerState.gd")
const Bot := preload("res://playtest.gd")
const T0: int = 1800000000
var live_S = null   # run kept alive between staged shots (null before the death shot)

## Mobile 5x5 cell index -> the same cell on the PC 7x7 board (r+1, c+1).
func _c(i5: int) -> int:
	return BaseMeta.idx5_to_7(i5)


func _initialize() -> void:
	var uargs := OS.get_cmdline_user_args()
	var outdir: String = uargs[0] if uargs.size() > 0 else "shots"
	MetaSave.clear()
	DirAccess.make_dir_recursive_absolute(outdir)
	var main: Node = load("res://Main.tscn").instantiate()
	get_root().add_child(main)
	await _wait(10)
	await _shot("%s/00_menu.png" % outdir)
	var save: Dictionary = BaseMeta.default_save()
	save["coins"] = 400
	Bot.spend_meta(save, "balanced")
	save["coins"] = 1370
	save["gems"] = 64
	save["best_wave_by_tier"] = {"1": 40, "2": 50}
	save["best_wave"] = 50
	save["tier"] = 3
	save["runs"] = 6
	# The away modal shows what the Outpost stored (a Coin Mill ran 3 h).
	save["coins"] = 2000
	Outpost.place(save, "mill", 4, 4, 0, T0 - 3 * 3600 - 200)
	Outpost.tick(save, T0 - 3 * 3600)
	save["coins"] = 1370
	save["last_seen"] = T0 - 3 * 3600
	save["research"]["lvls"]["speed"] = 2
	main.now_override = T0
	main.boot(save, T0)
	await _shot("%s/0_offline.png" % outdir)
	main.claim_offline(false)
	main.toast_queue.clear()
	main.toast_t = 0.0
	main.sel = _c(7)
	main._rebuild_ui()
	await _shot("%s/1_base.png" % outdir)
	# PC desktop screens: tooltip, drag ghost (valid + invalid), info popover,
	# settings tabs + remap capture, mode select, stats / history / awards.
	main.mouse_pos = main.w2s(TowerState.slot_pos(_c(7)))
	main.settings["controls"]["tooltip_delay"] = 0.0
	await _shot("%s/1g_tooltip.png" % outdir)
	main.begin_drag_building("gun")
	main.drag_start = Vector2(960, 1040)
	var free_cell: int = -1
	for i in TowerState.N:
		if free_cell < 0 and i != TowerState.CORE_SLOT and BaseMeta.is_unlocked(main.save, i) and BaseMeta.slot_of(main.save, i).is_empty():
			free_cell = i
	if free_cell < 0:
		free_cell = _c(13)
		BaseMeta.demolish(main.save, free_cell)
		main._rebuild_ui()
	main.mouse_pos = main.w2s(TowerState.slot_pos(free_cell))
	await _shot("%s/1h_drag_valid.png" % outdir)
	main.mouse_pos = main.w2s(TowerState.slot_pos(0))
	await _shot("%s/1i_drag_invalid.png" % outdir)
	main.drag_id = ""
	main.mouse_pos = Vector2(-1, -1)
	main.open_info(_c(7))
	await _shot("%s/1j_info.png" % outdir)
	for tb in ["video", "audio", "controls", "gameplay"]:
		main.set_tab_id = tb
		main.set_overlay("settings")
		await _shot("%s/1k_settings_%s.png" % [outdir, tb])
	main.set_tab_id = "controls"
	main.set_overlay("settings")
	main.remap_action = "upgrade"
	main._rebuild_ui()
	await _shot("%s/1l_remap.png" % outdir)
	main.remap_action = ""
	main.run_opts = {"mode": "endless", "modifiers": ["swarm", "haste"]}
	main.set_overlay("modes")
	await _shot("%s/1m_modes.png" % outdir)
	main.run_opts = {"mode": "normal", "modifiers": []}
	var hist: Array = []
	for k in 8:
		hist.append({"seed": 1000 + k * 37, "tier": 1 + k % 3, "mode": "endless" if k == 3 else "normal", "modifiers": ["swarm"] if k == 5 else [], "wave": 12 + k * 5, "coins": 300 + k * 140, "duration_s": 600.0 + k * 90.0, "build": [], "perks": [], "ts": T0 - k * 3600})
	main.save["history"] = hist
	main.save["stats"]["kills"] = 18450
	main.save["stats"]["runs"] = 8
	main.save["stats"]["waves"] = 260
	main.save["stats"]["bosses"] = 21
	main.save["stats"]["kills_by_kind"] = {"drone": 9000, "skitter": 5200, "hauler": 2100, "elite": 900, "boss": 21}
	main.save["stats"]["placed"] = {"gun": 30, "mine": 22, "tesla": 12}
	main.save["achievements"] = {"unlocked": {"ACH_FIRST_RUN": T0, "ACH_WAVE_25": T0, "ACH_FIRST_BOSS": T0}, "missions_claimed": 0}
	for ov in ["stats", "history", "achievements"]:
		main.set_overlay(ov)
		await _shot("%s/1n_%s.png" % [outdir, ov])
	main.set_overlay("")
	var s: Dictionary = main.save
	Labs.start(s, "dmg", T0 - 120)
	Labs.start(s, "coin", T0 - 30)
	main.set_tab("labs")
	await _shot("%s/1b_labs.png" % outdir)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	s["gems"] = 200
	for k in 9:
		Cards.open_chest(s, rng)
	for id in Cards.owned(s).keys().slice(0, 2):
		Cards.equip(s, String(id))
	main.toast_queue.clear()
	main.set_tab("cards")
	await _shot("%s/1c_cards.png" % outdir)
	var lst: Array = Missions.list(s)
	(lst[0] as Dictionary)["prog"] = int((lst[0] as Dictionary)["target"])
	(lst[1] as Dictionary)["prog"] = int((lst[1] as Dictionary)["target"]) / 2
	main.set_tab("missions")
	await _shot("%s/1d_missions.png" % outdir)
	main.set_tab("base")
	main.set_overlay("options")
	await _shot("%s/1e_options.png" % outdir)
	main.set_overlay("credits")
	await _shot("%s/1f_credits.png" % outdir)
	main.set_overlay("")
	main.start_run()
	var S = main.S
	live_S = S
	for k in 6000:
		S.tick(0.1)
		S.hp = float(S.stats["max_hp"])
		if k % 5 == 0:
			Bot.bot_step(S, "balanced")
		if S.wave >= 16 and S.enemies.size() > 14 and S.draft.is_empty() and S.perk_offer.is_empty() and S.pending_place == "":
			break
	main.sel = -1
	main._rebuild_ui()
	await _wait(20)
	await _shot("%s/2_run.png" % outdir)
	main.set_overlay("pause")
	await _shot("%s/2p_pause.png" % outdir)
	main.set_overlay("")
	# Boss bounty banner (below the grid) + the core's Overcharge button.
	main.sel = TowerState.CORE_SLOT
	main._rebuild_ui()
	main._handle([{"t": "boss_bounty", "coins": 120, "gems": 2, "pos": TowerState.CENTER + Vector2(40, 30)}])
	await _wait(4)
	await _shot("%s/2c_bounty.png" % outdir)
	# Midgame juice: weapon selected (Target button), live damage numbers,
	# hit flashes and pooled kill bursts from real engine events.
	main.sel = _c(7) if S.is_weapon_slot(_c(7)) else TowerState.CORE_SLOT
	main._rebuild_ui()
	for e in S.enemies:
		(e as Dictionary)["hp"] = minf(float((e as Dictionary)["hp"]), 30.0)
	await _wait(9)
	await _shot("%s/2j_juice.png" % outdir)
	main.sel = -1
	main._rebuild_ui()
	S.perk_pending = 1
	S.hp = float(S.stats["max_hp"])
	await _wait(6)
	await _shot("%s/2b_perk.png" % outdir)
	S.choose_perk(0)
	S.rerolls_left = 1
	S.xp = S.xp_need()
	S.hp = float(S.stats["max_hp"])
	await _wait(6)
	main._rebuild_ui()
	await _wait(2)
	await _shot("%s/3_draft.png" % outdir)
	S.choose_card(0)
	main._rebuild_ui()
	await _wait(6)
	await _shot("%s/4_place.png" % outdir)
	if S.pending_place != "":
		S.cancel_place()
	S.wave = 50
	S.next_plan = S._build_plan(51, 3.0)
	S.mode = "endless"
	S.mutation_offer = ["m_vigor", "m_rush", "m_horde"]
	main._rebuild_ui()
	await _wait(4)
	await _shot("%s/4m_mutation_telegraph.png" % outdir)
	S.mutation_offer = []
	live_S = null
	S.wind_used = true
	S.hp = -1.0
	S.stats["regen"] = 0.0
	await _wait(30)
	await _shot("%s/5_results.png" % outdir)
	main.go_menu()
	main.confirm_del = 1
	main._rebuild_ui()
	await _shot("%s/6_slots_delete.png" % outdir)
	MetaSave.clear()
	quit(0)

func _wait(n: int) -> void:
	for k in n:
		if live_S != null and not live_S.over:
			live_S.hp = float(live_S.stats["max_hp"])
		await process_frame

func _shot(path: String) -> void:
	# xvfb/opengl3 presents a few frames late; give the view time to catch up.
	await _wait(16)
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("shot ", path)
