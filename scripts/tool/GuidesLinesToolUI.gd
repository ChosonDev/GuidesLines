extends Reference

# GuidesLinesToolUI - UI panel creation, callbacks, and widget helpers for GuidesLinesTool.
# Holds all UI node references and handles user input from the tool panel.
# Parameter controls call tool actions; this class synchronizes their presentation.

const CLASS_NAME = "GuidesLinesToolUI"


var _controls = {}
var _icon_cache = {}

var tool = null  # Reference to GuidesLinesTool

# UI node references (owned by this class)
var type_specific_container = null    # Container for type-specific settings
var line_settings_container = null    # Settings for Line type
var shape_settings_container = null   # Settings for Shape type
var path_settings_container = null    # Settings for Path type
var fill_settings_container = null    # Settings for Fill type
var template_settings_container = null   # Settings for Template type
var _template_list_container = null      # VBoxContainer inside scroll for template rows
var _add_template_btn = null             # "Add Template" / "Cancel" button
var _top_bar = null                      # Floating top-center VBoxContainer inside Editor Content
var _type_panel = null                   # Floating main bar: Marker Type | Place/Move/Delete | Overlap
var _settings_panel = null               # Floating context settings bar (Line / Shape / Path)
var _line_top_settings = null            # Top settings row for Line
var _shape_top_settings = null           # Top settings row for Shape
var _path_top_settings = null            # Top settings row for Path
var _fill_top_settings = null            # Top settings row for Fill
var _template_top_settings = null        # Top settings row for Template
var _create_group_btn = null
var _cancel_group_btn = null
var _group_transform_container = null
var _group_error = null
var _text_focus_edit = null
var _text_focus_editor = null
var _previous_search_focus = false

func _init(tool_ref):
	tool = tool_ref

# ============================================================================
# PANEL STATE UPDATES
# ============================================================================

func update_ui():
	if not tool.tool_panel:
		return
	var cancel_btn = get_control("PathCancelButton")
	if cancel_btn:
		cancel_btn.visible = tool.active_marker_type == tool.MARKER_TYPE_PATH and tool.path_placement_active

func update_ui_checkboxes_state():
	var any_special_mode = tool.delete_mode or tool.move_mode
	if is_instance_valid(type_specific_container):
		_set_subtree_disabled(type_specific_container, any_special_mode)
	if is_instance_valid(_settings_panel):
		_set_subtree_disabled(_settings_panel, any_special_mode)
	if not any_special_mode:
		sync_spiral_controls()
		_update_template_capture_button(tool.template_capture_mode)
	var color_picker = get_control("ColorPicker")
	if color_picker:
		color_picker.disabled = any_special_mode
	var delete_all_btn = get_control("DeleteAllMarkersButton")
	if delete_all_btn:
		delete_all_btn.disabled = not tool.delete_mode
	update_overlap_panel_state()

func _set_subtree_disabled(node: Node, disabled: bool) -> void:
	if not is_instance_valid(node):
		return
	if node is BaseButton:
		node.disabled = disabled
	elif node is SpinBox:
		node.editable = not disabled
	elif node is LineEdit:
		node.editable = not disabled
	for child in node.get_children():
		_set_subtree_disabled(child, disabled)

# ============================================================================
# PANEL CREATION
# ============================================================================

# Create the UI panel for the tool with all controls
# Includes marker type selector and type-specific settings
func create_ui_panel():
	if not tool.tool_panel:
		return
	release_text_focus()
	_destroy_overlap_panel()

	_controls.clear()
	var container = VBoxContainer.new()
	container.add_constant_override("separation", 10)

	# Title
	var title = Label.new()
	title.text = "Guide Markers"
	title.align = Label.ALIGN_CENTER
	title.add_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	container.add_child(title)
	container.add_child(HSeparator.new())

	# === TYPE-SPECIFIC SETTINGS CONTAINER (kept empty; tool controls live in top bar) ===
	type_specific_container = VBoxContainer.new()
	type_specific_container.name = "TypeSpecificContainer"
	type_specific_container.visible = false
	_controls["TypeSpecificContainer"] = type_specific_container

	line_settings_container = _create_line_settings_ui()
	line_settings_container.name = "LineSettings"
	_controls["LineSettings"] = line_settings_container
	type_specific_container.add_child(line_settings_container)

	shape_settings_container = _create_shape_settings_ui()
	shape_settings_container.name = "ShapeSettings"
	_controls["ShapeSettings"] = shape_settings_container
	shape_settings_container.visible = false
	type_specific_container.add_child(shape_settings_container)

	path_settings_container = _create_path_settings_ui()
	path_settings_container.name = "PathSettings"
	_controls["PathSettings"] = path_settings_container
	path_settings_container.visible = false
	type_specific_container.add_child(path_settings_container)

	fill_settings_container = _create_fill_settings_ui()
	fill_settings_container.name = "FillSettings"
	_controls["FillSettings"] = fill_settings_container
	fill_settings_container.visible = false
	type_specific_container.add_child(fill_settings_container)

	template_settings_container = _create_template_settings_ui()
	template_settings_container.name = "TemplateSettings"
	_controls["TemplateSettings"] = template_settings_container
	template_settings_container.visible = false
	type_specific_container.add_child(template_settings_container)

	container.add_child(type_specific_container)

	# === COMMON & GLOBAL SETTINGS SECTIONS ===
	var common_container = _create_common_settings_ui()
	container.add_child(common_container)

	# === DELETE ALL ACTION ===
	var actions_section = _create_section_card("Cleanup")
	var delete_all_btn = Button.new()
	delete_all_btn.text = "Delete All Markers"
	delete_all_btn.hint_tooltip = "Switch to Delete Mode (Ctrl+D) to enable"
	delete_all_btn.disabled = not tool.delete_mode
	delete_all_btn.name = "DeleteAllMarkersButton"
	_controls["DeleteAllMarkersButton"] = delete_all_btn
	delete_all_btn.connect("pressed", tool, "delete_all_markers")
	actions_section.body.add_child(delete_all_btn)
	container.add_child(actions_section.card)

	tool.tool_panel.Align.add_child(container)
	_create_overlap_panel()
	sync_type_settings_controls(tool.active_marker_type)
	sync_type_selector_to_active_type()
	rebuild_template_list()
	_update_template_capture_button(tool.template_capture_mode)
	_sync_guide_overlay_checkboxes()
	update_ui_checkboxes_state()

# ============================================================================
# UI CREATION HELPERS FOR MARKER TYPES
# ============================================================================

# Create sidebar UI for Line marker type (controls live in top settings bar)
func _create_line_settings_ui():
	return VBoxContainer.new()

# Create sidebar UI for Shape marker type (controls live in top settings bar)
func _create_shape_settings_ui():
	return VBoxContainer.new()

# Create sidebar UI for Fill type (controls live in top settings bar)
func _create_fill_settings_ui():
	return VBoxContainer.new()

# Create sidebar UI for Path marker type (controls live in top settings bar)
func _create_path_settings_ui():
	return VBoxContainer.new()

# Create sidebar UI for Template type (controls live in top settings bar)
func _create_template_settings_ui():
	return VBoxContainer.new()

