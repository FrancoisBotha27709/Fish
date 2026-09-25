extends MeshInstance3D
class_name WaterManager

const MAX_RIPPLES := 16
const JITTER_RATE := 0.002      # must match the shader
const HEIGHT_ITERATIONS := 3    # inverts the horizontal Gerstner shift; 2 is fine if you need speed

@export var follow_target: Node3D   # optional: water plane follows this, snapped to the vertex grid

@export var ripple_lifetime: float = 5.0
@export var ripple_speed: float = 4.0
@export var ripple_wavelength: float = 1.5
@export var ripple_width: float = 3.0
@export var ripple_amplitude: float = 0.4
@export var meters_per_unit: float = 1.0

@export_group("Waves")
@export var swell_amplitude: float = 1.2
@export var swell_wavelength_scale: float = 0.5
@export var chop_amplitude: float = 0.6
@export var wave_speed: float = 1.0
@export var wave_choppiness: float = 0.6
@export var wind_direction_deg: float = 30.0
@export var wave_direction_jitter: float = 12.0
@export var chop_patchiness: float = 0.5
@export var mesh_vertex_spacing: float = 1.25   # keep equal to your mesh's real spacing

@export_group("Large Scale Variation")
@export var domain_warp_amount: float = 15.0
@export var domain_warp_scale: float = 0.004
@export var domain_warp_speed: float = 0.02

@export_group("Sea State (Temporal Variation)")
@export var enable_sea_state_variation: bool = true
@export var sea_state_min: float = 0.6
@export var sea_state_max: float = 1.0
@export var sea_state_period: float = 120.0
@export var sea_state_jitter: float = 0.15
@export var sea_state_speed_influence: float = 0.15

const WAVE_COUNT := 6
const IS_SWELL: Array[bool] = [true, true, false, false, false, false]
const WAVE_ANGLES: Array[float] = [0.0, 24.0, 61.0, -37.0, 104.0, -73.0]
const WAVE_BASE_LENGTHS: Array[float] = [85.0, 52.0, 22.0, 13.0, 6.0, 3.2]
const WAVE_STEEPNESS: Array[float] = [0.8, 0.7, 0.45, 0.35, 0.22, 0.14]
const WAVE_AMP_SCALE: Array[float] = [1.0, 0.6, 0.32, 0.2, 0.1, 0.05]
const WAVE_SPEED_MULT: Array[float] = [0.9, 1.05, 1.3, 1.5, 1.9, 2.2]

var _material: ShaderMaterial
var _slot_pos: Array[Vector2] = []
var _slot_time: Array[float] = []
var _slot_strength: Array[float] = []
var _next_slot := 0
var _sim_time := 0.0      # ripples, pollution drift
var _wave_clock := 0.0    # waves, warp, turbulence (speed-integrated)
var _sea_state_phase := 0.0
var _cur_swell: float
var _cur_chop: float
var _cur_speed: float
var _dirs: Array[Vector2] = []
var _b_n := 0
var _b_data = null
var _b_chop = null
var _b_rip = null

