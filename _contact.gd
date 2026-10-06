extends SceneTree
## Renders a contact sheet of every art/*.svg. Usage (under xvfb):
## godot --path . --script res://_contact.gd -- <out_dir>

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	var ids: Array[String] = []
	for f: String in DirAccess.get_files_at("res://art"):
		if f.ends_with(".svg"):
			ids.append(f.get_basename())
	ids.sort()
	var cols: int = 10
	var cell: int = 96
	var rows: int = int(ceil(float(ids.size()) / float(cols)))
	var img: Image = Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	img.fill(Color("1b2027"))
	var i: int = 0
	for id: String in ids:
		var t: Texture2D = ArtDB.tex(id)
		if t == null:
			push_error("missing art " + id)
			i += 1
			continue
		var src: Image = t.get_image()
		src.decompress()
		src.convert(Image.FORMAT_RGBA8)
		src.resize(64, 64, Image.INTERPOLATE_BILINEAR)
		var small: Image = src.duplicate() as Image
		small.resize(40, 40, Image.INTERPOLATE_BILINEAR)
		var x: int = (i % cols) * cell
		var y: int = (i / cols) * cell
		img.blend_rect(src, Rect2i(0, 0, 64, 64), Vector2i(x + 4, y + 4))
		img.blend_rect(small, Rect2i(0, 0, 40, 40), Vector2i(x + 52, y + 52))
		i += 1
	img.save_png(out_dir.path_join("contact_sheet.png"))
	print("CONTACT OK ", ids.size())
	quit()
