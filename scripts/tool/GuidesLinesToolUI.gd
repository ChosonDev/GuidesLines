extends Reference

# GuidesLinesToolUI - UI panel creation, callbacks, and widget helpers for GuidesLinesTool.
# Holds all UI node references and handles user input from the tool panel.
# Accesses and mutates tool state exclusively through the `tool` reference.

const CLASS_NAME = "GuidesLinesToolUI"

# Marker type constants (mirrored from GuidesLinesTool for self-contained use)
const MARKER_TYPE_LINE = "Line"
const MARKER_TYPE_SHAPE = "Shape"
const MARKER_TYPE_PATH = "Path"

# Shape preset labels
const SHAPE_CIRCLE = "Circle"
const SHAPE_SQUARE = "Square"
const SHAPE_PENTAGON = "Pentagon"
const SHAPE_HEXAGON = "Hexagon"
const SHAPE_OCTAGON = "Octagon"
const SHAPE_CUSTOM = "Custom"

# Default values used for type-switching fallbacks
const DEFAULT_SHAPE_SIDES = 6
const DEFAULT_ARROW_HEAD_LENGTH = 50.0
const DEFAULT_ARROW_HEAD_ANGLE = 30.0

var tool = null  # Reference to GuidesLinesTool

# UI node references (owned by this class)
var type_selector = null              # OptionButton for marker type selection
var type_specific_container = null    # Container for type-specific settings
var line_settings_container = null    # Settings for Line type
var shape_settings_container = null   # Settings for Shape type
var path_settings_container = null    # Settings for Path type

func _init(tool_ref):
	tool = tool_ref

# ============================================================================
# PANEL STATE UPDATES
# ============================================================================

func update_ui():
	if not tool.tool_panel:
		return
	var container = tool.tool_panel.Align.get_child(0)
	if container:
		# Update cancel button visibility for Path mode
		if tool.active_marker_type == MARKER_TYPE_PATH:
			var path_container = type_specific_container.get_node_or_null("PathSettings")
			if path_container:
				var cancel_btn = path_container.get_node_or_null("PathCancelButton")
				if cancel_btn:
					cancel_btn.visible = tool.path_placement_active

func update_ui_checkboxes_state():
	if not tool.tool_panel:
		return
	var container = tool.tool_panel.Align.get_child(0)
	if container:
		# Disable controls when delete mode is on
		for child in container.get_children():
			if child is CheckButton:
				if child.name == "DeleteModeCheckbox":
					continue  # Don't disable delete mode checkbox itself
				child.disabled = tool.delete_mode
			# Also disable spinboxes, color picker, and buttons
			elif child is HBoxContainer:
				for subchild in child.get_children():
					if subchild is SpinBox or subchild is ColorPickerButton:
						subchild.editable = not tool.delete_mode
			elif child is Button and child.text != "Delete All Markers":
				child.disabled = tool.delete_mode
			elif child is GridContainer:
				for btn in child.get_children():
					if btn is Button:
						btn.disabled = tool.delete_mode

# ============================================================================
# PANEL CREATION
# ============================================================================

