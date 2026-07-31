extends MeshInstance3D
class_name WaterManager

const MAX_RIPPLES := 16

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

var _material: ShaderMaterial
var _slot_pos: Array[Vector2] = []
var _slot_time: Array[float] = []
var _slot_strength: Array[float] = []
var _next_slot := 0
var _sim_time := 0.0

func _ready() -> void:
	if material_override is ShaderMaterial:
		_material = material_override
	elif mesh and mesh.surface_get_material(0) is ShaderMaterial:
		_material = mesh.surface_get_material(0)

	if _material == null:
		push_warning("WaterManager: no ShaderMaterial found on this MeshInstance3D.")

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

func _process(delta: float) -> void:
	_sim_time += delta
	if _material == null:
		return
	_material.set_shader_parameter("sim_time", _sim_time)

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
## (NOT the cosmetic sub-centimeter ambient chop, which isn't worth
## replicating for physics). Used by BuoyancySystem.gd; the water itself
## never calls this.
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

func _push_to_shader() -> void:
	var data: Array[Vector4] = []
	for i in MAX_RIPPLES:
		data.append(Vector4(_slot_pos[i].x, _slot_pos[i].y, _slot_time[i], _slot_strength[i]))
	_material.set_shader_parameter("ripple_data", data)
	_material.set_shader_parameter("ripple_count", MAX_RIPPLES)
