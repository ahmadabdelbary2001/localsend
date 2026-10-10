import QtQuick 2.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../pages"

Page {
    id: shell
    property var theme

    // Minimal header; pages own their own titles.
    header: null

    // UI-only state that mirrors home_page_controller.dart.
    // The authoritative current index lives in Rust (HomeController.current_tab).
    // The QML binding keeps the SwipeView in sync when Rust emits changes.
    SwipeView {
        id: view
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: nav.top
        }
        // Flutter uses PageView with NeverScrollableScrollPhysics.
        interactive: false
        currentIndex: homeController.current_tab

        // Pages must not react to swipe changes; only Rust drives the index.
        onCurrentIndexChanged: {
            if (homeController.current_tab !== currentIndex) {
                homeController.change_tab(currentIndex)
            }
        }

        ReceivePage  { theme: shell.theme }
        SendPage     { theme: shell.theme }
        SettingsPage { theme: shell.theme }
    }

    BottomNavigation {
        id: nav
        theme: shell.theme
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        currentIndex: homeController.current_tab
        onTabSelected: function(index) { homeController.change_tab(index) }
    }
}