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
var show_coordinates = false  # Show grid coordinates on new markers
var delete_mode = false  # Delete mode - click to remove markers

# Marker type system
const MARKER_TYPE_LINE = "Line"
const MARKER_TYPE_SHAPE = "Shape"
const MARKER_TYPE_PATH = "Path"
const MARKER_TYPE_ARROW = "Arrow"

# Shape subtypes
const SHAPE_CIRCLE = "Circle"
const SHAPE_SQUARE = "Square"
const SHAPE_PENTAGON = "Pentagon"
const SHAPE_HEXAGON = "Hexagon"
const SHAPE_OCTAGON = "Octagon"

var active_marker_type = MARKER_TYPE_LINE  # Current selected marker type

# Active marker settings (for new markers)
var active_angle = 0.0
var active_shape_radius = 1.0  # Shape radius in grid cells (circumradius)
var active_shape_subtype = SHAPE_CIRCLE  # Active shape subtype
var active_shape_angle = 0.0  # Shape rotation angle in degrees
var active_arrow_head_length = 50.0  # Arrow head length in pixels
var active_arrow_head_angle = 30.0  # Arrow head angle in degrees
var active_color = Color(0, 0.7, 1, 1)
var active_mirror = false

# Type-specific settings storage (each type stores its own parameters)
var type_settings = {
	"Line": {
		"angle": 0.0,
		"mirror": false
	},
	"Shape": {
		"subtype": "Circle",
		"radius": 1.0,
		"angle": 0.0
	},
	"Path": {
		# Path has no persistent settings, it's point-based
	},
	"Arrow": {
		"head_length": 50.0,
		"head_angle": 30.0
	}
}

# Default values
const DEFAULT_ANGLE = 0.0
const DEFAULT_SHAPE_RADIUS = 1.0
const DEFAULT_SHAPE_SUBTYPE = "Circle"
const DEFAULT_SHAPE_ANGLE = 0.0
const DEFAULT_ARROW_HEAD_LENGTH = 50.0
const DEFAULT_ARROW_HEAD_ANGLE = 30.0
const DEFAULT_COLOR = Color(0, 0.7, 1, 1)
const DEFAULT_MIRROR = false

# Markers storage
var markers = []  # Array of GuideMarker instances
var markers_lookup = {} # Dictionary { id: GuideMarker } for O(1) access
var next_id = 0

# UI References
var tool_panel = null
var overlay = null  # Node2D for drawing
var type_selector = null  # OptionButton for marker type selection
var type_specific_container = null  # Container for type-specific settings
var line_settings_container = null  # Settings for Line type
var shape_settings_container = null  # Settings for Shape type
var path_settings_container = null  # Settings for Path type
var arrow_settings_container = null  # Settings for Arrow type

# Path placement state
var path_placement_active = false  # Whether we're in path placement mode
var path_temp_points = []  # Temporary storage for points being placed
var path_preview_point = null  # Current mouse position for line preview

# Arrow placement state (similar to path but auto-finishes at 2 points)
var arrow_placement_active = false  # Whether we're in arrow placement mode
var arrow_temp_points = []  # Temporary storage for arrow points (max 2)
var arrow_preview_point = null  # Current mouse position for arrow preview

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

var last_log_time = 0.0  # Use time instead of frame counter
var first_update_logged = false
const LOG_INTERVAL = 5.0  # Log every 5 seconds

