import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

import "../components"

Page {
    id: page
    property var theme

    ContentHubPicker {
        id: picker
        onFilesPicked: function(paths) {
            if (typeof pendingFingerprint !== "undefined" && pendingFingerprint) {
                sendController.send_files(pendingFingerprint, JSON.stringify(paths))
                pendingFingerprint = ""
            }
        }
    }

    property string pendingFingerprint: ""

    ColumnLayout {
        anchors {
            top: parent.top; left: parent.left; right: parent.right; bottom: parent.bottom
            margins: units.gu(1.5)
        }
        spacing: units.gu(1)

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: translator.tr("sendTab.nearbyDevices")
                fontSize: "medium"
            }
            Button {
                text: discoveryController.scanning ? "…" : translator.tr("sendTab.scan")
                enabled: !discoveryController.scanning
                onClicked: {
                    discoveryController.scan_now()
                    discoveryController.poll()
                    page.refreshModel()
                }
            }
        }

        Label {
            visible: deviceListModel.rowCount() === 0
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: units.gu(6)
            text: "(no devices found yet — tap Scan)"
            opacity: 0.5
        }

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
                    page.pendingFingerprint = model.fingerprint
                    picker.open()
                }
            }
        }
    }

    function refreshModel() {
        list.model = null
        list.model = deviceListModel
    }

    Connections {
        target: discoveryController
        function onStateChanged() {
            page.refreshModel()
        }
    }
}