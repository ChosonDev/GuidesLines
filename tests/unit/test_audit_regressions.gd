extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..").simplify_path()
var mod
var tool
var api
var changes = []
var geometry
var owned_nodes = []

func test_spiral_preview_cache_tracks_grid_settings_and_parametric_templates():
	var overlay = probe("scripts/overlays/MarkerOverlay.gd")
	overlay.tool = tool
	tool.set_marker_type("Shape")
	tool.set_shape_preset("Spiral")
	var cell = tool._get_grid_cell_size()
	var points = tool.spiral_preview_points(tool.active_shape_spiral, true, cell)
	tool._spiral_cache["probe"] = true
	for pos in [Vector2(-80, 60), Vector2(30, -40)]:
		overlay.lines.clear()
		overlay._draw_spiral_preview(pos, tool.active_shape_spiral, true, cell, Color.white, 5)
		assert_true(tool._spiral_cache.has("probe"), "Cursor movement reuses generated geometry")
		assert_eq(overlay.lines[0].a, pos + points[0])
		assert_eq(overlay.draw_transform, Transform2D.IDENTITY)
	var scaled = tool.spiral_preview_points(tool.active_shape_spiral, true, cell * 2)
	assert_eq(scaled[0], points[0] * 2)
	assert_true(tool._spiral_cache.has("probe"), "Grid changes only rescale cached geometry")
	tool.templates = [{"data": {"marker_type": "Shape", "marker_subtype": "Spiral",
		"spiral_settings": tool.active_shape_spiral.duplicate()}}]
	tool.select_template(0)
	tool.template_rotation_offset = 45
	var desc = tool._build_shape_descriptor_from_template(Vector2.ZERO)
	tool._spiral_cache["template_probe"] = true
	for pos in [Vector2(-25, 70), Vector2(100, 120)]:
		overlay.lines.clear()
		overlay._draw_template_preview(pos, -1000, 1000, -1000, 1000, Vector2.ONE, tool.cached_world.WorldRect, cell, 5, 10)
		assert_true(tool._spiral_cache.has("template_probe"), "Parametric template preview reuses generation")
		assert_eq(overlay.lines[0].a, pos + desc.points[0])
	tool.template_rotation_offset = 90
	tool._build_shape_descriptor_from_template(Vector2.ZERO)
	assert_false(tool._spiral_cache.has("template_probe"), "Template rotation invalidates geometry")
	overlay.lines.clear()
	overlay._draw_custom_marker_preview(Vector2.ZERO, -1000, 1000, -1000, 1000,
		Vector2.ONE, tool.cached_world.WorldRect, null, 5, 10)
	assert_true(overlay.lines.empty(), "Wait for grid initialization before previewing a spiral")

func test_spiral_panel_signals_visibility_validation_and_type_memory():
	make_panel()
	tool.set_marker_type("Shape")
	tool.ui.get_control("ShapeSubtypeSelector").emit_signal("item_selected", 6)
	assert_true(tool.ui.get_control("ShapeSpiralPanel").visible)
	assert_false(tool.ui.get_control("RadiusRow").visible)
	assert_false(tool.ui.get_control("SideRow").visible)
	assert_false(tool.ui.get_control("SizeModeRow").visible)
	assert_false(tool.ui.get_control("ShapeAngleRow").visible)
	tool.ui.get_control("ShapeSpiral_turns").value = 2.5
	assert_eq(tool.active_shape_spiral.turns, 2.5)
	tool.ui.get_control("ShapeSpiralSizeMode").emit_signal("item_selected", 1)
	assert_false(tool.ui.get_control("ShapeSpiral_outer_radius").editable)
	assert_true(tool.ui.get_control("ShapeSpiral_spacing").editable)
	tool.ui.get_control("ShapeSpiral_spacing").value = 3
	assert_eq(tool.active_shape_spiral.outer_radius, 8.5)
	tool.ui.get_control("ShapeSpiral_width").value = 4
	assert_true(tool.ui.get_control("ShapeSpiralError").visible)
	assert_ne(tool.ui.get_control("ShapeSpiralError").text, "")
	tool.place_marker(Vector2.ZERO)
	assert_true(tool.markers.empty())
	tool.ui.get_control("ShapeSpiral_width").value = 1
	assert_false(tool.ui.get_control("ShapeSpiralError").visible)
	tool.set_marker_type("Path")
	tool.ui.get_control("PathSubtypeSelector").emit_signal("item_selected", 1)
	tool.ui.get_control("PathSpiral_reverse").pressed = true
	tool.ui.get_control("PathSpiral_clockwise").pressed = false
	assert_true(tool.active_path_spiral.reverse)
	assert_false(tool.active_path_spiral.clockwise)
	tool.set_marker_type("Shape")
	assert_eq(tool.ui.get_control("ShapeSpiral_turns").value, 2.5)
	assert_true(tool.ui.get_control("ShapeSpiral_clockwise").pressed)
	tool.create_ui_panel()
	assert_true(tool.ui.get_control("ShapeSpiralPanel").visible)
	assert_eq(tool.ui.get_control("ShapeSubtypeSelector").selected, 6)
	tool.ui.get_control("ShapeSubtypeSelector").emit_signal("item_selected", 1)
	assert_false(tool.ui.get_control("ShapeSpiralPanel").visible)
	assert_true(tool.ui.get_control("ShapeAngleRow").visible)

func test_spiral_preview_matches_snapped_placement_and_arrow_at_each_zoom():
	var overlay = probe("scripts/overlays/MarkerOverlay.gd")
	overlay.tool = tool
	tool.cached_snappy_mod = probe()
	mod.Global.Editor.IsSnapping = true
	var pos = Vector2(113, 222)
	var center = tool.snap_position_to_grid(pos)
	for kind in ["Shape", "Path"]:
		tool.set_marker_type(kind)
		if kind == "Shape": tool.set_shape_preset("Spiral")
		else: tool.set_path_subtype(1)
		tool.active_path_end_arrow = true
		tool.active_path_spiral.reverse = true
		var expected = tool.spiral_points_at(center)
		var cached = tool.spiral_result().points
		for zoom in [Vector2.ONE, Vector2(3, 3)]:
			overlay.lines.clear()
			overlay.polylines.clear()
			overlay._draw_custom_marker_preview(pos, -1000, 1000, -1000, 1000, zoom, tool.cached_world.WorldRect, tool._get_grid_cell_size(), 5, 10)
			assert_eq(overlay.polylines.size(), 1, "One native polyline per spiral")
			assert_eq(overlay.draw_transform, Transform2D.IDENTITY, "Restore canvas state before anchors")
			var edge_count = expected.size() if kind == "Shape" else expected.size() - 1
			assert_eq(overlay.lines.size(), edge_count + (3 if kind == "Path" else 0))
			for i in range(edge_count):
				assert_eq(overlay.lines[i].a, expected[i])
				assert_eq(overlay.lines[i].b, expected[(i + 1) % expected.size()])
			if kind == "Path":
				assert_eq(overlay.lines[edge_count + 1].a, expected.back())
		assert_eq(cached, tool.spiral_result().points)
		tool.place_marker(pos)
		var marker = tool.markers.back()
		assert_eq(marker.position, center)
		assert_eq_deep(marker.get_polygon() if kind == "Shape" else marker.marker_points, expected)
		tool.markers.clear()
		tool.markers_lookup.clear()


