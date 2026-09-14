# INTERFACE.md — the frozen Truma D6E contract

Everything below was read out of the two source files in this repo **before
any edit was made**:

- `truma-dashboard-flows-v1.13.json` (161 nodes, 8 tabs) — the working Node-RED flow
- `TrumaPageContent-v2.qml` (514 lines) — the GX Touch page

`README-v1.13.md` was named in the task but was **not** in the uploaded
files, so nothing here is quoted from it.

The rule applied throughout: **QML names and flow command keys are frozen.**
Where they disagreed, the bridge (`Truma Bridge` tab) was changed, never the
QML uids and never the command keys. See `truma-dashboard-flows-v1.14.json`
for the result and the "Changes v1.13 → v1.14" section at the bottom.

---

## 1. Device and dashboard (flow, config nodes) — unchanged

| Item | Value | Source (v1.13) |
|---|---|---|
| BLE device node | `truma_device`, type `truma-inetx-device` | `"bluetooth": "bluez"`, `"targetMode": "first"` (published default; set to `device` to pin your own panel), `"deviceName": "Truma iNetX-XXXXXX"`, `"deviceAddress": "<panel-mac>"`, `"pollOnDeploy": false` |
| Read node | `truma_get`, type `truma-inetx-get` | `"topics": "RoomClimate,AirHeating,EnergySrc,WaterHeating,AirCirculation"` |
| Write node | `truma_set`, type `truma-inetx-set` | fed by `queue_mgr` with `{ topic: cmd.tn, parameter: cmd.pn, value: cmd.value }` |
| Dashboard base | `ui_base`, type `ui-base` | `"path": "/dashboard"` |
| Home page | `page_home`, type `ui-page` | `"path": "/home"` → live URL `/dashboard/home` |
| Local MQTT broker | `mqtt_venus` | `"broker": "127.0.0.1"`, `"port": "1883"`, `"clientid": "truma-dashboard"` |
| Bridge tab | `tab_bridge` "Truma Bridge" | v1.13: `"disabled": true` → v1.14: `false` |

Exactly one device, one get, one set. That did not change.

---

## 2. Command keys the router understands (flow `cmd_router`) — unchanged

Quoted from `cmd_router`'s `MAP` (the comment says these were *"verified by
this project against the live D6E (August tests)"*):

| Key | Truma topic.parameter | Values | RANGE guard |
|---|---|---|---|
| `room.mode` | `RoomClimate.Mode` | 0 off / 3 heat / 5 vent | `[0,3,5]` |
| `room.tgt` | `AirHeating.TgtTemp` | tenths of °C | `50..300` |
| `room.airMode` | `AirHeating.Mode` | 0 fast / 1 comfort | `[0,1]` |
| `water.mode` | `WaterHeating.Mode` | 0=40 °C, 1=60 °C, 2=70 °C | `[0,1,2]` |
| `water.active` | `WaterHeating.Active` | 0 / 1 | `[0,1]` |
| `water.boost` | `WaterHeating.FasterHeatingMode` | 0 / 1 | `[0,1]` |
| `vent.level` | `AirCirculation.FanLevel` | 0..10 | `0..10` |
| `energy.diesel` | `EnergySrc.DieselLevel` | 0 / 1 | `[0,1]` |
| `energy.electric` | `EnergySrc.ElectricLevel` | 0 / 1 / 2 | `[0,1,2]` |

Composite keys that `cmd_router` expands itself (also unchanged):

| Key | Expansion (quoted behaviour) |
|---|---|
| `energy.mode` 1–5 | UI-only. `ENERGY = { 5:{d:1,e:0}, 3:{d:0,e:1}, 4:{d:0,e:2}, 1:{d:1,e:1}, 2:{d:1,e:2} }`, written by `energySteps()`: electric down first → diesel → electric up last |
| `water.mode` ≥ 0 | transaction: `water.mode` then `water.active = 1` with `minGap: 2000` (the 2 s) |
| `water.off` | `water.active = 0`, shown on the dashboard as `water.mode = -1` |
| `vent.on` | transaction: `room.mode = 5` then `vent.level = value` |
| `switch.<Name>` | `Switches.<Name>` passthrough |

