#!/bin/sh
# Makes node-red-contrib-truma-inetx use the Bluetooth adapter named in the
# environment variable TRUMA_BLE_ADAPTER (adapter address such as
# 3C:78:95:78:17:71, or a name such as hci2). Without that variable the package
# behaves exactly as before: first adapter BlueZ lists.
#
# Why: the package has no adapter setting and always takes the first adapter,
# which on a Cerbo GX is the built-in chip, not a USB stick such as the
# TP-Link UB500. Upstream has no option for this; a PR is the owner's call.
#
#   apply:   sh apply-on-cerbo.sh
#   revert:  sh apply-on-cerbo.sh --revert
# Then restart Node-RED. Re-run after every update of the package.
set -e
P=/data/home/nodered/.node-red/node_modules/node-red-contrib-truma-inetx/dist
for f in ble.js index.js; do
  [ -f "$P/$f" ] || { echo "$P/$f not found"; exit 1; }
done
if [ "$1" = "--revert" ]; then
  for f in ble.js index.js; do
    [ -f "$P/$f.orig" ] && cp "$P/$f.orig" "$P/$f" && echo "restored $f"
  done
  exit 0
fi
python3 - "$P" <<'PY'
import sys, os, shutil
P = sys.argv[1]
OLD = """function findBluezAdapterPath(objects) {
    for (const [path, interfaces] of Object.entries(objects)) {
        if (interfaces['org.bluez.Adapter1'])
            return path;
    }
    return null;
}"""
NEW = """function findBluezAdapterPath(objects) {
    // Patched (Camper-Project, venus/patches/truma-inetx-adapter): prefer the
    // adapter named in TRUMA_BLE_ADAPTER (address or hciN); otherwise the
    // first adapter BlueZ lists, which is the unpatched behaviour.
    const want = String(process.env.TRUMA_BLE_ADAPTER || '').trim().toUpperCase();
    let first = null;
    for (const [path, interfaces] of Object.entries(objects)) {
        const a = interfaces['org.bluez.Adapter1'];
        if (!a) continue;
        if (first === null) first = path;
        if (!want) return path;
        const raw = a.Address;
        const addr = raw && raw.value !== undefined ? raw.value : raw;
        if (String(addr || '').toUpperCase() === want || path.split('/').pop().toUpperCase() === want)
            return path;
    }
    return first;
}"""
for f in ('ble.js', 'index.js'):
    fp = os.path.join(P, f); s = open(fp).read()
    if NEW in s:
        print(f, 'already patched'); continue
    if s.count(OLD) != 1:
        print(f, 'ERROR: expected function not found exactly once; package version changed?'); sys.exit(1)
    if not os.path.exists(fp + '.orig'): shutil.copy(fp, fp + '.orig')
    open(fp, 'w').write(s.replace(OLD, NEW)); print(f, 'patched (backup', f + '.orig)')
PY
echo "done. Set TRUMA_BLE_ADAPTER and restart Node-RED."
