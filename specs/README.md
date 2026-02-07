# Playback Implementation Plans

**Version:** 1.0
**Status:** Production-Ready Transition
**Last Updated:** 2026-02-07

Design documentation and implementation plans for Playback, a macOS screen recording and timeline playback system.

## Overview

Playback continuously captures screenshots, processes them into video segments, and provides a timeline-based viewer for browsing screen history. The system operates as a fully automated background service with a menu bar interface for control and monitoring.

## Core Architecture

| Spec | Code | Purpose |
|------|------|---------|
| [architecture.md](./architecture.md) | [Playback/](../Playback/) | System architecture, component communication, file organization |
| [file-structure.md](./file-structure.md) | [Playback/Config/](../Playback/Playback/Config/) | Dev vs production structure, path resolution, app bundle organization |
| [configuration.md](./configuration.md) | [Playback/Config/ConfigManager.swift](../Playback/Playback/Config/ConfigManager.swift) | Configuration file format, hot-reloading, settings management |

## Recording & Processing

| Spec | Code | Purpose |
|------|------|---------|
| [recording-service.md](./recording-service.md) | [scripts/record_screen.py](../scripts/record_screen.py) | Screenshot capture service with 2-second intervals |
| [processing-service.md](./processing-service.md) | [scripts/build_chunks_from_temp.py](../scripts/build_chunks_from_temp.py) | Video generation, scheduled processing, and cleanup |
| [storage-cleanup.md](./storage-cleanup.md) | [scripts/cleanup_old_chunks.py](../scripts/cleanup_old_chunks.py) | File organization, retention policies, disk space management |

## User Interface

| Spec | Code | Purpose |
|------|------|---------|
| [menu-bar.md](./menu-bar.md) | [Playback/MenuBar/](../Playback/Playback/MenuBar/) | Menu bar UI, controls, settings window, crash notifications |
| [timeline-graphical-interface.md](./timeline-graphical-interface.md) | [Playback/Timeline/](../Playback/Playback/Timeline/) | Timeline viewer with Arc-inspired design, date/time picker, scrubbing |
| [logging-diagnostics.md](./logging-diagnostics.md) | [Playback/Diagnostics/](../Playback/Playback/Diagnostics/) | Logging standards, diagnostics viewer, health monitoring |

## Data & Storage

| Spec | Code | Purpose |
|------|------|---------|
| [database-schema.md](./database-schema.md) | [Playback/Database/](../Playback/Playback/Database/) | SQLite schema for segments and app activity |
| [search-ocr.md](./search-ocr.md) | [Playback/Search/](../Playback/Playback/Search/) | Text search and OCR functionality using Vision framework |

## Privacy & Security

| Spec | Code | Purpose |
|------|------|---------|
| [privacy-security.md](./privacy-security.md) | [Playback/Services/](../Playback/Playback/Services/) | App exclusion, permission management, security measures |

## Installation & Distribution

| Spec | Code | Purpose |
|------|------|---------|
| [installation-deployment.md](./installation-deployment.md) | [scripts/package_release.sh](../scripts/package_release.sh) | Arc-style .zip distribution, first-run setup, LaunchAgent installation |
| [build-process.md](./build-process.md) | [scripts/build_release.sh](../scripts/build_release.sh) | Build system, testing pipeline, CI/CD |

## Key Features

- **Continuous Recording**: 2-second screenshot intervals with automatic processing
- **Timeline Viewer**: Arc-inspired design with smooth scrubbing and zoom
- **Date/Time Navigation**: Precise picker for jumping to specific moments
- **Text Search**: OCR-based search to find recorded screen content
- **App Activity Tracking**: Color-coded timeline by frontmost application
- **Resource Monitoring**: Crash notifications with diagnostic information
- **Privacy Controls**: App exclusion and permission management
- **Configurable Retention**: Automatic cleanup based on age and storage limits

## Technical Stack

- **Platform**: macOS 26.0 (Tahoe) or later
- **Architecture**: Apple Silicon only (M1, M2, M3, M4+)
- **Languages**: Swift 6.0+, Python 3.12+
- **Dependencies**: FFmpeg 7.0+, SQLite 3.45+
- **Frameworks**: SwiftUI, Vision, AVFoundation, ScreenCaptureKit

## Storage Requirements

