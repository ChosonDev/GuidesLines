extends Reference

# GuidesLinesFill - Fill mode logic for GuidesLinesTool.
#
# Click behaviour depends on how many Shape markers contain the click point:
#
#   ONE shape contains pos  →  EXCLUSIVE fill:
#     Fill = primary shape MINUS every overlapping shape that is not an outer
#     container of the primary.
#     Examples:
#       B partially overlaps A, pos in A only  →  fill A − B
#       B fully inside A,       pos in A only  →  fill A − B  (hole where B is)
#       A fully inside B,       pos in A       →  fill A as-is (B is outer container)
#
#   MULTIPLE shapes contain pos  →  INTERSECTION fill:
#     pos sits in the zone where all hit shapes overlap each other.
#     Fill = (A ∩ B ∩ C …) minus shapes that do not contain pos.
#     Example:
#       A, B, C partially overlap, pos in the common zone  →  fill A ∩ B ∩ C
#
# Usage:
#   const GuidesLinesFill = preload("GuidesLinesFill.gd")
#   var _fill_handler = GuidesLinesFill.new(self)
#   var fill_data = _fill_handler.handle_fill_click(world_pos)

var tool = null

func _init(tool_ref):
	tool = tool_ref

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

## Given a click at [pos] in world space, compute the FillMarker data dict.
## Returns a populated Dictionary (FillMarker.Save() format) or {} on failure.
func handle_fill_click(pos: Vector2) -> Dictionary:
	var cell_size = tool._get_grid_cell_size()
	if cell_size == null:
		if tool.LOGGER:
			tool.LOGGER.warn("GuidesLinesFill: cell_size unavailable, cannot compute fill")
		return {}

	var hit_entries = _collect_hit_markers(pos, cell_size)
	if hit_entries.empty():
		if tool.LOGGER:
			tool.LOGGER.debug("GuidesLinesFill: no Shape marker hit at %s" % str(pos))
		return {}

	var zone = tool._regions_cache.resolve(tool, pos, hit_entries, false, true)
	if zone == null:
		if tool.LOGGER:
			tool.LOGGER.warn("GuidesLinesFill: computed polygon is empty at %s" % str(pos))
		return {}

	var c = tool.active_color
	var fill = tool.FillMarkerClass.new()
	fill.id      = tool.next_fill_id
	fill.polygon = zone.fill.polygon.duplicate()
	fill.color   = Color(c.r, c.g, c.b, 0.25)
	return fill.Save()

# ============================================================================
# HIT DETECTION
# ============================================================================

## Collects all Shape markers whose current polygon contains [pos].
## Returns Array of { "marker": GuideMarker, "desc": { shape_type, points } }.
func _collect_hit_markers(pos: Vector2, cell_size) -> Array:
	var result = []
	for entry in tool._regions_cache.shape_entries(tool):
		if entry.bounds.intersects(Rect2(pos, Vector2.ZERO), true) and Geometry.is_point_in_polygon(pos, entry.pool):
			result.append(entry)
	return result

# ============================================================================
# FILL POLYGON COMPUTATION
# ============================================================================

## Top-level dispatcher: choose fill strategy based on how many shapes contain pos.
func _compute_fill_polygon(pos: Vector2, hit_entries: Array, quiet: bool = false) -> Array:
	# Select the visited connected solid, preserving holes, from compound markers.
	var entries = []
	for entry in hit_entries:
		var points = entry.desc.points
		if entry.get("contours", []).size() > 1:
			var clips = []
			for ring in entry.contours: clips.append(PoolVector2Array(ring))
			points = Array(_merge_clips_to_polygon(clips, pos))
		if points.empty(): return []
		var selected = entry.duplicate()
		selected.desc = {"shape_type": "poly", "points": points}
		entries.append(selected)
	hit_entries = entries
	if hit_entries.size() == 1:
		# pos is inside exactly one shape → exclusive fill (subtract overlaps)
		if tool.LOGGER and not quiet:
			tool.LOGGER.debug("GuidesLinesFill: 1 hit — exclusive fill")
		return _compute_exclusive_fill(pos, hit_entries[0], quiet)
	else:
		# pos is inside the intersection zone of multiple shapes → intersection fill
		if tool.LOGGER and not quiet:
			tool.LOGGER.debug("GuidesLinesFill: %d hits — intersection fill" % hit_entries.size())
		return _compute_intersection_fill(pos, hit_entries, quiet)

