class_name DashboardLive
extends Control

## Live reactive layer over the reference-art dashboards.  Draws animated
## progress bars, charts, countdowns and a scrolling real NASA data feed that
## line up with the artwork's own panels, so the static control room reads as
## a running instrument.
##
## Real data: TEMPO incident locations come from NASA EONET and NO2 readings
## from NASA's public NRT ArcGIS image service. Ozone remains illustrative.
## NASA Image & Video Library supplies the SWOT headlines and product tiles.

const FEED_CACHE := "user://nasa_live_feed_"
const TEMPO_INCIDENTS_URL := "https://eonet.gsfc.nasa.gov/api/v3/events/geojson?status=open&category=wildfires,volcanoes,dustHaze,severeStorms&limit=100"
const TEMPO_INCIDENT_CACHE := "user://nasa_tempo_incidents.json"
const TEMPO_NO2_SERVICE := "https://gis.earthdata.nasa.gov/portal/rest/services/C3685668637-LARC_CLOUD/TEMPO_NO2_L3_NRT_V02_HOURLY_TROPOSPHERIC_VERTICAL_COLUMN/ImageServer"
const INCIDENT_REFRESH_SECONDS := 900.0
const NO2_HISTORY_LIMIT := 12
const TEMPO_VIEW_BOUNDS := [-140.0, -55.0, 10.0, 72.0] # west, east, south, north

# ─── Animated globe layer ────────────────────────────────────────────────────
# Bounding square of the artwork's Earth, per mission (fractions of screen).
# The rotating shader globe is drawn exactly over it; TEMPO's flat map gets
# scan-sweep VFX instead of a globe.
const GLOBE := {
	# Full extent of the (now erased) art planet, so no static Earth peeks out.
	"JPSS-2": [0.267, 0.077, 0.386, 0.686],
	"SWOT": [0.312, 0.124, 0.320, 0.570],
}
# UV-space holes punched in the globe (globe-rect UVs) so art callouts stay
# visible over the rotating Earth.  [cutout_a, cutout_b] per mission.
const GLOBE_CUTOUTS := {
	# EARTH observation button chips (protected in the art) + JPSS-2 callout.
	"JPSS-2": [[0.0, 0.2456, 0.179, 0.7026], [0.8016, 0.1668, 1.0, 0.266]],
	"SWOT": [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]],
}
# Screen point of each art GROUND STATION panel — downlink packets fly there.
const GROUND_LINK := {
	"JPSS-2": [0.828, 0.44],
	"SWOT": [0.830, 0.40],
}
const ORBIT_TILT := -0.42
const EARTH_TEX_URL := "https://unpkg.com/three-globe/example/img/earth-blue-marble.jpg"
const GlobeShader := preload("res://resources/dashboard_globe.gdshader")

# TEMPO's flat map region for the scan-sweep and NASA incident markers.
const TEMPO_MAP := [0.255, 0.14, 0.47, 0.46]

# Art panel overlays that get live VFX: meter bars, signal bars, thumbnail
# strips and the TEMPO radiance spectrum plot (fractions of screen).
const TEMPO_SPECTRUM := [0.770, 0.207, 0.213, 0.173]
const FX_RECTS := {
	"JPSS-2": {
		"battery": [0.856, 0.257, 0.059, 0.025],
		"storage": [0.856, 0.327, 0.059, 0.022],
		"signal": [0.933, 0.452, 0.030, 0.048],
		"analysis_strip": [0.034, 0.790, 0.454, 0.163],
		"instrument_strip": [0.050, 0.235, 0.038, 0.255],
	},
	"SWOT": {
		"battery": [0.830, 0.132, 0.076, 0.021],
		"storage": [0.830, 0.239, 0.078, 0.022],
		"signal": [0.830, 0.442, 0.064, 0.022],
	},
	"TEMPO": {
		"power": [0.139, 0.537, 0.111, 0.020],
		"data_bar": [0.139, 0.591, 0.111, 0.020],
	},
}

# Official mission pages — the ticker facts stream live from these when online.
const MISSION_PAGES := {
	"JPSS-2": "https://science.nasa.gov/mission/jpss/",
	"SWOT": "https://science.nasa.gov/mission/swot/",
	"TEMPO": "https://science.nasa.gov/mission/tempo/",
}

const FEED_QUERIES := {
	"JPSS-2": "JPSS weather satellite NOAA",
	"SWOT": "SWOT surface water ocean topography",
	"TEMPO": "TEMPO air pollution atmosphere",
}

const FALLBACK_FEEDS := {
	"JPSS-2": [
		"JPSS-2 (NOAA-21) launched Nov 10 2022 on Atlas V from Vandenberg SLC-3E",
		"VIIRS images 3,000 km-wide swaths of Earth day and night",
		"CrIS resolves atmospheric temperature in ~1 km vertical layers",
		"ATMS sounds 22 microwave channels straight through cloud cover",
		"OMPS maps total column ozone and the vertical ozone profile",
		"JPSS data feeds NOAA operational weather forecasts every 6 hours",
	],
	"SWOT": [
		"SWOT launched Dec 16 2022 on Falcon 9 from Vandenberg SLC-4E",
		"KaRIn measures water elevation to centimeter precision",
		"120 km-wide swath observing the global ocean every 21 days",
		"NASA-CNES mission with UK Space Agency and CSA partners",
		"Surveying rivers, lakes and reservoirs worldwide in 3D",
		"Latest headlines stream from images-api.nasa.gov when online",
	],
	"TEMPO": [
		"TEMPO launched April 2023 aboard Intelsat 40e",
		"First hourly daytime air-pollution measurements over North America",
		"UV-visible spectrometer records NO2, ozone and aerosol columns",
		"Geostationary orbit at ~91.8 degrees West",
		"TEMPO data supports air-quality alerts across the United States",
	],
}

const TILE_QUERIES := [
	"SWOT ocean sea surface height",
	"SWOT river water level",
	"SWOT reservoir flood water",
]

# Widget rects are fractions of the screen, matched to the artwork panels.
const WIDGETS := {
	"JPSS-2": {
		"obs_window": [0.508, 0.772, 0.235, 0.040],
		"data_volume": [0.745, 0.772, 0.235, 0.040],
		"ground_pass": [0.788, 0.345, 0.088, 0.036],
		"profile_chart": [0.730, 0.585, 0.135, 0.115],
		"pulse_a": [0.840, 0.848, 0.084, 0.108],
		"pulse_b": [0.928, 0.848, 0.070, 0.108],
	},
	"SWOT": {
		"progress_bar": [0.306, 0.903, 0.325, 0.028],
		"progress_pct": [0.627, 0.890, 0.048, 0.042],
		"status_line": [0.312, 0.940, 0.340, 0.034],
		"time_left": [0.540, 0.940, 0.118, 0.034],
		"water_chart": [0.730, 0.525, 0.258, 0.167],
		"ground_contact": [0.150, 0.357, 0.125, 0.036],
		"pulse_a": [0.236, 0.748, 0.228, 0.088],
	},
	"TEMPO": {
		"utc_chip": [0.804, 0.092, 0.185, 0.042],
		"progress_bar": [0.781, 0.442, 0.145, 0.026],
		"progress_pct": [0.947, 0.440, 0.045, 0.036],
		"insight_no2": [0.880, 0.550, 0.082, 0.055],
		"insight_no2_delta": [0.950, 0.552, 0.042, 0.040],
		"insight_o3": [0.880, 0.620, 0.082, 0.055],
		"insight_o3_delta": [0.950, 0.624, 0.042, 0.048],
		"hourly_chart": [0.283, 0.645, 0.332, 0.132],
		"pulse_a": [0.272, 0.896, 0.168, 0.07],
	},
}

const SCAN_DURATION := 210.0
# Flip on while debugging feeds/uniforms; stays quiet in normal play.
const DEBUG_LOGS := false

var mission := "JPSS-2"
var accent := Color(0.22, 0.85, 1.0)
var sim_state: Dictionary = {}

var tick_time := 0.0
var scan_progress := 0.72
var scan_duration := SCAN_DURATION
var last_status := ""
var was_scanning := false

var water_series: PackedFloat32Array = []
var water_timer := 0.0
var water_value := 0.35
var water_peak := 0.62

var contact_countdown := 756.0
var was_in_contact := false

var globe: TextureRect = null
var vfx_top: Control = null
var earth_fetched := false

var feed_lines: PackedStringArray = []
var feed_index := 0
var feed_timer := 0.0
var feed_is_live := false
var feed_source := "fallback"  # fallback | page | api
var mission_feeds := {}  # mode -> {"lines": PackedStringArray, "source": String}

var fetched_missions: Array[String] = []
var tile_urls: Array[String] = []
var tiles: Array[TextureRect] = []
var _o3_value := 410.0
var tempo_incidents: Array[Dictionary] = []
var incident_feed_status := "loading" # loading | live | cached | offline
var incident_fetch_in_progress := false
var incident_refresh_timer := 0.0
var incident_index := 0
var tempo_scan_times: Array[int] = []
var tempo_no2_history: Array[Dictionary] = []
var tempo_no2_status := "loading" # loading | live | cached | no_data | offline
var tempo_dimensions_fetch_in_progress := false
var tempo_sample_fetch_in_progress := false
# TEMPO bottom-command UI modes
var tempo_hour_compare_on := false
var tempo_no2_column_panel_on := false
var tempo_ozone_monitoring_on := false
var tempo_toast := ""
var tempo_toast_timer := 0.0
var tempo_manual_scan_pending := false
var tempo_fallback_attempted: Array[String] = []
# Fallback cities used when an incident location has no valid TEMPO pixels
# (cloud / night / quality-flag filtered). They are well-observed metros.
const TEMPO_FALLBACK_CITIES := [
	{"name": "New York", "lon": -74.006, "lat": 40.7128},
	{"name": "Los Angeles", "lon": -118.2437, "lat": 34.0522},
	{"name": "Chicago", "lon": -87.6298, "lat": 41.8781},
	{"name": "Houston", "lon": -95.3698, "lat": 29.7604},
	{"name": "Toronto", "lon": -79.3832, "lat": 43.6532},
	{"name": "Miami", "lon": -80.1918, "lat": 25.7617},
	{"name": "Phoenix", "lon": -112.074, "lat": 33.4484},
	{"name": "Seattle", "lon": -122.3321, "lat": 47.6062},
	{"name": "Atlanta", "lon": -84.388, "lat": 33.749},
]
var tempo_used_fallback_city := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(TILE_QUERIES.size()):
		var tile := TextureRect.new()
		tile.name = "NasaTile%d" % i
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		# Positions match the three data-product tiles drawn in the artwork.
		var tile_x: Array = [0.6875, 0.7773, 0.8633]
		tile.anchor_left = tile_x[i]
		tile.anchor_top = 0.861
		tile.anchor_right = tile_x[i] + 0.0742
		tile.anchor_bottom = 0.947
		for off in ["offset_left", "offset_top", "offset_right", "offset_bottom"]:
			tile.set(off, 0.0)
		add_child(tile)
		tiles.append(tile)
	# Seed the water elevation chart with a gentle opening curve so the panel
	# is alive the moment the dashboard appears.
	for i in range(24):
		water_series.append(0.35 + sin(i * 0.55) * 0.25)
	# Rotating Earth: a shader globe drawn exactly over the artwork's planet,
	# textured with real NASA Blue Marble imagery when the fetch lands.
	globe = TextureRect.new()
	globe.name = "DashboardGlobe"
	globe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	globe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	globe.stretch_mode = TextureRect.STRETCH_SCALE
	globe.visible = false
	var mat := ShaderMaterial.new()
	mat.shader = GlobeShader
	var fallback := _make_procedural_earth()
	mat.set_shader_parameter("map_tex", fallback)
	globe.material = mat
	# The node needs a texture to have anything to draw at all; the shader
	# replaces it via the map_tex uniform anyway.
	globe.texture = fallback
	add_child(globe)
	_fetch_earth_texture()
	# Top-most VFX pass: the orbiting satellite, scan beam and downlink
	# packets ride above the globe; widgets stay below it.  The pass does its
	# own drawing (a canvas item may only draw inside its own _draw).
	vfx_top = TopFx.new()
	vfx_top.layer = self
	add_child(vfx_top)

