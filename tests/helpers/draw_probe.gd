extends Node2D

# Records original render commands without requiring a Dungeondraft viewport.
var lines = []
var native_lines = []
var meshes = []
var polylines = []
var circles = []
var arcs = []
var strings = []
var transforms = []
var draw_transform = Transform2D.IDENTITY
var redraws = 0
var viewport_rect = Rect2(0, 0, 800, 600)
var custom_snap_enabled = true
var snap_interval = Vector2(10, 10)
var snap_offset = Vector2.ZERO
var active_geometry = 0
var radial_mode_to_corner = true

func update():
	redraws += 1

func get_viewport_rect():
	return viewport_rect

func get_snapped_position(point):
	return ((point - snap_offset) / snap_interval).snapped(Vector2.ONE) * snap_interval + snap_offset

func draw_set_transform(offset, rotation = 0.0, scale = Vector2.ONE):
	draw_transform = Transform2D(rotation, offset).scaled(scale)
	# CanvasItem scales local coordinates, not the translation itself.
	draw_transform.origin = offset
	transforms.append(draw_transform)

func draw_line(from, to, color, width = 1.0, _antialiased = false):
	var line = {"a": draw_transform.xform(from), "b": draw_transform.xform(to), "color": color, "width": width, "antialiased": _antialiased}
	lines.append(line)
	native_lines.append(line)

func draw_polyline(points, color, width = 1.0, _antialiased = false):
	polylines.append(points)
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, width)

func draw_circle(pos, radius, color):
	circles.append({"pos": pos, "radius": radius, "color": color})

func draw_arc(pos, radius, _start, _end, _count, color, width = 1.0, _antialiased = false):
	arcs.append({"pos": pos, "radius": radius, "color": color, "width": width})

func draw_string(_font: Font, pos: Vector2, text: String, color: Color = Color(1, 1, 1, 1), _clip: int = -1) -> void:
	strings.append({"pos": draw_transform.xform(pos), "text": text, "color": color})

# Decode the actual rectangle rows, retaining logical edges for geometry tests.
func draw_mesh(mesh, _texture = null, _normal = null, transform = Transform2D.IDENTITY, _modulate = Color.white):
	meshes.append(mesh)
	var arrays = mesh.surface_get_arrays(0)
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	var colors = arrays[Mesh.ARRAY_COLOR]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var cursor = 0
	while cursor < indices.size():
		var base = indices[cursor]
		var caps = cursor + 18 < indices.size() and indices[cursor + 18] == base + 4
		var a = (vertices[base] + vertices[base + 3]) * 0.5
		var b = (vertices[base + 4] + vertices[base + 7]) * 0.5
		if caps:
			b = (vertices[base + 12] + vertices[base + 15]) * 0.5
			var tangent = (b - a).normalized()
			var basis = get_global_transform_with_canvas() if is_inside_tree() else Transform2D.IDENTITY
			basis.origin = Vector2.ZERO
			var rotation = transform.get_rotation()
			basis = basis * Transform2D(rotation, Vector2.ZERO)
			var fringe = 0.5 * basis.basis_xform(tangent.tangent()).length() / abs(basis.x.cross(basis.y))
			if colors[base + 1].a == 0.0:
				a += tangent * fringe
			if colors[base + 13].a == 0.0:
				b -= tangent * fringe
		var row = base + 4 if caps else base
		var outer = vertices[row].distance_to(vertices[row + 3])
		var inner = vertices[row + 1].distance_to(vertices[row + 2])
		lines.append({"a": transform.xform(a), "b": transform.xform(b),
			"width": (outer + inner) * 0.5, "color": colors[row + 1], "antialiased": true})
		cursor += 54 if caps else 18
