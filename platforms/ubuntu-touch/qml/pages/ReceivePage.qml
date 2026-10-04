import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Page {
    id: page
    property var theme

    // UI-only state that mirrors receive_tab.dart
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

    Timer {
        id: hideTimer
        interval: 200
        repeat: false
        onTriggered: page._showHistoryButton = true
    }

    // ---------- Main content ----------
    Item {
        anchors.fill: parent

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - units.gu(4), units.gu(60))
            spacing: units.gu(2)

            // Animated logo. Rotates when server is running.
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: units.gu(20)
                Layout.preferredHeight: units.gu(20)

                Image {
                    id: logo
                    anchors.fill: parent
                    source: "qrc:/qml/assets/logo.svg"
                    fillMode: Image.PreserveAspectFit
                    // TODO(assets): reuse app/assets/images/logo.svg from Flutter.
                    visible: false
                }

                // Fallback text logo until assets are wired.
                Label {
                    anchors.centerIn: parent
                    text: "LocalSend"
                    fontSize: "x-large"
                }

                RotationAnimator on rotation {
                    running: serverController.running
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 15000
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: serverController.alias.length > 0 ? serverController.alias : settingsController.alias
                fontSize: "xx-large"
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: serverController.running
                    ? _ipsLabel()
                    : translator.tr("general.offline")
                fontSize: "large"
                opacity: 0.8
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Item { Layout.preferredHeight: units.gu(2) }

            Button {
                Layout.alignment: Qt.AlignHCenter
                text: translator.tr("receiveTab.link")
                onClicked: {
                    // TODO(nav): push WebSharePage once the Rust bridge exposes it.
                }
            }
        }
    }

    // ---------- Top-right corner buttons ----------
    Row {
        anchors { top: parent.top; right: parent.right; margins: units.gu(2) }
        spacing: units.gu(1)

        AbstractButton {
            visible: !page._showAdvanced && page._showHistoryButton
            width: units.gu(5); height: units.gu(5)
            Icon { anchors.centerIn: parent; name: "history"; width: units.gu(3); height: units.gu(3) }
            onClicked: {
                // TODO(nav): push ReceiveHistoryPage via Rust bridge.
            }
        }

        AbstractButton {
            width: units.gu(5); height: units.gu(5)
            Icon { anchors.centerIn: parent; name: "info"; width: units.gu(3); height: units.gu(3) }
            onClicked: page.toggleAdvanced()
        }
    }

    // ---------- Advanced info box ----------
    Rectangle {
        anchors { top: parent.top; right: parent.right; margins: units.gu(2) }
        width: units.gu(28)
        height: advancedColumn.height + units.gu(2)
        radius: theme ? theme.metrics.cardRadius : units.gu(0.6)
        color: theme ? theme.colors.surface : "#ffffff"
        border.color: theme ? theme.colors.divider : "#e0e0e0"
        visible: page._showAdvanced
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Column {
            id: advancedColumn
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: units.gu(1) }
            spacing: units.gu(0.5)

            Label { text: translator.tr("receiveTab.infoBox.alias"); fontSize: "small"; opacity: 0.6 }
            Label {
                text: serverController.alias.length > 0 ? serverController.alias : "-"
                wrapMode: Text.WrapAnywhere
                fontSize: "small"
            }

            Label { text: translator.tr("receiveTab.infoBox.ip"); fontSize: "small"; opacity: 0.6 }
            Label {
                text: localIpsModel.rowCount() > 0 ? _ipsLabel() : translator.tr("general.unknown")
                wrapMode: Text.WrapAnywhere
                fontSize: "small"
            }

            Label { text: translator.tr("receiveTab.infoBox.port"); fontSize: "small"; opacity: 0.6 }
            Label {
                text: serverController.running ? serverController.port.toString() : "-"
                fontSize: "small"
            }
        }
    }

    function _ipsLabel() {
        var parts = []
        for (var i = 0; i < localIpsModel.rowCount(); i++) {
            var ip = localIpsModel.data(localIpsModel.index(i, 0), 0)
            parts.push("· " + ip)
        }
        return parts.join("  ")
    }
}