func before_each():
	var file = File.new()
	file.open(mod_root.plus_file("GuidesLines.gd"), File.READ)
	var script = GDScript.new()
	script.source_code = "var Global = {}\nvar Script=null\n\n" + file.get_as_text()
	file.close()
	assert_eq(script.reload(), OK)
	mod = script.new()
	mod.Global = {"Root": mod_root + "/", "API": {}, "Editor": {"IsSnapping": false}}
	tool = load(mod_root.plus_file("scripts/tool/GuidesLinesTool.gd")).new(mod)
	mod.guides_tool = tool
	tool.GuideMarkerClass = load(mod_root.plus_file("scripts/guides/GuideMarker.gd"))
	tool.cached_world = {"WorldRect": Rect2(-1000, -1000, 2000, 2000), "Level": {"TileMap": {"CellSize": Vector2(100, 100)}}}
	api = load(mod_root.plus_file("scripts/api/guides_lines_api.gd")).new(mod, null)
	mod.guides_lines_api = api
	api.connect("settings_changed", self, "on_settings_changed")
	changes = []
	geometry = load(mod_root.plus_file("scripts/utils/GeometryUtils.gd"))


func after_each():
	api._unload()
	for node in owned_nodes:
		if is_instance_valid(node):
			node.free()
	owned_nodes = []
	tool.ui.tool = null
	tool.placement.tool = null
	tool._fill_handler.tool = null
	tool.parent_mod = null
	mod.guides_tool = null
	mod.guides_lines_api = null
	tool = null
	mod = null
	api = null


func on_settings_changed(key, value):
	changes.append([key, value])


func test_api_preview_survives_repeated_draws_and_expires_without_another_request():
	var overlay = probe("scripts/overlays/MarkerOverlay.gd")
	overlay.tool = tool
	tool.overlay = overlay
	var camera = Camera2D.new()
	owned_nodes.append(camera)
	tool.cached_camera = camera
	api.set_shape_preview(Vector2(50, 50))
	var request = tool._api_preview.duplicate(true)
	overlay._process(0.016)
	overlay._draw()
	var line_count = overlay.lines.size()
	assert_true(line_count > 0)
	overlay._draw()
	assert_eq(overlay.lines.size(), line_count * 2)
	assert_eq_deep(tool._api_preview, request)
	while Engine.get_idle_frames() <= tool._api_preview_frame:
		yield(get_tree(), "idle_frame")
	overlay._process(0.016)
	assert_true(tool._api_preview.empty(), "Preview expires on a later process frame")
	for _frame in range(2):
		api.set_shape_preview(Vector2(60, 60))
		overlay._process(0.016)
		assert_false(tool._api_preview.empty(), "A fresh request survives process ordering")
		yield(get_tree(), "idle_frame")
	api.clear_shape_preview()
	assert_true(tool._api_preview.empty())
	tool.overlay = null


func test_vanilla_line_labels_clip_samples_without_changing_origin_lattice():
	var marker = tool.GuideMarkerClass.new()
	var bounds = Rect2(0, 0, 100, 100)
	for origin in [Vector2(0, 50), Vector2(100, 50), Vector2(-30, 50), Vector2(-10000, 50), Vector2(-30, 150)]:
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2(1, 1).normalized()]:
			marker.position = origin
			marker.cached_coord_points = []
			marker._build_coord_points_vanilla(direction, Vector2(-direction.y, direction.x), bounds, Vector2(10, 10))
			var expected = []
			# Brute-force reference spans both off-map origins and the whole map.
			for index in range(1, 1100):
				var point = origin + direction * (index * 10.0)
				var snapped = point.snapped(Vector2(10, 10))
				if bounds.has_point(point) and point.distance_to(snapped) < 2.5:
					expected.append({"grid_pos": snapped, "text": str(index), "perp": Vector2(-direction.y, direction.x)})
			assert_eq_deep(marker.cached_coord_points, expected)


func test_query_bounds_cache_tracks_authoritative_geometry_and_invalidation():
	var marker = add_shape()
	var segments = [{"type": "seg", "a": Vector2(500, 0), "b": Vector2(500, 100)}]
	marker.set_primitives(segments)
	assert_eq(api.find_nearest_geometry_point(Vector2(500, 100), 0.0).marker_id, 1)
	assert_true(marker.cached_draw_data.has("bounds"))
	assert_eq(api.find_nearest_marker_by_geometry(Vector2.ZERO, 0.0).id, 1, "Bounds cannot cull anchors")
	var saved = marker.Save()
	tool._do_move_marker(marker, Vector2(50, 50))
	assert_null(api.find_nearest_geometry_point(Vector2(500, 100), 0.0))
	assert_eq(api.find_nearest_geometry_point(Vector2(550, 150), 0.0).marker_id, 1)
	marker.Load(saved)
	assert_eq(api.find_nearest_geometry_point(Vector2(500, 100), 0.0).marker_id, 1)
	marker.set_primitives([])
	assert_null(api.find_nearest_geometry_point(Vector2(500, 100), 0.0))
	marker.clear_clip()
	assert_not_null(api.find_nearest_geometry_point(Vector2.ZERO, 200.0))
	marker.set_property("marker_type", "Path")
	marker.set_property("marker_points", [Vector2(1000, 1000), Vector2(1000, 1100)])
	assert_eq(api.find_nearest_geometry_point(Vector2(1000, 1050), 0.0).marker_id, 1)
	marker.set_property("marker_points", [Vector2(2000, 1000), Vector2(2000, 1100)])
	assert_null(api.find_nearest_geometry_point(Vector2(1000, 1050), 0.0))
	assert_eq(api.find_nearest_geometry_point(Vector2(2000, 1050), 0.0).marker_id, 1)
	marker.set_property("marker_points", [])
	assert_null(api.find_nearest_geometry_point(Vector2(2000, 1050), 0.0))


