import QtQuick 2.15
import Lomiri.Components 1.3

Page {
    id: page
    property var theme
    title: i18n.tr("Receive")

    Column {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: units.gu(2)
        }
        spacing: units.gu(2)

        Label {
            text: i18n.tr("Waiting for incoming transfers")
            fontSize: "large"
        }

        Label {
            text: (typeof appController !== "undefined")
                  ? appController.status
                  : i18n.tr("(bridge not loaded)")
            wrapMode: Text.Wrap
        }

        Label {
            text: (typeof appController !== "undefined")
                  ? appController.coreVersion
                  : ""
            fontSize: "small"
            opacity: 0.7
        }
    }
}