extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..").simplify_path()
var tool
var api
var last_record
var deleted_ids = []

func _count_fill_queries():
	var script = GDScript.new()
	script.source_code = 'extends "' + mod_root.plus_file("scripts/tool/GuidesLinesFill.gd") + '"\nvar computations = 0\nfunc _init(owner).(owner):\n\tpass\nfunc _compute_fill_polygon(position: Vector2, hits: Array, quiet: bool = false) -> Array:\n\tcomputations += 1\n\treturn ._compute_fill_polygon(position, hits, quiet)\n'
	assert_eq(script.reload(), OK)
	tool._fill_handler.tool = null
	tool._fill_handler = script.new(tool)

func test_preview_nested_circle_profile():
	_count_fill_queries()
	for radius in range(1, 7):
		api.place_shape_marker_plain(Vector2.ZERO, float(radius), 0.0, 64)
	var start = OS.get_ticks_usec()
	var first = api.get_build_preview_target(Vector2(550, 10))
	var cold = OS.get_ticks_usec() - start
	assert_eq(first.kind, "Fill")
	assert_eq(first.fill.polygon.size(), 130)
	var timings = []
	for i in range(30):
		start = OS.get_ticks_usec()
		var same = api.get_build_preview_target(Vector2(550, i), false, first.zone_hash)
		timings.append(OS.get_ticks_usec() - start)
		assert_eq_deep(same, {"zone_hash": first.zone_hash})
	assert_eq(tool._fill_handler.computations, 1, "A visited ring is clipped once, not once per pointer move")
	var second = api.get_build_preview_target(Vector2(450, 10), false, first.zone_hash)
	assert_ne(second.zone_hash, first.zone_hash)
	assert_eq(tool._fill_handler.computations, 2)
	assert_eq(api.get_build_preview_target(Vector2(550, 20)).zone_hash, first.zone_hash)
	assert_eq(tool._fill_handler.computations, 2, "Revisiting a cached ring also skips clipping")
	timings.sort()
	print("Nested circles: cold=", cold, "us; cached median=", timings[15], "us p95=", timings[28], "us; computations=", tool._fill_handler.computations)

func test_preview_zone_rejects_stale_hits_and_reuses_unchanged_marker_fingerprints():
	var marker = add_shape(10)
	var pos = Vector2(20, 20)
	api.get_build_preview_target(pos)
	var retained = tool._regions_cache._markers[10]
	retained["reuse_probe"] = true
	api.place_path_marker([Vector2(1000, 0), Vector2(1100, 0)], false)
	api.get_build_preview_target(pos)
	assert_true(tool._regions_cache._markers[10].get("reuse_probe", false), "An unrelated revision reuses the full fingerprint record")
	var hits = tool._fill_handler._collect_hit_markers(pos, tool._get_grid_cell_size())
	assert_eq(hits.size(), 1)
	assert_true(api.delete_marker(marker.id))
	assert_null(tool._regions_cache.resolve(tool, pos, hits), "Stale hits must fail before typed Rect2 dependency lookup")

func test_preview_zone_fresh_click_replaces_restored_hash_without_dropping_other_components():
	var marker = add_shape(10)
	marker.set_primitives(tool.GeometryUtils.points_to_segs([Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)]))
	var cutter = add_shape(11)
	cutter.set_primitives(tool.GeometryUtils.points_to_segs([Vector2(-10, -150), Vector2(10, -150), Vector2(10, 150), Vector2(-10, 150)]))
	tool.invalidate_geometry()
	api.get_build_preview_target(Vector2(-50, 20))
	var right = api.get_build_preview_target(Vector2(50, 20))
	var data = JSON.parse(JSON.print(tool._regions_cache.save_data(tool))).result
	# Persisted keys are opaque identities; a fresh native calculation may have a different key after rounding.
	data.zones[0].zone_hash = "0".repeat(64)
	tool._regions_cache.clear()
	tool._regions_cache.load_data(data)
	assert_eq(api.get_build_preview_target(Vector2(-50, 20)).zone_hash, data.zones[0].zone_hash)
	api.compute_fill_polygon(Vector2(-50, 20))
	assert_eq(tool._regions_cache._regions.size(), 2, "Replace the queried component, not append another copy")
	assert_eq(api.get_build_preview_target(Vector2(50, 20)).zone_hash, right.zone_hash, "The other disconnected component stays cached")
	for entry in tool._regions_cache._regions:
		assert_true(entry.pool is PoolVector2Array, "Hit-test geometry is converted once on insertion")
		assert_ne(entry.value.zone_hash, data.zones[0].zone_hash)

func _rect_polygon(left: float, top: float, right: float, bottom: float) -> Array:
	return [Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)]

func _primitive_region_contains(primitives: Array, point: Vector2) -> bool:
	var inside = false
	for contour in tool.GeometryUtils.split_segments_into_chains(primitives):
		if Geometry.is_point_in_polygon(point, contour): inside = not inside
	return inside

func test_compound_shape_fill_api_cache_and_followup_booleans_preserve_every_ring():
	var marker = add_shape(10)
	var primitives = []
	for ring in [_rect_polygon(-100, -100, -10, 100), _rect_polygon(10, -100, 100, 100), _rect_polygon(30, -30, 70, 30)]:
		primitives += tool.GeometryUtils.points_to_segs(ring)
	marker.set_primitives(primitives)
	tool.invalidate_geometry()
	var whole = api.get_shape_polygon(10).polygon
	for point in [Vector2(-50, 10), Vector2(80, 10)]:
		assert_true(Geometry.is_point_in_polygon(point, whole))
		var preview = api.get_build_preview_target(point)
		assert_eq(preview.kind, "Fill")
		assert_eq(preview.fill.marker_ids, [10])
		assert_true(Geometry.is_point_in_polygon(point, preview.fill.polygon))
		assert_false(Geometry.is_point_in_polygon(-point, preview.fill.polygon), "Only the visited island is filled: %s %s" % [point, preview.fill.polygon])
		assert_eq_deep(api.compute_fill_polygon(point).polygon, preview.fill.polygon)
	assert_false(Geometry.is_point_in_polygon(Vector2(50, 10), whole))
	assert_eq_deep(api.get_build_preview_target(Vector2(50, 10)), {"zone_hash": ""})
	var saved = tool._regions_cache.save_data(tool)
	tool._regions_cache.clear()
	tool._regions_cache.load_data(JSON.parse(JSON.print(saved)).result)
	assert_eq(api.get_build_preview_target(Vector2(80, 10)).kind, "Fill")
	# Editing only the later ring must invalidate a saved/cached target.
	var old_hash = api.get_build_preview_target(Vector2(-50, 10)).zone_hash
	marker.set_primitives(primitives + tool.GeometryUtils.points_to_segs(_rect_polygon(-70, -30, -30, 30)))
	tool.invalidate_geometry()
	assert_ne(api.get_build_preview_target(Vector2(-80, 10)).zone_hash, old_hash)
	# Merge into the second island: the first island and both existing holes survive.
	var data = shape_data(11)
	data.shape_primitives = tool.GeometryUtils.points_to_segs(_rect_polygon(80, -20, 120, 20))
	var before = marker_state()
	assert_false(api.apply_marker_geometry(data, "Merge").empty())
	var after = marker_state()
	for point in [Vector2(-80, 10), Vector2(110, 10)]: assert_true(Geometry.is_point_in_polygon(point, marker.get_polygon()))
	for point in [Vector2(-50, 10), Vector2(50, 10)]: assert_false(Geometry.is_point_in_polygon(point, marker.get_polygon()))
	assert_false(Geometry.is_point_in_polygon(Vector2(-80, 10), api.compute_fill_polygon(Vector2(110, 10)).polygon), "Merge must also preserve island connectivity")
	last_record.undo()
	assert_eq_deep(marker_state(), before)
	last_record.redo()
	assert_eq_deep(marker_state(), after)
	var persistence = load(mod_root.plus_file("scripts/tool/GuidesLinesPersistence.gd")).new()
	persistence._mod = tool.parent_mod
	var map_data = {}
	persistence.save_map(map_data)
	assert_true(persistence.load_map(JSON.parse(JSON.print(map_data)).result))
	assert_true(Geometry.is_point_in_polygon(Vector2(-80, 10), api.get_shape_polygon(10).polygon))
	assert_false(Geometry.is_point_in_polygon(Vector2(50, 10), api.get_shape_polygon(10).polygon))
	assert_false(Geometry.is_point_in_polygon(Vector2(-80, 10), api.compute_fill_polygon(Vector2(110, 10)).polygon))
	persistence._mod = null

func test_cut_of_a_compound_shape_uses_real_boundaries_and_preserves_the_other_island():
	var marker = add_shape(10)
	marker.set_primitives(tool.GeometryUtils.points_to_segs(_rect_polygon(-100, -40, -10, 40)) + tool.GeometryUtils.points_to_segs(_rect_polygon(10, -40, 100, 40)))
	tool.invalidate_geometry()
	var data = shape_data(11)
	data.shape_primitives = tool.GeometryUtils.points_to_segs(_rect_polygon(-5, -60, 5, 60))
	var before = marker_state()
	var desc = tool._get_shape_descriptor_from_marker_data(data)
	assert_true(tool._take_cut_snapshot(desc).empty(), "Crossing only a transport bridge is a no-op")
	tool._do_apply_cut(desc)
	assert_eq_deep(marker_state(), before)
	data.shape_primitives = tool.GeometryUtils.points_to_segs(_rect_polygon(0, -60, 120, 60))
	tool.cut_mode = true
	assert_true(tool._try_apply_non_placing_shape_mode(tool._get_shape_descriptor_from_marker_data(data), Vector2.ZERO))
	assert_eq(marker.marker_type, "Path")
	for point in marker.marker_points: assert_lt(point.x, 0.0)
	var after = marker_state()
	last_record.undo()
	assert_eq_deep(marker_state(), before)
	last_record.redo()
	assert_eq_deep(marker_state(), after)

func test_tangent_hole_bridge_has_no_zero_length_edges_and_keeps_later_sectors():
	var handler = tool._fill_handler
	var outer = _rect_polygon(0, 0, 100, 100)
	var hole = [Vector2.ZERO, Vector2(10, 30), Vector2(30, 10)]
	var polygon = handler._bridge_hole_into_polygon(outer, hole, [0, 0])
	for i in range(polygon.size()): assert_ne(polygon[i], polygon[(i + 1) % polygon.size()])
	for point in [Vector2(3, 40), Vector2(40, 3)]:
		assert_ne(handler._bridge_vertex_index(Vector2.ZERO, point, polygon), -1)
	assert_false(Geometry.is_point_in_polygon(Vector2(12, 12), polygon))
	assert_true(Geometry.is_point_in_polygon(Vector2(50, 50), polygon))
	var clips = [PoolVector2Array(outer)]
	for points in [[Vector2.ZERO, Vector2(30, 5), Vector2(40, 1)], [Vector2.ZERO, Vector2(1, 40), Vector2(5, 30)], _rect_polygon(50, 50, 60, 60)]:
		var pool = PoolVector2Array(points)
		if not Geometry.is_polygon_clockwise(pool): pool.invert()
		clips.append(pool)
	var filled = handler._merge_clips_to_polygon(clips, Vector2(50, 10))
	assert_false(filled.empty())
	for i in range(filled.size()): assert_ne(filled[i], filled[(i + 1) % filled.size()])
	for point in [Vector2(20, 2), Vector2(2, 20), Vector2(55, 55)]: assert_false(Geometry.is_point_in_polygon(point, filled))
	assert_true(Geometry.is_point_in_polygon(Vector2(50, 10), filled))

func test_contour_membership_checks_later_vertices_and_tangent_hole_rotations():
	var handler = tool._fill_handler
	var outer = PoolVector2Array(_rect_polygon(0, 0, 100, 100))
	assert_true(handler._any_contour_vertex_inside(PoolVector2Array([Vector2(-1, 10), Vector2(10, 10), Vector2(10, 20)]), outer))
	assert_false(handler._any_contour_vertex_inside(PoolVector2Array(_rect_polygon(110, 110, 120, 120)), outer))
	var hole = [Vector2(0, 50), Vector2(20, 60), Vector2(20, 40)]
	if not Geometry.is_polygon_clockwise(hole): hole.invert()
	for _rotation in range(hole.size()):
		var filled = handler._merge_clips_to_polygon([outer, PoolVector2Array(hole)], Vector2(80, 50))
		assert_false(filled.empty())
		assert_false(Geometry.is_point_in_polygon(Vector2(15, 50), filled))
		assert_true(Geometry.is_point_in_polygon(Vector2(80, 50), filled))
		hole.append(hole.pop_front())

func test_normalized_contours_bounds_keep_tangent_equal_bounds_and_nested_rings():
	var rings = [_rect_polygon(0, 0, 100, 100), _rect_polygon(0, 40, 20, 60), _rect_polygon(5, 45, 10, 55)]
	# Disjoint rings should be rejected by bounds before native containment tests.
	for i in range(20): rings.append(_rect_polygon(200 + i * 20, 0, 210 + i * 20, 10))
	var segments = []
	for ring in rings: segments += tool.GeometryUtils.points_to_segs(ring)
	var normalized = tool.GeometryUtils.normalized_contours(segments)
	assert_eq(normalized.size(), rings.size())
	for i in range(normalized.size()):
		assert_eq(Geometry.is_polygon_clockwise(normalized[i]), i == 1)
	# A diamond inside a square has exactly the same bounds; it is still a hole.
	segments = tool.GeometryUtils.points_to_segs(rings[0]) + tool.GeometryUtils.points_to_segs([Vector2(0, 50), Vector2(50, 0), Vector2(100, 50), Vector2(50, 100)])
	normalized = tool.GeometryUtils.normalized_contours(segments)
	assert_eq(normalized.size(), 2)
	assert_false(Geometry.is_polygon_clockwise(normalized[0]))
	assert_true(Geometry.is_polygon_clockwise(normalized[1]))

