extends SceneTree
# Screenshot harness for Corehold PC (real renderer, native 1920x1080 view).
# Captures every screen: menu, away modal, hub tabs (Outpost home new /
# developed / armed ghost / plot, Core, Research, Missions, Reforge +
# confirm), settings / remap / modes / records, and the run (early battle,
# draft, Insight draft, place mode, late battle, aim, pause, results) plus
# 1280x720 checks.
#   godot --path games/towerdef-pc-0001/ --script res://_shots.gd -- <outdir>
# Headless containers: xvfb-run -a -s "-screen 0 1920x1080x24" <godot>
#   --path . --rendering-method gl_compatibility --rendering-driver opengl3
#   --script res://_shots.gd -- <outdir>
const BaseMeta := preload("res://BaseMeta.gd")
const MetaSave := preload("res://MetaSave.gd")
const Labs := preload("res://Labs.gd")
const Outpost := preload("res://Outpost.gd")
const Missions := preload("res://Missions.gd")
const Cores := preload("res://Cores.gd")
const Reforge := preload("res://Reforge.gd")
const TowerState := preload("res://TowerState.gd")
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
	save["best_wave_by_tier"] = {"1": 42, "2": 31}
	save["best_wave"] = 42
	save["tier"] = 2
	save["runs"] = 14
	save["core"]["lvl"] = 13
	Outpost.place(save, "mill", 7, 8, 0, T0 - 3 * 3600 - 200)
	Outpost.tick(save, T0 - 3 * 3600)
	save["last_seen"] = T0 - 3 * 3600
	save["research"]["lvls"]["speed"] = 2
	main.now_override = T0
	main.boot(save, T0)
	await _shot("%s/01_offline.png" % outdir)
	main.claim_offline()
	_quiet()
	var s: Dictionary = main.save
	main.set_tab("play")
	await _shot("%s/02_home_outpost.png" % outdir)
	# V2 P4 gear: a varied inventory (seeded drops), an Epic weapon and modules equipped
	var GR = load("res://Gear.gd")
	var GG = load("res://GearGen.gd")
	var rr := RandomNumberGenerator.new()
	rr.seed = 4242
	var best: int = 0
	for k in 26:
		var it: Dictionary = GG.roll(rr, "drop", {"ilvl": 70, "luck": 6.0}, {})
		it["lvl"] = 1 + (k * 7) % 14
		it["mw"] = int(it["lvl"]) / 5
		var u: int = GR.add_item(s, it)
		if String(it["kind"]) == "weapon" and (best == 0 or load("res://data/RarityDB.gd").rank(String(it["rar"])) > load("res://data/RarityDB.gd").rank(String(GR.item(s, best)["rar"]))):
			best = u
	GR.equip(s, best)
	var socks: int = 0
	for u in GR.uids(s, "module"):
		if socks < GR.sockets_for(Cores.level(s)):
			GR.equip(s, int(u))
			socks += 1
	Cores.set_look(s, "shell", 5)
	Cores.set_look(s, "trim", 2)
	main.set_tab("core")
	await _shot("%s/03_core.png" % outdir)
	main.core_tab = "look"
	main._rebuild_ui()
	await _shot("%s/03b_core_look.png" % outdir)
	main.core_tab = "loadout"
	main.core_sock = 1
	main._rebuild_ui()
	main.set_tab("forge")
	main.forge_sel = best
	main._rebuild_ui()
	await _shot("%s/04_forge.png" % outdir)
	s["scrap"] = 5000
	GR.reroll(s, best, 0)
	main._rebuild_ui()
	await _shot("%s/04b_forge_reroll.png" % outdir)
	GR.reroll_choose(s, -1)
	main.forge_kind = "module"
	main.forge_filter = "module"
	main.forge_sel = int(GR.uids(s, "module")[0])
	main._rebuild_ui()
	await _shot("%s/04c_forge_modules.png" % outdir)
	main.forge_kind = "weapon"
	main.forge_filter = "all"
	main.core_sock = -1
	# Outpost: developed (the bot's build plan over a few sessions), armed ghost, plot
	s["coins"] = 400000
	var t: int = T0
	for k in 10:
		Bot.outpost_spend(s, t)
		t += 3 * 3600
	Outpost.tick(s, t)
	main.now_override = t
	s["coins"] = 52000
	_quiet()
	main.set_tab("outpost")
	await _shot("%s/05_outpost_dev.png" % outdir)
	var OV = load("res://ui/OutpostView.gd")
	main.op_arm = "mill"
	main.mouse_pos = OV.cell_rect(main, 8, 8).get_center()
	main._rebuild_ui()
	await _shot("%s/05b_outpost_ghost.png" % outdir, false)
	main.op_arm = ""
	main.op_sel = "plot:1"
	main.mouse_pos = Vector2(-1, -1)
	main._rebuild_ui()
	await _shot("%s/05c_outpost_plot.png" % outdir)
	main.op_sel = ""
	# research / missions
	Labs.start(s, "dmg", main.now_override - 120)
	_quiet()
	main.set_tab("research")
	await _shot("%s/06_research.png" % outdir)
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
	s["achievements"] = {"unlocked": {"ACH_FIRST_RUN": T0, "ACH_WAVE_25": T0, "ACH_FIRST_BOSS": T0, "ACH_COURIER": T0}, "missions_claimed": 0}
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
	# FEEDBACK-1: cursor over a free cell -> building preview + range radius
	for i in TowerState.N:
		if S.pending_place != "" and S.in_grid(i) and bool(S.unlocked[i]) and S.id_at(i) == "" and S.can_place(i, S.pending_place):
			main.mouse_pos = main.w2s(TowerState.slot_pos(i))
			break
	main._rebuild_ui()
	await _wait(3)
	await _shot("%s/15_place.png" % outdir)
	if S.pending_place != "":
		main._handle(S.cancel_place())
	# V2 P3c: placing a directional weapon shows its facing wedge / lane
	for pid in ["gun", "flak"]:
		S.pending_place = String(pid)
		S.pending_rot = -1
		for i in TowerState.N:
			if S.can_place(i, S.pending_place) and TowerState.ring_of(i) >= 2:
				main.mouse_pos = main.w2s(TowerState.fp_center(i, TowerState.size_of(S.pending_place)))
				break
		main._rebuild_ui()
		await _wait(3)
		await _shot("%s/15b_place_%s.png" % [outdir, String(pid)])
		main._handle(S.cancel_place())
	for k in 9000:
		S.tick(0.1)
		S.hp = float(S.stats["max_hp"])
		if k % 4 == 0:
			Bot.bot_step(S, "balanced")
		if S.wave >= 22 and S.enemy_count() > 16 and S.draft.is_empty() and S.pending_place == "" and S.perk_offer.is_empty():
			break
	main.sel = TowerState.CORE_SLOT
	for i in TowerState.N:   # FEEDBACK-1: a selected building shows its range
		if i != TowerState.CORE_SLOT and S.is_weapon_slot(i) and S.id_at(i) != "":
			main.sel = i
			break
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
	# V2 P4 manual aim: reticle + focus ring, the turret on the cursor
	S.set_aim(TowerState.CENTER + Vector2(-170, 90), true)
	S.focus = 0.7
	main._rebuild_ui()
	await _wait(8)
	await _shot("%s/16c_manual_aim.png" % outdir)
	S.set_aim(TowerState.CENTER, false)
	main.set_overlay("pause")
	await _shot("%s/17_pause.png" % outdir)
	main.set_overlay("")
	# 1280x720 check of the run
	get_root().size = Vector2i(1280, 720)
	await _wait(6)
	await _shot("%s/20_720p_battle.png" % outdir)
	get_root().size = Vector2i(1920, 1080)
	await _wait(6)
	# HORDE P5/P6: dense horde with full gore + F3 overlay
	# MASS_HORDE: a designed mass wave (the shipping ruleset; Main sets S.mass)
	main.settings["video"]["gore"] = "full"
	main.dbg_overlay = true
	var hp_keep: float = float(S.stats["max_hp"])
	S.stats["max_hp"] = 1.0e9
	S.hp = 1.0e9
	# MASS_HORDE §View: early (hundreds), mid (thousands), late (10k+) with
	# orbital strikes landing in the thick of it (explosions part the sea).
	# The early shot starts on a clean field: no bodies, no queued corpses, no
	# ground layer from the earlier battle shots.
	S.set_enemies([])
	S.orbitals.clear()
	S.en.world.call("DrainCorpses", 1 << 20)
	main.gore.call("clear")
	await _wait(4)
	await _horde_stage(S, 300, "%s/21a_horde_early.png" % outdir)
	await _horde_stage(S, 2700, "%s/21b_horde_mid.png" % outdir)
	await _horde_stage(S, 9500, "%s/21c_horde_late.png" % outdir)
	S.stats["max_hp"] = hp_keep
	S.hp = hp_keep
	main.dbg_overlay = false
	main.settings["video"]["gore"] = "low"
	live_S = null
	# V2 P5: the run banks a Reliquary, a Boss Vault and two elite items
	(S.loot["caches"] as Array).append({"id": "reliquary", "ilvl": 90})
	(S.loot["caches"] as Array).append({"id": "boss", "ilvl": 60})
	(S.loot["items"] as Array).append({"src": "elite", "ilvl": 40})
	S.wind_used = true
	S.hp = -1.0
	S.stats["regen"] = 0.0
	await _wait(30)
	await _shot("%s/18_results.png" % outdir)
	main.open_loot()
	main.reveal_t0 = main.t_anim - 2.05   # mid-show: two up, the third face down
	await _wait(2)
	await _shot("%s/18b_loot_reveal.png" % outdir, false)
	main.reveal_skip = true
	main.reveal_fired = 10
	main._rebuild_ui()
	await _wait(4)
	await _shot("%s/18c_loot_all.png" % outdir, false)
	main.set_overlay("")
	main.go_base()
	main.set_tab("outpost")
	get_root().size = Vector2i(1280, 720)
	await _wait(6)
	await _shot("%s/20b_720p_outpost.png" % outdir)
	main.set_tab("core")
	await _shot("%s/20c_720p_core.png" % outdir)
	get_root().size = Vector2i(1920, 1080)
	await _wait(6)
	main.go_menu()
	main.confirm_del = 1
	main._rebuild_ui()
	await _shot("%s/19_menu_delete.png" % outdir)
	MetaSave.clear()
	quit(0)


