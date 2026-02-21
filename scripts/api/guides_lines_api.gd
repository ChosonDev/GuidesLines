extends Reference

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
	var tool = _mod.guides_tool
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
##   subtype  — one of "Circle", "Square", "Pentagon", "Hexagon", "Octagon", "Custom"
##   radius   — circumradius in grid cells (default 1.0)
##   angle    — rotation in degrees (default 0.0)
##   sides    — number of sides for "Custom" subtype (default 6)
##   color    — marker color (default active color)
func place_shape_marker(position: Vector2, subtype: String = "Circle", radius: float = 1.0,
						angle: float = 0.0, sides: int = 6, color = null) -> int:
	if not _has_tool():
		return -1
	var tool = _mod.guides_tool
	var marker_id = tool.next_id
	var marker_data = {
		"position": position,
		"marker_type": "Shape",
		"color": color if color != null else tool.active_color,
		"coordinates": tool.show_coordinates,
		"id": marker_id,
		"shape_subtype": subtype,
		"shape_radius": radius,
		"shape_angle": angle,
		"shape_sides": sides,
	}
	tool.api_place_marker(marker_data)
	if LOGGER:
		LOGGER.debug("API: Shape marker placed id=%d pos=%s subtype=%s" % [marker_id, str(position), subtype])
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
	var tool = _mod.guides_tool
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
	var tool = _mod.guides_tool
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
	var result = _mod.guides_tool.api_delete_marker_by_id(marker_id)
	if not result and LOGGER:
		LOGGER.warn("API: delete_marker — id %d not found" % [marker_id])
	return result

## Deletes all markers on the map. Supports undo.
func delete_all_markers() -> void:
	if not _has_tool():
		return
	_mod.guides_tool.delete_all_markers()
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
	for marker in _mod.guides_tool.markers:
		var d = marker.Save()
		# Convert serialized position back to Vector2 for convenience
		d["position"] = marker.position
		result.append(d)
	return result

## Returns a single marker Dictionary by id, or null if not found.
## Dict format is the same as for get_markers().
func get_marker(marker_id: int):
	if not _has_tool():
		return null
	var tool = _mod.guides_tool
	if not tool.markers_lookup.has(marker_id):
		return null
	var marker = tool.markers_lookup[marker_id]
	var d = marker.Save()
	d["position"] = marker.position
	return d