func test_initial_geometry_revision_read_is_pure_but_grid_change_invalidates():
	var before = tool.geometry_revision
	api.get_geometry_revision()
	assert_eq(tool.geometry_revision, before)
	api._geometry_cell_size = Vector2(1, 1)
	api.get_geometry_revision()
	assert_eq(tool.geometry_revision, before + 1)

func test_difference_preserves_holes_and_disconnected_solids_without_duplicate_edges():
	var marker = add_shape(10)
	var outer = _rect_polygon(-100, -100, 100, 100)
	marker.set_primitives(tool.GeometryUtils.points_to_segs(outer))
	for cut in [_rect_polygon(-30, -30, 30, 30), _rect_polygon(-30, -30, 30, 30), _rect_polygon(-10, -10, 10, 10)]:
		tool._do_apply_difference({"shape_type": "poly", "points": cut})
		assert_eq(marker.get_primitives().size(), 8, "Repeated and nested cuts into a hole add no edges")
		assert_false(_primitive_region_contains(marker.get_primitives(), Vector2(5, 5)))
		assert_true(_primitive_region_contains(marker.get_primitives(), Vector2(80, 10)))
	# A cut crossing an existing hole must keep a closed, duplicate-free boundary.
	tool._do_apply_difference({"shape_type": "poly", "points": _rect_polygon(0, -10, 120, 10)})
	for point in [Vector2(5, 5), Vector2(80, 5)]:
		assert_false(_primitive_region_contains(marker.get_primitives(), point))
	assert_true(_primitive_region_contains(marker.get_primitives(), Vector2(-80, 5)))
	marker.set_primitives(tool.GeometryUtils.points_to_segs(outer))
	tool._do_apply_difference({"shape_type": "poly", "points": _rect_polygon(-10, -120, 10, 120)})
	var data = shape_data(11, Vector2(50, 0))
	data.shape_primitives = tool.GeometryUtils.points_to_segs(_rect_polygon(40, -20, 60, 20))
	var before = marker_state()
	assert_false(api.apply_marker_geometry(data, "Difference").empty())
	var after = marker_state()
	assert_true(_primitive_region_contains(marker.get_primitives(), Vector2(-50, 5)))
	assert_false(_primitive_region_contains(marker.get_primitives(), Vector2(50, 5)))
	assert_true(_primitive_region_contains(marker.get_primitives(), Vector2(80, 5)))
	last_record.undo()
	assert_eq_deep(marker_state(), before)
	last_record.redo()
	assert_eq_deep(marker_state(), after)
	# Legacy rings can have identical winding; containment restores nested island topology.
	var primitives = []
	for ring in [outer, _rect_polygon(-70, -70, 70, 70), _rect_polygon(-40, -40, 40, 40), _rect_polygon(-10, -10, 10, 10)]:
		primitives += tool.GeometryUtils.points_to_segs(ring)
	marker.set_primitives(primitives)
	tool._do_apply_difference({"shape_type": "poly", "points": _rect_polygon(75, -10, 120, 10)})
	for point in [Vector2(5, 5), Vector2(50, 5), Vector2(85, 5)]:
		assert_false(_primitive_region_contains(marker.get_primitives(), point))
	for point in [Vector2(20, 5), Vector2(-85, 5)]:
		assert_true(_primitive_region_contains(marker.get_primitives(), point))

func test_bridge_visibility_rejects_a_bridge_contained_in_an_unrelated_edge():
	var outer = _rect_polygon(-100, -100, 100, 100)
	var edge = [Vector2(-40, 0), Vector2(40, 0), Vector2(0, -40)]
	assert_false(tool._fill_handler._bridge_visible(Vector2(-10, 0), Vector2(10, 0), outer, [edge]))
	assert_true(tool._fill_handler._bridge_visible(Vector2(-100, -100), Vector2(-40, -40), outer, []))

func test_bridge_selects_the_matching_sector_of_a_duplicated_vertex():
	var handler = tool._fill_handler
	var outer = _rect_polygon(-100, -100, 100, 100)
	var hole = _rect_polygon(-30, -30, 30, 30)
	hole.invert()
	var polygon = handler._bridge_hole_into_polygon(outer, hole, [0, 0])
	var a = outer[0]
	for b in [Vector2(-90, -20), Vector2(60, -90)]:
		var index = handler._bridge_vertex_index(a, b, polygon)
		assert_ne(index, -1)
		var next = polygon[(index + 1) % polygon.size()]
		var previous = polygon[(index - 1 + polygon.size()) % polygon.size()]
		assert_true((a - previous).cross(b - a) >= 0.0 and (next - a).cross(b - a) >= 0.0)

func test_preview_reuses_one_shape_snapshot_until_geometry_revision_changes():
	add_shape(10)
	api.get_geometry_revision()
	var entries = tool._regions_cache.shape_entries(tool)
	entries[0].reuse_probe = true
	api.get_build_preview_target(Vector2(20, 20))
	assert_true(tool._regions_cache.shape_entries(tool)[0].get("reuse_probe", false))
	tool.invalidate_geometry()
	assert_false(tool._regions_cache.shape_entries(tool)[0].has("reuse_probe"))
	assert_true(api.delete_marker(10))
	last_record.undo()
	assert_true(tool._regions_cache.shape_entries(tool)[0].marker == tool.markers_lookup[10], "Restored equal geometry must refresh the marker handle")

func _assert_no_crossed_bridges(polygon: Array):
	var crossings = []
	for i in range(polygon.size()):
		var a = polygon[i]
		var b = polygon[(i + 1) % polygon.size()]
		for j in range(i + 2, polygon.size()):
			var c = polygon[j]
			var d = polygon[(j + 1) % polygon.size()]
			var hit = Geometry.segment_intersects_segment_2d(a, b, c, d)
			if hit != null and not ((hit == a or hit == b) and (hit == c or hit == d)):
				crossings.append([i, j])
	assert_true(crossings.empty(), str(crossings))

func test_fill_hole_bridges_ignore_creation_order_and_nested_island_holes():
	var base = _rect_polygon(-100, -100, 100, 100)
	var cuts = [_rect_polygon(-10, -10, 10, 10), _rect_polygon(-70, -70, -40, -40), _rect_polygon(40, 40, 70, 70)]
	for reverse in [false, true]:
		if reverse: cuts.invert()
		var polygon = tool._fill_handler._subtract_shapes(Vector2(90, 0), base, cuts)
		assert_almost_eq(tool._fill_handler._polygon_area(polygon), 37800.0, 0.01)
		_assert_no_crossed_bridges(polygon)
		for cut in cuts:
			assert_false(Geometry.is_point_in_polygon((cut[0] + cut[2]) * 0.5, polygon))
	var hole = _rect_polygon(-50, -50, 50, 50)
	hole.invert()
	var island = _rect_polygon(-20, -20, 20, 20)
	var inner_hole = _rect_polygon(-5, -5, 5, 5)
	inner_hole.invert()
	for reverse in [false, true]:
		var clips = [PoolVector2Array(base), PoolVector2Array(hole), PoolVector2Array(island), PoolVector2Array(inner_hole)]
		if reverse: clips.invert()
		var outer = Array(tool._fill_handler._merge_clips_to_polygon(clips, Vector2(90, 0)))
		assert_almost_eq(tool._fill_handler._polygon_area(outer), 30000.0, 0.01)
		_assert_no_crossed_bridges(outer)
		assert_false(Geometry.is_point_in_polygon(Vector2(10, 10), outer))
		var inner = Array(tool._fill_handler._merge_clips_to_polygon(clips, Vector2(10, 10)))
		assert_almost_eq(tool._fill_handler._polygon_area(inner), 1500.0, 0.01)
		assert_false(Geometry.is_point_in_polygon(Vector2.ZERO, inner))
		_assert_no_crossed_bridges(inner)

func test_fill_repeated_cutter_vertices_use_topology_fallback():
	var script = GDScript.new()
	script.source_code = 'extends "' + mod_root.plus_file("scripts/tool/GuidesLinesFill.gd") + '"\nvar fallbacks = 0\nfunc _init(owner).(owner):\n\tpass\nfunc _subtract_shapes_sequential(pos: Vector2, base: Array, cuts: Array) -> Array:\n\tfallbacks += 1\n\treturn ._subtract_shapes_sequential(pos, base, cuts)\n'
	assert_eq(script.reload(), OK)
	var handler = script.new(tool)
	var tangent = [Vector2.ZERO, Vector2(-30, 0), Vector2(-30, -30), Vector2(0, -30), Vector2.ZERO, Vector2(30, 0), Vector2(30, 30), Vector2(0, 30)]
	var polygon = handler._subtract_shapes(Vector2(90, 10), _rect_polygon(-100, -100, 100, 100), [tangent])
	assert_eq(handler.fallbacks, 1)
	assert_almost_eq(handler._polygon_area(polygon), 38200.0, 0.01)
	_assert_no_crossed_bridges(polygon)
	handler.tool = null

func test_fill_separated_columns_and_touching_bounds_keep_exact_area():
	var cuts = []
	var removed_area = 0.0
	for x in range(5):
		for y in range(5):
			var points = []
			for i in range(64):
				points.append(Vector2(x * 100 - 200, y * 100 - 200) + Vector2(cos(TAU * i / 64), sin(TAU * i / 64)) * 10)
			cuts.append(points)
			removed_area += tool._fill_handler._polygon_area(points)
	var started = OS.get_ticks_usec()
	var polygon = tool._fill_handler._subtract_shapes(Vector2(280, 17), _rect_polygon(-300, -300, 300, 300), cuts)
	print("25 separated 64-vertex columns: cold=", OS.get_ticks_usec() - started, "us")
	assert_almost_eq(tool._fill_handler._polygon_area(polygon), 360000.0 - removed_area, 1.0)
	for cut in cuts:
		var center = (cut[0] + cut[32]) * 0.5
		assert_false(Geometry.is_point_in_polygon(center, polygon))
	# Inclusive AABB contact must still reach native union for edge-touching cutters.
	polygon = tool._fill_handler._subtract_shapes(Vector2(90, 10), _rect_polygon(-100, -100, 100, 100), [_rect_polygon(-40, -20, 0, 20), _rect_polygon(0, -20, 40, 20)])
	assert_almost_eq(tool._fill_handler._polygon_area(polygon), 36800.0, 0.01)
	_assert_no_crossed_bridges(polygon)

func test_preview_zone_save_fingerprints_are_lazy_and_invalidated_by_edits():
	var near_id = api.place_shape_marker_plain(Vector2.ZERO, 1.0, 0.0, 4)
	var far_id = api.place_shape_marker_plain(Vector2(1000, 0), 1.0, 0.0, 4)
	api.get_build_preview_target(Vector2(10, 10))
	var records = tool._regions_cache._markers
	assert_true(records[near_id].has("save_hash"))
	assert_false(records[far_id].has("save_hash"), "Distant shapes need no JSON serialization on first hover")
	api.get_build_preview_target(Vector2(1010, 10))
	assert_true(records[far_id].has("save_hash"))
	var old_hash = records[far_id].save_hash
	tool.move_marker(tool.markers_lookup[far_id], Vector2(1100, 0))
	api.get_build_preview_target(Vector2(10, 10))
	assert_false(tool._regions_cache._markers[far_id].has("save_hash"))
	api.get_build_preview_target(Vector2(1110, 10))
	assert_ne(tool._regions_cache._markers[far_id].save_hash, old_hash)
	var saved = tool._regions_cache.save_data(tool)
	tool._regions_cache.clear()
	tool._regions_cache.load_data(JSON.parse(JSON.print(saved)).result)
	api.get_build_preview_target(Vector2(1110, 10))
	assert_eq(tool._regions_cache._regions.size(), 2, "Lazy fingerprints still restore both saved zones")

func test_fill_batch_subtraction_matches_reference_for_holes_crossings_and_cutter_islands():
	var base = _rect_polygon(-100, -100, 100, 100)
	var cases = [
		[_rect_polygon(-70, -60, -40, -30), _rect_polygon(20, 20, 50, 50)],
		[_rect_polygon(-70, -60, 10, 10), _rect_polygon(-20, -20, 50, 50)],
		[_rect_polygon(-20, -150, 20, 150), _rect_polygon(40, -30, 70, 30)],
		[_rect_polygon(-60, -60, 60, -40), _rect_polygon(-60, 40, 60, 60), _rect_polygon(-60, -60, -40, 60), _rect_polygon(40, -60, 60, 60)],
		[_rect_polygon(-80, -80, 80, 80), _rect_polygon(-10, -10, 10, 10)],
	]
	for cuts in cases:
		for reverse in [false, true]:
			if reverse: cuts.invert()
			var pos = Vector2(-90, 0)
			var polygon = tool._fill_handler._subtract_shapes(pos, base, cuts)
			var reference = tool._fill_handler._subtract_shapes_sequential(pos, base, cuts)
			assert_false(polygon.empty())
			assert_almost_eq(tool._fill_handler._polygon_area(polygon), tool._fill_handler._polygon_area(reference), 0.01)
			for x in range(-95, 100, 10):
				for y in range(-95, 100, 10):
					var sample = Vector2(x + 0.137, y + 0.319) # Avoid zero-width bridge boundary points.
					assert_eq(Geometry.is_point_in_polygon(sample, polygon), Geometry.is_point_in_polygon(sample, reference), str([cuts, sample]))
	# A triangle's vertices can all lie inside a concave polygon while its edge crosses the notch.
	var concave = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(60, 100), Vector2(60, 40), Vector2(40, 40), Vector2(40, 100), Vector2(0, 100)]
	assert_false(tool._fill_handler._polygon_fully_inside([Vector2(20, 80), Vector2(80, 80), Vector2(50, 20)], concave))
	assert_true(tool._fill_handler._polygon_fully_inside(_rect_polygon(5, 5, 20, 20), concave))

