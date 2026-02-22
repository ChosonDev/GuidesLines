extends Reference

const GeometryUtils = preload("../utils/GeometryUtils.gd")

# GuideMarker - Simple data class for guide markers
# Stored and managed by GuidesLinesTool

var position = Vector2.ZERO
var marker_type = "Line"  # Type of marker (Line, Shape, Path)
var angle = 0.0  # Line angle in degrees (0-360) [Line only]
var shape_radius = 1.0  # Shape radius in grid cells (circumradius) [Shape only]
var shape_angle = 0.0  # Shape rotation angle in degrees (0-360) [Shape only]
var shape_sides = 6  # Number of polygon sides [Shape only]
var marker_points = []  # Array of Vector2 points [Shape vertices/Path points]
var path_closed = false  # Whether path is closed (loop) [Path only]
var path_end_arrow = false  # Draw arrowhead at the last path point [Path only]
var arrow_head_length = 50.0  # Arrowhead length in pixels [Path only, when path_end_arrow]
var arrow_head_angle = 30.0  # Arrowhead angle in degrees [Path only, when path_end_arrow]
var color = Color(0, 0.7, 1, 1)  # Line/Shape/Path/Arrow color
var mirror = false  # Mirror line at 180 degrees [Line only]
var id = -1  # Unique identifier
var show_coordinates = false  # Show grid coordinates on marker lines/shapes/paths/arrows

const MARKER_SIZE = 10.0  # Doubled size
const MARKER_COLOR = Color(1, 0, 0, 1)  # Red
const DEFAULT_LINE_COLOR = Color(0, 0.7, 1, 1)  # Blue (fully opaque)
const LINE_WIDTH = 5.0  # Thicker lines

# CACHED GEOMETRY — single source of truth for all current geometric data.
# Structure for Shape:
#   "type":        "shape"
#   "shape_type":  "poly"
#
#   "primitives":  Array[{"type":"seg","a":V2,"b":V2}]
#     The ONLY authoritative list of segments — outline AND all Difference boundary
#     segments mixed together.  Set once on fresh placement (full polygon edges)
#     and then modified IN-PLACE by each Clip / Cut / Difference op.
#     Never rebuilt from original parameters — use undo snapshots to revert.
var cached_draw_data = {}
var _dirty = true

# Initialize marker with position and type-specific parameters
func _init(pos = Vector2.ZERO, _angle = 0.0, _mirror = false, coords = false):
	position = pos
	angle = _angle
	shape_radius = 1.0  # Default Shape radius
	shape_angle = 0.0  # Default Shape angle
	shape_sides = 6  # Default sides
	mirror = _mirror
	show_coordinates = coords
	color = DEFAULT_LINE_COLOR
	_dirty = true

# Set a property and mark geometry as dirty if needed
func set_property(prop, value):
	var changed = false
	match prop:
		"angle": 
			if angle != value: angle = value; changed = true
		"shape_radius":
			if shape_radius != value: shape_radius = value; changed = true
		"shape_angle":
			if shape_angle != value: shape_angle = value; changed = true
		"shape_sides":
			if shape_sides != value: shape_sides = value; changed = true
		"position":
			if position != value: position = value; changed = true
		"mirror":
			if mirror != value: mirror = value; changed = true
		"marker_type":
			if marker_type != value: marker_type = value; changed = true
		"path_closed":
			if path_closed != value: path_closed = value; changed = true
		"arrow_head_length":
			if arrow_head_length != value: arrow_head_length = value; changed = true
		"arrow_head_angle":
			if arrow_head_angle != value: arrow_head_angle = value; changed = true
		"path_end_arrow":
			if path_end_arrow != value: path_end_arrow = value; changed = true
		"show_coordinates":
			if show_coordinates != value: show_coordinates = value; changed = true
		"marker_points":
			# Arrays are passed by reference, so we assume it changed if set
			marker_points = value; changed = true
	
	if changed:
		_dirty = true

# Generate geometry data based on current settings
# map_rect: Rectangle of the map (used for infinite line clipping)
# cell_size: Vector2 of grid cell size (used for shape scaling)
func get_draw_data(map_rect, cell_size):
	if _dirty or cached_draw_data.empty():
		_recalculate_geometry(map_rect, cell_size)
	return cached_draw_data

## Reset to the full unclipped outline.
## Clears Clip/Cut/Difference state; the next get_draw_data() rebuilds primitives
## from shape parameters (because saved_primitives is now empty).
func clear_clip():
	cached_draw_data["primitives"] = []
	_dirty = true

## Set the current segments (outline + diff fills merged into one list).
## Called by GuidesLinesTool after any Clip / Cut / Difference operation.
func set_primitives(segs: Array):
	cached_draw_data["primitives"] = segs

## Get the current segments.
func get_primitives() -> Array:
	return cached_draw_data.get("primitives", [])

