extends Reference

class_name GuidesLinesRender

# ============================================================================
# CONSTANTS & STYLING
# ============================================================================

const OUTLINE_COLOR = Color(0, 0, 0, 0.8)
const TEXT_SCALE = 4.0 # For high-res text scaling
const STROKE_SIDE_INDICES = [0, 4, 1, 4, 5, 1, 1, 5, 2, 5, 6, 2, 2, 6, 3, 6, 7, 3]
const STROKE_INDICES = [0, 4, 1, 4, 5, 1, 1, 5, 2, 5, 6, 2, 2, 6, 3, 6, 7, 3,
	4, 8, 5, 8, 9, 5, 5, 9, 6, 9, 10, 6, 6, 10, 7, 10, 11, 7,
	8, 12, 9, 12, 13, 9, 9, 13, 10, 13, 14, 10, 10, 14, 11, 14, 15, 11]

# Transient render slots, in draw order. Owned by an overlay, never map data.
var _stroke_cache = []
var _stroke_index = 0

func begin_strokes() -> void:
	_stroke_index = 0

func end_strokes() -> void:
	_stroke_cache.resize(_stroke_index)

# ============================================================================
# DRAWING PRIMITIVES
# ============================================================================

# Calculates adaptive line width based on camera zoom
static func get_adaptive_width(base_width: float, time_scale: Vector2) -> float:
	var width = base_width
	var zoom_factor = time_scale.x
	
	# Apply scaling for small zoom levels (zoomed out)
	if zoom_factor > 1.0:
		# Linear scaling: width increases proportionally to zoom
		width = base_width * zoom_factor
	
	if width < 1.0: 
		width = 1.0 # Minimum 1px
		
	return width

# Draws a line with adaptive width
static func draw_adaptive_line(canvas: CanvasItem, start: Vector2, end: Vector2, color: Color, base_width: float, time_scale: Vector2):
	var width = get_adaptive_width(base_width, time_scale)
	canvas.draw_line(start, end, color, width)

# Draws text with a black outline
static func draw_text_with_outline(canvas: CanvasItem, text: String, position: Vector2, color: Color, font: Font = null):
	if font == null:
		return
	canvas.draw_set_transform(position, 0, Vector2(TEXT_SCALE, TEXT_SCALE))
	var offset_step = 2.0 / TEXT_SCALE
	for dx in [-offset_step, 0.0, offset_step]:
		for dy in [-offset_step, 0.0, offset_step]:
			if dx != 0.0 or dy != 0.0:
				canvas.draw_string(font, Vector2(dx, dy), text, OUTLINE_COLOR, -1)
	canvas.draw_string(font, Vector2.ZERO, text, color, -1)
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# Draws a closed outline; two vertices form one stroke rather than two overlaps.
func draw_polygon_outline(canvas: CanvasItem, vertices: Array, color: Color, width: float, offset: Vector2 = Vector2.ZERO):
	var count = vertices.size()
	if count > 1 and vertices[0] == vertices[count - 1]:
		count -= 1
	if count < 2:
		return
	var points = PoolVector2Array()
	var edges = count if count > 2 else 1
	points.resize(edges * 2)
	for i in range(edges):
		points[i * 2] = vertices[i]
		points[i * 2 + 1] = vertices[(i + 1) % count]
	draw_strokes(canvas, points, color, width, offset)

func draw_shape_segments(canvas: CanvasItem, primitives: Array, color: Color, width: float, offset: Vector2 = Vector2.ZERO, rotation: float = 0.0) -> void:
	var points = PoolVector2Array()
	points.resize(primitives.size() * 2)
	var count = 0
	for segment in primitives:
		if not segment is Dictionary or segment.get("type", "seg") != "seg":
			continue
		var a = segment.get("a")
		var b = segment.get("b")
		if not _finite_point(a) or not _finite_point(b):
			continue
		points[count] = a
		points[count + 1] = b
		count += 2
	points.resize(count)
	draw_strokes(canvas, points, color, width, offset, rotation)

func draw_path(canvas: CanvasItem, vertices: Array, closed: bool, head: Array, color: Color, width: float, offset: Vector2 = Vector2.ZERO) -> void:
	if vertices.size() < 2:
		return
	var close_edge = closed and vertices.size() > 2 and vertices.back() != vertices.front()
	var points = PoolVector2Array()
	points.resize((vertices.size() - 1 + int(close_edge) + head.size()) * 2)
	var count = 0
	for i in range(vertices.size() - 1):
		points[count] = vertices[i]
		points[count + 1] = vertices[i + 1]
		count += 2
	if close_edge:
		points[count] = vertices.back()
		points[count + 1] = vertices.front()
		count += 2
	for point in head:
		points[count] = vertices.back()
		points[count + 1] = point
		count += 2
	draw_strokes(canvas, points, color, width, offset)