# Create the UI panel for the tool with all controls
# Includes marker type selector and type-specific settings
func create_ui_panel():
	if not tool.tool_panel:
		return

	var container = VBoxContainer.new()

	# Title
	var title = Label.new()
	title.text = "Guide Markers"
	title.align = Label.ALIGN_CENTER
	container.add_child(title)

	container.add_child(_create_spacer(10))

	# === MARKER TYPE SELECTOR ===
	var type_label = Label.new()
	type_label.text = "Marker Type:"
	container.add_child(type_label)

	type_selector = OptionButton.new()
	type_selector.add_item("Line")
	type_selector.set_item_metadata(0, MARKER_TYPE_LINE)
	type_selector.add_item("Shape")
	type_selector.set_item_metadata(1, MARKER_TYPE_SHAPE)
	type_selector.add_item("Path")
	type_selector.set_item_metadata(2, MARKER_TYPE_PATH)
	type_selector.selected = 0
	type_selector.name = "TypeSelector"
	type_selector.connect("item_selected", self, "_on_marker_type_changed")
	container.add_child(type_selector)

	container.add_child(_create_spacer(15))

	# === TYPE-SPECIFIC SETTINGS CONTAINER ===
	type_specific_container = VBoxContainer.new()
	type_specific_container.name = "TypeSpecificContainer"

	# Create Line settings UI
	line_settings_container = _create_line_settings_ui()
	line_settings_container.name = "LineSettings"
	type_specific_container.add_child(line_settings_container)

	# Create Shape settings UI
	shape_settings_container = _create_shape_settings_ui()
	shape_settings_container.name = "ShapeSettings"
	shape_settings_container.visible = false
	type_specific_container.add_child(shape_settings_container)

	# Create Path settings UI
	path_settings_container = _create_path_settings_ui()
	path_settings_container.name = "PathSettings"
	path_settings_container.visible = false
	type_specific_container.add_child(path_settings_container)

	container.add_child(type_specific_container)

	container.add_child(_create_spacer(20))

	# === COMMON SETTINGS ===
	var common_container = _create_common_settings_ui()
	container.add_child(common_container)

	container.add_child(_create_spacer(20))

	# === DELETE MODE ===
	var delete_check = CheckButton.new()
	delete_check.text = "Delete Markers Mode"
	delete_check.pressed = tool.delete_mode
	delete_check.name = "DeleteModeCheckbox"
	delete_check.connect("toggled", tool.parent_mod, "_on_delete_mode_toggled", [tool])
	container.add_child(delete_check)

	var delete_all_btn = Button.new()
	delete_all_btn.text = "Delete All Markers"
	delete_all_btn.connect("pressed", tool.parent_mod, "_on_delete_all_markers", [tool])
	container.add_child(delete_all_btn)

	tool.tool_panel.Align.add_child(container)

# ============================================================================
# UI CREATION HELPERS FOR MARKER TYPES
# ============================================================================

# Create UI for Line marker type
func _create_line_settings_ui():
	var container = VBoxContainer.new()

	# Quick Angle Buttons
	var quick_label = Label.new()
	quick_label.text = "Quick Angles:"
	container.add_child(quick_label)

	var quick_grid = GridContainer.new()
	quick_grid.columns = 4

	var quick_angles = [0, 45, 90, 135, 180, 225, 270, 315]
	var angle_names = ["0°", "45°", "90°", "135°", "180°", "225°", "270°", "315°"]

	for i in range(quick_angles.size()):
		var btn = Button.new()
		btn.text = angle_names[i]
		btn.connect("pressed", self, "_on_quick_angle_pressed", [quick_angles[i]])
		quick_grid.add_child(btn)

	container.add_child(quick_grid)
	container.add_child(_create_spacer(10))

	# Angle SpinBox
	var angle_hbox = HBoxContainer.new()
	var angle_label = Label.new()
	angle_label.text = "Angle (°):"
	angle_label.rect_min_size = Vector2(80, 0)
	angle_hbox.add_child(angle_label)

	var angle_spin = SpinBox.new()
	angle_spin.min_value = 0
	angle_spin.max_value = 360
	angle_spin.step = 1
	angle_spin.value = tool.active_angle
	angle_spin.name = "AngleSpinBox"
	angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_spin.connect("value_changed", self, "_on_angle_changed")
	angle_hbox.add_child(angle_spin)
	container.add_child(angle_hbox)

	# Mirror CheckBox
	var mirror_check = CheckButton.new()
	mirror_check.text = "Mirror"
	mirror_check.pressed = tool.active_mirror
	mirror_check.name = "MirrorCheckbox"
	mirror_check.connect("toggled", self, "_on_mirror_toggled")
	container.add_child(mirror_check)

	# Show Coordinates CheckBox (Line-only)
	var coords_check = CheckButton.new()
	coords_check.text = "Show Coordinates"
	coords_check.pressed = tool.show_coordinates
	coords_check.name = "CoordinatesCheckbox"
	coords_check.connect("toggled", tool.parent_mod, "_on_show_coordinates_toggled", [tool])
	container.add_child(coords_check)

	return container

