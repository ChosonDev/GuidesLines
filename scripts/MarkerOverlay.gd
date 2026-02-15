extends Node2D

# MarkerOverlay - Handles drawing and input for guide markers

var tool = null

# Calculate polygon vertices for regular n-gon inscribed in circle
# center: center point, radius: circumradius, sides: number of sides
# rotation_offset: rotation in radians (default 0, for "point up" orientation)
func _calculate_polygon_vertices(center, radius, sides, rotation_offset = 0.0):
	var vertices = []
	var angle_step = TAU / sides
	
	for i in range(sides):
		var angle = angle_step * i + rotation_offset
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		vertices.append(point)
	
	return vertices

# Helper to draw polygon outline from vertices
func _draw_polygon_outline(vertices, color, line_width):
	for i in range(vertices.size()):
		var start = vertices[i]
		var end = vertices[(i + 1) % vertices.size()]
		draw_line(start, end, color, line_width)

func _ready():
	set_process_input(true)
	set_process(true)

# Continuously update mouse position for path preview
func _process(_delta):
	# Always update to keep markers visible
	update()
	
	# Track mouse position for path preview
	if tool and tool.path_placement_active and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		tool.path_preview_point = tool.cached_worldui.MousePosition
	
	# Track mouse position for arrow preview
	if tool and tool.arrow_placement_active and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		tool.arrow_preview_point = tool.cached_worldui.MousePosition

# Handle mouse input for placing markers
func _input(event):
	if not tool or not tool.is_enabled:
		return
	
	# Handle RIGHT-CLICK for Path finalization or Arrow cancellation
	if event is InputEventMouseButton and event.button_index == BUTTON_RIGHT:
		if tool.path_placement_active and event.pressed:
			tool._finalize_path_marker(false)  # Finish as open path
			get_tree().set_input_as_handled()
			return
		# Cancel arrow placement if first point is placed
		if tool.arrow_placement_active and event.pressed:
			tool._cancel_arrow_placement()
			get_tree().set_input_as_handled()
			return
	
	# Handle ESC key for Path cancellation
	if event is InputEventKey and event.scancode == KEY_ESCAPE and event.pressed:
		if tool.path_placement_active:
			tool._cancel_path_placement()
			get_tree().set_input_as_handled()
			return
		# Handle ESC key for Arrow cancellation
		if tool.arrow_placement_active:
			tool._cancel_arrow_placement()
			get_tree().set_input_as_handled()
			return
	
	# Handle mouse wheel for parameter adjustment
	if event is InputEventMouseButton:
		# Ignore if CTRL is held (used for zoom)
		if not event.control:
			# Line type: adjust angle
			if tool.active_marker_type == tool.MARKER_TYPE_LINE:
				if event.button_index == BUTTON_WHEEL_UP and event.pressed:
					if tool.LOGGER:
						tool.LOGGER.debug("MarkerOverlay: Mouse wheel UP detected (Line)")
					tool.adjust_angle_with_wheel(1)
					get_tree().set_input_as_handled()
					return
				elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
					if tool.LOGGER:
						tool.LOGGER.debug("MarkerOverlay: Mouse wheel DOWN detected (Line)")
					tool.adjust_angle_with_wheel(-1)
					get_tree().set_input_as_handled()
					return
			
			# Shape type: adjust radius
			elif tool.active_marker_type == tool.MARKER_TYPE_SHAPE:
				if event.button_index == BUTTON_WHEEL_UP and event.pressed:
					if tool.LOGGER:
						tool.LOGGER.debug("MarkerOverlay: Mouse wheel UP detected (Shape)")
					tool.adjust_shape_radius_with_wheel(1)
					get_tree().set_input_as_handled()
					return
				elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
					if tool.LOGGER:
						tool.LOGGER.debug("MarkerOverlay: Mouse wheel DOWN detected (Shape)")
					tool.adjust_shape_radius_with_wheel(-1)
					get_tree().set_input_as_handled()
					return
		
		# Handle left click for placing/deleting markers
		if event.button_index == BUTTON_LEFT and event.pressed:
			# Check if click is inside world bounds
			if tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
				# Get mouse position in viewport coordinates
				var mouse_pos = get_viewport().get_mouse_position()
				
				# Check if mouse is over the tool panel (left side of screen)
				if mouse_pos.x < 450:
					return
				
				var pos = tool.cached_worldui.MousePosition
				
				if tool.LOGGER:
					tool.LOGGER.debug("MarkerOverlay: Mouse clicked at %s, delete_mode: %s" % [pos, str(tool.delete_mode)])
				
				# If in delete mode, try to delete marker
				if tool.delete_mode:
					tool.delete_marker_at_position(pos, 20.0)
				else:
					# Otherwise place new marker
					tool.place_marker(pos)
				
				update()  # Request redraw

