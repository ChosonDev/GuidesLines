extends Node2D

# PermanentOverlay - Displays permanent guide lines
# Shows blue guide lines that can be toggled on/off

var parent_mod = null
var cached_world = null
var cached_camera = null
var cached_snappy_mod = null  # Custom_snap mod reference (if available)

# Performance optimization: only redraw when camera changes
var _last_camera_pos = Vector2.ZERO
var _last_camera_zoom = Vector2.ONE
var _last_perm_v_enabled = false
var _last_perm_h_enabled = false
var _last_show_coords = false

# Performance optimization: iteration limits
const MAX_COORD_MARKERS = 100  # Maximum coordinate markers for vanilla grid
const MAX_ITERATIONS = 1000  # Maximum iterations for custom_snap grid

var _cached_font = null # Optim: Cache font resource

func _ready():
	set_z_index(99)
	set_process(true)  # Enable _process for camera change detection
	
	# Optim: Get font once, effectively resolving memory leak
	var temp_control = Control.new()
	_cached_font = temp_control.get_font("font")
	temp_control.free()

# Check for camera changes and trigger redraw only when needed
func _process(_delta):
	if cached_camera and parent_mod:
		var cam_pos = cached_camera.get_camera_position()
		var cam_zoom = cached_camera.zoom
		var perm_v = parent_mod.perm_vertical_enabled
		var perm_h = parent_mod.perm_horizontal_enabled
		var show_coords = parent_mod.show_coordinates_enabled
		
		# Only redraw if something changed
		if cam_pos != _last_camera_pos or cam_zoom != _last_camera_zoom or \
		   perm_v != _last_perm_v_enabled or perm_h != _last_perm_h_enabled or \
		   show_coords != _last_show_coords:
			_last_camera_pos = cam_pos
			_last_camera_zoom = cam_zoom
			_last_perm_v_enabled = perm_v
			_last_perm_h_enabled = perm_h
			_last_show_coords = show_coords
			update()

# Draw permanent guide lines at map center
# Shows blue lines that can be toggled on/off
func _draw():
	if parent_mod == null:
		return
	if not (parent_mod.perm_vertical_enabled or parent_mod.perm_horizontal_enabled):
		return
	if cached_world == null or cached_camera == null:
		return
	
	var rect = cached_world.WorldRect
	var map_cx = rect.position.x + rect.size.x * 0.5
	var map_cy = rect.position.y + rect.size.y * 0.5
	
	# Adjust center to nearest grid node if custom_snap is enabled
	var custom_snap = _get_custom_snap()
	if custom_snap and custom_snap.custom_snap_enabled:
		var center_pos = Vector2(map_cx, map_cy)
		var snapped_center = custom_snap.get_snapped_position(center_pos)
		map_cx = snapped_center.x
		map_cy = snapped_center.y
	
	var cam_pos = cached_camera.get_camera_position()
	var cam_zoom = cached_camera.zoom
	var vp_rect = get_viewport_rect()
	
	var world_width = vp_rect.size.x * cam_zoom.x
	var world_height = vp_rect.size.y * cam_zoom.y
	var world_left = cam_pos.x - world_width * 0.5
	var world_right = cam_pos.x + world_width * 0.5
	var world_top = cam_pos.y - world_height * 0.5
	var world_bottom = cam_pos.y + world_height * 0.5
	
	if parent_mod.perm_vertical_enabled:
		draw_line(
			Vector2(map_cx, world_top),
			Vector2(map_cx, world_bottom),
			parent_mod.PERM_LINE_COLOR,
			parent_mod.PERM_LINE_WIDTH
		)
	
	if parent_mod.perm_horizontal_enabled:
		draw_line(
			Vector2(world_left, map_cy),
			Vector2(world_right, map_cy),
			parent_mod.PERM_LINE_COLOR,
			parent_mod.PERM_LINE_WIDTH
		)
	
	# Draw red center marker
	if parent_mod.perm_vertical_enabled or parent_mod.perm_horizontal_enabled:
		var center_marker_size = 5.0 * cam_zoom.x
		draw_circle(Vector2(map_cx, map_cy), center_marker_size, Color(1, 0, 0, 0.8))
	
	# Draw grid coordinates if enabled
	if parent_mod.show_coordinates_enabled and (parent_mod.perm_vertical_enabled or parent_mod.perm_horizontal_enabled):
		_draw_grid_coordinates(map_cx, map_cy, world_left, world_right, world_top, world_bottom, cam_zoom)

