extends Node3D
class_name CharacterScene

## Emitted once the customer has finished walking to the counter and is ready to be served.
signal arrived_at_clerk
## Emitted once the customer has walked back out and can be freed/hidden.
signal left_scene

@export var anim_tree : AnimationTree
@export var clerk_position : Node3D          ## Marker3D where the customer stops to talk
@export var exit_position : Node3D           ## Marker3D the customer walks back to when leaving
@export var move_speed : float = 2.0
@export var arrival_distance : float = 0.15
@export var idle_switch_min_time : float = 4.0
@export var idle_switch_max_time : float = 9.0
@export var default_transition_blend_time : float = 0.25 ## crossfade length applied to every state transition

## Keys match the AnimationNodeStateMachine's advance-condition names, so
## change_animation() drives the tree by toggling parameters/conditions/<name>.
@export var anim_dict : Dictionary[int, String] = {
	0 : "Walk",
	1 : "Idle_Subtle",
	2 : "Idle_Fold",
	3 : "Idle_Rail",
	4 : "Idle_Listening",
	5 : "End",
	6 : "Reject",
	7 : "Accept",
}
@export_group("Face")
@export var face_mesh: MeshInstance3D
@export var face_surface_index: int = 0

## The idle animations that get randomly cycled through while a customer waits.
const IDLE_IDS : Array[int] = [1, 2, 3] # Idle_Subtle, Idle_Fold, Idle_Rail

var _current_customer : Customer
var _moving : bool = false
var _move_target : Vector3
var _move_purpose : String = "" # "clerk" or "exit"

var _idle_timer : Timer
var _current_idle_id : int = -1


func _ready() -> void:
	_idle_timer = Timer.new()
	_idle_timer.one_shot = true
	add_child(_idle_timer)
	_idle_timer.timeout.connect(_on_idle_timer_timeout)
	_apply_transition_blending()


## Forces every transition in the state machine to crossfade instead of hard-cutting,
## so change_animation() always blends smoothly regardless of how each transition
## was left configured in the editor.
func _apply_transition_blending() -> void:
	if anim_tree == null:
		return
	var state_machine := anim_tree.tree_root as AnimationNodeStateMachine
	if state_machine == null:
		return
	for i in state_machine.get_transition_count():
		var transition := state_machine.get_transition(i)
		transition.xfade_time = default_transition_blend_time


func _physics_process(delta: float) -> void:
	if not _moving:
		return

	var to_target := _move_target - global_position
	to_target.y = 0.0

	if to_target.length() <= arrival_distance:
		_moving = false
		global_position.x = _move_target.x
		global_position.z = _move_target.z
		_on_move_finished()
		return

	var dir := to_target.normalized()
	global_position += dir * move_speed * delta
	look_at(global_position - dir, Vector3.UP)



func _on_move_finished() -> void:
	match _move_purpose:
		"clerk":
			_start_idle_cycle()
			arrived_at_clerk.emit()
		"exit":
			left_scene.emit()
	_move_purpose = ""


## Picks a random waiting idle, then keeps swapping to a different random one
## from IDLE_IDS after a random interval, for as long as it isn't interrupted.
func _start_idle_cycle() -> void:
	_pick_random_idle()
	_idle_timer.start(randf_range(idle_switch_min_time, idle_switch_max_time))


func _stop_idle_cycle() -> void:
	_idle_timer.stop()


func _on_idle_timer_timeout() -> void:
	_pick_random_idle()
	_idle_timer.start(randf_range(idle_switch_min_time, idle_switch_max_time))


func _pick_random_idle() -> void:
	var choices := IDLE_IDS.duplicate()
	if _current_idle_id in choices and choices.size() > 1:
		choices.erase(_current_idle_id)
	var new_id : int = choices[randi() % choices.size()]
	_current_idle_id = new_id
	change_animation(new_id)


## Call when a new customer resource is assigned to this character.
func setup_customer(customer : Customer) -> void:
	_current_customer = customer


## Walks from the spawn point to the counter, playing Walk until arrival, then
## drops into the random idle cycle and emits arrived_at_clerk.
func walk_to_clerk() -> void:
	if clerk_position == null:
		push_warning("CharacterScene: clerk_position not set, cannot walk_to_clerk()")
		return
	_move_target = clerk_position.global_position
	_move_purpose = "clerk"
	_moving = true
	change_animation(0) # Walk


## Call while the player is deliberating an offer so the customer visibly waits.
func listen_for_offer() -> void:
	_stop_idle_cycle()
	change_animation(4) # Idle_Listening


## Call right after Customer.evaluate_offer() to react to its result.
## On REJECT the customer drops back into the random idle cycle to keep
## waiting for the next offer; ACCEPT/WALKAWAY hand off to leave_scene().
func react_to_offer(customer : Customer) -> void:
	_stop_idle_cycle()
	match customer.outcome:
		Customer.OfferResult.ACCEPT:
			change_animation(7) # Accept
		Customer.OfferResult.REJECT:
			change_animation(6) # Reject
			_start_idle_cycle()
		Customer.OfferResult.WALKAWAY:
			change_animation(5) # End
		Customer.OfferResult.NONE:
			pass


## Sends the customer back out once the deal is done or they've walked away.
func leave_scene() -> void:
	_stop_idle_cycle()
	if exit_position == null:
		push_warning("CharacterScene: exit_position not set, cannot leave_scene()")
		left_scene.emit()
		return
	_move_target = exit_position.global_position
	_move_purpose = "exit"
	_moving = true
	change_animation(0) # Walk


## Central point for driving the AnimationTree state machine. anim_dict values
## match the state machine's advance-condition names, so this sets exactly one
## condition true and clears the rest each time.
func change_animation(id : int) -> void:
	if not anim_dict.has(id):
		push_warning("CharacterScene: no animation registered for id %d" % id)
		return
	if anim_tree == null:
		push_warning("CharacterScene: anim_tree not assigned")
		return

	var target_name : String = anim_dict[id]
	for anim_id : int in anim_dict.keys():
		var cond_name : String = anim_dict[anim_id]
		anim_tree.set("parameters/conditions/%s" % cond_name, cond_name == target_name)

func set_face(face_index: int) -> void:
	if face_mesh == null:
		push_warning("CharacterScene: face_mesh is not assigned")
		return

	if face_index < 0 or face_index > 11:
		push_warning("CharacterScene: face index must be between 0 and 11")
		return

	var material := face_mesh.get_active_material(face_surface_index)

	if material == null or not material is StandardMaterial3D:
		push_warning("CharacterScene: face does not have a StandardMaterial3D")
		return

	# Duplicate it so we only modify this character's face material.
	if face_mesh.get_surface_override_material(face_surface_index) == null:
		material = material.duplicate()
		face_mesh.set_surface_override_material(face_surface_index, material)

	# 3 columns × 4 rows.
	var column := face_index % 3
	var row := face_index / 3.0

	material.uv1_scale = Vector3(0.25, 0.25, 1.0)
	material.uv1_offset = Vector3(
		column * 0.25,
		row * 0.25,
		0.0
	)