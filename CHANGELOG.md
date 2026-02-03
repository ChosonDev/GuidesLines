# Changelog

All notable changes to the Guides Lines mod will be documented in this file.

## [1.0.10] - 2026-02-04

### Added
- **UpdateChecker Integration**: Automatic update notifications
  - Integrated with _Lib UpdateChecker API for GitHub release tracking
  - Automatic version checking on startup
  - Visual notifications when new versions are available
  - One-click access to download page from "Mod Versions" window (Mods menu)
  - Follows semantic versioning (SemVer 2.0.0) for proper version comparison

- **HistoryApi Integration**: Full undo/redo support for marker operations
  - Press Ctrl+Z to undo marker placement/deletion
  - Press Ctrl+Y to redo marker placement/deletion
  - History tracking for individual marker placement (limit: 100 records)
  - History tracking for individual marker deletion (limit: 100 records)
  - History tracking for "Delete All Markers" operation
  - Proper integration with Dungeondraft's native undo/redo system
  - Seamless cooperation with other mods using HistoryApi

### Fixed
- Corrected Logger API usage to properly use ClassInstancedLogger pattern
- Fixed unsupported format specifier %v (changed to %s for Vector2 output)
- Fixed Global.API references to use parent_mod.Global.API for proper _Lib access

### Technical Changes
- Implemented custom History Record classes:
  - `PlaceMarkerRecord` - tracks marker creation with full state
  - `DeleteMarkerRecord` - tracks single marker deletion with restoration data
  - `DeleteAllMarkersRecord` - tracks bulk deletion with full restoration
- Added record type identifiers for proper history grouping:
  - `GuidesLines.PlaceMarker` - for placement operations
  - `GuidesLines.DeleteMarker` - for deletion operations
  - `GuidesLines.DeleteAll` - for bulk deletion
- UpdateChecker configured for GitHub repository: Choson/GuidesLines
- History records implement proper `redo()`, `undo()`, and `record_type()` methods
- Max count limiting prevents history overflow (100 records per operation type)

## [1.0.9] - 2026-02-03

### Changed
- **UI Redesign**: All settings moved to Guide Markers tool panel
  - Removed ModConfigApi settings menu (compatibility issues with _Lib-1.2.0)
  - All guide overlay settings now accessible directly in tool panel
  - More streamlined and accessible user experience
  - Settings organized in logical sections: Marker Types, Options, and Guide Overlays

### Fixed
- **_Lib-1.2.0 Compatibility**: Complete rewrite for new API structure
  - Fixed Logger API usage (removed non-existent `for_mod()` method)
  - Updated to use `self.Global.API` instead of `Global.API`
  - Fixed ResourceLoader cache parameter (changed from `true` to `false`)
  - Corrected ModRegistry API usage for mod detection
  - All API calls now conform to _Lib-1.2.0 standards
- Fixed integration with Custom Snap Mod (Lievven.Snappy_Mod)
- Markers now correctly snap to custom grid when Custom Snap Mod is enabled
- Improved mod detection using proper unique_id lookup instead of searching for field name

### Technical Changes
- Removed ModConfig integration (ModConfigApi builder)
- Added new UI callbacks: `_on_cross_guides_toggled`, `_on_perm_vertical_toggled`, `_on_perm_horizontal_toggled`, `_on_perm_coordinates_toggled`
- Updated Logger initialization to use InstancedLogger directly
- Fixed snappy_mod detection to work with new ModRegistry structure
- Removed `mod_config` and `config_initialized` variables
- Simplified `_init_mod_config()` removed entirely

## [1.0.8] - 2026-02-01

### Added
- **Logger API Integration**: Professional structured logging system
  - Replaced all `print()` calls with Logger API for better diagnostics
  - Added log levels (debug, info, error) for different message types
  - Automatic mod name prefix in all log messages
  - Better error tracking and debugging capabilities

- **HistoryApi Integration**: Full undo/redo support
  - Press Ctrl+Z to undo marker placement
  - Press Ctrl+Y to redo marker placement
  - Undo/redo for individual marker deletion
  - Undo/redo for "Delete All Markers" operation
  - Seamless integration with Dungeondraft's native history system

- **ModConfigApi Integration**: Professional settings panel
  - Replaced manual UI creation with ModConfigApi builder
  - Settings now integrated into Dungeondraft's Preferences window
  - Automatic saving/loading of all settings
  - Clean, organized settings categories:
    - Proximity Guides (cross guides toggle)
    - Permanent Guides (vertical/horizontal lines, coordinates)

### Improved
- **ModRegistry Integration**: Enhanced mod detection
  - Better detection of custom_snap mod using ModRegistry
  - Shows detected mod name and version in logs
  - More reliable cross-mod compatibility
  - Graceful fallback if ModRegistry not available

- **Code Quality**: Significant refactoring
  - Removed ~70 lines of manual UI code
  - Cleaner separation of concerns
  - Better error handling throughout
  - More maintainable codebase

### Technical Changes
- Added LOGGER variable to main mod and tool classes
- Implemented _init_mod_config() for ModConfigApi setup
- Added history action handlers: _do_place_marker, _undo_place_marker, etc.
- Removed manual settings panel creation (replaced by ModConfigApi)
- Removed manual toggle callback functions
- Enhanced snappy_mod detection with proper mod info retrieval

## [1.0.7] - 2026-02-01

### Updated
- **Compatibility Update**: Updated for _Lib 1.2.0 and Dungeondraft 1.1.1.1
  - Fixed snappy_mod detection to work with new _Lib API structure
  - Replaced unsafe `_get_property_list()` access with safe `get()` method
  - Improved compatibility with _Lib's new InstancedApiApi system
  - Added _Lib as explicit dependency

### Technical Changes
- Simplified snappy_mod detection logic using defensive programming
- Removed iteration through property list in favor of direct get() call
- Updated dd_version requirement to 1.1.1.1

## [1.0.6] - 2026-01-17

### Fixed
- **Critical Fix**: Application crash when `custom_snap` mod is not activated
  - Fixed incompatibility with Godot 3.4's property access mechanism for dynamic properties
  - Centralized `snappy_mod` detection in main mod file (`GuidesLines.gd`)
  - Implemented single-check optimization: `snappy_mod` availability is now checked only once after map load
  - Removed unsafe property access methods that caused crashes with _Lib API
  - All overlay classes now use cached reference to `snappy_mod` instead of performing runtime checks

### Improved
- **Smart Coordinates Toggle**: "Show Grid Coordinates" option now automatically disables when no guide lines are active
  - In Guide Markers tool: disabled when no marker line types are selected
  - In Guide Settings panel: disabled when both permanent center lines are off

### Technical Changes
- Replaced `cached_api` with `cached_snappy_mod` in tool and overlay classes
- Added `snappy_mod_checked` flag to prevent redundant API property list queries
- Simplified `_get_custom_snap()` methods to return cached reference
- Removed all debug logging statements
- Added `update_coordinates_checkbox_state()` method in `GuidesLinesTool`
- Added `settings_coords_checkbox` reference in main mod for dynamic UI updates

## [1.0.5] - Previous Version

### Features
- Advanced guide lines system with placeable markers
- Multiple marker types: vertical, horizontal, diagonal (45° and 135°)
- Grid coordinate display on guide lines
- Snap to grid functionality with custom_snap mod support
- Delete mode for marker removal
- Save/load markers with map files
- Optional proximity-based cross guides
- Optional permanent center guide lines

