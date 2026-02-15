extends Reference

# GuidesLinesTool - Tool for managing guide markers
# Stores markers internally and draws them via overlay

const CLASS_NAME = "GuidesLinesTool"

# ============================================================================
# HISTORY RECORDS FOR UNDO/REDO SUPPORT
# ============================================================================

# History record for placing a marker
class PlaceMarkerRecord:
	var tool
	var marker_data
	
	func _init(tool_ref, data):
		tool = tool_ref
		marker_data = data
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerRecord created for id: %d" % [data["id"]])
	
	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerRecord.redo() called for id: %d" % [marker_data["id"]])
		tool._do_place_marker(marker_data)
	
	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerRecord.undo() called for id: %d" % [marker_data["id"]])
		tool._undo_place_marker(marker_data["id"])
	
	func record_type():
		return "GuidesLines.PlaceMarker"

# History record for deleting a single marker
class DeleteMarkerRecord:
	var tool
	var marker_data
	var marker_index
	
	func _init(tool_ref, data, index):
		tool = tool_ref
		marker_data = data
		marker_index = index
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteMarkerRecord created for id: %d at index: %d" % [data["id"], index])
	
	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteMarkerRecord.redo() called for id: %d" % [marker_data["id"]])
		tool._do_delete_marker(marker_index)
	
	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteMarkerRecord.undo() called for id: %d" % [marker_data["id"]])
		tool._undo_delete_marker(marker_data, marker_index)
	
	func record_type():
		return "GuidesLines.DeleteMarker"

# History record for deleting all markers
class DeleteAllMarkersRecord:
	var tool
	var saved_markers
	
	func _init(tool_ref, markers_data):
		tool = tool_ref
		saved_markers = markers_data
	
	func redo():
		tool._do_delete_all()
	
	func undo():
		tool._undo_delete_all(saved_markers)
	
	func record_type():
		return "GuidesLines.DeleteAll"

# ============================================================================
# VARIABLES
# ============================================================================

var parent_mod = null
var GuideMarkerClass = null
var MarkerOverlayClass = null
var LOGGER = null  # Logger instance (passed from parent mod)

# Cached references (passed from main mod)
var cached_world = null
var cached_worldui = null
var cached_camera = null
var cached_snappy_mod = null  # Custom_snap mod reference (if available)

# Tool state
var is_enabled = false
var snap_to_grid = true  # Snap markers to grid by default
var show_coordinates = false  # Show grid coordinates on new markers
var delete_mode = false  # Delete mode - click to remove markers

# Marker type system
const MARKER_TYPE_LINE = "Line"
const MARKER_TYPE_CIRCLE = "Circle"
const MARKER_TYPE_PATH = "Path"

var active_marker_type = MARKER_TYPE_LINE  # Current selected marker type

# Active marker settings (for new markers)
var active_angle = 0.0
var active_line_range = 0.0  # In grid cells
var active_circle_radius = 1.0  # Circle radius in grid cells
var active_color = Color(0, 0.7, 1, 1)
var active_mirror = false

# Type-specific settings storage (each type stores its own parameters)
var type_settings = {
	"Line": {
		"angle": 0.0,
		"range": 0.0,
		"mirror": false
	},
	"Circle": {
		"radius": 1.0
	},
	"Path": {
		# Path has no persistent settings, it's point-based
	}
}

# Default values
const DEFAULT_ANGLE = 0.0
const DEFAULT_LINE_RANGE = 0.0
const DEFAULT_CIRCLE_RADIUS = 1.0
const DEFAULT_COLOR = Color(0, 0.7, 1, 1)
const DEFAULT_MIRROR = false

# Markers storage
var markers = []  # Array of GuideMarker instances
var next_id = 0

# UI References
var tool_panel = null
var overlay = null  # Node2D for drawing
var type_selector = null  # OptionButton for marker type selection
var type_specific_container = null  # Container for type-specific settings
var line_settings_container = null  # Settings for Line type
var circle_settings_container = null  # Settings for Circle type
var path_settings_container = null  # Settings for Path type

# Path placement state
var path_placement_active = false  # Whether we're in path placement mode
var path_temp_points = []  # Temporary storage for points being placed
var path_preview_point = null  # Current mouse position for line preview

# Initialize tool with reference to parent mod
func _init(mod):
	parent_mod = mod
	# Note: LOGGER will be set by parent mod after initialization

# Enable tool when selected in Dungeondraft
func Enable():
	is_enabled = true
	if LOGGER:
		LOGGER.info("Guide Markers tool ENABLED")
	else:
		print("GuidesLinesTool: Tool enabled but LOGGER is null!")

# Disable tool when deselected
func Disable():
	is_enabled = false
	if LOGGER:
		LOGGER.info("Guide Markers tool DISABLED")

var update_count = 0
var last_log_update = 0