func _horde_stage(S, n: int, path: String) -> void:
	var hev: Array = []
	var mix: Array = ["mite", "mite", "mite", "mite", "drone", "drone", "skitter", "ranged", "shield", "sapper", "splitter", "hauler"]
	for k in n:
		var ang: float = TAU * float(k % 7) / 7.0 + float(k) * 0.0007
		S._spawn(String(mix[k % mix.size()]), hev, TowerState.CENTER + Vector2.from_angle(ang) * (S.spawn_r() + float(k % 60) * 3.0), false, 1.0, S.wave, 1)
	await _wait(130)
	var core_w: Dictionary = (S.stats["weapons"] as Array).back()
	for j in 3:
		var pos: Vector2 = S._densest(90.0)
		if pos == Vector2.INF:
			break
		pos += Vector2(float(j) * 70.0 - 70.0, float(j % 2) * 50.0)
		S.orbitals.append({"pos": pos, "t": 0.05 + 0.1 * float(j), "dmg": float(core_w["dmg"]) * 40.0, "r": 110.0})
		S.en.world.call("RadialImpulse", pos.x, pos.y, 160.0, 900.0)
		main._ring(pos, 140.0, 0.6, Color("ffcf6b"))
	await _wait(9)
	print("stage bodies ", S.en.order.size())
	await _shot(path, false)


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
