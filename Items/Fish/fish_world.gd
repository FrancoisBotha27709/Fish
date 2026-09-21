extends Node2D
# attach directly to the world_scene root

func _ready() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "rotation_degrees", 8.0, 0.25).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "rotation_degrees", -8.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "rotation_degrees", 0.0, 0.25).set_trans(Tween.TRANS_SINE)
