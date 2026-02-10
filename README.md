<!--
 Copyright (c) 2026 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Playback

## Overview

Playback is a macOS screen recording and timeline playback system that continuously captures your screen activity and provides an elegant timeline-based viewer for browsing your screen history. The system operates as a fully automated background service with a menu bar interface for control and monitoring.

The system is designed around three core principles:

1. **Privacy First** - All data stays local. No cloud sync, no network access, no telemetry.
2. **Efficient Storage** - Smart video compression and configurable retention policies keep storage manageable (~10-14 GB/month typical usage).
3. **Elegant Interface** - Arc-inspired timeline design with smooth scrubbing, text search, and precise navigation.

## Architecture

Playback consists of a single unified macOS app with Python background services:

```
Playback/
├── Playback/                    # Xcode project
│   ├── Playback/                # Single unified SwiftUI app
│   │   ├── PlaybackApp.swift   # Main entry point
│   │   ├── MenuBar/             # Menu bar interface
│   │   ├── Timeline/            # Timeline viewer with video playback
│   │   ├── Settings/            # Settings window (all tabs)
│   │   ├── Config/              # Configuration management
│   │   ├── Database/            # SQLite database access
│   │   ├── Services/            # LaunchAgent management
│   │   └── Search/              # OCR and text search
│   ├── PlaybackTests/           # Unit and integration tests
│   └── PlaybackUITests/         # UI tests
├── scripts/
│   ├── record_screen.py         # Screenshot capture service
│   ├── build_chunks_from_temp.py # Video generation service
│   └── cleanup_old_chunks.py   # Retention cleanup service
└── specs/                       # Design specifications
```

### Key Components

| Component | Description |
|-----------|-------------|
| **Playback.app** | Single unified SwiftUI app with menu bar + timeline viewer |
| **Recording Service** | Python script capturing screenshots every 2 seconds via LaunchAgent |
| **Processing Service** | Python script generating H.264 video segments every 5 minutes |
| **Timeline Viewer** | SwiftUI interface for browsing recorded screen history |
| **Text Search** | OCR-powered search using Vision framework |
| **Database** | SQLite with WAL mode for metadata and segment tracking |

### Data Flow

```
┌──────────────┐   2s interval   ┌──────────────┐   5min interval   ┌──────────────┐
│  Recording   │ ────────────────▶│    Temp      │ ────────────────▶│   Video      │
│   Service    │  Screenshots     │  Directory   │  FFmpeg H.264    │  Segments    │
│ (LaunchAgent)│                  │              │                  │  + Metadata  │
└──────────────┘                  └──────────────┘                  └──────────────┘
                                                                            │
                                                                            │
                                                                            ▼
┌──────────────┐                  ┌──────────────┐                  ┌──────────────┐
│   Timeline   │ ◀────────────────│   SQLite     │ ◀────────────────│  Processing  │
│    Viewer    │  Query segments  │   Database   │  Write metadata  │   Service    │
│  (SwiftUI)   │                  │  (WAL mode)  │                  │ (LaunchAgent)│
└──────────────┘                  └──────────────┘                  └──────────────┘
```

All data stays local on your Mac. No cloud services, no network access.

## Building

### Prerequisites

- **macOS 26.0 (Tahoe)** or later
- **Xcode 15.0+** with Command Line Tools
- **Apple Silicon** (M1, M2, M3, M4+)
- **Python 3.12+** (`python3 --version`)
- **FFmpeg 7.0+** with libx264 (`brew install ffmpeg`)

### Development Build

```bash
# Setup development environment (first time only)
./scripts/setup_dev_env.sh

# Build the app
xcodebuild -scheme Playback-Development -configuration Debug

# Run tests
xcodebuild test -scheme Playback-Development -destination 'platform=macOS'

# Run from Xcode
open Playback/Playback.xcodeproj
```

Development builds use `dev_data/` and `dev_config.json` for complete isolation from production data.

