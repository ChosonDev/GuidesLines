extends Node2D

const GeometryUtils = preload("../utils/GeometryUtils.gd")
const GuidesLinesRender = preload("../render/GuidesLinesRender.gd")

# MarkerOverlay - Handles drawing and input for guide markers

var tool = null

# Performance optimization: track when redraw is needed
var _last_camera_pos = Vector2.ZERO
var _last_camera_zoom = Vector2.ONE
var _last_marker_count = 0
var _last_path_active = false
var _last_arrow_active = false
var _last_mouse_pos = Vector2.ZERO  # Track mouse position for preview updates
var _mouse_in_ui = false  # Track if cursor is in UI area

# Preview marker constants (matching GuideMarker constants)
const PREVIEW_MARKER_SIZE = 10.0  # Base size before zoom adaptation
const PREVIEW_LINE_WIDTH = 5.0    # Base width before zoom adaptation

var _cached_font = null # Optim: Cache font resource

func _ready():
	set_process_input(true)
	set_process(true)
	
	# Optim: Get font once
	var temp_control = Control.new()
	_cached_font = temp_control.get_font("font")
	temp_control.free()

# Continuously update mouse position for path preview
func _process(_delta):
	var needs_update = false
	
	# Track mouse position for path preview
	if tool and tool.path_placement_active and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		tool.path_preview_point = tool.cached_worldui.MousePosition
		needs_update = true  # Always update during path placement
	
	# Track mouse position for arrow preview
	if tool and tool.arrow_placement_active and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		tool.arrow_preview_point = tool.cached_worldui.MousePosition
		needs_update = true  # Always update during arrow placement
	
	# Track mouse position for preview marker (when tool is enabled and not in delete mode)
	if tool and tool.is_enabled and not tool.delete_mode and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		var current_mouse_pos = tool.cached_worldui.MousePosition
		var viewport_mouse_pos = get_viewport().get_mouse_position()
		
		# Check if mouse is over UI (x < 450 means over left panel)
		var new_mouse_in_ui = viewport_mouse_pos.x < 450
		
		# If mouse moved between UI and world, or position changed in world
		if new_mouse_in_ui != _mouse_in_ui:
			# Mouse crossed UI boundary - force update
			_mouse_in_ui = new_mouse_in_ui
			needs_update = true
		elif not _mouse_in_ui:
			# Mouse in world - check if position changed
			if current_mouse_pos != _last_mouse_pos:
				_last_mouse_pos = current_mouse_pos
				needs_update = true
	else:
		# Mouse left the bounds - clear preview if needed
		if not _mouse_in_ui:
			_mouse_in_ui = true  # Treat as "in UI" to hide preview
			needs_update = true
	
	# Check for camera changes
	if tool and tool.cached_camera:
		var cam_pos = tool.cached_camera.get_camera_position()
		var cam_zoom = tool.cached_camera.zoom
		
		if cam_pos != _last_camera_pos or cam_zoom != _last_camera_zoom:
			_last_camera_pos = cam_pos
			_last_camera_zoom = cam_zoom
			needs_update = true
	
	# Check if markers changed
	if tool and tool.markers.size() != _last_marker_count:
		_last_marker_count = tool.markers.size()
		needs_update = true
	
	# Check if placement mode changed
	if tool:
		var path_active = tool.path_placement_active
		var arrow_active = tool.arrow_placement_active
		
		if path_active != _last_path_active or arrow_active != _last_arrow_active:
			_last_path_active = path_active
			_last_arrow_active = arrow_active
			needs_update = true
	
	# Only update when necessary
	if needs_update:
		update()

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
		# Shape type: RMB rotates by 45 degrees (not in delete mode)
		if tool.active_marker_type == tool.MARKER_TYPE_SHAPE and event.pressed and not tool.delete_mode:
			tool.rotate_shape_45()
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
			
			# Shape type: wheel rotates angle, Alt+wheel adjusts radius
			elif tool.active_marker_type == tool.MARKER_TYPE_SHAPE:
				if event.button_index == BUTTON_WHEEL_UP and event.pressed:
					if event.alt:
						if tool.LOGGER:
							tool.LOGGER.debug("MarkerOverlay: Alt+Mouse wheel UP detected (Shape radius)")
						tool.adjust_shape_radius_with_wheel(1)
					else:
						if tool.LOGGER:
							tool.LOGGER.debug("MarkerOverlay: Mouse wheel UP detected (Shape angle)")
						tool.adjust_shape_angle_with_wheel(1)
					get_tree().set_input_as_handled()
					return
				elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
					if event.alt:
						if tool.LOGGER:
							tool.LOGGER.debug("MarkerOverlay: Alt+Mouse wheel DOWN detected (Shape radius)")
						tool.adjust_shape_radius_with_wheel(-1)
					else:
						if tool.LOGGER:
							tool.LOGGER.debug("MarkerOverlay: Mouse wheel DOWN detected (Shape angle)")
						tool.adjust_shape_angle_with_wheel(-1)
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
		# Don't draw preview if mouse is in UI area
		if _mouse_in_ui:
			return
		
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
	var MARKER_SIZE = GuidesLinesRender.get_adaptive_width(marker.MARKER_SIZE, cam_zoom)
	var MARKER_COLOR = marker.MARKER_COLOR
	var LINE_WIDTH = GuidesLinesRender.get_adaptive_width(marker.LINE_WIDTH, cam_zoom)
	
	var map_rect = Rect2(world_left, world_top, world_right - world_left, world_bottom - world_top) # Fallback
	if tool.cached_world:
		map_rect = tool.cached_world.WorldRect
	
	var cell_size = _get_grid_cell_size()
	
	# Fetch pre-calculated geometry
	var draw_data = marker.get_draw_data(map_rect, cell_size)
	
	# Draw based on marker type
	if marker.marker_type == "Line":
		if draw_data.has("segments"):
			for segment in draw_data.segments:
				draw_line(segment[0], segment[1], marker.color, LINE_WIDTH)
	
	elif marker.marker_type == "Shape":
		if draw_data.has("type") and draw_data.type == "shape":
			# Single primitives list holds the complete current visual state:
			# original outline minus clipped/diff zones, plus diff boundary segments.
			var primitives = draw_data.get("primitives", [])
			for item in primitives:
				if item.type == "seg":
					draw_line(item.a, item.b, marker.color, LINE_WIDTH)


	
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
			
			var arrow_length = GuidesLinesRender.get_adaptive_width(marker.arrow_head_length, cam_zoom)
			var head_points = GeometryUtils.calculate_arrowhead_points(end, start, arrow_length, marker.arrow_head_angle)
			
			GuidesLinesRender.draw_arrow(self, start, end, head_points, marker.color, LINE_WIDTH)


	
	# Draw marker circle on top (only if marker is visible on screen)
	# Optimized visibility check using Godot's built-in Rect2 methods if possible, 
	# but simple AABB check is fast enough.
	var is_marker_visible = marker.position.x >= world_left and marker.position.x <= world_right and \
	                        marker.position.y >= world_top and marker.position.y <= world_bottom
	
	if is_marker_visible:
		draw_circle(marker.position, MARKER_SIZE / 2.0, MARKER_COLOR)
		draw_arc(marker.position, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 1), 2)
	
	# Draw coordinates if enabled for this marker
	if marker.show_coordinates:
		_draw_marker_coordinates(marker, cam_zoom, world_left, world_right, world_top, world_bottom)


