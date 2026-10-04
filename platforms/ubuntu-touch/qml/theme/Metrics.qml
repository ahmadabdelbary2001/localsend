import QtQuick 2.15
import Lomiri.Components 1.3

QtObject {
    // Never hardcode pixels: everything derives from units.gu().
    // Flutter used: borderRadius = 5, contentPadding = (16,8) approx, page padding = 15.
    readonly property real pagePadding:   units.gu(2)          // ~15-16gu on phones
    readonly property real cardRadius:    units.gu(0.6)        // ~5dp
    readonly property real touchTarget:   units.gu(6)
    readonly property real cardMarginH:   units.gu(2)
    readonly property real cardMarginB:   units.gu(1)
    readonly property real sectionSpacing: units.gu(1.5)

    // Flutter's NavigationBar height; kept here for reference.
    readonly property real bottomNavHeight: units.gu(7)

    // Flutter: BigButton.mobileWidth / desktopWidth are logical; kept approximate.
    readonly property real bigButtonMinWidth: units.gu(18)
}