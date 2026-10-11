import QtQuick 2.15
import Lomiri.Components 1.3

QtObject {
    id: theme

    property string mode: "system"
    property string colorMode: "localsend"
    property color customColor: "#009688"

    readonly property bool dark: mode === "dark"

    // ---------- colors (inline) ----------
    readonly property QtObject colors: QtObject {
        readonly property color _primary: theme.dark ? "#4DB6AC" : "#00695C"

        readonly property color background:       theme.dark ? "#111214" : "#F6F6F6"
        readonly property color surface:          (theme.colorMode === "oled" && theme.dark) ? "#000000" : (theme.dark ? "#1B1D21" : "#FFFFFF")
        readonly property color surfaceTint:      theme.dark ? "#23262B" : "#ECEFF1"
        readonly property color primary:          _primary
        readonly property color primaryText:      "#FFFFFF"
        readonly property color surfaceText:      theme.dark ? "#F2F2F2" : "#1B1D21"
        readonly property color surfaceTextMuted: theme.dark ? "#9AA0A6" : "#5F6368"
        readonly property color divider:          theme.dark ? "#2A2D31" : "#E0E0E0"
        readonly property color danger:           "#C0392B"
        readonly property color warning:          "#FF9800"
    }

    // ---------- metrics (inline) ----------
    readonly property QtObject metrics: QtObject {
        readonly property real pagePadding:       units.gu(2)
        readonly property real cardRadius:        units.gu(0.6)
        readonly property real touchTarget:       units.gu(6)
        readonly property real cardMarginH:       units.gu(2)
        readonly property real cardMarginB:       units.gu(1)
        readonly property real sectionSpacing:    units.gu(1.5)
        readonly property real bottomNavHeight:   units.gu(7)
        readonly property real bigButtonMinWidth: units.gu(18)
    }
}