# Create UI for Shape marker type
func _create_shape_settings_ui():
	var container = VBoxContainer.new()

	# Shape Subtype Selector
	var subtype_label = Label.new()
	subtype_label.text = "Shape Type:"
	container.add_child(subtype_label)

	var subtype_option = OptionButton.new()
	subtype_option.add_item("Circle")
	subtype_option.set_item_metadata(0, SHAPE_CIRCLE)
	subtype_option.add_item("Square")
	subtype_option.set_item_metadata(1, SHAPE_SQUARE)
	subtype_option.add_item("Pentagon (5-sided)")
	subtype_option.set_item_metadata(2, SHAPE_PENTAGON)
	subtype_option.add_item("Hexagon (6-sided)")
	subtype_option.set_item_metadata(3, SHAPE_HEXAGON)
	subtype_option.add_item("Octagon (8-sided)")
	subtype_option.set_item_metadata(4, SHAPE_OCTAGON)
	subtype_option.add_item("Custom (N-sided)")
	subtype_option.set_item_metadata(5, SHAPE_CUSTOM)

	# Default to Circle preset (index 0)
	subtype_option.selected = 0

	subtype_option.name = "ShapeSubtypeSelector"
	subtype_option.connect("item_selected", self, "_on_shape_subtype_changed")
	container.add_child(subtype_option)

	container.add_child(_create_spacer(10))

	# Radius SpinBox
	var radius_hbox = HBoxContainer.new()
	var radius_label = Label.new()
	radius_label.text = "Radius:"
	radius_label.rect_min_size = Vector2(80, 0)
	radius_hbox.add_child(radius_label)

	var radius_spin = SpinBox.new()
	radius_spin.min_value = 0.1  # Minimum 0.1 cell
	radius_spin.max_value = 100
	radius_spin.step = 0.1
	radius_spin.value = tool.active_shape_radius
	radius_spin.name = "ShapeRadiusSpinBox"
	radius_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radius_spin.connect("value_changed", self, "_on_shape_radius_changed")
	radius_spin.allow_greater = true
	radius_spin.allow_lesser = false
	radius_hbox.add_child(radius_spin)
	container.add_child(radius_hbox)

	var radius_hint = Label.new()
	radius_hint.text = "  (grid cells, circumradius)"
	radius_hint.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	container.add_child(radius_hint)

	container.add_child(_create_spacer(5))

	# Angle SpinBox
	var angle_hbox = HBoxContainer.new()
	var angle_label = Label.new()
	angle_label.text = "Angle (°):"
	angle_label.rect_min_size = Vector2(80, 0)
	angle_hbox.add_child(angle_label)

	var angle_spin = SpinBox.new()
	angle_spin.min_value = 0
	angle_spin.max_value = 360
	angle_spin.step = 1
	angle_spin.value = tool.active_shape_angle
	angle_spin.name = "ShapeAngleSpinBox"
	angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_spin.connect("value_changed", self, "_on_shape_angle_changed")
	angle_hbox.add_child(angle_spin)
	container.add_child(angle_hbox)

	container.add_child(_create_spacer(5))

	# Sides SpinBox (only visible for Custom subtype)
	var sides_hbox = HBoxContainer.new()
	sides_hbox.name = "SidesRow"
	var sides_label = Label.new()
	sides_label.text = "Sides:"
	sides_label.rect_min_size = Vector2(80, 0)
	sides_hbox.add_child(sides_label)

	var sides_spin = SpinBox.new()
	sides_spin.min_value = 3
	sides_spin.max_value = 50
	sides_spin.step = 1
	sides_spin.value = tool.active_shape_sides
	sides_spin.name = "ShapeSidesSpinBox"
	sides_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides_spin.connect("value_changed", self, "_on_shape_sides_changed")
	sides_spin.allow_greater = false
	sides_spin.allow_lesser = false
	sides_hbox.add_child(sides_spin)
	container.add_child(sides_hbox)

	# Only show sides row for Custom subtype (hidden by default)
	sides_hbox.visible = false

	container.add_child(_create_spacer(10))

	# Clip Intersecting Shapes toggle
	var clip_check = CheckButton.new()
	clip_check.text = "Clip Intersecting Shapes"
	clip_check.pressed = tool.auto_clip_shapes
	clip_check.name = "ClipIntersectingShapesCheckbox"
	clip_check.connect("toggled", self, "_on_auto_clip_shapes_toggled")
	container.add_child(clip_check)

	var clip_hint = Label.new()
	clip_hint.text = "  (new shapes clip each other)"
	clip_hint.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	container.add_child(clip_hint)

	# Cut Into Existing Shapes toggle
	var cut_check = CheckButton.new()
	cut_check.text = "Cut Into Existing Shapes"
	cut_check.pressed = tool.cut_existing_shapes
	cut_check.name = "CutExistingShapesCheckbox"
	cut_check.connect("toggled", self, "_on_cut_existing_shapes_toggled")
	container.add_child(cut_check)

	var cut_hint = Label.new()
	cut_hint.text = "  (new shape cuts lines of others)"
	cut_hint.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	container.add_child(cut_hint)

	# Difference Mode toggle
	var diff_check = CheckButton.new()
	diff_check.text = "Difference Mode"
	diff_check.pressed = tool.difference_mode
	diff_check.name = "DifferenceModeCheckbox"
	diff_check.connect("toggled", self, "_on_difference_mode_toggled")
	container.add_child(diff_check)

	var diff_hint = Label.new()
	diff_hint.text = "  (fill overlap into existing shape)"
	diff_hint.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	container.add_child(diff_hint)

	return container