func test_spinbox_rows_preserve_limits_targets_and_visibility():
	make_panel()
	for item in [["AngleSpinBox", 0.0, 360.0, 1.0, false],
			["ShapeRadiusSpinBox", 0.1, 100.0, 0.1, true],
			["ShapeSideSpinBox", 0.1, 100.0, 0.1, true],
			["ShapeAngleSpinBox", 0.0, 360.0, 1.0, false],
			["ShapeSidesSpinBox", 3.0, 64.0, 1.0, false],
			["PathArrowHeadLengthSpinBox", 10.0, 200.0, 5.0, true],
			["PathArrowHeadAngleSpinBox", 10.0, 60.0, 5.0, false],
			["MarkersOpacitySpinBox", 0.0, 100.0, 5.0, false]]:
		var control = tool.ui.get_control(item[0])
		assert_eq(control.min_value, item[1])
		assert_eq(control.max_value, item[2])
		assert_eq(control.step, item[3])
		assert_eq(control.allow_greater, item[4])
		assert_false(control.allow_lesser)
	tool.ui.get_control("MarkersOpacitySpinBox").value = 55.0
	assert_almost_eq(mod.markers_opacity, 0.55, 0.00001)
	assert_false(tool.ui.get_control("SideRow").visible)
	assert_false(tool.ui.get_control("SidesRow").visible)


func test_overlay_canvas_gate_tracks_layout_scale_visibility_and_dialogs():
	var editor_script = GDScript.new()
	editor_script.source_code = "extends CanvasLayer\nvar Windows = {}\nvar IsSnapping = false\n"
	assert_eq(editor_script.reload(), OK)
	var editor = editor_script.new()
	owned_nodes.append(editor)
	add_child(editor)
	mod.Global.Editor = editor
	var parent = editor
	for name in ["VPartition", "Panels", "HSplit"]:
		var node = Control.new()
		node.name = name
		parent.add_child(node)
		parent = node
	# Controlled pointer; actual Godot Control transforms and visibility are used.
	var content_script = GDScript.new()
	content_script.source_code = "extends Control\nvar test_mouse = Vector2.ZERO\nfunc get_local_mouse_position():\n\treturn get_global_transform_with_canvas().affine_inverse().xform(test_mouse)\n"
	assert_eq(content_script.reload(), OK)
	var content = content_script.new()
	content.name = "Content"
	parent.add_child(content)
	content.rect_position = Vector2(300, 50)
	content.rect_size = Vector2(700, 400)
	var overlay = probe("scripts/overlays/MarkerOverlay.gd")
	add_child(overlay)
	overlay.set_process(false)
	overlay.tool = tool
	tool.is_enabled = true
	for scale in [1.0, 1.25, 1.5, 2.0]:
		content.rect_scale = Vector2.ONE * scale
		for point in [Vector2(1, 1), Vector2(350, 200), Vector2(699, 399)]:
			content.test_mouse = content.get_global_transform_with_canvas().xform(point)
			assert_true(overlay._is_mouse_over_canvas(), "Inside %s at scale %s" % [point, scale])
		for point in [Vector2(-1, 200), Vector2(350, -1), Vector2(701, 200), Vector2(350, 401)]:
			content.test_mouse = content.get_global_transform_with_canvas().xform(point)
			assert_false(overlay._is_mouse_over_canvas(), "Outside %s at scale %s" % [point, scale])
	var wheel = InputEventMouseButton.new()
	wheel.button_index = BUTTON_WHEEL_UP
	wheel.pressed = true
	tool.active_angle = 0.0
	overlay._input(wheel)
	assert_eq(tool.active_angle, 0.0, "Wheel over UI must reach its control")
	content.test_mouse = content.get_global_transform_with_canvas().xform(Vector2(350, 200))
	overlay._input(wheel)
	assert_eq(tool.active_angle, 1.0)
	content.hide()
	assert_false(overlay._is_mouse_over_canvas())
	content.show()
	var dialog = Control.new()
	editor.add_child(dialog)
	editor.Windows["Dialog"] = dialog
	assert_false(overlay._is_mouse_over_canvas())
	dialog.hide()
	assert_true(overlay._is_mouse_over_canvas())
	content.test_mouse = content.get_global_transform_with_canvas().xform(Vector2(-1, 200))
	tool.cached_worldui = {"IsInsideBounds": true, "MousePosition": Vector2(30, 40)}
	overlay._process(0.0)
	assert_true(overlay._mouse_in_ui)
	var click = InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	overlay._input(click)
	assert_eq(tool.markers.size(), 0, "UI click cannot place a marker")
	var marker = add_shape()
	tool.move_mode = true
	tool._move_selected_marker = marker
	tool._move_drag_pos = Vector2(20, 30)
	click.pressed = false
	overlay._input(click)
	assert_null(tool._move_selected_marker, "Release outside canvas must finish the drag")
	assert_eq(marker.position, Vector2(20, 30))
	content.free()
	assert_false(overlay._is_mouse_over_canvas(), "Missing host content disables mouse actions")


func test_overlap_icons_share_cached_textures_but_keep_scale_variants():
	make_panel()
	var shape_row = tool.ui.get_control("ShapeModesRow")
	var template_row = tool.ui.get_control("TemplateShapeModesRow")
	# The row names are owned by the existing panel builder.
	assert_not_null(shape_row)
	assert_not_null(template_row)
	if shape_row == null or template_row == null:
		return
	for index in range(6):
		assert_not_null(shape_row.get_child(index).icon)
		assert_eq(shape_row.get_child(index).icon, template_row.get_child(index).icon)
	var full = tool.ui._load_icon("normal64.png", 1.0)
	var half = tool.ui._load_icon("normal64.png", 0.5)
	assert_ne(full, half)
	assert_eq(full.get_width(), 64)
	assert_eq(half.get_width(), 32)


func test_real_panel_signals_edit_tool_parameters_and_restore_all_types():
	make_panel()
	tool.ui.get_control("AngleSpinBox").value = 37.0
	tool.ui.get_control("MirrorCheckbox").pressed = true
	assert_eq(tool.active_angle, 37.0)
	assert_true(tool.active_mirror)
	tool.ui.type_selector.emit_signal("item_selected", 1)
	assert_eq(tool.active_marker_type, "Shape")
	tool.ui.get_control("ShapeRadiusSpinBox").value = 3.0
	tool.ui.get_control("ShapeAngleSpinBox").value = 27.0
	tool.ui.get_control("ShapeSidesSpinBox").value = 5.0
	assert_eq(tool.active_shape_radius, 3.0)
	assert_eq(tool.active_shape_angle, 27.0)
	assert_eq(tool.active_shape_sides, 5)
	tool.ui.type_selector.emit_signal("item_selected", 2)
	tool.ui.get_control("PathEndArrowCheckbox").pressed = true
	tool.ui.get_control("PathArrowHeadLengthSpinBox").value = 25.0
	tool.ui.get_control("PathArrowHeadAngleSpinBox").value = 20.0
	assert_true(tool.active_path_end_arrow)
	assert_eq(tool.active_arrow_head_length, 25.0)
	assert_eq(tool.active_arrow_head_angle, 20.0)
	tool.set_marker_type("Line")
	assert_eq(tool.ui.get_control("AngleSpinBox").value, 37.0)
	assert_true(tool.ui.get_control("MirrorCheckbox").pressed)
	tool.set_marker_type("Shape")
	assert_eq(tool.ui.get_control("ShapeRadiusSpinBox").value, 3.0)
	assert_eq(tool.ui.get_control("ShapeAngleSpinBox").value, 27.0)
	assert_eq(tool.ui.get_control("ShapeSidesSpinBox").value, 5.0)
	tool.set_shape_preset("Square")
	var preset = tool.ui.get_control("ShapeSubtypeSelector")
	assert_eq(preset.get_item_metadata(preset.selected), "Square")
	tool.ui.get_control("ShapeSizeModeOption").emit_signal("item_selected", 1)
	assert_eq(tool.active_shape_size_mode, "side")
	assert_almost_eq(tool.active_shape_side, 3.0 * sqrt(2.0), 0.00001)
	tool.set_marker_type("Path")
	assert_true(tool.ui.get_control("PathEndArrowCheckbox").pressed)
	assert_eq(tool.ui.get_control("PathArrowHeadLengthSpinBox").value, 25.0)
	assert_eq(tool.ui.get_control("PathArrowHeadAngleSpinBox").value, 20.0)


