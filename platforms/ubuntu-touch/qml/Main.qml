import QtQuick 2.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "shell"
import "theme"

MainView {
    id: root
    objectName: "localsendMain"
    applicationName: "localsend.ahmadabdelbary"

    // Width/height reference for phones; page contents use units.gu().
    width: units.gu(50)
    height: units.gu(90)

    Theme { id: theme }

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
        } else {
            console.warn("appController not exposed to QML")
        }
    }

    Connections {
        target: (typeof Qt !== "undefined" && Qt.application) ? Qt.application : null
        // Placeholder for lifecycle hooks; Lomiri forwards these differently.
        // See application::AppControllerHandle::on_resumed for the Rust side.
    }
}