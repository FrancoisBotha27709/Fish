extends Node3D

class_name FireSmoke

@export_group("Particles")

@export_subgroup("Smoke")
@export var particle_smoke: GPUParticles3D

## Fixed GPUParticles3D.amount for smoke. Set once, never changed at runtime.
## Size this comfortably above max_smoke_amount so there's headroom for the
## gating mechanism to work with (see class comment).
@export var smoke_pool_amount: int = 50:
	set = _set_smoke_pool_amount

@export var base_smoke_amount: float = 8.0
@export var max_smoke_amount: float = 80.0

## How fast the visible smoke density can change, in "amount units" per
## second. Higher = snappier response, lower = lazier/smoother. This is
## frame-rate independent (applied via move_toward(..., speed * delta)).
@export var smoke_smoothing: float = 25.0

## How often (seconds) an invisible/gated smoke particle re-checks whether
## it should become visible. Lower = snappier response to amount changes,
## higher = cheaper but laggier. Does not affect already-visible particles.
@export var smoke_gated_poll_interval: float = 0.15:
	set = _set_smoke_gated_poll_interval

## Fraction of the smoke pool that spawns as small wisps instead of big
## roiling puffs. 0 = all big puffs, 1 = all small wisps.
@export_range(0.0, 1.0) var smoke_small_particle_ratio: float = 0.4:
	set = _set_smoke_small_particle_ratio

@export_subgroup("Smoke Colors")
## Color of freshly-spawned smoke (young / low in the air).
@export var smoke_start_color: Color = Color(0.62, 0.62, 0.65):
	set = _set_smoke_start_color
## Color smoke fades to as it ages / rises (e.g. Color.WHITE for a
## black-to-white plume, Color.BLACK for smoke that darkens with age).
@export var smoke_end_color: Color = Color(0.05, 0.05, 0.06):
	set = _set_smoke_end_color
## Multiplies the final color -- quick global tint without touching the
## gradient itself. Leave at white for no change.
@export var smoke_overall_tint: Color = Color.WHITE:
	set = _set_smoke_overall_tint

@export_subgroup("Fire")
@export var particle_fire: GPUParticles3D

## Fixed GPUParticles3D.amount for fire. Set once, never changed at runtime.
@export var fire_pool_amount: int = 80:
	set = _set_fire_pool_amount

@export var base_fire_amount: float = 8.0
@export var max_fire_amount: float = 40.0

## How fast the visible fire intensity can change, in "amount units" per
## second. Frame-rate independent.
@export var fire_smoothing: float = 30.0

## How often (seconds) an invisible/gated fire particle re-checks whether
## it should become visible. Fire's short base lifetime already made this
## less severe than smoke's, but it's still tunable.
@export var fire_gated_poll_interval: float = 0.08:
	set = _set_fire_gated_poll_interval

## Fraction of the fire pool that spawns as small embers/sparks instead of
## full flame licks. 0.0 (default) disables the effect entirely -- fire
## behaves exactly like before unless you opt in.
@export_range(0.0, 1.0) var fire_ember_ratio: float = 0.0:
	set = _set_fire_ember_ratio

@export_subgroup("Fire Colors")
@export var fire_start_color: Color = Color(1.00, 0.97, 0.75):
	set = _set_fire_start_color
@export var fire_end_color: Color = Color(0.65, 0.10, 0.02):
	set = _set_fire_end_color
@export var fire_overall_tint: Color = Color.WHITE:
	set = _set_fire_overall_tint

var _smoke_current: float
var _smoke_target: float
var _fire_current: float
var _fire_target: float

var _smoke_material: ShaderMaterial
var _fire_material: ShaderMaterial

var _configured: bool = false


func _ready() -> void:
	_smoke_current = base_smoke_amount
	_smoke_target = base_smoke_amount
	_fire_current = base_fire_amount
	_fire_target = base_fire_amount

	_configure_particle_node(particle_smoke, smoke_pool_amount)
	_configure_particle_node(particle_fire, fire_pool_amount)
	_configured = true

	_smoke_material = _get_process_material(particle_smoke)
	_fire_material = _get_process_material(particle_fire)

	if max_smoke_amount > smoke_pool_amount:
		push_warning("FireSmoke: max_smoke_amount (%s) exceeds smoke_pool_amount (%s); intensity will clamp at 1.0 and you'll never reach the requested density. Raise smoke_pool_amount." % [max_smoke_amount, smoke_pool_amount])
	if max_fire_amount > fire_pool_amount:
		push_warning("FireSmoke: max_fire_amount (%s) exceeds fire_pool_amount (%s); intensity will clamp at 1.0. Raise fire_pool_amount." % [max_fire_amount, fire_pool_amount])

	if _smoke_material:
		_smoke_material.set_shader_parameter("small_particle_ratio", smoke_small_particle_ratio)
		_smoke_material.set_shader_parameter("gated_poll_interval", smoke_gated_poll_interval)
	if _fire_material:
		_fire_material.set_shader_parameter("ember_ratio", fire_ember_ratio)
		_fire_material.set_shader_parameter("gated_poll_interval", fire_gated_poll_interval)

	_apply_smoke_gradient()
	_apply_fire_gradient()
	_push_smoke_uniforms()
	_push_fire_uniforms()


