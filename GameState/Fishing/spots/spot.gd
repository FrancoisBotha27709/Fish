extends Resource
class_name FishingSpot

enum Activity {
	LOW,
	MEDIUM,
	HIGH
}

signal fish_caught(remaining : int)
signal depleted()

@export var display_name : String
@export var activity_level : Activity = Activity.HIGH
@export var active_fish : Fish
@export var current_amount_available : int
@export var minigame : Minigame

## Removes one fish from the spot. Returns false if the spot was already
## empty (nothing to catch). Emits depleted() the moment the count hits 0.
func catch_one() -> bool:
	if current_amount_available <= 0:
		return false
	
	current_amount_available -= 1
	fish_caught.emit(current_amount_available)
	
	if current_amount_available <= 0:
		depleted.emit()
	
	return true

func has_fish() -> bool:
	return current_amount_available > 0