# Main update loop - manages overlay and drawing
func Update(_delta):
	update_count += 1
	
	# Debug: Check LOGGER status on first update
	if update_count == 1:
		if LOGGER:
			LOGGER.info("GuidesLinesTool.Update() first call - LOGGER is available")
	
	# Log status every 300 frames (5 seconds at 60fps)
	if LOGGER and is_enabled and update_count - last_log_update > 300:
		last_log_update = update_count
		LOGGER.debug("Tool active: overlay=%s, markers=%d" % [str(overlay != null), markers.size()])
	
	if not is_enabled:
		return
	
	# Create overlay if needed
	if not overlay and cached_worldui:
		_create_overlay()
	
	# Update overlay to redraw
	if overlay:
		overlay.update()

# Create overlay node for drawing markers and guide lines
func _create_overlay():
	if LOGGER:
		LOGGER.info("Creating MarkerOverlay...")
	overlay = MarkerOverlayClass.new()
	overlay.tool = self
	cached_worldui.add_child(overlay)
	overlay.set_z_index(100)
	if LOGGER:
		LOGGER.info("MarkerOverlay created successfully")

# Place a new marker at the specified position
# Applies grid snapping and active custom line settings
func place_marker(pos):
	# Special handling for Path type
	if active_marker_type == MARKER_TYPE_PATH:
		_handle_path_placement(pos)
		return
	
	# Apply grid snapping if enabled
	var snapped_pos = snap_position_to_grid(pos)
	
	var marker_data = {
		"position": snapped_pos,
		"marker_type": active_marker_type,
		"color": active_color,
		"coordinates": show_coordinates,
		"id": next_id
	}
	
	# Add type-specific parameters
	if active_marker_type == MARKER_TYPE_LINE:
		marker_data["angle"] = active_angle
		marker_data["line_range"] = active_line_range
		marker_data["mirror"] = active_mirror
	elif active_marker_type == MARKER_TYPE_CIRCLE:
		marker_data["circle_radius"] = active_circle_radius
	
	# Execute the action first
	_do_place_marker(marker_data)
	next_id += 1
	
	# Then add to history if available
	if parent_mod.Global.API and parent_mod.Global.API.has("HistoryApi"):
		if LOGGER:
			LOGGER.debug("Adding marker placement to history (id: %d)" % [marker_data["id"]])
		var record = PlaceMarkerRecord.new(self, marker_data)
		parent_mod.Global.API.HistoryApi.record(record, 100)
	else:
		if LOGGER:
			LOGGER.info("HistoryApi not available, marker placed without history")

# Handle path marker placement (multi-point)
func _handle_path_placement(pos):
	var snapped_pos = snap_position_to_grid(pos)
	
	# First point - start path placement
	if not path_placement_active:
		path_placement_active = true
		path_temp_points = [snapped_pos]
		if LOGGER:
			LOGGER.info("Path placement started at %s" % [str(snapped_pos)])
		update_ui()
		return
	
	# Check if clicking near first point (close path)
	var first_point = path_temp_points[0]
	if snapped_pos.distance_to(first_point) < 30.0 and path_temp_points.size() >= 3:
		# Close path and create marker
		var point_count = path_temp_points.size()
		_finalize_path_marker(true)
		if LOGGER:
			LOGGER.info("Path closed with %d points" % [point_count])
		return
	
	# Add new point to path
	path_temp_points.append(snapped_pos)
	if LOGGER:
		LOGGER.debug("Path point added: %s (total: %d)" % [str(snapped_pos), path_temp_points.size()])
	update_ui()

# Finalize path marker (called on RMB or close)
func _finalize_path_marker(closed):
	if not path_placement_active or path_temp_points.size() < 2:
		_cancel_path_placement()
		return
	
	# Create marker data
	var marker_data = {
		"position": path_temp_points[0],  # First point is marker position
		"marker_type": MARKER_TYPE_PATH,
		"color": active_color,
		"coordinates": show_coordinates,
		"id": next_id,
		"path_points": path_temp_points.duplicate(),
		"path_closed": closed
	}
	
	# Execute the action first
	_do_place_marker(marker_data)
	next_id += 1
	
	# Add to history
	if parent_mod.Global.API and parent_mod.Global.API.has("HistoryApi"):
		if LOGGER:
			LOGGER.debug("Adding path marker to history (id: %d)" % [marker_data["id"]])
		var record = PlaceMarkerRecord.new(self, marker_data)
		parent_mod.Global.API.HistoryApi.record(record, 100)
	
	# Reset path state
	_cancel_path_placement()

# Cancel path placement (ESC or new type selected)
func _cancel_path_placement():
	path_placement_active = false
	path_temp_points = []
	path_preview_point = null
	update_ui()
	if overlay:
		overlay.update()

