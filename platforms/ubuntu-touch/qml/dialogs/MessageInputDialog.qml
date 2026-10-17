import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

Dialog {
    id: root
    property var appTheme

    signal submitted(string message)
    signal canceled()

    title: qsTr("Send Message")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(60))

    contentItem: ColumnLayout {
        spacing: units.gu(1.5)

        TextField {
            id: messageField
            Layout.fillWidth: true
            placeholderText: qsTr("Type a message or paste…")
            onAccepted: {
                if (text.trim().length > 0) {
                    var msg = text
                    text = ""
                    root.submitted(msg)
                    root.close()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                text: qsTr("Paste")
                onClicked: {
                    try {
                        messageField.paste()
                    } catch (e) {
                        if (typeof Clipboard !== "undefined" && Clipboard.text) {
                            messageField.text = Clipboard.text
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Cancel")
                onClicked: {
                    messageField.text = ""
                    root.canceled()
                    root.close()
                }
            }

            Button {
                text: qsTr("Confirm")
                color: root.appTheme && root.appTheme.colors
                    ? root.appTheme.colors.primary
                    : "#00695C"
                enabled: messageField.text.trim().length > 0
                onClicked: {
                    var msg = messageField.text
                    messageField.text = ""
                    root.submitted(msg)
                    root.close()
                }
            }
        }
    }

    onOpened: {
        messageField.text = ""
        messageField.forceActiveFocus()
    }
}
