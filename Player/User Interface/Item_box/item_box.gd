extends Button
class_name ItemBox

@export var held_item : Item

@export_group("User Interface")
@export var sprite : Sprite2D
@export var title_lbl : Label
@export var symbols_container : HBoxContainer

@export_group("Symbols")
@export var symbol_size : Vector2 = Vector2(16, 16)


func _ready() -> void:
	_update_display()


func config(data : Item) -> void:
	held_item = data
	_update_display()


func _update_display() -> void:
	if not held_item:
		return
	if held_item is Fish:
		sprite.texture = held_item.get_freshness_level()
	else:
		sprite.texture = held_item.icon
	title_lbl.text = held_item.display_name
	if held_item.rarity:
		title_lbl.add_theme_color_override("font_color", held_item.rarity.color)
	tooltip_text = held_item.display_name  # only used as fallback text for _make_custom_tooltip
	#_update_symbols()


func _update_symbols() -> void:
	for child in symbols_container.get_children():
		child.queue_free()

	for symbol in held_item.get_symbols():
		var texture_rect := TextureRect.new()
		texture_rect.texture = symbol
		texture_rect.custom_minimum_size = symbol_size
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		symbols_container.add_child(texture_rect)


func _make_custom_tooltip(_for_text: String) -> Object:
	if not held_item:
		return null
	var tooltip := preload("res://Player/User Interface/Item_box/item_tooltip.tscn").instantiate() as ItemTooltip
	tooltip.config(held_item)
	return tooltip