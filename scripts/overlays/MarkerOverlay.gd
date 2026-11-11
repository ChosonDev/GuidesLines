extends Node2D

const GeometryUtils = preload("../utils/GeometryUtils.gd")
const GuidesLinesRender = preload("../render/GuidesLinesRender.gd")
const OptionalMods = preload("../integrations/OptionalMods.gd")
const MarkerContextMenu = preload("MarkerContextMenu.gd")

# MarkerOverlay - Owns a retained marker layer, interactive preview, and input.

var tool = null
var context_menu = null
var _markers_canvas = null
var _draw_canvas = self
var _last_render_state = []
var _preview_strokes = GuidesLinesRender.new()
var _placed_strokes = GuidesLinesRender.new()
var _shape_renderer = _preview_strokes

# Performance optimization: track when redraw is needed
var _last_camera_pos = Vector2.ZERO
var _last_camera_zoom = Vector2.ONE
var _last_marker_count = 0
var _last_fill_count = 0
var _last_path_active = false
var _last_mouse_pos = Vector2.ZERO  # Track mouse position for preview updates
var _mouse_in_ui = false  # Track if cursor is in UI area
var _api_preview_frame = -1

# Preview marker constants (matching GuideMarker constants)
const PREVIEW_MARKER_SIZE = 10.0  # Base size before zoom adaptation
const PREVIEW_LINE_WIDTH = 5.0    # Base width before zoom adaptation

# Static Color constants — avoids per-frame allocations in preview methods
const _PREVIEW_MARKER_COLOR      = Color(1, 0, 0, 0.5)
const _PREVIEW_ARC_COLOR         = Color(0, 0, 0, 0.5)
const _PATH_PREVIEW_LINE_COLOR   = Color(1, 1, 1, 0.5)
const _PATH_PREVIEW_FIRST_COLOR  = Color(0, 1, 0, 0.6)
const _PATH_PREVIEW_CURSOR_COLOR = Color(1, 1, 1, 0.3)

var _cached_font = null # Optim: Cache font resource

# Marker mutations invalidate both layers; preview-only changes call update().
func invalidate_markers() -> void:
	if _markers_canvas:
		_markers_canvas.update()
	update()

func _ready():
	context_menu = MarkerContextMenu.new()
	context_menu.tool = tool
	add_child(context_menu)
	_markers_canvas = Node2D.new()
	_markers_canvas.name = "PlacedMarkers"
	_markers_canvas.show_behind_parent = true
	add_child(_markers_canvas)
	_markers_canvas.connect("draw", self, "_draw_placed_markers")
	set_process_input(true)
	set_process(true)
	
	# Optim: Get font once
	var temp_control = Control.new()
	_cached_font = temp_control.get_font("font")
	temp_control.free()

# Continuously update mouse position for path preview
func _process(_delta):
	var needs_update = false
	var markers_changed = false
	
	# Track mouse position for path preview
	if tool and tool.path_placement_active and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		tool.path_preview_point = tool.cached_worldui.MousePosition
		needs_update = true  # Always update during path placement
	
	# Track mouse position for preview marker (when tool is enabled and not in delete mode)
	if tool and tool.is_enabled and not tool.delete_mode and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		var current_mouse_pos = tool.cached_worldui.MousePosition
		var new_mouse_in_ui = not _is_mouse_over_canvas()
		
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
			markers_changed = true
			_last_camera_pos = cam_pos
			_last_camera_zoom = cam_zoom
			needs_update = true
	
	# Check if markers changed
	if tool and tool.markers.size() != _last_marker_count:
		markers_changed = true
		_last_marker_count = tool.markers.size()
		needs_update = true
	
	# Check if fills changed
	if tool and tool.fills.size() != _last_fill_count:
		markers_changed = true
		_last_fill_count = tool.fills.size()
		needs_update = true
	
	# Grid/map/viewport changes can alter guides and coordinate labels without a mutation.
	if tool:
		var snap = _get_custom_snap()
		var snap_enabled = OptionalMods.snap_enabled(snap)
		var render_state = [tool.cached_camera, get_viewport_rect(), _get_grid_cell_size(),
			tool.cached_world.WorldRect if tool.cached_world else null, snap_enabled]
		if snap_enabled:
			render_state += [snap, snap.snap_interval, snap.snap_offset, snap.active_geometry, snap.radial_mode_to_corner]
		if render_state != _last_render_state:
			_last_render_state = render_state
			# Snap origin/orientation changes also invalidate retained coordinate labels.
			for marker in tool.markers:
				marker._coord_dirty = true
			markers_changed = true

	# Check if placement mode changed
	if tool:
		var path_active = tool.path_placement_active
		
		if path_active != _last_path_active:
			_last_path_active = path_active
			needs_update = true
	
	# Retain the request through every draw in its frame; expire before the next.
	if tool and not tool._api_preview.empty():
		if _api_preview_frame != tool._api_preview_frame:
			_api_preview_frame = tool._api_preview_frame
		elif Engine.get_idle_frames() > _api_preview_frame:
			tool._api_preview.clear()
		needs_update = true

	# Track drag position for move mode
	if tool and tool.move_mode and tool._move_selected_marker and tool.cached_worldui:
		var current = tool.cached_worldui.MousePosition
		if current != tool._move_drag_pos:
			tool._move_drag_pos = current
			needs_update = true

	# Only update when necessary
	if markers_changed:
		invalidate_markers()
	elif needs_update:
		update()

