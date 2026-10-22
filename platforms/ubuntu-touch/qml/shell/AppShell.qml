import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../pages"

Page {
    id: shell
    property var appTheme
    property var navigationStack: null

    // The system panel (clock, battery, camera cut-out) belongs to the shell
    // and is drawn outside the app window, so the app must not reserve a
    // second, empty title bar of its own.
    //
    // `header: null` is not enough: Lomiri's MainView then shows its own
    // AppHeader for the active page (MainView.qml:
    // `visible: !(activePage.header)`), which is drawn as an empty bar because
    // the tab page has no title. Giving the page a zero-height header item
    // disables the AppHeader and lets the tabs start at the top of the window
    // (the same trick WebReceivePage uses).
    header: Item { height: 0 }

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
