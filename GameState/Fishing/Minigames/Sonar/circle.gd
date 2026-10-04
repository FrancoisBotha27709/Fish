extends Control
class_name SonarCircle

## Emitted when the bar finishes sweeping over a target
signal bar_passed(target : Node2D)

@export_range(0.1, 360.0) var rotation_speed : float = 30.0: ## degrees per second
	set(value):
		rotation_speed = value
		_speed_rad = deg_to_rad(value)

@export_group("Circle")
@export var perimiter_length : float = 1.0
@export var num_sides : int = 6

@export_group("Visuals")
@export var bar : Area2D
@export var polygon : Polygon2D

## Circumradius of the generated shape (set in _generate_circle).
var radius : float = 0.0
## The blip currently holding a QTE prompt, if any. Only one at a time.
var active_qte : Node = null

var _speed_rad : float = deg_to_rad(30.0)


func _ready() -> void:
	_speed_rad = deg_to_rad(rotation_speed)
	# Blips are Area2Ds, so area_exited is all we need.
	bar.area_exited.connect(_on_bar_exited)
	_generate_circle()
	set_process(false)  # the minigame turns the sweep on via set_running()


func _process(delta : float) -> void:
	bar.rotation += _speed_rad * delta


## Starts/stops the sweep. Starting also restarts the bar at angle 0.
func set_running(running : bool) -> void:
	if running:
		bar.rotation = 0.0
		active_qte = null
	set_process(running)


func _generate_circle() -> void:
	var line_length : float = (perimiter_length * 10.0) / num_sides
	radius = line_length / (2.0 * sin(PI / num_sides))

	var points := PackedVector2Array()
	points.resize(num_sides)
	for i in num_sides:
		var angle : float = -TAU * i / num_sides
		points[i] = Vector2(cos(angle), sin(angle)) * radius
	polygon.polygon = points


## Center of the drawn circle, in this node's local space. Accounts for the
## polygon's position, scale and offset, so it's right wherever you put it.
func get_center() -> Vector2:
	return polygon.transform * polygon.offset


## Radius of the drawn circle in this node's local space (includes polygon scale).
func get_scaled_radius() -> float:
	return radius * absf(polygon.scale.x)


## Returns `count` points inside the circle, uniformly distributed by area and
## kept at least `min_separation_frac * radius` apart where possible.
func get_spawn_points(count : int, min_separation_frac : float = 0.2,
		min_frac : float = 0.4, max_frac : float = 0.9) -> PackedVector2Array:
	var points := PackedVector2Array()
	var center := get_center()
	var scaled_radius := get_scaled_radius()
	var min_dist_sq : float = pow(scaled_radius * min_separation_frac, 2.0)
	var r_min_sq : float = min_frac * min_frac
	var r_max_sq : float = max_frac * max_frac

	for i in count:
		var candidate := Vector2.ZERO
		for attempt in 20:
			var angle : float = randf() * TAU
			var dist : float = scaled_radius * sqrt(randf_range(r_min_sq, r_max_sq))
			candidate = center + Vector2(cos(angle), sin(angle)) * dist
			var ok := true
			for p in points:
				if p.distance_squared_to(candidate) < min_dist_sq:
					ok = false
					break
			if ok:
				break
		points.append(candidate)  # last candidate is used if no spot was free
	return points


func _on_bar_exited(target : Area2D) -> void:
	bar_passed.emit(target)