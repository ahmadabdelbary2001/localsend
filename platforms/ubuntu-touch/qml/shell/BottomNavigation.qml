import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: nav
    implicitHeight: units.gu(7)

    property var theme
    property int currentIndex: 0

    signal tabSelected(int index)

    Rectangle {
        anchors.fill: parent
        color: theme ? theme.colors.surface : "#ffffff"
    }

    // Top hairline
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.dp(1)
        color: theme ? theme.colors.divider : "#e0e0e0"
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: [
                { labelKey: "receiveTab.title", icon: "transfer" },
                { labelKey: "sendTab.title",    icon: "send"     },
                { labelKey: "settingsTab.title",icon: "settings" }
            ]

            delegate: AbstractButton {
                width: nav.width / 3
                height: nav.height

                Column {
                    anchors.centerIn: parent
                    spacing: units.gu(0.3)

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: modelData.icon
                        width: units.gu(3)
                        height: units.gu(3)
                        color: index === nav.currentIndex
                               ? (theme ? theme.colors.primary : "#00695c")
                               : (theme ? theme.colors.onSurfaceMuted : "#888")
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (typeof translator !== "undefined")
                              ? translator.tr(modelData.labelKey)
                              : modelData.labelKey
                        fontSize: "x-small"
                        color: index === nav.currentIndex
                               ? (theme ? theme.colors.primary : "#00695c")
                               : (theme ? theme.colors.onSurfaceMuted : "#888")
                    }
                }

                onClicked: nav.tabSelected(index)
            }
        }
    }
}