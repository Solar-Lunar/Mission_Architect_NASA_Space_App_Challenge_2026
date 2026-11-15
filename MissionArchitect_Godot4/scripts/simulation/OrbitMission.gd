## OrbitMission.gd
## The live orbital operations scene — satellite flying, mission control dashboard

extends Node3D

# ─── 3D Scene Nodes ───────────────────────────────────────────────────────────
var earth_sphere: MeshInstance3D
var earth_atmosphere: MeshInstance3D
var earth_clouds: MeshInstance3D
var satellite_node: Node3D
var satellite_visual: Node3D
var earth_node: Node3D
var satellite_mesh: MeshInstance3D
var solar_panel_l: MeshInstance3D
var solar_panel_r: MeshInstance3D
var orbit_path: MeshInstance3D
var ground_track: Node3D
var sun_light: DirectionalLight3D
var mission_camera: Camera3D
var orbit_camera: Camera3D

# ─── UI Nodes ─────────────────────────────────────────────────────────────────
var battery_bar: ProgressBar
var power_bar: ProgressBar
var science_bar: ProgressBar
var data_bar: ProgressBar
var battery_label: Label
var power_label: Label
var science_label: Label
var data_label: Label
var orbit_info: Label
var day_label: Label
var speed_label: Label
var eclipse_indicator: Label
var contact_indicator: Label
var event_log: VBoxContainer
var speed_btn_1x: Button
var speed_btn_10x: Button
var speed_btn_100x: Button
var transmit_btn: Button
var safemode_btn: Button
var end_mission_btn: Button
var orbital_map_panel: Control
var event_popup: PanelContainer
var event_popup_label: Label
var pause_menu: Control
var arrival_overlay: Control
var arrival_title: Label
var arrival_detail: Label
var arrival_fade: ColorRect
var rcs_thrusters: Array[MeshInstance3D] = []
var downlink_beam: MeshInstance3D
var scan_beam: MeshInstance3D
var solar_deployment: float = 0.0
var attitude_pulse: float = 0.0

# ─── State ────────────────────────────────────────────────────────────────────
var orbit_radius_3d: float = 3.5   # visual scale (Earth = radius 2)
var show_orbital_map: bool = false
var event_popup_timer: float = 0.0
var log_entries: Array = []
var arrival_active: bool = true
var arrival_timer: float = 0.0
var mars_operations: bool = false
var asteroid_operations: bool = false

# ─── Ground-station network + commissioning ────────────────────────────────────
# The scene and the simulation have to agree about where every station is and
# whether it can see the vehicle, or the picture contradicts the telemetry.  So
# the pins below are placed from the *same* functions the engine uses to decide
# contact, ride the *same* planet rotation, and the satellite itself is flown on
# the *same* sub-satellite direction — the beam is then simply a line between two
# points that both the model and the picture already know about.
var earth_surface_radius: float = 6.0
var stations_root: Node3D = null
var station_pins: Array[Node3D] = []
var station_halos: Array[MeshInstance3D] = []
const COMMISSION_TARGET_REVS: int = 2
var commissioning_active: bool = false
var commission_start_orbits: int = 0
var commission_revs_done: int = 0
var commission_passes: int = 0
var commission_mb: float = 0.0
var commission_complete: bool = false
var _last_contact: bool = false
var commission_overlay: Control = null
var commission_title: Label = null
var commission_detail: Label = null

# ─── Climate survey markers (Earth Climate Sentinel only) ─────────────────────
# One pin per real NASA-tracked event, placed with the same lat/lon→direction
# calibration as the ground stations so a marker sits on the actual place the
# headline happened.  They ride the planet's spin; the orbital plane does not,
# so the precessing ground track sweeps across them revolution by revolution.
var climate_root: Node3D = null
var climate_pins: Array[Node3D] = []
var climate_halos: Array[MeshInstance3D] = []

# ─── Capture flyover cinematic (Earth Climate Sentinel only) ─────────────────
# When the science model senses a real event, the camera flies to the exact
# lat/lon the marker sits on and a data card opens with the actual NASA
# WorldView scene — same pixel evidence a journalist would get, streamed
# live, cached for offline play, and degraded to numeric data when offline.
const ClimateMediaScript := preload("res://scripts/simulation/ClimateMedia.gd")
var climate_media: Node = null
var fly_time: float = 0.0
var fly_target: Dictionary = {}
var fly_pin: Node3D = null
var fly_panel: PanelContainer = null
var fly_image: TextureRect = null
var fly_title: Label = null
var fly_subtitle: Label = null
var fly_stat: Label = null
var fly_credit: Label = null
var fly_status: Label = null

# ─── Operator scan console (Earth Climate Sentinel only) ─────────────────────
var scan_console: PanelContainer = null
var scan_mode_label: Label = null
var scan_target_label: Label = null
var scan_status_label: Label = null
var scan_orbit_label: Label = null
var scan_link_label: Label = null
var payload_command_button: Button = null
var scan_mission_selector: OptionButton = null
var scan_dashboard_title: Label = null
var scan_right_status: Label = null
var scan_product_label: Label = null
var scan_objective_label: Label = null
var control_room_dashboard: Control = null
var scan_target_buttons: Array[Button] = []
var selected_scan_target: int = 0
var selected_scan_mode: String = "JPSS-2"
# ─── Reference-art dashboard (Earth Climate Sentinel only) ───────────────────
# Each mission shows its own designed control panel artwork full-screen; the
# interactive controls are invisible hotspots laid over the artwork's buttons.
var dashboard_background: TextureRect = null
var dashboard_hotspots: Array[Button] = []
var dashboard_accent: Color = Color(0.22, 0.85, 1.0)
var dashboard_live: Control = null

const DashboardLiveScript := preload("res://scripts/simulation/DashboardLive.gd")

const DASHBOARD_ART := {
	"JPSS-2": "res://assets/images/dashboard/dashboard_jpss2.png",
	"SWOT": "res://assets/images/dashboard/dashboard_swot.png",
	"TEMPO": "res://assets/images/dashboard/dashboard_tempo.png",
}
const DASHBOARD_ACCENTS := {
	"JPSS-2": Color(0.22, 0.85, 1.0),
	"SWOT": Color(0.25, 0.95, 0.92),
	"TEMPO": Color(0.65, 0.42, 1.0),
}
# Hotspot rects are fractions of the screen: [x, y, width, height], plus the
# command they trigger. Positions match the buttons drawn in each artwork.
const DASHBOARD_HOTSPOTS := {
	"JPSS-2": [
		{"r": [0.13, 0.075, 0.19, 0.095], "a": "cycle"},
		{"r": [0.012, 0.212, 0.244, 0.070], "a": "target"},
		{"r": [0.012, 0.288, 0.244, 0.070], "a": "target"},
		{"r": [0.012, 0.363, 0.244, 0.070], "a": "target"},
		{"r": [0.012, 0.438, 0.244, 0.070], "a": "target"},
		{"r": [0.514, 0.848, 0.092, 0.108], "a": "target"},
		{"r": [0.626, 0.848, 0.092, 0.108], "a": "scan"},
		{"r": [0.736, 0.848, 0.092, 0.108], "a": "downlink"},
		{"r": [0.840, 0.848, 0.084, 0.108], "a": "scan"},
		{"r": [0.928, 0.848, 0.070, 0.108], "a": "scan"},
	],
	"SWOT": [
		{"r": [0.088, 0.085, 0.13, 0.08], "a": "cycle"},
		{"r": [0.056, 0.755, 0.17, 0.075], "a": "target"},
		{"r": [0.236, 0.748, 0.228, 0.088], "a": "scan"},
		{"r": [0.475, 0.755, 0.145, 0.075], "a": "downlink"},
	],
	"TEMPO": [
		{"r": [0.005, 0.085, 0.24, 0.125], "a": "cycle"},
		{"r": [0.015, 0.896, 0.095, 0.07], "a": "menu"},
		{"r": [0.12, 0.896, 0.148, 0.07], "a": "select_region"},
		{"r": [0.272, 0.896, 0.168, 0.07], "a": "scan_pollution"},
		{"r": [0.443, 0.896, 0.166, 0.07], "a": "compare_hours"},
		{"r": [0.656, 0.896, 0.153, 0.07], "a": "no2_column"},
		{"r": [0.82, 0.896, 0.172, 0.07], "a": "ozone_monitoring"},
	],
}
const DASHBOARD_HOTSPOT_TIPS := {
	"scan": "Run the acquisition scan with this mission's payload",
	"downlink": "Downlink collected data to the ground station",
	"target": "Select the next NASA observation target",
	"menu": "Return to the main menu",
	"cycle": "Switch mission (Tab)",
	"select_region": "Cycle to the next NASA EONET incident region",
	"scan_pollution": "Force a fresh TEMPO NO₂ scan for the current region",
	"compare_hours": "Compare NO₂ columns across two hourly scans",
	"no2_column": "Inspect the NO₂ vertical column density panel",
	"ozone_monitoring": "Toggle the ozone (O₃) monitoring panel",
}

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# 3D nodes
	earth_sphere      = _g("Earth/EarthMesh")
	earth_atmosphere  = _g("Earth/AtmosphereMesh")
	satellite_node    = _g("Satellite")
	satellite_visual  = _g("Satellite/SatelliteModel")
	earth_node        = _g("Earth")
	satellite_mesh    = _g("Satellite/SatMesh")
	solar_panel_l     = _g("Satellite/SolarPanelL")
	solar_panel_r     = _g("Satellite/SolarPanelR")
	orbit_path        = _g("OrbitPath")
	sun_light         = _g("SunLight")
	mission_camera    = _g("MissionCamera")
	orbit_camera      = _g("OrbitCamera")

	# UI nodes
	battery_bar       = _g("UI/TelemetryPanel/VBox/BatteryBar")
	power_bar         = _g("UI/TelemetryPanel/VBox/PowerBar")
	science_bar       = _g("UI/TelemetryPanel/VBox/ScienceBar")
	data_bar          = _g("UI/TelemetryPanel/VBox/DataBar")
	battery_label     = _g("UI/TelemetryPanel/VBox/BatteryLabel")
	power_label       = _g("UI/TelemetryPanel/VBox/PowerLabel")
	science_label     = _g("UI/TelemetryPanel/VBox/ScienceLabel")
	data_label        = _g("UI/TelemetryPanel/VBox/DataLabel")
	orbit_info        = _g("UI/TelemetryPanel/VBox/OrbitInfoLabel")
	day_label         = _g("UI/HUD/DayLabel")
	speed_label       = _g("UI/HUD/SpeedLabel")
	eclipse_indicator = _g("UI/HUD/EclipseIndicator")
	contact_indicator = _g("UI/HUD/ContactIndicator")
	event_log         = _g("UI/EventLog/ScrollContainer/EventList")
	speed_btn_1x      = _g("UI/Controls/Speed1x")
	speed_btn_10x     = _g("UI/Controls/Speed10x")
	speed_btn_100x    = _g("UI/Controls/Speed100x")
	transmit_btn      = _g("UI/Controls/TransmitButton")
	safemode_btn      = _g("UI/Controls/SafeModeButton")
	end_mission_btn   = _g("UI/Controls/EndMissionButton")
	orbital_map_panel = _g("UI/OrbitalMapPanel")
	event_popup       = _g("UI/EventPopup")
	event_popup_label = _g("UI/EventPopup/EventLabel")
	pause_menu        = _g("UI/PauseMenu")
	arrival_overlay   = _g("UI/ArrivalOverlay")
	arrival_title     = _g("UI/ArrivalOverlay/ArrivalText/Title")
	arrival_detail    = _g("UI/ArrivalOverlay/ArrivalText/Detail")

	# Connect buttons
	if speed_btn_1x:    speed_btn_1x.pressed.connect(_on_speed_1x_pressed)
	if speed_btn_10x:   speed_btn_10x.pressed.connect(_on_speed_10x_pressed)
	if speed_btn_100x:  speed_btn_100x.pressed.connect(_on_speed_100x_pressed)
	var s1000 = _g("UI/Controls/Speed1000x")
	if s1000: s1000.pressed.connect(_on_speed_1000x_pressed)
	if transmit_btn:    transmit_btn.pressed.connect(_on_transmit_pressed)
	if safemode_btn:    safemode_btn.pressed.connect(_on_safemode_pressed)
	if end_mission_btn: end_mission_btn.pressed.connect(_on_end_mission_pressed)
	var resume_btn = _g("UI/PauseMenu/PauseVBox/ResumeButton")
	if resume_btn: resume_btn.pressed.connect(_on_resume_pressed)
	var quit_btn = _g("UI/PauseMenu/PauseVBox/QuitToMenuButton")
	if quit_btn: quit_btn.pressed.connect(_on_quit_to_menu_pressed)

	if orbital_map_panel: orbital_map_panel.hide()
	if event_popup: event_popup.hide()
	if pause_menu: pause_menu.hide()

	mars_operations = GameManager.is_mars_mission()
	asteroid_operations = GameManager.is_asteroid_mission()
	_setup_earth()
	_setup_orbit_path()
	if mars_operations and sun_light:
		sun_light.light_color = Color(1.0, 0.72, 0.48, 1.0)
		sun_light.light_energy = 1.55
	elif asteroid_operations and sun_light:
		sun_light.light_color = Color(0.92, 0.86, 0.72, 1.0)
		sun_light.light_energy = 1.35
	_setup_satellite_visuals()
	_create_starfield()
	if not mars_operations and not asteroid_operations:
		_build_ground_stations()
	if GameManager.is_earth_climate_mission():
		_build_climate_targets()
		_build_climate_flyover_ui()
		_build_scan_console()
	_create_arrival_fade()
	_begin_orbit_arrival()

	SimulationEngine.start_simulation(randi())
	SimulationEngine.state_updated.connect(_on_state_updated)
	SimulationEngine.event_occurred.connect(_on_event_occurred)
	SimulationEngine.mission_ended.connect(_on_mission_ended)

	_update_speed_buttons(1)
	print("[OrbitMission] Ready")

