import QtQuick 2.15
import Lomiri.Components 1.3

Page {
    id: page
    property var theme
    title: i18n.tr("Send")

    Column {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: units.gu(2)
        }
        spacing: units.gu(2)

        Label {
            text: i18n.tr("No devices yet")
            fontSize: "large"
        }

        Button {
            text: i18n.tr("Ping Rust")
            onClicked: {
                if (typeof appController !== "undefined") {
                    console.log(appController.ping())
                }
            }
        }
    }
}