# Draw all markers and their guide lines
# Also draws preview marker at cursor position
func _draw():
	if not tool:
		return
	
	var camera = tool.cached_camera
	if not camera:
		return
	
	var cam_pos = camera.get_camera_position()
	var cam_zoom = camera.zoom
	var vp_rect = get_viewport_rect()
	
	var world_width = vp_rect.size.x * cam_zoom.x
	var world_height = vp_rect.size.y * cam_zoom.y
	var world_left = cam_pos.x - world_width * 0.5
	var world_right = cam_pos.x + world_width * 0.5
	var world_top = cam_pos.y - world_height * 0.5
	var world_bottom = cam_pos.y + world_height * 0.5
	
	# Draw all markers
	for marker in tool.markers:
		if not marker:
			continue
		
		_draw_custom_marker(marker, world_left, world_right, world_top, world_bottom, cam_zoom)
	
	# Draw preview marker at cursor (only when tool is active and NOT in delete mode)
	if tool.is_enabled and not tool.delete_mode and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		# Special preview for Path type
		if tool.active_marker_type == tool.MARKER_TYPE_PATH:
			_draw_path_preview(world_left, world_right, world_top, world_bottom)
		# Special preview for Arrow type
		elif tool.active_marker_type == tool.MARKER_TYPE_ARROW:
			_draw_arrow_preview(world_left, world_right, world_top, world_bottom)
		else:
			var preview_pos = tool.cached_worldui.MousePosition
			_draw_custom_marker_preview(preview_pos, world_left, world_right, world_top, world_bottom)

# Draw a single custom marker with its line(s) or circle
func _draw_custom_marker(marker, world_left, world_right, world_top, world_bottom, cam_zoom):
	var MARKER_SIZE = marker.MARKER_SIZE
	var MARKER_COLOR = marker.MARKER_COLOR
	var LINE_WIDTH = marker.LINE_WIDTH
	
	# Draw based on marker type
	if marker.marker_type == "Line":
		# Draw line(s)
		var angles = [marker.angle]
		if marker.mirror:
			angles.append(fmod(marker.angle + 180.0, 360.0))
		
		for angle in angles:
			var line_points = _calculate_line_endpoints(
				marker.position,
				angle,
				world_left,
				world_right,
				world_top,
				world_bottom
			)
			
			draw_line(
				line_points[0],
				line_points[1],
				marker.color,
				LINE_WIDTH
			)
	
	elif marker.marker_type == "Shape":
		# Draw shape based on subtype
		var cell_size = _get_grid_cell_size()
		if cell_size:
			var radius_px = marker.shape_radius * min(cell_size.x, cell_size.y)
			var angle_rad = deg2rad(marker.shape_angle)  # Convert shape rotation angle to radians
			
			match marker.shape_subtype:
				"Circle":
					draw_arc(
						marker.position,
						radius_px,
						0,
						TAU,
						64,
						marker.color,
						LINE_WIDTH,
						true
					)
				
				"Square":
					var vertices = _calculate_polygon_vertices(marker.position, radius_px, 4, PI/4 + angle_rad)
					_draw_polygon_outline(vertices, marker.color, LINE_WIDTH)
				
				"Pentagon":
					var vertices = _calculate_polygon_vertices(marker.position, radius_px, 5, -PI/2 + angle_rad)
					_draw_polygon_outline(vertices, marker.color, LINE_WIDTH)
				
				"Hexagon":
					var vertices = _calculate_polygon_vertices(marker.position, radius_px, 6, angle_rad)
					_draw_polygon_outline(vertices, marker.color, LINE_WIDTH)
				
				"Octagon":
					var vertices = _calculate_polygon_vertices(marker.position, radius_px, 8, PI/8 + angle_rad)
					_draw_polygon_outline(vertices, marker.color, LINE_WIDTH)
	
	elif marker.marker_type == "Path":
		# Draw path lines
		if marker.marker_points.size() >= 2:
			for i in range(marker.marker_points.size() - 1):
				draw_line(
					marker.marker_points[i],
					marker.marker_points[i + 1],
					marker.color,
					LINE_WIDTH
				)
			
			# Close path if enabled
			if marker.path_closed and marker.marker_points.size() >= 3:
				draw_line(
					marker.marker_points[marker.marker_points.size() - 1],
					marker.marker_points[0],
					marker.color,
					LINE_WIDTH
				)
	
	elif marker.marker_type == "Arrow":
		# Draw arrow (always 2 points)
		if marker.marker_points.size() == 2:
			var start = marker.marker_points[0]
			var end = marker.marker_points[1]
			
			# Draw main line
			draw_line(start, end, marker.color, LINE_WIDTH)
			
			# Draw arrowhead
			_draw_arrowhead(end, start, marker.arrow_head_length, marker.arrow_head_angle, marker.color, LINE_WIDTH)
	
	# Draw marker circle on top
	draw_circle(marker.position, MARKER_SIZE / 2.0, MARKER_COLOR)
	draw_arc(marker.position, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 1), 2)
	
	# Draw coordinates if enabled for this marker
	if marker.show_coordinates:
		_draw_marker_coordinates(marker, cam_zoom, world_left, world_right, world_top, world_bottom)

