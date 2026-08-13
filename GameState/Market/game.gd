extends Node3D
class_name GameMarket

@export var player : PlayerMarket
@export var customer_list : Array[Customer]
@export var spawn_point : Node3D  # the single spot all customers appear at

var pending_customers : Array[Customer] = []
var active_visual : Node3D = null
var active_anim_player : AnimationPlayer = null

func _ready() -> void:
	pending_customers = customer_list.duplicate()
	next_customer()

## Bring in the next customer: instantiate, position, play "enter" anim, THEN negotiate
func next_customer() -> void:
	if player.active_customer != null:
		return
	if pending_customers.is_empty():
		print("No more customers today.")
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

	active_anim_player = _find_anim_player(active_visual)
	if active_anim_player and active_anim_player.has_animation("enter"):
		active_anim_player.play("enter")
		active_anim_player.animation_finished.connect(
			func(_anim_name): _start_after_entrance(next_c),
			CONNECT_ONE_SHOT
		)
	else:
		_start_after_entrance(next_c)

func _start_after_entrance(c : Customer) -> void:
	player.start_negotiating(c)

## Generic version — pass whichever animation name applies
func play_exit_animation(anim_name : String, on_finished : Callable) -> void:
	if active_anim_player and active_anim_player.has_animation(anim_name):
		active_anim_player.play(anim_name)
		active_anim_player.animation_finished.connect(
			func(_played_name): on_finished.call(),
			CONNECT_ONE_SHOT
		)
	else:
		on_finished.call()

## Called once the current customer is fully done (bought or walked away)
func on_customer_done() -> void:
	if active_visual:
		active_visual.queue_free()
		active_visual = null
		active_anim_player = null
	next_customer()

func _find_anim_player(node : Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found:
			return found
	return null
