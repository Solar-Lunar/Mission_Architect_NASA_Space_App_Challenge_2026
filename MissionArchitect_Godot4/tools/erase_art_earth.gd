extends SceneTree

## One-shot asset tool: the reference-art dashboards bake a static Earth into
## the picture, which peeks out around the live rotating shader globe.  This
## erases the static planet disc (and its glow) from the art, filling it with
## the artwork's own deep-space colour so the live globe sits on clean space.
##
## PROTECT rects keep baked UI chips (the EARTH observation buttons) intact so
## they still read as overlays; the live globe punches itself out around them
## via shader cutouts.  Originals live in tools/art_backup/*_orig.png; when a
## backup exists it is used as the erase source so the tool can be re-run with
## different protect rects without stacking erases.

const ART := {
	"res://assets/images/dashboard/dashboard_jpss2.png": {
		"disc": [0.460, 0.420, 0.343],
		"protect": [
			[0.2560, 0.2455, 0.3361, 0.2880],  # True Color
			[0.2560, 0.2997, 0.3361, 0.3422],  # Cloud Cover
			[0.2560, 0.3517, 0.3361, 0.3964],  # Thermal (Fire)
			[0.2560, 0.4070, 0.3361, 0.4495],  # Temperature
			[0.2560, 0.4623, 0.3361, 0.5037],  # Ozone (OMPS)
			[0.2560, 0.5165, 0.3361, 0.5590],  # Precipitation
		],
		# Baked header text (redrawn live over the globe by TopFx).
		"extra_erase": [[0.250, 0.186, 0.428, 0.232]],
	},
	"res://assets/images/dashboard/dashboard_swot.png": {
		"disc": [0.472, 0.409, 0.285],
		"protect": [],
		"extra_erase": [],
	},
}
# disc: cx, cy as width fractions; r as height fraction — the same disc the
# live globe renders over.  protect: [x0, y0, x1, y1] art fractions kept
# intact.  extra_erase: rects wiped to the space colour regardless of disc.

const BACKUP_DIR := "res://tools/art_backup"

func _initialize() -> void:
	var ok := true
	for path in ART:
		if not _erase(path, ART[path]):
			ok = false
	print("erase_art_earth done, ok=%s" % ok)
	quit(0 if ok else 1)

func _erase(path: String, spec: Dictionary) -> bool:
	var abs_path := ProjectSettings.globalize_path(path)
	# Prefer the pristine original as the source so re-runs never stack erases.
	var orig_name := path.get_file().get_basename() + "_orig.png"
	var orig_abs := ProjectSettings.globalize_path(BACKUP_DIR + "/" + orig_name)
	var source_abs := orig_abs if FileAccess.file_exists(orig_abs) else abs_path
	var img := Image.load_from_file(source_abs)
	if img == null:
		push_error("cannot load %s" % source_abs)
		return false
	if not FileAccess.file_exists(orig_abs):
		img.save_png(orig_abs)
	var s := img.get_size()
	var d: Array = spec["disc"]
	var c := Vector2(d[0] * s.x, d[1] * s.y)
	var r: float = d[2] * s.y
	var bg := _sample_bg(img, s)
	# Erase just past the art planet's own limb so its baked atmosphere glow
	# survives as a soft ring the live globe's rim melts into.
	var erase_r := r * 1.02
	var feather := 42.0
	var x0 := maxi(int(c.x - erase_r - 2.0), 0)
	var x1 := mini(int(c.x + erase_r + 2.0), s.x - 1)
	var y0 := maxi(int(c.y - erase_r - 2.0), 0)
	var y1 := mini(int(c.y + erase_r + 2.0), s.y - 1)
	var protect: Array = spec["protect"]
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dpx := Vector2(x, y).distance_to(c)
			if dpx >= erase_r:
				continue
			var fu := float(x) / float(s.x)
			var fv := float(y) / float(s.y)
			var skip := false
			for pr in protect:
				if fu > pr[0] and fu < pr[2] and fv > pr[1] and fv < pr[3]:
					skip = true
					break
			if skip:
				continue
			var t := 1.0
			if dpx > erase_r - feather:
				t = 1.0 - smoothstep(erase_r - feather, erase_r, dpx)
			var orig := img.get_pixel(x, y)
			img.set_pixel(x, y, orig.lerp(bg, t))
	# Extra full-width-of-rect erases (baked text redrawn live elsewhere).
	var extra: Array = spec.get("extra_erase", [])
	for er in extra:
		var rx0 := int(er[0] * s.x) - 2
		var ry0 := int(er[1] * s.y) - 2
		var rx1 := int(er[2] * s.x) + 2
		var ry1 := int(er[3] * s.y) + 2
		for y in range(maxi(ry0, 0), mini(ry1, s.y - 1) + 1):
			for x in range(maxi(rx0, 0), mini(rx1, s.x - 1) + 1):
				# Soft 6 px edge so the flat fill melts into the star field.
				var ex := minf(float(x - rx0), float(rx1 - x))
				var ey := minf(float(y - ry0), float(ry1 - y))
				var edge := minf(ex, ey)
				var t2 := 1.0 - smoothstep(0.0, 6.0, edge)
				var orig2 := img.get_pixel(x, y)
				img.set_pixel(x, y, orig2.lerp(bg, t2))
	img.save_png(abs_path)
	print("erased earth from %s (disc r=%.0f px, protected=%d, extra=%d, bg=%s)" % [path, r, protect.size(), extra.size(), bg])
	return true

func _sample_bg(img: Image, s: Vector2i) -> Color:
	# Average a couple of far corners — the artwork's empty space colour.
	var acc := Color(0.0, 0.0, 0.0, 1.0)
	var n := 0
	for patch in [Rect2i(6, 6, 24, 24), Rect2i(s.x - 30, 6, 24, 24), Rect2i(6, s.y - 30, 24, 24)]:
		for y in range(patch.position.y, patch.end.y):
			for x in range(patch.position.x, patch.end.x):
				acc += img.get_pixel(x, y)
				n += 1
	return acc / float(n)
