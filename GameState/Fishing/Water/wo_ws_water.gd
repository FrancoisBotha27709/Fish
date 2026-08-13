extends MeshInstance3D

class_name WaterManager

const MAX_RIPPLES := 32

# Keep these in sync with the shader's uniforms of the same name — they're
# pushed to the material in _ready so the script is the single source of
# truth (handy if you want to tune these from code/UI instead of the
# inspector).
@export var ripple_lifetime: float = 6.0
@export var ripple_speed: float = 2.2
@export var ripple_wavelength: float = 0.7
@export var ripple_width: float = 1.2
@export var ripple_amplitude: float = 0.4
@export var meters_per_unit: float = 1.0

# Mirrors the shader's Waves / Large_Scale_Variation uniform groups, same
# reason as the ripple params above: get_water_height_at() below has to
# reproduce this exact math on the CPU, so it needs the exact same values
# the shader is using, not a second hand-tuned copy that can drift.
@export_group("Waves")
@export var swell_amplitude: float = 3.2
@export var swell_wavelength_scale: float = 1.0
@export var chop_amplitude: float = 0.35
@export var wave_speed: float = 1.0
@export var wave_choppiness: float = 0.9        # steepens visual peaks only — doesn't affect the vertical height sampled below
@export var wind_direction_deg: float = 30.0
@export var wave_direction_jitter: float = 20.0
@export var chop_patchiness: float = 0.5

@export_group("Large Scale Variation")
@export var domain_warp_amount: float = 35.0
@export var domain_warp_scale: float = 0.004
@export var domain_warp_speed: float = 0.02

# Slowly, organically varies overall wave energy over time — calm
# stretches, then building chop, then big rolling swell, on no fixed
# cycle. This is a MULTIPLIER on swell_amplitude / chop_amplitude (and,
# more softly, wave_speed) — it doesn't replace biomes, which vary wave
# character by LOCATION; this varies it by TIME, everywhere at once. Both
# layer together: a biome's own amplitude multiplier still applies on top
# of whatever the sea state currently is.
@export_group("Sea State (Temporal Variation)")
@export var enable_sea_state_variation: bool = true
@export var sea_state_min: float = 0.2               # calmest multiplier on swell/chop amplitude (0.2 = 20% of your base height)
@export var sea_state_max: float = 1.6                # wildest multiplier on swell/chop amplitude
@export var sea_state_change_speed: float = 0.015     # how fast the sea state drifts; lower = longer, slower-building stretches of calm/storm
@export var sea_state_speed_influence: float = 0.4    # 0 = wave_speed never changes with sea state; 1 = wave_speed scales fully with the same multiplier as amplitude

var _material: ShaderMaterial

var _slot_pos: Array[Vector2] = []
var _slot_time: Array[float] = []
var _slot_strength: Array[float] = []
var _next_slot := 0
var _sim_time := 0.0

# Current sea-state-modulated values — what get_water_height_at() and the
# shader push actually use each frame. Initialized to the base exports and
# recomputed in _update_sea_state() every _process if variation is on.
var _sea_state_phase := 0.0
var _current_swell_amplitude: float
var _current_chop_amplitude: float
var _current_wave_speed: float

# ------------------------------------------------------------------
# Gerstner wave constants — copied verbatim from the shader so the
# height field sampled here matches what's actually rendered.
# ------------------------------------------------------------------
const WAVE_COUNT := 6
const IS_SWELL: Array[bool] = [true, true, false, false, false, false]
const WAVE_ANGLES: Array[float] = [0.0, 24.0, 61.0, -37.0, 104.0, -73.0]
const WAVE_BASE_LENGTHS: Array[float] = [85.0, 52.0, 22.0, 13.0, 6.0, 3.2]
const WAVE_STEEPNESS: Array[float] = [0.8, 0.7, 0.45, 0.35, 0.22, 0.14]
const WAVE_AMP_SCALE: Array[float] = [1.0, 0.6, 0.32, 0.2, 0.1, 0.05]
const WAVE_SPEED_MULT: Array[float] = [0.9, 1.05, 1.3, 1.5, 1.9, 2.2]

