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
# clip_snapshots stores the primitives of every marker that was clipped as a
# side-effect of this placement (auto_clip / cut modes).
# undo() removes the placed marker AND restores those clipped markers.
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
		if tool.auto_clip_shapes or tool.cut_existing_shapes:
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