func test_fill_batch_subtraction_stitches_each_final_hole_once():
	var script = GDScript.new()
	script.source_code = 'extends "' + mod_root.plus_file("scripts/tool/GuidesLinesFill.gd") + '"\nvar bridges = 0\nfunc _init(owner).(owner):\n\tpass\nfunc _bridge_hole_into_polygon(outer: Array, hole: Array, bridge: Array) -> Array:\n\tbridges += 1\n\treturn ._bridge_hole_into_polygon(outer, hole, bridge)\n'
	assert_eq(script.reload(), OK)
	var handler = script.new(tool)
	var base = _rect_polygon(-100, -100, 100, 100)
	var cuts = []
	for radius in range(10, 60, 10): cuts.append(_rect_polygon(-radius, -radius, radius, radius))
	var polygon = handler._subtract_shapes(Vector2(-90, 0), base, cuts)
	assert_eq(handler.bridges, 1, "Nested cutters create one final hole")
	assert_almost_eq(handler._polygon_area(polygon), 30000.0, 0.01)
	cuts = [_rect_polygon(-70, -60, -40, -30), _rect_polygon(20, 20, 50, 50), _rect_polygon(-60, 30, -30, 60)]
	handler.bridges = 0
	polygon = handler._subtract_shapes(Vector2(-90, 0), base, cuts)
	assert_eq(handler.bridges, 3, "Independent holes are stitched once each")
	assert_almost_eq(handler._polygon_area(polygon), 37300.0, 0.01)
	# A connected ring of cutters leaves an island under the cursor; keep the topology fallback.
	cuts = [_rect_polygon(-60, -60, 60, -40), _rect_polygon(-60, 40, 60, 60), _rect_polygon(-60, -60, -40, 60), _rect_polygon(40, -60, 60, 60)]
	polygon = handler._subtract_shapes(Vector2.ZERO, base, cuts)
	assert_almost_eq(handler._polygon_area(polygon), 6400.0, 0.01)
	assert_true(Geometry.is_point_in_polygon(Vector2.ZERO, polygon))
	assert_false(Geometry.is_point_in_polygon(Vector2(90, 0), polygon))
	handler.tool = null

func test_preview_zone_dependencies_invalidate_related_edits_and_new_subtractors_only():
	_count_fill_queries()
	var first_id = api.place_shape_marker_plain(Vector2.ZERO, 1.0, 0.0, 64)
	var second_id = api.place_shape_marker_plain(Vector2(1000, 0), 1.0, 0.0, 64)
	var first = api.get_build_preview_target(Vector2(20, 20))
	api.get_build_preview_target(Vector2(1020, 20))
	assert_eq(tool._fill_handler.computations, 2)
	tool.move_marker(tool.markers_lookup[second_id], Vector2(1100, 0))
	assert_eq_deep(api.get_build_preview_target(Vector2(20, 20), false, first.zone_hash), {"zone_hash": first.zone_hash})
	assert_eq(tool._fill_handler.computations, 2, "A distant marker edit preserves the cached zone")
	tool.move_marker(tool.markers_lookup[first_id], Vector2(10, 0))
	var moved = api.get_build_preview_target(Vector2(20, 20), false, first.zone_hash)
	assert_ne(moved.zone_hash, first.zone_hash)
	assert_eq(tool._fill_handler.computations, 3)
	var hole_id = api.place_shape_marker_plain(Vector2(55, 0), 0.2, 0.0, 64)
	var hole = api.get_build_preview_target(Vector2(20, 20), false, moved.zone_hash)
	assert_ne(hole.zone_hash, moved.zone_hash, "A newly inserted non-hit marker changes the zone's hole")
	assert_eq(hole.fill.marker_ids.size(), 1)
	assert_false(Geometry.is_point_in_polygon(Vector2(55, 0), PoolVector2Array(hole.fill.polygon)))
	var dependencies = tool._regions_cache._regions.back().dependencies
	assert_true(dependencies.has(str(hole_id)), "Subtractors are dependencies even when absent from marker_ids")
	api.delete_marker(hole_id)
	var deletion = last_record
	var restored = api.get_build_preview_target(Vector2(20, 20))
	assert_eq(restored.zone_hash, moved.zone_hash)
	deletion.undo()
	assert_eq(api.get_build_preview_target(Vector2(20, 20)).zone_hash, hole.zone_hash)
	deletion.redo()
	assert_eq(api.get_build_preview_target(Vector2(20, 20)).zone_hash, moved.zone_hash)

func test_preview_zones_distinguish_disconnected_components_and_path_priority():
	_count_fill_queries()
	var outer = add_shape(10)
	outer.set_primitives(tool.GeometryUtils.points_to_segs([Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)]))
	var cutter = add_shape(11)
	cutter.set_primitives(tool.GeometryUtils.points_to_segs([Vector2(-10, -150), Vector2(10, -150), Vector2(10, 150), Vector2(-10, 150)]))
	tool.invalidate_geometry()
	var left = api.get_build_preview_target(Vector2(-50, 20))
	var right = api.get_build_preview_target(Vector2(50, 20), false, left.zone_hash)
	assert_eq_deep(left.fill.marker_ids, right.fill.marker_ids)
	assert_ne(left.zone_hash, right.zone_hash)
	assert_eq(tool._fill_handler.computations, 2)
	assert_eq(api.get_build_preview_target(Vector2(-50, -20)).zone_hash, left.zone_hash)
	assert_eq(tool._fill_handler.computations, 2)
	var path_id = api.place_path_marker([Vector2(50, -50), Vector2(50, 50)], false)
	var path = api.get_build_preview_target(Vector2(50, 20), true)
	assert_eq(path.kind, "Path")
	assert_eq(path.marker.id, path_id)
	assert_eq_deep(api.get_build_preview_target(Vector2(50, 30), true, path.zone_hash), {"zone_hash": path.zone_hash})
	assert_eq_deep(api.get_build_preview_target(Vector2(1000, 1000)), {"zone_hash": ""})

func test_preview_zone_cache_round_trips_with_map_and_rejects_corruption_without_marker_loss():
	_count_fill_queries()
	for radius in range(1, 4): api.place_shape_marker_plain(Vector2.ZERO, float(radius), 0.0, 64)
	var first = api.get_build_preview_target(Vector2(250, 10))
	var persistence = load(mod_root.plus_file("scripts/tool/GuidesLinesPersistence.gd")).new()
	persistence._mod = tool.parent_mod
	var data = {}
	persistence.save_map(data)
	var saved = JSON.parse(JSON.print(data)).result
	assert_eq(saved[persistence.DATA_KEY].zones.zones.size(), 1)
	assert_true(persistence.load_map(saved))
	var restored = api.get_build_preview_target(Vector2(250, 10))
	assert_eq(restored.zone_hash, first.zone_hash)
	assert_eq(tool._fill_handler.computations, 1, "Loading a valid zone must not run clipping again")
	var copy = api.get_build_preview_target(Vector2(250, 10))
	copy.fill.polygon.clear()
	assert_false(api.get_build_preview_target(Vector2(250, 10)).fill.polygon.empty(), "Public snapshots cannot corrupt retained cache data")
	# A corrupt optional cache block is discarded; the authoritative marker load still succeeds.
	saved[persistence.DATA_KEY].zones.zones[0].polygon[0][0] += 1000
	assert_true(persistence.load_map(saved))
	assert_eq(tool.markers.size(), 3)
	api.get_build_preview_target(Vector2(250, 10))
	assert_eq(tool._fill_handler.computations, 2)
	# Click queries continue to resolve from markers rather than trusting persisted cache polygons.
	api.compute_fill_polygon(Vector2(250, 10))
	assert_eq(tool._fill_handler.computations, 3)
	persistence._mod = null

func test_preview_zone_restore_rejects_changed_sources_and_grid_without_losing_markers():
	_count_fill_queries()
	api.place_shape_marker_plain(Vector2.ZERO, 1.0, 0.0, 64)
	var first = api.get_build_preview_target(Vector2(20, 20))
	var persistence = load(mod_root.plus_file("scripts/tool/GuidesLinesPersistence.gd")).new()
	persistence._mod = tool.parent_mod
	var data = {}
	persistence.save_map(data)
	data = JSON.parse(JSON.print(data)).result
	var changed = data.duplicate(true)
	for segment in changed[persistence.DATA_KEY].markers[0].shape_primitives:
		segment.a[0] += 10
		segment.b[0] += 10
	assert_true(persistence.load_map(changed))
	assert_ne(api.get_build_preview_target(Vector2(20, 20)).zone_hash, first.zone_hash)
	assert_eq(tool._fill_handler.computations, 2, "Cached source fingerprints must match the loaded marker geometry")
	tool.cached_world.Level.TileMap.CellSize = Vector2(200, 200)
	assert_true(persistence.load_map(data))
	api.get_build_preview_target(Vector2(20, 20))
	assert_eq(tool._fill_handler.computations, 3, "A saved zone for another grid cannot be reused")
	assert_eq(tool.markers.size(), 1)
	persistence._mod = null

func test_preview_zone_lru_bounds_memory_and_persisted_zone_count():
	_count_fill_queries()
	for id in range(130): tool._do_place_marker(shape_data(id, Vector2(id * 500, 0)))
	for id in range(130): api.get_build_preview_target(Vector2(id * 500 + 20, 20))
	assert_eq(tool._regions_cache._regions.size(), 128)
	assert_eq(tool._regions_cache.save_data(tool).zones.size(), 128)
	var count = tool._fill_handler.computations
	api.get_build_preview_target(Vector2(129 * 500 + 20, 20))
	assert_eq(tool._fill_handler.computations, count)
	api.get_build_preview_target(Vector2(20, 20))
	assert_eq(tool._fill_handler.computations, count + 1, "Evicted zones are safely rebuilt when revisited")

class HoverLogger:
	extends Reference
	var messages = 0
	func debug(_message): messages += 1
	func warn(_message): messages += 1
	func error(_message): messages += 1

func test_hover_queries_are_quiet_match_click_and_do_not_allocate_ids_or_history():
	add_shape(10)
	add_shape(11, Vector2(100, 0))
	var logger = HoverLogger.new()
	api.LOGGER = logger
	tool.LOGGER = logger
	var before = marker_state()
	var ids = [tool.next_id, tool.next_fill_id]
	var record_before = last_record
	for position in [Vector2(-150, 0), Vector2(50, 0), Vector2(250, 0), Vector2(1500, 1500)]:
		logger.messages = 0
		var quiet = api.compute_fill_polygon_quiet(position)
		var nearest = api.find_nearest_marker_by_geometry_quiet(position)
		assert_eq(logger.messages, 0, "Hover must not produce per-query diagnostics")
		assert_eq_deep(api.compute_fill_polygon(position), quiet)
		assert_eq_deep(api.find_nearest_marker_by_geometry(position), nearest)
	assert_eq_deep(marker_state(), before)
	assert_eq_deep([tool.next_id, tool.next_fill_id], ids)
	assert_eq(last_record, record_before)
	tool.LOGGER = null
	api.LOGGER = null

func test_hover_geometry_revision_tracks_move_undo_redo_delete_restore_boolean_and_grid():
	var revision = api.get_geometry_revision()
	var marker = add_shape(10)
	assert_gt(api.get_geometry_revision(), revision)
	revision = api.get_geometry_revision()
	tool.move_marker(marker, Vector2(20, 30))
	var move = last_record
	for operation in ["undo", "redo"]:
		assert_gt(api.get_geometry_revision(), revision)
		revision = api.get_geometry_revision()
		move.call(operation)
	assert_gt(api.get_geometry_revision(), revision)
	revision = api.get_geometry_revision()
	assert_true(api.delete_marker(10))
	var deletion = last_record
	assert_gt(api.get_geometry_revision(), revision)
	revision = api.get_geometry_revision()
	deletion.undo()
	assert_gt(api.get_geometry_revision(), revision)
	revision = api.get_geometry_revision()
	tool.cached_world.Level.TileMap.CellSize = Vector2(200, 200)
	assert_gt(api.get_geometry_revision(), revision)
	revision = api.get_geometry_revision()
	assert_eq(api.get_geometry_revision(), revision, "Idle reads do not invalidate geometry")
	api.apply_shape_difference(Vector2(100, 0), 1.0, 45.0, 4)
	assert_gt(api.get_geometry_revision(), revision)
	revision = api.get_geometry_revision()
	last_record.undo()
	assert_gt(api.get_geometry_revision(), revision, "Boolean undo invalidates even without an overlay")

func test_hover_query_benchmark_with_1000_markers():
	for i in range(1000):
		tool._do_place_marker(shape_data(i, Vector2((i % 40) * 500, int(i / 40) * 500)))
	var before = [tool.next_id, tool.next_fill_id, api.get_geometry_revision()]
	# Warm the retained per-marker geometry before recording query costs.
	api.compute_fill_polygon_quiet(Vector2.ZERO)
	api.find_nearest_marker_by_geometry_quiet(Vector2.ZERO)
	var fill_times = []
	var outline_times = []
	for i in range(30):
		var position = Vector2(i * 500, 0)
		var start = OS.get_ticks_usec()
		assert_true(api.compute_fill_polygon_quiet(position) != null)
		fill_times.append(OS.get_ticks_usec() - start)
		start = OS.get_ticks_usec()
		assert_true(api.find_nearest_marker_by_geometry_quiet(position) != null)
		outline_times.append(OS.get_ticks_usec() - start)
	fill_times.sort()
	outline_times.sort()
	print("Hover query / 1000 separated markers, 30 samples: fill median=%dus p95=%dus; nearest median=%dus p95=%dus" % [fill_times[15], fill_times[28], outline_times[15], outline_times[28]])
	assert_eq_deep([tool.next_id, tool.next_fill_id, api.get_geometry_revision()], before)

