# Playback Specifications

**Status:** Active Development

Design documentation and specifications for Playback, a macOS screen recording and timeline playback system.

## Overview

Playback continuously captures screenshots, processes them into video segments, and provides a timeline-based viewer for browsing screen history. The entire system runs as a single Swift app with in-process services.

## Architecture

Playback is a single unified macOS app:

1. **Menu Bar**: Always-visible system tray icon for recording control
2. **Timeline Viewer**: Fullscreen window for browsing recorded screen history
3. **Recording Service**: In-process screenshot capture every 2 seconds (ScreenCaptureKit)
4. **Processing Service**: In-process video generation every 5 minutes (AVFoundation)

## Specifications

### Core Architecture

| Spec | Purpose |
|------|---------|
| [architecture.md](./architecture.md) | System architecture, data flow, component communication |
| [file-structure.md](./file-structure.md) | Project layout, path resolution, dev vs production |
| [configuration.md](./configuration.md) | Config file format, settings panel |

### Recording & Processing

| Spec | Purpose |
|------|---------|
| [recording-service.md](./recording-service.md) | In-process screenshot capture with ScreenCaptureKit |
| [processing-service.md](./processing-service.md) | In-process video generation with AVFoundation |

### User Interface

| Spec | Purpose |
|------|---------|
| [menu-bar.md](./menu-bar.md) | Menu bar icon, recording toggle, app controls |
| [timeline-graphical-interface.md](./timeline-graphical-interface.md) | Timeline viewer, video playback, date/time picker |

### Data & Security

| Spec | Purpose |
|------|---------|
| [database-schema.md](./database-schema.md) | SQLite schema for segments and app activity |
| [privacy-security.md](./privacy-security.md) | App exclusion, permissions, file security |

### Build & Distribution

| Spec | Purpose |
|------|---------|
| [build-process.md](./build-process.md) | Build system, testing, distribution |
| [installation-deployment.md](./installation-deployment.md) | .zip distribution, first launch |

## Key Features

- **Continuous Recording**: 2-second screenshot intervals with automatic processing
- **Timeline Viewer**: Smooth scrubbing and pinch zoom (1 min to 60 min range)
- **Date/Time Navigation**: Calendar picker for jumping to specific moments
- **App Activity Tracking**: Color-coded timeline by frontmost application
- **Privacy Controls**: App exclusion list (skip mode)

## Technical Stack

- **Platform**: macOS 26.0 (Tahoe) or later
- **Architecture**: Apple Silicon only
- **Language**: Swift 6.0+
- **Frameworks**: SwiftUI, AVFoundation, ScreenCaptureKit, Vision (future)
- **Database**: SQLite 3.45+ with WAL mode

## Storage

- **Typical Usage**: 10-14 GB/month (4-5 hours daily recording)
- **Light Usage**: 6-8 GB/month
- **Heavy Usage**: 20-28 GB/month

## User Interactions

- **Menu Bar Icon**: Toggle recording, access settings
- **Option+Shift+Space**: Open timeline viewer
- **ESC**: Close timeline viewer
- **Click time bubble**: Open date/time picker
- **Scroll/Trackpad**: Scrub through timeline
- **Pinch**: Zoom timeline

## Settings (Single Panel)

Only 4 user-facing settings:

1. **Launch at login** — toggle
2. **Permissions status** — Screen Recording (required), Accessibility (optional)
3. **Timeline hotkey** — customizable shortcut (default: Option+Shift+Space)
4. **Excluded apps** — list of bundle IDs to skip recording

All other values are hardcoded:
- Recording interval: 2 seconds
- Processing interval: 5 minutes
- Pause when timeline open: always on
- Exclusion mode: skip (only mode)