func _process(delta: float) -> void:
	_smoke_current = move_toward(_smoke_current, _smoke_target, smoke_smoothing * delta)
	_fire_current = move_toward(_fire_current, _fire_target, fire_smoothing * delta)
	_push_smoke_uniforms()
	_push_fire_uniforms()


## ---- Setup helpers --------------------------------------------------------

func _configure_particle_node(p: GPUParticles3D, pool_amount: int) -> void:
	if p == null:
		return
	p.amount = pool_amount            # set ONCE here, never touched again
	#p.local_coords = false            # world-space simulation, required by these shaders
	#p.inherit_velocity_ratio = 1.0    # required for EMITTER_VELOCITY to populate in-shader
	#p.emitting = true


func _get_process_material(p: GPUParticles3D) -> ShaderMaterial:
	if p == null:
		return null
	var mat := p.process_material
	if mat is ShaderMaterial:
		return mat
	push_warning("FireSmoke: %s has no ShaderMaterial assigned as its process_material." % p.name)
	return null


func _push_smoke_uniforms() -> void:
	if _smoke_material == null:
		return
	var intensity = clamp(_smoke_current / float(max(smoke_pool_amount, 1)), 0.0, 1.0)
	_smoke_material.set_shader_parameter("emission_intensity", intensity)


func _push_fire_uniforms() -> void:
	if _fire_material == null:
		return
	var intensity = clamp(_fire_current / float(max(fire_pool_amount, 1)), 0.0, 1.0)
	_fire_material.set_shader_parameter("emission_intensity", intensity)


## ---- Pool amount guards (amount must never change after _ready) ----------

func _set_smoke_pool_amount(value: int) -> void:
	if _configured:
		push_error("FireSmoke: smoke_pool_amount cannot change at runtime (GPUParticles3D.amount must stay constant). Ignoring.")
		return
	smoke_pool_amount = value


func _set_fire_pool_amount(value: int) -> void:
	if _configured:
		push_error("FireSmoke: fire_pool_amount cannot change at runtime (GPUParticles3D.amount must stay constant). Ignoring.")
		return
	fire_pool_amount = value


func _set_smoke_small_particle_ratio(value: float) -> void:
	smoke_small_particle_ratio = clamp(value, 0.0, 1.0)
	if _smoke_material:
		_smoke_material.set_shader_parameter("small_particle_ratio", smoke_small_particle_ratio)


func _set_fire_ember_ratio(value: float) -> void:
	fire_ember_ratio = clamp(value, 0.0, 1.0)
	if _fire_material:
		_fire_material.set_shader_parameter("ember_ratio", fire_ember_ratio)


func _set_smoke_gated_poll_interval(value: float) -> void:
	smoke_gated_poll_interval = max(value, 0.01)
	if _smoke_material:
		_smoke_material.set_shader_parameter("gated_poll_interval", smoke_gated_poll_interval)


func _set_fire_gated_poll_interval(value: float) -> void:
	fire_gated_poll_interval = max(value, 0.01)
	if _fire_material:
		_fire_material.set_shader_parameter("gated_poll_interval", fire_gated_poll_interval)


## ---- Color helpers ---------------------------------------------------------
## Both draw shaders expose a 4-stop gradient (color_stop_0..3 for smoke,
## color_core/color_yellow/color_orange/color_deep for fire) plus timing
## uniforms (color_stop_1_pos etc.) that control WHERE along a particle's
## life/height each stop kicks in. These helpers only touch the color
## values themselves -- start/end plus two auto-interpolated midpoints --
## so you get a simple 2-color gradient without hand-editing all 4 stops.
## For full manual control over all 4 stops and their timing, use
## set_smoke_param() / set_fire_param() directly on the material.