func test_boolean_anchor_centers_final_geometry_and_replays_original_position_in_all_shape_modes():
	for mode in ["Merge", "Difference", "Conform", "Wrap"]:
		tool.markers.clear()
		tool.markers_lookup.clear()
		tool.next_id = 11
		var original = tool.GuideMarkerClass.new(Vector2(10, 10))
		original.marker_type = "Shape"
		original.id = 10
		var polygon = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 80), Vector2(0, 80)]
		if mode == "Wrap":
			polygon = [Vector2(0, -20), Vector2(100, -20), Vector2(100, 100), Vector2(0, 100)]
		original.set_primitives(tool.GeometryUtils.points_to_segs(polygon))
		tool.markers.append(original)
		tool.markers_lookup[10] = original
		var before = marker_state()
		var cutter = [Vector2(60, -10), Vector2(120, -10), Vector2(120, 90), Vector2(60, 90)]
		var expected = Vector2(30, 40)
		if mode == "Merge":
			cutter = [Vector2(60, 0), Vector2(300, 0), Vector2(300, 80), Vector2(60, 80)]
			expected = Vector2(150, 40)
		elif mode == "Wrap":
			cutter = [Vector2(-50, 0), Vector2(50, 0), Vector2(50, 80), Vector2(-50, 80)]
			expected = Vector2(-25, 40)
		var data = shape_data(11, Vector2(60, 20))
		data["shape_primitives"] = tool.GeometryUtils.points_to_segs(cutter)
		var result = api.apply_marker_geometry(data, mode)
		assert_false(result.empty(), mode)
		var changed = tool.markers_lookup[result.marker_id] if mode == "Wrap" else original
		assert_almost_eq(changed.position.x, expected.x, 0.001, mode)
		assert_almost_eq(changed.position.y, expected.y, 0.001, mode)
		if mode == "Wrap":
			assert_eq(original.position, Vector2(10, 10), "Wrapping leaves neighbors untouched")
		if mode == "Merge":
			assert_eq(result.affected_markers[0].new_position, expected)
		var after = marker_state()
		var action = last_record
		for _cycle in range(2):
			action.undo()
			assert_eq_deep(marker_state(), before)
			action.redo()
			assert_eq_deep(marker_state(), after)
		# Baked templates now rotate around the final outline's center.
		tool.capture_marker_as_template(changed.position)
		tool.select_template(tool.templates.size() - 1)
		var resolved = api.get_template_markers(Vector2(500, 500), -1, 180, 1)[0]
		var points = []
		for segment in resolved.shape_primitives:
			points += [segment.a, segment.b]
		var bounds = tool.GeometryUtils.polygon_intersection_bounds(points)
		assert_almost_eq((bounds.position + bounds.size * 0.5).x, 500.0, 0.001)
		assert_almost_eq((bounds.position + bounds.size * 0.5).y, 500.0, 0.001)

func test_boolean_anchor_merge_does_not_skip_different_shapes_with_equal_anchor_and_vertex_count():
	var marker = add_shape(10)
	marker.set_primitives(tool.GeometryUtils.points_to_segs([Vector2.ZERO, Vector2(100, 0), Vector2(100, 80), Vector2(0, 80)]))
	var data = shape_data(11, marker.position)
	data["shape_primitives"] = tool.GeometryUtils.points_to_segs([Vector2(-50, -20), Vector2(150, -20), Vector2(150, 100), Vector2(-50, 100)])
	var result = api.apply_marker_geometry(data, "Merge")
	assert_false(result.empty())
	assert_eq(marker.position, Vector2(50, 40))
	assert_true(marker.get_geometry_bounds(null, tool._get_grid_cell_size()).size.x > 199.0)

func test_template_api_resolves_selected_and_explicit_ids_without_mutating_source_and_stamps_one_action():
	var line = api.place_line_marker(Vector2.ZERO, 30, true)
	var path = api.place_arrow_marker(Vector2(100, 0), Vector2(300, 0), 25, 30)
	tool.start_group_capture()
	tool.template_group_ids = {line: true, path: true}
	assert_true(tool.save_group_template())
	var id = tool.templates[0].id
	assert_true(api.select_template(id))
	assert_eq(api.get_placement_state().active_marker_type, "Template")
	assert_true(api.set_template_transform(30, 2))
	var source = tool.templates.duplicate(true)
	var copy = api.get_templates()
	copy[0].items.clear()
	assert_eq_deep(tool.templates, source)
	var state = api.get_placement_state()
	assert_eq(state.template_scale, 2.0)
	assert_eq(state.template_rotation_offset, 30.0)
	var next = tool.next_id
	var batch = api.get_template_markers(Vector2(1000, 1000), -1, 60, 0.5)
	assert_eq(batch.size(), 2)
	assert_false(batch[0].has("id"))
	assert_eq(batch[0].angle, 120.0)
	assert_almost_eq(batch[0].position.y, 850.0, 0.001)
	assert_almost_eq(batch[1].marker_points[1].y, 1150.0, 0.001)
	assert_eq(batch[0].outline_points.size(), 3)
	assert_false(batch[0].closed)
	assert_eq(tool.next_id, next)
	var explicit = api.get_template_markers(Vector2.ZERO, id)
	assert_eq(explicit[0].angle, 30.0)
	assert_almost_eq(explicit[0].position.x, -150.0, 0.001)
	assert_almost_eq(explicit[0].position.y, 0.0, 0.001)
	assert_eq_deep(tool.templates, source)
	assert_eq(tool.template_scale, 2.0)
	assert_eq(tool.template_rotation_offset, 30.0)
	assert_true(api.begin_history_capture())
	var placed = api.place_template(Vector2(1000, 1000), -1, 60, 0.5)
	var actions = api.end_history_capture()
	assert_eq(placed, [next, next + 1])
	assert_eq(actions.size(), 1)
	assert_eq(tool.markers_lookup[next].position, batch[0].position)
	assert_eq_deep(tool.markers_lookup[next + 1].marker_points, batch[1].marker_points)
	actions[0].undo()
	assert_eq(tool.markers.size(), 2)
	actions[0].redo()
	assert_eq(tool.markers.size(), 4)
	for invalid in [[NAN, 1.0], [0.0, -1.0], [0.0, 101.0]]:
		assert_false(api.set_template_transform(invalid[0], invalid[1]))
	assert_false(api.select_template(999))
	assert_true(api.get_template_markers(Vector2.ZERO, 999).empty())
	assert_true(api.place_template(Vector2(INF, 0)).empty())
	assert_eq(tool.markers.size(), 4)

func test_template_api_single_shape_scaling_and_exact_geometry_boolean_modes_restore_on_undo():
	var original = add_shape(10)
	original.set_primitives([{"type": "seg", "a": Vector2(-100, -50), "b": Vector2(100, -50)},
		{"type": "seg", "a": Vector2(100, -50), "b": Vector2(100, 50)},
		{"type": "seg", "a": Vector2(100, 50), "b": Vector2(-100, 50)},
		{"type": "seg", "a": Vector2(-100, 50), "b": Vector2(-100, -50)}])
	tool.capture_marker_as_template(Vector2.ZERO)
	assert_true(api.select_template(tool.templates[0].id))
	assert_true(api.set_template_transform(90, 2))
	var resolved = api.get_template_markers(Vector2(500, 500))[0]
	assert_eq(resolved.polygon.size(), 4)
	assert_almost_eq(resolved.shape_primitives[0].a.x, 600.0, 0.001)
	assert_almost_eq(resolved.shape_primitives[0].a.y, 300.0, 0.001)
	tool._place_template_marker(Vector2(500, 500))
	assert_eq_deep(tool.markers.back().get_primitives(), resolved.shape_primitives)
	last_record.undo()
	for mode in ["Normal", "Merge", "Conform", "Wrap", "Difference"]:
		var marker = api.get_template_markers(Vector2(100, 0), -1, -90, 0.5)[0]
		var before = marker_state()
		assert_true(api.begin_history_capture())
		var result = api.apply_marker_geometry(marker, mode)
		var actions = api.end_history_capture()
		assert_false(result.empty(), mode)
		for i in range(actions.size() - 1, -1, -1): actions[i].undo()
		assert_eq_deep(marker_state(), before)
	var count = tool.markers.size()
	for invalid in [{}, {"marker_type": "Shape", "position": Vector2(INF, 0), "color": Color.red},
		{"marker_type": "Path", "position": Vector2.ZERO, "color": Color.red, "marker_points": [Vector2.ZERO]}]:
		assert_true(api.apply_marker_geometry(invalid).empty())
	assert_eq(tool.markers.size(), count)

func test_template_rename_validates_names_and_preserves_geometry_and_active_transform():
	var marker_id = api.place_line_marker(Vector2.ZERO)
	tool.capture_marker_as_template(Vector2.ZERO)
	add_shape(10, Vector2(500, 0))
	tool.start_group_capture()
	tool.template_group_ids = {marker_id: true, 10: true}
	assert_true(tool.save_group_template())
	var items = tool.templates[1].items.duplicate(true)
	var data = tool.templates[0].data.duplicate(true)
	tool.set_group_transform(2)
	tool.set_group_transform(45, true)
	assert_true(tool.rename_template(tool.templates[0].id, "  Вісь кімнати  "))
	assert_true(tool.rename_template(tool.templates[1].id, "Кімната — шаблон"))
	assert_eq(tool.templates[0].name, "Вісь кімнати")
	assert_eq(tool.templates[1].name, "Кімната — шаблон")
	assert_eq_deep(tool.templates[0].data, data)
	assert_eq_deep(tool.templates[1].items, items)
	assert_eq(tool.active_template_index, 1)
	assert_eq(tool.template_scale, 2.0)
	assert_eq(tool.template_rotation_offset, 45.0)
	for invalid in [null, 42, "", "  ", "a\nb", "a\rb", "a\tb", "x".repeat(129)]:
		assert_false(tool.rename_template(tool.templates[1].id, invalid))
	assert_eq(tool.templates[1].name, "Кімната — шаблон")
	assert_false(tool.rename_template(-1, "Missing"))
	var group_id = tool.templates[1].id
	tool.delete_template(0)
	assert_true(tool.rename_template(group_id, "Renamed after deleting an earlier row"))
	assert_eq(tool.templates[0].name, "Renamed after deleting an earlier row")

func test_group_capture_toggles_contours_snapshots_actual_geometry_and_cancels():
	var shape = add_shape(10)
	var path_id = api.place_path_marker([Vector2(400, 0), Vector2(500, 0)])
	var originals = marker_state()
	tool.start_group_capture()
	assert_true(tool.template_capture_mode)
	assert_false(tool.save_group_template())
	tool.toggle_group_marker(Vector2(0, -141.42136))
	assert_true(tool.template_group_ids.has(10), "Outline hit selects the Shape")
	tool.toggle_group_marker(Vector2(0, -141.42136))
	assert_true(tool.template_group_ids.empty())
	tool.toggle_group_marker(shape.position)
	tool.toggle_group_marker(Vector2(450, 0))
	tool.toggle_group_marker(Vector2(1800, 1800))
	assert_eq(tool.template_group_ids.size(), 2)
	shape.set_primitives([])
	assert_true(tool.save_group_template())
	assert_true(tool.is_group_template())
	assert_false(tool.template_capture_mode)
	assert_true(tool.template_group_ids.empty())
	assert_eq(tool.templates[0].items.size(), 2)
	assert_true(tool.templates[0].items[0].shape_primitives.empty(), "Capture reflects geometry at Save time")
	assert_false(tool.templates[0].items[0].has("id"))
	assert_eq_deep(api.get_marker(path_id), originals[path_id])
	var stored = tool.templates.duplicate(true)
	tool._do_move_marker(shape, Vector2(900, 900))
	assert_eq_deep(tool.templates, stored)
	for exit_mode in ["move", "delete", "type", "disable"]:
		tool.set_move_mode(false)
		tool.set_delete_mode(false)
		tool.set_marker_type("Template")
		tool.start_group_capture()
		tool.toggle_group_marker(Vector2(450, 0))
		match exit_mode:
			"move": tool.set_move_mode(true)
			"delete": tool.set_delete_mode(true)
			"type": tool.set_marker_type("Path")
			"disable": tool.Disable()
		assert_false(tool.template_capture_mode)
		assert_false(tool.template_group_capture)
		assert_true(tool.template_group_ids.empty())
	tool.start_group_capture()
	tool.template_group_ids[path_id] = true
	api.delete_marker(path_id)
	tool.refresh_group_selection()
	assert_true(tool.template_group_ids.empty())

