extends Reference

class_name GeometryUtils

const TWO_PI = 6.28318530718

# Calculate vertices for a regular polygon
# center: Vector2 - Center point
# radius: float - Radius (circumradius)
# sides: int - Number of sides
# rotation_offset: float - Rotation in radians
static func calculate_polygon_vertices(center, radius, sides, rotation_offset = 0.0):
	var vertices = []
	var angle_step = TWO_PI / sides
	
	for i in range(sides):
		var angle = angle_step * i + rotation_offset
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		vertices.append(point)
	
	return vertices

# Standard polygon rotation offsets for named shape subtypes (radians)
const SHAPE_ROTATION_OFFSETS = {
	"Square":   PI / 4.0,
	"Pentagon": -PI / 2.0,
	"Hexagon":  0.0,
	"Octagon":  PI / 8.0,
}

# Standard polygon side counts for named shape subtypes
const SHAPE_SIDES = {
	"Square":   4,
	"Pentagon": 5,
	"Hexagon":  6,
	"Octagon":  8,
}

# Calculate polygon vertices for a named standard shape subtype.
# Handles Square, Pentagon, Hexagon, Octagon and Custom (any n-sided polygon).
# For Circle pass subtype = "Circle" — returns empty Array (use draw_arc instead).
#
# center:       Center position in world space
# radius:       Circumradius in pixels
# subtype:      One of "Circle", "Square", "Pentagon", "Hexagon", "Octagon", "Custom"
# angle_rad:    Additional rotation in radians (on top of the subtype base offset)
# custom_sides: Number of sides; used only when subtype == "Custom"
static func calculate_shape_vertices(center, radius, subtype: String, angle_rad: float, custom_sides: int = 6):
	if subtype == "Circle":
		return []
	var sides = SHAPE_SIDES.get(subtype, custom_sides)
	var offset = SHAPE_ROTATION_OFFSETS.get(subtype, 0.0)
	return calculate_polygon_vertices(center, radius, sides, offset + angle_rad)

## Returns the closest point on segment [a]→[b] to point [p].
static func closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab = b - a
	var len_sq = ab.length_squared()
	if len_sq == 0.0:
		return a
	return a + ab * clamp((p - a).dot(ab) / len_sq, 0.0, 1.0)

## Returns the distance from [p] to the closest point on segment [a]→[b].
static func dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(closest_point_on_segment(p, a, b))

## Returns the perpendicular distance from point [p] to the infinite ray
## defined by [origin] and normalized [direction].
static func dist_point_to_ray(p: Vector2, origin: Vector2, direction: Vector2) -> float:
	var perp = direction.rotated(PI / 2.0)
	return abs((p - origin).dot(perp))

## Returns the closest point on the circumference of circle ([center], [r]) to [p].
## If [p] coincides with [center], returns an arbitrary point on the circle.
static func closest_point_on_circle(p: Vector2, center: Vector2, r: float) -> Vector2:
	var to_p  = p - center
	var to_len = to_p.length()
	if to_len > 1e-10:
		return center + to_p / to_len * r
	return center + Vector2(r, 0.0)

## Returns the closest point on any edge of [pts] to [p].
## When [closed] is true (default) the last edge wraps back to pts[0].
## When [closed] is false, treats [pts] as an open polyline (n-1 edges).
## [pts] must have at least 2 elements.
static func closest_point_on_polygon_edges(p: Vector2, pts: Array, closed: bool = true) -> Vector2:
	var best_pt = pts[0]
	var best_dist_sq = INF
	var edge_count = pts.size() if closed else pts.size() - 1
	for i in range(edge_count):
		var pt = closest_point_on_segment(p, pts[i], pts[(i + 1) % pts.size()])
		var d_sq = p.distance_squared_to(pt)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_pt = pt
	return best_pt

## Returns the vertex in [pts] nearest to [p], or null if [pts] is empty.
static func nearest_polygon_vertex(p: Vector2, pts: Array):
	if pts.empty():
		return null
	var best_v    = pts[0]
	var best_d_sq = p.distance_squared_to(pts[0])
	for i in range(1, pts.size()):
		var d_sq = p.distance_squared_to(pts[i])
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best_v    = pts[i]
	return best_v

