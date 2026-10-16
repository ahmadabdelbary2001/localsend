import QtQuick 2.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../pages"

Page {
    id: shell
    property var appTheme

    header: null

    Component.onCompleted: {
        console.log("[BOOT] AppShell completed", shell.width, shell.height)
        console.log("[UI] AppShell geometry", "shell", shell.width, shell.height, "view", view.width, view.height, "nav", nav.width, nav.height, "implicitHeight", nav.implicitHeight, "tab", view.currentIndex)
    }

    SwipeView {
        id: view
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: nav.top
        }
        interactive: false
        currentIndex: homeController.current_tab

        onCurrentIndexChanged: {
            if (homeController.current_tab !== currentIndex) {
                homeController.change_tab(currentIndex)
            }
        }

        ReceivePage  { appTheme: shell.appTheme }
        SendPage     { appTheme: shell.appTheme }
        SettingsPage { appTheme: shell.appTheme }
    }

    BottomNavigation {
        id: nav
        appTheme: shell.appTheme
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        currentIndex: homeController.current_tab
        onTabSelected: function(index) {
            console.log("[NAV] tab selected", index)
            homeController.change_tab(index)
        }
    }
}
