extends Area3D
class_name FishingSpotObject
## Fired the moment this spot runs out of fish (whether the player was
## actively fishing or not). Useful for e.g. respawning fish later.
signal spot_depleted()
@export_group("Objects")
@export var collision : CollisionShape3D
@export var popup_window : PopupPanel
@export var minigame : FishingMinigame
@export_group("Data")
@export var data_resource : FishingSpot
@export_group("Outside Data")
@export var player : PlayerFish
@export_group("Catch Feedback")
## How long to pause on a "Nice catch!" beat before the next fish starts.
@export var catch_pause_seconds : float = 1.2
## Optional -- if assigned, its text/visibility is toggled during the pause.
@export var catch_message_label : Label
## Built at runtime so this works even without a hand-built popup scene.
## If you'd rather design your own, swap this out for an @export'd
## ConfirmationDialog/PackedScene and skip _setup_popup().
var _confirm_popup : ConfirmationDialog
var _fishing_active : bool = false

func _ready() -> void:
	await get_tree().process_frame
	data_resource.minigame.active_fish = data_resource.active_fish
	minigame.fish_caught.connect(_on_fish_caught)
	minigame.leave_requested.connect(_on_leave_requested)
	minigame.stop() # guarantee a clean, hidden state regardless of editor wiring
	_setup_popup()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _setup_popup() -> void:
	_confirm_popup = ConfirmationDialog.new()
	_confirm_popup.get_ok_button().text = "Fish"
	_confirm_popup.get_cancel_button().text = "Not now"
	_confirm_popup.confirmed.connect(_on_fish_confirmed)
	_confirm_popup.canceled.connect(_on_fish_declined)
	_confirm_popup.close_requested.connect(_on_fish_declined)
	add_child(_confirm_popup)

func _on_body_entered(body: Node3D) -> void:
	if body != player:
		return
	if not data_resource.has_fish():
		return
	_confirm_popup.dialog_text = "There are %d %s fish here. Want to fish?" % [
		data_resource.current_amount_available,
		data_resource.display_name
	]
	_confirm_popup.popup_centered()

func _on_body_exited(body: Node3D) -> void:
	popup_window.visible = false
	_confirm_popup.hide()
	_stop_fishing()

func _on_fish_confirmed() -> void:
	popup_window.visible = true
	_start_fishing()

func _on_fish_declined() -> void:
	pass # Player chose not to fish -- stay free to move around.

func _start_fishing() -> void:
	if not data_resource.has_fish():
		return
	_fishing_active = true
	popup_window.show()
	player.playing_minigame = true
	minigame.start(data_resource.minigame)

func _stop_fishing() -> void:
	_fishing_active = false
	player.playing_minigame = false
	minigame.stop()
	if catch_message_label:
		catch_message_label.visible = false

func _on_fish_caught(fish: Fish) -> void:
	if player:
		player.catch_fish(fish)
	var caught := data_resource.catch_one()
	if not caught or not data_resource.has_fish():
		_stop_fishing()
		spot_depleted.emit()
		return
	await _celebrate_catch()
	# The player may have walked off (or hit Leave) during the pause above --
	# don't resurrect the minigame if fishing was cancelled meanwhile.
	if not _fishing_active:
		return
	# Fish left in the spot -- go again after the little celebration beat.
	data_resource.minigame.active_fish = data_resource.active_fish
	minigame.start(data_resource.minigame)

func _celebrate_catch() -> void:
	if catch_message_label:
		catch_message_label.text = "Nice catch!"
		catch_message_label.visible = true
	await get_tree().create_timer(catch_pause_seconds).timeout
	if catch_message_label:
		catch_message_label.visible = false

func _on_leave_requested() -> void:
	_stop_fishing()
