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
var active_marker_types = ["vertical", "horizontal"]  # Array of currently selected types
var snap_to_grid = true  # Snap markers to grid by default
var show_coordinates = false  # Show grid coordinates on new markers
var delete_mode = false  # Delete mode - click to remove markers

# Markers storage
var markers = []  # Array of GuideMarker instances
var next_id = 0

# UI References
var tool_panel = null
var overlay = null  # Node2D for drawing

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
# Applies grid snapping and active guide line types
func place_marker(pos):
	# Apply grid snapping if enabled
	var snapped_pos = snap_position_to_grid(pos)
	
	var marker_data = {
		"position": snapped_pos,
		"types": active_marker_types.duplicate(),
		"coordinates": show_coordinates,
		"id": next_id
	}
	
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
	markers.clear()
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
	var marker = GuideMarkerClass.new(
		marker_data["position"],
		marker_data["types"],
		marker_data["coordinates"]
	)
	marker.id = marker_data["id"]
	markers.append(marker)
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Marker placed at %s with types: %s" % [marker_data["position"], str(marker_data["types"])])

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

# Toggle a guide line type on/off for new markers
func toggle_marker_type(type, enabled):
	if enabled:
		if not active_marker_types.has(type):
			active_marker_types.append(type)
	else:
		active_marker_types.erase(type)
	
	# If no line types selected, disable coordinates
	if active_marker_types.size() == 0:
		show_coordinates = false
		update_snap_checkbox_state()
		update_coordinates_checkbox_state()
	else:
		# Re-enable coordinates checkbox if it was disabled
		update_coordinates_checkbox_state()

# Enable/disable grid snapping for marker placement
func set_snap_to_grid(enabled):
	# Can't disable snap when coordinates are enabled
	if show_coordinates and not enabled:
		return
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

# Update coordinates checkbox enabled/disabled state based on active marker types
func update_coordinates_checkbox_state():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var coords_check = container.get_node_or_null("CoordinatesCheckbox")
		if coords_check:
			coords_check.pressed = show_coordinates
			# Disable coordinates if no line types are selected
			coords_check.disabled = (active_marker_types.size() == 0)

# Update all UI checkboxes based on delete mode
func update_ui_checkboxes_state():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		# Disable all type checkboxes, snap, and coordinates when delete mode is on
		for child in container.get_children():
			if child is CheckButton:
				if child.name == "DeleteModeCheckbox":
					continue  # Don't disable delete mode checkbox itself
				child.disabled = delete_mode

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
			info_label.text = "Click to place markers.\nMarkers: " + str(markers.size())

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
		
		if marker.id >= next_id:
			next_id = marker.id + 1
	
	if overlay:
		overlay.update()

