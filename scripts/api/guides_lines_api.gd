extends Reference

const GeometryUtils = preload("../utils/GeometryUtils.gd")

# GuidesLinesApi - External API for the GuidesLines mod
#
# Allows other mods to interact with GuidesLines programmatically.
#
# Usage from another mod:
#
#   # After map is loaded, check if the API is available:
#   if self.Global.API.has("GuidesLinesApi"):
#       var gl = self.Global.API.GuidesLinesApi
#       var id = gl.place_line_marker(Vector2(512, 512))
#       gl.connect("marker_placed", self, "_on_marker_placed")
#
#   # Or listen for late registration:
#   self.Global.API.connect("api_registered", self, "_on_api_registered")
#   func _on_api_registered(api_id, _api):
#       if api_id == "GuidesLinesApi":
#           var gl = self.Global.API.GuidesLinesApi
#           ...
#
# ============================================================================
# SIGNALS
# ============================================================================

# Emitted when any marker is placed via tool or API.
# marker_id: int  — unique marker id
# position:  Vector2 — world position of the marker
signal marker_placed(marker_id, position)

# Emitted when a single marker is deleted.
# marker_id: int — unique marker id that was removed
signal marker_deleted(marker_id)

# Emitted when all markers are cleared at once.
signal all_markers_deleted()

# Emitted when an overlay setting changes.
# setting_name: String — one of "cross_guides", "perm_vertical",
#                        "perm_horizontal", "show_coordinates"
# value: bool
signal settings_changed(setting_name, value)

# ============================================================================
# INTERNALS
# ============================================================================

const CLASS_NAME = "GuidesLinesApi"

var _mod   # Reference to GuidesLines main script
var LOGGER  # Logger instance

# ============================================================================
# INIT / UNLOAD
# ============================================================================

func _init(mod, logger):
	_mod = mod
	LOGGER = logger
	if LOGGER:
		LOGGER.info("GuidesLinesApi initialized")

func _unload():
	if LOGGER:
		LOGGER.info("Unloading %s." % [CLASS_NAME])
	# Disconnect all signal connections
	for signal_dict in get_signal_list():
		var signal_name = signal_dict.name
		for callable_dict in get_signal_connection_list(signal_name):
			disconnect(signal_name, callable_dict.target, callable_dict.method)

# ============================================================================
# MARKER PLACEMENT
# ============================================================================

## Places a Line marker at [position].
## Returns the integer id of the created marker, or -1 on failure.
## Parameters:
##   position — world-space Vector2
##   angle    — line angle in degrees (default 0.0)
##   mirror   — whether to also draw the mirrored line (default false)
##   color    — marker color (default Color(0, 0.7, 1, 1))
func place_line_marker(position: Vector2, angle: float = 0.0, mirror: bool = false, color = null) -> int:
	if not _has_tool():
		return -1
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position": position,
		"marker_type": "Line",
		"color": color if color != null else tool.active_color,
		"coordinates": tool.show_coordinates,
		"id": marker_id,
		"angle": angle,
		"mirror": mirror,
	}
	tool.api_place_marker(marker_data)
	if LOGGER:
		LOGGER.debug("API: Line marker placed id=%d pos=%s angle=%.1f" % [marker_id, str(position), angle])
	return marker_id

## Places a Shape marker at [position].
## Returns the integer id of the created marker, or -1 on failure.
## Parameters:
##   position — world-space Vector2
##   radius   — circumradius in grid cells (default 1.0)
##   angle    — rotation in degrees (default 0.0)
##   sides    — number of polygon sides (default 6)
##   color    — marker color (default active color)
func place_shape_marker(position: Vector2, radius: float = 1.0,
						angle: float = 0.0, sides: int = 6, color = null) -> int:
	if not _has_tool():
		return -1
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position": position,
		"marker_type": "Shape",
		"color": color if color != null else tool.active_color,
		"coordinates": tool.show_coordinates,
		"id": marker_id,
		"shape_radius": radius,
		"shape_angle": angle,
		"shape_sides": sides,
	}
	tool.api_place_marker(marker_data)
	if LOGGER:
		LOGGER.debug("API: Shape marker placed id=%d pos=%s sides=%d" % [marker_id, str(position), sides])
	return marker_id