# Draw semi-transparent preview of marker at cursor position
func _draw_custom_marker_preview(pos, world_left, world_right, world_top, world_bottom):
	var MARKER_SIZE = 40.0
	var MARKER_COLOR = Color(1, 0, 0, 0.5)
	var LINE_COLOR = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)
	var LINE_WIDTH = 8.0
	
	# Draw preview based on active marker type
	if tool.active_marker_type == tool.MARKER_TYPE_LINE:
		# Draw preview line(s)
		var angles = [tool.active_angle]
		if tool.active_mirror:
			angles.append(fmod(tool.active_angle + 180.0, 360.0))
		
		for angle in angles:
			var line_points = _calculate_line_endpoints(
				pos,
				angle,
				world_left,
				world_right,
				world_top,
				world_bottom
			)
			
			draw_line(
				line_points[0],
				line_points[1],
				LINE_COLOR,
				LINE_WIDTH
			)
	
	elif tool.active_marker_type == tool.MARKER_TYPE_SHAPE:
		# Draw preview shape
		var cell_size = _get_grid_cell_size()
		if cell_size:
			var radius_px = tool.active_shape_radius * min(cell_size.x, cell_size.y)
			var angle_rad = deg2rad(tool.active_shape_angle)  # Convert shape rotation angle to radians
			
			match tool.active_shape_subtype:
				"Circle":
					draw_arc(
						pos,
						radius_px,
						0,
						TAU,
						64,
						LINE_COLOR,
						LINE_WIDTH,
						true
					)
				
				"Square":
					var vertices = _calculate_polygon_vertices(pos, radius_px, 4, PI/4 + angle_rad)
					_draw_polygon_outline(vertices, LINE_COLOR, LINE_WIDTH)
				
				"Pentagon":
					var vertices = _calculate_polygon_vertices(pos, radius_px, 5, -PI/2 + angle_rad)
					_draw_polygon_outline(vertices, LINE_COLOR, LINE_WIDTH)
				
				"Hexagon":
					var vertices = _calculate_polygon_vertices(pos, radius_px, 6, angle_rad)
					_draw_polygon_outline(vertices, LINE_COLOR, LINE_WIDTH)
				
				"Octagon":
					var vertices = _calculate_polygon_vertices(pos, radius_px, 8, PI/8 + angle_rad)
					_draw_polygon_outline(vertices, LINE_COLOR, LINE_WIDTH)
	
	# Draw preview marker
	draw_circle(pos, MARKER_SIZE / 2.0, MARKER_COLOR)
	draw_arc(pos, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 2)

