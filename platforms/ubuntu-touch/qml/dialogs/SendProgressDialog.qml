import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Rectangle {
    id: root
    property var theme
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.5)
    z: 101

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - units.gu(4), units.gu(60))
        height: Math.min(parent.height - units.gu(8), units.gu(75))
        radius: theme ? theme.metrics.cardRadius : units.gu(0.6)
        color: theme ? theme.colors.surface : "#ffffff"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: units.gu(2)
            spacing: units.gu(1.5)

            Label {
                Layout.fillWidth: true
                text: sendController.done
                      ? (sendController.failed_count > 0 ? "Send finished with errors" : "Send finished")
                      : "Sending…"
                fontSize: "large"
                color: theme ? theme.colors.onSurface : "#1B1D21"
            }

            Label {
                Layout.fillWidth: true
                text: sendController.target_alias + " · " + sendController.finished_count + " / " + sendController.total_count
                fontSize: "small"
                opacity: 0.7
                color: theme ? theme.colors.onSurfaceMuted : "#5F6368"
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: outgoingFilesModel
                delegate: ColumnLayout {
                    width: list.width
                    spacing: units.gu(0.2)
                    RowLayout {
                        Layout.fillWidth: true
                        Label { Layout.fillWidth: true; text: model.fileName; fontSize: "small"; elide: Text.ElideRight }
                        Label { text: Math.round(model.progress * 100) + "%"; fontSize: "x-small"; opacity: 0.6 }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: units.dp(4)
                        radius: units.dp(2)
                        color: theme ? theme.colors.surfaceTint : "#ECEFF1"
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, model.progress))
                            height: parent.height
                            radius: parent.radius
                            color: model.status === "failed"
                                   ? (theme ? theme.colors.danger : "#C0392B")
                                   : (theme ? theme.colors.primary : "#00695C")
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    text: "Cancel"
                    visible: !sendController.done
                    onClicked: sendController.cancel()
                }
                Button {
                    text: "Close"
                    visible: sendController.done
                    color: theme ? theme.colors.primary : "#00695C"
                    onClicked: sendController.dismiss()
                }
            }
        }
    }
}