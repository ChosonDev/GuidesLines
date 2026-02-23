extends Reference

# GuidesLinesHistory - Undo/Redo history record classes for GuidesLinesTool
#
# Usage in GuidesLinesTool:
#   const GuidesLinesHistory = preload("GuidesLinesHistory.gd")
#   _record_history(GuidesLinesHistory.PlaceMarkerRecord.new(self, marker_data, clip_snaps))

# ============================================================================
# HISTORY RECORDS FOR UNDO/REDO SUPPORT
# ============================================================================

# History record for placing a marker.
# clip_snapshots stores the primitives of every marker that was modified as a
# side-effect of this placement (conforming mode).
# undo() removes the placed marker AND restores those modified markers.
class PlaceMarkerRecord:
	var tool
	var marker_data
	# { marker_id: {"primitives": [...]} }
	var clip_snapshots = {}

	func _init(tool_ref, data, p_clip_snapshots = {}):
		tool = tool_ref
		marker_data = data
		clip_snapshots = p_clip_snapshots
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerRecord created for id: %d" % [data["id"]])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerRecord.redo() called for id: %d" % [marker_data["id"]])
		# Re-snapshot before redo so that the NEXT undo can restore correctly.
		if tool.conforming_mode:
			clip_snapshots = tool._snapshot_potential_clip_targets(marker_data["position"])
		tool._do_place_marker(marker_data)

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerRecord.undo() called for id: %d" % [marker_data["id"]])
		tool._undo_place_marker(marker_data["id"])
		# Restore the primitives of every marker that was clipped by this placement.
		for cid in clip_snapshots:
			if tool.markers_lookup.has(cid):
				tool.markers_lookup[cid].set_primitives(
					clip_snapshots[cid]["primitives"].duplicate(true))
		if tool.overlay:
			tool.overlay.update()

	func record_type():
		return "GuidesLines.PlaceMarker"


# History record for deleting a single marker.
class DeleteMarkerRecord:
	var tool
	var marker_data
	var marker_index

	func _init(tool_ref, data, index):
		tool = tool_ref
		marker_data = data
		marker_index = index
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteMarkerRecord created for id: %d at index: %d" % [data["id"], index])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteMarkerRecord.redo() called for id: %d" % [marker_data["id"]])
		tool._do_delete_marker(marker_index)

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteMarkerRecord.undo() called for id: %d" % [marker_data["id"]])
		tool._undo_delete_marker(marker_data, marker_index)

	func record_type():
		return "GuidesLines.DeleteMarker"


# History record for deleting all markers.
class DeleteAllMarkersRecord:
	var tool
	var saved_markers

	func _init(tool_ref, markers_data):
		tool = tool_ref
		saved_markers = markers_data

	func redo():
		tool._do_delete_all()

	func undo():
		tool._undo_delete_all(saved_markers)

	func record_type():
		return "GuidesLines.DeleteAll"


# History record for applying a Difference operation.
# Uses snapshots to undo, because there is no "diff marker" that could be removed.
class DifferenceRecord:
	var tool
	var diff_desc   # in-memory Dictionary (has Vector2 values)
	# { marker_id: {"primitives":[...]} }
	var snapshots

	func _init(tool_ref, p_desc, p_snapshots):
		tool = tool_ref
		diff_desc = p_desc
		snapshots = p_snapshots

	func redo():
		tool._do_apply_difference(diff_desc)

	func undo():
		for id in snapshots:
			if tool.markers_lookup.has(id):
				tool.markers_lookup[id].set_primitives(
					snapshots[id]["primitives"].duplicate(true))
		if tool.overlay:
			tool.overlay.update()

	func record_type():
		return "GuidesLines.Difference"


# History record for a Merge operation.
# Merge does NOT create a new marker — instead existing Shape markers that overlap
# the placed shape have their primitives and position updated.
# undo() restores each affected marker to its pre-merge state.
# redo() re-applies _do_apply_merge() with the stored descriptor + center.
class MergeShapeRecord:
	var tool
	var merge_desc   # { shape_type, points } descriptor of the virtual new shape
	var new_pos      # Vector2 — center of the placed (virtual) shape
	# { marker_id: { "primitives": [...], "position": Vector2 } }
	var snapshots

	func _init(tool_ref, p_desc, p_pos, p_snapshots):
		tool = tool_ref
		merge_desc = p_desc
		new_pos = p_pos
		snapshots = p_snapshots
		if tool.LOGGER:
			tool.LOGGER.debug("MergeShapeRecord created at %s" % [str(p_pos)])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("MergeShapeRecord.redo() called")
		tool._do_apply_merge(merge_desc, new_pos)

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("MergeShapeRecord.undo() called — restoring %d markers" % [snapshots.size()])
		for id in snapshots:
			if tool.markers_lookup.has(id):
				var m = tool.markers_lookup[id]
				m.set_primitives(snapshots[id]["primitives"].duplicate(true))
				m.position = snapshots[id]["position"]
		if tool.overlay:
			tool.overlay.update()

	func record_type():
		return "GuidesLines.MergeShape"


# ============================================================================
# HISTORY RECORDS FOR FILL MODE
# ============================================================================

# History record for placing a single fill region.
# undo() removes the fill; redo() re-adds it.
class PlaceFillRecord:
	var tool
	var fill_data: Dictionary  # Serialised FillMarker (from FillMarker.Save())

	func _init(tool_ref, data: Dictionary):
		tool = tool_ref
		fill_data = data
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceFillRecord created for fill id: %d" % [data["id"]])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceFillRecord.redo() for fill id: %d" % [fill_data["id"]])
		tool._do_place_fill(fill_data)

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceFillRecord.undo() for fill id: %d" % [fill_data["id"]])
		tool._undo_place_fill(fill_data["id"])

	func record_type():
		return "GuidesLines.PlaceFill"


# History record for deleting all fill regions at once.
# undo() restores every previously deleted fill; redo() deletes them all again.
class DeleteAllFillsRecord:
	var tool
	var saved_fills: Array  # Array of serialised FillMarker dicts

	func _init(tool_ref, fills_data: Array):
		tool = tool_ref
		saved_fills = fills_data
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteAllFillsRecord created (%d fills saved)" % [fills_data.size()])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteAllFillsRecord.redo() — deleting all fills")
		tool._do_delete_all_fills()

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteAllFillsRecord.undo() — restoring %d fills" % [saved_fills.size()])
		tool._undo_delete_all_fills(saved_fills)

	func record_type():
		return "GuidesLines.DeleteAllFills"