# Draw preview for Path type (temp points + line to cursor)
func _draw_path_preview(world_left, world_right, world_top, world_bottom):
	if not tool.path_placement_active or tool.path_temp_points.size() == 0:
		return
	
	var MARKER_SIZE = 40.0
	var MARKER_COLOR = Color(1, 0, 0, 0.5)  # Red semi-transparent
	var LINE_COLOR = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)
	var LINE_WIDTH = 8.0
	var PREVIEW_LINE_COLOR = Color(1, 1, 1, 0.5)  # White semi-transparent for preview line
	
	# Draw all placed points
	for i in range(tool.path_temp_points.size()):
		var point = tool.path_temp_points[i]
		
		# First point is slightly larger and different color
		if i == 0:
			draw_circle(point, MARKER_SIZE / 1.5, Color(0, 1, 0, 0.6))  # Green first point
		else:
			draw_circle(point, MARKER_SIZE / 2.0, MARKER_COLOR)
		
		# Draw outline
		draw_arc(point, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 2)
	
	# Draw lines between placed points
	if tool.path_temp_points.size() >= 2:
		for i in range(tool.path_temp_points.size() - 1):
			draw_line(
				tool.path_temp_points[i],
				tool.path_temp_points[i + 1],
				LINE_COLOR,
				LINE_WIDTH
			)
	
	# Draw preview line from last point to cursor
	if tool.path_preview_point != null and tool.path_temp_points.size() > 0:
		var last_point = tool.path_temp_points[tool.path_temp_points.size() - 1]
		draw_line(
			last_point,
			tool.path_preview_point,
			PREVIEW_LINE_COLOR,
			LINE_WIDTH * 0.7
		)
		
		# Draw cursor preview circle
		draw_circle(tool.path_preview_point, MARKER_SIZE / 3.0, Color(1, 1, 1, 0.3))
	
	# Draw "close path" indicator if near first point
	if tool.path_temp_points.size() >= 3 and tool.path_preview_point != null:
		var first_point = tool.path_temp_points[0]
		if tool.path_preview_point.distance_to(first_point) < 30.0:
			# Draw pulsing circle around first point
			var pulse = sin(OS.get_ticks_msec() * 0.005) * 0.5 + 0.5
			draw_arc(first_point, MARKER_SIZE, 0, TAU, 32, Color(0, 1, 0, 0.5 + pulse * 0.3), 4)

# Draw preview for Arrow type (temp points + line to cursor with arrowhead)
func _draw_arrow_preview(world_left, world_right, world_top, world_bottom):
	if not tool.arrow_placement_active or tool.arrow_temp_points.size() == 0:
		return
	
	var MARKER_SIZE = 40.0
	var MARKER_COLOR = Color(1, 0, 0, 0.5)  # Red semi-transparent
	var LINE_COLOR = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)
	var LINE_WIDTH = 8.0
	var PREVIEW_LINE_COLOR = Color(1, 1, 1, 0.5)  # White semi-transparent for preview line
	
	# Draw start point (green, larger)
	var start_point = tool.arrow_temp_points[0]
	draw_circle(start_point, MARKER_SIZE / 1.5, Color(0, 1, 0, 0.6))  # Green first point
	draw_arc(start_point, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 2)
	
	# If we have 1 point and cursor preview, draw preview arrow
	if tool.arrow_temp_points.size() == 1 and tool.arrow_preview_point != null:
		var preview_end = tool.arrow_preview_point
		
		# Draw preview line
		draw_line(start_point, preview_end, PREVIEW_LINE_COLOR, LINE_WIDTH * 0.7)
		
		# Draw preview arrowhead
		_draw_arrowhead(
			preview_end,
			start_point,
			tool.active_arrow_head_length,
			tool.active_arrow_head_angle,
			PREVIEW_LINE_COLOR,
			LINE_WIDTH * 0.7
		)
		
		# Draw cursor preview circle
		draw_circle(preview_end, MARKER_SIZE / 3.0, Color(1, 1, 1, 0.3))

