# Deploying the Truma D6E integration — v1.14

**Supersedes** the earlier `DEPLOY.md` in the project (which deployed a
different contract: `OperatingMode`/`RoomSetpoint`, a `victron-virtual`
temperature node, and a full-file `SwipePageModel.qml` replacement). Do not
mix the two. If any of that older version was ever deployed, its rollback
section applies first.

**Nothing below has been run on your Cerbo or your Pi from this session.**
Running commands on the Cerbo, testing the interlock on the heater, and
pairing/unpairing the iNet X are hard stops: you do them, when you are at
the camper. The Pi testbench is the exception the task allows and is the
best use of the week the Cerbo is away — §1 is written for it.

Conventions: `<venus>` = the Pi's or the Cerbo's IP/`venus.local`; every
device command is an SSH session as `root` (Venus OS Large: Settings →
General → Access Level → SSH). Venus OS Large is BusyBox: no `systemd`, no
`ps aux`; services are `svc`; the GUI restart is `svc -t /service/gui-v2`.

Files you copy from this repo:

| What | From | To on the device |
|---|---|---|
| Node-RED flow | `truma-dashboard-flows-v1.14.json` | imported in the editor (§2), not scp'd |
| Page wrapper | `qml/TrumaPage.qml` | `/data/truma/qml/TrumaPage.qml` |
| Page content (unchanged) | `qml/TrumaPageContent-v2.qml` | `/data/truma/qml/TrumaPageContent-v2.qml` |
| Swipe entry | `qml/SwipePageModel.snippet.qml` | pasted into `/opt/victronenergy/gui-v2/components/SwipePageModel.qml` (§5) |
| Temperature services | `venus/dbus-truma-temp/` | `/data/truma/dbus-truma-temp/` (§6) |

---

## 0. Before you start (Pi or Cerbo)

```sh
ssh root@<venus> "cat /opt/victronenergy/version; uname -m; which dbus bluetoothctl python3; ls ~/.node-red/node_modules | grep -i -E 'truma|victron'"
```

You want: the firmware version noted; `dbus` and `python3` found
(`bluetoothctl` too on the Cerbo); `node-red-contrib-truma-inetx` and
`@victronenergy/...` (or `victron-...`) listed. If `dbus` is missing the
settings step (§3) has no tool to run — stop and say so.

Keep a copy of what is there now:

```sh
mkdir -p backup && cd backup
ssh root@<venus> "cp /opt/victronenergy/gui-v2/components/SwipePageModel.qml /data/truma-SwipePageModel.qml.orig 2>/dev/null; mkdir -p /data/truma"
```

and, in the Node-RED editor on the Cerbo: Menu ☰ → Export → *all flows* →
Download. That file is your Node-RED rollback.

---

## 1. Pi testbench first — the two things only a real Venus can answer

The Pi (Venus OS Large 3.75, HDMI) settles two open questions before the
Cerbo is touched. Neither needs the heater.

### 1a. Do the frozen QML uids resolve? (`INTERFACE.md` §7)

Create the settings paths by hand (same commands the flow runs at start):

```sh
ssh root@<venus> '
dbus -y com.victronenergy.settings /Settings AddSetting Truma RoomMode 0 i 0 5
dbus -y com.victronenergy.settings /Settings AddSetting Truma TargetTemperature 20.0 f 5.0 30.0
dbus -y com.victronenergy.settings /Settings AddSetting Truma AirMode 1 i 0 1
dbus -y com.victronenergy.settings /Settings AddSetting Truma WaterMode 0 i 0 2
dbus -y com.victronenergy.settings /Settings AddSetting Truma WaterActive 0 i 0 1
dbus -y com.victronenergy.settings /Settings AddSetting Truma Boost 0 i 0 1
dbus -y com.victronenergy.settings /Settings AddSetting Truma EnergyMode 5 i 1 5
dbus -y com.victronenergy.settings /Settings AddSetting Truma FanLevel 0 i 0 10
dbus -y com.victronenergy.settings /Settings AddSetting Truma RoomTemperature 0.0 f 0.0 0.0
dbus -y com.victronenergy.settings /Settings AddSetting Truma BoilerTemperature 0.0 f 0.0 0.0
dbus -y com.victronenergy.settings /Settings AddSetting Truma Online 0 i 0 1
dbus -y com.victronenergy.settings /Settings/Truma/RoomMode GetValue'
```

