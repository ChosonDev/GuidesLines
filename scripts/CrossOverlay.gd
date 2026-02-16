extends Node2D

# CrossOverlay - Displays proximity-based guide lines
# Shows red guide lines when cursor is near the map center

var parent_mod = null
var cached_world = null
var cached_camera = null

# Performance optimization: only redraw when camera or state changes
var _last_camera_pos = Vector2.ZERO
var _last_camera_zoom = Vector2.ONE
var _last_cross_show_v = false
var _last_cross_show_h = false

func _ready():
	set_z_index(100)
	set_process(true)  # Enable _process for camera change detection

# Check for camera changes and trigger redraw only when needed
func _process(_delta):
	if cached_camera and parent_mod:
		var cam_pos = cached_camera.get_camera_position()
		var cam_zoom = cached_camera.zoom
		var cross_v = parent_mod.cross_show_v
		var cross_h = parent_mod.cross_show_h
		
		# Only redraw if something changed
		if cam_pos != _last_camera_pos or cam_zoom != _last_camera_zoom or \
		   cross_v != _last_cross_show_v or cross_h != _last_cross_show_h:
			_last_camera_pos = cam_pos
			_last_camera_zoom = cam_zoom
			_last_cross_show_v = cross_v
			_last_cross_show_h = cross_h
			update()

# Draw proximity-based cross guides
# Shows red lines when cursor is near map center
func _draw():
	if parent_mod == null:
		return
	if not (parent_mod.cross_show_v or parent_mod.cross_show_h):
		return
	if cached_world == null or cached_camera == null:
		return
	
	var rect = cached_world.WorldRect
	var map_cx = rect.position.x + rect.size.x * 0.5
	var map_cy = rect.position.y + rect.size.y * 0.5
	
	var cam_pos = cached_camera.get_camera_position()
	var cam_zoom = cached_camera.zoom
	var vp_rect = get_viewport_rect()
	
	var world_width = vp_rect.size.x * cam_zoom.x
	var world_height = vp_rect.size.y * cam_zoom.y
	var world_left = cam_pos.x - world_width * 0.5
	var world_right = cam_pos.x + world_width * 0.5
	var world_top = cam_pos.y - world_height * 0.5
	var world_bottom = cam_pos.y + world_height * 0.5
	
	if parent_mod.cross_show_v:
		draw_line(
			Vector2(map_cx, world_top),
			Vector2(map_cx, world_bottom),
			parent_mod.CROSS_LINE_COLOR,
			parent_mod.CROSS_LINE_WIDTH
		)
	
	if parent_mod.cross_show_h:
		draw_line(
			Vector2(world_left, map_cy),
			Vector2(world_right, map_cy),
			parent_mod.CROSS_LINE_COLOR,
			parent_mod.CROSS_LINE_WIDTH
		)
