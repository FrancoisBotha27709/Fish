@icon('icon.svg')
class_name RadialMenuAdvanced extends Control

signal slot_selected(slot: Control, index: int)
signal selection_changed(new_selection: int)
signal selection_canceled

## Emitted when a grandchild (a child of the currently selected slot) is confirmed
## via [member select_action_name] while the popout is open.
signal sub_slot_selected(parent_slot: Control, sub_slot: Control, sub_index: int)
## Emitted whenever the hovered popout item changes. -1 means none hovered.
signal sub_selection_changed(new_sub_selection: int)

enum StrokeType { OUTLINE, INNER, OUTER }
enum PopoutAlignment { OUTWARD, CENTERED }

const _ANGLE_OFFSET: float = PI / 2.0
const _OUT_OF_BOUNDS := Vector2(-9999.0, -9999.0)
## Maximum number of horizontal popout items shown per slot (excluding the
## background). Extra grandchildren beyond this are simply left hidden.
const MAX_POPOUT_ITEMS: int = 5

## The action used to confirm selection
@export var select_action_name: StringName = &'fire'
## Select when action is released instead of pressed
@export var action_released := false

## Enables or disables the radial menu processing
@export var enabled := true: set = _set_enabled

## Automatic size based on this control size
@export var auto_sizing := true
## Is mouse hover and selection enabled. Works only when "Enabled" is true
@export var mouse_enabled := true: set = _set_mouse_enabled
## Does circle segments hover work when the mouse is outside the radius
@export var keep_selection_outside := true
## First child will be placed in the center
@export var first_in_center := false:	set = _set_first_in_center
## If true, sets "enabled" to false after a selection is made
@export var one_shot := false
## Rotates the starting position of the slots
@export var slots_offset: int = 0

@export_group('Controller')
## Controller works only when running the game
@export var controller_enabled := false
## Hold or press this action to enable controller. Leave empty to always work
@export var focus_action_name: StringName = &''
## Hold "focus_action_name" or just toggle. Works only if "focus_action_name" is not empty
@export var focus_action_hold_mode := true
@export var move_forward_action_name: StringName = &'move_forward'
@export var move_left_action_name: StringName = &'move_left'
@export var move_back_action_name: StringName = &'move_back'
@export var move_right_action_name: StringName = &'move_right'
## Select center element by pressing action (Works only if "first_in_center" is enabled)
@export var center_element_action_name: StringName = &''
## Deadzone for the controller stick
@export_range(0.0, 1.0, 0.01) var controller_deadzone: float = 0.2

@export_group('Base Circle')
## Offset of the entire radial menu from the center
@export var circle_offset := Vector2.ZERO
@export var color := Color(0, 0, 0, 0.3)
@export_range(0, 1024, 1) var circle_radius: int = 384
## Radius will dynamically be [code]viewport_size.y / 2.5[/code]
@export var set_auto_radius: Callable = func() -> void:
	circle_radius = get_viewport().get_visible_rect().size.y / 2.5
	queue_redraw()

@export_group('Arc', 'arc_')
@export var arc_color := Color.WHITE
@export_range(0, 1024) var arc_inner_radius: float = 32.0
@export_range(-TAU, TAU * 2.0) var arc_start_angle: float = TAU
@export_range(-TAU * 2.0, TAU) var arc_end_angle: float = 0.0
@export_range(2, 64) var arc_detail: int = 32
@export_range(1, 512) var arc_line_width: int = 6
@export var arc_antialiased := true

@export_group('Line', 'line_')
@export var line_rotation_offset_default: int = 0
@export var line_color := Color.WHITE
@export_range(1, 256) var line_width: int = 6
@export var line_antialiased := true

@export_group('Children', 'children_')
@export_range(1, 1024, 1) var children_size: int = 256
## If enabled, children [member Control.scale] will be changed instead of [member Control.size]
@export var children_size_as_scale := false
## Automatically resize children based on [member RadialMenuAdvanced.size]
@export var children_auto_sizing := false
@export_range(0, 2, 0.1) var children_auto_sizing_factor: float = 1.0
@export var children_distance_offset: float = 0.0
@export var children_offset := Vector2.ZERO
## Rotate children relative to their circular position
@export var children_rotate := false: set = _set_children_rotate
## Invert rotation relative to circular position (not towards, but away from center)
@export var children_rotate_inverted := false

