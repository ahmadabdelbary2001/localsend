import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Page {
    id: page
    property var appTheme
    property string pendingFingerprint: ""

    // ContentHubPicker is loaded on demand. If Lomiri.Content is not
    // available on this device, only file picking fails — the rest of
    // the app keeps working.
    Loader {
        id: pickerLoader
        active: false
        source: "../components/ContentHubPicker.qml"

        onLoaded: {
            item.filesPicked.connect(function(paths) {
                if (page.pendingFingerprint && page.pendingFingerprint.length > 0) {
                    sendController.send_files(page.pendingFingerprint, JSON.stringify(paths))
                    page.pendingFingerprint = ""
                }
            })
            item.pickCancelled.connect(function() {
                page.pendingFingerprint = ""
            })
            item.open()
        }

        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("ContentHubPicker unavailable: file picking disabled")
                page.pendingFingerprint = ""
                pickerLoader.active = false
            }
        }
    }

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
                appTheme: page.appTheme
                fingerprint: model.fingerprint
                alias: model.alias
                deviceModel: model.deviceModel
                deviceType: model.deviceType
                ip: model.ip
                port: model.port
                https: model.https

                onTapped: {
                    page.pendingFingerprint = model.fingerprint
                    pickerLoader.active = false
                    pickerLoader.active = true
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
