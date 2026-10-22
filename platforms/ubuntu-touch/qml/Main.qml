import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3
import Lomiri.Content 1.3

import "shell"
import "theme" as LocalSendThemeComponents

// QQmlApplicationEngine does not create a window around a root Item.
// A real Window is required to display the MainView on the phone.
Window {
    id: appWindow
    objectName: "localsendWindow"

    visible: true
    visibility: Window.AutomaticVisibility
    title: "LocalSend"
    color: localSendTheme.colors.background

    property string lastAppliedLocale: ""

    // Qt Quick only re-evaluates bindings when a property they read changes.
    // Text bindings call the translator's tr() method (methods never register a
    // dependency), so switching the locale in the language picker would leave
    // the UI in the previous language. Rebuild the page stack instead: the
    // pages are cheap to recreate and none of the runtime state lives in QML.
    property bool translationsReady: false

    // `MainView` (a StyledItem) exposes the resolved Lomiri theme; its palette
    // is updated in place when the system theme changes, so these bindings
    // re-evaluate on their own. There is no global ThemeSettings singleton in
    // Lomiri.Components (it is only a creatable per-component theme override).
    readonly property bool systemDark: root.theme.palette.normal.background.hsvValue < 0.5

    width: units.gu(50)
    height: units.gu(90)

    Component.onCompleted: {
        lastAppliedLocale = settingsController.locale
        translator.set_locale(lastAppliedLocale)
    }

    onVisibleChanged: {
    }

    // Sync translator locale whenever any setting changes (the NOTIFY signal
    // for the 'locale' property is the generic 'changed' signal, not 'localeChanged').
    Connections {
        target: settingsController
        function onChanged() {
            if (appWindow.lastAppliedLocale !== settingsController.locale) {
                appWindow.lastAppliedLocale = settingsController.locale
                translator.set_locale(appWindow.lastAppliedLocale)
            }
        }
    }

    Connections {
        target: translator
        function onLocaleChanged() {
            if (!appWindow.translationsReady) {
                // Initial application of the persisted locale.
                appWindow.translationsReady = true
                return
            }
            mainStack.clear()
            mainStack.push(shellComponent)
        }
    }

    MainView {
        id: root
        objectName: "localsendMain"

        property var pendingContentHubImports: []

        function localPathFromContentItem(item) {
            if (!item || !item.url)
                return ""
            var itemUrl = item.url
            try {
                if (typeof itemUrl.toLocalFile === "function") {
                    var localPath = itemUrl.toLocalFile()
                    if (localPath && localPath.length > 0 && localPath.charAt(0) === "/")
                        return localPath
                }
            } catch (e) {
                console.warn("[ContentHub] local URL conversion failed")
            }
            var uri = String(itemUrl)
            if (uri.indexOf("file://") !== 0)
                return ""
            var encodedPath = uri.substring(7)
            if (encodedPath.indexOf("localhost/") === 0)
                encodedPath = encodedPath.substring(9)
            if (encodedPath.length === 0 || encodedPath.charAt(0) !== "/")
                return ""
            try { return decodeURIComponent(encodedPath) } catch (e2) { return "" }
        }

        function deliverContentHubImports() {
            if (!root.pendingContentHubImports || root.pendingContentHubImports.length === 0)
                return
            var current = mainStack.currentPage
            if (current && typeof current.importFiles === "function") {
                var files = root.pendingContentHubImports.slice(0)
                root.pendingContentHubImports = []
                current.importFiles(files)
            }
        }

        x: 0
        y: 0
        width: appWindow.width
        height: appWindow.height

        applicationName: "localsend.ahmadabdelbary"
        backgroundColor: localSendTheme.colors.background

        // Right-to-left languages (Arabic, Persian, Hebrew, Urdu) mirror the
        // whole UI, matching Flutter's Directionality handling.
        LayoutMirroring.enabled: translator.rtl
        LayoutMirroring.childrenInherit: true

        LocalSendThemeComponents.Theme {
            id: localSendTheme
            mode: settingsController.theme
            colorMode: settingsController.color_mode
            customColor: settingsController.custom_color
            systemDark: appWindow.systemDark
            systemAccent: root.theme.palette.normal.activity
        }

        PageStack {
            id: mainStack
            anchors.fill: parent

            Component.onCompleted: {
                push(shellComponent)
            }
        }

        Component {
            id: shellComponent

            AppShell {
                appTheme: localSendTheme
                navigationStack: mainStack
            }
        }

        Connections {
            target: ContentHub
            function onImportRequested(transfer) {
                if (!transfer || !transfer.items || transfer.items.length === 0) {
                    console.warn("[ContentHub] import request contains no items")
                    return
                }

                var sourcePaths = []
                for (var i = 0; i < transfer.items.length; i++) {
                    var path = root.localPathFromContentItem(transfer.items[i])
                    if (path.length > 0)
                        sourcePaths.push(path)
                }
                if (sourcePaths.length === 0) {
                    console.warn("[ContentHub] no local files could be imported")
                    try { transfer.state = ContentTransfer.Aborted; transfer.finalize() } catch (e) { }
                    return
                }

                var staged = []
                try {
                    staged = JSON.parse(sendController.stage_imported_files(JSON.stringify(sourcePaths)))
                } catch (e2) {
                    console.warn("[ContentHub] staging imported files failed:", e2)
                }
                if (!staged || staged.length === 0) {
                    console.warn("[ContentHub] no imported files could be staged")
                    try { transfer.state = ContentTransfer.Aborted; transfer.finalize() } catch (e3) { }
                    return
                }

                // Copying succeeded inside the app-private data directory, so
                // the system transfer can now be collected and finalized.
                try {
                    transfer.state = ContentTransfer.Collected
                    transfer.finalize()
                } catch (e4) {
                    console.warn("[ContentHub] import finalization failed:", e4)
                }
                root.pendingContentHubImports = root.pendingContentHubImports.concat(staged)
                root.deliverContentHubImports()
            }
        }

        Connections {
            target: mainStack
            function onCurrentPageChanged() {
                root.deliverContentHubImports()
            }
        }
        // Incoming transfer dialog.
        Loader {
            id: incomingLoader
            anchors.fill: parent

            active: serverController.incoming_active
            source: active
                    ? "dialogs/IncomingTransferDialog.qml"
                    : ""

            onLoaded: {
                item.appTheme = localSendTheme
            }
        }

        // Outgoing transfer progress dialog.
        Loader {
            id: outgoingLoader
            anchors.fill: parent

            active: sendController.active
            source: active
                    ? "dialogs/SendProgressDialog.qml"
                    : ""

            onLoaded: {
                item.appTheme = localSendTheme
            }
        }

        // Received files are first staged in app-private storage. Content Hub
        // then hands completed files to the file manager so the user can save
        // them in shared storage without broad filesystem grants.
        // The component is loaded dynamically: the content hub module is not
        // available everywhere (e.g. on a desktop), and a missing module must
        // not take the whole app down.
        Loader {
            id: receiveExporterLoader
            anchors.fill: parent
            z: 5
            source: "components/ReceiveExporter.qml"

            onLoaded: {
                item.model = typeof incomingFilesModel !== "undefined" ? incomingFilesModel : null
                item.privateDir = settingsController.receive_directory()
                item.targetDir = settingsController.export_directory()
            }
        }

        Connections {
            target: settingsController
            function onChanged() {
                if (receiveExporterLoader.item) {
                    receiveExporterLoader.item.privateDir = settingsController.receive_directory()
                    receiveExporterLoader.item.targetDir = settingsController.export_directory()
                }
            }
        }

        // Single timer polls all controllers and models.
        Timer {
            interval: 250
            running: true
            repeat: true
            triggeredOnStart: true

            onTriggered: {
                if (typeof serverController !== "undefined")
                    serverController.poll()

                if (typeof discoveryController !== "undefined")
                    discoveryController.poll()

                if (typeof sendController !== "undefined")
                    sendController.poll()

                if (typeof deviceListModel !== "undefined")
                    deviceListModel.refresh()

                if (typeof localIpsModel !== "undefined")
                    localIpsModel.refresh()

                if (typeof incomingFilesModel !== "undefined")
                    incomingFilesModel.refresh()

                if (receiveExporterLoader.item)
                    receiveExporterLoader.item.check()

                if (typeof outgoingFilesModel !== "undefined")
                    outgoingFilesModel.refresh()

                if (typeof favoritesController !== "undefined")
                    favoritesController.refresh()

                if (typeof historyController !== "undefined")
                    historyController.refresh()
            }
        }

        Component.onCompleted: {
            if (typeof appController !== "undefined") {
                appController.initialize()
            }
        }
    }
}