# Delete all markers from the map
func delete_all_markers():
	if markers.size() == 0:
		return
	
	# Save state before deletion
	var saved_markers = []
	for marker in markers:
		saved_markers.append(marker.Save())
	
	# Execute the action first
	_do_delete_all()
	
	# Then add to history if available
	if parent_mod.Global.API and parent_mod.Global.API.has("HistoryApi"):
		var record = DeleteAllMarkersRecord.new(self, saved_markers)
		parent_mod.Global.API.HistoryApi.record(record)

func _do_delete_all():
	markers = []
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("All markers deleted")

func _undo_delete_all(saved_markers):
	for marker_data in saved_markers:
		var marker = GuideMarkerClass.new()
		marker.Load(marker_data)
		markers.append(marker)
		if marker.id >= next_id:
			next_id = marker.id + 1
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Restored %d markers" % [saved_markers.size()])

# Delete marker at specific position (within threshold)
func delete_marker_at_position(pos, threshold = 20.0):
	for i in range(markers.size() - 1, -1, -1):  # Iterate backwards for safe removal
		var marker = markers[i]
		if marker.position.distance_to(pos) < threshold:
			# Save marker data before deletion
			var marker_data = marker.Save()
			
			# Execute the action first
			_do_delete_marker(i)
			
			# Then add to history if available
			if parent_mod.Global.API and parent_mod.Global.API.has("HistoryApi"):
				var record = DeleteMarkerRecord.new(self, marker_data, i)
				parent_mod.Global.API.HistoryApi.record(record, 100)
			
			return true  # Marker was deleted
	return false  # No marker found

func _do_delete_marker(index):
	if index < markers.size():
		markers.remove(index)
		update_ui()
		if overlay:
			overlay.update()
		if LOGGER:
			LOGGER.debug("Marker deleted at index %d" % [index])

func _undo_delete_marker(marker_data, index):
	var marker = GuideMarkerClass.new()
	marker.Load(marker_data)
	markers.insert(index, marker)
	if marker.id >= next_id:
		next_id = marker.id + 1
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Marker restored at index %d" % [index])

# Helper functions for HistoryApi - place marker
func _do_place_marker(marker_data):
	var marker = GuideMarkerClass.new()
	marker.position = marker_data["position"]
	marker.id = marker_data["id"]
	marker.marker_type = marker_data["marker_type"]
	marker.color = marker_data["color"]
	marker.show_coordinates = marker_data["coordinates"]
	
	# Load type-specific parameters
	if marker_data["marker_type"] == MARKER_TYPE_LINE:
		marker.angle = marker_data["angle"]
		marker.line_range = marker_data["line_range"]
		marker.mirror = marker_data["mirror"]
	elif marker_data["marker_type"] == MARKER_TYPE_CIRCLE:
		marker.circle_radius = marker_data["circle_radius"]
	elif marker_data["marker_type"] == MARKER_TYPE_PATH:
		marker.path_points = marker_data["path_points"].duplicate()
		marker.path_closed = marker_data["path_closed"]
	
	markers.append(marker)
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		if marker_data["marker_type"] == MARKER_TYPE_LINE:
			LOGGER.debug("Line marker placed at %s (angle: %.1f°, range: %.1f cells, mirror: %s)" % [
				str(marker_data["position"]),
				marker_data["angle"],
				marker_data["line_range"],
				str(marker_data["mirror"])
			])
		elif marker_data["marker_type"] == MARKER_TYPE_CIRCLE:
			LOGGER.debug("Circle marker placed at %s (radius: %.1f cells)" % [
				str(marker_data["position"]),
				marker_data["circle_radius"]
			])
		elif marker_data["marker_type"] == MARKER_TYPE_PATH:
			LOGGER.debug("Path marker placed with %d points (closed: %s)" % [
				marker_data["path_points"].size(),
				str(marker_data["path_closed"])
			])

func _undo_place_marker(marker_id):
	# Find and remove marker by id
	for i in range(markers.size() - 1, -1, -1):
		if markers[i].id == marker_id:
			markers.remove(i)
			update_ui()
			if overlay:
				overlay.update()
			if LOGGER:
				LOGGER.debug("Marker placement undone (id: %d)" % [marker_id])
			break

# Enable/disable grid snapping for marker placement
func set_snap_to_grid(enabled):
	# Can't disable snap when coordinates are enabled
	if show_coordinates and not enabled:
		return
	# Cancel path if disabling snap during path placement
	if not enabled and path_placement_active:
		_cancel_path_placement()
	snap_to_grid = enabled
	update_snap_checkbox_state()

# Enable/disable coordinate display on new markers
func set_show_coordinates(enabled):
	show_coordinates = enabled
	# Auto-enable snap to grid when coordinates are enabled
	if enabled:
		snap_to_grid = true
	update_snap_checkbox_state()