Write path: `cmd_router → queue_mgr (single flight, coalesces plain writes,
keeps txn order) → truma_set → cmd_done (release + read back the touched
topic)`. Failure path: `catch_set → cmd_fail`. Safety net: `stuck_check`
frees the queue after 60 s.

---

## 3. Normalised state object (flow `normalise`) — unchanged

This is the object every consumer (dashboard, bridge, failsafe, schedule)
receives on the `state` links. Quoted field-for-field:

```
st.room.mode      = RoomClimate.Mode
st.room.tgt       = AirHeating.TgtTemp        (tenths)
st.room.temp      = RoomClimate.Temp ?? AirHeating.Temp   (tenths)
st.room.airMode   = AirHeating.Mode
st.room.active    = RoomClimate.Active
st.room.fanLevel  = AirCirculation.FanLevel
st.water.mode     = WaterHeating.Mode
st.water.temp     = WaterHeating.Temp         (tenths)
st.water.active   = WaterHeating.Active
st.water.boost    = WaterHeating.FasterHeatingMode
st.energy.mode    = 1..5 (from DieselLevel/ElectricLevel)  st.energy.diesel / .electric
st.online, st.lastOk, st.ts, st.caps, st.site, st.pending, st.guard
```

`st.pending` is keyed by **UI key** (`cmd.uiKey || cmd.key`), so a water
transaction pends on `water.mode` (value −1 for off), an energy transaction
on `energy.mode`, and everything else on its own key.

---

## 4. GX Touch bindings (`TrumaPageContent-v2.qml`) — frozen, unchanged

Service strings, quoted from lines 13–15:

```qml
readonly property string settingsService:   "com.victronenergy.settings"
readonly property string roomTempService:   "com.victronenergy.temperature.trumaroom"
readonly property string boilerTempService: "com.victronenergy.temperature.trumaboiler"
```

Every `VeQuickItem` uid, quoted from the `dbus` QtObject (lines 17–29), with
what the page does with it:

| QML id | uid | Read (`onValueChanged`) | Write (`send(item, v)`) | Type/unit the QML assumes |
|---|---|---|---|---|
| `dbus.roomTemp` | `…/Settings/Truma/RoomTemperature` (**since 14 Sep 2026**; was `com.victronenergy.temperature.trumaroom/Temperature`) | `root.roomTempC = valid ? value : -1`, shown `toFixed(1) + " °C"` | never | real, **whole °C** |
| `dbus.boilerTemp` | `…/Settings/Truma/BoilerTemperature` (**since 14 Sep 2026**; was `…trumaboiler/Temperature`) | same, as `waterTempC` | never | real, **whole °C** |
| `dbus.targetTemp` | `com.victronenergy.settings/Settings/Truma/TargetTemperature` | `root.tgtTemp = value` (int, when slider not pressed) | slider release: `send(dbus.targetTemp, root.tgtTemp)` | **whole °C**, slider 5..30 step 1 |
| `dbus.fanLevel` | `com.victronenergy.settings/Settings/Truma/FanLevel` | `root.fanLevel = value` (when slider not pressed) | `setFan(level)`: writes RoomMode 5 (or 0) then FanLevel | int 0..10 |
| `dbus.airMode` | `com.victronenergy.settings/Settings/Truma/AirMode` | `root.airMode = value` | Fast → 0, Comfort → 1 | int |
| `dbus.roomMode` | `com.victronenergy.settings/Settings/Truma/RoomMode` | `roomOn = (value===3)`, `ventOn = (value===5)` | `setRoomOn(true)`: FanLevel 0, Boost 0, RoomMode 3; `setRoomOn(false)`: RoomMode 0 | int 0/3/5 |
| `dbus.waterMode` | `com.victronenergy.settings/Settings/Truma/WaterMode` | `root.waterMode = value` | Eco/Comfort/Hot → 0/1/2, **immediately followed by** WaterActive 1 | int |
| `dbus.waterActive` | `com.victronenergy.settings/Settings/Truma/WaterActive` | `waterOn = (value===1)` | 1 after a mode button, 0 on OFF | int |
| `dbus.boost` | `com.victronenergy.settings/Settings/Truma/Boost` | `boostOn = (value===1)` | `setBoost(on)`: if on also RoomMode 0; then Boost 1/0 | int |
| `dbus.energyMode` | `com.victronenergy.settings/Settings/Truma/EnergyMode` | `root.energyMode = value` | buttons 1..5 (Hybrid 900 =1, Hybrid 1800 =2, Elec 900 =3, Elec 1800 =4, Diesel =5) | int 1..5 |

