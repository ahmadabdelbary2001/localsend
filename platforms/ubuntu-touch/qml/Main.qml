import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "shell"
import "theme" as LocalSendThemeComponents

// QQmlApplicationEngine does not create a window around a root Item.
// A real Window is required to display the MainView on the phone.
Window {
    id: appWindow
    objectName: "localsendWindow"

    visible: true
    visibility: Window.FullScreen
    title: "LocalSend"
    color: "#F6F6F6"

    width: units.gu(50)
    height: units.gu(90)

    Component.onCompleted: {
        // Initialize translator with the persisted locale setting on startup.
        translator.set_locale(settingsController.locale)
    }

    onVisibleChanged: {
    }

    // Sync translator locale whenever any setting changes (the NOTIFY signal
    // for the 'locale' property is the generic 'changed' signal, not 'localeChanged').
    Connections {
        target: settingsController
        function onChanged() {
            translator.set_locale(settingsController.locale)
        }
    }

    MainView {
        id: root
        objectName: "localsendMain"

        x: 0
        y: 0
        width: appWindow.width
        height: appWindow.height

        applicationName: "localsend.ahmadabdelbary"
        backgroundColor: localSendTheme.colors.background

        LocalSendThemeComponents.Theme {
            id: localSendTheme
            mode: settingsController.theme
            colorMode: settingsController.color_mode
            customColor: settingsController.custom_color
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

                if (typeof incomingFilesModel !== "undefined")
                    incomingFilesModel.refresh()

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