# Handle mouse input for placing markers
func _is_mouse_over_canvas() -> bool:
	if not tool or not tool.parent_mod:
		return false
	var editor = tool.parent_mod.Global.Editor
	if not editor is Node or not is_instance_valid(editor):
		return false
	var windows = editor.get("Windows")
	if windows != null:
		for window in windows.values():
			if is_instance_valid(window) and window.visible:
				return false
	# This is the host's Content.gui_input target (Editor.tscn / Editor.cs).
	# Local coordinates account for UI scale and resized side/top/bottom panels.
	var content = editor.get_node_or_null("VPartition/Panels/HSplit/Content")
	return content is Control and content.is_visible_in_tree() and Rect2(Vector2.ZERO,
		content.rect_size).has_point(content.get_local_mouse_position())

func _input(event):
	if not tool or not tool.is_enabled:
		return
	if context_menu and context_menu.handle_input(event, _is_mouse_over_canvas()):
		return
	if event is InputEventKey and tool.ui and tool.ui.text_field_has_focus():
		return
	if event is InputEventMouse and not _is_mouse_over_canvas():
		# Release still finishes an existing drag after the pointer leaves the canvas.
		if not (event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed):
			return
	
	# Handle RIGHT-CLICK for Path finalization
	if event is InputEventMouseButton and event.button_index == BUTTON_RIGHT:
		if not tool.path_placement_active and event.pressed and tool.cached_worldui and tool.cached_worldui.IsInsideBounds and context_menu:
			var position = tool.cached_worldui.MousePosition
			var marker = tool.find_marker_at(position, 20.0)
			if marker:
				context_menu.open_at(marker, position, get_viewport().get_mouse_position())
				get_tree().set_input_as_handled()
				return
		if tool.path_placement_active and event.pressed:
			tool._finalize_path_marker(false)  # Finish as open path
			get_tree().set_input_as_handled()
			return
		# Shape type: RMB rotates by 45 degrees (not in delete/move mode)
		if (tool.active_marker_type == tool.MARKER_TYPE_SHAPE or tool.is_spiral_active()) and event.pressed and not tool.delete_mode and not tool.move_mode:
			tool.rotate_shape_45()
			get_tree().set_input_as_handled()
			return
		# Template type: RMB rotates by 45 degrees (not in delete/move mode, not in capture mode)
		if tool.active_marker_type == tool.MARKER_TYPE_TEMPLATE and event.pressed and not tool.delete_mode and not tool.move_mode and not tool.template_capture_mode:
			tool.rotate_template_45()
			get_tree().set_input_as_handled()
			return
	
	# Handle ESC key for Path cancellation
	if event is InputEventKey and event.scancode == KEY_ESCAPE and event.pressed:
		if tool.template_capture_mode:
			tool.cancel_template_capture()
			get_tree().set_input_as_handled()
			return
		if tool.path_placement_active:
			tool._cancel_path_placement()
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
			elif tool.active_marker_type == tool.MARKER_TYPE_SHAPE or tool.is_spiral_active():
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

			# Template type: wheel rotates the ephemeral angle offset (not in capture mode)
			elif tool.active_marker_type == tool.MARKER_TYPE_TEMPLATE and not tool.template_capture_mode:
				if event.button_index == BUTTON_WHEEL_UP and event.pressed:
					tool.adjust_template_rotation_with_wheel(1)
					get_tree().set_input_as_handled()
					return
				elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
					tool.adjust_template_rotation_with_wheel(-1)
					get_tree().set_input_as_handled()
					return
		
		# Handle left click for placing/deleting markers
		if event.button_index == BUTTON_LEFT and event.pressed:
			# Check if click is inside world bounds
			if tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
				var pos = tool.cached_worldui.MousePosition
				
				if tool.LOGGER:
					tool.LOGGER.debug("MarkerOverlay: Mouse clicked at %s, delete_mode: %s, fill_mode: %s" % [pos, str(tool.delete_mode), str(tool.active_marker_type == tool.MARKER_TYPE_FILL)])
				
				# Move mode: start dragging the marker under the cursor
				if tool.move_mode:
					var marker = tool.find_marker_at(pos, 20.0)
					if marker:
						tool._move_selected_marker = marker
						tool._move_drag_offset = pos - marker.position
						tool._move_drag_pos = pos
						update()
					get_tree().set_input_as_handled()
					return
				
				# Template capture mode: save clicked marker as a new template
				if tool.template_capture_mode:
					if tool.template_group_capture:
						tool.toggle_group_marker(pos)
					else:
						tool.capture_marker_as_template(pos)
					get_tree().set_input_as_handled()
					update()
					return

				# Fill mode: click fills the region under the cursor inside a Shape polygon
				if tool.active_marker_type == tool.MARKER_TYPE_FILL:
					tool.handle_fill_click(pos)
					update()
					return
				
				# If in delete mode, try to delete marker
				if tool.delete_mode:
					tool.delete_marker_at_position(pos, 20.0)
				else:
					# Otherwise place new marker
					tool.place_marker(pos)
				
				update()  # Request redraw

	# LMB released — finalize drag in move mode
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
		if tool.move_mode and tool._move_selected_marker:
			var new_pos = tool._move_drag_pos - tool._move_drag_offset
			if tool.parent_mod.Global.Editor.IsSnapping:
				new_pos = tool.snap_position_to_grid(new_pos)
			tool.move_marker(tool._move_selected_marker, new_pos)
			tool._move_selected_marker = null
			get_tree().set_input_as_handled()
			return

	# Mouse motion — live preview while dragging in move mode
	if event is InputEventMouseMotion and tool.move_mode and tool._move_selected_marker:
		update()
		return

