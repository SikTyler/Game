extends SceneTree
## HORDE Phase-1 determinism golden: 120 s seeded sims (one per Core attack,
## a full weapon/hut/wall board, waves 12+) fingerprinted with SHA-256 over
## (wave, kills, cash, hp, every enemy eid/pos/hp) once per sim second, plus
## Orbital auto-aim (_densest). Prints HORDE FP <core> <hash> and a combined
## hash. selftest.gd embeds the combined value recorded from the Dict
## implementation (pre-SoA), so the SoA port must reproduce it bit-for-bit.
## Usage: godot --headless --path games/towerdef-pc-0001 --script res://horde_fp.gd

const BOARD: Dictionary = {16: "gun", 17: "mortar", 18: "tesla", 23: "frost", 25: "flak", 30: "hut_infantry", 31: "hut_sapper", 32: "hut_drone", 10: "railgun", 38: "barricade"}


func _initialize() -> void:
	var all: String = run_all()
	print("HORDE FP ALL " + all)
	quit(0)


static func run_all() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for core in ["bastion", "foundry", "lance", "tempest"]:
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
	var save: Dictionary = BM.default_save()
	save["cores"] = {"active": core, "owned": ["bastion", "foundry", "lance", "tempest"], "levels": {"bastion": 3, "foundry": 3, "lance": 3, "tempest": 3}}
	save = BM.normalize(save)
	var S = TS.new()
	S.setup(4242, save, 1_700_000_000)
	for i in BOARD.keys():
		S.slots[int(i)] = {"id": String(BOARD[i]), "perm": 0, "run": 2}
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
		if k == 600:   # a 150-body flood at deterministic positions (cap 220)
			var KS: Array = ["drone", "skitter", "hauler", "ranged", "splitter", "elite"]
			var hm: float = S.hp_mult
			S.hp_mult = 0.08   # fragile flood: kills, overkill carry, splits
			for j in 150:
				var a: float = TAU * float(j) / 150.0
				S._spawn(String(KS[j % KS.size()]), [], S.CENTER + Vector2.from_angle(a) * (230.0 + float(j % 7) * 30.0), -1)
			S.hp_mult = hm
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
