extends Resource
class_name Minigame

@export_group("Data")
@export var score : float = 0.0
var active_fish : Fish
@export var difficulty : Difficulty = Difficulty.EASY
enum Difficulty {
	EASY,
	NORMAL,
	HARD,
	LEGENDARY
}
@export_subgroup("Progress")
@export var goal_progress : float
@export var current_progress : float

@export_group("MetaData")
@export var scene : PackedScene

## Call this whenever a new attempt at catching a (possibly new) fish begins.
func reset() -> void:
	current_progress = 0.0
	score = 0.0

func is_complete() -> bool:
	return current_progress >= goal_progress
