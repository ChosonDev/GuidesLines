extends Reference

# Derived boolean zones, owned by a map. No marker IDs, nodes or history are created.
const CLASS_NAME = "GuidesLinesRegions"
const Persistence = preload("GuidesLinesPersistence.gd")
const DATA_VERSION = 5 # Bump when cached boolean semantics change.
const MAX_ZONES = 128
const MAX_VERTICES = 131072
var _regions = []
var _markers = {}
var _shape_entries = []
var _revision = -1
var _grid = null
var _pending = {}

func clear() -> void:
	_regions.clear()
	_markers.clear()
	_shape_entries.clear()
	_revision = -1
	_grid = null
	_pending = {}

func _pairs(points) -> Array:
	var result = []
	for point in points: result.append([point.x, point.y])
	return result

## Reconcile only after a mutation. Exact runtime hashes detect even sub-JSON-precision edits.
func _sync(source_tool) -> bool:
	var grid = source_tool._get_grid_cell_size()
	if grid == null:
		return false
	if _revision == source_tool.geometry_revision and _grid == grid:
		return true
	if _grid != null and _grid != grid:
		_regions.clear()
	var current = {}
	for marker in source_tool.markers:
		if marker.marker_type != "Shape": continue
		marker.get_draw_data(null, grid)
		var points = marker.get_polygon()
		var bounds = marker.get_geometry_bounds(null, grid)
		if points.empty() or bounds == null: continue
		if _markers.has(marker.id) and _markers[marker.id].points == points:
			_markers[marker.id].marker = marker
			current[marker.id] = _markers[marker.id]
			continue
		current[marker.id] = {"points": points.duplicate(), "pool": PoolVector2Array(points), "bounds": bounds, "marker": marker,
			"hash": var2bytes(points).hex_encode().sha256_text(), "contours": source_tool.GeometryUtils.normalized_contours(marker.get_primitives())}
	var changed = []
	for id in _markers:
		if not current.has(id) or current[id].hash != _markers[id].hash:
			changed.append(_markers[id].bounds)
	for id in current:
		if not _markers.has(id) or current[id].hash != _markers[id].hash:
			changed.append(current[id].bounds)
	for i in range(_regions.size() - 1, -1, -1):
		for bounds in changed:
			if _regions[i].bounds.intersects(bounds, true):
				_regions.remove(i)
				break
	_markers = current
	_shape_entries = []
	for record in _markers.values():
		_shape_entries.append({"marker": record.marker, "desc": {"shape_type": "poly", "points": record.points}, "bounds": record.bounds, "pool": record.pool, "contours": record.contours})
	_revision = source_tool.geometry_revision
	_grid = grid
	if not _pending.empty():
		_restore()
	return true

## One synchronized snapshot feeds hit testing and boolean candidate selection.
func shape_entries(source_tool) -> Array:
	if not _sync(source_tool): return []
	return _shape_entries # Internal read-only snapshot, rebuilt only after a revision.

func _influence(ids: Array):
	var bounds = null
	for id in ids:
		if not _markers.has(id): return null
		bounds = _markers[id].bounds if bounds == null else bounds.merge(_markers[id].bounds)
	return bounds

func _dependencies(bounds: Rect2) -> Dictionary:
	var result = {}
	for id in _markers:
		if bounds.intersects(_markers[id].bounds, true):
			if not _markers[id].has("save_hash"):
				_markers[id].save_hash = JSON.print(_pairs(_markers[id].points)).sha256_text()
			result[str(id)] = _markers[id].save_hash
	return result

## Includes subtracting/container markers, not just the containing markers in marker_ids.
func resolve(source_tool, coords: Vector2, hits: Array, quiet: bool = true, fresh: bool = false):
	if hits.empty() or not _sync(source_tool): return null
	var ids = []
	for hit in hits: ids.append(hit.marker.id)
	var bounds = _influence(ids)
	if bounds == null: return null
	if not fresh:
		for i in range(_regions.size() - 1, -1, -1):
			var entry = _regions[i]
			if entry.value.fill.marker_ids == ids and Geometry.is_point_in_polygon(coords, entry.pool):
				_regions.remove(i)
				_regions.append(entry)
				return entry.value
	var polygon = source_tool._fill_handler._compute_fill_polygon(coords, hits, quiet)
	if polygon.empty(): return null
	var sources = []
	for hit in hits: sources.append(hit.desc.points.duplicate())
	var fill = {"polygon": polygon, "marker_ids": ids, "fill_type": "exclusive" if ids.size() == 1 else "intersection", "source_polygons": sources}
	var dependencies = _dependencies(bounds)
	var zone_hash = var2bytes([ids, polygon, dependencies]).hex_encode().sha256_text()
	var value = {"zone_hash": zone_hash, "kind": "Fill", "fill": fill}
	# A click replaces the visited component even if JSON rounding changed its hash.
	if fresh:
		for i in range(_regions.size() - 1, -1, -1):
			if _regions[i].value.fill.marker_ids == ids and Geometry.is_point_in_polygon(coords, _regions[i].pool):
				_regions.remove(i)
	_store({"value": value, "bounds": bounds, "dependencies": dependencies})
	return value

