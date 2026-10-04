import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Page {
    id: page
    property var theme

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - units.gu(4)
        spacing: units.gu(2)

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: typeof translator !== "undefined"
                  ? translator.tr("settingsTab.title")
                  : "Settings"
            fontSize: "large"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "(SettingsPage skeleton — pending bridge)"
            opacity: 0.6
        }
    }
}