# Draw semi-transparent preview of marker at cursor position
func _draw_custom_marker_preview(pos, world_left, world_right, world_top, world_bottom):
	var MARKER_COLOR = Color(1, 0, 0, 0.5)
	var LINE_COLOR = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)
	
	# Get camera zoom for adaptive line width and marker size
	var cam_zoom = tool.cached_camera.zoom if tool.cached_camera else Vector2.ONE
	var LINE_WIDTH = GuidesLinesRender.get_adaptive_width(PREVIEW_LINE_WIDTH, cam_zoom)
	var MARKER_SIZE = GuidesLinesRender.get_adaptive_width(PREVIEW_MARKER_SIZE, cam_zoom)
	
	# Draw preview based on active marker type
	if tool.active_marker_type == tool.MARKER_TYPE_LINE:
		# Draw preview line(s)
		var angles = [tool.active_angle]
		if tool.active_mirror:
			angles.append(fmod(tool.active_angle + 180.0, 360.0))
		
		for angle in angles:
			# Get map boundaries for clipping
			var map_rect = null
			if tool.cached_world:
				map_rect = tool.cached_world.WorldRect
			
			var line_points = _calculate_line_endpoints(
				pos,
				angle,
				world_left,
				world_right,
				world_top,
				world_bottom,
				map_rect
			)
			
			# Only draw if line segment is valid (within map bounds)
			if line_points[0] != line_points[1]:
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
			var angle_rad = deg2rad(tool.active_shape_angle)
			var vertices = GeometryUtils.calculate_shape_vertices(pos, radius_px, tool.active_shape_sides, angle_rad)
			GuidesLinesRender.draw_polygon_outline(self, vertices, LINE_COLOR, LINE_WIDTH)

	
	# Draw preview marker
	draw_circle(pos, MARKER_SIZE / 2.0, MARKER_COLOR)
	draw_arc(pos, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 2)