## Intersects an infinite line (lp + t*ld, ld must be normalised) with segment
## [a]→[b].  Returns the intersection Vector2, or null if parallel / no hit.
static func line_intersect_segment(lp: Vector2, ld: Vector2, a: Vector2, b: Vector2):
	var ab    = b - a
	var denom = ab.x * ld.y - ab.y * ld.x   # cross(ab, ld)
	if abs(denom) < 1e-10:
		return null  # parallel
	var diff = lp - a
	var s    = (diff.x * ld.y - diff.y * ld.x) / denom  # cross(diff, ld) / cross(ab, ld)
	if s < -1e-6 or s > 1.0 + 1e-6:
		return null
	return a + ab * clamp(s, 0.0, 1.0)

## Intersects an infinite line (lp + t*ld, ld must be normalised) with a circle.
## Returns an Array of 0, 1, or 2 Vector2 intersection points.
static func line_intersect_circle(lp: Vector2, ld: Vector2, center: Vector2, r: float) -> Array:
	var to_center  = center - lp
	var proj       = to_center.dot(ld)
	var closest    = lp + ld * proj
	var dist_sq    = (center - closest).length_squared()
	var r_sq       = r * r
	if dist_sq > r_sq + 1e-10:
		return []
	var half_chord = sqrt(max(0.0, r_sq - dist_sq))
	if half_chord < 1e-5:
		return [closest]
	return [closest - ld * half_chord, closest + ld * half_chord]

# Liang-Barsky line clipping algorithm for a SEGMENT
# Returns [p1, p2] inside the rect, or empty array [] if outside
static func clip_line_segment_to_rect(p1, p2, rect):
	var x1 = p1.x
	var y1 = p1.y
	var x2 = p2.x
	var y2 = p2.y
	
	var dx = x2 - x1
	var dy = y2 - y1
	
	var t_min = 0.0
	var t_max = 1.0
	
	# Check all four boundaries
	# p values: -dx, dx, -dy, dy
	# q values: x1 - left, right - x1, y1 - top, bottom - y1
	var p = [-dx, dx, -dy, dy]
	var q = [x1 - rect.position.x, rect.position.x + rect.size.x - x1, 
			 y1 - rect.position.y, rect.position.y + rect.size.y - y1]
	
	for i in range(4):
		if p[i] == 0:
			# Line is parallel to boundary
			if q[i] < 0:
				return [] # Outside
		else:
			var t = q[i] / p[i]
			if p[i] < 0:
				# Entering the boundary
				if t > t_max: return []
				if t > t_min: t_min = t
			else:
				# Leaving the boundary
				if t < t_min: return []
				if t < t_max: t_max = t
	
	if t_min > t_max:
		return [] # Outside
	
	return [
		Vector2(x1 + t_min * dx, y1 + t_min * dy),
		Vector2(x1 + t_max * dx, y1 + t_max * dy)
	]

# Liang-Barsky line clipping algorithm for a RAY (infinite line in one direction)
# Returns [p_start, p_end] inside the rect, or null if outside
# pos: Start point of the ray
# dir: Direction vector (normalized)
# rect: Clipping rectangle
static func clip_ray_to_rect(pos: Vector2, dir: Vector2, rect: Rect2):
	var x_min = rect.position.x
	var y_min = rect.position.y
	var x_max = rect.position.x + rect.size.x
	var y_max = rect.position.y + rect.size.y
	
	var p = [-dir.x, dir.x, -dir.y, dir.y]
	var q = [pos.x - x_min, x_max - pos.x, pos.y - y_min, y_max - pos.y]
	
	var u1 = 0.0 # Start constraint: t >= 0 (Ray starts at pos)
	var u2 = 1e10 # End constraint: "infinite"
	
	for i in range(4):
		if p[i] == 0:
			if q[i] < 0:
				return null # Parallel and outside
		else:
			var t = q[i] / p[i]
			if p[i] < 0:
				if t > u2: return null
				if t > u1: u1 = t
			else:
				if t < u1: return null
				if t < u2: u2 = t
	
	if u1 > u2:
		return null
	
	var p_start = pos + dir * u1
	var p_end = pos + dir * u2
	return [p_start, p_end]

