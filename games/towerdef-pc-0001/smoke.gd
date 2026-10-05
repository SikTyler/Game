extends SceneTree
## Corehold V2 smoke gate (~1-2 min, V2_PROGRESS §Gates). Independent of the
## big playtest bot so it survives every phase of the redesign:
##   S1 a fresh T1 run played by a minimal bot ends (no stall), reaches wave 5
##      and banks coins;
##   S2 a 3-run mini campaign spends meta between runs (MetaPolicy) and the
##      save keeps progressing;
##   S3 the same seed replays to the same fingerprint (determinism).
## Prints SMOKE OK / SMOKE FAIL <reason>.
## Usage: godot --headless --path games/towerdef-pc-0001 --script res://smoke.gd

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Cores := preload("res://Cores.gd")
const Outpost := preload("res://Outpost.gd")
const Specials := preload("res://Specials.gd")

const DT: float = 0.1
const MAX_S: float = 1800.0
const LOD: int = 1200
const NOW0: int = 1767225600

var fails: Array = []


func _check(name: String, ok: bool, detail: String = "") -> void:
	print(("SMOKE ok   " if ok else "SMOKE FAIL ") + name + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails.append(name)


func _initialize() -> void:
	var t0: int = Time.get_ticks_msec()
	# S1 fresh run
	var save: Dictionary = BaseMeta.normalize({})
	var r: Dictionary = play(save, 4242)
	_check("S1 fresh run ends (no stall)", bool(r["over"]), "t=%.0f wave=%d" % [float(r["time"]), int(r["wave"])])
	_check("S1 reaches wave 5", int(r["wave"]) >= 5, "wave=%d" % int(r["wave"]))
	_check("S1 banks coins", int(save["coins"]) > 0, "coins=%d" % int(save["coins"]))
	# S2 mini campaign
	var lv0: int = Cores.level(save)
	var waves: Array = [int(r["wave"])]
	for k in 3:
		MetaPolicy.spend(save, NOW0 + 3600 * (k + 1))
		var rr: Dictionary = play(save, 5000 + k * 97)
		waves.append(int(rr["wave"]))
		_check("S2 run %d ends" % (k + 2), bool(rr["over"]), "wave=%d" % int(rr["wave"]))
	MetaPolicy.spend(save, NOW0 + 3600 * 5)
	_check("S2 meta progressed (Core level or Outpost grew)", Cores.level(save) > lv0 or MetaPolicy.outpost_size(save) > 1, "core L%d -> L%d, outpost %d" % [lv0, Cores.level(save), MetaPolicy.outpost_size(save)])
	_check("S2 runs counted", int(save["runs"]) == 4, "runs=%d" % int(save["runs"]))
	print("SMOKE waves %s" % str(waves))
	# S3 determinism
	var a: Dictionary = play(BaseMeta.normalize({}), 777, 240.0)
	var b: Dictionary = play(BaseMeta.normalize({}), 777, 240.0)
	_check("S3 same seed, same fingerprint", String(a["fp"]) == String(b["fp"]), "%s vs %s" % [a["fp"], b["fp"]])
	print("SMOKE time %.1f s" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	print("SMOKE OK" if fails.is_empty() else "SMOKE FAIL %d" % fails.size())
	quit(0 if fails.is_empty() else 1)


## One run with the minimal bot; returns {over, wave, kills, coins, time, fp}.
static func play(save: Dictionary, seed_value: int, max_s: float = MAX_S) -> Dictionary:
	var S = TowerState.new()
	S.mass = true
	S.mass_lod_cap = LOD
	S.setup(seed_value, save, NOW0)
	var t: float = 0.0
	var acc: float = 0.0
	while not S.over and t < max_s:
		S.tick(DT)
		t += DT
		acc += DT
		if acc >= 0.5:
			acc = 0.0
			Bot.step(S)
	var fp: String = "%d/%d/%d/%.1f" % [S.wave, S.kills, int(S.coins_run), S.cash_earned]
	return {"over": S.over, "wave": S.wave, "kills": S.kills, "coins": int(S.coins_run), "time": t, "fp": fp}


## Minimal in-run policy: take the first placeable building (else card 0),
## place it nearest the Core, take perk/mutation 0, buy the cheapest Core
## enhancement, fire every ready special.
class Bot:
	static func step(S) -> void:
		if S.mutation_offer.size() > 0:
			S.choose_mutation(0)
		if S.perk_offer.size() > 0:
			S.choose_perk(0)
		if S.draft.size() > 0:
			var pick: int = 0
			for k in S.draft.size():
				if String((S.draft[k] as Dictionary).get("kind", "")) == "new":
					pick = k
					break
			S.choose_card(pick)
		if S.pending_place != "":
			var best: int = -1
			var bd: int = 999
			for i in S.free_slots():
				if S.can_place(int(i), S.pending_place) and S.ring_of(int(i)) < bd:
					bd = S.ring_of(int(i))
					best = int(i)
			if best >= 0:
				S.place(best)
			else:
				S.cancel_place()
		if S.pending_upgrade != "":
			var tg: Array = S.upgrade_targets(S.pending_upgrade)
			if tg.is_empty():
				S.cancel_upgrade()
			else:
				S.apply_upgrade(int(tg[0]))
		for k in S.specials.size():
			if Specials.ready(S.specials, k):
				S.cast_special(k, -1)
		var guard: int = 0
		while guard < 8:
			guard += 1
			var bt: String = ""
			var bc: int = 1 << 30
			for tr in S.TRACK_IDS:
				var c: int = S.track_cost(String(tr))
				if c >= 0 and c < bc:
					bc = c
					bt = String(tr)
			if bt == "" or S.cash < float(bc):
				break
			S.buy_track(bt)


## Meta spending between runs: Core levels first, then the Outpost.
class MetaPolicy:
	static func spend(save: Dictionary, now: int) -> void:
		Outpost.collect_all(save, now, true)
		var guard: int = 0
		while guard < 200 and not Cores.try_level(save, Cores.active(save)).is_empty():
			guard += 1
		# one Coin Mill next to the Relay if affordable
		var o: Dictionary = save["outpost"]
		if Outpost.count_of(o, "mill") == 0:
			for y in range(0, 12):
				for x in range(0, 12):
					if Outpost.place_error(save, "mill", x, y, 0) == "" and not Outpost.place(save, "mill", x, y, 0, now).is_empty():
						return

	static func outpost_size(save: Dictionary) -> int:
		return (save["outpost"]["buildings"] as Dictionary).size()
