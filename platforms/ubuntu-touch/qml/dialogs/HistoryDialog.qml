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

    title: translator.tr("receiveHistoryPage.title")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(60))
    height: Math.min(parent.height - units.gu(8), units.gu(75))

    contentItem: ColumnLayout {

        // Popups live in the window overlay, outside the mirrored MainView
        // tree, so right-to-left layout has to be re-enabled on the content.
        LayoutMirroring.enabled: translator.rtl
        LayoutMirroring.childrenInherit: true
        spacing: units.gu(1)

        RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            Button {
                text: translator.tr("receiveHistoryPage.deleteHistory")
                enabled: historyController.count > 0
                onClicked: historyController.clear()
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: units.gu(4)
            visible: historyController.count === 0
            text: translator.tr("receiveHistoryPage.empty")
            fontSize: "medium"
            horizontalAlignment: Text.AlignHCenter
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368"
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: units.gu(0.5)
            model: historyController
            visible: historyController.count > 0

            delegate: ListItem {
                height: units.gu(7)
                ListItemLayout {
                    title.text: model.fileName
                    title.color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                    subtitle.text: model.senderAlias + "  ·  " + _humanSize(model.fileSize)
                    subtitle.color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368"
                }
                trailingActions: ListItemActions {
                    actions: [
                        Action {
                            iconName: "delete"
                            text: translator.tr("general.delete")
                            onTriggered: historyController.remove(model.id)
                        }
                    ]
                }
                onClicked: {
                    if (model.path.length > 0) {
                        Qt.openUrlExternally("file://" + model.path)
                    }
                }
            }
        }
    }

    function _humanSize(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
        if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " MB"
        return (bytes / 1024 / 1024 / 1024).toFixed(2) + " GB"
    }
}