func set_delete_mode(enabled):
	delete_mode = enabled
	update_ui_checkboxes_state()
	# Force overlay update to hide/show preview
	if overlay:
		overlay.update()

# Update snap checkbox enabled/disabled state based on coordinates
func update_snap_checkbox_state():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var snap_check = container.get_node_or_null("SnapCheckbox")
		if snap_check:
			snap_check.pressed = snap_to_grid
			snap_check.disabled = show_coordinates  # Disable when coordinates are on

# Update all UI checkboxes based on delete mode
func update_ui_checkboxes_state():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		# Disable controls when delete mode is on
		for child in container.get_children():
			if child is CheckButton:
				if child.name == "DeleteModeCheckbox":
					continue  # Don't disable delete mode checkbox itself
				child.disabled = delete_mode
			# Also disable spinboxes, color picker, and buttons
			elif child is HBoxContainer:
				for subchild in child.get_children():
					if subchild is SpinBox or subchild is ColorPickerButton:
						subchild.editable = not delete_mode
			elif child is Button and child.text != "Delete All Markers":
				child.disabled = delete_mode
			elif child is GridContainer:
				for btn in child.get_children():
					if btn is Button:
						btn.disabled = delete_mode

# Snap position to grid, using custom_snap mod if available
# Falls back to vanilla Dungeondraft snapping
func snap_position_to_grid(position):
	if not snap_to_grid:
		return position
	
	# Use custom_snap if available
	if cached_snappy_mod and cached_snappy_mod.has_method("get_snapped_position"):
		return cached_snappy_mod.get_snapped_position(position)
	
	# Use vanilla DD snap if custom_snap not available
	if cached_worldui:
		return cached_worldui.GetSnappedPosition(position)
	
	return position

# Update tool panel UI with current marker count
func update_ui():
	if not tool_panel:
		return
	
	# Find and update info label
	var container = tool_panel.Align.get_child(0)
	if container:
		var info_label = container.get_node_or_null("InfoLabel")
		if info_label:
			if path_placement_active:
				info_label.text = "Path mode: %d points placed\nClick to add, RMB to finish" % [path_temp_points.size()]
			else:
				info_label.text = "Click to place markers.\nMarkers: " + str(markers.size())
		
		# Update path status label if in Path mode
		if active_marker_type == MARKER_TYPE_PATH:
			var path_container = type_specific_container.get_node_or_null("PathSettings")
			if path_container:
				var status_label = path_container.get_node_or_null("PathStatusLabel")
				var cancel_btn = path_container.get_node_or_null("PathCancelButton")
				
				if status_label:
					if path_placement_active:
						status_label.text = "Points: %d (min 2)" % [path_temp_points.size()]
						status_label.add_color_override("font_color", Color(1.0, 1.0, 0.5, 1))
					else:
						status_label.text = "Ready to start"
						status_label.add_color_override("font_color", Color(0.5, 1.0, 0.5, 1))
				
				if cancel_btn:
					cancel_btn.visible = path_placement_active

# Serialize all markers for saving to map file
func save_markers():
	var data = []
	for marker in markers:
		data.append(marker.Save())
	return data

# Load markers from saved map file data
func load_markers(data):
	delete_all_markers()
	
	if not data:
		return
	
	for marker_data in data:
		# Convert legacy format to current format if needed
		var converted_data = _convert_legacy_marker_data(marker_data)
		
		var marker = GuideMarkerClass.new()
		marker.Load(converted_data)
		markers.append(marker)
		
		if marker.id >= next_id:
			next_id = marker.id + 1
	
	if overlay:
		overlay.update()
	
	if LOGGER:
		LOGGER.info("%d markers loaded" % [markers.size()])

# Convert legacy marker format to current format
func _convert_legacy_marker_data(data):
	# Check if already in new format (has type-specific parameters)
	if data.has("marker_type"):
		if data.marker_type == "Line" and data.has("angle") and data.has("line_range"):
			return data  # Already new Line format
		elif data.marker_type == "Circle" and data.has("circle_radius"):
			return data  # Already new Circle format
	
	# Create new format dictionary
	var new_data = {}
	
	# Copy position
	if data.has("position"):
		new_data["position"] = data.position
	
	# Copy or set marker_type (default to Line for legacy)
	if data.has("marker_type") and data.marker_type is String:
		if data.marker_type == "Circle":
			new_data["marker_type"] = "Circle"
			# Copy Circle-specific parameters
			if data.has("circle_radius"):
				new_data["circle_radius"] = data.circle_radius
			else:
				new_data["circle_radius"] = 1.0
		else:
			new_data["marker_type"] = "Line"
	else:
		new_data["marker_type"] = "Line"
	
	# Convert Line-specific parameters (only for Line type)
	if new_data["marker_type"] == "Line":
		# Convert old marker_types array or marker_type string to angle
		if data.has("angle"):
			new_data["angle"] = data.angle
		else:
			new_data["angle"] = _convert_legacy_types_to_angle(data)
			if LOGGER:
				LOGGER.debug("Converted legacy marker to angle: %.1f°" % [new_data["angle"]])
		
		# Convert range (old format used pixels, but we'll keep the value)
		if data.has("line_range"):
			new_data["line_range"] = data.line_range
		elif data.has("range"):
			new_data["line_range"] = data.range
		else:
			new_data["line_range"] = 0.0
		
		# Set mirror (legacy markers had no mirror)
		if data.has("mirror"):
			new_data["mirror"] = data.mirror
		else:
			new_data["mirror"] = false
	
	# Copy color (common for all types)
	if data.has("color"):
		new_data["color"] = data.color
	else:
		new_data["color"] = "#00b3ff"  # Default blue
	
	# Copy id
	if data.has("id"):
		new_data["id"] = data.id
	
	# Copy show_coordinates
	if data.has("show_coordinates"):
		new_data["show_coordinates"] = data.show_coordinates
	else:
		new_data["show_coordinates"] = false
	
	return new_data

