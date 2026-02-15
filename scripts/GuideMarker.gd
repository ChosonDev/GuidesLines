extends Reference

# GuideMarker - Simple data class for guide markers
# Stored and managed by GuidesLinesTool

var position = Vector2.ZERO
var marker_type = "Line"  # Type of marker (Line, Circle, Path)
var angle = 0.0  # Line angle in degrees (0-360) [Line only]
var line_range = 0.0  # Line length in grid cells (0 = infinite) [Line only]
var circle_radius = 1.0  # Circle radius in grid cells [Circle only]
var path_points = []  # Array of Vector2 points [Path only]
var path_closed = false  # Whether path is closed (loop) [Path only]
var color = Color(0, 0.7, 1, 1)  # Line/Circle/Path color
var mirror = false  # Mirror line at 180 degrees [Line only]
var id = -1  # Unique identifier
var show_coordinates = false  # Show grid coordinates on marker lines/circles/paths

const MARKER_SIZE = 40.0  # Doubled size
const MARKER_COLOR = Color(1, 0, 0, 1)  # Red
const DEFAULT_LINE_COLOR = Color(0, 0.7, 1, 1)  # Blue (fully opaque)
const LINE_WIDTH = 10.0  # Thicker lines

# Initialize marker with position and type-specific parameters
func _init(pos = Vector2.ZERO, _angle = 0.0, _range = 0.0, _mirror = false, coords = false):
	position = pos
	angle = _angle
	line_range = _range
	circle_radius = 1.0  # Default Circle radius
	mirror = _mirror
	show_coordinates = coords
	color = DEFAULT_LINE_COLOR

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
		data["line_range"] = line_range
		data["mirror"] = mirror
	elif marker_type == "Circle":
		data["circle_radius"] = circle_radius
	elif marker_type == "Path":
		# Serialize path points
		var points_data = []
		for point in path_points:
			points_data.append([point.x, point.y])
		data["path_points"] = points_data
		data["path_closed"] = path_closed
	
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
		
		if data.has("line_range"):
			line_range = data.line_range
		else:
			line_range = 0.0
		
		if data.has("mirror"):
			mirror = data.mirror
		else:
			mirror = false
	elif marker_type == "Circle":
		if data.has("circle_radius"):
			circle_radius = data.circle_radius
		else:
			circle_radius = 1.0
	elif marker_type == "Path":
		if data.has("path_points"):
			path_points = []
			for point_data in data.path_points:
				path_points.append(Vector2(point_data[0], point_data[1]))
		else:
			path_points = []
		
		if data.has("path_closed"):
			path_closed = data.path_closed
		else:
			path_closed = false
	
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
