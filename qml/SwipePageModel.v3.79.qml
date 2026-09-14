import QtQuick
import QtQml.Models
import Victron.VenusOS
import Victron.Boat as Boat

// SwipePageModel.qml as shipped with Venus OS v3.79 (gui-v2, Cerbo GX), plus one
// block that adds the Truma page between Levels and Notifications. Everything
// else is byte-for-byte the stock file. Lives on the rootfs at
//   /opt/victronenergy/gui-v2/Victron/VenusOS/components/SwipePageModel.qml
// and is only used when the "prefer" line is removed from the qmldir next to it
// (see qml/install-swipe-page-on-cerbo.sh). Re-apply after a firmware update.

ObjectModel {
	id: root

	required property SwipeView view
	readonly property bool showLevelsPage: tankCount > 0 || environmentInputCount > 0
	readonly property bool tankCount: Global.tanks ? Global.tanks.totalTankCount : 0
	readonly property bool environmentInputCount: Global.environmentInputs ? Global.environmentInputs.model.count : 0

	readonly property Component boatPage: Component {
		Boat.BoatPage {
			view: root.view
		}
	}
	readonly property VeQuickItem showBoatPage: VeQuickItem {
		uid: !!Global.systemSettings ? Global.systemSettings.serviceUid + "/Settings/Gui/ElectricPropulsionUI/Enabled" : ""
		onValueChanged: {
			if (!completed) {
				return
			}

			if (value) {
				root.view.insertItem(0, boatPage.createObject(parent))
			} else {
				root.view.removeItem(view.itemAt(0))
			}
		}
	}

	readonly property Component levelsComponent: Component {
		LevelsPage {
			view: root.view
		}
	}
	property LevelsPage levelsPage

	property bool completed: false

	BriefPage {
		view: root.view

		Image {
			width: status === Image.Null ? 0 : Theme.geometry_screen_width
			fillMode: Image.PreserveAspectFit
			source: BackendConnection.demoImageFileName
			onStatusChanged: {
				if (status === Image.Ready) {
					console.info("Loaded demo image:", source)
				}
			}
		}
	}

	OverviewPage {
		view: root.view
	}

	NotificationsPage {
		id: notificationsPage
		view: root.view
	}

	SettingsPage {
		view: root.view
	}

	// ---- Truma D6E: custom page, loaded from /data so it survives firmware updates ----
	// TrumaPage.qml is not part of the Victron.VenusOS module, so it is created by URL.
	// A missing or broken TrumaPage.qml costs only the Truma page, never the GUI.
	function insertTrumaPage() {
		var trumaComponent = Qt.createComponent("file:///data/truma/qml/TrumaPage.qml")
		if (trumaComponent.status !== Component.Ready) {
			console.warn("SwipePageModel: Truma page failed to load:", trumaComponent.errorString())
			return
		}
		var trumaPage = trumaComponent.createObject(parent, {
			"view": root.view,
			"navButtonText": "Truma",
			"navButtonIcon": "qrc:/images/icon_temp_32.svg",
			"url": "file:///data/truma/qml/TrumaPage.qml"
		})
		if (!trumaPage) {
			console.warn("SwipePageModel: Truma page could not be created")
			return
		}
		for (let i = 0; i < count; ++i) {
			if (get(i) === notificationsPage) {
				insert(i, trumaPage)
				console.info("SwipePageModel: Truma page inserted at", i)
				return
			}
		}
		append(trumaPage)
	}

	Component.onCompleted: {
		if (showLevelsPage) {
			levelsPage = levelsComponent.createObject(parent)
			insert(2, levelsPage) // ideally the index would not be hardcoded, but the view is not initialized yet
		}

		insertTrumaPage()

		if (showBoatPage.value) {
			insert(0, boatPage.createObject(parent))
		}

		completed = true
	}

	onShowLevelsPageChanged: {
		if (!completed) {
			return
		}

		if (showLevelsPage) {
			for (let i = 0; i < root.view.count; ++i) {
				if (root.view.itemAt(i) === notificationsPage) {
					root.levelsPage = levelsComponent.createObject(parent)
					root.view.insertItem(i, root.levelsPage)
					break
				}
			}
		} else {
			root.view.removeItem(root.levelsPage)
		}
	}
}
