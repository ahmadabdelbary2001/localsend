import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../components"

// Folder browser shared by the "save to folder" setting and the send tab.
//
// mode = "receive": pick the folder incoming files are saved in. Folders the
//                   confined app cannot write to are rejected up front.
// mode = "send":    pick a folder whose files are sent.
Dialog {
    id: root
    property var appTheme
    property string mode: "receive"

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
    property var shortcuts: []
    property bool creatingFolder: false

    readonly property string homePath: sendController.home_directory()
    readonly property bool receiveMode: root.mode === "receive"
    readonly property string effectivePath: root.currentPath.length > 0 ? root.currentPath : root.homePath
    readonly property bool atRoot: root.effectivePath === "/"

    // In receive mode the folder must accept writes: the server silently falls
    // back to ~/Downloads/LocalSend otherwise, and the user would look for the
    // received files in the wrong place.
    readonly property bool canUseFolder: root.effectivePath.length > 1
                                        && (!root.receiveMode
                                            || settingsController.is_directory_writable(root.effectivePath))

    signal folderSelected(string path)
    signal canceled()

    function loadPath(dirPath) {
        var path = (dirPath && dirPath.length > 0) ? dirPath : root.homePath
        if (path.length > 1 && path.charAt(path.length - 1) === "/")
            path = path.substring(0, path.length - 1)
        root.currentPath = path
        try {
            var parsed = JSON.parse(sendController.list_directory(path))
            // A folder picker only offers folders.
            root.entries = parsed.filter(function(entry) { return entry.is_dir })
        } catch (e) {
            console.warn("[FolderPicker] error reading directory:", e)
            root.entries = []
        }
        dirList.positionViewAtBeginning()
    }

    function refreshShortcuts() {
        var names = ["Downloads", "Documents", "Pictures", "Music", "Videos"]
        var found = []
        for (var i = 0; i < names.length; i++) {
            if (sendController.directory_exists(root.homePath + "/" + names[i]))
                found.push(names[i])
        }
        root.shortcuts = found
    }

    function goUp() {
        if (root.atRoot)
            return
        var parts = root.effectivePath.split("/")
        parts.pop()
        var parentPath = parts.join("/")
        if (parentPath.length === 0) parentPath = "/"
        root.loadPath(parentPath)
    }

    function createFolder() {
        var name = newFolderField.text.trim()
        if (name.length === 0) return
        var created = sendController.create_directory(root.effectivePath + "/" + name)
        if (created.length === 0) {
            createError.text = translator.tr("folderPicker.notWritable")
            return
        }
        newFolderField.text = ""
        root.creatingFolder = false
        root.loadPath(created)
    }

    // Reload every time the dialog opens: callers may set `currentPath`
    // before calling open() (e.g. the receive destination setting).
    onOpened: {
        root.creatingFolder = false
        root.refreshShortcuts()
        root.loadPath(root.currentPath)
    }

    title: root.receiveMode
           ? translator.tr("settingsTab.receive.destination")
           : translator.tr("folderPicker.title")
    modal: true
    // Instantiated through a Loader, so the declared parent (the
    // zero-sized Loader item) cannot be used for centering.
    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width - units.gu(4), units.gu(65))
    height: Math.min(parent.height - units.gu(6), units.gu(75))
    padding: units.gu(1.2)

    contentItem: ColumnLayout {

        // Popups live in the window overlay, outside the mirrored MainView
        // tree, so right-to-left layout has to be re-enabled on the content.
        LayoutMirroring.enabled: translator.rtl
        LayoutMirroring.childrenInherit: true
        spacing: units.gu(1)

        // Current path + up navigation
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            AbstractButton {
                Layout.preferredWidth: units.gu(5)
                Layout.preferredHeight: units.gu(5)
                enabled: !root.atRoot
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.goUp()

                Rectangle {
                    anchors.fill: parent
                    radius: units.gu(0.5)
                    color: root.appTheme && root.appTheme.colors
                           ? root.appTheme.colors.surfaceTint : "#ECEFF1"
                }

                Icon {
                    anchors.centerIn: parent
                    width: units.gu(2.6)
                    height: width
                    name: "go-up"
                    color: root.appTheme && root.appTheme.colors
                           ? root.appTheme.colors.surfaceText : "#1B1D21"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: units.gu(5)
                radius: units.gu(0.5)
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTint : "#ECEFF1"

                Label {
                    anchors { fill: parent; leftMargin: units.gu(1); rightMargin: units.gu(1) }
                    verticalAlignment: Text.AlignVCenter
                    text: root.effectivePath
                    elide: Text.ElideMiddle
                    font.family: "monospace"
                    fontSize: "x-small"
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                }
            }
        }

        // Quick shortcuts (only folders that exist on this device)
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? units.gu(4.5) : 0
            visible: root.shortcuts.length > 0
            contentWidth: shortcutsRow.width
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            Row {
                id: shortcutsRow
                spacing: units.gu(0.8)

                Repeater {
                    model: root.shortcuts
                    delegate: Button {
                        text: modelData
                        onClicked: root.loadPath(root.homePath + "/" + modelData)
                    }
                }
            }
        }

        // Folder list
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
                    height: units.gu(5.5)
                    color: itemArea.pressed ? (root.appTheme ? root.appTheme.colors.surfaceTint : "#ECEFF1") : "transparent"

                    RowLayout {
                        anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1) }
                        spacing: units.gu(1.5)

                        Icon {
                            width: units.gu(2.8)
                            height: units.gu(2.8)
                            name: "folder-symbolic"
                            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            fontSize: "small"
                            elide: Text.ElideMiddle
                            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceText : "#1B1D21"
                        }

                        Icon {
                            width: units.gu(2)
                            height: width
                            // Drill-in chevron: icons are not mirrored
                            // automatically, so pick the direction here.
                            name: translator.rtl ? "go-previous" : "go-next"
                            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#888888"
                        }
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        onClicked: root.loadPath(modelData.path)
                    }
                }

                Label {
                    anchors.centerIn: parent
                    width: parent.width - units.gu(4)
                    visible: root.entries.length === 0
                    text: translator.tr("assetPicker.emptyList")
                    fontSize: "small"
                    horizontalAlignment: Text.AlignHCenter
                    color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.surfaceTextMuted : "#888888"
                }
            }
        }

        // New folder
        ColumnLayout {
            Layout.fillWidth: true
            spacing: units.gu(0.6)
            visible: root.creatingFolder

            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)

                TextField {
                    id: newFolderField
                    Layout.fillWidth: true
                    placeholderText: translator.tr("folderPicker.folderName")
                    onAccepted: root.createFolder()
                }

                Button {
                    text: translator.tr("folderPicker.create")
                    enabled: newFolderField.text.trim().length > 0
                    onClicked: root.createFolder()
                }
            }

            Label {
                id: createError
                Layout.fillWidth: true
                text: ""
                visible: text.length > 0
                fontSize: "x-small"
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.danger : "#C0392B"
            }
        }

        // Receive mode: explain why a folder can not be used.
        Label {
            Layout.fillWidth: true
            visible: root.receiveMode && !root.canUseFolder
            text: translator.tr("folderPicker.notWritable")
            fontSize: "x-small"
            wrapMode: Text.Wrap
            color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.danger : "#C0392B"
        }

        // Actions
        RowLayout {
            Layout.fillWidth: true
            spacing: units.gu(1)

            Button {
                Layout.fillWidth: true
                text: root.creatingFolder
                      ? translator.tr("general.cancel")
                      : translator.tr("folderPicker.newFolder")
                onClicked: {
                    if (root.creatingFolder) {
                        root.creatingFolder = false
                        createError.text = ""
                    } else {
                        root.creatingFolder = true
                        newFolderField.text = ""
                        newFolderField.forceActiveFocus()
                    }
                }
            }

            Button {
                Layout.fillWidth: true
                text: translator.tr("general.cancel")
                visible: !root.creatingFolder
                onClicked: {
                    root.canceled()
                    root.close()
                }
            }

            Button {
                Layout.fillWidth: true
                visible: !root.creatingFolder
                text: translator.tr("folderPicker.useThisFolder")
                enabled: root.canUseFolder
                color: root.appTheme && root.appTheme.colors ? root.appTheme.colors.primary : "#00695C"
                onClicked: {
                    root.folderSelected(root.effectivePath)
                    root.close()
                }
            }
        }
    }
}
