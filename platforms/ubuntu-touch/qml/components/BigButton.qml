import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Rectangle {
    id: root
    property var appTheme
    property string iconName: ""
    property string label: ""

    signal clicked()

    Layout.fillWidth: true
    implicitHeight: units.gu(9)
    radius: appTheme && appTheme.metrics ? appTheme.metrics.cardRadius : units.gu(1)

    color: mouseArea.pressed
        ? (appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#D8DADD")
        : (appTheme && appTheme.colors ? appTheme.colors.surface : "#ffffff")

    border.color: mouseArea.pressed
        ? (appTheme && appTheme.colors ? appTheme.colors.primary : "#00695C")
        : (appTheme && appTheme.colors ? appTheme.colors.divider : "#e0e0e0")
    border.width: mouseArea.pressed ? units.dp(2) : units.dp(1)

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: root.clicked()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: units.gu(0.7)

        // Icon circle background
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: units.gu(4.5)
            height: units.gu(4.5)
            radius: width / 2
            color: mouseArea.pressed
                ? (root.appTheme && root.appTheme.colors ? Qt.rgba(0, 0.42, 0.36, 0.20) : "#C8E6C9")
                : (root.appTheme && root.appTheme.colors ? Qt.rgba(0, 0.42, 0.36, 0.10) : "#E8F5E9")

            Behavior on color { ColorAnimation { duration: 100 } }

            Icon {
                anchors.centerIn: parent
                width: units.gu(2.6)
                height: units.gu(2.6)
                name: root.iconName
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: units.gu(12)
            text: root.label
            fontSize: "small"
            font.bold: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
        }
    }
}

