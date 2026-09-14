import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import Victron.VenusOS

Item {
    id: root
    anchors.fill: parent
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // ---- D-Bus services -------------------------------------------------
    // gui-v2 prefixes every uid with its backend ("dbus/" on the GX Touch), so
    // the service uids are asked from BackendConnection instead of being
    // written out. The /Settings/Truma/* path names below are unchanged.
    // (Confirmed on a Cerbo GX, Venus OS v3.79: without the prefix nothing resolves.)
    readonly property string settingsService: BackendConnection.serviceUidForType("settings")
    readonly property string roomTempService: BackendConnection.serviceUidFromName("com.victronenergy.temperature.trumaroom", 0)
    readonly property string boilerTempService: BackendConnection.serviceUidFromName("com.victronenergy.temperature.trumaboiler", 0)

    QtObject {
        id: dbus
        // The two temperatures come from the bridge's own mirror paths, which
        // exist on every Cerbo running the flow. The optional dbus-truma-temp
        // service (venus/dbus-truma-temp) publishes the same values as real
        // temperature sensors for VRM; the page no longer depends on it.
        property VeQuickItem roomTemp: VeQuickItem { uid: root.settingsService + "/Settings/Truma/RoomTemperature" }
        property VeQuickItem boilerTemp: VeQuickItem { uid: root.settingsService + "/Settings/Truma/BoilerTemperature" }
        property VeQuickItem targetTemp: VeQuickItem { uid: root.settingsService + "/Settings/Truma/TargetTemperature" }
        property VeQuickItem fanLevel: VeQuickItem { uid: root.settingsService + "/Settings/Truma/FanLevel" }
        property VeQuickItem airMode: VeQuickItem { uid: root.settingsService + "/Settings/Truma/AirMode" }
        property VeQuickItem roomMode: VeQuickItem { uid: root.settingsService + "/Settings/Truma/RoomMode" }
        property VeQuickItem waterMode: VeQuickItem { uid: root.settingsService + "/Settings/Truma/WaterMode" }
        property VeQuickItem waterActive: VeQuickItem { uid: root.settingsService + "/Settings/Truma/WaterActive" }
        property VeQuickItem boost: VeQuickItem { uid: root.settingsService + "/Settings/Truma/Boost" }
        property VeQuickItem energyMode: VeQuickItem { uid: root.settingsService + "/Settings/Truma/EnergyMode" }
    }

    readonly property bool bridgeUp: dbus.roomMode.valid

    // ---- Lokale UI-state (bron voor de weergave) ------------------------
    property bool roomOn: false
    property int tgtTemp: 20
    property int airMode: 1
    property bool waterOn: false
    property int waterMode: -1
    property bool boostOn: false
    property bool ventOn: false
    property int fanLevel: 0
    property int energyMode: 0
    property real roomTempC: -1
    property real waterTempC: -1

    readonly property string roomTempText: root.roomTempC < 0 ? "—" : root.roomTempC.toFixed(1) + " °C"
    readonly property string waterTempText: root.waterTempC < 0 ? "—" : root.waterTempC.toFixed(1) + " °C"

    // ---- Sync: D-Bus -> lokale state (alleen als de bridge er is) -------
    Connections {
        target: dbus.roomMode
        function onValueChanged() {
            if (!dbus.roomMode.valid) return
            root.roomOn = dbus.roomMode.value === 3
            root.ventOn = dbus.roomMode.value === 5
        }
    }
    Connections {
        target: dbus.targetTemp
        function onValueChanged() {
            if (dbus.targetTemp.valid && !tempSlider.pressed) root.tgtTemp = dbus.targetTemp.value
        }
    }
    Connections {
        target: dbus.fanLevel
        function onValueChanged() {
            if (dbus.fanLevel.valid && !fanSlider.pressed) root.fanLevel = dbus.fanLevel.value
        }
    }
    Connections {
        target: dbus.airMode
        function onValueChanged() { if (dbus.airMode.valid) root.airMode = dbus.airMode.value }
    }
    Connections {
        target: dbus.waterMode
        function onValueChanged() { if (dbus.waterMode.valid) root.waterMode = dbus.waterMode.value }
    }
    Connections {
        target: dbus.waterActive
        function onValueChanged() { if (dbus.waterActive.valid) root.waterOn = dbus.waterActive.value === 1 }
    }
    Connections {
        target: dbus.boost
        function onValueChanged() { if (dbus.boost.valid) root.boostOn = dbus.boost.value === 1 }
    }
    Connections {
        target: dbus.energyMode
        function onValueChanged() { if (dbus.energyMode.valid) root.energyMode = dbus.energyMode.value }
    }
    Connections {
        target: dbus.roomTemp
        function onValueChanged() { root.roomTempC = dbus.roomTemp.valid ? dbus.roomTemp.value : -1 }
    }
    Connections {
        target: dbus.boilerTemp
        function onValueChanged() { root.waterTempC = dbus.boilerTemp.valid ? dbus.boilerTemp.value : -1 }
    }

    // ---- Schrijven: lokaal altijd, D-Bus als die er is ------------------
    function send(item, value) {
        if (item.valid) item.setValue(value)
        else console.log("Truma (geen bridge):", item.uid, value)
    }

    // ---- Interlocks (zoals de Truma zelf) ------------------------------
    function setRoomOn(on) {
        root.roomOn = on
        if (on) {
            root.ventOn = false
            root.fanLevel = 0
            root.boostOn = false
            send(dbus.fanLevel, 0)
            send(dbus.boost, 0)
            send(dbus.roomMode, 3)
        } else {
            send(dbus.roomMode, 0)
        }
    }

    function setBoost(on) {
        root.boostOn = on
        if (on) {
            root.roomOn = false
            send(dbus.roomMode, 0)
        }
        send(dbus.boost, on ? 1 : 0)
    }

    function setFan(level) {
        root.fanLevel = level
        if (level > 0) {
            root.ventOn = true
            root.roomOn = false
            send(dbus.roomMode, 5)
        } else if (root.ventOn) {
            root.ventOn = false
            send(dbus.roomMode, 0)
        }
        send(dbus.fanLevel, level)
    }

    // ---- Kleuren --------------------------------------------------------
    readonly property color colorAccent: "#00b3ff"
    readonly property color colorAlert: "#ff6b6b"

    // ---- Componenten ----------------------------------------------------
    component TBtn: Rectangle {
        property string label: ""
        property bool active: false
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: 52
        Layout.minimumHeight: 52
        Layout.maximumHeight: 52
        radius: 8
        color: active ? root.colorAccent : Theme.color_background_secondary
        border.color: Theme.color_background_disabled
        border.width: 1
        z: 1

        MouseArea {
            anchors.fill: parent
            z: 2
            preventStealing: true
            onClicked: parent.clicked()
        }
        Label {
            anchors.centerIn: parent
            width: parent.width - 6
            text: parent.label
            color: Theme.color_font_primary
            font.pixelSize: Theme.font_size_body1
            font.bold: parent.active
            horizontalAlignment: Text.AlignHCenter
        }
    }

    component THead: Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignLeft
        color: Theme.color_font_primary
        font.pixelSize: Theme.font_size_body1
        font.bold: true
    }

    component TStat: Rectangle {
        property string caption: ""
        property string valueText: ""
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: 8
        color: Theme.color_background_secondary
        border.color: Theme.color_background_disabled
        border.width: 1
        Row {
            anchors.centerIn: parent
            spacing: 6
            Label {
                text: parent.parent.caption
                color: Theme.color_font_secondary
                font.pixelSize: Theme.font_size_body2
            }
            Label {
                text: parent.parent.valueText
                color: Theme.color_font_primary
                font.pixelSize: Theme.font_size_body2
                font.bold: true
            }
        }
    }

    component TSwitch: C.Switch {
        id: sw
        implicitWidth: 68
        implicitHeight: 38
        indicator: Rectangle {
            implicitWidth: 68
            implicitHeight: 38
            x: sw.leftPadding
            y: sw.topPadding + (sw.availableHeight - height) / 2
            radius: 19
            color: sw.checked ? root.colorAccent : Theme.color_background_disabled
            border.color: Theme.color_background_disabled
            border.width: 1
            Rectangle {
                x: sw.checked ? parent.width - width - 4 : 4
                y: 4
                width: 30
                height: 30
                radius: 15
                color: Theme.color_font_primary
            }
        }
    }

    // ---- Layout ---------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 8

        // Sliders bovenaan
        RowLayout {
            Layout.fillWidth: true
            spacing: 24

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 2

                THead { text: "Room climate  " + root.tgtTemp + " °C" }

                C.Slider {
                    id: tempSlider
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    LayoutMirroring.enabled: false
                    from: 5
                    to: 30
                    stepSize: 1
                    value: root.tgtTemp
                    onMoved: root.tgtTemp = Math.round(value)
                    onPressedChanged: if (!pressed) root.send(dbus.targetTemp, root.tgtTemp)

                    background: Rectangle {
                        x: tempSlider.leftPadding
                        y: tempSlider.topPadding + tempSlider.availableHeight / 2 - height / 2
                        width: tempSlider.availableWidth
                        height: 8
                        radius: 4
                        color: Theme.color_background_disabled
                        Rectangle {
                            width: tempSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 4
                            color: root.roomOn ? root.colorAccent : Theme.color_font_secondary
                        }
                    }
                    handle: Rectangle {
                        x: tempSlider.leftPadding + tempSlider.visualPosition * (tempSlider.availableWidth - width)
                        y: tempSlider.topPadding + tempSlider.availableHeight / 2 - height / 2
                        width: 36
                        height: 36
                        radius: 18
                        color: root.roomOn ? root.colorAccent : Theme.color_font_primary
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "5"; color: Theme.color_font_secondary; font.pixelSize: Theme.font_size_caption }
                    Item { Layout.fillWidth: true }
                    Label { text: "30"; color: Theme.color_font_secondary; font.pixelSize: Theme.font_size_caption }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 2

                THead { text: "Ventilator  " + root.fanLevel }

                C.Slider {
                    id: fanSlider
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    LayoutMirroring.enabled: false
                    from: 0
                    to: 10
                    stepSize: 1
                    value: root.fanLevel
                    onMoved: root.fanLevel = Math.round(value)
                    onPressedChanged: if (!pressed) root.setFan(Math.round(value))

                    background: Rectangle {
                        x: fanSlider.leftPadding
                        y: fanSlider.topPadding + fanSlider.availableHeight / 2 - height / 2
                        width: fanSlider.availableWidth
                        height: 8
                        radius: 4
                        color: Theme.color_background_disabled
                        Rectangle {
                            width: fanSlider.visualPosition * parent.width
                            height: parent.height
                            radius: 4
                            color: root.fanLevel > 0 ? root.colorAccent : Theme.color_font_secondary
                        }
                    }
                    handle: Rectangle {
                        x: fanSlider.leftPadding + fanSlider.visualPosition * (fanSlider.availableWidth - width)
                        y: fanSlider.topPadding + fanSlider.availableHeight / 2 - height / 2
                        width: 36
                        height: 36
                        radius: 18
                        color: root.fanLevel > 0 ? root.colorAccent : Theme.color_font_primary
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "0"; color: Theme.color_font_secondary; font.pixelSize: Theme.font_size_caption }
                    Item { Layout.fillWidth: true }
                    Label { text: "10"; color: Theme.color_font_secondary; font.pixelSize: Theme.font_size_caption }
                }
            }
        }

        // Drie kolommen
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 24

            // Room Climate
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: 6

                THead { text: "Room Climate" }

                TBtn {
                    label: "Fast"
                    active: root.airMode === 0
                    onClicked: { root.airMode = 0; root.send(dbus.airMode, 0) }
                }
                TBtn {
                    label: "Comfort"
                    active: root.airMode === 1
                    onClicked: { root.airMode = 1; root.send(dbus.airMode, 1) }
                }

                Item { Layout.preferredHeight: 4 }
                RowLayout {
                    Layout.alignment: Qt.AlignLeft
                    spacing: 8
                    Label {
                        text: root.roomOn ? "Aan" : "Uit"
                        color: Theme.color_font_primary
                        font.pixelSize: Theme.font_size_body2
                    }
                    TSwitch {
                        checked: root.roomOn
                        onToggled: root.setRoomOn(checked)
                    }
                }

                Item { Layout.preferredHeight: 6 }
                THead { text: "Current" }
                TStat { caption: "Room temp"; valueText: root.roomTempText }
                TStat { caption: "Boiler temp"; valueText: root.waterTempText }
            }

            // Hot Water
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: 6

                THead { text: "Hot Water" }

                TBtn {
                    label: "Eco 40"
                    active: root.waterOn && root.waterMode === 0
                    onClicked: {
                        root.waterMode = 0; root.waterOn = true
                        root.send(dbus.waterMode, 0)
                        root.send(dbus.waterActive, 1)
                    }
                }
                TBtn {
                    label: "Comfort 60"
                    active: root.waterOn && root.waterMode === 1
                    onClicked: {
                        root.waterMode = 1; root.waterOn = true
                        root.send(dbus.waterMode, 1)
                        root.send(dbus.waterActive, 1)
                    }
                }
                TBtn {
                    label: "Hot 70"
                    active: root.waterOn && root.waterMode === 2
                    onClicked: {
                        root.waterMode = 2; root.waterOn = true
                        root.send(dbus.waterMode, 2)
                        root.send(dbus.waterActive, 1)
                    }
                }
                TBtn {
                    label: "OFF"
                    active: !root.waterOn
                    onClicked: {
                        root.waterOn = false; root.waterMode = -1
                        root.send(dbus.waterActive, 0)
                    }
                }

                Item { Layout.preferredHeight: 2 }
                THead { text: "Hot Water Boost" }
                RowLayout {
                    Layout.alignment: Qt.AlignLeft
                    spacing: 8
                    Label {
                        text: root.boostOn ? "Aan" : "Uit"
                        color: Theme.color_font_primary
                        font.pixelSize: Theme.font_size_body2
                    }
                    TSwitch {
                        checked: root.boostOn
                        onToggled: root.setBoost(checked)
                    }
                }
            }

            // Energy Source
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: 6

                THead { text: "Energy Source" }

                TBtn {
                    label: "Hybrid 900W"
                    active: root.energyMode === 1
                    onClicked: { root.energyMode = 1; root.send(dbus.energyMode, 1) }
                }
                TBtn {
                    label: "Hybrid 1800W"
                    active: root.energyMode === 2
                    onClicked: { root.energyMode = 2; root.send(dbus.energyMode, 2) }
                }
                TBtn {
                    label: "Electric 900W"
                    active: root.energyMode === 3
                    onClicked: { root.energyMode = 3; root.send(dbus.energyMode, 3) }
                }
                TBtn {
                    label: "Electric 1800W"
                    active: root.energyMode === 4
                    onClicked: { root.energyMode = 4; root.send(dbus.energyMode, 4) }
                }
                TBtn {
                    label: "Diesel"
                    active: root.energyMode === 5
                    onClicked: { root.energyMode = 5; root.send(dbus.energyMode, 5) }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Label {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: root.bridgeUp ? "Truma-bridge verbonden" : "Geen verbinding met de Truma-bridge"
                color: root.bridgeUp ? Theme.color_font_secondary : root.colorAlert
                font.pixelSize: 11
            }
        }
    }
}
