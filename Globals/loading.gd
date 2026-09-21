extends Node2D

@export var progress_bar : ProgressBar

@export var next_scene_path : String = "res://GameState/Fishing/Fising.tscn"
var progress : Array[float] = []

func _ready() -> void:
	ResourceLoader.load_threaded_request(next_scene_path)

func _process(delta: float) -> void:
	var status = ResourceLoader.load_threaded_get_status(next_scene_path, progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var pct = progress[0] * 100
			progress_bar.value = pct
		ResourceLoader.THREAD_LOAD_LOADED:
			var scene = ResourceLoader.load_threaded_get(next_scene_path)
			get_tree().change_scene_to_file(next_scene_path)