func _ready() -> void:
	if material_override is ShaderMaterial:
		_material = material_override
	elif mesh and mesh.surface_get_material(0) is ShaderMaterial:
		_material = mesh.surface_get_material(0)

	if _material == null:
		push_warning("WaterManager: no ShaderMaterial found on this MeshInstance3D.")

	_current_swell_amplitude = swell_amplitude
	_current_chop_amplitude = chop_amplitude
	_current_wave_speed = wave_speed

	_slot_pos.resize(MAX_RIPPLES)
	_slot_time.resize(MAX_RIPPLES)
	_slot_strength.resize(MAX_RIPPLES)
	for i in MAX_RIPPLES:
		_slot_pos[i] = Vector2.ZERO
		_slot_time[i] = -1000.0
		_slot_strength[i] = 0.0

	if _material:
		_material.set_shader_parameter("ripple_lifetime", ripple_lifetime)
		_material.set_shader_parameter("ripple_speed", ripple_speed)
		_material.set_shader_parameter("ripple_wavelength", ripple_wavelength)
		_material.set_shader_parameter("ripple_width", ripple_width)
		_material.set_shader_parameter("ripple_amplitude", ripple_amplitude)
		_material.set_shader_parameter("meters_per_unit", meters_per_unit)
		_material.set_shader_parameter("swell_amplitude", _current_swell_amplitude)
		_material.set_shader_parameter("swell_wavelength_scale", swell_wavelength_scale)
		_material.set_shader_parameter("chop_amplitude", _current_chop_amplitude)
		_material.set_shader_parameter("wave_speed", _current_wave_speed)
		_material.set_shader_parameter("wave_choppiness", wave_choppiness)
		_material.set_shader_parameter("wind_direction_deg", wind_direction_deg)
		_material.set_shader_parameter("wave_direction_jitter", wave_direction_jitter)
		_material.set_shader_parameter("chop_patchiness", chop_patchiness)
		_material.set_shader_parameter("domain_warp_amount", domain_warp_amount)
		_material.set_shader_parameter("domain_warp_scale", domain_warp_scale)
		_material.set_shader_parameter("domain_warp_speed", domain_warp_speed)

func _process(delta: float) -> void:
	_sim_time += delta
	_update_sea_state(delta)
	if _material == null:
		return
	_material.set_shader_parameter("sim_time", _sim_time)
	if enable_sea_state_variation:
		_material.set_shader_parameter("swell_amplitude", _current_swell_amplitude)
		_material.set_shader_parameter("chop_amplitude", _current_chop_amplitude)
		_material.set_shader_parameter("wave_speed", _current_wave_speed)

## Advances the sea state's slow noise phase and recomputes the current
## amplitude/speed multiplier. Deliberately fbm-driven rather than a sine
## wave — a sine gives a metronome-like calm/wild/calm/wild cycle; fbm
## gives irregular stretches of calm, then building, then wild, with no
## fixed period, which reads as much more natural.
func _update_sea_state(delta: float) -> void:
	if not enable_sea_state_variation:
		_current_swell_amplitude = swell_amplitude
		_current_chop_amplitude = chop_amplitude
		_current_wave_speed = wave_speed
		return

	_sea_state_phase += delta * sea_state_change_speed
	var raw: float = _fbm(Vector2(_sea_state_phase, 91.7))
	var state: float = clamp(raw / 0.9375, 0.0, 1.0) # fbm's theoretical max sum is 0.9375; renormalize to a full 0-1 range
	var mult: float = lerp(sea_state_min, sea_state_max, state)

	_current_swell_amplitude = swell_amplitude * mult
	_current_chop_amplitude = chop_amplitude * mult
	_current_wave_speed = wave_speed * lerp(1.0, mult, sea_state_speed_influence)

## Call this any time something touches the water: a hull cutting the
## surface, a shell/object splashing in, footsteps in shallows, etc.
## `world_pos` only needs x/z (world space) — y is ignored.
## `strength` roughly scales ring amplitude; 1.0 is a normal-sized disturbance.
func spawn_ripple(world_pos: Vector3, strength: float = 1.0) -> void:
	if _material == null:
		return
	var slot := _next_slot
	_next_slot = (_next_slot + 1) % MAX_RIPPLES
	_slot_pos[slot] = Vector2(world_pos.x, world_pos.z)
	_slot_time[slot] = _sim_time
	_slot_strength[slot] = strength
	_push_to_shader()

