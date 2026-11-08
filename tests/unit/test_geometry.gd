extends "res://addons/gut/test.gd"

# Tests the original mod script in an autonomous Godot CLI environment.
# An absolute path derived from this test root avoids res:// parent clamping.
var geometry = load(ProjectSettings.globalize_path("res://").plus_file("../scripts/utils/GeometryUtils.gd").simplify_path())

func test_spiral_spatial_buckets_match_exhaustive_clearance():
	for turns in [0.5, 1.25, 2.0, 4.0, 6.0]:
		for ratio in [0.5, 0.97, 0.999]:
			var settings = geometry.SPIRAL_DEFAULTS.duplicate()
			settings.inner_radius = 3.0
			settings.outer_radius = 8.0
			settings.turns = turns
			settings.width = 5.0 / turns * ratio
			settings.angle = -73.0
			settings.clockwise = ratio < 0.9
			if geometry.spiral_error(settings, true) != "": continue
			var points = geometry.build_spiral(settings).points
			var separation = max(2, int(ceil(PI / (TAU * turns) * (points.size() - 1))))
			var overlap = false
			for i in range(points.size() - 1):
				if overlap: break
				for j in range(i + separation, points.size() - 1):
					var a = points[i]
					var b = points[i + 1]
					var c = points[j]
					var d = points[j + 1]
					var distance = min(min(a.distance_to(geometry.closest_point_on_segment(a, c, d)),
						b.distance_to(geometry.closest_point_on_segment(b, c, d))),
						min(c.distance_to(geometry.closest_point_on_segment(c, a, b)),
						d.distance_to(geometry.closest_point_on_segment(d, a, b))))
					if distance <= settings.width + 0.001 or geometry.segment_segment_intersect(a, b, c, d) != null:
						overlap = true
						break
			assert_eq(geometry.build_spiral(settings, true).error != "", overlap,
				"Broad phase must preserve exact clearance: turns=%s ratio=%s" % [turns, ratio])

func test_spiral_fractional_turns_radii_direction_rotation_and_reverse():
	var settings = geometry.SPIRAL_DEFAULTS.duplicate(true)
	settings.turns = 1.25
	var result = geometry.build_spiral(settings)
	assert_eq(result.error, "")
	var points = result.points
	assert_almost_eq(points[0], Vector2(1, 0), Vector2.ONE * 0.0001)
	assert_almost_eq(points.back(), Vector2(0, 6), Vector2.ONE * 0.0001)
	assert_true(points[1].y > 0, "Positive screen Y winds clockwise")
	for i in range(points.size()):
		assert_almost_eq(points[i].length(), 1.0 + 5.0 * i / (points.size() - 1), 0.0001)
	settings.clockwise = false
	settings.angle = 90.0
	var reflected = geometry.build_spiral(settings).points
	for i in range(points.size()):
		assert_almost_eq(reflected[i], Vector2(points[i].x, -points[i].y).rotated(PI / 2), Vector2.ONE * 0.0001)
	settings.reverse = true
	reflected.invert()
	assert_eq_deep(geometry.build_spiral(settings).points, reflected)
	settings.inner_radius = 0
	assert_eq(geometry.build_spiral(settings).error, "", "Open paths can start at the center")

func test_spiral_shape_is_simple_closed_strip_with_butt_caps_and_empty_center():
	var settings = geometry.SPIRAL_DEFAULTS.duplicate(true)
	var line = geometry.build_spiral(settings).points
	var result = geometry.build_spiral(settings, true)
	assert_eq(result.error, "")
	var points = result.points
	assert_true(points.size() > line.size())
	assert_false(Geometry.is_point_in_polygon(Vector2.ZERO, PoolVector2Array(points)))
	assert_true(Geometry.is_point_in_polygon(line[int(line.size() / 2)], PoolVector2Array(points)))
	assert_true(Geometry.triangulate_polygon(PoolVector2Array(points)).size() > 0)
	var area = 0.0
	var crossing = false
	for i in range(points.size()):
		var a = points[i]
		var b = points[(i + 1) % points.size()]
		area += a.cross(b) * 0.5
		for j in range(i + 2, points.size()):
			if i == 0 and j == points.size() - 1: continue
			if geometry.segment_segment_intersect(a, b, points[j], points[(j + 1) % points.size()]) != null:
				crossing = true
	assert_false(crossing, "Non-neighboring edges must not cross")
	var length = 0.0
	for i in range(line.size() - 1): length += line[i].distance_to(line[i + 1])
	assert_almost_eq(abs(area), length * settings.width, length * 0.01)
	settings.clockwise = false
	assert_eq(geometry.build_spiral(settings, true).error, "")

func test_spiral_rejects_invalid_unbounded_and_overlapping_geometry():
	for overrides in [{"turns": 0}, {"turns": -1}, {"turns": 9}, {"outer_radius": 1},
		{"outer_radius": INF}, {"angle": NAN}, {"inner_radius": -1}, {"width": NAN},
		{"clockwise": 1}, {"reverse": "false"}, {"size_by": "side"}, {"turns": "2"}]:
		var settings = geometry.SPIRAL_DEFAULTS.duplicate(true)
		for key in overrides: settings[key] = overrides[key]
		var result = geometry.build_spiral(settings)
		assert_ne(result.error, "")
		assert_true(result.points.empty())
	for overrides in [{"width": 0}, {"width": 2.5}, {"inner_radius": 0}, {"outer_radius": 1000, "turns": 8}]:
		var settings = geometry.SPIRAL_DEFAULTS.duplicate(true)
		for key in overrides: settings[key] = overrides[key]
		assert_ne(geometry.build_spiral(settings, true).error, "")
	var tight = geometry.SPIRAL_DEFAULTS.duplicate(true)
	tight.inner_radius = 3.0
	tight.outer_radius = 8.0
	tight.width = 2.49
	assert_eq(geometry.spiral_error(tight, true), "", "Radial spacing alone is insufficient")
	assert_ne(geometry.build_spiral(tight, true).error, "", "Actual normal clearance rejects overlapping turns")
	assert_ne(geometry.build_spiral(null).error, "")


