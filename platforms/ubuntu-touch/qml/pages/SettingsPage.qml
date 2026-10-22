import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../components"
import "../dialogs"

Page {
    id: page

    property var appTheme

    // The tab pages live inside the shell, not in the MainView page stack.
    // No header at all: `header: null` would make Lomiri draw its default
    // (empty) page header, so a zero-height item removes it completely and
    // the content starts at the very top of the window.
    header: Item { height: 0 }
    property var navigationStack: null

    readonly property int defaultPort: 53317
    readonly property string defaultMulticastGroup: "224.0.0.167"

    readonly property var themeValues: ["system", "light", "dark"]
    readonly property var colorValues: ["system", "localsend", "oled", "yaru", "custom"]
    readonly property var deviceTypeValues: ["", "mobile", "desktop", "laptop", "tablet", "web", "headless", "server"]

    property var languages: []

    /// Effective receive folder, shown as the value of the destination row.
    property string receiveDirectory: ""

    function refreshLanguages() {
        try {
            languages = JSON.parse(translator.available_locales())
        } catch (e) {
            console.warn("[Settings] failed to parse available locales:", e)
            languages = []
        }
    }

    function languageName(code) {
        if (!code || code.length === 0)
            return translator.tr("settingsTab.general.languageOptions.system")
        for (var i = 0; i < page.languages.length; i++) {
            if (page.languages[i].code.toLowerCase() === code.toLowerCase())
                return page.languages[i].name
        }
        return code
    }

    function deviceTypeLabel(value) {
        switch (value) {
        case "mobile": return "Mobile"
        case "desktop": return "Desktop"
        case "laptop": return "Laptop"
        case "tablet": return "Tablet"
        case "web": return "Web"
        case "headless": return "Headless"
        case "server": return "Server"
        default: return translator.tr("dialogs.favoriteEditDialog.auto")
        }
    }

    readonly property var themeOptions: [
        { value: "system", label: translator.tr("settingsTab.general.brightnessOptions.system") },
        { value: "light",  label: translator.tr("settingsTab.general.brightnessOptions.light") },
        { value: "dark",   label: translator.tr("settingsTab.general.brightnessOptions.dark") }
    ]

    readonly property var colorOptions: [
        { value: "system",   label: translator.tr("settingsTab.general.colorOptions.system") },
        { value: "localsend", label: "LocalSend" },
        { value: "oled",     label: translator.tr("settingsTab.general.colorOptions.oled") },
        { value: "yaru",     label: "Yaru" },
        { value: "custom",   label: translator.tr("settingsTab.general.colorOptions.custom") }
    ]

    readonly property var deviceTypeOptions: [
        { value: "",        label: translator.tr("dialogs.favoriteEditDialog.auto") },
        { value: "mobile",  label: "Mobile" },
        { value: "desktop", label: "Desktop" },
        { value: "laptop",  label: "Laptop" },
        { value: "tablet",  label: "Tablet" },
        { value: "web",     label: "Web" },
        { value: "headless", label: "Headless" },
        { value: "server",  label: "Server" }
    ]

    function themeLabel(value) {
        for (var i = 0; i < page.themeOptions.length; i++)
            if (page.themeOptions[i].value === value)
                return page.themeOptions[i].label
        return page.themeOptions[0].label
    }

    function colorLabel(value) {
        for (var i = 0; i < page.colorOptions.length; i++)
            if (page.colorOptions[i].value === value)
                return page.colorOptions[i].label
        return page.colorOptions[0].label
    }

    function restartServerIfRunning() {
        if (serverController.running)
            serverController.restart_from_settings()
    }

    function applyQuickSave() {
        serverController.apply_auto_accept_from_settings()
    }

    // The effective receive folder is resolved by the backend (the configured
    // folder when the app may write into it, otherwise the app data folder),
    // so it can only be read through a method call and has to be refreshed
    // explicitly.
    function refreshReceiveDirectory() {
        page.receiveDirectory = settingsController.receive_directory()
    }

    Component.onCompleted: {
        refreshLanguages()
        refreshReceiveDirectory()
    }

    Connections {
        target: translator
        function onLocale_changed() { page.refreshLanguages() }
    }

    Connections {
        target: settingsController
        function onChanged() { page.refreshReceiveDirectory() }
    }

    Flickable {
        id: settingsFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + units.gu(4)
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: col
            x: units.gu(2)
            y: units.gu(2)
            width: Math.max(0, settingsFlickable.width - units.gu(4))
            spacing: units.gu(1.5)

            // Flutter renders the tab title with textTheme.titleLarge,
            // centred and not bold.
            Label {
                Layout.fillWidth: true
                text: translator.tr("settingsTab.title")
                fontSize: "x-large"
                horizontalAlignment: Text.AlignHCenter
                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
            }

            // ---------------- General ----------------
            SettingsSection {
                appTheme: page.appTheme
                title: translator.tr("settingsTab.general.title")

                SettingsButton {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.general.brightness")
                    buttonLabel: page.themeLabel(settingsController.theme)
                    onTapped: themeDialog.open()
                }

                SettingsButton {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.general.color")
                    buttonLabel: page.colorLabel(settingsController.color_mode)
                    onTapped: colorDialog.open()
                }

                // Custom accent color: quick swatches (Lomiri has no color picker).
                Flow {
                    Layout.fillWidth: true
                    spacing: units.gu(0.8)
                    visible: settingsController.color_mode === "custom"

                    Repeater {
                        model: ["#009688", "#1976D2", "#3F51B5", "#7B1FA2", "#C2185B",
                                "#D32F2F", "#F57C00", "#FBC02D", "#388E3C", "#455A64"]

                        delegate: Rectangle {
                            width: units.gu(4)
                            height: units.gu(4)
                            radius: width / 2
                            color: modelData
                            border.width: settingsController.custom_color.toLowerCase() === modelData.toLowerCase()
                                          ? units.dp(3) : units.dp(1)
                            border.color: page.appTheme && page.appTheme.colors
                                          ? page.appTheme.colors.surfaceText : "#1B1D21"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: settingsController.set_custom_color(modelData)
                            }
                        }
                    }
                }

                SettingsButton {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.general.language")
                    buttonLabel: page.languageName(settingsController.locale)
                    onTapped: languageDialog.open()
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.general.animations")
                    checked: settingsController.enable_animations
                    onToggled: settingsController.set_enable_animations(value)
                }
            }

            // ---------------- Receive ----------------
            SettingsSection {
                appTheme: page.appTheme
                title: translator.tr("settingsTab.receive.title")

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.quickSave")
                    checked: settingsController.quick_save
                    onToggled: {
                        settingsController.set_quick_save(value)
                        page.applyQuickSave()
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: settingsController.quick_save
                    text: translator.tr("dialogs.quickSaveNotice.content")
                    wrapMode: Text.Wrap
                    fontSize: "x-small"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.warning : "#C77700"
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.quickSaveFromFavorites")
                    checked: settingsController.quick_save_from_favorites
                    onToggled: {
                        settingsController.set_quick_save_from_favorites(value)
                        page.applyQuickSave()
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: settingsController.quick_save_from_favorites
                    text: translator.tr("dialogs.quickSaveFromFavoritesNotice.content")
                    wrapMode: Text.Wrap
                    fontSize: "x-small"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.warning : "#C77700"
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.requirePin")
                    checked: settingsController.receive_pin.length > 0
                    onToggled: {
                        if (value) {
                            pinDialog.open()
                        } else {
                            settingsController.set_receive_pin("")
                            page.restartServerIfRunning()
                        }
                    }
                }

                SettingsButton {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.destination")
                    // Show where files actually land, not just what was
                    // configured: the backend probes the folder and falls back
                    // to the app-private one when the app may not write there
                    // (a confined click may only write into its own folders).
                    buttonLabel: page.receiveDirectory
                    onTapped: {
                        destinationDialog.currentPath = page.receiveDirectory
                        destinationDialog.open()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: settingsController.destination.length > 0

                    Item { Layout.fillWidth: true }

                    AbstractButton {
                        // Inside a RowLayout: width/height are ignored there,
                        // which used to leave a zero-sized (unclickable) button.
                        Layout.preferredWidth: units.gu(5)
                        Layout.preferredHeight: units.gu(5)
                        Icon {
                            anchors.centerIn: parent
                            name: "edit-clear"
                            width: units.gu(2.6); height: units.gu(2.6)
                            color: page.appTheme && page.appTheme.colors
                                   ? page.appTheme.colors.danger : "#C0392B"
                        }
                        onClicked: {
                            settingsController.set_destination("")
                            page.restartServerIfRunning()
                        }
                    }
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.autoFinish")
                    checked: settingsController.auto_finish
                    onToggled: settingsController.set_auto_finish(value)
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.receive.saveToHistory")
                    checked: settingsController.save_to_history
                    onToggled: settingsController.set_save_to_history(value)
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    visible: settingsController.advanced_settings
                    label: translator.tr("settingsTab.receive.verifyChecksums")
                    checked: settingsController.verify_checksums
                    onToggled: {
                        settingsController.set_verify_checksums(value)
                        page.restartServerIfRunning()
                    }
                }
            }

            // ---------------- Send (advanced only) ----------------
            SettingsSection {
                appTheme: page.appTheme
                visible: settingsController.advanced_settings
                title: translator.tr("settingsTab.send.title")

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.send.shareViaLinkAutoAccept")
                    checked: settingsController.share_via_link_auto_accept
                    onToggled: settingsController.set_share_via_link_auto_accept(value)
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.send.createChecksums")
                    checked: settingsController.create_checksums
                    onToggled: settingsController.set_create_checksums(value)
                }
            }

            // ---------------- Network ----------------
            SettingsSection {
                appTheme: page.appTheme
                title: translator.tr("settingsTab.network.title")

                Label {
                    Layout.fillWidth: true
                    visible: serverController.running
                             && (serverController.alias !== settingsController.alias
                                 || serverController.port !== settingsController.port
                                 || serverController.https !== settingsController.https)
                    text: translator.tr("settingsTab.network.needRestart")
                    wrapMode: Text.Wrap
                    fontSize: "small"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.warning : "#C77700"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(1)

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr("settingsTab.network.server")
                              + (serverController.running ? "" : " (" + translator.tr("general.offline") + ")")
                        fontSize: "small"
                        wrapMode: Text.Wrap
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                    }

                    Row {
                        spacing: units.gu(0.5)

                        AbstractButton {
                            visible: !serverController.running
                            width: units.gu(5); height: units.gu(5)
                            Icon {
                                anchors.centerIn: parent
                                name: "media-playback-start"
                                width: units.gu(3); height: units.gu(3)
                                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.primary : "#00695C"
                            }
                            onClicked: serverController.start_from_settings()
                        }

                        AbstractButton {
                            visible: serverController.running
                            width: units.gu(5); height: units.gu(5)
                            Icon {
                                anchors.centerIn: parent
                                name: "view-refresh"
                                width: units.gu(3); height: units.gu(3)
                                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                            }
                            onClicked: serverController.restart_from_settings()
                        }

                        AbstractButton {
                            enabled: serverController.running
                            opacity: enabled ? 1 : 0.4
                            width: units.gu(5); height: units.gu(5)
                            Icon {
                                anchors.centerIn: parent
                                name: "media-playback-stop"
                                width: units.gu(3); height: units.gu(3)
                                color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.danger : "#C0392B"
                            }
                            onClicked: serverController.stop()
                        }
                    }
                }

                SettingsTextField {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.network.alias")
                    value: settingsController.alias
                    onEdited: {
                        settingsController.set_alias(editedValue)
                        // The alias is part of the register payload, so peers
                        // only see the new name after a restart.
                        page.restartServerIfRunning()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: units.gu(0.5)

                    Item { Layout.fillWidth: true }

                    AbstractButton {
                        Layout.preferredWidth: units.gu(5)
                        Layout.preferredHeight: units.gu(5)
                        Icon {
                            anchors.centerIn: parent
                            name: "view-refresh"
                            width: units.gu(2.8); height: units.gu(2.8)
                            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                        }
                        onClicked: {
                            settingsController.random_alias()
                            page.restartServerIfRunning()
                        }
                    }

                    AbstractButton {
                        Layout.preferredWidth: units.gu(5)
                        Layout.preferredHeight: units.gu(5)
                        Icon {
                            anchors.centerIn: parent
                            name: "computer-symbolic"
                            width: units.gu(2.8); height: units.gu(2.8)
                            color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                        }
                        onClicked: {
                            settingsController.use_system_name()
                            page.restartServerIfRunning()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: settingsController.advanced_settings
                    spacing: units.gu(1)

                    SettingsButton {
                        appTheme: page.appTheme
                        label: translator.tr("settingsTab.network.deviceType")
                        buttonLabel: page.deviceTypeLabel(settingsController.device_type)
                        onTapped: deviceTypeDialog.open()
                    }
                }

                SettingsTextField {
                    appTheme: page.appTheme
                    visible: settingsController.advanced_settings
                    label: translator.tr("settingsTab.network.deviceModel")
                    value: settingsController.device_model
                    onEdited: settingsController.set_device_model(editedValue)
                }

                SettingsTextField {
                    appTheme: page.appTheme
                    visible: settingsController.advanced_settings
                    label: translator.tr("settingsTab.network.port")
                    value: settingsController.port.toString()
                    inputMethodHints: Qt.ImhDigitsOnly
                    onEdited: {
                        var p = parseInt(editedValue)
                        if (!isNaN(p) && p > 0 && p < 65536)
                            settingsController.set_port(p)
                    }
                }

                SettingsTextField {
                    appTheme: page.appTheme
                    visible: settingsController.advanced_settings
                    label: translator.tr("settingsTab.network.discoveryTimeout")
                    value: settingsController.discovery_timeout.toString()
                    inputMethodHints: Qt.ImhDigitsOnly
                    onEdited: {
                        var t = parseInt(editedValue)
                        if (!isNaN(t) && t > 0 && t <= 60000)
                            settingsController.set_discovery_timeout(t)
                    }
                }

                SettingsSwitch {
                    appTheme: page.appTheme
                    visible: settingsController.advanced_settings
                    label: translator.tr("settingsTab.network.encryption")
                    checked: settingsController.https
                    onToggled: settingsController.set_https(value)
                }

                Label {
                    Layout.fillWidth: true
                    visible: settingsController.advanced_settings && !settingsController.https
                    text: translator.tr("dialogs.encryptionDisabledNotice.content")
                    wrapMode: Text.Wrap
                    fontSize: "x-small"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.warning : "#C77700"
                }

                SettingsTextField {
                    appTheme: page.appTheme
                    visible: settingsController.advanced_settings
                    label: translator.tr("settingsTab.network.multicastGroup")
                    value: settingsController.multicast_group
                    onEdited: settingsController.set_multicast_group(editedValue)
                }

                Label {
                    Layout.fillWidth: true
                    visible: settingsController.port !== page.defaultPort
                    text: translator.tr_args("settingsTab.network.portWarning",
                                             JSON.stringify({ defaultPort: page.defaultPort }))
                    wrapMode: Text.Wrap
                    fontSize: "x-small"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                }

                Label {
                    Layout.fillWidth: true
                    visible: settingsController.multicast_group.length > 0
                             && settingsController.multicast_group !== page.defaultMulticastGroup
                    text: translator.tr_args("settingsTab.network.multicastGroupWarning",
                                             JSON.stringify({ defaultMulticast: page.defaultMulticastGroup }))
                    wrapMode: Text.Wrap
                    fontSize: "x-small"
                    color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                }
            }

            // ---------------- Other ----------------
            SettingsSection {
                appTheme: page.appTheme
                title: translator.tr("settingsTab.other.title")

                SettingsButton {
                    appTheme: page.appTheme
                    label: translator.tr("aboutPage.title")
                    buttonLabel: translator.tr("general.open")
                    onTapped: {
                        if (page.navigationStack) {
                            page.navigationStack.push(
                                Qt.resolvedUrl("AboutPage.qml"),
                                {
                                    appTheme: page.appTheme,
                                    navigationStack: page.navigationStack
                                }
                            )
                        } else {
                            console.warn("[NAV] navigation stack unavailable for AboutPage")
                        }
                    }
                }

                SettingsButton {
                    appTheme: page.appTheme
                    label: translator.tr("settingsTab.other.privacyPolicy")
                    buttonLabel: translator.tr("general.open")
                    onTapped: Qt.openUrlExternally("https://localsend.org/privacy")
                }

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        Layout.fillWidth: true
                        text: translator.tr("deviceDetailsPage.info.version")
                        fontSize: "small"
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceText : "#1B1D21"
                    }

                    Label {
                        text: appController.core_version
                        fontSize: "small"
                        color: page.appTheme && page.appTheme.colors ? page.appTheme.colors.surfaceTextMuted : "#5F6368"
                    }
                }
            }

            // ---------------- Advanced toggle (bottom, like Flutter) ----------------
            SettingsSwitch {
                appTheme: page.appTheme
                label: translator.tr("settingsTab.advancedSettings")
                checked: settingsController.advanced_settings
                onToggled: settingsController.set_advanced_settings(value)
            }
        }
    }

    LanguageDialog {
        id: languageDialog
        appTheme: page.appTheme
        currentLocale: settingsController.locale
        // Main.qml mirrors settingsController.locale into the translator,
        // so only persist the setting here.
        onLocaleSelected: settingsController.set_locale(code)
    }

    OptionPickDialog {
        id: themeDialog
        appTheme: page.appTheme
        title: translator.tr("settingsTab.general.brightness")
        options: page.themeOptions
        currentValue: settingsController.theme
        onPicked: settingsController.set_theme(value)
    }

    OptionPickDialog {
        id: colorDialog
        appTheme: page.appTheme
        title: translator.tr("settingsTab.general.color")
        options: page.colorOptions
        currentValue: settingsController.color_mode
        onPicked: settingsController.set_color_mode(value)
    }

    OptionPickDialog {
        id: deviceTypeDialog
        appTheme: page.appTheme
        title: translator.tr("settingsTab.network.deviceType")
        options: page.deviceTypeOptions
        currentValue: settingsController.device_type
        onPicked: settingsController.set_device_type(value)
    }

    PinDialog {
        id: pinDialog
        appTheme: page.appTheme
        onSubmitted: {
            settingsController.set_receive_pin(pin)
            page.restartServerIfRunning()
            pinDialog.close()
        }
        onCanceled: pinDialog.close()
    }

    FolderPickerDialog {
        id: destinationDialog
        appTheme: page.appTheme
        mode: "receive"
        onFolderSelected: {
            settingsController.set_destination(path)
            page.restartServerIfRunning()
        }
    }
}