@export_group('Hover')
@export var hover_color := Color(1, 1, 1, 0.2)
@export_range(-1024, 1024, 1) var hover_offset_start: int = 0
@export_range(-1024, 1024, 1) var hover_offset_end: int = 0
@export_range(-10, 10, 0.1) var hover_size_factor: float = 1.0
@export_range(2, 1024, 1) var hover_detail: int = 96
@export var hover_offset := Vector2.ZERO
@export_range(-10, 10) var hover_children_radial_offset: float = 0.0
## Minimum time (seconds) the input must stay over a *different* slot before
## that slot actually becomes the selection. This is what keeps a quick sweep
## of the mouse across a boundary from instantly flipping the highlight —
## whichever slot you've settled on / hovered over last is the one that wins.
## Losing the selection entirely (moving off all slots) is still immediate.
## Set to 0 to go back to instant, no-debounce selection.
@export_range(0.0, 1.0, 0.01) var hover_confirm_delay: float = 0.12

@export_group('Stroke', 'stroke_')
@export var stroke_enabled := false
@export var stroke_color := Color.WHITE
@export var stroke_type: StrokeType = StrokeType.OUTER
@export_range(0, 1024) var stroke_width: int = 6

@export_group('Animated Pulse', 'animated_pulse_')
@export var animated_pulse_enabled := false
@export_range(-250, 256, 1) var animated_pulse_intensity: int = 5
@export_range(-250, 256, 1) var animated_pulse_offset: int = 0
@export_range(-56, 56, 1) var animated_pulse_speed: int = 10
@export var animated_pulse_color := Color.WHITE

@export_group('Popout', 'popout_')
## When the selected slot has its own Control children, show them as a horizontal
## flyout row instead of leaving them stacked invisibly on the slot.
@export var popout_enabled := true
## Size (in pixels) each popout item is resized to.
@export_range(1, 1024, 1) var popout_item_size: int = 96
## Gap between consecutive popout items.
@export_range(0, 512, 1) var popout_spacing: float = 12.0
## Distance from the slot's own edge to the start of the popout row.
@export_range(0, 1024, 1) var popout_distance: float = 140.0
## OUTWARD: row extends away from the wheel's center (won't overlap the wheel).
## CENTERED: row is centered on the slot itself.
@export var popout_alignment: PopoutAlignment = PopoutAlignment.OUTWARD
## FALLBACK ONLY — used only when the selected slot has no explicit
## `background` property (see RadialCategorySlot.background). When true, the
## FIRST popout-eligible child of the selected slot is treated as a
## background instead — it is placed once, centered on the row's midpoint,
## at a fixed size (not stretched to fit), and drawn behind everything else.
## The remaining children become the horizontal popout items. Requires at
## least 2 popout-eligible children; with only 1 it's shown as a normal
## single item instead. A slot's own `icon`/`label` are never popout-eligible
## regardless of this setting.
@export var popout_first_is_background := true
## Extra padding (px) added around a normal item's size when sizing the
## background — it's just a slightly larger frame behind the middle of the
## row, not stretched to span it.
@export_range(0, 256, 1) var popout_background_padding: int = 16
## If true, popout children [member Control.scale] is changed instead of size.
@export var popout_size_as_scale := false
## How fast the popout opens/closes, in the 0..1 progress units per second.
## Set to 0 to disable animation (snap open/closed instantly).
@export_range(0.0, 20.0, 0.1) var popout_lerp_speed: float = 8.0
## Only allow hovering/selecting a popout item once the open animation has
## finished, to avoid accidental clicks while it's still sliding in.
@export var popout_require_fully_open := true


var _current_selection_idx: int = -2 # 0+ = child index, -1 = center, -2 = none
var _children_list: Array[Control] = []
var _local_children_count: int = 0
var _time_tick: float = 0.0

var _current_menu_radius: float = 0.0
var _current_menu_offset := Vector2.ZERO
var _global_angle_offset: float = 0.0

var _temporary_selection: int = -2
var _is_focus_action_pressed := false

## The slot the input is currently sitting over (recomputed every frame from
## raw input), independent of whether it's been confirmed as the actual
## selection yet. Used together with _pending_selection_timer to implement
## the hover-confirm debounce.
var _pending_selection_idx: int = -2
var _pending_selection_timer: float = 0.0

## Set whenever slots need repositioning: on first frame, when the child list
## changes, or when this control itself is resized. Lets _process() skip
## _arrange_children() (a per-slot Control-property write + trig pass) on the
## overwhelming majority of frames where the selection and layout haven't
## actually changed.
var _needs_arrange := true