# Rebuild the template list UI from tool.templates[]
func rebuild_template_list() -> void:
	if not _template_list_container:
		return
	release_text_focus()

	# Clear existing rows
	for child in _template_list_container.get_children():
		child.queue_free()

	for i in range(tool.templates.size()):
		var tmpl = tool.templates[i]

		var row = HBoxContainer.new()
		row.set_meta("template_index", i)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_row = HBoxContainer.new()
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var edit = LineEdit.new()
		edit.text = tmpl.name
		edit.max_length = 128
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.hint_tooltip = "Rename template: Enter to save, Escape to cancel."
		edit.editable = not tool.template_capture_mode
		_connect_text_focus(edit)
		edit.connect("text_entered", self, "_on_template_name_entered", [edit])
		edit.connect("focus_exited", self, "_on_template_name_exited", [edit, tmpl.id])
		edit.connect("gui_input", self, "_on_template_name_input", [edit, tmpl.id])
		name_row.add_child(edit)
		if tmpl.get("kind", "") == "group":
			var count = Label.new()
			count.text = "(%d)" % tmpl.items.size()
			count.hint_tooltip = "%d markers" % tmpl.items.size()
			name_row.add_child(count)
		row.add_child(name_row)

		var select_btn = Button.new()
		select_btn.text = "Select"
		select_btn.disabled = tool.template_capture_mode or tool.active_template_index == i
		select_btn.connect("pressed", self, "_on_template_select_pressed", [i])
		row.add_child(select_btn)

		var delete_btn = Button.new()
		delete_btn.text = "Delete"
		delete_btn.disabled = tool.template_capture_mode
		delete_btn.connect("pressed", self, "_on_template_delete_pressed", [i])
		row.add_child(delete_btn)

		_template_list_container.add_child(row)

	var scroll = get_control("TemplateScroll")
	if scroll:
		scroll.visible = tool.templates.size() > 0
		scroll.rect_min_size = Vector2(360, min(tool.templates.size() * 32 + 6, 130))
	sync_group_transform()

# Update the Add Template button text/disabled state during capture mode
func _update_template_capture_button(capturing: bool) -> void:
	if not _add_template_btn:
		return
	if capturing and not tool.template_group_capture:
		_add_template_btn.text = "Click a marker..."
		_add_template_btn.disabled = true
	else:
		_add_template_btn.text = "Add Template"
		_add_template_btn.disabled = capturing
	if _create_group_btn:
		_create_group_btn.text = "Save Group (%d)" % tool.template_group_ids.size() if tool.template_group_capture else "Create Group"
		_create_group_btn.disabled = (tool.template_group_ids.size() < 2) if tool.template_group_capture else capturing
		_cancel_group_btn.visible = capturing
	sync_group_transform()
	# Selection/deletion of saved templates cannot interrupt an unfinished capture.
	if _template_list_container:
		for row in _template_list_container.get_children():
			if row.is_queued_for_deletion(): continue
			row.get_child(0).get_child(0).editable = not capturing
			row.get_child(1).disabled = capturing or row.get_meta("template_index") == tool.active_template_index
			row.get_child(2).disabled = capturing

func _on_create_group_pressed() -> void:
	if tool.template_group_capture:
		tool.save_group_template()
	else:
		tool.start_group_capture()

func sync_group_transform() -> void:
	if _group_transform_container:
		_group_transform_container.visible = tool.active_template_index >= 0 and tool.active_template_index < tool.templates.size() and not tool.template_capture_mode
	update_overlap_panel_state()
	_set_spinbox_value("GroupRotation", tool.template_rotation_offset)
	_set_spinbox_value("GroupScale", tool.template_scale * 100.0)
	set_group_error("")

func set_group_error(message: String) -> void:
	if _group_error:
		_group_error.text = message
		_group_error.visible = message != ""

func _on_group_rotation_changed(value: float) -> void:
	tool.set_group_transform(value, true)

func _on_group_scale_changed(value: float) -> void:
	tool.set_group_transform(value / 100.0)

func text_field_has_focus() -> bool:
	return is_instance_valid(_text_focus_edit) and _text_focus_edit.is_visible_in_tree() and _text_focus_edit.has_focus()

func _connect_text_focus(edit: LineEdit) -> void:
	edit.connect("focus_entered", self, "_on_text_focus_entered", [edit])
	edit.connect("focus_exited", self, "_on_text_focus_exited", [edit])
	edit.connect("tree_exiting", self, "_on_text_focus_exited", [edit])

func _on_text_focus_entered(edit: LineEdit) -> void:
	_text_focus_edit = edit
	var editor = tool.parent_mod.Global.Editor
	if editor != null and (editor is Dictionary or is_instance_valid(editor)) and editor.get("SearchHasFocus") != null:
		_text_focus_editor = editor
		_previous_search_focus = editor.SearchHasFocus
		editor.SearchHasFocus = true

func _on_text_focus_exited(edit: LineEdit) -> void:
	if edit != _text_focus_edit:
		return
	if _text_focus_editor != null and (_text_focus_editor is Dictionary or is_instance_valid(_text_focus_editor)):
		_text_focus_editor.SearchHasFocus = _previous_search_focus
	_text_focus_editor = null
	_text_focus_edit = null

func release_text_focus() -> void:
	if is_instance_valid(_text_focus_edit):
		_text_focus_edit.release_focus()

func _on_template_name_entered(_text: String, edit: LineEdit) -> void:
	edit.release_focus()

func _on_template_name_exited(edit: LineEdit, template_id: int) -> void:
	tool.rename_template(template_id, edit.text)
	_restore_template_name(edit, template_id)

func _restore_template_name(edit: LineEdit, template_id: int) -> void:
	for template in tool.templates:
		if template.id == template_id:
			edit.text = template.name
			return

func _on_template_name_input(event: InputEvent, edit: LineEdit, template_id: int) -> void:
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		_restore_template_name(edit, template_id)
		edit.release_focus()
		edit.accept_event()

func _on_add_template_pressed() -> void:
	tool.start_template_capture()

func _on_template_select_pressed(index: int) -> void:
	tool.select_template(index)
	rebuild_template_list()

func _on_template_delete_pressed(index: int) -> void:
	tool.delete_template(index)

func _create_section_card(title_text: String) -> Dictionary:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.45)
	style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	card.add_stylebox_override("panel", style)

	var body = VBoxContainer.new()
	body.add_constant_override("separation", 6)

	var header = Label.new()
	header.text = title_text
	header.add_color_override("font_color", Color(0.75, 0.85, 0.96, 0.95))
	body.add_child(header)
	body.add_child(HSeparator.new())

	card.add_child(body)
	return {"card": card, "body": body}