## Returns the total number of markers currently on the map.
func get_marker_count() -> int:
	if not _has_tool():
		return 0
	return _mod.guides_tool.markers.size()

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
	for marker in _mod.guides_tool.markers:
		var dist = marker.position.distance_to(coords)
		if dist <= nearest_dist:
			nearest_dist = dist
			nearest_marker = marker
	if nearest_marker == null:
		if LOGGER:
			LOGGER.debug("API: find_nearest_marker — nothing found within radius %.1f of %s" % [radius, str(coords)])
		return null
	var d = nearest_marker.Save()
	d["position"] = nearest_marker.position
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
	var tool = _mod.guides_tool

	# Gather map_rect and cell_size needed for Line / Shape draw data
	var map_rect = null
	var cell_size = null
	if tool.cached_world != null:
		map_rect = tool.cached_world.WorldRect
		cell_size = tool._get_grid_cell_size()

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
				if draw_data.has("shape_type"):
					if draw_data["shape_type"] == "circle" and draw_data.has("radius"):
						# Closest point on circumference
						var to_marker = coords - marker.position
						var to_len = to_marker.length()
						var pt
						if to_len > 1e-10:
							pt = marker.position + to_marker / to_len * draw_data["radius"]
						else:
							pt = marker.position + Vector2(draw_data["radius"], 0)
						var d = coords.distance_to(pt)
						if d < min_dist:
							min_dist = d
							min_point = pt
					elif draw_data["shape_type"] == "poly" and draw_data.has("points"):
						var pts = draw_data["points"]
						# Nearest edge point
						for i in range(pts.size()):
							var pt = _closest_point_on_segment(coords, pts[i], pts[(i + 1) % pts.size()])
							var d = coords.distance_to(pt)
							if d < min_dist:
								min_dist = d
								min_point = pt
						# Nearest vertex
						var best_vdist = INF
						for v in pts:
							var vd = coords.distance_to(v)
							if vd < best_vdist:
								best_vdist = vd
								min_vertex = v

			"Path":
				var pts = marker.marker_points
				if pts.size() >= 2:
					var edge_count = pts.size() - 1
					if marker.path_closed:
						edge_count = pts.size()  # last edge wraps back to pts[0]
					# Nearest edge point
					for i in range(edge_count):
						var pt = _closest_point_on_segment(coords, pts[i], pts[(i + 1) % pts.size()])
						var d = coords.distance_to(pt)
						if d < min_dist:
							min_dist = d
							min_point = pt
					# Nearest vertex
					var best_vdist = INF
					for v in pts:
						var vd = coords.distance_to(v)
						if vd < best_vdist:
							best_vdist = vd
							min_vertex = v

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
	var d = nearest_marker.Save()
	d["position"] = nearest_marker.position
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
	var tool = _mod.guides_tool

	var map_rect = null
	var cell_size = null
	if tool.cached_world != null:
		map_rect = tool.cached_world.WorldRect
		cell_size = tool._get_grid_cell_size()

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
				if draw_data.has("shape_type"):
					if draw_data["shape_type"] == "circle" and draw_data.has("radius"):
						for pt in _line_intersect_circle(line_from, line_dir, marker.position, draw_data["radius"]):
							candidates.append(pt)
					elif draw_data["shape_type"] == "poly" and draw_data.has("points"):
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

	var result = best_marker.Save()
	result["position"]    = best_marker.position
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
	var tool = _mod.guides_tool

	var map_rect = null
	var cell_size = null
	if tool.cached_world != null:
		map_rect = tool.cached_world.WorldRect
		cell_size = tool._get_grid_cell_size()

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
				if draw_data.has("shape_type"):
					if draw_data["shape_type"] == "circle" and draw_data.has("radius"):
						# Closest point on circumference
						var to_marker = coords - marker.position
						var to_len = to_marker.length()
						if to_len > 1e-10:
							candidates.append(marker.position + to_marker / to_len * draw_data["radius"])
						else:
							# coords is exactly at center — pick arbitrary point on circle
							candidates.append(marker.position + Vector2(draw_data["radius"], 0))
					elif draw_data["shape_type"] == "poly" and draw_data.has("points"):
						var pts = draw_data["points"]
						for i in range(pts.size()):
							candidates.append(_closest_point_on_segment(coords, pts[i], pts[(i + 1) % pts.size()]))

			"Path":
				if marker.position.distance_to(coords) > radius:
					continue
				var pts = marker.marker_points
				if pts.size() >= 2:
					var edge_count = pts.size() - 1
					if marker.path_closed:
						edge_count = pts.size()
					for i in range(edge_count):
						candidates.append(_closest_point_on_segment(coords, pts[i], pts[(i + 1) % pts.size()]))

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

	var result = best_marker.Save()
	result["position"]    = best_marker.position
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
		_mod.guides_tool.set_show_coordinates(enabled)
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

func _has_tool() -> bool:
	if _mod.guides_tool == null:
		if LOGGER:
			LOGGER.warn("API: Tool not ready yet (map not loaded?)")
		return false
	return true

## Returns the distance from point [p] to the closest point on segment [a]→[b].
func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var len_sq = ab.length_squared()
	if len_sq == 0.0:
		return p.distance_to(a)
	var t = clamp((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Returns the closest point on segment [a]→[b] to point [p].
func _closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab = b - a
	var len_sq = ab.length_squared()
	if len_sq == 0.0:
		return a
	var t = clamp((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t

## Intersects an infinite line (lp + t*ld, ld must be normalised) with segment
## [a]→[b].  Returns the intersection Vector2 or null if parallel / miss.
func _line_intersect_segment(lp: Vector2, ld: Vector2, a: Vector2, b: Vector2):
	var ab    = b - a
	var denom = ab.x * ld.y - ab.y * ld.x   # cross(ab, ld)
	if abs(denom) < 1e-10:
		return null  # parallel
	var diff = lp - a
	var s = (diff.x * ld.y - diff.y * ld.x) / denom  # cross(diff, ld) / cross(ab, ld)
	if s < -1e-6 or s > 1.0 + 1e-6:
		return null
	return a + ab * clamp(s, 0.0, 1.0)

## Intersects an infinite line (lp + t*ld, ld must be normalised) with a circle.
## Returns an Array of 0, 1, or 2 Vector2 intersection points.
func _line_intersect_circle(lp: Vector2, ld: Vector2, center: Vector2, r: float) -> Array:
	var to_center = center - lp
	var proj      = to_center.dot(ld)
	var closest   = lp + ld * proj
	var dist_sq   = (center - closest).length_squared()
	var r_sq      = r * r
	if dist_sq > r_sq + 1e-10:
		return []
	var half_chord = sqrt(max(0.0, r_sq - dist_sq))
	if half_chord < 1e-5:
		return [closest]
	return [closest - ld * half_chord, closest + ld * half_chord]
