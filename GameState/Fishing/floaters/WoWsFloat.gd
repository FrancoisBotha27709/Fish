extends Node3D

@export var stick_to_surface := false
@export var float_weight := 10.0
@export var tilt_multiplier := 0.0
@export var wake_strength := -1.0
@export var splash_strength := -1.0

func _ready() -> void:
	var b: Node3D = get_parent() as Node3D
	if b == null:
		b = self
	b.add_to_group("floating")
	b.set_meta("float_weight", float_weight)
	b.set_meta("stick_to_surface", stick_to_surface)
	if tilt_multiplier > 0.0:
		b.set_meta("tilt_multiplier", tilt_multiplier)
	if wake_strength >= 0.0:
		b.set_meta("wake_strength", wake_strength)
	if splash_strength >= 0.0:
		b.set_meta("splash_strength", splash_strength)