## A stylised stand-in Earth so the globe spins even with zero network.
func _make_procedural_earth() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.014
	noise.fractal_octaves = 5
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var lat := absf(1.0 - 2.0 * float(y) / float(h))
		for x in range(w):
			var n := noise.get_noise_2d(float(x), float(y))
			var col := Color(0.04, 0.20, 0.52)
			if n > 0.05:
				var land := clampf((n - 0.05) * 5.0, 0.0, 1.0)
				col = Color(0.14, 0.40, 0.18).lerp(Color(0.62, 0.54, 0.30), land)
			if lat > 0.80:
				col = col.lerp(Color(0.92, 0.96, 0.99), clampf((lat - 0.80) * 7.0, 0.0, 1.0))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## Real NASA Blue Marble imagery for the rotating globe (cached offline).
func _fetch_earth_texture() -> void:
	if earth_fetched:
		return
	earth_fetched = true
	var cached := ClimateMedia.load_cached(EARTH_TEX_URL)
	if cached != null:
		_apply_earth_texture(cached)
		return
	var req := HTTPRequest.new()
	req.timeout = 45.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var tex := ClimateMedia.load_cached(EARTH_TEX_URL)
			if tex != null:
				if DEBUG_LOGS:
					print("[DashboardLive] Earth texture loaded (NASA Blue Marble)")
				_apply_earth_texture(tex)
	)
	DirAccess.make_dir_recursive_absolute(ClimateMedia.CACHE_DIR)
	req.download_file = ClimateMedia.cache_path(EARTH_TEX_URL)
	req.request(EARTH_TEX_URL)

func _apply_earth_texture(tex: Texture2D) -> void:
	if globe != null and globe.material is ShaderMaterial:
		(globe.material as ShaderMaterial).set_shader_parameter("map_tex", tex)
		var check: Variant = (globe.material as ShaderMaterial).get_shader_parameter("map_tex")
		if DEBUG_LOGS:
			print("[DashboardLive] earth uniform applied: %s (readback=%s)" % [tex, str(check).substr(0, 40)])
	else:
		if DEBUG_LOGS:
			print("[DashboardLive] earth uniform SKIPPED (globe=%s mat=%s)" % [globe, globe.material if globe else null])

## The satellite, scan beam and downlink packets draw above the globe.
class TopFx extends Control:
	var layer: DashboardLive = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if layer == null:
			return
		if layer.mission == "TEMPO":
			_draw_tempo_map_fx()
			_draw_spectrum_fx()
		else:
			_draw_orbit_satellite()
			if layer.mission == "JPSS-2":
				_draw_earth_header()
		_draw_panel_fx()

	## The baked "EARTH (REAL-TIME SIMULATION)" header redrawn live over the
	## rotating globe, matching the artwork's original title treatment.
	func _draw_earth_header() -> void:
		var f := ThemeDB.fallback_font
		if f == null:
			return
		var cy := 0.2075 * size.y
		var cx := 0.268 * size.x
		# Small globe glyph: cyan disc with meridian lines.
		draw_circle(Vector2(cx, cy), 8.5, Color(0.06, 0.30, 0.55, 0.95))
		draw_arc(Vector2(cx, cy), 8.5, 0.0, TAU, 24, Color(0.35, 0.85, 1.0, 0.95), 1.5, true)
		draw_arc(Vector2(cx, cy), 5.0, 0.0, TAU, 20, Color(0.35, 0.85, 1.0, 0.55), 1.0, true)
		draw_line(Vector2(cx - 8.5, cy), Vector2(cx + 8.5, cy), Color(0.35, 0.85, 1.0, 0.55), 1.0, true)
		draw_string(f, Vector2(cx + 14.0, cy + 5.0), "EARTH",
				HORIZONTAL_ALIGNMENT_LEFT, 70.0, 14, Color(0.92, 0.98, 1.0))
		draw_string(f, Vector2(cx + 78.0, cy + 4.0), "(REAL-TIME SIMULATION)",
				HORIZONTAL_ALIGNMENT_LEFT, 140.0, 9, Color(0.55, 0.80, 1.0, 0.85))

	## ─── Art panel VFX: meters, signal bars, sweeps, spectrum ───────────────
	func _draw_panel_fx() -> void:
		var fx: Dictionary = DashboardLive.FX_RECTS.get(layer.mission, {})
		match layer.mission:
			"JPSS-2":
				_draw_meter_shimmer(fx, "battery", Color(0.25, 1.0, 0.55))
				_draw_meter_shimmer(fx, "storage", Color(0.30, 0.80, 1.0))
				_draw_signal_bars(fx)
				_draw_strip_sweep(fx, "analysis_strip", Color(0.30, 0.85, 1.0))
				_draw_strip_sweep(fx, "instrument_strip", Color(0.30, 0.85, 1.0))
			"SWOT":
				_draw_meter_shimmer(fx, "battery", Color(0.25, 1.0, 0.55))
				_draw_meter_shimmer(fx, "storage", Color(0.30, 0.80, 1.0))
				_draw_signal_bars(fx)
			"TEMPO":
				_draw_meter_shimmer(fx, "power", Color(0.25, 1.0, 0.55))
				_draw_meter_shimmer(fx, "data_bar", Color(0.30, 0.80, 1.0))

	## A bright data pulse sweeping along the artwork's meter bar.
	func _draw_meter_shimmer(fx: Dictionary, key: String, col: Color) -> void:
		if not fx.has(key):
			return
		var r := _rfx(fx[key])
		var u := fmod(layer.tick_time * 0.38 + float(key.hash() % 7) * 0.11, 1.0)
		var px := r.position.x + r.size.x * u
		draw_rect(Rect2(px - 9.0, r.position.y, 18.0, r.size.y), Color(col.r, col.g, col.b, 0.14))
		draw_rect(Rect2(px - 2.5, r.position.y + 1.0, 5.0, r.size.y - 2.0), Color(1.0, 1.0, 1.0, 0.35))

	## Live link-quality bars replacing the artwork's static ones.
	func _draw_signal_bars(fx: Dictionary) -> void:
		if not fx.has("signal"):
			return
		var r := _rfx(fx["signal"])
		draw_rect(r.grow(3.0), Color(0.008, 0.031, 0.075, 0.95))
		var n := 5
		var lit_pos: float = fmod(layer.tick_time * 2.2, 1.6) * float(n)
		for i in range(n):
			var bw := r.size.x / float(n)
			var h := r.size.y * (0.25 + 0.75 * float(i) / float(n - 1))
			var lit := float(i) < lit_pos
			draw_rect(Rect2(r.position.x + bw * float(i) + 1.0, r.end.y - h, bw - 2.0, h),
					Color(0.3, 1.0, 0.6, 0.9 if lit else 0.28))

	## A scan line gliding across the artwork's thumbnail strips.
	func _draw_strip_sweep(fx: Dictionary, key: String, col: Color) -> void:
		if not fx.has(key):
			return
		var r := _rfx(fx[key])
		var u := fmod(layer.tick_time * 0.09, 1.0)
		var x := r.position.x + r.size.x * u
		draw_rect(Rect2(x - 30.0, r.position.y, 30.0, r.size.y), Color(col.r, col.g, col.b, 0.05))
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(col.r, col.g, col.b, 0.40), 2.0, true)
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1.0, 1.0, 1.0, 0.18), 1.0, true)

	## TEMPO's UV-visible radiance spectrum, redrawn live: wavelength bars
	## breathing with the scan, absorption dips and a scanning cursor.
	func _draw_spectrum_fx() -> void:
		var r := _rfx(DashboardLive.TEMPO_SPECTRUM)
		draw_rect(r, Color(0.010, 0.020, 0.050, 0.96))
		draw_rect(r.grow(1.0), Color(0.55, 0.45, 1.0, 0.25), false, 1.0)
		draw_line(Vector2(r.position.x + 2.0, r.end.y - 1.0),
				Vector2(r.end.x - 2.0, r.end.y - 1.0), Color(0.5, 0.6, 0.9, 0.35), 1.0)
		var bars := 44
		var t := layer.tick_time
		var pts := PackedVector2Array()
		for i in range(bars + 1):
			var u := float(i) / float(bars)
			var h01 := 0.34 + 0.20 * sin(u * 7.0 + t * 1.9) \
					+ 0.15 * sin(u * 17.0 - t * 1.1) + 0.10 * sin(u * 31.0 + t * 2.7)
			# Absorption dips, like real spectra.
			h01 -= 0.16 * exp(-pow((u - 0.42) * 18.0, 2.0))
			h01 -= 0.10 * exp(-pow((u - 0.68) * 22.0, 2.0))
			h01 = clampf(h01, 0.08, 1.0)
			var bx := r.position.x + 4.0 + (r.size.x - 8.0) * u
			var bh := (r.size.y - 8.0) * h01
			var col := Color.from_hsv(u * 0.72, 0.85, 1.0)
			draw_rect(Rect2(bx - 1.5, r.end.y - 2.0 - bh, 3.0, bh), Color(col.r, col.g, col.b, 0.85))
			pts.append(Vector2(bx, r.end.y - 2.0 - bh))
		if pts.size() >= 2:
			draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.45), 1.2, true)
		var su := fmod(t * 0.12, 1.0)
		var sx := r.position.x + 4.0 + (r.size.x - 8.0) * su
		draw_line(Vector2(sx, r.position.y + 2.0), Vector2(sx, r.end.y - 2.0),
				Color(1.0, 1.0, 1.0, 0.35), 1.5, true)

	func _rfx(parts: Array) -> Rect2:
		return Rect2(parts[0] * size.x, parts[1] * size.y, parts[2] * size.x, parts[3] * size.y)

	## Spacecraft on the real orbit angle, scan beam and downlink packets.
	func _draw_orbit_satellite() -> void:
		var g: Array = DashboardLive.GLOBE.get(layer.mission, [])
		if g.size() != 4:
			return
		var acc: Color = layer.accent
		var c := Vector2((g[0] + g[2] * 0.5) * size.x, (g[1] + g[3] * 0.5) * size.y)
		var r: float = g[3] * size.y * 0.5
		var rx := r * 1.62
		var ry := r * 0.55
		# The satellite rides the real simulation's own orbit angle.
		var a: float = SimulationEngine.orbit_angle
		var pos := c + Vector2(cos(a) * rx, sin(a) * ry).rotated(DashboardLive.ORBIT_TILT)
		var heading := Vector2(-sin(a) * rx, cos(a) * ry).rotated(DashboardLive.ORBIT_TILT).normalized()

		# Fading trail dots along the path just travelled.
		for i in range(7):
			var ta: float = a - float(i + 1) * 0.055
			var tp := c + Vector2(cos(ta) * rx, sin(ta) * ry).rotated(DashboardLive.ORBIT_TILT)
			draw_circle(tp, 3.0, Color(acc.r, acc.g, acc.b, 0.5 - float(i) * 0.07))

		# Scan beam from the spacecraft down to its sub-satellite point.
		if layer.was_scanning:
			var to_c := (c - pos).normalized()
			var sp := c - to_c * r
			var perp := to_c.orthogonal()
			var wedge_w := r * 0.30
			var wedge := PackedVector2Array([pos, sp + perp * wedge_w, sp - perp * wedge_w])
			draw_colored_polygon(wedge, Color(acc.r, acc.g, acc.b, 0.14 + 0.07 * sin(layer.tick_time * 5.0)))
			draw_line(pos, sp, Color(acc.r, acc.g, acc.b, 0.55), 2.0, true)
			draw_arc(c, r * 0.99, a - 0.55, a + 0.55, 24, Color(acc.r, acc.g, acc.b, 0.35), 3.0, true)

		# Spacecraft: glowing bus with two solar wings, oriented along its motion.
		draw_circle(pos, 15.0, Color(acc.r, acc.g, acc.b, 0.16 + 0.07 * sin(layer.tick_time * 3.0)))
		draw_circle(pos, 8.0, Color(acc.r, acc.g, acc.b, 0.30))
		draw_set_transform(pos, heading.angle(), Vector2.ONE)
		draw_rect(Rect2(-7, -4, 14, 8), Color(0.9, 0.95, 1.0, 0.95))
		draw_rect(Rect2(-21, -2, 12, 4), Color(0.25, 0.62, 1.0, 0.95))
		draw_rect(Rect2(9, -2, 12, 4), Color(0.25, 0.62, 1.0, 0.95))
		draw_rect(Rect2(-21, -2, 12, 4), Color(1, 1, 1, 0.35), false, 1.0)
		draw_rect(Rect2(9, -2, 12, 4), Color(1, 1, 1, 0.35), false, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Downlink packets streaming to the art's ground-station panel.
		var gl: Array = DashboardLive.GROUND_LINK.get(layer.mission, [0.83, 0.42])
		var target := Vector2(gl[0] * size.x, gl[1] * size.y)
		draw_line(pos, target, Color(acc.r, acc.g, acc.b, 0.18), 1.0, true)
		var packets := 5 if layer.was_in_contact else 2
		for i in range(packets):
			var u := fmod(layer.tick_time * (0.7 if layer.was_in_contact else 0.35) + float(i) / float(packets), 1.0)
			var p := pos.lerp(target, u)
			draw_circle(p, 4.0 - 2.5 * u, Color(acc.r, acc.g, acc.b, (1.0 - u) * 0.85))

	## TEMPO's flat map: live scan sweep and NASA EONET incident markers.
	func _draw_tempo_map_fx() -> void:
		var mr := _rfx(DashboardLive.TEMPO_MAP)
		# Horizontal scan line sweeping the pollution map, with a glow trail.
		var u := fmod(layer.tick_time * 0.055, 1.0)
		var sx := mr.position.x + mr.size.x * u
		draw_rect(Rect2(maxf(sx - 56.0, mr.position.x), mr.position.y,
				minf(56.0, sx - mr.position.x), mr.size.y), Color(0.6, 0.3, 1.0, 0.06))
		draw_line(Vector2(sx, mr.position.y), Vector2(sx, mr.end.y),
				Color(0.75, 0.45, 1.0, 0.55), 2.0, true)
		draw_line(Vector2(sx, mr.position.y), Vector2(sx, mr.end.y),
				Color(1.0, 1.0, 1.0, 0.25), 1.0, true)
		# Plot NASA EONET incident locations instead of invented hotspots.
		for i in range(mini(layer.tempo_incidents.size(), 60)):
			var event: Dictionary = layer.tempo_incidents[i]
			var lon := float(event.get("lon", 0.0))
			var lat := float(event.get("lat", 0.0))
			var west: float = DashboardLive.TEMPO_VIEW_BOUNDS[0]
			var east: float = DashboardLive.TEMPO_VIEW_BOUNDS[1]
			var south: float = DashboardLive.TEMPO_VIEW_BOUNDS[2]
			var north: float = DashboardLive.TEMPO_VIEW_BOUNDS[3]
			var p := Vector2(
				mr.position.x + mr.size.x * (lon - west) / (east - west),
				mr.position.y + mr.size.y * (north - lat) / (north - south))
			var selected := i == layer.incident_index
			var pulse := 0.5 + 0.5 * sin(layer.tick_time * 2.4 + float(i))
			var col := Color(1.0, 0.48, 0.22, 0.75) if selected else Color(1.0, 0.72, 0.30, 0.58)
			if selected:
				draw_circle(p, 10.0 + 4.0 * pulse, Color(col.r, col.g, col.b, 0.12 + 0.10 * pulse))
				draw_arc(p, 9.0 + 4.0 * pulse, 0.0, TAU, 24, col, 1.5, true)
			draw_circle(p, 3.5 if selected else 2.5, col)

## Called by OrbitMission whenever the mission mode or accent changes.
func set_mission(mode: String, new_accent: Color) -> void:
	mission = mode
	accent = new_accent
	scan_progress = 0.72
	water_series.clear()
	for i in range(24):
		water_series.append(0.35 + sin(i * 0.55) * 0.25)
	water_peak = 0.62
	for tile in tiles:
		tile.visible = mode == "SWOT"
	# The rotating globe only exists on missions whose art shows a planet.
	if globe != null:
		var g: Array = GLOBE.get(mode, [])
		globe.visible = g.size() == 4
		if g.size() == 4:
			globe.anchor_left = g[0]
			globe.anchor_top = g[1]
			globe.anchor_right = g[0] + g[2]
			globe.anchor_bottom = g[1] + g[3]
			for off in ["offset_left", "offset_top", "offset_right", "offset_bottom"]:
				globe.set(off, 0.0)
			var cuts: Array = GLOBE_CUTOUTS.get(mode, [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]])
			if globe.material is ShaderMaterial and cuts.size() == 2:
				var sm := globe.material as ShaderMaterial
				var ca: Array = cuts[0]
				var cb: Array = cuts[1]
				sm.set_shader_parameter("cutout_a",
						Vector4(ca[0], ca[1], ca[2], ca[3]))
				sm.set_shader_parameter("cutout_b",
						Vector4(cb[0], cb[1], cb[2], cb[3]))
	if not mission in fetched_missions:
		fetched_missions.append(mission)
		# A fetch that finished while another mission was showing may already
		# have delivered this mission's real data — use it before fetching.
		var ready_feed: Dictionary = mission_feeds.get(mode, {})
		if ready_feed.has("lines"):
			feed_lines = PackedStringArray(ready_feed["lines"])
			feed_source = String(ready_feed["source"])
			feed_is_live = true
		else:
			feed_lines = PackedStringArray(FALLBACK_FEEDS.get(mode, []))
			feed_is_live = false
			feed_source = "fallback"
			_start_feed_fetch(mode)
	if mode == "TEMPO":
		_load_incident_cache()
		_restore_selected_incident_samples()
		incident_refresh_timer = 0.0
		_start_incident_fetch()
		_start_tempo_dimensions_fetch()
	_queue_refresh()

