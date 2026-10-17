import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

Dialog {
    id: root
    property var appTheme
    property bool showInvalidPin: false

    signal submitted(string pin)
    signal canceled()

    title: qsTr("Enter PIN")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(60))

    contentItem: ColumnLayout {
        spacing: units.gu(1)

        TextField {
            id: pinField
            Layout.fillWidth: true
            placeholderText: qsTr("PIN")
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText
            onAccepted: {
                var p = text
                text = ""
                root.submitted(p)
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.showInvalidPin
            text: qsTr("Invalid PIN")
            color: root.appTheme && root.appTheme.colors
                ? root.appTheme.colors.warning
                : "#FF9800"
            fontSize: "small"
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Cancel")
                onClicked: root.canceled()
            }

            Button {
                text: qsTr("Confirm")
                color: root.appTheme && root.appTheme.colors
                    ? root.appTheme.colors.primary
                    : "#00695C"
                enabled: pinField.text.length > 0
                onClicked: {
                    var p = pinField.text
                    pinField.text = ""
                    root.submitted(p)
                }
            }
        }
    }

    onOpened: {
        pinField.text = ""
        pinField.forceActiveFocus()
    }
}
