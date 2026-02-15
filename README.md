# GuidesLines - Dungeondraft Mod

**Version:** 1.0.10 (WIP)  
**Compatible with:** Dungeondraft 1.1.1.1 and later  
**Requires:** _Lib-1.2.0

Advanced guide system with fully customizable markers for precise map alignment and composition.

## Overview

GuidesLines provides a powerful, flexible system for adding guide lines and shapes to your Dungeondraft maps. Place markers anywhere on your map to create custom visual alignment guides. Choose between **Line markers** (at any angle, with optional range limits), **Circle markers** (any radius), **Path markers** (multi-point custom paths), or **Arrow markers** (2-point directional arrows with arrowheads). Customize colors, mirror lines, arrowhead size, and more. Perfect for ensuring symmetry, alignment, and precise composition in your map designs.

All settings are conveniently located in the Guide Markers tool panel - no need to navigate to separate menus or settings windows.

### Recent Changes (Work in Progress)

**⚠️ Major Refactoring in Progress**

The marker system has been completely redesigned for maximum flexibility:

- **Old System** (v1.0.10 and earlier): Fixed guide types (vertical, horizontal, diagonal left, diagonal right) with checkboxes
- **New System** (current WIP): Flexible marker types with customizable parameters:
  - **Line Markers**: Any angle (0-360°), optional range limit, mirror mode, custom color
  - **Circle Markers**: Any radius, custom color
  - **Path Markers**: Multi-point custom paths with sequential placement (NEW!)
    - Draw complex paths with any number of points
    - Click to add points, right-click to finish, ESC to cancel
    - Close path by clicking near first point (creates loop)
    - Real-time preview with visual feedback
  - **Arrow Markers**: 2-point directional arrows with arrowheads (NEW!)
    - Automatically finishes at second point
    - Customizable arrowhead length (10-200 pixels) and angle (10-60 degrees)
    - Real-time preview shows arrow line and arrowhead
    - ESC to cancel during placement
  - **Mouse Wheel Control**: Scroll to adjust angle (Lines) or radius (Circles) in real-time
  - **Color Customization**: Each marker can have its own color
  - **More Types Coming**: Architecture supports adding new marker types in future

> **Breaking Change**: Maps saved with the new system will NOT be compatible with v1.0.10 or earlier versions. Backup your maps before upgrading!

### What's New

**Automatic Update Notifications**: The mod now checks for updates automatically using _Lib's UpdateChecker. When a new version is released on GitHub, you'll see a notification in the "Mod Versions" window (accessible from the Mods menu). Click the button to visit the download page.

> **Note**: UpdateChecker will show "Repository does not have any releases" until the first GitHub Release is created. This is normal and doesn't affect mod functionality.

**Full Undo/Redo Support**: All marker operations are now fully undoable:
- Press **Ctrl+Z** to undo marker placement or deletion
- Press **Ctrl+Y** (or Ctrl+Shift+Z) to redo operations
- Works seamlessly with Dungeondraft's native undo system
- History is preserved across all marker operations

## Features

### Flexible Custom Markers
- **Custom Tool**: Dedicated "Guide Markers" tool in the Design category
- **Marker Types**: Choose between Line, Circle, Path, or Arrow markers (more types possible in future)
- **Line Markers**:
  - Any angle from 0° to 360° (adjustable via spinbox or mouse wheel)
  - Optional range limit (infinite by default, or specify length in grid cells)
  - Mirror mode (creates second line at 180° offset)
  - Customizable color
- **Circle Markers**:
  - Any radius in grid cells (adjustable via spinbox or mouse wheel)
  - Customizable color
- **Path Markers** (NEW):
  - Multi-point custom paths with interactive placement
  - Click to add points sequentially (minimum 2 points)
  - Right-click to finish as open path
  - Click near first point to close path (creates loop, requires 3+ points)
  - ESC to cancel placement
  - Real-time preview with visual feedback:
    - First point: green, larger
    - Intermediate points: red, semi-transparent
    - Preview line to cursor: white, dashed
    - Pulsing indicator when hovering to close
  - Grid snapping support for each point
  - Customizable color