# Draw grid coordinates along the guide lines
# Shows grid node markers and distance numbers from map center
func _draw_grid_coordinates(map_cx, map_cy, world_left, world_right, world_top, world_bottom, cam_zoom):
	# Try to use custom_snap if available
	var custom_snap = _get_custom_snap()
	
	if custom_snap and custom_snap.custom_snap_enabled:
		_draw_custom_snap_coordinates(map_cx, map_cy, world_left, world_right, world_top, world_bottom, cam_zoom, custom_snap)
	else:
		_draw_vanilla_coordinates(map_cx, map_cy, world_left, world_right, world_top, world_bottom, cam_zoom)

# Draw text with outline for better visibility
func _draw_text_with_outline(text, position, color):
	# Optim: Use cached font instead of creating new Control every call
	var font = _cached_font 
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

# Get custom_snap mod reference if available
func _get_custom_snap():
	return cached_snappy_mod

# Draw coordinates using vanilla Dungeondraft grid
func _draw_vanilla_coordinates(map_cx, map_cy, world_left, world_right, world_top, world_bottom, cam_zoom):
	# Get grid cell size
	if cached_world.Level == null or cached_world.Level.TileMap == null:
		return
	
	var cell_size = cached_world.Level.TileMap.CellSize
	if cell_size == null or cell_size.x <= 0 or cell_size.y <= 0:
		return
	
	# Configuration
	var marker_size = 5.0 * cam_zoom.x  # Size of coordinate marker
	var text_offset = 20.0 * cam_zoom.x  # Offset for text from line
	var marker_color = parent_mod.PERM_LINE_COLOR  # Same as permanent lines
	var text_color = parent_mod.PERM_LINE_COLOR  # Same as permanent lines
	
	# Draw vertical line coordinates
	if parent_mod.perm_vertical_enabled:
		# Calculate grid positions along vertical line
		var start_y = floor((world_top - map_cy) / cell_size.y) * cell_size.y + map_cy
		var y = start_y
		
		# Get map boundaries
		var map_rect = cached_world.WorldRect
		
		# Check if too many markers would be drawn
		var max_iterations = int((world_bottom - world_top) / cell_size.y) + 1
		if max_iterations > MAX_COORD_MARKERS:
			return  # Skip drawing if too many markers
		
		var iteration_count = 0
		while y <= world_bottom and iteration_count < MAX_COORD_MARKERS:
			if abs(y - map_cy) > 0.1:  # Skip center point
				# Check if position is within map bounds
				var pos = Vector2(map_cx, y)
				if map_rect.has_point(pos):
					# Calculate grid index (distance from center in cells)
					var grid_y = round((y - map_cy) / cell_size.y)
					
					# Draw marker
					draw_circle(pos, marker_size, marker_color)
					
					# Draw text with grid coordinate
					var text = str(abs(int(grid_y)))
					var text_pos = Vector2(map_cx + text_offset, y)
					_draw_text_with_outline(text, text_pos, text_color)
			
			y += cell_size.y
			iteration_count += 1
	
	# Draw horizontal line coordinates
	if parent_mod.perm_horizontal_enabled:
		# Calculate grid positions along horizontal line
		var start_x = floor((world_left - map_cx) / cell_size.x) * cell_size.x + map_cx
		var x = start_x
		
		# Get map boundaries
		var map_rect = cached_world.WorldRect
		
		# Check if too many markers would be drawn
		var max_iterations = int((world_right - world_left) / cell_size.x) + 1
		if max_iterations > MAX_COORD_MARKERS:
			return  # Skip drawing if too many markers
		
		var iteration_count = 0
		while x <= world_right and iteration_count < MAX_COORD_MARKERS:
			if abs(x - map_cx) > 0.1:  # Skip center point
				# Check if position is within map bounds
				var pos = Vector2(x, map_cy)
				if map_rect.has_point(pos):
					# Calculate grid index (distance from center in cells)
					var grid_x = round((x - map_cx) / cell_size.x)
					
					# Draw marker
					draw_circle(pos, marker_size, marker_color)
					
					# Draw text with grid coordinate
					var text = str(abs(int(grid_x)))
					var text_pos = Vector2(x, map_cy - text_offset)
					_draw_text_with_outline(text, text_pos, text_color)
			
			x += cell_size.x
			iteration_count += 1

