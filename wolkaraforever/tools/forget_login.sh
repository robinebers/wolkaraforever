#!/bin/bash
# Make WoW Forever forget the Battle.net login it remembers, so its login screen starts empty.
#
# usage: wolkaraforever/tools/forget_login.sh [--dry-run]
#
# What the client remembers between launches is two lines of its WTF/Config.wtf: accountName
# (the e-mail in the login screen) and accountList (the game-account selector under it). It
# keeps no login token - its own Logs/Connection.log reports usedToken="false" - and nothing
# about the authenticator, which belongs to the Blizzard account. This removes those two lines
# and nothing else: portal and locales stay, and the login fails without them.
#
# The client rewrites Config.wtf when it exits, so this refuses while a game session is live;
# like every tool that writes the game's files, it also refuses while an update is writing.
# The file as it was is kept under build/wtf-backups/<time>/ (ignored and never committed: it
# holds the e-mail), and the result is read back from the device before success is reported.
# Restoring is a copy of that backup to the same place.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 2
. wolkaraforever/tools/env.sh
device=${DEVICE:-}
bundle=${TOLKARA_BUNDLE_ID:-local.tolkara.app}
[ -n "$device" ] || { echo "forget_login: set DEVICE in local.env (see local.env.example)" >&2; exit 2; }
dry=0
case "${1:-}" in
    '') ;;
    --dry-run) dry=1 ;;
    *) echo "usage: wolkaraforever/tools/forget_login.sh [--dry-run]" >&2; exit 2 ;;
esac

umask 077
session=$(mktemp -d -t wolkara-login)
trap 'rm -rf "$session"' EXIT
bash wolkaraforever/tools/require_idle_device.sh "$session"

config="World of Warcraft/_forever_/WTF/Config.wtf"
mkdir -p build/wtf-backups
backup=$(mktemp -d build/wtf-backups/login.XXXXXXXX)
read_config() {
    xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" --source "Documents/$config" --destination "$1" >/dev/null
}
read_config "$backup/Config.wtf"
echo "forget_login: original saved at $backup/Config.wtf"
python3 - "$backup" <<'FILTER'
from pathlib import Path
import sys
folder = Path(sys.argv[1])
lines = (folder / "Config.wtf").read_bytes().splitlines(keepends=True)
filtered = b"".join(line for line in lines if not line.startswith((b"SET accountName ", b"SET accountList ")))
if not filtered:
    sys.exit("forget_login: refusing to write an empty Config.wtf")
result = folder / "Config.forgotten.wtf"
result.write_bytes(filtered)
if result.read_bytes() != filtered:
    sys.exit("forget_login: filtered config verification failed")
FILTER
if cmp -s "$backup/Config.wtf" "$backup/Config.forgotten.wtf"; then echo "forget_login: nothing to remove"; exit 0; fi
if [ "$dry" = 1 ]; then echo "forget_login: dry run, nothing written"; exit 0; fi

xcrun devicectl device copy to --device "$device" --domain-type appDataContainer \
    --domain-identifier "$bundle" --source "$backup/Config.forgotten.wtf" \
    --destination "Documents/$config" > /dev/null
read_config "$session/readback"
if ! cmp -s "$session/readback" "$backup/Config.forgotten.wtf"; then
    echo "forget_login: the file read back from the device is not the one written" >&2
    exit 1
fi
echo "forget_login: done; the login screen starts with no e-mail and no account selector"