- **Arrow Markers** (NEW):
  - 2-point directional arrows with arrowheads
  - Click to place start point, then second click places end point and finishes arrow
  - Automatically completes at second point
  - Customizable arrowhead:
    - Length: 10-200 pixels (adjustable via spinbox)
    - Angle: 10-60 degrees (adjustable via spinbox)
  - Real-time preview:
    - Green start point
    - White preview line from start to cursor
    - Preview arrowhead at cursor position
  - ESC to cancel placement before second point
  - Grid snapping support for both points
  - Customizable color
- **Real-Time Preview**: See exact marker appearance before placing
- **Mouse Wheel Adjustment**: Scroll to change angle (Lines) or radius (Circles) while hovering
- **Grid Snapping**: Optional snap-to-grid placement (works with custom_snap mod if installed)
- **Persistent**: Markers are saved with your map
- **Delete Mode**: Right-click to delete individual markers, or use "Delete All Markers" button
- **Undo/Redo Support**: Full integration with Dungeondraft's history system (Ctrl+Z/Ctrl+Y)
  - Undo/redo marker placement (including complete paths)
  - Undo/redo marker deletion
  - Undo/redo "Delete All Markers" operations
  - History limit: 100 operations per type (prevents memory overflow)

### Overlay Options

All overlay settings are accessible directly in the Guide Markers tool panel:

- **Cross Guides** (Proximity-Based): Red/green crosshair guides that appear only near your cursor (5-tile radius)
- **Vertical Center Line**: Permanent yellow vertical guide line at map center
- **Horizontal Center Line**: Permanent yellow horizontal guide line at map center
- **Show Grid Coordinates**: Toggle coordinate labels on all active guide lines

### Grid Coordinates Display

Both markers and permanent guides can display grid coordinates along their lines:

- **Grid Node Markers**: Small blue circles at each grid intersection along the guide lines
- **Distance Numbers**: Large numbers showing distance from the line's center in grid cells
- **Auto-Scaling**: Text and markers scale with camera zoom for consistent visibility
- **Custom Grid Support**: Works with both vanilla Dungeondraft grid and custom_snap modified grids
- **Map Boundaries**: Coordinates only display within map boundaries

**For Markers:**
- Enable "Show Coordinates" checkbox in the Guide Markers tool
- Automatically enables and locks "Snap to Grid" to ensure accurate positioning
- Coordinates appear only on placed markers (not in preview)
- Works for all line types: vertical, horizontal, and diagonal

**For Permanent Guides:**
- Enable "Show Grid Coordinates" checkbox in the Guide Overlays section
- Requires at least one permanent line (vertical or horizontal) to be enabled
- Shows coordinates on permanent center lines
- Includes a red center marker dot for easy map center identification

### Additional Features

All overlay options are integrated into the Guide Markers tool panel:

- **Cross Guides**: Red/green crosshair guides that appear when cursor is near a marker (proximity-based, 5-tile radius)
- **Permanent Center Lines**: Yellow vertical and/or horizontal lines at exact map center
- **Grid Coordinates**: Display grid position markers and distance numbers on all active guide lines

## Usage

### Placing Markers

1. Select the **"Guide Markers"** tool from the Design category
2. **Choose Marker Type** from the dropdown:
   - **Line**: Creates a guide line at specified angle
   - **Circle**: Creates a circle guide at specified radius
   - **Path**: Creates a multi-point custom path guide
3. **Configure Marker Settings**:
   
   **For Line Markers:**
   - **Angle**: Set the line angle in degrees (0-360°)
     - 0° = Horizontal right
     - 90° = Vertical down
     - 180° = Horizontal left
     - 270° = Vertical up
     - Or scroll mouse wheel while hovering to adjust in 5° increments
   - **Range**: Set line length in grid cells (0 = infinite, perfect for full-map guides)
   - **Mirror**: Check to create a second line at 180° offset (great for symmetry)
   - **Color**: Click color button to choose custom color (default: blue)
   
   **For Circle Markers:**
   - **Radius**: Set circle radius in grid cells
     - Or scroll mouse wheel while hovering to adjust in 0.5 cell increments
   - **Color**: Click color button to choose custom color (default: blue)
   
   **For Path Markers:**
   - **Interactive Placement Mode**: Path markers use a special multi-step placement process
   - Instructions are displayed in the tool panel
   - No pre-configuration needed - all setup happens during placement
   - **Color**: Choose color before starting path placement
   
   **For Arrow Markers:**
   - **Arrowhead Length**: Set arrowhead line length in pixels (10-200)
   - **Arrowhead Angle**: Set arrowhead wing angle in degrees (10-60)
   - **Interactive Placement Mode**: Arrow markers use 2-point placement
   - **Color**: Choose color before starting arrow placement
