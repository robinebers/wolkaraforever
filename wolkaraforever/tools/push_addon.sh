#!/bin/bash
# Copy the Mobile UI add-on (addons/WolkaraRoue) into the game's Interface/AddOns on the
# device, as the add-on's own commit says to install it.
#
# usage: wolkaraforever/tools/push_addon.sh [--dry-run]
#
# The game reads its add-ons when its interface loads, so this refuses while a game session is
# live; like every tool that writes the game's files, it also refuses while an update is
# writing. Every file is read back from the device and compared before success is reported.
# It only adds and replaces: a file removed from the add-on stays on the device. The add-on's
# settings are not touched - they live in the game's WTF folder, not beside the add-on.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2
. wolkaraforever/tools/env.sh
device=${DEVICE:-}
bundle=${TOLKARA_BUNDLE_ID:-local.tolkara.app}
[ -n "$device" ] || { echo "push_addon: set DEVICE in local.env (see local.env.example)" >&2; exit 2; }
dry=0
case "${1:-}" in
    '') ;;
    --dry-run) dry=1 ;;
    *) echo "usage: wolkaraforever/tools/push_addon.sh [--dry-run]" >&2; exit 2 ;;
esac

session=$(mktemp -d -t wolkara-addon)
trap 'rm -rf "$session"' EXIT
PILOT_SESSION="$session" bash wolkaraforever/tools/pilot.sh state >/dev/null
grep -qx 'inspection_ok=1' "$session/state.txt" ||
    { echo "push_addon: cannot inspect the device; unlock it and check the connection" >&2; exit 1; }
grep -qx 'update_writing=0' "$session/state.txt" ||
    { echo "push_addon: the updater recently wrote game files; wait until it finishes" >&2; exit 1; }
grep -qx 'app_running=0' "$session/state.txt" ||
    { echo "push_addon: quit the game and launcher before copying the add-on" >&2; exit 1; }
# An interrupted first install may be idle with gigabytes in staging. Only copy to
# a published installation, so we never create the active game folder prematurely.
python3 - "$session/files.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as handle:
    paths = {entry.get("relativePath") for entry in json.load(handle)["result"]["files"]}
root = "Documents/World of Warcraft/"
required = {root + ".build.info", root + "_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft"}
if not required.issubset(paths):
    sys.exit("push_addon: wait for the launcher to finish installing Forever and offer Play")
PY

addon=addons/WolkaraRoue
destination="World of Warcraft/_forever_/Interface/AddOns/WolkaraRoue"
files=$(cd "$addon" && ls -- *.toc *.lua *.xml 2>/dev/null)
[ -n "$files" ] || { echo "push_addon: nothing to copy in $addon" >&2; exit 1; }
echo "push_addon: $(echo "$files" | wc -l | tr -d ' ') file(s) to $destination"
if [ "$dry" = 1 ]; then echo "$files"; echo "push_addon: dry run, nothing copied"; exit 0; fi

for file in $files; do
    xcrun devicectl device copy to --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" --source "$addon/$file" --destination "Documents/$destination/$file" > /dev/null
done
for file in $files; do
    DEVICE_LOG_FILE="$destination/$file" bash wolkaraforever/tools/device_log.sh 0 > /dev/null
    cmp -s "build/device-log-files/$file" "$addon/$file" ||
        { echo "push_addon: $file read back from the device is not the one copied" >&2; exit 1; }
done
echo "push_addon: done; every file read back identical. The game loads it at its next login or /reload."