func test_map_reference_refresh_releases_replaced_and_freed_overlays():
	var old_parent = Node2D.new()
	var new_parent = Node2D.new()
	owned_nodes.append(old_parent)
	owned_nodes.append(new_parent)
	mod.Global["World"] = tool.cached_world
	mod.Global["WorldUI"] = old_parent
	mod.Global["Camera"] = null
	tool.cached_worldui = old_parent
	for property in ["cross_overlay", "perm_overlay"]:
		var node = Node2D.new()
		old_parent.add_child(node)
		mod.set(property, node)
	tool.overlay = Node2D.new()
	old_parent.add_child(tool.overlay)
	mod._refresh_map_references()
	assert_eq(old_parent.get_child_count(), 3, "Keep overlays on unchanged map")
	mod.Global.WorldUI = new_parent
	mod._refresh_map_references()
	assert_eq(old_parent.get_child_count(), 0)
	assert_null(mod.cross_overlay)
	assert_null(mod.perm_overlay)
	assert_null(tool.overlay)
	assert_eq(tool.cached_worldui, new_parent)
	tool.overlay = Node2D.new()
	tool.overlay.free()
	mod._refresh_map_references()
	assert_null(tool.overlay, "Clear freed object references")
	mod.perm_overlay = Node2D.new()
	new_parent.add_child(mod.perm_overlay)
	mod.Global.World = {"WorldRect": Rect2(0, 0, 500, 500)}
	mod._refresh_map_references()
	assert_null(mod.perm_overlay, "Replacing World also invalidates overlays on the same WorldUI")
	assert_eq(tool.cached_world, mod.Global.World)
	mod.Global.World = null
	mod.Global.WorldUI = null
	mod.cross_show_v = true
	mod._refresh_map_references()
	assert_null(tool.cached_world)
	assert_null(tool.cached_worldui)
	assert_null(tool.cached_camera)
	assert_false(mod.cross_show_v)
	yield(get_tree(), "idle_frame")


func make_panel():
	var align = VBoxContainer.new()
	add_child(align)
	owned_nodes.append(align)
	tool.tool_panel = {"Align": align}
	tool.create_ui_panel()
	return align


func probe(path = ""):
	var source = load("res://helpers/draw_probe.gd")
	if not path.empty():
		var script = GDScript.new()
		script.source_code = "extends \"" + mod_root.plus_file(path) + "\"\n" + source.source_code.split("\n", true, 1)[1]
		assert_eq(script.reload(), OK)
		source = script
	var result = source.new()
	owned_nodes.append(result)
	return result


func add_shape(id = 1):
	tool._do_place_marker({"id": id, "position": Vector2.ZERO, "marker_type": "Shape", "color": Color.blue,
		"coordinates": false, "shape_radius": 2.0, "shape_sides": 4, "shape_angle": 45.0})
	return tool.markers_lookup[id]


func total_length(segments):
	var result = 0.0
	for segment in segments:
		result += segment.a.distance_to(segment.b)
	return result


func test_settings_sync_api_widgets_and_ui_without_feedback():
	make_panel()
	var visible = tool.ui.get_control("MarkersVisibleCheckbox")
	var opacity = tool.ui.get_control("MarkersOpacitySpinBox")
	api.set_markers_visible(false)
	assert_false(visible.pressed)
	assert_eq_deep(changes, [["markers_visible", false]])
	api.set_markers_visible(false)
	assert_eq(changes.size(), 1)
	visible.pressed = true
	assert_true(mod.markers_visible)
	assert_eq_deep(changes[1], ["markers_visible", true])
	api.set_markers_opacity(0.35)
	assert_eq(opacity.value, 35.0)
	assert_eq_deep(changes[2], ["markers_opacity", 0.35])
	var marker = add_shape()
	opacity.value = 60
	assert_almost_eq(marker.draw_color.a, 0.6, 0.00001)
	assert_eq(changes.size(), 4)
	assert_eq_deep(changes[3], ["markers_opacity", 0.6])
	api.set_markers_opacity(NAN)
	assert_eq(mod.markers_opacity, 0.6)
	assert_eq(changes.size(), 4)
	api.set_markers_opacity(2.0)
	assert_eq(mod.markers_opacity, 1.0)
	assert_eq(opacity.value, 100.0)


func test_coordinate_settings_remain_independent_with_legacy_combined_setter():
	make_panel()
	tool.ui.get_control("CoordinatesCheckbox").pressed = true
	assert_true(api.get_settings().marker_coordinates)
	assert_false(api.get_settings().show_coordinates)
	assert_eq_deep(changes, [["marker_coordinates", true]])
	api.set_permanent_coordinates(true)
	assert_true(mod.show_coordinates_enabled)
	api.set_show_coordinates(false)
	assert_false(tool.show_coordinates)
	assert_false(tool.ui.get_control("CoordinatesCheckbox").pressed)
	assert_false(api.get_settings().show_coordinates)
	assert_eq(changes.size(), 4)
	api.set_show_coordinates(false)
	assert_eq(changes.size(), 4)
	api.set_marker_coordinates(true)
	assert_true(tool.show_coordinates)
	assert_false(mod.show_coordinates_enabled)


func test_modconfig_and_api_overlay_settings_emit_once_per_change():
	mod._on_cross_guides_toggled(false)
	api.set_cross_guides(false)
	mod._on_perm_vertical_toggled(true)
	api.set_permanent_vertical(true)
	mod._on_perm_horizontal_toggled(true)
	api.set_permanent_horizontal(true)
	mod._on_perm_coordinates_toggled(true)
	api.set_permanent_coordinates(true)
	assert_eq_deep(changes, [["cross_guides", false], ["perm_vertical", true], ["perm_horizontal", true], ["show_coordinates", true]])
	mod.guides_tool = null
	api.set_markers_visible(false)
	api.set_markers_opacity(0.5)
	assert_false(mod.markers_visible)
	assert_eq(mod.markers_opacity, 0.5)
	mod.guides_tool = tool


