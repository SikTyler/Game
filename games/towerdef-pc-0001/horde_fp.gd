extends SceneTree
## HORDE determinism golden: 120 s seeded MASS sims (V2 P3d: the designed mass
## horde is the only ruleset), one per Weapon frame equipped on the one Core
## (V2 P4: Autocannon, Slag Lobber, Lance, Pulse Nova, Scatter, Rail Driver,
## Arc Caster, Flame Projector, Swarm Missiles, Saw Launcher) on two boards:
## an open weapon/hut/wall board and the same board with the Core sealed by a
## Wall ring (Lance, Pulse: the squeeze path), waves 14+, fingerprinted with
## SHA-256 over (wave, kills, cash, hp, every enemy eid/pos/hp) once per sim
## second, plus Orbital auto-aim (_densest). Prints HORDE FP <frame> <hash>
## and a combined hash; selftest.gd embeds the combined value.
## Usage: godot --headless --path games/towerdef-pc-0001 --script res://horde_fp.gd

## V2 P3b board (21x21 small cells, 3x3 Core): [dr, dc] from the Core's
## centre cell -> id (the Mortar and Railgun are 2x2, anchored top-left).
const BOARD_RC: Array = [[-5, 0, "gun"], [-7, 2, "mortar"], [-5, 5, "tesla"], [-4, -5, "frost"], [-4, -3, "flak"],
	[-4, 3, "hut_infantry"], [-3, 6, "hut_sapper"], [-8, 7, "railgun"], [-3, 0, "barricade"]]


## `sealed` adds Walls on the 16 cells touching the Core (bodies squeeze through).
static func board(sealed: bool = false) -> Dictionary:
	var TS = load("res://TowerState.gd")
	var out: Dictionary = {}
	for e in BOARD_RC:
		out[int(TS.cell(int(e[0]), int(e[1])))] = String(e[2])
	if sealed:
		for c in TS.CORE_RING:
			out[int(c)] = "barricade"
	return out
## V2 P4: every Weapon frame, equipped through the gear save (Common, L1,
## no perks, quirk-free "standard" brand). The Lance and Pulse Nova run on the
## Wall-sealed board (squeeze path).
const FRAMES: Array = ["autocannon", "slag", "lance", "pulse", "scatter", "rail", "arc", "flame", "missiles", "saw"]
const SEALED: Array = ["lance", "pulse"]


func _initialize() -> void:
	var all: String = run_all()
	print("HORDE FP ALL " + all)
	quit(0)


static func run_all() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for core in FRAMES:
		var h: String = run_one(String(core))
		print("HORDE FP %s %s" % [core, h])
		ctx.update(h.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _dicts(S) -> Array:
	if S.get("en") != null:
		return S.en.to_dicts()
	return S.enemies


static func run_one(core: String) -> String:
	var BM = load("res://BaseMeta.gd")
	var TS = load("res://TowerState.gd")
	var GR = load("res://Gear.gd")
	var save: Dictionary = BM.default_save()
	save["core"] = {"lvl": 3}
	save = BM.normalize(save)
	GR.equip(save, GR.add_item(save, GR.make("weapon", core)))
	var S = TS.new()
	S.setup(4242, save, 1_700_000_000)
	var bd: Dictionary = board(SEALED.has(core))
	for i in bd.keys():
		S.slots[int(i)] = {"id": String(bd[i]), "perm": 0, "run": 2}
		S.unlocked[int(i)] = true
	S.recompute()
	S.wave = 14       # mid-game mix (elites, ranged, splitters, w15 boss)
	S._adopt_plan(S._build_plan(14, S.telegraph_s()), [], true)
	var buf := StreamPeerBuffer.new()
	var steps: int = int(120.0 / 0.05)
	for k in steps:
		if not S.draft.is_empty():
			S.choose_card(0)
		if not S.perk_offer.is_empty():
			S.choose_perk(0)
		if not S.mutation_offer.is_empty():
			S.choose_mutation(0)
		if S.pending_place != "":
			S.cancel_place()
		S.hp = maxf(S.hp, 5.0)
		if k == 600:   # a 150-body flood at deterministic positions
			var KS: Array = ["drone", "skitter", "hauler", "ranged", "splitter", "elite"]
			var hm: float = S.hp_mult
			var em: float = S.enemy_hp_mod
			S.hp_mult = 0.08   # fragile flood: kills, overkill carry, splits (elites: classic curve)
			S.enemy_hp_mod = 0.08   # mass bodies
			for j in 150:
				var a: float = TAU * float(j) / 150.0
				S._spawn(String(KS[j % KS.size()]), [], S.CENTER + Vector2.from_angle(a) * (230.0 + float(j % 7) * 30.0), false)
			S.hp_mult = hm
			S.enemy_hp_mod = em
		S.tick(0.05)
		if k % 20 == 19:
			buf.put_32(S.wave)
			buf.put_32(S.kills)
			buf.put_double(S.cash)
			buf.put_double(S.hp)
			var dn: Vector2 = S._densest(60.0)
			buf.put_float(dn.x)
			buf.put_float(dn.y)
			for e in _dicts(S):
				var ed: Dictionary = e
				buf.put_32(int(ed["eid"]))
				buf.put_float((ed["pos"] as Vector2).x)
				buf.put_float((ed["pos"] as Vector2).y)
				buf.put_double(float(ed["hp"]))
				buf.put_double(float(ed["slow_t"]))
				buf.put_32(int(ed.get("shield", 0)))
	buf.put_32(S.next_eid)
	print("  core=%s wave=%d kills=%d eids=%d live=%d troops=%d" % [core, S.wave, S.kills, S.next_eid, _dicts(S).size(), S.troops.size()])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf.data_array)
	return ctx.finish().hex_encode()
