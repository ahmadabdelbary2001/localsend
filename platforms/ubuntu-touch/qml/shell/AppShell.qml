import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../pages"

Page {
    id: shell

    property var appTheme
    property var navigationStack: null

    header: null

    // StackLayout keeps the pages in one layout but displays
    // only the page selected by currentIndex.
    StackLayout {
        id: view

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: nav.top
        }

        clip: true
        currentIndex: homeController.current_tab

        onCurrentIndexChanged: {
            if (homeController.current_tab !== currentIndex) {
                homeController.change_tab(currentIndex)
            }

            // Temporary diagnostic: verify inactive pages are hidden.
            Qt.callLater(function() {
                console.log(
                    "[UI] active tab",
                    view.currentIndex,
                    "receive visible", receivePage.visible,
                    "send visible", sendPage.visible,
                    "settings visible", settingsPage.visible,
                    "layout", view.width, view.height
                )
            })
        }

        ReceivePage {
            id: receivePage
            appTheme: shell.appTheme
        }

        SendPage {
            id: sendPage
            appTheme: shell.appTheme
        }

        SettingsPage {
            id: settingsPage
            appTheme: shell.appTheme
            navigationStack: shell.navigationStack
        }
    }

    BottomNavigation {
        id: nav

        appTheme: shell.appTheme
        currentIndex: homeController.current_tab

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        onTabSelected: function(index) {
            if (index >= 0 && index < 3) {
                homeController.change_tab(index)
            }
        }
    }
}
