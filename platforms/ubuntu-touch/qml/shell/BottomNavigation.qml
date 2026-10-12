import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: nav
    implicitHeight: units.gu(7)

    property var appTheme
    property int currentIndex: 0

    signal tabSelected(int index)

    Rectangle {
        anchors.fill: parent
        color: nav.appTheme && nav.appTheme.colors ? nav.appTheme.colors.surface : "#ffffff"
    }

    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.dp(1)
        color: nav.appTheme && nav.appTheme.colors ? nav.appTheme.colors.divider : "#e0e0e0"
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: [
                { labelKey: "receiveTab.title",  icon: "transfer" },
                { labelKey: "sendTab.title",     icon: "send"     },
                { labelKey: "settingsTab.title", icon: "settings" }
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
                               ? (nav.appTheme && nav.appTheme.colors ? nav.appTheme.colors.primary : "#00695c")
                               : (nav.appTheme && nav.appTheme.colors ? nav.appTheme.colors.surfaceTextMuted : "#888")
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: translator.tr(modelData.labelKey)
                        fontSize: "x-small"
                        color: index === nav.currentIndex
                               ? (nav.appTheme && nav.appTheme.colors ? nav.appTheme.colors.primary : "#00695c")
                               : (nav.appTheme && nav.appTheme.colors ? nav.appTheme.colors.surfaceTextMuted : "#888")
                    }
                }

                onClicked: nav.tabSelected(index)
            }
        }
    }
}
