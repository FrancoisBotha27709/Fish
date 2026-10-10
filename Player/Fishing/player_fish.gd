extends Player
class_name PlayerFish

## Emitted after a minigame catch has been added to the inventory. The spot that
## started the minigame listens to this to deduct from its fish count, and may
## call end_minigame() in response.
signal minigame_fish_caught(fish: Fish)
## Emitted whenever a minigame session ends: leave button, or the spot stopping it.
signal minigame_ended()
## Emitted when the player fails a minigame round (after UtilityStates.fail_streak
## has been increased). The session then ends after the "Fail" message.
signal minigame_failed()

@export_group("Movement")
@export var max_speed: float = 4.0
@export var acceleration: float = 2.0
@export var deceleration: float = 1.0
@export var turn_speed: float = 0.65
@export var turn_acceleration: float = 0.8
@export var turn_deceleration: float = 0.5
@export var drift_factor: float = 0.85
@export var model : BoatModel

@export_group("Boost")
@export var rotation_angle : float = 5.0
@export var rotation_speed : float = 12.0
@export var rotation_damping : float = 4.0
@export var max_boost_speed: float = 6.0
@export var boost_acceleration: float = 5.0
@export var boost_deceleration: float = 8.0

@export_subgroup("Boost FOV")
@export var normal_fov: float = 60.0
@export var boost_fov: float = 78.0
@export var fov_change_speed: float = 25.0

@export_subgroup("Wobble")
@export var wobble_amount: float = 0.4
@export var wobble_speed: float = 7.0
@export var wobble_randomness: float = 0.35
@export var wobble_random_speed: float = 0.8

@export_group("Physics")
@export var gravity: float = 20.0
@export var float_weight : float = 10.0
@export_subgroup("Collisions")
@export var collision_shapes : Array[CollisionShape3D] = []
@export_subgroup("Buoyancy Gate")
@export var buoyancy_system: BuoyancySys
@export var min_submersion_to_move: float = 0.4  # fraction of hull height that must be underwater
@export var submersion_hysteresis: float = 0.15  # extra submersion needed to count as back in the water

@export_group("Land")
@export var land_align_speed: float = 3.0      # how quickly the boat settles onto terrain (lower = heavier)
@export var land_friction: float = 1.5         # horizontal slow-down while beached (0 = slides forever)

@export_group("Camera")
@export var camera_target: Node3D
@export var cam_rig : CameraRig

@export_group("UI Objects")
@export var analog_motion_sensor : AnalogMotionSensor

@export_group("Minigame")
@export var fishing_camera: Camera3D        ## secondary camera we switch to while fishing
@export var minigame_holder: Control        ## Control under a CanvasLayer; minigame scenes are parented here
@export var catch_message_label: Label
@export var catch_pause_seconds: float = 1.2
@export var catch_text: String = "Nice catch!"
@export var fail_text: String = "Fail"

@export_group("Border")
@export var border_steer_gain: float = 2.0

## Read by BuoyancySys to stop forcing the hull level while on land.
var is_out_of_water := false
var playing_minigame := false

var _wobble_time := 0.0
var _wobble_offset := 0.0
var _boost_speed := 0.0
var _current_speed := 0.0
var _current_turn_rate := 0.0
var _boost_rotation_velocity := 0.0
var _minigame_position := Vector3.ZERO
var _border_active := false
var _border_push_direction := Vector3.ZERO

var _minigames: Dictionary[Minigame, FishingMinigame] = {}  ## one spawned instance per Minigame resource
var _active_minigame: FishingMinigame
var _active_data: Minigame
var _session := 0  ## bumps on every start/end so stale post-catch restarts can be cancelled
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _fishing_camera_rest := Transform3D.IDENTITY

func _ready() -> void:
	_wobble_offset = randf_range(0.0, TAU)
	set_meta("float_weight", float_weight)
	if fishing_camera:
		_fishing_camera_rest = fishing_camera.transform
	if minigame_holder:
		minigame_holder.hide()
	if catch_message_label:
		catch_message_label.hide()
	super._ready()

func _physics_process(delta: float) -> void:
	if playing_minigame:
		_current_speed = 0.0
		velocity = Vector3.ZERO
		global_position = _minigame_position
		analog_motion_sensor.neutral(delta)
	else:
		_handle_movement(delta)
		if is_out_of_water: _handle_land(delta)
	move_and_slide()