# Convert legacy marker_types array or marker_type string to angle
func _convert_legacy_types_to_angle(data):
	# Check for old marker_types array (v1.0.10)
	if data.has("marker_types"):
		var types = data.marker_types
		if types.has("vertical"):
			return 90.0
		elif types.has("horizontal"):
			return 0.0
		elif types.has("diagonal_left"):
			return 135.0
		elif types.has("diagonal_right"):
			return 45.0
	
	# Check for even older marker_type string (v1.0.0)
	if data.has("marker_type") and data.marker_type is String:
		var old_type = data.marker_type
		match old_type:
			"both", "vertical":
				return 90.0
			"horizontal":
				return 0.0
	
	return 0.0  # Default horizontal

# Create the UI panel for the tool with all controls
# Includes marker type selector and type-specific settings
func create_ui_panel():
	if not tool_panel:
		return
	
	var container = VBoxContainer.new()
	
	# Title
	var title = Label.new()
	title.text = "Guide Markers"
	title.align = Label.ALIGN_CENTER
	container.add_child(title)

	container.add_child(_create_spacer(10))
	
	# Info label
	var info = Label.new()
	info.text = "Click to place markers.\nMarkers: 0"
	info.autowrap = true
	info.name = "InfoLabel"
	container.add_child(info)
	
	container.add_child(_create_spacer(10))
	
	# === MARKER TYPE SELECTOR ===
	var type_label = Label.new()
	type_label.text = "Marker Type:"
	container.add_child(type_label)
	
	type_selector = OptionButton.new()
	type_selector.add_item("Line")
	type_selector.set_item_metadata(0, MARKER_TYPE_LINE)
	type_selector.add_item("Circle")
	type_selector.set_item_metadata(1, MARKER_TYPE_CIRCLE)
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
	
	# Create Circle settings UI
	circle_settings_container = _create_circle_settings_ui()
	circle_settings_container.name = "CircleSettings"
	circle_settings_container.visible = false
	type_specific_container.add_child(circle_settings_container)
	
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
	delete_check.pressed = delete_mode
	delete_check.name = "DeleteModeCheckbox"
	delete_check.connect("toggled", parent_mod, "_on_delete_mode_toggled", [self])
	container.add_child(delete_check)
	
	var delete_all_btn = Button.new()
	delete_all_btn.text = "Delete All Markers"
	delete_all_btn.connect("pressed", parent_mod, "_on_delete_all_markers", [self])
	container.add_child(delete_all_btn)
	
	container.add_child(_create_spacer(20))
	
	# === OPTIONS ===
	var options_label = Label.new()
	options_label.text = "Marker Options:"
	container.add_child(options_label)
	
	var snap_check = CheckButton.new()
	snap_check.text = "Snap to Grid"
	snap_check.pressed = snap_to_grid
	snap_check.name = "SnapCheckbox"
	snap_check.connect("toggled", parent_mod, "_on_snap_to_grid_toggled", [self])
	container.add_child(snap_check)
	
	var coords_check = CheckButton.new()
	coords_check.text = "Show Coordinates"
	coords_check.pressed = show_coordinates
	coords_check.name = "CoordinatesCheckbox"
	coords_check.connect("toggled", parent_mod, "_on_show_coordinates_toggled", [self])
	container.add_child(coords_check)
	
	container.add_child(_create_spacer(20))
	
	# === GUIDE OVERLAYS ===
	var overlays_label = Label.new()
	overlays_label.text = "Guide Overlays:"
	overlays_label.align = Label.ALIGN_CENTER
	container.add_child(overlays_label)
	
	var cross_check = CheckButton.new()
	cross_check.text = "Cross Guides (proximity)"
	cross_check.pressed = parent_mod.cross_guides_enabled
	cross_check.name = "CrossGuidesCheckbox"
	cross_check.connect("toggled", parent_mod, "_on_cross_guides_toggled")
	container.add_child(cross_check)
	
	var perm_vert_check = CheckButton.new()
	perm_vert_check.text = "Vertical Center Line"
	perm_vert_check.pressed = parent_mod.perm_vertical_enabled
	perm_vert_check.name = "PermVerticalCheckbox"
	perm_vert_check.connect("toggled", parent_mod, "_on_perm_vertical_toggled")
	container.add_child(perm_vert_check)
	
	var perm_horiz_check = CheckButton.new()
	perm_horiz_check.text = "Horizontal Center Line"
	perm_horiz_check.pressed = parent_mod.perm_horizontal_enabled
	perm_horiz_check.name = "PermHorizontalCheckbox"
	perm_horiz_check.connect("toggled", parent_mod, "_on_perm_horizontal_toggled")
	container.add_child(perm_horiz_check)
	
	var perm_coords_check = CheckButton.new()
	perm_coords_check.text = "Show Grid Coordinates"
	perm_coords_check.pressed = parent_mod.show_coordinates_enabled
	perm_coords_check.name = "PermCoordinatesCheckbox"
	perm_coords_check.connect("toggled", parent_mod, "_on_perm_coordinates_toggled")
	container.add_child(perm_coords_check)
	
	tool_panel.Align.add_child(container)