var _popout_parent: Control = null
var _popout_background: Control = null
var _popout_children: Array[Control] = []
var _popout_sub_selection: int = -1 # -1 = none, 0+ = popout child index
var _popout_visible_t: float = 0.0 # 0 = closed, 1 = fully open
## The row's outward direction (+1 right, -1 left), captured once when the
## popout opens from the slot's own angle on the wheel, and held fixed for
## the duration it's open/closing so it can't flip mid-animation.
var _popout_dir: float = 1.0
## Runtime-only overlay layer. Popout items are reparented here (out of the
## slot) whenever their slot is open, so the slot's own transform/layout
## (rotation, scale, or it being a Container) can never affect them and the
## row is guaranteed to render as a flat horizontal strip.
var _popout_host: Control = null



func set_temporary_selection(value: int = -2) -> void:
	_temporary_selection = value
	selection_changed.emit(clampi(_temporary_selection, -1, _local_children_count - 1))

func force_update() -> void:
	_update_children()

func get_selected_child() -> Control:
	if _current_selection_idx == -2:
		return null
	var list_idx: int = _current_selection_idx + (1 if first_in_center else 0)
	if list_idx >= 0 and list_idx < _children_list.size():
		return _children_list[list_idx]
	return null

## Returns the currently hovered popout item (grandchild of the selected slot), or null.
func get_selected_sub_child() -> Control:
	if _popout_sub_selection == -1 or _popout_sub_selection >= _popout_children.size():
		return null
	return _popout_children[_popout_sub_selection]

func select() -> void:
	# If a popout is open and one of its items is hovered, confirm that instead
	# of the top-level slot.
	if _popout_parent != null and _popout_sub_selection != -1:
		var sub_item: Control = get_selected_sub_child()
		if sub_item:
			sub_slot_selected.emit(_popout_parent, sub_item, _popout_sub_selection)
			if one_shot:
				enabled = false
		return

	if _current_selection_idx == -2:
		selection_canceled.emit()
		return
	
	var selected_child: Control = get_selected_child()
	if selected_child:
		slot_selected.emit(selected_child, _current_selection_idx)
		
	if one_shot:
		enabled = false
	_update_slot_hover_visuals(_current_selection_idx, -2)
	_current_selection_idx = -2
	_pending_selection_idx = -2
	_pending_selection_timer = 0.0

func _set_enabled(value: bool) -> void:
	enabled = value
	set_process(value)
	set_process_input(value)
	if not value:
		_update_slot_hover_visuals(_current_selection_idx, -2)
		_current_selection_idx = -2
		_pending_selection_idx = -2
		_pending_selection_timer = 0.0
		_close_popout()
	_reset_children_rotation()
	_update_children()
	queue_redraw()

func _set_first_in_center(value: bool) -> void:
	first_in_center = value
	_reset_children_rotation()
	_update_children()

func _set_mouse_enabled(value: bool) -> void:
	mouse_enabled = value
	if not value:
		_update_slot_hover_visuals(_current_selection_idx, -2)
		_current_selection_idx = -2
		_pending_selection_idx = -2
		_pending_selection_timer = 0.0

func _set_children_rotate(value: bool) -> void:
	children_rotate = value
	if not value:
		_reset_children_rotation()

func _ready() -> void:
	if not is_instance_valid(_popout_host):
		_popout_host = Control.new()
		_popout_host.name = &'_PopoutHost'
		_popout_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_popout_host.position = Vector2.ZERO
		add_child(_popout_host)
	
	child_entered_tree.connect(_update_children.unbind(1))
	child_order_changed.connect(_update_children)
	child_exiting_tree.connect(func(_node: Node): _update_children.call_deferred())
	visibility_changed.connect(_update_children)
	resized.connect(func(): _needs_arrange = true)
	_update_children()

## Returns a slot's permanent "chrome" (e.g. RadialCategorySlot's icon and
## label) via get_chrome_nodes(), if the slot implements it. These nodes are
## never hidden by _update_children() and never counted as popout items or
## background. Duck-typed (has_method check) so RadialMenuAdvanced doesn't
## need to know anything about RadialCategorySlot's specific properties —
## any slot type can opt in by implementing the same method. Slots that don't
## implement it simply have no chrome.
func _get_slot_chrome_nodes(slot: Control) -> Array:
	if slot.has_method(&'get_chrome_nodes'):
		return slot.get_chrome_nodes()
	return []

## Returns the slot's explicitly-assigned popout background via
## get_popout_background(), if the slot implements it and returns one. This
## is a specific node reference the slot itself decides on, never inferred
## from child order, so newly-added item boxes can never be mistaken for it.
func _get_slot_background_node(slot: Control) -> Variant:
	if slot.has_method(&'get_popout_background'):
		var bg: Variant = slot.get_popout_background()
		if bg is Control:
			return bg
	return null

