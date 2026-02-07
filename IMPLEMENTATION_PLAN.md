<!--
 Copyright (c) 2025 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Playback - Implementation Plan

Based on comprehensive technical specifications in `specs/`.

---

## Phase 1: Core Recording & Processing

### 1.1 Recording Service (Python)
- ✅ Implement screenshot capture using ScreenCaptureKit
- ✅ Implement 2-second capture interval loop
- ✅ Implement frontmost app detection via AppleScript
- ✅ Implement screen unavailability detection (screensaver, display off)
- Implement app exclusion logic (skip mode)
- Implement file naming convention (YYYYMMDD-HHMMSS-uuid-app_id)
- Implement date-based directory structure (YYYYMM/DD/)
- Implement structured JSON logging
- Implement permission checks (Screen Recording, Accessibility)
- Implement graceful error handling and recovery
- Implement metrics tracking (frames captured, errors, CPU/memory usage)

### 1.2 Processing Service (Python)
- ✅ Implement temp file scanning and grouping
- ✅ Implement FFmpeg video generation (H.264, CRF 28, 30fps)
- ✅ Implement segment ID generation
- Implement 5-minute processing interval via LaunchAgent
- Implement segment metadata extraction (duration, frame count, dimensions)
- Implement database insertion for segments
- Implement app segment aggregation and timeline generation
- Implement temp file cleanup after processing
- Implement error handling for corrupted frames
- Implement batch processing for efficiency
- Implement progress logging and metrics

### 1.3 Shared Python Utilities (src/lib/)
- Implement paths.py for environment-aware path resolution
- Implement database.py for SQLite operations and schema management
- Implement video.py for FFmpeg wrappers and video processing
- Implement macos.py for CoreGraphics and AppleScript integration
- Implement timestamps.py for filename parsing and generation
- Migrate duplicated logic from recording/processing services
- Implement unit tests for all shared utilities

### 1.4 Configuration System
- Implement ConfigManager in Swift
- Implement config.json schema with validation
- Implement default configuration generation
- Implement hot-reloading with FileSystemWatcher
- Implement config migration for version updates
- Implement environment-aware paths (dev vs production)
- Implement configuration UI bindings (@Published properties)
- Implement config backup before migrations
- Implement validation rules for all settings

### 1.5 LaunchAgent Management
- Implement LaunchAgentManager in Swift
- Implement plist template system with variable substitution
- Implement load/unload/start/stop commands via launchctl
- Implement status verification before operations
- Implement LaunchAgent installation on first run
- Implement plist validation before installation
- Implement separate dev/prod agent labels
- Implement error handling for launchctl failures
- Implement agent restart on configuration changes

---

## Phase 2: User Interface

### 2.1 Menu Bar Component
- Implement MenuBarExtra in SwiftUI
- Implement status icon states (Recording/Paused/Error)
- Implement menu structure (Toggle Recording, Open Timeline, Settings, Quit)
- Implement status display (recording time, storage used)
- Implement click handlers for all menu items
- Implement menu updates based on state changes
- Implement tooltips and keyboard shortcuts
- Implement "Processing..." status during video generation

### 2.2 Timeline Viewer
- Implement TimelineView in SwiftUI
- Implement AVPlayer integration for video playback
- Implement segment selection algorithm with video offset calculation
- Implement scroll gesture handling with momentum physics
- Implement pinch-to-zoom (60s to 3600s range)
- Implement time bubble display with current timestamp
- Implement app color generation (HSL from bundle ID hash)
- Implement app segment visual representation
- Implement frozen frame handling (gap detection)
- Implement playback controls (play/pause, seek)
- Implement keyboard shortcuts (Space, Left/Right arrows)
- Implement timeline scrubbing with precise positioning
- Implement auto-scroll on playback
- Implement performance optimization (viewport culling)

### 2.3 Date/Time Picker
- Implement DateTimePickerView in SwiftUI
- Implement calendar component with month/year selection
- Implement time input fields (hours, minutes)
- Implement "available dates" highlighting (days with recordings)
- Implement SQL queries for date availability
- Implement jump-to-timestamp functionality
- Implement smooth transition animations
- Implement keyboard navigation (Tab, Enter, Escape)
- Implement caching for date availability queries