func _g(path: String) -> Node:
	if has_node(path): return get_node(path)
	return null

# ─── Earth Setup ─────────────────────────────────────────────────────────────
func _setup_earth() -> void:
	# A separate, slowly moving cloud shell keeps the NASA Blue Marble surface
	# readable while giving Earth a living, weather-scale layer.
	if not earth_node: return
	if asteroid_operations:
		if earth_sphere:
			var asteroid_shader := Shader.new()
			asteroid_shader.code = "shader_type spatial;\nrender_mode diffuse_burley, specular_schlick_ggx;\nfloat hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }\nfloat noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y); }\nvoid vertex(){ float rough=sin(VERTEX.x*8.0+VERTEX.y*5.0)*sin(VERTEX.z*7.0+VERTEX.x*3.0); VERTEX += NORMAL*rough*0.055; }\nvoid fragment(){ vec2 uv=UV; float n=noise(uv*13.0)+0.45*noise(uv*31.0)+0.2*noise(uv*67.0); float pits=smoothstep(0.58,0.82,noise(uv*42.0)); vec3 rock=mix(vec3(0.12,0.095,0.075),vec3(0.43,0.32,0.22),smoothstep(0.42,1.0,n)); rock*=1.0-pits*0.32; ALBEDO=rock; ROUGHNESS=0.94; METALLIC=0.0; EMISSION=rock*0.025; }"
			var asteroid_material := ShaderMaterial.new()
			asteroid_material.shader = asteroid_shader
			earth_sphere.material_override = asteroid_material
			earth_sphere.scale = Vector3(1.25, 0.92, 1.08)
		if earth_atmosphere:
			earth_atmosphere.hide()
		if earth_clouds:
			earth_clouds.hide()
		return
	# Use one simple unshaded material for the NASA texture. This intentionally
	# avoids custom surface shader fallbacks while the presentation is verified.
	if earth_sphere:
		if mars_operations:
			var mars_shader := Shader.new()
			mars_shader.code = "shader_type spatial;\nrender_mode unshaded;\nfloat hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }\nfloat noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y); }\nvoid fragment(){ vec2 uv=UV; float n=noise(uv*6.0)+0.5*noise(uv*14.0)+0.25*noise(uv*32.0); float polar=smoothstep(0.32,0.46,abs(uv.y-0.5)); vec3 rust=mix(vec3(0.42,0.18,0.08), vec3(0.78,0.42,0.18), n); vec3 dark=mix(vec3(0.18,0.08,0.04), vec3(0.34,0.16,0.08), n); vec3 land=mix(dark, rust, smoothstep(0.35,1.05,n)); vec3 ice=vec3(0.86,0.88,0.92); ALBEDO=mix(land, ice, polar*0.85); EMISSION=ALBEDO*0.22; }"
			var mars_mat := ShaderMaterial.new()
			mars_mat.shader = mars_shader
			earth_sphere.material_override = mars_mat
			earth_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if earth_atmosphere:
				var atmo := StandardMaterial3D.new()
				atmo.albedo_color = Color(0.72, 0.32, 0.12, 0.10)
				atmo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				atmo.cull_mode = BaseMaterial3D.CULL_FRONT
				atmo.emission_enabled = true
				atmo.emission = Color(0.55, 0.18, 0.05, 1.0)
				atmo.emission_energy_multiplier = 0.22
				earth_atmosphere.material_override = atmo
		else:
			var earth_texture := load("res://assets/textures/nasa-blue-marble-2048.png") as Texture2D
			if earth_texture:
				var earth_mat := StandardMaterial3D.new()
				earth_mat.albedo_texture = earth_texture
				earth_mat.albedo_color = Color.WHITE
				earth_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				earth_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				earth_mat.emission_enabled = true
				earth_mat.emission_texture = earth_texture
				earth_mat.emission = Color(0.16, 0.22, 0.42, 1.0)
				earth_mat.emission_energy_multiplier = 0.32
				earth_sphere.material_override = earth_mat
				earth_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	earth_clouds = MeshInstance3D.new()
	earth_clouds.name = "DynamicCloudLayer"
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radius = 1.0
	cloud_mesh.height = 2.0
	earth_clouds.mesh = cloud_mesh
	earth_clouds.scale = Vector3.ONE * 6.075
	var cloud_shader := Shader.new()
	cloud_shader.code = "shader_type spatial;\nrender_mode blend_mix, cull_back, unshaded;\nfloat hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }\nfloat noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y); }\nvoid fragment(){ vec2 uv=UV; uv.x += TIME*0.0018; float n=noise(uv*8.0)+0.5*noise(uv*19.0)+0.25*noise(uv*38.0); float clouds=smoothstep(1.03,1.38,n)*(0.52-smoothstep(0.40,0.51,abs(uv.y-0.5))); ALBEDO=vec3(0.82,0.91,1.0); EMISSION=vec3(0.12,0.18,0.30)*clouds; ALPHA=clouds*0.56; }"
	var cloud_mat := ShaderMaterial.new()
	cloud_mat.shader = cloud_shader
	earth_clouds.material_override = cloud_mat
	earth_node.add_child(earth_clouds)
	# The procedural cloud mask is intentionally kept off until it has a proper
	# cloud texture. Its current noise threshold can blanket the whole planet in
	# white and destroy the Blue Marble surface.
	earth_clouds.hide()

	# The beam is only shown during a real simulated ground-station pass.
	# It terminates at the nadir point beneath the spacecraft rather than
	# floating decoratively in space.
	downlink_beam = MeshInstance3D.new()
	downlink_beam.name = "ActiveGroundStationDownlink"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.018
	beam_mesh.bottom_radius = 0.052
	beam_mesh.height = 2.0
	beam_mesh.radial_segments = 12
	downlink_beam.mesh = beam_mesh
	var beam_mat := StandardMaterial3D.new()
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(0.08, 0.82, 1.0, 0.42)
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(0.04, 0.65, 1.0, 1.0)
	beam_mat.emission_energy_multiplier = 2.8
	downlink_beam.material_override = beam_mat
	downlink_beam.hide()
	add_child(downlink_beam)
	# A separate nadir-pointing footprint is the active sensor, not a comms
	# link.  It appears only after an operator has tasked a geographic scan.
	scan_beam = MeshInstance3D.new()
	scan_beam.name = "ActiveSensorFootprint"
	var scan_mesh := CylinderMesh.new()
	scan_mesh.top_radius = 0.025
	scan_mesh.bottom_radius = 0.23
	scan_mesh.height = 2.0
	scan_mesh.radial_segments = 24
	scan_beam.mesh = scan_mesh
	var scan_mat := StandardMaterial3D.new()
	scan_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scan_mat.albedo_color = Color(0.1, 0.9, 1.0, 0.24)
	scan_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scan_mat.emission_enabled = true
	scan_mat.emission = Color(0.05, 0.75, 1.0, 1.0)
	scan_mat.emission_energy_multiplier = 2.4
	scan_beam.material_override = scan_mat
	scan_beam.hide()
	add_child(scan_beam)