func _apply_smoke_gradient() -> void:
	if _smoke_material == null:
		return
	var mid1 := smoke_start_color.lerp(smoke_end_color, 0.33)
	var mid2 := smoke_start_color.lerp(smoke_end_color, 0.66)
	_smoke_material.set_shader_parameter("color_stop_0", smoke_start_color)
	_smoke_material.set_shader_parameter("color_stop_1", mid1)
	_smoke_material.set_shader_parameter("color_stop_2", mid2)
	_smoke_material.set_shader_parameter("color_stop_3", smoke_end_color)
	_smoke_material.set_shader_parameter("overall_tint", smoke_overall_tint)


func _apply_fire_gradient() -> void:
	if _fire_material == null:
		return
	var mid1 := fire_start_color.lerp(fire_end_color, 0.33)
	var mid2 := fire_start_color.lerp(fire_end_color, 0.66)
	_fire_material.set_shader_parameter("color_core", fire_start_color)
	_fire_material.set_shader_parameter("color_yellow", mid1)
	_fire_material.set_shader_parameter("color_orange", mid2)
	_fire_material.set_shader_parameter("color_deep", fire_end_color)
	_fire_material.set_shader_parameter("overall_tint", fire_overall_tint)


func _set_smoke_start_color(value: Color) -> void:
	smoke_start_color = value
	_apply_smoke_gradient()


func _set_smoke_end_color(value: Color) -> void:
	smoke_end_color = value
	_apply_smoke_gradient()


func _set_smoke_overall_tint(value: Color) -> void:
	smoke_overall_tint = value
	_apply_smoke_gradient()


func _set_fire_start_color(value: Color) -> void:
	fire_start_color = value
	_apply_fire_gradient()


func _set_fire_end_color(value: Color) -> void:
	fire_end_color = value
	_apply_fire_gradient()


func _set_fire_overall_tint(value: Color) -> void:
	fire_overall_tint = value
	_apply_fire_gradient()


## Set the smoke gradient from code, e.g. set_smoke_colors(Color.BLACK, Color.WHITE)
## for smoke that starts black and fades to white as it ages.
func set_smoke_colors(start_color: Color, end_color: Color, overall_tint: Color = Color.WHITE) -> void:
	smoke_start_color = start_color
	smoke_end_color = end_color
	smoke_overall_tint = overall_tint
	_apply_smoke_gradient()


## Set the fire gradient from code.
func set_fire_colors(start_color: Color, end_color: Color, overall_tint: Color = Color.WHITE) -> void:
	fire_start_color = start_color
	fire_end_color = end_color
	fire_overall_tint = overall_tint
	_apply_fire_gradient()


## ---- Public API ------------------------------------------------------------

## Smoothly move the visible smoke density toward target_amount (in the same
## units as base_smoke_amount / max_smoke_amount, e.g. 8, 20, 40, 80...).
## Works for both increasing and decreasing -- direction is automatic.
func set_smoke_amount(target_amount: float) -> void:
	_smoke_target = clamp(target_amount, 0.0, max_smoke_amount)


## Smoothly move the visible fire intensity toward target_amount.
func set_fire_amount(target_amount: float) -> void:
	_fire_target = clamp(target_amount, 0.0, max_fire_amount)


func reset_smoke_to_base() -> void:
	set_smoke_amount(base_smoke_amount)


func reset_fire_to_base() -> void:
	set_fire_amount(base_fire_amount)


## Escape hatch: tweak any shader uniform on the smoke material at runtime
## without needing a dedicated export for it (individual gradient stops,
## wobble, taper, etc).
func set_smoke_param(param_name: StringName, value) -> void:
	if _smoke_material:
		_smoke_material.set_shader_parameter(param_name, value)


## Same escape hatch for fire.
func set_fire_param(param_name: StringName, value) -> void:
	if _fire_material:
		_fire_material.set_shader_parameter(param_name, value)


## ---- Back-compat wrappers ---------------------------------------------------
## The transition speed is now controlled by smoke_smoothing / fire_smoothing
## and applied continuously in _process(), not by the delta passed in here --
## `delta` is accepted only so old call sites keep compiling unchanged.

func increase_smoke(target_amount: float, _delta: float = 0.0) -> void:
	set_smoke_amount(target_amount)


func decrease_smoke(target_amount: float, _delta: float = 0.0) -> void:
	set_smoke_amount(target_amount)


func increase_fire(target_amount: float, _delta: float = 0.0) -> void:
	set_fire_amount(target_amount)


func decrease_fire(target_amount: float, _delta: float = 0.0) -> void:
	set_fire_amount(target_amount)
