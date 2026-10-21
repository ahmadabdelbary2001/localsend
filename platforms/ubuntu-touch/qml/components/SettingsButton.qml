import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

// Settings row that opens a dialog, e.g. "Language: System >".
// Flutter renders these as ListTiles with a trailing value; Lomiri's default
// Button is a dark pill, which clashes with the app palette, so the row is
// drawn directly.
Item {
    id: root

    property var appTheme
    property string label: ""
    property string buttonLabel: ""
    signal tapped()

    Layout.fillWidth: true
    implicitHeight: Math.max(units.gu(5), content.implicitHeight + units.gu(0.8))

    Rectangle {
        anchors.fill: parent
        radius: units.gu(0.5)
        color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTint : "#ECEFF1"
        opacity: pressArea.pressed ? 0.9 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    RowLayout {
        id: content
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: units.gu(1)

        Label {
            Layout.fillWidth: true
            text: root.label
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
            fontSize: "small"
            wrapMode: Text.Wrap
        }

        Label {
            text: root.buttonLabel
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
            fontSize: "small"
            elide: Text.ElideMiddle
            Layout.maximumWidth: units.gu(22)
        }

        Icon {
            width: units.gu(2)
            height: width
            // Icons are not mirrored by LayoutMirroring.
            name: translator.rtl ? "go-previous" : "go-next"
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368"
        }
    }

    MouseArea {
        id: pressArea
        anchors.fill: parent
        onClicked: root.tapped()
    }
}
