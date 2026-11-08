#!/bin/bash
# Caller provides a private temporary session directory.
set -euo pipefail
session=${1:?missing session directory}
PILOT_SESSION="$session" bash wolkaraforever/tools/pilot.sh state >/dev/null
grep -qx 'inspection_ok=1' "$session/state.txt" ||
    { echo "device guard: cannot inspect the device; unlock it and check the connection" >&2; exit 1; }
grep -qx 'update_writing=0' "$session/state.txt" ||
    { echo "device guard: the updater recently wrote game files; wait until it finishes" >&2; exit 1; }
grep -qx 'app_running=0' "$session/state.txt" ||
    { echo "device guard: quit the game and launcher before changing game files" >&2; exit 1; }
