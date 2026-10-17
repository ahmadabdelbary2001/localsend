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
    implicitHeight: units.gu(8)
    radius: appTheme && appTheme.metrics ? appTheme.metrics.cardRadius : units.gu(0.8)

    color: mouseArea.pressed
        ? (appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1")
        : (appTheme && appTheme.colors ? appTheme.colors.surface : "#ffffff")

    border.color: appTheme && appTheme.colors ? appTheme.colors.divider : "#e0e0e0"
    border.width: units.dp(1)

    Behavior on color { ColorAnimation { duration: 80 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: root.clicked()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: units.gu(0.6)

        Icon {
            Layout.alignment: Qt.AlignHCenter
            width: units.gu(3)
            height: units.gu(3)
            name: root.iconName
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            fontSize: "small"
            font.bold: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
        }
    }
}
