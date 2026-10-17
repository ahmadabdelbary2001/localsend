import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

Rectangle {
    id: root
    property var appTheme

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)
    z: 101

    readonly property int total: sendController.total_count
    readonly property int done: sendController.finished_count
    readonly property int failed: sendController.failed_count
    readonly property real overall: total > 0
        ? Math.min(1.0, (done + failed) / total)
        : 0.0

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
                    var st = sendController.status
                    if (st === "finished")           return qsTr("Send finished")
                    if (st === "finishedWithErrors") return qsTr("Send finished with errors")
                    if (st === "cancelled")          return qsTr("Cancelled")
                    if (st === "pinRequired")        return qsTr("Waiting for PIN…")
                    if (st === "declined")           return qsTr("Receiver declined")
                    if (st === "recipientBusy")      return qsTr("Receiver is busy")
                    if (st === "tooManyAttempts")    return qsTr("Too many attempts")
                    if (st === "canceledBySender")   return qsTr("Canceled")
                    if (st === "sending")            return qsTr("Sending…")
                    return root.failed > 0
                        ? qsTr("Send finished with errors")
                        : qsTr("Sending…")
                }
                fontSize: "large"
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
            }

            Label {
                Layout.fillWidth: true
                text: sendController.target_alias
                      + " · "
                      + root.done + " / " + root.total
                      + (root.failed > 0 ? "  (" + root.failed + " ✗)" : "")
                fontSize: "small"
                opacity: 0.7
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368"
                elide: Text.ElideRight
            }

            // ---- Overall progress ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: units.dp(6)
                radius: units.dp(3)
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTint : "#ECEFF1"

                Rectangle {
                    width: parent.width * root.overall
                    height: parent.height
                    radius: parent.radius
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
                    Behavior on width { NumberAnimation { duration: 150 } }
                }
            }

            // ---- Per-file list ----
            ListView {
                id: fileList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: units.gu(1)
                model: outgoingFilesModel

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
                        Icon {
                            Layout.preferredWidth: units.gu(2)
                            Layout.preferredHeight: units.gu(2)
                            name: model.status === "finished" ? "check"
                                : model.status === "failed"   ? "close"
                                : model.status === "sending"  ? "sync"
                                : "stock_website"
                            color: model.status === "finished"
                                ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C")
                                : model.status === "failed"
                                    ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.danger : "#C0392B")
                                    : (root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#888")
                        }
                            text: _statusText(model.status, model.progress)
                            fontSize: "x-small"
                            color: model.status === "failed"
                                   ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.danger : "#C0392B")
                                   : (root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#5F6368")
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
                        Layout.fillWidth: true
                        visible: model.status === "failed" && model.error.length > 0
                        text: model.error
                        fontSize: "x-small"
                        color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.danger : "#C0392B"
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- Error summary ----
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)
                visible: sendController.status === "finishedWithErrors"
                         && sendController.error_message.length > 0

                Label {
                    Layout.fillWidth: true
                    text: sendController.error_message
                    fontSize: "x-small"
                    wrapMode: Text.Wrap
                    color: root.appTheme && root.appTheme.colors
                        ? root.appTheme.colors.danger
                        : "#C0392B"
                }

                Button {
                    text: qsTr("Details")
                    onClicked: errorDetailsDialog.open()
                }
            }


            // ---- Actions ----
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)

                Item { Layout.fillWidth: true }

                Button {
                    text: qsTr("Cancel")
                    visible: !sendController.done
                    onClicked: sendController.cancel()
                }

                Button {
                    text: qsTr("Close")
                    visible: sendController.done
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
                    onClicked: sendController.dismiss()
                }
            }
        }
    }

    PinDialog {
        id: pinDialog
        appTheme: root.appTheme
        showInvalidPin: sendController.pin_invalid

        onSubmitted: function(pin) {
            sendController.submit_pin(pin)
        }
        onCanceled: {
            sendController.cancel()
        }
    }

    Connections {
        target: sendController

        function onStateChanged() {
            if (sendController.status === "pinRequired" && !pinDialog.visible) {
                pinDialog.open()
            } else if (sendController.status !== "pinRequired" && pinDialog.visible) {
                pinDialog.close()
            }
        }
    }

    Dialog {
        id: errorDetailsDialog
        title: qsTr("Send errors")
        modal: true
        anchors.centerIn: parent
        width: Math.min(parent.width - units.gu(4), units.gu(60))

        contentItem: ColumnLayout {
            spacing: units.gu(1)

            Label {
                Layout.fillWidth: true
                text: sendController.error_message
                wrapMode: Text.Wrap
                fontSize: "small"
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
            }

            Button {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Close")
                onClicked: errorDetailsDialog.close()
            }
        }
    }


    function _statusText(status, progress) {
        if (status === "queue")    return qsTr("Waiting…")
        if (status === "sending")  return Math.round(progress * 100) + "%"
        if (status === "finished") return qsTr("Done")
        if (status === "failed")   return qsTr("Failed")
        return status
    }
}
