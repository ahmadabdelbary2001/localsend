import QtQuick 2.15

QtObject {
    id: colors

    property bool   dark: false
    property string colorMode: "localsend"
    property color  customColor: "#009688"

    // Lightweight seed -> palette derivation.
    // TODO: replace with proper Material-3 generation.
    function _mix(a, b, t) {
        return Qt.rgba(
            a.r * (1 - t) + b.r * t,
            a.g * (1 - t) + b.g * t,
            a.b * (1 - t) + b.b * t,
            1
        )
    }

    readonly property color _seed: colorMode === "custom" ? customColor : "#009688"
    readonly property color _primaryDark:  _mix(_seed, "#000000", 0.20)
    readonly property color _primaryLight: _mix(_seed, "#FFFFFF", 0.30)

    readonly property color background:     (colorMode === "oled" && dark) ? "#000000"
                                            : (dark ? "#111214" : "#F6F6F6")
    readonly property color surface:        (colorMode === "oled" && dark) ? "#000000"
                                            : (dark ? "#1B1D21" : "#FFFFFF")
    readonly property color surfaceTint:    dark ? "#23262B" : "#ECEFF1"
    readonly property color primary:        dark ? _primaryLight : _primaryDark
    readonly property color onPrimary:      "#FFFFFF"
    readonly property color onSurface:      dark ? "#F2F2F2" : "#1B1D21"
    readonly property color onSurfaceMuted: dark ? "#9AA0A6" : "#5F6368"
    readonly property color divider:        dark ? "#2A2D31" : "#E0E0E0"
    readonly property color danger:         "#C0392B"
    readonly property color warning:        "#FF9800"
}