# Separate CanvasItems retain placed geometry while the cursor preview redraws.
func _draw():
	_shape_renderer = _preview_strokes
	_preview_strokes.begin_strokes()
	_draw_layer(self, true)
	_preview_strokes.end_strokes()

func _draw_placed_markers() -> void:
	_shape_renderer = _placed_strokes
	_placed_strokes.begin_strokes()
	_draw_layer(_markers_canvas, false)
	_placed_strokes.end_strokes()
	_shape_renderer = _preview_strokes
	_draw_canvas = self

func _draw_layer(canvas, preview: bool) -> void:
	_draw_canvas = canvas
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

	# Compute once — shared by all markers this frame
	var map_rect: Rect2
	if tool.cached_world:
		map_rect = tool.cached_world.WorldRect
	else:
		map_rect = Rect2(world_left, world_top, world_right - world_left, world_bottom - world_top)
	var cell_size = _get_grid_cell_size()
	var custom_snap = _get_custom_snap()
	var marker_size_draw    = GuidesLinesRender.get_adaptive_width(10.0, cam_zoom)
	var line_width_draw     = GuidesLinesRender.get_adaptive_width(5.0, cam_zoom)
	var preview_line_width  = GuidesLinesRender.get_adaptive_width(PREVIEW_LINE_WIDTH, cam_zoom)
	var preview_marker_size = GuidesLinesRender.get_adaptive_width(PREVIEW_MARKER_SIZE, cam_zoom)
	var coord_marker_size   = GuidesLinesRender.get_adaptive_width(5.0, cam_zoom)
	var coord_text_offset   = GuidesLinesRender.get_adaptive_width(20.0, cam_zoom)
	var active_arrow_length_px = GuidesLinesRender.get_adaptive_width(tool.active_arrow_head_length, cam_zoom)

	if not preview:
		# Draw fill regions under marker outlines (respects markers_opacity)
		_draw_fills()

		# Draw all markers (hidden when markers_visible is false)
		if not tool.parent_mod or tool.parent_mod.markers_visible:
			for marker in tool.markers:
				if not marker:
					continue
			
				_draw_custom_marker(marker, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, custom_snap, marker_size_draw, line_width_draw, coord_marker_size, coord_text_offset)
	
		return

	# Draw API-requested shape preview (external callers; rendered regardless of tool state)
	if not tool._api_preview.empty():
		_draw_api_shape_preview(tool._api_preview, cam_zoom, cell_size, preview_line_width, preview_marker_size)

	# Selection stays visible while the pointer is over the sidebar Save button.
	if tool.is_enabled and tool.template_group_capture and (not tool.parent_mod or tool.parent_mod.markers_visible):
		for id in tool.template_group_ids:
			if not tool.markers_lookup.has(id): continue
			var marker = tool.markers_lookup[id]
			marker.get_draw_data(map_rect, cell_size)
			var data = {"marker_type": marker.marker_type, "position": marker.position,
				"angle": marker.angle, "mirror": marker.mirror, "shape_primitives": marker.get_primitives(),
				"marker_points": marker.marker_points, "path_closed": marker.path_closed,
				"path_end_arrow": marker.path_end_arrow, "arrow_head_length": marker.arrow_head_length,
				"arrow_head_angle": marker.arrow_head_angle}
			_draw_group_geometry(data, Color(0.65, 1, 1, 0.3), line_width_draw + GuidesLinesRender.get_adaptive_width(4, cam_zoom),
				world_left, world_right, world_top, world_bottom, cam_zoom, map_rect)
			_draw_canvas.draw_arc(marker.position, marker_size_draw, 0, TAU, 32, Color(0.65, 1, 1, 0.5), line_width_draw)

	# Draw move mode drag preview
	if tool.move_mode and tool._move_selected_marker:
		var drag_pos = tool._move_drag_pos - tool._move_drag_offset
		if tool.parent_mod.Global.Editor.IsSnapping:
			drag_pos = tool.snap_position_to_grid(drag_pos)
		_draw_move_drag_preview(tool._move_selected_marker, drag_pos, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, custom_snap, preview_line_width, preview_marker_size)
		return

	# Draw preview marker at cursor (disabled in delete mode, move mode, fill mode, and template mode)
	if tool.is_enabled and not tool.delete_mode and not tool.move_mode and tool.active_marker_type != tool.MARKER_TYPE_FILL and tool.active_marker_type != tool.MARKER_TYPE_TEMPLATE and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		# Don't draw preview if mouse is in UI area
		if _mouse_in_ui:
			return
		
		# Special preview for Path type
		if tool.active_marker_type == tool.MARKER_TYPE_PATH and not tool.is_spiral_active():
			_draw_path_preview(world_left, world_right, world_top, world_bottom, cam_zoom, preview_line_width, preview_marker_size, active_arrow_length_px)
		else:
			var preview_pos = tool.cached_worldui.MousePosition
			_draw_custom_marker_preview(preview_pos, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, preview_line_width, preview_marker_size)

	# Draw template preview at cursor (Template mode with a selected template, not in capture mode)
	if tool.is_enabled and not tool.delete_mode and not tool.move_mode \
			and tool.active_marker_type == tool.MARKER_TYPE_TEMPLATE \
			and not tool.template_capture_mode \
			and tool.active_template_index >= 0 \
			and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		if not _mouse_in_ui:
			var preview_pos = tool.cached_worldui.MousePosition
			_draw_template_preview(preview_pos, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, preview_line_width, preview_marker_size)

