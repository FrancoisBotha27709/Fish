extends Resource
class_name Customer

enum HaggleState { LOW, MEDIUM, HIGH, NONE }
enum OfferResult { ACCEPT, REJECT, WALKAWAY, NONE }

@export_group("Data")
@export var display_name : String = "Bob"
@export_multiline() var dialog_text : String = ""
@export var dialog_file : String
@export var haggle_level : HaggleState = HaggleState.MEDIUM
@export var outcome : OfferResult = OfferResult.NONE
@export_group("Scenes")
@export var visual_scene : PackedScene

var want_item : Item = null
## what the customer currently expects to pay
var current_offer : float = 0.0
var rejections : int = 0
var max_rejections : int = 3

const HAGGLE_DATA : Dictionary[HaggleState, Dictionary] = {
	HaggleState.NONE : {"max_bonus_pct": 0.00, "concede_pct": 0.00},
	HaggleState.LOW : {"max_bonus_pct": 0.10, "concede_pct": 0.02},
	HaggleState.MEDIUM : {"max_bonus_pct": 0.25, "concede_pct": 0.05},
	HaggleState.HIGH : {"max_bonus_pct": 0.50, "concede_pct": 0.10},
}

## Pick a random item inside [UtilityStates] inventory
func request_random_item(available_items : Array[Item]) -> bool:
	if available_items.is_empty():
		return false

	want_item = available_items[randi() % available_items.size()]
	current_offer = want_item.get_value() * randf_range(0.6, 0.85) # opening lowball
	rejections = 0
	outcome = OfferResult.NONE
	return true

func ask_item() -> String:
	return want_item.display_name if want_item else ""

func get_current_offer() -> float:
	return current_offer

func get_ceiling() -> float:
	if want_item == null:
		return 0.0
	var data : Dictionary = HAGGLE_DATA[haggle_level]
	return want_item.get_value() * (1.0 + data.max_bonus_pct)

## Player sets a specific asking price via slider; customer judges it.
func evaluate_offer(requested_amount : float) -> float:
	if want_item == null:
		outcome = OfferResult.WALKAWAY
		return -1.0

	var ceiling := get_ceiling()

	if requested_amount <= current_offer or requested_amount <= ceiling:
		current_offer = requested_amount
		outcome = OfferResult.ACCEPT
		read_file(false)
		return current_offer

	# Too greedy — reject, nudge the customer's own offer up a little
	rejections += 1
	if haggle_level == HaggleState.NONE or rejections >= max_rejections:
		outcome = OfferResult.WALKAWAY
		read_file(false)
		return -1.0

	var data : Dictionary = HAGGLE_DATA[haggle_level]
	current_offer = min(current_offer + want_item.get_value() * data.concede_pct, ceiling)
	outcome = OfferResult.REJECT
	read_file(false)
	return current_offer

func read_file(is_haggle : bool = true) -> void:
	var data := _load_dialog_json()
	if data.is_empty():
		return

	if is_haggle:
		match haggle_level:
			HaggleState.LOW:
				dialog_text = data.get("low_haggle_%d" % randi_range(0, 9), "")
			HaggleState.MEDIUM:
				dialog_text = data.get("medium_haggle_%d" % randi_range(0, 9), "")
			HaggleState.HIGH:
				dialog_text = data.get("high_haggle_%d" % randi_range(0, 9), "")
	else:
		match outcome:
			OfferResult.ACCEPT:
				dialog_text = data.get("accept_%d" % randi_range(0, 9), "")
			OfferResult.REJECT:
				dialog_text = data.get("reject_%d" % randi_range(0, 9), "")
			OfferResult.WALKAWAY:
				dialog_text = data.get("walkaway_%d" % randi_range(0, 9), "")
			OfferResult.NONE:
				pass


## Builds a line for when the player doesn't have anything to offer this
## customer at all, pulled from the customer's dialog file's "request_N" keys.
func generate_request_text() -> String:
	var data := _load_dialog_json()
	if data.is_empty():
		return ""
	dialog_text = data.get("request_%d" % randi_range(0, 9), "")
	return dialog_text


func _load_dialog_json() -> Dictionary:
	if dialog_file.is_empty():
		return {}

	var text := FileAccess.get_file_as_string(dialog_file)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Customer %s: Failed to read dialog file - %s" % [display_name, dialog_file])
		return {}

	return json.data