## Per-frame simulation feed from OrbitMission.
func tick(delta: float, state: Dictionary) -> void:
	sim_state = state
	tick_time += delta
	_advance_scan_machine(delta)
	_advance_water_chart(delta)
	_advance_contact_countdown(delta)
	feed_timer += delta
	if feed_lines.size() > 0 and feed_timer > 7.0:
		feed_timer = 0.0
		feed_index = (feed_index + 1) % feed_lines.size()
	if mission == "TEMPO":
		incident_refresh_timer += delta
		if tempo_toast_timer > 0.0:
			tempo_toast_timer -= delta
			if tempo_toast_timer <= 0.0:
				tempo_toast = ""
		if incident_refresh_timer >= INCIDENT_REFRESH_SECONDS:
			incident_refresh_timer = 0.0
			_start_incident_fetch()
			_start_tempo_dimensions_fetch()
	_queue_refresh()

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	queue_redraw()
	if vfx_top != null:
		vfx_top.queue_redraw()

func _queue_refresh() -> void:
	if is_visible_in_tree():
		queue_redraw()

## ─── Simulation-driven values ────────────────────────────────────────────────
func _advance_scan_machine(delta: float) -> void:
	var status := String(sim_state.get("scan_status", ""))
	var scanning: bool = status.begins_with("Scanning")
	if status != last_status:
		if status.begins_with("task accepted") or status.begins_with("Awaiting") \
				or status.begins_with("Select") or status.begins_with("This incident") \
				or status.begins_with("%s payload" % mission):
			scan_progress = 0.0
		elif status.begins_with("Scan complete"):
			scan_progress = 1.0
	if scanning:
		scan_progress = minf(scan_progress + delta / scan_duration, 0.999)
		# New samples stream in faster while KaRIn is actually observing.
		water_timer += delta * 2.4
	elif was_scanning:
		scan_progress = 1.0
	was_scanning = scanning
	last_status = status
	var payload_live: bool = bool(sim_state.get("instruments_active", true))
	if payload_live and not scanning:
		water_timer += delta * 0.6
		# Ozone remains illustrative; NO2 is sampled from the NASA TEMPO service.
	if payload_live:
		var wobble := sin(tick_time * 0.7) * 0.15 + sin(tick_time * 0.23) * 0.1
		_o3_value = clampf(410.0 + wobble * 8.0 + scan_progress * 30.0, 380.0, 460.0)

func _advance_water_chart(delta: float) -> void:
	if water_timer < 1.4:
		return
	water_timer = fmod(water_timer, 1.4)
	var scanning: bool = was_scanning
	var drift: float = sin(tick_time * 0.4) * 0.3 + sin(tick_time * 1.7) * 0.12
	if scanning:
		drift += scan_progress * 0.55
	water_value = clampf(water_value * 0.7 + (0.35 + drift) * 0.3, -1.0, 1.0)
	water_series.append(water_value)
	while water_series.size() > 32:
		water_series.remove_at(0)
	var peak := -1.5
	for v in water_series:
		peak = maxf(peak, v)
	water_peak = peak

func _advance_contact_countdown(delta: float) -> void:
	var in_contact: bool = bool(sim_state.get("ground_contact", false))
	if in_contact and not was_in_contact:
		contact_countdown = 756.0
	was_in_contact = in_contact
	if not in_contact:
		contact_countdown -= delta
		if contact_countdown <= 0.0:
			contact_countdown = 756.0

