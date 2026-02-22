extends Reference

# GuidesLinesTool - Tool for managing guide markers
# Stores markers internally and draws them via overlay

const CLASS_NAME = "GuidesLinesTool"
const GeometryUtils = preload("../utils/GeometryUtils.gd")
const GuidesLinesHistory = preload("GuidesLinesHistory.gd")
const GuidesLinesToolUI = preload("GuidesLinesToolUI.gd")
const GuidesLinesPlacement = preload("GuidesLinesPlacement.gd")

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

# Shape preset labels (UI-only вЂ” used to set initial sides/angle when a preset is selected)
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
var active_shape_angle = 0.0  # Shape rotation angle in degrees
var active_shape_sides = 64  # Number of polygon sides (default: Circle = 64)
var active_path_end_arrow = false  # Draw arrowhead at last point of path
var active_arrow_head_length = 50.0  # Arrow head length in pixels
var active_arrow_head_angle = 30.0  # Arrow head angle in degrees
var active_color = Color(0, 0.7, 1, 1)
var active_mirror = false
var auto_clip_shapes = false  # Clip intersecting shape markers on placement (mutual)
var cut_existing_shapes = false  # Cut lines of existing markers inside the new shape (one-way)
var difference_mode = false  # Difference mode вЂ” don't place new shape; fill overlap into existing markers
var difference_ops = []  # Array of serializable op dicts; replayed on map load

# Type-specific settings storage (each type stores its own parameters)
var type_settings = {
	"Line": {
		"angle": 0.0,
		"mirror": false
	},
	"Shape": {
		"radius": 1.0,
		"angle": 0.0,
		"sides": 64
	},
	"Path": {
		"end_arrow": false,
		"head_length": 50.0,
		"head_angle": 30.0
	}
}

# Default values
const DEFAULT_ANGLE = 0.0
const DEFAULT_SHAPE_RADIUS = 1.0
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
var ui = null  # GuidesLinesToolUI instance
var placement = null  # GuidesLinesPlacement instance

# Path placement state
var path_placement_active = false  # Whether we're in path placement mode
var path_temp_points = []  # Temporary storage for points being placed
var path_preview_point = null  # Current mouse position for line preview


# Initialize tool with reference to parent mod
func _init(mod):
	parent_mod = mod
	# Note: LOGGER will be set by parent mod after initialization
	ui = GuidesLinesToolUI.new(self)
	placement = GuidesLinesPlacement.new(self)

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

	# Difference mode: don't place a marker вЂ” instead apply difference to existing shapes
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
		_record_history(GuidesLinesHistory.DifferenceRecord.new(self, diff_desc, diff_op, snap))
		return
	
	# Apply grid snapping if enabled globally
	var final_pos = pos
	if parent_mod.Global.Editor.IsSnapping:
		final_pos = snap_position_to_grid(pos)
	
	var marker_data = {
		"position": final_pos,
		"marker_type": active_marker_type,
		"color": active_color,
		"coordinates": show_coordinates if active_marker_type == MARKER_TYPE_LINE else false,
		"id": next_id
	}
	
	# Add type-specific parameters
	if active_marker_type == MARKER_TYPE_LINE:
		marker_data["angle"] = active_angle
		marker_data["mirror"] = active_mirror
	elif active_marker_type == MARKER_TYPE_SHAPE:
		marker_data["shape_radius"] = active_shape_radius
		marker_data["shape_angle"] = active_shape_angle
		marker_data["shape_sides"] = active_shape_sides
	
	# Snapshot primitives of markers that would be clipped BEFORE placement,
	# so PlaceMarkerRecord can restore them on undo.
	var clip_snaps = {}
	if active_marker_type == MARKER_TYPE_SHAPE and (auto_clip_shapes or cut_existing_shapes):
		clip_snaps = _snapshot_potential_clip_targets(final_pos)

	# Execute the action first
	_do_place_marker(marker_data)
	next_id += 1
	
	# Then add to history if available
	if LOGGER:
		LOGGER.debug("Adding marker placement to history (id: %d)" % [marker_data["id"]])
	_record_history(GuidesLinesHistory.PlaceMarkerRecord.new(self, marker_data, clip_snaps))