func draw_strokes(canvas: CanvasItem, points: PoolVector2Array, color: Color, width: float, offset: Vector2 = Vector2.ZERO, rotation: float = 0.0) -> void:
	if points.empty() or width <= 0 or is_nan(width) or is_inf(width):
		return
	# Translation is a draw transform, so cursor/drag movement reuses the mesh.
	var origin = points[0]
	var local_points = PoolVector2Array()
	local_points.resize(points.size())
	for i in range(points.size()):
		local_points[i] = points[i] - origin
	var transform = Transform2D(rotation, origin.rotated(rotation) + offset)
	var basis = canvas.get_global_transform_with_canvas() if canvas.is_inside_tree() else Transform2D.IDENTITY
	basis.origin = Vector2.ZERO
	basis = basis * Transform2D(rotation, Vector2.ZERO)
	var state = [width, color, basis.x, basis.y]
	if _stroke_index == _stroke_cache.size():
		_stroke_cache.append({})
	var cached = _stroke_cache[_stroke_index]
	_stroke_index += 1
	# ponytail: compare local endpoints on redraw, O(segments), to catch in-place
	# boolean/API edits too. Use geometry revisions if redraw profiling warrants it.
	if cached.get("state") != state or cached.get("points") != local_points:
		cached["mesh"] = build_stroke_mesh(local_points, color, width, basis)
		cached["state"] = state
		cached["points"] = local_points
	if cached.mesh != null:
		# Vertex colors carry opacity; Godot 3 overrides mesh modulation with them.
		canvas.draw_mesh(cached.mesh, null, null, transform)

static func _finite_point(point) -> bool:
	return typeof(point) == TYPE_VECTOR2 and not (is_nan(point.x) or is_inf(point.x) or is_nan(point.y) or is_inf(point.y))

# One indexed surface for disconnected rectangles, with a one-screen-pixel alpha
# fringe on all four edges. No polyline bisectors, bridging, shader or texture.
# ponytail: independent rectangles retain butt joins and can overlap at translucent
# corners; joined-stroke tessellation is the upgrade if host testing requires it.
static func build_stroke_mesh(points: PoolVector2Array, color: Color, width: float, basis: Transform2D = Transform2D.IDENTITY):
	var determinant = abs(basis.x.cross(basis.y))
	if points.size() % 2 != 0 or width <= 0 or is_nan(width) or is_inf(width) or determinant <= 0 or is_nan(determinant) or is_inf(determinant):
		return null
	var vertices = PoolVector2Array()
	var colors = PoolColorArray()
	var indices = PoolIntArray()
	# Pool arrays do not expose reserve(); allocate once rather than growing for
	# every vertex/index during a large map's first draw or a zoom change.
	vertices.resize(points.size() * 8)
	colors.resize(points.size() * 8)
	indices.resize(points.size() * 27)
	var vertex_count = 0
	var index_count = 0
	var transparent = Color(color.r, color.g, color.b, 0.0)
	var endpoints = {}
	for i in range(0, points.size(), 2):
		if _finite_point(points[i]) and _finite_point(points[i + 1]) and points[i] != points[i + 1]:
			for point in [points[i], points[i + 1]]:
				endpoints[point] = endpoints.get(point, 0) + 1
	for i in range(0, points.size(), 2):
		var a = points[i]
		var b = points[i + 1]
		if not _finite_point(a) or not _finite_point(b):
			continue
		var length = a.distance_to(b)
		if length <= 0 or is_inf(length) or is_nan(length):
			continue
		var tangent = (b - a) / length
		var normal = tangent.tangent()
		# A displacement d along tangent separates cap edges by
		# d * abs(det(basis)) / length(basis * normal) screen pixels (and vice versa).
		var fringe_x = 0.5 * basis.basis_xform(normal).length() / determinant
		var fringe_y = 0.5 * basis.basis_xform(tangent).length() / determinant
		var half_x = length * 0.5
		var half_y = width * 0.5
		var start_cap = endpoints.get(a, 0) == 1
		var end_cap = endpoints.get(b, 0) == 1
		# Internal joins must not fade twice: adjacent translucent strokes would
		# otherwise leave a darker seam at every short spiral segment.
		var xs = [-half_x - fringe_x if start_cap else -half_x,
			-abs(half_x - fringe_x) if start_cap else -half_x,
			abs(half_x - fringe_x) if end_cap else half_x,
			half_x + fringe_x if end_cap else half_x]
		var peak_x = 1.0
		if start_cap and end_cap:
			peak_x = min(1.0, half_x / fringe_x)
		elif start_cap:
			xs[1] = min(-half_x + fringe_x, half_x)
			peak_x = min(1.0, (length + fringe_x) / (2.0 * fringe_x))
		elif end_cap:
			xs[2] = max(half_x - fringe_x, -half_x)
			peak_x = min(1.0, (length + fringe_x) / (2.0 * fringe_x))
		var ys = [-half_y - fringe_y, -abs(half_y - fringe_y), abs(half_y - fringe_y), half_y + fringe_y]
		var peak = peak_x * min(1.0, half_y / fringe_y)
		var center = a * 0.5 + b * 0.5
		var first = vertex_count
		var solid = Color(color.r, color.g, color.b, color.a * peak)
		var offsets = [normal * ys[0], normal * ys[1], normal * ys[2], normal * ys[3]]
		# Closed contours need only the two side-fringe rows. Add cap rows only
		# at exposed fragment endpoints, avoiding degenerate triangles on spirals.
		var has_caps = start_cap or end_cap
		for x in ([0, 1, 2, 3] if has_caps else [1, 2]):
			var row = center + tangent * xs[x]
			var inside_x = (x > 0 and x < 3) or (x == 0 and not start_cap) or (x == 3 and not end_cap)
			for y in range(4):
				vertices[vertex_count] = row + offsets[y]
				colors[vertex_count] = solid if inside_x and y > 0 and y < 3 else transparent
				vertex_count += 1
		for index in (STROKE_INDICES if has_caps else STROKE_SIDE_INDICES):
			indices[index_count] = first + index
			index_count += 1
	if vertex_count == 0:
		return null
	vertices.resize(vertex_count)
	colors.resize(vertex_count)
	indices.resize(index_count)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	# Disable vertex compression: its quantization can change stroke width.
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], 0)
	return mesh