func _setup_orbit_path() -> void:
	# Orbit radius based on mission altitude — scene material already set
	var alt: float = GameManager.current_mission.get("altitude_km", 550)
	var body_r: float = 3389.5 if mars_operations else 6371.0
	var scale_3d: float = 2.4 if asteroid_operations else 6.0 + (alt / body_r) * 3.0
	orbit_radius_3d = scale_3d
	if orbit_path:
		# An orbit is a trajectory, not a glowing hula hoop. Keep it for a future
		# tactical map, but never render it in the cinematic exterior shot.
		orbit_path.hide()

func _setup_satellite_visuals() -> void:
	# Add explicit deployable arrays around the imported bus model. The model
	# remains the spacecraft body while these panels communicate mission state.
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.015, 0.07, 0.34, 1.0)
	panel_mat.metallic = 0.55
	panel_mat.roughness = 0.28
	panel_mat.emission_enabled = true
	panel_mat.emission = Color(0.015, 0.05, 0.22, 1.0)
	panel_mat.emission_energy_multiplier = 0.55
	for panel in [solar_panel_l, solar_panel_r]:
		if panel:
			var panel_mesh := BoxMesh.new()
			panel_mesh.size = Vector3(3.2, 0.045, 0.62)
			panel.mesh = panel_mesh
			panel.show()
			panel.material_override = panel_mat
			panel.scale = Vector3(0.06, 1.0, 1.0)
	# An Earth-observation payload aperture makes the satellite's purpose legible
	# in close shots instead of reading as an anonymous cube with solar panels.
	if satellite_node:
		var payload_camera := MeshInstance3D.new()
		payload_camera.name = "AsteroidCompositionImager" if asteroid_operations else "MarsClimateImager" if mars_operations else "EarthObservationCamera"
		var camera_mesh := CylinderMesh.new()
		camera_mesh.top_radius = 0.14
		camera_mesh.bottom_radius = 0.20
		camera_mesh.height = 0.30
		camera_mesh.radial_segments = 20
		payload_camera.mesh = camera_mesh
		payload_camera.position = Vector3(0.0, -0.28, 0.08)
		payload_camera.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		var lens_mat := StandardMaterial3D.new()
		lens_mat.albedo_color = Color(0.008, 0.025, 0.055, 1.0)
		lens_mat.metallic = 0.75
		lens_mat.roughness = 0.12
		lens_mat.emission_enabled = true
		lens_mat.emission = Color(0.01, 0.10, 0.18, 1.0)
		lens_mat.emission_energy_multiplier = 0.8
		payload_camera.material_override = lens_mat
		satellite_node.add_child(payload_camera)
	_create_rcs_thrusters()

func _create_rcs_thrusters() -> void:
	if not satellite_node: return
	var rcs_mat := StandardMaterial3D.new()
	rcs_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rcs_mat.emission_enabled = true
	rcs_mat.emission = Color(0.35, 0.72, 1.0, 1.0)
	rcs_mat.emission_energy_multiplier = 4.0
	for x in [-0.22, 0.22]:
		var puff := MeshInstance3D.new()
		puff.name = "RCSPuff"
		var mesh := SphereMesh.new()
		mesh.radius = 0.07
		mesh.height = 0.14
		puff.mesh = mesh
		puff.position = Vector3(x, 0.0, 0.32)
		puff.material_override = rcs_mat
		puff.hide()
		satellite_node.add_child(puff)
		rcs_thrusters.append(puff)

func _update_satellite_operations(delta: float, angle_rad: float) -> void:
	if not satellite_node: return
	# Earth-pointing attitude for an observation satellite, with small periodic
	# reaction-control corrections rather than an inert static model.
	satellite_node.look_at(Vector3.ZERO, Vector3.UP)
	attitude_pulse += delta * SimulationEngine.time_scale
	var correcting: bool = fmod(attitude_pulse, 8.0) < 0.16
	for puff in rcs_thrusters:
		puff.visible = correcting
		if correcting: puff.scale = Vector3.ONE * (0.7 + sin(attitude_pulse * 42.0) * 0.25)

	# Arrays track the sun when available; in eclipse they retain attitude and
	# the satellite visibly darkens with its real power-generation state.
	var in_eclipse: bool = SimulationEngine.state.get("in_eclipse", false)
	var target_panel_angle: float = 0.0 if not in_eclipse else 0.25
	for panel in [solar_panel_l, solar_panel_r]:
		if panel:
			panel.scale.x = lerpf(panel.scale.x, solar_deployment, min(delta * 1.8, 1.0))
			panel.rotation.z = lerpf(panel.rotation.z, target_panel_angle, min(delta * 1.4, 1.0))
			var panel_mat := panel.material_override as StandardMaterial3D
			if panel_mat:
				panel_mat.emission_energy_multiplier = 0.15 if in_eclipse else 0.85
	_update_downlink_visual()
	_update_scan_beam()