# UI Callbacks for custom line settings
func _on_quick_angle_pressed(angle_value):
	active_angle = angle_value
	_update_angle_spinbox()
	if LOGGER:
		LOGGER.debug("Quick angle set to: %.1f°" % [angle_value])

func _on_angle_changed(value):
	active_angle = value
	# Update preview
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Angle changed to: %.1f°" % [value])

func _on_range_changed(value):
	active_line_range = value
	# Update preview
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Range changed to: %.1f cells" % [value])

func _on_color_changed(new_color):
	active_color = new_color
	# Update preview
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Color changed to: %s" % [new_color.to_html()])

func _on_mirror_toggled(enabled):
	active_mirror = enabled
	# Update preview
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Mirror toggled: %s" % [str(enabled)])

func _on_reset_pressed():
	# Reset type-specific settings
	if active_marker_type == MARKER_TYPE_LINE:
		active_angle = DEFAULT_ANGLE
		active_line_range = DEFAULT_LINE_RANGE
		active_mirror = DEFAULT_MIRROR
		
		type_settings[MARKER_TYPE_LINE]["angle"] = DEFAULT_ANGLE
		type_settings[MARKER_TYPE_LINE]["range"] = DEFAULT_LINE_RANGE
		type_settings[MARKER_TYPE_LINE]["mirror"] = DEFAULT_MIRROR
		
		_update_angle_spinbox()
		_update_range_spinbox()
		_update_mirror_checkbox()
	
	# Reset Circle type settings
	elif active_marker_type == MARKER_TYPE_CIRCLE:
		active_circle_radius = DEFAULT_CIRCLE_RADIUS
		
		type_settings[MARKER_TYPE_CIRCLE]["radius"] = DEFAULT_CIRCLE_RADIUS
		
		_update_circle_radius_spinbox()
	
	# Reset common settings (always)
	active_color = DEFAULT_COLOR
	_update_color_picker()
	
	# Update preview
	if overlay:
		overlay.update()
	
	if LOGGER:
		LOGGER.info("Settings reset to defaults for type: %s" % [active_marker_type])

func _update_angle_spinbox():
	if not tool_panel:
		if LOGGER:
			LOGGER.debug("_update_angle_spinbox: tool_panel is null")
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("AngleSpinBox", true, false)
		if spinbox:
			if LOGGER:
				LOGGER.debug("Updating AngleSpinBox: %.1f° -> %.1f°" % [spinbox.value, active_angle])
			spinbox.value = active_angle
		else:
			if LOGGER:
				LOGGER.debug("_update_angle_spinbox: AngleSpinBox not found")
	else:
		if LOGGER:
			LOGGER.debug("_update_angle_spinbox: container is null")

func _update_range_spinbox():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("RangeSpinBox", true, false)
		if spinbox:
			spinbox.value = active_line_range

func _update_color_picker():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var picker = container.find_node("ColorPicker", true, false)
		if picker:
			picker.color = active_color

func _update_mirror_checkbox():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var checkbox = container.find_node("MirrorCheckbox", true, false)
		if checkbox:
			checkbox.pressed = active_mirror

# UI Callbacks for Circle settings
func _on_circle_radius_changed(value):
	# Ensure minimum radius of 0.1
	if value < 0.1:
		value = 0.1
	active_circle_radius = value
	
	# Update the spinbox if it was set below minimum
	_update_circle_radius_spinbox()
	
	# Update preview
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Circle radius changed to: %.1f cells" % [value])

