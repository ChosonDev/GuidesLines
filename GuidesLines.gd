# GuidesLines - Dungeondraft Mod
# Advanced guide lines system with placeable markers with multi-type support
#
# File Structure:
#   - GuidesLines.gd: Main mod file (this file)
#   - scripts/GuideMarker.gd: Placeable marker with guide lines (multi-type support)
#   - scripts/GuidesLinesTool.gd: Tool for placing and managing markers
#   - scripts/CrossOverlay.gd: Proximity-based guide overlay
#   - scripts/PermanentOverlay.gd: Permanent guide overlay

var script_class = "tool"

const CLASS_NAME = "GuidesLines"

# ============================================================================
# _LIB API
# ============================================================================

var LOGGER = null  # Logger API instance

# ============================================================================
# ICON PATHS
# ============================================================================

const TOOL_ICON_PATH = "icons/guides_lines_icon.png"

# ============================================================================
# EXTERNAL CLASSES
# ============================================================================

var GuideMarkerClass = null
var GuidesLinesToolClass = null
var MarkerOverlayClass = null
var CrossOverlay = null
var PermanentOverlay = null

# ============================================================================
# CONFIGURATION
# ============================================================================

# Cross guides (proximity-based) - from v1
const DETECTION_DISTANCE = 70.0
const HYSTERESIS = 30.0
const CROSS_LINE_COLOR = Color(1, 0, 0, 0.8)  # Red
const CROSS_LINE_WIDTH = 10.0

# Permanent guides - from v1
const PERM_LINE_COLOR = Color(0, 0.7, 1, 0.6)  # Blue
const PERM_LINE_WIDTH = 10.0

# ============================================================================
# STATE
# ============================================================================

# Tool and UI
var guides_tool = null
var tool_panel = null
var tool_created = false  # Flag to prevent multiple creation attempts

# Proximity and permanent guide overlays (optional features)
var cross_overlay = null
var perm_overlay = null

# Cached custom_snap mod reference (checked once after map load)
var cached_snappy_mod = null
var snappy_mod_checked = false  # Flag to check snappy_mod only once

# Proximity and permanent guide settings
var cross_guides_enabled = true  # Enabled by default
var perm_vertical_enabled = false
var perm_horizontal_enabled = false
var show_coordinates_enabled = false  # Show grid coordinates

# Cross guides state
var cross_show_v = false
var cross_show_h = false

# ============================================================================
# LIFECYCLE
# ============================================================================

# Initialize the mod and register with systems
# Called when Dungeondraft loads the mod
func start():
	# Register with _Lib to get API access
	if Engine.has_signal("_lib_register_mod"):
		Engine.emit_signal("_lib_register_mod", self)
		
		# Initialize Logger after registration (use self.Global.API)
		if self.Global.API and self.Global.API.has("Logger"):
			LOGGER = self.Global.API.Logger.for_class(CLASS_NAME)
			
			LOGGER.info("Mod starting - version 1.0.10")
			LOGGER.debug("Registered with _Lib successfully")
			
			# Register UpdateChecker for automatic update notifications
			if self.Global.API.has("UpdateChecker"):
				LOGGER.debug("UpdateChecker available, registering...")
				var update_checker = self.Global.API.UpdateChecker
				var agent = update_checker.builder()\
					.fetcher(update_checker.github_fetcher("ChosonDev", "GuidesLines"))\
					.downloader(update_checker.github_downloader("ChosonDev", "GuidesLines"))\
					.build()
				update_checker.register(agent)
				LOGGER.debug("UpdateChecker registered for automatic updates")
			else:
				LOGGER.info("UpdateChecker not available")
		else:
			print("GuidesLines: _Lib registered but Logger not available")
	else:
		print("GuidesLines: _Lib not found (API features will be unavailable)")
	
	if LOGGER:
		LOGGER.debug("Starting to load classes...")
	
	# Verify self.Global.Root exists
	if not self.Global or not self.Global.has("Root"):
		print("GuidesLines: ERROR - self.Global.Root not available!")
		return
	
	# Load classes (without cache flag to avoid potential issues)
	GuideMarkerClass = ResourceLoader.load(self.Global.Root + "scripts/GuideMarker.gd", "GDScript", false)
	if not GuideMarkerClass:
		print("GuidesLines: ERROR - Failed to load GuideMarker.gd")
		return
	
	GuidesLinesToolClass = ResourceLoader.load(self.Global.Root + "scripts/GuidesLinesTool.gd", "GDScript", false)
	if not GuidesLinesToolClass:
		print("GuidesLines: ERROR - Failed to load GuidesLinesTool.gd")
		return
	
	MarkerOverlayClass = ResourceLoader.load(self.Global.Root + "scripts/MarkerOverlay.gd", "GDScript", false)
	if not MarkerOverlayClass:
		print("GuidesLines: ERROR - Failed to load MarkerOverlay.gd")
		return
	
	CrossOverlay = ResourceLoader.load(self.Global.Root + "scripts/CrossOverlay.gd", "GDScript", false)
	if not CrossOverlay:
		print("GuidesLines: ERROR - Failed to load CrossOverlay.gd")
		return
	
	PermanentOverlay = ResourceLoader.load(self.Global.Root + "scripts/PermanentOverlay.gd", "GDScript", false)
	if not PermanentOverlay:
		print("GuidesLines: ERROR - Failed to load PermanentOverlay.gd")
		return
	
	if LOGGER:
		LOGGER.debug("Classes loaded successfully")