# ─── Branch A: EXCLUSIVE FILL ─────────────────────────────────────────────────
# pos is inside only one shape (primary). Fill = primary minus every shape that
# overlaps primary but does NOT fully contain primary.

func _compute_exclusive_fill(pos: Vector2, primary_entry: Dictionary, quiet: bool = false) -> Array:
	var primary_pts = primary_entry.desc.points
	var primary_id  = primary_entry.marker.id
	var primary_bounds = tool.GeometryUtils.polygon_intersection_bounds(primary_pts)

	var shapes_to_subtract = []
	for entry in tool._regions_cache.shape_entries(tool):
		var marker = entry.marker
		if marker.id == primary_id:
			continue
		if not primary_bounds.intersects(entry.bounds, true):
			continue
		var desc = entry.desc
		if not tool._shapes_overlap(primary_entry.desc, desc):
			continue
		# Outer container (primary is inside this marker) → skip, don't subtract.
		if _polygon_fully_inside(primary_pts, desc.points):
			if tool.LOGGER and not quiet:
				tool.LOGGER.debug(
					"GuidesLinesFill: marker %d fully contains primary — skipping" % marker.id)
			continue
		shapes_to_subtract.append(desc.points)

	if shapes_to_subtract.empty():
		if tool.LOGGER and not quiet:
			tool.LOGGER.debug("GuidesLinesFill: nothing to subtract — filling primary as-is")
		return primary_pts

	if tool.LOGGER and not quiet:
		tool.LOGGER.debug(
			"GuidesLinesFill: subtracting %d shape(s) from primary" % shapes_to_subtract.size())
	return _subtract_shapes(pos, primary_pts, shapes_to_subtract)

# ─── Branch B: INTERSECTION FILL ──────────────────────────────────────────────
# Intersect all hit shapes, then subtract non-hit shapes to preserve inner holes.

func _compute_intersection_fill(pos: Vector2, hit_entries: Array, quiet: bool = false) -> Array:
	var result: PoolVector2Array = PoolVector2Array(hit_entries[0].desc.points)

	for i in range(1, hit_entries.size()):
		var next_poly: PoolVector2Array = PoolVector2Array(hit_entries[i].desc.points)
		# intersect_polygons_2d returns the region common to both polygons.
		var clips = Geometry.intersect_polygons_2d(result, next_poly)
		if clips.empty():
			if tool.LOGGER and not quiet:
				tool.LOGGER.debug("GuidesLinesFill: intersection empty at step %d" % i)
			return []
		# Merge results (handles any outer+hole pairs) into one polygon.
		result = _merge_clips_to_polygon(clips, pos)
		if result.empty():
			return []

	var hit_ids = {}
	for entry in hit_entries:
		hit_ids[entry.marker.id] = true
	var intersection_desc = {"shape_type": "poly", "points": Array(result)}
	var intersection_bounds = tool.GeometryUtils.polygon_intersection_bounds(intersection_desc.points)
	var shapes_to_subtract = []
	for entry in tool._regions_cache.shape_entries(tool):
		if hit_ids.has(entry.marker.id):
			continue
		if not intersection_bounds.intersects(entry.bounds, true):
			continue
		var desc = entry.desc
		if not desc.empty() and tool._shapes_overlap(intersection_desc, desc):
			shapes_to_subtract.append(desc.points)
	return _subtract_shapes(pos, Array(result), shapes_to_subtract)

