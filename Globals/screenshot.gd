extends Node

# --- Tweak these ---
const RESOLUTION := Vector2i(2048, 2048)       # render size (square works for icons)
const VIEW_DIRECTION := Vector3(1.0, 0.35, 1.0) # direction FROM the item TO the camera
const FOV := 30.0                               # lower = flatter/more "product shot"
const FIT_PADDING := 1.1                        # >1 = more space around the item
const CROP_MARGIN := 24                         # px kept around item after auto-crop
const AUTO_CROP := true                         # trim empty transparent space
const MSAA := Viewport.MSAA_8X


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func take_screenshot(item: MeshInstance3D) -> void:
	if not OS.is_debug_build() or item == null:
		return

	# --- Isolated viewport with its own world and transparent background ---
	var vp := SubViewport.new()
	vp.size = RESOLUTION
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = MSAA
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)

	# --- Environment: no sky, soft ambient light ---
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR   # stays transparent
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)

	# --- Three-point lighting ---
	_add_light(vp, Vector3(-40, -35, 0), 1.2, Color(1.0, 0.97, 0.92))   # key
	_add_light(vp, Vector3(-15, 140, 0), 0.5, Color(0.8, 0.88, 1.0))    # fill
	_add_light(vp, Vector3(30, 200, 0), 0.8, Color(1, 1, 1))            # rim (back light)

	# --- Copy of the item, centered at origin, keeping its rotation/scale ---
	var copy: MeshInstance3D = item.duplicate()
	vp.add_child(copy)
	copy.visible = true
	copy.global_transform = Transform3D(item.global_transform.basis, Vector3.ZERO)

	# --- Auto-frame the camera using the mesh bounds ---
	var aabb: AABB = copy.global_transform * copy.get_aabb()
	var center := aabb.get_center()
	var radius := aabb.size.length() * 0.5
	var distance := radius / sin(deg_to_rad(FOV * 0.5)) * FIT_PADDING

	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.01
	cam.far = distance + radius * 4.0
	vp.add_child(cam)
	cam.look_at_from_position(center + VIEW_DIRECTION.normalized() * distance, center, Vector3.UP)
	cam.current = true

	# --- Wait for the render to finish ---
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()

	# --- Trim empty transparent space ---
	if AUTO_CROP:
		var rect := img.get_used_rect()
		if rect.has_area():
			rect = rect.grow(CROP_MARGIN).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			img = img.get_region(rect)

	# --- Save ---
	DirAccess.make_dir_recursive_absolute(UtilityStates.img_save_path)
	var file_path: String = UtilityStates.img_save_path + "%s_photo.png" % String(item.name).validate_filename()
	var err := img.save_png(file_path)
	if err != OK:
		push_error("Screenshot failed: %s" % error_string(err))
	else:
		print("Saved screenshot to: %s" % ProjectSettings.globalize_path(file_path))


func _add_light(parent: Node, rot_deg: Vector3, energy: float, color: Color) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rot_deg
	light.light_energy = energy
	light.light_color = color
	light.shadow_enabled = false
	parent.add_child(light)