func _update_children() -> void:
	_children_list.clear()
	
	for node: Node in get_children():
		if node == _popout_host:
			continue
		if (node is Control) and node.visible:
			_children_list.append(node)
	
	_local_children_count = _children_list.size()
	if first_in_center and _local_children_count > 0:
		_local_children_count -= 1
	
	# Grandchildren (item boxes AND the explicit background, if any) are
	# hidden by default; they only become visible when their slot is the
	# active popout (at which point they're reparented into _popout_host, so
	# this loop never touches them while they're showing). A slot's own
	# icon/label are chrome and left completely alone here — they're not
	# popout items, they're the slot's permanent display.
	for slot: Control in _children_list:
		var chrome: Array = _get_slot_chrome_nodes(slot)
		for grandchild: Node in slot.get_children():
			if grandchild is Control and not chrome.has(grandchild):
				grandchild.visible = false
	
	_needs_arrange = true
	queue_redraw()

func _reset_children_rotation() -> void:
	for child: Node in _children_list:
		child.rotation = 0.0

func _get_stroke_radius_offset(width: float, type: StrokeType) -> float:
	match type:
		StrokeType.INNER: return -width / 2.0
		StrokeType.OUTER: return width / 2.0
		_: return 0.0 # OUTLINE

func _process(delta: float) -> void:
	if not enabled:
		return
	
	# Tracks whether anything visible actually changed this frame; queue_redraw()
	# is only called when true, instead of unconditionally every frame.
	var dirty := false
	
	if animated_pulse_enabled:
		_time_tick += delta
		dirty = true # the pulse arc's radius is a function of time, so it must redraw continuously while enabled
	
	_current_menu_offset = size / 2.0 + circle_offset
	_current_menu_radius = (minf(size.x, size.y) / 2.0) if auto_sizing else float(circle_radius)
	
	var segment_angle: float = TAU / float(_local_children_count) if _local_children_count > 0 else TAU
	_global_angle_offset = deg_to_rad(line_rotation_offset_default) + (slots_offset * segment_angle)
	
	var prev_selection: int = _current_selection_idx
	
	if _temporary_selection != -2:
		var forced_selection: int = clampi(_temporary_selection, -1, _local_children_count - 1)
		_current_selection_idx = forced_selection
		_pending_selection_idx = forced_selection
		_pending_selection_timer = 0.0
	else:
		var local_input_pos: Vector2 = _OUT_OF_BOUNDS
		var is_controller_active := false
		
		if mouse_enabled:
			local_input_pos = get_local_mouse_position() - _current_menu_offset
		
		if controller_enabled:
			var controller_pos: Vector2 = _get_controller_simulated_pos()
			is_controller_active = controller_pos != _OUT_OF_BOUNDS
			
			if is_controller_active:
				local_input_pos = controller_pos
			elif not mouse_enabled:
				if _pending_selection_idx != -2:
					_pending_selection_idx = -2
					_pending_selection_timer = 0.0
				if _current_selection_idx != -2:
					_current_selection_idx = -2
		
		var input_radius: float = local_input_pos.length()
		
		if local_input_pos != _OUT_OF_BOUNDS:
			var computed_selection: int = _pending_selection_idx
			
			if input_radius < arc_inner_radius:
				computed_selection = -1 if first_in_center else -2
			elif _local_children_count == 1 and not first_in_center:
				computed_selection = 0 if input_radius < _current_menu_radius else -2
			else:
				if _local_children_count > 0 and (keep_selection_outside or input_radius <= _current_menu_radius):
					var input_angle: float = fposmod(local_input_pos.angle() + _ANGLE_OFFSET - _global_angle_offset, TAU)
					computed_selection = int(input_angle / segment_angle) % _local_children_count
				else:
					computed_selection = -2
			
			# Debounce: only commit a *new* slot as the selection once the
			# input has stayed over it for hover_confirm_delay seconds, so a
			# quick sweep across a boundary doesn't instantly flip the
			# highlight. Losing the selection (-2) is still applied right away.
			if computed_selection != _pending_selection_idx:
				_pending_selection_idx = computed_selection
				_pending_selection_timer = 0.0
			else:
				_pending_selection_timer += delta
			
			if computed_selection == -2 or hover_confirm_delay <= 0.0 or _pending_selection_timer >= hover_confirm_delay:
				_current_selection_idx = computed_selection
			
			if is_controller_active and not center_element_action_name.is_empty() and Input.is_action_just_pressed(center_element_action_name):
				_current_selection_idx = -1
				_pending_selection_idx = -1
				select()
	
	if _current_selection_idx != prev_selection:
		selection_changed.emit(_current_selection_idx)
		_update_slot_hover_visuals(prev_selection, _current_selection_idx)
		_needs_arrange = true
	
	if _needs_arrange:
		_arrange_children()
		_needs_arrange = false
		dirty = true
	
	if _sync_popout(delta):
		dirty = true
	
	if dirty:
		queue_redraw()


