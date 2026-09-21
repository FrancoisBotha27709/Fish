@tool
class_name PollutedAtmosphere
extends WorldEnvironment

@export var sky_shader: Shader   ## Leave empty to auto-load new_sky.gdshader from this script's folder.

@export_group("Sun")
@export var create_sun := true:
	set(v): create_sun = v; _queue_apply()
@export_range(2.0, 80.0) var sun_elevation_deg := 22.0:
	set(v): sun_elevation_deg = v; _queue_apply()
@export_range(-180.0, 180.0) var sun_azimuth_deg := 20.0:   ## 0 = sun straight ahead along -Z
	set(v): sun_azimuth_deg = v; _queue_apply()
@export_range(0.0, 4.0) var sun_energy := 1.5:
	set(v): sun_energy = v; _queue_apply()
@export var sun_color := Color(0.92, 0.86, 0.64):   ## warm, dirty, close to neutral - not saturated green
	set(v): sun_color = v; _queue_apply()
@export_range(0.5, 10.0) var sun_softness := 2.5:   ## light_angular_distance - big & soft, since real sunlight would be smog-diffused
	set(v): sun_softness = v; _queue_apply()
@export_range(50.0, 500.0) var sun_shadow_distance := 250.0:
	set(v): sun_shadow_distance = v; _queue_apply()

@export_group("Fill Light")
## A second, shadowless light standing in for light that has scattered through
## the smog itself. Without this, anything not directly hit by the sun goes
## pure black - one hard light with nothing filling the shadows is the #1
## reason a scene "just looks terrible". This is what actually fixes that.
@export var create_fill_light := true:
	set(v): create_fill_light = v; _queue_apply()
@export_range(0.0, 1.0) var fill_energy := 0.5:
	set(v): fill_energy = v; _queue_apply()
@export var fill_color := Color(0.38, 0.38, 0.32):
	set(v): fill_color = v; _queue_apply()

@export_group("Smog")
@export_range(0.0, 1.0) var smog_coverage := 0.75:
	set(v): smog_coverage = v; _queue_apply()
@export_range(0.0, 3.0) var smog_density := 1.1:
	set(v): smog_density = v; _queue_apply()
@export_range(0.2, 6.0) var smog_scale := 1.4:
	set(v): smog_scale = v; _queue_apply()
@export_range(0.0, 0.05) var smog_speed := 0.006:
	set(v): smog_speed = v; _queue_apply()
@export_range(0.0, 1.0) var haze_strength := 0.45:
	set(v): haze_strength = v; _queue_apply()

@export_group("Colors")
@export var zenith_color := Color(0.05, 0.06, 0.055):   ## dark neutral grey, only a whisper of green - not near-black
	set(v): zenith_color = v; _queue_apply()
@export var horizon_color := Color(0.42, 0.40, 0.33):   ## grey-brown haze with a hint of green. Also drives the fog colour, so distant water melts into the sky.
	set(v): horizon_color = v; _queue_apply()
@export var ground_color := Color(0.16, 0.15, 0.12):
	set(v): ground_color = v; _queue_apply()
@export var smog_light_color := Color(0.55, 0.52, 0.42):   ## sunlit smog - warm grey-brown, not neon green
	set(v): smog_light_color = v; _queue_apply()
@export var smog_dark_color := Color(0.11, 0.12, 0.10):   ## soot grey, not near-black
	set(v): smog_dark_color = v; _queue_apply()
@export_range(0.0, 4.0) var sun_glow := 0.9:
	set(v): sun_glow = v; _queue_apply()

@export_group("Hatching")
## How the smog's self-shadowing gets rendered - the original smooth look,
## or real pen-and-ink hatch marks. Matches hatch_shadow.gdshaderinc's presets.
@export_enum("Soft Relief", "Cross-Hatch", "Parallel Streaks", "Stipple") var hatch_style := 0:
	set(v): hatch_style = v; _queue_apply()
@export_range(1.0, 400.0) var hatch_scale := 40.0:   ## line/dot spacing
	set(v): hatch_scale = v; _queue_apply()
@export_range(0.0, 2.0) var hatch_strength := 1.0:   ## how readily shadow turns into visible marks
	set(v): hatch_strength = v; _queue_apply()
@export_range(0.0, 180.0) var hatch_angle_deg := 45.0:
	set(v): hatch_angle_deg = v; _queue_apply()
@export_range(0.01, 0.5) var hatch_offset := 0.12:   ## self-shadow sample offset toward the sun
	set(v): hatch_offset = v; _queue_apply()
