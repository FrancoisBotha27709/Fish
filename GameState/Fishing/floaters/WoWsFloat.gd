extends Node3D
## Drop this as a child of any moving object that should disturb the water
## (ship hull, floating crate, character wading, dropped shell, etc).
## Set `water_path` to the MeshInstance3D running WaterManager.gd.
##
## This is a minimal example, not a full wake simulation — swap the
## _physics_process logic for whatever detection makes sense for your
## object (Area3D overlap, raycast to water plane, etc).

@export var water_path: NodePath
@export var water_height: float = 0.0       # world-space Y of the water surface
@export var wake_interval: float = 0.25     # seconds between wake ripples while moving through water
@export var min_speed_for_wake: float = 0.3 # m/s, below this no wake is emitted
@export var wake_strength: float = 0.6
@export var splash_strength: float = 1.6    # one-off ripple strength when first entering the water

var _water: Node = null
var _timer := 0.0
var _last_pos: Vector3
var _was_submerged := false

func _ready() -> void:
	_water = get_node_or_null(water_path)
	if _water == null:
		push_warning("WaterWakeSource: water_path is not set or invalid.")
	_last_pos = global_position

func _physics_process(delta: float) -> void:
	if _water == null:
		return

	var pos := global_position
	var speed = (pos - _last_pos).length() / max(delta, 0.0001)
	_last_pos = pos

	var submerged := pos.y <= water_height
	if submerged and not _was_submerged:
		# just crossed into the water — one splash ripple
		_water.spawn_ripple(pos, splash_strength)
		_timer = 0.0
	_was_submerged = submerged

	if submerged and speed > min_speed_for_wake:
		_timer += delta
		if _timer >= wake_interval:
			_timer = 0.0
			var strength: float = clamp(speed / 10.0, 0.2, 1.0) * wake_strength
			_water.spawn_ripple(pos, strength)