# Main update loop - manages overlay and drawing
func Update(delta):
	# Debug: Check LOGGER status on first update
	if not first_update_logged:
		first_update_logged = true
		if LOGGER:
			LOGGER.info("GuidesLinesTool.Update() first call - LOGGER is available")
	
	# Log status every 5 seconds
	if LOGGER and is_enabled:
		last_log_time += delta
		if last_log_time >= LOG_INTERVAL:
			last_log_time = 0.0
			LOGGER.debug("Tool active: overlay=%s, markers=%d" % [str(overlay != null), markers.size()])
	
	if not is_enabled:
		return
	
	# Create overlay if needed
	if not overlay and cached_worldui:
		_create_overlay()
	
	# Overlay manages its own update based on changes
	# No need to force update every frame

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
	
	# Special handling for Arrow type
	if active_marker_type == MARKER_TYPE_ARROW:
		_handle_arrow_placement(pos)
		return
	
	# Apply grid snapping if enabled globally
	var final_pos = pos
	if parent_mod.Global.Editor.IsSnapping:
		final_pos = snap_position_to_grid(pos)
	
	var marker_data = {
		"position": final_pos,
		"marker_type": active_marker_type,
		"color": active_color,
		"coordinates": show_coordinates,
		"id": next_id
	}
	
	# Add type-specific parameters
	if active_marker_type == MARKER_TYPE_LINE:
		marker_data["angle"] = active_angle
		marker_data["mirror"] = active_mirror
	elif active_marker_type == MARKER_TYPE_SHAPE:
		marker_data["shape_subtype"] = active_shape_subtype
		marker_data["shape_radius"] = active_shape_radius
		marker_data["shape_angle"] = active_shape_angle
	
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
	# Apply grid snapping if enabled globally
	var final_pos = pos
	if parent_mod.Global.Editor.IsSnapping:
		final_pos = snap_position_to_grid(pos)
	
	# First point - start path placement
	if not path_placement_active:
		path_placement_active = true
		path_temp_points = [final_pos]
		if LOGGER:
			LOGGER.info("Path placement started at %s" % [str(final_pos)])
		update_ui()
		return
	
	# Check if clicking near first point (close path)
	var first_point = path_temp_points[0]
	if final_pos.distance_to(first_point) < 30.0 and path_temp_points.size() >= 3:
		# Close path and create marker
		var point_count = path_temp_points.size()
		_finalize_path_marker(true)
		if LOGGER:
			LOGGER.info("Path closed with %d points" % [point_count])
		return
	
	# Add new point to path
	path_temp_points.append(final_pos)
	if LOGGER:
		LOGGER.debug("Path point added: %s (total: %d)" % [str(final_pos), path_temp_points.size()])
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
		"marker_points": path_temp_points.duplicate(),
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

# Handle arrow marker placement (2-point auto-finish)
func _handle_arrow_placement(pos):
	# Apply grid snapping if enabled globally
	var final_pos = pos
	if parent_mod.Global.Editor.IsSnapping:
		final_pos = snap_position_to_grid(pos)
	
	# First point - start arrow placement
	if not arrow_placement_active:
		arrow_placement_active = true
		arrow_temp_points = [final_pos]
		if LOGGER:
			LOGGER.info("Arrow placement started at %s" % [str(final_pos)])
		update_ui()
		return
	
	# Second point - auto-finish arrow
	if arrow_temp_points.size() == 1:
		arrow_temp_points.append(final_pos)
		if LOGGER:
			LOGGER.info("Arrow completed with 2 points")
		_finalize_arrow_marker()
		return

# Finalize arrow marker (auto-called after 2 points)
func _finalize_arrow_marker():
	if not arrow_placement_active or arrow_temp_points.size() != 2:
		_cancel_arrow_placement()
		return
	
	# Create marker data
	var marker_data = {
		"position": arrow_temp_points[0],  # First point is marker position
		"marker_type": MARKER_TYPE_ARROW,
		"color": active_color,
		"coordinates": show_coordinates,
		"id": next_id,
		"marker_points": arrow_temp_points.duplicate(),
		"arrow_head_length": active_arrow_head_length,
		"arrow_head_angle": active_arrow_head_angle
	}
	
	# Execute the action first
	_do_place_marker(marker_data)
	next_id += 1
	
	# Add to history
	if parent_mod.Global.API and parent_mod.Global.API.has("HistoryApi"):
		if LOGGER:
			LOGGER.debug("Adding arrow marker to history (id: %d)" % [marker_data["id"]])
		var record = PlaceMarkerRecord.new(self, marker_data)
		parent_mod.Global.API.HistoryApi.record(record, 100)
	
	# Reset arrow state
	_cancel_arrow_placement()

