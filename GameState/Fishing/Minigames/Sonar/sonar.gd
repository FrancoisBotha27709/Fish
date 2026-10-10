extends FishingMinigame
class_name SonarMinigame

@export var circle : SonarCircle
@export var blip_scene : PackedScene
@export var base_rotation_speed : float = 30.0  ## degrees/sec at difficulty 1.0
@export var base_steps : int = 3                ## QTE steps per blip at difficulty 1.0
@export var min_blips : int = 2                 ## blips on the radar each round (random between min and max)
@export var max_blips : int = 4
@export var max_misses : int = 3                ## misses allowed per fish before the minigame is failed

var _pool : Array[Blip] = []     ## every blip ever created, reused between rounds
var _active_count : int = 0      ## first N blips of the pool are in play
var _steps_per_blip : int = 3
var _misses : int = 0


func _ready() -> void:
	super._ready()
	# Pre-warm one blip so the first round doesn't hitch.
	_get_blip(0)


# Progress is pushed by QTE events (see _refresh_progress), not polled every frame.
func _advance_progress(_delta : float) -> void:
	pass


func _on_apply_difficulty(scale : float) -> void:
	circle.rotation_speed = base_rotation_speed * scale
	_steps_per_blip = maxi(1, roundi(base_steps * scale))


func _on_start() -> void:
	_misses = 0
	circle.set_running(true)
	_activate_blips(randi_range(maxi(1, min_blips), maxi(min_blips, max_blips)))


func _on_catch() -> void:
	_deactivate_blips()


func _on_fail() -> void:
	_deactivate_blips()
	circle.set_running(false)


func _on_stop() -> void:
	_deactivate_blips()
	circle.set_running(false)


## Returns the pooled blip at `index`, creating it if the pool is too small.
func _get_blip(index : int) -> Blip:
	while _pool.size() <= index:
		var blip := blip_scene.instantiate() as Blip
		blip.sonar = circle  # set before add_child so the blip skips its tree search
		circle.add_child(blip)
		blip.step_completed.connect(_on_blip_step_completed)
		blip.caught.connect(_on_blip_caught)
		blip.failed.connect(_on_blip_failed)
		_pool.append(blip)
	return _pool[index]


func _activate_blips(amount : int) -> void:
	_deactivate_blips()
	var points := circle.get_spawn_points(amount)
	for i in amount:
		_get_blip(i).activate(points[i], _steps_per_blip)
	_active_count = amount


func _deactivate_blips() -> void:
	for i in _active_count:
		_pool[i].deactivate()
	_active_count = 0
	if circle:
		circle.active_qte = null


func _set_progress(value : float) -> void:
	if minigame == null:
		return
	minigame.current_progress = value
	catch_progress_bar.value = value
	catching_progress_changed.emit(value, minigame.goal_progress)


## The bar follows the most advanced blip, and drops when blips retreat. It stops
## just short of full until a blip is actually caught (after its final slide).
func _refresh_progress() -> void:
	if minigame == null:
		return
	var best := 0.0
	for i in _active_count:
		best = maxf(best, _pool[i].get_progress())
	_set_progress(minigame.goal_progress * minf(best, 0.99))


func _on_blip_step_completed(_done : int, _total : int) -> void:
	_refresh_progress()


func _on_blip_caught(_blip : Blip) -> void:
	if minigame == null:
		return
	# Stop further prompts this frame, then complete; the base class's
	# _physics_process sees is_complete() and runs _catch_fish() for us.
	for i in _active_count:
		_pool[i].active = false
	_set_progress(minigame.goal_progress)


## Any failed QTE (wrong button or a blip fading unanswered) is a miss.
func _on_blip_failed(_blip : Blip) -> void:
	if not started or minigame == null:
		return

	_misses += 1
	if _misses >= max_misses:
		_fail_minigame()  # base class: stops the round and emits minigame_failed
		return

	for i in _active_count:  # punish: EVERY blip loses a step
		_pool[i].retreat_one_step()
	_refresh_progress()