# Draw arrowhead at the end point
# end: arrowhead position, start: direction reference point
# length: arrowhead length in pixels, angle: arrowhead angle in degrees
func _draw_arrowhead(end, start, length, angle_deg, color, line_width):
	# Calculate direction from start to end
	var direction = (end - start).normalized()
	
	# Calculate arrow angle in radians
	var angle_rad = deg2rad(angle_deg)
	
	# Calculate the two points of the arrowhead
	# Rotate direction by +/- angle_deg to get the two arrowhead lines
	var left_angle = direction.angle() + PI - angle_rad
	var right_angle = direction.angle() + PI + angle_rad
	
	var left_point = end + Vector2(cos(left_angle), sin(left_angle)) * length
	var right_point = end + Vector2(cos(right_angle), sin(right_angle)) * length
	
	# Draw the two arrowhead lines
	draw_line(end, left_point, color, line_width)
	draw_line(end, right_point, color, line_width)

# Calculate line endpoints - always draws to map boundaries
func _calculate_line_endpoints(origin, angle_deg, world_left, world_right, world_top, world_bottom):
	var angle_rad = deg2rad(angle_deg)
	var direction = Vector2(cos(angle_rad), sin(angle_rad))
	
	# Always draw infinite ray from origin to viewport edge
	return _get_ray_to_viewport_edge(origin, direction, world_left, world_right, world_top, world_bottom)

# Calculate where a ray from origin in direction intersects viewport boundaries
# Returns [origin, intersection_point] representing a ray from marker to edge
func _get_ray_to_viewport_edge(origin, direction, world_left, world_right, world_top, world_bottom):
	var dx = direction.x
	var dy = direction.y
	
	var closest_point = null
	var closest_t = INF
	
	# Check all four boundaries and find the closest intersection in the direction
	
	# Left boundary
	if dx != 0:
		var t = (world_left - origin.x) / dx
		if t > 0.01:  # Small epsilon to avoid origin point
			var y = origin.y + t * dy
			if y >= world_top and y <= world_bottom and t < closest_t:
				closest_t = t
				closest_point = Vector2(world_left, y)
	
	# Right boundary
	if dx != 0:
		var t = (world_right - origin.x) / dx
		if t > 0.01:
			var y = origin.y + t * dy
			if y >= world_top and y <= world_bottom and t < closest_t:
				closest_t = t
				closest_point = Vector2(world_right, y)
	
	# Top boundary
	if dy != 0:
		var t = (world_top - origin.y) / dy
		if t > 0.01:
			var x = origin.x + t * dx
			if x >= world_left and x <= world_right and t < closest_t:
				closest_t = t
				closest_point = Vector2(x, world_top)
	
	# Bottom boundary
	if dy != 0:
		var t = (world_bottom - origin.y) / dy
		if t > 0.01:
			var x = origin.x + t * dx
			if x >= world_left and x <= world_right and t < closest_t:
				closest_t = t
				closest_point = Vector2(x, world_bottom)
	
	# Return ray from origin to edge
	if closest_point != null:
		return [origin, closest_point]
	
	# Fallback if no intersection found
	return [origin, origin + direction * 1000]

# Draw grid coordinates along marker's guide lines or circle
func _draw_marker_coordinates(marker, cam_zoom, world_left, world_right, world_top, world_bottom):
	if not tool or not tool.cached_world:
		return
	
	var marker_pos = marker.position
	
	# Draw coordinates based on marker type
	if marker.marker_type == "Line":
		var angles = [marker.angle]
		if marker.mirror:
			angles.append(fmod(marker.angle + 180.0, 360.0))
		
		for angle in angles:
			_draw_coordinates_along_line(
				marker_pos,
				angle,
				cam_zoom,
				world_left,
				world_right,
				world_top,
				world_bottom,
				marker.color
			)
	
	elif marker.marker_type == "Shape":
		_draw_coordinates_on_shape(
			marker.position,
			marker.shape_radius,
			marker.shape_subtype,
			cam_zoom,
			marker.color
		)
	
	elif marker.marker_type == "Path":
		# Draw coordinates at each path point
		_draw_coordinates_on_path(
			marker.marker_points,
			cam_zoom,
			marker.color
		)
	
	elif marker.marker_type == "Arrow":
		# Draw coordinates at arrow start and end points
		_draw_coordinates_on_path(
			marker.marker_points,
			cam_zoom,
			marker.color
		)

