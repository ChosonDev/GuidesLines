extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..").simplify_path()
var tool
var overlay
var menu
var records = []
var integration_nodes = []
var engine_meta = {}
var switcher = null

class IntegrationWorld:
	extends Node
	var WorldRect = Rect2(-1000, -1000, 2000, 2000)
	var Level = {"TileMap": {"CellSize": Vector2(100, 100)}}

class ToolSwitcher:
	extends Reference
	var editor
	var enabled = true
	func Quickswitch(name):
		if enabled:
			editor.ActiveToolName = name

class Snap:
	extends Reference
	var custom_snap_enabled = true
	var snap_interval = Vector2(25, 50)
	var snap_offset = Vector2(3, 7)
	var active_geometry = 1
	var radial_mode_to_corner = false
	var calls = 0
	func get_snapped_position(position):
		calls += 1
		return ((position - snap_offset) / snap_interval).snapped(Vector2.ONE) * snap_interval + snap_offset

class WorldUI:
	extends Reference
	var IsInsideBounds = true
	var MousePosition = Vector2.ZERO
	func GetSnappedPosition(position):
		return position.snapped(Vector2(100, 100))

func before_each():
	for name in ["_up_rcm_host", "_up_rcm_providers"]:
		if Engine.has_meta(name):
			engine_meta[name] = Engine.get_meta(name)
			Engine.remove_meta(name)
	var mod = {"markers_opacity": 0.7, "guides_lines_api": null,
		"Global": {"API": {"HistoryApi": self}, "Editor": {"IsSnapping": false}}}
	tool = load(mod_root.plus_file("scripts/tool/GuidesLinesTool.gd")).new(mod)
	tool.GuideMarkerClass = load(mod_root.plus_file("scripts/guides/GuideMarker.gd"))
	tool.cached_world = {"WorldRect": Rect2(-1000, -1000, 2000, 2000),
		"Level": {"TileMap": {"CellSize": Vector2(100, 100)}}}
	tool.cached_worldui = WorldUI.new()
	tool.is_enabled = true
	var script = GDScript.new()
	script.source_code = 'extends "' + mod_root.plus_file("scripts/overlays/MarkerOverlay.gd") + '"\nvar over_canvas = true\nfunc _is_mouse_over_canvas():\n\treturn over_canvas\n'
	assert_eq(script.reload(), OK)
	overlay = script.new()
	overlay.tool = tool
	tool.overlay = overlay
	add_child(overlay)
	overlay.set_process(false)
	overlay.set_process_input(false)
	menu = overlay.context_menu
	menu.set_process(false)
	records = []

func after_each():
	for node in integration_nodes:
		if is_instance_valid(node):
			node.free()
	integration_nodes.clear()
	if switcher:
		switcher.editor = null
	switcher = null
	for name in ["_up_rcm_host", "_up_rcm_providers"]:
		if Engine.has_meta(name):
			Engine.remove_meta(name)
		if engine_meta.has(name):
			Engine.set_meta(name, engine_meta[name])
	engine_meta.clear()
	overlay.free()
	tool.overlay = null
	records.clear()
	tool.ui.tool = null
	tool.placement.tool = null
	tool._fill_handler.tool = null
	tool.parent_mod = null
	tool = null
	menu = null
	overlay = null

func record(value, _max_count):
	records.append(value)

func add_marker(id = 1, kind = "Shape"):
	tool._do_place_marker({"id": id, "position": Vector2.ZERO, "marker_type": kind,
		"color": Color.blue, "path_closed": false, "shape_sides": 4, "shape_radius": 1.0,
		"marker_points": [Vector2.ZERO, Vector2(50, 0)]})
	return tool.markers_lookup[id]

func click(button = BUTTON_RIGHT, pressed = true):
	var event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	overlay.handle_content_input(event)

func open_menu(expected_header = ""):
	tool.cached_worldui.MousePosition = Vector2(5, 0)
	click()
	assert_true(menu.popup.visible)
	assert_eq(menu.popup.get_item_count(), 9)
	assert_true(menu.popup.is_item_disabled(0))
	if expected_header != "":
		assert_eq(menu.popup.get_item_text(0), expected_header)
	assert_true(menu.popup.is_item_separator(1))
	assert_eq(menu.popup.get_item_text(2), "Move")
	assert_eq(menu.popup.get_item_text(3), "Duplicate")
	assert_eq(menu.popup.get_item_text(4), "Pick Settings")
	assert_eq(menu.popup.get_item_text(5), "Apply Active Color")
	assert_eq(menu.popup.get_item_text(6), "Save as Template")
	assert_true(menu.popup.is_item_separator(7))
	assert_eq(menu.popup.get_item_text(8), "Delete")

