# GuidesLines - Dungeondraft Mod

**Version:** 2.4.9
**Compatible with:** Dungeondraft 1.1.1.1 and later  
**Requires:** _Lib-1.2.0

Advanced guide system with fully customizable markers for precise map alignment and composition.

### What's New in 2.4.9

- **Top-center floating toolbar**: Marker type selection (`Line`, `Shape`, `Path`, `Fill`, `Template`) with monochrome icons, unified `Place | Move | Delete` switcher, and always-visible `Overlap Mode` buttons (disabled when inapplicable) now sit centered above the canvas, with a second context row holding compact single-row settings for the active tool (including single-row `Spiral` controls, `Fill`, and `Template`).
- **Streamlined left tool panel**: Reorganized into clean card sections (`Marker Style`, `Map Display`, `Guide Overlays`, `Cleanup`), with `Guide Overlays` (`Proximity Cross`, `Vertical Center`, `Horizontal Center`, `Grid Coordinates`) synced two-way with `ModConfig` and persisted across sessions.
- **Expanded marker context menu**: Right-clicking a marker now shows a target header (`<Type> #<ID>`) and adds `Duplicate` (click-to-place with undo/redo), `Pick Settings`, `Apply Active Color` (undoable), and `Save as Template`. Optional UnofficialPatch `SelectTool` integration exposes `Move`, `Duplicate`, `Save as Template`, `Pick Settings`, and `Delete`.

---

## ⚠️ v2.0.0 — Breaking Changes (maps from v1.x are incompatible)

**Maps saved with v2.0.0+ are NOT compatible with v1.x.  No automatic migration — recreate markers using the new system.**

## ✨ What's New since 2.0.0