3. **(Optional)** Enable "Show Coordinates" to display grid position markers and numbers
   - This automatically enables "Snap to Grid" for accurate positioning
   - Coordinates show distance from marker center in grid cells
   - Works with custom_snap modified grids
4. Click anywhere on the map to place a marker
5. Guide lines will appear instantly through the marker position
6. **Tip**: Enable "Snap to Grid" for precise grid-aligned placement

### Placing Path Markers (Multi-Point Placement)

Path markers use a special interactive placement mode:

1. **Select Path Type** from the marker type dropdown
2. **Read Instructions** in the tool panel (they appear when Path is selected)
3. **Start Placement**: Click on the map to place the first point (shown in green)
4. **Add Points**: Continue clicking to add more points sequentially
   - Each point will be connected to the previous one with a line
   - Preview shows: green first point, red intermediate points, white line to cursor
   - Status label shows current point count
5. **Finish the Path** (two options):
   
   **Option A - Close Path (Create Loop):**
   - Click near the first point (within 30 pixels)
   - A pulsing green circle will appear when you're close enough
   - Requires minimum 3 points
   - Creates a closed path with line connecting last point to first
   
   **Option B - Open Path:**
   - Right-click anywhere to finish
   - Requires minimum 2 points
   - Creates an open path (no closing line)

6. **Cancel Placement**: Press ESC key at any time to cancel and start over
   - Or click the "Cancel Path" button in the tool panel

**Path Placement Tips:**
- Each point automatically snaps to grid (if "Snap to Grid" is enabled)
- The preview line helps visualize where the next segment will go
- You can place as many points as needed (no maximum limit)
- Coordinates display (if enabled) shows cumulative distance from path start
- Undo/Redo works on complete paths (entire path is one marker)

### Placing Arrow Markers (2-Point Placement)

Arrow markers use a simple 2-point placement mode with automatic completion:

1. **Select Arrow Type** from the marker type dropdown
2. **Configure Arrowhead**:
   - **Arrowhead Length**: Set length of arrowhead lines (10-200 pixels)
   - **Arrowhead Angle**: Set angle of arrowhead wings (10-60 degrees)
   - These can be adjusted before or between placements
3. **Start Placement**: Click on the map to place the start point (shown in green)
   - Preview shows green start point and white line to cursor with arrowhead
4. **Complete Arrow**: Click second point to finish
   - Arrow automatically completes after second point
   - Arrow points from first point to second point
   - Arrowhead appears at the second (end) point
5. **Cancel Placement**: Press ESC key before second point to cancel
   - Or click the "Cancel Arrow" button in the tool panel

**Arrow Placement Tips:**
- Both points automatically snap to grid (if "Snap to Grid" is enabled)
- Preview shows exact arrow appearance including arrowhead
- Arrowhead scales with camera zoom for consistent visibility
- Coordinates display (if enabled) shows start and end point distances
- Undo/Redo works on complete arrows (entire arrow is one marker)
- Great for indicating direction, flow, or pointing to map features

### Preview Mode

Before placing a marker, you'll see a semi-transparent red preview showing:
- Where the marker will be placed
- Which guide lines will be drawn
- How they'll look at that position

**For Path Markers**, the preview is interactive:
- First point: Green, larger
- Intermediate points: Red, semi-transparent
- Active preview line: White, from last point to cursor
- Close indicator: Pulsing green circle when hovering near first point

**For Arrow Markers**, the preview is interactive:
- Start point: Green, larger
- Preview line: White, from start point to cursor
- Preview arrowhead: Shows exact arrowhead appearance at cursor

This helps ensure perfect placement before committing.

### Managing Markers

#### Moving Markers
Markers are **not** movable after placement. To reposition:
1. Delete the marker (right-click or delete mode)
2. Place a new one at the desired location
3. Use Ctrl+Z to undo if needed

#### Deleting Markers

**Right-Click Deletion (Quick):**
- Right-click near any marker to delete it instantly
- Fully supports undo/redo (Ctrl+Z/Ctrl+Y)

**Delete Mode (Precise):**
1. Enable **"Delete Markers Mode"** checkbox in the tool panel
2. All other options will be disabled while delete mode is active
3. Preview marker will be hidden
4. Click near any marker (within 20 pixels) to delete it
5. Disable "Delete Markers Mode" to return to placement mode

