extends Node3D
class_name GameMarket

@export var player : PlayerMarket
@export var customer_list : Array[Customer]
@export var spawn_point : Node3D      # the single spot all customers appear at
@export var clerk_position : Marker3D # the single spot all customers go to the clerk
@export var exit_position : Marker3D  # the single spot all customers exit towards
@export var reaction_hold_time : float = 1.5 # how long Accept/Reject/End plays before leaving

var pending_customers : Array[Customer] = []
var active_visual : Node3D = null
var active_character : CharacterScene = null


func _ready() -> void:
	pending_customers = customer_list.duplicate()
	next_customer()


## Bring in the next customer: instantiate, position, walk them to the clerk, THEN negotiate
func next_customer() -> void:
	if player.active_customer != null:
		return
	if pending_customers.is_empty():
		player.ui_node.dialog_lbl.text = "No more customers today"
		return

	var next_c : Customer = pending_customers.pop_front()

	if next_c.visual_scene == null:
		push_error("Customer %s has no visual_scene" % next_c.display_name)
		_start_after_entrance(next_c)
		return

	active_visual = next_c.visual_scene.instantiate()
	add_child(active_visual)
	if spawn_point and active_visual is Node3D:
		active_visual.global_transform = spawn_point.global_transform

	active_character = active_visual as CharacterScene
	if active_character == null:
		push_warning("Customer %s visual_scene root is not a CharacterScene" % next_c.display_name)
		_start_after_entrance(next_c)
		return

	active_character.clerk_position = clerk_position
	active_character.exit_position = exit_position
	active_character.setup_customer(next_c)
	active_character.arrived_at_clerk.connect(
		func(): _start_after_entrance(next_c),
		CONNECT_ONE_SHOT
	)
	active_character.walk_to_clerk()


func _start_after_entrance(c : Customer) -> void:
	player.start_negotiating(c)


## Plays the given reaction animation (must be a name from CharacterScene.anim_dict,
## e.g. "Accept" / "Reject" / "End"), holds on it briefly, then walks the customer
## out and calls on_finished once they've left.
func play_exit_animation(anim_name : String, on_finished : Callable) -> void:
	if active_character == null:
		on_finished.call()
		return

	var anim_id : int = _id_for_anim_name(anim_name)
	if anim_id != -1:
		active_character.change_animation(anim_id)
	else:
		push_warning("GameMarket: '%s' is not a registered animation name" % anim_name)

	var hold_timer := get_tree().create_timer(reaction_hold_time)
	print("GameMarket: reaction hold started for '%s', %.2fs" % [anim_name, reaction_hold_time])
	hold_timer.timeout.connect(
		_on_reaction_hold_finished.bind(active_character, on_finished),
		CONNECT_ONE_SHOT
	)


func _on_reaction_hold_finished(character : CharacterScene, on_finished : Callable) -> void:
	if character == null:
		on_finished.call()
		return
	character.left_scene.connect(on_finished, CONNECT_ONE_SHOT)
	character.leave_scene()


func _id_for_anim_name(anim_name : String) -> int:
	for id : int in active_character.anim_dict.keys():
		if active_character.anim_dict[id] == anim_name:
			return id
	return -1


## Called once the current customer is fully done (bought or walked away)
func on_customer_done() -> void:
	if active_visual:
		active_visual.queue_free()
	active_visual = null
	active_character = null
	next_customer()
