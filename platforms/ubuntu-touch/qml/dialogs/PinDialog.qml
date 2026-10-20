import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../components"

Dialog {
    id: root
    property var appTheme

    // QQuickControls popups are drawn with the application palette; mirror the
    // app palette so dialogs stay readable in dark / OLED modes.
    palette.window: appTheme && appTheme.colors ? appTheme.colors.surface : "#FFFFFF"
    palette.windowText: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
    palette.base: appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1"
    palette.text: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
    palette.button: appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1"
    palette.buttonText: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"

    background: DialogFrame { appTheme: root.appTheme }
    property bool showInvalidPin: false

    signal submitted(string pin)
    signal canceled()

    title: translator.tr("dialogs.pin.title")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(60))

    contentItem: ColumnLayout {
        spacing: units.gu(1)

        TextField {
            id: pinField
            Layout.fillWidth: true
            placeholderText: translator.tr("web.enterPin")
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
            text: translator.tr("web.invalidPin")
            color: root.appTheme && root.appTheme.colors
                ? root.appTheme.colors.warning
                : "#FF9800"
            fontSize: "small"
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }

            Button {
                text: translator.tr("general.cancel")
                onClicked: root.canceled()
            }

            Button {
                text: translator.tr("general.confirm")
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
