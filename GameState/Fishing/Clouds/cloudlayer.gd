@tool
class_name CloudLayer
extends MeshInstance3D
## A big flat world-space cloud plane, floating above the water, using
## clouds.gdshader. Unlike the old cloud layer baked into the sky shader,
## this one has a real world position - which is the whole point: it reads
## the same biome_data your water reads (via WaterBiomeSystem.gd's optional
## cloud_path), so a storm biome visibly thickens and darkens the clouds
## sitting above it.
##
## USAGE: add this node anywhere in the scene (it repositions itself every
## frame, so where you place it doesn't matter). Point atmosphere_path at
## your PollutedAtmosphere node so the clouds catch light from the same sun.
## Point WaterBiomeSystem's own cloud_path export at THIS node so biomes
## reach the clouds too.

@export var cloud_shader: Shader   ## Leave empty to auto-load clouds.gdshader from this script's folder.
@export var atmosphere_path: NodePath   ## Your PollutedAtmosphere node - optional, but without it the clouds use a fixed default sun.

@export_group("Placement")
@export_range(20.0, 2000.0) var altitude := 220.0:   ## world-space height (Y) of the cloud plane
	set(v): altitude = v; _reposition()
@export_range(200.0, 20000.0) var plane_size := 3000.0:   ## width/depth of the plane in world units - should comfortably outrun your draw distance
	set(v): plane_size = v; _rebuild_mesh()
@export var follow_camera := true   ## keeps the (effectively infinite) plane centered under the viewport camera every frame

@export_group("Clouds")
@export_range(0.0, 1.0) var cloud_coverage := 0.55:
	set(v): cloud_coverage = v; _apply()
@export_range(0.0, 2.0) var cloud_density := 1.0:
	set(v): cloud_density = v; _apply()
@export_range(0.0005, 0.05) var cloud_scale := 0.006:
	set(v): cloud_scale = v; _apply()
@export_range(0.0, 20.0) var cloud_speed := 2.5:
	set(v): cloud_speed = v; _apply()
@export_range(0.01, 0.5) var cloud_softness := 0.12:
	set(v): cloud_softness = v; _apply()
@export var cloud_top_color := Color(0.46, 0.44, 0.36):
	set(v): cloud_top_color = v; _apply()
@export var cloud_under_color := Color(0.09, 0.10, 0.09):
	set(v): cloud_under_color = v; _apply()
@export_range(0.0, 360.0) var wind_direction_deg := 30.0:   ## match your water's wind_direction_deg so clouds drift the same way as the sea
	set(v): wind_direction_deg = v; _apply()

@export_group("Fade")
@export_range(0.0, 4000.0) var fade_start := 500.0:
	set(v): fade_start = v; _apply()
@export_range(0.0, 8000.0) var fade_end := 1100.0:
	set(v): fade_end = v; _apply()

@export_group("Hatching")
## Same hatch_shadow.gdshaderinc pipeline as PollutedAtmosphere's sky - kept
## independent so the clouds can use a different style/scale than the smog.
@export_enum("Soft Relief", "Cross-Hatch", "Parallel Streaks", "Stipple") var hatch_style := 0:
	set(v): hatch_style = v; _apply()
@export_range(0.5, 400.0) var hatch_scale := 25.0:
	set(v): hatch_scale = v; _apply()
@export_range(0.0, 2.0) var hatch_strength := 1.0:
	set(v): hatch_strength = v; _apply()
@export_range(0.0, 180.0) var hatch_angle_deg := 45.0:
	set(v): hatch_angle_deg = v; _apply()
@export_range(0.5, 8.0) var hatch_sharpness := 3.0:
	set(v): hatch_sharpness = v; _apply()

var _mat: ShaderMaterial
var _atmosphere: Node


func _ready() -> void:
	# Read the camera position AFTER other _process-driven movement/camera
	# scripts have run this frame (Node.process_priority: lower runs first,
	# so a high number here runs last). Without this, if something else
	# moves the camera in _process (rather than _physics_process) and
	# happens to run after this node in the scene tree, this plane would
	# follow one frame late - a small, constant lag that reads as jitter
	# exactly when the camera is moving.
	process_priority = 4096

	if cloud_shader == null:
		var dir: String = (get_script() as Script).resource_path.get_base_dir()
		cloud_shader = load(dir.path_join("clouds.gdshader")) as Shader
	if cloud_shader == null:
		push_warning("CloudLayer: clouds.gdshader not found next to this script - assign cloud_shader.")
		return

	_mat = ShaderMaterial.new()
	_mat.shader = cloud_shader
	material_override = _mat

	if not atmosphere_path.is_empty():
		_atmosphere = get_node_or_null(atmosphere_path)
		if _atmosphere == null:
			push_warning("CloudLayer: atmosphere_path is set but invalid.")

	_rebuild_mesh()
	_reposition()
	_apply()


func _process(_delta: float) -> void:
	if not is_instance_valid(_mat):
		return
	if follow_camera and not Engine.is_editor_hint():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			global_position = Vector3(cam.global_position.x, altitude, cam.global_position.z)
	_push_sun()


func _rebuild_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(plane_size, plane_size)
	mesh = plane


func _reposition() -> void:
	# In the editor (or with follow_camera off) we don't have a gameplay
	# camera to chase, so just pin the altitude and leave X/Z wherever the
	# node was placed.
	if not follow_camera or Engine.is_editor_hint():
		global_position.y = altitude


func _apply() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("cloud_coverage", cloud_coverage)
	_mat.set_shader_parameter("cloud_density", cloud_density)
	_mat.set_shader_parameter("cloud_scale", cloud_scale)
	_mat.set_shader_parameter("cloud_speed", cloud_speed)
	_mat.set_shader_parameter("cloud_softness", cloud_softness)
	_mat.set_shader_parameter("cloud_top_color", cloud_top_color)
	_mat.set_shader_parameter("cloud_under_color", cloud_under_color)
	_mat.set_shader_parameter("wind_direction_deg", wind_direction_deg)
	_mat.set_shader_parameter("fade_start", fade_start)
	_mat.set_shader_parameter("fade_end", fade_end)
	_mat.set_shader_parameter("hatch_style", hatch_style)
	_mat.set_shader_parameter("hatch_scale", hatch_scale)
	_mat.set_shader_parameter("hatch_strength", hatch_strength)
	_mat.set_shader_parameter("hatch_angle_deg", hatch_angle_deg)
	_mat.set_shader_parameter("hatch_sharpness", hatch_sharpness)


## Pulls sun_elevation_deg/sun_azimuth_deg/sun_color/sun_energy straight off
## PollutedAtmosphere's own exported values (via its get_sun_direction()
## helper) rather than hunting for the DirectionalLight3D node it builds -
## keeps this script decoupled from PollutedAtmosphere's internals.
func _push_sun() -> void:
	if _mat == null or _atmosphere == null:
		return
	if _atmosphere.has_method("get_sun_direction"):
		_mat.set_shader_parameter("sun_direction", _atmosphere.get_sun_direction())
	if "sun_color" in _atmosphere:
		_mat.set_shader_parameter("sun_color", _atmosphere.sun_color)
	if "sun_energy" in _atmosphere:
		_mat.set_shader_parameter("sun_energy", _atmosphere.sun_energy)