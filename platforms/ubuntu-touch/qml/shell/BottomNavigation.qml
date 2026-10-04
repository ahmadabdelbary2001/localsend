import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: nav
    implicitHeight: units.gu(7)

    property int currentIndex: 0
    signal tabSelected(int index)

    Rectangle {
        anchors.fill: parent
        color: theme ? theme.colors.surface : "#ffffff"
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: [
                { label: i18n.tr("Receive"), icon: "import" },
                { label: i18n.tr("Send"),    icon: "send" },
                { label: i18n.tr("Settings"),icon: "settings" }
            ]

            delegate: AbstractButton {
                width: nav.width / 3
                height: nav.height

                Column {
                    anchors.centerIn: parent
                    spacing: units.gu(0.5)

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: modelData.icon
                        width: units.gu(3)
                        height: units.gu(3)
                        color: index === nav.currentIndex
                               ? (theme ? theme.colors.primary : "#000")
                               : (theme ? theme.colors.onSurfaceMuted : "#888")
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        fontSize: "small"
                    }
                }

                onClicked: nav.tabSelected(index)
            }
        }
    }
}