## Places a Path marker.
## Returns the integer id of the created marker, or -1 on failure.
## Parameters:
##   points — Array of Vector2, minimum 2 points
##   closed — whether the path is a closed loop (default false)
##   color  — marker color (default active color)
func place_path_marker(points: Array, closed: bool = false, color = null) -> int:
	if not _has_tool():
		return -1
	if points.size() < 2:
		if LOGGER:
			LOGGER.warn("API: place_path_marker requires at least 2 points")
		return -1
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position": points[0],
		"marker_type": "Path",
		"color": color if color != null else tool.active_color,
		"coordinates": tool.show_coordinates,
		"id": marker_id,
		"marker_points": points.duplicate(),
		"path_closed": closed,
	}
	tool.api_place_marker(marker_data)
	if LOGGER:
		LOGGER.debug("API: Path marker placed id=%d points=%d closed=%s" % [marker_id, points.size(), str(closed)])
	return marker_id

## Places an Arrow marker from [from_pos] to [to_pos].
## Returns the integer id of the created marker, or -1 on failure.
## Parameters:
##   from_pos    — start world-space Vector2
##   to_pos      — end world-space Vector2
##   head_length — arrowhead length in pixels (default 50.0)
##   head_angle  — arrowhead opening angle in degrees (default 30.0)
##   color       — marker color (default active color)
func place_arrow_marker(from_pos: Vector2, to_pos: Vector2,
						head_length: float = 50.0, head_angle: float = 30.0, color = null) -> int:
	if not _has_tool():
		return -1
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position": from_pos,
		"marker_type": "Arrow",
		"color": color if color != null else tool.active_color,
		"coordinates": tool.show_coordinates,
		"id": marker_id,
		"marker_points": [from_pos, to_pos],
		"arrow_head_length": head_length,
		"arrow_head_angle": head_angle,
	}
	tool.api_place_marker(marker_data)
	if LOGGER:
		LOGGER.debug("API: Arrow marker placed id=%d from=%s to=%s" % [marker_id, str(from_pos), str(to_pos)])
	return marker_id

# ============================================================================
# MARKER DELETION
# ============================================================================

## Deletes a marker by its integer id.
## Returns true if the marker was found and deleted, false otherwise.
func delete_marker(marker_id: int) -> bool:
	if not _has_tool():
		return false
	var result = _tool().api_delete_marker_by_id(marker_id)
	if not result and LOGGER:
		LOGGER.warn("API: delete_marker — id %d not found" % [marker_id])
	return result

## Deletes all markers on the map. Supports undo.
func delete_all_markers() -> void:
	if not _has_tool():
		return
	_tool().delete_all_markers()
	if LOGGER:
		LOGGER.debug("API: All markers deleted")

# ============================================================================
# MARKER QUERIES
# ============================================================================

## Returns an Array of Dictionaries, one per marker.
## Each dict has the same format as GuideMarker.Save():
##   { id, position, marker_type, color, show_coordinates, ... }
## Note: position is returned as Vector2 (not serialized array).
func get_markers() -> Array:
	if not _has_tool():
		return []
	var result = []
	for marker in _tool().markers:
		result.append(_marker_save_with_pos(marker))
	return result

## Returns a single marker Dictionary by id, or null if not found.
## Dict format is the same as for get_markers().
func get_marker(marker_id: int):
	if not _has_tool():
		return null
	var tool = _tool()
	if not tool.markers_lookup.has(marker_id):
		return null
	return _marker_save_with_pos(tool.markers_lookup[marker_id])

## Returns the total number of markers currently on the map.
func get_marker_count() -> int:
	if not _has_tool():
		return 0
	return _tool().markers.size()