# Gravity comes from BuoyancySys, so only orientation and friction live here.
func _handle_land(delta: float) -> void:
	if is_on_floor():
		var n := get_floor_normal()
		var fwd := (-global_basis.z).slide(n).normalized()
		var target := Basis(fwd.cross(n).normalized(), n, -fwd).get_rotation_quaternion()
		global_basis = Basis(global_basis.get_rotation_quaternion().slerp(target, 1.0 - exp(-land_align_speed * delta)))
	var f := clampf(land_friction * delta, 0.0, 1.0)
	velocity *= Vector3(1.0 - f, 1.0, 1.0 - f)

func _handle_movement(delta: float) -> void:
	var throttle: float
	var steer: float
	if _border_active: # simulated input: drive forward and steer toward the return point
		throttle = 1.0
		var to := Vector3(_border_push_direction.x, 0.0, _border_push_direction.z)
		steer = clampf(-(-global_basis.z).signed_angle_to(to.normalized(), Vector3.UP) * border_steer_gain, -1.0, 1.0) if to.length() > 0.001 else 0.0
	else:
		throttle = Input.get_axis("boat_reverse", "boat_forward")
		steer = Input.get_axis("boat_turn_left", "boat_turn_right")

	# Hull must be sufficiently underwater to respond to input (hysteresis stops waterline flicker)
	is_out_of_water = buoyancy_system != null and buoyancy_system.get_submersion(self) < min_submersion_to_move + (submersion_hysteresis if is_out_of_water else 0.0)
	if is_out_of_water:
		throttle = 0.0
		steer = 0.0

	analog_motion_sensor.call(["reverse", "neutral", "forward"][int(signf(throttle)) + 1], delta)

	# Wobble
	_wobble_time += delta
	var t := _wobble_time * wobble_speed
	var wobble := sin(t + _wobble_offset) * 0.6 + sin(t * 0.47 + _wobble_offset * 1.7) * 0.25 + sin(t * 0.19 + _wobble_offset * 2.3) * 0.15
	wobble *= (1.0 + sin(_wobble_time * wobble_random_speed + _wobble_offset * 3.1) * wobble_randomness) * deg_to_rad(wobble_amount)
	model.rotation.z = 0.0
	model.rotate_z(wobble)

	# Speed + boost
	if throttle != 0.0:
		var target_speed := throttle * (max_speed + _boost_speed)
		var boosting := Input.is_action_pressed("boost")
		model.boost(30 if boosting else 4)
		cam_rig.camera.change_fov(boost_fov if boosting else normal_fov, delta)
		_boost_speed = move_toward(_boost_speed, max_boost_speed if boosting else 0.0, (boost_acceleration if boosting else boost_deceleration) * delta)
		_boost_rotation_velocity += (deg_to_rad(rotation_angle if boosting else 0.0) - model.rotation.x) * rotation_speed * delta
		_boost_rotation_velocity *= exp(-rotation_damping * delta)
		model.rotation.x += _boost_rotation_velocity * delta
		for c in collision_shapes: c.rotation.x += _boost_rotation_velocity * delta
		_current_speed = lerpf(_current_speed, target_speed, 1.0 - exp(-acceleration * delta))
	else:
		_current_speed = lerpf(_current_speed, 0.0, 1.0 - exp(-deceleration * delta))
	model.rotate_prop(_current_speed, delta, throttle >= 0.0)

	# Turning
	var target_turn := steer * turn_speed * clampf(absf(_current_speed) / max_speed, 0.0, 1.0)
	_current_turn_rate = move_toward(_current_turn_rate, target_turn if steer != 0.0 else 0.0, (turn_acceleration if steer != 0.0 else turn_deceleration) * delta)
	rotate_y(-_current_turn_rate * delta)
	model.turn_rudder(steer, turn_speed, delta)

	# Drift toward the drive velocity; while beached momentum carries (see _handle_land)
	if not is_out_of_water:
		var k := (1.0 - drift_factor) * delta * 10.0
		var target_velocity := -global_basis.z * _current_speed
		velocity.x = lerpf(velocity.x, target_velocity.x, k)
		velocity.z = lerpf(velocity.z, target_velocity.z, k)

	model.aim_lights(cam_rig.get_ray_target(), delta)