func test_square_vertices_use_world_coordinates_and_radians():
	var points = geometry.calculate_polygon_vertices(Vector2(10, 20), 2.0, 4, PI / 2.0)
	var expected = [Vector2(10, 22), Vector2(8, 20), Vector2(10, 18), Vector2(12, 20)]
	assert_eq(points.size(), expected.size())
	for i in range(min(points.size(), expected.size())):
		assert_almost_eq(points[i], expected[i], Vector2(0.0001, 0.0001))


func test_side_and_circumradius_match_a_square():
	assert_almost_eq(geometry.side_to_circumradius(2.0, 4), sqrt(2.0), 0.0001)
	assert_almost_eq(geometry.circumradius_to_side(sqrt(2.0), 4), 2.0, 0.0001)


func test_closest_point_clamps_to_segment_and_handles_zero_length():
	assert_eq(geometry.closest_point_on_segment(Vector2(5, 3), Vector2.ZERO, Vector2(10, 0)), Vector2(5, 0))
	assert_eq(geometry.closest_point_on_segment(Vector2(-2, 3), Vector2.ZERO, Vector2(10, 0)), Vector2.ZERO)
	assert_eq(geometry.closest_point_on_segment(Vector2(12, 3), Vector2.ZERO, Vector2(10, 0)), Vector2(10, 0))
	assert_eq(geometry.closest_point_on_segment(Vector2(8, 9), Vector2(2, 3), Vector2(2, 3)), Vector2(2, 3))


func test_segment_intersection_accepts_crossing_and_shared_endpoint():
	assert_eq(geometry.segment_segment_intersect(Vector2.ZERO, Vector2(10, 10), Vector2(0, 10), Vector2(10, 0)), Vector2(5, 5))
	assert_eq(geometry.segment_segment_intersect(Vector2.ZERO, Vector2(10, 0), Vector2(10, 0), Vector2(10, 10)), Vector2(10, 0))


func test_segment_intersection_rejects_parallel_and_outside_segments():
	assert_null(geometry.segment_segment_intersect(Vector2.ZERO, Vector2(10, 0), Vector2(0, 2), Vector2(10, 2)))
	assert_null(geometry.segment_segment_intersect(Vector2.ZERO, Vector2(1, 0), Vector2(2, -1), Vector2(2, 1)))




func test_segment_clipping_distinguishes_crossing_and_parallel_miss():
	var bounds = Rect2(0, 0, 10, 10)
	assert_eq(geometry.clip_line_segment_to_rect(Vector2(-5, 5), Vector2(15, 5), bounds), [Vector2(0, 5), Vector2(10, 5)])
	assert_eq(geometry.clip_line_segment_to_rect(Vector2(-5, -1), Vector2(15, -1), bounds), [])




func test_polygon_segments_close_the_last_edge():
	var points = [Vector2.ZERO, Vector2(10, 0), Vector2(0, 10)]
	var segments = geometry.points_to_segs(points)
	assert_eq(segments.size(), 3)
	assert_eq_deep(segments[2], {"type": "seg", "a": Vector2(0, 10), "b": Vector2.ZERO})
	assert_eq(geometry.points_to_segs([]), [])


func test_chaining_reversed_unordered_edges_preserves_square():
	var segments = [
		{"type": "seg", "a": Vector2(10, 0), "b": Vector2(10, 10)},
		{"type": "seg", "a": Vector2.ZERO, "b": Vector2(0, 10)},
		{"type": "seg", "a": Vector2.ZERO, "b": Vector2(10, 0)},
		{"type": "seg", "a": Vector2(0, 10), "b": Vector2(10, 10)},
	]
	var polygon = geometry.chain_segments_to_polygon(segments)
	assert_eq(polygon.size(), 4)
	for point in [Vector2.ZERO, Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]:
		assert_has(polygon, point)


func test_cut_chains_extend_backward_without_joining_disconnected_edges():
	var segments = [
		{"type": "seg", "a": Vector2(10, 0), "b": Vector2(20, 0)},
		{"type": "seg", "a": Vector2.ZERO, "b": Vector2(10, 0)},
		{"type": "seg", "a": Vector2(100, 0), "b": Vector2(110, 0)},
	]
	var chains = geometry.split_segments_into_chains(segments)
	assert_eq(chains.size(), 2)
	assert_has(chains, [Vector2.ZERO, Vector2(10, 0), Vector2(20, 0)])
	assert_has(chains, [Vector2(100, 0), Vector2(110, 0)])
	assert_eq(geometry.split_segments_into_chains([]), [])


func test_merge_keeps_containing_outline_and_rejects_separate_shapes():
	var outer = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	var inner = [Vector2(10, 10), Vector2(20, 10), Vector2(20, 20), Vector2(10, 20)]
	var merged = geometry.chain_segments_to_polygon(geometry.merge_polygons_outline(outer, inner))
	assert_eq(merged.size(), 4)
	for point in outer:
		assert_has(merged, point)
	var separate = [Vector2(200, 200), Vector2(210, 200), Vector2(210, 210)]
	assert_eq(geometry.merge_polygons_outline(outer, separate), [])
