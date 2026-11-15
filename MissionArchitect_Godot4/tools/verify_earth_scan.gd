extends SceneTree

## Rendering QA for the Earth observation control room.  This opens the real
## orbit scene, lets the deployment cinematic complete, submits a SWOT task,
## validates the rendered UI/footprint nodes, and saves a frame for inspection.

var frames := 0
var scene: Node = null
var task_submitted := false
var results: Array[String] = []

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

func _check(label: String, ok: bool) -> void:
	results.append("[%s] %s" % ["PASS" if ok else "FAIL", label])

func _process(_delta: float) -> bool:
	frames += 1
	if scene == null:
		scene = current_scene
		return false
	# CI renders as fast as possible, so deliberately complete the timed arrival
	# after scene setup rather than relying on wall-clock animation duration.
	if frames == 35 and scene.has_method("_finish_orbit_arrival"):
		scene._finish_orbit_arrival()
	if frames == 50 and scene.has_method("_on_scan_target_pressed"):
		scene._on_scan_target_pressed(3) # SWOT / Amazon River Flood Pulse
		scene._on_request_scan_pressed()
		task_submitted = true
	if frames != 80:
		return false
	_check("Earth mission selected", root.get_node("GameManager").is_earth_climate_mission())
	_check("Control room dashboard visible", scene.get("control_room_dashboard") != null and scene.get("control_room_dashboard").visible)
	_check("SWOT task submitted", task_submitted and scene.get("selected_scan_mode") == "SWOT")
	_check("Sensor footprint rendered", scene.get("scan_beam") != null and scene.get("scan_beam").visible)
	# The normal renderer returns a viewport texture; CI's headless dummy driver
	# does not.  Save the actual rendered frame whenever one is available.
	var viewport_texture := root.get_texture()
	if DisplayServer.get_name() != "headless" and viewport_texture != null:
		var image := viewport_texture.get_image()
		if image != null and not image.is_empty():
			image.save_png("res://tools/_diag_earth_scan.png")
			_check("Rendered frame saved", true)
	var file := FileAccess.open("res://tools/_verify_earth_scan.txt", FileAccess.WRITE)
	file.store_string("\n".join(results) + "\n")
	file.close()
	print("\n".join(results))
	var failed := false
	for line in results:
		if "FAIL" in line:
			failed = true
	quit(1 if failed else 0)
	return false