## Finds the nearest marker within [radius] world units of [coords].
## Searches by marker.position.
## Returns a Dictionary (same format as get_marker, with an extra "distance" key),
## or null if no marker exists within the given radius.
## Parameters:
##   coords — world-space Vector2 to search around
##   radius — search radius in world units (default 100.0)
func find_nearest_marker(coords: Vector2, radius: float = 100.0):
	if not _has_tool():
		return null
	var nearest_marker = null
	var nearest_dist = radius
	for marker in _tool().markers:
		var dist = marker.position.distance_to(coords)
		if dist <= nearest_dist:
			nearest_dist = dist
			nearest_marker = marker
	if nearest_marker == null:
		if LOGGER:
			LOGGER.debug("API: find_nearest_marker — nothing found within radius %.1f of %s" % [radius, str(coords)])
		return null
	var d = _marker_save_with_pos(nearest_marker)
	d["distance"] = nearest_dist
	if LOGGER:
		LOGGER.debug("API: find_nearest_marker — id=%d type=%s dist=%.3f" % [nearest_marker.id, nearest_marker.marker_type, nearest_dist])
	return d

## Finds the nearest marker by checking BOTH the marker's position and its drawn
## geometry (line segments, shape edges/circle circumference, path segments, arrow shaft).
## For each marker the minimum distance across the position and all geometry pieces
## is computed. Returns the marker with the smallest such distance within [radius].
##
## Returns a Dictionary on success:
##   { "point":    Vector2       — actual closest point on the marker's geometry,
##     "vertex":   Vector2|null  — nearest vertex of the marker (only for Shape/poly
##                                  and Path; null for Line, Circle, Arrow),
##     "distance": float         — distance from [coords] to [point],
##     + all keys from marker.Save(), plus "position" as Vector2 }
## Returns null if no marker geometry is found within the given radius.
##
## Parameters:
##   coords — world-space Vector2 to search around
##   radius — search radius in world units (default 100.0)
func find_nearest_marker_by_geometry(coords: Vector2, radius: float = 100.0):
	if not _has_tool():
		return null
	var tool = _tool()

	var ctx = _get_map_context(tool)
	var map_rect  = ctx[0]
	var cell_size = ctx[1]

	var nearest_marker = null
	var nearest_dist = radius
	var nearest_point = null   # actual closest Vector2 on the geometry
	var nearest_vertex = null  # nearest polygon vertex (Shape/poly and Path only)

	for marker in tool.markers:
		# Always start with the raw position distance / point
		var min_dist = marker.position.distance_to(coords)
		var min_point = marker.position
		var min_vertex = null  # populated only for Shape/poly and Path

		match marker.marker_type:
			"Line":
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("segments"):
					for seg in draw_data["segments"]:
						var pt = _closest_point_on_segment(coords, seg[0], seg[1])
						var d = coords.distance_to(pt)
						if d < min_dist:
							min_dist = d
							min_point = pt

			"Shape":
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("shape_type") and draw_data["shape_type"] == "poly" and draw_data.has("points"):
					var pts = draw_data["points"]
					var pt = GeometryUtils.closest_point_on_polygon_edges(coords, pts)
					var d = coords.distance_to(pt)
					if d < min_dist:
						min_dist = d
						min_point = pt
					min_vertex = GeometryUtils.nearest_polygon_vertex(coords, pts)

			"Path":
				var pts = marker.marker_points
				if pts.size() >= 2:
					var pt = GeometryUtils.closest_point_on_polygon_edges(coords, pts, marker.path_closed)
					var d = coords.distance_to(pt)
					if d < min_dist:
						min_dist = d
						min_point = pt
					min_vertex = GeometryUtils.nearest_polygon_vertex(coords, pts)

			"Arrow":
				if marker.marker_points.size() >= 2:
					# Primary shaft: from → to
					var pt = _closest_point_on_segment(coords, marker.marker_points[0], marker.marker_points[1])
					var d = coords.distance_to(pt)
					if d < min_dist:
						min_dist = d
						min_point = pt

		if min_dist <= nearest_dist:
			nearest_dist = min_dist
			nearest_point = min_point
			nearest_vertex = min_vertex
			nearest_marker = marker

	if nearest_marker == null:
		if LOGGER:
			LOGGER.debug("API: find_nearest_marker_by_geometry — nothing found within radius %.1f of %s" % [radius, str(coords)])
		return null
	var d = _marker_save_with_pos(nearest_marker)
	d["point"] = nearest_point
	d["vertex"] = nearest_vertex
	d["distance"] = nearest_dist
	if LOGGER:
		LOGGER.debug("API: find_nearest_marker_by_geometry — id=%d type=%s point=%s vertex=%s dist=%.3f" % [nearest_marker.id, nearest_marker.marker_type, str(nearest_point), str(nearest_vertex), nearest_dist])
	return d