# Create UI for Path marker type
func _create_path_settings_ui():
	var container = VBoxContainer.new()

	# Cancel button (only visible during placement)
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel Path"
	cancel_btn.name = "PathCancelButton"
	cancel_btn.connect("pressed", tool, "_cancel_path_placement")
	cancel_btn.visible = false
	container.add_child(cancel_btn)

	container.add_child(_create_spacer(5))

	# End with Arrow checkbox
	var end_arrow_check = CheckButton.new()
	end_arrow_check.text = "End with Arrow"
	end_arrow_check.pressed = tool.active_path_end_arrow
	end_arrow_check.name = "PathEndArrowCheckbox"
	end_arrow_check.connect("toggled", self, "_on_path_end_arrow_toggled")
	container.add_child(end_arrow_check)

	# Arrow head settings container (only visible when checkbox is active)
	var arrow_settings = VBoxContainer.new()
	arrow_settings.name = "PathArrowSettings"
	arrow_settings.visible = tool.active_path_end_arrow

	# Head Length SpinBox
	var head_length_hbox = HBoxContainer.new()
	var head_length_label = Label.new()
	head_length_label.text = "Head Length:"
	head_length_label.rect_min_size = Vector2(80, 0)
	head_length_hbox.add_child(head_length_label)

	var head_length_spin = SpinBox.new()
	head_length_spin.min_value = 10.0
	head_length_spin.max_value = 200.0
	head_length_spin.step = 5.0
	head_length_spin.value = tool.active_arrow_head_length
	head_length_spin.name = "PathArrowHeadLengthSpinBox"
	head_length_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_length_spin.connect("value_changed", self, "_on_path_arrow_head_length_changed")
	head_length_spin.allow_greater = true
	head_length_spin.allow_lesser = false
	head_length_hbox.add_child(head_length_spin)
	arrow_settings.add_child(head_length_hbox)

	arrow_settings.add_child(_create_spacer(5))

	# Head Angle SpinBox
	var head_angle_hbox = HBoxContainer.new()
	var head_angle_label = Label.new()
	head_angle_label.text = "Head Angle:"
	head_angle_label.rect_min_size = Vector2(80, 0)
	head_angle_hbox.add_child(head_angle_label)

	var head_angle_spin = SpinBox.new()
	head_angle_spin.min_value = 10.0
	head_angle_spin.max_value = 60.0
	head_angle_spin.step = 5.0
	head_angle_spin.value = tool.active_arrow_head_angle
	head_angle_spin.name = "PathArrowHeadAngleSpinBox"
	head_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_angle_spin.connect("value_changed", self, "_on_path_arrow_head_angle_changed")
	head_angle_hbox.add_child(head_angle_spin)
	arrow_settings.add_child(head_angle_hbox)

	container.add_child(arrow_settings)

	return container

