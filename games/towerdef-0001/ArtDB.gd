class_name ArtDB
extends RefCounted
## Static texture lookup for res://art/<id>.svg. Cached; returns null when missing
## so callers fall back to primitive _draw.

static var _cache: Dictionary = {}

static func tex(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id] as Texture2D
	var path: String = "res://art/%s.svg" % id
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_cache[id] = t
	return t
