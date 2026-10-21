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

    signal submitted(string message)
    signal canceled()

    title: translator.tr("dialogs.messageInput.title")
    modal: true
    // Instantiated through a Loader, so the declared parent (the
    // zero-sized Loader item) cannot be used for centering.
    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width - units.gu(4), units.gu(60))

    contentItem: ColumnLayout {

        // Popups live in the window overlay, outside the mirrored MainView
        // tree, so right-to-left layout has to be re-enabled on the content.
        LayoutMirroring.enabled: translator.rtl
        LayoutMirroring.childrenInherit: true
        spacing: units.gu(1.5)

        TextField {
            id: messageField
            Layout.fillWidth: true
            placeholderText: translator.tr("dialogs.messageInput.title")
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
                text: translator.tr("sendTab.picker.clipboard")
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
                text: translator.tr("general.cancel")
                onClicked: {
                    messageField.text = ""
                    root.canceled()
                    root.close()
                }
            }

            Button {
                text: translator.tr("general.confirm")
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
