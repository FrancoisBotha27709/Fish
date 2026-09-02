extends Control
class_name UserInterface

@export_group("User Interface")
@export var end_day_btn : Button
@export var end_night_btn : Button
@export var view_radial_btn : Button
@export_subgroup("Inventory")
@export var inventory_lbl : Label
@export var inventory_grid : GridContainer
@export var inventory_radial : RadialMenuAdvanced
@export var inventory_button : PackedScene
@export_subgroup("Market")
@export var player_market : PlayerMarket   ## only assigned in the Market scene
@export var dialog_lbl : Label             ## shows what the customer is saying
@export var price_slider : Slider          ## draggable bar the player sets the price with
@export var money_label : RichTextLabel
@export var offer_btn : Button             ## confirms the current slider value
@export_subgroup("Preview", "preview_")
@export var preview_label : RichTextLabel
@export var preview_symbol_container : HBoxContainer
@export var preview_description : RichTextLabel
@export var preview_sprite : Sprite2D


var offer_value : float = 0.0
var _viewing : bool = false

func _ready() -> void:
	inventory_radial.visible = false
	inventory_radial.scale = Vector2.ZERO

	end_day_btn.pressed.connect(_on_end_day_btn_pressed)
	end_night_btn.pressed.connect(_on_end_night_btn_pressed)
	view_radial_btn.pressed.connect(_on_radial_btn_pressed)

	if player_market:
		player_market.negotiation_started.connect(_on_negotiation_started)
		player_market.negotiation_started.connect(_preview_item)
		player_market.dialog_updated.connect(_on_dialog_updated)
		player_market.deal_finished.connect(_on_deal_finished)

	if price_slider:
		price_slider.value_changed.connect(_on_price_slider_value_changed)
	if offer_btn:
		offer_btn.pressed.connect(_on_offer_btn_pressed)


func _on_end_day_btn_pressed() -> void:
	# Time set night
	get_tree().change_scene_to_file("res://GameState/Fishing/Fishing.tscn")


func _on_end_night_btn_pressed() -> void:
	# Time set night
	get_tree().change_scene_to_file("res://GameState/Market/game.tscn")

func _on_radial_btn_pressed() -> void:
	_viewing = !_viewing

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	if _viewing:
		inventory_radial.visible = true
		inventory_radial.scale = Vector2.ZERO
		tween.tween_property(
			inventory_radial,
			"scale",
			Vector2.ONE,
			0.1
		)
	else:
		tween.tween_property(
			inventory_radial,
			"scale",
			Vector2.ZERO,
			0.1
		)
		tween.tween_callback(func():
			inventory_radial.visible = false
		)

## Rebuilds the inventory grid AND the radial menu's category popouts from
## scratch, so neither ever shows stale/sold items.
func set_items(items : Array[Item]) -> void:
	for child in inventory_grid.get_children():
		child.queue_free()

	for i in items:
		var ib := inventory_button.instantiate()
		ib.held_item = i
		inventory_grid.add_child(ib)

	_populate_radial_inventory(items)


## Finds whichever RadialCategorySlot (a direct child of inventory_radial)
## shares the most tags with the item's own tags. Ties go to whichever
## matching slot appears first. Returns null if no slot shares any tag at all.
func _find_best_category_slot(item : Item) -> RadialCategorySlot:
	var best_slot : RadialCategorySlot = null
	var best_score := 0

	for child in inventory_radial.get_children():
		var slot := child as RadialCategorySlot
		if slot == null:
			continue

		var score := slot.match_score(item.tags)
		if score > best_score:
			best_score = score
			best_slot = slot

	return best_slot


## Clears only the item boxes a previous call to this function added to each
## radial category slot — identified by the "held_item" property every
## inventory button exposes — and leaves everything else (the slot's own
## icon/label, or any other node someone put there) completely untouched.
## Freed immediately (not queue_free()) so a re-populate can never run while
## the old boxes are still sitting in the tree, which is what was causing
## items to briefly show twice.
func _clear_radial_item_boxes(slots : Array[RadialCategorySlot]) -> void:
	for slot in slots:
		for child in slot.get_children():
			if "held_item" in child:
				child.free()