## ─── Real NASA data fetch ────────────────────────────────────────────────────
func _cache_path_for(mode: String) -> String:
	return FEED_CACHE + mode.replace(" ", "_").replace("/", "_") + ".json"

func _cache_path() -> String:
	return _cache_path_for(mission)

func _start_feed_fetch(mode: String) -> void:
	var cache := _cache_path_for(mode)
	var now: float = Time.get_unix_time_from_system()
	if FileAccess.file_exists(cache):
		var f := FileAccess.open(cache, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			if data is Dictionary and float(data.get("ts", 0.0)) > now - 86400.0:
				var lines: Array = data.get("lines", [])
				if lines.size() >= 3:
					feed_lines = PackedStringArray(lines)
					feed_is_live = bool(data.get("live", false))
					feed_source = String(data.get("source", "api"))
					_apply_cached_tiles(data.get("thumbs", []))
					return
	# Fresh fetch: the official science.nasa.gov mission page first, then the
	# image library API, then the built-in real mission facts.
	_request_text(String(MISSION_PAGES.get(mode, MISSION_PAGES["SWOT"])), _on_mission_page.bind(mode))

## Reads the real mission facts straight off the official science.nasa.gov page.
func _on_mission_page(html: String, mode: String) -> void:
	var facts := _parse_facts(html)
	if DEBUG_LOGS:
		print("[DashboardLive] %s page facts=%d" % [mode, facts.size()])
	if facts.size() >= 3:
		mission_feeds[mode] = {"lines": PackedStringArray(facts), "source": "page"}
		if mode != mission:
			# The player already switched missions while this fetch was in
			# flight — record it for their return, never touch the live ticker.
			_save_cache_for(mode, PackedStringArray(facts), "page")
			return
		feed_lines = PackedStringArray(facts)
		feed_is_live = true
		feed_source = "page"
		_save_cache_for(mode, feed_lines, feed_source)
		_finish_feed(mode)
		return
	# Page unavailable or unparseable — fall back to the image library API.
	_request_text("https://images-api.nasa.gov/search?q=%s&media_type=image" % FEED_QUERIES.get(mode, "SWOT"),
			_on_feed_json.bind(mode))

func _on_feed_json(text: String, mode: String) -> void:
	var titles: Array[String] = []
	if not text.is_empty():
		var data = JSON.parse_string(text)
		if data is Dictionary:
			var items: Array = data.get("collection", {}).get("items", [])
			for item in items:
				if not (item is Dictionary):
					continue
				var d: Array = item.get("data", [])
				var title := String(d[0].get("title", "")) if d.size() > 0 and d[0] is Dictionary else ""
				if title.length() > 24:
					titles.append(title)
				if titles.size() >= 6:
					break
	if titles.size() < 3:
		return
	mission_feeds[mode] = {"lines": PackedStringArray(titles), "source": "api"}
	if mode != mission:
		_save_cache_for(mode, PackedStringArray(titles), "api")
		return
	feed_lines = PackedStringArray(titles)
	feed_is_live = true
	feed_source = "api"
	_save_cache_for(mode, feed_lines, feed_source)
	_finish_feed(mode)

func _finish_feed(mode: String) -> void:
	if mode == "SWOT":
		_fetch_tiles()

## Extracts readable fact sentences from the mission page HTML: scripts and
## styles out, tags out, entities unescaped, then the boilerplate filtered.
func _parse_facts(html: String) -> Array[String]:
	if html.is_empty():
		return []
	var text := _extract_text(html)
	var facts: Array[String] = []
	# The mission pages embed a structured summary block:
	#   "<Mission> ... Active Mission <summary paragraph> Type <instrument>
	#    Launch <date> Target <planet> Objective <objective text> Learn more ..."
	# Read it directly — far more reliable than sentence-guessing nav text.
	var core := text
	var am := text.find("Active Mission")
	if am != -1:
		core = text.substr(am + "Active Mission".length())
	var t_idx := core.find(" Type ")
	if t_idx != -1:
		var summary := core.substr(0, t_idx).strip_edges()
		for s in summary.split(". "):
			var piece := s.strip_edges()
			if piece.length() >= 40 and piece.length() <= 240 and not _is_boilerplate(piece):
				facts.append(_tidy(piece))
	var o_idx := core.find("Objective ")
	if o_idx != -1:
		var after := core.substr(o_idx + "Objective ".length())
		var l_idx := after.length()
		for stop in ["Learn more about", " NOAA Website", "Website", "Featured Video",
				"Featured ", " Stories", "Story "]:
			var si := after.find(stop)
			if si != -1 and si < l_idx:
				l_idx = si
		var obj := after.substr(0, l_idx).strip_edges()
		if obj.length() >= 20 and obj.length() <= 280 and not _is_boilerplate(obj):
			facts.append(_tidy(obj))
	# General sentence sweep over the whole page as extra filler.
	for sentence in text.split(". "):
		if facts.size() >= 6:
			break
		var s := sentence.strip_edges()
		if s.length() < 60 or s.length() > 240:
			continue
		if _is_boilerplate(s):
			continue
		var dup := false
		for f in facts:
			if f.find(s.substr(0, mini(30, s.length()))) != -1 or s.find(f.substr(0, mini(30, f.length()))) != -1:
				dup = true
				break
		if dup:
			continue
		facts.append(_tidy(s))
	return facts

func _tidy(s: String) -> String:
	if not s.ends_with(".") and not s.ends_with("!") and not s.ends_with("?"):
		s += "."
	return s

## Strips scripts/styles/tags out of an HTML page and collapses whitespace,
## leaving plain readable text for the fact extractor.
func _extract_text(html: String) -> String:
	var text := html
	for tag: String in ["script", "style", "noscript", "svg"]:
		var open: String = "<" + tag
		var close: String = "</" + tag + ">"
		while true:
			var start := text.find(open)
			if start == -1:
				break
			var end := text.find(close, start)
			if end == -1:
				text = text.substr(0, start)
				break
			text = text.substr(0, start) + " " + text.substr(end + close.length())
	var tags := RegEx.new()
	if tags.compile("<[^>]*>") == OK:
		text = tags.sub(text, " ", true)
	text = _unescape_entities(text)
	var ws := RegEx.new()
	if ws.compile("\\s+") == OK:
		text = ws.sub(text, " ", true)
	return text

func _is_boilerplate(s: String) -> bool:
	for junk in ["cookie", "Cookie", "subscribe", "Subscribe", "newsletter", "Sign up",
			"Skip to", "JavaScript", "javascript", "©", "Copyright", "copyright",
			"@media", "function(", "window.", "http://", "https://", ".gov/",
			"Min Read", "article ", "Explore", "Discover", "Read More",
			"Suggested Searches", "Watch", "Videos", "\uFFFD", "La NASA",
			"La agencia", "Eclipse", "Artemis", "Voyager", "Chandra", "Hubble"]:
		if s.find(junk) != -1:
			return true
	return false

func _unescape_entities(s: String) -> String:
	var pairs := [["&amp;", "&"], ["&#8217;", "'"], ["&rsquo;", "'"], ["&#8216;", "'"],
		["&quot;", '"'], ["&#34;", '"'], ["&nbsp;", " "], ["&#8211;", "-"],
		["&ndash;", "-"], ["&#8212;", "—"], ["&mdash;", "—"], ["&hellip;", "…"],
		["&lt;", "<"], ["&gt;", ">"], ["&#39;", "'"]]
	for p in pairs:
		s = s.replace(p[0], p[1])
	return s

## Offline-first tiles: restore the last known real NASA imagery from cache.
func _apply_cached_tiles(thumbs: Array) -> void:
	for i in range(mini(thumbs.size(), tiles.size())):
		var url := String(thumbs[i])
		if url.is_empty():
			continue
		var tex := ClimateMedia.load_cached(url)
		if tex != null:
			tiles[i].texture = tex

## The three SWOT data-product tiles are replaced by real NASA imagery.
func _fetch_tiles() -> void:
	tile_urls = ["", "", ""]
	for i in range(TILE_QUERIES.size()):
		_request_text("https://images-api.nasa.gov/search?q=%s&media_type=image" % TILE_QUERIES[i],
				_on_tile_json.bind(i))

func _on_tile_json(text: String, index: int) -> void:
	var thumb := ""
	if not text.is_empty():
		var data = JSON.parse_string(text)
		if data is Dictionary:
			var items: Array = data.get("collection", {}).get("items", [])
			for item in items:
				if item is Dictionary:
					var links: Array = item.get("links", [])
					if links.size() > 0 and links[0] is Dictionary:
						var href := String(links[0].get("href", ""))
						if href.ends_with(".jpg") or href.ends_with(".png"):
							thumb = href
							break
	if thumb.is_empty() or index >= tiles.size():
		return
	tile_urls[index] = thumb
	# Tiles belong to SWOT only; skip saving if the player has moved elsewhere
	# so their tile URLs never leak into another mission's cache file.
	if mission == "SWOT":
		_save_cache_for("SWOT", feed_lines, feed_source)
	_fetch_image(thumb, index)

## Record feed lines and tile thumbs so the next run is fully offline.
func _save_cache() -> void:
	_save_cache_for(mission, feed_lines, feed_source)

## Writes one mission's feed snapshot for offline replay.  Always keyed by the
## mode the data belongs to — never the mission the player happens to be
## looking at when the response lands.
func _save_cache_for(mode: String, lines: PackedStringArray, source: String) -> void:
	var f := FileAccess.open(_cache_path_for(mode), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"ts": Time.get_unix_time_from_system(),
			"lines": lines,
			"live": true,
			"source": source,
			"thumbs": tile_urls,
		}))
		if DEBUG_LOGS:
			print("[DashboardLive] cache saved: %s (lines=%d source=%s)" % [_cache_path_for(mode), lines.size(), source])
	elif DEBUG_LOGS:
		print("[DashboardLive] cache open FAILED: %s err=%d" % [_cache_path_for(mode), FileAccess.get_open_error()])

func _fetch_image(url: String, index: int) -> void:
	var cached := ClimateMedia.load_cached(url)
	if cached != null:
		tiles[index].texture = cached
		return
	var req := HTTPRequest.new()
	req.timeout = 25.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var tex := ClimateMedia.load_cached(url)
			if tex != null and index < tiles.size():
				tiles[index].texture = tex
	)
	DirAccess.make_dir_recursive_absolute(ClimateMedia.CACHE_DIR)
	req.download_file = ClimateMedia.cache_path(url)
	req.request(url)

func _request_text(url: String, cb: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	var started := tick_time
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if DEBUG_LOGS:
			print("[DashboardLive] fetch %s -> result=%d code=%d bytes=%d (%.1fs)" % [url.get_slice("/", 2), result, code, body.size(), tick_time - started])
		cb.call(body.get_string_from_utf8() if result == HTTPRequest.RESULT_SUCCESS and code == 200 else "")
	)
	var err := req.request(url)
	if err != OK:
		if DEBUG_LOGS:
			print("[DashboardLive] request() failed immediately: %d for %s" % [err, url])

func _start_incident_fetch() -> void:
	if incident_fetch_in_progress:
		return
	incident_fetch_in_progress = true
	if tempo_incidents.is_empty():
		incident_feed_status = "loading"
	_request_text(TEMPO_INCIDENTS_URL, _on_incident_feed)

