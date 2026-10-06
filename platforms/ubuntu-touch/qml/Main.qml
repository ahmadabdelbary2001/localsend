import QtQuick 2.15
import Lomiri.Components 1.3

import "shell"
import "theme"

MainView {
    id: root
    objectName: "localsendMain"
    applicationName: "localsend.ahmadabdelbary"

    width: units.gu(50)
    height: units.gu(90)

    Theme {
        id: theme
        mode: settingsController.theme
        colorMode: settingsController.colorMode
        customColor: settingsController.customColor
    }

    PageStack {
        id: mainStack
        Component.onCompleted: push(shellComponent)
    }

    Component {
        id: shellComponent
        AppShell { theme: theme }
    }

    Component.onCompleted: {
        if (typeof appController !== "undefined") {
            appController.initialize()
        }
        // Server startup now happens in Rust before QML loads.
        // The timer below only polls for events.
    }

    // Drains server events on the Qt thread.
    Timer {
        interval: 200
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (typeof serverController !== "undefined") {
                serverController.poll()
            }
            if (typeof discoveryController !== "undefined") {
                discoveryController.poll()
            }
        }
    }
}