@export_range(0.5, 8.0) var hatch_sharpness := 4.0:   ## contrast of the relief before hatching
	set(v): hatch_sharpness = v; _queue_apply()

@export_group("Atmosphere")
@export_range(0.0, 0.03, 0.0005) var fog_density := 0.0014:   ## Higher = thicker smog on the water. Also hides the edge of the water mesh.
	set(v): fog_density = v; _queue_apply()
@export_range(0.0, 0.1, 0.001) var ground_smog := 0.006:      ## Extra smog hugging the water surface.
	set(v): ground_smog = v; _queue_apply()
@export_range(0.2, 3.0) var exposure := 1.35:
	set(v): exposure = v; _queue_apply()
@export_range(0.0, 3.0) var ambient_energy := 1.7:
	set(v): ambient_energy = v; _queue_apply()
@export_range(0.0, 2.0) var glow_amount := 0.45:
	set(v): glow_amount = v; _queue_apply()

@export_group("Volumetric Fog")
## Real 3D fog that the sun scatters through -> visible dirty god-rays cutting
## through the smog. This is the single biggest upgrade over flat height-fog.
@export var enable_volumetric_fog := true:
	set(v): enable_volumetric_fog = v; _queue_apply()
@export_range(0.0, 1.0) var vol_fog_density := 0.012:
	set(v): vol_fog_density = v; _queue_apply()
@export_range(0.0, 1.0) var vol_fog_anisotropy := 0.35:   ## forward-scattering strength - higher = punchier god-rays toward the sun
	set(v): vol_fog_anisotropy = v; _queue_apply()
@export_range(0.0, 512.0) var vol_fog_length := 128.0:
	set(v): vol_fog_length = v; _queue_apply()
@export_range(0.0, 4.0) var vol_fog_gi_inject := 1.0:   ## how strongly the sky/GI ambient colours the fog itself
	set(v): vol_fog_gi_inject = v; _queue_apply()

@export_group("Ambient / GI")
@export var enable_ssao := true:
	set(v): enable_ssao = v; _queue_apply()
@export var enable_ssil := true:   ## bounces the sickly ambient light into corners/crevices instead of leaving them flat
	set(v): enable_ssil = v; _queue_apply()
@export var enable_sdfgi := false:   ## real-time GI - much nicer indirect bounce light, but costlier; try it if your scene has geometry to bounce off
	set(v): enable_sdfgi = v; _queue_apply()

@export_group("Blackout")
## Driven by VisionSignals.darken_vision_changed (fired by CameraLook when
## the player is being pushed back from a world border). 0 = normal look,
## 1 = fully blacked out. Only this group's-worth of properties get touched
## every frame during the transition - everything else is "static" and only
## recomputed when you actually change an exported value above.
@export var blackout_color := Color(0.0, 0.0, 0.0)
@export_range(0.0, 0.1, 0.001) var blackout_fog_density := 0.05
@export_range(0.05, 3.0) var blackout_exposure := 0.05
@export_range(0.0, 1.0) var blackout_ambient := 0.0

var _env: Environment
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D

var _blackout_amount: float = 0.0
var _apply_queued: bool = false

## Cached so get_sun_direction() (potentially polled every frame by e.g.
## CloudLayer.gd) doesn't rebuild a Basis + do trig on every call - it's only
## recomputed when the sun's angle actually changes.
var _cached_sun_direction: Vector3 = Vector3.FORWARD

## StringName constants for shader params: avoids re-hashing a string literal
## into a StringName on every set_shader_parameter call, which matters here
## since several of these are set every frame during a blackout transition.
const P_ZENITH := &"zenith_color"
const P_HORIZON := &"horizon_color"
const P_GROUND := &"ground_color"
const P_SMOG_LIGHT := &"smog_light_color"
const P_SMOG_DARK := &"smog_dark_color"
const P_SMOG_COVERAGE := &"smog_coverage"
const P_SMOG_DENSITY := &"smog_density"
const P_SMOG_SCALE := &"smog_scale"
const P_SMOG_SPEED := &"smog_speed"
const P_HAZE_STRENGTH := &"haze_strength"
const P_SUN_GLOW := &"sun_glow"
const P_HATCH_STYLE := &"hatch_style"
const P_HATCH_SCALE := &"hatch_scale"
const P_HATCH_STRENGTH := &"hatch_strength"
const P_HATCH_ANGLE := &"hatch_angle_deg"
const P_HATCH_OFFSET := &"hatch_offset"
const P_HATCH_SHARPNESS := &"hatch_sharpness"


