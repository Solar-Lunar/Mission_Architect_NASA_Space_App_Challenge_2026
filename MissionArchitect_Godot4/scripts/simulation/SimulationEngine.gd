## SimulationEngine.gd
## Autoload singleton — runs deterministic orbital mission simulation
## Physics: orbital mechanics, power model, data downlink, science collection

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal state_updated(state: Dictionary)
signal event_occurred(event: Dictionary)
signal mission_ended(result: Dictionary)

# ─── Constants ────────────────────────────────────────────────────────────────
const MU_EARTH: float    = 3.986e5   # km³/s²  (Earth gravitational parameter)
const RE_EARTH: float    = 6371.0    # km
const MU_MOON: float     = 4.905e3
const RE_MOON: float     = 1737.0
const PI2: float         = 2.0 * PI
const SECONDS_PER_DAY: float = 86400.0
const J2_EARTH: float    = 1.08263e-3   # Earth's dominant oblateness harmonic

# Time multipliers for simulation speed
const TIME_SCALES: Array = [1.0, 10.0, 60.0, 600.0, 3600.0]
var time_scale_idx: int = 1

# ─── Simulation State ─────────────────────────────────────────────────────────
var running: bool = false
var paused: bool = false
var state: Dictionary = {}
var time_scale: float = 10.0
var elapsed_sim_seconds: float = 0.0
var random_seed: int = 12345

var _rng: RandomNumberGenerator

# ─── Orbital Parameters ───────────────────────────────────────────────────────
var orbit_period_seconds: float = 0.0
var orbit_angle: float = 0.0        # radians, 0..2π
var eclipse_fraction: float = 0.35  # fraction of orbit in shadow
var orbit_inclination_rad: float = deg_to_rad(51.6)

# ─── Ground Station Positions (lat/lon in degrees) ────────────────────────────
const GROUND_STATIONS: Array = [
	{"name": "Goldstone", "lat": 35.4, "lon": -116.9},
	{"name": "Madrid DSN", "lat": 40.4, "lon": -4.2},
	{"name": "Canberra DSN", "lat": -35.4, "lon": 149.0},
	{"name": "Svalbard", "lat": 78.2, "lon": 15.4}
]