## Finds the nearest intersection point between an infinite line and any marker
## geometry within [radius] world units of [coords].
##
## The line is defined by two world-space points and is treated as infinite
## in both directions. Only intersection points that land within [radius] of
## [coords] are considered. The nearest such point to [coords] is returned.
## Line-type markers are always tested (their segments span the whole map);
## Shape/Path/Arrow markers are pre-filtered by their position distance to
## [coords] to skip obviously far markers early.
##
## Returns a Dictionary on success:
##   { "point":       Vector2  — world-space intersection point,
##     "distance":    float    — distance from [coords] to the intersection,
##     "on_positive": bool     — true if the hit is in the line_from→line_to direction,
##     "marker_id":   int,
##     "marker_type": String,
##     + all keys from marker.Save() }
## Returns null if no intersection was found.
##
## Parameters:
##   line_from — first point defining the infinite line
##   line_to   — second point defining the infinite line
##   coords    — world-space Vector2 centre of the search area
##   radius    — search radius in world units (default 100.0)
func find_line_intersection(line_from: Vector2, line_to: Vector2, coords: Vector2, radius: float = 100.0):
	if not _has_tool():
		return null
	var delta = line_to - line_from
	if delta.length_squared() < 1e-10:
		if LOGGER:
			LOGGER.warn("API: find_line_intersection — line_from and line_to are identical")
		return null
	var line_dir = delta.normalized()
	var tool = _tool()

	var ctx = _get_map_context(tool)
	var map_rect  = ctx[0]
	var cell_size = ctx[1]

	var best_point = null
	var best_dist  = radius
	var best_marker = null

	for marker in tool.markers:
		var candidates = []   # Vector2 intersection points to test

		match marker.marker_type:
			"Line":
				# Always test – drawn segments span the whole map
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("segments"):
					for seg in draw_data["segments"]:
						var pt = _line_intersect_segment(line_from, line_dir, seg[0], seg[1])
						if pt != null:
							candidates.append(pt)

			"Shape":
				if marker.position.distance_to(coords) > radius:
					continue
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("shape_type") and draw_data["shape_type"] == "poly" and draw_data.has("points"):
					var pts = draw_data["points"]
					for i in range(pts.size()):
						var pt = _line_intersect_segment(line_from, line_dir, pts[i], pts[(i + 1) % pts.size()])
						if pt != null:
							candidates.append(pt)

			"Path":
				if marker.position.distance_to(coords) > radius:
					continue
				var pts = marker.marker_points
				if pts.size() >= 2:
					var edge_count = pts.size() - 1
					if marker.path_closed:
						edge_count = pts.size()
					for i in range(edge_count):
						var pt = _line_intersect_segment(line_from, line_dir, pts[i], pts[(i + 1) % pts.size()])
						if pt != null:
							candidates.append(pt)

			"Arrow":
				if marker.position.distance_to(coords) > radius:
					continue
				if marker.marker_points.size() >= 2:
					var pt = _line_intersect_segment(line_from, line_dir, marker.marker_points[0], marker.marker_points[1])
					if pt != null:
						candidates.append(pt)

		# Keep only candidates within radius of coords; pick nearest to coords
		for pt in candidates:
			var dist = coords.distance_to(pt)
			if dist <= best_dist:
				best_dist   = dist
				best_point  = pt
				best_marker = marker

	if best_marker == null:
		if LOGGER:
			LOGGER.debug("API: find_line_intersection — no intersection found within radius %.1f of %s" % [radius, str(coords)])
		return null

	var result = _marker_save_with_pos(best_marker)
	result["point"]       = best_point
	result["distance"]    = best_dist
	result["on_positive"] = (best_point - line_from).dot(line_dir) >= 0.0
	result["marker_id"]   = best_marker.id
	result["marker_type"] = best_marker.marker_type
	if LOGGER:
		LOGGER.debug("API: find_line_intersection — id=%d type=%s point=%s dist=%.3f" % [
			best_marker.id, best_marker.marker_type, str(best_point), best_dist])
	return result

