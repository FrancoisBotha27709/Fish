extends Area2D
class_name Blip

## All QTE steps completed
signal caught(blip : Blip)
## Wrong button pressed
signal failed(blip : Blip)
## One QTE step completed
signal step_completed(done : int, total : int)

enum State {IDLE, AWAITING_INPUT, MOVING}

@export var steps_required : int = 3
@export var move_time : float = 0.4
## InputMap actions used for QTEs. Add them in Project Settings > Input Map.
@export var qte_actions : Array[StringName] = [&"qte_up", &"qte_down", &"qte_left", &"qte_right"]
@export var prompt_label : Label
## Optional. If empty, the blip walks up the tree to find a SonarCircle.
@export var sonar : SonarCircle

var active : bool = false

var _state : State = State.IDLE
var _steps_done : int = 0
var _current_action : StringName
var _home_position : Vector2
var _tween : Tween


func _ready() -> void:
	if sonar == null:
		sonar = _find_sonar()
	if sonar == null:
		push_error("Blip '%s' couldn't find a SonarCircle ancestor." % name)
		return
	sonar.bar_passed.connect(_on_bar_passed)
	deactivate()


func _find_sonar() -> SonarCircle:
	var node := get_parent()
	while node != null:
		if node is SonarCircle:
			return node
		node = node.get_parent()
	return null


## Brings the blip into play at `pos`. Safe to call repeatedly (pooling).
func activate(pos : Vector2, steps : int) -> void:
	_kill_tween()
	steps_required = steps
	_steps_done = 0
	_state = State.IDLE
	position = pos
	_home_position = pos
	active = true
	show()
	set_deferred("monitorable", true)


## Takes the blip out of play without freeing it.
func deactivate() -> void:
	active = false
	_kill_tween()
	_release_qte()
	_steps_done = 0
	_state = State.IDLE
	hide()
	set_deferred("monitorable", false)


func _on_bar_passed(target : Node2D) -> void:
	if not active or target != self or _state != State.IDLE:
		return
	if sonar.active_qte != null:  # another blip already has a prompt up
		return
	_request_qte()


func _request_qte() -> void:
	_state = State.AWAITING_INPUT
	sonar.active_qte = self
	_current_action = qte_actions.pick_random()
	set_process_unhandled_input(true)  # only listen while a prompt is up
	if prompt_label:
		prompt_label.text = String(_current_action).trim_prefix("qte_").to_upper()
		prompt_label.show()


func _unhandled_input(event : InputEvent) -> void:
	for action in qte_actions:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			if action == _current_action:
				_on_qte_success()
			else:
				_on_qte_fail()
			return


func _release_qte() -> void:
	set_process_unhandled_input(false)
	if prompt_label:
		prompt_label.hide()
	if sonar and sonar.active_qte == self:
		sonar.active_qte = null


func _on_qte_success() -> void:
	_steps_done += 1
	_state = State.MOVING
	_release_qte()
	step_completed.emit(_steps_done, steps_required)

	var target_pos := _home_position.lerp(sonar.get_center(), float(_steps_done) / steps_required)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "position", target_pos, move_time).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_on_move_finished)


func _on_move_finished() -> void:
	if _steps_done >= steps_required:
		caught.emit(self)
	else:
		_state = State.IDLE


func _on_qte_fail() -> void:
	_state = State.IDLE
	_release_qte()
	failed.emit(self)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null