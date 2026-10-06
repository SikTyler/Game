extends SceneTree
## MASS_HORDE profile: the FULL sim tick (TowerState._step: spawns, C#
## HordeWorld step + mirror pull, every weapon's targeting/damage through the
## C# queries, troops, reap) with N live bodies (1k / 10k / 20k) converging on
## a built-up board, plus the C# step alone. Bodies are fodder-tough (they do
## not all die in the first second) and get topped back up to N each tick so
## the count holds. Not a CI gate (MASS_HORDE H11): prints numbers.
## Usage: godot --headless --path games/towerdef-pc-0001 --script res://horde_prof.gd [-- 1000 10000 20000]

## V2 P3b board (21x21 small cells, 3x3 Core): [dr, dc] from the Core's
## centre cell -> id (the Mortar and Railgun are 2x2, anchored top-left).
const BOARD_RC: Array = [[-5, 0, "gun"], [-7, 2, "mortar"], [-5, 5, "tesla"], [-4, -5, "frost"], [-4, -3, "flak"],
	[-4, 3, "hut_infantry"], [-3, 6, "hut_sapper"], [-8, 7, "railgun"], [-3, 0, "barricade"]]


## `fill` > 0 tops the board up to that many buildings with 1x1 Gatlings /
## Walls / Mines on free cells (rings 1-6) - V2 P3d gate: 40 buildings.
static func board(fill: int = 0) -> Dictionary:
	var TS = load("res://TowerState.gd")
	var out: Dictionary = {}
	var used: Dictionary = {}
	for e in BOARD_RC:
		var a: int = int(TS.cell(int(e[0]), int(e[1])))
		out[a] = String(e[2])
		for c in TS.footprint(a, TS.size_of(String(e[2]))):
			used[int(c)] = true
	var extra: Array = ["gun", "barricade", "mine"]
	var k: int = 0
	for ring in range(1, 7):
		for i in TS.N:
			if out.size() >= fill:
				return out
			if TS.ring_of(i) != ring or used.has(i) or (i % 3) != 0:
				continue
			out[i] = String(extra[k % extra.size()])
			used[i] = true
			k += 1
	return out
const WARM: int = 120    # 6 s of sim: the crowd reaches the board and piles up
const STEPS: int = 60


func _initialize() -> void:
	var sizes: Array = [1000, 10000, 20000]
	var ua: PackedStringArray = OS.get_cmdline_user_args()
	if not ua.is_empty():
		sizes = []
		for a in ua:
			sizes.append(int(a))
	for n in sizes:
		_run(int(n), 0)
	_run(10000, 40)   # V2 P3d gate: 10k bodies + 40 buildings <= 8 ms per tick
	quit(0)


func _top_up(S, n: int, k: int) -> void:
	var KS: Array = ["mite", "mite", "mite", "mite", "drone", "drone", "skitter", "ranged", "hauler"]
	var i: int = S.en.count()
	while i < n:
		var a: float = TAU * float(i + k * 7919) / 1031.0
		var kind: String = String(KS[(i + k) % KS.size()])
		var d: Dictionary = EnemyDBRef.get_def(kind).duplicate()
		d["kind"] = kind
		d["pos"] = S.CENTER + Vector2.from_angle(a) * (380.0 + float((i * 37) % 300))
		d["hp"] = 30.0
		d["max_hp"] = 30.0
		S.add_enemy(d)
		i += 1


const EnemyDBRef := preload("res://data/EnemyDB.gd")


func _run(n: int, fill: int) -> void:
	var BM = load("res://BaseMeta.gd")
	var TS = load("res://TowerState.gd")
	var save: Dictionary = BM.normalize(BM.default_save())
	var S = TS.new()
	S.setup(4242, save, 1_700_000_000)
	var bd: Dictionary = board(fill)
	S.grid_n = TS.SIDE
	for i in bd.keys():
		S.slots[int(i)] = {"id": String(bd[i]), "perm": 0, "run": 2}
		S.unlocked[int(i)] = true
	S.recompute()
	S.spawn_hold = true
	_top_up(S, n, 0)
	for k in WARM:
		_keep(S)
		S.tick(TS.SUBSTEP)
		_top_up(S, n, k)
	var tick_us: int = 0
	var cs_us: int = 0
	var worst: int = 0
	for k in STEPS:
		_keep(S)
		var t0: int = Time.get_ticks_usec()
		S.tick(TS.SUBSTEP)
		var dt: int = Time.get_ticks_usec() - t0
		tick_us += dt
		worst = maxi(worst, dt)
		cs_us += int((S.en.world.call("Stats") as Dictionary)["step_us"])
		_top_up(S, n, k + WARM)
	var ov: PackedFloat64Array = S.en.world.call("OverlapStats")
	print("HORDE PROF n=%d buildings=%d alive=%d full_tick=%.2f ms (worst %.2f) cs_step=%.2f ms rules+pull=%.2f ms overlap_mean=%.2f kills=%d" % [n, bd.size(), S.en.count(), float(tick_us) / 1000.0 / STEPS, float(worst) / 1000.0, float(cs_us) / 1000.0 / STEPS, float(tick_us - cs_us) / 1000.0 / STEPS, ov[1], S.kills])


func _keep(S) -> void:
	S.hp = maxf(S.hp, 1e9)
	if not S.draft.is_empty():
		S.choose_card(0)
	if not S.perk_offer.is_empty():
		S.choose_perk(0)
	if not S.mutation_offer.is_empty():
		S.choose_mutation(0)
	if S.pending_place != "":
		S.cancel_place()