# ─── Real NASA-tracked climate survey targets (Earth Climate Sentinel only) ────
# Every entry below is a genuine event or record that NASA's Earth-observation
# program monitors, with the location of the event and the real sensor that
# observed it.  The game's instrument boxes are stand-ins for those sensors, so
# science is only earned over a target when the player flew the instrument that
# actually made the discovery — the data is the mission, not decoration.
const CLIMATE_FOOTPRINT_DEG: float = 15.0   # angular radius sensed at 550 km
const CLIMATE_TARGETS: Array = [
	{"name": "Northeast U.S. NO₂ Urban Corridor", "lat": 40.7, "lon": -74.0,
		"mission_mode": "TEMPO",
		"requires_instrument": "spectrometer", "needs_sunlight": true,
		"science": 14, "data_mb": 190,
		"sensor": "TEMPO UV-visible spectrometer NO₂ column", "source": "NASA TEMPO",
		"note": "NASA's TEMPO instrument provides hourly daytime observations of air pollution over North America; this simulation tasks an urban NO₂ observation over the Northeast corridor.", "date": "2024-07-15", "stat": "Hourly daytime NO₂ column product | UV-visible spectroscopy", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2024-07-15T16:00:00Z&BBOX=-78,38,-71,43&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Canadian Wildfire Megaseason 2023", "lat": 57.0, "lon": -106.0,
		"mission_mode": "JPSS-2",
		"requires_instrument": "thermal", "needs_sunlight": false,
		"science": 14, "data_mb": 220,
		"sensor": "MODIS/VIIRS thermal anomalies", "source": "NASA FIRMS (fire info)",
		"note": "2023 was Canada's worst wildfire season on record; ~650 kt of smoke was tracked from orbit and mapped plumes across North America and the Atlantic.", "date": "2023-07-08", "stat": "4.9 M ha burned | ~650 kt smoke emitted (CCAC)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor,VIIRS_SNPP_Thermal_Anomalies_all&Time=2023-07-08T18:00:00Z&BBOX=-114,52,-98,62&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Lahaina Urban Fire Damage, Maui 2023", "lat": 20.97, "lon": -156.68,
		"mission_mode": "JPSS-2",
		"requires_instrument": "camera_hires", "needs_sunlight": true,
		"science": 12, "data_mb": 480,
		"sensor": "Landsat 8/9 OLI burned-area imaging", "source": "NASA Earthdata / USGS Landsat",
		"note": "Landsat's 30 m imagery mapped the burn scar of the August 2023 disaster and became evidence in the recovery effort.", "date": "2023-08-09", "stat": "~2,200 structures lost | 21.7 km2 burn scar (Landsat 8 OLI)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor,VIIRS_SNPP_Thermal_Anomalies_all&Time=2023-08-09T19:40:00Z&BBOX=-157.3,20.3,-156.0,21.3&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Mediterranean Marine Heatwave 2022", "lat": 37.4, "lon": 15.0,
		"mission_mode": "SWOT",
		"requires_instrument": "thermal", "needs_sunlight": false,
		"science": 12, "data_mb": 180,
		"sensor": "MODIS sea-surface temperature (Aqua)", "source": "NASA Ocean Biology (OB.DAAC)",
		"note": "Summer 2022 SSTs in the Mediterranean exceeded +6 C climatology - one of the strongest marine heatwaves recorded anywhere by satellite.", "date": "2022-07-24", "stat": "SST anomaly up to +6.0 C | Class III MHW (OB.DAAC SST)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2022-07-24T11:30:00Z&BBOX=10.5,34.0,21.0,40.5&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Amazon River Flood Pulse (Rio Madeira)", "lat": -8.8, "lon": -63.9,
		"mission_mode": "SWOT",
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 15, "data_mb": 520,
		"sensor": "SWOT KaRIn radar altimetry", "source": "NASA/CNES SWOT",
		"note": "SWOT measures the height of every river and lake on Earth every 21 days - the 2025 record flood pulse on the Madeira was captured in its swaths.", "date": "2014-03-17", "stat": "River stage >19 m | ~250 km floodplain inundated (SWOT)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2014-03-17T15:30:00Z&BBOX=-67.0,-12.0,-60.0,-5.0&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Sundhnúkur Eruption SO₂ Plume, Iceland", "lat": 63.9, "lon": -22.4,
		"mission_mode": "JPSS-2",
		"requires_instrument": "spectrometer", "needs_sunlight": true,
		"science": 13, "data_mb": 160,
		"sensor": "TEMPO tropospheric SO₂ columns", "source": "NASA TEMPO",
		"note": "TEMPO, the first pollution instrument in geostationary orbit over the US, watched the 2024 Sundhnúkur fissure eruptions flood the atmosphere near Grindavík with SO₂.", "date": "2024-01-14", "stat": "Fissure eruption ~4 km from Grindavík | SO₂ plume tracked hourly", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor,VIIRS_SNPP_Thermal_Anomalies_all&Time=2024-01-14T13:00:00Z&BBOX=-24.0,63.0,-21.0,64.6&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Greenland Ice Sheet Mass Loss (SER4) ", "lat": 68.0, "lon": -50.0,
		"mission_mode": "SWOT",
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 12, "data_mb": 300,
		"sensor": "ICESat-2 ATLAS laser altimeter", "source": "NASA ICESat-2",
		"note": "ICESat-2's photon-counting laser has weighed the Greenland ice sheet since 2018, showing losses near 270 Gt per year that raise global sea level.", "date": "2024-06-23", "stat": "~270 Gt/yr mass loss | meltwater plumes at Ilulissat (ICESat-2)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2024-06-23T15:00:00Z&BBOX=-53.5,66.5,-46.0,70.0&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
]

# ─── Orbital Geometry ─────────────────────────────────────────────────────────
# One place decides where the satellite is, where every station is, and whether
# the two can see each other.  The scene draws from these functions and the
# numbers are computed from them, so a downlink you can see on screen and a
# downlink in the telemetry are the same event rather than two guesses that
# happen to agree.
const EARTH_ROTATION_RATE: float = PI2 / 86164.0   # rad/s — sidereal, not solar
const MIN_ELEVATION_DEG: float = 10.0              # no dish works at the horizon
var earth_rotation_rad: float = 0.0

# A sun-synchronous climate orbit is not inertial: Earth's oblateness (the J2
# harmonic) drags the orbital plane eastward about the spin axis, and at exactly
# +0.9856°/day the local sun-time of every pass stays fixed — that is the whole
# reason NASA flies 97-98° inclinations for Earth observation.  The climate
# sentinel precesses with the real rate; other missions keep a fixed plane.
var node_precession_rad: float = 0.0
var node_precession_rate: float = 0.0   # rad/s, eastward positive

## Unit direction from the body centre to the satellite.  The globe's spin axis
## is +Y and the orbit plane is tilted about +X, so the sub-point latitude runs
## between +/- the inclination and the ground track drifts west as the planet
## turns under a plane that does not.
func sub_point_direction(angle: float = -1.0) -> Vector3:
	var a: float = orbit_angle if angle < 0.0 else angle
	return Vector3(cos(a), sin(orbit_inclination_rad) * sin(a), cos(orbit_inclination_rad) * sin(a)) \
		.rotated(Vector3.UP, node_precession_rad)

## Unit direction of a point on the surface in the globe's own frame.  The two
## constants below are the only thing between a station and the continent it is
## supposed to be on: the sphere's UV seam does not sit where intuition puts it,
## so the mapping is calibrated against the texture rather than guessed at.
const STATION_LON_OFFSET_DEG: float = 180.0
const STATION_X_FLIP: float = 1.0
func station_local_direction(lat_deg: float, lon_deg: float) -> Vector3:
	var la: float = deg_to_rad(lat_deg)
	var lo: float = deg_to_rad(lon_deg + STATION_LON_OFFSET_DEG)
	return Vector3(STATION_X_FLIP * cos(la) * cos(lo), sin(la), cos(la) * sin(lo))

## The same point after the planet has turned under the orbit.
func station_world_direction(station: Dictionary) -> Vector3:
	return station_local_direction(float(station["lat"]), float(station["lon"])) \
		.rotated(Vector3.UP, earth_rotation_rad)

## Elevation of the satellite above the horizon at one station, in degrees, from
## the triangle centre-station-satellite.  This is the real formula, not a
## window: a pass begins when the number crosses 10° and ends when it falls back
## through it, which is why an equatorial station can never see a polar one.
func station_elevation_deg(station: Dictionary, altitude_km: float) -> float:
	var body_r: float = _body_radius_km()
	var sat_r: float = body_r + maxf(altitude_km, 1.0)
	var gamma: float = station_world_direction(station).angle_to(sub_point_direction())
	# The triangle centre–station–satellite: with the central angle γ between the
	# station and the sub-point, the elevation at the station is
	#     tan e = (r·cos γ − R) / (r·sin γ)
	# which is 90° overhead, 0° at the geometric horizon and negative when the
	# vehicle is below it.  No windows, no tables — this is the pass.
	return rad_to_deg(atan2(sat_r * cos(gamma) - body_r, sat_r * sin(gamma)))

func _body_radius_km() -> float:
	var target: String = String(GameManager.current_mission.get("target", ""))
	if "Moon" in target or "Lunar" in target:
		return RE_MOON
	if "Mars" in target:
		return 3389.5
	return RE_EARTH

## The station with the highest satellite elevation right now, and how high.
## Returns an empty dictionary when nothing on the network can see the vehicle.
func best_visible_station(altitude_km: float) -> Dictionary:
	var best: Dictionary = {}
	var best_el: float = MIN_ELEVATION_DEG
	for station in GROUND_STATIONS:
		var el: float = station_elevation_deg(station, altitude_km)
		if el > best_el:
			best_el = el
			best = station
	if best.is_empty():
		return {}
	return {
		"name": String(best["name"]),
		"lat": float(best["lat"]),
		"lon": float(best["lon"]),
		"elevation_deg": best_el,
		"direction": station_world_direction(best),
	}

# ─── Random Events Pool ───────────────────────────────────────────────────────
const EVENTS: Array = [
	{
		"id": "solar_flare", "name": "Solar Flare!",
		"desc": "Intense radiation reduces solar panel efficiency by 20% for 2 orbits.",
		"type": "warning", "probability": 0.04,
		"effect": {"power_gen_mult": 0.8, "duration_orbits": 2}
	},
	{
		"id": "micrometeorite", "name": "Micrometeorite Impact",
		"desc": "A tiny rock chips one solar panel. Power generation drops 10%.",
		"type": "danger", "probability": 0.02,
		"effect": {"power_gen_mult": 0.9, "duration_orbits": 9999}
	},
	{
		"id": "software_glitch", "name": "Software Anomaly",
		"desc": "Flight computer glitch. One instrument temporarily offline.",
		"type": "warning", "probability": 0.03,
		"effect": {"science_mult": 0.7, "duration_orbits": 3}
	},
	{
		"id": "comm_blackout", "name": "Communication Blackout",
		"desc": "Spacecraft behind target body. No ground contact for 2 orbits.",
		"type": "info", "probability": 0.05,
		"effect": {"comms_blocked": true, "duration_orbits": 2}
	},
	{
		"id": "discovery", "name": "Unexpected Discovery!",
		"desc": "Instruments detect an anomalous reading — bonus science data!",
		"type": "success", "probability": 0.04,
		"effect": {"bonus_science": 15}
	},
	{
		"id": "battery_surge", "name": "Battery Performance Boost",
		"desc": "Cold space temperatures improve battery efficiency. +10% capacity!",
		"type": "success", "probability": 0.03,
		"effect": {"battery_mult": 1.1}
	},
	{
		"id": "instrument_fail", "name": "Instrument Failure",
		"desc": "One science instrument stops responding. Science output reduced.",
		"type": "danger", "probability": 0.02,
		"effect": {"science_mult": 0.6, "duration_orbits": 9999}
	},
	{
		"id": "gravity_assist", "name": "Navigation Bonus",
		"desc": "Precise navigation saves propellant. Fuel reserve increases.",
		"type": "success", "probability": 0.03,
		"effect": {"bonus_science": 8}
	}
]

# ─── Init ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	print("[SimEngine] Ready")

# ─── Start Simulation ─────────────────────────────────────────────────────────
func start_simulation(seed_val: int = 12345) -> void:
	random_seed = seed_val
	_rng.seed = seed_val
	elapsed_sim_seconds = 0.0
	orbit_angle = 0.0
	earth_rotation_rad = 0.0
	node_precession_rad = 0.0
	node_precession_rate = 0.0
	running = true
	paused = false

	var mission: Dictionary = GameManager.current_mission
	var config: Dictionary = GameManager.spacecraft_config

	# The plane the vehicle is actually flying.  A sun-synchronous climate orbit is
	# near-polar, and that is the only reason a satellite in it can see Svalbard at
	# all — so the inclination has to come from the mission, not from a constant.
	orbit_inclination_rad = deg_to_rad(float(mission.get("inclination_deg", 51.6)))

	# Compute orbital period
	orbit_period_seconds = _compute_orbit_period(mission)

	# Eclipse fraction based on altitude
	var alt: float = mission.get("altitude_km", 550)
	eclipse_fraction = _compute_eclipse_fraction(alt)

	# The climate sentinel flies a real sun-synchronous orbit: the J2 nodal
	# precession is computed from the mission's own altitude and inclination, and
	# only the Earth mission precesses.  Every other mission keeps the fixed
	# inertial plane it always had.
	if String(mission.get("id", "")) == "earth_climate":
		var sma: float = RE_EARTH + alt
		var mean_motion: float = PI2 / orbit_period_seconds
		node_precession_rate = -1.5 * mean_motion * J2_EARTH \
			* pow(RE_EARTH / sma, 2.0) * cos(orbit_inclination_rad)

	# Init state
	state = {
		"day": 0,
		"orbit_number": 0,
		"orbit_angle_deg": 0.0,
		"battery_wh": config.get("battery_capacity", 0.0),
		"battery_max_wh": config.get("battery_capacity", 1.0),
		"data_stored_mb": 0.0,
		"data_transmitted_mb": 0.0,
		"science_points": 0.0,
		"power_gen": config.get("total_power_gen", 0.0),
		"power_draw": config.get("total_power_draw", 0.0),
		"power_balance": 0.0,
		"in_eclipse": false,
		"ground_contact": false,
		"ground_station_name": "",
		"station_elevation_deg": 0.0,
		"pass_mb": 0.0,
		"passes_completed": 0,
		"instruments_active": true,
		"mission_health": 100.0,
		"events_log": [],
		"power_gen_mult": 1.0,
		"science_mult": 1.0,
		"comms_blocked": false,
		"active_effects": [],
		"total_orbits": 0,
		"target_science": mission.get("science_goal", 80),
		"mission_duration_days": mission.get("duration_days", 365),
		"objectives_done": [],
	}
	if GameManager.is_asteroid_mission():
		var propulsion: Dictionary = config.get("propulsion", {})
		var has_spectrometer: bool = false
		for instrument in config.get("instruments", []):
			if instrument.get("id", "") == "spectrometer":
				has_spectrometer = true
				break
		state["rendezvous_complete"] = propulsion.get("delta_v", 0) >= 500
		state["composition_analyzed"] = false
		state["has_composition_instrument"] = has_spectrometer
		state["asteroid_orbit_days"] = 0
		state["objectives_done"] = _asteroid_objectives_done()
	if GameManager.is_earth_climate_mission():
		# Every real target starts unobserved; the survey is the mission.
		var targets: Array = []
		for t in CLIMATE_TARGETS:
			var entry: Dictionary = t.duplicate(true)
			entry["captured"] = false
			entry["captured_day"] = -1
			targets.append(entry)
		state["climate_targets"] = targets
		state["targets_captured"] = 0
		# Scans are commanded from mission control.  Keeping the requested target
		# in simulation state makes the control-room display and the actual sensor
		# model agree about what the spacecraft is trying to observe.
		state["active_scan_target"] = -1
		state["scan_mode"] = "JPSS-2"
		state["scan_status"] = "Select an incident and request a scan"
		state["safe_mode_events"] = 0
		state["nodal_precession_deg_day"] = rad_to_deg(node_precession_rate * SECONDS_PER_DAY)
		state["objectives_done"] = _earth_objectives_done()
	state_updated.emit(state)
	print("[SimEngine] Simulation started. Period: %.1f min" % (orbit_period_seconds / 60.0))

# ─── Per-Frame Update ─────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not running or paused:
		return

	var dt_sim: float = delta * time_scale

	# Advance orbital angle
	orbit_angle += (PI2 / orbit_period_seconds) * dt_sim
	if orbit_angle >= PI2:
		orbit_angle -= PI2
		state["total_orbits"] += 1
		_on_orbit_complete()

	state["orbit_angle_deg"] = rad_to_deg(orbit_angle)
	elapsed_sim_seconds += dt_sim
	# The planet turns under a plane that does not.  This is what makes the ground
	# track walk westward between revolutions, and it is the reason a station a
	# satellite passed ten minutes ago cannot see it now.
	earth_rotation_rad = fmod(earth_rotation_rad + EARTH_ROTATION_RATE * dt_sim, PI2)
	# The sun-synchronous plane creeps east at its computed J2 rate, carrying the
	# ground track — and which climate targets are overflown next — with it.
	node_precession_rad = fmod(node_precession_rad + node_precession_rate * dt_sim, PI2)
	state["day"] = int(elapsed_sim_seconds / SECONDS_PER_DAY)
	if GameManager.is_asteroid_mission():
		state["asteroid_orbit_days"] = min(state["day"], 30)
		if state["has_composition_instrument"] and state["science_points"] > 0.0:
			state["composition_analyzed"] = true
		state["objectives_done"] = _asteroid_objectives_done()
	if GameManager.is_earth_climate_mission():
		state["objectives_done"] = _earth_objectives_done()

	# Eclipse check
	var was_eclipse: bool = state["in_eclipse"]
	state["in_eclipse"] = _is_in_eclipse(orbit_angle)

	# Power simulation
	_simulate_power(dt_sim)

	# Data accumulation
	_simulate_data(dt_sim)

	# Ground contact
	_simulate_comms(dt_sim)

	# Real climate-event survey (Earth Climate Sentinel only)
	if GameManager.is_earth_climate_mission():
		_simulate_climate_observation()

	# Check mission end
	if state["day"] >= state["mission_duration_days"]:
		_end_mission()
		return

	state_updated.emit(state)

func _on_orbit_complete() -> void:
	state["orbit_number"] += 1

	# Decay effects
	var new_effects: Array = []
	for eff in state["active_effects"]:
		eff["remaining_orbits"] -= 1
		if eff["remaining_orbits"] > 0:
			new_effects.append(eff)
		else:
			_remove_effect(eff)
	state["active_effects"] = new_effects

	# Random event check
	if _rng.randf() < 0.08:  # 8% chance per orbit
		_trigger_random_event()

# ─── Power Simulation ─────────────────────────────────────────────────────────
func _simulate_power(dt_sim: float) -> void:
	var config: Dictionary = GameManager.spacecraft_config
	var gen: float = config.get("total_power_gen", 0.0) * state["power_gen_mult"]

	if state["in_eclipse"]:
		gen = 0.0  # No solar power in eclipse

	var draw: float = config.get("total_power_draw", 0.0)
	if not state["instruments_active"]:
		draw -= _instrument_power_draw()

	var balance: float = gen - draw
	state["power_gen"] = gen
	state["power_draw"] = draw
	state["power_balance"] = balance

	# Update battery
	var batt: float = state["battery_wh"]
	var batt_max: float = state["battery_max_wh"]
	if batt_max > 0:
		batt += balance * (dt_sim / 3600.0)  # Wh = W * hours
		batt = clamp(batt, 0.0, batt_max)
		state["battery_wh"] = batt

		# Auto safe mode if battery critically low
		if batt <= 0 and balance < 0:
			if state["instruments_active"]:
				state["instruments_active"] = false
				state["safe_mode_events"] = int(state.get("safe_mode_events", 0)) + 1
				_log_event("⚠️ Battery depleted! Entering safe mode — instruments offline.", "danger")

		# Auto restore when battery recovers
		if batt > batt_max * 0.3 and not state["instruments_active"] and gen > draw * 0.5:
			state["instruments_active"] = true
			_log_event("✅ Battery recovered — instruments back online.", "success")
	else:
		# No battery — direct solar dependency
		if balance < 0:
			state["instruments_active"] = false
		else:
			state["instruments_active"] = true

func _instrument_power_draw() -> float:
	var total: float = 0.0
	for inst in GameManager.spacecraft_config.get("instruments", []):
		total += inst.get("power_draw", 0)
	return total

# ─── Data Simulation ──────────────────────────────────────────────────────────
func _simulate_data(dt_sim: float) -> void:
	if not state["instruments_active"]:
		return
	var config: Dictionary = GameManager.spacecraft_config
	var bus: Dictionary = config.get("bus", {})
	var storage_mb: float = bus.get("data_storage", 200) * 1000  # MB
	var data_rate_mbps: float = config.get("total_data_rate", 0.0) * state["science_mult"]

	state["data_stored_mb"] += data_rate_mbps * dt_sim
	state["data_stored_mb"] = min(state["data_stored_mb"], storage_mb)

	# Science per orbit (accumulated per second)
	var sci_per_orbit: float = config.get("total_science_per_orbit", 0.0) * state["science_mult"]
	state["science_points"] += (sci_per_orbit / orbit_period_seconds) * dt_sim

# ─── Communications ───────────────────────────────────────────────────────────
func _simulate_comms(dt_sim: float) -> void:
	if state.get("comms_blocked", false):
		state["ground_contact"] = false
		state["ground_station_name"] = ""
		return

	# A Mars or asteroid mission is not limited by geometry in this build: the
	# antenna points home and which DSN complex answers is a scheduling question,
	# so those keep the simplified contact windows.
	if GameManager.is_mars_mission() or GameManager.is_asteroid_mission():
		_simulate_deep_space_comms()
		return

	# An Earth-orbiting satellite is reachable by exactly the stations that can
	# see it above ten degrees, for exactly as long as it stays above ten degrees.
	# No window in here was chosen by hand.
	var alt: float = float(GameManager.current_mission.get("altitude_km", 550))
	var visible: Dictionary = best_visible_station(alt)
	var had_contact: bool = state["ground_contact"]
	state["ground_contact"] = not visible.is_empty()
	state["ground_station_name"] = String(visible.get("name", ""))
	state["station_elevation_deg"] = float(visible.get("elevation_deg", 0.0))

	if state["ground_contact"]:
		var comms: Dictionary = GameManager.spacecraft_config.get("comms", {})
		var bw: float = comms.get("bandwidth_mbps", 1.0)
		# Megabytes, because the whole data model of this game is in megabytes: the
		# instruments add `rate × seconds` and the antenna takes it away again.  A
		# pass cut short by the horizon therefore delivers a smaller number, which
		# is the only way this can be honest.
		var downlinked: float = min(bw * dt_sim, state["data_stored_mb"])
		state["data_transmitted_mb"] += downlinked
		state["data_stored_mb"] = maxf(state["data_stored_mb"] - downlinked, 0.0)
		state["pass_mb"] = float(state.get("pass_mb", 0.0)) + downlinked
		if not had_contact:
			state["pass_mb"] = 0.0
			_log_event("📡 AOS — %s at %.0f° elevation" % [
				state["ground_station_name"], state["station_elevation_deg"]], "info")
	else:
		if had_contact:
			state["passes_completed"] = int(state.get("passes_completed", 0)) + 1
			_log_event("📡 LOS — %.0f MB of climate data received this pass" %
				float(state.get("pass_mb", 0.0)), "info")

## The simplified model, kept for the deep-space scenes.
func _simulate_deep_space_comms() -> void:
	# Simplified: contact 25% of the time (realistic for LEO with DSN coverage)
	var angle_deg: float = state["orbit_angle_deg"]
	# Contact windows at 4 points in the orbit
	var in_window: bool = false
	for center in [0, 90, 180, 270]:
		if abs(angle_deg - center) < 18.0:
			in_window = true
			break

	var had_contact: bool = state["ground_contact"]
	state["ground_contact"] = in_window

	if in_window:
		# Downlink data
		var comms: Dictionary = GameManager.spacecraft_config.get("comms", {})
		var bw: float = comms.get("bandwidth_mbps", 1.0)
		var downlinked: float = bw * 0.016  # per frame at ~60fps
		state["data_transmitted_mb"] += downlinked
		state["data_stored_mb"] = max(0, state["data_stored_mb"] - downlinked)
		state["ground_station_name"] = GROUND_STATIONS[state["total_orbits"] % 4]["name"]

		if not had_contact:
			_log_event("📡 Deep-space contact: " + state["ground_station_name"], "info")
	else:
		state["ground_station_name"] = ""
		if had_contact:
			_log_event("📡 Ground contact lost.", "info")

# ─── Real climate-event survey (Earth Climate Sentinel only) ─────────────────
## A target is observed when three things are simultaneously true, exactly as in
## the real programme: the sub-satellite point comes within the sensor's foot-
## print of the event, the spacecraft actually carries the instrument whose NASA
## analogue made the discovery, and the sensor can work right now — optical and
## trace-gas instruments need sunlight, thermal, SAR and the Day/Night Band do
## not.  A capture is one-time: the event enters the record and the data goes
## into the store, waiting for a ground-station pass like real science does.
func _simulate_climate_observation() -> void:
	if not state.get("instruments_active", true):
		return
	var targets: Array = state.get("climate_targets", [])
	if targets.is_empty():
		return
	var sat_dir: Vector3 = sub_point_direction()
	var sunlit: bool = not state["in_eclipse"]
	var payload: Array = GameManager.spacecraft_config.get("instruments", [])
	var active_target: int = int(state.get("active_scan_target", -1))
	if active_target < 0 or active_target >= targets.size():
		return
	for i in range(targets.size()):
		if i != active_target:
			continue
		var t: Dictionary = targets[i]
		if bool(t.get("captured", false)):
			continue
		if not _carries_instrument(payload, String(t["requires_instrument"])):
			continue
		if bool(t.get("needs_sunlight", false)) and not sunlit:
			continue
		var tgt_dir: Vector3 = station_world_direction(t)
		var separation: float = rad_to_deg(sat_dir.angle_to(tgt_dir))
		if separation > CLIMATE_FOOTPRINT_DEG:
			state["scan_status"] = "Awaiting overpass — %.1f° from scan footprint" % separation
			continue
		state["scan_status"] = "Scanning %s…" % String(t["name"])
		_capture_climate_target(t)
		state["active_scan_target"] = -1
		state["scan_status"] = "Scan complete — data recorder queued for downlink"

## Mission-control command.  It only arms a scan: data is collected later,
## when the real simulated ground track reaches the requested coordinates.
func request_climate_scan(target_index: int, mode: String = "JPSS-2") -> void:
	if not GameManager.is_earth_climate_mission():
		return
	var targets: Array = state.get("climate_targets", [])
	if target_index < 0 or target_index >= targets.size():
		return
	if bool(targets[target_index].get("captured", false)):
		state["scan_status"] = "This incident has already been scanned"
		return
	if String(targets[target_index].get("mission_mode", "JPSS-2")) != mode:
		state["scan_status"] = "%s payload is required for this target" % String(targets[target_index].get("mission_mode", "JPSS-2"))
		return
	state["active_scan_target"] = target_index
	state["scan_mode"] = mode
	state["scan_status"] = "%s task accepted — waiting for ground-track access" % mode
	_log_event("🎯 %s scan tasked: %s" % [mode, String(targets[target_index]["name"])], "info")

func _carries_instrument(payload: Array, wanted_id: String) -> bool:
	for inst in payload:
		if String(inst.get("id", "")) == wanted_id:
			return true
	return false

func _capture_climate_target(t: Dictionary) -> void:
	t["captured"] = true
	t["captured_day"] = int(state["day"])
	state["targets_captured"] = int(state.get("targets_captured", 0)) + 1
	var gained: float = float(t["science"]) * float(state.get("science_mult", 1.0))
	state["science_points"] = float(state["science_points"]) + gained
	# The observation becomes data before it becomes science: it lands in the
	# recorder and must still survive the trip home through a station pass.
	var bus: Dictionary = GameManager.spacecraft_config.get("bus", {})
	var storage_mb: float = bus.get("data_storage", 200) * 1000
	state["data_stored_mb"] = minf(float(state["data_stored_mb"]) + float(t["data_mb"]), storage_mb)
	var msg: String = "🌍 OBSERVED: %s — %s (source: %s). +%.0f climate science, %.0f MB recorded." % [
		t["name"], t["sensor"], t["source"], gained, float(t["data_mb"])]
	_log_event(msg, "success")
	event_occurred.emit({
		"id": "climate_target_" + String(t["requires_instrument"]),
		"kind": "climate_capture",
		"target": t.duplicate(true),
		"name": "Climate event observed: " + String(t["name"]),
		"desc": String(t["sensor"]) + "\n" + String(t["note"]),
		"type": "success"
	})

## The four listed climate objectives, evaluated live from state so the HUD and
## the final report always agree.
func _earth_objectives_done() -> Array:
	var done: Array = []
	if int(state.get("targets_captured", 0)) >= 3:
		done.append("Observe 3+ real NASA-tracked climate events from orbit")
	if float(state.get("science_points", 0.0)) >= float(state.get("target_science", 80)):
		done.append("Collect 80 science points from Earth observation")
	if int(state.get("passes_completed", 0)) >= 3:
		done.append("Downlink data during 3+ ground station passes")
	var cost: float = float(GameManager.spacecraft_config.get("total_cost", 0))
	if cost <= float(GameManager.current_mission.get("budget", 120)):
		done.append("Keep total mission cost under 120M credits")
	return done

# ─── Eclipse Detection ────────────────────────────────────────────────────────
func _is_in_eclipse(angle: float) -> bool:
	var target: String = String(GameManager.current_mission.get("target", ""))
	if "Asteroid" in target:
		return false
	# Eclipse in the "behind Earth" portion of orbit
	# Simplified: eclipse from π*0.6 to π*1.4 (roughly 40% of orbit in shadow for LEO)
	var norm: float = angle / PI2
	return norm > 0.55 and norm < 0.85

# ─── Orbital Mechanics ────────────────────────────────────────────────────────
func _compute_orbit_period(mission: Dictionary) -> float:
	var alt: float = mission.get("altitude_km", 550)
	var target: String = mission.get("target", "Low Earth Orbit")

	var mu: float
	var r_body: float

	if "Moon" in target or "Lunar" in target:
		mu = MU_MOON
		r_body = RE_MOON
	elif "Mars" in target:
		mu = 42828.0  # km³/s²
		r_body = 3389.5
	elif "Asteroid" in target:
		mu = 0.8  # km³/s² (small NEO analogue for the mission gameplay loop)
		r_body = 0.25 + alt * 0.15
	else:
		mu = MU_EARTH
		r_body = RE_EARTH

	var r: float = max(1.0, r_body + alt)
	var period: float = PI2 * sqrt(pow(r, 3) / mu)
	return max(period, 60.0)  # seconds

func _asteroid_objectives_done() -> Array:
	var completed: Array = []
	if state.get("rendezvous_complete", false):
		completed.append("Successfully rendezvous with asteroid")
	if state.get("asteroid_orbit_days", 0) >= 30:
		completed.append("Orbit the asteroid for 30 days")
	if state.get("composition_analyzed", false):
		completed.append("Analyze surface composition")
	if state.get("data_transmitted_mb", 0.0) > 0.0:
		completed.append("Return data to Earth")
	return completed

func _compute_eclipse_fraction(alt_km: float) -> float:
	# LEO: ~35% eclipse. Higher orbits: less eclipse.
	if alt_km < 600:
		return 0.35
	elif alt_km < 2000:
		return 0.30
	else:
		return 0.20

# ─── Random Events ────────────────────────────────────────────────────────────
func _trigger_random_event() -> void:
	var pool: Array = EVENTS.duplicate()
	var target: String = String(GameManager.current_mission.get("target", ""))
	if "Mars" in target:
		pool.append({
			"id": "dust_storm", "name": "Global Dust Storm",
			"desc": "A planet-wide Martian dust storm dims imaging and solar arrays.",
			"type": "warning", "probability": 0.08,
			"effect": {"power_gen_mult": 0.7, "science_mult": 0.75, "duration_orbits": 4}
		})
		pool.append({
			"id": "dust_devil", "name": "Dust Devil Tracked",
			"desc": "Instruments capture a dust devil — bonus climate science.",
			"type": "success", "probability": 0.05,
			"effect": {"bonus_science": 18}
		})
	if "Asteroid" in target:
		pool.append({
			"id": "outgassing", "name": "Outgassing Event",
			"desc": "A burst of volatile vapor vents from the asteroid and disturbs the spacecraft's attitude control.",
			"type": "warning", "probability": 0.07,
			"effect": {"science_mult": 0.8, "power_gen_mult": 0.9, "duration_orbits": 3}
		})
		pool.append({
			"id": "microgravity_drift", "name": "Microgravity Drift",
			"desc": "The asteroid's weak gravity shifts the spacecraft's line of sight and reduces imaging precision.",
			"type": "warning", "probability": 0.06,
			"effect": {"science_mult": 0.7, "duration_orbits": 2}
		})
		pool.append({
			"id": "organic_signal", "name": "Organic Signal Detected",
			"desc": "A faint organics signature appears in spectral data — unexpected bonus science.",
			"type": "success", "probability": 0.05,
			"effect": {"bonus_science": 22}
		})
	var roll: float = _rng.randf()
	var cumulative: float = 0.0
	for ev in pool:
		cumulative += ev["probability"]
		if roll <= cumulative:
			_apply_event(ev)
			return

func _apply_event(ev: Dictionary) -> void:
	var effect: Dictionary = ev.get("effect", {})
	_log_event(ev["name"] + " — " + ev["desc"], ev.get("type", "info"))

	if effect.has("power_gen_mult"):
		state["power_gen_mult"] *= effect["power_gen_mult"]
		state["active_effects"].append({
			"id": ev["id"], "power_gen_mult_inv": 1.0 / effect["power_gen_mult"],
			"remaining_orbits": effect.get("duration_orbits", 1)
		})
	if effect.has("science_mult"):
		state["science_mult"] *= effect["science_mult"]
		state["active_effects"].append({
			"id": ev["id"], "science_mult_inv": 1.0 / effect["science_mult"],
			"remaining_orbits": effect.get("duration_orbits", 1)
		})
	if effect.has("bonus_science"):
		state["science_points"] += effect["bonus_science"]
	if effect.has("comms_blocked"):
		state["comms_blocked"] = true
		state["active_effects"].append({
			"id": ev["id"], "comms_blocked": true,
			"remaining_orbits": effect.get("duration_orbits", 2)
		})
	if effect.has("battery_mult"):
		state["battery_max_wh"] *= effect["battery_mult"]

	event_occurred.emit(ev)

func _remove_effect(eff: Dictionary) -> void:
	if eff.has("power_gen_mult_inv"):
		state["power_gen_mult"] *= eff["power_gen_mult_inv"]
	if eff.has("science_mult_inv"):
		state["science_mult"] *= eff["science_mult_inv"]
	if eff.has("comms_blocked"):
		state["comms_blocked"] = false

func _log_event(msg: String, type: String) -> void:
	var log_entry: Dictionary = {
		"day": state.get("day", 0),
		"orbit": state.get("total_orbits", 0),
		"msg": msg,
		"type": type
	}
	state["events_log"].append(log_entry)
	print("[SimEngine] Day %d: %s" % [state.get("day", 0), msg])

# ─── Mission End ──────────────────────────────────────────────────────────────
func _end_mission() -> void:
	running = false
	var config: Dictionary = GameManager.spacecraft_config
	var mission: Dictionary = GameManager.current_mission

	var science: float = state.get("science_points", 0)
	var target_sci: float = mission.get("science_goal", 80)
	var duration: int = state.get("mission_duration_days", 365)
	var power_ok: bool = state.get("mission_health", 100) > 50

	# Score components (out of 100)
	var asteroid_mission: bool = GameManager.is_asteroid_mission()
	var earth_mission: bool = GameManager.is_earth_climate_mission()
	var asteroid_objectives: Array = _asteroid_objectives_done() if asteroid_mission else []
	var earth_objectives: Array = _earth_objectives_done() if earth_mission else []
	var obj_score: float
	if asteroid_mission:
		obj_score = 35.0 * float(asteroid_objectives.size()) / 4.0
	elif earth_mission:
		# The climate sentinel is scored on the survey it actually completed —
		# events observed, science returned, data downlinked, budget held — not
		# on a raw point tally.
		obj_score = 35.0 * float(earth_objectives.size()) / 4.0
	else:
		obj_score = clamp((science / target_sci) * 35, 0, 35)
	var sci_score: float    = clamp((science / target_sci) * 25, 0, 25)
	var rel_score: float    = state.get("mission_health", 100) / 100.0 * 20
	var budget_pct: float   = config.get("total_cost", 0) / mission.get("budget", 120)
	var eff_score: float    = clamp((1.0 - budget_pct) * 15, 0, 15)
	var ops_score: float    = 5.0  # Base ops score

	var total_score: float = obj_score + sci_score + rel_score + eff_score + ops_score

	# Reliability modifier
	var bus_rel: float = config.get("bus", {}).get("reliability", 0.9)
	var rocket_rel: float = config.get("rocket", {}).get("reliability", 0.95)
	total_score *= (bus_rel * rocket_rel)

	var success: bool = science >= target_sci and power_ok
	if asteroid_mission:
		success = success and asteroid_objectives.size() == 4
	# An Earth climate sentinel has only done its job once it has come all the way
	# round and got its observations off to the ground.  Reaching LEO and crossing
	# the Kármán line is necessary, not sufficient: without two downlinked survey
	# revolutions the mission has returned no climate data, and returning no data is
	# exactly the failure the operator was warned about.
	var revs: int = int(state.get("commission_revolutions", 0))
	var returned_mb: float = float(state.get("data_transmitted_mb", 0.0))
	if not asteroid_mission and not GameManager.is_mars_mission():
		success = success and revs >= 2 and returned_mb > 0.0

	# What the real-record contribution actually was: the events this design
	# observed, with the sensor and the NASA dataset behind each one.  The report
	# screen prints it as a data-return manifest.
	var observed: Array = []
	var earth_bonuses: Array = []
	if earth_mission:
		for t in state.get("climate_targets", []):
			if bool(t.get("captured", false)):
				observed.append({
					"name": String(t["name"]), "sensor": String(t["sensor"]),
					"source": String(t["source"]), "day": int(t["captured_day"]),
					"science": float(t["science"]), "note": String(t["note"]),
					"date": String(t.get("date", "")), "stat": String(t.get("stat", "")),
					"img_url": String(t.get("img_url", "")), "credit": String(t.get("credit", ""))
				})
		if observed.size() == CLIMATE_TARGETS.size():
			earth_bonuses.append("All 6 climate events observed")
		if int(state.get("safe_mode_events", 0)) == 0:
			earth_bonuses.append("No power failures (zero safe-mode entries)")
		if returned_mb >= 1000.0:
			earth_bonuses.append("Delivered 1+ GB of climate data to Earth")

	var result: Dictionary = {
		"success": success,
		"score": int(total_score),
		"science_collected": science,
		"science_goal": target_sci,
		"data_transmitted_gb": state.get("data_transmitted_mb", 0) / 1000.0,
		"total_orbits": state.get("total_orbits", 0),
		"commission_revolutions": revs,
		"commission_passes": int(state.get("commission_passes", 0)),
		"climate_data_returned_mb": returned_mb,
		"mission_days": duration,
		"objectives_done": asteroid_objectives if asteroid_mission else earth_objectives,
		"objectives_required": mission.get("objectives", []) if (asteroid_mission or earth_mission) else [],
		"climate_events_observed": observed,
		"targets_captured": int(state.get("targets_captured", 0)),
		"climate_bonus_objectives": earth_bonuses,
		"nodal_precession_deg_day": float(state.get("nodal_precession_deg_day", 0.0)),
		"events_log": state.get("events_log", []),
		"score_breakdown": {
			"objectives": int(obj_score),
			"science": int(sci_score),
			"reliability": int(rel_score),
			"efficiency": int(eff_score),
			"operations": int(ops_score)
		},
		"improvements": _generate_improvements()
	}

	GameManager.mission_result = result
	mission_ended.emit(result)
	print("[SimEngine] Mission ended. Score: %d/100 — %s" % [int(total_score), "SUCCESS" if success else "FAILURE"])

func _generate_improvements() -> Array:
	var tips: Array = []
	var config: Dictionary = GameManager.spacecraft_config
	var gen: float = config.get("total_power_gen", 0)
	var draw: float = config.get("total_power_draw", 0)
	if gen - draw < 50:
		tips.append("Add a larger solar array — your power margin was very tight during eclipses.")
	if config.get("battery_capacity", 0) < 200:
		tips.append("Upgrade your battery to survive longer eclipse periods without losing science.")
	var data_rate: float = config.get("total_data_rate", 0)
	var comms_bw: float = config.get("comms", {}).get("bandwidth_mbps", 1)
	if data_rate > comms_bw * 10:
		tips.append("Your antenna bandwidth is much lower than your data generation rate. Upgrade comms or reduce instruments.")
	if config.get("total_cost", 0) > GameManager.current_mission.get("budget", 120) * 0.9:
		tips.append("You were very close to your budget limit. A more affordable bus or fewer instruments could give more margin.")
	if GameManager.is_earth_climate_mission():
		# Coach the real-science layer specifically: which sensor senses which
		# event, and why daylight matters for the optical ones.
		var caps: int = int(state.get("targets_captured", 0))
		if caps < 3:
			tips.append("Only %d of the real climate events were sensed. Carry the instruments those events actually need — thermal imagers for FIRMS wildfires and marine heatwaves, SAR radar for the Amazon flood pulse and Greenland ice, a spectrometer for volcanic SO\u2082 — and remember optical instruments only work in sunlight." % caps)
		else:
			tips.append("%d real NASA-tracked events surveyed. Fly the full six-event record next time — and downlink it all, because science that stays onboard is science that never happened." % caps)
	if tips.is_empty():
		tips.append("Great design! Try increasing science instruments for an even higher score.")
	return tips

# ─── Controls ─────────────────────────────────────────────────────────────────
func set_time_scale(idx: int) -> void:
	time_scale_idx = clamp(idx, 0, TIME_SCALES.size() - 1)
	time_scale = TIME_SCALES[time_scale_idx]

func speed_up() -> void:
	set_time_scale(time_scale_idx + 1)

func speed_down() -> void:
	set_time_scale(time_scale_idx - 1)

func pause_sim() -> void:
	paused = true

func resume_sim() -> void:
	paused = false

func transmit_data_manual() -> void:
	if state.get("ground_contact", false):
		var comms: Dictionary = GameManager.spacecraft_config.get("comms", {})
		var bw: float = comms.get("bandwidth_mbps", 1.0)
		var burst: float = bw * 60  # 1 minute burst
		var sent: float = min(burst, state.get("data_stored_mb", 0))
		state["data_stored_mb"] -= sent
		state["data_transmitted_mb"] = state.get("data_transmitted_mb", 0) + sent
		_log_event("📡 Manual downlink: %.1f MB transmitted." % sent, "success")
	else:
		_log_event("❌ No ground contact — cannot transmit.", "warning")