func test_panel_cache_replacement_and_overlap_buttons_stay_in_sync():
	var panel = make_panel()
	var old_spin = tool.ui.get_control("ShapeSidesSpinBox")
	assert_eq(old_spin.max_value, 64.0)
	assert_eq(old_spin.value, 64.0)
	for mode in ["normal", "merge", "conforming", "wrapping", "difference", "cut"]:
		tool.set_shape_mode(mode)
		for row_name in ["ShapeModesRow", "TemplateShapeModesRow"]:
			var row = tool.ui.get_control(row_name)
			var pressed = 0
			for button in row.get_children():
				if button.pressed:
					pressed += 1
			assert_eq(pressed, 1, mode + row_name)
		assert_eq(tool.ui._active_overlap_mode(), mode)
	panel.free()
	make_panel()
	assert_true(is_instance_valid(tool.ui.get_control("ShapeSidesSpinBox")))
	assert_false(is_instance_valid(old_spin))
	tool.ui._set_spinbox_value("ShapeSidesSpinBox", 12)
	assert_eq(tool.active_shape_sides, 64, "Programmatic sync must not invoke callbacks")
	assert_eq(tool.ui.get_control("ShapeSidesSpinBox").value, 12.0)


func test_clipping_shared_core_preserves_crossing_inside_outside_and_degenerate_cases():
	var box = {"shape_type": "poly", "points": [Vector2(0, -5), Vector2(10, -5), Vector2(10, 5), Vector2(0, 5)]}
	var segments = [{"type": "seg", "a": Vector2(-5, 0), "b": Vector2(15, 0)}]
	var outside = geometry.clip_primitives_against_shapes(segments, [box])
	assert_eq_deep(outside, [{"type": "seg", "a": Vector2(-5, 0), "b": Vector2(0, 0)}, {"type": "seg", "a": Vector2(10, 0), "b": Vector2(15, 0)}])
	var polygon = [Vector2(-5, -2), Vector2(15, -2), Vector2(15, 2), Vector2(-5, 2)]
	var inside = geometry.clip_polygon_inside_shape(polygon, box)
	assert_almost_eq(total_length(inside), 20.0, 0.00001)
	assert_almost_eq(total_length(geometry.clip_polygon_against_shapes(polygon, [box])), 28.0, 0.00001)
	assert_eq_deep(geometry.clip_primitives_against_shapes(segments, []), segments)
	assert_eq_deep(geometry.clip_polygon_against_shapes([], [box]), [])
	assert_eq_deep(geometry.clip_polygon_inside_shape([Vector2.ZERO, Vector2.ZERO], box), [])
	var second = {"shape_type": "poly", "points": [Vector2(5, -5), Vector2(20, -5), Vector2(20, 5), Vector2(5, 5)]}
	assert_eq_deep(geometry.clip_primitives_against_shapes(segments, [box, second]), [outside[0]])


func test_polygon_cache_reuses_then_invalidates_on_mutation_move_clear_and_load():
	var marker = add_shape()
	tool._get_shape_descriptor(marker, Vector2(100, 100))
	assert_true(marker.cached_draw_data.has("polygon"))
	var triangle = [Vector2(0, 0), Vector2(100, 0), Vector2(0, 100)]
	marker.set_primitives(geometry.points_to_segs(triangle))
	assert_false(marker.cached_draw_data.has("polygon"))
	assert_eq_deep(tool._get_shape_descriptor(marker, Vector2(100, 100)).points, triangle)
	var saved = marker.Save()
	tool._do_move_marker(marker, Vector2(10, 20))
	var moved = [Vector2(10, 20), Vector2(110, 20), Vector2(10, 120)]
	assert_eq_deep(tool._get_shape_descriptor(marker, Vector2(100, 100)).points, moved)
	marker.Load(saved)
	assert_eq_deep(tool._get_shape_descriptor(marker, Vector2(100, 100)).points, triangle)
	marker.set_property("show_coordinates", true)
	assert_eq_deep(tool._get_shape_descriptor(marker, Vector2(100, 100)).points, triangle)
	marker.set_primitives([])
	assert_eq_deep(tool._get_shape_descriptor(marker, Vector2(100, 100)), {})
	marker.clear_clip()
	assert_eq(tool._get_shape_descriptor(marker, Vector2(100, 100)).points.size(), 4)


func test_fresh_shape_waits_for_grid_and_move_keeps_geometry():
	var marker = add_shape()
	marker.get_draw_data(null, null)
	assert_true(marker._dirty)
	tool._do_move_marker(marker, Vector2(20, 40))
	var points = tool._get_shape_descriptor(marker, Vector2(100, 100)).points
	assert_eq(points.size(), 4)
	var center = Vector2.ZERO
	for point in points:
		center += point
	assert_almost_eq((center / 4.0).x, 20.0, 0.0001)
	assert_almost_eq((center / 4.0).y, 40.0, 0.0001)


func test_text_outline_uses_two_transforms_and_preserves_world_offsets():
	var canvas = probe()
	var control = Control.new()
	var font = control.get_font("font")
	control.free()
	var render = load(mod_root.plus_file("scripts/render/GuidesLinesRender.gd"))
	render.draw_text_with_outline(canvas, "12", Vector2(100, 200), Color.blue, font)
	assert_eq(canvas.transforms.size(), 2)
	assert_eq(canvas.strings.size(), 9)
	for index in range(8):
		var delta = canvas.strings[index].pos - Vector2(100, 200)
		assert_true(abs(delta.x) <= 2.0 and abs(delta.y) <= 2.0)
		assert_ne(delta, Vector2.ZERO)
	assert_eq(canvas.strings[8].pos, Vector2(100, 200))
	assert_eq(canvas.draw_transform, Transform2D.IDENTITY)