func _on_incident_feed(text: String) -> void:
	incident_fetch_in_progress = false
	if text.is_empty():
		incident_feed_status = "cached" if not tempo_incidents.is_empty() else "offline"
		_queue_refresh()
		return
	var payload = JSON.parse_string(text)
	if not (payload is Dictionary):
		incident_feed_status = "cached" if not tempo_incidents.is_empty() else "offline"
		_queue_refresh()
		return

	var records: Array = payload.get("features", [])
	var geojson := not records.is_empty()
	if not geojson:
		records = payload.get("events", [])
	var fresh: Array[Dictionary] = []
	for record in records:
		if not (record is Dictionary):
			continue
		var properties: Dictionary = record.get("properties", record)
		var geometry: Variant = record.get("geometry", {})
		if geometry is Array:
			if geometry.is_empty():
				continue
			geometry = geometry[geometry.size() - 1]
		if not (geometry is Dictionary):
			continue
		var location := _incident_location(geometry)
		if location.x < TEMPO_VIEW_BOUNDS[0] or location.x > TEMPO_VIEW_BOUNDS[1] \
				or location.y < TEMPO_VIEW_BOUNDS[2] or location.y > TEMPO_VIEW_BOUNDS[3]:
			continue
		var title := String(properties.get("title", "Environmental event")).strip_edges()
		var event_date := String(geometry.get("date", properties.get("date", "")))
		fresh.append({
			"id": String(properties.get("id", record.get("id", title))),
			"title": title,
			"lon": location.x,
			"lat": location.y,
			"date": event_date,
			"link": String(properties.get("link", "")),
		})

	tempo_incidents = fresh
	incident_index = 0
	incident_feed_status = "live"
	_restore_selected_incident_samples()
	_save_incident_cache()
	_request_tempo_no2_history()
	_queue_refresh()

func _start_tempo_dimensions_fetch() -> void:
	if tempo_dimensions_fetch_in_progress:
		return
	tempo_dimensions_fetch_in_progress = true
	if tempo_no2_history.is_empty():
		tempo_no2_status = "loading"
	_request_text(TEMPO_NO2_SERVICE + "/multidimensionalInfo?f=json", _on_tempo_dimensions)

func _on_tempo_dimensions(text: String) -> void:
	tempo_dimensions_fetch_in_progress = false
	var payload = JSON.parse_string(text) if not text.is_empty() else null
	if not (payload is Dictionary):
		tempo_manual_scan_pending = false
		tempo_no2_status = "cached" if not tempo_no2_history.is_empty() else "offline"
		_queue_refresh()
		return
	var info: Dictionary = payload.get("multidimensionalInfo", {})
	for variable in info.get("variables", []):
		if not (variable is Dictionary) or String(variable.get("name", "")) != "NO2_Troposphere":
			continue
		for dimension in variable.get("dimensions", []):
			if dimension is Dictionary and String(dimension.get("name", "")) == "StdTime":
				tempo_scan_times.clear()
				for scan_time in dimension.get("values", []):
					tempo_scan_times.append(int(scan_time))
				break
		break
	if tempo_scan_times.is_empty():
		tempo_manual_scan_pending = false
		tempo_no2_status = "cached" if not tempo_no2_history.is_empty() else "offline"
	else:
		var force_scan := tempo_manual_scan_pending
		tempo_manual_scan_pending = false
		_request_tempo_no2_history(force_scan)
	_queue_refresh()

func _restore_selected_incident_samples() -> void:
	tempo_no2_history.clear()
	if tempo_incidents.is_empty():
		tempo_no2_status = "loading" if tempo_scan_times.is_empty() else "no_data"
		return
	var current: Dictionary = tempo_incidents[incident_index % tempo_incidents.size()]
	var saved: Variant = current.get("no2_history", [])
	if saved is Array:
		for sample in saved:
			if sample is Dictionary:
				tempo_no2_history.append(sample)
	if not tempo_no2_history.is_empty():
		tempo_no2_status = "cached" if incident_feed_status == "cached" else String(current.get("no2_status", "live"))
	else:
		tempo_no2_status = String(current.get("no2_status", "loading"))

## ────────────────────────────────────────────────────────────────────────────
## Bottom TEMPO command buttons
## ────────────────────────────────────────────────────────────────────────────

func select_next_incident() -> void:
	if tempo_incidents.size() <= 1:
		_show_toast("NO OTHER ACTIVE INCIDENTS")
		return
	incident_index = (incident_index + 1) % tempo_incidents.size()
	tempo_fallback_attempted.clear()
	tempo_hour_compare_on = false
	tempo_no2_column_panel_on = false
	_restore_selected_incident_samples()
	_request_tempo_no2_history()
	var cur: Dictionary = tempo_incidents[incident_index % tempo_incidents.size()]
	_show_toast("REGION → %s" % String(cur.get("title", "Incident")))
	_queue_refresh()

func force_no2_refresh() -> void:
	if tempo_incidents.is_empty():
		_show_toast("NO INCIDENT LOADED YET")
		return
	if tempo_sample_fetch_in_progress:
		_show_toast("SCAN ALREADY IN PROGRESS…")
		return
	tempo_fallback_attempted.clear()
	if tempo_dimensions_fetch_in_progress or tempo_scan_times.is_empty():
		tempo_manual_scan_pending = true
		if not tempo_dimensions_fetch_in_progress:
			_start_tempo_dimensions_fetch()
		_show_toast("SCAN QUEUED — LOADING TEMPO SCAN TIMES")
		return
	tempo_no2_status = "loading"
	tempo_used_fallback_city = ""
	_show_toast("SCANNING NO₂ NRT…")
	_request_tempo_no2_history(true)

func toggle_hour_compare() -> void:
	if tempo_no2_history.size() < 2:
		_show_toast("NEED ≥2 SCANS TO COMPARE")
		return
	tempo_hour_compare_on = not tempo_hour_compare_on
	tempo_no2_column_panel_on = false
	_show_toast("HOUR COMPARE %s" % ("ON" if tempo_hour_compare_on else "OFF"))
	_queue_refresh()

func toggle_no2_column_panel() -> void:
	tempo_no2_column_panel_on = not tempo_no2_column_panel_on
	tempo_hour_compare_on = false
	_show_toast("NO₂ COLUMN PANEL %s" % ("ON" if tempo_no2_column_panel_on else "OFF"))
	_queue_refresh()

func toggle_ozone_monitoring() -> void:
	tempo_ozone_monitoring_on = not tempo_ozone_monitoring_on
	_show_toast("O₃ MONITORING %s" % ("ON" if tempo_ozone_monitoring_on else "OFF"))
	_queue_refresh()

func _show_toast(msg: String) -> void:
	tempo_toast = msg
	tempo_toast_timer = 3.5
	_queue_refresh()

func _request_tempo_no2_history(force: bool = false, fallback_city: Dictionary = {}) -> void:
	if tempo_sample_fetch_in_progress or tempo_dimensions_fetch_in_progress \
			or tempo_scan_times.is_empty() or tempo_incidents.is_empty():
		return
	var event: Dictionary = tempo_incidents[incident_index % tempo_incidents.size()]
	var event_id := String(event.get("id", event.get("title", "")))
	var checked_at := float(event.get("no2_checked", 0.0))
	if not force and not fallback_city.is_empty():
		# Fallback requests always bypass the cache check.
		pass
	elif not force and Time.get_unix_time_from_system() - checked_at < INCIDENT_REFRESH_SECONDS:
		_restore_selected_incident_samples()
		return

	var lon := float(event.get("lon", 0.0))
	var lat := float(event.get("lat", 0.0))
	if not fallback_city.is_empty():
		lon = float(fallback_city.get("lon", lon))
		lat = float(fallback_city.get("lat", lat))
		tempo_used_fallback_city = String(fallback_city.get("name", ""))
		if not tempo_fallback_attempted.has(tempo_used_fallback_city):
			tempo_fallback_attempted.append(tempo_used_fallback_city)
	# Wider search grid: 3x3 at 0.06° spacing covers a ~0.12° box (~13 km),
	# enough to find valid pixels when the incident point itself is filtered.
	var offsets: Array = []
	for gx in range(-1, 2):
		for gy in range(-1, 2):
			offsets.append([float(gx) * 0.06, float(gy) * 0.06])
	var points: Array = []
	for offset in offsets:
		points.append([lon + offset[0], lat + offset[1]])
	var scan_times: Array[int] = []
	var first_time := maxi(0, tempo_scan_times.size() - NO2_HISTORY_LIMIT)
	for i in range(first_time, tempo_scan_times.size()):
		scan_times.append(tempo_scan_times[i])
	var geometry := JSON.stringify({
		"points": points,
		"spatialReference": {"wkid": 4326},
	}).uri_encode()
	var mosaic_rule := JSON.stringify({
		"multidimensionalDefinition": [{
			"dimensionName": "StdTime",
			"values": scan_times,
			"isSlice": false,
		}],
	}).uri_encode()
	var url := "%s/getSamples?geometry=%s&geometryType=esriGeometryMultipoint&mosaicRule=%s&returnFirstValueOnly=false&returnGeometry=false&f=json" % [
		TEMPO_NO2_SERVICE, geometry, mosaic_rule]
	tempo_sample_fetch_in_progress = true
	if fallback_city.is_empty():
		tempo_used_fallback_city = ""
	tempo_no2_status = "loading"
	_queue_refresh()
	_request_text(url, _on_tempo_no2_samples.bind(event_id, fallback_city))

func _on_tempo_no2_samples(text: String, event_id: String, fallback_city: Dictionary = {}) -> void:
	tempo_sample_fetch_in_progress = false
	var payload = JSON.parse_string(text) if not text.is_empty() else null
	var samples_by_time: Dictionary = {}
	if payload is Dictionary:
		for sample in payload.get("samples", []):
			if not (sample is Dictionary):
				continue
			var attributes: Dictionary = sample.get("attributes", {})
			var sample_time := int(attributes.get("StdTime", 0))
			var location_id := int(sample.get("locationId", 999))
			var raw_value := String(sample.get("value", ""))
			if sample_time <= 0 or not raw_value.is_valid_float():
				continue
			var value := raw_value.to_float()
			if value <= 0.0 or value >= 1.0e18:
				continue
			if not samples_by_time.has(sample_time) \
					or location_id < int(samples_by_time[sample_time]["location_id"]):
				samples_by_time[sample_time] = {
					"time": sample_time,
					"value": value / 1.0e15,
					"location_id": location_id,
				}

	var history: Array[Dictionary] = []
	for sample_time in tempo_scan_times:
		if samples_by_time.has(sample_time):
			history.append(samples_by_time[sample_time])
	var sample_status := "offline"
	if payload is Dictionary and payload.has("samples"):
		sample_status = "no_data"
	var found_event := false
	for i in range(tempo_incidents.size()):
		if String(tempo_incidents[i].get("id", tempo_incidents[i].get("title", ""))) != event_id:
			continue
		var updated: Dictionary = tempo_incidents[i]
		updated["no2_history"] = history
		updated["no2_checked"] = Time.get_unix_time_from_system()
		updated["no2_status"] = "live" if not history.is_empty() else sample_status
		tempo_incidents[i] = updated
		found_event = true
		if i == incident_index:
			tempo_no2_history = history
			tempo_no2_status = String(updated["no2_status"])
		break
	if found_event:
		_save_incident_cache()
		if not tempo_incidents.is_empty():
			var selected: Dictionary = tempo_incidents[incident_index % tempo_incidents.size()]
			var selected_id := String(selected.get("id", selected.get("title", "")))
			if event_id != selected_id:
				_request_tempo_no2_history()
				return
		# Keep trying the next nearest metro if this incident and the last
		# fallback location had no unfiltered pixels in the current NRT slices.
		if history.is_empty() and found_event:
			var next_city := _nearest_fallback_city(event_id)
			if not next_city.is_empty():
				_show_toast("NO PIXELS HERE — TRYING %s" % String(next_city.get("name", "")).to_upper())
				_request_tempo_no2_history(false, next_city)
				return
	_queue_refresh()

