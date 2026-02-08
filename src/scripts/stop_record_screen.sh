#!/bin/zsh

# Terminates any running instance of record_screen.py
# (assuming it's run from the Playback project root)

SCRIPT_PATTERN="scripts/record_screen.py"

PIDS=$(pgrep -f "$SCRIPT_PATTERN")

if [ -z "$PIDS" ]; then
  echo "[Playback] No recording process found."
  exit 0
fi

echo "[Playback] Terminating recording processes: $PIDS"
kill $PIDS

sleep 1

PIDS_RESTANTES=$(pgrep -f "$SCRIPT_PATTERN" || true)

if [ -n "$PIDS_RESTANTES" ]; then
  echo "[Playback] Some processes are still alive, forcing termination: $PIDS_RESTANTES"
  kill -9 $PIDS_RESTANTES
else
  echo "[Playback] All recording processes have been terminated."
fi