# Create common settings UI (Marker Style + Map Display + persistent Guide Overlays)
func _create_common_settings_ui():
	var container = VBoxContainer.new()
	container.add_constant_override("separation", 10)

	# === MARKER STYLE ===
	var style_section = _create_section_card("Marker Style")
	var color_hbox = HBoxContainer.new()
	color_hbox.add_constant_override("separation", 8)
	var color_label = Label.new()
	color_label.text = "Color:"
	color_label.rect_min_size = Vector2(72, 0)
	color_hbox.add_child(color_label)

	var color_picker = ColorPickerButton.new()
	color_picker.color = tool.active_color
	color_picker.name = "ColorPicker"
	_controls["ColorPicker"] = color_picker
	color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker.connect("color_changed", tool, "set_color")
	color_hbox.add_child(color_picker)
	style_section.body.add_child(color_hbox)
	container.add_child(style_section.card)

	# === MAP DISPLAY ===
	var display_section = _create_section_card("Map Display")
	var visible_check = CheckButton.new()
	visible_check.text = "Show Markers"
	visible_check.pressed = tool.parent_mod.markers_visible
	visible_check.name = "MarkersVisibleCheckbox"
	_controls["MarkersVisibleCheckbox"] = visible_check
	visible_check.connect("toggled", self, "_on_markers_visible_toggled")
	display_section.body.add_child(visible_check)

	var opacity_hbox = _create_spinbox_row("Opacity (%):", "MarkersOpacitySpinBox",
		0, 100, 5, tool.parent_mod.markers_opacity * 100.0, self, "_on_markers_opacity_changed", false)
	display_section.body.add_child(opacity_hbox)
	container.add_child(display_section.card)

	# === GUIDE OVERLAYS (synced with ModConfig) ===
	var overlays_section = _create_section_card("Guide Overlays")
	var overlay_defs = [
		["CrossGuidesCheckbox",     "Proximity Cross",   tool.parent_mod.get("cross_guides_enabled"),    "_on_cross_guides_toggled",     "Show red center cross lines when cursor approaches map center (saved across sessions)"],
		["PermVerticalCheckbox",    "Vertical Center",   tool.parent_mod.get("perm_vertical_enabled"),   "_on_perm_vertical_toggled",    "Show permanent vertical center line (saved across sessions)"],
		["PermHorizontalCheckbox",  "Horizontal Center", tool.parent_mod.get("perm_horizontal_enabled"), "_on_perm_horizontal_toggled",  "Show permanent horizontal center line (saved across sessions)"],
		["PermCoordinatesCheckbox", "Grid Coordinates",  tool.parent_mod.get("show_coordinates_enabled"), "_on_perm_coordinates_toggled", "Show grid coordinate labels on permanent center lines (saved across sessions)"],
	]
	for def in overlay_defs:
		var check = CheckButton.new()
		check.name = def[0]
		check.text = def[1]
		check.pressed = bool(def[2]) if def[2] != null else false
		check.hint_tooltip = def[4]
		_controls[def[0]] = check
		check.connect("toggled", self, def[3])
		overlays_section.body.add_child(check)
	container.add_child(overlays_section.card)

	return container

func _create_spinbox_row(label_text, control_name, minimum, maximum, step, value, target, method, allow_greater = false, binds = []):
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.rect_min_size = Vector2(80, 0)
	row.add_child(label)
	var spin = SpinBox.new()
	spin.name = control_name
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.allow_greater = allow_greater
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.connect("value_changed", target, method, binds)
	_controls[control_name] = spin
	row.add_child(spin)
	return row

func _create_spacer(height):
	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, height)
	return spacer

# ============================================================================
# UI CALLBACKS — LINE SETTINGS
# ============================================================================

func _on_markers_visible_toggled(enabled):
	tool.parent_mod._on_markers_visible_toggled(enabled)

func _on_markers_opacity_changed(value):
	tool.parent_mod._on_markers_opacity_changed(value / 100.0)

func _on_cross_guides_toggled(enabled):
	tool.parent_mod._on_cross_guides_toggled(enabled)

func _on_perm_vertical_toggled(enabled):
	tool.parent_mod._on_perm_vertical_toggled(enabled)

func _on_perm_horizontal_toggled(enabled):
	tool.parent_mod._on_perm_horizontal_toggled(enabled)

func _on_perm_coordinates_toggled(enabled):
	tool.parent_mod._on_perm_coordinates_toggled(enabled)

func _sync_guide_overlay_checkboxes() -> void:
	if not tool or not tool.parent_mod:
		return
	var pairs = [
		["CrossGuidesCheckbox", "cross_guides_enabled"],
		["PermVerticalCheckbox", "perm_vertical_enabled"],
		["PermHorizontalCheckbox", "perm_horizontal_enabled"],
		["PermCoordinatesCheckbox", "show_coordinates_enabled"],
	]
	for pair in pairs:
		var value = tool.parent_mod.get(pair[1])
		if value != null:
			_set_control_value(pair[0], bool(value), "pressed")

# ============================================================================
# UI CALLBACKS — FILL MODE
# ============================================================================

func _on_delete_all_fills() -> void:
	tool.delete_all_fills()

# ============================================================================
# UI CALLBACKS — SHAPE SETTINGS
# ============================================================================

# Helper to update the pressed state of all shape mode buttons
func _update_shape_mode_buttons(active_mode: String):
	_sync_overlap_buttons(get_control("OverlapModesRow"), active_mode)

func _get_editor_content():
	if not tool or not tool.parent_mod or not tool.parent_mod.Global:
		return null
	var editor = tool.parent_mod.Global.Editor
	if not editor is Node or not is_instance_valid(editor):
		return null
	var content = editor.get_node_or_null("VPartition/Panels/HSplit/Content")
	return content if content is Control and is_instance_valid(content) else null

func _destroy_overlap_panel() -> void:
	if is_instance_valid(_top_bar):
		if _top_bar.get_parent() != null:
			_top_bar.get_parent().remove_child(_top_bar)
		_top_bar.queue_free()
	_top_bar = null
	_type_panel = null
	_settings_panel = null
	_line_top_settings = null
	_shape_top_settings = null
	_path_top_settings = null
	_fill_top_settings = null
	_template_top_settings = null
	for key in ["TopBar", "TypePanel", "SettingsPanel", "MarkerTypeModesRow", "ToolActionModesRow",
		"PlaceModeButton", "MoveModeButton", "DeleteModeButton", "OverlapModesRow",
		"LineTopSettings", "ShapeTopSettings", "PathTopSettings", "FillTopSettings", "TemplateTopSettings"]:
		_controls.erase(key)

func _create_compact_spinbox_row(label_text: String, control_name: String, minimum, maximum, step, value, target, method, allow_greater = false, spin_width: float = 64.0, label_control_name: String = "", binds = []):
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 4)
	if label_text != "":
		var label = Label.new()
		label.text = label_text
		label.valign = Label.VALIGN_CENTER
		if label_control_name != "":
			label.name = label_control_name
			_controls[label_control_name] = label
		row.add_child(label)
	var spin = SpinBox.new()
	spin.name = control_name
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.allow_greater = allow_greater
	spin.rect_min_size = Vector2(spin_width, 0)
	spin.connect("value_changed", target, method, binds)
	_controls[control_name] = spin
	row.add_child(spin)
	return row