## World-space direction the sunlight TRAVELS IN (matches LIGHT0_DIRECTION's
## convention in the sky/cloud shaders). Lets other scripts (CloudLayer.gd)
## follow the same sun without needing a reference to the _sun node itself.
func get_sun_direction() -> Vector3:
	return _cached_sun_direction

func _ready() -> void:
	_build()
	_apply()

	if not Engine.is_editor_hint():
		var vision_signals := get_node_or_null("/root/VisionSignals")
		if vision_signals:
			vision_signals.darken_vision_changed.connect(_on_darken_vision_changed)
		else:
			push_warning("PollutedAtmosphere: VisionSignals autoload not found - add it in Project Settings > Autoload. Blackout effect will be disabled.")

func _build() -> void:
	if sky_shader == null:
		var dir: String = (get_script() as Script).resource_path.get_base_dir()
		sky_shader = load(dir.path_join("new_sky.gdshader")) as Shader
	if sky_shader == null:
		push_warning("PollutedAtmosphere: new_sky.gdshader not found next to this script - assign sky_shader.")
		return

	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sky_shader

	var sky := Sky.new()
	sky.sky_material = _sky_mat
	# The smog/clouds animate, so the reflection/ambient map must refresh.
	# INCREMENTAL spreads that cost over several frames instead of redoing the
	# whole cubemap every frame.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_white = 4.0

	_env.glow_enabled = true
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.glow_hdr_threshold = 0.9
	_env.glow_bloom = 0.06

	_env.fog_enabled = true
	_env.fog_sky_affect = 0.35
	_env.fog_aerial_perspective = 0.2
	_env.fog_sun_scatter = 0.08
	_env.fog_height = 25.0

	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.05
	_env.adjustment_saturation = 0.55   ## the big knob for "too green" - pushes the whole render toward grey

	# --- Ambient occlusion / bounce light: without these, anything not lit
	# straight-on by the sun goes flat and dead. SSIL specifically is what
	# makes the sickly green ambient light actually wrap into corners. ---
	_env.ssao_radius = 1.0
	_env.ssao_intensity = 1.1
	_env.ssao_power = 1.0

	_env.ssil_radius = 5.0
	_env.ssil_intensity = 1.2
	_env.ssil_sharpness = 0.98

	# --- Volumetric fog: real 3D density the sun scatters through, giving
	# visible dirty god-rays instead of a flat haze overlay. ---
	_env.volumetric_fog_detail_spread = 2.0

	environment = _env


## Coalesces any number of exported-property changes made within the same
## frame (e.g. dragging several inspector sliders, or a script setting many
## properties at once) into a single _apply() call instead of one per setter.
func _queue_apply() -> void:
	if _apply_queued or not is_node_ready() or _env == null:
		return
	_apply_queued = true
	call_deferred("_apply")


## Full, "static" rebuild of everything that ISN'T driven by the blackout
## blend - shader params, fog/GI toggles, light transforms/colors. Only runs
## when an exported property actually changes, not every frame.
func _apply() -> void:
	_apply_queued = false
	if not is_node_ready() or _env == null:
		return

	_sky_mat.set_shader_parameter(P_SMOG_SCALE, smog_scale)
	_sky_mat.set_shader_parameter(P_SMOG_SPEED, smog_speed)
	_sky_mat.set_shader_parameter(P_HAZE_STRENGTH, haze_strength)
	_sky_mat.set_shader_parameter(P_HATCH_STYLE, hatch_style)
	_sky_mat.set_shader_parameter(P_HATCH_SCALE, hatch_scale)
	_sky_mat.set_shader_parameter(P_HATCH_STRENGTH, hatch_strength)
	_sky_mat.set_shader_parameter(P_HATCH_ANGLE, hatch_angle_deg)
	_sky_mat.set_shader_parameter(P_HATCH_OFFSET, hatch_offset)
	_sky_mat.set_shader_parameter(P_HATCH_SHARPNESS, hatch_sharpness)

	_env.fog_height_density = ground_smog

	_env.ssao_enabled = enable_ssao
	_env.ssil_enabled = enable_ssil
	_env.sdfgi_enabled = enable_sdfgi

	_env.volumetric_fog_enabled = enable_volumetric_fog
	_env.volumetric_fog_anisotropy = vol_fog_anisotropy
	_env.volumetric_fog_length = vol_fog_length
	_env.volumetric_fog_gi_inject = vol_fog_gi_inject

	_update_cached_sun_direction()
	_update_lights_static()

	# Re-apply the blackout blend on top so changing a base color/value while
	# mid-transition doesn't cause a visible pop back to the "clean" look.
	_apply_blackout()


