extends Reference

# GuideMarker - Simple data class for guide markers
# Stored and managed by GuidesLinesTool

var position = Vector2.ZERO
var marker_types = []  # Array of strings: can contain "vertical", "horizontal", or both
var id = -1  # Unique identifier
var show_coordinates = false  # Show grid coordinates on marker lines

const MARKER_SIZE = 40.0  # Doubled size
const MARKER_COLOR = Color(1, 0, 0, 1)  # Red
const LINE_COLOR = Color(0, 0.7, 1, 1)  # Blue (fully opaque)
const LINE_WIDTH = 10.0  # Thicker lines

# Initialize marker with position and guide line types
func _init(pos = Vector2.ZERO, types = [], coords = false):
	position = pos
	marker_types = types if types else []
	show_coordinates = coords

# Check if marker has a specific guide line type
func has_type(type):
	return marker_types.has(type)

# Add a guide line type to this marker
func add_type(type):
	if not has_type(type):
		marker_types.append(type)

# Remove a guide line type from this marker
func remove_type(type):
	marker_types.erase(type)

# Get bounding rectangle for marker selection
func get_rect():
	var half_size = MARKER_SIZE * 0.5
	return Rect2(position - Vector2(half_size, half_size), Vector2(MARKER_SIZE, MARKER_SIZE))

# Check if a point is within marker's clickable area
func is_point_inside(point, threshold = MARKER_SIZE):
	return position.distance_to(point) < threshold

# Serialize marker data for saving to map file
func Save():
	return {
		"position": [position.x, position.y],
		"marker_types": marker_types.duplicate(),
		"id": id,
		"show_coordinates": show_coordinates
	}

# Deserialize marker data from map file
# Includes backward compatibility with older single-type format
func Load(data):
	if data.has("position"):
		position = Vector2(data.position[0], data.position[1])
	if data.has("marker_types"):
		marker_types = data.marker_types.duplicate()
	elif data.has("marker_type"):  # Backward compatibility with older format
		# Convert old "both"/"vertical"/"horizontal" to array
		var old_type = data.marker_type
		marker_types = []
		if old_type == "both" or old_type == "vertical":
			marker_types.append("vertical")
		if old_type == "both" or old_type == "horizontal":
			marker_types.append("horizontal")
	if data.has("id"):
		id = data.id
	if data.has("show_coordinates"):
		show_coordinates = data.show_coordinates
	else:
		show_coordinates = false  # Default for old saves