# Calculate geometric intersection of a ray with viewport/rect boundaries
# Used for previewing infinite lines before they are clipped to map bounds
# Returns [start, end] where end is on the boundary
static func get_ray_to_rect_edge(origin, direction, rect):
	var t_min = 0.0
	var t_max = INF
	
	# Check X (vertical boundaries)
	if abs(direction.x) < 0.00001:
		if origin.x < rect.position.x or origin.x > rect.end.x:
			return [origin, origin] # Parallel and outside
	else:
		var txt1 = (rect.position.x - origin.x) / direction.x
		var txt2 = (rect.end.x - origin.x) / direction.x
		
		# t_min/max for X interval
		var t_x_min = min(txt1, txt2)
		var t_x_max = max(txt1, txt2)
		
		t_min = max(t_min, t_x_min)
		t_max = min(t_max, t_x_max)

	# Check Y (horizontal boundaries)
	if abs(direction.y) < 0.00001:
		if origin.y < rect.position.y or origin.y > rect.end.y:
			return [origin, origin] # Parallel and outside
	else:
		var tyt1 = (rect.position.y - origin.y) / direction.y
		var tyt2 = (rect.end.y - origin.y) / direction.y
		
		# t_min/max for Y interval
		var t_y_min = min(tyt1, tyt2)
		var t_y_max = max(tyt1, tyt2)
		
		t_min = max(t_min, t_y_min)
		t_max = min(t_max, t_y_max)
	
	# If t_min > t_max, the ray misses the rect completely
	if t_min > t_max:
		return [origin, origin]
	
	# Construct the segment
	# If origin is inside, we want from origin (t=0) to exit point (t_max)
	if rect.has_point(origin):
		return [origin, origin + direction * t_max]
	
	# If origin is outside and ray hits rect, theoretically we want [entry, exit]
	# But for "infinite line from origin", we might want from origin to exit?
	# The original code logic implies drawing from origin to the edge of viewport.
	# If origin is outside viewport, we usually draw from entry to exit.
	return [origin + direction * t_min, origin + direction * t_max]

# Calculate points for an arrowhead
# tip_pos: Position of the arrow tip
# direction_from: Point to determine direction from (start of arrow line)
# length: Length of the arrowhead lines
# angle_deg: Angle of the arrowhead lines relative to the shaft
static func calculate_arrowhead_points(tip_pos, direction_from, length, angle_deg):
	var direction = (tip_pos - direction_from).normalized()
	var angle_rad = deg2rad(angle_deg)
	
	var left_angle = direction.angle() + PI - angle_rad
	var right_angle = direction.angle() + PI + angle_rad
	
	var left_point = tip_pos + Vector2(cos(left_angle), sin(left_angle)) * length
	var right_point = tip_pos + Vector2(cos(right_angle), sin(right_angle)) * length
	
	return [left_point, right_point]

# Normalize angle to range [-PI, PI]
# Returns the shortest difference between two angles in radians
static func get_angle_difference(angle1, angle2):
	var diff = angle1 - angle2
	return fposmod(diff + PI, TWO_PI) - PI

# Check if a point lies on a ray (within angular threshold)
# origin: Start of the ray
# direction: Direction vector (normalized)
# point: Point to check
# threshold_rad: Maximum angular deviation in radians
static func is_point_on_ray(origin, direction, point, threshold_rad = 0.1):
	var to_point = point - origin
	if to_point.length_squared() < 0.1: return true # Point coincides with origin
	
	var angle_to_point = to_point.angle()
	var line_angle = direction.angle()
	
	var diff = abs(get_angle_difference(angle_to_point, line_angle))
	
	return diff < threshold_rad

