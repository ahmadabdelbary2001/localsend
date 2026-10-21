import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../pages"

Page {
    id: shell
    property var appTheme
    property var navigationStack: null

    // Keep the Ubuntu Touch system panel visible without reserving a second,
    // empty title/header bar inside the app.
    header: null


    // StackLayout manages one page at a time. Each page is wrapped in
    // a plain Item with Layout.fillWidth/Height so the layout sizes
    // them, while the Page itself uses normal anchors internally.
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
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ReceivePage {
                id: receivePage
                anchors.fill: parent
                appTheme: shell.appTheme
                navigationStack: shell.navigationStack
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            SendPage {
                id: sendPage
                anchors.fill: parent
                appTheme: shell.appTheme
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            SettingsPage {
                id: settingsPage
                anchors.fill: parent
                appTheme: shell.appTheme
                navigationStack: shell.navigationStack
            }
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
            // The shell draws its own bar over the bottom of the app window
            // (the gesture area). The navigation has to stay above it,
            // otherwise it is cut off.
            bottomMargin: 0
        }
        onTabSelected: function(index) {
            if (index >= 0 && index < 3) {
                homeController.change_tab(index)
            }
        }
    }
}