## Union cutters first, then stitch the final holes once, not after every cut.
func _subtract_shapes(pos: Vector2, base_pts: Array, subtract_list: Array) -> Array:
	if subtract_list.empty(): return base_pts
	# ponytail: bridged inputs and cutter unions with islands retain the general sequential path.
	# A native multi-contour boolean API would remove this fallback without topology heuristics.
	var seen = {}
	for index in range(-1, subtract_list.size()):
		var points = base_pts if index == -1 else subtract_list[index]
		seen.clear()
		for point in points:
			if seen.has(point): return _subtract_shapes_sequential(pos, base_pts, subtract_list)
			seen[point] = true
	var cutters = []
	var cutter_bounds = []
	# ponytail: O(K^2) bounds checks; a spatial index is the upgrade for thousands of cutters.
	for points in subtract_list:
		var combined = PoolVector2Array(points)
		var bounds = tool.GeometryUtils.polygon_intersection_bounds(points)
		if Geometry.is_polygon_clockwise(combined): combined.invert()
		var i = 0
		while i < cutters.size():
			if not bounds.intersects(cutter_bounds[i], true):
				i += 1
				continue
			var merged = Geometry.merge_polygons_2d(combined, cutters[i])
			if merged.empty(): return _subtract_shapes_sequential(pos, base_pts, subtract_list)
			if merged.size() == 1:
				combined = merged[0]
				bounds = tool.GeometryUtils.polygon_intersection_bounds(Array(combined))
				cutters.remove(i)
				cutter_bounds.remove(i)
				i = 0
			else:
				for contour in merged:
					if Geometry.is_polygon_clockwise(contour):
						return _subtract_shapes_sequential(pos, base_pts, subtract_list)
				i += 1
		cutters.append(combined)
		cutter_bounds.append(bounds)
	var outer = PoolVector2Array(base_pts)
	var holes = []
	for cutter in cutters:
		var clips = Geometry.clip_polygons_2d(outer, cutter)
		var next_outer = PoolVector2Array()
		var best_area = INF
		for contour in clips:
			if not Geometry.is_polygon_clockwise(contour) and Geometry.is_point_in_polygon(pos, contour):
				var area = _polygon_area(Array(contour))
				if area < best_area:
					next_outer = contour
					best_area = area
			elif Geometry.is_polygon_clockwise(contour):
				holes.append(contour)
		if next_outer.empty(): return []
		outer = next_outer
	return Array(_merge_clips_to_polygon([outer] + holes, pos))

func _subtract_shapes_sequential(pos: Vector2, base_pts: Array, subtract_list: Array) -> Array:
	var result: PoolVector2Array = PoolVector2Array(base_pts)

	for sub_pts in subtract_list:
		var sub: PoolVector2Array = PoolVector2Array(sub_pts)
		# clip_polygons_2d returns the parts of `result` that lie OUTSIDE `sub`.
		# When sub is fully inside result, this returns [outer, hole_reversed].
		var clips = Geometry.clip_polygons_2d(result, sub)
		if clips.empty():
			# The entire remaining area was subtracted — nothing left to fill.
			return []
		# Merge outer polygon + any hole polygons into one drawable polygon.
		result = _merge_clips_to_polygon(clips, pos)
		if result.empty():
			return []

	return Array(result)

