import QtQuick 2.15
import QtQuick.Layouts 1.15
import Lomiri.Components 1.3

import "../components"
import "../dialogs" as LocalSendDialogs

Page {
    id: page
    header: Item { } // hides MainView's deprecated app header
    property var appTheme
    property string pendingFingerprint: ""
    property var pendingAddress: null // { ip: "", port: 53317, https: true }
    property var selectedPaths: []
    property string pickerType: "all" // "all" | "pictures"
    property string lastError: ""

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

    function _formatSize(bytes) {
        var b = bytes || 0
        if (b < 1024) return b + " B"
        if (b < 1024 * 1024) return (b / 1024).toFixed(1) + " KB"
        if (b < 1024 * 1024 * 1024) return (b / 1024 / 1024).toFixed(1) + " MB"
        return (b / 1024 / 1024 / 1024).toFixed(2) + " GB"
    }

    function _namesLabel() {
        var names = page.selection.names || []
        if (names.length === 0) return ""
        var shown = names.slice(0, 3).join(", ")
        return names.length > 3 ? shown + " …" : shown
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
                var pickedPaths = paths || []

                if (pickedPaths.length > 0) {
                    page.selectedPaths = page.selectedPaths.concat(pickedPaths)
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
                        iconName: "stock_application"
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

                    Label {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: page._namesLabel()
                        fontSize: "x-small"
                        elide: Text.ElideRight
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
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
                        iconName: "stock_application"
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
                }

                // Send by IP Button
                Button {
                    text: translator.tr("dialogs.addressInput.ip")
                    onClicked: {
                        manualSendLoader.active = true
                    }
                }

                // Refresh / Scan Button
                Button {
                    text: translator.tr("sendTab.scan")
                    enabled: !discoveryController.scanning
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTint : "#ECEFF1"
                    onClicked: {
                        discoveryController.scan_now()
                        discoveryController.poll()
                        deviceListModel.refresh()
                    }
                }
            }

            // ---------- Favorites Section ----------
            Label {
                Layout.fillWidth: true
                Layout.topMargin: units.gu(0.5)
                visible: favoritesController.count > 0
                text: translator.tr("dialogs.favoriteDialog.title") + " (" + favoritesController.count + ")"
                fontSize: "small"
                font.bold: true
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
            }

            Column {
                Layout.fillWidth: true
                spacing: units.gu(1)
                visible: favoritesController.count > 0

                Repeater {
                    model: favoritesController

                    delegate: DeviceCard {
                        width: parent.width
                    appTheme: page.appTheme
                    fingerprint: model.fingerprint
                    alias: model.alias
                    // Try to get live info if device is also discovered nearby (role2=deviceModel)
                    deviceModel: {
                        for (var i = 0; i < deviceListModel.count; i++) {
                            var idx = deviceListModel.index(i, 0)
                            if (deviceListModel.data(idx, 0) === model.fingerprint)
                                return deviceListModel.data(idx, 2)
                        }
                        return ""
                    }
                    deviceType: {
                        for (var i = 0; i < deviceListModel.count; i++) {
                            var idx = deviceListModel.index(i, 0)
                            if (deviceListModel.data(idx, 0) === model.fingerprint)
                                return deviceListModel.data(idx, 3)
                        }
                        return ""
                    }
                    ip: model.ip
                    port: model.port
                    https: {
                        // role6=https; fallback true for saved favorites
                        for (var i = 0; i < deviceListModel.count; i++) {
                            var idx = deviceListModel.index(i, 0)
                            if (deviceListModel.data(idx, 0) === model.fingerprint)
                                return deviceListModel.data(idx, 6)
                        }
                        return true
                    }
                    isFavorite: true
                    // offline = not found in current discovery snapshot
                    offline: (function() {
                        for (var i = 0; i < deviceListModel.count; i++) {
                            var idx = deviceListModel.index(i, 0)
                            if (deviceListModel.data(idx, 0) === model.fingerprint)
                                return false
                        }
                        return true
                    })()

                    onTapped: page.sendToDevice(model.fingerprint)
                    onSendTextRequested: page.sendTextToDevice(model.fingerprint)
                    onDetailsRequested: {
                        detailsDialog.fingerprint = model.fingerprint
                        detailsDialog.alias = model.alias
                        detailsDialog.deviceModel = ""
                        detailsDialog.deviceType = ""
                        detailsDialog.ip = model.ip
                        detailsDialog.port = model.port
                        detailsDialog.https = true
                        detailsDialog.protocolVersion = ""
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
                        // Nearby devices already shown under Favorites are hidden
                        // here, exactly like Flutter.
                        visible: !favoritesController.is_favorite(model.fingerprint)
                        width: parent.width
                        // When hidden, collapse height so the column has no gap.
                        height: visible ? implicitHeight : 0
                    appTheme: page.appTheme
                    fingerprint: model.fingerprint
                    alias: {
                        var custom = favoritesController.alias_for(model.fingerprint)
                        return (custom && custom.length > 0) ? custom : model.alias
                    }
                    deviceModel: model.deviceModel
                    deviceType: model.deviceType
                    ip: model.ip
                    port: model.port
                    https: model.https
                    isFavorite: favoritesController.is_favorite(model.fingerprint)
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
