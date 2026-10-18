import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

// Matches Flutter's BigButton: ElevatedButton, icon above label,
// backgroundColor = secondaryContainerIfDark (surfaceTint in our theme)
Rectangle {
    id: root
    property var appTheme
    property string iconName: ""
    property string label: ""

    signal clicked()

    Layout.fillWidth: true
    implicitHeight: units.gu(8.5)
    radius: appTheme && appTheme.metrics ? appTheme.metrics.cardRadius : units.gu(1.2)

    color: mouseArea.pressed
        ? (appTheme && appTheme.colors ? Qt.darker(appTheme.colors.surfaceTint, 1.08) : "#D0D3D7")
        : (appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#E8F5E9")

    border.color: "transparent"
    border.width: 0

    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: root.clicked()
    }

    // Flutter layout: Column(mainAxisAlignment: spaceBetween) - icon top, text bottom
    Column {
        anchors.centerIn: parent
        spacing: units.gu(0.5)

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: units.gu(3.2)
            height: units.gu(3.2)
            name: root.iconName
            color: root.appTheme && root.appTheme.colors
                   ? root.appTheme.colors.surfaceText
                   : "#1B1D21"
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            fontSize: "small"
            font.bold: false
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: root.appTheme && root.appTheme.colors
                   ? root.appTheme.colors.surfaceText
                   : "#1B1D21"
        }
    }
}
