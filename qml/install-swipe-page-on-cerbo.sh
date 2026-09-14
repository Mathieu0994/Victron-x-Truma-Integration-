#!/bin/sh
# Puts the Truma page into the GX Touch swipe view (Venus OS v3.79, gui-v2 on a Cerbo GX).
#
#   copy:    scp -r qml root@<venus>:/data/truma-src/
#   install: ssh root@<venus> "sh /data/truma-src/qml/install-swipe-page-on-cerbo.sh"
#   revert:  ssh root@<venus> "sh /data/truma-src/qml/install-swipe-page-on-cerbo.sh revert"
#
# What it changes on the rootfs (both files are overwritten by a firmware update: re-run then):
#   1. /opt/victronenergy/gui-v2/Victron/VenusOS/qmldir: the "prefer :/qt/qml/..." line is
#      removed, so gui-v2 reads the module's QML from disk instead of its built-in copy.
#      Without this, editing SwipePageModel.qml on disk does nothing.
#   2. .../components/SwipePageModel.qml: replaced by SwipePageModel.v3.79.qml (stock + Truma).
# What it puts under /data (survives updates): TrumaPage.qml + TrumaPageContent-v2.qml in
# /data/truma/qml/, originals of the two rootfs files in /data/truma/rootfs-backup/<firmware>/.
# It also removes the Truma entry under Settings > Integrations (/data/apps/*/truma-x-victron)
# and restarts the GUI. "revert" restores the two originals and restarts.
set -e
SRC=$(cd "$(dirname "$0")" && pwd)
G=/opt/victronenergy/gui-v2/Victron/VenusOS
FW=$(head -n 1 /opt/victronenergy/version)
BK=/data/truma/rootfs-backup/$FW
GUISVC=/service/$(ls /service | grep -i gui | head -n 1)

restart_gui() {
  echo "restarting $GUISVC"
  svc -t "$GUISVC"
  sleep 12
  if ps | grep -v grep | grep -q venus-gui-v2; then echo "GUI running"; else echo "GUI NOT running -> run this script with 'revert'"; fi
  tail -n 60 "/var/log/$(basename "$GUISVC")/current" 2>/dev/null | tai64nlocal | grep -i -E 'truma|SwipePageModel|error|warn' || true
}

if [ "$1" = "revert" ]; then
  [ -f "$BK/qmldir" ] && [ -f "$BK/SwipePageModel.qml" ] || { echo "no backup for firmware $FW in $BK"; exit 1; }
  cp "$BK/qmldir" "$G/qmldir"
  cp "$BK/SwipePageModel.qml" "$G/components/SwipePageModel.qml"
  echo "stock qmldir and SwipePageModel.qml restored"
  restart_gui
  exit 0
fi

[ -f "$G/components/SwipePageModel.qml" ] || { echo "no SwipePageModel.qml on disk: this firmware ships gui-v2 differently, stop"; exit 1; }
[ -f "$SRC/SwipePageModel.v3.79.qml" ] && [ -f "$SRC/TrumaPage.qml" ] && [ -f "$SRC/TrumaPageContent-v2.qml" ] || { echo "run from the repo's qml/ folder"; exit 1; }

# The patched file was written against the v3.79 stock file. Refuse on a different layout.
if ! grep -q 'insert(2, levelsPage)' "$G/components/SwipePageModel.qml" && ! grep -q 'insertTrumaPage' "$G/components/SwipePageModel.qml"; then
  echo "stock SwipePageModel.qml has a different layout than v3.79; read it first (docs/swipe-page.md)"; exit 1
fi

mkdir -p "$BK" /data/truma/qml
[ -f "$BK/qmldir" ] || cp "$G/qmldir" "$BK/qmldir"
[ -f "$BK/SwipePageModel.qml" ] || cp "$G/components/SwipePageModel.qml" "$BK/SwipePageModel.qml"
echo "originals kept in $BK"

cp "$SRC/TrumaPage.qml" "$SRC/TrumaPageContent-v2.qml" /data/truma/qml/
grep -q 'TrumaPageContent-v2.qml' /data/truma/qml/TrumaPage.qml || { echo "TrumaPage.qml does not reference the content page"; exit 1; }

sed -i '/^prefer /d' "$G/qmldir"
grep -q '^prefer' "$G/qmldir" && { echo "could not remove the prefer line"; exit 1; }
cp "$SRC/SwipePageModel.v3.79.qml" "$G/components/SwipePageModel.qml"
[ "$(grep -c 'file:///data/truma/qml/TrumaPage.qml' "$G/components/SwipePageModel.qml")" -ge 1 ] || { echo "patched swipe model not in place"; exit 1; }
echo "qmldir: prefer line removed; SwipePageModel.qml: Truma block in place"

rm -rf /data/apps/enabled/truma-x-victron /data/apps/available/truma-x-victron
echo "Settings > Integrations entry removed"

restart_gui
