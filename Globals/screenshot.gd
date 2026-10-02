extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if OS.is_debug_build() and Input.is_action_just_pressed("screenshot"):
		_take_screenshot()

func _take_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(UtilityStates.img_save_path)

	var img := get_viewport().get_texture().get_image()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file_path := UtilityStates.img_save_path + "screenshot_%s.png" % timestamp

	var err := img.save_png(file_path)

	if err != OK:
		push_error("Screenshot failed: %s" % error_string(err))
	else:
		print("Saved screenshot to: %s" % ProjectSettings.globalize_path(file_path))