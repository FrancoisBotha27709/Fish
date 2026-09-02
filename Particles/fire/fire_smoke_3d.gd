extends Node3D
class_name FireSmoke

@export_group("Particles")

@export_subgroup("Smoke")
@export var particle_smoke: GPUParticles3D
@export var base_smoke_amount: int = 8
@export var smoke_change_speed: float = 10.0

@export_subgroup("Fire")
@export var particle_fire: GPUParticles3D
@export var base_fire_amount: int = 8
@export var fire_change_speed: float = 10.0

var _smoke_amount: float
var _fire_amount: float


func _ready() -> void:
	_smoke_amount = particle_smoke.amount
	_fire_amount = particle_fire.amount


func increase_smoke(smoke_amount: int, delta: float) -> void:
	_smoke_amount = move_toward(_smoke_amount, smoke_amount, smoke_change_speed * delta)
	particle_smoke.amount = roundi(_smoke_amount)


func decrease_smoke(smoke_amount: int, delta: float) -> void:
	_smoke_amount = move_toward(_smoke_amount, smoke_amount, smoke_change_speed * delta)
	particle_smoke.amount = roundi(_smoke_amount)


func increase_fire(fire_amount: int, delta: float) -> void:
	_fire_amount = move_toward(_fire_amount, fire_amount, fire_change_speed * delta)
	particle_fire.amount = roundi(_fire_amount)


func decrease_fire(fire_amount: int, delta: float) -> void:
	_fire_amount = move_toward(_fire_amount, fire_amount, fire_change_speed * delta)
	particle_fire.amount = roundi(_fire_amount)
