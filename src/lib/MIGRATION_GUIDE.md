# Migration Guide: Using macos.py Library

This guide shows how to refactor `record_screen.py` to use the new `macos.py` library.

## Summary of Changes

The following functions were extracted from `record_screen.py` (lines 40-291) into `src/lib/macos.py`:

| Original Function | New Function | Lines |
|------------------|--------------|-------|
| `_load_coregraphics()` | `macos.load_coregraphics()` | 40-49 |
| `_check_display_active()` | `macos.is_display_active()` | 52-87 |
| `_get_active_display_index()` | `macos.get_active_display_index()` | 90-168 |
| `_check_screensaver_via_applescript()` | `macos.is_screensaver_active()` | 171-196 |
| `is_screen_unavailable()` | `macos.is_screen_unavailable()` | 199-226 |
| `_get_frontmost_app_bundle_id()` | `macos.get_frontmost_app_bundle_id()` | 274-291 |

## Before: record_screen.py (Original)

```python
import ctypes
import ctypes.util
import subprocess

# Global CoreGraphics reference
_CG = None

def _load_coregraphics():
    """Carrega a framework CoreGraphics via ctypes (lazy)."""
    global _CG
    if _CG is not None:
        return _CG
    path = ctypes.util.find_library("CoreGraphics")
    if not path:
        raise RuntimeError("CoreGraphics framework não encontrada")
    _CG = ctypes.CDLL(path)
    return _CG

def _check_display_active() -> Optional[bool]:
    """Verifica se há displays ativos usando CoreGraphics."""
    try:
        cg = _load_coregraphics()
    except Exception as e:
        print(f"[Playback] DEBUG: CoreGraphics indisponível: {e}")
        return None
    # ... 30+ lines of implementation

def _get_active_display_index() -> Optional[int]:
    """Descobre o índice do monitor em uso."""
    try:
        cg = _load_coregraphics()
    except Exception as e:
        print(f"[Playback] CoreGraphics indisponível: {e}")
        return None
    # ... 70+ lines of implementation

def _check_screensaver_via_applescript() -> Optional[bool]:
    """Verifica se o protetor de tela está ativo."""
    try:
        script = 'tell application "System Events" to tell screen saver preferences to get running'
        result = subprocess.run(["osascript", "-e", script], ...)
        # ... implementation
    except Exception as e:
        return None

def is_screen_unavailable() -> bool:
    """Retorna True se a tela NÃO deve ser gravada."""
    screensaver_active = _check_screensaver_via_applescript()
    if screensaver_active is True:
        return True
    display_active = _check_display_active()
    if display_active is False:
        return True
    return False

def _get_frontmost_app_bundle_id() -> str:
    """Usa AppleScript para descobrir o bundle id do app em foco."""
    script = 'tell application "System Events" to get bundle identifier of ...'
    try:
        out = subprocess.check_output(["osascript", "-e", script], text=True).strip()
        return out or "unknown"
    except Exception:
        return "unknown"

def generate_chunk_name(now: datetime) -> str:
    """Gera um nome de arquivo único."""
    # ... implementation
    app_id = _sanitize_app_id(_get_frontmost_app_bundle_id())
    return f"{date_part}-{ts}-{short_uuid}-{app_id}"

def capture_screen(output_path: Path) -> None:
    """Usa screencapture para tirar screenshot."""
    display_index = _get_active_display_index()
    cmd = ["screencapture", "-x", "-t", "png"]
    if display_index is not None:
        cmd.extend(["-D", str(display_index)])
    # ... rest of implementation

def main():
    """Loop principal."""
    while True:
        if is_screen_unavailable():
            time.sleep(interval_seconds)
            continue
        # ... capture logic
```

## After: record_screen.py (Refactored)