func _ready() -> void:
	if material_override is ShaderMaterial:
		_material = material_override
	elif mesh and mesh.surface_get_material(0) is ShaderMaterial:
		_material = mesh.surface_get_material(0)
	if _material == null:
		push_warning("WaterManager: no ShaderMaterial found on this MeshInstance3D.")

	_cur_swell = swell_amplitude
	_cur_chop = chop_amplitude
	_cur_speed = wave_speed
	_slot_pos.resize(MAX_RIPPLES)
	_slot_time.resize(MAX_RIPPLES)
	_slot_strength.resize(MAX_RIPPLES)
	for i in MAX_RIPPLES:
		_slot_pos[i] = Vector2.ZERO
		_slot_time[i] = -1000.0
		_slot_strength[i] = 0.0
	_dirs.resize(WAVE_COUNT)
	_refresh_dirs()

	if _material:
		var p := {
			"ripple_lifetime": ripple_lifetime, "ripple_speed": ripple_speed,
			"ripple_wavelength": ripple_wavelength, "ripple_width": ripple_width,
			"ripple_amplitude": ripple_amplitude, "meters_per_unit": meters_per_unit,
			"swell_amplitude": _cur_swell, "swell_wavelength_scale": swell_wavelength_scale,
			"chop_amplitude": _cur_chop, "wave_choppiness": wave_choppiness,
			"wind_direction_deg": wind_direction_deg, "wave_direction_jitter": wave_direction_jitter,
			"chop_patchiness": chop_patchiness, "domain_warp_amount": domain_warp_amount,
			"domain_warp_scale": domain_warp_scale, "domain_warp_speed": domain_warp_speed,
			"mesh_vertex_spacing": mesh_vertex_spacing,
		}
		for k in p:
			_material.set_shader_parameter(k, p[k])

func _process(delta: float) -> void:
	_sim_time += delta
	_update_sea_state(delta)
	_wave_clock += delta * _cur_speed   # speed changes only affect the future, never scrub the past
	_refresh_dirs()
	_refresh_biomes()
	if follow_target:
		global_position.x = snappedf(follow_target.global_position.x, mesh_vertex_spacing)
		global_position.z = snappedf(follow_target.global_position.z, mesh_vertex_spacing)
	if _material == null:
		return
	_material.set_shader_parameter("sim_time", _sim_time)
	_material.set_shader_parameter("wave_time", _wave_clock)
	_material.set_shader_parameter("swell_amplitude", _cur_swell)
	_material.set_shader_parameter("chop_amplitude", _cur_chop)

func _update_sea_state(delta: float) -> void:
	if not enable_sea_state_variation:
		_cur_swell = swell_amplitude
		_cur_chop = chop_amplitude
		_cur_speed = wave_speed
		return
	_sea_state_phase += delta * TAU / max(sea_state_period, 1.0)
	var wave: float = 0.5 + 0.5 * sin(_sea_state_phase)
	var jitter: float = clamp(_fbm(Vector2(_sea_state_phase * 0.15, 91.7)) / 0.9375, 0.0, 1.0)
	var state: float = clamp(lerp(wave, jitter, sea_state_jitter), 0.0, 1.0)
	var mult: float = lerp(sea_state_min, sea_state_max, state)
	_cur_swell = swell_amplitude * mult
	_cur_chop = chop_amplitude * mult
	_cur_speed = wave_speed * lerp(1.0, mult, sea_state_speed_influence)

# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------
func spawn_ripple(world_pos: Vector3, strength: float = 1.0) -> void:
	if _material == null:
		return
	var slot := _next_slot
	_next_slot = (_next_slot + 1) % MAX_RIPPLES
	_slot_pos[slot] = Vector2(world_pos.x, world_pos.z)
	_slot_time[slot] = _sim_time
	_slot_strength[slot] = strength
	_push_to_shader()

## Height offset from calm sea level at a world XZ point. Matches the rendered surface.
func get_water_height_at(world_xz: Vector2) -> float:
	var p := world_xz
	var m: Array
	var o := Vector3.ZERO
	var wp := Vector2.ZERO
	for i in HEIGHT_ITERATIONS:
		m = _biomes_at(p)
		wp = _domain_warp(p)
		o = _gerstner(wp, m[0])
		if i < HEIGHT_ITERATIONS - 1:
			p = world_xz - Vector2(o.x, o.z)   # rest position whose displaced vertex lands on world_xz
	return o.y + _turbulence(wp, m[0]) + _ripple_h(p, m[1])

## Absolute world-space Y of the water surface.
func get_water_world_y(world_pos: Vector3) -> float:
	return global_position.y + get_water_height_at(Vector2(world_pos.x, world_pos.z))

