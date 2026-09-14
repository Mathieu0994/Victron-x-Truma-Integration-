# BLE: current timeouts, the "phone steals the link" case, and recovery

## 1. Every timer that touches the BLE path today (v1.13 → unchanged in v1.14)

| Where | Value | Meaning |
|---|---|---|
| `inj_boot` | 8 s after start | first read |
| `inj_poll` | every 120 s | scheduled read of the 5 topics in `truma_get` |
| `cmd_done` | immediately | after a write, a forced read of just the topic written |
| `poll_fail` | `30 s × 2^(fails−1)`, capped at 15 min | exponential backoff between reads after a failure |
| `poll_fail` | 5 consecutive failures | circuit breaker "open" + toast *Lost contact with the heater* |
| `stuck_check` | 60 s | a write that neither returns nor errors frees the queue |
| `normalise` WINDOW | 45 s | optimistic (pending) value rolls back if the heater never confirms |
| `failsafe` staleAfter | 300 s | no fresh data → state marked offline |
| `diag_act release` | 300 s | "Release Bluetooth for 5 minutes" (pair the phone) |
| `truma_device` | `pollOnDeploy: false` | the device node does not read on deploy; the flow's own `inj_boot` does |

### The package's own timeout — "BlueZ discover Truma iNetX"

**Observed on the Cerbo (dashboard log, 4 Sep 2026):** `Timed out after 30000ms waiting for BlueZ to discover Truma iNetX` — so the discovery window is **30 s**, well inside `stuck_check`'s 60 s. No flow change needed.

That message is produced by `node-red-contrib-truma-inetx`'s BlueZ transport
when its device discovery does not find `Truma iNetX-XXXXXX` within the
package's scan window; the flow then sees it as a read/write failure
(`catch_poll` / `catch_set`) and the table above takes over. The exact
number of milliseconds lives inside the installed package, which was not
readable in this offline session (no network, package not vendored here).
Read it on the device — it is a one-liner:

```sh
grep -rn -i "discover" ~/.node-red/node_modules/node-red-contrib-truma-inetx/dist/*.js | grep -i -E "timeout|ms|[0-9]{4,}" | head
grep -rn -i "timeout" ~/.node-red/node_modules/node-red-contrib-truma-inetx/dist/*bluez*.js | head
```

and write the value into the table above. Whatever it is, note that the
flow's `stuck_check` (60 s) is the outer bound for a write and the package's
discovery timeout is the inner one; if the package's is larger than 60 s the
queue can be released while the package is still scanning — in that case
lower nothing in the flow, raise `stuck_check` instead (one number in
`stuck_check`).

## 2. The failure the flow could not recover from

Sequence, as observed with the Truma app:

1. The phone connects to the iNet X panel. A BLE peripheral accepts one
   central, so every read from the Cerbo fails → `poll_fail`.
2. Backoff doubles each time: 30 s, 60 s, 2, 4, 8, 15 min. After the 5th
   failure the breaker opens.
3. The phone disconnects (app closed, walked away). The panel advertises
   again within seconds.
4. The flow does nothing until the current backoff expires — up to 15
   minutes of "Lost contact" while the panel is perfectly reachable.
5. On some BlueZ versions the panel is additionally still listed as
   `Connected: yes` from the phone's session for a while, or discovery
   simply does not see it in the first scan after the hand-over; the
   package's per-operation connect then fails once more and the backoff
   grows again.

Step 4 is a flow-level problem; step 5 is a BlueZ-level one. Both are
addressed at flow level, no fork.

## 3. Watchdog (v1.14, `Truma Poller` tab)

```
inj_watchdog (60 s) → ble_watchdog → exec: (select <adapter>; connect <panel-mac>) | bluetoothctl
                                   → ble_watchdog_done → poll_guard (topic 'force') + log
```

`<adapter>` is `TRUMA_BLE_ADAPTER` (the USB adapter's address; empty = the
default controller, as before). The same variable steers the Truma node itself
once `venus/patches/truma-inetx-adapter/` is applied: the stock package has no
adapter setting and always takes the first adapter BlueZ lists (the Cerbo's
built-in chip), so a USB adapter is ignored without that patch. Piped
`bluetoothctl` exits 0 regardless, so `ble_watchdog_done` judges success on the
text *Connection successful* / *already connected* only.

- Fires only when reads are failing: `conn.fails ≥ 2` **or** more than
  5 min since the last good read.
- At most once every 5 min, so it never floods BlueZ or fights the phone.
- Honours the "Release Bluetooth" hold from the Diagnostics page (now
  mirrored into global context, `poll_guard` and the watchdog both read it).
- On `Connection successful` / `already connected` / exit code 0: clears
  `fails`, `backoffUntil` and the breaker, and forces a read **now** —
  cutting a 15-minute wait to under a minute.
- On failure: logs and waits for the next 5-minute slot; the poller's own
  backoff stays in charge.
- Off switch, no redeploy: in the Node-RED editor open any function node on
  the Poller tab and run `flow.set('bleWatchdog', false, 'file')`, or set
  it from a one-off inject. Delete the key to turn it back on.

Why `bluetoothctl connect` is safe with this package: the device node is
configured `bluetooth: "bluez"`, i.e. the package talks to the same BlueZ
daemon over D-Bus. A `Device1.Connect` that is already up returns at once,
so a watchdog-established connection is reused, not fought over. If the
package were ever switched to the `noble`/raw-HCI transport this watchdog
must be disabled — noble and BlueZ do not share connections.

`bluetoothctl` ships with BlueZ on Venus OS; confirm with `which bluetoothctl`
(`DEPLOY.md` §2). If it is missing, the exec node fails harmlessly (logged
as *connect failed*) and nothing else changes.

## 4. Fork decision: not justified (yet)

The requirement was to fork `node-red-contrib-truma-inetx` **only if** the
stock node cannot recover after the phone steals BLE. What is known:

- Its per-operation connect → read/write → disconnect design means every
  poll is a fresh attempt; there is no stale in-process connection that
  needs a restart. That is the right shape for this failure.
- What kept the link "down" was the flow's backoff (fixed above), not a
  state the package cannot leave.
- Two package-level improvements were identified in an earlier read-only
  analysis (persistent connection with auto-reconnect; boot-time discovery
  retry) and remain plausible, but neither is required for recovery.

Fork **if and only if** the on-device logs show `bluetoothctl connect`
succeeding while the very next `truma_get` still fails with the discovery
message for more than one cycle. That is a package discovery bug and the
flow cannot paper over it. If it comes to that: branch `truma/ble-reliability`
on a local fork, unit tests for the transport retry, no upstream PR (hard
stop), and `DEPLOY.md` §2 already describes how to drop `dist/` +
`nodes/` over the installed package without registry access on the Cerbo.