func _get_controller_simulated_pos() -> Vector2:
	var is_active := false
	
	if not focus_action_name.is_empty():
		if not focus_action_hold_mode:
			if Input.is_action_just_pressed(focus_action_name):
				_is_focus_action_pressed = not _is_focus_action_pressed
			is_active = _is_focus_action_pressed
		else:
			is_active = Input.is_action_pressed(focus_action_name)
	else:
		is_active = true
	
	if is_active:
		var vec: Vector2 = Input.get_vector(move_left_action_name, move_right_action_name, move_forward_action_name, move_back_action_name)
		if vec.length_squared() > controller_deadzone * controller_deadzone:
			var mid_radius := (arc_inner_radius + _current_menu_radius) / 2.0
			return vec * mid_radius
			
	return _OUT_OF_BOUNDS


## Notifies the previously- and newly-selected slot Controls (if they expose
## a set_hovered(bool) method, e.g. RadialCategorySlot) so they can swap
## between their idle (icon) and hovered (label) display. Center (-1) and
## none (-2) aren't slots, so they're simply skipped.
func _update_slot_hover_visuals(prev_idx: int, new_idx: int) -> void:
	if prev_idx == new_idx:
		return
	
	if prev_idx >= 0:
		var prev_list_idx: int = prev_idx + (1 if first_in_center else 0)
		if prev_list_idx >= 0 and prev_list_idx < _children_list.size():
			var prev_slot: Control = _children_list[prev_list_idx]
			if prev_slot.has_method(&'set_hovered'):
				prev_slot.set_hovered(false)
	
	if new_idx >= 0:
		var new_list_idx: int = new_idx + (1 if first_in_center else 0)
		if new_list_idx >= 0 and new_list_idx < _children_list.size():
			var new_slot: Control = _children_list[new_list_idx]
			if new_slot.has_method(&'set_hovered'):
				new_slot.set_hovered(true)


func _arrange_children() -> void:
	if _local_children_count == 0:
		return
	
	var segment_angle: float = TAU / float(_local_children_count)
	var child_size_factor: float = 1.0
	if children_auto_sizing and _current_menu_radius > 0:
		child_size_factor = (_current_menu_radius / (children_size * 1.5)) * children_auto_sizing_factor
	var target_child_size: Vector2 = Vector2.ONE * children_size * child_size_factor

	for i: int in _local_children_count:
		var angle: float = i * segment_angle - _ANGLE_OFFSET + _global_angle_offset
		var mid_rad: float = angle + (segment_angle / 2)
		var draw_pos: Vector2 = Vector2.from_angle(mid_rad) * ((arc_inner_radius + _current_menu_radius) / 2.0)
		
		if _current_selection_idx == i:
			draw_pos *= (1.0 + hover_children_radial_offset)
			draw_pos += hover_offset
		
		draw_pos *= (1.0 + children_distance_offset)
		
		var list_idx: int = i + (1 if first_in_center else 0)
		var child: Control = _children_list[list_idx]
		
		if children_size_as_scale:
			if child.scale != target_child_size:
				child.scale = target_child_size
		else:
			if child.size != target_child_size:
				child.size = target_child_size
		
		var target_pos: Vector2 = _current_menu_offset - (child.size / 2.0) + draw_pos + children_offset
		if child.has_meta(&'radial_offset'):
			target_pos += child.get_meta(&'radial_offset', Vector2.ZERO)
		
		if child.position != target_pos:
			child.position = target_pos
		if child.pivot_offset != child.size / 2.0:
			child.pivot_offset = child.size / 2.0
		
		# Rotation
		if children_rotate:
			var new_rotation: float
			if _local_children_count == 1:
				new_rotation = 0.0
			else:
				var rot_dir: int = -1 if children_rotate_inverted else 1
				new_rotation = rot_dir * _ANGLE_OFFSET + mid_rad
			if child.rotation != new_rotation:
				child.rotation = new_rotation
			
	if first_in_center and _children_list.size() > 0:
		var center_child: Control = _children_list[0]
		# var target_size := Vector2.ONE * children_size * (children_auto_sizing_factor if children_auto_sizing else 1.0)
		if children_size_as_scale:
			if center_child.scale != target_child_size:
				center_child.scale = target_child_size
		else:
			if center_child.size != target_child_size:
				center_child.size = target_child_size
		
		var center_target_pos: Vector2 = _current_menu_offset - (center_child.size / 2.0) + children_offset
		if center_child.position != center_target_pos:
			center_child.position = center_target_pos
		if center_child.pivot_offset != center_child.size / 2.0:
			center_child.pivot_offset = center_child.size / 2.0
		# if not children_rotate:
		# 	center_child.rotation = 0.0