# Calculate vertices for a thick line segment (rectangle)
# Used for hit testing or drawing thick lines as polygons
static func calculate_thick_line_poly(start, end, width):
	var direction = (end - start).normalized()
	# Perpendicular vector
	var normal = Vector2(-direction.y, direction.x) * (width * 0.5)
	
	return [
		start + normal,
		end + normal,
		end - normal,
		start - normal
	]

# ============================================================================
# SHAPE CLIPPING UTILITIES
# Used for "Clip Intersecting Shapes" feature
# ============================================================================

## Returns the intersection point of segment [a1]→[a2] with segment [b1]→[b2],
## or null if they don't intersect (includes parallel case).
static func segment_segment_intersect(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2):
	var da = a2 - a1
	var db = b2 - b1
	var denom = da.x * db.y - da.y * db.x
	if abs(denom) < 1e-10:
		return null  # Parallel
	var d = b1 - a1
	var t = (d.x * db.y - d.y * db.x) / denom
	var u = (d.x * da.y - d.y * da.x) / denom
	if t < -1e-6 or t > 1.0 + 1e-6 or u < -1e-6 or u > 1.0 + 1e-6:
		return null
	return a1 + da * clamp(t, 0.0, 1.0)

## Returns intersection points of segment [a]→[b] with circle ([center],[r]).
## Returns Array of 0, 1, or 2 Vector2 points.
static func segment_intersects_circle(a: Vector2, b: Vector2, center: Vector2, r: float) -> Array:
	var d = b - a
	var f = a - center
	var cap = d.dot(d)
	if cap < 1e-12:
		return []
	var bval = 2.0 * f.dot(d)
	var c = f.dot(f) - r * r
	var disc = bval * bval - 4.0 * cap * c
	if disc < 0.0:
		return []
	var sqrt_disc = sqrt(disc)
	var t1 = (-bval - sqrt_disc) / (2.0 * cap)
	var t2 = (-bval + sqrt_disc) / (2.0 * cap)
	var result = []
	if t1 >= -1e-6 and t1 <= 1.0 + 1e-6:
		result.append(a + d * clamp(t1, 0.0, 1.0))
	if abs(t2 - t1) > 1e-6 and t2 >= -1e-6 and t2 <= 1.0 + 1e-6:
		result.append(a + d * clamp(t2, 0.0, 1.0))
	return result

## Returns true if point [p] is strictly inside circle ([center],[r]).
static func point_inside_circle(p: Vector2, center: Vector2, r: float) -> bool:
	return center.distance_squared_to(p) < r * r - 1e-6

## Clip polygon edges against multiple shapes, keeping only sub-segments whose
## midpoint lies OUTSIDE ALL shapes in [b_shapes].
## Returns Array of { "type": "seg", "a": Vector2, "b": Vector2 }.
## Each b_shape must be one of:
##   { "shape_type": "poly",   "points": Array<Vector2> }
##   { "shape_type": "circle", "center": Vector2, "radius": float }
static func clip_polygon_against_shapes(poly_pts: Array, b_shapes: Array) -> Array:
	var result = []
	var n = poly_pts.size()
	for i in range(n):
		var pa = poly_pts[i]
		var pb = poly_pts[(i + 1) % n]
		var edge = pb - pa
		var edge_len_sq = edge.length_squared()
		if edge_len_sq < 1e-10:
			continue

		# Collect all parametric split positions along this edge
		var ts = [0.0, 1.0]
		for b_shape in b_shapes:
			if b_shape.shape_type == "poly":
				var m = b_shape.points.size()
				for j in range(m):
					var qa = b_shape.points[j]
					var qb = b_shape.points[(j + 1) % m]
					var pt = segment_segment_intersect(pa, pb, qa, qb)
					if pt != null:
						ts.append(clamp((pt - pa).dot(edge) / edge_len_sq, 0.0, 1.0))
			elif b_shape.shape_type == "circle":
				var hit_pts = segment_intersects_circle(pa, pb, b_shape.center, b_shape.radius)
				for pt in hit_pts:
					ts.append(clamp((pt - pa).dot(edge) / edge_len_sq, 0.0, 1.0))
		ts.sort()

		# Test midpoint of each sub-segment: keep if outside all shapes
		for k in range(ts.size() - 1):
			if ts[k + 1] - ts[k] < 1e-6:
				continue
			var mid = pa + edge * ((ts[k] + ts[k + 1]) * 0.5)
			var outside = true
			for b_shape in b_shapes:
				if b_shape.shape_type == "poly":
					if Geometry.is_point_in_polygon(mid, b_shape.points):
						outside = false
						break
				elif b_shape.shape_type == "circle":
					if point_inside_circle(mid, b_shape.center, b_shape.radius):
						outside = false
						break
			if outside:
				result.append({"type": "seg", "a": pa + edge * ts[k], "b": pa + edge * ts[k + 1]})
	return result