## Finds the nearest point on any marker's drawn geometry within [radius] world
## units of [coords].
##
## Unlike find_nearest_marker_by_geometry (which returns the marker with the
## closest geometry), this method returns the actual closest geometric point
## itself — the exact spot on the line/edge/circumference/path/shaft that is
## nearest to [coords].
##
## Returns a Dictionary on success (same format as find_line_intersection):
##   { "point":       Vector2  — world-space closest point on the geometry,
##     "distance":    float    — distance from [coords] to that point,
##     "marker_id":   int,
##     "marker_type": String,
##     + all keys from marker.Save() }
## Returns null if no marker geometry is found within the given radius.
##
## Parameters:
##   coords — world-space Vector2 origin of the search
##   radius — search radius in world units (default 100.0)
func find_nearest_geometry_point(coords: Vector2, radius: float = 100.0):
	if not _has_tool():
		return null
	var tool = _tool()

	var ctx = _get_map_context(tool)
	var map_rect  = ctx[0]
	var cell_size = ctx[1]

	var best_point  = null
	var best_dist   = radius
	var best_marker = null

	for marker in tool.markers:
		var candidates = []  # Array of Vector2 — closest points per geometry piece

		match marker.marker_type:
			"Line":
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("segments"):
					for seg in draw_data["segments"]:
						candidates.append(_closest_point_on_segment(coords, seg[0], seg[1]))

			"Shape":
				if marker.position.distance_to(coords) > radius:
					continue
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("shape_type") and draw_data["shape_type"] == "poly" and draw_data.has("points"):
					candidates.append(GeometryUtils.closest_point_on_polygon_edges(coords, draw_data["points"]))

			"Path":
				if marker.position.distance_to(coords) > radius:
					continue
				var pts = marker.marker_points
				if pts.size() >= 2:
					candidates.append(GeometryUtils.closest_point_on_polygon_edges(coords, pts, marker.path_closed))

			"Arrow":
				if marker.position.distance_to(coords) > radius:
					continue
				if marker.marker_points.size() >= 2:
					candidates.append(_closest_point_on_segment(coords, marker.marker_points[0], marker.marker_points[1]))

		for pt in candidates:
			var dist = coords.distance_to(pt)
			if dist <= best_dist:
				best_dist   = dist
				best_point  = pt
				best_marker = marker

	if best_marker == null:
		if LOGGER:
			LOGGER.debug("API: find_nearest_geometry_point — nothing found within radius %.1f of %s" % [radius, str(coords)])
		return null

	var result = _marker_save_with_pos(best_marker)
	result["point"]       = best_point
	result["distance"]    = best_dist
	result["marker_id"]   = best_marker.id
	result["marker_type"] = best_marker.marker_type
	if LOGGER:
		LOGGER.debug("API: find_nearest_geometry_point — id=%d type=%s point=%s dist=%.3f" % [
			best_marker.id, best_marker.marker_type, str(best_point), best_dist])
	return result

# ============================================================================
# OVERLAY SETTINGS
# ============================================================================

## Enables or disables the proximity cross-guide overlay.
func set_cross_guides(enabled: bool) -> void:
	_mod.cross_guides_enabled = enabled
	emit_signal("settings_changed", "cross_guides", enabled)
	if LOGGER:
		LOGGER.debug("API: cross_guides = %s" % [str(enabled)])

## Enables or disables the permanent vertical center line.
func set_permanent_vertical(enabled: bool) -> void:
	_mod.perm_vertical_enabled = enabled
	_mod._on_perm_guide_changed(enabled)
	emit_signal("settings_changed", "perm_vertical", enabled)
	if LOGGER:
		LOGGER.debug("API: perm_vertical = %s" % [str(enabled)])

## Enables or disables the permanent horizontal center line.
func set_permanent_horizontal(enabled: bool) -> void:
	_mod.perm_horizontal_enabled = enabled
	_mod._on_perm_guide_changed(enabled)
	emit_signal("settings_changed", "perm_horizontal", enabled)
	if LOGGER:
		LOGGER.debug("API: perm_horizontal = %s" % [str(enabled)])