# Draw all fill regions stored in the tool.
# Fills are drawn below marker outlines and respect the global markers_opacity.
func _draw_fills() -> void:
	if not tool or tool.fills.empty():
		return
	for fill in tool.fills:
		if fill.polygon.size() < 3:
			continue
		_draw_canvas.draw_colored_polygon(PoolVector2Array(fill.polygon), fill.draw_color)

# Draw a single custom marker with its line(s) or circle
func _draw_custom_marker(marker, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect: Rect2, cell_size, custom_snap, marker_size_draw: float, line_width_draw: float, coord_marker_size: float, coord_text_offset: float):
	var MARKER_SIZE = marker_size_draw
	var LINE_WIDTH  = line_width_draw

	var line_color   = marker.draw_color
	var MARKER_COLOR = marker.draw_marker_color

	# map_rect and cell_size come from _draw — computed once per frame
	var draw_data = marker.get_draw_data(map_rect, cell_size)
	
	# Draw based on marker type
	if marker.marker_type == "Line":
		if draw_data.has("segments"):
			var points = PoolVector2Array()
			for segment in draw_data.segments:
				points.append_array(PoolVector2Array(segment))
			_shape_renderer.draw_strokes(_draw_canvas, points, line_color, LINE_WIDTH)
	
	elif marker.marker_type == "Shape":
		if draw_data.has("type") and draw_data.type == "shape":
			# Single primitives list holds the complete current visual state:
			# original outline minus clipped/diff zones, plus diff boundary segments.
			_draw_shape_segments(draw_data.get("primitives", []), line_color, LINE_WIDTH)


	elif marker.marker_type == "Path":
		_draw_path_points(marker.marker_points, marker.path_closed, marker.path_end_arrow, marker.arrow_head_length, marker.arrow_head_angle, cam_zoom, line_color, LINE_WIDTH)

	# Draw marker circle on top (only if marker is visible on screen)
	# Optimized visibility check using Godot's built-in Rect2 methods if possible, 
	# but simple AABB check is fast enough.
	var is_marker_visible = marker.position.x >= world_left and marker.position.x <= world_right and \
	                        marker.position.y >= world_top and marker.position.y <= world_bottom
	
	if is_marker_visible:
		_draw_marker_anchor(marker.position, MARKER_SIZE, MARKER_COLOR, marker.draw_arc_color)
	
	# Draw coordinates if enabled for this marker
	if marker.show_coordinates:
		var snap_enabled  = OptionalMods.snap_enabled(custom_snap)
		var snap_interval = custom_snap.snap_interval if snap_enabled else Vector2.ZERO
		if marker._coord_dirty \
				or map_rect != marker._cached_coord_map_rect \
				or cell_size != marker._cached_coord_cell_size \
				or snap_enabled  != marker._cached_coord_snap_enabled \
				or snap_interval != marker._cached_coord_snap_interval:
			marker.rebuild_coord_cache(map_rect, cell_size, custom_snap)
		_draw_marker_coordinates_cached(marker, coord_marker_size, coord_text_offset)


