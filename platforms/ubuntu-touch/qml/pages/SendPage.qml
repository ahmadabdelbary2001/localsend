import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

import "../components"
import "../dialogs" as LocalSendDialogs

Page {
    id: page
    property var appTheme
    property string pendingFingerprint: ""

    Loader {
        id: pickerLoader
        active: false
        source: "../pickers/ContentHubPicker.qml"

        onLoaded: {
            item.filesPicked.connect(function(paths) {
                if (page.pendingFingerprint.length > 0 && paths && paths.length > 0) {
                    sendController.send_files(page.pendingFingerprint, JSON.stringify(paths))
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
                console.warn("ContentHubPicker unavailable")
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
            spacing: units.gu(1)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.2)

                Label {
                    Layout.fillWidth: true
                    text: translator.tr("sendTab.nearbyDevices")
                    fontSize: "medium"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
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
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                }
            }

            Button {
                text: discoveryController.scanning ? "…" : translator.tr("sendTab.scan")
                enabled: !discoveryController.scanning
                onClicked: {
                    discoveryController.scan_now()
                    discoveryController.poll()
                    deviceListModel.refresh()
                }
            }
        }

        // ---------- Favorites ----------
        Label {
            Layout.fillWidth: true
            Layout.topMargin: units.gu(0.5)
            visible: favoritesController.count > 0
            text: qsTr("Favorites")
            fontSize: "small"
            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
        }

        ListView {
            id: favList
            Layout.fillWidth: true
            Layout.preferredHeight: contentHeight
            Layout.maximumHeight: units.gu(20)
            visible: favoritesController.count > 0
            interactive: contentHeight > height
            clip: true
            spacing: units.gu(1)
            model: favoritesController

            delegate: DeviceCard {
                width: favList.width
                appTheme: page.appTheme
                fingerprint: model.fingerprint
                alias: model.alias
                deviceModel: ""
                deviceType: ""
                ip: model.ip
                port: model.port
                https: true
                isFavorite: true
                offline: false

                onTapped: {
                    if (sendController.active) return
                    page.pendingFingerprint = model.fingerprint
                    pickerLoader.active = true
                }
                onDetailsRequested: {
                    detailsDialog.fingerprint = model.fingerprint
                    detailsDialog.alias = model.alias
                    detailsDialog.deviceModel = ""
                    detailsDialog.deviceType = ""
                    detailsDialog.ip = model.ip
                    detailsDialog.port = model.port
                    detailsDialog.https = true
                    detailsDialog.open()
                }
                onToggleFavorite: favoritesController.remove(model.fingerprint)
            }
        }

        // ---------- Nearby ----------
        Label {
            Layout.fillWidth: true
            Layout.topMargin: units.gu(0.5)
            visible: deviceListModel.rowCount() > 0
            text: qsTr("Nearby")
            fontSize: "small"
            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
        }

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
                isFavorite: favoritesController.is_favorite(model.fingerprint)
                offline: false

                onTapped: {
                    if (sendController.active) return
                    page.pendingFingerprint = model.fingerprint
                    pickerLoader.active = true
                }
                onDetailsRequested: {
                    detailsDialog.fingerprint = model.fingerprint
                    detailsDialog.alias = model.alias
                    detailsDialog.deviceModel = model.deviceModel
                    detailsDialog.deviceType = model.deviceType
                    detailsDialog.ip = model.ip
                    detailsDialog.port = model.port
                    detailsDialog.https = model.https
                    detailsDialog.open()
                }
                onToggleFavorite: {
                    if (favoritesController.is_favorite(model.fingerprint)) {
                        favoritesController.remove(model.fingerprint)
                    } else {
                        favoritesController.add_or_update(
                            model.fingerprint, model.ip, model.port, model.alias)
                    }
                }
            }
        }

        // ---------- Empty state ----------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: units.gu(3)
            visible: deviceListModel.rowCount() === 0 && favoritesController.count === 0
            spacing: units.gu(1)

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: qsTr("Make sure the other device is on the same Wi-Fi network.")
                fontSize: "small"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
            }
        }
    }

    LocalSendDialogs.DeviceDetailsDialog {
        id: detailsDialog
        appTheme: page.appTheme
    }
}