func _update_scan_beam() -> void:
	if scan_beam == null or satellite_node == null:
		return
	if not GameManager.is_earth_climate_mission() or int(SimulationEngine.state.get("active_scan_target", -1)) < 0:
		scan_beam.hide()
		return
	var from: Vector3 = satellite_node.global_position
	var to: Vector3 = from.normalized() * earth_surface_radius * 1.012
	var direction := to - from
	var length := direction.length()
	if length < 0.1:
		scan_beam.hide()
		return
	var up_axis := Vector3.UP if abs(direction.normalized().dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	scan_beam.show()
	scan_beam.global_position = (from + to) * 0.5
	scan_beam.basis = Basis.looking_at(direction.normalized(), up_axis) * Basis(Vector3.RIGHT, -PI * 0.5)
	scan_beam.scale = Vector3(1.0, length * 0.5, 1.0)
	var mat := scan_beam.material_override as StandardMaterial3D
	if mat:
		var swot: bool = String(SimulationEngine.state.get("scan_mode", "JPSS-2")) == "SWOT"
		mat.emission = Color(0.18, 0.45, 1.0) if swot else Color(0.08, 1.0, 0.55)
		mat.albedo_color = Color(0.18, 0.45, 1.0, 0.26) if swot else Color(0.08, 1.0, 0.55, 0.24)

func _update_downlink_visual() -> void:
	if not downlink_beam or not satellite_node:
		return
	if asteroid_operations:
		downlink_beam.hide()
		return
	var spacecraft_pos: Vector3 = satellite_node.global_position
	var station_pos: Vector3
	if mars_operations:
		# Deep-space operations keep the simplified contact model; there is no
		# local station network to point at, so the beam stands in for the long
		# link home and terminates at the sub-spacecraft point.
		if not SimulationEngine.state.get("ground_contact", false):
			downlink_beam.hide()
			return
		station_pos = spacecraft_pos.normalized() * earth_surface_radius * 1.02
	else:
		# The beam runs to whichever station the *simulation* currently sees the
		# vehicle above — the very same best_visible_station() that moves the
		# telemetry — so the line on screen is the reason the number on screen is
		# climbing.  It used to aim straight down at the point beneath the craft,
		# which is not a station and does not receive anything.  Eclipse no longer
		# hides it either: a dish on the night side still sees the satellite, and
		# the contact model never stopped downloading in shadow, so neither does
		# the picture.
		var alt: float = float(GameManager.current_mission.get("altitude_km", 550))
		var visible: Dictionary = SimulationEngine.best_visible_station(alt)
		if visible.is_empty():
			downlink_beam.hide()
			return
		var station_dir: Vector3 = visible.get("direction", Vector3.ZERO)
		if station_dir.length_squared() < 0.01:
			downlink_beam.hide()
			return
		station_pos = station_dir.normalized() * earth_surface_radius
	var direction := station_pos - spacecraft_pos
	var beam_length := direction.length()
	if beam_length < 0.1:
		downlink_beam.hide()
		return
	var up_axis := Vector3.UP if abs(direction.normalized().dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	downlink_beam.show()
	downlink_beam.global_position = (spacecraft_pos + station_pos) * 0.5
	# Cylinder meshes run along local Y. Looking-at aligns -Z, then the local
	# X rotation turns that axis into the actual spacecraft-to-ground vector.
	downlink_beam.basis = Basis.looking_at(direction.normalized(), up_axis) * Basis(Vector3.RIGHT, -PI * 0.5)
	downlink_beam.scale = Vector3(1.0, beam_length * 0.5, 1.0)

# ─── Ground-station network ───────────────────────────────────────────────────
## One marker per real station in the network, placed from the same
## lat/lon→direction function the simulation uses to decide contact.  They are
## children of the globe's own frame, so as the planet turns the dishes turn with
## it and stay over their continents, and the downlink beam — which is aimed with
## that identical function — always lands on the pin it claims to be talking to.
func _build_ground_stations() -> void:
	if not earth_node:
		return
	stations_root = Node3D.new()
	stations_root.name = "GroundStationNetwork"
	earth_node.add_child(stations_root)
	for station in SimulationEngine.GROUND_STATIONS:
		var lat: float = float(station["lat"])
		var lon: float = float(station["lon"])
		var dir: Vector3 = SimulationEngine.station_local_direction(lat, lon)
		var pin := Node3D.new()
		pin.name = "Station_" + String(station["name"])
		pin.position = dir * earth_surface_radius
		stations_root.add_child(pin)
		# A short mast stood up on the local vertical, so each site reads as an
		# installed dish rather than a dot painted onto the map.
		var mast := MeshInstance3D.new()
		mast.name = "Mast"
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.015
		mast_mesh.bottom_radius = 0.055
		mast_mesh.height = 0.24
		mast_mesh.radial_segments = 8
		mast.mesh = mast_mesh
		var mmat := StandardMaterial3D.new()
		mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mmat.albedo_color = Color(0.80, 0.87, 1.0)
		mast.material_override = mmat
		mast.position = dir * 0.12
		mast.basis = Basis(Quaternion(Vector3.UP, dir))
		pin.add_child(mast)
		# A halo that brightens green for exactly as long as this station can see
		# the vehicle — the pass on the globe and the pass in the telemetry are the
		# same event, seen two ways.
		var halo := MeshInstance3D.new()
		halo.name = "ContactHalo"
		var hmesh := SphereMesh.new()
		hmesh.radius = 0.09
		hmesh.height = 0.18
		halo.mesh = hmesh
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.albedo_color = Color(0.35, 0.6, 1.0, 0.3)
		hmat.emission_enabled = true
		hmat.emission = Color(0.3, 0.6, 1.0)
		hmat.emission_energy_multiplier = 0.5
		halo.material_override = hmat
		halo.position = dir * 0.26
		pin.add_child(halo)
		var tag := Label3D.new()
		tag.text = String(station["name"])
		tag.font_size = 30
		tag.outline_size = 12
		tag.pixel_size = 0.012
		tag.modulate = Color(0.65, 0.9, 1.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = dir * 0.55
		pin.add_child(tag)
		station_pins.append(pin)
		station_halos.append(halo)

## Repaint the network every frame from the live elevation of each station, so a
## dish glows only while it genuinely holds the satellite above ten degrees.
func _update_station_visuals() -> void:
	var alt: float = float(GameManager.current_mission.get("altitude_km", 550))
	var stations: Array = SimulationEngine.GROUND_STATIONS
	for i in range(station_halos.size()):
		if i >= stations.size():
			break
		var halo: MeshInstance3D = station_halos[i]
		var mat := halo.material_override as StandardMaterial3D
		if mat == null:
			continue
		var el: float = SimulationEngine.station_elevation_deg(stations[i], alt)
		var holds: bool = el >= SimulationEngine.MIN_ELEVATION_DEG
		mat.emission = Color(0.2, 0.95, 0.5) if holds else Color(0.3, 0.6, 1.0)
		mat.emission_energy_multiplier = 3.4 if holds else 0.5
		mat.albedo_color.a = 0.9 if holds else 0.25
		var s: float = 1.35 if holds else 0.75
		halo.scale = Vector3.ONE * s

## One pin per real climate event, placed from the same lat/lon→direction
## calibration the stations and the simulation use, so the wildfire marker is
## genuinely over Canada and the SO₂ marker genuinely over Iceland.  Unobserved
## targets pulse cyan; once the simulation captures one it locks to green — the
## survey progress on the globe is the survey progress in the telemetry.
func _build_climate_targets() -> void:
	if not earth_node or not stations_root:
		return
	climate_root = Node3D.new()
	climate_root.name = "ClimateSurveyTargets"
	earth_node.add_child(climate_root)
	for t in SimulationEngine.CLIMATE_TARGETS:
		var dir: Vector3 = SimulationEngine.station_local_direction(float(t["lat"]), float(t["lon"]))
		var pin := Node3D.new()
		pin.name = "Target_" + String(t["name"]).replace(" ", "_")
		pin.position = dir * earth_surface_radius * 1.005
		climate_root.add_child(pin)
		var halo := MeshInstance3D.new()
		halo.name = "SurveyHalo"
		var hmesh := SphereMesh.new()
		hmesh.radius = 0.075
		hmesh.height = 0.15
		halo.mesh = hmesh
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.albedo_color = Color(0.2, 0.85, 1.0, 0.75)
		hmat.emission_enabled = true
		hmat.emission = Color(0.15, 0.75, 1.0)
		hmat.emission_energy_multiplier = 2.0
		halo.material_override = hmat
		halo.position = dir * 0.03
		pin.add_child(halo)
		var tag := Label3D.new()
		tag.text = "◉ " + String(t["name"])
		tag.font_size = 24
		tag.outline_size = 10
		tag.pixel_size = 0.010
		tag.modulate = Color(0.55, 0.9, 1.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = dir * 0.42
		pin.add_child(tag)
		climate_pins.append(pin)
		climate_halos.append(halo)

## Repaint the survey pins from the simulation's own capture state every frame,
## so "observed" means observed by the science model — not by a separate guess.
func _update_climate_target_visuals() -> void:
	var targets: Array = SimulationEngine.state.get("climate_targets", [])
	var pulse: float = sin(Time.get_ticks_msec() * 0.004) * 0.5 + 0.5
	for i in range(climate_halos.size()):
		if i >= targets.size():
			break
		var captured: bool = bool(targets[i].get("captured", false))
		var mat := climate_halos[i].material_override as StandardMaterial3D
		if mat == null:
			continue
		if captured:
			mat.emission = Color(0.2, 0.95, 0.45)
			mat.albedo_color = Color(0.35, 1.0, 0.55, 0.95)
			mat.emission_energy_multiplier = 3.2
			climate_halos[i].scale = Vector3.ONE * 1.3
			for c in climate_pins[i].get_children():
				if c is Label3D:
					(c as Label3D).text = "✅ " + String(targets[i]["name"])
					(c as Label3D).modulate = Color(0.55, 1.0, 0.65)
		else:
			mat.emission = Color(0.15, 0.75, 1.0)
			mat.albedo_color = Color(0.2, 0.85, 1.0, 0.4 + pulse * 0.4)
			mat.emission_energy_multiplier = 1.2 + pulse * 1.6
			climate_halos[i].scale = Vector3.ONE * (0.85 + pulse * 0.35)

# ─── Commissioning: the two climate-survey revolutions ────────────────────────
## Once the satellite is deployed it does not simply hand over to the free-running
## simulation: the first thing a climate sentinel must prove is that it can come
## all the way round twice and get its observations off to the ground.  So the
## operations screen opens on that, flown at 600× so two ninety-five-minute
## revolutions read as twenty seconds of film rather than three hours of waiting,
## and said out loud on the banner because a clock that names its own compression
## is honest and one that hides it is not.
func _begin_commissioning() -> void:
	if mars_operations or asteroid_operations:
		return
	if commissioning_active or commission_complete:
		return
	commissioning_active = true
	commission_start_orbits = int(SimulationEngine.state.get("total_orbits", 0))
	commission_revs_done = 0
	commission_passes = 0
	commission_mb = 0.0
	_last_contact = bool(SimulationEngine.state.get("ground_contact", false))
	_build_commissioning_overlay()
	if commission_overlay:
		commission_overlay.show()
	SimulationEngine.set_time_scale(3)   # 600× — TIME_SCALES index 3
	_update_speed_buttons(3)

func _update_commissioning() -> void:
	var orbits: int = int(SimulationEngine.state.get("total_orbits", 0))
	commission_revs_done = orbits - commission_start_orbits
	# A downlink is complete when the station loses the vehicle: everything the
	# dish collected between acquisition and loss came off in that one pass.
	var contact: bool = bool(SimulationEngine.state.get("ground_contact", false))
	if _last_contact and not contact:
		commission_passes += 1
	_last_contact = contact
	commission_mb = float(SimulationEngine.state.get("data_transmitted_mb", 0.0))
	if commission_overlay and commission_title and commission_detail:
		var rev: int = clampi(commission_revs_done + 1, 1, COMMISSION_TARGET_REVS)
		commission_title.text = "CLIMATE SURVEY COMMISSIONING — REVOLUTION %d OF %d" % [rev, COMMISSION_TARGET_REVS]
		var st_name: String = String(SimulationEngine.state.get("ground_station_name", ""))
		if st_name == "":
			st_name = "no station in view"
		commission_detail.text = "Now talking to %s   ·   Passes returned: %d   ·   Climate data downlinked: %.0f MB   ·   600× time" % [
			st_name, commission_passes, commission_mb]
	if commission_revs_done >= COMMISSION_TARGET_REVS:
		_finish_commissioning()

func _finish_commissioning() -> void:
	commissioning_active = false
	commission_complete = true
	SimulationEngine.state["commission_revolutions"] = commission_revs_done
	SimulationEngine.state["commission_passes"] = commission_passes
	GameManager.simulation_state["climate_commissioning_complete"] = true
	GameManager.simulation_state["commission_revolutions"] = commission_revs_done
	GameManager.simulation_state["commission_ground_passes"] = commission_passes
	if commission_title:
		commission_title.text = "COMMISSIONING COMPLETE"
	if commission_detail:
		commission_detail.text = "Two revolutions flown, %d station passes, %.0f MB of climate data returned to Earth." % [
			commission_passes, commission_mb]
	SimulationEngine._log_event("✅ Commissioning complete — %d revolutions, climate data returned from the ground-station network." %
		commission_revs_done, "success")
	_collapse_commission_overlay.call_deferred()

## Leave the finished banner up long enough to be read, then take it away so the
## operator's own dashboard is not permanently covered by a message that has
## already been delivered.
func _collapse_commission_overlay() -> void:
	await get_tree().create_timer(5.0).timeout
	if commission_overlay:
		commission_overlay.hide()

func _build_commissioning_overlay() -> void:
	if commission_overlay:
		return
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	commission_overlay = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.06, 0.12, 0.82)
	box.border_color = Color(0.35, 0.85, 1.0, 0.8)
	box.set_border_width_all(1)
	box.set_content_margin_all(14)
	commission_overlay.add_theme_stylebox_override("panel", box)
	layer.add_child(commission_overlay)
	commission_overlay.set_anchors_preset(Control.PRESET_TOP_WIDE)
	commission_overlay.offset_left = 0.0
	commission_overlay.offset_right = 0.0
	commission_overlay.offset_top = 96.0
	commission_overlay.offset_bottom = 96.0 + 96.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	commission_overlay.add_child(v)
	commission_title = Label.new()
	commission_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	commission_title.add_theme_font_size_override("font_size", 22)
	commission_title.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	v.add_child(commission_title)
	commission_detail = Label.new()
	commission_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	commission_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	commission_detail.add_theme_font_size_override("font_size", 15)
	commission_detail.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	v.add_child(commission_detail)
	commission_overlay.hide()

func _create_starfield() -> void:
	# Low-cost hand-placed stars give depth without a large panorama texture.
	# They are intentionally subtle so they do not compete with Earth or the HUD.
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.025
	star_mesh.height = 0.05
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(0.72, 0.82, 1.0, 1.0)
	star_mat.emission_enabled = true
	star_mat.emission = Color(0.32, 0.52, 1.0, 1.0)
	star_mat.emission_energy_multiplier = 1.8
	star_mesh.material = star_mat
	var stars := Node3D.new()
	stars.name = "CinematicStarfield"
	add_child(stars)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	for i in 120:
		var star := MeshInstance3D.new()
		star.mesh = star_mesh
		var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.65, 0.65), rng.randf_range(-1.0, 1.0)).normalized()
		star.position = direction * rng.randf_range(22.0, 36.0)
		var s := rng.randf_range(0.65, 2.2)
		star.scale = Vector3.ONE * s
		stars.add_child(star)

func _begin_orbit_arrival() -> void:
	# The operations screen is intentionally withheld until the player has seen
	# their spacecraft reach orbit and separate from the launch vehicle.
	arrival_active = true
	arrival_timer = 0.0
	_set_operations_visible(false)
	if arrival_overlay: arrival_overlay.show()
	if mission_camera:
		mission_camera.position = Vector3(0.0, 3.0, 24.0)
		mission_camera.fov = 48.0
		mission_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

func _create_arrival_fade() -> void:
	# The launch scene finishes on black. Fade this matching orbital view in so
	# the player perceives one continuous mission rather than a scene switch.
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	arrival_fade = ColorRect.new()
	arrival_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrival_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrival_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	layer.add_child(arrival_fade)

func _finish_orbit_arrival() -> void:
	arrival_active = false
	if arrival_overlay: arrival_overlay.hide()
	if scan_console: scan_console.hide()
	if control_room_dashboard: control_room_dashboard.show()
	_set_operations_visible(true)
	if mission_camera:
		# Clear complete-Earth shot. It is deliberately pulled back from the
		# satellite rather than attempting an extreme close external camera.
		mission_camera.position = Vector3(-11.5, 7.5, 14.5)
		mission_camera.fov = 60.0
		mission_camera.look_at(Vector3.ZERO, Vector3.UP)
	# The deployment is not the end of the story for a climate satellite: it has
	# to prove it can circle the planet and get the data home.  Open on that.
	_begin_commissioning()

func _set_operations_visible(is_visible: bool) -> void:
	# Earth Sentinel has its own dedicated mission-control workstation.  Leaving
	# the generic telemetry and bottom action bar visible beneath it made the
	# screen read like overlapping debug windows rather than a control room.
	if GameManager.is_earth_climate_mission():
		for path in ["UI/HUD", "UI/TelemetryPanel", "UI/EventLog", "UI/Controls"]:
			var climate_node := _g(path) as CanvasItem
			if climate_node: climate_node.visible = false
		return
	for path in ["UI/HUD", "UI/TelemetryPanel", "UI/EventLog", "UI/Controls"]:
		var node := _g(path) as CanvasItem
		if node: node.visible = is_visible

func _update_orbit_camera_composition() -> void:
	# A low-Earth-orbit exterior camera sits beside the spacecraft and looks
	# diagonally over its shoulder toward Earth. At 550 km, Earth should fill
	# most of the lower view as a curved horizon—not appear as a small toy globe.
	if not mission_camera or not satellite_node:
		return
	var radial := satellite_node.global_position.normalized()
	var tangent := Vector3.UP.cross(radial)
	if tangent.length_squared() < 0.01:
		tangent = Vector3.RIGHT
	else:
		tangent = tangent.normalized()
	# Keep several spacecraft lengths of separation: the prior close position
	# filled the screen with a solar panel and hid the Earth horizon.
	var desired_camera := satellite_node.global_position + radial * 4.0 + tangent * 4.8 + Vector3.UP * 1.2
	var desired_target := satellite_node.global_position - radial * 3.9 - tangent * 0.55
	mission_camera.position = mission_camera.position.lerp(desired_camera, 0.045)
	mission_camera.look_at(desired_target, Vector3.UP)

# ─── Per-Frame Update ─────────────────────────────────────────────────────────
## The right-hand data card that opens when a real event is sensed. Built
## once, hidden until a capture happens; every field is filled from the
## simulation's own target record, never re-typed here.
func _build_climate_flyover_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ClimateFlyoverLayer"
	layer.layer = 60
	add_child(layer)
	fly_panel = PanelContainer.new()
	fly_panel.anchor_left = 1.0
	fly_panel.anchor_right = 1.0
	fly_panel.offset_left = -660.0
	fly_panel.offset_right = -24.0
	fly_panel.offset_top = 70.0
	fly_panel.offset_bottom = 0.0
	fly_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.045, 0.09, 0.94)
	sb.border_color = Color(0.25, 0.8, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	fly_panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(fly_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	fly_panel.add_child(box)
	var head := Label.new()
	head.text = "🛰 REAL DATA RETURNED FROM ORBIT"
	head.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	head.add_theme_font_size_override("font_size", 18)
	box.add_child(head)
	fly_image = TextureRect.new()
	fly_image.custom_minimum_size = Vector2(590, 330)
	fly_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	box.add_child(fly_image)
	fly_title = Label.new()
	fly_title.add_theme_font_size_override("font_size", 20)
	fly_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(fly_title)
	fly_subtitle = Label.new()
	fly_subtitle.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	fly_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(fly_subtitle)
	fly_stat = Label.new()
	fly_stat.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	fly_stat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(fly_stat)
	fly_credit = Label.new()
	fly_credit.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	fly_credit.add_theme_font_size_override("font_size", 13)
	fly_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(fly_credit)
	fly_status = Label.new()
	fly_status.add_theme_color_override("font_color", Color(0.4, 1.0, 0.7))
	fly_status.add_theme_font_size_override("font_size", 13)
	box.add_child(fly_status)

## Persistent mission-control console.  The player picks an operational
## instrument family, chooses one real geographic incident, and sends a scan
## task.  The command is not a cosmetic shortcut: SimulationEngine waits until
## its ground track and sensor constraints can actually satisfy it.
func _build_scan_console() -> void:
	var layer := CanvasLayer.new()
	layer.name = "EarthObservationControlRoom"
	layer.layer = 45
	add_child(layer)
	scan_console = PanelContainer.new()
	scan_console.offset_left = 22.0
	scan_console.offset_top = 92.0
	scan_console.offset_right = 456.0
	scan_console.offset_bottom = 694.0
	scan_console.hide() # flight operations begin after deployment/arrival
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008, 0.025, 0.055, 0.93)
	style.border_color = Color(0.12, 0.72, 0.95, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	scan_console.add_theme_stylebox_override("panel", style)
	layer.add_child(scan_console)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	scan_console.add_child(box)
	var title := Label.new()
	title.text = "MISSION CONTROL  //  EARTH SENTINEL"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.42, 0.9, 1.0))
	box.add_child(title)
	var operator := Label.new()
	operator.text = "OPERATOR CONSOLE  •  LIVE ORBITAL TASKING"
	operator.add_theme_font_size_override("font_size", 12)
	operator.add_theme_color_override("font_color", Color(0.52, 0.65, 0.78))
	box.add_child(operator)
	scan_orbit_label = Label.new()
	scan_orbit_label.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0))
	scan_orbit_label.add_theme_font_size_override("font_size", 13)
	box.add_child(scan_orbit_label)
	scan_link_label = Label.new()
	scan_link_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.7))
	scan_link_label.add_theme_font_size_override("font_size", 13)
	box.add_child(scan_link_label)
	var system_divider := HSeparator.new()
	box.add_child(system_divider)
	scan_mode_label = Label.new()
	scan_mode_label.text = "PAYLOAD: JPSS-2 • WEATHER / CLIMATE"
	scan_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(scan_mode_label)
	var modes := HBoxContainer.new()
	box.add_child(modes)
	var swot := Button.new()
	swot.text = "SWOT  •  WATER"
	swot.tooltip_text = "KaRIn radar-altimetry tasks for oceans, rivers and lakes"
	swot.pressed.connect(_on_scan_mode_pressed.bind("SWOT"))
	modes.add_child(swot)
	var jpss := Button.new()
	jpss.text = "JPSS-2  •  CLIMATE"
	jpss.tooltip_text = "Visible, infrared and atmospheric monitoring for weather and climate"
	jpss.pressed.connect(_on_scan_mode_pressed.bind("JPSS-2"))
	modes.add_child(jpss)
	var divider := HSeparator.new()
	box.add_child(divider)
	scan_target_label = Label.new()
	scan_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scan_target_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))
	box.add_child(scan_target_label)
	var target_list := VBoxContainer.new()
	target_list.add_theme_constant_override("separation", 3)
	box.add_child(target_list)
	for i in range(SimulationEngine.CLIMATE_TARGETS.size()):
		var target: Dictionary = SimulationEngine.CLIMATE_TARGETS[i]
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.text = "[%s] %s" % [String(target.get("mission_mode", "JPSS-2")), String(target["name"])]
		btn.tooltip_text = "%s\n%s" % [target["sensor"], target["stat"]]
		btn.pressed.connect(_on_scan_target_pressed.bind(i))
		target_list.add_child(btn)
		scan_target_buttons.append(btn)
	var command_row := HBoxContainer.new()
	command_row.add_theme_constant_override("separation", 6)
	box.add_child(command_row)
	var request := Button.new()
	request.text = "ARM SCAN"
	request.custom_minimum_size = Vector2(130, 42)
	request.pressed.connect(_on_request_scan_pressed)
	command_row.add_child(request)
	var downlink := Button.new()
	downlink.text = "DOWNLINK"
	downlink.custom_minimum_size = Vector2(130, 42)
	downlink.pressed.connect(_on_control_downlink_pressed)
	command_row.add_child(downlink)
	payload_command_button = Button.new()
	payload_command_button.text = "PAUSE PAYLOAD"
	payload_command_button.custom_minimum_size = Vector2(150, 42)
	payload_command_button.pressed.connect(_on_control_payload_pressed)
	command_row.add_child(payload_command_button)
	scan_status_label = Label.new()
	scan_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scan_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.68))
	scan_status_label.add_theme_font_size_override("font_size", 13)
	box.add_child(scan_status_label)
	_refresh_scan_console()
	_build_full_control_room(layer)