## Render a one-frame Shape preview requested via GuidesLinesApi.set_shape_preview().
## [p] is the dict stored in tool._api_preview.
func _draw_api_shape_preview(p: Dictionary, cam_zoom: Vector2, cell_size, preview_line_width: float, preview_marker_size: float) -> void:
	if cell_size == null:
		return
	if p.has("markers"):
		var map_rect = tool.cached_world.WorldRect
		for data in p.markers:
			var c = data.color
			_draw_group_geometry(data, Color(c.r, c.g, c.b, 0.55), preview_line_width, map_rect.position.x, map_rect.end.x, map_rect.position.y, map_rect.end.y, cam_zoom, map_rect)
		_draw_marker_anchor(p.pos, preview_marker_size, _PREVIEW_MARKER_COLOR, _PREVIEW_ARC_COLOR)
		return
	var pos    = p.get("pos",    Vector2.ZERO)
	var radius = p.get("radius", 1.0)
	var angle  = p.get("angle",  0.0)
	var sides  = p.get("sides",  6)
	var color  = p.get("color",  Color(0, 0.7, 1, 0.5))
	var radius_px = radius * min(cell_size.x, cell_size.y)
	var angle_rad = deg2rad(angle)
	var vertices  = GeometryUtils.calculate_polygon_vertices(Vector2.ZERO, radius_px, sides, angle_rad)
	_shape_renderer.draw_polygon_outline(_draw_canvas, vertices, color, preview_line_width, pos)
	_draw_marker_anchor(pos, preview_marker_size, Color(color.r, color.g, color.b, 0.5), _PREVIEW_ARC_COLOR)

# Draw semi-transparent preview of marker at cursor position
func _draw_custom_marker_preview(pos, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, preview_line_width: float, preview_marker_size: float):
	if tool.is_spiral_active():
		if tool.parent_mod.Global.Editor.IsSnapping:
			pos = tool.snap_position_to_grid(pos)
		var color = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)
		if cell_size:
			_draw_spiral_preview(pos, tool.spiral_settings(), tool.active_marker_type == tool.MARKER_TYPE_SHAPE,
				cell_size, color, preview_line_width, tool.active_path_end_arrow,
				tool.active_arrow_head_length, tool.active_arrow_head_angle, cam_zoom)
		_draw_marker_anchor(pos, preview_marker_size, _PREVIEW_MARKER_COLOR, _PREVIEW_ARC_COLOR)
		return
	var MARKER_COLOR = _PREVIEW_MARKER_COLOR
	var LINE_COLOR = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)

	# Sizes pre-computed in _draw — no re-fetch needed
	var LINE_WIDTH  = preview_line_width
	var MARKER_SIZE = preview_marker_size
	
	# Draw preview based on active marker type
	if tool.active_marker_type == tool.MARKER_TYPE_LINE:
		# Draw preview line(s)
		var angles = [tool.active_angle]
		if tool.active_mirror:
			angles.append(fposmod(tool.active_angle + 180.0, 360.0))
		var points = PoolVector2Array()
		for angle in angles:
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
				points.append_array(PoolVector2Array(line_points))
		_shape_renderer.draw_strokes(_draw_canvas, points, LINE_COLOR, LINE_WIDTH)
	
	elif tool.active_marker_type == tool.MARKER_TYPE_SHAPE:
		# Draw preview shape — cell_size comes from _draw
		if cell_size:
			var radius_px = tool.active_shape_radius * min(cell_size.x, cell_size.y)
			var angle_rad = deg2rad(tool.active_shape_angle)
			var vertices = GeometryUtils.calculate_polygon_vertices(Vector2.ZERO, radius_px, tool.active_shape_sides, angle_rad)
			_shape_renderer.draw_polygon_outline(_draw_canvas, vertices, LINE_COLOR, LINE_WIDTH, pos)

	
	# Draw preview marker
	_draw_marker_anchor(pos, MARKER_SIZE, MARKER_COLOR, _PREVIEW_ARC_COLOR)

