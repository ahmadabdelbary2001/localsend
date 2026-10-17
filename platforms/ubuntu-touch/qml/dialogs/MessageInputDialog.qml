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

        TextArea {
            id: messageArea
            Layout.fillWidth: true
            Layout.preferredHeight: units.gu(14)
            placeholderText: qsTr("Type a message…")
            wrapMode: TextEdit.Wrap
            selectByMouse: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                text: qsTr("Paste")
                onClicked: {
                    messageArea.paste()
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Cancel")
                onClicked: {
                    messageArea.text = ""
                    root.canceled()
                    root.close()
                }
            }

            Button {
                text: qsTr("Confirm")
                color: root.appTheme && root.appTheme.colors
                    ? root.appTheme.colors.primary
                    : "#00695C"
                enabled: messageArea.text.trim().length > 0
                onClicked: {
                    var msg = messageArea.text
                    messageArea.text = ""
                    root.submitted(msg)
                    root.close()
                }
            }
        }
    }

    onOpened: {
        messageArea.forceActiveFocus()
    }
}
