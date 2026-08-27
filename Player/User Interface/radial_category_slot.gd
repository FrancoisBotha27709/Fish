extends Control
class_name RadialCategorySlot

## The set of tags this radial category represents. For example, a "Fish"
## slot might just use ["fish"], while a more specific slot could use
## ["fish", "rotting"] to preferentially catch spoiled fish over fresh ones.
##
## Inventory items are routed to whichever RadialCategorySlot shares the most
## tags with the item's own tags — never by matching an id or name.
@export var tags: Array[String] = []

## Icon shown while this slot is NOT hovered/selected. Assign in the editor
## (drag the child node into this slot in the Inspector).
@export var icon: Sprite2D = null
## Label shown while this slot IS the hovered/selected one on the wheel.
## Assign in the editor (drag the child node into this slot in the Inspector).
@export var label: Label = null

## The popout's background panel, shown behind the row of item boxes once
## this slot is hovered. This must be a direct child added ON TOP of this
## slot's own instanced scene (i.e. a sibling you add after instancing the
## category scene under the radial menu, NOT part of the category scene's
## own Icon/Label). Assign it here in the editor. Any children added at
## runtime after this (the actual inventory item boxes) are never treated as
## background, regardless of order.
@export var background: Control = null

var _hovered := false


func _ready() -> void:
	_apply_hover_visuals()


## Returns how many of `other_tags` also appear in this slot's own tags.
## Used by UserInterface to find the best-matching category for an item:
## e.g. an item tagged [fish, dead, rotting] scores 3 here if this slot's
## tags are [fish, dead, rotting], but only 2 against a slot tagged
## [fish, dead, blue] — so it's routed to the first slot.
func match_score(other_tags: Array[String]) -> int:
	var score := 0
	for tag: String in other_tags:
		if tags.has(tag):
			score += 1
	return score


## Called by RadialMenuAdvanced whenever this slot becomes (or stops being)
## the confirmed selection on the wheel. Swaps the icon (shown while idle)
## for the label (shown while hovered/selected).
func set_hovered(hovered: bool) -> void:
	if hovered == _hovered:
		return
	_hovered = hovered
	_apply_hover_visuals()


func _apply_hover_visuals() -> void:
	if icon:
		icon.visible = not _hovered
	if label:
		label.visible = _hovered


# The three methods below are what RadialMenuAdvanced actually calls (via
# has_method() duck-typing — it never reads `icon`/`label`/`background`
# directly). This slot owns the definition of what counts as its permanent
# chrome vs. its popout background vs. an actual popout item; the radial
# menu just asks and stays generic. Any other slot type could implement the
# same three methods to plug into RadialMenuAdvanced's popout system with
# completely different rules.

## This slot's permanent display nodes — never hidden by RadialMenuAdvanced,
## never treated as a popout item or background.
func get_chrome_nodes() -> Array:
	var chrome: Array = []
	if icon:
		chrome.append(icon)
	if label:
		chrome.append(label)
	return chrome


## This slot's dedicated popout background, or null if none is assigned
## (RadialMenuAdvanced falls back to its own `popout_first_is_background`
## behavior in that case).
func get_popout_background() -> Control:
	return background


## Every child eligible to appear as a popout item — i.e. everything that
## isn't chrome (icon/label) and isn't the explicit background. In practice
## this is just the inventory item boxes added at runtime.
func get_popout_candidates() -> Array[Control]:
	var chrome: Array = get_chrome_nodes()
	var list: Array[Control] = []
	for child: Node in get_children():
		if child is Control and not chrome.has(child) and child != background:
			list.append(child)
	return list