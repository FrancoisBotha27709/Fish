@tool
extends Node

## Attach this to the ROOT of the scene. All direct children should be
## instanced packed scenes. Pressing the button in the Inspector will:
##   1. "Make local" every child (break its link to the PackedScene so it
##      saves as plain nodes instead of an instance reference)
##   2. Move each child's first child to become a direct child of this root
##   3. Delete the now-empty wrapper node

@export_tool_button("Localize & Promote First Children") var _run_button := _localize_and_promote
@export var items: Array[MeshInstance3D]

var _current_index := -1


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# Start with everything hidden; first "screenshot" press shows item 0.
	for item in items:
		if item:
			item.visible = false

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not OS.is_debug_build():
		return
	if event.is_action_pressed("screenshot"):
		next_item()


func next_item() -> void:
	if items.is_empty():
		return

	# Hide the previous item
	if _current_index >= 0 and _current_index < items.size() and items[_current_index]:
		items[_current_index].visible = false

	# Advance (wraps back to the first item after the last)
	_current_index = (_current_index + 1) % items.size()

	var item := items[_current_index]
	if item == null:
		return

	item.visible = true

	# Name the file after the mesh node, e.g. "Chair" -> Chair_photo.png
	Screenie.take_screenshot(item)


func _localize_and_promote() -> void:
	if not Engine.is_editor_hint():
		return

	var edited_root: Node = get_tree().edited_scene_root if get_tree() else self
	if edited_root == null:
		edited_root = self

	var original_children := get_children() # snapshot before mutating

	for wrapper in original_children:
		_make_local(wrapper, edited_root)

		if wrapper.get_child_count() > 0:
			var first_child: Node = wrapper.get_child(0)
			var wrapper_index := wrapper.get_index()

			first_child.reparent(self, true)  # true = keep global transform
			move_child(first_child, wrapper_index)
			_set_owner_recursive(first_child, edited_root)

			# Auto-fill the items list so it's ready for screenshots
			if first_child is MeshInstance3D and not items.has(first_child):
				items.append(first_child)

		wrapper.queue_free()

	notify_property_list_changed()
	print("Localize & promote finished.")


func _make_local(node: Node, edited_root: Node) -> void:
	node.scene_file_path = ""  # this is what actually "unpacks" the instance
	node.owner = edited_root
	for child in node.get_children():
		_make_local(child, edited_root)


func _set_owner_recursive(node: Node, edited_root: Node) -> void:
	node.owner = edited_root
	for child in node.get_children():
		_set_owner_recursive(child, edited_root)