**Delete All:**
- Click **"Delete All Markers"** button to remove all markers instantly
- Fully supports undo/redo

#### Grid Snapping
- **Enabled by default** - markers snap to grid
- Works with **custom_snap** mod if installed for enhanced snapping
- Falls back to vanilla Dungeondraft snapping otherwise
- Uncheck "Snap to Grid" for freeform placement
- **Note**: "Snap to Grid" is automatically locked when "Show Coordinates" is enabled

### Using Overlay Features

#### Guide Overlays Section:
All overlay settings are in the Guide Markers tool panel under "Guide Overlays":

1. **Cross Guides**: Toggle proximity-based crosshairs
   - Red crosshairs when outside snap radius
   - Green crosshairs when inside snap radius
   - Only appear within 5 tiles of a placed marker

2. **Vertical Center Line**: Toggle permanent yellow vertical line at map center

3. **Horizontal Center Line**: Toggle permanent yellow horizontal line at map center

4. **Show Grid Coordinates**: Toggle coordinate display
   - Works on all active guide lines (marker-based or permanent)
   - Blue dots at grid intersections
   - Distance numbers from line center
   - Red center dot for permanent guides

**Custom Grid Compatibility:**
- If custom_snap mod is active, coordinates adapt to the modified grid

- Works with square, hexagonal, and isometric grids
- Permanent lines snap to nearest grid node as center
- Distance calculations account for custom grid spacing and offset

## File Structure

```
GuidesLines_v7/
├── GuidesLines.gd              # Main mod file - lifecycle and coordination
├── GuidesLines.ddmod           # Mod metadata
├── README.md                   # This file
├── CHANGELOG.md                # Version history
└── scripts/
    ├── GuideMarker.gd          # Marker data class with multi-type support
    ├── GuidesLinesTool.gd      # Tool for placing/managing markers
    ├── MarkerOverlay.gd        # Rendering engine for markers and guides
    ├── CrossOverlay.gd         # Proximity-based guide overlays
    └── PermanentOverlay.gd     # Permanent center guide overlays
```

## Technical Details

### Current Development Status

This is a **work-in-progress version** with major architectural changes:

