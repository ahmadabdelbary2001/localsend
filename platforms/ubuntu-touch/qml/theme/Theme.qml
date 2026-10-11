import QtQuick 2.15
import Lomiri.Components 1.3

QtObject {
    id: theme

    property string mode: "system"
    property string colorMode: "localsend"
    property color customColor: "#009688"

    readonly property bool dark: mode === "dark"

    // JS object literals are used instead of nested QtObject blocks:
    // inline QtObject inside a readonly property does not reliably
    // materialize on Qt 5.15, leaving colors/metrics as undefined.
    readonly property var colors: ({
        background:       dark ? "#111214" : "#F6F6F6",
        surface:          (colorMode === "oled" && dark) ? "#000000"
                            : (dark ? "#1B1D21" : "#FFFFFF"),
        surfaceTint:      dark ? "#23262B" : "#ECEFF1",
        primary:          dark ? "#4DB6AC" : "#00695C",
        primaryText:      "#FFFFFF",
        surfaceText:      dark ? "#F2F2F2" : "#1B1D21",
        surfaceTextMuted: dark ? "#9AA0A6" : "#5F6368",
        divider:          dark ? "#2A2D31" : "#E0E0E0",
        danger:           "#C0392B",
        warning:          "#FF9800"
    })

    readonly property var metrics: ({
        pagePadding:      units.gu(2),
        cardRadius:       units.gu(0.6),
        touchTarget:      units.gu(6),
        cardMarginH:      units.gu(2),
        cardMarginB:      units.gu(1),
        sectionSpacing:   units.gu(1.5),
        bottomNavHeight:  units.gu(7),
        bigButtonMinWidth: units.gu(18)
    })
}