# Cancel arrow placement (ESC or new type selected)
func _cancel_arrow_placement():
	arrow_placement_active = false
	arrow_temp_points = []
	arrow_preview_point = null
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
	markers_lookup = {} # Clear lookup
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
		markers_lookup[marker.id] = marker # Add to lookup
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
		var marker = markers[index]
		markers_lookup.erase(marker.id) # Remove from lookup
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
	markers_lookup[marker.id] = marker # Add to lookup
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
	marker.set_property("position", marker_data["position"])
	marker.id = marker_data["id"] 
	marker.set_property("marker_type", marker_data["marker_type"])
	marker.color = marker_data["color"]
	marker.set_property("show_coordinates", marker_data["coordinates"])
	
	# Load type-specific parameters
	if marker_data["marker_type"] == MARKER_TYPE_LINE:
		marker.set_property("angle", marker_data.get("angle", 0.0))
		marker.set_property("mirror", marker_data.get("mirror", false))
	elif marker_data["marker_type"] == MARKER_TYPE_SHAPE:
		marker.set_property("shape_subtype", marker_data["shape_subtype"])
		marker.set_property("shape_radius", marker_data["shape_radius"])
		marker.set_property("shape_angle", marker_data.get("shape_angle", 0.0))
		# Generate marker_points for Shape (vertices) - GuideMarker handles this via cache now
		# But if we need to store them for save/load, we might still want to generate them?
		# The old code did: marker.marker_points = _generate_shape_vertices(...)
		# We should let GuideMarker handle vertices. Marker points are mainly for custom paths/arrows
		# and potentially for saved Shapes if we want to freeze them?
		pass 
	elif marker_data["marker_type"] == MARKER_TYPE_PATH:
		marker.set_property("marker_points", marker_data["marker_points"].duplicate())
		marker.set_property("path_closed", marker_data["path_closed"])
	elif marker_data["marker_type"] == MARKER_TYPE_ARROW:
		marker.set_property("marker_points", marker_data["marker_points"].duplicate())
		marker.set_property("arrow_head_length", marker_data["arrow_head_length"])
		marker.set_property("arrow_head_angle", marker_data["arrow_head_angle"])
	
	markers.append(marker)
	markers_lookup[marker.id] = marker # Add to lookup
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		if marker_data["marker_type"] == MARKER_TYPE_LINE:
			LOGGER.debug("Line marker placed at %s (angle: %.1f°, mirror: %s)" % [
				str(marker_data["position"]),
				marker_data.get("angle", 0.0),
				str(marker_data.get("mirror", false))
			])
		elif marker_data["marker_type"] == MARKER_TYPE_SHAPE:
			LOGGER.debug("Shape marker placed at %s (subtype: %s, radius: %.1f cells)" % [
				str(marker_data["position"]),
				marker_data["shape_subtype"],
				marker_data["shape_radius"]
			])
		elif marker_data["marker_type"] == MARKER_TYPE_PATH:
			LOGGER.debug("Path marker placed with %d points (closed: %s)" % [
				marker_data["marker_points"].size(),
				str(marker_data["path_closed"])
			])
		elif marker_data["marker_type"] == MARKER_TYPE_ARROW:
			LOGGER.debug("Arrow marker placed with 2 points (head: %.1fpx at %.1f°)" % [
				marker_data["arrow_head_length"],
				marker_data["arrow_head_angle"]
			])

func _undo_place_marker(marker_id):
	# Optimized removal using Dictionary lookup
	if markers_lookup.has(marker_id):
		var marker = markers_lookup[marker_id]
		markers.erase(marker) # Godot optimizes erase by value, but still O(n) for array search internally
		markers_lookup.erase(marker_id) # O(1)
		
		update_ui()
		if overlay:
			overlay.update()
		if LOGGER:
			LOGGER.debug("Marker placement undone (id: %d)" % [marker_id])
	else:
		if LOGGER:
			LOGGER.warn("Attempted to undo placement of non-existent marker id: %d" % [marker_id])

# Enable/disable coordinate display on new markers
func set_show_coordinates(enabled):
	# Coordinates require snapping, but we now rely on global snap.
	# We can just set the value.
	show_coordinates = enabled
	
	# Update UI
	if tool_panel:
		var coords_check = tool_panel.find_node("CoordinatesCheckbox", true, false)
		if coords_check:
			coords_check.pressed = show_coordinates

func set_delete_mode(enabled):
	delete_mode = enabled
	update_ui_checkboxes_state()
	# Force overlay update to hide/show preview
	if overlay:
		overlay.update()

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
	# Use custom_snap if available
	if cached_snappy_mod and cached_snappy_mod.has_method("get_snapped_position"):
		return cached_snappy_mod.get_snapped_position(position)
	
	# Use vanilla DD snap if custom_snap not available
	if cached_worldui:
		return cached_worldui.GetSnappedPosition(position)
	
	return position


