extends Reference

class_name GuidesLinesRender

# ============================================================================
# CONSTANTS & STYLING
# ============================================================================

const TEXT_SCALE = 4.0 # For high-res text scaling

# ============================================================================
# DRAWING PRIMITIVES
# ============================================================================

# Calculates adaptive line width based on camera zoom
static func get_adaptive_width(base_width: float, time_scale: Vector2) -> float:
	var width = base_width
	var zoom_factor = time_scale.x
	
	# Apply scaling for small zoom levels (zoomed out)
	if zoom_factor > 1.0:
		# Linear scaling: width increases proportionally to zoom
		width = base_width * zoom_factor
	
	if width < 1.0: 
		width = 1.0 # Minimum 1px
		
	return width

# Draws a line with adaptive width
static func draw_adaptive_line(canvas: CanvasItem, start: Vector2, end: Vector2, color: Color, base_width: float, time_scale: Vector2):
	var width = get_adaptive_width(base_width, time_scale)
	canvas.draw_line(start, end, color, width)

# Draws text with a black outline
static func draw_text_with_outline(canvas: CanvasItem, text: String, position: Vector2, color: Color, font: Font = null):
	var outline_color = Color(0, 0, 0, 0.8)
	var outline_offset = 2
	
	# Set transform for high-res text
	canvas.draw_set_transform(position, 0, Vector2(TEXT_SCALE, TEXT_SCALE))
	
	# Draw outline (offset positions)
	for dx in [-outline_offset, 0, outline_offset]:
		for dy in [-outline_offset, 0, outline_offset]:
			if dx != 0 or dy != 0:
				# Use offset relative to scaled space, or separate draw calls
				# The logic in PermanentOverlay was:
				# draw_set_transform(position + Vector2(dx, dy), ...)
				# This means the offset is in WORLD space before scaling? 
				# No, let's look at PermanentOverlay code again: 
				# draw_set_transform(position + Vector2(dx, dy), 0, Vector2(scale, scale))
				# outline_offset was 2. So 2 units in world space.
				
				# However, shifting the transform repeatedly is expensive.
				# A better approach if we are already scaled is to just draw with offset if possible?
				# canvas.draw_string takes position.
				
				# Replicating PermanentOverlay logic exactly for now to be safe:
				canvas.draw_set_transform(position + Vector2(dx, dy), 0, Vector2(TEXT_SCALE, TEXT_SCALE))
				if font:
					canvas.draw_string(font, Vector2.ZERO, text, outline_color, -1)
				else:
					# Fallback if no font provided (though usually required in Godot 3)
					canvas.draw_string(null, Vector2.ZERO, text, outline_color, -1)
	
	# Draw main text
	canvas.draw_set_transform(position, 0, Vector2(TEXT_SCALE, TEXT_SCALE))
	if font:
		canvas.draw_string(font, Vector2.ZERO, text, color, -1)
	else:
		canvas.draw_string(null, Vector2.ZERO, text, color, -1)
	
	# Reset transform
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# ============================================================================
# COMPLEX SHAPES
# ============================================================================

# Draws an arrow (line + head)
static func draw_arrow(canvas: CanvasItem, start: Vector2, end: Vector2, head_points: Array, color: Color, width: float):
	canvas.draw_line(start, end, color, width)
	if head_points.size() >= 2:
		canvas.draw_line(end, head_points[0], color, width)
		canvas.draw_line(end, head_points[1], color, width)

# Draws a polygon outline
static func draw_polygon_outline(canvas: CanvasItem, vertices: Array, color: Color, width: float):
	if vertices.size() < 2:
		return
		
	for i in range(vertices.size()):
		var p1 = vertices[i]
		var p2 = vertices[(i + 1) % vertices.size()]
		canvas.draw_line(p1, p2, color, width)