### 2.4 Settings Window
- Implement SettingsView with tab navigation
- Implement GeneralTab (recording enabled, interval, retention)
- Implement StorageTab (location, usage, cleanup controls)
- Implement PrivacyTab (permissions, app exclusion, data export)
- Implement DiagnosticsTab (logs viewer, health metrics, database stats)
- Implement AboutTab (version, license, credits)
- Implement form validation for all settings
- Implement settings persistence to config.json
- Implement real-time preview of setting changes
- Implement "Apply" and "Reset" functionality

### 2.5 First-Run Setup
- Implement WelcomeView with onboarding flow
- Implement PermissionsView (Screen Recording, Accessibility)
- Implement StorageView with location picker and space validation
- Implement DependencyView (Python, FFmpeg detection)
- Implement ConfigurationView (initial settings)
- Implement progress indicator for setup steps
- Implement "Open System Settings" deep links
- Implement "Skip" options for optional steps
- Implement setup completion persistence (UserDefaults)

---

## Phase 3: Data & Storage

### 3.1 SQLite Database
- Implement database initialization (schema_version, segments, appsegments)
- Implement DatabaseManager in Swift
- Implement WAL mode configuration for concurrent access
- Implement index creation for performance
- Implement segment queries (by timestamp, by date range, by app)
- Implement FTS5 full-text search index for OCR
- Implement database integrity checks
- Implement VACUUM for maintenance
- Implement backup functionality
- Implement migration system with version tracking

### 3.2 File Management
- Implement Paths.swift for environment-aware path resolution
- Implement Environment.swift for dev vs production detection
- Implement DirectoryManager for creating data directories
- Implement file permission enforcement (0600 for sensitive files)
- Implement date-based directory creation and cleanup
- Implement storage monitoring and reporting
- Implement disk space checks and warnings
- Implement safe file operations (atomic writes, error recovery)

### 3.3 Storage Cleanup Service
- Implement cleanup script for retention policy enforcement
- Implement retention policy configurations (never, 1_day, 1_week, 1_month)
- Implement temp file cleanup (immediate after processing)
- Implement old segment deletion (based on retention policy)
- Implement database cleanup (orphaned records)
- Implement LaunchAgent for scheduled cleanup (daily at 2 AM)
- Implement storage usage calculation and reporting
- Implement cleanup preview (dry-run mode)
- Implement progress reporting and logging

---

## Phase 4: Advanced Features

### 4.1 Text Search with OCR
- Implement OCRService using Vision framework
- Implement batch OCR processing (4-8 parallel workers)
- Implement ocr_text table in database
- Implement FTS5 search index (porter unicode61 tokenizer)
- Implement SearchController with query parsing
- Implement SearchBar UI component (Command+F)
- Implement SearchResultsList with highlighted snippets
- Implement timeline match markers (yellow vertical lines)
- Implement result navigation (Enter, Shift+Enter)
- Implement query caching (5 minute TTL)
- Implement performance optimization (< 200ms query latency)
- Implement privacy considerations (local-only storage)

### 4.2 Privacy & Security
- Implement app exclusion system (skip screenshot mode)
- Implement frontmost app tracking
- Implement exclusion list management UI
- Implement recommended exclusions (password managers)
- Implement screen unavailability detection enhancement
- Implement permission checking functions
- Implement file permission enforcement
- Implement secure file creation helpers
- Implement network access audit (verify zero network calls)
- Implement data export functionality
- Implement uninstallation with data preservation option

### 4.3 Logging & Diagnostics
- Implement structured JSON logging for all services
- Implement log rotation (10MB per file, 5 backups)
- Implement log viewer UI in diagnostics tab
- Implement log filtering and search
- Implement resource metrics collection (CPU, memory, disk I/O)
- Implement health monitoring and alerts
- Implement crash notification system
- Implement diagnostic report generation
- Implement "Open Settings" button in crash notifications

### 4.4 Performance Monitoring
- Implement metrics collection for recording service
- Implement metrics collection for processing service
- Implement timeline performance metrics
- Implement database query performance tracking
- Implement storage I/O monitoring
- Implement performance dashboard in diagnostics
- Implement alerts for performance degradation
- Implement automatic optimization suggestions

---

## Phase 5: Testing & Quality

### 5.1 Unit Tests (Swift)
- Implement TimelineStore tests (segment selection, time mapping, gap handling)
- Implement ConfigManager tests (loading, saving, validation, migration)
- Implement DatabaseManager tests (queries, insertions, integrity)
- Implement Paths tests (environment detection, path resolution)
- Implement LaunchAgentManager tests (mock launchctl commands)
- Target: 80%+ code coverage for core logic