# ---------------------------------------------------------------------------
# Popout (grandchildren horizontal flyout)
# ---------------------------------------------------------------------------

## Returns the children of `parent` eligible to be popout items, via
## get_popout_candidates() if the slot implements it (this is where a slot
## defines what its own chrome/background are, so it excludes them itself).
## Falls back to "every Control child" for plain slots that don't implement
## it, so RadialMenuAdvanced still works with a bare Control as a slot.
func _get_popout_candidates(parent: Control) -> Array[Control]:
	if parent.has_method(&'get_popout_candidates'):
		return parent.get_popout_candidates()
	var list: Array[Control] = []
	for node: Node in parent.get_children():
		if node is Control:
			list.append(node)
	return list


## Reparents the currently-open popout's items (and background, if any) back
## to their original slot (hiding them again) and clears popout state.
func _close_popout() -> void:
	if _popout_parent != null:
		if is_instance_valid(_popout_background) and _popout_background.get_parent() == _popout_host:
			_popout_background.reparent(_popout_parent, false)
			_popout_background.visible = false
			_popout_background.modulate.a = 1.0
			_popout_background.position = Vector2.ZERO
		for item: Control in _popout_children:
			if is_instance_valid(item) and item.get_parent() == _popout_host:
				item.reparent(_popout_parent, false)
				item.visible = false
				item.modulate.a = 1.0
				item.position = Vector2.ZERO
	
	_popout_parent = null
	_popout_background = null
	_popout_children.clear()
	_popout_sub_selection = -1
	_popout_visible_t = 0.0


## Computes the row's outward direction purely from the slot's own angular
## position on the wheel (the same angle used to place it in _arrange_children),
## not from any post-layout pixel comparison.
func _compute_popout_direction() -> float:
	if _current_selection_idx < 0 or _local_children_count <= 0:
		return 1.0
	var segment_angle: float = TAU / float(_local_children_count)
	var angle: float = _current_selection_idx * segment_angle - _ANGLE_OFFSET + _global_angle_offset
	var mid_rad: float = angle + segment_angle / 2.0
	return 1.0 if cos(mid_rad) >= 0.0 else -1.0


func _sync_popout(delta: float) -> bool:
	var dirty := false
	
	if not popout_enabled:
		if _popout_parent != null:
			_close_popout()
			dirty = true
		return dirty
	
	var selected_child: Control = get_selected_child()
	
	# Only touch anything when the HOVERED SLOT itself actually changes.
	# (Reading the slot's live children every frame would break once items
	# are reparented into the overlay — the slot would look "empty" the
	# instant it opens, causing an open/close loop. So we snapshot the
	# candidates once, here, before any reparenting happens.)
	if selected_child != _popout_parent:
		_close_popout() # return whatever was previously open first
		dirty = true
		
		if selected_child != null:
			var explicit_bg: Variant = _get_slot_background_node(selected_child)
			var all_candidates: Array[Control] = _get_popout_candidates(selected_child)
			
			if explicit_bg != null or not all_candidates.is_empty():
				_popout_parent = selected_child
				_popout_dir = _compute_popout_direction()
				
				if explicit_bg != null:
					# An explicit background was assigned on the slot itself —
					# use it directly. Every popout-eligible child (i.e. every
					# item box added later) is a real item; none of them is
					# ever mistaken for the background.
					_popout_background = explicit_bg
					_popout_children = all_candidates
				elif popout_first_is_background and all_candidates.size() >= 2:
					# No explicit background: fall back to treating the first
					# surviving child as one.
					_popout_background = all_candidates[0]
					_popout_children = all_candidates.slice(1)
				else:
					_popout_background = null
					_popout_children = all_candidates
				
				if _popout_children.size() > MAX_POPOUT_ITEMS:
					_popout_children = _popout_children.slice(0, MAX_POPOUT_ITEMS)
				
				# Reparent background first so it stays behind the items when drawn.
				if _popout_background != null:
					_popout_background.reparent(_popout_host, false)
					_popout_background.visible = true
					_popout_background.modulate.a = 0.0
				for item: Control in _popout_children:
					# Pulled out of the slot entirely so the slot's own rotation,
					# scale, or Container behavior can't reposition these items.
					item.reparent(_popout_host, false)
					item.visible = true
					item.modulate.a = 0.0
	
	# Animate open amount
	var target_t: float = 1.0 if _popout_parent != null else 0.0
	var prev_t: float = _popout_visible_t
	if popout_lerp_speed <= 0.0:
		_popout_visible_t = target_t
	else:
		_popout_visible_t = move_toward(_popout_visible_t, target_t, popout_lerp_speed * delta)
	var t_animating: bool = _popout_visible_t != prev_t
	
	if _popout_parent != null:
		# Only re-run the (Control property write + trig) layout pass while
		# something is actually moving — once fully open and idle, the items
		# already sit at their final position and don't need re-setting.
		if t_animating or dirty:
			_arrange_popout()
			dirty = true
		if _update_popout_hover():
			dirty = true
	elif _popout_sub_selection != -1:
		_popout_sub_selection = -1
		sub_selection_changed.emit(-1)
		dirty = true
	
	return dirty