## Ripple-only vertical displacement at a world-space XZ point, in the same
## units as ripple_amplitude. Mirrors the shader's vertex-stage ripple loop
## (NOT the swell/chop waves, domain warp, or turbulence — see
## get_water_height_at() for the full surface height, which is what
## BuoyancySystem.gd actually samples). Kept as its own method for anything
## that only cares about interaction ripples specifically.
func get_ripple_height_at(world_xz: Vector2) -> float:
	var total := 0.0
	var sc: float = 1.0 / max(meters_per_unit, 0.001)
	var k: float = TAU / max(ripple_wavelength, 0.001)
	for i in MAX_RIPPLES:
		var strength: float = _slot_strength[i]
		if strength <= 0.0001:
			continue
		var age: float = _sim_time - _slot_time[i]
		if age < 0.0 or age > ripple_lifetime:
			continue
		var to_point: Vector2 = (world_xz - _slot_pos[i]) * sc
		var dist: float = to_point.length()
		var wavefront: float = age * ripple_speed
		var band: float = exp(-pow((dist - wavefront) / max(ripple_width, 0.001), 2.0))
		if band < 0.001:
			continue
		var decay: float = strength * (1.0 - age / ripple_lifetime)
		var phase: float = (dist - wavefront) * k
		total += sin(phase) * ripple_amplitude * decay * band
	return total

## Full water surface height (world-space Y offset from calm sea level) at
## a world-space XZ point: swell + chop Gerstner waves, domain warp,
## turbulence (if a biome sets it), and object-driven ripples — the same
## displacement the vertex shader applies, evaluated on the CPU. This is
## what BuoyancySystem.gd should sample; get_ripple_height_at() alone only
## covers interaction ripples, which is why floating objects were settling
## on a flat plane instead of riding the actual waves.
func get_water_height_at(world_xz: Vector2) -> float:
	var chop_mult := _blend_chop_mult(world_xz)
	var warped_pos := _domain_warp(world_xz, _sim_time)
	var wind_rad := deg_to_rad(wind_direction_deg)
	var height := _gerstner_height(warped_pos, _sim_time, wind_rad, chop_mult)
	height += _turbulence_height(warped_pos, _sim_time, chop_mult)
	height += get_ripple_height_at(world_xz)
	return height

func _push_to_shader() -> void:
	var data: Array[Vector4] = []
	for i in MAX_RIPPLES:
		data.append(Vector4(_slot_pos[i].x, _slot_pos[i].y, _slot_time[i], _slot_strength[i]))
	_material.set_shader_parameter("ripple_data", data)
	_material.set_shader_parameter("ripple_count", MAX_RIPPLES)

# ==================================================================
# Wave-field math ported from the shader (hash21 / value_noise / fbm /
# gerstner / domain warp / turbulence). Only the pieces needed for a
# height query are kept — horizontal (x/z) displacement, the Gerstner
# jacobian, and tangent/binormal (used by the shader for lighting only)
# are intentionally not reproduced here.
# ==================================================================

static func _fract(x: float) -> float:
	return x - floor(x)

static func _hash21(p: Vector2) -> float:
	var q := Vector2(_fract(p.x * 123.34), _fract(p.y * 456.21))
	var d: float = q.dot(q + Vector2(45.32, 45.32))
	q += Vector2(d, d)
	return _fract(q.x * q.y)

static func _value_noise(p: Vector2) -> float:
	var i := Vector2(floor(p.x), floor(p.y))
	var f := Vector2(_fract(p.x), _fract(p.y))
	var a := _hash21(i)
	var b := _hash21(i + Vector2(1.0, 0.0))
	var c := _hash21(i + Vector2(0.0, 1.0))
	var d := _hash21(i + Vector2(1.0, 1.0))
	var u := Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y)

static func _fbm(p: Vector2) -> float:
	var v := 0.0
	var amp := 0.5
	var pp := p
	for i in 4:
		v += amp * _value_noise(pp)
		pp *= 2.03
		amp *= 0.5
	return v

func _domain_warp(pos: Vector2, t: float) -> Vector2:
	var warp_seed: Vector2 = pos * domain_warp_scale
	var warp: Vector2 = Vector2(
		_fbm(warp_seed + Vector2(0.0, t * domain_warp_speed)),
		_fbm(warp_seed + Vector2(5.2, -t * domain_warp_speed))
	) - Vector2(0.5, 0.5)
	return pos + warp * domain_warp_amount