# Create common settings UI (Color picker)
func _create_common_settings_ui():
	var container = VBoxContainer.new()

	var common_label = Label.new()
	common_label.text = "Common Settings:"
	common_label.align = Label.ALIGN_CENTER
	container.add_child(common_label)

	container.add_child(_create_spacer(5))

	# Color Picker
	var color_hbox = HBoxContainer.new()
	var color_label = Label.new()
	color_label.text = "Color:"
	color_label.rect_min_size = Vector2(80, 0)
	color_hbox.add_child(color_label)

	var color_picker = ColorPickerButton.new()
	color_picker.color = tool.active_color
	color_picker.name = "ColorPicker"
	color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker.connect("color_changed", self, "_on_color_changed")
	color_hbox.add_child(color_picker)
	container.add_child(color_hbox)

	return container

func _create_spacer(height):
	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, height)
	return spacer

# ============================================================================
# UI CALLBACKS — LINE SETTINGS
# ============================================================================

func _on_quick_angle_pressed(angle_value):
	tool.active_angle = angle_value
	_update_angle_spinbox()
	if tool.LOGGER:
		tool.LOGGER.debug("Quick angle set to: %.1f°" % [angle_value])

func _on_angle_changed(value):
	tool.active_angle = value
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Angle changed to: %.1f°" % [value])

func _on_color_changed(new_color):
	tool.active_color = new_color
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Color changed to: %s" % [new_color.to_html()])

func _on_mirror_toggled(enabled):
	tool.active_mirror = enabled
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Mirror toggled: %s" % [str(enabled)])

# ============================================================================
# UI CALLBACKS — SHAPE SETTINGS
# ============================================================================

# UI callback for shape preset selector.
# Selecting a preset sets the canonical starting sides and angle for that shape;
# subtype is no longer stored on the marker — only sides/angle matter.
func _on_shape_subtype_changed(subtype_index):
	if not type_selector:
		return

	var subtype_selector = shape_settings_container.find_node("ShapeSubtypeSelector", true, false)
	if subtype_selector:
		var preset = subtype_selector.get_item_metadata(subtype_index)

		# Apply canonical defaults for the selected preset
		match preset:
			SHAPE_CIRCLE:
				tool.active_shape_sides = 64
				tool.active_shape_angle = 0.0
			SHAPE_SQUARE:
				tool.active_shape_sides = 4
				tool.active_shape_angle = 45.0
			SHAPE_PENTAGON:
				tool.active_shape_sides = 5
				tool.active_shape_angle = -90.0
			SHAPE_HEXAGON:
				tool.active_shape_sides = 6
				tool.active_shape_angle = 0.0
			SHAPE_OCTAGON:
				tool.active_shape_sides = 8
				tool.active_shape_angle = 22.5
			SHAPE_CUSTOM:
				# Keep current sides/angle as-is when switching to Custom
				pass

		tool.type_settings[MARKER_TYPE_SHAPE]["angle"] = tool.active_shape_angle
		tool.type_settings[MARKER_TYPE_SHAPE]["sides"] = tool.active_shape_sides

		# Show/hide sides spinbox — visible only for Custom
		var sides_row = shape_settings_container.find_node("SidesRow", true, false)
		if sides_row:
			sides_row.visible = (preset == SHAPE_CUSTOM)

		_update_shape_angle_spinbox()
		_update_shape_sides_spinbox()

		if tool.overlay:
			tool.overlay.update()

		if tool.LOGGER:
			tool.LOGGER.info("Shape preset changed to: %s (sides=%d, angle=%.1f)" % [preset, tool.active_shape_sides, tool.active_shape_angle])

func _on_shape_radius_changed(value):
	if value < 0.1:
		value = 0.1
	tool.active_shape_radius = value
	_update_shape_radius_spinbox()
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Shape radius changed to: %.1f cells" % [value])

func _on_shape_angle_changed(value):
	tool.active_shape_angle = value
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Shape angle changed to: %.1f°" % [value])

func _on_shape_sides_changed(value):
	tool.active_shape_sides = int(value)
	tool.type_settings[MARKER_TYPE_SHAPE]["sides"] = tool.active_shape_sides
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Shape sides changed to: %d" % [tool.active_shape_sides])