func _store(entry: Dictionary) -> void:
	entry.pool = PoolVector2Array(entry.value.fill.polygon)
	for i in range(_regions.size() - 1, -1, -1):
		if _regions[i].value.zone_hash == entry.value.zone_hash: _regions.remove(i)
	_regions.append(entry)
	var count = 0
	for region in _regions: count += region.value.fill.polygon.size()
	# ponytail: bounded LRU cache; retain one oversized target to avoid clipping it on every move.
	while _regions.size() > MAX_ZONES or (count > MAX_VERTICES and _regions.size() > 1):
		count -= _regions.pop_front().value.fill.polygon.size()

func save_data(source_tool) -> Dictionary:
	if _regions.empty() and _pending.empty():
		return {"version": DATA_VERSION, "grid": null, "zones": []}
	if not _sync(source_tool):
		return _pending.duplicate(true) if not _pending.empty() else {"version": DATA_VERSION, "grid": null, "zones": []}
	var saved = {"version": DATA_VERSION, "grid": [float(_grid), float(_grid)] if not _grid is Vector2 else [_grid.x, _grid.y], "zones": []}
	for entry in _regions:
		if entry.value.fill.polygon.size() > MAX_VERTICES: continue
		var polygon = _pairs(entry.value.fill.polygon)
		saved.zones.append({"polygon": polygon, "marker_ids": entry.value.fill.marker_ids.duplicate(),
			"dependencies": entry.dependencies.duplicate(), "zone_hash": entry.value.zone_hash,
			"geometry_hash": JSON.print(polygon).sha256_text()})
	return saved

## Optional derived data is discarded on error, never the user's authoritative markers.
func load_data(data) -> void:
	if not data is Dictionary or data.get("version") != DATA_VERSION or not data.get("zones") is Array or data.zones.size() > MAX_ZONES:
		return
	if not Persistence._point(data.get("grid")): return
	var count = 0
	for zone in data.zones:
		if not zone is Dictionary or not zone.get("polygon") is Array: return
		count += zone.polygon.size()
		if count > MAX_VERTICES: return
	_pending = data.duplicate(true)
	_revision = -1

func _restore() -> void:
	var saved = _pending
	_pending = {}
	var grid = Vector2(saved.grid[0], saved.grid[1])
	if grid != (Vector2.ONE * _grid if not _grid is Vector2 else _grid): return
	for row in saved.zones:
		if not row.get("marker_ids") is Array or row.marker_ids.empty() or row.marker_ids.size() > _markers.size(): continue
		var ids = []
		for id in row.marker_ids:
			if not Persistence._id(id) or not _markers.has(int(id)) or ids.has(int(id)): break
			ids.append(int(id))
		if ids.size() != row.marker_ids.size(): continue
		var bounds = _influence(ids)
		if bounds == null: continue
		var dependencies = _dependencies(bounds)
		if not row.get("dependencies") is Dictionary or row.dependencies.size() != dependencies.size(): continue
		var valid = true
		for id in dependencies:
			if row.dependencies.get(id) != dependencies[id]: valid = false
		if not valid or not row.get("zone_hash") is String or row.zone_hash.length() != 64: continue
		if row.polygon.size() < 3 or row.get("geometry_hash") != JSON.print(row.polygon).sha256_text(): continue
		var polygon = []
		for pair in row.polygon:
			if not Persistence._point(pair): break
			polygon.append(Vector2(pair[0], pair[1]))
		if polygon.size() != row.polygon.size(): continue
		var sources = []
		for id in ids: sources.append(_markers[id].points.duplicate())
		var fill = {"polygon": polygon, "marker_ids": ids, "fill_type": "exclusive" if ids.size() == 1 else "intersection", "source_polygons": sources}
		_store({"bounds": bounds, "dependencies": dependencies, "value": {"kind": "Fill", "zone_hash": row.zone_hash, "fill": fill}})
