extends Resource
class_name FishSpecies

@export_group("General")
@export var display_name: String
@export var scientific_name: String

@export_group("Economy")
@export var base_price_per_kg: float = 10.0
@export var rarity_multiplier: float = 1.0

@export_group("Biology")
@export var normal_weight: float = 1.0
@export var minimum_weight: float = 0.5
@export var maximum_weight: float = 5.0

@export_group("Visual")
@export var icon: Texture2D
@export var mesh: PackedScene