# Get grid cell size (accounting for custom_snap mod if active)
func _get_grid_cell_size():
	if not cached_world:
		return null
	
	# Check if custom_snap is active and use its snap_interval
	if cached_snappy_mod and cached_snappy_mod.has("custom_snap_enabled") and cached_snappy_mod.custom_snap_enabled:
		if cached_snappy_mod.has("snap_interval"):
			return cached_snappy_mod.snap_interval
	
	# Fallback to vanilla grid cell size
	if not cached_world.Level or not cached_world.Level.TileMap:
		return null
	return cached_world.Level.TileMap.CellSize

# Update tool panel UI with current marker count
func update_ui():
	if not tool_panel:
		return
	
	var container = tool_panel.Align.get_child(0)
	if container:
		# Update cancel button visibility for Path mode
		if active_marker_type == MARKER_TYPE_PATH:
			var path_container = type_specific_container.get_node_or_null("PathSettings")
			if path_container:
				var cancel_btn = path_container.get_node_or_null("PathCancelButton")
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
		var marker = GuideMarkerClass.new()
		marker.Load(marker_data)
		markers.append(marker)
		markers_lookup[marker.id] = marker # Add to lookup
		
		if marker.id >= next_id:
			next_id = marker.id + 1
	
	if overlay:
		overlay.update()
	
	if LOGGER:
		LOGGER.info("%d markers loaded" % [markers.size()])

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
	type_selector.add_item("Arrow")
	type_selector.set_item_metadata(3, MARKER_TYPE_ARROW)
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
	
	# Create Arrow settings UI
	arrow_settings_container = _create_arrow_settings_ui()
	arrow_settings_container.name = "ArrowSettings"
	arrow_settings_container.visible = false
	type_specific_container.add_child(arrow_settings_container)
	
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
		active_mirror = DEFAULT_MIRROR
		
		type_settings[MARKER_TYPE_LINE]["angle"] = DEFAULT_ANGLE
		type_settings[MARKER_TYPE_LINE]["mirror"] = DEFAULT_MIRROR
		
		_update_angle_spinbox()
		_update_mirror_checkbox()
	
	# Reset Shape type settings
	elif active_marker_type == MARKER_TYPE_SHAPE:
		active_shape_radius = DEFAULT_SHAPE_RADIUS
		active_shape_subtype = DEFAULT_SHAPE_SUBTYPE
		active_shape_angle = DEFAULT_SHAPE_ANGLE
		
		type_settings[MARKER_TYPE_SHAPE]["radius"] = DEFAULT_SHAPE_RADIUS
		type_settings[MARKER_TYPE_SHAPE]["subtype"] = DEFAULT_SHAPE_SUBTYPE
		type_settings[MARKER_TYPE_SHAPE]["angle"] = DEFAULT_SHAPE_ANGLE
		
		_update_shape_radius_spinbox()
		_update_shape_subtype_selector()
		_update_shape_angle_spinbox()
	
	# Reset Arrow type settings
	elif active_marker_type == MARKER_TYPE_ARROW:
		active_arrow_head_length = DEFAULT_ARROW_HEAD_LENGTH
		active_arrow_head_angle = DEFAULT_ARROW_HEAD_ANGLE
		
		type_settings[MARKER_TYPE_ARROW]["head_length"] = DEFAULT_ARROW_HEAD_LENGTH
		type_settings[MARKER_TYPE_ARROW]["head_angle"] = DEFAULT_ARROW_HEAD_ANGLE
		
		_update_arrow_head_length_spinbox()
		_update_arrow_head_angle_spinbox()
	
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

# UI Callbacks for Shape settings
func _on_shape_subtype_changed(subtype_index):
	if not type_selector:
		return
	
	var subtype_selector = shape_settings_container.find_node("ShapeSubtypeSelector", true, false)
	if subtype_selector:
		active_shape_subtype = subtype_selector.get_item_metadata(subtype_index)
		type_settings[MARKER_TYPE_SHAPE]["subtype"] = active_shape_subtype
		
		# Enable/disable angle spinbox based on subtype
		var angle_spinbox = shape_settings_container.find_node("ShapeAngleSpinBox", true, false)
		if angle_spinbox:
			angle_spinbox.editable = (active_shape_subtype != SHAPE_CIRCLE)
		
		if overlay:
			overlay.update()
		
		if LOGGER:
			LOGGER.info("Shape subtype changed to: %s" % [active_shape_subtype])