# Create the UI panel for the tool with all controls
# Includes checkboxes for guide line types and marker management
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
	
	# Marker type selection with checkboxes
	var type_label = Label.new()
	type_label.text = "Marker Types:"
	container.add_child(type_label)
	
	# Vertical checkbox
	var vert_check = CheckButton.new()
	vert_check.text = "Vertical Lines"
	vert_check.pressed = active_marker_types.has("vertical")
	vert_check.name = "VerticalCheckbox"
	vert_check.connect("toggled", parent_mod, "_on_marker_type_toggled", ["vertical", self])
	container.add_child(vert_check)
	
	# Horizontal checkbox
	var horiz_check = CheckButton.new()
	horiz_check.text = "Horizontal Lines"
	horiz_check.pressed = active_marker_types.has("horizontal")
	horiz_check.name = "HorizontalCheckbox"
	horiz_check.connect("toggled", parent_mod, "_on_marker_type_toggled", ["horizontal", self])
	container.add_child(horiz_check)
	
	# Diagonal Left checkbox (135°)
	var diag_left_check = CheckButton.new()
	diag_left_check.text = "Diagonal Left (135°)"
	diag_left_check.pressed = active_marker_types.has("diagonal_left")
	diag_left_check.name = "DiagonalLeftCheckbox"
	diag_left_check.connect("toggled", parent_mod, "_on_marker_type_toggled", ["diagonal_left", self])
	container.add_child(diag_left_check)
	
	# Diagonal Right checkbox (45°)
	var diag_right_check = CheckButton.new()
	diag_right_check.text = "Diagonal Right (45°)"
	diag_right_check.pressed = active_marker_types.has("diagonal_right")
	diag_right_check.name = "DiagonalRightCheckbox"
	diag_right_check.connect("toggled", parent_mod, "_on_marker_type_toggled", ["diagonal_right", self])
	container.add_child(diag_right_check)
	
	container.add_child(_create_spacer(10))

	# Delete Mode checkbox (placed first for visibility)
	var delete_check = CheckButton.new()
	delete_check.text = "Delete Markers Mode"
	delete_check.pressed = delete_mode
	delete_check.name = "DeleteModeCheckbox"
	delete_check.connect("toggled", parent_mod, "_on_delete_mode_toggled", [self])
	container.add_child(delete_check)
	
	# Delete all button
	var delete_all_btn = Button.new()
	delete_all_btn.text = "Delete All Markers"
	delete_all_btn.connect("pressed", parent_mod, "_on_delete_all_markers", [self])
	container.add_child(delete_all_btn)
	
	container.add_child(_create_spacer(20))

	# Marker settings with checkboxes
	var marker_settings_label = Label.new()
	marker_settings_label.text = "Marker Settings:"
	container.add_child(marker_settings_label)
	
	# Snap to Grid checkbox
	var snap_check = CheckButton.new()
	snap_check.text = "Snap to Grid"
	snap_check.pressed = snap_to_grid
	snap_check.name = "SnapCheckbox"  # Name for easy reference
	snap_check.connect("toggled", parent_mod, "_on_snap_to_grid_toggled", [self])
	container.add_child(snap_check)
	
	# Show Coordinates checkbox
	var coords_check = CheckButton.new()
	coords_check.text = "Show Coordinates"
	coords_check.pressed = show_coordinates
	coords_check.name = "CoordinatesCheckbox"
	coords_check.connect("toggled", parent_mod, "_on_show_coordinates_toggled", [self])
	container.add_child(coords_check)
	
	container.add_child(_create_spacer(20))
	
	# === GUIDE OVERLAYS SECTION ===
	var overlays_label = Label.new()
	overlays_label.text = "Guide Overlays:"
	overlays_label.align = Label.ALIGN_CENTER
	container.add_child(overlays_label)
	
	# Cross Guides (proximity-based)
	var cross_check = CheckButton.new()
	cross_check.text = "Cross Guides (proximity)"
	cross_check.pressed = parent_mod.cross_guides_enabled
	cross_check.name = "CrossGuidesCheckbox"
	cross_check.connect("toggled", parent_mod, "_on_cross_guides_toggled")
	container.add_child(cross_check)
	
	# Permanent Vertical Guide
	var perm_vert_check = CheckButton.new()
	perm_vert_check.text = "Vertical Center Line"
	perm_vert_check.pressed = parent_mod.perm_vertical_enabled
	perm_vert_check.name = "PermVerticalCheckbox"
	perm_vert_check.connect("toggled", parent_mod, "_on_perm_vertical_toggled")
	container.add_child(perm_vert_check)
	
	# Permanent Horizontal Guide
	var perm_horiz_check = CheckButton.new()
	perm_horiz_check.text = "Horizontal Center Line"
	perm_horiz_check.pressed = parent_mod.perm_horizontal_enabled
	perm_horiz_check.name = "PermHorizontalCheckbox"
	perm_horiz_check.connect("toggled", parent_mod, "_on_perm_horizontal_toggled")
	container.add_child(perm_horiz_check)
	
	# Show Grid Coordinates on permanent guides
	var perm_coords_check = CheckButton.new()
	perm_coords_check.text = "Show Grid Coordinates"
	perm_coords_check.pressed = parent_mod.show_coordinates_enabled
	perm_coords_check.name = "PermCoordinatesCheckbox"
	perm_coords_check.connect("toggled", parent_mod, "_on_perm_coordinates_toggled")
	container.add_child(perm_coords_check)
	
	tool_panel.Align.add_child(container)

func _create_spacer(height):
	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, height)
	return spacer

