import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

Dialog {
    id: root
    property var appTheme

    signal submitted(string ip, int port, bool https)
    signal canceled()

    title: qsTr("Send to address")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(50))
    height: Math.min(parent.height - units.gu(6), units.gu(48))

    contentItem: ColumnLayout {
        anchors.margins: units.gu(1.5)
        spacing: units.gu(1.5)

        Label {
            text: qsTr("Enter the recipient IP address and port:")
            fontSize: "small"
            wrapMode: Text.Wrap
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368"
        }

        // IP Address input
        Label {
            text: qsTr("IP address / Host")
            fontSize: "small"
            font.bold: true
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
        }

        TextField {
            id: ipField
            Layout.fillWidth: true
            placeholderText: "192.168.1.50"
            inputMethodHints: Qt.ImhUrlCharactersOnly
        }

        // Port & HTTPS
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(2)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.5)

                Label {
                    text: qsTr("Port")
                    fontSize: "small"
                    font.bold: true
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                }

                TextField {
                    id: portField
                    Layout.fillWidth: true
                    text: "53317"
                    inputMethodHints: Qt.ImhDigitsOnly
                }
            }

            ColumnLayout {
                spacing: units.gu(0.5)

                Label {
                    text: "HTTPS"
                    fontSize: "small"
                    font.bold: true
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                }

                CheckBox {
                    id: httpsCheck
                    checked: true
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                Layout.fillWidth: true
                text: qsTr("Cancel")
                onClicked: {
                    root.canceled()
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                text: qsTr("Send")
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
                enabled: ipField.text.trim().length > 0
                onClicked: {
                    var p = parseInt(portField.text.trim()) || 53317
                    root.submitted(ipField.text.trim(), p, httpsCheck.checked)
                    root.close()
                }
            }
        }
    }
}