## Clip circle arcs against multiple shapes, keeping only arcs whose midpoint
## lies OUTSIDE ALL shapes in [b_shapes].
## Returns Array of { "type": "arc", "center": Vector2, "radius": float, "from": float, "to": float }.
## [from] and [to] are angles in radians; "to" is always > "from" (may exceed PI).
static func clip_circle_against_shapes(center: Vector2, r: float, b_shapes: Array) -> Array:
	# Collect all angles where this circle crosses any shape boundary
	var intersection_angles = []

	for b_shape in b_shapes:
		if b_shape.shape_type == "poly":
			var pts = b_shape.points
			var m = pts.size()
			for j in range(m):
				var hit_pts = segment_intersects_circle(pts[j], pts[(j + 1) % m], center, r)
				for pt in hit_pts:
					intersection_angles.append((pt - center).angle())
		elif b_shape.shape_type == "circle":
			var d = b_shape.center.distance_to(center)
			# Skip if circles don't actually intersect
			if d < 1e-6 or d >= r + b_shape.radius - 1e-6 or d <= abs(r - b_shape.radius) + 1e-6:
				continue
			var a_val = (r * r - b_shape.radius * b_shape.radius + d * d) / (2.0 * d)
			var h = sqrt(max(0.0, r * r - a_val * a_val))
			var dir = (b_shape.center - center).normalized()
			var perp = Vector2(-dir.y, dir.x)
			var p0 = center + dir * a_val + perp * h
			var p1 = center + dir * a_val - perp * h
			intersection_angles.append((p0 - center).angle())
			intersection_angles.append((p1 - center).angle())

	# No intersection points: the circle is entirely inside or outside all shapes
	if intersection_angles.empty():
		var test_pt = center + Vector2(r, 0.0)
		var keep = true
		for b_shape in b_shapes:
			if b_shape.shape_type == "poly" and Geometry.is_point_in_polygon(test_pt, b_shape.points):
				keep = false
				break
			elif b_shape.shape_type == "circle" and point_inside_circle(test_pt, b_shape.center, b_shape.radius):
				keep = false
				break
		if keep:
			return [{"type": "arc", "center": center, "radius": r, "from": 0.0, "to": TAU}]
		return []

	intersection_angles.sort()
	var result = []
	var ang_count = intersection_angles.size()
	for i in range(ang_count):
		var a_from = intersection_angles[i]
		var a_to   = intersection_angles[(i + 1) % ang_count]
		if a_to <= a_from:
			a_to += TAU  # Wrap last arc back to first angle
		var mid_angle = (a_from + a_to) * 0.5
		var mid_pt = center + Vector2(cos(mid_angle), sin(mid_angle)) * r
		var keep = true
		for b_shape in b_shapes:
			if b_shape.shape_type == "poly" and Geometry.is_point_in_polygon(mid_pt, b_shape.points):
				keep = false
				break
			elif b_shape.shape_type == "circle" and point_inside_circle(mid_pt, b_shape.center, b_shape.radius):
				keep = false
				break
		if keep:
			result.append({"type": "arc", "center": center, "radius": r, "from": a_from, "to": a_to})
	return result

