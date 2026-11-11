extends Node

# OptionalMods - Optional grid support and UnofficialPatch context-menu provider.
const CLASS_NAME = "OptionalMods"
const GeometryUtils = preload("../utils/GeometryUtils.gd")
const HOST_META = "_up_rcm_host"
const PROVIDERS_META = "_up_rcm_providers"
const PROVIDER_ID = "Choson.GuidesLines"
const MAX_MARKER_COORD_SAMPLES = 1000

var parent_mod = null
var custom_snap = null
var _target = null
var _click_position = Vector2.ZERO
var _world = null
var _menu_host_available = null

func update() -> void:
	var global = parent_mod.Global
	# Resolve every update: optional APIs may register late or be replaced.
	var snap = global.API.get("snappy_mod") if global.API else null
	if snap != null and (not is_instance_valid(snap) or not snap.has_method("get_snapped_position")):
		snap = null
	if snap != custom_snap:
		if snap and parent_mod.LOGGER:
			parent_mod.LOGGER.info("Found custom_snap API: snappy_mod")
	custom_snap = snap
	_world = global.World
	var available = _host_available()
	if available != _menu_host_available:
		_menu_host_available = available
		if parent_mod.LOGGER:
			parent_mod.LOGGER.info("UnofficialPatch Select menu host: " + ("available (API v1)" if available else "unavailable for this map"))
	if not available:
		_unregister()
		return
	var entries = Engine.get_meta(PROVIDERS_META) if Engine.has_meta(PROVIDERS_META) else []
	if not entries is Array:
		return
	for entry in entries:
		if entry is Dictionary and entry.get("id") == PROVIDER_ID and entry.get("provider") == self and entry.get("world") == _world:
			return
	var kept = []
	for entry in entries:
		if not (entry is Dictionary and entry.get("id") == PROVIDER_ID):
			kept.append(entry)
	kept.append({"id": PROVIDER_ID, "provider": self, "world": _world, "order": 1000})
	Engine.set_meta(PROVIDERS_META, kept)

func _host_available() -> bool:
	if parent_mod == null or _world == null or not is_instance_valid(_world) or not Engine.has_meta(HOST_META):
		return false
	var host = Engine.get_meta(HOST_META)
	return host is Dictionary and host.get("version") == 1 and host.get("world") == _world and parent_mod.Global.World == _world

func _unregister() -> void:
	_target = null
	if not Engine.has_meta(PROVIDERS_META):
		return
	var entries = Engine.get_meta(PROVIDERS_META)
	if not entries is Array:
		return
	var kept = []
	for entry in entries:
		if not (entry is Dictionary and entry.get("provider") == self):
			kept.append(entry)
	if kept.size() != entries.size():
		Engine.set_meta(PROVIDERS_META, kept)

func _exit_tree():
	_unregister()
	custom_snap = null
	parent_mod = null

func get_context_items(_raw) -> Array:
	return get_void_context_items()

func get_void_context_items() -> Array:
	_target = null
	if not _host_available() or not parent_mod.markers_visible:
		return []
	var global = parent_mod.Global
	var tool = parent_mod.guides_tool
	if global.Editor == null or global.Editor.ActiveToolName != "SelectTool" or tool == null or not is_instance_valid(tool.overlay):
		return []
	if not global.WorldUI or not global.WorldUI.IsInsideBounds or not tool.overlay._is_mouse_over_canvas():
		return []
	_click_position = global.WorldUI.MousePosition
	_target = tool.find_marker_at(_click_position, 20.0)
	if _target == null:
		return []
	return [{"label": "Guide Marker", "submenu": [
		{"label": "Move", "action_id": "move"}, {"label": "Delete", "action_id": "delete"}]}]

func on_context_action(action_id, _raw) -> void:
	if not _host_available() or _target == null:
		return
	var global = parent_mod.Global
	var tool = parent_mod.guides_tool
	var marker = _target
	_target = null
	if tool == null or tool.markers_lookup.get(marker.id) != marker or global.Editor == null or global.Editor.ActiveToolName != "SelectTool":
		return
	if not is_instance_valid(tool.overlay) or not is_instance_valid(tool.overlay.context_menu):
		return
	var menu = tool.overlay.context_menu
	if action_id == "move":
		if not global.Editor.Toolset:
			return
		global.Editor.Toolset.Quickswitch("GuidesLinesTool")
		if global.Editor.ActiveToolName != "GuidesLinesTool":
			return
		# Quickswitch changes the host immediately; the mod's update follows later.
		if not tool.is_enabled:
			tool.Enable()
		menu.execute(menu.MOVE, marker, _click_position)
	elif action_id == "delete":
		menu.execute(menu.DELETE, marker, _click_position)

