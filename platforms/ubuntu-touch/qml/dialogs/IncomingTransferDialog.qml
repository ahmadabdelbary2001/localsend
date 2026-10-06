import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Rectangle {
    id: root
    property var theme

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.5)
    z: 100

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - units.gu(4), units.gu(60))
        height: Math.min(parent.height - units.gu(8), units.gu(75))
        radius: theme ? theme.metrics.cardRadius : units.gu(0.6)
        color: theme ? theme.colors.surface : "#ffffff"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: units.gu(2)
            spacing: units.gu(1.5)

            // ---- Header ----
            Label {
                Layout.fillWidth: true
                text: {
                    var p = serverController.incomingPhase
                    if (p === "waiting")   return "Incoming transfer"
                    if (p === "receiving") return "Receiving…"
                    return "Transfer finished"
                }
                fontSize: "large"
                color: theme ? theme.colors.onSurface : "#1B1D21"
            }

            Label {
                Layout.fillWidth: true
                text: serverController.incomingSender
                      + " · "
                      + serverController.incomingFileCount
                      + " file(s)"
                fontSize: "small"
                opacity: 0.7
                color: theme ? theme.colors.onSurfaceMuted : "#5F6368"
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

                delegate: Rectangle {
                    width: fileList.width
                    height: units.gu(8)
                    color: "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: units.gu(0.2)

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: model.fileName
                                fontSize: "small"
                                elide: Text.ElideRight
                                color: theme ? theme.colors.onSurface : "#1B1D21"
                            }
                            Label {
                                text: _humanSize(model.size)
                                fontSize: "x-small"
                                opacity: 0.6
                                color: theme ? theme.colors.onSurfaceMuted : "#5F6368"
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: units.dp(4)
                            radius: units.dp(2)
                            color: theme ? theme.colors.surfaceTint : "#ECEFF1"
                            visible: model.status === "sending"
                                     || model.status === "finished"
                                     || model.status === "failed"

                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, model.progress))
                                height: parent.height
                                radius: parent.radius
                                color: model.status === "failed"
                                       ? (theme ? theme.colors.danger : "#C0392B")
                                       : (theme ? theme.colors.primary : "#00695C")
                            }
                        }

                        Label {
                            text: {
                                var s = model.status
                                if (s === "queue")    return "Waiting…"
                                if (s === "sending")  return Math.round(model.progress * 100) + "%"
                                if (s === "finished") return "Saved"
                                if (s === "failed")   return "Failed" + (model.error ? ": " + model.error : "")
                                return s
                            }
                            fontSize: "x-small"
                            color: model.status === "failed"
                                   ? (theme ? theme.colors.danger : "#C0392B")
                                   : (theme ? theme.colors.onSurfaceMuted : "#5F6368")
                        }
                    }
                }
            }

            // ---- Actions ----
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight
                spacing: units.gu(1)

                Button {
                    text: "Decline"
                    visible: serverController.incomingPhase === "waiting"
                    onClicked: serverController.decline_incoming()
                }

                Button {
                    text: "Accept"
                    color: theme ? theme.colors.primary : "#00695C"
                    visible: serverController.incomingPhase === "waiting"
                    onClicked: serverController.accept_incoming()
                }

                Button {
                    text: "Close"
                    visible: serverController.incomingPhase === "done"
                    onClicked: serverController.dismiss_incoming()
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