func _arrange_popout() -> void:
	if _popout_children.is_empty() and _popout_background == null:
		return
	
	var slot: Control = _popout_parent
	# slot.position/size are already in THIS control's local space (slot is a
	# direct child of the radial menu), so no coordinate conversion is needed.
	var slot_center: Vector2 = slot.position + slot.size / 2.0
	
	var item_size: Vector2 = Vector2.ONE * popout_item_size
	var count: int = _popout_children.size()
	var step: float = item_size.x + popout_spacing
	var eased_t: float = ease(_popout_visible_t, -2.0)
	
	var total_width: float = 0.0
	if count > 0:
		total_width = count * item_size.x + (count - 1) * popout_spacing
	
	# Row's left edge, using the direction captured when the popout opened.
	var row_left: float
	if popout_alignment == PopoutAlignment.CENTERED:
		row_left = slot_center.x - total_width / 2.0
	else: # OUTWARD — away from the circle, using the slot's own angle
		if _popout_dir >= 0.0:
			row_left = slot_center.x + popout_distance
		else:
			row_left = slot_center.x - popout_distance - total_width
	
	var closed_pos: Vector2 = slot_center - (item_size / 2.0)
	
	for i: int in count:
		var item: Control = _popout_children[i]
		
		if popout_size_as_scale:
			if item.scale != item_size:
				item.scale = item_size
		else:
			if item.size != item_size:
				item.size = item_size
		if item.pivot_offset != item.size / 2.0:
			item.pivot_offset = item.size / 2.0
		if item.rotation != 0.0:
			item.rotation = 0.0 # always upright, regardless of the slot's rotation
		
		var target_pos: Vector2 = Vector2(row_left + step * i, slot_center.y - item_size.y / 2.0)
		item.position = closed_pos.lerp(target_pos, eased_t)
		item.modulate.a = _popout_visible_t
	
	if _popout_background != null:
		# Fixed size (a bit larger than a normal item), NOT stretched to span
		# the row — just centered on the row's midpoint, behind everything.
		var bg_size: Vector2 = item_size + Vector2.ONE * popout_background_padding * 2.0
		var row_center_x: float = row_left + total_width / 2.0
		var target_bg_pos: Vector2 = Vector2(row_center_x - bg_size.x / 2.0, slot_center.y - bg_size.y / 2.0)
		var closed_bg_pos: Vector2 = slot_center - bg_size / 2.0
		
		if popout_size_as_scale:
			if _popout_background.scale != bg_size:
				_popout_background.scale = bg_size
		else:
			if _popout_background.size != bg_size:
				_popout_background.size = bg_size
		if _popout_background.pivot_offset != _popout_background.size / 2.0:
			_popout_background.pivot_offset = _popout_background.size / 2.0
		if _popout_background.rotation != 0.0:
			_popout_background.rotation = 0.0
		_popout_background.position = closed_bg_pos.lerp(target_bg_pos, eased_t)
		_popout_background.modulate.a = _popout_visible_t