# Draw preview for Path type (temp points + line to cursor)
func _draw_path_preview(world_left, world_right, world_top, world_bottom):
	if not tool.path_placement_active or tool.path_temp_points.size() == 0:
		return
	
	var MARKER_COLOR = Color(1, 0, 0, 0.5)  # Red semi-transparent
	var LINE_COLOR = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)
	var PREVIEW_LINE_COLOR = Color(1, 1, 1, 0.5)  # White semi-transparent for preview line
	
	# Get camera zoom for adaptive line width and marker size
	var cam_zoom = tool.cached_camera.zoom if tool.cached_camera else Vector2.ONE
	var LINE_WIDTH = GuidesLinesRender.get_adaptive_width(PREVIEW_LINE_WIDTH, cam_zoom)
	var MARKER_SIZE = GuidesLinesRender.get_adaptive_width(PREVIEW_MARKER_SIZE, cam_zoom)
	
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
	
	var MARKER_COLOR = Color(1, 0, 0, 0.5)  # Red semi-transparent
	var LINE_COLOR = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)
	var PREVIEW_LINE_COLOR = Color(1, 1, 1, 0.5)  # White semi-transparent for preview line
	
	# Get camera zoom for adaptive line width and marker size
	var cam_zoom = tool.cached_camera.zoom if tool.cached_camera else Vector2.ONE
	var LINE_WIDTH = GuidesLinesRender.get_adaptive_width(PREVIEW_LINE_WIDTH, cam_zoom)
	var MARKER_SIZE = GuidesLinesRender.get_adaptive_width(PREVIEW_MARKER_SIZE, cam_zoom)
	
	# Draw start point (green, larger)
	var start_point = tool.arrow_temp_points[0]
	draw_circle(start_point, MARKER_SIZE / 1.5, Color(0, 1, 0, 0.6))  # Green first point
	draw_arc(start_point, MARKER_SIZE / 2.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 2)
	
	# If we have 1 point and cursor preview, draw preview arrow
	if tool.arrow_temp_points.size() == 1 and tool.arrow_preview_point != null:
		var preview_end = tool.arrow_preview_point
		
		var arrow_length = GuidesLinesRender.get_adaptive_width(tool.active_arrow_head_length, cam_zoom)
		var head_points = GeometryUtils.calculate_arrowhead_points(preview_end, start_point, arrow_length, tool.active_arrow_head_angle)
		
		GuidesLinesRender.draw_arrow(self, start_point, preview_end, head_points, PREVIEW_LINE_COLOR, LINE_WIDTH * 0.7)
		
		# Draw cursor preview circle
		draw_circle(preview_end, MARKER_SIZE / 3.0, Color(1, 1, 1, 0.3))

# Calculate line endpoints - always draws to map boundaries
func _calculate_line_endpoints(origin, angle_deg, world_left, world_right, world_top, world_bottom, map_rect):
	var angle_rad = deg2rad(angle_deg)
	var direction = Vector2(cos(angle_rad), sin(angle_rad))
	
	# Always draw infinite ray from origin to viewport edge
	# Create a Rect2 for the viewport/world bounds
	var viewport_rect = Rect2(world_left, world_top, world_right - world_left, world_bottom - world_top)
	var viewport_points = GeometryUtils.get_ray_to_rect_edge(origin, direction, viewport_rect)
	
	# Clip the line segment to map boundaries
	if map_rect:
		var clipped = GeometryUtils.clip_line_segment_to_rect(viewport_points[0], viewport_points[1], map_rect)
		if clipped.size() == 2:
			return clipped
		return [viewport_points[0], viewport_points[0]] # Return degenerate line if clipped out
	else:
		return viewport_points

# Draw grid coordinates along Line marker's guide lines
func _draw_marker_coordinates(marker, cam_zoom, world_left, world_right, world_top, world_bottom):
	if not tool or not tool.cached_world:
		return
	if marker.marker_type != "Line":
		return
	
	var marker_pos = marker.position
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
	
	var marker_size = GuidesLinesRender.get_adaptive_width(5.0, cam_zoom)
	var text_offset = GuidesLinesRender.get_adaptive_width(20.0, cam_zoom)
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
	var marker_size = GuidesLinesRender.get_adaptive_width(5.0, cam_zoom)
	var text_offset = GuidesLinesRender.get_adaptive_width(20.0, cam_zoom)
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
		
		if not checked_positions.has(key):
			# Use new optimized GeometryUtils method
			if GeometryUtils.is_point_on_ray(origin, direction, snapped, deg2rad(5.0)):
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
	GuidesLinesRender.draw_text_with_outline(self, text, position, color, _cached_font)