## Combine the array of polygons returned by clip_polygons_2d/intersect_polygons_2d
## (outer boundary + optional hole polygons) into a single polygon suitable for
## draw_colored_polygon.
##
## Strategy:
##   1. Pick the smallest outer contour containing [pos], or the largest outer.
##   2. Oppositely wound contours inside that outer are holes.
##   3. Each hole is stitched into the outer polygon via a minimum-distance bridge.
##
## The resulting polygon, when filled with the even-odd rule (used by Godot 3's
## tessellator), correctly leaves the hole regions empty.
func _merge_clips_to_polygon(clips: Array, pos: Vector2) -> PoolVector2Array:
	if clips.size() == 1:
		return clips[0]

	# Nested islands can share a containing outer boundary: select the innermost solid.
	var outer_idx = -1
	var containing_area = INF
	for i in range(clips.size()):
		if not Geometry.is_polygon_clockwise(clips[i]) and Geometry.is_point_in_polygon(pos, clips[i]):
			var area = _polygon_area(Array(clips[i]))
			if area < containing_area:
				outer_idx = i
				containing_area = area
	if outer_idx == -1:
		var max_area = -1.0
		for i in range(clips.size()):
			if Geometry.is_polygon_clockwise(clips[i]): continue
			var a = _polygon_area(Array(clips[i]))
			if a > max_area:
				max_area = a
				outer_idx = i
	if outer_idx == -1:
		return PoolVector2Array()

	# Try every vertex: a tangent first vertex need not count as inside.
	var outer_poly = Array(clips[outer_idx])
	var contained_holes = []
	for clip in clips:
		if not clip.empty() and Geometry.is_polygon_clockwise(clip) and _any_contour_vertex_inside(clip, clips[outer_idx]):
			var points = Array(clip)
			contained_holes.append({"points": points, "pool": clip, "area": _polygon_area(points)})
	var holes = []
	for hole in contained_holes:
		# Only holes belonging directly to this solid, not holes inside a nested island.
		var nested = false
		for other in contained_holes:
			if other.area > hole.area and _any_contour_vertex_inside(hole.pool, other.pool):
				nested = true
				break
		if not nested: holes.append(hole.points)

	if holes.empty():
		return PoolVector2Array(outer_poly)

	# Choose the shortest visible bridge across all remaining holes, independent of marker order.
	# ponytail: cached vertex-pair scans; only the rejected hole rescans the full boundary. Use a spatial/visibility index for many holes.
	var combined = outer_poly
	var added = combined
	var candidates = []
	var retry = -1
	for _hole in holes: candidates.append({"distance": INF, "blocked": {}})
	while not holes.empty():
		var best = -1
		for h in range(holes.size()):
			var candidate = candidates[h]
			for point in (combined if h == retry else added):
				for j in range(holes[h].size()):
					var distance = point.distance_squared_to(holes[h][j])
					if distance < candidate.distance and not candidate.blocked.get(point, {}).has(j):
						candidate.distance = distance
						candidate.a = point
						candidate.b = j
			if best == -1 or candidate.distance < candidates[best].distance: best = h
		if best == -1 or candidates[best].distance == INF: return PoolVector2Array()
		var selected = candidates[best]
		var bridge_direction = holes[best][selected.b]
		if selected.a == bridge_direction:
			bridge_direction = (holes[best][(selected.b + 1) % holes[best].size()] + holes[best][(selected.b - 1 + holes[best].size()) % holes[best].size()]) * 0.5
		var bridge_index = _bridge_vertex_index(selected.a, bridge_direction, combined)
		if bridge_index == -1 or not _bridge_visible(selected.a, holes[best][selected.b], combined, holes):
			# Test visibility only for the global minimum, not every improvement during the pair scan.
			if not selected.blocked.has(selected.a): selected.blocked[selected.a] = {}
			selected.blocked[selected.a][selected.b] = true
			selected.distance = INF
			retry = best
			added = []
			continue
		combined = _bridge_hole_into_polygon(combined, holes[best], [bridge_index, selected.b])
		added = holes[best]
		retry = -1
		holes.remove(best)
		candidates.remove(best)

	return PoolVector2Array(combined)

## Equal coordinates can belong to different sectors of a tangent or bridged outline.
func _bridge_vertex_index(a: Vector2, b: Vector2, polygon: Array) -> int:
	for i in range(polygon.size()):
		if polygon[i] != a: continue
		var incoming = a - polygon[(i - 1 + polygon.size()) % polygon.size()]
		var outgoing = polygon[(i + 1) % polygon.size()] - a
		var direction = b - a
		var left_in = incoming.cross(direction) >= 0.0
		var left_out = outgoing.cross(direction) >= 0.0
		if (left_in and left_out) if incoming.cross(outgoing) >= 0.0 else (left_in or left_out): return i
	return -1

