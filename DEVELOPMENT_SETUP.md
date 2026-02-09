# Development Environment Setup

This guide ensures the Playback development environment is correctly configured.

## Automatic Setup (Recommended)

Run this script to automatically set up the development environment:

```bash
./scripts/setup_dev_env.sh
```

## Manual Setup

If you need to set up manually or on a new machine, follow these steps:

### 1. Set Environment Variable in Xcode

**CRITICAL:** The app determines development mode via the `PLAYBACK_DEV_MODE` environment variable.

1. In Xcode, click on the scheme dropdown (next to the Run/Stop buttons)
2. Select "Edit Scheme..."
3. Select "Run" in the left sidebar
4. Click the "Arguments" tab
5. Under "Environment Variables", click the "+" button
6. Add:
   - **Name:** `PLAYBACK_DEV_MODE`
   - **Value:** `1`
7. Click "Close"

**Verification:** After setting this, the app will:
- Use `dev_config.json` instead of production config
- Use `dev_data/` instead of `~/Library/Application Support/Playback/data/`
- Use `dev_logs/` instead of `~/Library/Logs/Playback/`
- Look for scripts in project directory instead of bundle

### 2. Create Development Files

Run from the project root:

```bash
# Create dev config
cat > dev_config.json << 'EOF'
{
  "version": "1.0.0",
  "processing_interval_minutes": 5,
  "temp_retention_policy": "1_week",
  "recording_retention_policy": "never",
  "exclusion_mode": "skip",
  "excluded_apps": [],
  "ffmpeg_crf": 28,
  "video_fps": 30,
  "timeline_shortcut": "Option+Shift+Space",
  "pause_when_timeline_open": true,
  "recording_enabled": true,
  "launch_at_login": true,
  "notifications": {
    "processing_complete": true,
    "processing_errors": true,
    "disk_space_warnings": true,
    "recording_status": true
  }
}
EOF

# Create dev directories
mkdir -p dev_data/temp dev_data/chunks dev_logs

# Add to gitignore
echo "dev_data/" >> .gitignore
echo "dev_logs/" >> .gitignore
echo "dev_config.json" >> .gitignore
```

### 3. Verify Setup

After setup, verify everything is correct:

```bash
# Check files exist
ls -la dev_config.json dev_data/ dev_logs/ src/scripts/

# Run diagnostics (optional)
./diagnose_services.sh
```

## Cloning on a New Machine

When cloning the project on a new macOS machine:

```bash
# 1. Clone the repository
git clone <repository-url>
cd Playback

# 2. Run setup script
./scripts/setup_dev_env.sh

# 3. Open in Xcode
open src/Playback/Playback.xcodeproj

# 4. Set PLAYBACK_DEV_MODE=1 in scheme (see step 1 above)

# 5. Build and run
# Press Cmd+R or click the Run button
```

## Environment Variables

The app supports these environment variables:

| Variable | Purpose | Example |
|----------|---------|---------|
| `PLAYBACK_DEV_MODE` | Enable development mode | `1` |
| `PLAYBACK_CONFIG` | Override config path | `/custom/path/config.json` |
| `PLAYBACK_DATA_DIR` | Override data directory | `/custom/path/data` |

**Set in Xcode:** Edit Scheme → Run → Arguments → Environment Variables

## Development vs Production Mode

### Development Mode (`PLAYBACK_DEV_MODE=1`)
- **Config:** `<project>/dev_config.json`
- **Data:** `<project>/dev_data/`
- **Logs:** `<project>/dev_logs/`
- **Scripts:** `<project>/src/scripts/`
- **LaunchAgents:** `com.playback.dev.*` labels

### Production Mode (default)
- **Config:** `~/Library/Application Support/Playback/config.json`
- **Data:** `~/Library/Application Support/Playback/data/`
- **Logs:** `~/Library/Logs/Playback/`
- **Scripts:** Bundled in app or Application Support
- **LaunchAgents:** `com.playback.*` labels

## Troubleshooting

### "Development Mode: false" in diagnostics

**Problem:** Xcode environment variable not set.

**Solution:** Follow step 1 above to set `PLAYBACK_DEV_MODE=1` in the scheme.

### "Scripts not found" error

**Problem:** Environment variable not set OR scripts missing.

**Solution:**
1. Verify `PLAYBACK_DEV_MODE=1` is set in Xcode scheme
2. Verify scripts exist: `ls -la src/scripts/record_screen.py`
3. Restart Xcode after changing scheme

### Services won't start

**Problem:** Development environment not fully set up.

**Solution:** Run `./scripts/setup_dev_env.sh` again.

## Quick Verification

Run this one-liner to check if dev environment is ready:

```bash
[ -f dev_config.json ] && [ -d dev_data ] && [ -d dev_logs ] && [ -f src/scripts/record_screen.py ] && echo "✓ Dev environment OK" || echo "✗ Dev environment incomplete - run setup_dev_env.sh"
```

## CI/CD Note

For CI/CD environments, set `PLAYBACK_DEV_MODE=1` in the pipeline environment variables. The app will automatically use development paths.