func _on_shape_radius_changed(value):
	# Ensure minimum radius of 0.1
	if value < 0.1:
		value = 0.1
	active_shape_radius = value
	
	# Update the spinbox if it was set below minimum
	_update_shape_radius_spinbox()
	
	# Update preview
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Shape radius changed to: %.1f cells" % [value])

func _on_shape_angle_changed(value):
	active_shape_angle = value
	
	# Update preview
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Shape angle changed to: %.1f°" % [value])

func _update_shape_radius_spinbox():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("ShapeRadiusSpinBox", true, false)
		if spinbox:
			spinbox.value = active_shape_radius

func _update_shape_subtype_selector():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var selector = container.find_node("ShapeSubtypeSelector", true, false)
		if selector:
			for i in range(selector.get_item_count()):
				if selector.get_item_metadata(i) == active_shape_subtype:
					selector.selected = i
					break

func _update_shape_angle_spinbox():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("ShapeAngleSpinBox", true, false)
		if spinbox:
			spinbox.value = active_shape_angle
			# Update editable state based on subtype
			spinbox.editable = (active_shape_subtype != SHAPE_CIRCLE)

# UI Callbacks for Arrow settings
func _on_arrow_head_length_changed(value):
	# Ensure minimum length of 10
	if value < 10.0:
		value = 10.0
	active_arrow_head_length = value
	
	# Update the spinbox if it was set below minimum
	_update_arrow_head_length_spinbox()
	
	# Update preview
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Arrow head length changed to: %.1f px" % [value])

func _on_arrow_head_angle_changed(value):
	active_arrow_head_angle = value
	
	# Update preview
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Arrow head angle changed to: %.1f°" % [value])

func _update_arrow_head_length_spinbox():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("ArrowHeadLengthSpinBox", true, false)
		if spinbox:
			spinbox.value = active_arrow_head_length

func _update_arrow_head_angle_spinbox():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("ArrowHeadAngleSpinBox", true, false)
		if spinbox:
			spinbox.value = active_arrow_head_angle

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
	
	# Mirror CheckBox
	var mirror_check = CheckButton.new()
	mirror_check.text = "Mirror"
	mirror_check.pressed = active_mirror
	mirror_check.name = "MirrorCheckbox"
	mirror_check.connect("toggled", self, "_on_mirror_toggled")
	container.add_child(mirror_check)
	
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
	
	# Set current selection
	for i in range(subtype_option.get_item_count()):
		if subtype_option.get_item_metadata(i) == active_shape_subtype:
			subtype_option.selected = i
			break
	
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
	radius_spin.value = active_shape_radius
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
	
	# Angle SpinBox (disabled for Circle)
	var angle_hbox = HBoxContainer.new()
	var angle_label = Label.new()
	angle_label.text = "Angle (°):"
	angle_label.rect_min_size = Vector2(80, 0)
	angle_hbox.add_child(angle_label)
	
	var angle_spin = SpinBox.new()
	angle_spin.min_value = 0
	angle_spin.max_value = 360
	angle_spin.step = 1
	angle_spin.value = active_shape_angle
	angle_spin.name = "ShapeAngleSpinBox"
	angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_spin.connect("value_changed", self, "_on_shape_angle_changed")
	# Disable for Circle subtype
	angle_spin.editable = (active_shape_subtype != SHAPE_CIRCLE)
	angle_hbox.add_child(angle_spin)
	container.add_child(angle_hbox)
	
	return container

# Create UI for Path marker type
func _create_path_settings_ui():
	var container = VBoxContainer.new()
	
	# Cancel button (only visible during placement)
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel Path"
	cancel_btn.name = "PathCancelButton"
	cancel_btn.connect("pressed", self, "_cancel_path_placement")
	cancel_btn.visible = false
	container.add_child(cancel_btn)
	
	return container