func _update_popout_hover() -> bool:
	if not mouse_enabled:
		return false
	if popout_require_fully_open and _popout_visible_t < 0.999:
		if _popout_sub_selection != -1:
			_popout_sub_selection = -1
			sub_selection_changed.emit(-1)
			return true
		return false
	
	# _popout_host sits at local (0,0) in this control, so item.position is
	# already directly comparable to get_local_mouse_position().
	var mouse_pos: Vector2 = get_local_mouse_position()
	var prev_sub: int = _popout_sub_selection
	var new_sub: int = -1
	
	for i: int in _popout_children.size():
		var item: Control = _popout_children[i]
		if Rect2(item.position, item.size).has_point(mouse_pos):
			new_sub = i
			break
	
	_popout_sub_selection = new_sub
	if _popout_sub_selection != prev_sub:
		sub_selection_changed.emit(_popout_sub_selection)
		return true
	return false


func _draw() -> void:
	# if _local_children_count == 0 and not first_in_center:
	# 	return
	
	draw_circle(_current_menu_offset, _current_menu_radius, color)
	
	if _current_selection_idx == -1 and first_in_center:
		draw_circle(_current_menu_offset, arc_inner_radius, hover_color)
	
	if _local_children_count == 0:
		_draw_decorations()
		return
	
	var segment_angle: float = TAU / float(_local_children_count)
	
	for i: int in range(_local_children_count):
		var angle: float = i * segment_angle - _ANGLE_OFFSET + _global_angle_offset
		var start_rad: float = angle
		var end_rad: float = angle + segment_angle
		var mid_rad: float = angle + (segment_angle / 2)
		
		# Draw Hover Sector
		if _current_selection_idx == i and arc_inner_radius < _current_menu_radius:
			if _local_children_count == 1:
				draw_circle(_current_menu_offset, _current_menu_radius, hover_color)
			else:
				var points := PackedVector2Array()
				for j: int in range(hover_detail + 1):
					var t: float = j / float(hover_detail)
					var a: float = lerpf(start_rad, end_rad, t)
					points.append(_current_menu_offset + Vector2.from_angle(a) * (arc_inner_radius + hover_offset_start) * hover_size_factor)
				
				for j: int in range(hover_detail + 1):
					var t: float = 1.0 - j / float(hover_detail)
					var a: float = lerpf(start_rad, end_rad, t)
					points.append(_current_menu_offset + Vector2.from_angle(a) * (_current_menu_radius + hover_offset_end) * hover_size_factor)
					
				draw_polygon(points, PackedColorArray([hover_color]))
				
		# Draw dividing lines
		if _local_children_count > 1:
			var point := Vector2.from_angle(angle)
			draw_line(
				_current_menu_offset + point * arc_inner_radius,
				_current_menu_offset + point * _current_menu_radius,
				line_color, line_width, line_antialiased
			)
			
	_draw_decorations()
	_draw_popout_hover()


func _draw_decorations() -> void:
	# Inner Arc
	draw_arc(_current_menu_offset, arc_inner_radius, arc_start_angle, arc_end_angle, arc_detail, arc_color, arc_line_width, arc_antialiased)
	
	# Stroke
	if stroke_enabled and stroke_width != 0:
		var r_offset := _get_stroke_radius_offset(stroke_width, stroke_type)
		draw_arc(_current_menu_offset, _current_menu_radius + r_offset, 0, TAU, arc_detail, stroke_color, stroke_width, arc_antialiased)
	
	# Animated Pulse
	if animated_pulse_enabled:
		var pulse_radius: float = _current_menu_radius + animated_pulse_offset + animated_pulse_intensity + sin(_time_tick * animated_pulse_speed) * animated_pulse_intensity
		draw_arc(_current_menu_offset, pulse_radius, 0, TAU, arc_detail, animated_pulse_color, arc_line_width, arc_antialiased)


func _draw_popout_hover() -> void:
	if _popout_parent == null or _popout_sub_selection == -1:
		return
	if _popout_sub_selection >= _popout_children.size():
		return
	
	# item.position/size are already in this control's own local space
	# (items live in _popout_host, a plain child at local (0,0)).
	var item: Control = _popout_children[_popout_sub_selection]
	draw_rect(Rect2(item.position, item.size), hover_color)


func _input(event: InputEvent) -> void:
	if not enabled:
		return
		
	# Select Action
	if not select_action_name.is_empty():
		var is_triggered := event.is_action_released(select_action_name) if action_released else event.is_action_pressed(select_action_name)
		if is_triggered:
			var has_popout_hover: bool = _popout_parent != null and _popout_sub_selection != -1
			if has_popout_hover or _current_selection_idx != -2:
				select()
	
	# Cancel Action
	if event.is_action_pressed(&'ui_cancel'):
		selection_canceled.emit()
		if one_shot:
			enabled = false