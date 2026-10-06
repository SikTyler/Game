extends RefCounted
## Generated gear names (V2 P4): brand syllable + epithet + base noun, e.g.
## "Volt 'Stormjaw' Arc Caster". Pure function of (seed, brand, base,
## rarity): the same item always reads the same; players can rename.

const EPI_A: Array = ["Storm", "Grim", "Iron", "Night", "Sun", "Blood", "Frost", "Thunder", "Void", "Ember",
	"Star", "Rift", "Bone", "Gold", "Ghost", "Wild", "Hex", "Neon", "Dread", "Halo"]
const EPI_B: Array = ["jaw", "fang", "song", "maw", "call", "bite", "wake", "crown", "spite", "heart",
	"howl", "lash", "fall", "veil", "brand", "grin", "storm", "reign", "pulse", "spark"]
const MARKS: Dictionary = {"common": "", "uncommon": "", "rare": " Mk II", "epic": " Mk III", "legendary": " Prime", "mythic": " Apex", "exotic": " Omega"}


static func make(seed_value: int, brand_syl: Array, base_name: String, rarity: String) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var syl: String = String(brand_syl[r.randi_range(0, brand_syl.size() - 1)]) if not brand_syl.is_empty() else ""
	var epi: String = String(EPI_A[r.randi_range(0, EPI_A.size() - 1)]) + String(EPI_B[r.randi_range(0, EPI_B.size() - 1)])
	if rarity == "common":
		return "%s %s" % [syl, base_name]
	return "%s '%s' %s%s" % [syl, epi, base_name, String(MARKS.get(rarity, ""))]
