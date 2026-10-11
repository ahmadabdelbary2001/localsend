import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Page {
    id: page
    property var appTheme

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

    function _ipsLabel() {
        var parts = []
        for (var i = 0; i < localIpsModel.rowCount(); i++) {
            var idx = localIpsModel.index(i, 0)
            parts.push(localIpsModel.data(idx, 0))
        }
        return parts.join("   ")
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

            // Logo mark
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: units.gu(18)
                Layout.preferredHeight: units.gu(18)
                radius: width / 2
                color: page.appTheme ? page.appTheme.colors.surfaceTint : "#ECEFF1"

                Label {
                    anchors.centerIn: parent
                    text: "LS"
                    fontSize: "xx-large"
                    color: page.appTheme ? page.appTheme.colors.primary : "#00695C"
                }

                RotationAnimator on rotation {
                    running: serverController.running
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 15000
                }
            }

            // Alias
            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: serverController.alias.length > 0
                      ? serverController.alias
                      : settingsController.alias
                fontSize: "xx-large"
                color: page.appTheme ? page.appTheme.colors.surfaceText : "#1B1D21"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            // Online/offline indicator
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: units.gu(1)

                Rectangle {
                    width: units.gu(1)
                    height: width
                    radius: width / 2
                    color: serverController.running
                           ? (page.appTheme ? page.appTheme.colors.primary : "#00695C")
                           : (page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#888")
                }

                Label {
                    text: serverController.running
                          ? translator.tr("general.online")
                          : translator.tr("general.offline")
                    fontSize: "medium"
                    color: page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                }
            }

            // IPs
            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                text: page._ipsLabel()
                visible: serverController.running && text.length > 0
                fontSize: "small"
                color: page.appTheme ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            // Receive via link
            Button {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: units.gu(2)
                text: translator.tr("receiveTab.link")
                onClicked: {
                    // TODO: Web share page (core supports it)
                    console.log("TODO: web share page")
                }
            }

            // Server start/stop
            Button {
                Layout.alignment: Qt.AlignHCenter
                text: serverController.running
                      ? translator.tr("general.stop")
                      : translator.tr("general.start")
                color: serverController.running
                       ? (page.appTheme ? page.appTheme.colors.danger : "#C0392B")
                       : (page.appTheme ? page.appTheme.colors.primary : "#00695C")
                onClicked: {
                    if (serverController.running) {
                        serverController.stop()
                    } else {
                        serverController.start(
                            settingsController.alias,
                            settingsController.port,
                            settingsController.https,
                            settingsController.receivePin)
                    }
                }
            }
        }
    }

    // ---------------- Top-right buttons ----------------
    Row {
        anchors { top: parent.top; right: parent.right; margins: units.gu(2) }
        spacing: units.gu(1)

        AbstractButton {
            visible: !page._showAdvanced && page._showHistoryButton
            width: units.gu(5); height: units.gu(5)
            Icon { anchors.centerIn: parent; name: "history"; width: units.gu(3); height: units.gu(3) }
            onClicked: console.log("TODO: receive history page")
        }

        AbstractButton {
            width: units.gu(5); height: units.gu(5)
            Icon { anchors.centerIn: parent; name: "info"; width: units.gu(3); height: units.gu(3) }
            onClicked: page.toggleAdvanced()
        }
    }

    // ---------------- Advanced info box ----------------
    Rectangle {
        anchors { top: parent.top; right: parent.right; margins: units.gu(2) }
        width: units.gu(30)
        height: infoColumn.height + units.gu(2)
        radius: page.appTheme ? page.appTheme.metrics.cardRadius : units.gu(0.6)
        color: page.appTheme ? page.appTheme.colors.surface : "#ffffff"
        border.color: page.appTheme ? page.appTheme.colors.divider : "#e0e0e0"
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
}
