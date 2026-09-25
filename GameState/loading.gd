extends Node2D
class_name LoadingScene

@export var progress_bar: ProgressBar
@export var next_scene_path: String = "res://GameState/Fishing/Fising.tscn"

var progress: Array[float] = []

func _ready() -> void:
    progress_bar.visible = false
    if SceneLoader.pending_scene_path != "":
        next_scene_path = SceneLoader.pending_scene_path
    SignalBus.prepared_load.connect(_on_prepared_load, CONNECT_ONE_SHOT)
    SignalBus.loading_started.emit()
    ResourceLoader.load_threaded_request(next_scene_path)

func _on_prepared_load() -> void:
    progress_bar.visible = true

func _process(_delta: float) -> void:
    var status = ResourceLoader.load_threaded_get_status(next_scene_path, progress)
    match status:
        ResourceLoader.THREAD_LOAD_IN_PROGRESS:
            progress_bar.value = progress[0] * 100
        ResourceLoader.THREAD_LOAD_LOADED:
            set_process(false)
            var scene: PackedScene = ResourceLoader.load_threaded_get(next_scene_path)
            SignalBus.loaded.emit(true)
            get_tree().change_scene_to_packed(scene)
        ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
            set_process(false)
            printerr("Loading failed for '%s'" % next_scene_path)
            SignalBus.loaded.emit(false)