func _create_line_top_settings_ui():
	var row = HBoxContainer.new()
	row.name = "LineTopSettings"
	row.alignment = BoxContainer.ALIGN_CENTER
	row.add_constant_override("separation", 8)
	_controls["LineTopSettings"] = row

	row.add_child(_create_compact_spinbox_row("Angle:", "AngleSpinBox",
		0, 360, 1, tool.active_angle, tool, "set_angle", false, 64.0))

	var quick_hbox = HBoxContainer.new()
	quick_hbox.add_constant_override("separation", 2)
	var quick_angles = [0, 45, 90, 135, 180, 225, 270, 315]
	for angle in quick_angles:
		var btn = Button.new()
		btn.text = "%d°" % angle
		btn.connect("pressed", tool, "set_angle", [angle])
		quick_hbox.add_child(btn)
	row.add_child(quick_hbox)

	row.add_child(VSeparator.new())

	var mirror_check = CheckButton.new()
	mirror_check.text = "Mirror"
	mirror_check.pressed = tool.active_mirror
	mirror_check.name = "MirrorCheckbox"
	_controls["MirrorCheckbox"] = mirror_check
	mirror_check.connect("toggled", tool, "set_mirror")
	row.add_child(mirror_check)

	var coords_check = CheckButton.new()
	coords_check.text = "Coords"
	coords_check.hint_tooltip = "Show Grid Coordinates"
	coords_check.pressed = tool.show_coordinates
	coords_check.name = "CoordinatesCheckbox"
	_controls["CoordinatesCheckbox"] = coords_check
	coords_check.connect("toggled", tool, "set_show_coordinates")
	row.add_child(coords_check)

	return row

func _create_shape_top_settings_ui():
	var wrapper = VBoxContainer.new()
	wrapper.name = "ShapeTopSettings"
	wrapper.add_constant_override("separation", 4)
	_controls["ShapeTopSettings"] = wrapper

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_CENTER
	row.add_constant_override("separation", 8)

	var subtype_option = OptionButton.new()
	subtype_option.add_item("Circle")
	subtype_option.set_item_metadata(0, tool.SHAPE_CIRCLE)
	subtype_option.add_item("Square")
	subtype_option.set_item_metadata(1, tool.SHAPE_SQUARE)
	subtype_option.add_item("Pentagon")
	subtype_option.set_item_metadata(2, tool.SHAPE_PENTAGON)
	subtype_option.add_item("Hexagon")
	subtype_option.set_item_metadata(3, tool.SHAPE_HEXAGON)
	subtype_option.add_item("Octagon")
	subtype_option.set_item_metadata(4, tool.SHAPE_OCTAGON)
	subtype_option.add_item("Custom")
	subtype_option.set_item_metadata(5, tool.SHAPE_CUSTOM)
	subtype_option.add_item("Spiral")
	subtype_option.set_item_metadata(6, tool.SHAPE_SPIRAL)
	subtype_option.selected = 0
	subtype_option.name = "ShapeSubtypeSelector"
	_controls["ShapeSubtypeSelector"] = subtype_option
	subtype_option.connect("item_selected", self, "_on_shape_subtype_changed")
	row.add_child(subtype_option)

	var sides_hbox = _create_compact_spinbox_row("Sides:", "ShapeSidesSpinBox",
		3, 64, 1, tool.active_shape_sides, tool, "set_shape_sides", false, 58.0)
	sides_hbox.name = "SidesRow"
	_controls["SidesRow"] = sides_hbox
	sides_hbox.visible = false
	row.add_child(sides_hbox)

	var size_sep = VSeparator.new()
	_controls["ShapeSizeSeparator"] = size_sep
	row.add_child(size_sep)

	var size_mode_hbox = HBoxContainer.new()
	size_mode_hbox.name = "SizeModeRow"
	_controls["SizeModeRow"] = size_mode_hbox
	var size_mode_option = OptionButton.new()
	size_mode_option.add_item("Radius")
	size_mode_option.set_item_metadata(0, "radius")
	size_mode_option.add_item("Side")
	size_mode_option.set_item_metadata(1, "side")
	size_mode_option.selected = 0
	size_mode_option.name = "ShapeSizeModeOption"
	_controls["ShapeSizeModeOption"] = size_mode_option
	size_mode_option.connect("item_selected", self, "_on_shape_size_mode_changed")
	size_mode_hbox.add_child(size_mode_option)
	size_mode_hbox.visible = false
	row.add_child(size_mode_hbox)

	var radius_hbox = _create_compact_spinbox_row("Radius:", "ShapeRadiusSpinBox",
		0.1, 100, 0.1, tool.active_shape_radius, tool, "set_shape_radius", true, 66.0, "ShapeRadiusLabel")
	radius_hbox.name = "RadiusRow"
	_controls["RadiusRow"] = radius_hbox
	radius_hbox.hint_tooltip = "Radius in grid cells (circumradius — distance from center to vertex)"
	row.add_child(radius_hbox)

	var side_hbox = _create_compact_spinbox_row("Side:", "ShapeSideSpinBox",
		0.1, 100, 0.1, tool.active_shape_side, tool, "set_shape_side", true, 66.0, "ShapeSideLabel")
	side_hbox.name = "SideRow"
	_controls["SideRow"] = side_hbox
	side_hbox.hint_tooltip = "Side length in grid cells — the shape is sized so its edges equal this value"
	side_hbox.visible = false
	row.add_child(side_hbox)

	var angle_sep = VSeparator.new()
	_controls["ShapeAngleSeparator"] = angle_sep
	row.add_child(angle_sep)

	var angle_hbox = _create_compact_spinbox_row("Angle:", "ShapeAngleSpinBox",
		0, 360, 1, tool.active_shape_angle, tool, "set_shape_angle", false, 64.0)
	_controls["ShapeAngleRow"] = angle_hbox
	row.add_child(angle_hbox)

	row.add_child(_create_spiral_settings_ui("Shape", true))
	wrapper.add_child(row)
	wrapper.add_child(_create_spiral_error_label("Shape"))
	return wrapper

func _create_path_top_settings_ui():
	var wrapper = VBoxContainer.new()
	wrapper.name = "PathTopSettings"
	wrapper.add_constant_override("separation", 2)
	_controls["PathTopSettings"] = wrapper

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_CENTER
	row.add_constant_override("separation", 6)

	var subtype = OptionButton.new()
	subtype.add_item("Freeform")
	subtype.add_item("Spiral")
	subtype.connect("item_selected", tool, "set_path_subtype")
	_controls["PathSubtypeSelector"] = subtype
	row.add_child(subtype)

	row.add_child(VSeparator.new())

	var end_arrow_check = CheckButton.new()
	end_arrow_check.text = "Arrow"
	end_arrow_check.hint_tooltip = "End with Arrow"
	end_arrow_check.pressed = tool.active_path_end_arrow
	end_arrow_check.name = "PathEndArrowCheckbox"
	_controls["PathEndArrowCheckbox"] = end_arrow_check
	end_arrow_check.connect("toggled", tool, "set_path_end_arrow")
	row.add_child(end_arrow_check)

	var arrow_settings = HBoxContainer.new()
	arrow_settings.name = "PathArrowSettings"
	arrow_settings.add_constant_override("separation", 6)
	_controls["PathArrowSettings"] = arrow_settings
	arrow_settings.visible = tool.active_path_end_arrow
	arrow_settings.add_child(_create_compact_spinbox_row("Len:", "PathArrowHeadLengthSpinBox",
		10.0, 200.0, 5.0, tool.active_arrow_head_length, tool, "set_path_arrow_head_length", true, 58.0))
	arrow_settings.add_child(_create_compact_spinbox_row("Angle:", "PathArrowHeadAngleSpinBox",
		10.0, 60.0, 5.0, tool.active_arrow_head_angle, tool, "set_path_arrow_head_angle", false, 56.0))
	row.add_child(arrow_settings)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel Path"
	cancel_btn.name = "PathCancelButton"
	_controls["PathCancelButton"] = cancel_btn
	cancel_btn.connect("pressed", tool, "_cancel_path_placement")
	cancel_btn.visible = false
	row.add_child(cancel_btn)

	row.add_child(_create_spiral_settings_ui("Path", false))
	wrapper.add_child(row)
	wrapper.add_child(_create_spiral_error_label("Path"))
	return wrapper