# --- Minigames ---------------------------------------------------------------
# A fishing spot only tells us WHICH minigame to play (start_minigame). We spawn
# its scene under minigame_holder, switch to the fishing camera, and run it until
# the minigame's own leave button is pressed (or the spot calls end_minigame(),
# e.g. when it runs out of fish).

## `minigame_data.active_fish` must already be set by the caller. `focus` is an
## optional node for the fishing camera to look at.
func start_minigame(minigame_data: Minigame, focus: Node3D = null) -> void:
	if playing_minigame:
		return
	var minigame := _get_minigame(minigame_data)
	if minigame == null:
		return

	_session += 1
	playing_minigame = true
	_minigame_position = global_position
	velocity = Vector3.ZERO
	_active_minigame = minigame
	_active_data = minigame_data

	_switch_to_fishing_camera(focus)
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # the leave button needs a cursor
	minigame_holder.show()
	minigame.start(minigame_data)

func end_minigame() -> void:
	if not playing_minigame:
		return
	playing_minigame = false
	_session += 1  # cancels any pending "start the next fish" after a catch

	if _active_minigame:
		_active_minigame.stop()
	_active_minigame = null
	_active_data = null

	if catch_message_label:
		catch_message_label.hide()
	minigame_holder.hide()
	cam_rig.camera.make_current()  # back to the normal camera
	Input.mouse_mode = _prev_mouse_mode
	minigame_ended.emit()

func catch_fish(fish: Fish) -> void:
	UtilityStates.add_item(fish)
	print("Caught fish")

## Spawns the minigame scene on first use, then reuses it.
func _get_minigame(minigame_data: Minigame) -> FishingMinigame:
	if minigame_data == null or minigame_data.scene == null:
		push_error("start_minigame() needs a Minigame resource that has a scene.")
		return null
	if minigame_holder == null or fishing_camera == null:
		push_error("PlayerFish needs minigame_holder and fishing_camera assigned.")
		return null
	if _minigames.has(minigame_data):
		return _minigames[minigame_data]

	var instance := minigame_data.scene.instantiate()
	if not instance is FishingMinigame:
		push_error("Minigame scene root isn't a FishingMinigame.")
		instance.queue_free()
		return null

	var minigame := instance as FishingMinigame
	minigame_holder.add_child(minigame)
	minigame_holder.move_child(minigame, 0)  # keep the catch label drawn on top
	minigame.fish_caught.connect(_on_minigame_fish_caught)
	minigame.leave_requested.connect(end_minigame)
	minigame.minigame_failed.connect(_on_minigame_failed)
	minigame.stop()
	_minigames[minigame_data] = minigame
	return minigame

func _switch_to_fishing_camera(focus: Node3D) -> void:
	fishing_camera.transform = _fishing_camera_rest
	if focus:
		fishing_camera.look_at(focus.global_position, Vector3.UP)
	fishing_camera.make_current()

func _on_minigame_fish_caught(fish: Fish) -> void:
	catch_fish(fish)
	minigame_fish_caught.emit(fish)  # the spot may end the session in response
	if not playing_minigame:
		return

	var session := _session
	_show_message(catch_text)
	await get_tree().create_timer(catch_pause_seconds).timeout
	if session != _session:  # left (or restarted) during the celebration
		return
	if catch_message_label:
		catch_message_label.hide()
	_active_minigame.start(_active_data)

func _on_minigame_failed() -> void:
	UtilityStates.fail_streak += 1
	minigame_failed.emit()
	if not playing_minigame:
		return

	var session := _session
	_show_message(fail_text)
	UtilityStates.flash_red(catch_message_label)
	await get_tree().create_timer(catch_pause_seconds).timeout
	if session != _session:  # left during the message
		return
	end_minigame()  # also hides the label

func _show_message(text: String) -> void:
	if catch_message_label:
		catch_message_label.text = text
		catch_message_label.show()


func darken_vision(intensity: float, push_direction: Vector3) -> void:
	_border_active = true
	_border_push_direction = push_direction
	cam_rig.camera.darken_vision(intensity)

func clear_border() -> void:
	_border_active = false
	cam_rig.camera.darken_vision(0.0)