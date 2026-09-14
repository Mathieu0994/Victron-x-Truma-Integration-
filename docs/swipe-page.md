# Getting Truma into the main swipe view of the on-device gui-v2

## 0. What Venus OS v3.79 actually does (Cerbo GX, 14 Sep 2026) — read this first

Everything below §0 is the pre-deployment analysis. The facts, as found on the
device:

- gui-v2's QML **is** on the rootfs, but under
  `/opt/victronenergy/gui-v2/Victron/VenusOS/` (`components/`, `pages/`, …),
  not directly under `gui-v2/`. `SwipePageModel.qml` lives at
  `…/Victron/VenusOS/components/SwipePageModel.qml`.
- Editing it does **nothing** until the line `prefer :/qt/qml/Victron/VenusOS/`
  is removed from `…/Victron/VenusOS/qmldir`: that line tells gui-v2 to use the
  copy compiled into the binary. With the line gone, gui-v2 loads the module
  from disk (the sources are identical, no speed penalty seen).
- `SwipeViewPage` requires `navButtonText`, `navButtonIcon`, `url` and `view`
  (not `iconSource`). The nav bar reads `navButtonText`/`navButtonIcon`.
- The stock model uses `insert(index, page)` in `Component.onCompleted`, not a
  `pages` list. `qml/SwipePageModel.v3.79.qml` is that stock file plus one
  block that creates `TrumaPage.qml` by URL and inserts it before
  Notifications. Icon: `qrc:/images/icon_temp_32.svg`.
- Both rootfs edits (qmldir, SwipePageModel.qml) are lost on a firmware
  update; `qml/install-swipe-page-on-cerbo.sh` re-applies them, keeps the
  originals in `/data/truma/rootfs-backup/<firmware>/`, and has a `revert`.
- The Venus OS *app* mechanism (`/data/apps`, `gui-v2-plugin-compiler.py`)
  can only add pages under Settings → Integrations, the device list, or the
  Quick Access pane on this version (`GuiPluginLoader::IntegrationType`;
  `NavigationPage` is parsed but not rendered yet). It is not a swipe page
  and the owner has ruled it out.
- Uids: `com.victronenergy.settings/...` is rejected ("contains invalid part");
  the page now takes `BackendConnection.serviceUidForType("settings")`, which
  is `dbus/com.victronenergy.settings` on the Touch.

Install (from the repo folder on the laptop; details in the script header):

```sh
scp -r qml root@<venus>:/data/truma-src/
ssh root@<venus> "sh /data/truma-src/qml/install-swipe-page-on-cerbo.sh"
```

---


Goal (product requirement 1): a **real top-level page** on the GX Touch 70,
next to the stock ones:

```
Brief — Overview — (Boat) — (Levels) — Truma — Notifications — Settings
```

Not a Settings sub-item, not Remote-Console-only. This document is the
written finding on how to do that, what is certain, what is not, and where
the hard stop is.

## 1. What is certain

1. **The page list is a hardcoded QML file, not data.** gui-v2 keeps the
   top-level swipe pages in `components/SwipePageModel.qml` (the Boat and
   Levels pages already appear there conditionally). Adding a page means
   editing that file. There is no settings key that adds a page.
2. **On-device gui-v2 loads QML from the rootfs at runtime.** gui-v2's own
   README states that the QML files are still on the rootfs and can be
   edited, and that doing so changes what you see on the screen (but not
   the WASM/Remote Console build, which is a separate compiled blob). This
   is the fact that makes the whole approach work without a rebuild: the
   physical GX Touch is the on-device build. (Quoted in the earlier
   `DEPLOY.md` from a gui-v2 clone; not re-verifiable in this offline
   session — step 1 below re-checks it on the device in ten seconds.)
3. **Custom QML must be loaded by URL, not by type name.** `BriefPage`,
   `OverviewPage`, … are types the `Victron.VenusOS` module knows.
   `TrumaPage.qml` is not part of that module, so `TrumaPage { }` is not a
   valid type name inside `SwipePageModel.qml`. It has to go through
   `Loader.setSource("file:///…/TrumaPage.qml", { … })`. The two-argument
   form matters: `SwipeViewPage` declares `view` (and, in the checkouts seen
   earlier, `iconSource` and `url`) as `required` properties, which must be
   supplied at construction.
4. **A file on disk is not a page.** Nothing loads `TrumaPage.qml` until
   `SwipePageModel.qml` references it, and nothing loads
   `TrumaPageContent-v2.qml` until `TrumaPage.qml` references it. Both are
   verified with `grep` in `DEPLOY.md` §4, before the GUI is restarted.
