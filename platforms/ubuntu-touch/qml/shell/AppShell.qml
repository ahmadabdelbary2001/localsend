import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../pages"

Page {
    id: shell
    property var appTheme
    property var navigationStack: null

    // The application header of the MainView is used as an *empty* bar.
    //
    // On Ubuntu Touch the system panel (clock, battery, camera cut-out) is
    // drawn into that area, so the app must not put a title there - the bar
    // belongs to the system window and stays visible on both sides of the
    // camera. The page content is anchored below the header, so no part of
    // the app is hidden behind it.
    header: null

    // Height of the application header, i.e. the reserved system bar area.
    readonly property real headerOffset: {
        var header = shell.__propagated ? shell.__propagated.header : null
        return header ? header.height : 0
    }

    // StackLayout manages one page at a time. Each page is wrapped in
    // a plain Item with Layout.fillWidth/Height so the layout sizes
    // them, while the Page itself uses normal anchors internally.
    StackLayout {
        id: view
        anchors {
            top: parent.top
            topMargin: shell.headerOffset
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
        }
        onTabSelected: function(index) {
            if (index >= 0 && index < 3) {
                homeController.change_tab(index)
            }
        }
    }
}
