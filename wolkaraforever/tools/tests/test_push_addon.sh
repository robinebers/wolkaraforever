#!/bin/bash
# Exercise the add-on install guard with a fake device inventory.
set -euo pipefail
tools=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d -t wolkara-addon-test)
trap 'rm -rf "$work"' EXIT
cd "$work"
mkdir -p wolkaraforever/tools addons/WolkaraRoue bin
cp "$tools"/{push_addon,env}.sh wolkaraforever/tools/
touch addons/WolkaraRoue/{Interface.toc,Core.lua,Bindings.xml}
export DEVICE=fixture
export PATH="$work/bin:$PATH"
cat > bin/xcrun <<'STUB'
#!/bin/bash
touch unexpected-device-command
exit 1
STUB
chmod +x bin/xcrun
cat > wolkaraforever/tools/pilot.sh <<'STUB'
cp state.txt files.json "$PILOT_SESSION/"
STUB
ready_state() {
    printf '%s\n' inspection_ok=1 update_writing=0 app_running=0 > state.txt
}
refuses() {
    if bash wolkaraforever/tools/push_addon.sh > result 2>&1; then exit 1; fi
    grep -Fq "$1" result || { cat result >&2; exit 1; }
    test ! -e unexpected-device-command
}
ready_state
echo '{"result":{"files":[{"relativePath":"Documents/.tolkara-updates/example/installation/.build.info"}]}}' > files.json
refuses 'wait for the launcher to finish'
echo '{"result":{"files":[{"relativePath":"Documents/World of Warcraft/.build.info"},{"relativePath":"Documents/World of Warcraft/_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft"}]}}' > files.json
bash wolkaraforever/tools/push_addon.sh --dry-run | grep -q 'dry run, nothing copied'
test ! -e unexpected-device-command
for pair in 'inspection_ok=0|cannot inspect' 'app_running=1|quit the game' 'update_writing=1|recently wrote'; do
    ready_state
    key="${pair%%=*}"
    sed -i.bak "/^${key}=/d" state.txt
    echo "${pair%%|*}" >> state.txt
    refuses "${pair#*|}"
done
echo 'Add-on copy guards: incomplete, ready, unavailable, running, and updating cases passed.'
