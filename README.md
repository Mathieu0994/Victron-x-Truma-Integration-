# Truma D6E ↔ Victron Venus OS

Control a Truma Combi D6E (via a Truma iNet X panel, Bluetooth LE) from a
Victron GX device: a Node-RED bridge, a Dashboard 2 UI reachable through VRM,
and a custom page for the GX Touch.

> **Status: working for the author, unproven for everyone else.** The
> Node-RED bridge, the dashboard and the GX Touch page run daily on a Cerbo GX
> with Venus OS v3.79 (the Touch page since 14 Sep 2026). The optional
> temperature service has not been run on a device. The heater interlock has
> not been validated against hardware. See "What is and isn't proven" below
> and read `docs/DEPLOY.md` before you deploy anything.
>
> This is a hobby integration. It is not endorsed by Victron or Truma, it
> writes to a **diesel heater**, and you own the consequences of running it.

```
GX Touch (QML)  ─┐
                 ├─ D-Bus /Settings/Truma/*  ─  Node-RED bridge
VRM / browser   ─┘                                   │
                        Node-RED command queue ──────┘
                                   │
                     node-red-contrib-truma-inetx
                                   │
                        BlueZ  ─  iNet X  ─  D6E
```

## Requirements

- A GX device running **Venus OS Large** (Node-RED included). Developed and
  run on a Cerbo GX with Venus OS v3.79; a Raspberry Pi running Venus OS Large
  works for testing. The GX Touch page has only been verified on v3.79.
- A Truma iNet X panel, already paired with the GX device's Bluetooth.
- [`node-red-contrib-truma-inetx`](https://github.com/node-red-contrib/node-red-contrib-truma-inetx)
  installed in Node-RED. This project does the Venus side only; all BLE
  protocol work is that package's.

## What's here

| Path | What |
|---|---|
| `flows/truma-venus-flows.json` | the whole Node-RED side: BLE polling, command queue, weekly timers, failsafe, Dashboard 2 pages, and the D-Bus bridge |
| `qml/TrumaPage.qml`, `qml/TrumaPageContent-v2.qml` | the GX Touch page |
| `qml/SwipePageModel.v3.79.qml`, `qml/install-swipe-page-on-cerbo.sh` | makes it a real top-level swipe page (Venus OS v3.79); install, backup and revert in one script |
| `venus/patches/truma-inetx-adapter/` | optional: lets the Truma node use a USB Bluetooth adapter instead of the built-in chip (prepared, not yet tested) |
| `venus/dbus-truma-temp/` | optional Python service exposing room/boiler temperature as proper Venus temperature sensors (for VRM; the Touch does not need it) |
| `docs/DEPLOY.md` | step-by-step install, verification and rollback |
| `docs/dbus-paths.md`, `docs/INTERFACE.md` | every D-Bus path and command key, with types and units |
| `docs/swipe-page.md` | how the top-level swipe page works, and when a gui-v2 rebuild would be needed |
| `docs/ble-recovery.md` | timeouts, the "phone stole the Bluetooth link" case, and the watchdog |

## Quick start

1. Install `node-red-contrib-truma-inetx` in Node-RED on the GX device.
2. Import `flows/truma-venus-flows.json` (Node-RED menu → Import) and Deploy.
   The device node is set to auto-target the first iNet X panel it finds; if
   you have more than one, pin yours in that node's config.
3. The flow creates its `/Settings/Truma/*` paths itself on the first start.
   Verify with:
   `dbus -y com.victronenergy.settings /Settings/Truma/RoomMode GetValue`
4. Dashboard: `https://<gx-ip>:1881/dashboard` — the same page VRM's
   "Node-RED Dashboard" button opens.
5. GX Touch page: `qml/install-swipe-page-on-cerbo.sh` (see `docs/swipe-page.md`
   §0). Temperature service, only if you want the two temperatures in VRM:
   `docs/DEPLOY.md` §6.
6. **Before trusting it to run the heater**, do the interlock check in
   `docs/DEPLOY.md` §8, in person, in a ventilated space.

Optional: to enable the Bluetooth watchdog, set `TRUMA_MAC` to your panel's
address (Node-RED → the *Truma Poller* tab → Properties → Environment
variables, or `process.env.TRUMA_MAC` in `settings-user.js`). Without it the
watchdog stays off; nothing else changes. With a USB Bluetooth adapter (e.g.
TP-Link UB500) also set `TRUMA_BLE_ADAPTER` to that adapter's address and apply
`venus/patches/truma-inetx-adapter/` — the stock package always takes the
first adapter, i.e. the Cerbo's built-in chip.

## Features

- Room climate (on/off, setpoint, fast/comfort fan profile)
- Hot water (40/60/70 °C, off, boost) — the mode + activate sequence the
  panel needs is handled for you
- Energy source: diesel / electric 900 / electric 1800 / hybrid 900 /
  hybrid 1800, written in an order that never overshoots the power draw
- Ventilator (fan level 0–10)
- Weekly timers, temperature history, and a diagnostics page (link health,
  manual read, queue flush, "release Bluetooth for the Truma app")
- One single-flight command queue: the touchscreen, the dashboard and the
  timers can never write to the BLE link at the same time
- Optimistic UI with rollback, exponential backoff, circuit breaker

## What is and isn't proven

| Part | Status |
|---|---|
| Node-RED bridge, command queue, BLE read/write | running daily on a Cerbo GX |
| Dashboard 2 pages, VRM access | running; layout still being tuned |
| `/Settings/Truma/*` creation and mirroring | running |
| GX Touch QML page (top-level swipe page) | running on a Cerbo GX / GX Touch 70, Venus OS v3.79, since 14 Sep 2026 |
| `dbus-truma-temp` temperature service | written, **not yet run on a device**; optional, the Touch reads the bridge's mirror paths instead |
| USB Bluetooth adapter patch (`venus/patches/`) | written, **not yet applied or tested** |
| Heater interlock (modes mutually exclusive) | by construction, **not hardware-validated** |
| Fault/error codes from the D6E | **not implemented** — the topic that carries them is unknown to me; pointers welcome |

## Known limitations

- Only tested against one D6E with one iNet X panel, on Venus OS Large v3.79.
- The swipe page edits two gui-v2 files on the rootfs (the `qmldir` and
  `SwipePageModel.qml`), which a firmware update overwrites: re-run
  `qml/install-swipe-page-on-cerbo.sh` afterwards. Everything else lives in
  `/data` and survives. Other firmware versions may lay gui-v2 out
  differently; `docs/swipe-page.md` says what to check first.
- The GX Touch page only affects the physical screen, not the WASM/Remote
  Console build.
- Reads take 1.5–16 s typically, occasionally over a minute.

## Credits

BLE protocol work: [`node-red-contrib-truma-inetx`](https://github.com/node-red-contrib/node-red-contrib-truma-inetx).
The package is used as published; the only optional change is the small
adapter-selection patch in `venus/patches/`, applied locally.

Issues and corrections welcome — especially from anyone who knows the iNet X
fault-code topic, or who has run this on a different firmware.