func _control_card(parent: Control, left: float, top: float, right: float, bottom: float) -> VBoxContainer:
	var card := PanelContainer.new()
	card.offset_left = left
	card.offset_top = top
	card.offset_right = right
	card.offset_bottom = bottom
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.012, 0.045, 0.10, 0.92)
	skin.border_color = Color(0.05, 0.78, 1.0, 0.88)
	skin.set_border_width_all(2)
	skin.set_corner_radius_all(11)
	skin.content_margin_left = 14.0
	skin.content_margin_right = 14.0
	skin.content_margin_top = 12.0
	skin.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", skin)
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)
	return content

func _control_text(parent: Container, text_value: String, size: int = 14, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

## The actual control-room presentation: the 3D globe remains a live scene in
## the centre while these HUD cards turn it into an operations workstation.
func _build_full_control_room(layer: CanvasLayer) -> void:
	control_room_dashboard = Control.new()
	control_room_dashboard.name = "FullMissionControlDashboard"
	control_room_dashboard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control_room_dashboard.mouse_filter = Control.MOUSE_FILTER_PASS
	control_room_dashboard.hide()
	layer.add_child(control_room_dashboard)
	# Reference artwork background — the mission control panel exactly as
	# designed for each Earth-observation mission (JPSS-2, SWOT, TEMPO).
	dashboard_background = TextureRect.new()
	dashboard_background.name = "DashboardArt"
	dashboard_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Without EXPAND_IGNORE_SIZE the control's minimum size stays at the
	# texture's native 1672×941 and the artwork draws 1:1, cropping the right
	# deck off the 1280×720 screen.
	dashboard_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dashboard_background.stretch_mode = TextureRect.STRETCH_SCALE
	dashboard_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_room_dashboard.add_child(dashboard_background)
	# Reactive layer: animated progress, live charts, countdowns and the real
	# NASA data feed, all aligned over the artwork's own panels.
	dashboard_live = DashboardLiveScript.new()
	dashboard_live.name = "DashboardLiveLayer"
	dashboard_live.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control_room_dashboard.add_child(dashboard_live)
	# Mission selector chip (top-right) — the one always-visible control.
	scan_mission_selector = OptionButton.new()
	scan_mission_selector.add_item("JPSS-2 / NOAA-21")
	scan_mission_selector.add_item("SWOT")
	scan_mission_selector.add_item("TEMPO")
	scan_mission_selector.add_theme_font_size_override("font_size", 13)
	var sel_style := StyleBoxFlat.new()
	sel_style.bg_color = Color(0.0, 0.03, 0.09, 1.0)
	sel_style.set_border_width_all(1)
	sel_style.set_corner_radius_all(10)
	sel_style.content_margin_left = 12.0
	sel_style.content_margin_right = 12.0
	sel_style.content_margin_top = 5.0
	sel_style.content_margin_bottom = 5.0
	scan_mission_selector.add_theme_stylebox_override("button", sel_style)
	scan_mission_selector.anchor_left = 0.845
	scan_mission_selector.anchor_right = 0.985
	scan_mission_selector.anchor_top = 0.018
	scan_mission_selector.anchor_bottom = 0.062
	scan_mission_selector.offset_left = 0.0
	scan_mission_selector.offset_top = 0.0
	scan_mission_selector.offset_right = 0.0
	scan_mission_selector.offset_bottom = 0.0
	scan_mission_selector.item_selected.connect(_on_dashboard_mission_selected)
	control_room_dashboard.add_child(scan_mission_selector)
	# Invisible command hotspots laid exactly over each artwork's own buttons.
	for mode in DASHBOARD_HOTSPOTS:
		for spec in DASHBOARD_HOTSPOTS[mode]:
			var rect: Array = spec["r"]
			var spot := Button.new()
			spot.name = "Hotspot_%s_%s" % [mode, spec["a"]]
			spot.anchor_left = rect[0]
			spot.anchor_top = rect[1]
			spot.anchor_right = rect[0] + rect[2]
			spot.anchor_bottom = rect[1] + rect[3]
			spot.offset_left = 0.0
			spot.offset_top = 0.0
			spot.offset_right = 0.0
			spot.offset_bottom = 0.0
			spot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			spot.set_meta("mission", mode)
			spot.set_meta("action", spec["a"])
			spot.tooltip_text = String(DASHBOARD_HOTSPOT_TIPS.get(spec["a"], ""))
			spot.pressed.connect(_on_dashboard_hotspot.bind(String(spec["a"])))
			control_room_dashboard.add_child(spot)
			dashboard_hotspots.append(spot)
	_apply_dashboard_mission_visuals()

## Swap the artwork, accent color and hotspot set for the selected mission.
func _apply_dashboard_mission_visuals() -> void:
	if control_room_dashboard == null:
		return
	var mode := selected_scan_mode
	var art_path: String = String(DASHBOARD_ART.get(mode, DASHBOARD_ART["JPSS-2"]))
	dashboard_accent = DASHBOARD_ACCENTS.get(mode, Color(0.22, 0.85, 1.0))
	if dashboard_background:
		var art: Texture2D = load(art_path)
		if art:
			dashboard_background.texture = art
	if dashboard_live:
		dashboard_live.set_mission(mode, dashboard_accent)
	for spot in dashboard_hotspots:
		var matches: bool = String(spot.get_meta("mission", "")) == mode
		spot.visible = matches
		if matches:
			_style_dashboard_hotspot(spot)

## Transparent by default; the artwork stays untouched until the operator
## hovers a command, when a soft accent glow marks the clickable region.
func _style_dashboard_hotspot(spot: Button) -> void:
	var accent := dashboard_accent
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0, 0, 0, 0)
	idle.set_border_width_all(0)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(accent.r, accent.g, accent.b, 0.14)
	hover.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(10)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(accent.r, accent.g, accent.b, 0.28)
	pressed.border_color = accent
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(10)
	spot.add_theme_stylebox_override("normal", idle)
	spot.add_theme_stylebox_override("hover", hover)
	spot.add_theme_stylebox_override("pressed", pressed)
	spot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _on_dashboard_hotspot(action: String) -> void:
	match action:
		"scan":
			_on_request_scan_pressed()
		"downlink":
			_on_control_downlink_pressed()
		"payload":
			_on_control_payload_pressed()
		"target":
			_on_dashboard_next_target()
		"menu":
			_on_quit_to_menu_pressed()
		"cycle":
			_cycle_dashboard_mission()
		"select_region":
			if dashboard_live and dashboard_live.has_method("select_next_incident"):
				dashboard_live.select_next_incident()
		"scan_pollution":
			if dashboard_live and dashboard_live.has_method("force_no2_refresh"):
				dashboard_live.force_no2_refresh()
		"compare_hours":
			if dashboard_live and dashboard_live.has_method("toggle_hour_compare"):
				dashboard_live.toggle_hour_compare()
		"no2_column":
			if dashboard_live and dashboard_live.has_method("toggle_no2_column_panel"):
				dashboard_live.toggle_no2_column_panel()
		"ozone_monitoring":
			if dashboard_live and dashboard_live.has_method("toggle_ozone_monitoring"):
				dashboard_live.toggle_ozone_monitoring()