func _update_circle_radius_spinbox():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("CircleRadiusSpinBox", true, false)
		if spinbox:
			spinbox.value = active_circle_radius

func _create_spacer(height):
	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, height)
	return spacer

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
	angle_spin.value = active_angle
	angle_spin.name = "AngleSpinBox"
	angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_spin.connect("value_changed", self, "_on_angle_changed")
	angle_hbox.add_child(angle_spin)
	container.add_child(angle_hbox)
	
	# Range SpinBox
	var range_hbox = HBoxContainer.new()
	var range_label = Label.new()
	range_label.text = "Range:"
	range_label.rect_min_size = Vector2(80, 0)
	range_hbox.add_child(range_label)
	
	var range_spin = SpinBox.new()
	range_spin.min_value = 0
	range_spin.max_value = 100
	range_spin.step = 1
	range_spin.value = active_line_range
	range_spin.name = "RangeSpinBox"
	range_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_spin.connect("value_changed", self, "_on_range_changed")
	range_spin.allow_greater = true
	range_spin.allow_lesser = false
	range_hbox.add_child(range_spin)
	container.add_child(range_hbox)
	
	var range_hint = Label.new()
	range_hint.text = "  (grid cells, 0 = infinite)"
	range_hint.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	container.add_child(range_hint)
	
	# Mirror CheckBox
	var mirror_check = CheckButton.new()
	mirror_check.text = "Mirror"
	mirror_check.pressed = active_mirror
	mirror_check.name = "MirrorCheckbox"
	mirror_check.connect("toggled", self, "_on_mirror_toggled")
	container.add_child(mirror_check)
	
	return container

# Create UI for Circle marker type
func _create_circle_settings_ui():
	var container = VBoxContainer.new()
	
	var info_label = Label.new()
	info_label.text = "Circle guide around marker"
	info_label.align = Label.ALIGN_CENTER
	info_label.add_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	container.add_child(info_label)
	
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
	radius_spin.value = active_circle_radius
	radius_spin.name = "CircleRadiusSpinBox"
	radius_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radius_spin.connect("value_changed", self, "_on_circle_radius_changed")
	radius_spin.allow_greater = true
	radius_spin.allow_lesser = false
	radius_hbox.add_child(radius_spin)
	container.add_child(radius_hbox)
	
	var radius_hint = Label.new()
	radius_hint.text = "  (grid cells, min = 0.1)"
	radius_hint.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	container.add_child(radius_hint)
	
	return container

# Create UI for Path marker type
func _create_path_settings_ui():
	var container = VBoxContainer.new()
	
	var info_label = Label.new()
	info_label.text = "Multi-point path guide"
	info_label.align = Label.ALIGN_CENTER
	info_label.add_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	container.add_child(info_label)
	
	container.add_child(_create_spacer(10))
	
	var instructions = Label.new()
	instructions.text = "Instructions:\n• Click to add points\n• Click near first point to close\n• Right-click to finish open path\n• ESC to cancel"
	instructions.autowrap = true
	instructions.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	container.add_child(instructions)
	
	container.add_child(_create_spacer(10))
	
	# Status label (shows current point count)
	var status_label = Label.new()
	status_label.name = "PathStatusLabel"
	status_label.text = "Ready to start"
	status_label.align = Label.ALIGN_CENTER
	status_label.add_color_override("font_color", Color(0.5, 1.0, 0.5, 1))
	container.add_child(status_label)
	
	container.add_child(_create_spacer(10))
	
	# Cancel button (only visible during placement)
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel Path"
	cancel_btn.name = "PathCancelButton"
	cancel_btn.connect("pressed", self, "_cancel_path_placement")
	cancel_btn.visible = false
	container.add_child(cancel_btn)
	
	return container

# Create common settings UI (Color, Reset)
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
	color_picker.color = active_color
	color_picker.name = "ColorPicker"
	color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker.connect("color_changed", self, "_on_color_changed")
	color_hbox.add_child(color_picker)
	container.add_child(color_hbox)
	
	# Reset Button
	var reset_btn = Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.name = "ResetButton"
	reset_btn.connect("pressed", self, "_on_reset_pressed")
	container.add_child(reset_btn)
	
	return container

# ============================================================================
# MARKER TYPE SWITCHING
# ============================================================================

# Handle marker type selection change
func _on_marker_type_changed(type_index):
	var selected_type = type_selector.get_item_metadata(type_index)
	
	# Save current type settings before switching
	_save_current_type_settings()
	
	# Switch to new type
	active_marker_type = selected_type
	
	# Load settings for new type
	_load_type_settings(selected_type)
	
	# Switch visible UI container
	_switch_type_ui(selected_type)
	
	# Update preview
	if overlay:
		overlay.update()
	
	if LOGGER:
		LOGGER.debug("Marker type changed to: %s" % [selected_type])

