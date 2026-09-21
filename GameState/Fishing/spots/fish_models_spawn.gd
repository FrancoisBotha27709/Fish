extends Marker3D
class_name FishModelsSpawnPoint

@export_group("Movement")
@export var swim_radius := 10.0
@export var swim_speed := 5.0

var fishing_spot: FishingSpotObject
var active_models: Array[FishSwimmer] = []


func _ready() -> void:
	fishing_spot = get_parent() as FishingSpotObject

	if fishing_spot == null:
		push_error(
			"FishModelsSpawnPoint must be a direct child of FishingSpotObject."
		)
		return

	await get_tree().process_frame

	if not is_instance_valid(fishing_spot.data_resource):
		push_error("FishingSpotObject has no data_resource assigned.")
		return

	if not fishing_spot.fish_removed.is_connected(_on_fish_removed):
		fishing_spot.fish_removed.connect(_on_fish_removed)

	if not fishing_spot.spot_depleted.is_connected(_on_spot_depleted):
		fishing_spot.spot_depleted.connect(_on_spot_depleted)

	_spawn_fish_from_spot()


func _spawn_fish_from_spot() -> void:
	var spot_data := fishing_spot.data_resource

	if spot_data.active_fish == null:
		push_warning("Fishing spot has no active fish.")
		return

	var fish_data: Fish = spot_data.active_fish

	if fish_data.outside_mesh_scene == null:
		push_error("Active Fish resource has no outside_mesh_scene.")
		return

	var fish_count := maxi(
		spot_data.current_amount_available,
		0
	)

	for i in range(fish_count):
		var fish_instance := (
			fish_data.outside_mesh_scene.instantiate()
			as FishSwimmer
		)

		if fish_instance == null:
			push_error(
				"outside_mesh_scene must have a FishSwimmer root node."
			)
			continue

		# Save the center before adding the node.
		var fish_center := global_position

		fish_instance.setup(
			fish_center,
			swim_radius,
			swim_speed
		)

		# A node must be inside the scene tree before using global_position.
		get_tree().current_scene.add_child(fish_instance)

		fish_instance.global_position = (
			fish_instance.get_start_position()
		)

		active_models.append(fish_instance)


func _on_fish_removed() -> void:
	while not active_models.is_empty():
		var fish_instance = active_models.pop_back()

		if is_instance_valid(fish_instance):
			fish_instance.queue_free()
			return


func _on_spot_depleted() -> void:
	for fish_instance in active_models:
		if is_instance_valid(fish_instance):
			fish_instance.queue_free()

	active_models.clear()


func _exit_tree() -> void:
	for fish_instance in active_models:
		if is_instance_valid(fish_instance):
			fish_instance.queue_free()

	active_models.clear()
