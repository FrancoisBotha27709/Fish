extends Area3D
class_name FishingSpotObject

signal spot_depleted()
signal fish_removed()

@export_group("Objects")
@export var collision: CollisionShape3D
@export var popup_window: PopupPanel  ## the minigame scene is spawned as a child of this
@export var lantern_light : MeshInstance3D
@export var lantern_light_rotater : Node3D

@export_group("Lantern Flicker")
@export var flicker_enabled := true
@export var base_emission_energy := 2.0
@export var flicker_amplitude := 0.6   ## how far it can swing above/below base
@export var flicker_speed := 8.0       ## how fast it changes (higher = jittery)
@export var flicker_smoothness := 10.0 ## higher = smoother interpolation

@export_group("Data")
@export var data_resource: FishingSpot

@export_group("Outside Data")
@export var player: PlayerFish

@export_group("Catch Feedback")
@export var catch_pause_seconds := 1.2
@export var catch_message_label: Label

## Spawned from data_resource.minigame.scene in _ready().
var minigame: FishingMinigame

var _lantern_material: StandardMaterial3D
var _flicker_noise := FastNoiseLite.new()
var _flicker_time := 0.0
var _current_energy := 0.0
var _confirm_popup: ConfirmationDialog
var _fishing_active := false


func _ready() -> void:
	if data_resource == null:
		push_error("FishingSpotObject has no data_resource assigned.")
		return

	if popup_window == null:
		push_error("FishingSpotObject has no popup_window assigned.")
		return

	if not _spawn_minigame():
		return

	_sync_minigame_data()
	minigame.stop()
	_setup_popup()
	_setup_lantern_flicker()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Instantiates the minigame scene held by the Minigame resource and parents
## it to the popup. Done once; start()/stop() reuse the same instance.
func _spawn_minigame() -> bool:
	var minigame_data := data_resource.minigame
	if minigame_data == null or minigame_data.scene == null:
		push_error("FishingSpot '%s' has no minigame, or the minigame has no scene." % data_resource.display_name)
		return false

	var instance := minigame_data.scene.instantiate()
	if not instance is FishingMinigame:
		push_error("Minigame scene root for '%s' isn't a FishingMinigame." % data_resource.display_name)
		instance.queue_free()
		return false

	minigame = instance
	popup_window.add_child(minigame)  # its _ready() runs here

	minigame.fish_caught.connect(_on_fish_caught)
	minigame.leave_requested.connect(_on_leave_requested)
	return true


## Tells the Minigame resource which fish is being caught. The minigame never
## knows how many are left; this spot decides when to stop it.
func _sync_minigame_data() -> void:
	data_resource.minigame.active_fish = data_resource.active_fish


func _setup_lantern_flicker() -> void:
	if lantern_light == null:
		return

	var mat := lantern_light.get_surface_override_material(0)
	if mat == null:
		push_warning("Lantern has no surface material override on surface 0.")
		return

	if mat is StandardMaterial3D:
		_lantern_material = mat
	else:
		push_warning("Lantern surface material override is not a StandardMaterial3D.")
		return

	_flicker_noise.seed = randi()
	_flicker_noise.frequency = 1.0
	_current_energy = base_emission_energy


func rotate_lantern_light(delta: float) -> void:
	lantern_light_rotater.rotate_y(deg_to_rad(360.0 / 10.0) * delta)


func _process(delta: float) -> void:
	if not flicker_enabled or _lantern_material == null:
		return

	_flicker_time += delta * flicker_speed
	rotate_lantern_light(delta)
	# Sample smooth noise in range [-1, 1] and scale it into our flicker range.
	var noise_value := _flicker_noise.get_noise_1d(_flicker_time)
	var target_energy := base_emission_energy + noise_value * flicker_amplitude

	# Smoothly interpolate toward the target so it doesn't feel like it's snapping.
	_current_energy = lerp(_current_energy, target_energy, clamp(delta * flicker_smoothness, 0.0, 1.0))

	_lantern_material.emission_energy_multiplier = _current_energy


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

	popup_window.hide()

	if _confirm_popup:
		_confirm_popup.hide()

	_stop_fishing()


func _on_fish_confirmed() -> void:
	_start_fishing()


func _on_fish_declined() -> void:
	pass


func _start_fishing() -> void:
	if not data_resource.has_fish():
		return

	_fishing_active = true

	popup_window.show()

	if player:
		player.start_minigame()

	_sync_minigame_data()
	minigame.start(data_resource.minigame)


func _stop_fishing() -> void:
	_fishing_active = false

	if player:
		player.end_minigame()

	minigame.stop()
	popup_window.hide()

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

	_sync_minigame_data()
	minigame.start(data_resource.minigame)


func _celebrate_catch() -> void:
	if catch_message_label:
		catch_message_label.text = "Nice catch!"
		catch_message_label.show()

	await get_tree().create_timer(catch_pause_seconds).timeout

	if catch_message_label:
		catch_message_label.hide()


func _on_leave_requested() -> void:
	_stop_fishing()