func _update_cached_sun_direction() -> void:
	var rot := Vector3(-sun_elevation_deg, sun_azimuth_deg + 180.0, 0.0)
	var basis := Basis.from_euler(rot * (PI / 180.0))
	_cached_sun_direction = -basis.z   # a DirectionalLight3D shines along its local -Z


## Transform/shadow/color setup for the sun & fill lights - everything except
## their energy, which is blackout-dependent and lives in _apply_blackout().
func _update_lights_static() -> void:
	if create_sun:
		if _sun == null:
			_sun = DirectionalLight3D.new()
			_sun.name = "SmogSun"
			add_child(_sun)   # no owner set on purpose: rebuilt on load, never saved into your scene
			_sun.shadow_enabled = true
		_sun.directional_shadow_max_distance = sun_shadow_distance
		_sun.light_angular_distance = sun_softness   # big, soft, smog-diffused shadows
		# Light points along -Z; the sun sits opposite, so +180 makes azimuth 0 = sun ahead.
		_sun.rotation_degrees = Vector3(-sun_elevation_deg, sun_azimuth_deg + 180.0, 0.0)
		_sun.light_color = sun_color
	elif _sun != null:
		_sun.queue_free()
		_sun = null

	if create_fill_light:
		if _fill == null:
			_fill = DirectionalLight3D.new()
			_fill.name = "SmogFill"
			add_child(_fill)   # no owner set on purpose: rebuilt on load, never saved into your scene
			_fill.shadow_enabled = false   # cheap, and shadows here would just look like noise
		# Pointed roughly the opposite way and steeper than the sun, so it fills
		# in what the sun's hard shadow leaves dark, without fighting it visually.
		_fill.rotation_degrees = Vector3(-70.0, sun_azimuth_deg, 0.0)
		_fill.light_color = fill_color
	elif _fill != null:
		_fill.queue_free()
		_fill = null


func _on_darken_vision_changed(intensity: float) -> void:
	var clamped := clampf(intensity, 0.0, 1.0)
	if is_equal_approx(clamped, _blackout_amount):
		return
	_blackout_amount = clamped
	_apply_blackout()


## Lightweight path: only the properties that actually blend with the
## blackout amount. This is the one that runs every frame while a transition
## is in progress, so it deliberately touches far fewer params than _apply().
func _apply_blackout() -> void:
	if _env == null or _sky_mat == null:
		return

	var t := _blackout_amount
	var zc := zenith_color.lerp(blackout_color, t)
	var hc := horizon_color.lerp(blackout_color, t)
	var gc := ground_color.lerp(blackout_color, t)
	var slc := smog_light_color.lerp(blackout_color, t)
	var sdc := smog_dark_color.lerp(blackout_color, t)

	_sky_mat.set_shader_parameter(P_ZENITH, zc)
	_sky_mat.set_shader_parameter(P_HORIZON, hc)
	_sky_mat.set_shader_parameter(P_GROUND, gc)
	_sky_mat.set_shader_parameter(P_SMOG_LIGHT, slc)
	_sky_mat.set_shader_parameter(P_SMOG_DARK, sdc)
	_sky_mat.set_shader_parameter(P_SMOG_COVERAGE, lerpf(smog_coverage, 1.0, t))
	_sky_mat.set_shader_parameter(P_SMOG_DENSITY, smog_density)
	_sky_mat.set_shader_parameter(P_SUN_GLOW, lerpf(sun_glow, 0.0, t))

	_env.ambient_light_energy = lerpf(ambient_energy, blackout_ambient, t)
	_env.tonemap_exposure = lerpf(exposure, blackout_exposure, t)
	_env.glow_enabled = true
	_env.glow_intensity = lerpf(glow_amount, 0.0, t)
	_env.fog_enabled = true
	_env.fog_light_color = hc.darkened(0.15)
	_env.fog_density = lerpf(fog_density, blackout_fog_density, t)

	_env.volumetric_fog_density = lerpf(vol_fog_density, blackout_fog_density, t)
	_env.volumetric_fog_albedo = slc

	if _sun != null:
		_sun.light_energy = lerpf(sun_energy, 0.0, t)
	if _fill != null:
		_fill.light_energy = lerpf(fill_energy, 0.0, t)
