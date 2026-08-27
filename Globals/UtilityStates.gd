extends Node

signal item_added(item : Item)
signal item_removed(item : Item)
signal inventory_changed()

var items : Array[Item] = []
var requests : Array[String] = []
const SALMON_FISH = preload("uid://db5u6fhyhwtf2")

func _ready() -> void:
	add_item(SALMON_FISH)
	add_item(SALMON_FISH)

func add_item(item : Item) -> void:
	items.append(item)
	item_added.emit(item)
	inventory_changed.emit()

func remove_item(item : Item) -> bool:
	var idx := items.find(item)
	if idx == -1:
		return false
	
	items.remove_at(idx)
	item_removed.emit(item)
	inventory_changed.emit()
	return true

func get_items_by_tag(tag : String) -> Array[Item]:
	return items.filter(func(i: Item) -> bool: return tag in i.tags)

func get_total_value() -> float:
	var total := 0.0
	for item in items:
		total += item.get_value()
	return total