func _cycle_dashboard_mission() -> void:
	var next := 1 if selected_scan_mode == "JPSS-2" else 2 if selected_scan_mode == "SWOT" else 0
	_on_dashboard_mission_selected(next)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if control_room_dashboard == null or not control_room_dashboard.visible:
		return
	if key.keycode == KEY_TAB:
		_cycle_dashboard_mission()
		get_viewport().set_input_as_handled()

func _on_dashboard_mission_selected(index: int) -> void:
	var mode := "SWOT" if index == 1 else "TEMPO" if index == 2 else "JPSS-2"
	_on_scan_mode_pressed(mode)
	var targets: Array = SimulationEngine.state.get("climate_targets", SimulationEngine.CLIMATE_TARGETS)
	for i in range(targets.size()):
		if String(targets[i].get("mission_mode", "JPSS-2")) == mode and not bool(targets[i].get("captured", false)):
			_on_scan_target_pressed(i)
			return

func _on_dashboard_next_target() -> void:
	var targets: Array = SimulationEngine.state.get("climate_targets", SimulationEngine.CLIMATE_TARGETS)
	for offset in range(1, targets.size() + 1):
		var next_i := (selected_scan_target + offset) % targets.size()
		if not bool(targets[next_i].get("captured", false)):
			_on_scan_target_pressed(next_i)
			return

func _on_scan_mode_pressed(mode: String) -> void:
	selected_scan_mode = mode
	_apply_dashboard_mission_visuals()
	_refresh_scan_console()

func _on_scan_target_pressed(target_index: int) -> void:
	selected_scan_target = target_index
	# Target selection chooses its real mission family by default; an operator can
	# still deliberately change it to see why an incompatible payload is refused.
	if target_index < SimulationEngine.CLIMATE_TARGETS.size():
		selected_scan_mode = String(SimulationEngine.CLIMATE_TARGETS[target_index].get("mission_mode", "JPSS-2"))
	_refresh_scan_console()

func _on_request_scan_pressed() -> void:
	SimulationEngine.request_climate_scan(selected_scan_target, selected_scan_mode)
	_refresh_scan_console()

func _on_control_downlink_pressed() -> void:
	SimulationEngine.transmit_data_manual()
	_refresh_scan_console()

func _on_control_payload_pressed() -> void:
	_on_safemode_pressed()
	_refresh_scan_console()