func _on_auto_clip_shapes_toggled(enabled):
	tool.auto_clip_shapes = enabled
	# Only one clip mode can be active at a time
	if enabled:
		if tool.cut_existing_shapes:
			tool.cut_existing_shapes = false
			_set_shape_checkbox("CutExistingShapesCheckbox", false)
		if tool.difference_mode:
			tool.difference_mode = false
			_set_shape_checkbox("DifferenceModeCheckbox", false)
	if tool.LOGGER:
		tool.LOGGER.info("Clip Intersecting Shapes: %s" % ["ON" if enabled else "OFF"])

func _on_cut_existing_shapes_toggled(enabled):
	tool.cut_existing_shapes = enabled
	# Only one clip mode can be active at a time
	if enabled:
		if tool.auto_clip_shapes:
			tool.auto_clip_shapes = false
			_set_shape_checkbox("ClipIntersectingShapesCheckbox", false)
		if tool.difference_mode:
			tool.difference_mode = false
			_set_shape_checkbox("DifferenceModeCheckbox", false)
	if tool.LOGGER:
		tool.LOGGER.info("Cut Into Existing Shapes: %s" % ["ON" if enabled else "OFF"])

func _on_difference_mode_toggled(enabled):
	tool.difference_mode = enabled
	# Only one mode can be active at a time
	if enabled:
		if tool.auto_clip_shapes:
			tool.auto_clip_shapes = false
			_set_shape_checkbox("ClipIntersectingShapesCheckbox", false)
		if tool.cut_existing_shapes:
			tool.cut_existing_shapes = false
			_set_shape_checkbox("CutExistingShapesCheckbox", false)
	if tool.LOGGER:
		tool.LOGGER.info("Difference Mode: %s" % ["ON" if enabled else "OFF"])

# ============================================================================
# UI CALLBACKS — PATH ARROW SETTINGS
# ============================================================================

func _on_path_end_arrow_toggled(enabled):
	tool.active_path_end_arrow = enabled
	tool.type_settings[MARKER_TYPE_PATH]["end_arrow"] = enabled
	# Show/hide arrow head settings
	if path_settings_container:
		var arrow_settings = path_settings_container.find_node("PathArrowSettings", true, false)
		if arrow_settings:
			arrow_settings.visible = enabled
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Path end_arrow toggled: %s" % [str(enabled)])

func _on_path_arrow_head_length_changed(value):
	if value < 10.0:
		value = 10.0
	tool.active_arrow_head_length = value
	tool.type_settings[MARKER_TYPE_PATH]["head_length"] = value
	_update_path_arrow_head_length_spinbox()
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Path arrow head length changed to: %.1f px" % [value])

func _on_path_arrow_head_angle_changed(value):
	tool.active_arrow_head_angle = value
	tool.type_settings[MARKER_TYPE_PATH]["head_angle"] = value
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Path arrow head angle changed to: %.1f°" % [value])

# ============================================================================
# MARKER TYPE SWITCHING
# ============================================================================

# Handle marker type selection change
func _on_marker_type_changed(type_index):
	var selected_type = type_selector.get_item_metadata(type_index)

	# Save current type settings before switching
	_save_current_type_settings()

	# Cancel path placement if switching away from Path
	if tool.active_marker_type == MARKER_TYPE_PATH and selected_type != MARKER_TYPE_PATH:
		tool._cancel_path_placement()

	# Switch to new type
	tool.active_marker_type = selected_type

	# Load settings for new type
	_load_type_settings(selected_type)

	# Switch visible UI container
	_switch_type_ui(selected_type)

	if tool.overlay:
		tool.overlay.update()

	if tool.LOGGER:
		tool.LOGGER.debug("Marker type changed to: %s" % [selected_type])

# Switch visible type-specific UI container
func _switch_type_ui(marker_type):
	# Hide all type-specific containers
	for child in type_specific_container.get_children():
		child.visible = false

	# Show the selected type's container
	match marker_type:
		MARKER_TYPE_LINE:
			if line_settings_container:
				line_settings_container.visible = true
		MARKER_TYPE_SHAPE:
			if shape_settings_container:
				shape_settings_container.visible = true
		MARKER_TYPE_PATH:
			if path_settings_container:
				path_settings_container.visible = true