- ✅ Core marker system redesigned (Line and Circle types)
- ✅ UI rebuilt with type selector and dynamic controls
- ✅ Mouse wheel parameter adjustment implemented
- ✅ Color picker integration complete
- ✅ Line angle/range/mirror functionality working
- ✅ Circle radius functionality working
- ✅ Save/Load updated for new format
- ⚠️ Backward compatibility removed (old maps won't load)
- ⚠️ Coordinate display needs testing with new system
- ⚠️ Extensive testing needed before release

### Architecture

The mod uses a clean separation of concerns:

1. **GuidesLines.gd**: Main coordinator
   - Registers with Dungeondraft and _Lib API
   - Creates tools and manages lifecycle
   - Handles save/load operations
   - Manages overlay callbacks and state
   
2. **GuidesLinesTool.gd**: Tool logic
   - Manages marker creation and storage
   - Handles UI interactions and all settings
   - Integrates with custom_snap if available
   - Provides callbacks for overlay toggles
   
3. **MarkerOverlay.gd**: Rendering engine
   - Draws all markers and guide lines
   - Handles preview rendering
   - Calculates diagonal line intersections
   
4. **GuideMarker.gd**: Data model
   - Stores marker position and types
   - Provides serialization for save/load
   - Backward compatible with v2 format

5. **CrossOverlay.gd & PermanentOverlay.gd**: Overlay systems
   - Proximity-based and permanent guide overlays
   - Coordinate display system
   - Grid compatibility layer

### Integration Features

- **_Lib-1.2.0 API**: Uses modern `self.Global.API` pattern for all API access
- **Logger API**: Professional logging with InstancedLogger (auto-scoped to mod name)
- **HistoryApi**: Full undo/redo support for all marker operations
- **ModRegistry API**: Enhanced mod detection (custom_snap compatibility)
- **custom_snap Compatibility**: Uses custom_snap for grid snapping if available
- **Save/Load**: Markers persist with map files in the `guide_markers` key
- **Viewport Rendering**: Guide lines extend across entire visible area
- **Z-Index Ordering**: Overlays rendered at high z-index (99-100) for visibility

### Rendering Details
- **Coordinate Markers**: 5px blue circles at grid nodes (scales with zoom)
- **Coordinate Text**: 4x size with black outline, displays distance in grid cells
- **Center Marker**: 15px red circle on permanent guides (scales with zoom)
- **Marker Size**: 40px diameter red circles
- **Guide Lines**: 10px wide blue lines (Color: `0, 0.7, 1, 1`)
- **Preview**: Semi-transparent red (0.5-0.7 alpha)
- **Line Extension**: Lines calculated to viewport boundaries for infinite appearance

### Backward Compatibility

The mod maintains full compatibility with older save formats:
- Old single-type markers are converted to multi-type on load
- "both" type splits into separate vertical/horizontal types
- ID-based marker tracking prevents duplicates

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

### Current Version (1.0.9)
- All settings consolidated in Guide Markers tool panel
- Full _Lib-1.2.0 compatibility
- Removed ModConfig Settings menu (UX improvement)
- Updated API usage patterns for modern _Lib
- Improved accessibility of all features

### Previous Highlights
- Multi-type markers with checkbox selection
- Diagonal guide lines (45° and 135°)
- Real-time preview before placement
- Undo/redo support for all operations
- Logger API integration for diagnostics
- Custom_snap integration for enhanced snapping

## Known Limitations

- Markers cannot be moved after placement (must delete and recreate)
- Maximum practical markers: ~100 (performance depends on system)
- Delete mode requires clicking within 20 pixels of marker center

## Tips & Best Practices

1. **Symmetry**: Use vertical/horizontal guides to ensure symmetric map layouts
2. **Diagonals**: Use diagonal guides for 45° angles in buildings and rooms
3. **Composition**: Place markers at rule-of-thirds positions for better visual balance
4. **Grid Snapping**: Keep enabled for clean alignment with map grid
5. **Temporary Guides**: Delete all markers before exporting final map
6. **Layering**: Combine with permanent center lines for multi-level alignment system
7. **Coordinates for Measurement**: Use "Show Coordinates" to measure distances in grid cells
8. **Custom Grids**: Coordinates automatically adapt to custom_snap grid modifications
9. **Center Reference**: Use permanent guides with coordinates to mark map center with red dot
10. **Distance Planning**: Use coordinate numbers to plan symmetrical room layouts
11. **Undo/Redo**: Use Ctrl+Z/Ctrl+Y to undo/redo marker placement and deletion
12. **Quick Corrections**: Right-click to quickly delete misplaced markers
13. **Cross Guides**: Enable to get proximity-based alignment hints near placed markers

## Compatibility

### Requirements
- **Dungeondraft**: Version 1.1.1.1 or later
- **_Lib**: Version 1.2.0 (required dependency)

### Optional Mods
- **custom_snap**: Enhanced grid snapping functionality
  - Automatically detected when installed
  - Guide Lines gracefully degrades if not present

### Compatible Mods
- All _Lib-based mods
- Essential Utils
- Minor Utils
- Most other Dungeondraft mods

## Installation

1. Download the mod archive
2. Extract to your Dungeondraft mods folder:
   - **Windows**: `%AppData%\Dungeondraft\mods\`
   - **macOS**: `~/Library/Application Support/Dungeondraft/mods/`
   - **Linux**: `~/.local/share/Dungeondraft/mods/`
3. Install **_Lib-1.2.0** if not already installed
4. Restart Dungeondraft

## Troubleshooting

### Mod not appearing
- Verify _Lib-1.2.0 is installed
- Check Dungeondraft version is 1.1.1.1 or later
- Restart Dungeondraft completely

### Guide lines not visible
- Ensure at least one marker is placed
- Check that marker type checkboxes are enabled
- Verify the Guide Markers tool is active

### Coordinates not showing
- Enable "Show Grid Coordinates" in Guide Overlays section
- Ensure at least one guide line is active (marker-based or permanent)

### Undo/Redo not working
- Verify _Lib-1.2.0 is properly installed
- Check Dungeondraft version compatibility
- Try restarting Dungeondraft

## Author

**Choson**  
Created for the Dungeondraft map-making community.

**License**: Free for personal use

### Special Thanks
- MegalomaniacMegalodon for the _Lib framework
- The Dungeondraft modding community
- custom_snap mod authors for grid snapping inspiration


## License

Free to use and modify.
