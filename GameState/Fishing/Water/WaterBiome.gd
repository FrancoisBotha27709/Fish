extends Area3D
class_name WaterBiome
## Add this to an Area3D with a CollisionShape3D child (Sphere or Box work
## best) anywhere over the water. It's found automatically by
## WaterBiomeSystem.gd via the "water_biome" group — it never needs a
## reference to the water or to anything else.
##
## The collision shape is only used to get an approximate radius; biomes
## are treated as circles in the water's XZ plane, not exact shapes, and
## monitoring/collision detection is disabled since nothing needs to
## physically enter this area.
##
## Example presets:
##   Storm:      wave_height_mult 2.5, wave_length_mult 2.0, wave_speed_mult 0.8,
##               turbulence 0.3, tint_strength 0.4, tint_color dark grey-green,
##               foam_amount_mult 1.6, roughness_add 0.1
##   Cold ocean: wave_height_mult 1.2, wave_length_mult 0.8, wave_speed_mult 1.8,
##               turbulence 0.8, ripple_speed_mult 1.5, tint_strength 0.25,
##               tint_color pale steel blue

@export_group("Waves")
@export var wave_height_mult: float = 2.0    # >1 = bigger waves
@export var wave_length_mult: float = 1.8    # >1 = longer/broader waves
@export var wave_speed_mult: float = 1.0
@export var turbulence: float = 0.0          # 0 = smooth, >0 = extra chaotic chop layered on top ("wild" seas)

@export_group("Ripples")
@export var ripple_speed_mult: float = 1.0
@export var ripple_wavelength_mult: float = 1.0
@export var ripple_amplitude_mult: float = 1.0

@export_group("Look")
@export var tint_color: Color = Color(0.03, 0.05, 0.07, 1.0)
@export var tint_strength: float = 0.0       # 0 = no color change, 1 = fully tinted
@export var foam_amount_mult: float = 1.0
@export var roughness_add: float = 0.0

@export_group("Shape")
@export var blend_distance: float = 8.0      # meters of soft falloff at the biome's edge

func _ready() -> void:
	add_to_group("water_biome")
	monitoring = false
	monitorable = false