# Load settings for specific marker type
func _load_type_settings(marker_type):
	if not tool.type_settings.has(marker_type):
		return

	var settings = tool.type_settings[marker_type]

	if marker_type == MARKER_TYPE_LINE:
		tool.active_angle = settings["angle"]
		tool.active_mirror = settings["mirror"]
		_update_angle_spinbox()
		_update_mirror_checkbox()

	elif marker_type == MARKER_TYPE_SHAPE:
		tool.active_shape_radius = settings["radius"]
		tool.active_shape_angle = settings.get("angle", 0.0)
		tool.active_shape_sides = settings.get("sides", DEFAULT_SHAPE_SIDES)
		_update_shape_radius_spinbox()
		_update_shape_angle_spinbox()
		_update_shape_sides_spinbox()

	elif marker_type == MARKER_TYPE_PATH:
		tool.active_path_end_arrow = settings.get("end_arrow", false)
		tool.active_arrow_head_length = settings.get("head_length", DEFAULT_ARROW_HEAD_LENGTH)
		tool.active_arrow_head_angle = settings.get("head_angle", DEFAULT_ARROW_HEAD_ANGLE)
		_update_path_end_arrow_checkbox()
		_update_path_arrow_head_length_spinbox()
		_update_path_arrow_head_angle_spinbox()

# Save current type settings before switching
func _save_current_type_settings():
	if not tool.type_settings.has(tool.active_marker_type):
		tool.type_settings[tool.active_marker_type] = {}

	if tool.active_marker_type == MARKER_TYPE_LINE:
		tool.type_settings[MARKER_TYPE_LINE]["angle"] = tool.active_angle
		tool.type_settings[MARKER_TYPE_LINE]["mirror"] = tool.active_mirror

	elif tool.active_marker_type == MARKER_TYPE_SHAPE:
		tool.type_settings[MARKER_TYPE_SHAPE]["radius"] = tool.active_shape_radius
		tool.type_settings[MARKER_TYPE_SHAPE]["angle"] = tool.active_shape_angle
		tool.type_settings[MARKER_TYPE_SHAPE]["sides"] = tool.active_shape_sides

	elif tool.active_marker_type == MARKER_TYPE_PATH:
		tool.type_settings[MARKER_TYPE_PATH]["end_arrow"] = tool.active_path_end_arrow
		tool.type_settings[MARKER_TYPE_PATH]["head_length"] = tool.active_arrow_head_length
		tool.type_settings[MARKER_TYPE_PATH]["head_angle"] = tool.active_arrow_head_angle

# ============================================================================
# MOUSE WHEEL PARAMETER ADJUSTMENT
# ============================================================================

# Adjust angle using mouse wheel (only for Line type)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_angle_with_wheel(direction):
	if tool.active_marker_type != MARKER_TYPE_LINE:
		return

	var angle_step = 1.0
	var new_angle = tool.active_angle + (direction * angle_step)

	if new_angle < 0:
		new_angle += 360
	elif new_angle >= 360:
		new_angle -= 360

	tool.active_angle = new_angle
	tool.type_settings[MARKER_TYPE_LINE]["angle"] = tool.active_angle
	_update_angle_spinbox()

	if tool.overlay:
		tool.overlay.update()

	if tool.LOGGER:
		tool.LOGGER.debug("Angle adjusted via mouse wheel: %.1f°" % [tool.active_angle])

# Adjust shape radius using mouse wheel (only for Shape type)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_shape_radius_with_wheel(direction):
	if tool.active_marker_type != MARKER_TYPE_SHAPE:
		return

	var radius_step = 0.1
	var new_radius = tool.active_shape_radius + (direction * radius_step)

	if new_radius < 0.1:
		new_radius = 0.1

	tool.active_shape_radius = new_radius
	tool.type_settings[MARKER_TYPE_SHAPE]["radius"] = tool.active_shape_radius
	_update_shape_radius_spinbox()

	if tool.overlay:
		tool.overlay.update()

	if tool.LOGGER:
		tool.LOGGER.debug("Shape radius adjusted via mouse wheel: %.1f cells" % [tool.active_shape_radius])