Other QML facts that constrain the bridge:

- `readonly property bool bridgeUp: dbus.roomMode.valid` — the page shows
  *"Truma-bridge verbonden"* only when `/Settings/Truma/RoomMode` **exists**
  on D-Bus. It says nothing about the heater being online. So the settings
  must be created (see §6) or the page always shows the red text.
- `send()` only calls `setValue` when `item.valid`; otherwise it
  `console.log`s. Sliders commit on `onPressedChanged` (release), not per tick.
- Writes from one tap are **bursts** of 2–3 D-Bus writes in quick succession
  (e.g. Eco 40 = WaterMode 0 + WaterActive 1). The bridge must not turn that
  into duplicate heater writes (handled in `qml_in`, §7).
- The QML `EnergyMode` numbering (Hybrid 900 = 1 … Diesel = 5) is identical to
  the flow's `ENERGY` table — no translation needed.

---

## 5. Bridge, as it was in v1.13 (`Truma Bridge` tab, disabled)

Transport: the Venus OS MQTT mirror of D-Bus on `127.0.0.1:1883`.

| Node | Topic / behaviour (quoted) |
|---|---|
| `mqtt_serial` | subscribes `N/+/system/0/Serial` → `portal_id` stores `global.venusPortalId` |
| `inj_keepalive` + `keepalive` | every 25 s publishes `R/<id>/keepalive` (Venus stops `N/` publishing 60 s after the last one) |
| `mqtt_soc`, `mqtt_ac` | `N/+/system/0/Dc/Battery/Soc`, `N/+/system/0/Ac/ActiveIn/Connected` → `site_in` → `st.site` |
| `publish_state` | on every state message: retained `truma/state`, and if `id && st.online`: `W/<id>/settings/0/Settings/Truma/<Leaf>` with `{ value }` |
| `mqtt_qml` | subscribes `N/+/settings/0/Settings/Truma/#` → `qml_in` |
| `qml_in` | `MAPBACK` leaf → command key; drops the message if the value equals the last polled state or a pending write exists; else emits `{ key, value, source: 'gxtouch' }` to `lnk_bridge_cmd` → `lnk_cmd_in` (and `lnk_sched_watch`) |

`publish_state` in v1.13 wrote exactly these leaves:

```
RoomMode, TargetTemperature (tgt/10), AirMode, WaterMode, EnergyMode,
RoomTemperature (temp/10), BoilerTemperature (temp/10), Online
```

`qml_in` in v1.13 accepted exactly:

```
RoomMode → room.mode, TargetTemperature → room.tgt (×10), AirMode → room.airMode,
WaterMode → water.mode, EnergyMode → energy.mode
```

### Gaps found (all closed in v1.14, none by touching the QML)

