# Menu Bar Component Implementation Plan

**Component:** Menu Bar (Playback.app component)
**Last Updated:** 2026-02-07

## Implementation Checklist

### Menu Bar Icon Component
- [ ] Implement menu bar icon with status states
  - Source: `Playback/MenuBar/MenuBarView.swift`
  - States: Recording active (red filled circle), Recording paused (gray outlined circle), Error state (exclamation mark)
  - SF Symbols: `record.circle.fill`, `record.circle`, `exclamationmark.circle.fill`
  - Icon size: 16×16 points (standard menu bar icon size)
  - Color: System red (#FF3B30) for recording, system gray for paused, system red for error
  - Location: macOS menu bar (right side)
  - Animation: Smooth 0.2s fade transition between states

- [ ] Implement icon state management
  - Source: `Playback/MenuBar/MenuBarController.swift`
  - Property: `@Published var iconState: IconState`
  - Enum values: `.recording`, `.paused`, `.error`
  - Auto-update based on recording service status

- [ ] Implement tooltip behavior
  - Dynamic tooltips: "Playback: Recording", "Playback: Paused", "Playback: Error (click for details)"
  - Update tooltip text when state changes

### Dropdown Menu Implementation
- [ ] Create dropdown menu structure
  - Source: `Playback/MenuBar/MenuBarView.swift`
  - Menu items: Record Screen toggle, Open Timeline, Settings, Diagnostics, About, Quit
  - Separators between logical groups
  - Menu width: Auto-sizing (minimum 220px)
  - Font: System default (13pt San Francisco)
  - Padding: 8px vertical between items, 12px horizontal
  - Background: System standard menu background with blur effect

- [ ] Implement "Record Screen" toggle
  - Type: NSMenuItem with NSSwitch control (inline toggle)
  - Style: Blue toggle when ON, gray when OFF
  - Action: Enable/disable recording via LaunchAgent
  - Visual feedback: Icon changes immediately, menu remains open during toggle
  - Persist state in config.json field: `recording_enabled`
  - Loading state: Show spinner briefly while LaunchAgent processes command

- [ ] Implement "Open Timeline" menu item
  - Shortcut hint: Option+Shift+Space (⌥⇧Space) displayed on right side in gray
  - Action: Show timeline window
  - Disabled state: When no recordings exist (grayed out with reduced opacity)
  - Integration: Uses shared window management
  - Icon: Optional timeline icon on left (SF Symbol: `clock.arrow.circlepath`)

- [ ] Implement "Settings" menu item
  - Shortcut: Command+Comma (⌘,) displayed on right side in gray
  - Icon: Gear icon (SF Symbol: `gearshape`)
  - Action: Open settings window via NSApp.sendAction
  - Behavior: Brings existing window to front if already open

- [ ] Implement "Diagnostics" menu item
  - Badge: Show warning/error count if any (red circle with white number)
  - Badge style: 16px diameter, positioned on right side before shortcut area
  - Icon: Diagnostic icon (SF Symbol: `stethoscope`)
  - Action: Open diagnostics window
  - Real-time badge updates via Combine publishers

- [ ] Implement "About Playback" menu item
  - Action: Show standard macOS about panel
  - Display version info from bundle

- [ ] Implement "Quit Playback" menu item
  - Shortcut: Command+Q (⌘Q) displayed on right side in gray
  - Confirmation dialog: Modal alert with title "Stop recording and quit?"
  - Dialog buttons: "Cancel" (default), "Quit" (destructive style in red)
  - Dialog message: "Recording will be stopped and the app will close. Unprocessed screenshots will remain for later processing."
  - Action: Stop all services via launchctl unload, then quit entire app
  - No confirmation if recording is already stopped

### Settings Window - General Tab
- [ ] Create settings window shell
  - Source: `Playback/Settings/SettingsWindow.swift`
  - Title: "Playback Settings"
  - Size: 600×500 points (fixed, non-resizable)
  - Sidebar navigation: 150px width, light gray background (#F5F5F5)
  - Content area: 450px width, white background
  - Sidebar items: Icons + labels, 32px height per item, 8px padding
  - Selected item: Blue highlight with white text
  - Window style: Standard macOS settings window with toolbar
  - Minimum macOS: 12.0 (Monterey)

- [ ] Implement General tab layout
  - Source: `Playback/Settings/GeneralSettingsView.swift`
  - Icon: SF Symbol `gearshape` in sidebar
  - Sections: Launch at Login, Global Shortcuts, Notifications, Permissions
  - Section headers: Bold 13pt San Francisco, 20px top margin
  - Section spacing: 16px between sections
  - Content padding: 20px all sides

- [ ] Implement "Launch at Login" control
  - Type: Checkbox (NSSwitch style toggle in SwiftUI)
  - Label: "Launch Playback at login"
  - Default: ON
  - Uses: ServiceManagement framework (SMAppService.mainApp)
  - Platform: macOS 13.0+ (with fallback for macOS 12)
  - Action: Register/unregister login item
  - Error handling: Show inline error message if registration fails
  - Style: 300px max width, left-aligned

- [ ] Implement "Open Timeline Shortcut" field
  - Type: Hotkey recorder field (custom SwiftUI component)
  - Label: "Open Timeline:"
  - Default: Option+Shift+Space (⌥⇧Space)
  - Field style: 200px width, light gray border, rounded corners, center-aligned text
  - Recording state: Blue border when active, "Press keys..." placeholder
  - Validation: Check for conflicts with system shortcuts, show warning icon if conflict
  - Clear button: Small X button on right to reset to default
  - Persist in config.json field: `timeline_shortcut`

- [ ] Implement notification preferences
  - Type: Checkboxes (4 options), vertically stacked with 8px spacing
  - Option 1: "Error notifications" - Default ON, label suffix "(recommended)" in gray
  - Option 2: "Crash notifications" - Default ON, label suffix "(recommended)" in gray
  - Option 3: "Disk full notifications" - Default ON, label suffix "(recommended)" in gray
  - Option 4: "Recording status notifications" - Default OFF, label suffix "(optional)" in gray
  - Style: Standard checkbox (18px), 6px gap to label text
  - Persist in config.json fields: `notify_errors`, `notify_crashes`, `notify_disk_full`, `notify_status`

- [ ] Implement permission status display
  - Section header: "Required Permissions"
  - Layout: Two rows, one per permission, 40px height each
  - Row 1: "Screen Recording" with status indicator
  - Row 2: "Accessibility" with status indicator
  - Status indicators: Green checkmark (✓) or red X (✗), 20px size
  - Button style: "Open System Preferences" - secondary style, 140px wide, right-aligned
  - Button action: Opens System Preferences > Privacy & Security > specific pane
  - Auto-refresh: Check status when window gains focus or every 2 seconds while visible
  - Background: Light yellow (#FFF9E6) if any permission missing

### Settings Window - Recording Tab
- [ ] Implement Recording tab layout
  - Source: `Playback/Settings/RecordingSettingsView.swift`
  - Icon: SF Symbol `record.circle` in sidebar
  - Sections: Recording Behavior, Pause Recording When
  - Content padding: 20px all sides

- [ ] Display recording interval (read-only)
  - Label: "Recording Interval:"
  - Value: "2 seconds (not configurable)" in gray text
  - Style: Form row layout, label left-aligned, value right-aligned
  - Tooltip: "Screenshots are captured every 2 seconds when recording is active"

- [ ] Implement "Pause When Timeline Open" checkbox
  - Label: "Pause recording when Timeline window is open"
  - Default: ON
  - Type: Checkbox (standard 18px)
  - Action: Update recording service configuration in real-time
  - Persist in config.json field: `pause_when_timeline_open`
  - Help text below: "Prevents recording your own timeline browsing activity" (gray, 11pt)

- [ ] Add informational note
  - Text: "Playback will always pause recording when your screen is locked, display is off, or screensaver is active."
  - Style: Light blue info box (#E3F2FD), 12px padding, rounded 6px corners
  - Icon: Info icon (SF Symbol `info.circle`) on left, 16px size
  - Text color: Dark blue (#1565C0)
  - Width: Full content width with 20px margin

### Settings Window - Processing Tab
- [ ] Implement Processing tab layout
  - Source: `Playback/Settings/ProcessingSettingsView.swift`
  - Icon: SF Symbol `gearshape.2` in sidebar
  - Sections: Processing Schedule, Last Processing Run, Manual trigger
  - Content padding: 20px all sides

- [ ] Implement processing interval dropdown
  - Label: "Run processing every:"
  - Type: Popup button (NSPopUpButton style in SwiftUI)
  - Options: "1 minute", "5 minutes (recommended)", "10 minutes", "15 minutes", "30 minutes", "60 minutes"
  - Default: 5 minutes (recommended)
  - Width: 200px
  - Action: Update LaunchAgent plist StartInterval key and reload via launchctl
  - Help text: "How often to convert screenshots to video chunks" (gray, 11pt)
  - Persist in config.json field: `processing_interval_minutes`

- [ ] Implement last run status display
  - Section header: "Last Processing Run"
  - Layout: 3 rows with label-value pairs
  - Row 1: "Last run:" - Timestamp (e.g., "2 minutes ago" or "Jan 7, 2026 3:45 PM")
  - Row 2: "Duration:" - Time taken (e.g., "1.2 seconds")
  - Row 3: "Status:" - Colored indicator + text (green "Success", red "Failed", gray "Never run")
  - Source: Parse from processing logs at `~/Library/Logs/Playback/processing.log`
  - Auto-refresh: On tab activation and every 10 seconds while visible
  - Style: Monospaced font for values, 12pt size

- [ ] Implement "Process Now" button
  - Label: "Process Now"
  - Style: Primary button, blue background, white text, 120px width
  - Action: Manually trigger processing via `launchctl kickstart -k gui/$UID/com.playback.processing`
  - Disabled state: While processing is running (gray background, reduced opacity)
  - Progress indicator: Inline spinner on button during processing with text "Processing..."
  - Success feedback: Green checkmark briefly, then notification
  - Error feedback: Red X briefly, then notification with error details
  - Tooltip when disabled: "Processing is already running"

### Settings Window - Storage Tab
- [ ] Implement Storage tab layout
  - Source: `Playback/Settings/StorageSettingsView.swift`
  - Icon: SF Symbol `internaldrive` in sidebar
  - Sections: Current Usage, Location, Cleanup Policies
  - Content padding: 20px all sides

- [ ] Implement current usage display
  - Section header: "Current Storage Usage"
  - Layout: 3 rows with label-value pairs, right-aligned values
  - Row 1: "Screenshots (temp):" - Size in GB (e.g., "1.2 GB")
  - Row 2: "Videos (chunks):" - Size in GB (e.g., "45.8 GB")
  - Row 3: "Total:" - Size in GB, bold weight (e.g., "47.0 GB")
  - Calculation: Scan `~/Library/Application Support/Playback/data/temp/` and `.../chunks/` on tab open
  - Format: GB with one decimal place, use "MB" if under 1 GB
  - Refresh button: Small circular arrow icon button, 24px size, right of Total row
  - Loading state: Show spinner during calculation

- [ ] Implement storage location display
  - Section header: "Storage Location"
  - Label: "Data directory:" on left
  - Path display: Full path in monospace font, gray color, 11pt
  - Default path: `~/Library/Application Support/Playback/data`
  - Button: "Open in Finder" - secondary style, 120px width
  - Button icon: Finder icon (SF Symbol `folder`)
  - Button action: Open directory via `NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)`
  - Layout: Path on one line, button below with 8px spacing

- [ ] Implement temp retention policy dropdown
  - Section header: "Cleanup Policies"
  - Label: "Delete screenshots older than:"
  - Type: Popup button (NSPopUpButton style)
  - Options: "Never", "1 day", "1 week (recommended)", "1 month"
  - Default: "1 week"
  - Width: 200px
  - Applied: During next processing run (cleanup happens automatically)
  - Help text: "Temporary screenshots are kept for debugging" (gray, 11pt)
  - Persist in config.json field: `temp_retention_days` (values: -1, 1, 7, 30)

- [ ] Implement recording retention policy dropdown
  - Label: "Delete video recordings older than:"
  - Type: Popup button (NSPopUpButton style)
  - Options: "Never (default)", "1 day", "1 week", "1 month"
  - Default: "Never"
  - Width: 200px
  - Applied: During next processing run (cleanup happens automatically)
  - Warning: Deleting recordings is permanent and cannot be undone
  - Help text: "Video chunks are your primary recordings" (gray, 11pt)
  - Persist in config.json field: `recording_retention_days` (values: -1, 1, 7, 30)

- [ ] Implement "Clean Up Now" button
  - Label: "Clean Up Now"
  - Style: Secondary button, gray background, 130px width
  - Position: Below retention policy dropdowns with 16px top margin
  - Confirmation dialog: Modal alert with title "Clean Up Storage?"
  - Dialog message: Show preview like "This will delete: 143 old screenshots (1.2 GB), 5 old recordings (3.4 GB)"
  - Dialog buttons: "Cancel" (default), "Clean Up" (destructive style in red)
  - Progress indicator: Show modal progress sheet during cleanup with file count
  - Success notification: "Cleanup complete. Freed X GB of storage."
  - Error notification: "Cleanup failed: [error message]"
  - Post-cleanup: Refresh usage display automatically

### Settings Window - Privacy Tab
- [ ] Implement Privacy tab layout
  - Source: `Playback/Settings/PrivacySettingsView.swift`
  - Icon: SF Symbol `hand.raised` in sidebar
  - Sections: App Exclusion Mode, Excluded Apps List
  - Content padding: 20px all sides

- [ ] Implement exclusion mode dropdown
  - Label: "When excluded app is active:"
  - Type: Popup button (NSPopUpButton style)
  - Option 1: "Make app invisible (black out app area in screenshot)"
  - Option 2: "Skip screenshot entirely (recommended)"
  - Default: "Skip screenshot entirely"
  - Width: Full content width (410px)
  - Help text: "Excluded apps are detected by bundle ID or window title" (gray, 11pt)
  - Persist in config.json field: `exclusion_mode` (values: "blackout", "skip")

- [ ] Implement excluded apps list
  - Section header: "Excluded Apps"
  - Type: SwiftUI List/Table with selection
  - Height: 200px with scroll if needed
  - Columns: App icon (32px), App name (bold), Bundle ID (gray, small font)
  - Layout: Icon + two-line text (name above, bundle ID below)
  - Hover state: Light gray background
  - Selection: Blue highlight
  - Empty state: "No apps excluded" with add button prompt
  - Sorted: Alphabetically by app name
  - Border: 1px light gray border, rounded 6px corners

- [ ] Implement "Add App" button
  - Label: "Add App..." with plus icon (SF Symbol `plus.circle`)
  - Style: Secondary button, 100px width
  - Position: Below excluded apps list, left side
  - Action 1: Click opens standard NSOpenPanel for app selection (limited to /Applications/)
  - Action 2: Support drag & drop from Finder onto list area (NSTableView/List accepts drops)
  - Action 3: Sheet with text field to manually enter bundle ID (e.g., "com.apple.Safari")
  - Validation: Check if app already in list, show warning if duplicate
  - Post-add: Persist to config.json `excluded_apps` array, update recording service config

- [ ] Implement "Remove" button
  - Label: "Remove" with minus icon (SF Symbol `minus.circle`)
  - Style: Secondary button, 100px width, destructive style (red text when enabled)
  - Position: Below excluded apps list, right of "Add App" button, 8px spacing
  - Enabled state: Only when app(s) selected in list
  - Confirmation dialog: "Remove [App Name] from exclusion list?"
  - Dialog buttons: "Cancel" (default), "Remove" (destructive red)
  - Multi-selection: Support removing multiple apps at once
  - Post-remove: Persist to config.json, update recording service configuration

- [ ] Add privacy warning note
  - Position: Bottom of Privacy tab
  - Text: "⚠️ Screenshots may still contain sensitive information from other apps or notifications."
  - Style: Light orange warning box (#FFF3E0), 12px padding, rounded 6px corners
  - Icon: Warning icon (SF Symbol `exclamationmark.triangle`) on left, 16px size, orange color
  - Text color: Dark orange (#E65100)
  - Width: Full content width with 20px margin

### Settings Window - Advanced Tab
- [ ] Implement Advanced tab layout
  - Source: `Playback/Settings/AdvancedSettingsView.swift`
  - Icon: SF Symbol `gearshape.2.fill` in sidebar
  - Sections: Video Encoding, System Information, Service Status, Maintenance
  - Content padding: 20px all sides
  - Warning header: "⚠️ Advanced Settings" at top in orange

- [ ] Display video encoding parameters (read-only)
  - Section header: "Video Encoding Settings (Read-Only)"
  - Layout: 4 rows with label-value pairs, monospace font for values
  - Row 1: "Codec:" - "H.264"
  - Row 2: "Quality:" - "CRF 28"
  - Row 3: "Preset:" - "veryfast"
  - Row 4: "Frame Rate:" - "30 fps"
  - Style: Gray text color to indicate read-only, 11pt size
  - Help text: "These settings are optimized for performance and cannot be changed" (gray, 11pt)

- [ ] Implement system information display
  - Section header: "System Information"
  - Layout: 4 rows with label-value pairs, monospace font for values
  - Row 1: "macOS:" - Version string (e.g., "14.2 (Sonoma)")
  - Row 2: "Python:" - Version or "Not found" in red (e.g., "3.11.7")
  - Row 3: "FFmpeg:" - Version or "Not found" in red (e.g., "6.1.1")
  - Row 4: "Available Space:" - Free disk space in GB (e.g., "142.3 GB")
  - Detection: Run commands `sw_vers`, `python3 --version`, `ffmpeg -version`, `df -h`
  - Update: On tab open and every 30 seconds while visible
  - Error state: Red text with "Check Installation" button if dependencies missing

- [ ] Implement real-time service status
  - Section header: "Service Status"
  - Layout: 2 rows with service name, status indicator, and status text
  - Row 1: "Recording Service:" - Colored dot + status text
  - Row 2: "Processing Service:" - Colored dot + status text
  - Status indicators:
    - Green dot (●) + "Running" - Service actively processing
    - Yellow dot (●) + "Idle" - Service loaded but waiting
    - Red dot (●) + "Stopped" - Service not loaded
    - Red dot (●) + "Crashed" - Service exited with error
  - Dot size: 10px diameter
  - Detection: Query via `launchctl list | grep com.playback`
  - Auto-update: Every 5 seconds via Timer publisher
  - Action buttons: "Restart" button next to each service if stopped/crashed

- [ ] Implement "Reset All Settings" button
  - Section header: "Maintenance"
  - Label: "Reset All Settings"
  - Style: Destructive button, red text, 160px width
  - Confirmation dialog: Modal alert with title "Reset All Settings?"
  - Dialog message: "This will restore all settings to their default values. The app will need to restart. Recordings and data will not be affected."
  - Dialog icon: Warning icon
  - Dialog buttons: "Cancel" (default), "Reset and Restart" (destructive red)
  - Action: Write default config.json, then call `NSApp.terminate(nil)` to restart via launch agent
  - Position: First button in vertical stack with 12px spacing

- [ ] Implement "Rebuild Database" button
  - Label: "Rebuild Database"
  - Style: Secondary button, 160px width
  - Confirmation dialog: Modal alert with title "Rebuild Database?"
  - Dialog message: "This will scan all video chunks and rebuild the database. This may take several minutes depending on your recording history."
  - Dialog buttons: "Cancel" (default), "Rebuild"
  - Progress indicator: Modal progress sheet with determinate progress bar and file count
  - Action: Scan `~/Library/Application Support/Playback/data/chunks/`, regenerate `meta.sqlite3`
  - Success notification: "Database rebuilt successfully. Processed X video chunks."
  - Error notification: "Database rebuild failed: [error message]"
  - Position: Second button in vertical stack

- [ ] Implement "Export Logs" button
  - Label: "Export Logs"
  - Style: Secondary button, 160px width
  - File save dialog: Standard NSSavePanel with default name "Playback-Logs-[date].zip"
  - Action: Collect all logs into zip file
  - Include files:
    - `~/Library/Logs/Playback/recording.log`
    - `~/Library/Logs/Playback/processing.log`
    - `~/Library/Application Support/Playback/config.json`
    - System info (macOS version, dependencies)
  - Progress indicator: Brief spinner during zip creation
  - Success notification: "Logs exported to [filename]" with "Show in Finder" button
  - Error notification: "Export failed: [error message]"
  - Position: Third button in vertical stack

- [ ] Implement "Run Diagnostics Check" button
  - Label: "Run Diagnostics Check"
  - Style: Primary button, blue background, 180px width
  - Progress indicator: Inline spinner during check with text "Checking..."
  - Action: Verify all components working correctly
  - Checks performed:
    - Screen recording permission granted
    - Accessibility permission granted
    - Recording LaunchAgent loaded and running
    - Processing LaunchAgent loaded and running
    - Python 3.x installed and accessible
    - FFmpeg installed and accessible
    - Data directories exist and writable
    - Config file valid JSON
    - Database file accessible
  - Display results: Open diagnostics window and show Overview tab with results
  - Generate report: Create diagnostics report in logs directory
  - Success state: Green checkmark with summary
  - Error state: Red X with list of issues and suggested fixes
  - Position: Fourth button in vertical stack

### Diagnostics Window
- [ ] Create diagnostics window shell
  - Source: `Playback/Diagnostics/DiagnosticsWindow.swift`
  - Title: "Playback Diagnostics"
  - Size: 800×600 points (resizable, minimum 600×400)
  - Window style: Standard with toolbar
  - Toolbar style: Unified, compact height
  - Tab bar: Top of window content area, 4 tabs
  - Tab style: macOS standard segmented control

- [ ] Implement diagnostics toolbar
  - Button 1: "Refresh" - Circular arrow icon, reload logs and metrics
  - Button 2: "Export" - Share icon, save diagnostics to file
  - Button 3: "Clear" - Trash icon, clear on-screen display only
  - Style: Icon-only buttons, 28px size, 8px spacing
  - Tooltips: Show on hover for each button
  - Position: Right side of toolbar
  - Separator: Before buttons group

- [ ] Implement Overview tab
  - Source: `Playback/Diagnostics/OverviewView.swift`
  - Tab icon: SF Symbol `chart.bar.fill`
  - Layout: 3 sections vertically stacked with 20px spacing
  - Section 1: "System Status" - 4 rows showing service status, permissions, dependencies
  - Section 2: "Last 24 Hours" - Statistics cards in horizontal layout
    - Card 1: Screenshots captured (count)
    - Card 2: Videos processed (count)
    - Card 3: Errors encountered (count)
    - Card style: White background, border, padding, centered text
  - Section 3: "Recent Issues" - List of last 10 errors/warnings with timestamps
  - Auto-update: Every 10 seconds
  - Empty state: "No issues detected" with green checkmark

- [ ] Implement Recording Logs tab
  - Source: `Playback/Diagnostics/RecordingLogsView.swift`
  - Tab icon: SF Symbol `doc.text.fill`
  - Log source: `~/Library/Logs/Playback/recording.log`
  - Display: Scrollable text view with monospace font (Menlo, 11pt)
  - Toolbar controls:
    - Filter dropdown: "All", "Info", "Warning", "Error"
    - Search field: 200px width, real-time filter
    - Auto-scroll toggle: Checkbox "Auto-scroll to bottom"
  - Log format: [timestamp] [level] message
  - Color coding: Gray (info), orange (warning), red (error)
  - Line numbers: Optional, shown in gutter
  - Refresh: Manual via toolbar button or auto every 5 seconds
  - Max lines: Last 10,000 lines loaded (performance limit)

- [ ] Implement Processing Logs tab
  - Source: `Playback/Diagnostics/ProcessingLogsView.swift`
  - Tab icon: SF Symbol `doc.text.fill`
  - Log source: `~/Library/Logs/Playback/processing.log`
  - Display: Scrollable text view with monospace font (Menlo, 11pt)
  - Toolbar controls: Same as Recording Logs tab
    - Filter dropdown: "All", "Info", "Warning", "Error"
    - Search field: 200px width, real-time filter
    - Auto-scroll toggle: Checkbox "Auto-scroll to bottom"
  - Log format: [timestamp] [level] message
  - Color coding: Gray (info), orange (warning), red (error)
  - Line numbers: Optional, shown in gutter
  - Refresh: Manual via toolbar button or auto every 5 seconds
  - Max lines: Last 10,000 lines loaded (performance limit)

- [ ] Implement Resource Usage tab
  - Source: `Playback/Diagnostics/ResourceUsageView.swift`
  - Tab icon: SF Symbol `gauge.fill`
  - Layout: 3 charts vertically stacked with 16px spacing
  - Chart 1: "CPU Usage" - Line chart, last 60 seconds, 0-100% range
    - Blue line: Recording service
    - Green line: Processing service
  - Chart 2: "Memory Usage" - Line chart, last 60 seconds, MB scale
    - Blue line: Recording service
    - Green line: Processing service
  - Chart 3: "Disk I/O" - Line chart, last 60 seconds, MB/s scale
    - Blue line: Read operations
    - Red line: Write operations
  - Data collection: Sample via `ps` command every second
  - Chart style: Grid lines, axis labels, legend
  - Update: Real-time streaming via Combine
  - Performance: Limit data points to last 60 samples

### LaunchAgent Control Methods
- [ ] Implement LaunchAgent manager
  - Source: `Playback/Services/LaunchAgentManager.swift`
  - Methods: load, unload, reload, status
  - Agents: com.playback.recording, com.playback.processing

- [ ] Implement enableRecording method
  - Command: `launchctl load -w ~/Library/LaunchAgents/com.playback.recording.plist`
  - Pre-check: Verify plist file exists at path
  - Update config: Set `recording_enabled = true` in config.json
  - Post-action: Update menu bar icon to recording state
  - Error handling: Parse launchctl stderr, show notification on failure
  - Notification: "Recording service failed to start: [error]" with "Open Settings" button
  - Timeout: 5 seconds, show error if not loaded

- [ ] Implement disableRecording method
  - Command: `launchctl unload -w ~/Library/LaunchAgents/com.playback.recording.plist`
  - Pre-check: Verify service is loaded via `launchctl list`
  - Update config: Set `recording_enabled = false` in config.json
  - Post-action: Update menu bar icon to paused state
  - Error handling: Parse launchctl stderr, show notification on failure
  - Notification: "Recording service failed to stop: [error]" with "Open Diagnostics" button
  - Timeout: 5 seconds, show error if not unloaded
  - Graceful: Allow in-progress screenshot to complete before unload

- [ ] Implement updateProcessingInterval method
  - Input: Interval in minutes (1-60)
  - Validation: Check range, reject invalid values
  - Action 1: Read plist from `~/Library/LaunchAgents/com.playback.processing.plist`
  - Action 2: Update `StartInterval` key with value (minutes × 60 seconds)
  - Action 3: Write plist back to disk atomically
  - Action 4: Reload LaunchAgent via `launchctl unload` then `launchctl load`
  - Update config: Set `processing_interval_minutes` in config.json
  - Error handling: Rollback plist if reload fails
  - Notification: "Processing interval updated to X minutes" on success
  - Verification: Check service loaded after reload

- [ ] Implement getServiceStatus method
  - Input: Service name ("com.playback.recording" or "com.playback.processing")
  - Command: `launchctl list | grep [service-name]`
  - Parse output columns: PID, Status code, Label
  - Status determination:
    - Running: PID present and non-zero
    - Idle: PID present, status 0
    - Stopped: No output (service not loaded)
    - Crashed: PID "-", status code non-zero
  - Return: Enum value (ServiceStatus.running, .idle, .stopped, .crashed)
  - Caching: Cache result for 1 second to avoid excessive calls
  - Error handling: Return .stopped if command fails
  - Used by: Diagnostics window, Settings Advanced tab, menu bar icon

### Configuration Management
- [ ] Implement ConfigManager class
  - Source: `Playback/Config/ConfigManager.swift`
  - Protocol: ObservableObject for SwiftUI integration
  - Location: `~/Library/Application Support/Playback/config.json`
  - Reference: Original spec § "Configuration Management"

- [ ] Define Config struct
  - Fields: recording_enabled, processing_interval, retention policies, etc.
  - Codable conformance for JSON serialization
  - Default values for all fields

- [ ] Implement loadConfig method
  - Read JSON from disk
  - Parse with JSONDecoder
  - Return default config if file missing or corrupt

- [ ] Implement saveConfig method
  - Encode Config with JSONEncoder
  - Pretty print with sorted keys
  - Atomic write to disk

- [ ] Implement updateConfig method
  - Type-safe key path updates
  - Trigger save automatically
  - Publish changes for UI updates

### Notification System
- [ ] Implement notification manager
  - Source: `Playback/Notifications/NotificationManager.swift`
  - Uses: UserNotifications framework
  - Request authorization on first launch

- [ ] Implement showNotification method
  - Parameters: title, body, isError, withSettingsButton
  - Critical sound for errors
  - Default sound for informational notifications
  - Reference: Original spec § "Notifications"

- [ ] Implement notification categories
  - Category: SETTINGS_ACTION
  - Action: OPEN_SETTINGS (opens settings window)
  - Foreground option for button

- [ ] Implement notification response handling
  - Delegate: UNUserNotificationCenterDelegate
  - Action: Open settings on button tap
  - Bring app to foreground

- [ ] Define notification scenarios
  - Permission denied: "Playback needs Screen Recording permission"
  - Service crashed: "Recording Service crashed"
  - Disk full: "Playback stopped: Disk full"
  - Processing failed: "Video processing failed"

### Launch at Login
- [ ] Implement setLaunchAtLogin method
  - Source: `Playback/Services/LoginItemManager.swift`
  - Uses: ServiceManagement framework
  - Platform check: macOS 13.0+ vs macOS 12
  - Reference: Original spec § "Launch at Login"

- [ ] Modern implementation (macOS 13.0+)
  - API: SMAppService.mainApp.register()
  - API: SMAppService.mainApp.unregister()
  - Error handling: Log and notify user

- [ ] Legacy implementation (macOS 12)
  - API: SMLoginItemSetEnabled
  - Bundle ID: com.playback.Playback
  - Deprecation notice in logs

- [ ] Implement getLaunchAtLoginStatus method
  - Query current registration status
  - Used by Settings General tab
  - Auto-refresh when settings window opens

### Component Communication
- [ ] Implement menu bar to timeline communication
  - Method: openTimeline in MenuBarController
  - Find window by identifier: "timeline"
  - Activate app and bring window to front
  - Reference: Original spec § "Component Communication"

- [ ] Implement menu bar to settings communication
  - Method: openSettings in MenuBarController
  - Use NSApp.sendAction for standard preferences
  - Shortcut: Command+Comma

- [ ] Implement shared state management
  - Use SwiftUI @EnvironmentObject
  - Share ConfigManager across all views
  - Share MenuBarController state
  - Automatic UI updates on state changes

- [ ] Implement app delegate
  - Source: `Playback/AppDelegate.swift`
  - Handle application lifecycle
  - Set up global shortcuts
  - Register notification handlers

## UI Implementation Details

This section provides comprehensive technical details for implementing the menu bar component UI, settings windows, diagnostics, and system integrations.

### MenuBarExtra SwiftUI Structure

The menu bar is implemented using SwiftUI's `MenuBarExtra` API (macOS 13.0+):

```swift
@main
struct PlaybackApp: App {
    @StateObject private var menuBarController = MenuBarController()
    @StateObject private var configManager = ConfigManager.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(menuBarController)
                .environmentObject(configManager)
        } label: {
            MenuBarIconView(state: menuBarController.iconState)
        }

        Settings {
            SettingsWindow()
                .environmentObject(configManager)
        }
    }
}
```

**Icon State Management:**
- `MenuBarController` publishes icon state changes via Combine
- Icon automatically updates when recording service state changes
- Smooth transitions using SwiftUI animations (0.2s fade)
- System tray positioning handled automatically by macOS

**Menu Structure:**
```
┌─────────────────────────────────┐
│ ◉ Record Screen         [ON/OFF]│  <- Toggle with inline switch
├─────────────────────────────────┤
│ 🕐 Open Timeline    ⌥⇧Space     │  <- Shortcut hint right-aligned
│ ⚙️  Settings        ⌘,          │
│ 🩺 Diagnostics      [●3]        │  <- Badge shows issue count
├─────────────────────────────────┤
│ About Playback                  │
│ Quit Playback       ⌘Q          │
└─────────────────────────────────┘
```

### Settings Window Architecture

**Window Management:**
- Single window instance (singleton pattern)
- Preference identifier: "PlaybackSettings"
- Position persistence via UserDefaults
- Brings to front if already open
- Modal behavior (blocks interaction with other windows)

**Sidebar Navigation Implementation:**
```swift
NavigationView {
    List(selection: $selectedTab) {
        Label("General", systemImage: "gearshape")
            .tag(SettingsTab.general)
        Label("Recording", systemImage: "record.circle")
            .tag(SettingsTab.recording)
        Label("Processing", systemImage: "gearshape.2")
            .tag(SettingsTab.processing)
        Label("Storage", systemImage: "internaldrive")
            .tag(SettingsTab.storage)
        Label("Privacy", systemImage: "hand.raised")
            .tag(SettingsTab.privacy)
        Label("Advanced", systemImage: "gearshape.2.fill")
            .tag(SettingsTab.advanced)
    }
    .listStyle(SidebarListStyle())
    .frame(width: 150)

    // Content view based on selectedTab
    selectedTabContentView()
        .frame(width: 450, height: 500)
}
```

**Tab Content Views:**
Each tab is a separate SwiftUI view that observes `ConfigManager`:
- `GeneralSettingsView.swift`
- `RecordingSettingsView.swift`
- `ProcessingSettingsView.swift`
- `StorageSettingsView.swift`
- `PrivacySettingsView.swift`
- `AdvancedSettingsView.swift`

### Settings Window: Tab-Specific Controls

**General Tab Components:**
1. Launch at Login Toggle:
   ```swift
   Toggle("Launch Playback at login", isOn: $launchAtLogin)
       .onChange(of: launchAtLogin) { newValue in
           LoginItemManager.setLaunchAtLogin(enabled: newValue)
       }
   ```

2. Hotkey Recorder (custom component):
   ```swift
   HotkeyRecorderView(
       shortcut: $configManager.config.timeline_shortcut,
       placeholder: "Press keys...",
       onConflict: { conflictingApp in
           // Show warning about conflict
       }
   )
   ```

3. Permission Status Display:
   ```swift
   VStack(alignment: .leading, spacing: 12) {
       PermissionRow(
           name: "Screen Recording",
           granted: screenRecordingGranted,
           onOpenSettings: {
               NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
           }
       )
       PermissionRow(
           name: "Accessibility",
           granted: accessibilityGranted,
           onOpenSettings: {
               NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
           }
       )
   }
   .padding()
   .background(screenRecordingGranted && accessibilityGranted ? Color.clear : Color.yellow.opacity(0.2))
   ```

**Processing Tab Components:**
1. Interval Picker:
   ```swift
   Picker("Run processing every:", selection: $configManager.config.processing_interval_minutes) {
       Text("1 minute").tag(1)
       Text("5 minutes (recommended)").tag(5)
       Text("10 minutes").tag(10)
       Text("15 minutes").tag(15)
       Text("30 minutes").tag(30)
       Text("60 minutes").tag(60)
   }
   .pickerStyle(MenuPickerStyle())
   .frame(width: 200)
   .onChange(of: configManager.config.processing_interval_minutes) { newInterval in
       LaunchAgentManager.updateProcessingInterval(minutes: newInterval)
   }
   ```

2. Process Now Button:
   ```swift
   Button(action: triggerProcessingNow) {
       if isProcessing {
           HStack {
               ProgressView()
                   .scaleEffect(0.7)
               Text("Processing...")
           }
       } else {
           Text("Process Now")
       }
   }
   .disabled(isProcessing)
   .buttonStyle(.borderedProminent)
   .frame(width: 120)
   ```

**Storage Tab Components:**
1. Usage Display with Refresh:
   ```swift
   VStack(alignment: .leading, spacing: 8) {
       HStack {
           Text("Screenshots (temp):")
           Spacer()
           Text(formatBytes(tempSize))
               .monospacedDigit()
       }
       HStack {
           Text("Videos (chunks):")
           Spacer()
           Text(formatBytes(chunksSize))
               .monospacedDigit()
       }
       HStack {
           Text("Total:")
               .fontWeight(.bold)
           Spacer()
           Text(formatBytes(totalSize))
               .fontWeight(.bold)
               .monospacedDigit()
           Button(action: refreshUsage) {
               Image(systemName: "arrow.clockwise")
           }
           .buttonStyle(.plain)
       }
   }
   ```

2. Cleanup Button with Confirmation:
   ```swift
   Button("Clean Up Now") {
       showingCleanupConfirmation = true
   }
   .alert("Clean Up Storage?", isPresented: $showingCleanupConfirmation) {
       Button("Cancel", role: .cancel) {}
       Button("Clean Up", role: .destructive) {
           performCleanup()
       }
   } message: {
       Text("This will delete: \(filesToDelete.count) old screenshots (\(formatBytes(bytesToDelete)))")
   }
   ```

**Privacy Tab Components:**
1. Excluded Apps Table:
   ```swift
   Table(excludedApps, selection: $selectedApps) {
       TableColumn("App") { app in
           HStack(spacing: 8) {
               Image(nsImage: app.icon)
                   .resizable()
                   .frame(width: 32, height: 32)
               VStack(alignment: .leading, spacing: 2) {
                   Text(app.name)
                       .fontWeight(.medium)
                   Text(app.bundleID)
                       .font(.caption)
                       .foregroundColor(.secondary)
               }
           }
       }
   }
   .frame(height: 200)
   .border(Color.gray.opacity(0.3), width: 1)
   ```

2. Add/Remove Buttons:
   ```swift
   HStack(spacing: 8) {
       Button(action: showAppPicker) {
           Label("Add App...", systemImage: "plus.circle")
       }

       Button(action: removeSelectedApps) {
           Label("Remove", systemImage: "minus.circle")
       }
       .disabled(selectedApps.isEmpty)
       .foregroundColor(.red)
   }
   ```

**Advanced Tab Components:**
1. Service Status Indicators:
   ```swift
   VStack(alignment: .leading, spacing: 12) {
       ServiceStatusRow(
           name: "Recording Service",
           status: recordingServiceStatus,
           onRestart: { LaunchAgentManager.restartRecordingService() }
       )
       ServiceStatusRow(
           name: "Processing Service",
           status: processingServiceStatus,
           onRestart: { LaunchAgentManager.restartProcessingService() }
       )
   }
   .onReceive(statusUpdateTimer) { _ in
       updateServiceStatus()
   }
   ```

2. Maintenance Buttons:
   ```swift
   VStack(alignment: .leading, spacing: 12) {
       Button("Reset All Settings", role: .destructive) {
           showingResetConfirmation = true
       }
       .frame(width: 160)

       Button("Rebuild Database") {
           showingRebuildSheet = true
       }
       .frame(width: 160)

       Button("Export Logs") {
           showingSavePanel = true
       }
       .frame(width: 160)

       Button("Run Diagnostics Check") {
           runDiagnostics()
       }
       .buttonStyle(.borderedProminent)
       .frame(width: 180)
   }
   ```

### Diagnostics Window Layout

**Window Structure:**
```
┌──────────────────────────────────────────────────┐
│ Playback Diagnostics        [↻] [↗] [🗑]       │  <- Toolbar
├──────────────────────────────────────────────────┤
│ [Overview] [Recording Logs] [Processing] [Usage]│  <- Tabs
├──────────────────────────────────────────────────┤
│                                                  │
│                Tab Content Area                  │
│                                                  │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Overview Tab Layout:**
```swift
VStack(alignment: .leading, spacing: 20) {
    // System Status Section
    GroupBox(label: Text("System Status")) {
        VStack(alignment: .leading, spacing: 8) {
            StatusRow(label: "Recording", status: recordingStatus)
            StatusRow(label: "Processing", status: processingStatus)
            StatusRow(label: "Screen Recording Permission", status: permissionStatus)
            StatusRow(label: "Dependencies", status: dependencyStatus)
        }
    }

    // Statistics Section
    GroupBox(label: Text("Last 24 Hours")) {
        HStack(spacing: 16) {
            StatCard(label: "Screenshots", value: "\(screenshotCount)")
            StatCard(label: "Videos Processed", value: "\(videoCount)")
            StatCard(label: "Errors", value: "\(errorCount)")
        }
    }

    // Recent Issues Section
    GroupBox(label: Text("Recent Issues")) {
        if recentIssues.isEmpty {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("No issues detected")
            }
        } else {
            List(recentIssues) { issue in
                IssueRow(issue: issue)
            }
            .frame(height: 200)
        }
    }
}
.padding()
```

**Log Viewer Implementation:**
```swift
struct LogViewerView: View {
    @State private var logs: [LogEntry] = []
    @State private var filterLevel: LogLevel = .all
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Filter:", selection: $filterLevel) {
                    Text("All").tag(LogLevel.all)
                    Text("Info").tag(LogLevel.info)
                    Text("Warning").tag(LogLevel.warning)
                    Text("Error").tag(LogLevel.error)
                }
                .frame(width: 120)

                TextField("Search...", text: $searchText)
                    .frame(width: 200)

                Spacer()

                Toggle("Auto-scroll", isOn: $autoScroll)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredLogs) { log in
                            LogLineView(entry: log)
                                .id(log.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .font(.system(size: 11, design: .monospaced))
                .onChange(of: logs) { _ in
                    if autoScroll, let lastLog = filteredLogs.last {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
            }
        }
        .onAppear {
            loadLogs()
            startAutoRefresh()
        }
    }
}
```

### LaunchAgent Control Implementation

**Plist File Structure:**

Recording agent (`~/Library/LaunchAgents/com.playback.recording.plist`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.playback.recording</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Applications/Playback.app/Contents/Resources/recording_service.py</string>
    </array>
    <key>StartInterval</key>
    <integer>2</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/[USER]/Library/Logs/Playback/recording.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/[USER]/Library/Logs/Playback/recording-error.log</string>
</dict>
</plist>
```

Processing agent (`~/Library/LaunchAgents/com.playback.processing.plist`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.playback.processing</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Applications/Playback.app/Contents/Resources/processing_service.py</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/[USER]/Library/Logs/Playback/processing.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/[USER]/Library/Logs/Playback/processing-error.log</string>
</dict>
</plist>
```

**LaunchAgent Manager Swift Implementation:**
```swift
class LaunchAgentManager {
    static let shared = LaunchAgentManager()

    private let recordingAgentLabel = "com.playback.recording"
    private let processingAgentLabel = "com.playback.processing"

    func loadAgent(_ label: String) throws {
        let plistPath = getPlistPath(for: label)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w", plistPath]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw LaunchAgentError.loadFailed(message: errorMessage)
        }
    }

    func unloadAgent(_ label: String) throws {
        let plistPath = getPlistPath(for: label)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", "-w", plistPath]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw LaunchAgentError.unloadFailed
        }
    }

    func getAgentStatus(_ label: String) -> ServiceStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", label]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                return .stopped
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse output to determine status
            if output.contains("\"PID\" = ") {
                let pidLine = output.components(separatedBy: "\n")
                    .first(where: { $0.contains("\"PID\"") })

                if let pidString = pidLine?.split(separator: "=").last?.trimmingCharacters(in: .whitespaces),
                   pidString != "-" {
                    return .running
                } else {
                    return .crashed
                }
            }

            return .idle
        } catch {
            return .stopped
        }
    }

    func updateProcessingInterval(minutes: Int) throws {
        guard minutes >= 1 && minutes <= 60 else {
            throw LaunchAgentError.invalidInterval
        }

        let plistPath = getPlistPath(for: processingAgentLabel)
        let plistURL = URL(fileURLWithPath: plistPath)

        // Read plist
        guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw LaunchAgentError.plistReadFailed
        }

        // Update interval (convert minutes to seconds)
        plist["StartInterval"] = minutes * 60

        // Write plist
        let nsDict = NSDictionary(dictionary: plist)
        guard nsDict.write(to: plistURL, atomically: true) else {
            throw LaunchAgentError.plistWriteFailed
        }

        // Reload agent
        try unloadAgent(processingAgentLabel)
        try loadAgent(processingAgentLabel)
    }

    private func getPlistPath(for label: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/Library/LaunchAgents/\(label).plist"
    }
}

enum ServiceStatus {
    case running
    case idle
    case stopped
    case crashed
}

enum LaunchAgentError: Error {
    case loadFailed(message: String)
    case unloadFailed
    case invalidInterval
    case plistReadFailed
    case plistWriteFailed
}
```

### Configuration File Structure

**Location:** `~/Library/Application Support/Playback/config.json`

**Full Schema:**
```json
{
  "version": "1.0",
  "recording_enabled": true,
  "pause_when_timeline_open": true,
  "processing_interval_minutes": 5,
  "timeline_shortcut": {
    "modifiers": ["option", "shift"],
    "key": "space"
  },
  "notifications": {
    "notify_errors": true,
    "notify_crashes": true,
    "notify_disk_full": true,
    "notify_status": false
  },
  "storage": {
    "temp_retention_days": 7,
    "recording_retention_days": -1
  },
  "privacy": {
    "exclusion_mode": "skip",
    "excluded_apps": [
      {
        "bundle_id": "com.apple.Safari",
        "name": "Safari",
        "added_date": "2026-01-15T10:30:00Z"
      },
      {
        "bundle_id": "com.1password.1password",
        "name": "1Password",
        "added_date": "2026-01-15T10:31:00Z"
      }
    ]
  },
  "encoding": {
    "codec": "h264",
    "crf": 28,
    "preset": "veryfast",
    "fps": 30
  },
  "paths": {
    "data_dir": "~/Library/Application Support/Playback/data",
    "temp_dir": "~/Library/Application Support/Playback/data/temp",
    "chunks_dir": "~/Library/Application Support/Playback/data/chunks",
    "database": "~/Library/Application Support/Playback/data/meta.sqlite3"
  }
}
```

**ConfigManager Implementation:**
```swift
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var config: PlaybackConfig

    private let configURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        // Set up paths
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let playbackDir = appSupport.appendingPathComponent("Playback")
        configURL = playbackDir.appendingPathComponent("config.json")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: playbackDir,
            withIntermediateDirectories: true
        )

        // Load or create config
        if let loadedConfig = try? loadConfig() {
            config = loadedConfig
        } else {
            config = PlaybackConfig.default
            try? saveConfig()
        }

        // Set up encoder
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadConfig() throws -> PlaybackConfig {
        let data = try Data(contentsOf: configURL)
        return try decoder.decode(PlaybackConfig.self, from: data)
    }

    func saveConfig() throws {
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    func updateConfig(_ keyPath: WritableKeyPath<PlaybackConfig, some Any>, value: Any) {
        config[keyPath: keyPath] = value
        try? saveConfig()
    }
}

