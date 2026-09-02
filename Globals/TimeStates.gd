extends Node

## Single source of truth for the day/night cycle.
## Every other system (sun/environment, gameplay, NPC schedules, fishing spawn
## tables, etc.) should read from here or connect to `time_changed` —
## nothing else should keep its own clock.

signal time_changed(time_of_day: float, day_number: int)
signal day_changed(day_number: int)

## How long one full in-game day takes, in real-world seconds.
@export var day_length_seconds: float = 600.0

## Normalized time of day: 0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
@export_range(0.0, 1.0) var time_of_day: float = 0.4

@export var paused: bool = false
@export var time_scale: float = 1.0

var day_number: int = 1


func _ready() -> void:
	# Fire once on startup so listeners can sync immediately instead of
	# waiting for the first _process tick.
	time_changed.emit(time_of_day, day_number)


func _process(delta: float) -> void:
	if paused:
		return

	var delta_normalized: float = (delta * time_scale) / day_length_seconds
	time_of_day += delta_normalized

	if time_of_day >= 1.0:
		time_of_day = fmod(time_of_day, 1.0)
		day_number += 1
		day_changed.emit(day_number)

	time_changed.emit(time_of_day, day_number)


## Jump directly to a time (e.g. sleeping until morning). Wraps to 0-1.
func set_time_of_day(value: float) -> void:
	time_of_day = fposmod(value, 1.0)
	time_changed.emit(time_of_day, day_number)


## Sun elevation angle in radians for the current time_of_day.
## 0.5 (noon) -> straight overhead, 0.0/1.0 (midnight) -> straight underfoot.
func get_sun_angle() -> float:
	return (time_of_day - 0.25) * TAU