The last line must print `0`. Then deploy the two QML files (§4) and the
swipe entry (§5) on the Pi, restart the GUI, and look at the bottom-right
corner of the Truma page:

- **"Truma-bridge verbonden"** → the uids resolve as written. Nothing to
  change; the QML stays frozen.
- **"Geen verbinding met de Truma-bridge"** although `GetValue` works →
  the `VeQuickItem` tree wants a `dbus/` root. Contingency, three strings
  in `TrumaPageContent-v2.qml` lines 13–15, path names untouched:
  ```qml
  readonly property string settingsService:   "dbus/com.victronenergy.settings"
  readonly property string roomTempService:   "dbus/com.victronenergy.temperature.trumaroom"
  readonly property string boilerTempService: "dbus/com.victronenergy.temperature.trumaboiler"
  ```
  Re-copy, `svc -t /service/gui-v2`, check again. Record the answer in
  `INTERFACE.md` §7 so it is not re-discovered on the Cerbo.

Then prove the write path without any heater: on the Pi, run

```sh
ssh root@<venus> "dbus -y com.victronenergy.settings /Settings/Truma/RoomMode SetValue 3"
```

→ the Room Climate switch on the HDMI screen must flip to *Aan*. Tap it
off on the screen → `GetValue` must return `0`.

### 1b. Does the swipe insert work on this gui-v2?

`docs/swipe-page.md` §3 steps 1–4, then §5 below, on the Pi. A wrong
insert on the Pi costs a `cp` back; on the Cerbo it costs your only screen.

---

## 2. Node-RED: import v1.14 (Cerbo, later)

Open `https://<venus>:1881/` (Venus OS Large → Settings → Services →
Node-RED must be on).

1. Menu ☰ → **Import** → select `truma-dashboard-flows-v1.14.json`.
2. Node-RED will say the import contains nodes that already exist (same
   ids as your running v1.13). Choose **Replace** ("import as replacement" /
   "Replace existing nodes"), **not** "copy": v1.14 is v1.13 with 6 nodes
   edited and 9 added (`CHANGES-v1.14.md`); replacing keeps every widget,
   schedule rule and context key where it is.
3. Confirm the config nodes were kept, not duplicated: Menu ☰ →
   Configuration nodes. Exactly one `truma-inetx-device` (*Truma iNet X*,
   `<panel-mac>`), one `mqtt-broker` (*Venus OS local*), one
   `ui-base` at `/dashboard`.
4. **Deploy** (Full).
5. Watch the **Truma Bridge** tab (now enabled) for about ten seconds:
   - `Learn portal id` → green with your portal id
   - `Keepalive` → *alive (full publish)* then *alive*
   - `Ensure Truma settings: result` → *settings ok*
   - `Publish to D-Bus mirror` → *N paths* after the first read (8 s)
   - `GX Touch to command` → idle until you tap the Touch
   And the **Truma Poller** tab: `BLE watchdog` idle (it only acts while
   reads fail).
6. The dashboard is still at `https://<venus>:1881/dashboard` (home page
   `/dashboard/home`). Nothing moved.

No Node-RED process restart is needed: no package was changed, only the
flow.

---

## 3. Verify the D-Bus settings paths

```sh
ssh root@<venus> 'for p in RoomMode TargetTemperature AirMode WaterMode WaterActive Boost EnergyMode FanLevel RoomTemperature BoilerTemperature Online; do printf "%-18s " $p; dbus -y com.victronenergy.settings /Settings/Truma/$p GetValue; done'
```

Eleven lines, each a number. Once the flow has read the heater once,
`RoomMode`/`TargetTemperature`/… reflect the heater and `Online` is `1`.
If a line errors, run the `AddSetting` block from §1a by hand and check
the Node-RED log for *AddSetting check failed*.