func _refresh_scan_console() -> void:
	if scan_console == null:
		return
	# Mission artwork must follow the selected mode wherever it is changed
	# from (dropdown, target pick or keyboard cycle), not just the selector.
	_apply_dashboard_mission_visuals()
	var targets: Array = SimulationEngine.state.get("climate_targets", SimulationEngine.CLIMATE_TARGETS)
	if targets.is_empty() or selected_scan_target >= targets.size():
		return
	var t: Dictionary = targets[selected_scan_target]
	var is_swot: bool = selected_scan_mode == "SWOT"
	var is_tempo: bool = selected_scan_mode == "TEMPO"
	if scan_mission_selector:
		scan_mission_selector.select(1 if is_swot else 2 if is_tempo else 0)
	if scan_dashboard_title:
		scan_dashboard_title.text = "SWOT  //  SURFACE WATER" if is_swot else "TEMPO  //  ATMOSPHERIC POLLUTION" if is_tempo else "JPSS-2 / NOAA-21"
	if scan_objective_label:
		scan_objective_label.text = "Measure water elevation, river width and ocean topography." if is_swot else "Measure hourly daytime pollution columns over North America." if is_tempo else "Monitor weather, wildfire, atmosphere and climate signals."
	if scan_mode_label:
		var payload_name := "SWOT • KaRIn WATER-HEIGHT RADAR" if is_swot else "TEMPO • UV-VISIBLE SPECTROMETER" if is_tempo else "JPSS-2 • WEATHER / CLIMATE IMAGER"
		scan_mode_label.text = "PAYLOAD: " + payload_name
	if scan_target_label:
		scan_target_label.text = "TARGET: %s\n%s" % [String(t["name"]), String(t["sensor"])]
	if scan_status_label:
		var active: int = int(SimulationEngine.state.get("active_scan_target", -1))
		var prefix := "ACTIVE TASK  " if active == selected_scan_target else "SYSTEM  "
		scan_status_label.text = prefix + String(SimulationEngine.state.get("scan_status", "Ready"))
	if scan_product_label:
		scan_product_label.text = "Water elevation / river-width acquisition\nNASA-CNES SWOT data simulation" if is_swot else "Hourly NO₂ / ozone / aerosol column observation\nNASA TEMPO data simulation" if is_tempo else "VIIRS / CrIS / ATMS environmental scan\nNASA-NOAA JPSS-2 data simulation"
	var orbit_number: int = int(SimulationEngine.state.get("total_orbits", 0))
	var alt: int = int(GameManager.current_mission.get("altitude_km", 550))
	if scan_orbit_label:
		scan_orbit_label.text = "ORBIT %03d   •   %d km SUN-SYNCHRONOUS" % [orbit_number, alt]
	if scan_right_status:
		var temp: float = float(SimulationEngine.state.get("battery_wh", 0.0))
		scan_right_status.text = "ALTITUDE  %d km\nORBIT  %03d\nBATTERY RESERVE  %.0f Wh" % [int(GameManager.current_mission.get("altitude_km", 550)), orbit_number, temp]
	if scan_link_label:
		var linked: bool = bool(SimulationEngine.state.get("ground_contact", false))
		var station: String = String(SimulationEngine.state.get("ground_station_name", ""))
		var data_mb: float = float(SimulationEngine.state.get("data_stored_mb", 0.0))
		scan_link_label.text = ("LINK: %s  •  %.0f MB READY" % [station, data_mb]) if linked else ("LINK: NO GROUND STATION  •  %.0f MB ONBOARD" % data_mb)
		scan_link_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.7) if linked else Color(1.0, 0.72, 0.24))
	if payload_command_button:
		var payload_live: bool = bool(SimulationEngine.state.get("instruments_active", true))
		payload_command_button.text = "PAUSE PAYLOAD" if payload_live else "RESUME PAYLOAD"
	for i in range(scan_target_buttons.size()):
		var captured: bool = i < targets.size() and bool(targets[i].get("captured", false))
		scan_target_buttons[i].disabled = captured
		scan_target_buttons[i].button_pressed = (i == selected_scan_target)

func _begin_climate_flyover(t: Dictionary) -> void:
	if t.is_empty() or fly_panel == null:
		return
	fly_target = t
	fly_time = 5.5
	var idx: int = SimulationEngine.CLIMATE_TARGETS.size()
	for i in range(SimulationEngine.CLIMATE_TARGETS.size()):
		if String(SimulationEngine.CLIMATE_TARGETS[i]["name"]) == String(t.get("name", "")):
			idx = i
			break
	fly_pin = climate_pins[idx] if idx < climate_pins.size() else null
	fly_title.text = "🌍 " + String(t.get("name", ""))
	fly_subtitle.text = "%s · sensed %s · %s" % [t.get("sensor", ""), t.get("date", ""), t.get("requires_instrument", "")]
	fly_stat.text = String(t.get("stat", ""))
	fly_credit.text = "Source: %s · %s" % [t.get("source", "NASA"), t.get("credit", "")]
	fly_status.text = "📡 Streaming real imagery from NASA WorldView…"
	fly_image.texture = null
	var cached: Texture2D = ClimateMediaScript.load_cached(String(t.get("img_url", "")))
	if cached:
		fly_image.texture = cached
		fly_status.text = "✅ Real NASA WorldView imagery (cached — plays offline next time)"
	fly_panel.visible = true
	if climate_media == null:
		climate_media = ClimateMediaScript.new()
		climate_media.name = "ClimateMedia"
		climate_media.image_ready.connect(_on_fly_image)
		add_child(climate_media)
	if not cached:
		climate_media.fetch(String(t.get("img_url", "")))

func _on_fly_image(tex: Texture2D) -> void:
	if not fly_panel or not fly_panel.visible:
		return
	if tex:
		fly_image.texture = tex
		fly_status.text = "✅ Real NASA WorldView imagery (cached — plays offline next time)"
	else:
		fly_status.text = "⚠ Offline — numeric data from the same observation shown instead"

func _update_climate_flyover(delta: float) -> void:
	if fly_time <= 0.0:
		return
	fly_time -= delta
	if fly_time <= 0.0:
		fly_panel.visible = false
		return
	if fly_pin and mission_camera:
		var pin_pos: Vector3 = fly_pin.global_position
		var outward: Vector3 = (pin_pos - earth_node.global_position).normalized()
		var wanted: Vector3 = pin_pos + outward * 2.4 + Vector3(0.0, 0.55, 0.0)
		mission_camera.global_position = mission_camera.global_position.lerp(wanted, minf(delta * 4.5, 1.0))
		mission_camera.look_at(pin_pos, Vector3.UP)

func _process(delta: float) -> void:
	if arrival_active:
		_update_orbit_arrival(delta)
		return
	# Feed the reactive dashboard layer from the one shared simulation state.
	if control_room_dashboard != null and control_room_dashboard.visible and dashboard_live != null:
		dashboard_live.tick(delta, SimulationEngine.state)
	# The picture is driven directly off the simulation's own geometry: the
	# satellite sits on the sub-satellite direction the engine uses to decide
	# contact, and the planet turns by the same angle the ground-station model
	# turns by.  Nothing here re-derives an orbit, so what the player sees and
	# what the telemetry reports are one calculation, not two that merely look
	# alike — which is the whole difference between a data model and a picture.
	var sub_dir: Vector3 = SimulationEngine.sub_point_direction()
	satellite_node.position = sub_dir * orbit_radius_3d
	var angle_rad: float = SimulationEngine.orbit_angle
	_update_satellite_operations(delta, angle_rad)

	# Routine operations: the exterior camera chases the spacecraft so the
	# live orbit and the turning planet stay framed behind the real-time ops.
	if not arrival_active and control_room_dashboard != null and control_room_dashboard.visible:
		_update_orbit_camera_composition()

	# The globe spins at its real sidereal rate under a plane that does not, and
	# the station network rides that same spin so every dish stays on its own
	# continent while the ground track walks westward beneath it.
	var spin: float = SimulationEngine.earth_rotation_rad
	if earth_sphere:
		earth_sphere.rotation.y = spin
	if earth_atmosphere:
		earth_atmosphere.rotation.y = spin
	if earth_clouds:
		earth_clouds.rotation.y = spin
	if stations_root:
		stations_root.rotation.y = spin
		_update_station_visuals()
	if climate_root:
		climate_root.rotation.y = spin
		_update_climate_target_visuals()
		_refresh_scan_console()
	if commissioning_active:
		_update_commissioning()

	# Solar panel orientation toward sun
	var sun_dir: Vector3 = sun_light.global_transform.basis.z if sun_light else Vector3.RIGHT
	if solar_panel_l:
		solar_panel_l.rotation.x = angle_rad

	# Eclipse: darken satellite when in eclipse
	var in_eclipse: bool = SimulationEngine.state.get("in_eclipse", false)
	if satellite_mesh:
		var brightness: float = 0.3 if in_eclipse else 1.0
		var mat := satellite_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission = Color(0.7, 0.75, 0.8) * brightness * 0.2
			mat.emission_enabled = true

	# The flyover takes the camera last, after every routine follow-shot lerp,
	# so the close-up of the real location is what actually lands on screen.
	_update_climate_flyover(delta)

	# Popup timer
	if event_popup_timer > 0:
		event_popup_timer -= delta
		if event_popup_timer <= 0:
			event_popup.hide()

	# Input handling
	if Input.is_action_just_pressed("orbital_map"):
		_toggle_orbital_map()
	if Input.is_action_just_pressed("transmit_data"):
		SimulationEngine.transmit_data_manual()
	if Input.is_action_just_pressed("time_accel"):
		SimulationEngine.speed_up()
		_update_speed_buttons(SimulationEngine.time_scale_idx)
	if Input.is_action_just_pressed("time_decel"):
		SimulationEngine.speed_down()
		_update_speed_buttons(SimulationEngine.time_scale_idx)
	if Input.is_action_just_pressed("pause_game"):
		_toggle_pause()

func _update_orbit_arrival(delta: float) -> void:
	arrival_timer += delta
	if arrival_fade:
		arrival_fade.color.a = clampf(1.0 - arrival_timer / 1.6, 0.0, 1.0)
	# This is the same already-released spacecraft, now viewed by mission control.
	# Keep the deployment sequence on screen long enough for the player to read
	# it. The former 6-second version was easy to miss during a scene handoff.
	var drift: float = min(arrival_timer / 11.5, 1.0)
	if satellite_node:
		satellite_node.position = Vector3(lerp(-1.4, 3.8, drift), 0.8 + sin(arrival_timer * 1.2) * 0.25, 6.2)
		satellite_node.rotation_degrees = Vector3(8.0, -20.0 + arrival_timer * 7.0, 0.0)
	if satellite_visual:
		# The model begins compact against the upper stage and eases to its full
		# deployed span, making the handoff visibly feel like a mission event.
		var deployment: float = clamp((arrival_timer - 3.2) / 5.0, 0.0, 1.0)
		var scale_value: float = lerp(0.055, 0.22, deployment)
		satellite_visual.scale = Vector3.ONE * scale_value
		solar_deployment = deployment
	for panel in [solar_panel_l, solar_panel_r]:
		if panel: panel.scale.x = maxf(0.06, solar_deployment)
	if earth_node:
		earth_node.rotation.y += delta * 0.025
	if mission_camera:
		var target_camera := Vector3(-1.7, 3.0, 15.5)
		mission_camera.position = mission_camera.position.lerp(target_camera, min(delta * 0.42, 1.0))
		mission_camera.look_at(Vector3(0.4, 0.4, 4.8), Vector3.UP)
	if arrival_timer < 3.2:
		if arrival_title:
			arrival_title.text = "ASTEROID RENDEZVOUS" if asteroid_operations else "MARS ORBIT ACQUISITION" if mars_operations else "ORBIT ACQUISITION"
		if arrival_detail:
			arrival_detail.text = "Relative navigation lock established with 2025-XK7" if asteroid_operations else "DSN has acquired the climate orbiter arriving at Mars" if mars_operations else "Ground tracking has acquired the satellite released by the upper stage"
	elif arrival_timer < 8.4:
		if arrival_title: arrival_title.text = "SOLAR ARRAY DEPLOYMENT"
		if arrival_detail: arrival_detail.text = "Port and starboard arrays extending — hold attitude"
	elif arrival_timer < 11.8:
		if arrival_title: arrival_title.text = "ATTITUDE ACQUISITION"
		if arrival_detail:
			arrival_detail.text = "Low-thrust corrections holding a safe station around the asteroid" if asteroid_operations else "Reaction-control system pointing weather payload at Mars" if mars_operations else "Reaction-control system orienting payload toward Earth"
	elif arrival_timer < 14.0:
		if arrival_title:
			arrival_title.text = "2025-XK7 ORBIT ESTABLISHED" if asteroid_operations else "MARS CLIMATE ORBITER DEPLOYED" if mars_operations else "SATELLITE DEPLOYED"
		if arrival_detail:
			arrival_detail.text = "Rendezvous confirmed. Begin surface composition survey." if asteroid_operations else "Arrays locked. Mars-pointing climate survey confirmed." if mars_operations else "Arrays locked. Earth-pointing observation mode confirmed."
	else:
		_finish_orbit_arrival()

