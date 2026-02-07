# Playback Implementation Plans

**Version:** 1.0
**Status:** Production-Ready Transition
**Last Updated:** 2026-02-07

## Overview

Playback is a macOS screen recording and playback system that continuously captures screenshots, processes them into video segments, and provides a timeline-based viewer for browsing screen history. The system operates as a fully automated background service with a menu bar interface for control and monitoring.

This directory contains **implementation plans** for building Playback. Each file is organized as a checklist with references to source code locations and the original detailed specifications (available in version control history).

## System Architecture

Playback consists of three main components:

1. **Single Unified App (Playback.app)** - Menu bar interface + timeline viewer + settings
2. **Recording Service** - Background screenshot capture (LaunchAgent)
3. **Processing Service** - Video segment generation (Scheduled LaunchAgent)

## Implementation Plans

### Core System Plans

- **[architecture.md](architecture.md)** - High-level system architecture, component communication, and file organization
- **[recording-service.md](recording-service.md)** - Screenshot capture service with 2-second intervals
- **[processing-service.md](processing-service.md)** - Video generation, scheduled processing, and cleanup
- **[menu-bar.md](menu-bar.md)** - Menu bar UI, controls, settings window, crash notifications
- **[timeline-graphical-interface.md](timeline-graphical-interface.md)** - Timeline viewer with Arc-inspired design, date/time picker, and scrubbing

### Supporting Plans

- **[configuration.md](configuration.md)** - Configuration file format, hot-reloading, and settings management
- **[logging-diagnostics.md](logging-diagnostics.md)** - Logging standards, diagnostics viewer, and health monitoring
- **[storage-cleanup.md](storage-cleanup.md)** - File organization, retention policies, and disk space management
- **[privacy-security.md](privacy-security.md)** - App exclusion, permission management, and security measures
- **[installation-deployment.md](installation-deployment.md)** - Arc-style .zip distribution, first-run setup, and LaunchAgent installation

### Data Plans

- **[database-schema.md](database-schema.md)** - SQLite schema for segments and app activity
- **[file-structure.md](file-structure.md)** - Dev vs production structure, path resolution, and app bundle organization
- **[search-ocr.md](search-ocr.md)** - Text search and OCR functionality using Vision framework
- **[build-process.md](build-process.md)** - Build system, testing pipeline, and CI/CD

## Implementation Plan Format

Each implementation plan follows this structure:

1. **Implementation Checklist** - Actionable tasks with checkboxes, source file references, and implementation details
2. **Reference Documentation** - Pointers to original detailed specifications (in version control history)
3. **Testing Checklist** - Unit, integration, UI, and performance tests

Example task format:
```markdown
- [ ] Implement menu bar icon with status states
  - Source: `Playback/MenuBar/MenuBarView.swift`
  - States: Recording (red), Paused (gray), Error (red with exclamation)
  - Reference: See original spec § "Menu Bar Icon"
```

## Quick Reference

### Key Features

- Continuous screen recording with 2-second interval
- Automatic video segment generation (every 5 minutes, configurable)
- Timeline viewer with scrubbing and zoom (Arc-inspired design)
- Date/time picker for precise navigation
- Text search via OCR (search recorded screen content)
- App-based activity tracking
- Resource usage monitoring with crash notifications
- Configurable retention policies
- Privacy controls (app exclusion)
- Permission management UI

### User Interactions

- **Menu Bar Icon**: Toggle recording, access settings, view diagnostics
- **Option + Shift + Space**: Open timeline viewer (or click app icon)
- **ESC**: Close timeline viewer
- **Command + F**: Open text search
- **Click time bubble**: Open date/time picker
- **Scroll/Trackpad**: Scrub through timeline
- **Pinch**: Zoom timeline (1 minute to 60 minutes)

### Technical Requirements

- **Platform**: macOS 26.0 (Tahoe)
- **Architecture**: Apple Silicon only (M1, M2, M3, M4+)
- **Permissions**: Screen Recording, Accessibility
- **Dependencies**: Python 3.12+, FFmpeg 7.0+, Swift 6.0+
- **Storage**: Variable (depends on usage patterns and retention settings)

## Development Status

| Component | Status | Source Location |
|-----------|--------|-----------------|
| Unified Playback.app | 🚧 In Progress | `Playback/Playback/` |
| Recording Service | ✅ Prototype Complete | `scripts/record_screen.py` |
| Processing Service | ✅ Prototype Complete | `scripts/build_chunks_from_temp.py` |
| Configuration System | 🚧 Specification Complete | See `configuration.md` |
| Date/Time Picker | 🚧 Specification Complete | See `timeline-graphical-interface.md` |
| Text Search (OCR) | 🚧 Specification Complete | See `search-ocr.md` |
| Build System | ✅ Active Development | See `build-process.md` |

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

1. **Start with architecture.md** to understand the overall system structure
2. **Choose a component** from the implementation plans
3. **Follow the checklist** - each task has source file references and implementation details
4. **Refer to version control history** for the original detailed specifications if needed
5. **Run tests** as specified in the Testing Checklist sections
6. **Check off completed tasks** to track progress

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
3. Keep the "Reference Documentation" section updated with key source files
4. Update this README if adding/removing plans
5. Update the "Last Updated" date

## References

- [Prototype Implementation](../Playback/)
- [Python Scripts](../scripts/)
- [CLAUDE.md](../CLAUDE.md) - Project guidance and environment setup

## Original Detailed Specifications

The complete detailed specifications that these implementation plans are based on are available in the project's version control history. Each implementation plan references specific sections from the original specs for when detailed context is needed.
