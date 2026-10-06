import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

import "../components"

Page {
    id: page
    property var theme

    ColumnLayout {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: units.gu(1.5)
        }
        spacing: units.gu(1)

        // Header row: title + scan button
        RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.fillWidth: true
                text: translator.tr("sendTab.nearbyDevices")
                fontSize: "medium"
            }

            Button {
                text: discoveryController.scanning
                      ? "…"
                      : translator.tr("sendTab.scan")
                enabled: !discoveryController.scanning
                onClicked: {
                    discoveryController.scan_now()
                    // drain events right away
                    discoveryController.poll()
                    refreshModel()
                }
            }
        }

        // Empty state
        Label {
            visible: deviceListModel.rowCount() === 0
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: units.gu(6)
            text: "(no devices found yet — tap Scan)"
            opacity: 0.5
        }

        // Device list
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: units.gu(1)
            model: deviceListModel

            delegate: DeviceCard {
                width: list.width
                theme: page.theme
                fingerprint: model.fingerprint
                alias: model.alias
                deviceModel: model.deviceModel
                deviceType: model.deviceType
                ip: model.ip
                port: model.port
                https: model.https

                onTapped: {
                    console.log("TODO: send files to " + model.alias)
                }
            }
        }
    }

    function refreshModel() {
        var dc = discoveryController
        // Force a re-read of the model. The actual replacement happens
        // in Rust's headless/QML loop; here we just nudge the view.
        list.model = null
        list.model = deviceListModel
    }

    // Refresh whenever discovery produces new devices.
    Connections {
        target: discoveryController
        function onStateChanged() {
            page.refreshModel()
        }
    }
}