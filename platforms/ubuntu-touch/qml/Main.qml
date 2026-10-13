import QtQuick 2.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "shell"
import "theme" as LocalSendThemeComponents

MainView {
    id: root
    objectName: "localsendMain"
    applicationName: "localsend.ahmadabdelbary"

    width: units.gu(50)
    height: units.gu(90)

    LocalSendThemeComponents.Theme {
        id: localSendTheme
        mode: settingsController.theme
        colorMode: settingsController.color_mode
        customColor: settingsController.custom_color
    }

    PageStack {
        anchors.fill: parent
        id: mainStack
        Component.onCompleted: push(shellComponent)
    }

    Component {
        id: shellComponent
        AppShell { appTheme: localSendTheme }
    }

    // Incoming transfer dialog (auto-shown when a session is pending)
    Loader {
        id: incomingLoader
        anchors.fill: parent
        active: serverController.incoming_active
        source: active ? "dialogs/IncomingTransferDialog.qml" : ""
        onLoaded: item.appTheme = localSendTheme
    }

    // Outgoing send progress dialog (auto-shown while a session is active)
    Loader {
        id: outgoingLoader
        anchors.fill: parent
        active: sendController.active
        source: active ? "dialogs/SendProgressDialog.qml" : ""
        onLoaded: item.appTheme = localSendTheme
    }

    // Single Timer drives all polling. Each block touches exactly one
    // controller or model, so no RefCell is borrowed twice.
    Timer {
        interval: 250
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered: {
            if (typeof serverController !== "undefined")     serverController.poll()
            if (typeof discoveryController !== "undefined")  discoveryController.poll()
            if (typeof sendController !== "undefined")       sendController.poll()
            if (typeof deviceListModel !== "undefined")      deviceListModel.refresh()
            if (typeof incomingFilesModel !== "undefined")   incomingFilesModel.refresh()
            if (typeof outgoingFilesModel !== "undefined")   outgoingFilesModel.refresh()
        }
    }

    Component.onCompleted: {
        if (typeof appController !== "undefined") {
            appController.initialize()
        }
    }
}