### 5.2 Unit Tests (Python)
- Implement recording service tests (screenshot capture, app detection)
- Implement processing service tests (video generation, segment creation)
- Implement database tests (schema, queries, migrations)
- Implement OCR tests (accuracy, performance, error handling)
- Implement cleanup tests (retention policies, file deletion)
- Target: 80%+ code coverage for all Python scripts

### 5.3 Integration Tests
- Implement end-to-end recording → processing → playback pipeline
- Implement settings changes → LaunchAgent reload → config propagation
- Implement manual processing trigger → completion → database update
- Implement search indexing → query → result navigation
- Implement first-run setup → LaunchAgent installation → recording start
- Test with dev environment isolation

### 5.4 UI Tests
- Implement menu bar interaction tests (XCUITest)
- Implement timeline viewer tests (open, play, scrub, zoom)
- Implement date/time picker tests (navigation, selection, jump)
- Implement search tests (Command+F, query, results, navigation)
- Implement settings tests (tab navigation, form validation, apply)
- Implement first-run tests (all steps, permission prompts, completion)
- Target: Critical user flows covered

### 5.5 Performance Tests
- Benchmark screenshot capture rate (target: 1 per 2 seconds with <5% CPU)
- Benchmark video encoding speed (target: 5-10 frames/second with <20% CPU)
- Benchmark timeline rendering (target: 60fps scrolling)
- Benchmark database query performance (target: <100ms for typical queries)
- Benchmark OCR processing (target: 100-200ms per frame)
- Benchmark search query performance (target: <200ms)
- Test with 30+ days of data (~12GB)
- Test with 90+ days of data (~37GB)

### 5.6 Manual Testing
- Test on clean macOS Tahoe 26.0 installation
- Test permission prompts (Screen Recording, Accessibility)
- Test with various display configurations
- Test with screen lock and screensaver
- Test with app exclusion (1Password, etc.)
- Test with low disk space scenarios
- Test with corrupted database recovery
- Test uninstallation with data preservation/deletion

---

## Phase 6: Distribution & Deployment

### 6.1 Build System
- Implement build scripts (development and release)
- Implement code signing with Developer ID certificate
- Implement entitlements configuration
- Implement Hardened Runtime enablement
- Implement build validation (signature verification, entitlements check)
- Implement incremental build optimization
- Implement CI/CD pipeline (GitHub Actions)
- Implement automated testing on push
- Implement pre-commit hooks (SwiftLint, flake8, fast tests)

### 6.2 Notarization
- Implement notarization workflow script
- Implement Apple ID credential management (keychain)
- Implement notarization submission via xcrun notarytool
- Implement status checking and waiting
- Implement stapling to app bundle
- Implement verification steps
- Implement error handling and retry logic
- Implement audit log preservation

### 6.3 Arc-Style Distribution
- Implement .zip packaging script (ditto with proper attributes)
- Implement README.txt generation for installation instructions
- Implement SHA256 checksum generation
- Implement release notes generation
- Implement version numbering system
- Implement GitHub Releases upload
- Implement download page generation
- Implement update mechanism (version check, download, install)

### 6.4 Installation & Updates
- Implement first-run wizard
- Implement dependency detection and installation guidance
- Implement data directory creation
- Implement LaunchAgent installation
- Implement default configuration generation
- Implement update checker (daily check, optional)
- Implement in-place update mechanism
- Implement config migration on update
- Implement database migration on update
- Implement rollback on update failure

### 6.5 Documentation
- Write user guide (installation, features, troubleshooting)
- Write developer guide (building, testing, contributing)
- Write architecture documentation (system design, data flow)
- Write API documentation (Swift/Python APIs)
- Create tutorial videos (basic usage, advanced features)
- Write troubleshooting guide (common issues, solutions)
- Create FAQ page
- Write release notes for each version

---

## Project Structure

