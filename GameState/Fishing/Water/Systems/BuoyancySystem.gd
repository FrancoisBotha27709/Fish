extends Node
## Place one of these anywhere in the scene (it needs no parent/child
## relationship to the water or to floating objects).
##
## Neither the water mesh nor floating objects need any reference to this
## node or to each other:
##   - The water mesh only needs WaterManager.gd on it.
##   - Floating objects only need to be added to the "floatable" group in
##     the editor (Node > Groups). No script required on them at all.
##
## This node is the only thing that knows about both. Each physics frame
## it looks at get_tree().get_nodes_in_group("floatable") — so cost is
## paid only for objects you've actually tagged, nothing else — computes
## an Archimedes-style buoyancy force from each body's collision shape,
## and spawns ripples on the water when a tagged body enters it or moves
## through it.
##
## Supports RigidBody3D (full force/torque buoyancy) and CharacterBody3D
## (a simpler velocity nudge — see the caveat in _process_character_body).
## Plain Node3D/collision-shape-only bodies are ignored for physics but
## still generate splash/wake ripples if you want a purely visual effect.

@export var water_path: NodePath           # -> MeshInstance3D running WaterManager.gd
@export var water_base_height: float = 0.0 # world-space Y of calm sea level
@export var gravity: float = 9.8

@export_group("Buoyancy")
@export var buoyancy_multiplier: float = 1.6   # >1 so bodies settle partly submerged, not fully underwater
@export var linear_drag: float = 1.2
@export var angular_drag: float = 0.6
@export var sample_corners: bool = true        # 4-corner sampling = rocking/tilting; false = cheaper single center sample

@export_group("Wake")
@export var wake_min_speed: float = 0.3
@export var wake_interval: float = 0.25
@export var wake_strength: float = 0.6
@export var splash_strength: float = 1.6

var _water: Node = null
var _half_extents_cache: Dictionary = {}  # instance_id -> Vector3, computed once per body
var _wake_timer: Dictionary = {}          # instance_id -> float
var _was_submerged: Dictionary = {}       # instance_id -> bool

func _ready() -> void:
	_water = get_node_or_null(water_path)
	if _water == null:
		push_warning("BuoyancySystem: water_path is not set or invalid; buoyancy will run but ripples won't be spawned.")

func _physics_process(delta: float) -> void:
	for body in get_tree().get_nodes_in_group("floatable"):
		if body is RigidBody3D:
			_process_rigid_body(body, delta)
		elif body is CharacterBody3D:
			_process_character_body(body, delta)
		elif body is Node3D:
			# no physics body to push around, but still ripple-react visually
			_handle_wake(body, body.global_position, _water_height_at(body.global_position) >= body.global_position.y, delta)

# ---------------------------------------------------------------- geometry

func _get_half_extents(body: Node3D) -> Vector3:
	var id := body.get_instance_id()
	if _half_extents_cache.has(id):
		return _half_extents_cache[id]

	var half_extents := Vector3(0.5, 0.5, 0.5)
	for child in body.get_children():
		if child is CollisionShape3D and child.shape:
			var aabb := _shape_local_aabb(child.shape)
			half_extents = aabb.size * 0.5 * child.scale
			break

	_half_extents_cache[id] = half_extents
	body.tree_exiting.connect(_on_floatable_freed.bind(id))
	return half_extents

func _shape_local_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		return AABB(-shape.size * 0.5, shape.size)
	if shape is SphereShape3D:
		var d = shape.radius * 2.0
		return AABB(Vector3(-shape.radius, -shape.radius, -shape.radius), Vector3(d, d, d))
	if shape is CapsuleShape3D:
		var h = shape.height
		var r = shape.radius
		return AABB(Vector3(-r, -h * 0.5, -r), Vector3(r * 2.0, h, r * 2.0))
	if shape is CylinderShape3D:
		var h2 = shape.height
		var r2 = shape.radius
		return AABB(Vector3(-r2, -h2 * 0.5, -r2), Vector3(r2 * 2.0, h2, r2 * 2.0))
	# Fallback for shapes we don't special-case (convex/concave meshes, etc).
	# Tune manually per-object if this is too rough for something important.
	return AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1.0, 1.0, 1.0))

# ------------------------------------------------------------ water height

func _water_height_at(world_pos: Vector3) -> float:
	if _water == null or not _water.has_method("get_ripple_height_at"):
		return water_base_height
	return water_base_height + _water.get_ripple_height_at(Vector2(world_pos.x, world_pos.z))

