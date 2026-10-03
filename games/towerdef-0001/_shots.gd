extends SceneTree
# Screenshot harness for Corehold (real renderer). Captures base, mid-run,
# level-up draft and results.
#   godot --path games/towerdef-0001/ --script res://_shots.gd -- <outdir>
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const Bot := preload("res://playtest.gd")

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
	save["coins"] = 137
	main.save = save
	main.sel = 7
	main._rebuild_ui()
	await _shot("%s/1_base.png" % outdir)
	main.start_run()
	var S = main.S
	for k in 1500:
		S.tick(0.1)
		if k % 5 == 0:
			Bot.bot_step(S, "balanced")
	main.sel = -1
	main._rebuild_ui()
	await _wait(20)
	await _shot("%s/2_run.png" % outdir)
	S.xp = S.xp_need()
	await _wait(6)
	await _shot("%s/3_draft.png" % outdir)
	S.choose_card(0)
	main._rebuild_ui()
	await _wait(6)
	await _shot("%s/4_place.png" % outdir)
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
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("shot ", path)
