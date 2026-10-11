import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

import "../components"

Page {
    id: page
    property var appTheme
    property string pendingFingerprint: ""

    // Loaded on demand so a missing Lomiri.Content on the device
    // does not break the whole page.
    Loader {
        id: pickerLoader
        active: false
        source: "../pickers/ContentHubPicker.qml"

        onLoaded: {
            item.filesPicked.connect(function(paths) {
                if (page.pendingFingerprint && page.pendingFingerprint.length > 0
                        && paths && paths.length > 0) {
                    sendController.send_files(
                        page.pendingFingerprint,
                        JSON.stringify(paths))
                }
                page.pendingFingerprint = ""
                pickerLoader.active = false
            })
            item.pickCancelled.connect(function() {
                page.pendingFingerprint = ""
                pickerLoader.active = false
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
            top: parent.top; left: parent.left; right: parent.right
            bottom: parent.bottom
            margins: units.gu(1.5)
        }
        spacing: units.gu(1)

        // ---------------- Header ----------------
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.2)

                Label {
                    Layout.fillWidth: true
                    text: translator.tr("sendTab.nearbyDevices")
                    fontSize: "medium"
                    color: page.appTheme ? page.appTheme.colors.surfaceText : "#1B1D21"
                }

                Label {
                    Layout.fillWidth: true
                    text: {
                        var n = deviceListModel.rowCount()
                        if (discoveryController.scanning) return qsTr("Scanning…")
                        if (n === 0) return qsTr("No devices found")
                        if (n === 1) return qsTr("1 device found")
                        return n + " " + qsTr("devices found")
                    }
                    fontSize: "x-small"
                    color: page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                }
            }

            Button {
                text: discoveryController.scanning
                      ? "…"
                      : translator.tr("sendTab.scan")
                enabled: !discoveryController.scanning
                onClicked: {
                    discoveryController.scan_now()
                    discoveryController.poll()
                    deviceListModel.refresh()
                }
            }
        }

        // ---------------- Empty state ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: units.gu(6)
            visible: deviceListModel.rowCount() === 0
            spacing: units.gu(1)

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: units.gu(10)
                Layout.preferredHeight: units.gu(10)
                radius: width / 2
                color: page.appTheme ? page.appTheme.colors.surfaceTint : "#ECEFF1"

                Icon {
                    anchors.centerIn: parent
                    name: "network-wired"
                    width: units.gu(5)
                    height: units.gu(5)
                    color: page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#888"
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: qsTr("Make sure the other device is on the same Wi-Fi network.")
                fontSize: "small"
                color: page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }

        // ---------------- Device list ----------------
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: units.gu(1)
            model: deviceListModel
            visible: deviceListModel.rowCount() > 0

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
                    if (sendController.active) return
                    page.pendingFingerprint = model.fingerprint
                    pickerLoader.active = true
                }
            }
        }

        // ---------------- Footer hint ----------------
        Label {
            Layout.fillWidth: true
            Layout.topMargin: units.gu(0.5)
            text: qsTr("Tap a device to choose files and start sending.")
            fontSize: "x-small"
            horizontalAlignment: Text.AlignHCenter
            color: page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
            visible: deviceListModel.rowCount() > 0
        }
    }
}