# ------------------------------------------------------------- rigid body

func _process_rigid_body(body: RigidBody3D, delta: float) -> void:
	var half := _get_half_extents(body)
	var origin: Vector3 = body.global_position
	var basis: Basis = body.global_transform.basis

	var corners: Array[Vector3] = [Vector3.ZERO]
	if sample_corners:
		corners = [
			basis * Vector3(half.x, 0, half.z),
			basis * Vector3(-half.x, 0, half.z),
			basis * Vector3(half.x, 0, -half.z),
			basis * Vector3(-half.x, 0, -half.z),
		]

	var any_submerged := false
	var max_ratio := 0.0
	var force_per_sample := (body.mass * gravity * buoyancy_multiplier) / corners.size()

	for offset in corners:
		var world_pos: Vector3 = origin + offset
		var water_y := _water_height_at(world_pos)
		var bottom_y := world_pos.y - half.y
		var submersion: float = clamp((water_y - bottom_y) / max(half.y * 2.0, 0.001), 0.0, 1.0)
		if submersion <= 0.0:
			continue
		any_submerged = true
		max_ratio = max(max_ratio, submersion)
		body.apply_force(Vector3(0, force_per_sample * submersion, 0), offset)

	if any_submerged:
		# extra vertical drag so it settles instead of bobbing forever
		body.apply_central_force(Vector3(0, -body.linear_velocity.y * linear_drag * max_ratio * body.mass, 0))
		body.apply_torque(-body.angular_velocity * angular_drag * body.mass)

	_handle_wake(body, origin, any_submerged, delta)

# --------------------------------------------------------- character body

func _process_character_body(body: CharacterBody3D, delta: float) -> void:
	var half := _get_half_extents(body)
	var origin: Vector3 = body.global_position
	var water_y := _water_height_at(origin)
	var bottom_y := origin.y - half.y
	var submersion: float = clamp((water_y - bottom_y) / max(half.y * 2.0, 0.001), 0.0, 1.0)

	if submersion > 0.0:
		# Simple buoyant push, applied directly to velocity.y. CAVEAT: if this
		# body has its own movement script that also sets velocity.y every
		# physics frame (gravity, jumping, swimming state...), the two will
		# fight based on node process order. Either:
		#   - lower this node's Process Priority so it runs before the
		#     controller and the controller reads/respects the result, or
		#   - skip this automatic push (delete this if-block) and instead
		#     have the controller call this node's get_submersion(body)
		#     itself and decide how to react.
		body.velocity.y = lerp(body.velocity.y, gravity * 0.6, clamp(submersion * delta * 4.0, 0.0, 1.0))

	_handle_wake(body, origin, submersion > 0.0, delta)

## Optional query for character controllers that want to handle their own
## swimming logic instead of the automatic push above.
func get_submersion(body: Node3D) -> float:
	var half := _get_half_extents(body)
	var origin: Vector3 = body.global_position
	var water_y := _water_height_at(origin)
	var bottom_y := origin.y - half.y
	return clamp((water_y - bottom_y) / max(half.y * 2.0, 0.001), 0.0, 1.0)

# ------------------------------------------------------------------ wake

func _handle_wake(body: Node3D, world_pos: Vector3, submerged: bool, delta: float) -> void:
	var id := body.get_instance_id()
	var was: bool = _was_submerged.get(id, false)

	if submerged and not was:
		_spawn_ripple(world_pos, splash_strength)
		_wake_timer[id] = 0.0
	_was_submerged[id] = submerged

	if not submerged:
		return

	var speed := 0.0
	if body is RigidBody3D:
		speed = Vector2(body.linear_velocity.x, body.linear_velocity.z).length()
	elif body is CharacterBody3D:
		speed = Vector2(body.velocity.x, body.velocity.z).length()

	if speed < wake_min_speed:
		return

	_wake_timer[id] = _wake_timer.get(id, 0.0) + delta
	if _wake_timer[id] >= wake_interval:
		_wake_timer[id] = 0.0
		_spawn_ripple(world_pos, clamp(speed / 10.0, 0.2, 1.0) * wake_strength)

func _spawn_ripple(world_pos: Vector3, strength: float) -> void:
	if _water and _water.has_method("spawn_ripple"):
		_water.spawn_ripple(world_pos, strength)

# --------------------------------------------------------------- cleanup

func _on_floatable_freed(id: int) -> void:
	_half_extents_cache.erase(id)
	_wake_timer.erase(id)
	_was_submerged.erase(id)
