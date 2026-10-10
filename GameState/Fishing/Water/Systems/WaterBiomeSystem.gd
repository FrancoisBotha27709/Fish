class_name WaterBiomeSystem
extends Node

const MAX := 8

@export var water_path: NodePath
@export var cloud_path: NodePath
@export var update_interval := 0.15

var _w: WaterManager
var _cloud: ShaderMaterial
var _t := 0.0

func _ready() -> void:
	_w = get_node_or_null(water_path) as WaterManager
	var c := get_node_or_null(cloud_path)
	if c is GeometryInstance3D:
		_cloud = c.material_override as ShaderMaterial
		if _cloud == null and c is MeshInstance3D and c.mesh:
			_cloud = c.mesh.surface_get_material(0) as ShaderMaterial
	_push()

func _process(dt: float) -> void:
	_t += dt
	if _t >= update_interval:
		_t = 0.0
		_push()

func _push() -> void:
	var bs := get_tree().get_nodes_in_group("water_biome")
	var n := mini(bs.size(), MAX)
	var data := PackedVector4Array()
	var chop := PackedVector4Array()
	var rip := PackedVector4Array()
	var look := PackedVector4Array()
	var tint := PackedVector4Array()
	var cloud := PackedVector4Array()
	for i in MAX:
		if i < n:
			var b: WaterBiome = bs[i]
			var p := b.global_position
			data.append(Vector4(p.x, p.z, b.radius, b.blend_distance))
			chop.append(Vector4(b.wave_height_mult, 1.0 / maxf(b.wave_length_mult, 0.01), b.wave_speed_mult, b.turbulence))
			rip.append(Vector4(b.ripple_speed_mult, b.ripple_wavelength_mult, b.ripple_amplitude_mult, 0.0))
			look.append(Vector4(b.tint_strength, b.foam_amount_mult, b.roughness_add, b.pollution))
			tint.append(Vector4(b.tint_color.r, b.tint_color.g, b.tint_color.b, 1.0))
			cloud.append(Vector4(b.cloud_density_mult, b.cloud_darken, b.cloud_turbulence, 0.0))
		else:
			data.append(Vector4.ZERO)
			chop.append(Vector4(1, 1, 1, 0))
			rip.append(Vector4(1, 1, 1, 0))
			look.append(Vector4(0, 1, 0, 0))
			tint.append(Vector4.ZERO)
			cloud.append(Vector4(1, 0, 0, 0))
	if _w:
		_w.set_biomes(n, data, chop, rip, look, tint)
	if _cloud:
		_cloud.set_shader_parameter("biome_count", n)
		_cloud.set_shader_parameter("biome_data", data)
		_cloud.set_shader_parameter("biome_cloud", cloud)
		_cloud.set_shader_parameter("biome_look", look)
		_cloud.set_shader_parameter("biome_tint", tint)