func test_group_transform_uses_one_pivot_grid_units_and_immutable_source():
	var line_id = api.place_line_marker(Vector2.ZERO, 30, true, Color.red)
	var path_id = api.place_arrow_marker(Vector2(100, 0), Vector2(300, 0), 25, 30)
	tool.start_group_capture()
	tool.template_group_ids = {line_id: true, path_id: true}
	assert_true(tool.save_group_template())
	var original = tool.templates.duplicate(true)
	# Bounds are [0, 300] x {0}; center is (150, 0), independent of ray length.
	tool.set_group_transform(2.0)
	tool.set_group_transform(90, true)
	var result = tool.build_group_markers(Vector2(1000, 1000))
	assert_eq(result.size(), 2)
	assert_almost_eq(result[0].position.x, 1000.0, 0.001)
	assert_almost_eq(result[0].position.y, 700.0, 0.001)
	assert_eq(result[0].angle, 120.0)
	assert_true(result[0].mirror)
	assert_eq(result[0].color, Color.red)
	assert_almost_eq(result[1].marker_points[0].y, 900.0, 0.001)
	assert_almost_eq(result[1].marker_points[1].y, 1300.0, 0.001)
	assert_eq(result[1].arrow_head_length, 50.0)
	tool.cached_world.Level.TileMap.CellSize = Vector2(200, 300)
	var larger = tool.build_group_markers(Vector2.ZERO)
	assert_almost_eq(larger[0].position.y, -600.0, 0.001)
	assert_eq(larger[1].arrow_head_length, 100.0)
	assert_eq_deep(tool.templates, original)
	tool.reset_group_transform()
	assert_eq(tool.template_scale, 1.0)
	assert_eq(tool.template_rotation_offset, 0.0)

func test_group_regular_shape_snapshots_scale_every_edge_and_template_deletion_keeps_selection():
	var a = add_shape(10)
	var b = add_shape(11, Vector2(400, 0))
	var outline = a.get_primitives().duplicate(true)
	tool.capture_marker_as_template(b.position)
	tool.start_group_capture()
	tool.template_group_ids = {10: true, 11: true}
	assert_true(tool.save_group_template())
	assert_eq(tool.templates[1].items[0].shape_primitives.size(), 4)
	# Both equal squares have their combined bounds centered at (200, 0).
	tool.set_group_transform(2)
	tool.set_group_transform(90, true)
	var batch = tool.build_group_markers(Vector2(1000, 1000))
	for i in range(outline.size()):
		var expected_a = Vector2(1000 - 2 * outline[i].a.y, 1000 + 2 * (outline[i].a.x - 200))
		var expected_b = Vector2(1000 - 2 * outline[i].b.y, 1000 + 2 * (outline[i].b.x - 200))
		assert_almost_eq(batch[0].shape_primitives[i].a.x, expected_a.x, 0.001)
		assert_almost_eq(batch[0].shape_primitives[i].a.y, expected_a.y, 0.001)
		assert_almost_eq(batch[0].shape_primitives[i].b.x, expected_b.x, 0.001)
		assert_almost_eq(batch[0].shape_primitives[i].b.y, expected_b.y, 0.001)
	assert_eq(batch[0].shape_radius, 4.0)
	tool.delete_template(0)
	assert_eq(tool.active_template_index, 0)
	assert_true(tool.is_group_template())
	assert_eq(tool.template_scale, 2.0)
	tool.delete_template(0)
	assert_eq(tool.active_template_index, -1)
	assert_eq(tool.template_scale, 1.0)
	assert_eq(tool.template_rotation_offset, 0.0)

func test_group_placement_is_one_history_record_and_ignores_all_boolean_modes():
	var a = add_shape(10)
	var b = add_shape(11, Vector2(300, 0))
	a.set_primitives([{"type": "seg", "a": Vector2(-10, -20), "b": Vector2(30, 40)}])
	b.set_primitives([])
	tool.start_group_capture()
	tool.template_group_ids = {10: true, 11: true}
	assert_true(tool.save_group_template())
	var before = marker_state()
	tool.next_id = 20
	for name in ["merge_shapes", "difference_mode", "cut_mode", "conforming_mode", "wrapping_mode"]:
		tool.set(name, true)
	tool.set_group_transform(2.0)
	tool.set_group_transform(90.0, true)
	var expected = tool.build_group_markers(Vector2(500, 500))
	assert_true(api.begin_history_capture())
	tool._place_template_marker(Vector2(500, 500))
	var records = api.end_history_capture()
	assert_eq(records.size(), 1)
	assert_eq(records[0].record_type(), "GuidesLines.PlaceGroup")
	assert_eq(tool.next_id, 22)
	assert_eq(tool.markers.size(), 4)
	assert_eq_deep(api.get_marker(10), before[10])
	assert_eq_deep(api.get_marker(11), before[11])
	assert_eq_deep(tool.markers_lookup[20].get_primitives(), expected[0].shape_primitives)
	assert_true(tool.markers_lookup[21].get_primitives().empty())
	var after = marker_state()
	tool.templates.clear()
	tool.template_rotation_offset = 12
	tool.template_scale = 7
	for _cycle in range(2):
		records[0].undo()
		assert_eq_deep(marker_state(), before)
		records[0].redo()
		assert_eq_deep(marker_state(), after)

func test_group_spirals_keep_actual_outlines_and_validate_entire_batch_before_placement():
	var shape_id = api.place_spiral_shape_marker(Vector2.ZERO)
	var path_id = api.place_spiral_path_marker(Vector2(900, 0), {"reverse": true}, Color.red, true)
	tool.markers_lookup[shape_id].set_primitives([])
	tool.start_group_capture()
	tool.template_group_ids = {shape_id: true, path_id: true}
	assert_true(tool.save_group_template())
	tool.set_group_transform(0.5)
	tool.set_group_transform(45, true)
	var batch = tool.build_group_markers(Vector2.ZERO)
	assert_eq(batch.size(), 2)
	assert_true(batch[0].shape_primitives.empty())
	assert_eq(batch[0].spiral_settings.outer_radius, 3.0)
	assert_eq(batch[1].spiral_settings.angle, 45.0)
	assert_true(batch[1].spiral_settings.reverse)
	assert_true(batch[1].path_end_arrow)
	var before = marker_state()
	var next_id = tool.next_id
	last_record = null
	# A finite scale can still exceed the existing Spiral dimension limit.
	tool.set_group_transform(100.0)
	tool.templates[0].items[1].spiral_settings.outer_radius = 20.0
	assert_true(tool.build_group_markers(Vector2.ZERO).empty())
	tool._place_template_marker(Vector2.ZERO)
	assert_eq_deep(marker_state(), before)
	assert_eq(tool.next_id, next_id)
	assert_null(last_record)
	for invalid in [0.0, -1.0, INF, NAN, 101.0]:
		tool.set_group_transform(invalid)
		assert_eq(tool.template_scale, 100.0)
	tool.cached_world = null
	assert_true(tool.build_group_markers(Vector2.ZERO).empty())

func test_fill_nested_circles_excludes_inner_regions_in_both_marker_orders():
	tool.FillMarkerClass = load(mod_root.plus_file("scripts/guides/FillMarker.gd"))
	for radius in range(8, 0, -1):
		assert_ne(api.place_shape_marker_plain(Vector2.ZERO, float(radius), 0.0, 64), -1)
	for _order in range(2):
		for radius in range(8, 0, -1):
			var pos = Vector2((radius - 0.5) * 100, 0)
			var result = api.compute_fill_polygon(pos)
			assert_not_null(result)
			if result == null: continue
			var polygon = result.polygon
			assert_eq(result.marker_ids.size(), 9 - radius)
			assert_true(Geometry.is_point_in_polygon(pos, polygon))
			assert_eq(Geometry.is_point_in_polygon(Vector2.ZERO, polygon), radius == 1)
			var expected_area = 32.0 * sin(TAU / 64) * (radius * radius - (radius - 1) * (radius - 1)) * 10000
			assert_almost_eq(tool._fill_handler._polygon_area(polygon), expected_area, 2.0)
			for sample_radius in range(1, 9):
				var sample = Vector2((sample_radius - 0.5) * 100, 0).rotated(0.37)
				assert_eq(Geometry.is_point_in_polygon(sample, polygon), sample_radius == radius)
			var fill = tool.FillMarkerClass.new()
			fill.Load(tool._fill_handler.handle_fill_click(pos))
			assert_eq_deep(fill.polygon, polygon)
		tool.markers.invert()

func test_fill_intersection_subtracts_non_hit_overlap_and_hole():
	assert_ne(api.place_shape_marker_plain(Vector2.ZERO, sqrt(2.0), 45.0, 4), -1)
	assert_ne(api.place_shape_marker_plain(Vector2(100, 0), sqrt(2.0), 45.0, 4), -1)
	var pos = Vector2(25, 0)
	var result = api.compute_fill_polygon(pos)
	assert_not_null(result)
	if result == null: return
	assert_almost_eq(tool._fill_handler._polygon_area(result.polygon), 20000.0, 1.0)
	assert_ne(api.place_shape_marker_plain(Vector2(100, 0), sqrt(2.0) * 0.5, 45.0, 4), -1)
	assert_ne(api.place_shape_marker_plain(Vector2(25, 60), sqrt(2.0) * 0.1, 45.0, 4), -1)
	for _order in range(2):
		result = api.compute_fill_polygon(pos)
		assert_not_null(result)
		if result == null: continue
		assert_eq(result.fill_type, "intersection")
		assert_eq(result.marker_ids.size(), 2)
		assert_almost_eq(tool._fill_handler._polygon_area(result.polygon), 14600.0, 1.0)
		assert_true(Geometry.is_point_in_polygon(pos, result.polygon))
		assert_false(Geometry.is_point_in_polygon(Vector2(75, 0), result.polygon))
		assert_false(Geometry.is_point_in_polygon(Vector2(25, 60), result.polygon))
		assert_true(Geometry.is_point_in_polygon(Vector2(75, 75), result.polygon))
		assert_false(Geometry.is_point_in_polygon(Vector2(-50, 0), result.polygon))
		tool.markers.invert()

func test_path_spiral_ignores_shape_width_and_roundtrips():
	var id = api.place_spiral_path_marker(Vector2.ZERO, {"width": 0})
	assert_ne(id, -1)
	var saved = tool.markers_lookup[id].Save()
	var restored = tool.GuideMarkerClass.new()
	assert_true(restored.Load(saved))
	assert_eq(restored.spiral_settings.width, 0)
	assert_eq_deep(restored.marker_points, tool.markers_lookup[id].marker_points)
	assert_eq(api.place_spiral_shape_marker(Vector2.ZERO, {"width": 0}), -1)

func test_regular_template_keeps_grid_parameters_but_preserves_modified_and_empty_shapes():
	tool._do_place_marker(shape_data(1))
	var marker = tool.markers_lookup[1]
	marker.get_draw_data(null, tool._get_grid_cell_size())
	tool.capture_marker_as_template(marker.position)
	assert_false(tool.templates.back().data.has("shape_primitives"), "Drawing a regular shape must not bake its template")
	tool.select_template(tool.templates.size() - 1)
	var original = tool._build_shape_descriptor_from_template(Vector2.ZERO).points
	tool.cached_world.Level.TileMap.CellSize *= 2
	var resized = tool._build_shape_descriptor_from_template(Vector2.ZERO).points
	assert_eq(resized.size(), original.size())
	for i in range(original.size()):
		assert_eq(resized[i], original[i] * 2)
	marker.set_primitives([{"type": "seg", "a": Vector2.ZERO, "b": Vector2(2, 4)}])
	tool.capture_marker_as_template(marker.position)
	assert_eq(tool.templates.back().data.shape_primitives.size(), 1)
	marker.set_primitives([])
	tool.capture_marker_as_template(marker.position)
	assert_true(tool.templates.back().data.has("shape_primitives"))
	assert_true(tool.templates.back().data.shape_primitives.empty())

func test_spiral_api_rejects_bad_inputs_without_ids_history_or_markers():
	last_record = null
	for settings in [{"turns": 0}, {"width": 9}, {"outer_radius": INF}, {"clockwise": 1}, {"typo": 2}]:
		assert_eq(api.place_spiral_shape_marker(Vector2.ZERO, settings), -1)
	assert_eq(api.place_spiral_path_marker(Vector2(INF, 0)), -1)
	assert_eq(api.place_spiral_path_marker(Vector2.ZERO, {}, "red"), -1)
	assert_eq(tool.next_id, 0)
	assert_eq(tool.markers.size(), 0)
	assert_null(last_record)
	tool.cached_world = null
	assert_eq(api.place_spiral_path_marker(Vector2.ZERO), -1)

func test_spiral_placement_move_queries_and_replay_keep_exact_geometry():
	tool.set_marker_type("Shape")
	tool.set_shape_preset("Spiral")
	var center = Vector2(30, 40)
	var expected = tool.spiral_points_at(center)
	tool.place_marker(center)
	assert_eq(tool.markers.size(), 1)
	var marker = tool.markers[0]
	assert_eq(marker.marker_subtype, "Spiral")
	assert_eq_deep(api.get_shape_polygon(marker.id).polygon, expected)
	var placed = marker.Save()
	var record = last_record
	tool.active_shape_spiral.outer_radius = 8
	record.undo()
	assert_eq(tool.markers.size(), 0)
	record.redo()
	marker = tool.markers[0]
	assert_eq_deep(marker.Save(), placed)
	var edge = (expected[10] + expected[11]) * 0.5
	assert_eq(api.find_nearest_marker_by_geometry(edge, 1).id, marker.id)
	tool.move_marker(marker, center + Vector2(100, 50))
	assert_almost_eq(marker.get_polygon()[10], expected[10] + Vector2(100, 50), Vector2.ONE * 0.001)
	last_record.undo()
	assert_eq(marker.position, center)
	for i in range(expected.size()):
		assert_almost_eq(marker.get_polygon()[i], expected[i], Vector2.ONE * 0.001)
	tool.set_marker_type("Path")
	tool.set_path_subtype(1)
	tool.active_path_end_arrow = true
	tool.active_path_spiral.reverse = true
	expected = tool.spiral_points_at(center)
	tool.place_marker(center)
	marker = tool.markers.back()
	assert_eq(marker.marker_type, "Path")
	assert_eq(marker.position, center)
	assert_false(marker.path_closed)
	assert_true(marker.path_end_arrow)
	assert_false(tool.path_placement_active)
	assert_eq_deep(marker.marker_points, expected)
	var path_saved = marker.Save()
	last_record.undo()
	last_record.redo()
	assert_eq_deep(tool.markers.back().Save(), path_saved)