```python
from lib import macos

# Remove all the internal functions - they're now in macos.py
# Remove: _load_coregraphics, _check_display_active, _get_active_display_index
# Remove: _check_screensaver_via_applescript, is_screen_unavailable
# Remove: _get_frontmost_app_bundle_id

def generate_chunk_name(now: datetime) -> str:
    """Gera um nome de arquivo único."""
    date_part = now.strftime("%Y%m%d")
    ts = now.strftime("%H%M%S")
    short_uuid = uuid.uuid4().hex[:8]

    # Use library function instead of internal function
    bundle_id = macos.get_frontmost_app_bundle_id()
    app_id = _sanitize_app_id(bundle_id or "unknown")

    return f"{date_part}-{ts}-{short_uuid}-{app_id}"

def capture_screen(output_path: Path) -> None:
    """Usa screencapture para tirar screenshot."""
    temp_path = output_path.with_suffix(".png")

    # Use library function instead of internal function
    display_index = macos.get_active_display_index()

    cmd = ["screencapture", "-x", "-t", "png"]
    if display_index is not None:
        print(f"[Playback] Usando screencapture -D {display_index}")
        cmd.extend(["-D", str(display_index)])

    cmd.append(str(temp_path))
    subprocess.run(cmd, check=True)
    temp_path.rename(output_path)

def main(interval_seconds: int = 2) -> None:
    """Loop principal."""
    print(f"[Playback] Iniciando gravação de tela com intervalo de {interval_seconds}s...")

    while True:
        now = datetime.now()

        # Use library function instead of internal function
        if macos.is_screen_unavailable():
            print(f"[Playback] Tela indisponível; pulando captura.")
            time.sleep(interval_seconds)
            continue

        day_dir = ensure_chunk_dir(now)
        chunk_name = generate_chunk_name(now)
        chunk_path = day_dir / chunk_name

        try:
            capture_screen(chunk_path)
            print(f"[Playback] Captura salva em: {chunk_path}")
        except subprocess.CalledProcessError as e:
            print(f"[Playback] ERRO ao capturar tela: {e}")

        time.sleep(interval_seconds)
```

## Key Changes

### 1. Remove Internal Functions

Delete the following from `record_screen.py`:
- Lines 33-49: `_CG` global and `_load_coregraphics()`
- Lines 52-87: `_check_display_active()`
- Lines 90-168: `_get_active_display_index()`
- Lines 171-196: `_check_screensaver_via_applescript()`
- Lines 199-226: `is_screen_unavailable()`
- Lines 274-291: `_get_frontmost_app_bundle_id()`

### 2. Add Import

Add at the top of `record_screen.py`:

```python
from lib import macos
```

### 3. Replace Function Calls

| Old Call | New Call |
|----------|----------|
| `is_screen_unavailable()` | `macos.is_screen_unavailable()` |
| `_get_active_display_index()` | `macos.get_active_display_index()` |
| `_get_frontmost_app_bundle_id()` | `macos.get_frontmost_app_bundle_id()` |

### 4. Update Error Handling

The library functions return `None` on failure, so update checks:

```python
# Old
display_index = _get_active_display_index()
if display_index is not None:
    cmd.extend(["-D", str(display_index)])

# New (same, but using library)
display_index = macos.get_active_display_index()
if display_index is not None:
    cmd.extend(["-D", str(display_index)])
```

## Benefits of Migration

1. **Code Reuse**: macOS integration logic can be shared across multiple scripts
2. **Better Organization**: System-specific code separated from application logic
3. **Easier Testing**: Library functions can be tested independently
4. **Type Safety**: Comprehensive type hints for all functions
5. **Documentation**: Full API documentation and usage examples
6. **Maintainability**: Single place to fix bugs or add features

## Additional Functions Available

The library also provides functions not in the original `record_screen.py`:

### New Functions

```python
# Get number of active displays
count = macos.get_active_display_count()

# Get mouse location
x, y = macos.get_mouse_location()

# Get display bounds
x, y, width, height = macos.get_display_bounds(display_id)

# Get frontmost app name (not just bundle ID)
app_name = macos.get_frontmost_app_name()

# Check if user is idle
if macos.is_user_idle(threshold_seconds=300):
    print("User has been idle for 5+ minutes")
```

## Testing the Migration

After refactoring, verify everything works:

```bash
# 1. Test the library
python3 src/lib/test_macos.py

# 2. Test record_screen.py still works
PLAYBACK_DEV_MODE=1 python3 src/scripts/record_screen.py

# 3. Verify screenshots are captured
ls -la dev_data/temp/$(date +%Y%m)/*

# 4. Check logs for errors
tail -f dev_logs/recording.log
```

## Rollback Plan

If issues occur after migration:

1. **Keep a backup**: Copy original `record_screen.py` before refactoring
2. **Git revert**: Use `git checkout record_screen.py` to restore original
3. **Incremental migration**: Migrate one function at a time, test between each

## Example: Full Refactored record_screen.py

See the complete refactored version in `src/scripts/record_screen_refactored.py` (if created) or follow the patterns above to complete the migration.

## Questions?

- Check `src/lib/README_macos.md` for full API documentation
- Run `python3 src/lib/test_macos.py` to see usage examples
- Review original extraction in git history for implementation details