| # | Gap | Where | Fix |
|---|---|---|---|
| G1 | `FanLevel`, `WaterActive`, `Boost` never published | `publish_state` | added, from `st.room.fanLevel`, `st.water.active`, `st.water.boost` |
| G2 | `FanLevel`, `WaterActive`, `Boost` writes from the Touch ignored | `qml_in` MAPBACK | added → `vent.level`, `water.active`/`water.off`, `water.boost` |
| G3 | `Online` only written inside `if (st.online)`, so `Online = 0` can never reach D-Bus | `publish_state` | `Online` now published whenever the portal id is known |
| G4 | `publish_state` also receives the **optimistic** state from `queue_mgr` (`lnk_bridge_in` links `lnk_cmd_state`) but published the *actual* (old) values, so a tap on the Touch bounced back to the old value until the read-back confirmed it (a visible flicker of a few seconds, and a second spurious command if the user tapped again) | `publish_state` | pending values are overlaid on the published values, the same optimistic view the dashboard already shows |
| G5 | The QML's Eco/Comfort/Hot tap sends WaterMode then WaterActive 1; v1.13 would have queued `water.mode` (which already activates after 2 s) **and** a second `water.active = 1` | `qml_in` | WaterActive 1 arriving within 5 s of a WaterMode write from the Touch is dropped |
| G6 | The Settings paths do not exist on a stock Venus, so every `W/` write is silently ignored and `bridgeUp` is false | none in v1.13 (the comment says "paths must exist first, see the README") | new `ensure_settings` chain on the Bridge tab creates them with `AddSetting` at flow start; same commands in `DEPLOY.md` |
| G7 | Full re-publish every 25 s (`R/<id>/keepalive` with an empty payload asks Venus to republish *every* topic) | `keepalive` | first keepalive stays a full publish; the following ones send `{"keepalive-options":["suppress-republish"]}` |
| G8 | No recovery when the phone/Truma app takes the BLE link and the panel is never found again | none | flow-level BLE watchdog on the Poller tab (`docs/ble-recovery.md`) |

---

## 6. D-Bus paths — custom vs stock

**All Truma paths are custom.** Stock Venus OS has no heater/Truma service
of any kind. Full detail and the `localsettings` convention in `dbus-paths.md`.

| Path (on `com.victronenergy.settings`) | Bound by QML | Written by flow | Read by flow | Type | Range | Default |
|---|---|---|---|---|---|---|
| `/Settings/Truma/RoomMode` | yes | yes | yes | `i` | 0..5 | 0 |
| `/Settings/Truma/TargetTemperature` | yes | yes (÷10) | yes (×10) | `f` | 5..30 | 20 |
| `/Settings/Truma/AirMode` | yes | yes | yes | `i` | 0..1 | 1 |
| `/Settings/Truma/WaterMode` | yes | yes | yes | `i` | 0..2 | 0 |
| `/Settings/Truma/WaterActive` | yes | **new** | **new** | `i` | 0..1 | 0 |
| `/Settings/Truma/Boost` | yes | **new** | **new** | `i` | 0..1 | 0 |
| `/Settings/Truma/EnergyMode` | yes | yes | yes | `i` | 1..5 | 5 |
| `/Settings/Truma/FanLevel` | yes | **new** | **new** | `i` | 0..10 | 0 |
| `/Settings/Truma/RoomTemperature` | no | yes (÷10) | no | `f` | none | 0 |
| `/Settings/Truma/BoilerTemperature` | no | yes (÷10) | no | `f` | none | 0 |
| `/Settings/Truma/Online` | no | yes | no | `i` | 0..1 | 0 |

The last three are flow-only (kept from v1.13 for VRM/other consumers). They
are created too, otherwise their `W/` writes are silently dropped.

| Temperature service | Path | Bound by QML | Provided by |
|---|---|---|---|
| `com.victronenergy.temperature.trumaroom` | `/Temperature` (°C) | yes | `venus/dbus-truma-temp/` (optional Python mirror service, mirrors `/Settings/Truma/RoomTemperature`) |
| `com.victronenergy.temperature.trumaboiler` | `/Temperature` (°C) | yes | same, mirrors `/Settings/Truma/BoilerTemperature` |