func test_path_finish_takes_priority_over_existing_marker_menu():
	add_marker()
	tool.set_marker_type("Path")
	tool.path_placement_active = true
	tool.path_temp_points = [Vector2(50, 50), Vector2(5, 0)]
	tool.cached_worldui.MousePosition = Vector2(5, 0)
	click()
	assert_false(tool.path_placement_active)
	assert_false(menu.popup.visible)
	assert_eq(tool.markers.size(), 2)
	assert_eq(tool.markers.back().marker_type, "Path")
	assert_eq(records.size(), 1)

func test_dismissed_popup_releases_target_without_cancelling_selected_move():
	var marker = add_marker()
	open_menu()
	menu.popup.hide()
	yield(get_tree(), "idle_frame")
	assert_null(menu._target)
	assert_false(menu._moving)
	open_menu()
	# Godot may emit popup_hide before id_pressed.
	menu.popup.hide()
	menu.popup.emit_signal("id_pressed", menu.MOVE)
	yield(get_tree(), "idle_frame")
	assert_true(menu._target == marker)
	assert_true(menu._moving)
	assert_true(tool._move_selected_marker == marker)

func test_dense_custom_snap_marker_coordinates_bound_work_across_full_map():
	var support = load(mod_root.plus_file("scripts/integrations/OptionalMods.gd"))
	var snap = Snap.new()
	snap.snap_offset = Vector2.ZERO
	var rect = Rect2(0, 0, 40000, 40000)
	for interval in [Vector2(100, 100), Vector2(0.5, 0.5), Vector2(0.000001, 0.000001)]:
		snap.snap_interval = interval
		snap.calls = 0
		var points = []
		support.build_marker_coordinates(Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, rect, snap, points)
		assert_true(snap.calls <= support.MAX_MARKER_COORD_SAMPLES)
		assert_true(points.size() > 0)
		assert_true(points.back().grid_pos.x > 39000, "Dense sampling still reaches the far end")
		for point in points:
			assert_true(rect.has_point(point.grid_pos))
			assert_eq(point.text, str(int(round(point.grid_pos.length() / interval.x))))
	for invalid in [Vector2.ZERO, Vector2(-1, 1), Vector2(NAN, 1), Vector2(INF, 1)]:
		snap.snap_interval = invalid
		snap.calls = 0
		var points = []
		support.build_marker_coordinates(Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, rect, snap, points)
		assert_eq(snap.calls, 0)
		assert_true(points.empty())

func test_marker_context_move_click_commits_once_with_history_and_offset():
	for kind in ["Line", "Shape", "Path"]:
		var marker = add_marker(1, kind)
		open_menu()
		menu.popup.emit_signal("id_pressed", menu.MOVE)
		assert_true(tool.move_mode)
		assert_true(tool._move_selected_marker == marker)
		assert_eq(marker.position, Vector2.ZERO, "Movement remains a preview")
		tool.cached_worldui.MousePosition = Vector2(135, 240)
		overlay._process(0.0)
		assert_eq(tool._move_drag_pos, Vector2(135, 240))
		click(BUTTON_LEFT, false)
		assert_true(records.empty(), "Releasing the menu click cannot commit movement")
		click(BUTTON_LEFT)
		assert_eq(marker.position, Vector2(130, 240))
		assert_null(tool._move_selected_marker)
		assert_eq(records.size(), 1)
		click(BUTTON_LEFT, false)
		assert_eq(records.size(), 1)
		records[0].undo()
		assert_eq(marker.position, Vector2.ZERO)
		records[0].redo()
		assert_eq(marker.position, Vector2(130, 240))
		tool.markers.clear()
		tool.markers_lookup.clear()
		records.clear()

