extends Area2D
class_name Blip
## Sonar blip. Invisible until the bar sweeps over it, then it "pings" to full
## brightness and fades out. While the fade is running the player can answer the
## QTE prompt; if the blip fades out first, that counts as a miss. Any failure
## flashes the blip red.

## All QTE steps completed
signal caught(blip : Blip)
## A QTE was failed: wrong button, or the blip faded out before an answer
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

@export_group("Fade")
## The node that fades and flashes red (your dot sprite). If empty, the first
## Sprite2D / AnimatedSprite2D / Polygon2D child is used.
@export var visual : CanvasItem
## Seconds to fade from full brightness to invisible. 0 = auto (see below).
@export var fade_time : float = 0.0
## Used when fade_time is 0: fraction of one full sweep the fade lasts.
@export_range(0.1, 1.0) var auto_fade_fraction : float = 0.8

var active : bool = false

var _state : State = State.IDLE
var _steps_done : int = 0
var _current_action : StringName
var _home_position : Vector2
var _move_tween : Tween
var _fade_tween : Tween
var _flash_tween : Tween
var _visual_node : CanvasItem        ## what actually draws the dot (null if none found)
var _fade_node : CanvasItem          ## what fades (the dot, or the whole blip as a fallback)
var _base_self_modulate := Color.WHITE


func _ready() -> void:
	_visual_node = visual if visual else _find_visual()
	if _visual_node == null:
		push_warning("Blip '%s': assign 'visual' (the dot sprite) so it can flash red." % name)
	else:
		_base_self_modulate = _visual_node.self_modulate
	_fade_node = _visual_node if _visual_node else self

	if sonar == null:
		sonar = _find_sonar()
	if sonar == null:
		push_error("Blip '%s' couldn't find a SonarCircle ancestor." % name)
		return
	sonar.bar_passed.connect(_on_bar_passed)
	deactivate()


func _find_visual() -> CanvasItem:
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D or child is Polygon2D:
			return child
	return null


func _find_sonar() -> SonarCircle:
	var node := get_parent()
	while node != null:
		if node is SonarCircle:
			return node
		node = node.get_parent()
	return null


## How close to caught this blip is, 0.0 to 1.0.
func get_progress() -> float:
	return float(_steps_done) / maxi(steps_required, 1)


## Brings the blip into play at `pos`. It stays invisible until the bar sweeps it.
func activate(pos : Vector2, steps : int) -> void:
	_kill_tweens()
	steps_required = steps
	_steps_done = 0
	_state = State.IDLE
	position = pos
	_home_position = pos
	active = true
	_set_alpha(0.0)
	show()
	set_deferred("monitorable", true)


## Takes the blip out of play without freeing it.
func deactivate() -> void:
	active = false
	_kill_tweens()
	_release_qte()
	_steps_done = 0
	_state = State.IDLE
	_set_alpha(0.0)
	hide()
	set_deferred("monitorable", false)


## Punishment: slide one step back toward where it started (does nothing at step 0).
func retreat_one_step() -> void:
	if not active or _steps_done <= 0:
		return
	_release_qte()
	_steps_done -= 1
	_move_to_step()


func _on_bar_passed(target : Node2D) -> void:
	if not active or target != self or _state != State.IDLE:
		return
	_start_fade()  # ping
	if sonar.active_qte == null:  # otherwise another blip holds the prompt: show only
		_request_qte()


func _start_fade() -> void:
	_kill_fade()
	_set_alpha(1.0)
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_node, "modulate:a", 0.0, _get_fade_duration())
	_fade_tween.tween_callback(_on_fade_finished)


func _get_fade_duration() -> float:
	if fade_time > 0.0:
		return fade_time
	return maxf(0.2, sonar.get_sweep_period() * auto_fade_fraction)


func _on_fade_finished() -> void:
	if _state == State.AWAITING_INPUT:  # faded out before the player answered: a miss
		_state = State.IDLE
		_release_qte()
		_flash_fail()
		failed.emit(self)


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
	_release_qte()
	step_completed.emit(_steps_done, steps_required)
	_move_to_step()


## Slides to the position for the current step count (forward or back), fully
## visible while moving, then fades again until the next sweep.
func _move_to_step() -> void:
	_state = State.MOVING
	_kill_fade()
	_set_alpha(1.0)

	var target_pos := _home_position.lerp(sonar.get_center(), get_progress())
	_kill_move()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target_pos, move_time).set_trans(Tween.TRANS_SINE)
	_move_tween.tween_callback(_on_move_finished)


func _on_move_finished() -> void:
	if _steps_done >= steps_required:
		caught.emit(self)
	else:
		_state = State.IDLE
		_start_fade()


func _on_qte_fail() -> void:
	_state = State.IDLE
	_release_qte()
	_flash_fail()
	failed.emit(self)


## Flash red on any failure. The blip is usually (nearly) faded out when it fails,
## so bring it back to full brightness first; otherwise the flash can't be seen.
func _flash_fail() -> void:
	if _visual_node == null:
		return
	_start_fade()
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = UtilityStates.flash_red(_visual_node)


func _set_alpha(a : float) -> void:
	_fade_node.modulate.a = a


func _kill_move() -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null


func _kill_fade() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


## Stops a running flash and restores the dot's normal color (pool reuse).
func _kill_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	if _visual_node:
		_visual_node.self_modulate = _base_self_modulate


func _kill_tweens() -> void:
	_kill_move()
	_kill_fade()
	_kill_flash()