---

## 4. QML files → `/data/truma/qml/`

> **v3.79 (14 Sep 2026):** §4 and §5 are done in one go by
> `qml/install-swipe-page-on-cerbo.sh`; read `docs/swipe-page.md` §0 first.
> The GUI service is `/service/start-gui`, not `gui-v2`. The text below is
> kept for reference.


```sh
ssh root@<venus> "mkdir -p /data/truma/qml"
scp qml/TrumaPage.qml qml/TrumaPageContent-v2.qml root@<venus>:/data/truma/qml/
ssh root@<venus> "grep -n 'TrumaPageContent-v2.qml' /data/truma/qml/TrumaPage.qml"
```

The grep must print the `contentSource:` line. A file on disk is not loaded
by anything until `TrumaPage.qml` references it (it does) **and** the swipe
model references `TrumaPage.qml` (§5).

---

## 5. Swipe entry — the one rootfs edit (read `docs/swipe-page.md` first)

Back up, then look before editing:

```sh
ssh root@<venus> "cp /opt/victronenergy/gui-v2/components/SwipePageModel.qml /data/truma/SwipePageModel.qml.orig && cat /opt/victronenergy/gui-v2/components/SwipePageModel.qml"
ssh root@<venus> "grep -n 'required property\|property' /opt/victronenergy/gui-v2/components/SwipeViewPage.qml"
```

Adapt `qml/SwipePageModel.snippet.qml` to what you see (the `setSource`
property map must match the required properties and the expressions the
Levels/Boat entry uses). Then insert it before the Notifications entry:

```sh
ssh root@<venus> "vi /opt/victronenergy/gui-v2/components/SwipePageModel.qml"
```

(`vi`: `/Notifications` to find the entry, `O` to open a line above, paste,
`Esc`, `:wq`.) Keep a copy and check the diff is only the added block:

```sh
ssh root@<venus> "cp /opt/victronenergy/gui-v2/components/SwipePageModel.qml /data/truma/qml/SwipePageModel.qml.truma && diff /data/truma/SwipePageModel.qml.orig /opt/victronenergy/gui-v2/components/SwipePageModel.qml; grep -c 'file:///data/truma/qml/TrumaPage.qml' /opt/victronenergy/gui-v2/components/SwipePageModel.qml"
```

The last number must be `1`. Restart the GUI and watch it come back:

```sh
ssh root@<venus> "svc -t /service/gui-v2; sleep 6; ps | grep -v grep | grep gui-v2"
ssh root@<venus> "tail -n 40 /var/log/gui-v2/current | tai64nlocal | grep -i -E 'truma|error|warn'"
```

On the screen: Brief → Overview → (Levels) → **Truma** → Notifications →
Settings. If the display is blank or the process is missing → §9 rollback
of this file **now**, diagnose afterwards.

---

## 6. Temperature services (optional; gives the two "—" values on the Touch)

```sh
ssh root@<venus> "mkdir -p /data/truma/dbus-truma-temp"
scp -r venus/dbus-truma-temp/* root@<venus>:/data/truma/dbus-truma-temp/
ssh root@<venus> "chmod +x /data/truma/dbus-truma-temp/dbus-truma-temp.py /data/truma/dbus-truma-temp/service/run /data/truma/dbus-truma-temp/service/log/run"
```

Try it in the foreground first (Ctrl-C to stop):

```sh
ssh root@<venus> "python3 /data/truma/dbus-truma-temp/dbus-truma-temp.py"
```