func test_marker_context_cancel_inputs_bounds_and_snapping():
	var marker = add_marker()
	var key = InputEventKey.new()
	key.scancode = KEY_SHIFT
	key.pressed = true
	for event in [key, _button(BUTTON_RIGHT), _button(BUTTON_MIDDLE), _button(BUTTON_WHEEL_UP)]:
		open_menu()
		menu._on_action(menu.MOVE)
		overlay._input(event)
		assert_null(tool._move_selected_marker)
		assert_eq(marker.position, Vector2.ZERO)
		assert_true(records.empty())
	for outside_ui in [false, true]:
		open_menu()
		menu._on_action(menu.MOVE)
		overlay.over_canvas = not outside_ui
		tool.cached_worldui.IsInsideBounds = outside_ui
		click(BUTTON_LEFT)
		assert_null(tool._move_selected_marker)
		assert_eq(marker.position, Vector2.ZERO)
		assert_true(records.empty())
		overlay.over_canvas = true
		tool.cached_worldui.IsInsideBounds = true
	open_menu()
	menu._on_action(menu.MOVE)
	tool.parent_mod.Global.Editor.IsSnapping = true
	tool.cached_worldui.MousePosition = Vector2(138, 247)
	var expected = tool.snap_position_to_grid(Vector2(133, 247))
	click(BUTTON_LEFT)
	assert_eq(marker.position, expected)
	assert_eq(records.size(), 1)

func _button(button):
	var event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event

func test_marker_context_delete_targets_original_marker_and_rejects_stale_actions():
	var marker = add_marker()
	open_menu()
	add_marker(2)
	tool.cached_worldui.MousePosition = Vector2(500, 500)
	menu.popup.emit_signal("id_pressed", menu.DELETE)
	assert_false(tool.markers_lookup.has(marker.id))
	assert_true(tool.markers_lookup.has(2))
	assert_eq(records.size(), 1)
	records[0].undo()
	assert_true(tool.markers_lookup.has(marker.id))
	records[0].redo()
	assert_false(tool.markers_lookup.has(marker.id))
	open_menu()
	tool.markers_lookup.clear()
	tool.markers.clear()
	menu._on_action(menu.DELETE)
	assert_eq(records.size(), 1, "A stale target never deletes a different marker")
	assert_false(menu.popup.visible)

func test_marker_context_empty_canvas_fallback_and_lifecycle_cleanup():
	tool.active_marker_type = "Shape"
	click()
	assert_false(menu.popup.visible)
	assert_eq(tool.active_shape_angle, 45.0)
	var marker = add_marker()
	open_menu()
	menu._on_action(menu.MOVE)
	tool.Disable()
	assert_false(menu.popup.visible)
	assert_null(tool._move_selected_marker)
	assert_eq(marker.position, Vector2.ZERO)
	tool.Enable()
	open_menu()
	menu._on_action(menu.MOVE)
	tool.markers_lookup.clear()
	menu._process(0.0)
	assert_null(tool._move_selected_marker)
	assert_true(records.empty())
	tool.markers_lookup[marker.id] = marker
	open_menu()
	menu._on_action(menu.MOVE)
	menu.get_parent().remove_child(menu)
	assert_null(tool._move_selected_marker, "Removing the overlay's menu cancels transient movement")
	menu.free()
	overlay.context_menu = null

func test_marker_context_popup_routes_native_keyboard_selection():
	add_marker()
	open_menu("Shape #1")
	var event = InputEventKey.new()
	event.pressed = true
	# Exercise Godot's modal GUI routing, not only the action callback.
	overlay.set_process_input(true)
	event.scancode = KEY_DOWN
	for _i in range(6):
		Input.parse_input_event(event)
	event.scancode = KEY_ENTER
	Input.parse_input_event(event)
	yield(get_tree(), "idle_frame")
	assert_false(menu.popup.visible)
	assert_false(tool.markers_lookup.has(1))
	assert_eq(records.size(), 1)

