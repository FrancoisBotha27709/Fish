extends Node

var pending_scene_path: String = ""

func goto_scene(path: String) -> void:
    pending_scene_path = path
    get_tree().change_scene_to_file("res://GameState/loading.tscn")