func _create_fill_top_settings_ui():
	var row = HBoxContainer.new()
	row.name = "FillTopSettings"
	row.alignment = BoxContainer.ALIGN_CENTER
	row.add_constant_override("separation", 8)
	_controls["FillTopSettings"] = row

	var hint = Label.new()
	hint.text = "Click inside a Shape to fill"
	hint.valign = Label.VALIGN_CENTER
	row.add_child(hint)

	var delete_fills_btn = Button.new()
	delete_fills_btn.text = "Delete All Fills"
	delete_fills_btn.connect("pressed", self, "_on_delete_all_fills")
	row.add_child(delete_fills_btn)

	return row

func _create_template_top_settings_ui():
	var wrapper = VBoxContainer.new()
	wrapper.name = "TemplateTopSettings"
	wrapper.add_constant_override("separation", 6)
	_controls["TemplateTopSettings"] = wrapper

	var actions_row = HBoxContainer.new()
	actions_row.alignment = BoxContainer.ALIGN_CENTER
	actions_row.add_constant_override("separation", 6)

	_add_template_btn = Button.new()
	_add_template_btn.text = "Add Template"
	_add_template_btn.hint_tooltip = "Click a marker on the map to save it as a template"
	_add_template_btn.name = "AddTemplateButton"
	_controls["AddTemplateButton"] = _add_template_btn
	_add_template_btn.connect("pressed", self, "_on_add_template_pressed")
	actions_row.add_child(_add_template_btn)

	_create_group_btn = Button.new()
	_create_group_btn.text = "Create Group"
	_create_group_btn.hint_tooltip = "Click markers to toggle selection, then save as a group"
	_create_group_btn.connect("pressed", self, "_on_create_group_pressed")
	actions_row.add_child(_create_group_btn)

	_cancel_group_btn = Button.new()
	_cancel_group_btn.text = "Cancel"
	_cancel_group_btn.visible = false
	_cancel_group_btn.connect("pressed", tool, "cancel_template_capture")
	actions_row.add_child(_cancel_group_btn)

	_group_transform_container = HBoxContainer.new()
	_group_transform_container.alignment = BoxContainer.ALIGN_CENTER
	_group_transform_container.add_constant_override("separation", 6)
	_group_transform_container.visible = false
	_group_transform_container.add_child(VSeparator.new())
	_group_transform_container.add_child(_create_compact_spinbox_row("Rot:", "GroupRotation", 0, 360, 1, 0, self, "_on_group_rotation_changed", false, 58.0))
	_group_transform_container.add_child(_create_compact_spinbox_row("Scale %:", "GroupScale", 1, 10000, 1, 100, self, "_on_group_scale_changed", false, 64.0))
	for name in ["GroupRotation", "GroupScale"]:
		_connect_text_focus(get_control(name).get_line_edit())
	var reset = Button.new()
	reset.text = "Reset"
	reset.hint_tooltip = "Reset Transform"
	reset.connect("pressed", tool, "reset_group_transform")
	_group_transform_container.add_child(reset)
	actions_row.add_child(_group_transform_container)

	wrapper.add_child(actions_row)

	_group_error = Label.new()
	_group_error.align = Label.ALIGN_CENTER
	_group_error.autowrap = true
	_group_error.visible = false
	wrapper.add_child(_group_error)

	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(360, 0)
	scroll.visible = false
	scroll.name = "TemplateScroll"
	_controls["TemplateScroll"] = scroll

	_template_list_container = VBoxContainer.new()
	_template_list_container.name = "TemplateListContainer"
	_controls["TemplateListContainer"] = _template_list_container
	_template_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_template_list_container)
	wrapper.add_child(scroll)

	return wrapper

func _create_floating_panel_container(panel_name: String) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var style = StyleBoxFlat.new()
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_detail = 4
	var editor = tool.parent_mod.Global.Editor
	var tools_node = editor.get_node_or_null("VPartition/Panels/Tools")
	if tools_node and tools_node.material:
		panel.material = tools_node.material
		style.bg_color = Color(1, 1, 1, 1)
	else:
		style.bg_color = Color(0.14, 0.14, 0.16, 0.92)
	panel.add_stylebox_override("panel", style)
	return panel

func _create_marker_type_row(row_name: String, button_size: Vector2):
	var row = HBoxContainer.new()
	row.name = row_name
	row.alignment = BoxContainer.ALIGN_CENTER
	_controls[row_name] = row
	var btn_defs = [
		["LineTypeButton",     "line64.png",     tool.MARKER_TYPE_LINE,     "Line - place infinite alignment guide lines"],
		["ShapeTypeButton",    "shape64.png",    tool.MARKER_TYPE_SHAPE,    "Shape - place geometric shapes and spirals"],
		["PathTypeButton",     "path64.png",     tool.MARKER_TYPE_PATH,     "Path - draw multi-point paths and arrows"],
		["FillTypeButton",     "fill64.png",     tool.MARKER_TYPE_FILL,     "Fill - fill closed regions inside shapes"],
		["TemplateTypeButton", "template64.png", tool.MARKER_TYPE_TEMPLATE, "Template - save and reuse marker templates"],
	]
	for def in btn_defs:
		var btn = Button.new()
		btn.name = def[0]
		btn.toggle_mode = true
		btn.hint_tooltip = def[3]
		btn.rect_min_size = button_size
		btn.set_meta("marker_type", def[2])
		var icon = _load_icon(def[1], 0.5)
		if icon:
			btn.icon = icon
		btn.connect("pressed", tool, "set_marker_type", [def[2]])
		_controls[def[0]] = btn
		row.add_child(btn)
	_sync_marker_type_buttons(tool.active_marker_type)
	return row

func _sync_marker_type_buttons(active_type: String) -> void:
	var row = get_control("MarkerTypeModesRow")
	if not row:
		return
	for btn in row.get_children():
		btn.set_block_signals(true)
		btn.pressed = btn.get_meta("marker_type") == active_type
		btn.set_block_signals(false)

