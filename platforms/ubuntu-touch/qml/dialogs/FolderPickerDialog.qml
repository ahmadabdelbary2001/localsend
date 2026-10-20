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
    property string currentPath: ""
    property var entries: []

    readonly property string homePath: sendController.home_directory()

    signal folderSelected(string path)
    signal canceled()

    function loadPath(dirPath) {
        var path = (dirPath && dirPath.length > 0) ? dirPath : root.homePath
        if (path.length > 1 && path.charAt(path.length - 1) === "/")
            path = path.substring(0, path.length - 1)
        root.currentPath = path
        try {
            var json = sendController.list_directory(path)
            root.entries = JSON.parse(json)
        } catch (e) {
            console.warn("[FolderPicker] error reading directory:", e)
            root.entries = []
        }
    }

    function goUp() {
        if (!root.currentPath || root.currentPath === "/")
            return
        var parts = root.currentPath.split("/")
        parts.pop()
        var parentPath = parts.join("/")
        if (parentPath.length === 0) parentPath = "/"
        root.loadPath(parentPath)
    }

    // Reload every time the dialog opens: callers may set `currentPath`
    // before calling open() (e.g. the receive destination setting).
    onOpened: root.loadPath(root.currentPath)

    title: translator.tr("settingsTab.receive.destination")
    modal: true
    // Instantiated through a Loader, so the declared parent (the
    // zero-sized Loader item) cannot be used for centering.
    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
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
                    text: root.currentPath.length > 0 ? root.currentPath : root.homePath
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
                        onClicked: root.loadPath(root.homePath + "/" + modelData)
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
                            name: modelData.is_dir
                                      ? "folder-symbolic"
                                      : (/\.(click|deb|apk|snap|appimage|flatpak|flatpakref|run)$/i.test(modelData.name)
                                         ? "package-x-generic-symbolic"
                                         : "text-x-generic-symbolic")
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
                    text: translator.tr("assetPicker.emptyList")
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
                text: translator.tr("general.cancel")
                onClicked: {
                    root.canceled()
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                text: translator.tr("assetPicker.select")
                enabled: root.currentPath.length > 0
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
                onClicked: {
                    root.folderSelected(root.currentPath)
                    root.close()
                }
            }
        }
    }
}