## Stitch [hole_pts] into [outer_pts] via the selected visible zero-width bridge.
## The resulting single polygon, when rendered with the even-odd
## fill rule, visually excludes the hole region.
##
## Clipper returns hole polygons in the opposite winding order to outer polygons,
## which is exactly what the even-odd bridge technique requires — keep as-is.
func _any_contour_vertex_inside(inner: PoolVector2Array, outer: PoolVector2Array) -> bool:
	for point in inner:
		if Geometry.is_point_in_polygon(point, outer): return true
	return false

func _bridge_visible(a: Vector2, b: Vector2, outer: Array, holes: Array) -> bool:
	if a == b: return true
	var middle = (a + b) * 0.5
	if not Geometry.is_point_in_polygon(middle, outer): return false
	for hole in holes:
		if Geometry.is_point_in_polygon(middle, hole): return false
	for contour_index in range(-1, holes.size()):
		var contour = outer if contour_index == -1 else holes[contour_index]
		for i in range(contour.size()):
			var c = contour[i]
			var d = contour[(i + 1) % contour.size()]
			var hit = Geometry.segment_intersects_segment_2d(a, b, c, d)
			if hit != null and hit != a and hit != b: return false
			# Collinear edges can overlap without segment_intersects returning a point.
			for point in [c, d]:
				if point != a and point != b and point.distance_squared_to(Geometry.get_closest_point_to_segment_2d(point, a, b)) < 0.00000001:
					return false
			for point in [a, b]:
				if point != c and point != d and point.distance_squared_to(Geometry.get_closest_point_to_segment_2d(point, c, d)) < 0.00000001:
					return false
	return true

func _bridge_hole_into_polygon(outer_pts: Array, hole_pts: Array, bridge: Array) -> Array:
	if outer_pts.empty() or hole_pts.empty():
		return outer_pts

	var bi = bridge[0]
	var bj = bridge[1]

	# Build the bridged polygon:
	#   outer[0..bi]  →  bridge  →  hole[bj .. bj (full loop)]  →  hole[bj] (close)
	#   →  bridge back outer[bi]  →  outer[bi+1 .. end]
	# outer[bi] appears twice (departure and return), creating an invisible zero-
	# width bridge edge; the even-odd fill rule then leaves the hole region unfilled.
	var result = []
	for i in range(bi + 1):                       # outer[0 .. bi]
		result.append(outer_pts[i])
	var touching = outer_pts[bi] == hole_pts[bj]
	for k in range(1 if touching else 0, hole_pts.size()): # Share a tangent vertex without zero-length edges.
		result.append(hole_pts[(bj + k) % hole_pts.size()])
	result.append(hole_pts[bj])                   # close hole: return to bj
	if not touching: result.append(outer_pts[bi]) # bridge back: return to outer[bi]
	for i in range(bi + 1, outer_pts.size()):     # outer[bi+1 .. end]
		result.append(outer_pts[i])

	return result

func _polygon_fully_inside(inner: Array, outer: Array) -> bool:
	if inner.empty() or outer.empty():
		return false
	if not tool.GeometryUtils.polygon_intersection_bounds(outer).encloses(tool.GeometryUtils.polygon_intersection_bounds(inner)):
		return false
	var outer_pool = PoolVector2Array(outer)
	for pt in inner:
		if not Geometry.is_point_in_polygon(pt, outer_pool):
			return false
	# Vertices alone do not prove containment when an edge crosses a concave notch.
	return Geometry.clip_polygons_2d(PoolVector2Array(inner), outer_pool).empty()


func _polygon_area(pts: Array) -> float:
	var n = pts.size()
	if n < 3:
		return 0.0
	var area = 0.0
	for i in range(n):
		var j = (i + 1) % n
		area += pts[i].x * pts[j].y
		area -= pts[j].x * pts[i].y
	return abs(area) * 0.5
