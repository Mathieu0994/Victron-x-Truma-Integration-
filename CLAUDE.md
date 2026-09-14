# CLAUDE.md — project conventions

Truma Combi D6E ↔ Victron Venus OS integration. Read this before changing anything.

## Who you're working with

The owner is not a developer and has no prior coding experience. Explain
technical terms in plain language rather than assuming familiarity — with
file formats, tools and jargon alike. Keep answers short and concrete. He
communicates in Dutch; answer in Dutch unless he writes in English.

## What this is

```
GX Touch 70 (custom QML page)
      |  D-Bus: com.victronenergy.settings  /Settings/Truma/*
Node-RED "Truma Bridge" tab  (Venus MQTT mirror on 127.0.0.1:1883)
      |
Node-RED command queue  ->  node-red-contrib-truma-inetx (get/set)
      |
BlueZ  ->  Truma iNet X panel  ->  D6E

Browser / VRM  ->  Node-RED Dashboard 2  ->  same command queue
```

Hardware: Cerbo GX + GX Touch 70, Venus OS **Large**. A Raspberry Pi running
Venus OS Large is the testbench for QML work.

| Path | What |
|---|---|
| `flows/truma-venus-flows.json` | the entire Node-RED side |
| `qml/TrumaPage.qml`, `qml/TrumaPageContent-v2.qml` | GX Touch page (confirmed on the Cerbo, 14 Sep 2026) |
| `qml/SwipePageModel.v3.79.qml`, `qml/install-swipe-page-on-cerbo.sh` | makes it a top-level swipe page on Venus OS v3.79 (see `docs/swipe-page.md`) |
| `venus/patches/truma-inetx-adapter/` | lets the Truma node use a USB Bluetooth adapter (prepared, not yet applied) |
| `venus/dbus-truma-temp/` | Python service for the two temperature sensors |
| `docs/INTERFACE.md` | **every** key, path, unit and mapping — the contract |
| `docs/dbus-paths.md`, `docs/DEPLOY.md`, `docs/swipe-page.md`, `docs/ble-recovery.md` | reference and runbook |

## Hard stops — never do these without being asked, then hand off

- **Never run anything against the real Cerbo.** It isn't on this network,
  and there is a diesel heater on the other end. Prepare commands, let the
  owner run them at the van.
- **Never claim something is deployed.** Nothing is live until he deploys it.
- Heater interlock testing, BLE pairing/unpairing, and opening a PR on
  `node-red-contrib-truma-inetx` are all his to do.
- Rebuilding on-device gui-v2 is its own hard stop (see `docs/swipe-page.md`).

## Frozen — do not change

- Dashboard base path is **`/dashboard`** (VRM's button opens exactly that).
  Never `/truma`.
- Command keys the router understands: `room.mode`, `room.tgt`,
  `room.airMode`, `water.mode`, `water.active`, `water.boost`, `water.off`,
  `vent.level`, `vent.on`, `energy.mode`, `energy.diesel`, `energy.electric`.
- The QML `VeQuickItem` uids and the `/Settings/Truma/*` names. If the flow
  and the QML disagree, change the **bridge**, not the QML.
- One `truma-inetx-device`, one get, one set. All writes go through the
  single-flight command queue — never wire a new path straight to the set node.
- BLE only, via `node-red-contrib-truma-inetx`. No HTTP polling of the heater.

## Things that have bitten this project

- **Node-RED flow context is per tab.** State cached on one tab is invisible
  on another. The bridge keeps its own copy of the heater state for exactly
  this reason: comparing against another tab's copy fails silently and turns
  every mirror write back into a heater command — an endless BLE loop.
- **Every D-Bus write echoes back.** Only a value differing from both the
  heater's last reported state *and* any in-flight write is a real user action.
- **Units:** the protocol uses tenths of a degree; D-Bus and both UIs use
  whole degrees. The bridge converts.
- **Dashboard 2 row heights are fixed.** Setting a widget height to 1 does
  not make the card fit its content — it overflows. Heights are tuned
  numerically, or overridden with CSS that targets the widget's inline
  `grid-template-rows` (see the CSS block in each `ui-template`).
- **A QML file on disk is not loaded** until something references it. Verify
  with `grep` before restarting the GUI.
- **gui-v2 ignores its QML on disk** unless the `prefer :/qt/qml/…` line is
  removed from `/opt/victronenergy/gui-v2/Victron/VenusOS/qmldir` (v3.79).
  The install script does that; a firmware update puts it back.
- **VeQuickItem uids need the backend prefix** (`dbus/com.victronenergy.…`).
  The page asks `BackendConnection` for it; never hard-code a service name.
- **Venus OS "apps"** (`/data/apps`, Settings → Integrations) cannot add a
  swipe page on v3.79; the owner does not want that route. Don't propose it.
- **A stuck BlueZ session in Node-RED** shows as `DBusError: Operation
  already in progress` on every read; `svc -t /service/node-red-venus`
  clears it, then "Reset the connection" on the Diagnostics page.
- **Venus OS Large is BusyBox:** no `systemd`, no `ps aux`. Services via
  `svc`; the GUI service is `/service/start-gui` on v3.79 (`gui-v2` on
  older builds), Node-RED is `/service/node-red-venus`, its user dir is
  `/data/home/nodered/.node-red`.
- **Firmware updates overwrite the rootfs.** Custom QML lives in `/data/`;
  only the `SwipePageModel.qml` edit has to be reapplied.
- Sliders commit on release, not per tick — the GX Touch CPU is modest.
- **Never commit** the panel MAC, the VRM portal id, or any password. The
  published flow auto-targets the first iNet X panel; the BLE watchdog reads
  `TRUMA_MAC` from a Node-RED environment variable.

## How to work here

- **Read the relevant files fully before editing.** This project has been
  bitten twice by acting on assumptions instead of what the file actually says.
- Prefer targeted edits over regenerating a large file. The flow JSON is
  ~240 kB; rewriting it wholesale loses things silently.
- After changing the flow, sanity-check it: valid JSON, unique node ids,
  every wire/link target exists, `/dashboard` intact, device config untouched.
- Update `docs/INTERFACE.md` in the same commit if a key, path or unit changes.
- **Commit only when asked**, and prefer committing things that have been
  confirmed working on the device. Write commit messages that say *why*
  ("card heights back to fixed values, content was overflowing"), not "update".

## Open items

- v1.19 dashboard layout not yet confirmed on the device.
- TP-Link UB500 USB Bluetooth adapter: detected fine, but the Truma node
  always takes the first adapter (the built-in chip). Patch and flow change
  prepared in `venus/patches/truma-inetx-adapter/`, not yet applied or tested;
  the stick is currently unplugged.
- `dbus-truma-temp` still not run; only needed if the two temperatures should
  appear in VRM as sensors (the Touch reads the bridge's mirror paths since 14 Sep).
- Heater interlock guaranteed by construction, not hardware-validated.
- **Fault/error codes are not implemented** — the five polled topics don't
  carry them and the right topic is unknown. Needs a raw device-data dump
  taken while the heater shows a fault.
- A timer page for the GX Touch (weekly rules currently live only in Node-RED).
