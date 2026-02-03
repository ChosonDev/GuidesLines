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
	
	# Handle mouse button press
	if event is InputEventMouseButton:
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
		
		var MARKER_SIZE = marker.MARKER_SIZE
		var MARKER_COLOR = marker.MARKER_COLOR
		var LINE_COLOR = marker.LINE_COLOR
		var LINE_WIDTH = marker.LINE_WIDTH
		
		# Draw guide lines first (behind marker)
		if marker.has_type("vertical"):
			draw_line(
				Vector2(marker.position.x, world_top),
				Vector2(marker.position.x, world_bottom),
				LINE_COLOR,
				LINE_WIDTH
			)
		
		if marker.has_type("horizontal"):
			draw_line(
				Vector2(world_left, marker.position.y),
				Vector2(world_right, marker.position.y),
				LINE_COLOR,
				LINE_WIDTH
			)
		
		if marker.has_type("diagonal_left"):
			# 135° - from top-left to bottom-right
			var diag_points = _get_diagonal_line_points(marker.position, 135, world_left, world_right, world_top, world_bottom)
			draw_line(diag_points[0], diag_points[1], LINE_COLOR, LINE_WIDTH)
		
		if marker.has_type("diagonal_right"):
			# 45° - from top-right to bottom-left
			var diag_points = _get_diagonal_line_points(marker.position, 45, world_left, world_right, world_top, world_bottom)
			draw_line(diag_points[0], diag_points[1], LINE_COLOR, LINE_WIDTH)
		
		# Draw marker circle on top
		draw_circle(marker.position, MARKER_SIZE / 2.0, MARKER_COLOR)
		draw_arc(marker.position, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 1), 2)
		
		# Draw coordinates if enabled for this marker
		if marker.show_coordinates:
			_draw_marker_coordinates(marker, cam_zoom, world_left, world_right, world_top, world_bottom)
	
	# Draw preview marker at cursor (only when tool is active and NOT in delete mode)
	if tool.is_enabled and not tool.delete_mode and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		var preview_pos = tool.cached_worldui.MousePosition
		_draw_marker_preview(preview_pos, tool.active_marker_types, world_left, world_right, world_top, world_bottom)

# Draw semi-transparent preview of marker at cursor position
# Shows what the marker will look like before placement
func _draw_marker_preview(pos, types, world_left, world_right, world_top, world_bottom):
	var MARKER_SIZE = 40.0  # Match marker size
	var MARKER_COLOR = Color(1, 0, 0, 0.5)  # Red semi-transparent
	var LINE_COLOR = Color(1, 0, 0, 0.7)  # Red semi-transparent for visibility
	var LINE_WIDTH = 8.0  # Thicker preview lines
	
	# Draw preview marker
	draw_circle(pos, MARKER_SIZE / 2.0, MARKER_COLOR)
	draw_arc(pos, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 2)
	
	# Draw preview lines based on active types
	if types.has("vertical"):
		draw_line(
			Vector2(pos.x, world_top),
			Vector2(pos.x, world_bottom),
			LINE_COLOR,
			LINE_WIDTH
		)
	
	if types.has("horizontal"):
		draw_line(
			Vector2(world_left, pos.y),
			Vector2(world_right, pos.y),
			LINE_COLOR,
			LINE_WIDTH
		)
	
	if types.has("diagonal_left"):
		var diag_points = _get_diagonal_line_points(pos, 135, world_left, world_right, world_top, world_bottom)
		draw_line(diag_points[0], diag_points[1], LINE_COLOR, LINE_WIDTH)
	
	if types.has("diagonal_right"):
		var diag_points = _get_diagonal_line_points(pos, 45, world_left, world_right, world_top, world_bottom)
		draw_line(diag_points[0], diag_points[1], LINE_COLOR, LINE_WIDTH)

