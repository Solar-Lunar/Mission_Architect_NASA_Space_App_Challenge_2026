extends SceneTree

## Visual QA for the reference-art dashboards.  Opens the real orbit scene,
## completes the arrival, then captures one rendered frame per mission mode
## (JPSS-2, SWOT, TEMPO) so the artwork swap can be inspected offline.

var frames := 0
var scene: Node = null
var t0 := 0
var stage := 0

func _initialize() -> void:
	var gm := root.get_node_or_null("GameManager")
	if gm == null:
		push_error("GameManager autoload unavailable")
		quit(1)
		return
	for mission in gm.missions:
		if mission.get("id", "") == "earth_climate":
			gm.current_mission = mission.duplicate(true)
			gm._init_spacecraft_config()
			break
	gm.current_phase = 4
	change_scene_to_file("res://scenes/orbit/orbit.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	if scene == null:
		scene = current_scene
		return false
	if frames == 35 and scene.has_method("_finish_orbit_arrival"):
		scene._finish_orbit_arrival()
		t0 = Time.get_ticks_msec()
	var ms := Time.get_ticks_msec() - t0
	match stage:
		0:
			# Wall-clock wait plus a frame gate: the Earth texture decode can
			# stall the first frames, so never shoot before the arrival skip.
			if frames > 60 and ms > 4000:
				_shot("jpss2")
				if scene.has_method("_on_dashboard_mission_selected"):
					scene._on_dashboard_mission_selected(1)  # SWOT
				stage = 1
		1:
			if ms > 9000:
				_shot("swot")
				if scene.has_method("_on_dashboard_mission_selected"):
					scene._on_dashboard_mission_selected(2)  # TEMPO
				stage = 2
		2:
			if ms > 14000:
				_shot("tempo")
				_finish()
				return true
	return false

func _shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex := root.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img != null and not img.is_empty():
		img.save_png("res://tools/_diag_dashboard_%s.png" % tag)

func _finish() -> void:
	var mode: String = str(scene.get("selected_scan_mode")) if scene else "n/a"
	var art_loaded := false
	var spot_count := 0
	var bg = scene.get("dashboard_background") if scene else null
	if bg != null:
		art_loaded = bg.texture != null and bg.visible
	var spots = scene.get("dashboard_hotspots") if scene else null
	if spots != null:
		spot_count = spots.size()
	var txt := "mode=%s art_loaded=%s hotspots=%s\n" % [mode, str(art_loaded), str(spot_count)]
	var file := FileAccess.open("res://tools/_verify_dashboard_art.txt", FileAccess.WRITE)
	file.store_string(txt)
	file.close()
	print(txt)
	quit(0)
