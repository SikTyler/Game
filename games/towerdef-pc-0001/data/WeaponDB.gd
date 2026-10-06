extends RefCounted
## In-run weapon buildings (V2 P3c): footprint, aiming rule, firing pattern
## and base numbers (TowerState.compute_stats owns the math that scales them;
## FirePatterns owns what a shot does). P7 grows this table to 18 weapons.
##   size     footprint side on the run grid (1 or 2)
##   aim      "radial" - 360 deg, takes any target in range
##            "arc"    - turns within +-arc/2 of its facing
##            "fixed"  - fires straight along its facing: a cone (arc > 0) or
##                       a lane (arc 0); only when a body is in that shape
##   arc      traverse / cone width in degrees (360 radial, 0 a lane)
##   dir_mult damage for committing to a direction (radial 1.0 ... lane 1.6)
##   dmg, rate, range: T1 base (range in cpx() cells); p: pattern parameters
##            (`blast` / `lob_r` in cells; `pierce` = lane half-width in px)
## Facing is a building's `rot` (0-7, 45 deg steps, 0 = east, clockwise on
## screen); new buildings face away from the Core.
## V2 P7d: 18 weapons - radial: Mortar, Tesla, Cryo, Pulse, Missile Battery,
## Spike Pylon, Minelayer (+ the Gatling's wide arc); arc / fixed: Gatling,
## Flamer, Railgun, Scatter, Laser Lance, Saw, Arc Projector, Sonic Cannon,
## Harpoon, Plasma Fence, Flak Burst.