func test_marker_context_duplicate_pick_recolor_and_template():
	var marker = add_marker(1, "Shape")
	marker.set_property("shape_sides", 6)
	marker.set_property("shape_radius", 2.5)
	marker.set_property("shape_angle", 30.0)
	marker.set_property("color", Color.green)
	# Duplicate: preview then commit on LMB with undo/redo
	open_menu("Shape #1")
	menu.popup.emit_signal("id_pressed", menu.DUPLICATE)
	assert_true(tool.move_mode)
	assert_true(tool._move_selected_marker == marker)
	assert_eq(tool.markers.size(), 1, "Duplicate waits for placement click")
	tool.cached_worldui.MousePosition = Vector2(205, 100)
	click(BUTTON_LEFT)
	assert_eq(tool.markers.size(), 2)
	assert_eq(marker.position, Vector2.ZERO, "Original marker stays in place")
	var dup = tool.markers[1]
	assert_eq(dup.position, Vector2(200, 100))
	assert_eq(dup.shape_sides, 6)
	assert_eq(dup.shape_radius, 2.5)
	assert_eq(dup.color, Color.green)
	assert_eq(records.size(), 1)
	records[0].undo()
	assert_eq(tool.markers.size(), 1)
	records[0].redo()
	assert_eq(tool.markers.size(), 2)
	# Apply Active Color with undo/redo
	tool.active_color = Color.red
	open_menu("Shape #1")
	menu.popup.emit_signal("id_pressed", menu.APPLY_COLOR)
	assert_eq(marker.color, Color.red)
	assert_almost_eq(marker.draw_color.a, 0.7, 0.0001)
	assert_eq(records.size(), 2)
	records[1].undo()
	assert_eq(marker.color, Color.green)
	records[1].redo()
	assert_eq(marker.color, Color.red)
	# Save as Template in one click
	open_menu("Shape #1")
	menu.popup.emit_signal("id_pressed", menu.SAVE_TEMPLATE)
	assert_eq(tool.templates.size(), 1)
	assert_eq(tool.templates[0].data.shape_sides, 6)
	# Pick Settings copies type/params/color and exits move mode
	tool.active_color = Color.white
	tool.set_marker_type("Line")
	tool.set_move_mode(true)
	open_menu("Shape #1")
	menu.popup.emit_signal("id_pressed", menu.PICK_SETTINGS)
	assert_false(tool.move_mode)
	assert_eq(tool.active_marker_type, "Shape")
	assert_eq(tool.active_shape_sides, 6)
	assert_eq(tool.active_shape_radius, 2.5)
	assert_eq(tool.active_shape_angle, 30.0)
	assert_eq(tool.active_color, Color.red)

func integrations():
	var world = IntegrationWorld.new()
	add_child(world)
	integration_nodes.append(world)
	tool.cached_world = world
	var mod = tool.parent_mod
	mod["LOGGER"] = null
	mod["markers_visible"] = true
	mod["guides_tool"] = tool
	mod.Global["World"] = world
	mod.Global["WorldUI"] = tool.cached_worldui
	mod.Global.Editor["ActiveToolName"] = "SelectTool"
	switcher = ToolSwitcher.new()
	switcher.editor = mod.Global.Editor
	mod.Global.Editor["Toolset"] = switcher
	tool.Disable()
	var support = load(mod_root.plus_file("scripts/integrations/OptionalMods.gd")).new()
	support.parent_mod = mod
	world.add_child(support)
	return support

func test_optional_mods_registration_late_host_session_and_cleanup():
	var support = integrations()
	support.update()
	assert_false(Engine.has_meta("_up_rcm_providers"))
	var unrelated = {"id": "another.mod", "provider": self, "world": tool.cached_world}
	Engine.set_meta("_up_rcm_providers", [unrelated])
	Engine.set_meta("_up_rcm_host", {"world": tool.cached_world, "version": 1})
	for _i in range(3): support.update()
	var entries = Engine.get_meta("_up_rcm_providers")
	assert_eq(entries.size(), 2, "Repeated updates cannot duplicate registration")
	assert_true(entries[1].provider == support)
	assert_true(entries[1].world == tool.cached_world)
	var other_world = Node.new()
	Engine.set_meta("_up_rcm_host", {"world": other_world, "version": 1})
	support.update()
	assert_eq(Engine.get_meta("_up_rcm_providers").size(), 1)
	other_world.free()
	Engine.set_meta("_up_rcm_host", {"world": tool.cached_world, "version": 2})
	support.update()
	assert_eq(Engine.get_meta("_up_rcm_providers").size(), 1, "Unsupported API versions stay optional")
	Engine.set_meta("_up_rcm_host", {"world": tool.cached_world, "version": 1})
	support.update()
	support.free()
	assert_eq_deep(Engine.get_meta("_up_rcm_providers"), [unrelated])

