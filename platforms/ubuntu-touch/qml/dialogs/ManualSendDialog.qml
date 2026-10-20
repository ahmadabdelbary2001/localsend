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

    signal submitted(string ip, int port, bool https)
    signal canceled()

    // No QQuickControls header: it is drawn inside the same padded area as
    // the content item and overlaps it once the dialog has a custom background.
    header: null
    modal: true
    // This dialog is instantiated through a Loader, so its declared parent
    // (the zero-sized Loader item) cannot be used for centering. Attach the
    // popup to the window overlay instead.
    parent: Overlay.overlay
    width: Math.min(parent.width - units.gu(4), units.gu(50))
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    padding: units.gu(2)

    contentItem: ColumnLayout {
        spacing: units.gu(1.5)

        Label {
            Layout.fillWidth: true
            text: translator.tr("dialogs.addressInput.title")
            fontSize: "large"
            font.bold: true
            wrapMode: Text.Wrap
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
        }

        // IP Address input
        Label {
            text: translator.tr("dialogs.addressInput.ip")
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
                    text: translator.tr("settingsTab.network.port")
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

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                Layout.fillWidth: true
                text: translator.tr("general.cancel")
                onClicked: {
                    root.canceled()
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                text: translator.tr("sendTab.title")
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