## Surface normal (world space) via central differences. Use for aligning hulls.
func get_water_normal_at(world_xz: Vector2, e: float = 1.0) -> Vector3:
	var hx := get_water_height_at(world_xz + Vector2(e, 0)) - get_water_height_at(world_xz - Vector2(e, 0))
	var hz := get_water_height_at(world_xz + Vector2(0, e)) - get_water_height_at(world_xz - Vector2(0, e))
	return Vector3(-hx, 2.0 * e, -hz).normalized()

func get_ripple_height_at(world_xz: Vector2) -> float:
	return _ripple_h(world_xz, Vector4(1, 1, 1, 0))

func _push_to_shader() -> void:
	var data: Array[Vector4] = []
	for i in MAX_RIPPLES:
		data.append(Vector4(_slot_pos[i].x, _slot_pos[i].y, _slot_time[i], _slot_strength[i]))
	_material.set_shader_parameter("ripple_data", data)
	_material.set_shader_parameter("ripple_count", MAX_RIPPLES)

# ------------------------------------------------------------------
# Wave math (mirrors the shader)
# ------------------------------------------------------------------
func _refresh_dirs() -> void:
	var wind := deg_to_rad(wind_direction_deg)
	for i in WAVE_COUNT:
		var jit: float = (_fbm(Vector2(float(i) * 17.17, _wave_clock * JITTER_RATE)) - 0.5) * 2.0 * wave_direction_jitter
		var ang: float = deg_to_rad(WAVE_ANGLES[i] + jit) + wind
		_dirs[i] = Vector2(cos(ang), sin(ang))

func _refresh_biomes() -> void:
	_b_n = 0
	if _material == null:
		return
	var cnt = _material.get_shader_parameter("biome_count")
	_b_data = _material.get_shader_parameter("biome_data")
	_b_chop = _material.get_shader_parameter("biome_chop")
	_b_rip = _material.get_shader_parameter("biome_ripple")
	if cnt == null or _b_data == null or _b_chop == null:
		return
	_b_n = int(min(int(cnt), min(_b_data.size(), _b_chop.size())))

## Returns [chop_mult, ripple_mult] blended at pos (same soft circles as the shader).
func _biomes_at(pos: Vector2) -> Array:
	var chop := Vector4(1, 1, 1, 0)
	var rip := Vector4(1, 1, 1, 0)
	for i in _b_n:
		var bd: Vector4 = _b_data[i]
		var w: float = 1.0 - smoothstep(bd.z, bd.z + max(bd.w, 0.001), pos.distance_to(Vector2(bd.x, bd.y)))
		if w <= 0.001:
			continue
		chop = chop.lerp(_b_chop[i], w)
		if _b_rip != null and i < _b_rip.size():
			rip = rip.lerp(_b_rip[i], w)
	return [chop, rip]

func _domain_warp(pos: Vector2) -> Vector2:
	var s := pos * domain_warp_scale
	var t := _wave_clock * domain_warp_speed
	var w := Vector2(_fbm(s + Vector2(0.0, t)), _fbm(s + Vector2(5.2, -t))) - Vector2(0.5, 0.5)
	return pos + w * domain_warp_amount

## Full Gerstner displacement: x/z horizontal shift, y height.
func _gerstner(wp: Vector2, cm: Vector4) -> Vector3:
	var cp: float = _fbm(wp * 0.015 + Vector2(4.0, 9.0))
	var pm: float = lerp(1.0 - chop_patchiness * 0.7, 1.0 + chop_patchiness * 0.7, cp)
	var o := Vector3.ZERO
	for i in WAVE_COUNT:
		var wl: float
		var amp: float
		var spd: float
		if IS_SWELL[i]:
			wl = max(WAVE_BASE_LENGTHS[i] * swell_wavelength_scale, 0.5)
			amp = _cur_swell * lerp(1.0, cm.x, 0.35)
			spd = lerp(1.0, cm.z, 0.35)
		else:
			wl = max(WAVE_BASE_LENGTHS[i] / max(cm.y, 0.01), 0.5)
			amp = _cur_chop * pm * cm.x
			spd = cm.z
		amp *= smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, wl)
		var k: float = TAU / wl
		var c: float = sqrt(9.8 / k) * WAVE_SPEED_MULT[i] * spd
		var a: float = WAVE_AMP_SCALE[i] * amp
		var st: float = WAVE_STEEPNESS[i] * wave_choppiness
		var dir: Vector2 = _dirs[i]
		var f: float = k * (dir.dot(wp) - c * _wave_clock)
		var co := cos(f)
		o.x += st * a * dir.x * co
		o.z += st * a * dir.y * co
		o.y += a * sin(f)
	return o