5. **`/data` survives firmware updates; `/opt/victronenergy/gui-v2` does
   not.** So `TrumaPage.qml` and `TrumaPageContent-v2.qml` live in
   `/data/truma/qml/` and are referenced by absolute `file:///data/…` URLs.
   Only the one-block edit to `SwipePageModel.qml` lives in the rootfs and
   must be re-applied after a Venus OS update (a copy of the edited file is
   kept in `/data/truma/qml/` for that).

## 2. What is not certain (and how it is handled)

- **The exact shape of `SwipePageModel.qml` on your firmware.** gui-v2
  changes between Venus OS releases: page names, whether Boat/Levels are
  `Loader`s or conditional components, what property set `SwipeViewPage`
  requires, which icon files exist. This is why the repo ships a
  **snippet** (`qml/SwipePageModel.snippet.qml`) plus a read-first
  procedure, not a blind full-file replacement of a file I could not read
  this week. The earlier `DEPLOY.md` shipped a full replacement written
  against one specific checkout; that is exactly the kind of thing that
  breaks the GUI on a different firmware, and the Touch is the screen you
  rely on.
- **Whether the swipe model is an `ObjectModel` of page items or a list of
  component URLs.** In the first case a `Loader` child *is* a page slot
  (that is how the snippet is written, mirroring the Boat/Levels pattern).
  In the second case the entry is a data row and the Loader goes elsewhere
  (usually `MainView.qml`'s `Repeater`). Step 2 below tells them apart.
- **Icon.** The bottom navigation bar needs an `iconSource`. Icons are
  compiled into the binary (`qrc:/images/…`), so the snippet reuses the
  Levels icon until you pick another; `strings` on the binary lists the
  available names (step 2).

## 3. Procedure (user runs it — Pi testbench first, then Cerbo)

1. Confirm the runtime-QML fact on this firmware:
   ```sh
   ls -l /opt/victronenergy/gui-v2/components/SwipePageModel.qml \
         /opt/victronenergy/gui-v2/components/SwipeViewPage.qml
   ```
   Both exist → runtime QML, continue. **Neither exists** (only a
   `venus-gui-v2` binary, `.qmlc` caches or `.rcc` resources) → see §4,
   hard stop.
2. Read the stock file and the page base:
   ```sh
   cat /opt/victronenergy/gui-v2/components/SwipePageModel.qml
   grep -n "required property\|property" /opt/victronenergy/gui-v2/components/SwipeViewPage.qml
   strings /opt/victronenergy/gui-v2/venus-gui-v2 | grep -o 'images/icon_[a-z_0-9]*\.svg' | sort -u | head -40
   ```
   Note (a) the entry for Levels or Boat, (b) which properties are
   `required` on `SwipeViewPage`, (c) an icon name you like.
3. Edit the snippet so its `setSource` property map is exactly the set
   found in 2(b), using the same expressions the Levels/Boat entry uses,
   then insert it before the Notifications entry — `DEPLOY.md` §5 has the
   backup / insert / diff / restart / verify / rollback commands.
4. On the Touch: swipe. Truma sits between Levels and Notifications. If
   the page slot is there but blank, `TrumaPage.qml` failed to load — check
   `svc`'s gui-v2 log (`DEPLOY.md` §5) and the on-screen fallback label.

Test on the **Pi testbench** (Venus OS Large 3.75, HDMI) first. It has the
same gui-v2 layout as the Cerbo for this purpose, and a broken swipe model
there costs nothing.

## 4. Hard stop: when a rebuild would be required

If step 1 finds **no** `SwipePageModel.qml` on the rootfs (i.e. this
firmware ships gui-v2's QML compiled into the `venus-gui-v2` binary or an
`.rcc` bundle), then there is no honest way to add a top-level page without
rebuilding gui-v2 for the device: the page list is inside the compiled
resource and `Loader`-ing a file from `/data` cannot append to it.

That rebuild is **its own hard stop** — do not start it from this repo and
do not fall back to a Settings entry instead:

- What it is: build `victronenergy/gui-v2` (Qt 6, `qt_add_qml_module`) with
  the Venus OS SDK for the Cerbo's architecture (armv7 for Cerbo GX; check
  `uname -m`), with `qml/SwipePageModel.snippet.qml` applied to
  `components/SwipePageModel.qml` and `TrumaPage.qml` + content added to
  the module, then replace `/opt/victronenergy/gui-v2/venus-gui-v2` and
  restart with `svc -t /service/gui-v2`.
- Files touched on the device: the binary only (and it is overwritten by
  the next firmware update).
- Why it is a hard stop: it needs the Venus SDK/toolchain for the exact
  firmware version, produces an unsigned replacement of a stock binary, and
  cannot be tested anywhere but on a device with the screen.

Until step 1 says otherwise, the runtime-QML path in §3 is the plan. It
is grounded in gui-v2's own README statement and in the Boat/Levels Loader
pattern that already exists in that file; it has **not** been run against a
real Qt runtime in this session (none available), which is why the Pi
comes before the Cerbo.
