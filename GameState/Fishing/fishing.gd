extends Node3D
class_name GameFish
@export var player : PlayerFish

@export var world_origin_poi : Marker3D
@export var world_borders : Array[WorldBorder]
func _ready() -> void:
    if world_origin_poi:
        for wb in world_borders:
            wb.return_target = world_origin_poi
