extends RefCounted
## P2 selftest stage: the neon UI kit's pure parts. Palette contrast (every
## text token on every surface >= WCAG 4.5), the roll-up curve (deterministic,
## monotonic, lands exactly, pops once), juice scaling and the rising pitch
## ladder. `t` is the selftest runner (t._check(name, ok, detail)).

const Kit := preload("res://ui/Kit.gd")
const Roll := preload("res://vfx/Roll.gd")
const Juice := preload("res://vfx/Juice.gd")
const Sfx := preload("res://Sfx.gd")


static func run(t) -> void:
	_contrast(t)
	_roll(t)
	_juice(t)


static func _contrast(t) -> void:
	var bad: Array = []
	for fg in Kit.TEXT_TOKENS:
		for bg in Kit.SURFACES:
			var c: float = Kit.contrast(Kit.token(String(fg)), Kit.token(String(bg)))
			if c < 4.5:
				bad.append("%s/%s %.2f" % [fg, bg, c])
	t._check("P2 palette: every text token on every surface has WCAG contrast >= 4.5", bad.is_empty(), str(bad))
	var rb: Array = []
	for r in Kit.RARITIES:
		if String(r) != "exotic" and Kit.contrast(Kit.rarity_col(String(r)), Kit.PANEL2) < 4.5:
			rb.append(r)
	t._check("P2 palette: rarity colours stay readable as text on cards", rb.is_empty(), str(rb))
	t._check("P2 palette: contrast() is the WCAG ratio (white on black = 21)", absf(Kit.contrast(Color.WHITE, Color.BLACK) - 21.0) < 0.01)
	t._check("P2 palette: seven gear rarities, ranked common .. exotic", Kit.RARITIES.size() == 7 and Kit.rarity_rank("common") == 0 and Kit.rarity_rank("exotic") == 6 and Kit.rarity_rank("insight") == -1)
	t._check("P2 palette: Exotic cycles its hue, others are fixed", Kit.rarity_col_t("exotic", 0.0) != Kit.rarity_col_t("exotic", 2.0) and Kit.rarity_col_t("epic", 0.0) == Kit.rarity_col_t("epic", 2.0))


static func _roll(t) -> void:
	var d: float = Roll.duration(1500.0)
	t._check("P2 roll: duration grows with the jump and is clamped", Roll.duration(1.0) < d and d < Roll.duration(1.0e6) and is_equal_approx(Roll.duration(1.0e12), Roll.MAX_DUR) and Roll.duration(0.0) >= Roll.MIN_DUR)
	var prev: float = 100.0
	var mono: bool = true
	for k in 41:
		var v: float = Roll.value_at(100.0, 1600.0, d * float(k) / 40.0, d)
		if v < prev - 0.0001:
			mono = false
		prev = v
	t._check("P2 roll: monotonic from the old to the new value, lands exactly", mono and Roll.value_at(100.0, 1600.0, d, d) == 1600.0 and Roll.value_at(100.0, 1600.0, 0.0, d) == 100.0)
	t._check("P2 roll: ease-out (past halfway at a third of the time)", Roll.value_at(0.0, 1.0, d / 3.0, d) > 0.5)
	t._check("P2 roll: pop is 1.0 while rolling, peaks after landing, then settles", Roll.pop_at(d * 0.5, d) == 1.0 and Roll.pop_at(d + Roll.POP_DUR * 0.5, d) > 1.15 and Roll.pop_at(d + Roll.POP_DUR + 0.01, d) == 1.0)
	var a: Roll = Roll.new()
	var b: Roll = Roll.new()
	for r in [a, b]:
		(r as Roll).set_target(50.0)
		(r as Roll).set_target(5050.0)
	var same: bool = true
	for k in 30:
		a.update(0.033)
		b.update(0.033)
		if a.value() != b.value():
			same = false
	t._check("P2 roll: two counters fed the same steps show the same numbers", same)
	var c: Roll = Roll.new()
	c.set_target(10.0)
	t._check("P2 roll: the first target snaps (no roll from zero at boot)", c.value() == 10.0 and not c.busy())
	c.set_target(20.0)
	c.update(0.05)
	var mid: float = c.value()
	c.set_target(30.0)
	t._check("P2 roll: retargeting mid-roll continues from the shown value", c.value() == mid and c.busy())
	c.set_target(99.0, true)
	t._check("P2 roll: snap jumps straight to the value", c.value() == 99.0 and not c.busy())


static func _juice(t) -> void:
	t._check("P2 juice: shake grows with event size and is capped", Juice.shake_amount(0.0) < Juice.shake_amount(2.0) and Juice.shake_amount(2.0) < Juice.shake_amount(6.0) and Juice.shake_amount(100.0) <= 0.7)
	var j: Juice = Juice.new()
	j.shake(6.0)
	t._check("P2 juice: shake(mag) adds trauma (per-frame budget applies)", j.trauma > 0.0 and j.trauma <= Juice.TRAUMA_PER_FRAME + 0.0001)
	var ladder: bool = true
	for k in 8:
		if Sfx.seq_pitch(k + 1) <= Sfx.seq_pitch(k):
			ladder = false
	t._check("P2 sfx: the reveal pitch ladder rises a whole tone per step from 1.0", ladder and Sfx.seq_pitch(0) == 1.0 and absf(Sfx.seq_pitch(6) - 2.0) < 0.001 and Sfx.seq_pitch(100) == 4.0)