- **Typical Usage**: 10-14 GB per month (4-5 hours daily recording)
- **Light Usage**: 6-8 GB per month (2-3 hours daily)
- **Heavy Usage**: 20-28 GB per month (8+ hours daily)
- **Video Segments**: ~7.5 MB per segment (5s video, 5min real-time)
- **Database**: ~2.5 GB per year
- **Recommended**: 100 GB free for 6 months of recordings

## User Interactions

- **Menu Bar Icon**: Toggle recording, access settings, view diagnostics
- **Option + Shift + Space**: Open timeline viewer (or click app icon)
- **ESC**: Close timeline viewer
- **Command + F**: Open text search
- **Click time bubble**: Open date/time picker
- **Scroll/Trackpad**: Scrub through timeline
- **Pinch**: Zoom timeline (1 minute to 60 minutes)

## Development Status

| Component | Status |
|-----------|--------|
| Unified Playback.app | 🚧 In Progress |
| Recording Service | ✅ Prototype Complete |
| Processing Service | ✅ Prototype Complete |
| Configuration System | 🚧 Specification Complete |
| Date/Time Picker | 🚧 Specification Complete |
| Text Search (OCR) | 🚧 Specification Complete |
| Build System | ✅ Active Development |

## Implementation Plan Format

Each implementation plan follows this structure:

1. **Implementation Checklist**: Actionable tasks with checkboxes, source file references, and implementation details
2. **Technical Details**: Complete specifications, code examples, and implementation patterns
3. **Testing Checklist**: Unit, integration, UI, and performance tests

Example task format:
```markdown
- [ ] Implement menu bar icon with status states
  - Source: `Playback/MenuBar/MenuBarView.swift`
  - States: Recording (red), Paused (gray), Error (red with exclamation)
  - See: "UI Implementation Details" section below
```

## Implementation Priorities

### Phase 1: Development Infrastructure ✅
1. ✅ Build system with dev/prod separation
2. ✅ Hot-reloading for development
3. ✅ Pre-commit test hooks
4. ✅ Unit test framework
5. 🚧 File structure reorganization

### Phase 2: Unified App Foundation
1. Single Playback.app with menu bar + timeline
2. LaunchAgent management from within app
3. Settings window (all tabs)
4. Basic configuration system

### Phase 3: Core Recording & Playback
1. Recording service with LaunchAgent
2. Processing service with scheduling
3. Timeline viewer with video playback
4. Date/time picker navigation
5. Enhanced logging and diagnostics

### Phase 4: Advanced Features
1. Text search with OCR
2. Crash notifications with "Open Settings" button
3. Privacy controls (app exclusion)
4. Production build and installer package

## Using These Implementation Plans

1. **Start with [architecture.md](./architecture.md)** to understand the overall system structure
2. **Choose a component** from the implementation plans
3. **Follow the checklist** - each task has source file references and implementation details
4. **Run tests** as specified in the Testing Checklist sections
5. **Check off completed tasks** to track progress

## Source Code Organization

```
Playback/
├── Playback.xcodeproj         # Xcode project
├── Playback/                  # Single unified app source
│   ├── PlaybackApp.swift      # Main entry point
│   ├── MenuBar/               # Menu bar component
│   ├── Timeline/              # Timeline viewer component
│   ├── Settings/              # Settings window
│   ├── Services/              # LaunchAgent management
│   ├── Config/                # Configuration system
│   ├── Database/              # SQLite access
│   └── Resources/
├── PlaybackTests/             # Unit tests
└── PlaybackUITests/           # UI tests

scripts/
├── record_screen.py           # Recording service
├── build_chunks_from_temp.py  # Processing service
└── tests/                     # Python tests

dev_data/                      # Development data (gitignored)
├── temp/
├── chunks/
└── meta.sqlite3
```

## Contributing

When updating implementation plans:

1. Update the relevant plan file with checked boxes as tasks are completed
2. Add new tasks as needed when implementation reveals additional requirements
3. Keep the technical details sections updated with key implementation patterns
4. Update this README if adding/removing plans
5. Update the "Last Updated" date

## References

- [Prototype Implementation](../Playback/)
- [Python Scripts](../scripts/)
- [CLAUDE.md](../CLAUDE.md) - Project guidance and environment setup