# Adjust shape angle using mouse wheel (only for Shape type)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_shape_angle_with_wheel(direction):
	if tool.active_marker_type != MARKER_TYPE_SHAPE:
		return

	var angle_step = 5.0
	var new_angle = fmod(tool.active_shape_angle + (direction * angle_step), 360.0)
	if new_angle < 0:
		new_angle += 360.0

	tool.active_shape_angle = new_angle
	tool.type_settings[MARKER_TYPE_SHAPE]["angle"] = tool.active_shape_angle
	_update_shape_angle_spinbox()

	if tool.overlay:
		tool.overlay.update()

	if tool.LOGGER:
		tool.LOGGER.debug("Shape angle adjusted via mouse wheel: %.1f°" % [tool.active_shape_angle])

# Rotate shape by 45 degrees via RMB shortcut
func rotate_shape_45():
	if tool.active_marker_type != MARKER_TYPE_SHAPE:
		return

	var new_angle = fmod(tool.active_shape_angle + 45.0, 360.0)

	tool.active_shape_angle = new_angle
	tool.type_settings[MARKER_TYPE_SHAPE]["angle"] = tool.active_shape_angle
	_update_shape_angle_spinbox()

	if tool.overlay:
		tool.overlay.update()

	if tool.LOGGER:
		tool.LOGGER.debug("Shape rotated 45° via RMB: %.1f°" % [tool.active_shape_angle])

# ============================================================================
# WIDGET VALUE HELPERS
# ============================================================================

# Helper: set value on a named SpinBox inside the tool panel.
func _set_spinbox_value(node_name: String, value: float) -> void:
	if not tool.tool_panel:
		return
	var container = tool.tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node(node_name, true, false)
		if spinbox:
			spinbox.value = value

func _update_angle_spinbox():
	_set_spinbox_value("AngleSpinBox", tool.active_angle)

func _update_color_picker():
	if not tool.tool_panel:
		return
	var container = tool.tool_panel.Align.get_child(0)
	if container:
		var picker = container.find_node("ColorPicker", true, false)
		if picker:
			picker.color = tool.active_color

func _update_mirror_checkbox():
	if not tool.tool_panel:
		return
	var container = tool.tool_panel.Align.get_child(0)
	if container:
		var checkbox = container.find_node("MirrorCheckbox", true, false)
		if checkbox:
			checkbox.pressed = tool.active_mirror

func _update_shape_radius_spinbox():
	_set_spinbox_value("ShapeRadiusSpinBox", tool.active_shape_radius)

func _update_shape_angle_spinbox():
	if not tool.tool_panel:
		return
	var container = tool.tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("ShapeAngleSpinBox", true, false)
		if spinbox:
			spinbox.value = tool.active_shape_angle

func _update_shape_sides_spinbox():
	if not tool.tool_panel:
		return
	var container = tool.tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("ShapeSidesSpinBox", true, false)
		if spinbox:
			spinbox.value = tool.active_shape_sides

func _update_path_end_arrow_checkbox():
	if not path_settings_container:
		return
	var checkbox = path_settings_container.find_node("PathEndArrowCheckbox", true, false)
	if checkbox:
		checkbox.pressed = tool.active_path_end_arrow
	var arrow_settings = path_settings_container.find_node("PathArrowSettings", true, false)
	if arrow_settings:
		arrow_settings.visible = tool.active_path_end_arrow

func _update_path_arrow_head_length_spinbox():
	_set_spinbox_value("PathArrowHeadLengthSpinBox", tool.active_arrow_head_length)

func _update_path_arrow_head_angle_spinbox():
	_set_spinbox_value("PathArrowHeadAngleSpinBox", tool.active_arrow_head_angle)

# Helper: set pressed state on a named CheckButton inside shape_settings_container
# without triggering its toggled signal (to avoid recursion).
func _set_shape_checkbox(node_name: String, value: bool) -> void:
	if not shape_settings_container:
		return
	var btn = shape_settings_container.find_node(node_name, true, false)
	if btn:
		btn.set_block_signals(true)
		btn.pressed = value
		btn.set_block_signals(false)
