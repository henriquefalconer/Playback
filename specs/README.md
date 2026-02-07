# Playback Specifications

**Version:** 1.0
**Status:** Production-Ready Transition
**Last Updated:** 2026-02-07

## Overview

Playback is a macOS screen recording and playback system that continuously captures screenshots, processes them into video segments, and provides a timeline-based viewer for browsing screen history. The system operates as a fully automated background service with a menu bar interface for control and monitoring.

## System Architecture

Playback consists of three main components:

1. **Single Unified App (Playback.app)** - Menu bar interface + timeline viewer + settings + uninstall
2. **Recording Service** - Background screenshot capture (LaunchAgent)
3. **Processing Service** - Video segment generation (Scheduled LaunchAgent)

## Specification Documents

### Core System Specifications

- **[01-architecture.md](01-architecture.md)** - High-level system architecture and component interactions
- **[02-recording-service.md](02-recording-service.md)** - Screenshot capture service (LaunchAgent)
- **[03-processing-service.md](03-processing-service.md)** - Video generation and scheduling
- **[04-menu-bar-app.md](04-menu-bar-app.md)** - Menu bar UI, controls, settings window, crash notifications
- **[05-playback-app.md](05-playback-app.md)** - Playback app with timeline, date/time picker, Arc-inspired design

### Supporting Specifications

- **[06-configuration.md](06-configuration.md)** - Configuration file format and settings
- **[07-logging-diagnostics.md](07-logging-diagnostics.md)** - Logging standards and diagnostic information
- **[08-storage-cleanup.md](08-storage-cleanup.md)** - File organization and retention policies
- **[09-privacy-security.md](09-privacy-security.md)** - App exclusion and privacy features
- **[10-installation-deployment.md](10-installation-deployment.md)** - Installation process and LaunchAgent setup

### Data Specifications

- **[11-database-schema.md](11-database-schema.md)** - SQLite schema for metadata storage
- **[12-file-structure.md](12-file-structure.md)** - Dev vs production structure, unified app bundle
- **[13-search-ocr.md](13-search-ocr.md)** - Text search and OCR functionality
- **[14-build-process.md](14-build-process.md)** - Build system, hot-reloading, testing, pre-commit hooks

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
- **Option + Shift + Space**: Open Playback app (or click app icon)
- **ESC**: Close Playback app
- **Command + F**: Open text search
- **Click time bubble**: Open date/time picker
- **Scroll/Trackpad**: Scrub through timeline
- **Pinch**: Zoom timeline (1 minute to 60 minutes)

### Technical Requirements

- **Platform**: macOS 12.0+ (Monterey or later)
- **Permissions**: Screen Recording, Accessibility
- **Dependencies**: Python 3.8+, FFmpeg, Swift/SwiftUI
- **Storage**: Variable (depends on usage patterns and retention settings)

## Development Status

| Component | Status | Notes |
|-----------|--------|-------|
| Unified Playback.app | 🚧 Specification Only | Combines menu bar + timeline + settings |
| Recording Service | ✅ Prototype Complete | Needs LaunchAgent integration |
| Processing Service | ✅ Prototype Complete | Needs OCR integration |
| Configuration System | 🚧 Specification Only | Dev vs prod configs |
| Date/Time Picker | 🚧 Specification Only | Arc-inspired UI |
| Text Search (OCR) | 🚧 Specification Only | Vision framework |
| Build System | 🚧 Specification Only | Hot-reloading, tests |
| Pre-commit Tests | 🚧 Specification Only | Automated quality checks |

## Implementation Priorities

### Phase 1: Development Infrastructure
1. ✅ Build system with dev/prod separation
2. ✅ Hot-reloading for development
3. ✅ Pre-commit test hooks
4. ✅ Unit test framework
5. File structure reorganization

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
4. Uninstall functionality (button in settings)
5. Production build and installer package

## Contributing

When updating specifications:

1. Update the relevant spec file(s)
2. Update this README if adding/removing specs
3. Update the "Last Updated" date
4. Increment version number for major changes

## References

- [Prototype Implementation](../Playback/)
- [Python Scripts](../scripts/)
- [CLAUDE.md](../CLAUDE.md) - Project guidance and environment setup
