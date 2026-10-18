import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

Dialog {
    id: root
    property var appTheme
    property string currentPath: ""
    property var entries: []

    signal folderSelected(string path)
    signal canceled()

    function loadPath(dirPath) {
        root.currentPath = dirPath || ""
        try {
            var json = sendController.list_directory(root.currentPath)
            root.entries = JSON.parse(json)
        } catch (e) {
            console.warn("[FolderPicker] error reading directory:", e)
            root.entries = []
        }
    }

    function goUp() {
        if (!root.currentPath || root.currentPath === "/" || root.currentPath === "/home/phablet") {
            return
        }
        var parts = root.currentPath.split("/")
        parts.pop()
        var parentPath = parts.join("/")
        if (parentPath.length === 0) parentPath = "/"
        root.loadPath(parentPath)
    }

    Component.onCompleted: {
        root.loadPath("")
    }

    title: qsTr("Select Folder")
    modal: true
    anchors.centerIn: parent
    width: Math.min(parent.width - units.gu(4), units.gu(65))
    height: Math.min(parent.height - units.gu(6), units.gu(75))

    contentItem: ColumnLayout {
        anchors.margins: units.gu(1.5)
        spacing: units.gu(1)

        // Path header + Up button
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                text: "↑ .."
                onClicked: root.goUp()
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: units.gu(4.5)
                radius: units.gu(0.5)
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTint : "#ECEFF1"

                Label {
                    anchors { fill: parent; leftMargin: units.gu(1); rightMargin: units.gu(1) }
                    verticalAlignment: Text.AlignVCenter
                    text: root.currentPath.length > 0 ? root.currentPath : "/home/phablet"
                    elide: Text.ElideMiddle
                    font.family: "monospace"
                    fontSize: "x-small"
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                }
            }
        }

        // Quick Shortcuts Row
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: units.gu(4)
            contentWidth: shortcutsRow.width
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            Row {
                id: shortcutsRow
                spacing: units.gu(0.8)

                Repeater {
                    model: ["Documents", "Downloads", "Music", "Pictures", "Videos"]
                    delegate: Button {
                        text: modelData
                        onClicked: {
                            var p = (root.currentPath.indexOf("/home/") === 0
                                ? root.currentPath.split("/").slice(0, 3).join("/")
                                : "/home/phablet") + "/" + modelData
                            root.loadPath(p)
                        }
                    }
                }
            }
        }

        // Directory list
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: units.gu(0.5)
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surface : "#ffffff"
            border.color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.divider : "#e0e0e0"
            border.width: units.dp(1)
            clip: true

            ListView {
                id: dirList
                anchors.fill: parent
                model: root.entries

                delegate: Rectangle {
                    width: dirList.width
                    height: units.gu(6)
                    color: itemArea.pressed ? (root.appTheme ? root.appTheme.colors.surfaceTint : "#ECEFF1") : "transparent"

                    RowLayout {
                        anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                        spacing: units.gu(1.5)

                        Icon {
                            width: units.gu(2.8)
                            height: units.gu(2.8)
                            name: modelData.is_dir ? "folder" : "text-x-generic"
                            color: modelData.is_dir
                                ? (root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C")
                                : "#888888"
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            fontSize: "small"
                            font.bold: modelData.is_dir
                            elide: Text.ElideRight
                            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                        }

                        Label {
                            visible: !modelData.is_dir
                            text: {
                                var sz = modelData.size || 0
                                if (sz < 1024) return sz + " B"
                                if (sz < 1024 * 1024) return (sz / 1024).toFixed(1) + " KB"
                                return (sz / (1024 * 1024)).toFixed(1) + " MB"
                            }
                            fontSize: "x-small"
                            color: "#888888"
                        }
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.is_dir) {
                                root.loadPath(modelData.path)
                            }
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: root.entries.length === 0
                    text: qsTr("No subfolders found")
                    fontSize: "small"
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#888888"
                }
            }
        }

        // Bottom Action Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                Layout.fillWidth: true
                text: qsTr("Cancel")
                onClicked: {
                    root.canceled()
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                text: qsTr("Select This Folder")
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
                onClicked: {
                    root.folderSelected(root.currentPath)
                    root.close()
                }
            }
        }
    }
}