### Release Build

```bash
# Create production release (requires Developer ID certificate)
./scripts/build_release.sh 1.0.0

# Output: dist/Playback-1.0.0.zip (signed and notarized)
```

## Features

- **Continuous Recording**: 2-second screenshot intervals with automatic processing
- **Timeline Viewer**: Arc-inspired design with smooth scrubbing and zoom (1-60 minutes)
- **Date/Time Navigation**: Precise picker for jumping to specific moments
- **Text Search**: OCR-based search to find recorded screen content (Command+F)
- **App Activity Tracking**: Color-coded timeline by frontmost application
- **Privacy Controls**: App exclusion list and screen unavailability detection
- **Configurable Retention**: Automatic cleanup based on age and storage limits
- **Resource Monitoring**: Low CPU/memory usage with health monitoring

## Storage Requirements

- **Typical Usage**: 10-14 GB/month (4-5 hours daily recording)
- **Light Usage**: 6-8 GB/month (2-3 hours daily)
- **Heavy Usage**: 20-28 GB/month (8+ hours daily)
- **Video Segments**: ~7.5 MB per segment (5s video, 5min real-time)
- **Database**: ~2.5 GB per year
- **Recommended**: 100 GB free for 6 months of recordings

## User Guide

### Keyboard Shortcuts

- **Option + Shift + Space**: Open timeline viewer
- **ESC**: Close timeline viewer
- **Command + F**: Open text search (in timeline)
- **Scroll/Trackpad**: Scrub through timeline
- **Pinch**: Zoom timeline

### First Launch

1. **Permissions**: Grant Screen Recording permission (required)
2. **Storage**: Choose data location (default: `~/Library/Application Support/Playback/`)
3. **Settings**: Configure recording interval and retention policies
4. **Start Recording**: Enable recording from menu bar

### Menu Bar

Click the Playback icon in the menu bar to:
- Toggle recording on/off
- Open timeline viewer
- Access settings
- View diagnostics and logs
- Quit application

## Specifications

Design documentation and implementation plans live in `specs/`. See `specs/README.md` for a complete index organized by category:

- Core Architecture
- Recording & Processing
- User Interface
- Data & Storage
- Privacy & Security
- Installation & Distribution
- And more...

Each spec includes:
- Implementation checklist with source file references
- Complete technical details and code examples
- Testing checklist (unit, integration, UI tests)

## Development

### Quick Start

First-time setup or cloning on a new machine:

```bash
# Run the setup script
./scripts/setup_dev_env.sh

# Then set environment variables in Xcode (see below)
# Build and run (Cmd+R)
```

**Required:** Set two environment variables in Xcode scheme (Edit Scheme → Run → Arguments → Environment Variables):
1. `PLAYBACK_DEV_MODE` = `1`
2. `SRCROOT` = `~/Playback` (or your actual project path)

See [DEVELOPMENT_SETUP.md](./DEVELOPMENT_SETUP.md) for detailed setup instructions including:
- Xcode environment variable configuration
- Development vs production mode
- Setting up on new machines
- Troubleshooting common issues

See [AGENTS.md](./AGENTS.md) for comprehensive development guidelines including:
- Building and testing procedures
- LaunchAgent management
- Database migrations
- SwiftUI patterns and state management
- Code style and best practices
- Advanced troubleshooting

## Technical Stack

- **Platform**: macOS 26.0 (Tahoe) or later, Apple Silicon only
- **Languages**: Swift 6.0+ (app), Python 3.12+ (services)
- **Frameworks**: SwiftUI, Vision, AVFoundation, ScreenCaptureKit
- **Database**: SQLite 3.45+ with WAL mode
- **Video**: FFmpeg 7.0+ with H.264 (libx264)
- **Build**: Xcode 15.0+, native Apple Silicon builds

## License

Proprietary. Copyright (c) 2026 Henrique Falconer. All rights reserved.