# Draw semi-transparent preview of the selected template at cursor position.
func _draw_template_preview(preview_pos: Vector2, world_left: float, world_right: float, world_top: float, world_bottom: float, cam_zoom: Vector2, map_rect: Rect2, cell_size, preview_line_width: float, preview_marker_size: float) -> void:
	if tool.active_template_index < 0 or tool.active_template_index >= tool.templates.size():
		return
	if tool.is_group_template() or tool.template_scale != 1.0:
		if tool.parent_mod.Global.Editor and tool.parent_mod.Global.Editor.IsSnapping:
			preview_pos = tool.snap_position_to_grid(preview_pos)
		var batch = tool.build_template_markers(preview_pos, tool.active_template_index, tool.template_rotation_offset, tool.template_scale)
		if tool.ui:
			tool.ui.set_group_error("Cannot place group: check scale and marker dimensions." if batch.empty() else "")
		for data in batch:
			var color = Color(data.color.r, data.color.g, data.color.b, 0.55)
			_draw_group_geometry(data, color, preview_line_width, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect)
			_draw_marker_anchor(data.position, preview_marker_size, _PREVIEW_MARKER_COLOR, _PREVIEW_ARC_COLOR)
		_draw_marker_anchor(preview_pos, preview_marker_size, Color(0.65, 1, 1, 0.55), _PREVIEW_ARC_COLOR)
		return
	var data = tool.templates[tool.active_template_index]["data"]
	var ALPHA        = 0.55
	var c            = data.get("color", Color(0, 0.7, 1, 1))
	var line_color   = Color(c.r, c.g, c.b, ALPHA)
	var marker_color = Color(1, 0, 0, ALPHA)
	var arc_color    = Color(0, 0, 0, ALPHA)
	var LINE_WIDTH   = preview_line_width
	var MARKER_SIZE  = preview_marker_size

	match data.get("marker_type", ""):
		"Line":
			var base_angle = data.get("angle", 0.0)
			var eff_angle = fposmod(base_angle + tool.template_rotation_offset, 360.0)
			var angles = [eff_angle]
			if data.get("mirror", false):
				angles.append(fposmod(eff_angle + 180.0, 360.0))
			var points = PoolVector2Array()
			for ang in angles:
				var line_points = _calculate_line_endpoints(preview_pos, ang, world_left, world_right, world_top, world_bottom, map_rect)
				if line_points[0] != line_points[1]:
					points.append_array(PoolVector2Array(line_points))
			_shape_renderer.draw_strokes(_draw_canvas, points, line_color, LINE_WIDTH)
		"Shape":
			if data.has("shape_primitives"):
				# Modified shape — draw stored segments translated + rotated to cursor
				_draw_shape_segments(data["shape_primitives"], line_color, LINE_WIDTH,
					preview_pos, deg2rad(tool.template_rotation_offset))
			elif data.get("marker_subtype", "") == "Spiral":
				if cell_size and data.get("spiral_settings") is Dictionary:
					var settings = data.spiral_settings.duplicate()
					settings.angle = fposmod(settings.get("angle", 0.0) + tool.template_rotation_offset, 360.0)
					_draw_spiral_preview(preview_pos, settings, true, cell_size, line_color, LINE_WIDTH)
			elif cell_size:
				# Standard unmodified shape — regenerate from parameters
				var radius_px = data.get("shape_radius", 1.0) * min(cell_size.x, cell_size.y)
				var eff_angle = fposmod(data.get("shape_angle", 0.0) + tool.template_rotation_offset, 360.0)
				var angle_rad = deg2rad(eff_angle)
				var vertices  = GeometryUtils.calculate_polygon_vertices(Vector2.ZERO, radius_px, data.get("shape_sides", 6), angle_rad)
				_shape_renderer.draw_polygon_outline(_draw_canvas, vertices, line_color, LINE_WIDTH, preview_pos)
		"Path":
			var rel_pts = data.get("relative_points", [])
			if rel_pts.size() >= 2:
				var rot_rad = deg2rad(tool.template_rotation_offset)
				var pts = []
				for rp in rel_pts:
					pts.append(rp.rotated(rot_rad))
				_draw_path_points(pts, data.get("path_closed", false), data.get("path_end_arrow", false), data.get("arrow_head_length", 50.0), data.get("arrow_head_angle", 30.0), cam_zoom, line_color, LINE_WIDTH, preview_pos)

	_draw_marker_anchor(preview_pos, MARKER_SIZE, marker_color, arc_color)

