extends RefCounted
## Special attacks (REDESIGN_SPEC §2.4): active abilities on hotkeys 1-4.
## Pure + static over a slots Array owned by TowerState:
##   slots = [{id, copies, cd, charges}]   (at most PickDB.SPECIAL_SLOTS)
## Cooldowns tick in simulated time (they respect game speed). Each extra copy
## of a special cuts its cooldown 3% (max 3 copies). TowerState applies the
## effect of a successful cast and emits `special_cast`; this module owns the
## slot bookkeeping, cooldown math and the `special_ready` events.

const PickDB := preload("res://data/PickDB.gd")
const TuneRef := preload("res://Tune.gd")

## Effect numbers (SYSTEMS §2.5).
const FX: Dictionary = {
	"sp_orbital": {"radius": 1.5, "mult": 25.0, "delay": 0.8, "targeted": true},
	"sp_emp": {"slow": 0.5, "dur": 4.0},
	"sp_repair": {"heal": 0.35, "dur": 3.0},
	"sp_overdrive": {"rate": 2.0, "dur": 6.0},
	"sp_magnet": {"cash": 2.0, "dur": 10.0},
	"sp_timewarp": {"dur": 3.0},
	# V2 P7d
	"sp_nuke": {"radius": 3.0, "mult": 60.0, "delay": 1.5, "targeted": true},
	"sp_shield": {"dur": 3.0},
	"sp_frenzy": {"rate": 1.5, "dur": 8.0},
	"sp_blackhole": {"radius": 2.5, "mult": 10.0, "slow": 0.8, "dur": 4.0, "targeted": true},
	"sp_meteor": {"n": 5, "radius": 1.0, "mult": 8.0, "spread": 1.5},
	"sp_jackpot": {},
}


static func base_cd(id: String) -> float:
	return float((PickDB.get_def(id)).get("cd", 30.0))


## Cooldown of `id` with `copies` copies; cd_mult from parts (Capacitor slot).
static func cooldown(id: String, copies: int, cd_mult: float = 1.0) -> float:
	var extra: int = clampi(copies, 1, PickDB.SPECIAL_COPIES) - 1
	return base_cd(id) * (1.0 - TuneRef.num("pc_special_copy_cd", 0.03) * float(extra)) * maxf(0.1, cd_mult)


static func find(slots: Array, id: String) -> int:
	for k in slots.size():
		if String((slots[k] as Dictionary)["id"]) == id:
			return k
	return -1


## Take a special pick: +1 copy if slotted, else a new slot (ready at once);
## when all 4 slots are full the pick replaces slot `replace` (player choice).
static func take(slots: Array, id: String, replace: int = -1) -> Dictionary:
	var k: int = find(slots, id)
	if k >= 0:
		var s: Dictionary = slots[k]
		s["copies"] = mini(PickDB.SPECIAL_COPIES, int(s["copies"]) + 1)
		return {"slot": k, "copies": int(s["copies"]), "replaced": ""}
	var entry: Dictionary = {"id": id, "copies": 1, "cd": 0.0, "charges": 1}
	if slots.size() < PickDB.SPECIAL_SLOTS:
		slots.append(entry)
		return {"slot": slots.size() - 1, "copies": 1, "replaced": ""}
	var r: int = clampi(replace, 0, slots.size() - 1)
	var old: String = String((slots[r] as Dictionary)["id"])
	slots[r] = entry
	return {"slot": r, "copies": 1, "replaced": old}


## Advance every cooldown by dt (sim seconds); returns special_ready events.
static func tick(slots: Array, dt: float) -> Array:
	var ev: Array = []
	for k in slots.size():
		var s: Dictionary = slots[k]
		var cd: float = float(s["cd"])
		if cd <= 0.0:
			continue
		cd = maxf(0.0, cd - dt)
		s["cd"] = cd
		if cd <= 0.0:
			ev.append({"t": "special_ready", "slot": k, "id": String(s["id"])})
	return ev


static func ready(slots: Array, k: int) -> bool:
	return k >= 0 and k < slots.size() and float((slots[k] as Dictionary)["cd"]) <= 0.0


## Start the cooldown of slot k (after a successful cast).
static func consume(slots: Array, k: int, cd_mult: float = 1.0) -> void:
	var s: Dictionary = slots[k]
	s["cd"] = cooldown(String(s["id"]), int(s["copies"]), cd_mult)


static func is_targeted(id: String) -> bool:
	return bool((FX.get(id, {}) as Dictionary).get("targeted", false))