- 🔷 **Custom (N-sided) shapes** — place any regular polygon with 3–50 sides
- 🖱️ **Shape mouse controls** — scroll rotates, Alt+scroll changes radius, RMB rotates +45°
- ⚙️ **Persistent settings** — preferences saved between sessions (Edit → Preferences → Mods)
- ⌨️ **Configurable hotkey** — bind a key to the Guide Markers tool (default: `9`)
- 🔌 **External API** (`GuidesLinesApi`) — other mods can place/delete/query markers programmatically
- 🏗️ **Geometry centralised** — all math lives in `GeometryUtils.gd`; rendering in `GuidesLinesRender.gd`

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
  - [External API](#external-api)
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
   - 7 subtypes: Circle, Square, Pentagon, Hexagon, Octagon, **Custom (N-sided)**, **Spiral**
   - Spiral subtype: closed strips with adjustable turns, radii, spacing, width and winding
   - Custom subtype: any regular polygon from 3 to 50 sides
   - Radius: 0.5 to 100 grid cells
   - Full rotation support (except circles)
   - **Scroll wheel** — rotates shape (5° increments)
   - **Alt + Scroll wheel** — changes radius (0.1 cell increments)
   - **Right-click (RMB)** — quick +45° rotation
   - Custom color per marker
   - Ideal for circular rooms, polygonal features, area planning

3. **Path Markers**
   - Freeform and **Spiral** subtypes; Spiral supports single-click center placement, reversal and end arrows
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

- **Mouse Wheel** (over Line Angle): Adjust angle ±5°
- **Mouse Wheel** (over Shape): Rotate shape ±5°
- **Alt + Mouse Wheel** (over Shape): Adjust radius ±0.1 cells
- **Right-Click** (Shape, before placement): Quick +45° rotation
- **Quick Angle Buttons**: 0°, 45°, 90°, 135° presets for common angles
- **Color Picker**: Independent color for each marker
- **Real-time Preview**: See exactly what you'll place
- **Settings Memory**: Each marker type remembers its last settings

### 📐 Advanced Features

- **Grid Snapping**: Respects Dungeondraft's global Snap to Grid setting; works with custom_snap mod
- **Coordinate Display**: Show grid positions on guide lines
- **Overlay System**:
  - Proximity guides (cross overlays near cursor)
  - Permanent center guides (vertical/horizontal)
  - Coordinate markers on guide lines
- **Full Undo/Redo**: Every operation is undoable (Ctrl+Z / Ctrl+Y)
- **Persistent Settings**: Overlay toggles and preferences saved across sessions (Edit → Preferences → Mods → Guides Lines)
- **Configurable Hotkey**: Bind any key to activate the tool (Edit → Preferences → Shortcuts → Guides Lines; default: `9`)
- **External API**: Other mods can interact with GuidesLines via `self.Global.API.GuidesLinesApi`
- **Auto-Updates**: GitHub release notifications via UpdateChecker

### 💾 Persistence

- Line, Shape and Path markers, Fill regions and captured templates are stored inside the map file.
- Saved geometry includes outlines modified by boolean operations, colors and marker parameters.
- After Merge, Difference, Conforming or Wrapping changes a Shape, its anchor is
  recentered between the final outline's left/right and top/bottom extremes.
  The outline stays in place; undo/redo restores both geometry and anchor.
  Empty outlines keep the last anchor. The bounds center may lie outside a
  concave region. Cut converts Shapes to Paths and keeps their start-point anchors.
- Map data has its own format version, independent of the mod release version. Format 2 adds group templates and also reads format 1 maps; saving upgrades them to format 2. Incompatible or malformed blocks load no GuidesLines objects. The next map save replaces the entire GuidesLines block using the current format, including when the current collection is empty.
- In-progress placement, dragging, previews and undo history are session state and are not saved. Templates belong to their map.

### Group templates

Template names (single markers and groups) are editable directly in the list.
Press Enter or leave the name field to save; Escape restores the previous name.
Names are trimmed, must contain 1–128 characters, and are saved with the map.
Tool shortcuts are suppressed while editing names or group transform fields.
Leaving the field, switching tools/maps or unloading restores normal input.

In **Template**, click **Create Group**, then click marker anchors or outlines to
select them. Selected markers have a faint cyan outline; click again to deselect.
**Save Group (N)** becomes available after selecting at least two markers. Empty
clicks keep the selection. **Cancel**, Escape, Move/Delete, switching marker type
or leaving the tool discards the unfinished selection.

The saved group appears in the existing template list with its marker count.
Select it to preview the whole group at the cursor. **Rotation**, **Scale (%)**
(1–10000%) and **Reset Transform** affect the entire preview around its shared
center. The wheel rotates by 5°, right-click adds 45°, and Ctrl+wheel retains
camera zoom. Numeric field focus suppresses GuidesLines shortcuts. Only the group
center snaps; member offsets stay intact. Sizes and distances use grid units,
so changing grid size resizes the entire composition uniformly.

Click to place independent copies in one undo/redo action. The source markers and
saved template stay unchanged. Groups support Line, Shape and Path, including
spirals, arrows and boolean-edited outlines. Group placement ignores Shape overlap
modes to preserve its geometry. Fill regions are not selectable group members.
Groups are saved with their map; there are no persistent group links after placement.

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
2. Check **Mods** menu → **Mod Versions** — should show "Guide Markers v2.4.9"
3. Create/open a map
4. Select **Design** category → **Guide Markers** tool (or press **`9`**)
5. Top-center floating bar should display marker type icons, `Place | Move | Delete`, `Overlap Mode`, and active tool settings; the left panel shows `Marker Style`, `Map Display`, `Guide Overlays`, and `Cleanup`

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
4. Click on map to place marker
5. Guide lines appear instantly, extending infinitely to map edges

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
   - **Custom (N-sided)** — any regular polygon from 3 to 50 sides
     - Extra **Sides** spinbox appears when Custom is selected
4. Configure settings:
   - **Radius**: 0.5–100 grid cells
     - **Alt + scroll wheel** to adjust in 0.1-cell increments
   - **Shape Angle**: 0–360° rotation (disabled for circles)
     - **Scroll wheel** to rotate in 5° increments
     - **Right-click** for quick +45° snap
     - Or use quick angle buttons (0°, 45°, 90°, 135°)
   - **Color**: Custom color picker
5. Optionally toggle **Snap to Grid** (follows Dungeondraft global setting)
6. Click to place marker at shape center
7. Shape outline appears with specified radius and rotation

**Shape Angle Behavior:**

- Square: rotates on all 4 corners
- Pentagon/Hexagon/Octagon/Custom: rotates all vertices
- Circle: all rotation controls disabled (circles have no rotation)

---

### Placing Path Markers

**Best for: complex curves, custom boundaries, organic shapes**

Choose **Path Type: Freeform** for interactive sequential placement:

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

### Spiral Markers

Choose **Shape Type: Spiral** for a closed, constant-width spiral strip, or
**Path Type: Spiral** for an open spiral centerline. Both use an Archimedean
spiral with constant radial spacing and are placed with one click at the center.
Shape outlines are guide markers, not native Dungeondraft walls.

| Setting | Meaning |
| --- | --- |
| Outer Radius / Inner Radius | Centerline radii in grid cells; Path can start at radius zero |
| Turns | Fractional turns, from 0.01 to 8 |
| Size by: Outer Radius | Enter outer radius; turn spacing is calculated |
| Size by: Turn Spacing | Enter spacing; outer radius is calculated |
| Turn Spacing | Radial centerline spacing, not the clear gap between Shape boundaries |
| Angle | Inner endpoint angle in degrees, independent of Path reversal |
| Clockwise (inner to outer) | Uncheck for counterclockwise winding |
| Width (Shape) | Full strip width, with flat end caps |
| Reverse Path | Reverse point order, including which end receives the optional arrow |

The size relation is `outer_radius = inner_radius + turns * turn_spacing`.
Shape boundaries can extend up to half the width beyond the centerline radius.
Shape width must fit the inner curvature and leave space between turns;
Path geometry ignores width (the API accepts zero). Invalid settings display
an explanation and cannot be placed. There is a
512-centerline-segment limit and automatic detail of approximately 0.02 cells;
large radii can therefore reduce the available number of turns.

Scroll rotates by 5°, **Alt+scroll** changes the selected size by 0.1 cells,
and **right-click** rotates by 45°. Grid snapping applies only to the center,
using the existing host/custom snap integration. Shape and Path remember their
own spiral settings while switching types during the current tool session.

Spiral Shapes support the existing overlap modes and Fill. Both subtypes support
move/delete, undo/redo, rotated Templates and map save/load. Boolean results are
saved as actual geometry and are not regenerated from the original settings.
Cut fragments become ordinary Freeform Paths. Settings affect new markers;
they do not parametrically edit existing boolean results.

The public API provides `place_spiral_shape_marker(position, settings = {},
color = null, apply_tool_modes = false)` and
`place_spiral_path_marker(position, settings = {}, color = null, end_arrow = false)`.
Both return the marker ID, or `-1` without placing anything on invalid input or
when the map/grid is unavailable. Shape placement ignores Conform/Wrap by default;
set `apply_tool_modes` to opt into those two policies. UI Merge/Difference/Cut
remain separate tool actions.

```gdscript
var shape_id = gl.place_spiral_shape_marker(center, {
    "outer_radius": 8.0, "inner_radius": 1.0, "turns": 2.5,
    "width": 1.0, "clockwise": true, "angle": 45.0
})
var path_id = gl.place_spiral_path_marker(center, {"reverse": true}, null, true)
```

Accepted settings keys and defaults: `outer_radius: 6.0`, `inner_radius: 1.0`,
`turns: 2.0`, `width: 1.0`, `clockwise: true`, `angle: 0.0`, `reverse: false`,
`size_by: "radius"`. The API accepts `size_by: "spacing"` as construction metadata;
API callers always supply radii and turns and calculate spacing with the relation
above. Unknown keys are rejected. Saved markers expose `marker_subtype: "Spiral"`
and a separate `spiral_settings` dictionary alongside their actual geometry.

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

- With Guides Lines active, right-click a marker's anchor or outline to open its menu
- Choose **Delete** to remove that marker
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

- **Ctrl+Z**: Undo last operation (placement, move, deletion, delete all)
- **Ctrl+Y** (or Ctrl+Shift+Z): Redo operation
- History limit: 100 operations per type
- Full state restoration (color, angle, all parameters)

#### Notes

- Choose **Move** in a marker's context menu to enter Move mode. The preview
  follows the cursor, preserving the clicked offset; left-click on the map to
  commit with the current snapping setting. Any other mouse button, wheel, key
  press or click outside the map cancels the pending movement without changing
  the marker. Move mode remains selected for ordinary drag operations.
- **Use preview** to verify placement before clicking
- Right-clicking empty map space keeps the existing path finish/preview rotation
  behavior. This menu does not require UnofficialPatch.
- With optional **UnofficialPatch** (right-click provider API v1), the standard
  **Select** tool also offers **Guide Marker → Move / Delete** near a visible
  guide marker. Move activates Guides Lines and starts its click-to-place preview;
  Delete stays in Select. Native map-object selection is unchanged.
- Line, Shape and Path outlines use cached ArrayMesh strokes, including spirals,
  arrowheads, move/placement previews and templates. Fill uses polygon rendering;
  anchor circles and coordinate labels use native drawing.
- Enable **Unofficial Patch** (`Moulk.BugFixes`) for the map to use its Select
  menu; installing the folder alone does not activate it. Native asset selection
  is unnecessary: right-click the marker's anchor or outline.
- Optional-mod discovery, custom_snap grid behavior and UnofficialPatch provider
  registration live in `scripts/integrations/OptionalMods.gd`. Providers register
  for the current map, retry late initialization and unregister on map replacement.

---

### External API

`GuidesLinesApi` is available to other mods via `self.Global.API.GuidesLinesApi` after a map is loaded.

**Check readiness:**

```gdscript
if self.Global.API.has("GuidesLinesApi") and self.Global.API.GuidesLinesApi.is_ready():
    var gl = self.Global.API.GuidesLinesApi
```

**Or listen for late registration:**

```gdscript
self.Global.API.connect("api_registered", self, "_on_api_registered")
func _on_api_registered(api_id, _api):
    if api_id == "GuidesLinesApi":
        var gl = self.Global.API.GuidesLinesApi
```

**Placement:**

```gdscript
var id = gl.place_line_marker(Vector2(512, 512), 45.0)            # Line at 45°
var id = gl.place_shape_marker(Vector2(512, 512), "Hexagon", 3.0) # Hexagon r=3
var id = gl.place_shape_marker(pos, "Custom", 2.0, 0.0, 8)        # Octagon (custom)
var id = gl.place_path_marker([p1, p2, p3], true)                  # Closed path
var id = gl.place_arrow_marker(p1, p2, 60.0, 30.0)                # Arrow
```

**Queries:**

Hover consumers can use `compute_fill_polygon_quiet(coords)` and
`find_nearest_marker_by_geometry_quiet(coords, radius = 100.0)`. They follow the
normal query rules without query diagnostics and do not allocate IDs or record
history. Fill results also include `source_polygons`, snapshots of the containing
Shape outlines, alongside `polygon`, `marker_ids` and `fill_type`.

`get_build_preview_target(coords, outline = false, known_zone_hash = "")` performs
the cheap target selection before clipping. It returns an opaque SHA-256
`zone_hash`; an empty string means no target. Passing the same hash returns only
`{zone_hash}`. A different target also returns `kind = "Fill"` with a `fill`
snapshot, or `kind = "Path"` with a `marker` snapshot. Outline queries preserve
the existing nearest-marker/Path priority. Disconnected components have separate
hashes even when their containing marker IDs match. Snapshots are independent;
callers cannot modify retained cache data.

GuidesLines owns the derived fill-zone cache. A zone is calculated on its first
query, rather than enumerating every possible intersection during marker placement.
Dependencies include containing shapes and possible subtractors/containers within
their conservative bounds. Marker edits, deletion, undo/redo and new shapes entering
those bounds invalidate affected zones; distant edits preserve them. Geometry
fingerprints are checked after mutations, not for every cursor coordinate.
Quiet fill queries reuse this cache; normal click queries recompute geometry.
Unchanged marker polygons reuse their existing fingerprints after a revision;
cached zones retain packed hit-test geometry. A fresh click replaces the visited
component even when JSON rounding changes its key after loading.

Cold fill calculations test containment before edge-pair intersections. For simple
base polygons, cutters are combined with native boolean unions and final holes are
stitched once. Already bridged inputs and cutter unions containing islands retain
the sequential algorithm. Cached cutter bounds skip native unions for disjoint
pairs; the bounds scan remains quadratic in cutter count. Hole stitching selects
the shortest visible bridge across remaining holes and excludes holes belonging
to nested islands. Candidate vertex pairs are reused as the boundary grows.
Save fingerprints are computed only for markers needed by visited zones.

Visited zones are saved in the optional `zones` block of the existing map data,
with source marker IDs/fingerprints, polygons and checksums. Old maps remain valid.
Load validates dependencies and grid size before reuse; invalid/stale derived data
is discarded without rejecting markers. The LRU cache keeps up to 128 zones and
131072 vertices, retaining one oversized current target to prevent repeated clipping
(oversized targets are not persisted). Renderer/tool settings do not belong to this
geometry cache.

`get_geometry_revision()` returns a session-only invalidation counter, or `-1`
before tool initialization. It changes on marker edits, boolean operations,
undo/redo, map reload and grid-size changes; fill edits may also invalidate it.
Track API and world identity separately. A revision is not a region ID: moving
inside one Shape can select another boolean component. Feature-detect these
development API additions with `has_method()` when supporting older installations.

```gdscript
var nearest = gl.find_nearest_marker_by_geometry(cursor_pos, 100.0)
# Returns: { id, marker_type, position, point (closest geometry point), distance, ... }

var hit = gl.find_line_intersection(line_a, line_b, cursor_pos, 80.0)
# Returns: { point, distance, on_positive, marker_id, marker_type, ... }
```

`get_shape_state()` returns a fresh snapshot containing `ready`,
`active_shape_radius` (grid cells), `active_shape_angle` (degrees),
`active_shape_sides`, `active_color`, `active_shape_preset` and an independent
`active_shape_spiral` settings dictionary. Before initialization it returns
`{"ready": false}`. It is suitable for polling shape previews each frame;
consumers supporting older versions can fall back to `get_tool_state()` when
`has_method("get_shape_state")` is false. Continue calling `set_shape_preview()`
every frame to keep a preview alive, and `clear_shape_preview()` when leaving it.
`set_shape_preview()` remains a regular-polygon preview. For Spiral, read the
spiral settings explicitly; the polygon radius/angle/sides fields retain their
regular-polygon values. `get_tool_state()` also includes `active_path_subtype`
and an independent `active_path_spiral` dictionary.

**Template and group API:**

`get_placement_state()` adds `active_marker_type`, `active_template_index`,
`active_template_id` (-1 when none), `template_capture_mode`,
`template_rotation_offset` (degrees) and `template_scale` (1 = 100%) to the Shape
snapshot. Poll it when an external tool can consume the active Template tab.
`get_templates()` returns independent map-scoped snapshots with stable IDs and
names; groups have `kind = "group"` and `items`, singles have `data`.

```gdscript
var templates = gl.get_templates()
if not templates.empty():
 gl.select_template(templates[0].id) # Also activates the Template tab.
 gl.set_template_transform(30.0, 1.5) # Absolute sidebar rotation / uniform scale.

# World-space snapshots; does not place, allocate IDs, snap or modify sidebar state.
var markers = gl.get_template_markers(position, -1, 15.0, 2.0)
# -1: selected template, adds 15 degrees and multiplies sidebar scale by 2.
# Explicit stable template ID: rotation/scale start at 0 degrees / 1x instead.

# Same transform; one plain stamp and one history record. Returns new IDs or [].
var ids = gl.place_template(position, -1, 15.0, 2.0)

# One-frame preview, using the same geometry. Refresh each frame while active.
gl.set_template_preview(position, 15.0, 2.0)
gl.clear_shape_preview() # Clears the shared Shape/Template preview channel.
```

Resolved markers contain no IDs. Positions, Path `marker_points` and Shape
`shape_primitives` use world-space Vector2 values; colors are Color values.
Shapes additionally expose `polygon`; Paths/Lines expose `outline_points` and
`closed`. Line outlines are clipped to map bounds. Group members share one pivot
at the center of their captured bounds. Scaling changes sizes and member offsets
together. Single templates support the same uniform scaling, including their UI.

`apply_marker_geometry(marker, mode = "Normal")` consumes a resolved marker and
records its placement/edit. Shape modes are `Normal`, `Merge`, `Conform`, `Wrap`
and `Difference`; boolean result dictionaries match the existing Shape methods.
Normal returns `marker_id` and `marker_polygon`. Merge without overlaps returns
empty `affected_markers`/`absorbed_marker_ids` and leaves placement to the caller.
Line/Path accept Normal only. Invalid input returns `{}` before mutation.
Use `begin_history_capture()` / `end_history_capture()` around sequential edits
when another mod owns the compound undo action. Room Builder demonstrates this.

**Signals:**

```gdscript
gl.connect("marker_placed", self, "_on_marker_placed")  # (marker_id, position)
gl.connect("marker_deleted", self, "_on_marker_deleted") # (marker_id)
```

---

## Overlay Features

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
| ---------- | -------- |
| **`9`** (default, configurable) | Activate Guide Markers tool |
| **ESC** | Cancel path/arrow placement |
| **Right-Click** | Marker: Move/Delete menu. Empty map: finish path (open) / Shape or Template +45° |
| **Ctrl+Z** | Undo last operation |
| **Ctrl+Y** / **Ctrl+Shift+Z** | Redo operation |
| **Scroll Wheel** (Line, over Angle) | Adjust angle ±5° |
| **Scroll Wheel** (Shape, in viewport) | Rotate shape ±5° |
| **Alt + Scroll Wheel** (Shape) | Adjust radius ±0.1 cells |

---

## Technical Details

### Architecture

**Clean separation of concerns:**

1. **GuidesLines.gd** — Main coordinator
   - Registers with Dungeondraft and _Lib API
   - Creates tools and manages lifecycle
   - Handles save/load operations
   - Registers `GuidesLinesApi` with `_Lib`'s ApiApi

2. **GuidesLinesTool.gd** — Tool logic
   - Marker creation and storage
   - UI interactions and settings management
   - Path/Arrow placement state machines
   - Custom_snap integration
   - History record creation
   - Public bridge methods for external API (`api_place_marker`, `api_delete_marker_by_id`)

3. **MarkerOverlay.gd** — Rendering engine
   - Draws all marker types and guide lines
   - Handles preview rendering
   - Path/Arrow interactive previews
   - Mouse wheel / RMB input handling

4. **GuidesLinesRender.gd** — Drawing primitives
   - Centralised static helpers for lines, circles, polygons, arrows, text
   - All overlays delegate drawing calls here

5. **GeometryUtils.gd** — Math library
   - Polygon/vertex generation, line clipping, ray intersection
   - Closest-point and line–geometry intersection helpers used by the API

6. **GuideMarker.gd** — Data model
   - Stores marker type and all parameters
   - Serialization for save/load
   - Caches computed geometry (invalidated on property change)

7. **GuidesLinesApi** — External API
   - Signals: `marker_placed`, `marker_deleted`, `all_markers_deleted`, `settings_changed`
   - Placement: `place_line_marker()`, `place_shape_marker()`, `place_path_marker()`, `place_arrow_marker()`
   - Explicit plain Shape: `place_shape_marker_plain(position, radius, angle, sides, color)`
     ignores active Conform/Wrap modes without changing the user's mode settings.
   - Deletion: `delete_marker()`, `delete_all_markers()`
   - Compound history: `begin_history_capture()` / `end_history_capture()` capture
     synchronous edits for a caller-owned history record. Reject nested capture,
     never yield between calls, and always end a successful capture, including on
     failure. Undo returned records in reverse order; redo in execution order.
     The caller must record the compound action or roll it back. This addition is
     currently unreleased; detect both methods before starting edits.
   - Queries: `get_markers()`, `get_marker()`, `find_nearest_marker()`, `find_nearest_marker_by_geometry()`, `find_nearest_geometry_point()`, `find_line_intersection()`
   - Settings: `set_cross_guides()`, `set_permanent_vertical/horizontal()`, `get_settings()`

8. **CrossOverlay.gd & PermanentOverlay.gd** — Overlay systems
   - Proximity-based and permanent guides
   - Coordinate display system
   - Grid compatibility layer

### Integration

- **_Lib-1.2.0 API**: Modern `self.Global.API` pattern
- **Logger API**: Professional logging with class-scoped instances
- **HistoryApi**: Full undo/redo with custom record classes
- **ModConfigApi**: Persistent settings panel (Edit → Preferences → Mods)
- **InputMapApi**: Configurable hotkey (Edit → Preferences → Shortcuts)
- **OptionalMods**: Late discovery of optional APIs and map-scoped integrations
- **UpdateChecker**: Automatic GitHub release notifications
- **GuidesLinesApi**: External inter-mod API registered as `self.Global.API.GuidesLinesApi`
- **custom_snap**: Detects and uses custom grid snapping
- **UnofficialPatch API v1**: Guide Marker actions in the standard Select menu

### Save Format

Markers stored in map file under `guide_markers` key:

```json
{
  "marker_type": "Line|Shape|Path|Arrow",
  "position": {"x": float, "y": float},
  "color": {"r": float, "g": float, "b": float, "a": float},

  // Line-specific
  "angle": float (0-360),
  "mirror": bool,

  // Shape-specific
  "shape_radius": float,
  "shape_subtype": "Circle|Square|Pentagon|Hexagon|Octagon|Custom",
  "shape_angle": float (0-360),
  "shape_sides": int (3-50, used when subtype == "Custom"),

  // Path-specific
  "marker_points": [{"x": float, "y": float}, ...],
  "path_closed": bool,

  // Arrow-specific
  "marker_points": [{"x": float, "y": float}, {"x": float, "y": float}],
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
- **UnofficialPatch**: Guide Marker → Move / Delete in Select (right-click API v1;
  verified against the installed 1.7.4 sources)

### Compatible Mods

- All _Lib-based mods
- Essential Utils
- Minor Utils
- Most Dungeondraft mods

### Known Incompatibilities

- **None** - If you find one, please report on [GitHub Issues](https://github.com/ChosonDev/GuidesLines/issues)

---

## Version History

### v2.4.9 (Current) — 2026-11-28

- Floating top-center two-row toolbar over the canvas: icon-only marker type selector (`Line`, `Shape`, `Path`, `Fill`, `Template`), unified `Place | Move | Delete` switcher, always-visible `Overlap Mode` bar (disabled when inapplicable), and compact single-row context settings for all five marker types (including single-row `Spiral` controls).
- Reorganized left tool panel into styled card sections (`Marker Style`, `Map Display`, `Guide Overlays`, `Cleanup`) with two-way `ModConfig` sync and session persistence for `Guide Overlays`.
- Expanded marker right-click context menu (`<Type> #<ID>` header, `Move`, `Duplicate`, `Pick Settings`, `Apply Active Color`, `Save as Template`, `Delete`) and UnofficialPatch `SelectTool` submenu (`Move`, `Duplicate`, `Save as Template`, `Pick Settings`, `Delete`).
- Recursive disabling of nested and top-bar controls in `Move`/`Delete` modes, floating-panel canvas hover gating, and `GuideMarker.set_property("color", ...)` support.
- All 176 standalone Godot tests pass (18,516 assertions).

### v2.4.8 — 2026-11-23

- Route canvas mouse clicks, right-clicks and wheel events through `ModBaseTool._ContentInput` (`on_content_input`) and guard `_input` on active modals, preventing Guides Lines from intercepting clicks meant for third-party context menus and popup overlays.
- All 175 standalone Godot tests pass; the user confirmed the fix working in Dungeondraft.

### v2.4.7 — 2026-11-11

- Marker Move/Delete context menu and optional UnofficialPatch integration in Select.
- Cached ArrayMesh strokes for Line, Shape and Path, with mirrored-line batching and translated Path mesh reuse.
- Fix Path finalization priority, popup cleanup and optional custom_snap discovery; bound dense-grid coordinate sampling.
- All 175 standalone Godot tests pass; the user confirmed the changes working in Dungeondraft.

### v2.4.6 — 2026-11-10

- Quiet build-preview queries with persistent fill-zone caching and targeted invalidation.
- Fix holes, nested islands, disconnected contours and tangent boundaries in fill and Shape boolean operations.
- Reduce repeated geometry calculations; all 155 standalone tests pass and user testing confirmed the changes in Dungeondraft.

### v2.4.5 — 2026-11-09

- Group templates with toggle selection, contour highlights, shared rotation/scale and one undo/redo action per stamp.
- Inline renaming of single/group templates with shortcut suppression while typing.
- Public template/group geometry, transform, preview and placement API for BuildingPlanner Room and other consumers.
- Map format 2 stores group templates and reads format 1 maps.
- Boolean Shape edits recenter anchors on final geometry bounds and restore positions through undo/redo.
- All 127 standalone Godot tests pass; the user confirmed the current changes working in Dungeondraft.

### v2.4.4 — 2026-11-09

- Fill and `GuidesLinesApi.compute_fill_polygon()` preserve inner holes in nested and overlapping Shapes, fixing floor fills between inner rings in BuildingPlanner.
- The nested-ring fix was confirmed working by user testing in Dungeondraft.

### v2.4.3 — 2026-11-08

- Preview drawing is independent of placed markers and fills, reducing repeated work while moving the cursor.
- Connected Shape outlines use batched polyline drawing while preserving Cut/Difference gaps, moved geometry and rotated templates.
- User testing in Dungeondraft with many different spirals did not reproduce the previously reported system freeze.

### v2.4.2 — 2026-11-08

- Shape/Spiral closed strips and Path/Spiral open paths, with adjustable radii, turns, spacing, direction and rotation.
- Shape width, Path reversal and end arrows; integration with templates, Shape overlap modes, Fill, undo/redo and map saving.
- Rendering and geometry performance improvements, template fixes and expanded regression tests.

### v2.4.1 — 2026-11-04

- Technical maintenance: code cleanup, bug fixes, performance improvements and expanded regression tests.
- Markers, fill regions and marker templates are saved and restored with the map.

See [CHANGELOG.md](CHANGELOG.md) for the complete release history.

### v2.1.0 — 2026-02-21

- 🏗️ Geometry centralised into `GeometryUtils.gd` (Phase 3)
- Internal API helpers extracted; no public signature changes

### v2.0.11 — 2026-02-21

- 🔌 `GuidesLinesApi` external mod API with signals, placement, deletion, spatial queries

### v2.0.10 — 2026-02-19

- ➕ Custom (N-sided) shape subtype (3–50 sides)

### v2.0.9 — 2026-02-19

- 🖱️ Shape mouse controls: scroll = rotate, Alt+scroll = radius, RMB = +45°

### v2.0.8 — 2026-02-19

- ⚙️ Persistent settings via ModConfigApi; configurable hotkey

### v2.0.7 — 2026-02-17

- Removed Snap to Grid checkbox; respects Dungeondraft global snap

### v2.0.6 — 2026-02-17

- Scripts reorganised into subdirectories (`tool/`, `render/`, `overlays/`, `guides/`, `utils/`)

### v2.0.5 — 2026-02-17

- `GuidesLinesRender.gd` centralises all drawing primitives

### v2.0.4 — 2026-02-17

- `GeometryUtils.gd` created; polygon, clipping, ray math consolidated

### v2.0.3 — 2026-02-16

- ⚡ Geometry caching; expensive trig removed from render loop

### v2.0.0 — 2026-02-15

- 🎉 Complete redesign: Line, Shape, Path, Arrow markers
- ⚠️ Breaking: v1.x maps incompatible

### v1.0.10 — 2026-02-04

- UpdateChecker + HistoryApi

### v1.0.9 — 2026-02-03

- _Lib-1.2.0 compatibility

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
- **Scroll wheel** to rotate quickly; **Alt+scroll** to resize
- **Right-click** for instant +45° snap rotation
- Use **Custom** subtype for any regular polygon (3–50 sides)

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
