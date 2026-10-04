import QtQuick 2.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "shell"
import "theme"

ApplicationWindow {
    id: root
    visible: true
    width: units.gu(50)
    height: units.gu(90)
    title: i18n.tr("LocalSend")

    // Theme is a singleton-like object shared across pages.
    Theme { id: theme }

    AppShell {
        id: shell
        anchors.fill: parent
        theme: theme
    }

    Component.onCompleted: {
        if (typeof appController !== "undefined") {
            appController.initialize()
        }
    }
}