# truma-inetx-adapter — pick the Bluetooth adapter for the Truma node

`node-red-contrib-truma-inetx` 1.0.2 (BlueZ backend) has no adapter setting: it takes
the first adapter BlueZ reports, on a Cerbo GX the built-in chip (`hci0`). With a USB
adapter such as the TP-Link UB500 plugged in, the package keeps using the built-in one.

`apply-on-cerbo.sh` changes one function (`findBluezAdapterPath`, present in
`dist/ble.js` and `dist/index.js`) so that the environment variable
`TRUMA_BLE_ADAPTER` selects the adapter by **address** (stable across reboots; `hciN`
numbering is not, both adapters are USB). Unset, nothing changes.

```sh
scp -r venus root@<venus>:/data/truma-src/
ssh root@<venus> "sh /data/truma-src/venus/patches/truma-inetx-adapter/apply-on-cerbo.sh"
```

Set the variables in Node-RED's user settings (`/data/home/nodered/.node-red/settings-user.js`
on Venus OS Large, which survives updates), at the top of the file:

```js
process.env.TRUMA_BLE_ADAPTER = '3C:78:95:78:17:71'   // the USB adapter's address (bluetoothctl list)
process.env.TRUMA_MAC = 'XX:XX:XX:XX:XX:XX'           // the iNet X panel, for the BLE watchdog
```

Restart Node-RED, then confirm in its log: `Using BlueZ adapter /org/bluez/hci2`.
The flow's BLE watchdog (`exec_ble_connect`) selects the same adapter before
`bluetoothctl connect`. Revert with `apply-on-cerbo.sh --revert`; re-apply after any
package update (the script refuses if the function text changed).
