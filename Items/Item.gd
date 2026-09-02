extends Resource
class_name Item

@export var id: String
@export var display_name: String
@export_multiline var description: String
@export var tags: Array[String]
@export var rarity : Rarity
@export var icon: Texture2D
@export var world_scene: PackedScene
@export var outside_mesh_scene : PackedScene

@export_group("Symbols")
## The icon representing this item's category (e.g. fish, chest, key).
## Set this per item resource so every instance carries it automatically.
@export var category_symbol : Texture2D

func get_value() -> float:
	return 0.0

func get_description() -> String:
	return description

## Base symbol set for any item. Subclasses should call super.get_symbols()
## and append their own category-specific symbols on top.
func get_symbols() -> Array[Texture2D]:
	var symbols : Array[Texture2D] = []
	symbols.append(category_symbol)
	return symbols