func _draw_group_geometry(data: Dictionary, color: Color, width: float, world_left, world_right, world_top, world_bottom, cam_zoom: Vector2, map_rect: Rect2) -> void:
	match data.marker_type:
		"Line":
			var angles = [data.get("angle", 0.0)]
			if data.get("mirror", false): angles.append(angles[0] + 180.0)
			var strokes = PoolVector2Array()
			for angle in angles:
				var points = _calculate_line_endpoints(data.position, angle, world_left, world_right, world_top, world_bottom, map_rect)
				if points[0] != points[1]:
					strokes.append_array(PoolVector2Array(points))
			_shape_renderer.draw_strokes(_draw_canvas, strokes, color, width)
		"Shape":
			_draw_shape_segments(data.get("shape_primitives", []), color, width)
		"Path":
			_draw_path_points(data.marker_points, data.get("path_closed", false), data.get("path_end_arrow", false), data.get("arrow_head_length", 50.0), data.get("arrow_head_angle", 30.0), cam_zoom, color, width)

# Draw the selected marker semi-transparently at the dragged position during Move Mode.
func _draw_move_drag_preview(marker, drag_pos: Vector2, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect: Rect2, cell_size, custom_snap, preview_line_width: float, preview_marker_size: float):
	var ALPHA = 0.55
	var line_color   = Color(marker.draw_color.r, marker.draw_color.g, marker.draw_color.b, ALPHA)
	var marker_color = Color(marker.draw_marker_color.r, marker.draw_marker_color.g, marker.draw_marker_color.b, ALPHA)
	var arc_color    = Color(marker.draw_arc_color.r, marker.draw_arc_color.g, marker.draw_arc_color.b, ALPHA)
	var LINE_WIDTH   = preview_line_width
	var MARKER_SIZE  = preview_marker_size

	if marker.marker_type == "Line":
		var angles = [marker.angle]
		if marker.mirror:
			angles.append(fposmod(marker.angle + 180.0, 360.0))
		var points = PoolVector2Array()
		for ang in angles:
			var line_points = _calculate_line_endpoints(drag_pos, ang, world_left, world_right, world_top, world_bottom, map_rect)
			if line_points[0] != line_points[1]:
				points.append_array(PoolVector2Array(line_points))
		_shape_renderer.draw_strokes(_draw_canvas, points, line_color, LINE_WIDTH)

	elif marker.marker_type == "Shape":
		var offset = drag_pos - marker.position
		var data = marker.get_draw_data(map_rect, cell_size)
		_draw_shape_segments(data.get("primitives", []), line_color, LINE_WIDTH, offset)

	elif marker.marker_type == "Path":
		if marker.marker_points.size() >= 2:
			var offset = drag_pos - marker.position
			_draw_path_points(marker.marker_points, marker.path_closed, marker.path_end_arrow, marker.arrow_head_length, marker.arrow_head_angle, cam_zoom, line_color, LINE_WIDTH, offset)

	_draw_marker_anchor(drag_pos, MARKER_SIZE, marker_color, arc_color)

# Draw preview for Path type (temp points + line to cursor)
func _draw_path_preview(world_left, world_right, world_top, world_bottom, cam_zoom, preview_line_width: float, preview_marker_size: float, active_arrow_length_px: float):
	if not tool.path_placement_active or tool.path_temp_points.size() == 0:
		return
	
	var MARKER_COLOR       = _PREVIEW_MARKER_COLOR
	var LINE_COLOR         = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)
	var PREVIEW_LINE_COLOR = _PATH_PREVIEW_LINE_COLOR
	
	# Sizes pre-computed in _draw — no re-fetch needed
	var LINE_WIDTH  = preview_line_width
	var MARKER_SIZE = preview_marker_size
	
	# Draw all placed points
	for i in range(tool.path_temp_points.size()):
		var point = tool.path_temp_points[i]
		
		# First point is slightly larger and different color
		if i == 0:
			_draw_canvas.draw_circle(point, MARKER_SIZE / 1.5, _PATH_PREVIEW_FIRST_COLOR)
		else:
			_draw_canvas.draw_circle(point, MARKER_SIZE / 2.0, MARKER_COLOR)
		
		# Draw outline
		_draw_canvas.draw_arc(point, MARKER_SIZE / 2.0, 0, TAU, 32, _PREVIEW_ARC_COLOR, 2)
	
	_draw_path_points(tool.path_temp_points, false, false, 0, 0, cam_zoom, LINE_COLOR, LINE_WIDTH)
	if tool.path_preview_point != null:
		var last_point = tool.path_temp_points.back()
		_draw_path_points([last_point, tool.path_preview_point], false, tool.active_path_end_arrow,
			active_arrow_length_px, tool.active_arrow_head_angle, Vector2.ONE, PREVIEW_LINE_COLOR, LINE_WIDTH * 0.7)
		_draw_canvas.draw_circle(tool.path_preview_point, MARKER_SIZE / 3.0, _PATH_PREVIEW_CURSOR_COLOR)

	# Draw "close path" indicator if near first point
	if tool.path_temp_points.size() >= 3 and tool.path_preview_point != null:
		var first_point = tool.path_temp_points[0]
		if tool.path_preview_point.distance_to(first_point) < 30.0:
			# Draw pulsing circle around first point
			var pulse = sin(OS.get_ticks_msec() * 0.005) * 0.5 + 0.5
			_draw_canvas.draw_arc(first_point, MARKER_SIZE, 0, TAU, 32, Color(0, 1, 0, 0.5 + pulse * 0.3), 4)

