extends Node2D

# MarkerOverlay - Handles drawing and input for guide markers

var tool = null

func _ready():
	set_process_input(true)
	set_process(true)

# Continuously request redraw to keep markers visible
func _process(_delta):
	# Always update to keep markers visible
	update()

# Handle mouse input for placing markers
func _input(event):
	if not tool or not tool.is_enabled:
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
			
			# Circle type: adjust radius
			elif tool.active_marker_type == tool.MARKER_TYPE_CIRCLE:
				if event.button_index == BUTTON_WHEEL_UP and event.pressed:
					if tool.LOGGER:
						tool.LOGGER.debug("MarkerOverlay: Mouse wheel UP detected (Circle)")
					tool.adjust_circle_radius_with_wheel(1)
					get_tree().set_input_as_handled()
					return
				elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
					if tool.LOGGER:
						tool.LOGGER.debug("MarkerOverlay: Mouse wheel DOWN detected (Circle)")
					tool.adjust_circle_radius_with_wheel(-1)
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
				marker.line_range,
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
	
	elif marker.marker_type == "Circle":
		# Draw circle
		var cell_size = _get_grid_cell_size()
		if cell_size:
			var radius_px = marker.circle_radius * min(cell_size.x, cell_size.y)
			draw_arc(
				marker.position,
				radius_px,
				0,
				TAU,
				64,  # 64 points for smooth circle
				marker.color,
				LINE_WIDTH,
				true  # antialiased
			)
	
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
				tool.active_line_range,
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
	
	elif tool.active_marker_type == tool.MARKER_TYPE_CIRCLE:
		# Draw preview circle
		var cell_size = _get_grid_cell_size()
		if cell_size:
			var radius_px = tool.active_circle_radius * min(cell_size.x, cell_size.y)
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
	
	# Draw preview marker
	draw_circle(pos, MARKER_SIZE / 2.0, MARKER_COLOR)
	draw_arc(pos, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 2)

# Calculate line endpoints based on angle, range, and viewport bounds
func _calculate_line_endpoints(origin, angle_deg, range_cells, world_left, world_right, world_top, world_bottom):
	var angle_rad = deg2rad(angle_deg)
	var direction = Vector2(cos(angle_rad), sin(angle_rad))
	
	if range_cells <= 0:
		# Infinite ray - from origin to viewport edge in direction
		return _get_ray_to_viewport_edge(origin, direction, world_left, world_right, world_top, world_bottom)
	else:
		# Finite line - convert grid cells to pixels
		var cell_size = _get_grid_cell_size()
		if cell_size == null:
			return [origin, origin]
		var range_px = range_cells * min(cell_size.x, cell_size.y)
		var end_point = origin + direction * range_px
		return [origin, end_point]

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
				marker.line_range,
				cam_zoom,
				world_left,
				world_right,
				world_top,
				world_bottom,
				marker.color
			)
	
	elif marker.marker_type == "Circle":
		_draw_coordinates_on_circle(
			marker_pos,
			marker.circle_radius,
			cam_zoom,
			marker.color
		)

# Draw coordinates along a line at any angle
func _draw_coordinates_along_line(origin, angle_deg, range_cells, cam_zoom, world_left, world_right, world_top, world_bottom, line_color):
	var custom_snap = _get_custom_snap()
	
	if custom_snap and custom_snap.custom_snap_enabled:
		_draw_coords_custom_snap(origin, angle_deg, range_cells, cam_zoom, world_left, world_right, world_top, world_bottom, line_color, custom_snap)
	else:
		_draw_coords_vanilla(origin, angle_deg, range_cells, cam_zoom, world_left, world_right, world_top, world_bottom, line_color)

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

# Draw coordinates using vanilla Dungeondraft grid
func _draw_coords_vanilla(origin, angle_deg, range_cells, cam_zoom, world_left, world_right, world_top, world_bottom, line_color):
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
	var range_px = range_cells * step if range_cells > 0 else 0
	var max_dist = range_px if range_px > 0 else sqrt(pow(world_right - world_left, 2) + pow(world_bottom - world_top, 2))
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

# Draw coordinates using custom_snap grid
func _draw_coords_custom_snap(origin, angle_deg, range_cells, cam_zoom, world_left, world_right, world_top, world_bottom, line_color, custom_snap):
	var marker_size = 5.0 * cam_zoom.x
	var text_offset = 20.0 * cam_zoom.x
	var marker_color = line_color
	var text_color = line_color
	
	var snap_interval = custom_snap.snap_interval
	var snap_offset = custom_snap.snap_offset
	var test_spacing = min(snap_interval.x, snap_interval.y) * 0.5
	
	var angle_rad = deg2rad(angle_deg)
	var direction = Vector2(cos(angle_rad), sin(angle_rad))
	
	var range_px = range_cells * min(snap_interval.x, snap_interval.y) if range_cells > 0 else 0
	var max_dist = range_px if range_px > 0 else sqrt(pow(world_right - world_left, 2) + pow(world_bottom - world_top, 2))
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

# Draw coordinates on circle (at cardinal points: N, S, E, W)
func _draw_coordinates_on_circle(center, radius_cells, cam_zoom, circle_color):
	var cell_size = _get_grid_cell_size()
	if not cell_size or cell_size.x <= 0 or cell_size.y <= 0:
		return
	
	var marker_size = 5.0 * cam_zoom.x
	var text_offset = 20.0 * cam_zoom.x
	var marker_color = circle_color
	var text_color = circle_color
	
	var radius_px = radius_cells * min(cell_size.x, cell_size.y)
	
	# Draw markers at 4 cardinal directions (0°, 90°, 180°, 270°)
	var cardinal_angles = [0, 90, 180, 270]  # East, North, West, South
	
	for angle_deg in cardinal_angles:
		var angle_rad = deg2rad(angle_deg)
		var direction = Vector2(cos(angle_rad), sin(angle_rad))
		var point = center + direction * radius_px
		
		# Draw marker
		draw_circle(point, marker_size, marker_color)
		
		# Draw text with radius value
		var text = "R=" + ("%.1f" % radius_cells)
		var text_offset_dir = direction * text_offset
		var text_pos = point + text_offset_dir
		_draw_text_with_outline(text, text_pos, text_color)
