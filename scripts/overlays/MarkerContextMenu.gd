extends CanvasLayer

# MarkerContextMenu - Screen-space actions and click-to-place movement/duplication.
const CLASS_NAME = "MarkerContextMenu"
const HEADER = -1
const MOVE = 0
const DUPLICATE = 1
const PICK_SETTINGS = 2
const APPLY_COLOR = 3
const SAVE_TEMPLATE = 4
const DELETE = 5

var tool = null
var popup = null
var _target = null
var _click_position = Vector2.ZERO
var _moving = false
var _duplicating = false

func _ready():
	layer = 100
	popup = PopupMenu.new()
	popup.add_item("Marker", HEADER)
	popup.set_item_disabled(0, true)
	popup.add_separator()
	popup.add_item("Move", MOVE)
	popup.add_item("Duplicate", DUPLICATE)
	popup.add_item("Pick Settings", PICK_SETTINGS)
	popup.add_item("Apply Active Color", APPLY_COLOR)
	popup.add_item("Save as Template", SAVE_TEMPLATE)
	popup.add_separator()
	popup.add_item("Delete", DELETE)
	popup.connect("id_pressed", self, "_on_action")
	popup.connect("popup_hide", self, "_on_popup_hide")
	add_child(popup)

func _on_popup_hide() -> void:
	# PopupMenu may hide before id_pressed; let the selected action run first.
	call_deferred("_clear_dismissed_target")

func _clear_dismissed_target() -> void:
	if not popup.visible and not _moving:
		_target = null

func open_at(marker, world_position: Vector2, screen_position: Vector2) -> void:
	cancel()
	tool._move_selected_marker = null
	_target = marker
	_click_position = world_position
	popup.set_item_text(0, "%s #%d" % [marker.marker_type, marker.id])
	popup.rect_size = Vector2.ZERO
	popup.rect_position = screen_position
	popup.popup()
	if tool.overlay:
		tool.overlay.update()

func _exit_tree():
	cancel()

func cancel() -> void:
	if popup:
		popup.hide()
	if _moving and tool and tool._move_selected_marker == _target:
		tool._move_selected_marker = null
		if tool.overlay:
			tool.overlay.update()
	_moving = false
	_duplicating = false
	_target = null

func _target_exists() -> bool:
	return tool != null and _target != null and tool.markers_lookup.get(_target.id) == _target

func _process(_delta):
	if _target == null:
		return
	if not tool or not tool.is_enabled or not _target_exists():
		cancel()
	elif _moving and (not tool.move_mode or tool._move_selected_marker != _target):
		cancel()

func _on_action(action: int) -> void:
	var needs_enabled = action in [MOVE, DUPLICATE, PICK_SETTINGS]
	if not tool or (needs_enabled and not tool.is_enabled) or not _target_exists():
		cancel()
		return
	popup.hide()
	if action == MOVE or action == DUPLICATE:
		if not tool.cached_worldui:
			cancel()
			return
		tool._cancel_path_placement()
		tool.set_move_mode(true)
		tool._move_selected_marker = _target
		tool._move_drag_offset = _click_position - _target.position
		tool._move_drag_pos = tool.cached_worldui.MousePosition
		_moving = true
		_duplicating = action == DUPLICATE
		if tool.overlay:
			tool.overlay.update()
	elif action == PICK_SETTINGS:
		tool.pick_settings_from_marker(_target)
		cancel()
	elif action == APPLY_COLOR:
		tool.recolor_marker(_target, tool.active_color)
		cancel()
	elif action == SAVE_TEMPLATE:
		tool.capture_marker_object_as_template(_target)
		cancel()
	elif action == DELETE:
		tool.api_delete_marker_by_id(_target.id)
		cancel()

# Shared entry point for optional SelectTool providers; Move/Duplicate/Pick require activation.
func execute(action: int, marker, world_position: Vector2) -> void:
	cancel()
	_target = marker
	_click_position = world_position
	_on_action(action)

# Called before ordinary overlay input: GUI still receives events while open.
func handle_input(event, over_canvas: bool) -> bool:
	if popup and popup.visible:
		return true
	if not _moving:
		return false
	if not _target_exists() or not tool.move_mode or tool._move_selected_marker != _target:
		cancel()
		return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == BUTTON_LEFT and over_canvas and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
			var position = tool.cached_worldui.MousePosition - tool._move_drag_offset
			if tool.parent_mod.Global.Editor.IsSnapping:
				position = tool.snap_position_to_grid(position)
			if tool.cached_world and tool.cached_world.WorldRect.has_point(position):
				if _duplicating:
					tool.duplicate_marker_at(_target, position)
				else:
					tool.move_marker(_target, position)
		cancel()
		get_tree().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		cancel()
		get_tree().set_input_as_handled()
	# Releases never commit this movement; mouse motion uses the existing preview.
	return true
