extends Node

signal item_added(item : Item)
signal item_removed(item : Item)
signal inventory_changed()

var items : Array[Item] = []
var requests : Array[String] = []
var tiers : Array[Rarity] = []
var money : float = 0.0
const COMMON = preload("uid://eiexci1n8x7x")
# add one const per tier as you create the .tres resources, e.g.:
# const UNCOMMON = preload("uid://...")
# const RARE = preload("uid://...")
# const LEGENDARY = preload("uid://...")

const SALMON_FISH = preload("uid://db5u6fhyhwtf2")


func _ready() -> void:
	tiers = [COMMON]  # add UNCOMMON, RARE, LEGENDARY etc. here as you create them
	tiers.sort_custom(func(a: Rarity, b: Rarity) -> bool: return a.level < b.level)
	add_item(SALMON_FISH)
	add_item(SALMON_FISH)
	add_item(SALMON_FISH)

## Picks a tier using a 0..1 roll, where 0.0 always resolves to the lowest
## tier (tiers[0], e.g. Common) and 1.0 always resolves to the highest
## (e.g. Legendary). Bias the roll before calling this to make rare tiers rare.
func pick_rarity_by_roll(roll: float) -> Rarity:
	if tiers.is_empty():
		return null
	var index := int(clamp(roll, 0.0, 1.0) * tiers.size())
	index = clamp(index, 0, tiers.size() - 1)
	return tiers[index]


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