func test_optional_mods_select_menu_uses_up_dispatch_move_delete_and_history():
	var support = integrations()
	Engine.set_meta("_up_rcm_host", {"world": tool.cached_world, "version": 1})
	support.update()
	var marker = add_marker()
	tool.cached_worldui.MousePosition = Vector2(5, 0)
	var items = support.get_void_context_items()
	assert_eq(items[0].label, "Guide Marker")
	assert_eq(items[0].submenu.size(), 5)
	# Exercise the real upstream provider collector, submenu builder and dispatch.
	var upstream_path = mod_root.plus_file("../../ExternalMods/UnofficialPatch/scripts/right_click_util.gd").simplify_path()
	var upstream = load(upstream_path).new()
	upstream._g = tool.parent_mod.Global
	assert_eq(upstream._external_entries().size(), 1)
	var native_menu = PopupMenu.new()
	upstream._fill_menu(native_menu, upstream._normalize_items(items, support))
	var submenu = native_menu.get_node(native_menu.get_item_submenu(0))
	tool.cached_worldui.MousePosition = Vector2(300, 400)
	submenu.emit_signal("id_pressed", submenu.get_item_id(0))
	assert_eq(tool.parent_mod.Global.Editor.ActiveToolName, "GuidesLinesTool")
	assert_true(tool.is_enabled)
	assert_true(tool.move_mode)
	assert_true(tool._move_selected_marker == marker)
	assert_eq(marker.position, Vector2.ZERO)
	click(BUTTON_LEFT)
	assert_eq(marker.position, Vector2(295, 400), "Keep the original right-click offset")
	assert_eq(records.size(), 1)
	records[0].undo()
	assert_eq(marker.position, Vector2.ZERO)
	records[0].redo()
	assert_eq(marker.position, Vector2(295, 400))
	# Save as Template works directly from SelectTool without switching tools
	tool.Disable()
	tool.parent_mod.Global.Editor.ActiveToolName = "SelectTool"
	tool.cached_worldui.MousePosition = marker.position
	assert_eq(support.get_context_items(["native selection"]).size(), 1)
	submenu.emit_signal("id_pressed", submenu.get_item_id(2))
	assert_eq(tool.templates.size(), 1)
	assert_eq(tool.parent_mod.Global.Editor.ActiveToolName, "SelectTool")
	# Duplicate from SelectTool switches to GuidesLinesTool and places copy on LMB
	assert_eq(support.get_context_items(["native selection"]).size(), 1)
	submenu.emit_signal("id_pressed", submenu.get_item_id(1))
	assert_eq(tool.parent_mod.Global.Editor.ActiveToolName, "GuidesLinesTool")
	tool.cached_worldui.MousePosition = Vector2(100, 100)
	click(BUTTON_LEFT)
	assert_eq(tool.markers.size(), 2)
	# Pick Settings from SelectTool switches to GuidesLinesTool and copies settings
	tool.Disable()
	tool.parent_mod.Global.Editor.ActiveToolName = "SelectTool"
	tool.active_marker_type = "Line"
	tool.cached_worldui.MousePosition = marker.position
	assert_eq(support.get_context_items(["native selection"]).size(), 1)
	submenu.emit_signal("id_pressed", submenu.get_item_id(3))
	assert_eq(tool.parent_mod.Global.Editor.ActiveToolName, "GuidesLinesTool")
	assert_eq(tool.active_marker_type, "Shape")
	# Delete from SelectTool works without switching tools
	tool.Disable()
	tool.parent_mod.Global.Editor.ActiveToolName = "SelectTool"
	tool.cached_worldui.MousePosition = marker.position
	assert_eq(support.get_context_items(["native selection"]).size(), 1)
	add_marker(99)
	tool.cached_worldui.MousePosition = Vector2.ZERO
	submenu.emit_signal("id_pressed", submenu.get_item_id(4))
	assert_false(tool.markers_lookup.has(marker.id))
	assert_true(tool.markers_lookup.has(99))
	assert_eq(tool.parent_mod.Global.Editor.ActiveToolName, "SelectTool")
	assert_eq(records.size(), 3)
	records[2].undo()
	assert_true(tool.markers_lookup.has(marker.id))
	native_menu.free()
	upstream._g = null

func test_optional_mods_select_menu_gates_and_stale_target():
	var support = integrations()
	Engine.set_meta("_up_rcm_host", {"world": tool.cached_world, "version": 1})
	support.update()
	var marker = add_marker()
	for gate in ["hidden", "outside", "panel", "tool", "empty"]:
		tool.parent_mod.markers_visible = gate != "hidden"
		tool.cached_worldui.IsInsideBounds = gate != "outside"
		overlay.over_canvas = gate != "panel"
		tool.parent_mod.Global.Editor.ActiveToolName = "WallTool" if gate == "tool" else "SelectTool"
		tool.cached_worldui.MousePosition = Vector2(500, 500) if gate == "empty" else Vector2.ZERO
		assert_true(support.get_void_context_items().empty(), gate)
	tool.cached_worldui.MousePosition = Vector2.ZERO
	assert_eq(support.get_void_context_items().size(), 1)
	tool._undo_place_marker(marker.id)
	support.on_context_action("delete", null)
	assert_true(records.empty())
	add_marker()
	assert_eq(support.get_void_context_items().size(), 1)
	switcher.enabled = false
	support.on_context_action("move", null)
	assert_null(tool._move_selected_marker, "A failed host tool switch cannot start movement")
	assert_false(tool.is_enabled)
	assert_eq(support.get_void_context_items().size(), 1)
	Engine.remove_meta("_up_rcm_host")
	support.on_context_action("delete", null)
	assert_true(tool.markers_lookup.has(1), "A menu opened in an expired host session cannot mutate markers")