func _create_tool_action_row(row_name: String):
	var row = HBoxContainer.new()
	row.name = row_name
	row.alignment = BoxContainer.ALIGN_CENTER
	_controls[row_name] = row
	var btn_defs = [
		["PlaceModeButton",  "Place",  "place",  "Place Mode - place new guide markers"],
		["MoveModeButton",   "Move",   "move",   "Move Mode (Ctrl+M) - drag existing markers"],
		["DeleteModeButton", "Delete", "delete", "Delete Mode (Ctrl+D) - click markers to remove"],
	]
	for def in btn_defs:
		var btn = Button.new()
		btn.name = def[0]
		btn.text = def[1]
		btn.toggle_mode = true
		btn.hint_tooltip = def[3]
		btn.rect_min_size = Vector2(56, 40)
		btn.set_meta("action_mode", def[2])
		btn.connect("pressed", self, "_on_tool_action_mode_pressed", [def[2]])
		_controls[def[0]] = btn
		row.add_child(btn)
	_sync_tool_action_buttons()
	return row

func _on_tool_action_mode_pressed(mode: String) -> void:
	if mode == "place":
		if tool.move_mode:
			tool.set_move_mode(false)
		if tool.delete_mode:
			tool.set_delete_mode(false)
		_sync_tool_action_buttons()
	elif mode == "move":
		tool.set_move_mode(true)
	elif mode == "delete":
		tool.set_delete_mode(true)

func _sync_tool_action_buttons() -> void:
	var row = get_control("ToolActionModesRow")
	if not row:
		return
	var active = "delete" if tool.delete_mode else ("move" if tool.move_mode else "place")
	for btn in row.get_children():
		btn.set_block_signals(true)
		btn.pressed = btn.get_meta("action_mode") == active
		btn.set_block_signals(false)

func _create_overlap_panel() -> void:
	_destroy_overlap_panel()
	var content = _get_editor_content()
	if not content:
		return

	var top_bar = VBoxContainer.new()
	top_bar.name = "GuidesLinesTopBar"
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.anchor_left = 0.5
	top_bar.anchor_right = 0.5
	top_bar.anchor_top = 0.0
	top_bar.anchor_bottom = 0.0
	top_bar.margin_left = 0.0
	top_bar.margin_right = 0.0
	top_bar.margin_top = 10.0
	top_bar.margin_bottom = 0.0
	top_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_bar.grow_vertical = Control.GROW_DIRECTION_END
	top_bar.add_constant_override("separation", 6)

	# Row 1: Marker Type icons | Place / Move / Delete | Overlap Modes (always visible)
	var type_panel = _create_floating_panel_container("GuidesLinesTypePanel")
	var type_hbox = HBoxContainer.new()
	type_hbox.name = "TypePanelContent"
	type_hbox.alignment = BoxContainer.ALIGN_CENTER
	type_hbox.add_constant_override("separation", 8)
	type_hbox.add_child(_create_marker_type_row("MarkerTypeModesRow", Vector2(40, 40)))
	type_hbox.add_child(VSeparator.new())
	type_hbox.add_child(_create_tool_action_row("ToolActionModesRow"))
	type_hbox.add_child(VSeparator.new())
	type_hbox.add_child(_create_overlap_modes_row("OverlapModesRow", Vector2(40, 40)))
	type_panel.add_child(type_hbox)
	top_bar.add_child(type_panel)

	# Row 2: Active tool settings bar (Line / Shape / Path / Fill / Template)
	var settings_panel = _create_floating_panel_container("GuidesLinesSettingsPanel")
	var settings_hbox = HBoxContainer.new()
	settings_hbox.name = "SettingsPanelContent"
	settings_hbox.alignment = BoxContainer.ALIGN_CENTER

	_line_top_settings = _create_line_top_settings_ui()
	_shape_top_settings = _create_shape_top_settings_ui()
	_path_top_settings = _create_path_top_settings_ui()
	_fill_top_settings = _create_fill_top_settings_ui()
	_template_top_settings = _create_template_top_settings_ui()
	_shape_top_settings.visible = false
	_path_top_settings.visible = false
	_fill_top_settings.visible = false
	_template_top_settings.visible = false
	settings_hbox.add_child(_line_top_settings)
	settings_hbox.add_child(_shape_top_settings)
	settings_hbox.add_child(_path_top_settings)
	settings_hbox.add_child(_fill_top_settings)
	settings_hbox.add_child(_template_top_settings)

	settings_panel.add_child(settings_hbox)
	top_bar.add_child(settings_panel)

	content.add_child(top_bar)

	_top_bar = top_bar
	_type_panel = type_panel
	_settings_panel = settings_panel
	_controls["TopBar"] = top_bar
	_controls["TypePanel"] = type_panel
	_controls["SettingsPanel"] = settings_panel

func _should_show_overlap_panel() -> bool:
	if not tool or not tool.is_enabled:
		return false
	if tool.active_marker_type == tool.MARKER_TYPE_SHAPE:
		return true
	if tool.active_marker_type == tool.MARKER_TYPE_TEMPLATE:
		if tool.template_capture_mode or tool.is_group_template():
			return false
		if tool.active_template_index >= 0 and tool.active_template_index < tool.templates.size():
			return tool.templates[tool.active_template_index].data.get("marker_type", "") == tool.MARKER_TYPE_SHAPE
	return false

func _should_show_settings_panel() -> bool:
	return tool != null and tool.is_enabled

func update_overlap_panel_state() -> void:
	if not is_instance_valid(_top_bar):
		if _get_editor_content() != null:
			_create_overlap_panel()
		else:
			return
	var enabled = tool != null and tool.is_enabled
	var disabled = tool.delete_mode or tool.move_mode
	_top_bar.visible = enabled
	if is_instance_valid(_type_panel):
		_type_panel.visible = enabled
	var type_row = get_control("MarkerTypeModesRow")
	if type_row:
		_sync_marker_type_buttons(tool.active_marker_type)
		for btn in type_row.get_children():
			if btn is Button:
				btn.disabled = disabled
	_sync_tool_action_buttons()
	var overlap_disabled = disabled or not _should_show_overlap_panel()
	var row = get_control("OverlapModesRow")
	if row:
		_sync_overlap_buttons(row, _active_overlap_mode())
		for btn in row.get_children():
			if btn is Button:
				btn.disabled = overlap_disabled
	if is_instance_valid(_settings_panel):
		_settings_panel.visible = _should_show_settings_panel()
	if is_instance_valid(_line_top_settings):
		_line_top_settings.visible = tool.active_marker_type == tool.MARKER_TYPE_LINE
	if is_instance_valid(_shape_top_settings):
		_shape_top_settings.visible = tool.active_marker_type == tool.MARKER_TYPE_SHAPE
	if is_instance_valid(_path_top_settings):
		_path_top_settings.visible = tool.active_marker_type == tool.MARKER_TYPE_PATH
	if is_instance_valid(_fill_top_settings):
		_fill_top_settings.visible = tool.active_marker_type == tool.MARKER_TYPE_FILL
	if is_instance_valid(_template_top_settings):
		_template_top_settings.visible = tool.active_marker_type == tool.MARKER_TYPE_TEMPLATE