A Node-RED `victron-virtual` node cannot produce these names (it always
names its service `…temperature.virtual_<nodeid>`), so the names the QML
already uses can only be provided by a small native D-Bus service. Without
it the page shows "—" for the two temperatures and everything else works.

---

## 7. VeQuickItem uid root — resolved on the Cerbo (v3.79, 14 Sep 2026)

**Answer:** the `dbus/` root segment is real. With the bare service names the
page showed "Geen verbinding met de Truma-bridge" although
`/Settings/Truma/RoomMode GetValue` worked. `TrumaPageContent-v2.qml` now asks
gui-v2 for the prefixed uids (`BackendConnection.serviceUidForType("settings")`
and `serviceUidFromName("com.victronenergy.temperature.trumaroom", 0)`); the
`/Settings/Truma/*` path names are unchanged. The original analysis follows.


The QML binds `uid: "com.victronenergy.settings/Settings/Truma/…"`. In
gui-v2's own pages a settings uid is normally built as
`Global.systemSettings.serviceUid + "/Settings/…"`, and on the D-Bus backend
that `serviceUid` is (from memory of gui-v2 source, **not verified in this
offline session**) `"dbus/com.victronenergy.settings"` — i.e. the item tree
has a `dbus/` root segment. If that is right, the frozen uids never resolve
and `bridgeUp` stays false even after the settings exist.

This is a QML-lookup question, not a naming one, and the task forbids
renaming, so the QML is shipped **unchanged**. `DEPLOY.md` §2 puts a
five-minute check on the Pi testbench (which you have this week) *before*
anything goes near the Cerbo: create the settings, restart the GUI, read the
status line. If it stays red, the documented contingency is a three-string
change (`"dbus/" + …` on the service strings only — the path names stay
identical), and the bridge/flow need no change either way because they
never see the uid.

---

## 8. Observations on v1.13 that shaped the bridge (dashboard side left as is)

Node-RED **flow context is per tab**. Mapping every `flow.get`/`flow.set`
in v1.13 showed:

| Key | Written on | Read on | Effect |
|---|---|---|---|
| `state` | Poller (full tree), Commands (only `pending`), Bridge (only `site`) | each tab reads its *own* copy | **v1.13 `qml_in` would have compared Touch writes against an empty object** → every echo of a mirror write becomes a heater command → endless BLE loop. This is why v1.14's bridge keeps `bridgeFull`/`bridgePending` itself (verified by `tools/test-bridge.js`). |
| `bleReleaseUntil` | Log tab (`diag_act`, "Release Bluetooth 5 min") | Poller (`poll_guard`) | the hold never reached the poller. **Fixed** in v1.14 with a `global` mirror (two lines in `diag_act`, one in `poll_guard`) so the poller and the new watchdog both stop while you pair the phone. |
| `conn` | Poller | Log (`health`, `diag_act reconnect`) | the Diagnostics "Connection health" card reads an empty object and "Reconnect" resets a copy the poller never sees. **Not changed** (dashboard-side, cosmetic; one-line fix later: read/write via `global`). |
| `lastUserAction` | Commands (`cmd_router`), Bridge (`qml_in`) | Failsafe | frost guard cannot see recent user actions, so its 10-minute "respect the user" rule never applies. **Not changed**; worth a `global` mirror when you next touch the Failsafe tab. |
| `state.pending` | Commands (`queue_mgr` accumulates it) | Poller `normalise` (reads its own `state`) | pending entries are never cleared by `normalise`'s 45 s window; they disappear visually because `normalise` emits a state without `pending`. The bridge therefore ignores pending entries older than 45 s. **Not changed** on the dashboard side. |

None of these needed a QML change or a command-key change.
