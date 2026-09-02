extends Control
class_name FishingMinigame
## Base class for every fishing minigame variant. Handles the parts every
## variant needs -- wiring to a Minigame resource, pushing progress to the
## UI, the catch/leave flow, difficulty scaling, and swapping in the fish's
## visual -- and nothing about the actual gameplay feel.
##
## To make a new minigame type, extend this script and override whichever
## of the "Overridable hooks" below your variant needs. See
## stardew_fishing_minigame.gd for a full example.

@export_group("Core UI")
@export var fish_area : Area2D          ## the fish itself -- shared by all variants
@export var leave_button : Button
@export var catch_progress_bar : ProgressBar

@export_group("Tuning")
@export var progress_gain_rate : float = 25.0   ## progress/sec while "on target"
@export var progress_loss_rate : float = 15.0   ## progress/sec while "off target"

## Emitted every physics frame while running -- hook a UI progress bar to this.
signal catching_progress_changed(current: float, goal: float)
## Emitted the instant progress reaches goal_progress.
signal fish_caught(fish: Fish)
## Emitted when the player presses the in-minigame leave button.
signal leave_requested()

var minigame : Minigame
var fish : Fish
var started : bool = false
var fish_caught_count := 0
var difficulty_scale := 1.0

var _fish_visual : Node2D


func _ready() -> void:
	if leave_button:
		leave_button.pressed.connect(_on_leave_button_pressed)
	visible = false


func _physics_process(delta: float) -> void:
	if not started:
		return
	_update_gameplay(delta)
	if minigame == null:
		return
	_advance_progress(delta)
	if minigame.is_complete():
		_catch_fish()


## Applies gain/loss based on _is_on_target()/_get_progress_multiplier(),
## then pushes the result to the progress bar and signal.
func _advance_progress(delta: float) -> void:
	if _is_on_target():
		minigame.current_progress = min(
			minigame.current_progress + progress_gain_rate * _get_progress_multiplier() * delta,
			minigame.goal_progress
		)
	else:
		minigame.current_progress = max(
			minigame.current_progress - progress_loss_rate * delta,
			0.0
		)
	catch_progress_bar.value = minigame.current_progress
	catching_progress_changed.emit(minigame.current_progress, minigame.goal_progress)


func _catch_fish() -> void:
	if not started:
		return
	started = false
	minigame.reset()
	catch_progress_bar.value = 0

	var caught := fish.duplicate() as Fish
	caught.randomize_data()
	fish_caught_count += 1
	_on_catch()
	fish_caught.emit(caught)


func _on_leave_button_pressed() -> void:
	started = false
	leave_requested.emit()


## Call this to (re)start the minigame for a given Minigame resource. Safe to
## call again right after a catch to immediately go for the next fish.
func start(minigame_data: Minigame) -> void:
	minigame = minigame_data
	minigame.reset()
	fish = minigame.active_fish

	_apply_difficulty()
	catch_progress_bar.max_value = minigame.goal_progress
	_set_fish_visual()
	_on_start()

	started = true
	visible = true


func stop() -> void:
	started = false
	visible = false
	if minigame:
		minigame.reset()
	minigame = null
	fish = null

	catch_progress_bar.value = 0
	catch_progress_bar.max_value = 0
	_clear_fish_visual()
	_on_stop()


func _apply_difficulty() -> void:
	match minigame.difficulty:
		Minigame.Difficulty.EASY:
			difficulty_scale = 0.8
		Minigame.Difficulty.NORMAL:
			difficulty_scale = 1.0
		Minigame.Difficulty.HARD:
			difficulty_scale = 1.25
		Minigame.Difficulty.LEGENDARY:
			difficulty_scale = 1.6
	_on_apply_difficulty(difficulty_scale)


func _set_fish_visual() -> void:
	_clear_fish_visual()
	if not fish or not fish.world_scene:
		return
	var instance := fish.world_scene.instantiate()
	if not (instance is Node2D):
		push_warning("Fish '%s' world_scene root isn't a Node2D -- can't use it in the minigame." % fish.display_name)
		instance.queue_free()
		return
	_fish_visual = instance
	fish_area.add_child(_fish_visual)
	_fish_visual.position = Vector2.ZERO


func _clear_fish_visual() -> void:
	if _fish_visual:
		_fish_visual.queue_free()
		_fish_visual = null


# Base implementations are no-ops / neutral defaults. Override in a subclass
# to build the actual gameplay feel.

## Move the fish, the target, whatever -- called every physics frame while running.
func _update_gameplay(_delta: float) -> void:
	pass

## Whether progress should currently be gaining (true) or draining (false).
func _is_on_target() -> bool:
	return false

## Extra multiplier on top of progress_gain_rate (streaks, sweet spots, etc).
func _get_progress_multiplier() -> float:
	return 1.0

## Scale your variant's own tuning values by the resolved difficulty_scale.
func _on_apply_difficulty(_scale: float) -> void:
	pass

## Reset per-round state (positions, timers, input). Called from start(),
## after difficulty has been applied and the fish visual is in place.
func _on_start() -> void:
	pass

## Called right after a fish is caught, before fish_caught fires -- good
## place to reposition a target / shrink a hitbox / ramp difficulty up.
func _on_catch() -> void:
	pass

## Called from stop() for any variant-specific cleanup (resetting positions, etc).
func _on_stop() -> void:
	pass
