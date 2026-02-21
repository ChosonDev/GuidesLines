extends Reference

# GuidesLinesTool - Tool for managing guide markers
# Stores markers internally and draws them via overlay

const CLASS_NAME = "GuidesLinesTool"
const GeometryUtils = preload("../utils/GeometryUtils.gd")

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

# History record for applying a Difference operation
# Uses snapshots to undo, because there is no "diff marker" that could be
# removed via _remove_shape_clipping.
class DifferenceRecord:
	var tool
	var diff_desc   # in-memory Dictionary (has Vector2 values — not serializable)
	var diff_op     # serializable Dictionary stored in tool.difference_ops
	var snapshots   # { marker_id: {"render_primitives":[...], "render_fills":[...], "clipped_by_ids":[...]} }

	func _init(tool_ref, p_desc, p_op, p_snapshots):
		tool = tool_ref
		diff_desc = p_desc
		diff_op   = p_op
		snapshots = p_snapshots

	func redo():
		tool._do_apply_difference(diff_desc, diff_op)

	func undo():
		for id in snapshots:
			if tool.markers_lookup.has(id):
				var m = tool.markers_lookup[id]
				m.set_render_primitives(
					snapshots[id]["render_primitives"].duplicate(true),
					snapshots[id]["render_fills"].duplicate(true))
				m.clipped_by_ids = snapshots[id]["clipped_by_ids"].duplicate()
		tool.difference_ops.erase(diff_op)
		if tool.overlay:
			tool.overlay.update()

	func record_type():
		return "GuidesLines.Difference"

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
const SHAPE_CUSTOM = "Custom"

var active_marker_type = MARKER_TYPE_LINE  # Current selected marker type

# Active marker settings (for new markers)
var active_angle = 0.0
var active_shape_radius = 1.0  # Shape radius in grid cells (circumradius)
var active_shape_subtype = SHAPE_CIRCLE  # Active shape subtype
var active_shape_angle = 0.0  # Shape rotation angle in degrees
var active_shape_sides = 6  # Number of polygon sides for Custom shape type
var active_arrow_head_length = 50.0  # Arrow head length in pixels
var active_arrow_head_angle = 30.0  # Arrow head angle in degrees
var active_color = Color(0, 0.7, 1, 1)
var active_mirror = false
var auto_clip_shapes = false  # Clip intersecting shape markers on placement (mutual)
var cut_existing_shapes = false  # Cut lines of existing markers inside the new shape (one-way)
var difference_mode = false  # Difference mode — don't place new shape; fill overlap into existing markers
var difference_ops = []  # Array of serializable op dicts; replayed on map load