func test_spiral_settings_remember_types_and_size_modes_without_affecting_polygons():
	tool.set_marker_type("Shape")
	tool.set_shape_preset("Square")
	tool.set_shape_radius(3.0)
	tool.set_shape_preset("Spiral")
	var cached_result = tool.spiral_result()
	cached_result["cache_probe"] = true
	assert_true(tool.spiral_result().has("cache_probe"), "Repeated reads must reuse local generation")
	tool.set_spiral_value(7.0, "outer_radius")
	assert_false(tool.spiral_result().has("cache_probe"), "Parameter edits invalidate cached geometry")
	tool.set_spiral_value(6.0, "outer_radius")
	tool.set_spiral_value(1, "size_by")
	tool.set_spiral_value(3.0, "spacing")
	tool.set_spiral_value(2.5, "turns")
	assert_eq(tool.active_shape_spiral.outer_radius, 8.5)
	tool.adjust_shape_radius_with_wheel(1)
	assert_almost_eq(tool.active_shape_spiral.outer_radius, 8.75, 0.00001)
	tool.rotate_shape_45()
	assert_eq(tool.active_shape_spiral.angle, 45.0)
	tool.set_marker_type("Path")
	tool.place_marker(Vector2.ZERO)
	assert_true(tool.path_placement_active)
	tool.set_path_subtype(1)
	assert_false(tool.path_placement_active)
	tool.set_spiral_value(1.5, "turns")
	tool.set_spiral_value(false, "clockwise")
	tool.rotate_shape_45()
	assert_eq(tool.active_path_spiral.angle, 45.0)
	tool.set_marker_type("Line")
	tool.set_marker_type("Shape")
	assert_eq(tool.active_shape_preset, "Spiral")
	assert_eq(tool.active_shape_spiral.turns, 2.5)
	tool.set_shape_preset("Square")
	assert_eq(tool.active_shape_radius, 3.0)
	tool.set_marker_type("Path")
	assert_eq(tool.active_path_subtype, "Spiral")
	assert_eq(tool.active_path_spiral.turns, 1.5)
	assert_false(tool.active_path_spiral.clockwise)
	var state = api.get_tool_state()
	state.active_path_spiral.turns = 7
	assert_eq(tool.active_path_spiral.turns, 1.5)

func test_spiral_templates_rotate_about_center_and_replay_exact_geometry():
	for kind in ["Shape", "Path"]:
		tool.set_marker_type(kind)
		if kind == "Shape": tool.set_shape_preset("Spiral")
		else: tool.set_path_subtype(1)
		tool.place_marker(Vector2.ZERO)
		var original = tool.markers.back()
		var points = original.get_polygon() if kind == "Shape" else original.marker_points.duplicate()
		tool.capture_marker_as_template(Vector2.ZERO)
		tool.select_template(tool.templates.size() - 1)
		tool.template_rotation_offset = 90
		var pos = Vector2(900, 800)
		tool._place_template_marker(pos)
		var copy = tool.markers.back()
		assert_eq(copy.marker_subtype, "Spiral")
		assert_eq(copy.position, pos)
		assert_eq(copy.spiral_settings.angle, 90.0)
		var transformed = copy.get_polygon() if kind == "Shape" else copy.marker_points
		assert_eq(transformed.size(), points.size())
		for i in range(points.size()):
			assert_almost_eq(transformed[i], pos + points[i].rotated(PI / 2), Vector2.ONE * 0.001)
		var saved = copy.Save()
		last_record.undo()
		last_record.redo()
		assert_eq_deep(tool.markers.back().Save(), saved)
		tool.markers.clear()
		tool.markers_lookup.clear()
	var empty_id = api.place_spiral_shape_marker(Vector2.ZERO)
	tool.markers_lookup[empty_id].set_primitives([])
	tool.capture_marker_as_template(Vector2.ZERO)
	assert_true(tool.templates.back().data.has("shape_primitives"))
	assert_true(tool.templates.back().data.shape_primitives.empty())
	tool.select_template(tool.templates.size() - 1)
	var count = tool.markers.size()
	tool._place_template_marker(Vector2(100, 100))
	assert_eq(tool.markers.size(), count, "Empty geometry is not regenerated by templates")
	# A parameter-only spiral template uses the same rotated generator if supplied.
	tool.templates.back().data.erase("shape_primitives")
	tool.template_rotation_offset = 90
	var desc = tool._build_shape_descriptor_from_template(Vector2(100, 100))
	assert_false(desc.empty())
	tool._place_template_marker(Vector2(100, 100))
	assert_eq_deep(api.get_shape_polygon(tool.markers.back().id).polygon, desc.points)

func test_spiral_boolean_modes_and_fill_use_concave_contour_and_restore_history():
	tool.FillMarkerClass = load(mod_root.plus_file("scripts/guides/FillMarker.gd"))
	var geometry = load(mod_root.plus_file("scripts/utils/GeometryUtils.gd"))
	var centerline = geometry.build_spiral(geometry.SPIRAL_DEFAULTS).points
	var hit = centerline[int(centerline.size() / 2)] * 100
	for mode in ["normal", "merge", "conforming", "wrapping", "difference", "cut"]:
		tool.markers.clear()
		tool.markers_lookup.clear()
		tool.set_shape_mode("normal")
		var original_id = api.place_spiral_shape_marker(Vector2.ZERO)
		var original = tool.markers_lookup[original_id]
		var before = original.Save()
		assert_not_null(api.compute_fill_polygon(hit))
		assert_null(api.compute_fill_polygon(Vector2.ZERO), "The central void is not filled")
		tool.set_marker_type("Shape")
		tool.set_shape_preset("Square")
		tool.set_shape_radius(0.8)
		tool.set_shape_mode(mode)
		tool.place_marker(hit)
		var after = []
		for marker in tool.markers: after.append(marker.Save())
		assert_ne(JSON.print(after), JSON.print([before]), "Mode must affect the spiral: " + mode)
		var action = last_record
		action.undo()
		assert_eq(tool.markers.size(), 1, mode)
		assert_eq_deep(tool.markers[0].Save(), before)
		action.redo()
		var replayed = []
		for marker in tool.markers: replayed.append(marker.Save())
		assert_eq_deep(replayed, after)
	# A concave spiral's average point falls in its void; that is not containment.
	var spiral = {"shape_type": "poly", "points": geometry.build_spiral(geometry.SPIRAL_DEFAULTS, true).points}
	var small_square = {"shape_type": "poly", "points": geometry.calculate_polygon_vertices(Vector2.ZERO, 0.1, 4)}
	assert_false(tool._shapes_overlap(spiral, small_square))


func before_each():
	var mod = {"markers_opacity": 0.7, "guides_lines_api": null,
		"Global": {"API": {"HistoryApi": self}, "Editor": {"IsSnapping": false}}}
	tool = load(mod_root.plus_file("scripts/tool/GuidesLinesTool.gd")).new(mod)
	tool.GuideMarkerClass = load(mod_root.plus_file("scripts/guides/GuideMarker.gd"))
	tool.cached_world = {"WorldRect": Rect2(-2000, -2000, 4000, 4000),
		"Level": {"TileMap": {"CellSize": Vector2(100, 100)}}}
	mod["guides_tool"] = tool
	api = load(mod_root.plus_file("scripts/api/guides_lines_api.gd")).new(mod, null)
	mod.guides_lines_api = api


func after_each():
	# Break the real constructor's collaborator cycles explicitly.
	last_record = null
	api._unload()
	tool.parent_mod.clear()
	tool.ui.tool = null
	tool.placement.tool = null
	tool._fill_handler.tool = null
	tool = null
	api = null


func record(value, _max_count):
	last_record = value


func on_marker_deleted(id):
	deleted_ids.append(id)


func shape_data(id, pos = Vector2.ZERO):
	return {"id": id, "position": pos, "marker_type": "Shape", "coordinates": true,
		"color": Color(0.2, 0.4, 0.6), "shape_radius": 2.0, "shape_angle": 45.0, "shape_sides": 4}


func add_shape(id, pos = Vector2.ZERO):
	tool._do_place_marker(shape_data(id, pos))
	var marker = tool.markers_lookup[id]
	marker.get_draw_data(tool.cached_world.WorldRect, tool._get_grid_cell_size())
	return marker


func test_api_history_capture_keeps_original_records_and_rejects_nesting():
	last_record = null
	assert_true(api.begin_history_capture())
	assert_false(api.begin_history_capture())
	var id = api.place_shape_marker(Vector2.ZERO, 1.0, 0.0, 4)
	assert_true(id >= 0)
	assert_true(api.delete_marker(id))
	assert_null(last_record, "Captured edits must not create independent undo steps")
	var records = api.end_history_capture()
	assert_eq(records.size(), 2)
	assert_eq_deep(api.end_history_capture(), [])
	for i in range(records.size() - 1, -1, -1):
		records[i].undo()
	assert_eq(api.get_marker_count(), 0)
	for action in records:
		action.redo()
	assert_eq(api.get_marker_count(), 0, "Temporary placement/deletion replays without leftover markers")
	assert_true(api.begin_history_capture())
	var kept_id = api.place_shape_marker(Vector2(500, 500), 1.0, 0.0, 4)
	var kept = api.end_history_capture()
	kept[0].undo()
	assert_null(api.get_marker(kept_id))
	kept[0].redo()
	assert_eq(api.get_marker(kept_id).id, kept_id)
	api.place_shape_marker(Vector2(1000, 1000), 1.0, 0.0, 4)
	assert_true(last_record != null, "Normal recording resumes after capture")


func test_plain_shape_placement_ignores_boolean_modes_and_preserves_them_on_replay():
	for modes in [[true, false], [false, true], [true, true]]:
		tool.markers.clear()
		tool.markers_lookup.clear()
		tool.conforming_mode = false
		tool.wrapping_mode = false
		tool.next_id = 1000
		add_shape(100)
		var before = api.get_marker(100)
		tool.conforming_mode = modes[0]
		tool.wrapping_mode = modes[1]
		assert_true(api.begin_history_capture())
		var id = api.place_shape_marker_plain(Vector2(50, 0), 1.0, 0.0, 4)
		var actions = api.end_history_capture()
		assert_eq(actions.size(), 1)
		assert_false(actions[0].conforming)
		assert_false(actions[0].wrapping)
		for _cycle in range(3):
			assert_eq_deep(api.get_marker(100), before)
			var polygon = api.get_shape_polygon(id).polygon
			assert_eq(polygon.size(), 4)
			for point in polygon:
				assert_almost_eq(point.distance_to(Vector2(50, 0)), 100.0, 0.001)
			assert_eq(tool.conforming_mode, modes[0])
			assert_eq(tool.wrapping_mode, modes[1])
			actions[0].undo()
			assert_null(api.get_marker(id))
			actions[0].redo()
		# The original API keeps its existing mode inheritance contract.
		api.place_shape_marker(Vector2(1000, 0), 1.0, 0.0, 4)
		assert_eq(last_record.conforming, modes[0])
		assert_eq(last_record.wrapping, modes[1])


func test_identical_merge_reports_existing_survivor_without_placing_a_duplicate():
	add_shape(100)
	var before = api.get_marker(100)
	var result = api.place_shape_merge(Vector2.ZERO, 2.0, 45.0, 4)
	assert_eq(result.affected_markers.size(), 1)
	assert_eq(result.affected_markers[0].marker_id, 100)
	assert_true(result.absorbed_marker_ids.empty())
	assert_eq(api.get_marker_count(), 1)
	assert_eq_deep(api.get_marker(100), before)


func marker_state():
	var state = {}
	for marker in api.get_markers():
		state[marker.id] = marker
	return state


func test_captured_boolean_operations_restore_original_geometry_and_marker_ids():
	for method in ["place_shape_merge", "place_shape_conforming", "place_shape_wrapping", "apply_shape_difference"]:
		tool.markers.clear()
		tool.markers_lookup.clear()
		tool.next_id = 1000
		add_shape(100)
		add_shape(101, Vector2(300, 0))
		var before = marker_state()
		assert_true(api.begin_history_capture())
		var result = api.call(method, Vector2(150, 0), 2.0, 45.0, 4)
		assert_false(result.empty())
		var actions = api.end_history_capture()
		assert_eq(actions.size(), 1)
		var after = marker_state()
		for _cycle in range(2):
			actions[0].undo()
			assert_eq_deep(marker_state(), before)
			actions[0].redo()
			assert_eq_deep(marker_state(), after)


func test_shared_nearest_queries_keep_anchor_edge_and_tie_contracts():
	var marker = add_shape(1)
	marker.set_primitives([
		{"type": "seg", "a": Vector2(-10, -10), "b": Vector2(10, -10)},
		{"type": "seg", "a": Vector2(-10, 10), "b": Vector2(10, 10)}])
	var anchored = api.find_nearest_marker_by_geometry(Vector2.ZERO, 0.0)
	assert_eq(anchored.id, 1)
	assert_eq(anchored.point, Vector2.ZERO)
	assert_null(api.find_nearest_geometry_point(Vector2.ZERO, 0.0))
	var edge = api.find_nearest_geometry_point(Vector2.ZERO, 10.0)
	assert_eq(edge.point, Vector2(0, 10), "Edge query selects the last equally distant segment")
	assert_eq(edge.marker_id, 1)
	assert_eq(edge.distance, 10.0)
	var other = add_shape(2)
	other.set_primitives(marker.get_primitives().duplicate(true))
	assert_eq(api.find_nearest_geometry_point(Vector2.ZERO, 10.0).marker_id, 2)
	assert_eq(api.find_nearest_marker_by_geometry(Vector2.ZERO, 0.0).id, 2)
	assert_null(api.find_nearest_geometry_point(Vector2(1000, 1000), 1.0))
	marker.set_primitives([])
	other.set_primitives([])
	assert_null(api.find_nearest_geometry_point(Vector2.ZERO, 100.0))