# Switch visible type-specific UI container
func _switch_type_ui(marker_type):
	# Cancel path placement if switching away from Path
	if active_marker_type == MARKER_TYPE_PATH and marker_type != MARKER_TYPE_PATH:
		_cancel_path_placement()
	
	# Hide all type-specific containers
	for child in type_specific_container.get_children():
		child.visible = false
	
	# Show the selected type's container
	match marker_type:
		MARKER_TYPE_LINE:
			if line_settings_container:
				line_settings_container.visible = true
		MARKER_TYPE_CIRCLE:
			if circle_settings_container:
				circle_settings_container.visible = true
		MARKER_TYPE_PATH:
			if path_settings_container:
				path_settings_container.visible = true

# Load settings for specific marker type
func _load_type_settings(marker_type):
	if not type_settings.has(marker_type):
		return
	
	var settings = type_settings[marker_type]
	
	# Load Line type settings
	if marker_type == MARKER_TYPE_LINE:
		active_angle = settings["angle"]
		active_line_range = settings["range"]
		active_mirror = settings["mirror"]
		
		# Update UI
		_update_angle_spinbox()
		_update_range_spinbox()
		_update_mirror_checkbox()
	
	# Load Circle type settings
	elif marker_type == MARKER_TYPE_CIRCLE:
		active_circle_radius = settings["radius"]
		
		# Update UI
		_update_circle_radius_spinbox()

# Save current type settings before switching
func _save_current_type_settings():
	if not type_settings.has(active_marker_type):
		type_settings[active_marker_type] = {}
	
	# Save Line type settings
	if active_marker_type == MARKER_TYPE_LINE:
		type_settings[MARKER_TYPE_LINE]["angle"] = active_angle
		type_settings[MARKER_TYPE_LINE]["range"] = active_line_range
		type_settings[MARKER_TYPE_LINE]["mirror"] = active_mirror
	
	# Save Circle type settings
	elif active_marker_type == MARKER_TYPE_CIRCLE:
		type_settings[MARKER_TYPE_CIRCLE]["radius"] = active_circle_radius

# ============================================================================
# MOUSE WHEEL PARAMETER ADJUSTMENT
# ============================================================================

# Adjust angle using mouse wheel (only for Line type)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_angle_with_wheel(direction):
	if LOGGER:
		LOGGER.debug("adjust_angle_with_wheel called: direction=%d, current_type=%s, current_angle=%.1f" % [direction, active_marker_type, active_angle])
	
	# Only works for Line type
	if active_marker_type != MARKER_TYPE_LINE:
		if LOGGER:
			LOGGER.debug("Wheel adjustment ignored - not Line type")
		return
	
	# Angle step: 1 degree per wheel tick
	var angle_step = 1.0
	
	var new_angle = active_angle + (direction * angle_step)
	
	# Wrap around: 0-360 degrees
	if new_angle < 0:
		new_angle += 360
	elif new_angle >= 360:
		new_angle -= 360
	
	if LOGGER:
		LOGGER.debug("Angle changing: %.1f° -> %.1f°" % [active_angle, new_angle])
	
	active_angle = new_angle
	
	# Save to type settings
	type_settings[MARKER_TYPE_LINE]["angle"] = active_angle
	
	# Update UI
	_update_angle_spinbox()
	
	# Update preview
	if overlay:
		overlay.update()
	
	if LOGGER:
		LOGGER.info("Angle adjusted via mouse wheel: %.1f°" % [active_angle])

# Adjust circle radius using mouse wheel (only for Circle type)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_circle_radius_with_wheel(direction):
	if LOGGER:
		LOGGER.debug("adjust_circle_radius_with_wheel called: direction=%d, current_type=%s, current_radius=%.1f" % [direction, active_marker_type, active_circle_radius])
	
	# Only works for Circle type
	if active_marker_type != MARKER_TYPE_CIRCLE:
		if LOGGER:
			LOGGER.debug("Wheel adjustment ignored - not Circle type")
		return
	
	# Radius step: 0.1 cells per wheel tick
	var radius_step = 0.1
	
	var new_radius = active_circle_radius + (direction * radius_step)
	
	# Ensure minimum of 0.1
	if new_radius < 0.1:
		new_radius = 0.1
	
	if LOGGER:
		LOGGER.debug("Radius changing: %.1f cells -> %.1f cells" % [active_circle_radius, new_radius])
	
	active_circle_radius = new_radius
	
	# Save to type settings
	type_settings[MARKER_TYPE_CIRCLE]["radius"] = active_circle_radius
	
	# Update UI
	_update_circle_radius_spinbox()
	
	# Update preview
	if overlay:
		overlay.update()
	
	if LOGGER:
		LOGGER.info("Circle radius adjusted via mouse wheel: %.1f cells" % [active_circle_radius])