# Type-specific settings storage (each type stores its own parameters)
var type_settings = {
	"Line": {
		"angle": 0.0,
		"mirror": false
	},
	"Shape": {
		"subtype": "Circle",
		"radius": 1.0,
		"angle": 0.0,
		"sides": 6
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
const DEFAULT_SHAPE_SIDES = 6
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
		# Still ensure overlay exists for API-placed markers
		if not overlay and cached_worldui:
			_create_overlay()
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

# Helper: record undo/redo action if HistoryApi is available.
# max_count: maximum number of records kept in history (0 = unlimited)
func _record_history(record, max_count: int = 100) -> void:
	if parent_mod.Global.API and parent_mod.Global.API.has("HistoryApi"):
		parent_mod.Global.API.HistoryApi.record(record, max_count)

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

	# Difference mode: don't place a marker — instead apply difference to existing shapes
	if difference_mode and active_marker_type == MARKER_TYPE_SHAPE:
		var final_pos_diff = pos
		if parent_mod.Global.Editor.IsSnapping:
			final_pos_diff = snap_position_to_grid(pos)
		var diff_desc = _build_shape_descriptor_at(final_pos_diff)
		if diff_desc.empty():
			return
		var diff_op = _op_from_desc(diff_desc)
		var snap = _take_difference_snapshot(diff_desc)
		_do_apply_difference(diff_desc, diff_op)
		_record_history(DifferenceRecord.new(self, diff_desc, diff_op, snap))
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
		marker_data["shape_sides"] = active_shape_sides
	
	# Execute the action first
	_do_place_marker(marker_data)
	next_id += 1
	
	# Then add to history if available
	if LOGGER:
		LOGGER.debug("Adding marker placement to history (id: %d)" % [marker_data["id"]])
	_record_history(PlaceMarkerRecord.new(self, marker_data))

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
	if LOGGER:
		LOGGER.debug("Adding path marker to history (id: %d)" % [marker_data["id"]])
	_record_history(PlaceMarkerRecord.new(self, marker_data))

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
	if LOGGER:
		LOGGER.debug("Adding arrow marker to history (id: %d)" % [marker_data["id"]])
	_record_history(PlaceMarkerRecord.new(self, marker_data))

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

# ============================================================================
# API BRIDGE METHODS
# Called by GuidesLinesApi to avoid exposing inner HistoryRecord classes
# ============================================================================

# Place a marker from the external API (handles history recording internally)
func api_place_marker(marker_data: Dictionary) -> void:
	_do_place_marker(marker_data)
	next_id += 1
	_record_history(PlaceMarkerRecord.new(self, marker_data))

# Delete a marker by id from the external API (handles history recording internally)
# Returns true if the marker was found and deleted
func api_delete_marker_by_id(marker_id: int) -> bool:
	if not markers_lookup.has(marker_id):
		return false
	var marker = markers_lookup[marker_id]
	var index = markers.find(marker)
	if index == -1:
		return false
	var marker_data = marker.Save()
	_do_delete_marker(index)
	_record_history(DeleteMarkerRecord.new(self, marker_data, index))
	return true

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
	_record_history(DeleteAllMarkersRecord.new(self, saved_markers))

func _do_delete_all():
	markers = []
	markers_lookup = {} # Clear lookup
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("All markers deleted")
	# Notify external API listeners
	if parent_mod.guides_lines_api:
		parent_mod.guides_lines_api._notify_all_markers_deleted()

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
			_record_history(DeleteMarkerRecord.new(self, marker_data, i))
			return true  # Marker was deleted
	return false  # No marker found

func _do_delete_marker(index):
	if index < markers.size():
		var marker = markers[index]
		var deleted_id = marker.id
		# Clean up clipping relationships before removing
		_remove_shape_clipping(deleted_id)
		markers_lookup.erase(marker.id) # Remove from lookup
		markers.remove(index)
		update_ui()
		if overlay:
			overlay.update()
		if LOGGER:
			LOGGER.debug("Marker deleted at index %d" % [index])
		# Notify external API listeners
		if parent_mod.guides_lines_api:
			parent_mod.guides_lines_api._notify_marker_deleted(deleted_id)

func _undo_delete_marker(marker_data, index):
	var marker = GuideMarkerClass.new()
	marker.Load(marker_data)
	markers.insert(index, marker)
	markers_lookup[marker.id] = marker # Add to lookup
	if marker.id >= next_id:
		next_id = marker.id + 1
	# Reapply clipping relationships if the features are enabled
	if auto_clip_shapes and marker.marker_type == MARKER_TYPE_SHAPE:
		_apply_shape_clipping(marker)
	if cut_existing_shapes and marker.marker_type == MARKER_TYPE_SHAPE:
		_apply_cut_to_existing_shapes(marker)
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
		marker.set_property("shape_sides", marker_data.get("shape_sides", DEFAULT_SHAPE_SIDES))
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
	# Apply shape clipping if the feature is enabled
	if auto_clip_shapes and marker.marker_type == MARKER_TYPE_SHAPE:
		_apply_shape_clipping(marker)
	# Apply one-way cut to existing markers if the feature is enabled
	if cut_existing_shapes and marker.marker_type == MARKER_TYPE_SHAPE:
		_apply_cut_to_existing_shapes(marker)
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
	# Notify external API listeners
	if parent_mod.guides_lines_api:
		parent_mod.guides_lines_api._notify_marker_placed(marker_data["id"], marker_data["position"])

func _undo_place_marker(marker_id):
	# Optimized removal using Dictionary lookup
	if markers_lookup.has(marker_id):
		var marker = markers_lookup[marker_id]
		# Clean up clipping relationships contributed by this marker
		_remove_shape_clipping(marker_id)
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

# ============================================================================
# SHAPE CLIPPING (Clip Intersecting Shapes feature)
# ============================================================================

# Build a shape descriptor dict for GeometryUtils clip functions.
# Returns { shape_type, ... } or {} if not applicable.
func _get_shape_descriptor(marker, cell_size) -> Dictionary:
	marker.get_draw_data(null, cell_size)  # ensure cache is fresh
	return marker.get_base_descriptor()

## Build a shape descriptor using current tool settings at [pos].
## Creates a temporary marker (not added to the scene) so we can reuse
## get_draw_data / _get_shape_descriptor logic.
func _build_shape_descriptor_at(pos: Vector2) -> Dictionary:
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return {}
	var tmp = GuideMarkerClass.new()
	tmp.position         = pos
	tmp.marker_type      = MARKER_TYPE_SHAPE
	tmp.shape_subtype    = active_shape_subtype
	tmp.shape_radius     = active_shape_radius
	tmp.shape_angle      = active_shape_angle
	tmp.shape_sides      = active_shape_sides
	return _get_shape_descriptor(tmp, cell_size)

# Return true if the outlines of two shape descriptors actually intersect.
func _shapes_intersect(desc_a: Dictionary, desc_b: Dictionary) -> bool:
	if desc_a.empty() or desc_b.empty():
		return false
	if desc_a.shape_type == "poly" and desc_b.shape_type == "poly":
		var n = desc_a.points.size()
		var m = desc_b.points.size()
		for i in range(n):
			var a1 = desc_a.points[i]
			var a2 = desc_a.points[(i + 1) % n]
			for j in range(m):
				var b1 = desc_b.points[j]
				var b2 = desc_b.points[(j + 1) % m]
				if GeometryUtils.segment_segment_intersect(a1, a2, b1, b2) != null:
					return true
		return false
	elif desc_a.shape_type == "poly" and desc_b.shape_type == "circle":
		var n = desc_a.points.size()
		for i in range(n):
			var a1 = desc_a.points[i]
			var a2 = desc_a.points[(i + 1) % n]
			if GeometryUtils.segment_intersects_circle(a1, a2, desc_b.center, desc_b.radius).size() > 0:
				return true
		return false
	elif desc_a.shape_type == "circle" and desc_b.shape_type == "poly":
		return _shapes_intersect(desc_b, desc_a)
	elif desc_a.shape_type == "circle" and desc_b.shape_type == "circle":
		var d = desc_a.center.distance_to(desc_b.center)
		return d < desc_a.radius + desc_b.radius and d > abs(desc_a.radius - desc_b.radius)
	return false

# Return true if the two shapes have any overlapping area:
# edges intersect OR one shape is fully contained inside the other.
# Used by Difference mode (unlike clip/cut which require actual edge crossings).
func _shapes_overlap(desc_a: Dictionary, desc_b: Dictionary) -> bool:
	if _shapes_intersect(desc_a, desc_b):
		return true
	# Check containment: one representative point of A inside B or vice-versa
	var pt_a = _shape_sample_point(desc_a)
	var pt_b = _shape_sample_point(desc_b)
	if pt_a != null and _point_in_shape(pt_a, desc_b):
		return true
	if pt_b != null and _point_in_shape(pt_b, desc_a):
		return true
	return false

# Return a representative interior point for a shape descriptor (centroid).
func _shape_sample_point(desc: Dictionary):
	if desc.shape_type == "circle":
		return desc.center
	elif desc.shape_type == "poly" and desc.points.size() > 0:
		var sum = Vector2.ZERO
		for p in desc.points:
			sum += p
		return sum / desc.points.size()
	return null

# Return true if [pt] is strictly inside [desc] (boundary not counted).
func _point_in_shape(pt: Vector2, desc: Dictionary) -> bool:
	if desc.shape_type == "poly":
		return Geometry.is_point_in_polygon(pt, desc.points)
	elif desc.shape_type == "circle":
		return GeometryUtils.point_inside_circle(pt, desc.center, desc.radius)
	return false

# Recompute render_primitives for [marker] using its current clipped_by_ids list.
# Call this whenever the set of clippers changes.
func _recompute_marker_clip(marker, cell_size):
	if marker.marker_type != MARKER_TYPE_SHAPE:
		return
	if cell_size == null:
		return
	var self_desc = _get_shape_descriptor(marker, cell_size)
	if self_desc.empty():
		return
	# Build list of shape descriptors from current clippers that still exist
	var b_shapes = []
	for other_id in marker.clipped_by_ids:
		if markers_lookup.has(other_id):
			var other = markers_lookup[other_id]
			var d = _get_shape_descriptor(other, cell_size)
			if not d.empty():
				b_shapes.append(d)
	if b_shapes.empty():
		marker.set_render_primitives([], [])
		return
	if self_desc.shape_type == "poly":
		marker.set_render_primitives(GeometryUtils.clip_polygon_against_shapes(self_desc.points, b_shapes), [])
	elif self_desc.shape_type == "circle":
		marker.set_render_primitives(GeometryUtils.clip_circle_against_shapes(self_desc.center, self_desc.radius, b_shapes), [])

# Apply ONE-WAY cut when [new_marker] is placed: find all intersecting shape markers
# and register new_marker as their clipper — but NOT vice versa.
# The new marker itself is left untouched (its render_primitives stay empty).
func _apply_cut_to_existing_shapes(new_marker):
	if not cut_existing_shapes or new_marker.marker_type != MARKER_TYPE_SHAPE:
		return
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return
	var new_desc = _get_shape_descriptor(new_marker, cell_size)
	if new_desc.empty():
		return
	for other in markers:
		if other.id == new_marker.id or other.marker_type != MARKER_TYPE_SHAPE:
			continue
		var other_desc = _get_shape_descriptor(other, cell_size)
		if other_desc.empty():
			continue
		if not _shapes_intersect(new_desc, other_desc):
			continue
		# Register new_marker as clipper of other (one-way only)
		if not other.clipped_by_ids.has(new_marker.id):
			other.clipped_by_ids.append(new_marker.id)
			_recompute_marker_clip(other, cell_size)
	if overlay:
		overlay.update()

# Apply clipping when [new_marker] is placed: find all intersecting shape markers
# and register mutual clip relationships, then recompute both sides.
func _apply_shape_clipping(new_marker):
	if not auto_clip_shapes or new_marker.marker_type != MARKER_TYPE_SHAPE:
		return
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return
	var new_desc = _get_shape_descriptor(new_marker, cell_size)
	if new_desc.empty():
		return
	for other in markers:
		if other.id == new_marker.id or other.marker_type != MARKER_TYPE_SHAPE:
			continue
		var other_desc = _get_shape_descriptor(other, cell_size)
		if other_desc.empty():
			continue
		if not _shapes_intersect(new_desc, other_desc):
			continue
		# Register mutual relationship
		if not new_marker.clipped_by_ids.has(other.id):
			new_marker.clipped_by_ids.append(other.id)
		if not other.clipped_by_ids.has(new_marker.id):
			other.clipped_by_ids.append(new_marker.id)
		# Recompute clipping for both markers
		_recompute_marker_clip(new_marker, cell_size)
		_recompute_marker_clip(other, cell_size)
	if overlay:
		overlay.update()

# Remove clipping contributions of [removed_id] from all remaining markers
# and recompute their render_primitives.
func _remove_shape_clipping(removed_id):
	var cell_size = _get_grid_cell_size()
	for marker in markers:
		if marker.id == removed_id:
			continue
		if marker.marker_type != MARKER_TYPE_SHAPE:
			continue
		if marker.clipped_by_ids.has(removed_id):
			marker.clipped_by_ids.erase(removed_id)
			_recompute_marker_clip(marker, cell_size)

# ============================================================================
# DIFFERENCE MODE CORE
# ============================================================================

## Build in-memory descriptor from a serializable op dict.
func _desc_from_op(op: Dictionary) -> Dictionary:
	if op.shape_type == "poly":
		var pts = []
		for v in op.points:
			pts.append(Vector2(v[0], v[1]))
		return {"shape_type": "poly", "points": pts}
	else:  # circle
		return {"shape_type": "circle",
		        "center": Vector2(op.center[0], op.center[1]),
		        "radius": op.radius}

## Build serializable op dict from an in-memory descriptor.
func _op_from_desc(desc: Dictionary) -> Dictionary:
	if desc.shape_type == "poly":
		var pts = []
		for v in desc.points:
			pts.append([v.x, v.y])
		return {"shape_type": "poly", "points": pts}
	else:
		return {"shape_type": "circle",
		        "center": [desc.center.x, desc.center.y],
		        "radius": desc.radius}

## Snapshot clip state of all Shape markers that intersect diff_desc.
func _take_difference_snapshot(diff_desc: Dictionary) -> Dictionary:
	var snap = {}
	var cell_size = _get_grid_cell_size()
	for marker in markers:
		if marker.marker_type != MARKER_TYPE_SHAPE:
			continue
		var desc = _get_shape_descriptor(marker, cell_size)
		if desc.empty():
			continue
		if _shapes_overlap(desc, diff_desc):
			snap[marker.id] = {
				"render_primitives": marker.get_render_primitives().duplicate(true),
				"render_fills":      marker.get_render_fills().duplicate(true),
				"clipped_by_ids":    marker.clipped_by_ids.duplicate()
			}
	return snap

## Rebuild render_primitives for [marker] using only the difference_ops that were
## explicitly applied to it (tracked via op["applied_to"]).
## Always starts from the original marker geometry so multiple diffs compound.
func _rebuild_all_diffs_for_marker(marker, cell_size):
	var target_desc = _get_shape_descriptor(marker, cell_size)
	if target_desc.empty():
		return

	# Collect ops applied to this marker. For backward-compatibility, also
	# migrate ops whose applied_to is empty by doing a geometric overlap check.
	var affecting: Array = []
	for op in difference_ops:
		if op.get("applied_to", []).has(marker.id):
			affecting.append(_desc_from_op(op))
		elif not op.has("applied_to") or op["applied_to"].empty():
			# Legacy op with no tracking — check geometrically and migrate.
			var op_desc = _desc_from_op(op)
			if _shapes_overlap(target_desc, op_desc):
				if not op.has("applied_to"):
					op["applied_to"] = []
				op["applied_to"].append(marker.id)
				affecting.append(op_desc)

	if affecting.empty():
		marker.set_render_primitives([], [])
		return

	# Outer: marker outline OUTSIDE all its diffs simultaneously
	var outer = []
	if target_desc.shape_type == "poly":
		outer = GeometryUtils.clip_polygon_against_shapes(target_desc.points, affecting)
	elif target_desc.shape_type == "circle":
		outer = GeometryUtils.clip_circle_against_shapes(target_desc.center, target_desc.radius, affecting)

	# If outer covers the full shape (no actual edge was cut, e.g. all diffs are
	# inside), leave render_primitives empty so the fallback full-shape path is
	# used.  This prevents a redundant full-arc primitive from appearing in the
	# list alongside the fill lines.
	var all_inside = true
	for d in affecting:
		if _shapes_intersect(target_desc, d):
			all_inside = false
			break
	if all_inside:
		outer = []  # let fallback draw the full shape

	# Fill: each diff's outline INSIDE the marker, clipped against all OTHER diffs
	# so fill lines from earlier ops don't bleed into holes made by later ops.
	var fills = []
	for i in range(affecting.size()):
		var d = affecting[i]
		var raw_fill = []
		if d.shape_type == "poly":
			raw_fill = GeometryUtils.clip_polygon_inside_shape(d.points, target_desc)
		elif d.shape_type == "circle":
			raw_fill = GeometryUtils.clip_circle_inside_shape(d.center, d.radius, target_desc)
		# Remove portions that fall inside any other diff's hole
		var other_diffs = []
		for j in range(affecting.size()):
			if j != i:
				other_diffs.append(affecting[j])
		if not other_diffs.empty():
			raw_fill = GeometryUtils.clip_primitives_against_shapes(raw_fill, other_diffs)
		fills += raw_fill

	marker.set_render_primitives(outer, fills)

## Apply a Difference operation. Records which markers were affected in
## diff_op["applied_to"] so that subsequent rebuilds stay per-marker isolated.
func _do_apply_difference(diff_desc: Dictionary, diff_op: Dictionary):
	# Ensure the op has an applied_to list before registering
	if not diff_op.has("applied_to"):
		diff_op["applied_to"] = []
	if not difference_ops.has(diff_op):
		difference_ops.append(diff_op)

	var cell_size = _get_grid_cell_size()
	for marker in markers:
		if marker.marker_type != MARKER_TYPE_SHAPE:
			continue
		var target_desc = _get_shape_descriptor(marker, cell_size)
		if target_desc.empty():
			continue
		if not _shapes_overlap(target_desc, diff_desc):
			continue
		# Tag this marker as affected by this op, then rebuild from all its ops
		if not diff_op["applied_to"].has(marker.id):
			diff_op["applied_to"].append(marker.id)
		_rebuild_all_diffs_for_marker(marker, cell_size)

	if overlay:
		overlay.update()

## Serialize difference_ops for map save.
func save_difference_ops() -> Array:
	return difference_ops.duplicate(true)

## Restore difference_ops on map load and rebuild only the markers each op
## was applied to (per the saved applied_to lists).
func load_difference_ops(ops: Array):
	difference_ops = []
	for op in ops:
		difference_ops.append(op.duplicate(true))

	# Rebuild markers.  For legacy ops that have no applied_to tracking we
	# cannot know which markers were affected, so we fall back to rebuilding
	# all markers (the migration inside _rebuild_all_diffs_for_marker will
	# populate applied_to from a geometric check).
	var cell_size = _get_grid_cell_size()
	var has_legacy_ops = false
	var affected_ids    = {}
	for op in difference_ops:
		var a = op.get("applied_to", [])
		if a.empty():
			has_legacy_ops = true
		else:
			for id in a:
				affected_ids[id] = true
	for marker in markers:
		if has_legacy_ops or affected_ids.has(marker.id):
			_rebuild_all_diffs_for_marker(marker, cell_size)

	if overlay:
		overlay.update()

# ============================================================================
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
		active_shape_sides = DEFAULT_SHAPE_SIDES
		
		type_settings[MARKER_TYPE_SHAPE]["radius"] = DEFAULT_SHAPE_RADIUS
		type_settings[MARKER_TYPE_SHAPE]["subtype"] = DEFAULT_SHAPE_SUBTYPE
		type_settings[MARKER_TYPE_SHAPE]["angle"] = DEFAULT_SHAPE_ANGLE
		type_settings[MARKER_TYPE_SHAPE]["sides"] = DEFAULT_SHAPE_SIDES
		
		_update_shape_radius_spinbox()
		_update_shape_subtype_selector()
		_update_shape_angle_spinbox()
		_update_shape_sides_spinbox()
	
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

# Helper: set value on a named SpinBox inside the tool panel.
# node_name: the name used in find_node for the SpinBox
# value:     float value to assign
func _set_spinbox_value(node_name: String, value: float) -> void:
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node(node_name, true, false)
		if spinbox:
			spinbox.value = value

func _update_angle_spinbox():
	if LOGGER:
		LOGGER.debug("Updating AngleSpinBox: %.1f°" % [active_angle])
	_set_spinbox_value("AngleSpinBox", active_angle)

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
		
		# Show/hide sides row - only for Custom subtype
		var sides_row = shape_settings_container.find_node("SidesRow", true, false)
		if sides_row:
			sides_row.visible = (active_shape_subtype == SHAPE_CUSTOM)
		
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
	_set_spinbox_value("ShapeRadiusSpinBox", active_shape_radius)

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

func _on_shape_sides_changed(value):
	active_shape_sides = int(value)
	type_settings[MARKER_TYPE_SHAPE]["sides"] = active_shape_sides
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Shape sides changed to: %d" % [active_shape_sides])

func _on_auto_clip_shapes_toggled(enabled):
	auto_clip_shapes = enabled
	# Only one clip mode can be active at a time
	if enabled:
		if cut_existing_shapes:
			cut_existing_shapes = false
			_set_shape_checkbox("CutExistingShapesCheckbox", false)
		if difference_mode:
			difference_mode = false
			_set_shape_checkbox("DifferenceModeCheckbox", false)
	if LOGGER:
		LOGGER.info("Clip Intersecting Shapes: %s" % ["ON" if enabled else "OFF"])

func _on_cut_existing_shapes_toggled(enabled):
	cut_existing_shapes = enabled
	# Only one clip mode can be active at a time
	if enabled:
		if auto_clip_shapes:
			auto_clip_shapes = false
			_set_shape_checkbox("ClipIntersectingShapesCheckbox", false)
		if difference_mode:
			difference_mode = false
			_set_shape_checkbox("DifferenceModeCheckbox", false)
	if LOGGER:
		LOGGER.info("Cut Into Existing Shapes: %s" % ["ON" if enabled else "OFF"])

func _on_difference_mode_toggled(enabled):
	difference_mode = enabled
	# Only one mode can be active at a time
	if enabled:
		if auto_clip_shapes:
			auto_clip_shapes = false
			_set_shape_checkbox("ClipIntersectingShapesCheckbox", false)
		if cut_existing_shapes:
			cut_existing_shapes = false
			_set_shape_checkbox("CutExistingShapesCheckbox", false)
	if LOGGER:
		LOGGER.info("Difference Mode: %s" % ["ON" if enabled else "OFF"])

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

func _update_shape_sides_spinbox():
	if not tool_panel:
		return
	var container = tool_panel.Align.get_child(0)
	if container:
		var spinbox = container.find_node("ShapeSidesSpinBox", true, false)
		if spinbox:
			spinbox.value = active_shape_sides
		var sides_row = container.find_node("SidesRow", true, false)
		if sides_row:
			sides_row.visible = (active_shape_subtype == SHAPE_CUSTOM)

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
	_set_spinbox_value("ArrowHeadLengthSpinBox", active_arrow_head_length)

func _update_arrow_head_angle_spinbox():
	_set_spinbox_value("ArrowHeadAngleSpinBox", active_arrow_head_angle)

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
	subtype_option.add_item("Custom (N-sided)")
	subtype_option.set_item_metadata(5, SHAPE_CUSTOM)
	
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
	sides_spin.value = active_shape_sides
	sides_spin.name = "ShapeSidesSpinBox"
	sides_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides_spin.connect("value_changed", self, "_on_shape_sides_changed")
	sides_spin.allow_greater = false
	sides_spin.allow_lesser = false
	sides_hbox.add_child(sides_spin)
	container.add_child(sides_hbox)
	
	# Only show sides row for Custom subtype
	sides_hbox.visible = (active_shape_subtype == SHAPE_CUSTOM)

	container.add_child(_create_spacer(10))

	# Clip Intersecting Shapes toggle
	var clip_check = CheckButton.new()
	clip_check.text = "Clip Intersecting Shapes"
	clip_check.pressed = auto_clip_shapes
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
	cut_check.pressed = cut_existing_shapes
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
	diff_check.pressed = difference_mode
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
		active_shape_sides = settings.get("sides", DEFAULT_SHAPE_SIDES)
		
		# Update UI
		_update_shape_subtype_selector()
		_update_shape_radius_spinbox()
		_update_shape_angle_spinbox()
		_update_shape_sides_spinbox()
	
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
		type_settings[MARKER_TYPE_SHAPE]["sides"] = active_shape_sides
	
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