func is_mouse_over_floating_ui() -> bool:
	for panel in [_type_panel, _settings_panel]:
		if is_instance_valid(panel) and panel.is_visible_in_tree():
			if Rect2(Vector2.ZERO, panel.rect_size).has_point(panel.get_local_mouse_position()):
				return true
	return false

# ============================================================================
# MARKER TYPE SWITCHING
# ============================================================================

# Sync the top marker type bar and type-specific sidebar to match tool.active_marker_type.
# Called by the tool when it changes active_marker_type externally
# (e.g. when Delete Mode forces a reset away from Fill).
func sync_type_selector_to_active_type() -> void:
	_sync_marker_type_buttons(tool.active_marker_type)
	if type_specific_container:
		_switch_type_ui(tool.active_marker_type)

# Switch visible type-specific UI container
func _switch_type_ui(marker_type):
	# Hide all type-specific containers
	for child in type_specific_container.get_children():
		child.visible = false

	# Show the selected type's container
	match marker_type:
		tool.MARKER_TYPE_LINE:
			if line_settings_container:
				line_settings_container.visible = true
		tool.MARKER_TYPE_SHAPE:
			if shape_settings_container:
				shape_settings_container.visible = true
		tool.MARKER_TYPE_PATH:
			if path_settings_container:
				path_settings_container.visible = true
		tool.MARKER_TYPE_FILL:
			if fill_settings_container:
				fill_settings_container.visible = true
		tool.MARKER_TYPE_TEMPLATE:
			if template_settings_container:
				template_settings_container.visible = true
	update_overlap_panel_state()

# ============================================================================
# WIDGET VALUE HELPERS
# ============================================================================

# Helper: set value on a named SpinBox inside the tool panel.
func _set_spinbox_value(node_name: String, value: float) -> void:
	_set_control_value(node_name, value, "value")

func _update_angle_spinbox():
	_set_spinbox_value("AngleSpinBox", tool.active_angle)


func _update_markers_visible_checkbox():
	_set_control_value("MarkersVisibleCheckbox", tool.parent_mod.markers_visible, "pressed")

func _update_markers_opacity_spinbox():
	_set_spinbox_value("MarkersOpacitySpinBox", tool.parent_mod.markers_opacity * 100.0)

func _update_mirror_checkbox():
	_set_control_value("MirrorCheckbox", tool.active_mirror, "pressed")

func _update_shape_radius_spinbox():
	_set_spinbox_value("ShapeRadiusSpinBox", tool.active_shape_radius)

func _update_shape_side_spinbox():
	_set_spinbox_value("ShapeSideSpinBox", tool.active_shape_side)

# Update the size mode OptionButton and show/hide Radius/Side rows accordingly.
func _update_shape_size_mode_ui():
	if not shape_settings_container:
		return
	var subtype_selector = get_control("ShapeSubtypeSelector")
	var is_circle = false
	if subtype_selector:
		var preset = subtype_selector.get_item_metadata(subtype_selector.selected)
		is_circle = (preset == tool.SHAPE_CIRCLE)
	var size_mode_row = get_control("SizeModeRow")
	var is_spiral = tool.active_shape_preset == tool.SHAPE_SPIRAL
	var radius_row = get_control("RadiusRow")
	var side_row = get_control("SideRow")
	var radius_label = get_control("ShapeRadiusLabel")
	var side_label = get_control("ShapeSideLabel")
	var size_sep = get_control("ShapeSizeSeparator")
	var angle_sep = get_control("ShapeAngleSeparator")
	var mode_option   = get_control("ShapeSizeModeOption")
	if size_sep:
		size_sep.visible = not is_spiral
	if angle_sep:
		angle_sep.visible = not is_spiral
	if size_mode_row:
		size_mode_row.visible = not is_circle and not is_spiral
	if radius_row:
		radius_row.visible = not is_spiral and (is_circle or tool.active_shape_size_mode == "radius")
	if radius_label:
		radius_label.visible = is_circle
	if side_row:
		side_row.visible = not is_spiral and (not is_circle and tool.active_shape_size_mode == "side")
	if side_label:
		side_label.visible = false
	if mode_option:
		mode_option.set_block_signals(true)
		mode_option.selected = 0 if tool.active_shape_size_mode == "radius" else 1
		mode_option.set_block_signals(false)

func _update_shape_angle_spinbox():
	_set_spinbox_value("ShapeAngleSpinBox", tool.active_shape_angle)

func _update_shape_sides_spinbox():
	_set_spinbox_value("ShapeSidesSpinBox", tool.active_shape_sides)

func _update_path_end_arrow_checkbox():
	if not path_settings_container:
		return
	var checkbox = get_control("PathEndArrowCheckbox")
	if checkbox:
		checkbox.pressed = tool.active_path_end_arrow
	var arrow_settings = get_control("PathArrowSettings")
	if arrow_settings:
		arrow_settings.visible = tool.active_path_end_arrow

func _update_path_arrow_head_length_spinbox():
	_set_spinbox_value("PathArrowHeadLengthSpinBox", tool.active_arrow_head_length)

func _update_path_arrow_head_angle_spinbox():
	_set_spinbox_value("PathArrowHeadAngleSpinBox", tool.active_arrow_head_angle)

# Load an optional icon from the mod root; return null if unavailable.
func _load_icon(filename: String, scale: float = 1.0):
	var path = tool.parent_mod.Global.Root + "icons/" + filename
	var key = path + ":" + str(scale)
	if _icon_cache.has(key):
		return _icon_cache[key]
	var image = Image.new()
	if image.load(path) != OK:
		return null
	
	# Apply scaling if needed
	if scale != 1.0 and scale > 0.0:
		var new_width = int(image.get_width() * scale)
		var new_height = int(image.get_height() * scale)
		if new_width > 0 and new_height > 0:
			image.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)
	
	var texture = ImageTexture.new()
	texture.create_from_image(image, 0)
	_icon_cache[key] = texture
	return texture

func get_control(control_name: String):
	var control = _controls.get(control_name)
	return control if is_instance_valid(control) else null

func _set_control_value(control_name: String, value, property: String) -> void:
	var control = get_control(control_name)
	if control:
		var blocked = control.is_blocking_signals()
		control.set_block_signals(true)
		control.set(property, value)
		control.set_block_signals(blocked)