func _recalculate_geometry(map_rect, cell_size):
	# Preserve primitives across recalculation so Clip/Cut/Difference results
	# survive unrelated property changes (e.g. colour, show_coordinates).
	# Empty saved_primitives means this is a fresh (unmodified) shape.
	var saved_primitives = cached_draw_data.get("primitives", [])
	cached_draw_data = {}

	if marker_type == "Line" and map_rect != null:
		cached_draw_data["type"] = "line"
		cached_draw_data["segments"] = []
		
		var angles_list = [angle]
		if mirror: angles_list.append(fmod(angle + 180.0, 360.0))
		
		for ang in angles_list:
			var dir = Vector2(cos(deg2rad(ang)), sin(deg2rad(ang)))
			var segment = GeometryUtils.get_ray_to_rect_edge(position, dir, map_rect)
			if segment:
				cached_draw_data["segments"].append(segment)

	elif marker_type == "Shape":
		cached_draw_data["type"]       = "shape"
		cached_draw_data["shape_type"] = "poly"
		if cell_size:
			if saved_primitives.size() > 0:
				# Restore previously modified state (Clip / Cut / Difference applied).
				cached_draw_data["primitives"] = saved_primitives
			else:
				# Fresh shape — build full polygon outline from parameters.
				var radius_px = shape_radius * min(cell_size.x, cell_size.y)
				var angle_rad = deg2rad(shape_angle)
				var pts = GeometryUtils.calculate_shape_vertices(position, radius_px, shape_sides, angle_rad)
				cached_draw_data["primitives"] = GeometryUtils.points_to_segs(pts)
		else:
			# cell_size unavailable — preserve whatever state existed.
			cached_draw_data["primitives"] = saved_primitives
	_dirty = false

# Get bounding rectangle for marker selection
func get_rect():
	var half_size = MARKER_SIZE * 0.5
	return Rect2(position - Vector2(half_size, half_size), Vector2(MARKER_SIZE, MARKER_SIZE))

# Check if a point is within marker's clickable area
func is_point_inside(point, threshold = MARKER_SIZE):
	return position.distance_to(point) < threshold

# Serialize marker data for saving to map file
func Save():
	var data = {
		"position": [position.x, position.y],
		"marker_type": marker_type,
		"color": "#" + color.to_html(),
		"id": id,
		"show_coordinates": show_coordinates
	}
	
	# Add type-specific parameters
	if marker_type == "Line":
		data["angle"] = angle
		data["mirror"] = mirror
	elif marker_type == "Shape":
		data["shape_radius"] = shape_radius
		data["shape_angle"] = shape_angle
		data["shape_sides"] = shape_sides
		# Shape vertices are NOT saved — they are recomputed on load from the parameters above
	elif marker_type == "Path":
		# Serialize path points
		var points_data = []
		for point in marker_points:
			points_data.append([point.x, point.y])
		data["marker_points"] = points_data
		data["path_closed"] = path_closed
		data["path_end_arrow"] = path_end_arrow
		if path_end_arrow:
			data["arrow_head_length"] = arrow_head_length
			data["arrow_head_angle"] = arrow_head_angle
	
	return data

# Deserialize marker data from map file (current format only)
func Load(data):
	if data.has("position"):
		position = Vector2(data.position[0], data.position[1])
	
	if data.has("marker_type"):
		marker_type = data.marker_type
	else:
		marker_type = "Line"
	
	# Load type-specific parameters
	if marker_type == "Line":
		if data.has("angle"):
			angle = data.angle
		else:
			angle = 0.0
		
		if data.has("mirror"):
			mirror = data.mirror
		else:
			mirror = false
	elif marker_type == "Shape":
		shape_radius  = data.get("shape_radius", 1.0)
		shape_angle   = data.get("shape_angle", 0.0)
		shape_sides   = data.get("shape_sides", 6)
		# marker_points are not used for Shape — vertices are recomputed from the parameters above
		marker_points = []
	elif marker_type == "Path":
		if data.has("marker_points"):
			marker_points = []
			for point_data in data.marker_points:
				marker_points.append(Vector2(point_data[0], point_data[1]))
		else:
			marker_points = []
		
		path_closed = data.get("path_closed", false)
		path_end_arrow = data.get("path_end_arrow", false)
		if path_end_arrow:
			arrow_head_length = data.get("arrow_head_length", 50.0)
			arrow_head_angle = data.get("arrow_head_angle", 30.0)
	
	# Common parameters
	if data.has("color"):
		if data.color is String:
			color = Color(data.color.lstrip("#"))
		else:
			color = data.color
	else:
		color = DEFAULT_LINE_COLOR
	
	if data.has("id"):
		id = data.id
	else:
		id = -1
	
	if data.has("show_coordinates"):
		show_coordinates = data.show_coordinates
	else:
		show_coordinates = false		
	_dirty = true # Invalidate cache after loading