func _nearest_fallback_city(event_id: String) -> Dictionary:
	var ev_lon := 0.0
	var ev_lat := 0.0
	for i in range(tempo_incidents.size()):
		if String(tempo_incidents[i].get("id", tempo_incidents[i].get("title", ""))) == event_id:
			ev_lon = float(tempo_incidents[i].get("lon", 0.0))
			ev_lat = float(tempo_incidents[i].get("lat", 0.0))
			break
	var best: Dictionary = {}
	var best_dist := INF
	for city in TEMPO_FALLBACK_CITIES:
		if tempo_fallback_attempted.has(String(city.get("name", ""))):
			continue
		var d := pow(float(city.get("lon", 0.0)) - ev_lon, 2.0) + pow(float(city.get("lat", 0.0)) - ev_lat, 2.0)
		if d < best_dist:
			best_dist = d
			best = city
	return best

func _incident_location(geometry: Dictionary) -> Vector2:
	var coords: Variant = geometry.get("coordinates", [])
	if not (coords is Array) or coords.is_empty():
		return Vector2(INF, INF)
	var geometry_type := String(geometry.get("type", ""))
	if geometry_type == "Point":
		if coords.size() >= 2:
			return Vector2(float(coords[0]), float(coords[1]))
		return Vector2(INF, INF)

	var points: Variant = coords
	if geometry_type == "Polygon":
		points = coords[0] if coords[0] is Array else []
	elif geometry_type == "MultiPolygon":
		points = coords[0][0] if coords[0] is Array and not coords[0].is_empty() else []
	elif geometry_type == "MultiLineString":
		points = coords[0] if coords[0] is Array else []
	if not (points is Array) or points.is_empty():
		return Vector2(INF, INF)
	var lon_total := 0.0
	var lat_total := 0.0
	var point_count := 0
	for point in points:
		if point is Array and point.size() >= 2:
			lon_total += float(point[0])
			lat_total += float(point[1])
			point_count += 1
	if point_count == 0:
		return Vector2(INF, INF)
	return Vector2(lon_total / point_count, lat_total / point_count)

func _load_incident_cache() -> void:
	if not tempo_incidents.is_empty() or incident_feed_status != "loading":
		return
	if not FileAccess.file_exists(TEMPO_INCIDENT_CACHE):
		return
	var file := FileAccess.open(TEMPO_INCIDENT_CACHE, FileAccess.READ)
	if file == null:
		return
	var payload = JSON.parse_string(file.get_as_text())
	if not (payload is Dictionary):
		return
	var records: Variant = payload.get("events", [])
	if not (records is Array):
		return
	for record in records:
		if record is Dictionary:
			tempo_incidents.append(record)
	incident_feed_status = "cached"

func _save_incident_cache() -> void:
	var file := FileAccess.open(TEMPO_INCIDENT_CACHE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"ts": Time.get_unix_time_from_system(),
			"events": tempo_incidents,
		}))

## ─── Drawing ─────────────────────────────────────────────────────────────────
func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	match mission:
		"SWOT":
			_draw_swot(font)
		"TEMPO":
			_draw_tempo(font)
		_:
			_draw_jpss(font)
	if mission != "TEMPO" and GLOBE.has(mission):
		_draw_orbit_path()
	_draw_ticker(font)

## The orbit path drawn under the globe: a dashed ellipse matching the
## artwork's own ground track, animated by the real simulation orbit angle.
func _draw_orbit_path() -> void:
	var g: Array = GLOBE[mission]
	var c := Vector2((g[0] + g[2] * 0.5) * size.x, (g[1] + g[3] * 0.5) * size.y)
	var r: float = g[3] * size.y * 0.5
	var rx := r * 1.62
	var ry := r * 0.55
	var segs := 64
	var phase := fmod(tick_time * 0.22, 1.0)
	var pts := PackedVector2Array()
	for i in range(segs + 1):
		var a := TAU * (float(i) / segs + phase)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(ORBIT_TILT))
	# Two passes: wide soft glow + crisp dashes riding the glow.
	draw_polyline(pts, Color(accent.r, accent.g, accent.b, 0.10), 5.0, true)
	var dash := PackedVector2Array()
	for i in range(segs + 1):
		if i % 4 < 2:
			dash.append(pts[i])
	if dash.size() >= 2:
		draw_polyline(dash, Color(accent.r, accent.g, accent.b, 0.45), 1.5, true)

func _rf(parts: Array) -> Rect2:
	return Rect2(Vector2(parts[0] * size.x, parts[1] * size.y), Vector2(parts[2] * size.x, parts[3] * size.y))

func _panel_bg(r: Rect2) -> void:
	draw_rect(r, Color(0.008, 0.031, 0.075, 0.97))

func _chip(font: Font, key: String, text: String, font_size: int, color: Color, right_align: bool = false) -> void:
	var r := _rf(WIDGETS[mission][key])
	_panel_bg(r)
	var pad := 8.0
	var pos := Vector2(r.position.x + pad, r.position.y + r.size.y * 0.5)
	if right_align:
		draw_string(font, Vector2(r.position.x, pos.y + font_size * 0.4), text,
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - pad, font_size, color)
	else:
		draw_string(font, Vector2(r.position.x + pad, pos.y + font_size * 0.4), text,
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - pad * 2.0, font_size, color)

func _utc_string() -> String:
	var t := Time.get_time_dict_from_system(true)
	return "%02d:%02d UTC" % [int(t["hour"]), int(t["minute"])]

func _countdown(seconds: float) -> String:
	var s := int(maxf(seconds, 0.0))
	return "%d min %02d s" % [s / 60, s % 60]

func _blink(alpha_speed: float = 4.0) -> float:
	return 0.55 + 0.45 * sin(tick_time * alpha_speed)

func _draw_swot(font: Font) -> void:
	var w: Dictionary = WIDGETS["SWOT"]
	# Acquisition progress — driven by the real scan state machine.
	var bar := _rf(w["progress_bar"])
	_panel_bg(bar)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * scan_progress, bar.size.y)), accent)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * scan_progress, bar.size.y * 0.45)),
			Color(1, 1, 1, 0.25))
	var segments := 24
	for i in range(1, segments):
		var x := bar.position.x + bar.size.x * i / segments
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0.05, 0.1, 0.65), 1.0)
	_chip(font, "progress_pct", "%d%%" % int(round(scan_progress * 100.0)), 15, Color(0.92, 0.98, 1.0))
	# Status line — the simulation's own scan status, blinking when working.
	var st := _rf(w["status_line"])
	_panel_bg(st)
	var status := String(sim_state.get("scan_status", "Standing by"))
	if status.begins_with("Select"):
		status = "Ready — select a target and start acquisition"
	if was_scanning:
		draw_circle(Vector2(st.position.x + 12.0, st.position.y + st.size.y * 0.5), 5.0, Color(0.2, 1.0, 0.5, _blink()))
	else:
		draw_circle(Vector2(st.position.x + 12.0, st.position.y + st.size.y * 0.5), 5.0, Color(0.2, 1.0, 0.5, 0.35))
	draw_string(font, Vector2(st.position.x + 24.0, st.position.y + st.size.y * 0.5 + 5.0),
			status, HORIZONTAL_ALIGNMENT_LEFT, st.size.x - 30.0, 12, Color(0.88, 0.96, 1.0))
	var tl := _rf(w["time_left"])
	_panel_bg(tl)
	var remaining := "Time Remaining: --"
	if scan_progress > 0.01 and scan_progress < 1.0:
		remaining = "Time Remaining: %s" % _countdown((1.0 - scan_progress) * scan_duration)
	elif scan_progress >= 1.0:
		remaining = "Time Remaining: 00 min 00 s"
	draw_string(font, tl.position, remaining, HORIZONTAL_ALIGNMENT_RIGHT, tl.size.x - 4.0, 11, Color(0.88, 0.96, 1.0))
	# Water elevation chart — live rolling series with a glowing peak marker.
	var ch := _rf(w["water_chart"])
	_panel_bg(ch)
	for i in range(5):
		var gy := ch.position.y + ch.size.y * i / 4.0
		draw_line(Vector2(ch.position.x, gy), Vector2(ch.end.x, gy), Color(accent.r, accent.g, accent.b, 0.12), 1.0)
	var pts := PackedVector2Array()
	var n := water_series.size()
	for i in range(n):
		var vx := ch.position.x + ch.size.x * i / maxf(n - 1, 1.0)
		var vy := ch.position.y + ch.size.y * (0.5 - water_series[i] * 0.42)
		pts.append(Vector2(vx, vy))
	# VFX: luminous area fill under the curve, then a wide soft glow pass
	# under the crisp line.
	var fill := PackedVector2Array(pts)
	fill.append(Vector2(ch.end.x, ch.end.y))
	fill.append(Vector2(ch.position.x, ch.end.y))
	var colors := PackedColorArray()
	var top_col := Color(accent.r, accent.g, accent.b, 0.22)
	for i in range(pts.size()):
		colors.append(top_col)
	colors.append(Color(accent.r, accent.g, accent.b, 0.0))
	colors.append(Color(accent.r, accent.g, accent.b, 0.0))
	draw_polygon(fill, colors)
	draw_polyline(pts, Color(accent.r, accent.g, accent.b, 0.28), 5.0, true)
	draw_polyline(pts, accent, 2.0, true)
	if pts.size() > 0:
		var last := pts[pts.size() - 1]
		draw_circle(last, 9.0, Color(accent.r, accent.g, accent.b, 0.25))
		draw_circle(last, 4.0, accent)
		var peak_pt := pts[0]
		for p in pts:
			if p.y < peak_pt.y:
				peak_pt = p
		var label := "+%.2f m" % maxf(water_peak, 0.01)
		var label_pos := peak_pt + Vector2(-26.0, -14.0)
		label_pos.y = maxf(label_pos.y, ch.position.y + 14.0)
		draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 11, Color(0.9, 1.0, 1.0))
		_chip(font, "ground_contact",
				"IN CONTACT" if was_in_contact else _countdown(contact_countdown), 11, Color(0.3, 1.0, 0.65))

