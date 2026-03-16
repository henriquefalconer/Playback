# Plan: Smaller Timeline Segments

## Status: COMPLETED

## What was done

Reduced the visual height of timeline segment bars and adjusted all dependent elements proportionally for a more compact, refined look.

### Changes

| Element | Before | After |
|---------|--------|-------|
| Segment bar height | 20px | 12px |
| App icon in segment | 16×16 | 10×10 |
| Playhead | 4×110 | 3×70 |
| Container height | 120px | 80px |
| Bottom gradient | 140px | 100px |
| Bottom padding | 40px | 28px |
| Segments Y offset | +22 | +14 |
| Time bubble Y offset | -32 | -22 |
| Ticks Y offset | +60 | +38 |
| Major/minor ticks | 12/6 | 8/4 |

## Files Modified

- `src/Playback/Playback/TimelineView.swift` — 8 dimension changes (bar height, icon size, playhead, offsets, ticks)
- `src/Playback/Playback/ContentView.swift` — 3 dimension changes (container, gradient, padding)
- `specs/timeline-graphical-interface.md` — updated spec to match new dimensions