struct PlaybackConfig: Codable {
    var version: String
    var recording_enabled: Bool
    var pause_when_timeline_open: Bool
    var processing_interval_minutes: Int
    var timeline_shortcut: HotkeyConfig
    var notifications: NotificationConfig
    var storage: StorageConfig
    var privacy: PrivacyConfig
    var encoding: EncodingConfig
    var paths: PathsConfig

    static var `default`: PlaybackConfig {
        PlaybackConfig(
            version: "1.0",
            recording_enabled: true,
            pause_when_timeline_open: true,
            processing_interval_minutes: 5,
            timeline_shortcut: HotkeyConfig(modifiers: ["option", "shift"], key: "space"),
            notifications: NotificationConfig(
                notify_errors: true,
                notify_crashes: true,
                notify_disk_full: true,
                notify_status: false
            ),
            storage: StorageConfig(
                temp_retention_days: 7,
                recording_retention_days: -1
            ),
            privacy: PrivacyConfig(
                exclusion_mode: "skip",
                excluded_apps: []
            ),
            encoding: EncodingConfig(
                codec: "h264",
                crf: 28,
                preset: "veryfast",
                fps: 30
            ),
            paths: PathsConfig.default
        )
    }
}
```

### Notification System Implementation

**UserNotifications Setup:**
```swift
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        requestAuthorization()
        setupCategories()
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func setupCategories() {
        let openSettingsAction = UNNotificationAction(
            identifier: "OPEN_SETTINGS",
            title: "Open Settings",
            options: .foreground
        )

        let openDiagnosticsAction = UNNotificationAction(
            identifier: "OPEN_DIAGNOSTICS",
            title: "Open Diagnostics",
            options: .foreground
        )

        let settingsCategory = UNNotificationCategory(
            identifier: "SETTINGS_ACTION",
            actions: [openSettingsAction],
            intentIdentifiers: [],
            options: []
        )

        let diagnosticsCategory = UNNotificationCategory(
            identifier: "DIAGNOSTICS_ACTION",
            actions: [openDiagnosticsAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([settingsCategory, diagnosticsCategory])
    }

    func showNotification(
        title: String,
        body: String,
        isError: Bool = false,
        category: String? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isError ? .defaultCritical : .default

        if let category = category {
            content.categoryIdentifier = category
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case "OPEN_SETTINGS":
            openSettings()
        case "OPEN_DIAGNOSTICS":
            openDiagnostics()
        default:
            break
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openDiagnostics() {
        NotificationCenter.default.post(name: .openDiagnosticsWindow, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Notification scenarios
extension NotificationManager {
    func notifyPermissionDenied() {
        showNotification(
            title: "Permission Required",
            body: "Playback needs Screen Recording permission to function.",
            isError: true,
            category: "SETTINGS_ACTION"
        )
    }

    func notifyServiceCrashed(service: String) {
        showNotification(
            title: "Service Crashed",
            body: "\(service) has stopped unexpectedly.",
            isError: true,
            category: "DIAGNOSTICS_ACTION"
        )
    }

    func notifyDiskFull() {
        showNotification(
            title: "Disk Full",
            body: "Playback has stopped recording because your disk is full.",
            isError: true,
            category: "SETTINGS_ACTION"
        )
    }

    func notifyProcessingFailed(error: String) {
        showNotification(
            title: "Processing Failed",
            body: "Video processing encountered an error: \(error)",
            isError: true,
            category: "DIAGNOSTICS_ACTION"
        )
    }
}

## Testing Checklist

### Unit Tests
- [ ] Test ConfigManager load/save operations
  - Create config with all fields
  - Save to temporary location
  - Load and verify all values match
  - Test default config when file missing

- [ ] Test LaunchAgent control methods
  - Mock launchctl calls
  - Verify correct arguments for load/unload
  - Test error handling for failed operations

- [ ] Test notification scheduling
  - Create notification with each configuration
  - Verify category registration
  - Test action button presence

- [ ] Test launch at login toggle
  - Mock SMAppService calls
  - Test macOS 13.0+ code path
  - Test macOS 12 fallback

### UI Tests
- [ ] Test menu bar icon interaction
  - Click icon and verify menu appears
  - Verify all menu items present
  - Check shortcut hints displayed

- [ ] Test settings window navigation
  - Open each tab in sidebar
  - Verify correct content displayed
  - Test window position persistence

- [ ] Test recording toggle
  - Toggle switch on/off
  - Verify icon state changes
  - Verify config updated

- [ ] Test app exclusion management
  - Add app to exclusion list
  - Remove app from list
  - Verify table updates correctly

- [ ] Test diagnostics window
  - Open diagnostics from menu
  - Switch between tabs
  - Verify logs display correctly
  - Test export functionality

### Integration Tests
- [ ] Test enable/disable recording flow
  - Toggle recording in menu bar
  - Verify LaunchAgent loads/unloads
  - Verify config persists across app restarts
  - Verify icon updates correctly

- [ ] Test processing interval change
  - Change interval in settings
  - Verify plist updated on disk
  - Verify LaunchAgent reloaded
  - Verify processing runs at new interval

- [ ] Test manual processing trigger
  - Click "Process Now" button
  - Verify processing starts
  - Verify progress indicator appears
  - Verify notification on completion

- [ ] Test cleanup operations
  - Set retention policies
  - Click "Clean Up Now"
  - Verify files deleted correctly
  - Verify usage display updates

- [ ] Test open timeline from menu bar
  - Click "Open Timeline" menu item
  - Verify timeline window opens
  - Verify window brought to front
  - Test keyboard shortcut (⌥⇧Space)

- [ ] Test permission status display
  - Deny screen recording permission
  - Open settings General tab
  - Verify X shown for permission
  - Click "Open System Preferences"
  - Verify correct pane opens

- [ ] Test notification actions
  - Trigger error notification
  - Click "Open Settings" button
  - Verify settings window opens
  - Verify correct tab shown

- [ ] Test quit with confirmation
  - Recording active
  - Click "Quit Playback"
  - Verify confirmation dialog
  - Test both Cancel and Quit options

### Performance Tests
- [ ] Test settings window responsiveness
  - Open with 100+ excluded apps
  - Switch between tabs rapidly
  - Verify no lag or freezing

- [ ] Test diagnostics with large logs
  - Generate 10,000+ log entries
  - Open diagnostics window
  - Test scrolling performance
  - Test search performance

- [ ] Test menu bar icon updates
  - Rapidly toggle recording on/off
  - Verify icon updates immediately
  - No delayed or stuck states
