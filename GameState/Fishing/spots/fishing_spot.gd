extends Area3D
class_name FishingSpotObject
## Owns the fish count and the lantern. It does NOT hold any minigame UI: it only
## tells the player which minigame to play, then deducts fish as the player
## reports catches.

signal spot_depleted()
signal fish_removed()

@export_group("Objects")
@export var collision: CollisionShape3D
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

	if data_resource.minigame == null:
		push_error("FishingSpot '%s' has no minigame assigned." % data_resource.display_name)
		return

	_setup_popup()
	_setup_lantern_flicker()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


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
	_confirm_popup.title = "Fishing Spot"
	_confirm_popup.get_ok_button().text = "Yes"
	_confirm_popup.get_cancel_button().text = "No"

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
		"There are %d %s fish here. Try the fishing minigame?"
		% [
			data_resource.current_amount_available,
			data_resource.display_name
		]
	)

	_confirm_popup.popup_centered()


func _on_body_exited(body: Node3D) -> void:
	if body != player:
		return

	# Only the "Want to fish?" prompt goes away. A running minigame is never
	# stopped from here; the player leaves it with the minigame's leave button.
	if _confirm_popup:
		_confirm_popup.hide()


func _on_fish_confirmed() -> void:
	_start_fishing()


func _on_fish_declined() -> void:
	pass


func _start_fishing() -> void:
	if player == null or player.playing_minigame:
		return

	if not data_resource.has_fish():
		return

	_connect_player()
	_fishing_active = true

	data_resource.minigame.active_fish = data_resource.active_fish
	player.start_minigame(data_resource.minigame, self)


## Connected lazily because `player` can be assigned after _ready().
func _connect_player() -> void:
	if not player.minigame_fish_caught.is_connected(_on_player_fish_caught):
		player.minigame_fish_caught.connect(_on_player_fish_caught)

	if not player.minigame_ended.is_connected(_on_player_minigame_ended):
		player.minigame_ended.connect(_on_player_minigame_ended)


func _on_player_fish_caught(_fish: Fish) -> void:
	if not _fishing_active:  # another spot's session
		return

	if not data_resource.catch_one():
		return

	# Remove one visible fish.
	fish_removed.emit()

	if not data_resource.has_fish():
		_fishing_active = false
		player.end_minigame()
		spot_depleted.emit()


func _on_player_minigame_ended() -> void:
	_fishing_active = false