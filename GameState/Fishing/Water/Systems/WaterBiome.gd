class_name WaterBiome
extends Area3D

@export_group("Waves")
@export var wave_height_mult := 2.0
@export var wave_length_mult := 1.8
@export var wave_speed_mult := 1.0
@export var turbulence := 0.0

@export_group("Ripples")
@export var ripple_speed_mult := 1.0
@export var ripple_wavelength_mult := 1.0
@export var ripple_amplitude_mult := 1.0

@export_group("Look")
@export var tint_color := Color(0.03, 0.05, 0.07)
@export var tint_strength := 0.0
@export var foam_amount_mult := 1.0
@export var roughness_add := 0.0
@export_range(0.0, 1.0) var pollution := 0.0

@export_group("Clouds")
@export var cloud_density_mult := 1.0
@export_range(0.0, 1.0) var cloud_darken := 0.0
@export_range(0.0, 1.0) var cloud_turbulence := 0.0

@export_group("Shape")
@export var blend_distance := 8.0

var radius := 10.0

func _ready() -> void:
	add_to_group("water_biome")
	monitoring = false
	monitorable = false
	for c in get_children():
		if c is CollisionShape3D and c.shape:
			var s = c.shape
			var k := maxf(c.scale.x, c.scale.z)
			if s is BoxShape3D:
				radius = maxf(s.size.x, s.size.z) * 0.5 * k
			elif "radius" in s:
				radius = s.radius * k
			break