func _create_overlap_modes_row(row_name: String, button_size: Vector2):
	var modes_hbox = HBoxContainer.new()
	modes_hbox.name = row_name
	modes_hbox.alignment = BoxContainer.ALIGN_CENTER
	_controls[row_name] = modes_hbox
	var btn_defs = [
		["NormalModeButton",     "normal64.png",     "Normal Mode - place shapes without interaction"],
		["MergeModeButton",      "merge64.png",      "Merge Mode - new shape is merged (union) into any intersecting existing shapes"],
		["ConformingModeButton", "conforming64.png", "Conforming Mode - new shape dents the outlines of existing shapes"],
		["WrappingModeButton",   "wrapping64.png",   "Wrapping Mode - new shape is dented by existing shapes' outlines"],
		["DifferenceModeButton", "difference64.png", "Difference Mode - fills the overlapping area into existing shapes without placing a new shape"],
		["CutModeButton",        "cut64.png",        "Cut Mode - clips existing shapes with the new shape outline; intersected shapes become Path markers"],
	]
	var mode_keys = ["normal", "merge", "conforming", "wrapping", "difference", "cut"]

	for i in range(btn_defs.size()):
		var def = btn_defs[i]
		var btn = Button.new()
		btn.name = def[0]
		btn.toggle_mode = true
		btn.hint_tooltip = def[2]
		btn.rect_min_size = button_size
		var icon = _load_icon(def[1], 0.5)
		if icon:
			btn.icon = icon
		btn.connect("pressed", tool, "set_shape_mode", [mode_keys[i]])
		modes_hbox.add_child(btn)

	_sync_overlap_buttons(modes_hbox, _active_overlap_mode())
	return modes_hbox

func _active_overlap_mode() -> String:
	if tool.merge_shapes: return "merge"
	if tool.conforming_mode: return "conforming"
	if tool.wrapping_mode: return "wrapping"
	if tool.difference_mode: return "difference"
	if tool.cut_mode: return "cut"
	return "normal"

func _sync_overlap_buttons(row, active_mode: String) -> void:
	if not row:
		return
	var modes = ["normal", "merge", "conforming", "wrapping", "difference", "cut"]
	for index in range(row.get_child_count()):
		var button = row.get_child(index)
		button.set_block_signals(true)
		button.pressed = modes[index] == active_mode
		button.set_block_signals(false)

func sync_type_settings_controls(marker_type):
	if marker_type == tool.MARKER_TYPE_LINE:
		_update_angle_spinbox()
		_update_mirror_checkbox()

	elif marker_type == tool.MARKER_TYPE_SHAPE:
		sync_shape_preset(tool.active_shape_preset)
		_update_shape_radius_spinbox()
		_update_shape_angle_spinbox()
		_update_shape_sides_spinbox()
		_update_shape_side_spinbox()
		_update_shape_size_mode_ui()

	elif marker_type == tool.MARKER_TYPE_PATH:
		_set_control_value("PathSubtypeSelector", 1 if tool.active_path_subtype == "Spiral" else 0, "selected")
		var spiral_panel = get_control("PathSpiralPanel")
		if spiral_panel: spiral_panel.visible = tool.active_path_subtype == "Spiral"
		_update_path_end_arrow_checkbox()
		_update_path_arrow_head_length_spinbox()
		_update_path_arrow_head_angle_spinbox()
	sync_spiral_controls()

func _on_shape_size_mode_changed(mode_index):
	var option = get_control("ShapeSizeModeOption")
	if option:
		tool.set_shape_size_mode(option.get_item_metadata(mode_index))

func _on_shape_subtype_changed(subtype_index):
	var option = get_control("ShapeSubtypeSelector")
	if option:
		tool.set_shape_preset(option.get_item_metadata(subtype_index))

func sync_shape_preset(preset):
	var option = get_control("ShapeSubtypeSelector")
	if option:
		for index in range(option.get_item_count()):
			if option.get_item_metadata(index) == preset:
				_set_control_value("ShapeSubtypeSelector", index, "selected")
				break
	var sides_row = get_control("SidesRow")
	if sides_row:
		sides_row.visible = preset == tool.SHAPE_CUSTOM
	var angle_row = get_control("ShapeAngleRow")
	if angle_row: angle_row.visible = preset != tool.SHAPE_SPIRAL
	var panel = get_control("ShapeSpiralPanel")
	if panel: panel.visible = preset == tool.SHAPE_SPIRAL
	_update_shape_size_mode_ui()
	sync_spiral_controls()

func _create_spiral_settings_ui(prefix: String, closed: bool):
	var panel = HBoxContainer.new()
	panel.alignment = BoxContainer.ALIGN_CENTER
	panel.add_constant_override("separation", 5)
	_controls[prefix + "SpiralPanel"] = panel
	panel.visible = false

	panel.add_child(VSeparator.new())

	var mode = OptionButton.new()
	mode.add_item("Outer R")
	mode.add_item("Spacing")
	mode.hint_tooltip = "Size by: Outer Radius / Turn Spacing (centerline, in cells)"
	mode.connect("item_selected", tool, "set_spiral_value", ["size_by"])
	_controls[prefix + "SpiralSizeMode"] = mode
	panel.add_child(mode)

	for spec in [["Outer:", "outer_radius", 0.01, 1000, 0.1, 56.0],
		["Inner:", "inner_radius", 0, 999, 0.1, 54.0],
		["Turns:", "turns", 0.01, 8, 0.05, 54.0],
		["Spacing:", "spacing", 0.01, 1000, 0.1, 54.0],
		["Angle:", "angle", 0, 360, 1, 54.0]]:
		panel.add_child(_create_compact_spinbox_row(spec[0], prefix + "Spiral_" + spec[1],
			spec[2], spec[3], spec[4], 1, tool, "set_spiral_value", false, spec[5], "", [spec[1]]))
	if closed:
		panel.add_child(_create_compact_spinbox_row("Width:", prefix + "Spiral_width",
			0.01, 1000, 0.1, 1, tool, "set_spiral_value", false, 54.0, "", ["width"]))
	for spec in [["CW", "clockwise", "Clockwise (inner to outer)"], ["Rev", "reverse", "Reverse Path"]]:
		if closed and spec[1] == "reverse":
			continue
		var check = CheckButton.new()
		check.text = spec[0]
		check.hint_tooltip = spec[2]
		check.connect("toggled", tool, "set_spiral_value", [spec[1]])
		_controls[prefix + "Spiral_" + spec[1]] = check
		panel.add_child(check)
	return panel

func _create_spiral_error_label(prefix: String):
	var error = Label.new()
	error.align = Label.ALIGN_CENTER
	error.autowrap = true
	error.visible = false
	error.add_color_override("font_color", Color(1, 0.45, 0.3))
	_controls[prefix + "SpiralError"] = error
	return error

func sync_spiral_controls():
	if not tool.is_spiral_active():
		return
	var prefix = "Shape" if tool.active_marker_type == tool.MARKER_TYPE_SHAPE else "Path"
	var settings = tool.spiral_settings()
	for key in settings:
		if key in ["clockwise", "reverse"]:
			_set_control_value(prefix + "Spiral_" + key, settings[key], "pressed")
		elif key != "size_by":
			_set_spinbox_value(prefix + "Spiral_" + key, settings[key])
	_set_spinbox_value(prefix + "Spiral_spacing", (settings.outer_radius - settings.inner_radius) / settings.turns)
	_set_control_value(prefix + "SpiralSizeMode", 0 if settings.size_by == "radius" else 1, "selected")
	for key in ["outer_radius", "spacing"]:
		var spin = get_control(prefix + "Spiral_" + key)
		if spin: spin.editable = (settings.size_by == "radius") == (key == "outer_radius")
	var error = get_control(prefix + "SpiralError")
	if error:
		error.text = tool.spiral_result().error
		error.visible = error.text != ""
