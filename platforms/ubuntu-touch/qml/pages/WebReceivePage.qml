// SPDX-License-Identifier: Apache-2.0
//
// WebReceivePage.qml - "Receive via link" page for LocalSend on Ubuntu Touch.
// Starts the HTTP server in web-upload mode so any browser on the same network
// can upload files to this device without having LocalSend installed.

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

Page {
    id: page
    property var appTheme

    header: null

    // internal state
    property string _status: "initializing"   // "initializing" | "running" | "error" | "stopping"
    property string _errorMsg: ""
    property bool   _encrypted: false
    property string _pin: ""
    property bool   _pinEnabled: false

    Component.onCompleted: _startWebReceive()

    Component.onDestruction: {
        _status = "stopping"
        serverController.stop_web_receive()
        serverController.start(
            settingsController.alias,
            settingsController.port,
            settingsController.https,
            settingsController.receive_pin
        )
    }

    function _startWebReceive() {
        page._status = "initializing"
        serverController.start_web_receive(
            settingsController.alias,
            settingsController.port,
            false,
            page._pin
        )
    }

    function _ips() {
        var parts = []
        for (var i = 0; i < localIpsModel.rowCount(); i++) {
            var idx = localIpsModel.index(i, 0)
            parts.push(localIpsModel.data(idx, 0))
        }
        return parts
    }

    function _buildUrl(ip) {
        var scheme = page._encrypted ? "https" : "http"
        return scheme + "://" + ip + ":" + serverController.web_receive_port
    }

    function _showToast(msg) {
        toastLabel.text = msg
        toastRect.opacity = 1
        toastTimer.restart()
    }

    Connections {
        target: serverController
        function onWeb_receive_changed() {
            if (serverController.web_receive_active) {
                page._status = "running"
            } else if (page._status !== "stopping") {
                page._status = "error"
                page._errorMsg = translator.tr("webSharePage.error")
            }
        }
    }

    // Background
    Rectangle {
        anchors.fill: parent
        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.background : "#F5F5F5"
    }

    // Header bar
    Item {
        id: headerBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(6)
        z: 10

        Rectangle {
            anchors.fill: parent
            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surface : "#FFFFFF"
        }

        AbstractButton {
            id: backBtn
            width: units.gu(5); height: units.gu(5)
            anchors { left: parent.left; leftMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
            Icon {
                anchors.centerIn: parent
                name: "back"
                width: units.gu(2.5); height: units.gu(2.5)
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
            }
            onClicked: pageStack.pop()
        }

        Label {
            anchors { left: backBtn.right; right: parent.right; verticalCenter: parent.verticalCenter }
            leftPadding: units.gu(1)
            text: translator.tr("webReceivePage.title")
            fontSize: "large"
            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
            elide: Text.ElideRight
        }
    }

    // Loading / error state
    Item {
        anchors { top: headerBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page._status !== "running"

        ColumnLayout {
            anchors.centerIn: parent
            spacing: units.gu(2)

            ActivityIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: page._status === "initializing" || page._status === "stopping"
                visible: running
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: page._status === "initializing"
                text: translator.tr("webSharePage.loading")
                fontSize: "large"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                horizontalAlignment: Text.AlignHCenter
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: page._status === "stopping"
                text: translator.tr("webSharePage.stopping")
                fontSize: "large"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                horizontalAlignment: Text.AlignHCenter
            }

            Icon {
                Layout.alignment: Qt.AlignHCenter
                visible: page._status === "error"
                name: "dialog-error"
                width: units.gu(5); height: units.gu(5)
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: page._status === "error"
                text: page._errorMsg.length > 0 ? page._errorMsg : translator.tr("webSharePage.error")
                fontSize: "medium"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.danger : "#C0392B"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Button {
                Layout.alignment: Qt.AlignHCenter
                visible: page._status === "error"
                text: qsTr("Retry")
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                onClicked: page._startWebReceive()
            }
        }
    }

    // Running state - scrollable content
    Flickable {
        id: mainFlick
        anchors { top: headerBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page._status === "running"
        contentHeight: mainCol.implicitHeight + units.gu(4)
        clip: true

        ColumnLayout {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
            spacing: units.gu(1.5)

            Label {
                Layout.fillWidth: true
                text: {
                    var n = page._ips().length
                    if (n === 1) return translator.tr("webSharePage.openLink.one")
                    return translator.tr("webSharePage.openLink.other")
                }
                fontSize: "medium"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                wrapMode: Text.Wrap
            }

            // URL cards - one per IP
            Repeater {
                model: page._ips()
                delegate: Rectangle {
                    Layout.fillWidth: true
                    height: urlRow.implicitHeight + units.gu(2)
                    radius: page.appTheme && page.appTheme.metrics ? page.appTheme.metrics.cardRadius : units.gu(1)
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.secondaryContainer : "#E8F5E9"
                    border.color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.divider : "#E0E0E0"
                    border.width: units.dp(1)

                    RowLayout {
                        id: urlRow
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(1) }
                        spacing: units.gu(0.5)

                        Label {
                            Layout.fillWidth: true
                            text: page._buildUrl(modelData)
                            fontSize: "small"
                            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                            wrapMode: Text.WrapAnywhere
                        }

                        AbstractButton {
                            width: units.gu(4); height: units.gu(4)
                            Icon {
                                anchors.centerIn: parent
                                name: "edit-copy"
                                width: units.gu(2.5); height: units.gu(2.5)
                                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                            }
                            onClicked: {
                                Clipboard.push(page._buildUrl(modelData))
                                page._showToast(qsTr("Copied to clipboard"))
                            }
                        }
                    }
                }
            }

            // Divider
            Rectangle { Layout.fillWidth: true; height: units.dp(1); color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.divider : "#E0E0E0" }

            // Encryption toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)
                Label {
                    Layout.fillWidth: true
                    text: translator.tr("webSharePage.encryption")
                    fontSize: "medium"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                }
                Switch {
                    checked: page._encrypted
                    onCheckedChanged: {
                        if (checked !== page._encrypted) {
                            page._encrypted = checked
                            page._startWebReceive()
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: page._encrypted
                text: translator.tr("webSharePage.encryptionHint")
                fontSize: "small"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.warning : "#FF9800"
                wrapMode: Text.Wrap
            }

            // PIN toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)
                Label {
                    Layout.fillWidth: true
                    text: translator.tr("webSharePage.requirePin")
                    fontSize: "medium"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                }
                Switch {
                    id: pinSwitch
                    checked: page._pinEnabled
                    onCheckedChanged: {
                        if (checked && !page._pinEnabled) {
                            pinDialog.open()
                        } else if (!checked && page._pinEnabled) {
                            page._pinEnabled = false
                            page._pin = ""
                            page._startWebReceive()
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: page._pinEnabled && page._pin.length > 0
                text: translator.trArgs("webSharePage.pinHint", JSON.stringify({ pin: page._pin }))
                fontSize: "small"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.warning : "#FF9800"
                wrapMode: Text.Wrap
            }

            // Divider
            Rectangle { Layout.fillWidth: true; height: units.dp(1); color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.divider : "#E0E0E0" }

            // Info text
            Label {
                Layout.fillWidth: true
                text: qsTr("Open one of the above links in a browser on the same network to upload files to this device.")
                fontSize: "small"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                wrapMode: Text.Wrap
            }

            Item { implicitHeight: units.gu(2) }
        }
    }

    // Toast
    Rectangle {
        id: toastRect
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: units.gu(4) }
        width: toastLabel.implicitWidth + units.gu(3)
        height: toastLabel.implicitHeight + units.gu(1.5)
        radius: height / 2
        color: "#333333"
        opacity: 0
        z: 100
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Label { id: toastLabel; anchors.centerIn: parent; color: "white"; fontSize: "small" }
        Timer { id: toastTimer; interval: 2000; onTriggered: toastRect.opacity = 0 }
    }

    // PIN Dialog
    Dialog {
        id: pinDialog
        modal: true
        anchors.centerIn: parent
        width: Math.min(parent.width - units.gu(4), units.gu(50))
        header: null

        contentItem: ColumnLayout {
            spacing: units.gu(1)
            leftPadding: units.gu(2); rightPadding: units.gu(2)
            topPadding: units.gu(2); bottomPadding: units.gu(2)

            Label {
                Layout.fillWidth: true
                text: translator.tr("webSharePage.requirePin")
                fontSize: "medium"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
            }

            TextField {
                id: pinField
                Layout.fillWidth: true
                placeholderText: qsTr("Enter PIN")
                inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText
                onAccepted: pinDialog._accept()
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    text: qsTr("Cancel")
                    onClicked: { pinField.text = ""; pinSwitch.checked = false; pinDialog.close() }
                }
                Button {
                    text: qsTr("Confirm")
                    enabled: pinField.text.length > 0
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                    onClicked: pinDialog._accept()
                }
            }
        }

        function _accept() {
            var p = pinField.text.trim()
            pinField.text = ""
            if (p.length > 0) {
                page._pin = p
                page._pinEnabled = true
                page._startWebReceive()
            } else {
                pinSwitch.checked = false
            }
            pinDialog.close()
        }

        onOpened: { pinField.text = ""; pinField.forceActiveFocus() }
    }
}