func _draw_jpss(font: Font) -> void:
	var w: Dictionary = WIDGETS["JPSS-2"]
	_chip(font, "obs_window", "Observation Window: %s" % _utc_string(), 11, Color(0.85, 0.95, 1.0))
	var stored_gb: float = float(sim_state.get("data_stored_mb", 0.0)) / 1024.0
	_chip(font, "data_volume", "Data Volume: %.2f GB live" % stored_gb, 11, Color(0.85, 0.95, 1.0))
	_chip(font, "ground_pass",
			"CONTACT NOW" if was_in_contact else _countdown(contact_countdown), 11,
			Color(0.3, 1.0, 0.65) if was_in_contact else Color(0.88, 0.96, 1.0))
	# Atmospheric profile — animated CrIS/ATMS temperature sounding curve.
	var ch := _rf(w["profile_chart"])
	_panel_bg(ch)
	var pts := PackedVector2Array()
	var steps := 40
	for i in range(steps + 1):
		var u := float(i) / steps
		var t := -56.2 + 74.6 * smoothstep(0.30, 0.72, u)
		t += sin(tick_time * 1.3 + u * 5.0) * 1.2
		var vx := ch.position.x + ch.size.x * clampf((t + 80.0) / 100.0, 0.0, 1.0)
		var vy := ch.position.y + ch.size.y * u
		pts.append(Vector2(vx, vy))
	# VFX: halo pass under the sounding curve plus a probe dot riding it.
	draw_polyline(pts, Color(accent.r, accent.g, accent.b, 0.25), 5.0, true)
	draw_polyline(pts, accent, 2.0, true)
	var probe_u := fmod(tick_time * 0.10, 1.0)
	var probe_i := int(probe_u * float(pts.size() - 1))
	if probe_i >= 0 and probe_i < pts.size():
		var probe := pts[probe_i]
		draw_circle(probe, 8.0, Color(accent.r, accent.g, accent.b, 0.25))
		draw_circle(probe, 3.5, Color(1.0, 1.0, 1.0, 0.9))
	# Idle heartbeat around the two orange mission-mode commands.
	for key in ["pulse_a", "pulse_b"]:
		var r := _rf(w[key])
		draw_rect(r.grow(2.0), Color(1.0, 0.62, 0.15, 0.18 + 0.14 * sin(tick_time * 2.2)), false, 2.0)

func _draw_tempo(font: Font) -> void:
	var w: Dictionary = WIDGETS["TEMPO"]
	_chip(font, "utc_chip", "%s  •  LIVE SCAN" % _utc_string(), 11, Color(0.85, 0.8, 1.0))
	var map_box := Rect2(0.260 * size.x, 0.562 * size.y, 0.458 * size.x, 0.036 * size.y)
	draw_rect(map_box, Color(0.008, 0.020, 0.058, 0.94))
	draw_rect(map_box, Color(0.52, 0.38, 0.95, 0.55), false, 1.0)
	var feed_label := "NASA EONET %s  •  %d INCIDENTS  •  TEMPO NO2 %s  •  O3 SIM  •  BACKDROP STATIC" % [
		incident_feed_status.to_upper(), tempo_incidents.size(), tempo_no2_status.to_upper()]
	if incident_feed_status == "offline":
		feed_label = "NASA EONET OFFLINE  •  TEMPO NO2 %s  •  O3 SIM  •  BACKDROP STATIC" % tempo_no2_status.to_upper()
	if not tempo_used_fallback_city.is_empty():
		feed_label += "  •  FALLBACK %s" % tempo_used_fallback_city.to_upper()
	draw_string(font, Vector2(map_box.position.x + 6.0, map_box.position.y + 11.0),
		feed_label, HORIZONTAL_ALIGNMENT_LEFT, map_box.size.x - 12.0, 8, Color(0.65, 0.9, 1.0))
	var incident_label := "Loading active NASA EONET incidents..."
	if incident_feed_status == "live":
		incident_label = "No active North American incidents in NASA EONET."
	elif incident_feed_status == "cached":
		incident_label = "No cached North American incidents."
	elif incident_feed_status == "offline":
		incident_label = "NASA EONET incident feed is offline."
	if not tempo_incidents.is_empty():
		var current: Dictionary = tempo_incidents[incident_index % tempo_incidents.size()]
		var short_title := String(current.get("title", "Environmental event"))
		if short_title.length() > 62:
			short_title = short_title.substr(0, 59) + "..."
		var event_date := String(current.get("date", "")).split("T")[0]
		incident_label = "%s  |  %s  |  %.1f°, %.1f°" % [
			short_title, event_date, float(current.get("lat", 0.0)), float(current.get("lon", 0.0))]
		if not tempo_no2_history.is_empty():
			var latest: Dictionary = tempo_no2_history[-1]
			var scan_clock := Time.get_datetime_dict_from_unix_time(int(float(latest.get("time", 0)) / 1000.0))
			incident_label += "  |  NO2 %.1f ×10¹⁵ @ %02d:%02dZ" % [
				float(latest.get("value", 0.0)), int(scan_clock["hour"]), int(scan_clock["minute"])]
	draw_string(font, Vector2(map_box.position.x + 6.0, map_box.position.y + 25.0),
		incident_label, HORIZONTAL_ALIGNMENT_LEFT, map_box.size.x - 12.0, 9, Color(1.0, 0.9, 0.78))
	# Current scan progress bar (UV-visible spectrometer).
	var bar := _rf(w["progress_bar"])
	_panel_bg(bar)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * scan_progress, bar.size.y)), accent)
	_chip(font, "progress_pct", "%d%%" % int(round(scan_progress * 100.0)), 11, Color(0.9, 0.85, 1.0))
	var no2_text := "NO DATA"
	var no2_delta_text := "--"
	if not tempo_no2_history.is_empty():
		var first_no2 := float(tempo_no2_history[0].get("value", 0.0))
		var latest_no2 := float(tempo_no2_history[-1].get("value", 0.0))
		no2_text = "%.1f ×10¹⁵" % latest_no2
		if tempo_no2_history.size() > 1 and first_no2 > 0.0:
			var no2_delta := int(round((latest_no2 / first_no2 - 1.0) * 100.0))
			no2_delta_text = ("+%d%%" % no2_delta) if no2_delta >= 0 else ("%d%%" % no2_delta)
	_chip(font, "insight_no2", no2_text, 11, Color(0.95, 0.9, 1.0))
	_chip(font, "insight_o3", "%.0f DU" % _o3_value, 11, Color(0.95, 0.9, 1.0))
	var o3_delta := int(round((_o3_value / 410.0 - 1.0) * 100.0))
	var up := Color(1.0, 0.45, 0.3)
	_chip(font, "insight_no2_delta", no2_delta_text, 11, up)
	_chip(font, "insight_o3_delta", ("+%d%%" % o3_delta) if o3_delta >= 0 else ("%d%%" % o3_delta), 11, up)
	# Plot the latest available TEMPO NRT values for the selected incident.
	var ch := _rf(w["hourly_chart"])
	_panel_bg(ch)
	draw_rect(Rect2(ch.position + Vector2(4.0, 3.0), Vector2(242.0, 13.0)), Color(0.008, 0.031, 0.075, 0.9))
	draw_string(font, ch.position + Vector2(7.0, 13.0),
		"NO2 NRT  |  LAST SCANS UTC  |  %s" % tempo_no2_status.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, 238.0, 8, Color(0.55, 1.0, 0.72))
	for i in range(5):
		var gy := ch.position.y + ch.size.y * i / 4.0
		draw_line(Vector2(ch.position.x, gy), Vector2(ch.end.x, gy), Color(accent.r, accent.g, accent.b, 0.12), 1.0)
	if tempo_no2_history.is_empty():
		var no_data_text := "NO VALID TEMPO PIXELS FOR THIS INCIDENT"
		if tempo_no2_status == "loading":
			no_data_text = "FETCHING LIVE TEMPO NRT DATA..."
		elif tempo_no2_status == "offline":
			no_data_text = "TEMPO NRT SERVICE UNAVAILABLE"
		draw_string(font, ch.position + Vector2(12.0, ch.size.y * 0.60),
			no_data_text, HORIZONTAL_ALIGNMENT_LEFT, ch.size.x - 24.0, 9, Color(1.0, 0.78, 0.42))
	else:
		var chart_max := 2.0
		for sample in tempo_no2_history:
			chart_max = maxf(chart_max, float(sample.get("value", 0.0)))
		chart_max = maxf(12.0, ceilf(chart_max * 1.15))
		var pts := PackedVector2Array()
		var first_time := int(tempo_no2_history[0].get("time", 0))
		var last_time := int(tempo_no2_history[-1].get("time", first_time))
		var time_span := maxi(1, last_time - first_time)
		var peak_index := 0
		for i in range(tempo_no2_history.size()):
			var sample: Dictionary = tempo_no2_history[i]
			var value := float(sample.get("value", 0.0))
			var time_fraction := float(int(sample.get("time", first_time)) - first_time) / float(time_span)
			if tempo_no2_history.size() == 1:
				time_fraction = 1.0
			var vx := ch.position.x + ch.size.x * time_fraction
			var vy := ch.end.y - 7.0 - (ch.size.y - 25.0) * clampf(value / chart_max, 0.0, 1.0)
			pts.append(Vector2(vx, vy))
			if value > float(tempo_no2_history[peak_index].get("value", 0.0)):
				peak_index = i
		var line := Color(0.38, 1.0, 0.65)
		if pts.size() >= 2:
			draw_polyline(pts, Color(line.r, line.g, line.b, 0.25), 5.0, true)
			draw_polyline(pts, line, 2.0, true)
		for point in pts:
			draw_circle(point, 2.5, line)
		var latest_point := pts[-1]
		draw_circle(latest_point, 8.0, Color(line.r, line.g, line.b, 0.22))
		draw_circle(latest_point, 4.0, line)
		var peak_pos := pts[peak_index] + Vector2(-20.0, -10.0)
		peak_pos.y = maxf(peak_pos.y, ch.position.y + 26.0)
		draw_rect(Rect2(peak_pos - Vector2(4.0, 11.0), Vector2(46.0, 18.0)), Color(0.08, 0.02, 0.12, 0.95))
		draw_string(font, peak_pos, "%.1f" % float(tempo_no2_history[peak_index].get("value", 0.0)),
			HORIZONTAL_ALIGNMENT_CENTER, 42.0, 10, Color(0.9, 1.0, 0.92))
	# Idle heartbeat on the SCAN POLLUTION command.
	var r := _rf(w["pulse_a"])
	draw_rect(r.grow(2.0), Color(1.0, 0.55, 0.2, 0.18 + 0.14 * sin(tick_time * 2.2)), false, 2.0)

	# ── Hour-compare overlay: pick the earliest and latest scans and show delta.
	if tempo_hour_compare_on and tempo_no2_history.size() >= 2:
		_draw_hour_compare(font, ch)
	# ── NO₂ vertical column density panel.
	if tempo_no2_column_panel_on:
		_draw_no2_column_panel(font)
	# ── Ozone (O₃) monitoring panel.
	if tempo_ozone_monitoring_on:
		_draw_ozone_panel(font)
	# ── Toast feedback.
	if not tempo_toast.is_empty():
		_draw_toast(font)