# Main update loop - called every frame
# Manages tool lifecycle and updates overlays
func update(_delta):
	# Create tool when Editor is ready (only once)
	if not tool_created and Global.Editor != null and Global.Editor.Toolset != null:
		create_tool()
		tool_created = true
	
	# Only work when map is loaded
	if Global.World == null or Global.WorldUI == null:
		return
	
	# Check for snappy_mod once after map is loaded (mods don't change after map creation)
	if not snappy_mod_checked:
		if self.Global.API and self.Global.API.has("ModRegistry"):
			var registered = self.Global.API.ModRegistry.get_registered_mods()
			# Search for custom_snap mod by unique_id
			if registered.has("Lievven.Snappy_Mod"):
				var mod_info = registered["Lievven.Snappy_Mod"]
				if mod_info.mod:
					cached_snappy_mod = mod_info.mod
					if LOGGER:
						var mod_name = mod_info.mod_meta.get("name", "Custom Snap Mod")
						var mod_version = mod_info.mod_meta.get("version", "unknown")
						LOGGER.info("Found custom_snap mod: %s v%s" % [mod_name, mod_version])
			
			if not cached_snappy_mod and LOGGER:
				LOGGER.debug("custom_snap mod not found, using vanilla grid snapping")
		
		snappy_mod_checked = true
	
	# Check if our tool is active and enable/disable accordingly
	if guides_tool:
		# Refresh cached references before checking tool state
		guides_tool.cached_world = Global.World
		guides_tool.cached_worldui = Global.WorldUI
		guides_tool.cached_camera = Global.Camera
		guides_tool.cached_snappy_mod = cached_snappy_mod
		
		# Check if tool is active by tool name
		var is_active = Global.Editor.ActiveToolName == "GuidesLinesTool"
		
		# Enable/disable based on active state
		if is_active and not guides_tool.is_enabled:
			guides_tool.Enable()
		elif not is_active and guides_tool.is_enabled:
			guides_tool.Disable()
		
		# Always call Update when the tool is enabled
		if guides_tool.is_enabled:
			guides_tool.Update(_delta)
	
	# Update proximity and permanent guides if enabled
	if cross_guides_enabled or perm_vertical_enabled or perm_horizontal_enabled:
		_update_proximity_and_permanent_guides(_delta)

# Update proximity and permanent guide features
# Only runs if these features are enabled in settings
func _update_proximity_and_permanent_guides(_delta):
	# Create overlays if needed
	if cross_overlay == null and cross_guides_enabled:
		create_cross_overlay()
	if perm_overlay == null and (perm_vertical_enabled or perm_horizontal_enabled):
		create_perm_overlay()
	
	# Get camera
	var camera = null
	if Global.Camera != null:
		camera = Global.Camera
	else:
		camera = find_camera(Global.World.get_parent())
	
	if camera == null:
		return
	
	# Cache world and camera in overlays
	if cross_overlay != null:
		cross_overlay.cached_world = Global.World
		cross_overlay.cached_camera = camera
	if perm_overlay != null:
		perm_overlay.cached_world = Global.World
		perm_overlay.cached_camera = camera
		perm_overlay.cached_snappy_mod = cached_snappy_mod
	
	# Update cross guides (proximity-based)
	if cross_guides_enabled and cross_overlay != null:
		update_cross_guides()
	elif cross_overlay != null:
		if cross_show_v or cross_show_h:
			cross_show_v = false
			cross_show_h = false
			cross_overlay.update()
	
	# Update permanent guides
	if perm_overlay != null:
		perm_overlay.update()

# ============================================================================
# TOOL UI CALLBACKS
# ============================================================================

func _on_delete_all_markers(tool_instance):
	if tool_instance:
		tool_instance.delete_all_markers()

func _on_snap_to_grid_toggled(enabled, tool_instance):
	if tool_instance:
		tool_instance.set_snap_to_grid(enabled)

func _on_show_coordinates_toggled(enabled, tool_instance):
	if tool_instance:
		tool_instance.set_show_coordinates(enabled)

func _on_delete_mode_toggled(enabled, tool_instance):
	if tool_instance:
		tool_instance.set_delete_mode(enabled)

