import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

import "../components"
import "../dialogs" as LocalSendDialogs

Page {
    id: page
    property var appTheme

    // The tab pages live inside the shell, not in the MainView page stack.
    // No header at all: `header: null` would make Lomiri draw its default
    // (empty) page header, so a zero-height item removes it completely and
    // the content starts at the very top of the window.
    header: Item { height: 0 }
    property string pendingFingerprint: ""
    property var pendingAddress: null // { ip: "", port: 53317, https: true }
    property var selectedPaths: []
    property string pickerType: "all" // "all" | "pictures"
    property string lastError: ""

    // Favorites are shown in their own section above the nearby devices.
    property bool showFavorites: true

    // Local addresses of this device. The Android app shows them next to the
    // scan button, they are the addresses a peer can be reached at.
    readonly property string localIps: {
        var ips = []
        try {
            for (var i = 0; i < localIpsModel.rowCount(); i++) {
                var idx = localIpsModel.index(i, 0)
                var ip = localIpsModel.data(idx, 0)
                if (ip && ip.length > 0)
                    ips.push(ip)
            }
        } catch (e) {
            console.warn("[SendPage] cannot read local addresses:", e)
        }
        return ips.join("  ·  ")
    }

    // Devices that are currently visible in the discovery list. The bridge
    // exposes the snapshot as JSON, so the favorites list can look up the
    // live model / type / address of a peer (QML cannot query the list model
    // by fingerprint).
    readonly property var devices: {
        try {
            return JSON.parse(discoveryController.devices_json)
        } catch (e) {
            return []
        }
    }

    // Live information about a device, or null when it is not visible
    // (an offline favorite for example).
    function deviceInfo(fingerprint) {
        var list = page.devices
        for (var i = 0; i < list.length; i++) {
            if (list[i].fingerprint === fingerprint)
                return list[i]
        }
        return null
    }

    // Live summary of the current selection (count / total size / names).
    // Re-evaluates whenever selectedPaths changes.
    readonly property var selection: {
        if (page.selectedPaths.length === 0)
            return { count: 0, size: 0, names: [], missing: 0 }
        try {
            return JSON.parse(sendController.selection_info(JSON.stringify(page.selectedPaths)))
        } catch (e) {
            return { count: page.selectedPaths.length, size: 0, names: [], missing: 0 }
        }
    }

    // One row per selected file: name, size, image thumbnail or extension
    // badge. Same re-evaluation trigger as `selection`.
    readonly property var selectionItems: {
        if (page.selectedPaths.length === 0)
            return []
        try {
            return JSON.parse(sendController.selection_items(JSON.stringify(page.selectedPaths)))
        } catch (e) {
            return []
        }
    }

    // selectedPaths holds plain paths and, for folder sends, { path, name }
    // objects (see collect_directory_files), so removal has to normalize.
    function pathOf(entry) {
        if (typeof entry === "string")
            return entry
        return entry && entry.path ? entry.path : ""
    }

    function removeSelection(path) {
        page.selectedPaths = page.selectedPaths.filter(function(entry) {
            return page.pathOf(entry) !== path
        })
    }

    // Called when another application shares files to LocalSend through
    // Content Hub. Paths have already been copied into app-private storage.
    function importFiles(paths) {
        if (!paths || paths.length === 0)
            return
        var additions = []
        for (var i = 0; i < paths.length; i++) {
            var path = paths[i]
            if (!path || path.charAt(0) !== "/")
                continue
            var alreadySelected = false
            for (var j = 0; j < page.selectedPaths.length; j++) {
                if (page.pathOf(page.selectedPaths[j]) === path) {
                    alreadySelected = true
                    break
                }
            }
            for (var k = 0; k < additions.length; k++) {
                if (additions[k] === path)
                    alreadySelected = true
            }
            if (!alreadySelected)
                additions.push(path)
        }
        if (additions.length === 0)
            return
        page.pendingFingerprint = ""
        page.pendingAddress = null
        page.selectedPaths = page.selectedPaths.concat(additions)
        homeController.change_tab(1)
        page.showToast(translator.tr_args("contentHub.importReady", JSON.stringify({ n: additions.length })))
    }

    function _formatSize(bytes) {
        var b = bytes || 0
        if (b < 1024) return b + " B"
        if (b < 1024 * 1024) return (b / 1024).toFixed(1) + " KB"
        if (b < 1024 * 1024 * 1024) return (b / 1024 / 1024).toFixed(1) + " MB"
        return (b / 1024 / 1024 / 1024).toFixed(2) + " GB"
    }

    function sendToDevice(fingerprint) {
        if (sendController.active) return

        if (page.selectedPaths.length === 0) {
            page.pendingFingerprint = fingerprint
            page.pendingAddress = null
            page.pickerType = "all"
            pickerLoader.active = true
            return
        }

        sendController.send_files(
            fingerprint,
            JSON.stringify(page.selectedPaths)
        )
        page.selectedPaths = []
    }

    function sendTextToDevice(fingerprint) {
        if (sendController.active) return
        page.pendingFingerprint = fingerprint
        page.pendingAddress = null
        messageDialogLoader.active = true
    }

    function sendToAddress(ip, port, https) {
        if (sendController.active) return

        if (page.selectedPaths.length === 0) {
            page.pendingFingerprint = ""
            page.pendingAddress = { ip: ip, port: port, https: https }
            page.pickerType = "all"
            pickerLoader.active = true
            return
        }

        sendController.send_to_address(
            ip,
            port,
            https,
            ip,
            JSON.stringify(page.selectedPaths)
        )
        page.selectedPaths = []
    }

    function pasteFromClipboard() {
        var text = ""
        try {
            if (typeof Clipboard !== "undefined" && Clipboard.text) {
                text = Clipboard.text.trim()
            }
        } catch (e) {
            console.warn("[SendPage] clipboard read error:", e)
        }

        if (!text || text.length === 0) {
            page.showToast(translator.tr("general.noItemInClipboard"))
            return
        }

        var path = sendController.create_text_file(text)
        if (path.length > 0) {
            if (page.pendingFingerprint.length > 0) {
                sendController.send_files(page.pendingFingerprint, JSON.stringify([path]))
                page.pendingFingerprint = ""
            } else if (page.pendingAddress) {
                sendController.send_to_address(
                    page.pendingAddress.ip,
                    page.pendingAddress.port,
                    page.pendingAddress.https,
                    page.pendingAddress.ip,
                    JSON.stringify([path])
                )
                page.pendingAddress = null
            } else {
                page.selectedPaths = page.selectedPaths.concat([path])
                page.showToast(translator.tr("sendTab.picker.clipboard"))
            }
        }
    }

    function addFolder(folderPath) {
        if (!folderPath || folderPath.length === 0) return
        try {
            var filesJson = sendController.collect_directory_files(folderPath)
            var files = JSON.parse(filesJson)
            if (!files || files.length === 0) {
                page.showToast(translator.tr("dialogs.noFiles.title"))
                return
            }

            if (page.pendingFingerprint.length > 0) {
                sendController.send_files(page.pendingFingerprint, JSON.stringify(files))
                page.pendingFingerprint = ""
            } else if (page.pendingAddress) {
                sendController.send_to_address(
                    page.pendingAddress.ip,
                    page.pendingAddress.port,
                    page.pendingAddress.https,
                    page.pendingAddress.ip,
                    JSON.stringify(files)
                )
                page.pendingAddress = null
            } else {
                page.selectedPaths = page.selectedPaths.concat(files)
                page.showToast(files.length + " " + translator.tr("general.files"))
            }
        } catch (e) {
            console.warn("[SendPage] error adding folder:", e)
        }
    }

    function addApp(appPath) {
        if (!appPath || appPath.length === 0) return
        if (page.pendingFingerprint.length > 0) {
            sendController.send_files(page.pendingFingerprint, JSON.stringify([appPath]))
            page.pendingFingerprint = ""
        } else if (page.pendingAddress) {
            sendController.send_to_address(
                page.pendingAddress.ip,
                page.pendingAddress.port,
                page.pendingAddress.https,
                page.pendingAddress.ip,
                JSON.stringify([appPath])
            )
            page.pendingAddress = null
        } else {
            page.selectedPaths = page.selectedPaths.concat([appPath])
            page.showToast(translator.tr("dialogs.addFile.title"))
        }
    }

    function showToast(message) {
        toastLabel.text = message
        toastBanner.visible = true
        toastTimer.restart()
    }

    Connections {
        target: sendController
        function onState_changed() {
            var message = sendController.error_message
            if (!message || message.length === 0) {
                page.lastError = ""
                return
            }
            if (message !== page.lastError) {
                page.lastError = message
                page.showToast(message)
            }
        }
    }

    // ---------- File Picker Loader ----------
    Loader {
        id: pickerLoader
        anchors.fill: parent
        z: 150
        active: false
        source: "../pickers/ContentHubPicker.qml"

        onLoaded: {
            item.filesPicked.connect(function(paths) {
                // ContentHubPicker staged files before finalizing the transfer.
                var stagedPaths = paths || []
                if (stagedPaths.length > 0) {
                    page.selectedPaths = page.selectedPaths.concat(stagedPaths)
                }

                if (page.pendingFingerprint.length > 0 && page.selectedPaths.length > 0) {
                    sendController.send_files(
                        page.pendingFingerprint,
                        JSON.stringify(page.selectedPaths)
                    )
                    page.selectedPaths = []
                } else if (page.pendingAddress && page.selectedPaths.length > 0) {
                    sendController.send_to_address(
                        page.pendingAddress.ip,
                        page.pendingAddress.port,
                        page.pendingAddress.https,
                        page.pendingAddress.ip,
                        JSON.stringify(page.selectedPaths)
                    )
                    page.selectedPaths = []
                }

                page.pendingFingerprint = ""
                page.pendingAddress = null
                pickerLoader.active = false
            })
            item.pickCancelled.connect(function() {
                page.pendingFingerprint = ""
                page.pendingAddress = null
                pickerLoader.active = false
            })
            item.pickFailed.connect(function() {
                page.pendingFingerprint = ""
                page.pendingAddress = null
                page.showToast(translator.tr("contentHub.importFailed"))
                pickerLoader.active = false
            })
            item.open(page.pickerType)
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[SendPage] ContentHubPicker unavailable")
                page.pendingFingerprint = ""
                page.pendingAddress = null
                pickerLoader.active = false
            }
        }
    }

    // ---------- Main Scrollable View ----------
    Flickable {
        id: flickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainCol.y + mainCol.implicitHeight + units.gu(4)
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: mainCol
            x: units.gu(1.5)
            y: units.gu(1.5)
            width: Math.max(0, flickable.width - units.gu(3))
            spacing: units.gu(1.5)

            // ---------- Selection Area (When empty: 6 Big Buttons) ----------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: units.gu(0.8)
                visible: page.selectedPaths.length === 0

                Label {
                    text: translator.tr("sendTab.selection.title")
                    fontSize: "medium"
                    font.bold: true
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: units.gu(1)
                    rowSpacing: units.gu(1)

                    // 1. File (ملف) — Flutter: Icons.description
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "text-x-generic-symbolic"
                        label: translator.tr("sendTab.picker.file")
                        onClicked: {
                            page.pickerType = "all"
                            pickerLoader.active = true
                        }
                    }

                    // 2. Media (وسائط) — Flutter: Icons.image
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "camera-photo-symbolic"
                        label: translator.tr("sendTab.picker.media")
                        onClicked: {
                            page.pickerType = "pictures"
                            pickerLoader.active = true
                        }
                    }

                    // 3. Paste (لصق) — Flutter: Icons.paste
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "edit-paste"
                        label: translator.tr("sendTab.picker.clipboard")
                        onClicked: page.pasteFromClipboard()
                    }

                    // 4. Text (نص) — Flutter: Icons.subject
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "edit"
                        label: translator.tr("sendTab.picker.text")
                        onClicked: {
                            page.pendingFingerprint = ""
                            page.pendingAddress = null
                            messageDialogLoader.active = true
                        }
                    }

                    // 5. Folder (مجلد) — Flutter: Icons.folder
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "folder-symbolic"
                        label: translator.tr("sendTab.picker.folder")
                        onClicked: {
                            folderDialogLoader.active = true
                        }
                    }

                    // 6. App (تطبيق) — Flutter: Icons.apps
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "package-x-generic-symbolic"
                        label: translator.tr("sendTab.picker.app")
                        onClicked: {
                            appDialogLoader.active = true
                        }
                    }
                }
            }

            // ---------- Selected Items Summary (When not empty) ----------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: summaryCol.implicitHeight + units.gu(2.4)
                radius: units.gu(0.8)
                visible: page.selectedPaths.length > 0
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surface : "#ffffff"
                border.color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.divider : "#e0e0e0"
                border.width: units.dp(1)

                ColumnLayout {
                    id: summaryCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: units.gu(1.2)
                    }
                    spacing: units.gu(0.4)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: units.gu(1)

                        Label {
                            Layout.fillWidth: true
                            text: translator.tr("sendTab.selection.title")
                            fontSize: "small"
                            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                        }

                        Label {
                            text: translator.tr_args("sendTab.selection.files",
                                                     JSON.stringify({ files: page.selection.count }))
                            fontSize: "small"
                            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr_args("sendTab.selection.size",
                                                 JSON.stringify({ size: page._formatSize(page.selection.size) }))
                        fontSize: "medium"
                        font.bold: true
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                    }

                    // One row per file: thumbnail (images) or extension badge,
                    // full name, size, and a button that removes just that file.
                    ListView {
                        id: selectionList
                        Layout.fillWidth: true
                        // Row height is fixed (gu(6) + spacing), so the height
                        // is derived from the model instead of contentHeight:
                        // binding to the view's own contentHeight loops through
                        // the page Flickable.
                        Layout.preferredHeight: visible
                                                ? Math.min((page.selectionItems.length * units.gu(6.5)) - units.gu(0.5),
                                                           units.gu(20))
                                                : 0
                        visible: page.selectionItems.length > 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: units.gu(0.5)
                        model: page.selectionItems

                        delegate: Rectangle {
                            width: selectionList.width
                            height: units.gu(6)
                            radius: units.gu(0.5)
                            color: page.appTheme && page.appTheme.colors
                                   ? page.appTheme.colors.surfaceTint : "#ECEFF1"

                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: units.gu(0.8)
                                    rightMargin: units.gu(0.4)
                                    topMargin: units.gu(0.6)
                                    bottomMargin: units.gu(0.6)
                                }
                                spacing: units.gu(1)

                                // Thumbnail for media, file shape with the
                                // extension for everything else.
                                Item {
                                    Layout.preferredWidth: units.gu(4.4)
                                    Layout.preferredHeight: units.gu(4.4)

                                    Image {
                                        anchors.fill: parent
                                        visible: modelData.is_image === true
                                        source: visible ? "file://" + modelData.path : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize.width: units.gu(4.4)
                                        sourceSize.height: units.gu(4.4)
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: modelData.is_image !== true
                                        radius: units.gu(0.4)
                                        color: page.appTheme && page.appTheme.colors
                                               ? page.appTheme.colors.surface : "#ffffff"
                                        border.width: units.dp(1)
                                        border.color: page.appTheme && page.appTheme.colors
                                                      ? page.appTheme.colors.divider : "#e0e0e0"

                                        Label {
                                            anchors {
                                                fill: parent
                                                margins: units.gu(0.3)
                                            }
                                            text: modelData.ext && modelData.ext.length > 0
                                                  ? modelData.ext : "?"
                                            fontSize: "xx-small"
                                            font.bold: true
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: page.appTheme && page.appTheme.colors
                                                   ? page.appTheme.colors.primary : "#00695C"
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        fontSize: "x-small"
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideMiddle
                                        color: page.appTheme && page.appTheme.colors
                                               ? page.appTheme.colors.surfaceText : "#1B1D21"
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: page._formatSize(modelData.size)
                                        fontSize: "xx-small"
                                        color: page.appTheme && page.appTheme.colors
                                               ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                                    }
                                }

                                AbstractButton {
                                    Layout.preferredWidth: units.gu(4.5)
                                    Layout.preferredHeight: units.gu(4.5)
                                    onClicked: page.removeSelection(modelData.path)

                                    Icon {
                                        anchors.centerIn: parent
                                        width: units.gu(2.2)
                                        height: width
                                        name: "close"
                                        color: page.appTheme && page.appTheme.colors
                                               ? page.appTheme.colors.danger : "#C0392B"
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: units.gu(1)

                        Item { Layout.fillWidth: true }

                        Button {
                            text: translator.tr("general.add")
                            onClicked: addMenuPopup.visible = !addMenuPopup.visible
                        }

                        Button {
                            text: translator.tr("general.delete")
                            onClicked: page.selectedPaths = []
                        }
                    }
                }
            }

            // Expandable Add-More Grid when selection is active
            Rectangle {
                id: addMenuPopup
                Layout.fillWidth: true
                visible: false
                implicitHeight: addGrid.implicitHeight + units.gu(2)
                radius: units.gu(0.8)
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTint : "#ECEFF1"

                GridLayout {
                    id: addGrid
                    anchors {
                        fill: parent
                        margins: units.gu(1)
                    }
                    columns: 3
                    columnSpacing: units.gu(0.8)
                    rowSpacing: units.gu(0.8)

                    BigButton {
                        appTheme: page.appTheme
                        iconName: "text-x-generic-symbolic"
                        label: translator.tr("sendTab.picker.file")
                        onClicked: { addMenuPopup.visible = false; page.pickerType = "all"; pickerLoader.active = true; }
                    }
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "camera-photo-symbolic"
                        label: translator.tr("sendTab.picker.media")
                        onClicked: { addMenuPopup.visible = false; page.pickerType = "pictures"; pickerLoader.active = true; }
                    }
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "edit-paste"
                        label: translator.tr("sendTab.picker.clipboard")
                        onClicked: { addMenuPopup.visible = false; page.pasteFromClipboard(); }
                    }
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "edit"
                        label: translator.tr("sendTab.picker.text")
                        onClicked: { addMenuPopup.visible = false; messageDialogLoader.active = true; }
                    }
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "folder-symbolic"
                        label: translator.tr("sendTab.picker.folder")
                        onClicked: { addMenuPopup.visible = false; folderDialogLoader.active = true; }
                    }
                    BigButton {
                        appTheme: page.appTheme
                        iconName: "package-x-generic-symbolic"
                        label: translator.tr("sendTab.picker.app")
                        onClicked: { addMenuPopup.visible = false; appDialogLoader.active = true; }
                    }
                }
            }

            // ---------- Nearby Devices Header ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: units.gu(1)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(0.2)

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr("sendTab.nearbyDevices")
                        fontSize: "medium"
                        font.bold: true
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                    }

                    // Own addresses, like the scan button of the Android app.
                    Label {
                        Layout.fillWidth: true
                        visible: page.localIps.length > 0
                        text: page.localIps
                        fontSize: "x-small"
                        elide: Text.ElideRight
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                    }
                }

                // Scan for devices
                IconButton {
                    appTheme: page.appTheme
                    iconName: "view-refresh"
                    enabled: !discoveryController.scanning
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: {
                        discoveryController.scan_now()
                        discoveryController.poll()
                        deviceListModel.refresh()
                    }
                }

                // Send to a manually entered address
                IconButton {
                    appTheme: page.appTheme
                    iconName: "insert-link"
                    onClicked: {
                        manualSendLoader.active = true
                    }
                }

                // Show / hide the favorites
                IconButton {
                    appTheme: page.appTheme
                    iconName: page.showFavorites ? "starred" : "non-starred"
                    active: page.showFavorites
                    iconColor: page.showFavorites
                               ? (page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C")
                               : (page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368")
                    onClicked: {
                        page.showFavorites = !page.showFavorites
                    }
                }
            }

            // ---------- Favorites Section ----------
            Label {
                Layout.fillWidth: true
                Layout.topMargin: units.gu(0.5)
                visible: favoritesController.count > 0 && page.showFavorites
                text: translator.tr("dialogs.favoriteDialog.title") + " (" + favoritesController.count + ")"
                fontSize: "small"
                font.bold: true
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
            }

            Column {
                Layout.fillWidth: true
                spacing: units.gu(1)
                visible: favoritesController.count > 0 && page.showFavorites

                Repeater {
                    model: favoritesController

                    delegate: DeviceCard {
                        width: parent.width
                        appTheme: page.appTheme
                        fingerprint: model.fingerprint

                        // A favorite keeps the name it had when it was added,
                        // unless the user renamed it or the device is visible
                        // right now and reports a different name.
                        alias: {
                            var custom = favoritesController.alias_for(model.fingerprint)
                            if (custom && custom.length > 0)
                                return custom
                            var live = page.deviceInfo(model.fingerprint)
                            if (live && live.alias && live.alias.length > 0)
                                return live.alias
                            return model.alias
                        }

                        // Live information of the device, empty when it is not
                        // discovered (an offline favorite).
                        deviceModel: {
                            var live = page.deviceInfo(model.fingerprint)
                            return live ? live.deviceModel : ""
                        }
                        deviceType: {
                            var live = page.deviceInfo(model.fingerprint)
                            return live ? live.deviceType : ""
                        }
                        ip: {
                            var live = page.deviceInfo(model.fingerprint)
                            return live ? live.ip : model.ip
                        }
                        port: {
                            var live = page.deviceInfo(model.fingerprint)
                            return live ? live.port : model.port
                        }
                        https: {
                            var live = page.deviceInfo(model.fingerprint)
                            return live ? live.https : true
                        }
                        isFavorite: true
                        // Offline = not visible in the current discovery list.
                        offline: page.deviceInfo(model.fingerprint) === null

                        onTapped: page.sendToDevice(model.fingerprint)
                        onSendTextRequested: page.sendTextToDevice(model.fingerprint)
                        onDetailsRequested: {
                            var live = page.deviceInfo(model.fingerprint)
                            detailsDialog.fingerprint = model.fingerprint
                            detailsDialog.alias = live && live.alias ? live.alias : model.alias
                            detailsDialog.deviceModel = live ? live.deviceModel : ""
                            detailsDialog.deviceType = live ? live.deviceType : ""
                            detailsDialog.ip = live ? live.ip : model.ip
                            detailsDialog.port = live ? live.port : model.port
                            detailsDialog.https = live ? live.https : true
                            detailsDialog.protocolVersion = live ? live.version : ""
                            detailsDialog.isFavorite = true
                            detailsDialog.open()
                        }
                        onToggleFavorite: favoritesController.remove(model.fingerprint)
                    }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: units.gu(1)

                Repeater {
                    id: nearbyRepeater
                    model: deviceListModel

                    delegate: DeviceCard {
                        // Nearby devices that are shown in the favorites
                        // section are hidden here, exactly like Flutter. The
                        // favorites count is read so the row disappears as
                        // soon as the device is favorited (a method call
                        // alone would not update the binding).
                        visible: {
                            var favoriteCount = favoritesController.count
                            return favoriteCount === 0 || !favoritesController.is_favorite(model.fingerprint)
                        }
                        width: parent.width
                        // When hidden, collapse height so the column has no gap.
                        height: visible ? implicitHeight : 0
                        appTheme: page.appTheme
                        fingerprint: model.fingerprint
                        alias: {
                            // Read the count so the binding is re-evaluated
                            // when a favorite is added, renamed or removed.
                            var favoriteCount = favoritesController.count
                            var custom = favoritesController.alias_for(model.fingerprint)
                            return (custom && custom.length > 0) ? custom : model.alias
                        }
                        deviceModel: model.deviceModel
                        deviceType: model.deviceType
                        ip: model.ip
                        port: model.port
                        https: model.https
                        isFavorite: {
                            var favoriteCount = favoritesController.count
                            return favoritesController.is_favorite(model.fingerprint)
                        }
                        offline: false

                    onTapped: page.sendToDevice(model.fingerprint)
                    onSendTextRequested: page.sendTextToDevice(model.fingerprint)
                    onDetailsRequested: {
                        detailsDialog.fingerprint = model.fingerprint
                        detailsDialog.alias = model.alias
                        detailsDialog.deviceModel = model.deviceModel
                        detailsDialog.deviceType = model.deviceType
                        detailsDialog.ip = model.ip
                        detailsDialog.port = model.port
                        detailsDialog.https = model.https
                        detailsDialog.protocolVersion = model.version
                        detailsDialog.isFavorite = favoritesController.is_favorite(model.fingerprint)
                        detailsDialog.open()
                    }
                    onToggleFavorite: {
                        if (favoritesController.is_favorite(model.fingerprint)) {
                            favoritesController.remove(model.fingerprint)
                        } else {
                            favoritesController.add_or_update(
                                model.fingerprint, model.ip, model.port, model.alias)
                        }
                    }
                }
            }
            }

            // ---------- Empty State Placeholder ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: units.gu(2)
                implicitHeight: emptyCol.implicitHeight + units.gu(4)
                radius: units.gu(0.8)
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surface : "#ffffff"
                border.color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.divider : "#e0e0e0"
                border.width: units.dp(1)
                visible: (discoveryController.device_count === 0 && deviceListModel.count === 0) && favoritesController.count === 0

                ColumnLayout {
                    id: emptyCol
                    anchors {
                        left: parent.left; right: parent.right; top: parent.top
                        margins: units.gu(2)
                    }
                    spacing: units.gu(1.5)

                    Icon {
                        Layout.alignment: Qt.AlignHCenter
                        width: units.gu(5)
                        height: units.gu(5)
                        name: "find"
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        text: translator.tr("sendTab.help")
                        fontSize: "small"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: units.gu(1.5)

                        Button {
                            text: translator.tr("sendTab.scan")
                            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                            onClicked: {
                                discoveryController.scan_now()
                                discoveryController.poll()
                                deviceListModel.refresh()
                            }
                        }

                        Button {
                            text: translator.tr("sendTab.manualSending")
                            onClicked: {
                                manualSendLoader.active = true
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- Floating Toast Banner ----------
    Rectangle {
        id: toastBanner
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: units.gu(3)
        }
        visible: false
        z: 200
        implicitWidth: toastLabel.implicitWidth + units.gu(4)
        implicitHeight: units.gu(4.5)
        radius: units.gu(2.2)
        color: "#323232"
        opacity: 0.95

        Label {
            id: toastLabel
            anchors.centerIn: parent
            text: ""
            fontSize: "small"
            color: "#ffffff"
        }

        Timer {
            id: toastTimer
            interval: 2500
            onTriggered: toastBanner.visible = false
        }
    }

    // ---------- Text Message Dialog Loader ----------
    Loader {
        id: messageDialogLoader
        active: false
        source: "../dialogs/MessageInputDialog.qml"

        onLoaded: {
            item.appTheme = page.appTheme
            item.submitted.connect(function(message) {
                var path = sendController.create_text_file(message)
                if (path.length > 0) {
                    if (page.pendingFingerprint.length > 0) {
                        sendController.send_files(page.pendingFingerprint, JSON.stringify([path]))
                        page.pendingFingerprint = ""
                    } else if (page.pendingAddress) {
                        sendController.send_to_address(
                            page.pendingAddress.ip,
                            page.pendingAddress.port,
                            page.pendingAddress.https,
                            page.pendingAddress.ip,
                            JSON.stringify([path])
                        )
                        page.pendingAddress = null
                    } else {
                        page.selectedPaths = page.selectedPaths.concat([path])
                    }
                }
                messageDialogLoader.active = false
            })
            item.canceled.connect(function() {
                page.pendingFingerprint = ""
                page.pendingAddress = null
                messageDialogLoader.active = false
            })
            item.open()
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[SendPage] MessageInputDialog unavailable")
                page.pendingFingerprint = ""
                page.pendingAddress = null
                messageDialogLoader.active = false
            }
        }
    }

    // ---------- Folder Picker Dialog Loader ----------
    Loader {
        id: folderDialogLoader
        active: false
        source: "../dialogs/FolderPickerDialog.qml"

        onLoaded: {
            item.appTheme = page.appTheme
            // "send" mode: pick a folder whose files are sent (no writability
            // requirement, "Use this folder" label instead of the setting one).
            item.mode = "send"
            // Browse only LocalSend app-private folders. Shared files must be selected via Content Hub.
            item.currentPath = settingsController.private_receive_directory()
            item.folderSelected.connect(function(folderPath) {
                page.addFolder(folderPath)
                folderDialogLoader.active = false
            })
            item.canceled.connect(function() {
                page.pendingFingerprint = ""
                page.pendingAddress = null
                folderDialogLoader.active = false
            })
            item.open()
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[SendPage] FolderPickerDialog unavailable")
                folderDialogLoader.active = false
            }
        }
    }

    // ---------- App Picker Dialog Loader ----------
    Loader {
        id: appDialogLoader
        active: false
        source: "../dialogs/AppPickerDialog.qml"

        onLoaded: {
            item.appTheme = page.appTheme
            item.appSelected.connect(function(appPath) {
                page.addApp(appPath)
                appDialogLoader.active = false
            })
            item.pickCustomFile.connect(function() {
                appDialogLoader.active = false
                page.pickerType = "all"
                pickerLoader.active = true
            })
            item.canceled.connect(function() {
                page.pendingFingerprint = ""
                page.pendingAddress = null
                appDialogLoader.active = false
            })
            item.open()
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[SendPage] AppPickerDialog unavailable")
                appDialogLoader.active = false
            }
        }
    }

    // ---------- Manual Send Dialog Loader ----------
    Loader {
        id: manualSendLoader
        active: false
        source: "../dialogs/ManualSendDialog.qml"

        onLoaded: {
            item.appTheme = page.appTheme
            item.submitted.connect(function(ip, port, https) {
                page.sendToAddress(ip, port, https)
                manualSendLoader.active = false
            })
            item.canceled.connect(function() {
                manualSendLoader.active = false
            })
            item.open()
        }
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[SendPage] ManualSendDialog unavailable")
                manualSendLoader.active = false
            }
        }
    }

    // ---------- Device Details Dialog ----------
    LocalSendDialogs.DeviceDetailsDialog {
        id: detailsDialog
        appTheme: page.appTheme

        onToggleFavorite: {
            if (favoritesController.is_favorite(detailsDialog.fingerprint)) {
                favoritesController.remove(detailsDialog.fingerprint)
            } else {
                favoritesController.add_or_update(
                    detailsDialog.fingerprint,
                    detailsDialog.ip,
                    detailsDialog.port,
                    detailsDialog.alias
                )
            }
            detailsDialog.isFavorite =
                favoritesController.is_favorite(detailsDialog.fingerprint)
        }
    }
}