Expected: two lines `com.victronenergy.temperature.trumaroom registered,
DeviceInstance 30` / `…trumaboiler … 31` (or other instances if 30/31 were
taken). If it prints *waiting for /Settings/Truma/** the flow has not
created the paths yet (§3). Then install it as a service:

```sh
ssh root@<venus> "ln -s /data/truma/dbus-truma-temp/service /service/dbus-truma-temp; cat /data/truma/dbus-truma-temp/rc.local.snippet >> /data/rc.local; chmod +x /data/rc.local; sleep 5; svstat /service/dbus-truma-temp"
ssh root@<venus> "dbus -y com.victronenergy.temperature.trumaroom /Temperature GetValue; dbus -y com.victronenergy.temperature.trumaboiler /Status GetValue"
```

The two services also show up in the GUI's device list and in VRM as
temperature sensors ("Truma D6E room" / "Truma D6E boiler"). This service
was written against `velib_python`'s public API but **not run on a Venus
in this session**; the foreground test above is the gate.

---

## 7. End-to-end check (heater reachable, nothing dangerous yet)

1. Dashboard → any change (e.g. target temperature). Touch must follow
   within a few seconds (after the read-back).
2. Touch → target slider release. Node-RED log (Diagnostics page or the
   *Truma Log* tab) must show `GX Touch changed TargetTemperature to N
   (room.tgt)` **once**, then `wrote AirHeating.TgtTemp = N0`.
3. Watch `GX Touch to command`'s status for 30 s while doing nothing: it
   must stay idle. If it keeps changing, our mirror writes are being taken
   as commands — that is the loop the bridge is built to prevent; stop
   (disable the Bridge tab, Deploy) and capture the *5. MQTT to Venus*
   debug node on the Debug tab.

---

## 8. Interlock test — hard stop, you run it, vehicle ventilated

`TrumaPageContent-v2.qml` enforces, locally and by what it writes:
Room On ⇒ fan 0, boost off; Boost on ⇒ room off; fan > 0 ⇒ vent mode,
room off. The flow does not add a second interlock; it forwards what the
Touch asked for in the order it asked. Confirm against the heater itself:

| Step | On the Touch | Expected on the Truma panel / heater |
|---|---|---|
| 1 | everything off | heater idle |
| 2 | Room Climate → Aan, 21 °C, Comfort | heating starts, panel shows 21 °C, comfort |
| 3 | Boost → Aan | room heating stops, boiler boost starts |
| 4 | Boost → Uit | boost stops; room stays off |
| 5 | Ventilator slider → 6 | fan-only at 6, no burner |
| 6 | Ventilator → 0 | fan stops |
| 7 | Hot Water → Comfort 60 | boiler heats to 60 (activates ~2 s after the mode write) |
| 8 | Hot Water → OFF | boiler off |
| 9 | Energy → Diesel, then Hybrid 900 W, then Diesel | electric level changes in the safe order (electric down first, up last) |

After each step the Touch must settle on the state the panel shows within
one read-back. Repeat 2–8 from the dashboard.

---

## 9. Rollback (each piece independently)

- **Swipe entry** (first, if the GUI did not come back):
  ```sh
  ssh root@<venus> "cp /data/truma/SwipePageModel.qml.orig /opt/victronenergy/gui-v2/components/SwipePageModel.qml && svc -t /service/gui-v2"
  ```
- **QML files**: new files, nothing stock overwritten. Once the swipe entry
  is gone they are inert; `rm -r /data/truma/qml` if you want them gone.
- **Node-RED**: Menu ☰ → Import → your §0 export → Replace → Deploy. Or
  just disable the *Truma Bridge* tab (right-click the tab → Disable) and
  Deploy: that removes every D-Bus interaction and leaves the v1.14
  dashboard running exactly as v1.13 did.
- **Settings paths**: harmless to leave; to remove,
  `dbus -y com.victronenergy.settings /Settings/Truma RemoveSettings '%["RoomMode", ...]'`
  is the localsettings call, but simply leaving them costs nothing.
- **Temperature service**:
  ```sh
  ssh root@<venus> "rm /service/dbus-truma-temp; rm -r /data/truma/dbus-truma-temp; vi /data/rc.local"
  ```
  (remove the snippet block from `/data/rc.local`).

---

## 10. After a Venus OS firmware update

`/data` survives, the rootfs does not: the flow, the QML files under
`/data/truma/qml`, the settings (in `/data/conf`) and the temperature
service all survive. The **swipe entry does not** — re-apply §5 using the
copy in `/data/truma/qml/SwipePageModel.qml.truma` as a reference, after
reading the new stock file (the page list may have changed).
