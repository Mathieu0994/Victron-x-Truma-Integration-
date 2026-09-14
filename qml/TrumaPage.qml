// TrumaPage.qml — top-level swipe page wrapper for the GX Touch (gui-v2).
//
// Deployed to /data/truma/qml/ (survives Venus OS firmware updates, unlike
// anything under /opt/victronenergy/gui-v2/). Loaded into the main swipe
// view by qml/SwipePageModel.v3.79.qml (installed by
// qml/install-swipe-page-on-cerbo.sh) — see docs/swipe-page.md.
//
// What this file does NOT do: it does not touch a single binding of
// TrumaPageContent-v2.qml. The content page is loaded unchanged, by absolute
// file:// path, because a relative Loader source has silently failed to
// resolve on this project before.
//
// `view`, `navButtonText`, `navButtonIcon` and `url` are required properties
// of SwipeViewPage (names as of Venus OS v3.79) and are supplied by the swipe
// model when it creates this page (qml/SwipePageModel.v3.79.qml), not here.

import QtQuick
import Victron.VenusOS

SwipeViewPage {
    id: root

    readonly property url contentSource: "file:///data/truma/qml/TrumaPageContent-v2.qml"
    readonly property bool contentLoaded: contentLoader.status === Loader.Ready

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, contentLoader.height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // The content is laid out for the 7" screen; only become scrollable
        // when it genuinely overflows, so the sliders keep every drag.
        interactive: contentHeight > height + 1

        Loader {
            id: contentLoader
            width: flick.width
            height: Math.max(flick.height, item && item.implicitHeight ? item.implicitHeight : 0)
            source: root.contentSource
            asynchronous: false
            onStatusChanged: {
                if (status === Loader.Error)
                    console.warn("TrumaPage: could not load", source)
            }
        }
    }

    // Visible fallback so a broken content file is diagnosable on the screen
    // itself rather than only in the gui-v2 log.
    Label {
        anchors.centerIn: parent
        visible: contentLoader.status === Loader.Error
        text: "Truma page content failed to load\n" + root.contentSource
        horizontalAlignment: Text.AlignHCenter
        color: Theme.color_font_secondary
        font.pixelSize: Theme.font_size_body2
    }
}