# Create UI for Arrow marker type
func _create_arrow_settings_ui():
	var container = VBoxContainer.new()
	
	# Arrow head length SpinBox
	var head_length_hbox = HBoxContainer.new()
	var head_length_label = Label.new()
	head_length_label.text = "Head Length:"
	head_length_label.rect_min_size = Vector2(80, 0)
	head_length_hbox.add_child(head_length_label)
	
	var head_length_spin = SpinBox.new()
	head_length_spin.min_value = 10.0
	head_length_spin.max_value = 200.0
	head_length_spin.step = 5.0
	head_length_spin.value = active_arrow_head_length
	head_length_spin.name = "ArrowHeadLengthSpinBox"
	head_length_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_length_spin.connect("value_changed", self, "_on_arrow_head_length_changed")
	head_length_spin.allow_greater = true
	head_length_spin.allow_lesser = false
	head_length_hbox.add_child(head_length_spin)
	container.add_child(head_length_hbox)
	
	container.add_child(_create_spacer(5))
	
	# Arrow head angle SpinBox
	var head_angle_hbox = HBoxContainer.new()
	var head_angle_label = Label.new()
	head_angle_label.text = "Head Angle:"
	head_angle_label.rect_min_size = Vector2(80, 0)
	head_angle_hbox.add_child(head_angle_label)
	
	var head_angle_spin = SpinBox.new()
	head_angle_spin.min_value = 10.0
	head_angle_spin.max_value = 60.0
	head_angle_spin.step = 5.0
	head_angle_spin.value = active_arrow_head_angle
	head_angle_spin.name = "ArrowHeadAngleSpinBox"
	head_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_angle_spin.connect("value_changed", self, "_on_arrow_head_angle_changed")
	head_angle_hbox.add_child(head_angle_spin)
	container.add_child(head_angle_hbox)
	
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
	
	# Cancel arrow placement if switching away from Arrow
	if active_marker_type == MARKER_TYPE_ARROW and marker_type != MARKER_TYPE_ARROW:
		_cancel_arrow_placement()
	
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
		MARKER_TYPE_ARROW:
			if arrow_settings_container:
				arrow_settings_container.visible = true

# Load settings for specific marker type
func _load_type_settings(marker_type):
	if not type_settings.has(marker_type):
		return
	
	var settings = type_settings[marker_type]
	
	# Load Line type settings
	if marker_type == MARKER_TYPE_LINE:
		active_angle = settings["angle"]
		active_mirror = settings["mirror"]
		
		# Update UI
		_update_angle_spinbox()
		_update_mirror_checkbox()
	
	# Load Shape type settings
	elif marker_type == MARKER_TYPE_SHAPE:
		active_shape_subtype = settings["subtype"]
		active_shape_radius = settings["radius"]
		active_shape_angle = settings.get("angle", 0.0)
		
		# Update UI
		_update_shape_subtype_selector()
		_update_shape_radius_spinbox()
		_update_shape_angle_spinbox()
	
	# Load Arrow type settings
	elif marker_type == MARKER_TYPE_ARROW:
		active_arrow_head_length = settings["head_length"]
		active_arrow_head_angle = settings["head_angle"]
		
		# Update UI
		_update_arrow_head_length_spinbox()
		_update_arrow_head_angle_spinbox()

# Save current type settings before switching
func _save_current_type_settings():
	if not type_settings.has(active_marker_type):
		type_settings[active_marker_type] = {}
	
	# Save Line type settings
	if active_marker_type == MARKER_TYPE_LINE:
		type_settings[MARKER_TYPE_LINE]["angle"] = active_angle
		type_settings[MARKER_TYPE_LINE]["mirror"] = active_mirror
	
	# Save Shape type settings
	elif active_marker_type == MARKER_TYPE_SHAPE:
		type_settings[MARKER_TYPE_SHAPE]["subtype"] = active_shape_subtype
		type_settings[MARKER_TYPE_SHAPE]["radius"] = active_shape_radius
		type_settings[MARKER_TYPE_SHAPE]["angle"] = active_shape_angle
	
	# Save Arrow type settings
	elif active_marker_type == MARKER_TYPE_ARROW:
		type_settings[MARKER_TYPE_ARROW]["head_length"] = active_arrow_head_length
		type_settings[MARKER_TYPE_ARROW]["head_angle"] = active_arrow_head_angle

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

