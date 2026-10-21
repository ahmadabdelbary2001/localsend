import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3

import "../pages"

Page {
    id: shell
    property var appTheme
    property var navigationStack: null

    // Empty header bar for the system panel.
    //
    // On Ubuntu Touch the system panel (clock, battery, camera cut-out) is
    // drawn over the top of the app window, so the app must not put anything
    // there: the bar belongs to the system and stays visible on both sides of
    // the camera. The header only reserves the space, the page content is
    // anchored below it, so no part of the app is hidden behind the panel.
    header: Rectangle {
        height: units.gu(6)
        color: shell.appTheme && shell.appTheme.colors
               ? shell.appTheme.colors.background : "#FFFFFF"
    }

    // StackLayout manages one page at a time. Each page is wrapped in
    // a plain Item with Layout.fillWidth/Height so the layout sizes
    // them, while the Page itself uses normal anchors internally.
    StackLayout {
        id: view
        anchors {
            // Below the header: the system panel area must stay free.
            top: shell.header.bottom
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
            bottomMargin: units.gu(4)
        }
        onTabSelected: function(index) {
            if (index >= 0 && index < 3) {
                homeController.change_tab(index)
            }
        }
    }
}
