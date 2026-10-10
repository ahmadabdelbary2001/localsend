import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3
import Lomiri.Content 1.3

Rectangle {
    id: root
    property var theme

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.5)
    z: 100

    // ---- Content Hub ----
    ContentHub {
        id: contentHub
    }

    Component {
        id: contentItemFactory
        ContentItem {}
    }

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
                    var p = serverController.incoming_phase
                    if (p === "waiting")   return "Incoming transfer"
                    if (p === "receiving") return "Receiving…"
                    return "Transfer finished"
                }
                fontSize: "large"
                color: theme ? theme.colors.onSurface : "#1B1D21"
            }

            Label {
                Layout.fillWidth: true
                text: serverController.incoming_sender
                      + " · "
                      + serverController.incoming_file_count
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

                    RowLayout {
                        anchors.fill: parent
                        spacing: units.gu(1)

                        ColumnLayout {
                            Layout.fillWidth: true
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

                        // ---- Share button ----
                        Button {
                            visible: model.status === "finished"
                                     && model.path.length > 0
                            text: "Share"
                            onClicked: root.shareFile(model.path, model.fileName)
                        }
                    }
                }
            }

            // ---- Actions ----
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)

                // Share all — visible when at least one file is finished
                Button {
                    visible: serverController.incoming_phase === "done"
                             && _finishedCount() > 0
                    text: "Share all"
                    color: theme ? theme.colors.primary : "#00695C"
                    onClicked: root.shareAllFinished()
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Decline"
                    visible: serverController.incoming_phase === "waiting"
                    onClicked: serverController.decline_incoming()
                }

                Button {
                    text: "Accept"
                    color: theme ? theme.colors.primary : "#00695C"
                    visible: serverController.incoming_phase === "waiting"
                    onClicked: serverController.accept_incoming()
                }

                Button {
                    text: "Close"
                    visible: serverController.incoming_phase === "done"
                    onClicked: serverController.dismiss_incoming()
                }
            }
        }
    }

    // ---- helpers ----

    function _humanSize(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
        if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " MB"
        return (bytes / 1024 / 1024 / 1024).toFixed(2) + " GB"
    }

    function _contentTypeFor(fileName) {
        var i = fileName.lastIndexOf(".")
        if (i < 0) return ContentType.Documents
        var ext = fileName.substring(i + 1).toLowerCase()
        if (["jpg","jpeg","png","gif","webp","bmp","heic","heif"].indexOf(ext) >= 0)
            return ContentType.Pictures
        if (["mp4","mov","mkv","avi","webm","m4v"].indexOf(ext) >= 0)
            return ContentType.Videos
        if (["mp3","wav","flac","ogg","m4a","aac","opus"].indexOf(ext) >= 0)
            return ContentType.Music
        if (["vcf","vcard"].indexOf(ext) >= 0)
            return ContentType.Contacts
        if (["txt","pdf","doc","docx","odt","rtf","md","epub"].indexOf(ext) >= 0)
            return ContentType.Documents
        return ContentType.Documents
    }

    function shareFile(path, fileName) {
        if (!path || path.length === 0) return
        var item = contentItemFactory.createObject(root, {
            "source": "file://" + path,
            "contentType": _contentTypeFor(fileName)
        })
        if (item) contentHub.export([item])
    }

    function shareAllFinished() {
        var items = []
        var n = incomingFilesModel.rowCount()
        for (var i = 0; i < n; i++) {
            var idx = incomingFilesModel.index(i, 0)
            var status = incomingFilesModel.data(idx, 3)
            var path = incomingFilesModel.data(idx, 4)
            var name = incomingFilesModel.data(idx, 0)
            if (status === "finished" && path && path.length > 0) {
                var item = contentItemFactory.createObject(root, {
                    "source": "file://" + path,
                    "contentType": _contentTypeFor(name)
                })
                if (item) items.push(item)
            }
        }
        if (items.length > 0) {
            contentHub.export(items)
        }
    }

    function _finishedCount() {
        var n = incomingFilesModel.rowCount()
        var c = 0
        for (var i = 0; i < n; i++) {
            var idx = incomingFilesModel.index(i, 0)
            if (incomingFilesModel.data(idx, 3) === "finished") c++
        }
        return c
    }
}