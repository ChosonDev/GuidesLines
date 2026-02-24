extends Reference

# FillMarker - Data class for a filled polygon region.
# Analogous to GuideMarker but stores only a filled polygon and its color.
# Created by Fill Mode when the user clicks inside a Shape marker's polygon.
#
# The fill color is always stored with alpha = 0.25 (25% opacity).
# The RGB channels come from the tool's active_color at the time of creation.

var id = -1
var polygon = []   # Array[Vector2] — world-space vertices of the filled polygon
var color = Color(0, 0.7, 1, 0.25)  # Fill color (alpha always 0.25)

# CACHED DRAW COLOR — pre-multiplied with global opacity so _draw never allocs Color.
# Call update_opacity() whenever opacity setting changes.
var draw_color = Color(0, 0.7, 1, 0.25)

func _init():
	pass

# Refresh cached draw color for the given global opacity (0.0–1.0).
func update_opacity(opacity: float) -> void:
	draw_color = Color(color.r, color.g, color.b, color.a * opacity)

# ============================================================================
# SERIALISATION
# ============================================================================

# Serialize to a Dictionary suitable for HistoryApi records and map saves.
func Save() -> Dictionary:
	var pts = []
	for p in polygon:
		pts.append([p.x, p.y])
	return {
		"id":      id,
		"color":   "#" + Color(color.r, color.g, color.b, 1.0).to_html(),
		"polygon": pts
	}

# Deserialize from a Dictionary produced by Save().
func Load(data: Dictionary) -> void:
	id = data.get("id", -1)

	polygon = []
	for pt in data.get("polygon", []):
		polygon.append(Vector2(pt[0], pt[1]))

	var hex = data.get("color", "")
	if hex != "":
		var c = Color(hex.lstrip("#"))
		color = Color(c.r, c.g, c.b, 0.25)
	else:
		color = Color(0, 0.7, 1, 0.25)
