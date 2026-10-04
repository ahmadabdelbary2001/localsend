import QtQuick 2.15
import Lomiri.Components 1.3

QtObject {
    // Never hardcode pixels. Always derive from units.gu().
    readonly property real pagePadding: units.gu(2)
    readonly property real cardRadius:  units.gu(1)
    readonly property real touchTarget: units.gu(6)
}