import QtQuick 2.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../components"

// Generic single-choice dialog used for the settings dropdowns and the
// language picker. Flutter renders those as DropdownButtons; Lomiri has no
// light-themed dropdown that fits the custom palette, so a modal list is used
// instead (and it matches the language picker the app already had).
Dialog {
    id: root

    property var appTheme

    // QQuickControls popups are drawn with the application palette; mirror the
    // app palette so dialogs stay readable in dark / OLED modes.
    palette.window: appTheme && appTheme.colors ? appTheme.colors.surface : "#FFFFFF"
    palette.windowText: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
    palette.base: appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1"
    palette.text: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
    palette.button: appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1"
    palette.buttonText: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"

    background: DialogFrame { appTheme: root.appTheme }
    /// Array of objects: { value: string, label: string }
    property var options: []
    property string currentValue: ""

    signal picked(string value)

    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(60))

    contentItem: ListView {
        id: list
        // Fixed delegate height; the dialog sizes itself from this. Cap the
        // list so long lists (all languages) scroll instead of overflowing.
        implicitHeight: Math.min(root.options.length * units.gu(5.5), units.gu(50))
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.options

        delegate: Rectangle {
            width: ListView.view ? ListView.view.width : 0
            height: units.gu(5.5)
            color: "transparent"

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: units.dp(1)
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.divider : "#E0E0E0"
            }

            Label {
                anchors {
                    left: parent.left
                    leftMargin: units.gu(2)
                    right: tick.visible ? tick.left : parent.right
                    rightMargin: units.gu(1)
                    verticalCenter: parent.verticalCenter
                }
                text: modelData.label
                fontSize: "small"
                elide: Text.ElideRight
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
            }

            Icon {
                id: tick
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5)
                height: width
                name: "tick"
                visible: modelData.value === root.currentValue
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    // Close first: picking a language rebuilds the app text
                    // and can tear down this delegate mid-handler.
                    var value = modelData.value
                    root.close()
                    root.picked(value)
                }
            }
        }
    }
}
