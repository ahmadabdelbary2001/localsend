import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

// Incoming transfer prompt.
//
// This is a Popup (not a plain Item) so that it can be raised above every
// other dialog: an incoming request must stay visible and accept-able even
// when a picker is open, otherwise the sender times out.
Dialog {
    id: root
    property var appTheme

    // Match Flutter's auto-finish: close the dialog once the session ends.
    Connections {
        target: serverController
        function onIncoming_changed() {
            if (settingsController.auto_finish
                    && serverController.incoming_phase === "done") {
                serverController.dismiss_incoming()
            }
        }
    }

    // Keep the dialog in sync with the controller; the Loader in Main.qml
    // only creates/destroys it, it does not drive visibility.
    Component.onCompleted: root.open()

    modal: true
    dim: false // the background below is the scrim
    closePolicy: Popup.NoAutoClose
    // Above the folder / app / option dialogs (they default to z 0).
    z: 10

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    padding: 0

    background: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    contentItem: Item {

        // Popups live in the window overlay, outside the mirrored MainView
        // tree, so right-to-left layout has to be re-enabled on the content.
        LayoutMirroring.enabled: translator.rtl
        LayoutMirroring.childrenInherit: true
        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - units.gu(4), units.gu(60))
            height: Math.min(parent.height - units.gu(8), units.gu(75))
            radius: root.appTheme && root.appTheme.metrics ? root.appTheme.metrics.cardRadius : units.gu(0.6)
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surface : "#ffffff"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: units.gu(2)
                spacing: units.gu(1.5)

                // ---- Header ----
                Label {
                    Layout.fillWidth: true
                    text: {
                        var p = serverController.incoming_phase
                        if (p === "waiting")   return translator.tr("progressPage.titleReceiving")
                        if (p === "receiving") return translator.tr("progressPage.titleReceiving")
                        return translator.tr("general.finished")
                    }
                    fontSize: "large"
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                }

                Label {
                    Layout.fillWidth: true
                    text: serverController.incoming_sender
                          + " · "
                          + serverController.incoming_file_count
                          + " " + translator.tr("general.files")
                    fontSize: "small"
                    opacity: 0.7
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368"
                    elide: Text.ElideRight
                }

                // ---- File list ----
                ListView {
                    id: fileList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: units.gu(0.5)
                    model: incomingFilesModel

                    delegate: ColumnLayout {
                        width: fileList.width
                        spacing: units.gu(0.3)

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: model.fileName
                                fontSize: "small"
                                elide: Text.ElideRight
                                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                            }
                            Label {
                                text: _humanSize(model.size)
                                fontSize: "x-small"
                                opacity: 0.6
                                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368"
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: units.dp(4)
                            radius: units.dp(2)
                            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTint : "#ECEFF1"
                            visible: model.status === "sending"
                                     || model.status === "finished"
                                     || model.status === "failed"

                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, model.progress))
                                height: parent.height
                                radius: parent.radius
                                color: model.status === "failed"
                                       ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.danger : "#C0392B")
                                       : (root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C")
                            }
                        }

                        Label {
                            text: {
                                var s = model.status
                                if (s === "queue")    return translator.tr("general.queue")
                                if (s === "sending")  return Math.round(model.progress * 100) + "%"
                                if (s === "finished") return translator.tr("general.done")
                                if (s === "failed")   return translator.tr("general.error") + (model.error ? ": " + model.error : "")
                                return s
                            }
                            fontSize: "x-small"
                            color: model.status === "failed"
                                   ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.danger : "#C0392B")
                                   : (root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368")
                        }
                    }
                }

                // ---- Actions ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(1)

                    Item { Layout.fillWidth: true }

                    Button {
                        text: translator.tr("general.decline")
                        visible: serverController.incoming_phase === "waiting"
                        onClicked: serverController.decline_incoming()
                    }

                    Button {
                        text: translator.tr("general.accept")
                        color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
                        visible: serverController.incoming_phase === "waiting"
                        onClicked: serverController.accept_incoming()
                    }

                    Button {
                        text: translator.tr("general.close")
                        visible: serverController.incoming_phase === "done"
                        onClicked: serverController.dismiss_incoming()
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