func test_permanent_redraw_tracks_viewport_grid_map_visibility_and_idle():
	var overlay = probe("scripts/overlays/PermanentOverlay.gd")
	var camera = Camera2D.new()
	owned_nodes.append(camera)
	overlay.cached_camera = camera
	overlay.cached_world = tool.cached_world
	overlay.parent_mod = mod
	mod.cross_guides_enabled = false
	mod.perm_vertical_enabled = true
	mod.perm_overlay = overlay
	mod.Global["Camera"] = camera
	mod.Global["World"] = tool.cached_world
	mod._update_proximity_and_permanent_guides(0.016)
	assert_eq(overlay.redraws, 0, "Entry update must not force permanent redraw")
	overlay._process(0.016)
	assert_eq(overlay.redraws, 1)
	overlay._process(0.016)
	assert_eq(overlay.redraws, 1)
	overlay.viewport_rect.size.x += 100
	overlay._process(0.016)
	assert_eq(overlay.redraws, 2)
	var snap = probe()
	overlay.cached_snappy_mod = snap
	overlay._process(0.016)
	assert_eq(overlay.redraws, 3)
	for property in ["snap_offset", "snap_interval", "active_geometry", "radial_mode_to_corner", "custom_snap_enabled"]:
		var value = snap.get(property)
		if value is Vector2: snap.set(property, value + Vector2.ONE)
		elif value is bool: snap.set(property, not value)
		else: snap.set(property, value + 1)
		var previous = overlay.redraws
		overlay._process(0.016)
		assert_eq(overlay.redraws, previous + 1, property)
		assert_eq(overlay._perm_coord_cache_wt, -INF)
	mod.perm_vertical_enabled = true
	overlay._process(0.016)
	var count = overlay.redraws
	mod.perm_vertical_enabled = false
	overlay._process(0.016)
	assert_eq(overlay.redraws, count + 1)
	overlay._process(0.016)
	assert_eq(overlay.redraws, count + 1)
	tool.cached_world.WorldRect.size.x += 10
	overlay._process(0.016)
	assert_eq(overlay.redraws, count + 2)
	camera.zoom = Vector2(2, 2)
	overlay._process(0.016)
	assert_eq(overlay.redraws, count + 3)


func test_cross_overlay_redraws_once_when_last_line_is_hidden():
	var overlay = probe("scripts/overlays/CrossOverlay.gd")
	var camera = Camera2D.new()
	owned_nodes.append(camera)
	overlay.cached_camera = camera
	overlay.parent_mod = mod
	mod.cross_show_v = true
	overlay._process(0.016)
	assert_eq(overlay.redraws, 1)
	mod.cross_show_v = false
	overlay._process(0.016)
	assert_eq(overlay.redraws, 2)
	overlay._process(0.016)
	assert_eq(overlay.redraws, 2)


func test_permanent_coordinate_axes_preserve_labels_and_snapped_deduplication():
	var overlay = probe("scripts/overlays/PermanentOverlay.gd")
	overlay.parent_mod = mod
	overlay.cached_world = {"Level": {"TileMap": {"CellSize": Vector2(10, 10)}}}
	overlay._cached_map_rect_perm = Rect2(-100, -100, 200, 200)
	mod.perm_vertical_enabled = true
	mod.perm_horizontal_enabled = true
	overlay._rebuild_perm_coord_cache(0, 0, -20, 20, -20, 20, null, false)
	var vertical = overlay._perm_coord_cache_v.duplicate(true)
	var horizontal = overlay._perm_coord_cache_h.duplicate(true)
	assert_eq(vertical.size(), 4)
	assert_eq(horizontal.size(), 4)
	assert_eq_deep(vertical[0], {"pos": Vector2(0, -20), "text": "2", "text_dir": Vector2(1, 0)})
	assert_eq_deep(horizontal[3], {"pos": Vector2(20, 0), "text": "2", "text_dir": Vector2(0, -1)})
	var snap = probe()
	overlay._rebuild_perm_coord_cache(0, 0, -20, 20, -20, 20, snap, true)
	assert_eq_deep(overlay._perm_coord_cache_v, vertical)
	assert_eq_deep(overlay._perm_coord_cache_h, horizontal)
	snap.snap_interval = Vector2.ZERO
	overlay._rebuild_perm_coord_cache(0, 0, -20, 20, -20, 20, snap, true)
	assert_eq(overlay._perm_coord_cache_v.size(), 0)


func test_preview_rays_match_placed_geometry_for_offscreen_and_offmap_origins():
	var overlay = probe("scripts/overlays/MarkerOverlay.gd")
	var map_rect = Rect2(0, 0, 1000, 1000)
	for origin in [Vector2(500, 500), Vector2(-50, 500), Vector2(1050, 500)]:
		for angle in [0.0, 45.0, 90.0, 180.0, 270.0]:
			var marker = tool.GuideMarkerClass.new(origin, angle)
			var placed = marker.get_draw_data(map_rect, Vector2(100, 100)).segments[0]
			var preview = overlay._calculate_line_endpoints(origin, angle, 400, 600, 400, 600, map_rect)
			assert_eq_deep(preview, placed)
	assert_eq_deep(overlay._calculate_line_endpoints(Vector2(10, 10), 0, 0, 50, 0, 50, null), [Vector2(10, 10), Vector2(50, 10)])


func test_path_drawing_and_modified_shape_preview_preserve_render_commands():
	var overlay = probe("scripts/overlays/MarkerOverlay.gd")
	var points = [Vector2.ZERO, Vector2(20, 0), Vector2(20, 20)]
	overlay._draw_path_points(points, true, true, 10.0, 30.0, Vector2.ONE, Color.blue, 5.0)
	assert_eq(overlay.lines.size(), 6)
	assert_eq(overlay.lines[2].a, points[2])
	assert_eq(overlay.lines[2].b, points[0])
	assert_eq(overlay.lines[4].a, points[2])
	assert_almost_eq(overlay.lines[4].a.distance_to(overlay.lines[4].b), 10.0, 0.0001)
	overlay.lines.clear()
	var marker = add_shape()
	marker.set_primitives([{"type": "seg", "a": Vector2(1, 2), "b": Vector2(5, 8)}])
	overlay._draw_move_drag_preview(marker, Vector2(10, 20), -100, 100, -100, 100, Vector2.ONE, tool.cached_world.WorldRect, Vector2(100, 100), null, 5.0, 10.0)
	assert_eq(overlay.lines.size(), 1)
	assert_eq(overlay.lines[0].a, Vector2(11, 22))
	assert_eq(overlay.lines[0].b, Vector2(15, 28))
	assert_eq(overlay.circles.size(), 1)
	assert_eq(overlay.arcs.size(), 1)


func test_shape_and_template_nonplacing_modes_produce_equivalent_geometry():
	tool.active_marker_type = "Shape"
	tool.active_color = Color.blue
	tool.active_shape_radius = 1.0
	tool.active_shape_sides = 4
	tool.active_shape_angle = 45.0
	tool.templates = [{"data": {"marker_type": "Shape", "shape_radius": 1.0,
		"shape_sides": 4, "shape_angle": 45.0, "color": Color.blue}}]
	tool.active_template_index = 0
	for mode in ["normal", "difference", "cut", "merge", "conforming", "wrapping"]:
		tool.set_shape_mode(mode)
		var results = []
		for use_template in [false, true]:
			tool.markers.clear()
			tool.markers_lookup.clear()
			add_shape(1)
			tool.next_id = 2
			if use_template:
				tool._place_template_marker(Vector2(120, 0))
			else:
				tool.place_marker(Vector2(120, 0))
			var state = []
			for marker in tool.markers:
				marker.get_draw_data(tool.cached_world.WorldRect, Vector2(100, 100))
				state.append(marker.Save())
			results.append(state)
		assert_eq_deep(results[0], results[1])
		assert_eq(tool.markers.size(), tool.markers_lookup.size())