static func snap_enabled(snap) -> bool:
	return snap != null and (typeof(snap) != TYPE_OBJECT or is_instance_valid(snap)) and snap.custom_snap_enabled

static func snap_position(position: Vector2, snap, worldui) -> Vector2:
	if snap_enabled(snap) and snap.has_method("get_snapped_position"):
		return snap.get_snapped_position(position)
	return worldui.GetSnappedPosition(position) if worldui else position

static func grid_cell_size(world, snap):
	if not world:
		return null
	if snap_enabled(snap):
		return snap.snap_interval
	if not world.Level or not world.Level.TileMap:
		return null
	return world.Level.TileMap.CellSize

# custom_snap: SQUARE=0, HEX_V=1, HEX_H=2, ISOMETRIC=3. Edge mode uses
# the apothem as one grid unit; Side needs the circumradius instead.
static func hex_edge_correction(snap) -> float:
	if snap_enabled(snap) and snap.active_geometry in [1, 2] and not snap.radial_mode_to_corner:
		return 2.0 / sqrt(3.0)
	return 1.0

static func build_marker_coordinates(position: Vector2, direction: Vector2, perp: Vector2, map_rect: Rect2, custom_snap, points: Array) -> void:
	var snap_interval = custom_snap.snap_interval
	if snap_interval.x <= 0 or snap_interval.y <= 0 or is_nan(snap_interval.x) or is_nan(snap_interval.y) or is_inf(snap_interval.x) or is_inf(snap_interval.y):
		return
	var max_dist      = map_rect.size.length()
	if max_dist <= 0 or is_nan(max_dist) or is_inf(max_dist):
		return
	# ponytail: at most 1000 samples per ray; dense grids get sparse labels across
	# the full map. Enumerate visible grid nodes if every label becomes necessary.
	var test_spacing = max(min(snap_interval.x, snap_interval.y) * 0.5, max_dist / MAX_MARKER_COORD_SAMPLES)
	var checked       = {}
	for i in range(MAX_MARKER_COORD_SAMPLES):
		var distance = test_spacing * (i + 1)
		if distance >= max_dist:
			break
		var test_pos = position + direction * distance
		var snapped  = custom_snap.get_snapped_position(test_pos)
		if not map_rect.has_point(snapped):
			continue
		var key = Vector2(int(snapped.x * 10), int(snapped.y * 10))
		if not checked.has(key):
			if GeometryUtils.is_point_on_ray(position, direction, snapped, deg2rad(5.0)):
				checked[key] = true
				var grid_dist = round(snapped.distance_to(position) / min(snap_interval.x, snap_interval.y))
				points.append({
					"grid_pos": snapped,
					"text":     str(int(grid_dist)),
					"perp":     perp
				})


static func build_guide_coordinates(axis: int, center: Vector2, low: Vector2, high: Vector2, map_rect: Rect2, snap, points: Array, checked: Dictionary, max_iterations: int) -> bool:
	var text_dir = Vector2(1, 0) if axis == 1 else Vector2(0, -1)
	var interval = snap.snap_interval
	var spacing = min(interval.x, interval.y) * 0.5
	if spacing <= 0.0:
		return false
	checked.clear()
	var coordinate = low[axis]
	var iterations = 0
	# ponytail: bound sampling to max_iterations; enumerate grid nodes if larger views need labels.
	while coordinate <= high[axis] and iterations < max_iterations:
		var test_pos = center
		test_pos[axis] = coordinate
		var snapped = snap.get_snapped_position(test_pos)
		var key = int(snapped[axis] * 10)
		if abs(snapped[1 - axis] - center[1 - axis]) < 0.5 and abs(snapped[axis] - center[axis]) > 0.5:
			if not checked.has(key) and map_rect.has_point(snapped):
				checked[key] = true
				var delta = snapped - center - snap.snap_offset
				points.append({"pos": snapped, "text": str(int(round(abs(delta[axis]) / interval[axis]))), "text_dir": text_dir})
		coordinate += spacing
		iterations += 1
	return iterations >= max_iterations