# Draw coordinates along a line at any angle - always to map boundaries
func _draw_coordinates_along_line(origin, angle_deg, cam_zoom, world_left, world_right, world_top, world_bottom, line_color):
	var custom_snap = _get_custom_snap()
	
	if custom_snap and custom_snap.custom_snap_enabled:
		_draw_coords_custom_snap(origin, angle_deg, cam_zoom, world_left, world_right, world_top, world_bottom, line_color, custom_snap)
	else:
		_draw_coords_vanilla(origin, angle_deg, cam_zoom, world_left, world_right, world_top, world_bottom, line_color)

# Get custom_snap mod reference if available
func _get_custom_snap():
	if not tool:
		return null
	return tool.cached_snappy_mod

# Get grid cell size (accounting for custom_snap mod if active)
func _get_grid_cell_size():
	if not tool or not tool.cached_world:
		return null
	
	# Check if custom_snap is active and use its snap_interval
	var custom_snap = _get_custom_snap()
	if custom_snap and custom_snap.custom_snap_enabled:
		if custom_snap.has("snap_interval"):
			return custom_snap.snap_interval
	
	# Fallback to vanilla grid cell size
	if not tool.cached_world.Level or not tool.cached_world.Level.TileMap:
		return null
	return tool.cached_world.Level.TileMap.CellSize

# Draw coordinates using vanilla Dungeondraft grid - always to map boundaries
func _draw_coords_vanilla(origin, angle_deg, cam_zoom, world_left, world_right, world_top, world_bottom, line_color):
	# Get cell size (may be from custom_snap if active)
	var cell_size = _get_grid_cell_size()
	if cell_size == null or cell_size.x <= 0 or cell_size.y <= 0:
		return
	
	var marker_size = 5.0 * cam_zoom.x
	var text_offset = 20.0 * cam_zoom.x
	var marker_color = line_color
	var text_color = line_color
	
	var angle_rad = deg2rad(angle_deg)
	var direction = Vector2(cos(angle_rad), sin(angle_rad))
	
	var step = min(cell_size.x, cell_size.y)
	# Always draw to map boundaries
	var max_dist = sqrt(pow(world_right - world_left, 2) + pow(world_bottom - world_top, 2))
	var distance = step
	
	var map_rect = tool.cached_world.WorldRect
	
	while distance < max_dist:
		var test_pos = origin + direction * distance
		
		if not map_rect.has_point(test_pos):
			distance += step
			continue
		
		# Check if near grid intersection
		var grid_x = round(test_pos.x / cell_size.x)
		var grid_y = round(test_pos.y / cell_size.y)
		var grid_pos = Vector2(grid_x * cell_size.x, grid_y * cell_size.y)
		
		if test_pos.distance_to(grid_pos) < step * 0.25:
			var grid_dist = round(distance / step)
			
			# Draw marker
			draw_circle(grid_pos, marker_size, marker_color)
			
			# Draw text
			var text = str(int(grid_dist))
			var perp = Vector2(-direction.y, direction.x) * text_offset
			var text_pos = grid_pos + perp
			_draw_text_with_outline(text, text_pos, text_color)
		
		distance += step

