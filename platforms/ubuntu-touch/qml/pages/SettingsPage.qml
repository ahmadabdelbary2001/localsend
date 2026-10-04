import QtQuick 2.15
import Lomiri.Components 1.3

Page {
    id: page
    property var theme
    title: i18n.tr("Settings")

    Column {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: units.gu(2)
        }
        spacing: units.gu(2)

        Label {
            text: i18n.tr("Settings will appear here.")
            wrapMode: Text.Wrap
        }
    }
}