func test_explicit_api_placement_modes_restore_ui_flags_and_redo_exactly():
	for wrapping in [false, true]:
		tool.markers.clear()
		tool.markers_lookup.clear()
		var neighbor = add_shape(100)
		var original = neighbor.Save()
		tool.conforming_mode = wrapping
		tool.wrapping_mode = not wrapping
		var result
		if wrapping:
			result = tool.api_place_shape_wrapping(shape_data(101, Vector2(150, 0)))
		else:
			result = tool.api_place_shape_conforming(shape_data(101, Vector2(150, 0)))
		assert_eq(result.marker_id, 101)
		var placed = tool.markers_lookup[101].Save()
		var changed_neighbor = neighbor.Save()
		var placement = last_record
		assert_eq(placement.record_type(), "GuidesLines.PlaceMarker")
		assert_eq(tool.conforming_mode, wrapping)
		assert_eq(tool.wrapping_mode, not wrapping)
		placement.undo()
		assert_eq_deep(neighbor.Save(), original)
		placement.redo()
		assert_eq_deep(tool.markers_lookup[101].Save(), placed)
		assert_eq_deep(neighbor.Save(), changed_neighbor)
		assert_eq(tool.conforming_mode, wrapping)
		assert_eq(tool.wrapping_mode, not wrapping)


func test_delete_undo_restores_exact_geometry_without_applying_current_modes():
	var marker = add_shape(7)
	marker.set_primitives([{"type": "seg", "a": Vector2(4, 8), "b": Vector2(16, 8)}])
	var saved = marker.Save()
	var neighbor = add_shape(8)
	var neighbor_saved = neighbor.Save()
	tool.api_delete_marker_by_id(7)
	tool.conforming_mode = true
	tool.wrapping_mode = true
	last_record.undo()
	assert_eq_deep(tool.markers_lookup[7].Save(), saved)
	assert_eq_deep(neighbor.Save(), neighbor_saved)
	assert_eq(tool.markers.size(), tool.markers_lookup.size())
	tool.delete_all_markers()
	last_record.undo()
	assert_eq_deep(tool.markers_lookup[7].Save(), saved)
	assert_eq(tool.markers.size(), tool.markers_lookup.size())


func test_template_redo_keeps_rotated_primitives_and_original_overlap_mode():
	var relative = [{"type": "seg", "a": Vector2(0, 10), "b": Vector2(20, 10)}]
	var data = shape_data(0)
	data["shape_primitives"] = relative
	tool.templates = [{"data": data}]
	tool.active_template_index = 0
	tool.template_rotation_offset = 90.0
	tool._place_template_marker(Vector2(500, 500))
	var saved = tool.markers[0].Save()
	var placement_record = last_record
	placement_record.undo()
	tool.wrapping_mode = true
	tool.active_shape_radius = 50.0
	placement_record.redo()
	assert_eq_deep(tool.markers[0].Save(), saved)
	assert_true(tool.wrapping_mode, "Redo restores the current UI mode after using the recorded mode")
	var seg = tool.markers[0].get_primitives()[0]
	assert_almost_eq(seg.a.x, 490.0, 0.0001)
	assert_almost_eq(seg.b.y, 520.0, 0.0001)
	assert_eq_deep(relative, [{"type": "seg", "a": Vector2(0, 10), "b": Vector2(20, 10)}])


func test_conforming_redo_uses_stored_shape_not_active_settings():
	var existing = add_shape(8)
	var original = existing.get_primitives().duplicate(true)
	tool.conforming_mode = true
	tool.api_place_marker(shape_data(9, Vector2(140, 0)))
	var clipped = existing.get_primitives().duplicate(true)
	assert_ne(clipped, original)
	var placement_record = last_record
	placement_record.undo()
	assert_eq_deep(existing.get_primitives(), original)
	tool.conforming_mode = false
	tool.active_shape_radius = 0.1
	placement_record.redo()
	assert_eq_deep(existing.get_primitives(), clipped)
	placement_record.undo()
	assert_eq_deep(existing.get_primitives(), original)
	assert_false(tool.conforming_mode)

func test_compound_placement_undo_and_cut_do_not_repeat_geometry_invalidation():
	for wrapping in [false, true]:
		tool._do_delete_all()
		tool.conforming_mode = false
		tool.wrapping_mode = false
		add_shape(8)
		tool.conforming_mode = not wrapping
		tool.wrapping_mode = wrapping
		var before = tool.geometry_revision
		tool.api_place_marker(shape_data(9, Vector2(140, 0)))
		assert_eq(tool.geometry_revision, before + 1)
		var record = last_record
		before = tool.geometry_revision
		record.undo()
		assert_eq(tool.geometry_revision, before + 1)
		before = tool.geometry_revision
		record.redo()
		assert_eq(tool.geometry_revision, before + 1)
	tool._do_delete_all()
	tool.conforming_mode = false
	tool.wrapping_mode = false
	var marker = add_shape(10)
	marker.set_primitives(tool.GeometryUtils.points_to_segs(_rect_polygon(-100, -100, 100, 100)))
	tool.invalidate_geometry()
	var before = tool.geometry_revision
	var result = tool._do_apply_cut({"shape_type": "poly", "points": _rect_polygon(-10, -150, 10, 150)})
	assert_eq(result.created_markers_data.size(), 1)
	assert_eq(tool.geometry_revision, before + 1, "The extra Path placement already invalidated the cut")
	before = tool.geometry_revision
	tool._do_apply_cut({"shape_type": "poly", "points": _rect_polygon(1000, 1000, 1100, 1100)})
	assert_eq(tool.geometry_revision, before, "A cut with no target changes does not dirty the cache")


func test_cut_undo_restores_metadata_for_deleted_and_converted_shapes():
	for radius in [1.0, 5.0]:
		tool._do_delete_all()
		var marker = add_shape(5)
		marker.color = Color(0.12345, 0.54321, 0.98765)
		var saved = marker.Save()
		var original_polygon = marker.get_polygon().duplicate()
		var cutter = shape_data(6, Vector2(120, 0))
		cutter.shape_radius = radius
		var desc = tool._get_shape_descriptor_from_marker_data(cutter)
		var snapshots = tool._take_cut_snapshot(desc)
		assert_true(snapshots.has(5))
		var result = tool._do_apply_cut(desc)
		tool._undo_cut(snapshots, result.deleted_ids, result.created_markers_data)
		assert_eq_deep(tool.markers_lookup[5].Save(), saved)
		assert_eq_deep(tool._get_shape_descriptor(tool.markers_lookup[5], Vector2(100, 100)).points, original_polygon)
		assert_eq(tool.markers_lookup[5].color, marker.color)
		assert_eq(tool.markers.size(), tool.markers_lookup.size())


func test_merge_undo_restores_absorbed_shape_metadata():
	deleted_ids = []
	api.connect("marker_deleted", self, "on_marker_deleted")
	var first = add_shape(1, Vector2(-150, 0))
	var second = add_shape(2, Vector2(150, 0))
	second.color = Color(0.12345, 0.54321, 0.98765)
	var saved_first = first.Save()
	var saved_second = second.Save()
	var first_polygon = first.get_polygon().duplicate()
	var second_polygon = second.get_polygon().duplicate()
	var desc = tool._get_shape_descriptor_from_marker_data(shape_data(3))
	var snapshots = tool._snapshot_potential_merge_targets(desc)
	var absorbed = tool._do_apply_merge(desc, Vector2.ZERO)
	assert_eq_deep(absorbed, [2])
	assert_eq_deep(deleted_ids, [2])
	var history = load(mod_root.plus_file("scripts/tool/GuidesLinesHistory.gd"))
	var merge_record = history.MergeShapeRecord.new(tool, desc, Vector2.ZERO, snapshots, absorbed)
	tool.next_id = 1
	merge_record.undo()
	assert_true(tool.next_id > 2, "Restored IDs must be reserved before another placement")
	assert_eq_deep(tool.markers_lookup[1].Save(), saved_first)
	assert_eq_deep(tool.markers_lookup[2].Save(), saved_second)
	assert_eq_deep(tool._get_shape_descriptor(tool.markers_lookup[1], Vector2(100, 100)).points, first_polygon)
	assert_eq_deep(tool._get_shape_descriptor(tool.markers_lookup[2], Vector2(100, 100)).points, second_polygon)
	assert_eq(tool.markers_lookup[2].color, second.color)
	assert_eq(tool.markers.size(), tool.markers_lookup.size())


func test_spatial_queries_find_shape_and_path_edges_far_from_anchor():
	for kind in ["Shape", "Path"]:
		tool._do_delete_all()
		var data = shape_data(1)
		data.marker_type = kind
		data["shape_primitives"] = [{"type": "seg", "a": Vector2(500, -50), "b": Vector2(500, 50)}]
		data["marker_points"] = [Vector2.ZERO, Vector2(500, -50), Vector2(500, 50)]
		data["path_closed"] = false
		tool._do_place_marker(data)
		var point = api.find_nearest_geometry_point(Vector2(505, 0), 10.0)
		assert_not_null(point, kind)
		if point != null:
			assert_eq(point.point, Vector2(500, 0))
			assert_eq(point.distance, 5.0)
		var crossing = api.find_line_intersection(Vector2(490, 0), Vector2(510, 0), Vector2(505, 0), 10.0)
		assert_not_null(crossing, kind)
		if crossing != null:
			assert_eq(crossing.point, Vector2(500, 0))
		assert_null(api.find_nearest_geometry_point(Vector2(900, 900), 1.0))
		tool.parent_mod.guides_lines_api = null
		assert_eq(tool.find_marker_at(Vector2(505, 0), 10.0).id, 1, "UI picking works before API registration")
		assert_true(tool.delete_marker_at_position(Vector2(505, 0), 10.0))
		assert_false(tool.markers_lookup.has(1))
		last_record.undo()
		assert_true(tool.markers_lookup.has(1))
		tool.parent_mod.guides_lines_api = api


func test_merge_partial_failures_preserve_skipped_markers_including_first_candidate():
	var original_script = load(mod_root.plus_file("scripts/tool/GuidesLinesTool.gd"))
	for failed_ids in [[1], [2], [1, 2, 3]]:
		for failure in ["outline", "chain"]:
			var script = GDScript.new()
			var source = original_script.source_code
			for relative in ["../utils/GeometryUtils.gd", "GuidesLinesHistory.gd", "GuidesLinesToolUI.gd", "GuidesLinesPlacement.gd", "GuidesLinesFill.gd", "GuidesLinesRegions.gd", "GuidesLinesPersistence.gd"]:
				source = source.replace('preload("' + relative + '")', 'preload("' + mod_root.plus_file("scripts/tool").plus_file(relative).simplify_path() + '")')
			var expression = "GeometryUtils.merge_polygons_outline(running_pts, desc.points)" if failure == "outline" else "GeometryUtils.compound_segments_to_polygon(merged_segs)"
			assert_true(source.find(expression) >= 0, "Fault injection must target the real merge step")
			script.source_code = source.replace(expression, "([] if " + str(failed_ids) + ".has(marker.id) else " + expression + ")")
			assert_eq(script.reload(), OK)
			var subject = script.new(tool.parent_mod)
			subject.GuideMarkerClass = tool.GuideMarkerClass
			subject.cached_world = tool.cached_world
			var saved = {}
			for id in [1, 2, 3]:
				subject._do_place_marker(shape_data(id, Vector2((id - 2) * 100, 0)))
				subject.markers_lookup[id].get_draw_data(subject.cached_world.WorldRect, subject._get_grid_cell_size())
				saved[id] = subject.markers_lookup[id].Save()
			var desc = subject._get_shape_descriptor_from_marker_data(shape_data(4, Vector2(0, 50)))
			var absorbed = subject._do_apply_merge(desc, Vector2(0, 50))
			for id in failed_ids:
				assert_false(absorbed.has(id), failure)
				assert_true(subject.markers_lookup.has(id), failure)
				if subject.markers_lookup.has(id):
					assert_eq_deep(subject.markers_lookup[id].Save(), saved[id])
			assert_eq(subject.markers.size(), subject.markers_lookup.size())
			if failed_ids.size() == 3:
				assert_eq(subject.markers.size(), 3)
			else:
				assert_eq(subject.markers.size(), 2)
				assert_eq(absorbed.size(), 1)
			subject.ui.tool = null
			subject.placement.tool = null
			subject._fill_handler.tool = null
			subject.parent_mod = null


func test_wrapping_contract_includes_causing_markers_without_changing_them():
	var marker = add_shape(1)
	var saved = marker.Save()
	var result = tool.api_place_shape_wrapping(shape_data(2, Vector2(140, 0)))
	assert_eq_deep(result.dented_by, [1])
	assert_eq(result.affected_markers.size(), 1)
	assert_eq(result.affected_markers[0].marker_id, 1)
	assert_eq(result.affected_markers[0].new_polygon.size(), 4)
	assert_eq_deep(marker.Save(), saved)
	assert_true(result.marker_polygon.size() >= 3)
	tool.cached_world = null
	assert_eq_deep(tool.api_place_shape_wrapping(shape_data(3)).affected_markers, [])