func _turbulence(wp: Vector2, cm: Vector4) -> float:
	if cm.w <= 0.01:
		return 0.0
	var sc: float = 1.0 / max(meters_per_unit, 0.001)
	var tf: float = 0.03 * max(cm.y, 0.01)
	var uv := wp * sc * tf + Vector2(_wave_clock * 0.6, _wave_clock * 0.45)
	var fade: float = smoothstep(mesh_vertex_spacing * 2.0, mesh_vertex_spacing * 3.5, 1.0 / max(tf, 0.0001) / sc)
	return (_fbm(uv) - 0.5) * _cur_chop * 1.5 * cm.w * fade

func _ripple_env(age: float) -> float:
	var u: float = clamp(age / max(ripple_lifetime, 0.001), 0.0, 1.0)
	return smoothstep(0.0, 0.15, age) * (1.0 - u * u * (3.0 - 2.0 * u))

func _ripple_h(pos: Vector2, rm: Vector4) -> float:
	var total := 0.0
	var sc: float = 1.0 / max(meters_per_unit, 0.001)
	var spd: float = ripple_speed * rm.x
	var k: float = TAU / max(ripple_wavelength * rm.y, mesh_vertex_spacing * 3.5)
	var w0: float = max(ripple_width, mesh_vertex_spacing * 2.0)
	for i in MAX_RIPPLES:
		var s: float = _slot_strength[i]
		if s <= 0.0001:
			continue
		var age: float = _sim_time - _slot_time[i]
		if age < 0.0 or age > ripple_lifetime:
			continue
		var dist: float = ((pos - _slot_pos[i]) * sc).length()
		var front: float = age * spd
		var bx: float = (dist - front) / (w0 * (1.0 + age * 0.25))
		var band: float = exp(-bx * bx)
		if band < 0.001:
			continue
		var decay: float = s * _ripple_env(age) / sqrt(1.0 + front * 0.5)
		total += sin((dist - front) * k) * ripple_amplitude * rm.z * decay * band
	return total

# ------------------------------------------------------------------
# Noise (must match the shader's hash21 / value_noise / fbm)
# ------------------------------------------------------------------
static func _fract(x: float) -> float:
	return x - floor(x)

static func _hash21(p: Vector2) -> float:
	var m := Vector2(fposmod(p.x, 289.0), fposmod(p.y, 289.0))
	var p3 := Vector3(_fract(m.x * 0.1031), _fract(m.y * 0.1031), _fract(m.x * 0.1031))
	var d: float = p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3(33.33, 33.33, 33.33))
	p3 += Vector3(d, d, d)
	return _fract((p3.x + p3.y) * p3.z)

static func _value_noise(p: Vector2) -> float:
	var i := Vector2(floor(p.x), floor(p.y))
	var f := Vector2(_fract(p.x), _fract(p.y))
	var u := Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	return lerp(lerp(_hash21(i), _hash21(i + Vector2(1, 0)), u.x),
			lerp(_hash21(i + Vector2(0, 1)), _hash21(i + Vector2(1, 1)), u.x), u.y)

static func _fbm(p: Vector2) -> float:
	var v := 0.0
	var amp := 0.5
	for i in 4:
		v += amp * _value_noise(p)
		p *= 2.03
		amp *= 0.5
	return v