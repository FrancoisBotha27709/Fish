extends FishingMinigame
class_name StardewFishingMinigame
## The "chase the moving target box" fishing minigame: hold input to
## accelerate the fish up/down, keep it inside a drifting/dashing target box
## to fill the catch bar. Streaks and a sweet spot reward staying locked on.
##
## Everything generic (progress, catch flow, difficulty scaling, fish visual)
## lives in FishingMinigame -- this script only adds the movement/feel.

const BASE_STARTING_SPEED := 7.0
const BASE_ACCELERATION := 18.0   ## how quickly the fish ramps up to max speed
const BASE_DRAG := 6.0            ## how quickly the fish slows when input is released
const BASE_GAIN_RATE := 25.0
const BASE_LOSS_RATE := 15.0

@export_group("Target")
@export var target_box : Area2D
@export var target_collision : CollisionShape2D

@export_subgroup("Fish Feel")
@export var starting_speed := BASE_STARTING_SPEED   ## max speed the fish can reach
@export var acceleration := BASE_ACCELERATION
@export var drag := BASE_DRAG

@export_subgroup("Streak / Combo")
@export var streak_ramp_time := 2.5     ## seconds of unbroken target-time to reach full streak bonus
@export var streak_gain_bonus := 1.0    ## extra multiplier added at full streak (1.0 = up to 2x gain)

@export_subgroup("Sweet Spot")
@export var sweet_spot_ratio := 0.4     ## sweet spot width as a fraction of the target box width
@export var sweet_spot_bonus := 1.5

@export_subgroup("Target Movement")
@export var target_drift_speed := 60.0
@export var target_dash_chance_per_sec := 0.15
@export var target_dash_speed := 240.0
@export var target_dash_duration := 0.35

@export_subgroup("Bounds")
@export var min_x : float = -200.0
@export var max_x : float = 1000.0

## Fires whenever the current streak value changes (0..1). Hook this to a
## bar glow / color shift / particle intensity.
signal streak_changed(streak: float)
signal sweet_spot_entered()
signal sweet_spot_exited()
## Fired when the fish escapes the target right after a strong streak.
signal close_call()

var input_held := false
var current_speed := 0.0   ## signed px/sec

var _fish_start_pos : Vector2
var _target_start_pos : Vector2

var _time_in_target := 0.0
var _streak_t := 0.0
var _was_in_target := false
var _was_in_sweet_spot := false
var _in_sweet_spot_now := false

var _target_velocity := Vector2.ZERO
var _target_dash_timer := 0.0
var _target_drift_seed := 0.0


func _ready() -> void:
	super._ready()
	_fish_start_pos = fish_area.position
	_target_start_pos = target_box.position
	_target_drift_seed = randf() * TAU


func _unhandled_input(event: InputEvent) -> void:
	if not started:
		return
	if event.is_action_pressed("move_cursor"):
		input_held = true
	elif event.is_action_released("move_cursor"):
		input_held = false


func _update_gameplay(delta: float) -> void:
	_move_fish(delta)
	_move_target(delta)
	_update_streak_and_sweet_spot(delta)


func _move_fish(delta: float) -> void:
	# Momentum-based control: holding accelerates towards max speed, releasing
	# lets drag pull it back -- gives the fish "weight" instead of just
	# teleporting between two fixed velocities.
	var max_speed := starting_speed * 10.0
	if input_held:
		current_speed = move_toward(current_speed, max_speed, acceleration * 10.0 * delta)
	else:
		current_speed = move_toward(current_speed, -max_speed, drag * 10.0 * delta)

	fish_area.position.x += current_speed * delta
	fish_area.position.x = clamp(fish_area.position.x, min_x, max_x)
	if fish_area.position.x == min_x or fish_area.position.x == max_x:
		current_speed = 0.0


func _move_target(delta: float) -> void:
	# Smooth drift punctuated by occasional fast dashes -- the actual
	# tracking challenge; without it the player only fights their own input.
	_target_dash_timer -= delta

	if _target_dash_timer <= 0.0 and randf() < target_dash_chance_per_sec * delta:
		var dash_dir := 1.0 if randf() < 0.5 else -1.0
		_target_velocity = Vector2(dash_dir * target_dash_speed, 0.0)
		_target_dash_timer = target_dash_duration
	elif _target_dash_timer <= 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		_target_velocity = Vector2(sin(t + _target_drift_seed) * target_drift_speed, 0.0)

	target_box.position += _target_velocity * delta
	target_box.position.x = clamp(target_box.position.x, min_x - 100.0, max_x + 100.0)


func _update_streak_and_sweet_spot(delta: float) -> void:
	var in_target := _is_on_target()
	_in_sweet_spot_now = in_target and _is_in_sweet_spot()

	_time_in_target = _time_in_target + delta if in_target else 0.0
	_streak_t = clamp(_time_in_target / streak_ramp_time, 0.0, 1.0)
	streak_changed.emit(_streak_t)

	if not in_target and _was_in_target and _streak_t > 0.6:
		close_call.emit()

	if _in_sweet_spot_now and not _was_in_sweet_spot:
		sweet_spot_entered.emit()
	elif not _in_sweet_spot_now and _was_in_sweet_spot:
		sweet_spot_exited.emit()

	_was_in_target = in_target
	_was_in_sweet_spot = _in_sweet_spot_now


func _is_on_target() -> bool:
	return target_box.overlaps_area(fish_area)


func _get_progress_multiplier() -> float:
	var multiplier := 1.0 + _streak_t * streak_gain_bonus
	if _in_sweet_spot_now:
		multiplier *= sweet_spot_bonus
	return multiplier


func _is_in_sweet_spot() -> bool:
	var shape := target_collision.shape as RectangleShape2D
	if not shape:
		return false
	var half_width := (shape.size.x * sweet_spot_ratio) * 0.5
	return absf(fish_area.global_position.x - target_box.global_position.x) <= half_width


func _on_apply_difficulty(scale: float) -> void:
	starting_speed = BASE_STARTING_SPEED * scale
	acceleration = BASE_ACCELERATION * scale
	drag = BASE_DRAG * scale
	progress_loss_rate = BASE_LOSS_RATE * scale
	progress_gain_rate = BASE_GAIN_RATE / scale
	target_drift_speed = 60.0 * scale
	target_dash_chance_per_sec = 0.15 * scale
	target_dash_speed = 240.0 * scale


func _on_start() -> void:
	current_speed = 0.0
	input_held = false
	_time_in_target = 0.0
	_streak_t = 0.0
	_was_in_target = false
	_was_in_sweet_spot = false
	_target_dash_timer = 0.0


func _on_catch() -> void:
	_time_in_target = 0.0
	_move_target_to_random_spot()
	_shrink_target()


func _on_stop() -> void:
	fish_area.position = _fish_start_pos
	target_box.position = _target_start_pos


func _move_target_to_random_spot() -> void:
	var new_x := randf_range(min_x, max_x)
	create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_ELASTIC)\
		.tween_property(target_box, "position:x", new_x, 0.4)


func _shrink_target() -> void:
	var shape := target_collision.shape as RectangleShape2D
	if shape:
		shape.size.x = max(50.0, shape.size.x * 0.95)