# Calculate diagonal line endpoints from viewport edges
# Draws line at specified angle through center point
func _get_diagonal_line_points(center, angle_deg, world_left, world_right, world_top, world_bottom):
	# Calculate diagonal line from edge to edge through center point
	var angle_rad = deg2rad(angle_deg)
	var dx = cos(angle_rad)
	var dy = sin(angle_rad)
	
	# Find intersections with world boundaries
	var points = []
	
	# Calculate where line intersects each boundary
	# Left boundary
	if dx != 0:
		var t_left = (world_left - center.x) / dx
		var y_left = center.y + t_left * dy
		if y_left >= world_top and y_left <= world_bottom:
			points.append(Vector2(world_left, y_left))
	
	# Right boundary
	if dx != 0:
		var t_right = (world_right - center.x) / dx
		var y_right = center.y + t_right * dy
		if y_right >= world_top and y_right <= world_bottom:
			points.append(Vector2(world_right, y_right))
	
	# Top boundary
	if dy != 0:
		var t_top = (world_top - center.y) / dy
		var x_top = center.x + t_top * dx
		if x_top >= world_left and x_top <= world_right:
			points.append(Vector2(x_top, world_top))
	
	# Bottom boundary
	if dy != 0:
		var t_bottom = (world_bottom - center.y) / dy
		var x_bottom = center.x + t_bottom * dx
		if x_bottom >= world_left and x_bottom <= world_right:
			points.append(Vector2(x_bottom, world_bottom))
	
	# Return the two furthest points (should be exactly 2)
	if points.size() >= 2:
		return [points[0], points[points.size() - 1]]
	
	# Fallback
	return [center, center]

# Draw grid coordinates along marker's guide lines
func _draw_marker_coordinates(marker, cam_zoom, world_left, world_right, world_top, world_bottom):
	if not tool or not tool.cached_world:
		return
	
	var marker_cx = marker.position.x
	var marker_cy = marker.position.y
	
	# Try to use custom_snap if available
	var custom_snap = _get_custom_snap()
	
	if custom_snap and custom_snap.custom_snap_enabled:
		_draw_custom_snap_coordinates(marker_cx, marker_cy, world_left, world_right, world_top, world_bottom, cam_zoom, custom_snap, marker)
	else:
		_draw_vanilla_coordinates(marker_cx, marker_cy, world_left, world_right, world_top, world_bottom, cam_zoom, marker)

# Get custom_snap mod reference if available
func _get_custom_snap():
	if not tool:
		return null
	return tool.cached_snappy_mod

# Draw coordinates using vanilla Dungeondraft grid
func _draw_vanilla_coordinates(marker_cx, marker_cy, world_left, world_right, world_top, world_bottom, cam_zoom, marker):
	# Get grid cell size
	if not tool.cached_world.Level or not tool.cached_world.Level.TileMap:
		return
	
	var cell_size = tool.cached_world.Level.TileMap.CellSize
	if cell_size == null or cell_size.x <= 0 or cell_size.y <= 0:
		return
	
	# Configuration - same as permanent overlay
	var marker_size = 5.0 * cam_zoom.x
	var text_offset = 20.0 * cam_zoom.x
	var marker_color = Color(0, 0.7, 1, 1)  # Blue
	var text_color = Color(0, 0.7, 1, 1)
	
	# Get map boundaries
	var map_rect = tool.cached_world.WorldRect
	
	# Draw vertical line coordinates
	if marker.has_type("vertical"):
		var start_y = floor((world_top - marker_cy) / cell_size.y) * cell_size.y + marker_cy
		var y = start_y
		
		while y <= world_bottom:
			if abs(y - marker_cy) > 0.1:  # Skip center point
				var pos = Vector2(marker_cx, y)
				if map_rect.has_point(pos):
					var grid_y = round((y - marker_cy) / cell_size.y)
					draw_circle(pos, marker_size, marker_color)
					var text = str(abs(int(grid_y)))
					var text_pos = Vector2(marker_cx + text_offset, y)
					_draw_text_with_outline(text, text_pos, text_color)
			y += cell_size.y
	
	# Draw horizontal line coordinates
	if marker.has_type("horizontal"):
		var start_x = floor((world_left - marker_cx) / cell_size.x) * cell_size.x + marker_cx
		var x = start_x
		
		while x <= world_right:
			if abs(x - marker_cx) > 0.1:  # Skip center point
				var pos = Vector2(x, marker_cy)
				if map_rect.has_point(pos):
					var grid_x = round((x - marker_cx) / cell_size.x)
					draw_circle(pos, marker_size, marker_color)
					var text = str(abs(int(grid_x)))
					var text_pos = Vector2(x, marker_cy - text_offset)
					_draw_text_with_outline(text, text_pos, text_color)
			x += cell_size.x
	
	# Draw diagonal left coordinates (135°)
	if marker.has_type("diagonal_left"):
		_draw_diagonal_coordinates_vanilla(marker, marker_cx, marker_cy, cell_size, 135, world_left, world_right, world_top, world_bottom, map_rect, marker_size, text_offset, marker_color, text_color)
	
	# Draw diagonal right coordinates (45°)
	if marker.has_type("diagonal_right"):
		_draw_diagonal_coordinates_vanilla(marker, marker_cx, marker_cy, cell_size, 45, world_left, world_right, world_top, world_bottom, map_rect, marker_size, text_offset, marker_color, text_color)