func _on_cross_guides_toggled(enabled):
	cross_guides_enabled = enabled

func _on_perm_vertical_toggled(enabled):
	perm_vertical_enabled = enabled
	_on_perm_guide_changed(enabled)

func _on_perm_horizontal_toggled(enabled):
	perm_horizontal_enabled = enabled
	_on_perm_guide_changed(enabled)

func _on_perm_coordinates_toggled(enabled):
	show_coordinates_enabled = enabled
	_on_perm_guide_changed(enabled)

# ============================================================================
# TOOL CREATION
# ============================================================================

# Create and register the main Guide Markers tool
# Sets up the tool instance and its UI panel
func create_tool():
	if LOGGER:
		LOGGER.debug("Creating Guide Markers tool")
	
	# Create tool instance
	guides_tool = GuidesLinesToolClass.new(self)
	guides_tool.GuideMarkerClass = GuideMarkerClass
	guides_tool.MarkerOverlayClass = MarkerOverlayClass
	
	# Create ClassInstancedLogger for GuidesLinesTool
	if LOGGER:
		guides_tool.LOGGER = LOGGER.for_class("GuidesLinesTool")
	else:
		guides_tool.LOGGER = null
	
	# Cache global references
	guides_tool.cached_world = Global.World
	guides_tool.cached_worldui = Global.WorldUI
	guides_tool.cached_camera = Global.Camera
	
	# Register tool with Dungeondraft
	var icon_path = self.Global.Root + TOOL_ICON_PATH
	
	tool_panel = Global.Editor.Toolset.CreateModTool(
		self,
		"Design",  # Category
		"GuidesLinesTool",  # Unique ID
		"Guide Markers",  # Display name
		icon_path
	)
	
	if tool_panel == null:
		if LOGGER:
			LOGGER.error("Failed to create tool panel!")
		else:
			print("GuidesLines: ERROR - Failed to create tool panel!")
		return
	
	# Set tool reference
	guides_tool.tool_panel = tool_panel
	
	# Create UI for the tool
	guides_tool.create_ui_panel()
	
	if LOGGER:
		LOGGER.debug("Guide Markers tool created successfully")

# Settings changed handlers
func _on_perm_guide_changed(_enabled):
	# Update overlay when any permanent guide setting changes
	if perm_overlay:
		perm_overlay.update()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func find_camera(node):
	if node == null:
		return null
	if node.get_class() == "Camera2D":
		return node
	for child in node.get_children():
		var result = find_camera(child)
		if result != null:
			return result
	return null

# ============================================================================
# PROXIMITY AND PERMANENT GUIDE OVERLAYS
# ============================================================================

func create_cross_overlay():
	cross_overlay = CrossOverlay.new()
	cross_overlay.parent_mod = self
	Global.WorldUI.add_child(cross_overlay)
	cross_overlay.update()

func create_perm_overlay():

	perm_overlay = PermanentOverlay.new()
	perm_overlay.parent_mod = self
	Global.WorldUI.add_child(perm_overlay)
	perm_overlay.update()

# Update proximity-based cross guides
# Shows red lines when cursor approaches map center
func update_cross_guides():
	if not Global.WorldUI.IsInsideBounds:
		if cross_show_v or cross_show_h:
			cross_show_v = false
			cross_show_h = false
			cross_overlay.update()
		return
	
	var mp = Global.WorldUI.MousePosition
	var rect = Global.World.WorldRect
	var cx = rect.position.x + rect.size.x * 0.5
	var cy = rect.position.y + rect.size.y * 0.5
	
	var dx = abs(mp.x - cx)
	var dy = abs(mp.y - cy)
	
	var nv = false
	var nh = false
	
	if cross_show_v:
		nv = dx < (DETECTION_DISTANCE + HYSTERESIS)
	else:
		nv = dx < DETECTION_DISTANCE
	
	if cross_show_h:
		nh = dy < (DETECTION_DISTANCE + HYSTERESIS)
	else:
		nh = dy < DETECTION_DISTANCE
	
	if nv != cross_show_v or nh != cross_show_h:
		cross_show_v = nv
		cross_show_h = nh
		cross_overlay.update()

# ============================================================================
# SAVE/LOAD
# ============================================================================

# Save guide markers to map file
# Called by Dungeondraft when saving the map
func save_level(level_data):
	# Save guide markers data
	if guides_tool:
		var markers_data = guides_tool.save_markers()
		if markers_data.size() > 0:
			level_data["guide_markers"] = markers_data
	return level_data

# Load guide markers from map file
# Called by Dungeondraft when loading a map
func load_level(level_data):
	# Load guide markers data
	if guides_tool and level_data.has("guide_markers"):
		guides_tool.load_markers(level_data.guide_markers)
