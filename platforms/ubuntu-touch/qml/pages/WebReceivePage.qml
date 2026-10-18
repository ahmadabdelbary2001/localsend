// SPDX-License-Identifier: Apache-2.0
//
// WebReceivePage.qml - "Receive via link" (الاستلام عبر رابط) page for LocalSend on Ubuntu Touch.
// Perfectly mirrors Flutter Android app's WebSharePage (web_share_page.dart) in receive mode.

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3
import "../dialogs"

Page {
    id: page
    property var appTheme
    property var navigationStack: null

    header: null

    // Internal state matching Flutter's _WebSharePageState
    property string _status: "initializing"   // "initializing" | "running" | "error" | "stopping"
    property string _errorMsg: ""
    property bool   _encrypted: false
    property string _pin: ""
    property bool   _pinEnabled: false

    Component.onCompleted: {
        // If already active (e.g. reopen), just update status
        if (serverController.web_receive_active) {
            page._status = "running"
        } else {
            _startWebReceive()
        }
    }

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
            page._encrypted,
            page._pin
        )
    }

    function _ips() {
        var parts = []
        if (typeof localIpsModel !== "undefined" && localIpsModel) {
            var count = localIpsModel.rowCount()
            for (var i = 0; i < count; i++) {
                var idx = localIpsModel.index(i, 0)
                var ip = localIpsModel.data(idx, 0)
                if (ip && ip.length > 0) {
                    parts.push(ip)
                }
            }
        }
        if (parts.length === 0) {
            parts.push("127.0.0.1")
        }
        return parts
    }

    function _getPort() {
        if (serverController.web_receive_port > 0) {
            return serverController.web_receive_port
        }
        if (settingsController.port > 0) {
            return settingsController.port
        }
        return 53317
    }

    function _buildUrl(ip) {
        var scheme = page._encrypted ? "https" : "http"
        return scheme + "://" + ip + ":" + _getPort()
    }

    function _buildUrlWithPin(ip) {
        var url = _buildUrl(ip)
        if (page._pin.length > 0) {
            return url + "/?pin=" + encodeURIComponent(page._pin)
        }
        return url
    }

    function _showToast(msg) {
        toastLabel.text = msg
        toastRect.opacity = 1
        toastTimer.restart()
    }

    function _generateRandomPin() {
        var chars = "0123456789"
        var result = ""
        for (var i = 0; i < 6; i++) {
            result += chars.charAt(Math.floor(Math.random() * chars.length))
        }
        return result
    }

    Connections {
        target: serverController
        function onWeb_receive_changed() {
            if (serverController.web_receive_active) {
                page._status = "running"
                initTimer.stop()
            } else if (page._status !== "stopping") {
                page._status = "error"
                page._errorMsg = translator.tr("webSharePage.error")
                initTimer.stop()
            }
        }
    }

    // Fallback: if the server takes too long to initialize, show an error
    Timer {
        id: initTimer
        interval: 8000
        repeat: false
        onTriggered: {
            if (page._status === "initializing") {
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

    // App Bar / Header
    Item {
        id: headerBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(6)
        z: 10

        Rectangle {
            anchors.fill: parent
            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surface : "#FFFFFF"
            border.color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.divider : "#E0E0E0"
            border.width: units.dp(1)
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
            onClicked: {
                if (typeof pageStack !== "undefined" && pageStack !== null) {
                    pageStack.pop()
                } else if (page.navigationStack) {
                    page.navigationStack.pop()
                }
            }
        }

        Label {
            anchors {
                left: backBtn.right
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: units.gu(1)
            }
            text: translator.tr("webReceivePage.title")
            fontSize: "large"
            font.bold: true
            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
            elide: Text.ElideRight
        }
    }

    // Initializing / stopping / error states
    Item {
        anchors { top: headerBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page._status !== "running"

        ColumnLayout {
            anchors.centerIn: parent
            spacing: units.gu(2)
            width: Math.min(parent.width - units.gu(4), units.gu(45))

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
                wrapMode: Text.Wrap
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: page._status === "stopping"
                text: translator.tr("webSharePage.stopping")
                fontSize: "large"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Icon {
                Layout.alignment: Qt.AlignHCenter
                visible: page._status === "error"
                name: "dialog-error"
                width: units.gu(5); height: units.gu(5)
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.danger : "#C0392B"
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
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

    // Running view (mirrors ResponsiveListView from Flutter)
    Flickable {
        id: mainFlick
        anchors { top: headerBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: page._status === "running"
        contentHeight: mainCol.implicitHeight + units.gu(6)
        clip: true

        ColumnLayout {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
            spacing: units.gu(2)

            // Section title: "Open one of these links in your browser:" / "افتح أحد هذه الروابط في المتصفح:"
            Label {
                Layout.fillWidth: true
                text: {
                    var n = page._ips().length
                    if (n === 1) return translator.tr("webSharePage.openLink.one")
                    return translator.tr("webSharePage.openLink.other")
                }
                fontSize: "medium"
                font.bold: true
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                wrapMode: Text.Wrap
            }

            // Card with URLs (mirrors Flutter's Card with secondaryContainer color)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: urlsCol.implicitHeight + units.gu(2)
                radius: page.appTheme && page.appTheme.metrics ? page.appTheme.metrics.cardRadius : units.gu(1)
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTint : "#ECEFF1"
                border.color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.divider : "#E0E0E0"
                border.width: units.dp(1)

                ColumnLayout {
                    id: urlsCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(1) }
                    spacing: units.gu(1)

                    Repeater {
                        model: page._ips()
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: units.gu(0.5)

                            Label {
                                Layout.fillWidth: true
                                text: page._buildUrl(modelData)
                                fontSize: "small"
                                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                                wrapMode: Text.WrapAnywhere
                            }

                            // Copy button (content_copy)
                            AbstractButton {
                                width: units.gu(4.5); height: units.gu(4)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: units.gu(0.5)
                                    color: parent.pressed ? "#D0D0D0" : "transparent"
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    name: "edit-copy"
                                    width: units.gu(2.4); height: units.gu(2.4)
                                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                                }
                                onClicked: {
                                    Clipboard.push(page._buildUrl(modelData))
                                    page._showToast(translator.tr("general.copiedToClipboard"))
                                }
                            }

                            // QR button (qr_code)
                            AbstractButton {
                                width: units.gu(4.5); height: units.gu(4)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: units.gu(0.5)
                                    color: parent.pressed ? "#D0D0D0" : "transparent"
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    source: "qrc:/qml/assets/qr-code.svg"
                                    width: units.gu(2.4); height: units.gu(2.4)
                                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                                }
                                onClicked: {
                                    qrDialog.qrData = page._buildUrlWithPin(modelData)
                                    qrDialog.qrLabel = page._buildUrl(modelData)
                                    qrDialog.pin = page._pin
                                    qrDialog.open()
                                }
                            }
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: units.dp(1)
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.divider : "#E0E0E0"
            }

            // =========================================================
            // Checkbox 1: Encryption (التعمية)
            // =========================================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.5)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(1.5)

                    Rectangle {
                        width: units.gu(2.5); height: units.gu(2.5)
                        radius: units.dp(4)
                        color: page._encrypted
                            ? (page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C")
                            : "transparent"
                        border.color: page._encrypted
                            ? (page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C")
                            : (page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#757575")
                        border.width: units.dp(2)

                        Icon {
                            anchors.centerIn: parent
                            name: "tick"
                            width: units.gu(1.8); height: units.gu(1.8)
                            color: "#FFFFFF"
                            visible: page._encrypted
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                page._encrypted = !page._encrypted
                                page._startWebReceive()
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr("webSharePage.encryption")
                        fontSize: "medium"
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                page._encrypted = !page._encrypted
                                page._startWebReceive()
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: units.gu(4)
                    visible: page._encrypted
                    text: translator.tr("webSharePage.encryptionHint")
                    fontSize: "small"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.warning : "#FF9800"
                    wrapMode: Text.Wrap
                }
            }

            // =========================================================
            // Checkbox 2: Auto-accept requests (قبول الطلبات تلقائياً)
            // =========================================================
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1.5)

                Rectangle {
                    width: units.gu(2.5); height: units.gu(2.5)
                    radius: units.dp(4)
                    color: serverController.auto_accept
                        ? (page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C")
                        : "transparent"
                    border.color: serverController.auto_accept
                        ? (page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C")
                        : (page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#757575")
                    border.width: units.dp(2)

                    Icon {
                        anchors.centerIn: parent
                        name: "tick"
                        width: units.gu(1.8); height: units.gu(1.8)
                        color: "#FFFFFF"
                        visible: serverController.auto_accept
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            serverController.set_auto_accept(!serverController.auto_accept)
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: translator.tr("webSharePage.autoAccept")
                    fontSize: "medium"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            serverController.set_auto_accept(!serverController.auto_accept)
                        }
                    }
                }
            }

            // =========================================================
            // Checkbox 3: Require PIN (يتطلب رمز PIN)
            // =========================================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.5)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(1.5)

                    Rectangle {
                        width: units.gu(2.5); height: units.gu(2.5)
                        radius: units.dp(4)
                        color: (page._pin.length > 0)
                            ? (page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C")
                            : "transparent"
                        border.color: (page._pin.length > 0)
                            ? (page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C")
                            : (page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#757575")
                        border.width: units.dp(2)

                        Icon {
                            anchors.centerIn: parent
                            name: "tick"
                            width: units.gu(1.8); height: units.gu(1.8)
                            color: "#FFFFFF"
                            visible: (page._pin.length > 0)
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: page._togglePin()
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr("webSharePage.requirePin")
                        fontSize: "medium"
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: page._togglePin()
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: units.gu(4)
                    visible: (page._pin.length > 0)
                    text: translator.trArgs("webSharePage.pinHint", JSON.stringify({ pin: page._pin }))
                    fontSize: "small"
                    font.bold: true
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.warning : "#FF9800"
                    wrapMode: Text.Wrap
                }
            }

            Item { implicitHeight: units.gu(3) }
        }
    }

    function _togglePin() {
        if (page._pin.length > 0) {
            page._pin = ""
            page._pinEnabled = false
            page._startWebReceive()
        } else {
            pinEntryDialog.suggestedPin = page._generateRandomPin()
            pinEntryDialog.open()
        }
    }

    // QR Code Dialog
    QrDialog {
        id: qrDialog
        appTheme: page.appTheme
    }

    // PIN Input Dialog
    Dialog {
        id: pinEntryDialog
        property string suggestedPin: ""
        modal: true
        anchors.centerIn: parent
        width: Math.min(parent.width - units.gu(4), units.gu(45))
        header: null

        contentItem: ColumnLayout {
            spacing: units.gu(1.5)
            leftPadding: units.gu(2); rightPadding: units.gu(2)
            topPadding: units.gu(2); bottomPadding: units.gu(2)

            Label {
                Layout.fillWidth: true
                text: translator.tr("dialogs.pin.title")
                fontSize: "large"
                font.bold: true
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
            }

            TextField {
                id: pinField
                Layout.fillWidth: true
                placeholderText: qsTr("PIN")
                inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText
                onAccepted: pinEntryDialog._confirm()
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }

                Button {
                    text: translator.tr("general.cancel")
                    onClicked: {
                        pinField.text = ""
                        pinEntryDialog.close()
                    }
                }

                Button {
                    text: translator.tr("general.confirm")
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                    enabled: pinField.text.trim().length > 0
                    onClicked: pinEntryDialog._confirm()
                }
            }
        }

        function _confirm() {
            var p = pinField.text.trim()
            pinField.text = ""
            if (p.length > 0) {
                page._pin = p
                page._pinEnabled = true
                page._startWebReceive()
            }
            pinEntryDialog.close()
        }

        onOpened: {
            pinField.text = pinEntryDialog.suggestedPin
            pinField.forceActiveFocus()
        }
    }

    // Toast notification
    Rectangle {
        id: toastRect
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: units.gu(4) }
        width: toastLabel.implicitWidth + units.gu(4)
        height: toastLabel.implicitHeight + units.gu(2)
        radius: height / 2
        color: "#333333"
        opacity: 0
        z: 100
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Label {
            id: toastLabel
            anchors.centerIn: parent
            color: "white"
            fontSize: "small"
        }
        Timer {
            id: toastTimer
            interval: 2500
            onTriggered: toastRect.opacity = 0
        }
    }
}
