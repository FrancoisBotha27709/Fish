extends Control


@export var leave_btn : Button

func _ready() -> void:
	leave_btn.pressed.connect(_on_end_night_btn_pressed)

func _on_end_night_btn_pressed() -> void:
	# Time set night
	get_tree().change_scene_to_file("res://GameState/Market/game.tscn")