func test_side_callbacks_apply_hex_edge_correction_immediately():
	tool.cached_snappy_mod = {"custom_snap_enabled": true, "active_geometry": 1,
		"radial_mode_to_corner": false, "snap_interval": Vector2(100, 100)}
	tool.active_marker_type = "Shape"
	tool.active_shape_size_mode = "side"
	tool.active_shape_sides = 6
	tool.set_shape_side(2.0)
	assert_almost_eq(tool.active_shape_radius, 4.0 / sqrt(3.0), 0.00001)
	tool.adjust_shape_radius_with_wheel(1)
	assert_almost_eq(tool.active_shape_radius, 4.2 / sqrt(3.0), 0.00001)
	tool.set_shape_sides(4)
	assert_almost_eq(tool.active_shape_radius, 2.1 / sqrt(2.0) * 2.0 / sqrt(3.0), 0.00001)
	tool.cached_snappy_mod.radial_mode_to_corner = true
	assert_almost_eq(tool.recompute_radius_from_side(), 2.1 / sqrt(2.0), 0.00001)


func test_switching_radius_to_side_preserves_hex_shape_size():
	tool.cached_snappy_mod = {"custom_snap_enabled": true, "active_geometry": 2,
		"radial_mode_to_corner": false, "snap_interval": Vector2(100, 100)}
	tool.active_shape_sides = 6
	tool.active_shape_radius = 2.0
	var container = VBoxContainer.new()
	var option = OptionButton.new()
	option.name = "ShapeSizeModeOption"
	option.add_item("Side")
	option.set_item_metadata(0, "side")
	container.add_child(option)
	tool.ui.shape_settings_container = container
	tool.ui._controls["ShapeSizeModeOption"] = option
	tool.ui._on_shape_size_mode_changed(0)
	assert_almost_eq(tool.active_shape_side, sqrt(3.0), 0.00001)
	assert_almost_eq(tool.recompute_radius_from_side(), 2.0, 0.00001)
	tool.ui.shape_settings_container = null
	container.free()


func test_tool_state_exposes_current_move_cut_size_and_template_settings():
	tool.move_mode = true
	tool.cut_mode = true
	tool.active_shape_size_mode = "side"
	tool.active_shape_side = 3.5
	tool.active_template_index = 2
	tool.template_capture_mode = true
	var state = api.get_tool_state()
	for key in ["move_mode", "cut_mode", "active_shape_size_mode", "active_shape_side",
			"active_template_index", "template_capture_mode"]:
		assert_eq(state[key], tool.get(key), key)


func test_parameter_actions_and_type_memory_work_without_ui():
	var sidebar = tool.ui
	tool.ui = null
	tool.set_angle(359.0)
	tool.set_mirror(true)
	tool.adjust_angle_with_wheel(1)
	assert_eq(tool.active_angle, 0.0)
	tool.adjust_angle_with_wheel(-1)
	assert_eq(tool.active_angle, 359.0)
	tool.set_marker_type("Shape")
	tool.set_shape_preset("Square")
	assert_eq(tool.active_shape_sides, 4)
	assert_eq(tool.active_shape_angle, 45.0)
	tool.set_shape_radius(2.0)
	tool.set_shape_size_mode("side")
	assert_almost_eq(tool.active_shape_side, 2.0 * sqrt(2.0), 0.00001)
	tool.set_shape_side(0.1)
	tool.adjust_shape_radius_with_wheel(-1)
	assert_eq(tool.active_shape_side, 0.1)
	tool.set_shape_side(2.0)
	tool.set_shape_angle(358.0)
	tool.adjust_shape_angle_with_wheel(1)
	assert_eq(tool.active_shape_angle, 3.0)
	tool.rotate_shape_45()
	assert_eq(tool.active_shape_angle, 48.0)
	tool.set_marker_type("Path")
	tool.set_path_end_arrow(true)
	tool.set_path_arrow_head_length(23.0)
	tool.set_path_arrow_head_angle(17.0)
	tool.path_placement_active = true
	tool.path_temp_points = [Vector2.ZERO]
	tool.set_marker_type("Fill")
	assert_false(tool.path_placement_active)
	assert_eq(tool.path_temp_points, [])
	tool.set_delete_mode(true)
	assert_eq(tool.active_marker_type, "Line")
	assert_eq(tool.active_angle, 359.0)
	assert_true(tool.active_mirror)
	tool.set_marker_type("Template")
	tool.template_capture_mode = true
	tool.set_marker_type("Shape")
	assert_false(tool.template_capture_mode)
	assert_eq(tool.active_shape_size_mode, "side")
	assert_eq(tool.active_shape_side, 2.0)
	assert_eq(tool.active_shape_angle, 48.0)
	assert_eq(tool.active_shape_sides, 4)
	tool.set_shape_preset("Circle")
	assert_eq(tool.active_shape_size_mode, "radius")
	assert_eq(tool.active_shape_sides, 64)
	tool.set_marker_type("Path")
	assert_true(tool.active_path_end_arrow)
	assert_eq(tool.active_arrow_head_length, 23.0)
	assert_eq(tool.active_arrow_head_angle, 17.0)
	tool.set_marker_type("unsupported")
	assert_eq(tool.active_marker_type, "Path")
	tool.ui = sidebar


func test_shape_intersections_keep_endpoint_tolerance_after_bounds_filter():
	var a = {"shape_type": "poly", "points": [Vector2.ZERO, Vector2(100000, 0)]}
	var near = {"shape_type": "poly", "points": [Vector2(100000.05, -10), Vector2(100000.05, 10)]}
	var far = {"shape_type": "poly", "points": [Vector2(200000, -10), Vector2(200000, 10)]}
	assert_true(tool._shapes_intersect(a, near))
	assert_false(tool._shapes_intersect(a, far))
	assert_false(tool._shapes_intersect({"shape_type": "poly", "points": []}, near))


func test_type_setting_restoration_retains_legacy_missing_field_defaults():
	tool.type_settings["Shape"] = {"radius": 3.0}
	tool.load_type_settings("Shape")
	assert_eq(tool.active_shape_radius, 3.0)
	assert_eq(tool.active_shape_sides, 6)
	assert_eq(tool.active_shape_angle, 0.0)
	assert_eq(tool.active_shape_size_mode, "radius")
	assert_eq(tool.active_shape_side, 1.0)
	tool.type_settings["Path"] = {"end_arrow": true}
	tool.load_type_settings("Path")
	assert_true(tool.active_path_end_arrow)
	assert_eq(tool.active_arrow_head_length, 50.0)
	assert_eq(tool.active_arrow_head_angle, 30.0)


func test_placement_coordinate_alias_precedence_and_absence():
	for flags in [{}, {"show_coordinates": true}, {"coordinates": false, "show_coordinates": true}]:
		var data = {"id": 1, "position": Vector2.ZERO, "marker_type": "Line", "color": Color.blue}
		for key in flags:
			data[key] = flags[key]
		tool._do_place_marker(data)
		assert_eq(tool.markers_lookup[1].show_coordinates,
			flags.get("coordinates", flags.get("show_coordinates", false)))
		tool._undo_place_marker(1)


func test_new_placement_records_use_line_only_canonical_coordinate_flag():
	tool.show_coordinates = true
	for kind in ["Line", "Shape", "Path"]:
		tool.set_marker_type(kind)
		tool.place_marker(Vector2.ZERO)
		if kind == "Path":
			tool.place_marker(Vector2(100, 0))
			tool._finalize_path_marker(false)
		assert_false(last_record.marker_data.has("coordinates"))
		assert_eq(last_record.marker_data.has("show_coordinates"), kind == "Line")
		assert_eq(tool.markers.back().show_coordinates, kind == "Line")
	var id = api.place_line_marker(Vector2(0, 200))
	assert_true(last_record.marker_data.show_coordinates)
	assert_true(tool.markers_lookup[id].show_coordinates)
	for other_id in [api.place_shape_marker(Vector2(200, 200)), api.place_path_marker([Vector2(300, 0), Vector2(300, 100)])]:
		assert_false(tool.markers_lookup[other_id].show_coordinates)
	assert_false(last_record.marker_data.has("show_coordinates"))
	assert_false(last_record.marker_data.has("coordinates"))


func test_move_mode_exits_fill_and_preserves_line_settings():
	tool.set_angle(37.0)
	tool.set_marker_type("Fill")
	tool.set_move_mode(true)
	assert_eq(tool.active_marker_type, "Line")
	assert_eq(tool.active_angle, 37.0)
	assert_true(tool.move_mode)
	tool.set_move_mode(false)
	assert_false(tool.move_mode)
	assert_eq(tool.active_marker_type, "Line")


func test_virtual_descriptors_match_model_without_instantiating_markers():
	var marker = tool.GuideMarkerClass.new(Vector2(30, 40))
	marker.marker_type = "Shape"
	marker.shape_radius = 3.0
	marker.shape_sides = 5
	marker.shape_angle = -90.0
	var expected = tool._get_shape_descriptor(marker, tool._get_grid_cell_size())
	var data = {"position": marker.position, "shape_radius": 3.0, "shape_sides": 5, "shape_angle": -90.0}
	tool.GuideMarkerClass = null
	assert_eq_deep(tool._get_shape_descriptor_from_marker_data(data), expected)
	data["shape_primitives"] = []
	assert_eq_deep(tool._get_shape_descriptor_from_marker_data(data), {})
	data.erase("shape_primitives")
	data.erase("shape_sides")
	assert_eq_deep(tool._get_shape_descriptor_from_marker_data(data), {})
	tool.active_shape_radius = 3.0
	tool.active_shape_sides = 5
	tool.active_shape_angle = -90.0
	assert_eq_deep(tool._build_shape_descriptor_at(marker.position), expected)
	tool.templates = [{"data": {"marker_type": "Shape", "shape_radius": 3.0, "shape_sides": 5, "shape_angle": -90.0}}]
	tool.active_template_index = 0
	assert_eq_deep(tool._build_shape_descriptor_from_template(marker.position), expected)


class DiagnosticLogger:
	extends Reference
	var errors = []
	func error(message):
		errors.append(message)


func test_capture_protocol_and_missing_descriptor_radius_report_errors():
	var logger = DiagnosticLogger.new()
	api.LOGGER = logger
	assert_eq_deep(api.end_history_capture(), [])
	assert_eq(logger.errors.size(), 1)
	assert_true(api.begin_history_capture())
	assert_false(api.begin_history_capture())
	assert_eq(logger.errors.size(), 2)
	api.end_history_capture()
	api.LOGGER = null # Teardown uses normal lifecycle logging.
	tool.LOGGER = logger
	var data = shape_data(1)
	data.erase("shape_radius")
	tool.active_shape_radius = 123.0
	assert_eq_deep(tool._get_shape_descriptor_from_marker_data(data), {})
	assert_eq(logger.errors.size(), 3)
	assert_true("shape_radius" in logger.errors.back())
	tool.LOGGER = null


func test_corrupt_parametric_templates_cannot_bypass_descriptor_validation():
	var logger = DiagnosticLogger.new()
	tool.LOGGER = logger
	var valid = {"marker_type": "Shape", "shape_radius": 3.0, "shape_sides": 5, "shape_angle": 0.0}
	tool.active_template_index = 0
	for field in ["shape_radius", "shape_sides", "shape_angle"]:
		var data = valid.duplicate()
		data.erase(field)
		tool.templates = [{"data": data}]
		assert_eq_deep(tool._build_shape_descriptor_from_template(Vector2.ZERO), {})
		var count = tool.markers.size()
		tool._place_template_marker(Vector2.ZERO)
		assert_eq(tool.markers.size(), count)
	assert_eq(logger.errors.size(), 6)
	for value in [null, "bad", Vector2(INF, 0)]:
		var data = shape_data(1)
		data.position = value
		assert_eq_deep(tool._get_shape_descriptor_from_marker_data(data), {})
	tool.LOGGER = null


class PlacementModeObserver:
	extends Reference
	var tool
	var seen = []
	func update_ui():
		seen.append([tool.conforming_mode, tool.wrapping_mode])


func test_explicit_placement_and_replay_never_expose_temporary_ui_modes():
	var original_ui = tool.ui
	var observer = PlacementModeObserver.new()
	observer.tool = tool
	tool.ui = observer
	tool.conforming_mode = true
	tool.wrapping_mode = true
	for method in ["place_shape_marker_plain", "place_shape_conforming", "place_shape_wrapping"]:
		api.call(method, Vector2.ZERO, 2.0, 45.0, 4)
		assert_eq_deep(observer.seen.back(), [true, true])
		last_record.undo()
		last_record.redo()
		assert_eq_deep(observer.seen.back(), [true, true])
	assert_eq(observer.seen.size(), 9, "Placement, undo and redo each refresh UI")
	tool.ui = original_ui
	observer.tool = null


func test_shape_state_is_narrow_current_and_independent_and_preview_reuses_storage():
	var state = api.get_shape_state()
	var full = api.get_tool_state()
	assert_eq(state.size(), 7)
	for key in state:
		if state[key] is Dictionary:
			assert_eq_deep(state[key], full[key])
		else:
			assert_eq(state[key], full[key])
	state.active_shape_spiral.outer_radius = 999
	assert_eq(api.get_shape_state().active_shape_spiral.outer_radius, 6.0)
	state.active_shape_angle = 999
	tool.active_shape_angle = 37.0
	assert_eq(api.get_shape_state().active_shape_angle, 37.0)
	var preview = tool._api_preview
	api.set_shape_preview(Vector2(10, 20), 2, 30, 4, Color.red)
	assert_eq(preview.pos, Vector2(10, 20))
	api.set_shape_preview(Vector2(30, 40), 3, 50, 5, Color.blue)
	assert_eq_deep(preview, {"pos": Vector2(30, 40), "radius": 3.0, "angle": 50.0, "sides": 5, "color": Color.blue})
	api.clear_shape_preview()
	assert_true(preview.empty())