# Draw coordinates using custom_snap grid - always to map boundaries
func _draw_coords_custom_snap(origin, angle_deg, cam_zoom, world_left, world_right, world_top, world_bottom, line_color, custom_snap):
	var marker_size = 5.0 * cam_zoom.x
	var text_offset = 20.0 * cam_zoom.x
	var marker_color = line_color
	var text_color = line_color
	
	var snap_interval = custom_snap.snap_interval
	var snap_offset = custom_snap.snap_offset
	var test_spacing = min(snap_interval.x, snap_interval.y) * 0.5
	
	var angle_rad = deg2rad(angle_deg)
	var direction = Vector2(cos(angle_rad), sin(angle_rad))
	
	# Always draw to map boundaries
	var max_dist = sqrt(pow(world_right - world_left, 2) + pow(world_bottom - world_top, 2))
	var checked_positions = {}
	var distance = test_spacing
	
	var map_rect = tool.cached_world.WorldRect
	
	while distance < max_dist:
		var test_pos = origin + direction * distance
		var snapped = custom_snap.get_snapped_position(test_pos)
		
		if not map_rect.has_point(snapped):
			distance += test_spacing
			continue
		
		var key = str(int(snapped.x * 10)) + "_" + str(int(snapped.y * 10))
		
		if not checked_positions.has(key) and snapped.distance_to(origin) > 0.5:
			# Check if snapped point is on the line
			var to_snapped = snapped - origin
			var angle_to_snapped = atan2(to_snapped.y, to_snapped.x)
			var angle_diff = abs(angle_to_snapped - angle_rad)
			
			# Normalize angle
			while angle_diff > PI:
				angle_diff -= TAU
			angle_diff = abs(angle_diff)
			if angle_diff > PI:
				angle_diff = TAU - angle_diff
			
			if angle_diff < deg2rad(10):
				checked_positions[key] = true
				
				var delta = snapped - origin - snap_offset
				var grid_dist = round(snapped.distance_to(origin) / min(snap_interval.x, snap_interval.y))
				
				# Draw marker
				draw_circle(snapped, marker_size, marker_color)
				
				# Draw text
				var text = str(int(grid_dist))
				var perp = Vector2(-direction.y, direction.x) * text_offset
				var text_pos = snapped + perp
				_draw_text_with_outline(text, text_pos, text_color)
		
		distance += test_spacing

# Draw text with outline for better visibility
func _draw_text_with_outline(text, position, color):
	var font = Control.new().get_font("font")
	var scale = 4.0  # Quadruple the text size
	
	# Draw outline (black)
	var outline_color = Color(0, 0, 0, 0.8)
	var outline_offset = 2
	for dx in [-outline_offset, 0, outline_offset]:
		for dy in [-outline_offset, 0, outline_offset]:
			if dx != 0 or dy != 0:
				draw_set_transform(position + Vector2(dx, dy), 0, Vector2(scale, scale))
				draw_string(font, Vector2.ZERO, text, outline_color, -1)
	
	# Draw main text
	draw_set_transform(position, 0, Vector2(scale, scale))
	draw_string(font, Vector2.ZERO, text, color, -1)
	
	# Reset transform
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# Draw coordinates on shape (only at center)
func _draw_coordinates_on_shape(center, radius_cells, shape_subtype, cam_zoom, shape_color):
	var cell_size = _get_grid_cell_size()
	if not cell_size or cell_size.x <= 0 or cell_size.y <= 0:
		return
	
	var marker_size = 5.0 * cam_zoom.x
	var text_offset = 20.0 * cam_zoom.x
	var marker_color = shape_color
	var text_color = shape_color
	
	# Draw single marker at center
	draw_circle(center, marker_size, marker_color)
	
	# Draw text with radius
	var text = " R=" + ("%.1f" % radius_cells)
	var text_pos = center + Vector2(0, -text_offset)  # Above center
	_draw_text_with_outline(text, text_pos, text_color)

# Draw coordinates on path points
func _draw_coordinates_on_path(points, cam_zoom, path_color):
	if points.size() < 2:
		return
	
	var marker_size = 5.0 * cam_zoom.x
	var text_offset = 20.0 * cam_zoom.x
	var marker_color = path_color
	var text_color = path_color
	
	# Get cell size for distance calculation
	var cell_size = _get_grid_cell_size()
	if not cell_size or cell_size.x <= 0 or cell_size.y <= 0:
		return
	
	# Draw marker and distance at each point
	var total_distance = 0.0
	
	for i in range(points.size()):
		var point = points[i]
		
		# Draw marker
		draw_circle(point, marker_size, marker_color)
		
		# Calculate distance from start (in grid cells)
		if i > 0:
			var prev_point = points[i - 1]
			var segment_length = point.distance_to(prev_point)
			
			var cell_dist = segment_length / min(cell_size.x, cell_size.y)
			total_distance += cell_dist
		
		# Draw text with total distance
		var text = str(int(total_distance))
		var text_pos = point + Vector2(text_offset, -text_offset)
		_draw_text_with_outline(text, text_pos, text_color)
