extends Area3D
class_name FishingSpotObject

signal spot_depleted()
signal fish_removed()

@export_group("Objects")
@export var collision: CollisionShape3D
@export var popup_window: PopupPanel
@export var minigame: FishingMinigame

@export_group("Data")
@export var data_resource: FishingSpot

@export_group("Outside Data")
@export var player: PlayerFish

@export_group("Catch Feedback")
@export var catch_pause_seconds := 1.2
@export var catch_message_label: Label

var _confirm_popup: ConfirmationDialog
var _fishing_active := false


func _ready() -> void:
	if data_resource == null:
		push_error("FishingSpotObject has no data_resource assigned.")
		return

	if minigame == null:
		push_error("FishingSpotObject has no minigame assigned.")
		return

	await get_tree().process_frame

	data_resource.minigame.active_fish = data_resource.active_fish

	if not minigame.fish_caught.is_connected(_on_fish_caught):
		minigame.fish_caught.connect(_on_fish_caught)

	if not minigame.leave_requested.is_connected(_on_leave_requested):
		minigame.leave_requested.connect(_on_leave_requested)

	minigame.stop()
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

	_confirm_popup.dialog_text = (
		"There are %d %s fish here. Want to fish?"
		% [
			data_resource.current_amount_available,
			data_resource.display_name
		]
	)

	_confirm_popup.popup_centered()


func _on_body_exited(body: Node3D) -> void:
	if body != player:
		return

	if popup_window:
		popup_window.hide()

	if _confirm_popup:
		_confirm_popup.hide()

	_stop_fishing()


func _on_fish_confirmed() -> void:
	if popup_window:
		popup_window.show()

	_start_fishing()


func _on_fish_declined() -> void:
	pass


func _start_fishing() -> void:
	if not data_resource.has_fish():
		return

	_fishing_active = true

	if popup_window:
		popup_window.show()

	if player:
		player.playing_minigame = true

	minigame.start(data_resource.minigame)


func _stop_fishing() -> void:
	_fishing_active = false

	if player:
		player.playing_minigame = false

	minigame.stop()

	if catch_message_label:
		catch_message_label.hide()


func _on_fish_caught(fish: Fish) -> void:
	if player:
		player.catch_fish(fish)

	var caught := data_resource.catch_one()

	if not caught:
		return

	# Remove one visible fish.
	fish_removed.emit()

	if not data_resource.has_fish():
		_stop_fishing()
		spot_depleted.emit()
		return

	await _celebrate_catch()

	# The player may have left during the celebration.
	if not _fishing_active:
		return

	data_resource.minigame.active_fish = data_resource.active_fish
	minigame.start(data_resource.minigame)


func _celebrate_catch() -> void:
	if catch_message_label:
		catch_message_label.text = "Nice catch!"
		catch_message_label.show()

	await get_tree().create_timer(
		catch_pause_seconds
	).timeout

	if catch_message_label:
		catch_message_label.hide()


func _on_leave_requested() -> void:
	_stop_fishing()