## Highlights the earliest and latest NO₂ scans on the hourly chart and
## renders a delta readout so the operator can compare hours at a glance.
func _draw_hour_compare(font: Font, ch: Rect2) -> void:
	var first: Dictionary = tempo_no2_history[0]
	var last: Dictionary = tempo_no2_history[-1]
	var first_val := float(first.get("value", 0.0))
	var last_val := float(last.get("value", 0.0))
	var first_time := int(first.get("time", 0))
	var last_time := int(last.get("time", first_time))
	var first_dt := Time.get_datetime_dict_from_unix_time(int(first_time / 1000))
	var last_dt := Time.get_datetime_dict_from_unix_time(int(last_time / 1000))
	var delta_pct := 0.0
	if first_val > 0.0:
		delta_pct = (last_val / first_val - 1.0) * 100.0
	var banner := Rect2(ch.position.x, ch.position.y - 22.0, ch.size.x, 18.0)
	draw_rect(banner, Color(0.10, 0.02, 0.18, 0.96))
	draw_rect(banner, Color(0.65, 0.42, 1.0, 0.7), false, 1.0)
	var delta_col := Color(0.45, 1.0, 0.55) if delta_pct >= 0.0 else Color(1.0, 0.55, 0.45)
	var cmp_text := "COMPARE %02d:%02dZ (%.1f) → %02d:%02dZ (%.1f)   Δ %s%.0f%%" % [
		int(first_dt["hour"]), int(first_dt["minute"]), first_val,
		int(last_dt["hour"]), int(last_dt["minute"]), last_val,
		("+" if delta_pct >= 0.0 else ""), delta_pct]
	draw_string(font, Vector2(banner.position.x + 8.0, banner.position.y + 12.0),
		cmp_text, HORIZONTAL_ALIGNMENT_LEFT, banner.size.x - 16.0, 9, delta_col)
	# Markers on the chart endpoints.
	var chart_max := 12.0
	for sample in tempo_no2_history:
		chart_max = maxf(chart_max, float(sample.get("value", 0.0)))
	chart_max = maxf(12.0, ceilf(chart_max * 1.15))
	var span := maxi(1, last_time - first_time)
	for pair in [[first, Color(0.45, 0.75, 1.0)], [last, Color(1.0, 0.65, 0.35)]]:
		var s: Dictionary = pair[0]
		var col: Color = pair[1]
		var fx := float(int(s.get("time", first_time)) - first_time) / float(span)
		if tempo_no2_history.size() == 1:
			fx = 1.0
		var mx := ch.position.x + ch.size.x * fx
		var my := ch.end.y - 7.0 - (ch.size.y - 25.0) * clampf(float(s.get("value", 0.0)) / chart_max, 0.0, 1.0)
		draw_circle(Vector2(mx, my), 7.0, Color(col.r, col.g, col.b, 0.35))
		draw_circle(Vector2(mx, my), 3.5, col)

## Renders a dedicated NO₂ vertical column density readout panel over the
## existing hourly chart when the NO₂ COLUMN button is active.
func _draw_no2_column_panel(font: Font) -> void:
	var panel := Rect2(0.283 * size.x, 0.600 * size.y, 0.332 * size.x, 0.177 * size.y)
	draw_rect(panel, Color(0.01, 0.012, 0.04, 0.97))
	draw_rect(panel, Color(0.38, 1.0, 0.65, 0.6), false, 1.5)
	draw_string(font, panel.position + Vector2(10.0, 16.0),
		"NO₂ TROPOSPHERIC VERTICAL COLUMN DENSITY", HORIZONTAL_ALIGNMENT_LEFT,
		panel.size.x - 20.0, 10, Color(0.55, 1.0, 0.72))
	if tempo_no2_history.is_empty():
		draw_string(font, panel.position + Vector2(10.0, panel.size.y * 0.55),
			"NO COLUMN DATA — PRESS SCAN POLLUTION", HORIZONTAL_ALIGNMENT_LEFT,
			panel.size.x - 20.0, 11, Color(1.0, 0.78, 0.42))
		return
	var latest: Dictionary = tempo_no2_history[-1]
	var col_val := float(latest.get("value", 0.0))
	var col_units := "×10¹⁵ molecules/cm²"
	draw_string(font, panel.position + Vector2(12.0, panel.size.y * 0.50),
		"%.2f" % col_val, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 24.0, 34,
		Color(0.8, 1.0, 0.88))
	draw_string(font, panel.position + Vector2(12.0, panel.size.y * 0.74),
		col_units, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 24.0, 9, Color(0.6, 0.85, 0.7))
	# A simple vertical density gradient bar.
	var bar := Rect2(panel.end.x - 22.0, panel.position.y + 30.0, 10.0, panel.size.y - 50.0)
	var grad_color := Color(0.18, 0.9, 0.55)
	if col_val > 8.0:
		grad_color = Color(1.0, 0.45, 0.3)
	elif col_val > 4.0:
		grad_color = Color(1.0, 0.75, 0.3)
	for i in range(int(bar.size.y)):
		var a := 1.0 - float(i) / bar.size.y
		draw_line(Vector2(bar.position.x, bar.position.y + i),
			Vector2(bar.end.x, bar.position.y + i),
			Color(grad_color.r, grad_color.g, grad_color.b, a * 0.85), 1.0)
	var level := "LOW"
	if col_val > 8.0:
		level = "HIGH"
	elif col_val > 4.0:
		level = "MODERATE"
	draw_string(font, Vector2(bar.position.x - 6.0, bar.position.y - 6.0),
		level, HORIZONTAL_ALIGNMENT_RIGHT, 60.0, 9, grad_color)

## Renders an ozone (O₃) monitoring panel when the OZONE MONITORING button is
## active. O₃ is still illustrative, so the panel is clearly labelled SIM.
func _draw_ozone_panel(font: Font) -> void:
	var panel := Rect2(0.620 * size.x, 0.600 * size.y, 0.250 * size.x, 0.177 * size.y)
	draw_rect(panel, Color(0.01, 0.012, 0.04, 0.97))
	draw_rect(panel, Color(0.55, 0.7, 1.0, 0.6), false, 1.5)
	draw_string(font, panel.position + Vector2(10.0, 16.0),
		"OZONE (O₃) MONITORING  •  SIM", HORIZONTAL_ALIGNMENT_LEFT,
		panel.size.x - 20.0, 10, Color(0.65, 0.8, 1.0))
	draw_string(font, panel.position + Vector2(12.0, panel.size.y * 0.52),
		"%.0f" % _o3_value, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 24.0, 34,
		Color(0.8, 0.9, 1.0))
	draw_string(font, panel.position + Vector2(12.0, panel.size.y * 0.76),
		"Dobson Units (DU)", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 24.0, 9,
		Color(0.55, 0.7, 0.95))
	# Mini ozone trend sparkline.
	var spark := Rect2(panel.position.x + 12.0, panel.end.y - 26.0, panel.size.x - 24.0, 16.0)
	var sp := PackedVector2Array()
	var steps := 32
	for i in range(steps + 1):
		var u := float(i) / steps
		var v := 0.5 + 0.5 * sin(tick_time * 0.5 + u * 8.0) + 0.15 * sin(tick_time * 1.3 + u * 17.0)
		sp.append(Vector2(spark.position.x + spark.size.x * u,
			spark.end.y - spark.size.y * clampf(v, 0.0, 1.0)))
	if sp.size() >= 2:
		draw_polyline(sp, Color(0.55, 0.7, 1.0, 0.3), 3.0, true)
		draw_polyline(sp, Color(0.65, 0.8, 1.0, 0.9), 1.5, true)
	var du_delta := int(round((_o3_value / 410.0 - 1.0) * 100.0))
	var dcol := Color(0.45, 1.0, 0.55) if du_delta >= 0 else Color(1.0, 0.55, 0.45)
	draw_string(font, Vector2(panel.end.x - 12.0, panel.position.y + 16.0),
		("%+.0f%%" % du_delta), HORIZONTAL_ALIGNMENT_RIGHT, 80.0, 11, dcol)

## Short-lived operator feedback toast drawn above the bottom command row.
func _draw_toast(font: Font) -> void:
	var msg_size := font.get_string_size(tempo_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var box_w := msg_size.x + 24.0
	var box_h := 24.0
	var box := Rect2((size.x - box_w) * 0.5, 0.855 * size.y, box_w, box_h)
	var alpha := clampf(tempo_toast_timer / 1.0, 0.0, 1.0)
	draw_rect(box, Color(0.06, 0.02, 0.12, 0.92 * alpha))
	draw_rect(box, Color(0.95, 0.75, 0.35, alpha), false, 1.5)
	draw_string(font, Vector2(box.position.x + 12.0, box.position.y + 16.0),
		tempo_toast, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24.0, 11,
		Color(1.0, 0.92, 0.65, alpha))

## Bottom broadcast bar: real NASA SWOT headlines when online, mission facts
## offline — scrolling continuously like a control-room news ticker.
func _draw_ticker(font: Font) -> void:
	var strip_h := 0.024 * size.y
	var strip := Rect2(Vector2(0.0, size.y - strip_h), Vector2(size.x, strip_h))
	draw_rect(strip, Color(0.0, 0.0, 0.0, 0.88))
	var tag := "● NASA MISSION FACTS"
	match feed_source:
		"page":
			tag = "● SCIENCE.NASA.GOV LIVE"
		"api":
			tag = "● LIVE NASA FEED"
	var ticker_lines := feed_lines
	if mission == "TEMPO":
		ticker_lines = PackedStringArray()
		match incident_feed_status:
			"live":
				tag = "● NASA EONET LIVE"
			"cached":
				tag = "● NASA EONET CACHED"
			"offline":
				tag = "● NASA EONET OFFLINE"
			_:
				tag = "● NASA EONET LOADING"
		for i in range(mini(tempo_incidents.size(), 20)):
			var event: Dictionary = tempo_incidents[i]
			ticker_lines.append("%s (%s, %.1f, %.1f)" % [
				String(event.get("title", "Environmental event")),
				String(event.get("date", "")).split("T")[0],
				float(event.get("lat", 0.0)), float(event.get("lon", 0.0))])
		if ticker_lines.is_empty():
			var empty_message := "Loading active NASA EONET events"
			if incident_feed_status == "live":
				empty_message = "No active NASA EONET events in the TEMPO viewing region"
			elif incident_feed_status == "cached":
				empty_message = "No cached NASA EONET events in the TEMPO viewing region"
			elif incident_feed_status == "offline":
				empty_message = "NASA EONET incident feed is offline"
			ticker_lines.append(empty_message)
	var tag_w := 150.0
	draw_string(font, Vector2(12.0, strip.position.y + strip_h * 0.5 + 4.0), tag,
			HORIZONTAL_ALIGNMENT_LEFT, tag_w, 11, Color(0.3, 1.0, 0.6, _blink(2.5)))
	if ticker_lines.is_empty():
		return
	var msg := "  ▸  ".join(ticker_lines)
	var msg_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var span := msg_size.x + size.x
	var x := fmod(size.x - tick_time * 70.0, span + 200.0)
	var y := strip.position.y + strip_h * 0.5 + 4.0
	draw_string(font, Vector2(x, y), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.82, 0.92, 1.0))
	draw_string(font, Vector2(x + span + 100.0, y), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.82, 0.92, 1.0))