## Re-adds one item box per item, routed by tag overlap via
## _find_best_category_slot(). New boxes start hidden, matching how
## RadialMenuAdvanced expects un-popped-out grandchildren to look; it makes
## them visible itself once that category is hovered.
func _populate_radial_inventory(items : Array[Item]) -> void:
	if inventory_radial == null:
		return

	var slots : Array[RadialCategorySlot] = []
	for child in inventory_radial.get_children():
		var slot := child as RadialCategorySlot
		if slot != null:
			slots.append(slot)

	if slots.is_empty():
		push_error(
			"UserInterface: no RadialCategorySlot children found under inventory_radial. " +
			"Make sure every top-level radial item has radial_category_slot.gd attached " +
			"(Inspector > Script), and that they're direct children of inventory_radial."
		)
		return

	_clear_radial_item_boxes(slots)

	for item in items:
		var slot := _find_best_category_slot(item)
		if slot == null:
			push_warning("No radial category matches any tag for item '%s' (tags: %s). Check each RadialCategorySlot's 'tags' export is set." % [item.display_name, item.tags])
			continue

		var ib := inventory_button.instantiate()
		ib.held_item = item
		ib.visible = false
		slot.add_child(ib)


## Every currently-instantiated item box, across both the inventory grid and
## all radial category popouts, so highlighting can treat both views the same.
func _all_item_boxes() -> Array:
	var boxes : Array = []
	boxes.append_array(inventory_grid.get_children())

	if inventory_radial:
		for child in inventory_radial.get_children():
			var slot := child as RadialCategorySlot
			if slot == null:
				continue
			for grandchild in slot.get_children():
				if "held_item" in grandchild:
					boxes.append(grandchild)

	return boxes


## Enables only the button for the item the customer is asking for; disables the
## rest so the player can't try to sell the wrong fish mid-negotiation.
func _highlight_requested_item(want_item : Item) -> void:
	for child in _all_item_boxes():
		if not ("held_item" in child) or not ("disabled" in child):
			continue
		child.disabled = child.held_item != want_item


## Re-enables every inventory button once there's no active negotiation.
func _clear_inventory_highlight() -> void:
	for child in _all_item_boxes():
		if "disabled" in child:
			child.disabled = false


## A new customer's item + opening offer are known: set up the dialog, slider
## range, and inventory highlight for this negotiation.
func _on_negotiation_started(customer : Customer) -> void:
	dialog_lbl.text = "%s wants your %s" % [customer.display_name, customer.ask_item()]

	if price_slider and customer.want_item:
		var value := customer.want_item.get_value()
		price_slider.min_value = value * 0.5
		price_slider.max_value = value * 2.0
		price_slider.value = customer.get_current_offer()

	_highlight_requested_item(customer.want_item)


func _on_dialog_updated(text : String) -> void:
	if dialog_lbl and not text.is_empty():
		dialog_lbl.text = text


## Player dragged the price bar.
func _on_price_slider_value_changed(value : float) -> void:
	player_market.set_requested_amount(value)
	offer_btn.text = "Offer $%0.2d" % value
	offer_value = value

## Player confirmed the price — let the customer evaluate it.
func _on_offer_btn_pressed() -> void:
	player_market.try_haggle()


## A customer is fully resolved (sold or walked away): refresh the inventory
## (the sold fish is gone from UtilityStates.items) and unlock every button.
func _on_deal_finished() -> void:
	set_items(UtilityStates.items)
	UtilityStates.money += offer_value
	_clear_inventory_highlight()
	_clear_preview()
	money_label.text = "Money: [color=light_green][b][i]$%0.2d[/i][/b][/color]" % UtilityStates.money

func _preview_item(customer : Customer) -> void:
	_clear_preview()
	var item : Item = customer.want_item
	preview_label.text = "[color=%s][b]%s[/b][/color] [i](%s)[/i]" % [item.rarity.color.to_html(), item.display_name, item.rarity.display_name]
	# for symbol in customer.want_item.get_symbols():
	# 	var sprite : Sprite2D = Sprite2D.new()
	# 	sprite.texture = symbol
	# 	preview_symbol_container.add_child(sprite)
	preview_description.text = item.get_description()
	preview_sprite.texture = item.icon

func _clear_preview() -> void:
	preview_description.text = "[color=red]Please[/color] wait for someone to show up"
	preview_label.text = "Nothing of note..."
	preview_sprite.texture = null
	if preview_symbol_container.get_children() != []:
		for child in preview_symbol_container:
			child.queue_free()