## Enables or disables coordinate display on new markers.
func set_show_coordinates(enabled: bool) -> void:
	_mod.show_coordinates_enabled = enabled
	if _has_tool():
		_tool().set_show_coordinates(enabled)
	emit_signal("settings_changed", "show_coordinates", enabled)
	if LOGGER:
		LOGGER.debug("API: show_coordinates = %s" % [str(enabled)])

## Returns a snapshot of all current overlay/display settings.
## Dict keys: "cross_guides", "perm_vertical", "perm_horizontal", "show_coordinates"
func get_settings() -> Dictionary:
	return {
		"cross_guides": _mod.cross_guides_enabled,
		"perm_vertical": _mod.perm_vertical_enabled,
		"perm_horizontal": _mod.perm_horizontal_enabled,
		"show_coordinates": _mod.show_coordinates_enabled,
	}

# ============================================================================
# TOOL CONTROL
# ============================================================================

## Activates the GuidesLines tool in Dungeondraft's toolset.
func activate_tool() -> void:
	if _mod.Global.Editor and _mod.Global.Editor.Toolset:
		_mod.Global.Editor.Toolset.Quickswitch("GuidesLinesTool")
		if LOGGER:
			LOGGER.debug("API: Tool activated")

## Returns true if the GuidesLines tool is currently the active tool.
func is_tool_active() -> bool:
	if not _mod.Global.Editor:
		return false
	return _mod.Global.Editor.ActiveToolName == "GuidesLinesTool"

## Returns true when the GuidesLines tool has been created and the API is ready
## to accept marker placement/deletion calls.
## This becomes true after a map is loaded and GuidesLines' update() has run.
func is_ready() -> bool:
	return _mod.guides_tool != null

# ============================================================================
# INTERNAL NOTIFICATION METHODS
# Called by GuidesLinesTool to propagate user actions to API signals
# ============================================================================

func _notify_marker_placed(marker_id: int, position: Vector2) -> void:
	emit_signal("marker_placed", marker_id, position)

func _notify_marker_deleted(marker_id: int) -> void:
	emit_signal("marker_deleted", marker_id)

func _notify_all_markers_deleted() -> void:
	emit_signal("all_markers_deleted")

# ============================================================================
# PRIVATE HELPERS
# ============================================================================

## Returns [map_rect, cell_size] for the current world, or [null, null] if no world loaded.
func _get_map_context(t) -> Array:
	if t.cached_world != null:
		return [t.cached_world.WorldRect, t._get_grid_cell_size()]
	return [null, null]

## Silent accessor — returns guides_tool or null without logging.
## Call only after _has_tool() has confirmed readiness.
func _tool():
	return _mod.guides_tool

func _has_tool() -> bool:
	if _tool() == null:
		if LOGGER:
			LOGGER.warn("API: Tool not ready yet (map not loaded?)")
		return false
	return true

## Build a public-facing marker dict from a GuideMarker instance.
## Equivalent to marker.Save() with position already as Vector2.
func _marker_save_with_pos(marker) -> Dictionary:
	var d = marker.Save()
	d["position"] = marker.position
	return d

## Returns the perpendicular distance from point [p] to the infinite ray
## defined by [origin] and normalized [direction].
func _dist_point_to_ray(p: Vector2, origin: Vector2, direction: Vector2) -> float:
	return GeometryUtils.dist_point_to_ray(p, origin, direction)

## Returns the distance from point [p] to the closest point on segment [a]→[b].
func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return GeometryUtils.dist_point_to_segment(p, a, b)

## Returns the closest point on segment [a]→[b] to point [p].
func _closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	return GeometryUtils.closest_point_on_segment(p, a, b)

## Intersects an infinite line (lp + t*ld, ld must be normalised) with segment
## [a]→[b].  Returns the intersection Vector2 or null if parallel / miss.
func _line_intersect_segment(lp: Vector2, ld: Vector2, a: Vector2, b: Vector2):
	return GeometryUtils.line_intersect_segment(lp, ld, a, b)
