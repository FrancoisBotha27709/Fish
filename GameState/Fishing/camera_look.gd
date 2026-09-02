extends Camera3D
class_name CameraLook

#region Exports



#region Look
@export_group("Photo Look")
@export_subgroup("Lens")
@export_range(1.0, 179.0, 0.1, "degrees") var field_of_view : float = 60.0:
	set(value):
		field_of_view = value
		fov = value

@export_range(0.001, 10.0, 0.001, "or_greater") var near_clip : float = 0.05:
	set(value):
		near_clip = value
		near = value

@export_range(10.0, 20000.0, 1.0, "or_greater") var far_clip : float = 4000.0:
	set(value):
		far_clip = value
		far = value

@export_subgroup("Exposure", "exposure_")
## f-stop. Lower = wider aperture = brighter image + shallower dof
@export_range(0.5, 32.0, 0.1) var exposure_aperture : float = 8.0:
	set(value):
		exposure_aperture = value
		_apply_attributes()

## In 1/x seconds. Higher = darker image, less motion blur
@export_range(1.0, 8000.0, 1.0) var exposure_shutter_speed : float = 100.0:
	set(value):
		exposure_shutter_speed = value
		_apply_attributes()

## Sensor Sensitivity. Higher = brighter but granier IRL
@export_range(6.0, 12800.0, 1.0) var exposure_iso : float = 100.0:
	set(value):
		exposure_iso = value
		_apply_attributes()

## Extra manual stop of exposure on top of physics calculation
@export_range(-8.0, 8.0, 0.05) var exposure_compensation : float = 0.0:
	set(value):
		exposure_compensation = value
		_apply_attributes()

## Calculate exposure automatically
@export var exposure_auto : bool = true:
	set(value):
		exposure_auto = value
		_apply_attributes()

## Auto exposure speed
@export_range(0.01, 4.0, 0.01) var exposure_auto_speed : float = 0.5:
	set(value):
		exposure_auto_speed = value
		_apply_attributes()

## Auto exposure scale
@export_range(0.01, 4.0, 0.01) var exposure_auto_scale : float = 0.4:
	set(value):
		exposure_auto_scale = value
		_apply_attributes()

@export_subgroup("Depth of Field", "dof_")
@export var dof_enabled : bool = true:
	set(value):
		dof_enabled = value
		_apply_dof()

## Distance in meters where the image is sharp
@export_range(0.1, 500.0, 0.1, "or_greater") var dof_focus_distance : float = 10.0:
	set(value):
		dof_focus_distance = value
		_apply_dof()

@export var dof_near_enabled : bool = false:
	set(value):
		dof_near_enabled = value
		_apply_dof()

@export_range(0.01, 100.0) var dof_near_transition : float = 1.0:
	set(value):
		dof_near_transition = value
		_apply_dof()

@export var dof_far_enabled : bool = true:
	set(value):
		dof_far_enabled = value
		_apply_dof()

@export_range(0.01, 100.0) var dof_far_transition : float = 1.0:
	set(value):
		dof_far_transition = value
		_apply_dof()

## Strength of blur (including near & far)
@export_range(0.0, 8.0, 0.01) var dof_blur_amount : float = 0.15:
	set(value):
		dof_blur_amount = value
		_apply_dof()
#endregion

#region Editing
@export_group("Editing")
@export_subgroup("Tonemapping", "tonemap_")

enum TonemapMode { LINEAR, REINHARD, FILMIC, ACES }
@export var tonemap_mode : TonemapMode = TonemapMode.ACES:
	set(value):
		tonemap_mode = value
		_apply_environment()

@export_range(0.0, 32.0, 0.01) var tonemap_white : float = 1.0:
	set(value):
		tonemap_white = value
		_apply_environment()

@export_subgroup("Color Grading", "grade_")
@export_range(0.0, 4.0, 0.01) var grade_brightness : float = 1.0:
	set(value):
		grade_brightness = value
		_apply_environment()

@export_range(0.0, 4.0, 0.01) var grade_contrast : float = 1.0:
	set(value):
		grade_contrast = value
		_apply_environment()

@export_range(0.0, 4.0, 0.01) var grade_saturation : float = 1.0:
	set(value):
		grade_saturation = value
		_apply_environment()

## -1 = cooler/blue, 0 = neutral, 1 = warmer/orange. Approximated with a
## channel tint since [Environment] has no negative while-balance slider

#endregion
#endregion

func _apply_attributes() -> void:
	pass

func _apply_dof() -> void:
	pass

func _apply_environment() -> void:
	pass

func change_fov(target_fov: float, delta: float) -> void:
	fov = move_toward(fov, target_fov, 40.0 * delta)