func test_snapshot_wrappers_agree_and_handle_unavailable_world():
	var marker = add_shape()
	var desc = tool._build_shape_descriptor_at(Vector2.ZERO)
	var normal = tool._snapshot_potential_clip_targets_by_desc(desc)
	assert_eq_deep(tool._take_difference_snapshot(desc), normal)
	assert_eq_deep(tool._snapshot_potential_clip_targets(Vector2.ZERO), normal)
	var complete = tool._snapshot_potential_merge_targets(desc)
	assert_eq_deep(complete[marker.id].primitives, normal[marker.id].primitives)
	assert_eq_deep(complete[marker.id].saved_marker, marker.Save())
	tool.cached_world = null
	assert_eq_deep(tool._snapshot_potential_clip_targets_by_desc(desc), {})
	assert_eq_deep(tool._take_difference_snapshot(desc), {})
	assert_eq_deep(tool._snapshot_potential_merge_targets(desc), {})


func test_segment_chaining_keeps_strict_epsilon_and_tangent_loops():
	var segments = [{"type": "seg", "a": Vector2.ZERO, "b": Vector2(10, 0)},
		{"type": "seg", "a": Vector2(10.5, 0), "b": Vector2(20, 0)}]
	assert_eq(geometry.split_segments_into_chains(segments, 0.5).size(), 2)
	assert_eq(geometry.split_segments_into_chains(segments, 0.50001).size(), 1)
	assert_eq(geometry.split_segments_into_chains(segments, -1.0).size(), 2)
	var triangle = [Vector2.ZERO, Vector2(10, 0), Vector2(0, 10)]
	var other = [Vector2.ZERO, Vector2(-10, 0), Vector2(0, -10)]
	var loop = geometry.chain_segments_to_polygon(geometry.points_to_segs(triangle) + geometry.points_to_segs(other))
	assert_true(loop.has(Vector2(10, 0)))
	assert_true(loop.has(Vector2(-10, 0)))
	assert_true(loop.has(Vector2(0, 10)))
	assert_true(loop.has(Vector2(0, -10)))


func test_nearest_vertex_is_taken_from_winning_geometry_only():
	var marker = add_shape()
	marker.set_primitives(geometry.points_to_segs([Vector2(500, 500), Vector2(600, 500), Vector2(500, 600)]))
	tool._do_place_marker({"id": 2, "position": Vector2(50, 50), "marker_type": "Path", "coordinates": false,
		"color": Color.blue, "marker_points": [Vector2(50, 50), Vector2(150, 50)], "path_closed": false})
	var result = api.find_nearest_marker_by_geometry(Vector2(100, 55), 100.0)
	assert_eq(result.id, 2)
	assert_eq(result.point, Vector2(100, 50))
	assert_eq(result.vertex, Vector2(50, 50))
	result = api.find_nearest_marker_by_geometry(Vector2(550, 505), 100.0)
	assert_eq(result.id, 1)
	assert_eq(result.point, Vector2(550, 500))
	assert_eq(result.vertex, Vector2(500, 500))


func test_optimized_text_matches_original_outline_pixels():
	var script = GDScript.new()
	script.source_code = "extends Node2D\n" + "const Renderer = preload(\"" + mod_root.plus_file("scripts/render/GuidesLinesRender.gd") + "\")\n" + """
var optimized = false
var font
var draws = 0
func _draw():
	draws += 1
	var position = Vector2(30, 50)
	if optimized:
		Renderer.draw_text_with_outline(self, "123", position, Color(0.2, 0.7, 1.0), font)
	else:
		for dx in [-2, 0, 2]:
			for dy in [-2, 0, 2]:
				if dx != 0 or dy != 0:
					draw_set_transform(position + Vector2(dx, dy), 0, Vector2(4, 4))
					draw_string(font, Vector2.ZERO, "123", Color(0, 0, 0, 0.8), -1)
		draw_set_transform(position, 0, Vector2(4, 4))
		draw_string(font, Vector2.ZERO, "123", Color(0.2, 0.7, 1.0), -1)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
"""
	assert_eq(script.reload(), OK)
	var control = Control.new()
	var font = control.get_font("font")
	control.free()
	var views = []
	for optimized in [false, true]:
		var view = Viewport.new()
		view.size = Vector2(256, 128)
		view.disable_3d = true
		view.world_2d = World2D.new()
		view.transparent_bg = true
		view.render_target_update_mode = Viewport.UPDATE_ALWAYS
		var painter = script.new()
		painter.optimized = optimized
		painter.font = font
		view.add_child(painter)
		add_child(view)
		owned_nodes.append(view)
		views.append(view)
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	var original = views[0].get_texture().get_data()
	var optimized = views[1].get_texture().get_data()
	assert_true(views[0].get_child(0).draws > 0, "Reference painter must execute")
	assert_eq(original.get_size(), Vector2(256, 128))
	var ink_pixels = 0
	original.lock()
	for y in range(original.get_height()):
		for x in range(original.get_width()):
			if original.get_pixel(x, y).b > 0.1:
				ink_pixels += 1
	original.unlock()
	assert_true(ink_pixels > 100, "Reference must contain rendered glyphs, not an empty image")
	assert_true(original.get_data() == optimized.get_data(), "Text positions and outline pixels must match exactly")


var layer_draws = [0, 0]

func on_marker_layer_draw(layer: int) -> void:
	layer_draws[layer] += 1