# ============================================================================
# MULTI-POINT PLACEMENT (delegates to GuidesLinesPlacement)
# ============================================================================

func _handle_path_placement(pos): placement.handle_path_placement(pos)
func _finalize_path_marker(closed): placement.finalize_path_marker(closed)
func _cancel_path_placement(): placement.cancel_path_placement()

# ============================================================================
# API BRIDGE METHODS
# Called by GuidesLinesApi to avoid exposing inner HistoryRecord classes
# ============================================================================

# Place a marker from the external API (handles history recording internally)
func api_place_marker(marker_data: Dictionary) -> void:
	var clip_snaps = {}
	if marker_data.get("marker_type") == MARKER_TYPE_SHAPE and (auto_clip_shapes or cut_existing_shapes):
		clip_snaps = _snapshot_potential_clip_targets(marker_data["position"])
	_do_place_marker(marker_data)
	next_id += 1
	_record_history(GuidesLinesHistory.PlaceMarkerRecord.new(self, marker_data, clip_snaps))

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
	_record_history(GuidesLinesHistory.DeleteMarkerRecord.new(self, marker_data, index))
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
	_record_history(GuidesLinesHistory.DeleteAllMarkersRecord.new(self, saved_markers))

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
			_record_history(GuidesLinesHistory.DeleteMarkerRecord.new(self, marker_data, i))
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
		marker.set_property("path_end_arrow", marker_data.get("path_end_arrow", false))
		if marker_data.get("path_end_arrow", false):
			marker.set_property("arrow_head_length", marker_data.get("arrow_head_length", 50.0))
			marker.set_property("arrow_head_angle", marker_data.get("arrow_head_angle", 30.0))
	
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
			LOGGER.debug("Line marker placed at %s (angle: %.1fВ°, mirror: %s)" % [
				str(marker_data["position"]),
				marker_data.get("angle", 0.0),
				str(marker_data.get("mirror", false))
			])
		elif marker_data["marker_type"] == MARKER_TYPE_SHAPE:
			LOGGER.debug("Shape marker placed at %s (sides: %d, radius: %.1f cells)" % [
				str(marker_data["position"]),
				marker_data["shape_sides"],
				marker_data["shape_radius"]
			])
		elif marker_data["marker_type"] == MARKER_TYPE_PATH:
			LOGGER.debug("Path marker placed with %d points (closed: %s, end_arrow: %s)" % [
				marker_data["marker_points"].size(),
				str(marker_data["path_closed"]),
				str(marker_data.get("path_end_arrow", false))
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
	if ui:
		ui.update_ui_checkboxes_state()

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
# Computes polygon vertices directly from marker parameters вЂ” does NOT rely on
# cached_draw_data["points"] (which is no longer stored).
# Also calls get_draw_data() to ensure the marker's primitives are initialised.
# Returns { shape_type, points } or {} if not applicable.
func _get_shape_descriptor(marker, cell_size) -> Dictionary:
	if marker.marker_type != MARKER_TYPE_SHAPE:
		return {}
	# Ensure primitives are initialised for fresh markers.
	marker.get_draw_data(null, cell_size)
	var radius_px = marker.shape_radius * min(cell_size.x, cell_size.y)
	var angle_rad = deg2rad(marker.shape_angle)
	var pts = GeometryUtils.calculate_shape_vertices(
		marker.position, radius_px, marker.shape_sides, angle_rad)
	return {"shape_type": "poly", "points": pts}

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
	if desc.shape_type == "poly" and desc.points.size() > 0:
		var sum = Vector2.ZERO
		for p in desc.points:
			sum += p
		return sum / desc.points.size()
	return null

# Return true if [pt] is strictly inside [desc] (boundary not counted).
func _point_in_shape(pt: Vector2, desc: Dictionary) -> bool:
	if desc.shape_type == "poly":
		return Geometry.is_point_in_polygon(pt, desc.points)
	return false


# Apply ONE-WAY cut when [new_marker] is placed: clip the primitives of every
# intersecting Shape marker using new_markerвЂ™s shape boundary.
# The new marker itself keeps its full unclipped outline.
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
		# Apply cut directly to other's current outline.
		other.set_primitives(
			GeometryUtils.clip_primitives_against_shapes(
				other.get_primitives(), [new_desc]))
	if overlay:
		overlay.update()

# Apply mutual clipping when [new_marker] is placed: clip each intersecting
# Shape markerвЂ™s current primitives against the otherвЂ™s boundary.
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
		# Clip existing marker's outline by new_marker.
		other.set_primitives(
			GeometryUtils.clip_primitives_against_shapes(
				other.get_primitives(), [new_desc]))
		# Clip new_marker's outline by the existing marker.
		new_marker.set_primitives(
			GeometryUtils.clip_primitives_against_shapes(
				new_marker.get_primitives(), [other_desc]))
	if overlay:
		overlay.update()

# Clip / Cut relationships are reflected directly in primitives.
# This function is kept as a no-op hook in case future logic needs it.
func _remove_shape_clipping(_removed_id):
	pass

# ============================================================================
# DIFFERENCE MODE CORE
# ============================================================================

## Build in-memory descriptor from a serializable op dict.
func _desc_from_op(op: Dictionary) -> Dictionary:
	var pts = []
	for v in op.points:
		pts.append(Vector2(v[0], v[1]))
	return {"shape_type": "poly", "points": pts}

## Build serializable op dict from an in-memory descriptor.
func _op_from_desc(desc: Dictionary) -> Dictionary:
	var pts = []
	for v in desc.points:
		pts.append([v.x, v.y])
	return {"shape_type": "poly", "points": pts}

## Snapshot primitives of all Shape markers that intersect diff_desc.
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
				"primitives": marker.get_primitives().duplicate(true)
			}
	return snap

## Apply a Difference operation directly to each affected marker's current
## primitives (no rebuild from original polygon).
## Outline segments inside the diff area are replaced by the diff boundary.
func _do_apply_difference(diff_desc: Dictionary, diff_op: Dictionary):
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

		# Record which marker this op was applied to.
		if not diff_op["applied_to"].has(marker.id):
			diff_op["applied_to"].append(marker.id)

		# Clip the current outline: keep segments OUTSIDE the diff shape.
		# Append the diff boundary (inside the marker) to the same list.
		var diff_boundary = GeometryUtils.clip_polygon_inside_shape(
			diff_desc.points, target_desc)
		marker.set_primitives(
			GeometryUtils.clip_primitives_against_shapes(
				marker.get_primitives(), [diff_desc]) + diff_boundary)

	if overlay:
		overlay.update()

## Snapshot primitives of all Shape markers that would be affected
## by a new Clip / Cut shape placed at [pos] with the current active settings.
## Call this BEFORE _do_place_marker so the snapshot captures pre-clip state.
func _snapshot_potential_clip_targets(pos: Vector2) -> Dictionary:
	var snap = {}
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return snap
	var new_desc = _build_shape_descriptor_at(pos)
	if new_desc.empty():
		return snap
	for marker in markers:
		if marker.marker_type != MARKER_TYPE_SHAPE:
			continue
		var other_desc = _get_shape_descriptor(marker, cell_size)
		if _shapes_intersect(new_desc, other_desc):
			snap[marker.id] = {
				"primitives": marker.get_primitives().duplicate(true)
			}
	return snap


# ============================================================================
# Update tool panel UI with current state
func update_ui():
	if ui:
		ui.update_ui()

# ============================================================================
# UI PANEL AND CONTROLS (delegates to GuidesLinesToolUI)
# ============================================================================

# Create the UI panel for the tool with all controls
func create_ui_panel():
	if ui:
		ui.create_ui_panel()

# Adjust angle using mouse wheel (Line type)
func adjust_angle_with_wheel(direction):
	if ui:
		ui.adjust_angle_with_wheel(direction)

# Adjust shape radius using mouse wheel (Shape type)
func adjust_shape_radius_with_wheel(direction):
	if ui:
		ui.adjust_shape_radius_with_wheel(direction)

# Adjust shape angle using mouse wheel (Shape type)
func adjust_shape_angle_with_wheel(direction):
	if ui:
		ui.adjust_shape_angle_with_wheel(direction)

# Rotate shape by 45 degrees via RMB shortcut
func rotate_shape_45():
	if ui:
		ui.rotate_shape_45()