# Adjust shape radius using mouse wheel (only for Shape type)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_shape_radius_with_wheel(direction):
	if LOGGER:
		LOGGER.debug("adjust_shape_radius_with_wheel called: direction=%d, current_type=%s, current_radius=%.1f" % [direction, active_marker_type, active_shape_radius])
	
	# Only works for Shape type
	if active_marker_type != MARKER_TYPE_SHAPE:
		if LOGGER:
			LOGGER.debug("Wheel adjustment ignored - not Shape type")
		return
	
	# Radius step: 0.1 cells per wheel tick
	var radius_step = 0.1
	
	var new_radius = active_shape_radius + (direction * radius_step)
	
	# Ensure minimum of 0.1
	if new_radius < 0.1:
		new_radius = 0.1
	
	if LOGGER:
		LOGGER.debug("Radius changing: %.1f cells -> %.1f cells" % [active_shape_radius, new_radius])
	
	active_shape_radius = new_radius
	
	# Save to type settings
	type_settings[MARKER_TYPE_SHAPE]["radius"] = active_shape_radius
	
	# Update UI
	_update_shape_radius_spinbox()
	
	# Update preview
	if overlay:
		overlay.update()
	
	if LOGGER:
		LOGGER.info("Shape radius adjusted via mouse wheel: %.1f cells" % [active_shape_radius])

# Adjust shape angle using mouse wheel (only for Shape type, non-Circle)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_shape_angle_with_wheel(direction):
	if LOGGER:
		LOGGER.debug("adjust_shape_angle_with_wheel called: direction=%d, current_type=%s, current_angle=%.1f" % [direction, active_marker_type, active_shape_angle])
	
	# Only works for Shape type, and not for Circle
	if active_marker_type != MARKER_TYPE_SHAPE:
		if LOGGER:
			LOGGER.debug("Wheel angle adjustment ignored - not Shape type")
		return
	if active_shape_subtype == SHAPE_CIRCLE:
		if LOGGER:
			LOGGER.debug("Wheel angle adjustment ignored - Circle has no angle")
		return
	
	# Angle step: 5 degrees per wheel tick
	var angle_step = 5.0
	
	var new_angle = fmod(active_shape_angle + (direction * angle_step), 360.0)
	if new_angle < 0:
		new_angle += 360.0
	
	if LOGGER:
		LOGGER.debug("Shape angle changing: %.1f° -> %.1f°" % [active_shape_angle, new_angle])
	
	active_shape_angle = new_angle
	
	# Save to type settings
	type_settings[MARKER_TYPE_SHAPE]["angle"] = active_shape_angle
	
	# Update UI
	_update_shape_angle_spinbox()
	
	# Update preview
	if overlay:
		overlay.update()
	
	if LOGGER:
		LOGGER.info("Shape angle adjusted via mouse wheel: %.1f°" % [active_shape_angle])

# Rotate shape by 45 degrees via RMB shortcut
func rotate_shape_45():
	if LOGGER:
		LOGGER.debug("rotate_shape_45 called: current_type=%s, current_angle=%.1f" % [active_marker_type, active_shape_angle])
	
	# Only works for Shape type, and not for Circle
	if active_marker_type != MARKER_TYPE_SHAPE:
		if LOGGER:
			LOGGER.debug("rotate_shape_45 ignored - not Shape type")
		return
	if active_shape_subtype == SHAPE_CIRCLE:
		if LOGGER:
			LOGGER.debug("rotate_shape_45 ignored - Circle has no angle")
		return
	
	var new_angle = fmod(active_shape_angle + 45.0, 360.0)
	
	if LOGGER:
		LOGGER.debug("Shape angle rotating 45°: %.1f° -> %.1f°" % [active_shape_angle, new_angle])
	
	active_shape_angle = new_angle
	
	# Save to type settings
	type_settings[MARKER_TYPE_SHAPE]["angle"] = active_shape_angle
	
	# Update UI
	_update_shape_angle_spinbox()
	
	# Update preview
	if overlay:
		overlay.update()
	
	if LOGGER:
		LOGGER.info("Shape rotated 45° via RMB: %.1f°" % [active_shape_angle])