func test_marker_layers_keep_static_geometry_during_cursor_and_spiral_preview_changes():
	# Use real CanvasItems and draw signals: command probes alone cannot prove retention.
	var script = GDScript.new()
	script.source_code = "extends \"" + mod_root.plus_file("scripts/overlays/MarkerOverlay.gd") + "\"\nvar test_viewport = Rect2(0, 0, 800, 600)\nfunc get_viewport_rect():\n\treturn test_viewport\nfunc _is_mouse_over_canvas():\n\treturn true\n"
	assert_eq(script.reload(), OK)
	var overlay = script.new()
	owned_nodes.append(overlay)
	var camera = Camera2D.new()
	owned_nodes.append(camera)
	add_child(camera)
	tool.cached_camera = camera
	tool.cached_worldui = {"IsInsideBounds": true, "MousePosition": Vector2(20, 30)}
	for x in [0, 100, 200]:
		assert_true(api.place_spiral_shape_marker(Vector2(x, 0)) >= 0)
	tool.show_coordinates = true
	var line_id = api.place_line_marker(Vector2.ZERO)
	assert_true(line_id >= 0)
	tool.show_coordinates = false
	assert_true(api.place_path_marker([Vector2(20, 20), Vector2(50, 20)]) >= 0)
	tool.FillMarkerClass = load(mod_root.plus_file("scripts/guides/FillMarker.gd"))
	tool._do_place_fill({"id": 0, "color": "#00ffff", "polygon": [[20, 20], [30, 20], [25, 30]]})
	tool.set_marker_type("Path")
	tool.set_path_subtype(1)
	tool.is_enabled = true
	overlay.tool = tool
	tool.overlay = overlay
	add_child(overlay)
	overlay.set_process(false)
	layer_draws = [0, 0]
	overlay.connect("draw", self, "on_marker_layer_draw", [0])
	overlay._markers_canvas.connect("draw", self, "on_marker_layer_draw", [1])
	assert_true(overlay._markers_canvas.show_behind_parent, "Placed geometry stays below preview")
	overlay._process(0.0)
	yield(VisualServer, "frame_post_draw")
	assert_eq_deep(layer_draws, [1, 1])
	overlay._process(0.0)
	yield(VisualServer, "frame_post_draw")
	assert_eq_deep(layer_draws, [1, 1])
	for i in range(3):
		var previous = layer_draws.duplicate()
		tool.cached_worldui.MousePosition += Vector2(10, 10)
		overlay._process(0.0)
		yield(VisualServer, "frame_post_draw")
		assert_eq_deep(layer_draws, [previous[0] + 1, previous[1]])
	var previous = layer_draws.duplicate()
	tool.set_spiral_value(6.0, "turns")
	overlay._process(0.0)
	yield(VisualServer, "frame_post_draw")
	assert_eq_deep(layer_draws, [previous[0] + 1, previous[1]])
	previous = layer_draws.duplicate()
	tool._do_move_marker(tool.markers[0], Vector2(-50, 20))
	yield(VisualServer, "frame_post_draw")
	assert_eq_deep(layer_draws, [previous[0] + 1, previous[1] + 1])
	var history = load(mod_root.plus_file("scripts/tool/GuidesLinesHistory.gd"))
	var move = history.MoveMarkerRecord.new(tool, tool.markers[0].id, Vector2.ZERO, Vector2(-50, 20))
	for method in ["undo", "redo"]:
		previous = layer_draws.duplicate()
		move.call(method)
		yield(VisualServer, "frame_post_draw")
		assert_eq_deep(layer_draws, [previous[0] + 1, previous[1] + 1])
	var persistence = load(mod_root.plus_file("scripts/tool/GuidesLinesPersistence.gd")).new()
	persistence._mod = mod
	var saved = {}
	persistence.save_map(saved)
	previous = layer_draws.duplicate()
	assert_true(persistence.load_map(saved))
	yield(VisualServer, "frame_post_draw")
	assert_eq_deep(layer_draws, [previous[0] + 1, previous[1] + 1])
	persistence._mod = null
	for change in ["zoom", "viewport", "grid", "bounds", "opacity", "visibility"]:
		previous = layer_draws.duplicate()
		match change:
			"zoom": camera.zoom = Vector2(2, 2)
			"viewport": overlay.test_viewport.size += Vector2(50, 50)
			"grid": tool.cached_world.Level.TileMap.CellSize = Vector2(50, 50)
			"bounds": tool.cached_world.WorldRect.size += Vector2(100, 100)
			"opacity": api.set_markers_opacity(0.4)
			"visibility": api.set_markers_visible(false)
		overlay._process(0.0)
		yield(VisualServer, "frame_post_draw")
		assert_eq_deep(layer_draws, [previous[0] + 1, previous[1] + 1])
	api.set_markers_visible(true)
	yield(VisualServer, "frame_post_draw")
	var snap = probe()
	tool.cached_snappy_mod = snap
	for change in ["initial", "snap_offset", "snap_interval", "active_geometry", "radial_mode_to_corner", "custom_snap_enabled"]:
		previous = layer_draws.duplicate()
		match change:
			"snap_offset": snap.snap_offset = Vector2(5, 5)
			"snap_interval": snap.snap_interval = Vector2(20, 20)
			"active_geometry": snap.active_geometry = 1
			"radial_mode_to_corner": snap.radial_mode_to_corner = false
			"custom_snap_enabled": snap.custom_snap_enabled = false
		overlay._process(0.0)
		yield(VisualServer, "frame_post_draw")
		assert_eq_deep(layer_draws, [previous[0] + 1, previous[1] + 1])
		if change == "initial":
			assert_false(tool.markers_lookup[line_id].cached_coord_points.empty())
		elif change == "snap_offset":
			assert_eq(abs(tool.markers_lookup[line_id].cached_coord_points[0].grid_pos.y), 5.0, "Snap origin change must rebuild cached labels")
	previous = layer_draws.duplicate()
	overlay._process(0.0)
	yield(VisualServer, "frame_post_draw")
	assert_eq_deep(layer_draws, previous)
	var retained = overlay._markers_canvas
	tool.overlay = null
	overlay.free()
	assert_false(is_instance_valid(retained), "Freeing the overlay also frees its retained layer")

func test_shape_batches_preserve_every_segment_and_cut_gap():
	var overlay = probe("scripts/overlays/MarkerOverlay.gd")
	overlay.tool = tool
	var settings = geometry.SPIRAL_DEFAULTS.duplicate()
	var points = geometry.build_spiral(settings, true).points
	var segments = geometry.points_to_segs(points)
	overlay._draw_shape_segments(segments, Color.blue, 5.0)
	assert_eq(overlay.polylines.size(), 1, "One closed spiral uses one native polyline command")
	assert_eq(overlay.lines.size(), segments.size())
	for i in range(segments.size()):
		assert_eq(overlay.lines[i].a, segments[i].a)
		assert_eq(overlay.lines[i].b, segments[i].b)
		assert_eq(overlay.lines[i].width, 5.0)
	segments.remove(segments.size() / 2)
	overlay.lines.clear()
	overlay.polylines.clear()
	var offset = Vector2(30, -20)
	overlay._draw_shape_segments(segments, Color.blue, 7.0, offset)
	assert_eq(overlay.polylines.size(), 2, "A removed segment leaves two separate chains")
	assert_eq(overlay.lines.size(), segments.size(), "No extra bridge across Cut/Difference gap")
	for i in range(segments.size()):
		assert_eq(overlay.lines[i].a, segments[i].a + offset)
		assert_eq(overlay.lines[i].b, segments[i].b + offset)
		assert_eq(overlay.lines[i].width, 7.0)
	overlay.lines.clear()
	overlay.polylines.clear()
	overlay._draw_shape_segments([], Color.blue, 5.0)
	assert_true(overlay.polylines.empty(), "An explicitly empty outline stays empty")
