import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Rectangle {
    id: root
    property var appTheme
    property string title: ""
    default property alias items: content.children

    Layout.fillWidth: true
    implicitHeight: mainColumn.implicitHeight + units.gu(3)
    radius: appTheme && appTheme.metrics ? appTheme.metrics.cardRadius : units.gu(0.6)
    color: appTheme && appTheme.colors ? appTheme.colors.surface : "#ffffff"
    border.color: appTheme && appTheme.colors ? appTheme.colors.divider : "#e0e0e0"
    border.width: units.dp(1)

    Column {
        id: mainColumn
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: units.gu(1.5)
        }
        spacing: units.gu(1)

        Label {
            text: root.title
            fontSize: "medium"
            color: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
        }

        Column {
            id: content
            width: parent.width
            spacing: units.gu(1)
        }
    }
}
