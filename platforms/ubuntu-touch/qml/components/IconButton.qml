// SPDX-License-Identifier: Apache-2.0
//
// Round icon button used in the page headers (scan, manual address, ...).
// The Android app uses circular icon buttons in the "nearby devices" header,
// so the Ubuntu Touch frontend uses the same shape.

import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root

    property var appTheme
    property string iconName: ""
    property color iconColor: appTheme && appTheme.colors ? appTheme.colors.surfaceText : "#1B1D21"
    property bool active: false

    signal clicked()

    implicitWidth: units.gu(4.4)
    implicitHeight: implicitWidth
    width: implicitWidth
    height: implicitHeight
    radius: width / 2

    color: mouseArea.pressed
           ? (appTheme && appTheme.colors ? appTheme.colors.background : "#ffffff")
           : (appTheme && appTheme.colors ? appTheme.colors.surfaceTint : "#ECEFF1")
    border.color: root.active
                 ? (appTheme && appTheme.colors ? appTheme.colors.primary : "#00695C")
                 : (appTheme && appTheme.colors ? appTheme.colors.divider : "#e0e0e0")
    border.width: units.dp(1)
    opacity: enabled ? 1.0 : 0.4

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    Icon {
        anchors.centerIn: parent
        width: units.gu(2.2)
        height: width
        name: root.iconName
        color: root.iconColor
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
