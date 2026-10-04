import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Page {
    id: page
    property var theme

    // UI-only placeholder.
    // Real implementation comes after send_tab.dart is fully mapped
    // (NearbyDevicesModel, SelectedFilesModel, SendController).

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - units.gu(4)
        spacing: units.gu(2)

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: translator.tr("sendTab.selection.title")
            fontSize: "large"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "(SendPage skeleton — pending bridge)"
            opacity: 0.6
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Ping Rust"
            onClicked: console.log(appController.ping())
        }
    }
}