# Draw coordinates using custom_snap grid
func _draw_custom_snap_coordinates(marker_cx, marker_cy, world_left, world_right, world_top, world_bottom, cam_zoom, custom_snap, marker):
	# Configuration
	var marker_size = 5.0 * cam_zoom.x
	var text_offset = 20.0 * cam_zoom.x
	var marker_color = Color(0, 0.7, 1, 1)
	var text_color = Color(0, 0.7, 1, 1)
	
	var snap_interval = custom_snap.snap_interval
	var snap_offset = custom_snap.snap_offset
	var test_spacing = min(snap_interval.x, snap_interval.y) * 0.5
	
	var map_rect = tool.cached_world.WorldRect
	
	# Draw vertical line coordinates
	if marker.has_type("vertical"):
		var checked_positions = {}
		var y = world_top
		
		while y <= world_bottom:
			var test_pos = Vector2(marker_cx, y)
			var snapped = custom_snap.get_snapped_position(test_pos)
			
			if abs(snapped.x - marker_cx) < 0.5:
				var key = str(int(snapped.y * 10))
				
				if not checked_positions.has(key) and abs(snapped.y - marker_cy) > 0.5:
					if map_rect.has_point(snapped):
						checked_positions[key] = true
						var delta = snapped - Vector2(marker_cx, marker_cy) - snap_offset
						var grid_dist = round(abs(delta.y) / snap_interval.y)
						draw_circle(snapped, marker_size, marker_color)
						var text = str(int(grid_dist))
						var text_pos = Vector2(snapped.x + text_offset, snapped.y)
						_draw_text_with_outline(text, text_pos, text_color)
			y += test_spacing
	
	# Draw horizontal line coordinates
	if marker.has_type("horizontal"):
		var checked_positions = {}
		var x = world_left
		
		while x <= world_right:
			var test_pos = Vector2(x, marker_cy)
			var snapped = custom_snap.get_snapped_position(test_pos)
			
			if abs(snapped.y - marker_cy) < 0.5:
				var key = str(int(snapped.x * 10))
				
				if not checked_positions.has(key) and abs(snapped.x - marker_cx) > 0.5:
					if map_rect.has_point(snapped):
						checked_positions[key] = true
						var delta = snapped - Vector2(marker_cx, marker_cy) - snap_offset
						var grid_dist = round(abs(delta.x) / snap_interval.x)
						draw_circle(snapped, marker_size, marker_color)
						var text = str(int(grid_dist))
						var text_pos = Vector2(snapped.x, snapped.y - text_offset)
						_draw_text_with_outline(text, text_pos, text_color)
			x += test_spacing
	
	# Draw diagonal left coordinates (135°)
	if marker.has_type("diagonal_left"):
		_draw_diagonal_coordinates_custom(marker, marker_cx, marker_cy, 135, world_left, world_right, world_top, world_bottom, map_rect, marker_size, text_offset, marker_color, text_color, custom_snap, test_spacing, snap_offset, snap_interval)
	
	# Draw diagonal right coordinates (45°)
	if marker.has_type("diagonal_right"):
		_draw_diagonal_coordinates_custom(marker, marker_cx, marker_cy, 45, world_left, world_right, world_top, world_bottom, map_rect, marker_size, text_offset, marker_color, text_color, custom_snap, test_spacing, snap_offset, snap_interval)

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