# ─── State Update from Simulation ────────────────────────────────────────────
func _on_state_updated(sim_state: Dictionary) -> void:
	_update_telemetry(sim_state)
	_update_indicators(sim_state)

func _update_telemetry(s: Dictionary) -> void:
	var batt_pct: float = 0.0
	var batt_max: float = s.get("battery_max_wh", 1.0)
	if batt_max > 0:
		batt_pct = (s.get("battery_wh", 0.0) / batt_max) * 100.0

	var sci: float    = s.get("science_points", 0)
	var sci_goal: float = s.get("target_science", 80)
	var data_stored: float = s.get("data_stored_mb", 0)
	var bus: Dictionary = GameManager.spacecraft_config.get("bus", {})
	var storage_mb: float = bus.get("data_storage", 200) * 1000.0
	var gen: float    = s.get("power_gen", 0)
	var draw: float   = s.get("power_draw", 0)

	if battery_bar:
		battery_bar.value = batt_pct
		_color_bar(battery_bar, 1.0 - batt_pct / 100.0)
	if battery_label:
		battery_label.text = "🔋 Battery: %.0f%% (%.0fWh)" % [batt_pct, s.get("battery_wh", 0)]

	if power_bar:
		var bal: float = gen - draw
		power_bar.value = clamp(gen / max(draw, 1) * 50, 0, 100)
		_color_bar(power_bar, 0.1 if gen >= draw else 0.95)
	if power_label:
		var bal: float = gen - draw
		power_label.text = "⚡ Power: %.0fW gen | %.0fW draw | %s%.0fW" % [
			gen, draw, "+" if bal >= 0 else "", bal
		]
		power_label.add_theme_color_override("font_color",
			Color.GREEN if bal >= 0 else Color.RED)

	if science_bar:
		science_bar.max_value = sci_goal
		science_bar.value = sci
		_color_bar(science_bar, 1.0 - sci / max(sci_goal, 1))
	if science_label:
		science_label.text = "🔬 Science: %.1f / %.0f pts" % [sci, sci_goal]
		if GameManager.is_earth_climate_mission():
			var captured_n: int = int(s.get("targets_captured", 0))
			science_label.text += "  |  🌍 Real events %d/%d" % [captured_n, SimulationEngine.CLIMATE_TARGETS.size()]
		if sci >= sci_goal:
			science_label.add_theme_color_override("font_color", Color.GREEN)

	if data_bar:
		data_bar.max_value = max(storage_mb, 1)
		data_bar.value = data_stored
		_color_bar(data_bar, data_stored / max(storage_mb, 1))
	if data_label:
		var tx: float = s.get("data_transmitted_mb", 0)
		data_label.text = "📊 Data: %.0f MB stored | %.0f MB sent" % [data_stored, tx]

	if day_label:
		var day: int = s.get("day", 0)
		var total: int = s.get("mission_duration_days", 365)
		day_label.text = "Day %d / %d   |   Orbit #%d" % [day, total, s.get("total_orbits", 0)]

	if orbit_info:
		var mission: Dictionary = GameManager.current_mission
		orbit_info.text = "Orbit: %s at %d km  |  Period: %.0f min" % [
			mission.get("target", "?"),
			mission.get("altitude_km", 550),
			SimulationEngine.orbit_period_seconds / 60.0
		]
		if GameManager.is_earth_climate_mission():
			# Show the two numbers a real flight-dynamics officer would check: the
			# Kepler period and the J2 nodal drift against the 0.9856°/day that makes
			# an orbit sun-synchronous.  Both are the live simulation's own values.
			var prec: float = float(s.get("nodal_precession_deg_day", 0.0))
			var sync_err: float = absf(prec - 0.9856)
			orbit_info.text += "\nKepler period ✓  |  J2 nodal drift %.4f °/day (sun-sync needs 0.9856, Δ=%.4f)" % [prec, sync_err]

func _update_indicators(s: Dictionary) -> void:
	if eclipse_indicator:
		if asteroid_operations:
			eclipse_indicator.text = "☄ DEEP SPACE"
			eclipse_indicator.add_theme_color_override("font_color", Color(0.85, 0.68, 0.42))
		elif s.get("in_eclipse", false):
			eclipse_indicator.text = "🌑 ECLIPSE"
			eclipse_indicator.add_theme_color_override("font_color", Color(0.5, 0.5, 0.8))
		else:
			eclipse_indicator.text = "☀ SUNLIGHT"
			eclipse_indicator.add_theme_color_override("font_color", Color.YELLOW)

	if contact_indicator:
		if s.get("ground_contact", false):
			contact_indicator.text = "📡 DSN CONTACT: " + s.get("ground_station_name", "DSN") if asteroid_operations else "📡 CONTACT: " + s.get("ground_station_name", "DSN")
			contact_indicator.add_theme_color_override("font_color", Color.GREEN)
		else:
			contact_indicator.text = "📡 NO CONTACT"
			contact_indicator.add_theme_color_override("font_color", Color.RED)

	if speed_label:
		speed_label.text = "⏩ %dx" % int(SimulationEngine.time_scale)

# ─── Event Popup ─────────────────────────────────────────────────────────────
func _on_event_occurred(event: Dictionary) -> void:
	# Add to log
	var lbl: Label = Label.new()
	var type_col: Dictionary = {
		"success": Color.GREEN,
		"danger":  Color.RED,
		"warning": Color(1.0, 0.7, 0.0),
		"info":    Color.CYAN
	}
	lbl.text = "Day %d: %s" % [SimulationEngine.state.get("day", 0), event.get("name", "?")]
	lbl.add_theme_color_override("font_color", type_col.get(event.get("type", "info"), Color.WHITE))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	if event_log:
		event_log.add_child(lbl)
		# Keep last 12 entries
		while event_log.get_child_count() > 12:
			event_log.get_child(0).queue_free()

	# A climate capture gets its own flyover + imagery card; the generic popup
	# would only repeat what that panel already shows better.
	if String(event.get("kind", "")) == "climate_capture":
		_begin_climate_flyover(event.get("target", {}))
		return

	# Show popup
	if event_popup and event_popup_label:
		event_popup_label.text = "⚡ %s\n%s" % [event.get("name", ""), event.get("desc", "")]
		event_popup_label.add_theme_color_override("font_color",
			type_col.get(event.get("type", "info"), Color.WHITE))
		event_popup.show()
		event_popup_timer = 5.0

# ─── Mission End ──────────────────────────────────────────────────────────────
func _on_mission_ended(result: Dictionary) -> void:
	GameManager.mission_result = result
	await get_tree().create_timer(2.0).timeout
	GameManager.go_to_report()

# ─── Controls ────────────────────────────────────────────────────────────────
func _on_speed_1x_pressed() -> void:
	SimulationEngine.set_time_scale(0)
	_update_speed_buttons(0)

func _on_speed_10x_pressed() -> void:
	SimulationEngine.set_time_scale(1)
	_update_speed_buttons(1)

func _on_speed_100x_pressed() -> void:
	SimulationEngine.set_time_scale(2)
	_update_speed_buttons(2)

func _on_speed_1000x_pressed() -> void:
	SimulationEngine.set_time_scale(3)
	_update_speed_buttons(3)

func _update_speed_buttons(active_idx: int) -> void:
	var btns: Array = [speed_btn_1x, speed_btn_10x, speed_btn_100x]
	for i in range(btns.size()):
		if btns[i]:
			btns[i].button_pressed = (i == active_idx)

func _on_transmit_pressed() -> void:
	SimulationEngine.transmit_data_manual()

func _on_safemode_pressed() -> void:
	var s: Dictionary = SimulationEngine.state
	s["instruments_active"] = not s.get("instruments_active", true)
	var mode_str: String = "nominal" if s["instruments_active"] else "SAFE MODE"
	SimulationEngine._log_event("🛡️ Operator command: Instruments set to " + mode_str, "info")

func _on_end_mission_pressed() -> void:
	SimulationEngine._end_mission()

func _toggle_orbital_map() -> void:
	show_orbital_map = not show_orbital_map
	orbital_map_panel.visible = show_orbital_map

func _toggle_pause() -> void:
	var is_paused: bool = not SimulationEngine.paused
	SimulationEngine.paused = is_paused
	pause_menu.visible = is_paused

func _on_resume_pressed() -> void:
	SimulationEngine.paused = false
	pause_menu.hide()

func _on_quit_to_menu_pressed() -> void:
	SimulationEngine.running = false
	GameManager.go_to_main_menu()

func _color_bar(bar: ProgressBar, frac: float) -> void:
	var col: Color = Color.GREEN if frac < 0.4 else Color.YELLOW if frac < 0.75 else Color.RED
	bar.add_theme_color_override("font_color", col)