# Calculate line endpoints - always draws to map boundaries
func _calculate_line_endpoints(origin, angle_deg, world_left, world_right, world_top, world_bottom, map_rect):
	var angle_rad = deg2rad(angle_deg)
	var direction = Vector2(cos(angle_rad), sin(angle_rad))
	var bounds = map_rect if map_rect else Rect2(world_left, world_top, world_right - world_left, world_bottom - world_top)
	return GeometryUtils.get_ray_to_rect_edge(origin, direction, bounds)

func _get_custom_snap():
	if not tool:
		return null
	return tool.cached_snappy_mod

# Get grid cell size (accounting for custom_snap mod if active)
func _get_grid_cell_size():
	if not tool:
		return null
	# Single source of truth — delegate to the tool so all modes use identical cell_size.
	return tool._get_grid_cell_size()

# Draw cached coordinate points for a Line marker.
# All grid positions and texts are pre-computed in GuideMarker.rebuild_coord_cache().
# Sizes are pre-computed in _draw() — no per-call get_adaptive_width needed.
func _draw_marker_coordinates_cached(marker, marker_size: float, text_offset: float) -> void:
	if marker.cached_coord_points.empty():
		return
	var color = marker.draw_color
	for point in marker.cached_coord_points:
		_draw_canvas.draw_circle(point.grid_pos, marker_size, color)
		_draw_text_with_outline(point.text, point.grid_pos + point.perp * text_offset, color)

# Draw text with outline for better visibility
func _draw_text_with_outline(text, position, color):
	GuidesLinesRender.draw_text_with_outline(_draw_canvas, text, position, color, _cached_font)


func _draw_marker_anchor(pos: Vector2, size: float, fill_color: Color, arc_color: Color) -> void:
	_draw_canvas.draw_circle(pos, size / 2.0, fill_color)
	_draw_canvas.draw_arc(pos, size / 2.0, 0, TAU, 32, arc_color, 2)

func _draw_spiral_preview(pos: Vector2, settings: Dictionary, closed: bool, cell_size: Vector2, color: Color, width: float, end_arrow: bool = false, arrow_length: float = 50.0, arrow_angle: float = 30.0, zoom: Vector2 = Vector2.ONE) -> void:
	var points = tool.spiral_preview_points(settings, closed, cell_size)
	if points.size() < 2:
		return
	var head = []
	if not closed and end_arrow:
		head = GeometryUtils.calculate_arrowhead_points(points[points.size() - 1], points[points.size() - 2],
			GuidesLinesRender.get_adaptive_width(arrow_length, zoom), arrow_angle)
	_shape_renderer.draw_path(_draw_canvas, Array(points), closed, head, color, width, pos)

func _draw_path_points(points: Array, closed: bool, end_arrow: bool, arrow_length: float, arrow_angle: float, zoom: Vector2, color: Color, width: float, offset: Vector2 = Vector2.ZERO) -> void:
	if points.size() < 2:
		return
	var head = []
	if end_arrow:
		head = GeometryUtils.calculate_arrowhead_points(points.back(), points[points.size() - 2],
			GuidesLinesRender.get_adaptive_width(arrow_length, zoom), arrow_angle)
	_shape_renderer.draw_path(_draw_canvas, points, closed, head, color, width, offset)

# Authoritative segments stay disconnected, including Cut/Difference gaps.
func _draw_shape_segments(primitives: Array, color: Color, width: float, offset: Vector2 = Vector2.ZERO, rotation: float = 0.0) -> void:
	_shape_renderer.draw_shape_segments(_draw_canvas, primitives, color, width, offset, rotation)
