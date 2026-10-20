import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

import "../dialogs"

Page {
    id: page
    header: Item { } // hides MainView's deprecated app header
    property var appTheme
    property var navigationStack: null

    property bool _showAdvanced: false
    property bool _showHistoryButton: true

    function toggleAdvanced() {
        if (_showAdvanced) {
            _showAdvanced = false
            hideTimer.restart()
        } else {
            _showAdvanced = true
            _showHistoryButton = false
        }
    }

    function _ips() {
        var parts = []
        for (var i = 0; i < localIpsModel.rowCount(); i++) {
            var idx = localIpsModel.index(i, 0)
            var ip = localIpsModel.data(idx, 0)
            if (ip && ip.length > 0)
                parts.push(ip)
        }
        return parts
    }

    function _ipsLabel() {
        return _ips().join("   ")
    }

    // Flutter shows the last IPv4 octet (`#42`) instead of the full address.
    function _visualIds() {
        var ids = []
        var ips = _ips()
        for (var i = 0; i < ips.length; i++) {
            var value = "#" + ips[i].split(".").pop()
            if (ids.indexOf(value) === -1)
                ids.push(value)
        }
        return ids.join(" ")
    }

    Timer {
        id: hideTimer
        interval: 200
        repeat: false
        onTriggered: page._showHistoryButton = true
    }

    // ---------------- Main content ----------------
    Item {
        anchors.fill: parent

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - units.gu(4), units.gu(55))
            spacing: units.gu(2)

            // Logo / receive icon — mirrors Flutter's RotatingWidget(LocalSendLogo)
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: units.gu(18)
                Layout.preferredHeight: units.gu(18)

                // Outer circle (tinted when running)
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: page.appTheme && page.appTheme.colors
                           ? (serverController.running
                              ? Qt.rgba(0, 0.42, 0.36, 0.10)
                              : page.appTheme.colors.surfaceTint)
                           : "#ECEFF1"
                    Behavior on color { ColorAnimation { duration: 400 } }
                }

                // Try logo image first; fall back to an icon
                Image {
                    id: logoImg
                    anchors.centerIn: parent
                    width: units.gu(12)
                    height: units.gu(12)
                    source: "qrc:/qml/assets/logo.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    cache: true
                    visible: status === Image.Ready

                    RotationAnimator on rotation {
                        running: serverController.running && settingsController.enable_animations
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 15000
                    }
                }

                // Fallback icon when logo image fails to load
                Rectangle {
                    id: fallbackCircle
                    anchors.centerIn: parent
                    width: units.gu(9)
                    height: units.gu(9)
                    radius: width / 2
                    color: serverController.running
                           ? (page.appTheme && page.appTheme.colors ? Qt.rgba(0, 0.42, 0.36, 0.15) : "#E0F2F1")
                           : (page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTint : "#ECEFF1")
                    visible: logoImg.status !== Image.Ready
                    Behavior on color { ColorAnimation { duration: 400 } }

                    Icon {
                        anchors.centerIn: parent
                        width: units.gu(5)
                        height: units.gu(5)
                        name: "transfer-progress-download"
                        color: serverController.running
                               ? (page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C")
                               : (page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#888")
                        SequentialAnimation on opacity {
                            running: serverController.running && settingsController.enable_animations && logoImg.status !== Image.Ready
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.5; duration: 1200; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            // Alias
            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: serverController.alias.length > 0
                      ? serverController.alias
                      : settingsController.alias
                // Lomiri's Label has no "xx-large"; Flutter renders the alias
                // at 48px, so an explicit pixel size keeps the same hierarchy.
                font.pixelSize: units.dp(36)
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            // Offline, or the visual IP ids (#42 #7) exactly like Flutter.
            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: serverController.running
                      ? (page._visualIds().length > 0
                         ? page._visualIds()
                         : translator.tr("general.unknown"))
                      : translator.tr("general.offline")
                fontSize: "large"
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            // Receive via link (server controls live in the settings tab).
            // Flutter uses an OutlinedButton with a globe icon; Lomiri's
            // default Button is a dark pill, which clashes with the light
            // palette, so the outline is drawn directly.
            Rectangle {
                id: linkButton
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: units.gu(2)
                implicitWidth: linkRow.implicitWidth + units.gu(5)
                implicitHeight: units.gu(5)
                radius: height / 2
                color: "transparent"
                border.width: units.dp(1)
                border.color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"

                Row {
                    id: linkRow
                    anchors.centerIn: parent
                    spacing: units.gu(1)

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(2.4)
                        height: width
                        name: "stock_website"
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: translator.tr("receiveTab.link")
                        fontSize: "small"
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (page.navigationStack) {
                            page.navigationStack.push(
                                Qt.resolvedUrl("WebReceivePage.qml"),
                                {
                                    appTheme: page.appTheme,
                                    navigationStack: page.navigationStack
                                }
                            )
                        } else {
                            console.warn("[NAV] navigation stack unavailable for WebReceivePage")
                        }
                    }
                }
            }
        }
    }

    // ---------------- Top-right buttons ----------------
    Row {
        z: 2
        anchors { top: parent.top; right: parent.right; margins: units.gu(2) }
        spacing: units.gu(1)

        AbstractButton {
            visible: !page._showAdvanced && page._showHistoryButton
            width: units.gu(5); height: units.gu(5)
            Icon { anchors.centerIn: parent; name: "history"; width: units.gu(3); height: units.gu(3) }
            onClicked: historyDialog.open()
        }

        AbstractButton {
            width: units.gu(5); height: units.gu(5)
            Icon { anchors.centerIn: parent; name: "info"; width: units.gu(3); height: units.gu(3) }
            onClicked: page.toggleAdvanced()
        }
    }

    // ---------------- Advanced info box ----------------
    Rectangle {
        z: 1
        anchors { top: parent.top; right: parent.right; margins: units.gu(2) }
        width: Math.min(units.gu(30), Math.max(units.gu(1), parent.width - units.gu(4)))
        height: infoColumn.childrenRect.height + units.gu(2)
        radius: page.appTheme && page.appTheme.metrics ? page.appTheme.metrics.cardRadius : units.gu(0.6)
        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surface : "#ffffff"
        border.color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.divider : "#e0e0e0"
        border.width: units.dp(1)
        visible: page._showAdvanced
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Column {
            id: infoColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: units.gu(1)
            }
            spacing: units.gu(0.5)

            Label { text: translator.tr("receiveTab.infoBox.alias"); fontSize: "x-small"; opacity: 0.6 }
            Label {
                text: serverController.alias.length > 0 ? serverController.alias : "-"
                fontSize: "small"
                wrapMode: Text.WrapAnywhere
            }

            Label { text: translator.tr("receiveTab.infoBox.ip"); fontSize: "x-small"; opacity: 0.6 }
            Label {
                text: page._ipsLabel().length > 0
                      ? page._ipsLabel()
                      : translator.tr("general.unknown")
                fontSize: "small"
                wrapMode: Text.WrapAnywhere
            }

            Label { text: translator.tr("receiveTab.infoBox.port"); fontSize: "x-small"; opacity: 0.6 }
            Label {
                text: serverController.running ? serverController.port.toString() : "-"
                fontSize: "small"
            }
        }
    }

    HistoryDialog {
        id: historyDialog
        appTheme: page.appTheme
    }
}
