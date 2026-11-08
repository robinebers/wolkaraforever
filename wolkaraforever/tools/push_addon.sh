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
bash wolkaraforever/tools/require_idle_device.sh "$session"
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

job=$(uuidgen | tr '[:lower:]' '[:upper:]')
stage="tmp/mobile-addon-$job"
copy=(xcrun devicectl device copy)
scope=(--device "$device" --domain-type appDataContainer --domain-identifier "$bundle")
for file in $files; do
    "${copy[@]}" to "${scope[@]}" --source "$addon/$file" --destination "$stage/$file" >/dev/null
    "${copy[@]}" from "${scope[@]}" --source "$stage/$file" --destination "$session/$file" >/dev/null
    cmp "$session/$file" "$addon/$file"
done

DEVICECTL_CHILD_WOLKARA_MOBILE_ADDON_JOB="$job" xcrun devicectl device process launch --device "$device" "$bundle" >/dev/null
for _ in {1..15}; do
    if "${copy[@]}" from "${scope[@]}" --source "Documents/$destination/.install-id" \
        --destination "$session/receipt" >/dev/null 2>&1 && [[ $(cat "$session/receipt") == "$job" ]]; then
        echo "push_addon: verified and installed; ready for the next game launch"
        exit 0
    fi
    rm -f "$session/receipt"
    sleep 1
done
echo "push_addon: activation unconfirmed; check the launcher log before retrying" >&2
exit 1