func test_optional_mods_custom_snap_late_replaced_disabled_and_grid_helpers():
	var support = integrations()
	support.update()
	assert_null(support.custom_snap)
	var snap = Snap.new()
	tool.parent_mod.Global.API["snappy_mod"] = snap
	support.update()
	assert_true(support.custom_snap == snap)
	tool.cached_snappy_mod = support.custom_snap
	assert_eq(tool._get_grid_cell_size(), snap.snap_interval)
	assert_almost_eq(tool._get_hex_edge_correction(), 2.0 / sqrt(3.0), 0.00001)
	var position = Vector2(41, 72)
	assert_eq(tool.snap_position_to_grid(position), snap.get_snapped_position(position))
	snap.custom_snap_enabled = false
	assert_eq(tool._get_grid_cell_size(), Vector2(100, 100))
	assert_eq(tool._get_hex_edge_correction(), 1.0)
	assert_eq(tool.snap_position_to_grid(position), tool.cached_worldui.GetSnappedPosition(position))
	snap.custom_snap_enabled = true
	for geometry in [0, 1, 2, 3]:
		snap.active_geometry = geometry
		assert_almost_eq(tool._get_hex_edge_correction(), 2.0 / sqrt(3.0) if geometry in [1, 2] else 1.0, 0.00001)
	var replacement = Snap.new()
	tool.parent_mod.Global.API["snappy_mod"] = replacement
	support.update()
	assert_true(support.custom_snap == replacement)
	tool.parent_mod.Global.API.erase("snappy_mod")
	support.update()
	assert_null(support.custom_snap)

class SelectHost:
	extends Reference
	var RawSelectables = []

class EditorHost:
	extends Node
	var ActiveToolName = "SelectTool"
	var Tools = {}
	var Toolset = null
	var Windows = {}
	var IsSnapping = false

func test_optional_mods_full_up_right_click_opens_without_native_selection():
	var support = integrations()
	var editor = EditorHost.new()
	integration_nodes.append(editor)
	add_child(editor)
	editor.Tools["SelectTool"] = SelectHost.new()
	tool.parent_mod.Global.Editor = editor
	tool.parent_mod.Global["ModMapData"] = {}
	var parent = editor
	for name in ["VPartition", "Panels", "HSplit", "Content"]:
		var control = Control.new()
		control.name = name
		control.rect_size = Vector2(2000, 2000)
		parent.add_child(control)
		parent = control
	# Use the real canvas gate rather than the override used by unit input tests.
	var real_overlay = load(mod_root.plus_file("scripts/overlays/MarkerOverlay.gd")).new()
	real_overlay.tool = tool
	real_overlay.context_menu = menu
	tool.overlay = real_overlay
	var marker = add_marker()
	var upstream_path = mod_root.plus_file("../../ExternalMods/UnofficialPatch/scripts/right_click_util.gd").simplify_path()
	var upstream = load(upstream_path).new()
	upstream._g = tool.parent_mod.Global
	upstream.initialize()
	support.update()
	# Exercise the upstream entry point, including its gates and void branch.
	upstream._on_right_click()
	assert_not_null(upstream._context_menu, "No native Select selection is required")
	if upstream._context_menu != null:
		assert_true(upstream._context_menu.visible)
		assert_eq(upstream._context_menu.get_item_text(0), "Guide Marker")
		var submenu = upstream._context_menu.get_node(upstream._context_menu.get_item_submenu(0))
		submenu.emit_signal("id_pressed", submenu.get_item_id(4))
		assert_false(tool.markers_lookup.has(marker.id))
		assert_eq(editor.ActiveToolName, "SelectTool")
		assert_eq(records.size(), 1)
		records[0].undo()
		assert_true(tool.markers_lookup.has(marker.id))
	if is_instance_valid(upstream._popup_layer):
		upstream._popup_layer.free()
	if Engine.has_meta("rcu_popup_layer"):
		Engine.remove_meta("rcu_popup_layer")
	upstream._g = null
	tool.overlay = overlay
	real_overlay.free()