## Vertical (Y) component only of the shader's gerstner() function — the
## horizontal displacement, tangent/binormal, and jacobian are dropped
## since a height query doesn't need them.
func _gerstner_height(pos: Vector2, t: float, wind_rad: float, chop_mult: Vector4) -> float:
	var offset_y := 0.0

	var chop_patch: float = _fbm(pos * 0.015 + Vector2(4.0, 9.0))
	var chop_patch_mult: float = lerp(1.0 - chop_patchiness * 0.7, 1.0 + chop_patchiness * 0.7, chop_patch)

	for i in WAVE_COUNT:
		var wave_seed: float = float(i) * 17.17
		var jitter_deg: float = (_fbm(Vector2(wave_seed, t * 0.015)) - 0.5) * 2.0 * wave_direction_jitter
		var ang: float = deg_to_rad(WAVE_ANGLES[i] + jitter_deg) + wind_rad
		var dir := Vector2(cos(ang), sin(ang))

		var wavelength: float = WAVE_BASE_LENGTHS[i]
		var category_amp: float = _current_chop_amplitude
		var speed_mult_biome: float = 1.0

		if IS_SWELL[i]:
			wavelength *= swell_wavelength_scale
			category_amp = _current_swell_amplitude
			category_amp *= lerp(1.0, chop_mult.x, 0.35)
			speed_mult_biome = lerp(1.0, chop_mult.z, 0.35)
		else:
			wavelength /= max(chop_mult.y, 0.01)
			category_amp *= chop_patch_mult * chop_mult.x
			speed_mult_biome = chop_mult.z
		wavelength = max(wavelength, 0.5)

		var k: float = TAU / wavelength
		var c: float = sqrt(9.8 / k) * WAVE_SPEED_MULT[i] * speed_mult_biome
		var a: float = WAVE_AMP_SCALE[i] * category_amp
		var f: float = k * (dir.dot(pos) - c * t * _current_wave_speed)

		offset_y += a * sin(f)

	return offset_y

func _turbulence_height(warped_pos: Vector2, t: float, chop_mult: Vector4) -> float:
	if chop_mult.w <= 0.01:
		return 0.0
	var sc: float = 1.0 / max(meters_per_unit, 0.001)
	var turb_freq: Vector2 = Vector2(0.03, 0.03) * max(chop_mult.y, 0.01)
	var uv_t: Vector2 = warped_pos * sc * turb_freq + Vector2(t * 0.6, t * 0.45)
	var h_t: float = _fbm(uv_t) - 0.5
	var turb_height: float = _current_chop_amplitude * 1.5 * chop_mult.w
	return h_t * turb_height

## Blends biome_chop across whichever biomes (from WaterBiomeSystem.gd)
## overlap this XZ point — same soft-edged-circle blend the shader does.
## Reads biome_data/biome_chop/biome_count straight off this water's own
## shader material, so WaterManager doesn't need any reference to
## WaterBiomeSystem itself. Returns the neutral (1,1,1,0) multiplier if no
## biome uniforms have been set yet.
func _blend_chop_mult(pos_xz: Vector2) -> Vector4:
	var chop_mult := Vector4(1.0, 1.0, 1.0, 0.0)
	if _material == null:
		return chop_mult

	var count_variant = _material.get_shader_parameter("biome_count")
	var data_variant = _material.get_shader_parameter("biome_data")
	var chop_variant = _material.get_shader_parameter("biome_chop")
	if count_variant == null or data_variant == null or chop_variant == null:
		return chop_mult

	var biome_count: int = int(count_variant)
	var biome_data: Array = data_variant
	var biome_chop: Array = chop_variant
	var n: int = min(biome_count, min(biome_data.size(), biome_chop.size()))

	for i in n:
		var bd: Vector4 = biome_data[i]
		var center := Vector2(bd.x, bd.y)
		var radius: float = bd.z
		var blend: float = max(bd.w, 0.001)
		var dist: float = (pos_xz - center).length()
		var w: float = 1.0 - smoothstep(radius, radius + blend, dist)
		if w <= 0.001:
			continue
		chop_mult = chop_mult.lerp(biome_chop[i], w)

	return chop_mult
