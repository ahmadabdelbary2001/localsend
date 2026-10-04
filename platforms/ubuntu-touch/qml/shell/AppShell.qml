import QtQuick 2.15
import QtQuick.Controls 2.15
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3

import "BottomNavigation.qml"
import "../pages"

Item {
    id: shell

    property var theme

    // UI-only state: current tab index. This is fine in QML.
    property int currentIndex: 0

    StackView {
        id: stack
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: nav.top
        }
        initialItem: ReceivePage { theme: shell.theme }

        onCurrentItemChanged: {
            // Keep nav in sync when pages change the stack directly.
        }
    }

    BottomNavigation {
        id: nav
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        currentIndex: shell.currentIndex

        onTabSelected: function(index) {
            shell.currentIndex = index
            switch (index) {
            case 0: stack.replace(Qt.resolvedUrl("../pages/ReceivePage.qml"), { theme: shell.theme }); break
            case 1: stack.replace(Qt.resolvedUrl("../pages/SendPage.qml"),    { theme: shell.theme }); break
            case 2: stack.replace(Qt.resolvedUrl("../pages/SettingsPage.qml"),{ theme: shell.theme }); break
            }
        }
    }
}