const DEFS: Dictionary = {
	"gun":     {"name": "Gatling", "size": 1, "aim": "arc", "arc": 120.0, "pattern": "pierce_round", "dir_mult": 1.2,
		"dmg": 6.0, "rate": 2.0, "range": 3.0, "p": {}},
	"mortar":  {"name": "Mortar", "size": 2, "aim": "radial", "arc": 360.0, "pattern": "lob_aoe", "dir_mult": 1.0,
		"dmg": 18.0, "rate": 0.4, "range": 4.5, "p": {"splash": 1.0, "min_range": 1.5}},
	"tesla":   {"name": "Tesla Coil", "size": 1, "aim": "radial", "arc": 360.0, "pattern": "chain", "dir_mult": 1.0,
		"dmg": 9.0, "rate": 0.8, "range": 3.0, "p": {"chains": 3, "chain_frac": 0.7}},
	"flak":    {"name": "Flamer", "size": 1, "aim": "fixed", "arc": 50.0, "pattern": "cone_dot", "dir_mult": 1.4,
		"dmg": 8.0, "rate": 1.5, "range": 3.5, "p": {}},
	"railgun": {"name": "Railgun", "size": 2, "aim": "fixed", "arc": 0.0, "pattern": "pierce_line", "dir_mult": 1.6,
		"dmg": 60.0, "rate": 0.25, "range": 7.0, "p": {"pierce": 14.0}},
	"frost":   {"name": "Cryo Spire", "size": 1, "aim": "radial", "arc": 360.0, "pattern": "aura_slow", "dir_mult": 1.0,
		"dmg": 1.5, "rate": 2.0, "range": 2.5, "p": {"slow": 0.30, "slow_t": 0.6}},
	# ---- V2 P7d: 12 more (4 radial, 8 arc / fixed) --------------------------
	"pulse":     {"name": "Pulse Emitter", "size": 1, "aim": "radial", "arc": 360.0, "pattern": "nova", "dir_mult": 1.0,
		"dmg": 6.0, "rate": 0.7, "range": 2.2, "p": {}},
	"missile":   {"name": "Missile Battery", "size": 2, "aim": "radial", "arc": 360.0, "pattern": "homing", "dir_mult": 1.0,
		"dmg": 12.0, "rate": 0.5, "range": 5.0, "p": {"missiles": 4, "blast": 0.4}},
	"spike":     {"name": "Spike Pylon", "size": 1, "aim": "radial", "arc": 360.0, "pattern": "aura_dmg", "dir_mult": 1.0,
		"dmg": 3.0, "rate": 2.0, "range": 1.6, "p": {}},
	"mines":     {"name": "Minelayer", "size": 1, "aim": "radial", "arc": 360.0, "pattern": "mine", "dir_mult": 1.0,
		"dmg": 28.0, "rate": 0.35, "range": 3.5, "p": {"blast": 0.8, "fuse": 1.0}},
	"scatter":   {"name": "Scatter Gun", "size": 1, "aim": "fixed", "arc": 60.0, "pattern": "cone_burst", "dir_mult": 1.4,
		"dmg": 6.0, "rate": 1.0, "range": 2.8, "p": {"pellets": 6}},
	"laser":     {"name": "Laser Lance", "size": 2, "aim": "fixed", "arc": 0.0, "pattern": "beam_ramp", "dir_mult": 1.6,
		"dmg": 4.0, "rate": 4.0, "range": 6.0, "p": {"pierce": 8.0, "ramp": 3.0}},
	"saw":       {"name": "Saw Launcher", "size": 1, "aim": "arc", "arc": 140.0, "pattern": "bounce", "dir_mult": 1.2,
		"dmg": 12.0, "rate": 0.8, "range": 3.5, "p": {"bounces": 4}},
	"arcproj":   {"name": "Arc Projector", "size": 1, "aim": "arc", "arc": 100.0, "pattern": "chain", "dir_mult": 1.3,
		"dmg": 7.0, "rate": 0.9, "range": 3.0, "p": {"chain_base": 4}},
	"sonic":     {"name": "Sonic Cannon", "size": 1, "aim": "fixed", "arc": 70.0, "pattern": "cone_knock", "dir_mult": 1.4,
		"dmg": 5.0, "rate": 0.5, "range": 3.0, "p": {"knock": 2.5}},
	"harpoon":   {"name": "Harpoon", "size": 1, "aim": "arc", "arc": 90.0, "pattern": "heavy", "dir_mult": 1.3,
		"dmg": 40.0, "rate": 0.35, "range": 4.5, "p": {"elite": 2.5, "slow": 0.4}},
	"plasma":    {"name": "Plasma Fence", "size": 1, "aim": "fixed", "arc": 0.0, "pattern": "lane_burn", "dir_mult": 1.5,
		"dmg": 5.0, "rate": 0.8, "range": 4.0, "p": {"pierce": 10.0, "burn_s": 2.0}},
	"flakburst": {"name": "Flak Burst", "size": 1, "aim": "arc", "arc": 120.0, "pattern": "lob_aoe", "dir_mult": 1.2,
		"dmg": 9.0, "rate": 0.7, "range": 4.0, "p": {"lob_r": 0.5, "lob_knock": 0.8, "min_range": 0.0}},
}
const AIMS: Array = ["radial", "arc", "fixed"]
const ROT_STEP_DEG: float = 45.0


static func has(id: String) -> bool:
	return DEFS.has(id)


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func aim_of(id: String) -> String:
	return String((DEFS.get(id, {}) as Dictionary).get("aim", "radial"))


## Does this weapon have a facing that matters (arc or fixed)?
static func directional(id: String) -> bool:
	return aim_of(id) != "radial" and DEFS.has(id)


## Unit facing vector for rotation step r (0 = east, clockwise on screen).
static func facing(r: int) -> Vector2:
	return Vector2.from_angle(deg_to_rad(ROT_STEP_DEG * float(posmod(r, 8))))


## Rotation step (0-7) closest to direction d (the default: away from the Core).
static func rot_toward(d: Vector2) -> int:
	if d == Vector2.ZERO:
		return 6   # north
	return posmod(int(round(rad_to_deg(d.angle()) / ROT_STEP_DEG)), 8)