# Draw coordinates along a diagonal line (vanilla grid)
func _draw_diagonal_coordinates_vanilla(_marker, marker_cx, marker_cy, cell_size, angle_deg, world_left, world_right, world_top, world_bottom, map_rect, marker_size, text_offset, marker_color, text_color):
	var angle_rad = deg2rad(angle_deg)
	var dx = cos(angle_rad)
	var dy = sin(angle_rad)
	
	# Sample along the diagonal line
	var step_size = min(cell_size.x, cell_size.y) * 0.5
	var max_distance = sqrt(pow(world_right - world_left, 2) + pow(world_bottom - world_top, 2))
	
	# Sample in both directions from center
	for direction in [-1, 1]:
		var distance = step_size
		while distance < max_distance:
			var test_pos = Vector2(marker_cx + dx * distance * direction, marker_cy + dy * distance * direction)
			
			# Check if near a grid node
			var grid_x = round((test_pos.x - marker_cx) / cell_size.x)
			var grid_y = round((test_pos.y - marker_cy) / cell_size.y)
			var grid_pos = Vector2(marker_cx + grid_x * cell_size.x, marker_cy + grid_y * cell_size.y)
			
			# If close enough to grid node and on the diagonal
			if test_pos.distance_to(grid_pos) < step_size * 0.5:
				if map_rect.has_point(grid_pos) and grid_pos.distance_to(Vector2(marker_cx, marker_cy)) > 0.1:
					# Calculate diagonal distance (in grid cells)
					var diag_dist = max(abs(grid_x), abs(grid_y))
					
					draw_circle(grid_pos, marker_size, marker_color)
					var text = str(int(diag_dist))
					# Offset text perpendicular to diagonal
					var perp_x = -dy * text_offset
					var perp_y = dx * text_offset
					var text_pos = Vector2(grid_pos.x + perp_x, grid_pos.y + perp_y)
					_draw_text_with_outline(text, text_pos, text_color)
			
			distance += step_size

# Draw coordinates along a diagonal line (custom_snap grid)
func _draw_diagonal_coordinates_custom(_marker, marker_cx, marker_cy, angle_deg, world_left, world_right, world_top, world_bottom, map_rect, marker_size, text_offset, marker_color, text_color, custom_snap, test_spacing, snap_offset, snap_interval):
	var angle_rad = deg2rad(angle_deg)
	var dx = cos(angle_rad)
	var dy = sin(angle_rad)
	
	var max_distance = sqrt(pow(world_right - world_left, 2) + pow(world_bottom - world_top, 2))
	var checked_positions = {}
	
	# Sample in both directions from center
	for direction in [-1, 1]:
		var distance = test_spacing
		while distance < max_distance:
			var test_pos = Vector2(marker_cx + dx * distance * direction, marker_cy + dy * distance * direction)
			var snapped = custom_snap.get_snapped_position(test_pos)
			
			# Check if snapped point is on the diagonal line
			var marker_center = Vector2(marker_cx, marker_cy)
			var to_snapped = snapped - marker_center
			var angle_to_snapped = atan2(to_snapped.y, to_snapped.x)
			var angle_diff = abs(angle_to_snapped - angle_rad)
			
			# Normalize angle difference to [0, PI]
			while angle_diff > PI:
				angle_diff -= TAU
			angle_diff = abs(angle_diff)
			if angle_diff > PI:
				angle_diff = TAU - angle_diff
			
			# If close to the diagonal (within ~10 degrees)
			if angle_diff < deg2rad(10) or abs(angle_diff - PI) < deg2rad(10):
				var key = str(int(snapped.x * 10)) + "_" + str(int(snapped.y * 10))
				
				if not checked_positions.has(key) and snapped.distance_to(marker_center) > 0.5:
					if map_rect.has_point(snapped):
						checked_positions[key] = true
						
						# Calculate distance along diagonal
						var delta = snapped - marker_center - snap_offset
						var diag_dist = round(max(abs(delta.x) / snap_interval.x, abs(delta.y) / snap_interval.y))
						
						draw_circle(snapped, marker_size, marker_color)
						var text = str(int(diag_dist))
						# Offset text perpendicular to diagonal
						var perp_x = -dy * text_offset
						var perp_y = dx * text_offset
						var text_pos = Vector2(snapped.x + perp_x, snapped.y + perp_y)
						_draw_text_with_outline(text, text_pos, text_color)
			
			distance += test_spacing
