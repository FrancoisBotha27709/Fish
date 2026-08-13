extends Resource
class_name Item

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var tags: Array[String]
@export var rarity : Rarity
@export var icon: Texture2D
@export var world_scene: PackedScene

func get_value() -> float:
	return 0.0

func get_description() -> String:
	return description
