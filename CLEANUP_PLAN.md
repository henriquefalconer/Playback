# Playback Data Cleanup Plan

**Status:** Completed (2026-03-17)

Cleanup was executed successfully. All data was reset to a clean slate, config preserved.

During execution, a startup race condition was discovered and fixed: `Paths.ensureDirectoriesExist()` was not creating the `temp/` directory, causing the first processing cycle to fail with "Failed to list temp directory". Fix: added `tempDirectory` creation to `ensureDirectoriesExist()` in `Paths.swift`.

## Quick Reference (for future cleanups)

```bash
# Quit app first
osascript -e 'tell application "Playback" to quit'

# Remove all data (preserves config.json)
rm -rf ~/Library/Application\ Support/Playback/data/temp
rm -rf ~/Library/Application\ Support/Playback/data/chunks
rm -f ~/Library/Application\ Support/Playback/data/meta.sqlite3{,-wal,-shm}
rm -f ~/Library/Application\ Support/Playback/data/.timeline_open
rm -rf ~/Library/Logs/Playback

# Relaunch
open /Applications/Playback.app
```
