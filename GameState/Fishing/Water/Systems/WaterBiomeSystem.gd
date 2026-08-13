extends Node
class_name WaterBiomeSystem
## Place one of these in the scene and point water_path at the water
## MeshInstance3D (running WaterManager.gd). It finds biomes purely via
## the "water_biome" group (WaterBiome.gd) — biomes never reference this
## node or the water, and the water never references biomes directly.
##
## Biomes are static most of the time, so this only re-reads and pushes
## their data every `update_interval` seconds rather than every frame —
## if you later want a storm that visibly moves, just move its Area3D
## (e.g. from another script) and it'll pick up the new position on the
## next push, no other changes needed.

const MAX_BIOMES := 8

@export var water_path: NodePath
@export var update_interval: float = 0.15

var _material: ShaderMaterial
var _timer := 0.0

func _ready() -> void:
	var water := get_node_or_null(water_path)
	if water == null:
		push_warning("WaterBiomeSystem: water_path is not set or invalid.")
		return
	if water.material_override is ShaderMaterial:
		_material = water.material_override
	elif water is MeshInstance3D and water.mesh and water.mesh.surface_get_material(0) is ShaderMaterial:
		_material = water.mesh.surface_get_material(0)
	if _material == null:
		push_warning("WaterBiomeSystem: couldn't find a ShaderMaterial on the water node.")
	_push_biomes() # push once immediately so biomes are active before the first interval elapses

func _process(delta: float) -> void:
	_timer += delta
	if _timer < update_interval:
		return
	_timer = 0.0
	_push_biomes()

func _push_biomes() -> void:
	if _material == null:
		return

	var biomes := get_tree().get_nodes_in_group("water_biome")
	var count: int = min(biomes.size(), MAX_BIOMES)

	var biome_data: Array[Vector4] = []
	var biome_chop: Array[Vector4] = []
	var biome_ripple: Array[Vector4] = []
	var biome_look: Array[Vector4] = []
	var biome_tint: Array[Vector4] = []

	for i in MAX_BIOMES:
		if i < count:
			var b: Area3D = biomes[i]
			var center: Vector3 = b.global_position
			var radius := _get_radius(b)
			biome_data.append(Vector4(center.x, center.z, radius, b.blend_distance))
			biome_chop.append(Vector4(
				b.wave_height_mult,
				1.0 / max(b.wave_length_mult, 0.01),
				b.wave_speed_mult,
				b.turbulence
			))
			biome_ripple.append(Vector4(b.ripple_speed_mult, b.ripple_wavelength_mult, b.ripple_amplitude_mult, 0.0))
			biome_look.append(Vector4(b.tint_strength, b.foam_amount_mult, b.roughness_add, 0.0))
			biome_tint.append(Vector4(b.tint_color.r, b.tint_color.g, b.tint_color.b, 1.0))
		else:
			# neutral filler so unused slots have no effect
			biome_data.append(Vector4.ZERO)
			biome_chop.append(Vector4(1.0, 1.0, 1.0, 0.0))
			biome_ripple.append(Vector4(1.0, 1.0, 1.0, 0.0))
			biome_look.append(Vector4(0.0, 1.0, 0.0, 0.0))
			biome_tint.append(Vector4.ZERO)

	_material.set_shader_parameter("biome_count", count)
	_material.set_shader_parameter("biome_data", biome_data)
	_material.set_shader_parameter("biome_chop", biome_chop)
	_material.set_shader_parameter("biome_ripple", biome_ripple)
	_material.set_shader_parameter("biome_look", biome_look)
	_material.set_shader_parameter("biome_tint", biome_tint)

func _get_radius(area: Area3D) -> float:
	for child in area.get_children():
		if child is CollisionShape3D and child.shape:
			var shape = child.shape
			var s: float = maxf(child.scale.x, child.scale.z)
			if shape is SphereShape3D:
				return shape.radius * s
			if shape is BoxShape3D:
				return max(shape.size.x, shape.size.z) * 0.5 * s
			if shape is CylinderShape3D:
				return shape.radius * s
			if shape is CapsuleShape3D:
				return shape.radius * s
	return 10.0 # fallback if no recognizable shape is found
