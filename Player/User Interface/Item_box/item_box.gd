extends Button
class_name ItemBox

@export var held_item : Item

@export_group("User Interface")
@export var sprite : Sprite2D
@export var title_lbl : Label

func _ready() -> void:
	title_lbl.text = held_item.display_name
	sprite.texture = held_item.icon

func config(data : Item) -> void:
	held_item = data
	tooltip_text = "[color=#%s]%s[/color]\n%s" % [
		data.rarity.color.to_html(),
		data.display_name,
		data.get_description()
	]

func _make_custom_tooltip(for_text: String) -> Object:
	var tooltip := preload("res://Player/User Interface/Item_box/item_tooltip.tscn").instantiate() as ItemTooltip
	tooltip.config(held_item, for_text)
	return tooltip