```
Playback/
├── src/                            # All source code
│   ├── Playback/                  # Swift app
│   │   ├── Playback.xcodeproj    # Xcode project configuration
│   │   ├── Playback/              # Main app target
│   │   │   ├── PlaybackApp.swift # App entry point
│   │   │   ├── MenuBar/          # Menu bar component
│   │   │   ├── Timeline/         # Timeline viewer
│   │   │   ├── Settings/         # Settings window
│   │   │   ├── Config/           # Configuration management
│   │   │   ├── Database/         # SQLite access
│   │   │   ├── Services/         # LaunchAgent management
│   │   │   └── Search/           # OCR and search
│   │   ├── PlaybackTests/        # Unit and integration tests
│   │   └── PlaybackUITests/      # UI tests
│   ├── scripts/                   # Python background services
│   │   ├── record_screen.py      # Screenshot capture
│   │   ├── build_chunks_from_temp.py  # Video processing
│   │   ├── cleanup_old_chunks.py # Retention cleanup
│   │   ├── migrations.py         # Database migrations
│   │   └── tests/                # Python tests
│   └── lib/                       # Shared Python utilities (planned)
│       ├── paths.py               # Path resolution
│       ├── database.py            # Database operations
│       ├── video.py               # FFmpeg wrappers
│       ├── macos.py               # macOS integration
│       └── timestamps.py          # Filename parsing
├── specs/                          # Technical specifications
├── dev_data/                       # Development data (gitignored)
├── dev_logs/                       # Development logs (gitignored)
└── dist/                           # Build artifacts (gitignored)
```

---

## Key Dependencies

| Dependency | Purpose | Version |
|------------|---------|---------|
| **Xcode** | Build system and IDE | 15.0+ |
| **Swift** | App development language | 6.0+ |
| **SwiftUI** | UI framework | macOS 26.0+ |
| **Python** | Background services | 3.12+ |
| **FFmpeg** | Video encoding | 7.0+ |
| **SQLite** | Database | 3.45+ |
| **Vision** | OCR framework | macOS 26.0+ |
| **AVFoundation** | Video playback | macOS 26.0+ |
| **ScreenCaptureKit** | Screenshot capture | macOS 26.0+ |

---

## Success Criteria

### Functionality
- ✅ All core features implemented and tested
- ✅ Recording service stable for 24+ hour runs
- ✅ Processing service handles 1000+ frames without issues
- ✅ Timeline viewer smooth at 60fps with 30+ days of data
- ✅ Text search returns results in <200ms
- ✅ Zero crashes during normal operation
- ✅ All permissions properly requested and handled

### Performance
- CPU usage: <5% recording, <20% processing, <1% idle
- Memory usage: <50MB recording, <200MB processing, <100MB app
- Storage: 10-14 GB/month typical usage (4-5 hours/day)
- Database: <2.5 GB per year, query performance <100ms
- Timeline: 60fps scrolling, <16ms frame time

### Quality
- 80%+ code coverage for core logic
- All integration tests passing
- All UI tests passing for critical flows
- Zero known crashes or data loss issues
- Clean code that follows Swift/Python conventions
- Comprehensive documentation for users and developers

### User Experience
- Installation takes <5 minutes on clean system
- First launch setup takes <2 minutes
- Timeline opens in <500ms
- Search results appear in <200ms
- Settings changes apply immediately
- No manual configuration required for basic usage
- Intuitive UI that matches macOS design language

### Security & Privacy
- All data stays local (zero network access verified)
- File permissions properly set (0600 for sensitive files)
- App exclusion system working (password managers skipped)
- Permission checks working (Screen Recording, Accessibility)
- Uninstallation properly removes all data (when requested)
- No sensitive data in logs or crash reports

---

## Development Phases Timeline

| Phase | Duration | Status |
|-------|----------|--------|
| Phase 1: Core Recording & Processing | 4-6 weeks | 🚧 In Progress |
| Phase 2: User Interface | 6-8 weeks | 📋 Planned |
| Phase 3: Data & Storage | 3-4 weeks | 📋 Planned |
| Phase 4: Advanced Features | 4-6 weeks | 📋 Planned |
| Phase 5: Testing & Quality | 3-4 weeks | 📋 Planned |
| Phase 6: Distribution & Deployment | 2-3 weeks | 📋 Planned |

**Total Estimated Duration:** 22-31 weeks (5-7 months)

---

## Current Status

### Completed ✅
- Basic recording service (screenshot capture)
- Basic processing service (video generation)
- Database schema design
- Specifications for all major features

### In Progress 🚧
- Configuration system
- LaunchAgent management
- Timeline viewer foundation
- Build system setup

### Next Up 📋
- Menu bar implementation
- Settings window
- Date/time picker
- Text search with OCR
- First-run setup wizard

---

## References

- **Specifications:** See `specs/README.md` for detailed technical specs
- **Development Guide:** See `AGENTS.md` for development guidelines
- **Architecture:** See `README.md` for system overview
