# GuidesLines - Dungeondraft Mod

**Version:** 2.0.0  
**Compatible with:** Dungeondraft 1.1.1.1 and later  
**Requires:** _Lib-1.2.0

Advanced guide system with fully customizable markers for precise map alignment and composition.

---

## ⚠️ Version 2.0.0 - Breaking Changes

**This is a major release with breaking changes. Maps saved with v2.0.0 are NOT compatible with v1.x versions.**

### What's New in 2.0.0

- 🎨 **Complete marker system redesign** - flexible, extensible architecture
- 🔄 **4 marker types**: Line, Shape, Path, Arrow (vs 3 fixed types in v1.x)
- 🎯 **Infinite customization** - angles, colors, sizes for each marker
- 🖱️ **Mouse wheel controls** - adjust parameters in real-time
- 👁️ **Enhanced previews** - see exactly what you'll get before placing
- ⚡ **Better performance** - optimized rendering engine

### Migration from v1.x

**⚠️ IMPORTANT: Backup your maps before upgrading!**

1. **Export your v1.x maps** as images/exports before upgrading
2. **Install v2.0.0** in a fresh Dungeondraft mods folder
3. **Recreate markers** using the new flexible system (much more powerful!)

There is **no automatic migration** - the data formats are incompatible at the fundamental level.

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [Placing Line Markers](#placing-line-markers)
  - [Placing Shape Markers](#placing-shape-markers)
  - [Placing Path Markers](#placing-path-markers)
  - [Placing Arrow Markers](#placing-arrow-markers)
  - [Managing Markers](#managing-markers)
  - [Overlay Features](#overlay-features)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Technical Details](#technical-details)
- [Troubleshooting](#troubleshooting)
- [Compatibility](#compatibility)
- [License](#license)

---

## Features

### 🎨 Flexible Marker System

**4 Powerful Marker Types:**

1. **Line Markers**
   - Any angle from 0° to 360°
   - Infinite length extending to map boundaries
   - Mirror mode for symmetrical designs
   - Mouse wheel angle adjustment (5° increments)
   - Custom color per marker
   - Perfect for alignment and perspective guides

2. **Shape Markers**
   - 5 subtypes: Circle, Square, Pentagon, Hexagon, Octagon
   - Radius: 0.5 to 100 grid cells
   - Full rotation support (except circles)
   - Mouse wheel radius adjustment (0.5 cell increments)
   - Mouse wheel rotation adjustment (5° increments for shapes)
   - Custom color per marker
   - Ideal for circular rooms, polygonal features, area planning

3. **Path Markers**
   - Multi-point custom paths (minimum 2 points, no maximum)
   - Open or closed paths
   - Sequential placement with visual feedback
   - Right-click to finish, ESC to cancel
   - Grid snapping for each point
   - Custom color per marker
   - Perfect for complex curves, custom boundaries, organic shapes

4. **Arrow Markers**
   - 2-point directional arrows
   - Customizable arrowhead (length 10-200px, angle 10-60°)
   - Automatic completion at second point
   - Real-time preview
   - Custom color per marker
   - Great for indicating flow, direction, connections

### 🖱️ Interactive Controls

- **Mouse Wheel Adjustment**: Scroll to modify angle/radius while hovering
- **Quick Angle Buttons**: 0°, 45°, 90°, 135° presets for common angles
- **Color Picker**: Independent color for each marker
- **Real-time Preview**: See exactly what you'll place
- **Settings Memory**: Each marker type remembers its last settings

### 📐 Advanced Features

- **Grid Snapping**: Works with vanilla and custom_snap mod grids
- **Coordinate Display**: Show grid positions on guide lines
- **Overlay System**:
  - Proximity guides (cross overlays near cursor)
  - Permanent center guides (vertical/horizontal)
  - Coordinate markers on guide lines
- **Full Undo/Redo**: Every operation is undoable (Ctrl+Z / Ctrl+Y)
- **Auto-Updates**: GitHub release notifications via UpdateChecker

### 💾 Persistence

- Markers saved with map files
- All visual parameters preserved (angle, color, radius, etc.)
- Backward compatible within v2.x versions

---

## Installation

### Requirements

- **Dungeondraft** 1.1.1.1 or later
- **_Lib** 1.2.0 (required dependency)

### Steps

1. **Download** the latest release from [GitHub](https://github.com/ChosonDev/GuidesLines/releases)
2. **Extract** to your Dungeondraft mods folder:
   - **Windows**: `%AppData%\Dungeondraft\mods\`
   - **macOS**: `~/Library/Application Support/Dungeondraft/mods/`
   - **Linux**: `~/.local/share/Dungeondraft/mods/`
3. **Install _Lib** if not already present (from [_Lib releases](https://github.com/CreepyCre/_Lib/releases))
4. **Restart** Dungeondraft

### Verification

1. Launch Dungeondraft
2. Check **Mods** menu → **Mod Versions** - should show "Guide Markers v2.0.0"
3. Create/open a map
4. Select **Design** category → **Guide Markers** tool
5. Tool panel should display marker type dropdown and settings

---

## Usage

### Placing Line Markers

**Best for: alignment, perspective, symmetry**

1. Select **Guide Markers** tool (Design category)
2. Choose **"Line"** from marker type dropdown
3. Configure settings:
   - **Angle**: 0-360° (or use quick buttons: 0°, 45°, 90°, 135°)
   - **Mirror**: Check for symmetrical paired line at 180° offset
   - **Color**: Click to pick custom color
   - **Tip**: Hover over angle spinbox and scroll mouse wheel to adjust in 5° increments
4. Optional: Enable "Snap to Grid" for precise positioning
5. Click on map to place marker
6. Guide lines appear instantly, extending infinitely to map edges

**Angle Reference:**
- 0° = Horizontal right →
- 90° = Vertical down ↓
- 180° = Horizontal left ←
- 270° = Vertical up ↑

**Mirror Mode:** Creates two lines through the same point at opposite angles (great for symmetry axes)

---

### Placing Shape Markers

**Best for: circular rooms, polygonal structures, area planning**

1. Select **Guide Markers** tool
2. Choose **"Shape"** from dropdown
3. Select **Shape Subtype**:
   - Circle
   - Square
   - Pentagon (5 sides)
   - Hexagon (6 sides)
   - Octagon (8 sides)
4. Configure settings:
   - **Radius**: 0.5-100 grid cells
     - **Tip**: Hover over radius spinbox and scroll mouse wheel (0.5 cell increments)
   - **Shape Angle**: 0-360° rotation (disabled for circles)
     - **Tip**: Use quick angle buttons or scroll mouse wheel while hovering (5° increments)
     - Rotates the entire shape around its center
   - **Color**: Custom color picker
5. Optional: Enable "Snap to Grid"
6. Click to place marker at shape center
7. Shape outline appears with specified radius and rotation

**Shape Angle Behavior:**
- Square: rotates on all 4 corners
- Pentagon/Hexagon/Octagon: rotates all vertices
- Circle: angle control disabled (circles have no rotation)

---

### Placing Path Markers

**Best for: complex curves, custom boundaries, organic shapes**

Path markers use **interactive sequential placement**:

1. Select **Guide Markers** tool
2. Choose **"Path"** from dropdown
3. Configure color (other settings disabled during placement)
4. **Start placement**: Click on map for first point
   - Point appears in **green** (larger size)
   - Placement mode activates automatically
5. **Add points**: Click to add more points
   - Each new point connects to previous
   - Points shown in **red** (semi-transparent)
   - **White dashed line** previews next segment to cursor
6. **Finish placement**:
   - **Right-click**: Finish as open path (minimum 2 points)
   - **Click near first point**: Close path into loop (minimum 3 points)
     - Pulsing green circle indicates "close zone"
   - **ESC key**: Cancel and discard all points
7. Path appears in chosen color

**Path Tips:**
- Each point snaps to grid (if enabled)
- Preview line shows exactly where next segment will go
- Coordinate display (if enabled) shows cumulative distance from start
- No maximum point limit (tested up to 100+ points)
- Can't edit path after placement - use undo (Ctrl+Z) to remove and start over

---

### Placing Arrow Markers

**Best for: direction indicators, flow, connections**

Arrow markers use **2-point placement** with automatic completion:

1. Select **Guide Markers** tool
2. Choose **"Arrow"** from dropdown
3. Configure **Arrow head**:
   - **Head Length**: 10-200 pixels (arrowhead line length)
   - **Head Angle**: 10-60 degrees (wing angle)
4. Configure **Color**
5. **Start placement**: Click for arrow start point
   - Point appears in **green**
   - White preview line follows cursor with arrowhead preview
6. **Complete arrow**: Click for end point
   - Arrow automatically finishes (no third click needed)
   - Arrowhead appears at end point
   - Arrow points from start → end
7. **Cancel placement** (before second point):
   - **Right-click** or **ESC key**

**Arrow Tips:**
- Both points snap to grid (if enabled)
- Preview shows exact arrowhead appearance
- Arrowhead scales with camera zoom for visibility
- Can adjust head length/angle before or between placements
- Coordinate display shows start and end distances

---

### Managing Markers

#### Deleting Markers

**Method 1: Right-Click (Quick)**
- Right-click near any marker to delete instantly
- Works when NOT in path/arrow placement mode
- Fully undoable (Ctrl+Z)

**Method 2: Delete Mode (Precise)**
1. Enable **"Delete Markers Mode"** checkbox
2. All other options disabled, preview hidden
3. Click near marker (within 20 pixels of center) to delete
4. Disable checkbox to return to placement mode

**Method 3: Delete All**
- Click **"Delete All Markers"** button
- Removes all markers instantly
- Fully undoable (Ctrl+Z)

#### Undo/Redo

- **Ctrl+Z**: Undo last operation (placement, deletion, delete all)
- **Ctrl+Y** (or Ctrl+Shift+Z): Redo operation
- History limit: 100 operations per type
- Full state restoration (color, angle, all parameters)

#### Notes

- **Markers cannot be moved** - delete and recreate to reposition
- **Use preview** to verify placement before clicking
- **Right-click deletion** doesn't work during path/arrow placement

---

### Overlay Features

#### Proximity Guides (Cross Overlays)

**When enabled, shows guide lines when cursor approaches a marker:**

- Vertical and horizontal lines through marker center
- Appears when cursor within configurable distance
- Helps align new elements with existing markers
- Toggle: **"Show Cross Guides"** checkbox

#### Permanent Center Guides

**Fixed guide lines through map center:**

- **Permanent Vertical Guide**: Vertical line through center
- **Permanent Horizontal Guide**: Horizontal line through center
- Always visible when enabled (not tied to cursor)
- Great for symmetry and map center reference
- Toggle independently in **Guide Overlays** section

#### Grid Coordinates

**Display coordinate markers on guide lines:**

- Shows grid position at intersections
- Numbers indicate distance from marker center in cells
- Red center dot marks reference point (0, 0)
- Automatically enables "Snap to Grid" when activated
- Toggle: **"Show Grid Coordinates"** checkbox
- Works with custom_snap modified grids

**Smart Behavior:**
- Auto-disables when no guide lines active
- Updates dynamically as markers are added/removed

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **ESC** | Cancel path/arrow placement |
| **Right-Click** | Finish path (open) / Cancel arrow / Delete marker (when not placing) |
| **Ctrl+Z** | Undo last operation |
| **Ctrl+Y** / **Ctrl+Shift+Z** | Redo operation |
| **Mouse Wheel Up/Down** (over Angle) | Adjust angle ±5° |
| **Mouse Wheel Up/Down** (over Radius) | Adjust radius ±0.5 cells |

---

## Technical Details

### Architecture

**Clean separation of concerns:**

1. **GuidesLines.gd** - Main coordinator
   - Registers with Dungeondraft and _Lib API
   - Creates tools and manages lifecycle
   - Handles save/load operations
   - Manages overlay callbacks

2. **GuidesLinesTool.gd** - Tool logic
   - Marker creation and storage
   - UI interactions and settings management
   - Path/Arrow placement state machines
   - Custom_snap integration
   - History record creation

3. **MarkerOverlay.gd** - Rendering engine
   - Draws all marker types and guide lines
   - Handles preview rendering
   - Path/Arrow interactive previews
   - Mouse wheel input handling

4. **GuideMarker.gd** - Data model
   - Stores marker type and all parameters
   - Serialization for save/load
   - Single flat structure for all types

5. **CrossOverlay.gd & PermanentOverlay.gd** - Overlay systems
   - Proximity-based and permanent guides
   - Coordinate display system
   - Grid compatibility layer

### Integration

- **_Lib-1.2.0 API**: Modern `self.Global.API` pattern
- **Logger API**: Professional logging with class-scoped instances
- **HistoryApi**: Full undo/redo with custom record classes
- **ModRegistry API**: Enhanced mod detection (custom_snap)
- **UpdateChecker**: Automatic GitHub release notifications
- **custom_snap**: Detects and uses custom grid snapping

### Save Format

Markers stored in map file under `guide_markers` key:

```json
{
  "marker_type": "Line|Shape|Path|Arrow",
  "position": {"x": float, "y": float},
  "color": {"r": float, "g": float, "b": float, "a": float},
  
  // Line-specific
  "angle": float (0-360),
  "line_range": float,
  "mirror": bool,
  
  // Shape-specific
  "circle_radius": float,
  "shape_subtype": "Circle|Square|Pentagon|Hexagon|Octagon",
  "shape_angle": float (0-360),
  
  // Path-specific
  "path_points": [{"x": float, "y": float}, ...],
  "path_closed": bool,
  
  // Arrow-specific
  "arrow_head_length": float (10-200),
  "arrow_head_angle": float (10-60)
}
```

### Performance

- Tested with 100+ markers on 4K maps
- Optimized rendering loop
- Efficient coordinate calculations
- Smart preview updates

---

## Troubleshooting

### Mod not appearing
- **Check**: _Lib-1.2.0 installed?
- **Check**: Dungeondraft version ≥ 1.1.1.1?
- **Action**: Restart Dungeondraft completely

### Guide lines not visible
- **Check**: At least one marker placed?
- **Check**: Guide Markers tool active?
- **Action**: Try placing a Line marker at (0, 0)

### Undo not working
- **Check**: _Lib-1.2.0 properly installed?
- **Check**: History limit not exceeded? (100 per type)
- **Action**: Restart Dungeondraft

### Path placement stuck
- **Action**: Press ESC to cancel
- **Action**: Switch to different marker type
- **Check**: Minimum 2 points for open path, 3 for closed

### Custom_snap not detected
- **Check**: custom_snap enabled in Mods menu?
- **Check**: Map created with custom_snap active?
- **Note**: Detection happens once per map load

### Old map won't load
- **Reason**: v1.x maps incompatible with v2.0.0
- **Solution**: Use v1.x mod version for old maps
- **Alternative**: Recreate markers in v2.0.0 (better flexibility!)

---

## Compatibility

### Requirements
- **Dungeondraft**: 1.1.1.1+
- **_Lib**: 1.2.0 (required)

### Optional Mods
- **custom_snap**: Enhanced grid snapping (auto-detected)

### Compatible Mods
- All _Lib-based mods
- Essential Utils
- Minor Utils
- Most Dungeondraft mods

### Known Incompatibilities
- **None** - If you find one, please report on [GitHub Issues](https://github.com/ChosonDev/GuidesLines/issues)

---

## Version History

### v2.0.0 (Current) - 2026-02-15
- 🎉 Complete redesign with flexible marker system
- 🚀 4 marker types: Line, Shape, Path, Arrow
- ⚠️ Breaking: v1.x maps incompatible

### v1.0.10 - 2026-02-04
- UpdateChecker integration
- Full HistoryApi support

### v1.0.9 - 2026-02-03
- _Lib-1.2.0 compatibility
- UI consolidation in tool panel

[Full changelog](CHANGELOG.md)

---

## Known Limitations

- Markers cannot be moved after placement
- Maximum tested: ~100 markers (system-dependent)
- Delete mode requires clicking within 20px of center
- No automated v1.x → v2.0.0 migration

---

## Tips & Best Practices

### For Line Markers
- Use 0°/90° for axis-aligned grids
- Use 45°/135° for diagonal perspectives
- Enable Mirror for symmetrical designs
- Adjust angle with mouse wheel while hovering

### For Shape Markers
- Use circles for room templates
- Use hexagons for hex-grid overlays
- Rotate squares to create diamond guides
- Adjust radius with mouse wheel for fine-tuning

### For Path Markers
- Place fewer points for smooth curves
- Use many points for complex shapes
- Close paths for area boundaries
- Right-click to finish, ESC to cancel

### For Arrow Markers
- Use for one-way passages
- Great for trap triggers
- Indicate flow direction in rivers
- Adjust head angle for different arrow styles

### General Tips
- Use "Snap to Grid" for precision
- Enable coordinates for exact measurements
- Use preview to verify before placing
- Remember: Ctrl+Z is your friend!
- Save your map frequently

---

## Author

**Choson**  
Created for the Dungeondraft map-making community.

### Links
- [GitHub Repository](https://github.com/ChosonDev/GuidesLines)
- [Issue Tracker](https://github.com/ChosonDev/GuidesLines/issues)
- [Releases](https://github.com/ChosonDev/GuidesLines/releases)

### Special Thanks
- **CreepyCre** (MegalomaniacMegalodon) for the [_Lib framework](https://github.com/CreepyCre/_Lib)
- **Lievven** for the custom_snap mod inspiration
- The Dungeondraft modding community

---

## License

Free to use and modify for personal and commercial projects.

**MIT License** - See [LICENSE.md](LICENSE.md) for details.

---

## Support

### Getting Help
1. Check this README's [Troubleshooting](#troubleshooting) section
2. Search existing [GitHub Issues](https://github.com/ChosonDev/GuidesLines/issues)
3. Create a new issue with:
   - Dungeondraft version
   - _Lib version
   - Steps to reproduce problem
   - Error messages (if any)

### Feature Requests
Open an issue with tag `enhancement` describing:
- Desired feature
- Use case
- Why existing features don't solve it

---

**Happy Mapping! 🗺️**

