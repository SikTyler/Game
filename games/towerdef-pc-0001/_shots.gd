extends SceneTree
# Screenshot harness for Corehold (real renderer). Captures the offline modal,
# base / labs / cards / missions tabs, a tier-3 mid-run (wave 15+, mixed
# roster), the perk overlay, the building draft, place mode and results.
#   godot --path games/towerdef-pc-0001/ --script res://_shots.gd -- <outdir>
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const Labs := preload("res://Labs.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const TowerState := preload("res://TowerState.gd")
const Bot := preload("res://playtest.gd")
const T0: int = 1800000000

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
	var save: Dictionary = BaseMeta.default_save()
	save["coins"] = 400
	Bot.spend_meta(save, "balanced")
	save["coins"] = 1370
	save["gems"] = 64
	save["best_wave_by_tier"] = {"1": 40, "2": 50}
	save["best_wave"] = 50
	save["tier"] = 3
	save["runs"] = 6
	save["last_seen"] = T0 - 3 * 3600
	save["best_coin_rate"] = 12.0
	save["labs"]["lvls"]["speed"] = 2
	main.now_override = T0
	main.boot(save, T0)
	await _shot("%s/0_offline.png" % outdir)
	main.claim_offline(false)
	main.toast_queue.clear()
	main.toast_t = 0.0
	main.sel = _c(7)
	main._rebuild_ui()
	await _shot("%s/1_base.png" % outdir)
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
	await _wait(6)
	await _shot("%s/2b_perk.png" % outdir)
	S.choose_perk(0)
	S.rerolls_left = 1
	S.xp = S.xp_need()
	await _wait(6)
	main._rebuild_ui()
	await _wait(2)
	await _shot("%s/3_draft.png" % outdir)
	S.choose_card(0)
	main._rebuild_ui()
	await _wait(6)
	await _shot("%s/4_place.png" % outdir)
	S.wind_used = true
	S.hp = -1.0
	S.stats["regen"] = 0.0
	await _wait(30)
	await _shot("%s/5_results.png" % outdir)
	MetaSave.clear()
	quit(0)

func _wait(n: int) -> void:
	for k in n:
		await process_frame

func _shot(path: String) -> void:
	# xvfb/opengl3 presents a few frames late; give the view time to catch up.
	await _wait(16)
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("shot ", path)
