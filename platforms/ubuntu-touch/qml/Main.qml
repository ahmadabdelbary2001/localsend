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
        Component.onCompleted: {
            console.log("[BOOT] PageStack completed", width, height)
            push(shellComponent)
            console.log("[BOOT] PageStack push requested")
            console.log("[BOOT] PageStack state", mainStack.depth, mainStack.currentPage, mainStack.currentPage ? mainStack.currentPage.visible : false)
        }
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
    // TEMPORARY render probe. Remove after diagnosis.
    Rectangle {
        id: renderProbe
        z: 10000
        x: units.gu(1)
        y: units.gu(1)
        width: units.gu(24)
        height: units.gu(6)
        color: "#D500F9"
        Text {
            anchors.centerIn: parent
            text: "QML RENDER OK"
            color: "white"
            font.pixelSize: units.gu(2)
        }
    }

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
            if (typeof favoritesController !== "undefined")  favoritesController.refresh()
            if (typeof historyController !== "undefined")    historyController.refresh()
        }
    }

    Component.onCompleted: {
        console.log("[BOOT] MainView completed", root.visible, root.width, root.height)
        if (typeof appController !== "undefined") {
            appController.initialize()
        }
    }
}