# Draw coordinates using custom_snap grid
func _draw_custom_snap_coordinates(map_cx, map_cy, world_left, world_right, world_top, world_bottom, cam_zoom, custom_snap):
	# Configuration
	var marker_size = 5.0 * cam_zoom.x
	var text_offset = 20.0 * cam_zoom.x
	var marker_color = parent_mod.PERM_LINE_COLOR
	var text_color = parent_mod.PERM_LINE_COLOR
	
	var snap_interval = custom_snap.snap_interval
	var snap_offset = custom_snap.snap_offset
	
	# Determine approximate spacing for iteration
	# For hex grids, we need to sample more densely
	var test_spacing = min(snap_interval.x, snap_interval.y) * 0.5
	
	# Draw vertical line coordinates
	if parent_mod.perm_vertical_enabled:
		var checked_positions = {}  # Track unique snapped positions
		var y = world_top
		var iteration_count = 0
		
		# Get map boundaries
		var map_rect = cached_world.WorldRect
		
		while y <= world_bottom and iteration_count < MAX_ITERATIONS:
			var test_pos = Vector2(map_cx, y)
			var snapped = custom_snap.get_snapped_position(test_pos)
			
			# Check if this is actually on the vertical line and not already drawn
			if abs(snapped.x - map_cx) < 0.5:
				var key = str(int(snapped.y * 10))  # Round to avoid duplicates
				
				if not checked_positions.has(key) and abs(snapped.y - map_cy) > 0.5:
					# Check if position is within map bounds
					if map_rect.has_point(snapped):
						checked_positions[key] = true
						
						# Calculate grid distance from center
						var delta = snapped - Vector2(map_cx, map_cy) - snap_offset
						var grid_dist = round(abs(delta.y) / snap_interval.y)
						
						# Draw marker and text
						draw_circle(snapped, marker_size, marker_color)
						var text = str(int(grid_dist))
						var text_pos = Vector2(snapped.x + text_offset, snapped.y)
						_draw_text_with_outline(text, text_pos, text_color)
			
			y += test_spacing
			iteration_count += 1
		
		if iteration_count >= MAX_ITERATIONS and parent_mod.LOGGER:
			parent_mod.LOGGER.warn("Vertical coordinate drawing exceeded iteration limit")
	
	# Draw horizontal line coordinates
	if parent_mod.perm_horizontal_enabled:
		var checked_positions = {}
		var x = world_left
		var iteration_count = 0
		
		# Get map boundaries
		var map_rect = cached_world.WorldRect
		
		while x <= world_right and iteration_count < MAX_ITERATIONS:
			var test_pos = Vector2(x, map_cy)
			var snapped = custom_snap.get_snapped_position(test_pos)
			
			# Check if this is actually on the horizontal line and not already drawn
			if abs(snapped.y - map_cy) < 0.5:
				var key = str(int(snapped.x * 10))
				
				if not checked_positions.has(key) and abs(snapped.x - map_cx) > 0.5:
					# Check if position is within map bounds
					if map_rect.has_point(snapped):
						checked_positions[key] = true
						
						# Calculate grid distance from center
						var delta = snapped - Vector2(map_cx, map_cy) - snap_offset
						var grid_dist = round(abs(delta.x) / snap_interval.x)
						
						# Draw marker and text
						draw_circle(snapped, marker_size, marker_color)
						var text = str(int(grid_dist))
						var text_pos = Vector2(snapped.x, snapped.y - text_offset)
						_draw_text_with_outline(text, text_pos, text_color)
			
			x += test_spacing
			iteration_count += 1
		
		if iteration_count >= MAX_ITERATIONS and parent_mod.LOGGER:
			parent_mod.LOGGER.warn("Horizontal coordinate drawing exceeded iteration limit")